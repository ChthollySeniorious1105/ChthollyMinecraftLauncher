// 图像编辑：菜单栏、右键菜单、快捷键
import { contextMenu } from '../../core/menu.js'
import { keyString } from '../../core/menu.js'
import { ADJUSTMENTS, FILTERS } from './filters.js'
import { TOOLS } from './tools.js'

export function installMenus(Ed) {
    const P = Ed.prototype

    P.menus = function () {
        const hasSel = () => !!this.doc.selection
        const filterGroups = {}
        for (const [k, f] of Object.entries(FILTERS)) (filterGroups[f.group] ??= []).push([k, f])
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => this.copySel(true) },
                    { label: '拷贝', icon: 'copy', key: 'Ctrl+C', run: () => this.copySel(false) },
                    { label: '合并拷贝', key: 'Ctrl+Shift+C', run: () => this.copySel(false, true) },
                    { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.pasteClip(true) },
                    { label: '清除', icon: 'eraser', key: 'Delete', altKey: 'Backspace', run: () => this.clearSelection() },
                    '-',
                    { label: '填充前景色', icon: 'paint-bucket', key: 'Alt+Backspace', run: () => this.fillSelection(false) },
                    { label: '填充背景色', key: 'Ctrl+Backspace', run: () => this.fillSelection(true) },
                    { label: '描边…', run: () => this.strokeSelection() },
                    '-',
                    { label: '自由变换', icon: 'scaling', key: 'Ctrl+T', run: () => this.startTransform() },
                    { label: '数值变换…', run: () => this.transformDialog() },
                    { label: '水平翻转图层', icon: 'flip-horizontal-2', run: () => this.flipLayer('h') },
                    { label: '垂直翻转图层', icon: 'flip-vertical-2', run: () => this.flipLayer('v') },
                ],
            },
            {
                label: '图像', items: () => [
                    { label: '调整', icon: 'sliders-horizontal', submenu: Object.entries(ADJUSTMENTS).map(([k, a]) => ({ label: a.label + (a.instant ? '' : '…'), key: a.key, run: () => this.adjust(k) })) },
                    '-',
                    { label: '图像大小…', icon: 'scaling', key: 'Ctrl+Alt+I', run: () => this.imageSize() },
                    { label: '画布大小…', icon: 'frame', key: 'Ctrl+Alt+C', run: () => this.canvasSize() },
                    { label: '图像旋转', icon: 'rotate-cw', submenu: [
                        { label: '顺时针 90°', run: () => this.rotateImage(90) },
                        { label: '逆时针 90°', run: () => this.rotateImage(-90) },
                        { label: '180°', run: () => this.rotateImage(180) },
                        '-',
                        { label: '水平翻转画布', run: () => this.rotateImage(0, 'h') },
                        { label: '垂直翻转画布', run: () => this.rotateImage(0, 'v') },
                    ] },
                    '-',
                    { label: '裁剪到选区', icon: 'crop', disabled: () => !hasSel(), run: () => this.cropToSelection() },
                    { label: '裁切透明像素', run: () => this.trimTransparent() },
                ],
            },
            {
                label: '图层', items: () => [
                    { label: '新建图层', icon: 'file-plus-2', key: 'Ctrl+Shift+N', run: () => this.newLayerCmd() },
                    { label: '复制图层', icon: 'copy', key: 'Ctrl+J', run: () => this.duplicateLayer() },
                    { label: '删除图层', icon: 'trash-2', run: () => this.deleteLayer() },
                    { label: '图层属性…', run: () => this.renameLayer() },
                    '-',
                    { label: '图层蒙版', icon: 'venetian-mask', submenu: [
                        { label: '显示全部', run: () => this.addMask(false) },
                        { label: '显示选区', disabled: () => !hasSel(), run: () => this.addMask(true) },
                        { label: '应用蒙版', disabled: () => !this.doc.activeLayer?.mask, run: () => this.applyMask() },
                        { label: '删除蒙版', disabled: () => !this.doc.activeLayer?.mask, run: () => this.deleteMask() },
                    ] },
                    { label: '栅格化文字', disabled: () => !this.doc.activeLayer?.text, run: () => this.rasterizeLayer() },
                    '-',
                    { label: '排列', icon: 'layers', submenu: [
                        { label: '置为顶层', key: 'Ctrl+Shift+]', run: () => this.layerOrder('top') },
                        { label: '前移一层', key: 'Ctrl+]', run: () => this.layerOrder('up') },
                        { label: '后移一层', key: 'Ctrl+[', run: () => this.layerOrder('down') },
                        { label: '置为底层', key: 'Ctrl+Shift+[', run: () => this.layerOrder('bottom') },
                    ] },
                    '-',
                    { label: '向下合并', key: 'Ctrl+E', run: () => this.mergeDown() },
                    { label: '合并可见图层', key: 'Ctrl+Shift+E', run: () => this.mergeVisible() },
                    { label: '拼合图像', run: () => this.flattenImage() },
                ],
            },
            {
                label: '选择', items: () => [
                    { label: '全部', key: 'Ctrl+A', run: () => this.selectAll() },
                    { label: '取消选择', key: 'Ctrl+D', disabled: () => !hasSel(), run: () => this.deselect() },
                    { label: '反选', key: 'Ctrl+Shift+I', run: () => this.invertSel() },
                    { label: '载入图层选区', run: () => this.selectLayerPixels() },
                    '-',
                    { label: '羽化…', key: 'Shift+F6', disabled: () => !hasSel(), run: () => this.modifySelection('feather') },
                    { label: '扩展…', disabled: () => !hasSel(), run: () => this.modifySelection('grow') },
                    { label: '收缩…', disabled: () => !hasSel(), run: () => this.modifySelection('shrink') },
                ],
            },
            {
                label: '滤镜', items: () => [
                    { label: '上次滤镜', key: 'Ctrl+Alt+F', disabled: () => !this.lastFilter, run: () => this.repeatFilter() },
                    '-',
                    ...Object.entries(filterGroups).map(([g, list]) => ({ label: g, submenu: list.map(([k, f]) => ({ label: f.label + (f.instant ? '' : '…'), run: () => this.filter(k) })) })),
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '放大', icon: 'zoom-in', key: 'Ctrl+=', run: () => this.zoomBy(1.25) },
                    { label: '缩小', icon: 'zoom-out', key: 'Ctrl+-', run: () => this.zoomBy(1 / 1.25) },
                    { label: '按屏幕大小缩放', icon: 'maximize', key: 'Ctrl+0', run: () => this.fitView() },
                    { label: '100%', key: 'Ctrl+1', run: () => this.setZoom(1) },
                    '-',
                    { label: '显示右侧面板', checked: () => !this.panels.classList.contains('hidden'), key: 'Tab', run: () => { this.panels.classList.toggle('hidden'); this.sizeCanvas(); this.render() } },
                ],
            },
        ]
    }

    P.layerMenu = function () {
        const l = this.doc.activeLayer
        return [
            { label: '图层属性…', run: () => this.renameLayer() },
            { label: '复制图层', icon: 'copy', run: () => this.duplicateLayer() },
            { label: '删除图层', icon: 'trash-2', danger: true, run: () => this.deleteLayer() },
            '-',
            { label: l?.mask ? '删除蒙版' : '添加蒙版', icon: 'venetian-mask', run: () => (l?.mask ? this.deleteMask() : this.addMask(!!this.doc.selection)) },
            { label: '载入选区', run: () => this.selectLayerPixels() },
            l?.text ? { label: '栅格化文字', run: () => this.rasterizeLayer() } : null,
            '-',
            { label: '向下合并', run: () => this.mergeDown() },
            { label: '合并可见图层', run: () => this.mergeVisible() },
            { label: '拼合图像', run: () => this.flattenImage() },
        ]
    }

    P.contextMenuAt = function (e) {
        if (this.xf) return contextMenu(e, [{ label: '应用变换', icon: 'check', run: () => this.commitTransform() }, { label: '取消变换', icon: 'x', run: () => this.cancelTransform() }])
        const sel = !!this.doc.selection
        contextMenu(e, [
            sel ? { label: '取消选择', run: () => this.deselect() } : { label: '全选', run: () => this.selectAll() },
            { label: '反选', run: () => this.invertSel() },
            sel ? { label: '羽化…', run: () => this.modifySelection('feather') } : null,
            '-',
            { label: '拷贝', icon: 'copy', run: () => this.copySel(false) },
            { label: '剪切', icon: 'scissors', run: () => this.copySel(true) },
            { label: '粘贴', icon: 'clipboard-paste', run: () => this.pasteClip(true) },
            { label: '通过拷贝的图层', run: () => { this.copySel(false).then(() => this.pasteClip(true)) } },
            '-',
            { label: '填充前景色', icon: 'paint-bucket', run: () => this.fillSelection(false) },
            { label: '描边…', run: () => this.strokeSelection() },
            { label: '自由变换', icon: 'scaling', run: () => this.startTransform() },
            sel ? { label: '裁剪到选区', icon: 'crop', run: () => this.cropToSelection() } : null,
            '-',
            { label: '图层', icon: 'layers', submenu: () => this.layerMenu() },
        ])
    }

    P.onKey = function (e) {
        const typing = e.target?.closest?.('input, textarea, select, [contenteditable="true"]')
        if (e.target === this.textBox) {
            if (e.key === 'Escape') { e.preventDefault(); this.textBox.textContent = ''; this.commitText(); return true }
            if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); this.commitText(); return true }
            return false
        }
        if (typing) return false
        const k = keyString(e)
        if (this.xf) {
            if (e.key === 'Enter') { this.commitTransform(); return true }
            if (e.key === 'Escape') { this.cancelTransform(); return true }
        }
        if (e.key === 'Enter' && this.poly) { this.finishPoly(); return true }
        if (e.key === 'Escape') {
            if (this.poly) { this.poly = null; this.drawOverlay(); return true }
            if (this.doc.selection) { this.deselect(); return true }
            return false
        }
        if (e.code === 'Space') { if (!this.spaceDown) { this.spaceDown = true; this.updateCursor() } return true }
        // 方向键微移图层 / 变换
        if (e.key.startsWith('Arrow')) {
            const s = e.shiftKey ? 10 : 1
            const d = { ArrowLeft: [-s, 0], ArrowRight: [s, 0], ArrowUp: [0, -s], ArrowDown: [0, s] }[e.key]
            if (this.xf) { this.xf.cx += d[0]; this.xf.cy += d[1]; this.applyTransformPreview(); return true }
            const l = this.editableLayer(true)
            if (l && this.tool === 'move') { l.x += d[0]; l.y += d[1]; this.render(); this.commit('微移', { merge: 'nudge' }); return true }
            return false
        }
        if (k === '[' || k === ']') {
            const f = k === ']' ? 1 : -1
            this.opts.size = Math.max(1, Math.min(2000, Math.round(this.opts.size * (f > 0 ? 1.2 : 1 / 1.2) + f)))
            this.saveOpts(); this.buildOptionsBar(); this.drawOverlay()
            return true
        }
        if (k === 'Shift+[' || k === 'Shift+]') { this.opts.hardness = Math.max(0, Math.min(100, this.opts.hardness + (k.endsWith(']') ? 10 : -10))); this.saveOpts(); this.buildOptionsBar(); return true }
        if (k === 'X') { this.swapColors(); return true }
        if (k === 'D') { this.resetColors(); return true }
        if (!e.ctrlKey && !e.altKey && /^[0-9]$/.test(e.key) && ['brush', 'pencil', 'eraser', 'bucket', 'gradient', 'clone'].includes(this.tool)) {
            this.opts.opacity = e.key === '0' ? 100 : Number(e.key) * 10
            this.saveOpts(); this.buildOptionsBar()
            return true
        }
        // 工具快捷键（同一按键循环切换组内工具；Shift 切换到组内第二个）
        if (!e.ctrlKey && !e.altKey && e.key.length === 1) {
            const key = e.key.toUpperCase()
            const group = TOOLS.filter(t => t !== '-' && t.key === key)
            if (group.length) {
                const cur = group.findIndex(t => t.id === this.tool)
                const next = e.shiftKey ? group[(cur + 1) % group.length] : cur >= 0 ? group[cur] : group[0]
                this.setTool(next.id)
                return true
            }
        }
        return false
    }
}
