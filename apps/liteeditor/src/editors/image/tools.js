// 图像编辑工具：每个工具处理 down / move / up（坐标为文档像素），以及光标与选项
import { makeCanvas, ctx2d, cloneCanvas, selectionFromPath, combineSelection } from './doc.js'
import { hex } from './filters.js'

export const TOOLS = [
    { id: 'move', label: '移动', icon: 'move', key: 'V' },
    { id: 'marquee', label: '矩形选框', icon: 'square-dashed', key: 'M' },
    { id: 'ellipse', label: '椭圆选框', icon: 'circle-dashed', key: 'M', shift: true },
    { id: 'lasso', label: '套索', icon: 'lasso', key: 'L' },
    { id: 'polyLasso', label: '多边形套索', icon: 'lasso-select', key: 'L', shift: true },
    { id: 'wand', label: '魔棒', icon: 'wand-sparkles', key: 'W' },
    { id: 'crop', label: '裁剪', icon: 'crop', key: 'C' },
    '-',
    { id: 'brush', label: '画笔', icon: 'brush', key: 'B' },
    { id: 'pencil', label: '铅笔', icon: 'pencil', key: 'B', shift: true },
    { id: 'eraser', label: '橡皮擦', icon: 'eraser', key: 'E' },
    { id: 'clone', label: '仿制图章', icon: 'stamp', key: 'S' },
    { id: 'blurTool', label: '模糊 / 锐化', icon: 'droplet', key: 'R' },
    { id: 'dodge', label: '减淡 / 加深', icon: 'sun-medium', key: 'O' },
    { id: 'smudge', label: '涂抹', icon: 'pointer', key: 'R', shift: true },
    '-',
    { id: 'bucket', label: '油漆桶', icon: 'paint-bucket', key: 'G' },
    { id: 'gradient', label: '渐变', icon: 'blend', key: 'G', shift: true },
    { id: 'text', label: '文字', icon: 'type', key: 'T' },
    { id: 'shape', label: '形状', icon: 'shapes', key: 'U' },
    '-',
    { id: 'picker', label: '吸管', icon: 'pipette', key: 'I' },
    { id: 'hand', label: '抓手', icon: 'hand', key: 'H' },
    { id: 'zoom', label: '缩放', icon: 'zoom-in', key: 'Z' },
]

export const DEFAULT_OPTS = {
    size: 24, hardness: 80, opacity: 100, flow: 100, spacing: 12,
    tolerance: 32, contiguous: true, allLayers: false, antialias: true, feather: 0,
    selMode: 'new', gradType: 'linear', gradReverse: false,
    shape: 'rect', shapeFill: true, shapeStroke: false, strokeWidth: 4, radius: 0,
    font: '"Microsoft YaHei", sans-serif', fontSize: 64, bold: false, italic: false,
    blurMode: 'blur', strength: 50, dodgeMode: 'dodge', exposure: 30,
}

// ---------- 画笔笔尖 ----------
const tipCache = new Map()
function brushTip(size, hardness, color) {
    const key = `${size}|${hardness}|${color}`
    let c = tipCache.get(key)
    if (c) return c
    const d = Math.max(1, Math.ceil(size))
    c = makeCanvas(d, d)
    const g = ctx2d(c)
    const r = d / 2
    const grad = g.createRadialGradient(r, r, 0, r, r, r)
    const [R, G, B] = hex(color)
    const h = Math.max(0.01, Math.min(0.99, hardness / 100))
    grad.addColorStop(0, `rgba(${R},${G},${B},1)`)
    grad.addColorStop(h, `rgba(${R},${G},${B},1)`)
    grad.addColorStop(1, `rgba(${R},${G},${B},0)`)
    g.fillStyle = grad
    g.beginPath(); g.arc(r, r, r, 0, Math.PI * 2); g.fill()
    if (tipCache.size > 64) tipCache.clear()
    tipCache.set(key, c)
    return c
}

// 沿路径按间距盖印
function stampLine(from, to, spacing, fn) {
    const dx = to.x - from.x, dy = to.y - from.y
    const dist = Math.hypot(dx, dy)
    const step = Math.max(0.5, spacing)
    let t = from.rest ?? 0
    while (t <= dist) {
        fn(from.x + dx * (t / dist || 0), from.y + dy * (t / dist || 0))
        t += step
    }
    to.rest = t - dist
}

// ---------- 描边会话：在临时图层上绘制，结束时合成到目标图层（支持不透明度与选区裁剪） ----------
export class Stroke {
    constructor(ed, layer, { erase = false, pencil = false } = {}) {
        this.ed = ed
        this.layer = layer
        this.erase = erase
        this.pencil = pencil
        const o = ed.opts
        this.opacity = o.opacity / 100
        this.flow = o.flow / 100
        this.size = o.size
        this.color = ed.fg
        this.buf = makeCanvas(layer.canvas.width, layer.canvas.height)
        this.g = ctx2d(this.buf)
        this.tip = pencil ? null : brushTip(this.size, o.hardness, erase ? '#000000' : this.color)
        this.last = null
    }
    dab(x, y) {
        const lx = x - this.layer.x, ly = y - this.layer.y
        const g = this.g
        g.globalAlpha = this.flow
        if (this.pencil) {
            const s = Math.max(1, Math.round(this.size))
            g.fillStyle = this.erase ? '#000' : this.color
            g.fillRect(Math.round(lx - s / 2), Math.round(ly - s / 2), s, s)
        } else {
            const s = this.tip.width
            g.drawImage(this.tip, lx - s / 2, ly - s / 2)
        }
    }
    to(p) {
        if (!this.last) { this.dab(p.x, p.y); this.last = { ...p }; return }
        stampLine(this.last, p, Math.max(1, this.size * this.ed.opts.spacing / 100), (x, y) => this.dab(x, y))
        this.last = { ...p, rest: p.rest }
    }
    // 预览：返回图层画布与缓冲合成后的结果
    preview() {
        const out = cloneCanvas(this.layer.canvas)
        this.apply(out)
        return out
    }
    apply(target) {
        const g = ctx2d(target)
        let buf = this.buf
        const sel = this.ed.doc.selection
        if (sel) {
            buf = cloneCanvas(this.buf)
            const bg = ctx2d(buf)
            bg.globalCompositeOperation = 'destination-in'
            bg.drawImage(sel, -this.layer.x, -this.layer.y)
        }
        g.save()
        g.globalAlpha = this.opacity
        g.globalCompositeOperation = this.erase ? 'destination-out' : 'source-over'
        g.drawImage(buf, 0, 0)
        g.restore()
    }
    commit() {
        const c = this.ed.doc.writable(this.layer)
        this.apply(c)
    }
}

// ---------- 魔棒 / 油漆桶：颜色区域 ----------
// 返回蒙版 canvas（文档大小）
export function colorRegion(srcCanvas, ox, oy, docW, docH, x, y, tolerance, contiguous) {
    const w = srcCanvas.width, h = srcCanvas.height
    const lx = Math.floor(x - ox), ly = Math.floor(y - oy)
    const mask = makeCanvas(docW, docH)
    if (lx < 0 || ly < 0 || lx >= w || ly >= h) return mask
    const d = ctx2d(srcCanvas).getImageData(0, 0, w, h).data
    const i0 = (ly * w + lx) * 4
    const r0 = d[i0], g0 = d[i0 + 1], b0 = d[i0 + 2], a0 = d[i0 + 3]
    const tol = tolerance * 2.55 * 1.8
    const match = i => {
        const da = Math.abs(d[i + 3] - a0)
        if (a0 === 0 && d[i + 3] === 0) return true
        return Math.abs(d[i] - r0) + Math.abs(d[i + 1] - g0) + Math.abs(d[i + 2] - b0) + da <= tol
    }
    const out = new Uint8ClampedArray(w * h)
    if (contiguous) {
        const stack = [lx + ly * w]
        out[lx + ly * w] = 1
        while (stack.length) {
            const p = stack.pop()
            const px = p % w, py = (p - px) / w
            const nb = [px > 0 ? p - 1 : -1, px < w - 1 ? p + 1 : -1, py > 0 ? p - w : -1, py < h - 1 ? p + w : -1]
            for (const q of nb) if (q >= 0 && !out[q] && match(q * 4)) { out[q] = 1; stack.push(q) }
        }
    } else for (let p = 0; p < w * h; p++) if (match(p * 4)) out[p] = 1
    const lm = makeCanvas(w, h)
    const lg = ctx2d(lm)
    const id = lg.createImageData(w, h)
    for (let p = 0; p < w * h; p++) if (out[p]) id.data[p * 4 + 3] = 255
    lg.putImageData(id, 0, 0)
    ctx2d(mask).drawImage(lm, ox, oy)
    return mask
}

// ---------- 渐变 ----------
export function drawGradient(g, type, a, b, c1, c2) {
    let grad
    if (type === 'radial') grad = g.createRadialGradient(a.x, a.y, 0, a.x, a.y, Math.hypot(b.x - a.x, b.y - a.y))
    else if (type === 'conic') grad = g.createConicGradient(Math.atan2(b.y - a.y, b.x - a.x), a.x, a.y)
    else grad = g.createLinearGradient(a.x, a.y, b.x, b.y)
    grad.addColorStop(0, c1)
    grad.addColorStop(1, c2)
    if (type === 'reflected') {
        grad = g.createLinearGradient(a.x - (b.x - a.x), a.y - (b.y - a.y), b.x, b.y)
        grad.addColorStop(0, c2); grad.addColorStop(0.5, c1); grad.addColorStop(1, c2)
    }
    g.fillStyle = grad
    g.fillRect(-1e5, -1e5, 2e5, 2e5)
}

// ---------- 形状 ----------
export function shapePath(g, kind, x, y, w, h, radius = 0) {
    g.beginPath()
    if (kind === 'ellipse') g.ellipse(x + w / 2, y + h / 2, Math.abs(w / 2), Math.abs(h / 2), 0, 0, Math.PI * 2)
    else if (kind === 'line' || kind === 'arrow') { g.moveTo(x, y); g.lineTo(x + w, y + h) }
    else if (kind === 'triangle') { g.moveTo(x + w / 2, y); g.lineTo(x + w, y + h); g.lineTo(x, y + h); g.closePath() }
    else if (kind === 'star') {
        const cx = x + w / 2, cy = y + h / 2
        for (let i = 0; i < 10; i++) {
            const a = -Math.PI / 2 + i * Math.PI / 5, k = i % 2 ? 0.4 : 1
            const px = cx + (w / 2) * k * Math.cos(a), py = cy + (h / 2) * k * Math.sin(a)
            i ? g.lineTo(px, py) : g.moveTo(px, py)
        }
        g.closePath()
    } else if (kind === 'polygon') {
        const cx = x + w / 2, cy = y + h / 2
        for (let i = 0; i < 6; i++) { const a = -Math.PI / 2 + i * Math.PI / 3; const px = cx + w / 2 * Math.cos(a), py = cy + h / 2 * Math.sin(a); i ? g.lineTo(px, py) : g.moveTo(px, py) }
        g.closePath()
    } else if (radius > 0) g.roundRect(Math.min(x, x + w), Math.min(y, y + h), Math.abs(w), Math.abs(h), radius)
    else g.rect(x, y, w, h)
}
export function drawShape(g, o, fg, bg, a, b) {
    let x = a.x, y = a.y, w = b.x - a.x, h = b.y - a.y
    const line = o.shape === 'line' || o.shape === 'arrow'
    shapePath(g, o.shape, x, y, w, h, o.radius)
    g.lineJoin = 'round'
    g.lineCap = 'round'
    if (!line && o.shapeFill) { g.fillStyle = fg; g.fill() }
    if (line || o.shapeStroke) { g.strokeStyle = line ? fg : (o.shapeFill ? bg : fg); g.lineWidth = o.strokeWidth; g.stroke() }
    if (o.shape === 'arrow') {
        const ang = Math.atan2(h, w), L = Math.max(10, o.strokeWidth * 4)
        g.beginPath()
        g.moveTo(b.x, b.y)
        g.lineTo(b.x - L * Math.cos(ang - 0.45), b.y - L * Math.sin(ang - 0.45))
        g.lineTo(b.x - L * Math.cos(ang + 0.45), b.y - L * Math.sin(ang + 0.45))
        g.closePath()
        g.fillStyle = fg
        g.fill()
    }
}

// ---------- 选区形状 ----------
export function rectSelection(doc, a, b, ellipse, mode, feather) {
    const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y), w = Math.abs(b.x - a.x), h = Math.abs(b.y - a.y)
    if (w < 1 || h < 1) return mode === 'new' ? null : doc.selection
    const m = selectionFromPath(doc.w, doc.h, g => {
        if (feather) g.filter = `blur(${feather}px)`
        g.beginPath()
        if (ellipse) g.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2)
        else g.rect(Math.round(x), Math.round(y), Math.round(w), Math.round(h))
        g.fill()
    })
    return combineSelection(doc.selection, m, mode)
}
export function polySelection(doc, pts, mode, feather) {
    if (pts.length < 3) return doc.selection
    const m = selectionFromPath(doc.w, doc.h, g => {
        if (feather) g.filter = `blur(${feather}px)`
        g.beginPath()
        pts.forEach((p, i) => (i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)))
        g.closePath()
        g.fill()
    })
    return combineSelection(doc.selection, m, mode)
}

// ---------- 局部修饰工具（模糊 / 锐化 / 减淡 / 加深 / 涂抹） ----------
export function retouchDab(canvas, lx, ly, size, mode, strength) {
    const r = Math.max(2, size / 2)
    const x0 = Math.max(0, Math.floor(lx - r)), y0 = Math.max(0, Math.floor(ly - r))
    const x1 = Math.min(canvas.width, Math.ceil(lx + r)), y1 = Math.min(canvas.height, Math.ceil(ly + r))
    const w = x1 - x0, h = y1 - y0
    if (w <= 0 || h <= 0) return
    const g = ctx2d(canvas)
    const id = g.getImageData(x0, y0, w, h)
    const d = id.data
    const src = new Uint8ClampedArray(d)
    const k = strength / 100
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const dist = Math.hypot(x0 + x - lx, y0 + y - ly)
        if (dist > r) continue
        const f = (1 - dist / r) * k
        const i = (y * w + x) * 4
        if (mode === 'blur' || mode === 'sharpen') {
            let sr = 0, sg = 0, sb = 0, n = 0
            for (let yy = Math.max(0, y - 1); yy <= Math.min(h - 1, y + 1); yy++) for (let xx = Math.max(0, x - 1); xx <= Math.min(w - 1, x + 1); xx++) {
                const j = (yy * w + xx) * 4
                sr += src[j]; sg += src[j + 1]; sb += src[j + 2]; n++
            }
            const ar = sr / n, ag = sg / n, ab = sb / n
            if (mode === 'blur') { d[i] += (ar - src[i]) * f; d[i + 1] += (ag - src[i + 1]) * f; d[i + 2] += (ab - src[i + 2]) * f }
            else { d[i] += (src[i] - ar) * f * 1.5; d[i + 1] += (src[i + 1] - ag) * f * 1.5; d[i + 2] += (src[i + 2] - ab) * f * 1.5 }
        } else if (mode === 'dodge') { for (let c = 0; c < 3; c++) d[i + c] += (255 - src[i + c]) * f * 0.35 }
        else if (mode === 'burn') { for (let c = 0; c < 3; c++) d[i + c] -= src[i + c] * f * 0.35 }
    }
    g.putImageData(id, x0, y0)
}
// 涂抹：把上一位置的像素拖到当前位置
export function smudgeDab(canvas, from, to, size, strength) {
    const r = Math.max(2, Math.round(size / 2))
    const g = ctx2d(canvas)
    const sx = Math.round(from.x - r), sy = Math.round(from.y - r)
    const patch = makeCanvas(r * 2, r * 2)
    const pg = ctx2d(patch)
    pg.drawImage(canvas, sx, sy, r * 2, r * 2, 0, 0, r * 2, r * 2)
    pg.globalCompositeOperation = 'destination-in'
    const grad = pg.createRadialGradient(r, r, 0, r, r, r)
    grad.addColorStop(0, `rgba(0,0,0,${strength / 100})`)
    grad.addColorStop(1, 'rgba(0,0,0,0)')
    pg.fillStyle = grad
    pg.fillRect(0, 0, r * 2, r * 2)
    g.drawImage(patch, Math.round(to.x - r), Math.round(to.y - r))
}
