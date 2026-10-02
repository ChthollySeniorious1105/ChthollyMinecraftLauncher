// 文字处理器冒烟测试
const TMP = process.cwd().replace(/\\/g, '/') + '/.tmp'
const WIN = p => p.replace(/\//g, '\\')

export default async ({ js, shot, wait, key, type, click, log }) => {
    // 1. 报告示例
    await js(`await window.app.newDoc('doc', { sample: 'report' })`)
    await wait(700)
    await shot('report')
    const info = await js(`const e = window.app.active.editor; return { pages: e.pages, h: e.body.querySelectorAll('h1,h2').length, math: e.body.querySelectorAll('.doc-math .katex').length, toc: e.body.querySelectorAll('.toc-item').length }`)
    log('report', JSON.stringify(info))
    if (info.math < 3 || info.toc < 4) throw new Error('报告示例渲染不完整')

    // 2. 空白文档：输入、格式化、撤销
    await js(`await window.app.newDoc('doc', {})`)
    await wait(400)
    await js(`window.app.active.editor.body.focus()`)
    await type('第一章 引言')
    await js(`window.app.active.editor.setBlock('h1')`)
    const para = () => js(`document.execCommand('insertParagraph')`)
    await key('End'); await para()
    await type('这是一段正文，用来测试加粗和斜体。')
    await para()
    await type('#'); await type(' '); await type('用 Markdown 快捷方式创建的标题')
    const md = await js(`const e = window.app.active.editor; return e.body.innerHTML`)
    log('after md shortcut', md.slice(0, 300))
    if (!md.includes('<h1>用 Markdown')) throw new Error('Markdown 快捷输入失败')
    await js(`const e = window.app.active.editor, p = e.body.querySelector('p'), r = document.createRange()
        r.setStart(p.firstChild, 9); r.setEnd(p.firstChild, 11); getSelection().removeAllRanges(); getSelection().addRange(r)`)
    await key('B', ['control'])
    const bold = await js(`return window.app.active.editor.body.querySelector('b, strong')?.textContent`)
    log('bold', bold)
    if (bold !== '测试') throw new Error('加粗失败：' + bold)
    await key('Z', ['control'])
    const undone = await js(`return !!window.app.active.editor.body.querySelector('b, strong')`)
    await key('Y', ['control'])
    const redone = await js(`return !!window.app.active.editor.body.querySelector('b, strong')`)
    log('undo/redo', undone, redone)
    if (undone || !redone) throw new Error('撤销 / 重做失败')

    // 表格、公式、图片
    await js(`const e = window.app.active.editor, p = e.body.lastElementChild, r = document.createRange()
        r.selectNodeContents(p); r.collapse(false); getSelection().removeAllRanges(); getSelection().addRange(r); e.saveSel()
        e.insertTable(3, 3)
        const cells = e.body.querySelectorAll('td, th'); cells[0].textContent = '姓名'; cells[1].textContent = '成绩'; cells[3].textContent = '张三'; cells[4].textContent = '95'
        const c = document.createElement('canvas'); c.width = 320; c.height = 160; const g = c.getContext('2d'); g.fillStyle = '#6366f1'; g.fillRect(0, 0, 320, 160); g.fillStyle = '#fff'; g.font = '32px sans-serif'; g.fillText('测试图片', 90, 90)
        const last = e.body.lastElementChild, rr = document.createRange(); rr.selectNodeContents(last); rr.collapse(false); getSelection().removeAllRanges(); getSelection().addRange(rr); e.saveSel()
        await e.insertImage({ dataURL: c.toDataURL(), width: 320, height: 160, name: 'test' })
        e.insertHTML('<div class="doc-math-block"><span class="doc-math block" data-tex="\\\\sum_{k=1}^{n} k = \\\\frac{n(n+1)}{2}" contenteditable="false"></span></div><p>结束。</p>', '公式')`)
    await wait(300)
    await shot('edited')

    // 查找替换
    await js(`window.app.active.editor.openFind(true); const e = window.app.active.editor; e.findInput.value = '正文'; e.runFind(); e.replInput.value = '段落'; e.replaceAll(); e.closeFind()`)
    const replaced = await js(`return window.app.active.editor.body.textContent.includes('一段段落')`)
    log('replace', replaced)
    if (!replaced) throw new Error('替换失败')

    // 3. 保存为 DOCX / MD / HTML / TeX / PDF，重新打开 DOCX
    const out = await js(`const e = window.app.active.editor
        const r = {}
        for (const ext of ['docx', 'md', 'html', 'tex', 'ldoc']) { r[ext] = await e.writeTo(${JSON.stringify(TMP + '/test-doc.')} + ext) }
        const pdf = await e.exports()[0].write(); await window.lite.writeFile(${JSON.stringify(TMP + '/test-doc.pdf')}, pdf); r.pdf = pdf.length
        r.dirty = e.dirty
        return r`)
    log('save', JSON.stringify(out))
    if (!out.docx || !out.md || !out.tex || out.pdf < 5000) throw new Error('保存失败')
    const tex = await js(`return new TextDecoder().decode(await window.lite.readFile(${JSON.stringify(WIN(TMP + '/test-doc.tex'))}))`)
    log('tex:', tex.split('\n').slice(0, 30).join(' | ').slice(0, 900))
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/test-doc.docx'))}])`)
    await wait(900)
    const re = await js(`const e = window.app.active.editor; return { name: e.name, text: e.body.innerText.slice(0, 120), table: e.body.querySelectorAll('td, th').length, img: e.body.querySelectorAll('img').length, h1: e.body.querySelectorAll('h1').length }`)
    log('reopen docx', JSON.stringify(re))
    if (!re.table || !re.img || !re.text.includes('引言')) throw new Error('DOCX 往返失败')
    await shot('reopened-docx')

    // 4. LaTeX 文件
    await js(`await window.app.openPaths([${JSON.stringify(WIN(process.cwd() + '/samples/paper.tex'))}])`)
    await wait(1200)
    const tx = await js(`const e = window.app.active.editor; return { name: e.name, kind: e.kind, math: e.body.querySelectorAll('.doc-math').length, katex: e.body.querySelectorAll('.doc-math .katex').length, h: e.body.querySelectorAll('h1,h2,h3').length, err: e.body.querySelectorAll('.katex-error, .tex-err').length }`)
    log('tex open', JSON.stringify(tx))
    if (tx.kind !== 'doc' || tx.math < 5) throw new Error('LaTeX 打开失败')
    await shot('latex')
    // 编辑并另存为 .tex
    await js(`const e = window.app.active.editor, h = e.body.querySelector('h2.tex-section, h2:not(.tex-bib-title)'); h.append(' （已编辑）'); e.commit('编辑')
        await e.writeTo(${JSON.stringify(TMP + '/paper-edited.tex')})`)
    const edited = await js(`return new TextDecoder().decode(await window.lite.readFile(${JSON.stringify(WIN(TMP + '/paper-edited.tex'))}))`)
    const bi = edited.indexOf('\\begin{document}')
    log('edited tex body:', edited.slice(bi, bi + 1800).replace(/\n/g, ' | '))
    // 再次打开保存的 .tex，公式与章节数量应保持一致
    await js(`await window.app.openPaths([${JSON.stringify(WIN(TMP + '/paper-edited.tex'))}])`)
    await wait(800)
    const tx2 = await js(`const e = window.app.active.editor; return { name: e.name, math: e.body.querySelectorAll('.doc-math').length, h: e.body.querySelectorAll('h1,h2,h3').length, err: e.body.querySelectorAll('.tex-err').length, thm: e.body.querySelectorAll('.tex-theorem').length }`)
    log('tex reopen', JSON.stringify(tx2))
    if (!edited.includes('已编辑') || !edited.includes('\\newtheorem')) throw new Error('LaTeX 保存失败')
    // 源码视图
    await js(`await window.app.active.editor.toggleSource()`)
    await wait(500)
    await shot('latex-source')
    // 5. 菜单
    await js(`document.querySelectorAll('.e-menu')[3].click()`)
    await wait(200)
    await shot('menu')
    await key('Escape')
}
