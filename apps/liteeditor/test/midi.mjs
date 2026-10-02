// MIDI 编曲冒烟测试
const TMP = process.cwd().replace(/\\/g, '/') + '/.tmp'

export default async ({ theme, js, shot, wait, drag, click, key, log }) => {
    // 1. 示例乐曲
    await js(`await window.app.newDoc('midi', { sample: 'demo' })`)
    await wait(900)
    const info = await js(`const e = window.app.active.editor; return { tracks: e.song.tracks.length, notes: e.song.tracks.reduce((s, t) => s + t.notes.length, 0), track: e.track.name, grid: [e.grid.w, e.grid.h] }`)
    log('demo', JSON.stringify(info))
    if (info.tracks !== 4 || info.notes < 100) throw new Error('示例乐曲应有 4 条轨道')
    if (info.grid[0] < 300 || info.grid[1] < 200) throw new Error('钢琴卷帘尺寸异常')
    await shot('demo')

    // 2. 画笔添加音符
    const before = await js(`return window.app.active.editor.track.notes.length`)
    await js(`const e = window.app.active.editor; e.setTool('draw'); e.centerPitch(64); e.drawRoll()`)
    const pt = await js(`const e = window.app.active.editor, r = e.grid.c.getBoundingClientRect()
        const tick = e.song.ppq * 4 * 2 + e.song.ppq, p = 60
        return { x: r.left + e.xOf(tick) + 3, y: r.top + e.yOf(p) + e.view.rowH / 2, x2: r.left + e.xOf(tick + e.song.ppq * 2) }`)
    await drag(pt.x, pt.y, pt.x2, pt.y, 6)
    const added = await js(`const e = window.app.active.editor; const n = e.selNotes()[0]; return { count: e.track.notes.length, n: n && { tick: n.tick, dur: n.dur, pitch: n.pitch } }`)
    log('added', JSON.stringify(added))
    if (added.count !== before + 1 || added.n.pitch !== 60) throw new Error('画笔添加音符失败')
    // 3. 选择工具拖动音符（向上 2 个半音、向右 1 拍）
    await js(`window.app.active.editor.setTool('select')`)
    const mv = await js(`const e = window.app.active.editor, r = e.grid.c.getBoundingClientRect(), n = e.selNotes()[0]
        return { x: r.left + e.xOf(n.tick) + 8, y: r.top + e.yOf(n.pitch) + e.view.rowH / 2, dx: e.song.ppq * e.view.zx, dy: e.view.rowH * 2 }`)
    await drag(mv.x, mv.y, mv.x + mv.dx, mv.y - mv.dy, 8)
    const moved = await js(`const n = window.app.active.editor.selNotes()[0]; return { tick: n.tick, pitch: n.pitch, dur: n.dur }`)
    log('moved', JSON.stringify(moved))
    if (moved.pitch !== 62 || moved.tick !== added.n.tick + 480) throw new Error('拖动音符失败')
    // 4. 移调快捷键 / 撤销
    await key('Up')
    const tr = await js(`return window.app.active.editor.selNotes()[0].pitch`)
    if (tr !== 63) throw new Error('移调失败：' + tr)
    await key('z', ['control'])
    await key('z', ['control'])
    const undone = await js(`const e = window.app.active.editor, n = e.track.notes.find(n => n.tick === ${added.n.tick} && n.pitch === 60); return { count: e.track.notes.length, back: !!n }`)
    log('undo', JSON.stringify(undone))
    if (!undone.back) throw new Error('撤销移动失败')
    // 全选 + 复制粘贴
    await js(`const e = window.app.active.editor; e.selectAll(); e.copySel(); e.cursor = e.song.ppq * 4 * 8; e.paste()`)
    const pasted = await js(`return window.app.active.editor.track.notes.length`)
    log('pasted', pasted)
    if (pasted !== undone.count * 2) throw new Error('粘贴失败')
    await js(`window.app.active.editor.undo()`)
    // 量化
    await js(`const e = window.app.active.editor; e.track.notes[0].tick += 37; e.selectNone(); e.quantize({ grid: 1 / 16 })`)
    const q = await js(`const e = window.app.active.editor; return e.track.notes.every(n => n.tick % 120 === 0)`)
    if (!q) throw new Error('量化失败')
    await shot('edited')

    // 5. 鼓轨道
    await js(`const e = window.app.active.editor; e.selectTrack(e.song.tracks[3].id)`)
    await wait(300)
    await shot('drums')

    // 6. 保存 .mid 并重新打开
    const path = TMP + '/midi-demo.mid'
    const saved = await js(`const e = window.app.active.editor; await e.writeTo(${JSON.stringify(path)}); return { notes: e.song.tracks.reduce((s, t) => s + t.notes.length, 0), dirty: e.dirty }`)
    log('saved', JSON.stringify(saved))
    await js(`await window.app.openPaths([${JSON.stringify(path)}])`)
    await wait(600)
    const reopened = await js(`const e = window.app.active.editor; return { name: e.name, tracks: e.song.tracks.length, notes: e.song.tracks.reduce((s, t) => s + t.notes.length, 0), bpm: e.song.tempos[0].bpm, progs: e.song.tracks.map(t => t.program) }`)
    log('reopened', JSON.stringify(reopened))
    // 同一路径已打开：openPaths 会激活现有标签，因此用字节解析验证
    const rt = await js(`const bytes = await window.lite.readFile(${JSON.stringify(path)})
        const ed = await window.app.openEditor('midi', { name: 'rt.mid', bytes })
        return { notes: ed.song.tracks.reduce((s, t) => s + t.notes.length, 0), tracks: ed.song.tracks.length, progs: ed.song.tracks.map(t => t.program), bpm: ed.song.tempos[0].bpm }`)
    log('roundtrip', JSON.stringify(rt))
    if (rt.notes !== saved.notes) throw new Error(`往返音符数不一致：${rt.notes} vs ${saved.notes}`)

    // 7. 播放
    await js(`const e = window.app.active.editor; await e.play()`)
    await wait(2500)
    const pb = await js(`const e = window.app.active.editor; return { playing: e.playing, state: e.engine.ctx?.state, tick: Math.round(e.playTick), voices: e.engine.synth?.voiceCount }`)
    log('playback', JSON.stringify(pb))
    await shot('playing')
    if (!pb.playing || pb.tick <= 0) throw new Error('播放未开始')
    await js(`window.app.active.editor.pause()`)

    // 8. 导出 WAV
    const wav = await js(`const e = window.app.active.editor; const d = await e.exportWAV(); await window.lite.writeFile(${JSON.stringify(TMP + '/midi-demo.wav')}, d); return { bytes: d.length, ...e.lastRender }`)
    log('wav', JSON.stringify(wav))
    if (!wav.peak || wav.peak < 0.01) throw new Error('WAV 为静音')

    // 9. 空白 + 乐队模板 + 浅色主题
    await js(`await window.app.newDoc('midi', { sample: 'band' })`)
    await wait(500)
    await shot('band')
    await js(`await window.app.newDoc('midi', {})`)
    await wait(400)
    await shot('blank')
    await theme('dark')
    await wait(700)
    await js(`const e = window.app.active.editor; await window.app.newDoc('midi', { sample: 'demo' })`)
    await wait(700)
    await js(`const e = window.app.active.editor; e.selectAll()`)
    await shot('demo-dark')
    await js(`const e = window.app.active.editor; e.selectTrack(e.song.tracks[3].id)`)
    await shot('drums-dark')
}
