// 电子表格编辑器
import { Editor } from '../base.js'
import { h, toast, normColor } from '../../core/dom.js'
import * as store from '../../core/store.js'
import { Grid } from './grid.js'
import { Engine } from './formula/engine.js'
import { Sheet } from './model.js'
import { cfPrepare, cfApply } from './format.js'
import { MAX_ROWS, MAX_COLS, rangeName, cellName } from './addr.js'
import { isErr } from './formula/values.js'
import { Selection } from './selection.js'
import { Editing } from './editing.js'
import { Ops } from './ops.js'
import { DataOps } from './data.js'
import { Clipboard } from './clipboard.js'
import { Charts } from './chart.js'
import { IO } from './io.js'
import { UI } from './ui.js'
import { Menus } from './menus.js'
import { Dialogs } from './dialogs.js'
import { buildSample } from './samples.js'

export class SheetEditor extends Editor {
    static kind = 'sheet'

    constructor(file, app) {
        super(file, app)
        const pref = store.getPref('sheet', { zoom: 1 })
        this.zoom = pref.zoom ?? 1
        this.book = { sheets: [new Sheet('Sheet1')], active: 0 }
        this.engine = new Engine(this.book)
        this.sel = { r: 0, c: 0, ranges: [{ r1: 0, c1: 0, r2: 0, c2: 0 }], anchor: { r: 0, c: 0 } }
        this.editing = null
        this.clip = null
        this.cfCache = new Map()
        this.accent = '#1a73e8'
        this.grid = new Grid(this)
        this.buildUI()
        this.bindGrid()
        this.bindEditing()
        // 易失函数定时刷新（NOW / RAND 在每次编辑后刷新；这里仅让 NOW 每分钟更新一次）
        const t = setInterval(() => { if (this.engine.volatile.size && !this.editing) { this.engine.recalcVolatile(); this.invalidate() } }, 60000)
        this.onDispose(() => clearInterval(t))
    }

    get sheet() { return this.book.sheets[this.book.active] }
    get sheets() { return this.book.sheets }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        if (opts.sample) {
            this.book.sheets = []
            buildSample(this, opts.sample)
            this.book.active = 0
        }
        this.afterLoad()
    }

    async load(bytes, ext) {
        this.busy = true
        try { await this.readFile(bytes, ext) } finally { this.busy = false }
        this.afterLoad()
    }

    afterLoad() {
        this.engine.rebuild()
        this.cfCache.clear()
        this.selectCell(0, 0)
        this.renderTabs()
        this.renderCharts()
        this.grid.layout()
        this.refreshUI()
    }

    onShow() {
        super.onShow()
        this.accent = normColor(getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#1a73e8')
        requestAnimationFrame(() => { this.grid.layout(); this.focusGrid() })
    }

    // ---------- 撤销快照 ----------
    // 每个工作表的单元格按块共享（写时复制），属性为不可变对象，因此快照开销很小
    snapshot() {
        return {
            sheets: this.book.sheets.map(s => s.snapshot()),
            active: this.book.active,
            sel: { r: this.sel.r, c: this.sel.c, ranges: this.sel.ranges.map(g => ({ ...g })), anchor: { ...this.sel.anchor } },
        }
    }

    restore(s) {
        this.cancelEdit?.()
        this.book.sheets = s.sheets.map(x => Sheet.fromSnapshot(x))
        this.book.active = Math.min(s.active, this.book.sheets.length - 1)
        this.sel = { r: s.sel.r, c: s.sel.c, ranges: s.sel.ranges.map(g => ({ ...g })), anchor: { ...s.sel.anchor } }
        this.engine.rebuild()
        this.cfCache.clear()
        this.renderTabs()
        this.renderCharts()
        this.grid.updateExtent()
        this.grid.scrollTo(this.sel.r, this.sel.c)
        this.invalidate()
    }

    // ---------- 值 ----------
    valueOf(sh, r, c, cell = sh.get(r, c)) {
        if (!cell) return null
        if (cell.f) return this.engine.value(sh.id, r, c)
        return cell.v ?? null
    }
    value(r, c, sh = this.sheet) { return this.valueOf(sh, r, c) }

    // 修改单元格后调用：list = [[sheet, r, c], ...]
    changed(list, { structural = false } = {}) {
        if (structural) this.engine.rebuild()
        else {
            this.engine.changed(list.map(([sh, r, c]) => [sh.id, r, c]))
            this.engine.recalcVolatile()
        }
        this.cfCache.clear()
        this.applyFilterRefresh?.()
        this.invalidate()
    }

    // 重绘表格与相关 UI
    invalidate() {
        this.grid.updateExtent()
        this.grid.requestDraw()
        this.updateCharts?.()
        this.refreshUI()
    }

    // ---------- 条件格式 ----------
    cfFor(sh) {
        const rules = sh.meta.cf
        if (!rules.length) return null
        let p = this.cfCache.get(sh.id)
        if (!p || p.rules !== rules) {
            const list = cfPrepare(rules, (r, c) => this.valueOf(sh, r, c), (g, fn) => sh.cells.each((r, c) => fn(r, c), g.r1, g.c1, Math.min(g.r2, sh.bounds().r2), Math.min(g.c2, sh.bounds().c2)))
            p = { rules, list }
            this.cfCache.set(sh.id, p)
        }
        return p.list
    }
    cfResult(list, r, c, v) {
        const sh = this.sheet
        return cfApply(list, r, c, v, (f, dr, dc) => this.engine.evalFormula(this.shiftText(f, dr, dc), sh.id, r, c))
    }

    // ---------- 选区 ----------
    get range() { return this.sel.ranges[this.sel.ranges.length - 1] }
    inSelection(r, c) {
        for (const g of this.sel.ranges) if (r >= g.r1 && r <= g.r2 && c >= g.c1 && c <= g.c2) return true
        return false
    }
    // 活动单元格（或其所在合并区域）在窗格中的矩形
    activeRect(p) {
        const { r, c } = this.sel
        const m = this.sheet.mergeAt(r, c)
        const r1 = m?.r1 ?? r, c1 = m?.c1 ?? c, r2 = m?.r2 ?? r, c2 = m?.c2 ?? c
        if (p) {
            const inR = p.sy ? r1 >= this.grid.fr || r2 >= this.grid.fr : r1 < this.grid.fr
            const inC = p.sx ? c1 >= this.grid.fc || c2 >= this.grid.fc : c1 < this.grid.fc
            if (!inR || !inC) return null
            const x = p.X(c1), y = p.Y(r1)
            return { x, y, w: p.X(c2) + this.grid.colW(c2) - x, h: p.Y(r2) + this.grid.rowH(r2) - y }
        }
        return this.grid.cellRect(r1, c1, r2, c2)
    }

    // 把区域扩展到完整包含其中的合并单元格
    expandMerges(g, sh = this.sheet) {
        let changed = true
        g = { ...g }
        while (changed) {
            changed = false
            for (const m of sh.meta.merges) {
                if (m.r2 >= g.r1 && m.r1 <= g.r2 && m.c2 >= g.c1 && m.c1 <= g.c2) {
                    if (m.r1 < g.r1 || m.r2 > g.r2 || m.c1 < g.c1 || m.c2 > g.c2) {
                        g = { r1: Math.min(g.r1, m.r1), c1: Math.min(g.c1, m.c1), r2: Math.max(g.r2, m.r2), c2: Math.max(g.c2, m.c2) }
                        changed = true
                    }
                }
            }
        }
        return g
    }

    // 限定到已用区域（整行 / 整列选择时避免遍历百万单元格）
    clampUsed(g, sh = this.sheet) {
        const b = sh.bounds()
        return { r1: g.r1, c1: g.c1, r2: Math.min(g.r2, Math.max(g.r1, b.r2)), c2: Math.min(g.c2, Math.max(g.c1, b.c2)) }
    }

    // ---------- 状态栏 ----------
    statusStats() {
        let sum = 0, count = 0, nums = 0, min = Infinity, max = -Infinity
        const sh = this.sheet
        const seen = new Set()
        let cells = 0
        for (const g0 of this.sel.ranges) {
            const g = this.clampUsed(g0)
            cells += (g0.r2 - g0.r1 + 1) * (g0.c2 - g0.c1 + 1)
            sh.cells.each((r, c, cell) => {
                const k = r * MAX_COLS + c
                if (seen.has(k)) return
                seen.add(k)
                if (this.grid.rows.isHidden(r) || this.grid.cols.isHidden(c)) return
                const v = this.valueOf(sh, r, c, cell)
                if (v == null || v === '') return
                count++
                if (typeof v === 'number') { sum += v; nums++; if (v < min) min = v; if (v > max) max = v }
            }, g.r1, g.c1, g.r2, g.c2)
        }
        return { sum, count, nums, avg: nums ? sum / nums : null, min, max, cells }
    }

    focusGrid() {
        if (this.editing) return
        this.input?.focus({ preventScroll: true })
    }

    // 当前单元格的地址文本
    selName() {
        const g = this.range
        if (this.sel.ranges.length === 1 && (g.r1 !== g.r2 || g.c1 !== g.c2)) {
            const m = this.sheet.mergeAt(g.r1, g.c1)
            if (m && m.r1 === g.r1 && m.c1 === g.c1 && m.r2 === g.r2 && m.c2 === g.c2) return cellName(g.r1, g.c1)
            return rangeName(g)
        }
        return cellName(this.sel.r, this.sel.c)
    }

    isErrValue(v) { return isErr(v) }

    destroy() {
        cancelAnimationFrame(this.grid.raf)
        super.destroy()
    }
}

export const LIMITS = { MAX_ROWS, MAX_COLS }

Object.assign(SheetEditor.prototype, Selection, Editing, Ops, DataOps, Clipboard, Charts, IO, UI, Menus, Dialogs)

export function toastErr(e) { toast(String(e?.message ?? e), 'error') }
void h
