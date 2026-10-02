// 文本 / 查找引用 / 日期函数
import { E, isErr, isRange, isMulti, dims, at, toNum, toStr, toBool, compare, scalar, toMatrix, dateSerial, serialToDate, nowSerial, parseNumberText, parseDateText, RangeVal } from './values.js'
import { formatValue } from '../numfmt.js'

const s0 = (args, i, def = '') => args[i] == null ? def : toStr(scalar(args[i]))
const n0 = (args, i, def) => args[i] == null ? def : toNum(scalar(args[i]))
const firstErr = (...vs) => vs.find(isErr)

const txt1 = fn => args => { const s = s0(args, 0); return isErr(s) ? s : fn(s, args) }

function wildRe(pat) {
    return new RegExp('^' + pat.toLowerCase().replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/~\*/g, '\u0001').replace(/~\?/g, '\u0002')
        .replace(/\*/g, '.*').replace(/\?/g, '.').replace(/\u0001/g, '\\*').replace(/\u0002/g, '\\?') + '$', 's')
}
const eqLookup = (key, wild) => {
    if (typeof key === 'string' && wild && /[*?]/.test(key)) { const re = wildRe(key); return v => typeof v === 'string' && re.test(v.toLowerCase()) }
    return v => v != null && compare(v, key) === 0 && typeof v === typeof key
}

// 在一维向量中查找：mode 0 精确、1 小于等于的最大值（已排序）、-1 大于等于的最小值
function lookupIndex(key, getter, n, mode, wild = true) {
    if (mode === 0) {
        const eq = eqLookup(key, wild)
        for (let i = 0; i < n; i++) if (eq(getter(i))) return i
        return -1
    }
    // 二分查找（近似匹配）
    let lo = 0, hi = n - 1, best = -1
    while (lo <= hi) {
        const mid = (lo + hi) >> 1
        const v = getter(mid)
        const c = v == null ? 1 : compare(v, key)
        if (mode === 1 ? c <= 0 : c >= 0) { best = mid; if (mode === 1) lo = mid + 1; else hi = mid - 1 }
        else if (mode === 1) hi = mid - 1
        else lo = mid + 1
    }
    return best
}

function sub(rg, i1, j1, i2, j2) {
    if (isRange(rg)) return new RangeVal(rg.ctx, rg.sid, rg.r1 + i1, rg.c1 + j1, rg.r1 + i2, rg.c1 + j2)
    return toMatrix(rg).slice(i1, i2 + 1).map(r => r.slice(j1, j2 + 1))
}

const dateParts = v => {
    const n = toNum(scalar(v))
    if (isErr(n)) return n
    if (n < 0) return E.NUM
    return serialToDate(n)
}

export const TEXT_FUNCS = {
    LEN: { min: 1, fn: txt1(s => [...s].length) },
    LEFT: { min: 1, fn: txt1((s, a) => { const n = n0(a, 1, 1); return isErr(n) ? n : n < 0 ? E.VALUE : [...s].slice(0, n).join('') }) },
    RIGHT: { min: 1, fn: txt1((s, a) => { const n = n0(a, 1, 1); if (isErr(n)) return n; if (n < 0) return E.VALUE; const c = [...s]; return n === 0 ? '' : c.slice(Math.max(0, c.length - n)).join('') }) },
    MID: { min: 3, fn: txt1((s, a) => { const st = n0(a, 1), n = n0(a, 2); const e = firstErr(st, n); if (e) return e; if (st < 1 || n < 0) return E.VALUE; return [...s].slice(st - 1, st - 1 + n).join('') }) },
    UPPER: { min: 1, fn: txt1(s => s.toUpperCase()) },
    LOWER: { min: 1, fn: txt1(s => s.toLowerCase()) },
    PROPER: { min: 1, fn: txt1(s => s.toLowerCase().replace(/(^|[^a-z])([a-z])/g, (m, a, b) => a + b.toUpperCase())) },
    TRIM: { min: 1, fn: txt1(s => s.replace(/ +/g, ' ').trim()) },
    CLEAN: { min: 1, fn: txt1(s => s.replace(/[\x00-\x1f]/g, '')) },
    CONCAT: { fn: args => { let r = ''; for (const a of args) { if (isMulti(a)) { const [R, C] = dims(a); for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) { const v = at(a, i, j); if (isErr(v)) return v; r += toStr(v) } } else { const v = toStr(a); if (isErr(v)) return v; r += v } } return r } },
    CONCATENATE: { fn: args => { let r = ''; for (const a of args) { const v = toStr(scalar(a)); if (isErr(v)) return v; r += v } return r } },
    TEXTJOIN: {
        min: 3, fn: args => {
            const d = s0(args, 0), skip = toBool(scalar(args[1]))
            const parts = []
            for (const a of args.slice(2)) {
                if (isMulti(a)) { const [R, C] = dims(a); for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) { const v = at(a, i, j); if (isErr(v)) return v; if (!(skip && (v == null || v === ''))) parts.push(toStr(v)) } }
                else { if (isErr(a)) return a; if (!(skip && (a == null || a === ''))) parts.push(toStr(a)) }
            }
            return parts.join(d)
        },
    },
    REPT: { min: 2, fn: txt1((s, a) => { const n = n0(a, 1); return isErr(n) ? n : n < 0 ? E.VALUE : s.repeat(Math.floor(n)) }) },
    EXACT: { min: 2, fn: args => s0(args, 0) === s0(args, 1) },
    TEXT: {
        min: 2, fn: args => {
            const v = scalar(args[0]), f = s0(args, 1)
            if (isErr(v)) return v
            let x = v
            if (typeof v === 'string') { const n = parseNumberText(v) ?? parseDateText(v); if (n != null) x = n }
            return formatValue(x, f.replace(/[Yy]/g, 'y').replace(/D/g, 'd')).text
        },
    },
    VALUE: { min: 1, fn: args => { const v = scalar(args[0]); if (typeof v === 'number') return v; const s = toStr(v); if (isErr(s)) return s; if (s.trim() === '') return 0; const n = parseNumberText(s) ?? parseDateText(s); return n ?? E.VALUE } },
    NUMBERVALUE: { min: 1, fn: args => { const n = parseNumberText(s0(args, 0)); return n ?? E.VALUE } },
    FIND: { min: 2, fn: args => { const f = s0(args, 0), s = s0(args, 1), st = n0(args, 2, 1); const e = firstErr(f, s, st); if (e) return e; const i = s.indexOf(f, st - 1); return i < 0 || st < 1 ? E.VALUE : i + 1 } },
    SEARCH: {
        min: 2, fn: args => {
            const f = s0(args, 0), s = s0(args, 1), st = n0(args, 2, 1)
            const e = firstErr(f, s, st); if (e) return e
            const src = f.toLowerCase().replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')
            const re = new RegExp(src, 'g'); re.lastIndex = st - 1
            const m = re.exec(s.toLowerCase())
            return m ? m.index + 1 : E.VALUE
        },
    },
    SUBSTITUTE: {
        min: 3, fn: args => {
            const s = s0(args, 0), o = s0(args, 1), n = s0(args, 2)
            const e = firstErr(s, o, n); if (e) return e
            if (!o) return s
            if (args[3] == null) return s.split(o).join(n)
            const k = toNum(scalar(args[3])); if (isErr(k)) return k
            let idx = -1
            for (let i = 0; i < k; i++) { idx = s.indexOf(o, idx + 1); if (idx < 0) return s }
            return s.slice(0, idx) + n + s.slice(idx + o.length)
        },
    },
    REPLACE: { min: 4, fn: args => { const s = s0(args, 0), st = n0(args, 1), n = n0(args, 2), r = s0(args, 3); const e = firstErr(s, st, n, r); if (e) return e; return s.slice(0, st - 1) + r + s.slice(st - 1 + n) } },
    CHAR: { min: 1, fn: args => { const n = n0(args, 0); return isErr(n) ? n : String.fromCharCode(n) } },
    CODE: { min: 1, fn: txt1(s => s ? s.charCodeAt(0) : E.VALUE) },
    T: { min: 1, fn: args => { const v = scalar(args[0]); return typeof v === 'string' ? v : '' } },
    N: { min: 1, fn: args => { const v = scalar(args[0]); return typeof v === 'number' ? v : typeof v === 'boolean' ? +v : 0 } },

    // ---------- 查找与引用 ----------
    VLOOKUP: {
        min: 3, fn: args => {
            const key = scalar(args[0]), tb = args[1], col = n0(args, 2), approx = args[3] == null ? true : toBool(scalar(args[3]))
            const e = firstErr(key, col, approx); if (e) return e
            if (!isMulti(tb)) return E.VALUE
            const [R, C] = dims(tb)
            if (col < 1 || col > C) return E.REF
            const i = lookupIndex(key, i => at(tb, i, 0), R, approx ? 1 : 0)
            return i < 0 ? E.NA : at(tb, i, Math.floor(col) - 1)
        },
    },
    HLOOKUP: {
        min: 3, fn: args => {
            const key = scalar(args[0]), tb = args[1], row = n0(args, 2), approx = args[3] == null ? true : toBool(scalar(args[3]))
            const e = firstErr(key, row, approx); if (e) return e
            if (!isMulti(tb)) return E.VALUE
            const [R, C] = dims(tb)
            if (row < 1 || row > R) return E.REF
            const j = lookupIndex(key, j => at(tb, 0, j), C, approx ? 1 : 0)
            return j < 0 ? E.NA : at(tb, Math.floor(row) - 1, j)
        },
    },
    XLOOKUP: {
        min: 3, fn: args => {
            const key = scalar(args[0]), look = args[1], ret = args[2]
            if (isErr(key)) return key
            const mode = n0(args, 4, 0), search = n0(args, 5, 1)
            const [R, C] = dims(look)
            const vertical = C === 1
            const n = vertical ? R : C
            const get = i => vertical ? at(look, i, 0) : at(look, 0, i)
            let idx = -1
            if (mode === 0 || mode === 2) {
                const eq = eqLookup(key, mode === 2)
                if (search >= 0) { for (let i = 0; i < n; i++) if (eq(get(i))) { idx = i; break } }
                else for (let i = n - 1; i >= 0; i--) if (eq(get(i))) { idx = i; break }
            } else {
                let best = null
                for (let i = 0; i < n; i++) {
                    const v = get(i)
                    if (v == null) continue
                    const c = compare(v, key)
                    if (c === 0 && typeof v === typeof key) { idx = i; best = null; break }
                    if (mode === -1 && c < 0 && (best == null || compare(v, best) > 0)) { best = v; idx = i }
                    if (mode === 1 && c > 0 && (best == null || compare(v, best) < 0)) { best = v; idx = i }
                }
            }
            if (idx < 0) return args[3] != null && args[3] !== undefined ? args[3] : E.NA
            const [rr, rc] = dims(ret)
            if (vertical) return rc === 1 ? at(ret, idx, 0) : sub(ret, idx, 0, idx, rc - 1)
            return rr === 1 ? at(ret, 0, idx) : sub(ret, 0, idx, rr - 1, idx)
        },
    },
    LOOKUP: {
        min: 2, fn: args => {
            const key = scalar(args[0]), look = args[1], ret = args[2] ?? args[1]
            const [R, C] = dims(look)
            const vertical = R >= C
            const n = vertical ? R : C
            const i = lookupIndex(key, i => vertical ? at(look, i, 0) : at(look, 0, i), n, 1)
            if (i < 0) return E.NA
            const [rr, rc] = dims(ret)
            return rc === 1 || rr > 1 ? at(ret, i, args[2] ? 0 : C - 1) : at(ret, 0, i)
        },
    },
    MATCH: {
        min: 2, fn: args => {
            const key = scalar(args[0]), look = args[1], mode = n0(args, 2, 1)
            if (isErr(key)) return key
            const [R, C] = dims(look)
            const vertical = C === 1
            const n = vertical ? R : C
            const get = i => vertical ? at(look, i, 0) : at(look, 0, i)
            const i = lookupIndex(key, get, n, mode === 0 ? 0 : mode > 0 ? 1 : -1)
            return i < 0 ? E.NA : i + 1
        },
    },
    XMATCH: { min: 2, fn: args => TEXT_FUNCS.MATCH.fn([args[0], args[1], args[2] ?? 0]) },
    INDEX: {
        min: 2, fn: args => {
            const rg = args[0]
            let r = n0(args, 1, 0), c = n0(args, 2, 0)
            const e = firstErr(r, c); if (e) return e
            const [R, C] = dims(rg)
            if (R === 1 && args[2] == null) { c = r; r = 1 }
            if (r < 0 || c < 0 || r > R || c > C) return E.REF
            if (r === 0 && c === 0) return rg
            if (r === 0) return sub(rg, 0, c - 1, R - 1, c - 1)
            if (c === 0) return C === 1 ? at(rg, r - 1, 0) : sub(rg, r - 1, 0, r - 1, C - 1)
            return at(rg, r - 1, c - 1)
        },
    },
    CHOOSE: { min: 2, fn: args => { const i = n0(args, 0); if (isErr(i)) return i; return i >= 1 && i < args.length ? args[Math.floor(i)] : E.VALUE } },
    ROW: { fn: (args, ctx) => args[0] == null ? ctx.r + 1 : isRange(args[0]) ? args[0].r1 + 1 : E.VALUE },
    COLUMN: { fn: (args, ctx) => args[0] == null ? ctx.c + 1 : isRange(args[0]) ? args[0].c1 + 1 : E.VALUE },
    ROWS: { min: 1, fn: args => isRange(args[0]) ? args[0].fullR2 - args[0].r1 + 1 : dims(args[0])[0] },
    COLUMNS: { min: 1, fn: args => isRange(args[0]) ? args[0].fullC2 - args[0].c1 + 1 : dims(args[0])[1] },
    TRANSPOSE: { min: 1, fn: args => { const m = toMatrix(args[0]); return m[0].map((_, j) => m.map(r => r[j])) } },

    // ---------- 日期与时间 ----------
    TODAY: { volatile: true, fn: () => Math.floor(nowSerial()) },
    NOW: { volatile: true, fn: () => nowSerial() },
    DATE: { min: 3, fn: args => { const y = n0(args, 0), m = n0(args, 1), d = n0(args, 2); const e = firstErr(y, m, d); if (e) return e; const s = dateSerial(Math.floor(y), Math.floor(m), Math.floor(d)); return s == null || s < 0 ? E.NUM : s } },
    TIME: { min: 3, fn: args => { const h = n0(args, 0), m = n0(args, 1), s = n0(args, 2); const e = firstErr(h, m, s); if (e) return e; return ((h * 3600 + m * 60 + s) / 86400) % 1 } },
    YEAR: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCFullYear() } },
    MONTH: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCMonth() + 1 } },
    DAY: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCDate() } },
    HOUR: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCHours() } },
    MINUTE: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCMinutes() } },
    SECOND: { min: 1, fn: args => { const d = dateParts(args[0]); return isErr(d) ? d : d.getUTCSeconds() } },
    WEEKDAY: { min: 1, fn: args => { const d = dateParts(args[0]); if (isErr(d)) return d; const t = n0(args, 1, 1), w = d.getUTCDay(); return t === 2 ? (w + 6) % 7 + 1 : t === 3 ? (w + 6) % 7 : w + 1 } },
    DATEVALUE: { min: 1, fn: args => { const n = parseDateText(s0(args, 0)); return n == null ? E.VALUE : Math.floor(n) } },
    EDATE: { min: 2, fn: args => { const d = dateParts(args[0]), m = n0(args, 1); const e = firstErr(d, m); if (e) return e; return dateSerial(d.getUTCFullYear(), d.getUTCMonth() + 1 + Math.trunc(m), d.getUTCDate()) } },
    EOMONTH: { min: 2, fn: args => { const d = dateParts(args[0]), m = n0(args, 1); const e = firstErr(d, m); if (e) return e; return dateSerial(d.getUTCFullYear(), d.getUTCMonth() + 2 + Math.trunc(m), 0) } },
    DAYS: { min: 2, fn: args => { const a = n0(args, 0), b = n0(args, 1); const e = firstErr(a, b); return e ?? Math.floor(a) - Math.floor(b) } },
    DATEDIF: {
        min: 3, fn: args => {
            const a = dateParts(args[0]), b = dateParts(args[1]), u = s0(args, 2).toUpperCase()
            const e = firstErr(a, b); if (e) return e
            if (a > b) return E.NUM
            const months = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + b.getUTCMonth() - a.getUTCMonth() - (b.getUTCDate() < a.getUTCDate() ? 1 : 0)
            if (u === 'Y') return Math.floor(months / 12)
            if (u === 'M') return months
            if (u === 'D') return Math.round((b - a) / 86400000)
            return E.NUM
        },
    },
}
