import { Archive } from 'libarchive.js'
import { Viewer } from './base.js'
import { ImageViewer } from './image.js'
import { h, btn, formatBytes, prompt, toast, segmented } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { Source, typeOf, TYPES, extOf } from '../core/files.js'

Archive.init({ workerUrl: new URL('./vendor/libarchive/worker-bundle.js', location.href).href })

const naturalCompare = new Intl.Collator('zh-CN', { numeric: true, sensitivity: 'base' }).compare
const isJunk = p => /(^|\/)(__MACOSX|\.DS_Store|Thumbs\.db|desktop\.ini)(\/|$)/i.test(p)

// 压缩包查看器：列出内容、画廊式预览图片，支持从中打开任意受支持文件
export class ArchiveViewer extends Viewer {
    view = 'grid'
    filter = 'all'
    entries = []

    async mount() {
        this.addTitle()
        this.stats = h('span.v-progress-label', '')
        this.center.append(this.stats)
        this.modeSeg = segmented([['grid', '', 'layout-grid'], ['list', '', 'list']], this.view, v => { this.view = v; this.render() })
        this.filterSeg = segmented([['all', '全部'], ['image', '图片'], ['other', '其他']], this.filter, v => { this.filter = v; this.render() })
        this.right.append(this.filterSeg.el, this.modeSeg.el)
        this.tool('images', '以画廊方式浏览全部图片', () => this.openGallery(0))

        this.progress = h('div.ar-progress', h('div.ar-progress-bar'))
        this.body = h('div.ar-body')
        this.content.append(h('div.ar-root', this.progress, this.body))

        const ld = this.loading('正在读取压缩包…')
        try {
            const file = await this.source.file()
            this.archive = await Archive.open(file)
            const enc = await this.archive.hasEncryptedData()
            if (enc) {
                const pwd = await prompt({ title: '压缩包已加密', message: '请输入解压密码', type: 'password' })
                if (pwd == null) { ld.done(); return this.error('需要密码才能打开此压缩包') }
                await this.archive.usePassword(pwd)
            }
            const list = await this.archive.getFilesArray()
            this.entries = list
                .map(({ file, path }) => {
                    const full = (path ?? '') + file.name
                    return { name: file.name, dir: path ?? '', full, size: file.size, type: typeOf(file.name), file: null }
                })
                .filter(e => !isJunk(e.full))
                .sort((a, b) => naturalCompare(a.full, b.full))
        } catch (e) {
            ld.done()
            return this.error(e?.message?.includes('Unrecognized') ? '无法识别的压缩格式或文件已损坏' : e)
        }
        ld.done()
        this.images = this.entries.filter(e => e.type === 'image')
        const total = this.entries.reduce((s, e) => s + (e.size || 0), 0)
        this.stats.textContent = `${this.entries.length} 个文件 · ${this.images.length} 张图片 · ${formatBytes(total)}`
        this.setSubtitle(`${extOf(this.source.name).toUpperCase()} 压缩包`)
        if (!this.images.length) { this.filter = 'all'; this.view = 'list'; this.modeSeg.set('list') }
        this.render()
        this.extractAll()
    }

    // 后台解压全部文件，边解压边显示缩略图
    async extractAll() {
        const bar = this.progress.firstChild
        const byPath = new Map(this.entries.map(e => [e.full, e]))
        this.progress.classList.add('show')
        // libarchive 在 worker 中一次性解压，这里用渐进动画表示进度
        let fake = 0
        const timer = setInterval(() => { fake += (92 - fake) * 0.08; bar.style.width = fake + '%' }, 100)
        try {
            await this.archive.extractFiles()
            const files = await this.archive.getFilesArray()
            for (const { file, path } of files) {
                if (!(file instanceof File)) continue
                const e = byPath.get((path ?? '') + file.name)
                if (!e) continue
                e.file = file
                e.source = Source.fromBlob(file, e.name, this.source.name)
                this.fillEntry(e)
            }
            bar.style.width = '100%'
        } catch (e) {
            console.error(e)
            toast('解压时出错：' + (e.message ?? e) + '（可能是密码错误或文件损坏）', 'error', 5000)
        }
        clearInterval(timer)
        this.progress.classList.remove('show')
        this.extracted = true
        for (const e of this.entries) if (!e.file) this.markFailed(e)
    }

    visible() {
        if (this.filter === 'image') return this.images
        if (this.filter === 'other') return this.entries.filter(e => e.type !== 'image')
        return this.entries
    }

    render() {
        const list = this.visible()
        this.cells = new Map()
        if (!list.length) {
            this.body.replaceChildren(h('div.empty-mini.big', icon('package-open', 40), h('div', '没有可显示的内容')))
            return
        }
        const wrap = h(this.view === 'grid' ? 'div.ar-grid' : 'div.ar-list')
        let lastDir = null
        for (const e of list) {
            if (this.view === 'list' && e.dir !== lastDir) {
                lastDir = e.dir
                if (e.dir) wrap.append(h('div.ar-dir', icon('folder', 15), e.dir.replace(/\/$/, '')))
            }
            const cell = this.view === 'grid' ? this.gridCell(e) : this.listRow(e)
            this.cells.set(e, cell)
            wrap.append(cell)
            if (e.file) this.fillEntry(e)
        }
        this.body.replaceChildren(wrap)
    }

    gridCell(e) {
        const t = TYPES[e.type]
        return h('div.ar-cell' + (e.type === 'image' ? '.image' : ''), { title: e.full, onclick: () => this.openEntry(e) },
            h('div.ar-thumb', { style: { '--c': t?.color ?? '#888' } },
                e.type === 'image' ? h('div.ar-shimmer') : icon(t?.icon ?? 'file', 34)),
            h('div.ar-name', e.name),
            h('div.ar-size', formatBytes(e.size)))
    }

    listRow(e) {
        const t = TYPES[e.type]
        return h('div.ar-row', { title: e.full, onclick: () => this.openEntry(e) },
            h('span.ar-row-icon', { style: { '--c': t?.color ?? 'var(--text-3)' } }, icon(t?.icon ?? 'file', 17)),
            h('span.ar-row-name', e.name),
            h('span.ar-row-type', t?.name ?? (extOf(e.name).toUpperCase() || '文件')),
            h('span.ar-row-size', formatBytes(e.size)),
            h('span.ar-row-state'))
    }

    fillEntry(e) {
        const cell = this.cells?.get(e)
        if (!cell) return
        cell.classList.add('ready')
        if (e.type === 'image' && this.view === 'grid') {
            const img = h('img', { src: e.source.url(), decoding: 'async', loading: 'lazy', alt: '' })
            img.onerror = () => img.replaceWith(icon('image-off', 30))
            cell.querySelector('.ar-thumb').replaceChildren(img)
        }
    }
    markFailed(e) {
        const cell = this.cells?.get(e)
        cell?.classList.add('failed')
    }

    async openEntry(e) {
        if (!e.file) {
            if (!this.extracted) return toast('正在解压，请稍候…')
            return toast('该文件未能解压', 'error')
        }
        if (e.type === 'image') return this.openGallery(this.images.indexOf(e))
        if (!e.type) return toast(`不支持预览此类型的文件：${e.name}`, 'warn')
        if (e.type === 'archive') {
            // 嵌套压缩包
            return this.app.openSource(Source.fromBlob(e.file, e.name, this.source.name))
        }
        this.app.openSource(Source.fromBlob(e.file, e.name, this.source.name))
    }

    async openGallery(i) {
        const ready = this.images.filter(e => e.source)
        if (!ready.length) return toast(this.images.length ? '图片仍在解压中…' : '压缩包中没有图片', 'warn')
        const target = this.images[i]
        const index = Math.max(0, ready.indexOf(target))
        this.closeGallery()
        const iv = new ImageViewer(ready[0].source, this.app, { list: ready.map(e => e.source), index })
        iv.ownsList = true
        iv.setTabTitle = () => {}
        this.lightbox = iv
        const layer = h('div.ar-lightbox', iv.el)
        this.content.append(layer)
        await iv.mount()
        iv.left.prepend(btn('arrow-left', '返回列表 (Esc)', () => this.closeGallery()))
        requestAnimationFrame(() => layer.classList.add('show'))
    }

    closeGallery() {
        if (!this.lightbox) return
        const layer = this.lightbox.el.parentElement
        this.lightbox.destroy()
        layer?.remove()
        this.lightbox = null
    }

    onHide() { this.lightbox?.onHide() }

    onKey(e) {
        if (this.lightbox) {
            if (e.key === 'Escape') { this.closeGallery(); return true }
            return this.lightbox.onKey(e)
        }
        return false
    }

    destroy() {
        this.closeGallery()
        for (const e of this.entries) e.source?.release()
        this.archive?.close?.().catch?.(() => {})
        super.destroy()
    }
}
