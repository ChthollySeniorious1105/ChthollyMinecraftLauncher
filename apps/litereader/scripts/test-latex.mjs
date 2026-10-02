import { readFileSync, writeFileSync } from 'node:fs'
import { texToHtml } from '../src/core/latex.js'

const src = readFileSync(new URL('../samples/paper.tex', import.meta.url), 'utf8')
const r = texToHtml(src, { resolveAsset: f => 'media://local/x/' + f + '.png' })
writeFileSync(new URL('../dist/tex-test.html', import.meta.url), `<!DOCTYPE html><meta charset="utf-8"><link rel="stylesheet" href="../node_modules/katex/dist/katex.min.css"><body style="max-width:800px;margin:auto;font-family:serif">${r.html}</body>`)
console.log('caveats:', r.caveats)
console.log('toc:', r.toc.map(t => `${t.num} ${t.text}`))
const txt = r.html.replace(/<span class="katex[\s\S]*?<\/span><\/span><\/span>/g, '[M]')
const checks = {
    '无占位符残留': !/\u0000|ZQREF/.test(r.html),
    '标题': r.html.includes('LiteReader'),
    '注释被去除': !r.html.includes('这是注释'),
    '公式编号(1)': r.html.includes('(1)'),
    '引用 eq:gauss -> (1)': /href="#lbl-eq:gauss">1</.test(r.html),
    '引用 sec:method -> 2': /href="#lbl-sec:method">2</.test(r.html),
    '引用 tab -> 1': /href="#lbl-tab:formats">1</.test(r.html),
    '引用 thm -> 2.1': /href="#lbl-thm:mvt">2.1</.test(r.html),
    '引用 frob -> 3': /href="#lbl-eq:frob">3</.test(r.html),
    '文献引用 1': /href="#bib-knuth1984">1</.test(r.html),
    'verbatim 保留 %': r.html.includes('verbatim 中的 % 与 $ 不应被处理'),
    '脚注': r.html.includes('fn-1'),
    '定理': r.html.includes('定理 2.1'),
    '引理共用编号': r.html.includes('引理 2.2'),
    '表格 multicolumn': r.html.includes('colspan="2"'),
    '图片': r.html.includes('sample_1'),
    '无 KaTeX 错误': !r.html.includes('tex-err'),
    'TOC': r.html.includes('tex-toc'),
    '自定义标记': r.html.includes('tex-li-label'),
    'description': r.html.includes('<dt>PPTX</dt>'),
}
for (const [k, v] of Object.entries(checks)) console.log(v ? 'PASS' : 'FAIL', k)
if (r.html.includes('tex-err')) console.log([...r.html.matchAll(/tex-err" title="([^"]*)">([^<]*)/g)].map(m => m[1] + ' :: ' + m[2]).join('\n'))

// 边界情况
const cases = {
    '无 document 环境的片段': ['Hello $x^2$ world', h => h.includes('katex') && h.includes('Hello')],
    '宏带参数': [String.raw`\newcommand{\pair}[2]{(#1, #2)}\begin{document}\pair{a}{b} $\pair{x}{y}$\end{document}`, h => h.includes('(a, b)') && !h.includes('tex-err')],
    '可选参数宏': [String.raw`\newcommand{\hi}[1][世界]{你好#1}\begin{document}\hi \hi[朋友]\end{document}`, h => h.includes('你好世界') && h.includes('你好朋友')],
    '\\def': [String.raw`\def\foo{BAR}\begin{document}\foo\end{document}`, h => h.includes('BAR')],
    '未闭合公式不崩溃': [String.raw`\begin{document}$x^{2\end{document}`, h => typeof h === 'string'],
    '转义字符': [String.raw`\begin{document}50\% \& \$5 \#1 a\_b\end{document}`, h => h.includes('50%') && h.includes('&amp;') && h.includes('$5') && h.includes('a_b')],
    '引号与破折号': ['\\begin{document}``quote\'\' 1--2 a---b\\end{document}', h => h.includes('“quote”') && h.includes('1–2') && h.includes('a—b')],
    'appendix 字母编号': [String.raw`\begin{document}\section{A}\appendix\section{B}\label{s:b}见\ref{s:b}\end{document}`, h => /href="#lbl-s:b">A</.test(h)],
    '未知引用标 ??': [String.raw`\begin{document}\ref{nope}\end{document}`, h => h.includes('??')],
    'gather*': [String.raw`\begin{document}\begin{gather*}a\\b\end{gather*}\end{document}`, h => !h.includes('tex-err')],
    'multline': [String.raw`\begin{document}\begin{multline}a+b\\+c\end{multline}\end{document}`, h => !h.includes('tex-err') && h.includes('(1)')],
    'tikz 占位': [String.raw`\begin{document}\begin{tikzpicture}\draw (0,0)--(1,1);\end{tikzpicture}\end{document}`, h => h.includes('TikZ')],
    '章节 chapter': [String.raw`\documentclass{book}\begin{document}\chapter{一}\begin{equation}x\end{equation}\end{document}`, h => h.includes('第 1 章') && h.includes('(1.1)')],
    'XSS 防护': [String.raw`\begin{document}<script>alert(1)</script> \href{javascript:alert(1)}{x}\end{document}`, h => !h.includes('<script>')],
}
for (const [name, [src2, test]] of Object.entries(cases)) {
    let out
    try { out = texToHtml(src2).html } catch (e) { out = 'THROW ' + e.message }
    const ok = test(out)
    console.log(ok ? 'PASS' : 'FAIL', name, ok ? '' : out.slice(0, 300))
}

// 多文件工程：\include / \input 嵌套 + .bib
{
    const dir = new URL('../samples/thesis/', import.meta.url)
    const rd = p => readFileSync(new URL(p, dir), 'utf8')
    const includes = new Map([
        ['chapters/intro', rd('chapters/intro.tex')],
        ['chapters/method.tex', rd('chapters/method.tex')],
        ['chapters/detail', rd('chapters/detail.tex')],
    ])
    const r = texToHtml(rd('main.tex'), { includes, bibs: [rd('refs.bib')], resolveAsset: f => 'media://local/' + f + '.jpg' })
    const h = r.html
    const checks = {
        '工程: 合并 include 章节': h.includes('绪论') && h.includes('研究背景'),
        '工程: 嵌套 input': h.includes('模型细节') && h.includes('Attention'),
        '工程: 章节编号 第 2 章': h.includes('第 2 章'),
        '工程: 公式按章编号 2.1': h.includes('(2.1)'),
        '工程: 附录字母编号 A.1': h.includes('(A.1)'),
        '工程: 跨文件引用 ch:intro -> 1': /href="#lbl-ch:intro">1</.test(h),
        '工程: 跨文件引用 eq:attn -> 2.1': /href="#lbl-eq:attn">2.1</.test(h),
        '工程: bib 编号按引用顺序': /href="#bib-lecun2015deep">1</.test(h) && /href="#bib-vaswani2017attention">3</.test(h),
        '工程: bib 条目格式': h.includes('Yann LeCun') && h.includes('<em>Nature</em>') && h.includes('436–444'),
        '工程: bib 书名斜体 + TeX 标志': /<em>The T<sub>E<\/sub>X\s*book<\/em>/.test(h) || h.includes('The T<sub>E</sub>Xbook'),
        '工程: DOI 链接': h.includes('https://doi.org/10.1038/nature14539'),
        '工程: 未引用条目不列出': !h.includes('未被引用的条目'),
        '工程: 无近似提示': !r.caveats.length,
        '工程: 无占位符残留': !/\u0000|ZQREF/.test(h),
        '工程: 目录包含子文件章节': r.toc.some(t => t.text.includes('模型细节')),
    }
    for (const [k, v] of Object.entries(checks)) console.log(v ? 'PASS' : 'FAIL', k)
    if (r.caveats.length) console.log('  caveats:', r.caveats)
    const r2 = texToHtml(String.raw`\begin{document}\cite{a}\nocite{*}\bibliography{x}\end{document}`, { bibs: ['@misc{a, title={A}}\n@misc{b, title={B}}'] })
    console.log(r2.html.includes('>B') || r2.html.includes('B.') ? 'PASS' : 'FAIL', 'nocite{*} 列出全部条目')
    const r3 = texToHtml(String.raw`\begin{document}\input{missing}\end{document}`)
    console.log(r3.html.includes('missing') && r3.caveats.length ? 'PASS' : 'FAIL', '缺失的 input 显示占位并提示')
}
