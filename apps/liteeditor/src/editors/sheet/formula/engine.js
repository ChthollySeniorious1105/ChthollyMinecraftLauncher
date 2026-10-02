// 计算引擎：解析缓存、依赖图、增量重算、循环引用检测
import { parse, collectRefs, ParseError } from './parser.js'
import { evaluate, finalValue } from './evaluate.js'
import { E, isErr } from './values.js'
import { FUNCS } from './functions.js'
import { cellKey, keySheet, keyRow, keyCol } from '../addr.js'

const DEPTH = Symbol('depth')
const MAX_DEPTH = 600

export class Engine {
    // book: { sheets: Sheet[] }
    constructor(book) {
        this.book = book
        this.astCache = new Map()
        this.reset()
    }

    reset() {
        this.values = new Map()      // 公式单元格 -> 计算值
        this.state = new Map()       // 公式单元格 -> 1 计算中 / 2 已完成
        this.prec = new Map()        // 公式单元格 -> 引用列表 [{ sid, r1, c1, r2, c2 }]
        this.cellDeps = new Map()    // 单元格 -> Set(引用它的公式)
        this.rangeDeps = new Map()   // sid -> Map(公式 -> 区域列表)
        this.volatile = new Set()
        this.formulas = new Set()
    }

    sheet(sid) { return this.book.sheets.find(s => s.id === sid) }
    sheetId(name) {
        const low = String(name).toLowerCase()
        return this.book.sheets.find(s => s.name.toLowerCase() === low)?.id ?? null
    }

    ast(f) {
        let a = this.astCache.get(f)
        if (a === undefined) {
            try { a = parse(f) } catch (e) { a = e instanceof ParseError ? e : new ParseError(e.message) }
            if (this.astCache.size > 50000) this.astCache.clear()
            this.astCache.set(f, a)
        }
        return a
    }

    // 检查公式语法，返回错误信息或 null
    check(f) {
        const a = this.ast(f)
        return a instanceof Error ? a.message : null
    }

    // ---------- 依赖登记 ----------
    unregister(k) {
        const refs = this.prec.get(k)
        if (!refs) return
        for (const rf of refs) {
            if (rf.single) {
                const s = this.cellDeps.get(rf.key)
                if (s) { s.delete(k); if (!s.size) this.cellDeps.delete(rf.key) }
            } else this.rangeDeps.get(rf.sid)?.delete(k)
        }
        this.prec.delete(k)
        this.volatile.delete(k)
        this.formulas.delete(k)
    }

    register(k, f) {
        this.unregister(k)
        this.formulas.add(k)
        const ast = this.ast(f)
        const refs = []
        if (!(ast instanceof Error)) {
            const sid0 = keySheet(k)
            const { refs: rs, funcs } = collectRefs(ast)
            for (const fn of funcs) if (FUNCS[fn]?.volatile) this.volatile.add(k)
            for (const r of rs) {
                const sid = r.sheet != null ? this.sheetId(r.sheet) : sid0
                if (sid == null) continue
                if (r.r1 === r.r2 && r.c1 === r.c2) {
                    const key = cellKey(sid, r.r1, r.c1)
                    refs.push({ single: true, key })
                    let s = this.cellDeps.get(key)
                    if (!s) this.cellDeps.set(key, s = new Set())
                    s.add(k)
                } else {
                    const rect = { sid, r1: r.r1, c1: r.c1, r2: r.r2, c2: r.c2 }
                    refs.push(rect)
                    let m = this.rangeDeps.get(sid)
                    if (!m) this.rangeDeps.set(sid, m = new Map())
                    let list = m.get(k)
                    if (!list) m.set(k, list = [])
                    list.push(rect)
                }
            }
        }
        this.prec.set(k, refs)
    }

    // 某单元格的直接依赖者
    dependents(key, out) {
        const s = this.cellDeps.get(key)
        if (s) for (const f of s) out(f)
        const m = this.rangeDeps.get(keySheet(key))
        if (m) {
            const r = keyRow(key), c = keyCol(key)
            for (const [f, list] of m) {
                for (const rc of list) if (r >= rc.r1 && r <= rc.r2 && c >= rc.c1 && c <= rc.c2) { out(f); break }
            }
        }
    }

    // ---------- 重算 ----------
    // 全部重建（打开、撤销、结构性修改之后）
    rebuild() {
        this.reset()
        for (const sh of this.book.sheets) {
            sh.cells.each((r, c, cell) => { if (cell.f) this.register(cellKey(sh.id, r, c), cell.f) })
        }
        this.recalc(new Set(this.formulas))
    }

    // 单元格内容发生变化：keys 为 [sid, r, c] 列表；返回被重新计算的公式单元格集合
    changed(list) {
        const dirty = new Set()
        const queue = []
        for (const [sid, r, c] of list) {
            const k = cellKey(sid, r, c)
            const cell = this.sheet(sid)?.get(r, c)
            if (cell?.f) { this.register(k, cell.f); dirty.add(k) }
            else if (this.formulas.has(k)) { this.unregister(k); this.values.delete(k) }
            queue.push(k)
        }
        while (queue.length) {
            const k = queue.pop()
            this.dependents(k, f => { if (!dirty.has(f)) { dirty.add(f); queue.push(f) } })
        }
        this.recalc(dirty)
        return dirty
    }

    // 重新计算易失函数（RAND / NOW …）及其依赖者
    recalcVolatile() {
        if (!this.volatile.size) return new Set()
        const dirty = new Set(this.volatile), queue = [...dirty]
        while (queue.length) {
            const k = queue.pop()
            this.dependents(k, f => { if (!dirty.has(f)) { dirty.add(f); queue.push(f) } })
        }
        this.recalc(dirty)
        return dirty
    }

    recalc(dirty) {
        for (const k of dirty) { this.state.delete(k); this.values.delete(k) }
        this.dirty = dirty
        // 按位置排序，使“向上 / 向左引用”的常见情形递归最浅
        const order = [...dirty].sort((a, b) => a - b)
        let guard = 0
        for (let i = 0; i < order.length; i++) {
            const k = order[i]
            if (this.state.get(k) === 2) continue
            this.depth = 0
            try {
                this.evalCell(k)
            } catch (e) {
                if (e !== DEPTH) throw e
                // 递归过深：清除“计算中”标记后重试（已完成的部分保留，保证前进）
                for (const [kk, st] of this.state) if (st === 1) this.state.delete(kk)
                if (++guard < 100000) i--
            }
        }
        this.dirty = null
    }

    evalCell(k) {
        const st = this.state.get(k)
        if (st === 2) return this.values.get(k)
        if (st === 1) return E.CIRC
        const sid = keySheet(k), r = keyRow(k), c = keyCol(k)
        const cell = this.sheet(sid)?.get(r, c)
        if (!cell?.f) return cell?.v ?? null
        if (++this.depth > MAX_DEPTH) throw DEPTH
        this.state.set(k, 1)
        const ast = this.ast(cell.f)
        let v
        if (ast instanceof Error) v = E.NAME
        else {
            try {
                v = finalValue(evaluate(ast, this.ctx(sid, r, c)))
            } catch (e) {
                if (e === DEPTH) { this.state.delete(k); this.depth--; throw e }
                console.warn('公式计算出错', cell.f, e)
                v = E.VALUE
            }
        }
        this.depth--
        this.state.set(k, 2)
        this.values.set(k, v)
        return v
    }

    ctx(sid, r, c) {
        const eng = this
        return {
            sid, r, c,
            sheetId: name => eng.sheetId(name),
            cellValue: (s, rr, cc) => eng.cellValue(s, rr, cc),
            usedBounds: s => eng.sheet(s)?.bounds() ?? { r2: -1, c2: -1 },
            cellsIn: (s, r1, c1, r2, c2) => {
                if ((r2 - r1 + 1) * (c2 - c1 + 1) < 4096) return null
                const out = []
                eng.sheet(s)?.cells.each((rr, cc) => out.push([rr, cc]), r1, c1, r2, c2)
                return out
            },
        }
    }

    cellValue(sid, r, c) {
        const sh = this.sheet(sid)
        const cell = sh?.get(r, c)
        if (!cell) return null
        if (!cell.f) return cell.v ?? null
        const k = cellKey(sid, r, c)
        const st = this.state.get(k)
        if (st === 2) return this.values.get(k)
        if (this.dirty?.has(k) || st === 1) return this.evalCell(k)
        if (this.values.has(k)) return this.values.get(k)
        return this.evalCell(k)
    }

    // 对外：单元格显示值
    value(sid, r, c) {
        const v = this.cellValue(sid, r, c)
        return v
    }

    // 临时计算一个公式（用于条件格式、数据验证等）
    evalFormula(f, sid, r = 0, c = 0) {
        const ast = this.ast(f)
        if (ast instanceof Error) return E.NAME
        try { return finalValue(evaluate(ast, this.ctx(sid, r, c))) } catch { return E.VALUE }
    }
}

export { isErr }
