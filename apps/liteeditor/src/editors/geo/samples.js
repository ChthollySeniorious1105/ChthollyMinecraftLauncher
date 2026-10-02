// 几何画板示例
export function buildSample(ed, name) {
    const s = ed.scene
    const add = (def, o) => s.add(def, o)
    if (name === 'triangle') {
        ed.view.x0 = 1.2; ed.view.y0 = 1.4; ed.view.s = 62
        const A = add({ type: 'point', x: -2.6, y: -1.4 }), B = add({ type: 'point', x: 4.2, y: -1.2 }), C = add({ type: 'point', x: 0.6, y: 4.1 })
        const tri = add({ type: 'polygon', pts: [A.id, B.id, C.id] }, { style: { color: '#6366f1', fill: 0.08, width: 2.2 } })
        void tri
        const ab = add({ type: 'segment', a: A.id, b: B.id }, { style: { width: 0.01 } })
        const bc = add({ type: 'segment', a: B.id, b: C.id }, { style: { width: 0.01 } })
        const ca = add({ type: 'segment', a: C.id, b: A.id }, { style: { width: 0.01 } })
        for (const x of [ab, bc, ca]) x.hidden = true
        // 外心与外接圆
        const pb1 = add({ type: 'perpBisector', a: A.id, b: B.id }, { style: { color: '#94a3b8', dash: 'dash', width: 1 } })
        const pb2 = add({ type: 'perpBisector', a: B.id, b: C.id }, { style: { color: '#94a3b8', dash: 'dash', width: 1 } })
        pb1.hidden = pb2.hidden = true
        const O = add({ type: 'intersect', a: pb1.id, b: pb2.id }, { name: 'O', style: { color: '#dc2626' } })
        add({ type: 'circle', c: O.id, p: A.id }, { style: { color: '#dc2626', width: 1.4 } })
        // 内心与内切圆
        const bi1 = add({ type: 'angleBisector', a: B.id, b: A.id, c: C.id }, { style: { color: '#16a34a', dash: 'dot', width: 1 } })
        const bi2 = add({ type: 'angleBisector', a: A.id, b: B.id, c: C.id }, { style: { color: '#16a34a', dash: 'dot', width: 1 } })
        bi1.hidden = bi2.hidden = true
        const I = add({ type: 'intersect', a: bi1.id, b: bi2.id }, { name: 'I', style: { color: '#16a34a' } })
        const pI = add({ type: 'perpendicular', line: ab.id, point: I.id })
        pI.hidden = true
        const T = add({ type: 'intersect', a: pI.id, b: ab.id }, { name: 'T' })
        T.hidden = true
        add({ type: 'circle', c: I.id, p: T.id }, { style: { color: '#16a34a', width: 1.4 } })
        // 重心
        const Ma = add({ type: 'midpoint', a: B.id, b: C.id }, { style: { size: 3.2, color: '#64748b' } })
        const Mb = add({ type: 'midpoint', a: C.id, b: A.id }, { style: { size: 3.2, color: '#64748b' } })
        Ma.showLabel = Mb.showLabel = false
        const m1 = add({ type: 'segment', a: A.id, b: Ma.id }, { style: { color: '#ea580c', dash: 'dash', width: 1 } })
        const m2 = add({ type: 'segment', a: B.id, b: Mb.id }, { style: { color: '#ea580c', dash: 'dash', width: 1 } })
        const G = add({ type: 'intersect', a: m1.id, b: m2.id }, { name: 'G', style: { color: '#ea580c' } })
        // 垂心
        const h1 = add({ type: 'perpendicular', line: bc.id, point: A.id }, { style: { color: '#0891b2', dash: 'dot', width: 1 } })
        const h2 = add({ type: 'perpendicular', line: ca.id, point: B.id }, { style: { color: '#0891b2', dash: 'dot', width: 1 } })
        h1.hidden = h2.hidden = true
        const H = add({ type: 'intersect', a: h1.id, b: h2.id }, { name: 'H', style: { color: '#0891b2' } })
        // 欧拉线
        add({ type: 'line', a: O.id, b: H.id }, { name: '欧拉线', style: { color: '#9333ea', width: 1.6, dash: 'dashdot' } })
        add({ type: 'text', text: '三角形的五心\n拖动 A、B、C 观察：外心 O、重心 G、垂心 H 始终共线（欧拉线）' }, { style: { fontSize: 14, color: '#334155' } }).sx = 18
        s.objects.at(-1).sy = 16
        const d1 = add({ type: 'measure', m: 'distance', of: [O.id, G.id] })
        const d2 = add({ type: 'measure', m: 'distance', of: [G.id, H.id] })
        d1.sx = 18; d1.sy = 76; d2.sx = 18; d2.sy = 108
        const r = add({ type: 'calc', expr: `${d2.name} / ${d1.name}` }, { name: '比值' })
        r.sx = 18; r.sy = 140
        const ang = add({ type: 'measure', m: 'angle', of: [B.id, A.id, C.id] })
        ang.sx = 18; ang.sy = 172
    } else if (name === 'function') {
        ed.view.x0 = 0; ed.view.y0 = 0.6; ed.view.s = 58
        const a = add({ type: 'slider', value: 2, min: -4, max: 4, step: 0.1 }, { name: 'a' })
        a.sx = 18; a.sy = 16
        const b = add({ type: 'slider', value: 1, min: 0.2, max: 4, step: 0.1 }, { name: 'b' })
        b.sx = 18; b.sy = 76
        const f = add({ type: 'func', expr: 'a*sin(b*x)' }, { name: 'f', style: { color: '#2563eb', width: 2.4 } })
        const g = add({ type: 'func', expr: '0.25x^2 - 2' }, { name: 'g', style: { color: '#dc2626', width: 2.2 } })
        const P = add({ type: 'pointOn', path: f.id, t: 1 }, { name: 'P', style: { color: '#f59e0b', size: 5.5 } })
        const d = add({ type: 'derivative', of: f.id }, { style: { color: '#16a34a', width: 1.4, dash: 'dash' } })
        d.hidden = true
        const coords = add({ type: 'measure', m: 'coords', of: [P.id] })
        coords.sx = 18; coords.sy = 136
        const txt = add({ type: 'text', text: '拖动滑块 a、b 改变 f(x) = a·sin(bx)；拖动 P 沿曲线运动\nf 与 g 的交点会随参数实时更新' }, { style: { fontSize: 13.5, color: '#334155' } })
        txt.sx = 220; txt.sy = 16
        const X1 = add({ type: 'intersect', a: f.id, b: g.id, idx: 0 }, { style: { color: '#9333ea' } })
        const X2 = add({ type: 'intersect', a: f.id, b: g.id, idx: 1 }, { style: { color: '#9333ea' } })
        void X1; void X2; void g
    } else if (name === 'conic') {
        // 椭圆的定义：|PF₁| + |PF₂| = 2a；双曲线与抛物线由方程给出
        ed.view.x0 = 0; ed.view.y0 = 0; ed.view.s = 54
        const F1 = add({ type: 'point', x: -3, y: 0 }, { name: 'F₁' }), F2 = add({ type: 'point', x: 3, y: 0 }, { name: 'F₂' })
        const Q = add({ type: 'point', x: 0, y: 4 }, { name: 'Q' })
        const el = add({ type: 'ellipse', f1: F1.id, f2: F2.id, p: Q.id }, { style: { color: '#0d9488', width: 2.4, fill: 0.06 } })
        const P = add({ type: 'pointOn', path: el.id, t: 0.9 }, { name: 'P', style: { color: '#f59e0b', size: 5.5 } })
        add({ type: 'segment', a: P.id, b: F1.id }, { style: { color: '#f59e0b', width: 1.4, dash: 'dash' } })
        add({ type: 'segment', a: P.id, b: F2.id }, { style: { color: '#f59e0b', width: 1.4, dash: 'dash' } })
        const d1 = add({ type: 'measure', m: 'distance', of: [P.id, F1.id] }), d2 = add({ type: 'measure', m: 'distance', of: [P.id, F2.id] })
        d1.sx = 18; d1.sy = 76; d2.sx = 18; d2.sy = 108
        const sum = add({ type: 'calc', expr: `${d1.name} + ${d2.name}` }, { name: '和' })
        sum.sx = 18; sum.sy = 140
        const eq = add({ type: 'measure', m: 'equation', of: [el.id] })
        eq.sx = 18; eq.sy = 172
        const ec = add({ type: 'measure', m: 'eccentricity', of: [el.id] })
        ec.sx = 18; ec.sy = 204
        const hy = add({ type: 'equation', expr: 'x²/4 - y²/5 = 1' }, { name: 'h', style: { color: '#dc2626', width: 2 } })
        for (const i of [0, 1]) add({ type: 'conicPart', of: hy.id, part: 'asymptote', idx: i }, { style: { color: '#fca5a5', dash: 'dash', width: 1.1 } })
        add({ type: 'equation', expr: 'y² = 8(x + 5)' }, { name: 'p', style: { color: '#7c3aed', width: 2 } })
        add({ type: 'text', text: '圆锥曲线\n拖动 P 观察 |PF₁| + |PF₂| 保持不变；拖动焦点或 Q 改变椭圆\n在下方输入栏键入方程即可画出双曲线、抛物线' },{ style: { fontSize: 14, color: '#334155' } }).sx = 18
        s.objects.at(-1).sy = 16
    }
    s.touch()
    s.recompute(ed.view)
}
