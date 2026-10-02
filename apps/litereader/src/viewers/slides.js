import { Viewer, sidebarTabs } from './base.js'
import { h, btn, clamp, debounce, togglePopover, segmented } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { Pptx } from '../core/pptx.js'
import { OutlineDeck } from '../core/formats.js'
import { DomFinder, findBar } from '../core/find.js'

const GAP = 24

// 演示文稿查看器：PPTX / PPSX / POTX
// 单页 / 连续滚动两种浏览模式，缩略图、大纲、备注、全文搜索、放映模式
export class SlidesViewer extends Viewer {
    current = 0
    mode = 'single'
    fit = 'page'
    zoomLevel = 1
    slides = []

    async mount() {
        this.addTitle()
        this.left.prepend(btn('panel-left', '缩略图 / 大纲', () => this.toggleSidebar()))

        this.pageInput = h('input.page-input', { type: 'text', value: '1' })
        this.pageInput.addEventListener('keydown', e => {
            if (e.key === 'Enter') { this.goTo((parseInt(this.pageInput.value) || 1) - 1); this.pageInput.blur() }
        })
        this.pageTotal = h('span.page-total', '/ -')
        this.zoomLabel = h('button.zoom-label', { title: '缩放选项', onclick: e => togglePopover(e.currentTarget, () => this.zoomMenu(), { align: 'center' }) }, '100%')
        this.center.append(
            btn('chevron-left', '上一张 (←)', () => this.goTo(this.current - 1)),
            h('div.page-box', this.pageInput, this.pageTotal),
            btn('chevron-right', '下一张 (→)', () => this.goTo(this.current + 1)),
            h('span.v-sep'),
            btn('zoom-out', '缩小 (Ctrl -)', () => this.setZoom(this.zoomLevel / 1.15)),
            this.zoomLabel,
            btn('zoom-in', '放大 (Ctrl +)', () => this.setZoom(this.zoomLevel * 1.15)))

        this.modeSeg = segmented([['single', '', 'rectangle-horizontal'], ['scroll', '', 'rows-3']], this.mode, v => this.setMode(v))
        this.modeSeg.el.title = '单页 / 连续滚动'
        this.right.append(this.modeSeg.el)
        this.tool('search', '查找 (Ctrl F)', () => this.openSearch())
        this.notesBtn = this.tool('sticky-note', '演讲者备注 (N)', () => this.toggleNotes())
        this.tool('monitor-play', '从当前页放映 (F5)', () => this.present())
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在解析演示文稿…')
        try {
            const buf = await this.source.arrayBuffer()
            this.pptx = ['ppt', 'pps', 'pot', 'odp', 'otp'].includes(this.source.ext)
                ? await OutlineDeck.open(buf, this.source.ext)
                : await Pptx.open(buf)
        } catch (e) {
            ld.done()
            return this.error(/zip|central directory|end of data/i.test(e.message) ? '文件已损坏或格式不受支持' : e)
        }
        ld.done()
        this.onDispose(() => this.pptx.dispose())

        const n = this.pptx.count
        if (!n) return this.error('演示文稿中没有幻灯片')
        this.pageTotal.textContent = `/ ${n}`
        const W = this.pptx.width, H = this.pptx.height
        this.setSubtitle(`演示文稿 · ${n} 张幻灯片 · ${W > H * 1.5 ? '16:9' : W > H * 1.2 ? '4:3' : '自定义比例'}`)

        this.scroller = h('div.pp-scroller')
        this.stage = h('div.pp-stage')
        this.scroller.append(this.stage)
        this.notesEl = h('div.pp-notes', { hidden: true })
        this.find = findBar(() => this.finder)
        this.content.append(this.scroller, this.notesEl, this.find.el)
        for (let i = 0; i < n; i++) {
            const frame = h('div.pp-frame', { dataset: { i } }, h('div.pp-num', String(i + 1)))
            this.slides.push({ i, frame, el: null, loading: null })
            this.stage.append(frame)
        }

        this.io = new IntersectionObserver(entries => {
            for (const en of entries) if (en.isIntersecting) this.ensure(Number(en.target.dataset.i))
        }, { root: this.scroller, rootMargin: '100% 0px' })
        this.slides.forEach(s => this.io.observe(s.frame))
        this.onDispose(() => this.io.disconnect())

        this.listen(this.scroller, 'scroll', () => this.onScroll(), { passive: true })
        this.listen(this.scroller, 'wheel', e => {
            if (e.ctrlKey) {
                e.preventDefault()
                this.setZoom(this.zoomLevel * (e.deltaY < 0 ? 1.1 : 1 / 1.1))
                return
            }
            // 单页模式：未出现滚动条时用滚轮翻页
            if (this.mode === 'single' && this.scroller.scrollHeight <= this.scroller.clientHeight + 2) {
                e.preventDefault()
                this.wheelFlip(e.deltaY)
            }
        }, { passive: false })
        this.listen(this.stage, 'click', e => {
            const a = e.target.closest('a.pp-link')
            if (a) { e.preventDefault(); window.lite.openExternal(a.href) }
        })
        const ro = new ResizeObserver(debounce(() => this.layout(), 60))
        ro.observe(this.scroller)
        this.onDispose(() => ro.disconnect())

        this.buildSidebar()
        const saved = store.getProgress(this.source.key)
        this.mode = saved?.mode ?? 'single'
        this.modeSeg.set(this.mode)
        this.current = clamp(saved?.slide ?? 0, 0, n - 1)
        this.layout()
        this.goTo(this.current, false)
        this.checkLossy()
    }

    // 渲染（懒加载）单张幻灯片
    ensure(i) {
        const s = this.slides[i]
        if (!s || s.el || s.loading) return s?.loading
        s.loading = this.pptx.renderSlide(i).then(({ el, hidden }) => {
            if (this.destroyed) return
            s.el = el
            s.hidden = hidden
            el.style.transform = `scale(${this.scale})`
            s.frame.classList.toggle('hidden-slide', hidden)
            s.frame.prepend(el)
            s.frame.classList.add('ready')
            this.fillThumb(i)
            this.checkLossy()
            if (this.searchQ) this.finder?.search(this.searchQ)
        }).catch(e => {
            console.error(e)
            s.frame.classList.add('failed')
            s.frame.append(h('div.pp-fail', icon('file-x', 28), `第 ${i + 1} 张幻灯片渲染失败：${e.message}`))
        })
        return s.loading
    }

    checkLossy() {
        if (this.pptx.lossy.size !== this.caveats?.length) this.setCaveats([...this.pptx.lossy])
    }

    get scale() {
        const W = this.pptx.width, H = this.pptx.height
        const cw = this.scroller.clientWidth - GAP * 2, ch = this.scroller.clientHeight - GAP * 2
        const fitW = cw / W
        const base = this.fit === 'width' || this.mode === 'scroll' ? fitW : Math.min(fitW, ch / H)
        return clamp(base * this.zoomLevel, 0.05, 6)
    }

    layout() {
        if (!this.pptx) return
        const sc = this.scale
        const W = Math.floor(this.pptx.width * sc), H = Math.floor(this.pptx.height * sc)
        this.stage.classList.toggle('single', this.mode === 'single')
        for (const s of this.slides) {
            s.frame.style.width = W + 'px'
            s.frame.style.height = H + 'px'
            if (s.el) s.el.style.transform = `scale(${sc})`
            s.frame.hidden = this.mode === 'single' && s.i !== this.current
        }
        this.zoomLabel.textContent = Math.round(sc * 100) + '%'
        if (this.mode === 'single') this.ensure(this.current)
    }

    setMode(m) {
        this.mode = m
        this.modeSeg.set(m)
        this.layout()
        this.goTo(this.current, false)
        this.saveProgress()
    }

    setZoom(z) {
        this.zoomLevel = clamp(z, 0.2, 5)
        const anchor = this.current
        this.layout()
        if (this.mode === 'scroll') this.goTo(anchor, false)
    }

    zoomMenu() {
        const set = (fit, z = 1) => { this.fit = fit; this.zoomLevel = z; this.layout(); this.goTo(this.current, false) }
        return h('div.menu',
            h('button.menu-item' + (this.fit === 'page' && this.zoomLevel === 1 ? '.checked' : ''), { onclick: () => set('page') }, icon('scan', 16), h('span', '适合页面')),
            h('button.menu-item' + (this.fit === 'width' && this.zoomLevel === 1 ? '.checked' : ''), { onclick: () => set('width') }, icon('move-horizontal', 16), h('span', '适合宽度')))
    }

    goTo(i, smooth = true) {
        if (!this.pptx) return
        i = clamp(i, 0, this.pptx.count - 1)
        const changed = i !== this.current
        this.current = i
        if (this.mode === 'single') {
            for (const s of this.slides) s.frame.hidden = s.i !== i
            this.scroller.scrollTop = 0
            this.ensure(i)
            // 预加载相邻页
            this.ensure(i + 1)
            if (changed) this.slides[i].frame.animate?.([{ opacity: 0.4 }, { opacity: 1 }], { duration: 180 })
        } else {
            this.slides[i].frame.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto', block: 'start' })
        }
        this.updateCurrent()
    }

    onScroll() {
        if (this.mode !== 'scroll' || !this.pptx) return
        const top = this.scroller.scrollTop + this.scroller.clientHeight / 3
        let i = 0
        for (const s of this.slides) { if (s.frame.offsetTop <= top) i = s.i; else break }
        if (i !== this.current) { this.current = i; this.updateCurrent() }
    }

    wheelFlip(dy) {
        const now = performance.now()
        if (Math.abs(dy) < 4 || now - (this.lastFlip ?? 0) < 260) return
        this.lastFlip = now
        this.goTo(this.current + (dy > 0 ? 1 : -1))
    }

    updateCurrent() {
        this.pageInput.value = String(this.current + 1)
        this.thumbs?.querySelectorAll('.pp-thumb').forEach(t => t.classList.toggle('active', Number(t.dataset.i) === this.current))
        this.thumbs?.querySelector('.pp-thumb.active')?.scrollIntoView({ block: 'nearest' })
        this.outline?.querySelectorAll('a').forEach(a => a.toggleAttribute('aria-current', Number(a.dataset.i) === this.current))
        if (!this.notesEl.hidden) this.renderNotes()
        this.app.updateRecentProgress(this.source, this.pptx.count > 1 ? this.current / (this.pptx.count - 1) : 1)
        this.saveProgress()
        if (this.presenter) this.presenter.show(this.current)
    }

    saveProgress = debounce(() => {
        store.setProgress(this.source.key, { slide: this.current, mode: this.mode })
    }, 400)

    // ---------- 侧栏 ----------
    buildSidebar() {
        this.thumbs = h('div.pp-thumbs')
        this.thumbIO = new IntersectionObserver(entries => {
            for (const en of entries) if (en.isIntersecting) this.ensure(Number(en.target.dataset.i))
        }, { root: this.sidebar, rootMargin: '200px 0px' })
        this.onDispose(() => this.thumbIO.disconnect())
        const ratio = this.pptx.height / this.pptx.width
        for (const s of this.slides) {
            const t = h('div.pp-thumb', { dataset: { i: s.i }, onclick: () => this.goTo(s.i) },
                h('div.pp-thumb-img', { style: { aspectRatio: `1 / ${ratio}` } }),
                h('div.pp-thumb-num', String(s.i + 1)))
            this.thumbs.append(t)
            this.thumbIO.observe(t)
        }

        this.outline = h('div.toc-panel.outline', h('div.empty-mini', '正在读取…'))
        this.buildOutline()

        this.searchInput = h('input.input', { type: 'search', placeholder: '搜索幻灯片文字…' })
        this.searchResults = h('div.search-results')
        this.searchInput.addEventListener('keydown', e => { if (e.key === 'Enter') this.search(this.searchInput.value) })
        const searchPanel = h('div.search-panel', h('div.search-box', icon('search', 16), this.searchInput), this.searchResults)

        const m = this.pptx.meta
        const info = h('div.pp-info',
            ...[['标题', m.title], ['作者', m.creator], ['最后修改', m.lastModifiedBy], ['修改时间', m.modified && new Date(m.modified).toLocaleString('zh-CN')],
                ['尺寸', `${Math.round(this.pptx.width)} × ${Math.round(this.pptx.height)} px`], ['生成程序', m.app]]
                .filter(([, v]) => v).map(([k, v]) => h('div.pp-info-row', h('span', k), h('b', v))))

        this.tabs = sidebarTabs([
            { id: 'thumbs', label: '幻灯片', icon: 'gallery-vertical-end', panel: this.thumbs },
            { id: 'outline', label: '大纲', icon: 'list-tree', panel: this.outline },
            { id: 'search', label: '搜索', icon: 'search', panel: searchPanel, onshow: () => setTimeout(() => this.searchInput.focus(), 50) },
            { id: 'info', label: '信息', icon: 'info', panel: info },
        ])
        this.sidebar.append(this.tabs.el)
    }

    fillThumb(i) {
        const s = this.slides[i]
        const box = this.thumbs?.children[i]?.querySelector('.pp-thumb-img')
        if (!s?.el || !box || box.firstChild) return
        const clone = s.el.cloneNode(true)
        clone.querySelectorAll('video, audio').forEach(m => m.remove())
        clone.style.transform = `scale(${276 / this.pptx.width})`
        clone.classList.add('pp-thumb-slide')
        box.append(clone)
        if (s.hidden) box.parentElement.classList.add('hidden-slide')
    }

    async buildOutline() {
        const ol = h('ol')
        this.texts = []
        for (let i = 0; i < this.pptx.count; i++) {
            if (this.destroyed) return
            const t = await this.pptx.slideText(i).catch(() => ({ title: '', text: '' }))
            this.texts.push(t)
            const label = t.title || t.text.split('\n')[0] || '（无标题）'
            ol.append(h('li', h('a', { dataset: { i }, onclick: () => this.goTo(i) }, h('span.search-page', String(i + 1)), label.slice(0, 80))))
        }
        this.outline.replaceChildren(h('div.sb-caption', icon('list-tree', 15), '幻灯片大纲'), ol)
        this.updateCurrent()
    }

    async search(q) {
        q = q.trim()
        this.searchResults.replaceChildren()
        if (!q) return
        while (!this.texts || this.texts.length < this.pptx.count) {
            await new Promise(r => setTimeout(r, 50))
            if (this.destroyed) return
        }
        const lower = q.toLowerCase()
        let count = 0
        const notes = await Promise.all(this.texts.map((_, i) => this.pptx.notes(i).catch(() => '')))
        this.texts.forEach((t, i) => {
            for (const [src, text] of [['', t.text], ['备注 · ', notes[i]]]) {
                const low = text.toLowerCase()
                let idx = low.indexOf(lower), hits = 0
                while (idx >= 0 && hits < 10) {
                    count++, hits++
                    const pre = text.slice(Math.max(0, idx - 20), idx).replace(/\s+/g, ' ')
                    const post = text.slice(idx + q.length, idx + q.length + 36).replace(/\s+/g, ' ')
                    this.searchResults.append(h('div.search-item', { onclick: () => { this.goTo(i); this.highlight(q) } },
                        h('span.search-page', `${src}${i + 1}`), pre, h('mark', text.slice(idx, idx + q.length)), post))
                    idx = low.indexOf(lower, idx + q.length)
                }
            }
        })
        this.searchResults.prepend(h('div.search-status', count ? `共找到 ${count} 处结果` : '没有找到匹配内容'))
    }

    highlight(q) {
        this.searchQ = q
        this.finder ??= new DomFinder(this.stage)
        this.finder.search(q)
    }

    openSearch() {
        this.finder ??= new DomFinder(this.stage)
        this.find.open()
    }

    // ---------- 备注 ----------
    toggleNotes(force) {
        const open = force ?? this.notesEl.hidden
        this.notesEl.hidden = !open
        this.notesBtn.classList.toggle('active', open)
        this.content.classList.toggle('notes-open', open)
        if (open) this.renderNotes()
        requestAnimationFrame(() => this.layout())
    }
    async renderNotes() {
        const i = this.current
        const text = await this.pptx.notes(i)
        if (i !== this.current) return
        this.notesEl.replaceChildren(
            h('div.pp-notes-head', icon('sticky-note', 14), `第 ${i + 1} 张 · 备注`),
            text ? h('div.pp-notes-text', text) : h('div.empty-mini', '此幻灯片没有备注'))
    }

    // ---------- 放映 ----------
    async present(from = this.current) {
        if (this.presenter) return
        const W = this.pptx.width, H = this.pptx.height
        const stage = h('div.pp-show-stage')
        const counter = h('div.pp-show-counter')
        const root = h('div.pp-show', stage, counter,
            h('div.pp-show-hint', '← → 翻页 · Esc 退出 · B 黑屏'))
        document.body.append(root)
        const wasFs = document.documentElement.classList.contains('fullscreen')
        if (!wasFs) window.lite.win.setFullscreen(true)
        let idx = from
        const visible = []
        for (let i = 0; i < this.pptx.count; i++) visible.push(i)
        const show = async i => {
            idx = clamp(i, 0, this.pptx.count - 1)
            await this.ensure(idx)
            const s = this.slides[idx]
            if (!s.el) return
            const sc = Math.min(innerWidth / W, innerHeight / H)
            const clone = s.el.cloneNode(true)
            clone.style.transform = `scale(${sc})`
            const frame = h('div.pp-show-frame', { style: { width: W * sc + 'px', height: H * sc + 'px' } }, clone)
            stage.replaceChildren(frame)
            frame.animate?.([{ opacity: 0 }, { opacity: 1 }], { duration: 260, easing: 'ease-out' })
            counter.textContent = `${idx + 1} / ${this.pptx.count}`
            this.ensure(idx + 1)
            if (idx !== this.current) { this.current = idx; this.updateCurrent() }
        }
        const next = () => idx < this.pptx.count - 1 ? show(idx + 1) : exit()
        const onKey = e => {
            const k = e.key
            e.stopPropagation()
            e.preventDefault()
            if (k === 'Escape') exit()
            else if (['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter', 'n'].includes(k)) next()
            else if (['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace', 'p'].includes(k)) show(idx - 1)
            else if (k === 'Home') show(0)
            else if (k === 'End') show(this.pptx.count - 1)
            else if (k.toLowerCase() === 'b' || k === '.') root.classList.toggle('black')
            else if (k.toLowerCase() === 'w' || k === ',') root.classList.toggle('white')
        }
        const onClick = e => {
            if (e.target.closest('video, audio, a')) return
            if (e.button === 0) next()
        }
        const onCtx = e => { e.preventDefault(); show(idx - 1) }
        const onWheel = e => {
            const now = performance.now()
            if (now - (this.lastFlip ?? 0) < 300) return
            this.lastFlip = now
            e.deltaY > 0 ? next() : show(idx - 1)
        }
        const onResize = debounce(() => show(idx), 100)
        document.addEventListener('keydown', onKey, true)
        root.addEventListener('click', onClick)
        root.addEventListener('contextmenu', onCtx)
        root.addEventListener('wheel', onWheel, { passive: true })
        window.addEventListener('resize', onResize)
        const exit = () => {
            document.removeEventListener('keydown', onKey, true)
            window.removeEventListener('resize', onResize)
            root.remove()
            this.presenter = null
            if (!wasFs) window.lite.win.setFullscreen(false)
            this.goTo(idx, false)
        }
        this.presenter = { show, exit }
        this.onDispose(() => this.presenter?.exit())
        await show(idx)
    }

    onShow() {
        if (this.pptx) requestAnimationFrame(() => this.layout())
    }

    onKey(e) {
        if (!this.pptx) return false
        const k = e.key
        if (e.ctrlKey && (k === '=' || k === '+')) { this.setZoom(this.zoomLevel * 1.15); return true }
        if (e.ctrlKey && k === '-') { this.setZoom(this.zoomLevel / 1.15); return true }
        if (e.ctrlKey && k === '0') { this.zoomLevel = 1; this.layout(); return true }
        if (e.ctrlKey && k.toLowerCase() === 'f') { this.openSearch(); return true }
        if (k === 'F5') { this.present(e.shiftKey ? this.current : 0); return true }
        if (k.toLowerCase() === 'n' && !e.ctrlKey) { this.toggleNotes(); return true }
        const flip = this.mode === 'single' || ['PageDown', 'PageUp'].includes(k)
        if (flip && ['ArrowRight', 'ArrowDown', 'PageDown', ' '].includes(k)) { this.goTo(this.current + 1); return true }
        if (flip && ['ArrowLeft', 'ArrowUp', 'PageUp'].includes(k)) { this.goTo(this.current - 1); return true }
        if (k === 'Home') { this.goTo(0); return true }
        if (k === 'End') { this.goTo(this.pptx.count - 1); return true }
        return false
    }

    destroy() {
        this.destroyed = true
        this.saveProgress()
        super.destroy()
    }
}

