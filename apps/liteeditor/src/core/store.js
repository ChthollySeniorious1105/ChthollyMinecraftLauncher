// 本地持久化：设置、最近打开
const KEY_SETTINGS = 'le.settings'
const KEY_RECENT = 'le.recent'

const read = (k, d) => {
    try { return JSON.parse(localStorage.getItem(k)) ?? d } catch { return d }
}
const write = (k, v) => {
    try { localStorage.setItem(k, JSON.stringify(v)) } catch { /* 空间不足时忽略 */ }
}

export const DEFAULT_SETTINGS = {
    animations: true,
    uiScale: 1,
    autosave: false,        // 已保存过的原生格式文件自动保存
    autosaveInterval: 60,   // 秒
    historyLimit: 80,       // 撤销步数
    imageCheckerboard: true,
    geoGrid: true,
    geoSnap: true,
    docFont: 'serif',
    docFontSize: 16,
    docSpellcheck: false,
    sheetFormulaBar: true,
    slideRatio: '16:9',
}

let settings = { ...DEFAULT_SETTINGS, ...read(KEY_SETTINGS, {}) }
// 旧版内置主题的设置项（主题现在由 CML 启动器决定）
for (const k of ['theme', 'lastDark', 'lastLight']) delete settings[k]
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

// ---------- 编辑器私有偏好（画笔大小、最近颜色等） ----------
export const getPref = (ns, d = {}) => ({ ...d, ...read('le.pref.' + ns, {}) })
export const setPref = (ns, v) => write('le.pref.' + ns, v)
