const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
app.whenReady().then(async () => {
  await wait(2500);
  const pet = BrowserWindow.getAllWindows().find(w => w.getBounds().width < 600);
  const b0 = pet.getBounds();
  // fast upward-left drag, then release
  for (let i = 0; i < 6; i++) { ipcMain.emit('pet:drag', {}, -40, -60); await wait(12); }
  ipcMain.emit('pet:dragEnd', {});
  const ys = [];
  for (let i = 0; i < 40; i++) { await wait(100); const b = pet.getBounds(); ys.push(b.x + ',' + b.y); }
  console.log('start', b0.x, b0.y);
  console.log('path', ys.filter((_, i) => i % 4 === 0).join(' | '));
  const e = {}; ipcMain.emit('ach:get', e);
  console.log('flings', e.returnValue.stats.flings || 0);
  app.exit(0);
});
