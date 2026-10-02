// 演示文稿数据模型
// 幻灯片逻辑尺寸：16:9 为 1920×1080，4:3 为 1440×1080
// deck: { ratio, theme, slides: [slide] }
// slide: { id, layout, bg?: Background, transition: { type, dur }, notes, hidden, els: [el] }
// el 公共字段：{ id, type, x, y, w, h, rot, locked, anim?: { type, dur, delay, order } }
//   text:   { html, style: { font, size, color, align, valign, lineHeight }, fill, stroke, placeholder }
//   shape:  { shape, fill: Fill, stroke: { color, width, dash }, radius, shadow, html, style }
//   image:  { src, radius, border, opacity, brightness, contrast, fit }
//   table:  { rows: [[html]], style: { header, band, color, border, size } }
//   chart:  { chart: { kind, title, labels, series: [{ name, values, color }] } }
//   math:   { tex, color, size }
//   line:   { x1, y1, x2, y2 in 元素局部坐标 } 用 shape='line' / 'arrow' 表示
// Fill: { type: 'solid', color } | { type: 'linear', angle, stops: [[offset, color]] } | { type: 'none' }
import { uid } from '../../core/dom.js'

export const SIZES = { '16:9': { w: 1920, h: 1080 }, '4:3': { w: 1440, h: 1080 } }

export const THEMES = {
    clean: { name: '简洁白', bg: { type: 'solid', color: '#ffffff' }, title: '#0f172a', text: '#334155', accent: '#2563eb', accent2: '#0ea5e9', font: '"Microsoft YaHei", "PingFang SC", sans-serif', titleFont: '"Microsoft YaHei", "PingFang SC", sans-serif' },
    dark: { name: '深邃夜', bg: { type: 'solid', color: '#0f172a' }, title: '#f8fafc', text: '#cbd5e1', accent: '#38bdf8', accent2: '#a78bfa', font: '"Microsoft YaHei", sans-serif', titleFont: '"Microsoft YaHei", sans-serif' },
    gradient: { name: '霓虹渐变', bg: { type: 'linear', angle: 135, stops: [[0, '#4f46e5'], [1, '#db2777']] }, title: '#ffffff', text: '#f1f5f9', accent: '#fde68a', accent2: '#ffffff', font: '"Microsoft YaHei", sans-serif', titleFont: '"Microsoft YaHei", sans-serif' },
    ocean: { name: '海洋', bg: { type: 'linear', angle: 160, stops: [[0, '#ecfeff'], [1, '#dbeafe']] }, title: '#0c4a6e', text: '#155e75', accent: '#0891b2', accent2: '#2563eb', font: '"Microsoft YaHei", sans-serif', titleFont: '"Microsoft YaHei", sans-serif' },
    forest: { name: '森林', bg: { type: 'solid', color: '#f0fdf4' }, title: '#14532d', text: '#166534', accent: '#16a34a', accent2: '#ca8a04', font: '"Microsoft YaHei", sans-serif', titleFont: '"KaiTi", "STKaiti", serif' },
    sunset: { name: '暖阳', bg: { type: 'linear', angle: 180, stops: [[0, '#fff7ed'], [1, '#ffe4e6']] }, title: '#7c2d12', text: '#9a3412', accent: '#ea580c', accent2: '#e11d48', font: '"Microsoft YaHei", sans-serif', titleFont: '"Microsoft YaHei", sans-serif' },
    ink: { name: '水墨', bg: { type: 'solid', color: '#f7f5ef' }, title: '#1c1917', text: '#44403c', accent: '#b91c1c', accent2: '#57534e', font: '"SimSun", "Songti SC", serif', titleFont: '"KaiTi", "STKaiti", serif' },
    tech: { name: '科技蓝', bg: { type: 'linear', angle: 135, stops: [[0, '#020617'], [1, '#1e3a8a']] }, title: '#e0f2fe', text: '#bae6fd', accent: '#22d3ee', accent2: '#818cf8', font: '"Microsoft YaHei", sans-serif', titleFont: '"Microsoft YaHei", sans-serif' },
}

export const LAYOUTS = {
    title: '标题页',
    content: '标题和内容',
    two: '两栏内容',
    section: '章节标题',
    titleOnly: '仅标题',
    blank: '空白',
}

export const TRANSITIONS = {
    none: '无', fade: '淡入', push: '推入', wipe: '擦除', zoom: '缩放', flip: '翻转', cover: '覆盖', split: '分割', blur: '模糊',
}
export const ANIMS = {
    fade: '淡入', flyUp: '自底部飞入', flyLeft: '自左侧飞入', flyRight: '自右侧飞入', zoom: '缩放', bounce: '弹跳', spin: '旋转', wipe: '擦除',
}

export const SHAPES = {
    rect: '矩形', roundRect: '圆角矩形', ellipse: '椭圆', triangle: '三角形', rightTriangle: '直角三角形', diamond: '菱形',
    pentagon: '五边形', hexagon: '六边形', octagon: '八边形', star: '五角星', star6: '六角星', parallelogram: '平行四边形', trapezoid: '梯形',
    arrowRight: '右箭头', arrowLeft: '左箭头', arrowUp: '上箭头', arrowDown: '下箭头', chevron: 'V 形箭头', callout: '对话气泡',
    heart: '心形', cloud: '云朵', cross: '十字', ring: '圆环', line: '直线', arrow: '箭头线',
}

export const newId = () => uid('e')

export function sizeOf(deck) { return SIZES[deck.ratio] ?? SIZES['16:9'] }
export const themeOf = deck => ({ ...(THEMES[deck.theme] ?? THEMES.clean), ...(deck.themeOverride ?? {}) })

// 用主题填充的文本元素
function textEl(t, props) {
    const { title, style, ...rest } = props
    return {
        id: newId(), type: 'text', rot: 0, html: '',
        ...rest,
        style: { font: title ? t.titleFont : t.font, size: 40, color: title ? t.title : t.text, align: 'left', valign: 'top', lineHeight: 1.35, bold: !!title, ...(style ?? {}) },
    }
}

// 根据版式生成占位元素
export function layoutEls(deck, layout) {
    const t = themeOf(deck), { w, h } = sizeOf(deck)
    const m = 110
    switch (layout) {
        case 'title': return [
            textEl(t, { x: m, y: h * 0.32, w: w - m * 2, h: 180, title: true, placeholder: '单击添加标题', style: { size: 96, align: 'center', valign: 'middle' } }),
            textEl(t, { x: m, y: h * 0.32 + 200, w: w - m * 2, h: 100, placeholder: '单击添加副标题', style: { size: 40, align: 'center', color: t.text } }),
        ]
        case 'content': return [
            textEl(t, { x: m, y: 70, w: w - m * 2, h: 140, title: true, placeholder: '单击添加标题', style: { size: 68, valign: 'middle' } }),
            textEl(t, { x: m, y: 240, w: w - m * 2, h: h - 330, placeholder: '单击添加文本', html: '', style: { size: 40 }, list: true }),
        ]
        case 'two': return [
            textEl(t, { x: m, y: 70, w: w - m * 2, h: 140, title: true, placeholder: '单击添加标题', style: { size: 68, valign: 'middle' } }),
            textEl(t, { x: m, y: 240, w: (w - m * 2 - 60) / 2, h: h - 330, placeholder: '单击添加文本', style: { size: 36 }, list: true }),
            textEl(t, { x: m + (w - m * 2 + 60) / 2, y: 240, w: (w - m * 2 - 60) / 2, h: h - 330, placeholder: '单击添加文本', style: { size: 36 }, list: true }),
        ]
        case 'section': return [
            textEl(t, { x: m, y: h * 0.38, w: w - m * 2, h: 170, title: true, placeholder: '单击添加章节标题', style: { size: 88, valign: 'bottom' } }),
            { id: newId(), type: 'shape', shape: 'rect', x: m, y: h * 0.38 + 190, w: 220, h: 10, rot: 0, fill: { type: 'solid', color: t.accent }, stroke: { color: 'transparent', width: 0 } },
            textEl(t, { x: m, y: h * 0.38 + 230, w: w - m * 2, h: 90, placeholder: '单击添加说明', style: { size: 36 } }),
        ]
        case 'titleOnly': return [
            textEl(t, { x: m, y: 70, w: w - m * 2, h: 140, title: true, placeholder: '单击添加标题', style: { size: 68, valign: 'middle' } }),
        ]
        default: return []
    }
}

export function newSlide(deck, layout = 'content') {
    return { id: uid('s'), layout, transition: { type: 'fade', dur: 0.6 }, notes: '', hidden: false, els: layoutEls(deck, layout) }
}

export function newDeck(ratio = '16:9', theme = 'clean') {
    const deck = { format: 'lslide', version: 1, ratio, theme, slides: [] }
    deck.slides.push(newSlide(deck, 'title'))
    return deck
}

// 按主题重新着色文本（切换主题时，保留用户手动改过颜色的元素）
export function applyThemeToDeck(deck, themeId) {
    const from = themeOf(deck)
    deck.theme = themeId
    delete deck.themeOverride
    const to = themeOf(deck)
    const map = new Map([[from.title, to.title], [from.text, to.text], [from.accent, to.accent], [from.accent2, to.accent2]])
    for (const s of deck.slides) {
        for (const el of s.els) {
            if (el.style?.color && map.has(el.style.color)) el.style.color = map.get(el.style.color)
            if (el.style?.font === from.font) el.style.font = to.font
            if (el.style?.font === from.titleFont) el.style.font = to.titleFont
            if (el.fill?.type === 'solid' && map.has(el.fill.color)) el.fill.color = map.get(el.fill.color)
            if (el.stroke?.color && map.has(el.stroke.color)) el.stroke.color = map.get(el.stroke.color)
            if (el.type === 'chart') for (const sr of el.chart.series) if (map.has(sr.color)) sr.color = map.get(sr.color)
            if (el.type === 'math' && map.has(el.color)) el.color = map.get(el.color)
            if (el.type === 'table' && el.style && map.has(el.style.color)) el.style.color = map.get(el.style.color)
        }
    }
}

export const fillCSS = f => {
    if (!f || f.type === 'none') return 'transparent'
    if (f.type === 'linear') return `linear-gradient(${f.angle ?? 90}deg, ${f.stops.map(([o, c]) => `${c} ${o * 100}%`).join(', ')})`
    if (f.type === 'image') return `center / cover no-repeat url("${f.src}")`
    return f.color
}
export const firstColor = f => !f || f.type === 'none' ? 'transparent' : f.type === 'linear' ? f.stops[0][1] : f.color ?? '#ffffff'

export const CHART_COLORS = ['#2563eb', '#f97316', '#16a34a', '#db2777', '#9333ea', '#0891b2', '#ca8a04', '#64748b']

export function defaultChart(t) {
    return {
        kind: 'bar', title: '季度销售额',
        labels: ['第一季度', '第二季度', '第三季度', '第四季度'],
        series: [
            { name: '2025 年', values: [42, 58, 64, 80], color: t?.accent ?? CHART_COLORS[0] },
            { name: '2026 年', values: [50, 66, 79, 96], color: t?.accent2 ?? CHART_COLORS[1] },
        ],
        legend: true,
    }
}

// 深拷贝（图片 dataURL 为字符串，复制开销可接受）
export const clone = x => structuredClone(x)

// 纯文本（用于缩略图标题、导出 PPTX）
export function htmlToText(html) {
    const d = document.createElement('div')
    d.innerHTML = String(html ?? '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n')
    return d.textContent.replace(/\n{3,}/g, '\n\n').trim()
}
