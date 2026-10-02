// 演示文稿编辑器
import { h, fill, toast, clamp } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { contextMenu } from '../../core/menu.js'
import * as store from '../../core/store.js'
import { bytesToText } from '../../core/files.js'
import { embedFontCSS } from '../../core/fonts.js'
import { Editor } from '../base.js'
import { newDeck, newSlide, sizeOf, themeOf, newId, clone, SHAPES, htmlToText } from './model.js'
import { renderSlide, renderEl, scaledSlide } from './render.js'
import { injectSlideCSS } from './css.js'
import { buildSample } from './samples.js'
import { installInteract, bbox, unionBox } from './interact.js'
import { installUI } from './ui.js'

export class SlidesEditor extends Editor {
    static kind = 'slides'

    constructor(file, app) {
        super(file, app)
        injectSlideCSS()
        this.deck = null
        this.current = 0
        this.sel = []
        this.zoomMode = 'fit'
        this.zoomUser = 0.5
        this.clipboard = null
        this.buildLayout()
    }

    // ---------- 布局 ----------
    buildLayout() {
        this.thumbs = h('div.sl-thumbs', { tabIndex: 0 })
        this.leftbar.classList.add('sl-left')
        this.leftbar.append(
            h('div.sl-left-head',
                h('span', '幻灯片'),
                h('button.icon-btn', { title: '新建幻灯片 (Ctrl M)', onclick: e => this.newSlideMenu(e) }, icon('plus', 16))),
            this.thumbs)
        this.slideEl = h('div.sl-slide')
        this.overlay = h('div.sl-overlay')
        this.guides = h('div.sl-guides')
        this.slideHost = h('div.sl-host', this.slideEl, this.guides, this.overlay)
        this.canvasWrap = h('div.sl-canvas', { 'data-drop': '' }, this.slideHost)
        this.notesEl = h('div.sl-notes-input', { contentEditable: 'true', 'data-placeholder': '单击此处添加演讲者备注' })
        this.notesBar = h('div.sl-notes', h('div.sl-notes-head', icon('notebook-pen', 14), '备注', h('button.icon-btn', { title: '隐藏备注', onclick: () => this.toggleNotes() }, icon('chevron-down', 14))), this.notesEl)
        this.stage.classList.add('sl-stage')
        this.stage.append(h('div.sl-center', this.canvasWrap, this.notesBar))
        this.ro = new ResizeObserver(() => requestAnimationFrame(() => this.fit()))
        this.ro.observe(this.canvasWrap)
        this.onDispose(() => this.ro.disconnect())
        this.listen(this.notesEl, 'input', () => { this.slide.notes = this.notesEl.innerText.replace(/\n$/, ''); this.commit('编辑备注', { merge: 'notes' + this.slide.id }) })
        this.listen(this.canvasWrap, 'pointermove', e => { const r = this.slideHost.getBoundingClientRect(); this.mouseX = e.clientX - r.left + 14; this.mouseY = e.clientY - r.top + 14 })
        this.listen(this.canvasWrap, 'input', () => this.syncEditing())
        this.listen(document, 'selectionchange', () => { if (this.editing) this.updateFormatUI() })
        this.listen(this.canvasWrap, 'paste', e => this.onPaste(e))
        this.listen(this.canvasWrap, 'dragover', e => { if ([...e.dataTransfer.types].includes('Files')) e.preventDefault() })
        this.listen(this.canvasWrap, 'drop', e => this.onDrop(e))
        this.bindCanvas()
        this.bindThumbs()
        this.buildToolbar()
        this.buildPanels()
    }

    get slide() { return this.deck.slides[this.current] }
    selEls() { return this.sel.map(id => this.slide.els.find(e => e.id === id)).filter(Boolean) }

    // ---------- 生命周期 ----------
    async create(opts = {}) {
        const ratio = store.get('slideRatio') ?? '16:9'
        this.deck = opts.sample ? buildSample(opts.sample, ratio) : newDeck(ratio, opts.theme ?? 'clean')
        this.current = 0
        this.renderAll()
    }
    async load(bytes, ext) {
        if (ext === 'pptx') {
            const { importPPTX } = await import('./import-pptx.js')
            this.deck = await importPPTX(bytes)
        } else {
            const d = JSON.parse(bytesToText(bytes))
            if (d.format !== 'lslide' || !Array.isArray(d.slides)) throw new Error('不是有效的演示文稿文件')
            this.deck = d
        }
        if (!this.deck.slides.length) this.deck.slides.push(newSlide(this.deck, 'title'))
        this.current = 0
        this.renderAll()
    }
    snapshot() {
        // 图片 dataURL 很大：快照为 JSON 字符串，相同字符串由 JS 引擎共享
        return { deck: JSON.stringify(this.deck), current: this.current, sel: [...this.sel] }
    }
    restore(s) {
        this.stopEditing?.()
        this.deck = JSON.parse(s.deck)
        this.current = clamp(s.current, 0, this.deck.slides.length - 1)
        this.sel = s.sel.filter(id => this.slide.els.some(e => e.id === id))
        this.renderAll()
    }

    formats() {
        return [{ ext: 'lslide', name: '演示文稿', write: () => JSON.stringify(this.deck) }]
    }
    exports() {
        return [
            { ext: 'pptx', name: 'PowerPoint 演示文稿', write: () => this.exportPPTX() },
            { ext: 'pdf', name: 'PDF 文档', write: () => this.exportPDF() },
            { ext: 'png', name: '当前幻灯片 PNG', write: () => this.slidePNG(this.current) },
            { ext: 'zip', name: '全部幻灯片 PNG（ZIP）', write: () => this.allPNGZip() },
        ]
    }
    fileItems() {
        return [
            '-',
            { label: '从头开始放映', icon: 'play', key: 'F5', run: () => this.present(0) },
            { label: '打印…', icon: 'printer', key: 'Ctrl+P', run: () => this.print() },
        ]
    }

    onShow() {
        super.onShow()
        this.fit()
    }

    // 编辑中时由编辑器处理 Ctrl+B/I/U，但把撤销交给浏览器（编辑过程中的撤销）
    ownsTyping(e) {
        if (e.target === this.notesEl) return false
        return !!this.editing && /^[BIU]$/i.test(e.key) && e.ctrlKey
    }

    // ---------- 渲染 ----------
    renderAll() {
        if (!this.deck) return
        this.current = clamp(this.current, 0, this.deck.slides.length - 1)
        this.renderThumbs()
        this.renderCanvas()
        this.renderNotes()
        this.refreshPanels()
        this.updateStatus()
    }

    fitZoom() {
        const r = this.canvasWrap.getBoundingClientRect()
        const { w, h: H } = sizeOf(this.deck ?? { ratio: '16:9' })
        return Math.max(0.05, Math.min((r.width - 64) / w, (r.height - 56) / H))
    }
    fit() {
        if (!this.deck) return
        this.zoom = this.zoomMode === 'fit' ? this.fitZoom() : this.zoomUser
        this.layoutCanvas()
        this.renderOverlay()
        this.updateStatus()
    }
    setZoom(z) {
        this.zoomMode = 'user'
        this.zoomUser = clamp(z, 0.1, 3)
        this.fit()
    }
    layoutCanvas() {
        const { w, h: H } = sizeOf(this.deck)
        const k = this.zoom
        Object.assign(this.slideHost.style, { width: w * k + 'px', height: H * k + 'px' })
        Object.assign(this.slideEl.style, { width: w + 'px', height: H + 'px', transform: `scale(${k})`, transformOrigin: '0 0' })
    }

    renderCanvas({ keepOverlay } = {}) {
        if (!this.deck) return
        if (this.editing && !keepOverlay) this.stopEditing()
        const fresh = renderSlide(this.slide, this.deck, { editing: true })
        this.slideEl.replaceChildren(...fresh.childNodes)
        this.slideEl.style.background = fresh.style.background
        this.slideEl.style.fontFamily = fresh.style.fontFamily
        this.zoom ??= this.fitZoom()
        this.layoutCanvas()
        this.renderOverlay()
        if (keepOverlay) this.refreshThumbSoon()
    }

    // 选中框与控制点（屏幕坐标）
    renderOverlay() {
        const els = this.selEls()
        this.overlay.replaceChildren()
        if (!els.length || !this.deck) return
        const k = this.zoom
        if (els.length > 1) {
            for (const el of els) {
                const b = bbox(el)
                this.overlay.append(h('div.sl-sel.thin', { style: { left: b.x * k + 'px', top: b.y * k + 'px', width: b.w * k + 'px', height: b.h * k + 'px' } }))
            }
        }
        const single = els.length === 1 ? els[0] : null
        if (single && (single.shape === 'line' || single.shape === 'arrow')) {
            const box = h('div.sl-sel.line')
            this.overlay.append(box)
            for (const [key, x, y] of [['p1', single.x + (single.x1 ?? 0), single.y + (single.y1 ?? single.h / 2)], ['p2', single.x + (single.x2 ?? single.w), single.y + (single.y2 ?? single.h / 2)]]) {
                this.overlay.append(h('div.sl-handle.pt', { dataset: { h: key }, style: { left: x * k + 'px', top: y * k + 'px' } }))
            }
            return
        }
        const b = single ? { x: single.x, y: single.y, w: single.w, h: single.h } : unionBox(els)
        const frame = h('div.sl-sel' + (single?.locked ? '.locked' : ''), {
            style: {
                left: b.x * k + 'px', top: b.y * k + 'px', width: b.w * k + 'px', height: b.h * k + 'px',
                transform: single?.rot ? `rotate(${single.rot}deg)` : null,
            },
        })
        if (!single?.locked) {
            for (const hd of ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']) frame.append(h('div.sl-handle.' + hd, { dataset: { h: hd } }))
            frame.append(h('div.sl-rot-stem'), h('div.sl-handle.rot', { dataset: { h: 'rot' }, title: '旋转（Shift 以 15° 为步长）' }))
        } else frame.append(h('div.sl-lock', icon('lock', 12)))
        this.overlay.append(frame)
    }

    setSel(ids, { quiet } = {}) {
        this.sel = ids
        this.renderOverlay()
        if (!quiet) { this.refreshPanels(); this.updateStatus() }
    }

    // 修改后：重绘画布、缩略图并记录历史
    change(label, opts) {
        this.renderCanvas({ keepOverlay: !!this.editing })
        this.refreshThumb(this.current)
        this.refreshPanels()
        this.updateStatus()
        this.commit(label, opts)
    }

    // ---------- 缩略图 ----------
    renderThumbs() {
        const w = 196
        fill(this.thumbs, this.deck.slides.map((s, i) => this.thumbItem(s, i, w)))
        this.thumbs.children[this.current]?.scrollIntoView({ block: 'nearest' })
    }
    thumbItem(s, i, w = 196) {
        return h('div.sl-thumb' + (i === this.current ? '.active' : '') + (s.hidden ? '.is-hidden' : ''), { dataset: { i }, draggable: true },
            h('div.sl-thumb-num', String(i + 1), s.hidden ? icon('eye-off', 11) : null, s.transition?.type && s.transition.type !== 'none' ? icon('sparkles', 11) : null),
            h('div.sl-thumb-img', scaledSlide(s, this.deck, w)))
    }
    refreshThumb(i) {
        const old = this.thumbs.children[i]
        const s = this.deck.slides[i]
        if (!old || !s) return this.renderThumbs()
        old.replaceWith(this.thumbItem(s, i))
    }
    refreshThumbSoon() {
        clearTimeout(this.thumbT)
        this.thumbT = setTimeout(() => this.refreshThumb(this.current), 120)
    }
    bindThumbs() {
        this.listen(this.thumbs, 'click', e => {
            const t = e.target.closest('.sl-thumb')
            if (t) this.select(Number(t.dataset.i))
        })
        this.listen(this.thumbs, 'contextmenu', e => {
            const t = e.target.closest('.sl-thumb')
            if (t) this.select(Number(t.dataset.i))
            contextMenu(e, this.slideMenuItems())
        })
        let from = -1
        this.listen(this.thumbs, 'dragstart', e => { const t = e.target.closest('.sl-thumb'); from = Number(t?.dataset.i ?? -1); e.dataTransfer.effectAllowed = 'move' })
        this.listen(this.thumbs, 'dragover', e => {
            if (from < 0) return
            e.preventDefault()
            const t = e.target.closest('.sl-thumb')
            this.thumbs.querySelectorAll('.drop-before, .drop-after').forEach(x => x.classList.remove('drop-before', 'drop-after'))
            if (!t) return
            const r = t.getBoundingClientRect()
            t.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-before' : 'drop-after')
        })
        this.listen(this.thumbs, 'drop', e => {
            if (from < 0) return
            e.preventDefault()
            const t = e.target.closest('.sl-thumb')
            let to = t ? Number(t.dataset.i) + (t.classList.contains('drop-after') ? 1 : 0) : this.deck.slides.length
            this.thumbs.querySelectorAll('.drop-before, .drop-after').forEach(x => x.classList.remove('drop-before', 'drop-after'))
            if (to > from) to--
            if (to !== from) this.moveSlide(from, to)
            from = -1
        })
        this.listen(this.thumbs, 'dragend', () => { from = -1 })
        this.listen(this.thumbs, 'keydown', e => {
            if (e.key === 'ArrowDown' || e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); this.select(this.current + 1) }
            if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); this.select(this.current - 1) }
            if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); this.deleteSlide() }
        })
    }

    select(i) {
        if (!this.deck) return
        this.stopEditing()
        const n = clamp(i, 0, this.deck.slides.length - 1)
        if (n === this.current && this.thumbs.children[n]?.classList.contains('active')) return
        this.current = n
        this.sel = []
        this.thumbs.querySelectorAll('.sl-thumb.active').forEach(t => t.classList.remove('active'))
        this.thumbs.children[n]?.classList.add('active')
        this.thumbs.children[n]?.scrollIntoView({ block: 'nearest' })
        this.renderCanvas()
        this.renderNotes()
        this.refreshPanels()
        this.updateStatus()
    }

    renderNotes() {
        if (document.activeElement !== this.notesEl) this.notesEl.innerText = this.slide.notes ?? ''
    }
    toggleNotes() {
        this.notesBar.classList.toggle('collapsed')
        this.fit()
    }

    updateStatus() {
        if (!this.deck) return
        const { w, h: H } = sizeOf(this.deck)
        const els = this.selEls()
        this.statusItems(
            h('span.st-item', icon('presentation', 13), `幻灯片 ${this.current + 1} / ${this.deck.slides.length}`),
            h('span.st-item', themeOf(this.deck).name),
            h('span.st-item', `${this.deck.ratio} · ${w}×${H}`),
            els.length === 1 ? h('span.st-item', `X ${Math.round(els[0].x)}  Y ${Math.round(els[0].y)}  W ${Math.round(els[0].w)}  H ${Math.round(els[0].h)}${els[0].rot ? `  ${els[0].rot}°` : ''}`) : els.length ? h('span.st-item', `已选择 ${els.length} 个对象`) : null,
            h('span.st-flex'),
            h('button', { title: '备注', onclick: () => this.toggleNotes() }, icon('notebook-pen', 13)),
            h('button', { title: '放映 (F5)', onclick: () => this.present(this.current) }, icon('play', 13)),
            h('button', { onclick: () => this.setZoom(this.zoom / 1.2) }, icon('minus', 13)),
            h('button', { title: '适合窗口', onclick: () => { this.zoomMode = 'fit'; this.fit() } }, Math.round((this.zoom ?? 1) * 100) + '%'),
            h('button', { onclick: () => this.setZoom(this.zoom * 1.2) }, icon('plus', 13)))
    }

    // ---------- 元素操作 ----------
    makeEl(def) {
        const t = themeOf(this.deck)
        const base = { id: newId(), rot: 0, x: 200, y: 200, w: 320, h: 240 }
        if (def.type === 'text') return { ...base, type: 'text', html: '', style: { font: t.font, size: 40, color: t.text, align: 'left', valign: 'top', lineHeight: 1.35 }, ...def }
        if (def.type === 'shape') {
            const line = def.shape === 'line' || def.shape === 'arrow'
            return {
                ...base, type: 'shape', shape: 'rect',
                fill: line ? { type: 'none' } : { type: 'solid', color: t.accent },
                stroke: line ? { color: t.text, width: 6 } : { color: t.accent, width: 0 },
                radius: 28, ...def,
            }
        }
        return { ...base, ...def }
    }

    addEls(els, label) {
        this.slide.els.push(...els)
        this.sel = els.map(e => e.id)
        this.change(label)
    }

    // 复制元素（偏移 offset），返回副本
    duplicateEls(els, offset = 30) {
        const groupMap = new Map()
        const copies = els.map(el => {
            const c = clone(el)
            c.id = newId()
            c.x += offset; c.y += offset
            if (c.group) { if (!groupMap.has(c.group)) groupMap.set(c.group, newId()); c.group = groupMap.get(c.group) }
            return c
        })
        this.slide.els.push(...copies)
        this.sel = copies.map(c => c.id)
        return copies
    }

    deleteSel() {
        if (!this.sel.length) return
        const set = new Set(this.sel)
        this.slide.els = this.slide.els.filter(e => !set.has(e.id))
        this.sel = []
        this.change('删除')
    }

    // ---------- 幻灯片操作 ----------
    addSlide(layout = 'content', at = this.current + 1) {
        const s = newSlide(this.deck, layout)
        s.transition = clone(this.slide?.transition ?? { type: 'fade', dur: 0.6 })
        this.deck.slides.splice(at, 0, s)
        this.current = at
        this.sel = []
        this.renderAll()
        this.commit('新建幻灯片')
    }
    duplicateSlide(i = this.current) {
        const s = clone(this.deck.slides[i])
        s.id = newId()
        for (const e of s.els) e.id = newId()
        this.deck.slides.splice(i + 1, 0, s)
        this.current = i + 1
        this.sel = []
        this.renderAll()
        this.commit('复制幻灯片')
    }
    deleteSlide(i = this.current) {
        if (this.deck.slides.length <= 1) { toast('至少需要保留一张幻灯片'); return }
        this.deck.slides.splice(i, 1)
        this.current = Math.min(i, this.deck.slides.length - 1)
        this.sel = []
        this.renderAll()
        this.commit('删除幻灯片')
    }
    moveSlide(from, to) {
        const [s] = this.deck.slides.splice(from, 1)
        this.deck.slides.splice(to, 0, s)
        this.current = to
        this.renderAll()
        this.commit('移动幻灯片')
    }

    // ---------- 放映 ----------
    async present(start = 0, presenterView = false) {
        this.stopEditing()
        const { Presenter } = await import('./present.js')
        this.presenter = new Presenter(this, { start, presenterView })
        this.presenter.open()
    }

    // ---------- 导出 ----------
    async exportPPTX() {
        const { exportPPTX } = await import('./pptx.js')
        const { data, lost } = await exportPPTX(this.deck)
        if (lost.length) setTimeout(() => toast('PPTX 中未保留：' + lost.join('、'), 'warn', 5000), 400)
        return data
    }
    async exportPDF() {
        const { slidesHTML } = await import('./render.js')
        const { SLIDE_CSS } = await import('./css.js')
        const html = slidesHTML(this.deck, this.deck.slides.filter(s => !s.hidden), SLIDE_CSS)
        return window.lite.htmlToPdf(html, { landscape: false, pageSize: { width: sizeOf(this.deck).w / 96, height: sizeOf(this.deck).h / 96 } })
    }
    async print() {
        const { slidesHTML } = await import('./render.js')
        const { SLIDE_CSS } = await import('./css.js')
        await window.lite.printHtml(slidesHTML(this.deck, this.deck.slides.filter(s => !s.hidden), SLIDE_CSS))
    }
    // 渲染单张幻灯片为 PNG：先把 PDF 路线之外的 DOM 通过 SVG foreignObject 栅格化
    async slidePNG(i, scale = 1) {
        const { SLIDE_CSS } = await import('./css.js')
        const { w, h: H } = sizeOf(this.deck)
        const node = renderSlide(this.deck.slides[i], this.deck)
        // 内联图片以外的资源：KaTeX 字体无法在 foreignObject 中加载，公式使用系统字体近似
        const katexCSS = [...document.styleSheets].map(s => { try { return [...s.cssRules].map(r => r.cssText).filter(t => t.includes('.katex')).join('\n') } catch { return '' } }).join('\n').replace(/url\([^)]*\)/g, 'none')
        const xhtml = new XMLSerializer().serializeToString(node)
        const fontCSS = await embedFontCSS(xhtml + JSON.stringify(themeOf(this.deck)))
        const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w * scale}" height="${H * scale}"><foreignObject width="${w}" height="${H}" transform="scale(${scale})"><div xmlns="http://www.w3.org/1999/xhtml"><style>${fontCSS}${SLIDE_CSS}${katexCSS}</style>${xhtml}</div></foreignObject></svg>`
        const img = new Image()
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
        await img.decode()
        const c = document.createElement('canvas')
        c.width = w * scale; c.height = H * scale
        c.getContext('2d').drawImage(img, 0, 0)
        const blob = await new Promise(r => c.toBlob(r, 'image/png'))
        return new Uint8Array(await blob.arrayBuffer())
    }
    async allPNGZip() {
        const JSZip = (await import('jszip')).default
        const zip = new JSZip()
        for (let i = 0; i < this.deck.slides.length; i++) zip.file(`幻灯片${String(i + 1).padStart(2, '0')}.png`, await this.slidePNG(i))
        return zip.generateAsync({ type: 'uint8array' })
    }

    // 标题用于缩略图提示
    slideTitle(s) {
        const t = s.els.find(e => e.type === 'text' && e.style?.bold) ?? s.els.find(e => e.type === 'text')
        return htmlToText(t?.html ?? '') || '无标题'
    }
}

installInteract(SlidesEditor)
installUI(SlidesEditor)

export { SHAPES, renderEl }
