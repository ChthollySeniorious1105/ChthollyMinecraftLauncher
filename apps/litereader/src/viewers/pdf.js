import * as pdfjs from 'pdfjs-dist'
import 'pdfjs-dist/web/pdf_viewer.css'
import PdfWorker from 'pdfjs-dist/build/pdf.worker.min.mjs?worker&url'
import { Viewer, sidebarTabs } from './base.js'
import { h, btn, clamp, debounce, togglePopover, segmented, toggle, prompt, toast } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'

pdfjs.GlobalWorkerOptions.workerSrc = PdfWorker
const VENDOR = new URL('./vendor/pdfjs/', location.href).href

// PDF 查看器：虚拟化渲染（仅渲染可见页），支持文本选择、缩略图、目录、搜索、夜间反色
export class PdfViewer extends Viewer {
    scale = 1
    fitMode = 'width'
    rotation = 0
    spread = false
    pages = []
    renderQueue = new Set()

    async mount() {
        this.addTitle()
        this.left.prepend(btn('panel-left', '缩略图 / 目录', () => this.toggleSidebar()))

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

        this.tool('search', '查找 (Ctrl F)', () => { this.toggleSidebar(true); this.tabs.select('search') })
        this.tool('rotate-cw', '顺时针旋转', () => { this.rotation = (this.rotation + 90) % 360; this.relayout(true) })
        this.spreadBtn = this.tool('book-open', '双页模式', () => {
            this.spread = !this.spread
            this.spreadBtn.classList.toggle('active', this.spread)
            this.relayout(true)
        })
        this.invertBtn = this.tool('moon', '夜间反色', () => {
            store.set('pdfInvert', !store.get('pdfInvert'))
            this.applyInvert()
        })
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在打开 PDF…')
        try {
            const data = new Uint8Array(await this.source.arrayBuffer())
            const task = pdfjs.getDocument({
                data,
                cMapUrl: VENDOR + 'cmaps/',
                cMapPacked: true,
                standardFontDataUrl: VENDOR + 'standard_fonts/',
                wasmUrl: VENDOR + 'wasm/',
                iccUrl: VENDOR + 'iccs/',
                isEvalSupported: false,
            })
            task.onPassword = async (update, reason) => {
                const pwd = await prompt({ title: '此 PDF 已加密', message: reason === 2 ? '密码错误，请重试' : '请输入打开密码', type: 'password' })
                if (pwd == null) { task.destroy(); return }
                update(pwd)
            }
            task.onProgress = ({ loaded, total }) => total && ld.set(`正在打开 PDF… ${Math.round(loaded / total * 100)}%`)
            this.pdf = await task.promise
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.onDispose(() => this.pdf?.destroy())

        const n = this.pdf.numPages
        this.pageTotal.textContent = `/ ${n}`
        this.setSubtitle(`PDF · ${n} 页`)

        this.scroller = h('div.pdf-scroller')
        this.container = h('div.pdf-pages')
        this.scroller.append(this.container)
        this.content.append(this.scroller)
        this.applyInvert()

        const first = await this.pdf.getPage(1)
        const vp = first.getViewport({ scale: 1 })
        this.baseSize = { w: vp.width, h: vp.height }
        this.pageSizes = new Array(n).fill(null)
        this.pageSizes[0] = { w: vp.width, h: vp.height }

        for (let i = 1; i <= n; i++) {
            const el = h('div.pdf-page', { dataset: { page: i } }, h('div.pdf-page-num', String(i)))
            this.pages.push({ num: i, el, rendered: 0, task: null })
            this.container.append(el)
        }

        this.io = new IntersectionObserver(entries => {
            for (const en of entries) {
                const p = this.pages[en.target.dataset.page - 1]
                p.visible = en.isIntersecting
                if (en.isIntersecting) this.queueRender(p)
            }
        }, { root: this.scroller, rootMargin: '120% 0px' })
        this.pages.forEach(p => this.io.observe(p.el))
        this.onDispose(() => this.io.disconnect())

        this.listen(this.scroller, 'scroll', () => this.onScroll(), { passive: true })
        this.listen(this.scroller, 'wheel', e => {
            if (!e.ctrlKey) return
            e.preventDefault()
            this.zoom(this.scale * (e.deltaY < 0 ? 1.1 : 1 / 1.1), e)
        }, { passive: false })
        const ro = new ResizeObserver(debounce(() => { if (this.fitMode !== 'custom') this.relayout() }, 120))
        ro.observe(this.scroller)
        this.onDispose(() => ro.disconnect())

        this.buildSidebar()
        const saved = store.getProgress(this.source.key)
        if (saved?.scale) { this.scale = saved.scale; this.fitMode = saved.fit ?? 'width' }
        this.relayout()
        if (saved?.page > 1) requestAnimationFrame(() => this.goTo(saved.page, false))
        this.loadPageSizes()
    }

    // 后台读取所有页面尺寸，处理页面大小不一的文档
    async loadPageSizes() {
        let changed = false
        for (let i = 2; i <= this.pdf.numPages; i++) {
            if (this.destroyed) return
            try {
                const page = await this.pdf.getPage(i)
                const vp = page.getViewport({ scale: 1 })
                this.pageSizes[i - 1] = { w: vp.width, h: vp.height }
                if (Math.abs(vp.width - this.baseSize.w) > 1 || Math.abs(vp.height - this.baseSize.h) > 1) changed = true
            } catch { /* ignore */ }
            if (i % 50 === 0 && changed) { this.relayout(); changed = false }
        }
        if (changed) this.relayout()
    }

    sizeOf(i) {
        const s = this.pageSizes[i] ?? this.baseSize
        return this.rotation % 180 ? { w: s.h, h: s.w } : s
    }

    computeScale() {
        const w = this.scroller.clientWidth - 64
        const hh = this.scroller.clientHeight - 32
        const s = this.sizeOf(0)
        const perRow = this.spread ? 2 : 1
        if (this.fitMode === 'width') return clamp((w - (perRow - 1) * 16) / (s.w * perRow), 0.1, 8)
        if (this.fitMode === 'page') return clamp(Math.min((w - (perRow - 1) * 16) / (s.w * perRow), hh / s.h), 0.1, 8)
        return this.scale
    }

    relayout(force = false) {
        if (!this.pdf) return
        const anchor = this.current ?? 1
        const newScale = this.computeScale()
        const changed = force || Math.abs(newScale - this.scale) > 0.001 || !this.laidOut
        this.scale = newScale
        this.laidOut = true
        this.container.classList.toggle('spread', this.spread)
        for (const p of this.pages) {
            const s = this.sizeOf(p.num - 1)
            p.el.style.width = Math.floor(s.w * this.scale) + 'px'
            p.el.style.height = Math.floor(s.h * this.scale) + 'px'
            if (changed) {
                p.task?.cancel()
                p.rendered = 0
            }
        }
        this.zoomLabel.textContent = Math.round(this.scale * 100) + '%'
        if (changed) {
            this.goTo(anchor, false)
            for (const p of this.pages) if (p.visible) this.queueRender(p)
        }
        this.saveProgress()
    }

    zoom(scale, e) {
        const old = this.scale
        this.fitMode = 'custom'
        this.scale = clamp(scale, 0.1, 8)
        const sc = this.scroller
        const rect = sc.getBoundingClientRect()
        const ox = e ? e.clientX - rect.left : sc.clientWidth / 2
        const oy = e ? e.clientY - rect.top : sc.clientHeight / 2
        const fx = (sc.scrollLeft + ox) / old, fy = (sc.scrollTop + oy) / old
        for (const p of this.pages) {
            const s = this.sizeOf(p.num - 1)
            p.el.style.width = Math.floor(s.w * this.scale) + 'px'
            p.el.style.height = Math.floor(s.h * this.scale) + 'px'
        }
        sc.scrollLeft = fx * this.scale - ox
        sc.scrollTop = fy * this.scale - oy
        this.zoomLabel.textContent = Math.round(this.scale * 100) + '%'
        this.rerender()
    }

    rerender = debounce(() => {
        for (const p of this.pages) {
            p.task?.cancel()
            p.rendered = 0
            if (p.visible) this.queueRender(p)
        }
        this.saveProgress()
    }, 160)

    zoomMenu() {
        const set = mode => { this.fitMode = mode; this.relayout(true) }
        return h('div.menu',
            h('button.menu-item' + (this.fitMode === 'width' ? '.checked' : ''), { onclick: () => set('width') }, icon('move-horizontal', 16), h('span', '适合宽度')),
            h('button.menu-item' + (this.fitMode === 'page' ? '.checked' : ''), { onclick: () => set('page') }, icon('scan', 16), h('span', '适合页面')),
            h('div.menu-sep'),
            ...[0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4].map(z => h('button.menu-item', { onclick: () => this.zoom(z) }, h('span.menu-icon-space'), h('span', Math.round(z * 100) + '%'))))
    }

    queueRender(p) {
        const target = this.scale * (this.rotation + 1)
        if (p.rendered === target || p.pending) return
        p.pending = true
        requestAnimationFrame(() => { p.pending = false; this.renderPage(p) })
    }

    async renderPage(p) {
        if (this.destroyed || !p.visible && p.rendered) return
        const target = this.scale * (this.rotation + 1)
        if (p.rendered === target) return
        p.task?.cancel()
        const page = await this.pdf.getPage(p.num)
        const viewport = page.getViewport({ scale: this.scale, rotation: this.rotation })
        const dpr = Math.min(window.devicePixelRatio || 1, 3)
        const canvas = h('canvas.pdf-canvas')
        canvas.width = Math.floor(viewport.width * dpr)
        canvas.height = Math.floor(viewport.height * dpr)
        canvas.style.width = Math.floor(viewport.width) + 'px'
        canvas.style.height = Math.floor(viewport.height) + 'px'
        const task = page.render({
            canvas,
            viewport,
            transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : null,
        })
        p.task = task
        try {
            await task.promise
        } catch (e) {
            if (e?.name !== 'RenderingCancelledException') console.warn(e)
            return
        }
        if (p.task !== task) return
        p.rendered = target
        // 文本层：支持选择与复制
        const textLayer = h('div.textLayer')
        textLayer.style.setProperty('--total-scale-factor', this.scale)
        textLayer.style.setProperty('--scale-factor', this.scale)
        try {
            const tl = new pdfjs.TextLayer({
                textContentSource: page.streamTextContent({ includeMarkedContent: true }),
                container: textLayer,
                viewport,
            })
            await tl.render()
            if (this.searchQuery) this.highlightText(textLayer)
        } catch (e) { console.warn(e) }
        p.el.replaceChildren(canvas, textLayer, h('div.pdf-page-num', String(p.num)))
        // 远离视口的页面释放资源
        this.gcPages()
    }

    gcPages() {
        const cur = this.current ?? 1
        for (const p of this.pages) {
            if (p.rendered && Math.abs(p.num - cur) > 12 && !p.visible) {
                p.el.replaceChildren(h('div.pdf-page-num', String(p.num)))
                p.rendered = 0
            }
        }
    }

    onScroll() {
        const sc = this.scroller
        const mid = sc.scrollTop + sc.clientHeight * 0.35
        let cur = 1
        for (const p of this.pages) {
            if (p.el.offsetTop <= mid) cur = p.num
            else break
        }
        if (cur !== this.current) {
            this.current = cur
            this.pageInput.value = cur
            this.highlightThumb()
            this.saveProgress()
        }
    }

    goTo(n, smooth = true) {
        if (!this.pdf) return
        n = clamp(n, 1, this.pdf.numPages)
        const el = this.pages[n - 1].el
        this.scroller.scrollTo({ top: el.offsetTop - 16, behavior: smooth && store.get('animations') ? 'smooth' : 'instant' })
        this.current = n
        this.pageInput.value = n
        this.highlightThumb()
    }

    saveProgress = debounce(() => {
        if (!this.pdf) return
        store.setProgress(this.source.key, { page: this.current ?? 1, scale: this.scale, fit: this.fitMode })
        this.app.updateRecentProgress(this.source, (this.current ?? 1) / this.pdf.numPages)
    }, 500)

    applyInvert() {
        const on = store.get('pdfInvert')
        this.invertBtn.classList.toggle('active', on)
        this.content.classList.toggle('pdf-invert', on)
    }

    // ---------- 侧栏 ----------
    buildSidebar() {
        this.thumbs = h('div.pdf-thumbs')
        const outline = h('div.toc-panel')
        const search = this.buildSearch()
        this.tabs = sidebarTabs([
            { id: 'thumbs', label: '缩略图', icon: 'layout-grid', panel: this.thumbs, onshow: () => this.renderThumbs() },
            { id: 'outline', label: '目录', icon: 'list-tree', panel: outline },
            { id: 'search', label: '搜索', icon: 'search', panel: search, onshow: () => setTimeout(() => this.searchInput.focus(), 50) },
        ])
        this.sidebar.append(this.tabs.el)
        this.pdf.getOutline().then(items => {
            if (!items?.length) return outline.append(h('div.empty-mini', '此文档没有目录'))
            const build = (list, depth) => h('ol', list.map(it => h('li',
                h('a', {
                    style: { paddingInlineStart: `${depth * 16 + 12}px` },
                    onclick: async () => {
                        try {
                            const dest = typeof it.dest === 'string' ? await this.pdf.getDestination(it.dest) : it.dest
                            if (!dest) return
                            const idx = await this.pdf.getPageIndex(dest[0])
                            this.goTo(idx + 1)
                        } catch (e) { console.warn(e) }
                    },
                }, it.title),
                it.items?.length ? build(it.items, depth + 1) : null)))
            outline.append(build(items, 0))
        })
    }

    async renderThumbs() {
        if (this.thumbsBuilt) return this.highlightThumb()
        this.thumbsBuilt = true
        const io = new IntersectionObserver(entries => {
            for (const en of entries) {
                if (!en.isIntersecting) continue
                io.unobserve(en.target)
                const num = Number(en.target.dataset.page)
                this.pdf.getPage(num).then(page => {
                    const vp = page.getViewport({ scale: 1 })
                    const scale = 150 / vp.width
                    const viewport = page.getViewport({ scale })
                    const c = h('canvas')
                    c.width = viewport.width * 1.5
                    c.height = viewport.height * 1.5
                    page.render({ canvas: c, viewport, transform: [1.5, 0, 0, 1.5, 0, 0] }).promise
                        .then(() => en.target.querySelector('.thumb-img').replaceChildren(c)).catch(() => {})
                })
            }
        }, { root: this.sidebar.querySelector('.sb-body'), rootMargin: '300px 0px' })
        this.onDispose(() => io.disconnect())
        const ratio = this.baseSize.h / this.baseSize.w
        for (let i = 1; i <= this.pdf.numPages; i++) {
            const t = h('div.thumb', { dataset: { page: i }, onclick: () => this.goTo(i) },
                h('div.thumb-img', { style: { aspectRatio: `1 / ${ratio}` } }),
                h('div.thumb-num', String(i)))
            this.thumbs.append(t)
            io.observe(t)
        }
        this.highlightThumb()
    }

    highlightThumb() {
        if (!this.thumbsBuilt) return
        const prev = this.thumbs.querySelector('.thumb.active')
        prev?.classList.remove('active')
        const el = this.thumbs.children[(this.current ?? 1) - 1]
        el?.classList.add('active')
        if (this.sidebarOpen && this.tabs.active === 'thumbs') el?.scrollIntoView({ block: 'nearest' })
    }

    buildSearch() {
        this.searchInput = h('input.input', { type: 'search', placeholder: '搜索文档内容…' })
        this.searchResults = h('div.search-results')
        this.searchInput.addEventListener('keydown', e => { if (e.key === 'Enter') this.search(this.searchInput.value) })
        return h('div.search-panel', h('div.search-box', icon('search', 16), this.searchInput), this.searchResults)
    }

    async search(q) {
        q = q.trim()
        this.searchQuery = q
        this.searchResults.replaceChildren()
        document.querySelectorAll('.pdf-page mark.hl').forEach(m => m.replaceWith(m.textContent))
        if (!q) return
        const token = this.searchToken = Symbol()
        const status = h('div.search-status', '正在搜索…')
        this.searchResults.append(status)
        const lower = q.toLowerCase()
        let count = 0
        for (let i = 1; i <= this.pdf.numPages; i++) {
            if (token !== this.searchToken || this.destroyed) return
            const page = await this.pdf.getPage(i)
            const tc = await page.getTextContent()
            const text = tc.items.map(it => it.str + (it.hasEOL ? '\n' : '')).join('')
            const low = text.toLowerCase()
            let idx = low.indexOf(lower), hits = 0
            while (idx >= 0 && hits < 20) {
                count++, hits++
                const pre = text.slice(Math.max(0, idx - 24), idx).replace(/\s+/g, ' ')
                const post = text.slice(idx + q.length, idx + q.length + 36).replace(/\s+/g, ' ')
                const item = h('div.search-item', { onclick: () => this.goTo(i) },
                    h('span.search-page', `P${i}`), pre, h('mark', text.slice(idx, idx + q.length)), post)
                this.searchResults.append(item)
                idx = low.indexOf(lower, idx + q.length)
            }
            if (i % 10 === 0) status.textContent = `正在搜索… ${i}/${this.pdf.numPages}`
        }
        status.textContent = count ? `共找到 ${count} 处结果` : '没有找到匹配内容'
        for (const p of this.pages) if (p.rendered) this.highlightText(p.el.querySelector('.textLayer'))
        if (!count) toast('没有找到匹配内容', 'warn')
    }

    highlightText(layer) {
        if (!layer || !this.searchQuery) return
        const q = this.searchQuery.toLowerCase()
        for (const span of layer.querySelectorAll('span')) {
            if (span.children.length) continue
            const t = span.textContent
            const i = t.toLowerCase().indexOf(q)
            if (i < 0) continue
            span.replaceChildren(t.slice(0, i), h('mark.hl', t.slice(i, i + q.length)), t.slice(i + q.length))
        }
    }

    onKey(e) {
        if (!this.pdf) return false
        const k = e.key
        if (e.ctrlKey && (k === '=' || k === '+')) { this.zoom(this.scale * 1.15); return true }
        if (e.ctrlKey && k === '-') { this.zoom(this.scale / 1.15); return true }
        if (e.ctrlKey && k === '0') { this.fitMode = 'width'; this.relayout(true); return true }
        if (e.ctrlKey && k.toLowerCase() === 'f') { this.toggleSidebar(true); this.tabs.select('search'); return true }
        if (k === 'PageDown' || (k === 'ArrowRight' && !e.ctrlKey)) { this.goTo(this.current + 1); return true }
        if (k === 'PageUp' || (k === 'ArrowLeft' && !e.ctrlKey)) { this.goTo(this.current - 1); return true }
        if (k === 'Home') { this.goTo(1); return true }
        if (k === 'End') { this.goTo(this.pdf.numPages); return true }
        return false
    }

    destroy() {
        this.destroyed = true
        this.saveProgress()
        super.destroy()
    }
}

export { segmented, toggle }
