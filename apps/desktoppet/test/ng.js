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
  ipcMain.emit('hub:open', {}, 'nonogram');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  const wc = hub.webContents;
  const js = s => wc.executeJavaScript(s);
  const shot = n => wc.capturePage().then(i => fs.writeFileSync(path.join(__dirname, 'out', n + '.png'), i.toPNG()));
  await shot('ng-select');
  // open the first 5x5 puzzle and solve it by clicking cells using the hint button repeatedly
  await js(`document.querySelector('.ng-card').click(); 1`);
  await wait(500);
  await shot('ng-play');
  for (let i = 0; i < 60; i++) {
    const done = await js(`!document.querySelector('.ng-winbar').classList.contains('hidden')`);
    if (done) break;
    await js(`document.querySelector('.ng-hint').click(); 1`);
    await wait(60);
  }
  await wait(900);
  await shot('ng-win');
  console.log('win bar:', await js(`document.querySelector('.ng-win-name').textContent + document.querySelector('.ng-win-sub').textContent`));
  // pet puzzle
  await js(`document.querySelector('.ng-back2').click(); 1`);
  await wait(300);
  await js(`document.querySelector('[data-tab=pet]').click(); 1`);
  await wait(300);
  await js(`document.querySelector('.ng-card').click(); 1`);
  await wait(1500);
  await shot('ng-pet');
  console.log('pet title:', await js(`document.querySelector('.ng-title').textContent`));
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
