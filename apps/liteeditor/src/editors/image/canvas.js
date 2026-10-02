// 图像编辑：视口（缩放 / 平移）、渲染、指针交互与自由变换
import { h, toast, clamp } from '../../core/dom.js'
import * as store from '../../core/store.js'
import { makeCanvas, ctx2d, cloneCanvas, combineSelection, selectionBounds } from './doc.js'
import { Stroke, colorRegion, drawGradient, drawShape, rectSelection, polySelection, retouchDab, smudgeDab, TOOLS } from './tools.js'

export function installCanvas(Ed) {
    const P = Ed.prototype

    P.buildCanvas = function () {
        this.view = h('canvas.img-view')
        this.vctx = this.view.getContext('2d')
        this.overlay = h('canvas.img-overlay')
        this.octx = this.overlay.getContext('2d')
        this.textBox = h('div.img-textbox', { contentEditable: 'true', hidden: true, spellcheck: false })
        this.wrap = h('div.img-wrap', { 'data-drop': '' }, this.view, this.overlay, this.textBox)
        this.stage.classList.add('img-stage')
        this.stage.append(this.wrap)
        this.comp = makeCanvas(1, 1)
        this.ro = new ResizeObserver(() => { this.sizeCanvas(); this.render() })
        this.ro.observe(this.wrap)
        this.onDispose(() => this.ro.disconnect())
        this.listen(this.wrap, 'pointerdown', e => this.onDown(e))
        this.listen(this.wrap, 'pointermove', e => this.onMove(e))
        this.listen(this.wrap, 'pointerup', e => this.onUp(e))
        this.listen(this.wrap, 'pointerleave', () => { this.mouseDoc = null; this.hoverScreen = null; this.drawOverlay(); this.updateStatus() })
        this.listen(this.wrap, 'dblclick', e => this.onDbl(e))
        this.listen(this.wrap, 'wheel', e => this.onWheel(e), { passive: false })
        this.listen(this.wrap, 'contextmenu', e => this.onContext(e))
        this.listen(this.wrap, 'dragover', e => { if ([...e.dataTransfer.types].includes('Files')) e.preventDefault() })
        this.listen(this.wrap, 'drop', e => this.onDropFiles(e))
        this.listen(window, 'keyup', e => { if (e.code === 'Space') { this.spaceDown = false; this.updateCursor() } })
        this.listen(document, 'paste', e => { if (this.el.hidden || e.target.closest?.('input, textarea, [contenteditable="true"]')) return; this.onPaste(e) })
        this.antsTimer = setInterval(() => { if (this.doc.selection && !this.el.hidden) { this.antsPhase = ((this.antsPhase ?? 0) + 1) % 16; this.drawOverlay() } }, 110)
    }

    // ---------- 视口 ----------
    P.sizeCanvas = function () {
        const r = this.wrap.getBoundingClientRect()
        if (!r.width) return
        const dpr = devicePixelRatio || 1
        this.vw = r.width; this.vh = r.height
        for (const c of [this.view, this.overlay]) {
            c.width = Math.round(r.width * dpr); c.height = Math.round(r.height * dpr)
            c.style.width = r.width + 'px'; c.style.height = r.height + 'px'
        }
        this.dpr = dpr
    }
    P.fitView = function () {
        if (!this.vw) this.sizeCanvas()
        const k = Math.min((this.vw - 60) / this.doc.w, (this.vh - 60) / this.doc.h, 1)
        this.zoom = Math.max(0.01, k)
        this.panX = (this.vw - this.doc.w * this.zoom) / 2
        this.panY = (this.vh - this.doc.h * this.zoom) / 2
        this.render()
        this.updateStatus()
    }
    P.setZoom = function (z, cx = this.vw / 2, cy = this.vh / 2) {
        z = clamp(z, 0.01, 64)
        const dx = (cx - this.panX) / this.zoom, dy = (cy - this.panY) / this.zoom
        this.zoom = z
        this.panX = cx - dx * z
        this.panY = cy - dy * z
        this.render()
        this.updateStatus()
    }
    P.zoomBy = function (k, cx, cy) {
        // 缩放级别吸附到常用档位
        let z = this.zoom * k
        const stops = [0.05, 0.0833, 0.125, 0.1667, 0.25, 0.333, 0.5, 0.667, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]
        if (k > 1) z = stops.find(s => s > this.zoom * 1.01) ?? z
        else z = [...stops].reverse().find(s => s < this.zoom * 0.99) ?? z
        this.setZoom(z, cx, cy)
    }
    P.toDoc = function (e) {
        const r = this.wrap.getBoundingClientRect()
        return { x: (e.clientX - r.left - this.panX) / this.zoom, y: (e.clientY - r.top - this.panY) / this.zoom }
    }
    P.onWheel = function (e) {
        e.preventDefault()
        const r = this.wrap.getBoundingClientRect()
        if (e.ctrlKey || e.altKey) this.setZoom(this.zoom * Math.exp(-e.deltaY * 0.0022), e.clientX - r.left, e.clientY - r.top)
        else {
            this.panX -= e.shiftKey ? e.deltaY : e.deltaX
            this.panY -= e.shiftKey ? 0 : e.deltaY
            this.render()
        }
    }

    // ---------- 渲染 ----------
    P.render = function () {
        if (this.rafR) return
        this.rafR = requestAnimationFrame(() => { this.rafR = 0; this.renderNow() })
    }
    P.renderNow = function () {
        const g = this.vctx, dpr = this.dpr ?? 1
        if (!g || !this.vw) return
        g.setTransform(dpr, 0, 0, dpr, 0, 0)
        g.clearRect(0, 0, this.vw, this.vh)
        const d = this.doc
        const x = this.panX, y = this.panY, w = d.w * this.zoom, hh = d.h * this.zoom
        // 阴影与棋盘格
        g.save()
        g.shadowColor = 'rgba(0,0,0,.35)'; g.shadowBlur = 18; g.shadowOffsetY = 4
        g.fillStyle = '#fff'
        g.fillRect(x, y, w, hh)
        g.restore()
        if (store.get('imageCheckerboard') !== false) {
            g.save()
            g.beginPath(); g.rect(x, y, w, hh); g.clip()
            g.fillStyle = this.checkerPattern ??= g.createPattern(checker(), 'repeat')
            g.translate(x, y)
            g.fillRect(0, 0, w, hh)
            g.restore()
        }
        // 合成：拖动预览时替换图层
        if (this.comp.width !== d.w || this.comp.height !== d.h) { this.comp.width = d.w; this.comp.height = d.h }
        d.composite(this.comp, { override: this.preview })
        g.imageSmoothingEnabled = this.zoom < 2
        g.imageSmoothingQuality = 'high'
        g.drawImage(this.comp, x, y, w, hh)
        // 像素网格（放大到 12 倍以上）
        if (this.zoom >= 12) {
            g.strokeStyle = 'rgba(0,0,0,.12)'
            g.lineWidth = 1
            g.beginPath()
            const x0 = Math.max(0, Math.floor(-x / this.zoom)), x1 = Math.min(d.w, Math.ceil((this.vw - x) / this.zoom))
            const y0 = Math.max(0, Math.floor(-y / this.zoom)), y1 = Math.min(d.h, Math.ceil((this.vh - y) / this.zoom))
            for (let i = x0; i <= x1; i++) { const px = Math.round(x + i * this.zoom) + 0.5; g.moveTo(px, y + y0 * this.zoom); g.lineTo(px, y + y1 * this.zoom) }
            for (let j = y0; j <= y1; j++) { const py = Math.round(y + j * this.zoom) + 0.5; g.moveTo(x + x0 * this.zoom, py); g.lineTo(x + x1 * this.zoom, py) }
            g.stroke()
        }
        this.drawOverlay()
    }

    // 覆盖层：选区蚂蚁线、工具预览、变换框、画笔光标
    P.drawOverlay = function () {
        const g = this.octx, dpr = this.dpr ?? 1
        if (!g || !this.vw) return
        g.setTransform(dpr, 0, 0, dpr, 0, 0)
        g.clearRect(0, 0, this.vw, this.vh)
        const z = this.zoom, X = v => this.panX + v * z, Y = v => this.panY + v * z
        // 选区轮廓
        if (this.doc.selection) {
            this.antsPath ??= this.buildAntsPath()
            g.save()
            g.translate(this.panX, this.panY)
            g.scale(z, z)
            g.lineWidth = 1 / z
            g.setLineDash([4 / z, 4 / z])
            g.strokeStyle = '#000'
            g.lineDashOffset = -(this.antsPhase ?? 0) / z
            g.stroke(this.antsPath)
            g.strokeStyle = '#fff'
            g.lineDashOffset = (4 - (this.antsPhase ?? 0)) / z
            g.stroke(this.antsPath)
            g.restore()
        }
        // 拖动中的选框 / 裁剪框 / 渐变线 / 套索
        const dr = this.drag
        if (dr?.kind === 'marquee' || dr?.kind === 'crop') {
            const a = dr.a, b = dr.b
            if (b) {
                const x = X(Math.min(a.x, b.x)), y = Y(Math.min(a.y, b.y)), w = Math.abs(b.x - a.x) * z, hh = Math.abs(b.y - a.y) * z
                g.save()
                if (dr.kind === 'crop') { g.fillStyle = 'rgba(0,0,0,.45)'; g.fillRect(0, 0, this.vw, this.vh); g.clearRect(x, y, w, hh) }
                g.setLineDash([5, 4]); g.strokeStyle = '#fff'; g.lineWidth = 1
                if (dr.ellipse) { g.beginPath(); g.ellipse(x + w / 2, y + hh / 2, w / 2, hh / 2, 0, 0, Math.PI * 2); g.stroke() } else g.strokeRect(x + 0.5, y + 0.5, w, hh)
                g.setLineDash([]); g.strokeStyle = 'rgba(0,0,0,.6)'
                if (!dr.ellipse) g.strokeRect(x - 0.5, y - 0.5, w + 2, hh + 2)
                if (dr.kind === 'crop') {
                    g.strokeStyle = 'rgba(255,255,255,.4)'
                    for (let i = 1; i < 3; i++) { g.beginPath(); g.moveTo(x + w * i / 3, y); g.lineTo(x + w * i / 3, y + hh); g.moveTo(x, y + hh * i / 3); g.lineTo(x + w, y + hh * i / 3); g.stroke() }
                }
                g.fillStyle = 'rgba(15,23,42,.85)'
                const label = `${Math.round(Math.abs(b.x - a.x))} × ${Math.round(Math.abs(b.y - a.y))}`
                g.font = '12px "Microsoft YaHei UI", sans-serif'
                const tw = g.measureText(label).width + 12
                g.fillRect(x + w + 8, y + hh + 8, tw, 20)
                g.fillStyle = '#fff'; g.fillText(label, x + w + 14, y + hh + 22)
                g.restore()
            }
        }
        if (dr?.kind === 'lasso' || this.poly) {
            const pts = dr?.kind === 'lasso' ? dr.pts : this.poly
            g.save()
            g.strokeStyle = '#fff'; g.lineWidth = 1.5; g.setLineDash([5, 4])
            g.beginPath()
            pts.forEach((p, i) => (i ? g.lineTo(X(p.x), Y(p.y)) : g.moveTo(X(p.x), Y(p.y))))
            if (this.poly && this.mouseDoc) g.lineTo(X(this.mouseDoc.x), Y(this.mouseDoc.y))
            g.stroke()
            g.strokeStyle = '#000'; g.lineDashOffset = 4; g.stroke()
            g.restore()
        }
        if (dr?.kind === 'gradient' && dr.b) {
            g.save()
            g.strokeStyle = '#fff'; g.lineWidth = 2
            g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 3
            g.beginPath(); g.moveTo(X(dr.a.x), Y(dr.a.y)); g.lineTo(X(dr.b.x), Y(dr.b.y)); g.stroke()
            for (const p of [dr.a, dr.b]) { g.beginPath(); g.arc(X(p.x), Y(p.y), 4, 0, Math.PI * 2); g.fillStyle = '#fff'; g.fill() }
            g.restore()
        }
        if (this.cloneSrc && this.tool === 'clone') {
            const s = dr?.kind === 'clone' && this.mouseDoc ? { x: this.mouseDoc.x - dr.off.x, y: this.mouseDoc.y - dr.off.y } : this.cloneSrc
            g.save(); g.strokeStyle = '#fff'; g.lineWidth = 1.5
            g.beginPath(); g.moveTo(X(s.x) - 8, Y(s.y)); g.lineTo(X(s.x) + 8, Y(s.y)); g.moveTo(X(s.x), Y(s.y) - 8); g.lineTo(X(s.x), Y(s.y) + 8); g.stroke()
            g.strokeStyle = '#000'; g.setLineDash([2, 2]); g.stroke(); g.restore()
        }
        if (this.xf) this.drawTransformBox(g)
        // 画笔光标
        if (this.hoverScreen && ['brush', 'pencil', 'eraser', 'clone', 'blurTool', 'dodge', 'smudge'].includes(this.tool) && !this.spaceDown) {
            const r = Math.max(1, this.opts.size * z / 2)
            g.save()
            g.beginPath(); g.arc(this.hoverScreen.x, this.hoverScreen.y, r, 0, Math.PI * 2)
            g.strokeStyle = 'rgba(0,0,0,.7)'; g.lineWidth = 1; g.stroke()
            g.beginPath(); g.arc(this.hoverScreen.x, this.hoverScreen.y, r + 1, 0, Math.PI * 2)
            g.strokeStyle = 'rgba(255,255,255,.8)'; g.stroke()
            g.restore()
        }
    }

    // 选区轮廓：把蒙版的边缘转换为 Path2D（文档坐标）
    P.buildAntsPath = function () {
        const sel = this.doc.selection
        const path = new Path2D()
        if (!sel) return path
        const { width: w, height: hh } = sel
        const d = ctx2d(sel).getImageData(0, 0, w, hh).data
        const on = (x, y) => x >= 0 && y >= 0 && x < w && y < hh && d[(y * w + x) * 4 + 3] > 127
        // 水平与垂直边缘分别合并为线段
        for (let y = 0; y <= hh; y++) {
            let start = -1
            for (let x = 0; x <= w; x++) {
                const edge = x < w && on(x, y) !== on(x, y - 1)
                if (edge && start < 0) start = x
                if (!edge && start >= 0) { path.moveTo(start, y); path.lineTo(x, y); start = -1 }
            }
        }
        for (let x = 0; x <= w; x++) {
            let start = -1
            for (let y = 0; y <= hh; y++) {
                const edge = y < hh && on(x, y) !== on(x - 1, y)
                if (edge && start < 0) start = y
                if (!edge && start >= 0) { path.moveTo(x, start); path.lineTo(x, y); start = -1 }
            }
        }
        return path
    }
    // 修改选区后调用
    P.selectionChanged = function () {
        this.antsPath = null
        this.selBounds = selectionBounds(this.doc.selection)
        if (!this.selBounds && this.doc.selection) this.doc.selection = null
        this.drawOverlay()
        this.updateStatus()
    }

    P.updateCursor = function () {
        const t = this.tool
        const c = this.spaceDown || t === 'hand' ? (this.drag?.kind === 'pan' ? 'grabbing' : 'grab')
            : t === 'zoom' ? 'zoom-in' : t === 'move' ? 'move' : t === 'text' ? 'text' : t === 'picker' ? 'crosshair'
            : ['brush', 'pencil', 'eraser', 'clone', 'blurTool', 'dodge', 'smudge'].includes(t) ? 'none' : 'crosshair'
        this.wrap.style.cursor = c
    }

    // ---------- 指针 ----------
    P.selMode = function (e) {
        if (e.shiftKey && e.altKey) return 'intersect'
        if (e.shiftKey) return 'add'
        if (e.altKey) return 'sub'
        return this.opts.selMode
    }
    P.editableLayer = function (silent) {
        const l = this.doc.activeLayer
        if (!l) { if (!silent) toast('没有可编辑的图层', 'warn'); return null }
        if (l.locked) { if (!silent) toast('图层已锁定', 'warn'); return null }
        if (!l.visible) { if (!silent) toast('当前图层已隐藏', 'warn'); return null }
        if (l.text && !silent) {
            // 在文字图层上绘制：先栅格化
            delete l.text
            toast('已将文字图层栅格化')
        }
        return l
    }

    P.onDown = function (e) {
        if (e.button === 2) return
        this.wrap.setPointerCapture(e.pointerId)
        const p = this.toDoc(e)
        const t = this.tool
        this.textBox.hidden || this.commitText()
        if (this.xf) return this.xfDown(e, p)
        if (this.spaceDown || t === 'hand' || e.button === 1) { this.drag = { kind: 'pan', sx: e.clientX, sy: e.clientY, px: this.panX, py: this.panY }; this.updateCursor(); return }
        if (t === 'zoom') { const r = this.wrap.getBoundingClientRect(); this.zoomBy(e.altKey ? 1 / 1.25 : 1.25, e.clientX - r.left, e.clientY - r.top); return }
        if (t === 'picker') return this.pickColor(p, e.altKey ? 'bg' : 'fg')
        if (t === 'move') {
            const l = this.editableLayer()
            if (!l) return
            // Ctrl+拖动 / 有选区时：移动选区内容到新图层
            if (this.doc.selection && !e.ctrlKey) { this.floatSelection(); return this.startTransformMove(e, p) }
            this.drag = { kind: 'move', a: p, x: l.x, y: l.y, layer: l, dup: e.altKey }
            return
        }
        if (t === 'marquee' || t === 'ellipse' || t === 'crop') { this.drag = { kind: t === 'crop' ? 'crop' : 'marquee', ellipse: t === 'ellipse', a: p, b: null, mode: this.selMode(e) }; return }
        if (t === 'lasso') { this.drag = { kind: 'lasso', pts: [p], mode: this.selMode(e) }; return }
        if (t === 'polyLasso') {
            if (!this.poly) { this.poly = [p]; this.polyMode = this.selMode(e) }
            else {
                const f = this.poly[0]
                if (Math.hypot(f.x - p.x, f.y - p.y) * this.zoom < 8 && this.poly.length > 2) return this.finishPoly()
                this.poly.push(p)
            }
            this.drawOverlay()
            return
        }
        if (t === 'wand') return this.magicWand(p, this.selMode(e))
        if (t === 'bucket') return this.bucketFill(p, e.altKey)
        if (t === 'text') return this.startText(p)
        const l = this.editableLayer()
        if (!l) return
        if (t === 'brush' || t === 'pencil' || t === 'eraser') {
            if (e.shiftKey && this.lastPoint) {
                // Shift 单击：从上一点画直线
                const s = new Stroke(this, l, { erase: t === 'eraser', pencil: t === 'pencil' })
                s.to(this.lastPoint); s.to(p); s.commit()
                this.lastPoint = p
                this.commit(TOOLS.find(x => x.id === t).label)
                return this.render()
            }
            this.drag = { kind: 'stroke', stroke: new Stroke(this, l, { erase: t === 'eraser', pencil: t === 'pencil' }), layer: l }
            this.drag.stroke.to(p)
            this.preview = { id: l.id, canvas: this.drag.stroke.preview() }
            this.lastPoint = p
            return this.render()
        }
        if (t === 'clone') {
            if (e.altKey) { this.cloneSrc = p; this.cloneOff = null; toast('已设置仿制源'); return this.drawOverlay() }
            if (!this.cloneSrc) return toast('按住 Alt 单击设置仿制源')
            const off = this.cloneAligned && this.cloneOff ? this.cloneOff : { x: p.x - this.cloneSrc.x, y: p.y - this.cloneSrc.y }
            this.cloneOff = off
            const src = cloneCanvas(this.doc.writable(l))
            this.drag = { kind: 'clone', layer: l, off, src, last: null }
            this.cloneDab(p)
            return
        }
        if (t === 'blurTool' || t === 'dodge' || t === 'smudge') {
            this.doc.writable(l)
            this.drag = { kind: 'retouch', layer: l, last: p }
            if (t !== 'smudge') this.retouchAt(p)
            return
        }
        if (t === 'gradient') { this.drag = { kind: 'gradient', a: p, b: null, layer: l }; return }
        if (t === 'shape') { this.drag = { kind: 'shape', a: p, b: p, layer: l }; return }
    }

    P.onMove = function (e) {
        const p = this.toDoc(e)
        const r = this.wrap.getBoundingClientRect()
        this.mouseDoc = p
        this.hoverScreen = { x: e.clientX - r.left, y: e.clientY - r.top }
        const d = this.drag
        if (this.xf) { this.xfMove(e, p); this.updateStatus(); return }
        if (!d) { this.drawOverlay(); this.updateStatus(); return }
        switch (d.kind) {
            case 'pan':
                this.panX = d.px + e.clientX - d.sx
                this.panY = d.py + e.clientY - d.sy
                this.render()
                break
            case 'move': {
                let dx = p.x - d.a.x, dy = p.y - d.a.y
                if (e.shiftKey) { if (Math.abs(dx) > Math.abs(dy)) dy = 0; else dx = 0 }
                d.layer.x = Math.round(d.x + dx)
                d.layer.y = Math.round(d.y + dy)
                d.moved = true
                this.render()
                break
            }
            case 'marquee': case 'crop': {
                let b = { ...p }
                if (e.shiftKey) { const s = Math.max(Math.abs(b.x - d.a.x), Math.abs(b.y - d.a.y)); b = { x: d.a.x + Math.sign(b.x - d.a.x || 1) * s, y: d.a.y + Math.sign(b.y - d.a.y || 1) * s } }
                if (e.altKey && d.kind === 'marquee') { const dx = b.x - d.a.x, dy = b.y - d.a.y; d.a0 ??= { ...d.a }; d.a = { x: d.a0.x - dx, y: d.a0.y - dy } }
                d.b = b
                this.drawOverlay()
                break
            }
            case 'lasso': d.pts.push(p); this.drawOverlay(); break
            case 'stroke': {
                const evs = e.getCoalescedEvents?.() ?? [e]
                for (const ev of evs) d.stroke.to(this.toDoc(ev))
                this.preview = { id: d.layer.id, canvas: d.stroke.preview() }
                this.render()
                break
            }
            case 'clone': this.cloneDab(p); break
            case 'retouch': {
                if (this.tool === 'smudge') smudgeDab(d.layer.canvas, { x: d.last.x - d.layer.x, y: d.last.y - d.layer.y }, { x: p.x - d.layer.x, y: p.y - d.layer.y }, this.opts.size, this.opts.strength)
                else if (Math.hypot(p.x - d.last.x, p.y - d.last.y) >= Math.max(1, this.opts.size * 0.15)) this.retouchAt(p)
                else break
                d.last = p
                this.render()
                break
            }
            case 'gradient': {
                let b = p
                if (e.shiftKey) { const a = Math.round(Math.atan2(p.y - d.a.y, p.x - d.a.x) / (Math.PI / 4)) * Math.PI / 4, L = Math.hypot(p.x - d.a.x, p.y - d.a.y); b = { x: d.a.x + L * Math.cos(a), y: d.a.y + L * Math.sin(a) } }
                d.b = b
                this.preview = { id: d.layer.id, canvas: this.gradientCanvas(d.layer, d.a, b) }
                this.render()
                break
            }
            case 'shape': {
                let b = p
                if (e.shiftKey) {
                    if (this.opts.shape === 'line' || this.opts.shape === 'arrow') { const a = Math.round(Math.atan2(p.y - d.a.y, p.x - d.a.x) / (Math.PI / 4)) * Math.PI / 4, L = Math.hypot(p.x - d.a.x, p.y - d.a.y); b = { x: d.a.x + L * Math.cos(a), y: d.a.y + L * Math.sin(a) } }
                    else { const s = Math.max(Math.abs(p.x - d.a.x), Math.abs(p.y - d.a.y)); b = { x: d.a.x + Math.sign(p.x - d.a.x || 1) * s, y: d.a.y + Math.sign(p.y - d.a.y || 1) * s } }
                }
                d.b = b
                const c = cloneCanvas(d.layer.canvas)
                const g = ctx2d(c)
                g.translate(-d.layer.x, -d.layer.y)
                drawShape(g, this.opts, this.fg, this.bg, d.a, b)
                this.preview = { id: d.layer.id, canvas: c }
                this.render()
                break
            }
        }
        this.updateStatus()
    }

    P.onUp = function (e) {
        const d = this.drag
        this.drag = null
        if (this.xf) return this.xfUp(e)
        if (!d) return
        const p = this.toDoc(e)
        switch (d.kind) {
            case 'pan': this.updateCursor(); break
            case 'move':
                if (d.moved) {
                    if (d.dup) {
                        // Alt 拖动复制图层
                        const copy = { ...d.layer, id: Math.random().toString(36).slice(2), name: d.layer.name + ' 拷贝', canvas: cloneCanvas(d.layer.canvas) }
                        const i = this.doc.layers.indexOf(d.layer)
                        this.doc.layers.splice(i + 1, 0, copy)
                        d.layer.x = d.x; d.layer.y = d.y
                        this.doc.active = copy.id
                    }
                    this.commit(d.dup ? '复制图层' : '移动')
                    this.refreshPanels()
                }
                break
            case 'marquee': {
                if (!d.b || Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y) * this.zoom < 3) {
                    if (d.mode === 'new' && this.doc.selection) { this.doc.selection = null; this.selectionChanged(); this.commit('取消选择') }
                    break
                }
                this.doc.selection = rectSelection(this.doc, d.a, d.b, d.ellipse, d.mode, this.opts.feather)
                this.selectionChanged()
                this.commit(d.ellipse ? '椭圆选框' : '矩形选框')
                break
            }
            case 'crop': {
                if (!d.b) break
                const x = Math.round(Math.min(d.a.x, d.b.x)), y = Math.round(Math.min(d.a.y, d.b.y))
                const w = Math.round(Math.abs(d.b.x - d.a.x)), hh = Math.round(Math.abs(d.b.y - d.a.y))
                if (w > 2 && hh > 2) this.cropTo({ x, y, w, h: hh })
                break
            }
            case 'lasso':
                if (d.pts.length > 2) {
                    this.doc.selection = polySelection(this.doc, d.pts, d.mode, this.opts.feather)
                    this.selectionChanged()
                    this.commit('套索')
                }
                this.drawOverlay()
                break
            case 'stroke':
                d.stroke.commit()
                this.preview = null
                this.commit(TOOLS.find(x => x.id === this.tool)?.label ?? '绘制')
                this.render()
                this.refreshLayerThumbs?.()
                break
            case 'clone': this.commit('仿制图章'); this.refreshLayerThumbs?.(); break
            case 'retouch': this.commit(TOOLS.find(x => x.id === this.tool)?.label ?? '修饰'); this.refreshLayerThumbs?.(); break
            case 'gradient':
                if (d.b && Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y) > 1) {
                    d.layer.canvas = this.gradientCanvas(d.layer, d.a, d.b)
                    this.commit('渐变')
                }
                this.preview = null
                this.render()
                this.refreshLayerThumbs?.()
                break
            case 'shape': {
                if (Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y) < 2) { this.preview = null; this.render(); break }
                // 形状绘制在新图层上
                const l = this.addLayer({ name: '形状 ' + this.doc.layers.length })
                const g = ctx2d(l.canvas)
                if (this.doc.selection) { g.save(); g.drawImage(this.doc.selection, 0, 0); g.globalCompositeOperation = 'source-in' }
                drawShape(g, this.opts, this.fg, this.bg, d.a, d.b)
                if (this.doc.selection) g.restore()
                this.preview = null
                this.commit('形状')
                this.afterDocChange()
                break
            }
        }
        void p
    }

    P.onDbl = function (e) {
        if (this.tool === 'polyLasso' && this.poly) return this.finishPoly()
        if (this.xf) return this.commitTransform()
        if (this.tool === 'move' || this.tool === 'text') {
            const l = this.doc.activeLayer
            if (l?.text) this.startText({ x: l.text.x, y: l.text.y }, l)
        }
        if (this.tool === 'hand') this.fitView()
        if (this.tool === 'zoom') this.setZoom(1)
    }

    P.finishPoly = function () {
        if (this.poly.length > 2) {
            this.doc.selection = polySelection(this.doc, this.poly, this.polyMode, this.opts.feather)
            this.selectionChanged()
            this.commit('多边形套索')
        }
        this.poly = null
        this.drawOverlay()
    }

    // ---------- 工具实现 ----------
    P.pickColor = function (p, which = 'fg') {
        const x = Math.floor(p.x), y = Math.floor(p.y)
        if (x < 0 || y < 0 || x >= this.doc.w || y >= this.doc.h) return
        const src = this.opts.allLayers !== false ? this.comp : this.doc.activeLayer?.canvas
        const l = this.doc.activeLayer
        const [r, g, b, a] = ctx2d(src).getImageData(src === this.comp ? x : x - (l?.x ?? 0), src === this.comp ? y : y - (l?.y ?? 0), 1, 1).data
        if (!a) return
        this.setColor(which, '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join(''))
    }

    P.magicWand = function (p, mode) {
        const o = this.opts
        const src = o.allLayers ? this.doc.composite() : this.doc.activeLayer?.canvas
        const l = this.doc.activeLayer
        if (!src) return
        const ox = o.allLayers ? 0 : l.x, oy = o.allLayers ? 0 : l.y
        let m = colorRegion(src, ox, oy, this.doc.w, this.doc.h, p.x, p.y, o.tolerance, o.contiguous)
        if (o.feather) { const f = makeCanvas(m.width, m.height), fg = ctx2d(f); fg.filter = `blur(${o.feather}px)`; fg.drawImage(m, 0, 0); m = f }
        this.doc.selection = combineSelection(this.doc.selection, m, mode)
        this.selectionChanged()
        this.commit('魔棒')
    }

    P.bucketFill = function (p, useBg) {
        const l = this.editableLayer()
        if (!l) return
        const o = this.opts
        const src = o.allLayers ? this.doc.composite() : l.canvas
        const ox = o.allLayers ? 0 : l.x, oy = o.allLayers ? 0 : l.y
        const region = colorRegion(src, ox, oy, this.doc.w, this.doc.h, p.x, p.y, o.tolerance, o.contiguous)
        const fillC = makeCanvas(this.doc.w, this.doc.h)
        const g = ctx2d(fillC)
        g.drawImage(region, 0, 0)
        if (this.doc.selection) { g.globalCompositeOperation = 'destination-in'; g.drawImage(this.doc.selection, 0, 0) }
        g.globalCompositeOperation = 'source-in'
        g.fillStyle = useBg ? this.bg : this.fg
        g.fillRect(0, 0, fillC.width, fillC.height)
        const c = this.doc.writable(l)
        const lg = ctx2d(c)
        lg.globalAlpha = o.opacity / 100
        lg.drawImage(fillC, -l.x, -l.y)
        lg.globalAlpha = 1
        this.commit('油漆桶')
        this.render()
        this.refreshLayerThumbs?.()
    }

    P.gradientCanvas = function (layer, a, b) {
        const c = cloneCanvas(layer.canvas)
        const tmp = makeCanvas(c.width, c.height)
        const tg = ctx2d(tmp)
        tg.translate(-layer.x, -layer.y)
        const [c1, c2] = this.opts.gradReverse ? [this.bg, this.fg] : [this.fg, this.bg]
        drawGradient(tg, this.opts.gradType, a, b, c1, this.opts.gradTransparent ? 'rgba(0,0,0,0)' : c2)
        if (this.doc.selection) { tg.setTransform(1, 0, 0, 1, 0, 0); tg.globalCompositeOperation = 'destination-in'; tg.drawImage(this.doc.selection, -layer.x, -layer.y) }
        const g = ctx2d(c)
        g.globalAlpha = this.opts.opacity / 100
        g.drawImage(tmp, 0, 0)
        return c
    }

    P.cloneDab = function (p) {
        const d = this.drag
        const l = d.layer
        const r = this.opts.size / 2
        const g = ctx2d(l.canvas)
        const tip = makeCanvas(r * 2, r * 2)
        const tg = ctx2d(tip)
        tg.drawImage(d.src, p.x - d.off.x - l.x - r, p.y - d.off.y - l.y - r, r * 2, r * 2, 0, 0, r * 2, r * 2)
        tg.globalCompositeOperation = 'destination-in'
        const grad = tg.createRadialGradient(r, r, 0, r, r, r)
        const hd = Math.min(0.99, this.opts.hardness / 100)
        grad.addColorStop(0, `rgba(0,0,0,${this.opts.opacity / 100})`)
        grad.addColorStop(hd, `rgba(0,0,0,${this.opts.opacity / 100})`)
        grad.addColorStop(1, 'rgba(0,0,0,0)')
        tg.fillStyle = grad
        tg.fillRect(0, 0, r * 2, r * 2)
        if (this.doc.selection) { tg.globalCompositeOperation = 'destination-in'; tg.drawImage(this.doc.selection, -(p.x - r), -(p.y - r)) }
        g.drawImage(tip, p.x - l.x - r, p.y - l.y - r)
        this.render()
    }
    P.retouchAt = function (p) {
        const d = this.drag
        const mode = this.tool === 'blurTool' ? this.opts.blurMode : this.opts.dodgeMode
        retouchDab(d.layer.canvas, p.x - d.layer.x, p.y - d.layer.y, this.opts.size, mode, this.opts.strength)
        this.render()
    }

    // ---------- 文字 ----------
    P.startText = function (p, layer) {
        const o = this.opts
        const t = layer?.text
        this.textEdit = { p: { x: t?.x ?? p.x, y: t?.y ?? p.y }, layer }
        const box = this.textBox
        box.hidden = false
        box.textContent = t?.content ?? ''
        const st = t ?? { font: o.font, size: o.fontSize, color: this.fg, bold: o.bold, italic: o.italic, align: o.align ?? 'left' }
        this.textEdit.style = { ...st }
        this.placeTextBox()
        if (layer) { layer.visible = false; this.render() }
        requestAnimationFrame(() => { box.focus(); const r = document.createRange(); r.selectNodeContents(box); r.collapse(false); getSelection().removeAllRanges(); getSelection().addRange(r) })
    }
    P.placeTextBox = function () {
        const te = this.textEdit
        if (!te) return
        const st = te.style, box = this.textBox
        Object.assign(box.style, {
            left: this.panX + te.p.x * this.zoom + 'px', top: this.panY + te.p.y * this.zoom + 'px',
            font: `${st.italic ? 'italic ' : ''}${st.bold ? 'bold ' : ''}${st.size * this.zoom}px ${st.font}`,
            color: st.color, textAlign: st.align, lineHeight: '1.2',
        })
    }
    P.commitText = function () {
        const te = this.textEdit
        if (!te) return
        this.textEdit = null
        const content = this.textBox.innerText.replace(/\n$/, '')
        this.textBox.hidden = true
        if (te.layer) te.layer.visible = true
        if (!content.trim()) { if (te.layer) this.render(); return }
        const layer = te.layer ?? this.addLayer({ name: content.slice(0, 20) })
        layer.text = { content, x: te.p.x, y: te.p.y, ...te.style }
        layer.name = content.split('\n')[0].slice(0, 20)
        this.rasterizeText(layer)
        this.commit(te.layer ? '编辑文字' : '文字')
        this.afterDocChange()
        this.focusEditor?.()
    }
    // 文字图层按其参数重绘（图层画布为整张文档大小）
    P.rasterizeText = function (layer) {
        const t = layer.text
        const c = makeCanvas(this.doc.w, this.doc.h)
        const g = ctx2d(c)
        g.font = `${t.italic ? 'italic ' : ''}${t.bold ? 'bold ' : ''}${t.size}px ${t.font}`
        g.fillStyle = t.color
        g.textBaseline = 'top'
        g.textAlign = t.align ?? 'left'
        const lines = t.content.split('\n')
        const maxW = Math.max(...lines.map(l => g.measureText(l).width))
        const x0 = t.align === 'center' ? t.x + maxW / 2 : t.align === 'right' ? t.x + maxW : t.x
        lines.forEach((line, i) => g.fillText(line, x0, t.y + i * t.size * 1.2))
        layer.canvas = c
        layer.x = 0; layer.y = 0
    }

    // ---------- 右键 ----------
    P.onContext = function (e) {
        e.preventDefault()
        this.contextMenuAt?.(e)
    }

    // ---------- 拖入文件 / 粘贴 ----------
    P.onDropFiles = async function (e) {
        const files = [...e.dataTransfer.files].filter(f => f.type.startsWith('image/'))
        if (!files.length) return
        e.preventDefault(); e.stopPropagation()
        for (const f of files) await this.placeImage(URL.createObjectURL(f))
    }
    P.onPaste = async function (e) {
        const f = [...(e.clipboardData?.files ?? [])].find(x => x.type.startsWith('image/'))
        if (f) { e.preventDefault(); const l = await this.placeImage(URL.createObjectURL(f)); if (l) l.name = '粘贴的图层'; this.refreshPanels() }
    }
}

// 棋盘格图案
function checker() {
    const c = makeCanvas(16, 16)
    const g = ctx2d(c)
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, 16, 16)
    g.fillStyle = '#d4d4d8'; g.fillRect(0, 0, 8, 8); g.fillRect(8, 8, 8, 8)
    return c
}
