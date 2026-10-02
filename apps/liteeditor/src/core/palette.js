// 命令面板（Ctrl+Shift+P / F1）：搜索当前编辑器的全部菜单命令与全局命令
import { h } from './dom.js'
import { icon } from './icons.js'
import { prettyKey } from './menu.js'

const val = v => typeof v === 'function' ? v() : v

// 展开菜单树为命令列表：{ label, path, icon, key, run }
export function flattenMenus(menus, trail = [], out = [], depth = 0) {
    for (const m of menus) {
        let items
        try { items = val(m.items ?? m.submenu) ?? [] } catch { continue }
        const path = m.label ? [...trail, val(m.label)] : trail
        for (const it of items) {
            if (!it || typeof it !== 'object' || it.header || it.el) continue
            let disabled = false
            try { disabled = !!val(it.disabled) } catch { /* ignore */ }
            if (disabled) continue
            if (it.submenu) { if (depth < 3) flattenMenus([it], path, out, depth + 1); continue }
            if (!it.run) continue
            const label = String(val(it.label) ?? '')
            if (!label) continue
            out.push({ label, path: path.join(' › '), icon: it.icon, key: it.key, run: it.run })
        }
    }
    return out
}

// 子序列模糊匹配：连续命中与词首命中得分更高，返回 null 表示不匹配
function score(text, q) {
    if (!q) return 0
    const t = text.toLowerCase()
    const direct = t.indexOf(q)
    if (direct >= 0) return 1000 - direct * 2 - t.length * 0.1
    let s = 0, i = 0, run = 0
    for (const c of q) {
        const j = t.indexOf(c, i)
        if (j < 0) return null
        run = j === i ? run + 1 : 0
        s += 10 + run * 5 - (j - i)
        i = j + 1
    }
    return s - t.length * 0.1
}

let openEl = null
export function openPalette(commands, { placeholder = '输入命令名称…' } = {}) {
    if (openEl) return
    const input = h('input.pal-input', { placeholder, spellcheck: false })
    const list = h('div.pal-list')
    const mask = h('div.modal-mask.pal-mask', h('div.pal', h('div.pal-head', icon('search', 17), input), list))
    let shown = [], sel = 0

    const close = () => {
        if (!openEl) return
        openEl = null
        document.removeEventListener('keydown', onKey, true)
        mask.classList.remove('show')
        setTimeout(() => mask.remove(), 180)
    }
    const run = c => {
        close()
        // 等面板关闭后再执行，避免命令中的对话框与焦点冲突
        if (c) setTimeout(() => c.run(), 0)
    }
    const render = () => {
        const q = input.value.trim().toLowerCase()
        shown = commands
            .map(c => ({ c, s: score(c.label + ' ' + c.path, q) }))
            .filter(x => x.s != null)
            .sort((a, b) => b.s - a.s)
            .slice(0, 80)
            .map(x => x.c)
        sel = Math.min(sel, Math.max(0, shown.length - 1))
        list.replaceChildren(...(shown.length ? shown.map((c, i) => h('div.pal-item' + (i === sel ? '.active' : ''), {
            onmousemove: () => { if (sel !== i) { sel = i; mark() } },
            onclick: () => run(c),
        },
        c.icon ? icon(c.icon, 16) : h('span.pal-icon-space'),
        h('span.pal-label', c.label),
        c.path ? h('span.pal-path', c.path) : null,
        c.key ? h('span.pal-key', prettyKey(c.key)) : null)) : [h('div.pal-empty', '没有匹配的命令')]))
    }
    const mark = () => {
        list.querySelectorAll('.pal-item').forEach((el, i) => el.classList.toggle('active', i === sel))
        list.children[sel]?.scrollIntoView({ block: 'nearest' })
    }
    const onKey = e => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close() }
        else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault()
            if (shown.length) { sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + shown.length) % shown.length; mark() }
        } else if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); e.stopPropagation(); run(shown[sel]) }
    }
    input.addEventListener('input', () => { sel = 0; render() })
    mask.addEventListener('pointerdown', e => { if (e.target === mask) close() })
    document.addEventListener('keydown', onKey, true)
    document.body.append(mask)
    openEl = mask
    render()
    requestAnimationFrame(() => { mask.classList.add('show'); input.focus() })
}
