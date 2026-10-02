// 演示文稿右侧面板：对象格式 / 幻灯片（背景、切换）/ 动画窗格
import { h, fill, colorInput, select, numberInput, toggle, slider } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { panel } from '../base.js'
import { THEMES, TRANSITIONS, ANIMS, SHAPES, fillCSS, firstColor, themeOf, htmlToText } from './model.js'
import { pickImage } from '../../core/files.js'

export function buildPanels(ed) {
    ed.tabBar = h('div.sl-ptabs')
    ed.pBody = h('div.sl-pbody')
    ed.pTab = 'format'
    ed.panelTab = id => { ed.pTab = id; if (ed.panels.classList.contains('hidden')) { ed.panels.classList.remove('hidden'); ed.fit() } refreshPanels(ed) }
    ed.panels.append(ed.tabBar, ed.pBody)
}

const TYPE_NAMES = { text: '文本框', shape: '形状', image: '图片', table: '表格', chart: '图表', math: '公式', icon: '图标' }

export function refreshPanels(ed) {
    if (!ed.deck || !ed.pBody) return
    const tabs = [['format', '格式', 'sliders-horizontal'], ['slide', '幻灯片', 'presentation'], ['anim', '动画', 'sparkles']]
    fill(ed.tabBar, tabs.map(([id, l, ic]) => h('button' + (ed.pTab === id ? '.active' : ''), { onclick: () => { ed.pTab = id; refreshPanels(ed) } }, icon(ic, 14), l)))
    const body = ed.pTab === 'slide' ? slidePanel(ed) : ed.pTab === 'anim' ? animPanel(ed) : formatPanel(ed)
    fill(ed.pBody, body)
}

const row = (label, ctl) => h('div.ep-row', h('label', label), ctl)
const sec = (title, ...children) => h('div.sl-sec', h('div.sl-sec-title', title), ...children)

// 填充编辑器：纯色 / 渐变 / 无
function fillEditor(f, onchange, { allowNone = true, allowImage = false } = {}) {
    f = f ?? { type: 'solid', color: '#ffffff' }
    const box = h('div.sl-fill')
    const render = () => {
        const kind = select([['solid', '纯色'], ['linear', '渐变'], ...(allowImage ? [['image', '图片']] : []), ...(allowNone ? [['none', '无填充']] : [])], f.type, v => {
            if (v === 'solid') f = { type: 'solid', color: firstColor(f) === 'transparent' ? '#2563eb' : firstColor(f) }
            if (v === 'linear') f = { type: 'linear', angle: 135, stops: [[0, firstColor(f) === 'transparent' ? '#6366f1' : firstColor(f)], [1, '#ec4899']] }
            if (v === 'none') f = { type: 'none' }
            if (v === 'image') { pickImage().then(img => { if (img) { f = { type: 'image', src: img.dataURL }; onchange(f); render() } }); return }
            onchange(f)
            render()
        })
        const items = [row('填充', kind.el)]
        if (f.type === 'solid') {
            items.push(row('颜色', h('div.sl-colors', colorRow(f.color, c => { f = { ...f, color: c }; onchange(f, true) }))))
            items.push(row('不透明度', opacitySlider(f.color, c => { f = { ...f, color: c }; onchange(f, true) })))
        }
        if (f.type === 'linear') {
            items.push(row('起始色', colorInput(f.stops[0][1], c => { f.stops[0][1] = c; onchange(f, true) }).el))
            items.push(row('结束色', colorInput(f.stops[f.stops.length - 1][1], c => { f.stops[f.stops.length - 1][1] = c; onchange(f, true) }).el))
            items.push(row('角度', numberInput(f.angle ?? 90, v => { f.angle = v; onchange(f) }, { min: 0, max: 360, step: 15, width: 70, suffix: '°' }).el))
        }
        if (f.type === 'image') items.push(h('div.sl-bgimg', { style: { background: fillCSS(f) } }))
        box.replaceChildren(...items)
    }
    render()
    return box
}

const SWATCHES = ['#ffffff', '#0f172a', '#334155', '#94a3b8', '#ef4444', '#f97316', '#f59e0b', '#eab308', '#22c55e', '#10b981', '#06b6d4', '#3b82f6', '#6366f1', '#8b5cf6', '#ec4899', '#f43f5e']
function colorRow(value, onchange) {
    const ci = colorInput(value, onchange)
    return [
        ...SWATCHES.map(c => h('button.sl-sw' + (String(value).toLowerCase() === c ? '.active' : ''), { style: { background: c }, title: c, onclick: () => { ci.set(c); onchange(c) } })),
        ci.el,
    ]
}
function opacitySlider(color, onchange) {
    const m = /rgba\(([^,]+),([^,]+),([^,]+),\s*([\d.]+)\)/.exec(color ?? '')
    const alpha = m ? Number(m[4]) : 1
    const s = slider({ min: 0, max: 100, value: Math.round(alpha * 100), format: v => v + '%', oninput: v => onchange(withAlpha(color, v / 100)) })
    return h('div.form-range', s.el, s.el.nextSibling ?? h('span'))
}
export function withAlpha(c, a) {
    const ctx = withAlpha.ctx ??= document.createElement('canvas').getContext('2d')
    ctx.fillStyle = '#000'
    ctx.fillStyle = c
    const v = ctx.fillStyle
    let r, g, b
    if (v.startsWith('#')) { r = parseInt(v.slice(1, 3), 16); g = parseInt(v.slice(3, 5), 16); b = parseInt(v.slice(5, 7), 16) }
    else [r, g, b] = v.match(/[\d.]+/g).map(Number)
    return a >= 1 ? '#' + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('') : `rgba(${r}, ${g}, ${b}, ${a})`
}

function formatPanel(ed) {
    const els = ed.selEls()
    if (!els.length) {
        return [
            h('div.ep-empty', '选择幻灯片上的对象以设置格式。双击文本进行编辑，拖动控制点缩放，拖动顶部圆点旋转。'),
            sec('快速插入', h('div.sl-quick',
                ...[['type', '文本框', () => ed.toggleInsert({ type: 'text' })], ['square', '矩形', () => ed.toggleInsert({ type: 'shape', shape: 'roundRect' })], ['circle', '椭圆', () => ed.toggleInsert({ type: 'shape', shape: 'ellipse' })],
                    ['image-plus', '图片', () => ed.insertImage()], ['chart-column', '图表', () => ed.insertChart()], ['sigma', '公式', () => ed.insertMath()]]
                    .map(([ic, l, fn]) => h('button.sl-quick-btn', { onclick: fn }, icon(ic, 18), h('span', l))))),
            sec('快捷键', h('div.geo-shortcuts', ...[['F5', '放映'], ['Ctrl+M', '新幻灯片'], ['Ctrl+D', '创建副本'], ['Shift+拖动', '等比 / 水平'], ['Alt+拖动', '复制'], ['Ctrl+拖动', '不吸附']].map(([k, l]) => h('div', h('kbd', k), h('span', l))))),
        ]
    }
    const el = els[0]
    const one = els.length === 1
    const apply = (fn, label, live) => { for (const x of els) fn(x); if (live) { ed.renderCanvas({ keepOverlay: true }); ed.commit(label, { merge: 'live-' + label }) } else ed.change(label) }
    const out = []
    out.push(h('div.sl-obj-head', icon({ text: 'type', shape: 'shapes', image: 'image', table: 'table', chart: 'chart-column', math: 'sigma', icon: 'smile' }[el.type] ?? 'box', 16),
        h('b', one ? (el.type === 'shape' ? SHAPES[el.shape] ?? '形状' : TYPE_NAMES[el.type]) : `${els.length} 个对象`),
        one && el.locked ? h('span.tag', '已锁定') : null))

    // 位置与大小
    const num = (k, label, opts = {}) => row(label, numberInput(Math.round(el[k] ?? 0), v => apply(x => { x[k] = v }, '位置与大小'), { width: 76, ...opts }).el)
    if (one) {
        out.push(sec('位置与大小',
            h('div.sl-grid2', num('x', 'X'), num('y', 'Y'), num('w', '宽', { min: 10 }), num('h', '高', { min: 10 })),
            row('旋转', numberInput(el.rot ?? 0, v => apply(x => { x.rot = ((v % 360) + 360) % 360 }, '旋转'), { width: 76, step: 15, suffix: '°' }).el)))
    }
    // 形状填充 / 描边
    if (els.some(x => x.type === 'shape' || x.type === 'text')) {
        const isLine = el.shape === 'line' || el.shape === 'arrow'
        if (!isLine) out.push(sec('填充', fillEditor(el.fill ?? { type: 'none' }, (f, live) => apply(x => { x.fill = structuredClone(f) }, '填充', live))))
        const st = el.stroke ?? { color: '#333333', width: 0 }
        out.push(sec(isLine ? '线条' : '边框',
            row('颜色', colorInput(st.color === 'transparent' ? '#333333' : st.color ?? '#333333', c => apply(x => { x.stroke = { ...(x.stroke ?? {}), color: c, width: x.stroke?.width || 4 } }, '边框颜色', true)).el),
            row('粗细', numberInput(st.width ?? 0, v => apply(x => { x.stroke = { color: '#333333', ...(x.stroke ?? {}), width: v } }, '边框粗细'), { min: 0, max: 60, width: 76, suffix: 'px' }).el),
            row('线型', select([['solid', '实线'], ['dash', '虚线'], ['dot', '点线'], ['dashdot', '点划线']], st.dash ?? 'solid', v => apply(x => { x.stroke = { ...(x.stroke ?? {}), dash: v } }, '线型')).el),
            el.type === 'shape' && el.shape === 'roundRect' ? row('圆角', numberInput(el.radius ?? 24, v => apply(x => { x.radius = v }, '圆角'), { min: 0, max: 400, width: 76, suffix: 'px' }).el) : null,
            el.type === 'shape' ? row('阴影', toggle(!!el.shadow, v => apply(x => { x.shadow = v }, '阴影'))) : null))
    }
    // 文本
    if (els.some(x => x.type === 'text' || x.type === 'shape' && x.html != null)) {
        const st = el.style ?? {}
        out.push(sec('文本',
            row('行距', select([[1, '1.0'], [1.15, '1.15'], [1.35, '1.35'], [1.5, '1.5'], [2, '2.0']], st.lineHeight ?? 1.35, v => ed.fmtText({ lineHeight: Number(v) })).el),
            row('字间距', numberInput(st.spacing ?? 0, v => ed.fmtText({ spacing: v }), { min: -10, max: 40, width: 76, suffix: 'px' }).el),
            row('垂直', select([['top', '顶端'], ['middle', '居中'], ['bottom', '底端']], st.valign ?? 'top', v => ed.fmtText({ valign: v })).el)))
    }
    // 图片
    if (one && el.type === 'image') {
        out.push(sec('图片',
            row('填充方式', select([['cover', '裁剪填满'], ['contain', '完整显示'], ['fill', '拉伸']], el.fit ?? 'cover', v => apply(x => { x.fit = v }, '图片填充')).el),
            row('圆角', numberInput(el.radius ?? 0, v => apply(x => { x.radius = v }, '圆角'), { min: 0, max: 1000, width: 76, suffix: 'px' }).el),
            row('亮度', rangeCtl(el.brightness ?? 100, 0, 200, v => apply(x => { x.brightness = v }, '亮度', true), '%')),
            row('对比度', rangeCtl(el.contrast ?? 100, 0, 200, v => apply(x => { x.contrast = v }, '对比度', true), '%')),
            row('不透明度', rangeCtl(Math.round((el.opacity ?? 1) * 100), 0, 100, v => apply(x => { x.opacity = v / 100 }, '不透明度', true), '%')),
            row('黑白', toggle(!!el.grayscale, v => apply(x => { x.grayscale = v }, '黑白'))),
            row('阴影', toggle(!!el.shadow, v => apply(x => { x.shadow = v }, '阴影'))),
            row('边框', h('div.geo-range', colorInput(el.border?.color ?? '#ffffff', c => apply(x => { x.border = { width: x.border?.width || 6, color: c } }, '图片边框', true)).el,
                numberInput(el.border?.width ?? 0, v => apply(x => { x.border = { color: x.border?.color ?? '#ffffff', width: v } }, '图片边框'), { min: 0, max: 60, width: 60, suffix: 'px' }).el)),
            h('button.btn.sl-wide', { onclick: () => ed.replaceImage(el) }, icon('image', 15), '更换图片')))
    }
    if (one && el.type === 'chart') {
        out.push(sec('图表',
            row('类型', select([['bar', '柱形图'], ['line', '折线图'], ['area', '面积图'], ['pie', '饼图'], ['doughnut', '圆环图']], el.chart.kind, v => apply(x => { x.chart.kind = v }, '图表类型')).el),
            row('图例', toggle(el.chart.legend !== false, v => apply(x => { x.chart.legend = v }, '图例'))),
            h('button.btn.sl-wide', { onclick: () => ed.editChart(el) }, icon('table', 15), '编辑数据…')))
    }
    if (one && el.type === 'math') {
        out.push(sec('公式',
            row('颜色', colorInput(el.color ?? '#333333', c => apply(x => { x.color = c }, '公式颜色', true)).el),
            row('字号', numberInput(el.size ?? 48, v => apply(x => { x.size = v }, '公式字号'), { min: 12, max: 300, width: 76, suffix: 'px' }).el),
            h('button.btn.sl-wide', { onclick: () => ed.editMath(el) }, icon('sigma', 15), '编辑公式…')))
    }
    if (one && el.type === 'icon') out.push(sec('图标', row('颜色', colorInput(el.color ?? '#2563eb', c => apply(x => { x.color = c }, '图标颜色', true)).el), row('线宽', numberInput(el.strokeWidth ?? 1.6, v => apply(x => { x.strokeWidth = v }, '图标线宽'), { min: 0.5, max: 4, step: 0.2, width: 76 }).el)))
    if (one && el.type === 'table') {
        const st = el.style ?? {}
        out.push(sec('表格',
            row('主题色', colorInput(st.color ?? themeOf(ed.deck).accent, c => apply(x => { x.style = { ...x.style, color: c } }, '表格颜色', true)).el),
            row('边框色', colorInput(st.border ?? '#cbd5e1', c => apply(x => { x.style = { ...x.style, border: c } }, '表格边框', true)).el),
            row('字号', numberInput(st.size ?? 28, v => apply(x => { x.style = { ...x.style, size: v } }, '表格字号'), { min: 10, max: 120, width: 76, suffix: 'px' }).el),
            row('标题行', toggle(st.header !== false, v => apply(x => { x.style = { ...x.style, header: v } }, '标题行'))),
            row('镶边行', toggle(st.band !== false, v => apply(x => { x.style = { ...x.style, band: v } }, '镶边行'))),
            h('div.sl-btnrow', ...ed.tableItems(el).filter(i => i && i !== '-' && i.run && !i.checked).slice(0, 6).map(i => h('button.chip-btn', { onclick: i.run }, i.label.replace('在', '').replace('插入', '+ ')))))) }
    // 排列
    out.push(sec('排列', h('div.sl-btnrow',
        ...[['align-start-vertical', 'left', '左对齐'], ['align-center-vertical', 'center', '水平居中'], ['align-end-vertical', 'right', '右对齐'], ['align-start-horizontal', 'top', '顶端对齐'], ['align-center-horizontal', 'middle', '垂直居中'], ['align-end-horizontal', 'bottom', '底端对齐']]
            .map(([ic, how, t]) => ed.tb(ic, t + (one ? '（相对幻灯片）' : ''), () => ed.alignSel(how)))),
    h('div.sl-btnrow',
        ed.tb('bring-to-front', '置于顶层', () => ed.order('front')), ed.tb('arrow-up', '上移一层', () => ed.order('forward')),
        ed.tb('arrow-down', '下移一层', () => ed.order('backward')), ed.tb('send-to-back', '置于底层', () => ed.order('back')),
        ed.tb(el.locked ? 'lock-open' : 'lock', el.locked ? '解锁' : '锁定', () => ed.lock()),
        ed.tb('trash-2', '删除', () => ed.deleteSel()))))
    return out
}

function rangeCtl(value, min, max, oninput, suffix = '') {
    const s = slider({ min, max, value, format: v => v + suffix, oninput })
    return h('div.form-range', s.el, s.input.nextSibling ?? h('span.range-value', value + suffix))
}

function slidePanel(ed) {
    const s = ed.slide
    const t = themeOf(ed.deck)
    const tr = s.transition ?? { type: 'none', dur: 0.6 }
    const out = []
    out.push(sec('设计主题', h('div.sl-themes', Object.entries(THEMES).map(([k, th]) => h('button.sl-theme' + (ed.deck.theme === k ? '.active' : ''), { title: th.name, onclick: () => ed.setTheme(k) },
        h('span.sl-theme-prev', { style: { background: fillCSS(th.bg) } }, h('i', { style: { background: th.title } }), h('i', { style: { background: th.accent } }), h('i', { style: { background: th.text } })),
        h('span.sl-theme-name', th.name))))))
    out.push(sec('背景',
        fillEditor(s.bg ?? t.bg, (f, live) => {
            s.bg = structuredClone(f)
            ed.renderCanvas()
            ed.refreshThumb(ed.current)
            ed.commit('背景', live ? { merge: 'bg' } : undefined)
        }, { allowNone: false, allowImage: true }),
        h('div.sl-btnrow',
            h('button.chip-btn', { onclick: () => { delete s.bg; ed.renderAll(); ed.commit('重置背景') } }, '使用主题背景'),
            h('button.chip-btn', { onclick: () => { for (const x of ed.deck.slides) x.bg = structuredClone(s.bg ?? t.bg); ed.renderAll(); ed.commit('背景应用到全部') } }, '应用到全部'))))
    out.push(sec('切换效果',
        h('div.sl-trans', Object.entries(TRANSITIONS).map(([k, l]) => h('button.sl-trans-btn' + (tr.type === k ? '.active' : ''), { onclick: () => ed.setTransition(k) }, l))),
        row('时长', numberInput(tr.dur ?? 0.6, v => { s.transition = { ...tr, dur: v }; ed.commit('切换时长') }, { min: 0.1, max: 5, step: 0.1, width: 76, suffix: '秒' }).el),
        h('div.sl-btnrow',
            h('button.chip-btn', { onclick: () => ed.previewTransition() }, icon('play', 12), ' 预览'),
            h('button.chip-btn', { onclick: () => { for (const x of ed.deck.slides) x.transition = structuredClone(s.transition ?? tr); ed.renderThumbs(); ed.commit('切换效果') } }, '应用到全部'))))
    out.push(sec('幻灯片',
        row('版式', select(Object.entries({ title: '标题页', content: '标题和内容', two: '两栏内容', section: '章节标题', titleOnly: '仅标题', blank: '空白' }), s.layout ?? 'blank', v => ed.applyLayout(v)).el),
        row('隐藏', toggle(!!s.hidden, v => { s.hidden = v; ed.renderThumbs(); ed.commit('隐藏幻灯片') })),
        row('比例', select([['16:9', '宽屏 16:9'], ['4:3', '标准 4:3']], ed.deck.ratio, v => ed.setRatio(v)).el)))
    return out
}

function animPanel(ed) {
    const s = ed.slide
    const els = ed.selEls()
    const out = []
    out.push(sec('对象动画',
        els.length ? h('div.sl-trans', Object.entries(ANIMS).map(([k, l]) => h('button.sl-trans-btn' + (els.every(e => e.anim?.type === k) ? '.active' : ''), {
            onclick: () => {
                let order = Math.max(0, ...s.els.map(e => e.anim?.order ?? 0))
                for (const e of els) e.anim = { type: k, dur: e.anim?.dur ?? 0.6, delay: e.anim?.delay ?? 0, order: e.anim?.order ?? ++order }
                ed.change('设置动画')
                previewAnim(ed, els)
            },
        }, l))) : h('div.ep-empty', '在幻灯片上选择对象后，为它添加进入动画。'),
        els.length && els.some(e => e.anim) ? h('div',
            row('时长', numberInput(els[0].anim?.dur ?? 0.6, v => { for (const e of els) if (e.anim) e.anim.dur = v; ed.commit('动画时长') }, { min: 0.1, max: 5, step: 0.1, width: 76, suffix: '秒' }).el),
            row('延迟', numberInput(els[0].anim?.delay ?? 0, v => { for (const e of els) if (e.anim) e.anim.delay = v; ed.commit('动画延迟') }, { min: 0, max: 10, step: 0.1, width: 76, suffix: '秒' }).el),
            h('div.sl-btnrow', h('button.chip-btn', { onclick: () => previewAnim(ed, els) }, icon('play', 12), ' 预览'), h('button.chip-btn.danger', { onclick: () => { for (const e of els) delete e.anim; ed.change('移除动画') } }, '移除'))) : null))
    // 动画窗格：按顺序列出
    const list = s.els.filter(e => e.anim?.type).sort((a, b) => (a.anim.order ?? 0) - (b.anim.order ?? 0))
    const label = e => (e.type === 'text' || e.html ? htmlToText(e.html).slice(0, 16) : '') || (e.type === 'shape' ? SHAPES[e.shape] : TYPE_NAMES[e.type])
    out.push(sec('动画窗格（按点击顺序）', list.length ? h('div.e-list', list.map((e, i) => h('div.e-list-item' + (ed.sel.includes(e.id) ? '.active' : ''), { onclick: () => ed.setSel([e.id]) },
        h('span.sl-anim-num', String(e.anim.order ?? i + 1)),
        h('span.li-name', label(e)),
        h('span.li-sub', ANIMS[e.anim.type]),
        h('button.icon-btn', { title: '提前', onclick: ev => { ev.stopPropagation(); reorder(ed, list, i, -1) } }, icon('chevron-up', 13)),
        h('button.icon-btn', { title: '推后', onclick: ev => { ev.stopPropagation(); reorder(ed, list, i, 1) } }, icon('chevron-down', 13)),
        h('button.icon-btn', { title: '与上一项同时播放', onclick: ev => { ev.stopPropagation(); if (i > 0) { e.anim.order = list[i - 1].anim.order; ed.change('同时播放') } } }, icon('link', 13))))) : h('div.ep-empty', '本页没有动画。')))
    return out
}

function reorder(ed, list, i, d) {
    const j = i + d
    if (j < 0 || j >= list.length) return
    const arr = [...list]
    ;[arr[i], arr[j]] = [arr[j], arr[i]]
    arr.forEach((e, k) => { e.anim.order = k + 1 })
    ed.change('调整动画顺序')
}

function previewAnim(ed, els) {
    const FROM = { fade: { opacity: 0 }, flyUp: { opacity: 0, translate: '0 120px' }, flyLeft: { opacity: 0, translate: '-200px 0' }, flyRight: { opacity: 0, translate: '200px 0' }, zoom: { opacity: 0, scale: '.4' }, bounce: { opacity: 0, translate: '0 -100px' }, spin: { opacity: 0, rotate: '-180deg', scale: '.3' }, wipe: { clipPath: 'inset(0 100% 0 0)' } }
    for (const e of els) {
        const node = ed.slideEl.querySelector(`[data-id="${e.id}"]`)
        const f = FROM[e.anim?.type]
        if (!node || !f) continue
        node.animate([f, { opacity: e.opacity ?? 1, translate: '0 0', scale: '1', rotate: '0deg', clipPath: 'inset(0 0 0 0)' }], { duration: (e.anim.dur ?? 0.6) * 1000, easing: e.anim.type === 'bounce' ? 'cubic-bezier(.34,1.56,.64,1)' : 'cubic-bezier(.2,.8,.2,1)' })
    }
}
