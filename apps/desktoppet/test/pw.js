// screenshots of the password generator page (both modes, wide + narrow)
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
  ipcMain.emit('hub:open', {}, 'passgen');
  await wait(1800);
  const hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/'));
  const wc = hub.webContents;
  const shot = async n => fs.writeFileSync(path.join(__dirname, 'out', n), (await wc.capturePage()).toPNG());
  await shot('passgen.png');
  await wc.executeJavaScript(`document.querySelector('.pw-modes [data-m=words]').click(); document.querySelector('.pw-copy').click(); 1`);
  await wait(300);
  await shot('passgen-words.png');
  await wc.executeJavaScript(`document.querySelector('.pw-modes [data-m=chars]').click(); 1`);
  const b = hub.getBounds();
  hub.setBounds({ x: b.x, y: b.y, width: 820, height: b.height });
  await wait(500);
  await shot('passgen-narrow.png');
  hub.setBounds(b);
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
