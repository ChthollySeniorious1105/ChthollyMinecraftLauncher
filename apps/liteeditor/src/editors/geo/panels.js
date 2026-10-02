// 几何画板右侧面板：对象列表（代数视图）与属性
import { h, fill, formDialog, colorInput, select, numberInput, toggle } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import { panel } from '../base.js'
import { TYPES, categoryOf } from './model.js'
import { PALETTE } from './scene.js'
import { TOOLS } from './tools.js'
import { validName, renameRefs } from './index.js'

const KIND_ICON = {
    point: 'dot', linear: 'minus', circle: 'circle', polygon: 'pentagon', func: 'chart-spline', curve: 'spline', conic: 'ellipse',
    slider: 'sliders-horizontal', measure: 'ruler', calc: 'calculator', text: 'type', other: 'shapes',
}

export function buildPanels(ed) {
    ed.propBody = h('div.geo-props')
    ed.listBody = h('div.e-list.geo-list')
    ed.listFilter = 'all'
    const filterSel = select([['all', '全部对象'], ['visible', '仅可见'], ['point', '点'], ['linear', '线'], ['circle', '圆'], ['conic', '圆锥曲线'], ['func', '函数'], ['number', '数值']], 'all', v => { ed.listFilter = v; refreshPanels(ed) }, { title: '筛选' })
    ed.panels.append(
        panel('属性', ed.propBody, { icon: 'sliders-horizontal' }),
        panel('代数视图', h('div', h('div.geo-list-head', filterSel.el), ed.listBody), { icon: 'list-tree', cls: '.grow' }))
}

// values=true 时只更新数值文本（拖动过程中避免重建 DOM）
export function refreshPanels(ed, { values = false } = {}) {
    if (values && ed.listRows) {
        for (const [id, row] of ed.listRows) {
            const o = ed.scene.byId(id)
            if (o) row.querySelector('.li-sub').textContent = ed.scene.valueText(o)
        }
        const vEl = ed.propBody.querySelector('.geo-prop-value')
        const sel = [...ed.selected]
        if (vEl && sel.length === 1) { const o = ed.scene.byId(sel[0]); if (o) vEl.textContent = ed.scene.valueText(o) }
        return
    }
    renderList(ed)
    renderProps(ed)
}

function renderList(ed) {
    const s = ed.scene
    ed.listRows = new Map()
    const f = ed.listFilter
    const match = o => {
        const v = s.val(o.id), cat = categoryOf(o, v)
        if (f === 'all') return true
        if (f === 'visible') return !o.hidden
        if (f === 'number') return ['slider', 'measure', 'calc'].includes(cat)
        return cat === f
    }
    const rows = s.objects.filter(match).map(o => {
        const v = s.val(o.id)
        const cat = categoryOf(o, v)
        const eye = h('button.icon-btn', { title: o.hidden ? '显示' : '隐藏', onclick: e => { e.stopPropagation(); ed.setHidden([o.id], !o.hidden) } }, icon(o.hidden ? 'eye-off' : 'eye', 14))
        const row = h('div.e-list-item.geo-row' + (ed.selected.has(o.id) ? '.active' : '') + (o.hidden ? '.is-hidden' : '') + (v ? '' : '.undef'), {
            title: s.definition(o),
            onclick: e => {
                if (e.shiftKey || e.ctrlKey) { ed.selected.has(o.id) ? ed.selected.delete(o.id) : ed.selected.add(o.id) }
                else ed.selected = new Set([o.id])
                ed.afterChange()
            },
            ondblclick: () => editProperties(ed, o),
            oncontextmenu: e => {
                if (!ed.selected.has(o.id)) { ed.selected = new Set([o.id]); ed.afterChange() }
                contextMenu(e, ed.objectMenu([...ed.selected]))
            },
        },
        h('span.geo-swatch', { style: { '--c': o.style?.color ?? '#333' } }, icon(KIND_ICON[cat] ?? 'shapes', 13)),
        h('div.geo-row-text',
            h('div.li-name', h('b', o.name), h('span.geo-def', s.definition(o))),
            h('div.li-sub', s.valueText(o))),
        eye)
        ed.listRows.set(o.id, row)
        return row
    })
    fill(ed.listBody, rows.length ? rows : h('div.ep-empty', s.objects.length ? '没有符合筛选条件的对象' : '还没有对象。选择左侧的工具开始作图，或点击“函数”绘制函数图像。'))
    ed.listBody.querySelector('.active')?.scrollIntoView({ block: 'nearest' })
}

function renderProps(ed) {
    const s = ed.scene
    const sel = [...ed.selected].map(id => s.byId(id)).filter(Boolean)
    if (!sel.length) {
        const t = TOOLS[ed.tool]
        fill(ed.propBody,
            h('div.geo-tool-card',
                h('div.geo-tool-title', icon(t?.icon ?? 'mouse-pointer-2', 16), t?.label ?? ''),
                h('div.geo-tool-hint', t?.slots ? ed.stepHint() : t?.hint ?? '')),
            h('div.ep-empty', '选择对象以编辑颜色、线型与标签。双击对象打开完整属性。'),
            h('div.geo-shortcuts',
                ...[['Esc', '选择工具'], ['空格 + 拖动', '平移画板'], ['滚轮', '缩放'], ['Delete', '删除'], ['Ctrl+H', '隐藏'], ['Ctrl+J', '追踪'], ['E', '椭圆'], ['Ctrl+I', '输入栏']]
                    .map(([k, l]) => h('div', h('kbd', k), h('span', l)))))
        return
    }
    const one = sel.length === 1 ? sel[0] : null
    const first = sel[0]
    const cats = new Set(sel.map(o => categoryOf(o, s.val(o.id))))
    const setAll = (fn, label, merge) => { for (const o of sel) fn(o); s.touch(); ed.commit(label, merge ? { merge } : undefined); ed.afterChange() }
    const row = (label, ctl) => h('div.ep-row', h('label', label), ctl)
    const items = []
    if (one) {
        items.push(h('div.geo-prop-head',
            h('span.geo-swatch', { style: { '--c': one.style?.color } }, icon(KIND_ICON[categoryOf(one, s.val(one.id))] ?? 'shapes', 13)),
            h('div', h('div.geo-prop-name', one.name, h('span.tag', TYPES[one.type]?.label ?? '')),
                h('div.geo-prop-def', s.definition(one)),
                h('div.geo-prop-value', s.valueText(one)))))
    } else items.push(h('div.geo-prop-head', h('div', h('div.geo-prop-name', `已选择 ${sel.length} 个对象`))))

    // 颜色
    const colors = h('div.geo-colors', PALETTE.map(c => h('button.geo-color' + (first.style?.color === c ? '.active' : ''), { style: { background: c }, title: c, onclick: () => setAll(o => (o.style.color = c), '颜色') })),
        colorInput(first.style?.color ?? '#000000', v => { for (const o of sel) o.style.color = v; ed.draw() }).el)
    colors.lastChild.querySelector('input').addEventListener('change', () => { ed.commit('颜色'); ed.afterChange() })
    items.push(row('颜色', colors))

    const hasLine = [...cats].some(c => ['linear', 'circle', 'polygon', 'func', 'curve', 'conic', 'other'].includes(c))
    if (hasLine) {
        items.push(row('线宽', numberInput(first.style?.width ?? 1.8, v => setAll(o => (o.style.width = v), '线宽'), { min: 0, max: 12, step: 0.5, width: 70, suffix: 'px' }).el))
        items.push(row('线型', select([['solid', '实线'], ['dash', '虚线'], ['dot', '点线'], ['dashdot', '点划线']], first.style?.dash ?? 'solid', v => setAll(o => (o.style.dash = v), '线型')).el))
    }
    if (cats.has('polygon') || cats.has('circle') || cats.has('conic')) {
        items.push(row('填充', numberInput(Math.round((first.style?.fill ?? 0) * 100), v => setAll(o => (o.style.fill = v / 100), '填充'), { min: 0, max: 100, step: 5, width: 70, suffix: '%' }).el))
    }
    if (cats.has('point')) {
        items.push(row('点大小', numberInput(first.style?.size ?? 4.5, v => setAll(o => (o.style.size = v), '点大小'), { min: 1.5, max: 12, step: 0.5, width: 70, suffix: 'px' }).el))
        items.push(row('点样式', select([['dot', '实心圆'], ['ring', '空心圆'], ['square', '方形'], ['diamond', '菱形'], ['cross', '叉号']], first.style?.pointStyle ?? 'dot', v => setAll(o => (o.style.pointStyle = v), '点样式')).el))
    }
    if (cats.has('text') || cats.has('measure') || cats.has('calc')) {
        items.push(row('字号', numberInput(first.style?.fontSize ?? 14, v => setAll(o => (o.style.fontSize = v), '字号'), { min: 8, max: 72, width: 70, suffix: 'px' }).el))
    }
    if (one && ['measure', 'calc', 'slider'].includes(one.type)) {
        items.push(row('小数位', numberInput(one.digits ?? 2, v => setAll(o => (o.digits = v), '小数位'), { min: 0, max: 10, width: 70 }).el))
    }
    if (one?.type === 'slider') {
        items.push(row('数值', numberInput(one.value, v => setAll(o => (o.value = Math.min(o.max, Math.max(o.min, v))), '参数值'), { step: one.step, width: 90 }).el))
        items.push(row('范围', h('div.geo-range',
            numberInput(one.min, v => setAll(o => { o.min = Math.min(v, o.max); o.value = Math.max(o.value, o.min) }, '参数范围'), { width: 62 }).el,
            h('span', '~'),
            numberInput(one.max, v => setAll(o => { o.max = Math.max(v, o.min); o.value = Math.min(o.value, o.max) }, '参数范围'), { width: 62 }).el)))
        items.push(row('步长', numberInput(one.step ?? 0.1, v => setAll(o => (o.step = v || 0.01), '步长'), { min: 0.0001, step: 0.01, width: 90 }).el))
    }
    if (one && (one.type === 'slider' || one.type === 'pointOn')) {
        items.push(row('动画速度', numberInput(one.anim?.speed ?? 1, v => setAll(o => { o.anim = { ...(o.anim ?? {}), speed: v } }, '动画速度'), { min: 0.05, max: 20, step: 0.25, width: 90, suffix: '×' }).el))
    }
    if (one?.type === 'point') {
        items.push(row('坐标', h('div.geo-range',
            numberInput(round(one.x), v => setAll(o => (o.x = v), '坐标'), { step: 0.1, width: 72 }).el,
            numberInput(round(one.y), v => setAll(o => (o.y = v), '坐标'), { step: 0.1, width: 72 }).el)))
    }
    if (one?.type === 'text') {
        const ta = h('textarea.input.textarea', { rows: 3, oninput: () => { one.text = ta.value; s.touch(); s.recompute(); ed.draw() }, onchange: () => { ed.commit('编辑文本'); ed.afterChange() } })
        ta.value = one.text
        items.push(h('div.geo-textedit', ta, h('div.form-note', '用 {表达式} 插入实时数值，例如 {m1*2}')))
    }
    // 开关
    const flags = h('div.geo-flags',
        flag('显示标签', sel.every(o => o.showLabel), v => setAll(o => (o.showLabel = v), '标签')),
        flag('追踪', sel.every(o => o.trace), v => setAll(o => (o.trace = v), '追踪')),
        flag('隐藏', sel.every(o => o.hidden), v => ed.setHidden(sel.map(o => o.id), v)))
    items.push(flags)
    if (one && one.showLabel && !['slider', 'measure', 'calc', 'text'].includes(one.type)) {
        items.push(row('标签内容', select([['name', '名称'], ['value', '数值'], ['both', '名称和数值'], ['caption', '自定义标题']], one.labelMode ?? 'name', v => setAll(o => (o.labelMode = v), '标签')).el))
        if (one.labelMode === 'caption') {
            const inp = h('input.input.small', { value: one.caption ?? '', placeholder: '标题文字', onchange: () => setAll(o => (o.caption = inp.value), '标题') })
            items.push(row('标题', inp))
        }
    }
    items.push(h('div.geo-prop-actions',
        one ? h('button.btn', { onclick: () => editProperties(ed, one) }, icon('settings-2', 15), '更多') : null,
        h('button.btn.danger', { onclick: () => ed.deleteSelected() }, icon('trash-2', 15), '删除')))
    fill(ed.propBody, ...items)
}

const round = v => Math.round(v * 1000) / 1000
function flag(label, value, onchange) {
    return h('label.geo-flag', toggle(value, onchange), h('span', label))
}

// 完整属性对话框
export async function editProperties(ed, o) {
    if (!o) return
    const s = ed.scene
    const fields = [
        { key: 'name', label: '名称', value: o.name },
        { key: 'caption', label: '标题', value: o.caption ?? '', placeholder: '可选，标签显示为标题' },
        { key: 'color', label: '颜色', type: 'color', value: o.style?.color ?? '#000000' },
    ]
    const cat = categoryOf(o, s.val(o.id))
    if (['linear', 'circle', 'polygon', 'func', 'curve', 'conic', 'other'].includes(cat)) {
        fields.push({ key: 'width', label: '线宽', type: 'range', min: 0, max: 10, step: 0.5, value: o.style?.width ?? 1.8, suffix: 'px' })
        fields.push({ key: 'dash', label: '线型', type: 'select', value: o.style?.dash ?? 'solid', options: [['solid', '实线'], ['dash', '虚线'], ['dot', '点线'], ['dashdot', '点划线']] })
    }
    if (cat === 'polygon' || cat === 'circle' || cat === 'conic') fields.push({ key: 'fill', label: '填充不透明度', type: 'range', min: 0, max: 100, step: 5, value: Math.round((o.style?.fill ?? 0) * 100), suffix: '%' })
    if (cat === 'point') {
        fields.push({ key: 'size', label: '点大小', type: 'range', min: 1.5, max: 12, step: 0.5, value: o.style?.size ?? 4.5, suffix: 'px' })
        fields.push({ key: 'pointStyle', label: '点样式', type: 'select', value: o.style?.pointStyle ?? 'dot', options: [['dot', '实心圆'], ['ring', '空心圆'], ['square', '方形'], ['diamond', '菱形'], ['cross', '叉号']] })
    }
    if (o.type === 'circleR') fields.push({ key: 'r', label: '半径', value: o.r })
    if (o.type === 'rotate') fields.push({ key: 'angle', label: '角度 (°)', value: o.angle })
    if (o.type === 'dilate') fields.push({ key: 'k', label: '比例', value: o.k })
    if (o.type === 'regular') fields.push({ key: 'n', label: '边数', type: 'number', value: o.n, min: 3, max: 60 })
    if (o.type === 'measure' && o.m !== 'equation' && o.m !== 'coords') fields.push({ key: 'label', label: '显示名称', value: o.label ?? '', placeholder: '留空自动生成，例如 |AB|' })
    fields.push({ key: 'showLabel', label: '显示标签', type: 'check', value: !!o.showLabel })
    fields.push({ key: 'trace', label: '追踪', type: 'check', value: !!o.trace })
    fields.push({ key: 'hidden', label: '隐藏', type: 'check', value: !!o.hidden })
    fields.push({ type: 'note', label: `定义：${s.definition(o)}　　数值：${s.valueText(o)}` })
    const before = JSON.stringify(o)
    const r = await formDialog({
        title: `${TYPES[o.type]?.label ?? '对象'}属性`, width: 440, fields,
        onChange: v => { applyProps(o, v); s.touch(); s.recompute(); ed.draw() },
    })
    if (!r) { Object.assign(o, JSON.parse(before)); s.touch(); ed.afterChange(); return }
    if (r.name !== JSON.parse(before).name) {
        o.name = JSON.parse(before).name
        if (validName(ed, r.name, o)) { renameRefs(s, o.name, r.name); o.name = r.name }
    }
    applyProps(o, r, true)
    s.touch()
    ed.commit('修改属性')
    ed.afterChange()
}

function applyProps(o, v, final) {
    o.style = { ...o.style, color: v.color }
    for (const k of ['width', 'size']) if (k in v) o.style[k] = Number(v[k])
    for (const k of ['dash', 'pointStyle']) if (k in v) o.style[k] = v[k]
    if ('fill' in v) o.style.fill = v.fill / 100
    o.caption = v.caption || undefined
    if (v.caption && final) o.labelMode = 'caption'
    else if (!v.caption && o.labelMode === 'caption') o.labelMode = 'name'
    o.showLabel = v.showLabel
    o.trace = v.trace
    o.hidden = v.hidden
    for (const k of ['r', 'angle', 'k']) if (k in v) o[k] = String(v[k])
    if ('n' in v) o.n = Math.max(3, Math.min(60, Math.round(v.n)))
    if ('label' in v) o.label = v.label || undefined
}
