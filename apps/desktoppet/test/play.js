// exercise 每日任务 / 外出探险 / 钓鱼 end-to-end and screenshot the pages
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
  const shot = async (w, n) => fs.writeFileSync(out(n), (await w.webContents.capturePage()).toPNG());
  let st = sync('play:get');
  if (st.trip) { skew += 5 * 3600e3; sync('play:claim'); }
  console.log('QUESTS', JSON.stringify(st.quests.list.map(q => `${q.key}:${q.prog}/${q.n}`)));
  for (const k of ['wins', 'pomos', 'feeds', 'pets', 'feeds', 'pets', 'pets']) ipcMain.emit('stats:bump', {}, k);
  st = sync('play:get');
  console.log('AFTER', JSON.stringify(st.quests.list.map(q => `${q.key}:${q.prog}/${q.n}${q.done ? '✔' : ''}`)), 'bonus', st.quests.bonus);

  // make sure the pet has energy
  const careBefore = sync('care:get');
  console.log('care', careBefore.level, Math.round(careBefore.energy), careBefore.coins);
  console.log('trip', JSON.stringify(sync('play:trip', 'park')));
  console.log('trip again', JSON.stringify(sync('play:trip', 'beach')));
  console.log('rest while away', JSON.stringify(sync('care:action', 'rest').msg));
  ipcMain.emit('hub:open', {}, 'adventure');
  await wait(2000);
  const hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/'));
  const pet = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/pet/'));
  await hub.webContents.executeJavaScript(`Hub.open('adventure', true); 1`);
  await wait(600);
  await shot(hub, 'adv-away.png');
  await shot(pet, 'pet-away.png');
  console.log('claim early', JSON.stringify(sync('play:claim')));
  // fast forward past the trip end and let the tick announce it
  skew += 16 * 60e3;
  for (const w of [hub, pet]) await w.webContents.executeJavaScript(`(() => { const n = Date.now; Date.now = () => n() + ${skew}; })(); 1`).catch(e => console.log('inject fail', w.webContents.getURL(), e.message));
  await wait(31000);
  await hub.webContents.executeJavaScript(`Hub.open('adventure', true); 1`);
  await wait(600);
  await shot(hub, 'adv-back.png');
  await shot(pet, 'pet-back.png');
  console.log('state before claim', JSON.stringify(sync('play:get').trip));
  await hub.webContents.executeJavaScript(`(b => b ? (b.click(), 1) : 0)(document.querySelector('.adv-claim'))`).then(v => v || console.log('already claimed'));
  await wait(500);
  await shot(hub, 'adv-claim.png');
  st = sync('play:get');
  console.log('souvenirs', JSON.stringify(st.souvenirs), 'trip', st.trip);

  // fishing: simulate a full catch loop in the page
  await hub.webContents.executeJavaScript(`Hub.open('fishing', true); 1`);
  await wait(800);
  await shot(hub, 'fish-idle.png');
  const r = sync('play:fish', { id: 'koi', rarity: 3, size: 55.2, coins: 20 });
  console.log('fish', r.ok, r.coins, r.isNew, r.left);
  const big = sync('play:fish', { id: 'x', rarity: 1, size: 1, coins: 9999 });
  console.log('fish capped coins', big.coins);
  // play one round with the real UI: cast, wait for bite, hook, hold
  const wc = hub.webContents;
  wc.sendInputEvent({ type: 'keyDown', keyCode: 'Space' }); wc.sendInputEvent({ type: 'keyUp', keyCode: 'Space' });
  await wait(900);
  await shot(hub, 'fish-wait.png');
  let tip = '';
  for (let i = 0; i < 80; i++) { tip = await wc.executeJavaScript(`document.querySelector('.fs-tip').textContent`); if (tip.includes('上钩了')) break; await wait(100); }
  wc.sendInputEvent({ type: 'keyDown', keyCode: 'Space' }); wc.sendInputEvent({ type: 'keyUp', keyCode: 'Space' });
  await wait(300);
  await shot(hub, 'fish-reel.png');
  // auto-reel: keep the zone on the fish
  for (let i = 0; i < 300; i++) {
    const s = await wc.executeJavaScript(`(() => { const m = document.querySelector('.fs-meter'); if (m.classList.contains('hidden')) return null; const z = document.querySelector('.fs-zone').getBoundingClientRect(), f = document.querySelector('.fs-fishmark').getBoundingClientRect(); return (z.top + z.bottom) / 2 - (f.top + f.bottom) / 2; })()`);
    if (s === null) break;
    wc.sendInputEvent({ type: s > 0 ? 'keyDown' : 'keyUp', keyCode: 'Space' });
    await wait(30);
  }
  wc.sendInputEvent({ type: 'keyUp', keyCode: 'Space' });
  await wait(200);
  await shot(hub, 'fish-catch.png');
  console.log('tip', await wc.executeJavaScript(`document.querySelector('.fs-tip').textContent`));
  await wc.executeJavaScript(`document.querySelector('.fs-dexbtn').click(); 1`);
  await wait(300);
  await shot(hub, 'fish-dex.png');
  await wc.executeJavaScript(`Hub.open('achievements', true); 1`);
  await wait(600);
  await shot(hub, 'ach-new.png');
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
