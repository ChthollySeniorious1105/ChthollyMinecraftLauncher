import { marked } from 'marked'
import { FlowTextViewer } from './docs.js'
import { readerColors } from './reader-style.js'
import { h, btn, menu, togglePopover, toast, escapeHTML } from '../core/dom.js'
import { decodeText, ENCODINGS } from '../core/encoding.js'
import { DomFinder, findBar } from '../core/find.js'

const CODE_EXTS = new Set(['json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'cfg', 'toml', 'js', 'mjs', 'ts', 'css', 'py', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'sh', 'bat', 'ps1', 'sql', 'sty', 'cls', 'bib', 'log',
    'php', 'rb', 'kt', 'swift', 'lua', 'r', 'vue', 'jsx', 'tsx', 'scss', 'less', 'dart', 'pl'])
// 扩展名 → highlight.js 语言名
const LANG = { js: 'javascript', mjs: 'javascript', jsx: 'javascript', ts: 'typescript', tsx: 'typescript', py: 'python', rs: 'rust', rb: 'ruby', kt: 'kotlin', cs: 'csharp', h: 'c', hpp: 'cpp', sh: 'bash', bat: 'dos', ps1: 'powershell', yml: 'yaml', conf: 'ini', cfg: 'ini', toml: 'ini', vue: 'xml', sty: 'latex', cls: 'latex', bib: 'latex', pl: 'perl', log: 'plaintext' }
const MAX_HIGHLIGHT = 2 * 1024 * 1024

let hljsMod = null
const loadHljs = () => hljsMod ??= Promise.all([import('highlight.js'), import('highlight.js/styles/github-dark.css?inline'), import('highlight.js/styles/github.css?inline')])
    .then(([m, dark, light]) => ({ hljs: m.default, dark: dark.default, light: light.default }))
let katexMod = null
const loadKatex = () => katexMod ??= Promise.all([import('katex'), import('katex/dist/katex.min.css')]).then(([m]) => m.default)

// TXT / Markdown / 代码等文本文件，自动识别编码；代码语法高亮，Markdown 支持 $…$ 数学公式与代码高亮
export class TextViewer extends FlowTextViewer {
    loadingText = '正在读取文本…'

    get isCode() { return CODE_EXTS.has(this.source.ext) }
    get isMarkdown() { return ['md', 'markdown'].includes(this.source.ext) }

    extraTools() {
        this.encBtn = h('button.chip-btn', {
            title: '切换文本编码',
            onclick: e => togglePopover(e.currentTarget, () => menu(ENCODINGS.map(([v, label]) => ({
                label, checked: v === this.encoding, onclick: () => this.reload(v),
            })))),
        }, '编码')
        this.right.append(this.encBtn)
        this.tool('search', '查找 (Ctrl F)', () => this.openFind())
    }

    async load() {
        this.bytes ??= new Uint8Array(await this.source.arrayBuffer())
        const { text, encoding } = decodeText(this.bytes, this.forceEncoding)
        this.encoding = encoding
        this.encBtn.textContent = (ENCODINGS.find(e => e[0] === encoding)?.[1] ?? encoding).split(' ')[0]
        const words = text.replace(/\s/g, '').length
        const lines = text.split('\n').length
        this.setSubtitle(this.isCode ? `${encoding.toUpperCase()} · ${lines.toLocaleString()} 行` : `${encoding.toUpperCase()} · ${words.toLocaleString()} 字`)
        if (this.isMarkdown) return { html: await renderMarkdown(text) }
        if (this.isCode) {
            const html = await highlightCode(text, LANG[this.source.ext] ?? this.source.ext)
            if (html) return { html }
        }
        return { text }
    }

    async render() {
        await super.render()
        if (this.isCode || this.isMarkdown) this.applyCodeTheme()
        this.finder = new DomFinder(this.article)
    }

    // 代码配色跟随阅读区明暗（样式限定在本查看器内）
    async applyCodeTheme() {
        const { dark, light } = await loadHljs()
        const isDark = readerColors().dark
        this.codeStyle ??= document.head.appendChild(h('style'))
        const scope = `.viewer[data-code-theme="${isDark ? 'dark' : 'light'}"]`
        this.el.dataset.codeTheme = isDark ? 'dark' : 'light'
        this.codeStyle.textContent = (isDark ? dark : light).replace(/\.hljs/g, `${scope} .hljs`) + `${scope} .hljs { background: transparent; }`
    }
    applyStyle() {
        super.applyStyle()
        if (this.codeStyle) this.applyCodeTheme()
    }

    async reload(enc) {
        this.forceEncoding = enc
        await this.render()
        toast(`已切换为 ${enc.toUpperCase()} 编码`, 'success')
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

    destroy() {
        this.codeStyle?.remove()
        super.destroy()
    }
}

// 代码高亮：带行号；超大文件不高亮以免卡顿
export async function highlightCode(text, lang) {
    if (text.length > MAX_HIGHLIGHT) return null
    const { hljs } = await loadHljs()
    let out
    try {
        out = hljs.getLanguage(lang) ? hljs.highlight(text, { language: lang, ignoreIllegals: true }).value : hljs.highlightAuto(text.slice(0, 200000)).value
    } catch { return null }
    // 按行切分，保持跨行的 span 闭合
    const lines = []
    let open = []
    for (const raw of out.split('\n')) {
        const line = open.join('') + raw
        const tags = raw.match(/<span[^>]*>|<\/span>/g) ?? []
        for (const t of tags) t.startsWith('</') ? open.pop() : open.push(t)
        lines.push(line + '</span>'.repeat(open.length))
    }
    if (lines.length > 1 && lines.at(-1) === '') lines.pop()
    return `<pre class="code-block hljs code-lines"><code>${lines.map((l, i) => `<span class="ln" data-n="${i + 1}"></span>${l || ' '}`).join('\n')}</code></pre>`
}

// Markdown：GFM + 代码高亮 + KaTeX 公式（$…$、$$…$$、\(…\)、\[…\]）
export async function renderMarkdown(text) {
    const hasMath = /\$[^$\n]+\$|\$\$[\s\S]+?\$\$|\\\(|\\\[/.test(text)
    const katex = hasMath ? await loadKatex() : null
    const { hljs } = await loadHljs()
    // 先把公式替换为占位符，避免 Markdown 语法（_ * \）破坏公式
    const math = []
    let src = text
    if (katex) {
        // 跳过代码块与行内代码
        const parts = src.split(/(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]+`)/g)
        src = parts.map((p, i) => i % 2 ? p : p
            .replace(/\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]/g, (_, a, b) => `\n\nLRMATH${math.push({ tex: a ?? b, display: true }) - 1}X\n\n`)
            .replace(/\\\(([\s\S]+?)\\\)|(?<![\\$\w])\$(?!\s)([^$\n]+?)(?<!\s)\$(?![\d$])/g, (_, a, b) => `LRMATH${math.push({ tex: a ?? b, display: false }) - 1}X`)).join('')
    }
    const renderer = new marked.Renderer()
    renderer.code = ({ text: code, lang }) => {
        const l = (lang ?? '').split(/\s/)[0]
        if (l === 'math' || l === 'latex' && katex && !code.includes('\\documentclass')) {
            if (katex) return mathHtml(katex, code, true)
        }
        let body
        try { body = l && hljs.getLanguage(l) ? hljs.highlight(code, { language: l, ignoreIllegals: true }).value : escapeHTML(code) } catch { body = escapeHTML(code) }
        return `<pre class="hljs"><code class="language-${escapeHTML(l)}">${body}</code></pre>`
    }
    let html = marked.parse(src, { gfm: true, breaks: false, renderer })
    if (katex) html = html.replace(/(<p>)?LRMATH(\d+)X(<\/p>)?/g, (m, p1, i, p2) => {
        const it = math[i]
        const out = mathHtml(katex, it.tex, it.display)
        return it.display ? out : (p1 ?? '') + out + (p2 ?? '')
    })
    return html
}

function mathHtml(katex, tex, display) {
    try {
        return katex.renderToString(tex, { displayMode: display, throwOnError: false, strict: 'ignore' })
    } catch {
        return `<code>${escapeHTML(tex)}</code>`
    }
}

// 旧版 Word（.doc）：在主进程中提取文本后以阅读模式显示
export class DocViewer extends FlowTextViewer {
    loadingText = '正在解析 Word 97-2003 文档…'

    async load() {
        const src = this.source.path ?? new Uint8Array(await this.source.arrayBuffer())
        const r = await window.lite.extractDoc(src)
        const text = [r.body, r.footnotes && '\n\n脚注\n' + r.footnotes, r.endnotes && '\n\n尾注\n' + r.endnotes].filter(Boolean).join('')
        this.setSubtitle(`Word 97-2003 · ${text.replace(/\s/g, '').length.toLocaleString()} 字`)
        this.setCaveats(['DOC 仅提取文字内容（图片、表格与格式不显示）'])
        return { text }
    }
}

export { btn }
