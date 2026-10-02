// 钢琴卷帘：键盘 / 标尺 / 音符网格 / 力度条（Canvas 绘制）
import { h, clamp } from '../../core/dom.js'
import { contextMenu } from '../../core/menu.js'
import { noteName, isBlack, isDrum, DRUMS, forEachBar, sigAt } from './smf.js'
import { uid } from '../../core/dom.js'

export const KB_W = 64, KB_W_DRUM = 124, RULER_H = 26, VEL_H = 84

// 自动适配 devicePixelRatio 的画布
function canvasBox(cls, onResize) {
    const c = h('canvas.' + cls)
    const box = { c, g: c.getContext('2d'), w: 1, h: 1 }
    box.fit = () => {
        const r = c.parentElement ? c.getBoundingClientRect() : { width: 1, height: 1 }
        const dpr = devicePixelRatio || 1
        const w = Math.max(1, Math.round(r.width)), hh = Math.max(1, Math.round(r.height))
        if (w !== box.w || hh !== box.h || c.width !== Math.round(w * dpr)) {
            box.w = w; box.h = hh
            c.width = Math.round(w * dpr); c.height = Math.round(hh * dpr)
            onResize?.()
        }
        box.g.setTransform(dpr, 0, 0, dpr, 0, 0)
    }
    return box
}

export function installRoll(Ed) {
    const P = Ed.prototype

    P.buildRoll = function () {
        const redraw = () => this.drawRoll()
        this.kb = canvasBox('mi-kb', redraw)
        this.ruler = canvasBox('mi-ruler', redraw)
        this.grid = canvasBox('mi-grid', redraw)
        this.vel = canvasBox('mi-vel', redraw)
        this.velLabel = h('div.mi-vel-label', '力度')
        this.rollCorner = h('div.mi-corner')
        this.rollEl = h('div.mi-roll', this.rollCorner, this.ruler.c, this.kb.c, this.grid.c, this.velLabel, this.vel.c)
        const ro = new ResizeObserver(() => { this.clampView(); this.drawRoll() })
        ro.observe(this.rollEl)
        this.onDispose(() => ro.disconnect())
        this.bindGrid()
        this.bindKeyboard()
        this.bindRuler()
        this.bindVelocity()
        for (const b of [this.kb, this.ruler, this.grid, this.vel]) this.listen(b.c, 'wheel', e => this.onWheel(e, b), { passive: false })
        return this.rollEl
    }

    // ---------- 坐标 ----------
    P.kbWidth = function () { return this.track && isDrum(this.track) ? KB_W_DRUM : KB_W }
    P.xOf = function (tick) { return tick * this.view.zx - this.view.sx }
    P.tickAt = function (x) { return Math.max(0, (x + this.view.sx) / this.view.zx) }
    P.yOf = function (pitch) { return (127 - pitch) * this.view.rowH - this.view.sy }
    P.pitchAt = function (y) { return clamp(127 - Math.floor((y + this.view.sy) / this.view.rowH), 0, 127) }
    P.snapTicks = function () { return this.snap ? Math.max(1, Math.round(this.song.ppq * 4 * this.snap)) : 0 }
    P.snapRound = function (t) { const s = this.snapTicks(); return s ? Math.round(t / s) * s : Math.round(t) }
    P.snapFloor = function (t) { const s = this.snapTicks(); return s ? Math.floor(t / s) * s : Math.round(t) }

    P.clampView = function () {
        const v = this.view
        const H = this.grid.h || 300
        v.rowH = clamp(v.rowH, 5, 40)
        v.zx = clamp(v.zx, 0.004, 2)
        v.sy = clamp(v.sy, 0, Math.max(0, 128 * v.rowH - H))
        v.sx = clamp(v.sx, 0, Math.max(0, (this.endTick() + this.song.ppq * 32) * v.zx - (this.grid.w || 400) * 0.5))
    }
    // 垂直滚动到让某个音高居中
    P.centerPitch = function (p) {
        this.view.sy = (127 - p) * this.view.rowH - (this.grid.h || 400) / 2
        this.clampView()
    }
    P.centerOnTrack = function () {
        const ns = this.track?.notes ?? []
        if (!ns.length) { this.centerPitch(isDrum(this.track ?? {}) ? 42 : 64); return }
        let lo = 127, hi = 0
        for (const n of ns) { lo = Math.min(lo, n.pitch); hi = Math.max(hi, n.pitch) }
        this.centerPitch(Math.round((lo + hi) / 2))
    }
    P.zoomX = function (k, anchorX = (this.grid.w || 400) / 2) {
        const t = this.tickAt(anchorX)
        this.view.zx = clamp(this.view.zx * k, 0.004, 2)
        this.view.sx = t * this.view.zx - anchorX
        this.clampView()
        this.drawRoll()
        this.drawLanes()
    }
    P.zoomY = function (k, anchorY = (this.grid.h || 400) / 2) {
        const p = (anchorY + this.view.sy) / this.view.rowH
        this.view.rowH = clamp(this.view.rowH * k, 5, 40)
        this.view.sy = p * this.view.rowH - anchorY
        this.clampView()
        this.drawRoll()
    }
    P.onWheel = function (e, box) {
        e.preventDefault()
        const r = box.c.getBoundingClientRect()
        const dy = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY, dx = e.deltaMode === 1 ? e.deltaX * 16 : e.deltaX
        if (e.ctrlKey) this.zoomX(Math.exp(-dy * 0.0022), e.clientX - r.left)
        else if (e.altKey) this.zoomY(Math.exp(-dy * 0.0022), box === this.grid || box === this.kb ? e.clientY - r.top : undefined)
        else {
            if (e.shiftKey || box === this.ruler || box === this.vel) this.view.sx += dy + dx
            else { this.view.sy += dy; this.view.sx += dx }
            this.clampView()
            this.drawRoll()
            this.drawLanes()
        }
    }

    // ---------- 绘制 ----------
    P.drawRoll = function () {
        if (!this.song || !this.grid) return
        cancelAnimationFrame(this._rollRAF)
        this._rollRAF = 0
        const kw = this.kbWidth()
        if (this._kbw !== kw) { this._kbw = kw; this.rollEl.style.setProperty('--kbw', kw + 'px') }
        for (const b of [this.kb, this.ruler, this.grid, this.vel]) b.fit()
        this.drawGrid()
        this.drawKeyboard()
        this.drawRuler()
        this.drawVelocity()
    }
    // 下一帧重绘（拖动中合并多次请求）
    P.drawSoon = function () {
        if (this._rollRAF) return
        this._rollRAF = requestAnimationFrame(() => { this._rollRAF = 0; this.drawRoll() })
    }

    P.visibleTicks = function () { return [this.tickAt(0), this.tickAt(this.grid.w)] }

    // 竖向网格线：小节 / 拍 / 细分
    P.drawTimeLines = function (g, H, { sub = true } = {}) {
        const pal = this.pal, [t0, t1] = this.visibleTicks()
        const snap = this.snapTicks()
        forEachBar(this.song, 0, t1 + 1, b => {
            if (b.tick + b.len < t0) return
            // 细分
            const step = snap && snap * this.view.zx >= 7 && sub ? snap : 0
            if (step) {
                g.fillStyle = pal.lineSub
                for (let t = b.tick + step; t < b.tick + b.len; t += step) {
                    if ((t - b.tick) % b.beat === 0) continue
                    g.fillRect(Math.round(this.xOf(t)), 0, 1, H)
                }
            }
            if (b.beat * this.view.zx >= 5) {
                g.fillStyle = pal.lineBeat
                for (let i = 1; i < b.num; i++) g.fillRect(Math.round(this.xOf(b.tick + i * b.beat)), 0, 1, H)
            }
            const bx = Math.round(this.xOf(b.tick))
            if (b.len * this.view.zx >= 4 || b.bar % 4 === 1) { g.fillStyle = pal.lineBar; g.fillRect(bx, 0, 1, H) }
        })
    }

    P.drawGrid = function () {
        const { g, w: W, h: H } = this.grid
        const pal = this.pal, v = this.view, rh = v.rowH
        g.fillStyle = pal.rollWhite
        g.fillRect(0, 0, W, H)
        const pTop = this.pitchAt(0), pBot = this.pitchAt(H)
        const drum = isDrum(this.track)
        for (let p = pTop; p >= pBot; p--) {
            const y = this.yOf(p)
            if (!drum && isBlack(p)) { g.fillStyle = pal.rollBlack; g.fillRect(0, y, W, rh) }
            else if (drum && !DRUMS[p]) { g.fillStyle = pal.rollBlack; g.fillRect(0, y, W, rh) }
            if (p % 12 === 0 && !drum) { g.fillStyle = pal.lineBar; g.fillRect(0, Math.round(y + rh) - 1, W, 1) }
            else if (p % 12 === 5 || drum) { g.fillStyle = pal.lineSub; g.fillRect(0, Math.round(y + rh) - 1, W, 1) }
        }
        // 选中音高（键盘上按下 / 悬停）
        if (this.hoverPitch != null) { g.fillStyle = pal.hoverRow; g.fillRect(0, this.yOf(this.hoverPitch), W, rh) }
        this.drawTimeLines(g, H)
        // 循环区域
        if (this.loop.end > this.loop.start) {
            const x0 = this.xOf(this.loop.start), x1 = this.xOf(this.loop.end)
            g.fillStyle = this.loop.on ? pal.loopFill : pal.loopFillOff
            g.fillRect(x0, 0, x1 - x0, H)
        }
        const [t0, t1] = this.visibleTicks()
        // 其他轨道的“幽灵”音符
        if (this.ghosts) {
            for (const t of this.song.tracks) {
                if (t === this.track || isDrum(t) !== drum) continue
                g.fillStyle = t.color
                g.globalAlpha = 0.22
                for (const n of t.notes) {
                    if (n.tick > t1 || n.tick + n.dur < t0 || n.pitch > pTop || n.pitch < pBot) continue
                    g.fillRect(this.xOf(n.tick), this.yOf(n.pitch) + 1, Math.max(2, n.dur * v.zx), rh - 2)
                }
                g.globalAlpha = 1
            }
        }
        // 当前轨道音符
        const t = this.track
        if (t) {
            const sel = this.sel
            const rad = Math.min(3, rh / 4)
            for (const n of t.notes) {
                if (n.tick > t1 || n.tick + n.dur < t0 || n.pitch > pTop || n.pitch < pBot) continue
                const x = this.xOf(n.tick), y = this.yOf(n.pitch) + 0.5
                const w = Math.max(3, n.dur * v.zx - 1), hh = rh - 1
                const on = sel.has(n.id)
                g.fillStyle = velColor(t.color, n.vel, pal.dark)
                roundRect(g, x + 0.5, y, w, hh, rad)
                g.fill()
                g.lineWidth = on ? 1.6 : 1
                g.strokeStyle = on ? pal.selStroke : shade(t.color, pal.dark ? -0.45 : -0.35)
                g.stroke()
                if (on) { g.fillStyle = 'rgba(255,255,255,.28)'; g.fill() }
                if (w > 28 && rh >= 11) {
                    g.fillStyle = contrastInk(t.color, n.vel)
                    g.font = `${Math.min(11, rh - 3)}px system-ui, sans-serif`
                    g.textBaseline = 'middle'
                    g.save()
                    g.beginPath(); g.rect(x, y, w - 3, hh); g.clip()
                    g.fillText(drum ? (DRUMS[n.pitch] ?? noteName(n.pitch)) : noteName(n.pitch), x + 4, y + hh / 2 + 0.5)
                    g.restore()
                }
            }
        }
        // 框选
        if (this.marquee) {
            const m = this.marquee
            g.fillStyle = pal.accentSoft
            g.strokeStyle = pal.accent
            g.lineWidth = 1
            g.fillRect(m.x, m.y, m.w, m.h)
            g.strokeRect(m.x + 0.5, m.y + 0.5, m.w, m.h)
        }
        // 光标与播放头
        const cx = Math.round(this.xOf(this.cursor)) + 0.5
        g.strokeStyle = pal.cursor
        g.globalAlpha = 0.6
        g.setLineDash([3, 3])
        g.beginPath(); g.moveTo(cx, 0); g.lineTo(cx, H); g.stroke()
        g.setLineDash([])
        g.globalAlpha = 1
        if (this.playing) {
            const px = Math.round(this.xOf(this.playTick)) + 0.5
            g.strokeStyle = pal.playhead
            g.lineWidth = 1.5
            g.beginPath(); g.moveTo(px, 0); g.lineTo(px, H); g.stroke()
            g.lineWidth = 1
        }
    }

    P.drawKeyboard = function () {
        const { g, w: W, h: H } = this.kb
        const pal = this.pal, rh = this.view.rowH
        const drum = isDrum(this.track)
        g.fillStyle = pal.keyWhite
        g.fillRect(0, 0, W, H)
        const pTop = this.pitchAt(0), pBot = this.pitchAt(H)
        g.textBaseline = 'middle'
        for (let p = pTop; p >= pBot; p--) {
            const y = this.yOf(p)
            const pressed = this.kbDown === p
            if (drum) {
                g.fillStyle = pressed ? pal.accent : DRUMS[p] ? pal.keyWhite : pal.keyDrumEmpty
                g.fillRect(0, y, W, rh)
                g.fillStyle = pal.keyLine
                g.fillRect(0, Math.round(y + rh) - 1, W, 1)
                if (rh >= 9) {
                    g.font = `${Math.min(11.5, rh - 2)}px system-ui, sans-serif`
                    g.fillStyle = pressed ? '#fff' : DRUMS[p] ? pal.keyInk : pal.keyInkDim
                    g.fillText(DRUMS[p] ?? noteName(p), 6, y + rh / 2 + 0.5)
                    if (DRUMS[p]) { g.fillStyle = pal.keyInkDim; g.textAlign = 'right'; g.fillText(String(p), W - 5, y + rh / 2 + 0.5); g.textAlign = 'left' }
                }
                continue
            }
            if (isBlack(p)) {
                g.fillStyle = pressed ? pal.accent : pal.keyBlack
                g.fillRect(0, y, W * 0.62, rh)
                g.fillStyle = pal.keyLine
                g.fillRect(W * 0.62, Math.round(y + rh / 2), W * 0.38, 1)
            } else {
                if (pressed) { g.fillStyle = pal.accent; g.fillRect(0, y, W, rh) }
                // 白键分隔线（E/F 与 B/C 之间）
                if (p % 12 === 0 || p % 12 === 5) { g.fillStyle = pal.keyLine; g.fillRect(0, Math.round(y + rh) - 1, W, 1) }
                if (p % 12 === 0 && rh >= 8) {
                    g.font = `600 ${Math.min(11, rh - 1)}px system-ui, sans-serif`
                    g.fillStyle = pressed ? '#fff' : pal.keyInk
                    g.textAlign = 'right'
                    g.fillText(noteName(p), W - 5, y + rh / 2 + 0.5)
                    g.textAlign = 'left'
                }
            }
        }
        g.fillStyle = pal.keyLine
        g.fillRect(W - 1, 0, 1, H)
    }

    P.drawRuler = function () {
        const { g, w: W, h: H } = this.ruler
        const pal = this.pal
        g.fillStyle = pal.rulerBg
        g.fillRect(0, 0, W, H)
        const [t0, t1] = this.visibleTicks()
        // 循环区
        if (this.loop.end > this.loop.start) {
            const x0 = this.xOf(this.loop.start), x1 = this.xOf(this.loop.end)
            g.fillStyle = this.loop.on ? pal.loopBar : pal.loopBarOff
            g.fillRect(x0, 0, x1 - x0, 7)
        }
        g.font = '11px system-ui, sans-serif'
        g.textBaseline = 'alphabetic'
        let lastLabel = -1e9
        forEachBar(this.song, 0, t1 + 1, b => {
            if (b.tick + b.len < t0) return
            const x = Math.round(this.xOf(b.tick))
            g.fillStyle = pal.rulerTick
            g.fillRect(x, 8, 1, H - 8)
            if (b.beat * this.view.zx >= 10) for (let i = 1; i < b.num; i++) g.fillRect(Math.round(this.xOf(b.tick + i * b.beat)), H - 6, 1, 6)
            if (x - lastLabel >= 28) {
                g.fillStyle = pal.rulerInk
                g.fillText(String(b.bar), x + 4, H - 8)
                lastLabel = x
            }
        })
        // 拍号变化标记
        for (const s of this.song.timeSig) {
            if (s.tick === 0) continue
            const x = this.xOf(s.tick)
            if (x < -30 || x > W) continue
            g.fillStyle = pal.accent
            g.fillText(`${s.num}/${s.den}`, x + 4, 18)
        }
        g.fillStyle = pal.keyLine
        g.fillRect(0, H - 1, W, 1)
        // 光标三角
        const cx = this.xOf(this.cursor)
        g.fillStyle = pal.cursor
        g.beginPath(); g.moveTo(cx - 5, H - 9); g.lineTo(cx + 5, H - 9); g.lineTo(cx, H - 2); g.closePath(); g.fill()
        if (this.playing) {
            const px = this.xOf(this.playTick)
            g.fillStyle = pal.playhead
            g.fillRect(Math.round(px) - 0.5, 0, 1.5, H)
        }
    }

    P.drawVelocity = function () {
        const { g, w: W, h: H } = this.vel
        const pal = this.pal
        g.fillStyle = pal.velBg
        g.fillRect(0, 0, W, H)
        g.fillStyle = pal.lineSub
        for (const f of [0.25, 0.5, 0.75]) g.fillRect(0, Math.round(4 + (H - 8) * f), W, 1)
        this.drawTimeLines(g, H, { sub: false })
        const t = this.track
        if (!t) return
        const [t0, t1] = this.visibleTicks()
        const anySel = this.sel.size > 0
        for (const n of t.notes) {
            if (n.tick > t1 || n.tick < t0 - 10) continue
            const x = Math.round(this.xOf(n.tick))
            const hh = Math.max(2, (H - 8) * n.vel / 127)
            const on = this.sel.has(n.id)
            g.globalAlpha = anySel && !on ? 0.4 : 1
            g.fillStyle = on ? pal.accent : velColor(t.color, n.vel, pal.dark)
            g.fillRect(x, H - 4 - hh, 3, hh)
            g.beginPath(); g.arc(x + 1.5, H - 4 - hh, 3, 0, Math.PI * 2); g.fill()
        }
        g.globalAlpha = 1
        g.fillStyle = pal.keyLine
        g.fillRect(0, 0, W, 1)
    }

    // ---------- 命中测试 ----------
    P.noteAt = function (x, y) {
        const t = this.track
        if (!t) return null
        const tick = this.tickAt(x), p = this.pitchAt(y)
        const tol = 3 / this.view.zx
        for (let i = t.notes.length - 1; i >= 0; i--) {
            const n = t.notes[i]
            if (n.pitch === p && tick >= n.tick - tol * 0.3 && tick <= n.tick + Math.max(n.dur, 3 / this.view.zx) + tol * 0.3) return n
        }
        return null
    }
    P.isResizeZone = function (n, x) {
        const xr = this.xOf(n.tick + n.dur)
        const w = n.dur * this.view.zx
        return x >= xr - Math.min(7, Math.max(3, w / 3)) && x <= xr + 3
    }

    // ---------- 网格交互 ----------
    P.bindGrid = function () {
        const c = this.grid.c
        const pos = e => { const r = c.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top } }
        this.listen(c, 'pointermove', e => {
            if (this.drag) return
            const { x, y } = pos(e)
            const n = this.noteAt(x, y)
            c.style.cursor = this.tool === 'erase' ? 'cell'
                : n ? (this.isResizeZone(n, x) ? 'ew-resize' : 'grab')
                : this.tool === 'draw' ? 'copy' : 'default'
            const hp = this.pitchAt(y)
            if (hp !== this.hoverPitch) { this.hoverPitch = hp; this.drawSoon() }
        })
        this.listen(c, 'pointerleave', () => { if (!this.drag) { this.hoverPitch = null; this.drawSoon() } })
        this.listen(c, 'dblclick', e => {
            if (this.tool !== 'select') return
            const { x, y } = pos(e)
            if (this.noteAt(x, y)) return
            this.addNoteAt(x, y)
            this.commit('添加音符')
        })
        this.listen(c, 'contextmenu', e => {
            const { x, y } = pos(e)
            const n = this.noteAt(x, y)
            if (n && !this.sel.has(n.id)) { this.sel = new Set([n.id]); this.afterSel() }
            contextMenu(e, this.noteMenuItems())
        })
        this.listen(c, 'pointerdown', e => {
            if (e.button === 2) return
            this.el.focus({ preventScroll: true })
            const { x, y } = pos(e)
            c.setPointerCapture(e.pointerId)
            // 中键：平移
            if (e.button === 1) {
                e.preventDefault()
                this.drag = { mode: 'pan', x, y, sx: this.view.sx, sy: this.view.sy }
                return
            }
            if (!this.track) return
            const hit = this.noteAt(x, y)
            if (this.tool === 'erase') {
                this.drag = { mode: 'erase', removed: 0 }
                this.eraseAt(x, y)
                return
            }
            if (hit) {
                if (e.shiftKey) {
                    const s = new Set(this.sel)
                    if (s.has(hit.id)) s.delete(hit.id); else s.add(hit.id)
                    this.sel = s
                    if (!s.has(hit.id)) { this.afterSel(); return }
                } else if (!this.sel.has(hit.id)) this.sel = new Set([hit.id])
                // Ctrl 拖动：复制
                if ((e.ctrlKey || e.altKey) && !this.isResizeZone(hit, x)) {
                    const copies = this.selNotes().map(n => ({ ...n, id: uid('n') }))
                    const map = new Map(this.selNotes().map((n, i) => [n.id, copies[i]]))
                    this.track.notes.push(...copies)
                    this.sel = new Set(copies.map(n => n.id))
                    this.startNoteDrag(map.get(hit.id), x, y, 'move', true)
                } else this.startNoteDrag(hit, x, y, this.isResizeZone(hit, x) ? 'resize' : 'move')
                this.afterSel()
                this.previewNote(hit)
                return
            }
            if (this.tool === 'draw') {
                const n = this.addNoteAt(x, y)
                this.startNoteDrag(n, x, y, 'resize', true)
                this.drag.created = true
                return
            }
            // 空白处：框选
            this.drag = { mode: 'marquee', x, y, base: e.shiftKey ? new Set(this.sel) : new Set() }
            if (!e.shiftKey && this.sel.size) { this.sel = new Set(); this.afterSel() }
            // 单击空白也移动光标
            if (!this.playing) { this.cursor = this.snapRound(this.tickAt(x)); this.updatePosition() }
        })
        this.listen(c, 'pointermove', e => {
            const d = this.drag
            if (!d) return
            const { x, y } = pos(e)
            if (d.mode === 'pan') {
                this.view.sx = d.sx - (x - d.x)
                this.view.sy = d.sy - (y - d.y)
                this.clampView()
                this.drawSoon()
                this.drawLanes()
            } else if (d.mode === 'erase') this.eraseAt(x, y)
            else if (d.mode === 'marquee') {
                const x0 = Math.min(d.x, x), y0 = Math.min(d.y, y)
                this.marquee = { x: x0, y: y0, w: Math.abs(x - d.x), h: Math.abs(y - d.y) }
                const ta = this.tickAt(x0), tb = this.tickAt(x0 + this.marquee.w)
                const pa = this.pitchAt(y0 + this.marquee.h), pb = this.pitchAt(y0)
                const s = new Set(d.base)
                for (const n of this.track.notes) if (n.pitch >= pa && n.pitch <= pb && n.tick < tb && n.tick + n.dur > ta) s.add(n.id)
                this.sel = s
                this.drawSoon()
            } else if (d.mode === 'move' || d.mode === 'resize') this.moveNoteDrag(x, y, e)
        })
        const end = () => {
            const d = this.drag
            if (!d) return
            this.drag = null
            if (d.mode === 'marquee') { this.marquee = null; this.afterSel() }
            else if (d.mode === 'erase') { if (d.removed) { this.commit('删除音符'); this.afterEdit() } }
            else if (d.mode === 'move' || d.mode === 'resize') {
                if (d.mode === 'resize') this.noteLen = d.anchor.dur
                if (d.changed || d.forceCommit) {
                    this.sortNotes()
                    this.commit(d.created ? '添加音符' : d.copy ? '复制音符' : d.mode === 'resize' ? '调整时值' : '移动音符')
                    this.afterEdit()
                }
            }
            this.drawRoll()
        }
        this.listen(c, 'pointerup', end)
        this.listen(c, 'pointercancel', end)
    }

    P.addNoteAt = function (x, y) {
        const tick = this.snapFloor(this.tickAt(x))
        const n = { id: uid('n'), tick, dur: this.noteLen || this.snapTicks() || this.song.ppq / 2, pitch: this.pitchAt(y), vel: this.newVel ?? 100 }
        this.track.notes.push(n)
        this.sel = new Set([n.id])
        this.previewNote(n)
        this.afterEdit(true)
        return n
    }

    P.startNoteDrag = function (anchor, x, y, mode, forceCommit = false) {
        const orig = new Map(this.selNotes().map(n => [n.id, { tick: n.tick, dur: n.dur, pitch: n.pitch }]))
        if (!orig.has(anchor.id)) orig.set(anchor.id, { tick: anchor.tick, dur: anchor.dur, pitch: anchor.pitch })
        this.drag = { mode, anchor, orig, x, y, tick0: this.tickAt(x), pitch0: this.pitchAt(y), forceCommit, copy: forceCommit && mode === 'move', lastPitch: anchor.pitch }
    }
    P.moveNoteDrag = function (x, y, e) {
        const d = this.drag, a = d.orig.get(d.anchor.id)
        const raw = this.tickAt(x) - d.tick0
        const free = e.shiftKey && e.altKey
        const snapOff = free || !this.snap
        if (d.mode === 'move') {
            let dt = snapOff ? Math.round(raw) : this.snapRound(a.tick + raw) - a.tick
            let dp = this.pitchAt(y) - d.pitch0
            // 约束在合法范围
            let minT = Infinity, minP = 127, maxP = 0
            for (const [, o] of d.orig) { minT = Math.min(minT, o.tick); minP = Math.min(minP, o.pitch); maxP = Math.max(maxP, o.pitch) }
            dt = Math.max(dt, -minT)
            dp = clamp(dp, -minP, 127 - maxP)
            if (dt || dp) d.changed = true
            for (const n of this.track.notes) {
                const o = d.orig.get(n.id)
                if (!o) continue
                n.tick = o.tick + dt
                n.pitch = o.pitch + dp
            }
            if (d.anchor.pitch !== d.lastPitch) { d.lastPitch = d.anchor.pitch; this.previewNote(d.anchor) }
        } else {
            const minDur = this.snapTicks() || Math.max(10, Math.round(this.song.ppq / 32))
            const end0 = a.tick + a.dur
            const dd = (snapOff ? Math.round(end0 + raw) : this.snapRound(end0 + raw)) - end0
            if (dd) d.changed = true
            for (const n of this.track.notes) {
                const o = d.orig.get(n.id)
                if (o) n.dur = Math.max(snapOff ? 10 : minDur, o.dur + dd)
            }
        }
        this.drawSoon()
        this.updateNotePanel?.()
    }

    P.eraseAt = function (x, y) {
        const n = this.noteAt(x, y)
        if (!n) return
        this.track.notes.splice(this.track.notes.indexOf(n), 1)
        this.sel.delete(n.id)
        this.drag.removed++
        this.drawSoon()
    }

    // ---------- 键盘（试听） ----------
    P.bindKeyboard = function () {
        const c = this.kb.c
        const pitchOf = e => this.pitchAt(e.clientY - c.getBoundingClientRect().top)
        let down = false
        const on = p => {
            if (this.kbDown === p) return
            off()
            this.kbDown = p
            const t = this.track
            this.engineNoteOn(t, p, 100)
            this.drawKeyboard()
        }
        const off = () => {
            if (this.kbDown == null) return
            this.engine.noteOff(this.track?.channel ?? 0, this.kbDown)
            this.kbDown = null
            this.drawKeyboard()
        }
        this.listen(c, 'pointerdown', e => { if (e.button) return; down = true; c.setPointerCapture(e.pointerId); on(pitchOf(e)) })
        this.listen(c, 'pointermove', e => {
            if (down) on(pitchOf(e))
            const hp = pitchOf(e)
            if (hp !== this.hoverPitch) { this.hoverPitch = hp; this.drawSoon() }
        })
        const up = () => { down = false; off() }
        this.listen(c, 'pointerup', up)
        this.listen(c, 'pointercancel', up)
        this.listen(c, 'pointerleave', () => { if (!down) { this.hoverPitch = null; this.drawSoon() } })
    }

    // ---------- 标尺：单击定位，拖动设置循环区 ----------
    P.bindRuler = function () {
        const c = this.ruler.c
        const xOf = e => e.clientX - c.getBoundingClientRect().left
        let d = null
        const beatSnap = t => { const s = this.snapTicks() || this.song.ppq; return Math.round(t / s) * s }
        this.listen(c, 'pointerdown', e => {
            if (e.button) return
            c.setPointerCapture(e.pointerId)
            d = { x: xOf(e), moved: false }
        })
        this.listen(c, 'pointermove', e => {
            if (!d) return
            const x = xOf(e)
            if (!d.moved && Math.abs(x - d.x) < 4) return
            d.moved = true
            const a = beatSnap(this.tickAt(d.x)), b = beatSnap(this.tickAt(x))
            this.loop.start = Math.min(a, b)
            this.loop.end = Math.max(a, b)
            this.loop.on = this.loop.end > this.loop.start
            this.drawSoon()
            this.drawLanes()
        })
        const up = e => {
            if (!d) return
            if (!d.moved) this.seekTick(this.snapRound(this.tickAt(xOf(e))))
            else { this.updateTransportUI(); this.onLoopChanged() }
            d = null
        }
        this.listen(c, 'pointerup', up)
        this.listen(c, 'dblclick', () => { this.loop.on = false; this.loop.start = this.loop.end = 0; this.updateTransportUI(); this.onLoopChanged(); this.drawRoll(); this.drawLanes() })
    }

    // ---------- 力度条 ----------
    P.bindVelocity = function () {
        const c = this.vel.c
        const pos = e => { const r = c.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top } }
        let d = null
        const apply = (x, y) => {
            const H = this.vel.h
            const v = clamp(Math.round((H - 4 - y) / (H - 8) * 127), 1, 127)
            const tol = 4
            const onlySel = this.sel.size > 0
            let hit = false
            for (const n of this.track.notes) {
                if (onlySel && !this.sel.has(n.id)) continue
                const nx = this.xOf(n.tick)
                const inRange = d.lastX == null ? Math.abs(nx - x) <= tol
                    : nx >= Math.min(d.lastX, x) - tol && nx <= Math.max(d.lastX, x) + tol
                if (inRange) { n.vel = v; hit = true }
            }
            d.lastX = x
            if (hit) { d.changed = true; this.drawSoon(); this.updateNotePanel?.() }
        }
        this.listen(c, 'pointerdown', e => {
            if (e.button || !this.track) return
            c.setPointerCapture(e.pointerId)
            d = { changed: false, lastX: null }
            const { x, y } = pos(e)
            apply(x, y)
        })
        this.listen(c, 'pointermove', e => { if (d) { const { x, y } = pos(e); apply(x, y) } })
        const up = () => {
            if (!d) return
            if (d.changed) { this.commit('调整力度'); this.afterEdit() }
            d = null
        }
        this.listen(c, 'pointerup', up)
        this.listen(c, 'pointercancel', up)
    }
}

// ---------- 颜色工具 ----------
function hexRgb(c) {
    const m = /^#?([0-9a-f]{6})$/i.exec(c)
    const n = m ? parseInt(m[1], 16) : 0x3b82f6
    return [n >> 16 & 255, n >> 8 & 255, n & 255]
}
export function shade(c, k) {
    const [r, g, b] = hexRgb(c)
    const f = v => Math.round(k < 0 ? v * (1 + k) : v + (255 - v) * k)
    return `rgb(${f(r)},${f(g)},${f(b)})`
}
// 力度越大颜色越饱满，越小越浅
export function velColor(c, vel, dark) {
    const k = 1 - vel / 127
    return dark ? shade(c, -k * 0.55) : shade(c, k * 0.6)
}
function contrastInk(c, vel) {
    const [r, g, b] = hexRgb(c)
    const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return lum > 0.62 && vel > 60 ? 'rgba(0,0,0,.75)' : 'rgba(255,255,255,.92)'
}
function roundRect(g, x, y, w, hh, r) {
    g.beginPath()
    g.roundRect ? g.roundRect(x, y, w, hh, r) : g.rect(x, y, w, hh)
}
export { sigAt }
