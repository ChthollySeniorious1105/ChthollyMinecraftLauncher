// 文件类型识别与文件源抽象
export const TYPES = {
    ebook: { name: '电子书', icon: 'book-open', color: '#8b5cf6', exts: ['epub', 'mobi', 'azw3', 'azw', 'kf8', 'prc', 'fb2', 'fbz', 'cbz'] },
    pdf: { name: 'PDF', icon: 'file-text', color: '#ef4444', exts: ['pdf'] },
    docx: { name: 'Word', icon: 'file-type', color: '#2563eb', exts: ['docx', 'docm', 'dotx'] },
    doc: { name: 'Word 97', icon: 'file-type', color: '#3b82f6', exts: ['doc', 'dot'] },
    slides: { name: '演示文稿', icon: 'presentation', color: '#ea580c', exts: ['pptx', 'pptm', 'ppsx', 'ppsm', 'potx', 'potm', 'ppt', 'pps', 'pot', 'odp', 'otp'] },
    rich: { name: '富文本', icon: 'file-text', color: '#0284c7', exts: ['rtf', 'odt', 'ott'] },
    paged: { name: '版式文档', icon: 'file-scan', color: '#b91c1c', exts: ['ofd', 'xps', 'oxps', 'djvu', 'djv'] },
    chm: { name: '帮助文档', icon: 'book-marked', color: '#7c3aed', exts: ['chm'] },
    web: { name: '网页', icon: 'globe', color: '#0ea5e9', exts: ['html', 'htm', 'xhtml', 'xht', 'shtml', 'mht', 'mhtml'] },
    tex: { name: 'LaTeX', icon: 'sigma', color: '#0d9488', exts: ['tex', 'latex', 'ltx'] },
    sheet: { name: '表格', icon: 'file-spreadsheet', color: '#16a34a', exts: ['xlsx', 'xlsm', 'xlsb', 'xls', 'ods', 'csv', 'tsv', 'numbers'] },
    text: { name: '文本', icon: 'scroll-text', color: '#f59e0b', exts: ['txt', 'md', 'markdown', 'log', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'cfg', 'toml', 'js', 'mjs', 'ts', 'css', 'py', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'sh', 'bat', 'ps1', 'sql', 'sty', 'cls', 'bib', 'lrc', 'srt', 'vtt', 'nfo', 'php', 'rb', 'kt', 'swift', 'lua', 'r', 'vue', 'jsx', 'tsx', 'scss', 'less', 'dart', 'pl'] },
    audio: { name: '音乐', icon: 'music', color: '#ec4899', exts: ['mp3', 'ogg', 'oga', 'opus', 'wav', 'flac', 'm4a', 'aac', 'weba', 'mid', 'midi', 'rmi', 'kar'] },
    image: { name: '图片', icon: 'image', color: '#06b6d4', exts: ['png', 'jpg', 'jpeg', 'jfif', 'bmp', 'gif', 'webp', 'avif', 'svg', 'ico', 'apng'] },
    archive: { name: '压缩包', icon: 'file-archive', color: '#d97706', exts: ['zip', '7z', 'rar', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'cbr', 'cb7', 'cbt', 'lzh', 'iso', 'cab'] },
    video: { name: '视频', icon: 'film', color: '#f43f5e', exts: ['mp4', 'm4v', 'webm', 'mkv', 'mov', 'ogv', '3gp'] },
}

export const MIDI_EXTS = ['mid', 'midi', 'rmi', 'kar']

export const extOf = name => {
    const n = name.toLowerCase()
    if (n.endsWith('.fb2.zip')) return 'fbz'
    if (n.endsWith('.tar.gz')) return 'tgz'
    const i = n.lastIndexOf('.')
    return i >= 0 ? n.slice(i + 1) : ''
}
export const baseName = p => p.split(/[\\/]/).pop()
export const dirName = p => p.replace(/[\\/][^\\/]*$/, '')
export const stemOf = name => name.replace(/\.[^.]+$/, '')

export function typeOf(name) {
    const ext = extOf(name)
    for (const [k, t] of Object.entries(TYPES)) if (t.exts.includes(ext)) return k
    return null
}

export const allExts = () => Object.values(TYPES).flatMap(t => t.exts)

export const dialogFilters = () => [
    { name: '所有支持的文件', extensions: allExts() },
    ...Object.values(TYPES).map(t => ({ name: t.name, extensions: t.exts })),
    { name: '所有文件', extensions: ['*'] },
]

export const mediaURL = path => 'media://file/' + encodeURIComponent(path)
// 保留目录层级的本地文件地址，便于网页 / LaTeX 中的相对路径资源解析
export const localURL = path => 'media://local/' + path.replace(/\\/g, '/').split('/').filter(Boolean).map(encodeURIComponent).join('/')
export const localDirURL = path => localURL(dirName(path)) + '/'

// 文件源：可以来自磁盘路径，也可以来自压缩包中的 Blob
export class Source {
    constructor({ name, path = null, blob = null, size = 0, parent = null }) {
        this.name = name
        this.path = path
        this._blob = blob
        this.size = blob?.size ?? size
        this.parent = parent // 来自压缩包时记录压缩包名
        this.ext = extOf(name)
        this.type = typeOf(name)
        this._url = null
    }
    static fromPath(path, size) {
        return new Source({ name: baseName(path), path, size })
    }
    static fromBlob(blob, name, parent) {
        return new Source({ name, blob, parent })
    }
    get key() { return this.path ?? (this.parent ? `${this.parent}::${this.name}` : null) }
    get isLocal() { return !!this.path }
    url() {
        if (this.path) return mediaURL(this.path)
        this._url ??= URL.createObjectURL(this._blob)
        return this._url
    }
    async blob() {
        if (this._blob) return this._blob
        const res = await fetch(this.url())
        if (!res.ok) throw new Error(`无法读取文件（${res.status}）`)
        this._blob = await res.blob()
        this.size = this._blob.size
        return this._blob
    }
    async file() {
        const b = await this.blob()
        return b instanceof File && b.name === this.name ? b : new File([b], this.name, { type: b.type })
    }
    async arrayBuffer() { return (await this.blob()).arrayBuffer() }
    release() {
        if (this._url) URL.revokeObjectURL(this._url)
        this._url = null
        if (this.path) this._blob = null
    }
}

// 同目录下同类文件（用于图片 / 音乐 / 视频的上一张、下一首）
export async function siblings(source, type) {
    if (!source.path || !window.lite) return [source]
    const files = await window.lite.listDir(dirName(source.path))
    const list = files.filter(f => typeOf(f.name) === type).map(f => Source.fromPath(f.path, f.size))
    return list.length ? list : [source]
}
