// 画布渲染：四个窗格（冻结行 × 冻结列）分别裁剪绘制，只绘制可见单元格
import { colName } from './addr.js'
import { fontString, display, defaultAlign, parseBorder, borderWidth } from './format.js'
import { general } from './numfmt.js'

const HEAD_BG = '#f4f5f7', HEAD_LINE = '#d9dce1', HEAD_TEXT = '#5b6270', GRID = '#e1e3e8'
const UI_FONT = '"Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", sans-serif'

export function drawGrid(g) {
    const { ctx, dpr, W, H, HW, HH } = g
    const ed = g.ed, sh = g.sheet, z = g.z
    const snap = v => Math.round(v * dpr) / dpr
    const px = 1 / dpr
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, W, H)
    const accent = ed.accent
    const fW = g.frozenW, fH = g.frozenH
    const [vr0, vr1] = g.visibleRows(), [vc0, vc1] = g.visibleCols()
    const panes = []
    const fr = g.fr, fc = g.fc
    // 窗格：{ x, y, w, h, r0, r1, c0, c1, scrollX, scrollY }
    if (fr && fc) panes.push({ x: HW, y: HH, w: fW, h: fH, r0: 0, r1: fr - 1, c0: 0, c1: fc - 1, sx: false, sy: false })
    if (fr) panes.push({ x: HW + fW, y: HH, w: W - HW - fW, h: fH, r0: 0, r1: fr - 1, c0: vc0, c1: vc1, sx: true, sy: false })
    if (fc) panes.push({ x: HW, y: HH + fH, w: fW, h: H - HH - fH, r0: vr0, r1: vr1, c0: 0, c1: fc - 1, sx: false, sy: true })
    panes.push({ x: HW + fW, y: HH + fH, w: W - HW - fW, h: H - HH - fH, r0: vr0, r1: vr1, c0: vc0, c1: vc1, sx: true, sy: true })

    const cf = ed.cfFor(sh)
    const showGrid = sh.meta.showGrid && !ed.printMode

    for (const p of panes) {
        if (p.w <= 0 || p.h <= 0) continue
        const X = c => HW + (g.cols.pos(c) - (p.sx ? g.sx : 0)) * z
        const Y = r => HH + (g.rows.pos(r) - (p.sy ? g.sy : 0)) * z
        p.X = X; p.Y = Y
        ctx.save()
        ctx.beginPath(); ctx.rect(p.x, p.y, p.w, p.h); ctx.clip()
        const rows = [], cols = []
        for (let r = p.r0; r <= p.r1; r++) if (g.rows.size(r) > 0) rows.push(r)
        for (let c = p.c0; c <= p.c1; c++) if (g.cols.size(c) > 0) cols.push(c)
        const merges = sh.meta.merges.filter(m => m.r2 >= p.r0 && m.r1 <= p.r1 && m.c2 >= p.c0 && m.c1 <= p.c1)
        const inMerge = (r, c) => { for (const m of merges) if (r >= m.r1 && r <= m.r2 && c >= m.c1 && c <= m.c2) return m; return null }

        // 1. 背景（填充色 / 条件格式）
        const info = new Map()
        for (const r of rows) {
            const y = Y(r), hh = g.rowH(r)
            for (const c of cols) {
                const cell = sh.get(r, c)
                const st = sh.styleAt(r, c, cell)
                const v = cell ? ed.valueOf(sh, r, c, cell) : null
                const cfr = cf && cf.length ? ed.cfResult(cf, r, c, v) : null
                if (!cell && !st && !cfr) continue
                info.set(r * 16384 + c, { cell, st, v, cfr })
                const fill = cfr?.fill ?? st?.fill
                if (fill && !inMerge(r, c)) {
                    ctx.fillStyle = fill
                    const x = X(c)
                    ctx.fillRect(snap(x), snap(y), snap(x + g.colW(c)) - snap(x), snap(y + hh) - snap(y))
                }
            }
        }
        // 2. 选区底色
        drawSelectionTint(g, ctx, p, snap)
        // 3. 网格线
        if (showGrid) {
            ctx.fillStyle = GRID
            const top = Y(p.r0), bottom = Math.min(p.y + p.h, Y(p.r1) + g.rowH(p.r1))
            const left = X(p.c0), right = Math.min(p.x + p.w, X(p.c1) + g.colW(p.c1))
            for (const c of cols) ctx.fillRect(snap(X(c) + g.colW(c)) - px, top, px, bottom - top)
            for (const r of rows) ctx.fillRect(left, snap(Y(r) + g.rowH(r)) - px, right - left, px)
        }
        // 4. 数据条
        for (const [k, it] of info) {
            if (!it.cfr?.bar) continue
            const r = Math.floor(k / 16384), c = k % 16384
            const x = X(c), y = Y(r), w = g.colW(c), hh = g.rowH(r)
            const bw = Math.max(0, (w - 6) * it.cfr.bar.t)
            const grad = ctx.createLinearGradient(x + 2, 0, x + 2 + Math.max(bw, 1), 0)
            grad.addColorStop(0, it.cfr.bar.color)
            grad.addColorStop(1, it.cfr.bar.color + '55')
            ctx.fillStyle = grad
            ctx.fillRect(x + 3, y + 3, bw, hh - 6 - px)
        }
        // 5. 文本（含溢出到相邻空白单元格）
        const isBlank = (r, c) => {
            const cell = sh.get(r, c)
            if (cell && (cell.v != null || cell.f)) return false
            return !inMerge(r, c)
        }
        for (const r of rows) {
            const y = Y(r), hh = g.rowH(r)
            // 向左多扫描若干列，以绘制从左侧溢出进来的文本
            const scan0 = Math.max(p.sx ? fc : 0, p.c0 - 16)
            for (let c = scan0; c <= p.c1; c++) {
                if (c < p.c0 && g.cols.size(c) === 0) continue
                let it = info.get(r * 16384 + c)
                if (!it && c < p.c0) {
                    const cell = sh.get(r, c)
                    if (!cell || (cell.v == null && !cell.f)) continue
                    it = { cell, st: sh.styleAt(r, c, cell), v: ed.valueOf(sh, r, c, cell) }
                }
                if (!it || it.v == null || it.v === '') continue
                if (inMerge(r, c)) continue
                drawCellText(g, ctx, it, X(c), y, g.colW(c), hh, r, c, { X, isBlank, p, snap, px, sh })
            }
        }
        // 6. 合并单元格
        for (const m of merges) {
            const x = X(m.c1), y = Y(m.r1)
            const w = X(m.c2) + g.colW(m.c2) - x, hh = Y(m.r2) + g.rowH(m.r2) - y
            if (w <= 0 || hh <= 0) continue
            const cell = sh.get(m.r1, m.c1)
            const st = sh.styleAt(m.r1, m.c1, cell)
            const v = cell ? ed.valueOf(sh, m.r1, m.c1, cell) : null
            const cfr = cf?.length ? ed.cfResult(cf, m.r1, m.c1, v) : null
            ctx.fillStyle = cfr?.fill ?? st?.fill ?? '#ffffff'
            ctx.fillRect(snap(x), snap(y), snap(x + w) - snap(x) - (showGrid ? px : 0), snap(y + hh) - snap(y) - (showGrid ? px : 0))
            if (ed.inSelection(m.r1, m.c1) && !(ed.sel.r === m.r1 && ed.sel.c === m.c1)) {
                ctx.fillStyle = accent + '1f'
                ctx.fillRect(x, y, w, hh)
            }
            if (v != null && v !== '') drawCellText(g, ctx, { cell, st, v, cfr }, x, y, w, hh, m.r1, m.c1, { merged: true, snap, px, sh })
        }
        // 7. 边框
        for (const [k, it] of info) {
            const s = it.st
            if (!s || !(s.bt || s.br || s.bb || s.bl)) continue
            const r = Math.floor(k / 16384), c = k % 16384
            const m = inMerge(r, c)
            let x1 = X(c), y1 = Y(r), x2 = x1 + g.colW(c), y2 = y1 + g.rowH(r)
            if (m) { x1 = X(m.c1); y1 = Y(m.r1); x2 = X(m.c2) + g.colW(m.c2); y2 = Y(m.r2) + g.rowH(m.r2) }
            drawBorder(ctx, s.bt, x1, y1, x2, y1, snap, px, z)
            drawBorder(ctx, s.bb, x1, y2, x2, y2, snap, px, z)
            drawBorder(ctx, s.bl, x1, y1, x1, y2, snap, px, z)
            drawBorder(ctx, s.br, x2, y1, x2, y2, snap, px, z)
        }
        // 8. 筛选按钮
        const f = sh.meta.filter
        if (f && f.range.r1 >= p.r0 && f.range.r1 <= p.r1) {
            for (let c = Math.max(f.range.c1, p.c0); c <= Math.min(f.range.c2, p.c1); c++) {
                const x = X(c), y = Y(f.range.r1), w = g.colW(c), hh = g.rowH(f.range.r1)
                const s = Math.min(18 * z, hh - 4)
                const bx = x + w - s - 3, by = y + (hh - s) / 2
                const active = f.cols?.[c] != null
                ctx.fillStyle = active ? accent + '22' : '#ffffff'
                ctx.strokeStyle = active ? accent : '#b8bec8'
                ctx.lineWidth = px
                roundRect(ctx, snap(bx) + px / 2, snap(by) + px / 2, s, s, 3 * z)
                ctx.fill(); ctx.stroke()
                ctx.strokeStyle = active ? accent : '#4b5563'
                ctx.lineWidth = 1.4 * z
                ctx.beginPath()
                if (active) {
                    // 漏斗
                    ctx.moveTo(bx + s * .25, by + s * .3); ctx.lineTo(bx + s * .75, by + s * .3); ctx.lineTo(bx + s * .55, by + s * .55)
                    ctx.lineTo(bx + s * .55, by + s * .75); ctx.lineTo(bx + s * .45, by + s * .7); ctx.lineTo(bx + s * .45, by + s * .55); ctx.closePath()
                } else {
                    ctx.moveTo(bx + s * .3, by + s * .42); ctx.lineTo(bx + s * .5, by + s * .62); ctx.lineTo(bx + s * .7, by + s * .42)
                }
                ctx.stroke()
            }
        }
        // 9. 选区边框 / 引用高亮 / 复制虚线
        drawSelectionFrame(g, ctx, p, snap, px)
        ctx.restore()
    }

    // 冻结线
    ctx.fillStyle = '#9aa3af'
    if (fr) ctx.fillRect(0, snap(HH + fH) - px, W, px * Math.max(1, Math.round(dpr)))
    if (fc) ctx.fillRect(snap(HW + fW) - px, 0, px * Math.max(1, Math.round(dpr)), H)

    drawHeaders(g, ctx, panes, snap, px)
}

function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.roundRect ? ctx.roundRect(x, y, w, h, r) : ctx.rect(x, y, w, h)
}

function drawBorder(ctx, spec, x1, y1, x2, y2, snap, px, z) {
    const b = parseBorder(spec)
    if (!b) return
    ctx.strokeStyle = b.color
    ctx.lineWidth = b.style === 'double' ? Math.max(px, 1) : Math.max(px, borderWidth(b.style) * Math.min(Math.max(z, 1), 1.5))
    ctx.setLineDash(b.style === 'dashed' ? [4 * z, 2 * z] : b.style === 'dotted' ? [1.2 * z, 1.8 * z] : b.style === 'hair' ? [1, 1] : [])
    const vertical = x1 === x2
    const lw = ctx.lineWidth
    const off = -px / 2
    if (b.style === 'double') {
        for (const d of [-1.2, 1.2]) {
            ctx.beginPath()
            if (vertical) { const x = snap(x1 + d) + off; ctx.moveTo(x, y1 - 1); ctx.lineTo(x, y2 + 1) }
            else { const y = snap(y1 + d) + off; ctx.moveTo(x1 - 1, y); ctx.lineTo(x2 + 1, y) }
            ctx.stroke()
        }
    } else {
        ctx.beginPath()
        if (vertical) { const x = snap(x1) + off; ctx.moveTo(x, y1 - lw / 2); ctx.lineTo(x, y2 + lw / 2) }
        else { const y = snap(y1) + off; ctx.moveTo(x1 - lw / 2, y); ctx.lineTo(x2 + lw / 2, y) }
        ctx.stroke()
    }
    ctx.setLineDash([])
}

// 自动换行：返回行数组
export function wrapLines(g, font, text, maxW) {
    const out = []
    for (const para of String(text).split('\n')) {
        if (!para) { out.push(''); continue }
        let line = ''
        // 英文按单词，中日韩按字符断行
        const parts = para.match(/[　-鿿＀-￯]|[^\s　-鿿＀-￯]+|\s+/g) ?? [para]
        for (const part of parts) {
            const test = line + part
            if (g.measure(font, test) <= maxW || !line) {
                if (g.measure(font, test) > maxW && !line) {
                    // 单个超长单词：按字符切
                    let buf = ''
                    for (const ch of part) {
                        if (g.measure(font, buf + ch) > maxW && buf) { out.push(buf); buf = ch } else buf += ch
                    }
                    line = buf
                } else line = test
            } else {
                out.push(line.trimEnd())
                line = part.trimStart()
            }
        }
        out.push(line)
    }
    return out
}

function drawCellText(g, ctx, it, x, y, w, hh, r, c, o) {
    const z = g.z
    const s = it.st, cfr = it.cfr
    const fmt = s?.fmt
    let { text, color } = g.ed.showFormulas && it.cell?.f ? { text: '=' + it.cell.f } : display(it.v, fmt)
    if (text === '') return
    const eff = cfr && (cfr.b || cfr.i) ? { ...s, b: cfr.b ?? s?.b, i: cfr.i ?? s?.i } : s
    const font = fontString(eff, z)
    ctx.font = font
    const pad = 4 * z + (s?.indent ?? 0) * 9 * z
    const isNum = typeof it.v === 'number'
    let ha = s?.ha ?? defaultAlign(it.v)
    const va = s?.va ?? 'middle'
    const wrap = s?.wrap && !isNum
    const fsz = (s?.sz ?? 11) * 4 / 3 * z
    const lineH = fsz * 1.3
    let lines = [text]
    let tw = g.measure(font, text)
    let clipX1 = x, clipX2 = x + w
    if (wrap) {
        lines = wrapLines(g, font, text, Math.max(4, w - pad * 2))
    } else if (tw > w - pad * 2 + 0.5) {
        if (isNum) {
            // 数字放不下：常规格式减少小数位，否则显示 ###
            let t2 = null
            if (!fmt || fmt === 'General') {
                for (let p = 10; p >= 1 && t2 == null; p--) {
                    const cand = general(+it.v.toPrecision(p))
                    if (g.measure(font, cand) <= w - pad * 2) t2 = cand
                }
            }
            text = t2 ?? '#'.repeat(Math.max(1, Math.floor((w - pad) / g.measure(font, '#'))))
            tw = g.measure(font, text)
            lines = [text]
        } else if (!o.merged && o.isBlank && !text.includes('\n')) {
            // 文本溢出：向相邻空白单元格延伸
            const need = tw + pad * 2
            const maxC = o.p.c1 + 30
            if (ha === 'left' || ha === 'center') {
                let cc = c, right = x + w
                const extra = ha === 'center' ? (need - w) / 2 : need - w
                while (right - (x + w) < extra && cc < maxC && o.isBlank(r, cc + 1)) {
                    cc++
                    eraseGridLine(g, ctx, cc - 1, y, hh, o, r)
                    right += g.colW(cc)
                }
                clipX2 = right
            }
            if (ha === 'right' || ha === 'center') {
                let cc = c, left = x
                const extra = ha === 'center' ? (need - w) / 2 : need - w
                const minC = o.p.sx ? g.fc : 0
                while (x - left < extra && cc > minC && o.isBlank(r, cc - 1)) {
                    cc--
                    eraseGridLine(g, ctx, cc, y, hh, o, r)
                    left -= g.colW(cc)
                }
                clipX1 = left
            }
        }
    }
    ctx.save()
    ctx.beginPath()
    ctx.rect(clipX1, y, clipX2 - clipX1, hh)
    ctx.clip()
    ctx.fillStyle = cfr?.color ?? color ?? s?.color ?? '#1f2328'
    ctx.textBaseline = 'middle'
    const totalH = lines.length * lineH
    let ty = va === 'top' ? y + 2 * z + lineH / 2 : va === 'bottom' ? y + hh - 2 * z - totalH + lineH / 2 : y + hh / 2 - totalH / 2 + lineH / 2
    if (lines.length === 1 && va === 'middle') ty = y + hh / 2 + 0.5 * z
    for (const line of lines) {
        const lw = lines.length === 1 ? tw : g.measure(font, line)
        let tx = ha === 'right' ? x + w - pad - lw : ha === 'center' ? x + (w - lw) / 2 : x + pad
        ctx.fillText(line, tx, ty)
        if (s?.u || s?.st) {
            ctx.fillRect(tx, s.u ? ty + fsz * 0.45 : ty, lw, Math.max(1, z * 0.9))
            if (s.u && s.st) ctx.fillRect(tx, ty, lw, Math.max(1, z * 0.9))
        }
        ty += lineH
    }
    ctx.restore()
}

function eraseGridLine(g, ctx, c, y, hh, o, r) {
    if (!o.sh.meta.showGrid || g.ed.printMode) return
    const x = o.X(c) + g.colW(c)
    const st = o.sh.styleAt(r, c) ?? o.sh.styleAt(r, c + 1)
    ctx.fillStyle = st?.fill ?? '#ffffff'
    ctx.fillRect(o.snap(x) - o.px, o.snap(y), o.px, o.snap(y + hh) - o.snap(y) - o.px)
    if (g.ed.inSelection(r, c) && g.ed.inSelection(r, c + 1)) {
        ctx.fillStyle = g.ed.accent + '1f'
        ctx.fillRect(o.snap(x) - o.px, o.snap(y), o.px, o.snap(y + hh) - o.snap(y) - o.px)
    }
}

// 选区底色（活动单元格保持白色）
function drawSelectionTint(g, ctx, p, snap) {
    const ed = g.ed
    ctx.fillStyle = ed.accent + '1f'
    const a = ed.activeRect(p)
    for (const rg of ed.sel.ranges) {
        const R = paneRect(g, p, rg)
        if (!R) continue
        if (rg.r1 === rg.r2 && rg.c1 === rg.c2 && ed.sel.ranges.length === 1) continue
        const x1 = snap(R.x), y1 = snap(R.y), x2 = snap(R.x + R.w), y2 = snap(R.y + R.h)
        if (a && a.x >= R.x - 0.5 && a.x + a.w <= R.x + R.w + 0.5 && a.y >= R.y - 0.5 && a.y + a.h <= R.y + R.h + 0.5) {
            const ax1 = snap(a.x), ay1 = snap(a.y), ax2 = snap(a.x + a.w), ay2 = snap(a.y + a.h)
            ctx.fillRect(x1, y1, x2 - x1, ay1 - y1)
            ctx.fillRect(x1, ay2, x2 - x1, y2 - ay2)
            ctx.fillRect(x1, ay1, ax1 - x1, ay2 - ay1)
            ctx.fillRect(ax2, ay1, x2 - ax2, ay2 - ay1)
        } else ctx.fillRect(x1, y1, x2 - x1, y2 - y1)
    }
}

// 区域在某窗格中的矩形（与窗格不相交时返回 null）
export function paneRect(g, p, rg) {
    if (rg.r2 < p.r0 || rg.r1 > p.r1 || rg.c2 < p.c0 || rg.c1 > p.c1) {
        // 冻结窗格：区域可能跨越窗格边界
        const rOk = p.sy ? rg.r2 >= g.fr : rg.r1 < g.fr
        const cOk = p.sx ? rg.c2 >= g.fc : rg.c1 < g.fc
        if (!rOk || !cOk) return null
        if (rg.r2 < p.r0 && p.sy) return null
        if (rg.c2 < p.c0 && p.sx) return null
    }
    const r1 = p.sy ? Math.max(rg.r1, g.fr) : rg.r1, r2 = p.sy ? rg.r2 : Math.min(rg.r2, g.fr - 1)
    const c1 = p.sx ? Math.max(rg.c1, g.fc) : rg.c1, c2 = p.sx ? rg.c2 : Math.min(rg.c2, g.fc - 1)
    if (r1 > r2 || c1 > c2) return null
    const x = p.X(c1), y = p.Y(r1)
    // 避免对百万行区域逐项求和：直接用轴位置
    const x2 = p.X(Math.min(c2, 16383)) + g.colW(c2), y2 = p.Y(Math.min(r2, 1048575)) + g.rowH(r2)
    return { x, y, w: x2 - x, h: y2 - y, clipL: p.sx && rg.c1 < g.fc, clipT: p.sy && rg.r1 < g.fr, clipR: !p.sx && rg.c2 >= g.fc, clipB: !p.sy && rg.r2 >= g.fr }
}

function drawSelectionFrame(g, ctx, p, snap, px) {
    const ed = g.ed, z = g.z
    const accent = ed.accent
    // 公式引用高亮
    for (const hl of ed.refHighlights ?? []) {
        const R = paneRect(g, p, hl.range)
        if (!R) continue
        ctx.fillStyle = hl.color + '1a'
        ctx.fillRect(R.x, R.y, R.w, R.h)
        ctx.strokeStyle = hl.color
        ctx.lineWidth = Math.max(1.5, 1.5 * z)
        ctx.strokeRect(snap(R.x) + 0.5, snap(R.y) + 0.5, snap(R.w) - 2, snap(R.h) - 2)
        const s = 5 * z
        ctx.fillStyle = hl.color
        for (const [cx, cy] of [[R.x, R.y], [R.x + R.w, R.y], [R.x, R.y + R.h], [R.x + R.w, R.y + R.h]]) ctx.fillRect(cx - s / 2, cy - s / 2, s, s)
    }
    // 复制 / 剪切 的虚线框
    if (ed.clip?.range && ed.clip.sheetId === g.sheet.id) {
        const R = paneRect(g, p, ed.clip.range)
        if (R) {
            ctx.save()
            ctx.strokeStyle = accent
            ctx.lineWidth = 2
            ctx.setLineDash([5, 4])
            ctx.lineDashOffset = -(ed.antsPhase ?? 0)
            ctx.strokeRect(snap(R.x) + 1, snap(R.y) + 1, snap(R.w) - 2, snap(R.h) - 2)
            ctx.restore()
        }
    }
    // 拖动预览（移动 / 填充）
    for (const pv of [ed.dragPreview, ed.fillPreview]) {
        if (!pv) continue
        const R = paneRect(g, p, pv)
        if (!R) continue
        ctx.save()
        ctx.strokeStyle = '#6b7280'
        ctx.lineWidth = 1.5
        ctx.setLineDash([4, 3])
        ctx.strokeRect(snap(R.x) + 1, snap(R.y) + 1, snap(R.w) - 2, snap(R.h) - 2)
        ctx.restore()
    }
    // 选区边框
    const sel = ed.sel
    const lw = Math.max(2, Math.round(2 * Math.min(z, 1.5)))
    ctx.strokeStyle = accent
    ctx.lineWidth = lw
    sel.ranges.forEach((rg, i) => {
        const R = paneRect(g, p, rg)
        if (!R) return
        if (sel.ranges.length > 1) {
            ctx.lineWidth = 1
            ctx.strokeRect(snap(R.x) + 0.5, snap(R.y) + 0.5, snap(R.w) - 1, snap(R.h) - 1)
            ctx.lineWidth = lw
            if (i !== sel.ranges.length - 1) return
        } else ctx.strokeRect(snap(R.x) + lw / 2 - px, snap(R.y) + lw / 2 - px, snap(R.w) - lw + px, snap(R.h) - lw + px)
        // 填充柄
        if (i === sel.ranges.length - 1 && !ed.editing && !R.clipR && !R.clipB) {
            const s = Math.max(6, 6 * Math.min(z, 1.4))
            const hx = snap(R.x + R.w) - s / 2 - px, hy = snap(R.y + R.h) - s / 2 - px
            ctx.fillStyle = '#ffffff'
            ctx.fillRect(hx - 1, hy - 1, s + 2, s + 2)
            ctx.fillStyle = accent
            ctx.fillRect(hx, hy, s, s)
        }
    })
    // 多区域时活动单元格单独描边
    if (sel.ranges.length > 1) {
        const a = ed.activeRect(p)
        if (a) { ctx.lineWidth = lw; ctx.strokeRect(snap(a.x) + 1, snap(a.y) + 1, snap(a.w) - 2, snap(a.h) - 2) }
    }
    // 数据验证下拉按钮
    const dv = ed.validationAt(sel.r, sel.c)
    if (dv?.type === 'list' && p.r0 <= sel.r && sel.r <= p.r1 && p.c0 <= sel.c && sel.c <= p.c1) {
        const a = ed.activeRect(p)
        if (a) {
            const s = Math.min(20 * z, a.h)
            const b = { x: a.x + a.w + 1, y: a.y + a.h - s, w: s, h: s }
            g.dvButton = b
            ctx.fillStyle = '#f3f4f6'; ctx.strokeStyle = '#9ca3af'; ctx.lineWidth = 1
            ctx.fillRect(b.x, b.y, b.w, b.h); ctx.strokeRect(snap(b.x) + 0.5, snap(b.y) + 0.5, b.w - 1, b.h - 1)
            ctx.strokeStyle = '#374151'; ctx.lineWidth = 1.4
            ctx.beginPath(); ctx.moveTo(b.x + s * .3, b.y + s * .42); ctx.lineTo(b.x + s * .5, b.y + s * .62); ctx.lineTo(b.x + s * .7, b.y + s * .42); ctx.stroke()
        }
    } else if (p.sx && p.sy) g.dvButton = null
}

function drawHeaders(g, ctx, panes, snap, px) {
    const { W, H, HW, HH, z } = g
    const ed = g.ed, accent = ed.accent
    const sel = ed.sel
    ctx.font = `${(12 * z).toFixed(2)}px ${UI_FONT}`
    ctx.textBaseline = 'middle'
    ctx.textAlign = 'center'
    const colSel = c => sel.ranges.some(rg => c >= rg.c1 && c <= rg.c2)
    const rowSel = r => sel.ranges.some(rg => r >= rg.r1 && r <= rg.r2)
    const fullCol = c => sel.ranges.some(rg => c >= rg.c1 && c <= rg.c2 && rg.r1 === 0 && rg.r2 >= 1048575)
    const fullRow = r => sel.ranges.some(rg => r >= rg.r1 && r <= rg.r2 && rg.c1 === 0 && rg.c2 >= 16383)
    // 列标题
    ctx.fillStyle = HEAD_BG
    ctx.fillRect(0, 0, W, HH)
    for (const p of panes.filter(p => p.y === HH || (!g.fr))) {
        if (p.w <= 0) continue
        ctx.save(); ctx.beginPath(); ctx.rect(p.x, 0, p.w, HH); ctx.clip()
        for (let c = p.c0; c <= p.c1; c++) {
            const w = g.colW(c)
            if (w <= 0) continue
            const x = p.X(c)
            const on = colSel(c), full = fullCol(c)
            if (on) {
                ctx.fillStyle = full ? accent + '40' : accent + '1c'
                ctx.fillRect(x, 0, w, HH)
                ctx.fillStyle = accent
                ctx.fillRect(x, HH - 2, w, 2)
            }
            ctx.fillStyle = HEAD_LINE
            ctx.fillRect(snap(x + w) - px, 0, px, HH)
            if (w > 8) {
                ctx.fillStyle = on ? accent : HEAD_TEXT
                ctx.fillText(colName(c), x + w / 2, HH / 2 + 0.5)
            }
        }
        ctx.restore()
    }
    // 行标题
    ctx.fillStyle = HEAD_BG
    ctx.fillRect(0, HH, HW, H - HH)
    for (const p of panes.filter(p => p.x === HW || (!g.fc))) {
        if (p.h <= 0) continue
        ctx.save(); ctx.beginPath(); ctx.rect(0, p.y, HW, p.h); ctx.clip()
        for (let r = p.r0; r <= p.r1; r++) {
            const hh = g.rowH(r)
            if (hh <= 0) continue
            const y = p.Y(r)
            const on = rowSel(r), full = fullRow(r)
            if (on) {
                ctx.fillStyle = full ? accent + '40' : accent + '1c'
                ctx.fillRect(0, y, HW, hh)
                ctx.fillStyle = accent
                ctx.fillRect(HW - 2, y, 2, hh)
            }
            ctx.fillStyle = HEAD_LINE
            ctx.fillRect(0, snap(y + hh) - px, HW, px)
            if (hh > 8) {
                ctx.fillStyle = on ? accent : HEAD_TEXT
                ctx.fillText(String(r + 1), HW / 2, y + hh / 2 + 0.5)
            }
        }
        ctx.restore()
    }
    ctx.textAlign = 'left'
    // 标题分隔线与左上角
    ctx.fillStyle = HEAD_LINE
    ctx.fillRect(0, snap(HH) - px, W, px)
    ctx.fillRect(snap(HW) - px, 0, px, H)
    ctx.fillStyle = HEAD_BG
    ctx.fillRect(0, 0, HW - px, HH - px)
    ctx.fillStyle = '#b3b9c3'
    ctx.beginPath()
    ctx.moveTo(HW - 4 * z, HH - 4 * z - 10 * z); ctx.lineTo(HW - 4 * z, HH - 4 * z); ctx.lineTo(HW - 4 * z - 10 * z, HH - 4 * z)
    ctx.closePath(); ctx.fill()
}
