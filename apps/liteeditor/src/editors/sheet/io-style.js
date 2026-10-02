// XLSX 样式读写（社区版 SheetJS 不处理样式，这里直接解析 / 生成 styles.xml）
import { internStyle } from './model.js'

export function cssColor(c) {
    if (!c) return null
    c = c.trim()
    if (/^#[0-9a-f]{6}$/i.test(c)) return c.toLowerCase()
    if (/^#[0-9a-f]{3}$/i.test(c)) return '#' + [...c.slice(1)].map(x => x + x).join('').toLowerCase()
    const m = /rgba?\((\d+)\D+(\d+)\D+(\d+)(?:\D+([\d.]+))?/.exec(c)
    if (m) {
        if (m[4] != null && +m[4] === 0) return null
        return '#' + [m[1], m[2], m[3]].map(x => (+x).toString(16).padStart(2, '0')).join('')
    }
    const named = { black: '#000000', white: '#ffffff', red: '#ff0000', blue: '#0000ff', green: '#008000', yellow: '#ffff00', gray: '#808080', grey: '#808080' }
    return named[c.toLowerCase()] ?? null
}

// Office 默认主题色（theme1.xml 的 clrScheme，顺序：lt1 dk1 lt2 dk2 accent1-6 hlink folHlink）
const THEME = ['#ffffff', '#000000', '#e7e6e6', '#44546a', '#4472c4', '#ed7d31', '#a5a5a5', '#ffc000', '#5b9bd5', '#70ad47', '#0563c1', '#954f72']
const INDEXED = ['#000000', '#ffffff', '#ff0000', '#00ff00', '#0000ff', '#ffff00', '#ff00ff', '#00ffff', '#000000', '#ffffff', '#ff0000', '#00ff00', '#0000ff', '#ffff00', '#ff00ff', '#00ffff',
    '#800000', '#008000', '#000080', '#808000', '#800080', '#008080', '#c0c0c0', '#808080', '#9999ff', '#993366', '#ffffcc', '#ccffff', '#660066', '#ff8080', '#0066cc', '#ccccff',
    '#000080', '#ff00ff', '#ffff00', '#00ffff', '#800080', '#800000', '#008080', '#0000ff', '#00ccff', '#ccffff', '#ccffcc', '#ffff99', '#99ccff', '#ff99cc', '#cc99ff', '#ffcc99',
    '#3366ff', '#33cccc', '#99cc00', '#ffcc00', '#ff9900', '#ff6600', '#666699', '#969696', '#003366', '#339966', '#003300', '#333300', '#993300', '#993366', '#333399', '#333333']

function applyTint(hex, tint) {
    if (!tint) return hex
    const rgb = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16))
    const out = rgb.map(v => tint < 0 ? v * (1 + tint) : v + (255 - v) * tint)
    return '#' + out.map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('')
}

const attr = (xml, name) => { const m = new RegExp('\\b' + name + '="([^"]*)"').exec(xml); return m ? m[1] : null }
function colorOf(tagXml, theme = THEME) {
    if (!tagXml) return null
    const rgb = attr(tagXml, 'rgb')
    const tint = +(attr(tagXml, 'tint') ?? 0)
    if (rgb) return applyTint('#' + rgb.slice(-6).toLowerCase(), tint)
    const th = attr(tagXml, 'theme')
    if (th != null) {
        // styles.xml 的 theme 索引：0 lt1, 1 dk1, 2 lt2, 3 dk2 …
        return applyTint(theme[+th] ?? '#000000', tint)
    }
    const ix = attr(tagXml, 'indexed')
    if (ix != null && +ix < 64) return applyTint(INDEXED[+ix], tint)
    return null
}

const BUILTIN_FMT = {
    0: 'General', 1: '0', 2: '0.00', 3: '#,##0', 4: '#,##0.00', 9: '0%', 10: '0.00%', 11: '0.00E+00', 12: '# ?/?', 13: '# ??/??',
    14: 'yyyy-mm-dd', 15: 'd-mmm-yy', 16: 'd-mmm', 17: 'mmm-yy', 18: 'h:mm AM/PM', 19: 'h:mm:ss AM/PM', 20: 'h:mm', 21: 'h:mm:ss', 22: 'yyyy-mm-dd h:mm',
    37: '#,##0 ;(#,##0)', 38: '#,##0 ;[Red](#,##0)', 39: '#,##0.00;(#,##0.00)', 40: '#,##0.00;[Red](#,##0.00)', 45: 'mm:ss', 46: '[h]:mm:ss', 47: 'mmss.0', 48: '##0.0E+0', 49: '@',
    56: '"上午/下午 "hh"時"mm"分"ss"秒 "', 57: 'yyyy"年"m"月"', 58: 'm"月"d"日"', 31: 'yyyy"年"m"月"d"日"', 32: 'h"时"mm"分"', 33: 'h"时"mm"分"ss"秒"',
}
const decode = s => s.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
const encode = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

// 解析主题颜色
export function parseTheme(xml) {
    if (!xml) return THEME
    const get = tag => { const m = new RegExp('<a:' + tag + '>([\\s\\S]*?)</a:' + tag + '>').exec(xml); if (!m) return null; return /(?:srgbClr val|lastClr)="([0-9A-Fa-f]{6})"/.exec(m[1])?.[1] }
    const names = ['lt1', 'dk1', 'lt2', 'dk2', 'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6', 'hlink', 'folHlink']
    return names.map((n, i) => { const c = get(n); return c ? '#' + c.toLowerCase() : THEME[i] })
}

// styles.xml -> 每个 xf 索引对应的样式对象
export function parseStyles(xml, theme) {
    if (!xml) return []
    const section = tag => new RegExp('<' + tag + '\\b[^>]*>([\\s\\S]*?)</' + tag + '>').exec(xml)?.[1] ?? ''
    const items = (body, tag) => body.match(new RegExp('<' + tag + '\\b[^>]*?(?:/>|>[\\s\\S]*?</' + tag + '>)', 'g')) ?? []
    const numFmts = { ...BUILTIN_FMT }
    for (const nf of items(section('numFmts'), 'numFmt')) numFmts[+attr(nf, 'numFmtId')] = decode(attr(nf, 'formatCode') ?? '')
    const fonts = items(section('fonts'), 'font').map(f => {
        const o = {}
        const name = /<name val="([^"]*)"/.exec(f)?.[1]
        if (name) o.font = name
        const sz = /<sz val="([^"]*)"/.exec(f)?.[1]
        if (sz) o.sz = +sz
        if (/<b\/>|<b val="(1|true)"\/>/.test(f)) o.b = true
        if (/<i\/>|<i val="(1|true)"\/>/.test(f)) o.i = true
        if (/<u\/>|<u val="(single|double)"\/>/.test(f)) o.u = true
        if (/<strike\/>|<strike val="(1|true)"\/>/.test(f)) o.st = true
        const c = colorOf(/<color [^>]*\/>/.exec(f)?.[0], theme)
        if (c && c !== '#000000') o.color = c
        return o
    })
    const fills = items(section('fills'), 'fill').map(f => {
        const pt = attr(f, 'patternType')
        if (!pt || pt === 'none' || pt === 'gray125') return {}
        const c = colorOf(/<fgColor [^>]*\/>/.exec(f)?.[0], theme) ?? colorOf(/<bgColor [^>]*\/>/.exec(f)?.[0], theme)
        return c ? { fill: c } : {}
    })
    const borders = items(section('borders'), 'border').map(b => {
        const o = {}
        for (const [side, key] of [['left', 'bl'], ['right', 'br'], ['top', 'bt'], ['bottom', 'bb']]) {
            const m = new RegExp('<' + side + '\\b([^>]*?)(?:/>|>([\\s\\S]*?)</' + side + '>)').exec(b)
            if (!m) continue
            const st = attr(m[1], 'style')
            if (!st) continue
            const color = colorOf(/<color [^>]*\/>/.exec(m[2] ?? '')?.[0], theme) ?? '#000000'
            const style = { thin: 'thin', medium: 'medium', thick: 'thick', dashed: 'dashed', dotted: 'dotted', double: 'double', hair: 'hair', mediumDashed: 'dashed', dashDot: 'dashed', mediumDashDot: 'dashed', dashDotDot: 'dotted', slantDashDot: 'dashed' }[st] ?? 'thin'
            o[key] = style + ' ' + color
        }
        return o
    })
    return items(section('cellXfs'), 'xf').map(xf => {
        const o = { ...fonts[+(attr(xf, 'fontId') ?? 0)] }
        // 默认字体不单独记录
        const def = fonts[0] ?? {}
        if (o.font === def.font) delete o.font
        if (o.sz === def.sz) delete o.sz
        Object.assign(o, fills[+(attr(xf, 'fillId') ?? 0)], borders[+(attr(xf, 'borderId') ?? 0)])
        const nf = +(attr(xf, 'numFmtId') ?? 0)
        if (nf && numFmts[nf]) o.fmt = numFmts[nf]
        const al = /<alignment\b[^>]*\/?>/.exec(xf)?.[0]
        if (al) {
            const hz = attr(al, 'horizontal'), vt = attr(al, 'vertical')
            if (hz && ['left', 'center', 'right'].includes(hz)) o.ha = hz
            if (hz === 'centerContinuous') o.ha = 'center'
            if (vt) o.va = vt === 'center' ? 'middle' : vt === 'top' ? 'top' : 'bottom'
            if (attr(al, 'wrapText') === '1' || attr(al, 'wrapText') === 'true') o.wrap = true
            const ind = attr(al, 'indent')
            if (ind) o.indent = +ind
        }
        // Excel 默认垂直对齐为底部；本编辑器默认居中，保留原文件的底部对齐会显得偏下，这里统一视为居中
        if (o.va === 'bottom') delete o.va
        return internStyle(o)
    })
}

// ---------- 写出 ----------
export class StyleWriter {
    constructor(defFont = '微软雅黑', defSz = 11) {
        this.fonts = [{ font: defFont, sz: defSz }]
        this.fontKeys = new Map([[JSON.stringify(this.fonts[0]), 0]])
        this.fills = ['none', 'gray125']
        this.fillKeys = new Map()
        this.borders = [{}]
        this.borderKeys = new Map([['{}', 0]])
        this.numFmts = new Map()
        this.xfs = ['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>']
        this.xfKeys = new Map()
        this.defFont = defFont; this.defSz = defSz
    }
    idx(map, list, key, val) {
        let i = map.get(key)
        if (i == null) { i = list.length; list.push(val); map.set(key, i) }
        return i
    }
    // 样式对象 -> xf 索引
    xf(s) {
        if (!s) return 0
        const k = JSON.stringify(s)
        let i = this.xfKeys.get(k)
        if (i != null) return i
        const f = { font: s.font ?? this.defFont, sz: s.sz ?? this.defSz, b: s.b, i: s.i, u: s.u, st: s.st, color: s.color }
        const fontId = this.idx(this.fontKeys, this.fonts, JSON.stringify(f), f)
        const fillId = s.fill ? this.idx(this.fillKeys, this.fills, s.fill, s.fill) : 0
        const b = { bt: s.bt, br: s.br, bb: s.bb, bl: s.bl }
        const borderId = this.idx(this.borderKeys, this.borders, JSON.stringify(b), b)
        let numFmtId = 0
        if (s.fmt) {
            const builtin = Object.entries(BUILTIN_FMT).find(([id, code]) => code === s.fmt && +id < 50)
            if (builtin) numFmtId = +builtin[0]
            else { numFmtId = this.numFmts.get(s.fmt); if (numFmtId == null) { numFmtId = 164 + this.numFmts.size; this.numFmts.set(s.fmt, numFmtId) } }
        }
        const al = []
        if (s.ha) al.push(`horizontal="${s.ha}"`)
        al.push(`vertical="${s.va === 'top' ? 'top' : s.va === 'bottom' ? 'bottom' : 'center'}"`)
        if (s.wrap) al.push('wrapText="1"')
        if (s.indent) al.push(`indent="${s.indent}"`)
        const xml = `<xf numFmtId="${numFmtId}" fontId="${fontId}" fillId="${fillId}" borderId="${borderId}" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment ${al.join(' ')}/></xf>`
        i = this.xfs.length
        this.xfs.push(xml)
        this.xfKeys.set(k, i)
        return i
    }
    xml() {
        const rgb = c => 'FF' + c.replace('#', '').toUpperCase()
        const fonts = this.fonts.map(f => `<font>${f.b ? '<b/>' : ''}${f.i ? '<i/>' : ''}${f.st ? '<strike/>' : ''}${f.u ? '<u/>' : ''}<sz val="${f.sz}"/>${f.color ? `<color rgb="${rgb(f.color)}"/>` : '<color theme="1"/>'}<name val="${encode(f.font)}"/><family val="2"/><charset val="134"/></font>`)
        const fills = this.fills.map(f => f === 'none' || f === 'gray125' ? `<fill><patternFill patternType="${f}"/></fill>` : `<fill><patternFill patternType="solid"><fgColor rgb="${rgb(f)}"/><bgColor indexed="64"/></patternFill></fill>`)
        const side = (tag, v) => {
            if (!v) return `<${tag}/>`
            const [st, color] = v.split(' ')
            return `<${tag} style="${st}"><color rgb="${rgb(color ?? '#000000')}"/></${tag}>`
        }
        const borders = this.borders.map(b => `<border>${side('left', b.bl)}${side('right', b.br)}${side('top', b.bt)}${side('bottom', b.bb)}<diagonal/></border>`)
        const nf = [...this.numFmts].map(([code, id]) => `<numFmt numFmtId="${id}" formatCode="${encode(code)}"/>`)
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' +
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
            (nf.length ? `<numFmts count="${nf.length}">${nf.join('')}</numFmts>` : '') +
            `<fonts count="${fonts.length}">${fonts.join('')}</fonts>` +
            `<fills count="${fills.length}">${fills.join('')}</fills>` +
            `<borders count="${borders.length}">${borders.join('')}</borders>` +
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
            `<cellXfs count="${this.xfs.length}">${this.xfs.join('')}</cellXfs>` +
            '<cellStyles count="1"><cellStyle name="常规" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0"/></styleSheet>'
    }
}

export { attr, encode, decode }
