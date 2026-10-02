// 音符编辑命令：剪贴板、删除、移调、量化、力度、全选等
import { toast, formDialog, clamp } from '../../core/dom.js'
import { uid } from '../../core/dom.js'

// 剪贴板在所有 MIDI 编辑器之间共享
let clipboard = null

export const SNAPS = [
    [0, '不吸附'], [1, '1 小节'], [1 / 2, '1/2'], [1 / 4, '1/4'], [1 / 8, '1/8'], [1 / 16, '1/16'], [1 / 32, '1/32'],
    [1 / 6, '1/4 三连音'], [1 / 12, '1/8 三连音'], [1 / 24, '1/16 三连音'],
]

export function installOps(Ed) {
    const P = Ed.prototype

    P.selNotes = function () { return this.track ? this.track.notes.filter(n => this.sel.has(n.id)) : [] }
    // 未选中时作用于整条轨道
    P.targetNotes = function () { const s = this.selNotes(); return s.length ? s : this.track?.notes ?? [] }
    P.sortNotes = function () { this.track?.notes.sort((a, b) => a.tick - b.tick || a.pitch - b.pitch) }

    P.selectAll = function () {
        if (!this.track) return
        this.sel = new Set(this.track.notes.map(n => n.id))
        this.afterSel()
    }
    P.selectNone = function () { this.sel = new Set(); this.afterSel() }

    P.copySel = function (cut = false) {
        const ns = this.selNotes()
        if (!ns.length) return false
        const t0 = Math.min(...ns.map(n => n.tick))
        clipboard = { ppq: this.song.ppq, notes: ns.map(n => ({ tick: n.tick - t0, dur: n.dur, pitch: n.pitch, vel: n.vel })), span: Math.max(...ns.map(n => n.tick + n.dur)) - t0 }
        if (cut) this.deleteSel('剪切')
        return true
    }
    P.paste = function (at = this.cursor) {
        if (!clipboard || !this.track) { toast('剪贴板中没有音符'); return }
        const k = this.song.ppq / clipboard.ppq
        const ns = clipboard.notes.map(n => ({ id: uid('n'), tick: Math.round(at + n.tick * k), dur: Math.max(1, Math.round(n.dur * k)), pitch: n.pitch, vel: n.vel }))
        this.track.notes.push(...ns)
        this.sortNotes()
        this.sel = new Set(ns.map(n => n.id))
        // 光标移到粘贴内容之后，便于连续粘贴
        this.cursor = Math.round(at + clipboard.span * k)
        this.commit('粘贴')
        this.afterEdit()
    }
    P.duplicateSel = function () {
        const ns = this.selNotes()
        if (!ns.length) return
        const t0 = Math.min(...ns.map(n => n.tick)), t1 = Math.max(...ns.map(n => n.tick + n.dur))
        // 以吸附网格对齐的长度复制到其后
        const s = this.snapTicks() || 1
        const span = Math.max(s, Math.ceil((t1 - t0) / s) * s)
        const copies = ns.map(n => ({ ...n, id: uid('n'), tick: n.tick + span }))
        this.track.notes.push(...copies)
        this.sortNotes()
        this.sel = new Set(copies.map(n => n.id))
        this.commit('复制音符')
        this.afterEdit()
    }
    P.deleteSel = function (label = '删除音符') {
        if (!this.sel.size || !this.track) return
        this.track.notes = this.track.notes.filter(n => !this.sel.has(n.id))
        this.sel = new Set()
        this.commit(label)
        this.afterEdit()
    }
    P.transpose = function (d) {
        const ns = this.selNotes()
        if (!ns.length) return
        const lo = Math.min(...ns.map(n => n.pitch)), hi = Math.max(...ns.map(n => n.pitch))
        d = clamp(d, -lo, 127 - hi)
        if (!d) return
        for (const n of ns) n.pitch += d
        this.commit('移调', { merge: 'transpose' })
        this.afterEdit()
        if (ns.length <= 4) for (const n of ns) this.previewNote(n)
    }
    P.nudge = function (dir) {
        const ns = this.selNotes()
        if (!ns.length) return
        const s = this.snapTicks() || this.song.ppq / 4
        const min = Math.min(...ns.map(n => n.tick))
        const d = Math.max(-min, dir * s)
        if (!d) return
        for (const n of ns) n.tick += d
        this.sortNotes()
        this.commit('移动音符', { merge: 'nudge' })
        this.afterEdit()
    }
    P.setVelocity = function (v, merge) {
        const ns = this.targetNotes()
        if (!ns.length) return
        for (const n of ns) n.vel = clamp(Math.round(v), 1, 127)
        this.commit('力度', merge ? { merge: 'vel' } : undefined)
        this.afterEdit()
    }
    P.scaleLength = function (k) {
        const ns = this.targetNotes()
        for (const n of ns) n.dur = Math.max(10, Math.round(n.dur * k))
        this.commit('时值')
        this.afterEdit()
    }
    // 连奏：每个音符延长到下一个音符开始
    P.legato = function () {
        const ns = [...this.targetNotes()].sort((a, b) => a.tick - b.tick)
        const starts = [...new Set(ns.map(n => n.tick))].sort((a, b) => a - b)
        for (const n of ns) {
            const next = starts.find(t => t > n.tick)
            if (next != null) n.dur = next - n.tick
        }
        this.commit('连奏')
        this.afterEdit()
    }

    P.quantizeDialog = async function () {
        if (!this.track?.notes.length) { toast('当前轨道没有音符'); return }
        const pref = this.qPref ??= { grid: 1 / 16, triplet: false, strength: 100, ends: false }
        const base = [[1 / 4, '1/4'], [1 / 8, '1/8'], [1 / 16, '1/16'], [1 / 32, '1/32']]
        const r = await formDialog({
            title: this.sel.size ? `量化（${this.sel.size} 个选中音符）` : '量化（整条轨道）',
            fields: [
                { key: 'grid', label: '网格', type: 'select', value: pref.grid, options: base },
                { key: 'triplet', label: '三连音', type: 'check', value: pref.triplet },
                { key: 'strength', label: '强度', type: 'range', min: 10, max: 100, step: 5, value: pref.strength, suffix: '%' },
                { key: 'ends', label: '同时量化结尾', type: 'check', value: pref.ends },
            ],
            okText: '量化',
        })
        if (!r) return
        Object.assign(pref, r)
        this.quantize(r)
    }
    P.quantize = function ({ grid = 1 / 16, triplet = false, strength = 100, ends = false } = {}) {
        const step = this.song.ppq * 4 * grid * (triplet ? 2 / 3 : 1)
        const k = strength / 100
        const ns = this.targetNotes()
        for (const n of ns) {
            const q = Math.round(n.tick / step) * step
            const end = n.tick + n.dur
            n.tick = Math.max(0, Math.round(n.tick + (q - n.tick) * k))
            // 不量化结尾时保持原时值
            if (ends) {
                const qe = Math.max(q + step, Math.round(end / step) * step)
                n.dur = Math.max(10, Math.round(end + (qe - end) * k) - n.tick)
            }
        }
        this.sortNotes()
        this.commit('量化')
        this.afterEdit()
        toast(`已量化 ${ns.length} 个音符`, 'success')
    }

    P.humanize = function () {
        const ns = this.targetNotes()
        const j = this.song.ppq / 48
        for (const n of ns) {
            n.tick = Math.max(0, Math.round(n.tick + (Math.random() * 2 - 1) * j))
            n.vel = clamp(Math.round(n.vel + (Math.random() * 2 - 1) * 10), 1, 127)
        }
        this.sortNotes()
        this.commit('人性化')
        this.afterEdit()
    }

    P.velocityDialog = async function () {
        const ns = this.targetNotes()
        if (!ns.length) return
        const avg = Math.round(ns.reduce((s, n) => s + n.vel, 0) / ns.length)
        const r = await formDialog({
            title: '设置力度',
            fields: [
                { key: 'mode', label: '方式', type: 'select', value: 'set', options: [['set', '设为固定值'], ['scale', '按比例缩放'], ['ramp', '渐强 / 渐弱']] },
                { key: 'v', label: '力度 / 起始', type: 'range', min: 1, max: 127, value: avg },
                { key: 'v2', label: '比例 / 结束', type: 'range', min: 1, max: 200, value: 100 },
                { type: 'note', label: '“按比例缩放”使用第二个值作为百分比；“渐强 / 渐弱”从起始值线性过渡到结束值（上限 127）。' },
            ],
        })
        if (!r) return
        const sorted = [...ns].sort((a, b) => a.tick - b.tick)
        const t0 = sorted[0].tick, t1 = sorted.at(-1).tick || 1
        for (const n of sorted) {
            if (r.mode === 'set') n.vel = r.v
            else if (r.mode === 'scale') n.vel = n.vel * r.v2 / 100
            else n.vel = r.v + (Math.min(127, r.v2) - r.v) * (t1 > t0 ? (n.tick - t0) / (t1 - t0) : 0)
            n.vel = clamp(Math.round(n.vel), 1, 127)
        }
        this.commit('设置力度')
        this.afterEdit()
    }

    P.noteMenuItems = function () {
        const has = () => this.sel.size > 0
        return [
            { label: '剪切', icon: 'scissors', key: 'Ctrl+X', disabled: () => !has(), run: () => this.copySel(true) },
            { label: '复制', icon: 'copy', key: 'Ctrl+C', disabled: () => !has(), run: () => this.copySel() },
            { label: '粘贴到光标处', icon: 'clipboard-paste', key: 'Ctrl+V', disabled: () => !clipboard, run: () => this.paste() },
            { label: '重复', icon: 'copy-plus', key: 'Ctrl+D', disabled: () => !has(), run: () => this.duplicateSel() },
            { label: '删除', icon: 'trash-2', key: 'Delete', disabled: () => !has(), run: () => this.deleteSel() },
            '-',
            { label: '量化…', icon: 'grid-3x3', key: 'Q', run: () => this.quantizeDialog() },
            { label: '设置力度…', icon: 'bar-chart-3', run: () => this.velocityDialog() },
            { label: '升高八度', icon: 'arrow-up', key: 'Shift+ArrowUp', disabled: () => !has(), run: () => this.transpose(12) },
            { label: '降低八度', icon: 'arrow-down', key: 'Shift+ArrowDown', disabled: () => !has(), run: () => this.transpose(-12) },
            '-',
            { label: '全选', key: 'Ctrl+A', run: () => this.selectAll() },
        ]
    }
    P.hasClipboard = () => !!clipboard
}
