// 示例乐曲与模板
import { uid } from '../../core/dom.js'
import { newTrack, DRUM_CH } from './smf.js'

export const SAMPLES = {
    demo: { name: '示例乐曲', desc: '旋律 · 和弦 · 贝斯 · 鼓，8 小节' },
    band: { name: '乐队编制', desc: '钢琴 · 吉他 · 贝斯 · 弦乐 · 鼓' },
}

const PPQ = 480
// [起始拍, 时值（拍）, 音高, 力度?]
const put = (t, list, vel = 96) => { for (const [b, d, p, v] of list) t.notes.push({ id: uid('n'), tick: Math.round(b * PPQ), dur: Math.round(d * PPQ), pitch: p, vel: v ?? vel }) }

// 鼓：每小节的节奏型（36 大鼓、38 军鼓、42 闭镲、46 开镲、49 碎音镲）
function drumBars(t, bars, { from = 0, crashAt = [0], fill = true } = {}) {
    for (let bar = from; bar < from + bars; bar++) {
        const o = bar * 4
        const last = fill && bar === from + bars - 1
        const n = []
        n.push([o, .25, 36, 110], [o + 1, .25, 38, 100], [o + 2, .25, 36, 104], [o + 2.5, .25, 36, 84], [o + 3, .25, 38, 104])
        for (let i = 0; i < 8; i++) if (!(last && i >= 6)) n.push([o + i / 2, .25, 42, i % 2 ? 62 : 86])
        if (last) n.push([o + 3.25, .25, 38, 76], [o + 3.5, .25, 45, 96], [o + 3.75, .25, 41, 104])
        if (crashAt.includes(bar)) n.push([o, 1, 49, 100])
        else if (bar % 2 === 1 && !last) n.push([o + 3.5, .5, 46, 70])
        put(t, n)
    }
}

function demo() {
    const song = { ppq: PPQ, title: '示例乐曲', tempos: [{ tick: 0, bpm: 108 }], timeSig: [{ tick: 0, num: 4, den: 4 }], markers: [], tracks: [] }
    const mel = newTrack(0, '旋律', 0, 0)
    mel.volume = 108
    put(mel, [
        [0, 1, 76], [1, 1, 79], [2, 1.5, 84], [3.5, .5, 83],
        [4, 1, 81], [5, 1, 76], [6, 1, 81], [7, 1, 84],
        [8, 1.5, 81], [9.5, .5, 79], [10, 1, 77], [11, 1, 81],
        [12, 2, 79], [14, 1, 74], [15, 1, 71],
        [16, .5, 76], [16.5, .5, 77], [17, 1, 79], [18, 2, 84, 104],
        [20, 1, 84], [21, .5, 83], [21.5, .5, 81], [22, 2, 76],
        [24, 1, 77], [25, 1, 81], [26, 1, 84], [27, 1, 81],
        [28, 1, 79], [29, .5, 77], [29.5, .5, 74], [30, 2, 72, 90],
    ], 92)
    const pad = newTrack(1, '和弦', 1, 48)
    pad.volume = 78
    const chords = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
    for (let bar = 0; bar < 8; bar++) put(pad, chords[bar % 4].map(p => [bar * 4, 4, p]), 70)
    const bass = newTrack(2, '贝斯', 2, 33)
    bass.volume = 104
    const roots = [36, 45, 41, 43]
    for (let bar = 0; bar < 8; bar++) {
        const r = roots[bar % 4], o = bar * 4
        put(bass, [[o, 1.5, r], [o + 1.5, .5, r], [o + 2, 1, r + 7], [o + 3, 1, r + 12, 80]], 100)
    }
    const drums = newTrack(3, '鼓组', DRUM_CH, 0)
    drums.volume = 96
    drumBars(drums, 8, { crashAt: [0, 4] })
    song.tracks.push(mel, pad, bass, drums)
    return song
}

function band() {
    const song = { ppq: PPQ, title: '乐队编制', tempos: [{ tick: 0, bpm: 100 }], timeSig: [{ tick: 0, num: 4, den: 4 }], markers: [], tracks: [] }
    const tracks = [
        newTrack(0, '钢琴', 0, 0),
        newTrack(1, '电吉他', 1, 27),
        newTrack(2, '贝斯', 2, 33),
        newTrack(3, '弦乐', 3, 48),
        newTrack(4, '鼓组', DRUM_CH, 0),
    ]
    tracks[1].pan = 44
    tracks[3].pan = 84
    tracks[3].volume = 80
    drumBars(tracks[4], 4, { crashAt: [0] })
    song.tracks.push(...tracks)
    return song
}

export function buildSample(id) {
    return id === 'band' ? band() : demo()
}
