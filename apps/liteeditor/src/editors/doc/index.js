// 文字处理器
import katex from 'katex'
import { h, fill, toast } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import * as store from '../../core/store.js'
import { bytesToText, extOf, stemOf, dirName } from '../../core/files.js'
import { Editor, panel } from '../base.js'
import { mdToHTML, htmlToMD, docxToHTML } from './convert.js'
import { installUI } from './ui.js'
import { installFeatures } from './features.js'
import { SAMPLES } from './samples.js'

export const PAPERS = { A4: [210, 297], A5: [148, 210], B5: [176, 250], Letter: [216, 279], A3: [297, 420] }
const MM = 96 / 25.4 // 每毫米像素

export class DocEditor extends Editor {
    static kind = 'doc'

    constructor(file, app) {
        super(file, app)
        injectContentCSS()
        const pref = store.getPref('doc', { zoom: 1 })
        this.zoom = pref.zoom
        this.page = {
            paper: 'A4', landscape: false, margin: { top: 25, bottom: 25, left: 28, right: 28 },
            font: store.get('docFont') === 'sans' ? '"Microsoft YaHei", sans-serif' : '"SimSun", "Songti SC", serif',
            fontSize: store.get('docFontSize') ?? 16, lineHeight: 1.75, pageNumbers: true, header: '',
        }
        this.buildLayout()
        this.buildToolbar()
        this.buildPanels()
    }

    // ---------- 布局 ----------
    buildLayout() {
        this.body = h('div.doc-body', {
            contentEditable: 'true', spellcheck: store.get('docSpellcheck'), 'data-drop': '',
        })
        this.pageEl = h('div.doc-page', this.body)
        this.pageBreaks = h('div.doc-breaks')
        this.paper = h('div.doc-paper', this.pageEl, this.pageBreaks)
        this.scroller = h('div.doc-scroller', this.paper)
        this.source = h('textarea.doc-source', { spellcheck: false, hidden: true })
        this.stage.classList.add('doc-stage')
        this.stage.append(this.scroller, this.source)
        this.listen(this.body, 'focus', () => document.execCommand('defaultParagraphSeparator', false, 'p'))
        this.listen(this.body, 'input', e => this.onInput(e))
        this.listen(this.body, 'keydown', e => this.onBodyKey(e))
        this.listen(this.body, 'paste', e => this.onPaste(e))
        this.listen(this.body, 'drop', e => this.onDrop(e))
        this.listen(this.body, 'dragover', e => { if ([...e.dataTransfer.types].includes('Files')) e.preventDefault() })
        this.listen(this.body, 'click', e => this.onBodyClick(e))
        this.listen(this.body, 'dblclick', e => this.onBodyDbl(e))
        this.listen(this.body, 'contextmenu', e => this.onBodyContext(e))
        this.listen(document, 'selectionchange', () => { if (this.el.contains(document.activeElement) || this.hasSel()) this.updateFormatUI() })
        this.listen(this.source, 'input', () => this.onSourceInput())
        this.listen(this.scroller, 'wheel', e => { if (e.ctrlKey) { e.preventDefault(); this.setZoom(this.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1)) } }, { passive: false })
        this.ro = new ResizeObserver(() => this.layoutPages())
        this.ro.observe(this.body)
        this.onDispose(() => this.ro.disconnect())
    }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        const s = opts.sample && SAMPLES[opts.sample]
        this.setHTML(s ? s.html : '<p><br></p>')
        if (s?.page) Object.assign(this.page, s.page)
        this.applyPage()
        if (this.body.querySelector('.doc-toc')) requestAnimationFrame(() => { for (const t of this.body.querySelectorAll('.doc-toc')) t.innerHTML = this.tocHTML(); this.history.replace(this.snapshot()) })
    }

    async load(bytes, ext) {
        this.srcExt = ext
        let html = ''
        if (ext === 'docx') {
            const r = await docxToHTML(bytes)
            html = r.html
            const warn = r.messages.filter(m => m.type === 'warning').length
            if (warn) this.importNote = `部分 Word 格式未能完整导入（${warn} 项）`
        } else if (ext === 'ldoc') {
            const d = JSON.parse(bytesToText(bytes))
            if (d.format !== 'ldoc') throw new Error('不是有效的文档文件')
            html = d.html
            Object.assign(this.page, d.page ?? {})
        } else if (ext === 'md' || ext === 'markdown') {
            html = mdToHTML(bytesToText(bytes))
        } else if (ext === 'html' || ext === 'htm') {
            const doc = new DOMParser().parseFromString(bytesToText(bytes), 'text/html')
            doc.querySelectorAll('script, style, link, meta, iframe, object, embed').forEach(n => n.remove())
            doc.querySelectorAll('*').forEach(n => { for (const a of [...n.attributes]) if (/^on/i.test(a.name)) n.removeAttribute(a.name) })
            html = doc.body.innerHTML
            if (doc.title) this.docTitle = doc.title
        } else if (ext === 'tex' || ext === 'latex' || ext === 'ltx') {
            html = await this.loadTex(bytesToText(bytes))
        } else {
            const text = decodeText(bytes)
            html = text.split(/\r?\n/).map(l => `<p>${escapeHTML(l) || '<br>'}</p>`).join('')
        }
        this.setHTML(html || '<p><br></p>')
        this.applyPage()
        if (this.importNote) setTimeout(() => toast(this.importNote, 'warn', 4000), 300)
    }

    // LaTeX：转换为可编辑的文档；相对路径图片从同目录读取
    async loadTex(src) {
        const { texToHtml } = await import('./latex-in.js')
        this.texSource = src
        const dir = this.path ? dirName(this.path) : null
        // 预先解析插图路径（LaTeX 常省略扩展名）
        const assets = new Map()
        if (dir) {
            const files = [...new Set([...src.matchAll(/\\includegraphics\s*(?:\[[^\]]*\])?\s*\{([^}]+)\}/g)].map(m => m[1].trim()))]
            const exts = ['', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.bmp']
            await Promise.all(files.map(async f => {
                for (const e of /\.\w{2,4}$/.test(f) ? [''] : exts) {
                    const p = dir + '\\' + (f + e).replace(/\//g, '\\')
                    const st = await window.lite.stat(p)
                    if (st?.isFile) { assets.set(f, 'media://file/' + encodeURIComponent(p)); break }
                }
            }))
        }
        const r = texToHtml(src, {
            editable: true,
            resolveAsset: file => assets.get(file) ?? null,
        })
        if (r.caveats.length) this.importNote = 'LaTeX 部分内容为近似显示：' + r.caveats.join('、')
        const m = /\\documentclass\s*(\[[^\]]*\])?/.exec(src)
        if (m?.[1]?.includes('landscape')) this.page.landscape = true
        const geo = /\\geometry\{([^}]*)\}/.exec(src)?.[1] ?? ''
        const mm = k => { const x = new RegExp(k + '\\s*=\\s*([\\d.]+)\\s*mm').exec(geo); return x ? Number(x[1]) : null }
        for (const k of ['top', 'bottom', 'left', 'right']) if (mm(k)) this.page.margin[k] = mm(k)
        return r.html
    }

    snapshot() {
        return { html: this.body.innerHTML, page: JSON.stringify(this.page), sel: this.saveSel() }
    }
    restore(s) {
        this.body.innerHTML = s.html
        this.page = JSON.parse(s.page)
        this.renderMath()
        this.applyPage()
        this.restoreSel(s.sel)
        this.refreshAll()
        if (this.sourceMode) this.syncSource()
    }

    // ---------- 格式 ----------
    formats() {
        return [
            { ext: 'docx', name: 'Word 文档', write: () => this.writeDocx(), lossy: 'DOCX 中公式已转为图片' },
            { ext: 'ldoc', name: 'LiteEditor 文档', write: () => this.writeLdoc() },
            { ext: 'tex', name: 'LaTeX 源文件', write: target => this.writeTex(target), lossy: this.lossyNote('tex') },
            { ext: 'md', name: 'Markdown', write: () => this.writeMD(), lossy: this.lossyNote('md') },
            { ext: 'html', name: '网页', write: () => this.standaloneHTML() },
        ]
    }
    exports() {
        return [
            { ext: 'pdf', name: 'PDF 文档', write: () => window.lite.htmlToPdf(this.standaloneHTML({ print: true }), { landscape: this.page.landscape, pageSize: this.page.paper === 'Letter' ? 'Letter' : this.page.paper }) },
            { ext: 'txt', name: '纯文本', write: () => this.body.innerText.replace(/\n{3,}/g, '\n\n') },
        ]
    }
    fileItems() {
        return [
            '-',
            { label: '页面设置…', icon: 'file-cog', run: () => this.pageSetup() },
            { label: '打印…', icon: 'printer', key: 'Ctrl+P', run: () => window.lite.printHtml(this.standaloneHTML({ print: true })) },
        ]
    }
    lossyNote(kind) {
        if (kind === 'md') return 'Markdown 不保存字体、颜色、对齐与页面设置'
        if (kind === 'tex') return 'LaTeX 不保存字号与字体；图片保存到 images 文件夹'
        return ''
    }

    writeLdoc() {
        return JSON.stringify({ format: 'ldoc', version: 1, app: 'LiteEditor', page: this.page, html: this.cleanHTML() })
    }
    writeMD() {
        const r = htmlToMD(this.body)
        return r.md
    }
    async writeTex(target) {
        const { htmlToLatex } = await import('./latex-out.js')
        const r = htmlToLatex(this.body, this.page)
        // 内嵌图片写到 .tex 同目录的 images 文件夹
        if (target && r.images.length) {
            const dir = dirName(target)
            for (const img of r.images) {
                const dest = dir + '\\' + img.name.replace(/\//g, '\\')
                // 原目录中的图片：目标位置已存在则无需复制
                if (img.linked && decodeURIComponent(img.src.replace('media://file/', '')).toLowerCase() === dest.toLowerCase()) continue
                if (img.linked && await window.lite.stat(dest)) continue
                try {
                    const res = await fetch(img.src)
                    await window.lite.writeFile(dest, new Uint8Array(await res.arrayBuffer()))
                } catch { toast('无法写入图片：' + img.name, 'warn') }
            }
        }
        let tex = r.tex
        // 原文件来自 .tex：保留原导言区（宏包、宏定义），只补充缺少的宏包
        const orig = this.texSource
        const bi = orig ? orig.indexOf('\\begin{document}') : -1
        if (bi > 0) {
            let pre = orig.slice(0, bi)
            const have = new Set([...pre.matchAll(/\\usepackage(?:\[[^\]]*\])?\{([^}]+)\}/g)].flatMap(m => m[1].split(',').map(x => x.trim())))
            const need = [...r.tex.matchAll(/\\usepackage(\[[^\]]*\])?\{([^}]+)\}/g)]
                .filter(m => m[2] !== 'geometry' && !have.has(m[2]) && !(m[2] === 'ctex' && /ctex/.test(pre)))
            if (need.length) pre = pre.replace(/\s*$/, '\n' + need.map(m => m[0]).join('\n') + '\n\n')
            tex = pre + r.tex.slice(r.tex.indexOf('\\begin{document}'))
        }
        this.texSource = tex
        return tex
    }
    async writeDocx() {
        const { htmlToDocx } = await import('./docx.js')
        const [w, hh] = this.paperSize()
        const lossy = new Set()
        const data = await htmlToDocx(this.body, { ...this.page, w, h: hh, contentWidthPx: (w - this.page.margin.left - this.page.margin.right) * MM }, { lossy })
        if (lossy.size) setTimeout(() => toast('DOCX 中：' + [...lossy].join('、'), 'warn', 4200), 400)
        return data
    }

    // 复制正文并去掉编辑器内部标记（公式渲染结果、选中状态）
    cleanHTML() {
        const d = this.body.cloneNode(true)
        d.querySelectorAll('.doc-math').forEach(m => { m.innerHTML = '' })
        d.querySelectorAll('.selected, .doc-find-hit').forEach(n => n.classList.remove('selected', 'doc-find-hit'))
        d.querySelectorAll('mark.doc-find').forEach(m => m.replaceWith(...m.childNodes))
        return d.innerHTML
    }

    standaloneHTML({ print = false } = {}) {
        const d = this.body.cloneNode(true)
        d.querySelectorAll('[contenteditable]').forEach(n => n.removeAttribute('contenteditable'))
        d.querySelectorAll('mark.doc-find').forEach(m => m.replaceWith(...m.childNodes))
        const [w, hh] = this.paperSize()
        const m = this.page.margin
        const title = escapeHTML(this.docTitle ?? stemOf(this.name))
        return `<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>${title}</title>
<link rel="stylesheet" href="${print ? 'app://local/vendor/katex/katex.min.css' : 'https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css'}">
<style>
@page { size: ${w}mm ${hh}mm; margin: ${m.top}mm ${m.right}mm ${m.bottom}mm ${m.left}mm; }
${DOC_CONTENT_CSS}
body { margin: ${print ? 0 : '40px auto'}; max-width: ${print ? 'none' : (w - m.left - m.right) + 'mm'}; font-family: ${this.page.font}; font-size: ${this.page.fontSize}px; line-height: ${this.page.lineHeight}; color: #111; }
</style></head><body class="doc-content">
${d.innerHTML}
</body></html>`
    }

    // ---------- 内容 ----------
    setHTML(html) {
        this.body.innerHTML = html
        this.normalize()
        this.renderMath()
        this.refreshAll()
    }

    // 保证正文至少有一个段落，裸文本包入段落
    normalize() {
        const b = this.body
        for (const n of [...b.childNodes]) {
            if (n.nodeType === 3 && n.textContent.trim()) { const p = h('p'); n.replaceWith(p); p.append(n) }
            else if (n.nodeType === 3) n.remove()
        }
        if (!b.firstChild) b.append(h('p', h('br')))
    }

    renderMath(root = this.body) {
        for (const m of root.querySelectorAll('.doc-math')) {
            m.contentEditable = 'false'
            try { m.innerHTML = katex.renderToString(m.dataset.tex ?? '', { displayMode: m.classList.contains('block'), throwOnError: false }) }
            catch { m.textContent = m.dataset.tex }
        }
    }

    paperSize() {
        const [a, b] = PAPERS[this.page.paper] ?? PAPERS.A4
        return this.page.landscape ? [b, a] : [a, b]
    }

    applyPage() {
        const [w] = this.paperSize()
        const m = this.page.margin
        Object.assign(this.pageEl.style, {
            width: w * MM + 'px', padding: `${m.top * MM}px ${m.right * MM}px ${m.bottom * MM}px ${m.left * MM}px`,
            fontFamily: this.page.font, fontSize: this.page.fontSize + 'px', lineHeight: String(this.page.lineHeight),
        })
        this.paper.style.zoom = this.zoom
        this.layoutPages()
    }

    // 分页：在页高整数倍的位置画分页线，并在页面底部标注页码
    layoutPages() {
        const [, hh] = this.paperSize()
        const pageH = hh * MM
        const total = this.pageEl.offsetHeight
        const n = Math.max(1, Math.ceil(total / pageH))
        this.pageEl.style.minHeight = n * pageH + 'px'
        this.pages = n
        const marks = []
        for (let i = 1; i <= n; i++) {
            if (i < n) marks.push(h('div.doc-break', { style: { top: i * pageH + 'px' } }, h('span', `第 ${i + 1} 页`)))
            if (this.page.pageNumbers) marks.push(h('div.doc-pnum', { style: { top: i * pageH - this.page.margin.bottom * MM / 2 - 10 + 'px' } }, `${i} / ${n}`))
            if (this.page.header) marks.push(h('div.doc-phead', { style: { top: (i - 1) * pageH + this.page.margin.top * MM / 2 - 10 + 'px' } }, this.page.header))
        }
        this.pageBreaks.replaceChildren(...marks)
        this.updateStatus?.()
    }

    refreshAll() {
        this.layoutPages()
        this.refreshOutline?.()
        this.updateStatus?.()
        this.updateFormatUI?.()
    }

    // ---------- 输入 ----------
    onInput(e) {
        // 格式命令（execCommand）也会触发 input 事件：由 afterCommand 负责记录，这里忽略
        if (this.inCommand || (e && e.inputType?.startsWith('format'))) return
        if (e?.inputType === 'insertText' && e.data === ' ' && this.markdownShortcut()) return
        this.normalizeSoon()
        this.commit('输入', { merge: 'typing' })
        clearTimeout(this.outlineT)
        this.outlineT = setTimeout(() => { this.refreshOutline?.(); this.updateStatus?.() }, 300)
        if (this.sourceMode) this.syncSourceSoon()
    }
    normalizeSoon() {
        if (!this.body.firstChild || this.body.childNodes.length === 1 && this.body.firstChild.nodeName === 'BR') {
            this.body.innerHTML = '<p><br></p>'
            const r = document.createRange()
            r.setStart(this.body.firstChild, 0)
            getSelection().removeAllRanges()
            getSelection().addRange(r)
        }
    }

    // ---------- 选区保存 / 恢复（以文本偏移表示，快照中可序列化） ----------
    hasSel() {
        const s = getSelection()
        return s.rangeCount > 0 && this.body.contains(s.anchorNode)
    }
    saveSel() {
        const s = getSelection()
        if (!s.rangeCount || !this.body.contains(s.anchorNode)) return this.lastSel ?? null
        const r = s.getRangeAt(0)
        const off = (node, o) => {
            const pre = document.createRange()
            pre.selectNodeContents(this.body)
            pre.setEnd(node, o)
            return pre.toString().length
        }
        this.lastSel = { a: off(r.startContainer, r.startOffset), b: off(r.endContainer, r.endOffset) }
        return this.lastSel
    }
    restoreSel(sel) {
        if (!sel) return
        const find = pos => {
            const w = document.createTreeWalker(this.body, NodeFilter.SHOW_TEXT)
            let n, acc = 0, last = null
            while ((n = w.nextNode())) {
                if (acc + n.length >= pos) return [n, pos - acc]
                acc += n.length
                last = n
            }
            return last ? [last, last.length] : [this.body, 0]
        }
        const [sn, so] = find(sel.a), [en, eo] = find(sel.b)
        const r = document.createRange()
        try { r.setStart(sn, so); r.setEnd(en, eo) } catch { return }
        const s = getSelection()
        s.removeAllRanges()
        s.addRange(r)
    }

    onShow() {
        super.onShow()
        document.execCommand('defaultParagraphSeparator', false, 'p')
        this.layoutPages()
        if (!this.sourceMode) requestAnimationFrame(() => { if (!this.hasSel()) { this.body.focus({ preventScroll: true }); this.restoreSel(this.lastSel ?? { a: 0, b: 0 }) } })
    }

    // 编辑区内的撤销 / 格式快捷键由编辑器接管
    // 剪切 / 复制 / 粘贴 / 全选仍交给浏览器（粘贴经过 onPaste 清理）
    ownsTyping(e) {
        if (!(this.body.contains(e.target) || e.target === this.body)) return false
        return !(e.ctrlKey && !e.shiftKey && !e.altKey && /^[cxva]$/i.test(e.key))
    }

    // ---------- 右侧面板 ----------
    buildPanels() {
        this.outlineBody = h('div.e-list.doc-outline')
        this.panels.append(panel('导航', this.outlineBody, { icon: 'list-tree', cls: '.grow' }))
    }
    refreshOutline() {
        const hs = [...this.body.querySelectorAll('h1, h2, h3, h4')]
        fill(this.outlineBody, hs.length ? hs.map(el => h('div.e-list-item.doc-ol-' + el.tagName.toLowerCase(), {
            onclick: () => { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); const r = document.createRange(); r.selectNodeContents(el); r.collapse(true); getSelection().removeAllRanges(); getSelection().addRange(r) },
        }, h('span.li-name', el.textContent || '（空标题）'))) : h('div.ep-empty', '文档中的标题会显示在这里。使用“标题 1 / 2 / 3”样式创建章节。'))
    }

    updateStatus() {
        const text = this.body.innerText ?? ''
        const cjk = (text.match(/[㐀-鿿豈-﫿]/g) ?? []).length
        const words = (text.replace(/[㐀-鿿豈-﫿]/g, ' ').match(/[A-Za-z0-9_'’-]+/g) ?? []).length
        const paras = this.body.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li').length
        this.statusItems(
            h('span.st-item', icon('file-text', 13), `第 ${this.currentPage()} 页，共 ${this.pages ?? 1} 页`),
            h('span.st-item', `字数 ${cjk + words}`),
            h('span.st-item', `字符 ${text.replace(/\s/g, '').length}`),
            h('span.st-item', `段落 ${paras}`),
            this.srcExt ? h('span.st-item', (this.srcExt === 'tex' ? 'LaTeX' : this.srcExt.toUpperCase())) : null,
            h('span.st-flex'),
            h('button', { title: this.sourceMode ? '返回可视化编辑' : '源码视图', onclick: () => this.toggleSource() }, icon(this.sourceMode ? 'eye' : 'code', 13)),
            h('button', { onclick: () => this.setZoom(this.zoom - 0.1) }, icon('minus', 13)),
            h('button', { title: '重置缩放', onclick: () => this.setZoom(1) }, Math.round(this.zoom * 100) + '%'),
            h('button', { onclick: () => this.setZoom(this.zoom + 0.1) }, icon('plus', 13)))
    }
    currentPage() {
        const s = getSelection()
        if (!s.rangeCount || !this.body.contains(s.anchorNode)) return 1
        const r = s.getRangeAt(0).getBoundingClientRect()
        const top = this.pageEl.getBoundingClientRect().top
        const [, hh] = this.paperSize()
        return Math.max(1, Math.min(this.pages ?? 1, Math.floor((r.top - top) / this.zoom / (hh * MM)) + 1))
    }
    setZoom(z) {
        this.zoom = Math.round(Math.min(3, Math.max(0.3, z)) * 10) / 10
        store.setPref('doc', { zoom: this.zoom })
        this.applyPage()
    }

    // ---------- 源码视图（Markdown / HTML / LaTeX） ----------
    sourceKind() {
        const e = this.srcExt
        return e === 'md' || e === 'markdown' ? 'md' : e === 'tex' || e === 'latex' || e === 'ltx' ? 'tex' : 'html'
    }
    async toggleSource(kind) {
        this.sourceMode = !this.sourceMode
        if (kind) this.srcKindOverride = kind
        this.stage.classList.toggle('doc-split', this.sourceMode)
        this.source.hidden = !this.sourceMode
        if (this.sourceMode) await this.syncSource()
        this.updateStatus()
    }
    async syncSource() {
        const k = this.srcKindOverride ?? this.sourceKind()
        this.source.dataset.kind = k
        if (k === 'md') this.source.value = htmlToMD(this.body).md
        else if (k === 'tex') this.source.value = (await import('./latex-out.js')).htmlToLatex(this.body, this.page).tex
        else this.source.value = formatHTML(this.cleanHTML())
    }
    syncSourceSoon() {
        if (document.activeElement === this.source) return
        clearTimeout(this.srcT)
        this.srcT = setTimeout(() => this.syncSource(), 400)
    }
    onSourceInput() {
        clearTimeout(this.srcInT)
        this.srcInT = setTimeout(async () => {
            const k = this.source.dataset.kind
            const v = this.source.value
            let html
            if (k === 'md') html = mdToHTML(v)
            else if (k === 'tex') html = (await import('./latex-in.js')).texToHtml(v, { editable: true }).html
            else html = v
            this.body.innerHTML = html
            this.normalize()
            this.renderMath()
            this.refreshAll()
            this.commit('编辑源码', { merge: 'source' })
        }, 350)
    }
}

installUI(DocEditor)
installFeatures(DocEditor)

// 文档内容样式：编辑器与导出共用
export const DOC_CONTENT_CSS = `
.doc-content h1, .doc-body h1 { font-size: 2em; margin: .8em 0 .4em; font-weight: 700; line-height: 1.3; }
.doc-content h2, .doc-body h2 { font-size: 1.5em; margin: .8em 0 .4em; font-weight: 700; line-height: 1.35; }
.doc-content h3, .doc-body h3 { font-size: 1.25em; margin: .7em 0 .35em; font-weight: 700; }
.doc-content h4, .doc-body h4 { font-size: 1.1em; margin: .6em 0 .3em; font-weight: 700; }
.doc-content p, .doc-body p { margin: 0 0 .5em; }
.doc-content .doc-title, .doc-body .doc-title { font-size: 2.3em; text-align: center; margin: .4em 0 .2em; }
.doc-content .doc-subtitle, .doc-body .doc-subtitle { text-align: center; color: #555; font-size: 1.15em; }
.doc-content blockquote, .doc-body blockquote { margin: .6em 0; padding: .3em 1em; border-left: 4px solid #cbd5e1; color: #475569; }
.doc-content pre, .doc-body pre { background: #f1f5f9; padding: .8em 1em; border-radius: 6px; font-family: Consolas, "Cascadia Mono", monospace; font-size: .88em; white-space: pre-wrap; line-height: 1.5; }
.doc-content code, .doc-body code { font-family: Consolas, monospace; background: #f1f5f9; padding: .1em .35em; border-radius: 4px; font-size: .9em; }
.doc-content pre code, .doc-body pre code { background: none; padding: 0; }
.doc-content table, .doc-body table { border-collapse: collapse; margin: .6em 0; width: 100%; }
.doc-content td, .doc-content th, .doc-body td, .doc-body th { border: 1px solid #94a3b8; padding: .35em .6em; vertical-align: top; min-width: 2em; }
.doc-content th, .doc-body th { background: #f1f5f9; font-weight: 700; }
.doc-content img, .doc-body img { max-width: 100%; }
.doc-content hr, .doc-body hr { border: 0; border-top: 1px solid #cbd5e1; margin: 1em 0; }
.doc-content ul, .doc-content ol, .doc-body ul, .doc-body ol { padding-left: 1.8em; margin: .3em 0 .6em; }
.doc-content li.task, .doc-body li.task { list-style: none; position: relative; }
.doc-content li.task::before, .doc-body li.task::before { content: "☐"; position: absolute; left: -1.3em; }
.doc-content li.task.done::before, .doc-body li.task.done::before { content: "☑"; }
.doc-content li.task.done, .doc-body li.task.done { color: #64748b; text-decoration: line-through; }
.doc-content a, .doc-body a { color: #2563eb; }
.doc-content .page-break, .doc-body .page-break { break-after: page; page-break-after: always; height: 0; }
.doc-content .doc-math.block, .doc-body .doc-math.block { display: block; text-align: center; margin: .5em 0; }
.doc-content .doc-math-block, .doc-body .doc-math-block { position: relative; margin: .6em 0; }
.doc-content .doc-eqno, .doc-body .doc-eqno { position: absolute; right: 0; top: 50%; transform: translateY(-50%); }
.doc-content .doc-toc, .doc-body .doc-toc { border: 1px solid #e2e8f0; border-radius: 6px; padding: .6em 1em; margin: .8em 0; }
.doc-content .toc-title, .doc-body .toc-title { font-weight: 700; font-size: 1.15em; margin-bottom: .3em; }
.doc-content .toc-item, .doc-body .toc-item { display: flex; gap: .5em; color: inherit; text-decoration: none; padding: .1em 0; }
.doc-content .toc-item::after, .doc-body .toc-item::after { content: ""; flex: 1; order: 1; border-bottom: 1px dotted #94a3b8; margin-bottom: .35em; }
.doc-content .toc-item .toc-page, .doc-body .toc-item .toc-page { order: 2; }
.doc-content sup.doc-footnote-ref, .doc-body sup.doc-footnote-ref { color: #2563eb; }
.doc-content .doc-footnotes, .doc-body .doc-footnotes { font-size: .85em; color: #475569; border-top: 1px solid #cbd5e1; margin-top: 2em; padding-top: .5em; }
.doc-content figure, .doc-body figure { margin: .8em 0; text-align: center; }
.doc-content figcaption, .doc-body figcaption { font-size: .9em; color: #475569; }
.doc-content .tex-secnum, .doc-body .tex-secnum { margin-right: .6em; }
.doc-content .tex-title, .doc-body .tex-title { text-align: center; margin-bottom: 1.5em; }
.doc-content .tex-theorem, .doc-body .tex-theorem { margin: .6em 0; }
.doc-content .tex-author, .doc-content .tex-date, .doc-body .tex-author, .doc-body .tex-date { color: #475569; }
@media print { .doc-content .doc-toc { break-inside: avoid; } }
`

let cssInjected = false
function injectContentCSS() {
    if (cssInjected) return
    cssInjected = true
    document.head.append(h('style', DOC_CONTENT_CSS))
}

export function escapeHTML(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]) }
function decodeText(bytes) {
    if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return new TextDecoder().decode(bytes.subarray(3))
    if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder('utf-16le').decode(bytes.subarray(2))
    try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes) } catch { return new TextDecoder('gbk').decode(bytes) }
}
function formatHTML(html) {
    return html.replace(/(<\/(p|h\d|ul|ol|li|table|tr|blockquote|pre|div|figure)>)/g, '$1\n').replace(/(<(ul|ol|table|tbody|tr)[^>]*>)/g, '$1\n').replace(/\n{2,}/g, '\n').trim()
}
export { extOf, MM }
