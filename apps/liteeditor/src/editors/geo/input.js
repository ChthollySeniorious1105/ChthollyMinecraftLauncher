// 几何画板：代数输入栏 —— 像 GeoGebra 一样直接键入对象
// 支持的写法：
//   A = (1, 2)              点
//   f(x) = x^2 - 1 / y = 2x 函数
//   x²/9 + y²/4 = 1         方程曲线（二次方程自动识别为椭圆 / 双曲线 / 抛物线 / 圆）
//   a = 3                   参数滑块；已存在的参数则修改其值
//   2 + √3                  计算（在画板上显示结果）
import { h, toast } from '../../core/dom.js'
import { icon } from '../../core/icons.js'
import { attachMathKeyboard, mathKeyboard } from '../../core/mathkb.js'
import { compile, fmt } from './expr.js'
import { equationError, exprError } from './scene.js'
import { nextFreeName, validName } from './index.js'

const HISTORY_KEY = 'le.geo.inputHistory'

export function buildInputBar(ed) {
    const input = h('input.input.geo-input', {
        placeholder: '输入：A = (1, 2)　·　f(x) = x² − 2x　·　x²/9 + y²/4 = 1　·　y² = 4x　·　a = 3',
        spellcheck: false,
    })
    const status = h('span.geo-input-status')
    const hist = (() => { try { return JSON.parse(localStorage.getItem(HISTORY_KEY)) ?? [] } catch { return [] } })()
    let hi = hist.length
    const check = () => {
        const src = input.value.trim()
        if (!src) { status.textContent = ''; status.className = 'geo-input-status'; return }
        const r = parseCommand(src)
        status.textContent = r.error ? r.error : r.label
        status.className = 'geo-input-status' + (r.error ? ' err' : ' ok')
    }
    input.addEventListener('input', check)
    input.addEventListener('keydown', e => {
        e.stopPropagation()
        if (e.key === 'Enter' && !e.isComposing) {
            e.preventDefault()
            const src = input.value.trim()
            if (!src) return
            if (runCommand(ed, src)) {
                if (hist.at(-1) !== src) hist.push(src)
                if (hist.length > 60) hist.shift()
                localStorage.setItem(HISTORY_KEY, JSON.stringify(hist))
                hi = hist.length
                input.value = ''
                check()
            }
        } else if (e.key === 'ArrowUp' && hist.length) {
            e.preventDefault()
            hi = Math.max(0, hi - 1); input.value = hist[hi]; check()
        } else if (e.key === 'ArrowDown' && hist.length) {
            e.preventDefault()
            hi = Math.min(hist.length, hi + 1); input.value = hist[hi] ?? ''; check()
        } else if (e.key === 'Escape') {
            if (mathKeyboard.isOpen) mathKeyboard.close()
            else input.blur()
        }
    })
    ed.inputBox = input
    const bar = h('div.geo-inputbar',
        h('span.geo-input-icon', icon('square-function', 17)),
        attachMathKeyboard(input),
        status,
        h('button.btn.primary.small', { title: '添加 (Enter)', onclick: () => input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' })) }, icon('plus', 15), '添加'))
    return bar
}

// 识别输入：返回 { kind, label, ... } 或 { error }
export function parseCommand(src) {
    const s = src.replace(/：/g, ':').trim()
    let m
    // 点：A = (x, y) 或 (x, y)
    if ((m = /^(?:([\p{L}_][\p{L}\p{N}_']*)\s*=\s*)?\(\s*([^,()]+(?:\([^()]*\))?[^,()]*)\s*,\s*(.+)\)$/u.exec(s))) {
        const [, name, xs, ys] = m
        const ex = exprError(xs) || exprError(ys)
        if (ex) return { error: ex }
        return { kind: 'point', name, x: xs.trim(), y: ys.trim(), label: `点 ${name ?? ''}(${xs.trim()}, ${ys.trim()})` }
    }
    // 函数：f(x) = …
    if ((m = /^([\p{L}_][\p{L}\p{N}_']*)\s*\(\s*x\s*\)\s*=\s*(.+)$/u.exec(s))) {
        const err = exprError(m[2])
        return err ? { error: err } : { kind: 'func', name: m[1], expr: m[2], label: `函数 ${m[1]}(x) = ${m[2]}` }
    }
    // y = 只含 x 的表达式 → 函数图像
    if ((m = /^y\s*=\s*(.+)$/.exec(s)) && !/\by\b/.test(m[1])) {
        const c = compile(m[1])
        if (c.error) return { error: c.error }
        if (![...c.names].some(n => n === 'y')) return { kind: 'func', expr: m[1], label: `函数 y = ${m[1]}` }
    }
    // 名称 = 数值表达式（不含 x、y）→ 参数 / 计算
    if ((m = /^([\p{L}_][\p{L}\p{N}_']*)\s*=\s*([^=]+)$/u.exec(s)) && !['x', 'y'].includes(m[1])) {
        const c = compile(m[2])
        if (!c.error && !c.names.has('x') && !c.names.has('y')) return { kind: 'number', name: m[1], expr: m[2], label: `数值 ${m[1]} = ${m[2]}` }
    }
    // 包含 x 或 y 的方程
    if (s.includes('=') || /\b[xy]\b/.test(s)) {
        const err = equationError(s)
        if (err) return { error: err }
        return { kind: 'equation', expr: s, label: `曲线 ${s.includes('=') ? s : s + ' = 0'}` }
    }
    const err = exprError(s)
    if (err) return { error: err }
    return { kind: 'calc', expr: s, label: `计算 ${s}` }
}

export function runCommand(ed, src) {
    const r = parseCommand(src)
    if (r.error) { toast('无法识别：' + r.error, 'error'); return false }
    const sc = ed.scene
    let o
    if (r.kind === 'point') {
        const nx = Number(r.x), ny = Number(r.y)
        const exist = r.name && sc.byName(r.name)
        if (exist?.type === 'point' && Number.isFinite(nx) && Number.isFinite(ny)) { exist.x = nx; exist.y = ny; o = exist; sc.touch() }
        else {
            if (r.name && !validName(ed, r.name)) return false
            if (Number.isFinite(nx) && Number.isFinite(ny)) o = ed.addObject({ type: 'point', x: nx, y: ny }, { name: r.name })
            else {
                // 坐标包含表达式：用参数方程曲线上的单点表示太重，改为计算后固定
                const v = [compile(r.x).fn(sc.scope ?? {}), compile(r.y).fn(sc.scope ?? {})]
                if (!v.every(Number.isFinite)) { toast('坐标无法计算', 'error'); return false }
                o = ed.addObject({ type: 'point', x: v[0], y: v[1] }, { name: r.name })
            }
        }
    } else if (r.kind === 'func') {
        const exist = r.name && sc.byName(r.name)
        if (exist?.type === 'func') { exist.expr = r.expr; sc.touch(); o = exist }
        else {
            if (r.name && !validName(ed, r.name)) return false
            o = ed.addObject({ type: 'func', expr: r.expr, xmin: '', xmax: '' }, { name: r.name })
        }
    } else if (r.kind === 'number') {
        const exist = sc.byName(r.name)
        const val = compile(r.expr).fn(sc.scope ?? {})
        if (exist?.type === 'slider' && Number.isFinite(val)) {
            exist.value = val
            exist.min = Math.min(exist.min, val); exist.max = Math.max(exist.max, val)
            o = exist
        } else if (exist?.type === 'calc') { exist.expr = r.expr; sc.touch(); o = exist }
        else if (exist) { toast(`名称 “${r.name}” 已被使用`, 'error'); return false }
        else if (!validName(ed, r.name)) return false
        else if (/^-?\d+(\.\d+)?$/.test(r.expr.trim())) {
            // 纯数字：创建滑块，便于拖动调整
            const span = Math.max(5, Math.abs(val) * 2)
            o = ed.addObject({ type: 'slider', value: val, min: Math.min(-span, val), max: Math.max(span, val), step: Math.abs(val) >= 10 ? 1 : 0.1 }, { name: r.name })
            ed.placeAnnotation(o)
        } else {
            o = ed.addObject({ type: 'calc', expr: r.expr }, { name: r.name })
            ed.placeAnnotation(o)
        }
    } else if (r.kind === 'equation') {
        o = ed.addObject({ type: 'equation', expr: r.expr })
    } else {
        o = ed.addObject({ type: 'calc', expr: r.expr }, { name: nextFreeName(sc, ['v1', 'v2', 'v3', 'v4', 'v5', 'v6']) })
        ed.placeAnnotation(o)
    }
    ed.commit(r.label)
    ed.selected = new Set([o.id])
    ed.afterChange()
    const v = sc.val(o.id)
    if (v?.kind === 'conic' || v?.kind === 'circle') toast(`${o.name}：${v.kind === 'circle' ? '圆 · r = ' + fmt(v.r, 3) : sc.valueText(o)}`, 'success')
    else if (v?.kind === 'number' && r.kind === 'calc') toast(`${src} = ${fmt(v.v, 6)}`, 'success')
    return true
}
