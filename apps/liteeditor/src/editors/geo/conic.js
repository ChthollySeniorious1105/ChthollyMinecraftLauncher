// 圆锥曲线与隐函数曲线
// 圆锥曲线值：{ kind: 'conic', shape: 'ellipse' | 'hyperbola' | 'parabola', c, u, a, b, p, coef: [A, B, C, D, E, F] }
//   椭圆 / 双曲线：c 为中心，u 为长轴（实轴）方向的单位向量，a、b 为半轴长
//   抛物线：c 为顶点，u 为开口方向，p 为焦准距（局部方程 y'² = 2p·x'）
//   coef：一般方程 Ax² + Bxy + Cy² + Dx + Ey + F = 0
// 隐函数曲线值：{ kind: 'implicit', f(x, y), segs: [[p, q], ...] }（segs 为当前视口内的折线段）

const TAU = Math.PI * 2
const P = (x, y) => ({ x, y })
const perp = a => P(-a.y, a.x)
const hyp = Math.hypot

// 局部坐标 → 世界坐标
export const fromLocal = (v, x, y) => { const w = perp(v.u); return P(v.c.x + v.u.x * x + w.x * y, v.c.y + v.u.y * x + w.y * y) }
export const toLocal = (v, p) => { const dx = p.x - v.c.x, dy = p.y - v.c.y, w = perp(v.u); return P(dx * v.u.x + dy * v.u.y, dx * w.x + dy * w.y) }

// ---------- 构造 ----------
export function makeConic(shape, c, u, a, b, p) {
    const l = hyp(u.x, u.y)
    if (!(l > 1e-12)) return null
    const v = { kind: 'conic', shape, c: P(c.x, c.y), u: P(u.x / l, u.y / l), a, b, p }
    if (shape === 'parabola') { if (!(p > 1e-12) || !Number.isFinite(p)) return null }
    else if (!(a > 1e-12 && b > 1e-12) || !Number.isFinite(a) || !Number.isFinite(b)) return null
    v.coef = coefOf(v)
    return v
}

// 由两个焦点与曲线上一点确定的椭圆 / 双曲线
export function fromFoci(shape, f1, f2, pt) {
    const c = P((f1.x + f2.x) / 2, (f1.y + f2.y) / 2)
    const fc = hyp(f2.x - f1.x, f2.y - f1.y) / 2
    const d1 = hyp(pt.x - f1.x, pt.y - f1.y), d2 = hyp(pt.x - f2.x, pt.y - f2.y)
    let u = P(f2.x - f1.x, f2.y - f1.y)
    if (fc < 1e-12) u = P(1, 0)
    if (shape === 'ellipse') {
        const a = (d1 + d2) / 2
        return makeConic('ellipse', c, u, a, Math.sqrt(Math.max(0, a * a - fc * fc)))
    }
    const a = Math.abs(d1 - d2) / 2
    if (a < 1e-12 || a >= fc) return null
    return makeConic('hyperbola', c, u, a, Math.sqrt(fc * fc - a * a))
}

// 由中心、顶点与曲线上一点确定
export function fromCenter(shape, c, vtx, pt) {
    const u = P(vtx.x - c.x, vtx.y - c.y)
    const a = hyp(u.x, u.y)
    if (a < 1e-12) return null
    const q = toLocal({ c, u: P(u.x / a, u.y / a) }, pt)
    const t = (q.x / a) ** 2
    if (shape === 'ellipse') {
        if (t >= 1 - 1e-12) return null
        return makeConic('ellipse', c, u, a, Math.abs(q.y) / Math.sqrt(1 - t))
    }
    if (t <= 1 + 1e-12) return null
    return makeConic('hyperbola', c, u, a, Math.abs(q.y) / Math.sqrt(t - 1))
}

// 由焦点与准线确定的抛物线
export function fromFocusDirectrix(f, line) {
    const d = P(line.q.x - line.p.x, line.q.y - line.p.y)
    const l = hyp(d.x, d.y)
    if (l < 1e-12) return null
    const n = perp(P(d.x / l, d.y / l))
    let s = (f.x - line.p.x) * n.x + (f.y - line.p.y) * n.y   // 焦点到准线的有向距离
    if (Math.abs(s) < 1e-12) return null
    const u = s > 0 ? n : P(-n.x, -n.y)
    s = Math.abs(s)
    return makeConic('parabola', P(f.x - u.x * s / 2, f.y - u.y * s / 2), u, 0, 0, s)
}

// 一般方程系数（按局部方程展开）
function coefOf(v) {
    const w = perp(v.u)
    // x' = u·(p − c)，y' = w·(p − c)，写成 [kx, ky, k0]
    const X = [v.u.x, v.u.y, -(v.u.x * v.c.x + v.u.y * v.c.y)]
    const Y = [w.x, w.y, -(w.x * v.c.x + w.y * v.c.y)]
    const out = [0, 0, 0, 0, 0, 0]
    const sq = (L, k) => { out[0] += k * L[0] * L[0]; out[1] += k * 2 * L[0] * L[1]; out[2] += k * L[1] * L[1]; out[3] += k * 2 * L[0] * L[2]; out[4] += k * 2 * L[1] * L[2]; out[5] += k * L[2] * L[2] }
    const lin = (L, k) => { out[3] += k * L[0]; out[4] += k * L[1]; out[5] += k * L[2] }
    if (v.shape === 'ellipse') { sq(X, 1 / v.a ** 2); sq(Y, 1 / v.b ** 2); out[5] -= 1 }
    else if (v.shape === 'hyperbola') { sq(X, 1 / v.a ** 2); sq(Y, -1 / v.b ** 2); out[5] -= 1 }
    else { sq(Y, 1); lin(X, -2 * v.p) }
    return out
}

export const evalCoef = (k, x, y) => k[0] * x * x + k[1] * x * y + k[2] * y * y + k[3] * x + k[4] * y + k[5]

// 一般方程 → 几何值：圆锥曲线 / 圆 / 直线；退化（点、两条直线）返回 null
export function fromCoef(k) {
    let [A, B, C, D, E, F] = k
    const scale = Math.max(Math.abs(A), Math.abs(B), Math.abs(C))
    const lscale = Math.max(Math.abs(D), Math.abs(E))
    if (scale < 1e-12 * Math.max(1, lscale, Math.abs(F))) {
        // 一次方程：直线 Dx + Ey + F = 0
        if (lscale < 1e-14) return null
        const p0 = Math.abs(E) > Math.abs(D) ? P(0, -F / E) : P(-F / D, 0)
        return { kind: 'line', p: p0, q: P(p0.x - E, p0.y + D) }
    }
    // 统一缩放，避免数值过小
    A /= scale; B /= scale; C /= scale; D /= scale; E /= scale; F /= scale
    const th = 0.5 * Math.atan2(B, A - C)
    const c = Math.cos(th), s = Math.sin(th)
    const A1 = A * c * c + B * c * s + C * s * s
    const C1 = A * s * s - B * c * s + C * c * c
    const D1 = D * c + E * s, E1 = -D * s + E * c
    const rot = (x, y) => P(x * c - y * s, x * s + y * c)
    const eps = 1e-9
    if (Math.abs(A1) > eps && Math.abs(C1) > eps) {
        const x0 = -D1 / (2 * A1), y0 = -E1 / (2 * C1)
        const K = A1 * x0 * x0 + C1 * y0 * y0 - F
        if (Math.abs(K) < 1e-12) return null
        const a2 = K / A1, b2 = K / C1
        const center = rot(x0, y0)
        if (a2 > 0 && b2 > 0) {
            if (Math.abs(a2 - b2) < 1e-10 * Math.max(a2, b2)) return { kind: 'circle', c: center, r: Math.sqrt(a2) }
            return a2 >= b2 ? makeConic('ellipse', center, rot(1, 0), Math.sqrt(a2), Math.sqrt(b2)) : makeConic('ellipse', center, rot(0, 1), Math.sqrt(b2), Math.sqrt(a2))
        }
        if (a2 < 0 && b2 < 0) return null
        return a2 > 0 ? makeConic('hyperbola', center, rot(1, 0), Math.sqrt(a2), Math.sqrt(-b2)) : makeConic('hyperbola', center, rot(0, 1), Math.sqrt(b2), Math.sqrt(-a2))
    }
    // 抛物线：只有一个二次项
    if (Math.abs(A1) <= eps && Math.abs(C1) <= eps) return null
    if (Math.abs(A1) <= eps) {
        // C1 y'² + D1 x' + E1 y' + F = 0
        if (Math.abs(D1) < 1e-12) return null
        const y0 = -E1 / (2 * C1)
        const xv = (C1 * y0 * y0 - F) / D1
        const k2 = -D1 / C1       // (y' − y0)² = k2 (x' − xv)
        return makeConic('parabola', rot(xv, y0), rot(Math.sign(k2), 0), 0, 0, Math.abs(k2) / 2)
    }
    if (Math.abs(E1) < 1e-12) return null
    const x0 = -D1 / (2 * A1)
    const yv = (A1 * x0 * x0 - F) / E1
    const k2 = -E1 / A1
    return makeConic('parabola', rot(x0, yv), rot(0, Math.sign(k2)), 0, 0, Math.abs(k2) / 2)
}

// 五点确定的圆锥曲线：返回系数（零空间）
export function coefThrough(pts) {
    const rows = pts.map(p => [p.x * p.x, p.x * p.y, p.y * p.y, p.x, p.y, 1])
    const det = m => {
        const a = m.map(r => [...r]), n = a.length
        let d = 1
        for (let i = 0; i < n; i++) {
            let piv = i
            for (let r = i + 1; r < n; r++) if (Math.abs(a[r][i]) > Math.abs(a[piv][i])) piv = r
            if (Math.abs(a[piv][i]) < 1e-300) return 0
            if (piv !== i) { [a[piv], a[i]] = [a[i], a[piv]]; d = -d }
            d *= a[i][i]
            for (let r = i + 1; r < n; r++) { const f = a[r][i] / a[i][i]; for (let c = i; c < n; c++) a[r][c] -= f * a[i][c] }
        }
        return d
    }
    const k = [0, 1, 2, 3, 4, 5].map(j => (j % 2 ? -1 : 1) * det(rows.map(r => r.filter((_, c) => c !== j))))
    const m = Math.max(...k.map(Math.abs))
    return m < 1e-300 ? null : k.map(x => x / m)
}

// 用数值采样判断 g(x, y) 是否为二次（及以下）多项式，是则返回系数
export function quadraticCoef(g) {
    const F = g(0, 0)
    const gx1 = g(1, 0), gx2 = g(-1, 0), gy1 = g(0, 1), gy2 = g(0, -1), gxy = g(1, 1)
    const A = (gx1 + gx2) / 2 - F, D = (gx1 - gx2) / 2
    const C = (gy1 + gy2) / 2 - F, E = (gy1 - gy2) / 2
    const B = gxy - A - C - D - E - F
    const k = [A, B, C, D, E, F]
    if (!k.every(Number.isFinite)) return null
    const scale = Math.max(1, ...k.map(Math.abs))
    for (const [x, y] of [[2, -3], [-1.5, 2.5], [0.7, 1.9], [3.3, 4.1], [-2.6, -0.8], [5, 0.5]]) {
        const v = g(x, y)
        if (!Number.isFinite(v) || Math.abs(v - evalCoef(k, x, y)) > 1e-7 * scale * (1 + x * x + y * y)) return null
    }
    return k
}

// ---------- 参数化 ----------
// 椭圆：t 为离心角 ∈ [−π, π]；双曲线：x' = a·sec t，y' = b·tan t（t ∈ (−π/2, π/2) 为右支）；抛物线：t 为 y'
export function conicPoint(v, t) {
    if (v.shape === 'ellipse') return fromLocal(v, v.a * Math.cos(t), v.b * Math.sin(t))
    if (v.shape === 'hyperbola') {
        const c = Math.cos(t)
        if (Math.abs(c) < 1e-9) return null
        return fromLocal(v, v.a / c, v.b * Math.tan(t))
    }
    return fromLocal(v, t * t / (2 * v.p), t)
}

export function conicProject(v, p) {
    const q = toLocal(v, p)
    let t0, span
    if (v.shape === 'ellipse') { t0 = Math.atan2(q.y / v.b, q.x / v.a); span = 0.6 }
    else if (v.shape === 'hyperbola') {
        t0 = Math.atan(q.y / v.b)
        // 左支：cos t < 0，tan 相同 → 加减 π
        if (q.x < 0) t0 += t0 <= 0 ? Math.PI : -Math.PI
        span = 0.3
    } else { t0 = q.y; span = Math.max(1, Math.abs(q.y)) * 0.5 }
    // 局部搜索（距离的平方）
    const d = t => { const r = conicPoint(v, t); return r ? (r.x - p.x) ** 2 + (r.y - p.y) ** 2 : Infinity }
    let best = t0, bd = d(t0)
    for (let round = 0; round < 4; round++) {
        const n = 24
        for (let i = -n; i <= n; i++) {
            const t = best + span * i / n
            if (v.shape === 'hyperbola' && Math.abs(Math.cos(t)) < 1e-6) continue
            const e = d(t)
            if (e < bd) { bd = e; best = t }
        }
        span /= 12
    }
    if (v.shape !== 'parabola') best = Math.atan2(Math.sin(best), Math.cos(best))
    return best
}

// 参数范围：用于动画与轨迹采样
export function conicRange(v, view) {
    if (v.shape !== 'parabola') return [-Math.PI, Math.PI]
    const R = view ? hyp(view.xmax - view.xmin, view.ymax - view.ymin) + hyp((view.xmin + view.xmax) / 2 - v.c.x, (view.ymin + view.ymax) / 2 - v.c.y) : 50
    const S = Math.sqrt(2 * v.p * R) + 1
    return [-S, S]
}

// 世界坐标采样：R 为需要覆盖的半径（以 c 为中心）
export function conicSamples(v, R = 60) {
    const out = []
    if (v.shape === 'ellipse') {
        const pts = []
        const N = 240
        for (let i = 0; i <= N; i++) pts.push(conicPoint(v, -Math.PI + TAU * i / N))
        out.push(pts)
    } else if (v.shape === 'hyperbola') {
        const S = Math.asinh(R / Math.min(v.a, v.b)) + 0.5
        for (const br of [1, -1]) {
            const pts = []
            const N = 320
            for (let i = 0; i <= N; i++) {
                const s = -S + 2 * S * i / N
                pts.push(fromLocal(v, br * v.a * Math.cosh(s), v.b * Math.sinh(s)))
            }
            out.push(pts)
        }
    } else {
        const S = Math.sqrt(2 * v.p * R) + R * 0.1 + 1
        const pts = []
        const N = 400
        // 顶点附近更密
        for (let i = 0; i <= N; i++) { const w = -1 + 2 * i / N; const s = S * Math.sign(w) * w * w; pts.push(conicPoint(v, s)) }
        out.push(pts)
    }
    return out
}

// 焦点、渐近线、准线
export function foci(v) {
    if (v.shape === 'parabola') return [fromLocal(v, v.p / 2, 0)]
    const fc = v.shape === 'ellipse' ? Math.sqrt(Math.max(0, v.a * v.a - v.b * v.b)) : Math.sqrt(v.a * v.a + v.b * v.b)
    return [fromLocal(v, -fc, 0), fromLocal(v, fc, 0)]
}
export function asymptotes(v) {
    if (v.shape !== 'hyperbola') return []
    return [1, -1].map(k => ({ kind: 'line', p: P(v.c.x, v.c.y), q: fromLocal(v, v.a, k * v.b) }))
}
export function directrices(v) {
    const w = perp(v.u)
    const mk = x => { const p = fromLocal(v, x, 0); return { kind: 'line', p, q: P(p.x + w.x, p.y + w.y) } }
    if (v.shape === 'parabola') return [mk(-v.p / 2)]
    const fc = v.shape === 'ellipse' ? Math.sqrt(Math.max(0, v.a * v.a - v.b * v.b)) : Math.sqrt(v.a * v.a + v.b * v.b)
    if (fc < 1e-12) return []
    return [mk(-v.a * v.a / fc), mk(v.a * v.a / fc)]
}
export function vertices(v) {
    if (v.shape === 'parabola') return [P(v.c.x, v.c.y)]
    const r = [fromLocal(v, -v.a, 0), fromLocal(v, v.a, 0)]
    if (v.shape === 'ellipse') r.push(fromLocal(v, 0, -v.b), fromLocal(v, 0, v.b))
    return r
}
export function eccentricity(v) {
    if (v.shape === 'parabola') return 1
    return v.shape === 'ellipse' ? Math.sqrt(Math.max(0, 1 - (v.b / v.a) ** 2)) : Math.sqrt(1 + (v.b / v.a) ** 2)
}

// 直线与圆锥曲线的交点（参数 t 沿 l.p → l.q）
export function lineConicT(l, k) {
    const d = P(l.q.x - l.p.x, l.q.y - l.p.y), x0 = l.p.x, y0 = l.p.y
    const a = k[0] * d.x * d.x + k[1] * d.x * d.y + k[2] * d.y * d.y
    const b = 2 * k[0] * x0 * d.x + k[1] * (x0 * d.y + y0 * d.x) + 2 * k[2] * y0 * d.y + k[3] * d.x + k[4] * d.y
    const c = evalCoef(k, x0, y0)
    const sc = Math.max(Math.abs(a), Math.abs(b), Math.abs(c), 1e-300)
    if (Math.abs(a) < 1e-12 * sc) return Math.abs(b) < 1e-14 * sc ? [] : [-c / b]
    let disc = b * b - 4 * a * c
    if (disc < -1e-10 * b * b - 1e-12 * sc * sc) return []
    disc = Math.sqrt(Math.max(0, disc))
    const t1 = (-b - disc) / (2 * a), t2 = (-b + disc) / (2 * a)
    return t1 <= t2 ? [t1, t2] : [t2, t1]
}

// 过点 p 的切线（极线法）：返回直线数组
export function conicTangents(v, p) {
    const k = v.coef
    const [A, B, C, D, E, F] = k
    const g = evalCoef(k, p.x, p.y)
    const l1 = A * p.x + B / 2 * p.y + D / 2, l2 = B / 2 * p.x + C * p.y + E / 2, l3 = D / 2 * p.x + E / 2 * p.y + F
    const gl = hyp(l1, l2)
    if (gl < 1e-14) return []
    const dir = P(-l2 / gl, l1 / gl)
    // 点在曲线上：切线就是极线
    if (Math.abs(g) < 1e-9 * Math.max(1, gl * (1 + hyp(p.x, p.y)))) return [{ kind: 'line', p: P(p.x, p.y), q: P(p.x + dir.x, p.y + dir.y) }]
    const p0 = Math.abs(l2) > Math.abs(l1) ? P(0, -l3 / l2) : P(-l3 / l1, 0)
    const polar = { p: p0, q: P(p0.x + dir.x, p0.y + dir.y) }
    return lineConicT(polar, k).map(t => {
        const q = P(p0.x + dir.x * t, p0.y + dir.y * t)
        return hyp(q.x - p.x, q.y - p.y) < 1e-12 ? null : { kind: 'line', p: P(p.x, p.y), q }
    }).filter(Boolean)
}

// ---------- 隐函数曲线：视口内的 marching squares ----------
export function implicitSegments(f, box, cols = 160) {
    const w = box.xmax - box.xmin, hgt = box.ymax - box.ymin
    if (!(w > 0 && hgt > 0)) return []
    const nx = cols, ny = Math.max(8, Math.round(cols * hgt / w))
    const dx = w / nx, dy = hgt / ny
    const vals = new Float64Array((nx + 1) * (ny + 1))
    for (let j = 0; j <= ny; j++) for (let i = 0; i <= nx; i++) vals[j * (nx + 1) + i] = f(box.xmin + i * dx, box.ymin + j * dy)
    const segs = []
    const V = (i, j) => vals[j * (nx + 1) + i]
    const edge = (i0, j0, i1, j1) => {
        const a = V(i0, j0), b = V(i1, j1)
        const t = a / (a - b)
        return P(box.xmin + (i0 + (i1 - i0) * t) * dx, box.ymin + (j0 + (j1 - j0) * t) * dy)
    }
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
        const a = V(i, j), b = V(i + 1, j), c = V(i + 1, j + 1), d = V(i, j + 1)
        if (![a, b, c, d].every(Number.isFinite)) continue
        const pts = []
        if ((a > 0) !== (b > 0)) pts.push(edge(i, j, i + 1, j))
        if ((b > 0) !== (c > 0)) pts.push(edge(i + 1, j, i + 1, j + 1))
        if ((c > 0) !== (d > 0)) pts.push(edge(i + 1, j + 1, i, j + 1))
        if ((d > 0) !== (a > 0)) pts.push(edge(i, j + 1, i, j))
        if (pts.length < 2) continue
        // 过零而非穿越间断：跨度过大的格子（如 1/x 的渐近线）跳过
        const m = Math.max(Math.abs(a), Math.abs(b), Math.abs(c), Math.abs(d))
        const mid = f(box.xmin + (i + 0.5) * dx, box.ymin + (j + 0.5) * dy)
        if (Math.abs(mid) > m * 1.5 + 1e-9) continue
        if (pts.length === 2) segs.push([pts[0], pts[1]])
        else {
            // 鞍点：用中心值决定连接方式
            if ((mid > 0) === (a > 0)) { segs.push([pts[0], pts[3]]); segs.push([pts[1], pts[2]]) }
            else { segs.push([pts[0], pts[1]]); segs.push([pts[2], pts[3]]) }
        }
    }
    return joinSegments(segs, Math.min(dx, dy) * 1e-6)
}

// 把首尾相接的线段连成折线，减少绘制与命中测试的开销
function joinSegments(segs, eps) {
    const key = p => `${Math.round(p.x / eps)},${Math.round(p.y / eps)}`
    const ends = new Map()
    const add = (k, i) => { const l = ends.get(k); l ? l.push(i) : ends.set(k, [i]) }
    segs.forEach((s, i) => { add(key(s[0]), i); add(key(s[1]), i) })
    const used = new Uint8Array(segs.length)
    const out = []
    const other = (s, k) => (key(s[0]) === k ? s[1] : s[0])
    for (let i = 0; i < segs.length; i++) {
        if (used[i]) continue
        used[i] = 1
        const line = [segs[i][0], segs[i][1]]
        for (const dir of [1, 0]) {
            for (;;) {
                const end = dir ? line[line.length - 1] : line[0]
                const k = key(end)
                const next = (ends.get(k) ?? []).find(j => !used[j])
                if (next == null) break
                used[next] = 1
                const p = other(segs[next], k)
                dir ? line.push(p) : line.unshift(p)
            }
        }
        out.push(line)
    }
    return out
}

// 牛顿法把点投影到 f(x, y) = 0 上
export function implicitProject(f, p) {
    let x = p.x, y = p.y
    const h = 1e-6 * Math.max(1, Math.abs(x), Math.abs(y))
    for (let i = 0; i < 30; i++) {
        const v = f(x, y)
        if (!Number.isFinite(v)) return null
        const gx = (f(x + h, y) - f(x - h, y)) / (2 * h), gy = (f(x, y + h) - f(x, y - h)) / (2 * h)
        const g2 = gx * gx + gy * gy
        if (!(g2 > 1e-300)) break
        const k = v / g2
        x -= k * gx; y -= k * gy
        if (Math.abs(v) < 1e-12) break
    }
    return Math.abs(f(x, y)) < 1e-6 * (1 + Math.abs(x) + Math.abs(y)) ? P(x, y) : null
}

// 标准方程文本（轴与坐标轴平行时）与一般方程文本
export function conicEquation(v, fmt) {
    const axisX = Math.abs(v.u.y) < 1e-9, axisY = Math.abs(v.u.x) < 1e-9
    const sh = (n, c) => Math.abs(c) < 1e-9 ? n : `(${n} ${c > 0 ? '−' : '+'} ${fmt(Math.abs(c))})`
    if (v.shape !== 'parabola' && (axisX || axisY)) {
        const [X, Y] = axisX ? [sh('x', v.c.x), sh('y', v.c.y)] : [sh('y', v.c.y), sh('x', v.c.x)]
        const s = v.shape === 'ellipse' ? ' + ' : ' − '
        const first = axisX ? `${X}²/${fmt(v.a * v.a)}${s}${Y}²/${fmt(v.b * v.b)}` : v.shape === 'ellipse' ? `${Y}²/${fmt(v.b * v.b)} + ${X}²/${fmt(v.a * v.a)}` : `${X}²/${fmt(v.a * v.a)} − ${Y}²/${fmt(v.b * v.b)}`
        return `${first} = 1`
    }
    if (v.shape === 'parabola' && (axisX || axisY)) {
        const sgn = axisX ? Math.sign(v.u.x) : Math.sign(v.u.y)
        const k = fmt(2 * v.p * sgn)
        return axisX ? `${sh('y', v.c.y)}² = ${k}${sh('x', v.c.x)}` : `${sh('x', v.c.x)}² = ${k}${sh('y', v.c.y)}`
    }
    return generalEquation(v.coef, fmt)
}
export function generalEquation(k, fmt) {
    const m = Math.max(...k.map(Math.abs)) || 1
    // 以首个非零二次项为 1 规范化
    const lead = k.find(x => Math.abs(x) > 1e-9 * m) ?? 1
    const c = k.map(x => x / lead)
    const terms = ['x²', 'xy', 'y²', 'x', 'y', '']
    let s = ''
    c.forEach((v, i) => {
        if (Math.abs(v) < 1e-9) return
        const a = Math.abs(v)
        const num = terms[i] && Math.abs(a - 1) < 1e-9 ? '' : fmt(a)
        s += (s ? (v < 0 ? ' − ' : ' + ') : v < 0 ? '−' : '') + num + terms[i]
    })
    return (s || '0') + ' = 0'
}
