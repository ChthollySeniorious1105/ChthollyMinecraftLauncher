// 表格视图：DOM 结构、几何换算（冻结窗格 / 缩放 / 滚动）、命中测试
// 画布只绘制可见区域（虚拟滚动），滚动条由一个透明的原生滚动容器提供
import { h } from '../../core/dom.js'
import { Axis } from './axis.js'
import { MAX_ROWS, MAX_COLS } from './addr.js'
import { drawGrid } from './render.js'

export class Grid {
    constructor(ed) {
        this.ed = ed
        this.rows = new Axis()
        this.cols = new Axis()
        this.sx = 0; this.sy = 0          // 可滚动区域的滚动量（未缩放像素）
        this.W = 0; this.H = 0
        this.canvas = h('canvas.sh-canvas')
        this.spacer = h('div.sh-spacer')
        this.scroller = h('div.sh-scroller', { tabIndex: -1 }, this.spacer)
        this.layer = h('div.sh-layer')          // 编辑框、图表等浮动元素
        this.chartLayer = h('div.sh-chart-layer')
        this.layer.append(this.chartLayer)
        this.el = h('div.sh-gridwrap', this.canvas, this.scroller, this.layer)
        this.ctx = this.canvas.getContext('2d', { alpha: false })
        this.scroller.addEventListener('scroll', () => this.onScroll())
        new ResizeObserver(() => this.layout()).observe(this.el)
        this.measureCache = new Map()
    }

    get sheet() { return this.ed.sheet }
    get z() { return this.ed.zoom }
    get fr() { return this.sheet.meta.freeze.r }
    get fc() { return this.sheet.meta.freeze.c }

    sync() {
        const m = this.sheet.meta
        this.rows.sync(m.defRowH, m.rowH, m.hiddenR, m.filter?.hidden)
        this.cols.sync(m.defColW, m.colW, m.hiddenC, null)
        const z = this.z
        this.HH = Math.round(24 * z)
        const maxRow = this.rows.at(this.sy + this.rows.pos(this.fr) + this.H / z) + 1
        this.HW = Math.round(Math.max(38, 14 + String(maxRow).length * 7.5) * z)
    }

    layout() {
        const W = this.scroller.clientWidth, H = this.scroller.clientHeight
        if (!W || !H) return
        const dpr = window.devicePixelRatio || 1
        this.W = W; this.H = H; this.dpr = dpr
        this.canvas.width = Math.round(W * dpr)
        this.canvas.height = Math.round(H * dpr)
        this.canvas.style.width = W + 'px'
        this.canvas.style.height = H + 'px'
        this.updateExtent()
        this.draw()
    }

    // 滚动范围：已用区域 + 余量，滚动到末尾时自动扩展（最多 1048576 行 × 16384 列）
    updateExtent() {
        this.sync()
        const b = this.sheet.bounds()
        const z = this.z
        const sel = this.ed.sel
        const viewRows = Math.ceil(this.H / (this.sheet.meta.defRowH * z))
        const viewCols = Math.ceil(this.W / (this.sheet.meta.defColW * z))
        const lastR = this.rows.at(this.rows.pos(this.fr) + this.sy + this.H / z)
        const lastC = this.cols.at(this.cols.pos(this.fc) + this.sx + this.W / z)
        this.extR = Math.min(MAX_ROWS, Math.max(100, b.r2 + 1 + viewRows, sel.r + viewRows, lastR + viewRows))
        this.extC = Math.min(MAX_COLS, Math.max(26, b.c2 + 1 + viewCols, sel.c + viewCols, lastC + viewCols))
        const w = this.HW + this.cols.pos(this.extC) * z
        const hh = this.HH + this.rows.pos(this.extR) * z
        // 浏览器元素尺寸上限约 3350 万像素
        this.spacer.style.width = Math.min(w, 3.3e7) + 'px'
        this.spacer.style.height = Math.min(hh, 3.3e7) + 'px'
    }

    onScroll() {
        const z = this.z
        this.sx = this.scroller.scrollLeft / z
        this.sy = this.scroller.scrollTop / z
        const nearR = this.scroller.scrollTop + this.scroller.clientHeight > this.scroller.scrollHeight - 200
        const nearC = this.scroller.scrollLeft + this.scroller.clientWidth > this.scroller.scrollWidth - 200
        if (nearR || nearC) this.updateExtent()
        this.draw()
        this.ed.onGridScroll?.()
    }

    setScroll(sx, sy) {
        const z = this.z
        this.sx = Math.max(0, sx); this.sy = Math.max(0, sy)
        this.updateExtent()
        this.scroller.scrollLeft = this.sx * z
        this.scroller.scrollTop = this.sy * z
        this.sx = this.scroller.scrollLeft / z
        this.sy = this.scroller.scrollTop / z
        this.draw()
    }

    draw() {
        if (!this.W) return
        cancelAnimationFrame(this.raf)
        this.raf = 0
        this.sync()
        drawGrid(this)
        this.ed.onGridDrawn?.()
    }
    requestDraw() {
        if (this.raf) return
        this.raf = requestAnimationFrame(() => { this.raf = 0; this.draw() })
    }

    // ---------- 几何 ----------
    colX(c) { return this.HW + (this.cols.pos(c) - (c >= this.fc ? this.sx : 0)) * this.z }
    rowY(r) { return this.HH + (this.rows.pos(r) - (r >= this.fr ? this.sy : 0)) * this.z }
    colW(c) { return this.cols.size(c) * this.z }
    rowH(r) { return this.rows.size(r) * this.z }
    get frozenW() { return this.cols.pos(this.fc) * this.z }
    get frozenH() { return this.rows.pos(this.fr) * this.z }

    // 可滚动区域的可见行列范围
    visibleRows() {
        const r0 = this.rows.at(this.rows.pos(this.fr) + this.sy)
        const r1 = this.rows.at(this.rows.pos(this.fr) + this.sy + (this.H - this.HH - this.frozenH) / this.z)
        return [Math.max(r0, this.fr), Math.min(r1, MAX_ROWS - 1)]
    }
    visibleCols() {
        const c0 = this.cols.at(this.cols.pos(this.fc) + this.sx)
        const c1 = this.cols.at(this.cols.pos(this.fc) + this.sx + (this.W - this.HW - this.frozenW) / this.z)
        return [Math.max(c0, this.fc), Math.min(c1, MAX_COLS - 1)]
    }

    // 屏幕坐标（相对于表格区域左上角） -> 行列；返回的行列允许位于冻结区
    rowAt(y) {
        if (y < this.HH) return -1
        const yy = (y - this.HH) / this.z
        if (this.fr && yy < this.rows.pos(this.fr)) return this.rows.at(yy)
        return this.rows.at(yy + this.sy)
    }
    colAt(x) {
        if (x < this.HW) return -1
        const xx = (x - this.HW) / this.z
        if (this.fc && xx < this.cols.pos(this.fc)) return this.cols.at(xx)
        return this.cols.at(xx + this.sx)
    }
    // 限定到可视区域内的行列（拖动选择越界时）
    rowAtClamped(y) { return Math.max(0, this.rowAt(Math.max(this.HH + 1, y))) }
    colAtClamped(x) { return Math.max(0, this.colAt(Math.max(this.HW + 1, x))) }

    // 单元格（或合并区域）的屏幕矩形
    cellRect(r, c, r2 = r, c2 = c) {
        const x = this.colX(c), y = this.rowY(r)
        return { x, y, w: this.colX(c2) + this.colW(c2) - x, h: this.rowY(r2) + this.rowH(r2) - y }
    }
    rangeRect(g) {
        const x1 = this.colX(g.c1), y1 = this.rowY(g.r1)
        const x2 = this.colX(g.c2) + this.colW(g.c2), y2 = this.rowY(g.r2) + this.rowH(g.r2)
        return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
    }

    // 命中测试
    hit(x, y) {
        const { HW, HH } = this
        if (x < HW && y < HH) return { area: 'corner' }
        if (y < HH) {
            const c = this.colAt(x)
            // 列边界（调整列宽）
            const edge = this.edgeNear(x, c, 'col')
            if (edge != null) return { area: 'colresize', c: edge }
            return { area: 'colhead', c }
        }
        if (x < HW) {
            const r = this.rowAt(y)
            const edge = this.edgeNear(y, r, 'row')
            if (edge != null) return { area: 'rowresize', r: edge }
            return { area: 'rowhead', r }
        }
        const r = this.rowAt(y), c = this.colAt(x)
        // 填充柄
        const g = this.ed.sel.ranges[this.ed.sel.ranges.length - 1]
        if (g && this.ed.sel.ranges.length === 1 && !this.ed.editing) {
            const rr = this.rangeRect(g)
            if (Math.abs(x - (rr.x + rr.w)) <= 5 && Math.abs(y - (rr.y + rr.h)) <= 5) return { area: 'fill', r, c }
        }
        // 筛选按钮
        const f = this.sheet.meta.filter
        if (f && r === f.range.r1 && c >= f.range.c1 && c <= f.range.c2) {
            const rc = this.cellRect(r, c)
            const s = Math.min(18 * this.z, rc.h - 4)
            if (x >= rc.x + rc.w - s - 3 && y >= rc.y + (rc.h - s) / 2) return { area: 'filter', r, c }
        }
        // 数据验证下拉按钮
        if (this.dvButton && x >= this.dvButton.x && x <= this.dvButton.x + this.dvButton.w && y >= this.dvButton.y && y <= this.dvButton.y + this.dvButton.h)
            return { area: 'dvlist', r: this.ed.sel.r, c: this.ed.sel.c }
        return { area: 'cell', r, c }
    }

    edgeNear(p, i, kind) {
        if (i < 0) return null
        const tol = 4
        const start = kind === 'col' ? this.colX(i) : this.rowY(i)
        const size = kind === 'col' ? this.colW(i) : this.rowH(i)
        if (Math.abs(p - (start + size)) <= tol) return i
        if (Math.abs(p - start) <= tol && i > 0) {
            // 左 / 上边界属于前一个可见项（跳过隐藏项时也可以拖出隐藏的项）
            let j = i - 1
            return j
        }
        return null
    }

    // 让单元格进入可视区域
    scrollTo(r, c) {
        const z = this.z
        let { sx, sy } = this
        if (c >= this.fc) {
            const x = this.cols.pos(c) - this.cols.pos(this.fc), w = this.cols.size(c)
            const vw = (this.W - this.HW - this.frozenW) / z
            if (x < sx) sx = x
            else if (x + w > sx + vw) sx = Math.min(x, x + w - vw)
        }
        if (r >= this.fr) {
            const y = this.rows.pos(r) - this.rows.pos(this.fr), hh = this.rows.size(r)
            const vh = (this.H - this.HH - this.frozenH) / z
            if (y < sy) sy = y
            else if (y + hh > sy + vh) sy = Math.min(y, y + hh - vh)
        }
        if (sx !== this.sx || sy !== this.sy) this.setScroll(sx, sy)
    }

    pageRows() {
        const [r0, r1] = this.visibleRows()
        return Math.max(1, r1 - r0)
    }

    // 文本测量（带缓存）
    measure(font, text) {
        const key = font + '\u0000' + text
        let w = this.measureCache.get(key)
        if (w == null) {
            const ctx = this.mctx ??= document.createElement('canvas').getContext('2d')
            ctx.font = font
            w = ctx.measureText(text).width
            if (this.measureCache.size > 20000) this.measureCache.clear()
            this.measureCache.set(key, w)
        }
        return w
    }
}
