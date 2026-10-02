// 编辑器类型与文件格式
// exts: 可以打开的扩展名；native: 可直接保存（Ctrl+S）而不丢失信息的扩展名
export const KINDS = {
    image: {
        name: '图像', full: '图像编辑', icon: 'image', color: '#06b6d4',
        desc: '图层 · 选区 · 画笔 · 滤镜 · 调色',
        exts: ['psd', 'png', 'jpg', 'jpeg', 'jfif', 'webp', 'bmp', 'gif', 'avif', 'ico', 'svg'],
        native: ['psd'],
    },
    geo: {
        name: '几何', full: '几何画板', icon: 'triangle-right', color: '#8b5cf6',
        desc: '尺规作图 · 圆锥曲线 · 方程 · 函数图像',
        exts: ['lgeo'],
        native: ['lgeo'],
    },
    doc: {
        name: '文档', full: '文字处理', icon: 'file-type', color: '#2563eb',
        desc: 'DOCX · LaTeX · Markdown · 公式 · 表格',
        exts: ['docx', 'ldoc', 'tex', 'latex', 'ltx', 'md', 'markdown', 'html', 'htm', 'txt', 'rtf'],
        native: ['ldoc', 'docx', 'tex', 'latex', 'ltx', 'html', 'htm', 'md', 'markdown'],
    },
    sheet: {
        name: '表格', full: '电子表格', icon: 'sheet', color: '#16a34a',
        desc: 'XLSX · CSV · 公式 · 图表 · 排序筛选',
        exts: ['lsheet', 'xlsx', 'xlsm', 'xls', 'ods', 'csv', 'tsv'],
        native: ['lsheet', 'xlsx', 'ods'],
    },
    slides: {
        name: '演示', full: '演示文稿', icon: 'presentation', color: '#ea580c',
        desc: 'PPTX · 形状 · 动画切换 · 放映',
        exts: ['lslide', 'pptx'],
        native: ['lslide'],
    },
    video: {
        name: '视频', full: '视频剪辑', icon: 'clapperboard', color: '#e11d48',
        desc: '剪切 · 拼接 · 字幕 · 转场 · 导出 MP4',
        exts: ['lvideo', 'mp4', 'm4v', 'webm', 'mkv', 'mov', 'mp3', 'wav', 'ogg', 'oga', 'opus', 'flac', 'm4a', 'aac'],
        native: ['lvideo'],
    },
    midi: {
        name: '音乐', full: 'MIDI 编曲', icon: 'music', color: '#d946ef',
        desc: '钢琴卷帘 · 多轨 · 音色 · 导出 WAV',
        exts: ['mid', 'midi', 'rmi', 'kar'],
        native: ['mid', 'midi'],
    },
}

export const extOf = name => {
    const i = name.lastIndexOf('.')
    return i >= 0 ? name.slice(i + 1).toLowerCase() : ''
}
export const baseName = p => p.split(/[\\/]/).pop()
export const dirName = p => p.replace(/[\\/][^\\/]*$/, '')
export const stemOf = name => name.replace(/\.[^.]+$/, '')

export function kindOf(name) {
    const ext = extOf(name)
    for (const [k, t] of Object.entries(KINDS)) if (t.exts.includes(ext)) return k
    return null
}

export const allExts = () => Object.values(KINDS).flatMap(t => t.exts)

export const dialogFilters = () => [
    { name: '所有支持的文件', extensions: allExts() },
    ...Object.values(KINDS).map(t => ({ name: t.full, extensions: t.exts })),
    { name: '所有文件', extensions: ['*'] },
]

export const mediaURL = path => 'media://file/' + encodeURIComponent(path)

export const MIME = {
    png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', jfif: 'image/jpeg', webp: 'image/webp',
    bmp: 'image/bmp', gif: 'image/gif', avif: 'image/avif', ico: 'image/x-icon', svg: 'image/svg+xml',
    mp4: 'video/mp4', m4v: 'video/mp4', webm: 'video/webm', mkv: 'video/x-matroska', mov: 'video/quicktime',
    mp3: 'audio/mpeg', wav: 'audio/wav', ogg: 'audio/ogg', oga: 'audio/ogg', opus: 'audio/ogg', flac: 'audio/flac', m4a: 'audio/mp4', aac: 'audio/aac',
    mid: 'audio/midi', midi: 'audio/midi',
}

// Uint8Array / ArrayBuffer / string 之间的转换
export const toBytes = data => typeof data === 'string' ? new TextEncoder().encode(data)
    : data instanceof Uint8Array ? data : new Uint8Array(data)
export const bytesToText = bytes => new TextDecoder().decode(bytes)

export function bytesToDataURL(bytes, mime) {
    let s = ''
    const chunk = 0x8000
    for (let i = 0; i < bytes.length; i += chunk) s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk))
    return `data:${mime};base64,${btoa(s)}`
}

export async function blobToDataURL(blob) {
    return new Promise((resolve, reject) => {
        const r = new FileReader()
        r.onload = () => resolve(r.result)
        r.onerror = reject
        r.readAsDataURL(blob)
    })
}

// 让用户选择一张本地图片，返回 { dataURL, name, width, height } 或 null
export async function pickImage() {
    const [p] = await window.lite.openDialog({
        title: '插入图片', multi: false,
        filters: [{ name: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'svg', 'avif'] }],
    })
    if (!p) return null
    const bytes = await window.lite.readFile(p)
    const dataURL = bytesToDataURL(bytes, MIME[extOf(p)] ?? 'image/png')
    const img = await loadImage(dataURL)
    return { dataURL, name: baseName(p), width: img.naturalWidth, height: img.naturalHeight, img }
}

export const loadImage = src => new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('图片解码失败'))
    img.src = src
})
