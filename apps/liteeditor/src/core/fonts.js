// 字体管理：加载用户导入的字体（FontFace，DOM 与 canvas 均可使用）、列出系统字体、统一的字体下拉框
import { h, select, toast } from './dom.js'
import { mediaURL } from './files.js'

export const FONT_EXTS = ['ttf', 'otf', 'ttc', 'otc', 'woff', 'woff2']
export const isFontFile = p => FONT_EXTS.includes(String(p).split('.').pop().toLowerCase())

let user = []           // [{ file, path, family, label, sub, weight, style, size }]
let system = null       // [{ family, label }]
let fontDir = ''
const faces = new Map() // path -> FontFace
const listeners = new Set()

export const userFonts = () => user
export const systemFonts = () => system ?? []
export const userFontDir = () => fontDir
export function onFontsChange(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
}
const emit = () => { for (const fn of [...listeners]) fn() }

// 注册 / 注销 FontFace
async function sync(list) {
    const keep = new Set(list.map(f => f.path))
    for (const [p, face] of faces) if (!keep.has(p)) { document.fonts.delete(face); faces.delete(p) }
    await Promise.all(list.filter(f => !faces.has(f.path)).map(async f => {
        try {
            const face = new FontFace(f.family, `url("${mediaURL(f.path)}")`, { weight: String(f.weight), style: f.style })
            await face.load()
            document.fonts.add(face)
            faces.set(f.path, face)
        } catch (e) {
            console.warn('字体加载失败', f.file, e)
        }
    }))
    user = list.filter(f => faces.has(f.path))
    emit()
}

let ready = null
export function initFonts() {
    ready ??= (async () => {
        if (!window.lite?.fonts) return
        const r = await window.lite.fonts.list()
        fontDir = r.dir
        await sync(r.fonts)
        // 系统字体扫描较慢，放到后台
        window.lite.fonts.system().then(list => { system = list; emit() }).catch(() => { system = [] })
    })()
    return ready
}
export const fontsReady = () => ready ?? initFonts()

export async function importFonts(paths) {
    if (!paths?.length) return []
    const r = await window.lite.fonts.import(paths)
    await sync(r.fonts)
    if (r.added.length) {
        const fams = [...new Set(user.filter(f => r.added.includes(f.file)).map(f => f.label))]
        toast(`已导入字体：${fams.join('、') || r.added.join('、')}`, 'success', 3600)
    }
    if (r.failed.length) toast(`无法识别的字体文件：${r.failed.join('、')}`, 'error', 4200)
    return r.added
}

export async function pickAndImportFonts() {
    const paths = await window.lite.openDialog({ title: '导入字体', filters: [{ name: '字体文件', extensions: FONT_EXTS }] })
    return importFonts(paths)
}

export async function removeFont(file) {
    await sync(await window.lite.fonts.remove(file))
}

// ---------- 字体下拉框 ----------
// 选项值有两种形式：css —— '"Family", sans-serif'（文档 / 演示 / 图像）；name —— 'Family'（表格 / 视频）
const families = stack => String(stack ?? '').split(',').map(x => x.replace(/["']/g, '').trim().toLowerCase()).filter(Boolean)
export const fontValue = (family, fmt = 'css') => fmt === 'css' ? `"${family}", sans-serif` : family

// 返回分组后的选项：[[v, l], ..., { group, options }]
// stackOf：把选项值换算成 CSS font-family，用于去掉与内置项重复的系统字体
// current：当前值不在列表中时（例如文件使用了本机没有的字体）追加一项以便显示
export function fontOptions(builtins, { fmt = 'css', stackOf = v => v, importItem = true, current } = {}) {
    const seen = new Set(builtins.flatMap(([v]) => families(stackOf(v))))
    const group = (name, list) => {
        const options = []
        for (const f of list) {
            const k = f.family.toLowerCase()
            if (seen.has(k)) continue
            seen.add(k)
            options.push([fontValue(f.family, fmt), f.label === f.family ? f.label : `${f.label}（${f.family}）`])
        }
        return options.length ? { group: name, options } : null
    }
    const opts = [
        ...builtins,
        group('导入的字体', user.map(f => ({ family: f.family, label: f.label }))),
        group('系统字体', systemFonts()),
    ].filter(Boolean)
    const has = o => Array.isArray(o) ? o[0] === current : o.options.some(x => x[0] === current)
    if (current != null && current !== '' && !opts.some(has))
        opts.push({ group: '当前字体', options: [[current, String(current).split(',')[0].replace(/["']/g, '').trim()]] })
    if (importItem) opts.push({ group: '更多', options: [['__import__', '导入字体（TTF / OTF）…']] })
    return opts
}

// 自动随导入 / 删除字体刷新的字体下拉框；接口与 select() 相同
export function fontSelect(builtins, value, onchange, opts = {}) {
    const { fmt, stackOf, ...selOpts } = opts
    let cur = value
    const build = () => fontOptions(builtins, { fmt, stackOf, current: cur })
    const s = select(build(), value, v => {
        if (v === '__import__') {
            s.set(cur)
            pickAndImportFonts().then(added => {
                const f = user.find(x => added.includes(x.file))
                if (!f) return
                cur = fontValue(f.family, fmt)
                s.setOptions(build(), cur)
                onchange?.(cur)
            })
            return
        }
        cur = v
        onchange?.(v)
    }, selOpts)
    const off = onFontsChange(() => {
        // 已从页面移除的下拉框（面板重建）不再刷新
        if (!s.el.isConnected && s.el.dataset.mounted) return off()
        s.setOptions(build(), cur)
    })
    requestAnimationFrame(() => { s.el.dataset.mounted = '1' })
    // 按首个字体名匹配：计算样式中的 font-family 与选项值的引号 / 回退字体写法可能不同
    const set = s.set
    s.set = v => {
        const opts = [...s.el.options]
        const fam = families(stackOf?.(v) ?? v)[0]
        const hit = opts.find(o => o.value === String(v)) ?? opts.find(o => families(stackOf?.(o.value) ?? o.value)[0] === fam)
        cur = hit ? hit.value : v
        if (!hit) s.setOptions(build(), cur)
        set(cur)
    }
    fontsReady()
    return s
}

// 以 data URL 内嵌 text 中用到的导入字体：SVG foreignObject 栅格化与独立 HTML 文件无法访问应用内字体
const dataCache = new Map()
export async function embedFontCSS(text) {
    const used = user.filter(f => String(text).includes(f.family))
    const rules = await Promise.all(used.map(async f => {
        if (!dataCache.has(f.path)) {
            const bytes = await window.lite.readFile(f.path)
            let bin = ''
            for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000))
            const mime = { otf: 'font/otf', woff: 'font/woff', woff2: 'font/woff2' }[f.file.split('.').pop().toLowerCase()] ?? 'font/ttf'
            dataCache.set(f.path, `data:${mime};base64,${btoa(bin)}`)
        }
        return `@font-face{font-family:"${f.family.replace(/["\\]/g, '\\$&')}";src:url("${dataCache.get(f.path)}");font-weight:${f.weight};font-style:${f.style}}`
    }))
    return rules.join('\n')
}

export const fontPreview = (family, text = '永和九年 AaBbCc 123') => h('span.font-sample', { style: { fontFamily: `"${family}"` } }, text)
