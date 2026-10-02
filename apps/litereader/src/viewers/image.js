import { Viewer } from './base.js'
import { h, fill, btn, clamp, setIcon, formatBytes, togglePopover, segmented, slider } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { siblings } from '../core/files.js'
import * as store from '../core/store.js'

// 图片查看器：缩放、拖拽、旋转、翻转、幻灯片、胶片栏
// 可接收外部提供的图片列表（例如来自压缩包）
export class ImageViewer extends Viewer {
    scale = 1
    tx = 0
    ty = 0
    rot = 0
    flipX = 1
    flipY = 1
    fit = true

    constructor(source, app, { list, index } = {}) {
        super(source, app)
        this.list = list
        this.index = index ?? 0
    }

    get title() { return this.source.parent ?? this.source.name }

    async mount() {
        this.addTitle()
        this.counter = h('span.v-progress-label', '')
        this.zoomLabel = h('span.zoom-label.static', '100%')
        this.center.append(
            btn('chevron-left', '上一张 (←)', () => this.step(-1)),
            this.counter,
            btn('chevron-right', '下一张 (→)', () => this.step(1)),
            h('span.v-sep'),
            btn('zoom-out', '缩小', () => this.zoomBy(1 / 1.2)),
            this.zoomLabel,
            btn('zoom-in', '放大', () => this.zoomBy(1.2)),
            btn('scan', '适合窗口 (0)', () => this.resetView()),
            btn('square', '原始大小 (1)', () => this.actualSize()))
        this.tool('rotate-ccw', '逆时针旋转', () => this.rotate(-90))
        this.tool('rotate-cw', '顺时针旋转 (R)', () => this.rotate(90))
        this.tool('flip-horizontal', '水平翻转', () => { this.flipX *= -1; this.apply(true) })
        this.tool('flip-vertical', '垂直翻转', () => { this.flipY *= -1; this.apply(true) })
        this.sep()
        this.playBtn = this.tool('play', '幻灯片播放 (S)', () => this.toggleSlideshow())
        this.stripBtn = this.tool('gallery-horizontal', '胶片栏', () => this.toggleStrip())
        this.bgBtn = this.tool('palette', '背景', e => togglePopover(e.currentTarget, () => this.bgPanel()))
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        this.img = h('img.iv-img', { draggable: false, alt: '' })
        this.stage = h('div.iv-stage', this.img)
        this.info = h('div.iv-info')
        this.strip = h('div.iv-strip')
        this.content.append(h('div.iv-root', this.stage,
            h('button.iv-nav.prev', { onclick: () => this.step(-1), title: '上一张' }, icon('chevron-left', 30)),
            h('button.iv-nav.next', { onclick: () => this.step(1), title: '下一张' }, icon('chevron-right', 30)),
            this.info, this.strip))
        this.applyBg()

        if (!this.list) {
            this.list = await siblings(this.source, 'image')
            this.index = Math.max(0, this.list.findIndex(s => s.path === this.source.path))
        }
        this.stripOpen = this.list.length > 1
        this.content.classList.toggle('strip-open', this.stripOpen)
        this.stripBtn.classList.toggle('active', this.stripOpen)
        this.buildStrip()
        this.bindGestures()
        await this.show(this.index)
    }

    bgPanel() {
        const cur = store.get('imageBg') ?? 'theme'
        return h('div.panel',
            h('div.panel-title', '查看背景'),
            segmented([['theme', '主题'], ['dark', '深色'], ['light', '浅色'], ['checker', '棋盘格']], cur, v => {
                store.set('imageBg', v)
                this.applyBg()
            }).el,
            slider({
                label: '幻灯片间隔', min: 1, max: 15, value: store.get('slideshowInterval'), format: v => v + ' 秒',
                oninput: v => store.set('slideshowInterval', v),
            }).el)
    }

    applyBg() {
        this.content.dataset.bg = store.get('imageBg') ?? 'theme'
    }

    buildStrip() {
        this.strip.replaceChildren()
        if (this.list.length < 2) return
        const io = new IntersectionObserver(entries => {
            for (const en of entries) {
                if (!en.isIntersecting) continue
                io.unobserve(en.target)
                const s = this.list[en.target.dataset.i]
                const im = h('img', { loading: 'lazy', decoding: 'async', src: s.url(), alt: '' })
                en.target.append(im)
            }
        }, { root: this.strip, rootMargin: '0px 400px' })
        this.onDispose(() => io.disconnect())
        this.list.forEach((s, i) => {
            const t = h('button.iv-thumb', { dataset: { i }, title: s.name, onclick: () => this.show(i) })
            this.strip.append(t)
            io.observe(t)
        })
    }

    toggleStrip() {
        this.stripOpen = !this.stripOpen
        this.content.classList.toggle('strip-open', this.stripOpen)
        this.stripBtn.classList.toggle('active', this.stripOpen)
    }

    async show(i) {
        if (!this.list.length) return
        this.index = (i + this.list.length) % this.list.length
        const s = this.list[this.index]
        this.current = s
        this.counter.textContent = `${this.index + 1} / ${this.list.length}`
        this.rot = 0; this.flipX = 1; this.flipY = 1
        this.img.classList.add('loading')
        const token = this.token = Symbol()
        const url = s.url()
        await new Promise(res => {
            this.img.onload = res
            this.img.onerror = res
            this.img.src = url
        })
        if (token !== this.token) return
        this.img.classList.remove('loading')
        if (!this.img.naturalWidth) {
            fill(this.info, h('span', `无法显示：${s.name}`))
        }
        this.resetView(false)
        this.renderInfo()
        this.app.setTabTitle?.(this, s.name)
        for (const t of this.strip.querySelectorAll('.iv-thumb.active')) t.classList.remove('active')
        const thumb = this.strip.children[this.index]
        thumb?.classList.add('active')
        thumb?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' })
        // 预加载相邻图片
        for (const d of [1, -1]) {
            const n = this.list[(this.index + d + this.list.length) % this.list.length]
            if (n && n !== s) { const pre = new Image(); pre.src = n.url() }
        }
        const nameEl = this.left.querySelector('.v-title-name')
        if (nameEl) { nameEl.textContent = s.name; nameEl.title = s.name }
        this.setSubtitle(s.parent ? `来自 ${s.parent}` : '图片')
    }

    renderInfo() {
        const s = this.current
        const w = this.img.naturalWidth, hh = this.img.naturalHeight
        fill(this.info, 
            h('span.iv-name', s.name),
            w ? h('span', `${w} × ${hh}`) : null,
            s.size ? h('span', formatBytes(s.size)) : null)
    }

    step(d) {
        if (this.list.length < 2) return
        this.show(this.index + d)
    }

    fitScale() {
        const r = this.stage.getBoundingClientRect()
        const rotated = this.rot % 180 !== 0
        const w = rotated ? this.img.naturalHeight : this.img.naturalWidth
        const hh = rotated ? this.img.naturalWidth : this.img.naturalHeight
        if (!w || !hh) return 1
        return Math.min((r.width - 40) / w, (r.height - 40) / hh, 1)
    }

    resetView(anim = true) {
        this.fit = true
        this.scale = this.fitScale()
        this.tx = 0; this.ty = 0
        this.apply(anim)
    }

    actualSize() {
        this.fit = false
        this.scale = 1
        this.tx = 0; this.ty = 0
        this.apply(true)
    }

    rotate(d) {
        this.rot += d
        if (this.fit) this.scale = this.fitScale()
        this.apply(true)
    }

    zoomBy(f, cx, cy) {
        const r = this.stage.getBoundingClientRect()
        const ox = (cx ?? r.left + r.width / 2) - (r.left + r.width / 2)
        const oy = (cy ?? r.top + r.height / 2) - (r.top + r.height / 2)
        const ns = clamp(this.scale * f, 0.02, 40)
        const k = ns / this.scale
        this.tx = ox - (ox - this.tx) * k
        this.ty = oy - (oy - this.ty) * k
        this.scale = ns
        this.fit = false
        this.apply(false)
    }

    apply(anim) {
        const w = this.img.naturalWidth, hh = this.img.naturalHeight
        this.img.style.width = w + 'px'
        this.img.style.height = hh + 'px'
        this.img.classList.toggle('anim', !!anim && store.get('animations'))
        this.img.style.transform = `translate(-50%, -50%) translate(${this.tx}px, ${this.ty}px) rotate(${this.rot}deg) scale(${this.scale * this.flipX}, ${this.scale * this.flipY})`
        this.img.classList.toggle('pixelated', this.scale > 3)
        this.zoomLabel.textContent = Math.round(this.scale * 100) + '%'
        this.stage.classList.toggle('grab', this.scale > this.fitScale() + 0.001)
    }

    bindGestures() {
        this.listen(this.stage, 'wheel', e => {
            e.preventDefault()
            if (e.ctrlKey || !this.list || this.list.length < 2 || this.scale > this.fitScale() + 0.001 || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
                this.zoomBy(e.deltaY < 0 ? 1.15 : 1 / 1.15, e.clientX, e.clientY)
            } else {
                // 未放大时滚轮切换图片
                const now = performance.now()
                if (now - (this.lastWheel ?? 0) < 180) return
                this.lastWheel = now
                this.step(e.deltaY > 0 ? 1 : -1)
            }
        }, { passive: false })
        let drag = null
        this.listen(this.stage, 'pointerdown', e => {
            if (e.button !== 0) return
            drag = { x: e.clientX, y: e.clientY, tx: this.tx, ty: this.ty, moved: false }
            this.stage.setPointerCapture(e.pointerId)
            this.stage.classList.add('dragging')
        })
        this.listen(this.stage, 'pointermove', e => {
            if (!drag) return
            const dx = e.clientX - drag.x, dy = e.clientY - drag.y
            if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true
            this.tx = drag.tx + dx
            this.ty = drag.ty + dy
            this.apply(false)
        })
        const end = e => {
            if (!drag) return
            this.stage.classList.remove('dragging')
            // 未放大时左右滑动切换图片
            if (drag.moved && this.fit) {
                const dx = e.clientX - drag.x
                if (Math.abs(dx) > 80) this.step(dx < 0 ? 1 : -1)
                else this.resetView(true)
            }
            drag = null
        }
        this.listen(this.stage, 'pointerup', end)
        this.listen(this.stage, 'pointercancel', end)
        this.listen(this.stage, 'dblclick', e => {
            if (this.fit) this.zoomBy(Math.max(2, 1 / this.scale) , e.clientX, e.clientY)
            else this.resetView(true)
        })
        const ro = new ResizeObserver(() => { if (this.fit) this.resetView(false) })
        ro.observe(this.stage)
        this.onDispose(() => ro.disconnect())
    }

    toggleSlideshow() {
        if (this.timer) {
            clearInterval(this.timer)
            this.timer = null
            setIcon(this.playBtn, 'play')
            this.playBtn.classList.remove('active')
            return
        }
        setIcon(this.playBtn, 'pause')
        this.playBtn.classList.add('active')
        this.timer = setInterval(() => this.step(1), store.get('slideshowInterval') * 1000)
    }

    onHide() {
        if (this.timer) this.toggleSlideshow()
    }

    onKey(e) {
        const k = e.key
        if (k === 'ArrowLeft' || k === 'PageUp') { this.step(-1); return true }
        if (k === 'ArrowRight' || k === 'PageDown' || k === ' ') { this.step(1); return true }
        if (k === 'Home') { this.show(0); return true }
        if (k === 'End') { this.show(this.list.length - 1); return true }
        if (k === '+' || k === '=') { this.zoomBy(1.2); return true }
        if (k === '-') { this.zoomBy(1 / 1.2); return true }
        if (k === '0') { this.resetView(); return true }
        if (k === '1') { this.actualSize(); return true }
        if (k.toLowerCase() === 'r') { this.rotate(e.shiftKey ? -90 : 90); return true }
        if (k.toLowerCase() === 's') { this.toggleSlideshow(); return true }
        return false
    }

    destroy() {
        clearInterval(this.timer)
        if (!this.ownsList) for (const s of this.list ?? []) if (s.isLocal) s.release()
        super.destroy()
    }
}
