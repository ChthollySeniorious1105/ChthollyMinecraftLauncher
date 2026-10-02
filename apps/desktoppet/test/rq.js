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
  ipcMain.emit('hub:open', {}, 'riichi');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.getBounds().width > 600);
  hub.focus();
  const wc = hub.webContents;
  const js = s => wc.executeJavaScript(s);
  const shot = n => wc.capturePage().then(i => fs.writeFileSync(path.join(__dirname, 'out', n + '.png'), i.toPNG()));
  await shot('rq-lobby');
  const P = Number(process.env.P || 4);
  if (P === 3) { await js(`document.querySelector('.rq-seg[data-k=players] [data-v="3"]').click(); 1`); await wait(200); }
  await js(`document.querySelector('.rq-start').click(); 1`);
  // play automatically by clicking: discard the drawn tile, press pass/next buttons, accept wins
  let shots = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < Number(process.env.SECS || 40) * 1000) {
    await wait(250);
    const st = await js(`(() => {
      const pop = document.querySelector('.rq-popup:not(.rq-hidden)');
      if (pop) { const b = pop.querySelector('.rq-next, [data-e=lobby]'); if (b && b.dataset.e === 'lobby') return 'end'; if (b) { b.click(); return 'next'; } }
      const acts = [...document.querySelectorAll('.rq-actions button')];
      const win = acts.find(b => /自摸|荣和/.test(b.textContent));
      if (win) { win.click(); return 'win'; }
      const ri = acts.find(b => b.textContent === '立直');
      const pass = acts.find(b => b.textContent === '跳过');
      if (pass) { pass.click(); return 'pass'; }
      const mine = document.querySelectorAll('.rq-seat[data-s="0"] .rq-mine');
      if (mine.length && mine.length % 3 === 2) { mine[mine.length - 1].click(); return 'discard'; }
      return 'wait';
    })()`);
    if (st === 'win' && shots < 1) { await wait(400); await shot('rq-win'); shots++; }
    if (st === 'end') break;
  }
  await shot('rq-table');
  const recs = await js(`document.querySelector('.rq-popup:not(.rq-hidden) [data-e=replay]') ? 'end-popup' : 'no-end'`);
  console.log('state', recs);
  if (recs === 'end-popup') {
    await js(`document.querySelector('[data-e=replay]').click(); 1`);
    await wait(600);
    for (let i = 0; i < 40; i++) await js(`document.querySelector('[data-r=next]').click(); 1`);
    await wait(300);
    await shot('rq-replay');
  }
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
