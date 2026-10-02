// 场景：对象列表 + 拓扑排序求值 + 轨迹 + 级联删除 + 代数视图文本
import { compile, fmt } from './expr.js'
import {
    TYPES, MEASURES, computeVal, refIds, exprNames, isAnnotation, categoryOf, nextName,
    paramRange, pointAt, isPath, equationOf, splitEquation,
} from './model.js'
import { eccentricity } from './conic.js'

export const PALETTE = ['#2563eb', '#dc2626', '#16a34a', '#9333ea', '#ea580c', '#0891b2', '#db2777', '#4b5563', '#111827', '#ca8a04']

export const DEFAULT_STYLE = {
    point: { color: '#2563eb', size: 4.5, pointStyle: 'dot' },
    free: { color: '#dc2626' },
    linear: { color: '#1f2937', width: 1.8, dash: 'solid' },
    circle: { color: '#1f2937', width: 1.8, dash: 'solid' },
    polygon: { color: '#7c3aed', width: 1.6, dash: 'solid', fill: 0.18 },
    func: { color: '#2563eb', width: 2.2, dash: 'solid' },
    curve: { color: '#9333ea', width: 2, dash: 'solid' },
    conic: { color: '#0d9488', width: 2, dash: 'solid' },
    other: { color: '#1f2937', width: 1.8, dash: 'solid' },
    slider: { color: '#2563eb' },
    measure: { color: '#111827' },
    calc: { color: '#111827' },
    text: { color: '#111827', fontSize: 15 },
}

export class Scene {
    constructor() {
        this.objects = []
        this.vals = new Map()
        this.order = []
        this.structVersion = 0
        this.orderVersion = -1
        this.seq = 1
    }

    byId(id) { return this.objects.find(o => o.id === id) }
    byName(name) { return this.objects.find(o => o.name === name) }
    val(id) { return this.vals.get(id) ?? null }

    newId() {
        let id
        do { id = 'o' + (this.seq++) } while (this.objects.some(o => o.id === id))
        return id
    }

    // 添加对象：自动命名、默认样式；返回对象（若无法计算返回 null 并撤回）
    add(def, { name, style, view } = {}) {
        const o = { id: this.newId(), hidden: false, showLabel: true, ...def }
        this.objects.push(o)
        this.touch()
        this.recompute(view)
        const v = this.val(o.id)
        const cat = categoryOf(o, v)
        o.name ??= name ?? nextName(this.objects.filter(x => x !== o), cat)
        const base = { ...(DEFAULT_STYLE[cat] ?? DEFAULT_STYLE.other) }
        if (cat === 'point' && o.type === 'point') Object.assign(base, DEFAULT_STYLE.free)
        o.style = { ...base, ...(o.style ?? {}), ...(style ?? {}) }
        if (o.showLabel === true && !['point', 'slider', 'measure', 'calc', 'text', 'func'].includes(cat)) o.showLabel = false
        this.touch()
        this.recompute(view)
        return o
    }

    touch() { this.structVersion++ }

    // 名称 -> id（数值与函数对象可在表达式中引用）
    nameMap() {
        const m = new Map()
        for (const o of this.objects) m.set(o.name, o.id)
        return m
    }

    // 所有父对象（直接引用 + 表达式中引用的名称）
    parents(o, names = this.nameMap()) {
        const out = new Set(refIds(o))
        for (const n of exprNames(o)) { const id = names.get(n); if (id && id !== o.id) out.add(id) }
        if (o.type === 'locus') { out.add(o.point); out.add(o.driver) }
        return out
    }

    // 拓扑排序（出现环时按原顺序追加，其值为 null）
    sort() {
        if (this.orderVersion === this.structVersion) return this.order
        const names = this.nameMap()
        const byId = new Map(this.objects.map(o => [o.id, o]))
        const state = new Map(), order = []
        const visit = o => {
            const s = state.get(o.id)
            if (s === 2) return
            if (s === 1) { this.cyclic.add(o.id); return }
            state.set(o.id, 1)
            for (const p of this.parents(o, names)) { const po = byId.get(p); if (po) visit(po) }
            state.set(o.id, 2)
            order.push(o)
        }
        this.cyclic = new Set()
        for (const o of this.objects) visit(o)
        this.order = order
        this.orderVersion = this.structVersion
        return order
    }

    // 重新计算全部数值
    recompute(view = this.view) {
        if (view) this.view = view
        const order = this.sort()
        const vals = new Map()
        const scope = { __funcs: {} }
        const get = id => vals.get(id) ?? null
        for (const o of order) {
            let v = null
            if (!this.cyclic.has(o.id)) {
                try {
                    v = o.type === 'locus' ? this.computeLocus(o, vals, scope) : computeVal(o, get, scope, this.viewBox())
                } catch (e) { console.warn(e); v = null }
            }
            vals.set(o.id, v)
            if (v?.kind === 'number' && o.name && Number.isFinite(v.v)) scope[o.name] = v.v
            if (v?.kind === 'func' && o.name) scope.__funcs[o.name] = v.f
        }
        this.vals = vals
        this.scope = scope
    }

    viewBox() {
        const v = this.view
        if (!v) return { xmin: -10, xmax: 10, ymin: -10, ymax: 10 }
        return { xmin: v.x0 - v.w / 2 / v.s, xmax: v.x0 + v.w / 2 / v.s, ymin: v.y0 - v.h / 2 / v.s, ymax: v.y0 + v.h / 2 / v.s }
    }

    // 从 root 出发的后代（按拓扑顺序）
    descendants(rootIds) {
        const order = this.sort()
        const names = this.nameMap()
        const set = new Set(rootIds)
        const out = []
        for (const o of order) {
            if (set.has(o.id)) continue
            for (const p of this.parents(o, names)) if (set.has(p)) { set.add(o.id); out.push(o); break }
        }
        return out
    }

    ancestors(id) {
        const names = this.nameMap()
        const out = new Set()
        const walk = x => {
            const o = this.byId(x)
            if (!o) return
            for (const p of this.parents(o, names)) if (!out.has(p)) { out.add(p); walk(p) }
        }
        walk(id)
        return out
    }

    // 轨迹：驱动点沿路径运动时，被驱动点经过的路径
    computeLocus(o, vals, scope) {
        const driver = this.byId(o.driver), target = this.byId(o.point)
        if (!driver || !target || driver.type !== 'pointOn') return null
        const path = vals.get(driver.path)
        if (!isPath(path)) return null
        const anc = this.ancestors(target.id)
        if (!anc.has(driver.id)) return null
        // 需要重新计算的链：driver 的后代且是 target 的祖先（或 target 本身）
        const chain = this.descendants([driver.id]).filter(x => x.id === target.id || anc.has(x.id))
        const [t0, t1] = paramRange(path, this.viewBox())
        const N = o.samples ?? 400
        const pts = []
        const local = new Map(vals)
        const get = id => local.get(id) ?? null
        const sc = { ...scope, __funcs: { ...scope.__funcs } }
        for (let i = 0; i <= N; i++) {
            const t = t0 + (t1 - t0) * i / N
            const p = pointAt(path, t)
            local.set(driver.id, p ? { kind: 'point', ...p } : null)
            for (const c of chain) {
                const v = c.type === 'locus' ? null : computeVal(c, get, sc, this.viewBox())
                local.set(c.id, v)
                if (v?.kind === 'number' && c.name) sc[c.name] = v.v
            }
            const tv = local.get(target.id)
            pts.push(tv?.kind === 'point' ? { x: tv.x, y: tv.y } : { x: NaN, y: NaN })
        }
        return { kind: 'curve', pts, closed: path.kind === 'circle' || path.kind === 'polygon' }
    }

    // 删除对象及其所有依赖者，返回被删除的数量
    remove(ids) {
        const set = new Set(ids)
        for (const d of this.descendants(ids)) set.add(d.id)
        this.objects = this.objects.filter(o => !set.has(o.id))
        this.touch()
        this.recompute()
        return set.size
    }

    // ---------- 代数视图文本 ----------
    nm(id) { return this.byId(id)?.name ?? '?' }

    definition(o) {
        const n = id => this.nm(id)
        const T = TYPES[o.type]?.label ?? o.type
        switch (o.type) {
            case 'point': return '自由点'
            case 'pointOn': return `${n(o.path)} 上的点`
            case 'intersect': return `交点(${n(o.a)}, ${n(o.b)})${o.idx ? ' #' + (o.idx + 1) : ''}`
            case 'midpoint': return `中点(${n(o.a)}, ${n(o.b)})`
            case 'segment': case 'ray': case 'line': return `${T}(${n(o.a)}, ${n(o.b)})`
            case 'parallel': return `过 ${n(o.point)} 平行于 ${n(o.line)}`
            case 'perpendicular': return `过 ${n(o.point)} 垂直于 ${n(o.line)}`
            case 'perpBisector': return `中垂线(${n(o.a)}, ${n(o.b)})`
            case 'angleBisector': return `角平分线 ∠${n(o.a)}${n(o.b)}${n(o.c)}`
            case 'circle': return `圆(圆心 ${n(o.c)}, 过 ${n(o.p)})`
            case 'circleR': return `圆(圆心 ${n(o.c)}, 半径 ${o.r})`
            case 'circle3': return `圆(${n(o.a)}, ${n(o.b)}, ${n(o.c)})`
            case 'arc': return `圆弧(圆心 ${n(o.c)}, ${n(o.a)} → ${n(o.b)})`
            case 'arc3': return `圆弧(${n(o.a)}, ${n(o.b)}, ${n(o.c)})`
            case 'polygon': return `多边形(${o.pts.map(n).join(', ')})`
            case 'regular': return `正 ${o.n} 边形(${n(o.a)}, ${n(o.b)})`
            case 'tangent': return `切线(${n(o.point)}, ${n(o.circle)})`
            case 'translate': return `平移(${n(o.src)}, 向量 ${n(o.a)}${n(o.b)})`
            case 'rotate': return `旋转(${n(o.src)}, ${n(o.center)}, ${o.angle}°)`
            case 'reflect': return `反射(${n(o.src)}, ${n(o.line)})`
            case 'dilate': return `缩放(${n(o.src)}, ${n(o.center)}, ${o.k})`
            case 'locus': return `轨迹(${n(o.point)}, ${n(o.driver)})`
            case 'func': return `${o.name}(x) = ${o.expr}`
            case 'derivative': return `${n(o.of)}′(x)`
            case 'param': return `(${o.xExpr}, ${o.yExpr}), t ∈ [${o.tmin}, ${o.tmax}]`
            case 'polar': return `r = ${o.rExpr}, θ ∈ [${o.tmin}, ${o.tmax}]`
            case 'slider': return `参数 [${o.min}, ${o.max}]`
            case 'measure': return `${MEASURES[o.m]?.label ?? '度量'}(${(o.of ?? []).map(n).join(', ')})`
            case 'calc': return o.expr
            case 'text': return '文本'
            case 'ellipse': case 'hyperbola': return `${T}(焦点 ${n(o.f1)}, ${n(o.f2)}, 过 ${n(o.p)})`
            case 'ellipseC': case 'hyperbolaC': return `${T.replace('（中心）', '')}(中心 ${n(o.c)}, 顶点 ${n(o.v)}, 过 ${n(o.p)})`
            case 'parabola': return `抛物线(焦点 ${n(o.focus)}, 准线 ${n(o.line)})`
            case 'conic5': return `圆锥曲线(${o.pts.map(n).join(', ')})`
            case 'conicStd': return `${SHAPE_NAME[o.shape] ?? T}(中心 ${n(o.c)}, a = ${o.a}${o.shape === 'parabola' ? '' : `, b = ${o.b}`}${o.angle && o.angle !== '0' ? `, ${o.angle}°` : ''})`
            case 'equation': return o.expr.includes('=') ? o.expr : `${o.expr} = 0`
            case 'conicPart': return `${PART_NAME[o.part] ?? '元素'}(${n(o.of)})${['focus', 'vertex', 'asymptote', 'directrix'].includes(o.part) && (o.idx ?? 0) > 0 ? ' #' + ((o.idx ?? 0) + 1) : ''}`
        }
        return T
    }

    // 数值描述（代数视图右侧）
    valueText(o) {
        const v = this.val(o.id)
        const d = o.digits ?? 2
        if (!v) return '未定义'
        switch (v.kind) {
            case 'point': return `(${fmt(v.x, d)}, ${fmt(v.y, d)})`
            case 'segment': return `长度 ${fmt(Math.hypot(v.q.x - v.p.x, v.q.y - v.p.y), d)}`
            case 'circle': return `r = ${fmt(v.r, d)}`
            case 'arc': return `r = ${fmt(v.r, d)}`
            case 'number': return v.text ?? fmt(v.v, d) + (v.unit ?? '')
            case 'polygon': return `${v.pts.length} 个顶点`
            case 'conic': return `${SHAPE_NAME[v.shape]} · e = ${fmt(eccentricity(v), d)}`
            case 'line': case 'ray': return equationOf(v, d)
            case 'curve': return o.type === 'equation' ? '隐函数曲线' : ''
            case 'text': return v.text
        }
        return ''
    }

    // 画板上度量标注的文字，例如 “|AB| = 5.00”、“∠ABC = 60.00°”
    annotationText(o) {
        const v = this.val(o.id)
        const d = o.digits ?? 2
        const val = !v ? '未定义' : v.text ?? (Number.isFinite(v.v) ? fmt(v.v, d) + (v.unit ?? '') : '未定义')
        if (o.type === 'text') return v?.text ?? ''
        if (o.type === 'calc') return `${o.name} = ${val}`
        if (o.type === 'slider') return `${o.name} = ${fmt(o.value, d)}`
        if (o.type !== 'measure') return val
        if (o.label) return `${o.label} = ${val}`
        const ns = (o.of ?? []).map(id => this.nm(id))
        const prefix = {
            distance: `|${ns.join('')}|`, length: `|${ns[0]}|`, angle: `∠${ns.join('')}`, area: `S(${ns[0]})`, perimeter: `C(${ns[0]})`,
            radius: `r(${ns[0]})`, arcLength: `弧长(${ns[0]})`, arcAngle: `弧度角(${ns[0]})`, slope: `k(${ns[0]})`, coords: ns[0], equation: ns[0],
            eccentricity: `e(${ns[0]})`, focal: `2c(${ns[0]})`,
        }[o.m] ?? o.name
        return o.m === 'equation' ? `${prefix}: ${val}` : `${prefix} = ${val}`
    }

    // ---------- 序列化 ----------
    toJSON() { return this.objects.map(o => structuredClone(o)) }
    load(objects) {
        this.objects = objects.map(o => structuredClone(o))
        const max = Math.max(0, ...this.objects.map(o => Number(String(o.id).replace(/\D/g, '')) || 0))
        this.seq = max + 1
        this.touch()
        this.recompute()
    }
}

export const SHAPE_NAME = { ellipse: '椭圆', hyperbola: '双曲线', parabola: '抛物线' }
export const PART_NAME = { center: '中心', focus: '焦点', vertex: '顶点', asymptote: '渐近线', directrix: '准线', majorAxis: '长轴', minorAxis: '短轴' }

// 表达式合法性检查（供属性面板使用）
export const exprError = src => compile(String(src ?? '')).error
// 方程合法性检查：允许一个等号
export const equationError = src => {
    const e = splitEquation(src)
    if (e == null) return '只能有一个等号'
    const c = compile(e)
    if (c.error) return c.error
    return null
}
