import { app, BrowserWindow, ipcMain, dialog, protocol, shell, Menu } from 'electron'
import path from 'node:path'
import fs from 'node:fs'
import fsp from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { Readable } from 'node:stream'
import { createRequire } from 'node:module'
import { createHash } from 'node:crypto'
import { execFile } from 'node:child_process'
import { initThemeBridge, getTheme, onThemeChange } from './theme-bridge.js'

const require = createRequire(import.meta.url)
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DIST = path.join(__dirname, '..', 'dist')
const DEV_URL = process.env.VITE_DEV_SERVER_URL
const STATE_FILE = () => path.join(app.getPath('userData'), 'window-state.json')
// 由 CML 的共享 Electron 运行时以 `electron.exe <app 目录>` 启动：显式固定应用名、数据目录与任务栏身份，
// 保持与独立安装版相同的 %APPDATA%\LiteReader，并让单实例锁按应用区分
app.setName('LiteReader')
app.setPath('userData', path.join(app.getPath('appData'), 'LiteReader'))
if (process.platform === 'win32') app.setAppUserModelId('com.litereader.app')
if (process.env.LITE_USERDATA) app.setPath('userData', path.resolve(process.env.LITE_USERDATA))

const MIME = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm',
    '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.jfif': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.bmp': 'image/bmp',
    '.ico': 'image/x-icon', '.avif': 'image/avif', '.apng': 'image/apng',
    '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf',
    '.bcmap': 'application/octet-stream', '.pfb': 'application/octet-stream',
    '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg', '.oga': 'audio/ogg', '.opus': 'audio/ogg',
    '.wav': 'audio/wav', '.flac': 'audio/flac', '.m4a': 'audio/mp4', '.aac': 'audio/aac',
    '.weba': 'audio/webm', '.mp4': 'video/mp4', '.m4v': 'video/mp4', '.webm': 'video/webm',
    '.mkv': 'video/x-matroska', '.mov': 'video/quicktime', '.ogv': 'video/ogg', '.3gp': 'video/3gpp',
    '.htm': 'text/html; charset=utf-8', '.xhtml': 'application/xhtml+xml', '.eot': 'application/vnd.ms-fontobject',
    '.vtt': 'text/vtt', '.srt': 'text/plain', '.txt': 'text/plain',
}
const mimeOf = p => MIME[path.extname(p).toLowerCase()] ?? 'application/octet-stream'

protocol.registerSchemesAsPrivileged([
    { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
    { scheme: 'media', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true, bypassCSP: true } },
])

// 支持 Range 请求的文件响应，保证音视频可以任意拖动进度
async function serveFile(filePath, request) {
    let stat
    try { stat = await fsp.stat(filePath) } catch { return new Response('Not Found', { status: 404 }) }
    if (!stat.isFile()) return new Response('Not Found', { status: 404 })
    const size = stat.size
    const headers = {
        'Content-Type': mimeOf(filePath),
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache',
    }
    const range = request.headers.get('range')
    const m = range && /bytes=(\d*)-(\d*)/.exec(range)
    if (m && (m[1] || m[2])) {
        let start = m[1] ? Number(m[1]) : size - Number(m[2])
        let end = m[1] && m[2] ? Number(m[2]) : size - 1
        start = Math.max(0, start)
        end = Math.min(end, size - 1)
        if (start >= size || start > end)
            return new Response(null, { status: 416, headers: { ...headers, 'Content-Range': `bytes */${size}` } })
        const stream = fs.createReadStream(filePath, { start, end })
        return new Response(Readable.toWeb(stream), {
            status: 206,
            headers: { ...headers, 'Content-Length': String(end - start + 1), 'Content-Range': `bytes ${start}-${end}/${size}` },
        })
    }
    return new Response(Readable.toWeb(fs.createReadStream(filePath)), {
        status: 200, headers: { ...headers, 'Content-Length': String(size) },
    })
}

function registerProtocols() {
    protocol.handle('app', request => {
        const { pathname } = new URL(request.url)
        let rel = decodeURIComponent(pathname)
        if (rel === '/' || rel === '') rel = '/index.html'
        const target = path.normalize(path.join(DIST, rel))
        if (!target.startsWith(DIST)) return new Response('Forbidden', { status: 403 })
        return serveFile(target, request)
    })
    // media://file/<encodeURIComponent(本地绝对路径)>
    // media://local/D:/dir/file.png —— 保留目录层级，供网页中的相对路径使用
    protocol.handle('media', request => {
        const { host, pathname } = new URL(request.url)
        const rel = decodeURIComponent(pathname.slice(1))
        const filePath = host === 'local' ? path.normalize(process.platform === 'win32' ? rel : '/' + rel) : rel
        return serveFile(filePath, request)
    })
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
const pendingFiles = []

const collectFiles = argv => argv
    .filter(a => a && !a.startsWith('-'))
    .map(a => path.resolve(a))
    .filter(p => { try { return fs.statSync(p).isFile() } catch { return false } })
    .filter(p => !p.toLowerCase().endsWith('.exe') && !p.toLowerCase().endsWith('.asar'))

function createWindow() {
    state = readState()
    const b = state.bounds ?? {}
    win = new BrowserWindow({
        width: b.width ?? 1280,
        height: b.height ?? 820,
        x: b.x, y: b.y,
        minWidth: 900,
        minHeight: 580,
        frame: false,
        show: false,
        backgroundColor: getTheme().bg,
        title: 'LiteReader',
        icon: path.join(__dirname, '..', 'build', 'icon.png'),
        webPreferences: {
            preload: path.join(__dirname, 'preload.cjs'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
            spellcheck: false,
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

    win.webContents.on('before-input-event', (e, input) => {
        if (input.type === 'keyDown' && (input.key === 'F12' || (input.control && input.shift && input.key.toLowerCase() === 'i'))) {
            win.webContents.toggleDevTools()
            e.preventDefault()
        }
    })
    // 外部链接交给系统浏览器
    win.webContents.setWindowOpenHandler(({ url }) => {
        if (/^https?:|^mailto:/.test(url)) shell.openExternal(url)
        return { action: 'deny' }
    })
    win.webContents.on('will-navigate', (e, url) => {
        const current = win.webContents.getURL()
        if (url !== current) {
            e.preventDefault()
            if (/^https?:|^mailto:/.test(url)) shell.openExternal(url)
        }
    })

    if (DEV_URL) win.loadURL(DEV_URL)
    else win.loadURL('app://local/index.html')
}

// ---------- IPC ----------
const naturalCompare = new Intl.Collator('zh-CN', { numeric: true, sensitivity: 'base' }).compare

function registerIpc() {
    ipcMain.handle('dialog:open', async (_e, opts = {}) => {
        const r = await dialog.showOpenDialog(win, {
            title: opts.title ?? '打开文件',
            properties: ['openFile', 'multiSelections'],
            filters: opts.filters,
        })
        return r.canceled ? [] : r.filePaths
    })
    ipcMain.handle('dialog:save', async (_e, { defaultPath, filters, data }) => {
        const r = await dialog.showSaveDialog(win, { defaultPath, filters })
        if (r.canceled || !r.filePath) return null
        await fsp.writeFile(r.filePath, Buffer.from(data))
        return r.filePath
    })
    // 只选择保存位置（批量转换时逐个写入）
    ipcMain.handle('dialog:save-path', async (_e, { defaultPath, filters }) => {
        const r = await dialog.showSaveDialog(win, { defaultPath, filters })
        return r.canceled ? null : r.filePath
    })
    ipcMain.handle('dialog:folder', async (_e, { title, defaultPath } = {}) => {
        const r = await dialog.showOpenDialog(win, { title: title ?? '选择文件夹', defaultPath, properties: ['openDirectory', 'createDirectory'] })
        return r.canceled ? null : r.filePaths[0]
    })
    ipcMain.handle('fs:write', async (_e, p, data) => {
        await fsp.mkdir(path.dirname(p), { recursive: true })
        await fsp.writeFile(p, Buffer.from(data))
        return p
    })
    ipcMain.handle('fs:exists', async (_e, p) => { try { await fsp.access(p); return true } catch { return false } })
    // 打印 / 转换用的临时资源（页面图片等），返回可在打印窗口中加载的 media:// 地址
    ipcMain.handle('print:asset', async (_e, data, ext = 'png') => {
        const dir = path.join(app.getPath('temp'), 'LiteReader', 'print', 'assets')
        await fsp.mkdir(dir, { recursive: true })
        const file = path.join(dir, `${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`)
        await fsp.writeFile(file, Buffer.from(data))
        return 'media://local/' + file.replace(/\\/g, '/').split('/').filter(Boolean).map(encodeURIComponent).join('/')
    })
    // 打印 / 导出 PDF：在隐藏窗口中加载排版好的 HTML，由 Chromium 分页
    // mode: 'pdf' 写入 target；'print' 弹出系统打印对话框；'preview' 生成 PDF 数据返回给界面预览
    ipcMain.handle('print:html', async (_e, { html, mode, target, pageSize = 'A4', landscape = false, margins = 'default', scale = 1, headerFooter = false, title = 'LiteReader', cssPage = false }) => {
        const tmp = path.join(app.getPath('temp'), 'LiteReader', 'print', `${Date.now()}-${Math.random().toString(36).slice(2)}.html`)
        await fsp.mkdir(path.dirname(tmp), { recursive: true })
        await fsp.writeFile(tmp, html, 'utf8')
        const pw = new BrowserWindow({
            show: false, width: 1000, height: 1400,
            webPreferences: { sandbox: true, contextIsolation: true, javascript: false, offscreen: false },
        })
        try {
            await pw.loadURL('media://local/' + tmp.replace(/\\/g, '/').split('/').filter(Boolean).map(encodeURIComponent).join('/'))
            // 等待图片与字体加载完成
            await pw.webContents.executeJavaScript('document.fonts?.ready.then(() => true)', true).catch(() => {})
            await new Promise(r => setTimeout(r, 300))
            const m = { none: { marginType: 'none' }, minimum: { marginType: 'printableArea' }, default: { marginType: 'default' } }[margins] ?? { marginType: 'default' }
            if (mode === 'print') {
                return await new Promise(resolve => {
                    pw.webContents.print({ silent: false, printBackground: true, landscape, ...(cssPage ? { margins: { marginType: 'none' } } : { pageSize, margins: m }), scaleFactor: Math.round(scale * 100), header: headerFooter ? title : undefined },
                        (ok, reason) => resolve({ ok, reason }))
                })
            }
            const marginsPdf = margins === 'none' ? { top: 0, bottom: 0, left: 0, right: 0 } : margins === 'minimum' ? { top: 0.2, bottom: 0.2, left: 0.2, right: 0.2 } : { top: 0.6, bottom: 0.6, left: 0.6, right: 0.6 }
            const pdf = await pw.webContents.printToPDF({
                printBackground: true, landscape, pageSize, margins: cssPage ? { top: 0, bottom: 0, left: 0, right: 0 } : marginsPdf, scale: clampNum(scale, 0.1, 2),
                preferCSSPageSize: cssPage,
                displayHeaderFooter: headerFooter,
                headerTemplate: headerFooter ? `<div style="font-size:8px;width:100%;text-align:center;color:#888">${escapeHtml(title)}</div>` : '<span></span>',
                footerTemplate: headerFooter ? '<div style="font-size:8px;width:100%;text-align:center;color:#888"><span class="pageNumber"></span> / <span class="totalPages"></span></div>' : '<span></span>',
                generateDocumentOutline: true, generateTaggedPDF: true,
            })
            if (mode === 'preview') return { ok: true, data: new Uint8Array(pdf.buffer, pdf.byteOffset, pdf.byteLength) }
            await fsp.mkdir(path.dirname(target), { recursive: true })
            await fsp.writeFile(target, pdf)
            return { ok: true, path: target, size: pdf.length }
        } finally {
            pw.destroy()
            fsp.rm(tmp, { force: true }).catch(() => {})
        }
    })
    // 将 HTML 渲染为 PNG 截图（用于幻灯片 / 版式页面导出图片）
    ipcMain.handle('render:png', async (_e, { html, width, height, scale = 2 }) => {
        const tmp = path.join(app.getPath('temp'), 'LiteReader', 'print', `${Date.now()}-${Math.random().toString(36).slice(2)}.html`)
        await fsp.mkdir(path.dirname(tmp), { recursive: true })
        await fsp.writeFile(tmp, html, 'utf8')
        // 窗口按放大后的尺寸创建，页面内用 CSS zoom 放大，保证导出清晰
        const pw = new BrowserWindow({ show: false, width: Math.ceil(width * scale), height: Math.ceil(height * scale), useContentSize: true, frame: false, webPreferences: { sandbox: true, javascript: false } })
        try {
            await pw.loadURL('media://local/' + tmp.replace(/\\/g, '/').split('/').filter(Boolean).map(encodeURIComponent).join('/'))
            await new Promise(r => setTimeout(r, 250))
            const img = await pw.webContents.capturePage()
            const png = img.toPNG()
            return new Uint8Array(png.buffer, png.byteOffset, png.byteLength)
        } finally {
            pw.destroy()
            fsp.rm(tmp, { force: true }).catch(() => {})
        }
    })
    ipcMain.handle('fs:read', async (_e, p) => {
        const buf = await fsp.readFile(p)
        return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength)
    })
    ipcMain.handle('fs:stat', async (_e, p) => {
        try {
            const s = await fsp.stat(p)
            return { size: s.size, mtime: s.mtimeMs, isFile: s.isFile(), isDir: s.isDirectory() }
        } catch { return null }
    })
    // 按候选扩展名查找第一个存在的文件（LaTeX 插图常省略扩展名）
    ipcMain.handle('fs:find-first', async (_e, base, exts) => {
        for (const ext of exts) {
            try { if ((await fsp.stat(base + ext)).isFile()) return base + ext } catch { /* 继续尝试 */ }
        }
        return null
    })
    // CHM：使用 Windows 自带的 hh.exe 反编译到缓存目录，返回目录路径与文件列表
    ipcMain.handle('chm:extract', async (_e, file) => {
        if (process.platform !== 'win32') throw new Error('CHM 解析依赖 Windows 系统组件 hh.exe')
        const st = await fsp.stat(file)
        const key = createHash('md5').update(file + st.size + st.mtimeMs).digest('hex').slice(0, 16)
        const dir = path.join(app.getPath('temp'), 'LiteReader', 'chm', key)
        const listFiles = async () => {
            const out = []
            const walk = async (d, rel) => {
                for (const ent of await fsp.readdir(d, { withFileTypes: true })) {
                    const r = rel ? rel + '/' + ent.name : ent.name
                    if (ent.isDirectory()) await walk(path.join(d, ent.name), r)
                    else out.push(r)
                }
            }
            await walk(dir, '')
            return out
        }
        try {
            const files = await listFiles()
            if (files.length) return { dir, files }
        } catch { /* 尚未解压 */ }
        await fsp.mkdir(dir, { recursive: true })
        await new Promise((resolve, reject) => {
            execFile(path.join(process.env.SystemRoot ?? 'C:\\Windows', 'hh.exe'), ['-decompile', dir, file], { windowsHide: true, timeout: 120000 }, err => {
                // hh.exe 总是返回非 0，以是否产出文件为准
                resolve(err)
            })
        })
        const files = await listFiles()
        if (!files.length) throw new Error('无法解析此 CHM 文件（可能已损坏或被系统阻止）')
        return { dir, files }
    })
    ipcMain.handle('fs:list-dir', async (_e, dir) => {
        try {
            const ents = await fsp.readdir(dir, { withFileTypes: true })
            const files = []
            for (const d of ents) {
                if (!d.isFile()) continue
                const full = path.join(dir, d.name)
                let size = 0
                try { size = (await fsp.stat(full)).size } catch { /* ignore */ }
                files.push({ name: d.name, path: full, size })
            }
            return files.sort((a, b) => naturalCompare(a.name, b.name))
        } catch { return [] }
    })
    ipcMain.handle('doc:extract', async (_e, src) => {
        const WordExtractor = require('word-extractor')
        const extractor = new WordExtractor()
        const doc = await extractor.extract(typeof src === 'string' ? src : Buffer.from(src))
        return {
            body: doc.getBody(),
            footnotes: doc.getFootnotes?.() ?? '',
            endnotes: doc.getEndnotes?.() ?? '',
        }
    })
    ipcMain.handle('audio:meta', async (_e, src) => {
        try {
            const mm = await import('music-metadata')
            const meta = typeof src === 'string'
                ? await mm.parseFile(src)
                : await mm.parseBuffer(Buffer.from(src))
            const c = meta.common, f = meta.format
            const pic = c.picture?.[0]
            let lyrics = ''
            for (const l of c.lyrics ?? []) {
                if (typeof l === 'string') lyrics ||= l
                else if (l?.text) lyrics ||= l.text
                else if (l?.syncText?.length) lyrics ||= l.syncText
                    .map(s => `[${fmtLrc(s.timestamp)}]${s.text}`).join('\n')
            }
            return {
                title: c.title, artist: c.artist, album: c.album, year: c.year,
                genre: c.genre?.[0], track: c.track?.no,
                duration: f.duration, bitrate: f.bitrate, sampleRate: f.sampleRate,
                codec: f.codec, lossless: f.lossless, container: f.container, bits: f.bitsPerSample, channels: f.numberOfChannels,
                picture: pic ? { data: new Uint8Array(pic.data), format: pic.format } : null,
                lyrics,
            }
        } catch (err) {
            return { error: String(err?.message ?? err) }
        }
    })
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

const clampNum = (v, lo, hi) => Math.min(hi, Math.max(lo, Number(v) || 1))
const escapeHtml = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

const fmtLrc = ms => {
    const t = (ms ?? 0) / 1000
    const m = Math.floor(t / 60), s = (t % 60).toFixed(2).padStart(5, '0')
    return `${String(m).padStart(2, '0')}:${s}`
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
        fsp.rm(path.join(app.getPath('temp'), 'LiteReader', 'print'), { recursive: true, force: true }).catch(() => {})
        Menu.setApplicationMenu(null)
        initThemeBridge()
        onThemeChange(t => { if (win && !win.isDestroyed()) win.setBackgroundColor(t.bg) })
        registerProtocols()
        registerIpc()
        createWindow()
    })
    app.on('window-all-closed', () => app.quit())
}
