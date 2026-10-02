// PPTX 解析：将 OOXML 演示文稿转换为绝对定位的 HTML 幻灯片
// 支持：母版 / 版式继承、主题配色与字体、文本框、段落与项目符号、形状（常见几何）、
// 图片（含裁剪）、表格、组合、连接线、背景（纯色 / 渐变 / 图片）、备注
import JSZip from 'jszip'

const NS = {
    a: 'http://schemas.openxmlformats.org/drawingml/2006/main',
    p: 'http://schemas.openxmlformats.org/presentationml/2006/main',
    r: 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
}
const EMU = 12700 // 1pt = 12700 EMU
const px = emu => emu / EMU * 96 / 72 // EMU -> CSS px

// ---------- XML 工具 ----------
const kids = (el, name) => el ? [...el.children].filter(c => c.localName === name) : []
const kid = (el, name) => el ? [...el.children].find(c => c.localName === name) ?? null : null
const path = (el, ...names) => names.reduce((e, n) => kid(e, n), el)
const attr = (el, name) => el?.getAttribute(name) ?? null
const num = (el, name, d = 0) => { const v = attr(el, name); return v == null ? d : Number(v) }
const rid = el => el?.getAttributeNS(NS.r, 'embed') ?? el?.getAttributeNS(NS.r, 'id') ?? el?.getAttribute('r:embed') ?? el?.getAttribute('r:id')

const parseXML = s => new DOMParser().parseFromString(s, 'application/xml')

const dirOf = p => p.replace(/[^/]*$/, '')
function resolvePath(base, target) {
    if (target.startsWith('/')) return target.slice(1)
    const parts = (dirOf(base) + target).split('/')
    const out = []
    for (const s of parts) {
        if (s === '..') out.pop()
        else if (s !== '.' && s !== '') out.push(s)
    }
    return out.join('/')
}

// ---------- 颜色 ----------
const PRESET = {
    black: '000000', white: 'FFFFFF', red: 'FF0000', green: '008000', blue: '0000FF', yellow: 'FFFF00',
    gray: '808080', grey: '808080', darkGray: 'A9A9A9', lightGray: 'D3D3D3', orange: 'FFA500', purple: '800080',
    navy: '000080', cyan: '00FFFF', magenta: 'FF00FF', silver: 'C0C0C0', maroon: '800000', olive: '808000',
    teal: '008080', lime: '00FF00', pink: 'FFC0CB', brown: 'A52A2A', gold: 'FFD700', transparent: '000000',
}
const SYS = { windowText: '000000', window: 'FFFFFF', btnFace: 'F0F0F0', highlight: '3399FF', highlightText: 'FFFFFF' }

function hexToRgb(hex) {
    const n = parseInt(hex, 16)
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}
function rgbToHsl([r, g, b]) {
    r /= 255; g /= 255; b /= 255
    const max = Math.max(r, g, b), min = Math.min(r, g, b)
    let hh = 0, s = 0
    const l = (max + min) / 2
    if (max !== min) {
        const d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        hh = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
        hh /= 6
    }
    return [hh, s, l]
}
function hslToRgb([hh, s, l]) {
    if (!s) return [l * 255, l * 255, l * 255]
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    const f = t => {
        t = (t + 1) % 1
        if (t < 1 / 6) return p + (q - p) * 6 * t
        if (t < 1 / 2) return q
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
        return p
    }
    return [f(hh + 1 / 3) * 255, f(hh) * 255, f(hh - 1 / 3) * 255]
}

// ---------- 几何形状 ----------
// 返回 SVG path（坐标基于 w × h）；未知形状返回 null（按矩形处理）
function presetPath(name, w, h, adj) {
    const m = Math.min(w, h)
    const a = (k, d) => (adj[k] ?? d) / 100000
    switch (name) {
        case 'rect': case 'flowChartProcess': case 'textRect': return null
        case 'roundRect': case 'flowChartAlternateProcess': {
            const r = m * a('adj', 16667)
            return `M${r},0H${w - r}A${r},${r} 0 0 1 ${w},${r}V${h - r}A${r},${r} 0 0 1 ${w - r},${h}H${r}A${r},${r} 0 0 1 0,${h - r}V${r}A${r},${r} 0 0 1 ${r},0Z`
        }
        case 'ellipse': case 'flowChartConnector':
            return `M0,${h / 2}A${w / 2},${h / 2} 0 1 1 ${w},${h / 2}A${w / 2},${h / 2} 0 1 1 0,${h / 2}Z`
        case 'triangle': case 'flowChartExtract': {
            const x = w * a('adj', 50000)
            return `M${x},0L${w},${h}H0Z`
        }
        case 'rtTriangle': return `M0,0L${w},${h}H0Z`
        case 'diamond': case 'flowChartDecision': return `M${w / 2},0L${w},${h / 2}L${w / 2},${h}L0,${h / 2}Z`
        case 'parallelogram': case 'flowChartInputOutput': {
            const x = m * a('adj', 25000)
            return `M${x},0H${w}L${w - x},${h}H0Z`
        }
        case 'trapezoid': {
            const x = m * a('adj', 25000)
            return `M0,${h}L${x},0H${w - x}L${w},${h}Z`
        }
        case 'pentagon': return `M${w / 2},0L${w},${h * 0.38}L${w * 0.82},${h}H${w * 0.18}L0,${h * 0.38}Z`
        case 'homePlate': {
            const x = w - m * a('adj', 50000)
            return `M0,0H${x}L${w},${h / 2}L${x},${h}H0Z`
        }
        case 'chevron': {
            const x = m * a('adj', 50000)
            return `M0,0H${w - x}L${w},${h / 2}L${w - x},${h}H0L${x},${h / 2}Z`
        }
        case 'hexagon': {
            const x = m * a('adj', 25000)
            return `M${x},0H${w - x}L${w},${h / 2}L${w - x},${h}H${x}L0,${h / 2}Z`
        }
        case 'octagon': {
            const x = m * a('adj', 29289)
            return `M${x},0H${w - x}L${w},${x}V${h - x}L${w - x},${h}H${x}L0,${h - x}V${x}Z`
        }
        case 'plus': {
            const x = m * a('adj', 25000)
            return `M${x},0H${w - x}V${x}H${w}V${h - x}H${w - x}V${h}H${x}V${h - x}H0V${x}H${x}Z`
        }
        case 'rightArrow': {
            const t = h * a('adj1', 50000), hd = m * a('adj2', 50000)
            const y0 = (h - t) / 2
            return `M0,${y0}H${w - hd}V0L${w},${h / 2}L${w - hd},${h}V${y0 + t}H0Z`
        }
        case 'leftArrow': {
            const t = h * a('adj1', 50000), hd = m * a('adj2', 50000)
            const y0 = (h - t) / 2
            return `M${w},${y0}H${hd}V0L0,${h / 2}L${hd},${h}V${y0 + t}H${w}Z`
        }
        case 'upArrow': {
            const t = w * a('adj1', 50000), hd = m * a('adj2', 50000)
            const x0 = (w - t) / 2
            return `M${x0},${h}V${hd}H0L${w / 2},0L${w},${hd}H${x0 + t}V${h}Z`
        }
        case 'downArrow': {
            const t = w * a('adj1', 50000), hd = m * a('adj2', 50000)
            const x0 = (w - t) / 2
            return `M${x0},0V${h - hd}H0L${w / 2},${h}L${w},${h - hd}H${x0 + t}V0Z`
        }
        case 'leftRightArrow': {
            const t = h * a('adj1', 50000), hd = m * a('adj2', 50000)
            const y0 = (h - t) / 2
            return `M0,${h / 2}L${hd},0V${y0}H${w - hd}V0L${w},${h / 2}L${w - hd},${h}V${y0 + t}H${hd}V${h}Z`
        }
        case 'star5': {
            const pts = []
            for (let i = 0; i < 10; i++) {
                const r = i % 2 ? 0.38 : 1
                const ang = -Math.PI / 2 + i * Math.PI / 5
                pts.push(`${w / 2 + Math.cos(ang) * w / 2 * r},${h / 2 + Math.sin(ang) * h / 2 * r * 1.05 + h * 0.03}`)
            }
            return 'M' + pts.join('L') + 'Z'
        }
        case 'flowChartTerminator': {
            const r = h / 2
            return `M${r},0H${w - r}A${r},${r} 0 0 1 ${w - r},${h}H${r}A${r},${r} 0 0 1 ${r},0Z`
        }
        case 'snip1Rect': {
            const x = m * a('adj', 16667)
            return `M0,0H${w - x}L${w},${x}V${h}H0Z`
        }
        case 'round1Rect': {
            const r = m * a('adj', 16667)
            return `M0,0H${w - r}A${r},${r} 0 0 1 ${w},${r}V${h}H0Z`
        }
        case 'round2SameRect': {
            const r = m * a('adj1', 16667)
            return `M${r},0H${w - r}A${r},${r} 0 0 1 ${w},${r}V${h}H0V${r}A${r},${r} 0 0 1 ${r},0Z`
        }
        case 'wedgeRectCallout': case 'wedgeRoundRectCallout': {
            const tx = w / 2 + w * a('adj1', -20833), ty = h / 2 + h * a('adj2', 62500)
            return `M0,0H${w}V${h}H${w * 0.58}L${tx},${ty}L${w * 0.25},${h}H0Z`
        }
        case 'line': case 'straightConnector1': return `M0,0L${w},${h}`
        case 'bentConnector2': return `M0,0H${w}V${h}`
        case 'bentConnector3': {
            const x = w * a('adj1', 50000)
            return `M0,0H${x}V${h}H${w}`
        }
        case 'curvedConnector3': return `M0,0C${w / 2},0 ${w / 2},${h} ${w},${h}`
        case 'donut': {
            const t = m * a('adj', 25000)
            return `M0,${h / 2}A${w / 2},${h / 2} 0 1 1 ${w},${h / 2}A${w / 2},${h / 2} 0 1 1 0,${h / 2}Z` +
                `M${t},${h / 2}A${w / 2 - t},${h / 2 - t} 0 1 0 ${w - t},${h / 2}A${w / 2 - t},${h / 2 - t} 0 1 0 ${t},${h / 2}Z`
        }
        case 'can': {
            const e = h * a('adj', 25000) / 2
            return `M0,${e}A${w / 2},${e} 0 0 1 ${w},${e}V${h - e}A${w / 2},${e} 0 0 1 0,${h - e}Z M0,${e}A${w / 2},${e} 0 0 0 ${w},${e}`
        }
        case 'cloud': case 'cloudCallout':
            return `M${w * .2},${h * .85}C${-w * .05},${h * .85} ${-w * .02},${h * .45} ${w * .18},${h * .45}C${w * .15},${h * .1} ${w * .5},${h * .02} ${w * .55},${h * .25}` +
                `C${w * .7},${-h * .02} ${w * .98},${h * .15} ${w * .85},${h * .45}C${w * 1.05},${h * .55} ${w * .98},${h * .9} ${w * .78},${h * .85}C${w * .7},${h * 1.02} ${w * .35},${h * 1.02} ${w * .2},${h * .85}Z`
        case 'heart':
            return `M${w / 2},${h * .25}C${w / 2},0 0,0 0,${h * .3}C0,${h * .6} ${w / 2},${h * .8} ${w / 2},${h}C${w / 2},${h * .8} ${w},${h * .6} ${w},${h * .3}C${w},0 ${w / 2},0 ${w / 2},${h * .25}Z`
        case 'blockArc': case 'arc': {
            return `M0,${h / 2}A${w / 2},${h / 2} 0 0 1 ${w},${h / 2}`
        }
        default: return undefined
    }
}

// 自定义几何（a:custGeom）
function customPath(geom, w, h) {
    const out = []
    for (const p of kids(kid(geom, 'pathLst'), 'path')) {
        const pw = num(p, 'w', 0) || w, ph = num(p, 'h', 0) || h
        const sx = w / pw, sy = h / ph
        const pt = el => { const q = kid(el, 'pt'); return [num(q, 'x') * sx, num(q, 'y') * sy] }
        let cur = [0, 0]
        for (const c of p.children) {
            const pts = kids(c, 'pt').map(q => [num(q, 'x') * sx, num(q, 'y') * sy])
            switch (c.localName) {
                case 'moveTo': cur = pt(c); out.push(`M${cur}`); break
                case 'lnTo': cur = pt(c); out.push(`L${cur}`); break
                case 'cubicBezTo': out.push(`C${pts.join(' ')}`); cur = pts.at(-1); break
                case 'quadBezTo': out.push(`Q${pts.join(' ')}`); cur = pts.at(-1); break
                case 'close': out.push('Z'); break
                case 'arcTo': {
                    const wr = num(c, 'wR') * sx, hr = num(c, 'hR') * sy
                    const st = num(c, 'stAng') / 60000 * Math.PI / 180, sw = num(c, 'swAng') / 60000 * Math.PI / 180
                    const cx = cur[0] - wr * Math.cos(st), cy = cur[1] - hr * Math.sin(st)
                    const end = [cx + wr * Math.cos(st + sw), cy + hr * Math.sin(st + sw)]
                    out.push(`A${wr},${hr} 0 ${Math.abs(sw) > Math.PI ? 1 : 0} ${sw > 0 ? 1 : 0} ${end}`)
                    cur = end
                    break
                }
            }
        }
    }
    return out.join('')
}

// ---------- 演示文稿 ----------
export class Pptx {
    static async open(buf) {
        const p = new Pptx()
        await p.load(buf)
        return p
    }

    urls = []
    cache = new Map()
    lossy = new Set() // 记录无法完整还原的内容，供界面提示

    async load(buf) {
        this.zip = await JSZip.loadAsync(buf)
        const presPath = await this.mainPart()
        this.presPath = presPath
        const pres = await this.xml(presPath)
        this.pres = pres
        const sz = path(pres.documentElement, 'sldSz')
        this.width = px(num(sz, 'cx', 9144000))
        this.height = px(num(sz, 'cy', 6858000))
        const rels = await this.rels(presPath)
        this.slidePaths = kids(path(pres.documentElement, 'sldIdLst'), 'sldId')
            .map(s => rels[rid(s)]?.target).filter(Boolean)
        this.meta = await this.readMeta()
        this.defaultText = path(pres.documentElement, 'defaultTextStyle')
    }

    async mainPart() {
        const ct = await this.text('[Content_Types].xml')
        if (ct) {
            const m = /PartName="\/([^"]+)"\s+ContentType="application\/vnd\.ms-powerpoint\.(?:presentation|slideshow|template)\.macroEnabled\.main\+xml"|PartName="\/([^"]+)"\s+ContentType="application\/vnd\.openxmlformats-officedocument\.presentationml\.(?:presentation|slideshow|template)\.main\+xml"/.exec(ct)
            if (m) return m[1] ?? m[2]
        }
        if (this.zip.file('ppt/presentation.xml')) return 'ppt/presentation.xml'
        throw new Error('不是有效的 PowerPoint 演示文稿')
    }

    async readMeta() {
        const core = await this.xml('docProps/core.xml').catch(() => null)
        const app = await this.xml('docProps/app.xml').catch(() => null)
        const t = n => [...(core?.getElementsByTagName('*') ?? [])].find(e => e.localName === n)?.textContent?.trim()
        return {
            title: t('title'), creator: t('creator'), modified: t('modified'), lastModifiedBy: t('lastModifiedBy'),
            app: [...(app?.getElementsByTagName('*') ?? [])].find(e => e.localName === 'Application')?.textContent,
        }
    }

    get count() { return this.slidePaths.length }

    async text(p) { return this.zip.file(p)?.async('string') ?? null }
    async xml(p) {
        if (this.cache.has('x:' + p)) return this.cache.get('x:' + p)
        const s = await this.text(p)
        if (s == null) throw new Error('缺少部件 ' + p)
        const doc = parseXML(s)
        this.cache.set('x:' + p, doc)
        return doc
    }
    async rels(p) {
        const key = 'r:' + p
        if (this.cache.has(key)) return this.cache.get(key)
        const relPath = dirOf(p) + '_rels/' + p.split('/').pop() + '.rels'
        const out = {}
        const s = await this.text(relPath)
        if (s) {
            for (const r of parseXML(s).documentElement.children) {
                const external = attr(r, 'TargetMode') === 'External'
                out[attr(r, 'Id')] = {
                    type: attr(r, 'Type')?.split('/').pop(),
                    target: external ? attr(r, 'Target') : resolvePath(p, attr(r, 'Target')),
                    external,
                }
            }
        }
        this.cache.set(key, out)
        return out
    }
    async mediaURL(p) {
        const key = 'm:' + p
        if (this.cache.has(key)) return this.cache.get(key)
        const f = this.zip.file(p)
        if (!f) return null
        const ext = p.split('.').pop().toLowerCase()
        const type = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', bmp: 'image/bmp', svg: 'image/svg+xml', webp: 'image/webp', tif: 'image/tiff', tiff: 'image/tiff', mp4: 'video/mp4', m4v: 'video/mp4', mp3: 'audio/mpeg', wav: 'audio/wav', m4a: 'audio/mp4' }[ext]
        if (['emf', 'wmf', 'tif', 'tiff'].includes(ext)) this.lossy.add('部分 EMF/WMF/TIFF 矢量图无法显示')
        const blob = new Blob([await f.async('uint8array')], { type: type ?? 'application/octet-stream' })
        const url = URL.createObjectURL(blob)
        this.urls.push(url)
        this.cache.set(key, url)
        return url
    }

    // 读取幻灯片 → 版式 → 母版 → 主题 的继承链
    async chain(slidePath) {
        const key = 'c:' + slidePath
        if (this.cache.has(key)) return this.cache.get(key)
        const slide = await this.xml(slidePath)
        const sRels = await this.rels(slidePath)
        const layoutPath = Object.values(sRels).find(r => r.type === 'slideLayout')?.target
        const layout = layoutPath ? await this.xml(layoutPath) : null
        const lRels = layoutPath ? await this.rels(layoutPath) : {}
        const masterPath = Object.values(lRels).find(r => r.type === 'slideMaster')?.target
        const master = masterPath ? await this.xml(masterPath) : null
        const mRels = masterPath ? await this.rels(masterPath) : {}
        const themePath = Object.values(mRels).find(r => r.type === 'theme')?.target
        const theme = themePath ? await this.xml(themePath) : null
        const notesPath = Object.values(sRels).find(r => r.type === 'notesSlide')?.target
        const c = {
            slide: { doc: slide, path: slidePath, rels: sRels },
            layout: layout && { doc: layout, path: layoutPath, rels: lRels },
            master: master && { doc: master, path: masterPath, rels: mRels },
            theme, notesPath,
        }
        c.colors = this.themeColors(theme)
        c.fonts = this.themeFonts(theme)
        c.clrMap = this.clrMap(slide, layout, master)
        this.cache.set(key, c)
        return c
    }

    themeColors(theme) {
        const out = {}
        const scheme = theme && [...theme.getElementsByTagNameNS(NS.a, 'clrScheme')][0]
        for (const c of scheme?.children ?? []) {
            const v = c.firstElementChild
            out[c.localName] = v?.localName === 'sysClr' ? attr(v, 'lastClr') ?? SYS[attr(v, 'val')] : attr(v, 'val')
        }
        return out
    }
    themeFonts(theme) {
        const fs = theme && [...theme.getElementsByTagNameNS(NS.a, 'fontScheme')][0]
        const pick = n => {
            const f = kid(fs, n)
            return { latin: attr(kid(f, 'latin'), 'typeface'), ea: attr(kid(f, 'ea'), 'typeface') }
        }
        return { major: pick('majorFont'), minor: pick('minorFont') }
    }
    clrMap(slide, layout, master) {
        const ov = el => {
            const o = path(el?.documentElement, 'clrMapOvr')
            return kid(o, 'overrideClrMapping')
        }
        const m = ov(slide) ?? ov(layout) ?? path(master?.documentElement, 'clrMap')
        const map = { bg1: 'lt1', tx1: 'dk1', bg2: 'lt2', tx2: 'dk2' }
        if (m) for (const a of m.attributes) map[a.name] = a.value
        return map
    }

    // 解析颜色节点（srgbClr / schemeClr / ... 及其变换）
    color(el, c, phClr) {
        if (!el) return null
        let hex, alpha = 1
        switch (el.localName) {
            case 'srgbClr': hex = attr(el, 'val'); break
            case 'scrgbClr': hex = [num(el, 'r'), num(el, 'g'), num(el, 'b')].map(v => Math.round(v / 100000 * 255).toString(16).padStart(2, '0')).join(''); break
            case 'sysClr': hex = attr(el, 'lastClr') ?? SYS[attr(el, 'val')] ?? '000000'; break
            case 'prstClr': hex = PRESET[attr(el, 'val')] ?? '000000'; break
            case 'hslClr': hex = hslToRgb([num(el, 'hue') / 21600000, num(el, 'sat') / 100000, num(el, 'lum') / 100000]).map(v => Math.round(v).toString(16).padStart(2, '0')).join(''); break
            case 'schemeClr': {
                let v = attr(el, 'val')
                if (v === 'phClr') { if (phClr) return this.applyMods(phClr, el); v = 'tx1' }
                v = c.clrMap[v] ?? v
                hex = c.colors[v] ?? '000000'
                break
            }
            default: return null
        }
        return this.applyMods({ hex, alpha }, el)
    }
    scheme(name, c) {
        return this.color(parseXML(`<a:schemeClr xmlns:a="${NS.a}" val="${name}"/>`).documentElement, c)
    }
    applyMods(base, el) {
        let [r, g, b] = hexToRgb(base.hex ?? '000000')
        let alpha = base.alpha ?? 1
        for (const m of el.children) {
            const v = num(m, 'val') / 100000
            switch (m.localName) {
                case 'alpha': alpha = v; break
                case 'alphaMod': alpha *= v; break
                case 'lumMod': case 'lumOff': case 'satMod': case 'hueMod': case 'hueOff': case 'satOff': {
                    const hsl = rgbToHsl([r, g, b])
                    if (m.localName === 'lumMod') hsl[2] *= v
                    if (m.localName === 'lumOff') hsl[2] += v
                    if (m.localName === 'satMod') hsl[1] *= v
                    if (m.localName === 'satOff') hsl[1] += v
                    if (m.localName === 'hueMod') hsl[0] *= v
                    if (m.localName === 'hueOff') hsl[0] += num(m, 'val') / 21600000
                    hsl[1] = Math.min(1, Math.max(0, hsl[1])); hsl[2] = Math.min(1, Math.max(0, hsl[2]))
                    ;[r, g, b] = hslToRgb(hsl)
                    break
                }
                case 'tint': r += (255 - r) * (1 - v); g += (255 - g) * (1 - v); b += (255 - b) * (1 - v); break
                case 'shade': r *= v; g *= v; b *= v; break
                case 'inv': r = 255 - r; g = 255 - g; b = 255 - b; break
                case 'gray': { const y = r * .3 + g * .59 + b * .11; r = g = b = y; break }
            }
        }
        const cl = x => Math.round(Math.min(255, Math.max(0, x)))
        const hex = [r, g, b].map(x => cl(x).toString(16).padStart(2, '0')).join('')
        return { hex, alpha, css: alpha >= 1 ? '#' + hex : `rgba(${cl(r)},${cl(g)},${cl(b)},${+alpha.toFixed(3)})` }
    }
    colorOf(parent, c, phClr) {
        if (!parent) return null
        for (const ch of parent.children) {
            const col = this.color(ch, c, phClr)
            if (col) return col
        }
        return null
    }

    // 填充：返回 CSS background 值；'none' 表示无填充；null 表示未指定
    async fill(spPr, c, part, phClr) {
        if (!spPr) return null
        for (const f of spPr.children) {
            switch (f.localName) {
                case 'noFill': return 'none'
                case 'solidFill': return this.colorOf(f, c, phClr)?.css ?? null
                case 'gradFill': {
                    const stops = kids(kid(f, 'gsLst'), 'gs')
                        .map(g => ({ pos: num(g, 'pos') / 1000, col: this.colorOf(g, c, phClr)?.css ?? '#000' }))
                        .sort((a, b) => a.pos - b.pos)
                    if (!stops.length) return null
                    const lin = kid(f, 'lin')
                    const list = stops.map(s => `${s.col} ${s.pos}%`).join(', ')
                    if (kid(f, 'path')) return `radial-gradient(circle, ${list})`
                    const ang = (num(lin, 'ang', 0) / 60000 + 90) % 360
                    return `linear-gradient(${ang}deg, ${list})`
                }
                case 'blipFill': {
                    const url = await this.blip(f, part)
                    return url ? `center / cover no-repeat url("${url}")` : null
                }
                case 'pattFill': {
                    this.lossy.add('图案填充以前景色近似显示')
                    return this.colorOf(kid(f, 'fgClr'), c, phClr)?.css ?? null
                }
                case 'grpFill': return 'group'
            }
        }
        return null
    }
    async blip(blipFill, part) {
        const b = kid(blipFill, 'blip')
        const id = rid(b)
        const rel = id && part.rels[id]
        if (!rel || rel.external) return null
        // 优先使用 SVG 版本
        const svg = [...(b?.getElementsByTagName('*') ?? [])].find(e => e.localName === 'svgBlip')
        const svgRel = svg && part.rels[rid(svg)]
        return this.mediaURL(svgRel?.target ?? rel.target)
    }

    // 查找主题中的样式矩阵（fillRef / lnRef）
    styleRef(c, kind, idx) {
        const fmt = c.theme && [...c.theme.getElementsByTagNameNS(NS.a, 'fmtScheme')][0]
        if (!fmt || !idx) return null
        if (kind === 'fill') {
            if (idx >= 1001) return [...(kid(fmt, 'bgFillStyleLst')?.children ?? [])][idx - 1001] ?? null
            return [...(kid(fmt, 'fillStyleLst')?.children ?? [])][idx - 1] ?? null
        }
        if (kind === 'ln') return [...(kid(fmt, 'lnStyleLst')?.children ?? [])][idx - 1] ?? null
        return null
    }

    // ---------- 渲染 ----------
    async renderSlide(i) {
        const slidePath = this.slidePaths[i]
        const c = await this.chain(slidePath)
        const root = document.createElement('div')
        root.className = 'pp-slide'
        root.style.width = this.width + 'px'
        root.style.height = this.height + 'px'
        root.style.background = await this.background(c) ?? '#fff'

        const ctx = { c, root }
        const showMasterSp = el => attr(el?.documentElement, 'showMasterSp') !== '0'
        // 母版与版式上的非占位符形状（例如 Logo、装饰条）
        if (c.master && showMasterSp(c.slide.doc) && showMasterSp(c.layout?.doc)) await this.renderTree(c.master, ctx, root, true)
        if (c.layout && showMasterSp(c.slide.doc)) await this.renderTree(c.layout, ctx, root, true)
        await this.renderTree(c.slide, ctx, root, false)
        const hidden = attr(c.slide.doc.documentElement, 'show') === '0'
        return { el: root, hidden }
    }

    async background(c) {
        for (const part of [c.slide, c.layout, c.master]) {
            const bg = path(part?.doc.documentElement, 'cSld', 'bg')
            if (!bg) continue
            const pr = kid(bg, 'bgPr')
            if (pr) {
                const f = await this.fill(pr, c, part)
                if (f && f !== 'none') return f
            }
            const ref = kid(bg, 'bgRef')
            if (ref) {
                const phClr = this.colorOf(ref, c)
                const style = this.styleRef(c, 'fill', num(ref, 'idx'))
                if (style) {
                    const wrap = { children: [style] }
                    const f = await this.fill(wrap, c, c.master, phClr)
                    if (f && f !== 'none') return f
                }
                if (phClr) return phClr.css
            }
        }
        return null
    }

    async renderTree(part, ctx, into, skipPlaceholders) {
        const tree = path(part.doc.documentElement, 'cSld', 'spTree')
        if (!tree) return
        for (const el of tree.children) await this.renderNode(el, part, ctx, into, skipPlaceholders, null)
    }

    // 占位符匹配：先按 idx，再按 type
    findPlaceholder(part, ph) {
        if (!part || !ph) return null
        const type = attr(ph, 'type') ?? 'body'
        const idx = attr(ph, 'idx')
        const all = [...part.doc.getElementsByTagNameNS(NS.p, 'ph')]
        const norm = t => (t === 'ctrTitle' ? 'title' : t === 'subTitle' ? 'body' : t) ?? 'body'
        let hit = idx != null ? all.find(p => attr(p, 'idx') === idx) : null
        hit ??= all.find(p => (attr(p, 'type') ?? 'body') === type)
        hit ??= all.find(p => norm(attr(p, 'type')) === norm(type))
        let e = hit
        while (e && !['sp', 'pic', 'graphicFrame'].includes(e.localName)) e = e.parentElement
        return e
    }

    async renderNode(el, part, ctx, into, skipPh, group) {
        const name = el.localName
        if (name === 'AlternateContent') {
            const choice = kid(el, 'Choice'), fb = kid(el, 'Fallback')
            // 优先使用兼容性最好的 Fallback（通常是图片）
            const use = fb ?? choice
            for (const ch of use?.children ?? []) await this.renderNode(ch, part, ctx, into, skipPh, group)
            return
        }
        if (!['sp', 'pic', 'grpSp', 'graphicFrame', 'cxnSp'].includes(name)) return
        const nv = [...el.children].find(n => n.localName.startsWith('nv'))
        const ph = path(nv, 'nvPr', 'ph')
        if (skipPh && ph) return
        if (attr(kid(nv, 'cNvPr'), 'hidden') === '1') return

        const { c } = ctx
        // 继承链：幻灯片形状 → 版式占位符 → 母版占位符
        const inh = []
        if (ph && part === c.slide) {
            const l = this.findPlaceholder(c.layout, ph)
            if (l) inh.push(l)
            const m = this.findPlaceholder(c.master, ph)
            if (m) inh.push(m)
        } else if (ph && part === c.layout) {
            const m = this.findPlaceholder(c.master, ph)
            if (m) inh.push(m)
        }
        const spPr = kid(el, 'spPr') ?? kid(el, 'grpSpPr')
        const xfrmOf = e => {
            const pr = kid(e, 'spPr') ?? kid(e, 'grpSpPr')
            return kid(pr, 'xfrm') ?? kid(e, 'xfrm')
        }
        let xfrm = xfrmOf(el)
        if (!xfrm || !kid(xfrm, 'off')) xfrm = inh.map(xfrmOf).find(x => x && kid(x, 'off')) ?? xfrm
        const off = kid(xfrm, 'off'), ext = kid(xfrm, 'ext')
        let box = { x: px(num(off, 'x')), y: px(num(off, 'y')), w: px(num(ext, 'cx')), h: px(num(ext, 'cy')) }
        if (group) box = group.map(box)
        const rot = num(xfrm, 'rot') / 60000
        const flipH = attr(xfrm, 'flipH') === '1', flipV = attr(xfrm, 'flipV') === '1'

        const node = document.createElement('div')
        node.className = 'pp-el pp-' + name
        Object.assign(node.style, { left: box.x + 'px', top: box.y + 'px', width: box.w + 'px', height: box.h + 'px' })
        const tf = []
        if (rot) tf.push(`rotate(${rot}deg)`)
        if (flipH) tf.push('scaleX(-1)')
        if (flipV) tf.push('scaleY(-1)')
        if (tf.length) node.style.transform = tf.join(' ')

        if (name === 'grpSp') {
            const ch = path(el, 'grpSpPr', 'xfrm')
            const cOff = kid(ch, 'chOff'), cExt = kid(ch, 'chExt')
            const cx = px(num(cOff, 'x')), cy = px(num(cOff, 'y'))
            const cw = px(num(cExt, 'cx')) || box.w, chh = px(num(cExt, 'cy')) || box.h
            const sx = box.w / (cw || 1), sy = box.h / (chh || 1)
            // 子元素坐标相对组合
            const map = b => ({ x: (b.x - cx) * sx, y: (b.y - cy) * sy, w: b.w * sx, h: b.h * sy })
            node.classList.add('pp-group')
            const grpFill = await this.fill(spPr, c, part)
            for (const ch2 of el.children) await this.renderNode(ch2, part, ctx, node, skipPh, { map, fill: grpFill ?? group?.fill })
            into.append(node)
            return
        }

        if (name === 'pic') {
            const blipFill = kid(el, 'blipFill')
            const url = await this.blip(blipFill, part)
            const media = path(nv, 'nvPr')
            const vid = [...(media?.children ?? [])].find(e => ['videoFile', 'audioFile'].includes(e.localName))
            const ext2 = [...(media?.getElementsByTagName('*') ?? [])].find(e => e.localName === 'media')
            const mediaRel = (vid && part.rels[rid(vid)]) || (ext2 && part.rels[rid(ext2)])
            if (mediaRel && !mediaRel.external && /\.(mp4|m4v|webm|mov|mp3|wav|m4a)$/i.test(mediaRel.target)) {
                const murl = await this.mediaURL(mediaRel.target)
                const isAudio = /\.(mp3|wav|m4a)$/i.test(mediaRel.target) || vid?.localName === 'audioFile'
                const m = document.createElement(isAudio ? 'audio' : 'video')
                m.src = murl
                m.controls = true
                m.preload = 'metadata'
                if (url && !isAudio) m.poster = url
                m.className = 'pp-media'
                node.append(m)
            } else if (url) {
                const img = document.createElement('img')
                img.src = url
                img.draggable = false
                img.alt = attr(kid(nv, 'cNvPr'), 'descr') ?? ''
                const src = kid(blipFill, 'srcRect')
                if (src) {
                    const l = num(src, 'l') / 1000, t = num(src, 't') / 1000, r = num(src, 'r') / 1000, b = num(src, 'b') / 1000
                    const W = 100 - l - r, H = 100 - t - b
                    Object.assign(img.style, {
                        position: 'absolute', width: 100 / W * 100 + '%', height: 100 / H * 100 + '%',
                        left: -l / W * 100 + '%', top: -t / H * 100 + '%', maxWidth: 'none',
                    })
                    node.style.overflow = 'hidden'
                } else img.className = 'pp-img'
                const geom = attr(kid(spPr, 'prstGeom'), 'prst')
                if (geom === 'ellipse') node.style.borderRadius = '50%'
                if (geom === 'roundRect') node.style.borderRadius = Math.min(box.w, box.h) * 0.1667 + 'px'
                node.append(img)
            }
            this.applyLine(node, spPr, el, c, box, part)
            into.append(node)
            return
        }

        if (name === 'graphicFrame') {
            const gd = path(el, 'graphic', 'graphicData')
            const uri = attr(gd, 'uri') ?? ''
            if (uri.endsWith('/table')) {
                node.append(await this.table(kid(gd, 'tbl'), c, part))
                node.style.height = 'auto'
            } else if (uri.includes('diagram')) {
                await this.diagram(gd, c, part, node)
            } else if (uri.includes('chart')) {
                await this.chart(gd, c, part, node)
            } else {
                // OLE 等：使用预览图
                const pic = [...gd.getElementsByTagName('*')].find(e => e.localName === 'pic')
                const url = pic && await this.blip(kid(pic, 'blipFill'), part)
                if (url) {
                    const img = document.createElement('img')
                    img.src = url
                    img.className = 'pp-img'
                    node.append(img)
                } else {
                    this.lossy.add('嵌入对象（OLE）无法显示')
                    node.classList.add('pp-placeholder')
                    node.textContent = '嵌入对象'
                }
            }
            into.append(node)
            return
        }

        // sp / cxnSp：形状 + 文本
        const style = kid(el, 'style')
        let fillCss = await this.fill(spPr, c, part)
        if (fillCss == null) for (const s of inh) { fillCss = await this.fill(kid(s, 'spPr'), c, part); if (fillCss != null) break }
        if (fillCss == null && style) {
            const ref = kid(style, 'fillRef')
            const idx = num(ref, 'idx')
            const st = this.styleRef(c, 'fill', idx)
            if (st) fillCss = await this.fill({ children: [st] }, c, c.master ?? part, this.colorOf(ref, c))
        }
        if (fillCss === 'group') fillCss = group?.fill ?? null

        const prst = kid(spPr, 'prstGeom') ?? inh.map(s => path(s, 'spPr', 'prstGeom')).find(Boolean)
        const cust = kid(spPr, 'custGeom')
        const adj = {}
        for (const gd of kids(kid(prst, 'avLst'), 'gd')) {
            const m = /val\s+(-?\d+)/.exec(attr(gd, 'fmla') ?? '')
            if (m) adj[attr(gd, 'name')] = Number(m[1])
        }
        const geomName = attr(prst, 'prst') ?? (cust ? 'custom' : 'rect')
        let d = cust ? customPath(cust, box.w, box.h) : presetPath(geomName, box.w, box.h, adj)
        if (d === undefined) {
            this.lossy.add('部分特殊形状以矩形近似显示')
            d = null
        }
        const isLine = name === 'cxnSp' || ['line', 'straightConnector1', 'bentConnector2', 'bentConnector3', 'curvedConnector3', 'arc'].includes(geomName)
        const ln = this.lineStyle(spPr, style, inh, c, part)

        if (d != null || isLine) {
            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
            svg.setAttribute('class', 'pp-svg')
            svg.setAttribute('width', Math.max(box.w, 1))
            svg.setAttribute('height', Math.max(box.h, 1))
            svg.setAttribute('overflow', 'visible')
            const pEl = document.createElementNS('http://www.w3.org/2000/svg', 'path')
            pEl.setAttribute('d', d ?? `M0,0L${box.w},${box.h}`)
            const solid = fillCss && fillCss !== 'none' && !/gradient|url\(/.test(fillCss)
            if (!isLine && fillCss && fillCss !== 'none' && !solid) {
                // 渐变 / 图片填充：用裁剪路径 + 背景元素实现
                const bg = document.createElement('div')
                bg.className = 'pp-fill'
                bg.style.background = fillCss
                bg.style.clipPath = `path("${d}")`
                node.append(bg)
                pEl.setAttribute('fill', 'none')
            } else pEl.setAttribute('fill', !isLine && solid ? fillCss : 'none')
            pEl.setAttribute('fill-rule', 'evenodd')
            if (ln) {
                pEl.setAttribute('stroke', ln.color)
                pEl.setAttribute('stroke-width', ln.width)
                if (ln.dash) pEl.setAttribute('stroke-dasharray', ln.dash)
                if (ln.tail || ln.head) {
                    const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs')
                    const mk = (id, rev) => {
                        const mm = document.createElementNS('http://www.w3.org/2000/svg', 'marker')
                        mm.id = id
                        for (const [k, v] of Object.entries({ viewBox: '0 0 10 10', refX: 8, refY: 5, markerWidth: 5, markerHeight: 5, orient: rev ? 'auto-start-reverse' : 'auto' })) mm.setAttribute(k, v)
                        const ap = document.createElementNS('http://www.w3.org/2000/svg', 'path')
                        ap.setAttribute('d', 'M0,0L10,5L0,10Z')
                        ap.setAttribute('fill', ln.color)
                        mm.append(ap)
                        defs.append(mm)
                    }
                    const uid = 'm' + Math.random().toString(36).slice(2)
                    if (ln.tail) { mk(uid + 't', false); pEl.setAttribute('marker-end', `url(#${uid}t)`) }
                    if (ln.head) { mk(uid + 'h', true); pEl.setAttribute('marker-start', `url(#${uid}h)`) }
                    svg.append(defs)
                }
            } else if (isLine) {
                pEl.setAttribute('stroke', '#000')
                pEl.setAttribute('stroke-width', 1)
            }
            svg.append(pEl)
            node.append(svg)
        } else {
            if (fillCss && fillCss !== 'none') node.style.background = fillCss
            if (ln) node.style.border = `${ln.width}px ${ln.dash ? 'dashed' : 'solid'} ${ln.color}`
        }
        this.applyEffects(node, spPr, c)

        const txBody = kid(el, 'txBody')
        if (txBody) {
            const tb = await this.textBody(txBody, inh.map(s => kid(s, 'txBody')), c, part, ph, style, box)
            if (tb) node.append(tb)
        }
        into.append(node)
    }

    lineStyle(spPr, style, inh, c, part) {
        let ln = kid(spPr, 'ln')
        for (const s of inh) if (!ln) ln = path(s, 'spPr', 'ln')
        let refColor = null, refLn = null
        const lnRef = kid(style, 'lnRef')
        if (lnRef) {
            refColor = this.colorOf(lnRef, c)
            refLn = this.styleRef(c, 'ln', num(lnRef, 'idx'))
        }
        if (kid(ln, 'noFill')) return null
        const src = ln ?? refLn
        if (!src && !refColor) return null
        const fillEl = kid(ln, 'solidFill') ?? kid(ln, 'gradFill')
        let color = fillEl ? this.colorOf(fillEl.localName === 'gradFill' ? kid(kid(fillEl, 'gsLst'), 'gs') : fillEl, c)?.css : null
        if (!color && refLn) {
            if (kid(refLn, 'noFill')) return null
            color = this.colorOf(kid(refLn, 'solidFill'), c, refColor)?.css
        }
        color ??= refColor?.css
        if (!color) return null
        const w = attr(ln, 'w') ?? attr(refLn, 'w')
        const width = Math.max(0.75, px(Number(w ?? 12700)))
        const dashV = attr(kid(ln, 'prstDash'), 'val')
        const dash = dashV && dashV !== 'solid' ? (/dot/i.test(dashV) ? `${width},${width * 2}` : `${width * 4},${width * 3}`) : null
        const ht = e => { const t = attr(e, 'type'); return t && t !== 'none' }
        return { color, width, dash, head: ht(kid(ln, 'headEnd')), tail: ht(kid(ln, 'tailEnd')) }
    }

    applyLine(node, spPr, el, c, box, part) {
        const ln = this.lineStyle(spPr, kid(el, 'style'), [], c, part)
        if (ln) node.style.outline = `${ln.width}px solid ${ln.color}`
    }

    applyEffects(node, spPr, c) {
        const sh = path(spPr, 'effectLst', 'outerShdw')
        if (!sh) return
        const col = this.colorOf(sh, c)?.css ?? 'rgba(0,0,0,.35)'
        const dist = px(num(sh, 'dist')), dir = num(sh, 'dir') / 60000 * Math.PI / 180
        const blur = px(num(sh, 'blurRad'))
        node.style.filter = `drop-shadow(${(Math.cos(dir) * dist).toFixed(1)}px ${(Math.sin(dir) * dist).toFixed(1)}px ${blur.toFixed(1)}px ${col})`
    }

    // ---------- 文本 ----------
    // 各层级段落属性来源：形状 lstStyle → 继承占位符 lstStyle → 母版 txStyles → presentation defaultTextStyle
    levelStyles(txBody, inhBodies, c, ph, lvl) {
        const lk = `lvl${lvl + 1}pPr`
        const list = []
        const add = s => { if (s) list.push(s) }
        add(path(txBody, 'lstStyle', lk))
        for (const b of inhBodies) add(path(b, 'lstStyle', lk))
        // 分界：此前为形状 / 占位符自身样式，此后为母版与全局默认样式（优先级低于形状的 fontRef）
        list.localCount = list.length
        const master = c.master?.doc.documentElement
        const tx = path(master, 'txStyles')
        const type = attr(ph, 'type')
        if (ph) {
            const key = ['title', 'ctrTitle'].includes(type) ? 'titleStyle' : ['body', 'subTitle', 'obj', null].includes(type) ? 'bodyStyle' : 'otherStyle'
            add(path(tx, key, lk))
        } else add(path(tx, 'otherStyle', lk))
        add(kid(this.defaultText, lk))
        return list
    }

    async textBody(txBody, inhBodies, c, part, ph, style, box) {
        const bodyPr = kid(txBody, 'bodyPr')
        const inhPr = inhBodies.map(b => kid(b, 'bodyPr')).filter(Boolean)
        const bp = n => attr(bodyPr, n) ?? inhPr.map(p => attr(p, n)).find(v => v != null)
        const el = document.createElement('div')
        el.className = 'pp-text'
        const ins = (n, d) => px(Number(bp(n) ?? d))
        el.style.padding = `${ins('tIns', 45720)}px ${ins('rIns', 91440)}px ${ins('bIns', 45720)}px ${ins('lIns', 91440)}px`
        const anchor = bp('anchor') ?? (['title', 'ctrTitle'].includes(attr(ph, 'type')) ? 'ctr' : 't')
        el.style.justifyContent = { t: 'flex-start', ctr: 'center', b: 'flex-end' }[anchor] ?? 'flex-start'
        if (bp('wrap') === 'none') el.style.whiteSpace = 'nowrap'
        const vert = bp('vert')
        if (vert && vert !== 'horz') el.style.writingMode = vert === 'vert270' ? 'sideways-lr' : 'vertical-rl'
        const bodyRot = Number(bp('rot') ?? 0) / 60000
        if (bodyRot) el.style.transform = `rotate(${bodyRot}deg)`
        const auto = [bodyPr, ...inhPr].map(p => kid(p, 'normAutofit')).find(Boolean)
        const fontScale = auto ? num(auto, 'fontScale', 100000) / 100000 : 1
        const lnReduce = auto ? num(auto, 'lnSpcReduction', 0) / 100000 : 0
        const cols = Number(bp('numCol') ?? 1)
        if (cols > 1) { el.style.columnCount = cols; el.style.display = 'block' }

        const fontRefColor = this.colorOf(kid(style, 'fontRef'), c)
        const counters = {}
        let hasText = false
        for (const p of kids(txBody, 'p')) {
            const pPr = kid(p, 'pPr')
            const lvl = num(pPr, 'lvl', 0)
            const levels = this.levelStyles(txBody, inhBodies, c, ph, lvl)
            const chain = [pPr, ...levels].filter(Boolean)
            // 形状自身（含段落与 lstStyle）的默认字符属性，优先级高于 fontRef；母版样式低于 fontRef
            const localDef = [pPr, ...levels.slice(0, levels.localCount)].filter(Boolean).map(x => kid(x, 'defRPr')).filter(Boolean)
            const pa = n => chain.map(x => attr(x, n)).find(v => v != null)
            const pk = n => chain.map(x => kid(x, n)).find(Boolean)
            const para = document.createElement('p')
            para.className = 'pp-p'
            const algn = pa('algn')
            para.style.textAlign = { l: 'left', ctr: 'center', r: 'right', just: 'justify', dist: 'justify' }[algn] ?? 'left'
            const marL = px(Number(pa('marL') ?? 0)), indent = px(Number(pa('indent') ?? 0))
            para.style.paddingLeft = marL + 'px'
            para.style.textIndent = indent + 'px'
            const spc = (n, isLine) => {
                const s = pk(n)
                if (!s) return null
                const pct = kid(s, 'spcPct'), pts = kid(s, 'spcPts')
                if (pct) return isLine ? num(pct, 'val') / 100000 : { pct: num(pct, 'val') / 100000 }
                if (pts) return { pt: num(pts, 'val') / 100 }
                return null
            }
            const lnSpc = spc('lnSpc', true)
            // 默认段落属性中的字号
            const defRPr = chain.map(x => kid(x, 'defRPr')).filter(Boolean)
            const baseSz = Number(defRPr.map(x => attr(x, 'sz')).find(v => v != null) ?? 1800) / 100 * fontScale
            if (typeof lnSpc === 'number') para.style.lineHeight = Math.max(0.6, lnSpc * (1 - lnReduce)) * 1.2
            else if (lnSpc?.pt) para.style.lineHeight = lnSpc.pt * 96 / 72 + 'px'
            const sb = spc('spcBef'), sa = spc('spcAft')
            const spcPx = s => s?.pt != null ? s.pt * 96 / 72 : s?.pct != null ? s.pct * baseSz * 96 / 72 : 0
            para.style.marginTop = spcPx(sb) + 'px'
            para.style.marginBottom = spcPx(sa) + 'px'

            // 项目符号
            const runs = [...p.children].filter(r => ['r', 'fld', 'br'].includes(r.localName))
            const textLen = runs.reduce((n, r) => n + (path(r, 't')?.textContent.length ?? 0), 0)
            if (!pk('buNone') && textLen) {
                const buChar = pk('buChar'), buAuto = pk('buAutoNum')
                let bullet = null
                if (buChar) bullet = attr(buChar, 'char')
                else if (buAuto) {
                    const t = attr(buAuto, 'type') ?? 'arabicPeriod'
                    const key = lvl + ':' + t
                    counters[key] = (counters[key] ?? num(buAuto, 'startAt', 1) - 1) + 1
                    bullet = autoNum(t, counters[key])
                }
                if (bullet) {
                    const b = document.createElement('span')
                    b.className = 'pp-bullet'
                    b.textContent = mapBullet(bullet, attr(pk('buFont'), 'typeface'))
                    const bc = pk('buClr')
                    const col = bc && this.colorOf(bc, c)
                    if (col) b.style.color = col.css
                    const bsz = pk('buSzPct')
                    const firstSz = Number(attr(kid(runs.find(r => r.localName === 'r'), 'rPr'), 'sz') ?? baseSz * 100 / fontScale) / 100 * fontScale
                    b.style.fontSize = firstSz * 96 / 72 * (bsz ? num(bsz, 'val') / 100000 : 1) + 'px'
                    b.style.minWidth = Math.max(0, -indent) + 'px'
                    para.append(b)
                }
            }
            if (Object.keys(counters).length && !pk('buAutoNum')) for (const k of Object.keys(counters)) if (k.startsWith(lvl + ':')) delete counters[k]

            for (const r of runs) {
                if (r.localName === 'br') { para.append(document.createElement('br')); continue }
                const t = path(r, 't')?.textContent ?? ''
                if (!t) continue
                hasText = true
                const rPr = kid(r, 'rPr')
                const rc = [rPr, ...defRPr].filter(Boolean)
                const ra = n => rc.map(x => attr(x, n)).find(v => v != null)
                const rk = n => rc.map(x => kid(x, n)).find(Boolean)
                const span = document.createElement('span')
                span.textContent = t
                const sz = Number(ra('sz') ?? 1800) / 100 * fontScale
                span.style.fontSize = sz * 96 / 72 + 'px'
                if (ra('b') === '1') span.style.fontWeight = '700'
                if (ra('i') === '1') span.style.fontStyle = 'italic'
                const u = ra('u')
                const strike = ra('strike')
                const deco = []
                if (u && u !== 'none') deco.push('underline')
                if (strike && strike !== 'noStrike') deco.push('line-through')
                if (deco.length) span.style.textDecoration = deco.join(' ')
                const baseline = Number(ra('baseline') ?? 0)
                if (baseline) { span.style.verticalAlign = baseline > 0 ? 'super' : 'sub'; span.style.fontSize = sz * 0.65 * 96 / 72 + 'px' }
                const cap = ra('cap')
                if (cap === 'all') span.style.textTransform = 'uppercase'
                if (cap === 'small') span.style.fontVariant = 'small-caps'
                const spcAttr = ra('spc')
                if (spcAttr) span.style.letterSpacing = Number(spcAttr) / 100 * 96 / 72 + 'px'
                const colorFrom = list => {
                    for (const x of list) {
                        const f = kid(x, 'solidFill') ?? kid(x, 'gradFill')
                        if (f) return this.colorOf(f.localName === 'gradFill' ? kid(kid(f, 'gsLst'), 'gs') : f, c)
                    }
                    return null
                }
                let col = colorFrom([rPr, ...localDef].filter(Boolean))
                col ??= fontRefColor
                col ??= colorFrom(defRPr)
                col ??= this.scheme('tx1', c)
                if (col) span.style.color = col.css
                const hl = rk('highlight')
                const hc = hl && this.colorOf(hl, c)
                if (hc) span.style.background = hc.css
                span.style.fontFamily = this.fontFamily(rk('latin'), rk('ea'), c, ph)
                const link = kid(rPr, 'hlinkClick')
                const lr = link && part.rels[rid(link)]
                if (lr?.external) {
                    const a = document.createElement('a')
                    a.href = lr.target
                    a.className = 'pp-link'
                    a.append(span)
                    para.append(a)
                } else para.append(span)
            }
            if (!runs.length || !textLen) {
                // 空段落保留行高
                const endSz = Number(attr(kid(p, 'endParaRPr'), 'sz') ?? defRPr.map(x => attr(x, 'sz')).find(v => v != null) ?? 1800) / 100 * fontScale
                para.style.fontSize = endSz * 96 / 72 + 'px'
                para.append(document.createElement('br'))
            }
            el.append(para)
        }
        return hasText || kids(txBody, 'p').length ? el : null
    }

    fontFamily(latin, ea, c, ph) {
        const isTitle = ['title', 'ctrTitle'].includes(attr(ph, 'type'))
        const resolve = f => {
            const t = attr(f, 'typeface')
            if (!t) return null
            if (t.startsWith('+mj')) return (t.endsWith('ea') ? c.fonts.major.ea : c.fonts.major.latin) || null
            if (t.startsWith('+mn')) return (t.endsWith('ea') ? c.fonts.minor.ea : c.fonts.minor.latin) || null
            return t
        }
        const theme = isTitle ? c.fonts.major : c.fonts.minor
        const list = [resolve(latin) ?? theme.latin, resolve(ea) ?? theme.ea].filter(Boolean)
        return [...list.map(f => `"${f}"`), '"Microsoft YaHei"', 'sans-serif'].join(', ')
    }

    // ---------- 表格 ----------
    async table(tbl, c, part) {
        const table = document.createElement('table')
        table.className = 'pp-table'
        const grid = kids(kid(tbl, 'tblGrid'), 'gridCol').map(g => px(num(g, 'w')))
        const colgroup = document.createElement('colgroup')
        for (const w of grid) {
            const col = document.createElement('col')
            col.style.width = w + 'px'
            colgroup.append(col)
        }
        table.append(colgroup)
        const tblPr = kid(tbl, 'tblPr')
        const firstRow = attr(tblPr, 'firstRow') === '1', bandRow = attr(tblPr, 'bandRow') === '1'
        const accent = this.scheme('accent1', c)
        const rows = kids(tbl, 'tr')
        for (const [ri, tr] of rows.entries()) {
            const row = document.createElement('tr')
            row.style.height = px(num(tr, 'h')) + 'px'
            for (const tc of kids(tr, 'tc')) {
                if (attr(tc, 'hMerge') === '1' || attr(tc, 'vMerge') === '1') continue
                const td = document.createElement('td')
                const gs = num(tc, 'gridSpan', 1), rs = num(tc, 'rowSpan', 1)
                if (gs > 1) td.colSpan = gs
                if (rs > 1) td.rowSpan = rs
                const tcPr = kid(tc, 'tcPr')
                let bg = await this.fill(tcPr, c, part)
                // 未指定时使用常见的默认表格样式近似
                if (bg == null && accent) {
                    if (firstRow && ri === 0) bg = accent.css
                    else if (bandRow) bg = ri % 2 ? `color-mix(in srgb, ${accent.css} 12%, #fff)` : `color-mix(in srgb, ${accent.css} 24%, #fff)`
                }
                if (bg && bg !== 'none') td.style.background = bg
                for (const [side, n] of [['Left', 'lnL'], ['Right', 'lnR'], ['Top', 'lnT'], ['Bottom', 'lnB']]) {
                    const l = kid(tcPr, n)
                    if (!l) continue
                    if (kid(l, 'noFill')) { td.style['border' + side] = 'none'; continue }
                    const col = this.colorOf(kid(l, 'solidFill'), c)
                    if (col) td.style['border' + side] = `${Math.max(1, px(num(l, 'w', 12700)))}px solid ${col.css}`
                }
                const anchor = attr(tcPr, 'anchor')
                td.style.verticalAlign = { ctr: 'middle', b: 'bottom' }[anchor] ?? 'top'
                const body = kid(tc, 'txBody')
                if (body) {
                    const t = await this.textBody(body, [], c, part, null, null, {})
                    if (t) {
                        t.style.position = 'static'
                        t.style.padding = `${px(num(tcPr, 'marT', 45720))}px ${px(num(tcPr, 'marR', 91440))}px ${px(num(tcPr, 'marB', 45720))}px ${px(num(tcPr, 'marL', 91440))}px`
                        if (firstRow && ri === 0 && !kid(tcPr, 'solidFill')) t.querySelectorAll('span:not(.pp-bullet)').forEach(s => { if (!s.style.color || s.style.color === 'rgb(0, 0, 0)') s.style.color = '#fff'; s.style.fontWeight = '700' })
                        td.append(t)
                    }
                }
                row.append(td)
            }
            table.append(row)
        }
        return table
    }

    // SmartArt：使用已生成的绘图（drawing*.xml）
    async diagram(gd, c, part, node) {
        const relIds = kid(gd, 'relIds')
        const all = Object.values(part.rels)
        const dm = relIds && part.rels[relIds.getAttributeNS(NS.r, 'dm') ?? attr(relIds, 'r:dm')]
        const drawing = all.find(r => r.type === 'diagramDrawing' && (!dm || r.target.replace(/.*drawing/, '') === dm.target.replace(/.*data/, ''))) ?? all.find(r => r.type === 'diagramDrawing')
        if (!drawing) {
            this.lossy.add('SmartArt 图形无法完整显示')
            node.classList.add('pp-placeholder')
            node.textContent = 'SmartArt'
            return
        }
        const doc = await this.xml(drawing.target)
        const rels = await this.rels(drawing.target)
        const dPart = { doc, path: drawing.target, rels }
        const tree = [...doc.getElementsByTagName('*')].find(e => e.localName === 'spTree')
        const offX = parseFloat(node.style.left), offY = parseFloat(node.style.top)
        const map = b => ({ x: b.x - offX, y: b.y - offY, w: b.w, h: b.h })
        for (const ch of tree?.children ?? []) await this.renderNode(ch, dPart, { c }, node, false, { map })
    }

    // 图表：简化为数据表（标记为有损）
    async chart(gd, c, part, node) {
        this.lossy.add('图表以数据表形式简化显示')
        const chartEl = [...gd.children].find(e => e.localName === 'chart')
        const rel = chartEl && part.rels[rid(chartEl)]
        node.classList.add('pp-chart')
        if (!rel) { node.textContent = '图表'; return }
        const doc = await this.xml(rel.target).catch(() => null)
        if (!doc) { node.textContent = '图表'; return }
        const all = [...doc.getElementsByTagName('*')]
        const title = all.find(e => e.localName === 'title')
        const titleText = title ? [...title.getElementsByTagName('*')].filter(e => e.localName === 't').map(e => e.textContent).join('') : ''
        const series = all.filter(e => e.localName === 'ser').map(ser => {
            const nm = [...(kid(ser, 'tx')?.getElementsByTagName('*') ?? [])].find(e => e.localName === 'v')?.textContent ?? ''
            const pts = el => [...(el?.getElementsByTagName('*') ?? [])].filter(e => e.localName === 'pt').map(p => [num(p, 'idx'), path(p, 'v')?.textContent ?? ''])
            return { name: nm, cats: pts(kid(ser, 'cat')), vals: pts(kid(ser, 'val')) }
        })
        const box = document.createElement('div')
        box.className = 'pp-chart-box'
        const cap = document.createElement('div')
        cap.className = 'pp-chart-title'
        cap.textContent = titleText
        if (titleText) box.append(cap)
        if (series.length) box.append(barChart(series))
        if (series.some(x => x.name)) {
            const colors = ['#4472c4', '#ed7d31', '#a5a5a5', '#ffc000', '#5b9bd5', '#70ad47']
            const legend = document.createElement('div')
            legend.className = 'pp-chart-legend'
            series.forEach((x, i) => {
                const it = document.createElement('span')
                it.innerHTML = `<i style="background:${colors[i % colors.length]}"></i>`
                it.append(x.name)
                legend.append(it)
            })
            box.append(legend)
        }
        node.append(box)
    }

    async notes(i) {
        const c = await this.chain(this.slidePaths[i])
        if (!c.notesPath) return ''
        const doc = await this.xml(c.notesPath).catch(() => null)
        if (!doc) return ''
        const out = []
        for (const sp of doc.getElementsByTagNameNS(NS.p, 'sp')) {
            const type = attr([...sp.getElementsByTagNameNS(NS.p, 'ph')][0], 'type')
            if (type && type !== 'body') continue
            for (const p of sp.getElementsByTagNameNS(NS.a, 'p')) {
                out.push([...p.getElementsByTagNameNS(NS.a, 't')].map(t => t.textContent).join(''))
            }
        }
        return out.join('\n').trim()
    }

    // 幻灯片纯文本（用于搜索与标题）
    async slideText(i) {
        const doc = await this.xml(this.slidePaths[i])
        const title = []
        const all = []
        for (const sp of doc.getElementsByTagNameNS(NS.p, 'sp')) {
            const type = attr([...sp.getElementsByTagNameNS(NS.p, 'ph')][0], 'type')
            const paras = [...sp.getElementsByTagNameNS(NS.a, 'p')].map(p => [...p.getElementsByTagNameNS(NS.a, 't')].map(t => t.textContent).join(''))
            if (['title', 'ctrTitle'].includes(type)) title.push(...paras)
            all.push(...paras)
        }
        for (const t of doc.getElementsByTagNameNS(NS.a, 'tbl')) all.push(...[...t.getElementsByTagNameNS(NS.a, 't')].map(x => x.textContent))
        return { title: title.join(' ').trim(), text: all.filter(Boolean).join('\n') }
    }

    dispose() {
        for (const u of this.urls) URL.revokeObjectURL(u)
        this.urls = []
    }
}

function autoNum(type, n) {
    const roman = x => {
        const t = [[1000, 'm'], [900, 'cm'], [500, 'd'], [400, 'cd'], [100, 'c'], [90, 'xc'], [50, 'l'], [40, 'xl'], [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i']]
        let s = ''
        for (const [v, r] of t) while (x >= v) { s += r; x -= v }
        return s
    }
    const alpha = x => { let s = ''; while (x > 0) { x--; s = String.fromCharCode(97 + x % 26) + s; x = Math.floor(x / 26) } return s }
    const cn = x => '〇一二三四五六七八九十'[x] ?? String(x)
    let core
    if (type.startsWith('arabic')) core = String(n)
    else if (type.startsWith('alphaLc')) core = alpha(n)
    else if (type.startsWith('alphaUc')) core = alpha(n).toUpperCase()
    else if (type.startsWith('romanLc')) core = roman(n)
    else if (type.startsWith('romanUc')) core = roman(n).toUpperCase()
    else if (type.startsWith('circleNum')) core = String.fromCharCode(0x245f + Math.min(n, 20))
    else if (type.startsWith('ea1Chs') || type.startsWith('ea1Cht')) core = cn(n)
    else core = String(n)
    if (type.endsWith('ParenBoth')) return `(${core})`
    if (type.endsWith('ParenR')) return `${core})`
    if (type.endsWith('Period')) return `${core}.`
    if (type.endsWith('Plain') || type.startsWith('circleNum')) return core
    return `${core}.`
}

// Wingdings / Symbol 常见项目符号映射
function mapBullet(ch, font) {
    if (!font) return ch
    const f = font.toLowerCase()
    if (f.includes('wingdings')) return { 'l': '●', 'n': '■', 'q': '❑', 'u': '◆', 'v': '❖', 'Ø': '➢', 'ü': '✔', '§': '■', 'Ÿ': '•', 'è': '➔', 'à': '➢', 'o': '○', 'p': '□' }[ch] ?? '•'
    if (f.includes('symbol')) return { '·': '•', 'Þ': '⇒' }[ch] ?? (ch.charCodeAt(0) > 0xf000 ? '•' : ch)
    return ch
}

// 简易柱状图（SVG）
function barChart(series) {
    const cats = series[0].cats.length ? series[0].cats.map(c => c[1]) : series[0].vals.map((_, i) => String(i + 1))
    const W = 100, H = 60
    const vals = series.flatMap(s => s.vals.map(v => Number(v[1]) || 0))
    const max = Math.max(...vals, 0) || 1, min = Math.min(...vals, 0)
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('viewBox', `0 0 ${W} ${H + 12}`)
    svg.setAttribute('preserveAspectRatio', 'none')
    svg.setAttribute('class', 'pp-chart-svg')
    const colors = ['#4472c4', '#ed7d31', '#a5a5a5', '#ffc000', '#5b9bd5', '#70ad47']
    const groupW = W / Math.max(cats.length, 1)
    const barW = groupW * 0.8 / series.length
    const zeroY = H * max / (max - min)
    series.forEach((s, si) => s.vals.forEach(([idx, v]) => {
        const val = Number(v) || 0
        const r = document.createElementNS('http://www.w3.org/2000/svg', 'rect')
        const hgt = Math.abs(val) / (max - min) * H
        r.setAttribute('x', idx * groupW + groupW * 0.1 + si * barW)
        r.setAttribute('y', val >= 0 ? zeroY - hgt : zeroY)
        r.setAttribute('width', barW * 0.92)
        r.setAttribute('height', hgt)
        r.setAttribute('fill', colors[si % colors.length])
        const t = document.createElementNS('http://www.w3.org/2000/svg', 'title')
        t.textContent = `${s.name ? s.name + ' · ' : ''}${cats[idx] ?? ''}: ${v}`
        r.append(t)
        svg.append(r)
    }))
    cats.forEach((cName, i) => {
        const t = document.createElementNS('http://www.w3.org/2000/svg', 'text')
        t.setAttribute('x', i * groupW + groupW / 2)
        t.setAttribute('y', H + 8)
        t.setAttribute('font-size', 3.2)
        t.setAttribute('text-anchor', 'middle')
        t.setAttribute('fill', 'currentColor')
        t.textContent = String(cName).slice(0, 14)
        svg.append(t)
    })
    return svg
}
