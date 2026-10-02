// 数字格式引擎（Excel 格式代码的常用子集）：
// 分段 正;负;零;文本、[Red] 等颜色、"字面量"、\x、_x、*x、千分位、小数、百分比、科学计数、日期时间、@、分数(简化)
import { serialToDate } from './formula/values.js'

const cache = new Map()
const COLORS = { red: '#e11d48', blue: '#2563eb', green: '#16a34a', black: '#000000', white: '#ffffff', yellow: '#ca8a04', magenta: '#c026d3', cyan: '#0891b2' }
const WEEK = ['日', '一', '二', '三', '四', '五', '六']
const WEEK_EN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const MON_EN = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

// 返回 { text, color }
export function formatValue(v, fmt) {
    if (v == null) return { text: '' }
    if (typeof v === 'boolean') return { text: v ? 'TRUE' : 'FALSE' }
    if (typeof v === 'object') return { text: String(v) }
    if (!fmt || fmt === 'General' || fmt === 'general') {
        if (typeof v === 'number') return { text: general(v) }
        return { text: v }
    }
    const f = compile(fmt)
    if (typeof v === 'string') {
        const sec = f.text
        return sec ? { text: renderText(sec, v), color: sec.color } : { text: v }
    }
    let sec
    if (f.conds) {
        sec = f.sections.find(s => s.cond && testCond(s.cond, v)) ?? f.sections.find(s => !s.cond) ?? f.sections[0]
    } else if (v < 0 && f.sections.length > 1) sec = f.sections[1]
    else if (v === 0 && f.sections.length > 2) sec = f.sections[2]
    else sec = f.sections[0]
    const neg = v < 0 && sec === f.sections[0] && !(f.conds)
    const x = sec === f.sections[0] || f.conds ? v : Math.abs(v)
    if (sec.general) return { text: general(neg ? v : x), color: sec.color }
    return { text: (neg && !sec.date ? '-' : '') + renderNum(sec, Math.abs(x)), color: sec.color }
}

const testCond = ({ op, n }, v) => op === '>' ? v > n : op === '<' ? v < n : op === '>=' ? v >= n : op === '<=' ? v <= n : op === '=' ? v === n : v !== n

// 常规格式：最多 11 个字符宽度的数字
export function general(n) {
    if (!Number.isFinite(n)) return '#NUM!'
    if (Number.isInteger(n) && Math.abs(n) < 1e11) return String(n)
    const a = Math.abs(n)
    if (a !== 0 && (a >= 1e11 || a < 1e-9)) return n.toExponential(5).replace(/\.?0+e/, 'E').replace(/E\+?(-?)(\d)$/, 'E+$10$2').replace('E+-', 'E-')
    let s = String(+n.toPrecision(10))
    if (s.includes('e')) s = n.toFixed(10).replace(/0+$/, '').replace(/\.$/, '')
    return s
}

function compile(fmt) {
    let f = cache.get(fmt)
    if (f) return f
    const parts = splitSections(fmt)
    const sections = parts.map(parseSection)
    f = { sections: sections.filter(s => !s.isText), conds: sections.some(s => s.cond) }
    f.text = sections.find(s => s.isText) ?? (sections.length === 4 ? sections[3] : null)
    if (!f.sections.length) f.sections = [parseSection('General')]
    cache.set(fmt, f)
    return f
}

function splitSections(fmt) {
    const out = []
    let cur = '', q = false
    for (let i = 0; i < fmt.length; i++) {
        const ch = fmt[i]
        if (ch === '"') q = !q
        if (ch === '\\' && !q) { cur += ch + (fmt[i + 1] ?? ''); i++; continue }
        if (ch === ';' && !q) { out.push(cur); cur = ''; continue }
        cur += ch
    }
    out.push(cur)
    return out
}

// 把格式段解析为记号序列
function parseSection(src) {
    const s = { toks: [], color: null, cond: null }
    let i = 0
    while (i < src.length) {
        const ch = src[i]
        if (ch === '[') {
            const j = src.indexOf(']', i)
            const inner = src.slice(i + 1, j < 0 ? src.length : j)
            const low = inner.toLowerCase()
            if (COLORS[low]) s.color = COLORS[low]
            else if (/^color\d+$/.test(low)) s.color = null
            else if (/^(<=|>=|<>|<|>|=)/.test(inner)) { const m = /^(<=|>=|<>|<|>|=)\s*(-?[\d.]+)/.exec(inner); if (m) s.cond = { op: m[1], n: +m[2] } }
            else if (/^\$/.test(inner)) s.toks.push({ lit: inner.slice(1).split('-')[0] })
            else if (/^(h+|m+|s+)$/i.test(inner)) { s.toks.push({ d: inner.toLowerCase()[0] === 'h' ? 'H' : inner.toLowerCase()[0] === 'm' ? 'M' : 'S', elapsed: true }); s.date = true }
            i = j < 0 ? src.length : j + 1
            continue
        }
        if (ch === '"') {
            const j = src.indexOf('"', i + 1)
            s.toks.push({ lit: src.slice(i + 1, j < 0 ? src.length : j) })
            i = j < 0 ? src.length : j + 1
            continue
        }
        if (ch === '\\') { s.toks.push({ lit: src[i + 1] ?? '' }); i += 2; continue }
        if (ch === '_') { s.toks.push({ lit: ' ' }); i += 2; continue }
        if (ch === '*') { i += 2; continue }
        if (ch === '@') { s.toks.push({ at: true }); s.isText = true; i++; continue }
        if (/^general/i.test(src.slice(i))) { s.general = true; i += 7; continue }
        const dm = /^(yyyy|yy|e|mmmmm|mmmm|mmm|mm|m|dddd|ddd|dd|d|hh|h|ss|s|am\/pm|a\/p|上午\/下午)/i.exec(src.slice(i))
        if (dm && !/[0#?]/.test(ch)) {
            const k = dm[1].toLowerCase()
            s.toks.push({ d: k })
            s.date = true
            i += dm[1].length
            if (k === 'ss' || k === 's') {
                const fm = /^\.(0+)/.exec(src.slice(i))
                if (fm) { s.toks.push({ d: 'frac', n: fm[1].length }); i += fm[0].length }
            }
            continue
        }
        if (ch === '%') { s.toks.push({ lit: '%' }); s.pctCount = (s.pctCount ?? 0) + 1; i++; continue }
        if ('0#?.,Ee'.includes(ch)) {
            // 数字占位符块
            let j = i
            while (j < src.length && /[0#?.,]/.test(src[j]) || (j < src.length && /[Ee]/.test(src[j]) && /[+-]/.test(src[j + 1] ?? ''))) {
                if (/[Ee]/.test(src[j])) j += 2
                else j++
            }
            if (j === i) { s.toks.push({ lit: ch }); i++; continue }
            s.toks.push({ num: src.slice(i, j) })
            i = j
            continue
        }
        s.toks.push({ lit: ch })
        i++
    }
    // 月份 m 与分钟 m 的区分：紧随 h 之后或 s 之前的 m 视为分钟
    if (s.date) {
        const dts = s.toks.filter(t => t.d)
        dts.forEach((t, k) => {
            if (t.d === 'm' || t.d === 'mm') {
                const prev = dts[k - 1], next = dts[k + 1]
                if ((prev && /^h/.test(prev.d)) || (next && /^s/.test(next.d))) t.d = t.d === 'm' ? 'min' : 'mmin'
            }
        })
        s.ampm = s.toks.some(t => t.d === 'am/pm' || t.d === 'a/p' || t.d === '上午/下午')
    }
    // 数字块：合并成一个规格
    const numToks = s.toks.filter(t => t.num)
    if (numToks.length && !s.date) {
        const all = numToks.map(t => t.num).join('')
        s.pct = s.pctCount ?? 0
        const em = /[Ee]([+-])(0+)/.exec(all)
        s.sci = em ? { plus: em[1] === '+', digits: em[2].length } : null
        const mant = em ? all.slice(0, em.index) : all
        const [ip, dp = ''] = mant.split('.')
        s.comma = /[0#?],[0#?]/.test(ip)
        s.scale = (/,+$/.exec(ip)?.[0].length) ?? 0
        const ipd = ip.replace(/,/g, '')
        s.minInt = (ipd.match(/0/g) ?? []).length
        s.minDec = (dp.match(/0/g) ?? []).length
        s.maxDec = (dp.match(/[0#?]/g) ?? []).length
        s.hasDot = mant.includes('.')
        // 仅保留第一个数字块作为插入位置，其余（如 % 的独立块）作为字面量
        let first = true
        s.toks = s.toks.map(t => {
            if (!t.num) return t
            if (first) { first = false; return { numSlot: true } }
            return { lit: t.num.replace(/[0#?.,]/g, '') }
        })
    }
    return s
}

function renderNum(s, x) {
    if (s.date) return renderDate(s, x)
    if (s.toks.every(t => t.lit != null || t.at)) return s.toks.map(t => t.lit ?? '').join('')
    let v = x * Math.pow(100, s.pct ?? 0) / Math.pow(1000, s.scale ?? 0)
    let body
    if (s.sci) {
        let e = v === 0 ? 0 : Math.floor(Math.log10(v))
        let m = v / Math.pow(10, e)
        let ms = m.toFixed(s.maxDec)
        if (+ms >= 10) { e++; m = v / Math.pow(10, e); ms = m.toFixed(s.maxDec) }
        ms = trimDec(ms, s)
        const es = String(Math.abs(e)).padStart(s.sci.digits, '0')
        body = ms + 'E' + (e < 0 ? '-' : s.sci.plus ? '+' : '') + es
    } else {
        let t = round(v, s.maxDec)
        t = trimDec(t, s)
        let [ip, dp] = t.split('.')
        if (ip === '0' && s.minInt === 0) ip = ''
        if (ip.length < s.minInt) ip = ip.padStart(s.minInt, '0')
        if (s.comma) ip = ip.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
        body = ip + (dp != null ? '.' + dp : s.hasDot && s.maxDec === 0 ? '.' : '')
    }
    return s.toks.map(t => t.numSlot ? body : t.lit ?? '').join('')
}

function round(v, d) {
    const r = Math.round(v * Math.pow(10, d) + (v >= 0 ? 1e-9 : -1e-9)) / Math.pow(10, d)
    return r.toFixed(d)
}
function trimDec(t, s) {
    if (!t.includes('.')) return t
    let [ip, dp] = t.split('.')
    while (dp.length > s.minDec && dp.endsWith('0')) dp = dp.slice(0, -1)
    return dp.length ? ip + '.' + dp : ip
}

function renderText(s, v) {
    return s.toks.map(t => t.at ? v : t.lit ?? '').join('')
}

function renderDate(s, x) {
    const d = serialToDate(x)
    const Y = d.getUTCFullYear(), M = d.getUTCMonth(), D = d.getUTCDate(), W = d.getUTCDay()
    let hh = d.getUTCHours(), mi = d.getUTCMinutes(), ss = d.getUTCSeconds()
    const ms = d.getUTCMilliseconds()
    const p2 = n => String(n).padStart(2, '0')
    const pm = hh >= 12
    const h12 = hh % 12 === 0 ? 12 : hh % 12
    return s.toks.map(t => {
        if (t.lit != null) return t.lit
        if (t.numSlot) return ''
        if (t.elapsed) {
            const total = x * 86400
            return t.d === 'H' ? Math.floor(total / 3600) : t.d === 'M' ? Math.floor(total / 60) : Math.floor(total)
        }
        switch (t.d) {
            case 'yyyy': case 'e': return String(Y)
            case 'yy': return p2(Y % 100)
            case 'm': return String(M + 1)
            case 'mm': return p2(M + 1)
            case 'mmm': return MON_EN[M].slice(0, 3)
            case 'mmmm': return MON_EN[M]
            case 'mmmmm': return MON_EN[M][0]
            case 'd': return String(D)
            case 'dd': return p2(D)
            case 'ddd': return '周' + WEEK[W]
            case 'dddd': return '星期' + WEEK[W]
            case 'h': return String(s.ampm ? h12 : hh)
            case 'hh': return p2(s.ampm ? h12 : hh)
            case 'min': return String(mi)
            case 'mmin': return p2(mi)
            case 's': return String(ss)
            case 'ss': return p2(ss)
            case 'frac': return '.' + String(ms).padStart(3, '0').slice(0, t.n)
            case 'am/pm': return pm ? 'PM' : 'AM'
            case 'a/p': return pm ? 'P' : 'A'
            case '上午/下午': return pm ? '下午' : '上午'
        }
        return ''
    }).join('')
}

export const isDateFormat = fmt => !!fmt && compile(fmt).sections[0].date === true
export const WEEK_NAMES = WEEK_EN
