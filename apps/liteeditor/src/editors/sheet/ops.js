// 修改操作：写入单元格、样式、合并、行列插入删除、尺寸、移动、填充、工作表管理
import { toast, confirmDialog, prompt } from '../../core/dom.js'
import { MAX_ROWS, MAX_COLS, intersects, inRange, parseRange } from './addr.js'
import { makeCell, internStyle, mergeStyle, Sheet } from './model.js'
import { parseInput } from './editing.js'
import { shiftFormula, adjustFormula, renameSheetInFormula, moveRefsInFormula } from './formula/lexer.js'
import { fontString, display } from './format.js'
import { wrapLines } from './render.js'

export const Ops = {
    shiftText(f, dr, dc) { return shiftFormula(f, dr, dc) },

    // 写入区域时限定到已用区域（整行 / 整列），但保证至少包含活动单元格
    clampUsedForWrite(g) {
        const b = this.sheet.bounds()
        return { r1: g.r1, c1: g.c1, r2: Math.min(g.r2, Math.max(g.r1, b.r2, this.sel.r)), c2: Math.min(g.c2, Math.max(g.c1, b.c2, this.sel.c)) }
    },

    // 设置单元格内容（来自编辑框文本）
    setInput(r, c, text, sh = this.sheet, { commit = true } = {}) {
        const old = sh.get(r, c)
        const p = parseInput(text, old?.s?.fmt)
        let s = old?.s ?? sh.styleAt(r, c, old)
        if (p.fmt && (!s?.fmt || s.fmt === 'General')) s = mergeStyle(s, { fmt: p.fmt })
        sh.set(r, c, makeCell(p.v, p.f, s))
        if (p.f && /^[A-Z]+\d*$/i.test(p.f) === false) this.autoFormatFormula?.(sh, r, c)
        this.changed([[sh, r, c]])
        this.autoRowHeight(sh, r)
        if (commit) this.commit('编辑单元格')
    },

    setInputRanges(ranges, text, e) {
        const sh = this.sheet
        const list = []
        const baseR = e?.r ?? this.sel.r, baseC = e?.c ?? this.sel.c
        const p0 = parseInput(text)
        for (const g of ranges) for (let r = g.r1; r <= g.r2; r++) for (let c = g.c1; c <= g.c2; c++) {
            const old = sh.get(r, c)
            let s = old?.s ?? sh.styleAt(r, c, old)
            if (p0.fmt && !s?.fmt) s = mergeStyle(s, { fmt: p0.fmt })
            const f = p0.f ? shiftFormula(p0.f, r - baseR, c - baseC) : null
            sh.set(r, c, makeCell(p0.v, f, s))
            list.push([sh, r, c])
        }
        this.changed(list)
        this.commit('填充选区')
    },

    // 批量写：fn(set) 中调用 set(r, c, cell)
    batch(label, fn, { sh = this.sheet, structural = false, noCommit = false } = {}) {
        const list = []
        const set = (r, c, cell) => { sh.set(r, c, cell); list.push([sh, r, c]) }
        fn(set, sh)
        if (list.length || structural) this.changed(list, { structural: structural || list.length > 20000 })
        if (!noCommit) this.commit(label)
        return list
    },

    clearContents() {
        const sh = this.sheet
        this.batch('清除内容', set => {
            for (const g0 of this.sel.ranges) {
                const g = this.clampUsed(g0)
                sh.cells.each((r, c, cell) => {
                    if (cell.v == null && !cell.f) return
                    set(r, c, cell.s ? { s: cell.s } : null)
                }, g.r1, g.c1, g.r2, g.c2)
            }
        })
    },

    clearAll(what = 'all') {
        const sh = this.sheet
        this.batch(what === 'format' ? '清除格式' : '全部清除', set => {
            for (const g0 of this.sel.ranges) {
                const g = this.clampUsed(g0)
                sh.cells.each((r, c, cell) => {
                    if (what === 'format') set(r, c, cell.s ? makeCell(cell.v, cell.f, null) : cell)
                    else set(r, c, null)
                }, g.r1, g.c1, g.r2, g.c2)
                if (this.isFullCols(g0)) sh.update('colStyle', m => { for (let c = g0.c1; c <= g0.c2; c++) m.delete(c) })
                if (this.isFullRows(g0)) sh.update('rowStyle', m => { for (let r = g0.r1; r <= g0.r2; r++) m.delete(r) })
                if (what === 'all' || what === 'format') {
                    sh.setMeta({ cf: sh.meta.cf.filter(rule => !(rule.range.r1 >= g0.r1 && rule.range.r2 <= g0.r2 && rule.range.c1 >= g0.c1 && rule.range.c2 <= g0.c2)) })
                }
            }
        }, { structural: true })
    },

    // ---------- 样式 ----------
    // patch 为样式字段；fn(style, r, c) 可返回自定义补丁（边框用）
    applyStyle(patch, label = '设置格式', fn) {
        const sh = this.sheet
        const make = (s, r, c) => {
            const p = fn ? fn(s, r, c) : patch
            return p ? mergeStyle(s, p) : s
        }
        this.batch(label, set => {
            for (const g of this.sel.ranges) {
                const fullC = this.isFullCols(g), fullR = this.isFullRows(g)
                if (fullC || fullR) {
                    // 整行 / 整列：写入行列样式，并更新已存在的单元格
                    if (fullC && !fullR) sh.update('colStyle', m => { for (let c = g.c1; c <= g.c2; c++) { const s = make(m.get(c), 0, c); s ? m.set(c, s) : m.delete(c) } })
                    else if (fullR) sh.update('rowStyle', m => { for (let r = g.r1; r <= Math.min(g.r2, 100000); r++) { const s = make(m.get(r), r, 0); s ? m.set(r, s) : m.delete(r) } })
                    const u = this.clampUsed(g)
                    sh.cells.each((r, c, cell) => set(r, c, makeCell(cell.v, cell.f, make(cell.s, r, c)) ?? null), u.r1, u.c1, u.r2, u.c2)
                    continue
                }
                for (let r = g.r1; r <= g.r2; r++) for (let c = g.c1; c <= g.c2; c++) {
                    const cell = sh.get(r, c)
                    const base = cell ? cell.s : sh.styleAt(r, c, null)
                    const s = make(base, r, c)
                    if (s === (cell?.s ?? null) && cell) continue
                    set(r, c, makeCell(cell?.v, cell?.f, s))
                }
            }
        }, { structural: false })
        if ('sz' in (patch ?? {}) || 'wrap' in (patch ?? {}) || 'font' in (patch ?? {})) {
            for (const g of this.sel.ranges) { const u = this.clampUsed(g); for (let r = u.r1; r <= Math.min(u.r2, u.r1 + 2000); r++) this.autoRowHeight(sh, r) }
            this.grid.updateExtent(); this.grid.requestDraw()
        }
    },

    toggleStyle(key) {
        const s = this.sheet.styleAt(this.sel.r, this.sel.c)
        this.applyStyle({ [key]: !s?.[key] }, key === 'b' ? '加粗' : key === 'i' ? '倾斜' : key === 'u' ? '下划线' : key === 'st' ? '删除线' : '自动换行')
    },

    // 边框预设：all outer inner top bottom left right none thick-outer inside-h inside-v
    applyBorder(kind, spec = 'thin #000000') {
        const gs = this.sel.ranges
        const line = spec
        this.applyStyle(null, '边框', (s, r, c) => {
            const g = gs.find(g => inRange(g, r, c))
            if (!g) return null
            const top = r === g.r1, bottom = r === g.r2, left = c === g.c1, right = c === g.c2
            switch (kind) {
                case 'none': return { bt: null, bb: null, bl: null, br: null }
                case 'all': return { bt: line, bb: line, bl: line, br: line }
                case 'outer': return { ...(top ? { bt: line } : {}), ...(bottom ? { bb: line } : {}), ...(left ? { bl: line } : {}), ...(right ? { br: line } : {}) }
                case 'thick': { const t = 'medium ' + line.split(' ')[1]; return { ...(top ? { bt: t } : {}), ...(bottom ? { bb: t } : {}), ...(left ? { bl: t } : {}), ...(right ? { br: t } : {}) } }
                case 'inner': return { ...(!bottom ? { bb: line } : {}), ...(!right ? { br: line } : {}), ...(!top ? { bt: line } : {}), ...(!left ? { bl: line } : {}) }
                case 'top': return top ? { bt: line } : {}
                case 'bottom': return bottom ? { bb: line } : {}
                case 'left': return left ? { bl: line } : {}
                case 'right': return right ? { br: line } : {}
                case 'double-bottom': return bottom ? { bb: 'double ' + line.split(' ')[1] } : {}
                case 'inside-h': return { ...(!bottom ? { bb: line } : {}), ...(!top ? { bt: line } : {}) }
                case 'inside-v': return { ...(!right ? { br: line } : {}), ...(!left ? { bl: line } : {}) }
            }
            return null
        })
    },

    // ---------- 格式刷 ----------
    startPainter(sticky = false) {
        const g = this.range
        const sh = this.sheet
        const styles = []
        for (let r = g.r1; r <= Math.min(g.r2, g.r1 + 200); r++) {
            const row = []
            for (let c = g.c1; c <= Math.min(g.c2, g.c1 + 100); c++) row.push(sh.styleAt(r, c))
            styles.push(row)
        }
        const merges = sh.meta.merges.filter(m => m.r1 >= g.r1 && m.r2 <= g.r2 && m.c1 >= g.c1 && m.c2 <= g.c2).map(m => ({ r1: m.r1 - g.r1, c1: m.c1 - g.c1, r2: m.r2 - g.r1, c2: m.c2 - g.c1 }))
        this.painter = { styles, merges, sticky }
        this.refreshUI()
        toast(sticky ? '格式刷已锁定：选择目标区域，按 Esc 结束' : '选择要应用格式的区域')
    },
    applyPainter() {
        const p = this.painter
        if (!p) return
        const g = this.range
        const sh = this.sheet
        const R = p.styles.length, C = p.styles[0].length
        const tr2 = Math.max(g.r2, g.r1 + R - 1), tc2 = Math.max(g.c2, g.c1 + C - 1)
        this.batch('格式刷', set => {
            for (let r = g.r1; r <= Math.min(tr2, g.r1 + 5000); r++) for (let c = g.c1; c <= Math.min(tc2, g.c1 + 500); c++) {
                const s = p.styles[(r - g.r1) % R][(c - g.c1) % C]
                const cell = sh.get(r, c)
                set(r, c, makeCell(cell?.v, cell?.f, s))
            }
            if (p.merges.length) {
                const keep = sh.meta.merges.filter(m => !intersects(m, { r1: g.r1, c1: g.c1, r2: tr2, c2: tc2 }))
                sh.setMeta({ merges: [...keep, ...p.merges.map(m => ({ r1: m.r1 + g.r1, c1: m.c1 + g.c1, r2: m.r2 + g.r1, c2: m.c2 + g.c1 }))] })
            }
        })
        if (!p.sticky) this.painter = null
        this.refreshUI()
    },

    // ---------- 合并 ----------
    mergeCells(mode = 'merge') {
        const sh = this.sheet
        const g = this.clampUsedForWrite(this.range)
        const existing = sh.meta.merges.filter(m => intersects(m, g))
        if (mode === 'unmerge' || (mode === 'toggle' && existing.length && existing.every(m => m.r1 >= g.r1 && m.r2 <= g.r2 && m.c1 >= g.c1 && m.c2 <= g.c2) && existing.some(m => m.r1 === g.r1 && m.c1 === g.c1 && m.r2 === g.r2 && m.c2 === g.c2))) {
            sh.setMeta({ merges: sh.meta.merges.filter(m => !intersects(m, g)) })
            this.changed([], { structural: false })
            this.commit('取消合并')
            return
        }
        if (g.r1 === g.r2 && g.c1 === g.c2) return
        const add = []
        if (mode === 'across') for (let r = g.r1; r <= g.r2; r++) add.push({ r1: r, c1: g.c1, r2: r, c2: g.c2 })
        else add.push({ ...g })
        // 合并时只保留左上角的值
        let lost = 0
        sh.cells.each((r, c, cell) => {
            const keepCell = add.some(m => m.r1 === r && m.c1 === c)
            if (!keepCell && (cell.v != null || cell.f)) lost++
        }, g.r1, g.c1, g.r2, g.c2)
        const doMerge = () => {
            this.batch('合并单元格', set => {
                sh.cells.each((r, c, cell) => {
                    if (add.some(m => m.r1 === r && m.c1 === c)) return
                    if (cell.v != null || cell.f) set(r, c, cell.s ? { s: cell.s } : null)
                }, g.r1, g.c1, g.r2, g.c2)
                sh.setMeta({ merges: [...sh.meta.merges.filter(m => !intersects(m, g)), ...add] })
                if (mode === 'center') {
                    const cell = sh.get(g.r1, g.c1)
                    set(g.r1, g.c1, makeCell(cell?.v, cell?.f, mergeStyle(cell?.s ?? sh.styleAt(g.r1, g.c1), { ha: 'center', va: 'middle' })))
                }
            })
            this.selectRange(g)
        }
        if (lost) confirmDialog({ title: '合并单元格', message: '合并后只保留左上角单元格的值，其余值将被丢弃。', okText: '合并' }).then(ok => ok && doMerge())
        else doMerge()
    },

    // ---------- 尺寸 ----------
    setSize(kind, i1, i2, size) {
        const sh = this.sheet
        const key = kind === 'col' ? 'colW' : 'rowH'
        const hid = kind === 'col' ? 'hiddenC' : 'hiddenR'
        sh.update(key, m => { for (let i = i1; i <= Math.min(i2, i1 + 100000); i++) m.set(i, Math.max(0, size)) })
        if (size > 0 && [...sh.meta[hid]].some(i => i >= i1 && i <= i2)) sh.update(hid, s => { for (let i = i1; i <= i2; i++) s.delete(i) })
        if (size === 0) sh.update(hid, s => { for (let i = i1; i <= Math.min(i2, i1 + 100000); i++) s.add(i) })
        if (kind === 'row' && sh.meta.rowAuto) sh.update('rowAuto', s => { for (let i = i1; i <= Math.min(i2, i1 + 100000); i++) s.delete(i) })
        this.invalidate()
        this.commit(kind === 'col' ? '调整列宽' : '调整行高')
    },

    // 双击边界：列宽自适应内容
    autoFitCols([c1, c2]) {
        const sh = this.sheet, G = this.grid
        const b = sh.bounds()
        const widths = new Map()
        sh.cells.each((r, c, cell) => {
            if (cell.v == null && !cell.f) return
            if (G.rows.isHidden(r)) return
            const m = sh.mergeAt(r, c)
            if (m && m.c1 !== m.c2) return
            const st = sh.styleAt(r, c, cell)
            if (st?.wrap) return
            const { text } = display(this.valueOf(sh, r, c, cell), st?.fmt)
            const w = Math.max(...String(text).split('\n').map(t => G.measure(fontString(st, 1), t))) + 12 + (sh.meta.filter?.range.r1 === r ? 22 : 0)
            widths.set(c, Math.max(widths.get(c) ?? 0, w))
        }, 0, c1, Math.max(0, b.r2), c2)
        sh.update('colW', m => { for (let c = c1; c <= c2; c++) m.set(c, Math.ceil(Math.max(24, Math.min(600, widths.get(c) ?? sh.meta.defColW)))) })
        sh.update('hiddenC', s => { for (let c = c1; c <= c2; c++) s.delete(c) })
        this.invalidate()
        this.commit('自动调整列宽')
    },
    autoFitRows([r1, r2]) {
        const sh = this.sheet
        sh.update('rowH', m => { for (let r = r1; r <= Math.min(r2, r1 + 100000); r++) m.delete(r) })
        sh.update('hiddenR', s => { for (let r = r1; r <= r2; r++) s.delete(r) })
        for (let r = r1; r <= Math.min(r2, sh.bounds().r2); r++) this.autoRowHeight(sh, r, true)
        this.invalidate()
        this.commit('自动调整行高')
    },
    // 根据字号 / 换行自动增高行（仅对没有手动设置行高的行）
    autoRowHeight(sh, r, force = false) {
        if (!force && sh.meta.rowH.has(r) && !sh.meta.rowAuto?.has(r)) return
        let need = sh.meta.defRowH
        const G = this.grid
        sh.cells.each((rr, c, cell) => {
            const st = sh.styleAt(r, c, cell)
            if (!st) return
            const m = sh.mergeAt(r, c)
            if (m && m.r1 !== m.r2) return
            const lineH = (st.sz ?? 11) * 4 / 3 * 1.3
            let lines = 1
            if (st.wrap && (cell.v != null || cell.f)) {
                const w = m ? G.cols.pos(m.c2 + 1) - G.cols.pos(m.c1) : sh.colWidth(c)
                const { text } = display(this.valueOf(sh, r, c, cell), st.fmt)
                lines = wrapLines(G, fontString(st, 1), text, Math.max(4, w - 8)).length
            }
            need = Math.max(need, Math.ceil(lineH * lines + 6))
        }, r, 0, r, MAX_COLS - 1)
        const cur = sh.meta.rowH.get(r)
        if (need > sh.meta.defRowH) {
            if (cur !== need) { sh.update('rowH', m => { m.set(r, need) }); sh.update('rowAuto', s => { s = s instanceof Set ? s : new Set(); s.add(r); return s }) }
        } else if (cur != null && (sh.meta.rowAuto?.has(r) || force)) {
            sh.update('rowH', m => { m.delete(r) })
            if (sh.meta.rowAuto) sh.update('rowAuto', s => { s.delete(r) })
        }
    },

    hideRowsCols(kind, hide = true) {
        const sh = this.sheet
        const g = this.range
        const key = kind === 'col' ? 'hiddenC' : 'hiddenR'
        const [a, b] = kind === 'col' ? [g.c1, g.c2] : [g.r1, g.r2]
        sh.update(key, s => { for (let i = a; i <= Math.min(b, a + 100000); i++) hide ? s.add(i) : s.delete(i) })
        if (!hide) sh.update(kind === 'col' ? 'colW' : 'rowH', m => { for (let i = a; i <= b; i++) if (m.get(i) === 0) m.delete(i) })
        this.invalidate()
        this.commit(hide ? (kind === 'col' ? '隐藏列' : '隐藏行') : (kind === 'col' ? '取消隐藏列' : '取消隐藏行'))
        if (hide) this.selectCell(kind === 'row' ? this.grid.rows.visible(g.r2 + 1) : g.r1, kind === 'col' ? this.grid.cols.visible(g.c2 + 1) : g.c1)
    },

    // ---------- 冻结与缩放 ----------
    setFreeze(r, c) {
        const sh = this.sheet
        sh.setMeta({ freeze: { r, c } })
        this.grid.setScroll(0, 0)
        this.invalidate()
        this.commit('冻结窗格')
    },
    setZoom(z) {
        z = Math.max(0.25, Math.min(4, Math.round(z * 100) / 100))
        if (z === this.zoom) return
        const G = this.grid
        this.zoom = z
        this.grid.measureCache.clear()
        const { sx, sy } = G
        G.setScroll(sx, sy)
        G.layout()
        this.positionInput()
        this.layoutEditor()
        this.renderCharts?.()
        this.refreshUI()
        import('../../core/store.js').then(s => s.setPref('sheet', { ...s.getPref('sheet', {}), zoom: z }))
    },
    toggleGridlines() {
        this.sheet.setMeta({ showGrid: !this.sheet.meta.showGrid })
        this.invalidate()
        this.commit('网格线')
    },

    // ---------- 行列插入 / 删除 ----------
    // axis 'row'|'col'，at 起点，n > 0 插入，n < 0 删除
    shiftAxis(axis, at, n) {
        const sh = this.sheet
        const isRow = axis === 'row'
        const cells = sh.cells.sorted()
        const adjust = (f, fsh) => adjustFormula(f, { axis, at, count: n, targetSheet: sh.name, formulaSheet: fsh.name })
        // 1. 移动本表单元格
        const del = n < 0 ? -n : 0
        const next = []
        for (const [r, c, cell] of cells) {
            const i = isRow ? r : c
            let ni = i
            if (n > 0 && i >= at) ni = i + n
            if (n < 0) { if (i >= at && i < at + del) continue; if (i >= at + del) ni = i + n }
            if (ni >= (isRow ? MAX_ROWS : MAX_COLS)) continue
            const nr = isRow ? ni : r, nc = isRow ? c : ni
            const nf = cell.f ? adjust(cell.f, sh) : null
            next.push([nr, nc, nf !== cell.f ? { ...cell, f: nf } : cell])
        }
        for (const [r, c] of cells) sh.cells.set(r, c, null)
        for (const [r, c, cell] of next) sh.cells.set(r, c, cell)
        // 2. 其他表中引用本表的公式
        for (const other of this.sheets) {
            if (other === sh) continue
            other.cells.each((r, c, cell) => {
                if (!cell.f || !cell.f.includes('!')) return
                const nf = adjust(cell.f, other)
                if (nf !== cell.f) other.cells.set(r, c, { ...cell, f: nf })
            })
        }
        // 3. 行列属性
        const shiftMap = m => {
            const out = new Map()
            for (const [i, v] of m) {
                if (n > 0) out.set(i >= at ? i + n : i, v)
                else if (i < at) out.set(i, v)
                else if (i >= at + del) out.set(i + n, v)
            }
            return out
        }
        const shiftSet = s => new Set([...shiftMap(new Map([...s].map(i => [i, 1]))).keys()])
        const shiftIdx = i => n > 0 ? (i >= at ? i + n : i) : i < at ? i : i >= at + del ? i + n : null
        const shiftRange = g => {
            const a = isRow ? 'r1' : 'c1', b = isRow ? 'r2' : 'c2'
            let x = g[a], y = g[b]
            if (n > 0) { if (x >= at) x += n; if (y >= at) y += n }
            else {
                if (x >= at && y < at + del) return null
                x = x < at ? x : x >= at + del ? x + n : at
                y = y < at ? y : y >= at + del ? y + n : at - 1
                if (y < x) return null
            }
            return { ...g, [a]: x, [b]: y }
        }
        const m = sh.meta
        const patch = {}
        if (isRow) { patch.rowH = shiftMap(m.rowH); patch.hiddenR = shiftSet(m.hiddenR); patch.rowStyle = shiftMap(m.rowStyle); if (m.rowAuto) patch.rowAuto = shiftSet(m.rowAuto) }
        else { patch.colW = shiftMap(m.colW); patch.hiddenC = shiftSet(m.hiddenC); patch.colStyle = shiftMap(m.colStyle) }
        patch.merges = m.merges.map(shiftRange).filter(g => g && (g.r1 !== g.r2 || g.c1 !== g.c2))
        patch.cf = m.cf.map(rule => { const rg = shiftRange(rule.range); return rg && { ...rule, range: rg } }).filter(Boolean)
        patch.validations = m.validations.map(v => { const rg = shiftRange(v.range); return rg && { ...v, range: rg } }).filter(Boolean)
        if (m.filter) {
            const rg = shiftRange(m.filter.range)
            if (!rg) patch.filter = null
            else {
                let cols = m.filter.cols
                if (!isRow && cols) { cols = {}; for (const [k, v] of Object.entries(m.filter.cols)) { const ni = shiftIdx(+k); if (ni != null) cols[ni] = v } }
                patch.filter = { ...m.filter, range: rg, cols, hidden: isRow ? shiftSet(m.filter.hidden ?? new Set()) : m.filter.hidden }
            }
        }
        const fz = { ...m.freeze }
        if (isRow && n < 0 && fz.r > at) fz.r = Math.max(at, fz.r + n)
        if (!isRow && n < 0 && fz.c > at) fz.c = Math.max(at, fz.c + n)
        if (isRow && n > 0 && fz.r > at) fz.r += n
        if (!isRow && n > 0 && fz.c > at) fz.c += n
        patch.freeze = fz
        sh.setMeta(patch)
        // 4. 图表数据区域
        for (const s of this.sheets) {
            if (!s.meta.charts.length) continue
            s.setMeta({ charts: s.meta.charts.map(ch => {
                if ((ch.sheet ?? s.name) !== sh.name) return ch
                const rg = shiftRange(ch.range)
                return rg ? { ...ch, range: rg } : ch
            }) })
        }
        sh.boundsCache = null
        this.engine.rebuild()
        this.cfCache.clear()
        this.renderCharts?.()
        this.invalidate()
    },

    insertRows(where = 'above') {
        const g = this.range
        const n = this.isFullCols(g) ? 1 : g.r2 - g.r1 + 1
        const at = where === 'above' ? g.r1 : g.r2 + 1
        this.shiftAxis('row', at, Math.min(n, 10000))
        this.selectRows(at, at + n - 1)
        this.commit('插入行')
    },
    insertCols(where = 'left') {
        const g = this.range
        const n = this.isFullRows(g) ? 1 : g.c2 - g.c1 + 1
        const at = where === 'left' ? g.c1 : g.c2 + 1
        this.shiftAxis('col', at, Math.min(n, 1000))
        this.selectCols(at, at + n - 1)
        this.commit('插入列')
    },
    deleteRows() {
        const g = this.range
        if (this.isFullCols(g)) return toast('不能删除所有行', 'warn')
        this.shiftAxis('row', g.r1, -(g.r2 - g.r1 + 1))
        this.selectCell(g.r1, this.sel.c)
        this.commit('删除行')
    },
    deleteCols() {
        const g = this.range
        if (this.isFullRows(g)) return toast('不能删除所有列', 'warn')
        this.shiftAxis('col', g.c1, -(g.c2 - g.c1 + 1))
        this.selectCell(this.sel.r, g.c1)
        this.commit('删除列')
    },
    // 插入 / 删除单元格并移动
    shiftCells(mode) {
        const g = this.clampUsedForWrite(this.range)
        const sh = this.sheet
        const b = sh.bounds()
        if (mode === 'down' || mode === 'up') {
            const n = g.r2 - g.r1 + 1
            const src = { r1: mode === 'down' ? g.r1 : g.r2 + 1, c1: g.c1, r2: Math.max(b.r2, g.r2), c2: g.c2 }
            if (mode === 'up') this.batch('', set => sh.cells.each((r, c) => set(r, c, null), g.r1, g.c1, g.r2, g.c2), { noCommit: true })
            this.moveCells(src, { r1: src.r1 + (mode === 'down' ? n : -n), c1: g.c1, r2: src.r2 + (mode === 'down' ? n : -n), c2: g.c2 }, { label: mode === 'down' ? '插入单元格' : '删除单元格', force: true })
        } else {
            const n = g.c2 - g.c1 + 1
            const src = { r1: g.r1, c1: mode === 'right' ? g.c1 : g.c2 + 1, r2: g.r2, c2: Math.max(b.c2, g.c2) }
            if (mode === 'left') this.batch('', set => sh.cells.each((r, c) => set(r, c, null), g.r1, g.c1, g.r2, g.c2), { noCommit: true })
            this.moveCells(src, { r1: g.r1, c1: src.c1 + (mode === 'right' ? n : -n), r2: g.r2, c2: src.c2 + (mode === 'right' ? n : -n) }, { label: mode === 'right' ? '插入单元格' : '删除单元格', force: true })
        }
        this.selectRange(g)
    },

    // 移动 / 复制单元格（拖动选区边框）
    moveCells(from, to, { copy = false, label, force = false } = {}) {
        const sh = this.sheet
        const dr = to.r1 - from.r1, dc = to.c1 - from.c1
        const src = sh.cells.sorted(from.r1, from.c1, from.r2, from.c2)
        const occupied = !force && !copy && (() => { let n = 0; sh.cells.each((r, c, cell) => { if (!inRange(from, r, c) && (cell.v != null || cell.f)) n++ }, to.r1, to.c1, to.r2, to.c2); return n })()
        const run = () => {
            this.batch(label ?? (copy ? '复制单元格' : '移动单元格'), set => {
                if (!copy) for (const [r, c] of src) set(r, c, null)
                sh.cells.each((r, c) => set(r, c, null), to.r1, to.c1, to.r2, to.c2)
                for (const [r, c, cell] of src) {
                    const f = cell.f && copy ? shiftFormula(cell.f, dr, dc) : cell.f
                    set(r + dr, c + dc, f !== cell.f ? { ...cell, f } : cell)
                }
                if (!copy) {
                    // 指向被移动区域的引用随之更新
                    for (const other of this.sheets) other.cells.each((r, c, cell) => {
                        if (!cell.f) return
                        const nf = moveRefsInFormula(cell.f, { sheet: sh.name, formulaSheet: other.name, from, dr, dc, toSheet: sh.name })
                        if (nf !== cell.f) { other.set(r, c, { ...cell, f: nf }); if (other === sh) set(r, c, { ...cell, f: nf }) }
                    })
                    sh.setMeta({ merges: sh.meta.merges.map(m => m.r1 >= from.r1 && m.r2 <= from.r2 && m.c1 >= from.c1 && m.c2 <= from.c2 ? { r1: m.r1 + dr, c1: m.c1 + dc, r2: m.r2 + dr, c2: m.c2 + dc } : m) })
                }
            }, { structural: true })
            if (!force) this.selectRange(to)
        }
        if (occupied) confirmDialog({ title: '移动单元格', message: '目标区域已有数据，是否替换？', okText: '替换' }).then(ok => ok && run())
        else run()
    },

    // ---------- 工作表 ----------
    uniqueSheetName(base) {
        const names = new Set(this.sheets.map(s => s.name.toLowerCase()))
        if (!names.has(base.toLowerCase())) return base
        let i = 2
        const stem = base.replace(/\s*\(\d+\)$/, '')
        while (names.has(`${stem} (${i})`.toLowerCase())) i++
        return `${stem} (${i})`
    },
    addSheet(name, at = this.book.active + 1) {
        if (this.editing) this.commitEdit()
        if (!name) { let i = this.sheets.length + 1; while (this.sheets.some(s => s.name.toLowerCase() === 'sheet' + i)) i++; name = 'Sheet' + i }
        const sh = new Sheet(this.uniqueSheetName(name))
        this.sheets.splice(at, 0, sh)
        this.engine.rebuild()
        this.switchSheet(at)
        this.commit('新建工作表')
        return sh
    },
    async deleteSheet(i = this.book.active) {
        if (this.sheets.length <= 1) return toast('工作簿至少需要一个工作表', 'warn')
        const sh = this.sheets[i]
        if (sh.cells.size && !(await confirmDialog({ title: '删除工作表', message: `确定删除工作表“${sh.name}”吗？引用它的公式将显示 #REF!。`, okText: '删除', danger: true }))) return
        this.sheets.splice(i, 1)
        for (const other of this.sheets) other.cells.each((r, c, cell) => {
            if (!cell.f) return
            const nf = renameSheetInFormula(cell.f, sh.name, null)
            if (nf !== cell.f) other.cells.set(r, c, { ...cell, f: nf })
        })
        this.book.active = Math.min(i, this.sheets.length - 1)
        this.engine.rebuild()
        this.switchSheet(this.book.active)
        this.commit('删除工作表')
    },
    async renameSheet(i = this.book.active, name) {
        const sh = this.sheets[i]
        if (name == null) name = await prompt({ title: '重命名工作表', value: sh.name })
        if (name == null) return
        name = name.trim().replace(/[\\/?*[\]:]/g, '').slice(0, 31)
        if (!name || name === sh.name) return
        if (this.sheets.some(s => s !== sh && s.name.toLowerCase() === name.toLowerCase())) return toast('已存在同名工作表', 'warn')
        const old = sh.name
        sh.name = name
        for (const other of this.sheets) other.cells.each((r, c, cell) => {
            if (!cell.f) return
            const nf = renameSheetInFormula(cell.f, old, name)
            if (nf !== cell.f) other.cells.set(r, c, { ...cell, f: nf })
        })
        for (const s of this.sheets) if (s.meta.charts.some(ch => ch.sheet === old)) s.setMeta({ charts: s.meta.charts.map(ch => ch.sheet === old ? { ...ch, sheet: name } : ch) })
        this.engine.rebuild()
        this.renderTabs()
        this.invalidate()
        this.commit('重命名工作表')
    },
    duplicateSheet(i = this.book.active) {
        const src = this.sheets[i]
        const snap = src.snapshot()
        const sh = Sheet.fromSnapshot({ ...snap, id: undefined, name: this.uniqueSheetName(src.name) })
        sh.setMeta({ charts: src.meta.charts.map(ch => ({ ...ch, id: Math.random().toString(36).slice(2, 9), sheet: ch.sheet === src.name || !ch.sheet ? sh.name : ch.sheet })) })
        this.sheets.splice(i + 1, 0, sh)
        this.engine.rebuild()
        this.switchSheet(i + 1)
        this.commit('复制工作表')
    },
    moveSheet(from, to) {
        if (from === to) return
        const active = this.sheet
        const [sh] = this.sheets.splice(from, 1)
        this.sheets.splice(to, 0, sh)
        this.book.active = this.sheets.indexOf(active)
        this.renderTabs()
        this.commit('移动工作表')
    },
    setSheetColor(i, color) {
        this.sheets[i].setMeta({ color })
        this.renderTabs()
        this.commit('工作表标签颜色')
    },
    switchSheet(i, { keepEdit = false } = {}) {
        if (i < 0 || i >= this.sheets.length) return
        if (this.editing && !keepEdit && !this.canPickRef()) this.commitEdit()
        this.book.active = i
        const sh = this.sheet
        if (!keepEdit || !this.editing) {
            this.sel = sh.lastSel ?? { r: 0, c: 0, ranges: [{ r1: 0, c1: 0, r2: 0, c2: 0 }], anchor: { r: 0, c: 0 } }
        }
        this.grid.sx = sh.lastScroll?.[0] ?? 0
        this.grid.sy = sh.lastScroll?.[1] ?? 0
        this.grid.updateExtent()
        this.grid.scroller.scrollLeft = this.grid.sx * this.zoom
        this.grid.scroller.scrollTop = this.grid.sy * this.zoom
        this.renderTabs()
        this.renderCharts?.()
        if (this.editing) this.updateRefHighlights(this.input.value)
        this.layoutEditor()
        this.invalidate()
        this.positionInput()
    },
    onSelectionChange() {
        this.sheet.lastSel = this.sel
        this.sheet.lastScroll = [this.grid.sx, this.grid.sy]
    },

    // ---------- 数据验证 ----------
    validationAt(r, c, sh = this.sheet) {
        for (const v of sh.meta.validations) if (inRange(v.range, r, c)) return v
        return null
    },
    validateInput(dv, v) {
        const msg = dv.message || '输入的值不符合此单元格的数据验证规则'
        if (dv.type === 'list') {
            const items = this.listItems(dv)
            return v == null || items.some(x => String(x).toLowerCase() === String(v).toLowerCase()) ? null : msg
        }
        if (dv.type === 'number' || dv.type === 'integer') {
            if (typeof v !== 'number' || (dv.type === 'integer' && !Number.isInteger(v))) return msg
            if (dv.min != null && dv.min !== '' && v < +dv.min) return msg
            if (dv.max != null && dv.max !== '' && v > +dv.max) return msg
        }
        if (dv.type === 'length') {
            const n = String(v ?? '').length
            if ((dv.min !== '' && dv.min != null && n < +dv.min) || (dv.max !== '' && dv.max != null && n > +dv.max)) return msg
        }
        return null
    },
    listItems(dv) {
        if (dv.source?.startsWith('=')) {
            const t = dv.source.slice(1)
            const toks = t.match(/^(?:(.+)!)?(\$?[A-Z]+\$?\d+(?::\$?[A-Z]+\$?\d+)?)$/i)
            if (toks) {
                const shName = toks[1]?.replace(/^'|'$/g, '')
                const sh = shName ? this.sheets.find(s => s.name.toLowerCase() === shName.toLowerCase()) : this.sheet
                const g = parseRange(toks[2].replace(/\$/g, ''))
                if (sh && g) {
                    const out = []
                    for (let r = g.r1; r <= Math.min(g.r2, g.r1 + 500); r++) for (let c = g.c1; c <= g.c2; c++) { const x = this.valueOf(sh, r, c); if (x != null && x !== '') out.push(x) }
                    return out
                }
            }
            return []
        }
        return String(dv.source ?? '').split(/[,，]/).map(s => s.trim()).filter(Boolean)
    },
    lockedCell() { return false },
}
