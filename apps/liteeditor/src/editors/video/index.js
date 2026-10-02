// 视频剪辑编辑器
import JSZip from 'jszip'
import { h, fill, toast, clamp, formDialog, confirmDialog, sleep } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu, keyString } from '../../core/menu.js'
import { extOf, baseName, bytesToText } from '../../core/files.js'
import { Editor } from '../base.js'
import { newProject, clone, fmtTC, fmtDur, PRESETS, FPS_LIST, projDuration, clipEnd } from './model.js'
import { Asset, probeMedia } from './media.js'
import { installPreview } from './preview.js'
import { installTimeline } from './timeline.js'
import { installOps } from './ops.js'
import { installPanels } from './panels.js'

export class VideoEditor extends Editor {
    static kind = 'video'
    // 供测试 / 其他模块使用 mediabunny
    static mediabunny() { return import('mediabunny') }

    constructor(file, app) {
        super(file, app)
        this.proj = newProject()
        this.sel = []
        this.assets = new Map()   // mediaId -> Asset（运行时）
        this.blobs = new Map()    // mediaId -> Uint8Array（内嵌媒体字节，快照之间共享）
        this.clipboard = VideoEditor.clipboard?.clips ?? null
        this.initPreview()
        this.buildLayout()
    }

    // ---------- 布局 ----------
    buildLayout() {
        this.stage.classList.add('vx-stage')
        this.pv = h('canvas.vx-pv')
        this.pvCtx = this.pv.getContext('2d')
        this.pvOverlay = h('canvas.vx-pv-overlay')
        this.pvOCtx = this.pvOverlay.getContext('2d')
        this.pvEmpty = h('div.vx-empty',
            h('div.vx-empty-icon', icon('clapperboard', 38)),
            h('div.vx-empty-title', '拖入视频、音频或图片开始剪辑'),
            h('div.vx-empty-sub', '支持 MP4 · WebM · MKV · MOV · MP3 · WAV · PNG · JPG'),
            h('button.btn.primary', { onclick: () => this.importDialog() }, icon('file-plus-2', 16), '导入媒体…'))
        this.pvWrap = h('div.vx-pv-wrap', { 'data-drop': '' }, h('div.vx-pv-box', this.pv, this.pvOverlay), this.pvEmpty)
        this.buildTransport()
        this.buildTimeline()
        this.splitter = h('div.vx-splitter', { title: '拖动调整高度' })
        this.pvPane = h('div.vx-pv-pane', this.pvWrap, this.transport)
        this.stage.append(this.pvPane, this.splitter, this.tlEl)
        this.tlHeight = clamp(Number(localStorage.getItem('le.video.tlh')) || 280, 150, 700)
        this.tlEl.style.height = this.tlHeight + 'px'
        this.bindSplitter()
        this.buildToolbar()
        this.buildPanels()
        this.ro = new ResizeObserver(() => requestAnimationFrame(() => { this.sizePreview(); this.renderPreview(); this.sizeTimeline(); this.drawTimeline() }))
        this.ro.observe(this.pvWrap)
        this.ro.observe(this.tlArea)
        this.onDispose(() => this.ro.disconnect())
        // 预览中点击选择 / 拖动位置
        this.listen(this.pvOverlay, 'pointerdown', e => this.pvDown(e))
        this.listen(this.pvWrap, 'dragover', e => { if ([...e.dataTransfer.types].includes('Files')) { e.preventDefault(); this.pvWrap.classList.add('drop') } })
        this.listen(this.pvWrap, 'dragleave', () => this.pvWrap.classList.remove('drop'))
        this.listen(this.pvWrap, 'drop', e => { e.preventDefault(); this.pvWrap.classList.remove('drop'); this.importFiles([...e.dataTransfer.files], { start: this.proj.clips.length ? projDuration(this.proj) : 0 }) })
        this.listen(this.pvWrap, 'contextmenu', e => contextMenu(e, [
            { label: '导出当前帧为 PNG…', icon: 'image-down', run: () => this.exportAs('png') },
            { label: '添加字幕', icon: 'captions', run: () => this.addText('subtitle') },
            '-',
            { label: '循环播放', checked: () => this.loop, run: () => { this.loop = !this.loop; this.updateTransport() } },
        ]))
        this.listen(this.el, 'keyup', e => { if (e.code === 'KeyJ' || e.code === 'KeyL') this.shuttle = 0 })
    }

    bindSplitter() {
        this.splitter.addEventListener('pointerdown', e => {
            e.preventDefault()
            this.splitter.setPointerCapture(e.pointerId)
            const y0 = e.clientY, h0 = this.tlHeight
            const move = ev => {
                const max = this.stage.getBoundingClientRect().height - 200
                this.tlHeight = clamp(h0 - (ev.clientY - y0), 140, Math.max(160, max))
                this.tlEl.style.height = this.tlHeight + 'px'
            }
            const up = () => {
                this.splitter.removeEventListener('pointermove', move)
                this.splitter.removeEventListener('pointerup', up)
                localStorage.setItem('le.video.tlh', this.tlHeight)
            }
            this.splitter.addEventListener('pointermove', move)
            this.splitter.addEventListener('pointerup', up)
        })
    }

    buildTransport() {
        const b = (ic, title, fn, cls = '') => h('button.vx-tbtn' + cls, { title, onclick: fn }, icon(ic, 17))
        this.playBtn = h('button.vx-play', { title: '播放 / 暂停 (空格)', onclick: () => this.togglePlay() }, icon('play', 20))
        this.loopBtn = b('repeat', '循环播放', () => { this.loop = !this.loop; this.updateTransport() })
        this.tcEl = h('span.vx-tc', '00:00:00:00')
        this.durEl = h('span.vx-dur', '/ 00:00:00:00')
        this.transport = h('div.vx-transport',
            h('div.vx-tr-left', this.tcEl, this.durEl),
            h('div.vx-tr-center',
                b('skip-back', '跳到开头 (Home)', () => this.seek(0)),
                b('chevrons-left', '上一个剪辑点 (↑)', () => this.jumpEdit(-1)),
                b('step-back', '上一帧 (←)', () => this.stepFrames(-1)),
                this.playBtn,
                b('step-forward', '下一帧 (→)', () => this.stepFrames(1)),
                b('chevrons-right', '下一个剪辑点 (↓)', () => this.jumpEdit(1)),
                b('skip-forward', '跳到结尾 (End)', () => this.seek(this.duration()))),
            h('div.vx-tr-right', this.loopBtn,
                b('image-down', '导出当前帧 PNG', () => this.exportAs('png')),
                h('span.vx-res'), ))
        this.resEl = this.transport.querySelector('.vx-res')
    }

    buildToolbar() {
        this.tbGroup(
            h('button.tb-text-btn', { title: '导入媒体 (Ctrl+I)', onclick: () => this.importDialog() }, icon('file-plus-2', 16), '导入'),
            this.dd(h('span.tb-new', icon('type', 16), '文字'), [
                { label: '字幕', icon: 'captions', run: () => this.addText('subtitle') },
                { label: '标题', icon: 'heading', run: () => this.addText('title') },
                { label: '人名条', icon: 'id-card', run: () => this.addText('lower') },
            ], { title: '添加文字' }),
            this.tb('square', '添加纯色片段', () => this.addColor()))
        this.tbGroup(
            this.tb('undo-2', '撤销 (Ctrl+Z)', () => this.undo()),
            this.tb('redo-2', '重做 (Ctrl+Y)', () => this.redo()))
        this.selBtns = [
            this.tb('scissors', '在播放头处分割 (S)', () => this.splitAtPlayhead()),
            this.tb('arrow-left-to-line', '删除播放头左侧 (Q)', () => this.trimSide('left')),
            this.tb('arrow-right-to-line', '删除播放头右侧 (W)', () => this.trimSide('right')),
            this.tb('copy-plus', '创建副本 (Ctrl+D)', () => this.duplicateSel()),
            this.tb('trash-2', '删除 (Del)', () => this.deleteSel()),
            this.tb('trash', '波纹删除 (Shift+Del)', () => this.deleteSel(true)),
        ]
        this.tbGroup(...this.selBtns)
        this.snapBtn = this.tb('magnet', '吸附', () => { this.snapOn = !this.snapOn; this.updateToolbarState() })
        this.tbGroup(this.snapBtn,
            this.tb('zoom-out', '缩小时间线 (-)', () => this.zoomBy(1 / 1.4)),
            this.tb('zoom-in', '放大时间线 (=)', () => this.zoomBy(1.4)),
            this.tb('maximize-2', '适合窗口 (Shift+Z)', () => this.zoomFit()))
        this.toolbar.append(h('div.vx-tb-flex'))
        this.tbGroup(
            h('button.tb-text-btn', { title: '项目设置', onclick: () => this.projectDialog() }, icon('settings-2', 16), h('span.vx-proj-label', '')),
            h('button.tb-text-btn.primary', { title: '导出视频 (Ctrl+E)', onclick: () => this.exportDialog() }, icon('upload', 16), '导出'))
    }
    updateToolbarState() {
        this.snapBtn?.classList.toggle('active', this.snapOn)
        const lbl = this.toolbar.querySelector('.vx-proj-label')
        if (lbl) lbl.textContent = `${this.proj.width}×${this.proj.height} · ${this.proj.fps}fps`
    }

    updateTransport() {
        fill(this.playBtn, icon(this.playing ? 'pause' : 'play', 20))
        this.playBtn.classList.toggle('on', this.playing)
        this.loopBtn.classList.toggle('on', this.loop)
        this.durEl.textContent = '/ ' + fmtTC(this.duration(), this.proj.fps)
        this.resEl.textContent = `${this.proj.width} × ${this.proj.height}`
        this.pvEmpty.hidden = this.proj.clips.length > 0
        this.onTimeChange()
    }
    onTimeChange(fromPlayback) {
        this.tcEl.textContent = fmtTC(this.time, this.proj.fps)
        // 播放时让播放头保持可见
        if (fromPlayback) {
            const x = this.tx(this.time)
            if (x > this.tlW - 40 || x < 0) this.scrollX = clamp(this.time * this.pps - 60, 0, this.maxScrollX())
        }
        this.drawTimeline()
    }

    updateStatus() {
        const p = this.proj
        this.statusItems(
            h('span.st-item', icon('monitor', 13), `${p.width} × ${p.height}`),
            h('span.st-item', icon('gauge', 13), `${p.fps} fps`),
            h('span.st-item', icon('timer', 13), '时长 ' + fmtDur(this.duration())),
            h('span.st-item', icon('layers', 13), `${p.clips.length} 个片段`),
            this.sel.length ? h('span.st-item', `已选 ${this.sel.length}`) : null,
            h('span.st-flex'),
            h('button', { title: '适合窗口', onclick: () => this.zoomFit() }, icon('maximize-2', 13)),
            h('button', { onclick: () => this.zoomBy(1 / 1.4) }, icon('minus', 13)),
            h('span', `${Math.round(this.pps)} 像素/秒`),
            h('button', { onclick: () => this.zoomBy(1.4) }, icon('plus', 13)))
    }

    // ---------- 预览交互：点击选择、拖动移动位置 ----------
    pvDown(e) {
        if (e.button !== 0) return
        this.el.focus({ preventScroll: true })
        const r = this.pvOverlay.getBoundingClientRect()
        const k = this.proj.width / r.width
        const px = (e.clientX - r.left) * k, py = (e.clientY - r.top) * k
        // 自上而下命中
        const ids = [...this.boxes.keys()].reverse()
        const hit = ids.find(id => {
            const b = this.boxes.get(id)
            const a = -b.rot * Math.PI / 180
            const dx = px - b.cx, dy = py - b.cy
            const lx = dx * Math.cos(a) - dy * Math.sin(a), ly = dx * Math.sin(a) + dy * Math.cos(a)
            return Math.abs(lx) <= b.w / 2 && Math.abs(ly) <= b.h / 2
        })
        if (!hit) { this.setSel([]); return }
        const c = this.clipById(hit)
        if (!this.sel.includes(hit)) this.setSel([hit])
        if (this.trackLocked(c)) return
        const x0 = c.x || 0, y0 = c.y || 0
        this.pvOverlay.setPointerCapture(e.pointerId)
        let moved = false
        const move = ev => {
            let nx = x0 + (ev.clientX - e.clientX) * k, ny = y0 + (ev.clientY - e.clientY) * k
            // 吸附到中心
            if (!ev.altKey) { if (Math.abs(nx) < 12 * k) nx = 0; if (Math.abs(ny) < 12 * k) ny = 0 }
            c.x = Math.round(nx); c.y = Math.round(ny)
            moved = true
            this.renderPreview()
        }
        const up = () => {
            this.pvOverlay.removeEventListener('pointermove', move)
            this.pvOverlay.removeEventListener('pointerup', up)
            if (moved) { this.refreshPanels(); this.commit('移动位置') }
        }
        this.pvOverlay.addEventListener('pointermove', move)
        this.pvOverlay.addEventListener('pointerup', up)
    }
    trackLocked(c) { return this.proj.tracks.find(t => t.id === c.track)?.locked }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        const pr = PRESETS.find(x => x[0] === (opts.preset ?? '1080p'))
        this.proj = newProject({ width: opts.width ?? pr[2], height: opts.height ?? pr[3], fps: opts.fps ?? 30 })
        this.afterLoad()
    }

    async load(bytes, ext) {
        if (ext === 'lvideo') return this.loadProject(bytes)
        // 直接打开媒体文件：创建只包含该片段的项目
        const m = await this.addMediaFirst(bytes, ext)
        const p = this.proj
        if (m.width && m.height) {
            p.width = Math.round(m.width / 2) * 2
            p.height = Math.round(m.height / 2) * 2
        }
        const c = this.addMediaClip(m, { start: 0, commit: false })
        this.sel = [c.id]
        this.afterLoad()
    }
    async addMediaFirst(bytes, ext) {
        this.proj = newProject()
        if (this.path) return this.addMedia({ path: this.path })
        return this.addMedia({ name: this.name.endsWith('.' + ext) ? this.name : `${this.name}.${ext}`, bytes })
    }

    afterLoad() {
        this.time = 0
        requestAnimationFrame(() => { this.renderAll(); this.zoomFit() })
        this.renderAll()
    }

    // 快照：项目 JSON（媒体字节保存在 this.blobs 中，按引用共享）
    snapshot() { return { proj: JSON.stringify(this.proj), sel: [...this.sel] } }
    restore(s) {
        if (this.playing) this.pause()
        this.proj = JSON.parse(s.proj)
        this.sel = s.sel.filter(id => this.clipById(id))
        // 撤销可能恢复已移除的媒体：确保资源存在
        for (const m of this.proj.media) if (!this.assets.has(m.id)) this.attachAsset(new Asset(m, this.blobs.get(m.id)))
        this.invalidateFrames()
        this.time = Math.min(this.time, Math.max(0, this.duration()))
        this.renderAll()
    }

    // ---------- 保存 / 打开 .lvideo（ZIP：project.json + media/） ----------
    formats() {
        return [{ ext: 'lvideo', name: 'LiteEditor 视频项目', write: target => this.saveProject(target) }]
    }
    async saveProject() {
        const zip = new JSZip()
        const proj = clone(this.proj)
        const used = new Set(proj.clips.map(c => c.media).filter(Boolean))
        proj.media = proj.media.filter(m => used.has(m.id) || m.path)
        for (const m of proj.media) {
            const b = this.blobs.get(m.id)
            if (b && !m.path) { m.embedded = `media/${m.id}.${m.ext}`; zip.file(m.embedded, b, { compression: 'STORE' }) }
            delete m.offline
        }
        zip.file('project.json', JSON.stringify(proj, null, 1))
        return zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' })
    }
    async loadProject(bytes) {
        let proj, zip = null
        if (bytes[0] === 0x50 && bytes[1] === 0x4b) {
            zip = await JSZip.loadAsync(bytes)
            const f = zip.file('project.json')
            if (!f) throw new Error('不是有效的视频项目文件')
            proj = JSON.parse(await f.async('string'))
        } else proj = JSON.parse(bytesToText(bytes))
        if (proj.format !== 'lvideo' || !Array.isArray(proj.clips)) throw new Error('不是有效的视频项目文件')
        this.proj = { ...newProject(), ...proj }
        const missing = []
        for (const m of this.proj.media) {
            let b = null
            if (m.embedded && zip?.file(m.embedded)) b = await zip.file(m.embedded).async('uint8array')
            if (b) { this.blobs.set(m.id, b); delete m.embedded }
            else if (m.path) {
                const st = await window.lite.stat(m.path).catch(() => null)
                if (!st?.isFile) { m.offline = true; missing.push(m.name) }
            } else { m.offline = true; missing.push(m.name) }
            const asset = new Asset(m, b)
            if (!m.offline) {
                // 已记录的时长 / 尺寸可直接使用；探测失败则标记离线
                if (!m.duration && m.type !== 'image') await probeMedia(asset).catch(() => { m.offline = true; missing.push(m.name) })
            }
            this.attachAsset(asset)
        }
        if (missing.length) setTimeout(() => toast(`找不到 ${missing.length} 个媒体文件：${missing.slice(0, 3).join('、')}。可在媒体面板右键“重新链接”。`, 'warn', 6000), 400)
        this.afterLoad()
    }

    // ---------- 导出 ----------
    exports() {
        return [
            { ext: 'mp4', name: 'MP4 视频（H.264 + AAC）', write: () => this.runExport({ container: 'mp4' }) },
            { ext: 'webm', name: 'WebM 视频（VP9 + Opus）', write: () => this.runExport({ container: 'webm' }) },
            { ext: 'wav', name: 'WAV 音频', write: () => this.runAudioExport('wav') },
            { ext: 'm4a', name: 'M4A 音频（AAC）', write: () => this.runAudioExport('m4a') },
            { ext: 'png', name: '当前帧 PNG 图片', write: async () => (await import('./export.js')).framePNG(this, this.time) },
        ]
    }
    exportSettings() { return this._exportOpts ?? { quality: 'high', scale: 1, audio: true } }

    async runExport(opts) {
        if (!this.proj.clips.length) throw new Error('时间线为空')
        const { exportVideo, progressDialog } = await import('./export.js')
        const s = { ...this.exportSettings(), ...opts }
        if (this.playing) this.pause()
        const prog = progressDialog(`导出 ${opts.container === 'webm' ? 'WebM' : 'MP4'}`)
        this.busy = true
        try {
            return await exportVideo(this, { ...s, width: this.proj.width * (s.scale ?? 1), height: this.proj.height * (s.scale ?? 1) }, prog)
        } finally { this.busy = false; prog.close() }
    }
    async runAudioExport(kind) {
        const { exportAudio, progressDialog } = await import('./export.js')
        if (this.playing) this.pause()
        const prog = progressDialog('导出音频')
        this.busy = true
        try { return await exportAudio(this, kind, prog) } finally { this.busy = false; prog.close() }
    }
    // 导出对话框：格式 / 质量 / 分辨率
    async exportDialog() {
        if (!this.proj.clips.length) return toast('时间线为空，请先导入媒体', 'warn')
        const cur = this.exportSettings()
        const p = this.proj
        const v = await formDialog({
            title: '导出视频', width: 440, okText: '导出…',
            fields: [
                { key: 'fmt', label: '格式', type: 'select', value: cur.fmt ?? 'mp4', options: [['mp4', 'MP4（H.264 + AAC）'], ['webm', 'WebM（VP9 + Opus）'], ['wav', '仅音频 WAV'], ['m4a', '仅音频 M4A'], ['png', '当前帧 PNG']] },
                { key: 'scale', label: '分辨率', type: 'select', value: cur.scale ?? 1, options: [[1, `${p.width} × ${p.height}（原始）`], [0.6667, `${even(p.width * 2 / 3)} × ${even(p.height * 2 / 3)}`], [0.5, `${even(p.width / 2)} × ${even(p.height / 2)}`]] },
                { key: 'quality', label: '质量', type: 'select', value: cur.quality ?? 'high', options: [['low', '低（文件小）'], ['medium', '中'], ['high', '高'], ['very', '极高']] },
                { key: 'audio', label: '包含音频', type: 'check', value: cur.audio !== false },
                { type: 'note', label: `时长 ${fmtDur(this.duration())} · ${p.fps} fps。导出在本机逐帧渲染，时间取决于时长与分辨率。` },
            ],
        })
        if (!v) return
        this._exportOpts = { ...v, scale: Number(v.scale) }
        return this.exportAs(v.fmt)
    }

    fileItems() {
        return [
            '-',
            { label: '导入媒体…', icon: 'file-plus-2', key: 'Ctrl+I', run: () => this.importDialog() },
            { label: '导出视频…', icon: 'upload', key: 'Ctrl+E', run: () => this.exportDialog() },
            { label: '项目设置…', icon: 'settings-2', run: () => this.projectDialog() },
        ]
    }

    menus() {
        const has = () => this.sel.length > 0
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors-line-dashed', key: 'Ctrl+X', disabled: () => !has(), run: () => this.copySel(true) },
                    { label: '拷贝', icon: 'copy', key: 'Ctrl+C', disabled: () => !has(), run: () => this.copySel() },
                    { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', disabled: () => !this.clipboard, run: () => this.paste() },
                    { label: '创建副本', icon: 'copy-plus', key: 'Ctrl+D', disabled: () => !has(), run: () => this.duplicateSel() },
                    '-',
                    { label: '删除', icon: 'trash-2', key: 'Delete', altKey: 'Backspace', disabled: () => !has(), run: () => this.deleteSel() },
                    { label: '波纹删除', icon: 'trash', key: 'Shift+Delete', altKey: 'Shift+Backspace', disabled: () => !has(), run: () => this.deleteSel(true) },
                    '-',
                    { label: '全选', icon: 'list-checks', key: 'Ctrl+A', run: () => this.selectAll() },
                    { label: '取消选择', key: 'Escape', run: () => this.setSel([]) },
                ],
            },
            {
                label: '剪辑', items: () => [
                    { label: '在播放头处分割', icon: 'scissors', key: 'S', altKey: 'Ctrl+K', run: () => this.splitAtPlayhead() },
                    { label: '删除播放头左侧', icon: 'arrow-left-to-line', key: 'Q', run: () => this.trimSide('left') },
                    { label: '删除播放头右侧', icon: 'arrow-right-to-line', key: 'W', run: () => this.trimSide('right') },
                    { label: '设置入点（修剪开头）', key: 'I', disabled: () => !has(), run: () => this.markInOut('in') },
                    { label: '设置出点（修剪结尾）', key: 'O', disabled: () => !has(), run: () => this.markInOut('out') },
                    '-',
                    { label: '分离音频', icon: 'unlink', disabled: () => !has(), run: () => this.detachAudio() },
                    { label: '添加字幕', icon: 'captions', key: 'T', run: () => this.addText('subtitle') },
                    { label: '添加标题', icon: 'heading', run: () => this.addText('title') },
                    { label: '添加纯色', icon: 'square', run: () => this.addColor() },
                    '-',
                    { label: '添加视频轨道', icon: 'plus', run: () => this.addTrack('video') },
                    { label: '添加音频轨道', icon: 'plus', run: () => this.addTrack('audio') },
                    '-',
                    { label: '吸附', icon: 'magnet', checked: () => this.snapOn, key: 'N', run: () => { this.snapOn = !this.snapOn; this.updateToolbarState() } },
                ],
            },
            {
                label: '播放', items: () => [
                    { label: () => this.playing ? '暂停' : '播放', icon: 'play', key: 'Space', run: () => this.togglePlay() },
                    { label: '循环播放', checked: () => this.loop, run: () => { this.loop = !this.loop; this.updateTransport() } },
                    '-',
                    { label: '上一帧', key: 'ArrowLeft', run: () => this.stepFrames(-1) },
                    { label: '下一帧', key: 'ArrowRight', run: () => this.stepFrames(1) },
                    { label: '后退 1 秒', key: 'Shift+ArrowLeft', run: () => this.stepFrames(-this.proj.fps) },
                    { label: '前进 1 秒', key: 'Shift+ArrowRight', run: () => this.stepFrames(this.proj.fps) },
                    { label: '上一个剪辑点', key: 'ArrowUp', run: () => this.jumpEdit(-1) },
                    { label: '下一个剪辑点', key: 'ArrowDown', run: () => this.jumpEdit(1) },
                    { label: '跳到开头', key: 'Home', run: () => this.seek(0) },
                    { label: '跳到结尾', key: 'End', run: () => this.seek(this.duration()) },
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '放大时间线', icon: 'zoom-in', key: '=', run: () => this.zoomBy(1.4) },
                    { label: '缩小时间线', icon: 'zoom-out', key: '-', run: () => this.zoomBy(1 / 1.4) },
                    { label: '适合窗口', icon: 'maximize-2', key: 'Shift+Z', run: () => this.zoomFit() },
                    '-',
                    { label: '显示右侧面板', checked: () => !this.panels.classList.contains('hidden'), run: () => { this.panels.classList.toggle('hidden'); requestAnimationFrame(() => this.renderAll()) } },
                    { label: '项目设置…', icon: 'settings-2', run: () => this.projectDialog() },
                ],
            },
        ]
    }

    // 优先处理：J/K/L 穿梭、选中片段时 ←/→ 按 Alt 微移
    onKey(e) {
        if (e.target?.closest?.('input, textarea, select, [contenteditable="true"]')) return false
        if (document.querySelector('.modal-mask')) return false
        const k = keyString(e)
        if (k === 'Alt+ArrowLeft' || k === 'Alt+ArrowRight') return this.nudgeSel(k.endsWith('Left') ? -1 : 1)
        if (k === 'K') { if (this.playing) this.pause(); return true }
        if (k === 'L') { if (!this.playing) this.play(); return true }
        if (k === 'J') { this.stepFrames(-Math.round(this.proj.fps / 2)); return true }
        return false
    }

    onShow() {
        super.onShow()
        requestAnimationFrame(() => this.renderAll())
    }
    onHide() {
        super.onHide()
        if (this.playing) this.pause()
    }

    destroy() {
        this.destroyed = true
        this.disposePreview()
        for (const a of this.assets.values()) a.dispose()
        this.assets.clear()
        this.blobs.clear()
        super.destroy()
    }
}

const even = v => Math.max(2, Math.round(v / 2) * 2)
void confirmDialog; void sleep; void FPS_LIST; void clipEnd; void extOf; void baseName

installPreview(VideoEditor)
installTimeline(VideoEditor)
installOps(VideoEditor)
installPanels(VideoEditor)
