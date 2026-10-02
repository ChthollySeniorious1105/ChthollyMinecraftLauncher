// 图像编辑：选项栏、图层 / 历史 / 颜色面板
import { h, fill, select, numberInput, toggle, colorInput } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import { panel } from '../base.js'
import { BLEND_MODES, makeCanvas, ctx2d } from './doc.js'
import { TOOLS } from './tools.js'
import { fontSelect } from '../../core/fonts.js'

const SWATCHES = ['#000000', '#ffffff', '#ef4444', '#f97316', '#f59e0b', '#eab308', '#84cc16', '#22c55e', '#10b981', '#06b6d4', '#0ea5e9', '#3b82f6', '#6366f1', '#8b5cf6', '#a855f7', '#d946ef', '#ec4899', '#f43f5e', '#78716c', '#64748b', '#94a3b8', '#cbd5e1', '#7c2d12', '#1e3a8a']
const FONTS = [['"Microsoft YaHei", sans-serif', '微软雅黑'], ['"SimHei", sans-serif', '黑体'], ['"SimSun", serif', '宋体'], ['"KaiTi", serif', '楷体'], ['"Segoe UI", sans-serif', 'Segoe UI'], ['Arial, sans-serif', 'Arial'], ['Georgia, serif', 'Georgia'], ['"Times New Roman", serif', 'Times New Roman'], ['Impact, sans-serif', 'Impact'], ['Consolas, monospace', 'Consolas']]

export function installPanels(Ed) {
    const P = Ed.prototype

    P.buildToolbarUI = function () {
        this.optBar = h('div.img-opts')
        this.toolbar.append(this.optBar)
        this.buildOptionsBar()
    }

    // 选项栏：随工具变化
    P.buildOptionsBar = function () {
        const o = this.opts
        const set = (k, v) => { o[k] = v; this.saveOpts(); this.drawOverlay() }
        const num = (k, label, min, max, suffix = '', width = 56) => h('label.img-opt', h('span', label), numberInput(o[k], v => set(k, v), { min, max, width, suffix }).el)
        const chk = (k, label) => h('label.img-opt', toggle(!!o[k], v => set(k, v)), h('span', label))
        const sel = (k, label, options) => h('label.img-opt', label ? h('span', label) : null, select(options, o[k], v => set(k, v)).el)
        const t = TOOLS.find(x => x.id === this.tool)
        const items = [h('span.img-opt-title', icon(t?.icon ?? 'brush', 15), t?.label ?? '')]
        const selModes = sel('selMode', '', [['new', '新选区'], ['add', '添加到选区'], ['sub', '从选区减去'], ['intersect', '与选区交叉']])
        if (this.xf) {
            items.splice(0, 1, h('span.img-opt-title', icon('scaling', 15), '自由变换'),
                h('span.img-opt-hint', '拖动控制点缩放（Shift 自由比例）· 框外拖动旋转 · Enter 确认 · Esc 取消'),
                h('button.tb-text-btn.primary', { onclick: () => this.commitTransform() }, icon('check', 14), '应用'),
                h('button.tb-text-btn', { onclick: () => this.cancelTransform() }, icon('x', 14), '取消'))
        } else switch (this.tool) {
            case 'brush': case 'eraser': case 'clone':
                items.push(num('size', '大小', 1, 2000, 'px'), num('hardness', '硬度', 0, 100, '%'), num('opacity', '不透明度', 1, 100, '%'), num('flow', '流量', 1, 100, '%'))
                if (this.tool === 'clone') items.push(chk('cloneAligned', '对齐'), h('span.img-opt-hint', 'Alt + 单击设置仿制源'))
                break
            case 'pencil': items.push(num('size', '大小', 1, 500, 'px'), num('opacity', '不透明度', 1, 100, '%')); break
            case 'blurTool': items.push(sel('blurMode', '模式', [['blur', '模糊'], ['sharpen', '锐化']]), num('size', '大小', 1, 1000, 'px'), num('strength', '强度', 1, 100, '%')); break
            case 'dodge': items.push(sel('dodgeMode', '模式', [['dodge', '减淡'], ['burn', '加深']]), num('size', '大小', 1, 1000, 'px'), num('strength', '曝光', 1, 100, '%')); break
            case 'smudge': items.push(num('size', '大小', 1, 1000, 'px'), num('strength', '强度', 1, 100, '%')); break
            case 'marquee': case 'ellipse': case 'lasso': case 'polyLasso':
                items.push(selModes, num('feather', '羽化', 0, 250, 'px'), h('span.img-opt-hint', 'Shift 添加 · Alt 减去 · Shift 拖动为正方形 / 圆'))
                break
            case 'wand': items.push(selModes, num('tolerance', '容差', 0, 255), chk('contiguous', '连续'), chk('allLayers', '对所有图层取样')); break
            case 'bucket': items.push(num('tolerance', '容差', 0, 255), num('opacity', '不透明度', 1, 100, '%'), chk('contiguous', '连续'), chk('allLayers', '所有图层')); break
            case 'gradient':
                items.push(sel('gradType', '', [['linear', '线性'], ['radial', '径向'], ['conic', '角度'], ['reflected', '对称']]),
                    num('opacity', '不透明度', 1, 100, '%'), chk('gradReverse', '反向'), chk('gradTransparent', '前景到透明'))
                break
            case 'shape':
                items.push(sel('shape', '', [['rect', '矩形'], ['ellipse', '椭圆'], ['triangle', '三角形'], ['polygon', '六边形'], ['star', '星形'], ['line', '直线'], ['arrow', '箭头']]),
                    chk('shapeFill', '填充'), chk('shapeStroke', '描边'), num('strokeWidth', '线宽', 1, 200, 'px'), num('radius', '圆角', 0, 500, 'px'))
                break
            case 'text': {
                const fontSel = fontSelect(FONTS, o.font, v => { set('font', v); this.updateTextStyle({ font: v }) })
                items.push(h('label.img-opt', fontSel.el),
                    h('label.img-opt', numberInput(o.fontSize, v => { set('fontSize', v); this.updateTextStyle({ size: v }) }, { min: 4, max: 1000, width: 60, suffix: 'px' }).el),
                    h('button.icon-btn' + (o.bold ? '.active' : ''), { title: '加粗', onclick: e => { set('bold', !o.bold); e.currentTarget.classList.toggle('active', o.bold); this.updateTextStyle({ bold: o.bold }) } }, icon('bold', 16)),
                    h('button.icon-btn' + (o.italic ? '.active' : ''), { title: '倾斜', onclick: e => { set('italic', !o.italic); e.currentTarget.classList.toggle('active', o.italic); this.updateTextStyle({ italic: o.italic }) } }, icon('italic', 16)),
                    sel('align', '', [['left', '左对齐'], ['center', '居中'], ['right', '右对齐']]),
                    h('span.img-opt-hint', '单击画布输入文字 · 双击文字图层再次编辑 · 颜色使用前景色'))
                break
            }
            case 'crop': items.push(h('span.img-opt-hint', '拖动选择裁剪区域，松开即裁剪')); break
            case 'move': items.push(h('span.img-opt-hint', '拖动移动图层 · Alt 拖动复制 · 有选区时移动选区内容 · Ctrl T 自由变换'),
                h('button.tb-text-btn', { onclick: () => this.startTransform() }, icon('scaling', 14), '自由变换')); break
            case 'picker': items.push(chk('allLayers', '对所有图层取样'), h('span.img-opt-hint', 'Alt 单击取背景色')); break
            case 'zoom': items.push(h('button.tb-text-btn', { onclick: () => this.setZoom(1) }, '100%'), h('button.tb-text-btn', { onclick: () => this.fitView() }, '适合窗口'), h('span.img-opt-hint', 'Alt 单击缩小')); break
            case 'hand': items.push(h('button.tb-text-btn', { onclick: () => this.fitView() }, '适合窗口')); break
        }
        fill(this.optBar, items)
    }
    P.updateTextStyle = function (patch) {
        if (this.textEdit) { Object.assign(this.textEdit.style, patch); this.placeTextBox() }
    }

    // ---------- 右侧面板 ----------
    P.buildPanels = function () {
        this.swatchBox = h('div.img-swatches')
        this.recentBox = h('div.img-swatches.recent')
        this.layerList = h('div.e-list.img-layers')
        this.layerProps = h('div.img-layer-props')
        this.histList = h('div.e-list.img-history')
        const actions = [
            this.tb('file-plus-2', '新建图层 (Ctrl Shift N)', () => this.newLayerCmd()),
            this.tb('copy', '复制图层 (Ctrl J)', () => this.duplicateLayer()),
            this.tb('venetian-mask', '添加图层蒙版', () => this.addMask(true)),
            this.tb('trash-2', '删除图层', () => this.deleteLayer()),
        ]
        this.panels.append(
            panel('颜色', h('div', this.swatchBox, h('div.img-recent-label', '最近使用'), this.recentBox), { icon: 'palette' }),
            panel('图层', h('div', this.layerProps, this.layerList, h('div.img-layer-actions', actions)), { icon: 'layers', cls: '.grow' }),
            panel('历史记录', this.histList, { icon: 'history', collapsed: false }))
        fill(this.swatchBox, SWATCHES.map(c => h('button.img-swatch', { style: { background: c }, title: c + '（右键设为背景色）', onclick: () => this.setColor('fg', c), oncontextmenu: e => { e.preventDefault(); this.setColor('bg', c) } })))
        this.refreshSwatches()
    }
    P.refreshSwatches = function () {
        if (!this.recentBox) return
        fill(this.recentBox, (this.recent ?? []).map(c => h('button.img-swatch', { style: { background: c }, title: c, onclick: () => this.setColor('fg', c, false) })))
    }
    P.onHistory = function () { this.refreshHistory?.() }
    P.refreshHistory = function () {
        if (!this.histList) return
        const hs = this.history
        fill(this.histList, hs.stack.map((s, i) => h('div.e-list-item' + (i === hs.index ? '.active' : '') + (i > hs.index ? '.future' : ''), { onclick: () => this.gotoHistory(i) },
            icon(i === 0 ? 'file-image' : 'circle-dot', 13), h('span.li-name', s.label))))
        this.histList.querySelector('.active')?.scrollIntoView({ block: 'nearest' })
    }

    P.refreshPanels = function () {
        if (!this.layerList) return
        const d = this.doc
        const act = d.activeLayer
        // 图层属性：混合模式 + 不透明度
        if (act) {
            const blend = select(BLEND_MODES.map(([k, l]) => [k, l]), act.blend, v => this.setLayerProp(act.id, { blend: v }, '混合模式'))
            const op = numberInput(Math.round(act.opacity * 100), v => this.setLayerProp(act.id, { opacity: v / 100 }, '不透明度', 'opacity'), { min: 0, max: 100, width: 58, suffix: '%' })
            fill(this.layerProps,
                h('div.ep-row', h('label', '混合'), blend.el),
                h('div.ep-row', h('label', '不透明度'), op.el,
                    h('button.icon-btn' + (act.locked ? '.active' : ''), { title: act.locked ? '解锁图层' : '锁定图层', onclick: () => this.setLayerProp(act.id, { locked: !act.locked }, act.locked ? '解锁图层' : '锁定图层') }, icon(act.locked ? 'lock' : 'lock-open', 14))))
        } else fill(this.layerProps)
        // 从上到下列出
        const rows = [...d.layers].reverse().map(l => {
            const idx = d.layers.indexOf(l)
            const thumb = h('canvas.img-thumb', { width: 40, height: 30 })
            this.drawThumb(thumb, l)
            const mask = l.mask ? h('canvas.img-thumb.mask' + (l.maskEnabled === false ? '.off' : ''), { width: 30, height: 30, title: '图层蒙版（单击启用 / 停用）', onclick: e => { e.stopPropagation(); this.setLayerProp(l.id, { maskEnabled: l.maskEnabled === false }, '蒙版') } }) : null
            if (mask) this.drawMaskThumb(mask, l)
            const row = h('div.e-list-item.img-layer' + (l === act ? '.active' : '') + (l.visible ? '' : '.is-hidden'), {
                draggable: true,
                onclick: () => { d.active = l.id; this.refreshPanels(); this.updateStatus() },
                ondblclick: () => this.renameLayer(l.id),
                oncontextmenu: e => { d.active = l.id; this.refreshPanels(); contextMenu(e, this.layerMenu()) },
            },
            h('button.icon-btn.img-eye', { title: l.visible ? '隐藏' : '显示', onclick: e => { e.stopPropagation(); this.setLayerProp(l.id, { visible: !l.visible }, l.visible ? '隐藏图层' : '显示图层') } }, icon(l.visible ? 'eye' : 'eye-off', 14)),
            thumb, mask,
            h('span.li-name', l.text ? [icon('type', 12), ' ', l.name] : l.name),
            l.locked ? icon('lock', 12) : null,
            l.blend !== 'normal' || l.opacity < 1 ? h('span.li-sub', l.opacity < 1 ? Math.round(l.opacity * 100) + '%' : '') : null)
            row.addEventListener('dragstart', e => { this.dragLayer = idx; e.dataTransfer.effectAllowed = 'move' })
            row.addEventListener('dragover', e => {
                if (this.dragLayer == null) return
                e.preventDefault()
                const r = row.getBoundingClientRect()
                row.classList.toggle('drag-over-top', e.clientY < r.top + r.height / 2)
                row.classList.toggle('drag-over-bottom', e.clientY >= r.top + r.height / 2)
            })
            row.addEventListener('dragleave', () => row.classList.remove('drag-over-top', 'drag-over-bottom'))
            row.addEventListener('drop', e => {
                e.preventDefault()
                const r = row.getBoundingClientRect(), above = e.clientY < r.top + r.height / 2
                row.classList.remove('drag-over-top', 'drag-over-bottom')
                const from = this.dragLayer
                this.dragLayer = null
                if (from == null) return
                let to = above ? idx + 1 : idx
                if (from < to) to--
                this.moveLayer(from, Math.max(0, Math.min(d.layers.length - 1, to)))
            })
            return row
        })
        fill(this.layerList, rows)
        this.refreshHistory()
    }
    P.refreshLayerThumbs = function () {
        clearTimeout(this.thumbT)
        this.thumbT = setTimeout(() => this.refreshPanels(), 60)
    }
    P.drawThumb = function (c, l) {
        const g = c.getContext('2d')
        const k = Math.min(c.width / this.doc.w, c.height / this.doc.h)
        const w = this.doc.w * k, hh = this.doc.h * k, ox = (c.width - w) / 2, oy = (c.height - hh) / 2
        g.fillStyle = '#fff'; g.fillRect(ox, oy, w, hh)
        g.fillStyle = '#e4e4e7'
        for (let y = 0; y < hh; y += 4) for (let x = (y / 4) % 2 ? 4 : 0; x < w; x += 8) g.fillRect(ox + x, oy + y, 4, 4)
        g.imageSmoothingQuality = 'high'
        g.drawImage(l.canvas, ox + l.x * k, oy + l.y * k, l.canvas.width * k, l.canvas.height * k)
    }
    P.drawMaskThumb = function (c, l) {
        const g = c.getContext('2d')
        g.fillStyle = '#000'; g.fillRect(0, 0, c.width, c.height)
        const tmp = makeCanvas(l.mask.width, l.mask.height)
        const tg = ctx2d(tmp); tg.drawImage(l.mask, 0, 0); tg.globalCompositeOperation = 'source-in'; tg.fillStyle = '#fff'; tg.fillRect(0, 0, tmp.width, tmp.height)
        g.drawImage(tmp, 0, 0, c.width, c.height)
    }
}

export { colorInput }
