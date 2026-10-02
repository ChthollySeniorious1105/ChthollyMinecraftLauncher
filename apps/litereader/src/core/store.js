// 本地持久化：设置、最近打开、阅读进度
const KEY_SETTINGS = 'lr.settings'
const KEY_RECENT = 'lr.recent'
const KEY_PROGRESS = 'lr.progress'

const read = (k, d) => {
    try { return JSON.parse(localStorage.getItem(k)) ?? d } catch { return d }
}
const write = (k, v) => {
    try { localStorage.setItem(k, JSON.stringify(v)) } catch { /* 空间不足时忽略 */ }
}

export const DEFAULT_SETTINGS = {
    readerPaper: 'theme', // 阅读区纸张：默认跟随 CML 主题的 paper / ink
    readerFont: 'serif',
    readerFontSize: 19,
    readerLineHeight: 1.8,
    readerWidth: 760,
    readerMargin: 48,
    readerFlow: 'paginated',
    readerJustify: true,
    readerColumns: 2,
    pdfInvert: false,
    volume: 0.8,
    audioLoop: 'all',
    audioShuffle: false,
    visualizer: 'bars',
    videoSpeed: 1,
    imageFit: 'contain',
    slideshowInterval: 4,
    animations: true,
    rememberProgress: true,
    uiScale: 1,
}

let settings = { ...DEFAULT_SETTINGS, ...read(KEY_SETTINGS, {}) }
// 旧版内置主题的设置项（主题现在由 CML 启动器决定）
for (const k of ['theme', 'lastDark', 'lastLight', 'followTheme']) delete settings[k]
const listeners = new Set()

export const getSettings = () => settings
export const get = k => settings[k]
export function set(k, v) {
    if (typeof k === 'object') settings = { ...settings, ...k }
    else settings = { ...settings, [k]: v }
    write(KEY_SETTINGS, settings)
    for (const fn of listeners) fn(settings, k)
}
export function onSettings(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
}
export function resetSettings() {
    settings = { ...DEFAULT_SETTINGS }
    write(KEY_SETTINGS, settings)
    for (const fn of listeners) fn(settings, null)
}

// ---------- 最近打开 ----------
export const getRecent = () => read(KEY_RECENT, [])
export function addRecent(item) {
    const list = getRecent().filter(r => r.path !== item.path)
    list.unshift({ ...item, time: Date.now() })
    write(KEY_RECENT, list.slice(0, 60))
}
export function removeRecent(path) {
    write(KEY_RECENT, getRecent().filter(r => r.path !== path))
}
export const clearRecent = () => write(KEY_RECENT, [])

// ---------- 阅读 / 播放进度 ----------
export function getProgress(key) {
    if (!key) return null
    return read(KEY_PROGRESS, {})[key] ?? null
}
export function setProgress(key, value) {
    if (!key || !settings.rememberProgress) return
    const all = read(KEY_PROGRESS, {})
    all[key] = { ...value, t: Date.now() }
    const keys = Object.keys(all)
    if (keys.length > 500) {
        keys.sort((a, b) => all[a].t - all[b].t).slice(0, keys.length - 500).forEach(k => delete all[k])
    }
    write(KEY_PROGRESS, all)
}
