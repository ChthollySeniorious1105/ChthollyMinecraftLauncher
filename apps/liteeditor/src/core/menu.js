import { h } from './dom.js'
import { icon } from './icons.js'

// 菜单系统：支持子菜单、快捷键提示、禁用 / 勾选状态、右键菜单
// item: { label, icon, key, run, disabled, checked, danger, submenu: items | () => items } | '-'
// disabled / checked / label 可以是函数，渲染时求值

const val = (v, ...a) => typeof v === 'function' ? v(...a) : v
let active = null

export function closeMenu() {
    if (!active) return
    const a = active
    active = null
    document.removeEventListener('pointerdown', a.onDown, true)
    document.removeEventListener('keydown', a.onKey, true)
    window.removeEventListener('blur', closeMenu)
    for (const el of a.panels) el.remove()
    a.onClose?.()
}
export const menuOpen = () => !!active
export const menuAnchor = () => active?.anchor ?? null

function place(el, x, y, { alignRight = false, flipX = null } = {}) {
    document.body.append(el)
    const r = el.getBoundingClientRect()
    let left = alignRight ? x - r.width : x
    if (left + r.width > innerWidth - 6) left = flipX != null ? flipX - r.width : innerWidth - r.width - 6
    left = Math.max(6, left)
    let top = y
    if (top + r.height > innerHeight - 6) top = Math.max(6, innerHeight - r.height - 6)
    el.style.left = left + 'px'
    el.style.top = top + 'px'
    requestAnimationFrame(() => el.classList.add('show'))
}

function renderPanel(items, depth) {
    const panel = h('div.cmenu', { dataset: { depth } })
    let openSub = null
    const closeSub = () => {
        if (!openSub) return
        const idx = active.panels.indexOf(openSub.panel)
        for (const p of active.panels.splice(idx)) p.remove()
        openSub.item.classList.remove('open')
        openSub = null
    }
    for (const it of val(items) ?? []) {
        if (it == null || it === false) continue
        if (it === '-') { panel.append(h('div.cmenu-sep')); continue }
        if (it.header) { panel.append(h('div.cmenu-header', it.header)); continue }
        if (it.el) { panel.append(it.el); continue }
        const disabled = !!val(it.disabled)
        const checked = val(it.checked)
        const hasSub = !!it.submenu
        const lead = checked != null
            ? (checked ? icon('check', 15) : h('span.cmenu-icon-space'))
            : it.icon ? icon(it.icon, 15) : h('span.cmenu-icon-space')
        const row = h('div.cmenu-item' + (disabled ? '.disabled' : '') + (it.danger ? '.danger' : '') + (checked ? '.checked' : ''),
            { title: it.title ?? '' },
            lead,
            h('span.cmenu-label', val(it.label)),
            it.swatch ? h('span.cmenu-swatch', { style: { background: it.swatch } }) : null,
            it.key ? h('span.cmenu-key', prettyKey(it.key)) : null,
            hasSub ? icon('chevron-right', 14) : null)
        row.addEventListener('mouseenter', () => {
            if (openSub && openSub.item !== row) closeSub()
            if (hasSub && !disabled && !openSub) {
                const sub = renderPanel(it.submenu, depth + 1)
                active.panels.push(sub)
                openSub = { item: row, panel: sub }
                row.classList.add('open')
                const r = row.getBoundingClientRect()
                place(sub, r.right - 2, r.top - 5, { flipX: r.left + 2 })
            }
        })
        row.addEventListener('click', e => {
            e.stopPropagation()
            if (disabled || hasSub) return
            closeMenu()
            it.run?.()
        })
        panel.append(row)
    }
    return panel
}

// 打开菜单：anchor 为锚点元素（下拉），或给出 x / y（右键菜单）
export function openMenu(items, { anchor, x, y, align = 'start', onClose } = {}) {
    closeMenu()
    const onDown = e => {
        if (active.panels.some(p => p.contains(e.target))) return
        if (anchor && anchor.contains(e.target)) return
        closeMenu()
    }
    const onKey = e => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); closeMenu() } }
    active = { panels: [], anchor, onDown, onKey, onClose }
    const root = renderPanel(items, 0)
    active.panels.push(root)
    if (anchor) {
        const r = anchor.getBoundingClientRect()
        place(root, align === 'end' ? r.right : r.left, r.bottom + 4, { alignRight: align === 'end' })
    } else place(root, x, y)
    setTimeout(() => {
        if (!active) return
        document.addEventListener('pointerdown', onDown, true)
        document.addEventListener('keydown', onKey, true)
        window.addEventListener('blur', closeMenu)
    })
    return root
}

export function contextMenu(e, items) {
    e.preventDefault()
    e.stopPropagation()
    openMenu(items, { x: e.clientX, y: e.clientY })
}

// 下拉按钮
export function dropdown(content, items, { title, cls = '', align = 'start' } = {}) {
    const b = h('button.tb-menu' + cls, { title: title ?? '' }, content, icon('chevron-down', 13))
    b.addEventListener('click', () => {
        if (menuAnchor() === b) return closeMenu()
        b.classList.add('open')
        openMenu(items, { anchor: b, align, onClose: () => b.classList.remove('open') })
    })
    return b
}

// ---------- 快捷键 ----------
const CODE_KEYS = {
    Equal: '=', Minus: '-', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Slash: '/', Comma: ',',
    Period: '.', Semicolon: ';', Quote: "'", Backquote: '`', NumpadAdd: '=', NumpadSubtract: '-', Space: 'Space',
}
// 键盘事件 -> 'Ctrl+Shift+Z' 形式
export function keyString(e) {
    let k
    if (/^Key[A-Z]$/.test(e.code)) k = e.code.slice(3)
    else if (/^Digit\d$/.test(e.code)) k = e.code.slice(5)
    else if (/^Numpad\d$/.test(e.code)) k = e.code.slice(6)
    else if (CODE_KEYS[e.code]) k = CODE_KEYS[e.code]
    else if (e.key === ' ') k = 'Space'
    else k = e.key.length === 1 ? e.key.toUpperCase() : e.key
    if (['Control', 'Shift', 'Alt', 'Meta'].includes(k)) return ''
    return [(e.ctrlKey || e.metaKey) && 'Ctrl', e.shiftKey && 'Shift', e.altKey && 'Alt', k].filter(Boolean).join('+')
}
const KEY_NAMES = { ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→', Delete: 'Del', Backspace: '⌫', Escape: 'Esc', Enter: 'Enter', Space: '空格' }
export const prettyKey = k => [].concat(k)[0].split('+').map(p => KEY_NAMES[p] ?? p).join('+')

// 递归收集菜单项中的快捷键：返回 Map<keyString, item>
export function collectKeys(menus, map = new Map()) {
    for (const m of menus) {
        for (const it of val(m.items ?? m.submenu) ?? []) {
            if (!it || typeof it !== 'object') continue
            if (it.submenu) collectKeys([it], map)
            for (const k of [].concat(it.key ?? [])) if (!map.has(k)) map.set(k, it)
            for (const k of [].concat(it.altKey ?? [])) if (!map.has(k)) map.set(k, it)
        }
    }
    return map
}
