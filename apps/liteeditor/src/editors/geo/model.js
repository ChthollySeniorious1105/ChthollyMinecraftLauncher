// 几何画板数据模型：构造式依赖图
// 每个对象只保存“定义”（父对象 id + 参数），数值由 computeVal 按创建顺序推导
// 值的形状（世界坐标，y 轴向上）：
//   { kind: 'point', x, y }
//   { kind: 'line' | 'segment' | 'ray', p: {x,y}, q: {x,y} }        方向 p → q
//   { kind: 'circle', c: {x,y}, r }
//   { kind: 'arc', c, r, a0, a1 }                                     从 a0 逆时针到 a1（a1 > a0）
//   { kind: 'polygon', pts: [{x,y}] }
//   { kind: 'func', f, xmin, xmax }                                    y = f(x)
//   { kind: 'curve', pts: [{x,y}], closed, implicit? }                参数曲线 / 轨迹 / 隐函数曲线（采样）
//   { kind: 'conic', shape, c, u, a, b, p, coef }                     椭圆 / 双曲线 / 抛物线（见 conic.js）
//   { kind: 'number', v, text?, unit? }
//   { kind: 'text', text }
import { compile, fmt } from './expr.js'
import * as K from './conic.js'

export const EPS = 1e-9
const TAU = Math.PI * 2
const deg = Math.PI / 180

// ---------- 向量 ----------
export const P = (x, y) => ({ x, y })
export const add = (a, b) => P(a.x + b.x, a.y + b.y)
export const sub = (a, b) => P(a.x - b.x, a.y - b.y)
export const mul = (a, k) => P(a.x * k, a.y * k)
export const dot = (a, b) => a.x * b.x + a.y * b.y
export const cross = (a, b) => a.x * b.y - a.y * b.x
export const len = a => Math.hypot(a.x, a.y)
export const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)
export const norm = a => { const l = len(a); return l < EPS ? P(0, 0) : P(a.x / l, a.y / l) }
export const perp = a => P(-a.y, a.x)
export const lerp = (a, b, t) => P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
export const rot = (a, c, ang) => {
    const s = Math.sin(ang), co = Math.cos(ang), dx = a.x - c.x, dy = a.y - c.y
    return P(c.x + dx * co - dy * s, c.y + dx * s + dy * co)
}
const finite = p => p && Number.isFinite(p.x) && Number.isFinite(p.y)
const normAng = a => ((a % TAU) + TAU) % TAU

export const isLinear = v => v && (v.kind === 'line' || v.kind === 'segment' || v.kind === 'ray')
export const isRound = v => v && (v.kind === 'circle' || v.kind === 'arc')
export const isPath = v => v && ['line', 'segment', 'ray', 'circle', 'arc', 'polygon', 'func', 'curve', 'conic'].includes(v.kind)
export const isConic = v => v?.kind === 'conic'
// 可以作切线的曲线
export const isSmooth = v => isRound(v) || isConic(v)

// 直线参数 t 是否落在对象范围内
const inRange = (v, t) => v.kind === 'line' || (v.kind === 'ray' ? t >= -1e-9 : t >= -1e-9 && t <= 1 + 1e-9)
// 角度 a 是否在圆弧上
const onArc = (v, a) => v.kind !== 'arc' || normAng(a - v.a0) <= v.a1 - v.a0 + 1e-9

// ---------- 对象类型 ----------
// ref: 引用其他对象 id 的字段；exprs: 表达式字段（可引用数值对象的名称）
export const TYPES = {
    point: { label: '点', ref: [] },
    pointOn: { label: '路径上的点', ref: ['path'] },
    intersect: { label: '交点', ref: ['a', 'b'] },
    midpoint: { label: '中点', ref: ['a', 'b'] },
    segment: { label: '线段', ref: ['a', 'b'] },
    ray: { label: '射线', ref: ['a', 'b'] },
    line: { label: '直线', ref: ['a', 'b'] },
    parallel: { label: '平行线', ref: ['line', 'point'] },
    perpendicular: { label: '垂线', ref: ['line', 'point'] },
    perpBisector: { label: '中垂线', ref: ['a', 'b'] },
    angleBisector: { label: '角平分线', ref: ['a', 'b', 'c'] },
    circle: { label: '圆', ref: ['c', 'p'] },
    circleR: { label: '圆（半径）', ref: ['c'], exprs: ['r'] },
    circle3: { label: '三点圆', ref: ['a', 'b', 'c'] },
    arc: { label: '圆弧', ref: ['c', 'a', 'b'] },
    arc3: { label: '三点圆弧', ref: ['a', 'b', 'c'] },
    polygon: { label: '多边形', ref: ['pts'] },
    regular: { label: '正多边形', ref: ['a', 'b'] },
    tangent: { label: '切线', ref: ['point', 'circle'] },
    ellipse: { label: '椭圆', ref: ['f1', 'f2', 'p'] },
    hyperbola: { label: '双曲线', ref: ['f1', 'f2', 'p'] },
    ellipseC: { label: '椭圆（中心）', ref: ['c', 'v', 'p'] },
    hyperbolaC: { label: '双曲线（中心）', ref: ['c', 'v', 'p'] },
    parabola: { label: '抛物线', ref: ['focus', 'line'] },
    conic5: { label: '五点圆锥曲线', ref: ['pts'] },
    conicStd: { label: '圆锥曲线', ref: ['c'], exprs: ['a', 'b', 'angle'] },
    equation: { label: '方程曲线', ref: [], exprs: ['expr'] },
    conicPart: { label: '圆锥曲线元素', ref: ['of'] },
    translate: { label: '平移', ref: ['src', 'a', 'b'] },
    rotate: { label: '旋转', ref: ['src', 'center'], exprs: ['angle'] },
    reflect: { label: '反射', ref: ['src', 'line'] },
    dilate: { label: '缩放', ref: ['src', 'center'], exprs: ['k'] },
    locus: { label: '轨迹', ref: ['point', 'driver'] },
    func: { label: '函数', ref: [], exprs: ['expr', 'xmin', 'xmax'] },
    derivative: { label: '导函数', ref: ['of'] },
    param: { label: '参数曲线', ref: [], exprs: ['xExpr', 'yExpr', 'tmin', 'tmax'] },
    polar: { label: '极坐标曲线', ref: [], exprs: ['rExpr', 'tmin', 'tmax'] },
    slider: { label: '参数', ref: [] },
    measure: { label: '度量', ref: ['of'] },
    calc: { label: '计算', ref: [], exprs: ['expr'] },
    text: { label: '文本', ref: [] },
}

// 标注类对象：固定在屏幕坐标（sx, sy），不随画布平移缩放
export const isAnnotation = o => o.type === 'slider' || o.type === 'measure' || o.type === 'calc' || o.type === 'text'

// 直接引用的父对象 id
export function refIds(o) {
    const out = []
    for (const f of TYPES[o.type]?.ref ?? []) {
        const v = o[f]
        if (Array.isArray(v)) out.push(...v)
        else if (v) out.push(v)
    }
    return out
}
// 表达式中引用到的名称
export function exprNames(o) {
    const names = new Set()
    for (const f of TYPES[o.type]?.exprs ?? []) {
        if (o[f] == null || o[f] === '') continue
        for (const n of compile(String(o[f])).names) names.add(n)
    }
    if (o.type === 'text') for (const m of String(o.text ?? '').matchAll(/\{([^{}]+)\}/g)) {
        for (const n of compile(m[1]).names) names.add(n)
    }
    return names
}

// ---------- 求值 ----------
// get(id) -> 已计算的值；scope：数值对象名称 -> 数值，__funcs：函数名 -> (x) => y
// view: { xmin, xmax, ymin, ymax }，用于直线轨迹等需要视口范围的计算
export function computeVal(o, get, scope, view) {
    const pt = id => { const v = get(id); return v?.kind === 'point' ? v : null }
    const num = src => {
        const c = compile(String(src ?? ''))
        return c.error ? NaN : c.fn(scope)
    }
    switch (o.type) {
        case 'point': return { kind: 'point', x: o.x, y: o.y }
        case 'pointOn': {
            const path = get(o.path)
            if (!isPath(path)) return null
            const p = pointAt(path, o.t)
            return finite(p) ? { kind: 'point', ...p } : null
        }
        case 'intersect': {
            const a = get(o.a), b = get(o.b)
            if (!a || !b) return null
            const list = intersections(a, b)
            const p = list[o.idx ?? 0]
            return p && p.ok !== false && finite(p) ? { kind: 'point', x: p.x, y: p.y } : null
        }
        case 'midpoint': {
            const a = pt(o.a), b = pt(o.b)
            return a && b ? { kind: 'point', ...lerp(a, b, 0.5) } : null
        }
        case 'segment': case 'ray': case 'line': {
            const a = pt(o.a), b = pt(o.b)
            if (!a || !b || dist(a, b) < EPS) return null
            return { kind: o.type, p: P(a.x, a.y), q: P(b.x, b.y) }
        }
        case 'parallel': case 'perpendicular': {
            const l = get(o.line), p = pt(o.point)
            if (!isLinear(l) || !p) return null
            let d = norm(sub(l.q, l.p))
            if (o.type === 'perpendicular') d = perp(d)
            return { kind: 'line', p: P(p.x, p.y), q: add(p, d) }
        }
        case 'perpBisector': {
            const a = pt(o.a), b = pt(o.b)
            if (!a || !b || dist(a, b) < EPS) return null
            const m = lerp(a, b, 0.5)
            return { kind: 'line', p: m, q: add(m, perp(norm(sub(b, a)))) }
        }
        case 'angleBisector': {
            const a = pt(o.a), b = pt(o.b), c = pt(o.c)
            if (!a || !b || !c) return null
            const u = norm(sub(a, b)), w = norm(sub(c, b))
            let d = add(u, w)
            if (len(d) < 1e-12) d = perp(u)
            return { kind: 'ray', p: P(b.x, b.y), q: add(b, norm(d)) }
        }
        case 'circle': {
            const c = pt(o.c), p = pt(o.p)
            if (!c || !p) return null
            return { kind: 'circle', c: P(c.x, c.y), r: dist(c, p) }
        }
        case 'circleR': {
            const c = pt(o.c), r = Math.abs(num(o.r))
            return c && Number.isFinite(r) ? { kind: 'circle', c: P(c.x, c.y), r } : null
        }
        case 'circle3': {
            const a = pt(o.a), b = pt(o.b), c = pt(o.c)
            const cc = a && b && c && circumcenter(a, b, c)
            return cc ? { kind: 'circle', c: cc, r: dist(cc, a) } : null
        }
        case 'arc': {
            const c = pt(o.c), a = pt(o.a), b = pt(o.b)
            if (!c || !a || !b) return null
            const r = dist(c, a)
            if (r < EPS) return null
            const a0 = Math.atan2(a.y - c.y, a.x - c.x)
            let a1 = Math.atan2(b.y - c.y, b.x - c.x)
            a1 = a0 + normAng(a1 - a0)
            if (a1 - a0 < 1e-9) a1 = a0 + TAU
            return { kind: 'arc', c: P(c.x, c.y), r, a0, a1 }
        }
        case 'arc3': {
            // 从 a 经过 b 到 c 的圆弧
            const a = pt(o.a), b = pt(o.b), c = pt(o.c)
            const cc = a && b && c && circumcenter(a, b, c)
            if (!cc) return null
            const r = dist(cc, a)
            const ang = p => Math.atan2(p.y - cc.y, p.x - cc.x)
            const t0 = ang(a), tb = normAng(ang(b) - t0), tc = normAng(ang(c) - t0)
            // b 在 a→c 逆时针路径上则逆时针，否则从 c 逆时针到 a
            return tb <= tc ? { kind: 'arc', c: cc, r, a0: t0, a1: t0 + tc } : { kind: 'arc', c: cc, r, a0: ang(c), a1: ang(c) + normAng(t0 - ang(c)) }
        }
        case 'polygon': {
            const pts = o.pts.map(pt)
            return pts.every(Boolean) ? { kind: 'polygon', pts: pts.map(p => P(p.x, p.y)) } : null
        }
        case 'regular': {
            const a = pt(o.a), b = pt(o.b), n = Math.round(o.n)
            if (!a || !b || n < 3 || dist(a, b) < EPS) return null
            const pts = [P(a.x, a.y), P(b.x, b.y)]
            const ext = TAU / n
            for (let i = 2; i < n; i++) {
                const p1 = pts[i - 2], p2 = pts[i - 1]
                pts.push(rot(p1, p2, -(Math.PI - ext)))
            }
            return { kind: 'polygon', pts }
        }
        case 'ellipse': case 'hyperbola': {
            const f1 = pt(o.f1), f2 = pt(o.f2), p = pt(o.p)
            return f1 && f2 && p ? K.fromFoci(o.type, f1, f2, p) : null
        }
        case 'ellipseC': case 'hyperbolaC': {
            const c = pt(o.c), v = pt(o.v), p = pt(o.p)
            return c && v && p ? K.fromCenter(o.type === 'ellipseC' ? 'ellipse' : 'hyperbola', c, v, p) : null
        }
        case 'parabola': {
            const f = pt(o.focus), l = get(o.line)
            return f && isLinear(l) ? K.fromFocusDirectrix(f, l) : null
        }
        case 'conic5': {
            const pts = o.pts.map(pt)
            if (pts.length !== 5 || !pts.every(Boolean)) return null
            const k = K.coefThrough(pts)
            return k ? K.fromCoef(k) : null
        }
        case 'conicStd': {
            // 由中心、半轴与旋转角给出：椭圆 / 双曲线用 a、b，抛物线用 a 作焦准距 p
            const c = pt(o.c), a = num(o.a), b = num(o.b), ang = num(o.angle || '0') * deg
            if (!c || !Number.isFinite(ang)) return null
            const u = P(Math.cos(ang), Math.sin(ang))
            return o.shape === 'parabola' ? K.makeConic('parabola', c, u, 0, 0, Math.abs(a)) : K.makeConic(o.shape, c, u, Math.abs(a), Math.abs(b))
        }
        case 'equation': {
            const g = equationFn(o.expr, scope)
            if (!g) return null
            const k = K.quadraticCoef(g)
            if (k) {
                const v = K.fromCoef(k)
                if (v) return v
            }
            // 非二次（或退化）的方程：在视口内描绘 f(x, y) = 0
            const b = view ?? { xmin: -10, xmax: 10, ymin: -10, ymax: 10 }
            const px = (b.xmax - b.xmin) * 0.02, py = (b.ymax - b.ymin) * 0.02
            const lines = K.implicitSegments(g, { xmin: b.xmin - px, xmax: b.xmax + px, ymin: b.ymin - py, ymax: b.ymax + py }, 200)
            const pts = []
            for (const l of lines) { if (pts.length) pts.push(P(NaN, NaN)); pts.push(...l) }
            return { kind: 'curve', pts, implicit: true, f: g }
        }
        case 'conicPart': {
            const c = get(o.of)
            if (!isConic(c)) return null
            const i = o.idx ?? 0
            if (o.part === 'center') return c.shape === 'parabola' ? null : { kind: 'point', ...c.c }
            if (o.part === 'focus') { const f = K.foci(c)[i]; return f ? { kind: 'point', ...f } : null }
            if (o.part === 'vertex') { const f = K.vertices(c)[i]; return f ? { kind: 'point', ...f } : null }
            if (o.part === 'asymptote') return K.asymptotes(c)[i] ?? null
            if (o.part === 'directrix') return K.directrices(c)[i] ?? null
            if (o.part === 'majorAxis' || o.part === 'minorAxis') {
                const d = o.part === 'majorAxis' ? c.u : perp(c.u)
                return { kind: 'line', p: P(c.c.x, c.c.y), q: add(c.c, d) }
            }
            return null
        }
        case 'tangent': {
            const p = pt(o.point), c = get(o.circle)
            if (p && isConic(c)) return K.conicTangents(c, p)[o.idx ?? 0] ?? null
            if (!p || !isRound(c)) return null
            const d = dist(p, c.c)
            if (d < c.r - 1e-9) return null
            const base = Math.atan2(p.y - c.c.y, p.x - c.c.x)
            if (Math.abs(d - c.r) < 1e-9) {
                if ((o.idx ?? 0) > 0) return null
                return { kind: 'line', p: P(p.x, p.y), q: add(p, perp(norm(sub(p, c.c)))) }
            }
            const off = Math.acos(c.r / d) * ((o.idx ?? 0) ? -1 : 1)
            const t = add(c.c, mul(P(Math.cos(base + off), Math.sin(base + off)), c.r))
            return { kind: 'line', p: P(p.x, p.y), q: t }
        }
        case 'translate': case 'rotate': case 'reflect': case 'dilate': {
            const src = get(o.src)
            if (!src) return null
            let T, flips = false, k = 1
            if (o.type === 'translate') {
                const a = pt(o.a), b = pt(o.b)
                if (!a || !b) return null
                const d = sub(b, a)
                T = p => add(p, d)
            } else if (o.type === 'rotate') {
                const c = pt(o.center), ang = num(o.angle) * deg
                if (!c || !Number.isFinite(ang)) return null
                T = p => rot(p, c, ang)
            } else if (o.type === 'reflect') {
                const l = get(o.line)
                if (!isLinear(l)) return null
                const d = norm(sub(l.q, l.p))
                T = p => { const f = add(l.p, mul(d, dot(sub(p, l.p), d))); return sub(mul(f, 2), p) }
                flips = true
            } else {
                const c = pt(o.center)
                k = num(o.k)
                if (!c || !Number.isFinite(k)) return null
                T = p => add(c, mul(sub(p, c), k))
            }
            return transformVal(src, T, { flips, k, angle: o.type === 'rotate' ? num(o.angle) * deg : 0 })
        }
        case 'locus': return null // 由 Scene 单独计算（需要重复求值依赖链）
        case 'func': {
            const c = compile(o.expr)
            if (c.error) return null
            const lo = o.xmin !== '' && o.xmin != null ? num(o.xmin) : -Infinity
            const hi = o.xmax !== '' && o.xmax != null ? num(o.xmax) : Infinity
            const fn = c.fn
            const f = x => fn({ ...scope, x })
            return { kind: 'func', f, xmin: Number.isFinite(lo) ? lo : -Infinity, xmax: Number.isFinite(hi) ? hi : Infinity }
        }
        case 'derivative': {
            const g = get(o.of)
            if (g?.kind !== 'func') return null
            const h = 1e-5
            return { kind: 'func', f: x => (g.f(x + h) - g.f(x - h)) / (2 * h), xmin: g.xmin, xmax: g.xmax }
        }
        case 'param': case 'polar': {
            const t0 = num(o.tmin), t1 = num(o.tmax)
            if (!Number.isFinite(t0) || !Number.isFinite(t1) || t1 <= t0) return null
            const pts = []
            const N = 600
            if (o.type === 'param') {
                const fx = compile(o.xExpr), fy = compile(o.yExpr)
                if (fx.error || fy.error) return null
                for (let i = 0; i <= N; i++) {
                    const t = t0 + (t1 - t0) * i / N, s = { ...scope, t }
                    pts.push(P(fx.fn(s), fy.fn(s)))
                }
            } else {
                const fr = compile(o.rExpr)
                if (fr.error) return null
                for (let i = 0; i <= N; i++) {
                    const t = t0 + (t1 - t0) * i / N
                    const r = fr.fn({ ...scope, t, θ: t, theta: t })
                    pts.push(P(r * Math.cos(t), r * Math.sin(t)))
                }
            }
            return { kind: 'curve', pts }
        }
        case 'slider': return { kind: 'number', v: o.value }
        case 'calc': {
            const v = num(o.expr)
            return { kind: 'number', v }
        }
        case 'measure': return measure(o, get)
        case 'text': return { kind: 'text', text: interpolate(o.text, scope, o.digits ?? 2) }
    }
    return null
}

export function interpolate(text, scope, digits = 2) {
    return String(text ?? '').replace(/\{([^{}]+)\}/g, (_, src) => {
        const c = compile(src)
        return c.error ? '{?}' : fmt(c.fn(scope), digits)
    })
}

// “左边 = 右边” → g(x, y) = 左 − 右；没有等号时视为 表达式 = 0
export function splitEquation(src) {
    const parts = String(src ?? '').split(/(?<![<>=!≤≥≠])=(?!=)/)
    if (parts.length > 2) return null
    return parts.length === 2 ? `(${parts[0]}) - (${parts[1]})` : String(src)
}
export function equationFn(src, scope = {}) {
    const e = splitEquation(src)
    if (e == null) return null
    const c = compile(e)
    if (c.error) return null
    const s = { ...scope }
    return (x, y) => { s.x = x; s.y = y; return c.fn(s) }
}

// 对几何值做点变换
function transformVal(v, T, { flips, k, angle }) {
    switch (v.kind) {
        case 'point': return { kind: 'point', ...T(v) }
        case 'line': case 'segment': case 'ray': return { kind: v.kind, p: T(v.p), q: T(v.q) }
        case 'circle': return { kind: 'circle', c: T(v.c), r: v.r * Math.abs(k) }
        case 'arc': {
            const c = T(v.c)
            const s = T(add(v.c, P(Math.cos(v.a0) * v.r, Math.sin(v.a0) * v.r)))
            const e = T(add(v.c, P(Math.cos(v.a1) * v.r, Math.sin(v.a1) * v.r)))
            const ang = p => Math.atan2(p.y - c.y, p.x - c.x)
            const span = v.a1 - v.a0
            // 反射会改变方向：交换起止点
            const a0 = flips ? ang(e) : ang(s)
            return { kind: 'arc', c, r: v.r * Math.abs(k), a0, a1: a0 + span }
        }
        case 'polygon': return { kind: 'polygon', pts: v.pts.map(T) }
        case 'curve': return { kind: 'curve', pts: v.pts.map(T), closed: v.closed }
        case 'conic': {
            const c = T(v.c), e = sub(T(add(v.c, v.u)), c), s = len(e)
            return K.makeConic(v.shape, c, e, v.a * s, v.b * s, v.p * s)
        }
        default: return null
    }
}

export function circumcenter(a, b, c) {
    const d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
    if (Math.abs(d) < 1e-12) return null
    const a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
    return P((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d, (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
}

// ---------- 度量 ----------
export const MEASURES = {
    distance: { label: '距离', need: '两个点，或点与直线' },
    length: { label: '长度', need: '线段' },
    angle: { label: '角度', need: '三个点（顶点在中间）' },
    area: { label: '面积', need: '多边形或圆' },
    perimeter: { label: '周长', need: '多边形或圆' },
    radius: { label: '半径', need: '圆或圆弧' },
    arcLength: { label: '弧长', need: '圆弧' },
    arcAngle: { label: '弧度角', need: '圆弧' },
    slope: { label: '斜率', need: '直线、线段或射线' },
    coords: { label: '坐标', need: '点' },
    equation: { label: '方程', need: '直线、圆或圆锥曲线' },
    eccentricity: { label: '离心率', need: '圆锥曲线' },
    focal: { label: '焦距', need: '椭圆或双曲线' },
}

export function polygonArea(pts) {
    let s = 0
    for (let i = 0; i < pts.length; i++) s += cross(pts[i], pts[(i + 1) % pts.length])
    return Math.abs(s) / 2
}
const perimeterOf = pts => pts.reduce((s, p, i) => s + dist(p, pts[(i + 1) % pts.length]), 0)

function measure(o, get) {
    const vs = (o.of ?? []).map(get)
    if (vs.some(v => !v)) return null
    const [a, b, c] = vs
    const n = v => ({ kind: 'number', v })
    switch (o.m) {
        case 'distance':
            if (a.kind === 'point' && b?.kind === 'point') return n(dist(a, b))
            if (a.kind === 'point' && isLinear(b)) return n(distToLine(a, b))
            if (isLinear(a) && b?.kind === 'point') return n(distToLine(b, a))
            return null
        case 'length': return a.kind === 'segment' ? n(dist(a.p, a.q)) : a.kind === 'arc' ? n(a.r * (a.a1 - a.a0)) : null
        case 'angle': {
            if (vs.length !== 3 || vs.some(v => v.kind !== 'point')) return null
            const u = sub(a, b), w = sub(c, b)
            if (len(u) < EPS || len(w) < EPS) return null
            return { kind: 'number', v: Math.acos(Math.max(-1, Math.min(1, dot(u, w) / len(u) / len(w)))) / deg, unit: '°' }
        }
        case 'area':
            if (a.kind === 'polygon') return n(polygonArea(a.pts))
            if (a.kind === 'circle') return n(Math.PI * a.r * a.r)
            if (a.kind === 'arc') return n(0.5 * a.r * a.r * (a.a1 - a.a0))
            if (isConic(a) && a.shape === 'ellipse') return n(Math.PI * a.a * a.b)
            return null
        case 'perimeter':
            if (a.kind === 'polygon') return n(perimeterOf(a.pts))
            if (a.kind === 'circle') return n(TAU * a.r)
            if (isConic(a) && a.shape === 'ellipse') {
                // Ramanujan 近似
                const h3 = 3 * ((a.a - a.b) / (a.a + a.b)) ** 2
                return n(Math.PI * (a.a + a.b) * (1 + h3 / (10 + Math.sqrt(4 - h3))))
            }
            return null
        case 'eccentricity': return isConic(a) ? n(K.eccentricity(a)) : a.kind === 'circle' ? n(0) : null
        case 'focal': {
            if (!isConic(a) || a.shape === 'parabola') return null
            const [f1, f2] = K.foci(a)
            return n(dist(f1, f2))
        }
        case 'radius': return isRound(a) ? n(a.r) : null
        case 'arcLength': return a.kind === 'arc' ? n(a.r * (a.a1 - a.a0)) : null
        case 'arcAngle': return a.kind === 'arc' ? { kind: 'number', v: (a.a1 - a.a0) / deg, unit: '°' } : null
        case 'slope': {
            if (!isLinear(a)) return null
            const d = sub(a.q, a.p)
            return n(Math.abs(d.x) < 1e-12 ? NaN : d.y / d.x)
        }
        case 'coords': return a.kind === 'point' ? { kind: 'number', v: a.x, v2: a.y, text: `(${fmt(a.x, o.digits ?? 2)}, ${fmt(a.y, o.digits ?? 2)})` } : null
        case 'equation': return { kind: 'number', v: NaN, text: equationOf(a, o.digits ?? 2) }
    }
    return null
}

export function equationOf(v, d) {
    const f = x => fmt(x, d)
    const sgn = (x, first) => (x < 0 ? (first ? '−' : ' − ') : first ? '' : ' + ') + f(Math.abs(x))
    if (isLinear(v)) {
        const A = v.q.y - v.p.y, B = v.p.x - v.q.x, C = -(A * v.p.x + B * v.p.y)
        if (Math.abs(B) < 1e-12) return `x = ${f(-C / A)}`
        const k = -A / B, b = -C / B
        return `y = ${Math.abs(k) < 1e-12 ? '' : (k === 1 ? '' : k === -1 ? '−' : f(k)) + 'x'}${Math.abs(b) < 1e-12 && Math.abs(k) >= 1e-12 ? '' : Math.abs(k) < 1e-12 ? f(b) : sgn(b, false)}`
    }
    if (isRound(v)) {
        const part = (n, c) => Math.abs(c) < 1e-12 ? n + '²' : `(${n}${c > 0 ? ' − ' : ' + '}${f(Math.abs(c))})²`
        return `${part('x', v.c.x)} + ${part('y', v.c.y)} = ${f(v.r * v.r)}`
    }
    if (v.kind === 'point') return `(${f(v.x)}, ${f(v.y)})`
    if (isConic(v)) return K.conicEquation(v, f)
    return '—'
}

export function distToLine(p, l) {
    const d = sub(l.q, l.p)
    return Math.abs(cross(d, sub(p, l.p))) / len(d)
}

// ---------- 路径参数 ----------
// 路径上的点：直线类 t 为 p→q 的比例；圆 t 为角度（弧度）；圆弧 t ∈ [0,1]；
// 多边形 t ∈ [0, n)（第 i 条边上的比例）；函数 t 为 x；曲线 t ∈ [0,1]
export function pointAt(v, t) {
    switch (v.kind) {
        case 'line': return lerp(v.p, v.q, t)
        case 'ray': return lerp(v.p, v.q, Math.max(0, t))
        case 'segment': return lerp(v.p, v.q, Math.max(0, Math.min(1, t)))
        case 'circle': return P(v.c.x + v.r * Math.cos(t), v.c.y + v.r * Math.sin(t))
        case 'arc': {
            const a = v.a0 + (v.a1 - v.a0) * Math.max(0, Math.min(1, t))
            return P(v.c.x + v.r * Math.cos(a), v.c.y + v.r * Math.sin(a))
        }
        case 'polygon': {
            const n = v.pts.length
            const tt = ((t % n) + n) % n
            const i = Math.floor(tt)
            return lerp(v.pts[i], v.pts[(i + 1) % n], tt - i)
        }
        case 'func': {
            const x = Math.max(v.xmin, Math.min(v.xmax, t))
            return P(x, v.f(x))
        }
        case 'conic': return K.conicPoint(v, t)
        case 'curve': {
            const n = v.pts.length - 1
            if (n < 1) return v.pts[0] ?? null
            const tt = Math.max(0, Math.min(1, t)) * n
            const i = Math.min(n - 1, Math.floor(tt))
            return lerp(v.pts[i], v.pts[i + 1], tt - i)
        }
    }
    return null
}

// 把点 p 投影到路径上，返回参数 t
export function projectParam(v, p) {
    switch (v.kind) {
        case 'line': case 'ray': case 'segment': {
            const d = sub(v.q, v.p)
            let t = dot(sub(p, v.p), d) / dot(d, d)
            if (v.kind === 'ray') t = Math.max(0, t)
            if (v.kind === 'segment') t = Math.max(0, Math.min(1, t))
            return t
        }
        case 'circle': return Math.atan2(p.y - v.c.y, p.x - v.c.x)
        case 'arc': {
            const a = normAng(Math.atan2(p.y - v.c.y, p.x - v.c.x) - v.a0)
            const span = v.a1 - v.a0
            if (a <= span) return a / span
            // 弧外：取较近的端点
            return a - span < TAU - a ? 1 : 0
        }
        case 'polygon': {
            let best = Infinity, bt = 0
            const n = v.pts.length
            for (let i = 0; i < n; i++) {
                const a = v.pts[i], b = v.pts[(i + 1) % n], d = sub(b, a)
                const dd = dot(d, d)
                const s = dd < EPS ? 0 : Math.max(0, Math.min(1, dot(sub(p, a), d) / dd))
                const q = lerp(a, b, s), e = dist(p, q)
                if (e < best) { best = e; bt = i + s }
            }
            return bt
        }
        case 'func': return Math.max(v.xmin, Math.min(v.xmax, p.x))
        case 'conic': return K.conicProject(v, p)
        case 'curve': {
            let best = Infinity, bt = 0
            const n = v.pts.length - 1
            for (let i = 0; i < n; i++) {
                const a = v.pts[i], b = v.pts[i + 1]
                if (!finite(a) || !finite(b)) continue
                const d = sub(b, a), dd = dot(d, d)
                const s = dd < EPS ? 0 : Math.max(0, Math.min(1, dot(sub(p, a), d) / dd))
                const e = dist(p, lerp(a, b, s))
                if (e < best) { best = e; bt = (i + s) / n }
            }
            return bt
        }
    }
    return 0
}

// 路径参数的自然范围（用于动画和轨迹采样）
export function paramRange(v, view) {
    switch (v.kind) {
        case 'segment': case 'arc': case 'curve': return [0, 1]
        case 'circle': return [-Math.PI, Math.PI]
        case 'conic': return K.conicRange(v, view)
        case 'polygon': return [0, v.pts.length]
        case 'func': return [Math.max(v.xmin, view.xmin), Math.min(v.xmax, view.xmax)]
        case 'line': case 'ray': {
            // 视口四角在直线上的投影范围
            const d = sub(v.q, v.p), dd = dot(d, d)
            const ts = [P(view.xmin, view.ymin), P(view.xmax, view.ymin), P(view.xmin, view.ymax), P(view.xmax, view.ymax)].map(c => dot(sub(c, v.p), d) / dd)
            return [v.kind === 'ray' ? 0 : Math.min(...ts), Math.max(...ts)]
        }
    }
    return [0, 1]
}

// ---------- 交点 ----------
// 返回点数组；索引稳定（对应完整直线 / 圆上的交点），ok=false 表示不在线段 / 圆弧范围内
export function intersections(a, b) {
    if (isLinear(a) && isLinear(b)) return lineLine(a, b)
    if (isLinear(a) && isConic(b)) return lineConic(a, b)
    if (isConic(a) && isLinear(b)) return lineConic(b, a)
    // 圆 / 圆锥曲线之间：先折线求交，再用牛顿法精确化
    const ka = coefOfVal(a), kb = coefOfVal(b)
    if (ka && kb && (isConic(a) || isConic(b))) {
        const arcOk = (v, p) => v.kind !== 'arc' || onArc(v, Math.atan2(p.y - v.c.y, p.x - v.c.x))
        const out = []
        for (const p0 of polyPoly(polyline(a), polyline(b))) {
            const p = refine2(ka, kb, p0)
            if (!out.some(q => dist(q, p) < 1e-7)) out.push({ ...p, ok: arcOk(a, p) && arcOk(b, p) })
        }
        return out
    }
    if (isLinear(a) && isRound(b)) return lineCircle(a, b)
    if (isRound(a) && isLinear(b)) return lineCircle(b, a)
    if (isRound(a) && isRound(b)) return circleCircle(a, b)
    // 其余组合：把两者都折线化后求交
    const pa = polyline(a), pb = polyline(b)
    if (!pa || !pb) return []
    return polyPoly(pa, pb)
}

function lineLine(a, b) {
    const d1 = sub(a.q, a.p), d2 = sub(b.q, b.p)
    const den = cross(d1, d2)
    if (Math.abs(den) < 1e-12) return []
    const w = sub(b.p, a.p)
    const t = cross(w, d2) / den, u = cross(w, d1) / den
    const p = add(a.p, mul(d1, t))
    return [{ ...p, ok: inRange(a, t) && inRange(b, u) }]
}

function lineConic(l, c) {
    const d = sub(l.q, l.p)
    return K.lineConicT(l, c.coef).map(t => ({ ...add(l.p, mul(d, t)), ok: inRange(l, t) }))
}

// 圆与圆锥曲线的一般方程系数
function coefOfVal(v) {
    if (isConic(v)) return v.coef
    if (v.kind === 'circle' || v.kind === 'arc') return [1, 0, 1, -2 * v.c.x, -2 * v.c.y, v.c.x * v.c.x + v.c.y * v.c.y - v.r * v.r]
    return null
}
// 二元牛顿迭代：同时满足两条曲线的方程
function refine2(k1, k2, p0) {
    let { x, y } = p0
    const grad = k => [2 * k[0] * x + k[1] * y + k[3], k[1] * x + 2 * k[2] * y + k[4]]
    for (let i = 0; i < 12; i++) {
        const f1 = K.evalCoef(k1, x, y), f2 = K.evalCoef(k2, x, y)
        const [a, b] = grad(k1), [c, d] = grad(k2)
        const det = a * d - b * c
        if (Math.abs(det) < 1e-14) break
        const dx = (f1 * d - f2 * b) / det, dy = (a * f2 - c * f1) / det
        x -= dx; y -= dy
        if (Math.abs(dx) + Math.abs(dy) < 1e-13) break
    }
    return Number.isFinite(x) && Number.isFinite(y) && dist(P(x, y), p0) < 0.5 ? P(x, y) : p0
}

function lineCircle(l, c) {
    const d = sub(l.q, l.p), f = sub(l.p, c.c)
    const A = dot(d, d), B = 2 * dot(f, d), C = dot(f, f) - c.r * c.r
    let disc = B * B - 4 * A * C
    if (disc < -1e-9 * A) return []
    disc = Math.max(0, disc)
    const s = Math.sqrt(disc)
    return [(-B - s) / (2 * A), (-B + s) / (2 * A)].map(t => {
        const p = add(l.p, mul(d, t))
        return { ...p, ok: inRange(l, t) && onArc(c, Math.atan2(p.y - c.c.y, p.x - c.c.x)) }
    })
}

function circleCircle(a, b) {
    const d = dist(a.c, b.c)
    if (d < EPS || d > a.r + b.r + 1e-9 || d < Math.abs(a.r - b.r) - 1e-9) return []
    const x = (d * d + a.r * a.r - b.r * b.r) / (2 * d)
    const h = Math.sqrt(Math.max(0, a.r * a.r - x * x))
    const e = norm(sub(b.c, a.c)), m = add(a.c, mul(e, x)), n = perp(e)
    return [add(m, mul(n, h)), sub(m, mul(n, h))].map(p => ({
        ...p,
        ok: onArc(a, Math.atan2(p.y - a.c.y, p.x - a.c.x)) && onArc(b, Math.atan2(p.y - b.c.y, p.x - b.c.x)),
    }))
}

// 折线化：返回 [[p0, p1, ...], ...]（多段）
function polyline(v) {
    const LIM = 1e4
    switch (v.kind) {
        case 'segment': return [[v.p, v.q]]
        case 'ray': return [[v.p, add(v.p, mul(norm(sub(v.q, v.p)), LIM))]]
        case 'line': { const d = mul(norm(sub(v.q, v.p)), LIM); return [[sub(v.p, d), add(v.p, d)]] }
        case 'circle': case 'arc': {
            const a0 = v.kind === 'arc' ? v.a0 : 0, a1 = v.kind === 'arc' ? v.a1 : TAU
            const N = 180, pts = []
            for (let i = 0; i <= N; i++) { const a = a0 + (a1 - a0) * i / N; pts.push(P(v.c.x + v.r * Math.cos(a), v.c.y + v.r * Math.sin(a))) }
            return [pts]
        }
        case 'polygon': return [[...v.pts, v.pts[0]]]
        case 'conic': return K.conicSamples(v, 80)
        case 'curve': return splitFinite(v.pts)
        case 'func': {
            const lo = Math.max(v.xmin, -50), hi = Math.min(v.xmax, 50), N = 2000, pts = []
            for (let i = 0; i <= N; i++) { const x = lo + (hi - lo) * i / N; pts.push(P(x, v.f(x))) }
            return splitFinite(pts)
        }
    }
    return null
}
function splitFinite(pts) {
    const out = []
    let cur = []
    for (const p of pts) {
        if (finite(p) && Math.abs(p.y) < 1e6) cur.push(p)
        else { if (cur.length > 1) out.push(cur); cur = [] }
    }
    if (cur.length > 1) out.push(cur)
    return out
}
function polyPoly(A, B) {
    const out = []
    for (const pa of A) for (let i = 0; i < pa.length - 1; i++) {
        const a1 = pa[i], a2 = pa[i + 1]
        for (const pb of B) for (let j = 0; j < pb.length - 1; j++) {
            const b1 = pb[j], b2 = pb[j + 1]
            const d1 = sub(a2, a1), d2 = sub(b2, b1), den = cross(d1, d2)
            if (Math.abs(den) < 1e-14) continue
            const w = sub(b1, a1), t = cross(w, d2) / den, u = cross(w, d1) / den
            if (t >= 0 && t < 1 && u >= 0 && u < 1) {
                const p = add(a1, mul(d1, t))
                if (!out.some(q => dist(q, p) < 1e-6)) out.push(p)
            }
        }
    }
    return out
}

// ---------- 命名 ----------
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
export function nextName(objects, kind) {
    const used = new Set(objects.map(o => o.name))
    const pick = (seq, fallback) => {
        for (const n of seq) if (!used.has(n)) return n
        for (let i = 1; ; i++) { const n = fallback(i); if (!used.has(n)) return n }
    }
    if (kind === 'point') return pick([...LETTERS], i => `${LETTERS[(i - 1) % 26]}${Math.floor((i - 1) / 26) + 1}`)
    if (kind === 'linear') return pick([...'abcdeghjklmnopqrstuvwz'], i => `l${i}`)
    if (kind === 'circle') return pick([], i => `c${i}`)
    if (kind === 'polygon') return pick([], i => `poly${i}`)
    if (kind === 'func') return pick(['f', 'g', 'h', 'p', 'q', 'u', 'v', 'w'], i => `f${i}`)
    if (kind === 'curve') return pick([], i => `曲线${i}`)
    if (kind === 'conic') return pick([], i => `c${i}`)
    if (kind === 'slider') return pick(['a', 'b', 'k', 'm', 'n', 's', 'r', 'd'], i => `a${i}`)
    if (kind === 'measure') return pick([], i => `m${i}`)
    if (kind === 'calc') return pick([], i => `v${i}`)
    if (kind === 'text') return pick([], i => `文本${i}`)
    return pick([], i => `obj${i}`)
}

// 对象的“几何类别”，用于命名与默认样式
export function categoryOf(o, v) {
    if (['point', 'pointOn', 'intersect', 'midpoint'].includes(o.type)) return 'point'
    if (['func', 'derivative'].includes(o.type)) return 'func'
    if (['param', 'polar', 'locus'].includes(o.type)) return 'curve'
    if (o.type === 'conicPart') return v?.kind === 'point' ? 'point' : 'linear'
    if (o.type === 'equation') return v?.kind === 'curve' || !v ? 'curve' : isLinear(v) ? 'linear' : v.kind === 'circle' ? 'circle' : 'conic'
    if (isConic(v) || ['ellipse', 'hyperbola', 'ellipseC', 'hyperbolaC', 'parabola', 'conic5', 'conicStd'].includes(o.type)) return 'conic'
    if (o.type === 'slider') return 'slider'
    if (o.type === 'measure') return 'measure'
    if (o.type === 'calc') return 'calc'
    if (o.type === 'text') return 'text'
    const k = v?.kind
    if (k === 'point') return 'point'
    if (isLinear(v) || ['segment', 'ray', 'line', 'parallel', 'perpendicular', 'perpBisector', 'angleBisector', 'tangent'].includes(o.type)) return 'linear'
    if (isRound(v) || ['circle', 'circleR', 'circle3', 'arc', 'arc3'].includes(o.type)) return 'circle'
    if (k === 'polygon' || ['polygon', 'regular'].includes(o.type)) return 'polygon'
    if (k === 'curve') return 'curve'
    return 'other'
}
