// 数据模型：工作簿 / 工作表 / 单元格存储
// 单元格按 64 行分块存储；快照时只复制块索引，写入时按需复制被修改的块（写时复制），
// 使撤销快照几乎不占额外内存。工作表的其他属性（行高、合并、图表…）作为不可变对象整体替换。
import { MAX_ROWS, MAX_COLS } from './addr.js'

const BR = 6            // 每块 2^6 = 64 行
export const CK = (r, c) => r * 16384 + c
export const CR = k => Math.floor(k / 16384)
export const CC = k => k % 16384

export class CellStore {
    constructor(blocks) {
        this.blocks = blocks ? new Map(blocks) : new Map()
        this.gen = 1
        this.count = null
    }
    get(r, c) { return this.blocks.get(r >> BR)?.get(CK(r, c)) }
    has(r, c) { return !!this.blocks.get(r >> BR)?.has(CK(r, c)) }
    // 写入（cell 为 null / undefined 时删除）
    set(r, c, cell) {
        const bi = r >> BR
        let b = this.blocks.get(bi)
        if (!b) {
            if (cell == null) return
            b = new Map(); b.gen = this.gen
            this.blocks.set(bi, b)
        } else if (b.gen !== this.gen) {
            const nb = new Map(b); nb.gen = this.gen
            this.blocks.set(bi, nb)
            b = nb
        }
        const k = CK(r, c)
        if (cell == null) {
            b.delete(k)
            if (!b.size) this.blocks.delete(bi)
        } else b.set(k, cell)
        this.count = null
    }
    // 冻结当前内容并返回可共享的块索引
    snapshot() {
        this.gen++
        return new Map(this.blocks)
    }
    restore(blocks) {
        this.blocks = new Map(blocks)
        this.gen++
        this.count = null
    }
    // 遍历区域内已存在的单元格：fn(r, c, cell)
    each(fn, r1 = 0, c1 = 0, r2 = MAX_ROWS - 1, c2 = MAX_COLS - 1) {
        const b1 = r1 >> BR, b2 = r2 >> BR
        if (b2 - b1 > this.blocks.size * 2) {
            const keys = [...this.blocks.keys()].filter(k => k >= b1 && k <= b2).sort((a, b) => a - b)
            for (const bi of keys) this.#eachBlock(this.blocks.get(bi), fn, r1, c1, r2, c2)
        } else {
            for (let bi = b1; bi <= b2; bi++) {
                const b = this.blocks.get(bi)
                if (b) this.#eachBlock(b, fn, r1, c1, r2, c2)
            }
        }
    }
    #eachBlock(b, fn, r1, c1, r2, c2) {
        for (const [k, cell] of b) {
            const r = CR(k), c = CC(k)
            if (r >= r1 && r <= r2 && c >= c1 && c <= c2) fn(r, c, cell)
        }
    }
    // 所有单元格（按行、列排序）
    sorted(r1, c1, r2, c2) {
        const out = []
        this.each((r, c, cell) => out.push([r, c, cell]), r1, c1, r2, c2)
        out.sort((a, b) => a[0] - b[0] || a[1] - b[1])
        return out
    }
    get size() {
        if (this.count == null) { let n = 0; for (const b of this.blocks.values()) n += b.size; this.count = n }
        return this.count
    }
    bounds() {
        let r2 = -1, c2 = -1
        for (const b of this.blocks.values()) {
            if (!b.size) continue
            for (const k of b.keys()) {
                const r = CR(k), c = CC(k)
                if (r > r2) r2 = r
                if (c > c2) c2 = c
            }
        }
        return { r2, c2 }
    }
}

// 工作表默认属性（不可变）
export const DEFAULT_META = Object.freeze({
    rowH: new Map(), colW: new Map(), hiddenR: new Set(), hiddenC: new Set(),
    rowStyle: new Map(), colStyle: new Map(),
    merges: [], freeze: { r: 0, c: 0 }, cf: [], charts: [], filter: null, validations: [],
    showGrid: true, color: null, defRowH: 24, defColW: 88,
})

let SID = 1
export class Sheet {
    constructor(name, { id, cells, meta } = {}) {
        this.id = id ?? SID++
        if (this.id >= SID) SID = this.id + 1
        this.name = name
        this.cells = cells ?? new CellStore()
        this.meta = meta ?? DEFAULT_META
        this.boundsCache = null
    }
    get(r, c) { return this.cells.get(r, c) }
    set(r, c, cell) {
        this.cells.set(r, c, cell)
        if (this.boundsCache && cell) {
            if (r > this.boundsCache.r2) this.boundsCache.r2 = r
            if (c > this.boundsCache.c2) this.boundsCache.c2 = c
        } else if (!cell) this.boundsCache = null
    }
    // 已用区域右下角（含格式）
    bounds() {
        if (!this.boundsCache) {
            const b = this.cells.bounds()
            for (const m of this.meta.merges) { b.r2 = Math.max(b.r2, m.r2); b.c2 = Math.max(b.c2, m.c2) }
            this.boundsCache = b
        }
        return this.boundsCache
    }
    // 不可变地更新属性：update('rowH', m => m.set(3, 40))
    update(key, fn) {
        let v = this.meta[key]
        if (v instanceof Map) v = new Map(v)
        else if (v instanceof Set) v = new Set(v)
        else if (Array.isArray(v)) v = [...v]
        else if (v && typeof v === 'object') v = { ...v }
        const r = fn ? fn(v) : undefined
        this.meta = { ...this.meta, [key]: r === undefined ? v : r }
        if (key === 'merges') this.boundsCache = null
    }
    setMeta(patch) { this.meta = { ...this.meta, ...patch }; if ('merges' in patch) this.boundsCache = null }
    rowHeight(r) { return this.meta.rowH.get(r) ?? this.meta.defRowH }
    colWidth(c) { return this.meta.colW.get(c) ?? this.meta.defColW }
    // 有效样式（单元格 > 行 > 列）
    styleAt(r, c, cell = this.get(r, c)) {
        if (cell?.s) return cell.s
        return this.meta.rowStyle.get(r) ?? this.meta.colStyle.get(c) ?? null
    }
    mergeAt(r, c) {
        for (const m of this.meta.merges) if (r >= m.r1 && r <= m.r2 && c >= m.c1 && c <= m.c2) return m
        return null
    }
    snapshot() {
        return { id: this.id, name: this.name, blocks: this.cells.snapshot(), meta: this.meta }
    }
    static fromSnapshot(s) {
        const sh = new Sheet(s.name, { id: s.id, cells: new CellStore(), meta: s.meta })
        sh.cells.restore(s.blocks)
        return sh
    }
}

// ---------- 样式 ----------
// 样式对象为冻结的规范化对象，相同样式共享同一实例
const styleCache = new Map()
const STYLE_KEYS = ['font', 'sz', 'b', 'i', 'u', 'st', 'color', 'fill', 'ha', 'va', 'wrap', 'fmt', 'indent', 'bt', 'br', 'bb', 'bl']
export function internStyle(s) {
    if (!s) return null
    const o = {}
    for (const k of STYLE_KEYS) if (s[k] != null && s[k] !== false && s[k] !== '') o[k] = s[k]
    if (o.fmt === 'General') delete o.fmt
    const key = JSON.stringify(o)
    if (key === '{}') return null
    let v = styleCache.get(key)
    if (!v) { v = Object.freeze(o); styleCache.set(key, v) }
    return v
}
export const mergeStyle = (base, patch) => internStyle({ ...(base ?? {}), ...patch })

// 单元格对象：{ v: 常量值, f: 公式文本(不含 =), s: 样式 }，同样不可变
export function makeCell(v, f, s) {
    if ((v == null || v === '') && !f && !s) return null
    const c = {}
    if (f) c.f = f
    else if (v != null && v !== '') c.v = v
    if (s) c.s = s
    return c
}

export const isEmptyCell = cell => !cell || (cell.v == null && !cell.f)
