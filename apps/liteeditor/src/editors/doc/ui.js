// 文字处理器：工具栏、菜单、格式命令、快捷键
import { h, toast, colorInput, select, numberInput, formDialog } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu, keyString } from '../../core/menu.js'
import { PAPERS } from './index.js'
import { fontSelect, fontOptions } from '../../core/fonts.js'

const FONTS = [
    ['"SimSun", "Songti SC", serif', '宋体'], ['"Microsoft YaHei", sans-serif', '微软雅黑'], ['"SimHei", sans-serif', '黑体'],
    ['"KaiTi", "STKaiti", serif', '楷体'], ['"FangSong", "STFangsong", serif', '仿宋'], ['"DengXian", sans-serif', '等线'],
    ['"Times New Roman", serif', 'Times New Roman'], ['Arial, sans-serif', 'Arial'], ['Calibri, sans-serif', 'Calibri'], ['Georgia, serif', 'Georgia'], ['Consolas, monospace', 'Consolas'],
]
// 中文字号 → px
const SIZES = [['初号', 56], ['小初', 48], ['一号', 34.7], ['小一', 32], ['二号', 29.3], ['小二', 24], ['三号', 21.3], ['小三', 20], ['四号', 18.7], ['小四', 16], ['五号', 14], ['小五', 12], ['8', 10.7], ['9', 12], ['10', 13.3], ['11', 14.7], ['12', 16], ['14', 18.7], ['16', 21.3], ['18', 24], ['20', 26.7], ['24', 32], ['28', 37.3], ['36', 48], ['48', 64], ['72', 96]]
const BLOCKS = [['p', '正文'], ['h1', '标题 1'], ['h2', '标题 2'], ['h3', '标题 3'], ['h4', '标题 4'], ['blockquote', '引用'], ['pre', '代码块']]
const HILITE = ['#fef08a', '#bbf7d0', '#bfdbfe', '#fbcfe8', '#fed7aa', '#e5e7eb']

export function installUI(Ed) {
    const P = Ed.prototype

    P.buildToolbar = function () {
        const tb = (ic, title, fn) => { const b = this.tb(ic, title, fn); b.addEventListener('mousedown', e => e.preventDefault()); return b }
        this.tbGroup(tb('undo-2', '撤销 (Ctrl Z)', () => this.undo()), tb('redo-2', '重做 (Ctrl Y)', () => this.redo()),
            this.painterBtn = tb('paintbrush', '格式刷（双击连续使用）', () => this.startPainter()))
        this.painterBtn.addEventListener('dblclick', () => this.startPainter(true))
        this.blockSel = select(BLOCKS, 'p', v => this.setBlock(v), { title: '段落样式', width: 88 })
        this.fontSel = fontSelect(FONTS, FONTS[0][0], v => this.exec('fontName', v), { title: '字体', width: 104 })
        this.sizeSel = select(SIZES.map(([l, px]) => [String(px), l]), '16', v => this.setFontSize(Number(v)), { title: '字号', width: 64 })
        for (const s of [this.blockSel, this.fontSel, this.sizeSel]) s.el.addEventListener('mousedown', () => this.saveSel())
        this.tbGroup(this.blockSel.el, this.fontSel.el, this.sizeSel.el,
            tb('a-arrow-up', '增大字号 (Ctrl ])', () => this.bumpFont(1)), tb('a-arrow-down', '减小字号 (Ctrl [)', () => this.bumpFont(-1)))
        this.fmtBtns = {
            bold: tb('bold', '加粗 (Ctrl B)', () => this.exec('bold')),
            italic: tb('italic', '倾斜 (Ctrl I)', () => this.exec('italic')),
            underline: tb('underline', '下划线 (Ctrl U)', () => this.exec('underline')),
            strikeThrough: tb('strikethrough', '删除线', () => this.exec('strikeThrough')),
            superscript: tb('superscript', '上标 (Ctrl Shift =)', () => this.exec('superscript')),
            subscript: tb('subscript', '下标 (Ctrl =)', () => this.exec('subscript')),
        }
        this.colorCtl = colorInput('#dc2626', v => { this.restoreSel(this.lastSel); this.exec('foreColor', v) }, { title: '文字颜色' })
        this.colorCtl.el.addEventListener('mousedown', () => this.saveSel())
        const hl = this.dd(icon('highlighter', 17), () => [
            ...HILITE.map(c => ({ label: c, swatch: c, run: () => { this.restoreSel(this.lastSel); this.exec('hiliteColor', c) } })),
            '-', { label: '无颜色', run: () => { this.restoreSel(this.lastSel); this.exec('hiliteColor', 'transparent') } },
        ], { title: '突出显示' })
        hl.addEventListener('mousedown', () => this.saveSel())
        this.tbGroup(...Object.values(this.fmtBtns), this.colorCtl.el, hl, tb('remove-formatting', '清除格式', () => this.clearFormat()))
        this.alignBtns = {
            left: tb('align-left', '左对齐 (Ctrl L)', () => this.align('left')),
            center: tb('align-center', '居中 (Ctrl E)', () => this.align('center')),
            right: tb('align-right', '右对齐 (Ctrl R)', () => this.align('right')),
            justify: tb('align-justify', '两端对齐 (Ctrl J)', () => this.align('justify')),
        }
        const lh = this.dd(icon('list-collapse', 17), () => [1, 1.15, 1.5, 1.75, 2, 2.5, 3].map(v => ({ label: `${v} 倍行距`, run: () => this.setParaStyle({ lineHeight: String(v) }, '行距') })), { title: '行距' })
        lh.addEventListener('mousedown', () => this.saveSel())
        this.tbGroup(...Object.values(this.alignBtns),
            tb('list', '项目符号', () => this.exec('insertUnorderedList')),
            tb('list-ordered', '编号', () => this.exec('insertOrderedList')),
            tb('list-checks', '任务列表', () => this.toggleTaskList()),
            tb('outdent', '减少缩进', () => this.indent(-1)), tb('indent', '增加缩进', () => this.indent(1)), lh)
        const ins = (ic, t, fn) => { const b = tb(ic, t, fn); b.addEventListener('mousedown', () => this.saveSel()); return b }
        this.tbGroup(
            ins('image-plus', '插入图片', () => this.insertImage()),
            ins('table', '插入表格', () => this.insertTableDialog()),
            ins('sigma', '插入公式 (Ctrl M)', () => this.insertMath()),
            ins('link', '插入链接 (Ctrl K)', () => this.insertLink()),
            ins('omega', '特殊符号', () => this.insertSymbol()))
        this.tbGroup(
            ins('search', '查找 (Ctrl F)', () => this.openFind(false)),
            ins('replace', '替换 (Ctrl H)', () => this.openFind(true)),
            h('button.tb-text-btn', { onclick: () => this.toggleSource(), title: '源码视图：Markdown / HTML / LaTeX 与可视化编辑并排' }, icon('code', 15), '源码'))
    }

    // ---------- 命令 ----------
    P.focusBody = function () {
        if (!this.hasSel()) { this.body.focus({ preventScroll: true }); this.restoreSel(this.lastSel) }
    }
    P.exec = function (cmd, value) {
        this.focusBody()
        this.inCommand = true
        document.execCommand('styleWithCSS', false, !['bold', 'italic', 'underline', 'strikeThrough', 'superscript', 'subscript', 'insertUnorderedList', 'insertOrderedList'].includes(cmd))
        document.execCommand(cmd, false, value)
        this.inCommand = false
        this.afterCommand(CMD_LABEL[cmd] ?? '格式')
    }
    P.afterCommand = function (label) {
        this.inCommand = false
        this.lastMerge = null
        this.normalize()
        this.commit(label)
        this.saveSel()
        this.updateFormatUI()
        this.refreshOutline()
        this.layoutPages()
        if (this.sourceMode) this.syncSourceSoon()
    }

    // 当前选区所在的块级元素
    P.blocksInSel = function () {
        const s = getSelection()
        if (!s.rangeCount || !this.body.contains(s.anchorNode)) return []
        const r = s.getRangeAt(0)
        const blockOf = n => { while (n && n !== this.body) { if (n.nodeType === 1 && /^(P|H[1-6]|LI|BLOCKQUOTE|PRE|DIV|TD|TH|FIGURE)$/.test(n.tagName)) return n; n = n.parentNode } return null }
        const a = blockOf(r.startContainer), b = blockOf(r.endContainer)
        if (!a) return []
        if (a === b) return [a]
        const out = []
        const w = document.createTreeWalker(this.body, NodeFilter.SHOW_ELEMENT)
        let n, on = false
        while ((n = w.nextNode())) {
            if (n === a) on = true
            if (on && /^(P|H[1-6]|LI|BLOCKQUOTE|PRE)$/.test(n.tagName) && !out.some(x => x.contains(n))) out.push(n)
            if (n === b) break
        }
        return out
    }

    P.setBlock = function (tag) {
        this.focusBody()
        this.restoreSel(this.lastSel)
        this.inCommand = true
        document.execCommand('formatBlock', false, tag)
        this.afterCommand('段落样式')
    }
    P.align = function (a) {
        const bs = this.blocksInSel()
        if (!bs.length) return
        for (const b of bs) {
            const img = b.querySelector(':scope > img:only-child')
            b.style.textAlign = a === 'left' ? '' : a
            if (img) img.style.display = ''
        }
        this.afterCommand('对齐')
    }
    P.setParaStyle = function (st, label) {
        this.restoreSel(this.lastSel)
        const bs = this.blocksInSel()
        if (!bs.length) return
        for (const b of bs) Object.assign(b.style, st)
        this.afterCommand(label)
    }
    P.indent = function (d) {
        const s = getSelection()
        const inList = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement)?.closest('li')
        if (inList) return this.exec(d > 0 ? 'indent' : 'outdent')
        for (const b of this.blocksInSel()) {
            const cur = parseFloat(b.style.marginLeft) || 0
            const next = Math.max(0, cur + d * 32)
            b.style.marginLeft = next ? next + 'px' : ''
        }
        this.afterCommand('缩进')
    }
    P.firstLineIndent = function () {
        const bs = this.blocksInSel()
        const on = !bs.every(b => b.style.textIndent)
        for (const b of bs) b.style.textIndent = on ? '2em' : ''
        this.afterCommand('首行缩进')
    }

    // 字号：用 span 包裹选区
    P.setFontSize = function (px) {
        this.focusBody()
        this.restoreSel(this.lastSel)
        const s = getSelection()
        if (!s.rangeCount) return
        if (s.isCollapsed) {
            // 光标处：设置所在段落
            for (const b of this.blocksInSel()) b.style.fontSize = px + 'px'
            return this.afterCommand('字号')
        }
        document.execCommand('styleWithCSS', false, false)
        document.execCommand('fontSize', false, '7')
        for (const f of this.body.querySelectorAll('font[size="7"]')) {
            const span = h('span', { style: { fontSize: px + 'px' } })
            span.append(...f.childNodes)
            for (const inner of span.querySelectorAll('[style*="font-size"]')) inner.style.fontSize = ''
            f.replaceWith(span)
        }
        this.afterCommand('字号')
    }
    P.bumpFont = function (d) {
        const cur = this.currentFontPx()
        const list = [...new Set(SIZES.map(s => s[1]))].sort((a, b) => a - b)
        const next = d > 0 ? list.find(x => x > cur + 0.1) ?? cur + 4 : [...list].reverse().find(x => x < cur - 0.1) ?? Math.max(8, cur - 2)
        this.setFontSize(next)
    }
    P.currentFontPx = function () {
        const s = getSelection()
        const n = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement)
        return n && this.body.contains(n) ? parseFloat(getComputedStyle(n).fontSize) : this.page.fontSize
    }

    P.clearFormat = function () {
        this.focusBody()
        document.execCommand('removeFormat')
        for (const b of this.blocksInSel()) { b.removeAttribute('style'); if (/^H\d|BLOCKQUOTE|PRE$/.test(b.tagName)) { const p = h('p'); p.append(...b.childNodes); b.replaceWith(p) } }
        this.afterCommand('清除格式')
    }

    P.toggleTaskList = function () {
        this.focusBody()
        let li = getSelection().anchorNode
        li = li && (li.nodeType === 1 ? li : li.parentElement)?.closest('li')
        if (!li || !this.body.contains(li)) { document.execCommand('insertUnorderedList'); li = getSelection().anchorNode; li = li && (li.nodeType === 1 ? li : li.parentElement)?.closest('li') }
        const list = li?.parentElement
        if (!list) return
        const on = ![...list.children].every(x => x.classList.contains('task'))
        for (const x of list.children) x.classList.toggle('task', on)
        this.afterCommand('任务列表')
    }

    // 格式刷：记录当前位置的行内样式，应用到下一次选区
    P.startPainter = function (sticky = false) {
        const s = getSelection()
        const n = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement)
        if (!n || !this.body.contains(n)) return toast('请先把光标放在要复制格式的文字中')
        const cs = getComputedStyle(n)
        this.painter = { sticky, st: { fontWeight: cs.fontWeight, fontStyle: cs.fontStyle, textDecoration: cs.textDecorationLine, color: cs.color, backgroundColor: cs.backgroundColor, fontSize: cs.fontSize, fontFamily: cs.fontFamily } }
        this.painterBtn.classList.add('active')
        this.body.classList.add('painting')
        toast(sticky ? '格式刷：选择文字以应用格式，按 Esc 结束' : '格式刷：选择要应用格式的文字')
    }
    P.applyPainter = function () {
        const s = getSelection()
        if (!this.painter || s.isCollapsed || !this.hasSel()) return
        const r = s.getRangeAt(0)
        const span = h('span')
        Object.assign(span.style, this.painter.st)
        if (this.painter.st.textDecoration === 'none') span.style.textDecoration = 'none'
        span.append(r.extractContents())
        r.insertNode(span)
        if (!this.painter.sticky) this.stopPainter()
        this.afterCommand('格式刷')
    }
    P.stopPainter = function () {
        this.painter = null
        this.painterBtn.classList.remove('active')
        this.body.classList.remove('painting')
    }

    P.updateFormatUI = function () {
        if (!this.fmtBtns) return
        const s = getSelection()
        const inBody = s.rangeCount && this.body.contains(s.anchorNode)
        if (!inBody) return
        for (const [cmd, b] of Object.entries(this.fmtBtns)) {
            let on = false
            try { on = document.queryCommandState(cmd) } catch { /* ignore */ }
            b.classList.toggle('active', on)
        }
        const n = s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement
        const block = n.closest('h1, h2, h3, h4, blockquote, pre, p, li')
        const tag = block?.tagName.toLowerCase()
        this.blockSel.set(BLOCKS.some(b => b[0] === tag) ? tag : 'p')
        const cs = getComputedStyle(n)
        const px = parseFloat(cs.fontSize)
        const best = SIZES.reduce((a, b) => Math.abs(b[1] - px) < Math.abs(a[1] - px) ? b : a)
        this.sizeSel.set(String(best[1]))
        this.fontSel.set(cs.fontFamily)
        const al = block ? getComputedStyle(block).textAlign : 'left'
        for (const [k, b] of Object.entries(this.alignBtns)) b.classList.toggle('active', (al === 'start' ? 'left' : al) === k)
        this.updateStatus()
    }

    // ---------- 页面设置 ----------
    P.pageSetup = async function () {
        const p = this.page
        const r = await formDialog({
            title: '页面设置', width: 440,
            fields: [
                { key: 'paper', label: '纸张', type: 'select', value: p.paper, options: Object.keys(PAPERS).map(k => [k, `${k}（${PAPERS[k][0]} × ${PAPERS[k][1]} mm）`]) },
                { key: 'landscape', label: '横向', type: 'check', value: p.landscape },
                { key: 'top', label: '上边距', type: 'number', value: p.margin.top, min: 0, max: 80, suffix: 'mm' },
                { key: 'bottom', label: '下边距', type: 'number', value: p.margin.bottom, min: 0, max: 80, suffix: 'mm' },
                { key: 'left', label: '左边距', type: 'number', value: p.margin.left, min: 0, max: 80, suffix: 'mm' },
                { key: 'right', label: '右边距', type: 'number', value: p.margin.right, min: 0, max: 80, suffix: 'mm' },
                { key: 'font', label: '正文字体', type: 'select', value: p.font, options: fontOptions(FONTS, { importItem: false, current: p.font }) },
                { key: 'fontSize', label: '正文字号', type: 'select', value: String(p.fontSize), options: SIZES.map(([l, px]) => [String(px), l]) },
                { key: 'lineHeight', label: '行距', type: 'select', value: String(p.lineHeight), options: ['1', '1.15', '1.5', '1.75', '2', '2.5'].map(v => [v, v + ' 倍']) },
                { key: 'header', label: '页眉', value: p.header ?? '', placeholder: '可选' },
                { key: 'pageNumbers', label: '页码', type: 'check', value: p.pageNumbers },
            ],
        })
        if (!r) return
        this.page = {
            ...p, paper: r.paper, landscape: r.landscape, font: r.font, fontSize: Number(r.fontSize), lineHeight: Number(r.lineHeight),
            header: r.header, pageNumbers: r.pageNumbers, margin: { top: r.top, bottom: r.bottom, left: r.left, right: r.right },
        }
        this.applyPage()
        this.commit('页面设置')
    }

    // ---------- 键盘 ----------
    P.onKey = function (e) {
        const k = keyString(e)
        if (k === 'Escape' && this.painter) { this.stopPainter(); return true }
        if (this.findBar && !this.findBar.hidden && k === 'Escape') { this.closeFind(); return true }
        if (e.target === this.source) {
            if (k === 'Ctrl+Z' || k === 'Ctrl+Y' || k === 'Ctrl+Shift+Z') return false
            if (k === 'Tab') { e.preventDefault(); document.execCommand('insertText', false, '    '); return true }
        }
        return false
    }

    // 正文内的特殊按键
    P.onBodyKey = function (e) {
        const k = keyString(e)
        if (k === 'Tab' || k === 'Shift+Tab') {
            const cell = (getSelection().anchorNode?.nodeType === 1 ? getSelection().anchorNode : getSelection().anchorNode?.parentElement)?.closest('td, th')
            e.preventDefault()
            if (cell) return this.moveCell(cell, k === 'Tab' ? 1 : -1)
            const li = getSelection().anchorNode?.parentElement?.closest('li')
            if (li) return this.exec(k === 'Tab' ? 'indent' : 'outdent')
            document.execCommand('insertText', false, '　　')
            return
        }
        // 在标题末尾回车，下一段恢复为正文
        if (k === 'Enter') {
            const s = getSelection()
            const n = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement
            const hd = n?.closest('h1, h2, h3, h4, h5, h6')
            if (hd && s.isCollapsed) {
                const r = document.createRange()
                r.selectNodeContents(hd)
                r.setStart(s.anchorNode, s.anchorOffset)
                if (!r.toString()) {
                    e.preventDefault()
                    const p = h('p', h('br'))
                    hd.after(p)
                    const rr = document.createRange(); rr.setStart(p, 0)
                    s.removeAllRanges(); s.addRange(rr)
                    this.afterCommand('换行')
                }
            }
            // 代码块中回车：插入换行而不是新段落
            if (n?.closest('pre') && !e.shiftKey) { e.preventDefault(); document.execCommand('insertText', false, '\n') }
        }
    }

    // Markdown 风格快捷输入（在输入空格后检查）：行首 “# ” → 标题，“- ” → 列表，“1. ” → 编号，“> ” → 引用，“[] ” → 任务
    P.markdownShortcut = function () {
        const s = getSelection()
        const n = s.anchorNode
        if (n?.nodeType !== 3 || !s.isCollapsed) return false
        const block = n.parentElement.closest('p, div')
        if (!block || block === this.body || block.firstChild !== n || block.closest('li, td, th, pre')) return false
        const before = n.textContent.slice(0, s.anchorOffset)
        const m = /^(#{1,4}|>|[-*+]|1[.)]|\[\])[  ]$/.exec(before)
        if (!m) return false
        const mark = m[1]
        const rest = n.textContent.slice(s.anchorOffset)
        const heads = { '#': 'h1', '##': 'h2', '###': 'h3', '####': 'h4', '>': 'blockquote' }
        // 直接替换块元素（段落为空时 formatBlock 会与上一段合并）
        let target
        if (heads[mark]) {
            target = document.createElement(heads[mark])
            n.textContent = rest
            target.append(...block.childNodes)
            block.replaceWith(target)
        } else {
            const list = document.createElement(/^1/.test(mark) ? 'ol' : 'ul')
            target = document.createElement('li')
            if (mark === '[]') target.className = 'task'
            n.textContent = rest
            target.append(...block.childNodes)
            list.append(target)
            block.replaceWith(list)
        }
        if (!target.textContent) target.innerHTML = '<br>'
        const r = document.createRange()
        const first = target.firstChild
        if (first?.nodeType === 3) r.setStart(first, 0); else r.setStart(target, 0)
        s.removeAllRanges(); s.addRange(r)
        this.afterCommand('自动格式')
        return true
    }

    // ---------- 菜单 ----------
    P.menus = function () {
        const insideTable = () => !!this.currentCell()
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => { this.focusBody(); document.execCommand('cut') } },
                    { label: '复制', icon: 'copy', key: 'Ctrl+C', run: () => { this.focusBody(); document.execCommand('copy') } },
                    { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.pasteFromClipboard(false) },
                    { label: '粘贴为纯文本', key: 'Ctrl+Shift+V', run: () => this.pasteFromClipboard(true) },
                    { label: '全选', key: 'Ctrl+A', run: () => { this.body.focus(); document.execCommand('selectAll') } },
                    '-',
                    { label: '查找…', icon: 'search', key: 'Ctrl+F', run: () => this.openFind(false) },
                    { label: '替换…', icon: 'replace', key: 'Ctrl+H', run: () => this.openFind(true) },
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '源码视图', icon: 'code', key: 'Ctrl+/', checked: () => !!this.sourceMode, run: () => this.toggleSource() },
                    {
                        label: '源码格式', submenu: [['md', 'Markdown'], ['html', 'HTML'], ['tex', 'LaTeX']].map(([k, l]) => ({
                            label: l, checked: () => (this.srcKindOverride ?? this.sourceKind()) === k,
                            run: async () => { this.srcKindOverride = k; if (!this.sourceMode) await this.toggleSource(); else await this.syncSource() },
                        })),
                    },
                    '-',
                    { label: '放大', icon: 'zoom-in', run: () => this.setZoom(this.zoom + 0.1) },
                    { label: '缩小', icon: 'zoom-out', run: () => this.setZoom(this.zoom - 0.1) },
                    { label: '100%', run: () => this.setZoom(1) },
                    '-',
                    { label: '显示导航面板', checked: () => !this.panels.classList.contains('hidden'), key: 'Ctrl+\\', run: () => this.panels.classList.toggle('hidden') },
                ],
            },
            {
                label: '插入', items: () => [
                    { label: '图片…', icon: 'image-plus', run: () => this.insertImage() },
                    { label: '表格…', icon: 'table', run: () => this.insertTableDialog() },
                    { label: '公式…', icon: 'sigma', key: 'Ctrl+M', run: () => this.insertMath() },
                    { label: '行间公式…', icon: 'square-sigma', key: 'Ctrl+Shift+M', run: () => this.insertMath(true) },
                    { label: '超链接…', icon: 'link', key: 'Ctrl+K', run: () => this.insertLink() },
                    '-',
                    { label: '目录', icon: 'list-tree', run: () => this.insertTOC() },
                    { label: '脚注', icon: 'superscript', key: 'Ctrl+Alt+F', run: () => this.insertFootnote() },
                    { label: '分页符', icon: 'separator-horizontal', key: 'Ctrl+Enter', run: () => this.insertPageBreak() },
                    { label: '分隔线', icon: 'minus', run: () => this.insertHTML('<hr><p><br></p>', '分隔线') },
                    { label: '代码块', icon: 'code', run: () => this.setBlock('pre') },
                    '-',
                    { label: '特殊符号…', icon: 'omega', run: () => this.insertSymbol() },
                    { label: '日期和时间', icon: 'calendar', submenu: () => dateItems(this) },
                ],
            },
            {
                label: '格式', items: () => [
                    { label: '加粗', icon: 'bold', key: 'Ctrl+B', run: () => this.exec('bold') },
                    { label: '倾斜', icon: 'italic', key: 'Ctrl+I', run: () => this.exec('italic') },
                    { label: '下划线', icon: 'underline', key: 'Ctrl+U', run: () => this.exec('underline') },
                    { label: '删除线', icon: 'strikethrough', key: 'Alt+Shift+5', run: () => this.exec('strikeThrough') },
                    { label: '上标', icon: 'superscript', key: 'Ctrl+Shift+=', run: () => this.exec('superscript') },
                    { label: '下标', icon: 'subscript', key: 'Ctrl+=', run: () => this.exec('subscript') },
                    { label: '行内代码', icon: 'code', key: 'Ctrl+`', run: () => this.wrapInline('code') },
                    { label: '清除格式', icon: 'remove-formatting', key: 'Ctrl+Space', run: () => this.clearFormat() },
                    '-',
                    { label: '段落样式', submenu: BLOCKS.map(([t, l], i) => ({ label: l, key: i < 5 ? `Ctrl+Alt+${i}` : undefined, run: () => this.setBlock(t) })) },
                    { label: '对齐', submenu: [['left', '左对齐', 'Ctrl+L'], ['center', '居中', 'Ctrl+E'], ['right', '右对齐', 'Ctrl+R'], ['justify', '两端对齐', 'Ctrl+J']].map(([v, l, k]) => ({ label: l, key: k, run: () => this.align(v) })) },
                    { label: '行距', submenu: [1, 1.15, 1.5, 1.75, 2, 2.5].map(v => ({ label: v + ' 倍', run: () => this.setParaStyle({ lineHeight: String(v) }, '行距') })) },
                    { label: '段前 / 段后间距', submenu: [0, 6, 12, 18, 24].map(v => ({ label: v + ' px', run: () => this.setParaStyle({ marginTop: v + 'px', marginBottom: v + 'px' }, '段间距') })) },
                    { label: '首行缩进 2 字符', run: () => this.firstLineIndent() },
                    '-',
                    { label: '格式刷', icon: 'paintbrush', key: 'Ctrl+Shift+C', run: () => this.startPainter() },
                    { label: '页面设置…', icon: 'file-cog', run: () => this.pageSetup() },
                ],
            },
            {
                label: '表格', items: () => [
                    { label: '插入表格…', icon: 'table', run: () => this.insertTableDialog() },
                    '-',
                    ...this.tableItems().map(it => it === '-' ? it : { ...it, disabled: () => !insideTable() }),
                ],
            },
            {
                label: '工具', items: () => [
                    { label: '字数统计…', icon: 'hash', run: () => this.wordCount() },
                    { label: '更新目录', icon: 'refresh-cw', run: () => this.updateTOC() },
                    { label: '拼写检查', checked: () => this.body.spellcheck, run: () => { this.body.spellcheck = !this.body.spellcheck } },
                    '-',
                    { label: '中文标点规范化', run: () => this.normalizePunct() },
                    { label: '删除空段落', run: () => this.removeEmptyParas() },
                ],
            },
        ]
    }

    P.onBodyContext = function (e) {
        const img = e.target.closest('img')
        const math = e.target.closest('.doc-math')
        const link = e.target.closest('a')
        const cell = e.target.closest('td, th')
        if (img || math) { e.preventDefault(); this.selectNode(img ?? math) }
        const items = [
            { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => document.execCommand('cut') },
            { label: '复制', icon: 'copy', key: 'Ctrl+C', run: () => document.execCommand('copy') },
            { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.pasteFromClipboard(false) },
            { label: '粘贴为纯文本', run: () => this.pasteFromClipboard(true) },
            '-',
            img ? { label: '图片', icon: 'image', submenu: () => this.imageItems(img) } : null,
            math ? { label: '编辑公式…', icon: 'sigma', run: () => this.editMath(math) } : null,
            link ? { label: '编辑链接…', icon: 'link', run: () => this.insertLink(link) } : null,
            link ? { label: '移除链接', icon: 'unlink', run: () => { link.replaceWith(...link.childNodes); this.afterCommand('移除链接') } } : null,
            cell ? { label: '表格', icon: 'table', submenu: () => this.tableItems() } : null,
            '-',
            { label: '段落样式', submenu: BLOCKS.map(([t, l]) => ({ label: l, run: () => this.setBlock(t) })) },
            { label: '清除格式', icon: 'remove-formatting', run: () => this.clearFormat() },
        ]
        contextMenu(e, items)
    }
}

const CMD_LABEL = {
    bold: '加粗', italic: '倾斜', underline: '下划线', strikeThrough: '删除线', superscript: '上标', subscript: '下标',
    foreColor: '文字颜色', hiliteColor: '突出显示', fontName: '字体', insertUnorderedList: '项目符号', insertOrderedList: '编号',
    indent: '缩进', outdent: '缩进', removeFormat: '清除格式', formatBlock: '段落样式', insertHTML: '插入', insertText: '输入',
}

function dateItems(ed) {
    const d = new Date()
    const p = n => String(n).padStart(2, '0')
    const week = '日一二三四五六'[d.getDay()]
    return [
        `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`,
        `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 星期${week}`,
        `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`,
        `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`,
        `${p(d.getHours())}:${p(d.getMinutes())}`,
        `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`,
    ].map(t => ({ label: t, run: () => ed.insertText(t) }))
}

export { FONTS, SIZES, numberInput }
