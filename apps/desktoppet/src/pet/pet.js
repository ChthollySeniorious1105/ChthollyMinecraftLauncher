(function () {
const api = window.api;
const $ = id => document.getElementById(id);
const stage = $('stage'), petImg = $('pet'), bubble = $('bubble'), bubbleText = $('bubble-text');
const fx = $('fx'), menuBtn = $('menu-btn'), badge = $('pomo-badge'), badgeTime = $('pomo-time');
const quick = $('quick'), needBadge = $('need-badge');
const body = $('pet-body'), wearEl = $('wear'), wrap = $('pet-wrap');
const anchors = window.PET_ANCHORS || {};
function renderWear(c) {
  const a = anchors[settings.pet];
  wearEl.innerHTML = '';
  if (!a || !c || !c.equipped) return;
  for (const id of Object.values(c.equipped)) {
    const it = Wardrobe.ITEMS[id];
    if (!it) continue;
    const p = Wardrobe.place(it, a);
    const holder = document.createElement('div');
    holder.innerHTML = it.svg;
    const svg = holder.firstElementChild;
    Object.assign(svg.style, { left: `${p.left * 100}%`, top: `${p.top * 100}%`, width: `${p.width * 100}%`, height: `${p.height * 100}%`, transform: `rotate(${p.rot || 0}deg)` });
    wearEl.appendChild(svg);
  }
}
api.pet.onWalk(w => {
  body.classList.toggle('walking', !!w.walking && !body.classList.contains('dragging'));
  if (w.walking) wrap.classList.toggle('flip', w.dir < 0);
});

let settings = api.settings.get();

// ---------- pet image & alpha hit-testing ----------
let alphaMask = null; // { w, h, data }
function loadPet(file) {
  petImg.src = api.petImage(file);
  petImg.onload = () => {
    const c = document.createElement('canvas');
    c.width = petImg.naturalWidth; c.height = petImg.naturalHeight;
    const g = c.getContext('2d');
    g.drawImage(petImg, 0, 0);
    alphaMask = { w: c.width, h: c.height, data: g.getImageData(0, 0, c.width, c.height).data };
  };
}
loadPet(settings.pet);

function overPet(x, y) {
  if (!alphaMask) return false;
  const r = petImg.getBoundingClientRect();
  if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;
  const px = Math.floor((x - r.left) / r.width * alphaMask.w);
  const py = Math.floor((y - r.top) / r.height * alphaMask.h);
  return alphaMask.data[(py * alphaMask.w + px) * 4 + 3] > 24;
}
function overElement(el, x, y) {
  if (el.classList.contains('hidden')) return false;
  const r = el.getBoundingClientRect();
  return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
}

// The window ignores the mouse (click-through) except where the pet or controls are.
let ignoring = true, hoverTimer = null;
function setIgnore(v) {
  if (v === ignoring) return;
  ignoring = v;
  api.pet.ignoreMouse(v);
}
function hitTest(x, y) {
  if (dragging || down) return;
  const hit = overPet(x, y) || overElement(menuBtn, x, y) || overElement(badge, x, y) ||
    overElement(bubble, x, y) || overElement(quick, x, y) || overElement(needBadge, x, y);
  setIgnore(!hit);
  if (hit) {
    stage.classList.add('hover');
    quick.classList.remove('hidden');
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => { stage.classList.remove('hover'); quick.classList.add('hidden'); }, 2500);
  }
}
// main process polls the cursor (forwarded mousemove is unreliable on transparent windows).
// The polled point is only used to wake the window up: getCursorScreenPoint occasionally
// returns a mis-scaled point, and trusting it while interactive made clicks fall through.
// Once the window takes the mouse, real mousemove/mouseleave events drive hit-testing.
api.pet.onHover(p => {
  if (!ignoring) return;
  if (p) hitTest(p.x, p.y);
});
window.addEventListener('mousemove', e => hitTest(e.clientX, e.clientY));
document.addEventListener('mouseleave', () => { if (!dragging && !down) setIgnore(true); });

// ---------- dragging & clicking ----------
let dragging = false, down = null, moved = false;
petImg.addEventListener('mousedown', e => {
  if (e.button !== 0) return;
  down = { x: e.screenX, y: e.screenY };
  moved = false;
});
window.addEventListener('mousemove', e => {
  if (!down) return;
  const dx = e.screenX - down.x, dy = e.screenY - down.y;
  if (!moved && Math.hypot(dx, dy) < 4) return;
  if (!moved) { moved = true; dragging = true; setMood(null); body.classList.add('dragging'); }
  api.pet.drag(dx, dy);
  down = { x: e.screenX, y: e.screenY };
});
window.addEventListener('mouseup', () => {
  if (!down) return;
  down = null;
  if (dragging) {
    dragging = false;
    body.classList.remove('dragging');
    api.pet.dragEnd();
    setTimeout(() => { if (!body.classList.contains('dragging')) say(pick(['放我下来啦~', '呼，到新家了！', '这里视野不错！']), 2500); }, 60);
  } else {
    poke();
  }
  lastActive = Date.now();
});
petImg.addEventListener('dblclick', () => api.hub.open('home'));
window.addEventListener('contextmenu', e => { e.preventDefault(); api.pet.contextMenu(); });
menuBtn.addEventListener('click', () => api.hub.open('home'));
badge.addEventListener('click', () => api.hub.open('pomodoro'));
bubble.addEventListener('click', hideBubble);
needBadge.addEventListener('click', () => api.hub.open(trip ? 'adventure' : 'care'));

// ---------- quick actions & care ----------
const FOODS = ['fish', 'onigiri', 'cake', 'icecream', 'apple', 'milk'];
quick.addEventListener('click', e => {
  const b = e.target.closest('button');
  if (!b) return;
  const q = b.dataset.q;
  if (q === 'care') return api.hub.open('care');
  if (q === 'focus') return api.hub.open('pomodoro');
  if (q === 'play') {
    const r = api.care.action('play');
    if (r.ok) { setMood('happy'); spawn(NOTE, 3); } else if (r.msg) say(r.msg, 2500);
    return;
  }
  // feed: use the best food in the bag, otherwise buy an apple
  const c = api.care.get();
  let food = FOODS.find(f => c.inventory[f]);
  if (!food) {
    const buy = api.care.action('buy', 'apple');
    if (!buy.ok) { say('背包里没有吃的，小鱼干也不够了…去玩游戏赚一点吧！', 4000); return; }
    food = 'apple';
  }
  const r = api.care.action('use', food);
  if (r.ok) { setMood('jump'); spawn(HEART, 3); }
});
// while the pet is out on an adventure it fades out and the badge shows the trip instead of needs
let trip = null, lastCare = api.care.get();
function renderCare(c) {
  lastCare = c;
  const away = trip && trip.end > Date.now(), back = trip && trip.end <= Date.now();
  stage.classList.toggle('away', !!away);
  needBadge.classList.toggle('trip', !!trip);
  if (trip) {
    needBadge.classList.remove('hidden');
    const left = Math.ceil((trip.end - Date.now()) / 60e3);
    needBadge.textContent = back ? '🎁 带回礼物啦' : `🎒 探险中 · ${left >= 60 ? Math.floor(left / 60) + ' 小时 ' + (left % 60) + ' 分' : left + ' 分钟'}`;
    return;
  }
  const low = [['hunger', '🍙 饿了'], ['clean', '🛁 想洗澡'], ['energy', '💤 困了'], ['mood', '💔 无聊']]
    .filter(([k]) => c[k] < 25).sort((a, b) => c[a[0]] - c[b[0]])[0];
  needBadge.classList.toggle('hidden', !low);
  if (low) needBadge.textContent = low[1];
}
function onPlay(p) { trip = p.trip; renderCare(lastCare); }
onPlay(api.play.get());
api.play.onChange(onPlay);
setInterval(() => { if (trip) renderCare(lastCare); }, 30e3);
renderWear(lastCare);
api.care.onChange(c => { renderCare(c); renderWear(c); });

// alarm rings: keep bouncing until the pet is clicked
let ringTimer = null;
api.alarms.onRing(() => {
  clearInterval(ringTimer);
  let n = 0;
  ringTimer = setInterval(() => { setMood('jump'); if (++n > 10) clearInterval(ringTimer); }, 1500);
});
window.addEventListener('mousedown', () => clearInterval(ringTimer));

let pokes = [];
function poke() {
  const now = Date.now();
  pokes = pokes.filter(t => now - t < 2000);
  pokes.push(now);
  if (pokes.length >= 5) {
    pokes = [];
    setMood('shake');
    say(pick(['别戳啦，好晕~', '再戳我要生气了！', '哼！😤']), 2500);
    return;
  }
  setMood('jump');
  spawn(HEART, 3);
  api.care.action('pet');
  if (Math.random() < .6) say(pick(POKE_LINES), 2500);
}

// ---------- moods / animations ----------
let moodTimer = null;
function setMood(m, ms) {
  clearTimeout(moodTimer);
  body.classList.remove('jump', 'shake', 'happy', 'sleep');
  if (!m) return;
  void body.offsetWidth; // restart animation
  body.classList.add(m);
  if (m !== 'sleep') moodTimer = setTimeout(() => body.classList.remove(m), ms || 1800);
}

const HEART = '<svg viewBox="0 0 24 24"><path d="M12 21s-7.5-4.6-9.5-9.2C1 8.2 3.3 4.5 6.9 4.5c2.1 0 3.6 1.1 4.6 2.6 1-1.5 2.5-2.6 4.6-2.6 3.6 0 5.9 3.7 4.4 7.3C19.5 16.4 12 21 12 21z" fill="#f06f7e" stroke="#fff" stroke-width="1.2"/></svg>';
const ZZZ = '<svg viewBox="0 0 24 24"><text x="4" y="19" font-size="18" font-weight="700" font-family="Arial" fill="#8aa6d6" stroke="#fff" stroke-width=".8">z</text></svg>';
const NOTE = '<svg viewBox="0 0 24 24"><path d="M9 17.5V5l11-2v12.5" fill="none" stroke="#e8793a" stroke-width="2"/><ellipse cx="6.5" cy="17.5" rx="3" ry="2.4" fill="#e8793a"/><ellipse cx="17.5" cy="15.5" rx="3" ry="2.4" fill="#e8793a"/></svg>';
const STAR = '<svg viewBox="0 0 24 24"><path d="M12 2.5l2.9 6 6.6.9-4.8 4.6 1.2 6.5L12 17.4l-5.9 3.1 1.2-6.5L2.5 9.4l6.6-.9z" fill="#f7c948" stroke="#fff" stroke-width="1"/></svg>';

function spawn(svg, n) {
  for (let i = 0; i < n; i++) {
    setTimeout(() => {
      const d = document.createElement('div');
      d.className = 'fx-item';
      d.innerHTML = svg;
      d.style.left = `${25 + Math.random() * 50}%`;
      d.style.top = `${15 + Math.random() * 25}%`;
      fx.appendChild(d);
      setTimeout(() => d.remove(), 1700);
    }, i * 180);
  }
}

// ---------- speech ----------
let bubbleTimer = null;
function say(text, ms = 4000) {
  bubbleText.textContent = text;
  bubble.classList.remove('hidden');
  clearTimeout(bubbleTimer);
  bubbleTimer = setTimeout(hideBubble, ms);
}
function hideBubble() { bubble.classList.add('hidden'); }
const pick = a => a[Math.floor(Math.random() * a.length)];

api.pet.onSay(({ text, mood, ms }) => {
  wake();
  say(text, ms || 5000);
  if (mood === 'happy') { setMood('happy'); spawn(STAR, 4); }
  else if (mood === 'alert') setMood('jump');
  else if (mood === 'sad') setMood('shake');
});

const POKE_LINES = ['嘿嘿~', '你好呀！', '摸摸头~', '今天也要加油哦！', '嗯？找我有事吗？', '好痒~', '陪你一起工作~'];
function greeting() {
  const h = new Date().getHours();
  if (h < 5) return '这么晚还没睡？早点休息哦 🌙';
  if (h < 9) return '早上好！新的一天开始啦 ☀️';
  if (h < 12) return '上午好！喝杯水再开始吧~';
  if (h < 14) return '中午啦，记得吃午饭哦 🍚';
  if (h < 18) return '下午好！累了就休息一下~';
  if (h < 22) return '晚上好！今天辛苦啦~';
  return '夜深了，早点休息吧 🌙';
}
const IDLE_LINES = [
  '要不要来一局扫雷？', '2048 还没通关哦~', '来个番茄钟专注一下？', '伸个懒腰吧~',
  '记得眨眨眼睛~', '今天的待办完成了吗？', '我在这里陪着你哦', '坐直一点，保护腰椎！',
  '来一局五子棋吗？我可厉害了', '今天签到了吗？有小鱼干拿哦', '要不要放点白噪音？', '纠结的时候可以用转盘帮你决定~',
  () => `现在是 ${new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}`
];

// ---------- idle behaviour ----------
let lastActive = Date.now(), sleeping = false;
function wake() {
  lastActive = Date.now();
  if (sleeping) { sleeping = false; setMood(null); }
}
window.addEventListener('mousedown', wake);
setInterval(() => {
  const idle = Date.now() - lastActive;
  if (!sleeping && idle > 5 * 60 * 1000) {
    sleeping = true;
    setMood('sleep');
    return;
  }
  if (sleeping) { spawn(ZZZ, 1); return; }
  if (settings.chatter && Math.random() < .12 && bubble.classList.contains('hidden')) {
    const line = pick(IDLE_LINES);
    say(typeof line === 'function' ? line() : line, 4500);
    if (Math.random() < .5) spawn(NOTE, 2);
  }
}, 15000);

// ---------- pomodoro badge ----------
function fmt(ms) {
  const s = Math.ceil(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}
function renderPomo(p) {
  const active = p.running || p.remaining < p.total;
  badge.classList.toggle('hidden', !active);
  badge.classList.toggle('rest', p.mode !== 'work');
  badge.classList.toggle('paused', !p.running);
  badgeTime.textContent = fmt(p.remaining);
}
renderPomo(api.pomo.get());
api.pomo.onChange(renderPomo);

// colours follow the CML launcher; greet the new look when it changes
PetTheme.init((t, prev) => { if (t.id !== prev.id) { setMood('happy'); say(`换上「${t.name}」主题啦~`, 2500); } });
api.settings.onChange(s => {
  const changed = s.pet !== settings.pet;
  settings = s;
  if (changed) { loadPet(s.pet); renderWear(api.care.get()); setMood('jump'); say('换好啦，喜欢吗？', 3000); }
});

// festivals: a special greeting (and a small hat of confetti) on the day
const FEST_LINES = {
  '春节': '新年快乐！恭喜发财，红包拿来~ 🧧', '除夕': '除夕快乐！一起守岁吧 🏮', '元宵节': '元宵节快乐！吃汤圆了吗？',
  '端午节': '端午安康！粽子要甜的还是咸的？', '七夕': '七夕快乐！今天也有我陪你 💕', '中秋节': '中秋快乐！月饼分我一口嘛 🥮',
  '重阳节': '重阳节快乐！记得问候长辈哦', '元旦': '元旦快乐！新的一年也请多关照~', '情人节': '情人节快乐！送你一颗小心心 💗',
  '劳动节': '劳动节快乐！今天好好休息吧', '儿童节': '儿童节快乐！今天我们都是小朋友 🎈', '国庆节': '国庆节快乐！出去玩了吗？',
  '圣诞节': '圣诞快乐！🎄 叮叮当~', '平安夜': '平安夜快乐！吃苹果了吗？🍎', '万圣夜': 'Trick or treat！🎃 不给糖就捣蛋~',
  '教师节': '教师节快乐！谢谢所有的老师~', '母亲节': '母亲节快乐！给妈妈打个电话吧', '父亲节': '父亲节快乐！记得问候爸爸哦',
  '腊八节': '腊八节快乐！喝腊八粥啦', '小年': '小年快乐！年味越来越浓啦', '清明节': '清明时节，注意休息~', '中元节': '中元节，早点回家哦'
};
function festivalToday() {
  try {
    const f = window.PetFestivals && window.PetFestivals.festivalsOn(new Date());
    return f && f.find(x => FEST_LINES[x]);
  } catch { return null; }
}
setTimeout(() => {
  setMood('jump');
  const fest = festivalToday();
  if (fest) { say(FEST_LINES[fest], 8000); spawn(STAR, 6); api.ach.set('festival', true); }
  else say(greeting(), 5000);
}, 600);

// flung around the screen
api.pet.onFling(f => {
  if (f.phase === 'start') { body.classList.add('dragging'); say(pick(['哇啊啊啊——', '飞起来啦！', '救命呀~']), 1500); }
  else if (f.phase === 'bounce') { setMood('shake', 400); }
  else if (f.phase === 'land') {
    body.classList.remove('dragging');
    setMood(f.bounces >= 3 ? 'shake' : 'jump');
    say(f.bounces >= 3 ? pick(['头好晕…@_@', '再扔我就生气了！', '转得我眼冒金星~']) : pick(['安全着陆！', '好刺激！再来一次？']), 3000);
  }
});
})();
