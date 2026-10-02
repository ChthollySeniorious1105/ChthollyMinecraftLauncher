// 空当接龙 — Microsoft-Windows-style FreeCell module for the hub. See ../MODULES.md for the contract.
(function () {
  // ---------- geometry ----------
  const CW = 66, CH = 92, GAP = 14, PAD = 14;
  const TOP_Y = 12, TAB_Y = TOP_Y + CH + 18;
  const TW = PAD * 2 + 8 * CW + 7 * GAP; // 654
  const TH = 486;
  const FAN = 26;
  const colX = i => PAD + i * (CW + GAP);
  const MAX_GAME = 32000;

  const RANKS = ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const RED = '#c8001e', BLACK = '#161616';
  const isRed = s => s === 1 || s === 2; // 0 ♠ 1 ♥ 2 ♦ 3 ♣

  // ---------- card faces (drawing approach copied from solitaire.js) ----------
  const SUIT_SHAPE = [
    '<path d="M10 1C10 1 1.5 8 1.5 12.2C1.5 14.8 3.5 16.5 5.8 16.5C7.3 16.5 8.5 15.8 9.2 14.8C9 16.6 8.3 18 7 19L13 19C11.7 18 11 16.6 10.8 14.8C11.5 15.8 12.7 16.5 14.2 16.5C16.5 16.5 18.5 14.8 18.5 12.2C18.5 8 10 1 10 1Z"/>',
    '<path d="M10 18.5C10 18.5 1 12.5 1 6.6C1 3.6 3.3 1.5 6 1.5C7.8 1.5 9.3 2.6 10 4C10.7 2.6 12.2 1.5 14 1.5C16.7 1.5 19 3.6 19 6.6C19 12.5 10 18.5 10 18.5Z"/>',
    '<path d="M10 1L17.2 10L10 19L2.8 10Z"/>',
    '<circle cx="10" cy="5.6" r="4.2"/><circle cx="5.1" cy="11.6" r="4.2"/><circle cx="14.9" cy="11.6" r="4.2"/>' +
      '<path d="M9 10L11 10C11 14.5 12 17.3 13.8 19L6.2 19C8 17.3 9 14.5 9 10Z"/>'
  ];

  function pip(s, cx, cy, size, flip) {
    return `<g transform="translate(${cx} ${cy}) scale(${(size / 20).toFixed(3)})${flip ? ' rotate(180)' : ''} translate(-10 -10)">${SUIT_SHAPE[s]}</g>`;
  }

  const L = 22, M = 35, R = 48;
  const Y1 = 20, Y5 = 78, YM = 49, Y2 = 39.3, Y3 = 58.7;
  const PIPS = {
    2: [[M, Y1], [M, Y5]],
    3: [[M, Y1], [M, YM], [M, Y5]],
    4: [[L, Y1], [R, Y1], [L, Y5], [R, Y5]],
    5: [[L, Y1], [R, Y1], [M, YM], [L, Y5], [R, Y5]],
    6: [[L, Y1], [R, Y1], [L, YM], [R, YM], [L, Y5], [R, Y5]],
    7: [[L, Y1], [R, Y1], [M, 34.5], [L, YM], [R, YM], [L, Y5], [R, Y5]],
    8: [[L, Y1], [R, Y1], [M, 34.5], [L, YM], [R, YM], [M, 63.5], [L, Y5], [R, Y5]],
    9: [[L, Y1], [R, Y1], [L, Y2], [R, Y2], [M, YM], [L, Y3], [R, Y3], [L, Y5], [R, Y5]],
    10: [[L, Y1], [R, Y1], [M, 29.7], [L, Y2], [R, Y2], [L, Y3], [R, Y3], [M, 68.3], [L, Y5], [R, Y5]]
  };

  function corner(c) {
    const r = RANKS[c.rank], ten = r === '10';
    return `<text x="8" y="15" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="bold" ` +
      `font-size="${ten ? 11.5 : 14}"${ten ? ' letter-spacing="-1"' : ''}>${r}</text>` + pip(c.suit, 8, 24, 9, false);
  }

  const GOLD = 'fill="#e2b53a" stroke="#8a6414" stroke-width="0.8" stroke-linejoin="round"';
  const ORNAMENT = {
    13: `<path d="M24 36L24 25.5L29.5 30.5L35 21.5L40.5 30.5L46 25.5L46 36Z" ${GOLD}/>` +
      `<circle cx="24" cy="25" r="1.6" ${GOLD}/><circle cx="35" cy="21" r="1.8" ${GOLD}/><circle cx="46" cy="25" r="1.6" ${GOLD}/>` +
      '<rect x="24" y="34" width="22" height="3" fill="#8a6414"/>',
    12: `<path d="M26 36L27 28L31 32L35 25L39 32L43 28L44 36Z" ${GOLD}/>` +
      `<circle cx="27" cy="27.5" r="1.3" ${GOLD}/><circle cx="35" cy="24.5" r="1.5" ${GOLD}/><circle cx="43" cy="27.5" r="1.3" ${GOLD}/>` +
      '<circle cx="35" cy="32.5" r="1.4" fill="#c8001e"/>',
    11: `<path d="M26 36Q27 25 35 25Q43 25 44 36Z" ${GOLD}/>` +
      '<path d="M40 27Q46 20 51 16" fill="none" stroke="#2c7a3a" stroke-width="1.6" stroke-linecap="round"/>' +
      '<rect x="25" y="34.5" width="20" height="2.5" fill="#8a6414"/>'
  };

  function courtSvg(c) {
    const tint = isRed(c.suit) ? '#fde9e4' : '#e5ebf6';
    const col = isRed(c.suit) ? RED : BLACK;
    return `<rect x="15" y="9" width="40" height="80" rx="2" fill="${tint}" stroke="${col}" stroke-width="1"/>` +
      '<rect x="17.5" y="11.5" width="35" height="75" rx="1" fill="none" stroke="#c9a227" stroke-width="0.8"/>' +
      pip(c.suit, 21.5, 17.5, 7, false) + pip(c.suit, 48.5, 80.5, 7, true) +
      ORNAMENT[c.rank] +
      '<path d="M22 41H48M22 70H48" stroke="#c9a227" stroke-width="0.8"/>' +
      `<text x="35" y="65" text-anchor="middle" font-family="Georgia,'Times New Roman',serif" font-weight="bold" font-size="28">${RANKS[c.rank]}</text>` +
      pip(c.suit, 35, 77.5, 10, false);
  }

  function faceSvg(c) {
    const col = isRed(c.suit) ? RED : BLACK;
    let body;
    if (c.rank === 1) body = pip(c.suit, 35, 49, c.suit === 0 ? 40 : 32, false);
    else if (c.rank <= 10) body = PIPS[c.rank].map(([x, y]) => pip(c.suit, x, y, 14, y > 49.5)).join('');
    else body = courtSvg(c);
    const cr = corner(c);
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 70 98" width="70" height="98">` +
      '<rect x="0.5" y="0.5" width="69" height="97" rx="5" fill="#fff" stroke="#555"/>' +
      `<g fill="${col}">${cr}<g transform="rotate(180 35 49)">${cr}</g>${body}</g></svg>`;
  }

  // ---------- Microsoft deal generator ----------
  // MS card index k: rank = k>>2 (0 = A), suit = k&3 (0 ♣ 1 ♦ 2 ♥ 3 ♠). Our suits: 0 ♠ 1 ♥ 2 ♦ 3 ♣.
  const MS_SUIT = [3, 2, 1, 0];
  function msDeal(num) {
    let seed = num;
    const rand = () => {
      seed = (seed * 214013 + 2531011) % 2147483648;
      return (seed >> 16) & 0x7fff;
    };
    const deck = [];
    for (let k = 0; k < 52; k++) deck.push(MS_SUIT[k & 3] * 13 + (k >> 2)); // our card id = suit*13 + rank-1
    const cols = [[], [], [], [], [], [], [], []];
    let left = 52;
    for (let i = 0; i < 52; i++) {
      const j = rand() % left;
      cols[i % 8].push(deck[j]);
      deck[j] = deck[--left];
    }
    return cols;
  }

  const fmtTime = s => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  const randGame = () => 1 + Math.floor(Math.random() * MAX_GAME);

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'fc-root';
    root.innerHTML = `
      <div class="fc-bar">
        <button type="button" class="fc-btn fc-primary" data-act="new" title="随机新游戏 (F2)">新游戏</button>
        <button type="button" class="fc-btn" data-act="restart" title="重玩本局">重玩</button>
        <button type="button" class="fc-btn" data-act="undo" title="撤销 (Ctrl+Z)">撤销</button>
        <span class="fc-pick">
          <span>牌局</span>
          <input class="fc-num" type="number" min="1" max="${MAX_GAME}" step="1" placeholder="1-${MAX_GAME}">
          <button type="button" class="fc-btn" data-act="go">开始</button>
        </span>
      </div>
      <div class="fc-table" style="width:${TW}px;height:${TH}px">
        <canvas class="fc-canvas fc-hidden"></canvas>
        <div class="fc-over fc-hidden">
          <div class="fc-over-box">
            <div class="fc-over-title">无路可走</div>
            <div class="fc-over-text">已经没有合法的移动了。</div>
            <div class="fc-over-btns">
              <button type="button" class="fc-btn fc-primary" data-act="undo">撤销</button>
              <button type="button" class="fc-btn" data-act="restart">重玩本局</button>
              <button type="button" class="fc-btn" data-act="new">新游戏</button>
            </div>
          </div>
        </div>
      </div>
      <div class="fc-status">
        <span class="fc-gameno">游戏 #<b class="fc-gnum">0</b></span>
        <span>步数 <b class="fc-moves">0</b></span>
        <span>时间 <b class="fc-time">0:00</b></span>
        <span class="fc-rec"></span>
      </div>`;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const table = $('.fc-table'), canvas = $('.fc-canvas'), bar = $('.fc-bar'), over = $('.fc-over');
    const numInput = $('.fc-num');
    const gnumEl = $('.fc-gnum'), timeEl = $('.fc-time'), movesEl = $('.fc-moves'), recEl = $('.fc-rec');
    const undoBtn = bar.querySelector('[data-act="undo"]');

    // ---------- slots ----------
    function mkSlot(cls, x, y, html, loc) {
      const d = document.createElement('div');
      d.className = 'fc-slot ' + cls;
      d.style.left = x + 'px'; d.style.top = y + 'px';
      d.innerHTML = html || '';
      d.dataset.t = loc.t; d.dataset.i = loc.i;
      table.appendChild(d);
      return d;
    }
    [0, 1, 2, 3].forEach(i => mkSlot('fc-slot-cell', colX(i), TOP_Y, '', { t: 'cell', i }));
    [0, 1, 2, 3].forEach(i => mkSlot('fc-slot-found', colX(4 + i), TOP_Y, '<span>A</span>', { t: 'found', i }));
    [0, 1, 2, 3, 4, 5, 6, 7].forEach(i => mkSlot('fc-slot-tab', colX(i), TAB_Y, '', { t: 'tab', i }));

    // ---------- cards ----------
    const cards = [];
    for (let s = 0; s < 4; s++) for (let r = 1; r <= 13; r++) {
      const c = { id: cards.length, suit: s, rank: r, x: NaN, y: NaN, z: 0, el: null, svg: '' };
      c.svg = faceSvg(c);
      const d = document.createElement('div');
      d.className = 'fc-card';
      d.dataset.id = c.id;
      d.innerHTML = `<div class="fc-face">${c.svg}</div>`;
      c.el = d;
      table.appendChild(d);
      cards.push(c);
    }

    // ---------- state ----------
    let cells = [[], [], [], []], found = [[], [], [], []], tab = [[], [], [], [], [], [], [], []];
    let gameNo = 0, moves = 0, elapsed = 0, lastTick = 0, started = false, won = false, stuck = false;
    let history = [];
    let drag = null, down = null, sel = null, lastClick = null, autoTimer = 0, anim = null;

    const colorOf = c => isRed(c.suit) ? 1 : 0;
    const top = p => p[p.length - 1];
    const pileOf = loc => loc.t === 'cell' ? cells[loc.i] : loc.t === 'found' ? found[loc.i] : tab[loc.i];
    const sameLoc = (a, b) => a && b && a.t === b.t && a.i === b.i;

    function locate(c) {
      for (const [t, arr] of [['tab', tab], ['cell', cells], ['found', found]]) {
        for (let i = 0; i < arr.length; i++) {
          const k = arr[i].indexOf(c);
          if (k >= 0) return { loc: { t, i }, idx: k };
        }
      }
      return null;
    }
    const fits = (c, t) => colorOf(t) !== colorOf(c) && t.rank === c.rank + 1;
    function canStack(c, pile) { const t = top(pile); return !t || fits(c, t); }
    function canFound(c, f) {
      const t = top(found[f]);
      return t ? t.suit === c.suit && t.rank + 1 === c.rank : c.rank === 1;
    }
    function foundFor(c) {
      for (let f = 0; f < 4; f++) if (found[f].length && canFound(c, f)) return f;
      if (c.rank === 1) for (let f = 0; f < 4; f++) if (!found[f].length) return f;
      return -1;
    }
    function runStart(pile) {
      if (!pile.length) return 0;
      let k = pile.length - 1;
      while (k > 0 && fits(pile[k], pile[k - 1])) k--;
      return k;
    }
    const freeCells = () => cells.filter(p => !p.length).length;
    const emptyCols = () => tab.filter(p => !p.length).length;
    // supermove: (1 + free cells) * 2^(empty columns), with the target column not counted when it is empty
    function maxMove(toEmpty) {
      const e = emptyCols() - (toEmpty ? 1 : 0);
      return (1 + freeCells()) * Math.pow(2, Math.max(0, e));
    }
    function suitLevel(s) {
      const p = found.find(f => f.length && f[0].suit === s);
      return p ? p.length : 0;
    }
    // Windows rule: auto-play only when both opposite-color cards of rank-1 are already on foundations
    function isSafe(c) {
      if (c.rank <= 2) return true;
      for (let s = 0; s < 4; s++) if (isRed(s) !== isRed(c.suit) && suitLevel(s) < c.rank - 1) return false;
      return true;
    }

    // ---------- layout ----------
    let instant = false;
    function place(c, x, y, z) {
      c.z = z;
      if (c.x !== x || c.y !== y) {
        c.x = x; c.y = y;
        c.el.style.left = x + 'px';
        c.el.style.top = y + 'px';
        c.el.style.zIndex = instant ? z : 1000 + z;
      } else {
        c.el.style.zIndex = z;
      }
    }
    function fanOff(n) {
      const avail = TH - TAB_Y - CH - 8;
      return n > 1 ? Math.min(FAN, avail / (n - 1)) : FAN;
    }
    function layout(inst) {
      instant = !!inst;
      if (instant) table.classList.add('fc-noanim');
      cells.forEach((p, i) => p.forEach(c => place(c, colX(i), TOP_Y, 1)));
      found.forEach((p, f) => p.forEach((c, i) => place(c, colX(4 + f), TOP_Y, 1 + i)));
      tab.forEach((p, t) => {
        const off = fanOff(p.length);
        p.forEach((c, i) => place(c, colX(t), Math.round(TAB_Y + i * off), 1 + i));
      });
      cards.forEach(c => c.el.classList.remove('fc-sel'));
      if (sel) pileOf(sel.loc).slice(sel.idx).forEach(c => c.el.classList.add('fc-sel'));
      if (instant) { void table.offsetWidth; table.classList.remove('fc-noanim'); instant = false; }
    }
    function onTransEnd(e) {
      const d = e.target;
      if (!d.classList || !d.classList.contains('fc-card')) return;
      if (!d.classList.contains('fc-dragging')) d.style.zIndex = cards[+d.dataset.id].z;
    }

    // ---------- status ----------
    function updateStatus() {
      gnumEl.textContent = gameNo;
      movesEl.textContent = moves;
      timeEl.textContent = fmtTime(Math.floor(elapsed / 1000));
      const wins = ctx.store.get('wins', 0), played = ctx.store.get('played', 0);
      const streak = ctx.store.get('streak', 0), bestStreak = ctx.store.get('bestStreak', 0);
      const pct = played ? Math.round(wins * 100 / played) : 0;
      recEl.textContent = `胜 ${wins}/${played}（${pct}%）· 连胜 ${streak} · 最长 ${bestStreak}`;
      undoBtn.disabled = !history.length || won;
    }

    // ---------- history ----------
    function snap() {
      return { cells: cells.map(p => p.map(c => c.id)), found: found.map(p => p.map(c => c.id)), tab: tab.map(p => p.map(c => c.id)), moves };
    }
    function restore(s) {
      const m = id => cards[id];
      cells = s.cells.map(p => p.map(m)); found = s.found.map(p => p.map(m)); tab = s.tab.map(p => p.map(m));
      moves = s.moves;
    }

    // ---------- game ----------
    function abandonCheck() {
      if (started && !won) ctx.store.set('streak', 0);
    }
    function newGame(num) {
      abandonCheck();
      stopAnim(); stopAuto(); cancelDrag(); hideStuck();
      sel = null; lastClick = null;
      gameNo = num;
      numInput.value = '';
      const cols = msDeal(num);
      tab = cols.map(col => col.map(id => cards[id]));
      cells = [[], [], [], []]; found = [[], [], [], []];
      cards.forEach(c => { c.el.style.visibility = ''; c.x = NaN; });
      moves = 0; elapsed = 0; started = false; won = false; history = [];
      layout(true);
      updateStatus();
      autoTimer = setTimeout(autoStep, 250);
    }

    function startClock() {
      if (started) return;
      started = true;
      lastTick = performance.now();
      ctx.store.set('played', ctx.store.get('played', 0) + 1);
    }

    // returns '' on success or an error message
    function checkMove(from, idx, to) {
      if (won || sameLoc(from, to) || from.t === 'found') return '不能这样移动';
      const sp = pileOf(from), dp = pileOf(to);
      const n = sp.length - idx;
      if (n <= 0) return '不能这样移动';
      if (from.t === 'tab' && idx < runStart(sp)) return '不能这样移动';
      const c = sp[idx];
      if (to.t === 'cell') return n === 1 && !dp.length ? '' : '不能这样移动';
      if (to.t === 'found') return n === 1 && canFound(c, to.i) ? '' : '不能这样移动';
      if (!canStack(c, dp)) return '不能这样移动';
      const cap = maxMove(!dp.length);
      if (n > cap) return `空当不足：当前最多只能移动 ${cap} 张牌`;
      return '';
    }
    function doMove(from, idx, to, auto) {
      const sp = pileOf(from), dp = pileOf(to);
      sp.splice(idx).forEach(c => dp.push(c));
      if (!auto) moves++;
    }
    function userMove(from, idx, to) {
      flushAuto();
      const err = checkMove(from, idx, to);
      if (err) { ctx.toast && ctx.toast(err); return false; }
      history.push(snap());
      if (history.length > 2000) history.shift();
      startClock();
      sel = null;
      doMove(from, idx, to, false);
      layout();
      updateStatus();
      stopAuto();
      if (checkWin()) return true;
      autoTimer = setTimeout(autoStep, 120);
      return true;
    }

    function findSafe() {
      const srcs = [];
      cells.forEach((p, i) => { if (p.length) srcs.push({ loc: { t: 'cell', i }, idx: 0, c: p[0] }); });
      tab.forEach((p, i) => { if (p.length) srcs.push({ loc: { t: 'tab', i }, idx: p.length - 1, c: top(p) }); });
      srcs.sort((a, b) => a.c.rank - b.c.rank);
      for (const s of srcs) {
        if (!isSafe(s.c)) continue;
        const f = foundFor(s.c);
        if (f >= 0) return { from: s.loc, idx: s.idx, to: { t: 'found', i: f } };
      }
      return null;
    }
    function autoStep() {
      autoTimer = 0;
      if (won) return;
      const m = findSafe();
      if (m) {
        if (sel && sameLoc(sel.loc, m.from)) sel = null;
        doMove(m.from, m.idx, m.to, true);
        layout();
        if (checkWin()) return;
        autoTimer = setTimeout(autoStep, 90);
        return;
      }
      settled();
    }
    function flushAuto() {
      if (!autoTimer) return;
      clearTimeout(autoTimer); autoTimer = 0;
      let m;
      while (!won && (m = findSafe())) {
        if (sel && sameLoc(sel.loc, m.from)) sel = null;
        doMove(m.from, m.idx, m.to, true);
      }
      layout();
      settled();
    }
    function stopAuto() { if (autoTimer) { clearTimeout(autoTimer); autoTimer = 0; } }
    function settled() {
      if (checkWin()) return;
      updateStatus();
      if (!won && !hasMoves()) showStuck();
    }

    function hasMoves() {
      const free = freeCells(), empty = emptyCols();
      if (free && tab.some(p => p.length)) return true;
      if (empty && (cells.some(p => p.length) || tab.some(p => p.length > 1))) return true;
      const tops = [];
      cells.forEach(p => { if (p.length) tops.push(p[0]); });
      tab.forEach(p => { if (p.length) tops.push(top(p)); });
      if (tops.some(c => foundFor(c) >= 0)) return true;
      const cap = maxMove(false);
      for (const c of cells.map(p => p[0]).filter(Boolean)) {
        if (tab.some(p => p.length && fits(c, top(p)))) return true;
      }
      for (let i = 0; i < 8; i++) {
        const p = tab[i];
        if (!p.length) continue;
        for (let k = Math.max(runStart(p), p.length - cap); k < p.length; k++) {
          for (let j = 0; j < 8; j++) if (j !== i && tab[j].length && fits(p[k], top(tab[j]))) return true;
        }
      }
      return false;
    }
    function showStuck() {
      stuck = true;
      over.classList.remove('fc-hidden');
      ctx.toast && ctx.toast('无路可走了');
    }
    function hideStuck() { stuck = false; over.classList.add('fc-hidden'); }

    function undo() {
      if (won || !history.length) return;
      stopAuto(); cancelDrag(); hideStuck();
      sel = null; lastClick = null;
      restore(history.pop());
      layout();
      updateStatus();
    }

    // ---------- win ----------
    function checkWin() {
      if (won || !found.every(p => p.length === 13)) return false;
      won = true;
      stopAuto(); hideStuck();
      sel = null;
      const sec = Math.floor(elapsed / 1000);
      const wins = ctx.store.get('wins', 0) + 1;
      ctx.store.set('wins', wins);
      const streak = ctx.store.get('streak', 0) + 1;
      ctx.store.set('streak', streak);
      if (streak > ctx.store.get('bestStreak', 0)) ctx.store.set('bestStreak', streak);
      const best = ctx.store.get('best', null);
      const record = best == null || sec < best;
      if (record) ctx.store.set('best', sec);
      ctx.say('空当接龙通关！');
      ctx.reward(12, '空当接龙通关');
      ctx.toast && ctx.toast(`游戏 #${gameNo} 通关！用时 ${fmtTime(sec)}，${moves} 步${record ? '（最佳用时！）' : ''}`);
      updateStatus();
      startCascade();
      return true;
    }

    function startCascade() {
      stopAnim();
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(TW * dpr);
      canvas.height = Math.round(TH * dpr);
      canvas.style.width = TW + 'px';
      canvas.style.height = TH + 'px';
      canvas.classList.remove('fc-hidden');
      const g = canvas.getContext('2d');
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, TW, TH);
      const queue = [];
      for (let r = 13; r >= 1; r--) for (let f = 0; f < 4; f++) {
        const c = found[f][r - 1];
        if (!c) continue;
        const img = new Image();
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(c.svg);
        queue.push({ c, img, f });
      }
      anim = { raf: 0, last: 0, acc: 0, launch: 18, queue, parts: [], g };
      const step = () => {
        const a = anim;
        if (++a.launch >= 18 && a.queue.length) {
          a.launch = 0;
          const q = a.queue.shift();
          q.c.el.style.visibility = 'hidden';
          const dir = Math.random() < 0.5 ? -1 : 1;
          a.parts.push({ img: q.img, x: colX(4 + q.f), y: TOP_Y, vx: dir * (2 + Math.random() * 4), vy: -1 - Math.random() * 8 });
        }
        for (let k = a.parts.length - 1; k >= 0; k--) {
          const p = a.parts[k];
          p.vy += 0.5; p.x += p.vx; p.y += p.vy;
          if (p.y > TH - CH) { p.y = TH - CH; p.vy = -p.vy * 0.75; }
          if (p.x + CW < 0 || p.x > TW) { a.parts.splice(k, 1); continue; }
          if (p.img.complete && p.img.naturalWidth) a.g.drawImage(p.img, p.x, p.y, CW, CH);
        }
      };
      const frame = t => {
        if (!anim) return;
        if (!anim.last) anim.last = t;
        const dt = Math.min(50, t - anim.last);
        anim.last = t;
        if (ctx.isActive()) {
          anim.acc += dt;
          while (anim.acc >= 16.67) { step(); anim.acc -= 16.67; }
        }
        if (!anim.queue.length && !anim.parts.length) { anim.raf = 0; return; }
        anim.raf = requestAnimationFrame(frame);
      };
      anim.raf = requestAnimationFrame(frame);
    }
    function stopAnim() {
      if (anim && anim.raf) cancelAnimationFrame(anim.raf);
      anim = null;
      canvas.classList.add('fc-hidden');
    }
    function onCanvasClick() { newGame(randGame()); }

    // ---------- click / select (Windows style) ----------
    function handleDouble(c) {
      const L = locate(c);
      sel = null;
      if (!L || L.loc.t === 'found' || L.idx !== pileOf(L.loc).length - 1) { layout(); return; }
      const f = foundFor(c);
      if (f >= 0) { userMove(L.loc, L.idx, { t: 'found', i: f }); return; }
      if (L.loc.t === 'tab') {
        const ci = cells.findIndex(p => !p.length);
        if (ci >= 0) { userMove(L.loc, L.idx, { t: 'cell', i: ci }); return; }
      }
      layout();
    }

    function moveSelectionTo(to) {
      const from = sel.loc, sp = pileOf(from), dp = pileOf(to);
      let idx = sp.length - 1;
      if (from.t === 'tab' && to.t === 'tab') {
        const rs = runStart(sp);
        if (dp.length) {
          idx = -1;
          for (let k = rs; k < sp.length; k++) if (fits(sp[k], top(dp))) { idx = k; break; }
          if (idx < 0) { sel = null; layout(); ctx.toast && ctx.toast('不能这样移动'); return; }
        } else {
          idx = Math.max(sel.idx, rs, sp.length - maxMove(true));
        }
      }
      sel = null;
      if (!userMove(from, idx, to)) layout();
    }

    function handleClick(loc, idx, c) {
      const now = performance.now();
      if (c && lastClick && lastClick.id === c.id && now - lastClick.t < 380) {
        lastClick = null;
        handleDouble(c);
        return;
      }
      lastClick = c ? { id: c.id, t: now } : null;
      if (sel) {
        if (sameLoc(sel.loc, loc)) { sel = null; layout(); return; }
        moveSelectionTo(loc);
        lastClick = null;
        return;
      }
      if (!c || loc.t === 'found') return;
      const p = pileOf(loc);
      sel = { loc, idx: loc.t === 'tab' ? Math.max(idx, runStart(p)) : 0 };
      layout();
    }

    // ---------- pointer input ----------
    function hitLoc(target) {
      const d = target.closest && target.closest('.fc-card, .fc-slot');
      if (!d || !table.contains(d)) return null;
      if (d.classList.contains('fc-card')) {
        const c = cards[+d.dataset.id], L = locate(c);
        return L ? { loc: L.loc, idx: L.idx, c } : null;
      }
      return { loc: { t: d.dataset.t, i: +d.dataset.i }, idx: -1, c: null };
    }
    function onDown(e) {
      if (e.button !== 0 || won || stuck) return;
      const h = hitLoc(e.target);
      if (!h) return;
      e.preventDefault();
      flushAuto();
      if (won || stuck) return;
      const hc = h.c ? locate(h.c) : null; // re-locate after auto moves
      if (h.c && !hc) return;
      if (hc) { h.loc = hc.loc; h.idx = hc.idx; }
      down = { h, sx: e.clientX, sy: e.clientY, pid: e.pointerId };
      const p = h.c ? pileOf(h.loc) : null;
      const draggable = h.c && !sel && (h.loc.t === 'cell' || (h.loc.t === 'tab' && h.idx >= runStart(p)));
      if (draggable) {
        const moving = p.slice(h.idx);
        drag = { from: h.loc, idx: h.idx, cards: moving, orig: moving.map(k => [k.x, k.y]), started: false, dx: 0, dy: 0 };
      }
    }
    function onMove(e) {
      if (!down || e.pointerId !== down.pid || !drag) return;
      const dx = e.clientX - down.sx, dy = e.clientY - down.sy;
      if (!drag.started) {
        if (dx * dx + dy * dy < 16) return;
        drag.started = true;
        lastClick = null;
        drag.cards.forEach((c, k) => { c.el.classList.add('fc-dragging'); c.el.style.zIndex = 3000 + k; });
      }
      drag.cards.forEach((c, k) => {
        c.el.style.left = (drag.orig[k][0] + dx) + 'px';
        c.el.style.top = (drag.orig[k][1] + dy) + 'px';
      });
      drag.dx = dx; drag.dy = dy;
    }
    function overlap(ax, ay, bx, by) {
      const w = Math.min(ax, bx) + CW - Math.max(ax, bx), h = Math.min(ay, by) + CH - Math.max(ay, by);
      return w > 0 && h > 0 ? w * h : 0;
    }
    function dropTarget(d) {
      const x = d.orig[0][0] + d.dx, y = d.orig[0][1] + d.dy;
      const cands = [];
      for (let i = 0; i < 8; i++) {
        const t = top(tab[i]);
        cands.push({ loc: { t: 'tab', i }, a: overlap(x, y, t ? t.x : colX(i), t ? t.y : TAB_Y) });
      }
      for (let i = 0; i < 4; i++) {
        cands.push({ loc: { t: 'cell', i }, a: overlap(x, y, colX(i), TOP_Y) });
        cands.push({ loc: { t: 'found', i }, a: overlap(x, y, colX(4 + i), TOP_Y) });
      }
      const hits = cands.filter(k => k.a > 0 && !sameLoc(k.loc, d.from)).sort((a, b) => b.a - a.a);
      const ok = hits.find(k => !checkMove(d.from, d.idx, k.loc));
      if (ok) return { loc: ok.loc };
      return hits.length ? { err: checkMove(d.from, d.idx, hits[0].loc) } : null;
    }
    function endDrag(ok) {
      const d = drag;
      drag = null;
      if (!d || !d.started) return;
      d.cards.forEach(c => c.el.classList.remove('fc-dragging'));
      const t = ok ? dropTarget(d) : null;
      if (t && t.loc) { userMove(d.from, d.idx, t.loc); return; }
      if (t && t.err && t.err !== '不能这样移动') ctx.toast && ctx.toast(t.err);
      d.cards.forEach(c => { c.x = NaN; });
      layout();
    }
    function onUp(e) {
      if (!down || e.pointerId !== down.pid) return;
      const dn = down;
      down = null;
      if (drag && drag.started) { endDrag(true); return; }
      drag = null;
      handleClick(dn.h.loc, dn.h.idx, dn.h.c);
    }
    function onCancel(e) { if (down && e.pointerId === down.pid) { down = null; endDrag(false); } }
    function cancelDrag() { down = null; endDrag(false); }
    function onBlur() { cancelDrag(); }
    function onCtx(e) { e.preventDefault(); }

    function startNumbered() {
      const n = Math.floor(+numInput.value);
      if (!(n >= 1 && n <= MAX_GAME)) { ctx.toast && ctx.toast(`请输入 1-${MAX_GAME} 之间的牌局编号`); return; }
      newGame(n);
    }
    function onRootClick(e) {
      const b = e.target.closest('button[data-act]');
      if (!b || !root.contains(b)) return;
      b.blur();
      const act = b.dataset.act;
      if (act === 'new') newGame(randGame());
      else if (act === 'restart') newGame(gameNo);
      else if (act === 'undo') undo();
      else if (act === 'go') startNumbered();
    }
    function onNumKey(e) { if (e.key === 'Enter') { e.preventDefault(); startNumbered(); } }

    function onKey(e) {
      if (!ctx.isActive()) return;
      const inInput = e.target && e.target.tagName === 'INPUT';
      if (e.key === 'F2') { e.preventDefault(); newGame(randGame()); }
      else if (!inInput && (e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); }
      else if (!inInput && e.key === 'Escape' && sel) { sel = null; layout(); }
    }

    // ---------- timer ----------
    const timer = setInterval(() => {
      const now = performance.now();
      if (started && !won) {
        if (ctx.isActive()) elapsed += Math.min(now - lastTick, 1000);
        timeEl.textContent = fmtTime(Math.floor(elapsed / 1000));
      }
      lastTick = now;
    }, 250);

    table.addEventListener('pointerdown', onDown);
    table.addEventListener('transitionend', onTransEnd);
    table.addEventListener('contextmenu', onCtx);
    canvas.addEventListener('click', onCanvasClick);
    root.addEventListener('click', onRootClick);
    numInput.addEventListener('keydown', onNumKey);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
    window.addEventListener('blur', onBlur);
    window.addEventListener('keydown', onKey);

    newGame(randGame());

    cleanup = () => {
      clearInterval(timer);
      stopAuto();
      stopAnim();
      drag = null; down = null;
      table.removeEventListener('pointerdown', onDown);
      table.removeEventListener('transitionend', onTransEnd);
      table.removeEventListener('contextmenu', onCtx);
      canvas.removeEventListener('click', onCanvasClick);
      root.removeEventListener('click', onRootClick);
      numInput.removeEventListener('keydown', onNumKey);
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onCancel);
      window.removeEventListener('blur', onBlur);
      window.removeEventListener('keydown', onKey);
      root.remove();
    };
  }

  Hub.register({
    id: 'freecell',
    title: '空当接龙',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="2.5" y="3" width="8" height="8" rx="1.5" stroke-dasharray="2.5 1.8"/><rect x="13.5" y="3" width="8" height="8" rx="1.5" fill="currentColor" fill-opacity="0.15"/><rect x="2.5" y="13" width="8" height="8" rx="1.5"/><rect x="13.5" y="13" width="8" height="8" rx="1.5"/><path d="M17.5 5.2c-1.2 1.1-2 1.9-2 2.7 0 .7.5 1.1 1.1 1.1.4 0 .7-.2.9-.5.2.3.5.5.9.5.6 0 1.1-.4 1.1-1.1 0-.8-.8-1.6-2-2.7z" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
