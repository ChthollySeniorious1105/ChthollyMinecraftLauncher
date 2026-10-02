import { h, fill, btn, toast, unsavedDialog } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { KINDS, extOf, baseName, stemOf, dirName, toBytes } from '../core/files.js'
import { History } from '../core/history.js'
import { openMenu, closeMenu, menuAnchor, keyString, collectKeys, dropdown } from '../core/menu.js'
import * as store from '../core/store.js'
import { fontsReady, pickAndImportFonts } from '../core/fonts.js'

// 所有编辑器的基类
// 布局：菜单栏 / 工具栏 / [左工具条 | 画布区 | 右侧面板] / 状态栏
// 子类需实现：
//   static kind
//   menus()                 -> [{ label, items }]
//   formats()               -> [{ ext, name, write: async () => Uint8Array|string, lossy? }]  保存 / 另存为 / 导出
//   async load(bytes, ext)  打开文件
//   async create(opts)      新建文档
//   snapshot() / restore(s) 撤销快照
export class Editor {
    static kind = 'doc'

    constructor(file, app) {
        this.app = app
        this.kind = this.constructor.kind
        this.path = file?.path ?? null
        this.name = file?.name ?? (file?.path ? baseName(file.path) : `未命名${KINDS[this.kind].name}`)
        this.disposers = []
        this.savedIndex = 0
        this.history = new History({
            limit: store.get('historyLimit'),
            onChange: () => { this.updateDirty(); this.onHistory?.() },
        })

        this.el = h('div.viewer.editor.editor-' + this.kind, { tabIndex: -1 })
        this.menubar = h('div.e-menubar')
        this.toolbar = h('div.e-toolbar')
        this.leftbar = h('div.e-leftbar')
        this.stage = h('div.e-stage')
        this.panels = h('aside.e-panels')
        this.status = h('div.e-status')
        this.el.append(this.menubar, this.toolbar, h('div.e-main', this.leftbar, this.stage, this.panels), this.status)
    }

    get title() { return this.name + (this.dirty ? ' •' : '') }
    get tabIcon() { return KINDS[this.kind].icon }
    get dirty() { return this.history.index !== this.savedIndex }

    // ---------- 生命周期 ----------
    async mount(file) {
        this.buildMenubar()
        // 先加载导入的字体，避免画布类编辑器首次绘制时使用回退字体
        await fontsReady()
        const ext = this.path ? extOf(this.path) : null
        if (file?.bytes) await this.load(file.bytes, extOf(file.name ?? this.name))
        else if (this.path) await this.load(await window.lite.readFile(this.path), ext)
        else await this.create(file?.options ?? {})
        this.history.reset(this.snapshot(), file?.path || file?.bytes ? '打开' : '新建')
        this.savedIndex = 0
        // 只有无损格式才可以直接保存到原文件
        if (this.path && !KINDS[this.kind].native.includes(ext)) this.saveTarget = null
        else this.saveTarget = this.path
        this.updateDirty()
        this.startAutosave()
    }

    onShow() { this.el.focus({ preventScroll: true }) }
    onHide() { closeMenu() }

    listen(target, type, fn, opts) {
        target.addEventListener(type, fn, opts)
        this.disposers.push(() => target.removeEventListener(type, fn, opts))
    }
    onDispose(fn) { this.disposers.push(fn) }

    destroy() {
        clearInterval(this.autosaveTimer)
        for (const d of this.disposers.splice(0)) {
            try { d() } catch (e) { console.warn(e) }
        }
        this.el.remove()
    }

    error(err) {
        console.error(err)
        fill(this.stage, h('div.v-error',
            h('div.v-error-icon', icon('file-x', 44)),
            h('div.v-error-title', '无法打开此文件'),
            h('div.v-error-msg', String(err?.message ?? err)),
            this.path ? h('button.btn', { onclick: () => window.lite.showInFolder(this.path) }, icon('folder-open', 16), '在文件夹中显示') : null))
    }

    // ---------- 撤销 ----------
    // 记录一次修改：label 显示在历史面板；merge 为相同 key 时合并到上一步
    commit(label, { merge } = {}) {
        const snap = this.snapshot()
        if (merge && this.lastMerge === merge && this.history.index === this.history.stack.length - 1 && this.history.index > this.savedIndex) {
            this.history.replace(snap, label)
        } else this.history.push(label, snap)
        this.lastMerge = merge ?? null
    }
    undo() {
        const s = this.history.undo()
        this.lastMerge = null
        if (s != null) this.restore(s)
        else toast('没有可以撤销的操作')
    }
    redo() {
        const s = this.history.redo()
        this.lastMerge = null
        if (s != null) this.restore(s)
    }
    gotoHistory(i) {
        const s = this.history.goto(i)
        this.lastMerge = null
        if (s != null) this.restore(s)
    }

    updateDirty() {
        const d = this.dirty
        if (d !== this._lastDirty) {
            this._lastDirty = d
            this.app.setTabTitle(this, this.title)
        }
    }

    // ---------- 保存 ----------
    // 保存到原文件（仅原生格式），否则走另存为
    async save() {
        if (!this.saveTarget) return this.saveAs()
        return this.writeTo(this.saveTarget)
    }

    async saveAs(preferExt) {
        const fmts = this.formats()
        const cur = this.saveTarget ? extOf(this.saveTarget) : null
        const first = fmts.find(f => f.ext === preferExt) ?? fmts.find(f => f.ext === cur) ?? fmts[0]
        const ordered = [first, ...fmts.filter(f => f !== first)]
        const base = this.path ? dirName(this.path) + '\\' + stemOf(this.name) : stemOf(this.name)
        const target = await window.lite.saveDialog({
            title: '另存为',
            defaultPath: `${base}.${first.ext}`,
            filters: ordered.map(f => ({ name: f.name, extensions: [f.ext] })),
        })
        if (!target) return false
        return this.writeTo(target)
    }

    // 导出为某一格式（不改变当前文档的保存位置）
    async exportAs(ext) {
        const f = this.formats().find(x => x.ext === ext) ?? this.exports?.().find(x => x.ext === ext)
        if (!f) return
        const base = this.path ? dirName(this.path) + '\\' + stemOf(this.name) : stemOf(this.name)
        const target = await window.lite.saveDialog({ title: '导出为 ' + f.name, defaultPath: `${base}.${f.ext}`, filters: [{ name: f.name, extensions: [f.ext] }] })
        if (!target) return false
        try {
            const data = await f.write(target)
            await window.lite.writeFile(target, toBytes(data))
            toast(`已导出：${baseName(target)}`, 'success')
            return true
        } catch (e) {
            console.error(e)
            toast('导出失败：' + e.message, 'error', 5000)
            return false
        }
    }

    async writeTo(target) {
        const ext = extOf(target)
        const f = [...this.formats(), ...(this.exports?.() ?? [])].find(x => x.ext === ext)
        if (!f) { toast(`不支持保存为 .${ext}`, 'error'); return false }
        try {
            const data = await f.write(target)
            await window.lite.writeFile(target, toBytes(data))
        } catch (e) {
            console.error(e)
            toast('保存失败：' + e.message, 'error', 5000)
            return false
        }
        const nativeFmt = KINDS[this.kind].native.includes(ext)
        if (nativeFmt) {
            this.path = target
            this.saveTarget = target
            this.name = baseName(target)
            this.savedIndex = this.history.index
            this._lastDirty = null
            this.updateDirty()
            store.addRecent({ path: target, name: this.name, kind: this.kind })
        }
        toast(nativeFmt ? `已保存：${baseName(target)}` : `已导出：${baseName(target)}（${f.name}）`, 'success')
        if (!nativeFmt && f.lossy) toast(f.lossy, 'warn', 4200)
        return true
    }

    startAutosave() {
        clearInterval(this.autosaveTimer)
        const s = store.getSettings()
        if (!s.autosave) return
        this.autosaveTimer = setInterval(() => {
            if (this.dirty && this.saveTarget && !this.busy) this.writeTo(this.saveTarget)
        }, Math.max(15, s.autosaveInterval) * 1000)
    }

    // 关闭前确认，返回 true 表示可以关闭
    async confirmClose() {
        if (!this.dirty) return true
        this.app.activate(this.app.tabs.find(t => t.editor === this))
        const r = await unsavedDialog(this.name)
        if (r === 'save') return this.save()
        return r === 'discard'
    }

    // ---------- 菜单栏 ----------
    // 通用的“文件”菜单，子类可在 fileItems() 中追加
    fileMenu() {
        const fmts = this.formats()
        const exps = this.exports?.() ?? []
        return {
            label: '文件',
            items: () => [
                { label: '新建', icon: 'file-plus', submenu: () => this.app.newMenuItems() },
                { label: '打开…', icon: 'folder-open', key: 'Ctrl+O', run: () => this.app.openDialog() },
                '-',
                { label: '保存', icon: 'save', key: 'Ctrl+S', run: () => this.save() },
                { label: '另存为…', icon: 'save-all', key: 'Ctrl+Shift+S', run: () => this.saveAs() },
                exps.length || fmts.length > 1 ? {
                    label: '导出为', icon: 'file-down',
                    submenu: [...fmts, ...exps].map(f => ({ label: `${f.name} (.${f.ext})`, run: () => this.exportAs(f.ext) })),
                } : null,
                ...(this.fileItems?.() ?? []),
                { label: '导入字体…', icon: 'type', run: () => pickAndImportFonts() },
                '-',
                this.path ? { label: '在文件夹中显示', icon: 'folder', run: () => window.lite.showInFolder(this.path) } : null,
                { label: '关闭', icon: 'x', key: 'Ctrl+W', run: () => this.app.closeTab(this.app.tabs.find(t => t.editor === this)) },
            ],
        }
    }

    // 通用“编辑”菜单项（撤销 / 重做）
    undoItems() {
        return [
            { label: () => this.history.canUndo ? `撤销 ${this.history.current?.label ?? ''}` : '撤销', icon: 'undo-2', key: 'Ctrl+Z', disabled: () => !this.history.canUndo, run: () => this.undo() },
            { label: '重做', icon: 'redo-2', key: 'Ctrl+Y', altKey: 'Ctrl+Shift+Z', disabled: () => !this.history.canRedo, run: () => this.redo() },
        ]
    }

    buildMenubar() {
        const menus = [this.fileMenu(), ...this.menus()]
        this.keymap = collectKeys(menus)
        const btns = menus.map(m => {
            const b = h('button.e-menu', m.label)
            const open = () => {
                b.classList.add('open')
                openMenu(m.items, { anchor: b, onClose: () => b.classList.remove('open') })
            }
            b.addEventListener('click', () => (menuAnchor() === b ? closeMenu() : open()))
            // 菜单打开时，鼠标滑过其他菜单标题即切换
            b.addEventListener('mouseenter', () => {
                const a = menuAnchor()
                if (a && a !== b && a.classList.contains('e-menu')) open()
            })
            return b
        })
        fill(this.menubar, ...btns, h('div.e-menubar-flex'), this.menubarExtra?.() ?? null)
    }

    // ---------- 工具栏构造 ----------
    tbGroup(...children) {
        const g = h('div.tb-group', children)
        this.toolbar.append(g)
        return g
    }
    tb(iconName, title, onclick, extra) { return btn(iconName, title, onclick, { size: 17, ...extra }) }
    dd(content, items, opts) { return dropdown(typeof content === 'string' ? h('span', content) : content, items, opts) }

    // 状态栏片段
    statusItems(...items) { fill(this.status, ...items) }

    // ---------- 键盘 ----------
    // 返回 true 表示已处理
    handleKey(e) {
        if (this.onKey?.(e)) return true
        const typing = e.target?.closest?.('input:not([type=range]):not([type=checkbox]):not([type=color]), textarea, select, [contenteditable="true"], [contenteditable=""]')
        const k = keyString(e)
        if (!k) return false
        const it = this.keymap?.get(k)
        if (!it) return false
        // 输入状态下只响应带 Ctrl 的命令；撤销 / 剪贴板 / 全选等交给输入框本身，
        // 除非编辑器声明该输入区域由自己管理（如文档编辑区）
        if (typing && !this.ownsTyping?.(e)) {
            if (!k.startsWith('Ctrl+') || NATIVE_TEXT_KEYS.test(k)) return false
        }
        if (typeof it.disabled === 'function' ? it.disabled() : it.disabled) return true
        it.run?.()
        return true
    }
}

const NATIVE_TEXT_KEYS = /^Ctrl\+(Z|Y|Shift\+Z|A|C|V|X|B|I|U|Backspace|Delete|ArrowLeft|ArrowRight)$/

// 右侧可折叠面板
export function panel(title, body, { icon: ic, actions = [], collapsed = false, cls = '' } = {}) {
    const head = h('div.ep-head', ic ? icon(ic, 14) : null, h('span.ep-title', title), h('div.ep-actions', actions))
    const el = h('section.ep' + cls + (collapsed ? '.collapsed' : ''), head, h('div.ep-body', body))
    head.addEventListener('click', e => { if (!e.target.closest('.ep-actions')) el.classList.toggle('collapsed') })
    return el
}

// 左侧工具按钮组：tools = [{ id, icon, label, key }]
export function toolRail(tools, current, onSelect) {
    const el = h('div.tool-rail')
    const btns = new Map()
    for (const t of tools) {
        if (t === '-') { el.append(h('div.tool-sep')); continue }
        const b = h('button.tool-btn', { title: t.key ? `${t.label} (${t.key})` : t.label, dataset: { id: t.id }, onclick: () => onSelect(t.id) }, icon(t.icon, 19))
        btns.set(t.id, b)
        el.append(b)
    }
    const set = id => { for (const [k, b] of btns) b.classList.toggle('active', k === id) }
    set(current)
    return { el, set }
}
