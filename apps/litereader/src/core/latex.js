// LaTeX → HTML 转换（阅读用途，非完整 TeX 引擎）
// 支持：文档结构与编号、交叉引用、数学（KaTeX）、列表、表格、图片、脚注、定理类环境、
// 参考文献（thebibliography）、常见文本命令与宏定义（\newcommand / \def）
import katex from 'katex'

const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

const MATH_ENVS = new Set(['equation', 'equation*', 'align', 'align*', 'gather', 'gather*', 'multline', 'multline*',
    'flalign', 'flalign*', 'alignat', 'alignat*', 'eqnarray', 'eqnarray*', 'displaymath', 'math', 'dmath', 'dmath*'])
const NUMBERED_MATH = new Set(['equation', 'align', 'gather', 'multline', 'flalign', 'alignat', 'eqnarray', 'dmath'])
const THEOREMS = {
    theorem: '定理', lemma: '引理', proposition: '命题', corollary: '推论', definition: '定义', example: '例',
    remark: '注', conjecture: '猜想', assumption: '假设', exercise: '练习', problem: '问题', claim: '断言', note: '注记',
}
const SECTIONS = ['part', 'chapter', 'section', 'subsection', 'subsubsection', 'paragraph', 'subparagraph']
const IGNORE_ENVS = new Set(['comment', 'tikzpicture', 'pgfpicture', 'filecontents', 'filecontents*'])
const SYMBOLS = {
    LaTeX: 'L<sup>A</sup>T<sub>E</sub>X', TeX: 'T<sub>E</sub>X', LaTeXe: 'L<sup>A</sup>T<sub>E</sub>X 2ε', ldots: '…', dots: '…',
    textbackslash: '\\', textasciitilde: '~', textasciicircum: '^', textbar: '|', textless: '&lt;', textgreater: '&gt;',
    textendash: '–', textemdash: '—', textquoteleft: '‘', textquoteright: '’', textquotedblleft: '“', textquotedblright: '”',
    textbullet: '•', textperiodcentered: '·', textdegree: '°', copyright: '©', textcopyright: '©', textregistered: '®',
    texttrademark: '™', S: '§', P: '¶', dag: '†', ddag: '‡', pounds: '£', euro: '€', slash: '/', ss: 'ß', ae: 'æ', AE: 'Æ',
    oe: 'œ', OE: 'Œ', o: 'ø', O: 'Ø', aa: 'å', AA: 'Å', l: 'ł', L: 'Ł', i: 'ı', j: 'ȷ', quad: ' ', qquad: '  ',
    enspace: ' ', thinspace: ' ', ',': ' ', ';': ' ', ' ': ' ', linebreak: '<br>',
    '&': '&amp;', '%': '%', $: '$', '#': '#', _: '_', '{': '{', '}': '}', '-': '­', '/': '', '@': '', noindent: '', indent: '',
    par: '\n\n', today: new Date().toLocaleDateString('zh-CN'), hfill: '', vfill: '', centering: '', raggedright: '', raggedleft: '',
    clearpage: '', newpage: '', cleardoublepage: '', pagebreak: '', nopagebreak: '', smallskip: '', medskip: '', bigskip: '',
    maketitle: '\u0000MAKETITLE\u0000', tableofcontents: '\u0000TOC\u0000', protect: '', relax: '', selectfont: '', normalfont: '',
    frontmatter: '', mainmatter: '', backmatter: '', hline: '', toprule: '', midrule: '',
    bottomrule: '', leavevmode: '', ignorespaces: '', unskip: '', null: '',
}
const ACCENTS = { '"': '̈', "'": '́', '`': '̀', '^': '̂', '~': '̃', '=': '̄', '.': '̇', u: '̆', v: '̌', H: '̋', c: '̧', k: '̨', r: '̊', b: '̱', d: '̣' }
// 带一个参数、只做样式包装的命令
const WRAP = {
    textbf: 'strong', bf: 'strong', textit: 'em', it: 'em', emph: 'em', em: 'em', textsl: 'em', sl: 'em', underline: 'u', uline: 'u',
    texttt: 'code', tt: 'code', verb: 'code', textsc: 'span.sc', sc: 'span.sc', textsf: 'span.sf', sf: 'span.sf', textrm: 'span', rm: 'span',
    textup: 'span', textmd: 'span', textnormal: 'span', mbox: 'span', hbox: 'span', text: 'span', sout: 's', st: 's', xout: 's',
    textsuperscript: 'sup', textsubscript: 'sub', tiny: 'small', scriptsize: 'small', footnotesize: 'small', small: 'small',
    large: 'span.lg', Large: 'span.lg2', LARGE: 'span.lg3', huge: 'span.lg3', Huge: 'span.lg3', normalsize: 'span',
    centerline: 'div.center', fbox: 'span.fbox', framebox: 'span.fbox', makebox: 'span', boxed: 'span.fbox', textcolor: null, colorbox: null,
}

// includes：\input / \include 引用的文件名 → 文本（null 表示未找到）；bibs：.bib 文件文本数组
export function texToHtml(src, { resolveAsset, macros: extMacros, includes, bibs } = {}) {
    const ctx = {
        macros: { ...extMacros },
        mathMacros: {},
        labels: {},
        refs: [],
        counters: { part: 0, chapter: 0, section: 0, subsection: 0, subsubsection: 0, paragraph: 0, subparagraph: 0, equation: 0, figure: 0, table: 0, footnote: 0, theorem: 0 },
        toc: [],
        footnotes: [],
        meta: {},
        caveats: new Set(),
        resolveAsset,
        appendix: false,
        hasChapter: /\\chapter\*?\s*[{[]/.test(src),
        theoremNames: { ...THEOREMS },
        sharedCounter: {},
        bib: {},
        includes: includes instanceof Map ? includes : new Map(Object.entries(includes ?? {})),
        bibEntries: Object.assign({}, ...(bibs ?? []).map(parseBib)),
        citeOrder: [],
        nociteAll: false,
    }
    src = inlineInputs(stripComments(src), ctx)
    ctx.hasChapter = /\\chapter\*?\s*[{[]/.test(src)
    // 仅渲染正文；导言区用于读取宏定义与元数据
    const bi = src.indexOf('\\begin{document}')
    const ei = src.lastIndexOf('\\end{document}')
    const preamble = bi >= 0 ? src.slice(0, bi) : ''
    let body = bi >= 0 ? src.slice(bi + 16, ei > bi ? ei : undefined) : src
    readPreamble(preamble, ctx)
    // 正文中的宏定义也需要先收集
    body = collectDefs(body, ctx)
    const html = convert(body, ctx, { top: true })
    return finalize(html, ctx)
}

function stripComments(s) {
    // 去掉 % 注释（保留 \%）以及 verbatim 中的内容不处理
    const out = []
    const verb = /\\begin\{(verbatim\*?|lstlisting|minted|Verbatim)\}[\s\S]*?\\end\{\1\}/g
    let last = 0, m
    while ((m = verb.exec(s))) {
        out.push(strip(s.slice(last, m.index)), m[0])
        last = m.index + m[0].length
    }
    out.push(strip(s.slice(last)))
    return out.join('')
    function strip(t) {
        return t.replace(/(^|[^\\])((?:\\\\)*)%.*$/gm, '$1$2').replace(/\\iffalse[\s\S]*?\\fi\b/g, '')
    }
}

// 将 \input / \include / \subfile 引用的文件内容合并进来（子文件中的导言区会被去掉）
function inlineInputs(src, ctx, depth = 0) {
    if (!ctx.includes.size || depth > 8) return src
    // \verb 与 verbatim 环境中的内容不展开
    return src.replace(/\\verb\*?([^a-zA-Z\s])[\s\S]*?\1|\\begin\{(verbatim\*?|lstlisting|minted|Verbatim)\}[\s\S]*?\\end\{\2\}|\\(input|include|subfile)\s*\{([^}]+)\}/g, (m, _d, _env, cmd, name) => {
        if (!cmd) return m
        const text = ctx.includes.get(name.trim())
        if (text == null) return m
        let body = stripComments(text)
        const bi = body.indexOf('\\begin{document}')
        if (bi >= 0) {
            const ei = body.lastIndexOf('\\end{document}')
            body = body.slice(bi + 16, ei > bi ? ei : undefined)
        }
        const inner = inlineInputs(body, ctx, depth + 1)
        return cmd === 'input' ? inner : `\n\n${inner}\n\n`
    })
}

// ---------- BibTeX ----------
export function parseBib(text) {
    const out = {}
    const re = /@(\w+)\s*([{(])/g
    let m
    while ((m = re.exec(text))) {
        const type = m[1].toLowerCase()
        const open = m[2], close = open === '{' ? '}' : ')'
        const start = re.lastIndex
        let depth = 1, i = start
        for (; i < text.length && depth; i++) {
            if (text[i] === '\\') { i++; continue }
            if (text[i] === open) depth++
            else if (text[i] === close) depth--
        }
        re.lastIndex = i
        if (['comment', 'preamble', 'string'].includes(type)) continue
        const body = text.slice(start, i - 1)
        const comma = body.indexOf(',')
        if (comma < 0) continue
        const key = body.slice(0, comma).trim()
        const fields = {}
        const fre = /\s*([\w-]+)\s*=\s*/y
        let j = comma + 1
        while (j < body.length) {
            fre.lastIndex = j
            const fm = fre.exec(body)
            if (!fm) break
            j = fre.lastIndex
            let val = ''
            // 字段值：{…}、"…" 或裸词，可用 # 连接
            for (;;) {
                while (/\s/.test(body[j] ?? '')) j++
                if (body[j] === '{' || body[j] === '"') {
                    const quote = body[j] === '"'
                    let d = 0, k = j
                    for (; k < body.length; k++) {
                        const ch = body[k]
                        if (ch === '\\') { k++; continue }
                        if (ch === '{') d++
                        else if (ch === '}') { d--; if (!quote && d === 0) break }
                        else if (quote && ch === '"' && d === 0 && k > j) break
                    }
                    val += body.slice(j + 1, k)
                    j = k + 1
                } else {
                    const w = /^[\w.:+-]+/.exec(body.slice(j))
                    if (!w) break
                    val += w[0]
                    j += w[0].length
                }
                while (/\s/.test(body[j] ?? '')) j++
                if (body[j] === '#') { j++; continue }
                break
            }
            fields[fm[1].toLowerCase()] = val.replace(/\s+/g, ' ').trim()
            while (j < body.length && body[j] !== ',') j++
            j++
        }
        out[key] = { type, fields }
    }
    return out
}

// 近似 plain 样式的参考文献条目
function formatBibEntry(e, ctx) {
    const f = e.fields
    const cv = t => t ? convert(t, ctx, {}).trim() : ''
    const names = s => s.split(/\s+and\s+/i).map(a => a.includes(',') ? a.split(',').map(x => x.trim()).reverse().join(' ') : a.trim())
    const joinNames = list => list.length > 2 ? list.slice(0, -1).join(', ') + ' and ' + list.at(-1) : list.join(' and ')
    const parts = []
    if (f.author) parts.push(cv(joinNames(names(f.author))))
    else if (f.editor) parts.push(cv(joinNames(names(f.editor))) + ', editors')
    const isBook = ['book', 'phdthesis', 'mastersthesis', 'manual', 'proceedings'].includes(e.type)
    if (f.title) parts.push(isBook ? `<em>${cv(f.title)}</em>` : cv(f.title))
    const venue = []
    if (f.journal) venue.push(`<em>${cv(f.journal)}</em>`)
    if (f.booktitle) venue.push(`In <em>${cv(f.booktitle)}</em>`)
    if (f.volume) venue.push(f.number ? `${cv(f.volume)}(${cv(f.number)})` : cv(f.volume))
    if (f.pages) venue.push(cv(f.pages.replace(/-+/g, '--')))
    if (venue.length) parts.push(venue.join(', '))
    const pub = [f.publisher, f.school, f.institution, f.organization, f.address].filter(Boolean).map(cv)
    if (e.type === 'phdthesis') pub.unshift('PhD thesis')
    if (e.type === 'mastersthesis') pub.unshift("Master's thesis")
    if (pub.length) parts.push(pub.join(', '))
    if (f.note) parts.push(cv(f.note))
    if (f.year) parts.push(cv(f.month ? `${f.month} ${f.year}` : f.year))
    let html = parts.filter(Boolean).join('. ') + '.'
    if (f.doi) html += ` <a href="https://doi.org/${esc(f.doi)}">doi:${esc(f.doi)}</a>`
    else if (f.url) html += ` <a href="${esc(f.url)}"><code>${esc(f.url)}</code></a>`
    return html
}

function bibList(ctx) {
    const keys = ctx.nociteAll ? [...new Set([...ctx.citeOrder, ...Object.keys(ctx.bibEntries)])] : ctx.citeOrder
    const items = keys.filter(k => ctx.bibEntries[k]).map(k => {
        ctx.bib[k] ??= String(Object.keys(ctx.bib).length + 1)
        return `<li><span class="tex-bib-label" id="bib-${esc(k.replace(/[^\w:.-]/g, '_'))}">[${ctx.bib[k]}]</span> ${formatBibEntry(ctx.bibEntries[k], ctx)}</li>`
    })
    const missing = ctx.citeOrder.filter(k => !ctx.bibEntries[k] && !(k in ctx.bib))
    if (missing.length) ctx.caveats.add(`${missing.length} 条引用在 .bib 文件中未找到`)
    return `<h2 class="tex-bib-title" id="sec-bib">参考文献</h2><ol class="tex-bib">${items.join('')}</ol>`
}

// ---------- 解析工具 ----------
// 读取从 i 开始的 {…} 分组，返回 [内容, 结束位置]
function readGroup(s, i, open = '{', close = '}') {
    while (i < s.length && /\s/.test(s[i])) i++
    if (s[i] !== open) {
        if (open === '[') return [null, i]
        // 单个 token 作为参数
        if (s[i] === '\\') {
            const m = /^\\([a-zA-Z@]+|.)/.exec(s.slice(i))
            return [m[0], i + m[0].length]
        }
        return [s[i] ?? '', i + 1]
    }
    let depth = 0
    for (let j = i; j < s.length; j++) {
        const ch = s[j]
        if (ch === '\\') { j++; continue }
        if (ch === open) depth++
        else if (ch === close && --depth === 0) return [s.slice(i + 1, j), j + 1]
    }
    return [s.slice(i + 1), s.length]
}
function readOpt(s, i) {
    let k = i
    while (k < s.length && s[k] === ' ') k++
    if (s[k] !== '[') return [null, i]
    return readGroup(s, k, '[', ']')
}
// 查找与 \begin{env} 配对的 \end{env}
function findEnd(s, i, env) {
    const re = new RegExp(`\\\\(begin|end)\\{${env.replace(/[*]/g, '\\*')}\\}`, 'g')
    re.lastIndex = i
    let depth = 1, m
    while ((m = re.exec(s))) {
        if (m[1] === 'begin') depth++
        else if (--depth === 0) return [m.index, m.index + m[0].length]
    }
    return [s.length, s.length]
}

function readPreamble(pre, ctx) {
    collectDefs(pre, ctx)
    const grab = cmd => {
        const i = pre.search(new RegExp(`\\\\${cmd}\\s*[\\[{]`))
        if (i < 0) return null
        let j = i + cmd.length + 1
        const [, k] = readOpt(pre, j)
        return readGroup(pre, k)[0]
    }
    ctx.meta.title = grab('title')
    ctx.meta.author = grab('author')
    ctx.meta.date = grab('date')
    // \newtheorem{name}[shared]{Title} / \newtheorem{name}{Title}[within]
    for (const m of pre.matchAll(/\\newtheorem\*?\s*\{([^}]+)\}\s*(?:\[([^\]]+)\])?\s*\{([^}]+)\}/g)) {
        ctx.theoremNames[m[1]] = m[3]
        if (m[2]) ctx.sharedCounter[m[1]] = m[2]
    }
    const cls = /\\documentclass\s*(?:\[[^\]]*\])?\s*\{([^}]+)\}/.exec(pre)?.[1]
    ctx.meta.cls = cls
    if (cls && /beamer/.test(cls)) ctx.caveats.add('Beamer 幻灯片以连续文档形式显示')
    if (/\\usepackage[^\n]*\{[^}]*(tikz|pgfplots|pstricks)/.test(pre)) ctx.caveats.add('TikZ / PGF 绘图无法渲染，以占位框显示')
    if (/\\usepackage[^\n]*\{[^}]*ctex|\\documentclass[^\n]*\{ctex/.test(pre)) ctx.meta.cjk = true
    if (/\\bibliography\{|\\addbibresource/.test(pre)) ctx.hasBibFile = true
}

// 收集 \newcommand / \renewcommand / \def / \DeclareMathOperator，并从正文中移除
function collectDefs(s, ctx) {
    let out = '', i = 0
    const re = /\\(newcommand|renewcommand|providecommand|DeclareRobustCommand|def|DeclareMathOperator\*?|newenvironment|renewenvironment|let)\*?/g
    let m
    while ((m = re.exec(s))) {
        out += s.slice(i, m.index)
        let j = m.index + m[0].length
        const kind = m[1]
        try {
            if (kind === 'def') {
                const nm = /^\s*\\([a-zA-Z@]+)((?:#\d)*)/.exec(s.slice(j))
                if (!nm) { i = j; continue }
                j += nm[0].length
                const [body, k] = readGroup(s, j)
                defineMacro(ctx, nm[1], nm[2].length / 2, null, body)
                j = k
            } else if (kind === 'let') {
                const nm = /^\s*\\([a-zA-Z@]+)\s*=?\s*(\\[a-zA-Z@]+|.)/.exec(s.slice(j))
                if (nm) { defineMacro(ctx, nm[1], 0, null, nm[2]); j += nm[0].length }
            } else if (kind.startsWith('DeclareMathOperator')) {
                let [name, k] = readGroup(s, j)
                const [body, k2] = readGroup(s, k)
                name = name.replace(/^\\/, '')
                ctx.mathMacros['\\' + name] = `\\operatorname${kind.endsWith('*') ? '*' : ''}{${body}}`
                j = k2
            } else if (kind.endsWith('environment')) {
                const [name, k] = readGroup(s, j)
                const [nargs, k1] = readOpt(s, k)
                const [, k2] = readOpt(s, k1)
                const [begin, k3] = readGroup(s, k2)
                const [end, k4] = readGroup(s, k3)
                ctx.macros['env:' + name] = { n: Number(nargs ?? 0), begin, end }
                j = k4
            } else {
                let [name, k] = readGroup(s, j)
                const [nargs, k1] = readOpt(s, k)
                const [def, k2] = readOpt(s, k1)
                const [body, k3] = readGroup(s, k2)
                name = name.trim().replace(/^\\/, '')
                if (kind === 'providecommand' && ctx.macros[name]) { i = k3; re.lastIndex = k3; continue }
                defineMacro(ctx, name, Number(nargs ?? 0), def, body)
                j = k3
            }
        } catch { /* 忽略无法解析的定义 */ }
        i = j
        re.lastIndex = j
    }
    return out + s.slice(i)
}

function defineMacro(ctx, name, n, def, body) {
    ctx.macros[name] = { n, def, body }
    // 数学模式中同样可用
    if (!n) ctx.mathMacros['\\' + name] = body
    else ctx.mathMacros['\\' + name] = body // KaTeX 宏支持 #1 形式参数
}

// 展开用户宏（文本模式）
function expandMacro(s, i, name, ctx) {
    const mac = ctx.macros[name]
    let j = i
    const args = []
    if (mac.n) {
        let start = 0
        if (mac.def != null) {
            const [o, k] = readOpt(s, j)
            args.push(o ?? mac.def)
            j = k
            start = 1
        }
        for (let a = start; a < mac.n; a++) {
            const [g, k] = readGroup(s, j)
            args.push(g)
            j = k
        }
    }
    const body = mac.body.replace(/#(\d)/g, (_, d) => args[d - 1] ?? '')
    return [body, j]
}

// ---------- 数学 ----------
function renderMath(tex, display, ctx, { numbered = false, env } = {}) {
    let t = tex
    let tag = null
    // 收集 \label 以便引用（KaTeX 不支持 \label）；先替换为行内标记，便于按行分配编号
    const labels = []
    t = t.replace(/\\label\s*\{([^}]*)\}/g, (_, l) => `\\LRLBL{${labels.push(l.trim()) - 1}}`)
    const rowLabels = new Map() // 标签序号 -> 所在行编号
    const takeLabels = (r, num) => { for (const m of r.matchAll(/\\LRLBL\{(\d+)\}/g)) rowLabels.set(Number(m[1]), num) }
    if (env) {
        const e = env.replace('*', '')
        const star = env.endsWith('*')
        let inner = t
        if (e === 'multline') inner = `\\begin{gathered}${t}\\end{gathered}`
        else if (e === 'eqnarray') inner = `\\begin{aligned}${t.replace(/&\s*([=<>]|\\[a-z]+)\s*&/g, '&$1')}\\end{aligned}`
        else if (e === 'flalign') inner = `\\begin{aligned}${t}\\end{aligned}`
        else if (e === 'alignat') inner = `\\begin{alignedat}${t}\\end{alignedat}`
        else if (e === 'dmath' || e === 'displaymath' || e === 'math') inner = t
        else if (e === 'equation') inner = t
        else inner = `\\begin{${e === 'align' ? 'aligned' : e === 'gather' ? 'gathered' : e}}${t}\\end{${e === 'align' ? 'aligned' : e === 'gather' ? 'gathered' : e}}`
        // 编号：按行计数（\\ 分隔，\nonumber / \notag 跳过），整体使用一个编号列显示
        if (numbered && !star) {
            const rows = ['align', 'gather', 'eqnarray', 'flalign', 'alignat'].includes(e) ? splitRows(t) : [t]
            const nums = []
            for (const r of rows) {
                if (/\\(nonumber|notag)\b/.test(r) || !r.trim()) { nums.push(null); continue }
                const custom = /\\tag\*?\s*\{([^}]*)\}/.exec(r)
                if (custom) { nums.push(custom[1]); takeLabels(r, custom[1]); continue }
                ctx.counters.equation++
                nums.push(eqNum(ctx))
                takeLabels(r, eqNum(ctx))
            }
            inner = inner.replace(/\\(nonumber|notag)\b/g, '').replace(/\\tag\*?\s*\{[^}]*\}/g, '')
            tag = nums
        } else {
            const custom = /\\tag\*?\s*\{([^}]*)\}/.exec(t)
            if (custom) { tag = [custom[1]]; inner = inner.replace(/\\tag\*?\s*\{[^}]*\}/g, '') }
            inner = inner.replace(/\\(nonumber|notag)\b/g, '')
        }
        t = inner
    }
    // 公式中的引用：先用占位文本，全部转换完成后再替换为编号
    t = t.replace(/\\(eq)?ref\s*\{([^}]*)\}/g, (_, eq, key) => {
        const i = ctx.refs.push({ key: key.trim(), kind: 'ref' }) - 1
        return `${eq ? '(' : ''}\\text{ZQREF${i}Q}${eq ? ')' : ''}`
    })
    t = t.replace(/\\LRLBL\{\d+\}/g, '')
    const firstNum = tag?.find(Boolean)
    labels.forEach((l, i) => { ctx.labels[l] = { num: rowLabels.get(i) ?? firstNum ?? '', type: 'eq' } })
    let html
    try {
        html = katex.renderToString(t, {
            displayMode: display, throwOnError: true, strict: 'ignore', trust: false,
            macros: { '\\bm': '\\boldsymbol{#1}', '\\mathbbm': '\\mathbb{#1}', '\\si': '\\mathrm{#1}', '\\SI': '#1\\,\\mathrm{#2}', '\\num': '#1', '\\qty': '\\left(#1\\right)', '\\dd': '\\mathrm{d}', '\\abs': '\\left|#1\\right|', '\\norm': '\\left\\|#1\\right\\|', '\\RR': '\\mathbb{R}', '\\NN': '\\mathbb{N}', '\\ZZ': '\\mathbb{Z}', '\\QQ': '\\mathbb{Q}', '\\CC': '\\mathbb{C}', ...ctx.mathMacros },
        })
    } catch (e) {
        ctx.caveats.add('部分公式无法解析，以源码显示')
        html = `<code class="tex-err" title="${esc(String(e.message ?? e))}">${esc(display ? tex.trim() : '$' + tex + '$')}</code>`
    }
    if (!display) return html
    const id = labels[0] ? ` id="${esc(labelId(labels[0]))}"` : ''
    const nums = (tag ?? []).filter(Boolean)
    return `<div class="tex-display"${id}>${html}${nums.length ? `<span class="tex-eqno">${nums.map(n => `(${esc(String(n))})`).join('<br>')}</span>` : ''}</div>`
}

function splitRows(t) {
    const rows = []
    let depth = 0, last = 0
    for (let i = 0; i < t.length; i++) {
        const ch = t[i]
        if (ch === '{') depth++
        else if (ch === '}') depth--
        else if (ch === '\\' && t[i + 1] === '\\' && depth === 0) { rows.push(t.slice(last, i)); last = i + 2; i++ }
        else if (ch === '\\') {
            const m = /^\\(begin|end)\{/.exec(t.slice(i))
            if (m) depth += m[1] === 'begin' ? 1 : -1
            i++
        }
    }
    rows.push(t.slice(last))
    // 末尾空行不计编号
    if (rows.length > 1 && !rows.at(-1).trim()) rows.pop()
    return rows
}

const eqNum = ctx => ctx.hasChapter && ctx.counters.chapter ? `${chapterLabel(ctx)}.${ctx.counters.equation}` : String(ctx.counters.equation)
const chapterLabel = ctx => ctx.appendix ? String.fromCharCode(64 + ctx.counters.chapter) : String(ctx.counters.chapter)
const labelId = l => 'lbl-' + l.replace(/[^\w:.-]/g, '_')

// ---------- 主转换 ----------
function convert(s, ctx, opts = {}) {
    let out = ''
    let i = 0
    const n = s.length
    let guard = 0
    while (i < n) {
        if (++guard > 2_000_000) { ctx.caveats.add('文档过于复杂，部分内容被截断'); break }
        const ch = s[i]
        // 数学：$$…$$ \[…\] $…$ \(…\)
        if (ch === '$') {
            const display = s[i + 1] === '$'
            const close = display ? '$$' : '$'
            let j = i + close.length
            while (j < n) {
                if (s[j] === '\\') { j += 2; continue }
                if (s.startsWith(close, j)) break
                j++
            }
            out += renderMath(s.slice(i + close.length, j), display, ctx)
            i = j + close.length
            continue
        }
        if (ch === '\\') {
            if (s[i + 1] === '[' || s[i + 1] === '(') {
                const close = s[i + 1] === '[' ? '\\]' : '\\)'
                const j = s.indexOf(close, i + 2)
                const end = j < 0 ? n : j
                out += renderMath(s.slice(i + 2, end), s[i + 1] === '[', ctx)
                i = end + 2
                continue
            }
            const m = /^\\([a-zA-Z@]+\*?|.)/.exec(s.slice(i, i + 64))
            if (!m) { i++; continue }
            let name = m[1]
            let j = i + m[0].length
            // 带 * 的命令只对部分命令有意义
            if (name.endsWith('*') && !SECTIONS.includes(name.slice(0, -1)) && !['begin', 'end'].includes(name.slice(0, -1))) {
                name = name.slice(0, -1)
            }
            const r = command(name, s, j, ctx, opts)
            out += r[0]
            i = r[1]
            continue
        }
        if (ch === '{' ) {
            const [g, j] = readGroup(s, i)
            out += convert(g, ctx, opts)
            i = j
            continue
        }
        if (ch === '}') { i++; continue }
        if (ch === '~') { out += '&nbsp;'; i++; continue }
        if (ch === '&') { out += opts.inTable ? '\u0000CELL\u0000' : ' '; i++; continue }
        if (ch === '-' && s[i + 1] === '-') {
            if (s[i + 2] === '-') { out += '—'; i += 3 } else { out += '–'; i += 2 }
            continue
        }
        if (ch === '`' && s[i + 1] === '`') { out += '“'; i += 2; continue }
        if (ch === "'" && s[i + 1] === "'") { out += '”'; i += 2; continue }
        if (ch === '`') { out += '‘'; i++; continue }
        if (ch === '<') { out += '&lt;'; i++; continue }
        if (ch === '>') { out += '&gt;'; i++; continue }
        if (ch === '"') { out += '&quot;'; i++; continue }
        if (ch === '#' || ch === '^' || ch === '_') { i++; continue }
        out += ch === '&' ? '&amp;' : ch
        i++
    }
    return out
}

function command(name, s, j, ctx, opts) {
    // 用户宏优先
    if (ctx.macros[name] && !ctx.macros[name].env) {
        const [body, k] = expandMacro(s, j, name, ctx)
        return [convert(body, ctx, opts), k]
    }
    if (name === 'begin') {
        const [env, k] = readGroup(s, j)
        return environment(env.trim(), s, k, ctx, opts)
    }
    if (name === 'end') return ['', readGroup(s, j)[1]]

    const base = name.replace(/\*$/, '')
    if (SECTIONS.includes(base)) {
        const [short, k0] = readOpt(s, j)
        const [title, k] = readGroup(s, k0)
        return [section(base, name.endsWith('*'), title, short, ctx), k]
    }
    if (name in ACCENTS) {
        const [g, k] = readGroup(s, j)
        const t = convert(g, ctx, opts)
        return [(t || ' ') + ACCENTS[name], k]
    }
    if (Object.hasOwn(SYMBOLS, name)) {
        const v = SYMBOLS[name]
        // 控制词后的空格被吞掉
        let k = j
        if (/^[a-zA-Z]/.test(name)) while (s[k] === ' ') k++
        if (/^[a-zA-Z]/.test(name) && s[k] === '{' && s[k + 1] === '}') k += 2
        return [v, k]
    }
    if (Object.hasOwn(WRAP, name) && WRAP[name]) {
        // \bf 这类开关命令：作用到当前分组结束
        const isSwitch = ['bf', 'it', 'em', 'sl', 'tt', 'sc', 'sf', 'rm', 'tiny', 'scriptsize', 'footnotesize', 'small', 'large', 'Large', 'LARGE', 'huge', 'Huge', 'normalsize'].includes(name)
        let g, k
        if (isSwitch) { g = s.slice(j); k = s.length }
        else {
            if (name === 'verb') {
                const d = s[j]
                const e = s.indexOf(d, j + 1)
                return [`<code>${esc(s.slice(j + 1, e))}</code>`, e + 1]
            }
            if (name === 'makebox' || name === 'framebox') { k = readOpt(s, readOpt(s, j)[1])[1]; [g, k] = readGroup(s, k) }
            else [g, k] = readGroup(s, j)
        }
        const [tag, cls] = WRAP[name].split('.')
        return [`<${tag}${cls ? ` class="${cls}"` : ''}>${convert(g, ctx, opts)}</${tag}>`, k]
    }
    switch (name) {
        case 'textcolor': case 'color': {
            let [model, k] = readOpt(s, j)
            let [col, k1] = readGroup(s, k)
            const css = texColor(col, model)
            if (name === 'color') return [`<span style="color:${css}">${convert(s.slice(k1), ctx, opts)}</span>`, s.length]
            const [g, k2] = readGroup(s, k1)
            return [`<span style="color:${css}">${convert(g, ctx, opts)}</span>`, k2]
        }
        case 'colorbox': case 'highlight': case 'hl': {
            let k = j, css = '#ff0'
            if (name === 'colorbox') { const [model, k0] = readOpt(s, j); const [col, k1] = readGroup(s, k0); css = texColor(col, model); k = k1 }
            const [g, k2] = readGroup(s, k)
            return [`<span style="background:${css}">${convert(g, ctx, opts)}</span>`, k2]
        }
        case 'href': {
            const [url, k] = readGroup(s, j)
            const [txt, k1] = readGroup(s, k)
            return [`<a href="${esc(url.replace(/\\([#%&_~])/g, '$1'))}">${convert(txt, ctx, opts)}</a>`, k1]
        }
        case 'url': case 'nolinkurl': {
            const [url, k] = readGroup(s, j)
            const u = url.replace(/\\([#%&_~])/g, '$1')
            return [`<a href="${esc(u)}"><code>${esc(u)}</code></a>`, k]
        }
        case 'footnote': case 'footnotetext': {
            const [, k0] = readOpt(s, j)
            const [g, k] = readGroup(s, k0)
            const idx = ++ctx.counters.footnote
            ctx.footnotes.push({ idx, html: convert(g, ctx, opts) })
            return [`<sup class="tex-fn"><a href="#fn-${idx}" id="fnref-${idx}">${idx}</a></sup>`, k]
        }
        case 'thanks': {
            const [g, k] = readGroup(s, j)
            const idx = ++ctx.counters.footnote
            ctx.footnotes.push({ idx, html: convert(g, ctx, opts) })
            return [`<sup class="tex-fn"><a href="#fn-${idx}">${idx}</a></sup>`, k]
        }
        case 'label': {
            const [l, k] = readGroup(s, j)
            const key = l.trim()
            ctx.labels[key] ??= { num: opts.current?.() ?? ctx.lastNum ?? '', type: 'sec' }
            return [`<a class="tex-anchor" id="${esc(labelId(key))}"></a>`, k]
        }
        case 'ref': case 'eqref': case 'autoref': case 'cref': case 'Cref': case 'pageref': case 'nameref': case 'vref': {
            const [l, k] = readGroup(s, j)
            const keys = l.split(',').map(x => x.trim())
            const html = keys.map(key => {
                const i = ctx.refs.push({ key, kind: name }) - 1
                return `<a class="tex-ref" href="#${esc(labelId(key))}">\u0000REF${i}\u0000</a>`
            }).join(', ')
            return [name === 'eqref' ? `(${html})` : html, k]
        }
        case 'cite': case 'citep': case 'citet': case 'parencite': case 'textcite': case 'autocite': case 'citeauthor': case 'citeyear': case 'nocite': {
            let [o1, k] = readOpt(s, j)
            let [o2, k1] = readOpt(s, k)
            const [keys, k2] = readGroup(s, k1)
            const list = keys.split(',').map(x => x.trim()).filter(Boolean)
            for (const key of list) {
                if (key === '*') ctx.nociteAll = true
                else if (!ctx.citeOrder.includes(key)) ctx.citeOrder.push(key)
            }
            if (name === 'nocite') return ['', k2]
            const note = o2 ?? o1
            const html = list.map(key => {
                const i = ctx.refs.push({ key, kind: 'cite' }) - 1
                return `<a class="tex-cite" href="#bib-${esc(key.replace(/[^\w:.-]/g, '_'))}">\u0000REF${i}\u0000</a>`
            }).join(', ')
            return [`[${html}${note ? ', ' + convert(note, ctx, opts) : ''}]`, k2]
        }
        case 'includegraphics': {
            const [optStr, k] = readOpt(s, j)
            const [file, k1] = readGroup(s, k)
            return [image(file.trim(), optStr, ctx), k1]
        }
        case 'input': case 'include': case 'subfile': {
            // 能读取到的文件已在预处理阶段合并，这里只剩未找到的
            const [file, k] = readGroup(s, j)
            ctx.caveats.add('部分 \\input / \\include 引用的文件未找到')
            return [`<div class="tex-missing">📄 引用文件：${esc(file)}</div>`, k]
        }
        case 'caption': {
            const [, k0] = readOpt(s, j)
            const [g, k] = readGroup(s, k0)
            return [`\u0000CAPTION\u0000${convert(g, ctx, opts)}\u0000/CAPTION\u0000`, k]
        }
        case 'appendix':
            ctx.appendix = true
            ctx.counters[ctx.hasChapter ? 'chapter' : 'section'] = 0
            return ['', j]
        case 'title': case 'author': case 'date': {
            const [, k0] = readOpt(s, j)
            const [g, k] = readGroup(s, k0)
            ctx.meta[name] ??= g
            return ['', k]
        }
        case 'thispagestyle': case 'pagestyle': case 'pagenumbering': case 'setlength': case 'addtolength':
        case 'setcounter': case 'addtocounter': case 'vspace': case 'hspace': case 'bibliographystyle': case 'usepackage': case 'documentclass':
        case 'newtheorem': case 'theoremstyle': case 'geometry': case 'hypersetup': case 'graphicspath': case 'captionsetup': case 'setmainfont':
        case 'setCJKmainfont': case 'lstset': case 'definecolor': case 'numberwithin': case 'renewcommand': case 'addcontentsline': case 'markboth':
        case 'markright': case 'linespread': case 'fontsize': case 'label@': case 'rule': case 'phantom': case 'hphantom': case 'vphantom':
        case 'resizebox': case 'scalebox': case 'raisebox': case 'enlargethispage': case 'titleformat': case 'titlespacing': case 'setlist': {
            // 忽略：跳过所有参数
            let k = j
            const argc = { definecolor: 3, titleformat: 5, titlespacing: 4, setcounter: 2, addtocounter: 2, setlength: 2, addtolength: 2, addcontentsline: 3, markboth: 2, fontsize: 2, rule: 2, resizebox: 2, scalebox: 1, raisebox: 1, numberwithin: 2 }[name] ?? 1
            k = readOpt(s, k)[1]
            if (name === 'vspace' || name === 'hspace') { if (s[k] === '*') k++ }
            for (let a = 0; a < argc; a++) { k = readGroup(s, k)[1]; k = readOpt(s, k)[1] }
            // resizebox / scalebox / raisebox 的内容需要保留
            if (['resizebox', 'scalebox', 'raisebox'].includes(name)) {
                const [g, k2] = readGroup(s, k)
                return [convert(g, ctx, opts), k2]
            }
            if (['phantom', 'hphantom', 'vphantom'].includes(name)) return ['', k]
            if (name === 'vspace') return ['<div class="tex-vspace"></div>', k]
            if (name === 'hspace') return [' ', k]
            return ['', k]
        }
        case 'bibliography': case 'printbibliography': case 'addbibresource': {
            let k = readOpt(s, j)[1]
            if (name !== 'printbibliography') k = readGroup(s, k)[1]
            if (name === 'addbibresource') return ['', k]
            // 参考文献列表在全文转换完成后生成（需要知道所有引用）
            if (Object.keys(ctx.bibEntries).length) return ['\u0000BIBLIST\u0000', k]
            ctx.caveats.add('未找到 .bib 参考文献文件，引用以键名显示')
            return ['<h2 class="tex-bib-title">参考文献</h2><p class="tex-missing">（参考文献位于外部 .bib 文件中，未能读取）</p>', k]
        }
        case 'bibitem': {
            const [lbl, k0] = readOpt(s, j)
            const [key, k] = readGroup(s, k0)
            const idx = Object.keys(ctx.bib).length + 1
            const k2 = key.trim()
            ctx.bib[k2] = lbl ? convert(lbl, ctx, opts) : String(idx)
            return [`\u0000BIBITEM\u0000<span class="tex-bib-label" id="bib-${esc(k2.replace(/[^\w:.-]/g, '_'))}">[${ctx.bib[k2]}]</span> `, k]
        }
        case 'item': {
            const [lbl, k] = readOpt(s, j)
            // 标签本身是 HTML（可能含公式），存入表中，标记里只放编号
            if (lbl == null) return ['\u0000ITEM\u0000', k]
            ctx.itemLabels ??= []
            const i = ctx.itemLabels.push(convert(lbl, ctx, opts).replace(/\u0000/g, '')) - 1
            return [`\u0000ITEM[${i}]\u0000`, k]
        }
        case 'newline': case '\\': {
            let k = j
            if (s[k] === '*') k++
            k = readOpt(s, k)[1]
            return [opts.inTable ? '\u0000ROW\u0000' : '<br>', k]
        }
        case 'cline': case 'cmidrule': case 'hhline': {
            let k = readOpt(s, j)[1]
            if (s[k] === '(') k = s.indexOf(')', k) + 1
            return ['', readGroup(s, k)[1]]
        }
        case 'multicolumn': {
            const [cnt, k] = readGroup(s, j)
            const [, k1] = readGroup(s, k)
            const [g, k2] = readGroup(s, k1)
            return [`\u0000SPAN${Number(cnt) || 1}\u0000${convert(g, ctx, opts)}`, k2]
        }
        case 'multirow': {
            const [cnt, k] = readGroup(s, j)
            let k1 = readOpt(s, k)[1]
            k1 = readGroup(s, k1)[1]
            const [g, k2] = readGroup(s, k1)
            return [`\u0000RSPAN${Number(cnt) || 1}\u0000${convert(g, ctx, opts)}`, k2]
        }
        case 'abstractname': return ['摘要', j]
        case 'contentsname': return ['目录', j]
        case 'chaptername': return ['章', j]
        case 'figurename': return ['图', j]
        case 'tablename': return ['表', j]
        case 'refname': case 'bibname': return ['参考文献', j]
        case 'the': {
            const m = /^\s*\\?([a-zA-Z]+)/.exec(s.slice(j))
            return [String(ctx.counters[m?.[1]] ?? ''), j + (m?.[0].length ?? 0)]
        }
        case 'stepcounter': case 'refstepcounter': {
            const [c, k] = readGroup(s, j)
            ctx.counters[c] = (ctx.counters[c] ?? 0) + 1
            return ['', k]
        }
    }
    // 未知命令：如果带参数，保留参数内容
    if (/^[a-zA-Z@]+$/.test(name)) {
        let k = j
        while (s[k] === ' ') k++
        if (s[k] === '{') {
            const [g, k2] = readGroup(s, k)
            return [convert(g, ctx, opts), k2]
        }
        return ['', k]
    }
    return [esc(name), j]
}

function texColor(col, model) {
    col = col.trim()
    if (model === 'HTML') return '#' + col
    if (model === 'rgb') return `rgb(${col.split(',').map(v => Math.round(Number(v) * 255)).join(',')})`
    if (model === 'RGB') return `rgb(${col})`
    const named = { red: '#d32f2f', blue: '#1565c0', green: '#2e7d32', orange: '#ef6c00', purple: '#6a1b9a', gray: '#757575', cyan: '#00838f', magenta: '#ad1457', brown: '#6d4c41', violet: '#7b1fa2', teal: '#00796b', olive: '#827717', darkgray: '#555', lightgray: '#bbb', black: '#000', white: '#fff', yellow: '#f9a825' }
    const m = /^(\w+)!(\d+)(?:!(\w+))?$/.exec(col)
    if (m) return `color-mix(in srgb, ${named[m[1]] ?? m[1]} ${m[2]}%, ${m[3] ? named[m[3]] ?? m[3] : 'white'})`
    return named[col] ?? col
}

function section(kind, star, title, short, ctx) {
    const lvl = SECTIONS.indexOf(kind)
    let num = ''
    if (!star) {
        ctx.counters[kind]++
        for (const k of SECTIONS.slice(lvl + 1)) ctx.counters[k] = 0
        if (kind === 'chapter') { ctx.counters.equation = 0; ctx.counters.figure = 0; ctx.counters.table = 0 }
        const parts = []
        const start = ctx.hasChapter ? 1 : 2
        if (kind === 'part') num = toRoman(ctx.counters.part)
        else {
            for (let l = start; l <= lvl; l++) {
                const v = ctx.counters[SECTIONS[l]]
                parts.push(l === start && ctx.appendix ? String.fromCharCode(64 + v) : v)
            }
            num = lvl <= 4 ? parts.join('.') : ''
        }
    }
    const html = convert(title, ctx, {})
    const id = `sec-${ctx.toc.length}`
    const hl = Math.min(6, Math.max(1, lvl - (ctx.hasChapter ? 0 : 1)))
    ctx.toc.push({ id, lvl: hl, num, text: stripTags(short ? convert(short, ctx, {}) : html) })
    ctx.lastNum = num
    const label = kind === 'chapter' && num ? `<span class="tex-chapnum">${ctx.appendix ? `附录 ${num}` : `第 ${num} 章`}</span>` : kind === 'part' && num ? `<span class="tex-chapnum">第 ${num} 部分</span>` : num ? `<span class="tex-secnum">${num}</span>` : ''
    if (kind === 'paragraph' || kind === 'subparagraph') return `\n\n<strong class="tex-para" id="${id}">${html}</strong> `
    return `\n\n<h${hl} id="${id}" class="tex-${kind}">${label}${html}</h${hl}>\n\n`
}

const stripTags = s => s.replace(/<[^>]+>/g, '').replace(/\u0000[^\u0000]*\u0000/g, '').trim()
const toRoman = n => ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'][n] ?? String(n)

function image(file, optStr, ctx) {
    const width = /(?:^|,)\s*width\s*=\s*([\d.]+)\s*\\(textwidth|linewidth|columnwidth)/.exec(optStr ?? '')
    const scale = /(?:^|,)\s*scale\s*=\s*([\d.]+)/.exec(optStr ?? '')
    const absW = /(?:^|,)\s*width\s*=\s*([\d.]+)\s*(cm|mm|in|pt)/.exec(optStr ?? '')
    let style = ''
    if (width) style = `width:${Math.min(100, Number(width[1]) * 100)}%`
    else if (absW) style = `width:${Math.round(Number(absW[1]) * { cm: 37.8, mm: 3.78, in: 96, pt: 1.333 }[absW[2]])}px`
    else if (scale) style = `zoom:${scale[1]}`
    const url = ctx.resolveAsset?.(file)
    if (!url) {
        ctx.caveats.add('部分图片未找到或格式不支持（如 EPS）')
        return `<span class="tex-missing">🖼 ${esc(file)}</span>`
    }
    if (/\.(eps|ps)$/i.test(file)) ctx.caveats.add('EPS / PS 图片无法显示')
    return `<img class="tex-img" src="${esc(url)}" data-file="${esc(file)}" style="${style}" alt="${esc(file)}">`
}

function environment(env, s, k, ctx, opts) {
    const [bodyEnd, after] = findEnd(s, k, env)
    let body = s.slice(k, bodyEnd)
    const base = env.replace(/\*$/, '')

    // 用户定义的环境
    const user = ctx.macros['env:' + env]
    if (user) {
        const args = []
        let j = 0
        for (let a = 0; a < user.n; a++) { const [g, j2] = readGroup(body, j); args.push(g); j = j2 }
        const sub = (t) => t.replace(/#(\d)/g, (_, d) => args[d - 1] ?? '')
        return [convert(sub(user.begin) + body.slice(j) + user.end, ctx, opts), after]
    }
    if (MATH_ENVS.has(env)) {
        const display = env !== 'math'
        let inner = body
        let e = env
        if (base === 'alignat') { const [cols, j] = readGroup(body, 0); inner = `{${cols}}` + body.slice(j) }
        return [renderMath(inner, display, ctx, { numbered: NUMBERED_MATH.has(base), env: e }), after]
    }
    if (IGNORE_ENVS.has(env)) {
        if (env !== 'comment' && !env.startsWith('filecontents')) {
            ctx.caveats.add('TikZ / PGF 绘图无法渲染，以占位框显示')
            return ['<div class="tex-missing">[TikZ 图形]</div>', after]
        }
        return ['', after]
    }
    switch (base) {
        case 'document': return [convert(body, ctx, opts), after]
        case 'abstract': return [`<div class="tex-abstract"><div class="tex-abstract-title">摘要</div>${paragraphs(convert(body, ctx, opts))}</div>`, after]
        case 'itemize': case 'enumerate': case 'description': case 'compactitem': case 'compactenum': case 'inparaenum': case 'asparaenum': {
            const [, j] = readOpt(body, 0)
            const html = convert(body.slice(j), ctx, opts)
            return [list(base.includes('enum') ? 'enumerate' : base === 'description' ? 'description' : 'itemize', html, ctx), after]
        }
        case 'thebibliography': {
            const [, j] = readGroup(body, 0)
            const html = convert(body.slice(j), ctx, opts)
            const items = html.split('\u0000BIBITEM\u0000').slice(1).map(x => `<li>${x.trim()}</li>`).join('')
            return [`<h2 class="tex-bib-title" id="sec-bib">参考文献</h2><ol class="tex-bib">${items}</ol>`, after]
        }
        case 'figure': case 'wrapfigure': case 'SCfigure': case 'subfigure': case 'table': case 'wraptable': case 'sidewaystable': case 'sidewaysfigure': {
            let j = readOpt(body, 0)[1]
            if (base.startsWith('wrap') || base === 'subfigure') { j = readOpt(body, j)[1]; j = readGroup(body, j)[1] }
            const isTable = base.includes('table')
            const kind = isTable ? 'table' : 'figure'
            if (base !== 'subfigure') ctx.counters[kind]++
            const num = ctx.hasChapter && ctx.counters.chapter ? `${chapterLabel(ctx)}.${ctx.counters[kind]}` : String(ctx.counters[kind])
            const inner = convert(body.slice(j), ctx, { ...opts, current: () => num })
            let caption = ''
            const content = inner.replace(/\u0000CAPTION\u0000([\s\S]*?)\u0000\/CAPTION\u0000/g, (_, c) => { caption = c; return '' })
            const cap = caption ? `<figcaption><b>${isTable ? '表' : '图'} ${base === 'subfigure' ? '' : num}</b> ${caption}</figcaption>` : ''
            return [`<figure class="tex-${kind}">${isTable ? cap + content : content + cap}</figure>`, after]
        }
        case 'center': case 'centering': return [`<div class="tex-center">${paragraphs(convert(body, ctx, opts))}</div>`, after]
        case 'flushleft': case 'raggedright': return [`<div style="text-align:left">${paragraphs(convert(body, ctx, opts))}</div>`, after]
        case 'flushright': case 'raggedleft': return [`<div style="text-align:right">${paragraphs(convert(body, ctx, opts))}</div>`, after]
        case 'quote': case 'quotation': case 'verse': return [`<blockquote>${paragraphs(convert(body, ctx, opts))}</blockquote>`, after]
        case 'verbatim': case 'Verbatim': case 'lstlisting': case 'minted': case 'alltt': {
            let b = body
            if (base === 'minted') { const [lang, j] = readGroup(b, readOpt(b, 0)[1]); b = b.slice(j) }
            else if (base !== 'verbatim') b = b.slice(readOpt(b, 0)[1])
            return [`<pre class="tex-verb"><code>${esc(b.replace(/^\r?\n/, '').replace(/\s+$/, ''))}</code></pre>`, after]
        }
        case 'tabular': case 'tabularx': case 'tabular*': case 'longtable': case 'tabulary': case 'array': {
            let j = 0
            if (base === 'tabularx' || base === 'tabulary' || env === 'tabular*') j = readGroup(body, j)[1]
            j = readOpt(body, j)[1]
            const [spec, j2] = readGroup(body, j)
            return [table(spec, body.slice(j2), ctx, opts), after]
        }
        case 'minipage': {
            let j = readOpt(body, 0)[1]
            const [w, j2] = readGroup(body, j)
            const m = /([\d.]+)\s*\\(textwidth|linewidth)/.exec(w)
            const width = m ? `${Math.round(Number(m[1]) * 100)}%` : 'auto'
            return [`<div class="tex-minipage" style="width:${width}">${paragraphs(convert(body.slice(j2), ctx, opts))}</div>`, after]
        }
        case 'proof': {
            const [title, j] = readOpt(body, 0)
            return [`<div class="tex-proof"><em>${title ? convert(title, ctx, opts) : '证明'}.</em> ${paragraphs(convert(body.slice(j), ctx, opts))}<span class="tex-qed">∎</span></div>`, after]
        }
        case 'frame': {
            // Beamer 帧
            let j = readOpt(body, 0)[1]
            let title = ''
            if (body[j] === '{') { const [t, j2] = readGroup(body, j); title = t; j = j2 }
            const inner = body.slice(j).replace(/\\frametitle\s*\{([^}]*)\}/, (_, t) => { title = t; return '' })
            return [`<section class="tex-frame">${title ? `<h3 class="tex-frametitle">${convert(title, ctx, opts)}</h3>` : ''}${paragraphs(convert(inner, ctx, opts))}</section>`, after]
        }
        case 'multicols': {
            const [n, j] = readGroup(body, 0)
            return [`<div style="column-count:${Number(n) || 2};column-gap:2em">${paragraphs(convert(body.slice(j), ctx, opts))}</div>`, after]
        }
        case 'titlepage': return [`<div class="tex-titlepage">${paragraphs(convert(body, ctx, opts))}</div>`, after]
        case 'appendices': ctx.appendix = true; ctx.counters.chapter = 0; ctx.counters.section = 0; return [convert(body, ctx, opts), after]
    }
    if (ctx.theoremNames[base]) {
        const [title, j] = readOpt(body, 0)
        const counterKey = ctx.sharedCounter[base] ?? base
        let num = ''
        if (!env.endsWith('*')) {
            ctx.counters[counterKey] = (ctx.counters[counterKey] ?? 0) + 1
            const prefix = ctx.hasChapter ? ctx.counters.chapter : ctx.counters.section
            num = prefix ? `${prefix}.${ctx.counters[counterKey]}` : String(ctx.counters[counterKey])
        }
        const inner = convert(body.slice(j), ctx, { ...opts, current: () => num })
        const kind = ['definition', 'example', 'remark', 'note', 'exercise', 'problem'].includes(base) ? 'plain' : 'thm'
        return [`<div class="tex-theorem tex-${kind}"><b>${ctx.theoremNames[base]}${num ? ' ' + num : ''}</b>${title ? ` <span>(${convert(title, ctx, opts)})</span>` : ''}<b>.</b> ${paragraphs(inner)}</div>`, after]
    }
    // 未知环境：按普通内容处理
    if (!/^(small|footnotesize|large|Large|scriptsize|tiny|normalsize|spacing|singlespace|onehalfspace|doublespace|adjustbox|landscape|samepage|CJK\*?|otherlanguage|refsection|subequations|savenotes|threeparttable|tablenotes|columns|column|block|alertblock|exampleblock|onlyenv|overprint|scope)$/.test(base)) {
        ctx.caveats.add(`部分环境（如 ${base}）以普通文本显示`)
    }
    let j = 0
    if (/^(column|block|alertblock|exampleblock|CJK\*?|otherlanguage)$/.test(base)) {
        j = readOpt(body, 0)[1]
        if (base === 'CJK' || base === 'CJK*') { j = readGroup(body, j)[1]; j = readGroup(body, j)[1] }
        else if (base !== 'column') { const [t, j2] = readGroup(body, j); j = j2; return [`<div class="tex-block"><div class="tex-block-title">${convert(t, ctx, opts)}</div>${paragraphs(convert(body.slice(j), ctx, opts))}</div>`, after] }
        else j = readGroup(body, j)[1]
    }
    return [convert(body.slice(j), ctx, opts), after]
}

function list(kind, html, ctx) {
    const parts = html.split(/\u0000ITEM(\[\d+\])?\u0000/)
    // split 带捕获组：[前导, 标签1, 内容1, 标签2, 内容2, ...]
    const items = []
    for (let i = 1; i < parts.length; i += 2) items.push({ label: parts[i] ? ctx.itemLabels[Number(parts[i].slice(1, -1))] : undefined, body: parts[i + 1] ?? '' })
    if (kind === 'description') {
        return `<dl class="tex-dl">${items.map(it => `<dt>${it.label ?? ''}</dt><dd>${paragraphs(it.body)}</dd>`).join('')}</dl>`
    }
    const tag = kind === 'enumerate' ? 'ol' : 'ul'
    return `<${tag} class="tex-list">${items.map(it => `<li${it.label != null ? ' class="custom"' : ''}>${it.label != null ? `<span class="tex-li-label">${it.label}</span> ` : ''}${paragraphs(it.body, true)}</li>`).join('')}</${tag}>`
}

function table(spec, body, ctx, opts) {
    const aligns = []
    const borders = []
    let sp = spec.replace(/\*\{(\d+)\}\{([^}]*)\}/g, (_, n, x) => x.repeat(Number(n)))
    sp = sp.replace(/[@!>]\{[^}]*\}|<\{[^}]*\}/g, '')
    for (let i = 0; i < sp.length; i++) {
        const ch = sp[i]
        if ('lcrXLCRJ'.includes(ch)) aligns.push({ l: 'left', c: 'center', r: 'right', X: 'left', L: 'left', C: 'center', R: 'right', J: 'justify' }[ch])
        else if ('pmbw'.includes(ch)) { aligns.push('left'); i = readGroup(sp, i + 1)[1] - 1 }
        else if (ch === '|') borders[aligns.length] = true
    }
    const hasV = borders.some(Boolean)
    const html = convert(body, ctx, { ...opts, inTable: true })
    const rows = html.split('\u0000ROW\u0000')
    const rawRows = splitTableRows(body)
    const out = []
    rows.forEach((r, ri) => {
        const cells = r.split('\u0000CELL\u0000')
        if (cells.length === 1 && !stripTags(cells[0]).trim() && !/<img|katex/.test(cells[0])) return
        const hlineAbove = /\\(hline|toprule|midrule)/.test(rawRows[ri] ?? '')
        let col = 0
        const tds = cells.map(c => {
            let span = 1, rspan = 1
            c = c.replace(/\u0000SPAN(\d+)\u0000/, (_, n) => { span = Number(n); return '' })
            c = c.replace(/\u0000RSPAN(\d+)\u0000/, (_, n) => { rspan = Number(n); return '' })
            const al = aligns[col] ?? 'left'
            col += span
            return `<td${span > 1 ? ` colspan="${span}"` : ''}${rspan > 1 ? ` rowspan="${rspan}"` : ''} style="text-align:${al}">${c.trim()}</td>`
        })
        out.push(`<tr${hlineAbove && ri ? ' class="hl"' : ''}>${tds.join('')}</tr>`)
    })
    return `<div class="tex-table-wrap"><table class="tex-table${hasV ? ' vlines' : ''}">${out.join('')}</table></div>`
}

// 粗略按 \\ 拆分原始行，用于判断横线位置
function splitTableRows(body) {
    return body.split(/\\\\(?:\[[^\]]*\])?/)
}

// 按空行分段
function paragraphs(html, inline = false) {
    const blocks = html.split(/\n\s*\n/).map(b => b.trim()).filter(Boolean)
    if (inline && blocks.length <= 1) return blocks[0] ?? ''
    return blocks.map(b => /^<(h\d|div|figure|table|ul|ol|dl|pre|blockquote|section|p[ >])/.test(b) && /<\/(h\d|div|figure|table|ul|ol|dl|pre|blockquote|section|p)>$/.test(b) ? b : `<p>${b}</p>`).join('\n')
}

function finalize(html, ctx) {
    // 先生成 .bib 参考文献列表（确定编号），再解析引用
    if (html.includes('\u0000BIBLIST\u0000')) html = html.replace('\u0000BIBLIST\u0000', () => bibList(ctx)).replace(/\u0000BIBLIST\u0000/g, '')
    html = html.replace(/\u0000REF(\d+)\u0000|ZQREF(\d+)Q/g, (_, a, b) => {
        const i = a ?? b
        const r = ctx.refs[i]
        if (r.kind === 'cite') return esc(ctx.bib[r.key] ?? r.key)
        const l = ctx.labels[r.key]
        if (!l) { ctx.caveats.add('部分交叉引用无法解析（显示为 ??）'); return '??' }
        const prefix = { autoref: 1, cref: 1, Cref: 1 }[r.kind] ? (l.type === 'eq' ? '式 ' : '') : ''
        return esc(prefix + (l.num || '?'))
    })
    // 标题页
    const m = ctx.meta
    const titleBlock = m.title ? `<header class="tex-title">
        <h1>${convert(m.title, ctx, {})}</h1>
        ${m.author ? `<div class="tex-author">${convert(m.author.replace(/\\and\b/g, ' · '), ctx, {})}</div>` : ''}
        ${m.date !== '' ? `<div class="tex-date">${m.date != null ? convert(m.date, ctx, {}) : ''}</div>` : ''}
    </header>` : ''
    const toc = ctx.toc.length ? `<nav class="tex-toc"><div class="tex-toc-title">目录</div><ol>${ctx.toc.map(t => `<li style="padding-left:${(t.lvl - 1) * 1.2}em"><a href="#${t.id}">${t.num ? `<span>${t.num}</span>` : ''}${esc(t.text)}</a></li>`).join('')}</ol></nav>` : ''
    html = html.replace('\u0000MAKETITLE\u0000', titleBlock).replace('\u0000TOC\u0000', toc)
    html = html.replace(/\u0000[A-Z/]+\d*\u0000/g, '')
    let out = paragraphs(html)
    if (ctx.footnotes.length) {
        out += `<section class="tex-footnotes"><hr><ol>${ctx.footnotes.map(f => `<li id="fn-${f.idx}">${f.html} <a href="#fnref-${f.idx}" class="tex-fn-back">↩</a></li>`).join('')}</ol></section>`
    }
    return { html: out, toc: ctx.toc, meta: m, caveats: [...ctx.caveats] }
}
