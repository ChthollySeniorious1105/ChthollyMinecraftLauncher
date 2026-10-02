// 电子表格界面：功能区工具栏、编辑栏（名称框 + fx）、工作表标签、状态栏
import { h, fill, toast, colorInput, select, numberInput } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { openMenu, contextMenu } from '../../core/menu.js'
import { FONTS, SIZES, NUM_FORMATS, stepDecimals, DEFAULT_FONT, DEFAULT_SZ, fontFamily } from './format.js'
import { fontSelect } from '../../core/fonts.js'
import { parseRange, parseCell, rangeName } from './addr.js'
import { general } from './numfmt.js'
import { FUNC_INFO } from './funcinfo.js'
import { CHART_KINDS } from './chart.js'
import { editText } from './editing.js'
import { makeCell } from './model.js'

const TAB_COLORS = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#06b6d4', '#3b82f6', '#8b5cf6', '#ec4899', '#64748b']

export const UI = {
    buildUI() {
        const tb = (ic, title, fn) => { const b = this.tb(ic, title, fn); b.addEventListener('mousedown', e => e.preventDefault()); return b }
        const keepFocus = el => { el.addEventListener('mousedown', e => { if (e.target.tagName !== 'SELECT' && e.target.tagName !== 'INPUT') e.preventDefault() }); return el }
        // ---------- 工具栏 ----------
        this.tbGroup(
            tb('undo-2', '撤销 (Ctrl Z)', () => this.undo()), tb('redo-2', '重做 (Ctrl Y)', () => this.redo()),
            this.painterBtn = tb('paintbrush', '格式刷（双击连续使用）', () => this.painter ? (this.painter = null, this.refreshUI()) : this.startPainter(false)))
        this.painterBtn.addEventListener('dblclick', () => this.startPainter(true))
        this.fontSel = fontSelect(FONTS.map(f => [f, f]), DEFAULT_FONT, v => this.applyStyle({ font: v }, '字体'), { title: '字体', width: 110, fmt: 'name', stackOf: fontFamily })
        this.sizeSel = select(SIZES.map(s => [s, String(s)]), DEFAULT_SZ, v => this.applyStyle({ sz: Number(v) }, '字号'), { title: '字号', width: 58 })
        this.bBtn = tb('bold', '加粗 (Ctrl B)', () => this.toggleStyle('b'))
        this.iBtn = tb('italic', '倾斜 (Ctrl I)', () => this.toggleStyle('i'))
        this.uBtn = tb('underline', '下划线 (Ctrl U)', () => this.toggleStyle('u'))
        this.sBtn = tb('strikethrough', '删除线 (Ctrl 5)', () => this.toggleStyle('st'))
        this.colorCtl = colorInput('#dc2626', v => this.applyStyle({ color: v }, '文字颜色'), { title: '文字颜色' })
        this.fillCtl = colorInput('#fff2c7', v => this.applyStyle({ fill: v }, '填充颜色'), { title: '填充颜色' })
        this.fillCtl.el.classList.add('sh-fill-ctl')
        this.tbGroup(this.fontSel.el, this.sizeSel.el,
            tb('a-arrow-up', '增大字号', () => this.bumpFont(1)), tb('a-arrow-down', '减小字号', () => this.bumpFont(-1)),
            this.bBtn, this.iBtn, this.uBtn, this.sBtn,
            h('span.sh-color-wrap', { title: '文字颜色' }, icon('baseline', 16), this.colorCtl.el),
            h('span.sh-color-wrap', { title: '填充颜色' }, icon('paint-bucket', 16), this.fillCtl.el),
            this.dd(icon('grid-2x2', 17), () => this.borderItems(), { title: '边框' }))
        this.alignBtns = {
            left: tb('align-left', '左对齐', () => this.applyStyle({ ha: 'left' }, '对齐')),
            center: tb('align-center', '居中', () => this.applyStyle({ ha: 'center' }, '对齐')),
            right: tb('align-right', '右对齐', () => this.applyStyle({ ha: 'right' }, '对齐')),
        }
        this.vaBtn = this.dd(icon('align-vertical-justify-center', 17), () => [['top', '顶端对齐'], ['middle', '垂直居中'], ['bottom', '底端对齐']].map(([v, l]) => ({ label: l, checked: () => (this.curStyle()?.va ?? 'middle') === v, run: () => this.applyStyle({ va: v }, '垂直对齐') })), { title: '垂直对齐' })
        this.wrapBtn = tb('wrap-text', '自动换行', () => this.toggleStyle('wrap'))
        this.mergeBtn = this.dd(h('span.tb-new', icon('table-cells-merge', 16), '合并'), () => [
            { label: '合并后居中', run: () => this.mergeCells('center') },
            { label: '跨越合并', run: () => this.mergeCells('across') },
            { label: '合并单元格', run: () => this.mergeCells('merge') },
            { label: '取消合并', run: () => this.mergeCells('unmerge') },
        ], { title: '合并单元格' })
        this.tbGroup(...Object.values(this.alignBtns), this.vaBtn, this.wrapBtn, this.mergeBtn)
        this.fmtSel = select(NUM_FORMATS.map(([f, l]) => [f, l]), 'General', v => this.applyStyle({ fmt: v === 'General' ? null : v }, '数字格式'), { title: '数字格式', width: 108 })
        this.tbGroup(this.fmtSel.el,
            tb('japanese-yen', '货币格式', () => this.applyStyle({ fmt: '"¥"#,##0.00' }, '货币格式')),
            tb('percent', '百分比 (Ctrl Shift 5)', () => this.applyStyle({ fmt: '0%' }, '百分比')),
            h('button.tb-text-btn.sh-comma', { title: '千位分隔', onmousedown: e => e.preventDefault(), onclick: () => this.applyStyle({ fmt: '#,##0.00' }, '千位分隔') }, ','),
            h('button.tb-text-btn', { title: '增加小数位数', onmousedown: e => e.preventDefault(), onclick: () => this.stepDecimal(1) }, '.0', icon('arrow-left', 11), '.00'),
            h('button.tb-text-btn', { title: '减少小数位数', onmousedown: e => e.preventDefault(), onclick: () => this.stepDecimal(-1) }, '.00', icon('arrow-right', 11), '.0'))
        this.tbGroup(
            this.dd(icon('sigma', 17), () => this.autoSumItems(), { title: '自动求和' }),
            tb('arrow-down-a-z', '升序排序', () => this.quickSort(false)),
            tb('arrow-down-z-a', '降序排序', () => this.quickSort(true)),
            this.filterBtn = tb('filter', '筛选 (Ctrl Shift L)', () => this.toggleFilter()),
            this.dd(icon('chart-column', 17), () => CHART_KINDS.map(([k, l]) => ({ label: l, run: () => this.insertChart(k) })), { title: '插入图表' }),
            this.dd(icon('paintbrush-vertical', 17), () => this.cfMenuItems(), { title: '条件格式' }),
            tb('search', '查找 (Ctrl F)', () => this.findDialog(false)))
        for (const g of this.toolbar.children) keepFocus(g)

        // ---------- 编辑栏 ----------
        this.nameBox = h('input.sh-namebox', { spellcheck: false, title: '名称框：输入单元格地址并回车跳转' })
        this.nameBox.addEventListener('keydown', e => {
            if (e.key === 'Enter') { e.preventDefault(); this.gotoName(this.nameBox.value); this.focusGrid() }
            if (e.key === 'Escape') { e.preventDefault(); this.refreshUI(); this.focusGrid() }
        })
        this.nameBox.addEventListener('focus', () => this.nameBox.select())
        this.fxMirror = h('div.sh-fx-mirror')
        this.fxInput = h('textarea.sh-fx-input', { spellcheck: false, rows: 1, wrap: 'soft' })
        this.fxWrap = h('div.sh-fx-wrap', this.fxMirror, this.fxInput)
        this.fxBtns = h('div.sh-fx-btns',
            h('button.icon-btn.sh-fx-cancel', { title: '取消 (Esc)', onmousedown: e => e.preventDefault(), onclick: () => this.cancelEdit() }, icon('x', 15)),
            h('button.icon-btn.sh-fx-ok', { title: '确定 (Enter)', onmousedown: e => e.preventDefault(), onclick: () => this.commitEdit() }, icon('check', 15)),
            h('button.icon-btn', { title: '插入函数', onmousedown: e => e.preventDefault(), onclick: () => this.insertFunctionDialog() }, h('i.sh-fx-label', 'fx')))
        this.fxBar = h('div.sh-fxbar', this.nameBox, this.fxBtns, this.fxWrap)
        this.listen(this.fxInput, 'focus', () => { if (!this.editing) this.startEdit({ mode: 'edit', src: 'fx' }) })
        this.listen(this.fxInput, 'input', () => this.onEditorInput(this.fxInput))
        this.listen(this.fxInput, 'keydown', e => this.onEditorKey(e, this.fxInput))
        this.listen(this.fxInput, 'keyup', () => this.editing && this.updateAssist(this.fxInput))
        this.listen(this.fxInput, 'click', () => this.editing && this.updateAssist(this.fxInput))

        // ---------- 工作表标签 ----------
        this.tabsEl = h('div.sh-tabs')
        this.tabBar = h('div.sh-tabbar',
            h('button.icon-btn', { title: '新建工作表 (Shift F11)', onclick: () => this.addSheet() }, icon('plus', 16)),
            h('button.icon-btn', { title: '所有工作表', onclick: e => openMenu(this.sheets.map((s, i) => ({ label: s.name, checked: () => i === this.book.active, run: () => this.switchSheet(i) })), { anchor: e.currentTarget }) }, icon('list', 15)),
            this.tabsEl)
        this.tabsEl.addEventListener('wheel', e => { this.tabsEl.scrollLeft += e.deltaY; e.preventDefault() }, { passive: false })

        this.stage.classList.add('sh-stage')
        this.stage.append(this.fxBar, this.grid.el, this.tabBar)
        this.el.classList.add('sh-root')
    },

    // ---------- 刷新 ----------
    refreshUI() {
        if (!this.fontSel) return
        cancelAnimationFrame(this.uiRaf)
        this.uiRaf = requestAnimationFrame(() => this.refreshUINow())
    },
    refreshUINow() {
        const sh = this.sheet
        const st = this.curStyle() ?? {}
        this.fontSel.set(st.font ?? DEFAULT_FONT)
        this.sizeSel.set(st.sz ?? DEFAULT_SZ)
        this.bBtn.classList.toggle('active', !!st.b)
        this.iBtn.classList.toggle('active', !!st.i)
        this.uBtn.classList.toggle('active', !!st.u)
        this.sBtn.classList.toggle('active', !!st.st)
        this.wrapBtn.classList.toggle('active', !!st.wrap)
        for (const [k, b] of Object.entries(this.alignBtns)) b.classList.toggle('active', st.ha === k)
        const fmt = st.fmt ?? 'General'
        if (!NUM_FORMATS.some(f => f[0] === fmt)) this.fmtSel.setOptions([...NUM_FORMATS.map(([f, l]) => [f, l]), [fmt, '自定义：' + fmt]], fmt)
        else this.fmtSel.set(fmt)
        this.mergeBtn.classList.toggle('active', !!sh.mergeAt(this.sel.r, this.sel.c))
        this.filterBtn.classList.toggle('active', !!sh.meta.filter)
        this.painterBtn.classList.toggle('active', !!this.painter)
        // 编辑栏
        if (document.activeElement !== this.nameBox) this.nameBox.value = this.selName()
        if (!this.editing) {
            const cell = sh.get(this.sel.r, this.sel.c)
            const t = editText(cell)
            this.fxInput.value = t
            this.fxMirror.innerHTML = ''
            this.fxMirror.textContent = t
        }
        this.fxBar.classList.toggle('editing', !!this.editing)
        this.autoGrowFx()
        this.updateStatusBar()
        this.el.classList.toggle('sh-painting', !!this.painter)
    },
    autoGrowFx() {
        if (!this.fxInput) return
        const lines = Math.min(6, (this.fxInput.value.match(/\n/g)?.length ?? 0) + 1)
        this.fxWrap.style.height = (lines * 20 + 8) + 'px'
    },
    curStyle() { return this.sheet.styleAt(this.sel.r, this.sel.c) },

    updateStatusBar() {
        const s = this.statusStats()
        const fmt = v => general(Math.round(v * 1e10) / 1e10)
        const items = []
        const mode = this.editing ? (this.editing.mode === 'edit' ? '编辑' : '输入') : this.painter ? '格式刷' : this.clip ? '选择目标区域后按 Enter 或 Ctrl V 粘贴' : '就绪'
        items.push(h('span.st-item', icon(this.editing ? 'pencil' : 'check', 13), mode))
        if (s.count > 1 || s.nums > 1) {
            if (s.nums) items.push(h('span.st-item', `平均值：${fmt(s.avg)}`))
            items.push(h('span.st-item', `计数：${s.count}`))
            if (s.nums) items.push(h('span.st-item', `求和：${fmt(s.sum)}`), h('span.st-item', `最小值：${fmt(s.min)}`), h('span.st-item', `最大值：${fmt(s.max)}`))
        }
        items.push(h('span.st-flex'))
        items.push(h('button', { title: '网格线', onclick: () => this.toggleGridlines() }, icon('grid-3x3', 13)))
        items.push(h('button', { title: '冻结窗格', onclick: e => openMenu(this.freezeItems(), { anchor: e.currentTarget, align: 'end' }) }, icon('snowflake', 13)))
        items.push(h('button', { onclick: () => this.setZoom(this.zoom - 0.1) }, icon('minus', 13)))
        items.push(h('button', { title: '重置缩放', onclick: () => this.setZoom(1) }, Math.round(this.zoom * 100) + '%'))
        items.push(h('button', { onclick: () => this.setZoom(this.zoom + 0.1) }, icon('plus', 13)))
        this.statusItems(...items)
    },

    renderTabs() {
        const tabs = this.sheets.map((sh, i) => {
            const t = h('div.sh-tab' + (i === this.book.active ? '.active' : ''), {
                draggable: true, title: sh.name, style: sh.meta.color ? { '--tab': sh.meta.color } : null,
                onclick: () => this.switchSheet(i),
                ondblclick: () => this.renameSheet(i),
                oncontextmenu: e => { if (i !== this.book.active) this.switchSheet(i); contextMenu(e, this.tabMenu(i)) },
            }, h('span', sh.name))
            t.addEventListener('dragstart', e => { this.dragTab = i; e.dataTransfer.effectAllowed = 'move' })
            t.addEventListener('dragover', e => { if (this.dragTab == null) return; e.preventDefault(); t.classList.add('drop') })
            t.addEventListener('dragleave', () => t.classList.remove('drop'))
            t.addEventListener('drop', e => { e.preventDefault(); t.classList.remove('drop'); if (this.dragTab != null && this.dragTab !== i) this.moveSheet(this.dragTab, i); this.dragTab = null })
            return t
        })
        fill(this.tabsEl, tabs)
        this.tabsEl.children[this.book.active]?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
    },
    tabMenu(i) {
        return [
            { label: '插入工作表', icon: 'plus', run: () => this.addSheet(null, i + 1) },
            { label: '删除', icon: 'trash-2', danger: true, disabled: () => this.sheets.length <= 1, run: () => this.deleteSheet(i) },
            { label: '重命名', icon: 'pencil', run: () => this.renameSheet(i) },
            { label: '创建副本', icon: 'copy', run: () => this.duplicateSheet(i) },
            '-',
            { label: '左移', icon: 'arrow-left', disabled: () => i === 0, run: () => this.moveSheet(i, i - 1) },
            { label: '右移', icon: 'arrow-right', disabled: () => i >= this.sheets.length - 1, run: () => this.moveSheet(i, i + 1) },
            '-',
            { label: '工作表标签颜色', icon: 'palette', submenu: [...TAB_COLORS.map(c => ({ label: c, swatch: c, run: () => this.setSheetColor(i, c) })), '-', { label: '无颜色', run: () => this.setSheetColor(i, null) }] },
        ]
    },

    // ---------- 名称框跳转 ----------
    gotoName(text) {
        const t = text.trim()
        let sh = this.book.active
        let ref = t
        const m = /^(?:'([^']+)'|([^!]+))!(.+)$/.exec(t)
        if (m) {
            const i = this.sheets.findIndex(s => s.name.toLowerCase() === (m[1] ?? m[2]).toLowerCase())
            if (i < 0) return toast('找不到工作表：' + (m[1] ?? m[2]), 'warn')
            sh = i
            ref = m[3]
        }
        const g = parseRange(ref.replace(/\$/g, ''))
        if (!g) return toast('无效的引用：' + t, 'warn')
        if (sh !== this.book.active) this.switchSheet(sh)
        if (g.r1 === g.r2 && g.c1 === g.c2) this.selectCell(g.r1, g.c1)
        else this.selectRange(g, { active: { r: g.r1, c: g.c1 } })
    },

    bumpFont(d) {
        const cur = this.curStyle()?.sz ?? DEFAULT_SZ
        const next = d > 0 ? SIZES.find(s => s > cur) ?? cur + 4 : [...SIZES].reverse().find(s => s < cur) ?? Math.max(6, cur - 1)
        this.applyStyle({ sz: next }, '字号')
    },
    stepDecimal(d) {
        const v = this.value(this.sel.r, this.sel.c)
        const fmt = stepDecimals(this.curStyle()?.fmt, d, typeof v === 'number' ? v : 0)
        this.applyStyle({ fmt }, d > 0 ? '增加小数位数' : '减少小数位数')
    },

    // ---------- 边框 / 求和 / 冻结 ----------
    borderItems() {
        const B = (kind, label, ic) => ({ label, icon: ic, run: () => this.applyBorder(kind, `${this.borderStyle ?? 'thin'} ${this.borderColor ?? '#000000'}`) })
        return [
            B('bottom', '下框线', 'panel-bottom'), B('top', '上框线', 'panel-top'), B('left', '左框线', 'panel-left'), B('right', '右框线', 'panel-right'),
            '-',
            B('all', '所有框线', 'grid-2x2'), B('outer', '外侧框线', 'square'), B('thick-outer', '粗外侧框线', 'square-dashed-bottom'), B('inner', '内部框线', 'grid-2x2-plus'),
            B('inside-h', '内部横框线', 'rows-2'), B('inside-v', '内部竖框线', 'columns-2'),
            '-',
            B('none', '无框线', 'square-dashed'),
            '-',
            { label: '线型', submenu: [['thin', '细线'], ['medium', '中等'], ['thick', '粗线'], ['dashed', '虚线'], ['dotted', '点线'], ['double', '双线']].map(([v, l]) => ({ label: l, checked: () => (this.borderStyle ?? 'thin') === v, run: () => { this.borderStyle = v } })) },
            { label: '线条颜色', submenu: ['#000000', '#64748b', '#2563eb', '#dc2626', '#16a34a', '#f59e0b'].map(c => ({ label: c, swatch: c, checked: () => (this.borderColor ?? '#000000') === c, run: () => { this.borderColor = c } })) },
        ]
    },
    autoSumItems() {
        const f = fn => () => this.autoSum(fn)
        return [
            { label: '求和', icon: 'sigma', key: 'Alt+=', run: f('SUM') },
            { label: '平均值', run: f('AVERAGE') }, { label: '计数', run: f('COUNT') },
            { label: '最大值', run: f('MAX') }, { label: '最小值', run: f('MIN') },
            '-',
            { label: '其他函数…', icon: 'square-function', run: () => this.insertFunctionDialog() },
        ]
    },
    // 自动求和：选区下方 / 右侧空单元格写入公式；单个单元格时向上 / 向左找数据区域
    autoSum(fn = 'SUM') {
        const g = this.range, sh = this.sheet
        const isNum = (r, c) => typeof this.value(r, c) === 'number'
        if (g.r1 === g.r2 && g.c1 === g.c2) {
            const r = g.r1, c = g.c1
            let r0 = r - 1
            while (r0 >= 0 && isNum(r0, c)) r0--
            if (r0 < r - 1) return this.setInput(r, c, `=${fn}(${rangeName({ r1: r0 + 1, c1: c, r2: r - 1, c2: c })})`)
            let c0 = c - 1
            while (c0 >= 0 && isNum(r, c0)) c0--
            if (c0 < c - 1) return this.setInput(r, c, `=${fn}(${rangeName({ r1: r, c1: c0 + 1, r2: r, c2: c - 1 })})`)
            return this.startEdit({ mode: 'enter', text: `=${fn}()` })
        }
        const u = this.clampUsed(g)
        this.batch('自动求和', set => {
            // 每列在选区下方写入
            for (let c = u.c1; c <= u.c2; c++) {
                const target = u.r2 + 1
                const old = sh.get(target, c)
                if (old?.v != null || old?.f) continue
                set(target, c, makeCell(null, `${fn}(${rangeName({ r1: u.r1, c1: c, r2: u.r2, c2: c })})`, old?.s ?? sh.get(u.r2, c)?.s ?? null))
            }
        })
    },
    freezeItems() {
        const { r, c } = this.sel
        const fz = this.sheet.meta.freeze
        return [
            { label: `冻结至 ${rangeName({ r1: r, c1: c, r2: r, c2: c })} 左上方`, disabled: () => !r && !c, run: () => this.setFreeze(r, c) },
            { label: '冻结首行', run: () => this.setFreeze(1, 0) },
            { label: '冻结首列', run: () => this.setFreeze(0, 1) },
            { label: '取消冻结', disabled: () => !fz.r && !fz.c, run: () => this.setFreeze(0, 0) },
        ]
    },
}

export { numberInput, parseCell, FUNC_INFO }
