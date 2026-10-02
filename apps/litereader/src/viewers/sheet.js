import * as XLSX from 'xlsx'
import { Viewer } from './base.js'
import { h, btn, clamp, debounce } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { decodeText } from '../core/encoding.js'

const ROW_H = 30
const HEAD_H = 30
const IDX_W = 56

// 表格查看器：虚拟滚动，可流畅浏览数十万行
export class SheetViewer extends Viewer {
    zoomLevel = 1

    async mount() {
        this.addTitle()
        this.searchInput = h('input.input.small', { type: 'search', placeholder: '查找单元格…' })
        this.searchInput.addEventListener('keydown', e => { if (e.key === 'Enter') this.find(this.searchInput.value, e.shiftKey ? -1 : 1) })
        this.center.append(h('div.search-box.compact', icon('search', 15), this.searchInput))
        this.cellInfo = h('span.cell-info', '')
        this.right.append(this.cellInfo)
        this.tool('zoom-out', '缩小', () => this.setZoom(this.zoomLevel / 1.1))
        this.tool('zoom-in', '放大', () => this.setZoom(this.zoomLevel * 1.1))
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在解析表格…')
        try {
            const buf = new Uint8Array(await this.source.arrayBuffer())
            await new Promise(r => setTimeout(r, 30))
            if (['csv', 'tsv'].includes(this.source.ext)) {
                const { text } = decodeText(buf)
                this.wb = XLSX.read(text, { type: 'string', FS: this.source.ext === 'tsv' ? '\t' : undefined, dense: true })
            } else {
                this.wb = XLSX.read(buf, { type: 'array', dense: true, cellDates: true, cellStyles: false })
            }
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()

        this.grid = h('div.sheet-grid')
        this.canvasWrap = h('div.sheet-scroll', this.spacer = h('div.sheet-spacer'), this.grid)
        this.tabsBar = h('div.sheet-tabs')
        this.content.append(h('div.sheet-root', this.canvasWrap, this.tabsBar))
        this.listen(this.canvasWrap, 'scroll', () => this.paint(), { passive: true })
        const ro = new ResizeObserver(debounce(() => this.paint(), 50))
        ro.observe(this.canvasWrap)
        this.onDispose(() => ro.disconnect())

        this.wb.SheetNames.forEach((name, i) => {
            this.tabsBar.append(h('button.sheet-tab', { onclick: () => this.selectSheet(i) }, icon('table', 14), name))
        })
        this.setSubtitle(`表格 · ${this.wb.SheetNames.length} 个工作表`)
        this.selectSheet(0)
    }

    selectSheet(i) {
        this.sheetIndex = i
        ;[...this.tabsBar.children].forEach((b, j) => b.classList.toggle('active', j === i))
        const ws = this.wb.Sheets[this.wb.SheetNames[i]]
        const ref = ws['!ref'] ? XLSX.utils.decode_range(ws['!ref']) : { s: { r: 0, c: 0 }, e: { r: 0, c: 0 } }
        this.ws = ws
        this.rows = ref.e.r + 1
        this.cols = Math.max(ref.e.c + 1, 1)
        this.data = ws['!data'] ?? []
        this.merges = ws['!merges'] ?? []
        // 列宽：优先使用文件中的列宽，否则根据前 200 行内容估算
        const colsInfo = ws['!cols'] ?? []
        this.colW = []
        for (let c = 0; c < this.cols; c++) {
            let w = colsInfo[c]?.wpx ?? (colsInfo[c]?.wch ? colsInfo[c].wch * 8 : 0)
            if (!w) {
                let max = 4
                for (let r = 0; r < Math.min(this.rows, 200); r++) {
                    const v = this.text(r, c)
                    if (v) max = Math.max(max, [...v].reduce((n, ch) => n + (ch.charCodeAt(0) > 255 ? 2 : 1), 0))
                }
                w = clamp(max * 7.5 + 18, 60, 360)
            }
            if (colsInfo[c]?.hidden) w = 0
            this.colW.push(w)
        }
        this.colX = [0]
        for (const w of this.colW) this.colX.push(this.colX.at(-1) + w)
        this.selected = null
        this.cellInfo.textContent = `${this.rows.toLocaleString()} 行 × ${this.cols} 列`
        this.canvasWrap.scrollTo(0, 0)
        this.layout()
    }

    text(r, c) {
        const cell = this.data[r]?.[c]
        if (!cell) return ''
        if (cell.w != null) return cell.w
        if (cell.v instanceof Date) return cell.v.toLocaleString('zh-CN')
        return cell.v == null ? '' : String(cell.v)
    }

    setZoom(z) {
        this.zoomLevel = clamp(z, 0.5, 2.5)
        this.layout()
    }

    layout() {
        const z = this.zoomLevel
        this.spacer.style.width = (IDX_W + this.colX.at(-1)) * z + 'px'
        this.spacer.style.height = (HEAD_H + this.rows * ROW_H) * z + 'px'
        this.grid.style.setProperty('--z', z)
        this.paint()
    }

    paint() {
        if (!this.ws) return
        const z = this.zoomLevel
        const sc = this.canvasWrap
        const top = sc.scrollTop / z, left = sc.scrollLeft / z
        const vw = sc.clientWidth / z, vh = sc.clientHeight / z
        const r0 = Math.max(0, Math.floor(top / ROW_H) - 2)
        const r1 = Math.min(this.rows, Math.ceil((top + vh) / ROW_H) + 2)
        let c0 = 0
        while (c0 < this.cols - 1 && this.colX[c0 + 1] < left) c0++
        let c1 = c0
        while (c1 < this.cols && this.colX[c1] < left + vw) c1++

        const frag = document.createDocumentFragment()
        const sx = sc.scrollLeft, sy = sc.scrollTop
        const cell = (cls, x, y, w, hh, text, extra) => {
            const d = document.createElement('div')
            d.className = cls
            d.style.cssText = `transform:translate(${x * z}px,${y * z}px);width:${w * z}px;height:${hh * z}px`
            if (text) d.textContent = text
            if (extra) extra(d)
            frag.append(d)
            return d
        }
        // 数据单元格
        for (let r = r0; r < r1; r++) {
            const y = HEAD_H + r * ROW_H - top + sy / z
            for (let c = c0; c < c1; c++) {
                if (!this.colW[c]) continue
                const x = IDX_W + this.colX[c] - left + sx / z
                const raw = this.data[r]?.[c]
                const t = this.text(r, c)
                cell('sc' + (raw?.t === 'n' ? ' num' : '') + (this.selected?.r === r && this.selected?.c === c ? ' sel' : ''),
                    x, y, this.colW[c], ROW_H, t, d => { d.dataset.r = r; d.dataset.c = c; if (t.length > 20) d.title = t })
            }
            cell('sc idx', sx / z, y, IDX_W, ROW_H, String(r + 1))
        }
        // 列标题
        for (let c = c0; c < c1; c++) {
            if (!this.colW[c]) continue
            cell('sc head', IDX_W + this.colX[c] - left + sx / z, sy / z, this.colW[c], HEAD_H, XLSX.utils.encode_col(c))
        }
        cell('sc corner', sx / z, sy / z, IDX_W, HEAD_H, '')
        this.grid.replaceChildren(frag)
    }

    // 点击单元格显示内容
    onGridClick = e => {
        const d = e.target.closest('.sc[data-r]')
        if (!d) return
        this.selected = { r: Number(d.dataset.r), c: Number(d.dataset.c) }
        const addr = XLSX.utils.encode_cell(this.selected)
        const raw = this.data[this.selected.r]?.[this.selected.c]
        this.cellInfo.textContent = `${addr}  ${raw?.f ? '=' + raw.f : this.text(this.selected.r, this.selected.c)}`.slice(0, 120)
        this.paint()
    }

    find(q, dir = 1) {
        q = q.trim().toLowerCase()
        if (!q) return
        const start = this.selected ? this.selected.r * this.cols + this.selected.c + dir : 0
        const total = this.rows * this.cols
        for (let k = 0; k < total; k++) {
            const idx = ((start + k * dir) % total + total) % total
            const r = Math.floor(idx / this.cols), c = idx % this.cols
            if (this.text(r, c).toLowerCase().includes(q)) {
                this.selected = { r, c }
                const z = this.zoomLevel
                this.canvasWrap.scrollTo({
                    top: Math.max(0, (r * ROW_H - this.canvasWrap.clientHeight / z / 2) * z),
                    left: Math.max(0, (this.colX[c] - 40) * z),
                })
                this.cellInfo.textContent = `${XLSX.utils.encode_cell({ r, c })}  ${this.text(r, c)}`.slice(0, 120)
                this.paint()
                return
            }
        }
        this.cellInfo.textContent = '未找到'
    }

    onShow() {
        if (this.grid && !this.gridBound) {
            this.gridBound = true
            this.listen(this.grid, 'click', this.onGridClick)
        }
    }

    onKey(e) {
        if (!this.ws) return false
        if (e.ctrlKey && e.key.toLowerCase() === 'f') { this.searchInput.focus(); return true }
        if (e.ctrlKey && (e.key === '=' || e.key === '+')) { this.setZoom(this.zoomLevel * 1.1); return true }
        if (e.ctrlKey && e.key === '-') { this.setZoom(this.zoomLevel / 1.1); return true }
        if (e.key === 'PageDown' && e.ctrlKey) { this.selectSheet((this.sheetIndex + 1) % this.wb.SheetNames.length); return true }
        if (e.key === 'PageUp' && e.ctrlKey) { this.selectSheet((this.sheetIndex - 1 + this.wb.SheetNames.length) % this.wb.SheetNames.length); return true }
        return false
    }
}

export { btn }
