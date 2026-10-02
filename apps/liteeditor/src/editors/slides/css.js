// 幻灯片内容样式：应用内与导出 PDF 共用
export const SLIDE_CSS = `
.sl-slide { position: relative; overflow: hidden; box-sizing: border-box; color: #111; -webkit-font-smoothing: antialiased; }
.sl-slide *, .sl-slide *::before, .sl-slide *::after { box-sizing: border-box; }
.sl-el { position: absolute; transform-origin: 50% 50%; }
.sl-text { position: absolute; inset: 0; display: flex; flex-direction: column; padding: 14px 20px; overflow: hidden; overflow-wrap: anywhere; outline: none; white-space: pre-wrap; }
.sl-text > * { margin: 0; }
.sl-text p, .sl-text div { margin: 0; }
.sl-text ul, .sl-text ol { margin: 0; padding-left: 1.3em; }
.sl-text li { margin: .18em 0; }
.sl-text.is-list:not(:has(ul)):not(:has(ol)) > div, .sl-text.is-list:not(:has(ul)):not(:has(ol)) > p { }
.sl-ph { color: currentColor; opacity: .38; font-weight: inherit; }
.sl-shape-text { padding: 10px 24px; }
.sl-type-image img { width: 100%; height: 100%; display: block; }
.sl-table { width: 100%; height: 100%; border-collapse: collapse; table-layout: fixed; }
.sl-table th, .sl-table td { border: 2px solid var(--tb); padding: 10px 16px; text-align: left; vertical-align: middle; overflow: hidden; outline: none; }
.sl-table tr.head th { background: var(--tc); color: #fff; font-weight: 700; border-color: var(--tc); }
.sl-table tr.band td { background: color-mix(in srgb, var(--tc) 9%, transparent); }
.sl-math { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
.sl-math .katex-display { margin: 0; }
.sl-type-icon svg { display: block; }
`
let injected = false
export function injectSlideCSS() {
    if (injected) return
    injected = true
    const s = document.createElement('style')
    s.textContent = SLIDE_CSS
    document.head.append(s)
}
