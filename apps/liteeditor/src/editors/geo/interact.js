// 几何画板：鼠标交互、快捷键、菜单
import { h, toast, formDialog, clamp } from '../../core/dom.js'
import { contextMenu } from '../../core/menu.js'
import { validName, renameRefs } from './index.js'
import { TYPES, MEASURES, isPath, isAnnotation, projectParam, dist, P } from './model.js'
import { toWorld, toScreen, annotationRect, sliderTrack, labelAnchor } from './render.js'
import { TOOL_GROUPS, TOOLS, hitTest, resolvePoint, accepts, slotCreatesPoint, snapWorld } from './tools.js'
import { PALETTE } from './scene.js'
import { editProperties, refreshPanels } from './panels.js'
import { exprError, equationError } from './scene.js'
import { enhanceInputs } from '../../core/mathkb.js'
const exprErrorOf = Object.assign(src => exprError(src), { eq: equationError })

// 由 index.js 在类定义之后调用（避免循环导入时访问未初始化的类）
export function installInteract(GeoEditor) {
const proto = GeoEditor.prototype

proto.localPos = function (e) {
    const r = this.canvas.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
}

proto.bindPointer = function () {
    const c = this.canvas
    this.listen(c, 'pointerdown', e => this.onDown(e))
    this.listen(c, 'pointermove', e => this.onMove(e))
    this.listen(c, 'pointerup', e => this.onUp(e))
    this.listen(c, 'pointerleave', () => { this.mouse = null; this.hover = null; this.candidate = null; this.draw(); this.updateStatus() })
    this.listen(c, 'dblclick', e => this.onDbl(e))
    this.listen(c, 'contextmenu', e => this.onContext(e))
    // 滚轮以鼠标为中心缩放；Shift + 滚轮平移
    this.listen(c, 'wheel', e => {
        e.preventDefault()
        const s = this.localPos(e)
        if (e.shiftKey) {
            this.view.x0 += (e.deltaY || e.deltaX) / this.view.s
            this.scene.recompute(this.view)
            this.draw()
        } else this.zoomAt(s.x, s.y, Math.exp(-e.deltaY * 0.0018))
    }, { passive: false })
    this.listen(window, 'keyup', e => { if (e.code === 'Space') { this.spaceDown = false; this.stage.classList.remove('panning') } })
}

proto.hit = function (s, filter) {
    return hitTest(this.scene, this.view, s, { ctx: this.ctx, filter, showHidden: this.opts.showHidden })
}

proto.onDown = function (e) {
    this.canvas.setPointerCapture(e.pointerId)
    const s = this.localPos(e)
    this.downAt = s
    this.moved = false
    // 平移：抓手工具、空格、中键、右键拖动
    if (this.tool === 'pan' || this.spaceDown || e.button === 1) {
        this.drag = { kind: 'pan', x: s.x, y: s.y, x0: this.view.x0, y0: this.view.y0 }
        this.stage.classList.add('panning')
        return
    }
    if (e.button === 2) { this.drag = { kind: 'maybe-pan', x: s.x, y: s.y, x0: this.view.x0, y0: this.view.y0 }; return }
    if (e.button !== 0) return
    if (this.tool === 'select') return this.selectDown(e, s)
    if (this.tool === 'text' || this.tool === 'slider') return this.placeAt(this.tool, s).then(() => this.setTool('select'))
    this.toolDown(e, s)
}

proto.selectDown = function (e, s) {
    const hit = this.hit(s)
    if (!hit) {
        if (!e.shiftKey && !e.ctrlKey) this.selected.clear()
        this.marquee = { x0: s.x, y0: s.y, x1: s.x, y1: s.y, add: e.shiftKey || e.ctrlKey, base: new Set(this.selected) }
        this.drag = { kind: 'marquee' }
        this.draw()
        return
    }
    const o = hit.obj
    if (e.shiftKey || e.ctrlKey) {
        if (this.selected.has(o.id)) this.selected.delete(o.id)
        else this.selected.add(o.id)
    } else if (!this.selected.has(o.id)) this.selected = new Set([o.id])
    this.editorPanelsDirty = true
    // 拖动的目标
    if (hit.part === 'slider') {
        this.drag = { kind: 'slider', o, rect: hit.rect }
        this.dragSlider(s)
    } else if (hit.part === 'annotation') {
        this.drag = { kind: 'annotation', items: [...this.selected].map(id => this.scene.byId(id)).filter(x => x?.sx != null).map(x => ({ o: x, sx: x.sx, sy: x.sy })), x: s.x, y: s.y }
    } else if (hit.part === 'label') {
        const v = this.scene.val(o.id)
        const a = labelAnchor(o, v, this.view)
        this.drag = { kind: 'label', o, dx: (o.labelDx ?? 7) - (s.x - a.x), dy: (o.labelDy ?? -20) - (s.y - a.y), a }
    } else {
        this.drag = this.makeMoveDrag(o, s)
    }
    this.refreshSoon()
    this.draw()
}

// 移动对象：自由点直接移动；路径上的点沿路径；由自由点定义的对象整体平移其自由祖先点
proto.makeMoveDrag = function (o, s) {
    const w = toWorld(this.view, s.x, s.y)
    if (o.type === 'point') {
        const ids = [...this.selected].map(id => this.scene.byId(id)).filter(x => x?.type === 'point')
        return { kind: 'points', items: (ids.length ? ids : [o]).map(p => ({ o: p, x: p.x, y: p.y })), w, main: o }
    }
    if (o.type === 'pointOn') return { kind: 'pointOn', o }
    // 其他对象：找到全部自由祖先点，平移它们
    const roots = new Set()
    for (const id of this.selected) {
        const sel = this.scene.byId(id)
        if (!sel) continue
        if (sel.type === 'point') roots.add(sel)
        for (const a of this.scene.ancestors(id)) { const ao = this.scene.byId(a); if (ao?.type === 'point') roots.add(ao) }
    }
    if (!roots.size) return { kind: 'none' }
    return { kind: 'points', items: [...roots].map(p => ({ o: p, x: p.x, y: p.y })), w, main: null }
}

proto.dragSlider = function (s) {
    const { o } = this.drag
    const r = annotationRect(this.ctx, o, this.scene)
    const tr = sliderTrack(o, r)
    let v = o.min + (o.max - o.min) * clamp((s.x - tr.x0) / (tr.x1 - tr.x0), 0, 1)
    const step = o.step || 0.01
    v = Math.round(v / step) * step
    o.value = Number(clamp(v, o.min, o.max).toFixed(10))
    this.moved = true
    this.liveUpdate()
}

proto.liveUpdate = function () {
    this.scene.recompute(this.view)
    this.recordTraces()
    this.draw()
    this.refreshSoon(true)
}
proto.refreshSoon = function (valuesOnly) {
    if (this.refreshRaf) return
    this.refreshRaf = requestAnimationFrame(() => {
        this.refreshRaf = 0
        refreshPanels(this, { values: valuesOnly })
        this.updateStatus()
    })
}

proto.onMove = function (e) {
    const s = this.localPos(e)
    this.mouse = s
    const d = this.drag
    if (d && this.downAt && Math.hypot(s.x - this.downAt.x, s.y - this.downAt.y) > 2) this.moved = true
    if (!d) {
        // 悬停高亮
        if (this.tool === 'select' || this.tool === 'pan') {
            const hit = this.tool === 'select' ? this.hit(s) : null
            const id = hit?.obj.id ?? null
            if (id !== this.hover) { this.hover = id; this.draw() }
            this.canvas.style.cursor = this.tool === 'pan' ? 'grab' : hit ? (hit.part === 'slider' ? 'ew-resize' : 'move') : 'default'
        } else this.toolHover(s)
        this.updateStatus()
        return
    }
    switch (d.kind) {
        case 'pan': case 'maybe-pan':
            if (d.kind === 'maybe-pan' && !this.moved) return
            d.kind = 'pan'
            this.stage.classList.add('panning')
            this.view.x0 = d.x0 - (s.x - d.x) / this.view.s
            this.view.y0 = d.y0 + (s.y - d.y) / this.view.s
            this.scene.recompute(this.view)
            this.draw()
            return
        case 'marquee': {
            const m = this.marquee
            m.x1 = s.x; m.y1 = s.y
            const x0 = Math.min(m.x0, m.x1), x1 = Math.max(m.x0, m.x1), y0 = Math.min(m.y0, m.y1), y1 = Math.max(m.y0, m.y1)
            const inside = []
            for (const o of this.scene.objects) {
                if (o.hidden && !this.opts.showHidden) continue
                const v = this.scene.val(o.id)
                if (!v) continue
                const pts = o.sx != null ? [{ x: o.sx, y: o.sy }] : v.kind === 'point' ? [toScreen(this.view, v)] : v.kind === 'segment' ? [toScreen(this.view, v.p), toScreen(this.view, v.q)] : v.kind === 'polygon' ? v.pts.map(p => toScreen(this.view, p)) : v.kind === 'circle' ? [toScreen(this.view, P(v.c.x - v.r, v.c.y - v.r)), toScreen(this.view, P(v.c.x + v.r, v.c.y + v.r))] : null
                if (pts && pts.every(p => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1)) inside.push(o.id)
            }
            this.selected = new Set([...(m.add ? m.base : []), ...inside])
            this.draw()
            return
        }
        case 'points': {
            if (!this.moved) return
            let w = toWorld(this.view, s.x, s.y)
            // 单点拖动时吸附网格
            if (d.main && d.items.length === 1 && this.opts.snap && !e.altKey) w = snapWorld(this.view, s)
            const dx = w.x - d.w.x, dy = w.y - d.w.y
            for (const it of d.items) {
                if (d.main && d.items.length === 1) { it.o.x = w.x; it.o.y = w.y }
                else { it.o.x = it.x + dx; it.o.y = it.y + dy }
            }
            this.liveUpdate()
            return
        }
        case 'pointOn': {
            const path = this.scene.val(d.o.path)
            if (!path) return
            d.o.t = projectParam(path, toWorld(this.view, s.x, s.y))
            this.liveUpdate()
            return
        }
        case 'slider': return this.dragSlider(s)
        case 'annotation':
            for (const it of d.items) { it.o.sx = Math.round(it.sx + s.x - d.x); it.o.sy = Math.round(it.sy + s.y - d.y) }
            this.draw()
            return
        case 'label': {
            const a = labelAnchor(d.o, this.scene.val(d.o.id), this.view)
            d.o.labelDx = clamp(s.x - a.x + d.dx, -60, 60)
            d.o.labelDy = clamp(s.y - a.y + d.dy, -60, 60)
            this.draw()
            return
        }
    }
}

proto.onUp = function (e) {
    const d = this.drag
    this.drag = null
    this.stage.classList.remove('panning')
    if (!d) return
    if (d.kind === 'maybe-pan') return  // 右键单击：由 contextmenu 处理
    if (d.kind === 'marquee') { this.marquee = null; this.afterChange(); return }
    if (this.moved) {
        const label = { points: '移动', pointOn: '移动', slider: '调整参数', annotation: '移动标注', label: '移动标签' }[d.kind]
        if (label) {
            this.commit(label)
            this.afterChange()
        }
        if (d.kind === 'pan') this.suppressContext = true
    } else this.afterChange()
    void e
}

proto.onDbl = function (e) {
    if (this.tool !== 'select') return
    const hit = this.hit(this.localPos(e))
    if (!hit) return
    const o = hit.obj
    if (o.type === 'func' || o.type === 'param' || o.type === 'polar') return this.addFunctionDialog(o)
    if (o.type === 'calc') return this.addCalcDialog(o)
    if (o.type === 'conicStd') return this.addConicDialog(o)
    if (o.type === 'equation') return this.focusInput(o.expr)
    editProperties(this, o)
}

proto.onContext = function (e) {
    e.preventDefault()
    if (this.suppressContext) { this.suppressContext = false; return }
    const s = this.localPos(e)
    const hit = this.hit(s)
    if (hit && !this.selected.has(hit.obj.id)) { this.selected = new Set([hit.obj.id]); this.afterChange() }
    const ids = [...this.selected]
    if (hit && ids.length) return contextMenu(e, this.objectMenu(ids))
    const w = toWorld(this.view, s.x, s.y)
    contextMenu(e, [
        { label: '在此处创建点', icon: 'dot', run: () => { const o = this.addObject({ type: 'point', x: w.x, y: w.y }); this.commit('创建点'); this.selectOnly([o.id]); this.afterChange() } },
        { label: '在此处插入文本', icon: 'type', run: () => this.placeAt('text', s) },
        { label: '在此处插入参数', icon: 'sliders-horizontal', run: () => this.placeAt('slider', s) },
        '-',
        { label: '显示网格', checked: () => !!this.opts.grid, run: () => this.toggleOpt('grid') },
        { label: '显示坐标轴', checked: () => !!this.opts.axes, run: () => this.toggleOpt('axes') },
        { label: '吸附网格', checked: () => !!this.opts.snap, run: () => this.toggleOpt('snap') },
        { label: '显示隐藏对象', checked: () => !!this.opts.showHidden, run: () => this.toggleOpt('showHidden') },
        '-',
        { label: '显示全部对象', icon: 'maximize', run: () => this.fitAll() },
        { label: '重置视图', icon: 'locate-fixed', run: () => this.resetView() },
        { label: '清除追踪痕迹', icon: 'footprints', disabled: () => !this.traces.length, run: () => { this.traces = []; this.draw() } },
        '-',
        { label: '全选', key: 'Ctrl+A', run: () => this.selectOnly(this.scene.objects.filter(o => !o.hidden).map(o => o.id)) },
    ])
}

proto.objectMenu = function (ids) {
    const objs = ids.map(id => this.scene.byId(id)).filter(Boolean)
    const one = objs.length === 1 ? objs[0] : null
    const colors = PALETTE.map(c => ({ label: c, swatch: c, run: () => { for (const o of objs) o.style.color = c; this.commit('颜色'); this.afterChange() } }))
    const anim = objs.filter(o => o.type === 'pointOn' || o.type === 'slider')
    return [
        one ? { header: `${TYPES[one.type]?.label ?? ''} ${one.name}` } : { header: `${objs.length} 个对象` },
        one ? { label: '属性…', icon: 'settings-2', run: () => editProperties(this, one) } : null,
        one && ['func', 'param', 'polar'].includes(one.type) ? { label: '编辑表达式…', icon: 'chart-spline', run: () => this.addFunctionDialog(one) } : null,
        one && one.type === 'calc' ? { label: '编辑计算…', icon: 'calculator', run: () => this.addCalcDialog(one) } : null,
        one && one.type === 'conicStd' ? { label: '编辑参数…', icon: 'ellipse', run: () => this.addConicDialog(one) } : null,
        one && one.type === 'equation' ? { label: '编辑方程…', icon: 'square-function', run: () => this.editEquation(one) } : null,
        one && this.scene.val(one.id)?.kind === 'conic' ? { label: '特征元素', icon: 'orbit', submenu: this.conicPartItems(one) } : null,
        one ? { label: '重命名…', icon: 'pencil', run: () => this.renameDialog(one) } : null,
        { label: '颜色', icon: 'palette', submenu: colors },
        '-',
        { label: '显示标签', checked: () => objs.every(o => o.showLabel), run: () => { const on = !objs.every(o => o.showLabel); objs.forEach(o => (o.showLabel = on)); this.commit('标签'); this.afterChange() } },
        { label: '追踪', icon: 'footprints', checked: () => objs.every(o => o.trace), run: () => this.toggleTrace(ids) },
        anim.length ? { label: this.animating.size ? '停止动画' : '播放动画', icon: this.animating.size ? 'pause' : 'play', run: () => (this.animating.size ? this.stopAnimation() : this.startAnimation(anim.map(o => o.id))) } : null,
        objs.every(o => o.hidden) ? { label: '显示', icon: 'eye', run: () => this.setHidden(ids, false) } : { label: '隐藏', icon: 'eye-off', key: 'Ctrl+H', run: () => this.setHidden(ids, true) },
        '-',
        { label: '度量', icon: 'ruler', submenu: this.measureItems(ids) },
        '-',
        { label: '删除', icon: 'trash-2', danger: true, key: 'Delete', run: () => this.deleteSelected() },
    ]
}

// 根据当前选中对象给出可用的度量
proto.measureItems = function (ids = [...this.selected]) {
    const vs = ids.map(id => this.scene.val(id))
    const kinds = vs.map(v => v?.kind)
    const add = (m, of) => () => { const o = this.addMeasure(m, of); this.commit('度量 ' + MEASURES[m].label); this.selectOnly([o.id]); this.afterChange() }
    const items = []
    const lin = k => ['line', 'segment', 'ray'].includes(k)
    if (ids.length === 2 && kinds.every(k => k === 'point')) items.push({ label: '距离', run: add('distance', ids) })
    if (ids.length === 2 && ((kinds[0] === 'point' && lin(kinds[1])) || (lin(kinds[0]) && kinds[1] === 'point'))) items.push({ label: '点到直线的距离', run: add('distance', ids) })
    if (ids.length === 3 && kinds.every(k => k === 'point')) items.push({ label: '角度（第二个点为顶点）', run: add('angle', ids) })
    if (ids.length === 1) {
        const k = kinds[0]
        if (k === 'point') items.push({ label: '坐标', run: add('coords', ids) })
        if (k === 'segment') items.push({ label: '长度', run: add('length', ids) })
        if (lin(k)) items.push({ label: '斜率', run: add('slope', ids) }, { label: '方程', run: add('equation', ids) })
        if (k === 'circle') items.push({ label: '半径', run: add('radius', ids) }, { label: '周长', run: add('perimeter', ids) }, { label: '面积', run: add('area', ids) }, { label: '方程', run: add('equation', ids) })
        if (k === 'arc') items.push({ label: '半径', run: add('radius', ids) }, { label: '弧长', run: add('arcLength', ids) }, { label: '弧度角', run: add('arcAngle', ids) }, { label: '扇形面积', run: add('area', ids) })
        if (k === 'polygon') items.push({ label: '面积', run: add('area', ids) }, { label: '周长', run: add('perimeter', ids) })
        if (k === 'conic') {
            const sh = vs[0].shape
            items.push({ label: '方程', run: add('equation', ids) }, { label: '离心率', run: add('eccentricity', ids) })
            if (sh !== 'parabola') items.push({ label: '焦距', run: add('focal', ids) })
            if (sh === 'ellipse') items.push({ label: '面积', run: add('area', ids) }, { label: '周长', run: add('perimeter', ids) })
        }
    }
    if (!items.length) items.push({ label: '请选择：两点、线段、三个点、圆、多边形…', disabled: true })
    return items
}

proto.conicPartItems = function (o) {
    const v = this.scene.val(o.id)
    const it = (label, part) => ({ label, run: () => this.addConicPart(o.id, part) })
    return [
        v.shape !== 'parabola' ? it('中心', 'center') : null,
        it('焦点', 'focus'), it('顶点', 'vertex'),
        v.shape === 'hyperbola' ? it('渐近线', 'asymptote') : null,
        it('准线', 'directrix'),
        it(v.shape === 'hyperbola' ? '实轴所在直线' : v.shape === 'parabola' ? '对称轴' : '长轴所在直线', 'majorAxis'),
        v.shape !== 'parabola' ? it(v.shape === 'hyperbola' ? '虚轴所在直线' : '短轴所在直线', 'minorAxis') : null,
    ]
}

proto.editEquation = async function (o) {
    const r = await formDialog({ title: '编辑方程', width: 460, fields: [{ key: 'expr', label: '方程', value: o.expr }, { type: 'note', label: '例如 x²/9 + y²/4 = 1、y² = 4x、x³ + y³ = 3xy' }], onOpen: m => enhanceInputs(m) })
    if (!r) return
    const err = exprErrorOf.eq(r.expr)
    if (err) return toast('方程有误：' + err, 'error')
    o.expr = r.expr
    this.scene.touch()
    this.commit('编辑方程')
    this.afterChange()
}

proto.renameDialog = async function (o) {
    const r = await formDialog({ title: '重命名', fields: [{ key: 'name', label: '名称', value: o.name }] })
    if (!r || r.name === o.name) return
    if (!validName(this, r.name, o)) return
    renameRefs(this.scene, o.name, r.name)
    o.name = r.name
    this.scene.touch()
    this.commit('重命名')
    this.afterChange()
}

// ---------- 作图工具 ----------
proto.toolHover = function (s) {
    const slot = this.nextSlot()
    this.candidate = null
    let hover = null
    if (this.tool === 'point' || slotCreatesPoint(slot)) {
        this.candidate = resolvePoint(this.scene, this.view, s, { snap: this.opts.snap })
        hover = this.candidate?.existing?.id ?? null
    } else if (slot) {
        const hit = this.hit(s, (o, v) => accepts(slot, o, v))
        hover = hit?.obj.id ?? null
    }
    this.hover = hover
    this.canvas.style.cursor = hover || this.candidate ? 'pointer' : 'crosshair'
    this.draw()
}

proto.toolDown = function (e, s) {
    const t = TOOLS[this.tool]
    if (this.tool === 'point') {
        const r = resolvePoint(this.scene, this.view, s, { snap: this.opts.snap })
        if (r.existing) { this.selectOnly([r.existing.id]); return }
        const o = this.addObject(r.def)
        this.commit('创建点')
        this.selected = new Set([o.id])
        this.afterChange()
        return
    }
    const slot = this.nextSlot()
    if (!slot) return
    let id = null
    if (slotCreatesPoint(slot)) {
        const r = resolvePoint(this.scene, this.view, s, { snap: this.opts.snap })
        if (slot === 'polygonPts' && r.existing && this.pending.length >= 3 && r.existing.id === this.pending[0]) return this.finishPolygon()
        id = this.materialize(r)
    } else {
        // 特殊：中点工具允许直接点击线段
        const hit = this.hit(s, (o, v) => accepts(slot, o, v) || (this.tool === 'midpoint' && v.kind === 'segment') || (this.tool === 'm-distance' && v.kind === 'segment'))
        if (!hit) { toast(this.stepHint()); return }
        const v = this.scene.val(hit.obj.id)
        if (this.tool === 'midpoint' && v.kind === 'segment' && !this.pending.length) {
            const segObj = hit.obj
            return this.finishTool([segObj.a, segObj.b])
        }
        if (this.tool === 'm-distance' && !this.pending.length && (v.kind === 'segment' || v.kind === 'arc')) return this.finishTool([hit.obj.id])
        id = hit.obj.id
    }
    if (!id) return
    if (this.pending.includes(id) && slot !== 'polygonPts') { toast('请选择一个不同的对象'); return }
    this.pending.push(id)
    // m-distance：点 + 点 / 点 + 直线
    if (this.tool === 'm-distance' && this.pending.length === 2) return this.finishTool(this.pending)
    if (t.slots[0] !== 'polygonPts' && this.pending.length >= t.slots.length) return this.completeWithArgs()
    this.updateToolUI()
    this.draw()
}

proto.finishPolygon = function () {
    if (this.pending.length < 3) { toast('多边形至少需要三个顶点'); return }
    this.finishTool([[...this.pending]])
}

// 需要额外参数的工具先弹出对话框
proto.completeWithArgs = async function () {
    const t = TOOLS[this.tool]
    const ids = [...this.pending]
    let extra = {}
    if (t.ask) {
        const nums = this.scene.objects.filter(o => ['slider', 'measure', 'calc'].includes(o.type)).map(o => o.name)
        const hint = nums.length ? `可以输入数字，或使用数值名称组成表达式（${nums.slice(0, 6).join('、')}）` : '可以输入数字或表达式'
        const spec = {
            radius: { title: '圆的半径', fields: [{ key: 'r', label: '半径', value: '2' }, { type: 'note', label: hint }] },
            sides: { title: '正多边形', fields: [{ key: 'n', label: '边数', type: 'number', value: 5, min: 3, max: 60 }] },
            angle: { title: '旋转角度', fields: [{ key: 'angle', label: '角度（°，逆时针）', value: '90' }, { type: 'note', label: hint }] },
            factor: { title: '缩放比例', fields: [{ key: 'k', label: '比例', value: '2' }, { type: 'note', label: hint }] },
        }[t.ask]
        const r = await formDialog(spec)
        if (!r) { this.pending = []; this.updateToolUI(); this.draw(); return }
        for (const k of ['r', 'angle', 'k']) if (k in r) {
            const err = exprErrorOf(r[k])
            if (err) { toast('表达式有误：' + err, 'error'); this.pending = []; this.updateToolUI(); return }
            r[k] = String(r[k]).trim()
        }
        if ('n' in r) r.n = clamp(Math.round(r.n), 3, 60)
        extra = r
    }
    this.finishTool(ids, extra)
}

// ---------- 键盘 ----------
proto.onKey = function (e) {
    const typing = e.target?.closest?.('input, textarea, select, [contenteditable]')
    if (typing) return false
    if (e.code === 'Space' && !e.repeat) { this.spaceDown = true; this.stage.classList.add('panning'); return true }
    if (e.key === 'Escape') {
        if (this.pending.length) { this.pending = []; this.updateToolUI(); this.draw(); return true }
        if (this.tool !== 'select') { this.setTool('select'); return true }
        if (this.selected.size) { this.selectOnly([]); return true }
        return false
    }
    if (e.key === 'Enter' && this.tool === 'polygon') { this.finishPolygon(); return true }
    // “=” 或 “(” 直接开始在输入栏输入
    if (!e.ctrlKey && !e.altKey && (e.key === '=' || e.key === '(')) { this.focusInput(e.key === '(' ? '(' : ''); return true }
    if ((e.key === 'Delete' || e.key === 'Backspace') && this.selected.size) { this.deleteSelected(); return true }
    // 方向键微移选中的自由点
    if (e.key.startsWith('Arrow') && this.selected.size) {
        const step = (e.shiftKey ? 10 : 1) / this.view.s
        const d = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] }[e.key]
        let moved = false
        for (const id of this.selected) {
            const o = this.scene.byId(id)
            if (o?.type === 'point') { o.x += d[0]; o.y += d[1]; moved = true }
            else if (o?.sx != null) { o.sx += d[0] * this.view.s; o.sy -= d[1] * this.view.s; moved = true }
        }
        if (moved) { this.commit('微移', { merge: 'nudge' }); this.afterChange() }
        return moved
    }
    if (!e.ctrlKey && !e.altKey && !e.metaKey && e.key.length === 1) {
        const k = e.key.toUpperCase()
        for (const g of TOOL_GROUPS) for (const t of g.tools) if (t.key === k) { this.setTool(t.id); return true }
    }
    return false
}

// ---------- 菜单 ----------
proto.menus = function () {
    const sel = () => [...this.selected]
    const toolItem = id => ({ label: TOOLS[id].label, icon: TOOLS[id].icon, key: TOOLS[id].key && TOOLS[id].key !== 'Escape' ? TOOLS[id].key : undefined, checked: undefined, run: () => this.setTool(id) })
    const groupItems = gid => TOOL_GROUPS.find(g => g.id === gid).tools.map(t => toolItem(t.id))
    return [
        {
            label: '编辑',
            items: () => [
                ...this.undoItems(),
                '-',
                { label: '全选', key: 'Ctrl+A', run: () => this.selectOnly(this.scene.objects.filter(o => !o.hidden || this.opts.showHidden).map(o => o.id)) },
                { label: '选择所有点', run: () => this.selectOnly(this.scene.objects.filter(o => !o.hidden && this.scene.val(o.id)?.kind === 'point').map(o => o.id)) },
                { label: '取消选择', run: () => this.selectOnly([]) },
                '-',
                { label: '属性…', icon: 'settings-2', disabled: () => this.selected.size !== 1, run: () => editProperties(this, this.scene.byId(sel()[0])) },
                { label: '隐藏选中对象', icon: 'eye-off', key: 'Ctrl+H', disabled: () => !this.selected.size, run: () => this.setHidden(sel(), true) },
                { label: '显示所有隐藏对象', icon: 'eye', key: 'Ctrl+Shift+H', run: () => this.setHidden(this.scene.objects.filter(o => o.hidden).map(o => o.id), false) },
                { label: '追踪选中对象', icon: 'footprints', key: 'Ctrl+J', disabled: () => !this.selected.size, run: () => this.toggleTrace(sel()) },
                { label: '清除追踪痕迹', run: () => { this.traces = []; this.draw() } },
                '-',
                { label: '删除', icon: 'trash-2', danger: true, key: 'Delete', disabled: () => !this.selected.size, run: () => this.deleteSelected() },
            ],
        },
        {
            label: '视图',
            items: () => [
                { label: '显示网格', checked: () => !!this.opts.grid, key: 'Ctrl+G', run: () => this.toggleOpt('grid') },
                { label: '显示坐标轴', checked: () => !!this.opts.axes, key: 'Ctrl+Shift+G', run: () => this.toggleOpt('axes') },
                { label: '吸附网格', checked: () => !!this.opts.snap, run: () => this.toggleOpt('snap') },
                { label: '显示隐藏对象', checked: () => !!this.opts.showHidden, run: () => this.toggleOpt('showHidden') },
                { label: '显示右侧面板', checked: () => !this.panels.classList.contains('hidden'), key: 'Ctrl+\\', run: () => { this.panels.classList.toggle('hidden'); this.resize() } },
                '-',
                { label: '放大', icon: 'zoom-in', key: 'Ctrl+=', run: () => this.zoomBy(1.25) },
                { label: '缩小', icon: 'zoom-out', key: 'Ctrl+-', run: () => this.zoomBy(1 / 1.25) },
                { label: '重置视图', icon: 'locate-fixed', key: 'Ctrl+0', run: () => this.resetView() },
                { label: '显示全部对象', icon: 'maximize', key: 'Ctrl+Shift+F', run: () => this.fitAll() },
            ],
        },
        { label: '作图', items: () => [...groupItems('point'), '-', ...groupItems('line'), '-', ...groupItems('circle'), '-', ...groupItems('conic'), { label: '按方程参数新建…', icon: 'ellipse', run: () => this.addConicDialog() }, '-', ...groupItems('poly'), '-', toolItem('locus')] },
        { label: '变换', items: () => groupItems('transform') },
        {
            label: '度量',
            items: () => [
                { header: '按选中对象' },
                ...this.measureItems(),
                '-',
                { header: '工具' },
                ...groupItems('measure'),
                '-',
                { label: '计算…', icon: 'calculator', key: 'Alt+=', run: () => this.addCalcDialog() },
            ],
        },
        {
            label: '图表',
            items: () => [
                { label: '函数图像…', icon: 'chart-spline', key: 'Ctrl+Shift+E', run: () => this.addFunctionDialog() },
                { label: '输入方程 / 命令', icon: 'keyboard', key: 'Ctrl+I', run: () => this.focusInput() },
                { label: '圆锥曲线…', icon: 'ellipse', run: () => this.addConicDialog() },
                {
                    label: '导函数', icon: 'trending-up', disabled: () => !this.selectedFunc(),
                    run: () => { const f = this.selectedFunc(); const o = this.addObject({ type: 'derivative', of: f.id }, { style: { color: '#16a34a', dash: 'dash' } }); this.commit('导函数'); this.selectOnly([o.id]); this.afterChange() },
                },
                { label: '新建参数…', icon: 'sliders-horizontal', run: () => this.placeAt('slider') },
                '-',
                { label: '显示网格', checked: () => !!this.opts.grid, run: () => this.toggleOpt('grid') },
                { label: '显示坐标轴', checked: () => !!this.opts.axes, run: () => this.toggleOpt('axes') },
            ],
        },
        {
            label: '显示',
            items: () => [
                { label: '颜色', icon: 'palette', disabled: () => !this.selected.size, submenu: PALETTE.map(c => ({ label: c, swatch: c, run: () => { for (const id of sel()) this.scene.byId(id).style.color = c; this.commit('颜色'); this.afterChange() } })) },
                { label: '线型', disabled: () => !this.selected.size, submenu: [['solid', '实线'], ['dash', '虚线'], ['dot', '点线'], ['dashdot', '点划线']].map(([v, l]) => ({ label: l, run: () => { for (const id of sel()) this.scene.byId(id).style.dash = v; this.commit('线型'); this.afterChange() } })) },
                { label: '线宽', disabled: () => !this.selected.size, submenu: [1, 1.5, 2, 3, 4, 6].map(w => ({ label: w + ' 像素', run: () => { for (const id of sel()) this.scene.byId(id).style.width = w; this.commit('线宽'); this.afterChange() } })) },
                '-',
                { label: '显示 / 隐藏标签', key: 'Ctrl+K', disabled: () => !this.selected.size, run: () => { const objs = sel().map(id => this.scene.byId(id)); const on = !objs.every(o => o.showLabel); objs.forEach(o => (o.showLabel = on)); this.commit('标签'); this.afterChange() } },
                { label: '插入文本…', icon: 'type', run: () => this.placeAt('text') },
                '-',
                { label: this.animating.size ? '停止动画' : '播放动画', icon: this.animating.size ? 'pause' : 'play', key: 'Ctrl+Shift+A', run: () => this.toggleAnimation() },
            ],
        },
    ]
}

proto.selectedFunc = function () {
    const id = [...this.selected].find(id => this.scene.val(id)?.kind === 'func')
    return id ? this.scene.byId(id) : this.scene.objects.find(o => o.type === 'func')
}

}

export { isPath, isAnnotation, dist, h }
