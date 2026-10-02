// CML 主题桥（主进程）：读取 CML 启动器写出的 theme.json，监视变化并推送给所有窗口
// 查找顺序：环境变量 CML_THEME_FILE → %APPDATA%\CML\theme.json → 内置默认配色
// 协议见 CML 仓库 docs/THEME_BRIDGE.md；未知字段忽略，解析失败时保持当前配色
import { app, BrowserWindow, ipcMain, nativeTheme } from 'electron'
import path from 'node:path'
import fs from 'node:fs'

export const DEFAULT_THEME = Object.freeze({
    version: 1, id: 'default', name: 'CML 默认', dark: false,
    bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280',
    line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff',
    paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8'],
})
const COLOR_KEYS = ['bg', 'surface', 'panel', 'text', 'muted', 'line', 'field', 'accent', 'accent2', 'onAccent', 'paper', 'ink']
const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i
const hex6 = c => c.length === 4 ? '#' + [...c.slice(1)].map(x => x + x).join('') : c
const color = (v, d) => typeof v === 'string' && HEX.test(v.trim()) ? hex6(v.trim().toLowerCase()) : d

// 合并到默认值上：缺失或格式不对的字段沿用默认（按明暗选择合理的回退）
export function normalizeTheme(raw) {
    if (!raw || typeof raw !== 'object') return null
    const t = { ...DEFAULT_THEME, version: Number(raw.version) || 1, dark: !!raw.dark }
    t.id = typeof raw.id === 'string' ? raw.id : 'custom'
    t.name = typeof raw.name === 'string' ? raw.name : t.id
    const fallback = t.dark
        ? { bg: '#14161c', surface: '#1c1f27', panel: '#1c1f27', text: '#e6e9f2', muted: '#9aa3b2', line: '#2c313c', field: '#252a34', paper: '#1a1d24', ink: '#d9dde6' }
        : {}
    for (const k of COLOR_KEYS) t[k] = color(raw[k], fallback[k] ?? DEFAULT_THEME[k])
    const art = Array.isArray(raw.art) ? raw.art.map(c => color(c, null)).filter(Boolean) : []
    t.art = art.length ? art.slice(0, 3) : [t.accent, t.accent2]
    return Object.freeze(t)
}

export const themeFiles = () => {
    const list = []
    if (process.env.CML_THEME_FILE) list.push(path.resolve(process.env.CML_THEME_FILE))
    list.push(path.join(app.getPath('appData'), 'CML', 'theme.json'))
    return [...new Set(list)]
}

function readFile(file) {
    try { return normalizeTheme(JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''))) } catch { return null }
}

let current = DEFAULT_THEME
let started = false
const listeners = new Set()

export const getTheme = () => current
export function onThemeChange(fn) { listeners.add(fn); return () => listeners.delete(fn) }

function apply(t, { force = false } = {}) {
    if (!force && JSON.stringify(t) === JSON.stringify(current)) return
    current = t
    nativeTheme.themeSource = t.dark ? 'dark' : 'light'
    for (const w of BrowserWindow.getAllWindows()) {
        if (!w.isDestroyed()) w.webContents.send('cml-theme:changed', t)
    }
    for (const fn of listeners) { try { fn(t) } catch (e) { console.error(e) } }
}

// 第一份存在的主题文件为准：解析失败（例如正在写入）时保持当前配色；全都不存在时回到默认配色
function reload() {
    const f = themeFiles().find(x => fs.existsSync(x))
    if (!f) return apply(DEFAULT_THEME)
    const t = readFile(f)
    if (t) apply(t)
}

function watch() {
    let timer = null
    const kick = () => { clearTimeout(timer); timer = setTimeout(reload, 150) }
    for (const f of themeFiles()) {
        const dir = path.dirname(f), base = path.basename(f).toLowerCase()
        try {
            // 监视目录：CML 先写 theme.json.tmp 再重命名，直接监视文件会在替换后失效
            const w = fs.watch(dir, { persistent: false }, (_ev, name) => {
                if (!name || String(name).toLowerCase().startsWith(base)) kick()
            })
            w.on('error', () => {})
        } catch {
            // 目录尚不存在（未安装 / 未运行过 CML）：退化为轮询
            fs.watchFile(f, { persistent: false, interval: 2000 }, kick)
        }
    }
}

// 在 app ready 之前或之后调用均可；需在创建窗口前调用以避免首帧闪烁
export function initThemeBridge() {
    if (started) return current
    started = true
    reload()
    apply(current, { force: true })
    ipcMain.on('cml-theme:get', e => { e.returnValue = current })
    watch()
    return current
}
