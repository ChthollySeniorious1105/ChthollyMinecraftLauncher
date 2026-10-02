// 轨道列表 + 编排总览（所有轨道的迷你音符块）
import { h, fill, clamp, formDialog, confirmDialog } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu, openMenu } from '../../core/menu.js'
import { uid } from '../../core/dom.js'
import { newTrack, isDrum, DRUM_CH, GM_PROGRAMS, GM_FAMILIES, DRUM_KITS, TRACK_COLORS, programName, forEachBar, defaultChannel } from './smf.js'

export const ROW_H = 40

export function installTracks(Ed) {
    const P = Ed.prototype

    P.buildArrange = function () {
        this.trackList = h('div.mi-tracklist')
        this.ov = { c: h('canvas.mi-ov'), w: 1, h: 1 }
        this.ov.g = this.ov.c.getContext('2d')
        this.ovWrap = h('div.mi-ov-wrap', this.ov.c)
        const head = h('div.mi-arr-head',
            h('span.mi-arr-title', icon('list-music', 14), '轨道'),
            h('button.icon-btn', { title: '添加轨道', onclick: e => openMenu(this.addTrackItems(), { anchor: e.currentTarget }) }, icon('plus', 15)))
        this.arrLeft = h('div.mi-arr-left', head, this.trackList)
        this.arrEl = h('div.mi-arrange', this.arrLeft, this.ovWrap)
        // 轨道列表与总览同步垂直滚动
        this.listen(this.trackList, 'scroll', () => { this.ovScroll = this.trackList.scrollTop; this.drawOverview() })
        this.listen(this.ov.c, 'wheel', e => { e.preventDefault(); this.trackList.scrollTop += e.deltaY }, { passive: false })
        const ro = new ResizeObserver(() => this.drawOverview())
        ro.observe(this.ovWrap)
        this.onDispose(() => ro.disconnect())
        this.bindOverview()
        return this.arrEl
    }

    // ---------- 轨道列表 ----------
    P.renderTracks = function () {
        const anySolo = this.song.tracks.some(t => t.solo)
        fill(this.trackList, this.song.tracks.map((t, i) => {
            const silent = t.mute || (anySolo && !t.solo)
            const row = h('div.mi-track' + (t === this.track ? '.active' : '') + (silent ? '.silent' : ''), {
                style: { '--c': t.color }, dataset: { id: t.id }, draggable: true,
                onclick: e => { if (!e.target.closest('button, input')) this.selectTrack(t.id) },
                ondblclick: e => { if (!e.target.closest('button, input')) this.trackDialog(t) },
                oncontextmenu: e => { this.selectTrack(t.id); contextMenu(e, this.trackMenuItems(t)) },
            },
            h('span.mi-track-color'),
            h('div.mi-track-main',
                h('div.mi-track-name', h('span.mi-track-idx', String(i + 1)), h('span.mi-track-label', t.name)),
                h('button.mi-track-prog', { title: '选择音色', onclick: e => this.programMenu(t, e.currentTarget) },
                    icon(isDrum(t) ? 'drum' : 'piano', 12), h('span', programName(t)), h('span.mi-track-ch', `通道 ${t.channel + 1}`))),
            h('div.mi-track-btns',
                h('button.mi-ms' + (t.mute ? '.on.m' : ''), { title: '静音', onclick: () => this.setTrackProp(t, { mute: !t.mute }, '静音') }, 'M'),
                h('button.mi-ms' + (t.solo ? '.on.s' : ''), { title: '独奏', onclick: () => this.setTrackProp(t, { solo: !t.solo }, '独奏') }, 'S')))
            // 拖动排序
            row.addEventListener('dragstart', e => { this.dragTrack = t.id; e.dataTransfer.effectAllowed = 'move' })
            row.addEventListener('dragover', e => {
                if (!this.dragTrack) return
                e.preventDefault()
                const r = row.getBoundingClientRect(), top = e.clientY < r.top + r.height / 2
                row.classList.toggle('drop-before', top); row.classList.toggle('drop-after', !top)
            })
            row.addEventListener('dragleave', () => row.classList.remove('drop-before', 'drop-after'))
            row.addEventListener('drop', e => {
                e.preventDefault()
                row.classList.remove('drop-before', 'drop-after')
                const from = this.song.tracks.findIndex(x => x.id === this.dragTrack)
                let to = this.song.tracks.indexOf(t) + (row.getBoundingClientRect().top + row.offsetHeight / 2 < e.clientY ? 1 : 0)
                this.dragTrack = null
                if (from < 0) return
                if (from < to) to--
                if (from === to) return
                const [m] = this.song.tracks.splice(from, 1)
                this.song.tracks.splice(to, 0, m)
                this.commit('移动轨道')
                this.afterEdit()
            })
            row.addEventListener('dragend', () => { this.dragTrack = null })
            return row
        }))
        this.trackList.scrollTop = this.ovScroll ?? 0
    }

    P.selectTrack = function (id) {
        if (this.trackId === id) return
        this.trackId = id
        this.sel = new Set()
        this.renderTracks()
        this.centerOnTrack()
        this.drawRoll()
        this.drawOverview()
        this.refreshPanels()
        this.updateStatus()
    }

    P.setTrackProp = function (t, props, label, merge) {
        Object.assign(t, props)
        this.commit(label, merge ? { merge: merge + t.id } : undefined)
        this.afterEdit()
        // 立即同步到合成器（播放中也生效）
        const ch = t.channel
        if ('program' in props) this.engine.program(ch, t.program)
        if ('volume' in props) this.engine.cc(ch, 7, t.volume)
        if ('pan' in props) this.engine.cc(ch, 10, t.pan)
    }

    P.addTrackItems = function () {
        return [
            { label: '乐器轨道', icon: 'piano', run: () => this.addTrack() },
            { label: '鼓组轨道', icon: 'drum', run: () => this.addTrack({ drum: true }) },
            '-',
            { header: '常用乐器' },
            ...[[0, '钢琴'], [24, '吉他'], [33, '贝斯'], [48, '弦乐'], [56, '小号'], [73, '长笛'], [80, '合成主音'], [88, '合成铺底']].map(([p, n]) => ({
                label: n, run: () => this.addTrack({ program: p, name: n }),
            })),
        ]
    }
    P.freeChannel = function () {
        const used = new Set(this.song.tracks.map(t => t.channel))
        for (let i = 0; i < 16; i++) { const c = defaultChannel(i); if (!used.has(c)) return c }
        return defaultChannel(this.song.tracks.length)
    }
    P.addTrack = function ({ drum = false, program = 0, name } = {}) {
        const i = this.song.tracks.length
        const used = new Set(this.song.tracks.map(t => t.color))
        const t = newTrack(i, name ?? (drum ? '鼓组' : `轨道 ${i + 1}`), drum ? DRUM_CH : this.freeChannel(), program)
        t.color = TRACK_COLORS.find(c => !used.has(c)) ?? t.color
        const at = this.song.tracks.indexOf(this.track) + 1 || i
        this.song.tracks.splice(at, 0, t)
        this.trackId = t.id
        this.sel = new Set()
        this.commit('添加轨道')
        this.afterEdit()
        this.centerOnTrack()
        this.drawRoll()
        return t
    }
    P.duplicateTrack = function (t = this.track) {
        if (!t) return
        const c = structuredClone(t)
        c.id = uid('T')
        c.name = t.name + ' 副本'
        c.notes = c.notes.map(n => ({ ...n, id: uid('n') }))
        this.song.tracks.splice(this.song.tracks.indexOf(t) + 1, 0, c)
        this.trackId = c.id
        this.sel = new Set()
        this.commit('复制轨道')
        this.afterEdit()
    }
    P.deleteTrack = async function (t = this.track) {
        if (!t) return
        if (t.notes.length && !await confirmDialog({ title: '删除轨道', message: `删除轨道“${t.name}”及其 ${t.notes.length} 个音符？`, okText: '删除', danger: true })) return
        const i = this.song.tracks.indexOf(t)
        this.song.tracks.splice(i, 1)
        if (!this.song.tracks.length) this.song.tracks.push(newTrack(0, '钢琴'))
        this.trackId = this.song.tracks[Math.min(i, this.song.tracks.length - 1)].id
        this.sel = new Set()
        this.commit('删除轨道')
        this.afterEdit()
    }
    P.trackMenuItems = function (t) {
        return [
            { label: '轨道属性…', icon: 'sliders-horizontal', run: () => this.trackDialog(t) },
            { label: '选择音色', icon: 'piano', submenu: () => this.programItems(t) },
            { label: '颜色', icon: 'palette', submenu: () => TRACK_COLORS.map(c => ({ label: c, swatch: c, checked: () => t.color === c, run: () => this.setTrackProp(t, { color: c }, '轨道颜色') })) },
            '-',
            { label: '静音', checked: () => t.mute, run: () => this.setTrackProp(t, { mute: !t.mute }, '静音') },
            { label: '独奏', checked: () => t.solo, run: () => this.setTrackProp(t, { solo: !t.solo }, '独奏') },
            '-',
            { label: '添加轨道', icon: 'plus', submenu: () => this.addTrackItems() },
            { label: '复制轨道', icon: 'copy-plus', run: () => this.duplicateTrack(t) },
            { label: '清空音符', icon: 'eraser', disabled: () => !t.notes.length, run: () => { t.notes = []; this.sel = new Set(); this.commit('清空音符'); this.afterEdit() } },
            { label: '删除轨道', icon: 'trash-2', danger: true, run: () => this.deleteTrack(t) },
        ]
    }

    // 音色选择：按 GM 家族分组；鼓通道显示鼓组
    P.programItems = function (t) {
        const pick = p => this.setTrackProp(t, { program: p }, '更换音色')
        if (isDrum(t)) {
            return [
                ...Object.entries(DRUM_KITS).map(([p, n]) => ({ label: n, checked: () => t.program === +p, run: () => pick(+p) })),
                '-',
                { label: '改为乐器轨道', icon: 'piano', run: () => this.setTrackProp(t, { channel: this.freeChannel(), program: 0 }, '更改通道') },
            ]
        }
        return [
            ...GM_FAMILIES.map((f, fi) => ({
                label: f, checked: () => Math.floor(t.program / 8) === fi,
                submenu: () => GM_PROGRAMS.slice(fi * 8, fi * 8 + 8).map((n, k) => ({ label: `${fi * 8 + k + 1}. ${n}`, checked: () => t.program === fi * 8 + k, run: () => pick(fi * 8 + k) })),
            })),
            '-',
            { label: '改为鼓组轨道（通道 10）', icon: 'drum', run: () => this.setTrackProp(t, { channel: DRUM_CH, program: 0 }, '更改通道') },
        ]
    }
    P.programMenu = function (t, anchor) { openMenu(this.programItems(t), { anchor }) }

    P.trackDialog = async function (t) {
        const r = await formDialog({
            title: '轨道属性',
            fields: [
                { key: 'name', label: '名称', value: t.name },
                { key: 'channel', label: 'MIDI 通道', type: 'select', value: t.channel, options: Array.from({ length: 16 }, (_, i) => [i, i === DRUM_CH ? `${i + 1}（鼓）` : String(i + 1)]) },
                { key: 'program', label: '音色', type: 'select', value: t.program, options: GM_PROGRAMS.map((n, i) => [i, `${i + 1}. ${n}`]) },
                { key: 'volume', label: '音量', type: 'range', min: 0, max: 127, value: t.volume },
                { key: 'pan', label: '声像', type: 'range', min: 0, max: 127, value: t.pan },
                { key: 'color', label: '颜色', type: 'color', value: t.color },
                { type: 'note', label: '通道 10 为打击乐（鼓组），音色号对应鼓组类型。' },
            ],
        })
        if (!r) return
        this.setTrackProp(t, { ...r, name: r.name.trim() || t.name }, '轨道属性')
    }

    // ---------- 总览 ----------
    // 总览横向铺满整首曲子；显示钢琴卷帘的可见范围
    P.ovScale = function () {
        const end = Math.max(this.endTick() + this.song.ppq * 4, this.song.ppq * 16)
        return { end, k: this.ov.w / end }
    }
    P.drawOverview = function () {
        if (!this.song || !this.ov) return
        const o = this.ov, c = o.c
        const r = this.ovWrap.getBoundingClientRect()
        const dpr = devicePixelRatio || 1
        o.w = Math.max(1, Math.round(r.width)); o.h = Math.max(1, Math.round(r.height))
        if (c.width !== Math.round(o.w * dpr) || c.height !== Math.round(o.h * dpr)) { c.width = Math.round(o.w * dpr); c.height = Math.round(o.h * dpr) }
        const g = o.g
        g.setTransform(dpr, 0, 0, dpr, 0, 0)
        const pal = this.pal
        g.fillStyle = pal.ovBg
        g.fillRect(0, 0, o.w, o.h)
        const { k } = this.ovScale()
        const RH = 22, top = RH - (this.ovScroll ?? 0)
        // 标尺
        forEachBar(this.song, 0, o.w / k, b => {
            const x = Math.round(b.tick * k)
            g.fillStyle = pal.lineBeat
            g.fillRect(x, RH, 1, o.h)
            if (b.len * k > 22 || b.bar % 4 === 1) {
                g.fillStyle = pal.rulerInk
                g.font = '10.5px system-ui, sans-serif'
                g.fillText(String(b.bar), x + 3, 15)
            }
        })
        // 循环区
        if (this.loop.end > this.loop.start) {
            g.fillStyle = this.loop.on ? pal.loopBar : pal.loopBarOff
            g.fillRect(this.loop.start * k, 0, (this.loop.end - this.loop.start) * k, 5)
        }
        g.save()
        g.beginPath(); g.rect(0, RH, o.w, o.h - RH); g.clip()
        const anySolo = this.song.tracks.some(t => t.solo)
        this.song.tracks.forEach((t, i) => {
            const y = top + i * ROW_H
            if (y > o.h || y + ROW_H < RH) return
            if (t === this.track) { g.fillStyle = pal.ovActive; g.fillRect(0, y, o.w, ROW_H) }
            g.fillStyle = pal.lineSub
            g.fillRect(0, y + ROW_H - 1, o.w, 1)
            if (!t.notes.length) return
            let lo = 127, hi = 0
            for (const n of t.notes) { lo = Math.min(lo, n.pitch); hi = Math.max(hi, n.pitch) }
            const span = Math.max(12, hi - lo + 1), ph = (ROW_H - 10) / span
            const silent = t.mute || (anySolo && !t.solo)
            g.globalAlpha = silent ? 0.3 : 0.95
            g.fillStyle = t.color
            for (const n of t.notes) {
                const nx = n.tick * k
                g.fillRect(nx, y + 5 + (hi - n.pitch) * ph + (span - (hi - lo + 1)) * ph / 2, Math.max(1.5, n.dur * k - 0.5), Math.max(1.5, ph))
            }
            g.globalAlpha = 1
        })
        g.restore()
        // 钢琴卷帘可见范围
        if (this.grid?.w > 1) {
            const [t0, t1] = this.visibleTicks()
            const ti = this.song.tracks.indexOf(this.track)
            g.strokeStyle = pal.accent
            g.lineWidth = 1.5
            g.strokeRect(t0 * k + 0.75, Math.max(RH, top + ti * ROW_H) + 0.75, Math.max(4, (t1 - t0) * k) - 1.5, ROW_H - 1.5)
            g.lineWidth = 1
        }
        g.fillStyle = pal.keyLine
        g.fillRect(0, RH - 1, o.w, 1)
        if (this.playing || this.cursor) {
            const px = Math.round((this.playing ? this.playTick : this.cursor) * k) + 0.5
            g.strokeStyle = this.playing ? pal.playhead : pal.cursor
            g.globalAlpha = this.playing ? 1 : 0.6
            g.beginPath(); g.moveTo(px, 0); g.lineTo(px, o.h); g.stroke()
            g.globalAlpha = 1
        }
    }
    // 总览与钢琴卷帘一起刷新的轻量入口
    P.drawLanes = function () {
        if (this._ovRAF) return
        this._ovRAF = requestAnimationFrame(() => { this._ovRAF = 0; this.drawOverview() })
    }

    P.bindOverview = function () {
        const c = this.ov.c
        let d = null
        const at = e => {
            const r = c.getBoundingClientRect()
            const x = e.clientX - r.left, y = e.clientY - r.top
            const { k } = this.ovScale()
            return { x, y, tick: x / k, ti: Math.floor((y - 22 + (this.ovScroll ?? 0)) / ROW_H) }
        }
        const scrollTo = tick => {
            this.view.sx = tick * this.view.zx - this.grid.w / 2
            this.clampView()
            this.drawRoll()
            this.drawLanes()
        }
        this.listen(c, 'pointerdown', e => {
            if (e.button) return
            const p = at(e)
            if (p.y < 22) { this.seekTick(this.snapRound(p.tick)); return }
            const t = this.song.tracks[p.ti]
            if (t) this.selectTrack(t.id)
            c.setPointerCapture(e.pointerId)
            d = true
            scrollTo(p.tick)
        })
        this.listen(c, 'pointermove', e => { if (d) scrollTo(at(e).tick) })
        this.listen(c, 'pointerup', () => { d = null })
        this.listen(c, 'dblclick', e => { const p = at(e); const t = this.song.tracks[p.ti]; if (t) this.trackDialog(t) })
        this.listen(c, 'contextmenu', e => {
            const p = at(e), t = this.song.tracks[p.ti]
            if (t) { this.selectTrack(t.id); contextMenu(e, this.trackMenuItems(t)) }
            else contextMenu(e, this.addTrackItems())
        })
    }
}
export { clamp }
