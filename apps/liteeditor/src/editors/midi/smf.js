// 标准 MIDI 文件（SMF）读写，转换为便于编辑的音符模型
// 模型：{ ppq, tempos: [{ tick, bpm }], timeSig: [{ tick, num, den }], markers: [{ tick, text }], tracks: [track] }
// track: { id, name, channel, program, volume, pan, mute, solo, color, notes: [{ id, tick, dur, pitch, vel }], cc: [{ tick, ctrl, value }], pitchBend: [{ tick, value }] }
import { uid } from '../../core/dom.js'

export const TRACK_COLORS = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#a855f7', '#06b6d4', '#ec4899', '#84cc16', '#f97316', '#6366f1', '#14b8a6', '#e11d48', '#0ea5e9', '#d946ef', '#65a30d', '#fb7185']
export const DRUM_CH = 9

export function emptySong() {
    return {
        ppq: 480, tempos: [{ tick: 0, bpm: 120 }], timeSig: [{ tick: 0, num: 4, den: 4 }],
        tracks: [newTrack(0, '钢琴', 0, 0)], markers: [],
    }
}
// 第 i 条轨道的默认通道：跳过鼓通道 10
export const defaultChannel = i => (i < DRUM_CH ? i : i + 1) % 16
export function newTrack(i, name, channel = defaultChannel(i), program = 0) {
    return { id: uid('T'), name, channel, program, volume: 100, pan: 64, mute: false, solo: false, color: TRACK_COLORS[i % TRACK_COLORS.length], notes: [], cc: [], pitchBend: [] }
}
export const isDrum = t => t.channel === DRUM_CH

// ---------- 读取 ----------
export function parseMIDI(bytes) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
    let p = 0
    const str = n => { let s = ''; for (let i = 0; i < n; i++) s += String.fromCharCode(u8[p + i]); p += n; return s }
    const u32 = () => { const v = (u8[p] << 24 | u8[p + 1] << 16 | u8[p + 2] << 8 | u8[p + 3]) >>> 0; p += 4; return v }
    const u16 = () => { const v = u8[p] << 8 | u8[p + 1]; p += 2; return v }
    const vlq = () => { let v = 0, b, n = 0; do { b = u8[p++]; v = v * 128 + (b & 0x7f) } while (b & 0x80 && p < u8.length && ++n < 4); return v }
    if (u8.length < 14) throw new Error('不是有效的 MIDI 文件')
    // RIFF RMID 包装
    if (str(4) === 'RIFF') {
        p = 12
        while (p + 8 <= u8.length) {
            const id = str(4), len = (u8[p] | u8[p + 1] << 8 | u8[p + 2] << 16 | u8[p + 3] << 24) >>> 0
            p += 4
            if (id === 'data') break
            p += len + (len & 1)
        }
    } else p = 0
    // 容忍文件头前的垃圾数据
    const at = findMThd(u8, p)
    if (at < 0) throw new Error('不是有效的 MIDI 文件')
    p = at + 4
    const hlen = u32()
    const hstart = p
    const format = u16(), ntrk = u16(), div = u16()
    p = hstart + hlen
    const ppq = div & 0x8000 || !div ? 480 : div
    const song = { ppq, tempos: [], timeSig: [], tracks: [], markers: [], format }
    const text = arr => { try { return new TextDecoder('utf-8', { fatal: true }).decode(arr) } catch { return new TextDecoder('gbk').decode(arr) } }
    // 按“文件轨道 × 通道”拆分成编辑轨道；只有含音符的分组才成为轨道
    const buckets = new Map()
    const bucket = (ti, ch) => {
        const k = ti * 16 + ch
        let b = buckets.get(k)
        if (!b) buckets.set(k, b = { k, ti, ch, notes: [], cc: [], pitchBend: [], program: null, volume: null, pan: null, name: '' })
        return b
    }
    // 通道级的初始状态（例如格式 1 中写在第 0 轨的音色 / 音量）
    const chanState = Array.from({ length: 16 }, () => ({ program: null, volume: null, pan: null }))
    const trackNames = []
    for (let ti = 0; ti < ntrk && p + 8 <= u8.length; ti++) {
        const id = str(4)
        const len = u32()
        if (id !== 'MTrk') { p += len; ti--; continue }
        const end = Math.min(u8.length, p + len)
        let tick = 0, run = 0, trackName = ''
        const open = new Map() // ch*128+pitch -> [note...]
        while (p < end) {
            tick += vlq()
            if (p >= end) break
            let status = u8[p]
            if (status & 0x80) p++
            else if (run) status = run      // 运行状态：沿用上一个通道消息的状态字节
            else { p++; continue }         // 无法解析的数据字节
            if (status === 0xff) {
                const type = u8[p++], l = vlq(), data = u8.subarray(p, p + l)
                p += l
                if (type === 0x51 && l >= 3) song.tempos.push({ tick, bpm: Math.round(6e10 / Math.max(1, data[0] << 16 | data[1] << 8 | data[2])) / 1000 })
                else if (type === 0x58 && l >= 2) song.timeSig.push({ tick, num: data[0] || 4, den: 2 ** Math.min(6, data[1]) })
                else if (type === 0x03 && !trackName) trackName = text(data).replace(/\0/g, '').trim()
                else if (type === 0x06) song.markers.push({ tick, text: text(data) })
                else if (type === 0x2f) break
                continue   // 元事件不改变运行状态
            }
            if (status === 0xf0 || status === 0xf7) { const l = vlq(); p += l; run = 0; continue }
            if (status > 0xf0) { run = 0; continue } // 其他系统消息（文件中不应出现）
            run = status
            const hi = status & 0xf0, ch = status & 0x0f
            const d1 = u8[p++] & 0x7f, d2 = hi === 0xc0 || hi === 0xd0 ? 0 : u8[p++] & 0x7f
            if (hi === 0x90 && d2 > 0) {
                const b = bucket(ti, ch)
                const n = { id: uid('n'), tick, dur: 0, pitch: d1, vel: d2 }
                b.notes.push(n)
                const k = ch * 128 + d1
                if (!open.has(k)) open.set(k, [])
                open.get(k).push(n)
            } else if (hi === 0x80 || hi === 0x90) {
                const n = open.get(ch * 128 + d1)?.shift()
                if (n) n.dur = Math.max(1, tick - n.tick)
            } else if (hi === 0xc0) {
                const b = bucket(ti, ch)
                // 只取第一个音色（模型每轨一个音色）
                b.program ??= d1
                chanState[ch].program ??= d1
            } else if (hi === 0xb0) {
                const b = bucket(ti, ch)
                if (d1 === 7 && b.volume == null && !b.notes.length) { b.volume = d2; chanState[ch].volume ??= d2 }
                else if (d1 === 10 && b.pan == null && !b.notes.length) { b.pan = d2; chanState[ch].pan ??= d2 }
                else if (d1 !== 121 && d1 < 120) b.cc.push({ tick, ctrl: d1, value: d2 })
            } else if (hi === 0xe0) {
                bucket(ti, ch).pitchBend.push({ tick, value: (d2 << 7 | d1) - 8192 })
            }
        }
        // 未结束的音符：延续到轨道末尾
        for (const q of open.values()) for (const n of q) n.dur = Math.max(1, tick - n.tick)
        trackNames[ti] = trackName
        p = end
    }
    const withNotes = [...buckets.values()].filter(b => b.notes.length).sort((a, b) => a.k - b.k)
    const perTrack = new Map()
    for (const b of withNotes) perTrack.set(b.ti, (perTrack.get(b.ti) ?? 0) + 1)
    withNotes.forEach((b, i) => {
        const cs = chanState[b.ch]
        let name = trackNames[b.ti] || (b.ch === DRUM_CH ? '鼓组' : '')
        if (name && perTrack.get(b.ti) > 1) name += ` (通道 ${b.ch + 1})`
        if (!name) name = `轨道 ${i + 1}`
        const t = newTrack(i, name, b.ch, b.program ?? cs.program ?? 0)
        t.volume = b.volume ?? cs.volume ?? 100
        t.pan = b.pan ?? cs.pan ?? 64
        t.notes = b.notes.sort((x, y) => x.tick - y.tick || x.pitch - y.pitch)
        t.cc = b.cc
        t.pitchBend = b.pitchBend
        song.tracks.push(t)
    })
    song.tempos.sort((a, b) => a.tick - b.tick)
    song.timeSig.sort((a, b) => a.tick - b.tick)
    song.tempos = dedupe(song.tempos)
    song.timeSig = dedupe(song.timeSig)
    if (!song.tempos.length || song.tempos[0].tick > 0) song.tempos.unshift({ tick: 0, bpm: song.tempos[0]?.bpm ?? 120 })
    if (!song.timeSig.length || song.timeSig[0].tick > 0) song.timeSig.unshift({ tick: 0, num: 4, den: 4 })
    // 已被播放循环使用的标记不需要保留
    song.markers = song.markers.filter(m => !/^loop(start|end)$/i.test(m.text.trim()))
    if (!song.tracks.length) song.tracks.push(newTrack(0, '钢琴'))
    delete song.format
    return song
}
// 同一 tick 上的多个事件只保留最后一个
function dedupe(list) {
    const out = []
    for (const e of list) { if (out.length && out.at(-1).tick === e.tick) out[out.length - 1] = e; else out.push(e) }
    return out
}
function findMThd(u8, from) {
    for (let i = from; i + 4 <= Math.min(u8.length, from + 4096); i++) {
        if (u8[i] === 0x4d && u8[i + 1] === 0x54 && u8[i + 2] === 0x68 && u8[i + 3] === 0x64) return i
    }
    return -1
}

// ---------- 写出（格式 1：第 0 轨为速度 / 拍号，之后每条编辑轨道一条 MTrk） ----------
// opts.extraMarkers: 额外的标记（例如播放循环点）；opts.extraTracks: 额外轨道（节拍器）；opts.silent: 不写音符的轨道集合；opts.padTo: 延长到该 tick
export function writeMIDI(song, opts = {}) {
    const chunks = []
    const enc = new TextEncoder()
    const meta = (type, data) => [0xff, type, ...vlqBytes(data.length), ...data]
    const t0 = [{ tick: 0, order: 0, bytes: meta(0x03, [...enc.encode(opts.title ?? '')]) }]
    for (const t of song.tempos) { const us = Math.round(60000000 / t.bpm); t0.push({ tick: t.tick, order: 0, bytes: meta(0x51, [us >> 16 & 255, us >> 8 & 255, us & 255]) }) }
    for (const s of song.timeSig) t0.push({ tick: s.tick, order: 0, bytes: meta(0x58, [s.num, Math.round(Math.log2(s.den)), 24, 8]) })
    for (const m of [...(song.markers ?? []), ...(opts.extraMarkers ?? [])]) t0.push({ tick: m.tick, order: 1, bytes: meta(0x06, [...enc.encode(m.text)]) })
    // 用一个无作用的控制器事件把乐曲延长到指定位置（播放器以最后一个通道事件计算时长）
    if (opts.padTo) t0.push({ tick: opts.padTo, order: 9, bytes: [0xb0, 110, 0] })
    chunks.push(t0)
    for (const tr of [...song.tracks, ...(opts.extraTracks ?? [])]) {
        const ch = tr.channel & 15
        const ev = [
            { tick: 0, order: 0, bytes: meta(0x03, [...enc.encode(tr.name)]) },
            { tick: 0, order: 2, bytes: [0xc0 | ch, tr.program & 127] },
            { tick: 0, order: 3, bytes: [0xb0 | ch, 7, tr.volume & 127] },
            { tick: 0, order: 3, bytes: [0xb0 | ch, 10, tr.pan & 127] },
        ]
        // 音色库选择（CC0 / CC32）必须位于音色切换之前
        for (const c of tr.cc) ev.push({ tick: c.tick, order: c.ctrl === 0 || c.ctrl === 32 ? 1 : 3, bytes: [0xb0 | ch, c.ctrl & 127, c.value & 127] })
        for (const b of tr.pitchBend) { const v = Math.max(0, Math.min(16383, b.value + 8192)); ev.push({ tick: b.tick, order: 3, bytes: [0xe0 | ch, v & 127, v >> 7] }) }
        if (!opts.silent?.has(tr)) {
            for (const n of tr.notes) {
                ev.push({ tick: n.tick, order: 5, bytes: [0x90 | ch, n.pitch & 127, Math.max(1, Math.min(127, Math.round(n.vel)))] })
                ev.push({ tick: n.tick + Math.max(1, n.dur), order: 4, bytes: [0x80 | ch, n.pitch & 127, 0] })
            }
        }
        chunks.push(ev)
    }
    const parts = [[0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, (chunks.length >> 8) & 255, chunks.length & 255, (song.ppq >> 8) & 127, song.ppq & 255]]
    for (const c of chunks) {
        const data = encodeTrack(c)
        parts.push([0x4d, 0x54, 0x72, 0x6b, (data.length >>> 24) & 255, (data.length >> 16) & 255, (data.length >> 8) & 255, data.length & 255], data)
    }
    const total = parts.reduce((s, a) => s + a.length, 0)
    const out = new Uint8Array(total)
    let o = 0
    for (const a of parts) { out.set(a, o); o += a.length }
    return out
}
function encodeTrack(events) {
    for (const e of events) e.tick = Math.max(0, Math.round(e.tick))
    events.sort((a, b) => a.tick - b.tick || a.order - b.order)
    const out = []
    let last = 0
    for (const e of events) {
        for (const b of vlqBytes(e.tick - last)) out.push(b)
        last = e.tick
        for (const b of e.bytes) out.push(b)
    }
    out.push(0, 0xff, 0x2f, 0x00)
    return out
}
function vlqBytes(v) { const b = [v & 0x7f]; while ((v = Math.floor(v / 128))) b.unshift((v & 0x7f) | 0x80); return b }

// ---------- 时间换算 ----------
export function tickToSec(song, tick) {
    const ts = song.tempos
    let sec = 0
    for (let i = 0; i < ts.length; i++) {
        const t = ts[i], next = ts[i + 1]
        const end = next ? Math.min(tick, next.tick) : tick
        if (end <= t.tick) break
        sec += (end - t.tick) / song.ppq * 60 / t.bpm
        if (!next || tick <= next.tick) break
    }
    return sec
}
export function secToTick(song, sec) {
    const ts = song.tempos
    let acc = 0
    for (let i = 0; i < ts.length; i++) {
        const t = ts[i], next = ts[i + 1]
        const span = next ? (next.tick - t.tick) / song.ppq * 60 / t.bpm : Infinity
        if (sec <= acc + span) return t.tick + (sec - acc) * t.bpm / 60 * song.ppq
        acc += span
    }
    return 0
}
export const tempoAt = (song, tick) => { let b = song.tempos[0]?.bpm ?? 120; for (const t of song.tempos) { if (t.tick > tick) break; b = t.bpm } return b }
export const sigAt = (song, tick) => { let s = song.timeSig[0] ?? { tick: 0, num: 4, den: 4 }; for (const t of song.timeSig) { if (t.tick > tick) break; s = t } return s }
export function lastNoteTick(song) {
    let m = 0
    for (const t of song.tracks) for (const n of t.notes) if (n.tick + n.dur > m) m = n.tick + n.dur
    return m
}
export const songEndTick = song => Math.max(song.ppq * 4, lastNoteTick(song))
export function barTicks(song, tick = 0) {
    const ts = sigAt(song, tick)
    return song.ppq * 4 / ts.den * ts.num
}
// 遍历 [t0, t1) 范围内的小节：fn({ tick, bar, num, den, beat })，bar 从 1 开始
export function forEachBar(song, t0, t1, fn) {
    const sigs = song.timeSig.length ? song.timeSig : [{ tick: 0, num: 4, den: 4 }]
    let bar = 1
    for (let i = 0; i < sigs.length; i++) {
        const s = sigs[i], next = sigs[i + 1]?.tick ?? Infinity
        const beat = song.ppq * 4 / s.den, len = beat * s.num
        let tick = s.tick
        if (next !== Infinity) {
            const nbars = Math.ceil((next - s.tick) / len)
            if (next <= t0) { bar += nbars; continue }
        }
        if (tick < t0) { const skip = Math.floor((t0 - tick) / len); tick += skip * len; bar += skip }
        while (tick < next && tick < t1) {
            if (fn({ tick, bar, num: s.num, den: s.den, beat, len }) === false) return
            tick += len; bar++
        }
        if (tick >= t1) return
    }
}
// tick -> { bar, beat, sub }（均从 1 / 0 开始）
export function tickToBBT(song, tick) {
    let r = { bar: 1, beat: 1, sub: 0 }
    forEachBar(song, 0, tick + 1, b => {
        if (b.tick > tick) return false
        const off = tick - b.tick
        r = { bar: b.bar, beat: Math.floor(off / b.beat) + 1, sub: Math.round(off % b.beat) }
    })
    return r
}

// 音名
const NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
export const noteName = p => NAMES[p % 12] + (Math.floor(p / 12) - 1)
export const isBlack = p => [1, 3, 6, 8, 10].includes(p % 12)

// General MIDI 音色表（中文）
export const GM_PROGRAMS = [
    '大钢琴', '明亮钢琴', '电钢琴', '酒吧钢琴', '电钢琴 1', '电钢琴 2', '羽管键琴', '击弦古钢琴',
    '钢片琴', '钟琴', '八音盒', '颤音琴', '马林巴', '木琴', '管钟', '扬琴',
    '击杆风琴', '打击风琴', '摇滚风琴', '教堂管风琴', '簧风琴', '手风琴', '口琴', '探戈手风琴',
    '尼龙弦吉他', '钢弦吉他', '爵士电吉他', '清音电吉他', '闷音电吉他', '过载吉他', '失真吉他', '吉他泛音',
    '原声贝斯', '指弹电贝斯', '拨片电贝斯', '无品贝斯', '击弦贝斯 1', '击弦贝斯 2', '合成贝斯 1', '合成贝斯 2',
    '小提琴', '中提琴', '大提琴', '低音提琴', '颤弓弦乐', '拨奏弦乐', '竖琴', '定音鼓',
    '弦乐合奏 1', '弦乐合奏 2', '合成弦乐 1', '合成弦乐 2', '人声合唱 啊', '人声 哦', '合成人声', '管弦乐打击',
    '小号', '长号', '大号', '弱音小号', '圆号', '铜管组', '合成铜管 1', '合成铜管 2',
    '高音萨克斯', '中音萨克斯', '次中音萨克斯', '上低音萨克斯', '双簧管', '英国管', '大管', '单簧管',
    '短笛', '长笛', '竖笛', '排箫', '吹瓶', '尺八', '口哨', '陶笛',
    '方波主音', '锯齿波主音', '汽笛风琴', '吹管主音', '电荷主音', '人声主音', '五度主音', '贝斯与主音',
    '新世纪铺底', '温暖铺底', '复音铺底', '合唱铺底', '弓弦铺底', '金属铺底', '光晕铺底', '扫频铺底',
    '雨声', '音轨', '晶体', '大气', '明亮', '鬼魅', '回声', '科幻',
    '西塔琴', '班卓琴', '三味线', '筝', '卡林巴', '风笛', '古提琴', '唢呐',
    '叮当铃', '阿哥哥鼓', '钢鼓', '木鱼', '太鼓', '旋律嗵鼓', '合成鼓', '反向镲',
    '吉他擦弦', '呼吸声', '海浪', '鸟鸣', '电话铃', '直升机', '掌声', '枪声',
]
export const GM_FAMILIES = ['钢琴', '半音打击乐', '风琴', '吉他', '贝斯', '弦乐', '合奏', '铜管', '簧管', '笛', '合成主音', '合成铺底', '合成效果', '民族乐器', '打击乐', '音效']
// GS 鼓组（鼓通道上的音色号）
export const DRUM_KITS = { 0: '标准鼓组', 8: '房间鼓组', 16: '力量鼓组', 24: '电子鼓组', 25: 'TR-808 鼓组', 32: '爵士鼓组', 40: '刷子鼓组', 48: '管弦乐鼓组', 56: '音效组' }
export const programName = t => isDrum(t) ? (DRUM_KITS[t.program] ?? `鼓组 ${t.program + 1}`) : GM_PROGRAMS[t.program] ?? '—'
export const DRUMS = { 27: '高 Q', 28: '拍击', 29: '刮擦推', 30: '刮擦拉', 31: '鼓棒', 32: '方形节拍器', 33: '节拍器', 34: '节拍器铃', 35: '大鼓 2', 36: '大鼓', 37: '鼓边', 38: '军鼓', 39: '拍手', 40: '电军鼓', 41: '低地嗵', 42: '闭镲', 43: '高地嗵', 44: '踩镲', 45: '低嗵', 46: '开镲', 47: '中低嗵', 48: '中高嗵', 49: '碎音镲', 50: '高嗵', 51: '叮叮镲', 52: '中国镲', 53: '镲帽', 54: '铃鼓', 55: '水镲', 56: '牛铃', 57: '碎音镲 2', 58: '颤音器', 59: '叮叮镲 2', 60: '高邦戈', 61: '低邦戈', 62: '康加（闷）', 63: '高康加', 64: '低康加', 65: '高定音鼓', 66: '低定音鼓', 67: '高阿哥哥', 68: '低阿哥哥', 69: '沙锤', 70: '沙球', 71: '短口哨', 72: '长口哨', 73: '短刮瓜', 74: '长刮瓜', 75: '响棒', 76: '高木鱼', 77: '低木鱼', 78: '闷鸣筒', 79: '开鸣筒', 80: '闷三角铁', 81: '开三角铁' }
