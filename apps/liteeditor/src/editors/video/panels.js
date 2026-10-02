// 右侧面板：片段属性（检查器）/ 媒体库 / 项目
import { h, fill, colorInput, select, numberInput, slider, toggle, formatBytes } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import { panel } from '../base.js'
import { fontSelect } from '../../core/fonts.js'
import { clipDur, clipName, mediaOf, fmtTC, fmtDur, FONTS, TEXT_STYLES, PRESETS } from './model.js'

const TYPE_NAMES = { video: '视频片段', audio: '音频片段', image: '图片', text: '文字', color: '纯色' }
const TYPE_ICON = { video: 'film', audio: 'audio-lines', image: 'image', text: 'type', color: 'square' }

const row = (label, ...ctl) => h('div.ep-row', h('label', label), ...ctl)
const sec = (title, ...children) => h('div.vx-sec', h('div.vx-sec-title', title), ...children)

export function installPanels(Ed) {
    const P = Ed.prototype

    P.buildPanels = function () {
        this.ptab = 'clip'
        this.pTabs = h('div.vx-ptabs')
        this.pBody = h('div.vx-pbody')
        this.panels.append(this.pTabs, this.pBody)
    }

    P.refreshPanels = function () {
        if (!this.proj || !this.pBody) return
        const tabs = [['clip', '属性', 'sliders-horizontal'], ['media', '媒体', 'folder-open'], ['project', '项目', 'clapperboard']]
        fill(this.pTabs, tabs.map(([id, l, ic]) => h('button' + (this.ptab === id ? '.active' : ''), { onclick: () => { this.ptab = id; this.refreshPanels() } }, icon(ic, 14), l)))
        const body = this.ptab === 'media' ? this.mediaPanel() : this.ptab === 'project' ? this.projectPanel() : this.clipPanel()
        fill(this.pBody, body)
    }
    // 拖动时轻量更新（仅数值显示）
    P.refreshInspectorLive = function () {
        const c = this.selClips()[0]
        const info = this.pBody.querySelector('.vx-clip-time')
        if (c && info) info.textContent = `${fmtTC(c.start, this.proj.fps)} · 时长 ${fmtDur(clipDur(c))}`
    }

    // ---------- 片段属性 ----------
    P.clipPanel = function () {
        const cs = this.selClips()
        if (!cs.length) return this.emptyPanel()
        const c = cs[0]
        const multi = cs.length > 1
        const p = this.proj
        // 修改所有选中片段；live 为连续调整（合并撤销）
        const apply = (fn, label, live) => {
            for (const x of cs) fn(x)
            this.invalidateFrames(cs.map(x => x.id))
            this.schedulePreview()
            this.drawTimeline()
            if (live) this.commit(label, { merge: 'insp-' + label })
            else this.change(label)
        }
        const num = (k, label, opts = {}) => row(label, numberInput(round(c[k] ?? 0, opts.digits ?? 2), v => apply(x => { x[k] = opts.map ? opts.map(v) : v }, label), { width: 84, ...opts }).el)
        const rng = (k, label, { min = 0, max = 1, step = 0.01, fmt = v => Math.round(v * 100) + '%' } = {}) => {
            const s = slider({ min, max, step, value: c[k] ?? 0, format: fmt, oninput: v => apply(x => { x[k] = v }, label, true) })
            return row(label, s.el, s.el.nextSibling ?? h('span'))
        }
        const out = []
        const m = mediaOf(p, c)
        out.push(h('div.vx-obj-head', icon(TYPE_ICON[c.type] ?? 'box', 16),
            h('div.vx-obj-title', h('b', multi ? `${cs.length} 个片段` : TYPE_NAMES[c.type]), h('span', multi ? '' : clipName(p, c))),
            h('button.icon-btn', { title: '删除', onclick: () => this.deleteSel() }, icon('trash-2', 15))))
        if (!multi) out.push(h('div.vx-clip-time', `${fmtTC(c.start, p.fps)} · 时长 ${fmtDur(clipDur(c))}`))

        // 文字
        if (c.type === 'text' && !multi) {
            const ta = h('textarea.input.textarea.vx-text', { rows: 3, spellcheck: false, oninput: () => apply(x => { x.text = ta.value }, '编辑文字', true) })
            ta.value = c.text ?? ''
            out.push(sec('文字', ta,
                row('字体', fontSelect(FONTS, c.font, v => apply(x => { x.font = v }, '字体'), { fmt: 'name' }).el),
                h('div.vx-grid2',
                    row('字号', numberInput(c.size, v => apply(x => { x.size = v }, '字号'), { min: 8, max: 600, width: 64 }).el),
                    row('颜色', colorInput(c.color, v => apply(x => { x.color = v }, '文字颜色', true)).el)),
                row('样式', h('div.vx-btns',
                    tbtn('bold', '加粗', c.bold, () => apply(x => { x.bold = !x.bold }, '加粗')),
                    tbtn('italic', '倾斜', c.italic, () => apply(x => { x.italic = !x.italic }, '倾斜')),
                    tbtn('sun', '阴影', c.shadow, () => apply(x => { x.shadow = !x.shadow }, '阴影')),
                    h('span.vx-sep'),
                    tbtn('align-left', '左对齐', c.align === 'left', () => apply(x => { x.align = 'left' }, '对齐')),
                    tbtn('align-center', '居中', (c.align ?? 'center') === 'center', () => apply(x => { x.align = 'center' }, '对齐')),
                    tbtn('align-right', '右对齐', c.align === 'right', () => apply(x => { x.align = 'right' }, '对齐')))),
                h('div.vx-grid2',
                    row('描边', colorInput(c.stroke || '#000000', v => apply(x => { x.stroke = v; if (!x.strokeW) x.strokeW = 4 }, '描边颜色', true)).el),
                    row('粗细', numberInput(c.strokeW ?? 0, v => apply(x => { x.strokeW = v; if (v && !x.stroke) x.stroke = '#000000' }, '描边粗细'), { min: 0, max: 40, width: 64 }).el)),
                h('div.vx-grid2',
                    row('背景', h('div.vx-inline', toggle(!!c.bg, v => apply(x => { x.bg = v ? (x.bg || '#000000') : '' }, '文字背景')), c.bg ? colorInput(c.bg, v => apply(x => { x.bg = v }, '背景颜色', true)).el : null)),
                    c.bg ? row('不透明', numberInput(Math.round((c.bgAlpha ?? 0.6) * 100), v => apply(x => { x.bgAlpha = v / 100 }, '背景不透明度'), { min: 0, max: 100, width: 64, suffix: '%' }).el) : h('span')),
                row('预设', h('div.vx-btns',
                    ...[['subtitle', '字幕'], ['title', '标题'], ['lower', '标签']].map(([k, l]) => h('button.vx-chip', { onclick: () => apply(x => { const { text, ...st } = TEXT_STYLES[k]; Object.assign(x, st); void text }, '文字预设') }, l))))))
        }
        if (c.type === 'color' && !multi) out.push(sec('颜色', row('填充', colorInput(c.color, v => apply(x => { x.color = v }, '颜色', true)).el)))

        // 时间
        const media = c.type === 'video' || c.type === 'audio'
        if (!multi) {
            out.push(sec('时间',
                h('div.vx-grid2',
                    num('start', '开始', { min: 0, step: 1 / p.fps, suffix: '秒', width: 70 }),
                    row('时长', numberInput(round(clipDur(c), 2), v => apply(x => { x.out = Math.min(x.in + v * (x.speed || 1), media ? (m?.duration ?? Infinity) : Infinity) }, '时长'), { min: 1 / p.fps, step: 0.1, width: 70, suffix: '秒' }).el)),
                media ? h('div.vx-grid2',
                    num('in', '入点', { min: 0, step: 1 / p.fps, width: 70, suffix: '秒' }),
                    num('out', '出点', { min: 0, step: 1 / p.fps, width: 70, suffix: '秒', max: m?.duration })) : null,
                media ? row('速度', select([[0.25, '0.25×'], [0.5, '0.5×'], [0.75, '0.75×'], [1, '1× 正常'], [1.25, '1.25×'], [1.5, '1.5×'], [2, '2×'], [3, '3×'], [4, '4×']], c.speed ?? 1, v => apply(x => { x.speed = Number(v) }, '速度')).el) : null))
        }

        // 画面
        if (c.type !== 'audio') {
            out.push(sec('画面',
                rng('opacity', '不透明度'),
                rng('scale', '缩放', { min: 0.1, max: 4, step: 0.01, fmt: v => Math.round(v * 100) + '%' }),
                h('div.vx-grid2', num('x', 'X', { step: 10, digits: 0, width: 64 }), num('y', 'Y', { step: 10, digits: 0, width: 64 })),
                row('旋转', numberInput(c.rot ?? 0, v => apply(x => { x.rot = v }, '旋转'), { step: 5, width: 70, suffix: '°' }).el),
                row('', h('button.vx-chip', { onclick: () => apply(x => { x.x = 0; x.y = 0; x.scale = 1; x.rot = 0 }, '重置变换') }, icon('rotate-ccw', 13), '重置'),
                    c.type === 'video' || c.type === 'image' ? h('button.vx-chip', { onclick: () => apply(x => this.fillFrame(x), '填满画面') }, icon('maximize', 13), '填满画面') : null)))
        }
        // 音频
        if (c.type === 'audio' || (c.type === 'video' && m?.hasAudio)) {
            out.push(sec('音频',
                rng('volume', '音量', { min: 0, max: 2, step: 0.01, fmt: v => Math.round(v * 100) + '%' }),
                c.type === 'video' ? row('', h('button.vx-chip', { onclick: () => this.detachAudio() }, icon('unlink', 13), c.detached ? '已分离音频' : '分离音频到音频轨')) : null))
        }
        // 转场
        out.push(sec('淡入淡出与转场',
            h('div.vx-grid2',
                row('淡入', numberInput(round(c.fadeIn ?? 0, 2), v => apply(x => { x.fadeIn = Math.max(0, v) }, '淡入'), { min: 0, step: 0.25, width: 64, suffix: '秒' }).el),
                row('淡出', numberInput(round(c.fadeOut ?? 0, 2), v => apply(x => { x.fadeOut = Math.max(0, v) }, '淡出'), { min: 0, step: 0.25, width: 64, suffix: '秒' }).el)),
            c.type !== 'audio' ? row('交叉溶解', numberInput(round(c.dissolve ?? 0, 2), v => apply(x => { x.dissolve = Math.max(0, v) }, '交叉溶解'), { min: 0, step: 0.25, width: 64, suffix: '秒' }).el) : null,
            h('div.vx-note', c.type !== 'audio' ? '交叉溶解：与同一轨道上紧邻的前一个片段叠化过渡。' : '淡入淡出作用于音量。'),
            h('div.vx-btns', ...[[0.5, '0.5 秒'], [1, '1 秒'], [2, '2 秒']].map(([v, l]) => h('button.vx-chip', { onclick: () => apply(x => { x.fadeIn = v; x.fadeOut = v }, '淡入淡出') }, '淡入淡出 ' + l)))))

        if (m && !multi) {
            out.push(sec('源文件',
                h('div.vx-src', icon(m.type === 'audio' ? 'file-audio' : m.type === 'image' ? 'file-image' : 'file-video', 15),
                    h('div', h('div.vx-src-name', m.name),
                        h('div.vx-src-meta', [m.width ? `${m.width}×${m.height}` : null, m.duration ? fmtDur(m.duration) : null, m.path ? null : '已内嵌'].filter(Boolean).join(' · '))))))
        }
        return out
    }

    P.emptyPanel = function () {
        const add = (ic, l, fn) => h('button.vx-quick-btn', { onclick: fn }, icon(ic, 18), h('span', l))
        return [
            h('div.ep-empty', '在时间线上选择片段以编辑属性。拖动片段移动，拖动两端修剪。'),
            sec('添加', h('div.vx-quick',
                add('file-video', '导入媒体', () => this.importDialog()),
                add('captions', '字幕', () => this.addText('subtitle')),
                add('heading', '标题', () => this.addText('title')),
                add('square', '纯色', () => this.addColor()))),
            sec('快捷键', h('div.vx-keys', ...[['空格', '播放 / 暂停'], ['← →', '逐帧'], ['J K L', '倒退 / 暂停 / 前进'], ['S', '在播放头处分割'], ['Del', '删除'], ['Shift+Del', '波纹删除'], ['Ctrl+D', '复制片段'], ['I / O', '设置入点 / 出点'], ['Ctrl+滚轮', '缩放时间线'], ['Alt+拖动', '不吸附']]
                .map(([k, l]) => h('div', h('kbd', k), h('span', l))))),
        ]
    }

    // ---------- 媒体库 ----------
    P.mediaPanel = function () {
        const p = this.proj
        const items = p.media.map(m => {
            const asset = this.assets.get(m.id)
            const thumb = asset?.thumbs?.[Math.floor((asset.thumbs.length - 1) / 3)]?.c
            const used = p.clips.filter(c => c.media === m.id).length
            const el = h('div.vx-media' + (m.offline ? '.offline' : ''), { draggable: true, title: m.path ?? m.name },
                h('div.vx-media-thumb', thumb ? cloneCanvas(thumb) : icon(m.type === 'audio' ? 'audio-lines' : m.type === 'image' ? 'image' : 'film', 20)),
                h('div.vx-media-info',
                    h('div.vx-media-name', m.name),
                    h('div.vx-media-meta', [m.offline ? '离线' : null, m.duration ? fmtDur(m.duration) : '图片', m.width ? `${m.width}×${m.height}` : null, used ? `使用 ${used} 次` : '未使用'].filter(Boolean).join(' · '))),
                h('button.icon-btn', { title: '添加到时间线（播放头处）', onclick: () => this.addMediaClip(m) }, icon('plus', 15)))
            el.addEventListener('dragstart', e => { e.dataTransfer.setData('application/x-lite-media', m.id); e.dataTransfer.effectAllowed = 'copy' })
            el.addEventListener('dblclick', () => this.addMediaClip(m))
            el.addEventListener('contextmenu', e => contextMenu(e, [
                { label: '添加到时间线', icon: 'plus', run: () => this.addMediaClip(m) },
                m.path ? { label: '在文件夹中显示', icon: 'folder', run: () => window.lite.showInFolder(m.path) } : null,
                m.offline ? { label: '重新链接…', icon: 'link', run: () => this.relinkMedia(m) } : null,
                '-',
                { label: used ? '移除（同时删除片段）' : '从项目中移除', icon: 'trash-2', danger: true, run: () => this.removeMedia(m) },
            ]))
            return el
        })
        const bytes = [...this.blobs.values()].reduce((s, b) => s + b.length, 0)
        return [
            h('div.vx-media-actions', h('button.btn.vx-wide', { onclick: () => this.importDialog() }, icon('file-plus-2', 15), '导入媒体…')),
            items.length ? h('div.vx-media-list', items) : h('div.ep-empty', '暂无媒体。可以把视频、音频或图片文件拖到时间线上。'),
            bytes ? h('div.vx-note', `内嵌媒体 ${formatBytes(bytes)}（将保存在项目文件中）`) : null,
        ]
    }

    // ---------- 项目 ----------
    P.projectPanel = function () {
        const p = this.proj
        const preset = PRESETS.find(x => x[2] === p.width && x[3] === p.height)?.[0] ?? 'custom'
        return [
            sec('画布',
                row('分辨率', select([...PRESETS.map(([k, l]) => [k, l]), ['custom', `自定义 ${p.width}×${p.height}`]], preset, v => {
                    const pr = PRESETS.find(x => x[0] === v)
                    if (pr) this.setCanvas({ width: pr[2], height: pr[3] })
                }).el),
                row('帧率', select([24, 25, 30, 50, 60].map(v => [v, v + ' fps']), p.fps, v => this.setCanvas({ fps: Number(v) })).el),
                row('背景', colorInput(p.bg, v => { p.bg = v; this.schedulePreview(); this.commit('背景颜色', { merge: 'bg' }) }).el),
                row('', h('button.vx-chip', { onclick: () => this.projectDialog() }, icon('settings-2', 13), '更多设置…'))),
            sec('概况', h('div.vx-stats',
                stat('时长', fmtDur(this.duration())), stat('片段', p.clips.length), stat('轨道', p.tracks.length), stat('媒体', p.media.length))),
        ]
    }
}

function stat(k, v) { return h('div.vx-stat', h('b', String(v)), h('span', k)) }
function tbtn(ic, title, on, fn) { return h('button.vx-tb' + (on ? '.on' : ''), { title, onclick: fn }, icon(ic, 14)) }
const round = (v, d) => Number(Number(v).toFixed(d))
function cloneCanvas(c) {
    const n = document.createElement('canvas')
    n.width = c.width; n.height = c.height
    n.getContext('2d').drawImage(c, 0, 0)
    return n
}
