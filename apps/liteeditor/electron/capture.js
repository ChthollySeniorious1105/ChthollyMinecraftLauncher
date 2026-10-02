// 屏幕捕获：录屏源、截图（全屏冻结 + 区域选择遮罩窗口）、全局快捷键
import { BrowserWindow, ipcMain, desktopCapturer, session, screen, globalShortcut, clipboard, nativeImage, ClipboardItem } from 'electron'

let getMain = () => null
let pickedSourceId = null

export function registerCapture({ mainWindow, preload, loadPage }) {
    getMain = mainWindow

    // getDisplayMedia：使用渲染进程预先选择的源（没有选择时默认主屏幕）
    session.defaultSession.setDisplayMediaRequestHandler(async (request, callback) => {
        const sources = await desktopCapturer.getSources({ types: ['screen', 'window'] })
        const src = sources.find(s => s.id === pickedSourceId) ?? sources.find(s => s.id.startsWith('screen')) ?? sources[0]
        callback(src ? { video: src, audio: request.audioRequested ? 'loopback' : undefined } : {})
    }, { useSystemPicker: false })

    ipcMain.handle('capture:sources', async (_e, opts = {}) => {
        const sources = await desktopCapturer.getSources({ types: opts.types ?? ['screen', 'window'], thumbnailSize: { width: 320, height: 200 }, fetchWindowIcons: true })
        const main = getMain()
        return sources
            .filter(s => !main || s.name !== main.getTitle() || s.id.startsWith('screen'))
            .map(s => ({ id: s.id, name: s.name, display: s.display_id, thumb: s.thumbnail.toDataURL(), icon: s.appIcon?.toDataURL() ?? null }))
    })
    ipcMain.handle('capture:pick', (_e, id) => { pickedSourceId = id; return true })
    ipcMain.handle('capture:displays', () => screen.getAllDisplays().map(d => ({ id: d.id, bounds: d.bounds, scale: d.scaleFactor, primary: d.id === screen.getPrimaryDisplay().id })))
    ipcMain.handle('win:hide', () => { const w = getMain(); w?.minimize(); return true })
    ipcMain.handle('win:show', () => { const w = getMain(); if (w) { if (w.isMinimized()) w.restore(); w.show(); w.focus() } return true })

    // 截图：隐藏主窗口 → 抓取显示器原始分辨率图像 → 打开全屏遮罩让用户框选
    ipcMain.handle('capture:screenshot', async (_e, opts = {}) => shoot(opts, preload, loadPage))
    ipcMain.handle('clipboard:image', (_e, dataURL) => copyImage(dataURL))

    // 录制控制条：录制期间悬浮在屏幕底部，自身不会被录进视频
    ipcMain.handle('recbar:show', (_e, opts = {}) => showRecBar(opts, preload, loadPage))
    ipcMain.handle('recbar:hide', () => { if (recBar && !recBar.isDestroyed()) recBar.destroy(); recBar = null; return true })
    ipcMain.on('recbar:state', (_e, st) => { if (recBar && !recBar.isDestroyed()) recBar.webContents.send('rec:state', st) })
    ipcMain.on('recbar:cmd', (_e, cmd) => getMain()?.webContents.send('capture:hotkey', cmd === 'pause' ? 'record-pause' : 'record'))
}

// 旧版 Electron 使用 writeImage；新版剪贴板为异步 ClipboardItem API
async function copyImage(dataURL) {
    if (typeof clipboard.writeImage === 'function') { clipboard.writeImage(nativeImage.createFromDataURL(dataURL)); return true }
    const png = nativeImage.createFromDataURL(dataURL).toPNG()
    await clipboard.write([new ClipboardItem({ 'image/png': new Blob([png], { type: 'image/png' }) })])
    return true
}

let recBar = null
function showRecBar({ displayId } = {}, preload, loadPage) {
    if (recBar && !recBar.isDestroyed()) return true
    const d = screen.getAllDisplays().find(x => String(x.id) === String(displayId)) ?? screen.getPrimaryDisplay()
    const W = 236, H = 44, wa = d.workArea
    recBar = new BrowserWindow({
        x: Math.round(wa.x + (wa.width - W) / 2), y: wa.y + wa.height - H - 24, width: W, height: H,
        frame: false, transparent: true, resizable: false, maximizable: false, minimizable: false, fullscreenable: false,
        alwaysOnTop: true, skipTaskbar: true, show: false, hasShadow: false, focusable: true,
        webPreferences: { preload, contextIsolation: true, sandbox: true },
    })
    recBar.setAlwaysOnTop(true, 'screen-saver')
    recBar.setContentProtection(true)
    recBar.once('ready-to-show', () => recBar?.showInactive())
    recBar.on('closed', () => { recBar = null })
    loadPage(recBar, 'recbar.html')
    return true
}

async function grabDisplay(display) {
    const size = { width: Math.round(display.bounds.width * display.scaleFactor), height: Math.round(display.bounds.height * display.scaleFactor) }
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: size })
    const src = sources.find(s => String(s.display_id) === String(display.id)) ?? sources[0]
    return src?.thumbnail
}

let shooting = false
async function shoot({ mode = 'region', delay = 0, hideSelf = true } = {}, preload, loadPage) {
    if (shooting) return null
    shooting = true
    const main = getMain()
    try {
        const wasVisible = main?.isVisible() && !main.isMinimized()
        if (hideSelf && wasVisible) { main.hide(); await sleep(260) }
        if (delay) await sleep(delay * 1000)
        const point = screen.getCursorScreenPoint()
        const display = screen.getDisplayNearestPoint(point)
        const img = await grabDisplay(display)
        if (!img || img.isEmpty()) throw new Error('无法获取屏幕图像')
        const dataURL = img.toDataURL()
        let result
        if (mode === 'full') result = { dataURL, width: img.getSize().width, height: img.getSize().height }
        else result = await selectRegion(display, dataURL, preload, loadPage, mode)
        if (result && mode === 'rect') result.displayId = display.id
        if (hideSelf && wasVisible && mode !== 'rect') { main?.show(); main?.focus() }
        return result
    } finally {
        shooting = false
        if (main && !main.isVisible() && mode !== 'rect') main.show()
    }
}

// 全屏遮罩窗口：显示冻结的屏幕图像，用户拖出区域（或单击窗口）后返回裁剪结果
function selectRegion(display, dataURL, preload, loadPage, mode) {
    return new Promise(resolve => {
        const b = display.bounds
        const w = new BrowserWindow({
            x: b.x, y: b.y, width: b.width, height: b.height, frame: false, transparent: false, resizable: false, movable: false,
            alwaysOnTop: true, skipTaskbar: true, fullscreenable: false, enableLargerThanScreen: true, show: false, backgroundColor: '#000000',
            webPreferences: { preload, contextIsolation: true, sandbox: true },
        })
        w.setAlwaysOnTop(true, 'screen-saver')
        let done = false
        const finish = v => {
            if (done) return
            done = true
            ipcMain.removeHandler('shot:init')
            ipcMain.removeAllListeners('shot:done')
            if (!w.isDestroyed()) w.destroy()
            resolve(v)
        }
        ipcMain.handle('shot:init', () => ({ dataURL, scale: display.scaleFactor, mode }))
        ipcMain.on('shot:done', (_e, v) => finish(v))
        w.on('closed', () => finish(null))
        w.once('ready-to-show', () => { w.show(); w.focus() })
        loadPage(w, 'shot.html')
    })
}

export function registerHotkeys(send) {
    const keys = [
        ['CommandOrControl+Alt+A', 'region'],
        ['CommandOrControl+Alt+F', 'full'],
        ['CommandOrControl+Alt+R', 'record'],
        ['CommandOrControl+Alt+P', 'record-pause'],
    ]
    for (const [acc, kind] of keys) {
        try { globalShortcut.register(acc, () => send(kind)) } catch { /* 快捷键被占用时忽略 */ }
    }
}
export const unregisterHotkeys = () => globalShortcut.unregisterAll()

const sleep = ms => new Promise(r => setTimeout(r, ms))
