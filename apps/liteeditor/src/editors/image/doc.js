// 图像文档模型：图层（写时复制的画布）、选区蒙版、合成
// 每个图层持有一个 canvas；快照保存图层对象的浅拷贝（共享 canvas 引用）。
// 修改图层像素前调用 doc.writable(layer) 获得新 canvas（若该 canvas 已被快照引用），
// 因此撤销历史只为真正被修改的图层保存像素副本。
import { uid } from '../../core/dom.js'

export const BLEND_MODES = [
    ['normal', '正常', 'source-over'], ['multiply', '正片叠底', 'multiply'], ['screen', '滤色', 'screen'], ['overlay', '叠加', 'overlay'],
    ['soft-light', '柔光', 'soft-light'], ['hard-light', '强光', 'hard-light'], ['darken', '变暗', 'darken'], ['lighten', '变亮', 'lighten'],
    ['color-dodge', '颜色减淡', 'color-dodge'], ['color-burn', '颜色加深', 'color-burn'], ['difference', '差值', 'difference'], ['exclusion', '排除', 'exclusion'],
    ['hue', '色相', 'hue'], ['saturation', '饱和度', 'saturation'], ['color', '颜色', 'color'], ['luminosity', '明度', 'luminosity'],
]
export const compositeOp = mode => BLEND_MODES.find(b => b[0] === mode)?.[2] ?? 'source-over'

export function makeCanvas(w, h) {
    const c = document.createElement('canvas')
    c.width = Math.max(1, Math.round(w))
    c.height = Math.max(1, Math.round(h))
    return c
}
export const ctx2d = c => c.getContext('2d', { willReadFrequently: true })
export function cloneCanvas(src) {
    const c = makeCanvas(src.width, src.height)
    ctx2d(c).drawImage(src, 0, 0)
    return c
}

// 图层：{ id, name, canvas, x, y, visible, opacity, blend, locked, mask?: canvas, text?: 文字图层信息, clip }
export function newLayer(w, h, props = {}) {
    return { id: uid('L'), name: '图层', canvas: makeCanvas(w, h), x: 0, y: 0, visible: true, opacity: 1, blend: 'normal', locked: false, ...props }
}

export class ImageDoc {
    constructor(w, h) {
        this.w = w
        this.h = h
        this.layers = []
        this.active = null
        this.selection = null  // 选区蒙版 canvas（alpha 通道即选区强度），null 表示无选区
        this.shared = new WeakSet() // 已被快照引用的 canvas
        this.dpi = 72
    }

    get activeLayer() { return this.layers.find(l => l.id === this.active) ?? this.layers.at(-1) ?? null }
    layerById(id) { return this.layers.find(l => l.id === id) }

    // 获得可写的图层画布（写时复制）
    writable(layer) {
        if (this.shared.has(layer.canvas)) {
            layer.canvas = cloneCanvas(layer.canvas)
        }
        return layer.canvas
    }
    writableMask(layer) {
        if (layer.mask && this.shared.has(layer.mask)) layer.mask = cloneCanvas(layer.mask)
        return layer.mask
    }
    writableSelection() {
        if (this.selection && this.shared.has(this.selection)) this.selection = cloneCanvas(this.selection)
        return this.selection
    }

    snapshot() {
        for (const l of this.layers) { this.shared.add(l.canvas); if (l.mask) this.shared.add(l.mask) }
        if (this.selection) this.shared.add(this.selection)
        return {
            w: this.w, h: this.h, active: this.active, selection: this.selection,
            layers: this.layers.map(l => ({ ...l, text: l.text ? { ...l.text } : undefined })),
        }
    }
    restore(s) {
        this.w = s.w
        this.h = s.h
        this.active = s.active
        this.selection = s.selection
        this.layers = s.layers.map(l => ({ ...l, text: l.text ? { ...l.text } : undefined }))
    }

    // 合成全部可见图层（可选：替换某图层的画布用于实时预览）
    composite(target, { skipId, override, background = null } = {}) {
        const c = target ?? makeCanvas(this.w, this.h)
        const g = ctx2d(c)
        g.save()
        g.setTransform(1, 0, 0, 1, 0, 0)
        g.clearRect(0, 0, c.width, c.height)
        if (background) { g.fillStyle = background; g.fillRect(0, 0, c.width, c.height) }
        for (const l of this.layers) {
            if (!l.visible || l.id === skipId) continue
            const src = override?.id === l.id ? override.canvas : l.canvas
            g.globalAlpha = l.opacity
            g.globalCompositeOperation = compositeOp(l.blend)
            if (l.mask && l.maskEnabled !== false) {
                const tmp = makeCanvas(src.width, src.height)
                const t = ctx2d(tmp)
                t.drawImage(src, 0, 0)
                t.globalCompositeOperation = 'destination-in'
                t.drawImage(l.mask, 0, 0)
                g.drawImage(tmp, l.x, l.y)
            } else g.drawImage(src, l.x, l.y)
        }
        g.restore()
        return c
    }

    // 拼合为单个画布（带白色背景可选）
    flatten(bg) { return this.composite(null, { background: bg }) }
}

// ---------- 选区工具函数 ----------
export function selectionFromPath(w, h, draw) {
    const m = makeCanvas(w, h)
    const g = ctx2d(m)
    g.fillStyle = '#000'
    draw(g)
    return m
}
// 合并选区：mode = 'new' | 'add' | 'sub' | 'intersect'
export function combineSelection(old, next, mode) {
    if (!old || mode === 'new') return next
    const out = cloneCanvas(old)
    const g = ctx2d(out)
    g.globalCompositeOperation = mode === 'add' ? 'source-over' : mode === 'sub' ? 'destination-out' : 'destination-in'
    g.drawImage(next, 0, 0)
    return out
}
export function invertSelection(sel, w, h) {
    const out = makeCanvas(w, h)
    const g = ctx2d(out)
    g.fillStyle = '#000'
    g.fillRect(0, 0, w, h)
    if (sel) { g.globalCompositeOperation = 'destination-out'; g.drawImage(sel, 0, 0) }
    return out
}
// 选区的包围盒（alpha > 0）
export function selectionBounds(sel) {
    if (!sel) return null
    const { width: w, height: h } = sel
    const d = ctx2d(sel).getImageData(0, 0, w, h).data
    let x0 = w, y0 = h, x1 = -1, y1 = -1
    for (let y = 0; y < h; y++) {
        const row = y * w * 4
        for (let x = 0; x < w; x++) if (d[row + x * 4 + 3] > 8) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y }
    }
    return x1 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 }
}
// 羽化：模糊选区蒙版
export function featherSelection(sel, r) {
    if (!sel || r <= 0) return sel
    const out = makeCanvas(sel.width, sel.height)
    const g = ctx2d(out)
    g.filter = `blur(${r}px)`
    g.drawImage(sel, 0, 0)
    return out
}
// 扩展 / 收缩（通过阈值化模糊结果近似形态学运算）
export function growSelection(sel, r) {
    if (!sel || !r) return sel
    const b = featherSelection(sel, Math.abs(r))
    const g = ctx2d(b)
    const id = g.getImageData(0, 0, b.width, b.height)
    const d = id.data
    const t = r > 0 ? 8 : 247
    for (let i = 3; i < d.length; i += 4) d[i] = d[i] > t ? 255 : 0
    g.putImageData(id, 0, 0)
    return b
}

// 用选区裁剪某个画布：返回只保留选区部分的新画布（考虑图层偏移）
export function maskByLayerSelection(canvas, sel, ox, oy) {
    const out = cloneCanvas(canvas)
    if (!sel) return out
    const g = ctx2d(out)
    g.globalCompositeOperation = 'destination-in'
    g.drawImage(sel, -ox, -oy)
    return out
}
