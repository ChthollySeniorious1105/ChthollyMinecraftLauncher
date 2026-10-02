// 截图遮罩：在冻结的屏幕图像上框选区域，可调整、标注（矩形 / 箭头 / 画笔 / 文字 / 马赛克），然后完成
import './shot.css'

const bg = document.getElementById('bg'), ov = document.getElementById('ov')
const bar = document.getElementById('bar'), tip = document.getElementById('tip')
const W = innerWidth, H = innerHeight
const dpr = devicePixelRatio || 1
for (const c of [bg, ov]) { c.width = W * dpr; c.height = H * dpr; c.style.width = W + 'px'; c.style.height = H + 'px' }
const g = bg.getContext('2d'), o = ov.getContext('2d')
let img, scale = 1
let sel = null          // { x, y, w, h }（CSS 像素）
let drag = null
let tool = null          // 标注工具
let color = '#ef4444'
const marks = []         // 标注

const init = await window.lite.capture.shotInit()
scale = init.scale
// rect 模式：仅选择录制区域，不提供标注
const rectMode = init.mode === 'rect'
if (rectMode) tip.textContent = '拖动选择录制区域 · 单击选择整屏 · 右键 / Esc 取消 · Enter 开始录制'
img = new Image()
img.src = init.dataURL
await img.decode()
g.drawImage(img, 0, 0, W * dpr, H * dpr)
draw()

const norm = r => ({ x: Math.min(r.x, r.x + r.w), y: Math.min(r.y, r.y + r.h), w: Math.abs(r.w), h: Math.abs(r.h) })
function draw() {
    o.setTransform(dpr, 0, 0, dpr, 0, 0)
    o.clearRect(0, 0, W, H)
    o.fillStyle = 'rgba(0,0,0,.45)'
    o.fillRect(0, 0, W, H)
    if (!sel) return
    const s = norm(sel)
    o.clearRect(s.x, s.y, s.w, s.h)
    for (const m of marks) drawMark(o, m)
    if (drag?.mark) drawMark(o, drag.mark)
    o.strokeStyle = '#3b82f6'; o.lineWidth = 1.5
    o.strokeRect(s.x + 0.5, s.y + 0.5, s.w, s.h)
    if (!tool) for (const [hx, hy] of handles(s)) { o.fillStyle = '#fff'; o.fillRect(hx - 4, hy - 4, 8, 8); o.strokeRect(hx - 4, hy - 4, 8, 8) }
    // 尺寸标签
    const label = `${Math.round(s.w * scale)} × ${Math.round(s.h * scale)}`
    o.font = '12px "Microsoft YaHei UI", sans-serif'
    const tw = o.measureText(label).width + 12
    const ly = s.y > 26 ? s.y - 24 : s.y + 4
    o.fillStyle = 'rgba(15,23,42,.85)'; o.fillRect(s.x, ly, tw, 20)
    o.fillStyle = '#fff'; o.fillText(label, s.x + 6, ly + 14)
    placeBar(s)
}
function drawMark(c, m) {
    c.save()
    c.strokeStyle = c.fillStyle = m.color
    c.lineWidth = m.width ?? 3
    c.lineCap = c.lineJoin = 'round'
    if (m.kind === 'rect') c.strokeRect(m.x, m.y, m.w, m.h)
    else if (m.kind === 'ellipse') { c.beginPath(); c.ellipse(m.x + m.w / 2, m.y + m.h / 2, Math.abs(m.w / 2), Math.abs(m.h / 2), 0, 0, Math.PI * 2); c.stroke() }
    else if (m.kind === 'arrow') {
        const x2 = m.x + m.w, y2 = m.y + m.h, a = Math.atan2(m.h, m.w), L = 14
        c.beginPath(); c.moveTo(m.x, m.y); c.lineTo(x2, y2); c.stroke()
        c.beginPath(); c.moveTo(x2, y2); c.lineTo(x2 - L * Math.cos(a - 0.45), y2 - L * Math.sin(a - 0.45)); c.lineTo(x2 - L * Math.cos(a + 0.45), y2 - L * Math.sin(a + 0.45)); c.closePath(); c.fill()
    } else if (m.kind === 'pen') { c.beginPath(); m.pts.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y))); c.stroke() }
    else if (m.kind === 'text') { c.font = 'bold 20px "Microsoft YaHei UI", sans-serif'; c.textBaseline = 'top'; c.fillText(m.text, m.x, m.y) }
    else if (m.kind === 'mosaic') {
        const r = norm(m), b = 10
        for (let y = r.y; y < r.y + r.h; y += b) for (let x = r.x; x < r.x + r.w; x += b) {
            const d = g.getImageData(Math.round((x + b / 2) * dpr), Math.round((y + b / 2) * dpr), 1, 1).data
            c.fillStyle = `rgb(${d[0]},${d[1]},${d[2]})`
            c.fillRect(x, y, Math.min(b, r.x + r.w - x), Math.min(b, r.y + r.h - y))
        }
    }
    c.restore()
}
const handles = s => [[s.x, s.y], [s.x + s.w / 2, s.y], [s.x + s.w, s.y], [s.x + s.w, s.y + s.h / 2], [s.x + s.w, s.y + s.h], [s.x + s.w / 2, s.y + s.h], [s.x, s.y + s.h], [s.x, s.y + s.h / 2]]
const HANDLE_KEYS = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']
function hitHandle(p, s) {
    const hs = handles(s)
    for (let i = 0; i < hs.length; i++) if (Math.abs(hs[i][0] - p.x) < 7 && Math.abs(hs[i][1] - p.y) < 7) return HANDLE_KEYS[i]
    if (p.x > s.x && p.x < s.x + s.w && p.y > s.y && p.y < s.y + s.h) return 'move'
    return null
}

// ---------- 工具栏 ----------
const TOOLS = [['rect', '矩形', '▭'], ['ellipse', '椭圆', '◯'], ['arrow', '箭头', '↗'], ['pen', '画笔', '✎'], ['text', '文字', 'A'], ['mosaic', '马赛克', '▦']]
const COLORS = ['#ef4444', '#f59e0b', '#22c55e', '#3b82f6', '#ffffff', '#111827']
function buildBar() {
    bar.innerHTML = ''
    if (rectMode) {
        const cancel = document.createElement('button'); cancel.textContent = '✕ 取消'; cancel.className = 'wide danger'; cancel.onclick = () => finish(null)
        const ok = document.createElement('button'); ok.textContent = '● 开始录制'; ok.className = 'primary'; ok.onclick = () => finish('done')
        bar.append(cancel, ok)
        return
    }
    for (const [id, label, glyph] of TOOLS) {
        const b = document.createElement('button')
        b.textContent = glyph; b.title = label
        b.className = tool === id ? 'on' : ''
        b.onclick = () => { tool = tool === id ? null : id; buildBar(); draw() }
        bar.append(b)
    }
    bar.append(sep())
    for (const c of COLORS) {
        const b = document.createElement('button')
        b.className = 'sw' + (c === color ? ' on' : '')
        b.style.background = c
        b.onclick = () => { color = c; buildBar() }
        bar.append(b)
    }
    bar.append(sep())
    const undo = document.createElement('button'); undo.textContent = '↶'; undo.title = '撤销标注 (Ctrl Z)'; undo.onclick = () => { marks.pop(); draw() }
    const cancel = document.createElement('button'); cancel.textContent = '✕'; cancel.title = '取消 (Esc)'; cancel.className = 'danger'; cancel.onclick = () => finish(null)
    const edit = document.createElement('button'); edit.textContent = '编辑'; edit.title = '在图像编辑器中打开'; edit.className = 'wide'; edit.onclick = () => finish('edit')
    const copy = document.createElement('button'); copy.textContent = '复制'; copy.title = '复制到剪贴板 (Ctrl C)'; copy.className = 'wide'; copy.onclick = () => finish('copy')
    const save = document.createElement('button'); save.textContent = '保存'; save.title = '保存为文件 (Ctrl S)'; save.className = 'wide'; save.onclick = () => finish('save')
    const ok = document.createElement('button'); ok.textContent = '✓ 完成'; ok.title = '完成 (Enter)'; ok.className = 'primary'; ok.onclick = () => finish('done')
    bar.append(undo, cancel, edit, copy, save, ok)
}
const sep = () => { const s = document.createElement('i'); return s }
function placeBar(s) {
    bar.hidden = false
    const bw = bar.offsetWidth || 520, bh = 38
    let x = Math.min(W - bw - 6, Math.max(6, s.x + s.w - bw))
    let y = s.y + s.h + 8
    if (y + bh > H - 6) y = Math.max(6, s.y - bh - 8)
    if (y < 6) y = s.y + 8
    bar.style.left = x + 'px'
    bar.style.top = y + 'px'
}

// ---------- 交互 ----------
const pos = e => ({ x: Math.max(0, Math.min(W, e.clientX)), y: Math.max(0, Math.min(H, e.clientY)) })
ov.addEventListener('pointerdown', e => {
    if (e.button === 2) return
    ov.setPointerCapture(e.pointerId)
    const p = pos(e)
    tip.hidden = true
    if (sel && tool) {
        const s = norm(sel)
        if (tool === 'text') {
            // 行内文字输入框（Electron 不支持 prompt）
            const inp = document.createElement('input')
            inp.className = 'shot-text'
            Object.assign(inp.style, { left: p.x + 'px', top: p.y + 'px', color })
            document.body.append(inp)
            setTimeout(() => inp.focus())
            const done = ok => {
                if (inp.dataset.done) return
                inp.dataset.done = '1'
                if (ok && inp.value.trim()) marks.push({ kind: 'text', x: p.x, y: p.y + 2, text: inp.value, color })
                inp.remove()
                draw()
            }
            inp.addEventListener('keydown', ev => { ev.stopPropagation(); if (ev.key === 'Enter') done(true); if (ev.key === 'Escape') done(false) })
            inp.addEventListener('blur', () => done(true))
            return
        }
        drag = { mode: 'mark', mark: tool === 'pen' ? { kind: 'pen', pts: [p], color } : { kind: tool, x: p.x, y: p.y, w: 0, h: 0, color } }
        void s
        return
    }
    const hit = sel ? hitHandle(p, norm(sel)) : null
    if (hit) drag = { mode: hit, p0: p, s0: norm(sel) }
    else { sel = { x: p.x, y: p.y, w: 0, h: 0 }; drag = { mode: 'new', p0: p } }
    draw()
})
ov.addEventListener('pointermove', e => {
    const p = pos(e)
    if (!drag) {
        ov.style.cursor = sel && !tool ? ({ move: 'move', nw: 'nwse-resize', se: 'nwse-resize', ne: 'nesw-resize', sw: 'nesw-resize', n: 'ns-resize', s: 'ns-resize', e: 'ew-resize', w: 'ew-resize' }[hitHandle(p, norm(sel))] ?? 'crosshair') : 'crosshair'
        return
    }
    if (drag.mode === 'mark') {
        const m = drag.mark
        if (m.kind === 'pen') m.pts.push(p)
        else { m.w = p.x - m.x; m.h = p.y - m.y }
    } else if (drag.mode === 'new') sel = { x: drag.p0.x, y: drag.p0.y, w: p.x - drag.p0.x, h: p.y - drag.p0.y }
    else {
        const s = { ...drag.s0 }, dx = p.x - drag.p0.x, dy = p.y - drag.p0.y
        if (drag.mode === 'move') { s.x = Math.max(0, Math.min(W - s.w, s.x + dx)); s.y = Math.max(0, Math.min(H - s.h, s.y + dy)) }
        else {
            if (drag.mode.includes('w')) { s.x += dx; s.w -= dx }
            if (drag.mode.includes('e')) s.w += dx
            if (drag.mode.includes('n')) { s.y += dy; s.h -= dy }
            if (drag.mode.includes('s')) s.h += dy
        }
        sel = s
    }
    draw()
})
ov.addEventListener('pointerup', e => {
    const d = drag
    drag = null
    if (!d) return
    if (d.mode === 'mark') { marks.push(d.mark); buildBar(); draw(); return }
    if (d.mode === 'new') {
        const s = norm(sel)
        // 单击：整个屏幕
        if (s.w < 4 && s.h < 4) sel = { x: 0, y: 0, w: W, h: H }
        buildBar()
    }
    draw()
    void e
})
ov.addEventListener('dblclick', () => { if (sel && !tool) finish('done') })
ov.addEventListener('contextmenu', e => { e.preventDefault(); if (sel && !marks.length) { sel = null; bar.hidden = true; tip.hidden = false; draw() } else finish(null) })
addEventListener('keydown', e => {
    if (e.key === 'Escape') finish(null)
    if (e.key === 'Enter' && sel) finish('done')
    if (e.ctrlKey && e.key.toLowerCase() === 'z') { marks.pop(); draw() }
    if (e.ctrlKey && e.key.toLowerCase() === 'c' && sel && !rectMode) finish('copy')
    if (e.ctrlKey && e.key.toLowerCase() === 's' && sel && !rectMode) { e.preventDefault(); finish('save') }
})

// ---------- 完成：按原始分辨率裁剪并合成标注 ----------
function finish(action) {
    if (!action || !sel) return window.lite.capture.shotDone(null)
    const s = norm(sel)
    if (rectMode) return window.lite.capture.shotDone({ rect: { x: s.x, y: s.y, w: s.w, h: s.h }, cssWidth: W, scale, action })
    const k = img.naturalWidth / W
    const out = document.createElement('canvas')
    out.width = Math.max(1, Math.round(s.w * k)); out.height = Math.max(1, Math.round(s.h * k))
    const c = out.getContext('2d')
    c.drawImage(img, s.x * k, s.y * k, s.w * k, s.h * k, 0, 0, out.width, out.height)
    c.scale(k, k)
    c.translate(-s.x, -s.y)
    for (const m of marks) drawMark(c, m)
    window.lite.capture.shotDone({ dataURL: out.toDataURL('image/png'), width: out.width, height: out.height, action })
}
