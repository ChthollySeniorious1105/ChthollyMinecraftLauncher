// 导出：CSV / TSV、HTML 表格、PDF、打印
import { display, defaultAlign, fontFamily, parseBorder, borderWidth } from './format.js'
import { chartSVG } from './chart.js'

// 已用区域中可见的行列
function usedArea(ed, sh) {
    const b = sh.bounds()
    const rows = [], cols = []
    const m = sh.meta
    const hiddenR = new Set([...m.hiddenR, ...(m.filter?.hidden ?? [])])
    for (let r = 0; r <= b.r2; r++) if (!hiddenR.has(r)) rows.push(r)
    for (let c = 0; c <= b.c2; c++) if (!m.hiddenC.has(c)) cols.push(c)
    return { rows, cols }
}

export function cellText(ed, sh, r, c) {
    const cell = sh.get(r, c)
    if (!cell) return ''
    const v = ed.valueOf(sh, r, c, cell)
    return display(v, sh.styleAt(r, c, cell)?.fmt).text ?? ''
}

export function writeCSV(ed, sep = ',', sh = ed.sheet) {
    const { rows, cols } = usedArea(ed, sh)
    const q = s => /[",\n\r\t]/.test(s) || (sep !== ',' && s.includes(sep)) ? `"${s.replace(/"/g, '""')}"` : s
    const lines = rows.map(r => cols.map(c => {
        const cell = sh.get(r, c)
        if (!cell) return ''
        const v = ed.valueOf(sh, r, c, cell)
        // 数字保留原始精度（不套用显示格式），其余按显示文本
        return q(typeof v === 'number' && !sh.styleAt(r, c, cell)?.fmt ? String(v) : cellText(ed, sh, r, c))
    }).join(sep).replace(new RegExp(`${escapeRe(sep)}+$`), ''))
    // UTF-8 BOM：Excel 打开中文 CSV 不乱码
    return '﻿' + lines.join('\r\n') + '\r\n'
}
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

// 单个工作表 → <table>（保留样式、合并、列宽）
export function sheetTable(ed, sh, { gridlines = true } = {}) {
    const { rows, cols } = usedArea(ed, sh)
    const m = sh.meta
    const covered = new Set()
    const mergeAt = new Map()
    for (const g of m.merges) {
        mergeAt.set(g.r1 * 16384 + g.c1, g)
        for (let r = g.r1; r <= g.r2; r++) for (let c = g.c1; c <= g.c2; c++) if (r !== g.r1 || c !== g.c1) covered.add(r * 16384 + c)
    }
    const cf = ed.cfFor(sh)
    const colgroup = `<colgroup>${cols.map(c => `<col style="width:${sh.colWidth(c)}px">`).join('')}</colgroup>`
    const body = rows.map(r => {
        const tds = cols.map(c => {
            const k = r * 16384 + c
            if (covered.has(k)) return ''
            const cell = sh.get(r, c)
            const st = sh.styleAt(r, c, cell) ?? {}
            const v = cell ? ed.valueOf(sh, r, c, cell) : null
            const cfr = cf?.length ? ed.cfResult(cf, r, c, v) : null
            const d = display(v, st.fmt)
            const css = []
            if (st.font) css.push(`font-family:${fontFamily(st.font)}`)
            if (st.sz) css.push(`font-size:${st.sz}pt`)
            if (st.b || cfr?.b) css.push('font-weight:bold')
            if (st.i) css.push('font-style:italic')
            const deco = [st.u && 'underline', st.st && 'line-through'].filter(Boolean)
            if (deco.length) css.push(`text-decoration:${deco.join(' ')}`)
            const color = cfr?.color ?? d.color ?? st.color
            if (color) css.push(`color:${color}`)
            const fill = cfr?.fill ?? st.fill
            if (fill) css.push(`background:${fill}`)
            css.push(`text-align:${st.ha ?? defaultAlign(v)}`)
            css.push(`vertical-align:${st.va === 'top' ? 'top' : st.va === 'bottom' ? 'bottom' : 'middle'}`)
            if (st.wrap) css.push('white-space:pre-wrap')
            for (const [side, key] of [['top', 'bt'], ['right', 'br'], ['bottom', 'bb'], ['left', 'bl']]) {
                const bd = parseBorder(st[key])
                if (bd) css.push(`border-${side}:${borderWidth(bd.style)}px ${bd.style === 'dashed' ? 'dashed' : bd.style === 'dotted' || bd.style === 'hair' ? 'dotted' : bd.style === 'double' ? 'double' : 'solid'} ${bd.color}`)
            }
            if (cfr?.bar) css.push(`background:linear-gradient(90deg, ${cfr.bar.color} ${Math.round(cfr.bar.t * 100)}%, transparent 0)`)
            const g = mergeAt.get(k)
            const span = g ? ` colspan="${cols.filter(x => x >= g.c1 && x <= g.c2).length}" rowspan="${rows.filter(x => x >= g.r1 && x <= g.r2).length}"` : ''
            return `<td${span} style="${css.join(';')}">${esc(d.text ?? '')}</td>`
        }).join('')
        return `<tr style="height:${sh.rowHeight(r)}px">${tds}</tr>`
    }).join('\n')
    return `<table class="sheet${gridlines && m.showGrid !== false ? ' grid' : ''}">${colgroup}<tbody>${body}</tbody></table>`
}

// 图表：按图表所在的锚点单元格放在表格之后
function chartsHTML(ed, sh) {
    return (sh.meta.charts ?? []).map(ch => {
        try { return `<div class="chart" style="width:${ch.w}px;height:${ch.h}px">${chartSVG(ed, ch, ch.w, ch.h)}</div>` } catch { return '' }
    }).join('')
}

const TABLE_CSS = `
body { font-family: "Microsoft YaHei", "Segoe UI", sans-serif; font-size: 11pt; color: #1f2328; margin: 0; }
h2 { font-size: 14pt; margin: 18px 0 8px; }
table.sheet { border-collapse: collapse; table-layout: fixed; }
table.sheet td { padding: 2px 5px; overflow: hidden; white-space: nowrap; font-size: 11pt; }
table.sheet.grid td { border: 1px solid #d0d4da; }
.chart { display: inline-block; margin: 14px 14px 0 0; border: 1px solid #e2e8f0; border-radius: 6px; page-break-inside: avoid; }
.page { page-break-after: always; }
.page:last-child { page-break-after: auto; }
`

export function writeHTML(ed, { all = true } = {}) {
    const sheets = all ? ed.book.sheets : [ed.sheet]
    const pages = sheets.map(sh => `<section class="page">${sheets.length > 1 ? `<h2>${esc(sh.name)}</h2>` : ''}${sheetTable(ed, sh)}${chartsHTML(ed, sh)}</section>`).join('\n')
    return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>${esc(ed.name)}</title><style>${TABLE_CSS} body { margin: 24px; }</style></head><body>${pages}</body></html>`
}

function printHTML(ed, { all = false, landscape = true, gridlines = true } = {}) {
    const sheets = all ? ed.book.sheets : [ed.sheet]
    const pages = sheets.map(sh => `<section class="page">${all && sheets.length > 1 ? `<h2>${esc(sh.name)}</h2>` : ''}${sheetTable(ed, sh, { gridlines })}${chartsHTML(ed, sh)}</section>`).join('\n')
    return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><style>
@page { size: A4 ${landscape ? 'landscape' : 'portrait'}; margin: 12mm; }
${TABLE_CSS}
table.sheet td { font-size: 9pt; }
</style></head><body>${pages}</body></html>`
}

export async function writePDF(ed, opts = {}) {
    return window.lite.htmlToPdf(printHTML(ed, opts), { landscape: opts.landscape ?? true })
}

export async function printSheet(ed) {
    const { formDialog } = await import('../../core/dom.js')
    const r = await formDialog({
        title: '打印', fields: [
            { key: 'all', label: '范围', type: 'select', value: 'false', options: [['false', '当前工作表'], ['true', '整个工作簿']] },
            { key: 'landscape', label: '横向', type: 'check', value: true },
            { key: 'gridlines', label: '打印网格线', type: 'check', value: true },
        ],
    })
    if (!r) return
    await window.lite.printHtml(printHTML(ed, { all: r.all === 'true', landscape: r.landscape, gridlines: r.gridlines }))
}

export function exportsList(ed) {
    return [
        { ext: 'pdf', name: 'PDF 文档', write: () => writePDF(ed, { all: true }) },
        { ext: 'html', name: '网页（HTML 表格）', write: () => writeHTML(ed) },
        { ext: 'tsv', name: 'TSV（制表符分隔）', write: () => writeCSV(ed, '\t') },
        { ext: 'xls', name: 'Excel 97-2003', write: () => ed.writeSheetJS('biff8') },
    ]
}
