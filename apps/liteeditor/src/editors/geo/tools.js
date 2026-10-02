// 命中测试与作图工具
import { isLinear, isRound, isPath, isConic, isSmooth, intersections, projectParam, pointAt, dist, P, MEASURES } from './model.js'
import { toScreen, toWorld, linearEnds, funcPolylines, curvePolylines, conicPolylines, labelRect, annotationRect, gridStep } from './render.js'

const TOL = 7

function segDist(p, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, dd = dx * dx + dy * dy
    const t = dd < 1e-12 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / dd))
    return Math.hypot(p.x - a.x - dx * t, p.y - a.y - dy * t)
}
const polyDist = (p, lines) => {
    let best = Infinity
    for (const l of lines) for (let i = 0; i < l.length - 1; i++) best = Math.min(best, segDist(p, l[i], l[i + 1]))
    return best
}
function inPolygon(p, pts) {
    let c = false
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const a = pts[i], b = pts[j]
        if ((a.y > p.y) !== (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) c = !c
    }
    return c
}

// 屏幕点到几何值的距离（像素）；polygon 内部返回 TOL - 0.5（可选中但优先级低于边）
export function screenDist(v, s, view) {
    switch (v.kind) {
        case 'point': return Math.hypot(toScreen(view, v).x - s.x, toScreen(view, v).y - s.y)
        case 'line': case 'ray': case 'segment': { const [a, b] = linearEnds(v, view); return segDist(s, a, b) }
        case 'circle': { const c = toScreen(view, v.c); return Math.abs(Math.hypot(s.x - c.x, s.y - c.y) - v.r * view.s) }
        case 'arc': {
            const c = toScreen(view, v.c)
            let a = Math.atan2(-(s.y - c.y), s.x - c.x) - v.a0
            a = ((a % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2)
            if (a <= v.a1 - v.a0) return Math.abs(Math.hypot(s.x - c.x, s.y - c.y) - v.r * view.s)
            const e0 = toScreen(view, pointAt(v, 0)), e1 = toScreen(view, pointAt(v, 1))
            return Math.min(Math.hypot(s.x - e0.x, s.y - e0.y), Math.hypot(s.x - e1.x, s.y - e1.y))
        }
        case 'polygon': {
            const pts = v.pts.map(p => toScreen(view, p))
            const edge = polyDist(s, [[...pts, pts[0]]])
            return edge <= TOL ? edge : inPolygon(s, pts) ? TOL - 0.5 : edge
        }
        case 'func': return polyDist(s, funcPolylines(v, view))
        case 'curve': return polyDist(s, curvePolylines(v, view))
        case 'conic': return polyDist(s, conicPolylines(v, view))
    }
    return Infinity
}

// 命中测试：返回 { obj, part: 'obj'|'label'|'annotation'|'slider' }，优先级：标注 > 点 > 标签 > 线 > 多边形内部
export function hitTest(scene, view, s, { filter, ctx, showHidden } = {}) {
    const objs = scene.sort().filter(o => (!o.hidden || showHidden) && scene.val(o.id) && (!filter || filter(o, scene.val(o.id))))
    if (ctx) {
        for (let i = objs.length - 1; i >= 0; i--) {
            const o = objs[i]
            if (o.sx == null) continue
            const r = annotationRect(ctx, o, scene)
            if (s.x >= r.x && s.x <= r.x + r.w && s.y >= r.y && s.y <= r.y + r.h) return { obj: o, part: o.type === 'slider' && s.y > r.y + 22 ? 'slider' : 'annotation', rect: r }
        }
    }
    let best = null, bestD = TOL + 3
    for (const o of objs) {
        const v = scene.val(o.id)
        if (v.kind !== 'point') continue
        const d = screenDist(v, s, view)
        if (d < bestD) { best = o; bestD = d }
    }
    if (best) return { obj: best, part: 'obj' }
    if (ctx) {
        for (const o of objs) {
            if (!o.showLabel || o.sx != null) continue
            const r = labelRect(ctx, o, scene, view)
            if (r && s.x >= r.x - 2 && s.x <= r.x + r.w + 2 && s.y >= r.y - 2 && s.y <= r.y + r.h + 2) return { obj: o, part: 'label' }
        }
    }
    bestD = TOL
    for (const o of objs) {
        const v = scene.val(o.id)
        if (v.kind === 'point' || v.kind === 'number' || v.kind === 'text') continue
        const d = screenDist(v, s, view)
        if (d < bestD) { best = o; bestD = d }
    }
    return best ? { obj: best, part: 'obj' } : null
}

// 附近所有路径（用于交点吸附）
function nearbyPaths(scene, view, s, tol = TOL) {
    return scene.sort().filter(o => !o.hidden && isPath(scene.val(o.id)) && screenDist(scene.val(o.id), s, view) < tol)
}

// ---------- 智能取点 ----------
// 返回 { existing: obj } | { def: 新点定义, preview: {x,y} }
export function resolvePoint(scene, view, s, { snap = true, allowNew = true } = {}) {
    const hit = hitTest(scene, view, s, { filter: (o, v) => v.kind === 'point' })
    if (hit) return { existing: hit.obj }
    if (!allowNew) return null
    // 两条路径的交点
    const paths = nearbyPaths(scene, view, s, 10)
    if (paths.length >= 2) {
        let best = null
        for (let i = 0; i < paths.length; i++) for (let j = i + 1; j < paths.length; j++) {
            const list = intersections(scene.val(paths[i].id), scene.val(paths[j].id))
            list.forEach((p, idx) => {
                if (p.ok === false) return
                const d = Math.hypot(toScreen(view, p).x - s.x, toScreen(view, p).y - s.y)
                if (d < 12 && (!best || d < best.d)) best = { d, a: paths[i].id, b: paths[j].id, idx, p }
            })
        }
        if (best) {
            // 已存在同一交点则复用
            const ex = scene.objects.find(o => o.type === 'intersect' && ((o.a === best.a && o.b === best.b) || (o.a === best.b && o.b === best.a)) && dist(scene.val(o.id) ?? P(NaN, NaN), best.p) < 1e-7)
            if (ex) return { existing: ex }
            return { def: { type: 'intersect', a: best.a, b: best.b, idx: best.idx }, preview: best.p }
        }
    }
    // 路径上的点
    if (paths.length) {
        const path = paths.sort((a, b) => screenDist(scene.val(a.id), s, view) - screenDist(scene.val(b.id), s, view))[0]
        const v = scene.val(path.id)
        const t = projectParam(v, toWorld(view, s.x, s.y))
        return { def: { type: 'pointOn', path: path.id, t }, preview: pointAt(v, t) }
    }
    const w = snap ? snapWorld(view, s) : toWorld(view, s.x, s.y)
    return { def: { type: 'point', x: w.x, y: w.y }, preview: w }
}

// 吸附到网格交点（距离小于 8 像素时）
export function snapWorld(view, s) {
    const w = toWorld(view, s.x, s.y)
    const step = gridStep(view.s)
    const minor = step / (String(step)[0] === '2' ? 4 : 5)
    const g = minor * view.s >= 9 ? minor : step
    const sx = Math.round(w.x / g) * g, sy = Math.round(w.y / g) * g
    const sp = toScreen(view, P(sx, sy))
    return Math.hypot(sp.x - s.x, sp.y - s.y) < 8 ? P(clean(sx), clean(sy)) : w
}
const clean = v => Math.round(v * 1e9) / 1e9

// ---------- 工具定义 ----------
// slots: 每一步需要的对象类型：'point' | 'linear' | 'round' | 'path' | 'polygonPts' | 'transformable' | 'pointOn' | 'func'
// make(ids, extra) -> 对象定义；ask: 需要额外参数的对话框描述
export const TOOL_GROUPS = [
    {
        id: 'basic', label: '基本',
        tools: [
            { id: 'select', label: '选择 / 移动', icon: 'mouse-pointer-2', key: 'Escape', hint: '拖动自由点、标签与标注；框选多个对象；Shift 加选' },
            { id: 'pan', label: '平移画板', icon: 'hand', key: 'H', hint: '拖动画板；也可以在任意工具下按住空格或鼠标右键拖动' },
        ],
    },
    {
        id: 'point', label: '点',
        tools: [
            { id: 'point', label: '点', icon: 'dot', key: 'P', slots: [], hint: '单击空白处创建自由点；单击线上创建线上点；单击交叉处创建交点' },
            { id: 'intersect', label: '交点', icon: 'x', key: 'I', slots: ['path', 'path'], hint: '依次选择两个对象，创建它们的所有交点', make: null },
            { id: 'midpoint', label: '中点', icon: 'circle-dot', key: 'M', slots: ['point', 'point'], hint: '选择两个点（或一条线段）', make: ([a, b]) => ({ type: 'midpoint', a, b }) },
        ],
    },
    {
        id: 'line', label: '线',
        tools: [
            { id: 'segment', label: '线段', icon: 'minus', key: 'S', slots: ['point', 'point'], make: ([a, b]) => ({ type: 'segment', a, b }) },
            { id: 'ray', label: '射线', icon: 'move-up-right', key: 'R', slots: ['point', 'point'], make: ([a, b]) => ({ type: 'ray', a, b }) },
            { id: 'line', label: '直线', icon: 'move-diagonal', key: 'L', slots: ['point', 'point'], make: ([a, b]) => ({ type: 'line', a, b }) },
            { id: 'vector', label: '向量', icon: 'arrow-up-right', slots: ['point', 'point'], make: ([a, b]) => ({ type: 'segment', a, b, arrow: true }) },
            { id: 'parallel', label: '平行线', icon: 'equal', slots: ['linear', 'point'], hint: '选择一条直线，再选择一个点', make: ([line, point]) => ({ type: 'parallel', line, point }) },
            { id: 'perpendicular', label: '垂线', icon: 'square-bottom-dashed-scissors', slots: ['linear', 'point'], hint: '选择一条直线，再选择一个点', make: ([line, point]) => ({ type: 'perpendicular', line, point }) },
            { id: 'perpBisector', label: '中垂线', icon: 'split', slots: ['point', 'point'], make: ([a, b]) => ({ type: 'perpBisector', a, b }) },
            { id: 'angleBisector', label: '角平分线', icon: 'git-fork', slots: ['point', 'point', 'point'], hint: '依次选择三个点，第二个点为角的顶点', make: ([a, b, c]) => ({ type: 'angleBisector', a, b, c }) },
            { id: 'tangent', label: '切线', icon: 'circle-slash-2', slots: ['point', 'smooth'], hint: '选择曲线外（或曲线上）一点，再选择圆或圆锥曲线', make: null },
        ],
    },
    {
        id: 'circle', label: '圆',
        tools: [
            { id: 'circle', label: '圆（圆心与点）', icon: 'circle', key: 'C', slots: ['point', 'point'], make: ([c, p]) => ({ type: 'circle', c, p }) },
            { id: 'circleR', label: '圆（圆心与半径）', icon: 'circle-dashed', slots: ['point'], ask: 'radius', make: ([c], x) => ({ type: 'circleR', c, r: x.r }) },
            { id: 'circle3', label: '三点圆', icon: 'circle-ellipsis', slots: ['point', 'point', 'point'], make: ([a, b, c]) => ({ type: 'circle3', a, b, c }) },
            { id: 'arc', label: '圆弧（圆心）', icon: 'rotate-ccw', slots: ['point', 'point', 'point'], hint: '圆心、起点，再选择终点方向（逆时针）', make: ([c, a, b]) => ({ type: 'arc', c, a, b }) },
            { id: 'arc3', label: '三点圆弧', icon: 'spline', slots: ['point', 'point', 'point'], hint: '起点、经过点、终点', make: ([a, b, c]) => ({ type: 'arc3', a, b, c }) },
        ],
    },
    {
        id: 'conic', label: '圆锥曲线',
        tools: [
            { id: 'ellipse', label: '椭圆（两焦点与一点）', icon: 'ellipse', key: 'E', slots: ['point', 'point', 'point'], hint: '依次选择两个焦点，再选择椭圆经过的点', make: ([f1, f2, p]) => ({ type: 'ellipse', f1, f2, p }) },
            { id: 'ellipseC', label: '椭圆（中心、顶点与一点）', icon: 'egg', slots: ['point', 'point', 'point'], hint: '中心、长轴端点（顶点），再选择椭圆经过的点', make: ([c, v, p]) => ({ type: 'ellipseC', c, v, p }) },
            { id: 'hyperbola', label: '双曲线（两焦点与一点）', icon: 'hourglass', slots: ['point', 'point', 'point'], hint: '依次选择两个焦点，再选择双曲线经过的点', make: ([f1, f2, p]) => ({ type: 'hyperbola', f1, f2, p }) },
            { id: 'hyperbolaC', label: '双曲线（中心、顶点与一点）', icon: 'chevrons-left-right', slots: ['point', 'point', 'point'], hint: '中心、实轴端点（顶点），再选择双曲线经过的点', make: ([c, v, p]) => ({ type: 'hyperbolaC', c, v, p }) },
            { id: 'parabola', label: '抛物线（焦点与准线）', icon: 'rainbow', slots: ['point', 'linear'], hint: '选择焦点，再选择准线', make: ([focus, line]) => ({ type: 'parabola', focus, line }) },
            { id: 'conic5', label: '五点圆锥曲线', icon: 'orbit', slots: ['point', 'point', 'point', 'point', 'point'], hint: '选择五个点，确定过这五点的圆锥曲线', make: pts => ({ type: 'conic5', pts }) },
        ],
    },
    {
        id: 'poly', label: '多边形',
        tools: [
            { id: 'polygon', label: '多边形', icon: 'pentagon', key: 'G', slots: ['polygonPts'], hint: '依次单击顶点，单击第一个点闭合（或按 Enter）', make: ([pts]) => ({ type: 'polygon', pts }) },
            { id: 'triangle', label: '三角形', icon: 'triangle', slots: ['point', 'point', 'point'], make: ([a, b, c]) => ({ type: 'polygon', pts: [a, b, c] }) },
            { id: 'regular', label: '正多边形', icon: 'hexagon', slots: ['point', 'point'], ask: 'sides', make: ([a, b], x) => ({ type: 'regular', a, b, n: x.n }) },
        ],
    },
    {
        id: 'transform', label: '变换',
        tools: [
            { id: 'translate', label: '平移', icon: 'move', slots: ['transformable', 'point', 'point'], hint: '选择要平移的对象，再依次选择向量起点、终点', make: ([src, a, b]) => ({ type: 'translate', src, a, b }) },
            { id: 'rotate', label: '旋转', icon: 'rotate-cw', slots: ['transformable', 'point'], ask: 'angle', hint: '选择要旋转的对象，再选择旋转中心', make: ([src, center], x) => ({ type: 'rotate', src, center, angle: x.angle }) },
            { id: 'reflect', label: '反射（轴对称）', icon: 'flip-horizontal-2', slots: ['transformable', 'linear'], hint: '选择要反射的对象，再选择对称轴', make: ([src, line]) => ({ type: 'reflect', src, line }) },
            { id: 'dilate', label: '缩放（位似）', icon: 'scaling', slots: ['transformable', 'point'], ask: 'factor', hint: '选择要缩放的对象，再选择位似中心', make: ([src, center], x) => ({ type: 'dilate', src, center, k: x.k }) },
        ],
    },
    {
        id: 'measure', label: '度量',
        tools: [
            { id: 'm-distance', label: '距离 / 长度', icon: 'ruler', key: 'D', slots: ['measureDistance'], hint: '选择一条线段，或两个点，或一个点与一条直线' },
            { id: 'm-angle', label: '角度', icon: 'triangle-right', key: 'A', slots: ['point', 'point', 'point'], hint: '依次选择三个点，第二个点为顶点', make: ([a, b, c]) => ({ type: 'measure', m: 'angle', of: [a, b, c] }) },
            { id: 'm-area', label: '面积', icon: 'square-dashed', slots: ['area'], hint: '选择多边形或圆', make: ([a]) => ({ type: 'measure', m: 'area', of: [a] }) },
            { id: 'm-slope', label: '斜率', icon: 'trending-up', slots: ['linear'], make: ([a]) => ({ type: 'measure', m: 'slope', of: [a] }) },
            { id: 'm-coords', label: '坐标', icon: 'crosshair', slots: ['point'], make: ([a]) => ({ type: 'measure', m: 'coords', of: [a] }) },
            { id: 'm-equation', label: '方程', icon: 'sigma', slots: ['eqTarget'], hint: '选择直线或圆', make: ([a]) => ({ type: 'measure', m: 'equation', of: [a] }) },
        ],
    },
    {
        id: 'other', label: '其他',
        tools: [
            { id: 'locus', label: '轨迹', icon: 'waypoints', slots: ['point', 'pointOn'], hint: '先选择轨迹点，再选择在路径上运动的驱动点', make: ([point, driver]) => ({ type: 'locus', point, driver }) },
            { id: 'text', label: '文本', icon: 'type', key: 'T', hint: '单击画板放置文本；用 {表达式} 插入实时数值，例如 {m1*2}' },
            { id: 'slider', label: '参数滑块', icon: 'sliders-horizontal', hint: '单击画板放置滑块' },
        ],
    },
]
export const TOOLS = Object.fromEntries(TOOL_GROUPS.flatMap(g => g.tools).map(t => [t.id, t]))

// 对象是否满足槽位类型
export function accepts(slot, o, v) {
    if (!v) return false
    switch (slot) {
        case 'point': case 'polygonPts': return v.kind === 'point'
        case 'pointOn': return o.type === 'pointOn'
        case 'linear': return isLinear(v)
        case 'round': return isRound(v)
        case 'smooth': return isSmooth(v)
        case 'conic': return isConic(v)
        case 'path': return isPath(v)
        case 'area': return v.kind === 'polygon' || v.kind === 'circle' || v.kind === 'arc' || (isConic(v) && v.shape === 'ellipse')
        case 'eqTarget': return isLinear(v) || isRound(v) || isConic(v)
        case 'transformable': return ['point', 'line', 'ray', 'segment', 'circle', 'arc', 'polygon', 'curve', 'conic'].includes(v.kind)
        case 'measureDistance': return v.kind === 'point' || v.kind === 'segment' || isLinear(v) || v.kind === 'arc'
    }
    return false
}
// 该槽位是否可以通过单击空白处新建点
export const slotCreatesPoint = slot => slot === 'point' || slot === 'polygonPts'

export { MEASURES }
