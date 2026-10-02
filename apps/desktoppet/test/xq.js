const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error' || e.level === 'warning') errors.push(e.message); }));
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'xiangqi');
  await wait(2000);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  const wc = hub.webContents;
  const click = async (x, y) => { wc.sendInputEvent({ type: 'mouseDown', x, y, button: 'left', clickCount: 1 }); await wait(30); wc.sendInputEvent({ type: 'mouseUp', x, y, button: 'left', clickCount: 1 }); await wait(80); };
  const r = await wc.executeJavaScript(`(() => { const c = document.querySelector('.xq-board').getBoundingClientRect(); return { x: c.left, y: c.top }; })()`);
  const at = (col, row) => [Math.round(r.x + 40 + col * 52), Math.round(r.y + 40 + row * 52)];
  // red cannon (col 7,row 7) to centre file: 炮二平五
  await click(...at(7, 7)); await click(...at(4, 7));
  await wait(3500);
  const st = await wc.executeJavaScript(`[document.querySelector('.xq-status').textContent, [...document.querySelectorAll('.xq-moves li')].map(l => l.textContent).join('|'), typeof Worker]`);
  console.log(JSON.stringify(st));
  fs.writeFileSync(path.join(__dirname, 'out', 'xiangqi.png'), (await wc.capturePage()).toPNG());
  console.log('ERRORS:', errors.join('\n'));
  app.exit(0);
});
