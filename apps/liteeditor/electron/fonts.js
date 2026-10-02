// 字体：解析 TTF / OTF / TTC / WOFF 的 name 表；扫描系统字体；管理用户导入的字体（userData/fonts）
import { app, ipcMain } from 'electron'
import path from 'node:path'
import fsp from 'node:fs/promises'
import os from 'node:os'
import zlib from 'node:zlib'

export const FONT_EXT = /\.(ttf|otf|ttc|otc|woff|woff2)$/i
export const fontDir = () => path.join(app.getPath('userData'), 'fonts')

async function readAt(fh, pos, len) {
    const b = Buffer.alloc(len)
    const { bytesRead } = await fh.read(b, 0, len, pos)
    return b.subarray(0, bytesRead)
}
const utf16 = b => {
    const c = Buffer.from(b)
    c.swap16()
    return c.toString('utf16le')
}
// 简体中文优先，其次繁体 / 其他中文地区
const ZH_LANGS = [0x0804, 0x1004, 0x0404, 0x0c04, 0x1404]

// 从 name 表提取家族名：en 用作 CSS 字体名，zh 用于界面显示
function parseName(t) {
    if (t.length < 6) return null
    const count = t.readUInt16BE(2), strOff = t.readUInt16BE(4)
    const ids = {}
    for (let i = 0; i < count; i++) {
        const r = 6 + i * 12
        if (r + 12 > t.length) break
        const pid = t.readUInt16BE(r), eid = t.readUInt16BE(r + 2), lang = t.readUInt16BE(r + 4), nid = t.readUInt16BE(r + 6)
        const len = t.readUInt16BE(r + 8), off = strOff + t.readUInt16BE(r + 10)
        if (![1, 2, 16, 17].includes(nid) || off + len > t.length) continue
        let s
        if (pid === 3 || pid === 0) s = utf16(t.subarray(off, off + len))
        else if (pid === 1 && eid === 0) s = t.toString('latin1', off, off + len)
        else continue
        s = s.replace(/\0/g, '').trim()
        if (!s) continue
        const slot = ids[nid] ??= {}
        if (pid === 3 && lang === 0x0409) slot.en ??= s
        const zi = pid === 3 ? ZH_LANGS.indexOf(lang) : -1
        if (zi >= 0 && (slot.zhRank == null || zi < slot.zhRank)) { slot.zh = s; slot.zhRank = zi }
        slot.any ??= s
    }
    const fam = ids[16] ?? ids[1]
    const sub = ids[17] ?? ids[2]
    if (!fam) return null
    return { family: fam.en ?? fam.any, label: fam.zh ?? fam.en ?? fam.any, sub: sub?.en ?? sub?.any ?? '' }
}

// OS/2 表：字重与是否倾斜
function parseOS2(t) {
    if (!t || t.length < 64) return {}
    return { weight: t.readUInt16BE(4), italic: !!(t.readUInt16BE(62) & 1) }
}

// 读取 sfnt（base 为该字体在文件中的偏移，TTC 中的子字体）
async function sfntInfo(fh, base) {
    const head = await readAt(fh, base, 12)
    if (head.length < 12) return null
    const n = head.readUInt16BE(4)
    const dir = await readAt(fh, base + 12, n * 16)
    const tables = {}
    for (let p = 0; p + 16 <= dir.length; p += 16) {
        tables[dir.toString('latin1', p, p + 4)] = { off: dir.readUInt32BE(p + 8), len: dir.readUInt32BE(p + 12) }
    }
    if (!tables.name) return null
    const name = parseName(await readAt(fh, tables.name.off, Math.min(tables.name.len, 1 << 20)))
    if (!name) return null
    const os2 = tables['OS/2'] ? parseOS2(await readAt(fh, tables['OS/2'].off, Math.min(tables['OS/2'].len, 128))) : {}
    return { ...name, ...os2 }
}

// WOFF：表可能经过 zlib 压缩
async function woffInfo(fh) {
    const head = await readAt(fh, 0, 44)
    const n = head.readUInt16BE(12)
    const dir = await readAt(fh, 44, n * 20)
    const table = async tag => {
        for (let p = 0; p + 20 <= dir.length; p += 20) {
            if (dir.toString('latin1', p, p + 4) !== tag) continue
            const off = dir.readUInt32BE(p + 4), comp = dir.readUInt32BE(p + 8), orig = dir.readUInt32BE(p + 12)
            const raw = await readAt(fh, off, comp)
            return comp < orig ? zlib.inflateSync(raw) : raw
        }
        return null
    }
    const nt = await table('name')
    const name = nt && parseName(nt)
    return name ? { ...name, ...parseOS2(await table('OS/2')) } : null
}

export async function fontInfo(file) {
    let fh
    try {
        fh = await fsp.open(file, 'r')
        const sig = await readAt(fh, 0, 16)
        const tag = sig.toString('latin1', 0, 4)
        let info = null
        // TTC 集合：取第一个子字体
        if (tag === 'ttcf') info = await sfntInfo(fh, sig.readUInt32BE(12))
        else if (tag === 'wOFF') info = await woffInfo(fh)
        else if (tag !== 'wOF2') info = await sfntInfo(fh, 0)
        // WOFF2 的表经过 Brotli 与变换编码，直接用文件名作为字体名
        if (!info) {
            const stem = path.basename(file).replace(/\.[^.]+$/, '')
            info = { family: stem, label: stem, sub: '' }
        }
        return info
    } catch {
        return null
    } finally {
        await fh?.close()
    }
}

// ---------- 系统字体 ----------
function systemDirs() {
    const home = os.homedir()
    if (process.platform === 'win32') return [
        path.join(process.env.WINDIR ?? 'C:\\Windows', 'Fonts'),
        path.join(process.env.LOCALAPPDATA ?? path.join(home, 'AppData', 'Local'), 'Microsoft', 'Windows', 'Fonts'),
    ]
    if (process.platform === 'darwin') return ['/System/Library/Fonts', '/Library/Fonts', path.join(home, 'Library', 'Fonts')]
    return ['/usr/share/fonts', '/usr/local/share/fonts', path.join(home, '.local', 'share', 'fonts'), path.join(home, '.fonts')]
}

async function walk(dir, depth, out) {
    let ents
    try { ents = await fsp.readdir(dir, { withFileTypes: true }) } catch { return }
    for (const e of ents) {
        const p = path.join(dir, e.name)
        if (e.isDirectory()) { if (depth > 0) await walk(p, depth - 1, out) }
        else if (FONT_EXT.test(e.name)) out.push(p)
    }
}

let systemCache = null
export function systemFonts() {
    systemCache ??= (async () => {
        const files = []
        for (const d of systemDirs()) await walk(d, 3, files)
        const byFamily = new Map()
        // 分批并发读取，几百个字体文件通常在一秒内完成
        for (let i = 0; i < files.length; i += 32) {
            const infos = await Promise.all(files.slice(i, i + 32).map(fontInfo))
            for (const f of infos) {
                if (!f || f.family.startsWith('@') || f.family.startsWith('.')) continue
                const key = f.family.toLowerCase()
                const cur = byFamily.get(key)
                if (!cur || (cur.label === cur.family && f.label !== f.family)) byFamily.set(key, { family: f.family, label: f.label })
            }
        }
        return [...byFamily.values()].sort((a, b) => a.label.localeCompare(b.label, 'zh-CN'))
    })()
    return systemCache
}

// ---------- 用户字体 ----------
export async function userFonts() {
    const dir = fontDir()
    let names = []
    try { names = (await fsp.readdir(dir)).filter(n => FONT_EXT.test(n)) } catch { /* 目录尚不存在 */ }
    const list = []
    for (const file of names) {
        const p = path.join(dir, file)
        const [info, st] = await Promise.all([fontInfo(p), fsp.stat(p).catch(() => null)])
        if (!info || !st) continue
        list.push({
            file, path: p, size: st.size, family: info.family, label: info.label, sub: info.sub,
            weight: info.weight || (/bold/i.test(info.sub) ? 700 : 400),
            style: info.italic || /italic|oblique/i.test(info.sub) ? 'italic' : 'normal',
        })
    }
    return list.sort((a, b) => a.label.localeCompare(b.label, 'zh-CN') || a.weight - b.weight)
}

// 打印 / 导出 PDF 窗口中使用的 @font-face 规则
export async function userFontCSS() {
    const q = s => s.replace(/["\\]/g, '\\$&')
    return (await userFonts()).map(f => `@font-face{font-family:"${q(f.family)}";src:url("app://local/__fonts/${encodeURIComponent(f.file)}");font-weight:${f.weight};font-style:${f.style};font-display:block}`).join('\n')
}

export function registerFonts() {
    ipcMain.handle('fonts:list', async () => ({ dir: fontDir(), fonts: await userFonts() }))
    ipcMain.handle('fonts:system', () => systemFonts())
    ipcMain.handle('fonts:import', async (_e, paths) => {
        const dir = fontDir()
        await fsp.mkdir(dir, { recursive: true })
        const added = [], failed = []
        for (const src of paths ?? []) {
            const name = path.basename(src)
            if (!FONT_EXT.test(name) || !(await fontInfo(src))) { failed.push(name); continue }
            try {
                const dest = path.join(dir, name)
                if (path.resolve(src).toLowerCase() !== dest.toLowerCase()) await fsp.copyFile(src, dest)
                added.push(name)
            } catch { failed.push(name) }
        }
        return { added, failed, fonts: await userFonts() }
    })
    ipcMain.handle('fonts:remove', async (_e, file) => {
        await fsp.rm(path.join(fontDir(), path.basename(file)), { force: true })
        return userFonts()
    })
}
