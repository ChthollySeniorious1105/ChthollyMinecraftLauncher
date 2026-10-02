// 函数库（数学 / 统计 / 逻辑）。文本、查找、日期函数见 functions-text.js
import { E, isErr, isRange, isMulti, isMatrix, dims, at, toNum, toStr, toBool, compare, scalar, parseNumberText } from './values.js'
import { TEXT_FUNCS } from './functions-text.js'

// 展开参数中的所有值：区域内只取数字（Excel 规则），直接参数可转换
export function flatNums(args, { direct = true } = {}) {
    const out = []
    for (const a of args) {
        if (isRange(a)) {
            let e = null
            a.each(v => { if (e) return; if (isErr(v)) e = v; else if (typeof v === 'number') out.push(v) })
            if (e) return e
        } else if (isMatrix(a)) {
            for (const row of a) for (const v of row) { if (isErr(v)) return v; if (typeof v === 'number') out.push(v) }
        } else if (a != null) {
            if (!direct) continue
            const n = toNum(a)
            if (isErr(n)) return n
            out.push(n)
        }
    }
    return out
}
export function flatAll(args) {
    const out = []
    for (const a of args) {
        if (isRange(a)) a.each(v => out.push(v))
        else if (isMatrix(a)) for (const row of a) out.push(...row)
        else out.push(a)
    }
    return out
}

// 条件匹配：'>5' / '<>abc' / 'a*' / 5
export function criteria(crit) {
    if (isMulti(crit)) crit = scalar(crit)
    if (typeof crit === 'number' || typeof crit === 'boolean') return v => v === crit || (typeof v === 'string' && parseNumberText(v) === crit)
    if (crit == null) return v => v == null || v === ''
    let s = String(crit), op = '='
    const m = /^(<=|>=|<>|=|<|>)/.exec(s)
    if (m) { op = m[1]; s = s.slice(m[1].length) }
    const n = parseNumberText(s)
    if (n != null) {
        return v => {
            if (typeof v !== 'number') return op === '<>' ? true : false
            const c = v < n ? -1 : v > n ? 1 : 0
            return cmpOp(op, c)
        }
    }
    const lower = s.toLowerCase()
    if (op === '=' || op === '<>') {
        if (s === '') return op === '=' ? v => v == null || v === '' : v => !(v == null || v === '')
        const wild = /[*?]/.test(s)
        const re = wild ? new RegExp('^' + lower.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/~\*/g, '\u0001').replace(/~\?/g, '\u0002').replace(/\*/g, '.*').replace(/\?/g, '.').replace(/\u0001/g, '\\*').replace(/\u0002/g, '\\?') + '$', 's') : null
        const test = v => {
            if (typeof v === 'boolean') return lower === String(v).toLowerCase()
            if (typeof v !== 'string') return typeof v === 'number' ? String(v) === s : false
            return re ? re.test(v.toLowerCase()) : v.toLowerCase() === lower
        }
        return op === '=' ? test : v => !test(v)
    }
    return v => typeof v === 'string' && cmpOp(op, compare(v, s))
}
const cmpOp = (op, c) => op === '=' ? c === 0 : op === '<>' ? c !== 0 : op === '<' ? c < 0 : op === '>' ? c > 0 : op === '<=' ? c <= 0 : c >= 0

// 便捷包装
const num1 = fn => args => {
    const n = toNum(scalar(args[0]))
    return isErr(n) ? n : fn(n, args)
}
const nums = fn => args => {
    const a = flatNums(args)
    return isErr(a) ? a : fn(a)
}
const argNum = (args, i, def) => {
    if (args[i] == null) return def
    return toNum(scalar(args[i]))
}
const round = (x, d, mode) => {
    const f = Math.pow(10, d)
    const y = x * f
    let r
    if (mode === 'up') r = Math.sign(y) * Math.ceil(Math.abs(y) - 1e-9)
    else if (mode === 'down') r = Math.sign(y) * Math.floor(Math.abs(y) + 1e-9)
    else r = Math.sign(y) * Math.round(Math.abs(y) + 1e-9 * Math.abs(y) / Math.max(1, Math.abs(y)) + 1e-12)
    return +(r / f).toPrecision(15)
}
const mean = a => a.reduce((s, x) => s + x, 0) / a.length
const variance = (a, sample) => {
    const m = mean(a)
    return a.reduce((s, x) => s + (x - m) ** 2, 0) / (a.length - (sample ? 1 : 0))
}
const median = a => {
    const s = [...a].sort((x, y) => x - y), n = s.length
    return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

// 条件聚合：SUMIF / AVERAGEIF / COUNTIFS 等共用
function condIndexes(pairs) {
    // pairs: [[range, crit], ...]，返回满足全部条件的 [i, j] 列表
    const [r0] = pairs
    if (!isMulti(r0[0])) return E.VALUE
    const [R, C] = dims(r0[0])
    const tests = pairs.map(([rg, c]) => [rg, criteria(c)])
    for (const [rg] of tests) { const [r, c] = dims(rg); if (r !== R || c !== C) return E.VALUE }
    const out = []
    for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) {
        if (tests.every(([rg, t]) => t(at(rg, i, j)))) out.push([i, j])
    }
    return out
}
function sumAt(rg, idx) {
    let s = 0, n = 0
    for (const [i, j] of idx) {
        const v = at(rg, i, j)
        if (isErr(v)) return [v, 0]
        if (typeof v === 'number') { s += v; n++ }
    }
    return [s, n]
}

export const FUNCS = {
    // ---------- 数学 ----------
    SUM: { fn: nums(a => a.reduce((s, x) => s + x, 0)) },
    PRODUCT: { fn: nums(a => a.length ? a.reduce((s, x) => s * x, 1) : 0) },
    AVERAGE: { fn: nums(a => a.length ? mean(a) : E.DIV0) },
    MIN: { fn: nums(a => a.length ? Math.min(...a) : 0) },
    MAX: { fn: nums(a => a.length ? Math.max(...a) : 0) },
    MEDIAN: { fn: nums(a => a.length ? median(a) : E.NUM) },
    STDEV: { fn: nums(a => a.length > 1 ? Math.sqrt(variance(a, true)) : E.DIV0) },
    'STDEV.S': { fn: nums(a => a.length > 1 ? Math.sqrt(variance(a, true)) : E.DIV0) },
    STDEVP: { fn: nums(a => a.length ? Math.sqrt(variance(a, false)) : E.DIV0) },
    'STDEV.P': { fn: nums(a => a.length ? Math.sqrt(variance(a, false)) : E.DIV0) },
    VAR: { fn: nums(a => a.length > 1 ? variance(a, true) : E.DIV0) },
    'VAR.S': { fn: nums(a => a.length > 1 ? variance(a, true) : E.DIV0) },
    VARP: { fn: nums(a => a.length ? variance(a, false) : E.DIV0) },
    COUNT: { fn: args => { let n = 0; for (const v of flatAll(args)) if (typeof v === 'number') n++; return n } },
    COUNTA: { fn: args => { let n = 0; for (const v of flatAll(args)) if (v != null && v !== '') n++; return n } },
    COUNTBLANK: { fn: args => { let n = 0; const a = args[0]; const [R, C] = dims(a); for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) { const v = at(a, i, j); if (v == null || v === '') n++ } return n } },
    ABS: { min: 1, fn: num1(Math.abs) },
    SQRT: { min: 1, fn: num1(n => n < 0 ? E.NUM : Math.sqrt(n)) },
    POWER: { min: 2, fn: args => { const a = toNum(scalar(args[0])), b = toNum(scalar(args[1])); if (isErr(a)) return a; if (isErr(b)) return b; const r = Math.pow(a, b); return Number.isFinite(r) ? r : E.NUM } },
    EXP: { min: 1, fn: num1(Math.exp) },
    LN: { min: 1, fn: num1(n => n <= 0 ? E.NUM : Math.log(n)) },
    LOG10: { min: 1, fn: num1(n => n <= 0 ? E.NUM : Math.log10(n)) },
    LOG: { min: 1, fn: args => { const n = toNum(scalar(args[0])), b = argNum(args, 1, 10); if (isErr(n)) return n; if (isErr(b)) return b; return n <= 0 || b <= 0 || b === 1 ? E.NUM : Math.log(n) / Math.log(b) } },
    MOD: { min: 2, fn: args => { const a = toNum(scalar(args[0])), b = toNum(scalar(args[1])); if (isErr(a)) return a; if (isErr(b)) return b; if (b === 0) return E.DIV0; return +(a - b * Math.floor(a / b)).toPrecision(15) } },
    INT: { min: 1, fn: num1(Math.floor) },
    TRUNC: { min: 1, fn: args => { const n = toNum(scalar(args[0])), d = argNum(args, 1, 0); if (isErr(n)) return n; return round(n, d, 'down') } },
    SIGN: { min: 1, fn: num1(Math.sign) },
    PI: { fn: () => Math.PI },
    RAND: { volatile: true, fn: () => Math.random() },
    RANDBETWEEN: { volatile: true, min: 2, fn: args => { const a = toNum(scalar(args[0])), b = toNum(scalar(args[1])); if (isErr(a)) return a; if (isErr(b)) return b; const lo = Math.ceil(a), hi = Math.floor(b); return lo > hi ? E.NUM : lo + Math.floor(Math.random() * (hi - lo + 1)) } },
    ROUND: { min: 1, fn: args => { const n = toNum(scalar(args[0])), d = argNum(args, 1, 0); if (isErr(n)) return n; if (isErr(d)) return d; return round(n, Math.trunc(d)) } },
    ROUNDUP: { min: 1, fn: args => { const n = toNum(scalar(args[0])), d = argNum(args, 1, 0); if (isErr(n)) return n; if (isErr(d)) return d; return round(n, Math.trunc(d), 'up') } },
    ROUNDDOWN: { min: 1, fn: args => { const n = toNum(scalar(args[0])), d = argNum(args, 1, 0); if (isErr(n)) return n; if (isErr(d)) return d; return round(n, Math.trunc(d), 'down') } },
    CEILING: { min: 1, fn: args => { const n = toNum(scalar(args[0])), s = argNum(args, 1, 1); if (isErr(n)) return n; if (isErr(s)) return s; return s === 0 ? 0 : +(Math.ceil(n / s - 1e-12) * s).toPrecision(15) } },
    FLOOR: { min: 1, fn: args => { const n = toNum(scalar(args[0])), s = argNum(args, 1, 1); if (isErr(n)) return n; if (isErr(s)) return s; return s === 0 ? E.DIV0 : +(Math.floor(n / s + 1e-12) * s).toPrecision(15) } },
    SIN: { min: 1, fn: num1(Math.sin) }, COS: { min: 1, fn: num1(Math.cos) }, TAN: { min: 1, fn: num1(Math.tan) },
    ASIN: { min: 1, fn: num1(Math.asin) }, ACOS: { min: 1, fn: num1(Math.acos) }, ATAN: { min: 1, fn: num1(Math.atan) },
    ATAN2: { min: 2, fn: args => Math.atan2(toNum(scalar(args[1])), toNum(scalar(args[0]))) },
    DEGREES: { min: 1, fn: num1(n => n * 180 / Math.PI) }, RADIANS: { min: 1, fn: num1(n => n * Math.PI / 180) },
    FACT: { min: 1, fn: num1(n => { if (n < 0) return E.NUM; let r = 1; for (let i = 2; i <= Math.floor(n); i++) r *= i; return r }) },
    SUMSQ: { fn: nums(a => a.reduce((s, x) => s + x * x, 0)) },
    SUMPRODUCT: {
        fn: args => {
            if (!args.length) return E.VALUE
            const [R, C] = dims(args[0])
            for (const a of args) { const [r, c] = dims(a); if (r !== R || c !== C) return E.VALUE }
            let s = 0
            for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) {
                let p = 1
                for (const a of args) {
                    const v = at(a, i, j)
                    if (isErr(v)) return v
                    p *= typeof v === 'number' ? v : typeof v === 'boolean' && !isRange(a) ? +v : 0
                }
                s += p
            }
            return s
        },
    },
    COUNTIF: { min: 2, fn: args => { const idx = condIndexes([[args[0], args[1]]]); return isErr(idx) ? idx : idx.length } },
    COUNTIFS: { min: 2, fn: args => { const p = []; for (let i = 0; i < args.length; i += 2) p.push([args[i], args[i + 1]]); const idx = condIndexes(p); return isErr(idx) ? idx : idx.length } },
    SUMIF: { min: 2, fn: args => { const idx = condIndexes([[args[0], args[1]]]); if (isErr(idx)) return idx; const [s] = sumAt(args[2] ?? args[0], idx); return s } },
    SUMIFS: { min: 3, fn: args => { const p = []; for (let i = 1; i < args.length; i += 2) p.push([args[i], args[i + 1]]); const idx = condIndexes(p); if (isErr(idx)) return idx; return sumAt(args[0], idx)[0] } },
    AVERAGEIF: { min: 2, fn: args => { const idx = condIndexes([[args[0], args[1]]]); if (isErr(idx)) return idx; const [s, n] = sumAt(args[2] ?? args[0], idx); return isErr(s) ? s : n ? s / n : E.DIV0 } },
    AVERAGEIFS: { min: 3, fn: args => { const p = []; for (let i = 1; i < args.length; i += 2) p.push([args[i], args[i + 1]]); const idx = condIndexes(p); if (isErr(idx)) return idx; const [s, n] = sumAt(args[0], idx); return isErr(s) ? s : n ? s / n : E.DIV0 } },
    MAXIFS: { min: 3, fn: args => { const p = []; for (let i = 1; i < args.length; i += 2) p.push([args[i], args[i + 1]]); const idx = condIndexes(p); if (isErr(idx)) return idx; const v = idx.map(([i, j]) => at(args[0], i, j)).filter(x => typeof x === 'number'); return v.length ? Math.max(...v) : 0 } },
    MINIFS: { min: 3, fn: args => { const p = []; for (let i = 1; i < args.length; i += 2) p.push([args[i], args[i + 1]]); const idx = condIndexes(p); if (isErr(idx)) return idx; const v = idx.map(([i, j]) => at(args[0], i, j)).filter(x => typeof x === 'number'); return v.length ? Math.min(...v) : 0 } },
    RANK: { min: 2, fn: rank }, 'RANK.EQ': { min: 2, fn: rank },
    LARGE: { min: 2, fn: args => { const a = flatNums([args[0]]); if (isErr(a)) return a; const k = toNum(scalar(args[1])); if (isErr(k)) return k; const s = a.sort((x, y) => y - x); return k >= 1 && k <= s.length ? s[Math.ceil(k) - 1] : E.NUM } },
    SMALL: { min: 2, fn: args => { const a = flatNums([args[0]]); if (isErr(a)) return a; const k = toNum(scalar(args[1])); if (isErr(k)) return k; const s = a.sort((x, y) => x - y); return k >= 1 && k <= s.length ? s[Math.ceil(k) - 1] : E.NUM } },

    // ---------- 逻辑 ----------
    IF: {
        lazy: true,
        fn: (args, ctx, ev) => {
            if (!args.length) return E.VALUE
            const c = toBool(scalar(ev(args[0], ctx)))
            if (isErr(c)) return c
            if (c) return args.length > 1 ? ev(args[1], ctx) ?? 0 : true
            return args.length > 2 ? ev(args[2], ctx) ?? 0 : false
        },
    },
    IFS: {
        lazy: true,
        fn: (args, ctx, ev) => {
            for (let i = 0; i + 1 < args.length; i += 2) {
                const c = toBool(scalar(ev(args[i], ctx)))
                if (isErr(c)) return c
                if (c) return ev(args[i + 1], ctx)
            }
            return E.NA
        },
    },
    IFERROR: { lazy: true, fn: (args, ctx, ev) => { const v = ev(args[0], ctx); return isErr(scalar(v)) ? ev(args[1] ?? { type: 'str', v: '' }, ctx) : v } },
    IFNA: { lazy: true, fn: (args, ctx, ev) => { const v = ev(args[0], ctx); return scalar(v) === E.NA ? ev(args[1], ctx) : v } },
    SWITCH: {
        lazy: true,
        fn: (args, ctx, ev) => {
            const v = scalar(ev(args[0], ctx))
            if (isErr(v)) return v
            let i = 1
            for (; i + 1 < args.length; i += 2) if (compare(v, scalar(ev(args[i], ctx))) === 0) return ev(args[i + 1], ctx)
            return i < args.length ? ev(args[i], ctx) : E.NA
        },
    },
    AND: { fn: args => { let r = true, any = false; for (const v of flatAll(args)) { if (v == null || typeof v === 'string' && !/^(true|false)$/i.test(v)) continue; const b = toBool(v); if (isErr(b)) return b; any = true; r = r && b } return any ? r : E.VALUE } },
    OR: { fn: args => { let r = false, any = false; for (const v of flatAll(args)) { if (v == null || typeof v === 'string' && !/^(true|false)$/i.test(v)) continue; const b = toBool(v); if (isErr(b)) return b; any = true; r = r || b } return any ? r : E.VALUE } },
    XOR: { fn: args => { let r = false; for (const v of flatAll(args)) { if (v == null) continue; const b = toBool(v); if (isErr(b)) return b; r = r !== b } return r } },
    NOT: { min: 1, fn: args => { const b = toBool(scalar(args[0])); return isErr(b) ? b : !b } },
    TRUE: { fn: () => true }, FALSE: { fn: () => false },
    NA: { fn: () => E.NA },
    ISBLANK: { min: 1, fn: args => scalar(args[0]) == null },
    ISNUMBER: { min: 1, fn: args => typeof scalar(args[0]) === 'number' },
    ISTEXT: { min: 1, fn: args => typeof scalar(args[0]) === 'string' },
    ISLOGICAL: { min: 1, fn: args => typeof scalar(args[0]) === 'boolean' },
    ISERROR: { min: 1, fn: args => isErr(scalar(args[0])) },
    ISERR: { min: 1, fn: args => { const v = scalar(args[0]); return isErr(v) && v !== E.NA } },
    ISNA: { min: 1, fn: args => scalar(args[0]) === E.NA },
    ISEVEN: { min: 1, fn: num1(n => Math.floor(Math.abs(n)) % 2 === 0) },
    ISODD: { min: 1, fn: num1(n => Math.floor(Math.abs(n)) % 2 === 1) },
    ...TEXT_FUNCS,
}

function rank(args) {
    const n = toNum(scalar(args[0]))
    if (isErr(n)) return n
    const a = flatNums([args[1]])
    if (isErr(a)) return a
    const asc = args[2] != null && toNum(scalar(args[2])) !== 0
    if (!a.includes(n)) return E.NA
    return 1 + a.filter(x => asc ? x < n : x > n).length
}

export const FUNC_NAMES = Object.keys(FUNCS).sort()
