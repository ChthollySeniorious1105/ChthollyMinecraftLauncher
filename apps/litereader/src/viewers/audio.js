import { WorkletSynthesizer, Sequencer } from 'spessasynth_lib'
import { Viewer, sidebarTabs } from './base.js'
import { h, fill, btn, setIcon, formatTime, formatBytes, clamp, togglePopover, segmented, menu, toast } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { siblings, MIDI_EXTS, stemOf, Source, dirName } from '../core/files.js'
import { decodeText } from '../core/encoding.js'
import * as store from '../core/store.js'

const VENDOR = new URL('./vendor/', location.href).href
const SOUNDFONT = new URL('./soundfonts/GeneralUserGS.sf3', location.href).href

// ---------- 全局音频引擎（所有音乐标签页共享，保证同一时刻只有一个声音） ----------
let ctx = null, masterGain = null, analyser = null
function audioCtx() {
    if (!ctx) {
        ctx = new AudioContext({ latencyHint: 'playback' })
        masterGain = ctx.createGain()
        analyser = ctx.createAnalyser()
        analyser.fftSize = 2048
        analyser.smoothingTimeConstant = 0.82
        masterGain.connect(analyser)
        analyser.connect(ctx.destination)
        masterGain.gain.value = store.get('volume')
    }
    return ctx
}

let midiEngine = null
async function getMidiEngine() {
    if (midiEngine) return midiEngine
    midiEngine = (async () => {
        const c = audioCtx()
        await c.audioWorklet.addModule(VENDOR + 'spessasynth/spessasynth_processor.min.js')
        const synth = new WorkletSynthesizer(c)
        synth.connect(masterGain)
        const sf = await (await fetch(SOUNDFONT)).arrayBuffer()
        await synth.soundBankManager.addSoundBank(sf, 'main')
        await synth.isReady
        const seq = new Sequencer(synth, { skipToFirstNoteOn: true })
        seq.loopCount = 0
        return { synth, seq }
    })()
    midiEngine.catch(() => { midiEngine = null })
    return midiEngine
}

let activePlayer = null
const claim = p => {
    if (activePlayer && activePlayer !== p) activePlayer.pause()
    activePlayer = p
}

// 解析 LRC 歌词
function parseLRC(text) {
    const out = []
    let offset = 0
    for (const line of text.split(/\r?\n/)) {
        const off = /^\[offset:\s*(-?\d+)\]/i.exec(line)
        if (off) { offset = Number(off[1]) / 1000; continue }
        const tags = [...line.matchAll(/\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g)]
        if (!tags.length) continue
        const content = line.replace(/\[[^\]]*\]/g, '').trim()
        for (const t of tags) out.push({ t: Number(t[1]) * 60 + Number(t[2].replace(':', '.')) - offset, text: content })
    }
    return out.sort((a, b) => a.t - b.t)
}

export class AudioViewer extends Viewer {
    playlist = []
    index = 0
    lyrics = []

    async mount() {
        this.el.classList.add('audio-viewer')
        this.addTitle()
        this.tool('list-music', '播放列表', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)
        this.vizBtn = this.tool('audio-lines', '可视化效果', e => togglePopover(e.currentTarget, () => menu([
            ['bars', '频谱柱状'], ['mirror', '镜像频谱'], ['wave', '波形'], ['circle', '环形光谱'], ['particles', '粒子星空'], ['off', '关闭'],
        ].map(([v, label]) => ({ label, checked: store.get('visualizer') === v, onclick: () => store.set('visualizer', v) })))))
        this.tool('folder-open', '打开更多音乐', () => this.app.openDialog('audio'))

        this.audio = new Audio()
        this.audio.crossOrigin = 'anonymous'
        this.audio.preload = 'auto'

        this.buildUI()
        this.bindAudio()

        this.playlist = await siblings(this.source, 'audio')
        this.index = Math.max(0, this.playlist.findIndex(s => s.path === this.source.path))
        if (!this.source.path) { this.playlist = [this.source]; this.index = 0 }
        this.renderPlaylist()
        await this.load(this.index, true)
        this.startViz()
    }

    buildUI() {
        this.cover = h('div.ap-cover', h('div.ap-disc', h('div.ap-disc-img'), h('div.ap-disc-hole')))
        this.titleEl = h('div.ap-title', '—')
        this.artistEl = h('div.ap-artist', '')
        this.tagsEl = h('div.ap-tags')
        this.lyricBox = h('div.ap-lyrics')
        this.canvas = h('canvas.ap-viz')

        this.seek = h('input.range.ap-seek', { type: 'range', min: 0, max: 1000, value: 0, step: 1 })
        this.curTime = h('span.ap-time', '00:00')
        this.durTime = h('span.ap-time', '00:00')
        this.seek.addEventListener('input', () => {
            this.seeking = true
            this.seek.style.setProperty('--p', this.seek.value / 10 + '%')
            this.curTime.textContent = formatTime(this.seek.value / 1000 * this.duration())
        })
        this.seek.addEventListener('change', () => {
            this.seeking = false
            this.setTime(this.seek.value / 1000 * this.duration())
        })

        this.playBtn = h('button.ap-play', { title: '播放 / 暂停 (空格)', onclick: () => this.toggle() }, icon('play', 28))
        this.loopBtn = btn('repeat', '循环模式', () => this.cycleLoop())
        this.shuffleBtn = btn('shuffle', '随机播放', () => {
            store.set('audioShuffle', !store.get('audioShuffle'))
            this.updateModes()
        })
        this.speedBtn = h('button.chip-btn', { title: '播放速度', onclick: e => togglePopover(e.currentTarget, () => menu(
            [0.5, 0.75, 1, 1.25, 1.5, 2].map(r => ({ label: r + '×', checked: this.rate === r, onclick: () => this.setRate(r) }))), { side: 'top' }) }, '1.0×')
        this.rate = 1

        const vol = store.get('volume')
        this.volIcon = btn(vol ? 'volume-2' : 'volume-x', '静音', () => this.toggleMute())
        this.vol = h('input.range.ap-vol', { type: 'range', min: 0, max: 100, value: vol * 100 })
        this.vol.style.setProperty('--p', vol * 100 + '%')
        this.vol.addEventListener('input', () => this.setVolume(this.vol.value / 100))

        const controls = h('div.ap-controls',
            h('div.ap-ctrl-side', this.shuffleBtn, this.loopBtn),
            h('div.ap-ctrl-main',
                btn('skip-back', '上一首', () => this.prev(), { size: 22 }),
                this.playBtn,
                btn('skip-forward', '下一首', () => this.next(true), { size: 22 })),
            h('div.ap-ctrl-side', this.speedBtn, this.volIcon, this.vol))

        this.stage = h('div.ap-stage',
            h('div.ap-bg'),
            this.canvas,
            h('div.ap-center',
                h('div.ap-left', this.cover),
                h('div.ap-right',
                    h('div.ap-meta', this.titleEl, this.artistEl, this.tagsEl),
                    this.lyricBox)),
            h('div.ap-bottom',
                h('div.ap-seekrow', this.curTime, this.seek, this.durTime),
                controls))
        this.content.append(this.stage)

        this.listEl = h('div.ap-playlist')
        this.infoEl = h('div.ap-info')
        const tabs = sidebarTabs([
            { id: 'list', label: '播放列表', icon: 'list-music', panel: this.listEl },
            { id: 'info', label: '详细信息', icon: 'info', panel: this.infoEl },
        ])
        this.sidebar.append(tabs.el)
        this.updateModes()
    }

    bindAudio() {
        const a = this.audio
        this.listen(a, 'timeupdate', () => this.tick())
        this.listen(a, 'loadedmetadata', () => { this.durTime.textContent = formatTime(a.duration); this.renderInfo() })
        this.listen(a, 'play', () => this.setPlaying(true))
        this.listen(a, 'pause', () => this.setPlaying(false))
        this.listen(a, 'ended', () => this.onEnded())
        this.listen(a, 'error', () => {
            if (!this.isMidi) toast(`无法播放：${this.current?.name}（格式可能不受支持）`, 'error')
        })
        this.onSettingsOff = store.onSettings((_s, k) => { if (k === 'visualizer') this.vizMode = store.get('visualizer') })
        this.onDispose(this.onSettingsOff)
        this.vizMode = store.get('visualizer')
    }

    get current() { return this.playlist[this.index] }

    async load(i, autoplay) {
        const c = audioCtx()
        this.stopAll()
        this.index = (i + this.playlist.length) % this.playlist.length
        const s = this.current
        this.isMidi = MIDI_EXTS.includes(s.ext)
        this.meta = null
        this.lyrics = []
        this.titleEl.textContent = stemOf(s.name)
        this.artistEl.textContent = this.isMidi ? 'MIDI 音乐 · GeneralUser GS 音色库' : '未知艺术家'
        fill(this.tagsEl, h('span.tag', s.ext.toUpperCase()), s.size ? h('span.tag', formatBytes(s.size)) : null)
        this.setCover(null)
        this.renderLyrics()
        this.app.setTabTitle?.(this, s.name)
        this.highlightPlaylist()
        this.seek.value = 0
        this.seek.style.setProperty('--p', '0%')
        this.curTime.textContent = '00:00'
        this.durTime.textContent = '00:00'

        if (this.isMidi) {
            this.artistEl.textContent = '正在加载 MIDI 音色库…'
            try {
                const { seq } = await getMidiEngine()
                this.midi = seq
                const buf = await s.arrayBuffer()
                seq.loadNewSongList([{ binary: buf, fileName: s.name }])
                seq.playbackRate = this.rate
                seq.eventHandler.addEvent('songEnded', 'lr', () => { if (activePlayer === this && this.midi) this.onEnded() })
                this.artistEl.textContent = 'MIDI 音乐 · GeneralUser GS 音色库'
                if (autoplay) this.play()
                this.pollMidiDuration()
            } catch (e) {
                console.error(e)
                toast('MIDI 播放初始化失败：' + (e.message ?? e), 'error')
                this.artistEl.textContent = 'MIDI 加载失败'
            }
        } else {
            if (!this.mediaNode) {
                this.mediaNode = c.createMediaElementSource(this.audio)
                this.mediaNode.connect(masterGain)
            }
            this.audio.src = s.url()
            this.audio.playbackRate = this.rate
            if (autoplay) this.play()
            this.loadMeta(s)
        }
        this.loadLyricsFile(s)
        store.setProgress('audio:last', { path: s.path })
    }

    pollMidiDuration() {
        clearInterval(this.midiPoll)
        this.midiPoll = setInterval(() => {
            if (!this.midi) return clearInterval(this.midiPoll)
            this.tick()
        }, 250)
    }

    async loadMeta(s) {
        const src = s.path ?? new Uint8Array(await s.arrayBuffer())
        const m = await window.lite.audioMeta(src)
        if (s !== this.current || !m || m.error) return
        this.meta = m
        if (m.title) this.titleEl.textContent = m.title
        this.artistEl.textContent = [m.artist, m.album].filter(Boolean).join(' · ') || '未知艺术家'
        fill(this.tagsEl, 
            h('span.tag', (m.codec ?? s.ext).toUpperCase().slice(0, 16)),
            m.bitrate ? h('span.tag', Math.round(m.bitrate / 1000) + ' kbps') : null,
            m.sampleRate ? h('span.tag', (m.sampleRate / 1000).toFixed(1) + ' kHz') : null,
            m.lossless === true ? h('span.tag.accent', '无损') : null)
        if (m.picture) this.setCover(new Blob([m.picture.data], { type: m.picture.format }))
        if (m.lyrics && !this.lyrics.length) {
            this.lyrics = parseLRC(m.lyrics)
            if (!this.lyrics.length) this.lyrics = m.lyrics.split(/\r?\n/).filter(Boolean).map(text => ({ t: -1, text }))
            this.renderLyrics()
        }
        this.renderInfo()
        this.renderPlaylistItem(this.index)
    }

    async loadLyricsFile(s) {
        if (!s.path) return
        const lrcPath = dirName(s.path) + '\\' + stemOf(s.name) + '.lrc'
        const st = await window.lite.stat(lrcPath)
        if (!st?.isFile || s !== this.current) return
        const { text } = decodeText(await window.lite.readFile(lrcPath))
        this.lyrics = parseLRC(text)
        this.renderLyrics()
    }

    setCover(blob) {
        if (this.coverURL) URL.revokeObjectURL(this.coverURL)
        this.coverURL = blob ? URL.createObjectURL(blob) : null
        const img = this.cover.querySelector('.ap-disc-img')
        img.style.backgroundImage = this.coverURL ? `url("${this.coverURL}")` : ''
        this.cover.classList.toggle('has-art', !!blob)
        this.stage.querySelector('.ap-bg').style.backgroundImage = this.coverURL ? `url("${this.coverURL}")` : ''
        this.stage.classList.toggle('has-art', !!blob)
    }

    renderLyrics() {
        this.lyricLines = []
        if (!this.lyrics.length) {
            fill(this.lyricBox, h('div.ap-lyric-empty', icon(this.isMidi ? 'piano' : 'mic-vocal', 22),
                h('span', this.isMidi ? '正在用 SoundFont 合成器演奏' : '暂无歌词 · 可放置同名 .lrc 文件')))
            return
        }
        const inner = h('div.ap-lyric-inner')
        for (const l of this.lyrics) {
            const el = h('div.ap-lyric', { onclick: () => l.t >= 0 && this.setTime(l.t) }, l.text || '♪')
            this.lyricLines.push(el)
            inner.append(el)
        }
        fill(this.lyricBox, inner)
        this.lyricIndex = -1
    }

    syncLyrics(t) {
        if (!this.lyrics.length || this.lyrics[0].t < 0) return
        let i = -1
        for (let k = 0; k < this.lyrics.length; k++) { if (this.lyrics[k].t <= t + 0.15) i = k; else break }
        if (i === this.lyricIndex) return
        this.lyricLines[this.lyricIndex]?.classList.remove('active')
        this.lyricIndex = i
        const el = this.lyricLines[i]
        if (!el) return
        el.classList.add('active')
        const box = this.lyricBox
        box.scrollTo({ top: el.offsetTop - box.clientHeight / 2 + el.clientHeight / 2, behavior: 'smooth' })
    }

    renderPlaylist() {
        this.listEl.replaceChildren(
            h('div.sb-caption', icon('list-music', 15), `共 ${this.playlist.length} 首`),
            ...this.playlist.map((s, i) => this.playlistItem(s, i)))
        this.highlightPlaylist()
    }
    playlistItem(s, i) {
        return h('div.ap-item', { dataset: { i }, onclick: () => this.load(i, true) },
            h('span.ap-item-no', String(i + 1).padStart(2, '0')),
            h('span.ap-item-eq', h('i'), h('i'), h('i')),
            h('div.ap-item-text',
                h('div.ap-item-name', i === this.index && this.meta?.title ? this.meta.title : stemOf(s.name)),
                h('div.ap-item-sub', `${s.ext.toUpperCase()} · ${formatBytes(s.size)}`)))
    }
    renderPlaylistItem(i) {
        const el = this.listEl.querySelector(`.ap-item[data-i="${i}"]`)
        el?.replaceWith(this.playlistItem(this.playlist[i], i))
        this.highlightPlaylist()
    }
    highlightPlaylist() {
        this.listEl.querySelectorAll('.ap-item').forEach(el => el.classList.toggle('active', Number(el.dataset.i) === this.index))
        this.listEl.querySelector('.ap-item.active')?.scrollIntoView({ block: 'nearest' })
        this.listEl.classList.toggle('playing', !!this.playing)
    }

    renderInfo() {
        const s = this.current, m = this.meta ?? {}
        const row = (k, v) => v ? h('div.info-row', h('span', k), h('span', String(v))) : null
        fill(this.infoEl, h('div.info-list',
            row('文件名', s.name), row('标题', m.title), row('艺术家', m.artist), row('专辑', m.album),
            row('年份', m.year), row('流派', m.genre), row('时长', formatTime(this.duration())),
            row('编码', m.codec), row('容器', m.container), row('码率', m.bitrate && Math.round(m.bitrate / 1000) + ' kbps'),
            row('采样率', m.sampleRate && m.sampleRate + ' Hz'), row('大小', formatBytes(s.size)), row('路径', s.path)))
    }

    duration() {
        if (this.isMidi) return this.midi?.duration ?? 0
        return Number.isFinite(this.audio.duration) ? this.audio.duration : 0
    }
    time() {
        if (this.isMidi) return this.midi?.currentTime ?? 0
        return this.audio.currentTime
    }
    setTime(t) {
        if (this.isMidi) { if (this.midi) this.midi.currentTime = t }
        else this.audio.currentTime = t
        this.tick()
    }

    tick() {
        const d = this.duration(), t = this.time()
        if (!this.seeking && d) {
            this.seek.value = t / d * 1000
            this.seek.style.setProperty('--p', t / d * 100 + '%')
            this.curTime.textContent = formatTime(t)
        }
        this.durTime.textContent = formatTime(d)
        this.syncLyrics(t)
        if (this.isMidi && this.midi && this.playing !== !this.midi.paused) this.setPlaying(!this.midi.paused)
    }

    async play() {
        claim(this)
        const c = audioCtx()
        if (c.state === 'suspended') await c.resume()
        if (this.isMidi) this.midi?.play()
        else await this.audio.play().catch(e => console.warn(e))
        this.setPlaying(true)
    }
    pause() {
        if (this.isMidi) this.midi?.pause()
        else this.audio.pause()
        this.setPlaying(false)
    }
    toggle() { this.playing ? this.pause() : this.play() }

    stopAll() {
        this.audio.pause()
        if (this.midi) {
            this.midi.pause()
            this.midi.eventHandler.removeEvent('songEnded', 'lr')
            this.midi = null
        }
        clearInterval(this.midiPoll)
    }

    setPlaying(v) {
        this.playing = v
        setIcon(this.playBtn, v ? 'pause' : 'play', 28)
        this.stage.classList.toggle('playing', v)
        this.listEl.classList.toggle('playing', v)
        this.app.setTabBadge?.(this, v ? 'playing' : null)
    }

    onEnded() {
        const mode = store.get('audioLoop')
        if (mode === 'one') { this.setTime(0); this.play(); return }
        this.next(false)
    }

    next(manual) {
        if (store.get('audioShuffle') && this.playlist.length > 2) {
            let n
            do n = Math.floor(Math.random() * this.playlist.length); while (n === this.index)
            return this.load(n, true)
        }
        if (!manual && store.get('audioLoop') === 'off' && this.index === this.playlist.length - 1) {
            this.setPlaying(false)
            return
        }
        this.load(this.index + 1, true)
    }
    prev() {
        if (this.time() > 3) return this.setTime(0)
        this.load(this.index - 1, true)
    }

    cycleLoop() {
        const order = ['all', 'one', 'off']
        store.set('audioLoop', order[(order.indexOf(store.get('audioLoop')) + 1) % 3])
        this.updateModes()
        toast({ all: '列表循环', one: '单曲循环', off: '顺序播放' }[store.get('audioLoop')])
    }
    updateModes() {
        const mode = store.get('audioLoop')
        setIcon(this.loopBtn, mode === 'one' ? 'repeat-1' : 'repeat')
        this.loopBtn.classList.toggle('active', mode !== 'off')
        this.shuffleBtn.classList.toggle('active', store.get('audioShuffle'))
    }
    setRate(r) {
        this.rate = r
        this.speedBtn.textContent = r.toFixed(r % 1 ? 2 : 1).replace(/0$/, '') + '×'
        this.audio.playbackRate = r
        if (this.midi) this.midi.playbackRate = r
    }
    setVolume(v) {
        v = clamp(v, 0, 1)
        store.set('volume', v)
        if (masterGain) masterGain.gain.setTargetAtTime(v, ctx.currentTime, 0.02)
        this.vol.value = v * 100
        this.vol.style.setProperty('--p', v * 100 + '%')
        setIcon(this.volIcon, v === 0 ? 'volume-x' : v < 0.5 ? 'volume-1' : 'volume-2')
    }
    toggleMute() {
        const v = store.get('volume')
        if (v > 0) { this.lastVol = v; this.setVolume(0) }
        else this.setVolume(this.lastVol || 0.8)
    }

    // ---------- 可视化 ----------
    startViz() {
        const cv = this.canvas
        const g = cv.getContext('2d')
        const freq = new Uint8Array(analyser.frequencyBinCount)
        const wave = new Uint8Array(analyser.fftSize)
        let particles = []
        const loop = () => {
            this.raf = requestAnimationFrame(loop)
            if (this.el.hidden || !this.el.isConnected) return
            const dpr = devicePixelRatio || 1
            const W = cv.clientWidth, H = cv.clientHeight
            if (cv.width !== W * dpr || cv.height !== H * dpr) { cv.width = W * dpr; cv.height = H * dpr }
            g.setTransform(dpr, 0, 0, dpr, 0, 0)
            g.clearRect(0, 0, W, H)
            const mode = this.vizMode
            if (mode === 'off' || activePlayer !== this) return
            const css = getComputedStyle(this.el)
            const c1 = css.getPropertyValue('--accent').trim() || '#7c5cff'
            const c2 = css.getPropertyValue('--accent-2').trim() || '#20c4d8'
            analyser.getByteFrequencyData(freq)
            const grad = g.createLinearGradient(0, H, W, 0)
            grad.addColorStop(0, c1)
            grad.addColorStop(1, c2)
            if (mode === 'bars' || mode === 'mirror') {
                const n = 96
                const bw = W / n
                for (let i = 0; i < n; i++) {
                    const idx = Math.floor(Math.pow(i / n, 1.7) * freq.length * 0.72)
                    const v = freq[idx] / 255
                    const bh = Math.max(2, v * H * (mode === 'mirror' ? 0.32 : 0.42))
                    g.fillStyle = grad
                    g.globalAlpha = 0.25 + v * 0.55
                    const x = i * bw + bw * 0.18
                    if (mode === 'mirror') {
                        roundRect(g, x, H / 2 - bh, bw * 0.64, bh * 2, 3)
                    } else roundRect(g, x, H - bh, bw * 0.64, bh, 3)
                }
                g.globalAlpha = 1
            } else if (mode === 'wave') {
                analyser.getByteTimeDomainData(wave)
                g.lineWidth = 2.5
                g.strokeStyle = grad
                g.shadowColor = c1
                g.shadowBlur = 14
                g.beginPath()
                for (let i = 0; i < wave.length; i += 4) {
                    const x = i / wave.length * W
                    const y = H / 2 + (wave[i] - 128) / 128 * H * 0.3
                    i ? g.lineTo(x, y) : g.moveTo(x, y)
                }
                g.stroke()
                g.shadowBlur = 0
            } else if (mode === 'circle') {
                const cx = W / 2, cy = H / 2, r = Math.min(W, H) * 0.24
                const n = 160
                g.lineWidth = 2.2
                g.strokeStyle = grad
                for (let i = 0; i < n; i++) {
                    const v = freq[Math.floor(i / n * freq.length * 0.6)] / 255
                    const a = i / n * Math.PI * 2 - Math.PI / 2
                    const len = r + v * r * 0.9
                    g.globalAlpha = 0.3 + v * 0.7
                    g.beginPath()
                    g.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
                    g.lineTo(cx + Math.cos(a) * len, cy + Math.sin(a) * len)
                    g.stroke()
                }
                g.globalAlpha = 1
            } else if (mode === 'particles') {
                let energy = 0
                for (let i = 0; i < 64; i++) energy += freq[i]
                energy /= 64 * 255
                if (particles.length < 220) for (let k = 0; k < 3 + energy * 8; k++) particles.push({
                    x: W / 2, y: H / 2, a: Math.random() * Math.PI * 2, s: 0.4 + Math.random() * 2.4, r: 0.6 + Math.random() * 2.2, life: 1,
                })
                particles = particles.filter(p => p.life > 0 && p.x > -10 && p.x < W + 10 && p.y > -10 && p.y < H + 10)
                for (const p of particles) {
                    p.x += Math.cos(p.a) * p.s * (1 + energy * 5)
                    p.y += Math.sin(p.a) * p.s * (1 + energy * 5)
                    p.life -= 0.004
                    g.globalAlpha = p.life * 0.9
                    g.fillStyle = Math.random() > 0.5 ? c1 : c2
                    g.beginPath()
                    g.arc(p.x, p.y, p.r * (1 + energy), 0, Math.PI * 2)
                    g.fill()
                }
                g.globalAlpha = 1
            }
            // 唱片随低频微微跳动
            let bass = 0
            for (let i = 0; i < 12; i++) bass += freq[i]
            this.cover.style.setProperty('--beat', 1 + bass / (12 * 255) * 0.045)
        }
        loop()
        this.onDispose(() => cancelAnimationFrame(this.raf))
    }

    onKey(e) {
        const k = e.key
        if (k === ' ' || k.toLowerCase() === 'k') { this.toggle(); return true }
        if (k === 'ArrowRight' && e.ctrlKey) { this.next(true); return true }
        if (k === 'ArrowLeft' && e.ctrlKey) { this.prev(); return true }
        if (k === 'ArrowRight') { this.setTime(Math.min(this.duration(), this.time() + 5)); return true }
        if (k === 'ArrowLeft') { this.setTime(Math.max(0, this.time() - 5)); return true }
        if (k === 'ArrowUp') { this.setVolume(store.get('volume') + 0.05); return true }
        if (k === 'ArrowDown') { this.setVolume(store.get('volume') - 0.05); return true }
        if (k.toLowerCase() === 'm') { this.toggleMute(); return true }
        if (k.toLowerCase() === 'l') { this.cycleLoop(); return true }
        return false
    }

    destroy() {
        this.stopAll()
        this.audio.removeAttribute('src')
        this.audio.load()
        try { this.mediaNode?.disconnect() } catch { /* ignore */ }
        if (activePlayer === this) activePlayer = null
        if (this.coverURL) URL.revokeObjectURL(this.coverURL)
        super.destroy()
    }
}

function roundRect(g, x, y, w, hh, r) {
    g.beginPath()
    g.roundRect(x, y, w, hh, Math.min(r, w / 2, hh / 2))
    g.fill()
}

export { segmented, Source }
