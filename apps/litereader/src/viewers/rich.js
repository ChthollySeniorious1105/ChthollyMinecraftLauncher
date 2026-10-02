import { FlowTextViewer } from './docs.js'
import { h } from '../core/dom.js'
import { decodeRtf, decodeOdf } from '../core/formats.js'
import { DomFinder, findBar } from '../core/find.js'

// 富文本查看器：RTF / ODT，默认保留原文格式（颜色、字号、对齐），可切换为统一阅读排版
export class RichViewer extends FlowTextViewer {
    loadingText = '正在解析文档…'
    keepStyle = true

    extraTools() {
        this.styleToggle = h('button.chip-btn.active', { title: '保留原文格式 / 统一阅读排版', onclick: () => this.toggleStyle() }, '原格式')
        this.right.append(this.styleToggle)
        this.tool('search', '查找 (Ctrl F)', () => this.openFind())
    }

    async load() {
        if (!this.decoded) {
            const buf = await this.source.arrayBuffer()
            this.decoded = this.source.ext === 'rtf' ? await decodeRtf(buf) : await decodeOdf(buf)
            if (this.decoded.urls) this.onDispose(() => this.decoded.urls.forEach(u => URL.revokeObjectURL(u)))
            this.setCaveats(this.decoded.caveats)
        }
        const r = this.decoded
        const tmp = document.createElement('div')
        tmp.innerHTML = r.html
        const words = tmp.textContent.replace(/\s/g, '').length
        const kind = this.source.ext === 'rtf' ? 'RTF 富文本' : 'OpenDocument 文本'
        this.setSubtitle(`${kind}${r.title ? ' · ' + r.title : ''} · ${words.toLocaleString()} 字`)
        return { html: r.html }
    }

    async render() {
        await super.render()
        this.article.classList.add('rich-article')
        this.article.classList.toggle('keep-style', this.keepStyle)
        this.finder = new DomFinder(this.article)
    }

    toggleStyle() {
        this.keepStyle = !this.keepStyle
        this.styleToggle.classList.toggle('active', this.keepStyle)
        this.styleToggle.textContent = this.keepStyle ? '原格式' : '阅读排版'
        this.article.classList.toggle('keep-style', this.keepStyle)
    }

    openFind() {
        if (!this.find) {
            this.find = findBar(() => this.finder)
            this.content.append(this.find.el)
        }
        this.find.open()
    }

    onKey(e) {
        if (e.ctrlKey && e.key.toLowerCase() === 'f') { this.openFind(); return true }
        return super.onKey(e)
    }
}
