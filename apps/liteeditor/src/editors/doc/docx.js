// HTML → DOCX（docx 库）
// 支持：标题、段落对齐 / 缩进 / 行距、粗斜下划线删除线、上下标、颜色、高亮、字体字号、
// 有序 / 无序 / 任务列表（多级）、表格（合并单元格、底色）、图片、超链接、分页符、分隔线、代码块、引用、公式（转为图片）、页眉页脚页码
import {
    Document, Packer, Paragraph, TextRun, ImageRun, Table, TableRow, TableCell, HeadingLevel, AlignmentType,
    ExternalHyperlink, PageBreak, Footer, Header, PageNumber, LevelFormat, WidthType, BorderStyle, ShadingType,
    PageOrientation, LineRuleType,
} from 'docx'

const PX_TO_TWIP = 15 // 1px = 15 twip（96 dpi）
const MM_TO_TWIP = 56.7
const ALIGN = { left: AlignmentType.LEFT, center: AlignmentType.CENTER, right: AlignmentType.RIGHT, justify: AlignmentType.JUSTIFIED }
const HEAD = { H1: HeadingLevel.HEADING_1, H2: HeadingLevel.HEADING_2, H3: HeadingLevel.HEADING_3, H4: HeadingLevel.HEADING_4, H5: HeadingLevel.HEADING_5, H6: HeadingLevel.HEADING_6 }
const HIGHLIGHT = { '#ffff00': 'yellow', '#fef08a': 'yellow', '#fde047': 'yellow', '#bbf7d0': 'green', '#86efac': 'green', '#bfdbfe': 'cyan', '#a5f3fc': 'cyan', '#fbcfe8': 'magenta', '#f9a8d4': 'magenta', '#fed7aa': 'yellow', '#e5e7eb': 'lightGray' }

function hex(c) {
    if (!c) return undefined
    const ctx = hex.ctx ??= document.createElement('canvas').getContext('2d')
    ctx.fillStyle = '#000000'
    ctx.fillStyle = c
    const v = ctx.fillStyle
    if (v.startsWith('#')) return v.slice(1).toUpperCase()
    const m = v.match(/[\d.]+/g)
    if (!m || (m[3] !== undefined && Number(m[3]) === 0)) return undefined
    return m.slice(0, 3).map(n => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase()
}
const ptFromCSS = v => {
    if (!v) return undefined
    const n = parseFloat(v)
    if (/pt$/.test(v)) return n
    if (/px$/.test(v)) return n * 0.75
    if (/em$/.test(v)) return n * 12
    return undefined
}
const fontName = f => f ? f.split(',')[0].replace(/["']/g, '').trim() : undefined

export async function htmlToDocx(root, page, { lossy }) {
    const children = []
    const numbering = []
    let numId = 0
    const images = []

    // 行内节点 → runs
    const runs = async (node, st = {}) => {
        const out = []
        for (const n of node.childNodes) {
            if (n.nodeType === 3) {
                const text = n.textContent.replace(/\n/g, ' ')
                if (text) out.push(new TextRun({ text, ...st }))
                continue
            }
            if (n.nodeType !== 1) continue
            const t = n.tagName
            const s = { ...st }
            if (t === 'B' || t === 'STRONG') s.bold = true
            if (t === 'I' || t === 'EM') s.italics = true
            if (t === 'U') s.underline = {}
            if (t === 'S' || t === 'STRIKE' || t === 'DEL') s.strike = true
            if (t === 'SUP') s.superScript = true
            if (t === 'SUB') s.subScript = true
            if (t === 'CODE') { s.font = 'Consolas'; s.shading = { type: ShadingType.CLEAR, fill: 'F1F5F9', color: 'auto' } }
            if (t === 'MARK') s.highlight = 'yellow'
            const css = n.style
            if (css?.fontWeight && (css.fontWeight === 'bold' || Number(css.fontWeight) >= 600)) s.bold = true
            if (css?.fontStyle === 'italic') s.italics = true
            if (css?.textDecoration?.includes('underline') || css?.textDecorationLine?.includes('underline')) s.underline = {}
            if (css?.textDecoration?.includes('line-through') || css?.textDecorationLine?.includes('line-through')) s.strike = true
            if (css?.color) s.color = hex(css.color)
            if (css?.fontSize) { const p = ptFromCSS(css.fontSize); if (p) s.size = Math.round(p * 2) }
            if (css?.fontFamily) s.font = fontName(css.fontFamily)
            if (css?.backgroundColor) {
                const c = hex(css.backgroundColor)
                if (c) {
                    const hl = HIGHLIGHT['#' + c.toLowerCase()]
                    if (hl) s.highlight = hl
                    else s.shading = { type: ShadingType.CLEAR, fill: c, color: 'auto' }
                }
            }
            if (t === 'FONT') {
                if (n.getAttribute('color')) s.color = hex(n.getAttribute('color'))
                if (n.getAttribute('face')) s.font = fontName(n.getAttribute('face'))
            }
            if (t === 'BR') { out.push(new TextRun({ break: 1, ...st })); continue }
            if (t === 'IMG') { const r = await imageRun(n); if (r) out.push(r); continue }
            if (n.classList.contains('doc-math')) { const r = await mathRun(n); if (r) out.push(r); continue }
            if (n.classList.contains('doc-footnote-ref')) { out.push(new TextRun({ text: n.textContent, superScript: true, ...st })); continue }
            if (t === 'A' && n.getAttribute('href')) {
                const inner = await runs(n, { ...s, style: 'Hyperlink', color: '2563EB', underline: {} })
                out.push(new ExternalHyperlink({ link: n.getAttribute('href'), children: inner.length ? inner : [new TextRun({ text: n.href })] }))
                continue
            }
            out.push(...await runs(n, s))
        }
        return out
    }

    async function imageRun(img) {
        try {
            const src = img.getAttribute('src')
            if (!src) return null
            const res = await fetch(src)
            const blob = await res.blob()
            let data = new Uint8Array(await blob.arrayBuffer())
            let type = (blob.type.split('/')[1] ?? 'png').replace('jpeg', 'jpg')
            // docx 仅支持 png / jpg / gif / bmp：其他格式转为 png
            if (!['png', 'jpg', 'gif', 'bmp'].includes(type)) { data = await toPNG(img); type = 'png' }
            const w = img.width || img.naturalWidth || 300, h = img.height || img.naturalHeight || 200
            const maxW = (page.contentWidthPx ?? 600)
            const k = Math.min(1, maxW / w)
            images.push(1)
            return new ImageRun({ type, data, transformation: { width: Math.round(w * k), height: Math.round(h * k) } })
        } catch (e) { console.warn(e); return null }
    }
    async function mathRun(node) {
        lossy.add('公式（已转为图片）')
        const data = await renderToPNG(node)
        if (!data) return new TextRun({ text: node.dataset.tex, font: 'Cambria Math' })
        const r = node.getBoundingClientRect()
        return new ImageRun({ type: 'png', data: data.bytes, transformation: { width: Math.max(8, Math.round(r.width || data.w / 2)), height: Math.max(8, Math.round(r.height || data.h / 2)) } })
    }

    const paraProps = el => {
        const css = el.style ?? {}
        const p = {}
        const align = css.textAlign || el.getAttribute?.('align')
        if (ALIGN[align]) p.alignment = ALIGN[align]
        const ind = {}
        if (css.marginLeft) ind.left = Math.round(parseFloat(css.marginLeft) * PX_TO_TWIP)
        if (css.paddingLeft && el.tagName === 'BLOCKQUOTE') ind.left = Math.round(parseFloat(css.paddingLeft) * PX_TO_TWIP)
        if (css.textIndent) ind.firstLine = Math.round(parseFloat(css.textIndent) * (css.textIndent.endsWith('em') ? 16 * PX_TO_TWIP : PX_TO_TWIP))
        if (Object.keys(ind).length) p.indent = ind
        const sp = {}
        if (css.lineHeight && !isNaN(Number(css.lineHeight))) { sp.line = Math.round(Number(css.lineHeight) * 240); sp.lineRule = LineRuleType.AUTO }
        if (css.marginTop) sp.before = Math.round(parseFloat(css.marginTop) * PX_TO_TWIP)
        if (css.marginBottom) sp.after = Math.round(parseFloat(css.marginBottom) * PX_TO_TWIP)
        if (Object.keys(sp).length) p.spacing = sp
        return p
    }

    const list = async (el, level, ref) => {
        const ordered = el.tagName === 'OL'
        let reference = ref
        if (!reference) {
            reference = 'list' + (++numId)
            numbering.push({
                reference,
                levels: Array.from({ length: 9 }, (_, i) => ({
                    level: i,
                    format: ordered ? [LevelFormat.DECIMAL, LevelFormat.LOWER_LETTER, LevelFormat.LOWER_ROMAN][i % 3] : LevelFormat.BULLET,
                    text: ordered ? `%${i + 1}.` : ['●', '○', '■'][i % 3],
                    alignment: AlignmentType.LEFT,
                    style: { paragraph: { indent: { left: 420 * (i + 1), hanging: 360 } } },
                })),
            })
        }
        for (const li of el.children) {
            if (li.tagName !== 'LI') continue
            const nested = [...li.children].filter(c => c.tagName === 'UL' || c.tagName === 'OL')
            const shallow = li.cloneNode(true)
            shallow.querySelectorAll(':scope > ul, :scope > ol').forEach(x => x.remove())
            const r = await runs(shallow)
            if (li.classList.contains('task')) r.unshift(new TextRun({ text: li.classList.contains('done') ? '☑ ' : '☐ ' }))
            children.push(new Paragraph({ children: r, numbering: li.classList.contains('task') ? undefined : { reference, level }, indent: li.classList.contains('task') ? { left: 420 * (level + 1) } : undefined, ...paraProps(li) }))
            for (const c of nested) await list(c, level + 1, c.tagName === el.tagName ? reference : null)
        }
    }

    const table = async el => {
        const rows = []
        const grid = [...el.querySelectorAll(':scope > tbody > tr, :scope > thead > tr, :scope > tr')]
        const cols = Math.max(1, ...grid.map(tr => [...tr.children].reduce((s, c) => s + (c.colSpan || 1), 0)))
        const border = { style: BorderStyle.SINGLE, size: 4, color: 'A0A7B4' }
        for (const tr of grid) {
            const cells = []
            for (const td of tr.children) {
                const paras = []
                const blocks = [...td.childNodes].some(n => n.nodeType === 1 && /^(P|DIV|H\d|UL|OL)$/.test(n.tagName))
                if (blocks) {
                    for (const b of td.childNodes) {
                        if (b.nodeType === 1 && /^(P|DIV|H\d)$/.test(b.tagName)) paras.push(new Paragraph({ children: await runs(b, td.tagName === 'TH' ? { bold: true } : {}), ...paraProps(b) }))
                        else if (b.nodeType === 3 && b.textContent.trim()) paras.push(new Paragraph({ children: [new TextRun(b.textContent)] }))
                    }
                } else paras.push(new Paragraph({ children: await runs(td, td.tagName === 'TH' ? { bold: true } : {}), ...paraProps(td) }))
                const bg = hex(td.style.backgroundColor)
                cells.push(new TableCell({
                    children: paras.length ? paras : [new Paragraph('')],
                    columnSpan: td.colSpan > 1 ? td.colSpan : undefined,
                    rowSpan: td.rowSpan > 1 ? td.rowSpan : undefined,
                    shading: bg ? { type: ShadingType.CLEAR, fill: bg, color: 'auto' } : td.tagName === 'TH' ? { type: ShadingType.CLEAR, fill: 'F1F5F9', color: 'auto' } : undefined,
                    margins: { top: 60, bottom: 60, left: 100, right: 100 },
                    borders: { top: border, bottom: border, left: border, right: border },
                }))
            }
            rows.push(new TableRow({ children: cells, tableHeader: tr.parentElement?.tagName === 'THEAD' }))
        }
        if (!rows.length) return
        children.push(new Table({ rows, width: { size: 100, type: WidthType.PERCENTAGE }, columnWidths: Array(cols).fill(Math.round(9000 / cols)) }))
        children.push(new Paragraph(''))
    }

    const block = async el => {
        if (el.nodeType === 3) { if (el.textContent.trim()) children.push(new Paragraph({ children: [new TextRun(el.textContent)] })); return }
        if (el.nodeType !== 1) return
        const t = el.tagName
        if (HEAD[t]) {
            const heading = el.classList.contains('doc-title') ? HeadingLevel.TITLE : HEAD[t]
            children.push(new Paragraph({ heading, children: await runs(el), ...paraProps(el) }))
            return
        }
        if (el.classList.contains('page-break')) { children.push(new Paragraph({ children: [new PageBreak()] })); return }
        if (el.classList.contains('doc-toc')) {
            lossy.add('目录（已转为静态文本）')
            for (const a of el.querySelectorAll('.toc-item')) children.push(new Paragraph({ children: [new TextRun(a.textContent)], indent: { left: (Number(a.dataset.level) - 1) * 400 } }))
            return
        }
        if (el.classList.contains('doc-math') || el.classList.contains('doc-math-block')) {
            const m = el.classList.contains('doc-math') ? el : el.querySelector('.doc-math')
            children.push(new Paragraph({ alignment: AlignmentType.CENTER, children: m ? [await mathRun(m)] : [] }))
            return
        }
        if (t === 'P' || t === 'DIV' || t === 'FIGURE' || t === 'SECTION' || t === 'ARTICLE') {
            // 含块级子元素的 div：递归
            if ([...el.children].some(c => /^(P|DIV|H\d|UL|OL|TABLE|BLOCKQUOTE|PRE|HR|FIGURE)$/.test(c.tagName))) { for (const c of el.childNodes) await block(c); return }
            children.push(new Paragraph({ children: await runs(el), ...paraProps(el) }))
            return
        }
        if (t === 'BLOCKQUOTE') {
            children.push(new Paragraph({
                children: await runs(el, { italics: true, color: '475569' }),
                indent: { left: 480 }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: 'CBD5E1', space: 12 } },
            }))
            return
        }
        if (t === 'PRE') {
            for (const line of el.textContent.replace(/\n$/, '').split('\n')) {
                children.push(new Paragraph({ children: [new TextRun({ text: line || ' ', font: 'Consolas', size: 19 })], shading: { type: ShadingType.CLEAR, fill: 'F1F5F9', color: 'auto' }, spacing: { before: 0, after: 0 } }))
            }
            children.push(new Paragraph(''))
            return
        }
        if (t === 'HR') { children.push(new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: 'CBD5E1', space: 1 } } })); return }
        if (t === 'UL' || t === 'OL') return list(el, 0)
        if (t === 'TABLE') return table(el)
        if (t === 'IMG') { const r = await imageRun(el); if (r) children.push(new Paragraph({ children: [r], ...paraProps(el) })); return }
        children.push(new Paragraph({ children: await runs(el) }))
    }

    for (const c of root.childNodes) await block(c)

    // 页面
    const size = { width: Math.round(page.w * MM_TO_TWIP), height: Math.round(page.h * MM_TO_TWIP) }
    const m = page.margin
    const footer = page.pageNumbers ? new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ children: [PageNumber.CURRENT] }), new TextRun(' / '), new TextRun({ children: [PageNumber.TOTAL_PAGES] })] })] }) : undefined
    const header = page.header ? new Header({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: page.header, color: '64748B', size: 18 })] })] }) : undefined
    const doc = new Document({
        creator: 'LiteEditor',
        styles: {
            default: {
                document: { run: { font: fontName(page.font) ?? 'SimSun', size: Math.round((page.fontSize ?? 16) * 0.75 * 2) }, paragraph: { spacing: { line: Math.round((page.lineHeight ?? 1.6) * 240), after: 120 } } },
                heading1: { run: { size: 44, bold: true, color: '111827' }, paragraph: { spacing: { before: 360, after: 180 } } },
                heading2: { run: { size: 36, bold: true, color: '111827' }, paragraph: { spacing: { before: 300, after: 150 } } },
                heading3: { run: { size: 30, bold: true, color: '1F2937' }, paragraph: { spacing: { before: 240, after: 120 } } },
                title: { run: { size: 56, bold: true, color: '0F172A' }, paragraph: { alignment: AlignmentType.CENTER, spacing: { after: 240 } } },
            },
        },
        numbering: { config: numbering },
        sections: [{
            properties: {
                page: {
                    size: { ...size, orientation: page.landscape ? PageOrientation.LANDSCAPE : PageOrientation.PORTRAIT },
                    margin: { top: Math.round(m.top * MM_TO_TWIP), bottom: Math.round(m.bottom * MM_TO_TWIP), left: Math.round(m.left * MM_TO_TWIP), right: Math.round(m.right * MM_TO_TWIP) },
                },
            },
            headers: header ? { default: header } : undefined,
            footers: footer ? { default: footer } : undefined,
            children: children.length ? children : [new Paragraph('')],
        }],
    })
    const blob = await Packer.toBlob(doc)
    return new Uint8Array(await blob.arrayBuffer())
}

async function toPNG(img) {
    const c = document.createElement('canvas')
    c.width = img.naturalWidth || 300
    c.height = img.naturalHeight || 200
    c.getContext('2d').drawImage(img, 0, 0)
    const b = await new Promise(r => c.toBlob(r, 'image/png'))
    return new Uint8Array(await b.arrayBuffer())
}

// 通过 SVG foreignObject 把节点（KaTeX 公式）栅格化为 PNG
export async function renderToPNG(node, scale = 3) {
    const r = node.getBoundingClientRect()
    const w = Math.ceil(r.width) + 4, hh = Math.ceil(r.height) + 4
    if (!w || !hh) return null
    const css = [...document.styleSheets].map(s => { try { return [...s.cssRules].map(x => x.cssText).filter(t => t.includes('.katex')).join('\n') } catch { return '' } }).join('\n').replace(/url\([^)]*\)/g, 'none')
    const clone = node.cloneNode(true)
    clone.style.color = '#000'
    const xhtml = new XMLSerializer().serializeToString(clone)
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w * scale}" height="${hh * scale}"><foreignObject width="${w}" height="${hh}" transform="scale(${scale})"><div xmlns="http://www.w3.org/1999/xhtml" style="font-size:${getComputedStyle(node).fontSize};padding:2px"><style>${css}</style>${xhtml}</div></foreignObject></svg>`
    const img = new Image()
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
    try { await img.decode() } catch { return null }
    const c = document.createElement('canvas')
    c.width = w * scale; c.height = hh * scale
    c.getContext('2d').drawImage(img, 0, 0)
    const b = await new Promise(res => c.toBlob(res, 'image/png'))
    return { bytes: new Uint8Array(await b.arrayBuffer()), w: c.width, h: c.height }
}
