// 演示文稿对话框：图表数据、公式、图标
import katex from 'katex'
import * as L from 'lucide'
import { h, dialog, toast } from '../../core/dom.js'
import { CHART_COLORS } from './model.js'
import { chartSVG } from './render.js'

// 图表数据：以表格形式编辑（第一行为系列名称，第一列为分类）
export async function editChart(chart) {
    const kind = h('select.input.small', ['bar', 'line', 'area', 'pie', 'doughnut'].map(k => h('option', { value: k, selected: chart.kind === k }, { bar: '柱形图', line: '折线图', area: '面积图', pie: '饼图', doughnut: '圆环图' }[k])))
    const title = h('input.input.small', { value: chart.title ?? '', placeholder: '图表标题' })
    const grid = h('table.sl-data')
    const preview = h('div.sl-chart-prev')
    const read = () => {
        const rows = [...grid.querySelectorAll('tr')].map(tr => [...tr.querySelectorAll('input')].map(i => i.value))
        const names = rows[0].slice(1)
        const body = rows.slice(1).filter(r => r.some(v => v.trim()))
        return {
            ...chart, kind: kind.value, title: title.value,
            labels: body.map(r => r[0]),
            series: names.map((n, j) => ({ name: n || `系列 ${j + 1}`, values: body.map(r => Number(r[j + 1]) || 0), color: chart.series[j]?.color ?? CHART_COLORS[j % CHART_COLORS.length] })).filter((s, j) => names[j] !== '' || s.values.some(Boolean)),
        }
    }
    const draw = () => { preview.innerHTML = chartSVG(read(), 800, 450) }
    const build = (labels, series) => {
        const rows = [['', ...series.map(s => s.name)], ...labels.map((l, i) => [l, ...series.map(s => s.values[i] ?? '')])]
        grid.replaceChildren(...rows.map((r, ri) => h('tr', r.map((v, ci) => h(ri === 0 || ci === 0 ? 'th' : 'td', h('input', { value: String(v), placeholder: ri === 0 && ci === 0 ? '' : ri === 0 ? '系列' : ci === 0 ? '分类' : '0', oninput: draw, disabled: ri === 0 && ci === 0 }))))))
        draw()
    }
    build(chart.labels, chart.series)
    const addRow = () => { const cur = read(); cur.labels.push(`分类 ${cur.labels.length + 1}`); cur.series.forEach(s => s.values.push(0)); build(cur.labels, cur.series) }
    const addCol = () => { const cur = read(); cur.series.push({ name: `系列 ${cur.series.length + 1}`, values: cur.labels.map(() => 0) }); build(cur.labels, cur.series) }
    kind.addEventListener('change', draw)
    title.addEventListener('input', draw)
    const r = await dialog({
        title: '编辑图表', width: 860,
        body: h('div.sl-chart-dlg',
            h('div.sl-chart-left',
                h('div.form-row', h('span.form-label', '类型'), kind),
                h('div.form-row', h('span.form-label', '标题'), title),
                h('div.sl-data-wrap', grid),
                h('div.sl-btnrow', h('button.chip-btn', { onclick: addRow }, '+ 分类'), h('button.chip-btn', { onclick: addCol }, '+ 系列')),
                h('div.form-note', '饼图与圆环图只使用第一个系列。')),
            preview),
        actions: [{ label: '取消', value: null }, { label: '确定', primary: true, value: () => read() }],
    })
    return r
}

export async function editMath(tex) {
    const input = h('textarea.input.textarea.mono', { rows: 4, spellcheck: false })
    input.value = tex
    const prev = h('div.sl-math-prev')
    const err = h('div.form-note')
    const draw = () => {
        try { prev.innerHTML = katex.renderToString(input.value, { displayMode: true, throwOnError: true }); err.textContent = '' }
        catch (e) { err.textContent = String(e.message).replace('KaTeX parse error: ', '语法错误：') }
    }
    input.addEventListener('input', draw)
    const samples = [['分数', '\\frac{a}{b}'], ['根式', '\\sqrt{x^2+y^2}'], ['求和', '\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}'], ['积分', '\\int_a^b f(x)\\,dx'], ['极限', '\\lim_{x\\to 0}\\frac{\\sin x}{x}=1'], ['矩阵', '\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}'], ['方程组', '\\begin{cases}x+y=1\\\\x-y=3\\end{cases}']]
    draw()
    return dialog({
        title: '编辑公式（LaTeX）', width: 620,
        body: h('div.form',
            input,
            h('div.sl-btnrow', samples.map(([l, t]) => h('button.chip-btn', { onclick: () => { input.value = t; draw() } }, l))),
            prev, err),
        actions: [{ label: '取消', value: null }, { label: '确定', primary: true, value: () => input.value.trim() || null }],
    })
}

// 从 lucide 图标库中挑选图标
const ICONS = ['star', 'heart', 'check', 'x', 'circle-check', 'lightbulb', 'rocket', 'target', 'trophy', 'flag', 'users', 'user', 'mail', 'phone', 'globe', 'map-pin', 'calendar', 'clock', 'chart-line', 'chart-pie', 'trending-up', 'dollar-sign', 'shopping-cart', 'gift', 'camera', 'image', 'music', 'video', 'book-open', 'graduation-cap', 'briefcase', 'building-2', 'house', 'car', 'plane', 'ship', 'bike', 'cloud', 'sun', 'moon', 'zap', 'flame', 'leaf', 'tree-pine', 'coffee', 'pizza', 'shield-check', 'lock', 'key', 'settings', 'wrench', 'cpu', 'database', 'server', 'code', 'terminal', 'smartphone', 'laptop', 'wifi', 'bell', 'message-circle', 'thumbs-up', 'smile', 'sparkles', 'puzzle', 'layers', 'award', 'crown', 'gem', 'handshake', 'megaphone', 'search', 'eye', 'arrow-right', 'arrow-up-right', 'refresh-cw', 'infinity']
const pascal = n => n.split('-').map(s => s[0].toUpperCase() + s.slice(1)).join('')
export async function pickIcon() {
    const q = h('input.input.small', { placeholder: '搜索图标（英文名，如 star、chart）' })
    const grid = h('div.sl-icon-grid')
    let chosen = null
    const render = () => {
        const term = q.value.trim().toLowerCase()
        let names = term ? Object.keys(L).filter(k => /^[A-Z]/.test(k) && Array.isArray(L[k]) && k.toLowerCase().includes(term.replace(/-/g, ''))).slice(0, 120) : ICONS.map(pascal)
        names = names.filter(n => L[n])
        grid.replaceChildren(...names.map(n => {
            const el = L.createElement(L[n], { width: 26, height: 26, 'stroke-width': 1.8 })
            return h('button.sl-icon-btn' + (chosen === n ? '.active' : ''), { title: n, onclick: () => { chosen = n; render() }, ondblclick: () => { chosen = n; ok?.click() } }, el)
        }))
        if (!names.length) grid.append(h('div.ep-empty', '没有找到图标'))
    }
    q.addEventListener('input', render)
    render()
    let ok
    const r = await dialog({
        title: '插入图标', width: 560,
        body: h('div.form', q, grid),
        actions: [{ label: '取消', value: null }, { label: '插入', primary: true, value: () => chosen }],
        onOpen: mask => { ok = mask.querySelector('.btn.primary') },
    })
    if (!r) return null
    const svg = L.createElement(L[r], { width: 24, height: 24 })
    svg.setAttribute('stroke', 'currentColor')
    return { name: r, svg: svg.outerHTML }
}

export async function editTable() { toast('双击表格即可直接编辑单元格') }
