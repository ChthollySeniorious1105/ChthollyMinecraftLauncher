// 冒烟测试：以真实 Electron 环境打开样例文件并截图
// 用法：npx vite build && npx electron scripts/smoke.mjs samples/slides.pptx [...更多文件]
// 不带文件时只截取主页 / 设置页，并通过临时 CML_THEME_FILE 验证主题跟随（浅色 → 深色）
// SMOKE_THEME=dark 让打开文件的截图也使用深色主题
import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import fs from 'node:fs'

const files = process.argv.slice(2).filter(a => !a.startsWith('-') && fs.existsSync(a)).map(a => path.resolve(a))
const outDir = path.resolve('test-output/smoke')
fs.mkdirSync(outDir, { recursive: true })
// 避免 main.js 把测试文件当作启动参数重复打开
process.argv.splice(2)
process.env.LITE_SMOKE = '1'
process.env.LITE_USERDATA ??= path.resolve('test-output/userdata-smoke')

const THEMES = {
    light: { version: 1, id: 'smoke-light', name: '测试浅色', dark: false, bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280', line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff', paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8'] },
    dark: { version: 1, id: 'smoke-dark', name: '测试深色', dark: true, bg: '#11141c', surface: '#1a1e29', panel: '#1a1e29', text: '#e4e8f2', muted: '#97a0b3', line: '#2a3040', field: '#222838', accent: '#7c9cff', accent2: '#5ad1c4', onAccent: '#0d1020', paper: '#181c26', ink: '#d6dbe6', art: ['#7c9cff', '#5ad1c4'] },
}
const themeFile = path.join(outDir, 'theme.json')
const writeTheme = k => { fs.writeFileSync(themeFile + '.tmp', JSON.stringify(THEMES[k])); fs.renameSync(themeFile + '.tmp', themeFile) }
writeTheme(process.env.SMOKE_THEME ?? 'light')
process.env.CML_THEME_FILE = themeFile

let hooked = false
app.on('browser-window-created', (_e, win) => {
    // 只接管主窗口（打印 / 截图用的隐藏窗口也会触发此事件）
    if (hooked) return
    hooked = true
    win.webContents.on('console-message', (e) => {
        if (e.level === 'error' || e.level === 'warning') console.log(`[renderer:${e.level}]`, e.message.slice(0, 400))
    })
    win.webContents.once('did-finish-load', async () => {
        const wait = ms => new Promise(r => setTimeout(r, ms))
        await wait(800)
        await win.webContents.executeJavaScript("localStorage.removeItem('lr.progress')")
        const js = code => win.webContents.executeJavaScript(code)
        const snap = async n => fs.writeFileSync(path.join(outDir, n + '.png'), (await win.webContents.capturePage()).toPNG())
        if (!files.length) {
            const scheme = () => js(`[document.documentElement.dataset.scheme, getComputedStyle(document.documentElement).getPropertyValue('--bg').trim(), [...document.querySelectorAll('#rail .rail-btn')].map(b => b.dataset.id).join('|')].join(' ')`)
            console.log('== home', await scheme())
            await snap('home')
            await js(`window.app.showPage('settings')`)
            await wait(400)
            console.log('== settings hint', await js(`document.body.innerText.includes('主题跟随 CML 启动器')`))
            await snap('settings')
            writeTheme('dark')
            await wait(900)
            console.log('== after dark theme.json', await scheme())
            await snap('settings-dark')
            await js(`window.app.showPage('home')`)
            await wait(400)
            await snap('home-dark')
            writeTheme('light')
            await wait(900)
            console.log('== after light theme.json', await scheme())
        }
        for (const f of files) {
            const name = path.basename(f)
            await win.webContents.executeJavaScript(`window.app.openPaths([${JSON.stringify(f)}])`)
            await wait(3500)
            const report = await win.webContents.executeJavaScript(`(${inspect.toString()})()`).catch(e => ({ error: String(e) }))
            console.log('==', name, JSON.stringify(report))
            const img = await win.webContents.capturePage()
            fs.writeFileSync(path.join(outDir, name + '.png'), img.toPNG())
            // 额外场景
            if (name.endsWith('.pptx')) {
                for (const [k, label] of [['ArrowRight', 'slide2'], ['ArrowRight', 'slide3'], ['ArrowRight', 'slide4'], ['ArrowRight', 'slide5']]) {
                    win.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'Right' })
                    win.webContents.sendInputEvent({ type: 'keyUp', keyCode: 'Right' })
                    await wait(900)
                    fs.writeFileSync(path.join(outDir, `${name}.${label}.png`), (await win.webContents.capturePage()).toPNG())
                }
            }
            if (/\.html?$|\.mht$/.test(name)) {
                await win.webContents.executeJavaScript(`window.app.active.viewer.setView('read')`)
                await wait(900)
                fs.writeFileSync(path.join(outDir, name + '.read.png'), (await win.webContents.capturePage()).toPNG())
                await win.webContents.executeJavaScript(`window.app.active.viewer.setView('source')`)
                await wait(900)
                fs.writeFileSync(path.join(outDir, name + '.source.png'), (await win.webContents.capturePage()).toPNG())
            }
            if (name.endsWith('.tex')) {
                await win.webContents.executeJavaScript(`window.app.active.viewer.scroller.scrollTop = 1400`)
                await wait(500)
                fs.writeFileSync(path.join(outDir, name + '.2.png'), (await win.webContents.capturePage()).toPNG())
                await win.webContents.executeJavaScript(`window.app.active.viewer.scroller.scrollTop = 3200`)
                await wait(500)
                fs.writeFileSync(path.join(outDir, name + '.3.png'), (await win.webContents.capturePage()).toPNG())
            }
        }
        app.quit()
    })
})

// 在页面中执行：收集当前查看器状态
function inspect() {
    const v = window.app.active?.viewer
    if (!v) return { error: 'no viewer' }
    const err = v.content.querySelector('.v-error')
    const r = {
        type: v.source.type,
        subtitle: v.subtitle?.textContent,
        error: err?.textContent,
        caveats: v.caveats,
    }
    if (v.pptx) {
        const frame = v.slides[v.current]?.frame
        r.slides = v.pptx.count
        r.rendered = v.slides.filter(s => s.el).length
        r.currentText = frame?.innerText.slice(0, 120)
        r.failed = v.slides.filter(s => s.frame.classList.contains('failed')).length
    }
    if (v.frame) {
        const d = v.frame.contentDocument
        r.frameTitle = d?.title
        r.scripts = d?.querySelectorAll('script').length
        r.imgs = [...(d?.images ?? [])].map(i => ({ src: i.src.slice(0, 60), ok: i.complete && i.naturalWidth > 0 }))
        r.onload = d?.body?.getAttribute('onload')
    }
    if (v.doc?.pages) {
        r.pages = v.doc.pages.length
        r.rendered = v.pages.filter(p => p.rendered).length
        r.pageText = v.container.innerText.slice(0, 100)
        r.fail = v.container.querySelectorAll('.pp-fail').length
    }
    if (v.toc) { r.toc = v.toc.length; r.chmPage = v.page }
    if (v.article) {
        r.katex = v.article.querySelectorAll('.katex').length
        r.texErr = v.article.querySelectorAll('.tex-err').length
        r.imgs = [...v.article.querySelectorAll('img')].map(i => ({ src: i.src.slice(0, 80), ok: i.complete && i.naturalWidth > 0 }))
        r.hljs = v.article.querySelectorAll('.hljs-keyword, .hljs-string').length
        r.text = v.article.innerText.slice(0, 120)
    }
    return r
}

await import('../electron/main.js')
