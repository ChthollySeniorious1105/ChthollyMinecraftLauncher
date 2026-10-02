// 演示文稿示例
import { newDeck, newSlide, layoutEls, themeOf, newId, defaultChart, sizeOf } from './model.js'

const put = (slide, i, html) => { if (slide.els[i]) slide.els[i].html = html }

export function buildSample(name, ratio) {
    if (name === 'pitch') return pitch(ratio)
    const deck = newDeck(ratio, name === 'dark' ? 'dark' : 'clean')
    return deck
}

function pitch(ratio) {
    const deck = newDeck(ratio, 'gradient')
    const t = themeOf(deck)
    const { w, h } = sizeOf(deck)
    deck.slides = []

    // 1. 标题页
    const s1 = newSlide(deck, 'title')
    put(s1, 0, 'LiteEditor 项目介绍')
    put(s1, 1, '一个应用，修图、作图、写文档、做表格、做演示')
    s1.els[0].anim = { type: 'zoom', dur: 0.7, order: 1 }
    s1.els[1].anim = { type: 'flyUp', dur: 0.6, order: 2 }
    s1.els.push({ id: newId(), type: 'shape', shape: 'ellipse', x: w - 380, y: -140, w: 520, h: 520, rot: 0, fill: { type: 'solid', color: 'rgba(255,255,255,0.10)' }, stroke: { width: 0 } })
    s1.els.push({ id: newId(), type: 'shape', shape: 'ellipse', x: -160, y: h - 260, w: 420, h: 420, rot: 0, fill: { type: 'solid', color: 'rgba(255,255,255,0.08)' }, stroke: { width: 0 } })
    s1.els.unshift(...s1.els.splice(2))
    s1.transition = { type: 'fade', dur: 0.8 }
    deck.slides.push(s1)

    // 2. 要点
    const s2 = newSlide(deck, 'content')
    put(s2, 0, '为什么做 LiteEditor')
    put(s2, 1, '<ul><li>日常办公要在多个软件之间来回切换</li><li>大型套件启动慢、占用高、功能用不到</li><li>需要一个<b>轻量、离线、界面统一</b>的编辑工具</li><li>文件全部在本地处理，保护隐私</li></ul>')
    s2.els[1].anim = { type: 'flyLeft', dur: 0.6, order: 1 }
    s2.transition = { type: 'push', dur: 0.6 }
    deck.slides.push(s2)

    // 3. 两栏：形状 + 文本
    const s3 = newSlide(deck, 'titleOnly')
    put(s3, 0, '五大编辑器')
    const items = [['图像', '图层 · 选区 · 滤镜', '#22d3ee'], ['几何', '尺规作图 · 函数', '#a78bfa'], ['文档', 'DOCX · 公式', '#60a5fa'], ['表格', '公式 · 图表', '#4ade80'], ['演示', '动画 · 放映', '#fb923c']]
    const cw = (w - 220 - 4 * 36) / 5
    items.forEach(([name, desc, c], i) => {
        s3.els.push({
            id: newId(), type: 'shape', shape: 'roundRect', radius: 36, x: 110 + i * (cw + 36), y: 300, w: cw, h: 520, rot: 0,
            fill: { type: 'solid', color: 'rgba(255,255,255,0.14)' }, stroke: { color: 'rgba(255,255,255,0.35)', width: 3 },
            html: `<div style="font-size:64px;font-weight:800;color:${c}">${name}</div><div style="font-size:30px;margin-top:18px;opacity:.9">${desc}</div>`,
            style: { color: '#ffffff', size: 30, align: 'center', valign: 'middle', font: t.font },
            anim: { type: 'bounce', dur: 0.6, order: 1 + i },
        })
    })
    s3.transition = { type: 'zoom', dur: 0.6 }
    deck.slides.push(s3)

    // 4. 图表
    const s4 = newSlide(deck, 'titleOnly')
    put(s4, 0, '用户增长')
    const ch = defaultChart({ accent: '#fde68a', accent2: '#ffffff' })
    ch.title = ''
    ch.labels = ['1 月', '2 月', '3 月', '4 月', '5 月', '6 月']
    ch.series = [{ name: '活跃用户（千）', values: [12, 19, 27, 38, 52, 71], color: '#fde68a' }, { name: '新增用户（千）', values: [5, 8, 11, 14, 19, 26], color: '#ffffff' }]
    s4.els.push({ id: newId(), type: 'shape', shape: 'roundRect', radius: 30, x: 110, y: 250, w: w - 220, h: h - 330, rot: 0, fill: { type: 'solid', color: '#ffffff' }, stroke: { width: 0 }, shadow: true })
    s4.els.push({ id: newId(), type: 'chart', x: 150, y: 280, w: w - 300, h: h - 390, rot: 0, chart: { ...ch, series: [{ ...ch.series[0], color: '#4f46e5' }, { ...ch.series[1], color: '#db2777' }] }, anim: { type: 'wipe', dur: 0.8, order: 1 } })
    s4.transition = { type: 'wipe', dur: 0.7 }
    deck.slides.push(s4)

    // 5. 公式 + 结束
    const s5 = newSlide(deck, 'title')
    put(s5, 0, '谢谢观看')
    put(s5, 1, '欢迎试用与反馈')
    s5.els.push({ id: newId(), type: 'math', x: w / 2 - 500, y: h * 0.32 + 330, w: 1000, h: 160, rot: 0, tex: 'e^{i\\pi} + 1 = 0', color: '#fde68a', size: 64, anim: { type: 'fade', dur: 0.8, order: 1 } })
    s5.transition = { type: 'flip', dur: 0.8 }
    deck.slides.push(s5)
    s5.notes = '感谢大家！可以现场演示几何画板的欧拉线。'
    s1.notes = '开场：介绍项目背景与目标。'
    return deck
}

export { layoutEls }
