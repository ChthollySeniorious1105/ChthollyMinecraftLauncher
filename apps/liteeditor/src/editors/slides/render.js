// 幻灯片渲染：把模型渲染为 DOM（编辑画布、缩略图、放映、导出共用）
import katex from 'katex'
import { h } from '../../core/dom.js'
import { fillCSS, sizeOf, themeOf, CHART_COLORS } from './model.js'

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

// ---------- 形状路径（0..w, 0..h） ----------
export function shapePath(shape, w, h, radius = 24) {
    const P = pts => 'M' + pts.map(([x, y]) => `${r(x)} ${r(y)}`).join('L') + 'Z'
    const poly = (n, rot = -Math.PI / 2) => P(Array.from({ length: n }, (_, i) => [w / 2 + w / 2 * Math.cos(rot + i * 2 * Math.PI / n), h / 2 + h / 2 * Math.sin(rot + i * 2 * Math.PI / n)]))
    const star = (n, inner) => P(Array.from({ length: n * 2 }, (_, i) => {
        const a = -Math.PI / 2 + i * Math.PI / n, k = i % 2 ? inner : 1
        return [w / 2 + w / 2 * k * Math.cos(a), h / 2 + h / 2 * k * Math.sin(a)]
    }))
    const s = Math.min(w, h)
    switch (shape) {
        case 'rect': return `M0 0H${r(w)}V${r(h)}H0Z`
        case 'roundRect': {
            const k = Math.min(radius, w / 2, h / 2)
            return `M${r(k)} 0H${r(w - k)}A${r(k)} ${r(k)} 0 0 1 ${r(w)} ${r(k)}V${r(h - k)}A${r(k)} ${r(k)} 0 0 1 ${r(w - k)} ${r(h)}H${r(k)}A${r(k)} ${r(k)} 0 0 1 0 ${r(h - k)}V${r(k)}A${r(k)} ${r(k)} 0 0 1 ${r(k)} 0Z`
        }
        case 'ellipse': return `M0 ${r(h / 2)}A${r(w / 2)} ${r(h / 2)} 0 1 0 ${r(w)} ${r(h / 2)}A${r(w / 2)} ${r(h / 2)} 0 1 0 0 ${r(h / 2)}Z`
        case 'ring': {
            const t = s * 0.22
            return `M0 ${r(h / 2)}A${r(w / 2)} ${r(h / 2)} 0 1 0 ${r(w)} ${r(h / 2)}A${r(w / 2)} ${r(h / 2)} 0 1 0 0 ${r(h / 2)}Z` +
                `M${r(t)} ${r(h / 2)}A${r(w / 2 - t)} ${r(h / 2 - t)} 0 1 1 ${r(w - t)} ${r(h / 2)}A${r(w / 2 - t)} ${r(h / 2 - t)} 0 1 1 ${r(t)} ${r(h / 2)}Z`
        }
        case 'triangle': return P([[w / 2, 0], [w, h], [0, h]])
        case 'rightTriangle': return P([[0, 0], [w, h], [0, h]])
        case 'diamond': return P([[w / 2, 0], [w, h / 2], [w / 2, h], [0, h / 2]])
        case 'pentagon': return poly(5)
        case 'hexagon': return P([[w * 0.25, 0], [w * 0.75, 0], [w, h / 2], [w * 0.75, h], [w * 0.25, h], [0, h / 2]])
        case 'octagon': { const k = 0.29; return P([[w * k, 0], [w * (1 - k), 0], [w, h * k], [w, h * (1 - k)], [w * (1 - k), h], [w * k, h], [0, h * (1 - k)], [0, h * k]]) }
        case 'star': return star(5, 0.4)
        case 'star6': return star(6, 0.55)
        case 'parallelogram': return P([[w * 0.22, 0], [w, 0], [w * 0.78, h], [0, h]])
        case 'trapezoid': return P([[w * 0.2, 0], [w * 0.8, 0], [w, h], [0, h]])
        case 'arrowRight': return P([[0, h * 0.28], [w * 0.62, h * 0.28], [w * 0.62, 0], [w, h / 2], [w * 0.62, h], [w * 0.62, h * 0.72], [0, h * 0.72]])
        case 'arrowLeft': return P([[w, h * 0.28], [w * 0.38, h * 0.28], [w * 0.38, 0], [0, h / 2], [w * 0.38, h], [w * 0.38, h * 0.72], [w, h * 0.72]])
        case 'arrowUp': return P([[w * 0.28, h], [w * 0.28, h * 0.38], [0, h * 0.38], [w / 2, 0], [w, h * 0.38], [w * 0.72, h * 0.38], [w * 0.72, h]])
        case 'arrowDown': return P([[w * 0.28, 0], [w * 0.28, h * 0.62], [0, h * 0.62], [w / 2, h], [w, h * 0.62], [w * 0.72, h * 0.62], [w * 0.72, 0]])
        case 'chevron': return P([[0, 0], [w * 0.7, 0], [w, h / 2], [w * 0.7, h], [0, h], [w * 0.3, h / 2]])
        case 'cross': { const a = 0.33; return P([[w * a, 0], [w * (1 - a), 0], [w * (1 - a), h * a], [w, h * a], [w, h * (1 - a)], [w * (1 - a), h * (1 - a)], [w * (1 - a), h], [w * a, h], [w * a, h * (1 - a)], [0, h * (1 - a)], [0, h * a], [w * a, h * a]]) }
        case 'callout': {
            const k = Math.min(radius, w / 4, h / 4), bh = h * 0.78
            return `M${r(k)} 0H${r(w - k)}Q${r(w)} 0 ${r(w)} ${r(k)}V${r(bh - k)}Q${r(w)} ${r(bh)} ${r(w - k)} ${r(bh)}H${r(w * 0.36)}L${r(w * 0.18)} ${r(h)}L${r(w * 0.22)} ${r(bh)}H${r(k)}Q0 ${r(bh)} 0 ${r(bh - k)}V${r(k)}Q0 0 ${r(k)} 0Z`
        }
        case 'heart': return `M${r(w / 2)} ${r(h * 0.95)}C${r(w * 0.1)} ${r(h * 0.65)} 0 ${r(h * 0.4)} 0 ${r(h * 0.28)}C0 ${r(h * 0.08)} ${r(w * 0.18)} 0 ${r(w * 0.3)} 0C${r(w * 0.42)} 0 ${r(w / 2)} ${r(h * 0.1)} ${r(w / 2)} ${r(h * 0.2)}C${r(w / 2)} ${r(h * 0.1)} ${r(w * 0.58)} 0 ${r(w * 0.7)} 0C${r(w * 0.82)} 0 ${r(w)} ${r(h * 0.08)} ${r(w)} ${r(h * 0.28)}C${r(w)} ${r(h * 0.4)} ${r(w * 0.9)} ${r(h * 0.65)} ${r(w / 2)} ${r(h * 0.95)}Z`
        case 'cloud': return `M${r(w * 0.25)} ${r(h * 0.9)}C${r(w * 0.05)} ${r(h * 0.9)} 0 ${r(h * 0.62)} ${r(w * 0.12)} ${r(h * 0.52)}C${r(w * 0.05)} ${r(h * 0.3)} ${r(w * 0.25)} ${r(h * 0.15)} ${r(w * 0.38)} ${r(h * 0.25)}C${r(w * 0.45)} ${r(h * 0.02)} ${r(w * 0.72)} ${r(h * 0.02)} ${r(w * 0.76)} ${r(h * 0.26)}C${r(w * 0.95)} ${r(h * 0.22)} ${r(w)} ${r(h * 0.5)} ${r(w * 0.9)} ${r(h * 0.6)}C${r(w)} ${r(h * 0.75)} ${r(w * 0.92)} ${r(h * 0.92)} ${r(w * 0.75)} ${r(h * 0.9)}Z`
    }
    return `M0 0H${r(w)}V${r(h)}H0Z`
}
const r = v => Math.round(v * 10) / 10

let gradSeq = 0
function svgFill(defs, f) {
    if (!f || f.type === 'none') return 'none'
    if (f.type === 'linear') {
        const id = 'lg' + (++gradSeq)
        const a = ((f.angle ?? 90) - 90) * Math.PI / 180
        const x1 = 0.5 - Math.cos(a) / 2, y1 = 0.5 - Math.sin(a) / 2, x2 = 0.5 + Math.cos(a) / 2, y2 = 0.5 + Math.sin(a) / 2
        defs.push(`<linearGradient id="${id}" x1="${r(x1)}" y1="${r(y1)}" x2="${r(x2)}" y2="${r(y2)}">${f.stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('')}</linearGradient>`)
        return `url(#${id})`
    }
    return f.color
}
const DASH = { solid: '', dash: '18 10', dot: '3 8', dashdot: '18 8 3 8' }

function shapeSVG(el) {
    const { w, h } = el
    const defs = []
    const st = el.stroke ?? {}
    const sw = st.width ?? 0
    const dash = DASH[st.dash] ? ` stroke-dasharray="${DASH[st.dash].split(' ').map(n => n * Math.max(1, sw / 4)).join(' ')}"` : ''
    const shadow = el.shadow ? ' filter="url(#sh)"' : ''
    if (el.shadow) defs.push('<filter id="sh" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-opacity=".28"/></filter>')
    let body
    if (el.shape === 'line' || el.shape === 'arrow') {
        const x1 = el.x1 ?? 0, y1 = el.y1 ?? h / 2, x2 = el.x2 ?? w, y2 = el.y2 ?? h / 2
        const lw = Math.max(1, sw || 4)
        let marker = ''
        if (el.shape === 'arrow') {
            defs.push(`<marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="${4}" markerHeight="${4}" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="${st.color ?? '#333'}"/></marker>`)
            marker = ' marker-end="url(#ah)"'
        }
        body = `<line x1="${r(x1)}" y1="${r(y1)}" x2="${r(x2)}" y2="${r(y2)}" stroke="${st.color ?? '#333'}" stroke-width="${lw}" stroke-linecap="round"${dash}${marker}${shadow}/>`
    } else {
        const fill = svgFill(defs, el.fill)
        const inset = sw / 2
        const d = shapePath(el.shape, Math.max(1, w - sw), Math.max(1, h - sw), el.radius ?? 24)
        body = `<path d="${d}" transform="translate(${r(inset)} ${r(inset)})" fill="${fill}" fill-rule="evenodd" stroke="${sw ? st.color ?? 'none' : 'none'}" stroke-width="${sw}" stroke-linejoin="round"${dash}${shadow}/>`
    }
    // 渐变 id 需要在同一文档内唯一：放大 viewBox 边界避免描边被裁剪
    return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 ${r(w)} ${r(h)}" preserveAspectRatio="none" style="overflow:visible;display:block">${defs.length ? `<defs>${defs.join('')}</defs>` : ''}${body}</svg>`
}

// ---------- 图表 ----------
export function chartSVG(chart, w, h, t) {
    const out = []
    const title = chart.title ? 70 : 20
    const legendH = chart.legend !== false && chart.kind !== 'pie' ? 60 : 0
    const textColor = t?.text ?? '#334155'
    const font = `font-family="${esc(t?.font ?? 'sans-serif')}"`
    if (chart.title) out.push(`<text x="${w / 2}" y="46" text-anchor="middle" font-size="36" font-weight="700" fill="${t?.title ?? '#0f172a'}" ${font}>${esc(chart.title)}</text>`)
    const series = chart.series ?? []
    const labels = chart.labels ?? []
    const colorOf = (s, i) => s.color ?? CHART_COLORS[i % CHART_COLORS.length]
    if (chart.kind === 'pie' || chart.kind === 'doughnut') {
        const s = series[0] ?? { values: [] }
        const vals = s.values.map(v => Math.max(0, Number(v) || 0))
        const sum = vals.reduce((a, b) => a + b, 0) || 1
        const cx = w * 0.38, cy = title + (h - title) / 2, R = Math.min(w * 0.3, (h - title) / 2 - 20)
        let a = -Math.PI / 2
        vals.forEach((v, i) => {
            const da = v / sum * Math.PI * 2
            const c = s.colors?.[i] ?? CHART_COLORS[i % CHART_COLORS.length]
            const x1 = cx + R * Math.cos(a), y1 = cy + R * Math.sin(a), x2 = cx + R * Math.cos(a + da), y2 = cy + R * Math.sin(a + da)
            out.push(da >= Math.PI * 2 - 1e-6
                ? `<circle cx="${cx}" cy="${cy}" r="${R}" fill="${c}"/>`
                : `<path d="M${cx} ${cy}L${r(x1)} ${r(y1)}A${R} ${R} 0 ${da > Math.PI ? 1 : 0} 1 ${r(x2)} ${r(y2)}Z" fill="${c}" stroke="#fff" stroke-width="3"/>`)
            const m = a + da / 2
            if (v / sum > 0.04) out.push(`<text x="${r(cx + R * 0.68 * Math.cos(m))}" y="${r(cy + R * 0.68 * Math.sin(m))}" text-anchor="middle" dominant-baseline="central" font-size="26" font-weight="700" fill="#fff" ${font}>${Math.round(v / sum * 100)}%</text>`)
            a += da
        })
        if (chart.kind === 'doughnut') out.push(`<circle cx="${cx}" cy="${cy}" r="${R * 0.52}" fill="#fff"/>`)
        labels.forEach((l, i) => {
            const y = cy - labels.length * 22 + i * 44 + 10
            out.push(`<rect x="${w * 0.72}" y="${y - 14}" width="26" height="26" rx="6" fill="${s.colors?.[i] ?? CHART_COLORS[i % CHART_COLORS.length]}"/><text x="${w * 0.72 + 38}" y="${y}" dominant-baseline="central" font-size="26" fill="${textColor}" ${font}>${esc(l)}</text>`)
        })
    } else {
        const pl = 90, pr = 30, pt = title + 10, pb = 60 + legendH
        const cw = w - pl - pr, ch = h - pt - pb
        const all = series.flatMap(s => s.values.map(Number).filter(Number.isFinite))
        let max = Math.max(0, ...all), min = Math.min(0, ...all)
        if (max === min) max = min + 1
        const step = niceStep((max - min) / 5)
        max = Math.ceil(max / step) * step
        min = Math.floor(min / step) * step
        const Y = v => pt + ch - (v - min) / (max - min) * ch
        for (let v = min; v <= max + 1e-9; v += step) {
            out.push(`<line x1="${pl}" x2="${w - pr}" y1="${r(Y(v))}" y2="${r(Y(v))}" stroke="${v === 0 ? '#94a3b8' : '#e2e8f0'}" stroke-width="${v === 0 ? 2 : 1.5}"/>`)
            out.push(`<text x="${pl - 14}" y="${r(Y(v))}" text-anchor="end" dominant-baseline="central" font-size="22" fill="${textColor}" opacity=".75" ${font}>${fmtNum(v)}</text>`)
        }
        const n = Math.max(1, labels.length)
        const bw = cw / n
        labels.forEach((l, i) => out.push(`<text x="${r(pl + bw * (i + 0.5))}" y="${pt + ch + 34}" text-anchor="middle" font-size="24" fill="${textColor}" ${font}>${esc(l)}</text>`))
        if (chart.kind === 'bar') {
            const gw = bw * 0.7, sw = gw / Math.max(1, series.length)
            series.forEach((s, si) => s.values.forEach((v, i) => {
                v = Number(v) || 0
                const x = pl + bw * i + (bw - gw) / 2 + sw * si, y0 = Y(Math.max(0, v)), y1 = Y(Math.min(0, v))
                out.push(`<rect x="${r(x + 3)}" y="${r(y0)}" width="${r(sw - 6)}" height="${r(Math.max(1, y1 - y0))}" rx="6" fill="${colorOf(s, si)}"/>`)
            }))
        } else {
            series.forEach((s, si) => {
                const pts = s.values.map((v, i) => [pl + bw * (i + 0.5), Y(Number(v) || 0)])
                const c = colorOf(s, si)
                if (chart.kind === 'area') out.push(`<path d="M${r(pts[0]?.[0] ?? pl)} ${r(Y(Math.max(min, 0)))}L${pts.map(p => `${r(p[0])} ${r(p[1])}`).join('L')}L${r(pts.at(-1)?.[0] ?? pl)} ${r(Y(Math.max(min, 0)))}Z" fill="${c}" opacity=".25"/>`)
                out.push(`<polyline points="${pts.map(p => `${r(p[0])},${r(p[1])}`).join(' ')}" fill="none" stroke="${c}" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>`)
                for (const p of pts) out.push(`<circle cx="${r(p[0])}" cy="${r(p[1])}" r="9" fill="#fff" stroke="${c}" stroke-width="5"/>`)
            })
        }
        if (legendH) {
            let x = pl
            const y = h - 30
            series.forEach((s, si) => {
                out.push(`<rect x="${x}" y="${y - 13}" width="26" height="26" rx="6" fill="${colorOf(s, si)}"/><text x="${x + 36}" y="${y}" dominant-baseline="central" font-size="24" fill="${textColor}" ${font}>${esc(s.name)}</text>`)
                x += 70 + String(s.name ?? '').length * 26
            })
        }
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 ${r(w)} ${r(h)}" preserveAspectRatio="none" style="display:block">${out.join('')}</svg>`
}
function niceStep(raw) {
    const k = Math.pow(10, Math.floor(Math.log10(raw || 1)))
    for (const m of [1, 2, 2.5, 5, 10]) if (m * k >= raw) return m * k
    return 10 * k
}
const fmtNum = v => Math.abs(v) >= 1000 ? (v / 1000).toFixed(v % 1000 ? 1 : 0) + 'k' : String(Math.round(v * 100) / 100)

// ---------- 元素 ----------
export function textStyle(st = {}) {
    return {
        fontFamily: st.font, fontSize: (st.size ?? 36) + 'px', color: st.color,
        textAlign: st.align ?? 'left', lineHeight: String(st.lineHeight ?? 1.35),
        fontWeight: st.bold ? '700' : '400', fontStyle: st.italic ? 'italic' : 'normal',
        textDecoration: [st.underline && 'underline', st.strike && 'line-through'].filter(Boolean).join(' ') || 'none',
        justifyContent: { top: 'flex-start', middle: 'center', bottom: 'flex-end' }[st.valign ?? 'top'],
        letterSpacing: st.spacing ? st.spacing + 'px' : null,
    }
}

// 渲染单个元素；opts.editing: 是否为编辑画布（显示占位提示）
export function renderEl(el, deck, opts = {}) {
    const t = themeOf(deck)
    const node = h('div.sl-el.sl-type-' + el.type, {
        dataset: { id: el.id },
        style: {
            left: el.x + 'px', top: el.y + 'px', width: el.w + 'px', height: el.h + 'px',
            transform: el.rot ? `rotate(${el.rot}deg)` : null,
            opacity: el.opacity != null && el.type !== 'image' ? String(el.opacity) : null,
        },
    })
    switch (el.type) {
        case 'text': {
            node.style.background = fillCSS(el.fill)
            if (el.stroke?.width) node.style.border = `${el.stroke.width}px solid ${el.stroke.color}`
            const box = h('div.sl-text' + (el.list ? '.is-list' : ''), { style: textStyle(el.style) })
            const empty = !String(el.html ?? '').replace(/<[^>]+>|&nbsp;|\s/g, '')
            if (empty && opts.editing && el.placeholder) box.append(h('div.sl-ph', el.placeholder))
            else box.innerHTML = el.html ?? ''
            if (empty && !opts.editing) box.innerHTML = ''
            node.append(box)
            break
        }
        case 'shape': {
            node.innerHTML = shapeSVG(el)
            if (el.html || el.style) {
                const txt = h('div.sl-text.sl-shape-text', { style: { ...textStyle({ align: 'center', valign: 'middle', color: '#ffffff', size: 36, font: t.font, ...(el.style ?? {}) }) } })
                txt.innerHTML = el.html ?? ''
                node.append(txt)
            }
            break
        }
        case 'image': {
            const img = h('img', {
                src: el.src, draggable: false,
                style: {
                    objectFit: el.fit ?? 'cover', borderRadius: (el.radius ?? 0) + 'px', opacity: String(el.opacity ?? 1),
                    filter: [el.brightness != null && el.brightness !== 100 && `brightness(${el.brightness}%)`, el.contrast != null && el.contrast !== 100 && `contrast(${el.contrast}%)`, el.grayscale && 'grayscale(1)'].filter(Boolean).join(' ') || null,
                    border: el.border?.width ? `${el.border.width}px solid ${el.border.color}` : null,
                    boxShadow: el.shadow ? '0 14px 40px rgb(0 0 0 / .3)' : null,
                },
            })
            node.append(img)
            break
        }
        case 'table': {
            const st = { header: true, band: true, color: t.accent, border: '#cbd5e1', size: 28, ...(el.style ?? {}) }
            const table = h('table.sl-table', { style: { fontSize: st.size + 'px', fontFamily: t.font, color: t.text, '--tc': st.color, '--tb': st.border } })
            el.rows.forEach((row, ri) => {
                const tr = h('tr' + (ri === 0 && st.header ? '.head' : '') + (st.band && ri % 2 === 0 && ri > 0 ? '.band' : ''))
                row.forEach((cell, ci) => {
                    const td = h(ri === 0 && st.header ? 'th' : 'td', { dataset: { r: ri, c: ci } })
                    td.innerHTML = cell
                    tr.append(td)
                })
                table.append(tr)
            })
            node.append(table)
            break
        }
        case 'chart': node.innerHTML = chartSVG(el.chart, el.w, el.h, t); break
        case 'math': {
            const box = h('div.sl-math', { style: { color: el.color ?? t.text, fontSize: (el.size ?? 48) + 'px' } })
            try { box.innerHTML = katex.renderToString(el.tex ?? '', { displayMode: true, throwOnError: false, output: 'html' }) } catch { box.textContent = el.tex }
            node.append(box)
            break
        }
        case 'icon': {
            node.innerHTML = el.svg ?? ''
            const svg = node.querySelector('svg')
            if (svg) { svg.setAttribute('width', '100%'); svg.setAttribute('height', '100%'); svg.style.color = el.color ?? t.accent; svg.setAttribute('stroke-width', el.strokeWidth ?? 1.6) }
            break
        }
    }
    return node
}

// 渲染整张幻灯片（逻辑尺寸），返回 .sl-slide 元素
export function renderSlide(slide, deck, opts = {}) {
    const { w, h: H } = sizeOf(deck)
    const t = themeOf(deck)
    const el = h('div.sl-slide', { style: { width: w + 'px', height: H + 'px', background: fillCSS(slide.bg ?? t.bg), fontFamily: t.font } })
    for (const e of slide.els) el.append(renderEl(e, deck, opts))
    return el
}

// 按比例缩放放入容器：返回包裹元素
export function scaledSlide(slide, deck, width, opts) {
    const { w, h: H } = sizeOf(deck)
    const k = width / w
    const inner = renderSlide(slide, deck, opts)
    inner.style.transform = `scale(${k})`
    inner.style.transformOrigin = '0 0'
    return h('div.sl-scaled', { style: { width: width + 'px', height: H * k + 'px' } }, inner)
}

// 独立 HTML（导出 PDF 用）
export function slidesHTML(deck, slides, css) {
    const { w, h: H } = sizeOf(deck)
    const pages = slides.map(s => renderSlide(s, deck).outerHTML).join('\n')
    return `<!DOCTYPE html><html><head><meta charset="utf-8"><link rel="stylesheet" href="app://local/vendor/katex/katex.min.css"><style>
@page { size: ${w}px ${H}px; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.sl-slide { page-break-after: always; break-after: page; overflow: hidden; }
${css}
</style></head><body>${pages}</body></html>`
}
