// 图像编辑：图层 / 选区 / 剪贴板 / 图像调整 / 滤镜 / 自由变换
import { toast, formDialog, uid } from '../../core/dom.js'
import { makeCanvas, ctx2d, cloneCanvas, newLayer, invertSelection, featherSelection, growSelection, selectionBounds, maskByLayerSelection } from './doc.js'
import { ADJUSTMENTS, FILTERS, blendBySelection } from './filters.js'
import { askImageSize, askCanvasResize, curvesDialog } from './dialogs.js'

export function installOps(Ed) {
    const P = Ed.prototype

    // ---------- 图层 ----------
    P.newLayerCmd = function () { this.addLayer(); this.commit('新建图层'); this.afterDocChange() }
    P.duplicateLayer = function () {
        const l = this.doc.activeLayer
        if (!l) return
        const copy = { ...l, id: uid('L'), name: l.name + ' 拷贝', canvas: cloneCanvas(l.canvas), mask: l.mask ? cloneCanvas(l.mask) : undefined, text: l.text ? { ...l.text } : undefined }
        this.doc.layers.splice(this.doc.layers.indexOf(l) + 1, 0, copy)
        this.doc.active = copy.id
        this.commit('复制图层')
        this.afterDocChange()
    }
    P.deleteLayer = function (id = this.doc.active) {
        if (this.doc.layers.length <= 1) return toast('至少需要保留一个图层', 'warn')
        const i = this.doc.layers.findIndex(l => l.id === id)
        if (i < 0) return
        this.doc.layers.splice(i, 1)
        this.doc.active = this.doc.layers[Math.max(0, i - 1)].id
        this.commit('删除图层')
        this.afterDocChange()
    }
    P.moveLayer = function (from, to) {
        const L = this.doc.layers
        if (to < 0 || to >= L.length || from === to) return
        const [l] = L.splice(from, 1)
        L.splice(to, 0, l)
        this.commit('调整图层顺序')
        this.afterDocChange()
    }
    P.layerOrder = function (how) {
        const L = this.doc.layers, i = L.indexOf(this.doc.activeLayer)
        const to = how === 'top' ? L.length - 1 : how === 'bottom' ? 0 : how === 'up' ? i + 1 : i - 1
        this.moveLayer(i, Math.max(0, Math.min(L.length - 1, to)))
    }
    // 把图层渲染为文档大小的画布（应用不透明度、混合、蒙版）
    P.layerAsDocCanvas = function (l, { applyProps = false } = {}) {
        const c = makeCanvas(this.doc.w, this.doc.h)
        const g = ctx2d(c)
        let src = l.canvas
        if (l.mask && l.maskEnabled !== false) { src = cloneCanvas(src); const sg = ctx2d(src); sg.globalCompositeOperation = 'destination-in'; sg.drawImage(l.mask, 0, 0) }
        if (applyProps) g.globalAlpha = l.opacity
        g.drawImage(src, l.x, l.y)
        return c
    }
    P.mergeDown = function () {
        const L = this.doc.layers, i = L.indexOf(this.doc.activeLayer)
        if (i <= 0) return toast('下方没有图层', 'warn')
        const top = L[i], below = L[i - 1]
        const base = this.layerAsDocCanvas(below)
        const g = ctx2d(base)
        g.globalAlpha = top.opacity
        g.globalCompositeOperation = compositeOf(top.blend)
        if (top.visible) g.drawImage(this.layerAsDocCanvas(top), 0, 0)
        Object.assign(below, { canvas: base, x: 0, y: 0, mask: undefined, text: undefined })
        L.splice(i, 1)
        this.doc.active = below.id
        this.commit('向下合并')
        this.afterDocChange()
    }
    P.mergeVisible = function () {
        const vis = this.doc.layers.filter(l => l.visible)
        if (vis.length < 2) return
        const merged = newLayer(this.doc.w, this.doc.h, { name: '合并的图层' })
        const tmp = { ...this.doc, layers: vis }
        this.doc.composite.call(Object.assign(Object.create(Object.getPrototypeOf(this.doc)), tmp), merged.canvas)
        const idx = this.doc.layers.indexOf(vis.at(-1))
        this.doc.layers = this.doc.layers.filter(l => !l.visible || l === vis.at(-1))
        this.doc.layers.splice(this.doc.layers.indexOf(vis.at(-1)), 1, merged)
        this.doc.active = merged.id
        this.commit('合并可见图层')
        this.afterDocChange()
        void idx
    }
    P.flattenImage = function () {
        const flat = newLayer(this.doc.w, this.doc.h, { name: '背景' })
        this.doc.composite(flat.canvas, { background: '#ffffff' })
        this.doc.layers = [flat]
        this.doc.active = flat.id
        this.commit('拼合图像')
        this.afterDocChange()
    }
    P.setLayerProp = function (id, patch, label = '图层属性', merge) {
        const l = this.doc.layerById(id)
        if (!l) return
        Object.assign(l, patch)
        this.render()
        this.commit(label, merge ? { merge } : undefined)
        this.refreshPanels()
    }
    P.renameLayer = async function (id = this.doc.active) {
        const l = this.doc.layerById(id)
        const r = await formDialog({ title: '图层属性', fields: [{ key: 'name', label: '名称', value: l.name }] })
        if (r?.name) this.setLayerProp(id, { name: r.name }, '重命名图层')
    }
    P.addMask = function (fromSel = true) {
        const l = this.doc.activeLayer
        if (!l) return
        const m = makeCanvas(l.canvas.width, l.canvas.height)
        const g = ctx2d(m)
        if (fromSel && this.doc.selection) g.drawImage(this.doc.selection, -l.x, -l.y)
        else { g.fillStyle = '#000'; g.fillRect(0, 0, m.width, m.height) }
        l.mask = m
        l.maskEnabled = true
        this.commit('添加图层蒙版')
        this.afterDocChange()
    }
    P.applyMask = function () {
        const l = this.doc.activeLayer
        if (!l?.mask) return
        const c = this.doc.writable(l)
        const g = ctx2d(c)
        g.globalCompositeOperation = 'destination-in'
        g.drawImage(l.mask, 0, 0)
        l.mask = undefined
        this.commit('应用图层蒙版')
        this.afterDocChange()
    }
    P.deleteMask = function () {
        const l = this.doc.activeLayer
        if (!l?.mask) return
        l.mask = undefined
        this.commit('删除图层蒙版')
        this.afterDocChange()
    }
    P.rasterizeLayer = function () {
        const l = this.doc.activeLayer
        if (l?.text) { delete l.text; this.commit('栅格化文字'); this.refreshPanels() }
    }

    // ---------- 选区 ----------
    P.selectAll = function () {
        const m = makeCanvas(this.doc.w, this.doc.h)
        const g = ctx2d(m); g.fillStyle = '#000'; g.fillRect(0, 0, m.width, m.height)
        this.doc.selection = m
        this.selectionChanged()
        this.commit('全选')
    }
    P.deselect = function () {
        if (!this.doc.selection) return
        this.doc.selection = null
        this.selectionChanged()
        this.commit('取消选择')
    }
    P.invertSel = function () {
        this.doc.selection = invertSelection(this.doc.selection, this.doc.w, this.doc.h)
        this.selectionChanged()
        this.commit('反选')
    }
    P.selectLayerPixels = function () {
        const l = this.doc.activeLayer
        if (!l) return
        const m = makeCanvas(this.doc.w, this.doc.h)
        ctx2d(m).drawImage(l.canvas, l.x, l.y)
        this.doc.selection = m
        this.selectionChanged()
        this.commit('载入图层选区')
    }
    P.modifySelection = async function (kind) {
        if (!this.doc.selection) return toast('没有选区', 'warn')
        const label = { feather: '羽化选区', grow: '扩展选区', shrink: '收缩选区' }[kind]
        const r = await formDialog({ title: label, fields: [{ key: 'v', label: kind === 'feather' ? '羽化半径' : '量', type: 'number', value: kind === 'feather' ? 8 : 4, min: 1, max: 250, suffix: '像素' }] })
        if (!r) return
        this.doc.selection = kind === 'feather' ? featherSelection(this.doc.selection, r.v) : growSelection(this.doc.selection, kind === 'grow' ? r.v : -r.v)
        this.selectionChanged()
        this.commit(label)
    }
    P.strokeSelection = async function () {
        if (!this.doc.selection) return toast('没有选区', 'warn')
        const r = await formDialog({ title: '描边', fields: [{ key: 'w', label: '宽度', type: 'number', value: 4, min: 1, max: 100, suffix: '像素' }, { key: 'color', label: '颜色', type: 'color', value: this.fg }] })
        if (!r) return
        const l = this.editableLayer()
        if (!l) return
        // 描边：扩展选区 - 收缩选区
        const outer = growSelection(this.doc.selection, Math.ceil(r.w / 2)), inner = growSelection(this.doc.selection, -Math.floor(r.w / 2))
        const ring = cloneCanvas(outer)
        const rg = ctx2d(ring)
        rg.globalCompositeOperation = 'destination-out'; rg.drawImage(inner, 0, 0)
        rg.globalCompositeOperation = 'source-in'; rg.fillStyle = r.color; rg.fillRect(0, 0, ring.width, ring.height)
        ctx2d(this.doc.writable(l)).drawImage(ring, -l.x, -l.y)
        this.commit('描边')
        this.render()
    }
    P.fillSelection = function (useBg) {
        const l = this.editableLayer()
        if (!l) return
        const c = this.doc.writable(l)
        const g = ctx2d(c)
        const color = useBg ? this.bg : this.fg
        if (this.doc.selection) {
            const f = cloneCanvas(this.doc.selection)
            const fg = ctx2d(f); fg.globalCompositeOperation = 'source-in'; fg.fillStyle = color; fg.fillRect(0, 0, f.width, f.height)
            g.drawImage(f, -l.x, -l.y)
        } else { g.fillStyle = color; g.fillRect(0, 0, c.width, c.height) }
        this.commit(useBg ? '填充背景色' : '填充前景色')
        this.render()
        this.refreshLayerThumbs?.()
    }
    P.clearSelection = function () {
        const l = this.editableLayer()
        if (!l) return
        const c = this.doc.writable(l)
        const g = ctx2d(c)
        if (this.doc.selection) { g.globalCompositeOperation = 'destination-out'; g.drawImage(this.doc.selection, -l.x, -l.y); g.globalCompositeOperation = 'source-over' }
        else g.clearRect(0, 0, c.width, c.height)
        this.commit('清除')
        this.render()
        this.refreshLayerThumbs?.()
    }

    // ---------- 剪贴板 ----------
    P.copySel = async function (cut = false, merged = false) {
        const l = this.doc.activeLayer
        if (!l) return
        const src = merged ? this.doc.composite() : this.layerAsDocCanvas(l)
        let c = maskByLayerSelection(src, this.doc.selection, 0, 0)
        const b = this.selBounds ?? (merged ? { x: 0, y: 0, w: this.doc.w, h: this.doc.h } : null) ?? selectionBounds(c) ?? { x: 0, y: 0, w: this.doc.w, h: this.doc.h }
        const out = makeCanvas(b.w, b.h)
        ctx2d(out).drawImage(c, -b.x, -b.y)
        this.clip = { canvas: out, x: b.x, y: b.y }
        try {
            const blob = await new Promise(r => out.toBlob(r, 'image/png'))
            await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })])
        } catch { /* 系统剪贴板不可用时仅保留内部剪贴板 */ }
        if (cut) this.clearSelection()
        toast(cut ? '已剪切' : '已复制')
    }
    P.pasteClip = async function (inPlace = true) {
        let src = null, x = null, y = null
        try {
            const items = await navigator.clipboard.read()
            for (const it of items) {
                const t = it.types.find(t => t.startsWith('image/'))
                if (t) { src = await createImageBitmap(await it.getType(t)); break }
            }
        } catch { /* ignore */ }
        // 系统剪贴板中的图片与内部剪贴板尺寸一致时视为同一内容（保留原位置）
        if (this.clip && (!src || (src.width === this.clip.canvas.width && src.height === this.clip.canvas.height))) { src = this.clip.canvas; if (inPlace) { x = this.clip.x; y = this.clip.y } }
        if (!src) return toast('剪贴板中没有图像')
        const l = newLayer(src.width, src.height, { name: '粘贴的图层', x: x ?? Math.round((this.doc.w - src.width) / 2), y: y ?? Math.round((this.doc.h - src.height) / 2) })
        ctx2d(l.canvas).drawImage(src, 0, 0)
        this.doc.layers.splice(this.doc.layers.indexOf(this.doc.activeLayer) + 1, 0, l)
        this.doc.active = l.id
        this.doc.selection = null
        this.selectionChanged()
        this.commit('粘贴')
        this.afterDocChange()
    }

    // ---------- 图像 / 画布 ----------
    P.cropTo = function (r) {
        r = { x: Math.max(0, r.x), y: Math.max(0, r.y), w: r.w, h: r.h }
        r.w = Math.min(r.w, this.doc.w - r.x); r.h = Math.min(r.h, this.doc.h - r.y)
        if (r.w < 1 || r.h < 1) return
        for (const l of this.doc.layers) { l.x -= r.x; l.y -= r.y }
        this.doc.w = r.w; this.doc.h = r.h
        if (this.doc.selection) { const s = makeCanvas(r.w, r.h); ctx2d(s).drawImage(this.doc.selection, -r.x, -r.y); this.doc.selection = null }
        this.trimLayers()
        this.selectionChanged()
        this.commit('裁剪')
        this.afterDocChange(true)
    }
    P.cropToSelection = function () {
        if (!this.selBounds) return toast('没有选区', 'warn')
        this.cropTo(this.selBounds)
    }
    // 修整：裁掉四周的透明像素
    P.trimTransparent = function () {
        const b = selectionBounds(this.doc.composite())
        if (!b) return toast('图像为空', 'warn')
        this.cropTo(b)
    }
    // 把超出画布的图层像素裁掉（节省内存）
    P.trimLayers = function () {
        for (const l of this.doc.layers) {
            if (l.text) continue
            if (l.x >= 0 && l.y >= 0 && l.x + l.canvas.width <= this.doc.w && l.y + l.canvas.height <= this.doc.h) continue
            const c = makeCanvas(this.doc.w, this.doc.h)
            ctx2d(c).drawImage(l.canvas, l.x, l.y)
            if (l.mask) { const m = makeCanvas(this.doc.w, this.doc.h); ctx2d(m).drawImage(l.mask, l.x, l.y); l.mask = m }
            l.canvas = c; l.x = 0; l.y = 0
        }
    }
    P.imageSize = async function () {
        const r = await askImageSize(this.doc)
        if (!r) return
        const kx = r.w / this.doc.w, ky = r.h / this.doc.h
        for (const l of this.doc.layers) {
            const c = makeCanvas(Math.max(1, Math.round(l.canvas.width * kx)), Math.max(1, Math.round(l.canvas.height * ky)))
            const g = ctx2d(c)
            g.imageSmoothingEnabled = r.smooth
            g.imageSmoothingQuality = 'high'
            g.drawImage(l.canvas, 0, 0, c.width, c.height)
            if (l.mask) { const m = makeCanvas(c.width, c.height); ctx2d(m).drawImage(l.mask, 0, 0, c.width, c.height); l.mask = m }
            l.canvas = c
            l.x = Math.round(l.x * kx); l.y = Math.round(l.y * ky)
            if (l.text) { l.text = { ...l.text, x: l.text.x * kx, y: l.text.y * ky, size: l.text.size * ky } }
        }
        this.doc.w = r.w; this.doc.h = r.h
        this.doc.selection = null
        this.selectionChanged()
        this.commit('图像大小')
        this.afterDocChange(true)
    }
    P.canvasSize = async function () {
        const r = await askCanvasResize(this.doc)
        if (!r) return
        for (const l of this.doc.layers) { l.x += r.dx; l.y += r.dy; if (l.text) l.text = { ...l.text, x: l.text.x + r.dx, y: l.text.y + r.dy } }
        this.doc.w = r.w; this.doc.h = r.h
        this.doc.selection = null
        this.selectionChanged()
        this.commit('画布大小')
        this.afterDocChange(true)
    }
    // 旋转 / 翻转整个图像：deg ∈ {90, -90, 180}，flip ∈ {'h', 'v'}
    P.rotateImage = function (deg, flip) {
        const W = this.doc.w, H = this.doc.h
        const swap = Math.abs(deg) === 90
        const nw = swap ? H : W, nh = swap ? W : H
        const T = c => {
            const src = makeCanvas(W, H)
            ctx2d(src).drawImage(c.canvas, c.x, c.y)
            const out = makeCanvas(nw, nh)
            const g = ctx2d(out)
            g.translate(nw / 2, nh / 2)
            if (deg) g.rotate(deg * Math.PI / 180)
            if (flip === 'h') g.scale(-1, 1)
            if (flip === 'v') g.scale(1, -1)
            g.drawImage(src, -W / 2, -H / 2)
            return out
        }
        for (const l of this.doc.layers) {
            l.canvas = T(l)
            if (l.mask) l.mask = T({ canvas: l.mask, x: l.x, y: l.y })
            l.x = 0; l.y = 0
            delete l.text
        }
        if (this.doc.selection) this.doc.selection = T({ canvas: this.doc.selection, x: 0, y: 0 })
        this.doc.w = nw; this.doc.h = nh
        this.selectionChanged()
        this.commit(flip ? (flip === 'h' ? '水平翻转画布' : '垂直翻转画布') : `旋转画布 ${deg}°`)
        this.afterDocChange(swap)
    }
    P.flipLayer = function (dir) {
        const l = this.editableLayer()
        if (!l) return
        const c = makeCanvas(l.canvas.width, l.canvas.height)
        const g = ctx2d(c)
        g.translate(dir === 'h' ? c.width : 0, dir === 'v' ? c.height : 0)
        g.scale(dir === 'h' ? -1 : 1, dir === 'v' ? -1 : 1)
        g.drawImage(l.canvas, 0, 0)
        l.canvas = c
        this.commit(dir === 'h' ? '水平翻转图层' : '垂直翻转图层')
        this.render()
    }

    // ---------- 调整与滤镜 ----------
    // 对当前图层（选区内）应用像素函数；返回新画布
    P.processLayer = function (l, fn) {
        const src = l.canvas
        const g = ctx2d(src)
        const orig = g.getImageData(0, 0, src.width, src.height)
        const work = new ImageData(new Uint8ClampedArray(orig.data), orig.width, orig.height)
        const res = fn(work) ?? work
        let sel = null
        if (this.doc.selection) {
            const m = makeCanvas(src.width, src.height)
            ctx2d(m).drawImage(this.doc.selection, -l.x, -l.y)
            sel = ctx2d(m).getImageData(0, 0, m.width, m.height).data
        }
        blendBySelection(orig, res, sel)
        const out = makeCanvas(src.width, src.height)
        ctx2d(out).putImageData(res, 0, 0)
        return out
    }
    // 大图预览时缩小处理，确认后再全尺寸处理
    P.previewSource = function (l) {
        const max = 1600
        const k = Math.min(1, max / Math.max(l.canvas.width, l.canvas.height))
        if (k >= 1) return { canvas: l.canvas, k: 1 }
        const c = makeCanvas(l.canvas.width * k, l.canvas.height * k)
        ctx2d(c).drawImage(l.canvas, 0, 0, c.width, c.height)
        return { canvas: c, k }
    }
    P.runPixelOp = async function (def, label) {
        const l = this.editableLayer()
        if (!l) return
        if (def.instant) {
            this.busy = true
            await new Promise(r => setTimeout(r, 10))
            l.canvas = this.processLayer(l, id => def.apply(id, {}))
            this.busy = false
            this.commit(label)
            this.render()
            this.refreshLayerThumbs?.()
            return
        }
        const scale = def.fields?.some(f => ['r', 'dist', 's', 'size'].includes(f.key))
        const src = this.previewSource(l)
        const previewLayer = { ...l, canvas: src.canvas }
        let values
        const run = (v, layer) => this.processLayer(layer, id => def.apply(id, scale && layer === previewLayer ? scaleVals(v, src.k) : v))
        const showPreview = v => {
            cancelAnimationFrame(this.previewRaf)
            this.previewRaf = requestAnimationFrame(() => {
                const c = run(v, previewLayer)
                let full = c
                if (src.k < 1) { full = makeCanvas(l.canvas.width, l.canvas.height); const fg = ctx2d(full); fg.imageSmoothingQuality = 'high'; fg.drawImage(c, 0, 0, full.width, full.height) }
                this.preview = { id: l.id, canvas: full }
                this.render()
            })
        }
        if (def.custom === 'curves') {
            const hist = histogram(l.canvas)
            values = await curvesDialog((points, channel) => showPreview({ points, channel }), hist)
        } else {
            values = await formDialog({ title: label, width: 440, fields: def.fields, onChange: showPreview })
        }
        cancelAnimationFrame(this.previewRaf)
        this.preview = null
        if (!values) return this.render()
        this.busy = true
        toast('正在处理…')
        await new Promise(r => setTimeout(r, 30))
        try { l.canvas = run(values, l) } finally { this.busy = false }
        this.commit(label)
        this.render()
        this.refreshLayerThumbs?.()
        this.lastFilter = { def, values, label }
    }
    P.adjust = function (key) { return this.runPixelOp(ADJUSTMENTS[key], ADJUSTMENTS[key].label) }
    P.filter = function (key) { return this.runPixelOp(FILTERS[key], FILTERS[key].label) }
    // 不经对话框直接应用（isFilter 为 true 时从滤镜表查找）
    P.applyNamed = function (key, values = {}, isFilter = false) {
        const def = (isFilter ? FILTERS : ADJUSTMENTS)[key]
        const l = this.editableLayer()
        if (!def || !l) return
        l.canvas = this.processLayer(l, id => def.apply(id, values))
        this.commit(def.label)
        this.render()
        this.refreshLayerThumbs?.()
    }
    P.repeatFilter = function () {
        const f = this.lastFilter
        if (!f) return toast('还没有使用过滤镜')
        const l = this.editableLayer()
        if (!l) return
        l.canvas = this.processLayer(l, id => f.def.apply(id, f.values))
        this.commit(f.label)
        this.render()
    }

    // ---------- 自由变换 ----------
    // 把选区内容浮动为独立图层后进入变换
    P.floatSelection = function () {
        const l = this.editableLayer()
        if (!l || !this.doc.selection) return l
        const b = this.selBounds
        if (!b) return l
        const piece = makeCanvas(b.w, b.h)
        const pg = ctx2d(piece)
        pg.drawImage(l.canvas, l.x - b.x, l.y - b.y)
        pg.globalCompositeOperation = 'destination-in'
        pg.drawImage(this.doc.selection, -b.x, -b.y)
        // 从原图层挖掉
        const c = this.doc.writable(l)
        const g = ctx2d(c)
        g.globalCompositeOperation = 'destination-out'
        g.drawImage(this.doc.selection, -l.x, -l.y)
        const fl = newLayer(b.w, b.h, { name: l.name + '（浮动）', x: b.x, y: b.y })
        ctx2d(fl.canvas).drawImage(piece, 0, 0)
        this.doc.layers.splice(this.doc.layers.indexOf(l) + 1, 0, fl)
        this.doc.active = fl.id
        this.doc.selection = null
        this.selectionChanged()
        this.floated = true
        return fl
    }
    P.startTransform = function () {
        if (this.xf) return
        let l = this.doc.selection ? this.floatSelection() : this.editableLayer()
        if (!l) return
        // 以非透明像素的包围盒作为变换框
        const b = selectionBounds(l.canvas) ?? { x: 0, y: 0, w: l.canvas.width, h: l.canvas.height }
        const src = makeCanvas(b.w, b.h)
        ctx2d(src).drawImage(l.canvas, -b.x, -b.y)
        this.xf = { layer: l, src, cx: l.x + b.x + b.w / 2, cy: l.y + b.y + b.h / 2, w: b.w, h: b.h, sx: 1, sy: 1, rot: 0, orig: { canvas: l.canvas, x: l.x, y: l.y } }
        this.applyTransformPreview()
        this.buildOptionsBar()
    }
    P.startTransformMove = function (e, p) {
        this.startTransform()
        if (this.xf) this.xfDrag = { kind: 'move', a: p, cx: this.xf.cx, cy: this.xf.cy }
    }
    P.applyTransformPreview = function () {
        const t = this.xf
        const W = Math.abs(t.w * t.sx), H = Math.abs(t.h * t.sy)
        const a = t.rot, c = Math.abs(Math.cos(a)), s = Math.abs(Math.sin(a))
        const bw = Math.ceil(W * c + H * s) + 2, bh = Math.ceil(W * s + H * c) + 2
        const out = makeCanvas(bw, bh)
        const g = ctx2d(out)
        g.imageSmoothingQuality = 'high'
        g.translate(bw / 2, bh / 2)
        g.rotate(a)
        g.scale(t.sx, t.sy)
        g.drawImage(t.src, -t.w / 2, -t.h / 2)
        t.layer.canvas = out
        t.layer.x = Math.round(t.cx - bw / 2)
        t.layer.y = Math.round(t.cy - bh / 2)
        this.render()
    }
    P.xfCorners = function () {
        const t = this.xf
        const hw = t.w * t.sx / 2, hh = t.h * t.sy / 2, c = Math.cos(t.rot), s = Math.sin(t.rot)
        const pt = (x, y) => ({ x: t.cx + x * c - y * s, y: t.cy + x * s + y * c })
        return { nw: pt(-hw, -hh), n: pt(0, -hh), ne: pt(hw, -hh), e: pt(hw, 0), se: pt(hw, hh), s: pt(0, hh), sw: pt(-hw, hh), w: pt(-hw, 0), rot: pt(0, -hh - 28 / this.zoom * Math.sign(t.sy || 1)) }
    }
    P.drawTransformBox = function (g) {
        const k = this.xfCorners(), z = this.zoom
        const S = p => ({ x: this.panX + p.x * z, y: this.panY + p.y * z })
        g.save()
        g.strokeStyle = '#2563eb'; g.lineWidth = 1.5
        g.beginPath()
        for (const n of ['nw', 'ne', 'se', 'sw']) { const p = S(k[n]); n === 'nw' ? g.moveTo(p.x, p.y) : g.lineTo(p.x, p.y) }
        g.closePath(); g.stroke()
        const n = S(k.n), r = S(k.rot)
        g.beginPath(); g.moveTo(n.x, n.y); g.lineTo(r.x, r.y); g.stroke()
        for (const [key, p] of Object.entries(k)) {
            const q = S(p)
            g.fillStyle = key === 'rot' ? '#2563eb' : '#fff'
            g.beginPath()
            if (key === 'rot') g.arc(q.x, q.y, 5, 0, Math.PI * 2); else g.rect(q.x - 4, q.y - 4, 8, 8)
            g.fill(); g.stroke()
        }
        g.restore()
    }
    P.xfHit = function (p) {
        const k = this.xfCorners(), tol = 8 / this.zoom
        for (const [key, q] of Object.entries(k)) if (Math.hypot(q.x - p.x, q.y - p.y) < tol) return key
        // 框内：移动
        const t = this.xf, c = Math.cos(-t.rot), s = Math.sin(-t.rot)
        const lx = (p.x - t.cx) * c - (p.y - t.cy) * s, ly = (p.x - t.cx) * s + (p.y - t.cy) * c
        if (Math.abs(lx) <= Math.abs(t.w * t.sx) / 2 && Math.abs(ly) <= Math.abs(t.h * t.sy) / 2) return 'move'
        return 'rotate-outside'
    }
    P.xfDown = function (e, p) {
        const hit = this.xfHit(p)
        const t = this.xf
        if (hit === 'move') this.xfDrag = { kind: 'move', a: p, cx: t.cx, cy: t.cy }
        else if (hit === 'rot' || hit === 'rotate-outside') this.xfDrag = { kind: 'rot', a0: Math.atan2(p.y - t.cy, p.x - t.cx), rot: t.rot }
        else this.xfDrag = { kind: 'scale', h: hit, sx: t.sx, sy: t.sy, cx: t.cx, cy: t.cy, anchor: this.xfCorners()[{ nw: 'se', n: 's', ne: 'sw', e: 'w', se: 'nw', s: 'n', sw: 'ne', w: 'e' }[hit]] }
    }
    P.xfMove = function (e, p) {
        const d = this.xfDrag, t = this.xf
        if (!d) {
            const hit = this.xfHit(p)
            this.wrap.style.cursor = hit === 'move' ? 'move' : hit === 'rot' || hit === 'rotate-outside' ? 'alias' : 'nwse-resize'
            return
        }
        if (d.kind === 'move') { t.cx = d.cx + p.x - d.a.x; t.cy = d.cy + p.y - d.a.y }
        else if (d.kind === 'rot') {
            let r = d.rot + Math.atan2(p.y - t.cy, p.x - t.cx) - d.a0
            if (e.shiftKey) r = Math.round(r / (Math.PI / 12)) * (Math.PI / 12)
            t.rot = r
        } else {
            // 在未旋转坐标系中计算缩放
            const c = Math.cos(-t.rot), s = Math.sin(-t.rot)
            const loc = q => ({ x: q.x * c - q.y * s, y: q.x * s + q.y * c })
            const A = loc(d.anchor), Q = loc(p)
            const hx = d.h.includes('e') || d.h.includes('w'), hy = d.h.includes('n') || d.h.includes('s')
            let sx = hx ? (Q.x - A.x) / t.w * (d.h.includes('w') ? -1 : 1) : d.sx
            let sy = hy ? (Q.y - A.y) / t.h * (d.h.includes('n') ? -1 : 1) : d.sy
            if (e.shiftKey !== true && hx && hy) { const k = Math.max(Math.abs(sx), Math.abs(sy)); sx = Math.sign(sx || 1) * k; sy = Math.sign(sy || 1) * k }
            t.sx = Math.abs(sx) < 0.01 ? 0.01 * Math.sign(sx || 1) : sx
            t.sy = Math.abs(sy) < 0.01 ? 0.01 * Math.sign(sy || 1) : sy
            // 保持锚点不动：新中心 = 锚点 + 半尺寸（旋转回世界坐标）
            const hw = t.w * t.sx / 2 * (d.h.includes('w') ? -1 : 1) * (hx ? 1 : 0), hh = t.h * t.sy / 2 * (d.h.includes('n') ? -1 : 1) * (hy ? 1 : 0)
            const cr = Math.cos(t.rot), sr = Math.sin(t.rot)
            const ax = d.anchor.x, ay = d.anchor.y
            if (hx && hy) { t.cx = ax + hw * cr - hh * sr; t.cy = ay + hw * sr + hh * cr }
            else if (hx) { t.cx = ax + hw * cr; t.cy = ay + hw * sr }
            else { t.cx = ax - hh * sr; t.cy = ay + hh * cr }
        }
        this.applyTransformPreview()
    }
    P.xfUp = function () { this.xfDrag = null }
    P.commitTransform = function () {
        if (!this.xf) return
        this.xf = null
        this.xfDrag = null
        this.floated = false
        this.commit('自由变换')
        this.afterDocChange()
        this.buildOptionsBar()
        this.updateCursor()
    }
    P.cancelTransform = function () {
        const t = this.xf
        if (!t) return
        Object.assign(t.layer, t.orig)
        this.xf = null
        if (this.floated) {
            // 撤销浮动：恢复到浮动前的历史状态
            this.floated = false
            const s = this.history.current?.snap
            if (s) this.doc.restore(s)
        }
        this.afterDocChange()
        this.buildOptionsBar()
    }
    P.commitTransient = function () {
        if (this.xf) this.commitTransform()
        if (!this.textBox.hidden) this.commitText()
        if (this.poly) { this.poly = null; this.drawOverlay() }
    }
    P.cancelTransient = function () {
        if (this.xf) { this.xf = null; this.floated = false }
        this.textEdit = null
        if (this.textBox) this.textBox.hidden = true
        this.poly = null
        this.preview = null
    }

    // 数值变换（缩放 / 旋转指定值）
    P.transformDialog = async function () {
        this.startTransform()
        if (!this.xf) return
        const t = this.xf
        const r = await formDialog({
            title: '变换', fields: [
                { key: 'sx', label: '宽度', type: 'number', value: Math.round(t.sx * 100), suffix: '%' },
                { key: 'sy', label: '高度', type: 'number', value: Math.round(t.sy * 100), suffix: '%' },
                { key: 'rot', label: '旋转', type: 'number', value: Math.round(t.rot * 180 / Math.PI), suffix: '°' },
            ],
            onChange: v => { t.sx = v.sx / 100; t.sy = v.sy / 100; t.rot = v.rot * Math.PI / 180; this.applyTransformPreview() },
        })
        if (r) this.commitTransform(); else this.cancelTransform()
    }
}

const compositeOf = mode => ({ normal: 'source-over' })[mode] ?? mode
const scaleVals = (v, k) => Object.fromEntries(Object.entries(v).map(([key, val]) => [key, ['r', 'dist', 's', 'size'].includes(key) && typeof val === 'number' ? Math.max(1, val * k) : val]))
function histogram(c) {
    const d = ctx2d(c).getImageData(0, 0, c.width, c.height).data
    const hist = new Array(256).fill(0)
    const step = Math.max(1, Math.floor(d.length / 4 / 200000)) * 4
    for (let i = 0; i < d.length; i += step) if (d[i + 3]) hist[Math.round(0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2])]++
    return hist
}
