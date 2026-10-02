// 公式求值用到的值类型与类型转换
// 值：number | string | boolean | null(空) | FErr | RangeVal | Matrix(二维数组)

export class FErr {
    constructor(code) { this.code = code }
    toString() { return this.code }
}
const ERR_CACHE = {}
export const err = code => (ERR_CACHE[code] ??= new FErr(code))
export const E = {
    DIV0: err('#DIV/0!'), NA: err('#N/A'), NAME: err('#NAME?'), NUM: err('#NUM!'),
    REF: err('#REF!'), VALUE: err('#VALUE!'), CIRC: err('#CIRC!'), NULL: err('#NULL!'),
}
export const isErr = v => v instanceof FErr

// 区域值：延迟读取
export class RangeVal {
    constructor(ctx, sid, r1, c1, r2, c2) {
        this.ctx = ctx; this.sid = sid
        // 整行 / 整列引用裁剪到已用区域
        const used = ctx.usedBounds(sid)
        this.r1 = r1; this.c1 = c1
        this.r2 = Math.min(r2, Math.max(r1, used.r2)); this.c2 = Math.min(c2, Math.max(c1, used.c2))
        this.fullR2 = r2; this.fullC2 = c2
    }
    get rows() { return this.r2 - this.r1 + 1 }
    get cols() { return this.c2 - this.c1 + 1 }
    get(i, j) { return this.ctx.cellValue(this.sid, this.r1 + i, this.c1 + j) }
    // 逐个遍历（跳过稀疏的空单元格时更快）
    each(fn) {
        const cells = this.ctx.cellsIn(this.sid, this.r1, this.c1, this.r2, this.c2)
        if (cells) { for (const [r, c] of cells) fn(this.ctx.cellValue(this.sid, r, c), r - this.r1, c - this.c1); return }
        for (let i = 0; i < this.rows; i++) for (let j = 0; j < this.cols; j++) fn(this.get(i, j), i, j)
    }
    toMatrix() {
        const m = []
        for (let i = 0; i < this.rows; i++) {
            const row = new Array(this.cols)
            for (let j = 0; j < this.cols; j++) row[j] = this.get(i, j)
            m.push(row)
        }
        return m
    }
}
export const isRange = v => v instanceof RangeVal
export const isMatrix = v => Array.isArray(v)
export const isMulti = v => v instanceof RangeVal || Array.isArray(v)

export const dims = v => isRange(v) ? [v.rows, v.cols] : isMatrix(v) ? [v.length, v[0]?.length ?? 0] : [1, 1]
export const at = (v, i, j) => isRange(v) ? v.get(i, j) : isMatrix(v) ? v[i]?.[j] ?? null : v
export const toMatrix = v => isRange(v) ? v.toMatrix() : isMatrix(v) ? v : [[v]]

// 区域 -> 单值（隐式交集的简化：取左上角）
export function scalar(v) {
    if (isRange(v)) return v.rows === 1 && v.cols === 1 ? v.get(0, 0) : v.get(0, 0)
    if (isMatrix(v)) return v[0]?.[0] ?? null
    return v
}

// ---------- 类型转换 ----------
const NUM_TEXT = /^\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*$/
export function parseNumberText(s) {
    if (typeof s !== 'string') return null
    let t = s.trim()
    if (!t) return null
    let pct = false, neg = false
    if (/^\(.*\)$/.test(t)) { neg = true; t = t.slice(1, -1) }
    if (t.endsWith('%')) { pct = true; t = t.slice(0, -1) }
    t = t.replace(/^[¥$€£]/, '').replace(/^([+-])[¥$€£]/, '$1')
    if (/^[+-]?\d{1,3}(,\d{3})+(\.\d*)?$/.test(t)) t = t.replace(/,/g, '')
    if (!NUM_TEXT.test(t)) return null
    let n = parseFloat(t)
    if (pct) n /= 100
    return neg ? -n : n
}

// 日期文本 -> 序列号
export function parseDateText(s) {
    if (typeof s !== 'string') return null
    let m = /^\s*(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*$/.exec(s)
    if (m) {
        const d = dateSerial(+m[1], +m[2], +m[3])
        if (d == null) return null
        return d + (m[4] ? (+m[4] * 3600 + +m[5] * 60 + +(m[6] ?? 0)) / 86400 : 0)
    }
    m = /^\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*$/.exec(s)
    if (m && +m[1] < 24 && +m[2] < 60) return (+m[1] * 3600 + +m[2] * 60 + +(m[3] ?? 0)) / 86400
    return null
}

export function toNum(v) {
    if (typeof v === 'number') return v
    if (v == null) return 0
    if (typeof v === 'boolean') return v ? 1 : 0
    if (isErr(v)) return v
    if (typeof v === 'string') {
        if (v === '') return 0
        const n = parseNumberText(v)
        if (n != null) return n
        const d = parseDateText(v)
        if (d != null) return d
        return E.VALUE
    }
    if (isMulti(v)) return toNum(scalar(v))
    return E.VALUE
}
export function toStr(v) {
    if (typeof v === 'string') return v
    if (v == null) return ''
    if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE'
    if (typeof v === 'number') return numToStr(v)
    if (isErr(v)) return v
    if (isMulti(v)) return toStr(scalar(v))
    return ''
}
export function toBool(v) {
    if (typeof v === 'boolean') return v
    if (typeof v === 'number') return v !== 0
    if (v == null) return false
    if (isErr(v)) return v
    if (typeof v === 'string') {
        const u = v.toUpperCase()
        if (u === 'TRUE') return true
        if (u === 'FALSE') return false
        return E.VALUE
    }
    if (isMulti(v)) return toBool(scalar(v))
    return E.VALUE
}

// 数字 -> 常规格式文本（最多 15 位有效数字）
export function numToStr(n) {
    if (!Number.isFinite(n)) return '#NUM!'
    if (Number.isInteger(n) && Math.abs(n) < 1e15) return String(n)
    let s = String(+n.toPrecision(15))
    return s
}

// ---------- 日期（1900 日期系统，序列号 1 = 1900-01-01） ----------
const EPOCH = Date.UTC(1899, 11, 30)
export function dateSerial(y, m, d) {
    if (y < 100) y += 1900
    const t = Date.UTC(y, m - 1, d)
    if (!Number.isFinite(t)) return null
    let s = (t - EPOCH) / 86400000
    if (s < 61) s -= 1 // Excel 虚构的 1900-02-29
    return s
}
export function serialToDate(s) {
    let n = Math.floor(s)
    if (n < 61) n += 1
    const t = EPOCH + n * 86400000 + Math.round((s - Math.floor(s)) * 86400000)
    return new Date(t)
}
export function nowSerial() {
    const d = new Date()
    return dateSerial(d.getFullYear(), d.getMonth() + 1, d.getDate()) + (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400
}

// 比较：返回 -1 / 0 / 1（Excel 规则：数字 < 文本 < 逻辑值，文本不区分大小写）
const typeRank = v => typeof v === 'number' ? 1 : typeof v === 'string' ? 2 : typeof v === 'boolean' ? 3 : 0
export function compare(a, b) {
    if (a == null) a = typeof b === 'string' ? '' : typeof b === 'boolean' ? false : 0
    if (b == null) b = typeof a === 'string' ? '' : typeof a === 'boolean' ? false : 0
    const ta = typeRank(a), tb = typeRank(b)
    if (ta !== tb) return ta < tb ? -1 : 1
    if (ta === 2) {
        const x = a.toLowerCase(), y = b.toLowerCase()
        return x < y ? -1 : x > y ? 1 : 0
    }
    return a < b ? -1 : a > b ? 1 : 0
}
