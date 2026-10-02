import 'katex/dist/katex.min.css'
import { FlowTextViewer } from './docs.js'
import { h } from '../core/dom.js'
import { decodeText } from '../core/encoding.js'
import { localURL, dirName } from '../core/files.js'
import { texToHtml } from '../core/latex.js'
import { DomFinder, findBar } from '../core/find.js'

const IMG_EXTS = ['', '.png', '.jpg', '.jpeg', '.pdf', '.svg', '.gif', '.webp', '.eps']

// LaTeX 查看器：转换为排版后的 HTML（公式由 KaTeX 渲染），可切换查看源码
export class TexViewer extends FlowTextViewer {
    loadingText = '正在排版 LaTeX 文档…'
    showSource = false

    get isCode() { return this.showSource }

    extraTools() {
        this.srcBtn = h('button.chip-btn', { title: '切换排版 / 源码 (Ctrl U)', onclick: () => this.toggleSource() }, '源码')
        this.right.append(this.srcBtn)
        this.tool('search', '查找 (Ctrl F)', () => this.openFind())
    }

    async load() {
        if (this.text == null) {
            const bytes = new Uint8Array(await this.source.arrayBuffer())
            this.text = decodeText(bytes).text
            await this.loadProject()
        }
        if (this.showSource) {
            this.setCaveats([])
            this.setSubtitle(`LaTeX 源码 · ${this.text.split('\n').length.toLocaleString()} 行`)
            return { text: this.text }
        }
        const t0 = performance.now()
        const r = texToHtml(this.text, { resolveAsset: f => this.assets.get(f) ?? null, includes: this.includes, bibs: this.bibs })
        const ms = Math.round(performance.now() - t0)
        this.setCaveats(r.caveats)
        const words = this.fullText.replace(/\\[a-zA-Z]+|[{}$%\s]/g, '').length
        const extra = this.includes.size ? ` · ${this.includes.size + 1} 个文件` : ''
        this.setSubtitle(`LaTeX · ${r.meta.cls ?? '文档'}${extra} · 约 ${words.toLocaleString()} 字 · 排版 ${ms} ms`)
        this.pdfImgs = r.html.includes('.pdf"')
        return { html: r.html }
    }

    async loadProject() {
        Object.assign(this, await loadTexProject(this.source, this.text))
    }

    async render() {
        await super.render()
        this.article.classList.add('tex-article')
        this.srcBtn.textContent = this.showSource ? '排版' : '源码'
        this.srcBtn.classList.toggle('active', this.showSource)
        this.finder = new DomFinder(this.article)
        this.article.onclick = e => {
            const a = e.target.closest('a[href]')
            if (!a) return
            e.preventDefault()
            const href = a.getAttribute('href')
            if (href.startsWith('#')) this.article.querySelector(`[id="${CSS.escape(href.slice(1))}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
            else if (/^(https?:|mailto:)/.test(href)) window.lite.openExternal(href)
        }
        if (this.pdfImgs) this.renderPdfImages()
        this.article.querySelectorAll('img.tex-img').forEach(img => img.addEventListener('error', () => {
            img.replaceWith(h('span.tex-missing', '🖼 ' + (img.dataset.file ?? '')))
            this.setCaveats([...(this.caveats ?? []), '部分图片未找到或格式不支持（如 EPS）'])
        }, { once: true }))
    }

    // LaTeX 中常用 PDF 作为插图：渲染第一页为图片
    async renderPdfImages() {
        const imgs = [...this.article.querySelectorAll('img.tex-img')].filter(i => /\.pdf$/i.test(decodeURIComponent(i.src)))
        if (!imgs.length) return
        const pdfjs = await import('pdfjs-dist')
        const { default: worker } = await import('pdfjs-dist/build/pdf.worker.min.mjs?worker&url')
        pdfjs.GlobalWorkerOptions.workerSrc ||= worker
        for (const img of imgs) {
            try {
                const data = new Uint8Array(await (await fetch(img.src)).arrayBuffer())
                const doc = await pdfjs.getDocument({ data, isEvalSupported: false }).promise
                const page = await doc.getPage(1)
                const vp = page.getViewport({ scale: 2 })
                const canvas = h('canvas')
                canvas.width = vp.width
                canvas.height = vp.height
                await page.render({ canvas, viewport: vp }).promise
                const blob = await new Promise(r => canvas.toBlob(r, 'image/png'))
                const url = URL.createObjectURL(blob)
                this.onDispose(() => URL.revokeObjectURL(url))
                img.src = url
                if (!img.style.width) img.style.width = Math.min(100, vp.width / 2 / 7) + '%'
                doc.destroy()
            } catch (e) {
                console.warn(e)
                img.dispatchEvent(new Event('error'))
            }
        }
    }

    async toggleSource() {
        this.showSource = !this.showSource
        const pos = this.scroller.scrollTop / Math.max(1, this.scroller.scrollHeight - this.scroller.clientHeight)
        await this.render()
        this.applyStyle()
        requestAnimationFrame(() => { this.scroller.scrollTop = pos * (this.scroller.scrollHeight - this.scroller.clientHeight) })
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
        if (e.ctrlKey && e.key.toLowerCase() === 'u') { this.toggleSource(); return true }
        return super.onKey(e)
    }
}

// 读取 LaTeX 工程中的其他文件：\input / \include 子文件、.bib 参考文献、插图（查看器与格式转换共用）
export async function loadTexProject(source, text) {
    const out = { text, includes: new Map(), bibs: [], assets: new Map(), fullText: text }
    if (!source.path) return out
    const dir = dirName(source.path)
    const read = async p => decodeText(await window.lite.readFile(p)).text
    const pathOf = (f, ext) => (dir + '\\' + f + (/\.[a-z]{2,4}$/i.test(f) ? '' : ext)).replace(/\//g, '\\').replace(/\\\.\\/g, '\\')
    // 子文件可能继续引用其他文件，逐层读取（最多 8 层、200 个）
    let queue = [text]
    for (let depth = 0; depth < 8 && queue.length && out.includes.size < 200; depth++) {
        const next = []
        for (const t of queue) {
            for (const m of t.matchAll(/\\(?:input|include|subfile)\s*\{([^}]+)\}/g)) {
                const name = m[1].trim()
                if (out.includes.has(name)) continue
                const hit = await window.lite.findFirst(pathOf(name, '.tex'), ['', '.tex'])
                const sub = hit ? await read(hit).catch(() => null) : null
                if (sub == null) continue
                out.includes.set(name, sub)
                out.fullText += '\n' + sub
                next.push(sub)
            }
        }
        queue = next
    }
    const bibNames = new Set()
    for (const m of out.fullText.matchAll(/\\bibliography\s*\{([^}]+)\}/g)) m[1].split(',').forEach(n => bibNames.add(n.trim()))
    for (const m of out.fullText.matchAll(/\\addbibresource\s*(?:\[[^\]]*\])?\s*\{([^}]+)\}/g)) bibNames.add(m[1].trim())
    for (const n of bibNames) {
        const hit = await window.lite.findFirst(pathOf(n, '.bib'), ['', '.bib'])
        if (hit) out.bibs.push(await read(hit).catch(() => ''))
    }
    out.assets = await findAssets(dir, out.fullText)
    return out
}

// 插图路径解析：支持省略扩展名、子目录与 \graphicspath；PDF 插图交由 pdf.js 渲染
async function findAssets(dir, text) {
    const map = new Map()
    const roots = ['']
    const gp = /\\graphicspath\s*\{((?:\s*\{[^}]*\})+)\s*\}/.exec(text)
    if (gp) for (const m of gp[1].matchAll(/\{([^}]*)\}/g)) roots.push(m[1])
    const files = new Set([...text.matchAll(/\\includegraphics\s*(?:\[[^\]]*\])?\s*\{([^}]+)\}/g)].map(m => m[1].trim()))
    await Promise.all([...files].map(async f => {
        const hasExt = /\.[a-z0-9]{2,4}$/i.test(f)
        for (const root of roots) {
            const base = (dir + '\\' + root + f).replace(/\//g, '\\').replace(/\\\.\\/g, '\\')
            const hit = await window.lite.findFirst(base, hasExt ? [''] : IMG_EXTS)
            if (hit) { map.set(f, localURL(hit)); return }
        }
    }))
    return map
}
