import 'katex/dist/katex.min.css'
import './styles/base.css'
import './styles/app.css'
import './styles/editor.css'
import './styles/image.css'
import './styles/geo.css'
import './styles/mathkb.css'
import './styles/doc.css'
import './styles/sheet.css'
import './styles/slides.css'
import './styles/video.css'
import './styles/midi.css'
import './styles/capture.css'
import { h, btn, toast, formatDate, formatTime, formatBytes, menu, togglePopover, toggle, segmented, slider, dialog, confirmDialog } from './core/dom.js'
import { icon } from './core/icons.js'
import { initTheme, THEME_HINT } from './core/theme.js'
import * as store from './core/store.js'
import { KINDS, kindOf, dialogFilters, baseName, extOf } from './core/files.js'
import { closeMenu, menuOpen, openMenu } from './core/menu.js'
import { openPalette, flattenMenus } from './core/palette.js'
import { initFonts, userFonts, userFontDir, onFontsChange, importFonts, pickAndImportFonts, removeFont, isFontFile } from './core/fonts.js'

// 各编辑器按需加载，缩短启动时间
const LOADERS = {
    image: () => import('./editors/image/index.js').then(m => m.ImageEditor),
    geo: () => import('./editors/geo/index.js').then(m => m.GeoEditor),
    doc: () => import('./editors/doc/index.js').then(m => m.DocEditor),
    sheet: () => import('./editors/sheet/index.js').then(m => m.SheetEditor),
    slides: () => import('./editors/slides/index.js').then(m => m.SlidesEditor),
    video: () => import('./editors/video/index.js').then(m => m.VideoEditor),
    midi: () => import('./editors/midi/index.js').then(m => m.MidiEditor),
}
const capture = () => import('./tools/capture.js')

// 新建模板
const TEMPLATES = {
    image: [
        { id: 'blank', name: '空白画布', desc: '1920 × 1080 · 白色', options: { width: 1920, height: 1080, bg: '#ffffff' } },
        { id: 'transparent', name: '透明画布', desc: '1024 × 1024 · 透明', options: { width: 1024, height: 1024, bg: null } },
        { id: 'a4', name: 'A4 海报', desc: '2480 × 3508 · 300 DPI', options: { width: 2480, height: 3508, bg: '#ffffff' } },
        { id: 'custom', name: '自定义尺寸…', desc: '宽度、高度、背景', options: { ask: true } },
    ],
    geo: [
        { id: 'blank', name: '空白画板', desc: '坐标网格', options: {} },
        { id: 'triangle', name: '三角形的五心', desc: '外心 · 内心 · 重心 · 垂心', options: { sample: 'triangle' } },
        { id: 'function', name: '函数图像', desc: 'y = sin x · 抛物线', options: { sample: 'function' } },
        { id: 'conic', name: '圆锥曲线', desc: '椭圆 · 双曲线 · 抛物线', options: { sample: 'conic' } },
    ],
    doc: [
        { id: 'blank', name: '空白文档', desc: 'A4 · 宋体', options: {} },
        { id: 'report', name: '报告', desc: '标题 · 目录 · 章节', options: { sample: 'report' } },
        { id: 'letter', name: '信函', desc: '称呼 · 正文 · 落款', options: { sample: 'letter' } },
    ],
    sheet: [
        { id: 'blank', name: '空白表格', desc: '100 行 × 26 列', options: {} },
        { id: 'budget', name: '家庭预算', desc: '公式 · 图表 · 条件格式', options: { sample: 'budget' } },
        { id: 'grades', name: '成绩统计', desc: '排序 · 平均分 · 排名', options: { sample: 'grades' } },
    ],
    slides: [
        { id: 'blank', name: '空白演示', desc: '16:9 · 简洁白', options: {} },
        { id: 'pitch', name: '项目介绍', desc: '5 页 · 渐变主题', options: { sample: 'pitch' } },
        { id: 'dark', name: '暗色主题', desc: '16:9 · 深色背景', options: { theme: 'dark' } },
    ],
    video: [
        { id: 'blank', name: '空白项目', desc: '1920 × 1080 · 30 fps', options: {} },
        { id: 'vertical', name: '竖屏短视频', desc: '1080 × 1920 · 30 fps', options: { preset: 'vertical' } },
        { id: 'record', name: '录制屏幕…', desc: '录屏后直接剪辑', options: { record: true } },
    ],
    midi: [
        { id: 'blank', name: '空白乐曲', desc: '钢琴 · 120 BPM · 4/4', options: {} },
        { id: 'demo', name: '示例乐曲', desc: '旋律 · 和弦 · 贝斯 · 鼓', options: { sample: 'demo' } },
        { id: 'band', name: '乐队编制', desc: '多轨模板', options: { sample: 'band' } },
    ],
}

const $ = s => document.querySelector(s)

class App {
    tabs = []
    active = null
    page = 'home'
    untitled = {}
    closed = []     // 最近关闭的标签（路径），Ctrl+Shift+T 重新打开

    constructor() {
        initTheme()
        this.applyPrefs()
        initFonts()
        onFontsChange(() => { if (this.page === 'settings') this.renderFontList() })
        this.buildTitlebar()
        this.buildRail()
        this.renderHome()
        this.bindGlobal()
        this.showPage('home')
        window.lite?.takeFiles().then(files => this.openPaths(files))
        window.lite?.on('app:open-files', files => this.openPaths(files))
        window.lite?.on('app:before-close', () => this.quit())
        window.lite?.on('capture:hotkey', kind => {
            if (kind === 'record') this.toggleRecord()
            else if (kind === 'record-pause') this.recorder?.pause()
            else if (!this.recorder || this.recorder.state === 'idle') this.screenshot(kind)
        })
    }

    applyPrefs() {
        const s = store.getSettings()
        document.documentElement.classList.toggle('no-anim', !s.animations)
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
                else this.quit()
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
        const quick = Object.entries(KINDS).map(([k, t]) =>
            h('button.rail-btn.rail-kind', { dataset: { id: 'new-' + k }, title: '新建' + t.full, style: { '--c': t.color }, onclick: () => this.newDoc(k) },
                icon(t.icon, 20), h('span.rail-label', t.name)))
        this.rail.append(
            item('open', 'folder-open', '打开', () => this.openDialog()),
            item('home', 'house', '主页'),
            h('div.rail-sep'),
            ...quick,
            h('div.rail-sep'),
            item('shot', 'scissors', '截图', e => { const r = e.currentTarget.getBoundingClientRect(); capture().then(m => openMenu(m.screenshotItems(this), { x: r.right + 8, y: r.top })) }),
            item('record', 'circle-dot', '录屏', () => this.toggleRecord()),
            h('div.rail-flex'),
            item('settings', 'settings', '设置'))
    }

    // ---------- 页面切换 ----------
    showPage(id) {
        closeMenu()
        this.page = id
        for (const p of ['home', 'settings-page']) $('#' + p).hidden = true
        for (const t of this.tabs) t.editor.el.hidden = true
        if (this.active && id !== 'editor') { this.active.editor.onHide(); this.active = null }
        if (id === 'home') { $('#home').hidden = false; this.renderHome() }
        if (id === 'settings') { $('#settings-page').hidden = false; this.renderSettings() }
        this.rail.querySelectorAll('.rail-btn').forEach(b => b.classList.toggle('active', b.dataset.id === id))
        this.renderTabs()
        document.title = 'LiteEditor'
    }

    // ---------- 标签页 ----------
    renderTabs() {
        const box = $('#tabs')
        box.replaceChildren(...this.tabs.map(t => {
            const k = KINDS[t.editor.kind]
            return h('div.tab' + (t === this.active ? '.active' : '') + (t.editor.dirty ? '.dirty' : ''), {
                title: t.editor.path ?? t.editor.name,
                onclick: () => this.activate(t),
                onauxclick: e => { if (e.button === 1) this.closeTab(t) },
            },
            h('span.tab-icon', { style: { '--c': k?.color } }, icon(t.editor.tabIcon, 14)),
            h('span.tab-title', t.editor.name),
            h('span.tab-dot'),
            h('button.tab-close', { title: '关闭 (Ctrl W)', onclick: e => { e.stopPropagation(); this.closeTab(t) } }, icon('x', 13)))
        }))
        box.querySelector('.tab.active')?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
    }

    activate(tab) {
        if (!tab) return
        closeMenu()
        if (this.active && this.active !== tab) this.active.editor.onHide()
        this.active = tab
        for (const p of ['home', 'settings-page']) $('#' + p).hidden = true
        for (const t of this.tabs) t.editor.el.hidden = t !== tab
        this.page = 'editor'
        this.rail.querySelectorAll('.rail-btn').forEach(b => b.classList.remove('active'))
        tab.editor.onShow()
        this.renderTabs()
        document.title = `${tab.editor.name} - LiteEditor`
    }

    async closeTab(tab, { force = false } = {}) {
        if (!tab) return false
        if (!force && !(await tab.editor.confirmClose())) return false
        const i = this.tabs.indexOf(tab)
        if (i < 0) return true
        this.tabs.splice(i, 1)
        if (tab.editor.path) this.closed = [tab.editor.path, ...this.closed.filter(p => p !== tab.editor.path)].slice(0, 20)
        tab.editor.destroy()
        if (this.active === tab) {
            this.active = null
            const next = this.tabs[i] ?? this.tabs[i - 1]
            if (next) this.activate(next)
            else this.showPage('home')
        } else this.renderTabs()
        return true
    }

    setTabTitle(editor) {
        if (this.tabs.some(t => t.editor === editor)) this.renderTabs()
        if (this.active?.editor === editor) document.title = `${editor.name}${editor.dirty ? ' •' : ''} - LiteEditor`
    }

    // 退出前逐个确认未保存的文档
    async quit() {
        for (const t of [...this.tabs]) {
            if (!t.editor.dirty) continue
            if (!(await t.editor.confirmClose())) return
        }
        window.lite.win.closeConfirmed()
    }

    // ---------- 新建 / 打开 ----------
    newMenuItems() {
        return Object.entries(KINDS).map(([k, t]) => ({
            label: t.full, icon: t.icon,
            submenu: TEMPLATES[k].map(tp => ({ label: tp.name, run: () => this.newDoc(k, tp.options) })),
        }))
    }

    async newDoc(kind, options = {}) {
        if (options.record) return this.toggleRecord()
        if (options.ask && kind === 'image') {
            const { askCanvasSize } = await import('./editors/image/dialogs.js')
            const o = await askCanvasSize()
            if (!o) return
            options = o
        }
        this.untitled[kind] = (this.untitled[kind] ?? 0) + 1
        const n = this.untitled[kind]
        const name = `未命名${KINDS[kind].name}${n > 1 ? ' ' + n : ''}`
        return this.openEditor(kind, { name, options })
    }

    async openDialog(kind) {
        const filters = dialogFilters()
        if (kind && KINDS[kind]) filters.unshift({ name: KINDS[kind].full, extensions: KINDS[kind].exts })
        const files = await window.lite.openDialog({ filters })
        this.openPaths(files)
    }

    async openPaths(paths) {
        const fonts = (paths ?? []).filter(isFontFile)
        if (fonts.length) { importFonts(fonts); paths = paths.filter(p => !isFontFile(p)) }
        for (const p of paths ?? []) {
            const kind = kindOf(p)
            if (!kind) { toast(`不支持的文件格式：${baseName(p)}`, 'warn'); continue }
            const exist = this.tabs.find(t => t.editor.path === p)
            if (exist) { this.activate(exist); continue }
            const st = await window.lite.stat(p)
            if (!st?.isFile) { toast(`文件不存在：${baseName(p)}`, 'error'); store.removeRecent(p); continue }
            await this.openEditor(kind, { path: p, name: baseName(p) })
        }
    }

    // file: { path?, name, bytes?, options? }
    async openEditor(kind, file) {
        let Cls
        try {
            Cls = await LOADERS[kind]()
        } catch (e) {
            console.error(e)
            return toast('加载编辑器失败：' + e.message, 'error')
        }
        const editor = new Cls(file, this)
        const tab = { editor }
        this.tabs.push(tab)
        $('#viewers').append(editor.el)
        this.activate(tab)
        if (file.path) store.addRecent({ path: file.path, name: file.name, kind })
        try {
            await editor.mount(file)
            // 截图 / 录屏等内存中的新内容还没有文件，标记为未保存，关闭时提示
            if (file.bytes && !file.path) { editor.savedIndex = -1; editor.updateDirty() }
            if (tab === this.active) editor.onShow()
        } catch (e) {
            editor.error(e)
        }
        return editor
    }

    // ---------- 截图与录屏 ----------
    async screenshot(mode = 'region', opts) {
        try { await (await capture()).takeScreenshot(this, mode, opts) } catch (e) { console.error(e); toast('截图失败：' + e.message, 'error') }
    }

    async toggleRecord() {
        const { Recorder } = await capture()
        this.recorder ??= new Recorder(this)
        const st = this.recorder.state
        if (st === 'recording' || st === 'paused') this.recorder.stop()
        else if (st === 'idle') this.recorder.start().catch(e => { console.error(e); toast('录屏失败：' + e.message, 'error') })
    }

    // 录制中：侧栏按钮与标题栏显示计时 / 暂停 / 停止
    setRecording(on) {
        const b = this.rail.querySelector('[data-id="record"]')
        b.classList.toggle('recording', on)
        clearInterval(this.recTimer)
        let bar = $('#rec-bar')
        if (!on) { bar?.remove(); b.title = '录屏'; return }
        b.title = '停止录制'
        if (!bar) {
            bar = h('div#rec-bar',
                h('span.rec-dot'), h('span.rec-time', '00:00'),
                btn('pause', '暂停 / 继续', () => this.recorder.pause(), { size: 14 }),
                btn('square', '停止录制 (Ctrl+Alt+R)', () => this.recorder.stop(), { size: 14, class: 'rec-stop' }))
            $('#titlebar').insertBefore(bar, $('.win-controls'))
        }
        const r = this.recorder
        const upd = () => {
            bar.querySelector('.rec-time').textContent = formatTime(r.elapsed())
            bar.classList.toggle('paused', r.state === 'paused')
        }
        upd()
        this.recTimer = setInterval(upd, 500)
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

        const hero = h('div.hero',
            h('div.hero-art', h('i.o1'), h('i.o2'), h('i.o3')),
            h('div.hero-text',
                h('div.hero-greet', greet + '，欢迎使用'),
                h('h1.hero-title', 'LiteEditor'),
                h('p.hero-sub', '一个应用，修图、作图、写文档、做表格、做演示、剪视频、编曲，还能截图录屏。所有文件都在本地处理。'),
                h('div.hero-actions',
                    h('button.btn.primary.lg', { onclick: () => this.openDialog() }, icon('folder-open', 18), '打开文件'),
                    h('button.btn.lg', { onclick: e => togglePopover(e.currentTarget, () => menu(Object.entries(KINDS).map(([k, t]) => ({ label: '新建' + t.full, icon: t.icon, onclick: () => this.newDoc(k) })))) }, icon('file-plus', 18), '新建')),
                h('div.hero-tools',
                    h('button.hero-tool', { onclick: () => this.screenshot('region') }, icon('scissors', 16), '区域截图', h('kbd', 'Ctrl+Alt+A')),
                    h('button.hero-tool', { onclick: () => this.screenshot('full') }, icon('monitor', 16), '全屏截图', h('kbd', 'Ctrl+Alt+F')),
                    h('button.hero-tool', { onclick: () => this.toggleRecord() }, icon('circle-dot', 16), '录制屏幕', h('kbd', 'Ctrl+Alt+R'))),
                h('div.hero-hint', icon('mouse-pointer-2', 14), '也可以直接把文件拖到窗口任意位置')))

        const kinds = Object.entries(KINDS).map(([k, t]) => h('div.kind-block', { style: { '--c': t.color } },
            h('div.kind-head',
                h('span.cat-icon', icon(t.icon, 22)),
                h('div.cat-text', h('span.cat-name', t.full), h('span.cat-desc', t.desc)),
                h('button.link-btn', { onclick: () => this.openDialog(k) }, icon('folder-open', 14), '打开')),
            h('div.tpl-row', TEMPLATES[k].map(tp => h('button.tpl-card', { onclick: () => this.newDoc(k, tp.options) },
                h('span.tpl-thumb', tplThumb(k, tp.id)),
                h('span.tpl-name', tp.name),
                h('span.tpl-desc', tp.desc))))))

        const recentBox = h('div.recent')
        if (!recent.length) {
            recentBox.append(h('div.recent-empty', icon('library', 34), h('div', '最近打开或保存的文件会显示在这里')))
        } else {
            recentBox.append(...recent.slice(0, 24).map(r => {
                const t = KINDS[r.kind] ?? {}
                return h('div.recent-item', { title: r.path, onclick: () => this.openPaths([r.path]) },
                    h('span.recent-icon', { style: { '--c': t.color } }, icon(t.icon ?? 'file', 20),
                        h('span.recent-ext', extOf(r.name).toUpperCase())),
                    h('div.recent-text',
                        h('div.recent-name', r.name),
                        h('div.recent-sub', `${t.full ?? ''} · ${formatDate(r.time)}`)),
                    btn('ellipsis', '更多', e => {
                        e.stopPropagation()
                        togglePopover(e.currentTarget, () => menu([
                            { label: '打开', icon: 'folder-open', onclick: () => this.openPaths([r.path]) },
                            { label: '在文件夹中显示', icon: 'folder', onclick: () => window.lite.showInFolder(r.path) },
                            '-',
                            { label: '从列表中移除', icon: 'trash-2', danger: true, onclick: () => { store.removeRecent(r.path); this.renderHome() } },
                        ]))
                    }, { class: 'recent-more', size: 16 }))
            }))
        }

        home.replaceChildren(h('div.home-inner',
            hero,
            h('div.section-head', h('h2', '新建'), h('span.section-sub', '从模板开始，或直接打开已有文件')),
            h('div.kind-grid', kinds),
            h('div.section-head', h('h2', '最近文件'),
                recent.length ? h('button.link-btn', { onclick: () => { store.clearRecent(); this.renderHome() } }, icon('trash-2', 14), '清空') : null),
            recentBox,
            h('div.home-foot', '快捷键：Ctrl+Shift+P 命令面板 · Ctrl+N 新建 · Ctrl+O 打开 · Ctrl+S 保存 · Ctrl+Z / Ctrl+Y 撤销 / 重做 · Ctrl+W 关闭 · Ctrl+Shift+T 重新打开 · Ctrl+Tab 切换标签 · F11 全屏 · Ctrl+Alt+A 截图 · Ctrl+Alt+R 录屏')))
    }

    // ---------- 设置页 ----------
    renderSettings() {
        const s = store.getSettings()
        const page = $('#settings-page')
        const row = (title, desc, control) => h('div.set-row', h('div.set-text', h('div.set-title', title), desc ? h('div.set-desc', desc) : null), control)
        const info = h('div.set-desc', '')
        window.lite?.appInfo().then(i => { info.textContent = `版本 ${i.version} · Electron ${i.electron} · Chromium ${i.chrome}` })
        const restartAutosave = () => this.tabs.forEach(t => t.editor.startAutosave())
        page.replaceChildren(h('div.home-inner.narrow',
            h('div.page-head', h('div', h('h1.page-title', '设置'), h('p.page-sub', '个性化你的编辑体验'))),
            h('div.set-card',
                h('div.set-card-title', icon('sparkles', 16), '界面'),
                row('主题', THEME_HINT, null),
                row('动画效果', '界面过渡动画', toggle(s.animations, v => { store.set('animations', v); this.applyPrefs() })),
                row('界面缩放', '调整整体界面大小', segmented([[0.9, '90%'], [1, '100%'], [1.1, '110%'], [1.25, '125%']], s.uiScale, v => { store.set('uiScale', v); this.applyPrefs() }).el)),
            h('div.set-card',
                h('div.set-card-title', icon('save', 16), '保存与撤销'),
                row('自动保存', '已保存过的文件定时自动保存（仅无损格式）', toggle(s.autosave, v => { store.set('autosave', v); restartAutosave() })),
                row('自动保存间隔', null, slider({ min: 15, max: 600, step: 15, value: s.autosaveInterval, format: v => v + ' 秒', onchange: v => { store.set('autosaveInterval', v); restartAutosave() } }).el),
                row('撤销步数', '新打开的文档生效；图像编辑步数越多占用内存越大', slider({ min: 10, max: 300, step: 10, value: s.historyLimit, format: v => v + ' 步', oninput: v => store.set('historyLimit', v) }).el)),
            h('div.set-card',
                h('div.set-card-title', icon('pen-tool', 16), '编辑器'),
                row('透明背景棋盘格', '图像编辑中透明区域显示棋盘格', toggle(s.imageCheckerboard, v => store.set('imageCheckerboard', v))),
                row('几何画板网格', '新建画板时显示坐标网格', toggle(s.geoGrid, v => store.set('geoGrid', v))),
                row('几何画板吸附', '作图时自动吸附到已有的点、线与网格', toggle(s.geoSnap, v => store.set('geoSnap', v))),
                row('文档拼写检查', '新打开的文档生效', toggle(s.docSpellcheck, v => store.set('docSpellcheck', v))),
                row('新演示文稿比例', null, segmented([['16:9', '16:9'], ['4:3', '4:3']], s.slideRatio, v => store.set('slideRatio', v)).el)),
            h('div.set-card',
                h('div.set-card-title', icon('type', 16), '字体'),
                row('导入字体', '导入 TTF / OTF / WOFF 字体后，可在文档、表格、演示、图像与视频字幕中使用；也可以直接把字体文件拖进窗口', h('div.set-btns',
                    h('button.btn', { onclick: () => window.lite.showInFolder(userFontDir()) }, icon('folder', 15), '字体文件夹'),
                    h('button.btn.primary', { onclick: () => pickAndImportFonts() }, icon('plus', 15), '导入字体'))),
                this.fontListBox = h('div.font-list')),
            h('div.set-card',
                h('div.set-card-title', icon('scissors', 16), '截图与录屏'),
                row('截图后在图像编辑器中打开', '关闭后区域截图只复制到剪贴板', toggle(store.get('shotOpenEditor') !== false, v => store.set('shotOpenEditor', v))),
                row('全局快捷键', 'Ctrl+Alt+A 区域截图 · Ctrl+Alt+F 全屏截图 · Ctrl+Alt+R 开始 / 停止录屏 · Ctrl+Alt+P 暂停录屏', null)),
            h('div.set-card',
                h('div.set-card-title', icon('info', 16), '关于'),
                row('LiteEditor', info, h('img.about-logo', { src: './logo.svg', alt: '' })),
                row('恢复默认设置', '所有偏好将被重置（主题由 CML 启动器决定）', h('button.btn.danger', {
                    onclick: () => { store.resetSettings(); this.applyPrefs(); this.renderSettings(); toast('已恢复默认设置', 'success') },
                }, '恢复默认')),
                row('清除最近文件', null, h('button.btn', { onclick: () => { store.clearRecent(); toast('已清除', 'success') } }, '清除')))))
        this.renderFontList()
    }

    renderFontList() {
        if (!this.fontListBox) return
        const list = userFonts()
        if (!list.length) return this.fontListBox.replaceChildren(h('div.font-empty', '尚未导入字体'))
        this.fontListBox.replaceChildren(...list.map(f => h('div.font-item',
            h('div.font-meta',
                h('div.font-name', f.label, f.label !== f.family ? h('span.font-family', f.family) : null, h('span.font-sub', f.sub)),
                h('div.font-sample', { style: { fontFamily: `"${f.family}"`, fontWeight: f.weight, fontStyle: f.style } }, '永和九年，岁在癸丑 The quick brown fox 0123')),
            h('span.font-size', `${f.file} · ${formatBytes(f.size)}`),
            btn('trash-2', '删除字体', async () => {
                if (!(await confirmDialog({ title: '删除字体', message: `删除“${f.label} ${f.sub}”？使用该字体的内容将显示为默认字体。`, okText: '删除', danger: true }))) return
                await removeFont(f.file)
                toast('已删除字体', 'success')
            }, { size: 16 }))))
    }

    reopenClosed() {
        const p = this.closed.find(x => !this.tabs.some(t => t.editor.path === x))
        if (!p) return toast('没有最近关闭的文件')
        this.closed = this.closed.filter(x => x !== p)
        this.openPaths([p])
    }

    // ---------- 命令面板 ----------
    globalCommands() {
        const cmds = [
            ...Object.entries(KINDS).flatMap(([k, t]) => TEMPLATES[k].map(tp => ({ label: `新建${t.full}：${tp.name}`, path: '新建', icon: t.icon, run: () => this.newDoc(k, tp.options) }))),
            { label: '打开文件…', path: '文件', icon: 'folder-open', key: 'Ctrl+O', run: () => this.openDialog() },
            { label: '重新打开关闭的标签', path: '文件', icon: 'history', key: 'Ctrl+Shift+T', run: () => this.reopenClosed() },
            { label: '导入字体…', path: '字体', icon: 'type', run: () => pickAndImportFonts() },
            { label: '管理字体', path: '字体', icon: 'type', run: () => this.showPage('settings') },
            { label: '区域截图', path: '工具', icon: 'scissors', key: 'Ctrl+Alt+A', run: () => this.screenshot('region') },
            { label: '全屏截图', path: '工具', icon: 'monitor', key: 'Ctrl+Alt+F', run: () => this.screenshot('full') },
            { label: '开始 / 停止录屏', path: '工具', icon: 'circle-dot', key: 'Ctrl+Alt+R', run: () => this.toggleRecord() },
            { label: '全屏', path: '界面', icon: 'maximize', key: 'F11', run: () => this.toggleFullscreen() },
            { label: '主页', path: '界面', icon: 'house', run: () => this.showPage('home') },
            { label: '设置', path: '界面', icon: 'settings', run: () => this.showPage('settings') },
            ...this.tabs.map(t => ({ label: `切换到：${t.editor.name}`, path: '标签页', icon: t.editor.tabIcon, run: () => this.activate(t) })),
            ...store.getRecent().slice(0, 20).map(r => ({ label: `打开最近：${r.name}`, path: r.path, icon: KINDS[r.kind]?.icon ?? 'file', run: () => this.openPaths([r.path]) })),
        ]
        return cmds
    }

    commandPalette() {
        const ed = this.page === 'editor' ? this.active?.editor : null
        let cmds = []
        if (ed) {
            try { cmds = flattenMenus([ed.fileMenu(), ...ed.menus()]) } catch (e) { console.warn(e) }
        }
        const seen = new Set(cmds.map(c => c.label))
        openPalette([...cmds, ...this.globalCommands().filter(c => !seen.has(c.label))], { placeholder: ed ? `在“${ed.name}”中搜索命令，或输入全局命令…` : '搜索命令…' })
    }

    // ---------- 全局事件 ----------
    bindGlobal() {
        document.addEventListener('keydown', e => this.handleKey(e))

        let depth = 0
        const mask = $('#drop-mask')
        mask.querySelector('.drop-icon').append(icon('file-down', 44))
        const hasFiles = e => [...(e.dataTransfer?.types ?? [])].includes('Files')
        // 编辑器内部可以接管拖放（例如把图片拖进文档），此时不显示遮罩
        const inEditorDrop = e => e.target?.closest?.('[data-drop]')
        document.addEventListener('dragenter', e => { if (!hasFiles(e) || inEditorDrop(e)) return; depth++; mask.hidden = false; requestAnimationFrame(() => mask.classList.add('show')) })
        document.addEventListener('dragleave', e => { if (!hasFiles(e)) return; if (--depth <= 0) { depth = 0; mask.classList.remove('show'); mask.hidden = true } })
        document.addEventListener('dragover', e => { if (hasFiles(e)) e.preventDefault() })
        document.addEventListener('drop', e => {
            e.preventDefault()
            depth = 0
            mask.classList.remove('show')
            mask.hidden = true
            if (e.defaultPrevented && inEditorDrop(e)) return
            const paths = [...e.dataTransfer.files].map(f => window.lite.pathForFile(f)).filter(Boolean)
            // 字体文件直接导入
            importFonts(paths.filter(isFontFile))
            this.openPaths(paths.filter(p => !isFontFile(p)))
        })
        window.addEventListener('contextmenu', e => {
            if (!e.target.closest('input, textarea, [contenteditable]')) e.preventDefault()
        })
    }

    handleKey(e) {
        if (e.isComposing) return
        const k = e.key
        const lower = k.toLowerCase()
        if (menuOpen() && k === 'Escape') return
        // 模态对话框打开时不处理全局快捷键
        if (document.querySelector('.modal-mask')) return
        if (k === 'F1' || (e.ctrlKey && e.shiftKey && lower === 'p')) { e.preventDefault(); this.commandPalette(); return }
        if (e.ctrlKey && e.shiftKey && lower === 't') { e.preventDefault(); this.reopenClosed(); return }
        if (e.ctrlKey && !e.shiftKey && lower === 'o') { e.preventDefault(); this.openDialog(); return }
        if (e.ctrlKey && !e.shiftKey && lower === 'n') {
            e.preventDefault()
            this.newDoc(this.active?.editor.kind ?? 'doc')
            return
        }
        if (e.ctrlKey && lower === 'w') { e.preventDefault(); if (this.active) this.closeTab(this.active); return }
        if (e.ctrlKey && k === 'Tab') {
            e.preventDefault()
            if (!this.tabs.length) return
            const i = this.tabs.indexOf(this.active)
            this.activate(this.tabs[((i < 0 ? 0 : i + (e.shiftKey ? -1 : 1)) + this.tabs.length) % this.tabs.length])
            return
        }
        if (k === 'F11') { e.preventDefault(); this.toggleFullscreen(); return }
        if (this.active && this.page === 'editor') {
            if (this.active.editor.handleKey(e)) { e.preventDefault(); return }
        }
        if (k === 'Escape' && document.documentElement.classList.contains('fullscreen')) this.toggleFullscreen()
    }
}

// 模板缩略图（纯 CSS 小示意）
function tplThumb(kind, id) {
    const t = h('span.tt.tt-' + kind + '.tt-' + id)
    const n = { image: 3, geo: 4, doc: 5, sheet: 6, slides: 3, video: 4, midi: 6 }[kind]
    for (let i = 0; i < n; i++) t.append(h('i'))
    return t
}

window.app = new App()
