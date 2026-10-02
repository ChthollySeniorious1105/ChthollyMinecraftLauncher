// 图表：浮动在表格上方，数据来自单元格区域，随数据实时更新
// 图表对象：{ id, kind, title, sheet, range, x, y, w, h, legend, byRow, colors }
//   kind: bar 柱形 / hbar 条形 / line 折线 / area 面积 / pie 饼图 / doughnut 圆环 / scatter 散点
//   x / y 为工作表坐标（未缩放像素，相对于 A1 左上角）
import { h, toast, formDialog } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import { rangeName, parseRange } from './addr.js'
import { display } from './format.js'
import { isErr } from './formula/values.js'

export const CHART_KINDS = [['bar', '柱形图'], ['hbar', '条形图'], ['line', '折线图'], ['area', '面积图'], ['pie', '饼图'], ['doughnut', '圆环图'], ['scatter', '散点图']]
export const PALETTE = ['#4472c4', '#ed7d31', '#a5a5a5', '#ffc000', '#5b9bd5', '#70ad47', '#264478', '#9e480e', '#636363', '#997300']
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
const r1 = v => Math.round(v * 10) / 10

// 从区域读取数据：首行 / 首列为标题（自动识别）
export function chartData(ed, ch) {
    const sh = ed.book.sheets.find(s => s.name === ch.sheet) ?? ed.sheet
    const g = ch.range
    const val = (r, c) => { const v = ed.valueOf(sh, r, c); return isErr(v) ? null : v }
    const txt = (r, c) => { const cell = sh.get(r, c); const v = val(r, c); return v == null ? '' : display(v, sh.styleAt(r, c, cell)?.fmt).text }
    // 标签与数值分别来自两个区域（不相邻的选择）：range 为数值，labelsRange 为分类标签；
    // 或 range 为标题行、valuesRange 为数值行
    if (ch.labelsRange || ch.valuesRange) {
        const lab = ch.labelsRange ?? g, vals = ch.valuesRange ?? g
        const cells = rg => { const out = []; for (let r = rg.r1; r <= rg.r2; r++) for (let c = rg.c1; c <= rg.c2; c++) out.push([r, c]); return out }
        const num = v => typeof v === 'number' ? v : null
        return {
            labels: cells(lab).map(([r, c]) => txt(r, c)),
            series: [{ name: ch.title || '数值', values: cells(vals).map(([r, c]) => num(val(r, c))) }],
        }
    }
    const R = g.r2 - g.r1 + 1, C = g.c2 - g.c1 + 1
    // 首行是否为标题：除首列外存在非数字文本
    let headRow = false, headCol = false
    for (let c = g.c1; c <= g.c2; c++) { const v = val(g.r1, c); if (v != null && typeof v !== 'number') { headRow = true; break } }
    for (let r = g.r1 + (headRow ? 1 : 0); r <= g.r2; r++) { const v = val(r, g.c1); if (v != null && typeof v !== 'number') { headCol = true; break } }
    if (R === 1 || C === 1) { if (R === 1) headRow = false; if (C === 1) headCol = false }
    const rows = [], cols = []
    // ch.rows：只使用区域中的指定行（例如收入 / 支出合计 / 结余）
    for (let r = g.r1 + (headRow ? 1 : 0); r <= g.r2; r++) if ((!ch.rows || ch.rows.includes(r)) && (!ed.grid.rows.isHidden(r) || sh !== ed.sheet)) rows.push(r)
    for (let c = g.c1 + (headCol ? 1 : 0); c <= g.c2; c++) cols.push(c)
    const byRow = ch.byRow ?? (cols.length > rows.length * 2 && rows.length <= 8)
    const num = v => typeof v === 'number' ? v : Number.isFinite(+v) && v !== '' && v != null ? +v : null
    if (!byRow) {
        return {
            labels: rows.map((r, i) => headCol ? txt(r, g.c1) : String(i + 1)),
            series: cols.map((c, i) => ({ name: headRow ? txt(g.r1, c) : `系列 ${i + 1}`, values: rows.map(r => num(val(r, c))) })),
        }
    }
    return {
        labels: cols.map((c, i) => headRow ? txt(g.r1, c) : String(i + 1)),
        series: rows.map((r, i) => ({ name: headCol ? txt(r, g.c1) : `系列 ${i + 1}`, values: cols.map(c => num(val(r, c))) })),
    }
}

function niceStep(raw) {
    const k = Math.pow(10, Math.floor(Math.log10(raw || 1)))
    for (const m of [1, 2, 2.5, 5, 10]) if (m * k >= raw) return m * k
    return 10 * k
}
function fmtNum(v) {
    const a = Math.abs(v)
    if (a >= 1e8) return +(v / 1e8).toFixed(1) + '亿'
    if (a >= 1e4) return +(v / 1e4).toFixed(1) + '万'
    return String(+v.toFixed(2))
}

// 生成 SVG（导出、打印、画布共用）
export function chartSVG(ed, ch, W, H) {
    const d = ch.data ?? chartData(ed, ch)
    const colors = ch.colors ?? PALETTE
    const out = []
    const font = 'font-family="Microsoft YaHei, Segoe UI, sans-serif"'
    const top = ch.title ? 40 : 14
    if (ch.title) out.push(`<text x="${W / 2}" y="26" text-anchor="middle" font-size="15" font-weight="700" fill="#1f2328" ${font}>${esc(ch.title)}</text>`)
    const series = d.series.filter(s => s.values.some(v => v != null))
    const legend = ch.legend !== false && (series.length > 1 || ch.kind === 'pie' || ch.kind === 'doughnut')
    if (ch.kind === 'pie' || ch.kind === 'doughnut') {
        const s = series[0] ?? { values: [] }
        const vals = s.values.map(v => Math.max(0, v ?? 0))
        const sum = vals.reduce((a, b) => a + b, 0) || 1
        const lw = legend ? Math.min(160, W * 0.35) : 0
        const cx = (W - lw) / 2, cy = top + (H - top) / 2, R = Math.max(10, Math.min((W - lw) / 2, (H - top) / 2) - 14)
        let a = -Math.PI / 2
        vals.forEach((v, i) => {
            const da = v / sum * Math.PI * 2
            const c = colors[i % colors.length]
            if (da >= Math.PI * 2 - 1e-6) out.push(`<circle cx="${cx}" cy="${cy}" r="${R}" fill="${c}"/>`)
            else if (da > 0) {
                const x1 = cx + R * Math.cos(a), y1 = cy + R * Math.sin(a), x2 = cx + R * Math.cos(a + da), y2 = cy + R * Math.sin(a + da)
                out.push(`<path d="M${r1(cx)} ${r1(cy)}L${r1(x1)} ${r1(y1)}A${r1(R)} ${r1(R)} 0 ${da > Math.PI ? 1 : 0} 1 ${r1(x2)} ${r1(y2)}Z" fill="${c}" stroke="#fff" stroke-width="1.5"/>`)
            }
            const mid = a + da / 2
            if (v / sum > 0.05) out.push(`<text x="${r1(cx + R * (ch.kind === 'doughnut' ? 0.78 : 0.62) * Math.cos(mid))}" y="${r1(cy + R * (ch.kind === 'doughnut' ? 0.78 : 0.62) * Math.sin(mid))}" text-anchor="middle" dominant-baseline="central" font-size="11" font-weight="700" fill="#fff" ${font}>${Math.round(v / sum * 100)}%</text>`)
            a += da
        })
        if (ch.kind === 'doughnut') out.push(`<circle cx="${cx}" cy="${cy}" r="${r1(R * 0.55)}" fill="#fff"/>`)
        if (legend) d.labels.forEach((l, i) => {
            const y = cy - d.labels.length * 10 + i * 20 + 6
            if (y > H - 6) return
            out.push(`<rect x="${W - lw + 6}" y="${y - 6}" width="11" height="11" rx="2" fill="${colors[i % colors.length]}"/><text x="${W - lw + 22}" y="${y}" dominant-baseline="central" font-size="11.5" fill="#475569" ${font}>${esc(String(l).slice(0, 14))}</text>`)
        })
    } else {
        const horiz = ch.kind === 'hbar'
        const all = series.flatMap(s => s.values.filter(v => v != null))
        let max = Math.max(0, ...all), min = Math.min(0, ...all)
        if (max === min) max = min + 1
        const step = niceStep((max - min) / 5)
        max = Math.ceil(max / step - 1e-9) * step
        min = Math.floor(min / step + 1e-9) * step
        const lblW = horiz ? Math.min(90, 8 + Math.max(...d.labels.map(l => String(l).length)) * 12) : 0
        const pl = horiz ? lblW : 12 + Math.max(...[min, max].map(v => fmtNum(v).length)) * 7, pr = 16, pt = top + 6, pb = (legend ? 44 : 26)
        const cw = Math.max(10, W - pl - pr), chh = Math.max(10, H - pt - pb)
        const n = Math.max(1, d.labels.length)
        const V = v => horiz ? pl + (v - min) / (max - min) * cw : pt + chh - (v - min) / (max - min) * chh
        // 网格线与刻度
        for (let v = min; v <= max + 1e-9; v += step) {
            const p = r1(V(v))
            if (horiz) out.push(`<line x1="${p}" x2="${p}" y1="${pt}" y2="${pt + chh}" stroke="${Math.abs(v) < 1e-12 ? '#94a3b8' : '#e5e7eb'}"/><text x="${p}" y="${pt + chh + 14}" text-anchor="middle" font-size="10.5" fill="#64748b" ${font}>${fmtNum(v)}</text>`)
            else out.push(`<line x1="${pl}" x2="${pl + cw}" y1="${p}" y2="${p}" stroke="${Math.abs(v) < 1e-12 ? '#94a3b8' : '#e5e7eb'}"/><text x="${pl - 6}" y="${p}" text-anchor="end" dominant-baseline="central" font-size="10.5" fill="#64748b" ${font}>${fmtNum(v)}</text>`)
        }
        const band = (horiz ? chh : cw) / n
        const every = Math.max(1, Math.ceil(n / Math.max(1, (horiz ? chh / 16 : cw / 42))))
        d.labels.forEach((l, i) => {
            if (i % every) return
            const p = r1((horiz ? pt : pl) + band * (i + 0.5))
            if (horiz) out.push(`<text x="${pl - 6}" y="${p}" text-anchor="end" dominant-baseline="central" font-size="11" fill="#475569" ${font}>${esc(String(l).slice(0, 8))}</text>`)
            else if (ch.kind !== 'scatter') out.push(`<text x="${p}" y="${pt + chh + 15}" text-anchor="middle" font-size="11" fill="#475569" ${font}>${esc(String(l).slice(0, 10))}</text>`)
        })
        if (ch.kind === 'bar' || ch.kind === 'hbar') {
            const gw = band * 0.72, sw = gw / Math.max(1, series.length)
            series.forEach((s, si) => s.values.forEach((v, i) => {
                if (v == null) return
                const b0 = V(0), b1 = V(v)
                const off = (horiz ? pt : pl) + band * i + (band - gw) / 2 + sw * si
                if (horiz) out.push(`<rect x="${r1(Math.min(b0, b1))}" y="${r1(off + 1)}" width="${r1(Math.max(1, Math.abs(b1 - b0)))}" height="${r1(Math.max(1, sw - 2))}" rx="2" fill="${colors[si % colors.length]}"/>`)
                else out.push(`<rect x="${r1(off + 1)}" y="${r1(Math.min(b0, b1))}" width="${r1(Math.max(1, sw - 2))}" height="${r1(Math.max(1, Math.abs(b1 - b0)))}" rx="2" fill="${colors[si % colors.length]}"/>`)
            }))
        } else if (ch.kind === 'scatter') {
            // 散点：第一个系列为 x，其余为 y
            const xs = series[0]?.values ?? []
            const xmin = Math.min(...xs.filter(v => v != null)), xmax = Math.max(...xs.filter(v => v != null))
            const X = v => pl + (xmax === xmin ? 0.5 : (v - xmin) / (xmax - xmin)) * cw
            for (let k = 0; k <= 4; k++) { const v = xmin + (xmax - xmin) * k / 4; out.push(`<text x="${r1(X(v))}" y="${pt + chh + 15}" text-anchor="middle" font-size="10.5" fill="#64748b" ${font}>${fmtNum(v)}</text>`) }
            series.slice(1).forEach((s, si) => s.values.forEach((v, i) => {
                if (v == null || xs[i] == null) return
                out.push(`<circle cx="${r1(X(xs[i]))}" cy="${r1(V(v))}" r="4" fill="${colors[si % colors.length]}" fill-opacity=".85"/>`)
            }))
        } else {
            series.forEach((s, si) => {
                const c = colors[si % colors.length]
                const pts = s.values.map((v, i) => v == null ? null : [pl + band * (i + 0.5), V(v)])
                const segs = []
                let cur = []
                for (const p of pts) { if (p) cur.push(p); else { if (cur.length) segs.push(cur); cur = [] } }
                if (cur.length) segs.push(cur)
                for (const seg of segs) {
                    if (ch.kind === 'area') out.push(`<path d="M${r1(seg[0][0])} ${r1(V(Math.max(min, 0)))}L${seg.map(p => `${r1(p[0])} ${r1(p[1])}`).join('L')}L${r1(seg.at(-1)[0])} ${r1(V(Math.max(min, 0)))}Z" fill="${c}" fill-opacity=".22"/>`)
                    out.push(`<polyline points="${seg.map(p => `${r1(p[0])},${r1(p[1])}`).join(' ')}" fill="none" stroke="${c}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>`)
                    if (seg.length <= 40) for (const p of seg) out.push(`<circle cx="${r1(p[0])}" cy="${r1(p[1])}" r="3" fill="#fff" stroke="${c}" stroke-width="2"/>`)
                }
            })
        }
        if (legend) {
            const list = ch.kind === 'scatter' ? series.slice(1) : series
            const widths = list.map(s => 24 + Math.min(12, String(s.name).length) * 12)
            let x = Math.max(8, (W - widths.reduce((a, b) => a + b, 0)) / 2)
            const y = H - 12
            list.forEach((s, si) => {
                out.push(`<rect x="${r1(x)}" y="${y - 5}" width="11" height="11" rx="2" fill="${colors[si % colors.length]}"/><text x="${r1(x + 15)}" y="${y + 1}" dominant-baseline="central" font-size="11.5" fill="#475569" ${font}>${esc(String(s.name).slice(0, 12))}</text>`)
                x += widths[si]
            })
        }
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><rect width="${W}" height="${H}" fill="#ffffff"/>${out.join('')}</svg>`
}

// ---------- 编辑器中的图表层 ----------
export const Charts = {
    renderCharts() {
        const layer = this.grid.chartLayer
        layer.replaceChildren()
        this.chartEls = new Map()
        for (const ch of this.sheet.meta.charts ?? []) {
            const box = h('div.sh-chart' + (this.selChart === ch.id ? '.selected' : ''), { dataset: { id: ch.id } },
                h('div.sh-chart-body'),
                ...['nw', 'ne', 'sw', 'se'].map(k => h('div.sh-chart-handle.' + k, { dataset: { h: k } })))
            box.addEventListener('pointerdown', e => this.chartDown(e, ch.id))
            box.addEventListener('dblclick', () => this.editChart(ch.id))
            box.addEventListener('contextmenu', e => { this.selectChart(ch.id); contextMenu(e, this.chartMenu(ch.id)) })
            layer.append(box)
            this.chartEls.set(ch.id, box)
        }
        this.updateCharts()
    },
    // 数据变化时重绘图表内容
    updateCharts() {
        if (!this.chartEls) return
        for (const ch of this.sheet.meta.charts ?? []) {
            const el = this.chartEls.get(ch.id)
            if (!el) continue
            const body = el.querySelector('.sh-chart-body')
            try { body.innerHTML = chartSVG(this, ch, ch.w, ch.h) } catch (e) { body.textContent = '图表数据无效'; console.warn(e) }
        }
        this.positionCharts()
    },
    positionCharts() {
        if (!this.chartEls) return
        const G = this.grid, z = this.zoom
        for (const ch of this.sheet.meta.charts ?? []) {
            const el = this.chartEls.get(ch.id)
            if (!el) continue
            // 图表位于可滚动区域：扣除冻结窗格与滚动量
            const x = G.HW + (ch.x - G.sx) * z, y = G.HH + (ch.y - G.sy) * z
            el.style.transform = `translate(${x}px, ${y}px) scale(${z})`
            el.style.width = ch.w + 'px'
            el.style.height = ch.h + 'px'
            el.style.clipPath = `inset(${Math.max(0, (G.HH + G.frozenH - y) / z)}px 0 0 ${Math.max(0, (G.HW + G.frozenW - x) / z)}px)`
        }
    },
    selectChart(id) {
        if (this.selChart === id) return
        this.selChart = id
        for (const [k, el] of this.chartEls ?? []) el.classList.toggle('selected', k === id)
        this.refreshUI?.()
    },
    chartById(id) { return (this.sheet.meta.charts ?? []).find(c => c.id === id) },
    updateChart(id, patch, label = '修改图表') {
        this.sheet.setMeta({ charts: this.sheet.meta.charts.map(c => c.id === id ? { ...c, ...patch } : c) })
        this.renderCharts()
        this.commit(label)
    },
    chartDown(e, id) {
        if (e.button !== 0) return
        e.stopPropagation()
        e.preventDefault()
        this.selectChart(id)
        const ch = this.chartById(id)
        const handle = e.target.closest('.sh-chart-handle')?.dataset.h
        const z = this.zoom
        const x0 = e.clientX, y0 = e.clientY
        const start = { x: ch.x, y: ch.y, w: ch.w, h: ch.h }
        const el = this.chartEls.get(id)
        let moved = false
        const move = ev => {
            const dx = (ev.clientX - x0) / z, dy = (ev.clientY - y0) / z
            if (!moved && Math.hypot(dx, dy) < 3) return
            moved = true
            let { x, y, w, h: hh } = start
            if (!handle) { x += dx; y += dy }
            else {
                if (handle.includes('e')) w += dx
                if (handle.includes('w')) { x += dx; w -= dx }
                if (handle.includes('s')) hh += dy
                if (handle.includes('n')) { y += dy; hh -= dy }
            }
            Object.assign(ch, { x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)), w: Math.max(160, Math.round(w)), h: Math.max(110, Math.round(hh)) })
            if (handle) el.querySelector('.sh-chart-body').innerHTML = chartSVG(this, ch, ch.w, ch.h)
            this.positionCharts()
        }
        const up = () => {
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            if (moved) this.updateChart(id, {}, handle ? '调整图表大小' : '移动图表')
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    },

    async insertChart(kind = 'bar') {
        let g = this.range
        if (g.r1 === g.r2 && g.c1 === g.c2) g = this.currentRegion(g.r1, g.c1)
        g = this.clampUsed(g)
        if (g.r2 < g.r1 || g.c2 < g.c1 || !this.sheet.bounds() || this.sheet.bounds().r2 < 0) return toast('请先选择包含数据的区域', 'warn')
        const G = this.grid
        const vis = G.visibleCols()
        // 放在已用区域右侧（不遮挡数据），但不超出当前可见范围太远
        const x = G.cols.pos(Math.max(g.c2 + 1, Math.min(this.sheet.bounds().c2 + 1, vis[1] - 4))) + 16
        const y = G.rows.pos(g.r1)
        const header = this.valueOf(this.sheet, g.r1, g.c1)
        const ch = {
            id: Math.random().toString(36).slice(2, 9), kind, sheet: this.sheet.name, range: g,
            title: typeof header === 'string' && g.r1 !== g.r2 ? '' : '', x, y, w: 480, h: 300, legend: true,
        }
        this.sheet.setMeta({ charts: [...(this.sheet.meta.charts ?? []), ch] })
        this.renderCharts()
        this.selectChart(ch.id)
        this.commit('插入图表')
    },
    deleteChart(id = this.selChart) {
        if (!id) return
        this.sheet.setMeta({ charts: this.sheet.meta.charts.filter(c => c.id !== id) })
        this.selChart = null
        this.renderCharts()
        this.commit('删除图表')
    },
    async editChart(id = this.selChart) {
        const ch = this.chartById(id)
        if (!ch) return
        const r = await formDialog({
            title: '图表设置', width: 440,
            fields: [
                { key: 'kind', label: '类型', type: 'select', value: ch.kind, options: CHART_KINDS },
                { key: 'title', label: '标题', value: ch.title ?? '' },
                { key: 'range', label: '数据区域', value: rangeName(ch.range) },
                { key: 'byRow', label: '系列产生在', type: 'select', value: ch.byRow == null ? 'auto' : ch.byRow ? 'row' : 'col', options: [['auto', '自动'], ['col', '列'], ['row', '行']] },
                { key: 'legend', label: '显示图例', type: 'check', value: ch.legend !== false },
            ],
            onChange: v => {
                const g = parseRange(v.range)
                const preview = { ...ch, kind: v.kind, title: v.title, legend: v.legend, byRow: v.byRow === 'auto' ? undefined : v.byRow === 'row', range: g ?? ch.range }
                const el = this.chartEls.get(id)?.querySelector('.sh-chart-body')
                if (el) el.innerHTML = chartSVG(this, preview, ch.w, ch.h)
            },
        })
        if (!r) { this.updateCharts(); return }
        const g = parseRange(r.range)
        if (!g) { toast('数据区域无效', 'error'); this.updateCharts(); return }
        this.updateChart(id, { kind: r.kind, title: r.title, legend: r.legend, byRow: r.byRow === 'auto' ? undefined : r.byRow === 'row', range: g }, '图表设置')
    },
    chartMenu(id) {
        return [
            { label: '图表设置…', icon: 'settings-2', run: () => this.editChart(id) },
            { label: '更改类型', icon: 'chart-column', submenu: CHART_KINDS.map(([k, l]) => ({ label: l, checked: () => this.chartById(id)?.kind === k, run: () => this.updateChart(id, { kind: k }, '更改图表类型') })) },
            { label: '选择数据区域', icon: 'scan', run: () => { const ch = this.chartById(id); this.selectRange(ch.range) } },
            { label: '复制为图片', icon: 'image', run: () => this.copyChartImage(id) },
            '-',
            { label: '删除图表', icon: 'trash-2', danger: true, key: 'Delete', run: () => this.deleteChart(id) },
        ]
    },
    async copyChartImage(id) {
        const ch = this.chartById(id)
        const svg = chartSVG(this, ch, ch.w, ch.h)
        const img = new Image()
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
        await img.decode()
        const c = document.createElement('canvas')
        c.width = ch.w * 2; c.height = ch.h * 2
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
        const blob = await new Promise(res => c.toBlob(res, 'image/png'))
        await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })])
        toast('图表已复制到剪贴板', 'success')
    },
}

export { icon }
