// 媒体资源：探测时长 / 尺寸、缩略图条、音频波形、解码输入（mediabunny）
import { Input, ALL_FORMATS, UrlSource, BufferSource, CanvasSink, AudioBufferSink } from 'mediabunny'
import { mediaURL, MIME, extOf, baseName } from '../../core/files.js'
import { newId, mediaTypeOf } from './model.js'

// 运行时资源（不进入快照）：editor.assets: Map<mediaId, Asset>
// editor.blobs: Map<mediaId, Uint8Array> —— 无路径的媒体字节（录屏 / 内嵌），按引用共享
export class Asset {
    constructor(media, bytes) {
        this.media = media
        this.bytes = bytes ?? null
        this.url = bytes ? URL.createObjectURL(new Blob([bytes], { type: MIME[media.ext] ?? 'application/octet-stream' }))
            : media.path ? mediaURL(media.path) : null
        this.blobURL = !!bytes
        this.thumbs = []
        this.peaks = null
        this.listeners = new Set()
    }
    input() {
        if (!this._input) {
            const source = this.bytes ? new BufferSource(this.bytes) : new UrlSource(this.url)
            this._input = new Input({ formats: ALL_FORMATS, source })
        }
        return this._input
    }
    image() {
        return this._img ??= new Promise((resolve, reject) => {
            const img = new Image()
            img.onload = () => resolve(img)
            img.onerror = () => reject(new Error('图片解码失败'))
            img.src = this.url
        })
    }
    changed() { for (const fn of this.listeners) fn() }
    dispose() {
        try { this._input?.dispose() } catch { /* ignore */ }
        if (this.blobURL && this.url) URL.revokeObjectURL(this.url)
        this.thumbs = []
    }
}

// 用 <video>/<audio> 元素探测（mediabunny 不支持的容器时的后备方案）
function probeElement(url, type) {
    return new Promise((resolve, reject) => {
        const el = document.createElement(type === 'audio' ? 'audio' : 'video')
        el.preload = 'metadata'
        el.muted = true
        const done = ok => { el.removeAttribute('src'); el.load(); ok ? resolve(ok) : reject(new Error('无法解码此媒体文件')) }
        el.onloadedmetadata = () => done({ duration: el.duration, width: el.videoWidth || 0, height: el.videoHeight || 0 })
        el.onerror = () => done(null)
        el.src = url
    })
}

// 探测媒体信息：返回写入项目的媒体条目
export async function probeMedia(asset) {
    const m = asset.media
    if (m.type === 'image') {
        const img = await asset.image()
        m.width = img.naturalWidth; m.height = img.naturalHeight; m.duration = null
        m.hasVideo = true; m.hasAudio = false
        return m
    }
    try {
        const input = asset.input()
        const vt = m.type === 'video' ? await input.getPrimaryVideoTrack() : null
        const at = await input.getPrimaryAudioTrack()
        m.hasVideo = !!vt
        m.hasAudio = !!at
        if (vt) { m.width = await vt.getDisplayWidth(); m.height = await vt.getDisplayHeight() }
        let d = null
        try { d = await input.getDurationFromMetadata() } catch { /* ignore */ }
        if (!d || !Number.isFinite(d)) d = await input.computeDuration()
        m.duration = d
        if (!vt && m.type === 'video') m.type = 'audio'
    } catch (e) {
        console.warn('mediabunny 探测失败，改用媒体元素', e)
        const r = await probeElement(asset.url, m.type)
        m.duration = r.duration
        m.width = r.width; m.height = r.height
        m.hasVideo = !!r.width
        m.hasAudio = true
        if (!r.width && m.type === 'video') m.type = 'audio'
        m.noDecode = true
    }
    if (!Number.isFinite(m.duration) || m.duration <= 0) throw new Error('无法读取媒体时长')
    return m
}

export function newMediaEntry({ path, name, ext }) {
    ext = ext ?? extOf(name ?? path ?? '')
    const type = mediaTypeOf(ext)
    if (!type) throw new Error(`不支持的媒体格式：.${ext}`)
    return { id: newId('m'), name: name ?? baseName(path), ext, type, path: path ?? null }
}

// 后台生成缩略图条（视频）与波形（音频）
export async function analyze(asset) {
    const m = asset.media
    if (asset.analyzing || m.noDecode || m.offline) return
    asset.analyzing = true
    try {
        if (m.type === 'image') {
            const img = await asset.image()
            const c = document.createElement('canvas')
            c.height = 54; c.width = Math.max(1, Math.round(54 * img.naturalWidth / img.naturalHeight))
            c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
            asset.thumbs = [{ t: 0, c }]
            asset.changed()
            return
        }
        const input = asset.input()
        if (m.hasVideo) await buildThumbs(asset, input).catch(e => console.warn('缩略图失败', e))
        if (m.hasAudio) await buildPeaks(asset, input).catch(e => console.warn('波形失败', e))
    } finally { asset.analyzing = false }
}

async function buildThumbs(asset, input) {
    const vt = await input.getPrimaryVideoTrack()
    if (!vt || !(await vt.canDecode())) return
    const d = asset.media.duration
    const n = Math.min(120, Math.max(2, Math.ceil(d / 1)))
    const step = d / n
    const times = Array.from({ length: n }, (_, i) => Math.min(d - 0.01, i * step + step * 0.1))
    const sink = new CanvasSink(vt, { height: 54, fit: 'contain' })
    const out = []
    let i = 0
    for await (const w of sink.canvasesAtTimestamps(times)) {
        if (w) {
            // 复制到小画布，释放解码器画布
            const c = document.createElement('canvas')
            c.width = w.canvas.width; c.height = w.canvas.height
            c.getContext('2d').drawImage(w.canvas, 0, 0)
            out.push({ t: times[i], c })
        }
        i++
        if (i % 10 === 0) { asset.thumbs = [...out]; asset.changed() }
    }
    asset.thumbs = out
    asset.changed()
}

const PEAK_RATE = 100 // 每秒峰值数
async function buildPeaks(asset, input) {
    const at = await input.getPrimaryAudioTrack()
    if (!at || !(await at.canDecode())) return
    const d = asset.media.duration
    const peaks = new Float32Array(Math.ceil(d * PEAK_RATE) + 1)
    let n = 0
    for await (const { buffer, timestamp } of new AudioBufferSink(at).buffers()) {
        const sr = buffer.sampleRate, len = buffer.length
        const chs = []
        for (let c = 0; c < buffer.numberOfChannels; c++) chs.push(buffer.getChannelData(c))
        const per = sr / PEAK_RATE
        for (let s = 0; s < len; s += 16) {
            const idx = Math.floor((timestamp + s / sr) * PEAK_RATE)
            if (idx < 0 || idx >= peaks.length) continue
            let v = 0
            for (const ch of chs) { const a = Math.abs(ch[s]); if (a > v) v = a }
            if (v > peaks[idx]) peaks[idx] = v
        }
        if (++n % 400 === 0) { asset.peaks = peaks; asset.peakRate = PEAK_RATE; asset.changed() }
        void per
    }
    asset.peaks = peaks
    asset.peakRate = PEAK_RATE
    asset.changed()
}

// 解码一段音频为单个 AudioBuffer（导出混音用）：返回 { buffer, offset }，offset 为 buffer 开始对应的源时间
export async function decodeAudioRange(asset, from, to) {
    const input = asset.input()
    const at = await input.getPrimaryAudioTrack()
    if (!at || !(await at.canDecode())) return null
    const parts = []
    for await (const wb of new AudioBufferSink(at).buffers(Math.max(0, from), to)) parts.push(wb)
    if (!parts.length) return null
    const sr = parts[0].buffer.sampleRate
    const chs = Math.max(...parts.map(p => p.buffer.numberOfChannels))
    const t0 = parts[0].timestamp
    const last = parts[parts.length - 1]
    const total = Math.ceil((last.timestamp + last.buffer.duration - t0) * sr) + 1
    const out = new AudioBuffer({ length: Math.max(1, total), numberOfChannels: chs, sampleRate: sr })
    for (const p of parts) {
        const off = Math.max(0, Math.round((p.timestamp - t0) * sr))
        for (let c = 0; c < chs; c++) {
            const src = p.buffer.getChannelData(Math.min(c, p.buffer.numberOfChannels - 1))
            const n = Math.min(src.length, total - off)
            if (n > 0) out.getChannelData(c).set(n < src.length ? src.subarray(0, n) : src, off)
        }
    }
    return { buffer: out, offset: t0 }
}

// 后备方案：用 WebAudio 解码整个文件（mediabunny 无法解码时）
export async function decodeAudioWhole(asset) {
    const bytes = asset.bytes ?? await window.lite.readFile(asset.media.path)
    const ctx = new OfflineAudioContext(2, 1, 48000)
    const buf = await ctx.decodeAudioData(bytes.slice().buffer)
    return { buffer: buf, offset: 0 }
}
