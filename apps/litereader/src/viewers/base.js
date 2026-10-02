import { h, fill, btn, togglePopover, menu, toast } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { TYPES } from '../core/files.js'

// 所有查看器的基类：提供统一的工具栏 / 侧栏 / 内容区骨架
export class Viewer {
    constructor(source, app) {
        this.source = source
        this.app = app
        this.disposers = []
        this.el = h('div.viewer.viewer-' + (source.type ?? 'unknown'))
        this.toolbar = h('div.v-toolbar')
        this.left = h('div.v-tools.left')
        this.center = h('div.v-tools.center')
        this.right = h('div.v-tools.right')
        this.toolbar.append(this.left, this.center, this.right)
        this.sidebar = h('aside.v-sidebar')
        this.content = h('div.v-content')
        this.main = h('div.v-main', this.sidebar, this.content)
        this.el.append(this.toolbar, this.main)
        this.sidebarOpen = false
    }

    get title() { return this.source.name }
    get tabIcon() { return TYPES[this.source.type]?.icon ?? 'file' }

    // 子类实现
    async mount() {}
    onKey() { return false }
    onShow() {}
    onHide() {}

    // 事件注册，销毁时自动解绑
    listen(target, type, fn, opts) {
        target.addEventListener(type, fn, opts)
        this.disposers.push(() => target.removeEventListener(type, fn, opts))
    }
    onDispose(fn) { this.disposers.push(fn) }

    addTitle() {
        const t = TYPES[this.source.type]
        const info = h('div.v-title',
            h('span.v-title-icon', { style: { '--c': t?.color ?? 'var(--accent)' } }, icon(t?.icon ?? 'file', 16)),
            h('div.v-title-text',
                h('div.v-title-name', { title: this.source.name }, this.source.name),
                this.subtitle = h('div.v-title-sub', this.source.parent ? `来自 ${this.source.parent}` : t?.name ?? '')))
        this.left.append(info)
    }
    setSubtitle(text) { if (this.subtitle) this.subtitle.textContent = text }

    tool(iconName, title, onclick, where = this.right, extra) {
        const b = btn(iconName, title, onclick, extra)
        where.append(b)
        return b
    }
    sep(where = this.right) { where.append(h('span.v-sep')) }

    // ---------- 打印 / 导出 / 转换 ----------
    // 子类可覆盖 printable()：返回 { html, kind: 'doc' | 'pages', pages?, cssPage? }；默认按格式转换引擎生成
    get canPrint() { return !['audio', 'video', 'archive'].includes(this.source.type) }

    // 在工具栏最右侧加入「打印 / 导出 / 转换」菜单（由 App 在挂载后调用）
    addOutputMenu() {
        if (this.outputBtn) return
        this.outputBtn = btn('file-output', '打印 / 导出 / 转换', e => togglePopover(e.currentTarget, () => menu([
            this.canPrint ? { label: '打印…', icon: 'printer', hint: 'Ctrl P', onclick: () => this.print('print') } : null,
            this.canPrint ? { label: '导出为 PDF…', icon: 'file-down', hint: 'Ctrl ⇧ E', onclick: () => this.print('pdf') } : null,
            this.canPrint ? '-' : null,
            { label: '转换为其他格式…', icon: 'arrow-right-left', onclick: () => this.app.convertDialog(this.source) },
        ].filter(Boolean))))
        this.right.append(this.outputBtn)
    }

    async printable() {
        const { convertForPrint } = await import('../core/print-source.js')
        return convertForPrint(this)
    }

    async print(mode) {
        const { printDialog, runPrint, toastProgress, parseRange } = await import('../core/print.js')
        let data
        const t = toastProgress('正在准备打印内容…')
        try {
            data = await this.printable()
        } catch (e) {
            t.done()
            console.error(e)
            return toast('无法打印此文件：' + (e.message ?? e), 'error', 5000)
        }
        t.done()
        const opts = await printDialog({ title: mode === 'pdf' ? '导出为 PDF' : '打印', kind: data.kind, pages: data.pageCount ?? 0, defaultMode: mode })
        if (!opts) return
        let html = data.html
        if (data.build && opts.range) {
            const list = parseRange(opts.range, data.pageCount)
            if (!list.length) return toast('页码范围无效', 'warn')
            const t2 = toastProgress('正在准备页面…')
            try { html = await data.build(list) } finally { t2.done() }
        } else if (data.build) {
            const t2 = toastProgress('正在准备页面…')
            try { html = await data.build() } finally { t2.done() }
        }
        return runPrint({ html, opts, source: this.source, cssPage: data.kind === 'pages' })
    }

    // 内容无法完全还原时，在工具栏显示提示按钮，点击列出具体原因
    setCaveats(items) {
        const list = [...new Set(items)].filter(Boolean)
        if (!this.caveatBtn) {
            this.caveatBtn = btn('triangle-alert', '', e => togglePopover(e.currentTarget, () => h('div.panel',
                h('div.panel-title', '显示说明'),
                h('div.set-desc', '以下内容无法按原样还原，已做近似处理：'),
                h('ul.caveat-list', this.caveats.map(t => h('li', t))))), { class: 'caveat-btn' })
            this.right.prepend(this.caveatBtn)
        }
        this.caveats = list
        this.caveatBtn.hidden = !list.length
        this.caveatBtn.title = `近似显示（${list.length} 项），点击查看`
    }

    toggleSidebar(force) {
        this.sidebarOpen = force ?? !this.sidebarOpen
        this.el.classList.toggle('sidebar-open', this.sidebarOpen)
    }

    loading(text = '正在加载…') {
        const el = h('div.v-loading', h('div.spinner'), h('div.v-loading-text', text))
        this.content.append(el)
        return {
            el,
            set: t => { el.querySelector('.v-loading-text').textContent = t },
            done: () => el.remove(),
        }
    }

    error(err) {
        console.error(err)
        fill(this.content, h('div.v-error',
            h('div.v-error-icon', icon('file-x', 44)),
            h('div.v-error-title', '无法打开此文件'),
            h('div.v-error-msg', String(err?.message ?? err)),
            this.source.path ? h('button.btn', { onclick: () => window.lite.showInFolder(this.source.path) },
                icon('folder-open', 16), '在文件夹中显示') : null))
    }

    destroy() {
        for (const d of this.disposers.splice(0)) {
            try { d() } catch (e) { console.warn(e) }
        }
        this.el.remove()
    }
}

// 通用的侧栏标签页
export function sidebarTabs(tabs) {
    const head = h('div.sb-tabs')
    const body = h('div.sb-body')
    let active = null
    const select = id => {
        active = id
        for (const b of head.children) b.classList.toggle('active', b.dataset.id === id)
        for (const t of tabs) t.panel.hidden = t.id !== id
        tabs.find(t => t.id === id)?.onshow?.()
    }
    for (const t of tabs) {
        head.append(h('button', { dataset: { id: t.id }, onclick: () => select(t.id), title: t.label }, icon(t.icon, 15), h('span', t.label)))
        t.panel.classList.add('sb-panel')
        body.append(t.panel)
    }
    select(tabs[0].id)
    return { el: h('div.sb', head, body), select, get active() { return active } }
}
