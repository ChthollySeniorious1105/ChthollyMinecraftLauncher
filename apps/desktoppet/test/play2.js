const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const out = path.join(__dirname, 'out');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error') errors.push(e.message); }));
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'gomoku');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.isResizable());
  hub.focus();
  const wc = hub.webContents;
  const click = async (x, y, n = 1) => { for (let i = 1; i <= n; i++) { wc.sendInputEvent({ type: 'mouseDown', x, y, button: 'left', clickCount: i }); await wait(30); wc.sendInputEvent({ type: 'mouseUp', x, y, button: 'left', clickCount: i }); await wait(40); } };
  const rect = sel => wc.executeJavaScript(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; })()`);
  const shot = async n => fs.writeFileSync(path.join(out, n + '.png'), (await wc.capturePage()).toPNG());

  let r = await rect('.gk-root canvas');
  const cell = r.w / 16.5;
  for (const [i, j] of [[7, 7], [6, 8], [8, 6], [7, 5]]) {
    await click(Math.round(r.x + r.w / 2 + (i - 7) * (r.w - 2 * cell * 0.9) / 16), Math.round(r.y + r.h / 2 + (j - 7) * (r.w - 2 * cell * 0.9) / 16));
    await wait(900);
  }
  await shot('play-gomoku');

  wc.send('hub:open', 'memory'); await wait(900);
  const cards = await wc.executeJavaScript(`[...document.querySelectorAll('.mm-root [data-i], .mm-root .mm-card, .memory-root .card')].slice(0,3).map(e => { const r = e.getBoundingClientRect(); return [r.left + r.width/2, r.top + r.height/2]; })`);
  console.log('memory cards', cards.length);
  for (const [x, y] of cards.slice(0, 2)) { await click(Math.round(x), Math.round(y)); await wait(150); }
  await wait(250);
  await shot('play-memory');

  wc.send('hub:open', 'solitaire'); await wait(900);
  r = await rect('.sol-root .sol-slot-stock');
  console.log('stock', JSON.stringify(r));
  if (r) { await click(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2)); await wait(300); await click(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2)); await wait(400); }
  await shot('play-solitaire');

  wc.send('hub:open', 'sudoku'); await wait(900);
  const empty = await wc.executeJavaScript(`(() => { const c = [...document.querySelectorAll('.sd-root [data-i], .sudoku-root .cell, .sd-cell')].find(e => !e.textContent.trim()); if (!c) return null; const r = c.getBoundingClientRect(); return [r.left + r.width/2, r.top + r.height/2]; })()`);
  console.log('sudoku empty', JSON.stringify(empty));
  if (empty) { await click(Math.round(empty[0]), Math.round(empty[1])); wc.sendInputEvent({ type: 'char', keyCode: '5' }); wc.sendInputEvent({ type: 'keyDown', keyCode: '5' }); wc.sendInputEvent({ type: 'keyUp', keyCode: '5' }); await wait(400); }
  await shot('play-sudoku');
  console.log('ERRORS:\n' + errors.join('\n'));
  app.exit(0);
});
