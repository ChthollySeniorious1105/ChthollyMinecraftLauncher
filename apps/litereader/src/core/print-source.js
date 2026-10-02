// 各查看器的打印内容：回流文档 → 带样式的 HTML（由 Chromium 分页）；版式页面 → 每页原始尺寸
import { toDoc, toPages, docHtml, pagesPrintHtml, kindOf } from './convert.js'

export async function convertForPrint(viewer) {
    const source = viewer.source
    const kind = kindOf(source)
    if (kind === 'doc') {
        const doc = await toDoc(source)
        return { kind: 'doc', html: await docHtml(doc, { forPrint: true }) }
    }
    if (kind === 'pages') {
        const doc = await toPages(source)
        const total = doc.pages.length
        return {
            kind: 'pages',
            pageCount: total,
            build: async list => {
                try { return await pagesPrintHtml(doc, list ?? doc.pages.map((_, i) => i + 1), source.type === 'image' ? 1 : 2) }
                finally { doc.dispose?.() }
            },
        }
    }
    if (kind === 'sheet') {
        const XLSX = await import('xlsx')
        // 打印当前工作表（查看器中已解析的工作簿）
        const wb = viewer.wb
        const names = wb ? [wb.SheetNames[viewer.sheetIndex ?? 0]] : []
        const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c])
        const html = names.map(n => `<h2>${esc(n)}</h2>${XLSX.utils.sheet_to_html(wb.Sheets[n], { header: '', footer: '' }).replace(/^[\s\S]*?<table/, '<table').replace(/<\/table>[\s\S]*$/, '</table>')}`).join('')
        return { kind: 'doc', html: await docHtml({ title: source.name, html: `<div class="sheet-export">${html}</div>`, css: '.sheet-export table{border-collapse:collapse;font-size:11px}.sheet-export td{border:1px solid #bbb;padding:2px 6px}.sheet-export h2{font-size:15px;margin:0 0 8px}' }, { forPrint: true }) }
    }
    throw new Error('此类型文件不支持打印')
}
