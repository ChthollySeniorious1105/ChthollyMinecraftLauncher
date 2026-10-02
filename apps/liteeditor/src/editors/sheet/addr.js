// 地址工具：行列均为 0 起始
export const MAX_ROWS = 1048576
export const MAX_COLS = 16384

export function colName(c) {
    let s = ''
    c++
    while (c > 0) {
        const m = (c - 1) % 26
        s = String.fromCharCode(65 + m) + s
        c = Math.floor((c - 1) / 26)
    }
    return s
}

export function colIndex(name) {
    let c = 0
    for (const ch of name.toUpperCase()) c = c * 26 + (ch.charCodeAt(0) - 64)
    return c - 1
}

export const cellName = (r, c) => colName(c) + (r + 1)

// 'A1' / '$B$3' -> { r, c }
export function parseCell(s) {
    const m = /^\$?([A-Za-z]{1,3})\$?(\d+)$/.exec(s.trim())
    if (!m) return null
    const r = +m[2] - 1, c = colIndex(m[1])
    if (r < 0 || r >= MAX_ROWS || c >= MAX_COLS) return null
    return { r, c }
}

// 'A1:C5' / 'A:A' / '3:5' / 'B2' -> { r1, c1, r2, c2 }（已规范化）
export function parseRange(s) {
    s = s.trim().replace(/^.*!/, '')
    const parts = s.split(':')
    if (parts.length === 1) {
        const a = parseCell(parts[0])
        return a && { r1: a.r, c1: a.c, r2: a.r, c2: a.c }
    }
    if (parts.length !== 2) return null
    const [x, y] = parts.map(p => p.trim())
    let a, b
    if (/^\$?[A-Za-z]{1,3}$/.test(x) && /^\$?[A-Za-z]{1,3}$/.test(y)) {
        a = { r: 0, c: colIndex(x.replace('$', '')) }; b = { r: MAX_ROWS - 1, c: colIndex(y.replace('$', '')) }
    } else if (/^\$?\d+$/.test(x) && /^\$?\d+$/.test(y)) {
        a = { r: +x.replace('$', '') - 1, c: 0 }; b = { r: +y.replace('$', '') - 1, c: MAX_COLS - 1 }
    } else {
        a = parseCell(x); b = parseCell(y)
    }
    if (!a || !b) return null
    return normRange({ r1: a.r, c1: a.c, r2: b.r, c2: b.c })
}

export const normRange = ({ r1, c1, r2, c2 }) => ({ r1: Math.min(r1, r2), c1: Math.min(c1, c2), r2: Math.max(r1, r2), c2: Math.max(c1, c2) })

export function rangeName({ r1, c1, r2, c2 }) {
    if (r1 === 0 && r2 >= MAX_ROWS - 1) return colName(c1) + ':' + colName(c2)
    if (c1 === 0 && c2 >= MAX_COLS - 1) return (r1 + 1) + ':' + (r2 + 1)
    const a = cellName(r1, c1)
    return r1 === r2 && c1 === c2 ? a : a + ':' + cellName(r2, c2)
}

export const inRange = (g, r, c) => r >= g.r1 && r <= g.r2 && c >= g.c1 && c <= g.c2
export const intersects = (a, b) => a.r1 <= b.r2 && a.r2 >= b.r1 && a.c1 <= b.c2 && a.c2 >= b.c1
export const sameRange = (a, b) => a && b && a.r1 === b.r1 && a.c1 === b.c1 && a.r2 === b.r2 && a.c2 === b.c2

// 工作表名称在公式中是否需要引号
export const quoteSheet = name => /^[A-Za-z_一-鿿][\w.一-鿿]*$/.test(name) && !/^[A-Za-z]{1,3}\d+$/.test(name)
    ? name : `'${name.replace(/'/g, "''")}'`

// 单元格数值键：sheetId * 2^34 + r * 16384 + c
const R = 16384, S = 2 ** 34
export const cellKey = (sid, r, c) => sid * S + r * R + c
export const keySheet = k => Math.floor(k / S)
export const keyRow = k => Math.floor((k % S) / R)
export const keyCol = k => k % R
