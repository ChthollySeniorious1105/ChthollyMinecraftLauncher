// 截图与录屏冒烟测试：驱动真实的截图遮罩窗口，并录制几秒屏幕
import { BrowserWindow } from 'electron'

const overlay = async wait => {
    for (let i = 0; i < 50; i++) {
        const w = BrowserWindow.getAllWindows().find(x => x.id !== 1 && !x.isDestroyed() && x.webContents.getURL().includes('shot.html'))
        if (w?.isVisible()) return w
        await wait(100)
    }
    throw new Error('截图遮罩窗口没有出现')
}
const input = async (w, wait, events) => {
    for (const e of events) { if (w.isDestroyed()) return; w.webContents.sendInputEvent(e); await wait(20) }
}
const drag = (x1, y1, x2, y2) => [
    { type: 'mouseDown', x: x1, y: y1, button: 'left', clickCount: 1 },
    ...Array.from({ length: 8 }, (_, i) => ({ type: 'mouseMove', x: Math.round(x1 + (x2 - x1) * (i + 1) / 8), y: Math.round(y1 + (y2 - y1) * (i + 1) / 8), button: 'left' })),
    { type: 'mouseUp', x: x2, y: y2, button: 'left', clickCount: 1 },
]

export default async ({ js, shot, wait, log, outDir }) => {
    await shot('home-tools')

    // ---------- 区域截图：框选 → 矩形标注 → Enter 完成 → 在图像编辑器中打开 ----------
    await js(`window.app.screenshot('region'); return 1`)
    let ov = await overlay(wait)
    await wait(400)
    await input(ov, wait, drag(200, 150, 700, 450))
    await wait(200)
    // 选择矩形工具并画一个标注
    await ov.webContents.executeJavaScript(`document.querySelector('#bar button[title="矩形"]').click()`)
    await wait(100)
    await input(ov, wait, drag(260, 200, 480, 330))
    await wait(150)
    const img = await ov.webContents.capturePage()
    ;(await import('node:fs')).writeFileSync(outDir + '/overlay.png', img.toPNG())
    await input(ov, wait, [{ type: 'keyDown', keyCode: 'Return' }, { type: 'keyUp', keyCode: 'Return' }])
    await wait(1200)
    log('clipboard has image', await js(`const items = await navigator.clipboard.read().catch(e => []); return items.some(i => i.types.includes('image/png'))`))
    const shotInfo = await js(`const e = window.app.active?.editor; return e && { kind: e.kind, name: e.name, w: e.doc?.w, h: e.doc?.h, dirty: e.dirty }`)
    log('screenshot →', JSON.stringify(shotInfo))
    if (shotInfo?.kind !== 'image' || !(shotInfo.w > 400)) throw new Error('截图没有在图像编辑器中打开')
    if (!shotInfo.dirty) throw new Error('截图应标记为未保存')
    await shot('screenshot-in-editor')

    // ---------- Esc 取消 ----------
    await js(`window.__shot = window.app.screenshot('region').then(() => 'done'); return 1`)
    ov = await overlay(wait)
    await wait(300)
    await input(ov, wait, [{ type: 'keyDown', keyCode: 'Escape' }, { type: 'keyUp', keyCode: 'Escape' }])
    log('cancel →', await js(`return await window.__shot`))
    await js(`const t = window.app.active; await window.app.closeTab(t, { force: true }); return 1`)

    // ---------- 录屏：设置对话框 → 录制 3 秒 → 暂停 / 继续 → 停止 → 得到视频 ----------
    await js(`
        const o = { area: 'source', sysAudio: false, mic: false, cam: false, cursor: true, fps: 30, quality: 'low', format: 'mp4', countdown: 0 }
        localStorage.setItem('le.pref.recorder', JSON.stringify(o))
        window.__opened = null
        window.app.openEditor = async (kind, file) => { window.__opened = { kind, name: file.name, size: file.bytes.length, bytes: file.bytes }; return null }
        window.app.toggleRecord()
        return 1`)
    await wait(1500)
    await shot('record-setup')
    await js(`document.querySelector('.modal .btn.primary').click(); return 1`)
    await wait(1500)
    const st = await js(`return window.app.recorder.state`)
    log('state', st)
    if (st !== 'recording') throw new Error('录制没有开始：' + st)
    const bar = BrowserWindow.getAllWindows().find(x => x.webContents.getURL().includes('recbar.html'))
    log('control bar', !!bar, bar?.isVisible())
    await wait(1200)
    await js(`window.app.recorder.pause(); return 1`)
    await wait(600)
    await js(`window.app.recorder.pause(); return 1`)
    await wait(1200)
    await js(`window.app.recorder.stop(); return 1`)
    await wait(1500)
    await shot('record-done')
    await js(`[...document.querySelectorAll('.modal .btn')].find(b => b.textContent.includes('视频剪辑')).click(); return 1`)
    await wait(800)
    const rec = await js(`
        const r = window.__opened
        if (!r) return null
        return { kind: r.kind, name: r.name, size: r.size }`)
    log('recording →', JSON.stringify(rec))
    if (!rec || rec.kind !== 'video' || rec.size < 1000) throw new Error('录屏没有产生视频')
    const dur = await js(`
        const v = document.createElement('video')
        v.src = URL.createObjectURL(new Blob([window.__opened.bytes], { type: 'video/mp4' }))
        await new Promise((ok, no) => { v.onloadedmetadata = ok; v.onerror = () => no(new Error('视频无法解码')) })
        if (v.duration === Infinity) { v.currentTime = 1e9; await new Promise(r => v.ontimeupdate = r) }
        return { duration: v.duration, w: v.videoWidth, h: v.videoHeight }`)
    log('video', JSON.stringify(dur))
    if (!(dur.duration > 1.5)) throw new Error('录屏时长异常')
    log('bar closed', !BrowserWindow.getAllWindows().some(x => x.webContents.getURL().includes('recbar.html')))
}
