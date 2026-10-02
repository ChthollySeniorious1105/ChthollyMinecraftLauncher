// 字体导入、字体下拉框、命令面板、重新打开关闭的标签
import fs from 'node:fs'
import path from 'node:path'

export default async ({ js, shot, wait, key, log }) => {
    const src = path.resolve('.tmp/fonts-src/Caladea-Regular.ttf')
    fs.mkdirSync(path.dirname(src), { recursive: true })
    fs.copyFileSync('C:\\Windows\\Fonts\\Caladea-Regular.ttf', src)

    // 1. 导入字体
    const r = await js(`return window.lite.fonts.import([${JSON.stringify(src)}])`)
    if (!r.added.includes('Caladea-Regular.ttf')) throw new Error('导入失败 ' + JSON.stringify(r))
    const info = r.fonts.find(f => f.file === 'Caladea-Regular.ttf')
    log('字体信息', JSON.stringify(info))
    if (info.family !== 'Caladea' || info.weight !== 400) throw new Error('name 表解析错误')

    // 通过设置页导入（走渲染进程的 FontFace 注册）
    await js(`return window.app.openPaths([${JSON.stringify(src)}])`)
    await wait(1200)
    const loaded = await js(`return [...document.fonts].some(f => f.family.replace(/"/g, '') === 'Caladea' && f.status === 'loaded')`)
    if (!loaded) throw new Error('FontFace 未加载')

    // 系统字体扫描（含中文名）
    const sys = await js(`return window.lite.fonts.system()`)
    log('系统字体数', sys.length, sys.filter(f => /[\u4e00-\u9fa5]/.test(f.label)).slice(0, 6).map(f => f.label + '/' + f.family).join(' '))
    if (sys.length < 10) throw new Error('系统字体扫描失败')

    await js(`return window.app.showPage('settings')`)
    await wait(400)
    await js(`return document.querySelector('.font-list').scrollIntoView()`)
    await shot('settings-fonts')

    // 2. 文档编辑器：下拉框包含导入的字体，应用后渲染
    const ed = await js(`return window.app.newDoc('doc').then(() => true)`)
    await wait(800)
    const docOpts = await js(`return [...window.app.active.editor.fontSel.el.querySelectorAll('optgroup')].map(g => g.label + ':' + g.children.length)`)
    log('文档字体分组', docOpts.join(' '))
    if (!docOpts.some(x => x.startsWith('导入的字体'))) throw new Error('文档字体下拉框缺少导入的字体')
    await js(`return (() => {
        const e = window.app.active.editor
        e.body.innerHTML = '<p>Custom font: The quick brown fox jumps over the lazy dog</p>'
        const r = document.createRange(); r.selectNodeContents(e.body.firstChild)
        const s = getSelection(); s.removeAllRanges(); s.addRange(r)
        e.exec('fontName', '"Caladea", sans-serif')
    })()`)
    await wait(300)
    const fam = await js(`return getComputedStyle(window.app.active.editor.body.querySelector('font, span') ?? window.app.active.editor.body.firstChild).fontFamily`)
    log('文档应用后', fam)
    if (!/Caladea/.test(fam)) throw new Error('文档未应用字体')
    await shot('doc-font')

    // 3. 表格 / 视频（name 格式）
    await js(`return window.app.newDoc('sheet').then(() => true)`)
    await wait(800)
    const sheetHas = await js(`return [...window.app.active.editor.fontSel.el.options].some(o => o.value === 'Caladea')`)
    if (!sheetHas) throw new Error('表格字体下拉框缺少导入的字体')

    // 4. 命令面板
    await js(`window.app.commandPalette()`)
    await wait(300)
    await js(`return (() => { const i = document.querySelector('.pal-input'); i.value = '字体'; i.dispatchEvent(new Event('input')) })()`)
    await wait(200)
    const items = await js(`return [...document.querySelectorAll('.pal-item .pal-label')].map(x => x.textContent).slice(0, 5)`)
    log('命令面板', items.join(' | '))
    const n = await js(`return document.querySelectorAll('.pal-item').length`)
    if (!n) throw new Error('命令面板没有结果')
    await shot('palette')
    await key('Escape')
    await wait(300)
    if (await js(`return !!document.querySelector('.pal-mask')`)) throw new Error('命令面板未关闭')

    // 5. 删除字体
    await js(`return window.lite.fonts.remove('Caladea-Regular.ttf')`)
    const left = await js(`return window.lite.fonts.list().then(r => r.fonts.length)`)
    if (left !== 0) throw new Error('删除失败')
}
