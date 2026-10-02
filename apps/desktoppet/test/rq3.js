// Plays the riichi table through the real UI: clicks / drags tiles, presses call buttons, advances results.
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error' || e.level === 'warning') errors.push(e.message + ' @' + e.lineNumber); }));
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'riichi');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  hub.focus();
  const wc = hub.webContents;
  const js = s => wc.executeJavaScript(s);
  const shot = n => wc.capturePage().then(i => fs.writeFileSync(path.join(__dirname, 'out', n + '.png'), i.toPNG()));
  const click = async (x, y) => { wc.sendInputEvent({ type: 'mouseDown', x, y, button: 'left', clickCount: 1 }); await wait(40); wc.sendInputEvent({ type: 'mouseUp', x, y, button: 'left', clickCount: 1 }); };
  const P = Number(process.env.P || 4);
  if (P === 3) { await js(`document.querySelector('.rq-seg[data-k=players] [data-v="3"]').click(); 1`); await wait(200); }
  await js(`document.querySelector('.rq-start').click(); 1`);
  await wait(1500);
  const shots = { hover: 0, call: 0, result: 0, riichi: 0 };
  let discards = 0, drags = 0, results = 0, calls = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < Number(process.env.SECS || 60) * 1000) {
    await wait(220);
    const st = await js(`(() => {
      const res = document.querySelector('.rq-result:not(.rq-hidden)');
      if (res) { const b = res.querySelector('.rq-ok'); if (b) return { res: 'ok' }; if (res.querySelector('[data-e]')) return { res: 'end' }; return { res: 'wait' }; }
      const cbs = [...document.querySelectorAll('.rq-callbar .rq-cb')].map(b => b.textContent.trim());
      const mine = [...document.querySelectorAll('.rq-self .rq-mine')].map(t => { const r = t.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2, t.classList.contains('rq-drawn')]; });
      return { cbs, mine };
    })()`);
    if (st.res === 'ok') {
      if (shots.result++ < 2) { await wait(1800); await shot('rq3-result' + shots.result); }
      await js(`document.querySelector('.rq-result .rq-ok').click(); 1`); results++; continue;
    }
    if (st.res === 'end') { await shot('rq3-end'); break; }
    if (st.res) continue;
    const cb = st.cbs || [];
    if (cb.some(t => /自摸|荣和/.test(t))) { await js(`[...document.querySelectorAll('.rq-callbar .rq-cb')].find(b => /自摸|荣和/.test(b.textContent)).click(); 1`); continue; }
    if (cb.some(t => /碰|吃/.test(t))) {
      if (shots.call++ < 1) await shot('rq3-callbar');
      calls++;
      await js(`[...document.querySelectorAll('.rq-callbar .rq-cb')].find(b => /跳过/.test(b.textContent)).click(); 1`);
      continue;
    }
    if (cb.some(t => /立直/.test(t)) && shots.riichi++ < 1) {
      await js(`document.querySelector('.rq-cb-riichi').click(); 1`);
      await wait(150);
      await shot('rq3-riichi-mode');
      await js(`document.querySelector('.rq-cb-riichi').click(); 1`);
    }
    if (cb.some(t => /跳过/.test(t))) { await js(`[...document.querySelectorAll('.rq-callbar .rq-cb')].find(b => /跳过/.test(b.textContent)).click(); 1`); continue; }
    const mine = st.mine || [];
    if (mine.length % 3 === 2) {
      const [x, y] = (mine.find(m => m[2]) || mine[mine.length - 1]);
      if (shots.hover++ < 1) {
        const [hx, hy] = mine[Math.floor(mine.length / 2)];
        wc.sendInputEvent({ type: 'mouseMove', x: Math.round(hx), y: Math.round(hy) });
        await wait(250);
        await shot('rq3-hover');
      }
      if (discards % 4 === 1) {
        // drag the tile upward to throw it
        wc.sendInputEvent({ type: 'mouseDown', x: Math.round(x), y: Math.round(y), button: 'left', clickCount: 1 });
        for (let k = 1; k <= 6; k++) { await wait(16); wc.sendInputEvent({ type: 'mouseMove', x: Math.round(x), y: Math.round(y - k * 18), button: 'left' }); }
        wc.sendInputEvent({ type: 'mouseUp', x: Math.round(x), y: Math.round(y - 108), button: 'left', clickCount: 1 });
        drags++;
      } else await click(Math.round(x), Math.round(y));
      discards++;
      if (discards === 6) { await wait(80); await shot('rq3-flight'); }
    }
  }
  await shot('rq3-last');
  console.log({ discards, drags, calls, results });
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
