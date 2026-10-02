// 几何画板冒烟测试
export default async ({ theme, js, shot, wait, drag, click, key, log, mouse }) => {
    const mouseMoveTo = async (x, y) => { await mouse('mouseMove', x, y); await wait(120) }
    // 1. 三角形五心示例
    await js(`await window.app.newDoc('geo', { sample: 'triangle' })`)
    await wait(600)
    await shot('triangle')
    const tri = await js(`const e = window.app.active.editor, s = e.scene
        const v = n => s.valueText(s.byName(n))
        return { n: s.objects.length, O: v('O'), G: v('G'), H: v('H'), ratio: v('比值') }`)
    log('triangle', JSON.stringify(tri))
    if (Math.abs(parseFloat(tri.ratio) - 2) > 1e-6) throw new Error('欧拉线 GH/OG 比值应为 2：' + tri.ratio)

    // 2. 拖动自由点 A（通过鼠标），依赖对象随之更新
    const pos = await js(`const e = window.app.active.editor, s = e.scene
        const { toScreen } = await import('/src/editors/geo/render.js').catch(() => ({}))
        const A = s.val(s.byName('A').id), r = e.canvas.getBoundingClientRect()
        const x = r.left + e.view.w / 2 + (A.x - e.view.x0) * e.view.s, y = r.top + e.view.h / 2 - (A.y - e.view.y0) * e.view.s
        return { x, y, O: s.valueText(s.byName('O')) }`)
    await drag(pos.x, pos.y, pos.x - 60, pos.y + 40, 10)
    await wait(200)
    const after = await js(`const s = window.app.active.editor.scene; return { A: s.valueText(s.byName('A')), O: s.valueText(s.byName('O')), ratio: s.valueText(s.byName('比值')), undo: window.app.active.editor.history.index }`)
    log('after drag', JSON.stringify(after))
    if (after.O === pos.O) throw new Error('拖动 A 后外心 O 没有更新')
    if (Math.abs(parseFloat(after.ratio) - 2) > 1e-6) throw new Error('拖动后比值不再为 2')
    await shot('triangle-dragged')
    await key('Z', ['control'])
    await wait(150)
    const undone = await js(`const s = window.app.active.editor.scene; return s.valueText(s.byName('O'))`)
    if (undone !== pos.O) throw new Error('撤销后 O 未恢复：' + undone + ' vs ' + pos.O)
    log('undo ok')

    // 3. 函数示例
    await js(`await window.app.newDoc('geo', { sample: 'function' })`)
    await wait(600)
    await shot('function')
    const fn = await js(`const s = window.app.active.editor.scene; return s.objects.map(o => o.name + ':' + s.valueText(o)).join(' | ')`)
    log('function', fn)

    // 4. 空白画板中用鼠标作图：线段、圆、交点、中点、度量
    await js(`await window.app.newDoc('geo', {})`)
    await wait(500)
    const r = await js(`const e = window.app.active.editor, r = e.canvas.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }`)
    await key('S')
    await click(r.x - 150, r.y + 50)
    await click(r.x + 150, r.y + 50)
    await key('C')
    await click(r.x - 150, r.y + 50)
    await click(r.x - 20, r.y - 60)
    await key('I')
    await click(r.x, r.y + 50)
    // 选择圆：圆心 (-150, 50)，经过 (-20,-60)：半径约 170
    await click(r.x - 150, r.y + 50 - 170.3)
    await key('M')
    await click(r.x - 150, r.y + 50)
    await click(r.x - 20, r.y - 60)
    await key('Escape')
    await wait(200)
    const built = await js(`const s = window.app.active.editor.scene; return s.objects.map(o => o.name + '=' + s.definition(o) + '→' + s.valueText(o))`)
    log('built', JSON.stringify(built))
    if (built.length < 7) throw new Error('鼠标作图对象数量不足：' + built.length)
    await js(`const e = window.app.active.editor, s = e.scene
        e.selectOnly([s.objects.find(o => o.type === 'segment').id])
        e.measureItems()[0].run()
        e.selectOnly([s.objects.find(o => o.type === 'circle').id])
        e.measureItems().find(i => i.label === '面积').run()
        const pts = s.objects.filter(o => s.val(o.id)?.kind === 'point').slice(0, 3).map(o => o.id)
        e.selectOnly(pts)
        e.measureItems()[0].run()`)
    await wait(200)
    await js(`const e = window.app.active.editor; e.selectOnly([e.scene.objects.find(o => o.type === 'circle').id])`)
    await shot('construct')
    const ms = await js(`const s = window.app.active.editor.scene; return s.objects.filter(o => o.type === 'measure').map(o => s.annotationText(o))`)
    log('measures', JSON.stringify(ms))

    // 5. 变换 + 轨迹 + 函数（通过 API）
    await js(`const e = window.app.active.editor, s = e.scene
        const circ = s.objects.find(o => o.type === 'circle')
        const P = e.addObject({ type: 'pointOn', path: circ.id, t: 1 })
        const Q = e.addObject({ type: 'point', x: 4, y: -2 })
        const M = e.addObject({ type: 'midpoint', a: P.id, b: Q.id })
        e.addObject({ type: 'locus', point: M.id, driver: P.id })
        const seg = s.objects.find(o => o.type === 'segment')
        e.addObject({ type: 'reflect', src: circ.id, line: seg.id })
        e.addObject({ type: 'func', expr: '0.3x^2 - 3' })
        e.commit('测试'); e.afterChange()`)
    await wait(300)
    await shot('locus')

    // 6. 保存、重新打开、导出
    const out = await js(`const e = window.app.active.editor
        const ok = await e.writeTo(${JSON.stringify(process.cwd().replace(/\\/g, '/') + '/.tmp/test.lgeo')})
        const png = await e.exportPNG(), svg = e.exportSVG()
        await window.lite.writeFile(${JSON.stringify(process.cwd().replace(/\\/g, '/') + '/.tmp/test-geo.svg')}, svg)
        return { ok, dirty: e.dirty, n: e.scene.objects.length, png: png.length, svg: svg.length }`)
    log('save', JSON.stringify(out))
    if (!out.ok || out.dirty || out.png < 5000 || out.svg < 1000) throw new Error('保存 / 导出失败')
    await js(`await window.app.closeTab(window.app.active); await window.app.openPaths([${JSON.stringify(process.cwd() + '\\.tmp\\test.lgeo')}])`)
    await wait(600)
    const re = await js(`const e = window.app.active.editor; return { name: e.name, n: e.scene.objects.length, locus: e.scene.val(e.scene.objects.find(o => o.type === 'locus').id)?.pts.length }`)
    log('reopen', JSON.stringify(re))
    if (re.n !== out.n) throw new Error('重新打开后对象数量不一致')
    await shot('reopened')

    // 7. 菜单与右键菜单
    await js(`document.querySelectorAll('.e-menu')[4].click()`)
    await wait(200)
    await shot('menu')
    await key('Escape')

    // 8. 圆锥曲线示例
    await js(`await window.app.newDoc('geo', { sample: 'conic' })`)
    await wait(600)
    await shot('conic-sample')
    const cs = await js(`const s = window.app.active.editor.scene
        return { sum: s.valueText(s.byName('和')), eq: s.annotationText(s.objects.find(o => o.m === 'equation')), h: s.valueText(s.byName('h')), p: s.valueText(s.byName('p')) }`)
    log('conic sample', JSON.stringify(cs))
    if (Math.abs(parseFloat(cs.sum) - 10) > 1e-6) throw new Error('|PF1| + |PF2| 应为 2a = 10：' + cs.sum)
    if (!cs.h.startsWith('双曲线') || !cs.p.startsWith('抛物线')) throw new Error('方程没有识别为双曲线 / 抛物线')
    // 拖动 P：和保持不变
    const pp = await js(`const e = window.app.active.editor, s = e.scene, P = s.val(s.byName('P').id), r = e.canvas.getBoundingClientRect()
        return { x: r.left + e.view.w / 2 + (P.x - e.view.x0) * e.view.s, y: r.top + e.view.h / 2 - (P.y - e.view.y0) * e.view.s }`)
    await drag(pp.x, pp.y, pp.x - 120, pp.y + 160, 12)
    const sum2 = await js(`const s = window.app.active.editor.scene; return s.valueText(s.byName('和'))`)
    log('after drag P', sum2)
    if (Math.abs(parseFloat(sum2) - 10) > 1e-6) throw new Error('拖动 P 后和改变了：' + sum2)

    // 9. 用鼠标画椭圆（两焦点 + 一点），再求与直线的交点、切线
    await js(`await window.app.newDoc('geo', {})`)
    await wait(500)
    const c = await js(`const e = window.app.active.editor, r = e.canvas.getBoundingClientRect(); e.opts.snap = true; return { x: r.left + r.width / 2, y: r.top + r.height / 2, s: e.view.s }`)
    await key('E')
    await click(c.x - 3 * c.s, c.y)
    await click(c.x + 3 * c.s, c.y)
    await mouseMoveTo(c.x + 2 * c.s, c.y - 2.5 * c.s)
    await shot('ellipse-preview')
    await click(c.x, c.y - 4 * c.s)
    const el = await js(`const s = window.app.active.editor.scene, o = s.objects.find(o => o.type === 'ellipse'), v = s.val(o.id); return { a: v.a, b: v.b, text: s.valueText(o) }`)
    log('ellipse by mouse', JSON.stringify(el))
    if (Math.abs(el.a - 5) > 0.05 || Math.abs(el.b - 4) > 0.05) throw new Error('鼠标画的椭圆半轴不对')
    await key('L')
    await click(c.x - 6 * c.s, c.y - 1 * c.s)
    await click(c.x + 6 * c.s, c.y - 1 * c.s)
    await js(`const e = window.app.active.editor, s = e.scene; e.setTool('intersect'); e.finishTool([s.objects.find(o => o.type === 'ellipse').id, s.objects.find(o => o.type === 'line').id]); e.setTool('select')`)
    const xs = await js(`const s = window.app.active.editor.scene; return s.objects.filter(o => o.type === 'intersect').map(o => s.valueText(o))`)
    log('ellipse ∩ line', JSON.stringify(xs))
    if (xs.length !== 2) throw new Error('椭圆与直线应有两个交点')
    await js(`const e = window.app.active.editor, s = e.scene
        const T = e.addObject({ type: 'point', x: 0, y: 6 })
        e.setTool('tangent'); e.finishTool([T.id, s.objects.find(o => o.type === 'ellipse').id]); e.setTool('select')`)
    const tg = await js(`const s = window.app.active.editor.scene; return s.objects.filter(o => o.type === 'tangent').length`)
    log('tangents', tg)
    if (tg !== 2) throw new Error('椭圆外一点应有两条切线')
    await js(`const e = window.app.active.editor, s = e.scene, id = s.objects.find(o => o.type === 'ellipse').id; e.addConicPart(id, 'focus'); e.addConicPart(id, 'directrix'); e.addConicPart(id, 'vertex')`)

    // 10. 输入栏：方程、函数、点、参数
    const cmds = ['x²/9 − y²/4 = 1', 'y² = 4x', 'f(x) = √(x+4)', 'P = (1, 2)', 'k = 2', 'x·y = k', 'x³ + y³ = 3xy', '√2 + 3²']
    for (const cmd of cmds) {
        await js(`const e = window.app.active.editor; e.focusInput(); e.inputBox.value = ${JSON.stringify(cmd)}; e.inputBox.dispatchEvent(new Event('input')); return 1`)
        await key('Return')
        await wait(80)
    }
    const res = await js(`const s = window.app.active.editor.scene; return s.objects.slice(-8).map(o => o.name + ': ' + s.definition(o) + ' → ' + s.valueText(o))`)
    log('input bar', JSON.stringify(res, null, 1))
    const kinds = await js(`const s = window.app.active.editor.scene; return s.objects.filter(o => o.type === 'equation').map(o => s.val(o.id)?.kind + ':' + (s.val(o.id)?.shape ?? ''))`)
    log('equation kinds', JSON.stringify(kinds))
    if (kinds.join() !== 'conic:hyperbola,conic:parabola,conic:hyperbola,curve:') throw new Error('方程识别错误：' + kinds.join())
    await js(`window.app.active.editor.fitAll()`)
    await wait(200)
    await shot('conics')

    // 11. 数学键盘：在输入栏中键入 y=√(x²+1)
    await js(`const e = window.app.active.editor; e.focusInput(); if (!document.querySelector('.math-kb.show')) document.querySelector('.geo-inputbar .mk-toggle').click(); return 1`)
    await wait(300)
    log('keyboard open', await js(`return !!document.querySelector('.math-kb.show')`))
    const press = async label => js(`const b = [...document.querySelectorAll('.math-kb .mk-key')].find(k => k.textContent === ${JSON.stringify(label)}); if (!b) throw new Error('没有按键 ' + ${JSON.stringify(label)}); b.dispatchEvent(new PointerEvent('pointerup', { bubbles: true })); return 1`)
    await js(`const e = window.app.active.editor; e.inputBox.value = 'y='; e.inputBox.setSelectionRange(2, 2); return 1`)
    for (const k of ['√', 'x', 'x²', '+', '1']) { await press(k); log('  after', k, await js(`return window.app.active.editor.inputBox.value`)) }
    const typed = await js(`return window.app.active.editor.inputBox.value`)
    log('keyboard typed', typed)
    if (typed !== 'y=sqrt(x^2+1)') throw new Error('数学键盘输入错误：' + typed)
    await shot('math-keyboard')
    await js(`document.querySelector('.math-kb .mk-enter').dispatchEvent(new PointerEvent('pointerup', { bubbles: true })); return 1`)
    await wait(150)
    const last = await js(`const s = window.app.active.editor.scene, o = s.objects.at(-1); return o.type + ' ' + (o.expr ?? '')`)
    log('keyboard enter →', last)
    if (!last.startsWith('func')) throw new Error('键盘 Enter 没有添加函数')
    await js(`document.querySelector('.math-kb [title="关闭键盘"]').dispatchEvent(new PointerEvent('pointerup', { bubbles: true })); return 1`)

    // 12. 圆锥曲线对话框（对话框中的输入框带数学键盘）
    await js(`window.app.active.editor.addConicDialog(); return 1`)
    await wait(300)
    const kbInDialog = await js(`return document.querySelectorAll('.modal .mk-toggle').length`)
    log('dialog keyboard toggles', kbInDialog)
    if (kbInDialog < 3) throw new Error('对话框中没有数学键盘按钮')
    await shot('conic-dialog')
    await js(`document.querySelector('.modal .btn.primary').click(); return 1`)
    await wait(200)
    const std = await js(`const s = window.app.active.editor.scene, o = s.objects.find(o => o.type === 'conicStd'); return o && s.valueText(o)`)
    log('conicStd', std)
    if (!std?.startsWith('椭圆')) throw new Error('标准方程椭圆创建失败')

    // 13. 保存并重新打开
    const f2 = process.cwd().replace(/\\/g, '/') + '/.tmp/conic.lgeo'
    const n1 = await js(`const e = window.app.active.editor; await e.writeTo(${JSON.stringify(f2)}); return e.scene.objects.length`)
    await js(`await window.app.closeTab(window.app.active); await window.app.openPaths([${JSON.stringify(f2.replace(/\//g, '\\'))}])`)
    await wait(500)
    const n2 = await js(`const s = window.app.active.editor.scene; return { n: s.objects.length, undef: s.objects.filter(o => !s.val(o.id)).map(o => o.name) }`)
    log('reopen conic', n1, JSON.stringify(n2))
    if (n2.n !== n1) throw new Error('重新打开后数量不一致')
    await theme('dark')
    await wait(400)
    await shot('conics-dark')
}
