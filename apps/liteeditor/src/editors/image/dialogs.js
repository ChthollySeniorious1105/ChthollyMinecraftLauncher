// 图像编辑对话框：新建画布、画布大小、图像大小、曲线
import { h, dialog, formDialog, slider, toast } from '../../core/dom.js'
import { curveLUT } from './filters.js'

const PRESETS = [
    ['custom', '自定义'], ['1920x1080', '全高清 1920 × 1080'], ['3840x2160', '4K 3840 × 2160'], ['1280x720', 'HD 1280 × 720'],
    ['1080x1080', '方形 1080 × 1080'], ['1080x1920', '手机竖屏 1080 × 1920'], ['2480x3508', 'A4 300dpi 2480 × 3508'],
    ['800x600', '800 × 600'], ['512x512', '图标 512 × 512'],
]

export async function askCanvasSize(init = {}) {
    const r = await formDialog({
        title: '新建画布', width: 420,
        fields: [
            { key: 'preset', label: '预设', type: 'select', value: 'custom', options: PRESETS },
            { key: 'width', label: '宽度', type: 'number', value: init.width ?? 1920, min: 1, max: 16384, suffix: '像素' },
            { key: 'height', label: '高度', type: 'number', value: init.height ?? 1080, min: 1, max: 16384, suffix: '像素' },
            { key: 'bg', label: '背景', type: 'select', value: 'white', options: [['white', '白色'], ['black', '黑色'], ['transparent', '透明'], ['color', '自定义颜色']] },
            { key: 'color', label: '背景颜色', type: 'color', value: '#e2e8f0' },
            { type: 'note', label: '选择预设会覆盖宽度与高度。' },
        ],
    })
    if (!r) return null
    let { width, height } = r
    if (r.preset !== 'custom') [width, height] = r.preset.split('x').map(Number)
    width = Math.max(1, Math.min(16384, Math.round(width)))
    height = Math.max(1, Math.min(16384, Math.round(height)))
    if (width * height > 100e6) { toast('画布过大（超过 1 亿像素）', 'error'); return null }
    const bg = r.bg === 'white' ? '#ffffff' : r.bg === 'black' ? '#000000' : r.bg === 'color' ? r.color : null
    return { width, height, bg }
}

export async function askImageSize(doc) {
    const r = await formDialog({
        title: '图像大小', width: 420,
        fields: [
            { key: 'w', label: '宽度', type: 'number', value: doc.w, min: 1, max: 16384, suffix: '像素' },
            { key: 'h', label: '高度', type: 'number', value: doc.h, min: 1, max: 16384, suffix: '像素' },
            { key: 'keep', label: '约束比例', type: 'check', value: true },
            { key: 'pct', label: '或按百分比', type: 'number', value: 100, min: 1, max: 1000, suffix: '%' },
            { key: 'smooth', label: '重采样', type: 'select', value: 'high', options: [['high', '两次立方（平滑）'], ['low', '邻近（保留硬边）']] },
        ],
    })
    if (!r) return null
    let w = r.w, hh = r.h
    if (r.pct !== 100) { w = Math.round(doc.w * r.pct / 100); hh = Math.round(doc.h * r.pct / 100) }
    else if (r.keep) {
        if (w !== doc.w) hh = Math.round(doc.h * w / doc.w)
        else if (hh !== doc.h) w = Math.round(doc.w * hh / doc.h)
    }
    return { w: Math.max(1, w), h: Math.max(1, hh), smooth: r.smooth === 'high' }
}

export async function askCanvasResize(doc) {
    const anchors = [['tl', '左上'], ['t', '上'], ['tr', '右上'], ['l', '左'], ['c', '居中'], ['r', '右'], ['bl', '左下'], ['b', '下'], ['br', '右下']]
    const r = await formDialog({
        title: '画布大小', width: 420,
        fields: [
            { key: 'w', label: '宽度', type: 'number', value: doc.w, min: 1, max: 16384, suffix: '像素' },
            { key: 'h', label: '高度', type: 'number', value: doc.h, min: 1, max: 16384, suffix: '像素' },
            { key: 'anchor', label: '定位', type: 'select', value: 'c', options: anchors },
        ],
    })
    if (!r) return null
    const dx = r.anchor.includes('l') ? 0 : r.anchor.includes('r') ? r.w - doc.w : Math.round((r.w - doc.w) / 2)
    const dy = r.anchor.includes('t') ? 0 : r.anchor.includes('b') ? r.h - doc.h : Math.round((r.h - doc.h) / 2)
    return { w: r.w, h: r.h, dx, dy }
}

// 曲线对话框：可拖动控制点，双击添加，右键删除；onPreview(points, channel)
export async function curvesDialog(onPreview, histogram) {
    const S = 256
    const cv = h('canvas.img-curve', { width: S, height: S })
    let points = [[0, 0], [255, 255]]
    let channel = 'rgb'
    let drag = -1
    const draw = () => {
        const g = cv.getContext('2d')
        g.clearRect(0, 0, S, S)
        g.fillStyle = '#fff'; g.fillRect(0, 0, S, S)
        if (histogram) {
            const max = Math.max(...histogram)
            g.fillStyle = '#e2e8f0'
            histogram.forEach((v, i) => { const hh = v / max * S * 0.9; g.fillRect(i, S - hh, 1, hh) })
        }
        g.strokeStyle = '#e5e7eb'
        for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(i * S / 4, 0); g.lineTo(i * S / 4, S); g.moveTo(0, i * S / 4); g.lineTo(S, i * S / 4); g.stroke() }
        g.strokeStyle = '#cbd5e1'; g.beginPath(); g.moveTo(0, S); g.lineTo(S, 0); g.stroke()
        const lut = curveLUT(points)
        g.strokeStyle = { rgb: '#111827', r: '#dc2626', g: '#16a34a', b: '#2563eb' }[channel]
        g.lineWidth = 2
        g.beginPath()
        for (let x = 0; x < 256; x++) { const y = S - lut[x] * S / 256; x ? g.lineTo(x, y) : g.moveTo(x, y) }
        g.stroke()
        g.lineWidth = 1
        for (const [x, y] of points) { g.fillStyle = '#fff'; g.strokeStyle = '#111'; g.beginPath(); g.rect(x - 4, S - y - 4, 8, 8); g.fill(); g.stroke() }
        onPreview(points, channel)
    }
    const pos = e => { const r = cv.getBoundingClientRect(); return [Math.max(0, Math.min(255, (e.clientX - r.left) / r.width * 255)), Math.max(0, Math.min(255, 255 - (e.clientY - r.top) / r.height * 255))] }
    cv.addEventListener('pointerdown', e => {
        const [x, y] = pos(e)
        drag = points.findIndex(p => Math.hypot(p[0] - x, p[1] - y) < 10)
        if (e.button === 2 && drag > 0 && drag < points.length - 1) { points.splice(drag, 1); drag = -1; draw(); return }
        if (drag < 0 && e.button === 0) { points.push([x, y]); points.sort((a, b) => a[0] - b[0]); drag = points.findIndex(p => p[0] === x) }
        cv.setPointerCapture(e.pointerId)
        draw()
    })
    cv.addEventListener('pointermove', e => {
        if (drag < 0) return
        const [x, y] = pos(e)
        const lo = drag === 0 ? 0 : points[drag - 1][0] + 1, hi = drag === points.length - 1 ? 255 : points[drag + 1][0] - 1
        points[drag] = [drag === 0 || drag === points.length - 1 ? points[drag][0] : Math.max(lo, Math.min(hi, x)), y]
        draw()
    })
    cv.addEventListener('pointerup', () => { drag = -1 })
    cv.addEventListener('contextmenu', e => e.preventDefault())
    const chSel = h('select.input.small', { onchange: e => { channel = e.target.value; draw() } }, [['rgb', 'RGB'], ['r', '红'], ['g', '绿'], ['b', '蓝']].map(([v, l]) => h('option', { value: v }, l)))
    const presets = h('div.sl-btnrow',
        ...[['线性', [[0, 0], [255, 255]]], ['增强对比', [[0, 0], [64, 48], [192, 208], [255, 255]]], ['提亮', [[0, 0], [128, 170], [255, 255]]], ['压暗', [[0, 0], [128, 90], [255, 255]]], ['反相', [[0, 255], [255, 0]]]]
            .map(([l, p]) => h('button.chip-btn', { onclick: () => { points = p.map(x => [...x]); draw() } }, l)))
    requestAnimationFrame(draw)
    const ok = await dialog({
        title: '曲线', width: 340,
        body: h('div.form', h('div.form-row', h('span.form-label', '通道'), chSel), cv, presets, h('div.form-note', '单击曲线添加控制点，拖动调整，右键删除。')),
    })
    return ok ? { points, channel } : null
}

export { slider }
