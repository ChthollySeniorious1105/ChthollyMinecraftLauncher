import { Viewer, sidebarTabs } from './base.js'
import { h, btn, clamp, toast } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'
import { decodeText } from '../core/encoding.js'
import { localURL } from '../core/files.js'
import { DomFinder, findBar } from '../core/find.js'

// CHM 帮助文档：主进程用 hh.exe 反编译到缓存目录，这里解析目录（.hhc）与索引（.hhk），在沙箱 iframe 中浏览页面
export class ChmViewer extends Viewer {
    zoomLevel = 1
    history = []
    hIndex = -1

    async mount() {
        this.addTitle()
        this.tool('panel-left', '目录 / 索引', () => this.toggleSidebar(), this.left)
        this.left.prepend(this.left.lastChild)
        this.backBtn = btn('arrow-left', '后退 (Alt ←)', () => this.nav(-1))
        this.fwdBtn = btn('arrow-right', '前进 (Alt →)', () => this.nav(1))
        this.zoomLabel = h('span.zoom-label.static', '100%')
        this.center.append(this.backBtn, this.fwdBtn, btn('house', '首页', () => this.open(this.home)), h('span.v-sep'),
            btn('zoom-out', '缩小', () => this.setZoom(this.zoomLevel / 1.1)), this.zoomLabel, btn('zoom-in', '放大', () => this.setZoom(this.zoomLevel * 1.1)))
        this.tool('search', '页内查找 (Ctrl F)', () => this.find.open())
        this.tool('maximize', '全屏 (F11)', () => this.app.toggleFullscreen())

        this.frame = h('iframe.web-frame', { sandbox: 'allow-same-origin' })
        this.find = findBar(() => this.finder)
        this.content.append(this.frame, this.find.el)
        if (!this.source.path) return this.error('请先从压缩包中解压此 CHM 文件后再打开')

        const ld = this.loading('正在解析 CHM 帮助文档…')
        try {
            const { dir, files } = await window.lite.extractChm(this.source.path)
            this.dir = dir
            this.files = files
            const read = async rel => decodeText(await window.lite.readFile(dir + '\\' + rel.replace(/\//g, '\\'))).text
            const hhc = files.find(f => /\.hhc$/i.test(f))
            const hhk = files.find(f => /\.hhk$/i.test(f))
            this.toc = hhc ? parseSitemap(await read(hhc)) : []
            this.index = hhk ? flatten(parseSitemap(await read(hhk))) : []
            this.pages = files.filter(f => /\.html?$/i.test(f))
        } catch (e) {
            ld.done()
            return this.error(e)
        }
        ld.done()
        this.buildSidebar()
        const firstTopic = flatten(this.toc).find(t => t.local)?.local
        this.home = firstTopic ?? this.pages.find(p => /(^|\/)(index|default|main|welcome)\.html?$/i.test(p)) ?? this.pages[0]
        this.setSubtitle(`CHM 帮助文档 · ${flatten(this.toc).length || this.pages.length} 个主题`)
        const saved = store.getProgress(this.source.key)
        this.toggleSidebar(true)
        if (!this.home) return this.error('CHM 中没有可显示的页面')
        await this.open(saved?.page && this.pages.includes(saved.page) ? saved.page : this.home)
    }

    buildSidebar() {
        const tocPanel = h('div.toc-panel')
        const mk = list => h('ol', list.map(t => h('li',
            t.children?.length
                ? h('details', { open: list.length < 12 }, h('summary', h('a', { dataset: { local: t.local ?? '' }, onclick: e => { if (t.local) { e.preventDefault(); this.open(t.local) } } }, t.name)), mk(t.children))
                : h('a', { dataset: { local: t.local ?? '' }, onclick: () => t.local && this.open(t.local) }, t.name))))
        tocPanel.append(this.toc.length ? mk(this.toc) : h('div.empty-mini', '没有目录，可在「页面」中浏览'))
        this.tocPanel = tocPanel

        const idxInput = h('input.input', { type: 'search', placeholder: '筛选索引…' })
        const idxList = h('div.search-results')
        const renderIdx = () => {
            const q = idxInput.value.trim().toLowerCase()
            const src = this.index.length ? this.index : this.pages.map(p => ({ name: p.replace(/\.html?$/i, ''), local: p }))
            const list = src.filter(t => !q || t.name.toLowerCase().includes(q)).slice(0, 800)
            idxList.replaceChildren(...list.map(t => h('div.search-item', { onclick: () => t.local && this.open(t.local) }, t.name)))
            if (!list.length) idxList.append(h('div.search-status', '没有匹配项'))
        }
        idxInput.addEventListener('input', renderIdx)
        renderIdx()
        this.tabs = sidebarTabs([
            { id: 'toc', label: '目录', icon: 'list-tree', panel: tocPanel },
            { id: 'index', label: this.index.length ? '索引' : '页面', icon: 'list', panel: h('div.search-panel', h('div.search-box', icon('search', 16), idxInput), idxList), onshow: () => setTimeout(() => idxInput.focus(), 50) },
        ])
        this.sidebar.append(this.tabs.el)
    }

    // 打开 CHM 内的页面（相对路径，可带 #锚点）
    async open(local, push = true) {
        if (!local) return
        let [page, hash] = local.replace(/\\/g, '/').replace(/^\/+/, '').split('#')
        page = decodeURIComponent(page)
        const hit = this.files.find(f => f.toLowerCase() === page.toLowerCase())
        if (!hit) return toast('页面不存在：' + page, 'warn')
        this.page = hit
        if (push) {
            this.history.splice(this.hIndex + 1)
            this.history.push(hit + (hash ? '#' + hash : ''))
            this.hIndex = this.history.length - 1
        }
        this.updateNav()
        const html = decodeText(await window.lite.readFile(this.dir + '\\' + hit.replace(/\//g, '\\'))).text
        const doc = new DOMParser().parseFromString(html, 'text/html')
        doc.querySelectorAll('script, object[classid], meta[http-equiv="refresh" i]').forEach(e => e.remove())
        for (const el of doc.querySelectorAll('*')) for (const a of [...el.attributes]) if (/^on/i.test(a.name)) el.removeAttribute(a.name)
        const base = localURL(this.dir + '\\' + hit.replace(/\//g, '\\')).replace(/[^/]*$/, '')
        doc.head.prepend(Object.assign(doc.createElement('base'), { href: base }))
        const csp = doc.createElement('meta')
        csp.httpEquiv = 'Content-Security-Policy'
        csp.content = "default-src 'none'; img-src media: data:; style-src media: 'unsafe-inline'; font-src media: data:"
        doc.head.prepend(csp)
        await new Promise(r => { this.frame.onload = r; this.frame.srcdoc = '<!DOCTYPE html>' + doc.documentElement.outerHTML })
        const fdoc = this.frame.contentDocument
        this.finder = new DomFinder(fdoc.body ?? fdoc.documentElement)
        const st = fdoc.createElement('style')
        st.textContent = 'mark.lr-hit{background:#ffe066;color:inherit}mark.lr-hit.current{background:#ff9f1c}'
        fdoc.head.append(st)
        fdoc.documentElement.style.zoom = this.zoomLevel
        if (hash) fdoc.getElementById(hash)?.scrollIntoView() ?? fdoc.querySelector(`a[name="${CSS.escape(hash)}"]`)?.scrollIntoView()
        fdoc.addEventListener('click', e => {
            const a = e.target.closest?.('a[href]')
            if (!a) return
            const href = a.getAttribute('href')
            e.preventDefault()
            if (href.startsWith('#')) return fdoc.getElementById(href.slice(1))?.scrollIntoView({ behavior: 'smooth' })
            if (/^(https?:|mailto:)/i.test(href)) return window.lite.openExternal(href)
            // ms-its:xxx.chm::/page.htm 形式的内部链接
            const m = /::\/?(.+)$/.exec(href)
            const rel = m ? m[1] : resolveRel(hit, href)
            this.open(rel)
        })
        fdoc.addEventListener('keydown', e => {
            if (e.ctrlKey || e.altKey || ['F11', 'Escape'].includes(e.key)) {
                const ev = new KeyboardEvent('keydown', { key: e.key, ctrlKey: e.ctrlKey, altKey: e.altKey, shiftKey: e.shiftKey, bubbles: true, cancelable: true })
                if (!document.dispatchEvent(ev)) e.preventDefault()
            }
        })
        this.highlightToc()
        store.setProgress(this.source.key, { page: hit })
    }

    highlightToc() {
        const cur = this.page?.toLowerCase()
        this.tocPanel?.querySelectorAll('a').forEach(a => {
            const on = a.dataset.local && a.dataset.local.split('#')[0].toLowerCase() === cur
            a.toggleAttribute('aria-current', on)
            if (on) { a.closest('details')?.setAttribute('open', ''); a.scrollIntoView({ block: 'nearest' }) }
        })
    }

    nav(d) {
        const i = this.hIndex + d
        if (i < 0 || i >= this.history.length) return
        this.hIndex = i
        this.open(this.history[i], false)
    }
    updateNav() {
        this.backBtn.disabled = this.hIndex <= 0
        this.fwdBtn.disabled = this.hIndex >= this.history.length - 1
    }

    setZoom(z) {
        this.zoomLevel = clamp(z, 0.3, 4)
        this.zoomLabel.textContent = Math.round(this.zoomLevel * 100) + '%'
        const root = this.frame.contentDocument?.documentElement
        if (root) root.style.zoom = this.zoomLevel
    }

    onKey(e) {
        if (e.ctrlKey && e.key.toLowerCase() === 'f') { this.find.open(); return true }
        if (e.altKey && e.key === 'ArrowLeft') { this.nav(-1); return true }
        if (e.altKey && e.key === 'ArrowRight') { this.nav(1); return true }
        if (e.ctrlKey && (e.key === '=' || e.key === '+')) { this.setZoom(this.zoomLevel * 1.1); return true }
        if (e.ctrlKey && e.key === '-') { this.setZoom(this.zoomLevel / 1.1); return true }
        return false
    }
}

function resolveRel(from, href) {
    const parts = (from.replace(/[^/]*$/, '') + href).split('/')
    const out = []
    for (const s of parts) { if (s === '..') out.pop(); else if (s !== '.' && s !== '') out.push(s) }
    return out.join('/')
}

// 解析 HTML Help 的 sitemap 格式（.hhc 目录 / .hhk 索引）
export function parseSitemap(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html')
    const walk = ul => {
        const out = []
        let last = null
        for (const el of ul.children) {
            if (el.tagName === 'LI') {
                const obj = el.querySelector(':scope > object')
                if (obj) {
                    const p = n => obj.querySelector(`param[name="${n}" i]`)?.getAttribute('value')
                    last = { name: p('Name') ?? '', local: p('Local') ?? null, children: [] }
                    out.push(last)
                }
                const nested = el.querySelector(':scope > ul')
                if (nested && last) last.children.push(...walk(nested))
            } else if (el.tagName === 'UL' && last) last.children.push(...walk(el))
        }
        return out
    }
    const root = doc.body.querySelector('ul')
    return root ? walk(root) : []
}
const flatten = list => list.flatMap(t => [t, ...flatten(t.children ?? [])])
