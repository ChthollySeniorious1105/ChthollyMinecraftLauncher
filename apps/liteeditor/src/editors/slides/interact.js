// 画布交互：选择、框选、移动（智能参考线）、缩放、旋转、文字编辑
import { h } from '../../core/dom.js'
import { sizeOf } from './model.js'

const SNAP = 8 // 屏幕像素

// 元素旋转后的外接框
export function bbox(el) {
    if (!el.rot) return { x: el.x, y: el.y, w: el.w, h: el.h }
    const a = el.rot * Math.PI / 180, c = Math.abs(Math.cos(a)), s = Math.abs(Math.sin(a))
    const w = el.w * c + el.h * s, hh = el.w * s + el.h * c
    return { x: el.x + el.w / 2 - w / 2, y: el.y + el.h / 2 - hh / 2, w, h: hh }
}
export function unionBox(els) {
    const bs = els.map(bbox)
    const x0 = Math.min(...bs.map(b => b.x)), y0 = Math.min(...bs.map(b => b.y))
    const x1 = Math.max(...bs.map(b => b.x + b.w)), y1 = Math.max(...bs.map(b => b.y + b.h))
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

export function installInteract(Ed) {
    const P = Ed.prototype

    // 屏幕坐标 → 幻灯片坐标
    P.toSlide = function (e) {
        const r = this.slideEl.getBoundingClientRect()
        return { x: (e.clientX - r.left) / this.zoom, y: (e.clientY - r.top) / this.zoom }
    }

    P.bindCanvas = function () {
        this.listen(this.canvasWrap, 'pointerdown', e => this.onDown(e))
        this.listen(this.canvasWrap, 'dblclick', e => this.onDbl(e))
        this.listen(this.canvasWrap, 'contextmenu', e => this.onContext(e))
        this.listen(this.canvasWrap, 'wheel', e => {
            if (!e.ctrlKey) return
            e.preventDefault()
            this.setZoom(this.zoomMode === 'fit' ? this.fitZoom() * Math.exp(-e.deltaY * 0.0015) : this.zoomUser * Math.exp(-e.deltaY * 0.0015))
        }, { passive: false })
    }

    P.elAt = function (e) {
        const node = e.target.closest?.('.sl-el')
        if (!node || !this.slideEl.contains(node)) return null
        return this.slide.els.find(x => x.id === node.dataset.id) ?? null
    }

    P.onDown = function (e) {
        if (e.button === 1) return
        if (this.editing && e.target.closest('.sl-editing')) return
        const handle = e.target.closest('.sl-handle')
        if (this.editing) this.stopEditing()
        if (handle && e.button === 0) return this.startHandle(e, handle.dataset.h)
        const el = this.elAt(e)
        // 插入模式：拖出新形状 / 文本框
        if (this.insertMode && e.button === 0) return this.startInsert(e)
        if (!el) {
            if (e.button !== 0) return
            if (!e.shiftKey && !e.ctrlKey) this.setSel([])
            return this.startMarquee(e)
        }
        if (e.shiftKey || e.ctrlKey) {
            const s = new Set(this.sel)
            s.has(el.id) ? s.delete(el.id) : s.add(el.id)
            this.setSel([...s])
            if (!s.has(el.id)) return
        } else if (!this.sel.includes(el.id)) {
            // 组合：选中组内任意元素时选中整组
            this.setSel(el.group ? this.slide.els.filter(x => x.group === el.group).map(x => x.id) : [el.id])
        }
        if (e.button !== 0) return
        this.startMove(e)
    }

    P.startMarquee = function (e) {
        const p0 = this.toSlide(e)
        const base = e.shiftKey || e.ctrlKey ? [...this.sel] : []
        const box = h('div.sl-marquee')
        this.overlay.append(box)
        const move = ev => {
            const p = this.toSlide(ev)
            const x = Math.min(p.x, p0.x), y = Math.min(p.y, p0.y), w = Math.abs(p.x - p0.x), hh = Math.abs(p.y - p0.y)
            Object.assign(box.style, { left: x * this.zoom + 'px', top: y * this.zoom + 'px', width: w * this.zoom + 'px', height: hh * this.zoom + 'px' })
            const hit = this.slide.els.filter(el => { const b = bbox(el); return !el.locked && b.x < x + w && b.x + b.w > x && b.y < y + hh && b.y + b.h > y }).map(el => el.id)
            this.setSel([...new Set([...base, ...hit])], { quiet: true })
        }
        const up = () => {
            box.remove()
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            this.setSel(this.sel)
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }

    // 参考线目标：画布边缘与中心、其他元素的边缘与中心
    P.snapTargets = function (exclude) {
        const { w, h: H } = sizeOf(this.deck)
        const xs = [0, w / 2, w], ys = [0, H / 2, H]
        for (const el of this.slide.els) {
            if (exclude.has(el.id)) continue
            const b = bbox(el)
            xs.push(b.x, b.x + b.w / 2, b.x + b.w)
            ys.push(b.y, b.y + b.h / 2, b.y + b.h)
        }
        return { xs, ys }
    }

    // 对一组候选坐标求最近的吸附偏移
    function bestSnap(vals, targets, tol) {
        let best = null
        for (const v of vals) for (const t of targets) {
            const d = t - v
            if (Math.abs(d) <= tol && (!best || Math.abs(d) < Math.abs(best.d))) best = { d, t }
        }
        return best
    }

    P.showGuides = function (gx, gy) {
        this.guides.replaceChildren()
        const { w, h: H } = sizeOf(this.deck)
        if (gx != null) this.guides.append(h('div.sl-guide.v', { style: { left: gx * this.zoom + 'px', height: H * this.zoom + 'px' } }))
        if (gy != null) this.guides.append(h('div.sl-guide.h', { style: { top: gy * this.zoom + 'px', width: w * this.zoom + 'px' } }))
    }

    P.startMove = function (e) {
        const els = this.selEls().filter(x => !x.locked)
        if (!els.length) return
        const p0 = this.toSlide(e)
        const start = els.map(el => ({ el, x: el.x, y: el.y }))
        const box0 = unionBox(els)
        const targets = this.snapTargets(new Set(els.map(x => x.id)))
        let moved = false
        // Alt 拖动：复制
        let dup = e.altKey
        const move = ev => {
            const p = this.toSlide(ev)
            let dx = p.x - p0.x, dy = p.y - p0.y
            if (!moved && Math.hypot(dx, dy) * this.zoom < 3) return
            if (!moved && dup) {
                dup = false
                const copies = this.duplicateEls(els, 0)
                start.splice(0, start.length, ...copies.map(el => ({ el, x: el.x, y: el.y })))
            }
            moved = true
            if (ev.shiftKey) { if (Math.abs(dx) > Math.abs(dy)) dy = 0; else dx = 0 }
            let gx = null, gy = null
            if (!ev.ctrlKey) {
                const tol = SNAP / this.zoom
                const sx = bestSnap([box0.x + dx, box0.x + box0.w / 2 + dx, box0.x + box0.w + dx], targets.xs, tol)
                const sy = bestSnap([box0.y + dy, box0.y + box0.h / 2 + dy, box0.y + box0.h + dy], targets.ys, tol)
                if (sx) { dx += sx.d; gx = sx.t }
                if (sy) { dy += sy.d; gy = sy.t }
            }
            for (const s of start) { s.el.x = Math.round(s.x + dx); s.el.y = Math.round(s.y + dy) }
            this.showGuides(gx, gy)
            this.renderCanvas({ keepOverlay: true })
        }
        const up = () => {
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            this.guides.replaceChildren()
            if (moved) this.change('移动')
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }

    // 控制点：n ne e se s sw w nw 以及 rot（旋转）、line 端点 p1 / p2
    P.startHandle = function (e, which) {
        e.stopPropagation()
        const els = this.selEls()
        if (!els.length) return
        const p0 = this.toSlide(e)
        if (which === 'rot') return this.startRotate(e, els)
        if (which === 'p1' || which === 'p2') return this.startLineEnd(e, els[0], which)
        const single = els.length === 1 ? els[0] : null
        const box0 = single ? { x: single.x, y: single.y, w: single.w, h: single.h } : unionBox(els)
        const start = els.map(el => ({ el, x: el.x, y: el.y, w: el.w, h: el.h, size: el.style?.size, x1: el.x1, y1: el.y1, x2: el.x2, y2: el.y2 }))
        const rot = single?.rot ?? 0
        const a = rot * Math.PI / 180, cos = Math.cos(a), sin = Math.sin(a)
        const targets = this.snapTargets(new Set(els.map(x => x.id)))
        const keepRatio = single?.type === 'image' || single?.type === 'icon'
        let moved = false
        const move = ev => {
            const p = this.toSlide(ev)
            // 转换到元素自身坐标系
            let dx = p.x - p0.x, dy = p.y - p0.y
            const lx = dx * cos + dy * sin, ly = -dx * sin + dy * cos
            let { x, y, w, h: hh } = box0
            if (which.includes('e')) w = box0.w + lx
            if (which.includes('w')) { w = box0.w - lx }
            if (which.includes('s')) hh = box0.h + ly
            if (which.includes('n')) { hh = box0.h - ly }
            const ratio = box0.w / box0.h
            if ((ev.shiftKey !== keepRatio) && which.length === 2) {
                if (Math.abs(w / box0.w) > Math.abs(hh / box0.h)) hh = w / ratio; else w = hh * ratio
            }
            w = Math.max(10, w); hh = Math.max(10, hh)
            // 固定对角点：在旋转坐标系中计算新的左上角
            const fx = which.includes('w') ? 1 : which.includes('e') ? 0 : 0.5
            const fy = which.includes('n') ? 1 : which.includes('s') ? 0 : 0.5
            const ax = box0.w * fx, ay = box0.h * fy // 锚点（局部）
            const cx0 = box0.x + box0.w / 2, cy0 = box0.y + box0.h / 2
            const anchorWorld = { x: cx0 + (ax - box0.w / 2) * cos - (ay - box0.h / 2) * sin, y: cy0 + (ax - box0.w / 2) * sin + (ay - box0.h / 2) * cos }
            const nax = w * fx, nay = hh * fy
            const ncx = anchorWorld.x - ((nax - w / 2) * cos - (nay - hh / 2) * sin)
            const ncy = anchorWorld.y - ((nax - w / 2) * sin + (nay - hh / 2) * cos)
            x = ncx - w / 2; y = ncy - hh / 2
            // 未旋转时吸附边缘
            let gx = null, gy = null
            if (!rot && !ev.ctrlKey) {
                const tol = SNAP / this.zoom
                if (which.includes('e')) { const s = bestSnap([x + w], targets.xs, tol); if (s) { w += s.d; gx = s.t } }
                if (which.includes('w')) { const s = bestSnap([x], targets.xs, tol); if (s) { x += s.d; w -= s.d; gx = s.t } }
                if (which.includes('s')) { const s = bestSnap([y + hh], targets.ys, tol); if (s) { hh += s.d; gy = s.t } }
                if (which.includes('n')) { const s = bestSnap([y], targets.ys, tol); if (s) { y += s.d; hh -= s.d; gy = s.t } }
            }
            moved = true
            if (single) {
                Object.assign(single, { x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(hh) })
                const st = start[0]
                if (single.shape === 'line' || single.shape === 'arrow') {
                    const kx = w / st.w, ky = hh / st.h
                    single.x1 = (st.x1 ?? 0) * kx; single.x2 = (st.x2 ?? st.w) * kx
                    single.y1 = (st.y1 ?? st.h / 2) * ky; single.y2 = (st.y2 ?? st.h / 2) * ky
                }
            } else {
                const kx = w / box0.w, ky = hh / box0.h
                for (const s of start) {
                    Object.assign(s.el, { x: Math.round(x + (s.x - box0.x) * kx), y: Math.round(y + (s.y - box0.y) * ky), w: Math.round(s.w * kx), h: Math.round(s.h * ky) })
                }
            }
            this.showGuides(gx, gy)
            this.renderCanvas({ keepOverlay: true })
        }
        const up = () => {
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            this.guides.replaceChildren()
            if (moved) this.change('调整大小')
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }

    P.startRotate = function (e, els) {
        const box = unionBox(els)
        const c = { x: box.x + box.w / 2, y: box.y + box.h / 2 }
        const start = els.map(el => ({ el, rot: el.rot ?? 0, cx: el.x + el.w / 2, cy: el.y + el.h / 2 }))
        const a0 = Math.atan2(this.toSlide(e).y - c.y, this.toSlide(e).x - c.x)
        let moved = false
        const move = ev => {
            const p = this.toSlide(ev)
            let da = (Math.atan2(p.y - c.y, p.x - c.x) - a0) * 180 / Math.PI
            for (const s of start) {
                let r = s.rot + da
                // 吸附到 15° 的倍数（按住 Shift），或接近 0/90/180/270 时自动吸附
                r = ev.shiftKey ? Math.round(r / 15) * 15 : (Math.abs(((r % 90) + 90) % 90) < 3 || Math.abs(((r % 90) + 90) % 90) > 87 ? Math.round(r / 90) * 90 : r)
                const d = (r - s.rot) * Math.PI / 180
                s.el.rot = Math.round(((r % 360) + 360) % 360 * 10) / 10
                if (start.length > 1) {
                    const nx = c.x + (s.cx - c.x) * Math.cos(d) - (s.cy - c.y) * Math.sin(d)
                    const ny = c.y + (s.cx - c.x) * Math.sin(d) + (s.cy - c.y) * Math.cos(d)
                    s.el.x = Math.round(nx - s.el.w / 2); s.el.y = Math.round(ny - s.el.h / 2)
                }
            }
            void da
            moved = true
            this.renderCanvas({ keepOverlay: true })
            this.rotLabel(start[0].el.rot)
        }
        const up = () => {
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            this.guides.replaceChildren()
            if (moved) this.change('旋转')
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }
    P.rotLabel = function (deg) {
        this.guides.replaceChildren(h('div.sl-rot-label', { style: { left: (this.mouseX ?? 0) + 'px', top: (this.mouseY ?? 0) + 'px' } }, Math.round(deg) + '°'))
    }

    // 直线端点拖动
    P.startLineEnd = function (e, el, which) {
        const other = which === 'p1' ? { x: el.x + (el.x2 ?? el.w), y: el.y + (el.y2 ?? el.h / 2) } : { x: el.x + (el.x1 ?? 0), y: el.y + (el.y1 ?? el.h / 2) }
        let moved = false
        const move = ev => {
            let p = this.toSlide(ev)
            if (ev.shiftKey) {
                const a = Math.round(Math.atan2(p.y - other.y, p.x - other.x) / (Math.PI / 4)) * (Math.PI / 4), L = Math.hypot(p.x - other.x, p.y - other.y)
                p = { x: other.x + L * Math.cos(a), y: other.y + L * Math.sin(a) }
            }
            const a = which === 'p1' ? p : other, b = which === 'p1' ? other : p
            setLine(el, a, b)
            moved = true
            this.renderCanvas({ keepOverlay: true })
        }
        const up = () => {
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            if (moved) this.change('调整线条')
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }

    // 插入：拖出矩形区域后创建元素；单击则使用默认大小
    P.startInsert = function (e) {
        const mode = this.insertMode
        const p0 = this.toSlide(e)
        const box = h('div.sl-marquee.insert')
        this.overlay.append(box)
        let p1 = p0
        const isLine = mode.shape === 'line' || mode.shape === 'arrow'
        const move = ev => {
            p1 = this.toSlide(ev)
            if (ev.shiftKey && !isLine) {
                const d = Math.max(Math.abs(p1.x - p0.x), Math.abs(p1.y - p0.y))
                p1 = { x: p0.x + Math.sign(p1.x - p0.x || 1) * d, y: p0.y + Math.sign(p1.y - p0.y || 1) * d }
            }
            const x = Math.min(p1.x, p0.x), y = Math.min(p1.y, p0.y)
            Object.assign(box.style, { left: x * this.zoom + 'px', top: y * this.zoom + 'px', width: Math.abs(p1.x - p0.x) * this.zoom + 'px', height: Math.abs(p1.y - p0.y) * this.zoom + 'px' })
        }
        const up = () => {
            box.remove()
            window.removeEventListener('pointermove', move)
            window.removeEventListener('pointerup', up)
            const small = Math.hypot(p1.x - p0.x, p1.y - p0.y) < 12
            const def = mode.type === 'text' ? { w: 600, h: 120 } : isLine ? { w: 400, h: 0 } : { w: 320, h: 240 }
            let r
            if (small) r = { x: p0.x - def.w / 2, y: p0.y - def.h / 2, w: def.w, h: def.h }
            else r = { x: Math.min(p0.x, p1.x), y: Math.min(p0.y, p1.y), w: Math.abs(p1.x - p0.x), h: Math.abs(p1.y - p0.y) }
            this.insertMode = null
            this.updateInsertUI()
            if (isLine) {
                const a = small ? { x: r.x, y: p0.y } : p0, b = small ? { x: r.x + r.w, y: p0.y } : p1
                const el = this.makeEl({ type: 'shape', shape: mode.shape })
                setLine(el, a, b)
                this.addEls([el], '插入线条')
            } else {
                const el = this.makeEl({ ...mode, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(Math.max(20, r.w)), h: Math.round(Math.max(20, r.h)) })
                this.addEls([el], mode.type === 'text' ? '插入文本框' : '插入形状')
                if (mode.type === 'text') this.startEditing(el)
            }
        }
        window.addEventListener('pointermove', move)
        window.addEventListener('pointerup', up)
    }

    P.onDbl = function (e) {
        const el = this.elAt(e)
        if (!el || el.locked) return
        if (el.type === 'text' || el.type === 'shape' && el.shape !== 'line' && el.shape !== 'arrow') return this.startEditing(el, e)
        if (el.type === 'table') return this.startEditing(el, e)
        if (el.type === 'chart') return this.editChart(el)
        if (el.type === 'math') return this.editMath(el)
        if (el.type === 'image') return this.replaceImage(el)
    }

    // ---------- 文字编辑 ----------
    P.startEditing = function (el, ev) {
        this.setSel([el.id])
        this.renderCanvas()
        const node = this.slideEl.querySelector(`[data-id="${el.id}"]`)
        if (!node) return
        let target
        if (el.type === 'table') {
            node.classList.add('sl-editing')
            for (const c of node.querySelectorAll('th, td')) c.contentEditable = 'true'
            target = ev?.target.closest?.('th, td') ?? node.querySelector('th, td')
        } else {
            target = node.querySelector('.sl-text')
            if (!target) {
                // 形状中没有文字：添加文字层
                el.html = ''
                el.style ??= {}
                this.renderCanvas()
                return this.startEditing(el, ev)
            }
            if (target.querySelector('.sl-ph')) target.innerHTML = ''
            target.contentEditable = 'true'
            node.classList.add('sl-editing')
        }
        this.editing = { el, node, target, before: el.type === 'table' ? JSON.stringify(el.rows) : el.html }
        target.focus()
        // 把光标放在点击位置或末尾
        const sel = getSelection()
        let range = ev && document.caretRangeFromPoint?.(ev.clientX, ev.clientY)
        if (!range || !target.contains(range.startContainer)) { range = document.createRange(); range.selectNodeContents(target); range.collapse(false) }
        sel.removeAllRanges()
        sel.addRange(range)
        this.overlay.classList.add('editing')
        this.updateFormatUI()
    }

    P.stopEditing = function () {
        const ed = this.editing
        if (!ed) return
        this.editing = null
        this.overlay.classList.remove('editing')
        const { el, node } = ed
        if (el.type === 'table') {
            node.querySelectorAll('tr').forEach((tr, ri) => tr.querySelectorAll('th, td').forEach((c, ci) => { if (el.rows[ri]) el.rows[ri][ci] = cleanHTML(c.innerHTML) }))
            if (JSON.stringify(el.rows) !== ed.before) this.change('编辑表格')
        } else {
            const html = cleanHTML(ed.target.innerHTML)
            el.html = html
            if (html !== ed.before) this.change('编辑文字')
        }
        getSelection().removeAllRanges()
        this.renderAll()
    }

    // 编辑中的文字变化：同步到模型（不记录历史，结束编辑时统一记录）
    P.syncEditing = function () {
        const ed = this.editing
        if (!ed || ed.el.type === 'table') return
        ed.el.html = cleanHTML(ed.target.innerHTML)
        this.refreshThumb(this.current)
    }
}

// 用两个端点设置直线元素
export function setLine(el, a, b) {
    const pad = 20
    const x = Math.min(a.x, b.x) - pad, y = Math.min(a.y, b.y) - pad
    el.x = Math.round(x); el.y = Math.round(y)
    el.w = Math.round(Math.abs(a.x - b.x) + pad * 2); el.h = Math.round(Math.abs(a.y - b.y) + pad * 2)
    el.x1 = a.x - x; el.y1 = a.y - y; el.x2 = b.x - x; el.y2 = b.y - y
    el.rot = 0
}

export function cleanHTML(html) {
    return String(html ?? '')
        .replace(/<div class="sl-ph">[\s\S]*?<\/div>/g, '')
        .replace(/\s*contenteditable="[^"]*"/g, '')
        .replace(/^(<br\s*\/?>)+$/, '')
}
