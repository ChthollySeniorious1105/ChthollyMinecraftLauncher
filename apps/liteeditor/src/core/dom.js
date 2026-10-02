import { icon } from './icons.js'

// 轻量 DOM 构造：h('div.card#id', { onclick, title }, child1, 'text', ...)
export function h(sel, props, ...children) {
    if (props == null || typeof props !== 'object' || props instanceof Node || Array.isArray(props)) {
        if (props != null) children.unshift(props)
        props = {}
    }
    const [, tag = 'div', rest = ''] = /^([a-z0-9-]*)(.*)$/i.exec(sel)
    const el = document.createElement(tag || 'div')
    for (const part of rest.match(/[.#][^.#]+/g) ?? []) {
        if (part[0] === '.') el.classList.add(part.slice(1))
        else el.id = part.slice(1)
    }
    for (const [k, v] of Object.entries(props)) {
        if (v == null || v === false) continue
        if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v)
        else if (k === 'class') el.className += ' ' + v
        else if (k === 'style' && typeof v === 'object') {
            for (const [sk, sv] of Object.entries(v)) {
                if (sv == null) continue
                if (sk.startsWith('--')) el.style.setProperty(sk, sv)
                else el.style[sk] = sv
            }
        }
        else if (k === 'dataset') Object.assign(el.dataset, v)
        else if (k === 'html') el.innerHTML = v
        else if (k in el && typeof v !== 'string') el[k] = v
        else el.setAttribute(k, v === true ? '' : v)
    }
    append(el, children)
    return el
}

function append(el, children) {
    for (const c of children.flat(Infinity)) {
        if (c == null || c === false) continue
        el.append(c instanceof Node ? c : String(c))
    }
}

// 图标按钮
export function btn(iconName, title, onclick, extra = {}) {
    const b = h('button.icon-btn', { title, 'aria-label': title, onclick, ...extra }, icon(iconName, extra.size ?? 18))
    return b
}

// 替换子节点，忽略 null / false
export function fill(el, ...children) {
    el.replaceChildren()
    append(el, children)
    return el
}

export function setIcon(button, name, size = 18) {
    button.replaceChildren(icon(name, size))
}

export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))

export function formatBytes(n) {
    if (!Number.isFinite(n)) return '—'
    const u = ['B', 'KB', 'MB', 'GB', 'TB']
    let i = 0
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
    return `${n.toFixed(i && n < 10 ? 1 : 0)} ${u[i]}`
}

export function formatTime(sec) {
    if (!Number.isFinite(sec) || sec < 0) sec = 0
    sec = Math.floor(sec)
    const hh = Math.floor(sec / 3600), mm = Math.floor(sec % 3600 / 60), ss = sec % 60
    const p = v => String(v).padStart(2, '0')
    return hh ? `${hh}:${p(mm)}:${p(ss)}` : `${p(mm)}:${p(ss)}`
}

export function formatDate(ts) {
    const d = new Date(ts)
    const diff = (Date.now() - ts) / 1000
    if (diff < 60) return '刚刚'
    if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`
    if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`
    if (diff < 86400 * 7) return `${Math.floor(diff / 86400)} 天前`
    return d.toLocaleDateString('zh-CN')
}

export const debounce = (fn, ms = 200) => {
    let t
    return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms) }
}

export const throttle = (fn, ms = 100) => {
    let last = 0, t
    return (...a) => {
        const now = performance.now()
        clearTimeout(t)
        if (now - last >= ms) { last = now; fn(...a) }
        else t = setTimeout(() => { last = performance.now(); fn(...a) }, ms - (now - last))
    }
}

export const escapeHTML = s => String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])

// ---------- 提示 ----------
export function toast(message, type = 'info', ms = 2800) {
    const box = document.getElementById('toasts')
    const iconName = { info: 'info', success: 'circle-check', error: 'circle-alert', warn: 'triangle-alert' }[type] ?? 'info'
    const el = h('div.toast.' + type, icon(iconName, 18), h('span', message))
    box.append(el)
    requestAnimationFrame(() => el.classList.add('show'))
    setTimeout(() => {
        el.classList.remove('show')
        setTimeout(() => el.remove(), 300)
    }, ms)
}

// ---------- 弹出菜单 / 面板 ----------
let openPopover = null
export function popover(anchor, content, { align = 'end', side = 'bottom', onClose } = {}) {
    closePopover()
    const pop = h('div.popover', content)
    document.body.append(pop)
    const r = anchor.getBoundingClientRect()
    const pr = pop.getBoundingClientRect()
    let top = side === 'top' ? r.top - pr.height - 8 : r.bottom + 8
    let left = align === 'start' ? r.left : align === 'center' ? r.left + r.width / 2 - pr.width / 2 : r.right - pr.width
    left = clamp(left, 8, innerWidth - pr.width - 8)
    top = clamp(top, 8, innerHeight - pr.height - 8)
    pop.style.left = left + 'px'
    pop.style.top = top + 'px'
    requestAnimationFrame(() => pop.classList.add('show'))
    const onDown = e => {
        if (!pop.contains(e.target) && !anchor.contains(e.target)) closePopover()
    }
    const onKey = e => { if (e.key === 'Escape') closePopover() }
    setTimeout(() => {
        document.addEventListener('pointerdown', onDown, true)
        document.addEventListener('keydown', onKey, true)
    })
    openPopover = {
        el: pop, anchor,
        close() {
            document.removeEventListener('pointerdown', onDown, true)
            document.removeEventListener('keydown', onKey, true)
            pop.remove()
            onClose?.()
        },
    }
    return openPopover
}
export function closePopover() {
    openPopover?.close()
    openPopover = null
}
export const togglePopover = (anchor, build, opts) => {
    if (openPopover?.anchor === anchor) return closePopover()
    return popover(anchor, build(), opts)
}

// 简单菜单：items = [{ label, icon, onclick, checked, danger } | '-']
export function menu(items) {
    return h('div.menu', items.map(it => it === '-' ? h('div.menu-sep') :
        h('button.menu-item' + (it.checked ? '.checked' : '') + (it.danger ? '.danger' : ''), {
            onclick: () => { closePopover(); it.onclick?.() },
        }, it.icon ? icon(it.icon, 16) : h('span.menu-icon-space'), h('span', it.label),
        it.checked ? icon('check', 15) : null, it.hint ? h('span.menu-hint', it.hint) : null)))
}

// ---------- 对话框 ----------
export function prompt({ title, message, placeholder = '', type = 'text', value = '', okText = '确定' }) {
    return new Promise(resolve => {
        const input = h('input.input', { type, placeholder, value })
        const close = v => { mask.classList.remove('show'); setTimeout(() => mask.remove(), 200); resolve(v) }
        const mask = h('div.modal-mask', h('div.modal',
            h('div.modal-title', title),
            message ? h('div.modal-msg', message) : null,
            input,
            h('div.modal-actions',
                h('button.btn', { onclick: () => close(null) }, '取消'),
                h('button.btn.primary', { onclick: () => close(input.value) }, okText))))
        input.addEventListener('keydown', e => {
            if (e.key === 'Enter') close(input.value)
            if (e.key === 'Escape') close(null)
        })
        document.body.append(mask)
        requestAnimationFrame(() => { mask.classList.add('show'); input.focus(); input.select() })
    })
}

// 滑块控件：返回 { el, set(v) }
export function slider({ min = 0, max = 100, step = 1, value = 0, oninput, onchange, label, format }) {
    const input = h('input.range', { type: 'range', min, max, step, value })
    const out = h('span.range-value', format ? format(value) : value)
    const paint = () => {
        const p = (input.value - min) / (max - min) * 100
        input.style.setProperty('--p', p + '%')
        out.textContent = format ? format(Number(input.value)) : input.value
    }
    input.addEventListener('input', () => { paint(); oninput?.(Number(input.value)) })
    input.addEventListener('change', () => onchange?.(Number(input.value)))
    paint()
    const el = label ? h('label.field', h('span.field-label', label), h('div.field-row', input, out)) : input
    return { el, input, set(v) { input.value = v; paint() } }
}

// 分段选择
export function segmented(options, value, onchange) {
    const el = h('div.segmented')
    const render = () => el.replaceChildren(...options.map(([v, label, ic]) =>
        h('button' + (v === value ? '.active' : ''), {
            title: typeof label === 'string' ? label : '',
            onclick: () => { value = v; render(); onchange(v) },
        }, ic ? icon(ic, 15) : null, label ? h('span', label) : null)))
    render()
    return { el, set(v) { value = v; render() } }
}

export function toggle(checked, onchange) {
    const input = h('input', { type: 'checkbox', checked })
    input.addEventListener('change', () => onchange(input.checked))
    return h('label.switch', input, h('span.switch-track', h('span.switch-thumb')))
}

// ---------- 编辑器通用控件 ----------

// 带标题的对话框：body 为任意节点，actions = [{ label, primary, danger, value }]
// value 可以是函数（关闭时求值）。返回 Promise<value>；Esc 返回 null
export function dialog({ title, body, actions = [{ label: '取消', value: null }, { label: '确定', primary: true, value: true }], width = 420, onOpen }) {
    return new Promise(resolve => {
        let done = false
        const close = v => {
            if (done) return
            done = true
            document.removeEventListener('keydown', onKey, true)
            mask.classList.remove('show')
            setTimeout(() => mask.remove(), 200)
            resolve(typeof v === 'function' ? v() : v)
        }
        const onKey = e => {
            if (e.key === 'Escape') { e.stopPropagation(); close(null) }
            if (e.key === 'Enter' && !e.target.closest?.('textarea') && !e.isComposing) {
                const p = actions.find(a => a.primary)
                if (p) { e.preventDefault(); e.stopPropagation(); close(p.value) }
            }
        }
        const mask = h('div.modal-mask', h('div.modal', { style: { width: width + 'px' } },
            title ? h('div.modal-title', title) : null,
            h('div.modal-body', body),
            actions.length ? h('div.modal-actions', actions.map(a =>
                h('button.btn' + (a.primary ? '.primary' : '') + (a.danger ? '.danger' : ''), { onclick: () => close(a.value) }, a.label))) : null))
        document.addEventListener('keydown', onKey, true)
        document.body.append(mask)
        requestAnimationFrame(() => {
            mask.classList.add('show')
            const first = mask.querySelector('input:not([type=range]):not([type=checkbox]):not([type=color]), textarea')
            first?.focus()
            first?.select?.()
            onOpen?.(mask, close)
        })
    })
}

export const confirmDialog = ({ title, message, okText = '确定', danger = false, cancelText = '取消' }) =>
    dialog({ title, body: h('div.modal-msg', message), actions: [{ label: cancelText, value: false }, { label: okText, primary: !danger, danger, value: true }] })
        .then(v => !!v)

// 保存 / 不保存 / 取消，返回 'save' | 'discard' | null
export const unsavedDialog = name => dialog({
    title: '保存更改？',
    body: h('div.modal-msg', `“${name}” 有尚未保存的更改。关闭前是否保存？`),
    actions: [{ label: '取消', value: null }, { label: '不保存', danger: true, value: 'discard' }, { label: '保存', primary: true, value: 'save' }],
})

// 表单对话框
// fields: [{ key, label, type: 'number'|'text'|'textarea'|'select'|'color'|'range'|'check'|'note', value, min, max, step, options: [[v, label]], suffix }]
// onChange(values) 用于实时预览；返回 Promise<values | null>
export function formDialog({ title, fields, okText = '确定', width = 420, onChange, onOpen }) {
    const values = Object.fromEntries(fields.filter(f => f.key).map(f => [f.key, f.value]))
    const emit = () => onChange?.({ ...values })
    const rows = fields.map(f => {
        if (f.type === 'note') return h('div.form-note', f.label)
        const set = v => { values[f.key] = v; emit() }
        let ctl
        if (f.type === 'select') {
            ctl = h('select.input.small', { onchange: e => set(parseLike(e.target.value, f.value)) }, optionEls(f.options, f.value))
        } else if (f.type === 'color') {
            ctl = colorInput(f.value, set).el
        } else if (f.type === 'range') {
            const s = slider({ min: f.min ?? 0, max: f.max ?? 100, step: f.step ?? 1, value: f.value, format: v => v + (f.suffix ?? ''), oninput: set })
            ctl = h('div.form-range', s.el, s.el.nextSibling ?? null)
            ctl.append(h('span.range-value', s.input.value + (f.suffix ?? '')))
            s.input.addEventListener('input', () => { ctl.lastChild.textContent = s.input.value + (f.suffix ?? '') })
        } else if (f.type === 'check') {
            ctl = toggle(!!f.value, set)
        } else if (f.type === 'textarea') {
            ctl = h('textarea.input.textarea', { rows: f.rows ?? 4, placeholder: f.placeholder ?? '', oninput: e => set(e.target.value) })
            ctl.value = f.value ?? ''
        } else {
            ctl = h('input.input.small', {
                type: f.type ?? 'text', value: String(f.value ?? ''), min: f.min, max: f.max, step: f.step, placeholder: f.placeholder ?? '',
                oninput: e => set(f.type === 'number' ? Number(e.target.value) : e.target.value),
            })
            if (f.suffix) ctl = h('div.form-suffix', ctl, h('span', f.suffix))
        }
        return h('label.form-row' + (f.type === 'textarea' ? '.stack' : ''), h('span.form-label', f.label), ctl)
    })
    return dialog({
        title, width,
        body: h('div.form', rows),
        actions: [{ label: '取消', value: null }, { label: okText, primary: true, value: () => ({ ...values }) }],
        onOpen: (mask, close) => { onOpen?.(mask, close); emit() },
    })
}
const parseLike = (s, like) => typeof like === 'number' ? Number(s) : typeof like === 'boolean' ? s === 'true' : s

// 颜色选择：色块 + 原生取色器；返回 { el, set(v), get() }
export function colorInput(value = '#000000', onchange, { title = '颜色' } = {}) {
    const input = h('input', { type: 'color' })
    input.value = normColor(value)
    const swatch = h('span.color-swatch', { style: { background: value } })
    const el = h('label.color-input', { title }, swatch, input)
    input.addEventListener('input', () => { swatch.style.background = input.value; onchange?.(input.value) })
    return {
        el, input,
        set(v) { input.value = normColor(v); swatch.style.background = v },
        get: () => input.value,
    }
}
export function normColor(c) {
    if (!c || c === 'transparent') return '#000000'
    if (/^#[0-9a-f]{6}$/i.test(c)) return c.toLowerCase()
    if (/^#[0-9a-f]{3}$/i.test(c)) return '#' + [...c.slice(1)].map(x => x + x).join('').toLowerCase()
    const ctx = normColor.ctx ??= document.createElement('canvas').getContext('2d')
    ctx.fillStyle = '#000'
    ctx.fillStyle = c
    const v = ctx.fillStyle
    return /^#/.test(v) ? v : '#000000'
}

// 下拉选择：options = [[value, label]]
// options: [[value, label], ...]，也可以包含分组 { group, options: [[value, label], ...] }
const optionEls = (opts, v) => opts.map(o => Array.isArray(o)
    ? h('option', { value: o[0], selected: o[0] === v }, o[1])
    : h('optgroup', { label: o.group }, optionEls(o.options, v)))
export function select(options, value, onchange, { title, width } = {}) {
    const el = h('select.tb-select', { title, style: width ? { width: width + 'px' } : null, onchange: e => onchange?.(parseLike(e.target.value, value)) },
        optionEls(options, value))
    return {
        el,
        set(v) { el.value = String(v) },
        get: () => el.value,
        setOptions(opts, v) { fill(el, optionEls(opts, v)) },
    }
}

// 数字输入
export function numberInput(value, onchange, { min, max, step = 1, width = 64, title, suffix } = {}) {
    const input = h('input.tb-number', { type: 'number', min, max, step, title, style: { width: width + 'px' } })
    input.value = value
    input.addEventListener('change', () => {
        let v = Number(input.value)
        if (!Number.isFinite(v)) v = value
        if (min != null) v = Math.max(min, v)
        if (max != null) v = Math.min(max, v)
        input.value = v
        value = v
        onchange?.(v)
    })
    const el = suffix ? h('span.tb-number-wrap', input, h('span.tb-suffix', suffix)) : input
    return { el, input, set(v) { input.value = v; value = v }, get: () => Number(input.value) }
}

// 带下拉箭头的菜单按钮
export function menuButton(label, items, { icon: ic, title } = {}) {
    const b = h('button.tb-menu', { title: title ?? label }, ic ? icon(ic, 16) : null, label ? h('span', label) : null, icon('chevron-down', 13))
    b.addEventListener('click', () => togglePopover(b, () => menu(typeof items === 'function' ? items() : items), { align: 'start' }))
    return b
}

export const sleep = ms => new Promise(r => setTimeout(r, ms))
export const uid = (p = '') => p + Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-3)
