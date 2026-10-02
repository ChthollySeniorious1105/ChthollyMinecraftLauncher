// open every hub page at two widths, screenshot it and report overlapping UI elements
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error') errors.push(e.message); }));
const only = process.argv.find(a => a.startsWith('--pages='));
const DETECT = `(() => {
  const root = document.querySelector('#content > .page');
  const vis = e => { const s = getComputedStyle(e); if (s.visibility === 'hidden' || s.display === 'none') return false; let o = 1; for (let x = e; x && x !== document.body; x = x.parentElement) o *= +getComputedStyle(x).opacity; return o > 0.05; };
  const els = [];
  for (const e of root.querySelectorAll('*')) {
    if (e.closest('svg') && e.tagName.toLowerCase() !== 'svg') continue;
    if (e.closest('canvas, .toast')) continue;
    const tag = e.tagName.toLowerCase();
    const leafText = [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    const ctl = ['input', 'select', 'textarea', 'button', 'img', 'svg'].includes(tag) || e.classList.contains('switch');
    if (!leafText && !ctl) continue;
    if (e.closest('.switch') && !e.classList.contains('switch')) continue;
    if (!vis(e)) continue;
    let r;
    if (leafText && !ctl) {
      // measure the text itself, not the (maybe wide) block
      const rg = document.createRange(); rg.selectNodeContents(e); r = rg.getBoundingClientRect();
    } else r = e.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) continue;
    els.push({ e, r });
  }
  const name = e => e.tagName.toLowerCase() + (e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\s+/).join('.') : '') + (e.textContent.trim() ? ' "' + e.textContent.trim().slice(0, 18) + '"' : '');
  const out = [];
  for (let i = 0; i < els.length; i++) for (let j = i + 1; j < els.length; j++) {
    const a = els[i], b = els[j];
    if (a.e.contains(b.e) || b.e.contains(a.e)) continue;
    const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
    const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
    if (w > 3 && h > 3) {
      // ignore things that are both inside a positioned overlay by design (badges etc) - report anyway, filter later
      out.push(name(a.e) + '  <->  ' + name(b.e) + '  (' + Math.round(w) + 'x' + Math.round(h) + ')');
    }
    if (out.length > 40) return out;
  }
  // horizontal overflow of the page
  const pg = document.getElementById('content');
  if (pg.scrollWidth > pg.clientWidth + 2) out.push('HORIZONTAL OVERFLOW ' + pg.scrollWidth + ' > ' + pg.clientWidth);
  // content clipped at the left/right edge of the content area
  const cr = pg.getBoundingClientRect();
  let worst = null;
  for (const { e, r } of els) {
    const cut = Math.max(cr.left - r.left, r.right - (cr.left + pg.clientWidth));
    if (cut > 3 && (!worst || cut > worst.cut)) worst = { e, cut };
  }
  if (worst) out.push('CLIPPED ' + Math.round(worst.cut) + 'px: ' + name(worst.e));
  return out;
})()`;
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'home');
  await wait(1500);
  const hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/'));
  const wc = hub.webContents;
  let ids = await wc.executeJavaScript(`Hub.list().map(m => m.id)`);
  if (only) ids = only.slice(8).split(',');
  const dir = path.join(__dirname, 'out', 'ui');
  fs.mkdirSync(dir, { recursive: true });
  const b0 = hub.getBounds();
  const report = {};
  for (const [tag, width] of [['default', 980], ['min', 820]]) {
    hub.setBounds({ x: b0.x, y: b0.y, width, height: 700 });
    await wait(400);
    for (const id of ids) {
      await wc.executeJavaScript(`Hub.open(${JSON.stringify(id)}, true); 1`);
      await wait(1200);
      // open editors / forms that start hidden so they get checked too
      if (id === 'days') await wc.executeJavaScript(`document.querySelector('.dd-new').click(); 1`);
      await wait(150);
      await wc.executeJavaScript('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))');
      const res = await wc.executeJavaScript(DETECT).catch(e => ['DETECT FAILED ' + e.message]);
      if (res.length) report[`${id}@${tag}`] = res;
      fs.writeFileSync(path.join(dir, `${id}-${tag}.png`), (await wc.capturePage()).toPNG());
    }
  }
  hub.setBounds(b0);
  fs.writeFileSync(path.join(__dirname, 'out', 'overlap.json'), JSON.stringify(report, null, 1));
  for (const [k, v] of Object.entries(report)) { console.log('== ' + k); v.slice(0, 12).forEach(x => console.log('   ' + x)); }
  console.log('PAGES', ids.length, 'WITH ISSUES', Object.keys(report).length);
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
