const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
app.whenReady().then(async () => {
  await wait(2500);
  const call = (ch, ...a) => { const e = {}; ipcMain.emit(ch, e, ...a); return e.returnValue; };
  ipcMain.emit('care:reward', {}, 100, '测试'); ipcMain.emit('care:reward', {}, 100, '测试'); ipcMain.emit('care:reward', {}, 100, '测试');
  for (const id of ['crown', 'sunglasses', 'scarf']) console.log(id, call('care:action', 'wear-buy', id).ok);
  const pet = BrowserWindow.getAllWindows().find(w => w.getBounds().width < 600);
  for (const p of ['01-fox.png', '04-rabbit.png', '06-penguin.png', '19-turtle.png']) {
    ipcMain.emit('settings:update', {}, { pet: p });
    await wait(900);
    fs.writeFileSync(path.join(__dirname, 'out', 'wear-' + p), (await pet.webContents.capturePage()).toPNG());
  }
  console.log('ach', call('ach:get').list.filter(a => a.at).map(a => a.name).join(','));
  app.exit(0);
});
