// 其他文档格式解码：旧版 PPT、RTF、ODT / ODP、OFD、XPS / OXPS
// 统一输出：{ kind: 'flow', html } 回流文档；{ kind: 'pages', pages: [{ w, h, render() }] } 固定版式；
// { kind: 'slides', slides: [{ title, text }] } 纯文本幻灯片。所有结果都带 caveats（近似显示说明）
import JSZip from 'jszip'

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
const parseXML = s => new DOMParser().parseFromString(s, 'application/xml')
const local = (el, name) => el ? [...el.children].filter(c => c.localName === name) : []
const first = (el, name) => el ? [...el.children].find(c => c.localName === name) ?? null : null
const all = (el, name) => el ? [...el.getElementsByTagName('*')].filter(c => c.localName === name) : []

// ---------- 旧版 PowerPoint（.ppt / .pps，二进制）：提取每张幻灯片的文字 ----------
export async function decodePpt(buf) {
    const XLSX = await import('xlsx')
    const cfb = XLSX.CFB.read(new Uint8Array(buf), { type: 'array' })
    const stream = XLSX.CFB.find(cfb, 'PowerPoint Document')
    if (!stream) throw new Error('不是有效的 PowerPoint 97-2003 文件')
    const data = stream.content instanceof Uint8Array ? stream.content : new Uint8Array(stream.content)
    const dv = new DataView(data.buffer, data.byteOffset, data.byteLength)
    const slides = []
    let cur = null
    const utf16 = new TextDecoder('utf-16le')
    const latin = new TextDecoder('windows-1252')
    // 记录结构：recVer/Instance(2) recType(2) recLen(4)
    const walk = (start, end, depth) => {
        let p = start
        while (p + 8 <= end) {
            const verInst = dv.getUint16(p, true)
            const type = dv.getUint16(p + 2, true)
            const len = dv.getUint32(p + 4, true)
            const body = p + 8
            if (body + len > end || len < 0) break
            const container = (verInst & 0xf) === 0xf
            // SlideListWithText 中的 SlidePersistAtom（0x03F3）标记新幻灯片
            if (type === 0x03f3) { cur = { texts: [], title: '' }; slides.push(cur) }
            else if (type === 0x0f9f) cur && (cur.lastType = dv.getUint32(body, true)) // TextHeaderAtom
            else if (type === 0x0fa0 || type === 0x0fa8) {
                const text = (type === 0x0fa0 ? utf16 : latin).decode(data.subarray(body, body + len)).replace(/\r/g, '\n').replace(/\u000b/g, '\n').trim()
                if (text && cur) {
                    // 文本类型 0 = 标题，6 = 居中标题
                    if ((cur.lastType === 0 || cur.lastType === 6) && !cur.title) cur.title = text
                    else cur.texts.push(text)
                } else if (text && !cur) {
                    cur = { texts: [text], title: '' }
                    slides.push(cur)
                }
            }
            if (container && depth < 16) walk(body, body + len, depth + 1)
            p = body + len
        }
    }
    walk(0, data.length, 0)
    const out = slides.filter(s => s.title || s.texts.length).map(s => ({ title: s.title, text: s.texts.join('\n\n') }))
    return {
        kind: 'slides',
        slides: out,
        caveats: ['旧版 PPT 仅提取文字内容（版式、图片与形状不显示），建议另存为 .pptx 获得完整效果'],
    }
}

// ---------- RTF ----------
export async function decodeRtf(buf) {
    const { RTFJS, EMFJS, WMFJS } = await import('rtf.js')
    RTFJS.loggingEnabled(false)
    WMFJS.loggingEnabled(false)
    EMFJS.loggingEnabled(false)
    const doc = new RTFJS.Document(buf)
    const els = await doc.render()
    const box = document.createElement('div')
    box.append(...els)
    const caveats = []
    if (box.querySelector('[data-unsupported], .rtf-unsupported')) caveats.push('部分 RTF 对象无法显示')
    return { kind: 'flow', html: box.innerHTML, meta: doc.metadata?.() ?? {}, caveats, keepStyle: true }
}

// ---------- OpenDocument（.odt / .odp / .ods 的文字部分）----------
export async function decodeOdf(buf) {
    const zip = await JSZip.loadAsync(buf)
    const content = await zip.file('content.xml')?.async('string')
    if (!content) throw new Error('不是有效的 OpenDocument 文件')
    const styles = await zip.file('styles.xml')?.async('string')
    const doc = parseXML(content)
    const caveats = new Set()
    const urls = []
    const media = async href => {
        const f = zip.file(href.replace(/^\.\//, ''))
        if (!f) return null
        const ext = href.split('.').pop().toLowerCase()
        const type = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', svg: 'image/svg+xml', bmp: 'image/bmp', webp: 'image/webp' }[ext]
        if (!type) { caveats.add('部分嵌入对象（如 WMF / EMF / OLE）无法显示'); return null }
        const u = URL.createObjectURL(new Blob([await f.async('uint8array')], { type }))
        urls.push(u)
        return u
    }
    // 自动样式：粗体 / 斜体 / 下划线 / 颜色 / 字号 / 对齐
    const styleMap = {}
    const readStyles = xml => {
        if (!xml) return
        for (const st of all(parseXML(xml).documentElement, 'style')) {
            const name = st.getAttribute('style:name')
            const css = []
            const tp = first(st, 'text-properties'), pp = first(st, 'paragraph-properties')
            if (tp) {
                if (tp.getAttribute('fo:font-weight') === 'bold') css.push('font-weight:700')
                if (tp.getAttribute('fo:font-style') === 'italic') css.push('font-style:italic')
                const u = tp.getAttribute('style:text-underline-style')
                if (u && u !== 'none') css.push('text-decoration:underline')
                const lt = tp.getAttribute('style:text-line-through-style')
                if (lt && lt !== 'none') css.push('text-decoration:line-through')
                const col = tp.getAttribute('fo:color')
                if (col) css.push('color:' + col)
                const bg = tp.getAttribute('fo:background-color')
                if (bg && bg !== 'transparent') css.push('background:' + bg)
                const fs = tp.getAttribute('fo:font-size')
                if (fs && !fs.endsWith('%')) css.push('font-size:' + fs)
                const pos = tp.getAttribute('style:text-position')
                if (pos?.startsWith('super')) css.push('vertical-align:super;font-size:.7em')
                if (pos?.startsWith('sub')) css.push('vertical-align:sub;font-size:.7em')
            }
            if (pp) {
                const al = pp.getAttribute('fo:text-align')
                if (al) css.push('text-align:' + ({ start: 'left', end: 'right' }[al] ?? al))
                const ml = pp.getAttribute('fo:margin-left')
                if (ml && parseFloat(ml)) css.push('margin-left:' + ml)
            }
            styleMap[name] = { css: css.join(';'), parent: st.getAttribute('style:parent-style-name'), display: st.getAttribute('style:display-name') ?? name }
        }
    }
    readStyles(styles)
    readStyles(content)
    const cssOf = name => {
        const out = []
        for (let s = styleMap[name], guard = 0; s && guard < 10; s = styleMap[s.parent], guard++) if (s.css) out.unshift(s.css)
        return out.join(';')
    }
    const headingOf = name => {
        for (let s = styleMap[name], guard = 0; s && guard < 10; s = styleMap[s.parent], guard++) {
            const m = /^heading[ _]?(\d)|^标题[ _]?(\d)/i.exec(s.display ?? '')
            if (m) return Number(m[1] ?? m[2])
            if (/^title$/i.test(s.display)) return 1
        }
        return 0
    }

    const conv = async el => {
        let out = ''
        for (const n of el.childNodes) {
            if (n.nodeType === 3) { out += esc(n.nodeValue); continue }
            if (n.nodeType !== 1) continue
            const tag = n.localName
            const st = n.getAttribute('text:style-name') ?? n.getAttribute('table:style-name') ?? n.getAttribute('draw:style-name')
            const style = st ? cssOf(st) : ''
            const sa = style ? ` style="${esc(style)}"` : ''
            switch (tag) {
                case 'h': {
                    const lvl = Math.min(6, Number(n.getAttribute('text:outline-level') ?? 1))
                    out += `<h${lvl}${sa}>${await conv(n)}</h${lvl}>`
                    break
                }
                case 'p': {
                    const lvl = st ? headingOf(st) : 0
                    const inner = await conv(n)
                    out += lvl ? `<h${lvl}${sa}>${inner}</h${lvl}>` : `<p${sa}>${inner || '<br>'}</p>`
                    break
                }
                case 'span': out += `<span${sa}>${await conv(n)}</span>`; break
                case 'a': out += `<a href="${esc(n.getAttribute('xlink:href') ?? '#')}">${await conv(n)}</a>`; break
                case 's': out += '&nbsp;'.repeat(Number(n.getAttribute('text:c') ?? 1)); break
                case 'tab': out += '&emsp;'; break
                case 'line-break': out += '<br>'; break
                case 'list': out += `<ul>${await conv(n)}</ul>`; break
                case 'list-item': case 'list-header': out += `<li>${await conv(n)}</li>`; break
                case 'table': out += `<table class="odf-table">${await conv(n)}</table>`; break
                case 'table-header-rows': case 'table-rows': case 'table-row-group': out += await conv(n); break
                case 'table-row': out += `<tr>${await conv(n)}</tr>`; break
                case 'table-cell': {
                    const cs = n.getAttribute('table:number-columns-spanned'), rs = n.getAttribute('table:number-rows-spanned')
                    out += `<td${cs > 1 ? ` colspan="${cs}"` : ''}${rs > 1 ? ` rowspan="${rs}"` : ''}${sa}>${await conv(n)}</td>`
                    break
                }
                case 'covered-table-cell': case 'table-column': case 'table-columns': break
                case 'note': {
                    const cit = all(n, 'note-citation')[0]?.textContent ?? '*'
                    const body = first(n, 'note-body')
                    out += `<sup class="odf-note" title="${esc(body?.textContent.trim() ?? '')}">${esc(cit)}</sup>`
                    break
                }
                case 'frame': {
                    const img = first(n, 'image')
                    const href = img?.getAttribute('xlink:href')
                    const w = n.getAttribute('svg:width')
                    if (href) {
                        const u = await media(href)
                        if (u) out += `<img src="${u}" style="max-width:100%;${w ? 'width:' + w : ''}">`
                    } else out += await conv(n)
                    break
                }
                case 'text-box': out += await conv(n); break
                case 'custom-shape': case 'rect': case 'ellipse': case 'line': case 'connector': case 'g':
                    caveats.add('绘图形状仅显示其中的文字')
                    out += await conv(n)
                    break
                case 'sequence-decls': case 'tracked-changes': case 'soft-page-break': case 'bookmark': case 'bookmark-start': case 'bookmark-end': case 'annotation': case 'forms': break
                case 'table-of-content': out += await conv(first(n, 'index-body') ?? n); break
                case 'index-title': out += await conv(n); break
                case 'section': case 'index-body': out += await conv(n); break
                default: out += await conv(n)
            }
        }
        return out
    }

    const body = first(first(doc.documentElement, 'body'), 'text') ?? first(first(doc.documentElement, 'body'), 'presentation') ?? first(doc.documentElement, 'body')
    const isPres = body?.localName === 'presentation'
    if (isPres) {
        // 演示文稿：每页转为一个区块
        const slides = []
        for (const page of local(body, 'page')) {
            const title = page.getAttribute('draw:name') ?? ''
            const frames = local(page, 'frame')
            const html = []
            let heading = ''
            for (const f of frames) {
                const cls = f.getAttribute('presentation:class')
                const inner = await conv(f)
                if (cls === 'title' && !heading) heading = inner.replace(/<\/?p[^>]*>/g, '')
                else if (cls !== 'page-number' && cls !== 'footer' && cls !== 'date-time') html.push(inner)
            }
            for (const g of local(page, 'custom-shape').concat(local(page, 'g'))) html.push(await conv(g))
            slides.push({ title: stripHtml(heading) || title, html: html.join('') })
        }
        caveats.add('ODP 以文字大纲形式显示（版式与动画不保留）')
        return { kind: 'slides', slides: slides.map(s => ({ title: s.title, text: stripHtml(s.html), html: s.html })), caveats: [...caveats], urls }
    }
    const html = await conv(body)
    const meta = await zip.file('meta.xml')?.async('string')
    const title = meta ? all(parseXML(meta).documentElement, 'title')[0]?.textContent : null
    return { kind: 'flow', html, title, caveats: [...caveats], urls, keepStyle: true }
}

const stripHtml = s => s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim()

// ---------- OFD（国标版式文档 GB/T 33190）----------
export async function decodeOfd(buf) {
    const zip = await JSZip.loadAsync(buf)
    const read = async p => {
        const f = zip.file(p.replace(/^\//, '')) ?? zip.file(Object.keys(zip.files).find(k => k.toLowerCase() === p.replace(/^\//, '').toLowerCase()) ?? '')
        return f ? parseXML(await f.async('string')) : null
    }
    const ofd = await read('OFD.xml')
    if (!ofd) throw new Error('不是有效的 OFD 文件')
    const docRoot = all(ofd.documentElement, 'DocRoot')[0]?.textContent.trim()
    const docPath = docRoot.replace(/^\//, '')
    const docDir = docPath.replace(/[^/]*$/, '')
    const doc = await read(docPath)
    const caveats = new Set()
    const urls = []
    const resolve = (base, p) => {
        if (!p) return null
        if (p.startsWith('/')) return p.slice(1)
        const parts = (base + p).split('/')
        const out = []
        for (const s of parts) { if (s === '..') out.pop(); else if (s && s !== '.') out.push(s) }
        return out.join('/')
    }
    // 资源：字体、图片、绘制参数
    const res = { fonts: {}, media: {}, params: {} }
    const loadRes = async (path, base) => {
        const x = path && await read(path)
        if (!x) return
        const baseLoc = resolve(base, x.documentElement.getAttribute('BaseLoc') ?? '') ?? base
        const bdir = baseLoc && !baseLoc.endsWith('/') ? baseLoc + '/' : baseLoc
        for (const f of all(x.documentElement, 'Font')) res.fonts[f.getAttribute('ID')] = f.getAttribute('FamilyName') || f.getAttribute('FontName')
        for (const m of all(x.documentElement, 'MultiMedia')) {
            const file = all(m, 'MediaFile')[0]?.textContent.trim()
            res.media[m.getAttribute('ID')] = resolve(bdir, file)
        }
        for (const d of all(x.documentElement, 'DrawParam')) res.params[d.getAttribute('ID')] = d
    }
    const common = first(doc.documentElement, 'CommonData')
    for (const r of [...local(common, 'PublicRes'), ...local(common, 'DocumentRes')]) await loadRes(resolve(docDir, r.textContent.trim()), docDir)
    const mediaUrl = async id => {
        const p = res.media[id]
        if (!p) return null
        const f = zip.file(p)
        if (!f) return null
        const ext = p.split('.').pop().toLowerCase()
        const type = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', bmp: 'image/bmp', gif: 'image/gif', tif: 'image/tiff', tiff: 'image/tiff', svg: 'image/svg+xml' }[ext] ?? 'image/png'
        if (/tiff?|jb2/.test(ext)) caveats.add('部分 TIFF / JBIG2 图片无法显示')
        const u = URL.createObjectURL(new Blob([await f.async('uint8array')], { type }))
        urls.push(u)
        return u
    }
    const box = s => (s ?? '0 0 210 297').trim().split(/[\s,]+/).map(Number)
    const pageArea = first(common, 'PageArea')
    const defBox = box(first(pageArea, 'PhysicalBox')?.textContent)
    const templates = {}
    for (const t of local(common, 'TemplatePage')) templates[t.getAttribute('ID')] = resolve(docDir, t.getAttribute('BaseLoc'))

    const pages = local(first(doc.documentElement, 'Pages'), 'Page').map((p, i) => {
        const loc = resolve(docDir, p.getAttribute('BaseLoc'))
        return {
            index: i,
            async load() {
                const px = await read(loc)
                const area = first(px.documentElement, 'Area')
                const b = area ? box(first(area, 'PhysicalBox')?.textContent) : defBox
                this.w = b[2]; this.h = b[3]
                this.doc = px
                this.base = loc.replace(/[^/]*$/, '')
                return this
            },
            async render() {
                if (!this.doc) await this.load()
                const parts = []
                const tpl = first(this.doc.documentElement, 'Template')
                if (tpl && templates[tpl.getAttribute('TemplateID')]) {
                    const tdoc = await read(templates[tpl.getAttribute('TemplateID')])
                    if (tdoc) parts.push(await ofdContent(tdoc.documentElement, this.base))
                }
                parts.push(await ofdContent(this.doc.documentElement, this.base))
                return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${this.w} ${this.h}" width="${this.w}mm" height="${this.h}mm">${parts.join('')}</svg>`
            },
        }
    })
    // 预读首页尺寸
    for (const p of pages.slice(0, 1)) await p.load()
    for (const p of pages) { p.w ??= defBox[2]; p.h ??= defBox[3] }

    const color = el => {
        const v = el?.getAttribute('Value')
        if (!v) return null
        const n = v.trim().split(/\s+/).map(Number)
        const a = el.getAttribute('Alpha')
        return n.length >= 3 ? `rgba(${n[0]},${n[1]},${n[2]},${a != null ? Number(a) / 255 : 1})` : `rgb(${n[0]},${n[0]},${n[0]})`
    }
    const ctm = el => {
        const c = el.getAttribute('CTM')
        return c ? ` transform="matrix(${c.trim().split(/\s+/).join(' ')})"` : ''
    }
    const abbrev = d => {
        // OFD AbbreviatedData → SVG path
        const t = d.trim().split(/\s+/)
        const out = []
        for (let i = 0; i < t.length;) {
            const op = t[i++]
            const nums = n => t.slice(i, i += n).join(',')
            if (op === 'M' || op === 'S') out.push('M' + nums(2))
            else if (op === 'L') out.push('L' + nums(2))
            else if (op === 'B') out.push('C' + nums(6))
            else if (op === 'Q') out.push('Q' + nums(4))
            else if (op === 'A') out.push('A' + nums(7))
            else if (op === 'C') out.push('Z')
            else if (!isNaN(Number(op))) { out.push(op) }
        }
        return out.join(' ')
    }
    async function ofdContent(root, base) {
        const out = []
        const layers = all(root, 'Layer')
        for (const layer of layers) {
            const dp = res.params[layer.getAttribute('DrawParam')]
            for (const obj of layer.children) out.push(await ofdObject(obj, dp))
        }
        return out.join('')
    }
    async function ofdObject(obj, dp) {
        const bx = box(obj.getAttribute('Boundary'))
        const tr = `translate(${bx[0]},${bx[1]})`
        const fillC = color(first(obj, 'FillColor')) ?? color(first(dp, 'FillColor'))
        const strokeC = color(first(obj, 'StrokeColor')) ?? color(first(dp, 'StrokeColor'))
        switch (obj.localName) {
            case 'TextObject': {
                const size = Number(obj.getAttribute('Size') ?? 3.5)
                const font = res.fonts[obj.getAttribute('Font')] ?? 'SimSun'
                const bold = Number(obj.getAttribute('Weight') ?? 400) >= 700 || obj.getAttribute('Bold') === 'true'
                const italic = obj.getAttribute('Italic') === 'true'
                const spans = []
                for (const tc of local(obj, 'TextCode')) {
                    const text = tc.textContent
                    let x = Number(tc.getAttribute('X') ?? 0), y = Number(tc.getAttribute('Y') ?? 0)
                    const dx = (tc.getAttribute('DeltaX') ?? '').trim()
                    const xs = [x]
                    if (dx) {
                        const t = dx.split(/\s+/)
                        for (let i = 0; i < t.length && xs.length < text.length;) {
                            if (t[i] === 'g') { const n = Number(t[i + 1]), d = Number(t[i + 2]); for (let k = 0; k < n && xs.length < text.length; k++) xs.push(xs.at(-1) + d); i += 3 }
                            else { xs.push(xs.at(-1) + Number(t[i])); i++ }
                        }
                    }
                    spans.push(`<text x="${xs.join(' ')}" y="${y}">${esc(text)}</text>`)
                }
                return `<g transform="${tr}"${''} font-size="${size}" font-family="${esc(font)}, SimSun, 'Microsoft YaHei', serif" fill="${fillC ?? '#000'}"${bold ? ' font-weight="700"' : ''}${italic ? ' font-style="italic"' : ''}><g${ctm(obj)}>${spans.join('')}</g></g>`
            }
            case 'PathObject': {
                const d = first(obj, 'AbbreviatedData')?.textContent ?? ''
                const doFill = obj.getAttribute('Fill') === 'true'
                const doStroke = obj.getAttribute('Stroke') !== 'false'
                const lw = obj.getAttribute('LineWidth') ?? dp?.getAttribute('LineWidth') ?? 0.353
                return `<g transform="${tr}"><path${ctm(obj)} d="${abbrev(d)}" fill="${doFill ? fillC ?? '#000' : 'none'}" stroke="${doStroke ? strokeC ?? '#000' : 'none'}" stroke-width="${lw}"/></g>`
            }
            case 'ImageObject': {
                const u = await mediaUrl(obj.getAttribute('ResourceID'))
                if (!u) return ''
                const c = (obj.getAttribute('CTM') ?? `${bx[2]} 0 0 ${bx[3]} 0 0`).trim().split(/\s+/).map(Number)
                return `<g transform="${tr}"><image href="${u}" x="0" y="0" width="1" height="1" preserveAspectRatio="none" transform="matrix(${c.join(' ')})"/></g>`
            }
            case 'PageBlock': case 'CompositeObject': {
                const inner = []
                for (const ch of obj.children) inner.push(await ofdObject(ch, dp))
                return `<g>${inner.join('')}</g>`
            }
            default: return ''
        }
    }
    const sig = Object.keys(zip.files).some(k => /Signs?\//i.test(k))
    if (sig) caveats.add('电子签章 / 数字签名未验证，仅显示页面内容')
    caveats.add('OFD 使用系统字体近似显示，嵌入字体不加载')
    return { kind: 'pages', pages, caveats: [...caveats], urls, unit: 'mm' }
}

// ---------- XPS / OXPS ----------
export async function decodeXps(buf) {
    const zip = await JSZip.loadAsync(buf)
    const find = p => zip.file(p.replace(/^\//, '')) ?? zip.file(Object.keys(zip.files).find(k => k.toLowerCase() === p.replace(/^\//, '').toLowerCase()) ?? '')
    const readX = async p => { const f = find(p); return f ? parseXML(await f.async('string')) : null }
    const resolve = (base, p) => {
        if (p.startsWith('/')) return p.slice(1)
        const parts = (base.replace(/[^/]*$/, '') + p).split('/')
        const out = []
        for (const s of parts) { if (s === '..') out.pop(); else if (s && s !== '.') out.push(s) }
        return out.join('/')
    }
    const rels = await readX('_rels/.rels')
    const seqRel = [...(rels?.documentElement.children ?? [])].find(r => /fixedrepresentation/i.test(r.getAttribute('Type')))
    const seqPath = seqRel ? seqRel.getAttribute('Target').replace(/^\//, '') : Object.keys(zip.files).find(k => /\.fdseq$/i.test(k))
    const seq = await readX(seqPath)
    if (!seq) throw new Error('不是有效的 XPS 文件')
    const caveats = new Set(['XPS 使用系统字体近似显示，嵌入的混淆字体不加载'])
    const urls = []
    const pages = []
    for (const dr of all(seq.documentElement, 'DocumentReference')) {
        const docPath = resolve(seqPath, dr.getAttribute('Source'))
        const fdoc = await readX(docPath)
        for (const pc of all(fdoc?.documentElement, 'PageContent')) {
            const pagePath = resolve(docPath, pc.getAttribute('Source'))
            pages.push({
                w: Number(pc.getAttribute('Width') ?? 816), h: Number(pc.getAttribute('Height') ?? 1056),
                async render() {
                    const px = await readX(pagePath)
                    const root = px.documentElement
                    this.w = Number(root.getAttribute('Width') ?? this.w)
                    this.h = Number(root.getAttribute('Height') ?? this.h)
                    const body = await xpsNode(root, pagePath)
                    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${this.w} ${this.h}" width="${this.w}" height="${this.h}">${body}</svg>`
                },
            })
        }
    }
    const brush = (v) => {
        if (!v) return null
        if (v.startsWith('#')) {
            const hex = v.slice(1)
            if (hex.length === 8) return `rgba(${parseInt(hex.slice(2, 4), 16)},${parseInt(hex.slice(4, 6), 16)},${parseInt(hex.slice(6, 8), 16)},${(parseInt(hex.slice(0, 2), 16) / 255).toFixed(3)})`
            return '#' + hex
        }
        if (v.startsWith('sc#')) {
            const n = v.slice(3).split(',').map(Number)
            const [a, r, g, b] = n.length === 4 ? n : [1, ...n]
            return `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},${a})`
        }
        return null
    }
    const mat = m => m ? ` transform="matrix(${m.split(/[\s,]+/).join(' ')})"` : ''
    const geom = d => (d ?? '').replace(/^F\s*[01]\s*/, '')
    async function imgUrl(src, base) {
        const f = find(resolve(base, src))
        if (!f) return null
        const ext = src.split('.').pop().toLowerCase()
        const type = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', tif: 'image/tiff', tiff: 'image/tiff', wdp: 'image/vnd.ms-photo' }[ext] ?? 'image/png'
        if (/tif|wdp|jxr/.test(ext)) caveats.add('部分 TIFF / JPEG XR 图片无法显示')
        const u = URL.createObjectURL(new Blob([await f.async('uint8array')], { type }))
        urls.push(u)
        return u
    }
    async function xpsNode(el, base) {
        let out = ''
        for (const n of el.children) {
            const op = n.getAttribute('Opacity')
            const opa = op ? ` opacity="${op}"` : ''
            switch (n.localName) {
                case 'Canvas':
                    out += `<g${mat(n.getAttribute('RenderTransform'))}${opa}${n.getAttribute('Clip') ? '' : ''}>${await xpsNode(n, base)}</g>`
                    break
                case 'Path': {
                    let d = n.getAttribute('Data')
                    if (!d) {
                        const pg = all(n, 'PathGeometry')[0]
                        if (pg) d = all(pg, 'PathFigure').map(f => {
                            const segs = [...f.children].map(s => {
                                const pts = (s.getAttribute('Points') ?? s.getAttribute('Point') ?? '').trim()
                                if (s.localName === 'PolyLineSegment') return 'L' + pts
                                if (s.localName === 'PolyBezierSegment') return 'C' + pts
                                if (s.localName === 'ArcSegment') return `A${s.getAttribute('Size')} ${s.getAttribute('RotationAngle') ?? 0} ${s.getAttribute('IsLargeArc') === 'true' ? 1 : 0} ${s.getAttribute('SweepDirection') === 'Clockwise' ? 1 : 0} ${s.getAttribute('Point')}`
                                return ''
                            }).join(' ')
                            return `M${f.getAttribute('StartPoint')} ${segs}${f.getAttribute('IsClosed') === 'true' ? ' Z' : ''}`
                        }).join(' ')
                    }
                    let fill = brush(n.getAttribute('Fill'))
                    const stroke = brush(n.getAttribute('Stroke'))
                    // 图片画刷：常用于页面中的图片
                    const ib = all(n, 'ImageBrush')[0]
                    if (ib) {
                        const u = await imgUrl(ib.getAttribute('ImageSource'), base)
                        const vp = (ib.getAttribute('Viewport') ?? '0,0,1,1').split(/[\s,]+/).map(Number)
                        if (u) out += `<g${mat(n.getAttribute('RenderTransform'))}><image href="${u}" x="${vp[0]}" y="${vp[1]}" width="${vp[2]}" height="${vp[3]}" preserveAspectRatio="none"${mat(ib.getAttribute('Transform'))}/></g>`
                        continue
                    }
                    if (!fill && all(n, 'LinearGradientBrush').length) { caveats.add('渐变画刷以纯色近似'); fill = brush(all(n, 'GradientStop')[0]?.getAttribute('Color')) }
                    out += `<path d="${geom(d)}" fill="${fill ?? 'none'}" stroke="${stroke ?? 'none'}" stroke-width="${n.getAttribute('StrokeThickness') ?? 1}"${mat(n.getAttribute('RenderTransform'))}${opa}/>`
                    break
                }
                case 'Glyphs': {
                    const text = n.getAttribute('UnicodeString') ?? ''
                    if (!text || text.startsWith('{}') && text.length === 2) break
                    const size = n.getAttribute('FontRenderingEmSize') ?? 12
                    const x = n.getAttribute('OriginX'), y = n.getAttribute('OriginY')
                    const fill = brush(n.getAttribute('Fill')) ?? '#000'
                    // Indices 中的字宽（1/100 em）用于精确定位每个字符
                    const idx = (n.getAttribute('Indices') ?? '').split(';')
                    const xs = [Number(x)]
                    const chars = [...text.replace(/^\{\}/, '')]
                    for (let i = 0; i < chars.length - 1; i++) {
                        const adv = /,([\d.]+)/.exec(idx[i] ?? '')?.[1]
                        xs.push(xs.at(-1) + (adv != null ? Number(adv) / 100 * size : size * 0.55))
                    }
                    const bold = /bold/i.test(n.getAttribute('StyleSimulations') ?? '')
                    out += `<text x="${xs.join(' ')}" y="${y}" font-size="${size}" fill="${fill}" font-family="'Segoe UI', 'Microsoft YaHei', sans-serif"${bold ? ' font-weight="700"' : ''}${mat(n.getAttribute('RenderTransform'))}>${esc(chars.join(''))}</text>`
                    break
                }
            }
        }
        return out
    }
    return { kind: 'pages', pages, caveats: [...caveats], urls, unit: 'px' }
}

// 文字大纲型演示文稿（旧版 PPT / ODP）：实现与 Pptx 相同的接口，以简洁版式渲染每页
export class OutlineDeck {
    width = 960
    height = 540
    lossy = new Set()
    meta = {}

    static async open(buf, ext) {
        const d = new OutlineDeck()
        const r = ['ppt', 'pps', 'pot'].includes(ext) ? await decodePpt(buf) : await decodeOdf(buf)
        if (r.kind !== 'slides') throw new Error('文件中没有找到幻灯片')
        d.slides = r.slides
        d.urls = r.urls ?? []
        for (const c of r.caveats) d.lossy.add(c)
        if (!d.slides.length) throw new Error('没有提取到幻灯片内容（文件可能只包含图片或已加密）')
        return d
    }

    get count() { return this.slides.length }

    async renderSlide(i) {
        const s = this.slides[i]
        const el = document.createElement('div')
        el.className = 'pp-slide pp-outline'
        el.style.width = this.width + 'px'
        el.style.height = this.height + 'px'
        const body = s.html ?? s.text.split(/\n{2,}/).map(block => {
            const lines = block.split('\n').filter(Boolean)
            return lines.length > 1 ? `<ul>${lines.map(l => `<li>${esc(l)}</li>`).join('')}</ul>` : `<p>${esc(block)}</p>`
        }).join('')
        el.innerHTML = `<div class="pp-outline-title">${esc(s.title || `幻灯片 ${i + 1}`)}</div><div class="pp-outline-body">${body}</div>`
        return { el, hidden: false }
    }

    async slideText(i) { return { title: this.slides[i].title, text: this.slides[i].text } }
    async notes() { return '' }
    dispose() { for (const u of this.urls) URL.revokeObjectURL(u) }
}
