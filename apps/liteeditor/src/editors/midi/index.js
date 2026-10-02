// MIDI 编曲编辑器
import { h, fill, toast, clamp, debounce, dialog } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import * as store from '../../core/store.js'
import { stemOf } from '../../core/files.js'
import { Editor } from '../base.js'
import { parseMIDI, writeMIDI, emptySong, tickToSec, secToTick, songEndTick, lastNoteTick, forEachBar, tickToBBT, isDrum, DRUM_CH } from './smf.js'
import { buildSample, SAMPLES } from './samples.js'
import { AudioEngine, renderWAV } from './audio.js'
import { installRoll } from './roll.js'
import { installTracks } from './tracks.js'
import { installOps } from './ops.js'
import { installUI } from './ui.js'

export { SAMPLES }

export class MidiEditor extends Editor {
    static kind = 'midi'

    constructor(file, app) {
        super(file, app)
        const pref = store.getPref('midi', { snap: 1 / 16, ghosts: true, volume: 0.8, metronome: false, follow: true, arrH: 176 })
        this.pref = pref
        this.song = emptySong()
        this.trackId = this.song.tracks[0].id
        this.sel = new Set()
        this.tool = 'select'
        this.snap = pref.snap
        this.ghosts = pref.ghosts
        this.metronome = pref.metronome
        this.follow = pref.follow
        this.noteLen = 0
        this.newVel = 100
        this.cursor = 0
        this.playTick = 0
        this.playing = false
        this.loop = { on: false, start: 0, end: 0 }
        this.view = { zx: 0.12, sx: 0, rowH: 14, sy: 0 }
        this.engine = new AudioEngine(pref.volume)
        this.audioDirty = true
        this.readPalette()
        this.buildLayout()
        this.listen(window, 'themechange', () => requestAnimationFrame(() => { this.readPalette(); this.drawAll() }))
        this.hotReload = debounce(() => this.reloadWhilePlaying(), 220)
    }

    get track() { return this.song.tracks.find(t => t.id === this.trackId) ?? this.song.tracks[0] }

    savePref() {
        Object.assign(this.pref, { snap: this.snap, ghosts: this.ghosts, volume: this.engine.volume, metronome: this.metronome, follow: this.follow })
        store.setPref('midi', this.pref)
    }

    // ---------- 布局 ----------
    buildLayout() {
        this.stage.classList.add('mi-stage')
        const arr = this.buildArrange()
        arr.style.height = this.pref.arrH + 'px'
        const split = h('div.mi-split', { title: '拖动调整高度' })
        split.addEventListener('pointerdown', e => {
            split.setPointerCapture(e.pointerId)
            const y0 = e.clientY, h0 = arr.offsetHeight
            const move = ev => { arr.style.height = clamp(h0 + ev.clientY - y0, 84, this.stage.clientHeight - 200) + 'px' }
            const up = () => { split.removeEventListener('pointermove', move); this.pref.arrH = arr.offsetHeight; this.savePref() }
            split.addEventListener('pointermove', move)
            split.addEventListener('pointerup', up, { once: true })
        })
        this.stage.append(arr, split, this.buildRoll())
        this.buildLeft()
        this.buildToolbar()
        this.buildPanels()
    }

    // 从主题变量推导画布配色（钢琴卷帘跟随主题）
    readPalette() {
        const probe = h('div', { style: { display: 'none' } })
        document.body.append(probe)
        const get = v => { probe.style.color = `var(${v})`; return getComputedStyle(probe).color }
        const bg = rgb(get('--bg')), sf = rgb(get('--surface')), tx = rgb(get('--text')), ac = rgb(get('--accent'))
        probe.remove()
        const dark = document.documentElement.dataset.scheme !== 'light'
        const mix = (a, b, k) => a.map((v, i) => Math.round(v + (b[i] - v) * k))
        const css = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`
        this.pal = {
            dark,
            rollWhite: css(dark ? mix(bg, sf, 0.55) : mix(sf, bg, 0.15)),
            rollBlack: css(dark ? mix(bg, [0, 0, 0], 0.18) : mix(sf, bg, 0.75)),
            hoverRow: css(ac, dark ? 0.1 : 0.08),
            lineBar: css(tx, dark ? 0.26 : 0.24),
            lineBeat: css(tx, dark ? 0.11 : 0.11),
            lineSub: css(tx, dark ? 0.05 : 0.05),
            keyWhite: dark ? '#e9ebf1' : '#ffffff',
            keyBlack: dark ? '#1d2030' : '#2b2f3a',
            keyLine: css(tx, dark ? 0.2 : 0.18),
            keyInk: '#4b5162',
            keyInkDim: '#9aa0ad',
            keyDrumEmpty: dark ? '#cfd3dc' : '#eef0f4',
            rulerBg: css(dark ? mix(sf, tx, 0.04) : mix(sf, bg, 0.5)),
            rulerTick: css(tx, 0.3),
            rulerInk: css(tx, 0.7),
            velBg: css(dark ? mix(bg, sf, 0.3) : mix(sf, bg, 0.3)),
            ovBg: css(dark ? mix(bg, sf, 0.35) : sf),
            ovActive: css(ac, dark ? 0.1 : 0.07),
            accent: css(ac), accentSoft: css(ac, 0.16),
            selStroke: dark ? '#ffffff' : '#111827',
            cursor: css(ac),
            playhead: '#f43f5e',
            loopFill: css(ac, 0.07), loopFillOff: css(tx, 0.03),
            loopBar: css(ac, 0.85), loopBarOff: css(tx, 0.25),
        }
    }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        this.song = opts.sample ? buildSample(opts.sample) : emptySong()
        if (opts.sample && !this.path) this.name = (SAMPLES[opts.sample]?.name ?? this.name) + '.mid'
        this.afterLoad()
    }
    async load(bytes) {
        this.song = parseMIDI(bytes)
        this.afterLoad()
        const n = this.song.tracks.reduce((s, t) => s + t.notes.length, 0)
        if (!n) toast('文件中没有音符', 'warn')
    }
    afterLoad() {
        this.trackId = (this.song.tracks.find(t => t.notes.length && !isDrum(t)) ?? this.song.tracks[0]).id
        this.sel = new Set()
        this.cursor = 0
        this.audioDirty = true
        // 水平缩放：约 8 小节铺满
        requestAnimationFrame(() => {
            const w = this.grid.w > 10 ? this.grid.w : 900
            const bars = clamp(Math.ceil(lastNoteTick(this.song) / (this.song.ppq * 4)), 4, 16)
            this.view.zx = clamp(w / (bars * this.song.ppq * 4 + this.song.ppq), 0.01, 1)
            this.view.sx = 0
            this.centerOnTrack()
            this.drawAll()
        })
        this.drawAll()
    }

    snapshot() { return { song: structuredClone(this.song), trackId: this.trackId, sel: [...this.sel] } }
    restore(s) {
        this.song = structuredClone(s.song)
        this.trackId = this.song.tracks.some(t => t.id === s.trackId) ? s.trackId : this.song.tracks[0].id
        this.sel = new Set(s.sel)
        this.afterEdit()
    }

    formats() {
        return [
            { ext: 'mid', name: 'MIDI 文件', write: () => writeMIDI(this.song, { title: stemOf(this.name) }) },
            { ext: 'midi', name: 'MIDI 文件', write: () => writeMIDI(this.song, { title: stemOf(this.name) }) },
        ]
    }
    exports() {
        return [{ ext: 'wav', name: 'WAV 音频', write: () => this.exportWAV() }]
    }
    fileItems() {
        return ['-', { label: '导出 WAV 音频…', icon: 'audio-lines', run: () => this.exportAs('wav') }]
    }

    onShow() {
        super.onShow()
        requestAnimationFrame(() => this.drawAll())
    }
    onHide() {
        super.onHide()
        if (this.playing) this.pause()
    }
    destroy() {
        cancelAnimationFrame(this.playRAF)
        this.midiAccess && (this.midiAccess.onstatechange = null)
        for (const i of this.midiInputs ?? []) i.onmidimessage = null
        this.engine.destroy()
        super.destroy()
    }

    // ---------- 刷新 ----------
    drawAll() {
        if (!this.song) return
        this.renderTracks()
        this.drawRoll()
        this.drawOverview()
        this.refreshPanels()
        this.updateTransportUI()
        this.updateStatus()
    }
    // 模型改变后：重绘并标记需要重新载入音序器
    afterEdit(light = false) {
        this.audioDirty = true
        if (this.playing) this.hotReload()
        if (light) { this.drawSoon(); this.drawLanes(); return }
        this.drawAll()
    }
    afterSel() {
        this.drawSoon()
        this.refreshPanels()
        this.updateStatus()
    }
    endTick() { return songEndTick(this.song) }

    // ---------- 播放 ----------
    // 生成用于播放的 SMF：静音 / 独奏、循环标记、节拍器
    playBytes() {
        const anySolo = this.song.tracks.some(t => t.solo)
        const silent = new Set(this.song.tracks.filter(t => t.mute || (anySolo && !t.solo)))
        const extraMarkers = []
        if (this.loop.on && this.loop.end > this.loop.start) extraMarkers.push({ tick: this.loop.start, text: 'loopStart' }, { tick: this.loop.end, text: 'loopEnd' })
        const extraTracks = []
        const end = Math.max(lastNoteTick(this.song), this.loop.on ? this.loop.end : 0, this.cursor + this.song.ppq)
        if (this.metronome) {
            const drum = this.song.tracks.find(isDrum)
            const m = { name: '节拍器', channel: DRUM_CH, program: drum?.program ?? 0, volume: drum?.volume ?? 100, pan: 64, notes: [], cc: [], pitchBend: [] }
            forEachBar(this.song, 0, end + 1, b => {
                for (let i = 0; i < b.num; i++) m.notes.push({ tick: b.tick + i * b.beat, dur: this.song.ppq / 8, pitch: i ? 77 : 76, vel: i ? 80 : 110 })
            })
            extraTracks.push(m)
        }
        // 保证乐曲至少持续到末尾 / 循环终点（空乐曲也能播放节拍器 / 定位）
        const padTo = Math.max(end, this.loop.on ? this.loop.end : 0, lastNoteTick(this.song) ? 0 : this.song.ppq * 16)
        return writeMIDI(this.song, { silent, extraMarkers, extraTracks, padTo })
    }

    async ensureLoaded() {
        await this.engine.resume()
        if (this.audioDirty) {
            this.audioDirty = false
            this.playSong = structuredClone({ ppq: this.song.ppq, tempos: this.song.tempos })
            await this.engine.load(this.playBytes())
        }
    }

    async play() {
        if (this.playing || this.starting) return
        this.starting = true
        try {
            this.statusMsg = this.engine.started ? null : '正在加载音色库…'
            if (this.statusMsg) this.updateStatus()
            await this.ensureLoaded()
            let from = this.cursor
            if (this.loop.on && (from < this.loop.start || from >= this.loop.end)) from = this.loop.start
            if (from >= lastNoteTick(this.song) && lastNoteTick(this.song) > 0 && !this.loop.on) from = 0
            this.playStart = from
            await this.engine.play(tickToSec(this.song, from), this.loop.on)
            this.playing = true
            this.playTick = from
            this.tickLoop()
        } catch (e) {
            console.error(e)
            toast('无法播放：' + e.message, 'error', 5000)
        } finally {
            this.starting = false
            this.statusMsg = null
            this.updateTransportUI()
            this.updateStatus()
        }
    }
    pause() {
        if (!this.playing) return
        this.engine.pause()
        this.playing = false
        cancelAnimationFrame(this.playRAF)
        this.cursor = Math.max(0, Math.round(this.playTick))
        this.updateTransportUI()
        this.drawRoll()
        this.drawOverview()
        this.updateStatus()
    }
    stop() {
        const was = this.playing
        this.pause()
        this.engine.synth?.stopAll(true)
        this.cursor = was ? this.playStart ?? 0 : 0
        this.drawAll()
    }
    togglePlay() { this.playing ? this.pause() : this.play() }

    seekTick(t) {
        t = Math.max(0, Math.round(t))
        this.cursor = t
        if (this.playing) {
            this.playTick = t
            this.playStart = t
            this.engine.seek(tickToSec(this.song, t))
        }
        this.drawRoll()
        this.drawOverview()
        this.updateStatus()
    }
    async reloadWhilePlaying() {
        if (!this.playing) return
        const t = this.playTick
        try {
            this.audioDirty = false
            await this.engine.load(this.playBytes())
            if (!this.playing) return
            await this.engine.play(tickToSec(this.song, t), this.loop.on)
        } catch (e) { console.warn(e) }
    }
    onLoopChanged() {
        this.audioDirty = true
        if (this.playing) this.hotReload()
    }

    tickLoop() {
        cancelAnimationFrame(this.playRAF)
        const step = () => {
            if (!this.playing) return
            const sec = this.engine.time
            this.playTick = secToTick(this.song, sec)
            if (this.engine.finished) {
                this.playing = false
                this.cursor = 0
                this.engine.pause()
                this.drawAll()
                return
            }
            // 跟随播放头翻页
            if (this.follow && !this.drag) {
                const x = this.xOf(this.playTick)
                if (x > this.grid.w - 30 || x < 0) { this.view.sx = this.playTick * this.view.zx - 40; this.clampView() }
            }
            this.drawRoll()
            this.drawOverview()
            this.updatePosition()
            this.playRAF = requestAnimationFrame(step)
        }
        this.playRAF = requestAnimationFrame(step)
    }

    // 试听一个音符（用该轨道的音色）
    previewNote(n, t = this.track) {
        if (!t || this.playing) return
        this.engineNoteOn(t, n.pitch, n.vel ?? 100, Math.min(600, Math.max(160, tickToSec(this.song, n.dur ?? 240) * 1000)))
    }
    engineNoteOn(t, pitch, vel, ms = 0) {
        if (!t) return
        const go = () => {
            if (ms) this.engine.preview(t.channel, pitch, vel, { program: t.program, volume: t.volume, ms })
            else this.engine.noteOn(t.channel, pitch, vel, this.playing ? null : t.program)
        }
        if (this.engine.started) go()
        else this.engine.resume().then(go).catch(e => toast('音频初始化失败：' + e.message, 'error'))
    }

    // ---------- 导出 WAV ----------
    async exportWAV() {
        if (!lastNoteTick(this.song)) throw new Error('乐曲中没有音符')
        this.busy = true
        if (this.playing) this.pause()
        const bar = h('div.mi-progress-bar')
        const label = h('div.mi-progress-label', '正在准备…')
        let close = null
        dialog({ title: '导出 WAV 音频', body: h('div.mi-progress', label, h('div.mi-progress-track', bar)), actions: [], onOpen: (_m, c) => { close = c } })
        try {
            const anySolo = this.song.tracks.some(t => t.solo)
            const silent = new Set(this.song.tracks.filter(t => t.mute || (anySolo && !t.solo)))
            const r = await renderWAV(writeMIDI(this.song, { silent }), {
                onProgress: p => { bar.style.width = (p * 100).toFixed(1) + '%'; label.textContent = `正在渲染… ${Math.round(p * 100)}%` },
            })
            this.lastRender = { peak: r.peak, duration: r.duration, bytes: r.wav.length }
            return r.wav
        } finally {
            this.busy = false
            setTimeout(() => close?.(null), 50)
        }
    }

    // ---------- 状态栏 ----------
    updatePosition() {
        if (!this.posEl) return
        const t = this.playing ? this.playTick : this.cursor
        const b = tickToBBT(this.song, Math.round(t))
        const s = tickToSec(this.song, t)
        this.posEl.textContent = `${b.bar}.${b.beat}.${String(Math.floor(b.sub / this.song.ppq * 4) + 1)}`
        this.timeEl.textContent = fmtSec(s)
        if (this.stPos) this.stPos.textContent = `${b.bar}:${b.beat}`
    }
    updateStatus() {
        if (!this.song) return
        const notes = this.song.tracks.reduce((s, t) => s + t.notes.length, 0)
        const ts = this.song.timeSig[0]
        const dur = tickToSec(this.song, lastNoteTick(this.song))
        this.stPos = h('span')
        this.statusItems(
            h('span.st-item', icon('list-music', 13), `${this.song.tracks.length} 条轨道`),
            h('span.st-item', icon('music', 13), `${notes} 个音符`),
            this.sel.size ? h('span.st-item', icon('mouse-pointer-2', 13), `已选 ${this.sel.size}`) : null,
            h('span.st-item', icon('gauge', 13), `${fmtBpm(this.song.tempos[0].bpm)} BPM${this.song.tempos.length > 1 ? '（变速）' : ''}`),
            h('span.st-item', `${ts.num}/${ts.den}`),
            h('span.st-item', icon('map-pin', 13), '位置 ', this.stPos),
            h('span.st-item', icon('timer', 13), '时长 ', fmtSec(dur)),
            this.statusMsg ? h('span.st-item', icon('loader', 13), this.statusMsg) : null,
            h('span.st-flex'),
            h('button', { title: '缩小 (Ctrl 滚轮)', onclick: () => this.zoomX(1 / 1.3) }, icon('zoom-out', 13)),
            h('button', { title: '适合窗口', onclick: () => this.fitAll() }, icon('maximize', 13)),
            h('button', { title: '放大 (Ctrl 滚轮)', onclick: () => this.zoomX(1.3) }, icon('zoom-in', 13)))
        this.updatePosition()
    }
    fitAll() {
        const end = Math.max(lastNoteTick(this.song), this.song.ppq * 16)
        this.view.zx = clamp((this.grid.w - 20) / end, 0.004, 2)
        this.view.sx = 0
        this.clampView()
        this.drawRoll()
        this.drawOverview()
    }
}

const rgb = s => (s.match(/[\d.]+/g) ?? [0, 0, 0]).slice(0, 3).map(Number)
const fmtBpm = b => String(Math.round(b * 100) / 100)
export function fmtSec(s) {
    const m = Math.floor(s / 60), r = s - m * 60
    return `${m}:${r.toFixed(1).padStart(4, '0')}`
}

installRoll(MidiEditor)
installTracks(MidiEditor)
installOps(MidiEditor)
installUI(MidiEditor)
