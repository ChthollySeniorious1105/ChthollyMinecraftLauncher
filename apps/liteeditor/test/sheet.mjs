// 电子表格冒烟测试
const TMP = process.cwd().replace(/\\/g, '/') + '/.tmp'
const WIN = p => p.replace(/\//g, '\\')

export default async ({ js, shot, wait, key, type, click, drag, log }) => {
    // 1. 家庭预算示例
    await js(`await window.app.newDoc('sheet', { sample: 'budget' })`)
    await wait(800)
    await shot('budget')
    const b = await js(`const e = window.app.active.editor, v = (r, c) => e.value(r, c); return { h5: v(4, 7), b13: v(12, 1), h13: v(12, 7), b14: v(13, 1), j6: v(5, 9), e16: v(15, 4), charts: e.sheet.meta.charts.length }`)
    log('budget', JSON.stringify(b))
    if (b.h5 !== 110500 || b.b13 !== 11250 || b.b14 !== 6750) throw new Error('预算公式计算错误')

    // 修改数据 → 依赖重算
    await js(`const e = window.app.active.editor; e.selectCell(4, 1)`)
    await type('20000')
    await key('Enter')
    await wait(150)
    const re = await js(`const e = window.app.active.editor; return { b5: e.value(4, 1), h5: e.value(4, 7), b14: e.value(13, 1), sel: e.sel.r }`)
    log('after edit', JSON.stringify(re))
    if (re.b5 !== 20000 || re.h5 !== 112500 || re.b14 !== 8750 || re.sel !== 5) throw new Error('编辑后重算失败')
    await key('Z', ['control'])
    const un = await js(`return window.app.active.editor.value(4, 1)`)
    log('undo', un)
    if (un !== 18000) throw new Error('撤销失败')

    // 2. 成绩统计
    await js(`await window.app.newDoc('sheet', { sample: 'grades' })`)
    await wait(800)
    await shot('grades')
    const gr = await js(`const e = window.app.active.editor; return { total: e.value(3, 7), rank: e.value(3, 9), grade: e.value(3, 10), avg: e.value(15, 2), look: e.value(19, 4), pass: e.value(17, 3) }`)
    log('grades', JSON.stringify(gr))
    if (gr.total !== 463 || gr.look !== 99) throw new Error('成绩公式错误')
    // 按总分降序排序
    await js(`const e = window.app.active.editor; e.selectCell(5, 7); e.quickSort(true)`)
    await wait(200)
    const top = await js(`const e = window.app.active.editor; return [e.value(3, 1), e.value(3, 7), e.value(3, 9)]`)
    log('sorted top', JSON.stringify(top))
    if (top[2] !== 1) throw new Error('排序后名次错误')
    await shot('grades-sorted')

    // 3. 空白表格：输入公式、格式、合并、填充
    await js(`await window.app.newDoc('sheet', {})`)
    await wait(500)
    for (const [i, v] of [['A1', '月份'], ['B1', '销售额'], ['A2', '一月'], ['B2', '1200'], ['A3', '二月'], ['B3', '1500']].entries()) void i
    await js(`const e = window.app.active.editor
        const put = (r, c, t) => e.setInput(r, c, t)
        put(0, 0, '月份'); put(0, 1, '销售额'); put(0, 2, '同比')
        put(1, 0, '一月'); put(1, 1, '1200'); put(2, 0, '二月'); put(2, 1, '1500')
        put(1, 2, '=B2/1000-1')`)
    // 填充柄：A2:B3 向下填充到第 12 行
    await js(`const e = window.app.active.editor; e.selectRange({ r1: 1, c1: 0, r2: 2, c2: 1 }); e.fillRange({ r1: 1, c1: 0, r2: 2, c2: 1 }, { r1: 1, c1: 0, r2: 11, c2: 1 })`)
    const filled = await js(`const e = window.app.active.editor; return [e.value(11, 0), e.value(11, 1), e.value(5, 0)]`)
    log('filled', JSON.stringify(filled))
    await js(`const e = window.app.active.editor
        e.selectRange({ r1: 1, c1: 2, r2: 1, c2: 2 }); e.fillRange({ r1: 1, c1: 2, r2: 1, c2: 2 }, { r1: 1, c1: 2, r2: 11, c2: 2 })
        e.setInput(12, 0, '合计'); e.setInput(12, 1, '=SUM(B2:B12)'); e.setInput(12, 2, '=AVERAGE(C2:C12)')
        e.selectRange({ r1: 0, c1: 0, r2: 0, c2: 2 }); e.applyStyle({ b: true, fill: '#1f4e79', color: '#ffffff', ha: 'center' })
        e.selectRange({ r1: 1, c1: 2, r2: 12, c2: 2 }); e.applyStyle({ fmt: '0.0%' })
        e.selectRange({ r1: 1, c1: 1, r2: 12, c2: 1 }); e.applyStyle({ fmt: '#,##0' })
        e.selectRange({ r1: 0, c1: 0, r2: 12, c2: 2 }); e.applyBorder('all', 'thin #94a3b8')
        e.setInput(14, 0, '销售报表'); e.selectRange({ r1: 14, c1: 0, r2: 14, c2: 2 }); e.mergeCells('center')
        e.selectRange({ r1: 0, c1: 0, r2: 11, c2: 1 }); await e.insertChart('line')`)
    await wait(300)
    const s3 = await js(`const e = window.app.active.editor; return { sum: e.value(12, 1), avg: e.value(12, 2), c12: e.value(11, 2), merges: e.sheet.meta.merges.length, charts: e.sheet.meta.charts.length }`)
    log('blank', JSON.stringify(s3))
    // 公式编辑：键盘输入 =SUM( 并用方向键选择引用
    await js(`const e = window.app.active.editor; e.selectCell(13, 1)`)
    await type('=MAX(B2:B12)')
    await key('Enter')
    const mx = await js(`return window.app.active.editor.value(13, 1)`)
    log('max', mx)
    await js(`window.app.active.editor.selectCell(13, 1)`)
    await shot('blank-edited')
    // 公式输入中的自动补全
    await js(`window.app.active.editor.selectCell(15, 1)`)
    await type('=VLO')
    await wait(200)
    await shot('autocomplete')
    await key('Escape'); await key('Escape')

    // 多工作表 + 跨表引用
    await js(`const e = window.app.active.editor; e.addSheet('汇总'); e.setInput(0, 0, "=Sheet1!B13*2")`)
    const cross = await js(`return window.app.active.editor.value(0, 0)`)
    log('cross sheet', cross)
    if (cross !== s3.sum * 2) throw new Error('跨表引用失败')
    await js(`window.app.active.editor.switchSheet(0)`)

    // 4. 保存 XLSX / LSHEET / CSV / PDF，重新打开
    const out = await js(`const e = window.app.active.editor
        const r = {}
        r.xlsx = await e.writeTo(${JSON.stringify(TMP + '/test.xlsx')})
        r.lsheet = await e.writeTo(${JSON.stringify(TMP + '/test.lsheet')})
        const csv = await e.formats().find(f => f.ext === 'csv').write(); await window.lite.writeFile(${JSON.stringify(TMP + '/test.csv')}, csv); r.csv = csv.length
        const pdf = await e.exports()[0].write(); await window.lite.writeFile(${JSON.stringify(TMP + '/test-sheet.pdf')}, pdf); r.pdf = pdf.length
        r.dirty = e.dirty
        return r`)
    log('save', JSON.stringify(out))
    if (!out.xlsx || !out.lsheet || out.pdf < 3000) throw new Error('保存失败')
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/test.xlsx'))}])`)
    await wait(1000)
    const rx = await js(`const e = window.app.active.editor; return { name: e.name, sheets: e.sheets.length, sum: e.value(12, 1), f: e.sheet.get(12, 1)?.f, bold: e.sheet.get(0, 0)?.s?.b, fill: e.sheet.get(0, 0)?.s?.fill, fmt: e.sheet.get(1, 2)?.s?.fmt, merges: e.sheet.meta.merges.length, cross: e.value(0, 0, e.sheets[1]) }`)
    log('reopen xlsx', JSON.stringify(rx))
    if (rx.sum !== s3.sum || rx.f !== 'SUM(B2:B12)' || !rx.bold || rx.merges !== 1) throw new Error('XLSX 往返失败')
    await shot('reopened-xlsx')
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/test.lsheet'))}])`)
    await wait(800)
    const rl = await js(`const e = window.app.active.editor; return { charts: e.sheet.meta.charts.length, sum: e.value(12, 1) }`)
    log('reopen lsheet', JSON.stringify(rl))
    if (rl.charts !== 1) throw new Error('LSHEET 往返失败')
    // 5. 大数据量：10 万行
    await js(`const e = window.app.active.editor; const { makeCell } = { makeCell: (v) => ({ v }) }
        e.addSheet('大数据')
        const sh = e.sheet
        for (let r = 0; r < 100000; r++) { sh.cells.set(r, 0, { v: r + 1 }); sh.cells.set(r, 1, { v: 'Row ' + (r + 1) }); sh.cells.set(r, 2, { v: Math.round(Math.random() * 1000) }) }
        sh.boundsCache = null
        e.setInput(0, 4, '=SUM(C1:C100000)')
        e.engine.rebuild(); e.invalidate()`)
    await wait(300)
    const t0 = Date.now()
    await js(`const e = window.app.active.editor; for (let i = 0; i < 20; i++) { e.grid.setScroll(0, i * 100000); e.grid.draw() }`)
    log('scroll 20 frames ms', Date.now() - t0)
    await js(`window.app.active.editor.selectCell(99990, 0)`)
    await wait(300)
    await shot('big')
    // 菜单
    await js(`document.querySelectorAll('.e-menu')[6].click()`)
    await wait(200)
    await shot('menu')
    await key('Escape')
}
