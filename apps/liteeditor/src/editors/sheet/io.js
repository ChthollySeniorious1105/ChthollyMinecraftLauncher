// 文件读取：XLSX / XLSM / XLS / ODS（SheetJS + 自行解析样式等）、CSV / TSV、原生 .lsheet
import * as XLSX from 'xlsx'
import JSZip from 'jszip'
import { Sheet, makeCell, internStyle } from './model.js'
import { parseCell, parseRange, MAX_ROWS, MAX_COLS } from './addr.js'
import { parseStyles, parseTheme, attr, decode } from './io-style.js'
import { parseInput } from './editing.js'
import { toast } from '../../core/dom.js'
import { writeXLSX } from './io-xlsx.js'
import { exportsList, writeCSV, writeHTML, writePDF, printSheet } from './io-export.js'
import { KINDS } from '../../core/files.js'

const stripXlfn = f => f.replace(/_xlfn\.|_xlws\.|_xludf\./gi, '')

export const IO = {
    async readFile(bytes, ext) {
        ext = (ext || '').toLowerCase()
        if (ext === 'lsheet') return this.readLSheet(bytes)
        if (ext === 'csv' || ext === 'tsv' || ext === 'txt') return this.readCSV(bytes, ext)
        return this.readWorkbook(bytes, ext)
    },

    // ---------- CSV / TSV ----------
    readCSV(bytes, ext) {
        let text
        if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) text = new TextDecoder('utf-8').decode(bytes.subarray(3))
        else if (bytes[0] === 0xff && bytes[1] === 0xfe) text = new TextDecoder('utf-16le').decode(bytes.subarray(2))
        else {
            try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes) } catch { text = new TextDecoder('gbk').decode(bytes) }
        }
        const first = text.slice(0, 2000)
        const delim = ext === 'tsv' ? '\t' : [',', ';', '\t'].map(d => [d, first.split(d).length]).sort((a, b) => b[1] - a[1])[0][0]
        const rows = parseDelimited(text, delim)
        const sh = new Sheet(stemName(this.name) || 'Sheet1')
        rows.forEach((row, r) => row.forEach((t, c) => {
            if (t === '' || r >= MAX_ROWS || c >= MAX_COLS) return
            const p = parseInput(t)
            // CSV 中以 = 开头的内容按文本处理，避免意外执行公式
            const cell = p.f ? makeCell(t) : makeCell(p.v, null, p.fmt ? internStyle({ fmt: p.fmt }) : null)
            if (cell) sh.cells.set(r, c, cell)
        }))
        this.book.sheets = [sh]
        this.book.active = 0
        this.autoWidths(sh)
    },

    // 按内容估算列宽（CSV 没有列宽信息）
    autoWidths(sh) {
        const w = new Map()
        sh.cells.each((r, c, cell) => {
            if (r > 500) return
            const t = String(cell.v ?? '')
            let n = 0
            for (const ch of t) n += ch.charCodeAt(0) > 255 ? 2 : 1
            w.set(c, Math.max(w.get(c) ?? 0, n))
        }, 0, 0, 500, MAX_COLS - 1)
        sh.update('colW', m => { for (const [c, n] of w) { const px = Math.min(360, Math.max(64, n * 7.5 + 16)); if (px > sh.meta.defColW) m.set(c, Math.round(px)) } })
    },

    // ---------- 原生格式 ----------
    readLSheet(bytes) {
        const data = JSON.parse(new TextDecoder().decode(bytes))
        if (data.format !== 'lsheet') throw new Error('不是有效的 LiteEditor 表格文件')
        const styles = (data.styles ?? []).map(s => internStyle(s))
        this.book.sheets = data.sheets.map(s => {
            const sh = new Sheet(s.name)
            for (const [r, c, x] of s.cells ?? []) {
                const cell = makeCell(x.v, x.f, x.s != null ? styles[x.s] : null)
                if (cell) sh.cells.set(r, c, cell)
            }
            const m = s.meta ?? {}
            const map = (a, fn = v => v) => new Map((a ?? []).map(([k, v]) => [k, fn(v)]))
            sh.setMeta({
                rowH: map(m.rowH), colW: map(m.colW), hiddenR: new Set(m.hiddenR ?? []), hiddenC: new Set(m.hiddenC ?? []),
                rowStyle: map(m.rowStyle, i => styles[i]), colStyle: map(m.colStyle, i => styles[i]),
                merges: m.merges ?? [], freeze: m.freeze ?? { r: 0, c: 0 }, cf: m.cf ?? [], charts: m.charts ?? [],
                filter: m.filter ? { ...m.filter, hidden: new Set(m.filter.hidden ?? []) } : null,
                validations: m.validations ?? [], showGrid: m.showGrid ?? true, color: m.color ?? null,
                defRowH: m.defRowH ?? 24, defColW: m.defColW ?? 88, rowAuto: new Set(m.rowAuto ?? []),
            })
            return sh
        })
        if (!this.book.sheets.length) this.book.sheets = [new Sheet('Sheet1')]
        this.book.active = Math.min(data.active ?? 0, this.book.sheets.length - 1)
    },

    writeLSheet() {
        const styles = [], sIdx = new Map()
        const si = s => { if (!s) return undefined; let i = sIdx.get(s); if (i == null) { i = styles.length; styles.push(s); sIdx.set(s, i) } return i }
        const sheets = this.book.sheets.map(sh => {
            const cells = []
            for (const [r, c, cell] of sh.cells.sorted()) {
                const x = {}
                if (cell.f) x.f = cell.f
                else if (cell.v != null) x.v = cell.v
                if (cell.s) x.s = si(cell.s)
                cells.push([r, c, x])
            }
            const m = sh.meta
            return {
                name: sh.name, cells,
                meta: {
                    rowH: [...m.rowH], colW: [...m.colW], hiddenR: [...m.hiddenR], hiddenC: [...m.hiddenC],
                    rowStyle: [...m.rowStyle].map(([k, v]) => [k, si(v)]), colStyle: [...m.colStyle].map(([k, v]) => [k, si(v)]),
                    merges: m.merges, freeze: m.freeze, cf: m.cf, charts: m.charts,
                    filter: m.filter ? { ...m.filter, hidden: [...(m.filter.hidden ?? [])] } : null,
                    validations: m.validations, showGrid: m.showGrid, color: m.color, defRowH: m.defRowH, defColW: m.defColW,
                    rowAuto: [...(m.rowAuto ?? [])],
                },
            }
        })
        return JSON.stringify({ format: 'lsheet', version: 1, app: 'LiteEditor', active: this.book.active, styles, sheets })
    },

    // ---------- XLSX / XLS / ODS ----------
    async readWorkbook(bytes, ext) {
        const wb = XLSX.read(bytes, { type: 'array', cellFormula: true, cellNF: true, cellStyles: false, cellDates: false, sheetStubs: false, dense: true, cellHTML: false, cellText: false })
        // XLSX / XLSM：用 JSZip 读取样式、冻结窗格、条件格式等 SheetJS 社区版不处理的部分
        let extra = null
        if (ext === 'xlsx' || ext === 'xlsm') {
            try { extra = await readXlsxExtras(bytes) } catch (e) { console.warn('读取样式失败', e) }
        }
        const sheets = []
        wb.SheetNames.forEach((name, si) => {
            const ws = wb.Sheets[name]
            const sh = new Sheet(name)
            const ex = extra?.sheets.get(name)
            const styleOf = ex ? (r, c) => extra.styles[ex.cellStyle.get(r * MAX_COLS + c) ?? -1] ?? null : () => null
            const data = ws['!data'] ?? []
            for (let r = 0; r < data.length; r++) {
                const row = data[r]
                if (!row) continue
                for (let c = 0; c < row.length; c++) {
                    const x = row[c]
                    if (!x) continue
                    let s = styleOf(r, c)
                    if (!ex && x.z && x.z !== 'General') s = internStyle({ fmt: normFmt(x.z) })
                    let v = x.v
                    if (x.t === 'e') v = x.w ?? XLSX.utils.format_cell?.(x) ?? '#N/A'
                    if (x.t === 'd') v = toSerial(x.v)
                    if (x.t === 'z') v = null
                    const f = x.f ? stripXlfn(x.f) : null
                    const cell = makeCell(v, f, s)
                    if (cell) sh.cells.set(r, c, cell)
                }
            }
            // 只有样式的单元格
            if (ex) for (const [k, xf] of ex.cellStyle) {
                const r = Math.floor(k / MAX_COLS), c = k % MAX_COLS
                if (!sh.cells.has(r, c) && extra.styles[xf]) sh.cells.set(r, c, { s: extra.styles[xf] })
            }
            const meta = {}
            meta.merges = (ws['!merges'] ?? []).map(m => ({ r1: m.s.r, c1: m.s.c, r2: m.e.r, c2: m.e.c })).filter(m => m.r1 !== m.r2 || m.c1 !== m.c2)
            const colW = new Map(), hiddenC = new Set(), rowH = new Map(), hiddenR = new Set()
            ;(ws['!cols'] ?? []).forEach((col, c) => {
                if (!col) return
                if (col.hidden) hiddenC.add(c)
                const px = col.wpx ?? (col.wch != null ? col.wch * 7 + 5 : col.width != null ? col.width * 7 + 5 : null)
                if (px != null) colW.set(c, Math.round(px))
            })
            ;(ws['!rows'] ?? []).forEach((row, r) => {
                if (!row) return
                if (row.hidden) hiddenR.add(r)
                const px = row.hpx ?? (row.hpt != null ? row.hpt * 4 / 3 : null)
                if (px != null) rowH.set(r, Math.round(px))
            })
            Object.assign(meta, { colW, hiddenC, rowH, hiddenR })
            if (ex) {
                if (ex.defColW) meta.defColW = ex.defColW
                if (ex.defRowH) meta.defRowH = Math.max(18, ex.defRowH)
                meta.freeze = ex.freeze
                meta.showGrid = ex.showGrid
                meta.color = ex.tabColor
                meta.cf = ex.cf
                meta.validations = ex.validations
                meta.colStyle = new Map([...ex.colStyle].map(([c, xf]) => [c, extra.styles[xf]]).filter(x => x[1]))
                meta.rowStyle = new Map([...ex.rowStyle].map(([r, xf]) => [r, extra.styles[xf]]).filter(x => x[1]))
                if (ex.autoFilter) {
                    const hidden = new Set(), cols = ex.filterCols ?? {}
                    if (Object.keys(cols).length) for (const r of hiddenR) if (r > ex.autoFilter.r1 && r <= ex.autoFilter.r2) { hidden.add(r); hiddenR.delete(r) }
                    meta.filter = { range: ex.autoFilter, cols, hidden }
                }
            }
            sh.setMeta(meta)
            // 行高过小（Excel 默认 13.5pt = 18px）时统一到本编辑器默认行高，保持观感一致
            sheets.push(sh)
            void si
        })
        if (!sheets.length) sheets.push(new Sheet('Sheet1'))
        this.book.sheets = sheets
        this.book.active = Math.min(extra?.activeTab ?? 0, sheets.length - 1)
    },

    // ---------- 保存格式 ----------
    formats() {
        return [
            { ext: 'lsheet', name: 'LiteEditor 表格', write: async () => this.writeLSheet() },
            { ext: 'xlsx', name: 'Excel 工作簿', write: async () => writeXLSX(this), lossy: '图表与部分条件格式仅保存在 .lsheet 中' },
            { ext: 'ods', name: 'OpenDocument 表格', write: async () => this.writeSheetJS('ods'), lossy: 'ODS 仅保存数据、公式与合并单元格，不保存样式与图表' },
            { ext: 'csv', name: 'CSV（逗号分隔）', write: async () => writeCSV(this, ','), lossy: 'CSV 仅保存当前工作表的值' },
        ].filter(f => f.ext !== 'ods' || KINDS.sheet.native.includes('ods') || true)
    },
    exports() { return exportsList(this) },
    fileItems() {
        return [
            { label: '打印…', icon: 'printer', key: 'Ctrl+P', run: () => printSheet(this) },
        ]
    },

    // 通过 SheetJS 写 ODS / XLS / TSV
    writeSheetJS(bookType) {
        const wb = XLSX.utils.book_new()
        for (const sh of this.book.sheets) {
            const ws = { '!data': [] }
            const b = sh.bounds()
            for (const [r, c, cell] of sh.cells.sorted()) {
                if (cell.v == null && !cell.f) continue
                const v = this.valueOf(sh, r, c, cell)
                const x = {}
                if (v == null) { x.t = 's'; x.v = '' }
                else if (typeof v === 'number') { x.t = 'n'; x.v = v }
                else if (typeof v === 'boolean') { x.t = 'b'; x.v = v }
                else if (typeof v === 'object') { x.t = 'e'; x.v = errCode(v.code); x.w = v.code }
                else { x.t = 's'; x.v = v }
                if (cell.f) x.f = cell.f
                if (cell.s?.fmt) x.z = cell.s.fmt
                ;(ws['!data'][r] ??= [])[c] = x
            }
            ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: Math.max(0, b.r2), c: Math.max(0, b.c2) } })
            ws['!merges'] = sh.meta.merges.map(m => ({ s: { r: m.r1, c: m.c1 }, e: { r: m.r2, c: m.c2 } }))
            ws['!cols'] = []
            for (const [c, w] of sh.meta.colW) ws['!cols'][c] = { wpx: w }
            XLSX.utils.book_append_sheet(wb, ws, sh.name.slice(0, 31))
        }
        return new Uint8Array(XLSX.write(wb, { type: 'array', bookType, dense: true }))
    },
}

const ERR_CODES = { '#NULL!': 0, '#DIV/0!': 7, '#VALUE!': 15, '#REF!': 23, '#NAME?': 29, '#NUM!': 36, '#N/A': 42 }
const errCode = s => ERR_CODES[s] ?? 42
const stemName = n => (n ?? '').replace(/\.[^.]+$/, '').slice(0, 31).replace(/[\\/?*[\]:]/g, '')
const toSerial = d => (d.getTime() - Date.UTC(1899, 11, 30)) / 86400000 - d.getTimezoneOffset() / 1440
// SheetJS 的内置格式名规范化
const normFmt = z => z === 'm/d/yy' || z === 'yyyy\\-mm\\-dd' ? 'yyyy-mm-dd' : z.replace(/\\-/g, '-')

// 通用分隔文本解析（支持引号）
export function parseDelimited(text, d) {
    const rows = []
    let row = [], cur = '', q = false
    for (let i = 0; i < text.length; i++) {
        const ch = text[i]
        if (q) {
            if (ch === '"') { if (text[i + 1] === '"') { cur += '"'; i++ } else q = false }
            else cur += ch
            continue
        }
        if (ch === '"' && cur === '') q = true
        else if (ch === d) { row.push(cur); cur = '' }
        else if (ch === '\n' || ch === '\r') {
            if (ch === '\r' && text[i + 1] === '\n') i++
            row.push(cur); rows.push(row); row = []; cur = ''
        } else cur += ch
    }
    if (cur !== '' || row.length) { row.push(cur); rows.push(row) }
    return rows
}

// ---------- XLSX 附加信息 ----------
async function readXlsxExtras(bytes) {
    const zip = await JSZip.loadAsync(bytes)
    const read = p => zip.file(p)?.async('string')
    const wbXml = await read('xl/workbook.xml') ?? ''
    const rels = await read('xl/_rels/workbook.xml.rels') ?? ''
    const relMap = new Map()
    for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) relMap.set(attr(m[0], 'Id'), attr(m[0], 'Target'))
    const theme = parseTheme(await read('xl/theme/theme1.xml'))
    const stylesXml = await read('xl/styles.xml')
    const styles = parseStyles(stylesXml, theme)
    const dxfs = parseDxfs(stylesXml, theme)
    const activeTab = +(attr(/<workbookView\b[^>]*>/.exec(wbXml)?.[0] ?? '', 'activeTab') ?? 0)
    const sheets = new Map()
    for (const m of wbXml.matchAll(/<sheet\b[^>]*>/g)) {
        const name = decode(attr(m[0], 'name') ?? '')
        const rid = attr(m[0], 'r:id') ?? /\br:id="([^"]*)"/.exec(m[0])?.[1]
        let target = relMap.get(rid)
        if (!target) continue
        target = target.replace(/^\/?xl\//, '').replace(/^\//, '')
        const xml = await read('xl/' + target)
        if (xml) sheets.set(name, parseSheetExtras(xml, dxfs))
    }
    return { styles, sheets, activeTab }
}

function parseDxfs(xml, theme) {
    const body = /<dxfs\b[^>]*>([\s\S]*?)<\/dxfs>/.exec(xml ?? '')?.[1] ?? ''
    return (body.match(/<dxf>[\s\S]*?<\/dxf>/g) ?? []).map(d => {
        const s = {}
        const font = /<font>([\s\S]*?)<\/font>/.exec(d)?.[1] ?? ''
        if (/<b\/>|<b val="1"/.test(font)) s.b = true
        if (/<i\/>|<i val="1"/.test(font)) s.i = true
        const fc = /<color [^>]*\/>/.exec(font)?.[0]
        if (fc) s.color = colorFrom(fc, theme)
        const fill = /<fill>([\s\S]*?)<\/fill>/.exec(d)?.[1] ?? ''
        const bg = /<bgColor [^>]*\/>/.exec(fill)?.[0] ?? /<fgColor [^>]*\/>/.exec(fill)?.[0]
        if (bg) s.fill = colorFrom(bg, theme)
        return s
    })
}
function colorFrom(tag, theme) {
    const rgb = attr(tag, 'rgb')
    if (rgb) return '#' + rgb.slice(-6).toLowerCase()
    const th = attr(tag, 'theme')
    if (th != null) return theme[+th] ?? '#000000'
    return '#000000'
}

function parseSheetExtras(xml, dxfs) {
    const out = { cellStyle: new Map(), colStyle: new Map(), rowStyle: new Map(), freeze: { r: 0, c: 0 }, showGrid: true, cf: [], validations: [] }
    // 单元格样式索引
    const sd = xml.indexOf('<sheetData')
    const sdEnd = xml.indexOf('</sheetData>')
    const data = sd >= 0 ? xml.slice(sd, sdEnd < 0 ? xml.length : sdEnd) : ''
    for (const m of data.matchAll(/<c r="([A-Z]+)(\d+)"([^>]*?)\/?>/g)) {
        const s = /\bs="(\d+)"/.exec(m[3])
        if (!s || s[1] === '0') continue
        const p = parseCell(m[1] + m[2])
        if (p) out.cellStyle.set(p.r * MAX_COLS + p.c, +s[1])
    }
    for (const m of data.matchAll(/<row\b([^>]*)>/g)) {
        if (!/customFormat="(1|true)"/.test(m[1])) continue
        const r = +attr(m[1], 'r') - 1, s = attr(m[1], 's')
        if (s && s !== '0') out.rowStyle.set(r, +s)
    }
    const head = sd >= 0 ? xml.slice(0, sd) : xml
    for (const m of head.matchAll(/<col\b[^>]*\/?>/g)) {
        const s = attr(m[0], 'style')
        if (!s || s === '0') continue
        const a = +attr(m[0], 'min') - 1, b = Math.min(+attr(m[0], 'max') - 1, a + 300)
        for (let c = a; c <= b; c++) out.colStyle.set(c, +s)
    }
    const fmt = /<sheetFormatPr\b[^>]*>/.exec(head)?.[0]
    if (fmt) {
        const w = attr(fmt, 'defaultColWidth'), h = attr(fmt, 'defaultRowHeight')
        if (w) out.defColW = Math.round(+w * 7 + 5)
        if (h && /customHeight="1"/.test(fmt)) out.defRowH = Math.round(+h * 4 / 3)
    }
    const view = /<sheetView\b[^>]*>/.exec(head)?.[0] ?? ''
    if (/showGridLines="(0|false)"/.test(view)) out.showGrid = false
    const pane = /<pane\b[^>]*>/.exec(head)?.[0]
    if (pane && /state="frozen(Split)?"/.test(pane)) out.freeze = { r: Math.round(+(attr(pane, 'ySplit') ?? 0)), c: Math.round(+(attr(pane, 'xSplit') ?? 0)) }
    const tab = /<tabColor\b[^>]*>/.exec(head)?.[0]
    if (tab && attr(tab, 'rgb')) out.tabColor = '#' + attr(tab, 'rgb').slice(-6).toLowerCase()
    const tail = sdEnd >= 0 ? xml.slice(sdEnd) : ''
    // 自动筛选
    const af = /<autoFilter\b[^>]*?(?:\/>|>([\s\S]*?)<\/autoFilter>)/.exec(tail)
    if (af) {
        const g = parseRange(attr(af[0], 'ref') ?? '')
        if (g) {
            out.autoFilter = g
            out.filterCols = {}
            for (const fc of (af[1] ?? '').matchAll(/<filterColumn colId="(\d+)"[^>]*>([\s\S]*?)<\/filterColumn>/g)) {
                const c = g.c1 + +fc[1]
                const vals = [...fc[2].matchAll(/<filter val="([^"]*)"/g)].map(x => decode(x[1]))
                if (vals.length || /<filters\b/.test(fc[2])) { out.filterCols[c] = { type: 'values', values: [...vals, ...(/blank="1"/.test(fc[2]) ? [''] : [])] }; continue }
                const cfs = [...fc[2].matchAll(/<customFilter\b[^>]*>/g)].map(x => ({ op: attr(x[0], 'operator') ?? 'equal', val: decode(attr(x[0], 'val') ?? '') }))
                if (cfs.length === 2 && cfs[0].op === 'greaterThanOrEqual' && cfs[1].op === 'lessThanOrEqual') out.filterCols[c] = { type: 'cond', op: 'between', a: cfs[0].val, b: cfs[1].val }
                else if (cfs.length) {
                    const x = cfs[0]
                    const op = { greaterThan: 'gt', lessThan: 'lt', greaterThanOrEqual: 'ge', equal: 'eq', notEqual: 'ne' }[x.op] ?? 'eq'
                    if (op === 'eq' && /^\*.*\*$/.test(x.val)) out.filterCols[c] = { type: 'cond', op: 'contains', a: x.val.slice(1, -1) }
                    else if (op === 'eq' && /\*$/.test(x.val)) out.filterCols[c] = { type: 'cond', op: 'begins', a: x.val.slice(0, -1) }
                    else out.filterCols[c] = { type: 'cond', op, a: x.val }
                }
            }
        }
    }
    // 条件格式
    for (const m of tail.matchAll(/<conditionalFormatting\b([^>]*)>([\s\S]*?)<\/conditionalFormatting>/g)) {
        const refs = (attr(m[1], 'sqref') ?? '').split(/\s+/).map(parseRange).filter(Boolean)
        for (const rm of m[2].matchAll(/<cfRule\b([^>]*)>([\s\S]*?)<\/cfRule>|<cfRule\b([^>]*)\/>/g)) {
            const a = rm[1] ?? rm[3], body = rm[2] ?? ''
            const type = attr(a, 'type'), op = attr(a, 'operator')
            const fs = [...body.matchAll(/<formula>([\s\S]*?)<\/formula>/g)].map(x => decode(x[1]))
            const style = dxfs[+(attr(a, 'dxfId') ?? -1)] ?? { fill: '#fde2e4', color: '#9c0006' }
            const num = s => { const n = +String(s ?? '').replace(/^"|"$/g, ''); return Number.isFinite(n) ? n : String(s ?? '').replace(/^"|"$/g, '') }
            let rule = null
            if (type === 'cellIs') {
                const t = { greaterThan: 'gt', lessThan: 'lt', between: 'between', equal: 'eq', notEqual: 'ne', greaterThanOrEqual: 'ge', lessThanOrEqual: 'le' }[op]
                if (t) rule = { type: t, a: num(fs[0]), b: fs[1] != null ? num(fs[1]) : undefined, style }
            } else if (type === 'containsText') rule = { type: 'text', a: decode(attr(a, 'text') ?? ''), style }
            else if (type === 'notContainsText') rule = { type: 'notext', a: decode(attr(a, 'text') ?? ''), style }
            else if (type === 'beginsWith') rule = { type: 'begins', a: decode(attr(a, 'text') ?? ''), style }
            else if (type === 'duplicateValues') rule = { type: 'dup', style }
            else if (type === 'uniqueValues') rule = { type: 'unique', style }
            else if (type === 'top10') rule = { type: attr(a, 'bottom') === '1' ? 'bottom' : 'top', a: +(attr(a, 'rank') ?? 10), style }
            else if (type === 'aboveAverage') rule = { type: attr(a, 'aboveAverage') === '0' ? 'below' : 'above', style }
            else if (type === 'containsBlanks') rule = { type: 'blank', style }
            else if (type === 'expression') rule = { type: 'formula', a: stripXlfn(fs[0] ?? 'FALSE'), style }
            else if (type === 'dataBar') { const c = /<color [^>]*\/>/.exec(body)?.[0]; rule = { type: 'bar', color: c ? colorFrom(c, []) : '#638ec6' } }
            else if (type === 'colorScale') { const cs = [...body.matchAll(/<color [^>]*\/>/g)].map(x => colorFrom(x[0], [])); rule = { type: 'scale', colors: cs.length >= 2 ? cs : undefined } }
            if (!rule) continue
            for (const range of refs) out.cf.push({ id: Math.random().toString(36).slice(2, 9), range, ...rule })
        }
    }
    // 数据验证
    for (const m of tail.matchAll(/<dataValidation\b([^>]*)>([\s\S]*?)<\/dataValidation>/g)) {
        const type = attr(m[1], 'type')
        const refs = (attr(m[1], 'sqref') ?? '').split(/\s+/).map(parseRange).filter(Boolean)
        const f1 = decode(/<formula1>([\s\S]*?)<\/formula1>/.exec(m[2])?.[1] ?? ''), f2 = decode(/<formula2>([\s\S]*?)<\/formula2>/.exec(m[2])?.[1] ?? '')
        const message = decode(attr(m[1], 'error') ?? '')
        let v = null
        if (type === 'list') v = { type: 'list', source: /^".*"$/.test(f1) ? f1.slice(1, -1) : '=' + f1 }
        else if (type === 'decimal' || type === 'whole') v = { type: type === 'whole' ? 'integer' : 'number', min: f1, max: f2 }
        else if (type === 'textLength') v = { type: 'length', min: f1, max: f2 }
        if (v) for (const range of refs) out.validations.push({ range, ...v, message })
    }
    return out
}

export { toast }
