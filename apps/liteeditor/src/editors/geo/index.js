// 几何画板编辑器
import { h, fill, toast, formDialog, colorInput, select, numberInput, clamp } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import * as store from '../../core/store.js'
import { bytesToText } from '../../core/files.js'
import { Editor, panel } from '../base.js'
import { Scene, PALETTE, exprError } from './scene.js'
import { TYPES, MEASURES, isPath, isAnnotation, projectParam, pointAt, paramRange, dist, P, intersections } from './model.js'
import { drawScene, toScreen, toWorld, viewBox, SvgContext, annotationRect, sliderTrack, drawPoint } from './render.js'
import { TOOL_GROUPS, TOOLS, hitTest, resolvePoint, accepts, slotCreatesPoint, snapWorld } from './tools.js'
import { buildSample } from './samples.js'
import { fmt } from './expr.js'
import { buildPanels, refreshPanels } from './panels.js'
import { installInteract } from './interact.js'
import { buildInputBar } from './input.js'
import { enhanceInputs, mathKeyboard } from '../../core/mathkb.js'
import { conicPoint, fromFoci, fromCenter, coefThrough, fromCoef } from './conic.js'
import { conicPolylines } from './render.js'

export class GeoEditor extends Editor {
    static kind = 'geo'

    constructor(file, app) {
        super(file, app)
        this.scene = new Scene()
        this.view = { x0: 0, y0: 0, s: 50, w: 800, h: 600 }
        this.opts = { grid: store.get('geoGrid'), axes: store.get('geoGrid'), snap: store.get('geoSnap'), showHidden: false }
        this.selected = new Set()
        this.tool = 'select'
        this.pending = []          // 当前工具已选择的对象 id（或待创建点定义）
        this.traces = []
        this.animating = new Set()
        this.buildUI()
    }

    // ---------- 界面 ----------
    buildUI() {
        // 左侧工具条：每组一个按钮，右键 / 长按展开组内工具
        this.toolBtns = new Map()
        const rail = h('div.tool-rail.geo-rail')
        for (const g of TOOL_GROUPS) {
            rail.append(h('div.tool-group-label', g.label))
            for (const t of g.tools) {
                const b = h('button.tool-btn', { title: `${t.label}${t.key && t.key !== 'Escape' ? ` (${t.key})` : ''}${t.hint ? '\n' + t.hint : ''}`, onclick: () => this.setTool(t.id) }, icon(t.icon, 18))
                this.toolBtns.set(t.id, b)
                rail.append(b)
            }
        }
        this.leftbar.append(rail)

        // 工具栏
        this.hintEl = h('div.geo-hint')
        this.tbGroup(
            this.tb('undo-2', '撤销 (Ctrl Z)', () => this.undo()),
            this.tb('redo-2', '重做 (Ctrl Y)', () => this.redo()))
        this.gridBtn = this.tb('grid-3x3', '显示网格', () => this.toggleOpt('grid'))
        this.axesBtn = this.tb('move-3d', '显示坐标轴', () => this.toggleOpt('axes'))
        this.snapBtn = this.tb('magnet', '吸附网格', () => this.toggleOpt('snap'))
        this.hiddenBtn = this.tb('eye', '显示隐藏对象', () => this.toggleOpt('showHidden'))
        this.tbGroup(this.gridBtn, this.axesBtn, this.snapBtn, this.hiddenBtn)
        this.tbGroup(
            this.tb('zoom-out', '缩小', () => this.zoomBy(1 / 1.25)),
            this.zoomLabel = h('button.chip-btn', { title: '重置视图', onclick: () => this.resetView() }, '100%'),
            this.tb('zoom-in', '放大', () => this.zoomBy(1.25)),
            this.tb('maximize', '显示全部对象', () => this.fitAll()))
        this.tbGroup(
            h('button.tb-text-btn', { title: '在输入栏中键入对象（Ctrl+I）', onclick: () => this.focusInput() }, icon('keyboard', 16), '输入'),
            h('button.tb-text-btn', { onclick: () => this.addFunctionDialog() }, icon('chart-spline', 16), '函数'),
            h('button.tb-text-btn', { onclick: () => this.addConicDialog() }, icon('ellipse', 16), '圆锥曲线'),
            h('button.tb-text-btn', { onclick: () => this.addCalcDialog() }, icon('calculator', 16), '计算'),
            h('button.tb-text-btn', { onclick: () => this.placeAt('slider') }, icon('sliders-horizontal', 16), '参数'))
        this.playBtn = h('button.tb-text-btn', { onclick: () => this.toggleAnimation() }, icon('play', 16), '动画')
        this.traceBtn = this.tb('footprints', '清除追踪痕迹', () => { this.traces = []; this.draw() })
        this.tbGroup(this.playBtn, this.traceBtn)
        this.toolbar.append(h('div.tb-flex'), this.hintEl)

        // 画布
        this.canvas = h('canvas.geo-canvas')
        this.ctx = this.canvas.getContext('2d')
        this.editBox = h('div.geo-float', { hidden: true })
        this.stage.classList.add('geo-stage')
        this.stage.append(this.canvas, this.editBox)
        this.inputBar = buildInputBar(this)
        this.stageWrap = h('div.geo-stage-wrap')
        this.stage.replaceWith(this.stageWrap)
        this.stageWrap.append(this.stage, this.inputBar)
        this.ro = new ResizeObserver(() => this.resize())
        this.ro.observe(this.stage)
        this.onDispose(() => this.ro.disconnect())
        this.bindPointer()

        buildPanels(this)
        this.updateToolUI()
    }

    menubarExtra() { return h('span.mb-extra', icon('info', 13), '双击对象编辑属性 · 右键查看更多操作') }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        if (opts.sample) buildSample(this, opts.sample)
        this.scene.recompute(this.view)
        this.afterChange()
    }

    async load(bytes) {
        const data = JSON.parse(bytesToText(bytes))
        if (data.format !== 'lgeo') throw new Error('不是有效的几何画板文件')
        this.scene.load(data.objects ?? [])
        if (data.view) Object.assign(this.view, { x0: data.view.x0, y0: data.view.y0, s: data.view.s })
        if (data.options) Object.assign(this.opts, data.options)
        this.scene.recompute(this.view)
        this.afterChange()
    }

    snapshot() {
        return JSON.stringify({ objects: this.scene.objects, sel: [...this.selected] })
    }
    restore(snap) {
        const d = JSON.parse(snap)
        this.scene.load(d.objects)
        this.scene.recompute(this.view)
        this.selected = new Set(d.sel.filter(id => this.scene.byId(id)))
        this.pending = []
        this.afterChange()
    }

    formats() {
        return [{ ext: 'lgeo', name: '几何画板', write: () => this.serialize() }]
    }
    exports() {
        return [
            { ext: 'png', name: 'PNG 图片', write: () => this.exportPNG() },
            { ext: 'svg', name: 'SVG 矢量图', write: () => this.exportSVG() },
        ]
    }
    fileItems() {
        return [{ label: '复制画板为图片', icon: 'clipboard-copy', run: () => this.copyImage() }]
    }

    serialize() {
        return JSON.stringify({
            format: 'lgeo', version: 1, app: 'LiteEditor',
            view: { x0: this.view.x0, y0: this.view.y0, s: this.view.s },
            options: this.opts,
            objects: this.scene.toJSON(),
        }, null, 1)
    }

    onShow() {
        super.onShow()
        this.resize()
    }
    onHide() {
        super.onHide()
        this.stopAnimation()
        mathKeyboard.close()
    }
    destroy() {
        this.stopAnimation()
        super.destroy()
    }

    // ---------- 绘制 ----------
    resize() {
        const r = this.stage.getBoundingClientRect()
        if (!r.width || !r.height) return
        const dpr = devicePixelRatio || 1
        this.view.w = r.width
        this.view.h = r.height
        this.canvas.width = Math.round(r.width * dpr)
        this.canvas.height = Math.round(r.height * dpr)
        this.canvas.style.width = r.width + 'px'
        this.canvas.style.height = r.height + 'px'
        this.scene.recompute(this.view)
        this.draw()
    }

    draw() {
        if (this.raf) return
        this.raf = requestAnimationFrame(() => { this.raf = 0; this.drawNow() })
    }
    drawNow() {
        const ctx = this.ctx, dpr = devicePixelRatio || 1
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
        drawScene(ctx, this.scene, this.view, {
            grid: this.opts.grid, axes: this.opts.axes,
            selected: new Set([...this.selected, ...this.pending.filter(p => typeof p === 'string')]),
            hover: this.hover, showHidden: this.opts.showHidden,
            traces: this.traces,
            preview: c => this.drawPreview(c),
        })
        this.zoomLabel.textContent = Math.round(this.view.s / 50 * 100) + '%'
    }

    // 作图过程中的预览（橡皮筋线、候选点）
    drawPreview(ctx) {
        if (this.marquee) {
            const m = this.marquee
            ctx.save()
            ctx.fillStyle = 'rgba(37, 99, 235, 0.08)'
            ctx.strokeStyle = 'rgba(37, 99, 235, 0.7)'
            ctx.setLineDash([4, 3])
            ctx.fillRect(Math.min(m.x0, m.x1), Math.min(m.y0, m.y1), Math.abs(m.x1 - m.x0), Math.abs(m.y1 - m.y0))
            ctx.strokeRect(Math.min(m.x0, m.x1) + 0.5, Math.min(m.y0, m.y1) + 0.5, Math.abs(m.x1 - m.x0), Math.abs(m.y1 - m.y0))
            ctx.restore()
        }
        const t = TOOLS[this.tool]
        if (!t?.slots || !this.mouse) return
        const pts = this.pending.map(p => this.pendingPos(p)).filter(Boolean).map(p => toScreen(this.view, p))
        const cand = this.candidate
        const cp = cand?.preview ? toScreen(this.view, cand.preview) : cand?.existing ? toScreen(this.view, this.scene.val(cand.existing.id)) : this.mouse
        ctx.save()
        ctx.strokeStyle = 'rgba(37, 99, 235, 0.75)'
        ctx.lineWidth = 1.5
        ctx.setLineDash([6, 4])
        const last = pts[pts.length - 1]
        const id = t.id
        if (last && ['segment', 'ray', 'line', 'vector', 'perpBisector', 'polygon', 'triangle', 'regular', 'translate'].includes(id)) {
            ctx.beginPath()
            if (id === 'polygon' || id === 'triangle') { ctx.moveTo(pts[0].x, pts[0].y); for (const p of pts.slice(1)) ctx.lineTo(p.x, p.y) } else ctx.moveTo(last.x, last.y)
            ctx.lineTo(cp.x, cp.y)
            ctx.stroke()
        }
        if (pts[0] && (id === 'circle' || (id === 'arc' && pts.length === 1))) {
            ctx.beginPath(); ctx.arc(pts[0].x, pts[0].y, Math.hypot(cp.x - pts[0].x, cp.y - pts[0].y), 0, Math.PI * 2); ctx.stroke()
        }
        // 圆锥曲线工具：用当前鼠标位置作为最后一个点预览
        const conicPreview = this.previewConic(id, cand, cp)
        if (conicPreview) {
            ctx.beginPath()
            for (const l of conicPolylines(conicPreview, this.view)) { ctx.moveTo(l[0].x, l[0].y); for (const p of l.slice(1)) ctx.lineTo(p.x, p.y) }
            ctx.stroke()
        }
        if (id === 'arc' && pts.length === 2) {
            const c = pts[0], r = Math.hypot(pts[1].x - c.x, pts[1].y - c.y)
            const a0 = Math.atan2(pts[1].y - c.y, pts[1].x - c.x), a1 = Math.atan2(cp.y - c.y, cp.x - c.x)
            ctx.beginPath(); ctx.arc(c.x, c.y, r, a0, a1, true); ctx.stroke()
        }
        ctx.restore()
        // 候选点
        if (cand?.def && slotCreatesPoint(this.nextSlot())) {
            drawPoint(ctx, cp, { color: cand.def.type === 'point' ? '#dc2626' : '#2563eb', size: 4 }, { hov: true })
        } else if (cand?.def?.type === 'point' && t.id === 'point') drawPoint(ctx, cp, { color: '#dc2626', size: 4 }, { hov: true })
    }

    previewConic(id, cand, cp) {
        const need = { ellipse: 3, hyperbola: 3, ellipseC: 3, hyperbolaC: 3, conic5: 5, parabola: 2 }[id]
        if (!need || this.pending.length !== need - 1) return null
        const mouse = cand?.preview ?? (cand?.existing ? this.scene.val(cand.existing.id) : toWorld(this.view, cp.x, cp.y))
        const pts = this.pending.map(p => this.pendingPos(p))
        try {
            if (id === 'ellipse' || id === 'hyperbola') return pts[0] && pts[1] ? fromFoci(id, pts[0], pts[1], mouse) : null
            if (id === 'ellipseC' || id === 'hyperbolaC') return pts[0] && pts[1] ? fromCenter(id === 'ellipseC' ? 'ellipse' : 'hyperbola', pts[0], pts[1], mouse) : null
            if (id === 'conic5') { const v = pts.every(Boolean) && coefThrough([...pts, mouse]); const c = v && fromCoef(v); return c?.kind === 'conic' ? c : null }
        } catch { return null }
        return null
    }

    pendingPos(p) {
        if (typeof p === 'string') { const v = this.scene.val(p); return v?.kind === 'point' ? v : null }
        return null
    }

    // 修改后的统一刷新
    afterChange() {
        this.scene.recompute(this.view)
        for (const id of [...this.selected]) if (!this.scene.byId(id)) this.selected.delete(id)
        refreshPanels(this)
        this.updateStatus()
        this.draw()
    }

    updateStatus() {
        const m = this.mouse ? toWorld(this.view, this.mouse.x, this.mouse.y) : null
        const n = this.scene.objects.length
        this.statusItems(
            h('span.st-item', icon(TOOLS[this.tool]?.icon ?? 'mouse-pointer-2', 13), TOOLS[this.tool]?.label ?? ''),
            h('span.st-item', `${n} 个对象`),
            this.selected.size ? h('span.st-item', `已选择 ${this.selected.size}`) : null,
            h('span.st-flex'),
            m ? h('span.st-item', `x = ${fmt(m.x, 2)}  y = ${fmt(m.y, 2)}`) : null)
    }

    toggleOpt(k) {
        this.opts[k] = !this.opts[k]
        this.updateToolUI()
        this.draw()
    }

    // ---------- 工具 ----------
    setTool(id) {
        this.tool = id
        this.pending = []
        this.candidate = null
        this.polyStart = null
        if (id !== 'select') this.selected.clear()
        // 预选对象可以直接作为工具输入（例如先选中两点再点“中点”）
        this.updateToolUI()
        refreshPanels(this)
        this.draw()
    }

    updateToolUI() {
        for (const [id, b] of this.toolBtns) b.classList.toggle('active', id === this.tool)
        this.gridBtn.classList.toggle('active', !!this.opts.grid)
        this.axesBtn.classList.toggle('active', !!this.opts.axes)
        this.snapBtn.classList.toggle('active', !!this.opts.snap)
        this.hiddenBtn.classList.toggle('active', !!this.opts.showHidden)
        const t = TOOLS[this.tool]
        const step = t?.slots ? this.stepHint() : t?.hint ?? ''
        fill(this.hintEl, t ? h('b', t.label) : null, step ? h('span', step) : null)
        this.stage.dataset.tool = this.tool
        this.updateStatus()
    }

    nextSlot() {
        const t = TOOLS[this.tool]
        if (!t?.slots) return null
        if (t.slots[0] === 'polygonPts') return 'polygonPts'
        return t.slots[this.pending.length] ?? null
    }

    stepHint() {
        const t = TOOLS[this.tool]
        const slot = this.nextSlot()
        const names = { point: '一个点', linear: '一条直线 / 线段 / 射线', round: '一个圆或圆弧', path: '一个对象（直线、圆、函数…）', polygonPts: '顶点', transformable: '要变换的对象', pointOn: '路径上的驱动点', area: '多边形或圆', eqTarget: '直线或圆', measureDistance: '线段、两个点或点与直线' }
        if (this.tool === 'point') return t.hint
        if (this.tool === 'polygon') return this.pending.length ? `已选 ${this.pending.length} 个顶点 · 单击第一个点或按 Enter 闭合 · Esc 取消` : '单击选择或创建第一个顶点'
        const n = t.slots.length
        return `第 ${this.pending.length + 1}/${n} 步：选择${names[slot] ?? ''}${t.hint ? ' · ' + t.hint : ''}`
    }

    // ---------- 创建对象 ----------
    addObject(def, opts) {
        const o = this.scene.add(def, { ...opts, view: this.view })
        if (!this.scene.val(o.id) && !['locus'].includes(o.type) && !isAnnotation(o)) {
            // 当前无解（例如两圆不相交）也保留对象，但给出提示
            toast(`${TYPES[o.type]?.label ?? '对象'} ${o.name} 当前不存在（位置关系不满足）`, 'warn')
        }
        return o
    }

    // 解析“点”输入：已有点返回 id，否则创建新点
    materialize(res) {
        if (!res) return null
        if (res.existing) return res.existing.id
        return this.addObject(res.def).id
    }

    finishTool(ids, extra = {}) {
        const t = TOOLS[this.tool]
        let made = []
        if (this.tool === 'intersect') {
            const [a, b] = ids
            // 只创建当前实际存在的交点（线段 / 圆弧范围外的不创建）
            const va = this.scene.val(a), vb = this.scene.val(b)
            const list = va && vb ? intersections(va, vb) : []
            list.forEach((p, i) => {
                if (p.ok === false) return
                const exists = this.scene.objects.some(o => o.type === 'intersect' && ((o.a === a && o.b === b) || (o.a === b && o.b === a)) && (o.idx ?? 0) === i)
                if (!exists) made.push(this.addObject({ type: 'intersect', a, b, idx: i }))
            })
            if (!made.length) toast(list.some(p => p.ok !== false) ? '这两个对象的交点已经存在' : '这两个对象没有交点')
        } else if (this.tool === 'tangent') {
            const [point, circle] = ids
            for (const idx of [0, 1]) {
                const o = this.addObject({ type: 'tangent', point, circle, idx })
                made.push(o)
            }
            made = made.filter(o => this.scene.val(o.id) || (this.scene.remove([o.id]), false))
            if (!made.length) toast('点在圆内，无法作切线', 'warn')
        } else if (this.tool === 'm-distance') {
            made.push(this.addMeasure(ids.length === 1 ? (this.scene.val(ids[0])?.kind === 'arc' ? 'arcLength' : 'length') : 'distance', ids))
        } else if (t.make) {
            const def = t.make(ids, extra)
            if (def.type === 'measure') made.push(this.addMeasure(def.m, def.of))
            else made.push(this.addObject(def))
        }
        this.pending = []
        this.candidate = null
        if (made.length) {
            this.commit(`${t.label}`)
            this.selected = new Set(made.map(o => o.id))
        }
        this.afterChange()
        this.updateToolUI()
        return made
    }

    countIntersections(a, b) {
        const va = this.scene.val(a), vb = this.scene.val(b)
        if (!va || !vb) return 1
        const lin = v => ['line', 'segment', 'ray'].includes(v.kind), rnd = v => v.kind === 'circle' || v.kind === 'arc'
        if (lin(va) && lin(vb)) return 1
        if ((lin(va) && rnd(vb)) || (rnd(va) && lin(vb)) || (rnd(va) && rnd(vb))) return 2
        return 0
    }

    // 度量结果放在画板左侧依次排列
    addMeasure(m, of) {
        const o = this.addObject({ type: 'measure', m, of })
        this.placeAnnotation(o)
        return o
    }
    placeAnnotation(o) {
        const used = this.scene.objects.filter(x => x !== o && x.sx != null)
        let y = 16
        const ctx = this.ctx
        for (;;) {
            const r = { x: 16, y, w: 180, h: 26 }
            const clash = used.find(u => { const b = annotationRect(ctx, u, this.scene); return b.x < r.x + r.w && b.x + b.w > r.x && b.y < r.y + r.h && b.y + b.h > r.y })
            if (!clash) break
            y = annotationRect(ctx, clash, this.scene).y + annotationRect(ctx, clash, this.scene).h + 6
            if (y > this.view.h - 40) { y = 16 + Math.random() * 100; break }
        }
        o.sx = 16
        o.sy = y
    }

    // 在屏幕点放置滑块 / 文本
    async placeAt(kind, s) {
        s ??= { x: 24, y: 24 }
        if (kind === 'slider') {
            const r = await formDialog({
                title: '新建参数',
                fields: [
                    { key: 'name', label: '名称', value: this.scene.objects.length ? nextFreeName(this.scene, ['a', 'b', 'k', 'm', 'n', 't', 's', 'r']) : 'a' },
                    { key: 'value', label: '初始值', type: 'number', value: 1, step: 0.1 },
                    { key: 'min', label: '最小值', type: 'number', value: -5, step: 0.1 },
                    { key: 'max', label: '最大值', type: 'number', value: 5, step: 0.1 },
                    { key: 'step', label: '步长', type: 'number', value: 0.1, step: 0.01 },
                ],
            })
            if (!r) return
            if (!validName(this, r.name)) return
            const o = this.addObject({ type: 'slider', value: clamp(r.value, Math.min(r.min, r.max), Math.max(r.min, r.max)), min: Math.min(r.min, r.max), max: Math.max(r.min, r.max), step: r.step || 0.1 }, { name: r.name })
            o.sx = s.x; o.sy = s.y
            this.commit('新建参数')
            this.selected = new Set([o.id])
            this.afterChange()
        } else if (kind === 'text') {
            const r = await formDialog({
                title: '插入文本',
                fields: [
                    { key: 'text', label: '内容', type: 'textarea', value: '', placeholder: '可以用 {表达式} 插入实时数值，例如：周长 = {m1}' },
                    { key: 'fontSize', label: '字号', type: 'number', value: 15, min: 8, max: 72 },
                ],
            })
            if (!r?.text?.trim()) return
            const o = this.addObject({ type: 'text', text: r.text }, { style: { fontSize: r.fontSize } })
            o.sx = s.x; o.sy = s.y
            this.commit('插入文本')
            this.selected = new Set([o.id])
            this.afterChange()
        }
    }

    async addFunctionDialog(edit) {
        const r = await formDialog({
            title: edit ? '编辑函数' : '新建函数图像',
            width: 460,
            fields: [
                { key: 'kind', label: '类型', type: 'select', value: edit ? edit.type : 'func', options: [['func', 'y = f(x)'], ['param', '参数方程 (x(t), y(t))'], ['polar', '极坐标 r = f(θ)']] },
                { key: 'expr', label: 'f(x) 或 r(θ)', value: edit ? (edit.expr ?? edit.rExpr ?? '') : 'sin(x)', placeholder: '例如 x^2 - 2x + 1、a*sin(x)、2cos(3t)' },
                { key: 'xExpr', label: 'x(t)', value: edit?.xExpr ?? 'cos(t)', placeholder: '仅参数方程' },
                { key: 'yExpr', label: 'y(t)', value: edit?.yExpr ?? 'sin(t)', placeholder: '仅参数方程' },
                { key: 'min', label: '定义域下限', value: String(edit?.xmin ?? edit?.tmin ?? ''), placeholder: '留空为 -∞（参数方程默认 0）' },
                { key: 'max', label: '定义域上限', value: String(edit?.xmax ?? edit?.tmax ?? ''), placeholder: '留空为 +∞（参数方程默认 2π）' },
                { key: 'note', type: 'note', label: '支持 + − × ÷ ^、sin cos tan sqrt abs ln log exp、pi、e，以及参数名称（如 a）。可以写 2x、3sin(x)、x²、√x 这样的写法；点输入框右侧的键盘图标打开数学键盘。' },
            ],
            onOpen: m => enhanceInputs(m),
        })
        if (!r) return
        const err = r.kind === 'param' ? exprError(r.xExpr) || exprError(r.yExpr) : exprError(r.expr)
        if (err) { toast('表达式有误：' + err, 'error'); return }
        const tmin = r.min === '' ? (r.kind === 'func' ? '' : '0') : r.min
        const tmax = r.max === '' ? (r.kind === 'func' ? '' : '2pi') : r.max
        let def
        if (r.kind === 'func') def = { type: 'func', expr: r.expr, xmin: tmin, xmax: tmax }
        else if (r.kind === 'param') def = { type: 'param', xExpr: r.xExpr, yExpr: r.yExpr, tmin, tmax }
        else def = { type: 'polar', rExpr: r.expr, tmin, tmax }
        if (edit) {
            for (const k of ['expr', 'xmin', 'xmax', 'xExpr', 'yExpr', 'rExpr', 'tmin', 'tmax']) delete edit[k]
            Object.assign(edit, def)
            this.scene.touch()
            this.commit('编辑函数')
        } else {
            const o = this.addObject(def)
            this.commit('新建函数')
            this.selected = new Set([o.id])
        }
        this.afterChange()
    }

    focusInput(text) {
        this.inputBox.focus()
        if (text != null) { this.inputBox.value = text; this.inputBox.dispatchEvent(new Event('input')) }
        this.inputBox.select?.()
    }

    // 按标准方程创建：中心（可选已有点或坐标）、a、b、旋转角
    async addConicDialog(edit) {
        const pts = this.scene.objects.filter(o => this.scene.val(o.id)?.kind === 'point')
        const r = await formDialog({
            title: edit ? '编辑圆锥曲线' : '新建圆锥曲线', width: 460,
            fields: [
                { key: 'shape', label: '类型', type: 'select', value: edit?.shape ?? 'ellipse', options: [['ellipse', '椭圆 x²/a² + y²/b² = 1'], ['hyperbola', '双曲线 x²/a² − y²/b² = 1'], ['parabola', '抛物线 y² = 2px']] },
                { key: 'center', label: '中心 / 顶点', type: 'select', value: edit?.c ?? '__new', options: [['__new', '新建点（下方坐标）'], ...pts.map(o => [o.id, o.name])] },
                { key: 'cx', label: '坐标 x', value: '0' },
                { key: 'cy', label: '坐标 y', value: '0' },
                { key: 'a', label: 'a（抛物线为 p）', value: edit?.a ?? '3', placeholder: '数字或表达式，可引用参数' },
                { key: 'b', label: 'b', value: edit?.b ?? '2' },
                { key: 'angle', label: '旋转角 (°)', value: edit?.angle ?? '0' },
                { type: 'note', label: '也可以直接在画板下方的输入栏键入方程，例如 x²/9 + y²/4 = 1、y² = 4x、x·y = 1。' },
            ],
            onOpen: m => enhanceInputs(m),
        })
        if (!r) return
        for (const k of ['a', 'b', 'angle']) { const err = exprError(r[k] || '0'); if (err) return toast(`${k} 有误：${err}`, 'error') }
        let c = r.center
        if (c === '__new') {
            const x = Number(r.cx), y = Number(r.cy)
            if (!Number.isFinite(x) || !Number.isFinite(y)) return toast('坐标需要是数字', 'error')
            c = this.addObject({ type: 'point', x, y }).id
        }
        const def = { type: 'conicStd', shape: r.shape, c, a: String(r.a).trim(), b: String(r.b || '1').trim(), angle: String(r.angle || '0').trim() }
        if (edit) { Object.assign(edit, def); this.scene.touch(); this.commit('编辑圆锥曲线') }
        else { const o = this.addObject(def); this.commit('新建圆锥曲线'); this.selected = new Set([o.id]) }
        this.afterChange()
    }

    // 圆锥曲线的焦点、顶点、渐近线、准线等
    addConicPart(of, part) {
        const v = this.scene.val(of)
        if (v?.kind !== 'conic') return
        const n = { focus: v.shape === 'parabola' ? 1 : 2, vertex: v.shape === 'parabola' ? 1 : v.shape === 'ellipse' ? 4 : 2, asymptote: v.shape === 'hyperbola' ? 2 : 0, directrix: v.shape === 'parabola' ? 1 : 2, center: 1, majorAxis: 1, minorAxis: 1 }[part]
        const made = []
        for (let i = 0; i < n; i++) {
            if (this.scene.objects.some(o => o.type === 'conicPart' && o.of === of && o.part === part && (o.idx ?? 0) === i)) continue
            const style = ['asymptote', 'directrix', 'majorAxis', 'minorAxis'].includes(part) ? { color: '#94a3b8', dash: 'dash', width: 1.2 } : { color: '#0d9488' }
            const o = this.addObject({ type: 'conicPart', of, part, idx: i }, { style })
            if (!this.scene.val(o.id)) { this.scene.remove([o.id]); continue }
            made.push(o)
        }
        if (!made.length) return toast('已经存在')
        this.commit({ focus: '焦点', vertex: '顶点', asymptote: '渐近线', directrix: '准线', center: '中心', majorAxis: '长轴', minorAxis: '短轴' }[part])
        this.selected = new Set(made.map(o => o.id))
        this.afterChange()
    }

    async addCalcDialog(edit) {
        const nums = this.scene.objects.filter(o => ['measure', 'calc', 'slider'].includes(o.type) && Number.isFinite(this.scene.val(o.id)?.v))
        const r = await formDialog({
            title: edit ? '编辑计算' : '新建计算',
            width: 460,
            fields: [
                { key: 'name', label: '名称', value: edit?.name ?? nextFreeName(this.scene, ['v1', 'v2', 'v3', 'v4', 'v5', 'v6']) },
                { key: 'expr', label: '表达式', value: edit?.expr ?? '', placeholder: nums.length ? `例如 ${nums[0].name} * 2` : '例如 sqrt(2) * pi' },
                { key: 'note', type: 'note', label: nums.length ? '可用的数值：' + nums.map(o => `${o.name} = ${this.scene.valueText(o)}`).join('，') : '先用度量工具测量长度、角度或面积，然后在表达式中引用它们的名称。' },
            ],
            onOpen: m => enhanceInputs(m),
        })
        if (!r) return
        const err = exprError(r.expr)
        if (err) { toast('表达式有误：' + err, 'error'); return }
        if (!edit && !validName(this, r.name)) return
        if (edit) {
            if (r.name !== edit.name && !validName(this, r.name)) return
            renameRefs(this.scene, edit.name, r.name)
            edit.name = r.name
            edit.expr = r.expr
            this.scene.touch()
            this.commit('编辑计算')
        } else {
            const o = this.addObject({ type: 'calc', expr: r.expr }, { name: r.name })
            this.placeAnnotation(o)
            this.commit('新建计算')
            this.selected = new Set([o.id])
        }
        this.afterChange()
    }

    // ---------- 视图 ----------
    zoomAt(sx, sy, k) {
        const w = toWorld(this.view, sx, sy)
        this.view.s = clamp(this.view.s * k, 2, 20000)
        const w2 = toWorld(this.view, sx, sy)
        this.view.x0 += w.x - w2.x
        this.view.y0 += w.y - w2.y
        this.scene.recompute(this.view)
        this.draw()
    }
    zoomBy(k) { this.zoomAt(this.view.w / 2, this.view.h / 2, k) }
    resetView() { Object.assign(this.view, { x0: 0, y0: 0, s: 50 }); this.scene.recompute(this.view); this.draw() }

    fitAll() {
        const pts = []
        for (const o of this.scene.objects) {
            const v = this.scene.val(o.id)
            if (!v || o.hidden) continue
            if (v.kind === 'point') pts.push(v)
            else if (v.kind === 'segment') pts.push(v.p, v.q)
            else if (v.kind === 'circle' || v.kind === 'arc') pts.push(P(v.c.x - v.r, v.c.y - v.r), P(v.c.x + v.r, v.c.y + v.r))
            else if (v.kind === 'polygon') pts.push(...v.pts)
            else if (v.kind === 'conic') {
                if (v.shape === 'ellipse') for (let i = 0; i < 16; i++) pts.push(conicPoint(v, i / 16 * Math.PI * 2))
                else pts.push(v.c, ...[-0.9, 0.9].map(t => conicPoint(v, t)).filter(Boolean))
            }
        }
        if (!pts.length) return this.resetView()
        const xs = pts.map(p => p.x), ys = pts.map(p => p.y)
        const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys)
        const s = Math.min((this.view.w - 120) / Math.max(1e-6, x1 - x0), (this.view.h - 120) / Math.max(1e-6, y1 - y0))
        Object.assign(this.view, { x0: (x0 + x1) / 2, y0: (y0 + y1) / 2, s: clamp(s, 5, 2000) })
        this.scene.recompute(this.view)
        this.draw()
    }

    // ---------- 选择与编辑 ----------
    selectOnly(ids) { this.selected = new Set(ids); refreshPanels(this); this.draw() }

    deleteSelected() {
        if (!this.selected.size) return
        const ids = [...this.selected]
        const dep = this.scene.descendants(ids).length
        const n = this.scene.remove(ids)
        this.selected.clear()
        this.commit(`删除 ${n} 个对象`)
        this.afterChange()
        if (dep) toast(`同时删除了 ${dep} 个依赖对象`, 'info')
    }

    setHidden(ids, hidden) {
        for (const id of ids) { const o = this.scene.byId(id); if (o) o.hidden = hidden }
        if (hidden) for (const id of ids) this.selected.delete(id)
        this.commit(hidden ? '隐藏' : '显示')
        this.afterChange()
    }

    toggleTrace(ids) {
        const on = !ids.every(id => this.scene.byId(id)?.trace)
        for (const id of ids) { const o = this.scene.byId(id); if (o) o.trace = on }
        this.commit(on ? '开启追踪' : '关闭追踪')
        this.afterChange()
    }

    // 记录追踪残影
    recordTraces() {
        for (const o of this.scene.objects) {
            if (!o.trace || o.hidden) continue
            const v = this.scene.val(o.id)
            if (!v || ['number', 'text', 'func'].includes(v.kind)) continue
            this.traces.push({ v: structuredClone(v), style: o.style })
        }
        if (this.traces.length > 6000) this.traces.splice(0, this.traces.length - 6000)
    }

    // ---------- 动画 ----------
    toggleAnimation() {
        if (this.animating.size) return this.stopAnimation()
        let ids = [...this.selected].filter(id => { const o = this.scene.byId(id); return o?.type === 'pointOn' || o?.type === 'slider' })
        if (!ids.length) ids = this.scene.objects.filter(o => o.anim?.on).map(o => o.id)
        if (!ids.length) ids = this.scene.objects.filter(o => o.type === 'slider' || o.type === 'pointOn').slice(0, 1).map(o => o.id)
        if (!ids.length) return toast('请先选中一个路径上的点或参数滑块')
        this.startAnimation(ids)
    }
    startAnimation(ids) {
        this.stopAnimation()
        this.animating = new Set(ids)
        this.animBase = this.snapshot()
        let last = performance.now()
        const tick = now => {
            const dt = Math.min(0.05, (now - last) / 1000)
            last = now
            for (const id of this.animating) {
                const o = this.scene.byId(id)
                if (!o) { this.animating.delete(id); continue }
                const speed = o.anim?.speed ?? 1
                if (o.type === 'slider') {
                    const span = o.max - o.min || 1
                    o.anim ??= { dir: 1 }
                    o.anim.dir ??= 1
                    o.value += o.anim.dir * span * 0.25 * speed * dt
                    if (o.value >= o.max) { o.value = o.max; o.anim.dir = -1 }
                    if (o.value <= o.min) { o.value = o.min; o.anim.dir = 1 }
                } else {
                    const path = this.scene.val(o.path)
                    if (!path) continue
                    const [t0, t1] = paramRange(path, viewBox(this.view))
                    const span = t1 - t0
                    o.anim ??= { dir: 1 }
                    o.anim.dir ??= 1
                    o.t += o.anim.dir * span * 0.12 * speed * dt
                    if (path.kind === 'circle') { if (o.t > Math.PI) o.t -= Math.PI * 2 }
                    else if (path.kind === 'polygon') { if (o.t >= t1) o.t -= span }
                    else if (o.t >= t1) { o.t = t1; o.anim.dir = -1 } else if (o.t <= t0) { o.t = t0; o.anim.dir = 1 }
                }
            }
            this.scene.recompute(this.view)
            this.recordTraces()
            this.drawNow()
            refreshPanels(this, { values: true })
            if (this.animating.size) this.animRaf = requestAnimationFrame(tick)
        }
        this.animRaf = requestAnimationFrame(tick)
        fill(this.playBtn, icon('pause', 16), '停止')
        this.playBtn.classList.add('active')
    }
    stopAnimation() {
        if (!this.animating?.size) return
        cancelAnimationFrame(this.animRaf)
        this.animating = new Set()
        fill(this.playBtn, icon('play', 16), '动画')
        this.playBtn.classList.remove('active')
        this.commit('动画')
        this.afterChange()
    }

    // ---------- 导出 ----------
    renderTo(ctx, w, h, scale = 1) {
        const view = { ...this.view, w: w / scale, h: h / scale }
        ctx.setTransform(scale, 0, 0, scale, 0, 0)
        drawScene(ctx, this.scene, view, { grid: this.opts.grid, axes: this.opts.axes, traces: this.traces })
    }
    async exportPNG() {
        const scale = 2
        const c = document.createElement('canvas')
        c.width = Math.round(this.view.w * scale)
        c.height = Math.round(this.view.h * scale)
        this.renderTo(c.getContext('2d'), c.width, c.height, scale)
        const blob = await new Promise(r => c.toBlob(r, 'image/png'))
        return new Uint8Array(await blob.arrayBuffer())
    }
    exportSVG() {
        const ctx = new SvgContext(Math.round(this.view.w), Math.round(this.view.h))
        drawScene(ctx, this.scene, this.view, { grid: this.opts.grid, axes: this.opts.axes, traces: this.traces })
        return ctx.toString()
    }
    async copyImage() {
        const bytes = await this.exportPNG()
        await navigator.clipboard.write([new ClipboardItem({ 'image/png': new Blob([bytes], { type: 'image/png' }) })])
        toast('已复制到剪贴板', 'success')
    }
}

installInteract(GeoEditor)

// ---------- 辅助 ----------
export function nextFreeName(scene, seq) {
    for (const n of seq) if (!scene.byName(n)) return n
    for (let i = 1; ; i++) if (!scene.byName(seq[0] + i)) return seq[0] + i
}
const RESERVED = new Set(['x', 'y', 't', 'e', 'pi', 'π', 'θ', 'theta', 'tau'])
export function validName(ed, name, self) {
    name = String(name ?? '').trim()
    if (!/^[\p{L}_][\p{L}\p{N}_']*$/u.test(name)) { toast('名称只能包含字母、数字与下划线，且不能以数字开头', 'error'); return false }
    if (RESERVED.has(name)) { toast(`“${name}” 是保留名称`, 'error'); return false }
    const other = ed.scene.byName(name)
    if (other && other !== self) { toast(`名称 “${name}” 已被使用`, 'error'); return false }
    return true
}
// 重命名时更新表达式中的引用
export function renameRefs(scene, from, to) {
    if (!from || from === to) return
    const re = new RegExp(`(?<![\\p{L}\\p{N}_'])${from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\p{L}\\p{N}_'])`, 'gu')
    for (const o of scene.objects) {
        for (const f of TYPES[o.type]?.exprs ?? []) if (typeof o[f] === 'string') o[f] = o[f].replace(re, to)
        if (o.type === 'text') o.text = o.text.replace(/\{([^{}]+)\}/g, (_, s) => `{${s.replace(re, to)}}`)
    }
}

export { PALETTE, MEASURES, isPath, projectParam, pointAt, dist, hitTest, resolvePoint, accepts, slotCreatesPoint, snapWorld, sliderTrack, annotationRect, toWorld, toScreen, contextMenu, colorInput, select, numberInput, panel }
