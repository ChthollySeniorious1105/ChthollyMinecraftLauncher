// 格式转换界面：单文件转换对话框 + 批量转换页面
import { h, toast, formatBytes } from '../core/dom.js'
import { icon } from '../core/icons.js'
import { TYPES, typeOf, dirName, stemOf, Source } from '../core/files.js'
import { targetsFor, convert, TARGETS } from '../core/convert.js'
import { toastProgress, toastAction } from '../core/print.js'

const lossBadge = t => t.lossless
    ? h('span.cv-badge.ok', icon('badge-check', 13), '无损')
    : h('span.cv-badge.lossy', { title: t.losses.join('\n') }, icon('triangle-alert', 13), '有损')

// 目标格式选择列表（附带有损原因）
function targetList(targets, selected, onpick) {
    const list = h('div.cv-targets')
    const detail = h('div.cv-detail')
    const render = () => {
        list.replaceChildren(...targets.map(t => h('button.cv-target' + (t.id === selected ? '.active' : ''), {
            onclick: () => { selected = t.id; render(); onpick(t) },
        }, h('span.cv-target-name', t.label), lossBadge(t))))
        const t = targets.find(x => x.id === selected)
        detail.replaceChildren(!t ? '' : t.lossless
            ? h('div.cv-ok', icon('circle-check', 15), `转换为 ${t.label} 不会丢失内容。`)
            : h('div.cv-warn', h('div.cv-warn-title', icon('triangle-alert', 15), `转换为 ${t.label} 属于有损转换：`), h('ul', t.losses.map(x => h('li', x)))))
    }
    render()
    return { el: h('div', list, detail), get value() { return selected } }
}

// 单个文件的转换对话框
export async function convertDialog(app, source) {
    const targets = targetsFor(source)
    if (!targets.length) return toast(`暂不支持转换 ${source.ext.toUpperCase()} 文件`, 'warn')
    const last = localStorage.getItem('lr.convert.' + source.type)
    let pick = targets.find(t => t.id === last)?.id ?? targets[0].id
    const tl = targetList(targets, pick, t => { pick = t.id })
    await new Promise(resolve => {
        const close = () => { mask.classList.remove('show'); setTimeout(() => mask.remove(), 200); resolve() }
        const mask = h('div.modal-mask', h('div.modal.cv-dialog',
            h('div.modal-title', icon('arrow-right-left', 18), '转换格式'),
            h('div.cv-src', icon(TYPES[source.type]?.icon ?? 'file', 16), h('span', source.name), source.size ? h('span.cv-size', formatBytes(source.size)) : null),
            h('div.cv-caption', '选择目标格式'),
            tl.el,
            h('div.modal-actions',
                h('button.btn', { onclick: close }, '取消'),
                h('button.btn.primary', { onclick: async () => { close(); await runOne(source, tl.value) } }, icon('arrow-right-left', 15), '转换'))))
        mask.addEventListener('keydown', e => { if (e.key === 'Escape') close() })
        document.body.append(mask)
        requestAnimationFrame(() => mask.classList.add('show'))
    })
}

async function runOne(source, target) {
    localStorage.setItem('lr.convert.' + source.type, target)
    const info = targetsFor(source).find(t => t.id === target)
    const ext = TARGETS[target].ext
    const baseDir = source.path ? dirName(source.path) : null
    // 先选保存位置（多文件输出时选择的文件名作为前缀）
    const dest = await window.lite.savePath({
        defaultPath: (baseDir ? baseDir + '\\' : '') + stemOf(source.name) + '.' + ext,
        filters: [{ name: TARGETS[target].label, extensions: [ext.split('.').pop()] }],
    })
    if (!dest) return
    const t = toastProgress('正在转换…')
    try {
        const files = await convert(source, { target, onProgress: text => t.set(text) })
        const outDir = dirName(dest)
        const destStem = dest.replace(/^.*[\\/]/, '').replace(new RegExp(`\\.${ext.replace('.', '\\.')}$`, 'i'), '')
        const written = []
        for (const f of files) {
            // 单文件使用用户指定的名字；多文件以指定名字为前缀
            const name = files.length === 1 ? dest.replace(/^.*[\\/]/, '') : f.name.replace(stemOf(source.name), destStem)
            written.push(await window.lite.writeFile(outDir + '\\' + name, f.data))
        }
        t.done()
        const size = files.reduce((s, f) => s + (f.data.byteLength ?? f.data.size ?? 0), 0)
        const msg = `已转换为 ${TARGETS[target].label}${files.length > 1 ? `（${files.length} 个文件）` : ''} · ${formatBytes(size)}${info?.lossless ? '' : ' · 有损'}`
        toastAction(msg, '在文件夹中显示', () => window.lite.showInFolder(written[0]))
    } catch (e) {
        t.done()
        console.error(e)
        toast('转换失败：' + (e.message ?? e), 'error', 6000)
    }
}

// ---------- 批量转换页面 ----------
export class ConvertPage {
    items = []
    running = false

    constructor(app, el) {
        this.app = app
        this.el = el
    }

    render() {
        const drop = h('div.cv-drop', { onclick: () => this.addFiles() },
            icon('file-input', 34), h('div.cv-drop-title', '添加要转换的文件'), h('div.cv-drop-sub', '点击选择，或将文件拖到此处（可多选，支持混合格式）'))
        drop.addEventListener('dragover', e => { e.preventDefault(); e.stopPropagation(); drop.classList.add('over') })
        drop.addEventListener('dragleave', () => drop.classList.remove('over'))
        drop.addEventListener('drop', e => {
            e.preventDefault(); e.stopPropagation()
            drop.classList.remove('over')
            this.add([...e.dataTransfer.files].map(f => window.lite.pathForFile(f)).filter(Boolean))
        })
        this.list = h('div.cv-list')
        this.targetBox = h('div.cv-batch-targets')
        this.outDir = localStorage.getItem('lr.convert.outDir') || ''
        this.outLabel = h('span.cv-out-label', this.outDir || '与源文件相同的文件夹')
        this.runBtn = h('button.btn.primary.lg', { onclick: () => this.run() }, icon('arrow-right-left', 18), '开始转换')
        this.el.replaceChildren(h('div.home-inner.narrow',
            h('div.page-head', h('div', h('h1.page-title', '格式转换'), h('p.page-sub', '在常见文档、表格、图片、音频与压缩格式之间转换。每个目标格式都会标明是否有损，以及具体丢失的内容。'))),
            drop,
            this.list,
            h('div.set-card',
                h('div.set-card-title', icon('file-output', 16), '转换设置'),
                h('div.set-row', h('div.set-text', h('div.set-title', '目标格式'), h('div.set-desc', '按文件类型分别选择；灰色表示当前没有该类型的文件')), null),
                this.targetBox,
                h('div.set-row', h('div.set-text', h('div.set-title', '输出位置'), this.outLabel),
                    h('div.cv-out-btns',
                        h('button.btn', { onclick: () => this.pickOut() }, icon('folder', 15), '选择'),
                        h('button.btn', { onclick: () => { this.outDir = ''; localStorage.removeItem('lr.convert.outDir'); this.outLabel.textContent = '与源文件相同的文件夹' } }, '重置')))),
            h('div.cv-run', this.runBtn)))
        this.renderList()
    }

    async addFiles() {
        const files = await window.lite.openDialog({ title: '选择要转换的文件' })
        this.add(files)
    }

    async add(paths) {
        for (const p of paths ?? []) {
            if (this.items.some(i => i.path === p)) continue
            if (!typeOf(p)) { toast(`不支持的格式：${p.replace(/^.*[\\/]/, '')}`, 'warn'); continue }
            const st = await window.lite.stat(p)
            if (!st?.isFile) continue
            const source = Source.fromPath(p, st.size)
            if (!targetsFor(source).length) { toast(`${source.name} 暂不支持转换`, 'warn'); continue }
            this.items.push({ path: p, source, status: 'wait', message: '' })
        }
        this.renderList()
    }

    // 按文件类型分组选择目标格式
    renderTargets() {
        const groups = {}
        for (const it of this.items) (groups[it.source.type] ??= []).push(it)
        this.choice ??= {}
        this.targetBox.replaceChildren(...Object.entries(groups).map(([type, items]) => {
            const targets = targetsFor(items[0].source)
            const saved = this.choice[type] ?? localStorage.getItem('lr.convert.' + type)
            this.choice[type] = targets.find(t => t.id === saved)?.id ?? targets[0].id
            // 同类文件中若有任何一个有损，就标记为有损（例如 MP3 → WAV 与 FLAC → WAV 不同）
            const merged = targets.map(t => {
                const all = items.map(i => targetsFor(i.source).find(x => x.id === t.id)).filter(Boolean)
                const losses = [...new Set(all.flatMap(x => x.losses))]
                return { ...t, lossless: !losses.length, losses }
            })
            const tl = targetList(merged, this.choice[type], t => { this.choice[type] = t.id; localStorage.setItem('lr.convert.' + type, t.id) })
            return h('div.cv-group', h('div.cv-group-title', icon(TYPES[type]?.icon ?? 'file', 15), `${TYPES[type]?.name ?? type}（${items.length} 个）`), tl.el)
        }))
        if (!this.items.length) this.targetBox.append(h('div.empty-mini', '添加文件后在这里选择目标格式'))
    }

    renderList() {
        this.list.replaceChildren(...this.items.map((it, i) => h('div.cv-item.' + it.status,
            h('span.cv-item-icon', { style: { '--c': TYPES[it.source.type]?.color } }, icon(TYPES[it.source.type]?.icon ?? 'file', 17)),
            h('div.cv-item-text', h('div.cv-item-name', it.source.name), h('div.cv-item-sub', it.message || formatBytes(it.source.size))),
            it.status === 'done' && it.out ? h('button.icon-btn', { title: '在文件夹中显示', onclick: () => window.lite.showInFolder(it.out) }, icon('folder-open', 16)) : null,
            it.status === 'run' ? h('div.spinner.small') : null,
            !this.running ? h('button.icon-btn', { title: '移除', onclick: () => { this.items.splice(i, 1); this.renderList() } }, icon('x', 16)) : null)))
        this.renderTargets()
        this.runBtn.disabled = !this.items.length || this.running
    }

    async pickOut() {
        const d = await window.lite.pickFolder({ title: '选择输出文件夹' })
        if (!d) return
        this.outDir = d
        localStorage.setItem('lr.convert.outDir', d)
        this.outLabel.textContent = d
    }

    async run() {
        if (this.running) return
        this.running = true
        let ok = 0, fail = 0
        for (const it of this.items) {
            if (it.status === 'done') { ok++; continue }
            it.status = 'run'
            it.message = '正在转换…'
            this.renderList()
            const target = this.choice[it.source.type]
            try {
                const files = await convert(it.source, { target, onProgress: text => { it.message = text; this.list.querySelector('.cv-item.run .cv-item-sub')?.replaceChildren(text) } })
                const dir = this.outDir || dirName(it.path)
                let first
                for (const f of files) {
                    let dest = dir + '\\' + f.name
                    // 避免覆盖已有文件
                    for (let n = 2; await window.lite.exists(dest); n++) dest = dir + '\\' + f.name.replace(/(\.[^.]+(\.gz)?)$/, ` (${n})$1`)
                    await window.lite.writeFile(dest, f.data)
                    first ??= dest
                }
                const info = targetsFor(it.source).find(t => t.id === target)
                it.status = 'done'
                it.out = first
                it.message = `→ ${TARGETS[target].label}${files.length > 1 ? `（${files.length} 个文件）` : ''}${info?.lossless ? '' : ' · 有损'}`
                ok++
            } catch (e) {
                console.error(e)
                it.status = 'fail'
                it.message = '失败：' + (e.message ?? e)
                fail++
            }
            this.renderList()
        }
        this.running = false
        this.renderList()
        toast(fail ? `转换完成：${ok} 个成功，${fail} 个失败` : `全部转换完成（${ok} 个）`, fail ? 'warn' : 'success', 4000)
    }
}
