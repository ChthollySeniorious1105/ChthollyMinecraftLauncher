// 合成器：计算某一时刻的可见图层并绘制到 2D 画布（预览与导出共用）
import { clipDur, clipEnd, srcTime, isActive, prevAdjacent, mediaOf } from './model.js'

// 片段自身的淡入淡出包络（0..1）
export function fadeEnv(c, t) {
    let a = 1
    const d = clipDur(c)
    if (c.fadeIn > 0) a = Math.min(a, (t - c.start) / Math.min(c.fadeIn, d))
    if (c.fadeOut > 0) a = Math.min(a, (clipEnd(c) - t) / Math.min(c.fadeOut, d))
    return Math.max(0, Math.min(1, a))
}

const isVisual = c => c.type === 'video' || c.type === 'image' || c.type === 'text' || c.type === 'color'

// 返回自下而上的图层列表：[{ c, st(源时间), a(不透明度) }]
// 轨道数组顺序即时间线上自上而下的显示顺序；上方的视频轨道覆盖下方
export function visualLayers(p, t) {
    const out = []
    const tracks = p.tracks.filter(tr => tr.type === 'video' && !tr.hidden).reverse()
    for (const tr of tracks) {
        const cs = p.clips.filter(c => c.track === tr.id && isVisual(c) && isActive(c, t)).sort((a, b) => a.start - b.start)
        for (const c of cs) {
            let a = (c.opacity ?? 1) * fadeEnv(c, t)
            // 交叉溶解：前一个片段延续播放，本片段逐渐显现
            if (c.dissolve > 0 && t < c.start + c.dissolve) {
                const prev = prevAdjacent(p, c)
                if (prev && isVisual(prev)) {
                    const k = (t - c.start) / c.dissolve
                    out.push({ c: prev, st: clampSrc(p, prev, srcTime(prev, t)), a: (prev.opacity ?? 1) })
                    a *= Math.max(0, Math.min(1, k))
                }
            }
            if (a > 0.001) out.push({ c, st: clampSrc(p, c, srcTime(c, t)), a })
        }
    }
    return out
}
function clampSrc(p, c, st) {
    const d = mediaOf(p, c)?.duration
    return d ? Math.min(Math.max(0, st), d - 0.001) : st
}

// 需要解码帧的图层
export const needsFrame = l => l.c.type === 'video' || l.c.type === 'image'

// 绘制所有图层。getFrame(layer) 返回 { src: CanvasImageSource | VideoSample, w, h } 或 null
// bounds: 可选 Map，记录每个片段在项目坐标中的外框（用于预览中的点击选择）
export function drawLayers(ctx, p, layers, getFrame, bounds) {
    ctx.save()
    ctx.fillStyle = p.bg || '#000'
    ctx.fillRect(0, 0, p.width, p.height)
    for (const l of layers) {
        const c = l.c
        ctx.save()
        ctx.globalAlpha = l.a
        if (c.type === 'text') {
            const b = drawText(ctx, p, c)
            bounds?.set(c.id, b)
        } else if (c.type === 'color') {
            placeTransform(ctx, p, c)
            ctx.fillStyle = c.color || '#000'
            ctx.fillRect(-p.width / 2, -p.height / 2, p.width, p.height)
            bounds?.set(c.id, boxOf(p, c, p.width, p.height))
        } else {
            const f = getFrame(l)
            const m = mediaOf(p, c)
            const fw = m?.width || f?.w || p.width, fh = m?.height || f?.h || p.height
            const k = Math.min(p.width / fw, p.height / fh)
            const w = fw * k, hh = fh * k
            bounds?.set(c.id, boxOf(p, c, w, hh))
            if (f) {
                placeTransform(ctx, p, c)
                if (typeof f.src.draw === 'function' && !(f.src instanceof HTMLElement)) f.src.draw(ctx, -w / 2, -hh / 2, w, hh)
                else ctx.drawImage(f.src, -w / 2, -hh / 2, w, hh)
            }
        }
        ctx.restore()
    }
    ctx.restore()
}

function placeTransform(ctx, p, c) {
    ctx.translate(p.width / 2 + (c.x || 0), p.height / 2 + (c.y || 0))
    if (c.rot) ctx.rotate(c.rot * Math.PI / 180)
    const s = c.scale ?? 1
    ctx.scale(s, s)
}
const boxOf = (p, c, w, hh) => {
    const s = c.scale ?? 1
    return { cx: p.width / 2 + (c.x || 0), cy: p.height / 2 + (c.y || 0), w: w * s, h: hh * s, rot: c.rot || 0 }
}

export const fontOf = c => `${c.italic ? 'italic ' : ''}${c.bold ? 'bold ' : ''}${c.size || 48}px "${c.font || 'Microsoft YaHei'}", "Microsoft YaHei", sans-serif`

function hexAlpha(color, a) {
    const m = /^#([0-9a-f]{6})$/i.exec(color || '')
    if (!m) return color
    const n = parseInt(m[1], 16)
    return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${a})`
}

// 绘制文字片段，返回外框
export function drawText(ctx, p, c) {
    const size = c.size || 48
    ctx.font = fontOf(c)
    ctx.textBaseline = 'middle'
    const lines = String(c.text ?? '').split('\n')
    const lh = size * (c.lineH || 1.3)
    const widths = lines.map(l => ctx.measureText(l).width)
    const maxW = Math.max(1, ...widths)
    const pad = c.bg ? size * 0.35 : 0
    const bw = maxW + pad * 2, bh = lines.length * lh + pad * 2 * 0.6
    placeTransform(ctx, p, c)
    if (c.bg) {
        ctx.fillStyle = hexAlpha(c.bg, c.bgAlpha ?? 0.6)
        ctx.beginPath()
        ctx.roundRect(-bw / 2, -bh / 2, bw, bh, size * 0.18)
        ctx.fill()
    }
    const align = c.align || 'center'
    ctx.textAlign = align
    const ax = align === 'left' ? -maxW / 2 : align === 'right' ? maxW / 2 : 0
    const y0 = -(lines.length - 1) * lh / 2
    if (c.shadow) { ctx.shadowColor = 'rgba(0,0,0,.55)'; ctx.shadowBlur = size * 0.25; ctx.shadowOffsetY = size * 0.06 }
    lines.forEach((l, i) => {
        const y = y0 + i * lh
        if (c.stroke && c.strokeW > 0) {
            ctx.lineJoin = 'round'
            ctx.lineWidth = c.strokeW * 2
            ctx.strokeStyle = c.stroke
            ctx.strokeText(l, ax, y)
            ctx.shadowColor = 'transparent'
        }
        ctx.fillStyle = c.color || '#fff'
        ctx.fillText(l, ax, y)
    })
    return boxOf(p, c, bw, bh)
}

// 在某一时刻可以听到的片段（预览与导出混音）
export function audibleClips(p) {
    const muted = new Set(p.tracks.filter(t => t.muted).map(t => t.id))
    return p.clips.filter(c => !muted.has(c.track) && (c.volume ?? 1) > 0 &&
        (c.type === 'audio' || (c.type === 'video' && !c.detached && mediaOf(p, c)?.hasAudio)))
}
