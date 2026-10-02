// Smoke test: boots the real app, visits every hub page and saves screenshots to test/out.
const { app, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const out = path.join(__dirname, 'out');
fs.mkdirSync(out, { recursive: true });
const pages = (process.env.PAGES || 'bongo,home').split(',');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => {
  wc.on('console-message', (e) => { if (e.level === 'error' || e.level === 3) errors.push(`${e.message} @${e.sourceId}:${e.lineNumber}`); });
});
app.whenReady().then(async () => {
  await wait(2500);
  const pet = BrowserWindow.getAllWindows()[0];
  fs.writeFileSync(path.join(out, 'pet.png'), (await pet.webContents.capturePage()).toPNG());
  const { ipcMain } = require('electron');
  ipcMain.emit('hub:open', {}, 'home');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  for (const p of pages) {
    hub.webContents.send('hub:open', p);
    await wait(900);
    fs.writeFileSync(path.join(out, `${p}.png`), (await hub.webContents.capturePage()).toPNG());
  }
  fs.writeFileSync(path.join(out, 'errors.txt'), errors.join('\n'));
  console.log('ERRORS:\n' + errors.join('\n'));
  app.exit(0);
});
