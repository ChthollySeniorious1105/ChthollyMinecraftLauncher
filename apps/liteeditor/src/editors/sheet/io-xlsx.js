// 写出 XLSX：直接生成 OOXML（值、公式及缓存结果、样式、合并、列宽行高、隐藏行列、冻结窗格、
// 网格线、标签颜色、自动筛选、条件格式、数据验证）
import JSZip from 'jszip'
import { colName, rangeName } from './addr.js'
import { StyleWriter, encode } from './io-style.js'
import { isErr } from './formula/values.js'

const x = s => encode(s)
const refOf = g => rangeName(g).replace(/^([A-Z]+):([A-Z]+)$/, '$1:$2')

export async function writeXLSX(ed) {
    const sw = new StyleWriter()
    const shared = [], sharedIdx = new Map()
    const ss = s => { let i = sharedIdx.get(s); if (i == null) { i = shared.length; shared.push(s); sharedIdx.set(s, i) } return i }
    const dxfs = []
    const dxf = st => { dxfs.push(st ?? {}); return dxfs.length - 1 }
    const zip = new JSZip()
    const sheets = ed.book.sheets

    sheets.forEach((sh, i) => zip.file(`xl/worksheets/sheet${i + 1}.xml`, sheetXML(ed, sh, sw, ss, dxf, i === ed.book.active)))

    zip.file('[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>`)
    zip.file('_rels/.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>`)
    const now = new Date().toISOString().replace(/\.\d+Z$/, 'Z')
    zip.file('docProps/core.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:creator>LiteEditor</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">${now}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}</dcterms:modified></cp:coreProperties>`)
    zip.file('docProps/app.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>LiteEditor</Application></Properties>`)
    zip.file('xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId${sheets.length + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>`)
    // 自动筛选需要定义名称 _xlnm._FilterDatabase
    const names = sheets.map((sh, i) => sh.meta.filter ? `<definedName name="_xlnm._FilterDatabase" localSheetId="${i}" hidden="1">${x(quote(sh.name))}!${absRef(sh.meta.filter.range)}</definedName>` : '').join('')
    zip.file('xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView activeTab="${ed.book.active}"/></bookViews><sheets>${sheets.map((sh, i) => `<sheet name="${x(sh.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets>${names ? `<definedNames>${names}</definedNames>` : ''}<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>`)
    zip.file('xl/sharedStrings.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${shared.length}" uniqueCount="${shared.length}">${shared.map(s => `<si><t xml:space="preserve">${x(s)}</t></si>`).join('')}</sst>`)
    // 样式表：插入条件格式用的 dxfs
    let styles = sw.xml()
    if (dxfs.length) styles = styles.replace('<dxfs count="0"/>', `<dxfs count="${dxfs.length}">${dxfs.map(dxfXML).join('')}</dxfs>`)
    zip.file('xl/styles.xml', styles)
    return zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' })
}

const quote = n => /^[A-Za-z_][\w.]*$/.test(n) ? n : `'${n.replace(/'/g, "''")}'`
const absRef = g => `$${colName(g.c1)}$${g.r1 + 1}:$${colName(g.c2)}$${g.r2 + 1}`

function dxfXML(s) {
    const rgb = c => 'FF' + c.replace('#', '').toUpperCase()
    let out = '<dxf>'
    if (s.b || s.i || s.color) out += `<font>${s.b ? '<b/>' : ''}${s.i ? '<i/>' : ''}${s.color ? `<color rgb="${rgb(s.color)}"/>` : ''}</font>`
    if (s.fill) out += `<fill><patternFill patternType="solid"><fgColor rgb="${rgb(s.fill)}"/><bgColor rgb="${rgb(s.fill)}"/></patternFill></fill>`
    return out + '</dxf>'
}

function sheetXML(ed, sh, sw, ss, dxf, active) {
    const m = sh.meta
    const b = sh.bounds()
    const lastR = Math.max(0, b.r2), lastC = Math.max(0, b.c2)
    const parts = []
    parts.push('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    parts.push(`<sheetPr${m.filter ? ' filterMode="1"' : ''}>${m.color ? `<tabColor rgb="FF${m.color.replace('#', '').toUpperCase()}"/>` : ''}</sheetPr>`)
    parts.push(`<dimension ref="A1:${colName(lastC)}${lastR + 1}"/>`)
    // 视图：冻结窗格、网格线、活动单元格
    const fz = m.freeze ?? { r: 0, c: 0 }
    let pane = ''
    if (fz.r || fz.c) {
        const tl = `${colName(fz.c)}${fz.r + 1}`
        const which = fz.r && fz.c ? 'bottomRight' : fz.r ? 'bottomLeft' : 'topRight'
        pane = `<pane${fz.c ? ` xSplit="${fz.c}"` : ''}${fz.r ? ` ySplit="${fz.r}"` : ''} topLeftCell="${tl}" activePane="${which}" state="frozen"/><selection pane="${which}"/>`
    }
    parts.push(`<sheetViews><sheetView workbookViewId="0"${m.showGrid === false ? ' showGridLines="0"' : ''}${active ? ' tabSelected="1"' : ''}${ed.zoom !== 1 ? ` zoomScale="${Math.round(ed.zoom * 100)}"` : ''}>${pane}</sheetView></sheetViews>`)
    parts.push(`<sheetFormatPr defaultRowHeight="${pt(m.defRowH ?? 24)}" customHeight="1" defaultColWidth="${chars(m.defColW ?? 88)}"/>`)
    // 列：宽度、隐藏、列样式（连续相同的列合并为一个区间）
    const colIdx = new Set([...m.colW.keys(), ...m.hiddenC, ...m.colStyle.keys()])
    if (colIdx.size) {
        const sorted = [...colIdx].sort((a, b) => a - b)
        const key = c => `${m.colW.get(c) ?? ''}|${m.hiddenC.has(c)}|${m.colStyle.get(c) ? sw.xf(m.colStyle.get(c)) : 0}`
        const cols = []
        for (let i = 0; i < sorted.length;) {
            let j = i
            while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1 && key(sorted[j + 1]) === key(sorted[i])) j++
            const c = sorted[i]
            const w = m.colW.get(c) ?? m.defColW ?? 88
            const st = m.colStyle.get(c)
            cols.push(`<col min="${c + 1}" max="${sorted[j] + 1}" width="${chars(w)}" customWidth="1"${m.hiddenC.has(c) ? ' hidden="1"' : ''}${st ? ` style="${sw.xf(st)}"` : ''}/>`)
            i = j + 1
        }
        parts.push(`<cols>${cols.join('')}</cols>`)
    }
    // 数据：按行输出
    const rows = new Map()
    for (const [r, c, cell] of sh.cells.sorted()) {
        if (!rows.has(r)) rows.set(r, [])
        rows.get(r).push([c, cell])
    }
    const hiddenRows = new Set([...m.hiddenR, ...(m.filter?.hidden ?? [])])
    for (const r of [...m.rowH.keys(), ...hiddenRows, ...m.rowStyle.keys()]) if (!rows.has(r) && r <= 1048575) rows.set(r, [])
    parts.push('<sheetData>')
    for (const r of [...rows.keys()].sort((a, b) => a - b)) {
        const h = m.rowH.get(r), rs = m.rowStyle.get(r)
        const attrs = `r="${r + 1}"${h != null ? ` ht="${pt(h)}" customHeight="1"` : ''}${hiddenRows.has(r) ? ' hidden="1"' : ''}${rs ? ` s="${sw.xf(rs)}" customFormat="1"` : ''}`
        const cells = rows.get(r).map(([c, cell]) => cellXML(ed, sh, r, c, cell, sw, ss)).join('')
        parts.push(cells ? `<row ${attrs}>${cells}</row>` : `<row ${attrs}/>`)
    }
    parts.push('</sheetData>')
    if (m.filter) parts.push(filterXML(m.filter))
    if (m.merges.length) parts.push(`<mergeCells count="${m.merges.length}">${m.merges.map(g => `<mergeCell ref="${refOf(g)}"/>`).join('')}</mergeCells>`)
    // 条件格式
    let prio = 1
    for (const rule of m.cf ?? []) {
        const xml = cfXML(rule, dxf, prio)
        if (xml) { parts.push(`<conditionalFormatting sqref="${refOf(rule.range)}">${xml}</conditionalFormatting>`); prio++ }
    }
    // 数据验证
    const dvs = (m.validations ?? []).map(dvXML).filter(Boolean)
    if (dvs.length) parts.push(`<dataValidations count="${dvs.length}">${dvs.join('')}</dataValidations>`)
    parts.push('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>')
    parts.push('</worksheet>')
    return parts.join('')
}

function cellXML(ed, sh, r, c, cell, sw, ss) {
    const ref = `${colName(c)}${r + 1}`
    const s = cell.s ? sw.xf(cell.s) : 0
    const sa = s ? ` s="${s}"` : ''
    if (cell.f) {
        const v = ed.valueOf(sh, r, c, cell)
        const f = `<f>${x(cell.f)}</f>`
        if (v == null || v === '') return `<c r="${ref}"${sa}>${f}</c>`
        if (typeof v === 'number') return `<c r="${ref}"${sa}>${f}<v>${num(v)}</v></c>`
        if (typeof v === 'boolean') return `<c r="${ref}"${sa} t="b">${f}<v>${v ? 1 : 0}</v></c>`
        if (isErr(v)) return `<c r="${ref}"${sa} t="e">${f}<v>${x(v.code)}</v></c>`
        return `<c r="${ref}"${sa} t="str">${f}<v>${x(String(v))}</v></c>`
    }
    const v = cell.v
    if (v == null || v === '') return s ? `<c r="${ref}"${sa}/>` : ''
    if (typeof v === 'number') return `<c r="${ref}"${sa}><v>${num(v)}</v></c>`
    if (typeof v === 'boolean') return `<c r="${ref}"${sa} t="b"><v>${v ? 1 : 0}</v></c>`
    if (isErr(v)) return `<c r="${ref}"${sa} t="e"><v>${x(v.code)}</v></c>`
    return `<c r="${ref}"${sa} t="s"><v>${ss(String(v))}</v></c>`
}

function filterXML(f) {
    const cols = Object.entries(f.cols ?? {}).map(([c, spec]) => {
        const id = +c - f.range.c1
        if (spec.type === 'values') {
            const blank = spec.values.includes('')
            return `<filterColumn colId="${id}"><filters${blank ? ' blank="1"' : ''}>${spec.values.filter(v => v !== '').map(v => `<filter val="${x(String(v))}"/>`).join('')}</filters></filterColumn>`
        }
        if (spec.type === 'cond') {
            const op = { gt: 'greaterThan', lt: 'lessThan', ge: 'greaterThanOrEqual', le: 'lessThanOrEqual', eq: 'equal', ne: 'notEqual' }[spec.op]
            if (spec.op === 'between') return `<filterColumn colId="${id}"><customFilters and="1"><customFilter operator="greaterThanOrEqual" val="${x(String(spec.a))}"/><customFilter operator="lessThanOrEqual" val="${x(String(spec.b))}"/></customFilters></filterColumn>`
            if (spec.op === 'contains') return `<filterColumn colId="${id}"><customFilters><customFilter val="*${x(String(spec.a))}*"/></customFilters></filterColumn>`
            if (spec.op === 'begins') return `<filterColumn colId="${id}"><customFilters><customFilter val="${x(String(spec.a))}*"/></customFilters></filterColumn>`
            if (op) return `<filterColumn colId="${id}"><customFilters><customFilter operator="${op}" val="${x(String(spec.a))}"/></customFilters></filterColumn>`
        }
        return ''
    }).join('')
    return `<autoFilter ref="${refOf(f.range)}">${cols}</autoFilter>`
}

function cfXML(rule, dxf, priority) {
    const st = rule.style ?? { fill: '#fde2e4', color: '#9c0006' }
    const fv = v => typeof v === 'number' ? String(v) : `"${String(v ?? '').replace(/"/g, '""')}"`
    const ops = { gt: 'greaterThan', lt: 'lessThan', ge: 'greaterThanOrEqual', le: 'lessThanOrEqual', eq: 'equal', ne: 'notEqual', between: 'between' }
    const first = `${colName(rule.range.c1)}${rule.range.r1 + 1}`
    switch (rule.type) {
        case 'gt': case 'lt': case 'ge': case 'le': case 'eq': case 'ne': case 'between':
            return `<cfRule type="cellIs" dxfId="${dxf(st)}" priority="${priority}" operator="${ops[rule.type]}"><formula>${x(fv(rule.a))}</formula>${rule.type === 'between' ? `<formula>${x(fv(rule.b))}</formula>` : ''}</cfRule>`
        case 'text': return `<cfRule type="containsText" dxfId="${dxf(st)}" priority="${priority}" operator="containsText" text="${x(rule.a)}"><formula>NOT(ISERROR(SEARCH("${x(rule.a)}",${first})))</formula></cfRule>`
        case 'notext': return `<cfRule type="notContainsText" dxfId="${dxf(st)}" priority="${priority}" operator="notContains" text="${x(rule.a)}"><formula>ISERROR(SEARCH("${x(rule.a)}",${first}))</formula></cfRule>`
        case 'begins': return `<cfRule type="beginsWith" dxfId="${dxf(st)}" priority="${priority}" operator="beginsWith" text="${x(rule.a)}"><formula>LEFT(${first},${String(rule.a).length})="${x(rule.a)}"</formula></cfRule>`
        case 'dup': return `<cfRule type="duplicateValues" dxfId="${dxf(st)}" priority="${priority}"/>`
        case 'unique': return `<cfRule type="uniqueValues" dxfId="${dxf(st)}" priority="${priority}"/>`
        case 'top': case 'bottom': return `<cfRule type="top10" dxfId="${dxf(st)}" priority="${priority}" rank="${rule.a ?? 10}"${rule.type === 'bottom' ? ' bottom="1"' : ''}/>`
        case 'above': case 'below': return `<cfRule type="aboveAverage" dxfId="${dxf(st)}" priority="${priority}"${rule.type === 'below' ? ' aboveAverage="0"' : ''}/>`
        case 'blank': return `<cfRule type="containsBlanks" dxfId="${dxf(st)}" priority="${priority}"><formula>LEN(TRIM(${first}))=0</formula></cfRule>`
        case 'formula': return `<cfRule type="expression" dxfId="${dxf(st)}" priority="${priority}"><formula>${x(rule.a)}</formula></cfRule>`
        case 'bar': return `<cfRule type="dataBar" priority="${priority}"><dataBar><cfvo type="min"/><cfvo type="max"/><color rgb="FF${(rule.color ?? '#638ec6').replace('#', '').toUpperCase()}"/></dataBar></cfRule>`
        case 'scale': {
            const cs = rule.colors ?? ['#f8696b', '#ffeb84', '#63be7b']
            const vos = cs.length === 3 ? '<cfvo type="min"/><cfvo type="percentile" val="50"/><cfvo type="max"/>' : '<cfvo type="min"/><cfvo type="max"/>'
            return `<cfRule type="colorScale" priority="${priority}"><colorScale>${vos}${cs.map(c => `<color rgb="FF${c.replace('#', '').toUpperCase()}"/>`).join('')}</colorScale></cfRule>`
        }
    }
    return ''
}

function dvXML(dv) {
    const ref = refOf(dv.range)
    const err = dv.message ? ` showErrorMessage="1" error="${x(dv.message)}"` : ' showErrorMessage="1"'
    if (dv.type === 'list') {
        const src = String(dv.source ?? '')
        const f = src.startsWith('=') ? src.slice(1) : `"${src.replace(/"/g, '""')}"`
        return `<dataValidation type="list" allowBlank="1" showInputMessage="1"${err} sqref="${ref}"><formula1>${x(f)}</formula1></dataValidation>`
    }
    const t = { integer: 'whole', number: 'decimal', length: 'textLength' }[dv.type]
    if (!t) return ''
    const hasMin = dv.min !== '' && dv.min != null, hasMax = dv.max !== '' && dv.max != null
    const op = hasMin && hasMax ? 'between' : hasMin ? 'greaterThanOrEqual' : 'lessThanOrEqual'
    return `<dataValidation type="${t}" operator="${op}" allowBlank="1"${err} sqref="${ref}">${hasMin ? `<formula1>${x(String(dv.min))}</formula1>` : `<formula1>${x(String(dv.max))}</formula1>`}${hasMin && hasMax ? `<formula2>${x(String(dv.max))}</formula2>` : ''}</dataValidation>`
}

const num = v => Number.isFinite(v) ? String(+v.toPrecision(17)) : '0'
const pt = px => +(px * 0.75).toFixed(2)
const chars = px => +((px - 5) / 7).toFixed(2)
