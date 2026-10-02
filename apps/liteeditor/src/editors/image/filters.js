// 调整与滤镜：纯像素计算（ImageData），在选区内生效
// 调整：apply(src ImageData, params) -> 修改后的 ImageData（原地）
import { makeCanvas, ctx2d } from './doc.js'

const clamp8 = v => v < 0 ? 0 : v > 255 ? 255 : v
// ---------- 颜色空间 ----------
export function rgb2hsl(r, g, b) {
    r /= 255; g /= 255; b /= 255
    const max = Math.max(r, g, b), min = Math.min(r, g, b)
    let h = 0, s = 0
    const l = (max + min) / 2
    if (max !== min) {
        const d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
        h /= 6
    }
    return [h, s, l]
}
export function hsl2rgb(h, s, l) {
    if (s === 0) { const v = l * 255; return [v, v, v] }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    const f = t => { if (t < 0) t += 1; if (t > 1) t -= 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p }
    return [f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255]
}
const lum = (r, g, b) => 0.299 * r + 0.587 * g + 0.114 * b

// 通过查找表逐通道映射
function applyLUT(id, lr, lg = lr, lb = lr) {
    const d = id.data
    for (let i = 0; i < d.length; i += 4) { d[i] = lr[d[i]]; d[i + 1] = lg[d[i + 1]]; d[i + 2] = lb[d[i + 2]] }
    return id
}
const lut = fn => { const t = new Uint8ClampedArray(256); for (let i = 0; i < 256; i++) t[i] = fn(i); return t }

// 单调三次样条（曲线调整）
export function curveLUT(points) {
    const pts = [...points].sort((a, b) => a[0] - b[0])
    const n = pts.length
    if (n < 2) return lut(i => i)
    const xs = pts.map(p => p[0]), ys = pts.map(p => p[1])
    const dx = [], dy = [], m = []
    for (let i = 0; i < n - 1; i++) { dx.push(xs[i + 1] - xs[i] || 1e-6); dy.push(ys[i + 1] - ys[i]); m.push(dy[i] / dx[i]) }
    const t = [m[0]]
    for (let i = 1; i < n - 1; i++) t.push(m[i - 1] * m[i] <= 0 ? 0 : 3 * (dx[i - 1] + dx[i]) / ((2 * dx[i] + dx[i - 1]) / m[i - 1] + (dx[i] + 2 * dx[i - 1]) / m[i]))
    t.push(m[n - 2])
    return lut(x => {
        if (x <= xs[0]) return ys[0]
        if (x >= xs[n - 1]) return ys[n - 1]
        let i = 0
        while (x > xs[i + 1]) i++
        const h = dx[i], u = (x - xs[i]) / h
        const h00 = 2 * u ** 3 - 3 * u ** 2 + 1, h10 = u ** 3 - 2 * u ** 2 + u, h01 = -2 * u ** 3 + 3 * u ** 2, h11 = u ** 3 - u ** 2
        return h00 * ys[i] + h10 * h * t[i] + h01 * ys[i + 1] + h11 * h * t[i + 1]
    })
}

// ---------- 调整 ----------
// fields 描述对话框；apply(ImageData, values)
export const ADJUSTMENTS = {
    brightness: {
        label: '亮度 / 对比度', key: 'Ctrl+Alt+B',
        fields: [{ key: 'b', label: '亮度', type: 'range', min: -150, max: 150, value: 0 }, { key: 'c', label: '对比度', type: 'range', min: -100, max: 100, value: 0 }],
        apply(id, { b, c }) {
            const k = (259 * (c * 2.55 + 255)) / (255 * (259 - c * 2.55))
            return applyLUT(id, lut(i => k * (i + b - 128) + 128))
        },
    },
    levels: {
        label: '色阶', key: 'Ctrl+L',
        fields: [
            { key: 'inB', label: '输入黑场', type: 'range', min: 0, max: 253, value: 0 }, { key: 'gamma', label: '中间调', type: 'range', min: 10, max: 300, value: 100, suffix: '%' },
            { key: 'inW', label: '输入白场', type: 'range', min: 2, max: 255, value: 255 }, { key: 'outB', label: '输出黑场', type: 'range', min: 0, max: 255, value: 0 },
            { key: 'outW', label: '输出白场', type: 'range', min: 0, max: 255, value: 255 },
        ],
        apply(id, { inB, inW, gamma, outB, outW }) {
            const g = 100 / gamma
            return applyLUT(id, lut(i => {
                const t = Math.max(0, Math.min(1, (i - inB) / Math.max(1, inW - inB)))
                return outB + Math.pow(t, g) * (outW - outB)
            }))
        },
    },
    hsl: {
        label: '色相 / 饱和度', key: 'Ctrl+U',
        fields: [
            { key: 'h', label: '色相', type: 'range', min: -180, max: 180, value: 0, suffix: '°' },
            { key: 's', label: '饱和度', type: 'range', min: -100, max: 100, value: 0 },
            { key: 'l', label: '明度', type: 'range', min: -100, max: 100, value: 0 },
            { key: 'colorize', label: '着色', type: 'check', value: false },
        ],
        apply(id, { h, s, l, colorize }) {
            const d = id.data
            for (let i = 0; i < d.length; i += 4) {
                let [H, S, L] = rgb2hsl(d[i], d[i + 1], d[i + 2])
                if (colorize) { H = ((h + 180) / 360); S = Math.max(0, (s + 100) / 200) } else {
                    H = (H + h / 360 + 1) % 1
                    S = s >= 0 ? S + (1 - S) * s / 100 * S : S * (1 + s / 100)
                }
                L = l >= 0 ? L + (1 - L) * l / 100 : L * (1 + l / 100)
                const [r, g, b] = hsl2rgb(H, Math.max(0, Math.min(1, S)), Math.max(0, Math.min(1, L)))
                d[i] = r; d[i + 1] = g; d[i + 2] = b
            }
            return id
        },
    },
    balance: {
        label: '色彩平衡', key: 'Ctrl+B',
        fields: [
            { key: 'cr', label: '青色 ↔ 红色', type: 'range', min: -100, max: 100, value: 0 },
            { key: 'mg', label: '洋红 ↔ 绿色', type: 'range', min: -100, max: 100, value: 0 },
            { key: 'yb', label: '黄色 ↔ 蓝色', type: 'range', min: -100, max: 100, value: 0 },
            { key: 'tone', label: '色调', type: 'select', value: 'mid', options: [['shadow', '阴影'], ['mid', '中间调'], ['high', '高光']] },
            { key: 'keep', label: '保持明度', type: 'check', value: true },
        ],
        apply(id, { cr, mg, yb, tone, keep }) {
            const d = id.data
            const w = v => tone === 'shadow' ? Math.max(0, 1 - v / 128) : tone === 'high' ? Math.max(0, (v - 128) / 128) : 1 - Math.abs(v - 128) / 128
            for (let i = 0; i < d.length; i += 4) {
                const r0 = d[i], g0 = d[i + 1], b0 = d[i + 2], L0 = lum(r0, g0, b0), k = w(L0) * 0.8
                let r = r0 + cr * k, g = g0 + mg * k, b = b0 + yb * k
                if (keep) { const dl = L0 - lum(r, g, b); r += dl; g += dl; b += dl }
                d[i] = r; d[i + 1] = g; d[i + 2] = b
            }
            return id
        },
    },
    curves: {
        label: '曲线', key: 'Ctrl+M', custom: 'curves',
        apply(id, { points, channel = 'rgb' }) {
            const t = curveLUT(points), idt = lut(i => i)
            return applyLUT(id, channel === 'rgb' || channel === 'r' ? t : idt, channel === 'rgb' || channel === 'g' ? t : idt, channel === 'rgb' || channel === 'b' ? t : idt)
        },
    },
    exposure: {
        label: '曝光度',
        fields: [{ key: 'ev', label: '曝光度', type: 'range', min: -300, max: 300, value: 0, suffix: '' }, { key: 'offset', label: '位移', type: 'range', min: -50, max: 50, value: 0 }, { key: 'gamma', label: '灰度系数', type: 'range', min: 20, max: 300, value: 100, suffix: '%' }],
        apply(id, { ev, offset, gamma }) {
            const k = Math.pow(2, ev / 100), gm = 100 / gamma
            return applyLUT(id, lut(i => 255 * Math.pow(Math.max(0, Math.min(1, (i / 255) * k + offset / 255)), gm)))
        },
    },
    vibrance: {
        label: '自然饱和度',
        fields: [{ key: 'v', label: '自然饱和度', type: 'range', min: -100, max: 100, value: 0 }, { key: 's', label: '饱和度', type: 'range', min: -100, max: 100, value: 0 }],
        apply(id, { v, s }) {
            const d = id.data
            for (let i = 0; i < d.length; i += 4) {
                const r = d[i], g = d[i + 1], b = d[i + 2]
                const max = Math.max(r, g, b), avg = (r + g + b) / 3
                const amt = ((Math.abs(max - avg) * 2 / 255) * (-v / 100)) + (-s / 100)
                const k = -amt
                d[i] = r + (r - avg) * (k + (v / 100) * (1 - Math.abs(max - avg) / 128)) * 0.8
                d[i + 1] = g + (g - avg) * (k + (v / 100) * (1 - Math.abs(max - avg) / 128)) * 0.8
                d[i + 2] = b + (b - avg) * (k + (v / 100) * (1 - Math.abs(max - avg) / 128)) * 0.8
            }
            return id
        },
    },
    bw: {
        label: '黑白', key: 'Ctrl+Alt+Shift+B',
        fields: [
            { key: 'r', label: '红色', type: 'range', min: -100, max: 200, value: 40, suffix: '%' }, { key: 'g', label: '绿色', type: 'range', min: -100, max: 200, value: 40, suffix: '%' },
            { key: 'b', label: '蓝色', type: 'range', min: -100, max: 200, value: 20, suffix: '%' }, { key: 'tint', label: '色调', type: 'check', value: false },
            { key: 'tintColor', label: '色调颜色', type: 'color', value: '#c8a26b' },
        ],
        apply(id, { r, g, b, tint, tintColor }) {
            const d = id.data
            const tc = hex(tintColor)
            for (let i = 0; i < d.length; i += 4) {
                const v = clamp8((d[i] * r + d[i + 1] * g + d[i + 2] * b) / 100)
                if (tint) { d[i] = v * tc[0] / 255 * 1.4; d[i + 1] = v * tc[1] / 255 * 1.4; d[i + 2] = v * tc[2] / 255 * 1.4 } else d[i] = d[i + 1] = d[i + 2] = v
            }
            return id
        },
    },
    photoFilter: {
        label: '照片滤镜',
        fields: [{ key: 'color', label: '滤镜颜色', type: 'color', value: '#ec8a00' }, { key: 'density', label: '浓度', type: 'range', min: 1, max: 100, value: 25, suffix: '%' }, { key: 'keep', label: '保持明度', type: 'check', value: true }],
        apply(id, { color, density, keep }) {
            const d = id.data, c = hex(color), k = density / 100
            for (let i = 0; i < d.length; i += 4) {
                const L0 = lum(d[i], d[i + 1], d[i + 2])
                let r = d[i] * (1 - k) + (d[i] * c[0] / 255) * k * 1.6 + c[0] * k * 0.15
                let g = d[i + 1] * (1 - k) + (d[i + 1] * c[1] / 255) * k * 1.6 + c[1] * k * 0.15
                let b = d[i + 2] * (1 - k) + (d[i + 2] * c[2] / 255) * k * 1.6 + c[2] * k * 0.15
                if (keep) { const dl = L0 - lum(r, g, b); r += dl; g += dl; b += dl }
                d[i] = r; d[i + 1] = g; d[i + 2] = b
            }
            return id
        },
    },
    gradientMap: {
        label: '渐变映射',
        fields: [{ key: 'c1', label: '暗部颜色', type: 'color', value: '#1e1b4b' }, { key: 'c2', label: '亮部颜色', type: 'color', value: '#fbbf24' }],
        apply(id, { c1, c2 }) {
            const a = hex(c1), b = hex(c2), d = id.data
            for (let i = 0; i < d.length; i += 4) {
                const t = lum(d[i], d[i + 1], d[i + 2]) / 255
                d[i] = a[0] + (b[0] - a[0]) * t; d[i + 1] = a[1] + (b[1] - a[1]) * t; d[i + 2] = a[2] + (b[2] - a[2]) * t
            }
            return id
        },
    },
    invert: { label: '反相', key: 'Ctrl+I', instant: true, apply: id => applyLUT(id, lut(i => 255 - i)) },
    desaturate: {
        label: '去色', key: 'Ctrl+Shift+U', instant: true,
        apply(id) { const d = id.data; for (let i = 0; i < d.length; i += 4) d[i] = d[i + 1] = d[i + 2] = lum(d[i], d[i + 1], d[i + 2]); return id },
    },
    threshold: {
        label: '阈值',
        fields: [{ key: 't', label: '阈值色阶', type: 'range', min: 1, max: 255, value: 128 }],
        apply(id, { t }) { const d = id.data; for (let i = 0; i < d.length; i += 4) d[i] = d[i + 1] = d[i + 2] = lum(d[i], d[i + 1], d[i + 2]) >= t ? 255 : 0; return id },
    },
    posterize: {
        label: '色调分离',
        fields: [{ key: 'n', label: '色阶', type: 'range', min: 2, max: 32, value: 4 }],
        apply(id, { n }) { const s = 255 / (n - 1); return applyLUT(id, lut(i => Math.round(Math.round(i / s) * s))) },
    },
    equalize: {
        label: '色调均化', instant: true,
        apply(id) {
            const d = id.data, hist = new Array(256).fill(0)
            let n = 0
            for (let i = 0; i < d.length; i += 4) if (d[i + 3]) { hist[Math.round(lum(d[i], d[i + 1], d[i + 2]))]++; n++ }
            const cdf = []; let acc = 0
            for (let i = 0; i < 256; i++) { acc += hist[i]; cdf.push(acc / (n || 1)) }
            for (let i = 0; i < d.length; i += 4) {
                const L0 = lum(d[i], d[i + 1], d[i + 2]), L1 = cdf[Math.round(L0)] * 255, k = L0 ? L1 / L0 : 1
                d[i] *= k; d[i + 1] *= k; d[i + 2] *= k
            }
            return id
        },
    },
    autoContrast: {
        label: '自动对比度', key: 'Ctrl+Alt+Shift+L', instant: true,
        apply(id) {
            const d = id.data, hist = new Array(256).fill(0)
            let n = 0
            for (let i = 0; i < d.length; i += 4) if (d[i + 3]) { hist[Math.round(lum(d[i], d[i + 1], d[i + 2]))]++; n++ }
            let lo = 0, hi = 255, acc = 0
            while (lo < 255 && (acc += hist[lo]) < n * 0.005) lo++
            acc = 0
            while (hi > 0 && (acc += hist[hi]) < n * 0.005) hi--
            if (hi <= lo) return id
            return applyLUT(id, lut(i => (i - lo) * 255 / (hi - lo)))
        },
    },
}

export function hex(c) {
    const s = String(c).replace('#', '')
    const f = s.length === 3 ? [...s].map(x => x + x).join('') : s
    const n = parseInt(f, 16)
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

// ---------- 滤镜（需要邻域） ----------
// 高斯模糊：三次盒式模糊近似，分别处理 RGBA（预乘避免透明边缘发黑）
function boxBlur(src, dst, w, h, r, horizontal) {
    const iarr = 1 / (r + r + 1)
    const outer = horizontal ? h : w, inner = horizontal ? w : h
    for (let o = 0; o < outer; o++) {
        const idx = i => horizontal ? (o * w + i) * 4 : (i * w + o) * 4
        for (let c = 0; c < 4; c++) {
            let acc = 0
            const first = src[idx(0) + c], last = src[idx(inner - 1) + c]
            acc = (r + 1) * first
            for (let j = 0; j < r; j++) acc += src[idx(Math.min(j, inner - 1)) + c]
            for (let i = 0; i < inner; i++) {
                const add = i + r < inner ? src[idx(i + r) + c] : last
                const sub = i - r - 1 >= 0 ? src[idx(i - r - 1) + c] : first
                acc += add - sub
                dst[idx(i) + c] = acc * iarr
            }
        }
    }
}
export function gaussianBlur(id, radius) {
    const { width: w, height: h, data } = id
    if (radius < 0.5) return id
    const f = new Float32Array(data.length)
    for (let i = 0; i < data.length; i += 4) { const a = data[i + 3] / 255; f[i] = data[i] * a; f[i + 1] = data[i + 1] * a; f[i + 2] = data[i + 2] * a; f[i + 3] = data[i + 3] }
    const tmp = new Float32Array(data.length)
    // 三次盒式模糊的半径
    const sigma = radius / 2, n = 3
    const wIdeal = Math.sqrt((12 * sigma * sigma / n) + 1)
    let wl = Math.floor(wIdeal); if (wl % 2 === 0) wl--
    const m = Math.round((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4))
    for (let k = 0; k < n; k++) {
        const r = Math.max(1, ((k < m ? wl : wl + 2) - 1) / 2)
        boxBlur(f, tmp, w, h, r, true)
        boxBlur(tmp, f, w, h, r, false)
    }
    for (let i = 0; i < data.length; i += 4) {
        const a = f[i + 3]
        data[i + 3] = a
        const k = a > 0 ? 255 / a : 0
        data[i] = f[i] * k; data[i + 1] = f[i + 1] * k; data[i + 2] = f[i + 2] * k
    }
    return id
}
function convolve(id, kernel, { bias = 0, divisor, gray = false } = {}) {
    const { width: w, height: h, data } = id
    const src = new Uint8ClampedArray(data)
    const size = Math.sqrt(kernel.length) | 0, half = size >> 1
    const div = divisor ?? (kernel.reduce((a, b) => a + b, 0) || 1)
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        let r = 0, g = 0, b = 0
        for (let ky = 0; ky < size; ky++) {
            const yy = Math.min(h - 1, Math.max(0, y + ky - half))
            for (let kx = 0; kx < size; kx++) {
                const xx = Math.min(w - 1, Math.max(0, x + kx - half))
                const k = kernel[ky * size + kx], p = (yy * w + xx) * 4
                r += src[p] * k; g += src[p + 1] * k; b += src[p + 2] * k
            }
        }
        const o = (y * w + x) * 4
        if (gray) { const v = (r + g + b) / 3 / div + bias; data[o] = data[o + 1] = data[o + 2] = v }
        else { data[o] = r / div + bias; data[o + 1] = g / div + bias; data[o + 2] = b / div + bias }
    }
    return id
}

export const FILTERS = {
    gaussian: {
        label: '高斯模糊', group: '模糊',
        fields: [{ key: 'r', label: '半径', type: 'range', min: 1, max: 100, value: 4, suffix: ' px' }],
        apply: (id, { r }) => gaussianBlur(id, r),
    },
    motion: {
        label: '动感模糊', group: '模糊',
        fields: [{ key: 'angle', label: '角度', type: 'range', min: -90, max: 90, value: 0, suffix: '°' }, { key: 'dist', label: '距离', type: 'range', min: 1, max: 100, value: 16, suffix: ' px' }],
        apply(id, { angle, dist }) {
            const { width: w, height: h, data } = id
            const src = new Uint8ClampedArray(data)
            const dx = Math.cos(angle * Math.PI / 180), dy = Math.sin(angle * Math.PI / 180)
            const steps = Math.max(2, Math.round(dist))
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                let r = 0, g = 0, b = 0, a = 0
                for (let s = 0; s < steps; s++) {
                    const t = s - steps / 2
                    const xx = Math.min(w - 1, Math.max(0, Math.round(x + dx * t))), yy = Math.min(h - 1, Math.max(0, Math.round(y + dy * t)))
                    const p = (yy * w + xx) * 4
                    r += src[p]; g += src[p + 1]; b += src[p + 2]; a += src[p + 3]
                }
                const o = (y * w + x) * 4
                data[o] = r / steps; data[o + 1] = g / steps; data[o + 2] = b / steps; data[o + 3] = a / steps
            }
            return id
        },
    },
    sharpen: {
        label: 'USM 锐化', group: '锐化',
        fields: [{ key: 'amount', label: '数量', type: 'range', min: 1, max: 500, value: 100, suffix: '%' }, { key: 'r', label: '半径', type: 'range', min: 1, max: 20, value: 2, suffix: ' px' }, { key: 't', label: '阈值', type: 'range', min: 0, max: 60, value: 2 }],
        apply(id, { amount, r, t }) {
            const blur = new ImageData(new Uint8ClampedArray(id.data), id.width, id.height)
            gaussianBlur(blur, r)
            const d = id.data, b = blur.data, k = amount / 100
            for (let i = 0; i < d.length; i += 4) for (let c = 0; c < 3; c++) {
                const diff = d[i + c] - b[i + c]
                if (Math.abs(diff) >= t) d[i + c] = clamp8(d[i + c] + diff * k)
            }
            return id
        },
    },
    sharpenSimple: { label: '锐化', group: '锐化', instant: true, apply: id => convolve(id, [0, -1, 0, -1, 5, -1, 0, -1, 0]) },
    noise: {
        label: '添加杂色', group: '杂色',
        fields: [{ key: 'amount', label: '数量', type: 'range', min: 1, max: 100, value: 15, suffix: '%' }, { key: 'mono', label: '单色', type: 'check', value: true }],
        apply(id, { amount, mono }) {
            const d = id.data, k = amount * 2.55
            for (let i = 0; i < d.length; i += 4) {
                if (mono) { const n = (Math.random() - 0.5) * k; d[i] += n; d[i + 1] += n; d[i + 2] += n }
                else { d[i] += (Math.random() - 0.5) * k; d[i + 1] += (Math.random() - 0.5) * k; d[i + 2] += (Math.random() - 0.5) * k }
            }
            return id
        },
    },
    median: {
        label: '中间值（去斑）', group: '杂色',
        fields: [{ key: 'r', label: '半径', type: 'range', min: 1, max: 6, value: 1, suffix: ' px' }],
        apply(id, { r }) {
            const { width: w, height: h, data } = id
            const src = new Uint8ClampedArray(data)
            const vals = [[], [], []]
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                vals[0].length = vals[1].length = vals[2].length = 0
                for (let yy = Math.max(0, y - r); yy <= Math.min(h - 1, y + r); yy++) for (let xx = Math.max(0, x - r); xx <= Math.min(w - 1, x + r); xx++) {
                    const p = (yy * w + xx) * 4
                    vals[0].push(src[p]); vals[1].push(src[p + 1]); vals[2].push(src[p + 2])
                }
                const o = (y * w + x) * 4
                for (let c = 0; c < 3; c++) { const v = vals[c].sort((a, b) => a - b); data[o + c] = v[v.length >> 1] }
            }
            return id
        },
    },
    mosaic: {
        label: '马赛克', group: '像素化',
        fields: [{ key: 's', label: '单元格大小', type: 'range', min: 2, max: 100, value: 12, suffix: ' px' }],
        apply(id, { s }) {
            const { width: w, height: h, data } = id
            for (let by = 0; by < h; by += s) for (let bx = 0; bx < w; bx += s) {
                let r = 0, g = 0, b = 0, a = 0, n = 0
                for (let y = by; y < Math.min(h, by + s); y++) for (let x = bx; x < Math.min(w, bx + s); x++) { const p = (y * w + x) * 4; r += data[p]; g += data[p + 1]; b += data[p + 2]; a += data[p + 3]; n++ }
                for (let y = by; y < Math.min(h, by + s); y++) for (let x = bx; x < Math.min(w, bx + s); x++) { const p = (y * w + x) * 4; data[p] = r / n; data[p + 1] = g / n; data[p + 2] = b / n; data[p + 3] = a / n }
            }
            return id
        },
    },
    emboss: { label: '浮雕效果', group: '风格化', instant: true, apply: id => convolve(id, [-2, -1, 0, -1, 1, 1, 0, 1, 2], { divisor: 1, bias: 0 }) },
    edges: {
        label: '查找边缘', group: '风格化', instant: true,
        apply(id) {
            const { width: w, height: h, data } = id
            const g = new Float32Array(w * h)
            for (let i = 0; i < w * h; i++) g[i] = lum(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
            const at = (x, y) => g[Math.min(h - 1, Math.max(0, y)) * w + Math.min(w - 1, Math.max(0, x))]
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                const gx = -at(x - 1, y - 1) - 2 * at(x - 1, y) - at(x - 1, y + 1) + at(x + 1, y - 1) + 2 * at(x + 1, y) + at(x + 1, y + 1)
                const gy = -at(x - 1, y - 1) - 2 * at(x, y - 1) - at(x + 1, y - 1) + at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1)
                const v = 255 - clamp8(Math.hypot(gx, gy))
                const o = (y * w + x) * 4
                data[o] = data[o + 1] = data[o + 2] = v
            }
            return id
        },
    },
    sketch: {
        label: '素描', group: '艺术效果',
        fields: [{ key: 'r', label: '线条粗细', type: 'range', min: 1, max: 20, value: 6 }],
        apply(id, { r }) {
            const d = id.data
            // 去色 → 反相模糊 → 颜色减淡
            const gray = new Uint8ClampedArray(d.length)
            for (let i = 0; i < d.length; i += 4) { const v = lum(d[i], d[i + 1], d[i + 2]); gray[i] = gray[i + 1] = gray[i + 2] = 255 - v; gray[i + 3] = 255 }
            const inv = new ImageData(gray, id.width, id.height)
            gaussianBlur(inv, r)
            for (let i = 0; i < d.length; i += 4) {
                const base = lum(d[i], d[i + 1], d[i + 2]), top = inv.data[i]
                const v = top >= 255 ? 255 : Math.min(255, base * 255 / (255 - top))
                d[i] = d[i + 1] = d[i + 2] = v
            }
            return id
        },
    },
    oil: {
        label: '油画', group: '艺术效果',
        fields: [{ key: 'r', label: '笔刷大小', type: 'range', min: 1, max: 8, value: 3 }, { key: 'levels', label: '细节', type: 'range', min: 4, max: 40, value: 20 }],
        apply(id, { r, levels }) {
            const { width: w, height: h, data } = id
            const src = new Uint8ClampedArray(data)
            const cnt = new Int32Array(levels), sr = new Int32Array(levels), sg = new Int32Array(levels), sb = new Int32Array(levels)
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                cnt.fill(0); sr.fill(0); sg.fill(0); sb.fill(0)
                for (let yy = Math.max(0, y - r); yy <= Math.min(h - 1, y + r); yy++) for (let xx = Math.max(0, x - r); xx <= Math.min(w - 1, x + r); xx++) {
                    const p = (yy * w + xx) * 4
                    const l = Math.min(levels - 1, (lum(src[p], src[p + 1], src[p + 2]) * levels / 256) | 0)
                    cnt[l]++; sr[l] += src[p]; sg[l] += src[p + 1]; sb[l] += src[p + 2]
                }
                let best = 0
                for (let l = 1; l < levels; l++) if (cnt[l] > cnt[best]) best = l
                const o = (y * w + x) * 4
                data[o] = sr[best] / cnt[best]; data[o + 1] = sg[best] / cnt[best]; data[o + 2] = sb[best] / cnt[best]
            }
            return id
        },
    },
    vignette: {
        label: '暗角', group: '镜头',
        fields: [{ key: 'amount', label: '强度', type: 'range', min: -100, max: 100, value: 50 }, { key: 'size', label: '范围', type: 'range', min: 10, max: 100, value: 60, suffix: '%' }],
        apply(id, { amount, size }) {
            const { width: w, height: h, data } = id
            const cx = w / 2, cy = h / 2, R = Math.hypot(cx, cy), inner = R * size / 100
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                const dd = Math.hypot(x - cx, y - cy)
                if (dd <= inner) continue
                const t = Math.min(1, (dd - inner) / (R - inner)), k = t * t * amount / 100
                const o = (y * w + x) * 4
                for (let c = 0; c < 3; c++) data[o + c] = k > 0 ? data[o + c] * (1 - k) : data[o + c] + (255 - data[o + c]) * -k
            }
            return id
        },
    },
    pixelateColor: {
        label: '彩色半调', group: '像素化',
        fields: [{ key: 's', label: '网点大小', type: 'range', min: 4, max: 40, value: 8, suffix: ' px' }],
        apply(id, { s }) {
            const { width: w, height: h } = id
            const c = makeCanvas(w, h), g = ctx2d(c)
            g.fillStyle = '#fff'; g.fillRect(0, 0, w, h)
            const d = id.data
            for (let y = 0; y < h; y += s) for (let x = 0; x < w; x += s) {
                const p = (Math.min(h - 1, y + (s >> 1)) * w + Math.min(w - 1, x + (s >> 1))) * 4
                const L = 1 - lum(d[p], d[p + 1], d[p + 2]) / 255
                g.fillStyle = `rgb(${d[p]},${d[p + 1]},${d[p + 2]})`
                g.beginPath(); g.arc(x + s / 2, y + s / 2, Math.max(0.5, s * 0.7 * Math.sqrt(0.2 + L * 0.8)), 0, Math.PI * 2); g.fill()
            }
            const out = g.getImageData(0, 0, w, h)
            for (let i = 0; i < d.length; i += 4) { d[i] = out.data[i]; d[i + 1] = out.data[i + 1]; d[i + 2] = out.data[i + 2] }
            return id
        },
    },
}

// 把 ImageData 结果按选区混合回原图（sel 为图层坐标系中的蒙版 alpha）
export function blendBySelection(orig, result, selAlpha) {
    if (!selAlpha) return result
    const o = orig.data, r = result.data
    for (let i = 0; i < r.length; i += 4) {
        const k = selAlpha[i + 3] / 255
        if (k >= 1) continue
        for (let c = 0; c < 4; c++) r[i + c] = o[i + c] + (r[i + c] - o[i + c]) * k
    }
    return result
}
