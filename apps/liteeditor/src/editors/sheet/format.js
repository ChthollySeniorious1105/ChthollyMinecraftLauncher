// 单元格样式、显示文本、条件格式
import { formatValue } from './numfmt.js'
import { isErr } from './formula/values.js'
import { inRange } from './addr.js'

export const DEFAULT_FONT = '微软雅黑'
export const DEFAULT_SZ = 11
export const FONTS = ['微软雅黑', '等线', '宋体', '黑体', '楷体', '仿宋', 'Calibri', 'Arial', 'Segoe UI', 'Times New Roman', 'Consolas', 'Courier New', 'Georgia', 'Verdana']
export const SIZES = [8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
const FAMILY = {
    '微软雅黑': '"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", sans-serif',
    '等线': 'DengXian, "Microsoft YaHei UI", sans-serif',
    '宋体': 'SimSun, "Songti SC", serif', '黑体': 'SimHei, "Heiti SC", sans-serif',
    '楷体': 'KaiTi, "Kaiti SC", serif', '仿宋': 'FangSong, serif',
}
export const fontFamily = name => FAMILY[name ?? DEFAULT_FONT] ?? `"${name}", "Microsoft YaHei UI", sans-serif`

// canvas font 字符串；sz 单位为磅
export function fontString(s, z = 1) {
    const px = ((s?.sz ?? DEFAULT_SZ) * 4 / 3 * z).toFixed(2)
    return `${s?.i ? 'italic ' : ''}${s?.b ? 'bold ' : ''}${px}px ${fontFamily(s?.font)}`
}

// 值 + 格式 -> { text, color }
export function display(v, fmt) {
    if (v == null) return { text: '' }
    if (isErr(v)) return { text: v.code }
    if (fmt === '@' && typeof v === 'number') return { text: String(v) }
    try { return formatValue(v, fmt) } catch { return { text: String(v) } }
}

export const defaultAlign = v => typeof v === 'number' ? 'right' : typeof v === 'boolean' || isErr(v) ? 'center' : 'left'

// 边框：'thin #000000'
export const BORDER_STYLES = ['thin', 'medium', 'thick', 'dashed', 'dotted', 'double', 'hair']
export function parseBorder(b) {
    if (!b) return null
    const [style = 'thin', color = '#000000'] = b.split(' ')
    return { style, color }
}
export const borderWidth = st => st === 'medium' ? 2 : st === 'thick' ? 3 : st === 'double' ? 3 : 1

// ---------- 数字格式预设 ----------
export const NUM_FORMATS = [
    ['General', '常规', '1234.5'],
    ['0', '数值（整数）', '1235'],
    ['0.00', '数值（2 位小数）', '1234.50'],
    ['#,##0', '千分位', '1,235'],
    ['#,##0.00', '千分位（2 位小数）', '1,234.50'],
    ['"¥"#,##0.00', '货币 ¥', '¥1,234.50'],
    ['"$"#,##0.00', '货币 $', '$1,234.50'],
    ['"¥"#,##0.00;[Red]-"¥"#,##0.00', '货币（负数红色）', '-¥1,234.50'],
    ['0%', '百分比', '12%'],
    ['0.00%', '百分比（2 位小数）', '12.35%'],
    ['yyyy-mm-dd', '日期', '2024-03-15'],
    ['yyyy"年"m"月"d"日"', '长日期', '2024年3月15日'],
    ['m/d', '短日期', '3/15'],
    ['h:mm:ss', '时间', '13:30:00'],
    ['h:mm', '时间（时:分）', '13:30'],
    ['yyyy-mm-dd h:mm', '日期时间', '2024-03-15 13:30'],
    ['0.00E+00', '科学计数', '1.23E+03'],
    ['@', '文本', 'abc'],
]

// 调整小数位数
export function stepDecimals(fmt, delta, sample) {
    if (!fmt || fmt === 'General') {
        const dec = typeof sample === 'number' && !Number.isInteger(sample) ? Math.min(10, (String(sample).split('.')[1] ?? '').length) : 0
        const d = Math.max(0, dec + delta)
        return d ? '0.' + '0'.repeat(d) : '0'
    }
    if (/[ymdhs]/i.test(fmt.replace(/"[^"]*"/g, ''))) return fmt
    return fmt.split(';').map(sec => {
        // 找到最后一个数字占位块（忽略引号内的字面量）
        const re = /([0#,]*0)(\.0*)?/g
        let last = null, x
        const masked = sec.replace(/"[^"]*"/g, m => ' '.repeat(m.length))
        while ((x = re.exec(masked))) if (x[0]) last = x
        if (!last) return sec
        const cur = last[2] ? last[2].length - 1 : 0
        const d = Math.max(0, cur + delta)
        const rep = last[1] + (d ? '.' + '0'.repeat(d) : '')
        return sec.slice(0, last.index) + rep + sec.slice(last.index + last[0].length)
    }).join(';')
}

// ---------- 条件格式 ----------
// 规则：{ id, range, type, a, b, text, style: { fill, color, b }, color, colors }
// type: gt lt between eq ne text notext begins dup unique top bottom above below bar scale formula blank
export const CF_TYPES = [
    ['gt', '大于'], ['lt', '小于'], ['between', '介于'], ['eq', '等于'], ['ne', '不等于'],
    ['text', '文本包含'], ['begins', '开头是'], ['dup', '重复值'], ['unique', '唯一值'],
    ['top', '值最大的 N 项'], ['bottom', '值最小的 N 项'], ['above', '高于平均值'], ['below', '低于平均值'],
    ['blank', '空值'], ['formula', '使用公式'],
]
export const CF_PRESETS = [
    ['浅红填充深红文本', { fill: '#fde2e4', color: '#9c0006' }],
    ['黄填充深黄文本', { fill: '#fff2c7', color: '#8a5a00' }],
    ['绿填充深绿文本', { fill: '#d9f2dc', color: '#006100' }],
    ['浅红填充', { fill: '#fde2e4' }],
    ['红色文本', { color: '#c00000' }],
    ['加粗蓝色文本', { color: '#1d4ed8', b: true }],
]

// 为一组规则准备统计量（数据条 / 色阶 / 前 N 项 / 重复值 需要整个区域的数据）
// valueAt(r, c) 返回计算后的值
export function cfPrepare(rules, valueAt, eachCell) {
    return rules.map(rule => {
        const st = { rule }
        const need = ['bar', 'scale', 'top', 'bottom', 'above', 'below', 'dup', 'unique'].includes(rule.type)
        if (!need) return st
        const nums = [], counts = new Map()
        eachCell(rule.range, (r, c) => {
            const v = valueAt(r, c)
            if (typeof v === 'number') nums.push(v)
            if (v != null && v !== '') { const k = typeof v === 'string' ? v.toLowerCase() : v; counts.set(k, (counts.get(k) ?? 0) + 1) }
        })
        st.min = nums.length ? Math.min(...nums) : 0
        st.max = nums.length ? Math.max(...nums) : 0
        st.avg = nums.length ? nums.reduce((a, b) => a + b, 0) / nums.length : 0
        st.counts = counts
        if (rule.type === 'top' || rule.type === 'bottom') {
            const s = [...nums].sort((a, b) => rule.type === 'top' ? b - a : a - b)
            const n = Math.max(1, Math.floor(rule.a ?? 10))
            st.cut = s[Math.min(n, s.length) - 1]
        }
        return st
    })
}

const lerp = (a, b, t) => Math.round(a + (b - a) * t)
const hex = c => [1, 3, 5].map(i => parseInt(c.slice(i, i + 2), 16))
export function mix(c1, c2, t) {
    const a = hex(c1), b = hex(c2)
    return '#' + a.map((x, i) => lerp(x, b[i], t).toString(16).padStart(2, '0')).join('')
}

// 计算某单元格的条件格式结果：{ fill, color, b, i, bar: { t, color } }
export function cfApply(prepared, r, c, v, evalFormula) {
    let out = null
    for (const st of prepared) {
        const rule = st.rule
        if (!inRange(rule.range, r, c)) continue
        let hit = false
        const n = typeof v === 'number' ? v : null
        switch (rule.type) {
            case 'gt': hit = n != null && n > +rule.a; break
            case 'lt': hit = n != null && n < +rule.a; break
            case 'ge': hit = n != null && n >= +rule.a; break
            case 'le': hit = n != null && n <= +rule.a; break
            case 'between': hit = n != null && n >= Math.min(+rule.a, +rule.b) && n <= Math.max(+rule.a, +rule.b); break
            case 'eq': hit = n != null ? n === +rule.a : v != null && String(v).toLowerCase() === String(rule.a ?? '').toLowerCase(); break
            case 'ne': hit = v != null && v !== '' && (n != null ? n !== +rule.a : String(v).toLowerCase() !== String(rule.a ?? '').toLowerCase()); break
            case 'text': hit = v != null && String(v).toLowerCase().includes(String(rule.a ?? '').toLowerCase()); break
            case 'notext': hit = v != null && !String(v).toLowerCase().includes(String(rule.a ?? '').toLowerCase()); break
            case 'begins': hit = v != null && String(v).toLowerCase().startsWith(String(rule.a ?? '').toLowerCase()); break
            case 'blank': hit = v == null || v === ''; break
            case 'dup': case 'unique': {
                if (v == null || v === '') break
                const k = typeof v === 'string' ? v.toLowerCase() : v
                const cnt = st.counts.get(k) ?? 0
                hit = rule.type === 'dup' ? cnt > 1 : cnt === 1
                break
            }
            case 'top': hit = n != null && st.cut != null && n >= st.cut; break
            case 'bottom': hit = n != null && st.cut != null && n <= st.cut; break
            case 'above': hit = n != null && n > st.avg; break
            case 'below': hit = n != null && n < st.avg; break
            case 'formula': {
                if (!evalFormula) break
                const res = evalFormula(rule.a, r - rule.range.r1, c - rule.range.c1)
                hit = res === true || (typeof res === 'number' && res !== 0)
                break
            }
            case 'bar': {
                if (n == null) break
                const lo = Math.min(0, st.min), span = st.max - lo || 1
                out = { ...out, bar: { t: Math.max(0, Math.min(1, (n - lo) / span)), color: rule.color ?? '#638ec6' } }
                continue
            }
            case 'scale': {
                if (n == null) break
                const cs = rule.colors ?? ['#f8696b', '#ffeb84', '#63be7b']
                const t = st.max === st.min ? 0.5 : (n - st.min) / (st.max - st.min)
                const fill = cs.length === 3 ? (t < 0.5 ? mix(cs[0], cs[1], t * 2) : mix(cs[1], cs[2], (t - 0.5) * 2)) : mix(cs[0], cs[1], t)
                out = { ...out, fill }
                continue
            }
        }
        if (hit) out = { ...out, ...rule.style }
    }
    return out
}
