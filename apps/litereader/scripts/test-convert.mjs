// 格式转换 / 导出 PDF 端到端测试：在真实 Electron 窗口中执行转换，检查输出文件
// 用法：npx vite build && npx electron scripts/test-convert.mjs
import { app } from 'electron'
import path from 'node:path'
import fs from 'node:fs'

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..')
const S = p => path.join(root, 'samples', p)
const out = path.join(root, 'test-output', 'convert')
try { fs.rmSync(out, { recursive: true, force: true }) } catch { /* 目录被占用时直接覆盖 */ }
fs.mkdirSync(out, { recursive: true })
process.argv.splice(2)

// [源文件, 目标格式]
const ONLY = process.env.ONLY
const CASES_ALL = [
    ['readme.md', 'html'], ['readme.md', 'pdf'], ['readme.md', 'docx'], ['readme.md', 'txt'], ['readme.md', 'epub'],
    ['formats/math.md', 'pdf'], ['formats/code.py', 'pdf'], ['novel_gbk.txt', 'epub'],
    ['document.docx', 'pdf'], ['document.docx', 'md'], ['document.docx', 'html'],
    ['legacy.doc', 'docx'], ['formats/document.rtf', 'docx'], ['formats/document.odt', 'pdf'], ['formats/document.odt', 'md'],
    ['page.html', 'pdf'], ['archive.mht', 'html'], ['paper.tex', 'pdf'], ['paper.tex', 'docx'], ['paper.tex', 'md'], ['thesis/main.tex', 'pdf'],
    ['book.epub', 'pdf'], ['book.epub', 'txt'], ['book.mobi', 'epub'], ['formats/help.chm', 'epub'],
    ['document.pdf', 'png'], ['document.pdf', 'txt'], ['document.pdf', 'docx'], ['slides.pptx', 'pdf'], ['slides.pptx', 'png'],
    ['formats/legacy.ppt', 'pdf'], ['formats/slides.odp', 'txt'], ['formats/document.ofd', 'pdf'], ['formats/document.xps', 'png'], ['formats/sample.djvu', 'pdf'],
    ['images/sample_1.png', 'jpg'], ['images/sample_2.jpg', 'webp'], ['images/sample_4.bmp', 'png'], ['images/sample_5.png', 'bmp'], ['images/sample_3.jpeg', 'pdf'],
    ['sheet.xlsx', 'csv'], ['sheet.xlsx', 'ods'], ['sheet.xlsx', 'xls'], ['sheet.xlsx', 'json'], ['sheet.xlsx', 'pdf'],
    ['song_c.wav', 'mp3'], ['song_b.ogg', 'wav'], ['melody.mid', 'wav'],
    ['gallery.zip', '7z'], ['gallery.7z', 'zip'], ['test-v5.rar', 'tgz'],
]
const CASES = ONLY ? CASES_ALL.filter(([f]) => f.includes(ONLY)) : CASES_ALL
const MAGIC = {
    pdf: b => b.subarray(0, 5).toString() === '%PDF-',
    docx: b => b[0] === 0x50 && b[1] === 0x4b, epub: b => b[0] === 0x50 && b.subarray(30, 58).toString() === 'mimetypeapplication/epub+zip',
    ods: b => b[0] === 0x50 && b[1] === 0x4b, zip: b => b[0] === 0x50 && b[1] === 0x4b,
    xls: b => b.readUInt32BE(0) === 0xd0cf11e0, png: b => b.readUInt32BE(0) === 0x89504e47, jpg: b => b[0] === 0xff && b[1] === 0xd8,
    webp: b => b.subarray(8, 12).toString() === 'WEBP', bmp: b => b.subarray(0, 2).toString() === 'BM',
    wav: b => b.subarray(0, 4).toString() === 'RIFF', mp3: b => b[0] === 0xff && (b[1] & 0xe0) === 0xe0 || b.subarray(0, 3).toString() === 'ID3',
    '7z': b => b.subarray(0, 2).toString() === '7z', tgz: b => b[0] === 0x1f && b[1] === 0x8b,
    html: b => /<!DOCTYPE html>/i.test(b.subarray(0, 200).toString()), md: b => b.length > 10, txt: b => b.length > 3,
    csv: b => b.length > 3, json: b => { try { JSON.parse(b.toString()); return true } catch { return false } },
}

let hooked = false
app.on('browser-window-created', (_e, win) => {
    // 只接管主窗口（打印 / 截图用的隐藏窗口也会触发此事件）
    if (hooked) return
    hooked = true
    win.webContents.on('console-message', e => { if (e.level === 'error') console.log('  [renderer]', e.message.slice(0, 300)) })
    win.webContents.once('did-finish-load', async () => {
        await new Promise(r => setTimeout(r, 800))
        let pass = 0, fail = 0
        for (const [file, target] of CASES) {
            const src = S(file)
            const t0 = Date.now()
            const res = await win.webContents.executeJavaScript(`window.__convertTest(${JSON.stringify(src)}, ${JSON.stringify(target)}, ${JSON.stringify(out)})`).catch(e => ({ error: String(e.message ?? e) }))
            const ms = Date.now() - t0
            if (res?.error) { fail++; console.log(`FAIL ${file} → ${target}  ${res.error}`); continue }
            const checks = res.files.map(f => {
                const b = fs.readFileSync(f)
                const ext = target === 'tgz' ? 'tgz' : target
                return { f: path.basename(f), size: b.length, ok: b.length > 0 && (MAGIC[ext]?.(b) ?? true) }
            })
            const ok = checks.length && checks.every(c => c.ok)
            ok ? pass++ : fail++
            console.log(`${ok ? 'PASS' : 'FAIL'} ${file} → ${target}  ${checks.map(c => `${c.f} ${(c.size / 1024).toFixed(1)}KB`).slice(0, 3).join(', ')}${checks.length > 3 ? ` …共 ${checks.length} 个` : ''}  ${res.lossless ? '无损' : '有损(' + res.losses.length + ')'}  ${ms}ms`)
        }
        console.log(`\n结果：${pass} 通过，${fail} 失败`)
        app.quit()
    })
})

await import('../electron/main.js')
