// 格式转换引擎
// 思路：每种输入先解码为一种「中间表示」，再由写出器输出为目标格式。
//   doc   —— 回流文档 { title, html, css? }（文本 / Markdown / Word / RTF / ODT / 网页 / LaTeX / 电子书 / CHM）
//   pages —— 固定页面 { pages: [{ w, h, image() -> Blob(png/jpeg) }] }（PDF / 演示文稿 / OFD / XPS / DjVu / 图片）
//   sheet —— 工作簿（SheetJS）
//   audio —— 解码后的 PCM（AudioBuffer）
//   archive —— 文件列表 [{ name, blob }]
// 每条转换路线都会给出 lossless 标记与 losses（有损原因），界面据此提示「有损」。
import { typeOf, extOf, stemOf, Source } from './files.js'
import { printStyles } from './print.js'

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

// ---------- 目标格式 ----------
export const TARGETS = {
    pdf: { label: 'PDF', ext: 'pdf', desc: '通用版式文档' },
    docx: { label: 'Word (DOCX)', ext: 'docx', desc: '可编辑文档' },
    html: { label: 'HTML 网页', ext: 'html', desc: '单文件网页（图片内嵌）' },
    md: { label: 'Markdown', ext: 'md', desc: '轻量标记文本' },
    txt: { label: '纯文本 (TXT)', ext: 'txt', desc: '仅保留文字' },
    epub: { label: 'EPUB 电子书', ext: 'epub', desc: '可回流电子书' },
    png: { label: 'PNG 图片', ext: 'png', desc: '无损位图，多页时每页一张' },
    jpg: { label: 'JPEG 图片', ext: 'jpg', desc: '有损压缩位图' },
    webp: { label: 'WebP 图片', ext: 'webp', desc: '现代图片格式' },
    bmp: { label: 'BMP 图片', ext: 'bmp', desc: '无压缩位图' },
    xlsx: { label: 'Excel (XLSX)', ext: 'xlsx', desc: '工作簿' },
    xls: { label: 'Excel 97 (XLS)', ext: 'xls', desc: '旧版工作簿' },
    ods: { label: 'OpenDocument 表格 (ODS)', ext: 'ods', desc: '开放格式工作簿' },
    csv: { label: 'CSV', ext: 'csv', desc: '逗号分隔，仅当前 / 每个工作表' },
    tsv: { label: 'TSV', ext: 'tsv', desc: '制表符分隔' },
    json: { label: 'JSON', ext: 'json', desc: '结构化数据' },
    wav: { label: 'WAV 音频', ext: 'wav', desc: '无损 PCM' },
    mp3: { label: 'MP3 音频', ext: 'mp3', desc: '有损压缩音频' },
    zip: { label: 'ZIP 压缩包', ext: 'zip', desc: '通用压缩格式' },
    '7z': { label: '7Z 压缩包', ext: '7z', desc: '存储模式（不压缩）' },
    tar: { label: 'TAR 归档', ext: 'tar', desc: '无压缩归档' },
    tgz: { label: 'TAR.GZ 压缩包', ext: 'tar.gz', desc: 'gzip 压缩归档' },
}

// 输入类型 → 中间表示
const KIND = {
    text: 'doc', doc: 'doc', docx: 'doc', rich: 'doc', web: 'doc', tex: 'doc', ebook: 'doc', chm: 'doc',
    pdf: 'pages', slides: 'pages', paged: 'pages', image: 'pages',
    sheet: 'sheet', audio: 'audio', archive: 'archive',
}
// 每种中间表示可输出的目标
const OUTPUTS = {
    doc: ['pdf', 'docx', 'html', 'md', 'txt', 'epub'],
    pages: ['pdf', 'png', 'jpg', 'webp', 'bmp', 'html', 'txt', 'docx'],
    sheet: ['xlsx', 'xls', 'ods', 'csv', 'tsv', 'json', 'html', 'pdf', 'txt'],
    audio: ['wav', 'mp3'],
    archive: ['zip', '7z', 'tar', 'tgz'],
}

const kindOf = source => {
    if (source.type === 'ebook' && source.ext === 'cbz') return 'pages'
    return KIND[source.type] ?? null
}

// 某个文件可转换为哪些格式（附带有损说明）
export function targetsFor(source) {
    const kind = kindOf(source)
    if (!kind) return []
    return OUTPUTS[kind]
        .filter(t => !isSame(source, t))
        .map(t => ({ id: t, ...TARGETS[t], ...lossInfo(source, kind, t) }))
}

const isSame = (s, t) => s.ext === t || (t === 'jpg' && ['jpeg', 'jfif'].includes(s.ext)) || (t === 'tgz' && s.ext === 'tgz') || (t === 'md' && s.ext === 'markdown') || (t === 'html' && s.ext === 'htm')

// 有损判断：返回 { lossless, losses: [原因] }
export function lossInfo(source, kind, target) {
    const L = []
    const e = source.ext, type = source.type
    const add = (...r) => L.push(...r)
    if (kind === 'doc') {
        if (target === 'txt') add('仅保留文字，格式、图片、表格结构全部丢失')
        if (target === 'md') add('Markdown 不支持字体、颜色、对齐等样式')
        if (target === 'md' && type !== 'text') add('复杂表格（合并单元格）会被简化')
        if (target === 'pdf') { if (type === 'text' && e !== 'md' && e !== 'markdown') { /* 纯文本转 PDF 不丢信息 */ } else add('按阅读排版重新分页，原文的分页位置可能不同') }
        if (target === 'docx') add('按 HTML 结构重建 Word 文档，复杂排版（浮动图片、分栏、页眉页脚）会简化')
        if (target === 'epub') add('转为可回流电子书，固定排版不保留')
        if (type === 'docx' && target !== 'txt') add('Word 的页眉页脚、批注与修订不保留')
        if (type === 'doc') add('DOC 源文件只能提取文字，格式与图片在转换中丢失')
        if (type === 'web') add('网页脚本与交互内容不保留')
        if (type === 'tex') add('LaTeX 经 HTML 转换，TikZ 图形、部分宏包效果不保留')
        if (type === 'tex' && target !== 'pdf' && target !== 'html' && target !== 'epub') add('数学公式转为文本 / 图片形式')
        if (type === 'ebook' && target !== 'epub') add('电子书的目录层级与元数据部分保留')
        if (type === 'ebook' && ['mobi', 'azw3', 'azw', 'kf8', 'prc'].includes(e) && target === 'epub') add('Kindle 专有排版特性不保留')
        if (type === 'chm') add('CHM 的索引与全文搜索数据不保留')
        if (type === 'rich' && target === 'html') { /* 基本无损 */ }
        if (type === 'text' && !['md', 'markdown'].includes(e) && ['html', 'pdf', 'docx', 'epub'].includes(target)) { /* 纯文本 → 富格式，不丢信息 */ }
        if (type === 'text' && ['md', 'markdown'].includes(e) && target === 'html') { /* 无损 */ }
    }
    if (kind === 'pages') {
        const raster = ['png', 'jpg', 'webp', 'bmp'].includes(target)
        if (type === 'image') {
            if (target === 'jpg') add('JPEG 为有损压缩，透明背景变为白色')
            if (target === 'bmp' && ['png', 'webp', 'gif', 'avif', 'apng', 'ico', 'svg'].includes(e)) add('BMP 不支持透明通道')
            if (target === 'webp') add('以 90% 质量有损压缩')
            if (['gif', 'apng', 'webp'].includes(e)) add('动画仅保留第一帧')
            if (e === 'svg' && target !== 'pdf') add('矢量图转为位图，放大后会模糊')
            if (target === 'html') { /* 内嵌图片，无损 */ }
            if (target === 'txt' || target === 'docx') add('图片没有文字内容可提取')
        } else {
            if (raster) add('矢量页面转为位图（默认 2 倍分辨率），文字不可再编辑或搜索')
            if (target === 'jpg') add('JPEG 有损压缩')
            if (target === 'txt') add('仅保留可提取的文字，版式与图片丢失')
            if (target === 'docx') add('仅提取文字段落，版式与图片丢失')
            if (target === 'html') add('每页以图片形式嵌入，文字不可编辑')
            if (target === 'pdf' && ['djvu', 'djv', 'cbz'].includes(e)) add('页面以高分辨率图片写入 PDF')
            if (target === 'pdf' && (type === 'slides' || type === 'paged') && !['djvu', 'djv'].includes(e)) add('以矢量方式重新绘制页面，字体使用系统字体近似')
            if (type === 'slides' && ['ppt', 'pps', 'pot', 'odp', 'otp'].includes(e)) add('源文件只能提取文字大纲，原始版式已丢失')
            if (type === 'slides') add('动画、切换效果与备注不保留')
            if (type === 'paged' && e === 'ofd') add('电子签章不保留')
        }
        if (type === 'pdf' && target === 'pdf') { /* 同格式不出现 */ }
    }
    if (kind === 'sheet') {
        const flat = ['csv', 'tsv', 'txt']
        if (flat.includes(target)) add('仅保留单元格的值，公式、格式、合并单元格丢失；多个工作表拆分为多个文件')
        if (target === 'json') add('仅保留单元格的值，公式与格式丢失')
        if (target === 'html' || target === 'pdf') add('公式只保留计算结果，单元格样式简化')
        if (target === 'xls') add('XLS 最多 65536 行 × 256 列，超出部分截断；部分新函数不支持')
        if (['xlsx', 'xls', 'ods'].includes(target)) add('单元格样式（字体、颜色、边框）不保留，保留值、公式与合并单元格')
        if (['csv', 'tsv'].includes(e) && ['xlsx', 'xls', 'ods'].includes(target)) L.length = 0
    }
    if (kind === 'audio') {
        const midi = ['mid', 'midi', 'rmi', 'kar'].includes(e)
        const lossyIn = ['mp3', 'ogg', 'oga', 'opus', 'm4a', 'aac', 'weba'].includes(e)
        if (midi) add('MIDI 由 GeneralUser GS 音色库合成为音频，音色取决于音色库')
        if (target === 'mp3') add('MP3 为有损压缩（192 kbps）')
        if (target === 'wav' && lossyIn) add('源文件本身已是有损格式，转为 WAV 不会恢复丢失的音质（文件变大）')
        add('标签信息（封面、歌词、艺术家）不保留')
    }
    if (kind === 'archive') {
        if (['rar', 'cbr'].includes(e)) add('RAR 的恢复记录与固实压缩信息不保留')
        if (target === 'tar') add('TAR 不压缩，文件会变大')
        if (target === '7z') add('7z 以存储模式写出（不压缩），文件会变大')
        add('文件权限、时间戳与空目录不保留')
        if (/7z|rar|zip/.test(e)) add('原压缩包的密码保护不保留')
    }
    return { lossless: !L.length, losses: [...new Set(L)] }
}

// ---------- 执行转换 ----------
// options: { target, dpi, quality, sheetMode, onProgress(text, fraction) }
// 返回 [{ name, data: Uint8Array | Blob }]（多页图片、多工作表 CSV 会返回多个文件）
export async function convert(source, options) {
    const { target } = options
    const kind = kindOf(source)
    if (!kind || !OUTPUTS[kind].includes(target)) throw new Error(`不支持将 ${source.ext.toUpperCase()} 转换为 ${TARGETS[target]?.label ?? target}`)
    const progress = options.onProgress ?? (() => {})
    const stem = stemOf(source.name)
    const ext = TARGETS[target].ext
    if (kind === 'doc') {
        progress('正在解析文档…', 0.1)
        const doc = await toDoc(source, progress)
        progress('正在写出…', 0.6)
        return [{ name: `${stem}.${ext}`, data: await writeDoc(doc, target, options) }]
    }
    if (kind === 'pages') {
        progress('正在读取页面…', 0.05)
        const pages = await toPages(source, options, progress)
        return writePages(pages, target, stem, options, progress)
    }
    if (kind === 'sheet') return writeSheet(source, target, stem, options, progress)
    if (kind === 'audio') return writeAudio(source, target, stem, options, progress)
    if (kind === 'archive') return writeArchive(source, target, stem, options, progress)
}

// ================= 回流文档 =================
export async function toDoc(source, progress = () => {}) {
    const type = source.type, e = source.ext
    const buf = () => source.arrayBuffer()
    const { decodeText } = await import('./encoding.js')
    if (type === 'text') {
        const { text } = decodeText(new Uint8Array(await buf()))
        if (['md', 'markdown'].includes(e)) {
            const { renderMarkdown } = await import('../viewers/text.js')
            return { title: firstHeading(text) ?? stemOf(source.name), html: await renderMarkdown(text), markdown: text, katex: true }
        }
        const { highlightCode } = await import('../viewers/text.js')
        const code = CODE.has(e)
        const html = code ? (await highlightCode(text, e)) ?? `<pre>${esc(text)}</pre>` : textToHtml(text)
        return { title: stemOf(source.name), html, plain: text, code }
    }
    if (type === 'doc') {
        const src = source.path ?? new Uint8Array(await buf())
        const r = await window.lite.extractDoc(src)
        const text = [r.body, r.footnotes && '\n\n脚注\n' + r.footnotes, r.endnotes && '\n\n尾注\n' + r.endnotes].filter(Boolean).join('')
        return { title: stemOf(source.name), html: textToHtml(text), plain: text }
    }
    if (type === 'docx') {
        const { renderAsync } = await import('docx-preview')
        const host = document.createElement('div'), style = document.createElement('div')
        await renderAsync(await buf(), host, style, { inWrapper: false, ignoreLastRenderedPageBreak: true, breakPages: false, renderHeaders: false, renderFooters: false, useBase64URL: true, experimental: true })
        const css = [...style.querySelectorAll('style')].map(s => s.textContent).join('\n')
        return { title: stemOf(source.name), html: host.innerHTML, css }
    }
    if (type === 'rich') {
        const { decodeRtf, decodeOdf } = await import('./formats.js')
        const r = e === 'rtf' ? await decodeRtf(await buf()) : await decodeOdf(await buf())
        return { title: r.title || stemOf(source.name), html: await inlineBlobs(r.html) }
    }
    if (type === 'web') {
        const { sanitize, parseMht } = await import('../viewers/web.js')
        const bytes = new Uint8Array(await buf())
        let html
        if (['mht', 'mhtml'].includes(e)) html = parseMht(bytes).html
        else html = decodeText(bytes).text
        const d = new DOMParser().parseFromString(html, 'text/html')
        sanitize(d)
        const css = [...d.querySelectorAll('style')].map(s => s.textContent).join('\n')
        await inlineImages(d, source)
        return { title: d.title || stemOf(source.name), html: d.body.innerHTML, css }
    }
    if (type === 'tex') {
        const { texToHtml } = await import('./latex.js')
        const { loadTexProject } = await import('../viewers/tex.js')
        const { text } = decodeText(new Uint8Array(await buf()))
        const p = await loadTexProject(source, text)
        const r = texToHtml(text, { resolveAsset: f => p.assets.get(f) ?? null, includes: p.includes, bibs: p.bibs })
        const d = new DOMParser().parseFromString(`<body>${r.html}</body>`, 'text/html')
        await inlineImages(d, source)
        return { title: r.meta.title?.replace(/\\[a-zA-Z]+|[{}]/g, '') || stemOf(source.name), html: d.body.innerHTML, katex: true, tex: true }
    }
    if (type === 'ebook') return ebookToDoc(source, progress)
    if (type === 'chm') return chmToDoc(source, progress)
    throw new Error('不支持的文档类型')
}

const CODE = new Set(['json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'cfg', 'toml', 'js', 'mjs', 'ts', 'css', 'py', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'sh', 'bat', 'ps1', 'sql', 'sty', 'cls', 'bib', 'php', 'rb', 'kt', 'swift', 'lua', 'r', 'vue', 'jsx', 'tsx', 'scss', 'less', 'dart', 'pl'])
const firstHeading = md => /^#\s+(.+)$/m.exec(md)?.[1]?.trim()
// 纯文本 → 段落：空行分段；没有空行的文本（如 DOC 提取结果）每行一段
const textToHtml = text => {
    const t = text.replace(/\r\n?/g, '\n')
    const blocks = /\n\s*\n/.test(t) ? t.split(/\n\s*\n/) : t.split('\n')
    return blocks.filter(b => b.trim()).map(p => `<p>${esc(p.trim()).replace(/\n/g, '<br>')}</p>`).join('\n')
}

// blob: 地址转为 data URL（导出文件需要自包含）
async function blobToDataURL(blob) {
    return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(blob) })
}
async function inlineBlobs(html) {
    const d = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
    await inlineImages(d)
    return d.body.innerHTML
}
// 把 blob: / media: / 相对路径图片转为 data URL
async function inlineImages(d, source) {
    const base = source?.path ? (await import('./files.js')).localDirURL(source.path) : null
    for (const img of d.querySelectorAll('img[src]')) {
        let src = img.getAttribute('src')
        if (/^data:/.test(src)) continue
        if (/^https?:/i.test(src)) { img.remove(); continue }
        try {
            if (!/^(blob|media):/.test(src)) { if (!base) continue; src = new URL(src, base).href }
            const res = await fetch(src)
            if (!res.ok) throw 0
            img.setAttribute('src', await blobToDataURL(await res.blob()))
        } catch { img.replaceWith(d.createTextNode(`[图片：${img.getAttribute('alt') || ''}]`)) }
    }
}

async function ebookToDoc(source, progress) {
    const { makeBook } = await import('foliate-js/view.js')
    const book = await makeBook(await source.file())
    const parts = []
    const n = book.sections.length
    for (let i = 0; i < n; i++) {
        const s = book.sections[i]
        if (s.linear === 'no') continue
        progress(`正在读取章节 ${i + 1}/${n}…`, 0.1 + 0.4 * i / n)
        try {
            const doc = await s.createDocument()
            // 章节内图片转为 data URL
            for (const img of doc.querySelectorAll('img[src], image')) {
                const attr = img.localName === 'image' ? (img.getAttribute('href') ? 'href' : 'xlink:href') : 'src'
                const src = img.getAttribute(attr)
                if (!src || src.startsWith('data:')) continue
                try {
                    const href = s.resolveHref ? s.resolveHref(src) : src
                    const blob = book.loadBlob ? await book.loadBlob(href) : await (await fetch(src)).blob()
                    img.setAttribute(attr, await blobToDataURL(blob))
                } catch { /* 忽略 */ }
            }
            doc.querySelectorAll('script, style, link').forEach(el => el.remove())
            parts.push(`<section class="ebook-chapter">${doc.body?.innerHTML ?? ''}</section>`)
        } catch (e) { console.warn(e) }
        s.unload?.()
    }
    const title = typeof book.metadata?.title === 'string' ? book.metadata.title : Object.values(book.metadata?.title ?? {})[0]
    const author = [book.metadata?.author].flat().map(a => typeof a === 'string' ? a : a?.name).filter(Boolean).join('、')
    return { title: title || stemOf(source.name), author, html: parts.join('\n<hr class="chapter-break">\n') }
}

async function chmToDoc(source, progress) {
    const { dir, files } = await window.lite.extractChm(source.path)
    const { decodeText } = await import('./encoding.js')
    const { parseSitemap } = await import('../viewers/chm.js')
    const { localURL } = await import('./files.js')
    const read = async rel => decodeText(await window.lite.readFile(dir + '\\' + rel.replace(/\//g, '\\'))).text
    const hhc = files.find(f => /\.hhc$/i.test(f))
    const flat = list => list.flatMap(t => [t, ...flat(t.children ?? [])])
    const order = []
    const seen = new Set()
    if (hhc) for (const t of flat(parseSitemap(await read(hhc)))) {
        const page = t.local?.split('#')[0]
        const hit = page && files.find(f => f.toLowerCase() === page.toLowerCase())
        if (hit && !seen.has(hit)) { seen.add(hit); order.push(hit) }
    }
    for (const f of files) if (/\.html?$/i.test(f) && !seen.has(f)) order.push(f)
    const parts = []
    for (const [i, f] of order.entries()) {
        progress(`正在读取页面 ${i + 1}/${order.length}…`, 0.1 + 0.4 * i / order.length)
        const d = new DOMParser().parseFromString(await read(f), 'text/html')
        d.querySelectorAll('script, object, style, link').forEach(el => el.remove())
        const base = localURL(dir + '\\' + f.replace(/\//g, '\\')).replace(/[^/]*$/, '')
        for (const img of d.querySelectorAll('img[src]')) img.setAttribute('src', new URL(img.getAttribute('src'), base).href)
        await inlineImages(d)
        parts.push(`<section>${d.body.innerHTML}</section>`)
    }
    return { title: stemOf(source.name), html: parts.join('\n<hr class="chapter-break">\n') }
}

// 完整的 HTML 文档（导出 HTML 与打印共用）
export async function docHtml(doc, { forPrint = false } = {}) {
    let katexCss = ''
    if (doc.katex && /class="katex/.test(doc.html)) katexCss = await inlineKatexCss()
    const hl = /class="hljs/.test(doc.html) ? (await import('highlight.js/styles/github.css?inline')).default : ''
    return `<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(doc.title ?? '')}</title>
<style>${printStyles(forPrint)}</style>
${doc.css ? `<style>${doc.css}</style>` : ''}
${katexCss ? `<style>${katexCss}</style>` : ''}
${hl ? `<style>${hl}</style>` : ''}
</head><body><article class="lr-doc${doc.tex ? ' tex' : ''}${doc.code ? ' code' : ''}">${doc.html}</article></body></html>`
}

// KaTeX 样式与字体内嵌为 data URL，保证导出的 HTML / PDF 在任何环境中都能正确显示公式
let katexCssCache = null
async function inlineKatexCss() {
    if (katexCssCache) return katexCssCache
    const css = (await import('katex/dist/katex.min.css?inline')).default
    const fonts = import.meta.glob('/node_modules/katex/dist/fonts/*.woff2', { query: '?url', import: 'default', eager: true })
    const byName = Object.fromEntries(Object.entries(fonts).map(([k, v]) => [k.split('/').pop(), v]))
    const cache = {}
    let out = css
    for (const m of new Set(css.match(/fonts\/[\w-]+\.woff2/g) ?? [])) {
        const file = m.slice(6)
        const url = byName[file]
        if (!url) continue
        try {
            cache[file] ??= await blobToDataURL(await (await fetch(url)).blob())
            out = out.split(m).join(cache[file])
        } catch { /* 忽略 */ }
    }
    // 去掉 woff / ttf 备选，避免引用不存在的文件
    out = out.replace(/,url\(fonts\/[^)]+\.(woff|ttf)\) format\("(woff|truetype)"\)/g, '')
    katexCssCache = out
    return out
}

async function writeDoc(doc, target, options) {
    if (target === 'html') return new TextEncoder().encode(await docHtml(doc))
    if (target === 'pdf') return printToBytes(await docHtml(doc, { forPrint: true }), options)
    if (target === 'txt') return new TextEncoder().encode('\ufeff' + (doc.plain ?? htmlToText(doc.html)))
    if (target === 'md') {
        if (doc.markdown) return new TextEncoder().encode(doc.markdown)
        return new TextEncoder().encode(await htmlToMarkdown(doc.html))
    }
    if (target === 'docx') return htmlToDocx(doc)
    if (target === 'epub') return htmlToEpub(doc)
}

export function htmlToText(html) {
    const d = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
    d.querySelectorAll('script, style, .katex-html').forEach(e => e.remove())
    // KaTeX 保留 TeX 源码
    d.querySelectorAll('.katex-mathml annotation').forEach(a => a.closest('.katex')?.replaceWith(d.createTextNode(a.textContent)))
    d.querySelectorAll('br').forEach(b => b.replaceWith('\n'))
    d.querySelectorAll('p, div, h1, h2, h3, h4, h5, h6, li, tr, pre, blockquote, section, figure, dt, dd').forEach(el => el.append('\n'))
    d.querySelectorAll('td, th').forEach(el => el.append('\t'))
    d.querySelectorAll('.ln').forEach(el => el.remove())
    return d.body.textContent.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim() + '\n'
}

async function htmlToMarkdown(html) {
    const [{ default: TurndownService }, gfm] = await Promise.all([import('turndown'), import('turndown-plugin-gfm')])
    const td = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced', bulletListMarker: '-', emDelimiter: '*' })
    td.use(gfm.gfm)
    // 公式还原为 $…$
    td.addRule('katex', {
        filter: n => n.classList?.contains('katex-display') || n.classList?.contains('katex') && !n.closest?.('.katex-display'),
        replacement: (_c, n) => {
            const tex = n.querySelector('annotation')?.textContent ?? ''
            return n.classList.contains('katex-display') ? `\n\n$$\n${tex}\n$$\n\n` : `$${tex}$`
        },
    })
    td.addRule('texDisplay', { filter: n => n.classList?.contains('tex-display'), replacement: (_c, n) => `\n\n$$\n${n.querySelector('annotation')?.textContent ?? ''}\n$$\n\n` })
    td.addRule('lineNo', { filter: n => n.classList?.contains('ln'), replacement: () => '' })
    td.remove(['script', 'style'])
    const d = new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')
    // 代码行号块还原为纯代码
    d.querySelectorAll('pre.code-lines').forEach(pre => { pre.querySelectorAll('.ln').forEach(x => x.remove()); pre.replaceChildren(Object.assign(d.createElement('code'), { textContent: pre.textContent })) })
    return td.turndown(d.body)
}

// ---------- HTML → DOCX（docx 库，按段落 / 标题 / 列表 / 表格 / 图片重建） ----------
async function htmlToDocx(doc) {
    const D = await import('docx')
    const d = new DOMParser().parseFromString(`<body>${doc.html}</body>`, 'text/html')
    d.querySelectorAll('script, style, .katex-html, .ln').forEach(e => e.remove())
    d.querySelectorAll('.katex').forEach(k => k.replaceWith(d.createTextNode(k.querySelector('annotation')?.textContent ?? k.textContent)))
    const HEAD = { H1: D.HeadingLevel.HEADING_1, H2: D.HeadingLevel.HEADING_2, H3: D.HeadingLevel.HEADING_3, H4: D.HeadingLevel.HEADING_4, H5: D.HeadingLevel.HEADING_5, H6: D.HeadingLevel.HEADING_6 }
    const children = []

    const runs = (el, fmt = {}) => {
        const out = []
        for (const n of el.childNodes) {
            if (n.nodeType === 3) {
                const t = n.nodeValue.replace(/\s+/g, ' ')
                if (t) out.push(new D.TextRun({ text: t, bold: fmt.b, italics: fmt.i, underline: fmt.u ? {} : undefined, strike: fmt.s, font: fmt.code ? 'Consolas' : undefined, superScript: fmt.sup, subScript: fmt.sub, color: fmt.color }))
                continue
            }
            if (n.nodeType !== 1) continue
            const t = n.tagName
            if (t === 'BR') { out.push(new D.TextRun({ text: '', break: 1 })); continue }
            if (t === 'IMG') { const img = imageRun(n); if (img) out.push(img); continue }
            const f = { ...fmt }
            if (t === 'B' || t === 'STRONG' || /font-weight:\s*(bold|[6-9]00)/.test(n.getAttribute('style') ?? '')) f.b = true
            if (t === 'I' || t === 'EM' || /font-style:\s*italic/.test(n.getAttribute('style') ?? '')) f.i = true
            if (t === 'U' || /underline/.test(n.getAttribute('style') ?? '')) f.u = true
            if (t === 'S' || t === 'DEL' || t === 'STRIKE') f.s = true
            if (t === 'CODE' || t === 'KBD') f.code = true
            if (t === 'SUP') f.sup = true
            if (t === 'SUB') f.sub = true
            const col = /(?:^|;)\s*color:\s*#([0-9a-f]{6})/i.exec(n.getAttribute('style') ?? '')
            if (col) f.color = col[1]
            if (t === 'A' && /^https?:/.test(n.getAttribute('href') ?? '')) {
                out.push(new D.ExternalHyperlink({ link: n.getAttribute('href'), children: runs(n, { ...f, u: true, color: '0563C1' }) }))
                continue
            }
            out.push(...runs(n, f))
        }
        return out
    }
    const imageRun = img => {
        const src = img.getAttribute('src') ?? ''
        const m = /^data:image\/(png|jpe?g|gif|bmp);base64,(.+)$/i.exec(src)
        if (!m) return null
        const bytes = Uint8Array.from(atob(m[2]), c => c.charCodeAt(0))
        let w = Number(img.getAttribute('width')) || img.naturalWidth || 480
        let h = Number(img.getAttribute('height')) || img.naturalHeight || w * 0.66
        const size = imageSize(bytes)
        if (size) { w = size.w; h = size.h }
        const max = 600
        if (w > max) { h = h * max / w; w = max }
        return new D.ImageRun({ type: m[1].toLowerCase().replace('jpeg', 'jpg'), data: bytes, transformation: { width: Math.round(w), height: Math.round(h) } })
    }
    const align = el => {
        const a = /text-align:\s*(center|right|justify)/.exec(el.getAttribute?.('style') ?? '')?.[1] ?? el.getAttribute?.('align')
        return { center: D.AlignmentType.CENTER, right: D.AlignmentType.RIGHT, justify: D.AlignmentType.JUSTIFIED }[a]
    }
    const block = (el, ctx = {}) => {
        for (const n of el.childNodes) {
            if (n.nodeType === 3) {
                if (n.nodeValue.trim()) children.push(new D.Paragraph({ children: [new D.TextRun(n.nodeValue.trim())] }))
                continue
            }
            if (n.nodeType !== 1) continue
            const t = n.tagName
            if (HEAD[t]) children.push(new D.Paragraph({ heading: HEAD[t], children: runs(n), alignment: align(n) }))
            else if (t === 'P' || t === 'DT' || t === 'FIGCAPTION') children.push(new D.Paragraph({ children: runs(n), alignment: align(n), indent: ctx.quote ? { left: 720 } : undefined }))
            else if (t === 'UL' || t === 'OL') {
                for (const li of n.children) {
                    if (li.tagName !== 'LI') continue
                    const nested = [...li.children].filter(c => c.tagName === 'UL' || c.tagName === 'OL')
                    nested.forEach(x => x.remove())
                    children.push(new D.Paragraph({ children: runs(li), bullet: t === 'UL' ? { level: Math.min(ctx.level ?? 0, 8) } : undefined, numbering: t === 'OL' ? { reference: 'lr-num', level: Math.min(ctx.level ?? 0, 8) } : undefined }))
                    for (const x of nested) block(Object.assign(d.createElement('div'), { append: null }) && wrap(x), { ...ctx, level: (ctx.level ?? 0) + 1 })
                }
            } else if (t === 'PRE') {
                for (const line of n.textContent.replace(/\n$/, '').split('\n')) children.push(new D.Paragraph({ children: [new D.TextRun({ text: line || ' ', font: 'Consolas', size: 19 })], shading: { fill: 'F3F4F6' }, spacing: { after: 0 } }))
            } else if (t === 'BLOCKQUOTE') block(n, { ...ctx, quote: true })
            else if (t === 'TABLE') children.push(table(n))
            else if (t === 'HR') children.push(new D.Paragraph({ border: { bottom: { style: D.BorderStyle.SINGLE, size: 6, color: 'CCCCCC' } }, children: [] }))
            else if (t === 'IMG') { const img = imageRun(n); if (img) children.push(new D.Paragraph({ children: [img], alignment: D.AlignmentType.CENTER })) }
            else if (t === 'DD') children.push(new D.Paragraph({ children: runs(n), indent: { left: 720 } }))
            else if (/^(DIV|SECTION|ARTICLE|MAIN|FIGURE|HEADER|FOOTER|NAV|ASIDE|DL|CENTER|DETAILS|SUMMARY|SPAN|FONT)$/.test(t) || !n.textContent.trim()) {
                // 容器：若只含内联内容则作为段落
                const hasBlock = n.querySelector('p, div, h1, h2, h3, h4, h5, h6, ul, ol, table, pre, blockquote, section, figure, dl, hr')
                if (hasBlock) block(n, ctx)
                else if (n.textContent.trim() || n.querySelector('img')) children.push(new D.Paragraph({ children: runs(n), alignment: align(n) }))
            } else children.push(new D.Paragraph({ children: runs(n) }))
        }
    }
    const wrap = x => { const w = d.createElement('div'); w.append(x); return w }
    const table = t => {
        const rows = [...t.querySelectorAll(':scope > tr, :scope > thead > tr, :scope > tbody > tr, :scope > tfoot > tr')]
        const cols = Math.max(1, ...rows.map(r => [...r.children].reduce((s, c) => s + (Number(c.getAttribute('colspan')) || 1), 0)))
        return new D.Table({
            width: { size: 100, type: D.WidthType.PERCENTAGE },
            rows: rows.map(r => new D.TableRow({
                children: [...r.children].filter(c => /^T[DH]$/.test(c.tagName)).map(c => new D.TableCell({
                    columnSpan: Number(c.getAttribute('colspan')) || undefined,
                    rowSpan: Number(c.getAttribute('rowspan')) || undefined,
                    children: [new D.Paragraph({ children: runs(c, { b: c.tagName === 'TH' }) })],
                })),
            })),
            columnWidths: new Array(cols).fill(Math.floor(9000 / cols)),
        })
    }
    block(d.body)
    const file = new D.Document({
        creator: 'LiteReader', title: doc.title ?? '',
        styles: { default: { document: { run: { font: 'Microsoft YaHei', size: 22 } } } },
        numbering: { config: [{ reference: 'lr-num', levels: Array.from({ length: 9 }, (_, i) => ({ level: i, format: D.LevelFormat.DECIMAL, text: `%${i + 1}.`, alignment: D.AlignmentType.START, style: { paragraph: { indent: { left: 720 * (i + 1), hanging: 360 } } } })) }] },
        sections: [{ children: children.length ? children : [new D.Paragraph('')] }],
    })
    return new Uint8Array(await D.Packer.toArrayBuffer(file))
}

// 读取 PNG / JPEG 尺寸
function imageSize(b) {
    if (b[0] === 0x89 && b[1] === 0x50) return { w: (b[16] << 24 | b[17] << 16 | b[18] << 8 | b[19]) >>> 0, h: (b[20] << 24 | b[21] << 16 | b[22] << 8 | b[23]) >>> 0 }
    if (b[0] === 0xff && b[1] === 0xd8) {
        let i = 2
        while (i < b.length) {
            if (b[i] !== 0xff) return null
            const m = b[i + 1], len = b[i + 2] << 8 | b[i + 3]
            if (m >= 0xc0 && m <= 0xc3) return { h: b[i + 5] << 8 | b[i + 6], w: b[i + 7] << 8 | b[i + 8] }
            i += 2 + len
        }
    }
    return null
}

// ---------- HTML → EPUB 3 ----------
async function htmlToEpub(doc) {
    const { default: JSZip } = await import('jszip')
    const zip = new JSZip()
    zip.file('mimetype', 'application/epub+zip', { compression: 'STORE' })
    zip.file('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    const d = new DOMParser().parseFromString(`<body>${doc.html}</body>`, 'text/html')
    d.querySelectorAll('script, .katex-mathml').forEach(e => e.remove())
    // 图片抽出为独立文件
    const manifest = []
    let n = 0
    for (const img of d.querySelectorAll('img[src^="data:"]')) {
        const m = /^data:(image\/[\w+.-]+);base64,(.+)$/.exec(img.getAttribute('src'))
        if (!m) continue
        const ext = { 'image/jpeg': 'jpg', 'image/svg+xml': 'svg' }[m[1]] ?? m[1].split('/')[1]
        const name = `images/img${++n}.${ext}`
        zip.file('OEBPS/' + name, m[2], { base64: true })
        manifest.push(`<item id="img${n}" href="${name}" media-type="${m[1]}"/>`)
        img.setAttribute('src', name)
    }
    // 按一级 / 二级标题或 chapter-break 拆分章节
    const chapters = []
    let cur = null
    const push = () => { if (cur && cur.nodes.length) chapters.push(cur) }
    const start = title => { push(); cur = { title, nodes: [] } }
    start(doc.title || '正文')
    const flatNodes = []
    const collect = el => {
        for (const c of [...el.childNodes]) {
            if (c.nodeType === 1 && (c.tagName === 'SECTION' || c.tagName === 'ARTICLE') && c.querySelector('h1, h2')) collect(c)
            else flatNodes.push(c)
        }
    }
    collect(d.body)
    for (const node of flatNodes) {
        if (node.nodeType === 1 && node.classList?.contains('chapter-break')) { start(''); continue }
        if (node.nodeType === 1 && /^H[12]$/.test(node.tagName) && cur.nodes.some(x => x.nodeType === 1 && x.textContent.trim())) start(node.textContent.trim())
        else if (node.nodeType === 1 && /^H[12]$/.test(node.tagName) && !cur.title) cur.title = node.textContent.trim()
        cur.nodes.push(node)
    }
    push()
    const ser = new XMLSerializer()
    const xhtml = (title, body) => `<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN"><head><meta charset="utf-8"/><title>${esc(title)}</title><link rel="stylesheet" href="style.css"/></head><body>${body}</body></html>`
    const spine = [], items = []
    chapters.forEach((c, i) => {
        const body = c.nodes.map(x => x.nodeType === 1 ? ser.serializeToString(x).replace(/ xmlns="http:\/\/www\.w3\.org\/1999\/xhtml"/g, '') : esc(x.textContent)).join('\n')
        c.title ||= `第 ${i + 1} 部分`
        zip.file(`OEBPS/ch${i + 1}.xhtml`, xhtml(c.title, body))
        items.push(`<item id="ch${i + 1}" href="ch${i + 1}.xhtml" media-type="application/xhtml+xml"/>`)
        spine.push(`<itemref idref="ch${i + 1}"/>`)
    })
    zip.file('OEBPS/style.css', (doc.css ?? '') + '\nbody{font-family:serif;line-height:1.7}img{max-width:100%}pre{white-space:pre-wrap}table{border-collapse:collapse}td,th{border:1px solid #999;padding:3px 6px}')
    zip.file('OEBPS/nav.xhtml', xhtml('目录', `<nav epub:type="toc"><h1>目录</h1><ol>${chapters.map((c, i) => `<li><a href="ch${i + 1}.xhtml">${esc(c.title)}</a></li>`).join('')}</ol></nav>`))
    const uid = 'urn:uuid:' + crypto.randomUUID()
    zip.file('OEBPS/content.opf', `<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="zh-CN">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">${uid}</dc:identifier><dc:title>${esc(doc.title ?? '未命名')}</dc:title><dc:language>zh-CN</dc:language>${doc.author ? `<dc:creator>${esc(doc.author)}</dc:creator>` : ''}<meta property="dcterms:modified">${new Date().toISOString().replace(/\.\d+Z$/, 'Z')}</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="style.css" media-type="text/css"/>${items.join('')}${manifest.join('')}</manifest>
<spine>${spine.join('')}</spine></package>`)
    return zip.generateAsync({ type: 'uint8array', mimeType: 'application/epub+zip', compression: 'DEFLATE' })
}

// ---------- 打印为 PDF（主进程 printToPDF） ----------
async function printToBytes(html, options = {}) {
    const r = await window.lite.printHtml({ html, mode: 'preview', pageSize: options.pageSize ?? 'A4', landscape: !!options.landscape, margins: options.margins ?? 'default', headerFooter: !!options.headerFooter, cssPage: !!options.cssPage })
    if (!r?.ok) throw new Error('生成 PDF 失败')
    return r.data
}

// ================= 固定页面 =================
// 返回 { pages: [{ w, h, image(scale) -> Blob, text?() }], vector?: html }
export async function toPages(source, options = {}, progress = () => {}) {
    const type = source.type, e = source.ext
    if (type === 'image') {
        // 先读为 Blob 再解码：直接使用 media:// 地址绘制会使画布被标记为跨域，无法导出
        const url = URL.createObjectURL(await source.blob())
        const img = await loadImage(url).catch(e => { URL.revokeObjectURL(url); throw e })
        // SVG 可能没有固有尺寸
        const w = img.naturalWidth || 1024, hh = img.naturalHeight || 768
        return { pages: [{ w, h: hh, image: s => canvasFrom(img, Math.round(w * (s ?? 1)), Math.round(hh * (s ?? 1))) }], title: stemOf(source.name), single: true, dispose: () => URL.revokeObjectURL(url) }
    }
    if (type === 'pdf') {
        const pdfjs = await import('pdfjs-dist')
        if (!pdfjs.GlobalWorkerOptions.workerSrc) pdfjs.GlobalWorkerOptions.workerSrc = (await import('pdfjs-dist/build/pdf.worker.min.mjs?worker&url')).default
        const VENDOR = new URL('./vendor/pdfjs/', location.href).href
        const task = pdfjs.getDocument({ data: new Uint8Array(await source.arrayBuffer()), cMapUrl: VENDOR + 'cmaps/', cMapPacked: true, standardFontDataUrl: VENDOR + 'standard_fonts/', wasmUrl: VENDOR + 'wasm/', isEvalSupported: false })
        const pdf = await task.promise
        const pages = []
        for (let i = 1; i <= pdf.numPages; i++) {
            const page = await pdf.getPage(i)
            const vp = page.getViewport({ scale: 1 })
            pages.push({
                w: vp.width * 96 / 72, h: vp.height * 96 / 72,
                async image(scale) {
                    const v = page.getViewport({ scale: scale * 96 / 72 })
                    const c = document.createElement('canvas')
                    c.width = Math.ceil(v.width); c.height = Math.ceil(v.height)
                    const ctx = c.getContext('2d')
                    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height)
                    await page.render({ canvas: c, viewport: v }).promise
                    return c
                },
                async text() { const tc = await page.getTextContent(); return tc.items.map(it => it.str + (it.hasEOL ? '\n' : '')).join('') },
            })
        }
        return { pages, title: stemOf(source.name), dispose: () => task.destroy() }
    }
    if (type === 'slides') {
        const buf = await source.arrayBuffer()
        const { Pptx } = await import('./pptx.js')
        const { OutlineDeck } = await import('./formats.js')
        const deck = ['ppt', 'pps', 'pot', 'odp', 'otp'].includes(e) ? await OutlineDeck.open(buf, e) : await Pptx.open(buf)
        const css = await slideCss()
        const pages = Array.from({ length: deck.count }, (_, i) => ({
            w: deck.width, h: deck.height,
            async html() {
                const { el } = await deck.renderSlide(i)
                el.style.transform = ''
                await inlineElementImages(el)
                return el.outerHTML
            },
            async image(scale) { return htmlPageToCanvas(await this.html(), deck.width, deck.height, scale, css) },
            async text() { const t = await deck.slideText(i); return [t.title, t.text].filter(Boolean).join('\n') },
        }))
        return { pages, title: stemOf(source.name), css, dispose: () => deck.dispose() }
    }
    if (type === 'paged') {
        const buf = await source.arrayBuffer()
        if (['djvu', 'djv'].includes(e)) {
            const m = await import('djvu-rs')
            await m.default()
            const doc = m.WasmDocument.from_bytes(new Uint8Array(buf))
            const pages = Array.from({ length: doc.page_count() }, (_, i) => {
                const pg = doc.page(i)
                return {
                    w: pg.width_at(96), h: pg.height_at(96),
                    async image(scale) {
                        const dpi = Math.round(96 * scale)
                        const pw = pg.width_at(dpi), ph = pg.height_at(dpi)
                        const c = document.createElement('canvas')
                        c.width = pw; c.height = ph
                        c.getContext('2d').putImageData(new ImageData(pg.render(dpi), pw, ph), 0, 0)
                        return c
                    },
                    async text() { return pg.text?.() ?? '' },
                }
            })
            return { pages, title: stemOf(source.name), dispose: () => doc.free?.() }
        }
        const { decodeOfd, decodeXps } = await import('./formats.js')
        const d = e === 'ofd' ? await decodeOfd(buf) : await decodeXps(buf)
        const unit = d.unit === 'mm' ? 96 / 25.4 : 1
        const pages = d.pages.map(p => ({
            get w() { return p.w * unit }, get h() { return p.h * unit },
            async html() {
                let svg = await p.render()
                const holder = document.createElement('div')
                holder.innerHTML = svg
                const el = holder.firstElementChild
                el.setAttribute('width', p.w * unit); el.setAttribute('height', p.h * unit)
                await inlineElementImages(holder)
                return holder.innerHTML
            },
            async image(scale) { return htmlPageToCanvas(await this.html(), p.w * unit, p.h * unit, scale) },
            async text() { const holder = document.createElement('div'); holder.innerHTML = await p.render(); return [...holder.querySelectorAll('text')].map(t => t.textContent).join('\n') },
        }))
        return { pages, title: stemOf(source.name), dispose: () => d.urls?.forEach(u => URL.revokeObjectURL(u)) }
    }
    if (type === 'ebook' && e === 'cbz') {
        const { default: JSZip } = await import('jszip')
        const zip = await JSZip.loadAsync(await source.arrayBuffer())
        const names = Object.keys(zip.files).filter(n => /\.(png|jpe?g|gif|webp|bmp|avif)$/i.test(n) && !zip.files[n].dir).sort(new Intl.Collator('zh', { numeric: true }).compare)
        const pages = []
        for (const n of names) {
            const url = URL.createObjectURL(await zip.file(n).async('blob'))
            const img = await loadImage(url)
            pages.push({ w: img.naturalWidth, h: img.naturalHeight, image: () => canvasFrom(img, img.naturalWidth, img.naturalHeight), url })
        }
        return { pages, title: stemOf(source.name), dispose: () => pages.forEach(p => URL.revokeObjectURL(p.url)) }
    }
    throw new Error('不支持的页面类型')
}

const loadImage = url => new Promise((res, rej) => {
    const img = new Image()
    img.onload = () => res(img)
    img.onerror = () => rej(new Error('图片无法解码'))
    img.src = url
})
function canvasFrom(img, w, h) {
    const c = document.createElement('canvas')
    c.width = w; c.height = h
    c.getContext('2d').drawImage(img, 0, 0, w, h)
    return c
}

// 幻灯片渲染需要的样式（来自应用样式表中的 .pp-* 规则）
async function slideCss() {
    const rules = []
    for (const sheet of document.styleSheets) {
        try { for (const r of sheet.cssRules) if (/\.pp-(slide|el|group|svg|fill|img|media|text|p|bullet|link|table|placeholder|chart|outline)/.test(r.cssText)) rules.push(r.cssText) } catch { /* 跨域样式表 */ }
    }
    return rules.join('\n')
}
async function inlineElementImages(el) {
    for (const img of el.querySelectorAll('img[src^="blob:"]')) img.src = await blobToDataURL(await (await fetch(img.src)).blob())
    for (const img of el.querySelectorAll('image')) {
        const href = img.getAttribute('href') ?? img.getAttribute('xlink:href')
        if (href?.startsWith('blob:')) img.setAttribute('href', await blobToDataURL(await (await fetch(href)).blob()))
    }
    for (const n of el.querySelectorAll('[style*="blob:"]')) {
        const style = n.getAttribute('style')
        const urls = [...style.matchAll(/url\("?(blob:[^")]+)"?\)/g)].map(m => m[1])
        let out = style
        for (const u of urls) out = out.split(u).join(await blobToDataURL(await (await fetch(u)).blob()))
        n.setAttribute('style', out)
    }
    el.querySelectorAll('video, audio').forEach(m => m.remove())
}
// HTML 页面（幻灯片 / SVG）→ 位图：交由主进程在隐藏窗口中截图，保证字体与样式一致
async function htmlPageToCanvas(inner, w, h, scale, css = '') {
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;overflow:hidden;background:#fff}body{zoom:${scale};width:${w}px;height:${h}px;position:relative}${css}.pp-slide{position:absolute;left:0;top:0}</style></head><body>${inner}</body></html>`
    const png = await window.lite.renderPng({ html, width: w, height: h, scale })
    const img = await loadImage(URL.createObjectURL(new Blob([png], { type: 'image/png' })))
    const c = canvasFrom(img, img.naturalWidth, img.naturalHeight)
    URL.revokeObjectURL(img.src)
    return c
}

const MIME = { png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp', bmp: 'image/bmp' }
async function canvasToBytes(c, target, quality = 0.92) {
    if (target === 'bmp') return encodeBmp(c)
    if (target === 'jpg') {
        // JPEG 无透明通道，铺白底
        const w = document.createElement('canvas')
        w.width = c.width; w.height = c.height
        const ctx = w.getContext('2d')
        ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w.width, w.height)
        ctx.drawImage(c, 0, 0)
        c = w
    }
    const blob = await new Promise(r => c.toBlob(r, MIME[target], target === 'png' ? undefined : target === 'webp' ? 0.9 : quality))
    return new Uint8Array(await blob.arrayBuffer())
}
function encodeBmp(c) {
    const { width: w, height: h } = c
    const px = c.getContext('2d').getImageData(0, 0, w, h).data
    const row = Math.ceil(w * 3 / 4) * 4
    const size = 54 + row * h
    const b = new DataView(new ArrayBuffer(size))
    b.setUint16(0, 0x4d42, true); b.setUint32(2, size, true); b.setUint32(10, 54, true)
    b.setUint32(14, 40, true); b.setInt32(18, w, true); b.setInt32(22, h, true)
    b.setUint16(26, 1, true); b.setUint16(28, 24, true); b.setUint32(34, row * h, true)
    b.setInt32(38, 2835, true); b.setInt32(42, 2835, true)
    for (let y = 0; y < h; y++) {
        const off = 54 + (h - 1 - y) * row
        for (let x = 0; x < w; x++) {
            const i = (y * w + x) * 4, a = px[i + 3] / 255
            // 透明像素与白色混合
            b.setUint8(off + x * 3, Math.round(px[i + 2] * a + 255 * (1 - a)))
            b.setUint8(off + x * 3 + 1, Math.round(px[i + 1] * a + 255 * (1 - a)))
            b.setUint8(off + x * 3 + 2, Math.round(px[i] * a + 255 * (1 - a)))
        }
    }
    return new Uint8Array(b.buffer)
}

async function writePages(doc, target, stem, options, progress) {
    const n = doc.pages.length
    const scale = options.scale ?? (doc.single ? 1 : 2)
    const pad = String(n).length
    try {
        if (['png', 'jpg', 'webp', 'bmp'].includes(target)) {
            const out = []
            for (const [i, p] of doc.pages.entries()) {
                progress(`正在渲染第 ${i + 1}/${n} 页…`, 0.1 + 0.85 * i / n)
                const c = await p.image(scale)
                const ext = TARGETS[target].ext
                out.push({ name: n === 1 ? `${stem}.${ext}` : `${stem}_${String(i + 1).padStart(pad, '0')}.${ext}`, data: await canvasToBytes(c, target, options.quality) })
            }
            return out
        }
        if (target === 'txt' || target === 'docx') {
            const texts = []
            for (const [i, p] of doc.pages.entries()) {
                progress(`正在提取第 ${i + 1}/${n} 页文字…`, 0.1 + 0.8 * i / n)
                texts.push((await p.text?.()) ?? '')
            }
            if (target === 'txt') return [{ name: `${stem}.txt`, data: new TextEncoder().encode('\ufeff' + texts.map((t, i) => n > 1 ? `—— 第 ${i + 1} 页 ——\n${t.trim()}` : t.trim()).join('\n\n') + '\n') }]
            const html = texts.map((t, i) => (n > 1 ? `<h2>第 ${i + 1} 页</h2>` : '') + textToHtml(t)).join('\n')
            return [{ name: `${stem}.docx`, data: await htmlToDocx({ title: doc.title, html }) }]
        }
        // PDF / HTML：矢量页面（幻灯片、OFD、XPS）直接嵌入 HTML，位图页面嵌入高清图片
        const isPdf = target === 'pdf'
        if (isPdf) {
            const html = await pagesPrintHtml(doc, doc.pages.map((_, i) => i + 1), scale, progress)
            progress('正在生成 PDF…', 0.9)
            return [{ name: `${stem}.pdf`, data: await printToBytes(html, { ...options, cssPage: true }) }]
        }
        const parts = []
        for (const [i, p] of doc.pages.entries()) {
            progress(`正在处理第 ${i + 1}/${n} 页…`, 0.1 + 0.75 * i / n)
            const c = await p.image(Math.min(scale, 1.5))
            const bytes = await canvasToBytes(c, doc.single ? 'png' : 'jpg', 0.9)
            parts.push({ w: p.w, h: p.h, body: `<img src="${await blobToDataURL(new Blob([bytes], { type: doc.single ? 'image/png' : 'image/jpeg' }))}" style="width:${p.w}px;height:${p.h}px;display:block">` })
        }
        const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>${esc(doc.title ?? '')}</title><style>body{margin:0;background:#e5e7eb;font-family:sans-serif}.pg{margin:24px auto;box-shadow:0 4px 20px rgb(0 0 0/.2);background:#fff;max-width:100%}.pg img{max-width:100%;height:auto !important}</style></head><body>${parts.map(p => `<div class="pg" style="width:${p.w}px">${p.body}</div>`).join('\n')}</body></html>`
        return [{ name: `${stem}.html`, data: new TextEncoder().encode(html) }]
    } finally {
        doc.dispose?.()
    }
}

// 版式页面 → 可打印的 HTML（每页使用自己的 CSS @page 尺寸，与原文页面一一对应）
export async function pagesPrintHtml(doc, list, scale = 2, progress = () => {}) {
    const parts = []
    for (const [k, num] of list.entries()) {
        const p = doc.pages[num - 1]
        progress(`正在处理第 ${num} 页…`, 0.1 + 0.75 * k / list.length)
        let body
        if (p.html) body = await p.html()
        else {
            const c = await p.image(scale)
            const bytes = await canvasToBytes(c, 'jpg', 0.92)
            body = `<img src="${await window.lite.printAsset(bytes, 'jpg')}" style="width:${p.w}px;height:${p.h}px;display:block">`
        }
        parts.push({ w: p.w, h: p.h, body })
    }
    const pagesHtml = parts.map((p, i) => `<style>@page p${i} { size: ${p.w}px ${p.h}px; margin: 0 }</style><div class="pg" style="page:p${i};width:${p.w}px;height:${p.h}px">${p.body}</div>`).join('')
    return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${esc(doc.title ?? '')}</title><style>
        @page { margin: 0 } html, body { margin: 0; padding: 0; background: #fff } .pg { position: relative; overflow: hidden; break-after: page } .pg:last-child { break-after: auto }
        ${doc.css ?? ''} .pp-slide { position: absolute; left: 0; top: 0; transform: none !important }</style></head><body>${pagesHtml}</body></html>`
}

// ================= 表格 =================
async function writeSheet(source, target, stem, options, progress) {
    const XLSX = await import('xlsx')
    const { decodeText } = await import('./encoding.js')
    progress('正在解析表格…', 0.1)
    const buf = new Uint8Array(await source.arrayBuffer())
    const wb = ['csv', 'tsv'].includes(source.ext)
        ? XLSX.read(decodeText(buf).text, { type: 'string', FS: source.ext === 'tsv' ? '\t' : undefined })
        : XLSX.read(buf, { type: 'array', cellFormula: true, cellDates: true })
    progress('正在写出…', 0.6)
    const names = wb.SheetNames
    const each = fn => names.map(n => ({ name: names.length > 1 ? `${stem}_${safe(n)}` : stem, sheet: wb.Sheets[n], title: n, data: null })).map(fn)
    if (['xlsx', 'xls', 'ods'].includes(target)) {
        const bookType = { xlsx: 'xlsx', xls: 'biff8', ods: 'ods' }[target]
        return [{ name: `${stem}.${target}`, data: new Uint8Array(XLSX.write(wb, { type: 'array', bookType, compression: true })) }]
    }
    if (target === 'csv' || target === 'tsv') {
        return each(s => ({ name: `${s.name}.${target}`, data: new TextEncoder().encode('\ufeff' + XLSX.utils.sheet_to_csv(s.sheet, { FS: target === 'tsv' ? '\t' : ',', blankrows: false })) }))
    }
    if (target === 'txt') {
        const text = names.map(n => (names.length > 1 ? `=== ${n} ===\n` : '') + XLSX.utils.sheet_to_csv(wb.Sheets[n], { FS: '\t', blankrows: false })).join('\n\n')
        return [{ name: `${stem}.txt`, data: new TextEncoder().encode('\ufeff' + text) }]
    }
    if (target === 'json') {
        const obj = Object.fromEntries(names.map(n => [n, XLSX.utils.sheet_to_json(wb.Sheets[n], { defval: null, raw: true })]))
        return [{ name: `${stem}.json`, data: new TextEncoder().encode(JSON.stringify(names.length === 1 ? obj[names[0]] : obj, null, 2)) }]
    }
    // HTML / PDF：每个工作表一个表格
    const html = names.map(n => `${names.length > 1 ? `<h2>${esc(n)}</h2>` : ''}${XLSX.utils.sheet_to_html(wb.Sheets[n], { header: '', footer: '' }).replace(/^[\s\S]*?<table/, '<table').replace(/<\/table>[\s\S]*$/, '</table>')}`).join('\n')
    const doc = { title: stem, html: `<div class="sheet-export">${html}</div>`, css: '.sheet-export table{border-collapse:collapse;font-size:12px;margin-bottom:24px}.sheet-export td{border:1px solid #bbb;padding:2px 6px;white-space:nowrap}.sheet-export h2{font-size:16px}' }
    if (target === 'html') return [{ name: `${stem}.html`, data: new TextEncoder().encode(await docHtml(doc)) }]
    return [{ name: `${stem}.pdf`, data: await printToBytes(await docHtml(doc, { forPrint: true }), { ...options, landscape: options.landscape ?? true }) }]
}
const safe = s => s.replace(/[\\/:*?"<>|]/g, '_').slice(0, 60)

// ================= 音频 =================
async function writeAudio(source, target, stem, options, progress) {
    progress('正在解码音频…', 0.05)
    const buf = await source.arrayBuffer()
    let channels, sampleRate
    if (['mid', 'midi', 'rmi', 'kar'].includes(source.ext)) ({ channels, sampleRate } = await renderMidi(buf, progress))
    else {
        const ctx = new OfflineAudioContext(2, 1, 44100)
        const ab = await ctx.decodeAudioData(buf.slice(0))
        sampleRate = ab.sampleRate
        channels = Array.from({ length: Math.min(2, ab.numberOfChannels) }, (_, i) => ab.getChannelData(i))
    }
    progress('正在编码…', 0.7)
    if (target === 'wav') return [{ name: `${stem}.wav`, data: encodeWav(channels, sampleRate) }]
    return [{ name: `${stem}.mp3`, data: await encodeMp3(channels, sampleRate, options.bitrate ?? 192, progress) }]
}

async function renderMidi(buf, progress) {
    const { BasicMIDI, SoundBankLoader, SpessaSynthProcessor, SpessaSynthSequencer } = await import('spessasynth_core')
    const sf = await (await fetch(new URL('./soundfonts/GeneralUserGS.sf3', location.href))).arrayBuffer()
    const midi = BasicMIDI.fromArrayBuffer(buf)
    const bank = SoundBankLoader.fromArrayBuffer(sf)
    const sampleRate = 44100
    const synth = new SpessaSynthProcessor(sampleRate, { eventsEnabled: false })
    synth.soundBankManager.addSoundBank(bank, 'main')
    await synth.processorInitialized
    const seq = new SpessaSynthSequencer(synth)
    seq.loadNewSongList([midi])
    seq.loopCount = 0
    seq.play()
    const total = Math.ceil(sampleRate * (midi.duration + 2))
    const L = new Float32Array(total), R = new Float32Array(total)
    const BLOCK = 128
    let filled = 0, tick = 0
    while (filled < total) {
        seq.processTick()
        const n = Math.min(BLOCK, total - filled)
        synth.process(L, R, filled, n)
        filled += n
        // 定期让出主线程，避免界面卡死
        if (++tick % 2000 === 0) { progress(`正在合成 MIDI… ${Math.round(filled / total * 100)}%`, 0.05 + 0.6 * filled / total); await new Promise(r => setTimeout(r)) }
    }
    return { channels: [L, R], sampleRate }
}

function encodeWav(channels, sampleRate) {
    const n = channels[0].length, ch = channels.length
    const b = new DataView(new ArrayBuffer(44 + n * ch * 2))
    const w = (o, s) => { for (let i = 0; i < s.length; i++) b.setUint8(o + i, s.charCodeAt(i)) }
    w(0, 'RIFF'); b.setUint32(4, 36 + n * ch * 2, true); w(8, 'WAVE'); w(12, 'fmt ')
    b.setUint32(16, 16, true); b.setUint16(20, 1, true); b.setUint16(22, ch, true); b.setUint32(24, sampleRate, true)
    b.setUint32(28, sampleRate * ch * 2, true); b.setUint16(32, ch * 2, true); b.setUint16(34, 16, true)
    w(36, 'data'); b.setUint32(40, n * ch * 2, true)
    let o = 44
    for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) {
        const v = Math.max(-1, Math.min(1, channels[c][i]))
        b.setInt16(o, v < 0 ? v * 0x8000 : v * 0x7fff, true)
        o += 2
    }
    return new Uint8Array(b.buffer)
}

async function encodeMp3(channels, sampleRate, kbps, progress) {
    const { Mp3Encoder } = await import('@breezystack/lamejs')
    // lame 支持的采样率
    const rates = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000]
    if (!rates.includes(sampleRate)) {
        channels = channels.map(c => resample(c, sampleRate, 44100))
        sampleRate = 44100
    }
    const enc = new Mp3Encoder(channels.length, sampleRate, kbps)
    const toI16 = f => { const o = new Int16Array(f.length); for (let i = 0; i < f.length; i++) { const v = Math.max(-1, Math.min(1, f[i])); o[i] = v < 0 ? v * 0x8000 : v * 0x7fff } return o }
    const L = toI16(channels[0]), R = channels[1] ? toI16(channels[1]) : null
    const chunks = []
    const BLOCK = 1152 * 20
    for (let i = 0; i < L.length; i += BLOCK) {
        const out = R ? enc.encodeBuffer(L.subarray(i, i + BLOCK), R.subarray(i, i + BLOCK)) : enc.encodeBuffer(L.subarray(i, i + BLOCK))
        if (out.length) chunks.push(new Uint8Array(out))
        if ((i / BLOCK) % 50 === 0) { progress(`正在编码 MP3… ${Math.round(i / L.length * 100)}%`, 0.7 + 0.28 * i / L.length); await new Promise(r => setTimeout(r)) }
    }
    const end = enc.flush()
    if (end.length) chunks.push(new Uint8Array(end))
    const size = chunks.reduce((s, c) => s + c.length, 0)
    const out = new Uint8Array(size)
    let o = 0
    for (const c of chunks) { out.set(c, o); o += c.length }
    return out
}
function resample(data, from, to) {
    const ratio = from / to, n = Math.round(data.length / ratio)
    const out = new Float32Array(n)
    for (let i = 0; i < n; i++) {
        const x = i * ratio, j = Math.floor(x), f = x - j
        out[i] = (data[j] ?? 0) * (1 - f) + (data[j + 1] ?? data[j] ?? 0) * f
    }
    return out
}

// ================= 压缩包 =================
async function writeArchive(source, target, stem, options, progress) {
    const { Archive, ArchiveFormat, ArchiveCompression } = await import('libarchive.js')
    Archive.init({ workerUrl: new URL('./vendor/libarchive/worker-bundle.js', location.href).href })
    progress('正在解压…', 0.1)
    const arc = await Archive.open(await source.file())
    if (await arc.hasEncryptedData()) {
        const pwd = options.password ?? (await (await import('./dom.js')).prompt({ title: '压缩包已加密', message: '请输入解压密码', type: 'password' }))
        if (pwd == null) throw new Error('需要密码才能转换此压缩包')
        await arc.usePassword(pwd)
    }
    await arc.extractFiles()
    const files = (await arc.getFilesArray()).filter(f => f.file instanceof File).map(({ file, path }) => ({ file, pathname: (path ?? '') + file.name }))
    await arc.close?.()
    progress(`正在打包 ${files.length} 个文件…`, 0.5)
    if (target === 'zip') {
        // ZIP 使用 JSZip 生成，保证中文文件名（UTF-8 标记）在 Windows 资源管理器中正常显示
        const { default: JSZip } = await import('jszip')
        const zip = new JSZip()
        for (const f of files) zip.file(f.pathname, f.file)
        return [{ name: `${stem}.zip`, data: await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE', compressionOptions: { level: 6 } }, m => progress(`正在压缩… ${Math.round(m.percent)}%`, 0.5 + m.percent / 220)) }]
    }
    if (target === '7z') {
        // libarchive.js 的写出缓冲区计算有缺陷，7z 由内置写出器生成（存储模式）
        const { write7z } = await import('./sevenzip.js')
        const list = []
        for (const f of files) list.push({ pathname: f.pathname, data: new Uint8Array(await f.file.arrayBuffer()) })
        return [{ name: `${stem}.7z`, data: write7z(list) }]
    }
    const format = ArchiveFormat.USTAR
    const compression = target === 'tgz' ? ArchiveCompression.GZIP : ArchiveCompression.NONE
    const out = await Archive.write({ files, outputFileName: `${stem}.${TARGETS[target].ext}`, compression, format, passphrase: null })
    return [{ name: `${stem}.${TARGETS[target].ext}`, data: new Uint8Array(await out.arrayBuffer()) }]
}

// ---------- 供批量转换使用：由路径创建 Source ----------
export const sourceFromPath = (path, size) => Source.fromPath(path, size)
export { kindOf, canvasToBytes }
export { typeOf, extOf }
