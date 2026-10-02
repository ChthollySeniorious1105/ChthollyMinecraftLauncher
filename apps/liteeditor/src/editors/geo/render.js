// 渲染：同一套绘制代码，既可画到 Canvas，也可通过 SvgContext 输出 SVG
import { fmt } from './expr.js'
import { isLinear, paramRange, P, sub, norm, dist } from './model.js'
import { conicSamples, conicPoint } from './conic.js'

const TAU = Math.PI * 2
const ACCENT = '#f59e0b'

// ---------- 视图坐标 ----------
// view: { x0, y0 世界坐标中心, s 每单位像素, w, h 画布 CSS 像素 }
export const toScreen = (v, p) => ({ x: v.w / 2 + (p.x - v.x0) * v.s, y: v.h / 2 - (p.y - v.y0) * v.s })
export const toWorld = (v, x, y) => ({ x: v.x0 + (x - v.w / 2) / v.s, y: v.y0 - (y - v.h / 2) / v.s })
export const viewBox = v => ({ xmin: v.x0 - v.w / 2 / v.s, xmax: v.x0 + v.w / 2 / v.s, ymin: v.y0 - v.h / 2 / v.s, ymax: v.y0 + v.h / 2 / v.s })

// 网格步长：1、2、5 × 10^k，使相邻网格线间距不小于 minPx
export function gridStep(s, minPx = 46) {
    const raw = minPx / s
    const k = Math.pow(10, Math.floor(Math.log10(raw)))
    for (const m of [1, 2, 5, 10]) if (m * k >= raw) return m * k
    return 10 * k
}

const DASH = { solid: [], dash: [8, 5], dot: [2, 4], dashdot: [9, 4, 2, 4] }

// ---------- 场景绘制 ----------
// opts: { grid, axes, selected: Set, hover, showHidden, preview: fn(ctx), traces, highlightIds }
export function drawScene(ctx, scene, view, opts = {}) {
    const { w, h } = view
    ctx.save()
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, w, h)
    if (opts.grid || opts.axes) drawGrid(ctx, view, opts)

    const vis = o => (!o.hidden || opts.showHidden) && scene.val(o.id)
    const objs = scene.sort().filter(vis)
    const layer = o => {
        const v = scene.val(o.id)
        if (o.type === 'slider' || o.type === 'measure' || o.type === 'calc' || o.type === 'text') return 5
        if (v.kind === 'polygon') return 0
        if (v.kind === 'point') return 3
        return 1
    }
    // 追踪残影
    if (opts.traces?.length) drawTraces(ctx, opts.traces, view)

    // 角度标记（度量角度时在顶点处画小弧）
    for (const o of objs) if (o.type === 'measure' && o.m === 'angle' && o.mark !== false) drawAngleMark(ctx, scene, o, view)

    for (const L of [0, 1, 3]) {
        for (const o of objs) {
            if (layer(o) !== L) continue
            const sel = opts.selected?.has(o.id), hov = opts.hover === o.id
            ctx.globalAlpha = o.hidden ? 0.35 : 1
            drawObject(ctx, o, scene.val(o.id), view, { sel, hov })
        }
    }
    ctx.globalAlpha = 1
    // 标签
    for (const o of objs) {
        if (layer(o) === 5 || !o.showLabel) continue
        drawLabel(ctx, o, scene, view, opts.selected?.has(o.id))
    }
    opts.preview?.(ctx)
    // 标注（度量、文本、参数）
    for (const o of objs) {
        if (layer(o) !== 5) continue
        ctx.globalAlpha = o.hidden ? 0.4 : 1
        drawAnnotation(ctx, o, scene, view, { sel: opts.selected?.has(o.id), hov: opts.hover === o.id })
    }
    ctx.globalAlpha = 1
    ctx.restore()
}

function drawGrid(ctx, view, opts) {
    const { w, h, s } = view
    const b = viewBox(view)
    const step = gridStep(s)
    const minor = step / (String(step)[0] === '2' ? 4 : 5)
    ctx.lineWidth = 1
    if (opts.grid) {
        if (minor * s >= 9) {
            ctx.strokeStyle = '#f1f4f8'
            ctx.beginPath()
            for (let x = Math.ceil(b.xmin / minor) * minor; x <= b.xmax; x += minor) { const X = Math.round(toScreen(view, P(x, 0)).x) + 0.5; ctx.moveTo(X, 0); ctx.lineTo(X, h) }
            for (let y = Math.ceil(b.ymin / minor) * minor; y <= b.ymax; y += minor) { const Y = Math.round(toScreen(view, P(0, y)).y) + 0.5; ctx.moveTo(0, Y); ctx.lineTo(w, Y) }
            ctx.stroke()
        }
        ctx.strokeStyle = '#e1e6ee'
        ctx.beginPath()
        for (let x = Math.ceil(b.xmin / step) * step; x <= b.xmax; x += step) { const X = Math.round(toScreen(view, P(x, 0)).x) + 0.5; ctx.moveTo(X, 0); ctx.lineTo(X, h) }
        for (let y = Math.ceil(b.ymin / step) * step; y <= b.ymax; y += step) { const Y = Math.round(toScreen(view, P(0, y)).y) + 0.5; ctx.moveTo(0, Y); ctx.lineTo(w, Y) }
        ctx.stroke()
    }
    if (!opts.axes) return
    const o = toScreen(view, P(0, 0))
    const ax = Math.round(Math.min(Math.max(o.y, 0), h)) + 0.5
    const ay = Math.round(Math.min(Math.max(o.x, 0), w)) + 0.5
    ctx.strokeStyle = '#64748b'
    ctx.lineWidth = 1.2
    ctx.beginPath()
    ctx.moveTo(0, ax); ctx.lineTo(w, ax)
    ctx.moveTo(ay, 0); ctx.lineTo(ay, h)
    ctx.stroke()
    // 箭头
    ctx.fillStyle = '#64748b'
    ctx.beginPath(); ctx.moveTo(w, ax); ctx.lineTo(w - 9, ax - 4); ctx.lineTo(w - 9, ax + 4); ctx.closePath(); ctx.fill()
    ctx.beginPath(); ctx.moveTo(ay, 0); ctx.lineTo(ay - 4, 9); ctx.lineTo(ay + 4, 9); ctx.closePath(); ctx.fill()
    // 刻度数字
    ctx.font = '11px "Segoe UI", "Microsoft YaHei", sans-serif'
    ctx.fillStyle = '#64748b'
    const digits = Math.max(0, -Math.floor(Math.log10(step) + 1e-9))
    const label = v => fmt(v, digits + 1).replace('-', '−')
    ctx.textAlign = 'center'; ctx.textBaseline = 'top'
    const tyTop = ax + 4 > h - 16 ? ax - 16 : ax + 4
    for (let x = Math.ceil(b.xmin / step) * step; x <= b.xmax; x += step) {
        if (Math.abs(x) < step / 2) continue
        const X = toScreen(view, P(x, 0)).x
        ctx.beginPath(); ctx.moveTo(X, ax - 3); ctx.lineTo(X, ax + 3); ctx.strokeStyle = '#64748b'; ctx.lineWidth = 1; ctx.stroke()
        ctx.fillText(label(x), X, tyTop)
    }
    ctx.textBaseline = 'middle'
    const left = ay - 6 < 24
    ctx.textAlign = left ? 'left' : 'right'
    for (let y = Math.ceil(b.ymin / step) * step; y <= b.ymax; y += step) {
        if (Math.abs(y) < step / 2) continue
        const Y = toScreen(view, P(0, y)).y
        ctx.beginPath(); ctx.moveTo(ay - 3, Y); ctx.lineTo(ay + 3, Y); ctx.stroke()
        ctx.fillText(label(y), left ? ay + 6 : ay - 6, Y)
    }
    ctx.textAlign = 'right'; ctx.textBaseline = 'top'
    if (o.x > 0 && o.x < w && o.y > 0 && o.y < h) ctx.fillText('O', o.x - 5, o.y + 3)
    ctx.textAlign = 'right'; ctx.textBaseline = 'bottom'
    ctx.font = 'italic 13px "Times New Roman", serif'
    ctx.fillText('x', w - 6, ax - 6)
    ctx.textAlign = 'left'; ctx.textBaseline = 'top'
    ctx.fillText('y', ay + 8, 4)
}

function stroke(ctx, st, { sel, hov }, extra = 0) {
    const width = (st.width ?? 1.8) + extra
    if (sel || hov) {
        ctx.save()
        ctx.setLineDash([])
        ctx.strokeStyle = sel ? ACCENT : 'rgba(37, 99, 235, 0.35)'
        ctx.globalAlpha = sel ? 0.55 : 0.6
        ctx.lineWidth = width + 6
        ctx.lineCap = 'round'
        ctx.stroke()
        ctx.restore()
    }
    ctx.setLineDash(DASH[st.dash] ?? [])
    ctx.strokeStyle = st.color
    ctx.lineWidth = width
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.stroke()
    ctx.setLineDash([])
}

// 直线在视口中的可见端点（屏幕坐标）
export function linearEnds(v, view) {
    if (v.kind === 'segment') return [toScreen(view, v.p), toScreen(view, v.q)]
    const b = viewBox(view)
    const pad = 20 / view.s
    const [t0, t1] = paramRange(v, { xmin: b.xmin - pad, xmax: b.xmax + pad, ymin: b.ymin - pad, ymax: b.ymax + pad })
    const at = t => P(v.p.x + (v.q.x - v.p.x) * t, v.p.y + (v.q.y - v.p.y) * t)
    return [toScreen(view, at(t0)), toScreen(view, at(Math.max(t0, t1)))]
}

// 函数图像按像素列采样，遇到间断或渐近线时断开
export function funcPolylines(v, view) {
    const b = viewBox(view)
    const lo = Math.max(v.xmin, b.xmin), hi = Math.min(v.xmax, b.xmax)
    const out = []
    if (!(hi > lo)) return out
    const N = Math.max(2, Math.ceil((hi - lo) * view.s))
    let cur = []
    let prev = null
    for (let i = 0; i <= N; i++) {
        const x = lo + (hi - lo) * i / N
        const y = v.f(x)
        const sp = Number.isFinite(y) ? toScreen(view, P(x, y)) : null
        const jump = sp && prev && Math.abs(sp.y - prev.y) > view.h * 1.5
        if (!sp || jump || Math.abs(sp.y) > 1e5) {
            if (cur.length > 1) out.push(cur)
            cur = sp && !jump && Math.abs(sp.y) <= 1e5 ? [sp] : []
            if (jump) cur = [sp]
        } else cur.push(sp)
        prev = sp
    }
    if (cur.length > 1) out.push(cur)
    return out
}

export function curvePolylines(v, view) {
    const out = []
    let cur = []
    for (const p of v.pts) {
        if (Number.isFinite(p.x) && Number.isFinite(p.y)) {
            const s = toScreen(view, p)
            if (cur.length && Math.hypot(s.x - cur[cur.length - 1].x, s.y - cur[cur.length - 1].y) > Math.max(view.w, view.h)) { if (cur.length > 1) out.push(cur); cur = [] }
            cur.push(s)
        } else { if (cur.length > 1) out.push(cur); cur = [] }
    }
    if (cur.length > 1) out.push(cur)
    return out
}

// 圆锥曲线：按视口大小采样后转换为屏幕坐标，并按视口裁剪过远的点
export function conicPolylines(v, view) {
    const b = viewBox(view)
    const R = Math.hypot(b.xmax - b.xmin, b.ymax - b.ymin) + Math.hypot((b.xmin + b.xmax) / 2 - v.c.x, (b.ymin + b.ymax) / 2 - v.c.y)
    const lim = Math.max(view.w, view.h) * 4
    return conicSamples(v, R).map(l => l.map(p => toScreen(view, p)).filter(s => Math.abs(s.x) < lim && Math.abs(s.y) < lim)).filter(l => l.length > 1)
}

function polylinePath(ctx, lines) {
    ctx.beginPath()
    for (const l of lines) {
        ctx.moveTo(l[0].x, l[0].y)
        for (let i = 1; i < l.length; i++) ctx.lineTo(l[i].x, l[i].y)
    }
}

function drawObject(ctx, o, v, view, state) {
    const st = o.style ?? {}
    switch (v.kind) {
        case 'point': return drawPoint(ctx, toScreen(view, v), st, state, o.type === 'point' || o.type === 'pointOn')
        case 'line': case 'ray': case 'segment': {
            const [a, b] = linearEnds(v, view)
            ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y)
            stroke(ctx, st, state)
            if (o.arrow && v.kind === 'segment') arrowHead(ctx, a, b, st)
            return
        }
        case 'circle': {
            const c = toScreen(view, v.c)
            ctx.beginPath(); ctx.arc(c.x, c.y, v.r * view.s, 0, TAU)
            if (st.fill > 0) { ctx.globalAlpha *= st.fill; ctx.fillStyle = st.color; ctx.fill(); ctx.globalAlpha /= st.fill }
            stroke(ctx, st, state)
            return
        }
        case 'arc': {
            const c = toScreen(view, v.c)
            ctx.beginPath(); ctx.arc(c.x, c.y, v.r * view.s, -v.a0, -v.a1, true)
            stroke(ctx, st, state)
            return
        }
        case 'polygon': {
            const pts = v.pts.map(p => toScreen(view, p))
            ctx.beginPath()
            pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)))
            ctx.closePath()
            const fa = st.fill ?? 0.18
            if (fa > 0) {
                const g = ctx.globalAlpha
                ctx.globalAlpha = g * fa * (state.sel ? 1.6 : 1)
                ctx.fillStyle = st.color
                ctx.fill()
                ctx.globalAlpha = g
            }
            if (st.width > 0 || state.sel) stroke(ctx, { ...st, width: st.width || 0.01 }, state)
            return
        }
        case 'func': polylinePath(ctx, funcPolylines(v, view)); return stroke(ctx, st, state)
        case 'curve': polylinePath(ctx, curvePolylines(v, view)); return stroke(ctx, st, state)
        case 'conic': {
            const lines = conicPolylines(v, view)
            if (v.shape === 'ellipse' && st.fill > 0) {
                polylinePath(ctx, lines)
                ctx.closePath()
                const g = ctx.globalAlpha
                ctx.globalAlpha = g * st.fill
                ctx.fillStyle = st.color
                ctx.fill()
                ctx.globalAlpha = g
            }
            polylinePath(ctx, lines)
            return stroke(ctx, st, state)
        }
    }
}

function arrowHead(ctx, a, b, st) {
    const d = norm(sub(b, a)), n = P(-d.y, d.x), L = 8 + (st.width ?? 2) * 2
    ctx.beginPath()
    ctx.moveTo(b.x, b.y)
    ctx.lineTo(b.x - d.x * L + n.x * L * 0.45, b.y - d.y * L + n.y * L * 0.45)
    ctx.lineTo(b.x - d.x * L - n.x * L * 0.45, b.y - d.y * L - n.y * L * 0.45)
    ctx.closePath()
    ctx.fillStyle = st.color
    ctx.fill()
}

export function drawPoint(ctx, p, st, { sel, hov } = {}, free = false) {
    const r = st.size ?? 4.5
    if (sel || hov) {
        ctx.beginPath(); ctx.arc(p.x, p.y, r + 5, 0, TAU)
        ctx.fillStyle = sel ? 'rgba(245, 158, 11, 0.4)' : 'rgba(37, 99, 235, 0.2)'
        ctx.fill()
    }
    ctx.beginPath()
    const style = st.pointStyle ?? 'dot'
    if (style === 'cross') {
        ctx.moveTo(p.x - r, p.y - r); ctx.lineTo(p.x + r, p.y + r); ctx.moveTo(p.x + r, p.y - r); ctx.lineTo(p.x - r, p.y + r)
        ctx.strokeStyle = st.color; ctx.lineWidth = 2; ctx.stroke()
        return
    }
    if (style === 'square') ctx.rect(p.x - r, p.y - r, r * 2, r * 2)
    else if (style === 'diamond') { ctx.moveTo(p.x, p.y - r * 1.3); ctx.lineTo(p.x + r * 1.3, p.y); ctx.lineTo(p.x, p.y + r * 1.3); ctx.lineTo(p.x - r * 1.3, p.y); ctx.closePath() }
    else ctx.arc(p.x, p.y, r, 0, TAU)
    if (style === 'ring') {
        ctx.fillStyle = '#ffffff'; ctx.fill()
        ctx.strokeStyle = st.color; ctx.lineWidth = 2; ctx.stroke()
        return
    }
    ctx.fillStyle = st.color
    ctx.fill()
    ctx.strokeStyle = free ? '#ffffff' : 'rgba(0,0,0,0.55)'
    ctx.lineWidth = free ? 1.4 : 0.8
    ctx.stroke()
}

// 标签锚点（屏幕坐标）
export function labelAnchor(o, v, view) {
    switch (v.kind) {
        case 'point': return toScreen(view, v)
        case 'segment': case 'line': case 'ray': {
            const [a, b] = linearEnds(v, view)
            const t = v.kind === 'segment' ? 0.5 : 0.82
            return P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
        case 'circle': { const c = toScreen(view, v.c), r = v.r * view.s; return P(c.x + r * 0.7071, c.y - r * 0.7071) }
        case 'arc': { const m = (v.a0 + v.a1) / 2, c = toScreen(view, v.c), r = v.r * view.s; return P(c.x + r * Math.cos(m), c.y - r * Math.sin(m)) }
        case 'polygon': {
            const c = v.pts.reduce((s, p) => P(s.x + p.x / v.pts.length, s.y + p.y / v.pts.length), P(0, 0))
            return toScreen(view, c)
        }
        case 'func': {
            const b = viewBox(view)
            const lines = funcPolylines(v, view)
            const l = lines.find(l => l.length > 4) ?? lines[0]
            if (!l) return null
            const i = Math.min(l.length - 1, Math.floor(l.length * 0.86))
            void b
            return l[i]
        }
        case 'curve': { const l = curvePolylines(v, view)[0]; return l ? l[Math.floor(l.length * 0.7)] : null }
        case 'conic': {
            const p = conicPoint(v, v.shape === 'parabola' ? Math.sqrt(2 * v.p * 2) : 0.6)
            return p ? toScreen(view, p) : null
        }
    }
    return null
}

export function labelRect(ctx, o, scene, view) {
    const v = scene.val(o.id)
    const a = v && labelAnchor(o, v, view)
    if (!a) return null
    const text = labelText(o, scene)
    ctx.font = labelFont(o)
    const w = ctx.measureText(text).width
    const dx = o.labelDx ?? (v.kind === 'point' ? 7 : 6), dy = o.labelDy ?? (v.kind === 'point' ? -20 : -18)
    return { x: a.x + dx, y: a.y + dy, w: w + 2, h: 18, text }
}

const labelFont = o => o.type === 'func' || o.type === 'derivative' ? 'italic 15px "Times New Roman", "Cambria Math", serif' : 'italic 16px "Times New Roman", "Cambria Math", serif'
export function labelText(o, scene) {
    if (o.labelMode === 'value') return scene.valueText(o)
    if (o.labelMode === 'both') return `${o.name} ${scene.valueText(o)}`
    if (o.labelMode === 'caption' && o.caption) return o.caption
    if (o.type === 'func' || o.type === 'derivative') return o.type === 'derivative' ? `${scene.nm(o.of)}′` : `${o.name}(x) = ${o.expr}`
    return o.name
}

function drawLabel(ctx, o, scene, view, sel) {
    const r = labelRect(ctx, o, scene, view)
    if (!r) return
    ctx.font = labelFont(o)
    ctx.textAlign = 'left'
    ctx.textBaseline = 'top'
    ctx.lineWidth = 3
    ctx.strokeStyle = 'rgba(255,255,255,0.9)'
    ctx.lineJoin = 'round'
    ctx.strokeText(r.text, r.x, r.y)
    ctx.fillStyle = sel ? '#b45309' : (o.style?.labelColor ?? o.style?.color ?? '#111')
    ctx.fillText(r.text, r.x, r.y)
}

// ---------- 标注 ----------
export const SLIDER_W = 170
export function annotationRect(ctx, o, scene) {
    if (o.type === 'slider') {
        ctx.font = '13px "Segoe UI", "Microsoft YaHei", sans-serif'
        const tw = ctx.measureText(scene.annotationText(o)).width
        return { x: o.sx, y: o.sy, w: Math.max(SLIDER_W, tw) + 20, h: 50 }
    }
    const fs = o.style?.fontSize ?? (o.type === 'text' ? 15 : 14)
    ctx.font = `${o.style?.bold ? '600 ' : ''}${fs}px "Segoe UI", "Microsoft YaHei", sans-serif`
    const lines = scene.annotationText(o).split('\n')
    const w = Math.max(...lines.map(l => ctx.measureText(l).width))
    return { x: o.sx, y: o.sy, w: w + 16, h: lines.length * fs * 1.4 + 8, fs, lines }
}

function drawAnnotation(ctx, o, scene, view, { sel, hov }) {
    const r = annotationRect(ctx, o, scene)
    const st = o.style ?? {}
    ctx.save()
    if (o.type !== 'text' || sel || hov || st.box) {
        ctx.beginPath()
        roundRect(ctx, r.x, r.y, r.w, r.h, 6)
        ctx.fillStyle = o.type === 'text' && !st.box ? 'rgba(255,255,255,0.6)' : 'rgba(255,255,255,0.92)'
        ctx.fill()
        ctx.strokeStyle = sel ? ACCENT : hov ? 'rgba(37,99,235,0.5)' : o.type === 'text' ? 'rgba(0,0,0,0.12)' : 'rgba(15,23,42,0.14)'
        ctx.lineWidth = sel ? 2 : 1
        ctx.stroke()
    }
    if (o.type === 'slider') {
        ctx.font = '13px "Segoe UI", "Microsoft YaHei", sans-serif'
        ctx.fillStyle = '#0f172a'
        ctx.textAlign = 'left'; ctx.textBaseline = 'top'
        ctx.fillText(scene.annotationText(o), r.x + 10, r.y + 7)
        const tr = sliderTrack(o, r)
        ctx.beginPath(); ctx.moveTo(tr.x0, tr.y); ctx.lineTo(tr.x1, tr.y)
        ctx.strokeStyle = '#cbd5e1'; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.stroke()
        const k = tr.x0 + (tr.x1 - tr.x0) * ((o.value - o.min) / (o.max - o.min || 1))
        ctx.beginPath(); ctx.moveTo(tr.x0, tr.y); ctx.lineTo(k, tr.y)
        ctx.strokeStyle = st.color ?? '#2563eb'; ctx.stroke()
        ctx.beginPath(); ctx.arc(k, tr.y, 7, 0, TAU)
        ctx.fillStyle = '#fff'; ctx.fill()
        ctx.strokeStyle = st.color ?? '#2563eb'; ctx.lineWidth = 2.5; ctx.stroke()
        ctx.font = '10px "Segoe UI", sans-serif'; ctx.fillStyle = '#94a3b8'
        ctx.textAlign = 'left'; ctx.fillText(fmt(o.min, 2), tr.x0 - 2, tr.y + 8)
        ctx.textAlign = 'right'; ctx.fillText(fmt(o.max, 2), tr.x1 + 2, tr.y + 8)
        if (o.anim?.on) { ctx.fillStyle = st.color ?? '#2563eb'; ctx.beginPath(); ctx.moveTo(r.x + r.w - 16, r.y + 7); ctx.lineTo(r.x + r.w - 8, r.y + 12); ctx.lineTo(r.x + r.w - 16, r.y + 17); ctx.closePath(); ctx.fill() }
    } else {
        ctx.font = `${st.bold ? '600 ' : ''}${r.fs}px "Segoe UI", "Microsoft YaHei", sans-serif`
        ctx.fillStyle = st.color ?? '#111827'
        ctx.textAlign = 'left'; ctx.textBaseline = 'top'
        r.lines.forEach((l, i) => ctx.fillText(l, r.x + 8, r.y + 5 + i * r.fs * 1.4))
    }
    ctx.restore()
}

export function sliderTrack(o, r) {
    return { x0: r.x + 12, x1: r.x + r.w - 12, y: r.y + 33 }
}

function roundRect(ctx, x, y, w, h, r) {
    ctx.moveTo(x + r, y)
    ctx.lineTo(x + w - r, y); ctx.arc(x + w - r, y + r, r, -Math.PI / 2, 0)
    ctx.lineTo(x + w, y + h - r); ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2)
    ctx.lineTo(x + r, y + h); ctx.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI)
    ctx.lineTo(x, y + r); ctx.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5)
    ctx.closePath()
}

function drawAngleMark(ctx, scene, o, view) {
    const [a, b, c] = (o.of ?? []).map(id => scene.val(id))
    if (![a, b, c].every(p => p?.kind === 'point')) return
    const B = toScreen(view, b), A = toScreen(view, a), C = toScreen(view, c)
    const t1 = Math.atan2(A.y - B.y, A.x - B.x), t2 = Math.atan2(C.y - B.y, C.x - B.x)
    let d = t2 - t1
    while (d > Math.PI) d -= TAU
    while (d < -Math.PI) d += TAU
    const R = Math.min(24, dist(A, B) * 0.4, dist(C, B) * 0.4)
    if (R < 4) return
    const val = scene.val(o.id)?.v
    ctx.save()
    ctx.fillStyle = 'rgba(234, 88, 12, 0.16)'
    ctx.strokeStyle = '#ea580c'
    ctx.lineWidth = 1.4
    ctx.beginPath()
    if (Math.abs(val - 90) < 1e-6) {
        const u = norm(sub(A, B)), w = norm(sub(C, B)), k = R * 0.6
        ctx.moveTo(B.x + u.x * k, B.y + u.y * k)
        ctx.lineTo(B.x + (u.x + w.x) * k, B.y + (u.y + w.y) * k)
        ctx.lineTo(B.x + w.x * k, B.y + w.y * k)
        ctx.stroke()
    } else {
        ctx.moveTo(B.x, B.y)
        ctx.arc(B.x, B.y, R, t1, t1 + d, d < 0)
        ctx.closePath()
        ctx.fill()
        ctx.beginPath()
        ctx.arc(B.x, B.y, R, t1, t1 + d, d < 0)
        ctx.stroke()
    }
    ctx.restore()
}

// ---------- 追踪 ----------
// traces: [{ v, style }]，v 为某一时刻的几何值
function drawTraces(ctx, traces, view) {
    ctx.save()
    for (const t of traces) {
        ctx.globalAlpha = 0.55
        const st = t.style
        if (t.v.kind === 'point') {
            const p = toScreen(view, t.v)
            ctx.beginPath(); ctx.arc(p.x, p.y, Math.max(1.6, (st.size ?? 4) * 0.55), 0, TAU)
            ctx.fillStyle = st.color; ctx.fill()
        } else {
            drawObject(ctx, { style: { ...st, width: Math.max(1, (st.width ?? 1.8) * 0.7) } }, t.v, view, {})
        }
    }
    ctx.restore()
}

// ---------- SVG 输出 ----------
// 实现 drawScene 用到的 Canvas 2D 子集，把路径记录为 SVG 元素
export class SvgContext {
    constructor(w, h) {
        this.w = w; this.h = h
        this.out = []
        this.stack = []
        this.st = { fillStyle: '#000', strokeStyle: '#000', lineWidth: 1, globalAlpha: 1, font: '14px sans-serif', textAlign: 'left', textBaseline: 'alphabetic', dash: [], lineCap: 'butt', lineJoin: 'miter' }
        this.path = ''
        this.cx = 0; this.cy = 0
        this.measurer = document.createElement('canvas').getContext('2d')
    }
    get fillStyle() { return this.st.fillStyle } set fillStyle(v) { this.st.fillStyle = v }
    get strokeStyle() { return this.st.strokeStyle } set strokeStyle(v) { this.st.strokeStyle = v }
    get lineWidth() { return this.st.lineWidth } set lineWidth(v) { this.st.lineWidth = v }
    get globalAlpha() { return this.st.globalAlpha } set globalAlpha(v) { this.st.globalAlpha = v }
    get font() { return this.st.font } set font(v) { this.st.font = v }
    get textAlign() { return this.st.textAlign } set textAlign(v) { this.st.textAlign = v }
    get textBaseline() { return this.st.textBaseline } set textBaseline(v) { this.st.textBaseline = v }
    get lineCap() { return this.st.lineCap } set lineCap(v) { this.st.lineCap = v }
    get lineJoin() { return this.st.lineJoin } set lineJoin(v) { this.st.lineJoin = v }
    save() { this.stack.push({ ...this.st }) }
    restore() { if (this.stack.length) this.st = this.stack.pop() }
    setLineDash(d) { this.st.dash = d }
    beginPath() { this.path = '' }
    moveTo(x, y) { this.path += `M${r2(x)} ${r2(y)}`; this.cx = x; this.cy = y }
    lineTo(x, y) { this.path += `L${r2(x)} ${r2(y)}`; this.cx = x; this.cy = y }
    closePath() { this.path += 'Z' }
    rect(x, y, w, h) { this.path += `M${r2(x)} ${r2(y)}h${r2(w)}v${r2(h)}h${r2(-w)}Z` }
    arc(x, y, r, a0, a1, ccw = false) {
        let d = a1 - a0
        if (!ccw && d < 0) d += TAU * Math.ceil(-d / TAU)
        if (ccw && d > 0) d -= TAU * Math.ceil(d / TAU)
        if (Math.abs(d) >= TAU - 1e-6) {
            // 整圆：两段半圆
            const sx = x + r * Math.cos(a0), sy = y + r * Math.sin(a0)
            const mx = x - r * Math.cos(a0), my = y - r * Math.sin(a0)
            this.path += `${this.path ? 'L' : 'M'}${r2(sx)} ${r2(sy)}A${r2(r)} ${r2(r)} 0 1 1 ${r2(mx)} ${r2(my)}A${r2(r)} ${r2(r)} 0 1 1 ${r2(sx)} ${r2(sy)}`
            return
        }
        const sx = x + r * Math.cos(a0), sy = y + r * Math.sin(a0)
        const ex = x + r * Math.cos(a0 + d), ey = y + r * Math.sin(a0 + d)
        this.path += `${this.path ? 'L' : 'M'}${r2(sx)} ${r2(sy)}A${r2(r)} ${r2(r)} 0 ${Math.abs(d) > Math.PI ? 1 : 0} ${d > 0 ? 1 : 0} ${r2(ex)} ${r2(ey)}`
        this.cx = ex; this.cy = ey
    }
    fillRect(x, y, w, h) { this.out.push(`<rect x="${r2(x)}" y="${r2(y)}" width="${r2(w)}" height="${r2(h)}" fill="${this.st.fillStyle}"${this.alpha()}/>`) }
    alpha() { return this.st.globalAlpha < 1 ? ` opacity="${r2(this.st.globalAlpha)}"` : '' }
    fill() { if (this.path) this.out.push(`<path d="${this.path}" fill="${this.st.fillStyle}"${this.alpha()}/>`) }
    stroke() {
        if (!this.path) return
        const dash = this.st.dash.length ? ` stroke-dasharray="${this.st.dash.join(' ')}"` : ''
        this.out.push(`<path d="${this.path}" fill="none" stroke="${this.st.strokeStyle}" stroke-width="${r2(this.st.lineWidth)}" stroke-linecap="${this.st.lineCap}" stroke-linejoin="${this.st.lineJoin}"${dash}${this.alpha()}/>`)
    }
    measureText(t) { this.measurer.font = this.st.font; return this.measurer.measureText(t) }
    textAttrs(x, y) {
        const anchor = { left: 'start', center: 'middle', right: 'end', start: 'start', end: 'end' }[this.st.textAlign]
        const base = { top: 'hanging', middle: 'central', bottom: 'text-after-edge', alphabetic: 'alphabetic' }[this.st.textBaseline] ?? 'alphabetic'
        const m = /(italic\s+)?(\d+\s+)?(\d+(?:\.\d+)?)px\s+(.*)/.exec(this.st.font) ?? []
        const style = m[1] ? ' font-style="italic"' : ''
        const weight = m[2] ? ` font-weight="${m[2].trim()}"` : ''
        return `x="${r2(x)}" y="${r2(y)}" font-size="${m[3] ?? 14}" font-family="${esc(m[4] ?? 'sans-serif')}"${style}${weight} text-anchor="${anchor}" dominant-baseline="${base}"`
    }
    fillText(t, x, y) { this.out.push(`<text ${this.textAttrs(x, y)} fill="${this.st.fillStyle}"${this.alpha()}>${esc(t)}</text>`) }
    strokeText(t, x, y) { this.out.push(`<text ${this.textAttrs(x, y)} fill="none" stroke="${this.st.strokeStyle}" stroke-width="${this.st.lineWidth}" stroke-linejoin="round"${this.alpha()}>${esc(t)}</text>`) }
    toString() {
        return `<svg xmlns="http://www.w3.org/2000/svg" width="${this.w}" height="${this.h}" viewBox="0 0 ${this.w} ${this.h}">\n${this.out.join('\n')}\n</svg>\n`
    }
}
const r2 = v => Math.round(v * 100) / 100
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

export { isLinear }
