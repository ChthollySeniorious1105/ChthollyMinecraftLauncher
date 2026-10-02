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
  ipcMain.emit('hub:open', {}, 'pinball');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  hub.focus();
  const wc = hub.webContents;
  const js = s => wc.executeJavaScript(s);
  const key = (k, type) => wc.sendInputEvent({ type, keyCode: k });
  await js(`document.querySelector('.pb-go').click(); 1`);
  await wait(300);
  key('Space', 'keyDown'); await wait(700); key('Space', 'keyUp');
  // keep flipping for a while
  for (let i = 0; i < 40; i++) {
    const hot = await js(`(() => { const s = document.querySelector('.pb-root')._pb.sim; return s.balls.map(b => [b.x, b.y, b.vy]); })()`);
    const l = hot.some(([x, y, vy]) => y > 520 && x < 210 && vy > 0), r = hot.some(([x, y, vy]) => y > 520 && x >= 210 && vy > 0);
    key('Z', l ? 'keyDown' : 'keyUp'); key('Right', r ? 'keyDown' : 'keyUp');
    if (i === 12) fs.writeFileSync(path.join(__dirname, 'out', 'pinball.png'), (await wc.capturePage()).toPNG());
    await wait(80);
  }
  console.log('score', await js(`document.querySelector('.pb-root')._pb.score`), await js(`document.querySelector('.pb-ball').textContent`));
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
