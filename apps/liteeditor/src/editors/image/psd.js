// PSD 读写（ag-psd）
import { readPsd, writePsdUint8Array, initializeCanvas } from 'ag-psd'
import { ImageDoc, newLayer, makeCanvas, ctx2d } from './doc.js'

let inited = false
function init() {
    if (inited) return
    inited = true
    initializeCanvas((w, h) => makeCanvas(w, h), (w, h) => new ImageData(w, h))
}

const BLEND_IN = {
    'pass through': 'normal', normal: 'normal', multiply: 'multiply', screen: 'screen', overlay: 'overlay', 'soft light': 'soft-light',
    'hard light': 'hard-light', darken: 'darken', lighten: 'lighten', 'color dodge': 'color-dodge', 'color burn': 'color-burn',
    difference: 'difference', exclusion: 'exclusion', hue: 'hue', saturation: 'saturation', color: 'color', luminosity: 'luminosity',
    'linear burn': 'multiply', 'linear dodge': 'screen', 'vivid light': 'overlay', 'linear light': 'overlay', 'pin light': 'overlay',
}
const BLEND_OUT = Object.fromEntries(Object.entries({
    normal: 'normal', multiply: 'multiply', screen: 'screen', overlay: 'overlay', 'soft-light': 'soft light', 'hard-light': 'hard light',
    darken: 'darken', lighten: 'lighten', 'color-dodge': 'color dodge', 'color-burn': 'color burn', difference: 'difference', exclusion: 'exclusion',
    hue: 'hue', saturation: 'saturation', color: 'color', luminosity: 'luminosity',
}))

export function readPSD(bytes) {
    init()
    const psd = readPsd(bytes, { skipThumbnail: true, useImageData: false })
    const doc = new ImageDoc(psd.width, psd.height)
    const caveats = new Set()
    // 图层组展开为平铺的图层（组名作为前缀）
    const walk = (children, prefix = '', groupHidden = false, groupOpacity = 1) => {
        for (const ch of children ?? []) {
            if (ch.children) {
                caveats.add('图层组已展开为普通图层')
                walk(ch.children, prefix + (ch.name ?? '组') + ' / ', groupHidden || ch.hidden, groupOpacity * (ch.opacity ?? 1))
                continue
            }
            const w = Math.max(1, (ch.right ?? 0) - (ch.left ?? 0)), h = Math.max(1, (ch.bottom ?? 0) - (ch.top ?? 0))
            const layer = newLayer(w, h, {
                name: prefix + (ch.name ?? '图层'), x: ch.left ?? 0, y: ch.top ?? 0,
                visible: !(ch.hidden || groupHidden), opacity: (ch.opacity ?? 1) * groupOpacity,
                blend: BLEND_IN[ch.blendMode] ?? 'normal', locked: !!ch.protected?.position,
            })
            if (ch.blendMode && !BLEND_IN[ch.blendMode]) caveats.add('部分混合模式不受支持')
            if (ch.canvas) ctx2d(layer.canvas).drawImage(ch.canvas, 0, 0)
            if (ch.mask?.canvas) {
                // 蒙版转换为图层坐标下的 alpha 蒙版
                const m = makeCanvas(w, h)
                const mg = ctx2d(m)
                mg.fillStyle = (ch.mask.defaultColor ?? 255) > 127 ? '#fff' : 'rgba(0,0,0,0)'
                if ((ch.mask.defaultColor ?? 255) > 127) mg.fillRect(0, 0, w, h)
                const mc = ch.mask.canvas
                const tmp = makeCanvas(mc.width, mc.height)
                const tg = ctx2d(tmp)
                tg.drawImage(mc, 0, 0)
                const id = tg.getImageData(0, 0, mc.width, mc.height)
                for (let i = 0; i < id.data.length; i += 4) { id.data[i + 3] = id.data[i]; id.data[i] = id.data[i + 1] = id.data[i + 2] = 255 }
                tg.putImageData(id, 0, 0)
                mg.clearRect((ch.mask.left ?? 0) - layer.x, (ch.mask.top ?? 0) - layer.y, mc.width, mc.height)
                mg.drawImage(tmp, (ch.mask.left ?? 0) - layer.x, (ch.mask.top ?? 0) - layer.y)
                layer.mask = m
                layer.maskEnabled = !ch.mask.disabled
            }
            if (ch.text) {
                caveats.add('文字图层已栅格化（保留原文字内容）')
                layer.name = prefix + (ch.name ?? ch.text.text ?? '文字')
            }
            if (ch.effects) caveats.add('图层样式（投影、描边等）已忽略')
            if (ch.adjustment) caveats.add('调整图层已忽略')
            doc.layers.push(layer)
        }
    }
    walk(psd.children)
    // 没有图层时使用合成图
    if (!doc.layers.length && psd.canvas) {
        const l = newLayer(psd.width, psd.height, { name: '背景' })
        ctx2d(l.canvas).drawImage(psd.canvas, 0, 0)
        doc.layers.push(l)
    }
    doc.active = doc.layers.at(-1)?.id
    return { doc, caveats: [...caveats] }
}

export function writePSD(doc) {
    init()
    const composite = doc.composite()
    const children = doc.layers.map(l => {
        let canvas = l.canvas
        const out = {
            name: l.name, left: Math.round(l.x), top: Math.round(l.y), canvas,
            hidden: !l.visible, opacity: l.opacity, blendMode: BLEND_OUT[l.blend] ?? 'normal',
        }
        if (l.mask) {
            // 图层蒙版：alpha → 灰度
            const m = makeCanvas(l.mask.width, l.mask.height)
            const g = ctx2d(m)
            g.fillStyle = '#000'; g.fillRect(0, 0, m.width, m.height)
            const src = ctx2d(l.mask).getImageData(0, 0, m.width, m.height)
            const id = g.getImageData(0, 0, m.width, m.height)
            for (let i = 0; i < id.data.length; i += 4) id.data[i] = id.data[i + 1] = id.data[i + 2] = src.data[i + 3]
            g.putImageData(id, 0, 0)
            out.mask = { canvas: m, left: Math.round(l.x), top: Math.round(l.y), defaultColor: 0, disabled: l.maskEnabled === false }
        }
        return out
    })
    return writePsdUint8Array({ width: doc.w, height: doc.h, canvas: composite, children }, { generateThumbnail: true })
}
