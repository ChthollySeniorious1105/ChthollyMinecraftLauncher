// 电子表格对话框：插入函数、条件格式、单元格格式、行高列宽、分列
import { h, fill, toast, dialog, formDialog, colorInput } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { FUNC_INFO } from './funcinfo.js'
import { FUNCS } from './formula/functions.js'
import { CF_TYPES, CF_PRESETS, NUM_FORMATS, FONTS, SIZES, BORDER_STYLES, display, fontFamily } from './format.js'
import { fontOptions } from '../../core/fonts.js'
import { rangeName, parseRange } from './addr.js'
import { makeCell } from './model.js'
import { parseInput } from './editing.js'

export const Dialogs = {
    funcExists(n) { return !!FUNCS[n] },

    // 插入函数：搜索、说明、参数提示
    async insertFunctionDialog() {
        const names = Object.keys(FUNCS).sort()
        const q = h('input.input.small', { placeholder: '搜索函数（名称或说明）' })
        const list = h('div.sh-fn-list')
        const desc = h('div.sh-fn-desc')
        let chosen = null
        const pick = n => {
            chosen = n
            for (const el of list.children) el.classList.toggle('active', el.dataset.n === n)
            const info = FUNC_INFO[n]
            fill(desc, h('div.sh-fn-sig', info?.[0] ?? `${n}(…)`), h('div', info?.[1] ?? ''))
        }
        const render = () => {
            const t = q.value.trim().toUpperCase()
            const hits = names.filter(n => !t || n.includes(t) || (FUNC_INFO[n]?.[1] ?? '').toUpperCase().includes(t))
            fill(list, hits.map(n => h('div.sh-fn-item', { dataset: { n }, onclick: () => pick(n), ondblclick: () => ok.click() }, h('b', n), h('span', FUNC_INFO[n]?.[1] ?? ''))))
            if (hits.length) pick(hits.includes(chosen) ? chosen : hits[0])
        }
        let ok
        q.addEventListener('input', render)
        q.addEventListener('keydown', e => {
            const i = [...list.children].findIndex(x => x.dataset.n === chosen)
            if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                e.preventDefault()
                const n = list.children[Math.max(0, Math.min(list.children.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))]
                if (n) { pick(n.dataset.n); n.scrollIntoView({ block: 'nearest' }) }
            }
        })
        render()
        const r = await dialog({
            title: '插入函数', width: 520,
            body: h('div.form', q, list, desc),
            actions: [{ label: '取消', value: null }, { label: '插入', primary: true, value: () => chosen }],
            onOpen: m => { ok = m.querySelector('.btn.primary') },
        })
        if (!r) return this.focusGrid()
        if (this.editing) {
            const inp = this.activeEditor()
            const s = inp.selectionStart
            inp.value = inp.value.slice(0, s) + r + '(' + inp.value.slice(inp.selectionEnd)
            inp.setSelectionRange(s + r.length + 1, s + r.length + 1)
            inp.focus()
            this.onEditorInput(inp)
        } else this.startEdit({ mode: 'enter', text: `=${r}(` })
    },

    // 条件格式规则对话框
    async cfDialog(type = 'gt', a) {
        const g = this.clampUsed(this.range)
        const needsA = !['dup', 'unique', 'above', 'below', 'blank'].includes(type)
        const needsB = type === 'between'
        const presets = CF_PRESETS.map(([l], i) => [i, l])
        const r = await formDialog({
            title: '条件格式', width: 460,
            fields: [
                { key: 'range', label: '应用于', value: rangeName(g) },
                { key: 'type', label: '规则', type: 'select', value: type, options: CF_TYPES },
                ...(needsA || type === 'formula' ? [{ key: 'a', label: type === 'formula' ? '公式' : type === 'top' || type === 'bottom' ? '项数' : '值', value: a ?? (type === 'formula' ? `=${rangeName({ r1: g.r1, c1: g.c1, r2: g.r1, c2: g.c1 })}>100` : ''), placeholder: type === 'formula' ? '以活动单元格为准的相对公式' : '' }] : []),
                ...(needsB ? [{ key: 'b', label: '到', value: '' }] : []),
                { key: 'preset', label: '格式', type: 'select', value: 0, options: [...presets, [-1, '自定义…']] },
                { key: 'fill', label: '填充色', type: 'color', value: CF_PRESETS[0][1].fill ?? '#fde2e4' },
                { key: 'color', label: '文字颜色', type: 'color', value: CF_PRESETS[0][1].color ?? '#9c0006' },
                { key: 'bold', label: '加粗', type: 'check', value: false },
                { type: 'note', label: '选择“自定义”时使用下方的颜色设置。' },
            ],
        })
        if (!r) return
        const range = parseRange(r.range)
        if (!range) return toast('应用范围无效', 'error')
        let style = r.preset >= 0 ? CF_PRESETS[r.preset][1] : { fill: r.fill, color: r.color }
        if (r.bold) style = { ...style, b: true }
        const num = v => v !== '' && v != null && Number.isFinite(+v) ? +v : v
        const rule = { id: Math.random().toString(36).slice(2, 9), range, type: r.type, style }
        if (r.a != null) rule.a = r.type === 'formula' ? String(r.a).replace(/^=/, '') : num(r.a)
        if (r.b != null) rule.b = num(r.b)
        if ((r.type === 'top' || r.type === 'bottom') && rule.a == null) rule.a = 10
        this.sheet.setMeta({ cf: [...this.sheet.meta.cf, rule] })
        this.cfCache.clear()
        this.invalidate()
        this.commit('条件格式')
    },

    async cfManager() {
        const sh = this.sheet
        let rules = [...sh.meta.cf]
        const listEl = h('div.e-list.sh-cf-list')
        const label = rule => {
            const t = CF_TYPES.find(x => x[0] === rule.type)?.[1] ?? { bar: '数据条', scale: '色阶' }[rule.type] ?? rule.type
            return `${t}${rule.a != null ? '：' + rule.a : ''}${rule.b != null ? ' ~ ' + rule.b : ''}`
        }
        const render = () => fill(listEl, rules.map((rule, i) => h('div.e-list-item',
            h('span.sh-cf-swatch', { style: { background: rule.style?.fill ?? rule.color ?? (rule.colors ? `linear-gradient(90deg, ${rule.colors.join(',')})` : '#fff'), color: rule.style?.color ?? '#111' } }, 'Aa'),
            h('span.li-name', label(rule)),
            h('span.li-sub', rangeName(rule.range)),
            h('button.icon-btn', { title: '上移', onclick: () => { if (i) { [rules[i - 1], rules[i]] = [rules[i], rules[i - 1]]; render() } } }, icon('chevron-up', 14)),
            h('button.icon-btn', { title: '删除', onclick: () => { rules.splice(i, 1); render() } }, icon('trash-2', 14)))))
        render()
        const ok = await dialog({ title: '管理条件格式规则', width: 520, body: listEl })
        if (!ok) return
        sh.setMeta({ cf: rules })
        this.cfCache.clear()
        this.invalidate()
        this.commit('管理条件格式')
    },

    // 设置单元格格式（Ctrl+1）
    async formatCellsDialog() {
        const st = this.curStyle() ?? {}
        const v = this.value(this.sel.r, this.sel.c)
        const sample = h('div.sh-fmt-sample')
        const upd = x => {
            const fmt = x.fmt === 'custom' ? x.custom : x.fmt
            const d = display(typeof v === 'number' ? v : 1234.5678, fmt === 'General' ? null : fmt)
            sample.textContent = '示例：' + d.text
            sample.style.color = d.color ?? ''
        }
        const known = NUM_FORMATS.some(f => f[0] === (st.fmt ?? 'General'))
        const r = await formDialog({
            title: '设置单元格格式', width: 480,
            onChange: upd,
            fields: [
                { key: 'fmt', label: '数字格式', type: 'select', value: known ? st.fmt ?? 'General' : 'custom', options: [...NUM_FORMATS.map(([f, l, e]) => [f, `${l}　${e}`]), ['custom', '自定义…']] },
                { key: 'custom', label: '自定义格式', value: st.fmt ?? '', placeholder: '例如 #,##0.00;[Red]-#,##0.00' },
                { key: 'font', label: '字体', type: 'select', value: st.font ?? FONTS[0], options: fontOptions(FONTS.map(f => [f, f]), { fmt: 'name', stackOf: fontFamily, importItem: false, current: st.font }) },
                { key: 'sz', label: '字号', type: 'select', value: st.sz ?? 11, options: SIZES.map(s => [s, String(s)]) },
                { key: 'b', label: '加粗', type: 'check', value: !!st.b },
                { key: 'i', label: '倾斜', type: 'check', value: !!st.i },
                { key: 'color', label: '文字颜色', type: 'color', value: st.color ?? '#1f2328' },
                { key: 'fill', label: '填充颜色', type: 'color', value: st.fill ?? '#ffffff' },
                { key: 'nofill', label: '无填充', type: 'check', value: !st.fill },
                { key: 'ha', label: '水平对齐', type: 'select', value: st.ha ?? '', options: [['', '常规'], ['left', '靠左'], ['center', '居中'], ['right', '靠右']] },
                { key: 'va', label: '垂直对齐', type: 'select', value: st.va ?? 'middle', options: [['top', '靠上'], ['middle', '居中'], ['bottom', '靠下']] },
                { key: 'wrap', label: '自动换行', type: 'check', value: !!st.wrap },
                { key: 'indent', label: '缩进', type: 'number', value: st.indent ?? 0, min: 0, max: 15 },
            ],
        })
        if (!r) return this.focusGrid()
        const fmt = r.fmt === 'custom' ? r.custom : r.fmt
        this.applyStyle({
            fmt: fmt === 'General' || !fmt ? null : fmt, font: r.font, sz: Number(r.sz), b: r.b, i: r.i,
            color: r.color === '#1f2328' ? null : r.color, fill: r.nofill ? null : r.fill, ha: r.ha || null, va: r.va === 'middle' ? null : r.va,
            wrap: r.wrap, indent: r.indent || null,
        }, '设置单元格格式')
        this.focusGrid()
        void sample
    },

    async sizeDialog(kind) {
        const g = this.range
        const cur = kind === 'row' ? this.sheet.rowHeight(g.r1) : this.sheet.colWidth(g.c1)
        const r = await formDialog({ title: kind === 'row' ? '行高' : '列宽', fields: [{ key: 'v', label: kind === 'row' ? '行高' : '列宽', type: 'number', value: cur, min: 2, max: 2000, suffix: '像素' }] })
        if (!r) return
        if (kind === 'row') this.setSize('row', g.r1, Math.min(g.r2, g.r1 + 100000), r.v)
        else this.setSize('col', g.c1, Math.min(g.c2, g.c1 + 16383), r.v)
    },

    // 分列：按分隔符拆分选中列
    async textToColumns() {
        const g = this.clampUsed(this.range)
        if (g.c1 !== g.c2) return toast('分列一次只能处理一列', 'warn')
        const r = await formDialog({
            title: '分列', fields: [
                { key: 'sep', label: '分隔符', type: 'select', value: ',', options: [[',', '逗号 ,'], ['\t', '制表符'], [';', '分号 ;'], [' ', '空格'], ['、', '顿号 、'], ['|', '竖线 |'], ['custom', '其他…']] },
                { key: 'custom', label: '其他分隔符', value: '' },
                { key: 'merge', label: '连续分隔符视为一个', type: 'check', value: true },
            ],
        })
        if (!r) return
        const sep = r.sep === 'custom' ? r.custom : r.sep
        if (!sep) return
        const sh = this.sheet
        this.batch('分列', set => {
            for (let row = g.r1; row <= g.r2; row++) {
                const v = this.value(row, g.c1)
                if (typeof v !== 'string' || !v.includes(sep)) continue
                let parts = v.split(sep)
                if (r.merge) parts = parts.filter(p => p !== '')
                const style = sh.get(row, g.c1)?.s ?? null
                parts.forEach((p, i) => {
                    const x = parseInput(p.trim())
                    set(row, g.c1 + i, makeCell(x.v, x.f, i === 0 ? style : sh.get(row, g.c1 + i)?.s ?? null))
                })
            }
        })
    },
}

export { colorInput, BORDER_STYLES }
