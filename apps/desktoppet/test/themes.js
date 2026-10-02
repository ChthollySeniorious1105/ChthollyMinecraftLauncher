// write a few CML theme.json palettes and screenshot the hub + pet window, to eyeball contrast on real pages
// (the app follows the CML launcher theme via CML_THEME_FILE; this uses a private temp file)
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
app.setPath('userData', path.join(__dirname, 'userdata'));
const dir = path.join(__dirname, 'out', 'themes');
fs.mkdirSync(dir, { recursive: true });
const themeFile = path.join(dir, 'theme.json');
const PALETTES = {
  light: { id: 'light', name: 'CML 浅色', dark: false, bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280', line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff', paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8'] },
  sakura: { id: 'sakura', name: '樱花', dark: false, bg: '#fdf3f6', surface: '#ffffff', panel: '#fffafb', text: '#3b2a33', muted: '#9a7f8a', line: '#f0d6df', field: '#fbeef2', accent: '#e8628a', accent2: '#b77ce6', onAccent: '#ffffff', paper: '#fffafb', ink: '#3b2a33', art: ['#ffb3cc', '#e3c4ff'] },
  dark: { id: 'dark', name: 'CML 深色', dark: true, bg: '#11141c', surface: '#1a1e29', panel: '#1a1e29', text: '#e4e8f2', muted: '#97a0b3', line: '#2a3040', field: '#222838', accent: '#7c9cff', accent2: '#5ad1c4', onAccent: '#0d1020', paper: '#181c26', ink: '#d6dbe6', art: ['#7c9cff', '#5ad1c4'] }
};
const writeTheme = t => { fs.writeFileSync(themeFile + '.tmp', JSON.stringify({ version: 1, ...t })); fs.renameSync(themeFile + '.tmp', themeFile); };
writeTheme(PALETTES.light);
process.env.CML_THEME_FILE = themeFile;
require('../src/main.js');
const wait = ms => new Promise(r => setTimeout(r, ms));
const errors = [];
app.on('web-contents-created', (_e, wc) => wc.on('console-message', e => { if (e.level === 'error' || e.level === 'warning') errors.push(e.message); }));
const THEMES = (process.env.THEMES || 'light,sakura,dark').split(',');
const PAGES = (process.env.PAGES || 'home,settings,care,fishing,gacha,minesweeper').split(',');
app.whenReady().then(async () => {
  await wait(2000);
  ipcMain.emit('hub:open', {}, 'home');
  let hub;
  for (let i = 0; i < 40 && !hub; i++) { await wait(250); hub = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/hub/')); }
  const pet = BrowserWindow.getAllWindows().find(w => w.webContents.getURL().includes('/pet/'));
  await wait(1500);
  const js = s => hub.webContents.executeJavaScript(s);
  for (const t of THEMES) {
    writeTheme(PALETTES[t]);
    await wait(700);
    for (const p of PAGES) {
      await js(`Hub.open('${p}', true); 1`);
      await wait(p === 'fishing' ? 700 : 350);
      fs.writeFileSync(path.join(dir, `${t}-${p}.png`), (await hub.webContents.capturePage()).toPNG());
    }
    await pet.webContents.executeJavaScript(`document.getElementById('bubble').classList.remove('hidden'); document.getElementById('quick').classList.remove('hidden'); document.getElementById('stage').classList.add('hover'); 1`);
    await wait(300);
    fs.writeFileSync(path.join(dir, `${t}-pet.png`), (await pet.webContents.capturePage()).toPNG());
    const applied = await js(`document.documentElement.dataset.theme + ' ' + document.documentElement.classList.contains('theme-dark') + ' ' + getComputedStyle(document.documentElement).getPropertyValue('--accent')`);
    const petApplied = await pet.webContents.executeJavaScript(`document.documentElement.dataset.theme + ' ' + getComputedStyle(document.documentElement).getPropertyValue('--panel')`);
    const nav = await js(`[...document.querySelectorAll('.nav-item')].some(b => b.dataset.id === 'themes')`);
    console.log(t, '-> hub', applied, '| pet', petApplied, '| themes nav entry:', nav);
  }
  console.log('ERRORS:', [...new Set(errors)].join('\n'));
  app.exit(0);
});
