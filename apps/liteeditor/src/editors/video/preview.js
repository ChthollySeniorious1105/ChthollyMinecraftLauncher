// 预览：画布合成、播放时钟、媒体元素同步、暂停时的精确帧（mediabunny CanvasSink）
import { CanvasSink } from 'mediabunny'
import { visualLayers, drawLayers, audibleClips, fadeEnv } from './render.js'
import { projDuration, isActive, srcTime, clipEnd, mediaOf } from './model.js'

export function installPreview(Ed) {
    const P = Ed.prototype

    P.initPreview = function () {
        this.time = 0
        this.playing = false
        this.loop = false
        this.pool = new Map()      // clipId -> { el, gain, src }
        this.frames = new Map()    // clipId -> { st, canvas }
        this.boxes = new Map()     // clipId -> 预览中的外框（项目坐标）
        this.onDispose(() => this.disposePreview())
    }

    P.duration = function () { return projDuration(this.proj) }

    // ---------- 画布尺寸 ----------
    P.sizePreview = function () {
        const r = this.pvWrap.getBoundingClientRect()
        if (!r.width || !r.height) return
        const p = this.proj
        const k = Math.min((r.width - 24) / p.width, (r.height - 24) / p.height)
        const w = Math.max(16, Math.floor(p.width * k)), hh = Math.max(16, Math.floor(p.height * k))
        const dpr = devicePixelRatio || 1
        this.pvScale = k
        this.pv.style.width = w + 'px'
        this.pv.style.height = hh + 'px'
        this.pvOverlay.style.width = w + 'px'
        this.pvOverlay.style.height = hh + 'px'
        const cw = Math.round(w * dpr), ch = Math.round(hh * dpr)
        if (this.pv.width !== cw || this.pv.height !== ch) { this.pv.width = cw; this.pv.height = ch }
        if (this.pvOverlay.width !== cw || this.pvOverlay.height !== ch) { this.pvOverlay.width = cw; this.pvOverlay.height = ch }
    }

    // ---------- 渲染当前帧 ----------
    P.renderPreview = function () {
        if (!this.proj || !this.pv.width) return
        const p = this.proj
        const ctx = this.pvCtx
        ctx.setTransform(this.pv.width / p.width, 0, 0, this.pv.height / p.height, 0, 0)
        const layers = visualLayers(p, this.time)
        this.boxes.clear()
        drawLayers(ctx, p, layers, l => this.previewFrame(l), this.boxes)
        if (!this.playing) this.requestFrames(layers)
        this.drawPreviewOverlay()
    }
    P.schedulePreview = function () {
        if (this._pvRaf) return
        this._pvRaf = requestAnimationFrame(() => { this._pvRaf = 0; this.renderPreview() })
    }

    P.drawPreviewOverlay = function () {
        const o = this.pvOverlay, ctx = this.pvOCtx
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        ctx.clearRect(0, 0, o.width, o.height)
        const k = o.width / this.proj.width
        for (const id of this.sel) {
            const b = this.boxes.get(id)
            if (!b) continue
            ctx.save()
            ctx.translate(b.cx * k, b.cy * k)
            ctx.rotate(b.rot * Math.PI / 180)
            ctx.strokeStyle = '#38bdf8'
            ctx.lineWidth = 1.5 * (devicePixelRatio || 1)
            ctx.setLineDash([6, 4])
            ctx.strokeRect(-b.w * k / 2, -b.h * k / 2, b.w * k, b.h * k)
            ctx.restore()
        }
    }

    // 取得图层的画面来源
    P.previewFrame = function (l) {
        const c = l.c
        const asset = this.assets.get(c.media)
        if (!asset) return null
        if (c.type === 'image') return asset.img ? { src: asset.img } : null
        const m = asset.media
        if (this.playing || m.noDecode) {
            const e = this.pool.get(c.id)
            if (e && e.el.readyState >= 2 && (this.playing || Math.abs(e.el.currentTime - l.st) < 0.1)) return { src: e.el }
        }
        const f = this.frames.get(c.id)
        return f ? { src: f.canvas } : null
    }

    // 暂停时：按需解码精确帧（每个媒体串行，只保留最新请求）
    P.requestFrames = function (layers) {
        const fps = this.proj.fps
        for (const l of layers) {
            const c = l.c
            const asset = this.assets.get(c.media)
            if (!asset) continue
            if (c.type === 'image') {
                if (!asset.img && !asset._imgReq) asset._imgReq = asset.image().then(img => { asset.img = img; this.schedulePreview() }).catch(() => {})
                continue
            }
            if (c.type !== 'video') continue
            if (asset.media.noDecode || asset.sinkFailed) { this.seekElementFor(c, l.st); continue }
            const f = this.frames.get(c.id)
            if (f && Math.abs(f.st - l.st) < 0.5 / fps) continue
            asset.want = asset.want ?? new Map()
            asset.want.set(c.id, l.st)
            this.pumpFrames(asset)
        }
    }

    P.pumpFrames = async function (asset) {
        if (asset.pumping) return
        asset.pumping = true
        try {
            if (!asset.sink) {
                const vt = await asset.input().getPrimaryVideoTrack()
                if (!vt || !(await vt.canDecode())) throw new Error('无法解码')
                const m = asset.media
                const maxW = 1280
                asset.sink = m.width > maxW ? new CanvasSink(vt, { width: maxW }) : new CanvasSink(vt)
                asset.firstTs = await vt.getFirstTimestamp()
            }
            while (asset.want?.size) {
                const [clipId, st] = asset.want.entries().next().value
                asset.want.delete(clipId)
                const w = await asset.sink.getCanvas(Math.max(st, asset.firstTs ?? 0))
                if (w) {
                    this.frames.set(clipId, { st, canvas: w.canvas })
                    if (!this.playing) this.schedulePreview()
                }
            }
        } catch (e) {
            if (!this.destroyed) {
                console.warn('帧解码失败，改用媒体元素', e)
                asset.sinkFailed = true
                this.schedulePreview()
            }
        } finally { asset.pumping = false }
    }

    // 后备：用媒体元素定位到帧
    P.seekElementFor = function (c, st) {
        const e = this.ensureElement(c)
        if (!e) return
        if (Math.abs(e.el.currentTime - st) > 0.02 && !e.el.seeking) e.el.currentTime = st
    }

    // ---------- 媒体元素池 ----------
    P.audioCtx = function () {
        if (!this.actx) {
            this.actx = new AudioContext()
            this.master = this.actx.createGain()
            this.master.connect(this.actx.destination)
        }
        return this.actx
    }
    P.ensureElement = function (c) {
        let e = this.pool.get(c.id)
        const asset = this.assets.get(c.media)
        if (!asset?.url) return null
        if (e && e.url !== asset.url) { this.dropElement(c.id); e = null }
        if (e) return e
        const el = document.createElement('video')
        el.crossOrigin = 'anonymous'
        el.preload = 'auto'
        el.playsInline = true
        el.src = asset.url
        el.preservesPitch = true
        e = { el, url: asset.url }
        el.addEventListener('seeked', () => { if (!this.playing) this.schedulePreview() })
        el.addEventListener('loadeddata', () => { if (!this.playing) this.schedulePreview() })
        try {
            const ctx = this.audioCtx()
            e.src = ctx.createMediaElementSource(el)
            e.gain = ctx.createGain()
            e.gain.gain.value = 0
            e.src.connect(e.gain).connect(this.master)
        } catch (err) { console.warn(err); el.volume = 0 }
        this.pool.set(c.id, e)
        return e
    }
    P.dropElement = function (id) {
        const e = this.pool.get(id)
        if (!e) return
        try { e.el.pause(); e.src?.disconnect(); e.gain?.disconnect() } catch { /* ignore */ }
        e.el.removeAttribute('src')
        e.el.load()
        this.pool.delete(id)
    }

    // 播放时同步所有媒体元素的位置 / 播放状态 / 音量
    P.syncElements = function () {
        const p = this.proj, t = this.time
        const want = new Map()
        for (const l of visualLayers(p, t)) if (l.c.type === 'video') want.set(l.c.id, l.c)
        const audible = new Set(audibleClips(p).map(c => c.id))
        for (const c of p.clips) {
            if (c.type !== 'video' && c.type !== 'audio') continue
            if (!audible.has(c.id) && !want.has(c.id)) continue
            // 当前播放的片段，以及即将开始的片段（提前预加载）
            if (isActive(c, t) || (c.start > t && c.start - t < 1.5)) want.set(c.id, c)
        }
        for (const [id, c] of want) {
            const e = this.ensureElement(c)
            if (!e) continue
            const active = isActive(c, t) || (c.dissolve > 0 && false)
            const st = srcTime(c, t)
            const tr = p.tracks.find(x => x.id === c.track)
            let vol = 0
            if (audible.has(id) && active && !tr?.muted) vol = (c.volume ?? 1) * fadeEnv(c, t)
            if (e.gain) e.gain.gain.value = vol
            if (!active) {
                // 预加载：停在入点
                if (!e.el.paused) e.el.pause()
                if (Math.abs(e.el.currentTime - c.in) > 0.05 && !e.el.seeking) e.el.currentTime = c.in
                continue
            }
            const md = mediaOf(p, c)?.duration ?? Infinity
            if (st >= md - 0.02) { if (!e.el.paused) e.el.pause(); continue }
            e.el.playbackRate = c.speed || 1
            if (this.playing) {
                if (e.el.paused) {
                    if (Math.abs(e.el.currentTime - st) > 0.05) e.el.currentTime = st
                    e.el.play().catch(() => {})
                } else if (Math.abs(e.el.currentTime - st) > 0.25 && !e.el.seeking) e.el.currentTime = st
            }
        }
        for (const [id, e] of this.pool) {
            if (!want.has(id)) { if (!e.el.paused) e.el.pause(); if (e.gain) e.gain.gain.value = 0 }
        }
        // 清理已删除片段的元素 / 过多的缓存
        if (this.pool.size > 16) for (const id of [...this.pool.keys()]) if (!want.has(id)) this.dropElement(id)
        for (const id of this.pool.keys()) if (!p.clips.some(c => c.id === id)) this.dropElement(id)
    }

    // ---------- 播放控制 ----------
    P.play = function () {
        if (this.playing) return
        const d = this.duration()
        if (d <= 0) return
        if (this.time >= d - 1 / this.proj.fps) this.time = 0
        this.audioCtx().resume?.()
        this.playing = true
        this.clock0 = performance.now()
        this.time0 = this.time
        this.syncElements()
        this.updateTransport()
        const tick = () => {
            if (!this.playing) return
            let t = this.time0 + (performance.now() - this.clock0) / 1000
            const dd = this.duration()
            if (t >= dd) {
                if (this.loop && dd > 0) { this.time0 = 0; this.clock0 = performance.now(); t = 0; for (const e of this.pool.values()) e.el.pause() }
                else { this.time = dd; this.pause(); return }
            }
            this.time = t
            this.syncElements()
            this.renderPreview()
            this.onTimeChange(true)
            this.raf = requestAnimationFrame(tick)
        }
        this.raf = requestAnimationFrame(tick)
    }
    P.pause = function () {
        this.playing = false
        cancelAnimationFrame(this.raf)
        for (const e of this.pool.values()) { e.el.pause(); if (e.gain) e.gain.gain.value = 0 }
        this.time = Math.round(this.time * this.proj.fps) / this.proj.fps
        this.renderPreview()
        this.onTimeChange()
        this.updateTransport()
    }
    P.togglePlay = function () { this.playing ? this.pause() : this.play() }

    P.seek = function (t, { keepPlaying = true } = {}) {
        const d = this.duration()
        t = Math.max(0, Math.min(t, Math.max(d, 0)))
        this.time = t
        if (this.playing && keepPlaying) {
            this.time0 = t
            this.clock0 = performance.now()
            for (const e of this.pool.values()) e.el.pause()
            this.syncElements()
        }
        this.schedulePreview()
        this.onTimeChange()
    }
    P.stepFrames = function (n) {
        if (this.playing) this.pause()
        const fps = this.proj.fps
        this.seek((Math.round(this.time * fps) + n) / fps)
    }

    P.disposePreview = function () {
        this.playing = false
        cancelAnimationFrame(this.raf)
        for (const id of [...this.pool.keys()]) this.dropElement(id)
        this.frames.clear()
        try { this.actx?.close() } catch { /* ignore */ }
    }

    // 某片段的编辑发生变化后：清除缓存帧
    P.invalidateFrames = function (ids) {
        if (!ids) this.frames.clear()
        else for (const id of ids) this.frames.delete(id)
    }

    void clipEnd
}
