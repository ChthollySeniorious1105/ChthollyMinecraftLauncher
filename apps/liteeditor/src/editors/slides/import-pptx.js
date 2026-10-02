// 导入 PPTX：解析文本框、形状（几何 + 填充 + 描边）、图片、背景色与备注
// 母版 / 版式继承只做基础处理：占位符位置从版式中查找
import JSZip from 'jszip'
import { newId, SIZES } from './model.js'
import { bytesToDataURL, MIME } from '../../core/files.js'

const EMU = 914400 // 每英寸
const R_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
const NS_A = 'http://schemas.openxmlformats.org/drawingml/2006/main'

const q = (el, name) => el ? [...el.getElementsByTagName('*')].find(n => n.localName === name) ?? null : null
const qa = (el, name) => el ? [...el.getElementsByTagName('*')].filter(n => n.localName === name) : []
const kids = (el, name) => el ? [...el.children].filter(n => n.localName === name) : []
const kid = (el, name) => kids(el, name)[0] ?? null

const GEOM = {
    rect: 'rect', roundRect: 'roundRect', ellipse: 'ellipse', triangle: 'triangle', rtTriangle: 'rightTriangle', diamond: 'diamond',
    pentagon: 'pentagon', hexagon: 'hexagon', octagon: 'octagon', star5: 'star', star6: 'star6', parallelogram: 'parallelogram', trapezoid: 'trapezoid',
    rightArrow: 'arrowRight', leftArrow: 'arrowLeft', upArrow: 'arrowUp', downArrow: 'arrowDown', chevron: 'chevron', wedgeRoundRectCallout: 'callout',
    heart: 'heart', cloud: 'cloud', plus: 'cross', donut: 'ring', line: 'line', straightConnector1: 'arrow',
}

function colorOf(node, themeColors) {
    if (!node) return null
    const srgb = kid(node, 'srgbClr'), scheme = kid(node, 'schemeClr'), sys = kid(node, 'sysClr')
    let c = srgb ? '#' + srgb.getAttribute('val') : sys ? '#' + (sys.getAttribute('lastClr') ?? '000000') : scheme ? themeColors[scheme.getAttribute('val')] ?? null : null
    const mod = srgb ?? scheme ?? sys
    if (c && mod) {
        const lum = kid(mod, 'lumMod'), off = kid(mod, 'lumOff'), alpha = kid(mod, 'alpha')
        if (lum || off) c = adjustLum(c, (lum ? Number(lum.getAttribute('val')) : 100000) / 100000, (off ? Number(off.getAttribute('val')) : 0) / 100000)
        if (alpha) {
            const a = Number(alpha.getAttribute('val')) / 100000
            const n = parseInt(c.slice(1), 16)
            c = `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`
        }
    }
    return c
}
function adjustLum(hex, mod, off) {
    const n = parseInt(hex.slice(1), 16)
    let [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => v / 255)
    const max = Math.max(r, g, b), min = Math.min(r, g, b)
    let hh = 0, s = 0, l = (max + min) / 2
    if (max !== min) {
        const d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        hh = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
        hh /= 6
    }
    l = Math.min(1, Math.max(0, l * mod + off))
    const f = (p, qq, t) => { if (t < 0) t += 1; if (t > 1) t -= 1; return t < 1 / 6 ? p + (qq - p) * 6 * t : t < 1 / 2 ? qq : t < 2 / 3 ? p + (qq - p) * (2 / 3 - t) * 6 : p }
    if (s === 0) r = g = b = l
    else { const qq = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - qq; r = f(p, qq, hh + 1 / 3); g = f(p, qq, hh); b = f(p, qq, hh - 1 / 3) }
    return '#' + [r, g, b].map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('')
}

export async function importPPTX(bytes) {
    const zip = await JSZip.loadAsync(bytes)
    const read = async p => { const f = zip.file(p); return f ? new DOMParser().parseFromString(await f.async('text'), 'application/xml') : null }
    const rels = async p => {
        const dir = p.replace(/[^/]+$/, ''), name = p.split('/').pop()
        const doc = await read(`${dir}_rels/${name}.rels`)
        const map = {}
        for (const r of qa(doc, 'Relationship')) map[r.getAttribute('Id')] = { target: resolve(dir, r.getAttribute('Target')), type: r.getAttribute('Type') }
        return map
    }
    const pres = await read('ppt/presentation.xml')
    if (!pres) throw new Error('不是有效的 PPTX 文件')
    const sz = q(pres, 'sldSz')
    const cx = Number(sz?.getAttribute('cx') ?? 12192000), cy = Number(sz?.getAttribute('cy') ?? 6858000)
    const ratio = Math.abs(cx / cy - 4 / 3) < 0.05 ? '4:3' : '16:9'
    const W = SIZES[ratio].w
    const k = W / cx // EMU → 逻辑像素
    const presRels = await rels('ppt/presentation.xml')
    // 主题颜色
    const themeColors = {}
    const themePath = Object.values(presRels).find(r => r.type.endsWith('/theme'))?.target ?? 'ppt/theme/theme1.xml'
    const theme = await read(themePath)
    for (const n of ['dk1', 'lt1', 'dk2', 'lt2', 'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6', 'hlink']) {
        const node = q(q(theme, 'clrScheme'), n)
        if (node) themeColors[n] = colorOf(node, {})
    }
    Object.assign(themeColors, { tx1: themeColors.dk1, bg1: themeColors.lt1, tx2: themeColors.dk2, bg2: themeColors.lt2 })

    const ids = qa(q(pres, 'sldIdLst'), 'sldId').map(n => n.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id') ?? n.getAttribute('r:id'))
    const deck = { format: 'lslide', version: 1, ratio, theme: 'clean', slides: [] }
    let unsupported = 0
    for (const rid of ids) {
        const path = presRels[rid]?.target
        if (!path) continue
        const doc = await read(path)
        const srels = await rels(path)
        const layoutPath = Object.values(srels).find(r => r.type.endsWith('/slideLayout'))?.target
        const layout = layoutPath ? await read(layoutPath) : null
        const slide = { id: newId(), layout: 'blank', transition: { type: 'none', dur: 0.6 }, notes: '', els: [] }
        // 背景
        const bgNode = q(doc, 'bg')
        const bgFill = q(bgNode, 'solidFill'), bgBlip = q(bgNode, 'blip'), bgGrad = q(bgNode, 'gradFill')
        if (bgBlip) {
            const t = srels[bgBlip.getAttributeNS(R_NS, 'embed') ?? bgBlip.getAttribute('r:embed')]?.target
            const f = t && zip.file(t)
            if (f) slide.bg = { type: 'image', src: bytesToDataURL(await f.async('uint8array'), MIME[t.split('.').pop().toLowerCase()] ?? 'image/png') }
        } else if (bgGrad) {
            const stops = qa(bgGrad, 'gs').map(g => [Number(g.getAttribute('pos')) / 100000, colorOf(g, themeColors) ?? '#ffffff'])
            const ang = Number(q(bgGrad, 'lin')?.getAttribute('ang') ?? 0) / 60000
            if (stops.length) slide.bg = { type: 'linear', angle: ang + 90, stops }
        } else if (bgFill) slide.bg = { type: 'solid', color: colorOf(bgFill, themeColors) ?? '#ffffff' }
        const findPh = ph => {
            if (!ph || !layout) return null
            const type = ph.getAttribute('type') ?? 'body', idx = ph.getAttribute('idx')
            return qa(layout, 'sp').find(sp => { const p = q(sp, 'ph'); return p && ((idx && p.getAttribute('idx') === idx) || (p.getAttribute('type') ?? 'body') === type) }) ?? null
        }
        const xfrm = (sp, ph) => {
            let x = q(q(sp, 'spPr'), 'xfrm') ?? q(sp, 'xfrm')
            if (!x && ph) x = q(q(findPh(ph), 'spPr'), 'xfrm')
            if (!x) return null
            const off = kid(x, 'off'), ext = kid(x, 'ext')
            return {
                x: Math.round(Number(off?.getAttribute('x') ?? 0) * k), y: Math.round(Number(off?.getAttribute('y') ?? 0) * k),
                w: Math.round(Number(ext?.getAttribute('cx') ?? 0) * k), h: Math.round(Number(ext?.getAttribute('cy') ?? 0) * k),
                rot: Number(x.getAttribute('rot') ?? 0) / 60000,
            }
        }
        const tree = q(doc, 'spTree')
        for (const node of [...(tree?.children ?? [])]) {
            const tag = node.localName
            if (tag === 'sp' || tag === 'cxnSp') {
                const ph = q(q(node, 'nvPr'), 'ph')
                const box = xfrm(node, ph)
                if (!box) continue
                const spPr = kid(node, 'spPr')
                const geom = kid(spPr, 'prstGeom')?.getAttribute('prst')
                const fill = kid(spPr, 'solidFill') ? { type: 'solid', color: colorOf(kid(spPr, 'solidFill'), themeColors) } : kid(spPr, 'noFill') ? { type: 'none' } : null
                const ln = kid(spPr, 'ln')
                const stroke = ln && kid(ln, 'solidFill') ? { color: colorOf(kid(ln, 'solidFill'), themeColors) ?? '#333333', width: Math.max(1, Math.round(Number(ln.getAttribute('w') ?? 12700) * k)) } : { width: 0 }
                const { html, style } = readText(kid(node, 'txBody'), themeColors, k, ph)
                const hasShape = tag === 'cxnSp' || (geom && (fill?.type === 'solid' || stroke.width) && !ph)
                if (hasShape) {
                    const shape = GEOM[geom] ?? 'rect'
                    const el = { id: newId(), type: 'shape', shape, ...box, fill: fill ?? { type: 'none' }, stroke }
                    if (shape === 'line' || shape === 'arrow') { el.x1 = 0; el.y1 = 0; el.x2 = box.w; el.y2 = box.h; el.stroke = { ...stroke, width: stroke.width || 4 } }
                    if (html) { el.html = html; el.style = style }
                    if (!GEOM[geom]) unsupported++
                    slide.els.push(el)
                } else if (html || ph) {
                    slide.els.push({ id: newId(), type: 'text', ...box, html, style, fill: fill ?? undefined, placeholder: ph ? (ph.getAttribute('type') === 'title' || ph.getAttribute('type') === 'ctrTitle' ? '单击添加标题' : '单击添加文本') : undefined })
                }
            } else if (tag === 'pic') {
                const box = xfrm(node)
                const blip = q(node, 'blip')
                const rid2 = blip?.getAttributeNS(R_NS, 'embed') ?? blip?.getAttribute('r:embed')
                const target = srels[rid2]?.target
                const file = target && zip.file(target)
                if (!box || !file) continue
                const ext = target.split('.').pop().toLowerCase()
                const data = await file.async('uint8array')
                slide.els.push({ id: newId(), type: 'image', ...box, src: bytesToDataURL(data, MIME[ext] ?? 'image/png'), fit: 'fill' })
            } else if (tag === 'graphicFrame') {
                const box = xfrm(node)
                const tbl = q(node, 'tbl')
                if (box && tbl) {
                    const rows = qa(tbl, 'tr').map(tr => kids(tr, 'tc').map(tc => readText(kid(tc, 'txBody'), themeColors, k).html))
                    slide.els.push({ id: newId(), type: 'table', ...box, rows, style: { header: true, band: true, color: themeColors.accent1 ?? '#2563eb', border: '#cbd5e1', size: 24 } })
                } else if (box && q(node, 'chart')) {
                    const c = q(node, 'chart')
                    const target = srels[c.getAttributeNS(R_NS, 'id') ?? c.getAttribute('r:id')]?.target
                    const chart = target && await readChart(await read(target), themeColors)
                    if (chart) slide.els.push({ id: newId(), type: 'chart', ...box, chart })
                    else unsupported++
                } else unsupported++
            } else if (tag === 'grpSp') unsupported++
        }
        // 备注
        const notesPath = Object.values(srels).find(r => r.type.endsWith('/notesSlide'))?.target
        if (notesPath) {
            const nd = await read(notesPath)
            const body = qa(nd, 'sp').find(sp => q(sp, 'ph')?.getAttribute('type') === 'body')
            slide.notes = qa(body, 'p').map(p => qa(p, 't').map(t => t.textContent).join('')).join('\n').trim()
        }
        deck.slides.push(slide)
    }
    deck.importNote = unsupported ? `有 ${unsupported} 个对象（组合、图表、SmartArt 等）未能导入` : ''
    return deck
}

// 图表：读取类型、分类、系列数值与颜色
async function readChart(doc, themeColors) {
    if (!doc) return null
    const plot = q(doc, 'plotArea')
    const typeNode = plot && [...plot.children].find(n => /Chart$/.test(n.localName))
    if (!typeNode) return null
    const kind = { barChart: 'bar', bar3DChart: 'bar', lineChart: 'line', line3DChart: 'line', areaChart: 'area', pieChart: 'pie', pie3DChart: 'pie', doughnutChart: 'doughnut' }[typeNode.localName] ?? 'bar'
    const sers = kids(typeNode, 'ser')
    const pts = node => qa(node, 'pt').sort((a, b) => Number(a.getAttribute('idx')) - Number(b.getAttribute('idx'))).map(p => q(p, 'v')?.textContent ?? '')
    const labels = pts(q(sers[0], 'cat'))
    const series = sers.map((sr, i) => ({
        name: q(q(sr, 'tx'), 'v')?.textContent ?? `系列 ${i + 1}`,
        values: pts(q(sr, 'val')).map(Number),
        color: colorOf(q(kid(sr, 'spPr'), 'solidFill'), themeColors) ?? undefined,
    }))
    const title = qa(q(doc, 'title'), 't').map(t => t.textContent).join('')
    return { kind, title, labels, series, legend: !!q(doc, 'legend') }
}

function readText(body, themeColors, k, ph) {
    if (!body) return { html: '', style: {} }
    const isTitle = ph && /title/i.test(ph.getAttribute('type') ?? '')
    const style = { font: '"Microsoft YaHei", sans-serif', size: isTitle ? 64 : 36, color: themeColors.tx1 ?? '#222222', align: 'left', valign: isTitle ? 'middle' : 'top', lineHeight: 1.25, bold: false }
    const anchor = kid(kid(body, 'bodyPr'), '')
    void anchor
    const bodyPr = kid(body, 'bodyPr')
    if (bodyPr?.getAttribute('anchor') === 'ctr') style.valign = 'middle'
    if (bodyPr?.getAttribute('anchor') === 'b') style.valign = 'bottom'
    const paras = kids(body, 'p')
    let firstSize = null, firstColor = null
    const parts = []
    let listOpen = false
    for (const p of paras) {
        const pPr = kid(p, 'pPr')
        const algn = pPr?.getAttribute('algn')
        if (algn && parts.length === 0) style.align = { ctr: 'center', r: 'right', just: 'justify' }[algn] ?? 'left'
        const bullet = pPr && (kid(pPr, 'buChar') || kid(pPr, 'buAutoNum'))
        const runs = [...p.children].filter(n => n.localName === 'r' || n.localName === 'br').map(r => {
            if (r.localName === 'br') return '<br>'
            const rPr = kid(r, 'rPr')
            const t = esc(q(r, 't')?.textContent ?? '')
            const css = []
            const sz = rPr?.getAttribute('sz')
            if (sz) { const px = Math.round(Number(sz) / 100 * 2); firstSize ??= px; if (px !== firstSize) css.push(`font-size:${px}px`) }
            const c = colorOf(kid(rPr, 'solidFill'), themeColors)
            if (c) { firstColor ??= c; if (c !== firstColor) css.push(`color:${c}`) }
            let out = css.length ? `<span style="${css.join(';')}">${t}</span>` : t
            if (rPr?.getAttribute('b') === '1') out = `<b>${out}</b>`
            if (rPr?.getAttribute('i') === '1') out = `<i>${out}</i>`
            if (rPr?.getAttribute('u') && rPr.getAttribute('u') !== 'none') out = `<u>${out}</u>`
            return out
        }).join('')
        if (bullet) { if (!listOpen) { parts.push('<ul>'); listOpen = true } parts.push(`<li>${runs || '<br>'}</li>`) }
        else { if (listOpen) { parts.push('</ul>'); listOpen = false } parts.push(`<div>${runs || '<br>'}</div>`) }
    }
    if (listOpen) parts.push('</ul>')
    if (firstSize) style.size = firstSize
    if (firstColor) style.color = firstColor
    const html = parts.join('')
    return { html: html.replace(/<div><br><\/div>$/, '').replace(/^(<div><br><\/div>)+$/, ''), style }
}

const esc = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c])
function resolve(dir, target) {
    if (target.startsWith('/')) return target.slice(1)
    const parts = (dir + target).split('/')
    const out = []
    for (const p of parts) { if (p === '..') out.pop(); else if (p !== '.') out.push(p) }
    return out.join('/')
}
export { NS_A, EMU }
