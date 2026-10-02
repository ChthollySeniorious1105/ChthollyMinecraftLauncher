const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
app.whenReady().then(async () => {
  await wait(2500);
  const pet = BrowserWindow.getAllWindows().find(w => w.getBounds().width < 600);
  console.log('start', JSON.stringify(pet.getBounds()));
  ipcMain.emit('settings:update', {}, { walk: true });
  for (let i = 0; i < 5; i++) { await wait(1000); console.log('t' + i, JSON.stringify(pet.getBounds())); }
  const e = {}; ipcMain.emit('ach:get', e);
  console.log('walker ach', e.returnValue.list.find(a => a.id === 'walker').at > 0);
  ipcMain.emit('settings:update', {}, { walk: false });
  await wait(500);
  const b = pet.getBounds(); await wait(800);
  console.log('stopped', JSON.stringify(b) === JSON.stringify(pet.getBounds()));
  app.exit(0);
});
