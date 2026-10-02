import { h, btn } from './dom.js'
import { icon } from './icons.js'

const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'SELECT', 'svg', 'SVG'])

// 在任意 DOM（含 iframe 文档）中查找并高亮文本
export class DomFinder {
    hits = []
    index = -1

    constructor(root, { cls = 'lr-hit', limit = 5000 } = {}) {
        this.root = root
        this.cls = cls
        this.limit = limit
    }

    clear() {
        const parents = new Set()
        for (const m of this.hits) {
            if (!m.isConnected) continue
            parents.add(m.parentNode)
            m.replaceWith(m.ownerDocument.createTextNode(m.textContent))
        }
        for (const p of parents) p.normalize()
        this.hits = []
        this.index = -1
    }

    search(q) {
        this.clear()
        q = q.trim().toLowerCase()
        if (!q || !this.root) return 0
        const doc = this.root.ownerDocument ?? this.root
        const walker = doc.createTreeWalker(this.root, NodeFilter.SHOW_TEXT, {
            acceptNode: n => {
                const p = n.parentElement
                if (!p || SKIP.has(p.tagName) || p.closest('.katex-mathml, [aria-hidden="true"]')) return NodeFilter.FILTER_REJECT
                return n.nodeValue.toLowerCase().includes(q) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP
            },
        })
        const nodes = []
        while (walker.nextNode()) nodes.push(walker.currentNode)
        for (const node of nodes) {
            if (this.hits.length >= this.limit) break
            const text = node.nodeValue, low = text.toLowerCase()
            const frag = doc.createDocumentFragment()
            let last = 0, i = low.indexOf(q)
            while (i >= 0 && this.hits.length < this.limit) {
                if (i > last) frag.append(text.slice(last, i))
                const m = doc.createElement('mark')
                m.className = this.cls
                m.textContent = text.slice(i, i + q.length)
                frag.append(m)
                this.hits.push(m)
                last = i + q.length
                i = low.indexOf(q, last)
            }
            if (last < text.length) frag.append(text.slice(last))
            node.replaceWith(frag)
        }
        if (this.hits.length) this.step(1)
        return this.hits.length
    }

    step(dir = 1) {
        if (!this.hits.length) return
        this.hits[this.index]?.classList.remove('current')
        this.index = ((this.index + dir) % this.hits.length + this.hits.length) % this.hits.length
        const m = this.hits[this.index]
        m.classList.add('current')
        m.scrollIntoView({ block: 'center', inline: 'nearest' })
    }
}

// 浮动查找栏：Enter 下一个，Shift+Enter 上一个，Esc 关闭
export function findBar(getFinder) {
    const input = h('input.input.small', { type: 'search', placeholder: '查找…' })
    const count = h('span.find-count', '')
    let lastQ = ''
    const update = () => {
        const f = getFinder()
        count.textContent = !lastQ ? '' : f?.hits.length ? `${f.index + 1}/${f.hits.length}` : '无结果'
    }
    const run = dir => {
        const f = getFinder()
        if (!f) return
        const q = input.value
        if (q !== lastQ) { lastQ = q; f.search(q) } else f.step(dir)
        update()
    }
    const el = h('div.find-bar', { hidden: true },
        icon('search', 15), input, count,
        btn('chevron-up', '上一个 (Shift Enter)', () => run(-1), { size: 16 }),
        btn('chevron-down', '下一个 (Enter)', () => run(1), { size: 16 }),
        btn('x', '关闭 (Esc)', () => close(), { size: 16 }))
    const open = () => {
        el.hidden = false
        input.focus()
        input.select()
    }
    const close = () => {
        el.hidden = true
        getFinder()?.clear()
        lastQ = ''
        update()
    }
    input.addEventListener('keydown', e => {
        if (e.key === 'Enter') { e.preventDefault(); run(e.shiftKey ? -1 : 1) }
        if (e.key === 'Escape') { e.stopPropagation(); close() }
    })
    return { el, open, close, get isOpen() { return !el.hidden } }
}
