const { app, BrowserWindow, ipcMain, screen, Tray, Menu, nativeImage, Notification, clipboard, dialog, shell, globalShortcut } = require('electron');
const path = require('path');
const fs = require('fs');
const { GACHA } = require('./play');
// colours follow the CML launcher (theme.json, see src/theme-bridge.js)
const { initThemeBridge, getTheme, onThemeChange } = require('./theme-bridge');

const ASSETS = path.join(__dirname, '..', 'assets');
const PETS = fs.readdirSync(path.join(ASSETS, 'pets')).filter(f => f.endsWith('.png')).sort();
const PET_BASE = { w: 260, h: 330 };

// CML starts us through its shared Electron runtime as `electron.exe <app dir>`: pin the app name and
// userData dir (same %APPDATA%/DesktopPet as the standalone build) before the single-instance lock is taken,
// so the lock and the data are per app rather than per runtime. A custom userData set earlier (test/) is kept.
app.setName('DesktopPet');
if (path.dirname(app.getPath('userData')) === app.getPath('appData')) app.setPath('userData', path.join(app.getPath('appData'), 'DesktopPet'));
if (!app.requestSingleInstanceLock()) {
  app.quit();
  process.exit(0);
}
app.setAppUserModelId('com.desktoppet.app');

// ---------- persistent store ----------
const storeFile = path.join(app.getPath('userData'), 'data.json');
let data = {};
try { data = JSON.parse(fs.readFileSync(storeFile, 'utf8')); } catch { data = {}; }
let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flush, 300);
}
function flush() {
  try {
    fs.mkdirSync(path.dirname(storeFile), { recursive: true });
    fs.writeFileSync(storeFile, JSON.stringify(data, null, 1));
  } catch (e) { console.error(e); }
}

const DEFAULT_SETTINGS = {
  pet: PETS[0],
  scale: 1,
  alwaysOnTop: true,
  autoStart: false,
  chatter: true,
  opacity: 1,
  walk: false,
  clipboard: true,
  hotkey: 'Ctrl+Alt+P',
  bongo: { on: false, mode: 'cat', skin: 'orange', sound: false, scale: 1, opacity: 1, showKeys: true, clickThrough: true, x: null, y: null, hotkey: 'Ctrl+Alt+B' },
  water: { enabled: true, minutes: 60 },
  sit: { enabled: true, minutes: 45 },
  eye: { enabled: false, minutes: 20 }
};
function settings() {
  data.settings = Object.assign({}, DEFAULT_SETTINGS, data.settings || {});
  if (!PETS.includes(data.settings.pet)) data.settings.pet = PETS[0];
  delete data.settings.theme;   // the old built-in theme choice; CML decides the colours now
  return data.settings;
}

// ---------- debug log (DESKTOPPET_DEBUG=1) ----------
const DEBUG = !!process.env.DESKTOPPET_DEBUG;
function dlog(...a) {
  if (DEBUG) fs.appendFileSync(path.join(app.getPath('userData'), 'debug.log'), `${new Date().toISOString()} ${a.join(' ')}
`);
}

// ---------- windows ----------
let petWin = null, hubWin = null, tray = null;

function broadcast(channel, payload) {
  for (const w of [petWin, hubWin]) if (w && !w.isDestroyed()) w.webContents.send(channel, payload);
}

function petSize() {
  const s = settings().scale;
  return { width: Math.round(PET_BASE.w * s), height: Math.round(PET_BASE.h * s) };
}

function createPet() {
  const s = settings();
  const size = petSize();
  const wa = screen.getPrimaryDisplay().workArea;
  let { x, y } = data.petPos || { x: wa.x + wa.width - size.width - 40, y: wa.y + wa.height - size.height };
  petWin = new BrowserWindow({
    ...size, x, y,
    transparent: true, frame: false, resizable: false, hasShadow: false,
    skipTaskbar: true, alwaysOnTop: s.alwaysOnTop, maximizable: false, fullscreenable: false,
    backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js') }
  });
  petWin.setAlwaysOnTop(s.alwaysOnTop, 'floating');
  petWin.setOpacity(s.opacity);
  petWin.loadFile(path.join(__dirname, 'pet', 'index.html'));
  petWin.setIgnoreMouseEvents(true);
  ensureOnScreen();
  petWin.on('closed', () => { petWin = null; clearInterval(hoverPoll); });
  startHoverPoll();
}

// setIgnoreMouseEvents({ forward: true }) does not deliver mousemove to transparent
// windows reliably on Windows, so poll the cursor and let the renderer hit-test.
let hoverPoll = null, wasInside = false;
function startHoverPoll() {
  clearInterval(hoverPoll);
  hoverPoll = setInterval(() => {
    if (!petWin || petWin.isDestroyed() || !petWin.isVisible()) return;
    const p = screen.getCursorScreenPoint();
    const b = petWin.getContentBounds();
    const inside = p.x >= b.x && p.x < b.x + b.width && p.y >= b.y && p.y < b.y + b.height;
    if (inside !== wasInside) dlog('hover inside', inside, p.x - b.x, p.y - b.y);
    if (inside) petWin.webContents.send('pet:hover', { x: p.x - b.x, y: p.y - b.y });
    else if (wasInside) petWin.webContents.send('pet:hover', null);
    wasInside = inside;
  }, 50);
}

function ensureOnScreen() {
  if (!petWin) return;
  const b = petWin.getBounds();
  const d = screen.getDisplayMatching(b).workArea;
  // allow the transparent margins to hang off-screen, but keep the pet itself reachable
  const x = Math.min(Math.max(b.x, d.x - b.width * 0.3), d.x + d.width - b.width * 0.7);
  const y = Math.min(Math.max(b.y, d.y - b.height * 0.3), d.y + d.height - b.height * 0.9);
  petWin.setPosition(Math.round(x), Math.round(y));
}

// The hub window is created once and hidden instead of closed, so reopening never
// shows a half-loaded page. It is only shown after the page has verifiably rendered.
let hubReady = false, hubPending = null, hubReloads = 0, quitting = false, hubWatchdog = null;
function createHub(page) {
  hubReady = false;
  hubReloads = 0;
  hubWin = new BrowserWindow({
    width: 980, height: 700, minWidth: 820, minHeight: 600,
    frame: false, show: false, backgroundColor: getTheme().bg, title: 'DesktopPet',
    icon: petIcon(64),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), backgroundThrottling: false }
  });
  const wc = hubWin.webContents;
  wc.on('did-finish-load', verifyHub);
  wc.on('render-process-gone', (_e, d) => { dlog('hub render-process-gone', JSON.stringify(d), 'lastPage', lastHubPage); reloadHub(); });
  wc.on('did-fail-load', (_e, code, desc) => { dlog('hub did-fail-load', code, desc); reloadHub(); });
  hubWin.on('unresponsive', () => { dlog('hub unresponsive'); reloadHub(); });
  hubWin.on('close', e => {
    if (quitting) return;
    e.preventDefault();
    hubWin.hide();
  });
  hubWin.on('closed', () => { hubWin = null; hubReady = false; });
  hubWin.loadFile(path.join(__dirname, 'hub', 'index.html'), { query: { page: page || 'home' } });
}
function reloadHub() {
  if (!hubWin || hubWin.isDestroyed()) return;
  hubReady = false;
  if (hubReloads++ >= 3) {
    // give up on this window and start from a fresh one
    const pending = hubPending;
    hubWin.destroy();
    hubWin = null;
    if (pending) openHub(pending);
    return;
  }
  hubWin.webContents.reloadIgnoringCache();
}
async function verifyHub() {
  if (!hubWin || hubWin.isDestroyed()) return;
  let ok = false;
  try {
    ok = await hubWin.webContents.executeJavaScript(
      `!!(document.querySelector('#content > .page') && document.querySelectorAll('.nav-item').length)`);
  } catch (e) { dlog('hub verify error', e.message); }
  dlog('hub verify', ok);
  if (!ok) return reloadHub();
  hubReady = true;
  hubReloads = 0;
  if (hubPending) showHub(hubPending);
}
let lastHubPage = null;
function showHub(page) {
  hubPending = null;
  lastHubPage = page;
  clearTimeout(hubWatchdog);
  hubWin.webContents.send('hub:open', page || 'home');
  if (hubWin.isMinimized()) hubWin.restore();
  hubWin.show();
  hubWin.focus();
  dlog('hub shown', hubWin.isVisible(), hubWin.isMinimized(), JSON.stringify(hubWin.getBounds()));
}
function openHub(page) {
  page = page || 'home';
  if (!hubWin || hubWin.isDestroyed()) createHub(page);
  if (hubReady) return showHub(page);
  hubPending = page;
  // if the page still hasn't rendered after a while, force a reload
  clearTimeout(hubWatchdog);
  hubWatchdog = setTimeout(() => { if (!hubReady) { dlog('hub watchdog'); reloadHub(); } }, 4000);
}

function petIcon(size) {
  return nativeImage.createFromPath(path.join(ASSETS, 'pets', settings().pet)).resize({ width: size, height: size });
}

function createTray() {
  tray = new Tray(petIcon(16));
  tray.setToolTip('DesktopPet');
  tray.on('click', () => togglePet(true));
  tray.on('double-click', () => openHub('home'));
  refreshTrayMenu();
}
function refreshTrayMenu() {
  if (!tray) return;
  tray.setImage(petIcon(16));
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: '打开菜单', click: () => openHub('home') },
    { label: petWin && petWin.isVisible() ? '隐藏宠物' : '显示宠物', click: () => togglePet() },
    { label: '番茄钟', click: () => openHub('pomodoro') },
    { label: '照顾宠物', click: () => openHub('care') },
    { label: bongoWin ? '关闭键鼠映射' : '键鼠映射看板', click: toggleBongo },
    { type: 'separator' },
    { label: '退出', click: () => app.quit() }
  ]));
}
function togglePet(forceShow) {
  if (!petWin) return;
  if (forceShow || !petWin.isVisible()) petWin.show(); else petWin.hide();
  refreshTrayMenu();
}

// Start with Windows. Standalone builds register the exe itself; under CML's shared runtime the login item is
// `electron.exe "<app dir>"` (process.execPath + app path). A dev run from node_modules/electron never registers.
function setAutoStart(on) {
  if (process.platform !== 'win32') return;
  if (app.isPackaged) {
    app.setLoginItemSettings({ openAtLogin: on, path: process.env.PORTABLE_EXECUTABLE_FILE || process.execPath });
    return;
  }
  if (/[\\/]node_modules[\\/]electron[\\/]/i.test(process.execPath)) return;
  const opts = { path: process.execPath, args: [app.getAppPath()] };
  if (app.getLoginItemSettings(opts).openAtLogin === on) return;
  app.setLoginItemSettings({ ...opts, openAtLogin: on });
}

function applySettings(prev) {
  const s = settings();
  if (petWin) {
    petWin.setAlwaysOnTop(s.alwaysOnTop, 'floating');
    petWin.setOpacity(Number(s.opacity) || 1);
    if (!prev || prev.scale !== s.scale) {
      const b = petWin.getBounds();
      const size = petSize();
      // keep feet anchored
      petWin.setBounds({ x: b.x + Math.round((b.width - size.width) / 2), y: b.y + b.height - size.height, ...size });
    }
  }
  setAutoStart(!!s.autoStart);
  if (!prev || prev.pet !== s.pet) { refreshTrayMenu(); stats().petsTried[s.pet] = 1; }
  if (s.walk && !stats().walked) { stats().walked = true; setImmediate(checkAchievements); }
  if (!prev || prev.walk !== s.walk) walkReset();
  if (!prev || prev.clipboard !== s.clipboard) clipWatch(s.clipboard);
  if (!prev || prev.hotkey !== s.hotkey) registerHotkey();
  scheduleReminders();
  broadcast('settings', s);
}

// ---------- pomodoro (runs in main so it survives the hub closing) ----------
const POMO_DEFAULT = { work: 25, short: 5, long: 15, longEvery: 4, autoStart: false };
const pomo = { mode: 'work', running: false, endAt: 0, remaining: 0, round: 0 };
function pomoCfg() {
  data.pomoCfg = Object.assign({}, POMO_DEFAULT, data.pomoCfg || {});
  return data.pomoCfg;
}
function pomoDuration(mode) { return pomoCfg()[mode] * 60 * 1000; }
function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function pomoState() {
  const remaining = pomo.running ? Math.max(0, pomo.endAt - Date.now()) : pomo.remaining;
  return {
    mode: pomo.mode, running: pomo.running, remaining, total: pomoDuration(pomo.mode),
    round: pomo.round, cfg: pomoCfg(), stats: data.pomoStats || {}, today: today()
  };
}
pomo.remaining = pomoDuration('work');
let pomoTick = null;
function pomoStart() {
  if (pomo.running) return;
  if (pomo.remaining <= 0) pomo.remaining = pomoDuration(pomo.mode);
  pomo.running = true;
  pomo.endAt = Date.now() + pomo.remaining;
  clearInterval(pomoTick);
  pomoTick = setInterval(pomoStep, 250);
  broadcast('pomo', pomoState());
}
function pomoPause() {
  if (!pomo.running) return;
  pomo.remaining = Math.max(0, pomo.endAt - Date.now());
  pomo.running = false;
  clearInterval(pomoTick);
  broadcast('pomo', pomoState());
}
function pomoSetMode(mode) {
  pomo.running = false;
  clearInterval(pomoTick);
  pomo.mode = mode;
  pomo.remaining = pomoDuration(mode);
  broadcast('pomo', pomoState());
}
let lastSecond = -1;
function pomoStep() {
  const left = pomo.endAt - Date.now();
  if (left <= 0) return pomoFinish();
  const sec = Math.ceil(left / 1000);
  if (sec !== lastSecond) { lastSecond = sec; broadcast('pomo', pomoState()); }
}
function pomoFinish() {
  clearInterval(pomoTick);
  pomo.running = false;
  const cfg = pomoCfg();
  let msg;
  if (pomo.mode === 'work') {
    pomo.round++;
    data.pomoStats = data.pomoStats || {};
    const t = today();
    data.pomoStats[t] = (data.pomoStats[t] || 0) + 1;
    reward(Math.max(3, Math.round(cfg.work / 3)), '完成一个番茄钟');
    bump('pomos');
    const long = pomo.round % cfg.longEvery === 0;
    pomo.mode = long ? 'long' : 'short';
    msg = long ? `完成 ${cfg.longEvery} 个番茄啦！好好休息 ${cfg.long} 分钟吧~` : `一个番茄完成！休息 ${cfg.short} 分钟~`;
  } else {
    pomo.mode = 'work';
    msg = '休息结束，继续专注吧！';
  }
  pomo.remaining = pomoDuration(pomo.mode);
  notify('番茄钟', msg);
  broadcast('pet:say', { text: msg, mood: 'happy', ms: 8000 });
  broadcast('pomo', pomoState());
  if (cfg.autoStart) pomoStart();
}

// ---------- health reminders ----------
const reminderTimers = {};
const REMINDER_TEXT = {
  water: ['该喝水啦！补充一杯水吧 💧', '喝口水休息一下~', '记得喝水哦，身体最重要！'],
  sit: ['坐太久啦，起来活动一下吧！', '站起来伸个懒腰~', '起身走走，放松一下肩颈吧'],
  eye: ['看看远处 20 秒，让眼睛休息一下吧 👀', '眨眨眼，眺望一下远方~']
};
function scheduleReminders() {
  const s = settings();
  for (const key of Object.keys(REMINDER_TEXT)) {
    clearInterval(reminderTimers[key]);
    const r = s[key];
    if (r && r.enabled && r.minutes > 0) {
      reminderTimers[key] = setInterval(() => {
        const list = REMINDER_TEXT[key];
        const text = list[Math.floor(Math.random() * list.length)];
        broadcast('pet:say', { text, mood: 'alert', ms: 10000 });
        notify('健康提醒', text);
      }, r.minutes * 60 * 1000);
    }
  }
}

function notify(title, body) {
  if (Notification.isSupported()) new Notification({ title, body, icon: petIcon(64) }).show();
}

// ---------- pet care: needs, level, 小鱼干 coins, shop ----------
const NEEDS = ['hunger', 'mood', 'energy', 'clean'];
// points lost per hour while the app runs (offline time decays at half rate, capped at 24h)
const DECAY = { hunger: 5, mood: 4, energy: 3, clean: 2.5 };
const SHOP = {
  apple:     { price: 5,  effect: { hunger: 10, mood: 2 } },
  onigiri:   { price: 12, effect: { hunger: 25 } },
  milk:      { price: 8,  effect: { hunger: 8, energy: 12 } },
  coffee:    { price: 15, effect: { energy: 35, mood: -3 } },
  cake:      { price: 25, effect: { hunger: 18, mood: 25 } },
  icecream:  { price: 18, effect: { hunger: 6, mood: 22 } },
  fish:      { price: 20, effect: { hunger: 35, mood: 8 } },
  ball:      { price: 30, effect: { mood: 35, energy: -10 } },
  bath:      { price: 10, effect: { clean: 60, mood: 5 } }
};
function care() {
  const c = data.care = Object.assign({
    hunger: 80, mood: 80, energy: 80, clean: 80, exp: 0, level: 1, coins: 60,
    inventory: {}, last: Date.now(), log: [], lastPlay: 0, lastPet: 0, lastNeedTalk: 0, bornAt: Date.now(),
    owned: [], equipped: {}
  }, data.care || {});
  return c;
}
const clamp = v => Math.max(0, Math.min(100, v));
function careDecay(hours) {
  const c = care();
  for (const k of NEEDS) c[k] = clamp(c[k] - DECAY[k] * hours);
}
function careLog(text) {
  const c = care();
  c.log.unshift({ t: Date.now(), text });
  c.log.length = Math.min(c.log.length, 40);
}
function careState() {
  const c = care();
  return { ...c, need: c.level * 100, shop: SHOP };
}
const WARDROBE = (() => {
  // the same catalogue the renderers draw from
  const ctx = {};
  new Function('globalThis', fs.readFileSync(path.join(__dirname, 'shared', 'wardrobe.js'), 'utf8'))(ctx);
  return ctx.Wardrobe.ITEMS;
})();
function careChanged() {
  save();
  broadcast('care', careState());
}
function addExp(n) {
  const c = care();
  c.exp += n;
  while (c.exp >= c.level * 100) {
    c.exp -= c.level * 100;
    c.level++;
    const bonus = 20 + c.level * 5;
    c.coins += bonus;
    careLog(`升到了 ${c.level} 级！奖励 ${bonus} 小鱼干`);
    broadcast('pet:say', { text: `升级啦！现在是 Lv.${c.level} 🎉`, mood: 'happy', ms: 6000 });
    notify('升级啦', `你的宠物升到了 Lv.${c.level}`);
  }
}
function reward(coins, reason, exp) {
  const c = care();
  coins = Math.max(0, Math.min(100, Math.round(Number(coins) || 0)));
  if (!coins) return;
  c.coins += coins;
  careLog(`${reason || '奖励'} +${coins} 小鱼干`);
  addExp(exp != null ? exp : coins * 2);
  c.mood = clamp(c.mood + 3);
  careChanged();
  if (reason && /^签到/.test(reason)) play.questEvent('checkin');
  // game wins/settlements are the rewards whose reason names a game
  if (reason && !/番茄|签到|习惯|测试/.test(reason)) {
    const s = stats();
    s.gameKinds[reason.replace(/(胜利|通关|过关|结算|获胜|全收|合成 2048)$/, '').trim() || reason] = 1;
    bump('wins');
  }
}
function careAction(action, item) {
  const c = care();
  const now = Date.now();
  let say = null, mood = 'happy', ok = true;
  if (action === 'buy') {
    const it = SHOP[item];
    if (!it) return { ok: false };
    if (c.coins < it.price) return { ok: false, msg: '小鱼干不够啦' };
    c.coins -= it.price;
    c.inventory[item] = (c.inventory[item] || 0) + 1;
  } else if (action === 'use') {
    const it = SHOP[item];
    if (!it || !c.inventory[item]) return { ok: false, msg: '背包里没有这个' };
    c.inventory[item]--;
    if (!c.inventory[item]) delete c.inventory[item];
    for (const [k, v] of Object.entries(it.effect)) c[k] = clamp(c[k] + v);
    addExp(Math.ceil(it.price / 2));
    if ('hunger' in it.effect && it.effect.hunger > 0) setImmediate(() => bump('feeds'));
    if (item === 'bath') setImmediate(() => play.questEvent('bath'));
    say = item === 'bath' ? '洗得香喷喷的~ 🛁' : item === 'ball' ? '玩球好开心！' : item === 'coffee' ? '精神百倍！☕' : '好好吃！谢谢你~ 😋';
  } else if (action === 'bait') {
    // 钓鱼 bait: 2 coins, no care effect
    if (c.coins < 2) return { ok: false, msg: '小鱼干不够买鱼饵了' };
    c.coins -= 2;
  } else if (action === 'wear-buy') {
    const it = WARDROBE[item];
    if (!it) return { ok: false };
    if (c.owned.includes(item)) return { ok: false, msg: '已经拥有啦' };
    if (c.coins < it.price) return { ok: false, msg: '小鱼干不够啦' };
    c.coins -= it.price;
    c.owned.push(item);
    c.equipped[it.slot] = item;
    careLog(`买了 ${it.name}`);
    say = `穿上${it.name}啦，好看吗？`;
  } else if (action === 'wear') {
    const it = WARDROBE[item];
    if (!it || !c.owned.includes(item)) return { ok: false };
    if (c.equipped[it.slot] === item) delete c.equipped[it.slot];
    else c.equipped[it.slot] = item;
  } else if ((action === 'play' || action === 'rest') && play.trip() && play.trip().end > now) {
    return { ok: false, msg: '宠物正在外面探险，还没回来哦' };
  } else if (action === 'play') {
    if (now - c.lastPlay < 10 * 60 * 1000) return { ok: false, msg: '刚玩过啦，歇一会儿吧' };
    if (c.energy < 15) return { ok: false, msg: '太累了，先让它休息一下吧' };
    c.lastPlay = now;
    setImmediate(() => play.questEvent('play'));
    c.mood = clamp(c.mood + 20); c.energy = clamp(c.energy - 12); c.hunger = clamp(c.hunger - 5);
    addExp(10);
    say = '一起玩真开心！';
  } else if (action === 'rest') {
    if (c.energy > 90) return { ok: false, msg: '现在一点都不困哦' };
    c.energy = clamp(c.energy + 30); c.hunger = clamp(c.hunger - 5);
    say = '呼…睡了个好觉~ 😴';
  } else if (action === 'pet') {
    // clicking the pet on the desktop: tiny mood boost, rate limited
    if (now - c.lastPet < 30 * 1000) return { ok: false };
    c.lastPet = now;
    c.mood = clamp(c.mood + 2);
    addExp(1);
    setImmediate(() => bump('pets'));
  } else ok = false;
  if (ok) {
    careChanged();
    if (say) broadcast('pet:say', { text: say, mood, ms: 4000 });
    if (action === 'wear-buy') setImmediate(checkAchievements);
  }
  return { ok, state: careState() };
}
function careTick() {
  const c = care();
  const now = Date.now();
  const hours = (now - c.last) / 3600e3;
  c.last = now;
  careDecay(hours);
  // complain about the most urgent need now and then
  if (now - c.lastNeedTalk > 20 * 60 * 1000) {
    const low = NEEDS.filter(k => c[k] < 25).sort((a, b) => c[a] - c[b])[0];
    const lines = { hunger: '肚子饿扁了…喂我点吃的吧 🍙', mood: '好无聊啊，陪我玩一会儿嘛~', energy: '好困…想睡觉了 💤', clean: '身上脏脏的，想洗澡 🛁' };
    if (low) { c.lastNeedTalk = now; broadcast('pet:say', { text: lines[low], mood: 'sad', ms: 8000 }); }
  }
  save();
  broadcast('care', careState());
}
{
  // apply offline decay at half rate, at most one day's worth
  const c = care();
  const hours = Math.min(24, (Date.now() - c.last) / 3600e3) / 2;
  careDecay(hours);
  c.last = Date.now();
}

// ---------- achievements ----------
// stats: counters bumped by events; each achievement unlocks once and pays coins
const ACHIEVEMENTS = [
  { id: 'first_win', name: '初出茅庐', desc: '第一次赢得任意小游戏', icon: '🎮', coins: 10, test: s => s.wins >= 1 },
  { id: 'win10', name: '游戏达人', desc: '累计赢得 10 次小游戏', icon: '🏅', coins: 30, test: s => s.wins >= 10 },
  { id: 'win50', name: '游戏大师', desc: '累计赢得 50 次小游戏', icon: '🏆', coins: 100, test: s => s.wins >= 50 },
  { id: 'games5', name: '博采众长', desc: '在 5 种不同的小游戏中获胜', icon: '🎲', coins: 40, test: s => Object.keys(s.gameKinds || {}).length >= 5 },
  { id: 'games12', name: '十八般武艺', desc: '在 12 种不同的小游戏中获胜', icon: '🧩', coins: 120, test: s => Object.keys(s.gameKinds || {}).length >= 12 },
  { id: 'pomo1', name: '专注起步', desc: '完成第一个番茄钟', icon: '🍅', coins: 10, test: s => s.pomos >= 1 },
  { id: 'pomo25', name: '番茄农场主', desc: '累计完成 25 个番茄钟', icon: '🧺', coins: 60, test: s => s.pomos >= 25 },
  { id: 'pomo100', name: '心流大师', desc: '累计完成 100 个番茄钟', icon: '🧘', coins: 200, test: s => s.pomos >= 100 },
  { id: 'feed10', name: '好好吃饭', desc: '喂食 10 次', icon: '🍙', coins: 15, test: s => s.feeds >= 10 },
  { id: 'feed100', name: '美食家', desc: '喂食 100 次', icon: '🍰', coins: 80, test: s => s.feeds >= 100 },
  { id: 'pet50', name: '撸宠爱好者', desc: '摸摸宠物 50 次', icon: '🤚', coins: 20, test: s => s.pets >= 50 },
  { id: 'lv5', name: '茁壮成长', desc: '宠物达到 5 级', icon: '🌱', coins: 30, test: (s, c) => c.level >= 5 },
  { id: 'lv10', name: '独当一面', desc: '宠物达到 10 级', icon: '🌳', coins: 80, test: (s, c) => c.level >= 10 },
  { id: 'rich', name: '小富翁', desc: '同时拥有 500 小鱼干', icon: '💰', coins: 50, test: (s, c) => c.coins >= 500 },
  { id: 'dress', name: '时尚达人', desc: '拥有 5 件装扮', icon: '👒', coins: 40, test: (s, c) => (c.owned || []).length >= 5 },
  { id: 'dressall', name: '衣橱收藏家', desc: '集齐所有装扮', icon: '👑', coins: 150, test: (s, c) => (c.owned || []).length >= Object.keys(WARDROBE).length },
  { id: 'streak7', name: '坚持一周', desc: '连续签到 7 天', icon: '📅', coins: 50, test: s => s.streak >= 7 },
  { id: 'night', name: '夜猫子', desc: '在凌晨 0-4 点和宠物互动', icon: '🦉', coins: 15, test: s => s.night },
  { id: 'walker', name: '散步爱好者', desc: '开启散步模式', icon: '🚶', coins: 10, test: s => s.walked },
  { id: 'flinger', name: '空中飞宠', desc: '把宠物扔出去弹跳 3 次以上', icon: '🪃', coins: 15, test: s => s.flings >= 1 },
  { id: 'festival', name: '节日快乐', desc: '在节日当天和宠物互动', icon: '🎉', coins: 20, test: s => s.festival },
  { id: 'quest1', name: '今日事今日毕', desc: '完成一天的全部每日任务', icon: '📋', coins: 15, test: s => (s.questDays || 0) >= 1 },
  { id: 'quest7', name: '任务狂人', desc: '累计 7 天完成全部每日任务', icon: '🗂️', coins: 60, test: s => (s.questDays || 0) >= 7 },
  { id: 'trip1', name: '第一次出远门', desc: '完成一次外出探险', icon: '🎒', coins: 10, test: s => (s.trips || 0) >= 1 },
  { id: 'trip20', name: '环游世界', desc: '完成 20 次外出探险', icon: '🗺️', coins: 80, test: s => (s.trips || 0) >= 20 },
  { id: 'souv', name: '纪念品收藏家', desc: '收集全部探险纪念品', icon: '🏺', coins: 150, test: () => Object.keys(data.souvenirs || {}).length >= play.souvenirTotal() },
  { id: 'fish1', name: '初次上钩', desc: '钓到第一条鱼', icon: '🎣', coins: 10, test: s => (s.fish || 0) >= 1 },
  { id: 'fishdex', name: '水族馆馆长', desc: '集齐钓鱼图鉴中的全部鱼', icon: '🐠', coins: 150, test: () => Object.keys(data.fishdex || {}).length >= 16 },
  { id: 'farm1', name: '小小农夫', desc: '在花园收获第一次作物', icon: '🌱', coins: 10, test: s => (s.harvests || 0) >= 1 },
  { id: 'farm50', name: '丰收季节', desc: '在花园累计收获 50 次', icon: '🌾', coins: 80, test: s => (s.harvests || 0) >= 50 },
  { id: 'golden', name: '金灿灿', desc: '收获一次金色作物', icon: '🌟', coins: 30, test: s => s.golden },
  { id: 'gacha1', name: '扭一扭', desc: '第一次扭扭蛋', icon: '🥚', coins: 5, test: s => (s.gacha || 0) >= 1 },
  { id: 'gachaall', name: '手办收藏家', desc: '集齐扭蛋机里的全部手办', icon: '🏆', coins: 200, test: () => Object.keys(data.gacha || {}).length >= GACHA.length },
  { id: 'catch500', name: '接接乐', desc: '在接食物中得到 500 分', icon: '🧺', coins: 20, test: s => (s.catchBest || 0) >= 500 },
  { id: 'allpets', name: '动物园园长', desc: '换上过全部 20 只宠物', icon: '🦁', coins: 60, test: s => Object.keys(s.petsTried || {}).length >= PETS.length }
];
function stats() {
  return (data.stats = Object.assign({ wins: 0, gameKinds: {}, pomos: 0, feeds: 0, pets: 0, streak: 0, night: false, walked: false, petsTried: {} }, data.stats || {}));
}
function achState() {
  const got = data.achievements || {};
  return { list: ACHIEVEMENTS.map(({ test, ...a }) => ({ ...a, at: got[a.id] || 0 })), stats: stats() };
}
function checkAchievements() {
  data.achievements = data.achievements || {};
  const s = stats(), c = care();
  for (const a of ACHIEVEMENTS) {
    if (data.achievements[a.id] || !a.test(s, c)) continue;
    data.achievements[a.id] = Date.now();
    c.coins += a.coins;
    careLog(`达成成就「${a.name}」+${a.coins} 小鱼干`);
    notify('达成成就', `${a.icon} ${a.name}：${a.desc}`);
    broadcast('pet:say', { text: `达成成就「${a.name}」！${a.icon}`, mood: 'happy', ms: 6000 });
    broadcast('achievement', a.id);
  }
  save();
  broadcast('care', careState());
}
function bump(key, n = 1) {
  const s = stats();
  s[key] = (s[key] || 0) + n;
  if (['wins', 'pomos', 'feeds', 'pets'].includes(key)) play.questEvent(key, n);
  const h = new Date().getHours();
  if (h < 4) s.night = true;
  checkAchievements();
}

// ---------- 每日任务 / 外出探险 / 钓鱼 (src/play.js) ----------
const play = require('./play').init({
  store: () => data, save, broadcast, notify, care, careLog, careChanged, addExp, clamp, today, stats,
  checkAchievements: () => checkAchievements()
});
ipcMain.on('play:get', e => { e.returnValue = play.playState(); });
ipcMain.on('play:trip', (e, id) => { e.returnValue = play.tripStart(id); });
ipcMain.on('play:claim', e => { e.returnValue = play.tripClaim(); });
ipcMain.on('play:recall', e => { e.returnValue = play.tripRecall(); });
ipcMain.on('play:fish', (e, f) => { e.returnValue = play.fishCatch(f); });
ipcMain.on('play:garden', (e, op, a) => { e.returnValue = play.gardenOp(op, a); });
ipcMain.on('play:gacha', e => { e.returnValue = play.gachaSpin(); });

// ---------- alarms & countdowns ----------
// alarm: { id, time: 'HH:MM', days: [0..6] (empty = once), label, enabled, lastFired }
// countdown: { id, label, endAt, total }
function alarms() { return (data.alarms = data.alarms || []); }
function countdowns() { return (data.countdowns = data.countdowns || []); }
function alarmsState() { return { alarms: alarms(), countdowns: countdowns() }; }
function alarmFire(title, text) {
  notify(title, text);
  broadcast('pet:say', { text: `⏰ ${text}`, mood: 'alert', ms: 15000 });
  broadcast('alarm:ring', { title, text });
}
function alarmTick() {
  const now = new Date();
  const hm = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  const stamp = `${today()} ${hm}`;
  let changed = false;
  for (const a of alarms()) {
    if (!a.enabled || a.time !== hm || a.lastFired === stamp) continue;
    if (a.days.length && !a.days.includes(now.getDay())) continue;
    a.lastFired = stamp;
    if (!a.days.length) a.enabled = false;
    alarmFire('闹钟', a.label || `现在是 ${hm}`);
    changed = true;
  }
  const due = countdowns().filter(c => c.endAt <= Date.now());
  if (due.length) {
    data.countdowns = countdowns().filter(c => c.endAt > Date.now());
    for (const c of due) alarmFire('倒计时结束', c.label || '时间到啦！');
    changed = true;
  }
  if (changed) { save(); broadcast('alarms', alarmsState()); }
}

// ---------- system stats ----------
const os = require('os');
let prevCpu = null;
function cpuSample() {
  const t = os.cpus().reduce((a, c) => {
    const tot = Object.values(c.times).reduce((x, y) => x + y, 0);
    return { idle: a.idle + c.times.idle, total: a.total + tot };
  }, { idle: 0, total: 0 });
  let usage = 0;
  if (prevCpu && t.total > prevCpu.total) usage = 1 - (t.idle - prevCpu.idle) / (t.total - prevCpu.total);
  prevCpu = t;
  return usage;
}
cpuSample();
function sysState() {
  const cpus = os.cpus();
  return {
    cpu: cpuSample(), cpuModel: cpus[0] ? cpus[0].model.trim() : '', cores: cpus.length,
    memTotal: os.totalmem(), memFree: os.freemem(), uptime: os.uptime(),
    host: os.hostname(), platform: `${os.type()} ${os.release()}`, appUptime: process.uptime()
  };
}

// ---------- walk mode: the pet strolls along the bottom of the work area ----------
let walkTimer = null, walkState = { dir: 1, pauseUntil: 0 };
function walkReset() {
  clearInterval(walkTimer);
  walkTimer = null;
  if (petWin && !petWin.isDestroyed()) petWin.webContents.send('pet:walk', { walking: false });
  if (!settings().walk) return;
  walkTimer = setInterval(walkStep, 40);
}
let petDragging = false;
function walkStep() {
  if (!petWin || petWin.isDestroyed() || !petWin.isVisible() || petDragging) return;
  const now = Date.now();
  const b = petWin.getBounds();
  const wa = screen.getDisplayMatching(b).workArea;
  const floor = wa.y + wa.height - b.height;
  // fall back to the floor first
  if (b.y < floor - 1) {
    petWin.setPosition(b.x, Math.min(floor, b.y + Math.max(4, Math.round((floor - b.y) * 0.25))));
    return;
  }
  if (now < walkState.pauseUntil) return;
  if (Math.random() < 0.004) {
    walkState.pauseUntil = now + 2000 + Math.random() * 6000;
    petWin.webContents.send('pet:walk', { walking: false });
    return;
  }
  if (Math.random() < 0.002) walkState.dir *= -1;
  let x = b.x + walkState.dir * 2;
  const minX = wa.x - b.width * 0.15, maxX = wa.x + wa.width - b.width * 0.85;
  if (x < minX || x > maxX) { walkState.dir *= -1; x = Math.max(minX, Math.min(maxX, x)); }
  petWin.setPosition(Math.round(x), floor);
  petWin.webContents.send('pet:walk', { walking: true, dir: walkState.dir });
}

// ---------- clipboard history (text only, kept in memory + optional persistence) ----------
let clipTimer = null, clipLast = '';
function clipList() {
  // drop anything malformed (older builds could store non-string entries)
  return (data.clips = (data.clips || []).filter(c => c && typeof c.text === 'string'));
}
function clipWatch(on) {
  clearInterval(clipTimer);
  clipTimer = null;
  if (!on) return;
  try { clipLast = String(clipboard.readText() || ''); } catch { clipLast = ''; }
  clipTimer = setInterval(() => {
    let t = '';
    try { t = clipboard.readText(); } catch { return; }
    if (typeof t !== 'string' || !t || t === clipLast || t.length > 20000) return;
    clipLast = t;
    const list = clipList();
    const i = list.findIndex(c => c.text === t);
    let pinned = false;
    if (i >= 0) { pinned = list[i].pinned; list.splice(i, 1); }
    list.unshift({ text: t, t: Date.now(), pinned });
    // keep pinned items, cap the rest at 100
    let unpinned = 0;
    data.clips = list.filter(c => c.pinned || ++unpinned <= 100);
    save();
    broadcast('clips', data.clips);
  }, 800);
}

// ---------- 键鼠映射看板 (BongoCat-style input overlay) ----------
// A separate transparent always-on-top window; a global input hook (uiohook-napi) feeds it
// key/mouse events from every application. The hook only runs while the board is open.
let bongoWin = null, hook = null, hookOn = false, bongoMoveT = 0;
const BONGO_SIZE = { cat: [380, 300], keyboard: [640, 300], bongo: [400, 300], piano: [620, 300], gamepad: [460, 300], strip: [640, 150], lkeys: [400, 270], ldesk: [400, 270], lbongo: [400, 270], ltable: [400, 270] };
function bongoCfg() {
  const s = settings();
  s.bongo = Object.assign({}, DEFAULT_SETTINGS.bongo, s.bongo || {});
  return s.bongo;
}
function loadHook() {
  if (hook) return hook;
  try { hook = require('uiohook-napi'); } catch (e) { dlog('uiohook load failed', e.message); hook = null; }
  return hook;
}
function bongoSend(ch, payload) { if (bongoWin && !bongoWin.isDestroyed()) bongoWin.webContents.send(ch, payload); }
function startHook() {
  const h = loadHook();
  if (!h || hookOn) return !!h;
  const { uIOhook } = h;
  uIOhook.on('keydown', e => bongoSend('bongo:key', { down: true, code: e.keycode }));
  uIOhook.on('keyup', e => bongoSend('bongo:key', { down: false, code: e.keycode }));
  uIOhook.on('mousedown', e => bongoSend('bongo:mouse', { down: true, button: e.button }));
  uIOhook.on('mouseup', e => bongoSend('bongo:mouse', { down: false, button: e.button }));
  uIOhook.on('wheel', e => bongoSend('bongo:wheel', { dir: Math.sign(e.rotation || e.amount || 0) }));
  uIOhook.on('mousemove', e => {
    const now = Date.now();
    if (now - bongoMoveT < 16) return;          // ~60 updates/s is plenty
    bongoMoveT = now;
    const d = screen.getDisplayNearestPoint({ x: e.x, y: e.y }).bounds;
    // uiohook reports physical pixels on scaled displays; normalise against the primary size
    const sf = screen.getPrimaryDisplay().scaleFactor || 1;
    bongoSend('bongo:move', { x: (e.x / sf - d.x) / d.width, y: (e.y / sf - d.y) / d.height });
  });
  try { uIOhook.start(); hookOn = true; } catch (e) { dlog('uiohook start failed', e.message); return false; }
  return true;
}
function stopHook() {
  if (!hook || !hookOn) return;
  try { hook.uIOhook.removeAllListeners(); hook.uIOhook.stop(); } catch { /* ignore */ }
  hookOn = false;
}
function openBongo() {
  const c = bongoCfg();
  if (bongoWin && !bongoWin.isDestroyed()) { bongoWin.showInactive(); return; }
  const [bw, bh] = BONGO_SIZE[c.mode] || BONGO_SIZE.cat;
  const w = Math.round(bw * c.scale), h = Math.round(bh * c.scale);
  const wa = screen.getPrimaryDisplay().workArea;
  const x = c.x != null ? c.x : wa.x + 40, y = c.y != null ? c.y : wa.y + wa.height - h - 10;
  bongoWin = new BrowserWindow({
    width: w, height: h, x, y, transparent: true, frame: false, resizable: false, hasShadow: false,
    skipTaskbar: true, alwaysOnTop: true, focusable: false, maximizable: false, fullscreenable: false,
    backgroundColor: '#00000000', show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), backgroundThrottling: false }
  });
  bongoWin.setAlwaysOnTop(true, 'screen-saver');
  bongoWin.setOpacity(Number(c.opacity) || 1);
  if (c.clickThrough) bongoWin.setIgnoreMouseEvents(true, { forward: true });
  bongoWin.loadFile(path.join(__dirname, 'bongo', 'index.html'));
  bongoWin.once('ready-to-show', () => bongoWin.showInactive());
  bongoWin.on('moved', () => {
    if (!bongoWin) return;
    const [nx, ny] = bongoWin.getPosition();
    Object.assign(bongoCfg(), { x: nx, y: ny });
    save();
  });
  bongoWin.on('closed', () => { bongoWin = null; stopHook(); });
  const ok = startHook();
  if (!ok) notify('键鼠映射', '无法启动全局键鼠监听，看板只能显示本程序内的输入');
  c.on = true;
  save();
  refreshTrayMenu();
  broadcast('settings', settings());
}
function closeBongo() {
  const c = bongoCfg();
  c.on = false;
  save();
  if (bongoWin && !bongoWin.isDestroyed()) bongoWin.close();
  stopHook();
  refreshTrayMenu();
  broadcast('settings', settings());
}
function toggleBongo() { if (bongoWin && !bongoWin.isDestroyed()) closeBongo(); else openBongo(); }
// apply size/mode/opacity/click-through changes to an open board
function applyBongo() {
  if (!bongoWin || bongoWin.isDestroyed()) return;
  const c = bongoCfg();
  const [bw, bh] = BONGO_SIZE[c.mode] || BONGO_SIZE.cat;
  const b = bongoWin.getBounds();
  const w = Math.round(bw * c.scale), h = Math.round(bh * c.scale);
  bongoWin.setBounds({ x: b.x, y: b.y + b.height - h, width: w, height: h });
  bongoWin.setOpacity(Number(c.opacity) || 1);
  bongoWin.setIgnoreMouseEvents(!!c.clickThrough, { forward: true });
  bongoSend('bongo:cfg', c);
}
let bongoHotkey = '';
function registerBongoHotkey() {
  if (bongoHotkey) { try { globalShortcut.unregister(bongoHotkey); } catch { /* ignore */ } bongoHotkey = ''; }
  const k = bongoCfg().hotkey;
  if (!k) return;
  try { if (globalShortcut.register(k, toggleBongo)) bongoHotkey = k; } catch (e) { dlog('bongo hotkey failed', e.message); }
}
ipcMain.on('bongo:toggle', () => toggleBongo());
ipcMain.on('bongo:get', e => { e.returnValue = bongoCfg(); });
ipcMain.on('bongo:update', (_e, patch) => {
  const prevKey = bongoCfg().hotkey;
  Object.assign(bongoCfg(), patch || {});
  save();
  applyBongo();
  if (prevKey !== bongoCfg().hotkey) registerBongoHotkey();
  broadcast('settings', settings());
});
ipcMain.on('bongo:drag', (_e, dx, dy) => {
  if (!bongoWin) return;
  const [x, y] = bongoWin.getPosition();
  bongoWin.setPosition(x + dx, y + dy);
});
ipcMain.on('bongo:ignore', (_e, v) => { if (bongoWin && bongoCfg().clickThrough) bongoWin.setIgnoreMouseEvents(v, { forward: true }); });
ipcMain.on('bongo:menu', () => {
  if (!bongoWin) return;
  const c = bongoCfg();
  const set = patch => ipcMain.emit('bongo:update', {}, patch);
  Menu.buildFromTemplate([
    ...[['cat', '猫猫桌面'], ['keyboard', '完整键盘'], ['bongo', '邦戈鼓'], ['piano', '钢琴猫'], ['gamepad', '手柄'], ['strip', '按键条'], ['lkeys', '线条猫·键盘'], ['ldesk', '线条猫·键鼠'], ['lbongo', '线条猫·鼓'], ['ltable', '线条猫·拍桌']]
      .map(([m, label]) => ({ label, type: 'radio', checked: c.mode === m, click: () => set({ mode: m }) })),
    { label: '钢琴音效', type: 'checkbox', checked: !!c.sound, visible: c.mode === 'piano', click: m => set({ sound: m.checked }) },
    { type: 'separator' },
    { label: '大小', submenu: [0.6, 0.8, 1, 1.25, 1.5].map(v => ({ label: `${Math.round(v * 100)}%`, type: 'radio', checked: c.scale === v, click: () => set({ scale: v }) })) },
    { label: '显示按键文字', type: 'checkbox', checked: c.showKeys, click: m => set({ showKeys: m.checked }) },
    { label: '鼠标穿透', type: 'checkbox', checked: c.clickThrough, click: m => set({ clickThrough: m.checked }) },
    { label: '看板设置…', click: () => openHub('bongo') },
    { type: 'separator' },
    { label: '关闭看板', click: closeBongo }
  ]).popup({ window: bongoWin });
});

// ---------- IPC ----------
ipcMain.on('store:get', (e, key) => { e.returnValue = data[key]; });
ipcMain.on('store:set', (_e, key, value) => { data[key] = value; save(); });
ipcMain.on('settings:get', e => { e.returnValue = settings(); });
ipcMain.on('pets:list', e => { e.returnValue = PETS; });
const imageCache = {};
ipcMain.on('pets:image', (e, file) => {
  const f = PETS.includes(file) ? file : PETS[0];
  imageCache[f] = imageCache[f] || 'data:image/png;base64,' + fs.readFileSync(path.join(ASSETS, 'pets', f)).toString('base64');
  e.returnValue = imageCache[f];
});
ipcMain.on('settings:update', (_e, patch) => {
  const prev = { ...settings() };
  data.settings = Object.assign(settings(), patch);
  save();
  applySettings(prev);
});

// drag samples are kept so a quick release flings the pet with that velocity
let dragTrail = [], flingTimer = null;
ipcMain.on('pet:drag', (_e, dx, dy) => {
  if (!petWin) return;
  petDragging = true;
  clearInterval(flingTimer); flingTimer = null;
  const [x, y] = petWin.getPosition();
  petWin.setPosition(x + dx, y + dy);
  const now = Date.now();
  dragTrail.push({ t: now, x: x + dx, y: y + dy });
  dragTrail = dragTrail.filter(p => now - p.t < 90);
});
function savePetPos() {
  if (!petWin) return;
  const [x, y] = petWin.getPosition();
  data.petPos = { x, y };
  save();
}
ipcMain.on('pet:dragEnd', () => {
  petDragging = false;
  if (!petWin) return;
  const trail = dragTrail; dragTrail = [];
  let vx = 0, vy = 0;
  if (trail.length >= 2) {
    const a = trail[0], b = trail[trail.length - 1], dt = Math.max(16, b.t - a.t) / 1000;
    vx = (b.x - a.x) / dt; vy = (b.y - a.y) / dt;
  }
  if (Math.hypot(vx, vy) < 900) { ensureOnScreen(); return savePetPos(); }
  fling(vx, vy);
});
// simple physics: gravity, bounce off the work-area edges, friction on the floor
function fling(vx, vy) {
  clearInterval(flingTimer);
  const cap = 4000;
  const sp = Math.hypot(vx, vy);
  if (sp > cap) { vx *= cap / sp; vy *= cap / sp; }
  let [x, y] = petWin.getPosition();
  const { width: w, height: h } = petWin.getBounds();
  let bounces = 0, still = 0;
  petWin.webContents.send('pet:fling', { phase: 'start' });
  flingTimer = setInterval(() => {
    if (!petWin || petWin.isDestroyed()) return clearInterval(flingTimer);
    const dt = 1 / 60;
    const wa = screen.getDisplayNearestPoint({ x: Math.round(x + w / 2), y: Math.round(y + h / 2) }).workArea;
    // the pet art occupies roughly the lower-middle of the window; let the transparent margin overhang
    const minX = wa.x - w * 0.12, maxX = wa.x + wa.width - w * 0.88;
    const minY = wa.y - h * 0.2, floor = wa.y + wa.height - h * 0.96;
    vy += 2600 * dt;
    x += vx * dt; y += vy * dt;
    let hit = false;
    if (x < minX) { x = minX; vx = -vx * 0.6; hit = true; }
    if (x > maxX) { x = maxX; vx = -vx * 0.6; hit = true; }
    if (y < minY) { y = minY; vy = -vy * 0.5; hit = true; }
    if (y > floor) {
      y = floor;
      if (Math.abs(vy) > 300) { vy = -vy * 0.45; hit = true; }
      else vy = 0;
      vx *= 0.9;
    }
    if (hit && ++bounces <= 6) petWin.webContents.send('pet:fling', { phase: 'bounce' });
    petWin.setPosition(Math.round(x), Math.round(y));
    if (y >= floor && Math.abs(vx) < 20 && vy === 0) still++;
    if (still > 5) {
      clearInterval(flingTimer); flingTimer = null;
      petWin.webContents.send('pet:fling', { phase: 'land', bounces });
      savePetPos();
      if (bounces >= 3) setImmediate(() => bump('flings'));
    }
  }, 1000 / 60);
}
ipcMain.on('pet:ignoreMouse', (_e, ignore) => {
  dlog('ignoreMouse', ignore);
  if (petWin) petWin.setIgnoreMouseEvents(ignore);
});
ipcMain.on('pet:say', (_e, payload) => { if (petWin) petWin.webContents.send('pet:say', payload); });
ipcMain.on('pet:contextMenu', () => {
  if (!petWin) return;
  const s = settings();
  Menu.buildFromTemplate([
    { label: '打开菜单', click: () => openHub('home') },
    { label: '照顾宠物', click: () => openHub('care') },
    { label: bongoWin ? '关闭键鼠映射' : '键鼠映射看板', click: toggleBongo },
    { label: '番茄钟', click: () => openHub('pomodoro') },
    { label: '换个宠物', click: () => openHub('pets') },
    { type: 'separator' },
    { label: '置顶显示', type: 'checkbox', checked: s.alwaysOnTop, click: m => applyPatch({ alwaysOnTop: m.checked }) },
    { label: '随机说话', type: 'checkbox', checked: s.chatter, click: m => applyPatch({ chatter: m.checked }) },
    { label: '散步模式', type: 'checkbox', checked: s.walk, click: m => applyPatch({ walk: m.checked }) },
    { label: '衣橱', click: () => openHub('wardrobe') },
    {
      label: '大小', submenu: [0.7, 0.85, 1, 1.25, 1.5].map(v => ({
        label: `${Math.round(v * 100)}%`, type: 'radio', checked: s.scale === v, click: () => applyPatch({ scale: v })
      }))
    },
    { label: '隐藏宠物', click: () => togglePet() },
    { type: 'separator' },
    { label: '退出', click: () => app.quit() }
  ]).popup({ window: petWin });
});
function applyPatch(patch) {
  const prev = { ...settings() };
  Object.assign(settings(), patch);
  save();
  applySettings(prev);
}

ipcMain.on('hub:open', (_e, page) => { dlog('hub:open', page); openHub(page); });
ipcMain.on('hub:minimize', () => hubWin && hubWin.minimize());
ipcMain.on('hub:toggleMax', () => hubWin && (hubWin.isMaximized() ? hubWin.unmaximize() : hubWin.maximize()));
ipcMain.on('hub:close', () => hubWin && hubWin.hide());
ipcMain.on('app:quit', () => app.quit());
ipcMain.on('debug', (_e, msg) => dlog('renderer', msg));
app.on('child-process-gone', (_e, d) => dlog('child-process-gone', JSON.stringify(d)));

ipcMain.on('pomo:get', e => { e.returnValue = pomoState(); });
ipcMain.on('pomo:start', pomoStart);
ipcMain.on('pomo:pause', pomoPause);
ipcMain.on('pomo:reset', () => pomoSetMode(pomo.mode));
ipcMain.on('pomo:mode', (_e, m) => pomoSetMode(m));
ipcMain.on('pomo:skip', () => { pomo.endAt = Date.now(); pomo.running = true; pomoFinish(); });
ipcMain.on('pomo:cfg', (_e, cfg) => {
  data.pomoCfg = Object.assign(pomoCfg(), cfg);
  save();
  if (!pomo.running) pomo.remaining = pomoDuration(pomo.mode);
  broadcast('pomo', pomoState());
});
ipcMain.on('notify', (_e, title, body) => notify(title, body));

ipcMain.on('care:get', e => { e.returnValue = careState(); });
ipcMain.on('care:action', (e, action, item) => { e.returnValue = careAction(action, item); });
ipcMain.on('care:reward', (_e, coins, reason) => reward(coins, reason));

ipcMain.on('alarms:get', e => { e.returnValue = alarmsState(); });
ipcMain.on('alarms:set', (_e, list) => { data.alarms = list; save(); broadcast('alarms', alarmsState()); });
ipcMain.on('countdowns:set', (_e, list) => { data.countdowns = list; save(); broadcast('alarms', alarmsState()); });

ipcMain.on('sys:get', e => { e.returnValue = sysState(); });

// ---------- quick launcher ----------
// items: { id, name, kind: 'app'|'folder'|'url', target }
const launchIcons = new Map();
ipcMain.handle('launch:pick', async (_e, kind) => {
  const r = await dialog.showOpenDialog(hubWin, kind === 'folder'
    ? { title: '选择文件夹', properties: ['openDirectory'] }
    : { title: '选择程序或文件', properties: ['openFile'], filters: [{ name: '程序 / 快捷方式', extensions: ['exe', 'lnk', 'bat', 'cmd', 'url'] }, { name: '所有文件', extensions: ['*'] }] });
  if (r.canceled || !r.filePaths[0]) return null;
  const target = r.filePaths[0];
  return { target, name: path.basename(target).replace(/\.(exe|lnk|bat|cmd|url)$/i, '') };
});
ipcMain.handle('launch:icon', async (_e, target) => {
  if (launchIcons.has(target)) return launchIcons.get(target);
  let url = null;
  try { url = (await app.getFileIcon(target, { size: 'large' })).toDataURL(); } catch { url = null; }
  launchIcons.set(target, url);
  return url;
});
ipcMain.handle('launch:open', async (_e, item) => {
  if (!item || typeof item.target !== 'string') return { ok: false };
  if (item.kind === 'url') {
    if (!/^https?:\/\//i.test(item.target)) return { ok: false, msg: '网址需要以 http:// 或 https:// 开头' };
    await shell.openExternal(item.target);
    return { ok: true };
  }
  if (!fs.existsSync(item.target)) return { ok: false, msg: '找不到这个路径了' };
  const err = await shell.openPath(item.target);
  return err ? { ok: false, msg: err } : { ok: true };
});

// global hotkey (default Ctrl+Alt+P) toggles the menu window
function registerHotkey() {
  globalShortcut.unregisterAll();
  const key = settings().hotkey;
  if (!key) return;
  try {
    globalShortcut.register(key, () => {
      if (hubWin && hubWin.isVisible() && hubWin.isFocused()) hubWin.hide();
      else openHub(lastHubPage || 'home');
    });
  } catch (e) { dlog('hotkey failed', e.message); }
}
app.on('will-quit', () => { globalShortcut.unregisterAll(); stopHook(); });

ipcMain.on('ach:get', e => { e.returnValue = achState(); });
ipcMain.on('stats:bump', (_e, key) => { if (['streak'].includes(key)) return; bump(key); });
ipcMain.on('stats:set', (_e, key, value) => {
  // stats() rebuilds the object on every call, so grab it once before writing
  const s = stats();
  if (key === 'streak') { s.streak = Math.max(s.streak, Number(value) || 0); checkAchievements(); }
  if (key === 'festival' && value) { s.festival = true; checkAchievements(); }
  if (key === 'catchBest') { s.catchBest = Math.max(s.catchBest || 0, Math.min(1e5, Number(value) || 0)); checkAchievements(); }
});

ipcMain.on('clips:get', e => { e.returnValue = clipList(); });
ipcMain.on('clips:set', (_e, list) => { data.clips = Array.isArray(list) ? list : []; save(); broadcast('clips', clipList()); });
ipcMain.on('clips:copy', (_e, text) => { text = String(text); clipLast = text; clipboard.writeText(text); });

// backup / restore of everything in data.json
ipcMain.handle('data:export', async () => {
  const r = await dialog.showSaveDialog(hubWin, {
    title: '导出备份', defaultPath: `DesktopPet-备份-${today()}.json`, filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (r.canceled || !r.filePath) return { ok: false };
  fs.writeFileSync(r.filePath, JSON.stringify({ app: 'DesktopPet', version: 1, at: Date.now(), data }, null, 1));
  return { ok: true, path: r.filePath };
});
ipcMain.handle('data:import', async () => {
  const r = await dialog.showOpenDialog(hubWin, { title: '导入备份', properties: ['openFile'], filters: [{ name: 'JSON', extensions: ['json'] }] });
  if (r.canceled || !r.filePaths[0]) return { ok: false };
  let parsed;
  try { parsed = JSON.parse(fs.readFileSync(r.filePaths[0], 'utf8')); } catch { return { ok: false, msg: '文件格式不正确' }; }
  if (!parsed || parsed.app !== 'DesktopPet' || typeof parsed.data !== 'object') return { ok: false, msg: '这不是 DesktopPet 的备份文件' };
  data = parsed.data;
  flush();
  app.relaunch();
  app.exit(0);
  return { ok: true };
});

// ---------- lifecycle ----------
app.on('second-instance', () => { togglePet(true); openHub('home'); });
app.whenReady().then(() => {
  settings();
  initThemeBridge();
  onThemeChange(t => { if (hubWin && !hubWin.isDestroyed()) hubWin.setBackgroundColor(t.bg); });
  createPet();
  createTray();
  applySettings(null);
  screen.on('display-removed', ensureOnScreen);
  setInterval(careTick, 60 * 1000);
  setInterval(() => play.tick(), 20 * 1000);
  setTimeout(() => play.tick(), 5000);
  registerBongoHotkey();
  if (bongoCfg().on) setTimeout(openBongo, 1200);
  // build the hub in the background so the first open is instant
  setTimeout(() => { if (!hubWin) createHub('home'); }, 1500);
  setInterval(alarmTick, 1000);
});
// keep running in the tray when the hub closes
app.on('window-all-closed', () => {});
app.on('before-quit', () => { quitting = true; flush(); });
