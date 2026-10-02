// 纸牌接龙 — classic Windows-style Klondike Solitaire module for the hub. See ../MODULES.md for the contract.
(function () {
  // ---------- geometry ----------
  const CW = 70, CH = 98, GAP = 20, PAD = 14;
  const TOP_Y = 12, TAB_Y = TOP_Y + CH + 16;
  const TW = PAD * 2 + 7 * CW + 6 * GAP; // 598
  const TH = 450;
  const DOWN_OFF = 7, UP_OFF = 22, FAN = 16;
  const colX = i => PAD + i * (CW + GAP);

  const RANKS = ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const RED = '#c8001e', BLACK = '#161616';
  const isRed = s => s === 1 || s === 2; // 0 ♠ 1 ♥ 2 ♦ 3 ♣

  // suit shapes in a 20x20 box
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

  // classic blue lattice card back
  const BACK_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 70 98" width="70" height="98">' +
    '<defs><pattern id="solBackPat" width="8" height="8" patternUnits="userSpaceOnUse">' +
    '<rect width="8" height="8" fill="#1f4fa8"/><path d="M0 4L4 0L8 4L4 8Z" fill="none" stroke="#8fb4f0" stroke-width="0.8"/>' +
    '<circle cx="4" cy="4" r="1" fill="#d8e6ff"/></pattern></defs>' +
    '<rect x="0.5" y="0.5" width="69" height="97" rx="5" fill="#fff" stroke="#555"/>' +
    '<rect x="4" y="4" width="62" height="90" rx="3" fill="url(#solBackPat)" stroke="#123a80" stroke-width="1"/>' +
    '<rect x="7" y="7" width="56" height="84" rx="2" fill="none" stroke="#d8e6ff" stroke-width="0.8" opacity="0.7"/>' +
    '<g transform="translate(35 49)"><path d="M0 -13L9 0L0 13L-9 0Z" fill="#1f4fa8" stroke="#f3d27a" stroke-width="1.4"/>' +
    '<circle r="3.2" fill="#f3d27a"/></g></svg>';

  const fmtTime = s => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'sol-root';
    root.innerHTML = `
      <div class="sol-bar">
        <button type="button" class="sol-btn sol-primary" data-act="new" title="新游戏 (F2)">新游戏</button>
        <button type="button" class="sol-btn" data-act="undo" title="撤销 (Ctrl+Z)">撤销</button>
        <button type="button" class="sol-btn" data-act="hint">提示</button>
        <button type="button" class="sol-btn sol-auto" data-act="auto">自动完成</button>
        <div class="sol-seg" role="group" aria-label="抽牌">
          <button type="button" data-draw="1">抽 1 张</button><button type="button" data-draw="3">抽 3 张</button>
        </div>
      </div>
      <div class="sol-table" style="width:${TW}px;height:${TH}px"><canvas class="sol-canvas hidden"></canvas></div>
      <div class="sol-status">
        <span>分数 <b class="sol-score">0</b></span>
        <span>时间 <b class="sol-time">0:00</b></span>
        <span>步数 <b class="sol-moves">0</b></span>
        <span class="sol-rec"></span>
      </div>`;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const table = $('.sol-table'), canvas = $('.sol-canvas'), bar = $('.sol-bar');
    const scoreEl = $('.sol-score'), timeEl = $('.sol-time'), movesEl = $('.sol-moves'), recEl = $('.sol-rec');
    const undoBtn = bar.querySelector('[data-act="undo"]'), autoBtn = bar.querySelector('[data-act="auto"]');
    const drawBtns = [...bar.querySelectorAll('[data-draw]')];

    // ---------- slots ----------
    function mkSlot(cls, x, y, html) {
      const d = document.createElement('div');
      d.className = 'sol-slot ' + cls;
      d.style.left = x + 'px'; d.style.top = y + 'px';
      d.innerHTML = html || '';
      table.appendChild(d);
      return d;
    }
    const stockSlot = mkSlot('sol-slot-stock', colX(0), TOP_Y,
      '<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="12" fill="none" stroke="currentColor" stroke-width="4"/></svg>');
    const foundSlots = [0, 1, 2, 3].map(f => mkSlot('sol-slot-found', colX(3 + f), TOP_Y, '<span>A</span>'));
    const tabSlots = [0, 1, 2, 3, 4, 5, 6].map(i => mkSlot('sol-slot-tab', colX(i), TAB_Y));

    // ---------- cards ----------
    const cards = [];
    for (let s = 0; s < 4; s++) for (let r = 1; r <= 13; r++) {
      const c = { id: cards.length, suit: s, rank: r, up: false, x: NaN, y: NaN, z: 0, el: null, svg: '' };
      c.svg = faceSvg(c);
      const d = document.createElement('div');
      d.className = 'sol-card';
      d.dataset.id = c.id;
      d.innerHTML = `<div class="sol-face">${c.svg}</div><div class="sol-back">${BACK_SVG}</div>`;
      c.el = d;
      table.appendChild(d);
      cards.push(c);
    }

    // ---------- state ----------
    let stock = [], waste = [], found = [[], [], [], []], tab = [[], [], [], [], [], [], []];
    let score = 0, moves = 0, elapsed = 0, lastTick = 0, started = false, won = false, wasteFan = 0;
    let history = [];
    let drawN = ctx.store.get('draw', 1) === 3 ? 3 : 1;
    let drag = null, autoTimer = 0, hintTimer = 0, hintEls = [];
    let anim = null;

    const colorOf = c => isRed(c.suit) ? 1 : 0;
    const top = p => p[p.length - 1];

    function pileOf(loc) {
      if (loc.t === 'stock') return stock;
      if (loc.t === 'waste') return waste;
      if (loc.t === 'found') return found[loc.i];
      return tab[loc.i];
    }
    function locate(c) {
      let i = stock.indexOf(c); if (i >= 0) return { loc: { t: 'stock' }, idx: i };
      i = waste.indexOf(c); if (i >= 0) return { loc: { t: 'waste' }, idx: i };
      for (let f = 0; f < 4; f++) { i = found[f].indexOf(c); if (i >= 0) return { loc: { t: 'found', i: f }, idx: i }; }
      for (let t = 0; t < 7; t++) { i = tab[t].indexOf(c); if (i >= 0) return { loc: { t: 'tab', i: t }, idx: i }; }
      return null;
    }
    function canTab(c, pile) {
      const t = top(pile);
      if (!t) return c.rank === 13;
      return t.up && colorOf(t) !== colorOf(c) && t.rank === c.rank + 1;
    }
    function canFound(c, f) {
      const t = top(found[f]);
      if (!t) return c.rank === 1;
      return t.suit === c.suit && t.rank + 1 === c.rank;
    }
    function foundFor(c) {
      for (let f = 0; f < 4; f++) if (found[f].length && canFound(c, f)) return f;
      if (c.rank === 1) for (let f = 0; f < 4; f++) if (!found[f].length) return f;
      return -1;
    }
    function validSeq(pile, idx) {
      for (let k = idx; k < pile.length; k++) {
        const c = pile[k];
        if (!c.up) return false;
        if (k > idx) { const p = pile[k - 1]; if (p.rank !== c.rank + 1 || colorOf(p) === colorOf(c)) return false; }
      }
      return true;
    }

    // ---------- layout ----------
    let instant = false;
    function place(c, x, y, z) {
      c.el.classList.toggle('up', c.up);
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
    function layout(inst) {
      instant = !!inst;
      if (instant) table.classList.add('sol-noanim');
      stock.forEach((c, i) => place(c, colX(0) + Math.floor(i / 8), TOP_Y + Math.floor(i / 8), 1 + i));
      const n = waste.length;
      const fanStart = drawN === 3 ? n - Math.max(1, Math.min(wasteFan, n)) : n;
      waste.forEach((c, i) => place(c, colX(1) + (i > fanStart ? (i - fanStart) * FAN : 0), TOP_Y, 1 + i));
      found.forEach((p, f) => p.forEach((c, i) => place(c, colX(3 + f), TOP_Y, 1 + i)));
      tab.forEach((p, t) => {
        let downs = 0, ups = 0;
        p.forEach(c => c.up ? ups++ : downs++);
        const avail = TH - TAB_Y - CH - 6 - downs * DOWN_OFF;
        const upOff = ups > 1 ? Math.min(UP_OFF, avail / (ups - 1)) : UP_OFF;
        let y = TAB_Y;
        p.forEach((c, i) => { place(c, colX(t), Math.round(y), 1 + i); y += c.up ? upOff : DOWN_OFF; });
      });
      stockSlot.classList.toggle('sol-empty-dead', !stock.length && !waste.length);
      if (instant) { void table.offsetWidth; table.classList.remove('sol-noanim'); instant = false; }
    }
    function onTransEnd(e) {
      const d = e.target.closest && e.target.closest('.sol-card');
      if (!d || d !== e.target) return;
      const c = cards[+d.dataset.id];
      if (!d.classList.contains('sol-dragging')) d.style.zIndex = c.z;
    }

    // ---------- status ----------
    function updateStatus() {
      scoreEl.textContent = score;
      movesEl.textContent = moves;
      timeEl.textContent = fmtTime(Math.floor(elapsed / 1000));
      const wins = ctx.store.get('wins', 0), best = ctx.store.get('best', null);
      recEl.textContent = `胜场 ${wins} · 最佳 ${best != null ? fmtTime(best) : '—'}`;
      undoBtn.disabled = !history.length || won || !!autoTimer;
      const ca = canAuto();
      autoBtn.disabled = !ca;
      autoBtn.classList.toggle('sol-ready', ca);
      drawBtns.forEach(b => b.classList.toggle('active', +b.dataset.draw === drawN));
    }

    // ---------- history ----------
    function snap() {
      return {
        stock: stock.map(c => c.id), waste: waste.map(c => c.id),
        found: found.map(p => p.map(c => c.id)), tab: tab.map(p => p.map(c => c.id)),
        up: cards.map(c => c.up), score, moves, fan: wasteFan
      };
    }
    function restore(s) {
      const m = id => cards[id];
      stock = s.stock.map(m); waste = s.waste.map(m);
      found = s.found.map(p => p.map(m)); tab = s.tab.map(p => p.map(m));
      cards.forEach((c, i) => { c.up = s.up[i]; });
      score = s.score; moves = s.moves; wasteFan = s.fan;
    }
    function pushHistory() {
      history.push(snap());
      if (history.length > 1000) history.shift();
    }

    // ---------- game ----------
    function newGame() {
      stopAnim();
      stopAuto();
      cancelDrag();
      clearHint();
      const deck = cards.slice();
      for (let i = deck.length - 1; i > 0; i--) {
        const j = (Math.random() * (i + 1)) | 0;
        const t = deck[i]; deck[i] = deck[j]; deck[j] = t;
      }
      deck.forEach(c => { c.up = false; c.el.style.visibility = ''; });
      tab = [[], [], [], [], [], [], []];
      for (let t = 0; t < 7; t++) for (let k = 0; k <= t; k++) tab[t].push(deck.pop());
      tab.forEach(p => { top(p).up = true; });
      stock = deck; waste = []; found = [[], [], [], []];
      score = 0; moves = 0; elapsed = 0; started = false; won = false; wasteFan = 0; history = [];
      layout(true);
      updateStatus();
    }

    function startClock() {
      if (!started) { started = true; lastTick = performance.now(); }
    }

    function after() {
      layout();
      checkWin();
      updateStatus();
    }

    function drawStock() {
      if (won || (!stock.length && !waste.length)) return;
      clearHint();
      pushHistory(); startClock();
      if (!stock.length) {
        stock = waste.reverse();
        stock.forEach(c => { c.up = false; });
        waste = []; wasteFan = 0;
        score = Math.max(0, score - (drawN === 1 ? 100 : 20));
      } else {
        const n = Math.min(drawN, stock.length);
        for (let k = 0; k < n; k++) { const c = stock.pop(); c.up = true; waste.push(c); }
        wasteFan = n;
      }
      moves++;
      after();
    }

    function doMove(from, idx, to) {
      clearHint();
      pushHistory(); startClock();
      const sp = pileOf(from), dp = pileOf(to);
      const moving = sp.splice(idx);
      moving.forEach(c => dp.push(c));
      if (from.t === 'waste') { wasteFan = Math.max(0, wasteFan - 1); score += to.t === 'tab' ? 5 : 10; }
      else if (from.t === 'tab' && to.t === 'found') score += 10;
      else if (from.t === 'found' && to.t === 'tab') score = Math.max(0, score - 15);
      flipTop(from);
      moves++;
      after();
    }
    function flipTop(loc) {
      if (loc.t !== 'tab') return false;
      const t = top(tab[loc.i]);
      if (t && !t.up) { t.up = true; score += 5; return true; }
      return false;
    }

    function undo() {
      if (won || autoTimer || !history.length) return;
      cancelDrag(); clearHint();
      restore(history.pop());
      layout();
      updateStatus();
    }

    function canAuto() {
      if (won || autoTimer) return false;
      if (found.every(p => p.length === 13)) return false;
      return tab.every(p => p.every(c => c.up));
    }

    function autoStep() {
      autoTimer = 0;
      if (won) return;
      // accessible tops first
      const srcs = [];
      if (waste.length) srcs.push({ loc: { t: 'waste' }, c: top(waste), idx: waste.length - 1 });
      tab.forEach((p, i) => { if (p.length) srcs.push({ loc: { t: 'tab', i }, c: top(p), idx: p.length - 1 }); });
      srcs.sort((a, b) => a.c.rank - b.c.rank);
      for (const s of srcs) {
        const f = foundFor(s.c);
        if (f >= 0) {
          doMove(s.loc, s.idx, { t: 'found', i: f });
          if (!won) autoTimer = setTimeout(autoStep, 90);
          updateStatus();
          return;
        }
      }
      // pull the lowest needed card straight out of stock / waste
      const rest = stock.concat(waste).sort((a, b) => a.rank - b.rank);
      for (const c of rest) {
        const f = foundFor(c);
        if (f < 0) continue;
        pushHistory();
        const arr = stock.includes(c) ? stock : waste;
        arr.splice(arr.indexOf(c), 1);
        if (arr === waste) wasteFan = Math.max(0, wasteFan - 1);
        c.up = true;
        found[f].push(c);
        score += 10; moves++;
        after();
        if (!won) autoTimer = setTimeout(autoStep, 90);
        updateStatus();
        return;
      }
      updateStatus();
    }
    function startAuto() {
      if (!canAuto()) return;
      cancelDrag(); clearHint(); startClock();
      autoTimer = setTimeout(autoStep, 10);
      updateStatus();
    }
    function stopAuto() { if (autoTimer) { clearTimeout(autoTimer); autoTimer = 0; } }

    // ---------- hint ----------
    function clearHint() {
      if (hintTimer) { clearTimeout(hintTimer); hintTimer = 0; }
      hintEls.forEach(e => e.classList.remove('sol-hint'));
      hintEls = [];
    }
    function findHint() {
      const tops = [];
      if (waste.length) tops.push({ loc: { t: 'waste' }, idx: waste.length - 1 });
      tab.forEach((p, i) => { if (p.length && top(p).up) tops.push({ loc: { t: 'tab', i }, idx: p.length - 1 }); });
      for (const s of tops) {
        const c = pileOf(s.loc)[s.idx], f = foundFor(c);
        if (f >= 0) return { src: [c], dst: found[f].length ? top(found[f]).el : foundSlots[f] };
      }
      for (let i = 0; i < 7; i++) {
        const p = tab[i];
        const idx = p.findIndex(c => c.up);
        if (idx < 0) continue;
        const c = p[idx];
        for (let j = 0; j < 7; j++) {
          if (j === i || !canTab(c, tab[j])) continue;
          if (!tab[j].length && idx === 0) continue; // pointless king shuffle
          return { src: p.slice(idx), dst: tab[j].length ? top(tab[j]).el : tabSlots[j] };
        }
      }
      if (waste.length) {
        const c = top(waste);
        for (let j = 0; j < 7; j++) if (canTab(c, tab[j])) return { src: [c], dst: tab[j].length ? top(tab[j]).el : tabSlots[j] };
      }
      if (stock.length) return { src: [top(stock)], dst: null };
      if (waste.length) return { src: [], dst: stockSlot };
      return null;
    }
    function hint() {
      if (won || autoTimer) return;
      clearHint();
      const h = findHint();
      if (!h) { ctx.toast && ctx.toast('没有可用的移动了'); return; }
      hintEls = h.src.map(c => c.el);
      if (h.dst) hintEls.push(h.dst);
      hintEls.forEach(e => e.classList.add('sol-hint'));
      hintTimer = setTimeout(clearHint, 1200);
    }

    // ---------- win ----------
    function checkWin() {
      if (won || !found.every(p => p.length === 13)) return;
      won = true;
      stopAuto();
      const sec = Math.floor(elapsed / 1000);
      const wins = ctx.store.get('wins', 0) + 1;
      ctx.store.set('wins', wins);
      const best = ctx.store.get('best', null);
      const record = best == null || sec < best;
      if (record) ctx.store.set('best', sec);
      const bestScore = ctx.store.get('bestScore', 0);
      if (score > bestScore) ctx.store.set('bestScore', score);
      ctx.say('纸牌接龙通关！');
      ctx.reward(15, '纸牌接龙通关');
      ctx.toast && ctx.toast(`通关！用时 ${fmtTime(sec)}，得分 ${score}${record ? '（最佳用时！）' : ''}`);
      updateStatus();
      startCascade();
    }

    function startCascade() {
      stopAnim();
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(TW * dpr);
      canvas.height = Math.round(TH * dpr);
      canvas.style.width = TW + 'px';
      canvas.style.height = TH + 'px';
      canvas.classList.remove('hidden');
      const g = canvas.getContext('2d');
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, TW, TH);
      const queue = [];
      for (let r = 13; r >= 1; r--) for (let f = 0; f < 4; f++) {
        const c = found[f][r - 1];
        if (!c) continue;
        const img = new Image();
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(c.svg);
        queue.push({ c, img });
      }
      anim = { raf: 0, last: 0, acc: 0, launch: 18, queue, parts: [], g };
      const step = () => {
        const a = anim;
        if (++a.launch >= 18 && a.queue.length) {
          a.launch = 0;
          const q = a.queue.shift();
          q.c.el.style.visibility = 'hidden';
          const dir = Math.random() < 0.5 ? -1 : 1;
          a.parts.push({ img: q.img, x: q.c.x, y: q.c.y, vx: dir * (2 + Math.random() * 4), vy: -1 - Math.random() * 8 });
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
        if (!anim.queue.length && !anim.parts.length) { anim.raf = 0; anim.done = true; return; }
        anim.raf = requestAnimationFrame(frame);
      };
      anim.raf = requestAnimationFrame(frame);
    }
    function stopAnim() {
      if (anim && anim.raf) cancelAnimationFrame(anim.raf);
      anim = null;
      canvas.classList.add('hidden');
    }
    function onCanvasClick() { newGame(); }

    // ---------- pointer input ----------
    function onDown(e) {
      if (e.button !== 0 || won || autoTimer) return;
      const d = e.target.closest && e.target.closest('.sol-card, .sol-slot-stock');
      if (!d || !table.contains(d)) return;
      e.preventDefault();
      clearHint();
      if (d === stockSlot) { drawStock(); return; }
      const c = cards[+d.dataset.id];
      const L = locate(c);
      if (!L) return;
      const pile = pileOf(L.loc);
      if (L.loc.t === 'stock') { drawStock(); return; }
      if (L.loc.t === 'tab' && !c.up) {
        if (L.idx === pile.length - 1) {
          pushHistory(); startClock(); c.up = true; score += 5; moves++; after();
        }
        return;
      }
      if (L.loc.t === 'waste' || L.loc.t === 'found') { if (L.idx !== pile.length - 1) return; }
      else if (!validSeq(pile, L.idx)) return;
      drag = {
        from: L.loc, idx: L.idx, cards: pile.slice(L.idx), sx: e.clientX, sy: e.clientY,
        orig: pile.slice(L.idx).map(k => [k.x, k.y]), started: false, pid: e.pointerId
      };
    }
    function onMove(e) {
      if (!drag || e.pointerId !== drag.pid) return;
      const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
      if (!drag.started) {
        if (dx * dx + dy * dy < 16) return;
        drag.started = true;
        drag.cards.forEach((c, k) => { c.el.classList.add('sol-dragging'); c.el.style.zIndex = 3000 + k; });
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
    function dropTarget() {
      const first = drag.cards[0];
      const x = drag.orig[0][0] + drag.dx, y = drag.orig[0][1] + drag.dy;
      let best = null, bestA = 0;
      for (let i = 0; i < 7; i++) {
        if (drag.from.t === 'tab' && drag.from.i === i) continue;
        const p = tab[i], t = top(p);
        if (!canTab(first, p)) continue;
        const a = overlap(x, y, t ? t.x : colX(i), t ? t.y : TAB_Y);
        if (a > bestA) { bestA = a; best = { t: 'tab', i }; }
      }
      if (drag.cards.length === 1) for (let f = 0; f < 4; f++) {
        if (drag.from.t === 'found' && drag.from.i === f) continue;
        if (!canFound(first, f)) continue;
        const a = overlap(x, y, colX(3 + f), TOP_Y);
        if (a > bestA) { bestA = a; best = { t: 'found', i: f }; }
      }
      return best;
    }
    function endDrag(ok) {
      if (!drag) return;
      const d = drag;
      drag = null;
      if (!d.started) return;
      d.cards.forEach(c => c.el.classList.remove('sol-dragging'));
      drag = d;
      const target = ok ? dropTarget() : null;
      drag = null;
      if (target) doMove(d.from, d.idx, target);
      else { d.cards.forEach(c => { c.x = NaN; }); layout(); }
    }
    function onUp(e) { if (drag && e.pointerId === drag.pid) endDrag(true); }
    function onCancel(e) { if (drag && e.pointerId === drag.pid) endDrag(false); }
    function cancelDrag() { endDrag(false); }
    function onBlur() { cancelDrag(); }

    function onDbl(e) {
      if (won || autoTimer) return;
      const d = e.target.closest && e.target.closest('.sol-card');
      if (!d) return;
      const c = cards[+d.dataset.id];
      const L = locate(c);
      if (!L || !c.up || (L.loc.t !== 'tab' && L.loc.t !== 'waste')) return;
      if (L.idx !== pileOf(L.loc).length - 1) return;
      const f = foundFor(c);
      if (f >= 0) doMove(L.loc, L.idx, { t: 'found', i: f });
    }

    function onBar(e) {
      const b = e.target.closest('button');
      if (!b) return;
      b.blur();
      if (b.dataset.draw) {
        const n = +b.dataset.draw;
        if (n === drawN) return;
        drawN = n;
        ctx.store.set('draw', n);
        newGame();
        ctx.toast && ctx.toast(n === 1 ? '抽 1 张模式：新游戏' : '抽 3 张模式：新游戏');
        return;
      }
      const act = b.dataset.act;
      if (act === 'new') newGame();
      else if (act === 'undo') undo();
      else if (act === 'hint') hint();
      else if (act === 'auto') startAuto();
    }

    function onKey(e) {
      if (!ctx.isActive()) return;
      if (e.key === 'F2') { e.preventDefault(); newGame(); }
      else if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); }
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
    table.addEventListener('dblclick', onDbl);
    table.addEventListener('transitionend', onTransEnd);
    table.addEventListener('contextmenu', onCtx);
    canvas.addEventListener('click', onCanvasClick);
    bar.addEventListener('click', onBar);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
    window.addEventListener('blur', onBlur);
    window.addEventListener('keydown', onKey);
    function onCtx(e) { e.preventDefault(); }

    newGame();

    cleanup = () => {
      clearInterval(timer);
      stopAuto();
      clearHint();
      stopAnim();
      drag = null;
      table.removeEventListener('pointerdown', onDown);
      table.removeEventListener('dblclick', onDbl);
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
    id: 'solitaire',
    title: '纸牌接龙',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="5" width="11" height="15" rx="2" transform="rotate(-10 8.5 12.5)"/><rect x="10" y="4" width="11" height="15" rx="2" fill="currentColor" fill-opacity="0.15"/><path d="M15.5 8.5c-1.6 1.5-2.6 2.5-2.6 3.6 0 .9.7 1.5 1.5 1.5.5 0 .9-.2 1.1-.6.2.4.6.6 1.1.6.8 0 1.5-.6 1.5-1.5 0-1.1-1-2.1-2.6-3.6z" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
