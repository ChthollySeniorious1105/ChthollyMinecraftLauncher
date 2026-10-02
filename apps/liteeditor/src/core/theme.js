// 主题：跟随 CML 启动器（主进程 electron/theme-bridge.js 读取并监视 theme.json，经 preload 的 window.cmlTheme 推送）
// 这里只把基础色映射到 CSS 变量，其余派生色仍由 base.css 中的 color-mix 推导
// 主题对象字段：dark bg surface panel text muted line field accent accent2 onAccent paper ink art

export const DEFAULT_THEME = {
    id: 'default', name: 'CML 默认', dark: false,
    bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280',
    line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff',
    paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8'],
}

let current = DEFAULT_THEME

export const currentTheme = () => current

export function themeVars(t) {
    const art = t.art?.length ? t.art : [t.accent, t.accent2]
    return {
        '--bg': t.bg,
        '--surface': t.surface,
        '--text': t.text,
        '--accent': t.accent,
        '--accent-2': t.accent2,
        '--on-accent': t.onAccent,
        '--paper': t.paper,
        '--ink': t.ink,
        '--art-1': art[0],
        '--art-2': art[1] ?? art[0],
        '--art-3': art[2] ?? art[1] ?? art[0],
    }
}

export function applyTheme(t, { fade = false } = {}) {
    t = { ...DEFAULT_THEME, ...t }
    current = t
    const root = document.documentElement
    if (fade) {
        root.classList.add('theme-fade')
        setTimeout(() => root.classList.remove('theme-fade'), 450)
    }
    for (const [k, v] of Object.entries(themeVars(t))) root.style.setProperty(k, v)
    root.dataset.theme = t.id
    root.dataset.scheme = t.dark ? 'dark' : 'light'
    root.style.colorScheme = t.dark ? 'dark' : 'light'
    window.lite?.win.setBackground?.(t.bg)
    window.dispatchEvent(new CustomEvent('themechange', { detail: t }))
    return t
}

// 启动时同步取一次，之后跟随 CML 实时换色
export function initTheme() {
    applyTheme(window.cmlTheme?.get() ?? DEFAULT_THEME)
    window.cmlTheme?.onChange(t => applyTheme(t, { fade: true }))
}

export const THEME_HINT = '主题跟随 CML 启动器，在 CML 设置 → 外观 中切换'
