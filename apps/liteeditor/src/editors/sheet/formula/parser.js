// 公式语法分析：记号 -> AST
// 优先级（从低到高）：比较 < & < + - < * / < ^ < 百分号 < 取负 < 区域 ':'
import { tokenize } from './lexer.js'

export class ParseError extends Error {}

export function parse(src) {
    const toks = tokenize(src)
    let i = 0
    const peek = () => toks[i]
    const next = () => toks[i++]
    const isOp = (...ops) => peek()?.t === 'op' && ops.includes(peek().v)
    const expect = t => {
        const k = next()
        if (!k || k.t !== t) throw new ParseError(`缺少 “${t}”`)
        return k
    }

    const cmp = () => {
        let a = concat()
        while (isOp('=', '<>', '<', '>', '<=', '>=')) { const op = next().v; a = { type: 'bin', op, a, b: concat() } }
        return a
    }
    const concat = () => {
        let a = add()
        while (isOp('&')) { next(); a = { type: 'bin', op: '&', a, b: add() } }
        return a
    }
    const add = () => {
        let a = mul()
        while (isOp('+', '-')) { const op = next().v; a = { type: 'bin', op, a, b: mul() } }
        return a
    }
    const mul = () => {
        let a = pow()
        while (isOp('*', '/')) { const op = next().v; a = { type: 'bin', op, a, b: pow() } }
        return a
    }
    const pow = () => {
        let a = pct()
        while (isOp('^')) { next(); a = { type: 'bin', op: '^', a, b: pct() } }
        return a
    }
    const pct = () => {
        let a = unary()
        while (isOp('%')) { next(); a = { type: 'pct', a } }
        return a
    }
    const unary = () => {
        if (isOp('-')) { next(); return { type: 'neg', a: unary() } }
        if (isOp('+')) { next(); return unary() }
        return range()
    }
    const range = () => {
        let a = primary()
        while (peek()?.t === ':') {
            next()
            const b = primary()
            if (a.type !== 'ref' || b.type !== 'ref') throw new ParseError('区域运算符只能用于引用')
            a = { type: 'ref', kind: 'range', sheet: a.sheet, r1: Math.min(a.r1, b.r1), c1: Math.min(a.c1, b.c1), r2: Math.max(a.r2, b.r2), c2: Math.max(a.c2, b.c2) }
        }
        return a
    }
    const primary = () => {
        const t = next()
        if (!t) throw new ParseError('公式不完整')
        switch (t.t) {
            case 'num': return { type: 'num', v: t.v }
            case 'str': return { type: 'str', v: t.v }
            case 'bool': return { type: 'bool', v: t.v }
            case 'err': return { type: 'err', v: t.v }
            case 'ref': return { type: 'ref', kind: t.kind, sheet: t.sheet, r1: t.r1, c1: t.c1, r2: t.r2, c2: t.c2 }
            case 'name': return { type: 'name', v: t.v }
            case '(': {
                const e = cmp()
                expect(')')
                return e
            }
            case '{': {
                const rows = [[]]
                for (;;) {
                    let neg = false
                    if (isOp('-')) { next(); neg = true }
                    const v = next()
                    if (!v || !['num', 'str', 'bool', 'err'].includes(v.t)) throw new ParseError('数组常量无效')
                    rows[rows.length - 1].push(v.t === 'num' && neg ? -v.v : v.t === 'err' ? { err: v.v } : v.v)
                    const s = next()
                    if (s?.t === '}') break
                    if (s?.t === ',' && !s.semi) continue
                    if (s?.t === ',' && s.semi) { rows.push([]); continue }
                    throw new ParseError('数组常量无效')
                }
                return { type: 'array', rows }
            }
            case 'func': {
                expect('(')
                const args = []
                if (peek()?.t === ')') { next(); return { type: 'func', name: t.v, args } }
                for (;;) {
                    if (peek()?.t === ',' || peek()?.t === ')') args.push({ type: 'missing' })
                    else args.push(cmp())
                    const s = next()
                    if (s?.t === ')') break
                    if (s?.t !== ',') throw new ParseError('函数参数缺少 “)”')
                }
                return { type: 'func', name: t.v, args }
            }
            case 'op':
                throw new ParseError(`意外的运算符 “${t.v}”`)
            default:
                throw new ParseError('无法识别的内容 “' + (t.text ?? t.t) + '”')
        }
    }

    if (!toks.length) throw new ParseError('公式为空')
    const ast = cmp()
    if (i < toks.length) throw new ParseError('公式中有多余的内容')
    return ast
}

// 收集 AST 中的引用与函数名
export function collectRefs(ast, out = { refs: [], funcs: new Set() }) {
    if (!ast) return out
    if (ast.type === 'ref') out.refs.push(ast)
    else if (ast.type === 'func') { out.funcs.add(ast.name); for (const a of ast.args) collectRefs(a, out) }
    else if (ast.a) { collectRefs(ast.a, out); if (ast.b) collectRefs(ast.b, out) }
    return out
}
