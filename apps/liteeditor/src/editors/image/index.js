// 图像编辑器
import { h, fill, toast, clamp } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import * as store from '../../core/store.js'
import { extOf, MIME, bytesToDataURL, loadImage } from '../../core/files.js'
import { Editor } from '../base.js'
import { ImageDoc, newLayer, makeCanvas, ctx2d, cloneCanvas } from './doc.js'
import { TOOLS, DEFAULT_OPTS } from './tools.js'
import { installCanvas } from './canvas.js'
import { installOps } from './ops.js'
import { installPanels } from './panels.js'
import { installMenus } from './menus.js'

export class ImageEditor extends Editor {
    static kind = 'image'

    constructor(file, app) {
        super(file, app)
        this.doc = new ImageDoc(800, 600)
        this.tool = 'brush'
        this.opts = { ...DEFAULT_OPTS, ...store.getPref('image-opts', {}) }
        this.fg = store.getPref('image-colors', {}).fg ?? '#1e293b'
        this.bg = store.getPref('image-colors', {}).bg ?? '#ffffff'
        this.recent = store.getPref('image-colors', {}).recent ?? []
        this.zoom = 1
        this.panX = 0
        this.panY = 0
        this.buildCanvas()
        this.buildLeft()
        this.buildToolbarUI()
        this.buildPanels()
    }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        const w = opts.width ?? 1920, hh = opts.height ?? 1080
        this.doc = new ImageDoc(w, hh)
        const bg = newLayer(w, hh, { name: opts.bg ? '背景' : '图层 1' })
        if (opts.bg) { const g = ctx2d(bg.canvas); g.fillStyle = opts.bg; g.fillRect(0, 0, w, hh) }
        this.doc.layers.push(bg)
        this.doc.active = bg.id
        this.afterDocChange(true)
    }

    async load(bytes, ext) {
        if (ext === 'psd') {
            const { readPSD } = await import('./psd.js')
            const { doc, caveats } = readPSD(bytes)
            this.doc = doc
            if (caveats.length) setTimeout(() => toast('PSD：' + caveats.join('、'), 'warn', 5000), 400)
        } else {
            const src = bytesToDataURL(bytes, MIME[ext] ?? 'image/png')
            const img = await loadImage(src)
            const w = img.naturalWidth || 800, hh = img.naturalHeight || 600
            this.doc = new ImageDoc(w, hh)
            const l = newLayer(w, hh, { name: '背景' })
            ctx2d(l.canvas).drawImage(img, 0, 0, w, hh)
            this.doc.layers.push(l)
            this.doc.active = l.id
            this.srcExt = ext
        }
        this.afterDocChange(true)
    }

    snapshot() { return this.doc.snapshot() }
    restore(s) {
        this.cancelTransient?.()
        this.doc.restore(s)
        this.afterDocChange()
    }

    formats() {
        return [
            { ext: 'psd', name: 'Photoshop 文档', write: async () => (await import('./psd.js')).writePSD(this.doc) },
            { ext: 'png', name: 'PNG 图片', write: () => this.exportRaster('image/png'), lossy: 'PNG 会合并所有图层' },
            { ext: 'jpg', name: 'JPEG 图片', write: () => this.exportRaster('image/jpeg'), lossy: 'JPEG 会合并图层并丢失透明度' },
            { ext: 'webp', name: 'WebP 图片', write: () => this.exportRaster('image/webp'), lossy: 'WebP 会合并所有图层' },
        ]
    }
    exports() {
        return [{ ext: 'bmp', name: 'BMP 位图', write: () => this.exportBMP() }]
    }
    fileItems() {
        return [
            '-',
            { label: '置入图片…', icon: 'image-plus', run: () => this.placeImage() },
            { label: '导出质量…', icon: 'sliders-horizontal', run: () => this.qualityDialog() },
        ]
    }

    // 保存 PNG / JPG 时，原文件就是该格式则允许直接保存（不提示）
    async save() {
        if (!this.saveTarget && this.path && ['png', 'jpg', 'jpeg', 'webp'].includes(extOf(this.path)) && this.doc.layers.length === 1) {
            return this.writeTo(this.path)
        }
        return super.save()
    }

    async exportRaster(mime) {
        const bg = mime === 'image/jpeg' ? '#ffffff' : null
        const c = this.doc.flatten(bg)
        const q = (this.opts.quality ?? 92) / 100
        const blob = await new Promise(r => c.toBlob(r, mime, q))
        return new Uint8Array(await blob.arrayBuffer())
    }
    exportBMP() {
        const c = this.doc.flatten('#ffffff')
        const { width: w, height: hh } = c
        const d = ctx2d(c).getImageData(0, 0, w, hh).data
        const row = (w * 3 + 3) & ~3
        const size = 54 + row * hh
        const buf = new Uint8Array(size), dv = new DataView(buf.buffer)
        buf[0] = 66; buf[1] = 77
        dv.setUint32(2, size, true); dv.setUint32(10, 54, true); dv.setUint32(14, 40, true)
        dv.setInt32(18, w, true); dv.setInt32(22, hh, true); dv.setUint16(26, 1, true); dv.setUint16(28, 24, true); dv.setUint32(34, row * hh, true)
        for (let y = 0; y < hh; y++) {
            const o = 54 + (hh - 1 - y) * row
            for (let x = 0; x < w; x++) { const i = (y * w + x) * 4, p = o + x * 3; buf[p] = d[i + 2]; buf[p + 1] = d[i + 1]; buf[p + 2] = d[i] }
        }
        return buf
    }

    // 文档结构变化后刷新所有界面
    afterDocChange(fit = false) {
        this.sizeCanvas()
        if (fit) this.fitView()
        this.render()
        this.refreshPanels()
        this.updateStatus()
    }

    onShow() {
        super.onShow()
        requestAnimationFrame(() => { this.sizeCanvas(); this.render() })
    }

    // ---------- 左侧工具条 ----------
    buildLeft() {
        this.toolBtns = new Map()
        const rail = h('div.tool-rail.img-rail')
        for (const t of TOOLS) {
            if (t === '-') { rail.append(h('div.tool-sep')); continue }
            const b = h('button.tool-btn', { title: `${t.label} (${t.shift ? 'Shift+' : ''}${t.key})`, onclick: () => this.setTool(t.id) }, icon(t.icon, 18))
            this.toolBtns.set(t.id, b)
            rail.append(b)
        }
        // 前景 / 背景色
        this.fgInput = h('input', { type: 'color' })
        this.bgInput = h('input', { type: 'color' })
        this.fgSw = h('label.img-sw.fg', { title: '前景色（单击选择）' }, this.fgInput)
        this.bgSw = h('label.img-sw.bg', { title: '背景色（单击选择）' }, this.bgInput)
        this.fgInput.addEventListener('input', () => this.setColor('fg', this.fgInput.value))
        this.bgInput.addEventListener('input', () => this.setColor('bg', this.bgInput.value))
        const colors = h('div.img-colors', this.bgSw, this.fgSw,
            h('button.img-swap', { title: '交换前景 / 背景色 (X)', onclick: () => this.swapColors() }, icon('arrow-left-right', 12)),
            h('button.img-reset', { title: '默认颜色 (D)', onclick: () => this.resetColors() }, icon('rotate-ccw', 11)))
        rail.append(h('div.tool-sep'), colors)
        this.leftbar.append(rail)
        this.updateToolUI()
        this.updateColorUI()
    }

    setTool(id) {
        if (this.tool === id) return
        this.commitTransient?.()
        this.tool = id
        this.updateToolUI()
        this.buildOptionsBar()
        this.render()
    }
    updateToolUI() {
        for (const [id, b] of this.toolBtns ?? []) b.classList.toggle('active', id === this.tool)
        this.updateCursor?.()
    }
    setColor(which, c, remember = true) {
        this[which] = c
        if (remember && which === 'fg') {
            this.recent = [c, ...this.recent.filter(x => x !== c)].slice(0, 14)
        }
        store.setPref('image-colors', { fg: this.fg, bg: this.bg, recent: this.recent })
        this.updateColorUI()
    }
    swapColors() { [this.fg, this.bg] = [this.bg, this.fg]; this.setColor('fg', this.fg, false) }
    resetColors() { this.fg = '#000000'; this.bg = '#ffffff'; this.setColor('fg', this.fg, false) }
    updateColorUI() {
        this.fgSw.style.background = this.fg
        this.bgSw.style.background = this.bg
        this.fgInput.value = this.fg
        this.bgInput.value = this.bg
        this.refreshSwatches?.()
    }
    saveOpts() { store.setPref('image-opts', this.opts) }

    // ---------- 状态栏 ----------
    updateStatus() {
        const p = this.mouseDoc
        const l = this.doc.activeLayer
        this.statusItems(
            h('span.st-item', icon('image', 13), `${this.doc.w} × ${this.doc.h} 像素`),
            l ? h('span.st-item', icon('layers', 13), l.name) : null,
            p ? h('span.st-item', `X ${Math.floor(p.x)}  Y ${Math.floor(p.y)}`) : null,
            this.selBounds ? h('span.st-item', icon('square-dashed', 13), `选区 ${this.selBounds.w} × ${this.selBounds.h}`) : null,
            h('span.st-flex'),
            h('button', { title: '适合窗口 (Ctrl 0)', onclick: () => this.fitView() }, icon('maximize', 13)),
            h('button', { onclick: () => this.zoomBy(1 / 1.25) }, icon('minus', 13)),
            h('button', { title: '实际像素 (Ctrl 1)', onclick: () => this.setZoom(1) }, Math.round(this.zoom * 100) + '%'),
            h('button', { onclick: () => this.zoomBy(1.25) }, icon('plus', 13)))
    }

    // 以当前前景 / 背景色初始化新图层
    addLayer(props = {}, index) {
        const l = newLayer(this.doc.w, this.doc.h, { name: `图层 ${this.doc.layers.length + 1}`, ...props })
        const i = index ?? this.doc.layers.indexOf(this.doc.activeLayer) + 1
        this.doc.layers.splice(i, 0, l)
        this.doc.active = l.id
        return l
    }

    // 从图片（dataURL / Image）创建新图层并居中放置
    async placeImage(src) {
        if (!src) {
            const { pickImage } = await import('../../core/files.js')
            const r = await pickImage()
            if (!r) return
            src = r.img
        }
        const img = src instanceof HTMLImageElement || src instanceof HTMLCanvasElement || src instanceof ImageBitmap ? src : await loadImage(src)
        const w = img.naturalWidth ?? img.width, hh = img.naturalHeight ?? img.height
        const l = newLayer(w, hh, { name: '置入的图片', x: Math.round((this.doc.w - w) / 2), y: Math.round((this.doc.h - hh) / 2) })
        ctx2d(l.canvas).drawImage(img, 0, 0)
        const i = this.doc.layers.indexOf(this.doc.activeLayer) + 1
        this.doc.layers.splice(i, 0, l)
        this.doc.active = l.id
        this.commit('置入图片')
        this.afterDocChange()
        return l
    }

    destroy() {
        clearInterval(this.antsTimer)
        super.destroy()
    }
}

installCanvas(ImageEditor)
installOps(ImageEditor)
installPanels(ImageEditor)
installMenus(ImageEditor)

export { askCanvasSize } from './dialogs.js'
export { makeCanvas, cloneCanvas, clamp, fill }
