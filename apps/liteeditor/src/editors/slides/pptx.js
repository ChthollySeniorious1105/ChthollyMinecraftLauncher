// 导出 PPTX（pptxgenjs）
import PptxGenJS from 'pptxgenjs'
import { sizeOf, themeOf, firstColor, htmlToText, CHART_COLORS } from './model.js'
import { chartSVG } from './render.js'

const PX = 1 / 144 // 逻辑像素 → 英寸（1920px = 13.333in）
const hex = c => {
    if (!c || c === 'transparent') return null
    const m = /^#([0-9a-f]{6})$/i.exec(c) ?? /^#([0-9a-f]{3})$/i.exec(c)
    if (m) return m[1].length === 3 ? [...m[1]].map(x => x + x).join('') : m[1]
    const rgba = /rgba?\(([^)]+)\)/.exec(c)
    if (rgba) { const [r, g, b] = rgba[1].split(',').map(Number); return [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('') }
    return null
}
const alphaOf = c => { const m = /rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)/.exec(c ?? ''); return m ? Number(m[1]) : 1 }
const pt = px => Math.round(px * 0.5 * 10) / 10 // 逻辑像素字号 → 磅

const SHAPE_MAP = {
    rect: 'rect', roundRect: 'roundRect', ellipse: 'ellipse', triangle: 'triangle', rightTriangle: 'rtTriangle', diamond: 'diamond',
    pentagon: 'pentagon', hexagon: 'hexagon', octagon: 'octagon', star: 'star5', star6: 'star6', parallelogram: 'parallelogram', trapezoid: 'trapezoid',
    arrowRight: 'rightArrow', arrowLeft: 'leftArrow', arrowUp: 'upArrow', arrowDown: 'downArrow', chevron: 'chevron', callout: 'wedgeRoundRectCallout',
    heart: 'heart', cloud: 'cloud', cross: 'plus', ring: 'donut', line: 'line', arrow: 'line',
}

// HTML 富文本 → pptxgenjs 文本段
function runs(html, base) {
    const d = document.createElement('div')
    d.innerHTML = html ?? ''
    const out = []
    const walk = (n, st, para) => {
        if (n.nodeType === 3) {
            const text = n.textContent
            if (text) out.push({ text, options: { ...st } })
            return
        }
        if (n.nodeType !== 1) return
        const tag = n.tagName
        const s = { ...st }
        if (tag === 'B' || tag === 'STRONG') s.bold = true
        if (tag === 'I' || tag === 'EM') s.italic = true
        if (tag === 'U') s.underline = { style: 'sng' }
        if (tag === 'S' || tag === 'STRIKE') s.strike = 'sngStrike'
        const color = n.style?.color || n.getAttribute?.('color')
        if (color && hex(color)) s.color = hex(color)
        if (n.style?.fontSize) s.fontSize = pt(parseFloat(n.style.fontSize))
        if (n.style?.fontWeight && Number(n.style.fontWeight) >= 600) s.bold = true
        if (tag === 'BR') { out.push({ text: '', options: { ...s, breakLine: true } }); return }
        const block = ['P', 'DIV', 'LI', 'H1', 'H2', 'H3'].includes(tag)
        if (tag === 'LI') s.bullet = n.parentElement?.tagName === 'OL' ? { type: 'number' } : true
        const start = out.length
        for (const c of n.childNodes) walk(c, s, block)
        if (block && out.length > start) {
            out[out.length - 1].options.breakLine = true
            if (tag === 'LI') for (let i = start; i < out.length; i++) out[i].options.bullet = s.bullet
        }
        void para
    }
    walk(d, base, false)
    if (out.length) delete out[out.length - 1].options.breakLine
    return out.length ? out : [{ text: '', options: base }]
}

export async function exportPPTX(deck) {
    const pptx = new PptxGenJS()
    const { w, h } = sizeOf(deck)
    pptx.defineLayout({ name: 'LITE', width: w * PX, height: h * PX })
    pptx.layout = 'LITE'
    const t = themeOf(deck)
    const lost = new Set()
    for (const s of deck.slides) {
        const slide = pptx.addSlide()
        const bg = s.bg ?? t.bg
        if (bg.type === 'image') slide.background = { data: bg.src }
        else {
            slide.background = { color: hex(firstColor(bg)) ?? 'FFFFFF' }
            if (bg.type === 'linear') {
                // 渐变背景：渲染为图片保证效果一致
                slide.background = { data: await gradientPNG(bg, w, h) }
            }
        }
        if (s.notes) slide.addNotes(s.notes)
        if (s.hidden) slide.hidden = true
        if (s.transition?.type && s.transition.type !== 'none') lost.add('切换效果')
        for (const el of s.els) {
            if (el.anim) lost.add('对象动画')
            const box = { x: el.x * PX, y: el.y * PX, w: el.w * PX, h: el.h * PX, rotate: el.rot || 0 }
            const st = el.style ?? {}
            const textOpts = {
                fontFace: (st.font ?? t.font).split(',')[0].replace(/"/g, '').trim(), fontSize: pt(st.size ?? 36),
                color: hex(st.color) ?? '333333', bold: !!st.bold, italic: !!st.italic,
                align: st.align === 'justify' ? 'justify' : st.align ?? 'left', valign: st.valign ?? 'top',
                lineSpacingMultiple: st.lineHeight ?? 1.2, margin: 6,
            }
            if (el.type === 'text') {
                const fill = el.fill && el.fill.type !== 'none' ? { color: hex(firstColor(el.fill)) } : undefined
                slide.addText(runs(el.html, {}), { ...box, ...textOpts, fill, line: el.stroke?.width ? { color: hex(el.stroke.color), width: el.stroke.width * 0.5 } : undefined })
            } else if (el.type === 'shape') {
                const shape = SHAPE_MAP[el.shape] ?? 'rect'
                if (el.fill?.type === 'linear') lost.add('形状渐变填充（已使用首个颜色）')
                const fc = firstColor(el.fill)
                const opts = {
                    ...box,
                    fill: el.fill?.type === 'none' || fc === 'transparent' ? { type: 'none' } : { color: hex(fc) ?? 'FFFFFF', transparency: Math.round((1 - alphaOf(fc)) * 100) },
                    line: el.stroke?.width ? { color: hex(el.stroke.color) ?? '333333', width: el.stroke.width * 0.5, dashType: { dash: 'dash', dot: 'sysDot', dashdot: 'dashDot' }[el.stroke.dash] ?? 'solid' } : { type: 'none' },
                    shadow: el.shadow ? { type: 'outer', blur: 8, offset: 4, angle: 90, opacity: 0.3, color: '000000' } : undefined,
                    rectRadius: shape === 'roundRect' ? Math.min(0.5, (el.radius ?? 24) / Math.min(el.w, el.h)) : undefined,
                }
                if (el.shape === 'line' || el.shape === 'arrow') {
                    opts.line = { color: hex(el.stroke?.color) ?? '333333', width: (el.stroke?.width || 4) * 0.5, endArrowType: el.shape === 'arrow' ? 'triangle' : undefined }
                    delete opts.fill
                }
                if (el.html) slide.addText(runs(el.html, {}), { ...opts, ...textOpts, shape, color: hex(st.color) ?? 'FFFFFF', align: st.align ?? 'center', valign: st.valign ?? 'middle' })
                else slide.addShape(shape, opts)
            } else if (el.type === 'image') {
                slide.addImage({ data: el.src, ...box, rounding: (el.radius ?? 0) >= Math.min(el.w, el.h) / 2, sizing: el.fit === 'contain' ? { type: 'contain', w: box.w, h: box.h } : { type: 'cover', w: box.w, h: box.h } })
                if (el.brightness !== undefined && el.brightness !== 100) lost.add('图片亮度 / 对比度调整')
            } else if (el.type === 'table') {
                const tst = { header: true, color: t.accent, border: '#cbd5e1', size: 28, ...(el.style ?? {}) }
                const rows = el.rows.map((r, ri) => r.map(cell => ({
                    text: htmlToText(cell),
                    options: ri === 0 && tst.header ? { bold: true, color: 'FFFFFF', fill: { color: hex(tst.color) } } : {},
                })))
                slide.addTable(rows, { ...box, fontSize: pt(tst.size), fontFace: t.font.split(',')[0].replace(/"/g, ''), color: hex(t.text), border: { type: 'solid', color: hex(tst.border) ?? 'CBD5E1', pt: 1 } })
            } else if (el.type === 'chart') {
                const c = el.chart
                const type = { bar: pptx.ChartType.bar, line: pptx.ChartType.line, area: pptx.ChartType.area, pie: pptx.ChartType.pie, doughnut: pptx.ChartType.doughnut }[c.kind] ?? pptx.ChartType.bar
                const data = c.series.map(s => ({ name: s.name, labels: c.labels, values: s.values.map(Number) }))
                slide.addChart(type, c.kind === 'pie' || c.kind === 'doughnut' ? data.slice(0, 1) : data, {
                    ...box, showTitle: !!c.title, title: c.title, showLegend: c.legend !== false, legendPos: 'b',
                    chartColors: (c.kind === 'pie' || c.kind === 'doughnut' ? c.labels.map((_, i) => c.series[0].colors?.[i] ?? CHART_COLORS[i % 8]) : c.series.map((s, i) => s.color ?? CHART_COLORS[i % 8])).map(x => hex(x) ?? '2563EB'),
                    barGapWidthPct: 60,
                })
            } else if (el.type === 'math' || el.type === 'icon') {
                // 公式与图标渲染为图片
                const png = await nodePNG(el, deck)
                if (png) slide.addImage({ data: png, ...box })
                lost.add(el.type === 'math' ? '公式（已转为图片）' : '图标（已转为图片）')
            }
        }
    }
    const data = await pptx.write({ outputType: 'uint8array' })
    return { data, lost: [...lost] }
}

async function gradientPNG(bg, w, h) {
    const c = document.createElement('canvas')
    c.width = w / 2; c.height = h / 2
    const ctx = c.getContext('2d')
    const a = ((bg.angle ?? 90) - 90) * Math.PI / 180
    const cx = c.width / 2, cy = c.height / 2, L = Math.abs(c.width * Math.cos(a)) / 2 + Math.abs(c.height * Math.sin(a)) / 2
    const g = ctx.createLinearGradient(cx - Math.cos(a) * L, cy - Math.sin(a) * L, cx + Math.cos(a) * L, cy + Math.sin(a) * L)
    for (const [o, col] of bg.stops) g.addColorStop(o, col)
    ctx.fillStyle = g
    ctx.fillRect(0, 0, c.width, c.height)
    return c.toDataURL('image/png')
}

// 把公式 / 图标元素栅格化：通过 SVG foreignObject 渲染 DOM
async function nodePNG(el, deck) {
    const { renderEl } = await import('./render.js')
    const { SLIDE_CSS } = await import('./css.js')
    const node = renderEl({ ...el, x: 0, y: 0, rot: 0 }, deck)
    const katexCSS = [...document.styleSheets].map(s => { try { return [...s.cssRules].map(r => r.cssText).filter(t => t.includes('.katex')).join('\n') } catch { return '' } }).join('\n')
    const scale = 2
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${el.w * scale}" height="${el.h * scale}"><foreignObject width="${el.w}" height="${el.h}" transform="scale(${scale})"><div xmlns="http://www.w3.org/1999/xhtml" class="sl-slide" style="width:${el.w}px;height:${el.h}px;background:transparent"><style>${SLIDE_CSS}${katexCSS.replace(/url\([^)]*\)/g, 'none')}</style>${node.outerHTML}</div></foreignObject></svg>`
    const img = new Image()
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
    try { await img.decode() } catch { return null }
    const c = document.createElement('canvas')
    c.width = el.w * scale; c.height = el.h * scale
    c.getContext('2d').drawImage(img, 0, 0)
    try { return c.toDataURL('image/png') } catch { return null }
}

export { chartSVG }
