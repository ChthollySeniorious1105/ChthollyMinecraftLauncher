// 音频引擎：spessasynth_lib（AudioWorklet 合成器 + 音序器），离线渲染在 Worker 中进行
import { WorkletSynthesizer, Sequencer } from 'spessasynth_lib'
import workletURL from 'spessasynth_lib/dist/spessasynth_processor.min.js?url'

const SF_URL = './soundfonts/GeneralUserGS.sf3'
let sfPromise = null
// 音色库只下载一次，所有编辑器共享（每次使用时复制，因为会被转移给 Worklet）
export function loadSoundFont() {
    sfPromise ??= fetch(new URL(SF_URL, document.baseURI)).then(r => {
        if (!r.ok) throw new Error('无法加载音色库（' + r.status + '）')
        return r.arrayBuffer()
    }).catch(e => { sfPromise = null; throw e })
    return sfPromise
}

const waitFor = async (cond, ms = 4000) => {
    const t0 = performance.now()
    while (!cond()) {
        if (performance.now() - t0 > ms) return false
        await new Promise(r => setTimeout(r, 15))
    }
    return true
}

export class AudioEngine {
    constructor(volume = 0.8) {
        this.volume = volume
        this.valid = false
        this.ready = null
    }
    get started() { return !!this.synth }

    init() {
        this.ready ??= this._init().catch(e => { this.ready = null; throw e })
        return this.ready
    }
    async _init() {
        const ctx = this.ctx = new AudioContext({ latencyHint: 'interactive' })
        await ctx.audioWorklet.addModule(workletURL)
        if (this.dead) throw new Error('已关闭')
        this.synth = new WorkletSynthesizer(ctx)
        this.gain = ctx.createGain()
        this.gain.gain.value = this.volume
        this.synth.connect(this.gain)
        this.gain.connect(ctx.destination)
        const sf = await loadSoundFont()
        await this.synth.soundBankManager.addSoundBank(sf.slice(0), 'main')
        await this.synth.isReady
        this.seq = new Sequencer(this.synth, { skipToFirstNoteOn: false })
        this.seq.loopCount = 0
    }
    async resume() {
        await this.init()
        if (this.ctx.state !== 'running') await this.ctx.resume().catch(() => {})
    }

    setVolume(v) {
        this.volume = v
        if (this.gain) this.gain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.02)
    }

    // 载入 SMF 字节
    async load(bytes) {
        const seq = this.seq
        seq.pause()
        seq.loadNewSongList([{ binary: bytes.slice().buffer, fileName: 'song.mid' }])
        const ok = await waitFor(() => seq.midiData)
        if (!ok) throw new Error('音序器载入超时')
        this.valid = true
    }

    // 从 sec 秒开始播放
    async play(sec, loop) {
        const seq = this.seq
        seq.loopCount = loop ? Infinity : 0
        seq.currentTime = sec
        await waitFor(() => Math.abs(seq.currentTime - sec) < 0.03, 600)
        seq.play()
        this.playing = true
    }
    seek(sec) { if (this.seq) this.seq.currentTime = sec }
    setLoop(on) { if (this.seq) this.seq.loopCount = on ? Infinity : 0 }
    pause() {
        this.playing = false
        if (!this.seq) return
        this.seq.pause()
        this.synth.stopAll()
    }
    get time() { return this.seq ? this.seq.currentHighResolutionTime : 0 }
    get finished() { return !!this.seq && this.playing && this.seq.paused && this.seq.isFinished }

    // 试听：program 为音色，drum 为鼓通道
    preview(ch, pitch, vel = 100, { program, volume, ms = 360 } = {}) {
        if (!this.synth) { this.resume().catch(() => {}); return }
        if (this.ctx.state !== 'running') this.ctx.resume().catch(() => {})
        if (!this.playing) {
            if (program != null) this.synth.programChange(ch, program)
            if (volume != null) this.synth.controllerChange(ch, 7, volume)
        }
        this.synth.noteOn(ch, pitch, vel)
        if (ms) setTimeout(() => this.synth?.noteOff(ch, pitch), ms)
    }
    noteOn(ch, pitch, vel, program) {
        if (!this.synth) return
        if (!this.playing && program != null) this.synth.programChange(ch, program)
        this.synth.noteOn(ch, pitch, vel)
    }
    noteOff(ch, pitch) { this.synth?.noteOff(ch, pitch) }
    cc(ch, ctrl, v) { this.synth?.controllerChange(ch, ctrl, v) }
    program(ch, p) { this.synth?.programChange(ch, p) }

    destroy() {
        this.dead = true
        try { this.seq?.pause() } catch { /* 忽略 */ }
        try { this.synth?.stopAll(true) } catch { /* 忽略 */ }
        try { this.synth?.destroy() } catch { /* 忽略 */ }
        this.ctx?.close().catch(() => {})
        this.synth = this.seq = null
    }
}

// 离线渲染为 WAV（在 Worker 中进行，不阻塞界面）
export async function renderWAV(bytes, { sampleRate = 44100, tail = 2, onProgress } = {}) {
    const sf = await loadSoundFont()
    const worker = new Worker(new URL('./render-worker.js', import.meta.url), { type: 'module' })
    try {
        return await new Promise((resolve, reject) => {
            worker.onmessage = e => {
                const d = e.data
                if (d.progress != null) onProgress?.(d.progress, d.stage)
                else if (d.error) reject(new Error(d.error))
                else if (d.wav) resolve({ wav: new Uint8Array(d.wav), peak: d.peak, duration: d.duration })
            }
            worker.onerror = e => reject(new Error(e.message || '渲染线程出错'))
            const sfCopy = sf.slice(0), mid = bytes.slice().buffer
            worker.postMessage({ sf: sfCopy, midi: mid, sampleRate, tail }, [sfCopy, mid])
        })
    } finally { worker.terminate() }
}
