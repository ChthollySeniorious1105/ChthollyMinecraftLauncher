// 图像编辑冒烟测试
const TMP = process.cwd().replace(/\\/g, '/') + '/.tmp'
const WIN = p => p.replace(/\//g, '\\')

export default async ({ js, shot, wait, key, drag, click, log }) => {
    await js(`await window.app.newDoc('image', { width: 1200, height: 800, bg: '#ffffff' })`)
    await wait(600)
    await js(`window.app.active.editor.sizeCanvas(); window.app.active.editor.fitView()`)
    await wait(200)
    const pos = async (x, y) => js(`const e = window.app.active.editor, r = e.wrap.getBoundingClientRect(); return { x: r.left + e.panX + ${x} * e.zoom, y: r.top + e.panY + ${y} * e.zoom }`)
    const px = async (x, y) => js(`const e = window.app.active.editor; const c = e.doc.composite(); return Array.from(c.getContext('2d').getImageData(${x}, ${y}, 1, 1).data)`)

    // 1. 渐变背景
    await js(`const e = window.app.active.editor; e.setColor('fg', '#6366f1'); e.setColor('bg', '#ec4899'); e.setTool('gradient')`)
    let a = await pos(0, 0), b = await pos(1200, 800)
    await drag(a.x + 2, a.y + 2, b.x - 2, b.y - 2, 6)
    log('gradient px', JSON.stringify(await px(600, 400)))

    // 2. 新图层 + 画笔
    await js(`const e = window.app.active.editor; e.newLayerCmd(); e.setColor('fg', '#fde047'); e.opts.size = 40; e.setTool('brush')`)
    a = await pos(150, 600); b = await pos(1050, 250)
    await drag(a.x, a.y, b.x, b.y, 24)
    const brushPx = await px(600, 425)
    log('brush px', JSON.stringify(brushPx))
    // 3. 形状（新图层）
    await js(`const e = window.app.active.editor; e.setColor('fg', '#ffffff'); e.opts.shape = 'ellipse'; e.opts.shapeFill = true; e.setTool('shape')`)
    a = await pos(820, 90); b = await pos(1020, 290)
    await drag(a.x, a.y, b.x, b.y, 8)
    // 4. 文字
    await js(`const e = window.app.active.editor; e.setColor('fg', '#ffffff'); e.opts.fontSize = 96; e.opts.bold = true; e.startText({ x: 80, y: 80 }); e.textBox.textContent = 'LiteEditor'; e.commitText()`)
    await wait(300)
    const layers = await js(`const e = window.app.active.editor; return e.doc.layers.map(l => l.name + (l.text ? '[T]' : ''))`)
    log('layers', JSON.stringify(layers))
    if (layers.length < 4) throw new Error('图层数量不足')
    await shot('painted')

    // 5. 选区 + 调整 + 滤镜
    await js(`const e = window.app.active.editor; e.doc.active = e.doc.layers[0].id; e.setTool('marquee')`)
    a = await pos(100, 450); b = await pos(500, 750)
    await drag(a.x, a.y, b.x, b.y, 6)
    const sel = await js(`return window.app.active.editor.selBounds`)
    log('selection', JSON.stringify(sel))
    if (!sel || sel.w < 390) throw new Error('矩形选框失败')
    // 直接调用处理函数（绕过对话框）
    await js(`const e = window.app.active.editor
        e.applyNamed('hsl', { h: 120, s: 30, l: 0, colorize: false })
        e.applyNamed('gaussian', { r: 12 }, true)`)
    const inside = await px(300, 600), outside = await px(900, 600)
    log('after hsl+blur inside/outside', JSON.stringify(inside), JSON.stringify(outside))
    await js(`window.app.active.editor.deselect()`)
    await js(`window.app.active.editor.applyNamed('vignette', { amount: 60, size: 55 }, true)`)
    await shot('adjusted')

    // 6. 撤销 / 重做
    const before = await js(`return window.app.active.editor.history.index`)
    await key('Z', ['control']); await key('Z', ['control'])
    const mid = await js(`return window.app.active.editor.history.index`)
    await key('Y', ['control'])
    const after = await js(`return window.app.active.editor.history.index`)
    log('history', before, mid, after)
    if (mid !== before - 2 || after !== before - 1) throw new Error('撤销 / 重做失败')

    // 7. 自由变换：缩放文字图层
    await js(`const e = window.app.active.editor; e.doc.active = e.doc.layers.at(-1).id; e.setTool('move'); e.startTransform()`)
    const k = await js(`const e = window.app.active.editor, c = e.xfCorners().se, r = e.wrap.getBoundingClientRect(); return { x: r.left + e.panX + c.x * e.zoom, y: r.top + e.panY + c.y * e.zoom, w: e.xf.w }`)
    await drag(k.x, k.y, k.x + 80, k.y + 30, 8)
    await wait(100)
    await shot('transform')
    await key('Enter')
    const xfw = await js(`const e = window.app.active.editor; return e.doc.activeLayer.canvas.width`)
    log('transform width', k.w, '->', xfw)

    // 8. 魔棒 + 油漆桶
    await js(`const e = window.app.active.editor; e.doc.active = e.doc.layers[2].id; e.opts.tolerance = 20; e.setTool('wand')`)
    a = await pos(920, 190)
    await click(a.x, a.y)
    const wand = await js(`return window.app.active.editor.selBounds`)
    log('wand', JSON.stringify(wand))
    await js(`const e = window.app.active.editor; e.setColor('fg', '#22c55e'); e.fillSelection(false); e.deselect()`)

    // 9. 图像大小 / 旋转
    await js(`window.app.active.editor.rotateImage(90)`)
    const rot = await js(`const e = window.app.active.editor; return [e.doc.w, e.doc.h]`)
    log('rotated', JSON.stringify(rot))
    await js(`window.app.active.editor.rotateImage(-90)`)
    await wait(200)
    await shot('final')

    // 10. 保存 PSD / PNG / JPG，重新打开 PSD
    const out = await js(`const e = window.app.active.editor
        const r = {}
        r.psd = await e.writeTo(${JSON.stringify(TMP + '/test.psd')})
        const png = await e.exportRaster('image/png'); await window.lite.writeFile(${JSON.stringify(TMP + '/test-img.png')}, png); r.png = png.length
        const jpg = await e.exportRaster('image/jpeg'); await window.lite.writeFile(${JSON.stringify(TMP + '/test-img.jpg')}, jpg); r.jpg = jpg.length
        r.layers = e.doc.layers.length; r.dirty = e.dirty
        return r`)
    log('save', JSON.stringify(out))
    if (!out.psd || out.png < 10000) throw new Error('保存失败')
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/test.psd'))}])`)
    await wait(1200)
    const re = await js(`const e = window.app.active.editor; return { name: e.name, w: e.doc.w, h: e.doc.h, layers: e.doc.layers.map(l => l.name + ':' + l.opacity) }`)
    log('reopen psd', JSON.stringify(re))
    if (re.layers.length !== out.layers) throw new Error('PSD 图层数不一致')
    await shot('reopened-psd')
    // 打开 PNG
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/test-img.png'))}])`)
    await wait(800)
    const rp = await js(`const e = window.app.active.editor; return [e.doc.w, e.doc.h, e.doc.layers.length]`)
    log('reopen png', JSON.stringify(rp))
    // 菜单
    await js(`document.querySelectorAll('.e-menu')[5].click()`)
    await wait(150)
    await js(`const it = [...document.querySelectorAll('.cmenu-item')].find(x => x.textContent.includes('艺术效果')); it?.dispatchEvent(new MouseEvent('mouseenter'))`)
    await wait(200)
    await shot('menu')
    await key('Escape')
}
