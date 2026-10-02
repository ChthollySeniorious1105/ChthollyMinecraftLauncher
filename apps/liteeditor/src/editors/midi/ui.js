// 工具栏、工具条、右侧面板、菜单与快捷键
import { h, fill, toast, clamp, numberInput, slider, formDialog, colorInput } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { toolRail, panel } from '../base.js'
import { isDrum, DRUM_CH, programName, noteName, DRUMS, tempoAt, sigAt, lastNoteTick } from './smf.js'
import { SNAPS } from './ops.js'

const fmtBpm = b => String(Math.round(b * 100) / 100)

const TOOLS = [
    { id: 'select', icon: 'mouse-pointer-2', label: '选择', key: 'V' },
    { id: 'draw', icon: 'pencil', label: '画笔', key: 'B' },
    { id: 'erase', icon: 'eraser', label: '橡皮擦', key: 'E' },
]
const SIGS = [[2, 4], [3, 4], [4, 4], [5, 4], [6, 8], [7, 8], [9, 8], [12, 8], [2, 2]]
const LENS = [[0, '自动'], [1, '全音符'], [1 / 2, '二分'], [1 / 4, '四分'], [1 / 8, '八分'], [1 / 16, '十六分'], [1 / 32, '三十二分']]

export function installUI(Ed) {
    const P = Ed.prototype

    P.buildLeft = function () {
        this.rail = toolRail(TOOLS, this.tool, id => this.setTool(id))
        this.rail.el.append(h('div.tool-sep'),
            this.ghostBtn = h('button.tool-btn', { title: '显示其他轨道的音符（幽灵音符）', onclick: () => this.toggleGhosts() }, icon('ghost', 19)),
            h('button.tool-btn', { title: '量化… (Q)', onclick: () => this.quantizeDialog() }, icon('grid-3x3', 19)),
            h('button.tool-btn', { title: '适合窗口', onclick: () => this.fitAll() }, icon('maximize', 19)))
        this.leftbar.append(this.rail.el)
        this.ghostBtn.classList.toggle('active', this.ghosts)
    }
    P.setTool = function (id) {
        this.tool = id
        this.rail.set(id)
        this.grid.c.style.cursor = id === 'erase' ? 'cell' : id === 'draw' ? 'copy' : 'default'
    }
    P.toggleGhosts = function () {
        this.ghosts = !this.ghosts
        this.ghostBtn.classList.toggle('active', this.ghosts)
        this.savePref()
        this.drawRoll()
    }

    P.buildToolbar = function () {
        // 走带控制
        this.playBtn = h('button.mi-play', { title: '播放 / 暂停 (空格)', onclick: () => this.togglePlay() }, icon('play', 18))
        this.loopBtn = this.tb('repeat', '循环播放 (L)：在标尺上拖动设置循环区', () => this.toggleLoop())
        this.metroBtn = this.tb('metronome', '节拍器', () => this.toggleMetronome())
        this.followBtn = this.tb('scan-line', '跟随播放头', () => { this.follow = !this.follow; this.savePref(); this.updateTransportUI() })
        this.tbGroup(
            this.tb('skip-back', '回到开头 (Home)', () => this.seekTick(0)),
            this.tb('square', '停止', () => this.stop()),
            this.playBtn,
            this.loopBtn, this.metroBtn, this.followBtn)
        this.posEl = h('span.mi-pos', '1.1.1')
        this.timeEl = h('span.mi-time', '0:00.0')
        this.tbGroup(h('div.mi-lcd', this.posEl, this.timeEl))
        // 速度 / 拍号
        this.bpmInput = numberInput(120, v => this.setTempo(v), { min: 20, max: 400, step: 1, width: 58, title: '速度（每分钟拍数）' })
        this.sigBtn = this.dd(h('span.mi-sig', '4/4'), () => [
            ...SIGS.map(([n, d]) => ({ label: `${n}/${d}`, checked: () => { const s = this.song.timeSig[0]; return s.num === n && s.den === d }, run: () => this.setTimeSig(n, d) })),
            '-', { label: '自定义…', run: () => this.timeSigDialog() },
        ], { title: '拍号' })
        this.tbGroup(icon('gauge', 16), this.bpmInput.el, h('span.tb-suffix', 'BPM'), this.sigBtn)
        // 吸附 / 音符长度
        this.snapBtn = this.dd(h('span.mi-snap', icon('magnet', 15), h('span.mi-snap-label')), () => SNAPS.map(([v, l]) => ({ label: l, checked: () => this.snap === v, run: () => this.setSnap(v) })), { title: '吸附网格' })
        this.lenBtn = this.dd(h('span.mi-len', icon('music-2', 15), h('span.mi-len-label')), () => LENS.map(([v, l]) => ({
            label: l, checked: () => (v ? Math.round(this.song.ppq * 4 * v) : 0) === this.noteLen,
            run: () => { this.noteLen = v ? Math.round(this.song.ppq * 4 * v) : 0; this.updateTransportUI() },
        })), { title: '新音符时值（自动 = 跟随吸附或上次调整）' })
        this.tbGroup(this.snapBtn, this.lenBtn)
        // 编辑
        this.tbGroup(
            this.tb('undo-2', '撤销 (Ctrl Z)', () => this.undo()),
            this.tb('redo-2', '重做 (Ctrl Y)', () => this.redo()),
            this.tb('copy-plus', '重复选中音符 (Ctrl D)', () => this.duplicateSel()),
            this.tb('trash-2', '删除 (Delete)', () => this.deleteSel()))
        // 音量
        const vol = slider({ min: 0, max: 100, value: Math.round(this.engine.volume * 100), oninput: v => { this.engine.setVolume(v / 100) }, onchange: () => this.savePref() })
        vol.input.title = '主音量'
        this.tbGroup(icon('volume-2', 16), h('div.mi-vol', vol.input))
        this.tbGroup(h('button.tb-text-btn', { title: '导出 WAV 音频', onclick: () => this.exportAs('wav') }, icon('audio-lines', 15), '导出音频'))
        this.updateTransportUI()
    }

    P.updateTransportUI = function () {
        if (!this.playBtn) return
        fill(this.playBtn, icon(this.playing ? 'pause' : 'play', 18))
        this.playBtn.classList.toggle('on', this.playing)
        this.loopBtn.classList.toggle('active', this.loop.on)
        this.metroBtn.classList.toggle('active', this.metronome)
        this.followBtn.classList.toggle('active', this.follow)
        const bpm = tempoAt(this.song, 0)
        if (document.activeElement !== this.bpmInput.input) this.bpmInput.set(fmtBpm(bpm))
        const s = this.song.timeSig[0]
        this.sigBtn.querySelector('.mi-sig').textContent = `${s.num}/${s.den}`
        this.snapBtn.querySelector('.mi-snap-label').textContent = SNAPS.find(([v]) => v === this.snap)?.[1] ?? '—'
        const len = LENS.find(([v]) => (v ? Math.round(this.song.ppq * 4 * v) : 0) === this.noteLen)
        this.lenBtn.querySelector('.mi-len-label').textContent = len ? len[1] : '自定义'
    }

    P.toggleLoop = function () {
        if (!(this.loop.end > this.loop.start)) {
            // 默认循环：光标所在的 4 小节
            const bar = this.song.ppq * 4 / this.song.timeSig[0].den * this.song.timeSig[0].num
            this.loop.start = Math.floor(this.cursor / bar) * bar
            this.loop.end = this.loop.start + bar * 4
        }
        this.loop.on = !this.loop.on
        this.updateTransportUI()
        this.onLoopChanged()
        if (this.playing) this.engine.setLoop(this.loop.on)
        this.drawRoll()
        this.drawOverview()
    }
    P.toggleMetronome = function () {
        this.metronome = !this.metronome
        this.savePref()
        this.onLoopChanged()
        this.updateTransportUI()
    }
    P.setSnap = function (v) {
        this.snap = v
        this.savePref()
        this.updateTransportUI()
        this.drawRoll()
    }
    P.setTempo = function (bpm) {
        bpm = clamp(Number(bpm) || 120, 20, 400)
        // 修改起始速度；其余速度变化按比例缩放
        const k = bpm / this.song.tempos[0].bpm
        if (k === 1) return
        for (const t of this.song.tempos) t.bpm = clamp(t.bpm * k, 10, 999)
        this.commit('速度', { merge: 'tempo' })
        this.afterEdit()
    }
    P.setTimeSig = function (num, den) {
        this.song.timeSig = [{ tick: 0, num, den }, ...this.song.timeSig.slice(1)]
        this.commit('拍号')
        this.afterEdit()
    }
    P.timeSigDialog = async function () {
        const s = this.song.timeSig[0]
        const r = await formDialog({
            title: '拍号', fields: [
                { key: 'num', label: '每小节拍数', type: 'number', min: 1, max: 32, value: s.num },
                { key: 'den', label: '以几分音符为一拍', type: 'select', value: s.den, options: [[2, '2'], [4, '4'], [8, '8'], [16, '16']] },
            ],
        })
        if (r) this.setTimeSig(clamp(Math.round(r.num) || 4, 1, 32), r.den)
    }
    P.tempoDialog = async function () {
        const r = await formDialog({
            title: '速度', fields: [
                { key: 'bpm', label: '速度 (BPM)', type: 'number', min: 20, max: 400, step: 1, value: Math.round(this.song.tempos[0].bpm * 100) / 100 },
                this.song.tempos.length > 1 ? { key: 'flat', label: '清除变速', type: 'check', value: false } : null,
                this.song.tempos.length > 1 ? { type: 'note', label: `乐曲中有 ${this.song.tempos.length - 1} 处速度变化，修改起始速度会按比例缩放它们。` } : null,
            ].filter(Boolean),
        })
        if (!r) return
        if (r.flat) { this.song.tempos = [{ tick: 0, bpm: this.song.tempos[0].bpm }]; this.commit('清除变速') }
        this.setTempo(r.bpm)
        this.afterEdit()
    }

    // ---------- 右侧面板 ----------
    P.buildPanels = function () {
        this.trackPanelBody = h('div.mi-panel')
        this.notePanelBody = h('div.mi-panel')
        this.panels.append(
            panel('轨道', this.trackPanelBody, { icon: 'sliders-horizontal' }),
            panel('音符', this.notePanelBody, { icon: 'music' }),
            panel('快捷键', h('div.mi-help', [
                ['单击 / 拖动', '选择、移动音符'], ['拖动音符右端', '调整时值'], ['双击空白', '添加音符'], ['Ctrl 拖动', '复制音符'],
                ['↑ ↓', '移调半音'], ['Shift ↑ ↓', '移调八度'], ['← →', '按网格移动'], ['Ctrl 滚轮', '水平缩放'], ['Alt 滚轮', '垂直缩放'],
                ['空格', '播放 / 暂停'], ['标尺上拖动', '设置循环区'],
            ].map(([k, v]) => h('div.mi-help-row', h('kbd', k), h('span', v)))), { icon: 'keyboard', collapsed: true }))
    }
    P.refreshPanels = function () {
        if (!this.trackPanelBody) return
        const t = this.track
        if (!t) return
        const row = (label, ...ctl) => h('div.ep-row', h('label', label), ...ctl)
        const name = h('input.tb-number.mi-name', { value: t.name, onchange: e => this.setTrackProp(t, { name: e.target.value.trim() || t.name }, '重命名轨道') })
        const vol = slider({ min: 0, max: 127, value: t.volume, oninput: v => this.setTrackProp(t, { volume: v }, '音量', 'vol'), format: v => v })
        const pan = slider({ min: 0, max: 127, value: t.pan, oninput: v => this.setTrackProp(t, { pan: v }, '声像', 'pan'), format: v => v === 64 ? '居中' : v < 64 ? `左 ${64 - v}` : `右 ${v - 64}` })
        const color = colorInput(t.color, v => this.setTrackProp(t, { color: v }, '轨道颜色', 'color'))
        const ch = h('select.tb-select', { onchange: e => this.setTrackProp(t, { channel: Number(e.target.value) }, '更改通道') },
            Array.from({ length: 16 }, (_, i) => h('option', { value: i, selected: i === t.channel }, i === DRUM_CH ? `${i + 1}（鼓）` : String(i + 1))))
        const prog = h('button.tb-menu.mi-prog-btn', { onclick: e => this.programMenu(t, e.currentTarget) }, icon(isDrum(t) ? 'drum' : 'piano', 14), h('span', programName(t)), icon('chevron-down', 13))
        fill(this.trackPanelBody,
            row('名称', name, color.el),
            row('音色', prog),
            row('通道', ch),
            row('音量', vol.input),
            row('声像', pan.input),
            h('div.ep-row.mi-track-actions',
                h('button.tb-text-btn', { onclick: () => this.setTrackProp(t, { mute: !t.mute }, '静音'), class: t.mute ? 'active' : '' }, icon(t.mute ? 'volume-x' : 'volume-2', 14), '静音'),
                h('button.tb-text-btn', { onclick: () => this.setTrackProp(t, { solo: !t.solo }, '独奏'), class: t.solo ? 'active' : '' }, icon('headphones', 14), '独奏'),
                h('button.icon-btn', { title: '复制轨道', onclick: () => this.duplicateTrack(t) }, icon('copy-plus', 15)),
                h('button.icon-btn', { title: '删除轨道', onclick: () => this.deleteTrack(t) }, icon('trash-2', 15))),
            h('div.mi-panel-sub', `${t.notes.length} 个音符`))
        // 显示滑块数值
        for (const [s, lbl] of [[vol, v => v], [pan, v => v === 64 ? '居中' : v < 64 ? `左 ${64 - v}` : `右 ${v - 64}`]]) {
            const out = h('span.range-value', lbl(Number(s.input.value)))
            s.input.after(out)
            s.input.addEventListener('input', () => { out.textContent = lbl(Number(s.input.value)) })
        }
        this.updateNotePanel()
    }
    P.updateNotePanel = function () {
        if (!this.notePanelBody) return
        const ns = this.selNotes()
        const t = this.track
        if (!ns.length) {
            fill(this.notePanelBody,
                h('div.ep-empty', '未选择音符。单击或框选音符以编辑；使用画笔工具（B）或双击空白处添加。'),
                h('div.ep-row', h('label', '新音符力度'), (() => { const s = slider({ min: 1, max: 127, value: this.newVel, oninput: v => { this.newVel = v; out.textContent = v } }); const out = h('span.range-value', this.newVel); return [s.input, out] })()))
            return
        }
        const n = ns[0], one = ns.length === 1
        const avgVel = Math.round(ns.reduce((s, x) => s + x.vel, 0) / ns.length)
        const vel = slider({ min: 1, max: 127, value: avgVel, oninput: v => { for (const x of ns) x.vel = v; out.textContent = v; this.audioDirty = true; this.drawSoon(); this.commit('力度', { merge: 'vel' }) } })
        const out = h('span.range-value', avgVel)
        const ppq = this.song.ppq
        const fmtLen = d => { const b = d / ppq; return Number.isInteger(b) ? `${b} 拍` : `${Math.round(b * 1000) / 1000} 拍` }
        fill(this.notePanelBody,
            h('div.mi-panel-sub', one ? `${isDrum(t) ? DRUMS[n.pitch] ?? noteName(n.pitch) : noteName(n.pitch)} · 音高 ${n.pitch}` : `已选择 ${ns.length} 个音符`),
            one ? h('div.ep-row', h('label', '时值'), h('span', fmtLen(n.dur))) : null,
            h('div.ep-row', h('label', '力度'), vel.input, out),
            h('div.ep-row.mi-note-actions',
                h('button.tb-text-btn', { onclick: () => this.transpose(-12) }, '-8度'),
                h('button.tb-text-btn', { onclick: () => this.transpose(-1) }, '-1'),
                h('button.tb-text-btn', { onclick: () => this.transpose(1) }, '+1'),
                h('button.tb-text-btn', { onclick: () => this.transpose(12) }, '+8度')),
            h('div.ep-row.mi-note-actions',
                h('button.tb-text-btn', { onclick: () => this.quantizeDialog() }, icon('grid-3x3', 14), '量化'),
                h('button.tb-text-btn', { onclick: () => this.legato() }, '连奏'),
                h('button.tb-text-btn', { onclick: () => this.deleteSel() }, icon('trash-2', 14), '删除')))
    }

    // ---------- 菜单 ----------
    P.menus = function () {
        const has = () => this.sel.size > 0
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors', key: 'Ctrl+X', disabled: () => !has(), run: () => this.copySel(true) },
                    { label: '复制', icon: 'copy', key: 'Ctrl+C', disabled: () => !has(), run: () => this.copySel() },
                    { label: '粘贴到光标处', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste() },
                    { label: '重复', icon: 'copy-plus', key: 'Ctrl+D', disabled: () => !has(), run: () => this.duplicateSel() },
                    { label: '删除', icon: 'trash-2', key: 'Delete', altKey: 'Backspace', disabled: () => !has(), run: () => this.deleteSel() },
                    '-',
                    { label: '全选', icon: 'box-select', key: 'Ctrl+A', run: () => this.selectAll() },
                    { label: '取消选择', key: 'Escape', run: () => this.selectNone() },
                    '-',
                    { label: '选择', icon: 'mouse-pointer-2', key: 'V', checked: () => this.tool === 'select', run: () => this.setTool('select') },
                    { label: '画笔', icon: 'pencil', key: 'B', checked: () => this.tool === 'draw', run: () => this.setTool('draw') },
                    { label: '橡皮擦', icon: 'eraser', key: 'E', checked: () => this.tool === 'erase', run: () => this.setTool('erase') },
                ],
            },
            {
                label: '音符', items: () => [
                    { label: '量化…', icon: 'grid-3x3', key: 'Q', run: () => this.quantizeDialog() },
                    { label: '设置力度…', icon: 'bar-chart-3', run: () => this.velocityDialog() },
                    { label: '连奏（延长到下一音符）', run: () => this.legato() },
                    { label: '时值加倍', run: () => this.scaleLength(2) },
                    { label: '时值减半', run: () => this.scaleLength(0.5) },
                    { label: '人性化（随机微调）', icon: 'sparkles', run: () => this.humanize() },
                    '-',
                    { label: '升高半音', icon: 'arrow-up', key: 'ArrowUp', disabled: () => !has(), run: () => this.transpose(1) },
                    { label: '降低半音', icon: 'arrow-down', key: 'ArrowDown', disabled: () => !has(), run: () => this.transpose(-1) },
                    { label: '升高八度', key: 'Shift+ArrowUp', disabled: () => !has(), run: () => this.transpose(12) },
                    { label: '降低八度', key: 'Shift+ArrowDown', disabled: () => !has(), run: () => this.transpose(-12) },
                    { label: '左移', icon: 'arrow-left', key: 'ArrowLeft', disabled: () => !has(), run: () => this.nudge(-1) },
                    { label: '右移', icon: 'arrow-right', key: 'ArrowRight', disabled: () => !has(), run: () => this.nudge(1) },
                    '-',
                    { label: '吸附网格', icon: 'magnet', submenu: () => SNAPS.map(([v, l]) => ({ label: l, checked: () => this.snap === v, run: () => this.setSnap(v) })) },
                ],
            },
            {
                label: '轨道', items: () => [
                    { label: '添加轨道', icon: 'plus', submenu: () => this.addTrackItems() },
                    { label: '复制轨道', icon: 'copy-plus', run: () => this.duplicateTrack() },
                    { label: '删除轨道', icon: 'trash-2', danger: true, run: () => this.deleteTrack() },
                    '-',
                    { label: '轨道属性…', icon: 'sliders-horizontal', run: () => this.trackDialog(this.track) },
                    { label: '选择音色', icon: 'piano', submenu: () => this.programItems(this.track) },
                    '-',
                    { label: '上一条轨道', key: 'Alt+ArrowUp', run: () => this.stepTrack(-1) },
                    { label: '下一条轨道', key: 'Alt+ArrowDown', run: () => this.stepTrack(1) },
                    { label: '静音当前轨道', key: 'M', checked: () => this.track.mute, run: () => this.setTrackProp(this.track, { mute: !this.track.mute }, '静音') },
                    { label: '独奏当前轨道', key: 'S', checked: () => this.track.solo, run: () => this.setTrackProp(this.track, { solo: !this.track.solo }, '独奏') },
                    { label: '取消所有静音 / 独奏', run: () => { for (const t of this.song.tracks) { t.mute = false; t.solo = false } this.commit('取消静音'); this.afterEdit() } },
                ],
            },
            {
                label: '播放', items: () => [
                    { label: () => this.playing ? '暂停' : '播放', icon: this.playing ? 'pause' : 'play', key: 'Space', run: () => this.togglePlay() },
                    { label: '停止', icon: 'square', run: () => this.stop() },
                    { label: '回到开头', icon: 'skip-back', key: 'Home', run: () => this.seekTick(0) },
                    { label: '跳到结尾', icon: 'skip-forward', key: 'End', run: () => this.seekTick(lastNoteTick(this.song)) },
                    '-',
                    { label: '循环播放', icon: 'repeat', key: 'L', checked: () => this.loop.on, run: () => this.toggleLoop() },
                    { label: '将循环区设为选中音符', disabled: () => !has(), run: () => this.loopToSelection() },
                    { label: '节拍器', checked: () => this.metronome, run: () => this.toggleMetronome() },
                    { label: '跟随播放头', checked: () => this.follow, run: () => { this.follow = !this.follow; this.savePref(); this.updateTransportUI() } },
                    '-',
                    { label: '速度…', icon: 'gauge', run: () => this.tempoDialog() },
                    { label: '拍号…', run: () => this.timeSigDialog() },
                    '-',
                    { label: this.midiInputs?.length ? `MIDI 键盘：已连接 ${this.midiInputs.length} 个` : '连接 MIDI 键盘', icon: 'keyboard-music', run: () => this.connectMIDI() },
                    { label: '录制 MIDI 键盘输入', icon: 'circle-dot', key: 'R', checked: () => !!this.recording, run: () => this.toggleRecord() },
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '水平放大', icon: 'zoom-in', key: 'Ctrl+=', run: () => this.zoomX(1.3) },
                    { label: '水平缩小', icon: 'zoom-out', key: 'Ctrl+-', run: () => this.zoomX(1 / 1.3) },
                    { label: '垂直放大', key: 'Alt+=', run: () => this.zoomY(1.2) },
                    { label: '垂直缩小', key: 'Alt+-', run: () => this.zoomY(1 / 1.2) },
                    { label: '适合窗口', icon: 'maximize', key: 'Ctrl+0', run: () => this.fitAll() },
                    '-',
                    { label: '幽灵音符（其他轨道）', icon: 'ghost', checked: () => this.ghosts, run: () => this.toggleGhosts() },
                    { label: '右侧面板', checked: () => !this.panels.classList.contains('hidden'), run: () => { this.panels.classList.toggle('hidden'); requestAnimationFrame(() => this.drawAll()) } },
                ],
            },
        ]
    }

    P.stepTrack = function (d) {
        const i = this.song.tracks.indexOf(this.track)
        const t = this.song.tracks[clamp(i + d, 0, this.song.tracks.length - 1)]
        this.selectTrack(t.id)
    }
    P.loopToSelection = function () {
        const ns = this.selNotes()
        if (!ns.length) return
        const s = this.snapTicks() || this.song.ppq
        this.loop.start = Math.floor(Math.min(...ns.map(n => n.tick)) / s) * s
        this.loop.end = Math.ceil(Math.max(...ns.map(n => n.tick + n.dur)) / s) * s
        this.loop.on = true
        this.updateTransportUI()
        this.onLoopChanged()
        this.drawRoll()
        this.drawOverview()
    }

    // 空格在菜单快捷键之前处理（避免按钮获得焦点时触发点击）
    P.onKey = function (e) {
        if (e.target?.closest?.('input:not([type=range]), textarea, select')) return false
        if (e.code === 'Space' && !e.ctrlKey && !e.altKey) { e.preventDefault(); this.togglePlay(); return true }
        return false
    }

    // ---------- Web MIDI 输入（可选） ----------
    P.connectMIDI = async function () {
        if (!navigator.requestMIDIAccess) { toast('当前环境不支持 Web MIDI', 'warn'); return }
        try {
            const acc = this.midiAccess = await navigator.requestMIDIAccess()
            const bind = () => {
                this.midiInputs = [...acc.inputs.values()]
                for (const i of this.midiInputs) i.onmidimessage = e => this.onMIDIMessage(e.data)
            }
            bind()
            acc.onstatechange = bind
            toast(this.midiInputs.length ? `已连接 ${this.midiInputs.length} 个 MIDI 输入设备` : '未发现 MIDI 输入设备', this.midiInputs.length ? 'success' : 'warn')
        } catch (e) { toast('无法访问 MIDI 设备：' + e.message, 'error') }
    }
    P.onMIDIMessage = function (d) {
        const t = this.track
        if (!t) return
        const hi = d[0] & 0xf0
        const on = hi === 0x90 && d[2] > 0, off = hi === 0x80 || (hi === 0x90 && d[2] === 0)
        if (on) this.engineNoteOn(t, d[1], d[2])
        else if (off) this.engine.noteOff(t.channel, d[1])
        if (!this.recording || !this.playing) return
        const rec = this.recording
        const tick = Math.round(this.playTick)
        if (on) rec.open.set(d[1], { tick, vel: d[2] })
        else if (off && rec.open.has(d[1])) {
            const o = rec.open.get(d[1])
            rec.open.delete(d[1])
            t.notes.push({ id: 'n' + Math.random().toString(36).slice(2, 10), tick: o.tick, dur: Math.max(10, tick - o.tick), pitch: d[1], vel: o.vel })
            rec.count++
            this.sortNotes()
            this.drawSoon()
        }
    }
    P.toggleRecord = async function () {
        if (this.recording) {
            const n = this.recording.count
            this.recording = null
            if (n) { this.commit('录制'); this.afterEdit() }
            toast(`录制结束：${n} 个音符`)
            return
        }
        if (!this.midiInputs?.length) await this.connectMIDI()
        if (!this.midiInputs?.length) return
        this.recording = { open: new Map(), count: 0 }
        toast('开始录制：弹奏 MIDI 键盘，再次按 R 结束')
        if (!this.playing) this.play()
    }
}
