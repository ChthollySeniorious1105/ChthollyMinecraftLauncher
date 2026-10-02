// 公式求值：AST + 上下文 -> 值
// ctx: { sid, r, c, sheetId(name) -> sid|null, cellValue(sid,r,c), usedBounds(sid), cellsIn(...) }
import { FErr, E, isErr, RangeVal, isMulti, isRange, dims, at, toNum, toStr, toBool, compare, scalar } from './values.js'
import { FUNCS } from './functions.js'

export function evaluate(ast, ctx) {
    switch (ast.type) {
        case 'num': case 'str': case 'bool': return ast.v
        case 'err': return new FErr(ast.v)
        case 'missing': return null
        case 'array': return ast.rows.map(r => r.map(v => v && typeof v === 'object' && v.err ? new FErr(v.err) : v))
        case 'name': {
            const n = ctx.resolveName?.(ast.v)
            return n === undefined ? E.NAME : n
        }
        case 'ref': {
            const sid = ast.sheet != null ? ctx.sheetId(ast.sheet) : ctx.sid
            if (sid == null) return E.REF
            if (ast.kind === 'cell') return ctx.cellValue(sid, ast.r1, ast.c1)
            return new RangeVal(ctx, sid, ast.r1, ast.c1, ast.r2, ast.c2)
        }
        case 'neg': return map1(evaluate(ast.a, ctx), v => { const n = toNum(v); return isErr(n) ? n : -n })
        case 'pct': return map1(evaluate(ast.a, ctx), v => { const n = toNum(v); return isErr(n) ? n : n / 100 })
        case 'bin': return binary(ast.op, evaluate(ast.a, ctx), evaluate(ast.b, ctx))
        case 'func': {
            const f = FUNCS[ast.name] ?? FUNCS[ast.name.replace(/^_XLFN\./, '')]
            if (!f) return E.NAME
            if (f.lazy) return f.fn(ast.args, ctx, evaluate)
            const args = ast.args.map(a => evaluate(a, ctx))
            if (f.min != null && args.length < f.min) return E.VALUE
            return f.fn(args, ctx)
        }
    }
    return E.VALUE
}

// 最终结果：区域 / 数组取左上角；空值 -> 0（公式引用空单元格时显示 0）
export function finalValue(v) {
    if (isMulti(v)) v = scalar(v)
    if (v == null) return 0
    if (typeof v === 'number' && !Number.isFinite(v)) return E.NUM
    return v
}

function map1(v, fn) {
    if (!isMulti(v)) return fn(v)
    const [R, C] = dims(v), out = []
    for (let i = 0; i < R; i++) { const row = []; for (let j = 0; j < C; j++) row.push(fn(at(v, i, j))); out.push(row) }
    return out
}

function binary(op, a, b) {
    if (isMulti(a) || isMulti(b)) {
        const [ra, ca] = dims(a), [rb, cb] = dims(b)
        const R = Math.max(ra, rb), C = Math.max(ca, cb)
        const pick = (v, rv, cv, i, j) => isMulti(v) ? (i < rv || rv === 1) && (j < cv || cv === 1) ? at(v, rv === 1 ? 0 : i, cv === 1 ? 0 : j) : E.NA : v
        const out = []
        for (let i = 0; i < R; i++) {
            const row = []
            for (let j = 0; j < C; j++) row.push(binScalar(op, pick(a, ra, ca, i, j), pick(b, rb, cb, i, j)))
            out.push(row)
        }
        return out
    }
    return binScalar(op, a, b)
}

function binScalar(op, a, b) {
    if (isErr(a)) return a
    if (isErr(b)) return b
    switch (op) {
        case '&': return toStr(a) + toStr(b)
        case '=': return compare(a, b) === 0
        case '<>': return compare(a, b) !== 0
        case '<': return compare(a, b) < 0
        case '>': return compare(a, b) > 0
        case '<=': return compare(a, b) <= 0
        case '>=': return compare(a, b) >= 0
    }
    const x = toNum(a), y = toNum(b)
    if (isErr(x)) return x
    if (isErr(y)) return y
    switch (op) {
        case '+': return x + y
        case '-': return x - y
        case '*': return x * y
        case '/': return y === 0 ? E.DIV0 : x / y
        case '^': {
            if (x === 0 && y === 0) return E.NUM
            const r = Math.pow(x, y)
            return Number.isFinite(r) ? r : E.NUM
        }
    }
    return E.VALUE
}

export { toBool }
