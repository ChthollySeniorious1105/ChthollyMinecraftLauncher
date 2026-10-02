// 剪贴板：复制 / 剪切 / 粘贴（系统剪贴板互通 TSV 与 HTML），选择性粘贴
import { toast, escapeHTML } from '../../core/dom.js'
import { MAX_ROWS, MAX_COLS, intersects } from './addr.js'
import { makeCell, internStyle } from './model.js'
import { shiftFormula, moveRefsInFormula } from './formula/lexer.js'
import { display } from './format.js'
import { parseInput } from './editing.js'
import { cssColor } from './io-style.js'

export const Clipboard = {
    // 构建剪贴板数据
    clipData(g, sh = this.sheet) {
        g = this.clampUsed(g, sh)
        const rows = []
        for (let r = g.r1; r <= g.r2; r++) {
            if (this.grid.rows.isHidden(r) && sh.meta.filter) continue
            const row = []
            for (let c = g.c1; c <= g.c2; c++) {
                const cell = sh.get(r, c)
                row.push({ cell, v: this.valueOf(sh, r, c, cell), style: sh.styleAt(r, c, cell) })
            }
            rows.push(row)
        }
        const merges = sh.meta.merges.filter(m => m.r1 >= g.r1 && m.r2 <= g.r2 && m.c1 >= g.c1 && m.c2 <= g.c2).map(m => ({ r1: m.r1 - g.r1, c1: m.c1 - g.c1, r2: m.r2 - g.r1, c2: m.c2 - g.c1 }))
        const text = rows.map(row => row.map(x => {
            const t = display(x.v, x.style?.fmt).text
            return /[\t\n"]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t
        }).join('\t')).join('\r\n')
        const html = '<table>' + rows.map(row => '<tr>' + row.map(x => {
            const s = x.style
            const css = []
            if (s?.b) css.push('font-weight:bold')
            if (s?.i) css.push('font-style:italic')
            if (s?.u) css.push('text-decoration:underline')
            if (s?.color) css.push('color:' + s.color)
            if (s?.fill) css.push('background:' + s.fill)
            if (s?.sz) css.push(`font-size:${s.sz}pt`)
            if (s?.ha) css.push('text-align:' + s.ha)
            return `<td${css.length ? ` style="${css.join(';')}"` : ''}>${escapeHTML(display(x.v, s?.fmt).text)}</td>`
        }).join('') + '</tr>').join('') + '</table>'
        return { range: g, sheetId: sh.id, rows, merges, text, html }
    },

    copy(cut = false) {
        if (this.sel.ranges.length > 1) return toast('无法对多重选择区域执行此操作', 'warn')
        const d = this.clipData(this.range)
        this.clip = { ...d, cut }
        this.writeSystemClipboard(d)
        this.startAnts()
        this.grid.requestDraw()
    },
    writeSystemClipboard(d) {
        try {
            const item = new ClipboardItem({ 'text/plain': new Blob([d.text], { type: 'text/plain' }), 'text/html': new Blob([d.html], { type: 'text/html' }) })
            navigator.clipboard.write([item]).catch(() => navigator.clipboard.writeText(d.text).catch(() => {}))
        } catch { navigator.clipboard?.writeText(d.text).catch(() => {}) }
        this.lastClipText = d.text
    },
    // 原生 copy / cut 事件（Ctrl+C / Ctrl+X）
    onCopyEvent(e, cut) {
        if (this.editing) return
        e.preventDefault()
        if (this.sel.ranges.length > 1) return toast('无法对多重选择区域执行此操作', 'warn')
        const d = this.clipData(this.range)
        e.clipboardData.setData('text/plain', d.text)
        e.clipboardData.setData('text/html', d.html)
        this.lastClipText = d.text
        this.clip = { ...d, cut }
        this.startAnts()
        this.grid.requestDraw()
    },
    onPasteEvent(e) {
        if (this.editing) return
        e.preventDefault()
        const text = e.clipboardData.getData('text/plain')
        const html = e.clipboardData.getData('text/html')
        this.pasteData({ text, html })
    },
    // 菜单中的“粘贴”：从系统剪贴板读取
    async paste(mode = 'all') {
        let text = '', html = ''
        try {
            const items = await navigator.clipboard.read()
            for (const it of items) {
                if (it.types.includes('text/html')) html = await (await it.getType('text/html')).text()
                if (it.types.includes('text/plain')) text = await (await it.getType('text/plain')).text()
            }
        } catch {
            try { text = await navigator.clipboard.readText() } catch { /* 无权限 */ }
        }
        this.pasteData({ text, html }, mode)
    },

    startAnts() {
        clearInterval(this.antsTimer)
        this.antsPhase = 0
        this.antsTimer = setInterval(() => { if (!this.clip) return this.stopAnts(); this.antsPhase = (this.antsPhase + 1) % 18; this.grid.requestDraw() }, 80)
        this.onDispose(() => clearInterval(this.antsTimer))
    },
    stopAnts() { clearInterval(this.antsTimer) },

    // mode: all | values | formats | formulas | transpose
    pasteData({ text, html }, mode = 'all') {
        const internal = this.clip && (!text || normalizeNL(text) === normalizeNL(this.lastClipText ?? ''))
        if (internal) return this.pasteInternal(this.clip, mode)
        let rows = null
        if (html && /<table/i.test(html)) rows = parseHTMLTable(html)
        if (!rows && text) rows = parseTSV(text).map(r => r.map(t => ({ text: t })))
        if (!rows?.length) return
        this.pasteExternal(rows, mode)
    },

    // 目标区域：选区为多个单元格且是源尺寸的整数倍时平铺
    pasteTarget(R, C) {
        const g = this.range
        const h0 = g.r2 - g.r1 + 1, w0 = g.c2 - g.c1 + 1
        const tileR = h0 % R === 0 && h0 > R && !this.isFullCols(g) ? h0 / R : 1
        const tileC = w0 % C === 0 && w0 > C && !this.isFullRows(g) ? w0 / C : 1
        return { r0: g.r1, c0: g.c1, tileR, tileC }
    },

    pasteInternal(clip, mode) {
        const src = this.sheets.find(s => s.id === clip.sheetId)
        const transpose = mode === 'transpose'
        const R = clip.rows.length, C = clip.rows[0]?.length ?? 0
        const RR = transpose ? C : R, CC = transpose ? R : C
        const { r0, c0, tileR, tileC } = this.pasteTarget(RR, CC)
        if (r0 + RR * tileR > MAX_ROWS || c0 + CC * tileC > MAX_COLS) return toast('粘贴区域超出工作表范围', 'warn')
        const sh = this.sheet
        const target = { r1: r0, c1: c0, r2: r0 + RR * tileR - 1, c2: c0 + CC * tileC - 1 }
        this.batch(clip.cut ? '剪切粘贴' : '粘贴', set => {
            // 剪切：先清空源区域
            if (clip.cut && src) {
                src.cells.each((r, c) => { src.set(r, c, null); if (src === sh) set(r, c, null) }, clip.range.r1, clip.range.c1, clip.range.r2, clip.range.c2)
            }
            for (let tr = 0; tr < tileR; tr++) for (let tc = 0; tc < tileC; tc++) {
                for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) {
                    const x = clip.rows[i][j]
                    const ri = transpose ? j : i, cj = transpose ? i : j
                    const r = r0 + tr * RR + ri, c = c0 + tc * CC + cj
                    const old = sh.get(r, c)
                    const sr = clip.range.r1 + i, sc = clip.range.c1 + j
                    let cell
                    if (mode === 'formats') cell = makeCell(old?.v, old?.f, x.style)
                    else if (mode === 'values') cell = makeCell(x.v != null && typeof x.v === 'object' ? String(x.v) : x.v, null, old?.s ?? null)
                    else {
                        let f = x.cell?.f
                        if (f && !clip.cut) f = shiftFormula(f, r - sr, c - sc)
                        cell = makeCell(x.cell?.v, f, mode === 'formulas' ? old?.s ?? null : x.style)
                    }
                    set(r, c, cell)
                }
            }
            // 合并单元格
            if (mode !== 'values' && !transpose) {
                const keep = sh.meta.merges.filter(m => !intersects(m, target))
                const add = []
                for (let tr = 0; tr < tileR; tr++) for (let tc = 0; tc < tileC; tc++) for (const m of clip.merges) add.push({ r1: m.r1 + r0 + tr * RR, c1: m.c1 + c0 + tc * CC, r2: m.r2 + r0 + tr * RR, c2: m.c2 + c0 + tc * CC })
                sh.setMeta({ merges: [...keep, ...add] })
            }
            if (clip.cut && src) {
                // 其他公式中指向源区域的引用移动到新位置
                if (src !== sh) src.setMeta({ merges: src.meta.merges.filter(m => !intersects(m, clip.range)) })
                for (const other of this.sheets) other.cells.each((r, c, cell) => {
                    if (!cell.f) return
                    const nf = moveRefsInFormula(cell.f, { sheet: src.name, formulaSheet: other.name, from: clip.range, dr: r0 - clip.range.r1, dc: c0 - clip.range.c1, toSheet: sh.name })
                    if (nf !== cell.f) { other.set(r, c, { ...cell, f: nf }); if (other === sh) set(r, c, { ...cell, f: nf }) }
                })
            }
        }, { structural: clip.cut || R * C > 2000 })
        if (clip.cut) { this.clip = null; this.stopAnts() }
        this.selectRange(target)
    },

    pasteExternal(rows, mode) {
        const R = rows.length, C = Math.max(...rows.map(r => r.length))
        const transpose = mode === 'transpose'
        const RR = transpose ? C : R, CC = transpose ? R : C
        const { r0, c0 } = this.pasteTarget(RR, CC)
        if (r0 + RR > MAX_ROWS || c0 + CC > MAX_COLS) return toast('粘贴区域超出工作表范围', 'warn')
        const sh = this.sheet
        this.batch('粘贴', set => {
            for (let i = 0; i < R; i++) for (let j = 0; j < C; j++) {
                const x = rows[i][j] ?? { text: '' }
                const r = r0 + (transpose ? j : i), c = c0 + (transpose ? i : j)
                const old = sh.get(r, c)
                if (mode === 'formats') { set(r, c, makeCell(old?.v, old?.f, x.style ? internStyle({ ...old?.s, ...x.style }) : old?.s)); continue }
                const p = parseInput(x.text)
                let s = mode === 'values' ? old?.s ?? null : x.style ? internStyle({ ...(old?.s ?? {}), ...x.style }) : old?.s ?? null
                if (p.fmt && !s?.fmt) s = internStyle({ ...(s ?? {}), fmt: p.fmt })
                set(r, c, makeCell(p.v, mode === 'values' ? null : p.f, s))
            }
            const keep = sh.meta.merges.filter(m => !intersects(m, { r1: r0, c1: c0, r2: r0 + RR - 1, c2: c0 + CC - 1 }))
            const add = rows.merges && !transpose ? rows.merges.map(m => ({ r1: m.r1 + r0, c1: m.c1 + c0, r2: m.r2 + r0, c2: m.c2 + c0 })) : []
            if (keep.length !== sh.meta.merges.length || add.length) sh.setMeta({ merges: [...keep, ...add] })
        }, { structural: R * C > 2000 })
        this.clip = null
        this.stopAnts()
        this.selectRange({ r1: r0, c1: c0, r2: r0 + RR - 1, c2: c0 + CC - 1 })
    },
}

const normalizeNL = s => String(s).replace(/\r\n/g, '\n').replace(/\n$/, '')

// TSV 解析（支持引号内的换行与制表符）
export function parseTSV(text) {
    text = text.replace(/\r\n/g, '\n').replace(/\n$/, '')
    const rows = [[]]
    let cur = '', q = false
    for (let i = 0; i < text.length; i++) {
        const ch = text[i]
        if (q) {
            if (ch === '"' && text[i + 1] === '"') { cur += '"'; i++ }
            else if (ch === '"') q = false
            else cur += ch
        } else if (ch === '"' && cur === '') q = true
        else if (ch === '\t') { rows[rows.length - 1].push(cur); cur = '' }
        else if (ch === '\n') { rows[rows.length - 1].push(cur); rows.push([]); cur = '' }
        else cur += ch
    }
    rows[rows.length - 1].push(cur)
    return rows
}

// 解析 Excel / 网页复制的 HTML 表格（含基础样式与合并单元格）
export function parseHTMLTable(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html')
    const table = doc.querySelector('table')
    if (!table) return null
    // Excel 的 <style> 中定义了类样式
    const classCss = new Map()
    for (const st of doc.querySelectorAll('style')) {
        for (const m of st.textContent.matchAll(/\.([\w-]+)\s*\{([^}]*)\}/g)) classCss.set(m[1], m[2])
    }
    const rows = []
    const merges = []
    const occupied = new Set()
    let r = 0
    for (const tr of table.querySelectorAll('tr')) {
        const row = rows[r] ??= []
        let c = 0
        for (const td of tr.querySelectorAll('td, th')) {
            while (occupied.has(r + ',' + c)) c++
            const rs = +td.getAttribute('rowspan') || 1, cs = +td.getAttribute('colspan') || 1
            const css = [...td.classList].map(k => classCss.get(k) ?? '').join(';') + ';' + (td.getAttribute('style') ?? '')
            const style = cssToStyle(css, td)
            let text = td.innerText ?? td.textContent
            text = td.textContent.replace(/ /g, ' ').replace(/\s*\n\s*/g, td.querySelector('br') ? '\n' : ' ').trim()
            if (td.querySelector('br')) text = [...td.childNodes].map(n => n.nodeName === 'BR' ? '\n' : n.textContent).join('').trim()
            row[c] = { text, style }
            if (rs > 1 || cs > 1) {
                merges.push({ r1: r, c1: c, r2: r + rs - 1, c2: c + cs - 1 })
                for (let i = 0; i < rs; i++) for (let j = 0; j < cs; j++) if (i || j) { occupied.add((r + i) + ',' + (c + j)); (rows[r + i] ??= [])[c + j] = { text: '' } }
            }
            c += cs
        }
        r++
    }
    rows.merges = merges
    return rows
}

function cssToStyle(css, td) {
    const get = k => { const m = new RegExp('(?:^|;)\\s*' + k + '\\s*:\\s*([^;]+)', 'i').exec(css); return m?.[1].trim() }
    const s = {}
    const fw = get('font-weight')
    if (fw && (fw === 'bold' || +fw >= 600)) s.b = true
    if (td.querySelector('b, strong')) s.b = true
    if (/italic/i.test(get('font-style') ?? '') || td.querySelector('i, em')) s.i = true
    if (/underline/i.test(get('text-decoration') ?? '') || td.querySelector('u')) s.u = true
    const color = cssColor(get('color'))
    if (color && color !== '#000000') s.color = color
    const bg = cssColor(get('background') ?? get('background-color'))
    if (bg && bg !== '#ffffff') s.fill = bg
    const ta = get('text-align')
    if (ta && ['left', 'center', 'right'].includes(ta)) s.ha = ta
    const fs = get('font-size')
    if (fs) { const m = /([\d.]+)(pt|px)/.exec(fs); if (m) { const pt = m[2] === 'px' ? +m[1] * 0.75 : +m[1]; if (Math.abs(pt - 11) > 0.4) s.sz = Math.round(pt * 2) / 2 } }
    return Object.keys(s).length ? s : null
}
