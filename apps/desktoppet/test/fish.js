// play the 钓鱼 page with real input and screenshot each phase (day / dusk / night via a faked clock)
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
  const out = n => path.join(__dirname, 'out', n);
  ipcMain.emit('hub:open', {}, 'fishing');
  let hub;
  for (let i = 0; i < 40 && !hub; i++) { await wait(250); hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/')); }
  await wait(1500);
  const wc = hub.webContents, js = s => wc.executeJavaScript(s);
  const shot = async n => fs.writeFileSync(out(n), (await wc.capturePage()).toPNG());
  const hour = h => js(`(() => { const D = Date; window.Date = class extends D { constructor(...a) { super(...(a.length ? a : [])); if (!a.length) this.setHours(${h}); } }; Hub.open('fishing', true); return 1; })()`);
  const space = type => wc.sendInputEvent({ type, keyCode: 'Space' });
  const tip = () => js(`document.querySelector('.fs-tip').textContent`);

  for (const [h, tag] of [[12, 'day'], [18, 'dusk'], [22, 'night']]) {
    await hour(h); await wait(700);
    await shot(`fish-${tag}.png`);
  }
  // one full round at night
  space('keyDown'); space('keyUp');
  await wait(1000);
  await shot('fish-wait.png');
  for (let i = 0; i < 100; i++) { if ((await tip()).includes('上钩了')) break; await wait(50); }
  await shot('fish-bite.png');
  space('keyDown'); space('keyUp');
  await wait(400);
  await shot('fish-reel.png');
  let landed = false;
  for (let i = 0; i < 400; i++) {
    const s = await js(`(() => { const m = document.querySelector('.fs-meter'); if (m.classList.contains('hidden')) return null; const z = document.querySelector('.fs-zone').getBoundingClientRect(), f = document.querySelector('.fs-fishmark').getBoundingClientRect(); return (z.top + z.bottom) / 2 - (f.top + f.bottom) / 2; })()`);
    if (s === null) { landed = true; break; }
    space(s > 0 ? 'keyDown' : 'keyUp');
    await wait(30);
  }
  space('keyUp');
  await wait(350);
  await shot('fish-jump.png');
  await wait(700);
  await shot('fish-catch.png');
  console.log('landed', landed, 'tip', await tip(), 'basket', await js(`document.querySelectorAll('.fs-bk span').length`));
  await wait(3500);
  await js(`document.querySelector('.fs-dexbtn').click(); 1`);
  await wait(400);
  await shot('fish-dex.png');
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
