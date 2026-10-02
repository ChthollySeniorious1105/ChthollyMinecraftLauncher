import './styles/base.css'
import './styles/app.css'
import './styles/viewers.css'
import './styles/formats.css'
import { h, btn, toast, formatDate, formatBytes, menu, togglePopover, toggle, segmented, slider } from './core/dom.js'
import { icon } from './core/icons.js'
import { initTheme, THEME_HINT } from './core/theme.js'
import * as store from './core/store.js'
import { Source, TYPES, typeOf, dialogFilters, baseName, extOf } from './core/files.js'

// 各查看器按需加载，缩短启动时间
const LOADERS = {
    ebook: () => import('./viewers/ebook.js').then(m => m.EbookViewer),
    pdf: () => import('./viewers/pdf.js').then(m => m.PdfViewer),
    docx: () => import('./viewers/docs.js').then(m => m.DocxViewer),
    doc: () => import('./viewers/text.js').then(m => m.DocViewer),
    text: () => import('./viewers/text.js').then(m => m.TextViewer),
    sheet: () => import('./viewers/sheet.js').then(m => m.SheetViewer),
    slides: () => import('./viewers/slides.js').then(m => m.SlidesViewer),
    web: () => import('./viewers/web.js').then(m => m.WebViewer),
    tex: () => import('./viewers/tex.js').then(m => m.TexViewer),
    rich: () => import('./viewers/rich.js').then(m => m.RichViewer),
    paged: () => import('./viewers/paged.js').then(m => m.PagedViewer),
    chm: () => import('./viewers/chm.js').then(m => m.ChmViewer),
    image: () => import('./viewers/image.js').then(m => m.ImageViewer),
    audio: () => import('./viewers/audio.js').then(m => m.AudioViewer),
    video: () => import('./viewers/video.js').then(m => m.VideoViewer),
    archive: () => import('./viewers/archive.js').then(m => m.ArchiveViewer),
}

const $ = s => document.querySelector(s)

class App {
    tabs = []
    active = null
    page = 'home'

    constructor() {
        initTheme()
        this.applyPrefs()
        this.buildTitlebar()
        this.buildRail()
        this.renderHome()
        this.bindGlobal()
        this.showPage('home')
        window.lite?.takeFiles().then(files => this.openPaths(files))
        window.lite?.on('app:open-files', files => this.openPaths(files))
    }

    applyPrefs() {
        const s = store.getSettings()
        document.documentElement.classList.toggle('no-anim', !s.animations)
        document.documentElement.style.setProperty('--ui-scale', s.uiScale)
        document.body.style.zoom = s.uiScale
    }

    // ---------- 标题栏与窗口控制 ----------
    buildTitlebar() {
        const icons = { minimize: 'minus', maximize: 'square', close: 'x' }
        document.querySelectorAll('.win-btn').forEach(b => {
            const act = b.dataset.win
            b.append(icon(icons[act], act === 'maximize' ? 13 : 16))
            b.addEventListener('click', () => {
                if (act === 'minimize') window.lite.win.minimize()
                else if (act === 'maximize') window.lite.win.toggleMaximize()
                else window.lite.win.close()
            })
        })
        const upd = st => {
            const b = $('[data-win="maximize"]')
            b.replaceChildren(icon(st?.maximized ? 'copy' : 'square', 13))
            b.title = st?.maximized ? '还原' : '最大化'
            document.documentElement.classList.toggle('fullscreen', !!st?.fullscreen)
            document.documentElement.classList.toggle('maximized', !!st?.maximized)
        }
        window.lite?.on('win:state', upd)
        window.lite?.win.state().then(upd)
        $('#titlebar').addEventListener('dblclick', e => {
            if (e.target.closest('button, .tab')) return
            window.lite.win.toggleMaximize()
        })
    }

    buildRail() {
        const item = (id, ic, label, fn) => h('button.rail-btn', { dataset: { id }, title: label, onclick: fn ?? (() => this.showPage(id)) },
            icon(ic, 21), h('span.rail-label', label))
        this.rail = $('#rail')
        this.rail.append(
            item('open', 'folder-open', '打开', () => this.openDialog()),
            item('home', 'house', '主页'),
            h('div.rail-sep'),
            item('convert', 'arrow-right-left', '转换'),
            h('div.rail-flex'),
            item('settings', 'settings', '设置'))
    }

    // ---------- 页面切换 ----------
    showPage(id) {
        this.page = id
        for (const p of ['home', 'settings-page', 'convert-page']) $('#' + p).hidden = true
        for (const t of this.tabs) { t.viewer.el.hidden = true }
        if (this.active && id !== 'viewer') { this.active.viewer.onHide(); this.active = null }
        if (id === 'home') { $('#home').hidden = false; this.renderHome() }
        if (id === 'settings') { $('#settings-page').hidden = false; this.renderSettings() }
        if (id === 'convert') { $('#convert-page').hidden = false; this.renderConvert() }
        this.rail.querySelectorAll('.rail-btn').forEach(b => b.classList.toggle('active', b.dataset.id === id))
        this.renderTabs()
    }

    // ---------- 标签页 ----------
    renderTabs() {
        const box = $('#tabs')
        box.replaceChildren(...this.tabs.map(t => {
            const tt = TYPES[t.viewer.source.type]
            const el = h('div.tab' + (t === this.active ? '.active' : ''), {
                title: t.title,
                onclick: () => this.activate(t),
                onauxclick: e => { if (e.button === 1) this.closeTab(t) },
            },
            h('span.tab-icon', { style: { '--c': tt?.color } }, t.badge === 'playing' ? h('span.eq', h('i'), h('i'), h('i')) : icon(t.viewer.tabIcon, 14)),
            h('span.tab-title', t.title),
            h('button.tab-close', { title: '关闭 (Ctrl W)', onclick: e => { e.stopPropagation(); this.closeTab(t) } }, icon('x', 13)))
            return el
        }))
        const a = box.querySelector('.tab.active')
        a?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
    }

    activate(tab) {
        if (this.active && this.active !== tab) this.active.viewer.onHide()
        this.active = tab
        for (const p of ['home', 'settings-page', 'convert-page']) $('#' + p).hidden = true
        for (const t of this.tabs) t.viewer.el.hidden = t !== tab
        this.page = 'viewer'
        this.rail.querySelectorAll('.rail-btn').forEach(b => b.classList.remove('active'))
        tab.viewer.onShow()
        this.renderTabs()
        document.title = `${tab.title} - LiteReader`
    }

    closeTab(tab) {
        const i = this.tabs.indexOf(tab)
        if (i < 0) return
        this.tabs.splice(i, 1)
        tab.viewer.destroy()
        if (this.active === tab) {
            this.active = null
            const next = this.tabs[i] ?? this.tabs[i - 1]
            if (next) this.activate(next)
            else { this.showPage('home'); document.title = 'LiteReader' }
        } else this.renderTabs()
    }

    setTabTitle(viewer, title) {
        const t = this.tabs.find(t => t.viewer === viewer)
        if (!t) return
        t.title = title
        this.renderTabs()
    }
    setTabBadge(viewer, badge) {
        const t = this.tabs.find(t => t.viewer === viewer)
        if (!t || t.badge === badge) return
        t.badge = badge
        this.renderTabs()
    }

    // ---------- 打开文件 ----------
    async openDialog(kind) {
        const filters = dialogFilters()
        if (kind && TYPES[kind]) filters.unshift({ name: TYPES[kind].name, extensions: TYPES[kind].exts })
        const files = await window.lite.openDialog({ filters })
        this.openPaths(files)
    }

    async openPaths(paths) {
        if (!paths?.length) return
        // 多个图片 / 音乐时只打开第一个，其余在列表中切换
        const seenTypes = new Set()
        for (const p of paths) {
            const type = typeOf(p)
            if (!type) { toast(`不支持的文件格式：${baseName(p)}`, 'warn'); continue }
            if (['image', 'audio', 'video'].includes(type)) {
                if (seenTypes.has(type)) continue
                seenTypes.add(type)
            }
            const st = await window.lite.stat(p)
            if (!st?.isFile) { toast(`文件不存在：${baseName(p)}`, 'error'); store.removeRecent(p); continue }
            await this.openSource(Source.fromPath(p, st.size))
        }
    }

    async openSource(source) {
        if (!source.type) return toast(`不支持的文件格式：${source.name}`, 'warn')
        // 已打开则直接切换
        const exist = source.path && this.tabs.find(t => t.viewer.source.path === source.path)
        if (exist) return this.activate(exist)
        // 音乐只保留一个播放器标签
        if (source.type === 'audio') {
            const player = this.tabs.find(t => t.viewer.source.type === 'audio')
            if (player && source.path) {
                const v = player.viewer
                const i = v.playlist.findIndex(s => s.path === source.path)
                this.activate(player)
                if (i >= 0) return v.load(i, true)
                this.closeTab(player)
            }
        }
        let Cls
        try {
            Cls = await LOADERS[source.type]()
        } catch (e) {
            console.error(e)
            return toast('加载查看器失败：' + e.message, 'error')
        }
        const viewer = new Cls(source, this)
        const tab = { viewer, title: viewer.title }
        this.tabs.push(tab)
        $('#viewers').append(viewer.el)
        this.activate(tab)
        if (source.path) store.addRecent({ path: source.path, name: source.name, type: source.type, size: source.size })
        try {
            await viewer.mount()
            if (tab === this.active) viewer.onShow()
        } catch (e) {
            viewer.error(e)
        }
        viewer.addOutputMenu()
    }

    // ---------- 格式转换 ----------
    async convertDialog(source) {
        const { convertDialog } = await import('./viewers/convert-ui.js')
        return convertDialog(this, source)
    }
    async renderConvert() {
        if (this.convertPage) return
        const { ConvertPage } = await import('./viewers/convert-ui.js')
        this.convertPage = new ConvertPage(this, $('#convert-page'))
        this.convertPage.render()
    }

    updateRecentProgress(source, fraction) {
        if (!source.path) return
        const list = store.getRecent()
        const r = list.find(x => x.path === source.path)
        if (r) {
            r.progress = fraction
            localStorage.setItem('lr.recent', JSON.stringify(list))
        }
    }

    toggleFullscreen() {
        const fs = document.documentElement.classList.contains('fullscreen')
        window.lite.win.setFullscreen(!fs)
    }

    // ---------- 主页 ----------
    renderHome() {
        const home = $('#home')
        const recent = store.getRecent()
        const hour = new Date().getHours()
        const greet = hour < 6 ? '夜深了' : hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好'
        const cats = [
            ['ebook', 'EPUB · MOBI · AZW3'],
            ['pdf', 'PDF 文档'],
            ['docx', 'DOCX · DOC'],
            ['sheet', 'XLSX · XLS · CSV'],
            ['slides', 'PPTX · PPT · ODP'],
            ['rich', 'RTF · ODT'],
            ['paged', 'OFD · XPS · DjVu'],
            ['chm', 'CHM 帮助文档'],
            ['web', 'HTML · XHTML · MHT'],
            ['tex', 'TEX · LaTeX 公式'],
            ['audio', 'MP3 · OGG · WAV · MIDI'],
            ['image', 'PNG · JPG · BMP · GIF'],
            ['archive', 'ZIP · 7Z · RAR'],
            ['video', 'MP4 · WEBM · MKV'],
        ]
        const hero = h('div.hero',
            h('div.hero-art', h('i.o1'), h('i.o2'), h('i.o3')),
            h('div.hero-text',
                h('div.hero-greet', greet + '，欢迎使用'),
                h('h1.hero-title', 'LiteReader'),
                h('p.hero-sub', '一个应用，读遍电子书与文档，听音乐、看图片与视频、浏览压缩包。'),
                h('div.hero-actions',
                    h('button.btn.primary.lg', { onclick: () => this.openDialog() }, icon('folder-open', 18), '打开文件'),
                    h('button.btn.lg', { onclick: () => this.showPage('convert') }, icon('arrow-right-left', 18), '格式转换')),
                h('div.hero-hint', icon('mouse-pointer-2', 14), '也可以直接把文件拖到窗口任意位置')))

        const grid = h('div.cat-grid', cats.map(([k, desc]) => {
            const t = TYPES[k]
            return h('button.cat-card', { style: { '--c': t.color }, onclick: () => this.openDialog(k) },
                h('span.cat-icon', icon(t.icon, 22)),
                h('span.cat-text', h('span.cat-name', t.name), h('span.cat-desc', desc)))
        }))

        const recentBox = h('div.recent')
        if (!recent.length) {
            recentBox.append(h('div.recent-empty', icon('library', 34), h('div', '最近打开的文件会显示在这里')))
        } else {
            recentBox.append(...recent.slice(0, 24).map(r => {
                const t = TYPES[r.type] ?? {}
                const card = h('div.recent-item', { title: r.path, onclick: () => this.openPaths([r.path]) },
                    h('span.recent-icon', { style: { '--c': t.color } }, icon(t.icon ?? 'file', 20),
                        h('span.recent-ext', extOf(r.name).toUpperCase())),
                    h('div.recent-text',
                        h('div.recent-name', r.name),
                        h('div.recent-sub', `${t.name ?? ''} · ${formatBytes(r.size)} · ${formatDate(r.time)}`),
                        r.progress > 0.005 ? h('div.recent-bar', h('i', { style: { width: Math.min(100, r.progress * 100) + '%' } })) : null),
                    btn('ellipsis', '更多', e => {
                        e.stopPropagation()
                        togglePopover(e.currentTarget, () => menu([
                            { label: '打开', icon: 'folder-open', onclick: () => this.openPaths([r.path]) },
                            { label: '在文件夹中显示', icon: 'folder', onclick: () => window.lite.showInFolder(r.path) },
                            { label: '转换格式…', icon: 'arrow-right-left', onclick: () => this.convertDialog(Source.fromPath(r.path, r.size)) },
                            '-',
                            { label: '从列表中移除', icon: 'trash-2', danger: true, onclick: () => { store.removeRecent(r.path); this.renderHome() } },
                        ]))
                    }, { class: 'recent-more', size: 16 }))
                return card
            }))
        }

        home.replaceChildren(h('div.home-inner',
            hero,
            h('div.section-head', h('h2', '支持的格式'), h('span.section-sub', '点击分类快速打开对应文件')),
            grid,
            h('div.section-head', h('h2', '最近打开'),
                recent.length ? h('button.link-btn', { onclick: () => { store.clearRecent(); this.renderHome() } }, icon('trash-2', 14), '清空') : null),
            recentBox,
            h('div.home-foot', '快捷键：Ctrl+O 打开 · Ctrl+P 打印 · Ctrl+Shift+E 导出 PDF · Ctrl+W 关闭标签 · Ctrl+Tab 切换标签 · F11 全屏')))
    }

    // ---------- 设置页 ----------
    renderSettings() {
        const s = store.getSettings()
        const page = $('#settings-page')
        const row = (title, desc, control) => h('div.set-row', h('div.set-text', h('div.set-title', title), desc ? h('div.set-desc', desc) : null), control)
        const info = h('div.set-desc', '')
        window.lite?.appInfo().then(i => { info.textContent = `版本 ${i.version} · Electron ${i.electron} · Chromium ${i.chrome}` })
        page.replaceChildren(h('div.home-inner.narrow',
            h('div.page-head', h('div', h('h1.page-title', '设置'), h('p.page-sub', '个性化你的阅读与播放体验'))),
            h('div.set-card',
                h('div.set-card-title', icon('sparkles', 16), '界面'),
                row('主题', THEME_HINT + '；阅读区纸张颜色可在阅读设置中单独选择', null),
                row('动画效果', '界面过渡与翻页动画', toggle(s.animations, v => { store.set('animations', v); this.applyPrefs() })),
                row('界面缩放', '调整整体界面大小', segmented([[0.9, '90%'], [1, '100%'], [1.1, '110%'], [1.25, '125%']], s.uiScale, v => { store.set('uiScale', v); this.applyPrefs() }).el)),
            h('div.set-card',
                h('div.set-card-title', icon('book-open', 16), '阅读'),
                row('记住阅读进度', '重新打开时自动跳转到上次位置', toggle(s.rememberProgress, v => store.set('rememberProgress', v))),
                row('默认翻页方式', '电子书的分页或滚动模式', segmented([['paginated', '分页'], ['scrolled', '滚动']], s.readerFlow, v => store.set('readerFlow', v)).el),
                row('默认字号', null, slider({ min: 12, max: 36, value: s.readerFontSize, format: v => v + 'px', oninput: v => store.set('readerFontSize', v) }).el),
                row('PDF 夜间反色', '在深色主题下降低 PDF 亮度', toggle(s.pdfInvert, v => store.set('pdfInvert', v)))),
            h('div.set-card',
                h('div.set-card-title', icon('music', 16), '媒体'),
                row('音乐可视化', null, segmented([['bars', '柱状'], ['mirror', '镜像'], ['wave', '波形'], ['circle', '环形'], ['particles', '粒子'], ['off', '关闭']], s.visualizer, v => store.set('visualizer', v)).el),
                row('默认音量', null, slider({ min: 0, max: 100, value: Math.round(s.volume * 100), format: v => v + '%', oninput: v => store.set('volume', v / 100) }).el),
                row('幻灯片间隔', '图片自动播放的切换时间', slider({ min: 1, max: 15, value: s.slideshowInterval, format: v => v + ' 秒', oninput: v => store.set('slideshowInterval', v) }).el)),
            h('div.set-card',
                h('div.set-card-title', icon('info', 16), '关于'),
                row('LiteReader', info, h('img.about-logo', { src: './logo.svg', alt: '' })),
                row('恢复默认设置', '所有偏好将被重置（主题由 CML 启动器决定）', h('button.btn.danger', {
                    onclick: () => { store.resetSettings(); this.applyPrefs(); this.renderSettings(); toast('已恢复默认设置', 'success') },
                }, '恢复默认')),
                row('清除阅读记录', '清空最近打开与所有阅读进度', h('button.btn', {
                    onclick: () => { store.clearRecent(); localStorage.removeItem('lr.progress'); toast('已清除', 'success') },
                }, '清除')))))
    }

    // ---------- 全局事件 ----------
    bindGlobal() {
        document.addEventListener('keydown', e => this.handleKey(e))

        let depth = 0
        const mask = $('#drop-mask')
        mask.querySelector('.drop-icon').append(icon('file-down', 44))
        const hasFiles = e => [...(e.dataTransfer?.types ?? [])].includes('Files')
        document.addEventListener('dragenter', e => { if (!hasFiles(e)) return; depth++; mask.hidden = false; requestAnimationFrame(() => mask.classList.add('show')) })
        document.addEventListener('dragleave', e => { if (!hasFiles(e)) return; if (--depth <= 0) { depth = 0; mask.classList.remove('show'); mask.hidden = true } })
        document.addEventListener('dragover', e => { if (hasFiles(e)) e.preventDefault() })
        document.addEventListener('drop', e => {
            e.preventDefault()
            depth = 0
            mask.classList.remove('show')
            mask.hidden = true
            const paths = [...e.dataTransfer.files].map(f => window.lite.pathForFile(f)).filter(Boolean)
            if (this.page === 'convert' && this.convertPage) return this.convertPage.add(paths)
            this.openPaths(paths)
        })
        window.addEventListener('contextmenu', e => {
            if (!e.target.closest('input, textarea, [contenteditable], .textLayer, .flow-article, .docx-host')) e.preventDefault()
        })
    }

    handleKey(e) {
        const target = e.target
        const typing = target?.closest?.('input:not([type=range]), textarea, [contenteditable="true"]')
        const k = e.key
        if (e.ctrlKey && k.toLowerCase() === 'o') { e.preventDefault(); this.openDialog(); return }
        if (e.ctrlKey && k.toLowerCase() === 'w') { e.preventDefault(); if (this.active) this.closeTab(this.active); return }
        if (e.ctrlKey && k === 'Tab') {
            e.preventDefault()
            if (!this.tabs.length) return
            const i = this.tabs.indexOf(this.active)
            this.activate(this.tabs[((i < 0 ? 0 : i + (e.shiftKey ? -1 : 1)) + this.tabs.length) % this.tabs.length])
            return
        }
        if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'p' && this.page === 'viewer' && this.active?.viewer.canPrint) { e.preventDefault(); this.active.viewer.print('print'); return }
        if (e.ctrlKey && e.shiftKey && k.toLowerCase() === 'e' && this.page === 'viewer' && this.active?.viewer.canPrint) { e.preventDefault(); this.active.viewer.print('pdf'); return }
        if (k === 'F11') { e.preventDefault(); this.toggleFullscreen(); return }
        if (typing) return
        if (this.active && this.page === 'viewer') {
            if (this.active.viewer.onKey(e)) { e.preventDefault(); return }
        }
        if (k === 'Escape' && document.documentElement.classList.contains('fullscreen')) { this.toggleFullscreen(); return }
    }
}

window.app = new App()

// 自动化测试入口：转换文件并写入指定目录（scripts/test-convert.mjs 使用）
window.__convertTest = async (path, target, outDir) => {
    const { convert, targetsFor } = await import('./core/convert.js')
    const st = await window.lite.stat(path)
    const source = Source.fromPath(path, st.size)
    const info = targetsFor(source).find(t => t.id === target)
    if (!info) throw new Error('不支持的目标：' + target)
    const files = await convert(source, { target, password: '' })
    const written = []
    for (const f of files) written.push(await window.lite.writeFile(outDir + '\\' + source.ext + '_' + f.name, f.data))
    return { files: written, lossless: info.lossless, losses: info.losses }
}
