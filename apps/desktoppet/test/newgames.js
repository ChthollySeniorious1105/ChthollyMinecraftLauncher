// open the new mini-games, drive them a little and screenshot them
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error' || e.level === 'warning') errors.push(e.message); }));
const only = (process.argv.find(a => a.startsWith('--games=')) || '--games=connect4,match3,typing,point24').slice(8).split(',');
const js = (wc, s) => wc.executeJavaScript(s);
const key = (wc, keyCode, type) => { for (const t of type ? [type] : ['keyDown', 'char', 'keyUp']) wc.sendInputEvent({ type: t, keyCode }); };
const SCRIPTS = {
  // start, then make a few valid swaps found by scanning the board DOM positions
  match3: async (wc, shot) => {
    await wait(700);
    await js(wc, `document.querySelector('.m3-go').click(); 1`);
    await wait(900);
    await shot('match3.png');
    let made = 0;
    for (let i = 0; i < 6; i++) {
      await wait(1200);
      const ok = await js(wc, `(() => { const h = document.querySelectorAll('.m3-tile.hint'); document.querySelector('.m3-hintbtn').click(); const t = [...document.querySelectorAll('.m3-tile.hint')]; if (t.length !== 2) return false; for (const el of t) { const r = el.getBoundingClientRect(); const box = document.querySelector('.m3-tiles'); box.dispatchEvent(new PointerEvent('pointerdown', { clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true })); } return true; })()`);
      if (ok) made++;
    }
    await wait(1500);
    await shot('match3-play.png');
    console.log('match3 swaps', made, 'score', await js(wc, `document.querySelector('.m3-score').textContent`));
  },
  // type words: read the lowest word and type it
  typing: async (wc, shot) => {
    await shot('typing.png');
    key(wc, 'Enter', 'keyDown');
    await wait(2500);
    for (let i = 0; i < 14; i++) {
      const w = await js(wc, `(() => { const ws = [...document.querySelectorAll('.tp-word:not(.miss)')]; if (!ws.length) return ''; ws.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top); return ws[0].textContent; })()`);
      if (w) for (const ch of w) { key(wc, ch.toUpperCase(), 'keyDown'); await wait(35); }
      await wait(500);
      if (i === 6) await shot('typing-play.png');
    }
    console.log('typing score', await js(wc, `document.querySelector('.tp-score').textContent`), 'wpm', await js(wc, `document.querySelector('.tp-wpm').textContent`), 'acc', await js(wc, `document.querySelector('.tp-acc').textContent`));
  },
  // solve the hand through the UI using the hint text steps is hard; use the answer display then an exact merge sequence
  point24: async (wc, shot) => {
    await shot('point24.png');
    await js(wc, `document.querySelector('.p24-card').click(); document.querySelector('.p24-op[data-op="+"]').click(); document.querySelectorAll('.p24-card')[1].click(); 1`);
    await wait(400);
    await shot('point24-merge.png');
    await js(wc, `document.querySelector('.p24-hint').click(); 1`);
    await wait(200);
    console.log('point24 hint:', await js(wc, `document.querySelector('.p24-msg').textContent`));
    await js(wc, `document.querySelector('.p24-show').click(); 1`);
    await wait(200);
    await shot('point24-answer.png');
    console.log('point24 answer:', await js(wc, `document.querySelector('.p24-msg').textContent`));
  },
  // play a full game vs the normal AI by clicking random legal columns; report timing of AI replies
  connect4: async (wc, shot) => {
    await shot('connect4.png');
    for (let i = 0; i < 25; i++) {
      const done = await wc.executeJavaScript(`(() => { if (!document.querySelector('.c4-ov').classList.contains('hidden')) return 'over'; const cols = [...document.querySelectorAll('.c4-col:not(.full)')]; if (!cols.length) return 'full'; cols[(Math.random() * cols.length) | 0].click(); return ''; })()`);
      if (done) break;
      await wait(1200);
    }
    await wait(1200);
    await shot('connect4-end.png');
    console.log('connect4 status:', await wc.executeJavaScript(`document.querySelector('.c4-status span').textContent`));
  }
};
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'home');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/'));
  const wc = hub.webContents;
  for (const id of only) {
    await wc.executeJavaScript(`Hub.open(${JSON.stringify(id)}, true); 1`);
    await wait(900);
    const ok = await wc.executeJavaScript(`!!document.querySelector('#content > .page').children.length`);
    console.log('mounted', id, ok);
    const shot = async n => fs.writeFileSync(path.join(__dirname, 'out', n), (await wc.capturePage()).toPNG());
    if (SCRIPTS[id]) await SCRIPTS[id](wc, shot).catch(e => console.log('script fail', id, e.message));
    else await shot(id + '.png');
  }
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
