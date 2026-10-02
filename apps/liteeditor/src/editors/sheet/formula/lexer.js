// 公式词法分析：把公式文本（不含开头的 '='）拆成带位置的记号
// 引用记号保留原文位置，便于在复制 / 插入行列时就地改写引用
import { colIndex, colName, MAX_ROWS, MAX_COLS, quoteSheet } from '../addr.js'

const ERRORS = ['#DIV/0!', '#N/A', '#NAME?', '#NULL!', '#NUM!', '#REF!', '#VALUE!', '#CIRC!', '#GETTING_DATA']
const SHEET_RE = /^(?:'((?:[^']|'')+)'|([A-Za-z_㐀-鿿豈-﫿][\w.㐀-鿿豈-﫿]*))!/
const CELL = '(\\$?)([A-Za-z]{1,3})(\\$?)(\\d+)'
const CELL_RANGE_RE = new RegExp('^' + CELL + '(?::' + CELL + ')?(?![\\w(!])')
const COL_RANGE_RE = /^(\$?)([A-Za-z]{1,3}):(\$?)([A-Za-z]{1,3})(?![\w(])/
const ROW_RANGE_RE = /^(\$?)(\d+):(\$?)(\d+)(?![\w(.])/
const NUM_RE = /^(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/
const FUNC_RE = /^([A-Za-z_][\w.]*)\s*\(/
const NAME_RE = /^[A-Za-z_㐀-鿿][\w.㐀-鿿]*/
const OPS = ['<>', '<=', '>=', '+', '-', '*', '/', '^', '&', '=', '<', '>', '%']

export function tokenize(src) {
    const toks = []
    let i = 0
    const n = src.length
    while (i < n) {
        const ch = src[i]
        if (ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r') { i++; continue }
        const rest = src.slice(i)
        const start = i
        // 字符串
        if (ch === '"') {
            let j = i + 1, s = ''
            for (; j < n; j++) {
                if (src[j] === '"') {
                    if (src[j + 1] === '"') { s += '"'; j++ } else break
                } else s += src[j]
            }
            if (j >= n) { toks.push({ t: 'bad', start, end: n, text: rest }); break }
            toks.push({ t: 'str', v: s, start, end: j + 1 })
            i = j + 1
            continue
        }
        // 错误值
        if (ch === '#') {
            const e = ERRORS.find(x => rest.toUpperCase().startsWith(x))
            if (e) { toks.push({ t: 'err', v: e, start, end: i + e.length }); i += e.length; continue }
        }
        // 引用（可带工作表前缀）
        let sheet = null, j = i
        const sm = SHEET_RE.exec(rest)
        if (sm) { sheet = sm[1] != null ? sm[1].replace(/''/g, "'") : sm[2]; j = i + sm[0].length }
        const tail = src.slice(j)
        const ref = matchRef(tail)
        if (ref && (sheet != null || !/^[A-Za-z]{1,3}\d+\s*\(/.test(tail))) {
            ref.sheet = sheet
            ref.start = start
            ref.end = j + ref.len
            ref.t = 'ref'
            delete ref.len
            toks.push(ref)
            i = ref.end
            continue
        }
        if (sheet != null) {
            // 工作表名后面不是合法引用
            toks.push({ t: 'err', v: '#REF!', start, end: j, sheet })
            i = j
            if (/^#REF!/i.test(tail)) { toks[toks.length - 1].end = j + 5; i = j + 5 }
            continue
        }
        const nm = NUM_RE.exec(rest)
        if (nm) { toks.push({ t: 'num', v: parseFloat(nm[0]), start, end: i + nm[0].length }); i += nm[0].length; continue }
        const fm = FUNC_RE.exec(rest)
        if (fm) { toks.push({ t: 'func', v: fm[1].toUpperCase(), start, end: i + fm[1].length }); i += fm[1].length; continue }
        const idm = NAME_RE.exec(rest)
        if (idm) {
            const up = idm[0].toUpperCase()
            if (up === 'TRUE' || up === 'FALSE') toks.push({ t: 'bool', v: up === 'TRUE', start, end: i + idm[0].length })
            else toks.push({ t: 'name', v: idm[0], start, end: i + idm[0].length })
            i += idm[0].length
            continue
        }
        const op = OPS.find(o => rest.startsWith(o))
        if (op) { toks.push({ t: 'op', v: op, start, end: i + op.length }); i += op.length; continue }
        if ('(),;{}:'.includes(ch)) { toks.push({ t: ch === ';' ? ',' : ch, start, end: i + 1, semi: ch === ';' }); i++; continue }
        toks.push({ t: 'bad', start, end: i + 1, text: ch })
        i++
    }
    return toks
}

function matchRef(s) {
    let m = CELL_RANGE_RE.exec(s)
    if (m) {
        const c1 = colIndex(m[2]), r1 = +m[4] - 1
        if (r1 < 0 || r1 >= MAX_ROWS || c1 >= MAX_COLS) return null
        if (m[5] == null) return { kind: 'cell', r1, c1, r2: r1, c2: c1, ar1: !!m[3], ac1: !!m[1], ar2: !!m[3], ac2: !!m[1], len: m[0].length }
        const c2 = colIndex(m[6]), r2 = +m[8] - 1
        if (r2 < 0 || r2 >= MAX_ROWS || c2 >= MAX_COLS) return null
        return { kind: 'range', r1, c1, r2, c2, ar1: !!m[3], ac1: !!m[1], ar2: !!m[7], ac2: !!m[5], len: m[0].length }
    }
    m = COL_RANGE_RE.exec(s)
    if (m) return { kind: 'cols', r1: 0, r2: MAX_ROWS - 1, c1: colIndex(m[2]), c2: colIndex(m[4]), ac1: !!m[1], ac2: !!m[3], ar1: true, ar2: true, len: m[0].length }
    m = ROW_RANGE_RE.exec(s)
    if (m) {
        const r1 = +m[2] - 1, r2 = +m[4] - 1
        if (r1 < 0 || r2 < 0) return null
        return { kind: 'rows', c1: 0, c2: MAX_COLS - 1, r1, r2, ar1: !!m[1], ar2: !!m[3], ac1: true, ac2: true, len: m[0].length }
    }
    return null
}

// 引用记号 -> 文本
export function refText(t) {
    const pre = t.sheet != null ? quoteSheet(t.sheet) + '!' : ''
    const cell = (r, c, ar, ac) => (ac ? '$' : '') + colName(c) + (ar ? '$' : '') + (r + 1)
    if (t.kind === 'cols') return pre + (t.ac1 ? '$' : '') + colName(t.c1) + ':' + (t.ac2 ? '$' : '') + colName(t.c2)
    if (t.kind === 'rows') return pre + (t.ar1 ? '$' : '') + (t.r1 + 1) + ':' + (t.ar2 ? '$' : '') + (t.r2 + 1)
    if (t.kind === 'cell') return pre + cell(t.r1, t.c1, t.ar1, t.ac1)
    return pre + cell(t.r1, t.c1, t.ar1, t.ac1) + ':' + cell(t.r2, t.c2, t.ar2, t.ac2)
}

// 按记号改写公式：fn(refToken) 返回新的记号对象、字符串（直接替换），或 undefined（保持不变）
export function rewriteRefs(src, fn) {
    const toks = tokenize(src)
    let out = '', pos = 0, changed = false
    for (const t of toks) {
        if (t.t !== 'ref') continue
        const r = fn({ ...t })
        if (r === undefined) continue
        const text = typeof r === 'string' ? r : refText(r)
        out += src.slice(pos, t.start) + text
        pos = t.end
        changed = true
    }
    return changed ? out + src.slice(pos) : src
}

// 复制公式时平移相对引用；越界时变为 #REF!
export function shiftFormula(src, dr, dc) {
    if (!dr && !dc) return src
    return rewriteRefs(src, t => {
        if (t.kind !== 'cols') {
            if (!t.ar1) t.r1 += dr
            if (!t.ar2) t.r2 += dr
        }
        if (t.kind !== 'rows') {
            if (!t.ac1) t.c1 += dc
            if (!t.ac2) t.c2 += dc
        }
        if (t.r1 < 0 || t.c1 < 0 || t.r2 < 0 || t.c2 < 0 || t.r1 >= MAX_ROWS || t.r2 >= MAX_ROWS || t.c1 >= MAX_COLS || t.c2 >= MAX_COLS)
            return (t.sheet != null ? quoteSheet(t.sheet) + '!' : '') + '#REF!'
        return t
    })
}

// 插入 / 删除行列时调整引用
// axis: 'row' | 'col'；at: 起始索引；count > 0 插入，< 0 删除 |count| 个
// targetSheet: 被修改的工作表名；formulaSheet: 公式所在工作表名
export function adjustFormula(src, { axis, at, count, targetSheet, formulaSheet }) {
    return rewriteRefs(src, t => {
        const sheet = t.sheet ?? formulaSheet
        if (sheet !== targetSheet) return undefined
        const k1 = axis === 'row' ? 'r1' : 'c1', k2 = axis === 'row' ? 'r2' : 'c2'
        if ((axis === 'row' && t.kind === 'cols') || (axis === 'col' && t.kind === 'rows')) return undefined
        let a = t[k1], b = t[k2]
        if (count > 0) {
            if (a >= at) a += count
            if (b >= at) b += count
        } else {
            const n = -count, end = at + n - 1
            if (a >= at && b <= end) return (t.sheet != null ? quoteSheet(t.sheet) + '!' : '') + '#REF!'
            if (a > end) a -= n
            else if (a >= at) a = at
            if (b > end) b -= n
            else if (b >= at) b = at - 1
        }
        if (a === t[k1] && b === t[k2]) return undefined
        t[k1] = a; t[k2] = b
        return t
    })
}

// 重命名 / 删除工作表时更新引用
export function renameSheetInFormula(src, oldName, newName) {
    return rewriteRefs(src, t => {
        if (t.sheet == null || t.sheet.toLowerCase() !== oldName.toLowerCase()) return undefined
        if (newName == null) return '#REF!'
        t.sheet = newName
        return t
    })
}

// 剪切移动单元格：指向源区域内的引用随之移动
export function moveRefsInFormula(src, { sheet, formulaSheet, from, dr, dc, toSheet }) {
    return rewriteRefs(src, t => {
        const sh = t.sheet ?? formulaSheet
        if (sh !== sheet) return undefined
        if (!(t.r1 >= from.r1 && t.r2 <= from.r2 && t.c1 >= from.c1 && t.c2 <= from.c2)) return undefined
        t.r1 += dr; t.r2 += dr; t.c1 += dc; t.c2 += dc
        if (toSheet !== sheet || t.sheet != null) t.sheet = toSheet === formulaSheet && t.sheet == null ? null : toSheet
        return t
    })
}
