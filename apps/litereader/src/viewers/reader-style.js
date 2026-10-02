import { h, slider, segmented, toggle } from '../core/dom.js'
import * as store from '../core/store.js'
import { currentTheme } from '../core/theme.js'

export const FONT_STACKS = {
    serif: '"Noto Serif SC", "Source Han Serif SC", "Songti SC", "SimSun", "宋体", Georgia, serif',
    sans: '"HarmonyOS Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Segoe UI", sans-serif',
    kai: '"KaiTi", "STKaiti", "楷体", "Kaiti SC", serif',
    fangsong: '"FangSong", "STFangsong", "仿宋", serif',
    mono: '"Cascadia Code", "JetBrains Mono", Consolas, "Microsoft YaHei", monospace',
}

// 阅读区配色预设：默认“跟随主题”（CML 主题的 paper / ink），也可单独选择纸张
export const PAPERS = [
    { id: 'theme', name: '跟随主题' },
    { id: 'white', name: '纯白', paper: '#ffffff', ink: '#222222', dark: false },
    { id: 'warm', name: '暖黄', paper: '#f8f1e3', ink: '#4a3c2a', dark: false },
    { id: 'sepia', name: '羊皮', paper: '#efe2c6', ink: '#4b3a22', dark: false },
    { id: 'green', name: '护眼绿', paper: '#cce8cf', ink: '#1f3a25', dark: false },
    { id: 'blue', name: '天青', paper: '#e3eef8', ink: '#1d3148', dark: false },
    { id: 'gray', name: '灰雾', paper: '#3a3d42', ink: '#d6d6d6', dark: true },
    { id: 'night', name: '夜间', paper: '#141414', ink: '#9d9d9d', dark: true },
    { id: 'black', name: '纯黑', paper: '#000000', ink: '#b8b8b8', dark: true },
]

export function readerColors() {
    const s = store.getSettings()
    const t = currentTheme()
    const p = PAPERS.find(x => x.id === s.readerPaper)
    const base = p?.paper ? p : { paper: t.paper, ink: t.ink, dark: t.dark }
    return {
        ...base,
        heading: base.ink,
        link: t.accent,
        selection: t.accent + '55',
    }
}

// 阅读设置面板
export function readerPanel({ flow = false, columns = false, fonts = true, width = true } = {}) {
    const s = store.getSettings()
    const papers = h('div.paper-list', PAPERS.map(p => {
        const b = h('button.paper' + ((s.readerPaper ?? 'theme') === p.id ? '.active' : ''), {
            title: p.name,
            style: p.paper ? { background: p.paper, color: p.ink } : {},
            onclick: () => {
                store.set('readerPaper', p.id)
                papers.querySelectorAll('.paper').forEach(x => x.classList.toggle('active', x === b))
            },
        }, p.paper ? 'Aa' : '主题')
        return b
    }))
    return h('div.panel.reader-panel',
        h('div.panel-title', '阅读设置'),
        h('div.field', h('span.field-label', '背景'), papers),
        fonts ? h('div.field', h('span.field-label', '字体'), segmented([
            ['serif', '宋体'], ['sans', '黑体'], ['kai', '楷体'], ['fangsong', '仿宋'], ['mono', '等宽'],
        ], s.readerFont, v => store.set('readerFont', v)).el) : null,
        slider({ label: '字号', min: 12, max: 36, value: s.readerFontSize, format: v => v + 'px', oninput: v => store.set('readerFontSize', v) }).el,
        slider({ label: '行距', min: 1.2, max: 2.6, step: 0.1, value: s.readerLineHeight, format: v => v.toFixed(1), oninput: v => store.set('readerLineHeight', v) }).el,
        width ? slider({ label: '版心宽度', min: 480, max: 1400, step: 20, value: s.readerWidth, format: v => v + 'px', oninput: v => store.set('readerWidth', v) }).el : null,
        slider({ label: '页边距', min: 0, max: 120, step: 4, value: s.readerMargin, format: v => v + 'px', oninput: v => store.set('readerMargin', v) }).el,
        flow ? h('div.field', h('span.field-label', '翻页方式'), segmented([
            ['paginated', '分页', 'book-open'], ['scrolled', '滚动', 'scroll-text'],
        ], s.readerFlow, v => store.set('readerFlow', v)).el) : null,
        columns ? h('div.field', h('span.field-label', '宽屏分栏'), segmented([
            [1, '单栏', 'square'], [2, '双栏', 'columns-2'],
        ], s.readerColumns, v => store.set('readerColumns', v)).el) : null,
        h('div.field.inline', h('span.field-label', '两端对齐'), toggle(s.readerJustify, v => store.set('readerJustify', v))),
    )
}
