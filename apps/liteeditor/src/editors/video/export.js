// 导出：逐帧离线渲染（mediabunny 精确解码 → OffscreenCanvas 合成 → CanvasSource 编码），OfflineAudioContext 混音
import { Output, Mp4OutputFormat, WebMOutputFormat, WavOutputFormat, BufferTarget, CanvasSource, AudioBufferSource, VideoSampleSink, QUALITY_HIGH, QUALITY_MEDIUM, QUALITY_VERY_HIGH, QUALITY_LOW, canEncodeAudio, canEncodeVideo } from 'mediabunny'
import { h } from '../../core/dom.js'
import { visualLayers, drawLayers, audibleClips, fadeEnv } from './render.js'
import { projDuration, clipDur, clipEnd, mediaOf } from './model.js'
import { decodeAudioRange, decodeAudioWhole } from './media.js'

export const QUALITIES = { low: QUALITY_LOW, medium: QUALITY_MEDIUM, high: QUALITY_HIGH, very: QUALITY_VERY_HIGH }

export class Canceled extends Error { constructor() { super('已取消'); this.canceled = true } }

// 进度对话框
export function progressDialog(title) {
    let canceled = false
    const bar = h('div.vx-bar-fill')
    const label = h('div.vx-prog-label', '准备中…')
    const pct = h('span.vx-prog-pct', '0%')
    const cancelBtn = h('button.btn', { onclick: () => { canceled = true; label.textContent = '正在取消…'; cancelBtn.disabled = true } }, '取消')
    const mask = h('div.modal-mask.vx-prog-mask', h('div.modal', { style: { width: '420px' } },
        h('div.modal-title', title),
        h('div.modal-body', h('div.vx-prog-row', label, pct), h('div.vx-bar', bar)),
        h('div.modal-actions', cancelBtn)))
    document.body.append(mask)
    requestAnimationFrame(() => mask.classList.add('show'))
    const t0 = performance.now()
    return {
        get canceled() { return canceled },
        set(p, text) {
            p = Math.max(0, Math.min(1, p))
            bar.style.width = (p * 100).toFixed(1) + '%'
            let eta = ''
            const el = (performance.now() - t0) / 1000
            if (p > 0.03 && p < 1) { const r = el / p * (1 - p); eta = ` · 剩余约 ${r < 60 ? Math.ceil(r) + ' 秒' : Math.ceil(r / 60) + ' 分钟'}` }
            pct.textContent = Math.round(p * 100) + '%'
            if (text) label.textContent = text + eta
        },
        close() { mask.classList.remove('show'); setTimeout(() => mask.remove(), 200) },
    }
}

// ---------- 音频混音 ----------
export async function mixAudio(ed, { sampleRate = 48000, channels = 2, from = 0, to, onProgress, isCanceled } = {}) {
    const p = ed.proj
    to ??= projDuration(p)
    const dur = Math.max(0.05, to - from)
    const ctx = new OfflineAudioContext(channels, Math.ceil(dur * sampleRate), sampleRate)
    const clips = audibleClips(p).filter(c => clipEnd(c) > from && c.start < to)
    let i = 0
    for (const c of clips) {
        if (isCanceled?.()) throw new Canceled()
        onProgress?.(i++ / Math.max(1, clips.length))
        const asset = ed.assets.get(c.media)
        if (!asset || asset.media.offline) continue
        const sp = c.speed || 1
        // 片段在导出范围内的部分
        const cs = Math.max(c.start, from), ce = Math.min(clipEnd(c), to)
        if (ce <= cs) continue
        const s0 = c.in + (cs - c.start) * sp, s1 = c.in + (ce - c.start) * sp
        let dec = null
        try { dec = asset.media.noDecode ? null : await decodeAudioRange(asset, s0 - 0.05, s1 + 0.05) } catch (e) { console.warn(e) }
        if (!dec) { try { dec = await decodeAudioWhole(asset) } catch (e) { console.warn('音频解码失败', e); continue } }
        const src = ctx.createBufferSource()
        src.buffer = dec.buffer
        src.playbackRate.value = sp
        const g = ctx.createGain()
        const vol = c.volume ?? 1
        // 音量包络（淡入淡出）：按 20 ms 采样
        const steps = Math.max(2, Math.ceil((ce - cs) / 0.02))
        const curve = new Float32Array(steps + 1)
        for (let k = 0; k <= steps; k++) curve[k] = vol * fadeEnv(c, cs + (ce - cs) * k / steps)
        if (c.fadeIn > 0 || c.fadeOut > 0) g.gain.setValueCurveAtTime(curve, cs - from, Math.max(0.001, ce - cs))
        else g.gain.value = vol
        src.connect(g).connect(ctx.destination)
        const offset = Math.max(0, s0 - dec.offset)
        src.start(cs - from, offset, (ce - cs) * sp)
    }
    onProgress?.(1)
    return ctx.startRendering()
}

// ---------- 视频导出 ----------
// opts: { container: 'mp4'|'webm', width, height, fps, quality, audio: bool, from, to }
export async function exportVideo(ed, opts, prog) {
    const p = ed.proj
    const fps = opts.fps ?? p.fps
    const W = even(opts.width ?? p.width), H = even(opts.height ?? p.height)
    const from = opts.from ?? 0, to = opts.to ?? projDuration(p)
    const total = Math.max(1, Math.round((to - from) * fps))
    const webm = opts.container === 'webm'
    const vcodec = webm ? 'vp9' : 'avc'
    const acodec = webm ? 'opus' : 'aac'
    if (!(await canEncodeVideo(vcodec, { width: W, height: H }))) throw new Error(`当前环境不支持 ${webm ? 'VP9' : 'H.264'} 编码（${W}×${H}）`)
    const withAudio = opts.audio !== false && audibleClips(p).length > 0 && await canEncodeAudio(acodec)

    // 1. 混音
    let mixed = null
    if (withAudio) {
        prog.set(0, '正在混合音频…')
        mixed = await mixAudio(ed, { from, to, onProgress: k => prog.set(k * 0.05, '正在混合音频…'), isCanceled: () => prog.canceled })
    }

    // 2. 输出
    const target = new BufferTarget()
    const output = new Output({ format: webm ? new WebMOutputFormat() : new Mp4OutputFormat({ fastStart: 'in-memory' }), target })
    const canvas = new OffscreenCanvas(W, H)
    const ctx = canvas.getContext('2d', { alpha: false })
    const quality = QUALITIES[opts.quality] ?? QUALITY_HIGH
    const vsrc = new CanvasSource(canvas, { codec: vcodec, quality, keyFrameInterval: 2 })
    output.addVideoTrack(vsrc, { frameRate: fps })
    let asrc = null
    if (mixed) { asrc = new AudioBufferSource({ codec: acodec, quality }); output.addAudioTrack(asrc) }
    await output.start()

    // 3. 为每个视频片段预先计算需要解码的源时间序列，使用 samplesAtTimestamps 顺序解码（每个数据包最多解码一次）
    const scale = W / p.width
    const plan = new Map()      // clipId -> number[]
    const frameTimes = []
    for (let f = 0; f < total; f++) {
        const t = from + (f + 0.5) / fps * 0 + f / fps
        frameTimes.push(t)
        for (const l of visualLayers(p, t)) if (l.c.type === 'video') { let a = plan.get(l.c.id); if (!a) plan.set(l.c.id, a = []); a.push(l.st) }
    }
    const readers = new Map()
    const openReader = async c => {
        const asset = ed.assets.get(c.media)
        if (!asset || asset.media.offline) return null
        try {
            const vt = await asset.input().getPrimaryVideoTrack()
            if (!vt || !(await vt.canDecode())) return null
            const first = await vt.getFirstTimestamp()
            const times = plan.get(c.id).map(s => Math.max(s, first))
            return new VideoSampleSink(vt).samplesAtTimestamps(times)[Symbol.asyncIterator]()
        } catch (e) { console.warn(e); return null }
    }
    // 图片预先加载
    for (const c of p.clips) if (c.type === 'image') { const a = ed.assets.get(c.media); if (a && !a.img) a.img = await a.image().catch(() => null) }

    const frames = new Map()
    try {
        for (let f = 0; f < total; f++) {
            if (prog.canceled) throw new Canceled()
            const t = frameTimes[f]
            const layers = visualLayers(p, t)
            // 取得每个视频图层的帧
            for (const l of layers) {
                if (l.c.type !== 'video') continue
                if (!readers.has(l.c.id)) readers.set(l.c.id, await openReader(l.c))
                const r = readers.get(l.c.id)
                if (!r) continue
                const { value, done } = await r.next()
                frames.get(l.c.id)?.close()
                if (done) { readers.set(l.c.id, null); frames.delete(l.c.id); continue }
                if (value) frames.set(l.c.id, value)
            }
            ctx.setTransform(scale, 0, 0, H / p.height, 0, 0)
            drawLayers(ctx, p, layers, l => {
                if (l.c.type === 'image') { const a = ed.assets.get(l.c.media); return a?.img ? { src: a.img } : null }
                const s = frames.get(l.c.id)
                return s ? { src: s } : null
            })
            // 已经结束的片段：释放解码器
            for (const [id, r] of readers) {
                const c = ed.clipById(id)
                if (!c || clipEnd(c) + (c.dissolve ?? 0) + 1 < t) { if (r) r.return?.(); readers.delete(id); frames.get(id)?.close(); frames.delete(id) }
            }
            await vsrc.add(f / fps, 1 / fps)
            if (f % 5 === 0) prog.set(0.05 + 0.9 * f / total, `正在渲染视频 ${f + 1} / ${total} 帧`)
        }
        vsrc.close()
        if (asrc && mixed) {
            prog.set(0.96, '正在编码音频…')
            await asrc.add(mixed)
            asrc.close()
        }
        prog.set(0.98, '正在写入文件…')
        await output.finalize()
    } catch (e) {
        await output.cancel().catch(() => {})
        throw e
    } finally {
        for (const r of readers.values()) r?.return?.()
        for (const s of frames.values()) s.close()
    }
    prog.set(1, '完成')
    return new Uint8Array(target.buffer)
}

// ---------- 仅音频 ----------
export async function exportAudio(ed, kind, prog) {
    prog.set(0, '正在混合音频…')
    const buf = await mixAudio(ed, { onProgress: k => prog.set(k * 0.7, '正在混合音频…'), isCanceled: () => prog.canceled })
    if (prog.canceled) throw new Canceled()
    if (kind === 'wav') { prog.set(1, '完成'); return encodeWAV(buf) }
    const target = new BufferTarget()
    const output = new Output({ format: new Mp4OutputFormat({ fastStart: 'in-memory' }), target })
    const src = new AudioBufferSource({ codec: 'aac', quality: QUALITY_HIGH })
    output.addAudioTrack(src)
    await output.start()
    prog.set(0.8, '正在编码 AAC…')
    await src.add(buf)
    src.close()
    await output.finalize()
    prog.set(1, '完成')
    return new Uint8Array(target.buffer)
}

// 16 位 PCM WAV
export function encodeWAV(buf) {
    const ch = buf.numberOfChannels, sr = buf.sampleRate, n = buf.length
    const out = new Uint8Array(44 + n * ch * 2)
    const dv = new DataView(out.buffer)
    const str = (o, s) => { for (let i = 0; i < s.length; i++) out[o + i] = s.charCodeAt(i) }
    str(0, 'RIFF'); dv.setUint32(4, 36 + n * ch * 2, true); str(8, 'WAVE'); str(12, 'fmt ')
    dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, ch, true); dv.setUint32(24, sr, true)
    dv.setUint32(28, sr * ch * 2, true); dv.setUint16(32, ch * 2, true); dv.setUint16(34, 16, true); str(36, 'data'); dv.setUint32(40, n * ch * 2, true)
    const data = []
    for (let c = 0; c < ch; c++) data.push(buf.getChannelData(c))
    let o = 44
    for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) {
        const v = Math.max(-1, Math.min(1, data[c][i]))
        dv.setInt16(o, v < 0 ? v * 0x8000 : v * 0x7fff, true)
        o += 2
    }
    return out
}

// 当前帧 PNG（精确解码）
export async function framePNG(ed, t) {
    const p = ed.proj
    const canvas = new OffscreenCanvas(p.width, p.height)
    const ctx = canvas.getContext('2d')
    const layers = visualLayers(p, t)
    const got = new Map()
    for (const l of layers) {
        const asset = ed.assets.get(l.c.media)
        if (!asset) continue
        if (l.c.type === 'image') { got.set(l.c.id, { src: asset.img ?? await asset.image() }); continue }
        try {
            const vt = await asset.input().getPrimaryVideoTrack()
            const s = await new VideoSampleSink(vt).getSample(Math.max(l.st, await vt.getFirstTimestamp()))
            if (s) got.set(l.c.id, { src: s })
        } catch (e) { console.warn(e) }
    }
    drawLayers(ctx, p, layers, l => got.get(l.c.id) ?? null)
    for (const g of got.values()) g.src.close?.()
    const blob = await canvas.convertToBlob({ type: 'image/png' })
    return new Uint8Array(await blob.arrayBuffer())
}

const even = v => Math.max(2, Math.round(v / 2) * 2)
void clipDur; void mediaOf
