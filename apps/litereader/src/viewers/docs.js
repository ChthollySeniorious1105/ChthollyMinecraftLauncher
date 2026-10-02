import { renderAsync } from 'docx-preview'
import { Viewer } from './base.js'
import { h, btn, clamp, togglePopover, debounce, escapeHTML } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { readerPanel, readerColors, FONT_STACKS } from './reader-style.js'

// 带缩放与进度记忆的滚动型文档查看器基类
class ScrollDocViewer extends Viewer {
    zoomLevel = 1

    setupScroller(inner) {
        this.scroller = h('div.doc-scroller', inner)
        this.content.append(this.scroller)
        this.listen(this.scroller, 'scroll', () => this.saveProgress(), { passive: true })
        this.listen(this.scroller, 'wheel', e => {
            if (!e.ctrlKey) return
            e.preventDefault()
            this.setZoom(this.zoomLevel * (e.deltaY < 0 ? 1.1 : 1 / 1.1))
        }, { passive: false })
    }

    addZoomTools() {
        this.zoomLabel = h('span.zoom-label.static', '100%')
        this.center.append(
            btn('zoom-out', '缩小', () => this.setZoom(this.zoomLevel / 1.1)),
            this.zoomLabel,
            btn('zoom-in', '放大', () => this.setZoom(this.zoomLevel * 1.1)))
    }

    setZoom(z) {
        this.zoomLevel = clamp(z, 0.3, 4)
        this.zoomLabel.textContent = Math.round(this.zoomLevel * 100) + '%'
        this.applyZoom()
        this.saveProgress()
    }
    applyZoom() {}

    restore() {
        const p = store.getProgress(this.source.key)
        if (p?.zoom) this.setZoom(p.zoom)
        if (p?.pos) requestAnimationFrame(() => {
            this.scroller.scrollTop = p.pos * (this.scroller.scrollHeight - this.scroller.clientHeight)
        })
    }

    saveProgress = debounce(() => {
        if (!this.scroller) return
        const max = this.scroller.scrollHeight - this.scroller.clientHeight
        const pos = max > 0 ? this.scroller.scrollTop / max : 0
        store.setProgress(this.source.key, { pos, zoom: this.zoomLevel })
        this.app.updateRecentProgress(this.source, pos)
    }, 400)

    onKey(e) {
        if (!this.scroller) return false
        const sc = this.scroller
        if (e.ctrlKey && (e.key === '=' || e.key === '+')) { this.setZoom(this.zoomLevel * 1.1); return true }
        if (e.ctrlKey && e.key === '-') { this.setZoom(this.zoomLevel / 1.1); return true }
        if (e.ctrlKey && e.key === '0') { this.setZoom(1); return true }
        if (e.key === 'PageDown' || e.key === ' ') { sc.scrollBy({ top: sc.clientHeight * 0.9, behavior: 'smooth' }); return true }
        if (e.key === 'PageUp') { sc.scrollBy({ top: -sc.clientHeight * 0.9, behavior: 'smooth' }); return true }
        if (e.key === 'Home' && !e.target.closest?.('input')) { sc.scrollTo({ top: 0 }); return true }
        if (e.key === 'End' && !e.target.closest?.('input')) { sc.scrollTo({ top: sc.scrollHeight }); return true }
        return false
    }

    destroy() {
        this.saveProgress()
        super.destroy()
    }
}

// ---------- DOCX：保留排版的页面渲染 ----------
export class DocxViewer extends ScrollDocViewer {
    async mount() {
        this.addTitle()
        this.addZoomTools()
        this.tool('panel-left', '文档结构', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading('正在渲染 Word 文档…')
        this.docHost = h('div.docx-host')
        const styleHost = h('div')
        this.setupScroller(h('div.docx-wrap', styleHost, this.docHost))
        try {
            const buf = await this.source.arrayBuffer()
            await renderAsync(buf, this.docHost, styleHost, {
                className: 'docx',
                inWrapper: true,
                ignoreLastRenderedPageBreak: true,
                experimental: true,
                renderHeaders: true,
                renderFooters: true,
                renderFootnotes: true,
                renderEndnotes: true,
                renderComments: false,
                useBase64URL: false,
                breakPages: true,
            })
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.docHost.addEventListener('click', e => {
            const a = e.target.closest('a[href]')
            if (!a) return
            e.preventDefault()
            const href = a.getAttribute('href')
            if (href.startsWith('#')) this.docHost.querySelector(`[id="${CSS.escape(href.slice(1))}"], a[name="${CSS.escape(href.slice(1))}"]`)?.scrollIntoView({ behavior: 'smooth' })
            else if (/^https?:/.test(href)) window.lite.openExternal(href)
        })
        const pages = this.docHost.querySelectorAll('section.docx').length
        this.setSubtitle(`Word 文档${pages ? ` · ${pages} 页` : ''}`)
        this.buildOutline()
        this.restore()
    }

    buildOutline() {
        const heads = [...this.docHost.querySelectorAll('h1, h2, h3, h4, p[class*="heading" i], p[class*="Heading"]')]
            .filter(el => el.textContent.trim()).slice(0, 500)
        const panel = h('div.toc-panel.outline')
        panel.append(h('div.sb-caption', icon('list-tree', 15), '文档结构'))
        if (!heads.length) panel.append(h('div.empty-mini', '文档中没有标题'))
        const ol = h('ol')
        for (const el of heads) {
            const m = /h(\d)|heading\s*(\d)/i.exec(el.tagName + ' ' + el.className)
            const lvl = Number(m?.[1] ?? m?.[2] ?? 1)
            ol.append(h('li', h('a', {
                style: { paddingInlineStart: `${(lvl - 1) * 16 + 12}px` },
                onclick: () => el.scrollIntoView({ behavior: 'smooth', block: 'start' }),
            }, el.textContent.trim().slice(0, 80))))
        }
        panel.append(ol)
        this.sidebar.append(panel)
    }

    applyZoom() {
        this.docHost.style.zoom = this.zoomLevel
    }
}

// ---------- 纯文本 / 回流式阅读（txt、md、doc、代码文件）----------
export class FlowTextViewer extends ScrollDocViewer {
    // 子类返回 { html } 或 { text }
    async load() { return { text: '' } }

    async mount() {
        this.addTitle()
        this.tool('panel-left', '章节', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)
        this.addZoomTools()
        this.extraTools?.()
        this.tool('type', '阅读设置', e => togglePopover(e.currentTarget, () => readerPanel({ width: true })))
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        const ld = this.loading(this.loadingText ?? '正在加载…')
        this.article = h('article.flow-article')
        this.page = h('div.flow-page', this.article)
        this.setupScroller(this.page)
        this.scroller.classList.add('flow-scroller')
        try {
            await this.render()
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.applyStyle()
        this.listen(window, 'themechange', () => this.applyStyle())
        this.onDispose(store.onSettings(() => this.applyStyle()))
        this.restore()
    }

    async render() {
        const r = await this.load()
        if (r.html != null) this.article.innerHTML = r.html
        else this.article.replaceChildren(...textToNodes(r.text, this.isCode))
        this.article.classList.toggle('code', !!this.isCode)
        this.buildChapters()
    }

    buildChapters() {
        this.sidebar.replaceChildren()
        const panel = h('div.toc-panel.outline', h('div.sb-caption', icon('list-tree', 15), '章节导航'))
        const heads = [...this.article.querySelectorAll('h1, h2, h3, h4, .chapter')].slice(0, 2000)
        if (!heads.length) panel.append(h('div.empty-mini', '未识别到章节'))
        const ol = h('ol')
        heads.forEach(el => {
            const lvl = el.classList.contains('chapter') ? 1 : Number(el.tagName[1])
            ol.append(h('li', h('a', {
                style: { paddingInlineStart: `${(lvl - 1) * 16 + 12}px` },
                onclick: () => el.scrollIntoView({ behavior: 'smooth', block: 'start' }),
            }, el.textContent.trim().slice(0, 60))))
        })
        panel.append(ol)
        this.sidebar.append(panel)
        this.chapterCount = heads.length
    }

    applyStyle() {
        const s = store.getSettings()
        const c = readerColors()
        const st = this.page.style
        st.setProperty('--r-paper', c.paper)
        st.setProperty('--r-ink', c.ink)
        st.setProperty('--r-link', c.link)
        st.setProperty('--r-font', this.isCode ? FONT_STACKS.mono : FONT_STACKS[s.readerFont] ?? FONT_STACKS.serif)
        st.setProperty('--r-size', s.readerFontSize + 'px')
        st.setProperty('--r-lh', s.readerLineHeight)
        st.setProperty('--r-width', s.readerWidth + 'px')
        st.setProperty('--r-pad', s.readerMargin + 'px')
        st.setProperty('--r-align', s.readerJustify ? 'justify' : 'start')
        this.scroller.style.background = `color-mix(in srgb, ${c.paper} 88%, ${c.dark ? '#000' : '#888'})`
        this.applyZoom()
    }

    applyZoom() {
        this.page.style.setProperty('--r-zoom', this.zoomLevel)
    }
}

// 章节标题识别（中文网络小说与常见英文格式）
const CHAPTER_RE = /^\s*((第\s*[0-9零〇一二两三四五六七八九十百千万]+\s*[章节回卷集部篇幕话]|卷\s*[0-9零〇一二三四五六七八九十百千]+|(chapter|part|book)\s+[0-9ivxlc]+|序章|序言|楔子|前言|引子|尾声|后记|番外)[^\n]{0,40})\s*$/i

// 将大段文本转换为段落节点；大文件分块以免阻塞
export function textToNodes(text, isCode = false) {
    if (isCode) return [h('pre.code-block', h('code', text))]
    const lines = text.replace(/\r\n?/g, '\n').split('\n')
    const frag = []
    let buf = []
    const flush = () => {
        if (!buf.length) return
        const p = document.createElement('p')
        p.textContent = buf.join('')
        frag.push(p)
        buf = []
    }
    for (const raw of lines) {
        const line = raw.replace(/^[\s　]+|\s+$/g, '')
        if (!line) { flush(); continue }
        if (line.length < 50 && CHAPTER_RE.test(line)) {
            flush()
            const hEl = document.createElement('h2')
            hEl.className = 'chapter'
            hEl.textContent = line
            frag.push(hEl)
            continue
        }
        buf.push(line)
        flush()
    }
    flush()
    return frag
}

export { escapeHTML }
