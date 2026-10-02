// exercise 宠物花园 / 扭蛋机 / 接食物 and screenshot the pages
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error' || e.level === 'warning') errors.push(e.message); }));
const sync = (ch, ...a) => { const e = {}; ipcMain.emit(ch, e, ...a); return e.returnValue; };
const realNow = Date.now;
let skew = 0;
Date.now = () => realNow() + skew;
app.whenReady().then(async () => {
  await wait(2000);
  const out = n => path.join(__dirname, 'out', n);
  ipcMain.emit('care:reward', {}, 100, '测试');
  ipcMain.emit('care:reward', {}, 100, '测试');
  // garden: plant everything plantable, water half, fast-forward
  let r = sync('play:garden', 'unlock');
  console.log('unlock', r.ok, r.msg || '');
  const g0 = sync('play:get').garden;
  for (let i = 0; i < g0.plots.length; i++) if (!g0.plots[i]) console.log('plant', i, sync('play:garden', 'plant', { i, crop: ['radish', 'carrot', 'tomato', 'corn', 'strawberry'][i % 5] }).ok);
  console.log('water', JSON.stringify(sync('play:garden', 'water', 0).n), sync('play:garden', 'water', 1).ok);
  skew += 10 * 60e3;
  let g = sync('play:get').garden;
  console.log('after 10 min', g.plots.map(p => p && `${p.crop}:${p.pct.toFixed(2)}${p.ripe ? '✔' : ''}${p.wet ? '💧' : ''}`).join(' '));
  r = sync('play:garden', 'harvest', -1);
  console.log('harvest', r.ok, r.coins, JSON.stringify(r.got));
  sync('play:garden', 'plant', { i: 0, crop: 'radish' });
  skew += 16 * 60e3;

  ipcMain.emit('hub:open', {}, 'garden');
  let hub;
  for (let i = 0; i < 40 && !hub; i++) { await wait(250); hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/')); }
  await wait(1500);
  const wc = hub.webContents, js = s => wc.executeJavaScript(s);
  await js(`(() => { const n = Date.now; Date.now = () => n() + ${skew}; Hub.open('garden', true); return 1; })()`);
  const shot = async n => fs.writeFileSync(out(n), (await wc.capturePage()).toPNG());
  await wait(700);
  await shot('garden.png');
  await js(`document.querySelectorAll('.gd-plot.empty')[0] && document.querySelectorAll('.gd-plot.empty')[0].click(); 1`);
  await wait(400);
  await shot('garden-pick.png');
  await js(`document.querySelector('.gd-pick').classList.add('hidden'); document.querySelector('.gd-harvall').click(); 1`);
  await wait(250);
  await shot('garden-harvest.png');

  // gacha
  await js(`Hub.open('gacha', true); 1`);
  await wait(600);
  await shot('gacha.png');
  await js(`document.querySelector('.gc-spin').click(); 1`);
  await wait(900);
  await shot('gacha-spin.png');
  await wait(1100);
  await shot('gacha-reveal.png');
  await js(`document.querySelector('.gc-ok').click(); 1`);
  for (let i = 0; i < 12; i++) { const x = sync('play:gacha'); if (!x.ok) { console.log('gacha stop', x.msg); break; } }
  const gs = sync('play:get').gacha;
  console.log('gacha owned', Object.keys(gs.owned).length, 'pity', gs.pity, 'free', gs.free);
  await js(`Hub.open('gacha', true); 1`);
  await wait(500);
  await shot('gacha-shelf.png');

  // catch game: start and follow the nearest food with the mouse
  await js(`Hub.open('catch', true); 1`);
  await wait(500);
  await shot('catch.png');
  hub.focus();
  await js(`document.querySelector('.cc-go').click(); 1`);
  // chase the lowest falling food with the mouse, pixel coordinates from the canvas rect
  for (let i = 0; i < 90; i++) {
    const p = await js(`(() => { const r = document.querySelector('.cc-canvas').getBoundingClientRect(); return { x: r.left + r.width * (0.2 + 0.6 * Math.abs(Math.sin(${i} / 6))), y: r.top + r.height / 2 }; })()`);
    wc.sendInputEvent({ type: 'mouseMove', x: Math.round(p.x), y: Math.round(p.y) });
    await wait(80);
  }
  await shot('catch-play.png');
  for (let i = 0; i < 900; i++) { if (await js(`!document.querySelector('.cc-ov').classList.contains('hidden')`)) break; await wait(100); }
  await wait(300);
  await shot('catch-over.png');
  console.log('catch', await js(`document.querySelector('.cc-sub').textContent`));
  await js(`Hub.open('achievements', true); 1`);
  await wait(500);
  await shot('ach-v2.png');
  console.log('ach', sync('ach:get').list.filter(a => a.at).map(a => a.id).join(','));
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
