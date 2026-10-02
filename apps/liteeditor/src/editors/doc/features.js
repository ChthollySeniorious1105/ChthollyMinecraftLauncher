// 文字处理器：插入对象、表格、公式、目录、脚注、查找替换、粘贴
import katex from 'katex'
import { h, toast, dialog, formDialog, uid } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { pickImage, blobToDataURL } from '../../core/files.js'
import { mdToHTML } from './convert.js'
import { escapeHTML } from './index.js'

const SYMBOLS = [
    ['常用', '，。、；：？！“”‘’（）【】《》——……·￥°℃‰§№★☆●○◆◇■□▲△※→←↑↓↔⇒⇔✓✗'],
    ['数学', '±×÷≈≠≤≥∞∑∏∫∮√∂∇∈∉⊂⊃⊆⊇∪∩∧∨¬∀∃∅∠⊥∥≅∽∝πθαβγδεζηλμνξρστφχψωΔΣΩΦΨΓΛ'],
    ['上下标', '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻ⁿ₀₁₂₃₄₅₆₇₈₉₊₋'],
    ['序号', '①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ㈠㈡㈢㈣㈤'],
    ['货币单位', '€£¥$¢₩₽㎡㎝㎜㎞㎏㎎㏄'],
]
const MATH_SAMPLES = [
    ['分数', '\\frac{a}{b}'], ['根式', '\\sqrt[n]{x}'], ['上下标', 'x_i^2'], ['求和', '\\sum_{i=1}^{n} a_i'],
    ['积分', '\\int_{a}^{b} f(x)\\,dx'], ['极限', '\\lim_{n\\to\\infty}\\left(1+\\frac{1}{n}\\right)^n=e'],
    ['矩阵', '\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}'], ['方程组', '\\begin{cases} x+y=2 \\\\ x-y=0 \\end{cases}'],
    ['求根公式', 'x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}'], ['欧拉公式', 'e^{i\\pi}+1=0'],
]

export function installFeatures(Ed) {
    const P = Ed.prototype

    // ---------- 通用插入 ----------
    P.insertHTML = function (html, label = '插入') {
        this.focusBody()
        this.restoreSel(this.lastSel)
        this.inCommand = true
        document.execCommand('insertHTML', false, html)
        this.renderMath()
        this.afterCommand(label)
    }
    P.insertText = function (t) {
        this.focusBody()
        this.restoreSel(this.lastSel)
        this.inCommand = true
        document.execCommand('insertText', false, t)
        this.afterCommand('插入')
    }
    P.selectNode = function (n) {
        const r = document.createRange()
        r.selectNode(n)
        getSelection().removeAllRanges()
        getSelection().addRange(r)
    }
    P.wrapInline = function (tag) {
        const s = getSelection()
        if (!s.rangeCount || s.isCollapsed) return
        const r = s.getRangeAt(0)
        const el = document.createElement(tag)
        el.append(r.extractContents())
        r.insertNode(el)
        this.afterCommand(tag === 'code' ? '行内代码' : '格式')
    }

    // ---------- 图片 ----------
    P.insertImage = async function (img) {
        this.saveSel()
        img ??= await pickImage()
        if (!img) return
        const maxW = this.pageEl.clientWidth - parseFloat(this.pageEl.style.paddingLeft) - parseFloat(this.pageEl.style.paddingRight)
        const w = Math.min(img.width, maxW)
        this.insertHTML(`<p style="text-align:center"><img src="${img.dataURL}" style="width:${Math.round(w)}px" alt="${escapeHTML(img.name ?? '')}"></p>`, '插入图片')
    }
    P.insertBlobImage = async function (blob) {
        const dataURL = await blobToDataURL(blob)
        const im = new Image()
        im.src = dataURL
        await im.decode()
        return this.insertImage({ dataURL, width: im.naturalWidth, height: im.naturalHeight })
    }
    P.onPaste = function (e) {
        const cd = e.clipboardData
        const file = [...cd.files].find(f => f.type.startsWith('image/'))
        if (file) { e.preventDefault(); this.saveSel(); return this.insertBlobImage(file) }
        const html = cd.getData('text/html')
        const text = cd.getData('text/plain')
        e.preventDefault()
        if (html) {
            this.insertHTML(sanitizePaste(html), '粘贴')
        } else if (text) {
            // 看起来像 Markdown 的文本按 Markdown 解析
            if (/^(#{1,6} |[-*] |\d+\. |> |```)/m.test(text) && text.includes('\n')) this.insertHTML(mdToHTML(text), '粘贴')
            else this.insertHTML(text.split(/\r?\n/).map((l, i, a) => a.length === 1 ? escapeHTML(l) : `<p>${escapeHTML(l) || '<br>'}</p>`).join(''), '粘贴')
        }
    }
    P.pasteFromClipboard = async function (plain) {
        this.focusBody()
        try {
            if (!plain) {
                const items = await navigator.clipboard.read()
                for (const it of items) {
                    const img = it.types.find(t => t.startsWith('image/'))
                    if (img) return this.insertBlobImage(await it.getType(img))
                    if (it.types.includes('text/html')) return this.insertHTML(sanitizePaste(await (await it.getType('text/html')).text()), '粘贴')
                }
            }
            const t = await navigator.clipboard.readText()
            if (t) this.insertText(t)
        } catch { toast('无法读取剪贴板') }
    }
    P.onDrop = function (e) {
        const files = [...e.dataTransfer.files].filter(f => f.type.startsWith('image/'))
        if (!files.length) return
        e.preventDefault()
        e.stopPropagation()
        const r = document.caretRangeFromPoint?.(e.clientX, e.clientY)
        if (r) { getSelection().removeAllRanges(); getSelection().addRange(r); this.saveSel() }
        files.reduce((p, f) => p.then(() => this.insertBlobImage(f)), Promise.resolve())
    }

    // 单击图片：选中并显示缩放手柄
    P.onBodyClick = function (e) {
        if (this.painter) setTimeout(() => this.applyPainter())
        const img = e.target.closest('img')
        this.body.querySelectorAll('img.selected').forEach(i => i !== img && i.classList.remove('selected'))
        this.imgHandle?.remove()
        if (img && this.body.contains(img)) {
            img.classList.add('selected')
            this.selectNode(img)
            this.showImageHandle(img)
        }
        const a = e.target.closest('a')
        if (a && (e.ctrlKey || e.metaKey)) {
            e.preventDefault()
            const href = a.getAttribute('href') ?? ''
            if (href.startsWith('#')) this.body.querySelector(CSS.escape(href) === href ? href : `[id="${href.slice(1)}"]`)?.scrollIntoView({ behavior: 'smooth' })
            else window.lite.openExternal(href)
        }
        const task = e.target.closest('li.task')
        if (task && e.offsetX < 0) { task.classList.toggle('done'); this.afterCommand('任务') }
    }
    P.showImageHandle = function (img) {
        const hd = h('div.doc-img-handle', { title: '拖动调整大小' })
        this.paper.append(hd)
        this.imgHandle = hd
        const place = () => {
            const pr = this.paper.getBoundingClientRect(), r = img.getBoundingClientRect(), z = this.zoom
            hd.style.left = (r.right - pr.left) / z - 7 + 'px'
            hd.style.top = (r.bottom - pr.top) / z - 7 + 'px'
        }
        place()
        hd.addEventListener('pointerdown', e => {
            e.preventDefault()
            hd.setPointerCapture(e.pointerId)
            const x0 = e.clientX, w0 = img.getBoundingClientRect().width / this.zoom
            const move = ev => { img.style.width = Math.max(20, Math.round(w0 + (ev.clientX - x0) / this.zoom)) + 'px'; img.style.height = ''; place() }
            const up = () => { hd.removeEventListener('pointermove', move); hd.removeEventListener('pointerup', up); this.afterCommand('调整图片大小'); place() }
            hd.addEventListener('pointermove', move)
            hd.addEventListener('pointerup', up)
        })
    }
    P.onBodyDbl = function (e) {
        const m = e.target.closest('.doc-math')
        if (m) return this.editMath(m)
        const img = e.target.closest('img')
        if (img) this.imageDialog(img)
    }
    P.imageItems = function (img) {
        const block = img.closest('p, div, figure') ?? img
        return [
            { label: '左对齐', run: () => { block.style.textAlign = 'left'; this.afterCommand('图片对齐') } },
            { label: '居中', run: () => { block.style.textAlign = 'center'; this.afterCommand('图片对齐') } },
            { label: '右对齐', run: () => { block.style.textAlign = 'right'; this.afterCommand('图片对齐') } },
            '-',
            ...[25, 50, 75, 100].map(p => ({ label: `宽度 ${p}%`, run: () => { img.style.width = p + '%'; this.afterCommand('图片大小') } })),
            { label: '原始大小', run: () => { img.style.width = img.naturalWidth + 'px'; this.afterCommand('图片大小') } },
            '-',
            { label: '添加题注…', run: () => this.imageCaption(img) },
            { label: '图片属性…', run: () => this.imageDialog(img) },
            { label: '删除图片', danger: true, run: () => { img.remove(); this.imgHandle?.remove(); this.afterCommand('删除图片') } },
        ]
    }
    P.imageDialog = async function (img) {
        const r = await formDialog({
            title: '图片属性', fields: [
                { key: 'w', label: '宽度', type: 'number', value: Math.round(img.getBoundingClientRect().width / this.zoom), min: 10, suffix: 'px' },
                { key: 'alt', label: '替代文字', value: img.alt ?? '' },
                { key: 'border', label: '边框', type: 'check', value: !!img.style.border },
                { key: 'radius', label: '圆角', type: 'number', value: parseFloat(img.style.borderRadius) || 0, min: 0, suffix: 'px' },
            ],
        })
        if (!r) return
        img.style.width = r.w + 'px'
        img.alt = r.alt
        img.style.border = r.border ? '1px solid #94a3b8' : ''
        img.style.borderRadius = r.radius ? r.radius + 'px' : ''
        this.afterCommand('图片属性')
    }
    P.imageCaption = async function (img) {
        const n = this.body.querySelectorAll('figure').length + 1
        const r = await formDialog({ title: '题注', fields: [{ key: 't', label: '题注', value: `图 ${n}  ` }] })
        if (!r) return
        const fig = h('figure')
        const block = img.parentElement !== this.body && img.parentElement.childNodes.length === 1 ? img.parentElement : img
        block.replaceWith(fig)
        fig.append(img, h('figcaption', r.t))
        this.afterCommand('题注')
    }

    // ---------- 表格 ----------
    P.insertTableDialog = async function () {
        this.saveSel()
        const r = await formDialog({
            title: '插入表格', fields: [
                { key: 'rows', label: '行数', type: 'number', value: 3, min: 1, max: 100 },
                { key: 'cols', label: '列数', type: 'number', value: 3, min: 1, max: 20 },
                { key: 'header', label: '标题行', type: 'check', value: true },
            ],
        })
        if (!r) return
        this.insertTable(r.rows, r.cols, r.header)
    }
    P.insertTable = function (rows, cols, header = true) {
        const tr = i => `<tr>${Array.from({ length: cols }, () => i === 0 && header ? '<th><br></th>' : '<td><br></td>').join('')}</tr>`
        this.insertHTML(`<table><tbody>${Array.from({ length: rows }, (_, i) => tr(i)).join('')}</tbody></table><p><br></p>`, '插入表格')
    }
    P.currentCell = function () {
        const s = getSelection()
        const n = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement)
        const c = n?.closest('td, th')
        return c && this.body.contains(c) ? c : null
    }
    P.moveCell = function (cell, d) {
        const cells = [...cell.closest('table').querySelectorAll('td, th')]
        let i = cells.indexOf(cell) + d
        if (i >= cells.length) { this.tableOp('rowBelow'); return this.moveCell(cell, d) }
        i = Math.max(0, i)
        const r = document.createRange()
        r.selectNodeContents(cells[i])
        getSelection().removeAllRanges()
        getSelection().addRange(r)
    }
    P.tableOp = function (op) {
        const cell = this.currentCell()
        if (!cell) return
        const tr = cell.parentElement, table = cell.closest('table')
        const ci = [...tr.children].indexOf(cell)
        const newCell = tag => { const c = document.createElement(tag); c.innerHTML = '<br>'; return c }
        switch (op) {
            case 'rowAbove': case 'rowBelow': {
                const nr = document.createElement('tr')
                for (const c of tr.children) nr.append(newCell('td'))
                op === 'rowAbove' ? tr.before(nr) : tr.after(nr)
                break
            }
            case 'colLeft': case 'colRight':
                for (const row of table.querySelectorAll('tr')) {
                    const ref = row.children[Math.min(ci, row.children.length - 1)]
                    const c = newCell(ref?.tagName === 'TH' ? 'th' : 'td')
                    op === 'colLeft' ? ref.before(c) : ref.after(c)
                }
                break
            case 'delRow': tr.remove(); if (!table.querySelector('tr')) table.remove(); break
            case 'delCol': for (const row of table.querySelectorAll('tr')) row.children[ci]?.remove(); if (!table.querySelector('td, th')) table.remove(); break
            case 'delTable': table.remove(); break
            case 'header': {
                const first = table.querySelector('tr')
                const on = ![...first.children].every(c => c.tagName === 'TH')
                for (const c of [...first.children]) { const n = newCell(on ? 'th' : 'td'); n.innerHTML = c.innerHTML; n.style.cssText = c.style.cssText; c.replaceWith(n) }
                break
            }
            case 'mergeRight': {
                const next = cell.nextElementSibling
                if (!next) return toast('右侧没有单元格')
                cell.innerHTML += ' ' + next.innerHTML
                cell.colSpan = (cell.colSpan || 1) + (next.colSpan || 1)
                next.remove()
                break
            }
            case 'mergeDown': {
                const rows = [...table.querySelectorAll('tr')]
                const below = rows[rows.indexOf(tr) + (cell.rowSpan || 1)]?.children[ci]
                if (!below) return toast('下方没有单元格')
                cell.innerHTML += '<br>' + below.innerHTML
                cell.rowSpan = (cell.rowSpan || 1) + (below.rowSpan || 1)
                below.remove()
                break
            }
            case 'split':
                if ((cell.colSpan || 1) > 1) { for (let i = 1; i < cell.colSpan; i++) cell.after(newCell(cell.tagName.toLowerCase())); cell.colSpan = 1 }
                else if ((cell.rowSpan || 1) > 1) cell.rowSpan = 1
                break
        }
        this.afterCommand('表格')
    }
    P.cellShade = function (color) {
        const c = this.currentCell()
        if (!c) return
        c.style.backgroundColor = color ?? ''
        this.afterCommand('单元格底纹')
    }
    P.tableBorders = function (style) {
        const t = this.currentCell()?.closest('table')
        if (!t) return
        t.dataset.border = style
        const css = { all: '1px solid #94a3b8', none: '0', thick: '2px solid #334155', dashed: '1px dashed #94a3b8' }[style]
        for (const c of t.querySelectorAll('td, th')) c.style.border = css
        this.afterCommand('表格边框')
    }
    P.tableItems = function () {
        const shade = ['#f1f5f9', '#dbeafe', '#dcfce7', '#fef9c3', '#fee2e2', '#f3e8ff']
        return [
            { label: '在上方插入行', run: () => this.tableOp('rowAbove') },
            { label: '在下方插入行', run: () => this.tableOp('rowBelow') },
            { label: '在左侧插入列', run: () => this.tableOp('colLeft') },
            { label: '在右侧插入列', run: () => this.tableOp('colRight') },
            '-',
            { label: '向右合并单元格', run: () => this.tableOp('mergeRight') },
            { label: '向下合并单元格', run: () => this.tableOp('mergeDown') },
            { label: '拆分单元格', run: () => this.tableOp('split') },
            { label: '标题行', run: () => this.tableOp('header') },
            '-',
            { label: '单元格底纹', submenu: [...shade.map(c => ({ label: c, swatch: c, run: () => this.cellShade(c) })), { label: '无', run: () => this.cellShade(null) }] },
            { label: '边框', submenu: [['all', '所有框线'], ['thick', '粗框线'], ['dashed', '虚线'], ['none', '无框线']].map(([k, l]) => ({ label: l, run: () => this.tableBorders(k) })) },
            '-',
            { label: '删除行', danger: true, run: () => this.tableOp('delRow') },
            { label: '删除列', danger: true, run: () => this.tableOp('delCol') },
            { label: '删除表格', danger: true, run: () => this.tableOp('delTable') },
        ]
    }

    // ---------- 公式 ----------
    P.insertMath = async function (block = false) {
        this.saveSel()
        const sel = getSelection().toString()
        const tex = await mathDialog(sel || (block ? '\\int_0^1 x^2\\,dx = \\frac{1}{3}' : 'a^2+b^2=c^2'), block)
        if (!tex) return
        const node = `<span class="doc-math${tex.block ? ' block' : ''}" data-tex="${escapeHTML(tex.tex)}" contenteditable="false"></span>`
        this.insertHTML(tex.block ? `<div class="doc-math-block">${node}</div><p><br></p>` : node + '&#8203;', '插入公式')
    }
    P.editMath = async function (m) {
        const r = await mathDialog(m.dataset.tex, m.classList.contains('block'))
        if (!r) return
        m.dataset.tex = r.tex
        delete m.dataset.orig
        m.classList.toggle('block', r.block)
        this.renderMath(m.parentElement)
        this.afterCommand('编辑公式')
    }

    // ---------- 链接 / 符号 ----------
    P.insertLink = async function (link) {
        this.saveSel()
        const text = link?.textContent ?? getSelection().toString()
        const r = await formDialog({
            title: link ? '编辑链接' : '插入链接', fields: [
                { key: 'text', label: '显示文字', value: text },
                { key: 'href', label: '地址', value: link?.getAttribute('href') ?? 'https://', placeholder: 'https://… 或 #标题' },
            ],
        })
        if (!r?.href) return
        if (link) { link.href = r.href; link.textContent = r.text || r.href; return this.afterCommand('编辑链接') }
        this.insertHTML(`<a href="${escapeHTML(r.href)}">${escapeHTML(r.text || r.href)}</a>`, '插入链接')
    }
    P.insertSymbol = async function () {
        this.saveSel()
        let chosen = null
        const body = h('div.doc-symbols', SYMBOLS.map(([name, chars]) => h('div',
            h('div.cmenu-header', name),
            h('div.doc-sym-grid', [...chars].map(ch => h('button.doc-sym', { title: `U+${ch.codePointAt(0).toString(16).toUpperCase()}`, onclick: () => { chosen = ch; this.insertText(ch) } }, ch))))))
        await dialog({ title: '特殊符号（单击插入）', body, width: 520, actions: [{ label: '完成', primary: true, value: true }] })
        void chosen
    }

    // ---------- 目录 / 脚注 / 分页 ----------
    P.tocHTML = function () {
        const hs = [...this.body.querySelectorAll('h1, h2, h3')].filter(x => !x.closest('.doc-toc') && x.textContent.trim())
        const items = hs.map(x => {
            x.id ||= 'h-' + uid()
            return `<a class="toc-item" href="#${x.id}" data-level="${x.tagName[1]}" style="padding-left:${(Number(x.tagName[1]) - 1) * 1.5}em">${escapeHTML(x.textContent.trim())}</a>`
        })
        return `<div class="toc-title">目录</div>${items.join('') || '<div>（文档中还没有标题）</div>'}`
    }
    P.insertTOC = function () {
        this.insertHTML(`<nav class="doc-toc" contenteditable="false">${this.tocHTML()}</nav><p><br></p>`, '插入目录')
        this.updateTOC()
    }
    P.updateTOC = function () {
        const tocs = this.body.querySelectorAll('.doc-toc')
        if (!tocs.length) return toast('文档中没有目录')
        for (const t of tocs) t.innerHTML = this.tocHTML()
        // 页码：根据标题在页面中的位置估算
        const [, hh] = this.paperSize()
        const top = this.pageEl.getBoundingClientRect().top
        for (const a of this.body.querySelectorAll('.toc-item')) {
            const target = this.body.querySelector(`[id="${a.getAttribute('href').slice(1)}"]`)
            if (!target) continue
            const page = Math.floor((target.getBoundingClientRect().top - top) / this.zoom / (hh * 96 / 25.4)) + 1
            a.append(h('span.toc-page', String(page)))
        }
        this.afterCommand('更新目录')
    }
    P.insertFootnote = function () {
        this.saveSel()
        let box = this.body.querySelector('.doc-footnotes')
        const n = (box?.querySelectorAll('li').length ?? 0) + 1
        const id = 'fn-' + uid()
        this.insertHTML(`<sup class="doc-footnote-ref" data-fn="${id}" contenteditable="false"><a href="#${id}">[${n}]</a></sup>`, '插入脚注')
        box = this.body.querySelector('.doc-footnotes')
        if (!box) { box = h('section.doc-footnotes', h('ol')); this.body.append(box) }
        const li = h('li', { id }, '脚注内容')
        box.querySelector('ol').append(li)
        const r = document.createRange()
        r.selectNodeContents(li)
        getSelection().removeAllRanges()
        getSelection().addRange(r)
        li.scrollIntoView({ block: 'center' })
        this.afterCommand('脚注')
    }
    P.insertPageBreak = function () {
        this.insertHTML('<div class="page-break" contenteditable="false"></div><p><br></p>', '分页符')
    }

    // ---------- 查找替换 ----------
    P.openFind = function (replace) {
        if (!this.findBar) {
            this.findInput = h('input.input.small', { placeholder: '查找', oninput: () => this.runFind() })
            this.replInput = h('input.input.small', { placeholder: '替换为' })
            this.findCase = h('input', { type: 'checkbox', onchange: () => this.runFind() })
            this.findWhole = h('input', { type: 'checkbox', onchange: () => this.runFind() })
            this.findRegex = h('input', { type: 'checkbox', onchange: () => this.runFind() })
            this.findCount = h('span.doc-find-count')
            this.findInput.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); this.findStep(e.shiftKey ? -1 : 1) } if (e.key === 'Escape') this.closeFind() })
            this.replInput.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); this.replaceOne() } if (e.key === 'Escape') this.closeFind() })
            this.replRow = h('div.doc-find-row', this.replInput,
                h('button.chip-btn', { onclick: () => this.replaceOne() }, '替换'),
                h('button.chip-btn', { onclick: () => this.replaceAll() }, '全部替换'))
            this.findBar = h('div.doc-findbar',
                h('div.doc-find-row', icon('search', 15), this.findInput, this.findCount,
                    this.tb('chevron-up', '上一个 (Shift Enter)', () => this.findStep(-1)),
                    this.tb('chevron-down', '下一个 (Enter)', () => this.findStep(1)),
                    this.tb('x', '关闭 (Esc)', () => this.closeFind())),
                this.replRow,
                h('div.doc-find-opts',
                    h('label', this.findCase, '区分大小写'), h('label', this.findWhole, '全字匹配'), h('label', this.findRegex, '正则表达式')))
            this.stage.append(this.findBar)
        }
        this.findBar.hidden = false
        this.replRow.hidden = !replace
        const sel = getSelection().toString()
        if (sel && !sel.includes('\n')) this.findInput.value = sel
        this.findInput.focus()
        this.findInput.select()
        this.runFind()
    }
    P.closeFind = function () {
        this.clearFindMarks()
        this.findBar.hidden = true
        this.body.focus()
    }
    P.clearFindMarks = function () {
        for (const m of this.body.querySelectorAll('mark.doc-find')) m.replaceWith(...m.childNodes)
        this.body.normalize()
        this.findHits = []
    }
    P.findRegexp = function () {
        const q = this.findInput.value
        if (!q) return null
        let src = this.findRegex.checked ? q : q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
        if (this.findWhole.checked) src = `(?<![\\p{L}\\p{N}_])${src}(?![\\p{L}\\p{N}_])`
        try { return new RegExp(src, 'gu' + (this.findCase.checked ? '' : 'i')) } catch { return null }
    }
    // 在文本节点中标记所有匹配（不跨节点）
    P.runFind = function () {
        this.clearFindMarks()
        const re = this.findRegexp()
        if (!re) { this.findCount.textContent = ''; return }
        const w = document.createTreeWalker(this.body, NodeFilter.SHOW_TEXT, { acceptNode: n => n.parentElement.closest('.doc-math, .doc-toc') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT })
        const nodes = []
        let n
        while ((n = w.nextNode())) nodes.push(n)
        const hits = []
        for (const node of nodes) {
            const text = node.textContent
            const ms = [...text.matchAll(re)].filter(m => m[0].length)
            if (!ms.length) continue
            let cur = node, offset = 0
            for (const m of ms) {
                const start = m.index - offset
                const hit = cur.splitText(start)
                const rest = hit.splitText(m[0].length)
                const mark = h('mark.doc-find')
                hit.replaceWith(mark)
                mark.append(hit)
                hits.push(mark)
                cur = rest
                offset = m.index + m[0].length
            }
        }
        this.findHits = hits
        this.findIdx = -1
        this.findCount.textContent = hits.length ? `${hits.length} 处` : '无结果'
        if (hits.length) this.findStep(1, true)
    }
    P.findStep = function (d, fromStart) {
        const hits = this.findHits ?? []
        if (!hits.length) return
        hits[this.findIdx]?.classList.remove('current')
        this.findIdx = fromStart ? 0 : (this.findIdx + d + hits.length) % hits.length
        const m = hits[this.findIdx]
        m.classList.add('current')
        m.scrollIntoView({ block: 'center', behavior: 'smooth' })
        this.findCount.textContent = `${this.findIdx + 1} / ${hits.length}`
    }
    P.replaceOne = function () {
        const m = this.findHits?.[this.findIdx]
        if (!m) return
        m.replaceWith(document.createTextNode(this.replacement(m.textContent)))
        this.commit('替换')
        const q = this.findIdx
        this.runFind()
        if (this.findHits.length) { this.findHits[this.findIdx]?.classList.remove('current'); this.findIdx = Math.min(q, this.findHits.length - 1) - 1; this.findStep(1) }
    }
    P.replacement = function (text) {
        const re = this.findRegexp()
        return this.findRegex.checked && re ? text.replace(new RegExp(re.source, re.flags.replace('g', '')), this.replInput.value) : this.replInput.value
    }
    P.replaceAll = function () {
        const hits = this.findHits ?? []
        if (!hits.length) return
        for (const m of hits) m.replaceWith(document.createTextNode(this.replacement(m.textContent)))
        this.body.normalize()
        this.findHits = []
        this.commit('全部替换')
        toast(`已替换 ${hits.length} 处`, 'success')
        this.runFind()
    }

    // ---------- 工具 ----------
    P.wordCount = function () {
        const t = this.body.innerText
        const cjk = (t.match(/[㐀-鿿豈-﫿]/g) ?? []).length
        const en = (t.replace(/[㐀-鿿豈-﫿]/g, ' ').match(/[A-Za-z0-9_'’-]+/g) ?? []).length
        const rows = [
            ['页数', this.pages], ['字数', cjk + en], ['中文字符', cjk], ['英文单词', en],
            ['字符数（不计空格）', t.replace(/\s/g, '').length], ['字符数（计空格）', t.replace(/\n/g, '').length],
            ['段落数', this.body.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li').length],
            ['图片', this.body.querySelectorAll('img').length], ['表格', this.body.querySelectorAll('table').length], ['公式', this.body.querySelectorAll('.doc-math').length],
        ]
        dialog({ title: '字数统计', body: h('table.doc-wc', rows.map(([k, v]) => h('tr', h('td', k), h('td', String(v))))), actions: [{ label: '关闭', primary: true, value: true }] })
    }
    P.normalizePunct = function () {
        const map = { ',': '，', ';': '；', ':': '：', '?': '？', '!': '！', '(': '（', ')': '）' }
        const w = document.createTreeWalker(this.body, NodeFilter.SHOW_TEXT)
        let n, count = 0
        while ((n = w.nextNode())) {
            if (n.parentElement.closest('pre, code, .doc-math, a')) continue
            const t = n.textContent.replace(/([一-鿿])([,;:?!])/g, (_, a, p) => { count++; return a + map[p] }).replace(/([一-鿿])\(([^)]*)\)/g, (_, a, x) => { count++; return `${a}（${x}）` })
            if (t !== n.textContent) n.textContent = t
        }
        this.afterCommand('标点规范化')
        toast(count ? `已修正 ${count} 处标点` : '没有需要修正的标点')
    }
    P.removeEmptyParas = function () {
        let n = 0
        for (const p of this.body.querySelectorAll('p')) if (!p.textContent.trim() && !p.querySelector('img, .doc-math, br + br') && p !== this.body.lastElementChild) { p.remove(); n++ }
        this.afterCommand('删除空段落')
        toast(`已删除 ${n} 个空段落`)
    }
}

// 公式对话框：实时预览 + 常用模板
async function mathDialog(tex, block) {
    const input = h('textarea.input.textarea.mono', { rows: 3, spellcheck: false })
    input.value = tex
    const prev = h('div.doc-math-prev')
    const err = h('div.form-note')
    const blockCb = h('input', { type: 'checkbox', checked: block })
    const draw = () => {
        try { prev.innerHTML = katex.renderToString(input.value, { displayMode: true, throwOnError: true }); err.textContent = '' }
        catch (e) { err.textContent = String(e.message).replace('KaTeX parse error: ', '语法错误：') }
    }
    input.addEventListener('input', draw)
    draw()
    return dialog({
        title: '公式（LaTeX）', width: 600,
        body: h('div.form', input,
            h('div.sl-btnrow', MATH_SAMPLES.map(([l, t]) => h('button.chip-btn', { onclick: () => { input.value = t; draw(); input.focus() } }, l))),
            prev, err,
            h('label.doc-inline-opt', blockCb, '独立成行（行间公式）')),
        actions: [{ label: '取消', value: null }, { label: '确定', primary: true, value: () => input.value.trim() ? { tex: input.value.trim(), block: blockCb.checked } : null }],
    })
}

// 清理粘贴的 HTML：去掉脚本、样式表、Office 专有标记，保留基本格式
function sanitizePaste(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html')
    doc.querySelectorAll('script, style, meta, link, title, xml, o\\:p').forEach(n => n.remove())
    for (const el of doc.body.querySelectorAll('*')) {
        for (const a of [...el.attributes]) {
            if (/^on/i.test(a.name) || ['class', 'id', 'lang', 'data-start', 'data-end'].includes(a.name) || a.name.startsWith('xmlns')) el.removeAttribute(a.name)
        }
        if (el.style) {
            const keep = {}
            for (const k of ['color', 'backgroundColor', 'fontWeight', 'fontStyle', 'textDecoration', 'textAlign', 'fontSize']) if (el.style[k]) keep[k] = el.style[k]
            el.removeAttribute('style')
            Object.assign(el.style, keep)
            if (keep.color === 'rgb(0, 0, 0)' || keep.color === 'black') el.style.color = ''
        }
    }
    return doc.body.innerHTML.replace(/<!--[\s\S]*?-->/g, '')
}
