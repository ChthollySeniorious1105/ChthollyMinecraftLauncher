import { Viewer, sidebarTabs } from './base.js'
import { h, btn, clamp, debounce, togglePopover } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { decodeOfd, decodeXps } from '../core/formats.js'
import { DomFinder, findBar } from '../core/find.js'

const MM = 96 / 25.4

// 版式文档查看器：OFD / XPS / OXPS / DjVu
// 页面按需渲染（仅渲染可见页），支持缩放、缩略图、页码跳转、文字查找（OFD / XPS / 带文字层的 DjVu）
export class PagedViewer extends Viewer {
    scale = 1
    fit = 'width'
    current = 1
    pages = []

    async mount() {
        this.addTitle()
        this.left.prepend(btn('panel-left', '缩略图', () => this.toggleSidebar()))
        this.pageInput = h('input.page-input', { type: 'text', value: '1' })
        this.pageInput.addEventListener('keydown', e => {
            if (e.key === 'Enter') { this.goTo(parseInt(this.pageInput.value) || 1); this.pageInput.blur() }
        })
        this.pageTotal = h('span.page-total', '/ -')
        this.zoomLabel = h('button.zoom-label', { title: '缩放选项', onclick: e => togglePopover(e.currentTarget, () => this.zoomMenu(), { align: 'center' }) }, '100%')
        this.center.append(
            btn('chevron-up', '上一页', () => this.goTo(this.current - 1)),
            h('div.page-box', this.pageInput, this.pageTotal),
            btn('chevron-down', '下一页', () => this.goTo(this.current + 1)),
            h('span.v-sep'),
            btn('zoom-out', '缩小 (Ctrl -)', () => this.zoom(this.scale / 1.15)),
            this.zoomLabel,
            btn('zoom-in', '放大 (Ctrl +)', () => this.zoom(this.scale * 1.15)))
        this.tool('search', '查找 (Ctrl F)', () => this.openFind())
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在解析文档…')
        try {
            const buf = await this.source.arrayBuffer()
            const ext = this.source.ext
            if (ext === 'ofd') this.doc = await decodeOfd(buf)
            else if (ext === 'xps' || ext === 'oxps') this.doc = await decodeXps(buf)
            else this.doc = await decodeDjvu(buf)
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.onDispose(() => { this.doc.urls?.forEach(u => URL.revokeObjectURL(u)); this.doc.dispose?.() })
        const n = this.doc.pages.length
        if (!n) return this.error('文档中没有页面')
        this.setCaveats(this.doc.caveats)
        this.pageTotal.textContent = `/ ${n}`
        this.setSubtitle(`${{ ofd: 'OFD 版式文档', xps: 'XPS 文档', oxps: 'OpenXPS 文档' }[this.source.ext] ?? 'DjVu 文档'} · ${n} 页`)

        // 页面尺寸统一换算为 CSS px
        this.unit = this.doc.unit === 'mm' ? MM : 1
        this.scroller = h('div.pdf-scroller')
        this.container = h('div.pdf-pages')
        this.scroller.append(this.container)
        this.find = findBar(() => this.finder)
        this.content.append(this.scroller, this.find.el)
        this.doc.pages.forEach((p, i) => {
            const el = h('div.pdf-page.paged-page', { dataset: { page: i + 1 } }, h('div.pdf-page-num', String(i + 1)))
            this.pages.push({ num: i + 1, src: p, el, rendered: false })
            this.container.append(el)
        })
        this.io = new IntersectionObserver(entries => {
            for (const en of entries) if (en.isIntersecting) this.renderPage(this.pages[en.target.dataset.page - 1])
        }, { root: this.scroller, rootMargin: '120% 0px' })
        this.pages.forEach(p => this.io.observe(p.el))
        this.onDispose(() => this.io.disconnect())
        this.listen(this.scroller, 'scroll', () => this.onScroll(), { passive: true })
        this.listen(this.scroller, 'wheel', e => {
            if (!e.ctrlKey) return
            e.preventDefault()
            this.zoom(this.scale * (e.deltaY < 0 ? 1.1 : 1 / 1.1))
        }, { passive: false })
        const ro = new ResizeObserver(debounce(() => { if (this.fit !== 'custom') this.layout() }, 100))
        ro.observe(this.scroller)
        this.onDispose(() => ro.disconnect())
        this.buildSidebar()
        const saved = store.getProgress(this.source.key)
        this.layout()
        if (saved?.page > 1) requestAnimationFrame(() => this.goTo(saved.page, false))
    }

    pageSize(p) { return { w: p.src.w * this.unit, h: p.src.h * this.unit } }

    computeScale() {
        const s = this.pageSize(this.pages[0])
        const w = this.scroller.clientWidth - 64, hh = this.scroller.clientHeight - 32
        if (this.fit === 'width') return clamp(w / s.w, 0.1, 6)
        if (this.fit === 'page') return clamp(Math.min(w / s.w, hh / s.h), 0.1, 6)
        return this.scale
    }

    layout() {
        const anchor = this.current
        this.scale = this.computeScale()
        for (const p of this.pages) {
            const s = this.pageSize(p)
            p.el.style.width = Math.floor(s.w * this.scale) + 'px'
            p.el.style.height = Math.floor(s.h * this.scale) + 'px'
            const view = p.el.querySelector('.paged-view')
            if (view) view.style.transform = `scale(${this.scale})`
            // 位图页（DjVu）在放大后需要重新渲染
            if (p.bitmap && Math.abs(p.bitmapScale - this.scale) / this.scale > 0.3) { p.rendered = false; this.renderPage(p) }
        }
        this.zoomLabel.textContent = Math.round(this.scale * 100) + '%'
        this.goTo(anchor, false)
    }

    zoom(s) {
        this.fit = 'custom'
        this.scale = clamp(s, 0.1, 6)
        this.layout()
    }

    zoomMenu() {
        const set = mode => { this.fit = mode; this.layout() }
        return h('div.menu',
            h('button.menu-item' + (this.fit === 'width' ? '.checked' : ''), { onclick: () => set('width') }, icon('move-horizontal', 16), h('span', '适合宽度')),
            h('button.menu-item' + (this.fit === 'page' ? '.checked' : ''), { onclick: () => set('page') }, icon('scan', 16), h('span', '适合页面')),
            h('div.menu-sep'),
            ...[0.5, 0.75, 1, 1.5, 2, 3].map(z => h('button.menu-item', { onclick: () => this.zoom(z) }, h('span.menu-icon-space'), h('span', Math.round(z * 100) + '%'))))
    }

    async renderPage(p) {
        if (!p || p.rendered || p.loading) return
        p.loading = true
        try {
            const out = await p.src.render(this.scale)
            if (this.destroyed) return
            const s = this.pageSize(p)
            const view = h('div.paged-view', { style: { width: s.w + 'px', height: s.h + 'px', transform: `scale(${this.scale})` } })
            if (typeof out === 'string') {
                view.innerHTML = out
                const svg = view.querySelector('svg')
                if (svg) { svg.setAttribute('width', s.w); svg.setAttribute('height', s.h) }
            } else {
                // DjVu：位图 + 可选文字层
                view.append(out.canvas)
                out.canvas.style.width = s.w + 'px'
                out.canvas.style.height = s.h + 'px'
                if (out.text) view.append(out.text)
                p.bitmap = true
                p.bitmapScale = this.scale
            }
            p.el.querySelector('.paged-view')?.remove()
            p.el.prepend(view)
            p.rendered = true
            this.fillThumb(p)
            if (this.findQ) this.finder?.search(this.findQ)
        } catch (e) {
            console.error(e)
            p.el.append(h('div.pp-fail', icon('file-x', 26), `第 ${p.num} 页渲染失败：${e.message}`))
            p.rendered = true
        } finally {
            p.loading = false
        }
    }

    goTo(n, smooth = true) {
        n = clamp(n, 1, this.pages.length)
        this.current = n
        this.pages[n - 1].el.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto', block: 'start' })
        this.updateCurrent()
    }

    onScroll() {
        const mid = this.scroller.scrollTop + this.scroller.clientHeight / 3
        let n = 1
        for (const p of this.pages) { if (p.el.offsetTop <= mid) n = p.num; else break }
        if (n !== this.current) { this.current = n; this.updateCurrent() }
    }

    updateCurrent() {
        this.pageInput.value = String(this.current)
        this.thumbs?.querySelectorAll('.thumb').forEach(t => t.classList.toggle('active', Number(t.dataset.page) === this.current))
        this.saveProgress()
    }

    saveProgress = debounce(() => {
        store.setProgress(this.source.key, { page: this.current })
        this.app.updateRecentProgress(this.source, this.pages.length > 1 ? (this.current - 1) / (this.pages.length - 1) : 1)
    }, 400)

    buildSidebar() {
        this.thumbs = h('div.pdf-thumbs')
        const io = new IntersectionObserver(entries => {
            for (const en of entries) if (en.isIntersecting) this.renderPage(this.pages[en.target.dataset.page - 1])
        }, { root: this.sidebar, rootMargin: '200px 0px' })
        this.onDispose(() => io.disconnect())
        for (const p of this.pages) {
            const s = this.pageSize(p)
            const t = h('div.thumb', { dataset: { page: p.num }, onclick: () => this.goTo(p.num) },
                h('div.thumb-img', { style: { aspectRatio: `${s.w} / ${s.h}` } }), h('div.thumb-num', String(p.num)))
            this.thumbs.append(t)
            io.observe(t)
        }
        this.sidebar.append(sidebarTabs([{ id: 'thumbs', label: '缩略图', icon: 'layout-grid', panel: this.thumbs }]).el)
    }

    fillThumb(p) {
        const box = this.thumbs?.children[p.num - 1]?.querySelector('.thumb-img')
        const view = p.el.querySelector('.paged-view')
        if (!box || !view || box.firstChild) return
        const s = this.pageSize(p)
        const clone = view.cloneNode(true)
        clone.querySelectorAll('.paged-text').forEach(e => e.remove())
        // canvas 克隆后内容为空，复制像素
        const src = view.querySelector('canvas'), dst = clone.querySelector('canvas')
        if (src && dst) { dst.width = src.width; dst.height = src.height; dst.getContext('2d').drawImage(src, 0, 0) }
        clone.style.transform = `scale(${118 / s.w})`
        box.append(clone)
    }

    openFind() {
        this.finder ??= new DomFinder(this.container)
        this.find.open()
    }

    onKey(e) {
        if (!this.pages.length) return false
        const k = e.key
        if (e.ctrlKey && (k === '=' || k === '+')) { this.zoom(this.scale * 1.15); return true }
        if (e.ctrlKey && k === '-') { this.zoom(this.scale / 1.15); return true }
        if (e.ctrlKey && k === '0') { this.fit = 'width'; this.layout(); return true }
        if (e.ctrlKey && k.toLowerCase() === 'f') { this.openFind(); return true }
        if (k === 'PageDown' || k === 'ArrowRight') { this.goTo(this.current + 1); return true }
        if (k === 'PageUp' || k === 'ArrowLeft') { this.goTo(this.current - 1); return true }
        if (k === 'Home') { this.goTo(1); return true }
        if (k === 'End') { this.goTo(this.pages.length); return true }
        return false
    }

    destroy() {
        this.destroyed = true
        this.saveProgress()
        super.destroy()
    }
}

// ---------- DjVu（djvu-rs WASM 解码）----------
let djvuMod = null
async function decodeDjvu(buf) {
    djvuMod ??= import('djvu-rs').then(async m => { await m.default(); return m })
    const m = await djvuMod
    const doc = m.WasmDocument.from_bytes(new Uint8Array(buf))
    const count = doc.page_count()
    const pages = []
    let hasText = false
    for (let i = 0; i < count; i++) {
        const page = doc.page(i)
        // 以 96 DPI 作为 CSS 尺寸基准
        const w = page.width_at(96)
        const hgt = page.height_at(96)
        pages.push({
            w, h: hgt,
            async render(scale) {
                const target = Math.min(600, Math.round(96 * scale * (window.devicePixelRatio || 1)))
                const pw = page.width_at(target)
                const ph = page.height_at(target)
                const px = page.render(target)
                const canvas = document.createElement('canvas')
                canvas.width = pw
                canvas.height = ph
                canvas.getContext('2d').putImageData(new ImageData(px, pw, ph), 0, 0)
                // 文字层：透明文字叠加，用于选择与查找
                let text = null
                const zones = page.text_zones_json?.(96)
                if (zones) {
                    hasText = true
                    text = document.createElement('div')
                    text.className = 'paged-text'
                    for (const z of JSON.parse(zones)) {
                        const s = document.createElement('span')
                        s.textContent = z.t ?? z.text
                        Object.assign(s.style, { left: z.x + 'px', top: z.y + 'px', width: z.w + 'px', height: z.h + 'px', fontSize: z.h * 0.85 + 'px' })
                        text.append(s)
                    }
                }
                return { canvas, text }
            },
        })
    }
    const caveats = []
    const probe = count ? doc.page(0).text?.() : null
    if (!probe) caveats.push('此 DjVu 文件没有文字层，无法查找与复制文字')
    return { kind: 'pages', pages, caveats, unit: 'px', dispose: () => doc.free?.(), hasText }
}
