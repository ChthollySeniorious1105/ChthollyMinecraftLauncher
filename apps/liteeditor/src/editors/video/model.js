// 视频项目数据模型：画布 / 媒体库 / 轨道 / 片段（纯 JSON，可直接快照）
import { uid } from '../../core/dom.js'

export const PRESETS = [
    ['1080p', '1080p 横屏', 1920, 1080],
    ['720p', '720p 横屏', 1280, 720],
    ['4k', '4K 超清', 3840, 2160],
    ['vertical', '竖屏 1080 × 1920', 1080, 1920],
    ['square', '正方形 1080 × 1080', 1080, 1080],
    ['portrait', '4:5 竖版 1080 × 1350', 1080, 1350],
]
export const FPS_LIST = [24, 25, 30, 50, 60]

export const VIDEO_EXTS = ['mp4', 'm4v', 'webm', 'mkv', 'mov']
export const AUDIO_EXTS = ['mp3', 'wav', 'ogg', 'oga', 'opus', 'flac', 'm4a', 'aac']
export const IMAGE_EXTS = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'avif']
export const mediaTypeOf = ext => VIDEO_EXTS.includes(ext) ? 'video' : AUDIO_EXTS.includes(ext) ? 'audio' : IMAGE_EXTS.includes(ext) ? 'image' : null

export const newId = p => uid(p)
export const clone = o => JSON.parse(JSON.stringify(o))
const EPS = 1e-4

export function newProject({ width = 1920, height = 1080, fps = 30 } = {}) {
    return {
        format: 'lvideo', version: 1, width, height, fps, bg: '#000000',
        media: [], tracks: [newTrack('video', 'V1'), newTrack('audio', 'A1')], clips: [],
    }
}
export const newTrack = (type, name) => ({ id: newId('t'), type, name, muted: false, hidden: false, locked: false })

export const TEXT_STYLES = {
    subtitle: { text: '在此输入字幕', font: 'Microsoft YaHei', size: 56, color: '#ffffff', bold: true, italic: false, stroke: '#000000', strokeW: 6, bg: '', bgAlpha: 0.55, align: 'center', lineH: 1.3 },
    title: { text: '标题文字', font: 'Microsoft YaHei', size: 120, color: '#ffffff', bold: true, italic: false, stroke: '', strokeW: 0, bg: '', bgAlpha: 0.55, align: 'center', lineH: 1.25, shadow: true },
    lower: { text: '姓名 · 职位', font: 'Microsoft YaHei', size: 48, color: '#ffffff', bold: true, italic: false, stroke: '', strokeW: 0, bg: '#e11d48', bgAlpha: 0.9, align: 'left', lineH: 1.3 },
}
export const FONTS = [
    ['Microsoft YaHei', '微软雅黑'], ['SimHei', '黑体'], ['SimSun', '宋体'], ['KaiTi', '楷体'], ['FangSong', '仿宋'],
    ['Arial', 'Arial'], ['Georgia', 'Georgia'], ['Impact', 'Impact'], ['Consolas', 'Consolas'],
]

export function makeClip(type, props = {}) {
    const c = { id: newId('c'), type, track: null, start: 0, in: 0, out: 5, speed: 1, volume: 1, fadeIn: 0, fadeOut: 0, opacity: 1, x: 0, y: 0, scale: 1, rot: 0, dissolve: 0 }
    if (type === 'text') Object.assign(c, TEXT_STYLES.subtitle)
    if (type === 'color') c.color = '#1e293b'
    return Object.assign(c, props)
}

// ---------- 时间计算 ----------
export const clipDur = c => (c.out - c.in) / (c.speed || 1)
export const clipEnd = c => c.start + clipDur(c)
export const srcTime = (c, t) => c.in + (t - c.start) * (c.speed || 1)
export const hasSource = c => c.type === 'video' || c.type === 'audio' || c.type === 'image'
export const projDuration = p => p.clips.reduce((m, c) => Math.max(m, clipEnd(c)), 0)
export const isActive = (c, t) => t >= c.start - EPS && t < clipEnd(c) - EPS

export const trackOf = (p, c) => p.tracks.find(t => t.id === c.track)
export const clipsOn = (p, trackId) => p.clips.filter(c => c.track === trackId).sort((a, b) => a.start - b.start)
export const mediaOf = (p, c) => c.media ? p.media.find(m => m.id === c.media) : null

// 同一轨道上紧挨着 c 之前的片段（交叉溶解使用）
export function prevAdjacent(p, c) {
    let best = null
    for (const o of p.clips) if (o !== c && o.track === c.track && Math.abs(clipEnd(o) - c.start) < 0.02) best = o
    return best
}

export function clipName(p, c) {
    if (c.type === 'text') return (c.text || '文字').split('\n')[0]
    if (c.type === 'color') return '纯色'
    return mediaOf(p, c)?.name ?? '媒体'
}

// 片段可修剪的最大源时长（图片 / 文字 / 纯色不限）
export function maxOut(p, c) {
    if (c.type !== 'video' && c.type !== 'audio') return Infinity
    return mediaOf(p, c)?.duration ?? Infinity
}

// ---------- 编辑操作 ----------
export function splitClip(p, c, t) {
    if (t <= c.start + EPS || t >= clipEnd(c) - EPS) return null
    const s = srcTime(c, t)
    const right = { ...clone(c), id: newId('c'), in: s, start: t, fadeIn: 0, dissolve: 0 }
    c.out = s
    c.fadeOut = 0
    p.clips.splice(p.clips.indexOf(c) + 1, 0, right)
    return right
}
export function trimStartTo(c, t) {
    const d = t - c.start
    c.in += d * (c.speed || 1)
    c.start = t
}
export function trimEndTo(c, t) { c.out = srcTime(c, t) }

export function removeClip(p, c) {
    const i = p.clips.indexOf(c)
    if (i >= 0) p.clips.splice(i, 1)
}

// 覆盖式放置：清空轨道上 [s, e) 范围内的其他片段（完全覆盖删除，部分覆盖修剪，跨越则切开）
export function clearRange(p, trackId, s, e, except = new Set()) {
    for (const c of [...p.clips]) {
        if (c.track !== trackId || except.has(c.id)) continue
        const cs = c.start, ce = clipEnd(c)
        if (ce <= s + EPS || cs >= e - EPS) continue
        if (cs >= s - EPS && ce <= e + EPS) { removeClip(p, c); continue }
        if (cs < s && ce > e) {
            const right = splitClip(p, c, e)
            trimEndTo(c, s)
            if (right) right.dissolve = 0
            continue
        }
        if (cs < s) trimEndTo(c, s)
        else trimStartTo(c, e)
    }
}

// 在轨道上寻找从 t 开始能放下 dur 时长的位置（不与其他片段重叠）
export function freeSpotAfter(p, trackId, t) {
    let end = t
    for (const c of clipsOn(p, trackId)) if (clipEnd(c) > end && c.start < end + EPS) end = clipEnd(c)
    return end
}
export const trackEnd = (p, trackId) => clipsOn(p, trackId).reduce((m, c) => Math.max(m, clipEnd(c)), 0)

// 格式化时间：00:01:23.12（帧）
export function fmtTC(t, fps = 30) {
    if (!Number.isFinite(t) || t < 0) t = 0
    const f = Math.floor(t * fps + 1e-6)
    const fr = f % fps, s = Math.floor(f / fps)
    const p2 = v => String(v).padStart(2, '0')
    return `${p2(Math.floor(s / 3600))}:${p2(Math.floor(s / 60) % 60)}:${p2(s % 60)}:${p2(fr)}`
}
export function fmtDur(t) {
    if (!Number.isFinite(t)) return '—'
    const s = Math.max(0, t)
    const m = Math.floor(s / 60)
    return m ? `${m}:${(s % 60).toFixed(1).padStart(4, '0')}` : `${s.toFixed(1)} 秒`
}
