// 选区与鼠标 / 键盘导航
import { MAX_ROWS, MAX_COLS, normRange } from './addr.js'
import { contextMenu } from '../../core/menu.js'
import { clamp } from '../../core/dom.js'

const isEmpty = cell => !cell || (cell.v == null && !cell.f) || cell.v === ''

export const Selection = {
    // ---------- 选区操作 ----------
    selectCell(r, c, { scroll = true } = {}) {
        r = clamp(r, 0, MAX_ROWS - 1); c = clamp(c, 0, MAX_COLS - 1)
        const m = this.sheet.mergeAt(r, c)
        const g = m ? { ...m } : { r1: r, c1: c, r2: r, c2: c }
        if (m) { r = m.r1; c = m.c1 }
        this.sel = { r, c, ranges: [g], anchor: { r, c }, end: { r, c } }
        this.afterSel(scroll ? [r, c] : null)
    },

    // 设置单一区域；active 默认为左上角
    selectRange(g, { active, add = false, anchor, end } = {}) {
        g = this.expandMerges(normRange(g))
        const a = active ?? { r: g.r1, c: g.c1 }
        const ranges = add ? [...this.sel.ranges, g] : [g]
        this.sel = { r: a.r, c: a.c, ranges, anchor: anchor ?? { ...a }, end: end ?? { r: g.r2, c: g.c2 } }
        this.afterSel(null)
    },

    // 从锚点扩展到 (r, c)
    extendTo(r, c, scroll = true) {
        r = clamp(r, 0, MAX_ROWS - 1); c = clamp(c, 0, MAX_COLS - 1)
        const a = this.sel.anchor
        const g = this.expandMerges(normRange({ r1: a.r, c1: a.c, r2: r, c2: c }))
        const ranges = [...this.sel.ranges]
        ranges[ranges.length - 1] = g
        this.sel = { ...this.sel, ranges, end: { r, c } }
        this.afterSel(scroll ? [r, c] : null)
    },

    selectAll() {
        this.sel = { r: this.sel.r, c: this.sel.c, ranges: [{ r1: 0, c1: 0, r2: MAX_ROWS - 1, c2: MAX_COLS - 1 }], anchor: { r: 0, c: 0 }, end: { r: MAX_ROWS - 1, c: MAX_COLS - 1 } }
        this.afterSel(null)
    },
    selectCols(c1, c2, add = false) {
        const g = { r1: 0, r2: MAX_ROWS - 1, c1: Math.min(c1, c2), c2: Math.max(c1, c2) }
        const top = this.grid.rows.visible(0)
        this.sel = { r: add ? this.sel.r : top, c: add ? this.sel.c : c1, ranges: add ? [...this.sel.ranges, g] : [g], anchor: { r: 0, c: c1 }, end: { r: MAX_ROWS - 1, c: c2 } }
        if (!add) { this.sel.r = top; this.sel.c = Math.min(c1, c2) }
        this.afterSel(null)
    },
    selectRows(r1, r2, add = false) {
        const g = { c1: 0, c2: MAX_COLS - 1, r1: Math.min(r1, r2), r2: Math.max(r1, r2) }
        const left = this.grid.cols.visible(0)
        this.sel = { r: this.sel.r, c: this.sel.c, ranges: add ? [...this.sel.ranges, g] : [g], anchor: { r: r1, c: 0 }, end: { r: r2, c: MAX_COLS - 1 } }
        if (!add) { this.sel.r = Math.min(r1, r2); this.sel.c = left }
        this.afterSel(null)
    },

    afterSel(scrollTo) {
        if (scrollTo) this.grid.scrollTo(scrollTo[0], scrollTo[1])
        this.grid.updateExtent()
        this.grid.requestDraw()
        this.positionInput?.()
        this.refreshUI()
        this.onSelectionChange?.()
    },

    // 是否选择了整列 / 整行
    isFullCols(g = this.range) { return g.r1 === 0 && g.r2 >= MAX_ROWS - 1 },
    isFullRows(g = this.range) { return g.c1 === 0 && g.c2 >= MAX_COLS - 1 },

    // ---------- 键盘导航 ----------
    // 从 (r, c) 沿方向前进一步（跳过隐藏行列与合并区域）
    step(r, c, dr, dc) {
        const m = this.sheet.mergeAt(r, c)
        if (m) {
            if (dr > 0) r = m.r2; if (dr < 0) r = m.r1
            if (dc > 0) c = m.c2; if (dc < 0) c = m.c1
        }
        let nr = r + dr, nc = c + dc
        const G = this.grid
        if (dr) { nr = clamp(nr, 0, MAX_ROWS - 1); while (G.rows.isHidden(nr) && nr > 0 && nr < MAX_ROWS - 1) nr += dr; if (G.rows.isHidden(nr)) nr = r }
        if (dc) { nc = clamp(nc, 0, MAX_COLS - 1); while (G.cols.isHidden(nc) && nc > 0 && nc < MAX_COLS - 1) nc += dc; if (G.cols.isHidden(nc)) nc = c }
        return [nr, nc]
    },

    // Ctrl + 方向键：跳到数据块边界
    jump(r, c, dr, dc) {
        const sh = this.sheet
        const b = sh.bounds()
        const limR = dr > 0 ? MAX_ROWS - 1 : 0, limC = dc > 0 ? MAX_COLS - 1 : 0
        const get = (rr, cc) => sh.get(rr, cc)
        const out = (rr, cc) => rr < 0 || cc < 0 || rr >= MAX_ROWS || cc >= MAX_COLS
        const beyond = (rr, cc) => (dr > 0 && rr > b.r2) || (dc > 0 && cc > b.c2)
        let [nr, nc] = [r + dr, c + dc]
        if (out(nr, nc)) return [r, c]
        const curFilled = !isEmpty(get(r, c)), nextFilled = !isEmpty(get(nr, nc))
        if (curFilled && nextFilled) {
            // 到连续数据的末尾
            while (!out(nr + dr, nc + dc) && !isEmpty(get(nr + dr, nc + dc))) { nr += dr; nc += dc }
            return [nr, nc]
        }
        // 到下一个非空单元格，或边缘
        while (!out(nr, nc) && isEmpty(get(nr, nc))) {
            if (beyond(nr, nc)) return [dr ? limR : r, dc ? limC : c]
            nr += dr; nc += dc
        }
        if (out(nr, nc)) return [dr ? limR : r, dc ? limC : c]
        return [nr, nc]
    },

    moveActive(dr, dc, { extend = false, jump = false } = {}) {
        if (extend) {
            const e = this.sel.end ?? { r: this.sel.r, c: this.sel.c }
            const [nr, nc] = jump ? this.jump(e.r, e.c, dr, dc) : this.step(e.r, e.c, dr, dc)
            this.extendTo(nr, nc)
            return
        }
        const [nr, nc] = jump ? this.jump(this.sel.r, this.sel.c, dr, dc) : this.step(this.sel.r, this.sel.c, dr, dc)
        this.selectCell(nr, nc)
    },

    // Enter / Tab 在多单元格选区内循环移动
    moveWithin(dr, dc) {
        const g = this.range
        const single = this.sel.ranges.length === 1 && g.r1 === g.r2 && g.c1 === g.c2
        const m = this.sheet.mergeAt(g.r1, g.c1)
        const isMergeOnly = m && m.r1 === g.r1 && m.c1 === g.c1 && m.r2 === g.r2 && m.c2 === g.c2
        if (single || isMergeOnly) {
            // Tab 之后按 Enter 回到起始列（Excel 行为）
            if (dr > 0 && this.tabStart != null) {
                const c0 = this.tabStart
                this.tabStart = null
                const [nr] = this.step(this.sel.r, this.sel.c, 1, 0)
                return this.selectCell(nr, c0)
            }
            if (dc && this.tabStart == null) this.tabStart = this.sel.c
            if (dr) this.tabStart = null
            return this.moveActive(dr, dc)
        }
        let { r, c } = this.sel
        const next = () => {
            if (dr) {
                r += dr
                if (r > g.r2) { r = g.r1; c = c + 1 > g.c2 ? g.c1 : c + 1 }
                if (r < g.r1) { r = g.r2; c = c - 1 < g.c1 ? g.c2 : c - 1 }
            } else {
                c += dc
                if (c > g.c2) { c = g.c1; r = r + 1 > g.r2 ? g.r1 : r + 1 }
                if (c < g.c1) { c = g.c2; r = r - 1 < g.r1 ? g.r2 : r - 1 }
            }
        }
        next()
        let guard = 0
        while (guard++ < 10000) {
            const mm = this.sheet.mergeAt(r, c)
            if (!(mm && (mm.r1 !== r || mm.c1 !== c)) && !this.grid.rows.isHidden(r) && !this.grid.cols.isHidden(c)) break
            next()
        }
        this.sel = { ...this.sel, r, c }
        this.afterSel([r, c])
    },

    // 返回 true 表示已处理
    navKey(e) {
        const k = e.key, ctrl = e.ctrlKey || e.metaKey, shift = e.shiftKey
        const G = this.grid
        switch (k) {
            case 'ArrowUp': this.moveActive(-1, 0, { extend: shift, jump: ctrl }); return true
            case 'ArrowDown': this.moveActive(1, 0, { extend: shift, jump: ctrl }); return true
            case 'ArrowLeft': this.moveActive(0, -1, { extend: shift, jump: ctrl }); return true
            case 'ArrowRight': this.moveActive(0, 1, { extend: shift, jump: ctrl }); return true
            case 'Tab': this.moveWithin(0, shift ? -1 : 1); return true
            case 'Enter': this.moveWithin(shift ? -1 : 1, 0); return true
            case 'Home': {
                if (ctrl) { shift ? this.extendTo(G.fr, G.fc) : this.selectCell(G.rows.visible(0), G.cols.visible(0)) }
                else shift ? this.extendTo(this.sel.end?.r ?? this.sel.r, 0) : this.selectCell(this.sel.r, G.cols.visible(0))
                return true
            }
            case 'End': {
                const b = this.sheet.bounds()
                if (ctrl) { shift ? this.extendTo(Math.max(0, b.r2), Math.max(0, b.c2)) : this.selectCell(Math.max(0, b.r2), Math.max(0, b.c2)) }
                else {
                    // 当前行最后一个有数据的单元格
                    let last = 0
                    this.sheet.cells.each((r, c) => { if (c > last) last = c }, this.sel.r, 0, this.sel.r, MAX_COLS - 1)
                    shift ? this.extendTo(this.sel.r, last) : this.selectCell(this.sel.r, last)
                }
                return true
            }
            case 'PageDown': case 'PageUp': {
                const n = G.pageRows() * (k === 'PageDown' ? 1 : -1)
                if (e.altKey) {
                    const [c0, c1] = G.visibleCols()
                    const nc = clamp(this.sel.c + (c1 - c0) * Math.sign(n), 0, MAX_COLS - 1)
                    shift ? this.extendTo(this.sel.end?.r ?? this.sel.r, nc) : this.selectCell(this.sel.r, nc)
                } else {
                    const base = shift ? this.sel.end?.r ?? this.sel.r : this.sel.r
                    let nr = clamp(base + n, 0, MAX_ROWS - 1)
                    nr = G.rows.visible(nr, n > 0 ? 1 : -1)
                    G.setScroll(G.sx, G.sy + n * G.sheet.meta.defRowH)
                    shift ? this.extendTo(nr, this.sel.end?.c ?? this.sel.c) : this.selectCell(nr, this.sel.c)
                }
                return true
            }
        }
        return false
    },

    // ---------- 鼠标 ----------
    bindGrid() {
        const G = this.grid, el = G.scroller
        const local = e => {
            const r = G.el.getBoundingClientRect()
            return [e.clientX - r.left, e.clientY - r.top]
        }
        this.listen(el, 'pointerdown', e => this.onGridDown(e, local))
        this.listen(el, 'dblclick', e => this.onGridDbl(e, local))
        this.listen(el, 'pointermove', e => {
            if (this.dragging) return
            const [x, y] = local(e)
            if (x > el.clientWidth || y > el.clientHeight) { el.style.cursor = ''; return }
            const hit = G.hit(x, y)
            el.style.cursor = hit.area === 'colresize' ? 'col-resize' : hit.area === 'rowresize' ? 'row-resize'
                : hit.area === 'fill' ? 'crosshair' : hit.area === 'colhead' ? 's-resize' : hit.area === 'rowhead' ? 'e-resize'
                : hit.area === 'filter' || hit.area === 'dvlist' ? 'pointer' : hit.area === 'cell' ? (this.painter ? 'copy' : 'cell') : 'default'
            this.hoverTip?.(hit, e)
        })
        this.listen(el, 'contextmenu', e => {
            const [x, y] = local(e)
            const hit = G.hit(x, y)
            if (hit.area === 'cell' && !this.inSelection(hit.r, hit.c)) this.selectCell(hit.r, hit.c, { scroll: false })
            if (hit.area === 'colhead' && !(this.isFullCols() && hit.c >= this.range.c1 && hit.c <= this.range.c2)) this.selectCols(hit.c, hit.c)
            if (hit.area === 'rowhead' && !(this.isFullRows() && hit.r >= this.range.r1 && hit.r <= this.range.r2)) this.selectRows(hit.r, hit.r)
            const items = hit.area === 'colhead' ? this.colMenu() : hit.area === 'rowhead' ? this.rowMenu() : this.cellMenu()
            contextMenu(e, items)
        })
        // 滚轮：Ctrl 缩放
        this.listen(el, 'wheel', e => {
            if (e.ctrlKey) {
                e.preventDefault()
                this.setZoom(this.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1))
            }
        }, { passive: false })
    },

    onGridDbl(e, local) {
        const [x, y] = local(e)
        const hit = this.grid.hit(x, y)
        if (hit.area === 'colresize') return this.autoFitCols(this.isFullCols() && this.inSelection(0, hit.c) ? [this.range.c1, this.range.c2] : [hit.c, hit.c])
        if (hit.area === 'rowresize') return this.autoFitRows(this.isFullRows() && this.inSelection(hit.r, 0) ? [this.range.r1, this.range.r2] : [hit.r, hit.r])
        if (hit.area === 'fill') return this.fillDownAuto()
        if (hit.area === 'cell') this.startEdit({ mode: 'edit' })
    },

    onGridDown(e, local) {
        if (e.button === 2) return
        const G = this.grid, el = G.scroller
        const [x, y] = local(e)
        if (x > el.clientWidth || y > el.clientHeight) return // 滚动条
        const hit = G.hit(x, y)
        this.selectChart?.(null)
        if (e.button !== 0) return
        e.preventDefault()
        // 公式编辑中：点击单元格插入引用
        if (this.editing && hit.area === 'cell' && this.canPickRef()) {
            this.pickRef(hit.r, hit.c, e.shiftKey)
            this.dragLoop(e, (xx, yy) => this.pickRefExtend(G.rowAtClamped(yy), G.colAtClamped(xx)))
            return
        }
        if (this.editing && hit.area !== 'filter') this.commitEdit()
        this.focusGrid()
        const add = e.ctrlKey || e.metaKey
        switch (hit.area) {
            case 'corner': this.selectAll(); return
            case 'colresize': return this.dragResize('col', hit.c, x, e)
            case 'rowresize': return this.dragResize('row', hit.r, y, e)
            case 'filter': return this.openFilterMenu(hit.c)
            case 'dvlist': return this.openValidationList()
            case 'fill': return this.dragFill(e, local)
            case 'colhead': {
                if (e.shiftKey) this.selectCols(this.sel.anchor.c, hit.c)
                else this.selectCols(hit.c, hit.c, add)
                const c0 = e.shiftKey ? this.sel.anchor.c : hit.c
                this.dragLoop(e, xx => {
                    const c = G.colAtClamped(xx)
                    const ranges = [...this.sel.ranges]
                    ranges[ranges.length - 1] = { r1: 0, r2: MAX_ROWS - 1, c1: Math.min(c0, c), c2: Math.max(c0, c) }
                    this.sel = { ...this.sel, ranges }
                    this.afterSel(null)
                }, { autoY: false })
                return
            }
            case 'rowhead': {
                if (e.shiftKey) this.selectRows(this.sel.anchor.r, hit.r)
                else this.selectRows(hit.r, hit.r, add)
                const r0 = e.shiftKey ? this.sel.anchor.r : hit.r
                this.dragLoop(e, (xx, yy) => {
                    const r = G.rowAtClamped(yy)
                    const ranges = [...this.sel.ranges]
                    ranges[ranges.length - 1] = { c1: 0, c2: MAX_COLS - 1, r1: Math.min(r0, r), r2: Math.max(r0, r) }
                    this.sel = { ...this.sel, ranges }
                    this.afterSel(null)
                }, { autoX: false })
                return
            }
            case 'cell': {
                // 拖动选区边框移动单元格
                if (!add && !e.shiftKey && this.onSelBorder(x, y)) return this.dragMove(e, local, hit)
                if (e.shiftKey) this.extendTo(hit.r, hit.c, false)
                else if (add) {
                    const m = this.sheet.mergeAt(hit.r, hit.c)
                    this.selectRange(m ?? { r1: hit.r, c1: hit.c, r2: hit.r, c2: hit.c }, { add: true, active: { r: m?.r1 ?? hit.r, c: m?.c1 ?? hit.c } })
                } else this.selectCell(hit.r, hit.c, { scroll: false })
                this.dragLoop(e, (xx, yy) => this.extendTo(G.rowAtClamped(yy), G.colAtClamped(xx), false), {
                    end: () => { if (this.painter) this.applyPainter() },
                })
            }
        }
    },

    // 鼠标是否位于当前选区边框上
    onSelBorder(x, y) {
        if (this.sel.ranges.length !== 1) return false
        const g = this.range
        if (this.isFullCols(g) || this.isFullRows(g)) return false
        const R = this.grid.rangeRect(g)
        const tol = 3
        const inY = y >= R.y - tol && y <= R.y + R.h + tol, inX = x >= R.x - tol && x <= R.x + R.w + tol
        const nearX = Math.abs(x - R.x) <= tol || Math.abs(x - (R.x + R.w)) <= tol
        const nearY = Math.abs(y - R.y) <= tol || Math.abs(y - (R.y + R.h)) <= tol
        return (nearX && inY) || (nearY && inX)
    },

    // 通用拖动循环，带边缘自动滚动
    dragLoop(e0, onMove, { autoX = true, autoY = true, end } = {}) {
        const G = this.grid
        const box = () => G.el.getBoundingClientRect()
        let last = [e0.clientX, e0.clientY]
        let timer = null
        this.dragging = true
        const apply = () => {
            const b = box()
            onMove(last[0] - b.left, last[1] - b.top)
        }
        const auto = () => {
            const b = box()
            const x = last[0] - b.left, y = last[1] - b.top
            let dx = 0, dy = 0
            if (autoX) { if (x > G.W - 4) dx = (x - G.W + 4) / 2 + 8; else if (x < G.HW + G.frozenW && G.sx > 0) dx = -((G.HW + G.frozenW - x) / 2 + 8) }
            if (autoY) { if (y > G.H - 4) dy = (y - G.H + 4) / 2 + 8; else if (y < G.HH + G.frozenH && G.sy > 0) dy = -((G.HH + G.frozenH - y) / 2 + 8) }
            if (dx || dy) { G.setScroll(G.sx + dx / G.z, G.sy + dy / G.z); apply() }
        }
        const move = e => { last = [e.clientX, e.clientY]; apply() }
        const up = () => {
            clearInterval(timer)
            this.dragging = false
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            end?.()
        }
        timer = setInterval(auto, 40)
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    },

    // 行高 / 列宽拖动
    dragResize(kind, i, start, e0) {
        const G = this.grid
        const sh = this.sheet
        const orig = kind === 'col' ? sh.colWidth(i) : sh.rowHeight(i)
        const sel = kind === 'col' ? (this.isFullCols() && i >= this.range.c1 && i <= this.range.c2 ? [this.range.c1, this.range.c2] : [i, i])
            : (this.isFullRows() && i >= this.range.r1 && i <= this.range.r2 ? [this.range.r1, this.range.r2] : [i, i])
        const tip = this.showTip()
        let size = orig
        this.dragLoop(e0, (x, y) => {
            const d = ((kind === 'col' ? x : y) - start) / G.z
            size = Math.max(0, Math.round(orig + d))
            // 实时预览：直接修改当前 meta（结束时再提交）
            const key = kind === 'col' ? 'colW' : 'rowH'
            sh.update(key, m => { m.set(i, size); return m })
            G.draw()
            tip(kind === 'col' ? `宽度：${size} 像素` : `高度：${size} 像素`, e0.clientX + (kind === 'col' ? x - start : 0), e0.clientY + (kind === 'row' ? y - start : 0))
        }, {
            autoX: false, autoY: false,
            end: () => {
                tip(null)
                if (size === orig) return
                this.setSize(kind, sel[0], sel[1], size)
            },
        })
    },

    // 浮动提示
    showTip() {
        const el = document.createElement('div')
        el.className = 'sh-tip'
        document.body.append(el)
        return (text, x, y) => {
            if (text == null) { el.remove(); return }
            el.textContent = text
            el.style.left = x + 12 + 'px'
            el.style.top = y + 14 + 'px'
        }
    },

    // 拖动选区移动单元格（Ctrl 复制）
    dragMove(e0, local, hit0) {
        const G = this.grid
        const g = this.range
        const dr0 = hit0.r - g.r1, dc0 = hit0.c - g.c1
        let target = null
        this.dragLoop(e0, (x, y) => {
            const r = G.rowAtClamped(y), c = G.colAtClamped(x)
            const r1 = clamp(r - dr0, 0, MAX_ROWS - 1 - (g.r2 - g.r1)), c1 = clamp(c - dc0, 0, MAX_COLS - 1 - (g.c2 - g.c1))
            target = { r1, c1, r2: r1 + g.r2 - g.r1, c2: c1 + g.c2 - g.c1 }
            this.dragPreview = target
            G.requestDraw()
        }, {
            end: () => {
                this.dragPreview = null
                if (target && (target.r1 !== g.r1 || target.c1 !== g.c1)) this.moveCells(g, target, { copy: e0.ctrlKey })
                else G.requestDraw()
            },
        })
    },

    // 填充柄拖动
    dragFill(e0) {
        const G = this.grid
        const g = this.range
        let target = null
        this.dragLoop(e0, (x, y) => {
            const r = G.rowAtClamped(y), c = G.colAtClamped(x)
            // 选择主方向
            const downBy = r > g.r2 ? r - g.r2 : r < g.r1 ? r - g.r1 : 0
            const rightBy = c > g.c2 ? c - g.c2 : c < g.c1 ? c - g.c1 : 0
            const hr = Math.abs(downBy) * this.sheet.meta.defRowH, hc = Math.abs(rightBy) * this.sheet.meta.defColW
            if (!downBy && !rightBy) target = null
            else if (hr >= hc) target = downBy > 0 ? { ...g, r2: r } : { ...g, r1: r }
            else target = rightBy > 0 ? { ...g, c2: c } : { ...g, c1: c }
            this.fillPreview = target
            G.requestDraw()
        }, {
            end: () => {
                this.fillPreview = null
                if (target) this.fillRange(g, target)
                else G.requestDraw()
            },
        })
    },
}

export { isEmpty }
