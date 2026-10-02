// screenshots of the line-art Bongo Cat boards (overlay + settings preview)
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
  const find = () => BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/bongo/'));
  for (const mode of ['lkeys', 'ldesk', 'lbongo', 'ltable']) {
    ipcMain.emit('bongo:update', {}, { mode, scale: 1, opacity: 1 });
    if (!find()) ipcMain.emit('bongo:toggle', {});
    await wait(1200);
    const wc = find().webContents;
    // white backdrop so the transparent board is visible in the png
    await wc.executeJavaScript(`document.body.style.background = '#e9eef3'; 1`);
    wc.send('bongo:key', { down: true, code: 30 });
    wc.send('bongo:mouse', { down: true, button: 2 });
    wc.send('bongo:move', { x: 0.8, y: 0.3 });
    await wait(60);
    fs.writeFileSync(path.join(__dirname, 'out', `line-${mode}-hit.png`), (await wc.capturePage()).toPNG());
    wc.send('bongo:key', { down: false, code: 30 });
    wc.send('bongo:mouse', { down: false, button: 2 });
    await wait(300);
    fs.writeFileSync(path.join(__dirname, 'out', `line-${mode}-idle.png`), (await wc.capturePage()).toPNG());
  }
  ipcMain.emit('hub:open', {}, 'bongo');
  await wait(1800);
  const hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/'));
  fs.writeFileSync(path.join(__dirname, 'out', 'line-hub.png'), (await hub.webContents.capturePage()).toPNG());
  ipcMain.emit('bongo:update', {}, { mode: 'cat' });
  ipcMain.emit('bongo:toggle', {});
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
