// 安全的数学表达式解析器（不使用 eval）
// 支持：数字、变量、常量 pi/π/e、函数调用、+ - * / % ^、阶乘 !、角度 °、比较运算、|x| 绝对值、隐式乘法（2x、3(x+1)、2 sin(x)、xy）
//       √x / √(x+1) / ∛x、上标 x² x³ x⁻¹、≤ ≥ ≠
// compile(src) -> { fn(scope), names }；scope: { 变量名: 数值, __funcs: { 名称: (x) => y } }

const deg = Math.PI / 180
const fact = n => {
    if (n < 0 || !Number.isFinite(n)) return NaN
    if (n !== Math.floor(n)) return Math.exp(lnGamma(n + 1))
    let r = 1
    for (let i = 2; i <= n; i++) r *= i
    return r
}
function lnGamma(z) {
    const g = 7, c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
    if (z < 0.5) return Math.log(Math.PI / Math.abs(Math.sin(Math.PI * z))) - lnGamma(1 - z)
    z -= 1
    let x = c[0]
    for (let i = 1; i < g + 2; i++) x += c[i] / (z + i)
    const t = z + g + 0.5
    return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(x)
}

export const FUNCS = {
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan, arcsin: Math.asin, arccos: Math.acos, arctan: Math.atan,
    atan2: Math.atan2,
    sec: x => 1 / Math.cos(x), csc: x => 1 / Math.sin(x), cot: x => 1 / Math.tan(x),
    sinh: Math.sinh, cosh: Math.cosh, tanh: Math.tanh,
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, root4: x => Math.pow(x, 0.25),
    nroot: (x, n) => (x < 0 && Math.round(n) % 2 === 1 ? -Math.pow(-x, 1 / n) : Math.pow(x, 1 / n)),
    ln: Math.log, log: (x, b) => b === undefined ? Math.log10(x) : Math.log(x) / Math.log(b), lg: Math.log10, log2: Math.log2,
    exp: Math.exp, floor: Math.floor, ceil: Math.ceil, round: (x, n = 0) => Math.round(x * 10 ** n) / 10 ** n,
    sign: Math.sign, sgn: Math.sign, min: Math.min, max: Math.max, pow: Math.pow,
    mod: (a, b) => ((a % b) + b) % b, fact, gamma: x => Math.exp(lnGamma(x)),
    rad: x => x * deg, deg: x => x / deg,
    random: () => Math.random(),
    if: (c, a, b = NaN) => (c ? a : b),
}
export const CONSTS = { pi: Math.PI, 'π': Math.PI, e: Math.E, tau: Math.PI * 2 }

// ---------- 词法 ----------
function tokenize(src) {
    const toks = []
    let i = 0
    const s = normalize(src)
    while (i < s.length) {
        const c = s[i]
        if (/\s/.test(c)) { i++; continue }
        let m
        if ((m = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(i)))) {
            // 2e 之类的写法：e 后面不是数字时视为常数 e
            let text = m[0]
            if (m[2] === undefined && /e/i.test(text)) text = text.replace(/e.*/i, '')
            toks.push({ t: 'num', v: Number(text), pos: i })
            i += text.length
            continue
        }
        if ((m = /^[\p{L}_][\p{L}\p{N}_']*/u.exec(s.slice(i)))) {
            // xy、xyz 这类由坐标变量组成的写法视为乘积
            if (/^[xyzt]{2,3}$/.test(m[0])) for (const ch of m[0]) toks.push({ t: 'id', v: ch, pos: i })
            else toks.push({ t: 'id', v: m[0], pos: i })
            i += m[0].length
            continue
        }
        const two = s.slice(i, i + 2)
        if (['<=', '>=', '==', '!=', '**'].includes(two)) {
            toks.push({ t: 'op', v: two === '**' ? '^' : two, pos: i })
            i += 2
            continue
        }
        if ('+-*/%^()!,<>|°'.includes(c)) { toks.push({ t: 'op', v: c, pos: i }); i++; continue }
        if (c === '=') { toks.push({ t: 'op', v: '==', pos: i }); i++; continue }
        throw new SyntaxError(`无法识别的字符 “${c}”`)
    }
    toks.push({ t: 'end', pos: s.length })
    return toks
}

// 统一各种书写习惯：全角符号、上标、根号、π 等
const SUP = { '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-', '⁺': '+', '⁽': '(', '⁾': ')', 'ⁿ': 'n', 'ˣ': 'x' }
export function normalize(src) {
    return String(src)
        .replace(/[×·∙⋅]/g, '*').replace(/÷/g, '/').replace(/[−–—]/g, '-')
        .replace(/（/g, '(').replace(/）/g, ')').replace(/，/g, ',').replace(/［/g, '[').replace(/］/g, ']')
        .replace(/≤/g, '<=').replace(/≥/g, '>=').replace(/≠/g, '!=')
        // 上标序列 → ^(...)
        .replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺⁽⁾ⁿˣ]+/g, m => '^(' + [...m].map(c => SUP[c]).join('') + ')')
        // 根号：√x、√(…)、∛x、∜x
        .replace(/∛/g, 'cbrt ').replace(/∜/g, 'root4 ').replace(/√/g, 'sqrt ')
        .replace(/[\[]/g, '(').replace(/]/g, ')')
}

// ---------- 语法 ----------
// AST 节点：{ k: 'num', v } | { k: 'var', n } | { k: 'call', n, args } | { k: 'un', op, a } | { k: 'bin', op, a, b }
function parse(src) {
    const toks = tokenize(src)
    let p = 0
    let absDepth = 0
    const peek = () => toks[p]
    const next = () => toks[p++]
    const isOp = (v, t = peek()) => t.t === 'op' && t.v === v
    const expect = v => {
        if (!isOp(v)) throw new SyntaxError(`缺少 “${v}”`)
        p++
    }

    const expr = () => cmp()
    const cmp = () => {
        let a = add()
        while (peek().t === 'op' && ['<', '>', '<=', '>=', '==', '!='].includes(peek().v)) {
            const op = next().v
            a = { k: 'bin', op, a, b: add() }
        }
        return a
    }
    const add = () => {
        let a = mul()
        while (isOp('+') || isOp('-')) {
            const op = next().v
            a = { k: 'bin', op, a, b: mul() }
        }
        return a
    }
    // 下一个记号能否开始一个因子（用于隐式乘法）
    const startsPrimary = t => t.t === 'num' || t.t === 'id' || (t.t === 'op' && (t.v === '(' || (t.v === '|' && absDepth === 0)))
    const mul = () => {
        let a = unary()
        for (;;) {
            if (isOp('*') || isOp('/') || isOp('%')) {
                const op = next().v
                a = { k: 'bin', op, a, b: unary() }
            } else if (startsPrimary(peek())) {
                a = { k: 'bin', op: '*', a, b: power() }
            } else break
        }
        return a
    }
    const unary = () => {
        if (isOp('-')) { next(); return { k: 'un', op: '-', a: unary() } }
        if (isOp('+')) { next(); return unary() }
        return power()
    }
    const power = () => {
        const base = postfix()
        if (isOp('^')) { next(); return { k: 'bin', op: '^', a: base, b: unary() } }
        return base
    }
    const postfix = () => {
        let a = primary()
        for (;;) {
            if (isOp('!')) { next(); a = { k: 'call', n: 'fact', args: [a] } }
            else if (isOp('°')) { next(); a = { k: 'bin', op: '*', a, b: { k: 'num', v: deg } } }
            else break
        }
        return a
    }
    const primary = () => {
        const t = next()
        if (t.t === 'num') return { k: 'num', v: t.v }
        if (t.t === 'id') {
            if (isOp('(')) {
                next()
                const args = []
                if (!isOp(')')) {
                    args.push(expr())
                    while (isOp(',')) { next(); args.push(expr()) }
                }
                expect(')')
                return { k: 'call', n: t.v, args }
            }
            // sin x 这种不带括号的写法
            if (FUNCS[t.v] && startsPrimary(peek()) && peek().t !== 'op') return { k: 'call', n: t.v, args: [power()] }
            return { k: 'var', n: t.v }
        }
        if (t.t === 'op' && t.v === '(') {
            const e = expr()
            expect(')')
            return e
        }
        if (t.t === 'op' && t.v === '|') {
            absDepth++
            const e = expr()
            absDepth--
            expect('|')
            return { k: 'call', n: 'abs', args: [e] }
        }
        if (t.t === 'end') throw new SyntaxError('表达式不完整')
        throw new SyntaxError(`意外的 “${t.v}”`)
    }

    const ast = expr()
    if (peek().t !== 'end') throw new SyntaxError(`意外的 “${peek().v}”`)
    return ast
}

// ---------- 编译为闭包 ----------
function build(node, names) {
    switch (node.k) {
        case 'num': { const v = node.v; return () => v }
        case 'var': {
            const n = node.n
            if (n in CONSTS) {
                const v = CONSTS[n]
                return s => (n in s ? s[n] : v)
            }
            names.add(n)
            return s => { const v = s[n]; return typeof v === 'number' ? v : NaN }
        }
        case 'un': { const a = build(node.a, names); return s => -a(s) }
        case 'call': {
            const args = node.args.map(x => build(x, names))
            const n = node.n
            const f = FUNCS[n]
            if (f) {
                if (args.length === 1) { const a = args[0]; return s => f(a(s)) }
                if (args.length === 2) { const [a, b] = args; return s => f(a(s), b(s)) }
                return s => f(...args.map(a => a(s)))
            }
            // 用户定义的函数（例如几何画板中的 f(x)）
            names.add(n)
            return s => {
                const uf = s.__funcs?.[n]
                return uf ? uf(...args.map(a => a(s))) : NaN
            }
        }
        case 'bin': {
            const a = build(node.a, names), b = build(node.b, names)
            switch (node.op) {
                case '+': return s => a(s) + b(s)
                case '-': return s => a(s) - b(s)
                case '*': return s => a(s) * b(s)
                case '/': return s => a(s) / b(s)
                case '%': return s => a(s) % b(s)
                case '^': return s => Math.pow(a(s), b(s))
                case '<': return s => +(a(s) < b(s))
                case '>': return s => +(a(s) > b(s))
                case '<=': return s => +(a(s) <= b(s))
                case '>=': return s => +(a(s) >= b(s))
                case '==': return s => +(Math.abs(a(s) - b(s)) < 1e-9)
                case '!=': return s => +(Math.abs(a(s) - b(s)) >= 1e-9)
            }
        }
    }
    throw new Error('未知节点')
}

const cache = new Map()
export function compile(src) {
    const key = String(src ?? '')
    let c = cache.get(key)
    if (c) return c
    const names = new Set()
    try {
        const fn = build(parse(key), names)
        c = { fn, names, error: null }
    } catch (e) {
        c = { fn: () => NaN, names, error: e.message }
    }
    if (cache.size > 2000) cache.clear()
    cache.set(key, c)
    return c
}

// 计算一次表达式
export const evaluate = (src, scope = {}) => compile(src).fn(scope)

// 数值格式化：去掉多余的 0
export function fmt(v, digits = 2) {
    if (v == null || !Number.isFinite(v)) return '未定义'
    if (Math.abs(v) >= 1e7 || (Math.abs(v) < 1e-4 && v !== 0)) return v.toExponential(digits)
    const s = v.toFixed(digits)
    return s.includes('.') ? s.replace(/\.?0+$/, '') || '0' : s
}
