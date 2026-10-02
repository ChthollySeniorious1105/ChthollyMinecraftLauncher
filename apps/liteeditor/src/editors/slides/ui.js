// 演示文稿：工具栏、菜单、快捷键、格式命令
import { h, fill, toast, colorInput, select, numberInput, formDialog } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu, openMenu } from '../../core/menu.js'
import { pickImage, blobToDataURL, loadImage } from '../../core/files.js'
import { SHAPES, LAYOUTS, THEMES, TRANSITIONS, ANIMS, sizeOf, themeOf, newId, clone, applyThemeToDeck, defaultChart } from './model.js'
import { unionBox } from './interact.js'
import { buildPanels, refreshPanels } from './panels.js'
import { fontSelect } from '../../core/fonts.js'
import { editChart, editMath, editTable, pickIcon } from './dialogs.js'

const FONTS = [
    ['"Microsoft YaHei", "PingFang SC", sans-serif', '微软雅黑'], ['"SimSun", "Songti SC", serif', '宋体'], ['"KaiTi", "STKaiti", serif', '楷体'],
    ['"SimHei", sans-serif', '黑体'], ['"FangSong", "STFangsong", serif', '仿宋'], ['"DengXian", sans-serif', '等线'],
    ['"Segoe UI", Arial, sans-serif', 'Segoe UI'], ['Georgia, serif', 'Georgia'], ['"Times New Roman", serif', 'Times New Roman'], ['Consolas, monospace', 'Consolas'],
]
const SIZES_PX = [16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 88, 96, 120, 144]

export function installUI(Ed) {
    const P = Ed.prototype

    P.buildToolbar = function () {
        const tb = (ic, title, fn) => this.tb(ic, title, fn)
        this.tbGroup(
            this.dd(h('span.tb-new', icon('plus', 15), '新建幻灯片'), () => Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, run: () => this.addSlide(k) })), { title: '新建幻灯片' }),
            tb('undo-2', '撤销 (Ctrl Z)', () => this.undo()),
            tb('redo-2', '重做 (Ctrl Y)', () => this.redo()))
        // 插入
        this.insertBtns = {
            text: tb('type', '文本框（拖动绘制）', () => this.toggleInsert({ type: 'text' })),
        }
        this.tbGroup(
            this.insertBtns.text,
            this.dd(icon('shapes', 17), () => this.shapeMenu(), { title: '形状' }),
            tb('image-plus', '图片', () => this.insertImage()),
            tb('table', '表格', () => this.insertTable()),
            tb('chart-column', '图表', () => this.insertChart()),
            tb('sigma', '公式', () => this.insertMath()),
            tb('smile-plus', '图标', () => this.insertIcon()))
        // 文字格式
        this.fontSel = fontSelect(FONTS, FONTS[0][0], v => this.fmtText({ font: v }), { title: '字体', width: 112 })
        this.sizeInput = numberInput(40, v => this.fmtText({ size: v }), { min: 8, max: 400, width: 58, title: '字号 (px)' })
        this.boldBtn = tb('bold', '加粗 (Ctrl B)', () => this.toggleFmt('bold'))
        this.italicBtn = tb('italic', '倾斜 (Ctrl I)', () => this.toggleFmt('italic'))
        this.underBtn = tb('underline', '下划线 (Ctrl U)', () => this.toggleFmt('underline'))
        this.colorCtl = colorInput('#333333', v => this.fmtText({ color: v }), { title: '文字颜色' })
        this.tbGroup(this.fontSel.el, this.sizeInput.el,
            tb('a-arrow-up', '增大字号 (Ctrl ])', () => this.bumpSize(1)), tb('a-arrow-down', '减小字号 (Ctrl [)', () => this.bumpSize(-1)),
            this.boldBtn, this.italicBtn, this.underBtn, this.colorCtl.el)
        this.alignBtns = {}
        const aligns = [['left', 'align-left', '左对齐'], ['center', 'align-center', '居中'], ['right', 'align-right', '右对齐'], ['justify', 'align-justify', '两端对齐']]
        this.tbGroup(
            ...aligns.map(([v, ic, t]) => (this.alignBtns[v] = tb(ic, t, () => this.fmtText({ align: v })))),
            tb('list', '项目符号', () => this.execText('insertUnorderedList')),
            tb('list-ordered', '编号', () => this.execText('insertOrderedList')),
            this.dd(icon('align-vertical-justify-center', 17), () => [['top', '顶端对齐'], ['middle', '垂直居中'], ['bottom', '底端对齐']].map(([v, l]) => ({ label: l, run: () => this.fmtText({ valign: v }) })), { title: '垂直对齐' }))
        // 排列
        this.tbGroup(
            this.dd(icon('align-start-vertical', 17), () => this.alignItems(), { title: '对齐与分布' }),
            this.dd(icon('layers', 17), () => this.orderItems(), { title: '排列层次' }),
            tb('copy-plus', '复制 (Ctrl D)', () => this.duplicate()),
            tb('trash-2', '删除 (Delete)', () => this.deleteSel()))
        this.tbGroup(
            this.dd(h('span.tb-new', icon('palette', 15), '主题'), () => this.themeItems(), { title: '设计主题' }),
            h('button.tb-text-btn.primary', { onclick: () => this.present(this.current) }, icon('play', 15), '放映'))
    }

    P.toggleInsert = function (mode) {
        const same = this.insertMode && JSON.stringify(this.insertMode) === JSON.stringify(mode)
        this.insertMode = same ? null : mode
        this.updateInsertUI()
        if (this.insertMode) toast(mode.type === 'text' ? '在幻灯片上拖动以绘制文本框，单击使用默认大小' : `在幻灯片上拖动以绘制${SHAPES[mode.shape] ?? '形状'}（Shift 等比）`)
    }
    P.updateInsertUI = function () {
        this.insertBtns.text.classList.toggle('active', this.insertMode?.type === 'text')
        this.canvasWrap.classList.toggle('inserting', !!this.insertMode)
    }

    P.shapeMenu = function () {
        const groups = [
            ['基本形状', ['rect', 'roundRect', 'ellipse', 'triangle', 'rightTriangle', 'diamond', 'parallelogram', 'trapezoid', 'pentagon', 'hexagon', 'octagon', 'ring', 'cross']],
            ['箭头与线条', ['arrowRight', 'arrowLeft', 'arrowUp', 'arrowDown', 'chevron', 'line', 'arrow']],
            ['星形与标注', ['star', 'star6', 'callout', 'heart', 'cloud']],
        ]
        const grid = groups.map(([label, list]) => h('div.sl-shape-group',
            h('div.cmenu-header', label),
            h('div.sl-shape-grid', list.map(s => h('button.sl-shape-btn', {
                title: SHAPES[s],
                onclick: () => { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); this.toggleInsert({ type: 'shape', shape: s }) },
            }, shapeIcon(s))))))
        return [{ el: h('div.sl-shape-menu', grid) }]
    }

    // ---------- 文本格式 ----------
    // 编辑中：对选区执行命令；未编辑：作用于选中元素整体
    P.execText = function (cmd, value) {
        if (this.editing) {
            document.execCommand('styleWithCSS', false, true)
            document.execCommand(cmd, false, value)
            this.syncEditing()
            this.updateFormatUI()
            return
        }
        const els = this.selEls().filter(e => e.type === 'text' || e.type === 'shape')
        if (!els.length) return
        for (const el of els) {
            if (cmd === 'insertUnorderedList' || cmd === 'insertOrderedList') {
                const tag = cmd === 'insertOrderedList' ? 'ol' : 'ul'
                const has = new RegExp(`^\\s*<${tag}`).test(el.html ?? '')
                const lines = htmlLines(el.html)
                el.html = has ? lines.map(l => `<div>${l}</div>`).join('') : `<${tag}>${lines.map(l => `<li>${l}</li>`).join('')}</${tag}>`
            }
        }
        this.change('列表')
    }

    P.fmtText = function (st) {
        if (this.editing && (st.color || st.size || st.font)) {
            const sel = getSelection()
            if (sel.rangeCount && !sel.isCollapsed) {
                document.execCommand('styleWithCSS', false, true)
                if (st.color) document.execCommand('foreColor', false, st.color)
                if (st.font) document.execCommand('fontName', false, st.font)
                if (st.size) wrapSelection(`font-size:${st.size}px`)
                this.syncEditing()
                return
            }
        }
        const els = this.editing ? [this.editing.el] : this.selEls().filter(e => e.type === 'text' || e.type === 'shape' || e.type === 'table' || e.type === 'math')
        if (!els.length) return
        for (const el of els) {
            if (el.type === 'math') { if (st.color) el.color = st.color; if (st.size) el.size = st.size; continue }
            if (el.type === 'table') { el.style = { ...(el.style ?? {}), ...(st.size ? { size: st.size } : {}) }; continue }
            el.style = { ...(el.style ?? {}), ...st }
            if (el.type === 'shape' && el.html == null) el.html = ''
        }
        if (this.editing) {
            // 保持编辑状态：直接更新编辑节点的样式
            const { target } = this.editing
            if (st.align) target.style.textAlign = st.align
            if (st.valign) target.style.justifyContent = { top: 'flex-start', middle: 'center', bottom: 'flex-end' }[st.valign]
            if (st.color) target.style.color = st.color
            if (st.size) target.style.fontSize = st.size + 'px'
            if (st.font) target.style.fontFamily = st.font
            this.commit('文字格式')
            this.updateFormatUI()
            return
        }
        this.change('文字格式', { merge: 'fmt' + Object.keys(st).join() })
    }

    P.toggleFmt = function (k) {
        if (this.editing) {
            const sel = getSelection()
            if (sel.rangeCount && !sel.isCollapsed) return this.execText(k)
        }
        const els = this.editing ? [this.editing.el] : this.selEls().filter(e => e.type === 'text' || e.type === 'shape')
        if (!els.length) return
        const on = !els.every(e => e.style?.[k])
        this.fmtText({ [k]: on })
    }

    P.bumpSize = function (dir) {
        const els = this.editing ? [this.editing.el] : this.selEls()
        const cur = els[0]?.type === 'math' ? els[0].size ?? 48 : els[0]?.style?.size ?? 40
        const next = dir > 0 ? SIZES_PX.find(s => s > cur) ?? cur + 16 : [...SIZES_PX].reverse().find(s => s < cur) ?? Math.max(8, cur - 4)
        this.fmtText({ size: next })
    }

    P.updateFormatUI = function () {
        const el = this.editing?.el ?? this.selEls()[0]
        const st = el?.style ?? {}
        const t = this.deck ? themeOf(this.deck) : null
        this.fontSel.set(st.font ?? t?.font ?? FONTS[0][0])
        this.sizeInput.set(el?.type === 'math' ? el.size ?? 48 : st.size ?? 40)
        let bold = !!st.bold, italic = !!st.italic, under = !!st.underline
        if (this.editing) {
            try { bold = document.queryCommandState('bold'); italic = document.queryCommandState('italic'); under = document.queryCommandState('underline') } catch { /* ignore */ }
        }
        this.boldBtn.classList.toggle('active', bold)
        this.italicBtn.classList.toggle('active', italic)
        this.underBtn.classList.toggle('active', under)
        this.colorCtl.set(el?.type === 'math' ? el.color ?? t?.text : st.color ?? t?.text ?? '#333333')
        for (const [k, b] of Object.entries(this.alignBtns)) b.classList.toggle('active', (st.align ?? 'left') === k && !!el)
    }

    // ---------- 插入 ----------
    P.centerRect = function (w, hh) {
        const s = sizeOf(this.deck)
        return { x: Math.round((s.w - w) / 2), y: Math.round((s.h - hh) / 2), w: Math.round(w), h: Math.round(hh) }
    }
    P.insertImage = async function (img) {
        img ??= await pickImage()
        if (!img) return
        const s = sizeOf(this.deck)
        const k = Math.min(1, (s.w * 0.6) / img.width, (s.h * 0.6) / img.height)
        this.addEls([this.makeEl({ type: 'image', src: img.dataURL, fit: 'cover', radius: 0, ...this.centerRect(img.width * k, img.height * k) })], '插入图片')
    }
    P.replaceImage = async function (el) {
        const img = await pickImage()
        if (!img) return
        el.src = img.dataURL
        el.h = Math.round(el.w * img.height / img.width)
        this.change('替换图片')
    }
    P.insertTable = async function () {
        const r = await formDialog({ title: '插入表格', fields: [{ key: 'rows', label: '行数', type: 'number', value: 4, min: 1, max: 30 }, { key: 'cols', label: '列数', type: 'number', value: 4, min: 1, max: 12 }] })
        if (!r) return
        const rows = Array.from({ length: r.rows }, (_, i) => Array.from({ length: r.cols }, (_, j) => (i === 0 ? `标题 ${j + 1}` : '')))
        const s = sizeOf(this.deck)
        this.addEls([this.makeEl({ type: 'table', rows, style: { header: true, band: true, color: themeOf(this.deck).accent, border: '#cbd5e1', size: 28 }, ...this.centerRect(Math.min(s.w - 200, r.cols * 280), r.rows * 74) })], '插入表格')
    }
    P.insertChart = async function () {
        const chart = await editChart(defaultChart(themeOf(this.deck)))
        if (!chart) return
        this.addEls([this.makeEl({ type: 'chart', chart, ...this.centerRect(1100, 640) })], '插入图表')
    }
    P.editChart = async function (el) {
        const chart = await editChart(clone(el.chart))
        if (!chart) return
        el.chart = chart
        this.change('编辑图表')
    }
    P.insertMath = async function () {
        const tex = await editMath('\\int_0^1 x^2\\,dx = \\frac{1}{3}')
        if (!tex) return
        this.addEls([this.makeEl({ type: 'math', tex, size: 56, color: themeOf(this.deck).text, ...this.centerRect(900, 200) })], '插入公式')
    }
    P.editMath = async function (el) {
        const tex = await editMath(el.tex)
        if (tex == null) return
        el.tex = tex
        this.change('编辑公式')
    }
    P.insertIcon = async function () {
        const r = await pickIcon()
        if (!r) return
        this.addEls([this.makeEl({ type: 'icon', svg: r.svg, name: r.name, color: themeOf(this.deck).accent, ...this.centerRect(200, 200) })], '插入图标')
    }
    P.editTable = function (el) { return editTable(this, el) }

    P.onPaste = async function (e) {
        if (this.editing) {
            // 编辑文字时只粘贴纯文本，避免带入外部样式
            const text = e.clipboardData.getData('text/plain')
            e.preventDefault()
            document.execCommand('insertText', false, text)
            return
        }
        const file = [...e.clipboardData.files].find(f => f.type.startsWith('image/'))
        if (file) { e.preventDefault(); return this.insertBlobImage(file) }
    }
    P.insertBlobImage = async function (blob) {
        const dataURL = await blobToDataURL(blob)
        const img = await loadImage(dataURL)
        return this.insertImage({ dataURL, width: img.naturalWidth, height: img.naturalHeight })
    }
    P.onDrop = function (e) {
        const files = [...e.dataTransfer.files].filter(f => f.type.startsWith('image/'))
        if (!files.length) return
        e.preventDefault()
        e.stopPropagation()
        files.forEach(f => this.insertBlobImage(f))
    }

    // ---------- 剪贴板 ----------
    P.copy = function (cut) {
        const els = this.selEls()
        if (!els.length) return false
        this.clipboard = clone(els)
        this.pasteCount = 0
        // 同时写入系统剪贴板：纯文本内容
        const text = els.map(e => e.html ? e.html.replace(/<[^>]+>/g, ' ').trim() : '').filter(Boolean).join('\n')
        navigator.clipboard.writeText(text || ' ').catch(() => {})
        if (cut) this.deleteSel()
        return true
    }
    P.paste = async function () {
        if (this.clipboard?.length) {
            this.pasteCount = (this.pasteCount ?? 0) + 1
            const copies = this.clipboard.map(e => ({ ...clone(e), id: newId(), x: e.x + 30 * this.pasteCount, y: e.y + 30 * this.pasteCount }))
            this.addEls(copies, '粘贴')
            return
        }
        try {
            const items = await navigator.clipboard.read()
            for (const it of items) {
                const type = it.types.find(t => t.startsWith('image/'))
                if (type) return this.insertBlobImage(await it.getType(type))
            }
            const text = await navigator.clipboard.readText()
            if (text.trim()) this.addEls([this.makeEl({ type: 'text', html: text.split('\n').map(l => `<div>${escapeHTML(l) || '<br>'}</div>`).join(''), ...this.centerRect(900, 200) })], '粘贴文本')
        } catch { /* 无权限或剪贴板为空 */ }
    }
    P.duplicate = function () {
        const els = this.selEls()
        if (!els.length) return
        this.duplicateEls(els)
        this.change('复制')
    }

    // ---------- 排列 ----------
    P.alignSel = function (how) {
        const els = this.selEls()
        if (!els.length) return
        const s = sizeOf(this.deck)
        const box = els.length === 1 ? { x: 0, y: 0, w: s.w, h: s.h } : unionBox(els)
        for (const el of els) {
            if (how === 'left') el.x = box.x
            if (how === 'center') el.x = Math.round(box.x + box.w / 2 - el.w / 2)
            if (how === 'right') el.x = box.x + box.w - el.w
            if (how === 'top') el.y = box.y
            if (how === 'middle') el.y = Math.round(box.y + box.h / 2 - el.h / 2)
            if (how === 'bottom') el.y = box.y + box.h - el.h
        }
        this.change('对齐')
    }
    P.distribute = function (axis) {
        const els = this.selEls()
        if (els.length < 3) { toast('分布需要至少选择三个对象'); return }
        const k = axis === 'h' ? 'x' : 'y', d = axis === 'h' ? 'w' : 'h'
        els.sort((a, b) => a[k] - b[k])
        const first = els[0], last = els[els.length - 1]
        const total = els.reduce((s, e) => s + e[d], 0)
        const gap = (last[k] + last[d] - first[k] - total) / (els.length - 1)
        let pos = first[k]
        for (const e of els) { e[k] = Math.round(pos); pos += e[d] + gap }
        this.change('分布')
    }
    P.order = function (how) {
        const els = this.slide.els
        const set = new Set(this.sel)
        const chosen = els.filter(e => set.has(e.id)), rest = els.filter(e => !set.has(e.id))
        if (how === 'front') this.slide.els = [...rest, ...chosen]
        else if (how === 'back') this.slide.els = [...chosen, ...rest]
        else {
            const arr = [...els]
            const idx = arr.map((e, i) => (set.has(e.id) ? i : -1)).filter(i => i >= 0)
            if (how === 'forward') for (const i of idx.reverse()) { if (i < arr.length - 1 && !set.has(arr[i + 1].id)) [arr[i], arr[i + 1]] = [arr[i + 1], arr[i]] }
            if (how === 'backward') for (const i of idx) { if (i > 0 && !set.has(arr[i - 1].id)) [arr[i], arr[i - 1]] = [arr[i - 1], arr[i]] }
            this.slide.els = arr
        }
        this.change('调整层次')
    }
    P.group = function (on) {
        const els = this.selEls()
        if (on && els.length < 2) return
        const g = on ? newId() : undefined
        for (const e of els) { if (g) e.group = g; else delete e.group }
        this.change(on ? '组合' : '取消组合')
    }
    P.lock = function () {
        const els = this.selEls()
        const on = !els.every(e => e.locked)
        for (const e of els) e.locked = on
        this.change(on ? '锁定' : '解锁')
    }
    P.nudge = function (dx, dy) {
        const els = this.selEls().filter(e => !e.locked)
        if (!els.length) return false
        for (const e of els) { e.x += dx; e.y += dy }
        this.change('微移', { merge: 'nudge' })
        return true
    }

    P.alignItems = function () {
        const n = this.sel.length
        return [
            { header: n > 1 ? '相对于所选对象' : '相对于幻灯片' },
            { label: '左对齐', icon: 'align-start-vertical', disabled: () => !n, run: () => this.alignSel('left') },
            { label: '水平居中', icon: 'align-center-vertical', disabled: () => !n, run: () => this.alignSel('center') },
            { label: '右对齐', icon: 'align-end-vertical', disabled: () => !n, run: () => this.alignSel('right') },
            { label: '顶端对齐', icon: 'align-start-horizontal', disabled: () => !n, run: () => this.alignSel('top') },
            { label: '垂直居中', icon: 'align-center-horizontal', disabled: () => !n, run: () => this.alignSel('middle') },
            { label: '底端对齐', icon: 'align-end-horizontal', disabled: () => !n, run: () => this.alignSel('bottom') },
            '-',
            { label: '横向分布', icon: 'align-horizontal-distribute-center', disabled: () => n < 3, run: () => this.distribute('h') },
            { label: '纵向分布', icon: 'align-vertical-distribute-center', disabled: () => n < 3, run: () => this.distribute('v') },
        ]
    }
    P.orderItems = function () {
        const n = this.sel.length
        return [
            { label: '置于顶层', icon: 'bring-to-front', key: 'Ctrl+Shift+]', disabled: () => !n, run: () => this.order('front') },
            { label: '上移一层', icon: 'arrow-up', key: 'Ctrl+]', disabled: () => !n, run: () => this.order('forward') },
            { label: '下移一层', icon: 'arrow-down', key: 'Ctrl+[', disabled: () => !n, run: () => this.order('backward') },
            { label: '置于底层', icon: 'send-to-back', key: 'Ctrl+Shift+[', disabled: () => !n, run: () => this.order('back') },
            '-',
            { label: '组合', icon: 'group', key: 'Ctrl+G', disabled: () => n < 2, run: () => this.group(true) },
            { label: '取消组合', icon: 'ungroup', key: 'Ctrl+Shift+G', disabled: () => !this.selEls().some(e => e.group), run: () => this.group(false) },
            { label: '锁定 / 解锁', icon: 'lock', key: 'Ctrl+L', disabled: () => !n, run: () => this.lock() },
        ]
    }
    P.themeItems = function () {
        return Object.entries(THEMES).map(([k, t]) => ({
            label: t.name, swatch: t.bg.type === 'linear' ? t.bg.stops[0][1] : t.bg.color, checked: () => this.deck.theme === k,
            run: () => this.setTheme(k),
        }))
    }
    P.setTheme = function (k) {
        applyThemeToDeck(this.deck, k)
        for (const s of this.deck.slides) delete s.bg
        this.renderAll()
        this.commit('设计主题')
    }

    P.newSlideMenu = function (e) {
        openMenu(Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, run: () => this.addSlide(k) })), { anchor: e.currentTarget })
    }

    P.slideMenuItems = function () {
        const s = this.slide
        return [
            { label: '新建幻灯片', icon: 'plus', key: 'Ctrl+M', submenu: Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, run: () => this.addSlide(k) })) },
            { label: '复制幻灯片', icon: 'copy-plus', key: 'Ctrl+Shift+D', run: () => this.duplicateSlide() },
            { label: '删除幻灯片', icon: 'trash-2', danger: true, disabled: () => this.deck.slides.length <= 1, run: () => this.deleteSlide() },
            '-',
            { label: s.hidden ? '取消隐藏' : '隐藏幻灯片', icon: s.hidden ? 'eye' : 'eye-off', run: () => { s.hidden = !s.hidden; this.renderThumbs(); this.commit(s.hidden ? '隐藏幻灯片' : '显示幻灯片') } },
            { label: '上移', icon: 'arrow-up', disabled: () => this.current === 0, run: () => this.moveSlide(this.current, this.current - 1) },
            { label: '下移', icon: 'arrow-down', disabled: () => this.current >= this.deck.slides.length - 1, run: () => this.moveSlide(this.current, this.current + 1) },
            '-',
            { label: '版式', icon: 'layout-template', submenu: Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, checked: () => s.layout === k, run: () => this.applyLayout(k) })) },
            { label: '从此页放映', icon: 'play', key: 'Shift+F5', run: () => this.present(this.current) },
        ]
    }
    // 更换版式：保留已有文本内容，按顺序填入新版式的占位符
    P.applyLayout = async function (k) {
        const { layoutEls } = await import('./model.js')
        const s = this.slide
        const texts = s.els.filter(e => e.type === 'text' && e.placeholder)
        const others = s.els.filter(e => !(e.type === 'text' && e.placeholder))
        const fresh = layoutEls(this.deck, k)
        fresh.filter(e => e.type === 'text').forEach((e, i) => { if (texts[i]) e.html = texts[i].html })
        s.layout = k
        s.els = [...fresh, ...others]
        this.sel = []
        this.change('更换版式')
    }

    P.onContext = function (e) {
        const el = this.elAt(e)
        if (el && !this.sel.includes(el.id)) this.setSel([el.id])
        if (!el) this.setSel([])
        const els = this.selEls()
        const items = els.length ? [
            { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => this.copy(true) },
            { label: '复制', icon: 'copy', key: 'Ctrl+C', run: () => this.copy() },
            { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste() },
            { label: '创建副本', icon: 'copy-plus', key: 'Ctrl+D', run: () => this.duplicate() },
            '-',
            els.length === 1 && (els[0].type === 'text' || els[0].type === 'shape' && !['line', 'arrow'].includes(els[0].shape)) ? { label: '编辑文字', icon: 'type', run: () => this.startEditing(els[0]) } : null,
            els.length === 1 && els[0].type === 'chart' ? { label: '编辑数据…', icon: 'chart-column', run: () => this.editChart(els[0]) } : null,
            els.length === 1 && els[0].type === 'math' ? { label: '编辑公式…', icon: 'sigma', run: () => this.editMath(els[0]) } : null,
            els.length === 1 && els[0].type === 'image' ? { label: '更换图片…', icon: 'image', run: () => this.replaceImage(els[0]) } : null,
            els.length === 1 && els[0].type === 'table' ? { label: '表格行列…', icon: 'table', submenu: () => this.tableItems(els[0]) } : null,
            { label: '对齐', icon: 'align-start-vertical', submenu: () => this.alignItems() },
            { label: '排列', icon: 'layers', submenu: () => this.orderItems() },
            { label: '动画', icon: 'sparkles', submenu: () => this.animItems() },
            '-',
            { label: '删除', icon: 'trash-2', danger: true, key: 'Delete', run: () => this.deleteSel() },
        ] : [
            { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste() },
            { label: '全选', key: 'Ctrl+A', run: () => this.setSel(this.slide.els.map(e => e.id)) },
            '-',
            { label: '新建幻灯片', icon: 'plus', submenu: Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, run: () => this.addSlide(k) })) },
            { label: '版式', icon: 'layout-template', submenu: Object.entries(LAYOUTS).map(([k, l]) => ({ label: l, checked: () => this.slide.layout === k, run: () => this.applyLayout(k) })) },
            { label: '设计主题', icon: 'palette', submenu: () => this.themeItems() },
            { label: '背景…', icon: 'paint-bucket', run: () => this.panelTab?.('slide') },
        ]
        contextMenu(e, items)
    }

    P.animItems = function () {
        const els = this.selEls()
        const set = type => {
            let order = Math.max(0, ...this.slide.els.map(e => e.anim?.order ?? 0))
            for (const e of els) e.anim = type ? { type, dur: e.anim?.dur ?? 0.6, delay: 0, order: e.anim?.order ?? ++order } : undefined
            this.change(type ? '设置动画' : '移除动画')
        }
        return [
            ...Object.entries(ANIMS).map(([k, l]) => ({ label: l, checked: () => els.every(e => e.anim?.type === k), run: () => set(k) })),
            '-',
            { label: '移除动画', danger: true, disabled: () => !els.some(e => e.anim), run: () => set(null) },
        ]
    }

    P.tableItems = function (el) {
        const cell = this.editing?.el === el ? getSelection().anchorNode?.parentElement?.closest?.('th, td') ?? getSelection().anchorNode?.closest?.('th, td') : null
        const r = Number(cell?.dataset.r ?? el.rows.length - 1), c = Number(cell?.dataset.c ?? el.rows[0].length - 1)
        const mod = (fn, label) => { this.stopEditing(); fn(); el.h = Math.max(el.h, el.rows.length * 60); this.change(label) }
        return [
            { label: '在下方插入行', run: () => mod(() => el.rows.splice(r + 1, 0, el.rows[0].map(() => '')), '插入行') },
            { label: '在上方插入行', run: () => mod(() => el.rows.splice(r, 0, el.rows[0].map(() => '')), '插入行') },
            { label: '在右侧插入列', run: () => mod(() => el.rows.forEach(row => row.splice(c + 1, 0, '')), '插入列') },
            { label: '在左侧插入列', run: () => mod(() => el.rows.forEach(row => row.splice(c, 0, '')), '插入列') },
            '-',
            { label: '删除行', danger: true, disabled: () => el.rows.length <= 1, run: () => mod(() => el.rows.splice(r, 1), '删除行') },
            { label: '删除列', danger: true, disabled: () => el.rows[0].length <= 1, run: () => mod(() => el.rows.forEach(row => row.splice(c, 1)), '删除列') },
            '-',
            { label: '标题行', checked: () => el.style?.header !== false, run: () => { el.style = { ...el.style, header: el.style?.header === false }; this.change('表格样式') } },
            { label: '镶边行', checked: () => el.style?.band !== false, run: () => { el.style = { ...el.style, band: el.style?.band === false }; this.change('表格样式') } },
        ]
    }

    // ---------- 菜单栏 ----------
    P.menus = function () {
        const n = () => this.sel.length
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors', key: 'Ctrl+X', disabled: () => !n(), run: () => this.copy(true) },
                    { label: '复制', icon: 'copy', key: 'Ctrl+C', disabled: () => !n(), run: () => this.copy() },
                    { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste() },
                    { label: '创建副本', icon: 'copy-plus', key: 'Ctrl+D', disabled: () => !n(), run: () => this.duplicate() },
                    { label: '删除', icon: 'trash-2', key: 'Delete', disabled: () => !n(), run: () => this.deleteSel() },
                    '-',
                    { label: '全选', key: 'Ctrl+A', run: () => this.setSel(this.slide.els.map(e => e.id)) },
                    { label: '查找与替换…', icon: 'replace', key: 'Ctrl+H', run: () => this.findReplace() },
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '适合窗口', key: 'Ctrl+0', run: () => { this.zoomMode = 'fit'; this.fit() } },
                    { label: '放大', icon: 'zoom-in', key: 'Ctrl+=', run: () => this.setZoom(this.zoom * 1.2) },
                    { label: '缩小', icon: 'zoom-out', key: 'Ctrl+-', run: () => this.setZoom(this.zoom / 1.2) },
                    { label: '实际大小 (100%)', run: () => this.setZoom(1) },
                    '-',
                    { label: '显示备注', checked: () => !this.notesBar.classList.contains('collapsed'), run: () => this.toggleNotes() },
                    { label: '显示右侧面板', checked: () => !this.panels.classList.contains('hidden'), key: 'Ctrl+\\', run: () => { this.panels.classList.toggle('hidden'); this.fit() } },
                ],
            },
            {
                label: '插入', items: () => [
                    { label: '新建幻灯片', icon: 'plus', key: 'Ctrl+M', run: () => this.addSlide(this.slide.layout === 'title' ? 'content' : this.slide.layout ?? 'content') },
                    '-',
                    { label: '文本框', icon: 'type', run: () => this.toggleInsert({ type: 'text' }) },
                    { label: '形状', icon: 'shapes', submenu: Object.entries(SHAPES).map(([k, l]) => ({ label: l, run: () => this.toggleInsert({ type: 'shape', shape: k }) })) },
                    { label: '图片…', icon: 'image-plus', run: () => this.insertImage() },
                    { label: '表格…', icon: 'table', run: () => this.insertTable() },
                    { label: '图表…', icon: 'chart-column', run: () => this.insertChart() },
                    { label: '公式…', icon: 'sigma', run: () => this.insertMath() },
                    { label: '图标…', icon: 'smile-plus', run: () => this.insertIcon() },
                    '-',
                    { label: '页码', icon: 'hash', run: () => this.insertSlideNumbers() },
                ],
            },
            {
                label: '格式', items: () => [
                    { label: '加粗', icon: 'bold', key: 'Ctrl+B', run: () => this.toggleFmt('bold') },
                    { label: '倾斜', icon: 'italic', key: 'Ctrl+I', run: () => this.toggleFmt('italic') },
                    { label: '下划线', icon: 'underline', key: 'Ctrl+U', run: () => this.toggleFmt('underline') },
                    { label: '删除线', icon: 'strikethrough', run: () => this.toggleFmt('strike') },
                    '-',
                    { label: '增大字号', icon: 'a-arrow-up', key: 'Ctrl+Shift+.', run: () => this.bumpSize(1) },
                    { label: '减小字号', icon: 'a-arrow-down', key: 'Ctrl+Shift+,', run: () => this.bumpSize(-1) },
                    '-',
                    { label: '左对齐', icon: 'align-left', key: 'Ctrl+Shift+L', run: () => this.fmtText({ align: 'left' }) },
                    { label: '居中', icon: 'align-center', key: 'Ctrl+E', run: () => this.fmtText({ align: 'center' }) },
                    { label: '右对齐', icon: 'align-right', key: 'Ctrl+R', run: () => this.fmtText({ align: 'right' }) },
                    '-',
                    { label: '行距', submenu: [1, 1.15, 1.35, 1.5, 2].map(v => ({ label: String(v), run: () => this.fmtText({ lineHeight: v }) })) },
                ],
            },
            { label: '排列', items: () => [...this.alignItems(), '-', ...this.orderItems()] },
            {
                label: '设计', items: () => [
                    { header: '主题' }, ...this.themeItems(), '-',
                    { label: '幻灯片大小', submenu: [['16:9', '宽屏 16:9'], ['4:3', '标准 4:3']].map(([v, l]) => ({ label: l, checked: () => this.deck.ratio === v, run: () => this.setRatio(v) })) },
                    { label: '背景…', icon: 'paint-bucket', run: () => this.panelTab('slide') },
                ],
            },
            {
                label: '切换', items: () => [
                    ...Object.entries(TRANSITIONS).map(([k, l]) => ({ label: l, checked: () => (this.slide.transition?.type ?? 'none') === k, run: () => this.setTransition(k) })),
                    '-',
                    { label: '应用到全部幻灯片', icon: 'copy-check', run: () => { for (const s of this.deck.slides) s.transition = clone(this.slide.transition); this.renderThumbs(); this.commit('切换效果') } },
                ],
            },
            { label: '动画', items: () => [...(this.sel.length ? this.animItems() : [{ label: '请先选择对象', disabled: true }]), '-', { label: '动画窗格', icon: 'list-ordered', run: () => this.panelTab('anim') }] },
            {
                label: '放映', items: () => [
                    { label: '从头开始', icon: 'play', key: 'F5', run: () => this.present(0) },
                    { label: '从当前幻灯片开始', icon: 'monitor-play', key: 'Shift+F5', run: () => this.present(this.current) },
                    { label: '演讲者视图', icon: 'monitor-speaker', key: 'Alt+F5', run: () => this.present(this.current, true) },
                    '-',
                    { label: '隐藏当前幻灯片', checked: () => !!this.slide.hidden, run: () => { this.slide.hidden = !this.slide.hidden; this.renderThumbs(); this.commit('隐藏幻灯片') } },
                ],
            },
        ]
    }

    P.setTransition = function (k) {
        this.slide.transition = { ...(this.slide.transition ?? {}), type: k, dur: this.slide.transition?.dur ?? 0.6 }
        this.refreshThumb(this.current)
        this.refreshPanels()
        this.commit('切换效果')
        if (k !== 'none') this.previewTransition()
    }
    P.previewTransition = function () {
        const inner = this.slideEl
        const type = this.slide.transition?.type
        const kf = { fade: [{ opacity: 0 }, { opacity: 1 }], push: [{ transform: inner.style.transform + ' translateX(40%)', opacity: 0 }, { transform: inner.style.transform }], zoom: [{ transform: inner.style.transform + ' scale(.7)', opacity: 0 }, { transform: inner.style.transform }], wipe: [{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0 0 0)' }], split: [{ clipPath: 'inset(0 50%)' }, { clipPath: 'inset(0 0)' }], blur: [{ filter: 'blur(20px)', opacity: 0 }, { filter: 'none', opacity: 1 }], cover: [{ transform: inner.style.transform + ' translateY(40%)' }, { transform: inner.style.transform }], flip: [{ transform: inner.style.transform + ' perspective(2400px) rotateY(80deg)', opacity: 0 }, { transform: inner.style.transform }] }[type]
        if (kf) inner.animate(kf, { duration: (this.slide.transition?.dur ?? 0.6) * 1000, easing: 'cubic-bezier(.2,.8,.2,1)' })
    }

    P.setRatio = function (r) {
        if (this.deck.ratio === r) return
        const from = sizeOf(this.deck)
        this.deck.ratio = r
        const to = sizeOf(this.deck)
        const kx = to.w / from.w
        for (const s of this.deck.slides) for (const e of s.els) { e.x = Math.round(e.x * kx); e.w = Math.round(e.w * kx) }
        this.zoomMode = 'fit'
        this.renderAll()
        this.fit()
        this.commit('幻灯片大小')
    }

    P.insertSlideNumbers = function () {
        const { w, h: H } = sizeOf(this.deck)
        const t = themeOf(this.deck)
        this.deck.slides.forEach((s, i) => {
            s.els = s.els.filter(e => !e.slideNumber)
            if (i === 0) return
            s.els.push({ id: newId(), type: 'text', slideNumber: true, x: w - 220, y: H - 90, w: 160, h: 60, rot: 0, html: String(i + 1), style: { font: t.font, size: 26, color: t.text, align: 'right', valign: 'middle' } })
        })
        this.renderAll()
        this.commit('插入页码')
    }

    P.findReplace = async function () {
        const r = await formDialog({ title: '查找与替换', fields: [{ key: 'find', label: '查找', value: '' }, { key: 'repl', label: '替换为', value: '' }], okText: '全部替换' })
        if (!r?.find) return
        let count = 0
        const re = new RegExp(r.find.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g')
        const rep = html => html.replace(/(^|>)([^<]*)/g, (m, a, text) => a + text.replace(re, () => { count++; return escapeHTML(r.repl) }))
        for (const s of this.deck.slides) for (const e of s.els) {
            if (e.html) e.html = rep(e.html)
            if (e.rows) e.rows = e.rows.map(row => row.map(rep))
        }
        this.renderAll()
        if (count) this.commit('替换')
        toast(count ? `已替换 ${count} 处` : '未找到匹配内容')
    }

    // ---------- 键盘 ----------
    P.onKey = function (e) {
        if (this.presenter) return true
        const k = e.key
        if (k === 'F5') { e.preventDefault(); this.present(e.shiftKey ? this.current : e.altKey ? this.current : 0, e.altKey); return true }
        if (this.editing) {
            if (k === 'Escape') { this.stopEditing(); this.setSel([this.sel[0]].filter(Boolean)); return true }
            if (e.ctrlKey && /^[biu]$/i.test(k)) { this.execText({ b: 'bold', i: 'italic', u: 'underline' }[k.toLowerCase()]); return true }
            if (k === 'Tab' && this.editing.el.type === 'table') {
                const cells = [...this.editing.node.querySelectorAll('th, td')]
                const cur = cells.indexOf(getSelection().anchorNode?.parentElement?.closest?.('th, td') ?? getSelection().anchorNode?.closest?.('th, td'))
                const next = cells[cur + (e.shiftKey ? -1 : 1)]
                if (next) { const r = document.createRange(); r.selectNodeContents(next); getSelection().removeAllRanges(); getSelection().addRange(r) }
                return true
            }
            return false
        }
        const typing = e.target?.closest?.('input, textarea, select, [contenteditable="true"]')
        if (typing) return false
        if (e.target.closest?.('.sl-thumbs') && ['ArrowUp', 'ArrowDown', 'Delete', 'Backspace'].includes(k)) return false
        if (k === 'Escape') { if (this.insertMode) { this.insertMode = null; this.updateInsertUI(); return true } if (this.sel.length) { this.setSel([]); return true } return false }
        if ((k === 'Delete' || k === 'Backspace') && this.sel.length) { this.deleteSel(); return true }
        if (k.startsWith('Arrow') && this.sel.length) {
            const s = e.shiftKey ? 20 : e.altKey ? 1 : 5
            return this.nudge({ ArrowLeft: -s, ArrowRight: s }[k] ?? 0, { ArrowUp: -s, ArrowDown: s }[k] ?? 0)
        }
        if (!this.sel.length && ['PageDown', 'ArrowDown', 'ArrowRight'].includes(k)) { this.select(this.current + 1); return true }
        if (!this.sel.length && ['PageUp', 'ArrowUp', 'ArrowLeft'].includes(k)) { this.select(this.current - 1); return true }
        if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'c') return this.copy()
        if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'x') return this.copy(true)
        if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'v') { this.paste(); return true }
        if (e.ctrlKey && k.toLowerCase() === 'm') { this.addSlide(); return true }
        if (e.ctrlKey && e.shiftKey && k.toLowerCase() === 'd') { this.duplicateSlide(); return true }
        if (k === 'Enter' && this.sel.length === 1) { const el = this.selEls()[0]; if (el.type === 'text' || el.type === 'shape' || el.type === 'table') { this.startEditing(el); return true } }
        // 选中文本框后直接输入：进入编辑并替换内容
        if (this.sel.length === 1 && k.length === 1 && !e.ctrlKey && !e.altKey) {
            const el = this.selEls()[0]
            if (el.type === 'text') { this.startEditing(el); return false }
        }
        return false
    }

    P.buildPanels = function () { buildPanels(this) }
    P.refreshPanels = function () { refreshPanels(this); this.updateFormatUI?.() }
}

function shapeIcon(s) {
    const svgNS = 'http://www.w3.org/2000/svg'
    const svg = document.createElementNS(svgNS, 'svg')
    svg.setAttribute('viewBox', '-2 -2 28 28')
    svg.setAttribute('width', '22'); svg.setAttribute('height', '22')
    if (s === 'line' || s === 'arrow') {
        svg.innerHTML = `<line x1="2" y1="22" x2="22" y2="2" stroke="currentColor" stroke-width="2"/>${s === 'arrow' ? '<path d="M22 2l-7 1.5L20.5 9z" fill="currentColor"/>' : ''}`
        return svg
    }
    import('./render.js').then(({ shapePath }) => { svg.innerHTML = `<path d="${shapePath(s, 24, s.startsWith('arrow') && (s === 'arrowUp' || s === 'arrowDown') ? 24 : 24, 6)}" fill="currentColor" fill-opacity=".18" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>` })
    return svg
}

function htmlLines(html) {
    const d = document.createElement('div')
    d.innerHTML = html ?? ''
    const li = [...d.querySelectorAll('li')]
    if (li.length) return li.map(x => x.innerHTML)
    const blocks = [...d.children].filter(x => ['DIV', 'P'].includes(x.tagName))
    if (blocks.length) return blocks.map(x => x.innerHTML)
    return (d.innerHTML || '').split(/<br\s*\/?>/i)
}

// 用 span 包裹选区并设置样式
function wrapSelection(css) {
    const sel = getSelection()
    if (!sel.rangeCount) return
    const range = sel.getRangeAt(0)
    const span = document.createElement('span')
    span.setAttribute('style', css)
    span.append(range.extractContents())
    for (const inner of span.querySelectorAll('[style*="font-size"]')) inner.style.fontSize = ''
    range.insertNode(span)
    sel.removeAllRanges()
    const r = document.createRange()
    r.selectNodeContents(span)
    sel.addRange(r)
}

const escapeHTML = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

export { fill }
