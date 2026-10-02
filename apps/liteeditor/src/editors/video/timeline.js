// 时间线：标尺、轨道、片段（缩略图 / 波形）、播放头；拖动移动 / 修剪 / 框选 / 吸附 / 缩放
import { h, fill, clamp } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import { clipDur, clipEnd, srcTime, clipsOn, clipName, mediaOf, maxOut, clearRange, trackOf, fmtTC } from './model.js'

const RULER = 28
const TRACK_H = { video: 62, audio: 50 }
const HEAD_W = 148
const EDGE = 7
const COLORS = { video: '#3b82f6', audio: '#10b981', image: '#0ea5e9', text: '#a855f7', color: '#f59e0b' }
const TYPE_ICON = { video: 'film', audio: 'audio-lines', image: 'image', text: 'type', color: 'square' }

export const compatible = (clip, track) => track && (clip.type === 'audio' ? track.type === 'audio' : track.type === 'video')

export function installTimeline(Ed) {
    const P = Ed.prototype

    P.buildTimeline = function () {
        this.pps = 60              // 每秒像素
        this.scrollX = 0
        this.scrollY = 0
        this.snapOn = true
        this.heads = h('div.vt-heads-inner')
        this.headCol = h('div.vt-heads',
            h('div.vt-heads-top',
                h('button.vt-mini', { title: '添加视频轨道', onclick: () => this.addTrack('video') }, icon('plus', 13), '视频轨'),
                h('button.vt-mini', { title: '添加音频轨道', onclick: () => this.addTrack('audio') }, icon('plus', 13), '音频轨')),
            h('div.vt-heads-scroll', this.heads))
        this.tl = h('canvas.vt-tl-canvas')
        this.tlCtx = this.tl.getContext('2d')
        this.hInner = h('div.vt-hscroll-inner')
        this.hScroll = h('div.vt-hscroll', this.hInner)
        this.tlArea = h('div.vt-tl-area', { 'data-drop': '' }, this.tl, this.hScroll)
        this.tlEl = h('div.vt-timeline', this.headCol, this.tlArea)
        this.listen(this.tl, 'pointerdown', e => this.tlDown(e))
        this.listen(this.tl, 'pointermove', e => this.tlMove(e))
        this.listen(this.tl, 'pointerup', e => this.tlUp(e))
        this.listen(this.tl, 'pointercancel', e => this.tlUp(e))
        this.listen(this.tl, 'dblclick', e => this.tlDbl(e))
        this.listen(this.tl, 'wheel', e => this.tlWheel(e), { passive: false })
        this.listen(this.tl, 'contextmenu', e => this.tlContext(e))
        this.listen(this.hScroll, 'scroll', () => {
            if (this._syncingScroll) return
            this.scrollX = this.hScroll.scrollLeft
            this.drawTimeline()
        })
        this.listen(this.tlArea, 'dragover', e => {
            const types = [...e.dataTransfer.types]
            if (types.includes('Files') || types.includes('application/x-lite-media')) { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; this.dropHint = this.tlPos(e); this.drawTimeline() }
        })
        this.listen(this.tlArea, 'dragleave', () => { this.dropHint = null; this.drawTimeline() })
        this.listen(this.tlArea, 'drop', e => this.tlDrop(e))
    }

    // ---------- 几何 ----------
    P.tx = function (t) { return t * this.pps - this.scrollX }
    P.xt = function (x) { return (x + this.scrollX) / this.pps }
    P.trackRows = function () {
        let y = RULER - this.scrollY
        return this.proj.tracks.map(tr => { const r = { tr, y, h: TRACK_H[tr.type] }; y += r.h; return r })
    }
    P.rowAt = function (y) { return this.trackRows().find(r => y >= r.y && y < r.y + r.h) ?? null }
    P.tlPos = function (e) {
        const r = this.tl.getBoundingClientRect()
        return { x: e.clientX - r.left, y: e.clientY - r.top }
    }
    P.contentH = function () { return this.proj.tracks.reduce((s, t) => s + TRACK_H[t.type], 0) }

    P.sizeTimeline = function () {
        const r = this.tl.getBoundingClientRect()
        if (!r.width) return
        const dpr = devicePixelRatio || 1
        this.tlW = r.width; this.tlH = r.height
        const cw = Math.round(r.width * dpr), ch = Math.round(r.height * dpr)
        if (this.tl.width !== cw || this.tl.height !== ch) { this.tl.width = cw; this.tl.height = ch }
    }

    P.maxScrollX = function () { return Math.max(0, (this.duration() + 10) * this.pps - (this.tlW || 800) * 0.5) }
    P.setScrollX = function (v) {
        this.scrollX = clamp(v, 0, this.maxScrollX())
        this.drawTimeline()
    }
    P.setZoom = function (pps, anchorX) {
        pps = clamp(pps, 1, 600)
        const ax = anchorX ?? this.tx(this.time)
        const t = this.xt(ax)
        this.pps = pps
        this.scrollX = clamp(t * pps - ax, 0, this.maxScrollX())
        this.drawTimeline()
        this.updateStatus()
    }
    P.zoomBy = function (k) { this.setZoom(this.pps * k) }
    P.zoomFit = function () {
        const w = (this.tlW || 800) - 40
        this.pps = clamp(w / Math.max(this.duration(), 5), 1, 600)
        this.scrollX = 0
        this.drawTimeline()
        this.updateStatus()
    }

    // ---------- 轨道头 ----------
    P.renderHeads = function () {
        const rows = this.proj.tracks.map(tr => {
            const vis = tr.type === 'video'
            const b = (ic, title, on, fn) => h('button.vt-hbtn' + (on ? '.on' : ''), { title, onclick: e => { e.stopPropagation(); fn() } }, icon(ic, 14))
            const el = h('div.vt-head.' + tr.type + (tr.locked ? '.locked' : ''), { style: { height: TRACK_H[tr.type] + 'px' } },
                h('span.vt-head-badge', tr.name),
                h('span.vt-head-flex'),
                vis ? b(tr.hidden ? 'eye-off' : 'eye', tr.hidden ? '显示轨道' : '隐藏轨道', tr.hidden, () => this.toggleTrack(tr, 'hidden'))
                    : null,
                b(tr.muted ? 'volume-x' : 'volume-2', tr.muted ? '取消静音' : '静音', tr.muted, () => this.toggleTrack(tr, 'muted')),
                b(tr.locked ? 'lock' : 'lock-open', tr.locked ? '解锁' : '锁定', tr.locked, () => this.toggleTrack(tr, 'locked')))
            el.addEventListener('contextmenu', e => contextMenu(e, [
                { label: '重命名…', icon: 'pencil', run: () => this.renameTrack(tr) },
                { label: '添加视频轨道', icon: 'plus', run: () => this.addTrack('video') },
                { label: '添加音频轨道', icon: 'plus', run: () => this.addTrack('audio') },
                '-',
                { label: '选择轨道上所有片段', icon: 'list-checks', run: () => this.setSel(clipsOn(this.proj, tr.id).map(c => c.id)) },
                { label: '删除轨道', icon: 'trash-2', danger: true, disabled: () => this.proj.tracks.filter(t => t.type === tr.type).length <= 1, run: () => this.deleteTrack(tr) },
            ]))
            return el
        })
        fill(this.heads, rows)
        this.heads.style.transform = `translateY(${-this.scrollY}px)`
    }

    // ---------- 绘制 ----------
    P.themeColors = function () {
        const now = performance.now()
        if (this._tc && now - this._tcTime < 800) return this._tc
        const s = getComputedStyle(this.el)
        const v = k => s.getPropertyValue(k).trim()
        this._tcTime = now
        return this._tc = { bg: v('--bg'), surface: v('--surface'), s2: v('--surface-2'), s3: v('--surface-3'), line: v('--line'), line2: v('--line-2'), text: v('--text'), text2: v('--text-2'), text3: v('--text-3'), accent: v('--accent') }
    }

    P.drawTimeline = function () {
        if (!this.proj || !this.tl.width) return
        const ctx = this.tlCtx, dpr = devicePixelRatio || 1
        const W = this.tlW, H = this.tlH
        const C = this.themeColors()
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
        ctx.clearRect(0, 0, W, H)
        ctx.fillStyle = C.s2
        ctx.fillRect(0, 0, W, H)
        // 轨道背景
        const rows = this.trackRows()
        for (const r of rows) {
            if (r.y > H || r.y + r.h < RULER) continue
            ctx.fillStyle = r.tr.type === 'video' ? C.surface : C.s3
            ctx.globalAlpha = 0.55
            ctx.fillRect(0, r.y, W, r.h)
            ctx.globalAlpha = 1
            ctx.fillStyle = C.line
            ctx.fillRect(0, r.y + r.h - 1, W, 1)
        }
        // 片段
        ctx.save()
        ctx.beginPath(); ctx.rect(0, RULER, W, H - RULER); ctx.clip()
        const t0 = this.xt(0), t1 = this.xt(W)
        const sel = new Set(this.sel)
        for (const r of rows) {
            if (r.y > H || r.y + r.h < RULER) continue
            for (const c of this.proj.clips) {
                if (c.track !== r.tr.id || clipEnd(c) < t0 || c.start > t1) continue
                this.drawClip(ctx, c, r, sel.has(c.id), C)
            }
            if (r.tr.locked) {
                ctx.fillStyle = 'rgba(127,127,127,.12)'
                ctx.fillRect(0, r.y, W, r.h - 1)
            }
        }
        // 拖入提示
        if (this.dropHint) {
            const row = this.rowAt(this.dropHint.y)
            if (row) {
                ctx.fillStyle = C.accent
                ctx.globalAlpha = 0.18
                ctx.fillRect(0, row.y, W, row.h)
                ctx.globalAlpha = 1
                ctx.fillRect(this.dropHint.x - 1, row.y, 2, row.h)
            }
        }
        // 框选
        if (this.drag?.kind === 'marquee' && this.drag.moved) {
            const d = this.drag
            const x = Math.min(d.x0, d.x1), y = Math.min(d.y0, d.y1)
            ctx.fillStyle = C.accent
            ctx.globalAlpha = 0.15
            ctx.fillRect(x, y, Math.abs(d.x1 - d.x0), Math.abs(d.y1 - d.y0))
            ctx.globalAlpha = 1
            ctx.strokeStyle = C.accent
            ctx.strokeRect(x + 0.5, y + 0.5, Math.abs(d.x1 - d.x0), Math.abs(d.y1 - d.y0))
        }
        ctx.restore()
        // 吸附线
        if (this.snapLine != null) {
            const x = Math.round(this.tx(this.snapLine)) + 0.5
            ctx.strokeStyle = '#facc15'
            ctx.setLineDash([4, 3])
            ctx.beginPath(); ctx.moveTo(x, RULER); ctx.lineTo(x, H); ctx.stroke()
            ctx.setLineDash([])
        }
        this.drawRuler(ctx, W, C)
        // 播放头
        const px = Math.round(this.tx(this.time)) + 0.5
        if (px >= -10 && px <= W + 10) {
            ctx.strokeStyle = '#f43f5e'
            ctx.lineWidth = 1.5
            ctx.beginPath(); ctx.moveTo(px, 14); ctx.lineTo(px, H); ctx.stroke()
            ctx.lineWidth = 1
            ctx.fillStyle = '#f43f5e'
            ctx.beginPath()
            ctx.moveTo(px - 6, 6); ctx.lineTo(px + 6, 6); ctx.lineTo(px + 6, 14); ctx.lineTo(px, 20); ctx.lineTo(px - 6, 14)
            ctx.closePath(); ctx.fill()
        }
        this.syncHScroll()
    }

    P.syncHScroll = function () {
        const W = this.tlW || 800
        this.hInner.style.width = Math.max(W, this.maxScrollX() + W) + 'px'
        if (Math.abs(this.hScroll.scrollLeft - this.scrollX) > 1) {
            this._syncingScroll = true
            this.hScroll.scrollLeft = this.scrollX
            requestAnimationFrame(() => { this._syncingScroll = false })
        }
    }

    P.drawRuler = function (ctx, W, C) {
        ctx.fillStyle = C.surface
        ctx.fillRect(0, 0, W, RULER)
        ctx.fillStyle = C.line2
        ctx.fillRect(0, RULER - 1, W, 1)
        const fps = this.proj.fps
        const steps = [1 / fps, 2 / fps, 5 / fps, 10 / fps, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800]
        const step = steps.find(s => s * this.pps >= 70) ?? 3600
        const minor = step >= 1 ? step / (step % 5 === 0 || step === 1 ? 5 : 2) : step / 5
        const t0 = Math.max(0, Math.floor(this.xt(0) / minor) * minor), t1 = this.xt(W)
        ctx.font = '10.5px "Segoe UI", "Microsoft YaHei UI", sans-serif'
        ctx.textBaseline = 'top'
        for (let i = Math.round(t0 / minor); i * minor <= t1; i++) {
            const t = i * minor
            const x = Math.round(this.tx(t)) + 0.5
            const major = Math.abs(t / step - Math.round(t / step)) < 1e-6
            ctx.fillStyle = major ? C.text3 : C.line2
            ctx.fillRect(x - 0.5, major ? RULER - 12 : RULER - 6, 1, major ? 11 : 5)
            if (major) {
                ctx.fillStyle = C.text2
                ctx.fillText(rulerLabel(t, step, fps), x + 4, 5)
            }
        }
        // 预览范围末尾
        const ex = this.tx(this.duration())
        if (ex > 0 && ex < W) {
            ctx.fillStyle = C.accent
            ctx.globalAlpha = 0.6
            ctx.fillRect(Math.round(ex), RULER - 3, 1.5, 3)
            ctx.globalAlpha = 1
        }
    }

    P.drawClip = function (ctx, c, r, selected, C) {
        const x0 = this.tx(c.start), x1 = this.tx(clipEnd(c))
        const x = Math.max(x0, -4), w = Math.min(x1, this.tlW + 4) - x
        if (w <= 0) return
        const y = r.y + 3, hh = r.h - 7
        const col = COLORS[c.type] ?? '#64748b'
        ctx.save()
        ctx.beginPath()
        ctx.roundRect(x0, y, Math.max(1, x1 - x0), hh, 5)
        ctx.clip()
        ctx.fillStyle = col
        ctx.globalAlpha = 0.85
        ctx.fillRect(x, y, w, hh)
        ctx.globalAlpha = 1
        const asset = this.assets.get(c.media)
        // 缩略图条
        if ((c.type === 'video' || c.type === 'image') && asset?.thumbs.length) {
            const th = hh - 16, ty = y + 16
            const first = asset.thumbs[0].c
            const tw = Math.max(8, th * first.width / first.height)
            const startI = Math.floor((x - x0) / tw)
            for (let i = startI; x0 + i * tw < x + w; i++) {
                const tx = x0 + i * tw
                const st = c.type === 'image' ? 0 : srcTime(c, c.start + (i * tw + tw / 2) / this.pps)
                const th0 = nearestThumb(asset.thumbs, st)
                if (th0) ctx.drawImage(th0.c, tx, ty, tw, th)
            }
            ctx.fillStyle = 'rgba(0,0,0,.18)'
            ctx.fillRect(x, ty, w, th)
        }
        // 波形
        if ((c.type === 'audio' || (c.type === 'video' && !c.detached)) && asset?.peaks) {
            const isA = c.type === 'audio'
            const wy = isA ? y + 16 : y + hh - 14, wh = isA ? hh - 18 : 12
            const mid = isA ? wy + wh / 2 : wy + wh
            ctx.fillStyle = isA ? 'rgba(255,255,255,.78)' : 'rgba(255,255,255,.55)'
            const pk = asset.peaks, rate = asset.peakRate
            const vol = Math.min(2, c.volume ?? 1)
            for (let px = Math.max(0, Math.floor(x)); px < x + w; px++) {
                const s0 = srcTime(c, this.xt(px)), s1 = srcTime(c, this.xt(px + 1))
                let v = 0
                for (let k = Math.floor(s0 * rate); k <= Math.floor(s1 * rate); k++) if (pk[k] > v) v = pk[k]
                v = Math.min(1, v * vol)
                const a = v * (isA ? wh / 2 : wh)
                if (a < 0.5) continue
                if (isA) ctx.fillRect(px, mid - a, 1, a * 2)
                else ctx.fillRect(px, mid - a, 1, a)
            }
        }
        if (c.type === 'color') {
            ctx.fillStyle = c.color
            ctx.fillRect(x, y + 16, w, hh - 16)
        }
        if (c.type === 'text') {
            ctx.fillStyle = 'rgba(255,255,255,.14)'
            ctx.fillRect(x, y + 16, w, hh - 16)
            ctx.fillStyle = '#fff'
            ctx.font = 'bold 13px "Microsoft YaHei UI", sans-serif'
            ctx.textBaseline = 'middle'
            ctx.fillText((c.text || '').split('\n')[0], Math.max(x0, 0) + 8, y + 16 + (hh - 16) / 2, Math.max(10, w - 12))
        }
        // 标题条
        ctx.fillStyle = 'rgba(0,0,0,.28)'
        ctx.fillRect(x, y, w, 16)
        ctx.fillStyle = '#fff'
        ctx.font = '11px "Segoe UI", "Microsoft YaHei UI", sans-serif'
        ctx.textBaseline = 'middle'
        const lx = Math.max(x0, 0) + 6
        let label = clipName(this.proj, c)
        if ((c.speed ?? 1) !== 1) label = `${c.speed}× ` + label
        if (c.volume === 0 && c.type !== 'text' && c.type !== 'color' && c.type !== 'image') label = '(静音) ' + label
        if (asset?.media.offline) label = '[离线] ' + label
        ctx.fillText(label, lx, y + 8.5, Math.max(4, x1 - lx - 6))
        // 淡入淡出 / 溶解
        ctx.strokeStyle = 'rgba(255,255,255,.9)'
        ctx.lineWidth = 1.2
        if (c.fadeIn > 0) {
            const fw = c.fadeIn * this.pps
            ctx.fillStyle = 'rgba(0,0,0,.28)'
            ctx.beginPath(); ctx.moveTo(x0, y + 16); ctx.lineTo(x0 + fw, y + 16); ctx.lineTo(x0, y + hh); ctx.closePath(); ctx.fill()
            ctx.beginPath(); ctx.moveTo(x0, y + hh); ctx.lineTo(x0 + fw, y + 16); ctx.stroke()
        }
        if (c.fadeOut > 0) {
            const fw = c.fadeOut * this.pps
            ctx.fillStyle = 'rgba(0,0,0,.28)'
            ctx.beginPath(); ctx.moveTo(x1, y + 16); ctx.lineTo(x1 - fw, y + 16); ctx.lineTo(x1, y + hh); ctx.closePath(); ctx.fill()
            ctx.beginPath(); ctx.moveTo(x1 - fw, y + 16); ctx.lineTo(x1, y + hh); ctx.stroke()
        }
        if (c.dissolve > 0) {
            const fw = c.dissolve * this.pps
            const g = ctx.createLinearGradient(x0, 0, x0 + fw, 0)
            g.addColorStop(0, 'rgba(255,255,255,.45)'); g.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = g
            ctx.fillRect(x0, y, fw, hh)
        }
        ctx.restore()
        // 边框
        ctx.lineWidth = selected ? 2 : 1
        ctx.strokeStyle = selected ? '#fff' : 'rgba(0,0,0,.35)'
        ctx.beginPath()
        ctx.roundRect(x0 + 0.5, y + 0.5, Math.max(1, x1 - x0 - 1), hh - 1, 5)
        ctx.stroke()
        if (selected) {
            ctx.strokeStyle = C.accent
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.roundRect(x0 - 1, y - 1, Math.max(1, x1 - x0 + 2), hh + 2, 6)
            ctx.stroke()
            // 修剪把手
            ctx.fillStyle = '#fff'
            if (x1 - x0 > 18) {
                ctx.fillRect(x0 + 2, y + hh / 2 - 8, 3, 16)
                ctx.fillRect(x1 - 5, y + hh / 2 - 8, 3, 16)
            }
        }
    }

    // ---------- 命中测试 ----------
    P.hitClip = function (x, y) {
        const row = this.rowAt(y)
        if (!row || y < RULER) return null
        const t = this.xt(x)
        const cs = this.proj.clips.filter(c => c.track === row.tr.id)
        // 优先边缘
        for (const c of cs) {
            const x0 = this.tx(c.start), x1 = this.tx(clipEnd(c))
            if (x1 - x0 < 16) continue
            if (Math.abs(x - x0) <= EDGE && x < x1) return { c, row, edge: 'L' }
            if (Math.abs(x - x1) <= EDGE && x > x0) return { c, row, edge: 'R' }
        }
        const c = cs.find(c => t >= c.start && t < clipEnd(c))
        return c ? { c, row, edge: null } : { c: null, row }
    }

    // ---------- 吸附 ----------
    P.snapPoints = function (exclude) {
        const pts = [0, this.time]
        for (const c of this.proj.clips) if (!exclude.has(c.id)) pts.push(c.start, clipEnd(c))
        return pts
    }
    P.snapTime = function (t, pts, alt) {
        if (!this.snapOn || alt) return { t, snap: null }
        const th = 8 / this.pps
        let best = null, bd = th
        for (const p of pts) { const d = Math.abs(p - t); if (d < bd) { bd = d; best = p } }
        return best != null ? { t: best, snap: best } : { t, snap: null }
    }

    // ---------- 指针 ----------
    P.tlDown = function (e) {
        if (e.button === 1) { this.drag = { kind: 'pan', x: e.clientX, sx: this.scrollX }; this.tl.setPointerCapture(e.pointerId); return }
        if (e.button !== 0) return
        this.el.focus({ preventScroll: true })
        const { x, y } = this.tlPos(e)
        this.tl.setPointerCapture(e.pointerId)
        // 标尺 / 播放头
        const nearHead = Math.abs(x - this.tx(this.time)) <= 5
        if (y < RULER || (nearHead && !this.hitClip(x, y)?.edge)) {
            this.drag = { kind: 'scrub', wasPlaying: this.playing }
            if (this.playing) this.pause()
            this.seek(this.xt(x))
            return
        }
        const hit = this.hitClip(x, y)
        if (hit?.c) {
            const c = hit.c
            if (trackOf(this.proj, c)?.locked) { this.setSel([c.id]); return }
            if (e.ctrlKey || e.metaKey || e.shiftKey) {
                this.setSel(this.sel.includes(c.id) ? this.sel.filter(i => i !== c.id) : [...this.sel, c.id])
                if (!this.sel.includes(c.id)) return
            } else if (!this.sel.includes(c.id) || hit.edge) this.setSel([c.id])
            const ids = hit.edge ? [c.id] : this.sel.filter(id => { const k = this.clipById(id); return k && !trackOf(this.proj, k)?.locked })
            const orig = new Map(ids.map(id => { const k = this.clipById(id); return [id, { start: k.start, in: k.in, out: k.out, track: k.track }] }))
            this.drag = { kind: hit.edge ? 'trim' + hit.edge : 'move', c, ids, orig, x0: x, y0: y, t0: this.xt(x), row0: this.proj.tracks.indexOf(hit.row.tr), moved: false }
            return
        }
        this.drag = { kind: 'marquee', x0: x, y0: y, x1: x, y1: y, add: e.ctrlKey || e.shiftKey, base: [...this.sel], moved: false }
    }

    P.tlMove = function (e) {
        const { x, y } = this.tlPos(e)
        const d = this.drag
        if (!d) {
            // 光标
            const hit = y >= RULER ? this.hitClip(x, y) : null
            this.tl.style.cursor = y < RULER ? 'text' : hit?.edge ? 'ew-resize' : Math.abs(x - this.tx(this.time)) <= 5 ? 'col-resize' : hit?.c ? 'grab' : 'default'
            return
        }
        if (d.kind === 'pan') { this.setScrollX(d.sx - (e.clientX - d.x)); return }
        if (d.kind === 'scrub') { this.seek(this.xt(x)); this.autoEdge(x); return }
        if (d.kind === 'marquee') {
            d.x1 = x; d.y1 = y
            d.moved ||= Math.abs(d.x1 - d.x0) + Math.abs(d.y1 - d.y0) > 4
            if (d.moved) {
                const ta = this.xt(Math.min(d.x0, x)), tb = this.xt(Math.max(d.x0, x))
                const ya = Math.min(d.y0, y), yb = Math.max(d.y0, y)
                const rows = this.trackRows().filter(r => r.y + r.h > ya && r.y < yb).map(r => r.tr.id)
                const hitIds = this.proj.clips.filter(c => rows.includes(c.track) && clipEnd(c) > ta && c.start < tb).map(c => c.id)
                this.sel = d.add ? [...new Set([...d.base, ...hitIds])] : hitIds
                this.drawTimeline()
            }
            return
        }
        if (!d.moved && Math.abs(x - d.x0) < 3 && Math.abs(y - d.y0) < 3) return
        d.moved = true
        const p = this.proj, fps = p.fps
        const exclude = new Set(d.ids)
        const pts = this.snapPoints(exclude)
        let t = this.xt(x)
        this.snapLine = null
        if (d.kind === 'move') {
            let dt = t - d.t0
            const minStart = Math.min(...[...d.orig.values()].map(o => o.start))
            dt = Math.max(dt, -minStart)
            // 吸附：任一选中片段的首尾
            if (this.snapOn && !e.altKey) {
                let best = null, bd = 8 / this.pps
                for (const id of d.ids) {
                    const o = d.orig.get(id), k = this.clipById(id)
                    const dur = clipDur(k)
                    for (const edge of [o.start + dt, o.start + dt + dur]) {
                        for (const pt of pts) { const dd = Math.abs(pt - edge); if (dd < bd) { bd = dd; best = { dt: dt + pt - edge, pt } } }
                    }
                }
                if (best) { dt = Math.max(best.dt, -minStart); this.snapLine = best.pt }
            }
            dt = Math.round(dt * fps) / fps
            // 跨轨道
            const row = this.rowAt(y)
            const dRow = row ? p.tracks.indexOf(row.tr) - d.row0 : 0
            const ok = d.ids.every(id => {
                const tr = p.tracks[p.tracks.findIndex(t => t.id === d.orig.get(id).track) + dRow]
                return compatible(this.clipById(id), tr) && !tr.locked
            })
            for (const id of d.ids) {
                const k = this.clipById(id), o = d.orig.get(id)
                k.start = Math.max(0, o.start + dt)
                k.track = ok ? p.tracks[p.tracks.findIndex(t => t.id === o.track) + dRow].id : o.track
            }
            this.tl.style.cursor = 'grabbing'
        } else {
            const c = d.c, o = d.orig.get(c.id)
            const sp = c.speed || 1
            const neighbors = p.clips.filter(k => k.track === c.track && k !== c)
            const snapped = this.snapTime(t, pts, e.altKey)
            t = Math.round(snapped.t * fps) / fps
            this.snapLine = snapped.snap
            const oEnd = o.start + (o.out - o.in) / sp
            const media = c.type === 'video' || c.type === 'audio'
            if (d.kind === 'trimL') {
                const prevEnd = Math.max(0, ...neighbors.filter(k => clipEnd(k) <= o.start + 1e-4).map(clipEnd))
                let lo = prevEnd
                if (media) lo = Math.max(lo, o.start - o.in / sp)
                t = clamp(t, lo, oEnd - 1 / fps)
                c.start = t
                c.in = o.in + (t - o.start) * sp
            } else {
                const nextStart = Math.min(Infinity, ...neighbors.filter(k => k.start >= oEnd - 1e-4).map(k => k.start))
                let hi = nextStart
                if (media) hi = Math.min(hi, o.start + (maxOut(p, c) - o.in) / sp)
                t = clamp(t, o.start + 1 / fps, hi)
                c.out = o.in + (t - o.start) * sp
            }
            // 修剪时预览入点 / 出点画面
            if (!this.playing) { this.time = d.kind === 'trimL' ? c.start : Math.max(c.start, clipEnd(c) - 1 / fps); this.onTimeChange() }
        }
        this.autoEdge(x)
        this.invalidateFrames(d.ids)
        this.schedulePreview()
        this.drawTimeline()
        this.refreshInspectorLive?.()
    }

    // 拖到边缘时自动滚动
    P.autoEdge = function (x) {
        const W = this.tlW
        if (x > W - 30) this.setScrollX(this.scrollX + 12)
        else if (x < 30 && this.scrollX > 0) this.setScrollX(this.scrollX - 12)
    }

    P.tlUp = function (e) {
        const d = this.drag
        this.drag = null
        this.snapLine = null
        try { this.tl.releasePointerCapture(e.pointerId) } catch { /* ignore */ }
        if (!d) return
        if (d.kind === 'scrub') { if (d.wasPlaying) this.play(); this.drawTimeline(); return }
        if (d.kind === 'marquee') {
            if (!d.moved) {
                if (!d.add) this.setSel([])
                this.seek(this.xt(d.x0))
            } else this.setSel(this.sel)
            this.drawTimeline()
            return
        }
        if (d.kind === 'pan') return
        if (!d.moved) { this.drawTimeline(); return }
        if (d.kind === 'move') {
            const ids = new Set(d.ids)
            for (const id of d.ids) {
                const k = this.clipById(id)
                clearRange(this.proj, k.track, k.start, clipEnd(k), ids)
            }
            this.change('移动片段')
        } else this.change('修剪片段')
    }

    P.tlDbl = function (e) {
        const { x, y } = this.tlPos(e)
        const hit = this.hitClip(x, y)
        if (hit?.c) {
            this.setSel([hit.c.id])
            if (hit.c.type === 'text') requestAnimationFrame(() => this.panels.querySelector('textarea')?.focus())
        }
    }

    P.tlWheel = function (e) {
        e.preventDefault()
        const { x } = this.tlPos(e)
        if (e.ctrlKey || e.metaKey) { this.setZoom(this.pps * Math.exp(-e.deltaY * 0.0022), x); return }
        const overflowY = this.contentH() + RULER > this.tlH
        if (!e.shiftKey && overflowY && !e.deltaX && Math.abs(e.deltaY) > 0) {
            this.scrollY = clamp(this.scrollY + e.deltaY * 0.5, 0, Math.max(0, this.contentH() + RULER - this.tlH + 20))
            this.heads.style.transform = `translateY(${-this.scrollY}px)`
            this.drawTimeline()
            return
        }
        this.setScrollX(this.scrollX + (e.deltaX || e.deltaY))
    }

    P.tlContext = function (e) {
        const { x, y } = this.tlPos(e)
        if (y < RULER) return contextMenu(e, [{ label: '缩放到适合', icon: 'maximize-2', run: () => this.zoomFit() }])
        const hit = this.hitClip(x, y)
        if (hit?.c) {
            if (!this.sel.includes(hit.c.id)) this.setSel([hit.c.id])
            return contextMenu(e, this.clipMenu(hit.c))
        }
        const t = this.xt(x)
        const row = hit?.row
        contextMenu(e, [
            { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', disabled: () => !this.clipboard, run: () => { this.seek(t); this.paste(row?.tr) } },
            row?.tr.type === 'video' ? { label: '在此添加字幕', icon: 'captions', run: () => this.addText('subtitle', { start: t, track: row.tr.id }) } : null,
            row ? { label: '删除此处间隙', icon: 'arrow-left-to-line', run: () => this.closeGap(row.tr, t) } : null,
            '-',
            { label: '全选', icon: 'list-checks', key: 'Ctrl+A', run: () => this.selectAll() },
            { label: '缩放到适合', icon: 'maximize-2', run: () => this.zoomFit() },
        ])
    }

    P.tlDrop = function (e) {
        e.preventDefault()
        const pos = this.tlPos(e)
        this.dropHint = null
        const row = this.rowAt(pos.y)
        const t = Math.max(0, this.xt(pos.x))
        const mid = e.dataTransfer.getData('application/x-lite-media')
        if (mid) {
            const m = this.proj.media.find(x => x.id === mid)
            if (m) this.addMediaClip(m, { start: t, track: row?.tr })
            return
        }
        const files = [...e.dataTransfer.files]
        this.importFiles(files, { start: t, track: row?.tr })
    }
}

function nearestThumb(thumbs, t) {
    let lo = 0, hi = thumbs.length - 1
    while (lo < hi) { const m = (lo + hi + 1) >> 1; if (thumbs[m].t <= t) lo = m; else hi = m - 1 }
    const a = thumbs[lo], b = thumbs[lo + 1]
    return b && Math.abs(b.t - t) < Math.abs(a.t - t) ? b : a
}

function rulerLabel(t, step, fps) {
    const m = Math.floor(t / 60), s = Math.floor(t % 60)
    const base = `${m}:${String(s).padStart(2, '0')}`
    if (step >= 1) return base
    const f = Math.round((t - Math.floor(t)) * fps)
    return f ? `${base}:${String(f).padStart(2, '0')}` : base
}

export { RULER, HEAD_W, fmtTC, mediaOf }
