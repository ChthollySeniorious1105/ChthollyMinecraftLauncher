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
  ipcMain.emit('hub:open', {}, 'breakout');
  await wait(1800);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  hub.focus();
  const wc = hub.webContents;
  const js = s => wc.executeJavaScript(s);
  await js(`window.__bo = document.querySelector('.bo-root')._bo; __bo.launch(); 1`);
  const kinds = ['split', 'bomb', 'missile', 'shield', 'x2'];
  for (const k of kinds) {
    await js(`__bo.applyPower('${k}'); 1`);
    await wait(120);
    // keep the paddle under the balls so the test survives
  }
  for (let i = 0; i < 14; i++) {
    await js(`(() => { const r = document.querySelector('.bo-canvas').getBoundingClientRect(); 1 })()`);
    wc.sendInputEvent({ type: 'keyDown', keyCode: 'Space' }); await wait(20); wc.sendInputEvent({ type: 'keyUp', keyCode: 'Space' });
    await wait(300);
    if (i === 1) fs.writeFileSync(path.join(__dirname, 'out', 'breakout-play.png'), (await wc.capturePage()).toPNG());
  }
  console.log(JSON.stringify(await js('__bo.state')));
  fs.writeFileSync(path.join(__dirname, 'out', 'breakout-play2.png'), (await wc.capturePage()).toPNG());
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
