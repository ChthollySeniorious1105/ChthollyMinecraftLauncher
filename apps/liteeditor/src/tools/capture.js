// 录屏与截图（应用级工具）
// 录屏：选择屏幕 / 窗口 → 可选系统声音、麦克风、摄像头画中画、鼠标高亮 → 倒计时 → 录制（可暂停）→ 保存 / 在视频编辑器中打开
import { h, fill, toast, dialog, confirmDialog, formatTime } from '../core/dom.js'
import { icon } from '../core/icons.js'
import * as store from '../core/store.js'

// ---------- 截图 ----------
// mode: region（框选 + 标注）/ full（整个屏幕，直接打开图像编辑器）
// 完成动作：done = 复制并在图像编辑器中打开（可在设置中关闭打开）；copy；save；edit
export async function takeScreenshot(app, mode = 'region', { delay = 0 } = {}) {
    const r = await window.lite.capture.screenshot({ mode, delay })
    if (!r) return null
    const action = r.action ?? (mode === 'full' ? 'edit' : 'done')
    const name = stampName('截图', 'png')
    if (action === 'copy' || action === 'done') {
        await window.lite.capture.copyImage(r.dataURL)
        toast(`截图已复制到剪贴板（${r.width} × ${r.height}）`, 'success')
    }
    if (action === 'save') {
        const target = await window.lite.saveDialog({ title: '保存截图', defaultPath: name, filters: [{ name: 'PNG 图片', extensions: ['png'] }, { name: 'JPEG 图片', extensions: ['jpg'] }] })
        if (!target) return r
        let bytes = dataURLToBytes(r.dataURL)
        if (/\.jpe?g$/i.test(target)) bytes = await reencode(r.dataURL, 'image/jpeg')
        await window.lite.writeFile(target, bytes)
        toast('已保存：' + target.split(/[\\/]/).pop(), 'success')
    }
    if (action === 'edit' || action === 'done' && store.get('shotOpenEditor') !== false) {
        await app.openEditor('image', { name, bytes: dataURLToBytes(r.dataURL) })
    }
    return r
}

async function reencode(dataURL, mime) {
    const img = new Image()
    img.src = dataURL
    await img.decode()
    const c = h('canvas', { width: img.naturalWidth, height: img.naturalHeight })
    const g = c.getContext('2d')
    g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0)
    const blob = await new Promise(r => c.toBlob(r, mime, 0.92))
    return new Uint8Array(await blob.arrayBuffer())
}

// “截图 20260928-153000.png”
export function stampName(prefix, ext) {
    const d = new Date(), p = n => String(n).padStart(2, '0')
    return `${prefix} ${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.${ext}`
}

// 截图菜单（侧栏按钮右键 / 主页）
export const screenshotItems = app => [
    { label: '区域截图', icon: 'scissors', key: 'Ctrl+Alt+A', run: () => app.screenshot('region') },
    { label: '全屏截图', icon: 'monitor', key: 'Ctrl+Alt+F', run: () => app.screenshot('full') },
    { label: '3 秒后区域截图', icon: 'timer', run: () => app.screenshot('region', { delay: 3 }) },
    { label: '5 秒后全屏截图', icon: 'timer', run: () => app.screenshot('full', { delay: 5 }) },
    '-',
    { label: '截图后在图像编辑器中打开', checked: () => store.get('shotOpenEditor') !== false, run: () => store.set('shotOpenEditor', store.get('shotOpenEditor') === false) },
]

export function dataURLToBytes(u) {
    const b = atob(u.slice(u.indexOf(',') + 1))
    const out = new Uint8Array(b.length)
    for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i)
    return out
}

// ---------- 录屏 ----------
const pref = () => store.getPref('recorder', { area: 'source', sysAudio: true, mic: false, cam: false, cursor: true, fps: 30, quality: 'high', format: 'mp4', countdown: 3 })
const isScreen = id => id.startsWith('screen')

export class Recorder {
    constructor(app) {
        this.app = app
        this.state = 'idle'
        this.chunks = []
    }

    // 选择录制源与选项；返回 false 表示取消
    async setup() {
        const o = pref()
        const sources = await window.lite.capture.sources({ types: ['screen', 'window'] })
        if (!sources.length) { toast('没有可以录制的屏幕或窗口', 'error'); return false }
        let chosen = sources.find(s => s.id === this.sourceId)?.id ?? sources.find(s => isScreen(s.id))?.id ?? sources[0].id
        let close = null
        const grid = h('div.rec-sources')
        const areaSel = h('select.input.small', { onchange: e => { o.area = e.target.value } },
            h('option', { value: 'source', selected: o.area !== 'region' }, '整个屏幕 / 窗口'),
            h('option', { value: 'region', selected: o.area === 'region' }, '屏幕上的区域…'))
        const render = () => {
            fill(grid, sources.map(s => h('button.rec-src' + (s.id === chosen ? '.active' : ''), { onclick: () => { chosen = s.id; render() }, ondblclick: () => close?.(true), title: s.name },
                h('img', { src: s.thumb, alt: '' }),
                h('span', s.icon ? h('img.rec-icon', { src: s.icon }) : icon(isScreen(s.id) ? 'monitor' : 'app-window', 13),
                    isScreen(s.id) ? s.name.replace(/^Screen/, '屏幕').replace(/^Entire screen/i, '整个屏幕') : s.name))))
            areaSel.disabled = !isScreen(chosen)
        }
        render()
        const opt = (k, label, ic) => {
            const cb = h('input', { type: 'checkbox', checked: o[k], onchange: () => { o[k] = cb.checked } })
            return h('label.rec-opt', cb, icon(ic, 15), label)
        }
        const sel = (k, label, options) => h('label.rec-opt', label, h('select.input.small', { onchange: e => { o[k] = isNaN(+e.target.value) ? e.target.value : +e.target.value } },
            options.map(([v, l]) => h('option', { value: v, selected: v === o[k] }, l))))
        const ok = await dialog({
            title: '录制屏幕', width: 740,
            onOpen: (_m, c) => { close = c },
            body: h('div.rec-setup',
                grid,
                h('div.rec-opts',
                    h('label.rec-opt', icon('crop', 15), '录制范围', areaSel),
                    opt('sysAudio', '系统声音', 'volume-2'), opt('mic', '麦克风', 'mic'), opt('cam', '摄像头画中画', 'webcam'), opt('cursor', '鼠标指针', 'mouse-pointer-2')),
                h('div.rec-opts',
                    sel('fps', '帧率', [[15, '15'], [24, '24'], [30, '30'], [60, '60']]),
                    sel('quality', '画质', [['low', '标准'], ['high', '高'], ['max', '极高']]),
                    sel('format', '格式', [['mp4', 'MP4 (H.264)'], ['webm', 'WebM (VP9)']]),
                    sel('countdown', '倒计时', [[0, '无'], [3, '3 秒'], [5, '5 秒']])),
                h('div.form-note', '开始后主窗口会最小化，屏幕底部显示录制控制条（不会被录进视频）。Ctrl+Alt+P 暂停 / 继续，Ctrl+Alt+R 停止；录制完成后可以直接在视频剪辑中编辑。')),
            actions: [{ label: '取消', value: null }, { label: '开始录制', primary: true, value: true }],
        })
        if (!ok || !chosen) return false
        store.setPref('recorder', o)
        this.opts = { ...o, area: isScreen(chosen) ? o.area : 'source' }
        this.sourceId = chosen
        this.source = sources.find(s => s.id === chosen)
        return true
    }

    async start() {
        if (this.state !== 'idle') return
        this.state = 'setup'
        try {
            if (await this.setup()) await this.begin()
        } catch (e) {
            this.cleanup()
            this.state = 'idle'
            await window.lite.win.show()
            throw e
        } finally {
            if (this.state === 'setup') this.state = 'idle'
        }
    }

    async begin() {
        const o = this.opts
        // 区域录制：先在冻结的屏幕画面上框选
        let region = null
        if (o.area === 'region') {
            const r = await window.lite.capture.screenshot({ mode: 'rect' })
            if (!r?.rect || r.rect.w < 8 || r.rect.h < 8) { await window.lite.win.show(); return }
            region = r
            const src = (await window.lite.capture.sources({ types: ['screen'] })).find(s => String(s.display) === String(r.displayId))
            if (src) this.sourceId = src.id
        }
        await window.lite.capture.pick(this.sourceId)
        const display = await navigator.mediaDevices.getDisplayMedia({
            video: { frameRate: o.fps, cursor: o.cursor ? 'always' : 'never' },
            audio: o.sysAudio && isScreen(this.sourceId),
        }).catch(e => { throw new Error('无法获取屏幕画面：' + e.message) })
        this.streams = [display]
        let mic = null, cam = null
        if (o.mic) try { mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } }); this.streams.push(mic) } catch { toast('无法使用麦克风', 'warn') }
        if (o.cam) try { cam = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 360 } }); this.streams.push(cam) } catch { toast('无法使用摄像头', 'warn') }

        // 画面：直接使用屏幕轨道；需要裁剪区域或叠加摄像头时通过 canvas 合成
        const screenTrack = display.getVideoTracks()[0]
        const videoTrack = region || cam ? await this.compose(display, cam, region, o.fps) : screenTrack

        // 声音：系统声音 + 麦克风混音
        const ac = new AudioContext()
        this.ac = ac
        const dest = ac.createMediaStreamDestination()
        let hasAudio = false
        for (const s of [display, mic]) if (s?.getAudioTracks().length) { ac.createMediaStreamSource(s).connect(dest); hasAudio = true }
        const out = new MediaStream([videoTrack, ...(hasAudio ? dest.stream.getAudioTracks() : [])])

        // 码率按分辨率与帧率缩放
        const st = videoTrack.getSettings()
        const px = (st.width ?? 1920) * (st.height ?? 1080)
        const bps = Math.round({ low: 3, high: 6, max: 12 }[o.quality] * 1e6 * Math.max(0.35, px / (1920 * 1080)) * (o.fps >= 60 ? 1.6 : o.fps <= 15 ? 0.6 : 1))
        const want = o.format === 'mp4' ? ['video/mp4;codecs=avc1,mp4a.40.2', 'video/mp4'] : ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus']
        this.mime = [...want, 'video/webm'].find(m => MediaRecorder.isTypeSupported(m))
        this.rec = new MediaRecorder(out, { mimeType: this.mime, videoBitsPerSecond: bps, audioBitsPerSecond: 160000 })
        this.chunks = []
        this.rec.ondataavailable = e => { if (e.data.size) this.chunks.push(e.data) }
        this.rec.onstop = () => this.finish()
        // 被录制的窗口关闭 / 用户在系统中停止共享
        screenTrack.addEventListener('ended', () => this.stop())

        if (o.countdown) await this.countdown(o.countdown)
        await window.lite.win.hide()
        await sleep(200)
        this.rec.start(1000)
        this.t0 = performance.now()
        this.pausedTotal = 0
        this.duration = null
        this.state = 'recording'
        await window.lite.capture.showBar({ displayId: region?.displayId ?? this.source?.display })
        this.sync()
    }

    // 裁剪区域 / 叠加摄像头画中画，合成为一个视频轨道
    async compose(display, cam, region, fps) {
        const sv = h('video', { muted: true, playsInline: true })
        sv.srcObject = display
        await sv.play()
        let cv = null
        if (cam) { cv = h('video', { muted: true, playsInline: true }); cv.srcObject = cam; await cv.play().catch(() => {}) }
        const vw = sv.videoWidth || 1920, vh = sv.videoHeight || 1080
        // 选区为显示器 CSS 像素，换算到视频像素
        let crop = { x: 0, y: 0, w: vw, h: vh }
        if (region) {
            const r = region.rect, k = vw / region.cssWidth
            crop = { x: Math.round(r.x * k), y: Math.round(r.y * k), w: Math.round(r.w * k), h: Math.round(r.h * k) }
            crop.w = Math.min(crop.w, vw - crop.x); crop.h = Math.min(crop.h, vh - crop.y)
        }
        // 编码器要求宽高为偶数
        const c = h('canvas', { width: Math.max(2, crop.w & ~1), height: Math.max(2, crop.h & ~1) })
        const g = c.getContext('2d', { alpha: false })
        this.composing = true
        const tick = () => {
            if (!this.composing) return
            g.drawImage(sv, crop.x, crop.y, crop.w, crop.h, 0, 0, crop.w, crop.h)
            if (cv?.videoWidth) {
                const w = Math.round(c.width * 0.22), hh = Math.round(w * cv.videoHeight / cv.videoWidth), m = Math.round(c.width * 0.015)
                const x = c.width - w - m, y = c.height - hh - m
                g.save()
                g.beginPath(); g.roundRect(x, y, w, hh, 12); g.clip()
                g.drawImage(cv, x, y, w, hh)
                g.restore()
                g.strokeStyle = 'rgba(255,255,255,.9)'; g.lineWidth = 3
                g.beginPath(); g.roundRect(x, y, w, hh, 12); g.stroke()
            }
            // 主窗口最小化时 requestAnimationFrame 会停止，使用定时器驱动
            this.composeTimer = setTimeout(tick, 1000 / fps)
        }
        tick()
        return c.captureStream(fps).getVideoTracks()[0]
    }

    countdown(n) {
        return new Promise(resolve => {
            const el = h('div.rec-countdown', String(n))
            document.body.append(el)
            const t = setInterval(() => {
                n--
                if (n <= 0) { clearInterval(t); el.remove(); resolve() }
                else el.textContent = String(n)
            }, 1000)
        })
    }

    // 同步状态到标题栏与悬浮控制条
    sync() {
        this.app.setRecording(this.state === 'recording' || this.state === 'paused')
        window.lite.capture.barState({ elapsed: this.elapsed(), paused: this.state === 'paused' })
    }

    pause() {
        if (this.state === 'recording') { this.rec.pause(); this.pauseAt = performance.now(); this.state = 'paused' }
        else if (this.state === 'paused') { this.rec.resume(); this.pausedTotal += performance.now() - this.pauseAt; this.state = 'recording' }
        else return
        this.sync()
    }
    elapsed() {
        if (!this.t0) return 0
        const now = this.state === 'paused' ? this.pauseAt : performance.now()
        return (now - this.t0 - this.pausedTotal) / 1000
    }
    stop() {
        if (this.state !== 'recording' && this.state !== 'paused') return
        this.duration = this.elapsed()
        this.state = 'stopping'
        try { this.rec.stop() } catch { this.finish() }
    }

    cleanup() {
        this.composing = false
        clearTimeout(this.composeTimer)
        for (const s of this.streams ?? []) for (const t of s.getTracks()) t.stop()
        this.streams = []
        this.ac?.close().catch(() => {})
        this.ac = null
        window.lite.capture.hideBar()
    }

    async finish() {
        if (!['stopping', 'recording', 'paused'].includes(this.state)) return
        this.state = 'saving'
        this.cleanup()
        this.app.setRecording(false)
        await window.lite.win.show()
        const blob = new Blob(this.chunks, { type: this.mime.split(';')[0] })
        this.chunks = []
        const ext = this.mime.startsWith('video/mp4') ? 'mp4' : 'webm'
        const dur = this.duration ?? this.elapsed()
        this.state = 'idle'
        this.t0 = 0
        if (!blob.size) return toast('录制内容为空', 'warn')
        const name = stampName('录屏', ext)
        const r = await dialog({
            title: '录制完成', width: 460,
            body: h('div.modal-msg', `已录制 ${formatTime(dur)}，文件大小 ${(blob.size / 1048576).toFixed(1)} MB。`),
            actions: [{ label: '丢弃', danger: true, value: 'discard' }, { label: '另存为…', value: 'save' }, { label: '在视频剪辑中打开', primary: true, value: 'edit' }],
        })
        if (r === 'discard' && await confirmDialog({ title: '丢弃录制', message: '录制的视频将被删除，无法恢复。', okText: '丢弃', danger: true })) return
        const bytes = new Uint8Array(await blob.arrayBuffer())
        if (r === 'save') {
            const target = await window.lite.saveDialog({ title: '保存录屏', defaultPath: name, filters: [{ name: ext.toUpperCase() + ' 视频', extensions: [ext] }] })
            if (target) {
                await window.lite.writeFile(target, bytes)
                toast('已保存：' + target.split(/[\\/]/).pop(), 'success')
                return this.app.openPaths([target])
            }
        }
        // 选择编辑、取消保存或取消丢弃：在视频剪辑中打开（未保存，关闭时会提示）
        await this.app.openEditor('video', { name, bytes })
    }
}

const sleep = ms => new Promise(r => setTimeout(r, ms))
