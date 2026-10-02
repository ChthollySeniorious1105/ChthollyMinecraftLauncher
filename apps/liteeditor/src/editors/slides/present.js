// 幻灯片放映：全屏、切换效果、按点击顺序播放对象动画、黑屏 / 白屏、演讲者视图
import { h, formatTime } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { sizeOf } from './model.js'
import { renderSlide } from './render.js'

const ANIM_FROM = {
    fade: { opacity: 0 },
    flyUp: { opacity: 0, transform: 'translateY(160px)' },
    flyLeft: { opacity: 0, transform: 'translateX(-240px)' },
    flyRight: { opacity: 0, transform: 'translateX(240px)' },
    zoom: { opacity: 0, transform: 'scale(.4)' },
    bounce: { opacity: 0, transform: 'translateY(-120px) scale(.9)' },
    spin: { opacity: 0, transform: 'rotate(-180deg) scale(.3)' },
    wipe: { clipPath: 'inset(0 100% 0 0)' },
}

// 某一页的动画步骤：按 order 分组（同 order 同时播放）
export function animSteps(slide) {
    const groups = new Map()
    for (const el of slide.els) {
        if (!el.anim?.type) continue
        const k = el.anim.order ?? 1
        if (!groups.has(k)) groups.set(k, [])
        groups.get(k).push(el)
    }
    return [...groups.entries()].sort((a, b) => a[0] - b[0]).map(e => e[1])
}

export class Presenter {
    constructor(editor, { start = 0, presenterView = false } = {}) {
        this.ed = editor
        this.deck = editor.deck
        this.slides = this.deck.slides.map((s, i) => ({ s, i })).filter(x => !x.s.hidden || x.i === start)
        this.pos = Math.max(0, this.slides.findIndex(x => x.i === start))
        this.step = 0
        this.presenterView = presenterView
        this.t0 = Date.now()
        this.build()
    }

    build() {
        const { w, h: H } = sizeOf(this.deck)
        this.size = { w, h: H }
        this.stage = h('div.pr-stage')
        this.cover = h('div.pr-cover')
        this.counter = h('div.pr-counter')
        this.bar = h('div.pr-bar',
            h('button', { title: '上一页 (←)', onclick: () => this.prev() }, icon('chevron-left', 20)),
            this.counter,
            h('button', { title: '下一页 (→ / 空格)', onclick: () => this.next() }, icon('chevron-right', 20)),
            h('button', { title: '演讲者视图 (P)', onclick: () => this.togglePresenter() }, icon('monitor-speaker', 18)),
            h('button', { title: '退出放映 (Esc)', onclick: () => this.close() }, icon('x', 18)))
        this.side = h('div.pr-side')
        this.el = h('div.pr-root', { tabIndex: -1 }, h('div.pr-main', this.stage, this.cover, this.bar), this.side)
        this.el.addEventListener('click', e => { if (!e.target.closest('.pr-bar, .pr-side')) this.next() })
        this.el.addEventListener('contextmenu', e => { e.preventDefault(); this.prev() })
        this.el.addEventListener('wheel', e => { if (Math.abs(e.deltaY) > 20) (e.deltaY > 0 ? this.next() : this.prev()) }, { passive: true })
        this.el.addEventListener('mousemove', () => { this.bar.classList.add('show'); clearTimeout(this.hideT); this.hideT = setTimeout(() => this.bar.classList.remove('show'), 1800) })
        this.onKey = e => this.key(e)
        this.onResize = () => this.layout()
    }

    open() {
        document.body.append(this.el)
        document.addEventListener('keydown', this.onKey, true)
        window.addEventListener('resize', this.onResize)
        this.wasFull = document.documentElement.classList.contains('fullscreen')
        if (!this.wasFull) window.lite?.win.setFullscreen(true)
        this.el.focus()
        this.el.classList.toggle('with-side', this.presenterView)
        this.show(this.pos, 'none')
        this.timer = setInterval(() => this.updateSide(), 1000)
        requestAnimationFrame(() => this.el.classList.add('show'))
    }

    close() {
        clearInterval(this.timer)
        document.removeEventListener('keydown', this.onKey, true)
        window.removeEventListener('resize', this.onResize)
        if (!this.wasFull) window.lite?.win.setFullscreen(false)
        this.el.remove()
        const cur = this.slides[this.pos]?.i
        this.ed.presenter = null
        if (cur != null) this.ed.select(cur)
    }

    layout() {
        const main = this.el.querySelector('.pr-main').getBoundingClientRect()
        const k = Math.min(main.width / this.size.w, main.height / this.size.h)
        for (const s of this.stage.children) {
            s.style.transform = `translate(${(main.width - this.size.w * k) / 2}px, ${(main.height - this.size.h * k) / 2}px) scale(${k})`
        }
        this.k = k
    }

    // 渲染第 i 页（在放映列表中的位置）
    show(pos, transition) {
        const item = this.slides[pos]
        if (!item) return
        const old = this.stage.lastElementChild
        // 快速翻页时，上一次切换尚未结束的页面直接移除
        for (const p of [...this.stage.children]) if (p !== old) p.remove()
        const page = h('div.pr-page', renderSlide(item.s, this.deck))
        page.style.transformOrigin = '0 0'
        this.steps = animSteps(item.s)
        this.step = 0
        // 有动画的元素初始隐藏
        for (const g of this.steps) for (const el of g) {
            const node = page.querySelector(`[data-id="${el.id}"]`)
            if (node) node.style.visibility = 'hidden'
        }
        this.stage.append(page)
        this.layout()
        const tr = transition ?? item.s.transition
        const type = tr?.type ?? 'none'
        const dur = (tr?.dur ?? 0.6) * 1000
        if (old && type !== 'none') {
            const inner = page.firstElementChild, oldInner = old.firstElementChild
            const A = {
                fade: [[{ opacity: 0 }, { opacity: 1 }], null],
                push: [[{ transform: 'translateX(100%)' }, { transform: 'none' }], [{ transform: 'none' }, { transform: 'translateX(-100%)' }]],
                cover: [[{ transform: 'translateY(100%)' }, { transform: 'none' }], null],
                wipe: [[{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0 0 0)' }], null],
                split: [[{ clipPath: 'inset(0 50% 0 50%)' }, { clipPath: 'inset(0 0 0 0)' }], null],
                zoom: [[{ opacity: 0, transform: 'scale(.6)' }, { opacity: 1, transform: 'none' }], [{ opacity: 1 }, { opacity: 0, transform: 'scale(1.3)' }]],
                flip: [[{ transform: 'perspective(2400px) rotateY(90deg)', opacity: 0 }, { transform: 'none', opacity: 1 }], [{ transform: 'none' }, { transform: 'perspective(2400px) rotateY(-90deg)', opacity: 0 }]],
                blur: [[{ opacity: 0, filter: 'blur(30px)' }, { opacity: 1, filter: 'none' }], null],
            }[type] ?? [[{ opacity: 0 }, { opacity: 1 }], null]
            if (type === 'flip') {
                oldInner.animate(A[1], { duration: dur / 2, easing: 'ease-in', fill: 'forwards' })
                inner.style.opacity = '0'
                setTimeout(() => { inner.style.opacity = ''; inner.animate(A[0], { duration: dur / 2, easing: 'ease-out' }) }, dur / 2)
            } else {
                inner.animate(A[0], { duration: dur, easing: 'cubic-bezier(.2,.8,.2,1)' })
                if (A[1]) oldInner.animate(A[1], { duration: dur, easing: 'cubic-bezier(.2,.8,.2,1)', fill: 'forwards' })
            }
            setTimeout(() => { if (old.isConnected) old.remove() }, type === 'flip' ? dur : dur + 30)
        } else if (old) old.remove()
        this.pos = pos
        this.updateSide()
    }

    // 播放下一组动画；返回 false 表示本页动画已播完
    playStep() {
        if (this.step >= this.steps.length) return false
        const page = this.stage.lastElementChild
        for (const el of this.steps[this.step]) {
            const node = page.querySelector(`[data-id="${el.id}"]`)
            if (!node) continue
            node.style.visibility = ''
            const from = ANIM_FROM[el.anim.type] ?? ANIM_FROM.fade
            const base = el.rot ? `rotate(${el.rot}deg)` : ''
            const f = { ...from }
            if (f.transform) f.transform = `${base} ${f.transform}`
            const to = { opacity: from.opacity != null ? (el.opacity ?? 1) : undefined, transform: base || 'none', clipPath: from.clipPath ? 'inset(0 0 0 0)' : undefined }
            for (const k of Object.keys(to)) if (to[k] === undefined) delete to[k]
            node.animate([f, to], {
                duration: (el.anim.dur ?? 0.6) * 1000, delay: (el.anim.delay ?? 0) * 1000,
                easing: el.anim.type === 'bounce' ? 'cubic-bezier(.34,1.56,.64,1)' : 'cubic-bezier(.2,.8,.2,1)', fill: 'backwards',
            })
        }
        this.step++
        this.updateSide()
        return true
    }

    next() {
        if (this.blank) return this.setBlank(null)
        if (this.playStep()) return
        if (this.pos < this.slides.length - 1) this.show(this.pos + 1)
        else if (!this.ended) { this.ended = true; this.showEnd() } else this.close()
    }
    prev() {
        if (this.blank) return this.setBlank(null)
        if (this.ended) { this.ended = false; this.cover.className = 'pr-cover'; this.cover.textContent = ''; return }
        if (this.pos > 0) {
            this.show(this.pos - 1, { type: 'none' })
            while (this.playStepInstant()) { /* 回到上一页时显示全部内容 */ }
        }
    }
    playStepInstant() {
        if (this.step >= this.steps.length) return false
        const page = this.stage.lastElementChild
        for (const el of this.steps[this.step]) { const n = page.querySelector(`[data-id="${el.id}"]`); if (n) n.style.visibility = '' }
        this.step++
        return true
    }
    goto(pos) { this.ended = false; this.cover.className = 'pr-cover'; this.show(Math.max(0, Math.min(this.slides.length - 1, pos)), { type: 'none' }) }

    showEnd() {
        this.cover.className = 'pr-cover end'
        this.cover.textContent = '放映结束，单击退出'
    }
    setBlank(color) {
        this.blank = color
        this.cover.className = 'pr-cover' + (color ? ' ' + color : '')
        this.cover.textContent = ''
    }

    togglePresenter() {
        this.presenterView = !this.presenterView
        this.el.classList.toggle('with-side', this.presenterView)
        requestAnimationFrame(() => this.layout())
        this.updateSide()
    }

    updateSide() {
        this.counter.textContent = `${this.pos + 1} / ${this.slides.length}`
        if (!this.presenterView) return
        const next = this.slides[this.pos + 1]
        const cur = this.slides[this.pos]
        const k = 300 / this.size.w
        const thumb = s => {
            const n = renderSlide(s, this.deck)
            n.style.transform = `scale(${k})`
            n.style.transformOrigin = '0 0'
            return h('div.pr-thumb', { style: { width: '300px', height: this.size.h * k + 'px' } }, n)
        }
        const key = `${this.pos}`
        if (this.sideKey !== key) {
            this.sideKey = key
            this.side.replaceChildren(
                h('div.pr-time', h('span.pr-clock'), h('span.pr-elapsed')),
                h('div.pr-label', '下一页'),
                next ? thumb(next.s) : h('div.pr-thumb.empty', '最后一页'),
                h('div.pr-label', '备注'),
                h('div.pr-notes', cur?.s.notes || '（无备注）'),
                h('div.pr-steps'))
        }
        this.side.querySelector('.pr-clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
        this.side.querySelector('.pr-elapsed').textContent = '已用 ' + formatTime((Date.now() - this.t0) / 1000)
        this.side.querySelector('.pr-steps').textContent = this.steps?.length ? `动画 ${this.step} / ${this.steps.length}` : ''
    }

    key(e) {
        e.stopPropagation()
        const k = e.key
        // 输入页码后回车跳转
        if (k === 'Enter' && this.jump) { e.preventDefault(); this.goto(Number(this.jump) - 1); this.jump = ''; return }
        if (['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter', 'n', 'N'].includes(k)) { e.preventDefault(); this.next() }
        else if (['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace', 'p'].includes(k)) { e.preventDefault(); this.prev() }
        else if (k === 'Home') { e.preventDefault(); this.goto(0) }
        else if (k === 'End') { e.preventDefault(); this.goto(this.slides.length - 1) }
        else if (k === 'Escape') { e.preventDefault(); this.close() }
        else if (k === 'b' || k === 'B' || k === '.') { e.preventDefault(); this.setBlank(this.blank === 'black' ? null : 'black') }
        else if (k === 'w' || k === 'W' || k === ',') { e.preventDefault(); this.setBlank(this.blank === 'white' ? null : 'white') }
        else if (k === 'P') { e.preventDefault(); this.togglePresenter() }
        else if (/^\d$/.test(k)) {
            this.jump = (this.jump ?? '') + k
            clearTimeout(this.jumpT)
            this.jumpT = setTimeout(() => { this.jump = '' }, 900)
        } else if (k === 'F5' || k === 'F11') e.preventDefault()
    }
}
