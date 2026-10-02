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
