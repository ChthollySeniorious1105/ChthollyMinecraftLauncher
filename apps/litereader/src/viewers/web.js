import { Viewer } from './base.js'
import { h, btn, clamp, debounce, togglePopover, segmented, menu, toast } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { decodeText, ENCODINGS } from '../core/encoding.js'
import { localDirURL, typeOf, dirName } from '../core/files.js'
import { readerPanel, readerColors, FONT_STACKS } from './reader-style.js'
import { DomFinder, findBar } from '../core/find.js'

// 网页查看器：HTML / XHTML / MHT(MHTML)
// 在禁用脚本的沙箱 iframe 中渲染；支持原始样式 / 阅读模式 / 源代码三种视图
export class WebViewer extends Viewer {
    view = 'page'
    zoomLevel = 1
    blobUrls = []

    async mount() {
        this.addTitle()
        this.tool('panel-left', '文档结构', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)

        this.zoomLabel = h('span.zoom-label.static', '100%')
        this.viewSeg = segmented([['page', '原始', 'globe'], ['read', '阅读', 'book-open-text'], ['source', '源码', 'code']], this.view, v => this.setView(v))
        this.center.append(this.viewSeg.el, h('span.v-sep'),
            btn('zoom-out', '缩小', () => this.setZoom(this.zoomLevel / 1.1)),
            this.zoomLabel,
            btn('zoom-in', '放大', () => this.setZoom(this.zoomLevel * 1.1)))
        this.encBtn = h('button.chip-btn', {
            title: '切换文本编码',
            onclick: e => togglePopover(e.currentTarget, () => menu(ENCODINGS.map(([v, label]) => ({
                label, checked: v === this.encoding, onclick: () => this.reload(v),
            })))),
        }, '编码')
        this.right.append(this.encBtn)
        this.tool('search', '查找 (Ctrl F)', () => this.find.open())
        this.styleBtn = this.tool('type', '阅读设置', e => togglePopover(e.currentTarget, () => readerPanel({ width: true })))
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        this.frame = h('iframe.web-frame', { sandbox: 'allow-same-origin', referrerpolicy: 'no-referrer' })
        this.find = findBar(() => this.finder)
        this.content.append(this.frame, this.find.el)

        const ld = this.loading('正在读取网页…')
        try {
            this.bytes = new Uint8Array(await this.source.arrayBuffer())
            await this.render()
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.listen(window, 'themechange', () => this.view === 'read' && this.render())
        this.onDispose(store.onSettings((_s, k) => {
            if (this.view === 'read' && (typeof k !== 'string' || k.startsWith('reader'))) this.render(true)
        }))
        this.onDispose(() => this.blobUrls.forEach(u => URL.revokeObjectURL(u)))
    }

    get isMht() { return ['mht', 'mhtml'].includes(this.source.ext) }

    // 解析原文：得到 HTML 字符串与资源基址
    parse() {
        if (this.parsed && this.parsed.enc === this.forceEncoding) return this.parsed
        const caveats = []
        let html, base = this.source.path ? localDirURL(this.source.path) : null, encoding
        if (this.isMht) {
            const r = parseMht(this.bytes, this.forceEncoding)
            this.blobUrls.forEach(u => URL.revokeObjectURL(u))
            this.blobUrls = r.urls
            html = r.html
            encoding = r.encoding
            base = null
            if (r.missing) caveats.push(`${r.missing} 个资源在归档中缺失`)
        } else {
            // 优先使用文件中声明的字符集
            const head = new TextDecoder('latin1').decode(this.bytes.subarray(0, 4096))
            const declared = /<meta[^>]+charset\s*=\s*["']?([\w-]+)/i.exec(head)?.[1]?.toLowerCase()
            const norm = declared && ({ gb2312: 'gb18030', gbk: 'gb18030', 'x-gbk': 'gb18030', utf8: 'utf-8' }[declared] ?? declared)
            let enc = this.forceEncoding ?? norm
            try { if (enc) new TextDecoder(enc) } catch { enc = undefined }
            const r = decodeText(this.bytes, enc)
            html = r.text
            encoding = r.encoding
        }
        if (/<script[\s>]/i.test(html)) caveats.push('网页脚本已禁用（交互内容、动态加载的内容不会显示）')
        if (/<(iframe|frame|embed|object)[\s>]/i.test(html)) caveats.push('嵌入的框架 / 插件内容可能无法显示')
        if (/(src|href)\s*=\s*["']?https?:/i.test(html)) caveats.push('网络资源已屏蔽，仅显示本地资源')
        this.parsed = { html, base, encoding, caveats, enc: this.forceEncoding }
        return this.parsed
    }

    async render(keepScroll = false) {
        const { html, base, encoding, caveats } = this.parse()
        this.encoding = encoding
        this.encBtn.textContent = (ENCODINGS.find(e => e[0] === encoding)?.[1] ?? encoding).split(' ')[0]
        const doc = new DOMParser().parseFromString(html, this.source.ext.startsWith('xht') && !/<html/i.test(html.slice(0, 200)) ? 'application/xhtml+xml' : 'text/html')
        if (doc.querySelector('parsererror')) return this.renderDoc(new DOMParser().parseFromString(html, 'text/html'), base, caveats, keepScroll)
        return this.renderDoc(doc, base, caveats, keepScroll)
    }

    async renderDoc(doc, base, caveats, keepScroll) {
        const title = doc.title?.trim()
        const text = doc.body?.textContent ?? ''
        this.setSubtitle(`${this.isMht ? 'MHT 网页归档' : '网页'}${title ? ' · ' + title : ''} · ${text.replace(/\s/g, '').length.toLocaleString()} 字`)
        sanitize(doc)
        const prevScroll = keepScroll ? this.frame.contentDocument?.scrollingElement?.scrollTop : null
        let out
        if (this.view === 'source') out = this.sourceDoc()
        else if (this.view === 'read') out = this.readerDoc(doc, base)
        else {
            if (base) doc.head.prepend(Object.assign(doc.createElement('base'), { href: base }))
            // 仅允许本地 / 内嵌资源，禁止网络请求与脚本
            const csp = doc.createElement('meta')
            csp.httpEquiv = 'Content-Security-Policy'
            csp.content = "default-src 'none'; img-src media: blob: data:; style-src media: blob: data: 'unsafe-inline'; font-src media: blob: data:; media-src media: blob: data:"
            doc.head.prepend(csp)
            out = '<!DOCTYPE html>' + doc.documentElement.outerHTML
        }
        this.setCaveats(this.view === 'source' ? [] : caveats)
        this.styleBtn.hidden = this.view !== 'read'
        await new Promise(resolve => {
            this.frame.onload = resolve
            this.frame.srcdoc = out
        })
        const fdoc = this.frame.contentDocument
        this.finder = new DomFinder(fdoc.body ?? fdoc.documentElement, { cls: 'lr-hit' })
        const hitStyle = fdoc.createElement('style')
        hitStyle.textContent = 'mark.lr-hit{background:#ffe066;color:inherit;border-radius:2px}mark.lr-hit.current{background:#ff9f1c}'
        fdoc.head?.append(hitStyle)
        this.applyZoom()
        this.bindFrame(fdoc)
        this.buildOutline(fdoc)
        if (prevScroll != null) fdoc.scrollingElement.scrollTop = prevScroll
        else this.restore()
    }

    // 阅读模式：去掉原有样式，套用阅读器排版
    readerDoc(doc, base) {
        const s = store.getSettings()
        const c = readerColors()
        doc.querySelectorAll('style, link[rel~="stylesheet"], nav, header > nav, footer, aside, form, button, input, select').forEach(e => e.remove())
        doc.querySelectorAll('[style]').forEach(e => e.removeAttribute('style'))
        doc.querySelectorAll('[class]').forEach(e => e.removeAttribute('class'))
        const main = doc.querySelector('article, main, [role="main"]') ?? doc.body
        const css = `
            html { background: color-mix(in srgb, ${c.paper} 88%, ${c.dark ? '#000' : '#888'}); }
            body { max-width: ${s.readerWidth}px; margin: 28px auto 60px; padding: 56px ${s.readerMargin}px; background: ${c.paper}; color: ${c.ink};
                font: ${s.readerFontSize}px/${s.readerLineHeight} ${FONT_STACKS[s.readerFont] ?? FONT_STACKS.serif}; text-align: ${s.readerJustify ? 'justify' : 'start'};
                border-radius: 6px; box-shadow: 0 6px 30px rgb(0 0 0 / .16); word-break: break-word; }
            a { color: ${c.link}; } img, video, svg { max-width: 100%; height: auto; }
            h1, h2, h3, h4 { line-height: 1.4; text-align: start; }
            pre, code { font-family: ${FONT_STACKS.mono}; font-size: .88em; }
            pre { padding: 14px 16px; border-radius: 8px; overflow: auto; background: color-mix(in srgb, ${c.ink} 6%, transparent); white-space: pre-wrap; }
            table { border-collapse: collapse; margin: 1em 0; } th, td { border: 1px solid color-mix(in srgb, ${c.ink} 18%, transparent); padding: 6px 10px; }
            blockquote { margin: 1em 0; padding: .2em 1em; border-left: 3px solid ${c.link}; opacity: .85; }
            ::selection { background: ${c.selection}; }`
        return `<!DOCTYPE html><html><head><meta charset="utf-8">${base ? `<base href="${base}">` : ''}
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src media: blob: data:; style-src 'unsafe-inline'; media-src media: blob: data:">
            <title>${escapeText(doc.title)}</title><style>${css}</style></head><body>${main.innerHTML}</body></html>`
    }

    sourceDoc() {
        const { html } = this.parse()
        const c = readerColors()
        const lines = html.split(/\r?\n/)
        const esc = lines.map((l, i) => `<tr><td class="n">${i + 1}</td><td>${highlightHtml(l)}</td></tr>`).join('')
        return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
            body { margin: 0; background: ${c.paper}; color: ${c.ink}; font: 13px/1.6 ${FONT_STACKS.mono}; }
            table { border-collapse: collapse; width: 100%; } td { vertical-align: top; white-space: pre-wrap; word-break: break-all; padding: 0 12px; }
            td.n { width: 1%; white-space: nowrap; text-align: right; opacity: .4; user-select: none; border-right: 1px solid color-mix(in srgb, ${c.ink} 12%, transparent); }
            .t { color: ${c.dark ? '#7cc4ff' : '#1d4ed8'}; } .a { color: ${c.dark ? '#f0b86e' : '#b45309'}; } .v { color: ${c.dark ? '#9ee29e' : '#15803d'}; } .c { opacity: .5; font-style: italic; }
        </style></head><body><table>${esc}</table></body></html>`
    }

    bindFrame(fdoc) {
        fdoc.addEventListener('click', e => {
            const a = e.target.closest?.('a[href]')
            if (!a) return
            e.preventDefault()
            const href = a.getAttribute('href')
            if (href.startsWith('#')) {
                const id = decodeURIComponent(href.slice(1))
                fdoc.getElementById(id)?.scrollIntoView({ behavior: 'smooth' }) ?? fdoc.querySelector(`a[name="${CSS.escape(id)}"]`)?.scrollIntoView({ behavior: 'smooth' })
                return
            }
            if (/^(https?:|mailto:)/i.test(href)) return window.lite.openExternal(href)
            // 本地相对链接：在 LiteReader 中打开受支持的文件
            if (this.source.path && !/^[a-z]+:/i.test(href)) {
                const target = dirName(this.source.path) + '\\' + decodeURIComponent(href.split('#')[0].split('?')[0]).replace(/\//g, '\\')
                if (typeOf(target)) this.app.openPaths([target])
                else toast('不支持打开此链接：' + href, 'warn')
            }
        })
        fdoc.addEventListener('keydown', e => {
            // iframe 中的快捷键转交给主界面
            if (e.ctrlKey || ['F11', 'Escape', 'F5'].includes(e.key)) {
                const ev = new KeyboardEvent('keydown', { key: e.key, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, altKey: e.altKey, bubbles: true, cancelable: true })
                if (!document.dispatchEvent(ev)) e.preventDefault()
            }
        })
        fdoc.addEventListener('wheel', e => {
            if (!e.ctrlKey) return
            e.preventDefault()
            this.setZoom(this.zoomLevel * (e.deltaY < 0 ? 1.1 : 1 / 1.1))
        }, { passive: false })
        fdoc.addEventListener('scroll', () => this.saveProgress(), { passive: true })
        fdoc.addEventListener('contextmenu', e => e.stopPropagation())
    }

    buildOutline(fdoc) {
        this.sidebar.replaceChildren()
        const panel = h('div.toc-panel.outline', h('div.sb-caption', icon('list-tree', 15), '文档结构'))
        const heads = this.view === 'source' ? [] : [...fdoc.querySelectorAll('h1, h2, h3, h4, h5, h6')].filter(e => e.textContent.trim()).slice(0, 1000)
        if (!heads.length) panel.append(h('div.empty-mini', this.view === 'source' ? '源码视图没有结构' : '网页中没有标题'))
        const min = Math.min(...heads.map(e => Number(e.tagName[1])))
        const ol = h('ol')
        for (const el of heads) {
            const lvl = Number(el.tagName[1]) - min + 1
            ol.append(h('li', h('a', {
                style: { paddingInlineStart: `${(lvl - 1) * 16 + 12}px` },
                onclick: () => el.scrollIntoView({ behavior: 'smooth', block: 'start' }),
            }, el.textContent.trim().replace(/\s+/g, ' ').slice(0, 80))))
        }
        panel.append(ol)
        this.sidebar.append(panel)
    }

    setView(v) {
        this.view = v
        this.viewSeg.set(v)
        this.render(false)
    }

    async reload(enc) {
        this.forceEncoding = enc
        await this.render(true)
        toast(`已切换为 ${enc.toUpperCase()} 编码`, 'success')
    }

    setZoom(z) {
        this.zoomLevel = clamp(z, 0.3, 4)
        this.applyZoom()
        this.saveProgress()
    }
    applyZoom() {
        this.zoomLabel.textContent = Math.round(this.zoomLevel * 100) + '%'
        const root = this.frame.contentDocument?.documentElement
        if (root) root.style.zoom = this.zoomLevel
    }

    get scrollEl() { return this.frame.contentDocument?.scrollingElement }

    restore() {
        const p = store.getProgress(this.source.key)
        if (p?.zoom) { this.zoomLevel = p.zoom; this.applyZoom() }
        const sc = this.scrollEl
        if (p?.pos && sc) requestAnimationFrame(() => { sc.scrollTop = p.pos * (sc.scrollHeight - sc.clientHeight) })
    }

    saveProgress = debounce(() => {
        const sc = this.scrollEl
        if (!sc) return
        const max = sc.scrollHeight - sc.clientHeight
        const pos = max > 0 ? sc.scrollTop / max : 0
        store.setProgress(this.source.key, { pos, zoom: this.zoomLevel })
        this.app.updateRecentProgress(this.source, pos)
    }, 400)

    onKey(e) {
        const k = e.key
        const sc = this.scrollEl
        if (e.ctrlKey && k.toLowerCase() === 'f') { this.find.open(); return true }
        if (e.ctrlKey && (k === '=' || k === '+')) { this.setZoom(this.zoomLevel * 1.1); return true }
        if (e.ctrlKey && k === '-') { this.setZoom(this.zoomLevel / 1.1); return true }
        if (e.ctrlKey && k === '0') { this.setZoom(1); return true }
        if (e.ctrlKey && k.toLowerCase() === 'u') { this.setView(this.view === 'source' ? 'page' : 'source'); return true }
        if (!sc) return false
        if (k === 'PageDown' || k === ' ') { sc.scrollBy({ top: sc.clientHeight * 0.9, behavior: 'smooth' }); return true }
        if (k === 'PageUp') { sc.scrollBy({ top: -sc.clientHeight * 0.9, behavior: 'smooth' }); return true }
        if (k === 'Home') { sc.scrollTo({ top: 0 }); return true }
        if (k === 'End') { sc.scrollTo({ top: sc.scrollHeight }); return true }
        return false
    }

    destroy() {
        this.saveProgress()
        super.destroy()
    }
}

// 移除脚本与事件处理器
export function sanitize(doc) {
    doc.querySelectorAll('script, noscript, meta[http-equiv="refresh" i], base, meta[http-equiv="Content-Security-Policy" i]').forEach(e => e.remove())
    for (const el of doc.querySelectorAll('*')) {
        for (const a of [...el.attributes]) {
            if (/^on/i.test(a.name)) el.removeAttribute(a.name)
            else if (/^(href|src|action|formaction|xlink:href)$/i.test(a.name) && /^\s*javascript:/i.test(a.value)) el.removeAttribute(a.name)
        }
    }
}

const escapeText = s => String(s ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c])

// 简易 HTML 源码高亮（按行处理）
function highlightHtml(line) {
    const e = escapeText(line)
    return e
        .replace(/(&lt;!--.*?(--&gt;|$))/g, '<span class="c">$1</span>')
        .replace(/(&lt;\/?)([\w:-]+)((?:\s+[\w:-]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s&]+))?)*)(\s*\/?&gt;)?/g, (m, open, tag, attrs, close) => {
            if (m.includes('class="c"')) return m
            const at = attrs.replace(/([\w:-]+)(\s*=\s*)("[^"]*"|'[^']*'|[^\s]+)?/g, (_m, n, eq, v) => `<span class="a">${n}</span>${eq}${v ? `<span class="v">${v}</span>` : ''}`)
            return `<span class="t">${open}${tag}</span>${at}${close ? `<span class="t">${close}</span>` : ''}`
        })
}

// ---------- MHT(MHTML) 解析 ----------
export function parseMht(bytes, forceEnc) {
    const raw = new TextDecoder('latin1').decode(bytes)
    const headEnd = raw.search(/\r?\n\r?\n/)
    const topHead = raw.slice(0, headEnd)
    const boundary = /boundary\s*=\s*"?([^";\r\n]+)"?/i.exec(unfold(topHead))?.[1]
    const parts = []
    if (!boundary) parts.push(parsePart(raw))
    else {
        for (const chunk of raw.split('--' + boundary).slice(1)) {
            if (chunk.startsWith('--')) break
            parts.push(parsePart(chunk.replace(/^\r?\n/, '')))
        }
    }
    const byLoc = new Map()
    const urls = []
    let htmlPart = null
    for (const p of parts) {
        if (!p) continue
        if (!htmlPart && /text\/html/i.test(p.type)) { htmlPart = p; continue }
        const blob = new Blob([p.data], { type: p.type.split(';')[0] || 'application/octet-stream' })
        const url = URL.createObjectURL(blob)
        urls.push(url)
        if (p.location) byLoc.set(p.location, url)
        if (p.cid) byLoc.set('cid:' + p.cid, url)
    }
    if (!htmlPart) throw new Error('MHT 文件中没有找到网页内容')
    const charset = /charset\s*=\s*"?([\w-]+)/i.exec(htmlPart.type)?.[1]?.toLowerCase()
    const enc = forceEnc ?? (charset ? ({ gb2312: 'gb18030', gbk: 'gb18030' }[charset] ?? charset) : undefined)
    const { text, encoding } = decodeText(htmlPart.data, enc)
    // 替换资源引用为 blob 地址（包括 CSS 中的 url()）
    let missing = 0
    const baseLoc = htmlPart.location
    const resolve = ref => {
        if (!ref || /^(data|blob|#)/i.test(ref)) return null
        if (byLoc.has(ref)) return byLoc.get(ref)
        try {
            const abs = new URL(ref, baseLoc || 'http://mht.local/').href
            if (byLoc.has(abs)) return byLoc.get(abs)
        } catch { /* ignore */ }
        return undefined
    }
    const html = text
        .replace(/(\b(?:src|href|background|poster)\s*=\s*)(["'])([^"']*)\2/gi, (m, pre, q, ref) => {
            const u = resolve(ref)
            if (u === undefined && /\.(png|jpe?g|gif|webp|svg|css|bmp)(\?|$)/i.test(ref)) missing++
            return u ? `${pre}${q}${u}${q}` : m
        })
        .replace(/url\(\s*(["']?)([^"')]+)\1\s*\)/gi, (m, q, ref) => {
            const u = resolve(ref)
            return u ? `url(${q}${u}${q})` : m
        })
    return { html, urls, encoding, missing }
}

const unfold = s => s.replace(/\r?\n[ \t]+/g, ' ')

function parsePart(chunk) {
    const idx = chunk.search(/\r?\n\r?\n/)
    if (idx < 0) return null
    const head = unfold(chunk.slice(0, idx))
    const body = chunk.slice(idx).replace(/^\r?\n\r?\n/, '').replace(/\r?\n$/, '')
    const hv = n => new RegExp(`^${n}\\s*:\\s*(.+)$`, 'im').exec(head)?.[1]?.trim()
    const type = hv('Content-Type') ?? 'text/html'
    const te = (hv('Content-Transfer-Encoding') ?? '').toLowerCase()
    let data
    if (te === 'base64') {
        const b = atob(body.replace(/[^A-Za-z0-9+/=]/g, ''))
        data = Uint8Array.from(b, c => c.charCodeAt(0))
    } else if (te === 'quoted-printable') {
        const s = body.replace(/=\r?\n/g, '')
        const out = []
        for (let i = 0; i < s.length; i++) {
            if (s[i] === '=' && /^[0-9A-F]{2}$/i.test(s.slice(i + 1, i + 3))) { out.push(parseInt(s.slice(i + 1, i + 3), 16)); i += 2 }
            else out.push(s.charCodeAt(i) & 255)
        }
        data = new Uint8Array(out)
    } else data = Uint8Array.from(body, c => c.charCodeAt(0) & 255)
    return { type, data, location: hv('Content-Location'), cid: hv('Content-ID')?.replace(/^<|>$/g, '') }
}

