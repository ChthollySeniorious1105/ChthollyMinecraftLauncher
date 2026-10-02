// 打印与导出 PDF：统一的排版样式、打印对话框与执行
import { h, toast } from './dom.js'
import { icon } from './icons.js'
import { stemOf, dirName } from './files.js'

// 导出 / 打印用的文档样式（与阅读器的主题无关，始终为白底黑字）
export function printStyles(forPrint = false) {
    return `
    html { background: ${forPrint ? '#fff' : '#f3f4f6'}; }
    body { margin: 0; color: #1f2937; font: 15px/1.75 "Noto Serif SC", "Source Han Serif SC", "SimSun", Georgia, serif; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .lr-doc { max-width: ${forPrint ? 'none' : '820px'}; margin: ${forPrint ? '0' : '32px auto'}; padding: ${forPrint ? '0' : '48px 56px'}; background: #fff; ${forPrint ? '' : 'box-shadow: 0 4px 24px rgb(0 0 0 / .1); border-radius: 6px;'} word-break: break-word; }
    .lr-doc.code { font-family: Consolas, "Cascadia Code", monospace; font-size: 12.5px; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.35; break-after: avoid; font-family: "Microsoft YaHei", "Segoe UI", sans-serif; }
    h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
    p { margin: 0 0 .8em; orphans: 3; widows: 3; }
    img, svg, video { max-width: 100%; height: auto; break-inside: avoid; }
    figure { margin: 1em 0; text-align: center; break-inside: avoid; }
    pre { white-space: pre-wrap; word-break: break-all; font: 12.5px/1.55 Consolas, "Cascadia Code", monospace; background: #f6f8fa; padding: 12px 14px; border-radius: 6px; break-inside: avoid; }
    pre.code-lines { white-space: pre; overflow: hidden; background: none; padding: 0; }
    pre.code-lines .ln::before { content: attr(data-n); display: inline-block; width: 3em; margin-right: 1em; text-align: right; color: #9ca3af; border-right: 1px solid #e5e7eb; padding-right: .5em; }
    code { font-family: Consolas, "Cascadia Code", monospace; font-size: .9em; }
    :not(pre) > code { background: #f3f4f6; padding: 1px 4px; border-radius: 3px; }
    table { border-collapse: collapse; margin: 1em 0; max-width: 100%; }
    th, td { border: 1px solid #d1d5db; padding: 4px 8px; vertical-align: top; }
    tr { break-inside: avoid; }
    blockquote { margin: 1em 0; padding: .2em 1em; border-left: 3px solid #60a5fa; color: #4b5563; }
    a { color: #2563eb; }
    hr.chapter-break { border: 0; break-after: page; margin: 0; }
    .katex-display { overflow: visible; }
    .tex-display { position: relative; margin: .9em 0; padding: 0 3.4em; }
    .tex-eqno { position: absolute; right: 0; top: 50%; transform: translateY(-50%); }
    .tex-display .katex .eqn-num::before { content: none; }
    .tex-title { text-align: center; margin-bottom: 2em; } .tex-chapnum { display: block; font-size: .6em; opacity: .6; }
    .tex-secnum { margin-right: .7em; } .tex-abstract { margin: 1.5em 2em; font-size: .94em; } .tex-abstract-title { text-align: center; font-weight: 700; }
    .tex-toc ol { list-style: none; padding: 0; } .tex-toc a { color: inherit; text-decoration: none; } .tex-toc a span { display: inline-block; min-width: 2.6em; }
    .tex-theorem.tex-thm { font-style: italic; } .tex-theorem b { font-style: normal; } .tex-qed { float: right; }
    .tex-table-wrap { display: flex; justify-content: center; } table.tex-table { border-top: 1.5px solid; border-bottom: 1.5px solid; } .tex-table td { border: 0; }
    .tex-table.vlines td { border: 1px solid #999; } .tex-table tr.hl td { border-top: 1px solid #666; }
    .tex-bib { list-style: none; padding: 0; } .tex-bib li { padding-left: 3em; text-indent: -3em; } .tex-bib-label { display: inline-block; min-width: 3em; text-indent: 0; }
    .tex-missing { border: 1px dashed #aaa; padding: .2em .6em; font-size: .85em; color: #666; }
    .tex-li-label { font-weight: 600; margin-left: -1.4em; margin-right: .3em; } .tex-list li.custom { list-style: none; }
    .tex-figure figcaption, .tex-table figcaption { font-size: .9em; }
    @media print { a { color: inherit; text-decoration: none; } }
    `
}

export const PAGE_SIZES = [['A4', 'A4'], ['A3', 'A3'], ['A5', 'A5'], ['B5', 'B5'], ['Letter', 'Letter'], ['Legal', 'Legal']]

// 打印 / 导出对话框。返回 Promise<{ mode, pageSize, landscape, margins, headerFooter, range } | null>
export function printDialog({ title = '打印', kind = 'doc', pages = 0, defaultMode = 'print' } = {}) {
    return new Promise(resolve => {
        const s = JSON.parse(localStorage.getItem('lr.print') ?? '{}')
        const state = { mode: defaultMode, pageSize: s.pageSize ?? 'A4', landscape: s.landscape ?? false, margins: s.margins ?? 'default', headerFooter: s.headerFooter ?? false, range: '' }
        const seg = (options, key) => {
            const el = h('div.segmented')
            const render = () => el.replaceChildren(...options.map(([v, label]) => h('button' + (state[key] === v ? '.active' : ''), { onclick: () => { state[key] = v; render() } }, label)))
            render()
            return el
        }
        const row = (label, ctrl, hint) => h('div.pd-row', h('span.pd-label', label), h('div.pd-ctrl', ctrl, hint ? h('div.pd-hint', hint) : null))
        const range = h('input.input.small', { placeholder: pages ? `全部（共 ${pages} 页），如 1-3,5` : '全部', value: '' })
        range.addEventListener('input', () => { state.range = range.value })
        const hf = h('input', { type: 'checkbox', checked: state.headerFooter })
        hf.addEventListener('change', () => { state.headerFooter = hf.checked })
        const fixed = kind === 'pages'
        const close = v => {
            mask.classList.remove('show')
            setTimeout(() => mask.remove(), 200)
            if (v) localStorage.setItem('lr.print', JSON.stringify({ pageSize: state.pageSize, landscape: state.landscape, margins: state.margins, headerFooter: state.headerFooter }))
            resolve(v)
        }
        const mask = h('div.modal-mask', h('div.modal.print-dialog',
            h('div.modal-title', icon('printer', 18), title),
            row('输出', seg([['print', '打印'], ['pdf', '导出 PDF']], 'mode')),
            fixed ? h('div.pd-note', icon('info', 14), '版式文档按原始页面尺寸输出，每页一张') : null,
            !fixed ? row('纸张', seg(PAGE_SIZES, 'pageSize')) : null,
            !fixed ? row('方向', seg([[false, '纵向'], [true, '横向']], 'landscape')) : null,
            !fixed ? row('边距', seg([['default', '标准'], ['minimum', '窄'], ['none', '无']], 'margins')) : null,
            pages > 1 ? row('页码范围', range) : null,
            !fixed ? row('页眉页脚', h('label.switch', hf, h('span.switch-track', h('span.switch-thumb'))), '页眉显示标题，页脚显示页码') : null,
            h('div.modal-actions',
                h('button.btn', { onclick: () => close(null) }, '取消'),
                h('button.btn.primary', { onclick: () => close({ ...state }) }, '继续'))))
        mask.addEventListener('keydown', e => { if (e.key === 'Escape') close(null) })
        document.body.append(mask)
        requestAnimationFrame(() => mask.classList.add('show'))
    })
}

// 解析页码范围 "1-3,5,8-" → [1,2,3,5,8,...]
export function parseRange(text, total) {
    const t = (text ?? '').trim()
    if (!t) return Array.from({ length: total }, (_, i) => i + 1)
    const out = new Set()
    for (const part of t.split(/[,，\s]+/)) {
        const m = /^(\d*)\s*[-–~]\s*(\d*)$/.exec(part)
        if (m) {
            const a = Math.max(1, Number(m[1] || 1)), b = Math.min(total, Number(m[2] || total))
            for (let i = a; i <= b; i++) out.add(i)
        } else if (/^\d+$/.test(part)) {
            const n = Number(part)
            if (n >= 1 && n <= total) out.add(n)
        }
    }
    return [...out].sort((a, b) => a - b)
}

// 执行打印 / 导出。html 为完整 HTML 文档；cssPage 表示由文档自带 @page 尺寸（版式页面）
export async function runPrint({ html, opts, source, cssPage = false }) {
    const common = { html, pageSize: opts.pageSize, landscape: opts.landscape, margins: opts.margins, headerFooter: opts.headerFooter, title: source?.name ?? 'LiteReader', cssPage }
    if (opts.mode === 'print') {
        const r = await window.lite.printHtml({ ...common, mode: 'print' })
        if (r?.ok) toast('已发送到打印机', 'success')
        else if (r?.reason && !/cancel/i.test(r.reason)) toast('打印失败：' + r.reason, 'error')
        return r
    }
    const target = await window.lite.savePath({
        defaultPath: (source?.path ? dirName(source.path) + '\\' : '') + stemOf(source?.name ?? 'document') + '.pdf',
        filters: [{ name: 'PDF 文档', extensions: ['pdf'] }],
    })
    if (!target) return null
    const t = toastProgress('正在生成 PDF…')
    try {
        const r = await window.lite.printHtml({ ...common, mode: 'pdf', target })
        t.done()
        if (r?.ok) toastAction(`已导出 PDF（${(r.size / 1024).toFixed(0)} KB）`, '在文件夹中显示', () => window.lite.showInFolder(r.path))
        return r
    } catch (e) {
        t.done()
        toast('导出失败：' + (e.message ?? e), 'error', 5000)
    }
}

// 长时间任务的提示
export function toastProgress(text) {
    const box = document.getElementById('toasts')
    const el = h('div.toast.show.info', h('div.spinner.small'), h('span', text))
    box.append(el)
    return { set: t => { el.lastChild.textContent = t }, done: () => { el.classList.remove('show'); setTimeout(() => el.remove(), 300) } }
}
export function toastAction(text, action, fn, ms = 6000) {
    const box = document.getElementById('toasts')
    const el = h('div.toast.success', icon('circle-check', 18), h('span', text), h('button.toast-action', { onclick: () => { fn(); el.remove() } }, action))
    box.append(el)
    requestAnimationFrame(() => el.classList.add('show'))
    setTimeout(() => { el.classList.remove('show'); setTimeout(() => el.remove(), 300) }, ms)
}
