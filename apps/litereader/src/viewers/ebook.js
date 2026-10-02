import 'foliate-js/view.js'
import { createTOCView } from 'foliate-js/ui/tree.js'
import { Viewer, sidebarTabs } from './base.js'
import { h, btn, togglePopover, slider, segmented, toggle, debounce, escapeHTML } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { readerPanel, readerColors, FONT_STACKS } from './reader-style.js'

const fmtLang = x => {
    if (!x) return ''
    if (typeof x === 'string') return x
    return x[Object.keys(x)[0]] ?? ''
}
const fmtAuthor = a => Array.isArray(a) ? a.map(fmtAuthor).join('、') : typeof a === 'string' ? a : fmtLang(a?.name)

export class EbookViewer extends Viewer {
    async mount() {
        this.addTitle()
        this.tool('panel-left', '目录 / 书签 / 搜索', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)

        this.progressLabel = h('span.v-progress-label', '')
        this.center.append(
            btn('chevron-left', '上一页', () => this.view?.goLeft()),
            this.progressLabel,
            btn('chevron-right', '下一页', () => this.view?.goRight()))

        this.bookmarkBtn = this.tool('bookmark', '添加书签 (B)', () => this.toggleBookmark())
        this.tool('type', '阅读设置', e => togglePopover(e.currentTarget, () => this.stylePanel()))
        this.tool('maximize', '全屏阅读 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在解析电子书…')
        try {
            const file = await this.source.file()
            this.view = document.createElement('foliate-view')
            this.view.classList.add('foliate')
            this.stageEl = h('div.ebook-stage', this.view)
            this.content.append(this.stageEl)
            await this.view.open(file)
        } catch (e) {
            ld.done()
            return this.error(e?.name === 'UnsupportedTypeError' ? '不支持的电子书格式或文件已损坏（注意：带 DRM 加密的 Kindle 书籍无法打开）' : e)
        }
        ld.done()

        const { book } = this.view
        this.book = book
        this.bookTitle = fmtLang(book.metadata?.title) || this.source.name
        this.setSubtitle(fmtAuthor(book.metadata?.author) || '电子书')

        book.transformTarget?.addEventListener('data', ({ detail }) => {
            detail.data = Promise.resolve(detail.data).catch(e => { console.warn(e); return '' })
        })

        this.buildSidebar()
        this.progressBar = h('input.range.ebook-progress', { type: 'range', min: 0, max: 1, step: 0.0001, value: 0 })
        this.progressBar.addEventListener('input', () => {
            this.progressBar.style.setProperty('--p', this.progressBar.value * 100 + '%')
            this.view.goToFraction(Number(this.progressBar.value))
        })
        this.footer = h('div.ebook-footer',
            this.chapterLabel = h('span.ebook-chapter', ''),
            this.progressBar,
            this.percentLabel = h('span.ebook-percent', '0%'))
        this.content.append(this.footer)

        this.view.addEventListener('load', e => this.onDocLoad(e.detail))
        this.view.addEventListener('relocate', e => this.onRelocate(e.detail))
        this.view.addEventListener('external-link', e => {
            e.preventDefault()
            window.lite.openExternal(e.detail.href)
        })

        this.applyStyle()
        this.listen(window, 'themechange', () => this.applyStyle())
        this.onDispose(store.onSettings((_s, k) => {
            if (typeof k !== 'string' || k.startsWith('reader')) this.applyStyle()
        }))

        const saved = store.getProgress(this.source.key)
        this.bookmarks = saved?.bookmarks ?? []
        this.renderBookmarks()
        try {
            await this.view.init({ lastLocation: saved?.cfi, showTextStart: !saved?.cfi })
        } catch (e) {
            console.warn(e)
            await this.view.init({ showTextStart: true })
        }

        // 点击左右边缘翻页
        const edge = side => h('div.ebook-edge.' + side, {
            onclick: () => side === 'left' ? this.view.goLeft() : this.view.goRight(),
        })
        this.stageEl.append(edge('left'), edge('right'))
    }

    buildSidebar() {
        const { book } = this
        const coverImg = h('img.book-cover', { alt: '' })
        Promise.resolve(book.getCover?.()).then(blob => {
            if (blob) {
                coverImg.src = URL.createObjectURL(blob)
                this.onDispose(() => URL.revokeObjectURL(coverImg.src))
            } else coverImg.replaceWith(h('div.book-cover.placeholder', icon('book', 36)))
        }).catch(() => coverImg.replaceWith(h('div.book-cover.placeholder', icon('book', 36))))

        const meta = h('div.book-meta',
            coverImg,
            h('div.book-meta-text',
                h('div.book-meta-title', this.bookTitle),
                h('div.book-meta-author', fmtAuthor(book.metadata?.author) || '佚名'),
                book.metadata?.publisher ? h('div.book-meta-pub', fmtLang(book.metadata.publisher)) : null))

        const tocPanel = h('div.toc-panel')
        if (book.toc?.length) {
            this.tocView = createTOCView(book.toc, href => {
                this.view.goTo(href).catch(console.error)
            })
            tocPanel.append(this.tocView.element)
        } else tocPanel.append(h('div.empty-mini', '此书没有目录'))

        this.bookmarkList = h('div.bm-list')
        const searchInput = h('input.input', { placeholder: '搜索全文…', type: 'search' })
        this.searchResults = h('div.search-results')
        searchInput.addEventListener('keydown', e => { if (e.key === 'Enter') this.search(searchInput.value) })
        const searchPanel = h('div.search-panel', h('div.search-box', icon('search', 16), searchInput), this.searchResults)

        const tabs = sidebarTabs([
            { id: 'toc', label: '目录', icon: 'list-tree', panel: tocPanel },
            { id: 'bm', label: '书签', icon: 'bookmark', panel: this.bookmarkList },
            { id: 'search', label: '搜索', icon: 'search', panel: searchPanel, onshow: () => setTimeout(() => searchInput.focus(), 50) },
        ])
        this.sidebarTabs = tabs
        this.sidebar.append(meta, tabs.el)
    }

    applyStyle() {
        const s = store.getSettings()
        const c = readerColors()
        const r = this.view?.renderer
        if (!r) return
        const font = FONT_STACKS[s.readerFont] ?? FONT_STACKS.serif
        r.setAttribute('flow', s.readerFlow)
        r.setAttribute('margin', s.readerMargin + 'px')
        r.setAttribute('gap', '6%')
        r.setAttribute('max-inline-size', s.readerWidth + 'px')
        r.setAttribute('max-column-count', s.readerColumns)
        r.setStyles?.(`
            @namespace epub "http://www.idpf.org/2007/ops";
            html { color-scheme: ${c.dark ? 'dark' : 'light'}; color: ${c.ink} !important; background: ${c.paper} !important; }
            html, body { font-family: ${font} !important; }
            body { font-size: ${s.readerFontSize}px !important; color: ${c.ink} !important; background: transparent !important; }
            body * { color: inherit; }
            p, li, blockquote, dd, div {
                line-height: ${s.readerLineHeight} !important;
                text-align: ${s.readerJustify ? 'justify' : 'start'};
                hyphens: auto; widows: 2; orphans: 2;
            }
            p { margin-block: .45em; }
            h1, h2, h3, h4, h5, h6 { color: ${c.heading} !important; line-height: 1.4; }
            a:link, a:visited { color: ${c.link} !important; }
            [align="center"] { text-align: center; }
            [align="right"] { text-align: right; }
            img, svg, video { max-width: 100%; height: auto; object-fit: contain; }
            pre { white-space: pre-wrap !important; }
            ::selection { background: ${c.selection}; }
            aside[epub|type~="footnote"], aside[epub|type~="endnote"], aside[epub|type~="rearnote"] { display: none; }
        `)
        this.stageEl.style.background = c.paper
        this.el.style.setProperty('--paper', c.paper)
        this.el.style.setProperty('--ink', c.ink)
    }

    stylePanel() {
        return readerPanel({ flow: true, columns: true })
    }

    onDocLoad({ doc }) {
        doc.addEventListener('keydown', e => this.app.handleKey(e))
        doc.addEventListener('wheel', e => {
            if (store.get('readerFlow') === 'scrolled' || e.ctrlKey) return
            if (Math.abs(e.deltaY) < 4) return
            e.deltaY > 0 ? this.view.next() : this.view.prev()
        }, { passive: true })
    }

    onRelocate(detail) {
        const { fraction = 0, tocItem, location, cfi } = detail
        this.location = detail
        const pct = Math.round(fraction * 1000) / 10
        this.percentLabel.textContent = pct + '%'
        this.progressBar.value = fraction
        this.progressBar.style.setProperty('--p', fraction * 100 + '%')
        this.chapterLabel.textContent = tocItem?.label ?? ''
        this.progressLabel.textContent = location ? `${location.current + 1} / ${location.total}` : `${pct}%`
        if (tocItem?.href) this.tocView?.setCurrentHref?.(tocItem.href)
        this.bookmarkBtn.classList.toggle('active', this.bookmarks.some(b => b.cfi === cfi))
        this.saveProgress()
    }

    saveProgress = debounce(() => {
        if (!this.location) return
        store.setProgress(this.source.key, {
            cfi: this.location.cfi,
            fraction: this.location.fraction,
            bookmarks: this.bookmarks,
        })
        this.app.updateRecentProgress(this.source, this.location.fraction)
    }, 400)

    toggleBookmark() {
        const loc = this.location
        if (!loc) return
        const i = this.bookmarks.findIndex(b => b.cfi === loc.cfi)
        if (i >= 0) this.bookmarks.splice(i, 1)
        else {
            const text = loc.range?.toString?.().trim().slice(0, 80) ?? ''
            this.bookmarks.push({ cfi: loc.cfi, label: loc.tocItem?.label ?? '', text, fraction: loc.fraction, time: Date.now() })
            this.bookmarks.sort((a, b) => a.fraction - b.fraction)
        }
        this.bookmarkBtn.classList.toggle('active', i < 0)
        this.renderBookmarks()
        this.saveProgress()
    }

    renderBookmarks() {
        if (!this.bookmarkList) return
        if (!this.bookmarks.length) {
            this.bookmarkList.replaceChildren(h('div.empty-mini', icon('bookmark-plus', 28), h('div', '按 B 键或点击右上角书签按钮添加书签')))
            return
        }
        this.bookmarkList.replaceChildren(...this.bookmarks.map(b => h('div.bm-item', {
            onclick: () => this.view.goTo(b.cfi),
        },
        h('div.bm-head', h('span.bm-chapter', b.label || '书签'), h('span.bm-pct', Math.round(b.fraction * 100) + '%')),
        b.text ? h('div.bm-text', b.text) : null,
        btn('trash-2', '删除', e => {
            e.stopPropagation()
            this.bookmarks = this.bookmarks.filter(x => x !== b)
            this.renderBookmarks()
            this.saveProgress()
        }, { class: 'bm-del', size: 14 }))))
    }

    async search(query) {
        query = query.trim()
        this.view.clearSearch()
        this.searchResults.replaceChildren()
        if (!query) return
        const token = this.searchToken = Symbol()
        const status = h('div.search-status', '正在搜索…')
        this.searchResults.append(status)
        let count = 0
        try {
            for await (const r of this.view.search({ query })) {
                if (token !== this.searchToken) return
                if (r === 'done') break
                if (r.progress != null) { status.textContent = `正在搜索… ${Math.round(r.progress * 100)}%`; continue }
                if (r.subitems) {
                    const group = h('div.search-group', h('div.search-group-title', r.label || '—'))
                    for (const s of r.subitems) {
                        count++
                        const { pre, match, post } = s.excerpt
                        group.append(h('div.search-item', {
                            onclick: () => this.view.goTo(s.cfi),
                            html: `${escapeHTML(pre)}<mark>${escapeHTML(match)}</mark>${escapeHTML(post)}`,
                        }))
                    }
                    this.searchResults.append(group)
                }
            }
        } catch (e) { console.error(e) }
        status.textContent = count ? `共找到 ${count} 处结果` : '没有找到匹配内容'
    }

    onKey(e) {
        if (!this.view) return false
        const k = e.key
        if (k === 'ArrowLeft' || k === 'PageUp') { this.view.goLeft(); return true }
        if (k === 'ArrowRight' || k === 'PageDown' || k === ' ') { this.view.goRight(); return true }
        if (k === 'ArrowUp' && store.get('readerFlow') !== 'scrolled') { this.view.prev(); return true }
        if (k === 'ArrowDown' && store.get('readerFlow') !== 'scrolled') { this.view.next(); return true }
        if (k === 'Home') { this.view.goToFraction(0); return true }
        if (k === 'End') { this.view.goToFraction(1); return true }
        if (k.toLowerCase() === 'b' && !e.ctrlKey) { this.toggleBookmark(); return true }
        if (k.toLowerCase() === 'f' && e.ctrlKey) {
            this.toggleSidebar(true)
            this.sidebarTabs.select('search')
            return true
        }
        return false
    }

    destroy() {
        this.saveProgress()
        try { this.view?.close() } catch { /* ignore */ }
        super.destroy()
    }
}

export { toggle, segmented, slider }
