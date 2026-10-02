// 离线渲染 Worker：spessasynth_core 合成整首乐曲并编码为 WAV
import { SoundBankLoader, SpessaSynthProcessor, SpessaSynthSequencer, BasicMIDI, audioToWav } from 'spessasynth_core'

self.onmessage = async e => {
    const { sf, midi, sampleRate, tail } = e.data
    try {
        self.postMessage({ progress: 0, stage: 'load' })
        const bank = SoundBankLoader.fromArrayBuffer(sf)
        const synth = new SpessaSynthProcessor(sampleRate, { eventsEnabled: false, effectsEnabled: true })
        synth.soundBankManager.addSoundBank(bank, 'main')
        await synth.processorInitialized
        synth.setSystemParameter('autoAllocateVoices', true)
        const mid = BasicMIDI.fromArrayBuffer(midi)
        const seq = new SpessaSynthSequencer(synth)
        seq.skipToFirstNoteOn = false
        seq.loopCount = 0
        seq.loadNewSongList([mid])
        seq.play()
        const total = Math.ceil(sampleRate * (mid.duration + tail))
        const L = new Float32Array(total), R = new Float32Array(total)
        let done = 0, i = 0
        while (done < total) {
            seq.processTick()
            const n = Math.min(128, total - done)
            synth.process(L, R, done, n)
            done += n
            if (++i % 1500 === 0) self.postMessage({ progress: done / total, stage: 'render' })
        }
        let peak = 0
        for (let k = 0; k < total; k++) { const a = Math.abs(L[k]), b = Math.abs(R[k]); if (a > peak) peak = a; if (b > peak) peak = b }
        // 峰值过高时整体压低，避免削波；否则保持原始响度
        if (peak > 0.98) { const g = 0.98 / peak; for (let k = 0; k < total; k++) { L[k] *= g; R[k] *= g } }
        const wav = audioToWav([L, R], sampleRate, { normalizeAudio: false })
        self.postMessage({ wav, peak, duration: total / sampleRate }, [wav])
    } catch (err) {
        self.postMessage({ error: String(err?.message ?? err) })
    }
}
