// 数学虚拟键盘：为任意 <input> / <textarea> 提供平方、开根、括号、希腊字母等符号输入
// 用法：attachMathKeyboard(input) 为输入框添加键盘按钮；mathKeyboard.open(input) 直接打开
// 键盘不会抢走输入框焦点（按钮使用 pointerdown 阻止默认行为），可以和物理键盘混合使用
import { h } from './dom.js'
import { icon } from './icons.js'

// 键定义：[显示, 插入文本, 光标回退字符数, 标题]；插入文本中的 “|” 为插入后的光标位置
const K = (label, ins = label, title) => ({ label, ins, title })
const PAGES = {
    base: {
        label: '基本',
        rows: [
            [K('x'), K('y'), K('x²', '^2', '平方'), K('x³', '^3', '立方'), K('xⁿ', '^(|)', '乘方'), K('√', 'sqrt(|)', '平方根'), K('ⁿ√', 'nroot(|, 3)', 'n 次方根'), K('|x|', 'abs(|)', '绝对值'), K('7'), K('8'), K('9'), K('÷', '/', '除')],
            [K('(', '(|)', '括号'), K(')'), K('[', '[|]', '方括号'), K(']'), K('π', 'pi'), K('e'), K('°', '°', '度'), K('!', '!', '阶乘'), K('4'), K('5'), K('6'), K('×', '*', '乘')],
            [K('='), K('<'), K('>'), K('≤', '<='), K('≥', '>='), K(','), K('a'), K('b'), K('1'), K('2'), K('3'), K('−', '-', '减')],
            [K('frac', '(|)/()', '分式'), K('1/x', '1/(|)', '倒数'), K('x⁻¹', '^(-1)', '负一次方'), K('eˣ', 'exp(|)', '指数'), K('t'), K('θ'), K('k'), K('n'), K('0'), K('.'), K('%'), K('+')],
        ],
    },
    func: {
        label: '函数',
        rows: [
            [K('sin', 'sin(|)'), K('cos', 'cos(|)'), K('tan', 'tan(|)'), K('cot', 'cot(|)'), K('sec', 'sec(|)'), K('csc', 'csc(|)')],
            [K('arcsin', 'arcsin(|)'), K('arccos', 'arccos(|)'), K('arctan', 'arctan(|)'), K('sinh', 'sinh(|)'), K('cosh', 'cosh(|)'), K('tanh', 'tanh(|)')],
            [K('ln', 'ln(|)'), K('lg', 'lg(|)'), K('log₂', 'log2(|)'), K('logₐb', 'log(|, 2)', 'log(x, 底数)'), K('exp', 'exp(|)'), K('∛', 'cbrt(|)', '立方根')],
            [K('floor', 'floor(|)', '向下取整'), K('ceil', 'ceil(|)', '向上取整'), K('round', 'round(|)', '四舍五入'), K('sgn', 'sign(|)', '符号'), K('min', 'min(|, )'), K('max', 'max(|, )')],
            [K('mod', 'mod(|, )', '取模'), K('if', 'if(|, , )', 'if(条件, 真值, 假值)'), K('rad', 'rad(|)', '角度转弧度'), K('deg', 'deg(|)', '弧度转角度'), K('random', 'random()'), K('fact', 'fact(|)', '阶乘')],
        ],
    },
    greek: {
        label: 'αβγ',
        rows: [
            [K('α'), K('β'), K('γ'), K('δ'), K('ε'), K('ζ'), K('η'), K('θ'), K('λ'), K('μ')],
            [K('ξ'), K('ρ'), K('σ'), K('τ'), K('φ'), K('ψ'), K('ω'), K('Δ'), K('Φ'), K('Ω')],
            [K('²'), K('³'), K('√'), K('∛'), K('≠'), K('±'), K('∞', 'Infinity'), K('′', "'"), K('·'), K('…', '...')],
        ],
    },
    abc: {
        label: 'abc',
        rows: [
            [...'qwertyuiop'].map(c => K(c)),
            [...'asdfghjkl'].map(c => K(c)),
            [K('⇧', null, '大写'), ...[...'zxcvbnm'].map(c => K(c)), K('_')],
        ],
    },
}

class MathKeyboard {
    constructor() {
        this.page = 'base'
        this.upper = false
        this.target = null
        this.el = null
    }

    build() {
        const keep = e => e.preventDefault()   // 保持输入框焦点
        this.tabs = h('div.mk-tabs')
        this.body = h('div.mk-body')
        this.el = h('div.math-kb', { onpointerdown: keep, onmousedown: keep },
            h('div.mk-head',
                this.tabs,
                h('div.mk-flex'),
                h('button.mk-key.mk-ctrl', { title: '左移', onpointerup: () => this.move(-1) }, icon('chevron-left', 16)),
                h('button.mk-key.mk-ctrl', { title: '右移', onpointerup: () => this.move(1) }, icon('chevron-right', 16)),
                h('button.mk-key.mk-ctrl', { title: '退格', onpointerup: () => this.backspace() }, icon('delete', 16)),
                h('button.mk-key.mk-ctrl', { title: '清空', onpointerup: () => this.clear() }, icon('eraser', 16)),
                h('button.mk-key.mk-ctrl.mk-enter', { title: '确定 (Enter)', onpointerup: () => this.enter() }, icon('corner-down-left', 16)),
                h('button.mk-key.mk-ctrl', { title: '关闭键盘', onpointerup: () => this.close() }, icon('chevron-down', 16))),
            this.body)
        document.body.append(this.el)
        this.render()
        // 目标输入框失去焦点（且焦点没有移到其他可输入元素）时自动关闭
        this.onFocus = e => {
            const t = e.target
            if (this.el.contains(t)) return
            if (t?.matches?.('input[data-mathkb], textarea[data-mathkb]')) { this.target = t; this.place(); return }
            if (t?.matches?.('input, textarea')) this.close()
        }
        document.addEventListener('focusin', this.onFocus)
    }

    render() {
        this.tabs.replaceChildren(...Object.entries(PAGES).map(([id, p]) =>
            h('button.mk-tab' + (id === this.page ? '.active' : ''), { onpointerup: () => { this.page = id; this.render() } }, p.label)))
        const page = PAGES[this.page]
        this.body.replaceChildren(...page.rows.map(r => h('div.mk-row', { style: { '--n': r.length } }, r.map(k => {
            const label = this.page === 'abc' && this.upper && k.ins ? k.label.toUpperCase() : k.label
            const cls = /^[0-9.]$/.test(k.label) ? '.mk-num' : /^[+−×÷=]$/.test(k.label) ? '.mk-op' : ''
            return h('button.mk-key' + cls + (k.label === '⇧' && this.upper ? '.active' : ''), {
                title: k.title ?? '',
                onpointerup: () => {
                    if (k.label === '⇧') { this.upper = !this.upper; this.render(); return }
                    this.insert(this.page === 'abc' && this.upper ? k.ins.toUpperCase() : k.ins)
                },
            }, label === 'frac' ? h('span.mk-frac', h('i', '□'), h('i', '□')) : label)
        }))))
    }

    open(input) {
        if (!this.el) this.build()
        this.target = input
        input.dataset.mathkb ??= '1'
        this.el.classList.add('show')
        this.place()
        input.focus()
    }
    close() { this.el?.classList.remove('show') }
    get isOpen() { return !!this.el?.classList.contains('show') }
    toggle(input) { this.isOpen && this.target === input ? this.close() : this.open(input) }

    // 键盘放在屏幕底部；若挡住输入框，则放到输入框上方
    place() {
        const r = this.target?.getBoundingClientRect()
        if (!r) return
        this.el.style.top = ''
        this.el.style.bottom = '12px'
        const kb = this.el.getBoundingClientRect()
        if (r.bottom > kb.top - 8) { this.el.style.bottom = ''; this.el.style.top = Math.max(8, r.top - kb.height - 10) + 'px' }
    }

    // 当前输入目标：优先使用拥有焦点的数学输入框
    get input() {
        const a = document.activeElement
        if (a?.matches?.('input[data-mathkb], textarea[data-mathkb]')) this.target = a
        return this.target?.isConnected ? this.target : null
    }

    // 在光标处插入；ins 中的 “|” 标记插入后的光标位置；选中文字会被放进括号里
    insert(ins) {
        const t = this.input
        if (!t) return
        const a = t.selectionStart ?? t.value.length, b = t.selectionEnd ?? a
        const sel = t.value.slice(a, b)
        let text = ins, caret = ins.indexOf('|')
        if (caret >= 0) {
            text = ins.replace('|', sel)
            caret += sel.length
        } else caret = text.length
        t.setRangeText(text, a, b, 'end')
        t.setSelectionRange(a + caret, a + caret)
        t.dispatchEvent(new Event('input', { bubbles: true }))
    }
    move(d) {
        const t = this.input
        if (!t) return
        const p = Math.max(0, Math.min(t.value.length, (d < 0 ? t.selectionStart : t.selectionEnd) + d))
        t.setSelectionRange(p, p)
    }
    backspace() {
        const t = this.input
        if (!t) return
        const a = t.selectionStart, b = t.selectionEnd
        if (a !== b) t.setRangeText('', a, b, 'end')
        else if (a > 0) {
            // 删除 “函数名(” 这样的整体，以及成对的空括号
            const before = t.value.slice(0, a)
            const m = /[a-z]+\($/i.exec(before)
            const n = m ? m[0].length : 1
            const pair = t.value[a] === ')' && t.value[a - 1] === '(' ? 1 : 0
            t.setRangeText('', a - n, a + pair, 'end')
        }
        t.dispatchEvent(new Event('input', { bubbles: true }))
    }
    clear() {
        const t = this.input
        if (!t) return
        t.value = ''
        t.dispatchEvent(new Event('input', { bubbles: true }))
    }
    enter() {
        const t = this.input
        if (!t) return
        t.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }))
    }
}

export const mathKeyboard = new MathKeyboard()

// 为输入框加上键盘开关按钮：返回包裹后的元素
export function attachMathKeyboard(input, { auto = false } = {}) {
    input.dataset.mathkb = '1'
    input.spellcheck = false
    const b = h('button.mk-toggle', { type: 'button', title: '数学键盘', onmousedown: e => e.preventDefault(), onclick: () => mathKeyboard.toggle(input) }, icon('keyboard', 15))
    if (auto) input.addEventListener('focus', () => mathKeyboard.open(input))
    return h('div.mk-field', input, b)
}

// 为对话框中的若干输入框统一启用（传入 formDialog 的 onOpen 容器）
export function enhanceInputs(root, selector = 'input[type=text], input:not([type])') {
    for (const inp of root.querySelectorAll(selector)) {
        if (inp.dataset.mathkb) continue
        // 先占位，再把输入框移入包裹元素
        const mark = document.createComment('')
        inp.replaceWith(mark)
        mark.replaceWith(attachMathKeyboard(inp))
    }
}
