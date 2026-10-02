// HTML（文档编辑器内容）→ LaTeX 源码
// 生成可用 XeLaTeX / ctex 编译的完整文档：标题、章节、列表、表格、图片、公式、脚注、链接、对齐、颜色
const SPECIAL = { '\\': '\\textbackslash{}', '{': '\\{', '}': '\\}', '$': '\\$', '&': '\\&', '#': '\\#', '%': '\\%', '_': '\\_', '^': '\\textasciicircum{}', '~': '\\textasciitilde{}' }
const escTex = s => s.replace(/[\\{}$&#%_^~]/g, c => SPECIAL[c]).replace(/\u00a0/g, '~')

function hexColor(c) {
    if (!c) return null
    const ctx = hexColor.ctx ??= document.createElement('canvas').getContext('2d')
    ctx.fillStyle = '#000000'
    ctx.fillStyle = c
    const v = ctx.fillStyle
    if (v.startsWith('#')) return v.slice(1).toUpperCase()
    const m = v.match(/[\d.]+/g)
    if (!m || (m[3] !== undefined && Number(m[3]) === 0)) return null
    return m.slice(0, 3).map(n => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase()
}

// page: { title?, author?, paper, landscape, margin, fontSize }；images: 收集到的内嵌图片 [{ name, dataURL }]
export function htmlToLatex(root, page = {}) {
    const lossy = new Set()
    const images = []
    const pkgs = new Set(['ctex', 'amsmath', 'amssymb', 'graphicx', 'geometry', 'hyperref', 'xcolor'])
    let hasToc = false

    const inline = n => {
        if (n.nodeType === 3) return escTex(n.textContent)
        if (n.nodeType !== 1) return ''
        const t = n.tagName
        const kids = () => [...n.childNodes].map(inline).join('')
        if (n.classList.contains('doc-math')) {
            if (n.dataset.orig) return n.classList.contains('block') ? `\n${n.dataset.orig}\n` : n.dataset.orig
            return n.classList.contains('block') ? `\n\\[\n${n.dataset.tex}\n\\]\n` : `$${n.dataset.tex}$`
        }
        if (n.classList.contains('tex-src')) return n.dataset.src
        if (n.classList.contains('tex-anchor')) return n.dataset.label ? `\\label{${n.dataset.label}}` : ''
        if (n.classList.contains('doc-eqno') || n.classList.contains('tex-secnum') || n.classList.contains('tex-chapnum')) return ''
        if (n.classList.contains('tex-logo')) return `\\${n.dataset.cmd}{}`
        if (n.classList.contains('tex-fn')) return n.dataset.fn != null ? `\\footnote{${n.dataset.fn}}` : n.dataset.thanks != null ? `\\thanks{${n.dataset.thanks}}` : ''
        if (n.classList.contains('tex-bib-label')) return ''
        if (n.classList.contains('doc-footnote-ref')) {
            const fn = root.querySelector(`#${CSS.escape(n.dataset.fn ?? '')}`)
            return fn ? `\\footnote{${[...fn.childNodes].map(inline).join('').replace(/\s*↩\s*$/, '')}}` : ''
        }
        let s
        switch (t) {
            case 'B': case 'STRONG': s = `\\textbf{${kids()}}`; break
            case 'I': case 'EM': s = `\\textit{${kids()}}`; break
            case 'U': pkgs.add('ulem'); s = `\\uline{${kids()}}`; break
            case 'S': case 'STRIKE': case 'DEL': pkgs.add('ulem'); s = `\\sout{${kids()}}`; break
            case 'SUP': s = `\\textsuperscript{${kids()}}`; break
            case 'SUB': s = `\\textsubscript{${kids()}}`; break
            case 'CODE': s = `\\texttt{${kids()}}`; break
            case 'MARK': pkgs.add('soul'); s = `\\hl{${kids()}}`; break
            case 'BR': return '\\\\\n'
            case 'A': {
                const href = n.getAttribute('href') ?? ''
                if (href.startsWith('#')) s = kids()
                else s = `\\href{${href.replace(/[%#]/g, '\\$&')}}{${kids()}}`
                break
            }
            case 'IMG': return image(n)
            default: s = kids()
        }
        const css = n.style
        if (css?.color) { const c = hexColor(css.color); if (c && c !== '000000') s = `\\textcolor[HTML]{${c}}{${s}}` }
        if (css?.backgroundColor) { const c = hexColor(css.backgroundColor); if (c && c !== 'FFFFFF') s = `\\colorbox[HTML]{${c}}{${s}}` }
        if (css?.fontWeight && Number(css.fontWeight) >= 600 && t !== 'B' && t !== 'STRONG') s = `\\textbf{${s}}`
        if (css?.fontStyle === 'italic' && t !== 'I' && t !== 'EM') s = `\\textit{${s}}`
        if (css?.fontSize) lossy.add('字号')
        if (css?.fontFamily) lossy.add('字体')
        return s
    }

    const image = img => {
        const src = img.getAttribute('src') ?? ''
        const w = img.style.width || (img.getAttribute('width') ? img.getAttribute('width') + 'px' : '')
        let opt = 'width=0.8\\linewidth'
        if (/%$/.test(w)) opt = `width=${(parseFloat(w) / 100).toFixed(2)}\\linewidth`
        else if (/px$/.test(w)) opt = `width=${Math.min(1, parseFloat(w) / 680).toFixed(2)}\\linewidth`
        let file = img.dataset.file
        if (!file || src.startsWith('data:')) {
            const ext = (/^data:image\/(\w+)/.exec(src)?.[1] ?? 'png').replace('jpeg', 'jpg').replace('svg+xml', 'svg')
            file = `images/image${images.length + 1}.${ext === 'svg' ? 'png' : ext}`
            images.push({ name: file, src })
        } else if (src.startsWith('media://')) {
            // 引用原目录中的图片：另存到其他目录时需要一并复制
            const ext = /\.\w+$/.test(file) ? '' : (/(\.\w+)$/.exec(decodeURIComponent(src))?.[1] ?? '')
            images.push({ name: file + ext, src, linked: true })
        }
        return `\\includegraphics[${opt}]{${file}}`
    }

    const align = (el, body) => {
        const a = el.style?.textAlign
        if (a === 'center') return `\\begin{center}\n${body}\n\\end{center}`
        if (a === 'right') return `\\begin{flushright}\n${body}\n\\end{flushright}`
        return body
    }

    const blocks = []
    const title = {}
    const block = (el, out = blocks, depth = 0) => {
        if (el.nodeType === 3) { const t = el.textContent.trim(); if (t) out.push(escTex(t)); return }
        if (el.nodeType !== 1) return
        const t = el.tagName
        if (el.classList.contains('doc-footnotes')) return
        const ds = el.dataset ?? {}
        if (ds.maketitle) {
            const part = sel => { const x = el.querySelector(sel); return x ? [...x.childNodes].map(inline).join('').trim() : null }
            title.title = part('h1') ?? ''
            title.author = (part('.tex-author') ?? '').replace(/\s*·\s*/g, ' \\and ')
            title.date = part('.tex-date')
            out.push('\\maketitle')
            return
        }
        if (ds.toc) { out.push('\\tableofcontents'); return }
        if (ds.bib != null && el.classList.contains('tex-bibliography')) { out.push(`\\begin{thebibliography}${ds.bib.trimEnd()}\n\\end{thebibliography}`); return }
        if (ds.env) {
            // 摘要、定理、证明等环境：去掉自动生成的标题后递归转换内容
            const c = el.cloneNode(true)
            c.querySelector(':scope > .tex-abstract-title, :scope > b, :scope > em')?.remove()
            c.querySelector('.tex-qed')?.remove()
            const sub = []
            for (const x of c.childNodes) block(x, sub, depth)
            const opt = ds.title ? `[${ds.title}]` : ''
            out.push(`\\begin{${ds.env}}${opt}\n${sub.join('\n\n').replace(/^\.\s*/, '')}\n\\end{${ds.env}}`)
            return
        }
        if (el.classList.contains('tex-table-wrap')) { for (const c of el.childNodes) block(c, out, depth); return }
        if (el.classList.contains('tex-center')) {
            const sub = []
            for (const c of el.childNodes) block(c, sub, depth)
            out.push(el.closest('figure') ? sub.join('\n') : `\\begin{center}\n${sub.join('\n\n')}\n\\end{center}`)
            return
        }
        if (el.classList.contains('doc-toc')) { hasToc = true; out.push('\\tableofcontents'); return }
        if (el.classList.contains('page-break')) { out.push('\\newpage'); return }
        if (el.classList.contains('doc-math-block')) {
            const m = el.querySelector('.doc-math')
            if (m) out.push(m.dataset.orig ?? `\\begin{equation}\n${m.dataset.tex}\n\\end{equation}`)
            return
        }
        if (el.classList.contains('doc-title')) { out.push(`\\begin{center}\n{\\LARGE\\bfseries ${[...el.childNodes].map(inline).join('')}}\n\\end{center}`); return }
        if (/^H[1-6]$/.test(t)) {
            const cmd = ['section', 'subsection', 'subsubsection', 'paragraph', 'subparagraph', 'subparagraph'][Number(t[1]) - 1]
            const numbered = el.querySelector('.tex-secnum, .tex-chapnum') ? '' : el.dataset.numbered === 'false' ? '*' : ''
            const clone = el.cloneNode(true)
            clone.querySelectorAll('.tex-secnum, .tex-chapnum').forEach(x => x.remove())
            out.push(`\\${cmd}${numbered}{${[...clone.childNodes].map(inline).join('').trim()}}`)
            return
        }
        if (t === 'P' || t === 'DIV') {
            if ([...el.children].some(c => /^(P|DIV|H\d|UL|OL|TABLE|BLOCKQUOTE|PRE|HR|FIGURE)$/.test(c.tagName))) { for (const c of el.childNodes) block(c, out, depth); return }
            const body = [...el.childNodes].map(inline).join('').trim()
            if (!body) return
            const indent = el.style.textIndent ? '' : ''
            out.push(align(el, indent + body))
            return
        }
        if (t === 'BLOCKQUOTE') { out.push(`\\begin{quote}\n${[...el.childNodes].map(inline).join('').trim()}\n\\end{quote}`); return }
        if (t === 'PRE') { pkgs.add('listings'); out.push(`\\begin{lstlisting}\n${el.textContent.replace(/\n$/, '')}\n\\end{lstlisting}`); return }
        if (t === 'HR') { out.push('\\noindent\\rule{\\linewidth}{0.4pt}'); return }
        if (t === 'DL') {
            const lines = ['\\begin{description}']
            for (const dt of el.querySelectorAll(':scope > dt')) {
                const dd = dt.nextElementSibling?.tagName === 'DD' ? dt.nextElementSibling : null
                lines.push(`  \\item[${[...dt.childNodes].map(inline).join('').trim()}] ${dd ? [...dd.childNodes].map(inline).join('').trim() : ''}`)
            }
            lines.push('\\end{description}')
            out.push(lines.join('\n'))
            return
        }
        if (t === 'UL' || t === 'OL') {
            const env = t === 'OL' ? 'enumerate' : 'itemize'
            const lines = [`\\begin{${env}}`]
            for (const li of el.children) {
                if (li.tagName !== 'LI') continue
                const nested = [...li.children].filter(c => c.tagName === 'UL' || c.tagName === 'OL')
                const lbl = li.querySelector(':scope > .tex-li-label')
                const text = [...li.childNodes].filter(c => !nested.includes(c) && c !== lbl).map(inline).join('').trim()
                const custom = lbl ? `[${[...lbl.childNodes].map(inline).join('').trim()}] ` : ''
                const mark = custom || (li.classList.contains('task') ? (li.classList.contains('done') ? '[$\\boxtimes$] ' : '[$\\square$] ') : '')
                lines.push(`  \\item${mark ? mark : ' '}${text}`)
                for (const c of nested) { const sub = []; block(c, sub, depth + 1); lines.push(...sub.map(s => s.replace(/^/gm, '    '))) }
            }
            lines.push(`\\end{${env}}`)
            out.push(lines.join('\n'))
            return
        }
        if (t === 'TABLE') {
            const rows = [...el.querySelectorAll('tr')]
            if (!rows.length) return
            const cols = Math.max(...rows.map(r => [...r.children].reduce((s, c) => s + (c.colSpan || 1), 0)))
            if (el.querySelector('[rowspan]')) { pkgs.add('multirow'); lossy.add('跨行合并单元格（已近似）') }
            const spec = el.dataset.spec ?? `|${'l|'.repeat(cols)}`
            const ruled = !el.dataset.spec || spec.includes('|')
            const inFloat = !!el.closest('figure')
            const lines = [...(inFloat ? [] : ['\\begin{table}[htbp]', '\\centering']), `\\begin{tabular}{${spec}}`, ...(ruled ? ['\\hline'] : [])]
            for (const tr of rows) {
                const cells = [...tr.children].map(td => {
                    let s = [...td.childNodes].map(inline).join('').replace(/\\\\\n/g, ' ').trim()
                    if (td.tagName === 'TH') s = `\\textbf{${s}}`
                    if (td.colSpan > 1) s = `\\multicolumn{${td.colSpan}}{${ruled ? '|c|' : 'c'}}{${s}}`
                    if (td.rowSpan > 1) s = `\\multirow{${td.rowSpan}}{*}{${s}}`
                    return s
                })
                lines.push(cells.join(' & ') + (ruled ? ' \\\\ \\hline' : ' \\\\'))
            }
            lines.push('\\end{tabular}')
            const cap = el.querySelector('caption')
            if (cap && !inFloat) lines.splice(2, 0, `\\caption{${[...cap.childNodes].map(inline).join('')}}`)
            if (!inFloat) lines.push('\\end{table}')
            out.push(lines.join('\n'))
            return
        }
        if (t === 'FIGURE') {
            // 图 / 表浮动体：保留原环境名，内容（图片、表格、居中块、\label）递归转换，题注去掉自动编号
            const env = el.dataset.float === 'table' || el.classList.contains('tex-table') || el.querySelector(':scope > table, :scope > .tex-table-wrap') ? 'table' : 'figure'
            const cap = el.querySelector(':scope > figcaption')
            const c = el.cloneNode(true)
            c.querySelector(':scope > figcaption')?.remove()
            const sub = []
            for (const x of c.childNodes) {
                if (x.nodeType === 1 && x.tagName === 'IMG') sub.push(image(x))
                else block(x, sub, depth)
            }
            let capText = ''
            if (cap) { const cc = cap.cloneNode(true); cc.querySelector(':scope > b')?.remove(); capText = [...cc.childNodes].map(inline).join('').trim() }
            const capLine = capText ? `\\caption{${capText}}` : ''
            out.push([`\\begin{${env}}[htbp]`, '\\centering', env === 'table' ? capLine : '', ...sub, env === 'table' ? '' : capLine, `\\end{${env}}`].filter(Boolean).join('\n'))
            return
        }
        if (t === 'IMG') { out.push(`\\begin{center}\n${image(el)}\n\\end{center}`); return }
        if (t === 'HEADER' || t === 'SECTION' || t === 'ARTICLE' || t === 'NAV') { for (const c of el.childNodes) block(c, out, depth); return }
        const s = inline(el).trim()
        if (s) out.push(s)
    }

    for (const c of root.childNodes) block(c)

    const m = page.margin ?? { top: 25, bottom: 25, left: 25, right: 25 }
    const paper = { A4: 'a4paper', A5: 'a5paper', B5: 'b5paper', Letter: 'letterpaper' }[page.paper] ?? 'a4paper'
    const fs = Math.round((page.fontSize ?? 16) * 0.75)
    const cls = fs <= 10 ? '10pt' : fs <= 11 ? '11pt' : '12pt'
    const pre = [
        `\\documentclass[${cls},${paper}${page.landscape ? ',landscape' : ''}]{article}`,
        ...[...pkgs].sort().map(p => p === 'ctex' ? '\\usepackage[UTF8]{ctex}' : `\\usepackage{${p}}`),
        `\\geometry{top=${m.top}mm,bottom=${m.bottom}mm,left=${m.left}mm,right=${m.right}mm}`,
        '\\hypersetup{colorlinks=true,linkcolor=blue,urlcolor=blue}',
    ]
    if (pkgs.has('listings')) pre.push('\\lstset{basicstyle=\\ttfamily\\small,breaklines=true,frame=single}')
    if (title.title != null) {
        pre.push('', `\\title{${title.title}}`)
        if (title.author) pre.push(`\\author{${title.author}}`)
        pre.push(title.date == null ? '\\date{\\today}' : `\\date{${title.date}}`)
    }
    void hasToc
    const tex = `${pre.join('\n')}\n\n\\begin{document}\n\n${blocks.join('\n\n')}\n\n\\end{document}\n`
    return { tex, images, lossy: [...lossy] }
}
