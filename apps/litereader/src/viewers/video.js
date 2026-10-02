import { Viewer } from './base.js'
import { h, btn, setIcon, formatTime, clamp, togglePopover, menu, toast, throttle } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { siblings, stemOf, dirName, baseName, Source } from '../core/files.js'
import { decodeText } from '../core/encoding.js'
import * as store from '../core/store.js'

// SRT 转 WebVTT
const srtToVtt = srt => 'WEBVTT\n\n' + srt.replace(/\r/g, '')
    .replace(/^\d+\s*$/gm, '')
    .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
    .trim()

export class VideoViewer extends Viewer {
    async mount() {
        this.el.classList.add('video-viewer')
        this.addTitle()
        this.tool('list-video', '播放列表', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)
        this.tool('captions', '加载字幕文件', () => this.pickSubtitle())
        this.tool('camera', '截图 (Ctrl S)', () => this.screenshot())

        this.video = h('video.vp-video', { preload: 'auto', playsInline: true })
        this.video.crossOrigin = 'anonymous'
        this.osd = h('div.vp-osd')
        this.bigPlay = h('button.vp-bigplay', { onclick: () => this.toggle() }, icon('play', 40))
        this.spinner = h('div.vp-spinner', h('div.spinner'))
        this.buildControls()
        this.player = h('div.vp-player', this.video, this.spinner, this.bigPlay, this.osd, this.controls)
        this.content.append(this.player)
        this.bind()

        this.playlist = await siblings(this.source, 'video')
        this.index = Math.max(0, this.playlist.findIndex(s => s.path === this.source.path))
        if (!this.source.path) { this.playlist = [this.source]; this.index = 0 }
        this.renderPlaylist()
        this.load(this.index)
    }

    buildControls() {
        this.seek = h('input.range.vp-seek', { type: 'range', min: 0, max: 1000, step: 0.1, value: 0 })
        this.buffered = h('div.vp-buffered')
        this.hoverTip = h('div.vp-hovertip')
        this.seekWrap = h('div.vp-seekwrap', this.buffered, this.seek, this.hoverTip)
        this.timeEl = h('span.vp-time', '00:00 / 00:00')
        this.playBtn = btn('play', '播放 / 暂停 (空格)', () => this.toggle(), { size: 22 })
        this.volBtn = btn('volume-2', '静音 (M)', () => this.toggleMute())
        this.vol = h('input.range.vp-vol', { type: 'range', min: 0, max: 100, value: store.get('volume') * 100 })
        this.speedBtn = h('button.chip-btn', { title: '播放速度', onclick: e => togglePopover(e.currentTarget, () => menu(
            [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3].map(r => ({ label: r + '×', checked: this.video.playbackRate === r, onclick: () => this.setRate(r) }))), { side: 'top' }) }, '1×')
        this.subBtn = btn('subtitles', '字幕', e => togglePopover(e.currentTarget, () => this.subtitleMenu(), { side: 'top' }))
        this.fsBtn = btn('maximize', '全屏 (F / 双击)', () => this.app.toggleFullscreen())
        this.controls = h('div.vp-controls',
            this.seekWrap,
            h('div.vp-row',
                h('div.vp-group',
                    btn('skip-back', '上一个', () => this.load(this.index - 1)),
                    this.playBtn,
                    btn('skip-forward', '下一个', () => this.load(this.index + 1)),
                    this.volBtn, this.vol, this.timeEl),
                h('div.vp-group',
                    this.speedBtn, this.subBtn,
                    btn('picture-in-picture-2', '画中画', () => this.pip()),
                    btn('repeat', '循环播放', e => {
                        this.video.loop = !this.video.loop
                        e.currentTarget.classList.toggle('active', this.video.loop)
                    }),
                    this.fsBtn)))
        this.vol.style.setProperty('--p', this.vol.value + '%')
    }

    bind() {
        const v = this.video
        v.volume = store.get('volume')
        this.listen(v, 'loadedmetadata', () => {
            this.updateTime()
            const saved = store.getProgress(this.current.key)
            if (saved?.time > 5 && saved.time < v.duration - 5) {
                v.currentTime = saved.time
                this.flash(`已从 ${formatTime(saved.time)} 继续播放`)
            }
            this.setSubtitle(`${v.videoWidth} × ${v.videoHeight} · ${formatTime(v.duration)}`)
            if (!v.videoWidth) toast('该视频的画面编码可能不受支持（仅有声音）', 'warn', 4000)
        })
        this.listen(v, 'timeupdate', () => { this.updateTime(); this.saveTime() })
        this.listen(v, 'progress', () => this.updateBuffered())
        this.listen(v, 'play', () => this.setPlaying(true))
        this.listen(v, 'pause', () => this.setPlaying(false))
        this.listen(v, 'waiting', () => this.spinner.classList.add('show'))
        this.listen(v, 'playing', () => this.spinner.classList.remove('show'))
        this.listen(v, 'canplay', () => this.spinner.classList.remove('show'))
        this.listen(v, 'ended', () => {
            store.setProgress(this.current.key, { time: 0 })
            if (this.index < this.playlist.length - 1) this.load(this.index + 1)
        })
        this.listen(v, 'error', () => {
            this.spinner.classList.remove('show')
            toast(`无法播放此视频：可能是不受支持的编码（${this.current.ext.toUpperCase()}）`, 'error', 5000)
        })
        this.listen(v, 'click', () => this.toggle())
        this.listen(v, 'dblclick', () => this.app.toggleFullscreen())
        this.listen(v, 'wheel', e => {
            e.preventDefault()
            this.setVolume(v.volume + (e.deltaY < 0 ? 0.05 : -0.05))
        }, { passive: false })

        this.seek.addEventListener('input', () => {
            if (!v.duration) return
            v.currentTime = this.seek.value / 1000 * v.duration
            this.updateTime()
        })
        this.seekWrap.addEventListener('pointermove', e => {
            const r = this.seek.getBoundingClientRect()
            const f = clamp((e.clientX - r.left) / r.width, 0, 1)
            this.hoverTip.textContent = formatTime(f * (v.duration || 0))
            this.hoverTip.style.left = f * 100 + '%'
        })
        this.vol.addEventListener('input', () => this.setVolume(this.vol.value / 100))

        // 鼠标静止后自动隐藏控制条
        const wake = () => {
            this.player.classList.add('awake')
            clearTimeout(this.idleTimer)
            this.idleTimer = setTimeout(() => {
                if (!this.video.paused && !this.controls.matches(':hover')) this.player.classList.remove('awake')
            }, 2600)
        }
        this.listen(this.player, 'pointermove', wake)
        this.listen(this.player, 'pointerdown', wake)
        wake()
    }

    get current() { return this.playlist[this.index] }

    load(i) {
        if (!this.playlist.length) return
        this.saveTimeNow()
        this.index = (i + this.playlist.length) % this.playlist.length
        const s = this.current
        for (const t of [...this.video.querySelectorAll('track')]) t.remove()
        this.subs = []
        this.spinner.classList.add('show')
        this.video.src = s.url()
        this.video.playbackRate = store.get('videoSpeed') ?? 1
        this.speedBtn.textContent = this.video.playbackRate + '×'
        this.video.play().catch(() => {})
        this.app.setTabTitle?.(this, s.name)
        this.highlightPlaylist()
        this.autoSubtitles(s)
    }

    async autoSubtitles(s) {
        if (!s.path) return
        const files = await window.lite.listDir(dirName(s.path))
        const stem = stemOf(s.name).toLowerCase()
        for (const f of files) {
            const n = f.name.toLowerCase()
            if (!/\.(srt|vtt)$/.test(n) || !n.startsWith(stem)) continue
            await this.addSubtitle(f.path, f.name)
        }
    }

    async addSubtitle(path, name) {
        const bytes = await window.lite.readFile(path)
        let { text } = decodeText(bytes)
        if (!/^WEBVTT/.test(text.trim())) text = srtToVtt(text)
        const url = URL.createObjectURL(new Blob([text], { type: 'text/vtt' }))
        this.onDispose(() => URL.revokeObjectURL(url))
        const label = name.replace(/\.(srt|vtt)$/i, '').replace(stemOf(this.current.name), '').replace(/^[._\s-]+/, '') || '字幕'
        const track = h('track', { kind: 'subtitles', src: url, label, srclang: 'zh' })
        this.video.append(track)
        this.subs.push(track)
        track.track.mode = this.subs.length === 1 ? 'showing' : 'hidden'
        this.subBtn.classList.add('active')
        this.flash(`已加载字幕：${label}`)
    }

    async pickSubtitle() {
        const files = await window.lite.openDialog({ title: '选择字幕文件', filters: [{ name: '字幕', extensions: ['srt', 'vtt'] }] })
        for (const f of files) await this.addSubtitle(f, baseName(f))
    }

    subtitleMenu() {
        const tracks = [...this.video.textTracks]
        return menu([
            { label: '关闭字幕', checked: tracks.every(t => t.mode !== 'showing'), onclick: () => { tracks.forEach(t => t.mode = 'hidden'); this.subBtn.classList.remove('active') } },
            ...tracks.map(t => ({
                label: t.label || '字幕', checked: t.mode === 'showing',
                onclick: () => { tracks.forEach(x => x.mode = x === t ? 'showing' : 'hidden'); this.subBtn.classList.add('active') },
            })),
            '-',
            { label: '加载字幕文件…', icon: 'folder-open', onclick: () => this.pickSubtitle() },
        ])
    }

    renderPlaylist() {
        this.sidebar.replaceChildren(h('div.sb-caption', icon('list-video', 15), `播放列表 · ${this.playlist.length}`),
            h('div.vp-list', this.playlist.map((s, i) => h('div.ap-item', { dataset: { i }, onclick: () => this.load(i) },
                h('span.ap-item-no', String(i + 1).padStart(2, '0')),
                h('div.ap-item-text', h('div.ap-item-name', stemOf(s.name)), h('div.ap-item-sub', s.ext.toUpperCase()))))))
    }
    highlightPlaylist() {
        this.sidebar.querySelectorAll('.ap-item').forEach(el => el.classList.toggle('active', Number(el.dataset.i) === this.index))
    }

    updateTime() {
        const v = this.video
        const d = v.duration || 0
        this.seek.value = d ? v.currentTime / d * 1000 : 0
        this.seek.style.setProperty('--p', (d ? v.currentTime / d * 100 : 0) + '%')
        this.timeEl.textContent = `${formatTime(v.currentTime)} / ${formatTime(d)}`
    }
    updateBuffered() {
        const v = this.video
        if (!v.duration || !v.buffered.length) return
        const end = v.buffered.end(v.buffered.length - 1)
        this.buffered.style.width = end / v.duration * 100 + '%'
    }
    saveTime = throttle(() => this.saveTimeNow(), 3000)
    saveTimeNow() {
        const s = this.current, v = this.video
        if (!s || !v.duration) return
        store.setProgress(s.key, { time: v.currentTime, duration: v.duration })
        this.app.updateRecentProgress(this.source, v.currentTime / v.duration)
    }

    setPlaying(p) {
        setIcon(this.playBtn, p ? 'pause' : 'play', 22)
        this.player.classList.toggle('paused', !p)
    }
    toggle() {
        if (this.video.paused) this.video.play().catch(() => {})
        else this.video.pause()
    }
    setVolume(v) {
        v = clamp(v, 0, 1)
        this.video.volume = v
        this.video.muted = v === 0
        store.set('volume', v)
        this.vol.value = v * 100
        this.vol.style.setProperty('--p', v * 100 + '%')
        setIcon(this.volBtn, v === 0 ? 'volume-x' : v < 0.5 ? 'volume-1' : 'volume-2')
        this.flash(`音量 ${Math.round(v * 100)}%`)
    }
    toggleMute() {
        if (this.video.volume > 0) { this.lastVol = this.video.volume; this.setVolume(0) }
        else this.setVolume(this.lastVol || 0.8)
    }
    setRate(r) {
        this.video.playbackRate = r
        store.set('videoSpeed', r)
        this.speedBtn.textContent = r + '×'
        this.flash(`播放速度 ${r}×`)
    }
    async pip() {
        try {
            if (document.pictureInPictureElement) await document.exitPictureInPicture()
            else await this.video.requestPictureInPicture()
        } catch (e) { toast('画中画不可用：' + e.message, 'error') }
    }
    async screenshot() {
        const v = this.video
        if (!v.videoWidth) return
        const c = h('canvas')
        c.width = v.videoWidth
        c.height = v.videoHeight
        c.getContext('2d').drawImage(v, 0, 0)
        const blob = await new Promise(r => c.toBlob(r, 'image/png'))
        const name = `${stemOf(this.current.name)}_${formatTime(v.currentTime).replace(/:/g, '-')}.png`
        const saved = await window.lite.saveFile({
            defaultPath: name,
            filters: [{ name: 'PNG 图片', extensions: ['png'] }],
            data: new Uint8Array(await blob.arrayBuffer()),
        })
        if (saved) toast('截图已保存', 'success')
    }
    flash(text) {
        this.osd.textContent = text
        this.osd.classList.add('show')
        clearTimeout(this.osdTimer)
        this.osdTimer = setTimeout(() => this.osd.classList.remove('show'), 1200)
    }

    onHide() { this.video.pause() }

    onKey(e) {
        const v = this.video, k = e.key
        if (k === ' ' || k.toLowerCase() === 'k') { this.toggle(); return true }
        if (k === 'ArrowRight') { v.currentTime = Math.min(v.duration, v.currentTime + (e.shiftKey ? 30 : 5)); this.flash('快进 ' + (e.shiftKey ? 30 : 5) + ' 秒'); return true }
        if (k === 'ArrowLeft') { v.currentTime = Math.max(0, v.currentTime - (e.shiftKey ? 30 : 5)); this.flash('后退 ' + (e.shiftKey ? 30 : 5) + ' 秒'); return true }
        if (k === 'ArrowUp') { this.setVolume(v.volume + 0.05); return true }
        if (k === 'ArrowDown') { this.setVolume(v.volume - 0.05); return true }
        if (k.toLowerCase() === 'm') { this.toggleMute(); return true }
        if (k.toLowerCase() === 'f') { this.app.toggleFullscreen(); return true }
        if (k === 'PageDown') { this.load(this.index + 1); return true }
        if (k === 'PageUp') { this.load(this.index - 1); return true }
        if (k === ']' || k === '>') { this.setRate(Math.min(4, +(v.playbackRate + 0.25).toFixed(2))); return true }
        if (k === '[' || k === '<') { this.setRate(Math.max(0.25, +(v.playbackRate - 0.25).toFixed(2))); return true }
        if (e.ctrlKey && k.toLowerCase() === 's') { this.screenshot(); return true }
        if (/^[0-9]$/.test(k) && !e.ctrlKey) { v.currentTime = v.duration * Number(k) / 10; return true }
        return false
    }

    destroy() {
        this.saveTimeNow()
        clearTimeout(this.idleTimer)
        this.video.pause()
        this.video.removeAttribute('src')
        this.video.load()
        super.destroy()
    }
}

export { Source }
