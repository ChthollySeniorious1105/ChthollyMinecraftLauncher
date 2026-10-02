// 单元格编辑：隐藏输入框捕获键盘 / 输入法；公式引用点选、着色、函数自动补全、参数提示
import { h, escapeHTML } from '../../core/dom.js'
import { keyString } from '../../core/menu.js'
import { tokenize, refText } from './formula/lexer.js'
import { FUNC_NAMES } from './formula/functions.js'
import { FUNC_INFO } from './funcinfo.js'
import { cellName, colName, normRange, quoteSheet } from './addr.js'
import { fontString, display } from './format.js'
import { parseNumberText, parseDateText, isErr } from './formula/values.js'

export const REF_COLORS = ['#2563eb', '#dc2626', '#7c3aed', '#059669', '#d97706', '#db2777', '#0891b2', '#65a30d']
const PICK_BEFORE = /[=(,+\-*/^&<>:;{%]\s*$/

// 输入文本 -> { v, f, fmt }
export function parseInput(text, curFmt) {
    if (text == null || text === '') return { v: null }
    if (text[0] === "'") return { v: text.slice(1), text: true }
    if (text[0] === '=' && text.length > 1) return { f: text.slice(1) }
    if (curFmt === '@') return { v: text }
    const t = text.trim()
    const up = t.toUpperCase()
    if (up === 'TRUE' || up === 'FALSE') return { v: up === 'TRUE' }
    const n = parseNumberText(t)
    if (n != null) {
        let fmt = null
        if (/%\s*$/.test(t)) fmt = /\.\d/.test(t) ? '0.00%' : '0%'
        else if (/^[+-]?¥/.test(t) || /^\(?¥/.test(t)) fmt = '"¥"#,##0.00'
        else if (/^[+-]?\$/.test(t)) fmt = '"$"#,##0.00'
        else if (/\d,\d{3}/.test(t)) fmt = /\.\d/.test(t) ? '#,##0.00' : '#,##0'
        return { v: n, fmt }
    }
    const d = parseDateText(t)
    if (d != null) {
        const hasDate = /[-/.年]/.test(t), hasTime = /:/.test(t)
        return { v: d, fmt: hasDate && hasTime ? 'yyyy-mm-dd h:mm' : hasDate ? 'yyyy-mm-dd' : /:\d+:/.test(t) ? 'h:mm:ss' : 'h:mm' }
    }
    if (isErr(t)) return { v: t }
    return { v: text }
}

// 单元格 -> 编辑文本
export function editText(cell, v) {
    if (!cell) return ''
    if (cell.f) return '=' + cell.f
    if (cell.v == null) return ''
    const fmt = cell.s?.fmt
    if (typeof cell.v === 'number') {
        if (fmt && /[ymdhs]/i.test(fmt.replace(/"[^"]*"|\[[^\]]*\]/g, ''))) {
            const hasDate = /[ymd]/i.test(fmt.replace(/"[^"]*"/g, '').replace(/mm(?=:)|(?<=:)mm/g, ''))
            return display(cell.v, hasDate ? (cell.v % 1 ? 'yyyy-mm-dd h:mm:ss' : 'yyyy-mm-dd') : 'h:mm:ss').text
        }
        if (fmt && /%/.test(fmt)) return String(+(cell.v * 100).toPrecision(15)) + '%'
        return String(+cell.v.toPrecision(15))
    }
    if (typeof cell.v === 'boolean') return cell.v ? 'TRUE' : 'FALSE'
    if (typeof cell.v === 'string' && (parseNumberText(cell.v) != null || cell.v[0] === '=' || cell.v[0] === "'")) return "'" + cell.v
    void v
    return String(cell.v)
}

// 公式着色 HTML（引用按出现顺序取色）
export function highlightFormula(text) {
    if (!text.startsWith('=')) return escapeHTML(text) + '​'
    const body = text.slice(1)
    const toks = tokenize(body)
    const colorOf = new Map()
    let out = '=', pos = 0
    for (const t of toks) {
        out += escapeHTML(body.slice(pos, t.start))
        const raw = escapeHTML(body.slice(t.start, t.end))
        if (t.t === 'ref') {
            const key = refText({ ...t, ar1: false, ac1: false, ar2: false, ac2: false }).toUpperCase()
            if (!colorOf.has(key)) colorOf.set(key, REF_COLORS[colorOf.size % REF_COLORS.length])
            out += `<span style="color:${colorOf.get(key)}">${raw}</span>`
        } else if (t.t === 'func') out += `<span class="hl-fn">${raw}</span>`
        else if (t.t === 'str') out += `<span class="hl-str">${raw}</span>`
        else if (t.t === 'num') out += `<span class="hl-num">${raw}</span>`
        else if (t.t === 'err' || t.t === 'bad') out += `<span class="hl-err">${raw}</span>`
        else out += raw
        pos = t.end
    }
    return out + escapeHTML(body.slice(pos)) + '​'
}

export const Editing = {
    bindEditing() {
        // 单元格编辑器：镜像层（着色）+ 透明文本框
        this.mirror = h('div.sh-mirror')
        this.input = h('textarea.sh-input', { spellcheck: false, autocomplete: 'off', rows: 1, wrap: 'soft' })
        this.editBox = h('div.sh-editor.idle', this.mirror, this.input)
        this.grid.layer.append(this.editBox)
        this.acBox = h('div.sh-ac', { hidden: true })
        this.hintBox = h('div.sh-hint', { hidden: true })
        document.body.append(this.acBox, this.hintBox)
        this.onDispose(() => { this.acBox.remove(); this.hintBox.remove() })

        const inp = this.input
        this.listen(inp, 'input', () => this.onEditorInput(inp))
        this.listen(inp, 'compositionstart', () => { if (!this.editing) this.startEdit({ mode: 'enter', text: '', keep: true }) })
        this.listen(inp, 'keydown', e => this.onEditorKey(e, inp))
        this.listen(inp, 'keyup', () => this.editing && this.updateAssist(inp))
        this.listen(inp, 'click', () => this.editing && this.updateAssist(inp))
        this.listen(inp, 'blur', () => setTimeout(() => this.hideAssist(), 150))
        this.listen(inp, 'copy', e => this.onCopyEvent(e, false))
        this.listen(inp, 'cut', e => this.onCopyEvent(e, true))
        this.listen(inp, 'paste', e => this.onPasteEvent(e))
        this.positionInput()
    },

    // 空闲时让输入框跟随活动单元格（使输入法候选窗位置正确）
    positionInput() {
        if (this.editing || !this.editBox) return
        const a = this.activeRect()
        const box = this.editBox
        box.style.left = Math.max(0, a.x) + 'px'
        box.style.top = Math.max(0, a.y) + 'px'
        box.style.width = Math.max(20, a.w) + 'px'
        box.style.height = Math.max(16, a.h) + 'px'
    },

    onGridScroll() { if (this.editing) this.layoutEditor(); else this.positionInput(); this.positionCharts?.() },
    onGridDrawn() { this.positionCharts?.() },

    onEditorInput(inp) {
        if (!this.editing) {
            if (inp.value === '') return
            if (this.readOnlyCell?.()) { inp.value = ''; return }
            this.startEdit({ mode: 'enter', text: inp.value, keep: true })
        }
        this.editing.text = inp.value
        this.pick = null
        this.syncEditors(inp)
        this.updateAssist(inp)
    },

    // text 为初始文本；keep 表示保留输入框中已有的内容（输入法组合中）
    startEdit({ mode = 'edit', text, keep = false, src = 'cell' } = {}) {
        if (this.editing) return
        const sh = this.sheet
        const { r, c } = this.sel
        const cell = sh.get(r, c)
        const original = editText(cell)
        if (this.lockedCell?.(r, c)) return
        this.editing = { r, c, sheetId: sh.id, mode, original, text: text ?? original, src }
        this.editBox.classList.remove('idle')
        this.el.classList.add('sh-is-editing')
        if (!keep) this.input.value = this.editing.text
        const st = sh.styleAt(r, c, cell)
        this.editBox.style.setProperty('--ed-font', fontString(st, this.zoom))
        this.editBox.style.setProperty('--ed-color', st?.color ?? '#1f2328')
        this.editBox.style.setProperty('--ed-bg', st?.fill ?? '#ffffff')
        this.editBox.style.setProperty('--ed-align', 'left')
        this.syncEditors(this.input)
        this.layoutEditor()
        if (src === 'fx') {
            this.fxInput.focus()
        } else {
            this.input.focus({ preventScroll: true })
            if (!keep) { const n = this.input.value.length; this.input.setSelectionRange(n, n) }
        }
        this.grid.requestDraw()
        this.refreshUI()
    },

    // 同步单元格编辑器与编辑栏
    syncEditors(from) {
        const t = from.value
        if (this.editing) this.editing.text = t
        if (from !== this.input) this.input.value = t
        if (from !== this.fxInput && this.fxInput) this.fxInput.value = t
        const html = highlightFormula(t)
        this.mirror.innerHTML = html
        if (this.fxMirror) this.fxMirror.innerHTML = html
        this.updateRefHighlights(t)
        this.layoutEditor()
        this.autoGrowFx?.()
    },

    // 编辑框尺寸：至少覆盖单元格，文本变长时向右扩展，再向下换行
    layoutEditor() {
        if (!this.editing) return
        const G = this.grid
        const e = this.editing
        const box = this.editBox
        if (e.sheetId !== this.sheet.id) { box.style.visibility = 'hidden'; return }
        box.style.visibility = ''
        const a = this.activeRect()
        const maxW = Math.max(a.w, G.W - a.x - 4)
        const font = fontString(this.sheet.styleAt(e.r, e.c), this.zoom)
        const lines = (this.input.value || ' ').split('\n')
        const tw = Math.max(...lines.map(l => G.measure(font, l))) + 12 * this.zoom + 8
        const w = Math.min(maxW, Math.max(a.w, tw))
        box.style.left = a.x + 'px'
        box.style.top = a.y + 'px'
        box.style.width = w + 'px'
        box.style.height = 'auto'
        box.style.minHeight = a.h + 'px'
        this.input.style.height = '0px'
        const need = Math.max(a.h, this.mirror.scrollHeight)
        box.style.height = Math.min(need, G.H - a.y - 4) + 'px'
        this.input.style.height = '100%'
    },

    commitEdit(moveAfter) {
        const e = this.editing
        if (!e) return true
        const text = this.input.value
        if (text.startsWith('=') && text.length > 1) {
            // 自动补全缺失的右括号
            let t = text
            let depth = 0, inStr = false
            for (const ch of t) { if (ch === '"') inStr = !inStr; else if (!inStr) { if (ch === '(') depth++; else if (ch === ')') depth-- } }
            if (depth > 0 && !inStr) t += ')'.repeat(depth)
            const errMsg = this.engine.check(t.slice(1))
            if (errMsg) {
                this.toastWarn(`公式有误：${errMsg}`)
                return false
            }
            this.input.value = t
        }
        // 数据验证
        const sh = this.sheets.find(s => s.id === e.sheetId)
        const dv = this.validationAt(e.r, e.c, sh)
        if (dv && text !== '' && !text.startsWith('=')) {
            const bad = this.validateInput(dv, parseInput(text).v)
            if (bad) { this.toastWarn(bad); return false }
        }
        this.endEdit()
        if (sh !== this.sheet) this.switchSheet(this.sheets.indexOf(sh), { keepEdit: true })
        if (this.input.value !== e.original) this.setInput(e.r, e.c, this.input.value, sh)
        this.input.value = ''
        this.selectCell(e.r, e.c, { scroll: false })
        if (moveAfter) moveAfter()
        return true
    },

    cancelEdit() {
        const e = this.editing
        if (!e) return
        this.endEdit()
        this.input.value = ''
        if (e.sheetId !== this.sheet.id) this.switchSheet(this.sheets.findIndex(s => s.id === e.sheetId), { keepEdit: true })
        this.refreshUI()
    },

    endEdit() {
        this.editing = null
        this.pick = null
        this.refHighlights = null
        this.editBox.classList.add('idle')
        this.el.classList.remove('sh-is-editing')
        this.mirror.textContent = ''
        this.editBox.style.minHeight = ''
        this.hideAssist()
        this.positionInput()
        this.grid.requestDraw()
        if (document.activeElement === this.fxInput) this.input.focus({ preventScroll: true })
    },

    // ---------- 键盘 ----------
    onEditorKey(e, inp) {
        if (e.isComposing || e.keyCode === 229) return
        if (!this.editing) return // 空闲状态由 onKey 处理
        const k = e.key
        const stop = () => { e.preventDefault(); e.stopPropagation() }
        // 自动补全列表
        if (!this.acBox.hidden) {
            if (k === 'ArrowDown' || k === 'ArrowUp') { stop(); this.acMove(k === 'ArrowDown' ? 1 : -1); return }
            if (k === 'Tab' || (k === 'Enter' && this.acIndex >= 0)) { stop(); this.acAccept(inp); return }
            if (k === 'Escape') { stop(); this.hideAssist(); return }
        }
        if (k === 'Enter' && e.altKey) {
            stop()
            const s = inp.selectionStart, t = inp.value
            inp.value = t.slice(0, s) + '\n' + t.slice(inp.selectionEnd)
            inp.setSelectionRange(s + 1, s + 1)
            this.syncEditors(inp)
            return
        }
        if (k === 'Enter' && (e.ctrlKey || e.metaKey)) { stop(); this.commitToSelection(); return }
        if (k === 'Enter') { stop(); this.commitEdit(() => this.moveWithin(e.shiftKey ? -1 : 1, 0)); return }
        if (k === 'Tab') { stop(); this.commitEdit(() => this.moveWithin(0, e.shiftKey ? -1 : 1)); return }
        if (k === 'Escape') { stop(); this.cancelEdit(); return }
        if (k === 'F2') { stop(); this.editing.mode = this.editing.mode === 'edit' ? 'enter' : 'edit'; this.refreshUI(); return }
        if (k === 'F4') { stop(); this.toggleAbsolute(inp); return }
        if (/^Arrow/.test(k) && this.editing.mode === 'enter' && inp === this.input) {
            const dr = k === 'ArrowDown' ? 1 : k === 'ArrowUp' ? -1 : 0, dc = k === 'ArrowRight' ? 1 : k === 'ArrowLeft' ? -1 : 0
            stop()
            if (this.canPickRef()) {
                const base = this.pick ? (e.shiftKey ? this.pick.end2 : this.pick.cur) : { r: this.editing.r, c: this.editing.c }
                const [nr, nc] = this.step(base.r, base.c, dr, dc)
                if (e.shiftKey && this.pick) this.pickRefExtend(nr, nc)
                else this.pickRef(nr, nc)
                this.grid.scrollTo(nr, nc)
                return
            }
            this.commitEdit(() => this.moveActive(dr, dc))
            return
        }
        // 编辑状态下 Ctrl+Z 等交给文本框本身
    },

    // Ctrl+Enter：把输入写入整个选区
    commitToSelection() {
        const e = this.editing
        const text = this.input.value
        const ranges = this.sel.ranges.map(g => this.clampUsedForWrite(g))
        this.endEdit()
        this.input.value = ''
        this.setInputRanges(ranges, text, e)
    },

    // ---------- 引用点选 ----------
    canPickRef() {
        const e = this.editing
        if (!e) return false
        const t = this.input.value
        if (!t.startsWith('=')) return false
        if (this.pick) return true
        const s = this.activeEditor().selectionStart
        return PICK_BEFORE.test(t.slice(0, s))
    },
    activeEditor() { return document.activeElement === this.fxInput ? this.fxInput : this.input },

    refString(r1, c1, r2, c2) {
        const g = normRange({ r1, c1, r2, c2 })
        const m = this.sheet.mergeAt(g.r1, g.c1)
        let txt = g.r1 === g.r2 && g.c1 === g.c2 || (m && m.r1 === g.r1 && m.c1 === g.c1 && m.r2 === g.r2 && m.c2 === g.c2)
            ? cellName(g.r1, g.c1) : cellName(g.r1, g.c1) + ':' + cellName(g.r2, g.c2)
        if (this.sheet.id !== this.editing.sheetId) txt = quoteSheet(this.sheet.name) + '!' + txt
        return txt
    },

    pickRef(r, c, extend = false) {
        const inp = this.activeEditor()
        const t = inp.value
        if (extend && this.pick) return this.pickRefExtend(r, c)
        let start, end
        if (this.pick) { start = this.pick.start; end = this.pick.end }
        else { start = inp.selectionStart; end = inp.selectionEnd }
        const ref = this.refString(r, c, r, c)
        inp.value = t.slice(0, start) + ref + t.slice(end)
        this.pick = { start, end: start + ref.length, anchor: { r, c }, cur: { r, c }, end2: { r, c } }
        inp.setSelectionRange(this.pick.end, this.pick.end)
        this.syncEditors(inp)
        this.updateAssist(inp)
    },
    pickRefExtend(r, c) {
        if (!this.pick) return this.pickRef(r, c)
        const inp = this.activeEditor()
        const a = this.pick.anchor
        const ref = this.refString(a.r, a.c, r, c)
        const t = inp.value
        inp.value = t.slice(0, this.pick.start) + ref + t.slice(this.pick.end)
        this.pick.end = this.pick.start + ref.length
        this.pick.end2 = { r, c }
        inp.setSelectionRange(this.pick.end, this.pick.end)
        this.syncEditors(inp)
        const keep = this.pick
        this.pick = keep
    },

    // F4：在 A1 → $A$1 → A$1 → $A1 之间切换
    toggleAbsolute(inp) {
        const t = inp.value
        if (!t.startsWith('=')) return
        const pos = inp.selectionStart - 1
        const toks = tokenize(t.slice(1))
        const tk = toks.find(x => x.t === 'ref' && pos >= x.start && pos <= x.end) ?? [...toks].reverse().find(x => x.t === 'ref' && x.end <= pos + 1)
        if (!tk) return
        const cyc = ({ ar1, ac1 }) => ar1 && ac1 ? [true, false] : ar1 && !ac1 ? [false, true] : !ar1 && ac1 ? [false, false] : [true, true]
        const [nr, nc] = cyc(tk)
        const nt = { ...tk, ar1: nr, ac1: nc, ar2: nr, ac2: nc }
        const txt = refText(nt)
        inp.value = '=' + t.slice(1, tk.start + 1) + txt + t.slice(tk.end + 1)
        const caret = tk.start + 1 + txt.length
        inp.setSelectionRange(caret, caret)
        this.syncEditors(inp)
    },

    updateRefHighlights(text) {
        if (!text?.startsWith('=')) { this.refHighlights = null; this.grid.requestDraw(); return }
        const toks = tokenize(text.slice(1))
        const colorOf = new Map()
        const out = []
        const editSheet = this.sheets.find(s => s.id === this.editing?.sheetId) ?? this.sheet
        for (const t of toks) {
            if (t.t !== 'ref') continue
            const key = refText({ ...t, ar1: false, ac1: false, ar2: false, ac2: false }).toUpperCase()
            if (!colorOf.has(key)) colorOf.set(key, REF_COLORS[colorOf.size % REF_COLORS.length])
            const shName = t.sheet ?? editSheet.name
            if (shName.toLowerCase() !== this.sheet.name.toLowerCase()) continue
            out.push({ range: { r1: t.r1, c1: t.c1, r2: t.r2, c2: t.c2 }, color: colorOf.get(key) })
        }
        this.refHighlights = out
        this.grid.requestDraw()
    },

    // ---------- 自动补全与参数提示 ----------
    updateAssist(inp) {
        const t = inp.value
        if (!t.startsWith('=') || inp.selectionStart !== inp.selectionEnd) return this.hideAssist()
        const before = t.slice(0, inp.selectionStart)
        const m = /(^|[=(,+\-*/^&<>:;\s])([A-Za-z][A-Za-z0-9.]*)$/.exec(before)
        if (m && !/^[A-Za-z]{1,3}\d+$/.test(m[2]) || (m && FUNC_NAMES.some(n => n.startsWith(m[2].toUpperCase()) && n !== m[2].toUpperCase()) && !/\d$/.test(m[2]))) {
            const pre = m[2].toUpperCase()
            const list = FUNC_NAMES.filter(n => n.startsWith(pre)).slice(0, 12)
            if (list.length) { this.showAc(inp, list, pre.length); this.hintBox.hidden = true; return }
        }
        this.acBox.hidden = true
        this.acIndex = -1
        // 参数提示：找到光标所在的函数调用
        let depth = 0, arg = 0, inStr = false, fn = null
        for (let i = before.length - 1; i >= 0; i--) {
            const ch = before[i]
            if (ch === '"') { inStr = !inStr; continue }
            if (inStr) continue
            if (ch === ')') depth++
            else if (ch === '(') {
                if (depth === 0) { const mm = /([A-Za-z][A-Za-z0-9.]*)$/.exec(before.slice(0, i)); fn = mm?.[1].toUpperCase(); break }
                depth--
            } else if ((ch === ',' || ch === ';') && depth === 0) arg++
        }
        const info = fn && FUNC_INFO[fn]
        if (!info) { this.hintBox.hidden = true; return }
        const [sig, desc] = info
        const inner = sig.slice(sig.indexOf('(') + 1, sig.lastIndexOf(')'))
        const parts = inner.split(/,\s*/)
        const idx = Math.min(arg, parts.length - 1)
        const hl = parts.map((p, i) => i === idx || (i === parts.length - 1 && p.includes('…') && arg >= i) ? `<b>${escapeHTML(p)}</b>` : escapeHTML(p)).join(', ')
        this.hintBox.innerHTML = `<div class="sh-hint-sig">${escapeHTML(fn)}(${hl})</div><div class="sh-hint-desc">${escapeHTML(desc)}</div>`
        this.placeAssist(this.hintBox, inp)
    },
    showAc(inp, list, preLen) {
        this.acList = list
        this.acPre = preLen
        this.acIndex = 0
        this.acBox.replaceChildren(...list.map((n, i) => h('div.sh-ac-item' + (i === 0 ? '.active' : ''), {
            onpointerdown: e => { e.preventDefault(); this.acIndex = i; this.acAccept(inp) },
        }, h('span.sh-ac-name', n), h('span.sh-ac-desc', FUNC_INFO[n]?.[1] ?? ''))))
        this.placeAssist(this.acBox, inp)
    },
    acMove(d) {
        const n = this.acList.length
        this.acIndex = (this.acIndex + d + n) % n
        ;[...this.acBox.children].forEach((el, i) => el.classList.toggle('active', i === this.acIndex))
        this.acBox.children[this.acIndex]?.scrollIntoView({ block: 'nearest' })
    },
    acAccept(inp) {
        const name = this.acList[this.acIndex]
        if (!name) return
        const s = inp.selectionStart, t = inp.value
        const start = s - this.acPre
        inp.value = t.slice(0, start) + name + '(' + t.slice(s)
        const caret = start + name.length + 1
        inp.setSelectionRange(caret, caret)
        this.acBox.hidden = true
        this.pick = null
        this.syncEditors(inp)
        this.updateAssist(inp)
    },
    placeAssist(box, inp) {
        box.hidden = false
        const r = (inp === this.fxInput ? this.fxWrap : this.editBox).getBoundingClientRect()
        box.style.left = Math.min(r.left, innerWidth - box.offsetWidth - 8) + 'px'
        let top = r.bottom + 4
        if (top + box.offsetHeight > innerHeight - 8) top = r.top - box.offsetHeight - 4
        box.style.top = top + 'px'
    },
    hideAssist() {
        if (this.acBox) this.acBox.hidden = true
        if (this.hintBox) this.hintBox.hidden = true
        this.acIndex = -1
    },

    // ---------- 空闲状态按键 ----------
    onKey(e) {
        if (e.target !== this.input || this.editing) return false
        if (e.isComposing) return false
        const k = e.key, ks = keyString(e)
        if (this.navKey(e)) return true
        if (k === 'F2') { this.startEdit({ mode: 'edit' }); return true }
        if (k === 'Delete' || k === 'Backspace') {
            if (k === 'Backspace') { this.clearContents(); this.startEdit({ mode: 'enter', text: '' }); return true }
            this.clearContents()
            return true
        }
        if (k === 'Escape') { if (this.clip) { this.clip = null; this.stopAnts?.(); this.grid.requestDraw() } if (this.painter) { this.painter = null; this.refreshUI() } return true }
        if (ks === 'Ctrl+A') { this.selectAll(); return true }
        if (ks === 'Ctrl+Space') { this.selectCols(this.range.c1, this.range.c2); return true }
        if (ks === 'Shift+Space') { this.selectRows(this.range.r1, this.range.r2); return true }
        if (ks === 'Ctrl+;') { this.setInput(this.sel.r, this.sel.c, display(Math.floor(this.engine.evalFormula('TODAY()', this.sheet.id)), 'yyyy-mm-dd').text); return true }
        if (ks === 'Ctrl+Shift+;') { this.setInput(this.sel.r, this.sel.c, display(this.engine.evalFormula('NOW()', this.sheet.id) % 1, 'h:mm').text); return true }
        return false
    },

    // 编辑器声明：空闲时 Ctrl+Z / B / I / A … 由表格处理（复制粘贴仍由原生事件处理）
    ownsTyping(e) {
        if (e.target !== this.input || this.editing) return false
        return !/^Ctrl\+(C|X|V)$/.test(keyString(e))
    },

    toastWarn(msg) { import('../../core/dom.js').then(m => m.toast(msg, 'warn', 3600)) },
}

export { colName }
