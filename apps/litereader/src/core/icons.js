import * as L from 'lucide'

const cache = new Map()

// icon('play', 18) -> SVGElement；名称使用 kebab-case 或 PascalCase
export function icon(name, size = 18, attrs = {}) {
    const key = name.includes('-') || name[0] === name[0].toLowerCase()
        ? name.split('-').map(s => s[0].toUpperCase() + s.slice(1)).join('')
        : name
    let node = cache.get(key)
    if (!node) {
        node = L[key] ?? L.CircleHelp
        cache.set(key, node)
    }
    const el = L.createElement(node, { width: size, height: size, 'stroke-width': 1.9, ...attrs })
    el.classList.add('icon')
    return el
}

export const iconHTML = (name, size) => icon(name, size).outerHTML
