// 编辑操作：导入媒体、添加 / 分割 / 删除 / 复制粘贴片段、轨道管理、项目设置
import { h, toast, formDialog, prompt } from '../../core/dom.js'
import { extOf, baseName } from '../../core/files.js'
import {
    makeClip, clone, newId, newTrack, clipDur, clipEnd, splitClip, removeClip, clearRange, clipsOn, trackOf, mediaOf,
    freeSpotAfter, trackEnd, mediaTypeOf, isActive, PRESETS, FPS_LIST, TEXT_STYLES,
} from './model.js'
import { Asset, probeMedia, newMediaEntry, analyze } from './media.js'
import { compatible } from './timeline.js'

export function installOps(Ed) {
    const P = Ed.prototype

    P.clipById = function (id) { return this.proj.clips.find(c => c.id === id) }
    P.selClips = function () { return this.sel.map(id => this.clipById(id)).filter(Boolean) }
    P.setSel = function (ids) {
        this.sel = [...new Set(ids)].filter(id => this.clipById(id))
        if (this.sel.length && this.ptab !== 'clip') this.ptab = 'clip'
        this.drawTimeline()
        this.drawPreviewOverlay()
        this.refreshPanels()
        this.updateToolbarState?.()
    }
    P.selectAll = function () { this.setSel(this.proj.clips.map(c => c.id)) }

    // 修改后统一刷新 + 记录撤销
    P.change = function (label) {
        this.sel = this.sel.filter(id => this.clipById(id))
        this.invalidateFrames()
        this.renderAll()
        this.commit(label)
    }
    P.renderAll = function () {
        this.renderHeads()
        this.sizeTimeline()
        this.drawTimeline()
        this.sizePreview()
        this.renderPreview()
        this.refreshPanels()
        this.updateTransport()
        this.updateStatus()
        this.updateToolbarState?.()
    }

    // ---------- 媒体 ----------
    // 注册媒体：{ path } 或 { name, bytes }；返回媒体条目
    P.addMedia = async function ({ path, name, bytes }) {
        if (path) {
            const exist = this.proj.media.find(m => m.path === path)
            if (exist) return exist
        }
        const m = newMediaEntry({ path, name: name ?? baseName(path) })
        if (!path && bytes) this.blobs.set(m.id, bytes)
        const asset = new Asset(m, path ? null : bytes)
        await probeMedia(asset)
        this.attachAsset(asset)
        this.proj.media.push(m)
        return m
    }
    P.attachAsset = function (asset) {
        this.assets.set(asset.media.id, asset)
        asset.listeners.add(() => { this.drawTimelineSoon(); if (this.ptab === 'media') this.refreshPanelsSoon() })
        analyze(asset)
    }
    P.drawTimelineSoon = function () {
        if (this._tlRaf) return
        this._tlRaf = requestAnimationFrame(() => { this._tlRaf = 0; this.drawTimeline() })
    }
    P.refreshPanelsSoon = function () {
        clearTimeout(this._ppT)
        this._ppT = setTimeout(() => this.refreshPanels(), 300)
    }

    // 为媒体创建片段：视频放到视频轨（若有音频，音频仍随视频片段播放）
    P.addMediaClip = function (m, { start, track, commit = true } = {}) {
        const p = this.proj
        const type = m.type
        let tr = track && compatible({ type }, track) && !track.locked ? track : null
        tr ??= p.tracks.find(t => compatible({ type }, t) && !t.locked)
        if (!tr) { tr = newTrack(type === 'audio' ? 'audio' : 'video', type === 'audio' ? 'A' + (p.tracks.filter(t => t.type === 'audio').length + 1) : 'V' + (p.tracks.filter(t => t.type === 'video').length + 1)); type === 'audio' ? p.tracks.push(tr) : p.tracks.unshift(tr) }
        const dur = type === 'image' ? 5 : m.duration
        const s = start ?? freeSpotAfter(p, tr.id, this.time)
        const c = makeClip(type, { media: m.id, track: tr.id, start: Math.round(s * p.fps) / p.fps, in: 0, out: dur })
        if (type === 'image') this.fitClip(c, m)
        clearRange(p, tr.id, c.start, clipEnd(c))
        p.clips.push(c)
        this.sel = [c.id]
        if (commit) this.change('添加片段')
        return c
    }
    P.fitClip = function () { /* 默认按“适应画布”显示，缩放 = 1 */ }
    // 填满画面（裁切）
    P.fillFrame = function (c) {
        const m = mediaOf(this.proj, c)
        if (!m?.width) return
        const p = this.proj
        const kFit = Math.min(p.width / m.width, p.height / m.height)
        const kFill = Math.max(p.width / m.width, p.height / m.height)
        c.scale = +(kFill / kFit).toFixed(4)
        c.x = 0; c.y = 0
    }

    P.importDialog = async function () {
        const paths = await window.lite.openDialog({
            title: '导入媒体', multi: true,
            filters: [
                { name: '媒体文件', extensions: ['mp4', 'm4v', 'webm', 'mkv', 'mov', 'mp3', 'wav', 'ogg', 'oga', 'opus', 'flac', 'm4a', 'aac', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'] },
                { name: '所有文件', extensions: ['*'] },
            ],
        })
        if (paths?.length) await this.importPaths(paths)
    }
    P.importFiles = async function (files, opts) {
        const paths = [], blobs = []
        for (const f of files) {
            const p = window.lite.pathForFile(f)
            if (p) paths.push(p)
            else blobs.push(f)
        }
        await this.importPaths(paths, opts, blobs)
    }
    // 导入并依次放置到时间线
    P.importPaths = async function (paths, { start, track } = {}, fileBlobs = []) {
        const items = [...paths.map(p => ({ path: p })), ...fileBlobs.map(f => ({ file: f }))]
        let t = start, added = 0
        for (const it of items) {
            const name = it.path ? baseName(it.path) : it.file.name
            if (!mediaTypeOf(extOf(name))) {
                if (extOf(name) === 'lvideo' || !it.path) { toast(`不支持导入：${name}`, 'warn'); continue }
                toast(`不支持的媒体格式：${name}`, 'warn')
                continue
            }
            try {
                toast(`正在导入 ${name}…`)
                const m = await this.addMedia(it.path ? { path: it.path } : { name, bytes: new Uint8Array(await it.file.arrayBuffer()) })
                const c = this.addMediaClip(m, { start: t, track, commit: false })
                t = start != null ? clipEnd(c) : undefined
                added++
            } catch (e) {
                console.error(e)
                toast(`无法导入 ${name}：${e.message}`, 'error', 4500)
            }
        }
        if (added) {
            this.change(added > 1 ? `导入 ${added} 个媒体` : '导入媒体')
            if (this.proj.clips.length === added) this.zoomFit()
        }
    }

    P.removeMedia = function (m) {
        const p = this.proj
        p.clips = p.clips.filter(c => c.media !== m.id)
        p.media = p.media.filter(x => x !== m)
        this.change('移除媒体')
    }
    P.relinkMedia = async function (m) {
        const [path] = await window.lite.openDialog({ title: '重新链接 ' + m.name, multi: false, filters: [{ name: '媒体文件', extensions: [m.ext] }, { name: '所有文件', extensions: ['*'] }] })
        if (!path) return
        const next = { ...m, path, name: baseName(path), ext: extOf(path), offline: false }
        const asset = new Asset(next)
        try { await probeMedia(asset) } catch (e) { toast('无法读取：' + e.message, 'error'); return }
        this.assets.get(m.id)?.dispose()
        Object.assign(m, next)
        asset.media = m
        this.attachAsset(asset)
        this.change('重新链接媒体')
    }

    // ---------- 添加片段 ----------
    P.addText = function (style = 'subtitle', { start, track } = {}) {
        const p = this.proj
        const t0 = start ?? this.time
        let tr = track ? p.tracks.find(t => t.id === track) : null
        if (!tr) {
            // 最上方的视频轨在 [t0, t0+3) 空闲且其下方有画面（或整个项目为空）时使用，否则新建顶部轨道
            const top = p.tracks.find(t => t.type === 'video')
            const free = top && !top.locked && !p.clips.some(c => c.track === top.id && clipEnd(c) > t0 && c.start < t0 + 3)
            const onlyTrackWithVideo = top && p.clips.some(c => c.track === top.id && c.type !== 'text')
            if (free && !(onlyTrackWithVideo && p.tracks.filter(t => t.type === 'video').length === 1)) tr = top
            if (!tr) {
                tr = newTrack('video', 'V' + (p.tracks.filter(t => t.type === 'video').length + 1))
                p.tracks.unshift(tr)
            }
        }
        const { text, ...st } = TEXT_STYLES[style] ?? TEXT_STYLES.subtitle
        const c = makeClip('text', { ...st, text, track: tr.id, start: Math.round(t0 * p.fps) / p.fps, in: 0, out: style === 'title' ? 4 : 3 })
        if (style === 'subtitle') c.y = Math.round(p.height * 0.38)
        if (style === 'lower') { c.x = -Math.round(p.width * 0.28); c.y = Math.round(p.height * 0.3) }
        clearRange(p, tr.id, c.start, clipEnd(c))
        p.clips.push(c)
        this.sel = [c.id]
        this.ptab = 'clip'
        this.change('添加文字')
        requestAnimationFrame(() => { const ta = this.panels.querySelector('textarea'); ta?.focus(); ta?.select() })
        return c
    }
    P.addColor = function () {
        const p = this.proj
        const tr = p.tracks.find(t => t.type === 'video' && !t.locked)
        const s = freeSpotAfter(p, tr.id, this.time)
        const c = makeClip('color', { track: tr.id, start: s, in: 0, out: 3, color: '#1e293b' })
        p.clips.push(c)
        this.sel = [c.id]
        this.change('添加纯色')
    }

    // ---------- 编辑 ----------
    // 在播放头处分割：有选中则分割选中片段，否则分割所有未锁定轨道上经过播放头的片段
    P.splitAtPlayhead = function () {
        const t = Math.round(this.time * this.proj.fps) / this.proj.fps
        let targets = this.selClips().filter(c => isActive(c, t))
        if (!targets.length) targets = this.proj.clips.filter(c => isActive(c, t) && !trackOf(this.proj, c)?.locked)
        const made = []
        for (const c of targets) { const r = splitClip(this.proj, c, t); if (r) made.push(r) }
        if (!made.length) return toast('播放头处没有可以分割的片段')
        this.sel = made.map(c => c.id)
        this.change('分割')
    }
    P.deleteSel = function (ripple = false) {
        const cs = this.selClips().filter(c => !trackOf(this.proj, c)?.locked)
        if (!cs.length) return
        const p = this.proj
        for (const c of cs) {
            removeClip(p, c)
            if (ripple) {
                const d = clipDur(c)
                for (const o of p.clips) if (o.track === c.track && o.start >= c.start - 1e-4) o.start = Math.max(0, o.start - d)
            }
        }
        this.sel = []
        this.change(ripple ? '波纹删除' : '删除片段')
    }
    // 删除播放头左侧 / 右侧部分（快速裁剪）
    P.trimSide = function (side) {
        const t = this.time
        const cs = (this.sel.length ? this.selClips() : this.proj.clips).filter(c => isActive(c, t) && !trackOf(this.proj, c)?.locked)
        if (!cs.length) return toast('播放头处没有片段')
        for (const c of cs) {
            const r = splitClip(this.proj, c, t)
            if (!r) continue
            removeClip(this.proj, side === 'left' ? c : r)
        }
        this.sel = []
        this.change(side === 'left' ? '删除左侧' : '删除右侧')
    }
    P.closeGap = function (tr, t) {
        const cs = clipsOn(this.proj, tr.id)
        const prevEnd = Math.max(0, ...cs.filter(c => clipEnd(c) <= t + 1e-4).map(clipEnd))
        const next = cs.find(c => c.start >= t - 1e-4)
        if (!next) return
        const d = next.start - prevEnd
        if (d <= 1e-4) return
        for (const c of cs) if (c.start >= next.start - 1e-4) c.start -= d
        this.change('删除间隙')
    }
    P.copySel = function (cut = false) {
        const cs = this.selClips()
        if (!cs.length) return
        const t0 = Math.min(...cs.map(c => c.start))
        this.clipboard = cs.map(c => ({ ...clone(c), start: c.start - t0 }))
        Ed.clipboard = { clips: this.clipboard, media: cs.map(c => mediaOf(this.proj, c)).filter(Boolean).map(clone) }
        if (cut) this.deleteSel()
        toast(cut ? `已剪切 ${cs.length} 个片段` : `已拷贝 ${cs.length} 个片段`)
    }
    P.paste = function (track) {
        const p = this.proj
        const clips = this.clipboard
        if (!clips?.length) return
        const t = this.time
        const made = []
        const tracksSame = clips.every(c => p.tracks.some(t => t.id === c.track))
        for (const src of clips) {
            if (src.media && !p.media.some(m => m.id === src.media)) continue
            const c = { ...clone(src), id: newId('c'), start: Math.round((t + src.start) * p.fps) / p.fps }
            let tr = tracksSame && !track ? trackOf(p, c) : track
            if (!compatible(c, tr)) tr = p.tracks.find(x => compatible(c, x))
            c.track = tr.id
            clearRange(p, c.track, c.start, clipEnd(c))
            p.clips.push(c)
            made.push(c)
        }
        this.sel = made.map(c => c.id)
        this.change('粘贴')
    }
    P.duplicateSel = function () {
        const cs = this.selClips()
        if (!cs.length) return
        const p = this.proj
        const t0 = Math.min(...cs.map(c => c.start)), t1 = Math.max(...cs.map(clipEnd))
        const made = cs.map(c => {
            const n = { ...clone(c), id: newId('c'), start: c.start + (t1 - t0) }
            clearRange(p, n.track, n.start, clipEnd(n))
            p.clips.push(n)
            return n
        })
        this.sel = made.map(c => c.id)
        this.change('创建副本')
    }
    // 将视频片段的音频分离到音频轨
    P.detachAudio = function () {
        const p = this.proj
        const cs = this.selClips().filter(c => c.type === 'video' && !c.detached && mediaOf(p, c)?.hasAudio)
        if (!cs.length) return toast('选中的片段没有可分离的音频')
        const made = []
        for (const c of cs) {
            let tr = p.tracks.find(t => t.type === 'audio' && !t.locked && !p.clips.some(o => o.track === t.id && clipEnd(o) > c.start && o.start < clipEnd(c)))
            if (!tr) { tr = newTrack('audio', 'A' + (p.tracks.filter(t => t.type === 'audio').length + 1)); p.tracks.push(tr) }
            const a = { ...clone(c), id: newId('c'), type: 'audio', track: tr.id, dissolve: 0 }
            c.detached = true
            p.clips.push(a)
            made.push(a)
        }
        this.sel = made.map(c => c.id)
        this.change('分离音频')
    }
    // 标记入点 / 出点：修剪选中片段
    P.markInOut = function (which) {
        const t = this.time
        const cs = this.selClips().filter(c => isActive(c, t) || (which === 'out' && Math.abs(clipEnd(c) - t) < 1e-3))
        if (!cs.length) return toast('请先选中播放头所在的片段')
        for (const c of cs) {
            if (which === 'in') { const d = t - c.start; c.in += d * (c.speed || 1); c.start = t }
            else c.out = c.in + (t - c.start) * (c.speed || 1)
        }
        this.change(which === 'in' ? '设置入点' : '设置出点')
    }
    P.nudgeSel = function (frames) {
        const cs = this.selClips()
        if (!cs.length) return false
        const d = frames / this.proj.fps
        for (const c of cs) c.start = Math.max(0, c.start + d)
        this.change('微移片段')
        return true
    }
    // 跳到上一个 / 下一个剪辑点
    P.jumpEdit = function (dir) {
        const pts = [...new Set(this.proj.clips.flatMap(c => [c.start, clipEnd(c)]))].sort((a, b) => a - b)
        const t = this.time
        const n = dir > 0 ? pts.find(x => x > t + 1e-3) : [...pts].reverse().find(x => x < t - 1e-3)
        if (n != null) this.seek(n)
        else this.seek(dir > 0 ? this.duration() : 0)
    }

    // ---------- 轨道 ----------
    P.addTrack = function (type) {
        const p = this.proj
        const n = p.tracks.filter(t => t.type === type).length + 1
        const tr = newTrack(type, (type === 'video' ? 'V' : 'A') + n)
        if (type === 'video') p.tracks.unshift(tr)
        else p.tracks.push(tr)
        this.change('添加轨道')
    }
    P.toggleTrack = function (tr, k) {
        tr[k] = !tr[k]
        this.change({ hidden: '显示 / 隐藏轨道', muted: '静音轨道', locked: '锁定轨道' }[k])
    }
    P.renameTrack = async function (tr) {
        const v = await prompt({ title: '重命名轨道', value: tr.name })
        if (!v) return
        tr.name = v.slice(0, 12)
        this.change('重命名轨道')
    }
    P.deleteTrack = function (tr) {
        const p = this.proj
        if (p.tracks.filter(t => t.type === tr.type).length <= 1) return
        p.clips = p.clips.filter(c => c.track !== tr.id)
        p.tracks = p.tracks.filter(t => t !== tr)
        this.change('删除轨道')
    }

    // ---------- 项目 ----------
    P.setCanvas = function ({ width, height, fps, bg }) {
        const p = this.proj
        if (width) p.width = width
        if (height) p.height = height
        if (fps) {
            p.fps = fps
            for (const c of p.clips) c.start = Math.round(c.start * fps) / fps
        }
        if (bg) p.bg = bg
        this.sizePreview()
        this.change('项目设置')
    }
    P.projectDialog = async function () {
        const p = this.proj
        const preset = PRESETS.find(x => x[2] === p.width && x[3] === p.height)?.[0] ?? 'custom'
        const v = await formDialog({
            title: '项目设置', width: 440,
            fields: [
                { key: 'preset', label: '分辨率预设', type: 'select', value: preset, options: [...PRESETS.map(([k, l, w, hh]) => [k, `${l}（${w}×${hh}）`]), ['custom', '自定义']] },
                { key: 'width', label: '宽度', type: 'number', value: p.width, min: 16, max: 7680, suffix: '像素' },
                { key: 'height', label: '高度', type: 'number', value: p.height, min: 16, max: 4320, suffix: '像素' },
                { key: 'fps', label: '帧率', type: 'select', value: p.fps, options: FPS_LIST.map(f => [f, f + ' fps']) },
                { key: 'bg', label: '背景颜色', type: 'color', value: p.bg },
                { type: 'note', label: '选择预设会覆盖宽度与高度；导出时使用项目分辨率（可在导出对话框中缩放）。' },
            ],
        })
        if (!v) return
        const pr = PRESETS.find(x => x[0] === v.preset)
        let w = v.width, hh = v.height
        if (pr && v.preset !== preset) { w = pr[2]; hh = pr[3] }
        this.setCanvas({ width: Math.round(w / 2) * 2, height: Math.round(hh / 2) * 2, fps: v.fps, bg: v.bg })
    }

    // ---------- 右键菜单 ----------
    P.clipMenu = function (c) {
        const p = this.proj
        return [
            { label: '在播放头处分割', icon: 'scissors', key: 'S', disabled: () => !isActive(c, this.time), run: () => this.splitAtPlayhead() },
            { label: '删除播放头左侧', icon: 'arrow-left-to-line', key: 'Q', disabled: () => !isActive(c, this.time), run: () => this.trimSide('left') },
            { label: '删除播放头右侧', icon: 'arrow-right-to-line', key: 'W', disabled: () => !isActive(c, this.time), run: () => this.trimSide('right') },
            '-',
            { label: '剪切', icon: 'scissors-line-dashed', key: 'Ctrl+X', run: () => this.copySel(true) },
            { label: '拷贝', icon: 'copy', key: 'Ctrl+C', run: () => this.copySel() },
            { label: '创建副本', icon: 'copy-plus', key: 'Ctrl+D', run: () => this.duplicateSel() },
            '-',
            c.type === 'video' && mediaOf(p, c)?.hasAudio && !c.detached ? { label: '分离音频', icon: 'unlink', run: () => this.detachAudio() } : null,
            {
                label: '速度', icon: 'gauge', disabled: () => c.type !== 'video' && c.type !== 'audio',
                submenu: [0.25, 0.5, 1, 1.5, 2, 4].map(s => ({ label: s + '×', checked: () => (c.speed ?? 1) === s, run: () => { for (const x of this.selClips()) if (x.type === 'video' || x.type === 'audio') x.speed = s; this.change('速度') } })),
            },
            {
                label: '淡入淡出', icon: 'blend',
                submenu: [
                    { label: '淡入 1 秒', run: () => { for (const x of this.selClips()) x.fadeIn = 1; this.change('淡入') } },
                    { label: '淡出 1 秒', run: () => { for (const x of this.selClips()) x.fadeOut = 1; this.change('淡出') } },
                    { label: '交叉溶解 1 秒', disabled: () => c.type === 'audio', run: () => { for (const x of this.selClips()) x.dissolve = 1; this.change('交叉溶解') } },
                    '-',
                    { label: '清除', run: () => { for (const x of this.selClips()) { x.fadeIn = 0; x.fadeOut = 0; x.dissolve = 0 } this.change('清除转场') } },
                ],
            },
            c.type !== 'audio' ? { label: '填满画面', icon: 'maximize', run: () => { for (const x of this.selClips()) this.fillFrame(x); this.change('填满画面') } } : null,
            { label: (c.volume ?? 1) === 0 ? '取消静音' : '静音片段', icon: 'volume-x', disabled: () => c.type === 'text' || c.type === 'color' || c.type === 'image', run: () => { const v = (c.volume ?? 1) === 0 ? 1 : 0; for (const x of this.selClips()) x.volume = v; this.change('片段音量') } },
            '-',
            { label: '删除', icon: 'trash-2', key: 'Delete', danger: true, run: () => this.deleteSel() },
            { label: '波纹删除', icon: 'trash', key: 'Shift+Delete', danger: true, run: () => this.deleteSel(true) },
        ]
    }

    void h; void trackEnd
}
