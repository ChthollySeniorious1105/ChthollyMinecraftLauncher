// 录制控制条：显示计时，暂停 / 停止（本窗口开启了内容保护，不会被录进视频）
import './recbar.css'

const $ = id => document.getElementById(id)
const fmt = s => { s = Math.max(0, Math.floor(s)); const p = v => String(v).padStart(2, '0'); return (s >= 3600 ? Math.floor(s / 3600) + ':' : '') + p(Math.floor(s % 3600 / 60)) + ':' + p(s % 60) }
let st = { elapsed: 0, paused: false }, at = performance.now()
window.lite.on('rec:state', v => { st = v; at = performance.now(); render() })
const render = () => {
    const t = st.paused ? st.elapsed : st.elapsed + (performance.now() - at) / 1000
    $('time').textContent = fmt(t)
    document.body.classList.toggle('paused', !!st.paused)
    $('pause').textContent = st.paused ? '▶' : '❚❚'
}
setInterval(render, 250)
$('pause').onclick = () => window.lite.capture.barCmd('pause')
$('stop').onclick = () => window.lite.capture.barCmd('stop')
