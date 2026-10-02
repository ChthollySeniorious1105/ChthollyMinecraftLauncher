// 冒烟测试：在真实 Electron 窗口中执行测试脚本并截图
// 用法：node scripts/smoke.mjs <测试名...>      （会先构建到 .tmp/dist-<名>）
//       electron scripts/smoke.mjs --run <测试文件.mjs>   （内部使用）
// 测试文件导出 default async ({ win, js, shot, wait, key, log, theme }) => {}
// theme('dark' | 'light' | {...}) 写入临时的 CML_THEME_FILE，经真实的主题桥切换配色
import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'

const i = process.argv.indexOf('--run')
const testFile = path.resolve(process.argv[i + 1])
const name = path.basename(testFile, '.mjs')
const outDir = path.resolve('.tmp/smoke', name)
fs.rmSync(outDir, { recursive: true, force: true })
fs.mkdirSync(outDir, { recursive: true })
process.argv.splice(2)
process.env.LITE_SMOKE = '1'

// 主题：使用独立的主题文件，不读取本机 CML 的 theme.json
const THEMES = {
    light: { version: 1, id: 'smoke-light', name: '测试浅色', dark: false, bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280', line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff', paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8'] },
    dark: { version: 1, id: 'smoke-dark', name: '测试深色', dark: true, bg: '#11141c', surface: '#1a1e29', panel: '#1a1e29', text: '#e4e8f2', muted: '#97a0b3', line: '#2a3040', field: '#222838', accent: '#7c9cff', accent2: '#5ad1c4', onAccent: '#0d1020', paper: '#181c26', ink: '#d6dbe6', art: ['#7c9cff', '#5ad1c4'] },
}
const themeFile = path.join(outDir, '..', `theme-${name}.json`)
const writeTheme = t => fs.writeFileSync(themeFile + '.tmp', JSON.stringify(typeof t === 'string' ? THEMES[t] : t)) || fs.renameSync(themeFile + '.tmp', themeFile)
writeTheme(process.env.SMOKE_THEME ?? 'light')
process.env.CML_THEME_FILE = themeFile

let failed = false
const errors = []
app.on('browser-window-created', (_e, win) => {
    if (win.id !== 1) return
    win.setSize(1440, 900)
    win.webContents.on('console-message', e => {
        if (e.level === 'error' || e.level === 'warning') {
            const msg = e.message.slice(0, 600)
            console.log(`[renderer:${e.level}]`, msg)
            if (e.level === 'error') errors.push(msg)
        }
    })
    win.webContents.on('render-process-gone', (_e, d) => { console.log('[gone]', d.reason); failed = true })
    win.webContents.once('did-finish-load', async () => {
        const wait = ms => new Promise(r => setTimeout(r, ms))
        const js = async code => {
            let r
            try {
                r = await win.webContents.executeJavaScript(`(async () => { try { return { ok: await (async () => { ${code} })() } } catch (e) { return { err: String(e?.message ?? e), stack: String(e?.stack ?? '').split(String.fromCharCode(10)).slice(1, 5).join(' | ') } } })()`)
            } catch (err) {
                throw new Error('JS 执行失败：' + err.message + '\n' + code.slice(0, 300))
            }
            if (r && 'err' in r) throw new Error('JS 执行失败：' + r.err + '\n  ' + r.stack + '\n' + code.slice(0, 300))
            return r?.ok
        }
        let n = 0
        const shot = async label => {
            await wait(250)
            const img = await win.webContents.capturePage()
            const f = path.join(outDir, `${String(++n).padStart(2, '0')}-${label}.png`)
            fs.writeFileSync(f, img.toPNG())
            return f
        }
        const key = async (keyCode, modifiers = []) => {
            win.webContents.sendInputEvent({ type: 'keyDown', keyCode, modifiers })
            if (keyCode.length === 1) win.webContents.sendInputEvent({ type: 'char', keyCode, modifiers })
            win.webContents.sendInputEvent({ type: 'keyUp', keyCode, modifiers })
            await wait(60)
        }
        const mouse = async (type, x, y, opts = {}) => {
            win.webContents.sendInputEvent({ type, x: Math.round(x), y: Math.round(y), button: 'left', clickCount: 1, ...opts })
            await wait(16)
        }
        const drag = async (x1, y1, x2, y2, steps = 8, opts = {}) => {
            await mouse('mouseDown', x1, y1, opts)
            for (let s = 1; s <= steps; s++) await mouse('mouseMove', x1 + (x2 - x1) * s / steps, y1 + (y2 - y1) * s / steps, opts)
            await mouse('mouseUp', x2, y2, opts)
            await wait(60)
        }
        const click = async (x, y, opts = {}) => { await mouse('mouseDown', x, y, opts); await mouse('mouseUp', x, y, opts); await wait(60) }
        const type = async text => { win.webContents.insertText(text); await wait(60) }
        const log = (...a) => console.log('  ', ...a)
        const theme = async t => { writeTheme(t); await wait(700) }
        await wait(600)
        try {
            const test = (await import(pathToFileURL(testFile).href)).default
            await test({ win, js, shot, wait, key, mouse, drag, click, type, log, outDir, theme })
        } catch (err) {
            failed = true
            console.log('[FAIL]', err.stack ?? err)
            await shot('failure').catch(() => {})
        }
        if (errors.length) console.log(`[renderer errors] ${errors.length}`)
        console.log(failed ? `== ${name}: FAILED` : `== ${name}: ok`, '→', outDir)
        app.exit(failed ? 1 : 0)
    })
})

await import('../electron/main.js')
