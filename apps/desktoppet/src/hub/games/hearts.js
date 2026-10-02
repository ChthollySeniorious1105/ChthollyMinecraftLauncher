// 红心大战 — Microsoft-Windows-style Hearts module for the hub. See ../MODULES.md for the contract.
(function () {
  // =====================================================================
  // Card drawing (copied from solitaire.js, ids renamed for this module)
  // =====================================================================
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

  // red lattice card back
  const BACK_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 70 98" width="70" height="98">' +
    '<defs><pattern id="htBackPat" width="8" height="8" patternUnits="userSpaceOnUse">' +
    '<rect width="8" height="8" fill="#a8232f"/><path d="M0 4L4 0L8 4L4 8Z" fill="none" stroke="#f0a0a8" stroke-width="0.8"/>' +
    '<circle cx="4" cy="4" r="1" fill="#ffe0e3"/></pattern></defs>' +
    '<rect x="0.5" y="0.5" width="69" height="97" rx="5" fill="#fff" stroke="#555"/>' +
    '<rect x="4" y="4" width="62" height="90" rx="3" fill="url(#htBackPat)" stroke="#6e1119" stroke-width="1"/>' +
    '<rect x="7" y="7" width="56" height="84" rx="2" fill="none" stroke="#ffe0e3" stroke-width="0.8" opacity="0.7"/>' +
    '<g transform="translate(35 49)"><path d="M0 -13L9 0L0 13L-9 0Z" fill="#a8232f" stroke="#f3d27a" stroke-width="1.4"/>' +
    '<circle r="3.2" fill="#f3d27a"/></g></svg>';

  // =====================================================================
  // Rules engine (pure, DOM-free). Card id 0..51: suit = id/13 (0♠ 1♥ 2♦ 3♣), rank = id%13 + 2 (2..14, 14 = A)
  // =====================================================================
  const QS = 10;          // Q♠
  const C2 = 39;          // 2♣
  const suitOf = c => (c / 13) | 0;
  const rankOf = c => c % 13 + 2;
  const ptsOf = c => suitOf(c) === 1 ? 1 : (c === QS ? 13 : 0);
  const SUIT_ORDER = [2, 3, 1, 0]; // display order: ♣ ♦ ♠ ♥
  const sortKey = c => SUIT_ORDER[suitOf(c)] * 13 + rankOf(c);
  const sortHand = h => h.sort((a, b) => sortKey(a) - sortKey(b));
  const PASS_NAMES = ['左', '右', '对家', '不传'];

  function passTarget(p, dir) { return dir === 0 ? (p + 1) % 4 : dir === 1 ? (p + 3) % 4 : (p + 2) % 4; }

  function newHand(handNo, rnd) {
    rnd = rnd || Math.random;
    const deck = [];
    for (let i = 0; i < 52; i++) deck.push(i);
    for (let i = 51; i > 0; i--) { const j = (rnd() * (i + 1)) | 0; const t = deck[i]; deck[i] = deck[j]; deck[j] = t; }
    const hands = [0, 1, 2, 3].map(p => sortHand(deck.slice(p * 13, p * 13 + 13)));
    return {
      handNo, passDir: handNo % 4, hands, trick: [], leader: -1, turn: -1, trickNo: 0,
      broken: false, taken: [0, 0, 0, 0], tricks: [0, 0, 0, 0], played: new Array(52).fill(false), lastTrick: null
    };
  }

  function applyPass(s, picks) {
    for (let p = 0; p < 4; p++) {
      if (!picks[p] || picks[p].length !== 3) throw new Error('bad pass');
      picks[p].forEach(c => { const i = s.hands[p].indexOf(c); if (i < 0) throw new Error('pass card not in hand'); s.hands[p].splice(i, 1); });
    }
    for (let p = 0; p < 4; p++) picks[p].forEach(c => s.hands[passTarget(p, s.passDir)].push(c));
    s.hands.forEach(sortHand);
  }

  function startPlay(s) {
    const p = s.hands.findIndex(h => h.includes(C2));
    s.leader = s.turn = p;
  }

  function legalMoves(s, p) {
    const h = s.hands[p];
    if (!s.trick.length) {
      if (s.trickNo === 0 && h.includes(C2)) return [C2];
      if (!s.broken) { const nh = h.filter(c => suitOf(c) !== 1); if (nh.length) return nh; }
      return h.slice();
    }
    const led = suitOf(s.trick[0].c);
    const f = h.filter(c => suitOf(c) === led);
    if (f.length) return f;
    if (s.trickNo === 0) { const np = h.filter(c => !ptsOf(c)); if (np.length) return np; }
    return h.slice();
  }

  function illegalReason(s, p, c) {
    if (!s.trick.length) {
      if (s.trickNo === 0) return '第一轮必须先出 梅花 2';
      if (suitOf(c) === 1) return '红心还没破，不能先出红心';
      return '现在不能出这张';
    }
    const led = suitOf(s.trick[0].c);
    if (suitOf(c) !== led && s.hands[p].some(x => suitOf(x) === led)) return '必须跟出同花色';
    if (s.trickNo === 0 && ptsOf(c)) return '第一轮不能出红心或黑桃 Q';
    return '现在不能出这张';
  }

  function trickWinner(trick) {
    const led = suitOf(trick[0].c);
    let w = trick[0];
    for (const t of trick) if (suitOf(t.c) === led && rankOf(t.c) > rankOf(w.c)) w = t;
    return w.p;
  }

  function playCard(s, p, c) {
    if (s.turn !== p || !legalMoves(s, p).includes(c)) return null;
    s.hands[p].splice(s.hands[p].indexOf(c), 1);
    s.trick.push({ p, c });
    s.played[c] = true;
    if (suitOf(c) === 1) s.broken = true;
    if (s.trick.length < 4) { s.turn = (p + 1) % 4; return { complete: false }; }
    const trick = s.trick, w = trickWinner(trick);
    const pts = trick.reduce((a, t) => a + ptsOf(t.c), 0);
    s.taken[w] += pts;
    s.tricks[w]++;
    s.lastTrick = trick;
    s.trick = [];
    s.trickNo++;
    s.leader = s.turn = w;
    return { complete: true, winner: w, trick, pts };
  }

  function handResult(s) {
    const moon = s.taken.indexOf(26);
    const add = moon >= 0 ? s.taken.map((_, i) => i === moon ? 0 : 26) : s.taken.slice();
    return { add, moon };
  }

  // ---------- AI ----------
  function aiPass(hand) {
    const cnt = [0, 0, 0, 0];
    hand.forEach(c => cnt[suitOf(c)]++);
    const lowSpades = hand.filter(c => suitOf(c) === 0 && rankOf(c) < 12).length;
    const score = c => {
      const su = suitOf(c), r = rankOf(c);
      if (c === QS) return lowSpades >= 4 ? 20 : 100;         // keep Q♠ when well guarded
      if (su === 0) return r > 12 ? (lowSpades >= 4 && !hand.includes(QS) ? 30 + r : 80 + r) : r - 12;
      if (su === 1) return r >= 10 ? 40 + r : r;
      return r + (cnt[su] <= 3 ? (4 - cnt[su]) * 5 : 0);     // help void short minor suits
    };
    return hand.slice().sort((a, b) => score(b) - score(a)).slice(0, 3);
  }

  function aiPlay(s, p) {
    const legal = legalMoves(s, p);
    if (legal.length === 1) return legal[0];
    const hand = s.hands[p];
    const qsLive = !s.played[QS] && !hand.includes(QS);    // someone else still holds Q♠
    const maxBy = (arr, f) => arr.reduce((b, c) => (f(c) > f(b) ? c : b));
    const minBy = (arr, f) => arr.reduce((b, c) => (f(c) < f(b) ? c : b));

    if (!s.trick.length) {
      const cnt = [0, 0, 0, 0];
      hand.forEach(c => cnt[suitOf(c)]++);
      return minBy(legal, c => {
        const su = suitOf(c), r = rankOf(c);
        let sc = r;
        if (su === 0) {
          if (r >= 12 && !s.played[QS]) sc += 30;             // never lead Q/K/A♠ while Q♠ is live
          else if (qsLive) sc -= 3;                          // flush out Q♠ with low spades
        }
        if (su === 1) sc += 4;
        sc += cnt[su] * 0.2;                                 // slightly prefer short suits
        return sc;
      });
    }

    const led = suitOf(s.trick[0].c);
    const last = s.trick.length === 3;
    let winT = s.trick[0];
    for (const t of s.trick) if (suitOf(t.c) === led && rankOf(t.c) > rankOf(winT.c)) winT = t;
    const winRank = rankOf(winT.c);

    if (suitOf(legal[0]) === led && legal.every(c => suitOf(c) === led)) {
      if (s.trickNo === 0) return maxBy(legal, rankOf);      // first trick carries no points
      const under = legal.filter(c => rankOf(c) < winRank);
      if (under.length) return maxBy(under, rankOf);
      const nonQ = legal.filter(c => c !== QS);
      if (last) {
        const trickPts = s.trick.reduce((a, t) => a + ptsOf(t.c), 0);
        if (!trickPts || !nonQ.length) return nonQ.length ? maxBy(nonQ, rankOf) : QS;
        return maxBy(nonQ, rankOf);
      }
      return nonQ.length ? minBy(nonQ, rankOf) : QS;
    }

    // void in led suit: dump. Minimal moon defence: don't feed points to a player who has taken all points so far.
    const total = s.taken.reduce((a, b) => a + b, 0);
    const shooter = total >= 10 && s.taken[winT.p] === total && winT.p !== p;
    const cnt = [0, 0, 0, 0];
    hand.forEach(c => cnt[suitOf(c)]++);
    if (shooter) {
      const safe = legal.filter(c => !ptsOf(c));
      if (safe.length) return maxBy(safe, rankOf);
    }
    return maxBy(legal, c => {
      const su = suitOf(c), r = rankOf(c);
      if (c === QS) return 1000;
      if (su === 0 && r > 12 && !s.played[QS]) return 500 + r;
      if (su === 1) return 100 + r;
      return r + (cnt[su] <= 2 ? 6 : 0);
    });
  }

  const Engine = { QS, C2, suitOf, rankOf, ptsOf, passTarget, newHand, applyPass, startPlay, legalMoves, playCard, handResult, trickWinner, aiPass, aiPlay };

  // =====================================================================
  // UI
  // =====================================================================
  const CW = 70, CH = 98;
  const TW = 740, TH = 520;
  const CX = TW / 2, CY = 248;
  const HAND_Y = TH - CH - 12;
  const SP0 = 36, SPA = 16;
  const NAMES = ['你', '小狐狸', '小熊', '企鹅'];
  const TRICK_OFF = [[0, 44], [-56, 0], [0, -44], [56, 0]];
  const ANCHOR = [[CX - CW / 2, HAND_Y + 20], [20, CY - CH / 2], [CX - CW / 2, -10], [TW - CW - 20, CY - CH / 2]];

  function handPos(p, i, n) {
    if (p === 0) return { x: Math.round((TW - (n - 1) * SP0 - CW) / 2 + i * SP0), y: HAND_Y, side: false };
    if (p === 2) return { x: Math.round((TW - (n - 1) * SPA - CW) / 2 + (n - 1 - i) * SPA), y: 10, side: false };
    const cx = p === 1 ? 16 + CH / 2 : TW - 16 - CH / 2;
    const cy = CY - (n - 1) * SPA / 2 + i * SPA;
    return { x: Math.round(cx - CW / 2), y: Math.round(cy - CH / 2), side: true };
  }

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'ht-root';
    root.innerHTML = `
      <div class="ht-bar">
        <button type="button" class="ht-btn ht-primary" data-act="new">新游戏</button>
        <button type="button" class="ht-btn" data-act="score">积分表</button>
        <span class="ht-info"></span>
        <span class="ht-rec"></span>
      </div>
      <div class="ht-table" style="width:${TW}px;height:${TH}px">
        <div class="ht-broken"><span class="ht-heart">♥</span><b></b></div>
        <div class="ht-seat ht-seat-0"></div>
        <div class="ht-seat ht-seat-1"></div>
        <div class="ht-seat ht-seat-2"></div>
        <div class="ht-seat ht-seat-3"></div>
        <div class="ht-center"><div class="ht-msg"></div><button type="button" class="ht-btn ht-primary ht-go"></button></div>
        <div class="ht-overlay ht-hidden"><div class="ht-panel"></div></div>
      </div>`;
    el.appendChild(root);

    const $ = q => root.querySelector(q);
    const table = $('.ht-table'), bar = $('.ht-bar'), info = $('.ht-info'), rec = $('.ht-rec');
    const brokenEl = $('.ht-broken'), msgEl = $('.ht-msg'), goBtn = $('.ht-go');
    const overlay = $('.ht-overlay'), panel = $('.ht-panel');
    const seatEls = [0, 1, 2, 3].map(p => $('.ht-seat-' + p));

    const els = [];
    for (let c = 0; c < 52; c++) {
      const r = rankOf(c);
      const d = document.createElement('div');
      d.className = 'ht-card ht-out';
      d.dataset.id = c;
      d.innerHTML = `<div class="ht-face">${faceSvg({ suit: suitOf(c), rank: r === 14 ? 1 : r })}</div><div class="ht-back">${BACK_SVG}</div>`;
      table.appendChild(d);
      els.push(d);
    }

    // ---------- state ----------
    let game = null;      // { totals, history, handNo, over }
    let s = null;         // current hand (engine state)
    let phase = 'idle';   // pass | received | play | busy | handEnd | over
    let selected = new Set(), received = new Set();
    let shown = [];       // trick cards on the table
    let collecting = null;
    const timers = new Set();
    const later = (fn, ms) => { const id = setTimeout(() => { timers.delete(id); fn(); }, ms); timers.add(id); return id; };
    const clearTimers = () => { timers.forEach(clearTimeout); timers.clear(); };

    // ---------- rendering ----------
    function setCard(c, x, y, z, o) {
      const e = els[c];
      e.style.left = x + 'px';
      e.style.top = y + 'px';
      e.style.zIndex = z;
      e.classList.toggle('up', !!o.up);
      e.classList.toggle('ht-side', !!o.side);
      e.classList.toggle('ht-gone', !!o.gone);
      e.classList.toggle('ht-out', !!o.out);
      e.classList.toggle('ht-sel', !!o.sel);
      e.classList.toggle('ht-new', !!o.isNew);
      e.classList.toggle('ht-playable', !!o.playable);
    }

    function layout(instant) {
      if (instant) table.classList.add('ht-noanim');
      const done = new Set();
      if (s) {
        const playable = phase === 'play' && s.turn === 0 ? new Set(legalMoves(s, 0)) : null;
        for (let p = 0; p < 4; p++) {
          const h = s.hands[p], n = h.length;
          h.forEach((c, i) => {
            const pos = handPos(p, i, n);
            const lift = p === 0 && (selected.has(c) || received.has(c));
            setCard(c, pos.x, pos.y - (lift ? 22 : 0), 1 + i, {
              up: p === 0 || phase === 'over', side: pos.side, sel: p === 0 && selected.has(c),
              isNew: p === 0 && received.has(c), playable: p === 0 && (phase === 'pass' || (playable && playable.has(c)))
            });
            done.add(c);
          });
        }
      }
      shown.forEach((t, k) => {
        const o = TRICK_OFF[t.p];
        if (collecting) {
          const a = ANCHOR[collecting.winner];
          setCard(t.c, a[0], a[1], 100 + k, { up: true, gone: true });
        } else {
          setCard(t.c, CX - CW / 2 + o[0], CY - CH / 2 + o[1], 100 + k, { up: true });
        }
        done.add(t.c);
      });
      for (let c = 0; c < 52; c++) if (!done.has(c)) {
        const e = els[c];
        e.classList.add('ht-out');
        e.classList.remove('ht-sel', 'ht-new', 'ht-playable', 'ht-gone');
      }
      if (instant) { void table.offsetWidth; table.classList.remove('ht-noanim'); }
    }

    function updateUI() {
      const played = ctx.store.get('played', 0), wins = ctx.store.get('wins', 0);
      rec.textContent = `已完成 ${played} 盘 · 胜 ${wins} 盘`;
      if (game && s) {
        info.textContent = `第 ${s.handNo + 1} 局 · 传牌：${PASS_NAMES[s.passDir]}`;
      } else info.textContent = '';
      brokenEl.classList.toggle('ht-on', !!(s && s.broken));
      brokenEl.querySelector('b').textContent = s && s.broken ? '红心已破' : '红心未破';
      for (let p = 0; p < 4; p++) {
        const tot = game ? game.totals[p] : 0, cur = s ? s.taken[p] : 0;
        seatEls[p].innerHTML = `<span class="ht-name">${NAMES[p]}</span><span class="ht-pts">${tot} 分${cur ? `<i>+${cur}</i>` : ''}</span>`;
        seatEls[p].classList.toggle('ht-turn', !!s && phase === 'play' && s.turn === p && !collecting);
      }
      let msg = '', btn = '';
      if (phase === 'pass') {
        const to = NAMES[passTarget(0, s.passDir)];
        msg = `选择 3 张牌传给 ${to}（${PASS_NAMES[s.passDir]}）`;
        btn = `传牌 (${selected.size}/3)`;
        goBtn.disabled = selected.size !== 3;
      } else if (phase === 'received') {
        const from = NAMES[[1, 2, 3].find(p => passTarget(p, s.passDir) === 0)];
        msg = `收到 ${from} 传来的 3 张牌`;
        btn = '确定';
        goBtn.disabled = false;
      } else if (phase === 'play' && s.turn === 0 && !shown.length && s.trickNo === 0) {
        msg = '请出 梅花 2';
      }
      msgEl.textContent = msg;
      msgEl.classList.toggle('ht-hidden', !msg);
      goBtn.textContent = btn;
      goBtn.classList.toggle('ht-hidden', !btn);
    }

    // ---------- flow ----------
    function newGame() {
      clearTimers();
      hideOverlay();
      game = { totals: [0, 0, 0, 0], history: [], handNo: 0, over: false };
      startHand();
    }

    function startHand() {
      clearTimers();
      s = newHand(game.handNo);
      selected = new Set(); received = new Set(); shown = []; collecting = null;
      phase = s.passDir === 3 ? 'busy' : 'pass';
      // deal from centre
      table.classList.add('ht-noanim');
      for (let c = 0; c < 52; c++) setCard(c, CX - CW / 2, CY - CH / 2, 50, {});
      void table.offsetWidth;
      table.classList.remove('ht-noanim');
      layout();
      updateUI();
      if (s.passDir === 3) {
        ctx.toast && ctx.toast('本局不传牌');
        later(beginPlay, 500);
      }
    }

    function doPass() {
      if (phase !== 'pass' || selected.size !== 3) return;
      const picks = [0, 1, 2, 3].map(p => p === 0 ? [...selected] : aiPass(s.hands[p]));
      const from = [0, 1, 2, 3].find(p => passTarget(p, s.passDir) === 0);
      applyPass(s, picks);
      selected = new Set();
      received = new Set(picks[from]);
      phase = 'received';
      layout();
      updateUI();
    }

    function beginPlay() {
      received = new Set();
      startPlay(s);
      phase = 'play';
      layout();
      updateUI();
      nextTurn();
    }

    function nextTurn() {
      if (phase !== 'play') return;
      layout();
      updateUI();
      if (s.turn !== 0) later(aiTurn, 520);
    }

    function aiTurn() {
      if (phase !== 'play' || s.turn === 0) return;
      if (!ctx.isActive()) { later(aiTurn, 300); return; }
      doPlay(s.turn, aiPlay(s, s.turn));
    }

    function doPlay(p, c) {
      const res = playCard(s, p, c);
      if (!res) return;
      if (res.complete) {
        shown = res.trick.slice();
        phase = 'busy';
        layout();
        updateUI();
        later(() => {
          collecting = { winner: res.winner };
          layout();
          later(() => {
            shown = []; collecting = null;
            if (s.trickNo === 13) endHand();
            else { phase = 'play'; nextTurn(); }
          }, 430);
        }, 950);
      } else {
        shown = s.trick.slice();
        nextTurn();
      }
    }

    function endHand() {
      const { add, moon } = handResult(s);
      for (let p = 0; p < 4; p++) game.totals[p] += add[p];
      game.history.push({ add, moon });
      phase = 'handEnd';
      if (moon === 0) {
        ctx.say('我全收啦！红心大战射月成功！');
        ctx.reward(10, '红心大战全收');
      } else if (moon > 0) {
        ctx.toast && ctx.toast(`${NAMES[moon]} 全收了！其他人各加 26 分`);
      }
      if (game.totals.some(t => t >= 100)) {
        game.over = true;
        phase = 'over';
        const low = Math.min(...game.totals);
        const win = game.totals[0] === low;
        ctx.store.set('played', ctx.store.get('played', 0) + 1);
        if (win) {
          ctx.store.set('wins', ctx.store.get('wins', 0) + 1);
          ctx.say('红心大战获胜！');
          ctx.reward(15, '红心大战获胜');
        }
      }
      layout();
      updateUI();
      later(() => showOverlay(false), 350);
    }

    // ---------- score overlay ----------
    function showOverlay(viewOnly) {
      if (!game) return;
      const rows = game.history.map((h, i) =>
        `<tr${h.moon >= 0 ? ' class="ht-moonrow"' : ''}><td>${i + 1}${h.moon >= 0 ? ' ☾' : ''}</td>${h.add.map(v => `<td>${v}</td>`).join('')}</tr>`).join('');
      const low = Math.min(...game.totals);
      const tot = game.totals.map(v => `<td class="${game.over && v === low ? 'ht-best' : ''}">${v}</td>`).join('');
      let title, note = '', btn;
      const lastH = game.history[game.history.length - 1];
      if (game.over) {
        const winners = [0, 1, 2, 3].filter(p => game.totals[p] === low).map(p => NAMES[p]);
        title = game.totals[0] === low ? '你赢了！' : `${winners.join('、')} 获胜`;
        note = '有人达到 100 分，分数最低者获胜';
        btn = '<button type="button" class="ht-btn ht-primary" data-ov="new">再来一盘</button>';
      } else if (viewOnly) {
        title = '积分表';
        btn = '<button type="button" class="ht-btn ht-primary" data-ov="close">关闭</button>';
      } else {
        title = `第 ${game.history.length} 局结束`;
        btn = '<button type="button" class="ht-btn ht-primary" data-ov="next">下一局</button>';
      }
      if (!viewOnly && lastH && lastH.moon >= 0) note = `${lastH.moon === 0 ? '你' : NAMES[lastH.moon]} 全收（射月）！其他人各加 26 分。` + (note ? ' ' + note : '');
      panel.innerHTML = `<h3>${title}</h3>${note ? `<p class="ht-note">${note}</p>` : ''}
        <div class="ht-scroll"><table class="ht-score">
          <thead><tr><th>局</th>${NAMES.map(n => `<th>${n}</th>`).join('')}</tr></thead>
          <tbody>${rows || '<tr><td colspan="5" class="ht-empty">还没有完成的局</td></tr>'}</tbody>
          <tfoot><tr><th>总分</th>${tot}</tr></tfoot>
        </table></div><div class="ht-ovbtns">${btn}</div>`;
      overlay.classList.remove('ht-hidden');
      const sc = panel.querySelector('.ht-scroll');
      sc.scrollTop = sc.scrollHeight;
    }
    function hideOverlay() { overlay.classList.add('ht-hidden'); }

    function onOverlay(e) {
      const b = e.target.closest('[data-ov]');
      if (!b) return;
      const a = b.dataset.ov;
      if (a === 'close') hideOverlay();
      else if (a === 'new') newGame();
      else if (a === 'next') { hideOverlay(); game.handNo++; startHand(); }
    }

    // ---------- input ----------
    function shake(e) {
      e.classList.remove('ht-shake');
      void e.offsetWidth;
      e.classList.add('ht-shake');
    }
    function onAnimEnd(e) { if (e.animationName === 'ht-shake-kf') e.target.classList.remove('ht-shake'); }

    function onTableClick(e) {
      if (e.target.closest('.ht-overlay')) return;
      if (e.target === goBtn) {
        goBtn.blur();
        if (phase === 'pass') doPass();
        else if (phase === 'received') beginPlay();
        return;
      }
      const d = e.target.closest('.ht-card');
      if (!d || !s) return;
      const c = +d.dataset.id;
      if (!s.hands[0].includes(c)) return;
      if (phase === 'pass') {
        if (selected.has(c)) selected.delete(c);
        else if (selected.size < 3) selected.add(c);
        else { shake(d); ctx.toast && ctx.toast('只能选择 3 张牌'); return; }
        layout(); updateUI();
      } else if (phase === 'play' && s.turn === 0 && !collecting) {
        if (!legalMoves(s, 0).includes(c)) {
          shake(d);
          ctx.toast && ctx.toast(illegalReason(s, 0, c));
          return;
        }
        doPlay(0, c);
      } else if (phase === 'received') {
        beginPlay();
      }
    }

    function onBar(e) {
      const b = e.target.closest('button');
      if (!b) return;
      b.blur();
      if (b.dataset.act === 'new') newGame();
      else if (b.dataset.act === 'score') {
        if (overlay.classList.contains('ht-hidden')) showOverlay(!(phase === 'handEnd' || phase === 'over'));
        else if (phase !== 'handEnd' && phase !== 'over') hideOverlay();
      }
    }
    function onCtx(e) { e.preventDefault(); }

    table.addEventListener('click', onTableClick);
    table.addEventListener('animationend', onAnimEnd);
    table.addEventListener('contextmenu', onCtx);
    overlay.addEventListener('click', onOverlay);
    bar.addEventListener('click', onBar);

    newGame();

    cleanup = () => {
      clearTimers();
      table.removeEventListener('click', onTableClick);
      table.removeEventListener('animationend', onAnimEnd);
      table.removeEventListener('contextmenu', onCtx);
      overlay.removeEventListener('click', onOverlay);
      bar.removeEventListener('click', onBar);
      root.remove();
    };
  }

  Hub.register({
    id: 'hearts',
    title: '红心大战',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="4" width="11" height="15" rx="2" transform="rotate(-10 8.5 11.5)"/><rect x="10" y="5" width="11" height="15" rx="2" fill="currentColor" fill-opacity="0.15"/><path d="M15.5 16c-2.2-1.6-3.4-2.8-3.4-4.2 0-1 .8-1.8 1.8-1.8.7 0 1.3.4 1.6 1 .3-.6.9-1 1.6-1 1 0 1.8.8 1.8 1.8 0 1.4-1.2 2.6-3.4 4.2z" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    },
    _engine: Engine
  });
})();
