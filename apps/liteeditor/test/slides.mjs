// 演示文稿冒烟测试
const TMP = process.cwd().replace(/\\/g, '/') + '/.tmp'

export default async ({ js, shot, wait, drag, click, key, log }) => {
    // 1. 示例：项目介绍
    await js(`await window.app.newDoc('slides', { sample: 'pitch' })`)
    await wait(700)
    await shot('pitch')
    const info = await js(`const e = window.app.active.editor; return { n: e.deck.slides.length, els: e.slide.els.length, zoom: e.zoom }`)
    log('pitch', JSON.stringify(info))
    if (info.n !== 5) throw new Error('示例应有 5 页')
    await js(`window.app.active.editor.select(2)`)
    await wait(300)
    await shot('pitch-slide3')
    await js(`window.app.active.editor.select(3)`)
    await wait(300)
    await shot('pitch-chart')

    // 2. 新建空白演示，插入对象
    await js(`await window.app.newDoc('slides', {})`)
    await wait(500)
    await js(`const e = window.app.active.editor
        e.slide.els[0].html = '季度总结'
        e.slide.els[1].html = '2026 年第三季度'
        e.renderAll(); e.commit('标题')
        e.addSlide('content')
        e.slide.els[0].html = '要点'
        e.slide.els[1].html = '<ul><li>收入同比增长 32%</li><li>新用户 12 万</li><li>发布 3 个新版本</li></ul>'
        e.renderAll(); e.commit('要点')`)
    await wait(200)
    // 用鼠标绘制一个形状
    const r = await js(`const e = window.app.active.editor; const b = e.slideHost.getBoundingClientRect(); return { x: b.left, y: b.top, k: e.zoom }`)
    await js(`window.app.active.editor.toggleInsert({ type: 'shape', shape: 'star' })`)
    await drag(r.x + 1400 * r.k, r.y + 300 * r.k, r.x + 1750 * r.k, r.y + 640 * r.k, 8)
    await wait(200)
    const afterShape = await js(`const e = window.app.active.editor; const s = e.selEls()[0]; return s && { type: s.type, shape: s.shape, x: s.x, y: s.y, w: s.w, h: s.h }`)
    log('shape', JSON.stringify(afterShape))
    if (!afterShape || afterShape.shape !== 'star') throw new Error('鼠标绘制形状失败')
    // 拖动移动形状
    await drag(r.x + 1575 * r.k, r.y + 470 * r.k, r.x + 1475 * r.k, r.y + 520 * r.k, 8)
    const moved = await js(`const s = window.app.active.editor.selEls()[0]; return { x: s.x, y: s.y }`)
    log('moved', JSON.stringify(moved))
    if (moved.x === afterShape.x) throw new Error('拖动移动失败')
    // 缩放控制点（右下角）
    const se = await js(`const h = document.querySelector('.sl-handle.se').getBoundingClientRect(); return { x: h.left + h.width / 2, y: h.top + h.height / 2 }`)
    await drag(se.x, se.y, se.x + 60, se.y + 40, 6)
    const resized = await js(`const s = window.app.active.editor.selEls()[0]; return { w: s.w, h: s.h }`)
    log('resized', JSON.stringify(resized))
    if (resized.w <= afterShape.w) throw new Error('缩放失败')
    await shot('shape')

    // 图表 / 公式 / 图片 / 表格 / 图标（API）
    await js(`const e = window.app.active.editor, { defaultChart } = await import('/src/editors/slides/model.js').catch(() => ({}))
        e.addSlide('titleOnly')
        e.slide.els[0].html = '图表与公式'
        const c = document.createElement('canvas'); c.width = 400; c.height = 260
        const g = c.getContext('2d'); const gr = g.createLinearGradient(0, 0, 400, 260); gr.addColorStop(0, '#f97316'); gr.addColorStop(1, '#8b5cf6'); g.fillStyle = gr; g.fillRect(0, 0, 400, 260)
        g.fillStyle = '#fff'; g.font = 'bold 40px sans-serif'; g.fillText('图片', 150, 145)
        await e.insertImage({ dataURL: c.toDataURL(), width: 400, height: 260 })
        const img = e.selEls()[0]; img.x = 120; img.y = 260; img.radius = 24
        e.addEls([e.makeEl({ type: 'chart', chart: { kind: 'bar', title: '销量', labels: ['一月', '二月', '三月'], series: [{ name: 'A', values: [3, 5, 8], color: '#2563eb' }], legend: true }, x: 620, y: 240, w: 700, h: 420 })], '图表')
        e.addEls([e.makeEl({ type: 'math', tex: '\\\\frac{-b\\\\pm\\\\sqrt{b^2-4ac}}{2a}', size: 60, color: '#0f172a', x: 1360, y: 300, w: 480, h: 200 })], '公式')
        e.addEls([e.makeEl({ type: 'table', rows: [['指标', '数值'], ['收入', '1.2 亿'], ['用户', '86 万']], style: { header: true, band: true, color: '#2563eb', border: '#cbd5e1', size: 28 }, x: 120, y: 720, w: 700, h: 230 })], '表格')`)
    await wait(400)
    await shot('objects')

    // 对齐：选中图表与表格，左对齐
    await js(`const e = window.app.active.editor; e.setSel(e.slide.els.filter(x => x.type === 'chart' || x.type === 'table').map(x => x.id)); e.alignSel('left')`)
    const al = await js(`const e = window.app.active.editor; return e.slide.els.filter(x => x.type === 'chart' || x.type === 'table').map(x => x.x)`)
    log('aligned', JSON.stringify(al))
    if (al[0] !== al[1]) throw new Error('左对齐失败')

    // 主题切换
    await js(`window.app.active.editor.setTheme('tech')`)
    await wait(300)
    await shot('theme-tech')

    // 幻灯片操作：复制、移动、撤销
    const before = await js(`return window.app.active.editor.deck.slides.length`)
    await js(`const e = window.app.active.editor; e.duplicateSlide(); e.moveSlide(e.current, 0)`)
    const mid = await js(`return window.app.active.editor.deck.slides.length`)
    await key('Z', ['control']); await key('Z', ['control'])
    await wait(200)
    const after = await js(`return window.app.active.editor.deck.slides.length`)
    log('slides', before, mid, after)
    if (mid !== before + 1 || after !== before) throw new Error('复制 / 撤销幻灯片失败')

    // 文字编辑：双击标题并输入
    await js(`window.app.active.editor.select(0)`)
    await wait(200)
    const t = await js(`const e = window.app.active.editor, el = e.slide.els[0], k = e.zoom, b = e.slideHost.getBoundingClientRect(); return { x: b.left + (el.x + el.w / 2) * k, y: b.top + (el.y + el.h / 2) * k }`)
    await click(t.x, t.y)
    await js(`window.app.active.editor.startEditing(window.app.active.editor.slide.els[0])`)
    await js(`document.execCommand('selectAll'); document.execCommand('insertText', false, '新的标题')`)
    await key('Escape')
    await wait(200)
    const title = await js(`return window.app.active.editor.slide.els[0].html`)
    log('title', title)
    if (!title.includes('新的标题')) throw new Error('文字编辑失败')
    await shot('edited')

    // 3. 放映（示例文稿）
    await js(`window.app.activate(window.app.tabs[0]); window.app.active.editor.present(0)`)
    await wait(1200)
    await shot('present-1')
    await key('Right'); await wait(900)
    await key('Right'); await wait(900)
    await shot('present-2')
    await js(`window.app.active.editor.presenter.togglePresenter()`)
    await wait(500)
    await shot('presenter-view')
    await key('Escape')
    await wait(500)

    // 4. 保存 / 重新打开 / 导出
    const saved = await js(`const e = window.app.active.editor
        const ok = await e.writeTo(${JSON.stringify(TMP + '/test.lslide')})
        const pptx = await e.exportPPTX()
        await window.lite.writeFile(${JSON.stringify(TMP + '/test.pptx')}, pptx)
        const pdf = await e.exportPDF()
        await window.lite.writeFile(${JSON.stringify(TMP + '/test-slides.pdf')}, pdf)
        const png = await e.slidePNG(0)
        await window.lite.writeFile(${JSON.stringify(TMP + '/test-slide.png')}, png)
        return { ok, dirty: e.dirty, pptx: pptx.length, pdf: pdf.length, png: png.length }`)
    log('export', JSON.stringify(saved))
    if (!saved.ok || saved.dirty || saved.pptx < 10000 || saved.pdf < 10000 || saved.png < 5000) throw new Error('保存 / 导出失败')
    await js(`await window.app.openPaths([${JSON.stringify(TMP.replace(/\//g, '\\') + '\\test.lslide')}])`)
    await wait(600)
    const re = await js(`const e = window.app.active.editor; return { name: e.name, n: e.deck.slides.length }`)
    log('reopen', JSON.stringify(re))
    if (re.n !== 5) throw new Error('重新打开失败')
    // 导入刚导出的 PPTX
    await js(`await window.app.openPaths([${JSON.stringify(TMP.replace(/\//g, '\\') + '\\test.pptx')}])`)
    await wait(1200)
    const imp = await js(`const e = window.app.active.editor; return { name: e.name, n: e.deck.slides.length, els: e.deck.slides.map(s => s.els.length), note: e.deck.importNote }`)
    log('import pptx', JSON.stringify(imp))
    await shot('imported-pptx')
    await js(`window.app.active.editor.select(3)`)
    await wait(300)
    await shot('imported-pptx-4')
    // 菜单
    await js(`document.querySelectorAll('.e-menu')[3].click()`)
    await wait(200)
    await shot('menu')
    await key('Escape')
}
