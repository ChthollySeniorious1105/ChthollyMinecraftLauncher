// 蜘蛛纸牌 — Windows-style Spider Solitaire module for the hub. See ../MODULES.md for the contract.
(function () {
  // ---------- geometry ----------
  const CW = 64, CH = 90, GAP = 8, PAD = 10, NC = 10;
  const TW = PAD * 2 + NC * CW + (NC - 1) * GAP; // 732
  const TH = 500;
  const TOP_Y = 10;
  const BOT_Y = TH - CH - 8;          // row of completed pile + stock
  const MAX_TOP = BOT_Y - 8 - CH;     // lowest top-y a tableau card may reach
  const DOWN_OFF = 8, UP_OFF = 24, MIN_DOWN = 3, MIN_UP = 11;
  const STOCK_X = TW - PAD - CW, STOCK_STEP = 12, DONE_STEP = 16;
  const colX = i => PAD + i * (CW + GAP);

  const REWARD = { 1: 10, 2: 18, 4: 30 };
  const DIFF_NAME = { 1: '单色', 2: '双色', 4: '四色' };
  const SUITS_FOR = { 1: [0, 0, 0, 0, 0, 0, 0, 0], 2: [0, 0, 0, 0, 1, 1, 1, 1], 4: [0, 0, 1, 1, 2, 2, 3, 3] };

  // ---------- card drawing (copied from the Klondike module) ----------
  const RANKS = ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const RED = '#c8001e', BLACK = '#161616';
  const isRed = s => s === 1 || s === 2; // 0 ♠ 1 ♥ 2 ♦ 3 ♣

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

  const SVG_OPEN = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 70 98" width="${CW}" height="${CH}" preserveAspectRatio="none">`;

  const faceCache = {};
  function faceSvg(suit, rank) {
    const key = suit + '_' + rank;
    if (faceCache[key]) return faceCache[key];
    const c = { suit, rank };
    const col = isRed(suit) ? RED : BLACK;
    let body;
    if (rank === 1) body = pip(suit, 35, 49, suit === 0 ? 40 : 32, false);
    else if (rank <= 10) body = PIPS[rank].map(([x, y]) => pip(suit, x, y, 14, y > 49.5)).join('');
    else body = courtSvg(c);
    const cr = corner(c);
    return (faceCache[key] = SVG_OPEN +
      '<rect x="0.5" y="0.5" width="69" height="97" rx="5" fill="#fff" stroke="#555"/>' +
      `<g fill="${col}">${cr}<g transform="rotate(180 35 49)">${cr}</g>${body}</g></svg>`);
  }

  const BACK_SVG = SVG_OPEN +
    '<defs><pattern id="spBackPat" width="8" height="8" patternUnits="userSpaceOnUse">' +
    '<rect width="8" height="8" fill="#1f4fa8"/><path d="M0 4L4 0L8 4L4 8Z" fill="none" stroke="#8fb4f0" stroke-width="0.8"/>' +
    '<circle cx="4" cy="4" r="1" fill="#d8e6ff"/></pattern></defs>' +
    '<rect x="0.5" y="0.5" width="69" height="97" rx="5" fill="#fff" stroke="#555"/>' +
    '<rect x="4" y="4" width="62" height="90" rx="3" fill="url(#spBackPat)" stroke="#123a80" stroke-width="1"/>' +
    '<rect x="7" y="7" width="56" height="84" rx="2" fill="none" stroke="#d8e6ff" stroke-width="0.8" opacity="0.7"/>' +
    '<g transform="translate(35 49)"><path d="M0 -13L9 0L0 13L-9 0Z" fill="#1f4fa8" stroke="#f3d27a" stroke-width="1.4"/>' +
    '<circle r="3.2" fill="#f3d27a"/></g></svg>';

  const fmtTime = s => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'sp-root';
    root.innerHTML = `
      <div class="sp-bar">
        <button type="button" class="sp-btn sp-primary" data-act="new" title="新游戏 (F2)">新游戏</button>
        <button type="button" class="sp-btn" data-act="undo" title="撤销 (Ctrl+Z)">撤销</button>
        <button type="button" class="sp-btn" data-act="hint" title="提示 (H)">提示</button>
        <button type="button" class="sp-btn" data-act="deal" title="发牌 (D)">发牌</button>
        <div class="sp-seg" role="group" aria-label="难度">
          <button type="button" data-suits="1">单色</button><button type="button" data-suits="2">双色</button><button type="button" data-suits="4">四色</button>
        </div>
      </div>
      <div class="sp-table" style="width:${TW}px;height:${TH}px">
        <canvas class="sp-canvas sp-hidden"></canvas>
        <div class="sp-win sp-hidden"><div class="sp-win-title">恭喜通关！</div><div class="sp-win-sub"></div><div class="sp-win-tip">点击开始新游戏</div></div>
      </div>
      <div class="sp-status">
        <span>分数 <b class="sp-score">500</b></span>
        <span>时间 <b class="sp-time">0:00</b></span>
        <span>步数 <b class="sp-moves">0</b></span>
        <span>完成 <b class="sp-done">0/8</b></span>
        <span class="sp-rec"></span>
      </div>`;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const table = $('.sp-table'), canvas = $('.sp-canvas'), bar = $('.sp-bar'), winEl = $('.sp-win');
    const scoreEl = $('.sp-score'), timeEl = $('.sp-time'), movesEl = $('.sp-moves'), doneEl = $('.sp-done'), recEl = $('.sp-rec');
    const undoBtn = bar.querySelector('[data-act="undo"]'), dealBtn = bar.querySelector('[data-act="deal"]');
    const suitBtns = [...bar.querySelectorAll('[data-suits]')];

    // ---------- timers ----------
    const timeouts = new Set();
    function later(fn, ms) {
      const id = setTimeout(() => { timeouts.delete(id); fn(); }, ms);
      timeouts.add(id);
      return id;
    }
    function clearLater() { timeouts.forEach(clearTimeout); timeouts.clear(); }

    // ---------- slots ----------
    function mkSlot(cls, x, y) {
      const d = document.createElement('div');
      d.className = 'sp-slot ' + cls;
      d.style.left = x + 'px'; d.style.top = y + 'px';
      table.appendChild(d);
      return d;
    }
    const tabSlots = [];
    for (let i = 0; i < NC; i++) tabSlots.push(mkSlot('sp-slot-tab', colX(i), TOP_Y));
    mkSlot('sp-slot-done', PAD, BOT_Y);
    const stockSlot = mkSlot('sp-slot-stock', STOCK_X, BOT_Y);

    // ---------- cards ----------
    const cards = [];
    for (let k = 0; k < 8; k++) for (let r = 1; r <= 13; r++) {
      const c = { id: cards.length, set: k, suit: -1, rank: r, up: false, x: NaN, y: NaN, z: 0, el: null };
      const d = document.createElement('div');
      d.className = 'sp-card';
      d.dataset.id = c.id;
      d.innerHTML = `<div class="sp-face"></div><div class="sp-back">${BACK_SVG}</div>`;
      c.el = d;
      c.faceEl = d.firstChild;
      table.appendChild(d);
      cards.push(c);
    }
    const imgCache = {};
    function imgFor(c) {
      const key = c.suit + '_' + c.rank;
      if (!imgCache[key]) {
        const img = new Image();
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(faceSvg(c.suit, c.rank));
        imgCache[key] = img;
      }
      return imgCache[key];
    }

    // ---------- state ----------
    let tab = [], stock = [], done = [];
    let score = 500, moves = 0, elapsed = 0, lastTick = 0, started = false, won = false;
    let history = [];
    let suits = [1, 2, 4].includes(ctx.store.get('suits', 1)) ? ctx.store.get('suits', 1) : 1;
    let drag = null, hintTimer = 0, hintEls = [], hintList = null, hintPos = 0;
    let anim = null;

    const top = p => p[p.length - 1];

    function locate(c) {
      for (let t = 0; t < NC; t++) { const i = tab[t].indexOf(c); if (i >= 0) return { t: 'tab', col: t, idx: i }; }
      if (stock.includes(c)) return { t: 'stock' };
      return { t: 'done' };
    }
    // start index of the movable same-suit descending run at the top of a column
    function runStart(p) {
      let s = p.length - 1;
      if (s < 0 || !p[s].up) return -1;
      while (s > 0) {
        const a = p[s - 1], b = p[s];
        if (!a.up || a.suit !== b.suit || a.rank !== b.rank + 1) break;
        s--;
      }
      return s;
    }
    const canDrop = (c, j) => { const t = top(tab[j]); return !t || t.rank === c.rank + 1; };

    // ---------- layout ----------
    let instant = false;
    function place(c, x, y, z, delay) {
      c.el.classList.toggle('up', c.up);
      c.z = z;
      const dl = delay ? delay + 'ms' : '';
      if (c.el.style.getPropertyValue('--sp-d') !== dl) c.el.style.setProperty('--sp-d', dl);
      if (c.x !== x || c.y !== y) {
        c.x = x; c.y = y;
        c.el.style.left = x + 'px';
        c.el.style.top = y + 'px';
        c.el.style.zIndex = instant ? z : 1000 + z;
      } else {
        c.el.style.zIndex = z;
      }
    }
    function colOffsets(p) {
      let nd = 0, nu = 0;
      for (let k = 0; k < p.length - 1; k++) p[k].up ? nu++ : nd++;
      const avail = MAX_TOP - TOP_Y;
      let dOff = DOWN_OFF, uOff = UP_OFF;
      const total = () => nd * dOff + nu * uOff;
      if (total() > avail && nu) uOff = Math.max(MIN_UP, (avail - nd * dOff) / nu);
      if (total() > avail && nd) dOff = Math.max(MIN_DOWN, (avail - nu * uOff) / nd);
      if (total() > avail && nu) uOff = Math.max(3, (avail - nd * dOff) / nu);
      return [dOff, uOff];
    }
    function layout(delays, inst) {
      instant = !!inst;
      if (instant) table.classList.add('sp-noanim');
      const dl = c => (delays && delays.get(c)) || 0;
      tab.forEach((p, t) => {
        const [dOff, uOff] = colOffsets(p);
        let y = TOP_Y;
        p.forEach((c, i) => { place(c, colX(t), Math.round(y), 1 + i, dl(c)); y += c.up ? uOff : dOff; });
      });
      const groups = Math.ceil(stock.length / 10);
      stock.forEach((c, k) => place(c, STOCK_X - (groups - 1 - Math.floor(k / 10)) * STOCK_STEP, BOT_Y, 1 + k, dl(c)));
      done.forEach((run, k) => run.forEach((c, i) => place(c, PAD + k * DONE_STEP, BOT_Y, 1 + k * 13 + (12 - i), dl(c))));
      stockSlot.classList.toggle('sp-empty', !stock.length);
      if (instant) { void table.offsetWidth; table.classList.remove('sp-noanim'); instant = false; }
    }
    function onTransEnd(e) {
      const d = e.target;
      if (!d.classList || !d.classList.contains('sp-card')) return;
      const c = cards[+d.dataset.id];
      if (!d.classList.contains('sp-dragging')) d.style.zIndex = c.z;
    }

    // ---------- status ----------
    function stats() {
      const all = ctx.store.get('stats', {});
      return all[suits] || { wins: 0, best: null };
    }
    function updateStatus() {
      scoreEl.textContent = score;
      movesEl.textContent = moves;
      doneEl.textContent = done.length + '/8';
      timeEl.textContent = fmtTime(Math.floor(elapsed / 1000));
      const st = stats();
      recEl.textContent = `${DIFF_NAME[suits]} · 胜场 ${st.wins} · 最高分 ${st.best != null ? st.best : '—'}`;
      undoBtn.disabled = !history.length || won;
      dealBtn.disabled = !stock.length || won;
      dealBtn.textContent = stock.length ? `发牌 (${Math.ceil(stock.length / 10)})` : '发牌';
      suitBtns.forEach(b => b.classList.toggle('active', +b.dataset.suits === suits));
    }

    // ---------- history ----------
    function snap() {
      return {
        tab: tab.map(p => p.map(c => c.id)), stock: stock.map(c => c.id), done: done.map(r => r.map(c => c.id)),
        up: cards.map(c => c.up), score, moves
      };
    }
    function restore(s) {
      const m = id => cards[id];
      tab = s.tab.map(p => p.map(m)); stock = s.stock.map(m); done = s.done.map(r => r.map(m));
      cards.forEach((c, i) => { c.up = s.up[i]; });
      score = s.score; moves = s.moves;
    }
    function pushHistory() {
      history.push(snap());
      if (history.length > 2000) history.shift();
    }

    // ---------- game ----------
    function newGame() {
      stopAnim();
      clearLater();
      cancelDrag();
      clearHint();
      const map = SUITS_FOR[suits];
      cards.forEach(c => {
        const s = map[c.set];
        if (c.suit !== s) { c.suit = s; c.faceEl.innerHTML = faceSvg(s, c.rank); }
        c.up = false;
        c.el.style.visibility = '';
        c.el.classList.remove('sp-shake');
      });
      const deck = cards.slice();
      for (let i = deck.length - 1; i > 0; i--) {
        const j = (Math.random() * (i + 1)) | 0;
        const t = deck[i]; deck[i] = deck[j]; deck[j] = t;
      }
      tab = [];
      for (let t = 0; t < NC; t++) {
        const n = t < 4 ? 6 : 5;
        tab.push(deck.splice(0, n));
        top(tab[t]).up = true;
      }
      stock = deck; // 50 cards
      done = [];
      score = 500; moves = 0; elapsed = 0; started = false; won = false; history = [];
      hintList = null;
      winEl.classList.add('sp-hidden');
      // stage cards at the stock, then deal them out
      cards.forEach(c => { c.x = NaN; c.y = NaN; });
      table.classList.add('sp-noanim');
      cards.forEach(c => { c.el.style.left = STOCK_X + 'px'; c.el.style.top = BOT_Y + 'px'; c.el.style.removeProperty('--sp-d'); c.el.classList.toggle('up', false); });
      void table.offsetWidth;
      table.classList.remove('sp-noanim');
      const delays = new Map();
      let k = 0;
      for (let row = 0; row < 6; row++) for (let t = 0; t < NC; t++) if (tab[t][row]) delays.set(tab[t][row], k++ * 12);
      layout(delays);
      updateStatus();
    }

    function startClock() {
      if (!started) { started = true; lastTick = performance.now(); }
    }

    function flipTop(i) {
      const t = top(tab[i]);
      if (t && !t.up) t.up = true;
    }

    // removes any complete K→A same-suit run sitting on top of column i
    function collect(i, delays, base) {
      const p = tab[i];
      if (p.length < 13) return false;
      const s = p.length - 13, k0 = p[s];
      if (k0.rank !== 13 || !k0.up) return false;
      for (let k = 1; k < 13; k++) {
        const c = p[s + k];
        if (!c.up || c.suit !== k0.suit || c.rank !== 13 - k) return false;
      }
      const run = p.splice(s);
      done.push(run);
      score += 100;
      flipTop(i);
      run.forEach((c, k) => delays.set(c, base + (12 - k) * 35)); // A flies first, K last
      return true;
    }

    function after(delays, collected) {
      hintList = null;
      layout(delays);
      updateStatus();
      if (collected) ctx.toast && ctx.toast(done.length < 8 ? `完成一组！(${done.length}/8)` : '全部完成！');
      if (!won && done.length === 8) win();
    }

    function doMove(from, idx, to) {
      clearHint();
      pushHistory(); startClock();
      const moving = tab[from].splice(idx);
      moving.forEach(c => tab[to].push(c));
      flipTop(from);
      score -= 1; moves++;
      const delays = new Map();
      const got = collect(to, delays, 200);
      after(delays, got);
    }

    function deal() {
      if (won) return;
      if (!stock.length) { ctx.toast && ctx.toast('没有可发的牌了'); return; }
      if (tab.some(p => !p.length)) { ctx.toast && ctx.toast('有空列时不能发牌'); flashEmpty(); return; }
      cancelDrag(); clearHint();
      pushHistory(); startClock();
      const delays = new Map();
      for (let i = 0; i < NC; i++) {
        const c = stock.pop();
        c.up = true;
        tab[i].push(c);
        delays.set(c, i * 45);
      }
      score -= 1; moves++;
      let got = false;
      for (let i = 0; i < NC; i++) if (collect(i, delays, 650)) got = true;
      after(delays, got);
    }
    function flashEmpty() {
      const els = tabSlots.filter((s, i) => !tab[i].length);
      showHint(els, 900);
    }

    function undo() {
      if (won || !history.length) return;
      cancelDrag(); clearHint();
      restore(history.pop());
      hintList = null;
      layout();
      updateStatus();
    }

    // ---------- move evaluation ----------
    // value of moving tab[i][idx..] onto column j; <= 0 means pointless / not worth hinting
    function moveValue(i, idx, j, s) {
      const p = tab[i], c = p[idx], below = p[idx - 1], t = top(tab[j]);
      const belowFits = !!below && below.up && below.rank === c.rank + 1;
      if (t) {
        if (t.rank !== c.rank + 1) return -1;
        const same = t.suit === c.suit;
        if (idx > s) return same ? 4 : 0; // splitting a same-suit run
        if (belowFits && !same) return 0;  // lateral shuffle
        let v = same ? 100 + (p.length - idx) : 20;
        if (!below) v += 40;
        else if (!below.up) v += 60;
        else if (belowFits && below.suit !== c.suit && same) v += 10;
        return v;
      }
      // empty target
      if (idx === 0) return 0;
      if (idx > s) return 1;
      if (below && !below.up) return 8;
      return belowFits ? 1 : 3;
    }
    function allMoves() {
      const list = [];
      for (let i = 0; i < NC; i++) {
        const p = tab[i], s = runStart(p);
        if (s < 0) continue;
        for (let idx = s; idx < p.length; idx++) {
          let emptyDone = false;
          for (let j = 0; j < NC; j++) {
            if (j === i || !canDrop(p[idx], j)) continue;
            if (!tab[j].length) { if (emptyDone) continue; emptyDone = true; }
            const v = moveValue(i, idx, j, s);
            if (v > 0) list.push({ i, idx, j, v });
          }
        }
      }
      list.sort((a, b) => b.v - a.v);
      return list;
    }
    function bestTarget(i, idx) {
      const p = tab[i], s = runStart(p);
      let best = -1, bestV = -Infinity;
      for (let d = 1; d < NC; d++) {
        const j = (i + d) % NC;
        if (!canDrop(p[idx], j)) continue;
        let v = moveValue(i, idx, j, s);
        if (!tab[j].length && idx === 0) v = -0.5;
        if (v > bestV) { bestV = v; best = j; }
      }
      return best;
    }

    // ---------- hint ----------
    function clearHint() {
      if (hintTimer) { clearTimeout(hintTimer); hintTimer = 0; }
      hintEls.forEach(e => e.classList.remove('sp-hint'));
      hintEls = [];
    }
    function showHint(els, ms) {
      clearHint();
      hintEls = els;
      els.forEach(e => e.classList.add('sp-hint'));
      hintTimer = setTimeout(clearHint, ms);
    }
    function hint() {
      if (won) return;
      cancelDrag();
      if (!hintList) { hintList = allMoves(); hintPos = 0; }
      if (!hintList.length) {
        if (stock.length && !tab.some(p => !p.length)) {
          showHint(stock.slice(-10).map(c => c.el), 1300);
          ctx.toast && ctx.toast('没有可移动的牌，试试发牌');
        } else if (stock.length) {
          flashEmpty();
          ctx.toast && ctx.toast('请先填满空列再发牌');
        } else {
          clearHint();
          ctx.toast && ctx.toast('没有可用的移动了');
        }
        return;
      }
      const h = hintList[hintPos % hintList.length];
      hintPos++;
      const els = tab[h.i].slice(h.idx).map(c => c.el);
      els.push(tab[h.j].length ? top(tab[h.j]).el : tabSlots[h.j]);
      showHint(els, 1400);
    }

    // ---------- win ----------
    function win() {
      won = true;
      cancelDrag(); clearHint();
      const sec = Math.floor(elapsed / 1000);
      const all = ctx.store.get('stats', {});
      const st = all[suits] || { wins: 0, best: null };
      st.wins = (st.wins || 0) + 1;
      const record = st.best == null || score > st.best;
      if (record) st.best = score;
      all[suits] = st;
      ctx.store.set('stats', all);
      ctx.say('蜘蛛纸牌通关！');
      ctx.reward(REWARD[suits], '蜘蛛纸牌通关');
      winEl.querySelector('.sp-win-sub').textContent =
        `${DIFF_NAME[suits]} · 得分 ${score}${record ? '（新纪录！）' : ''} · 用时 ${fmtTime(sec)} · 小鱼干 +${REWARD[suits]}`;
      updateStatus();
      done.forEach(run => run.forEach(imgFor)); // preload cascade images
      later(startCascade, 1100);
    }

    function startCascade() {
      stopAnim();
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(TW * dpr);
      canvas.height = Math.round(TH * dpr);
      canvas.style.width = TW + 'px';
      canvas.style.height = TH + 'px';
      canvas.classList.remove('sp-hidden');
      winEl.classList.remove('sp-hidden');
      const g = canvas.getContext('2d');
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, TW, TH);
      const queue = [];
      for (let i = 0; i < 13; i++) for (let k = done.length - 1; k >= 0; k--) {
        const c = done[k][i];
        if (c) queue.push({ c, img: imgFor(c) });
      }
      anim = { raf: 0, last: 0, acc: 0, launch: 99, queue, parts: [], g };
      const step = () => {
        const a = anim;
        if (++a.launch >= 7 && a.queue.length) {
          a.launch = 0;
          const q = a.queue.shift();
          q.c.el.style.visibility = 'hidden';
          const dir = Math.random() < 0.3 ? -1 : 1;
          a.parts.push({ img: q.img, x: q.c.x, y: q.c.y, vx: dir * (2 + Math.random() * 4), vy: -2 - Math.random() * 8 });
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
      canvas.classList.add('sp-hidden');
    }
    function onCanvasClick() { newGame(); }

    // ---------- pointer input ----------
    function shake(list) {
      list.forEach(c => {
        c.el.classList.remove('sp-shake');
        void c.el.offsetWidth;
        c.el.classList.add('sp-shake');
      });
      later(() => list.forEach(c => c.el.classList.remove('sp-shake')), 350);
    }
    function onDown(e) {
      if (e.button !== 0 || won || drag) return;
      const d = e.target.closest && e.target.closest('.sp-card, .sp-slot-stock');
      if (!d || !table.contains(d)) return;
      e.preventDefault();
      clearHint();
      if (d === stockSlot) { deal(); return; }
      const c = cards[+d.dataset.id];
      const loc = locate(c);
      if (loc.t === 'stock') { deal(); return; }
      if (loc.t !== 'tab' || !c.up) return;
      const p = tab[loc.col], s = runStart(p);
      if (loc.idx < s) { shake(p.slice(loc.idx).filter(k => k.up)); return; }
      const list = p.slice(loc.idx);
      drag = {
        from: loc.col, idx: loc.idx, cards: list, sx: e.clientX, sy: e.clientY,
        orig: list.map(k => [k.x, k.y]), started: false, pid: e.pointerId, dx: 0, dy: 0
      };
    }
    function onMove(e) {
      if (!drag || e.pointerId !== drag.pid) return;
      const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
      if (!drag.started) {
        if (dx * dx + dy * dy < 16) return;
        drag.started = true;
        drag.cards.forEach((c, k) => {
          c.el.classList.add('sp-dragging');
          c.el.style.removeProperty('--sp-d');
          c.el.style.zIndex = 3000 + k;
        });
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
      const first = d.cards[0];
      const x = d.orig[0][0] + d.dx, y = d.orig[0][1] + d.dy;
      let best = -1, bestA = 0;
      for (let j = 0; j < NC; j++) {
        if (j === d.from || !canDrop(first, j)) continue;
        const t = top(tab[j]);
        const a = overlap(x, y, colX(j), t ? t.y : TOP_Y);
        if (a > bestA) { bestA = a; best = j; }
      }
      return best;
    }
    function endDrag(ok) {
      if (!drag) return;
      const d = drag;
      drag = null;
      if (!d.started) {
        if (ok) { // plain click: auto-move to the best target
          const j = bestTarget(d.from, d.idx);
          if (j >= 0) doMove(d.from, d.idx, j);
          else shake(d.cards);
        }
        return;
      }
      d.cards.forEach(c => c.el.classList.remove('sp-dragging'));
      const target = ok ? dropTarget(d) : -1;
      if (target >= 0) doMove(d.from, d.idx, target);
      else { d.cards.forEach(c => { c.x = NaN; }); layout(); }
    }
    function onUp(e) { if (drag && e.pointerId === drag.pid) endDrag(true); }
    function onCancel(e) { if (drag && e.pointerId === drag.pid) endDrag(false); }
    function cancelDrag() { endDrag(false); }
    function onBlur() { cancelDrag(); }
    function onCtx(e) { e.preventDefault(); }

    function onBar(e) {
      const b = e.target.closest('button');
      if (!b) return;
      b.blur();
      if (b.dataset.suits) {
        const n = +b.dataset.suits;
        if (n === suits) return;
        suits = n;
        ctx.store.set('suits', n);
        newGame();
        ctx.toast && ctx.toast(`${DIFF_NAME[n]}模式：新游戏`);
        return;
      }
      const act = b.dataset.act;
      if (act === 'new') newGame();
      else if (act === 'undo') undo();
      else if (act === 'hint') hint();
      else if (act === 'deal') deal();
    }

    function onKey(e) {
      if (!ctx.isActive()) return;
      if (e.key === 'F2') { e.preventDefault(); newGame(); }
      else if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); }
      else if (e.ctrlKey || e.metaKey || e.altKey) return;
      else if (e.key === 'h' || e.key === 'H') { e.preventDefault(); hint(); }
      else if (e.key === 'd' || e.key === 'D') { e.preventDefault(); deal(); }
    }

    // ---------- clock ----------
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
    bar.addEventListener('click', onBar);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
    window.addEventListener('blur', onBlur);
    window.addEventListener('keydown', onKey);

    newGame();

    cleanup = () => {
      clearInterval(timer);
      clearLater();
      clearHint();
      stopAnim();
      drag = null;
      table.removeEventListener('pointerdown', onDown);
      table.removeEventListener('transitionend', onTransEnd);
      table.removeEventListener('contextmenu', onCtx);
      canvas.removeEventListener('click', onCanvasClick);
      bar.removeEventListener('click', onBar);
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onCancel);
      window.removeEventListener('blur', onBlur);
      window.removeEventListener('keydown', onKey);
      root.remove();
    };
  }

  Hub.register({
    id: 'spider',
    title: '蜘蛛纸牌',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
      '<ellipse cx="12" cy="14" rx="3.2" ry="4" fill="currentColor" fill-opacity="0.2"/><circle cx="12" cy="8.2" r="2.2" fill="currentColor"/>' +
      '<path d="M9 12L5 9L3 5M9 14H4L2 12M9 16L5 18L4 21M15 12L19 9L21 5M15 14H20L22 12M15 16L19 18L20 21"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
