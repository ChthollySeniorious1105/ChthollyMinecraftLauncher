export default async ({ js, log }) => {
    log(JSON.stringify(await js(`
        const out = {}
        for (const codec of ['avc1.640028', 'avc1.42E01F', 'vp09.00.10.08', 'vp8', 'av01.0.04M.08', 'hvc1.1.6.L93.B0']) {
            try { out[codec] = (await VideoEncoder.isConfigSupported({ codec, width: 1280, height: 720, bitrate: 4e6, framerate: 30 })).supported } catch (e) { out[codec] = 'err ' + e.message }
        }
        for (const codec of ['mp4a.40.2', 'opus']) {
            try { out[codec] = (await AudioEncoder.isConfigSupported({ codec, sampleRate: 48000, numberOfChannels: 2, bitrate: 128000 })).supported } catch (e) { out[codec] = 'err ' + e.message }
        }
        out.mr = ['video/mp4;codecs=avc1,mp4a.40.2', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=h264', 'video/mp4'].map(t => t + '=' + MediaRecorder.isTypeSupported(t))
        return out`)))
}
