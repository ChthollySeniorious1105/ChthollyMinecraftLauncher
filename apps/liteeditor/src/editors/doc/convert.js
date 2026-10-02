// 文档格式转换：HTML ⇄ Markdown、HTML → DOCX、DOCX → HTML
import { marked } from 'marked'
import mammoth from 'mammoth/mammoth.browser.js'

// ---------- Markdown → HTML ----------
export function mdToHTML(md) {
    // 公式：$$...$$ 与 $...$ 转为可编辑的公式节点
    const math = []
    const src = md
        .replace(/\$\$([\s\S]+?)\$\$/g, (_, t) => { math.push({ t: t.trim(), block: true }); return `\u0000M${math.length - 1}\u0000` })
        .replace(/(^|[^\\$])\$([^$\n]+?)\$/g, (_, a, t) => { math.push({ t: t.trim(), block: false }); return `${a}\u0000M${math.length - 1}\u0000` })
    let html = marked.parse(src, { gfm: true, breaks: false })
    html = html.replace(/\u0000M(\d+)\u0000/g, (_, i) => {
        const m = math[i]
        return `<span class="doc-math${m.block ? ' block' : ''}" data-tex="${attr(m.t)}" contenteditable="false"></span>`
    })
    // 任务列表
    html = html.replace(/<li><input (checked="" )?disabled="" type="checkbox"> ?/g, (_, c) => `<li class="task${c ? ' done' : ''}">`)
    return html
}

// ---------- HTML → Markdown ----------
export function htmlToMD(root) {
    const lossy = new Set()
    const out = []
    const inline = n => {
        if (n.nodeType === 3) return n.textContent.replace(/([*_`\\[\]])/g, '\\$1').replace(/ /g, ' ')
        if (n.nodeType !== 1) return ''
        const t = n.tagName, inner = () => [...n.childNodes].map(inline).join('')
        if (n.classList.contains('doc-math')) return n.classList.contains('block') ? `\n$$\n${n.dataset.tex}\n$$\n` : `$${n.dataset.tex}$`
        switch (t) {
            case 'B': case 'STRONG': return wrap(inner(), '**')
            case 'I': case 'EM': return wrap(inner(), '*')
            case 'S': case 'STRIKE': case 'DEL': return wrap(inner(), '~~')
            case 'CODE': return '`' + n.textContent + '`'
            case 'A': return `[${inner()}](${n.getAttribute('href') ?? ''})`
            case 'IMG': return `![${n.alt ?? ''}](${n.getAttribute('src')})`
            case 'BR': return '  \n'
            case 'SUP': case 'SUB': case 'U': case 'MARK': lossy.add('下划线 / 上下标 / 高亮'); return inner()
            case 'SPAN': case 'FONT': if (n.getAttribute('style')) lossy.add('字体、字号与颜色'); return inner()
            default: return inner()
        }
    }
    const block = (n, depth = 0) => {
        if (n.nodeType === 3) { const t = n.textContent.trim(); if (t) out.push(t, ''); return }
        if (n.nodeType !== 1) return
        const t = n.tagName
        if (/^H[1-6]$/.test(t)) { out.push('#'.repeat(Number(t[1])) + ' ' + inline(n).trim(), ''); return }
        if (t === 'P' || t === 'DIV') {
            if (n.classList.contains('page-break')) { out.push('<div style="page-break-after: always"></div>', ''); lossy.add('分页符'); return }
            if (n.classList.contains('doc-toc')) { lossy.add('目录'); return }
            if (n.style?.textAlign && n.style.textAlign !== 'left' && n.style.textAlign !== 'justify') lossy.add('段落对齐')
            const s = inline(n).trim()
            out.push(s, '')
            return
        }
        if (t === 'BLOCKQUOTE') { out.push(...inline(n).trim().split('\n').map(l => '> ' + l), ''); return }
        if (t === 'PRE') { out.push('```', n.textContent.replace(/\n$/, ''), '```', ''); return }
        if (t === 'HR') { out.push('---', ''); return }
        if (t === 'UL' || t === 'OL') {
            let i = 1
            for (const li of n.children) {
                if (li.tagName !== 'LI') continue
                const nested = [...li.children].filter(c => c.tagName === 'UL' || c.tagName === 'OL')
                const text = [...li.childNodes].filter(c => !nested.includes(c)).map(inline).join('').trim()
                const mark = t === 'OL' ? `${i++}.` : li.classList.contains('task') ? (li.classList.contains('done') ? '- [x]' : '- [ ]') : '-'
                out.push('  '.repeat(depth) + mark + ' ' + text)
                for (const c of nested) { const save = out.length; block(c, depth + 1); if (out[out.length - 1] === '') out.pop(); void save }
            }
            out.push('')
            return
        }
        if (t === 'TABLE') {
            const rows = [...n.querySelectorAll('tr')].map(tr => [...tr.children].map(c => inline(c).replace(/\|/g, '\\|').replace(/\n/g, ' ').trim()))
            if (!rows.length) return
            if (n.querySelector('[colspan],[rowspan]')) lossy.add('合并单元格')
            const w = Math.max(...rows.map(r => r.length))
            const pad = r => [...r, ...Array(w - r.length).fill('')]
            out.push('| ' + pad(rows[0]).join(' | ') + ' |', '|' + ' --- |'.repeat(w), ...rows.slice(1).map(r => '| ' + pad(r).join(' | ') + ' |'), '')
            return
        }
        if (t === 'FIGURE' || t === 'IMG') { out.push(inline(n), ''); return }
        for (const c of n.childNodes) block(c, depth)
    }
    for (const c of root.childNodes) block(c)
    return { md: out.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n', lossy: [...lossy] }
}
const wrap = (s, m) => s.trim() ? m + s + m : s

// ---------- DOCX → HTML ----------
export async function docxToHTML(bytes) {
    const styleMap = [
        "p[style-name='Title'] => h1.doc-title:fresh",
        "p[style-name='Subtitle'] => p.doc-subtitle:fresh",
        "p[style-name='Quote'] => blockquote:fresh",
        "p[style-name='Intense Quote'] => blockquote:fresh",
        "r[style-name='Code'] => code",
        "p[style-name='Code'] => pre:separator('\\n')",
        'u => u', 'strike => s',
    ]
    const r = await mammoth.convertToHtml({ arrayBuffer: bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) }, {
        styleMap, includeDefaultStyleMap: true,
        convertImage: mammoth.images.imgElement(img => img.read('base64').then(b => ({ src: `data:${img.contentType};base64,${b}` }))),
    })
    // mammoth 不保留字体颜色 / 字号 / 对齐：从 document.xml 补充段落对齐
    const html = await restoreAlignment(bytes, r.value)
    return { html, messages: r.messages }
}

async function restoreAlignment(bytes, html) {
    try {
        const JSZip = (await import('jszip')).default
        const zip = await JSZip.loadAsync(bytes)
        const xml = await zip.file('word/document.xml')?.async('text')
        if (!xml) return html
        const doc = new DOMParser().parseFromString(xml, 'application/xml')
        const W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
        const paras = [...doc.getElementsByTagNameNS(W, 'body')[0].children].filter(p => p.localName === 'p')
        const aligns = paras.map(p => {
            const jc = p.getElementsByTagNameNS(W, 'jc')[0]
            const hasText = [...p.getElementsByTagNameNS(W, 't')].some(t => t.textContent.trim()) || p.getElementsByTagNameNS(W, 'drawing').length
            return hasText ? jc?.getAttributeNS(W, 'val') ?? jc?.getAttribute('w:val') ?? null : undefined
        }).filter(a => a !== undefined)
        const d = document.createElement('div')
        d.innerHTML = html
        const blocks = [...d.children].filter(b => /^(P|H[1-6])$/.test(b.tagName) && (b.textContent.trim() || b.querySelector('img')))
        const map = { center: 'center', right: 'right', end: 'right', both: 'justify', distribute: 'justify' }
        blocks.forEach((b, i) => { const a = map[aligns[i]]; if (a) b.style.textAlign = a })
        return d.innerHTML
    } catch { return html }
}

const attr = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
export { attr }
