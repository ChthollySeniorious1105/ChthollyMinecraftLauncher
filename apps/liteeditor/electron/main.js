import { app, BrowserWindow, ipcMain, dialog, protocol, shell, Menu } from 'electron'
import { registerCapture, registerHotkeys, unregisterHotkeys } from './capture.js'
import { registerFonts, fontDir, userFontCSS } from './fonts.js'
import { initThemeBridge, getTheme, onThemeChange } from './theme-bridge.js'
import path from 'node:path'
import fs from 'node:fs'
import fsp from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { Readable } from 'node:stream'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
// LITE_DIST 允许冒烟测试使用独立的构建目录
const DIST = path.resolve(process.env.LITE_DIST ?? path.join(__dirname, '..', 'dist'))
const PUBLIC = path.join(__dirname, '..', 'public')
const DEV_URL = process.env.VITE_DEV_SERVER_URL
// 由 CML 的共享 Electron 运行时以 `electron.exe <app 目录>` 启动：显式固定应用名、数据目录与任务栏身份，
// 保持与独立安装版相同的 %APPDATA%\LiteEditor，并让单实例锁按应用区分
app.setName('LiteEditor')
app.setPath('userData', path.join(app.getPath('appData'), 'LiteEditor'))
if (process.platform === 'win32') app.setAppUserModelId('com.liteeditor.app')
// 冒烟测试使用独立的用户数据目录，避免多个实例争用同一份 localStorage
if (process.env.LITE_USERDATA) app.setPath('userData', path.resolve(process.env.LITE_USERDATA))
const STATE_FILE = () => path.join(app.getPath('userData'), 'window-state.json')

const MIME = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm',
    '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.gif': 'image/gif', '.webp': 'image/webp', '.bmp': 'image/bmp', '.ico': 'image/x-icon', '.avif': 'image/avif',
    '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf',
    '.mp4': 'video/mp4', '.m4v': 'video/mp4', '.webm': 'video/webm', '.mkv': 'video/x-matroska', '.mov': 'video/quicktime', '.ogv': 'video/ogg',
    '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg', '.oga': 'audio/ogg', '.opus': 'audio/ogg', '.flac': 'audio/flac', '.m4a': 'audio/mp4', '.aac': 'audio/aac',
    '.sf2': 'application/octet-stream', '.sf3': 'application/octet-stream', '.mid': 'audio/midi', '.midi': 'audio/midi',
}
const mimeOf = p => MIME[path.extname(p).toLowerCase()] ?? 'application/octet-stream'

protocol.registerSchemesAsPrivileged([
    { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
    { scheme: 'media', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true, bypassCSP: true } },
])

// 支持 Range 请求，音视频可以任意跳转
async function serveFile(filePath, request) {
    let stat
    try { stat = await fsp.stat(filePath) } catch { return new Response('Not Found', { status: 404 }) }
    if (!stat.isFile()) return new Response('Not Found', { status: 404 })
    const size = stat.size
    const headers = { 'Content-Type': mimeOf(filePath), 'Accept-Ranges': 'bytes', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-cache' }
    const m = /bytes=(\d*)-(\d*)/.exec(request?.headers.get('range') ?? '')
    if (m && (m[1] || m[2])) {
        let start = m[1] ? Number(m[1]) : size - Number(m[2])
        let end = m[1] && m[2] ? Number(m[2]) : size - 1
        start = Math.max(0, start); end = Math.min(end, size - 1)
        if (start >= size || start > end) return new Response(null, { status: 416, headers: { ...headers, 'Content-Range': `bytes */${size}` } })
        return new Response(Readable.toWeb(fs.createReadStream(filePath, { start, end })), {
            status: 206, headers: { ...headers, 'Content-Length': String(end - start + 1), 'Content-Range': `bytes ${start}-${end}/${size}` },
        })
    }
    return new Response(Readable.toWeb(fs.createReadStream(filePath)), { status: 200, headers: { ...headers, 'Content-Length': String(size) } })
}

function registerProtocols() {
    protocol.handle('app', async request => {
        let rel = decodeURIComponent(new URL(request.url).pathname)
        if (rel.startsWith('/__print/')) {
            const html = printJobs.get(rel.slice(9))
            return html == null ? new Response('Not Found', { status: 404 })
                : new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })
        }
        // 用户导入的字体：app://local/__fonts/<文件名>
        if (rel.startsWith('/__fonts/')) return serveFile(path.join(fontDir(), path.basename(rel)), request)
        if (rel === '/' || rel === '') rel = '/index.html'
        const target = path.normalize(path.join(DIST, rel))
        if (!target.startsWith(DIST)) return new Response('Forbidden', { status: 403 })
        // 开发模式下 dist 可能不存在，回退到 public 中的静态资源
        if (!(await fsp.stat(target).catch(() => null))) {
            const pub = path.normalize(path.join(PUBLIC, rel))
            if (pub.startsWith(PUBLIC)) return serveFile(pub, request)
        }
        return serveFile(target, request)
    })
    // media://file/<encodeURIComponent(本地绝对路径)> —— 读取本地图片等资源
    protocol.handle('media', request => serveFile(decodeURIComponent(new URL(request.url).pathname.slice(1)), request))
}

// ---------- 窗口状态 ----------
function readState() {
    try { return JSON.parse(fs.readFileSync(STATE_FILE(), 'utf8')) } catch { return {} }
}
let state = {}
function writeState(patch) {
    state = { ...state, ...patch }
    try { fs.writeFileSync(STATE_FILE(), JSON.stringify(state)) } catch { /* ignore */ }
}

let win = null
let allowClose = false
const pendingFiles = []

const collectFiles = argv => argv
    .filter(a => a && !a.startsWith('-'))
    .map(a => path.resolve(a))
    .filter(p => { try { return fs.statSync(p).isFile() } catch { return false } })
    .filter(p => !/\.(exe|asar|js|mjs)$/i.test(p))

function createWindow() {
    state = readState()
    const b = state.bounds ?? {}
    win = new BrowserWindow({
        width: b.width ?? 1360,
        height: b.height ?? 860,
        x: b.x, y: b.y,
        minWidth: 980,
        minHeight: 620,
        frame: false,
        show: false,
        backgroundColor: getTheme().bg,
        title: 'LiteEditor',
        icon: path.join(__dirname, '..', 'build', 'icon.png'),
        webPreferences: {
            preload: path.join(__dirname, 'preload.cjs'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
            spellcheck: false,
            // 录屏时窗口最小化，仍需保持定时器与画面合成的正常速度
            backgroundThrottling: false,
        },
    })
    if (state.maximized) win.maximize()
    win.once('ready-to-show', () => win.show())

    const saveBounds = () => {
        if (!win.isMaximized() && !win.isFullScreen() && !win.isMinimized())
            writeState({ bounds: win.getBounds() })
    }
    win.on('resize', saveBounds)
    win.on('move', saveBounds)
    const sendMax = () => {
        writeState({ maximized: win.isMaximized() })
        win.webContents.send('win:state', { maximized: win.isMaximized(), fullscreen: win.isFullScreen() })
    }
    win.on('maximize', sendMax)
    win.on('unmaximize', sendMax)
    win.on('enter-full-screen', sendMax)
    win.on('leave-full-screen', sendMax)
    // 关闭前交给渲染进程确认未保存的文档
    win.on('close', e => {
        if (allowClose || process.env.LITE_SMOKE) return
        e.preventDefault()
        win.webContents.send('app:before-close')
    })

    win.webContents.on('before-input-event', (e, input) => {
        if (input.type === 'keyDown' && (input.key === 'F12' || (input.control && input.shift && input.key.toLowerCase() === 'i'))) {
            win.webContents.toggleDevTools()
            e.preventDefault()
        }
    })
    win.webContents.setWindowOpenHandler(({ url }) => {
        if (/^https?:|^mailto:/.test(url)) shell.openExternal(url)
        return { action: 'deny' }
    })
    win.webContents.on('will-navigate', (e, url) => {
        if (url !== win.webContents.getURL()) {
            e.preventDefault()
            if (/^https?:|^mailto:/.test(url)) shell.openExternal(url)
        }
    })

    if (DEV_URL) win.loadURL(DEV_URL)
    else win.loadURL('app://local/index.html')
}

// 在隐藏窗口中加载 HTML，用于导出 PDF 与打印
// 通过 app://local/__print/<id> 提供页面，使 ./vendor/... 等相对资源可以正常加载
const printJobs = new Map()
let printSeq = 0
async function withHtmlWindow(html, fn) {
    const id = `${Date.now()}-${++printSeq}`
    // 注入用户字体，使导出的 PDF 与打印内容使用相同字体
    const css = await userFontCSS().catch(() => '')
    if (css) {
        const style = `<style>${css}</style>`
        html = /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, m => m + style) : style + html
    }
    printJobs.set(id, html)
    const w = new BrowserWindow({ show: false, webPreferences: { sandbox: true, javascript: false } })
    try {
        await w.loadURL(`app://local/__print/${id}`)
        await w.webContents.executeJavaScript('document.fonts.ready.then(() => 1)').catch(() => {})
        await new Promise(r => setTimeout(r, 250))
        return await fn(w)
    } finally {
        w.destroy()
        printJobs.delete(id)
    }
}

// ---------- IPC ----------
function registerIpc() {
    ipcMain.handle('dialog:open', async (_e, opts = {}) => {
        const r = await dialog.showOpenDialog(win, {
            title: opts.title ?? '打开文件',
            properties: ['openFile', ...(opts.multi === false ? [] : ['multiSelections'])],
            filters: opts.filters,
        })
        return r.canceled ? [] : r.filePaths
    })
    ipcMain.handle('dialog:save', async (_e, { defaultPath, filters, title }) => {
        const r = await dialog.showSaveDialog(win, { title, defaultPath, filters })
        return r.canceled || !r.filePath ? null : r.filePath
    })
    ipcMain.handle('dialog:message', async (_e, opts) => (await dialog.showMessageBox(win, opts)).response)
    ipcMain.handle('fs:read', async (_e, p) => {
        const buf = await fsp.readFile(p)
        return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    })
    ipcMain.handle('fs:write', async (_e, p, data) => {
        await fsp.mkdir(path.dirname(p), { recursive: true })
        await fsp.writeFile(p, typeof data === 'string' ? data : Buffer.from(data))
        return true
    })
    ipcMain.handle('fs:stat', async (_e, p) => {
        try {
            const s = await fsp.stat(p)
            return { size: s.size, mtime: s.mtimeMs, isFile: s.isFile(), isDir: s.isDirectory() }
        } catch { return null }
    })
    ipcMain.handle('print:pdf', (_e, html, opts = {}) => withHtmlWindow(html, async w => {
        const buf = await w.webContents.printToPDF({
            printBackground: true, landscape: !!opts.landscape, preferCSSPageSize: true,
            pageSize: opts.pageSize ?? 'A4', margins: { marginType: 'none' },
        })
        return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    }))
    ipcMain.handle('print:html', (_e, html) => withHtmlWindow(html, w => new Promise(resolve => {
        w.webContents.print({ printBackground: true }, ok => resolve(ok))
    })))
    ipcMain.handle('shell:show', (_e, p) => shell.showItemInFolder(p))
    ipcMain.handle('shell:open-external', (_e, url) => shell.openExternal(url))

    ipcMain.on('win:minimize', () => win?.minimize())
    ipcMain.on('win:toggle-maximize', () => {
        if (!win) return
        if (win.isFullScreen()) win.setFullScreen(false)
        else if (win.isMaximized()) win.unmaximize()
        else win.maximize()
    })
    ipcMain.on('win:close', () => win?.close())
    ipcMain.on('win:close-confirmed', () => { allowClose = true; win?.close() })
    ipcMain.on('win:set-fullscreen', (_e, v) => win?.setFullScreen(!!v))
    ipcMain.handle('win:state', () => ({ maximized: win?.isMaximized(), fullscreen: win?.isFullScreen() }))
    ipcMain.on('win:set-bg', (_e, bg) => win?.setBackgroundColor(bg))
    ipcMain.handle('app:take-files', () => pendingFiles.splice(0))
    ipcMain.handle('app:info', () => ({
        version: app.getVersion(),
        electron: process.versions.electron,
        chrome: process.versions.chrome,
        node: process.versions.node,
    }))
}

// ---------- 启动 ----------
if (!process.env.LITE_SMOKE && !app.requestSingleInstanceLock()) {
    app.quit()
} else {
    pendingFiles.push(...collectFiles(process.argv.slice(1)))
    app.on('second-instance', (_e, argv) => {
        const files = collectFiles(argv.slice(1))
        if (win) {
            if (win.isMinimized()) win.restore()
            win.focus()
            if (files.length) win.webContents.send('app:open-files', files)
        }
    })
    app.whenReady().then(() => {
        Menu.setApplicationMenu(null)
        initThemeBridge()
        onThemeChange(t => { if (win && !win.isDestroyed()) win.setBackgroundColor(t.bg) })
        registerProtocols()
        registerIpc()
        registerFonts()
        createWindow()
        registerCapture({
            mainWindow: () => win,
            preload: path.join(__dirname, 'preload.cjs'),
            // 截图遮罩页面：开发模式从 Vite 加载，生产模式从 app:// 加载
            loadPage: (w, page) => DEV_URL ? w.loadURL(new URL(page, DEV_URL).href) : w.loadURL('app://local/' + page),
        })
        if (!process.env.LITE_SMOKE) registerHotkeys(kind => win?.webContents.send('capture:hotkey', kind))
    })
    app.on('will-quit', () => unregisterHotkeys())
    app.on('window-all-closed', () => app.quit())
}
