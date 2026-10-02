// 界面测试：打开文件 → 打印 / 导出 PDF 对话框 → 转换对话框 → 批量转换页面，并截图
import { app } from 'electron'
import path from 'node:path'
import fs from 'node:fs'

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..')
const out = path.join(root, 'test-output', 'ui')
fs.mkdirSync(out, { recursive: true })
process.argv.splice(2)
let hooked = false
app.on('browser-window-created', (_e, win) => {
    if (hooked) return
    hooked = true
    win.webContents.on('console-message', e => { if (e.level === 'error') console.log('  [renderer]', e.message.slice(0, 300)) })
    win.webContents.once('did-finish-load', async () => {
        const wait = ms => new Promise(r => setTimeout(r, ms))
        const js = code => win.webContents.executeJavaScript(code)
        const shot = async name => fs.writeFileSync(path.join(out, name + '.png'), (await win.webContents.capturePage()).toPNG())
        await wait(800)
        await js(`window.app.openPaths([${JSON.stringify(path.join(root, 'samples', 'paper.tex'))}])`)
        await wait(2500)
        // 输出菜单
        await js(`document.querySelector('.viewer:not([hidden]) [title="打印 / 导出 / 转换"]').click()`)
        await wait(400)
        await shot('1-output-menu')
        console.log('menu items:', await js(`[...document.querySelectorAll('.popover .menu-item span:not(.menu-hint)')].map(s => s.textContent).join(' | ')`))
        await js(`document.querySelectorAll('.popover .menu-item')[1].click()`)
        await wait(2500)
        await shot('2-print-dialog')
        console.log('print dialog:', await js(`document.querySelector('.print-dialog')?.innerText.replace(/\\n+/g, ' ')`))
        await js(`[...document.querySelectorAll('.print-dialog .btn')].find(b => b.textContent === '取消').click()`)
        await wait(400)
        // 转换对话框
        await js(`window.app.convertDialog(window.app.active.viewer.source); true`)
        await wait(600)
        await js(`[...document.querySelectorAll('.cv-target')].find(b => b.textContent.includes('Markdown'))?.click()`)
        await wait(300)
        await shot('3-convert-dialog')
        console.log('convert targets:', await js(`[...document.querySelectorAll('.cv-target')].map(b => b.innerText.replace(/\\n/g, ':')).join(' | ')`))
        console.log('detail:', await js(`document.querySelector('.cv-detail')?.innerText.replace(/\\n+/g, ' / ')`))
        await js(`[...document.querySelectorAll('.cv-dialog .btn')].find(b => b.textContent === '取消').click()`)
        await wait(300)
        // 批量转换页面
        await js(`window.app.showPage('convert')`)
        await wait(600)
        await js(`window.app.convertPage.add(${JSON.stringify(['samples/readme.md', 'samples/song_b.ogg', 'samples/sheet.xlsx', 'samples/formats/document.rtf', 'samples/images/sample_1.png'].map(p => path.join(root, p)))})`)
        await wait(800)
        await js(`window.app.convertPage.outDir = ${JSON.stringify(path.join(root, 'test-output', 'batch'))}`)
        await shot('4-batch-page')
        await js(`window.app.convertPage.run()`)
        for (let i = 0; i < 40; i++) { await wait(500); if (!(await js('window.app.convertPage.running'))) break }
        await shot('5-batch-done')
        console.log('batch:', await js(`window.app.convertPage.items.map(i => i.source.name + ' ' + i.status + ' ' + i.message).join('\\n')`))
        app.quit()
    })
})
await import('../electron/main.js')
