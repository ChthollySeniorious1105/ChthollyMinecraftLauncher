// 连连看 — tile-matching (onet) game module for the hub. See ../MODULES.md for the contract.
(function () {
  const COLS = 12, ROWS = 8;
  const W = COLS + 2, H = ROWS + 2;       // invisible 1-cell border around the board
  const TIME_MAX = 240000;                // ms
  const MATCH_BONUS = 2000;               // +2s per match
  const PATH_MS = 300;
  const HINTS = 3, SHUFFLES = 3;
  const COMBO_WINDOW = 4000;
  const LEVELS = [
    { g: 'none',  desc: '静止不动' },
    { g: 'down',  desc: '方块向下掉落' },
    { g: 'left',  desc: '方块向左靠拢' },
    { g: 'up',    desc: '方块向上浮起' },
    { g: 'split', desc: '方块左右分离' }
  ];
  const imgCache = new Map();

  let cleanup = null;

  function petImage(file) {
    if (imgCache.has(file)) return imgCache.get(file);
    let url = '';
    try { url = (window.api && window.api.petImage(file)) || ''; } catch (_) { url = ''; }
    imgCache.set(file, url);
    return url;
  }
  let petList = null;
  function pets() {
    if (petList) return petList;
    try { petList = (window.api && window.api.pets()) || []; } catch (_) { petList = []; }
    return petList;
  }

  function fallbackFace(i) {
    const hue = (i * 47) % 360;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="42" fill="hsl(${hue},70%,78%)"/><text x="50" y="65" font-size="44" text-anchor="middle" font-family="sans-serif" font-weight="700" fill="hsl(${hue},55%,30%)">${i + 1}</text></svg>`;
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  }

  function shuffleArr(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  const idx = (x, y) => y * W + x;
  const cx = c => c % W;
  const cy = c => (c / W) | 0;

  // Precomputed gravity lines: each is a list of cells ordered from the "sink" end.
  function gravityLines(mode) {
    const L = [];
    if (mode === 'down' || mode === 'up') {
      for (let x = 1; x <= COLS; x++) {
        const s = [];
        if (mode === 'down') for (let y = ROWS; y >= 1; y--) s.push(idx(x, y));
        else for (let y = 1; y <= ROWS; y++) s.push(idx(x, y));
        L.push(s);
      }
    } else if (mode === 'left') {
      for (let y = 1; y <= ROWS; y++) {
        const s = [];
        for (let x = 1; x <= COLS; x++) s.push(idx(x, y));
        L.push(s);
      }
    } else if (mode === 'split') {
      const half = COLS / 2;
      for (let y = 1; y <= ROWS; y++) {
        const a = [], b = [];
        for (let x = 1; x <= half; x++) a.push(idx(x, y));
        for (let x = COLS; x > half; x--) b.push(idx(x, y));
        L.push(a, b);
      }
    }
    return L;
  }

  function fmtSec(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'llk-root';
    root.innerHTML = `
      <div class="llk-bar">
        <div class="llk-stats">
          <div class="llk-stat"><span class="llk-lbl">分数</span><b class="llk-score">0</b></div>
          <div class="llk-stat llk-combo-box"><span class="llk-lbl">连击</span><b class="llk-combo">0</b></div>
          <div class="llk-stat"><span class="llk-lbl">剩余</span><b class="llk-left">0</b></div>
          <div class="llk-stat"><span class="llk-lbl">最佳</span><b class="llk-best">—</b></div>
        </div>
        <div class="llk-opts">
          <div class="llk-seg" role="group" aria-label="关卡">
            ${LEVELS.map((l, i) => `<button type="button" data-lv="${i}" title="第${i + 1}关 · ${l.desc}">${i + 1}</button>`).join('')}
          </div>
          <button type="button" class="llk-btn llk-hint-btn">提示 <span>3</span></button>
          <button type="button" class="llk-btn llk-shuf-btn">洗牌 <span>3</span></button>
          <button type="button" class="llk-btn llk-primary llk-new">新游戏</button>
        </div>
      </div>
      <div class="llk-timer"><div class="llk-timer-fill"></div><span class="llk-timer-txt">4:00</span></div>
      <div class="llk-stage">
        <div class="llk-board">
          <svg class="llk-svg" xmlns="http://www.w3.org/2000/svg"></svg>
        </div>
        <div class="llk-overlay hidden">
          <div class="llk-card-ov">
            <div class="llk-ov-title"></div>
            <div class="llk-ov-sub"></div>
            <div class="llk-ov-btns">
              <button type="button" class="llk-btn llk-again">再来一局</button>
              <button type="button" class="llk-btn llk-primary llk-next">下一关</button>
            </div>
          </div>
        </div>
      </div>
      <div class="llk-help"></div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.llk-stage'), board = $('.llk-board'), svg = $('.llk-svg');
    const scoreEl = $('.llk-score'), comboEl = $('.llk-combo'), leftEl = $('.llk-left'), bestEl = $('.llk-best');
    const comboBox = $('.llk-combo-box');
    const timerBar = $('.llk-timer'), timerFill = $('.llk-timer-fill'), timerTxt = $('.llk-timer-txt');
    const hintBtn = $('.llk-hint-btn'), shufBtn = $('.llk-shuf-btn'), newBtn = $('.llk-new');
    const overlay = $('.llk-overlay'), ovTitle = $('.llk-ov-title'), ovSub = $('.llk-ov-sub');
    const againBtn = $('.llk-again'), nextBtn = $('.llk-next');
    const helpEl = $('.llk-help');
    const lvBtns = [...root.querySelectorAll('[data-lv]')];

    // ---------- state ----------
    let lv = ctx.store.get('level', 0);
    if (!(lv >= 0 && lv < LEVELS.length)) lv = 0;
    let grid = new Array(W * H).fill(null);
    let alive = [];                      // tile objects {uid, id, cell, el}
    const byEl = new WeakMap();
    let lines = [];
    let S = 46;                          // cell size px
    let sel = null;
    let locked = false, over = false, started = false, rewarded = false;
    let timeLeft = TIME_MAX, lastTick = performance.now();
    let score = 0, combo = 0, lastMatchAt = 0;
    let hints = HINTS, shuffles = SHUFFLES;
    let hintPair = null;
    const timers = new Set();

    function later(fn, ms) {
      const id = setTimeout(() => { timers.delete(id); fn(); }, ms);
      timers.add(id);
      return id;
    }
    function clearTimers() { timers.forEach(clearTimeout); timers.clear(); }

    const bestKey = () => 'best_' + lv;

    // ---------- geometry / rendering ----------
    function place(t) {
      t.el.style.transform = `translate(${cx(t.cell) * S}px, ${cy(t.cell) * S}px)`;
    }

    function fit() {
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(200, stage.clientWidth - 4);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 6);
      S = Math.max(26, Math.min(58, Math.floor(Math.min(aw / W, ah / H))));
      board.style.width = W * S + 'px';
      board.style.height = H * S + 'px';
      board.style.setProperty('--s', S + 'px');
      svg.setAttribute('width', W * S);
      svg.setAttribute('height', H * S);
      svg.setAttribute('viewBox', `0 0 ${W * S} ${H * S}`);
      board.classList.add('llk-noanim');
      alive.forEach(place);
      void board.offsetWidth;
      board.classList.remove('llk-noanim');
    }

    function updateHud() {
      scoreEl.textContent = score;
      comboEl.textContent = combo;
      leftEl.textContent = alive.length;
      const b = ctx.store.get(bestKey(), null);
      bestEl.textContent = b != null ? b : '—';
      hintBtn.querySelector('span').textContent = hints;
      shufBtn.querySelector('span').textContent = shuffles;
      hintBtn.disabled = hints <= 0 || over;
      shufBtn.disabled = shuffles <= 0 || over;
      lvBtns.forEach(bt => bt.classList.toggle('active', +bt.dataset.lv === lv));
      helpEl.textContent = `第${lv + 1}关 · ${LEVELS[lv].desc} · 连线最多拐两个弯 · 每次消除 +2 秒`;
    }

    function updateTimer() {
      const f = Math.max(0, Math.min(1, timeLeft / TIME_MAX));
      timerFill.style.transform = `scaleX(${f})`;
      timerTxt.textContent = fmtSec(timeLeft);
      timerBar.classList.toggle('warn', timeLeft < 30000);
    }

    // ---------- path finding ----------
    function emptyAt(x, y) {
      if (x < 0 || y < 0 || x >= W || y >= H) return false;
      return !grid[idx(x, y)];
    }
    // endpoints excluded
    function clearLine(x1, y1, x2, y2) {
      if (x1 === x2 && y1 === y2) return true;
      if (x1 === x2) {
        const s = Math.sign(y2 - y1);
        for (let y = y1 + s; y !== y2; y += s) if (!emptyAt(x1, y)) return false;
        return true;
      }
      if (y1 === y2) {
        const s = Math.sign(x2 - x1);
        for (let x = x1 + s; x !== x2; x += s) if (!emptyAt(x, y1)) return false;
        return true;
      }
      return false;
    }
    function findPath(a, b) {
      const ax = cx(a), ay = cy(a), bx = cx(b), by = cy(b);
      if ((ax === bx || ay === by) && clearLine(ax, ay, bx, by)) return [[ax, ay], [bx, by]];
      for (const [px, py] of [[ax, by], [bx, ay]]) {
        if (emptyAt(px, py) && clearLine(ax, ay, px, py) && clearLine(px, py, bx, by)) {
          return [[ax, ay], [px, py], [bx, by]];
        }
      }
      let best = null, bestLen = Infinity;
      for (let x = 0; x < W; x++) {
        if (x === ax || x === bx) continue;
        if (emptyAt(x, ay) && emptyAt(x, by) && clearLine(ax, ay, x, ay) && clearLine(x, ay, x, by) && clearLine(x, by, bx, by)) {
          const len = Math.abs(x - ax) + Math.abs(x - bx) + Math.abs(ay - by);
          if (len < bestLen) { bestLen = len; best = [[ax, ay], [x, ay], [x, by], [bx, by]]; }
        }
      }
      for (let y = 0; y < H; y++) {
        if (y === ay || y === by) continue;
        if (emptyAt(ax, y) && emptyAt(bx, y) && clearLine(ax, ay, ax, y) && clearLine(ax, y, bx, y) && clearLine(bx, y, bx, by)) {
          const len = Math.abs(y - ay) + Math.abs(y - by) + Math.abs(ax - bx);
          if (len < bestLen) { bestLen = len; best = [[ax, ay], [ax, y], [bx, y], [bx, by]]; }
        }
      }
      return best;
    }

    function findMove() {
      const groups = new Map();
      for (const t of alive) {
        if (!groups.has(t.id)) groups.set(t.id, []);
        groups.get(t.id).push(t);
      }
      for (const g of groups.values()) {
        for (let i = 0; i < g.length; i++) {
          for (let j = i + 1; j < g.length; j++) {
            if (findPath(g[i].cell, g[j].cell)) return [g[i], g[j]];
          }
        }
      }
      return null;
    }

    function rebuildGrid() {
      grid.fill(null);
      alive.forEach(t => { grid[t.cell] = t; });
    }

    // Force a solvable move: find two connectable occupied cells and put a matching pair there.
    function forceMove() {
      for (let i = 0; i < alive.length; i++) {
        for (let j = i + 1; j < alive.length; j++) {
          const a = alive[i], b = alive[j];
          if (!findPath(a.cell, b.cell)) continue;
          const r = alive.find(t => t !== a && t.id === a.id);
          if (!r) continue;
          if (r !== b) { const c = b.cell; b.cell = r.cell; r.cell = c; rebuildGrid(); }
          return true;
        }
      }
      return false;
    }

    function reshuffle() {
      clearHint();
      setSel(null);
      const cells = alive.map(t => t.cell);
      for (let tries = 0; tries < 60; tries++) {
        shuffleArr(cells);
        alive.forEach((t, i) => { t.cell = cells[i]; });
        rebuildGrid();
        if (findMove()) break;
      }
      if (alive.length && !findMove()) forceMove();
      alive.forEach(place);
    }

    function applyGravity() {
      for (const s of lines) {
        const ts = s.map(c => grid[c]).filter(Boolean);
        s.forEach((c, i) => {
          const t = ts[i] || null;
          grid[c] = t;
          if (t && t.cell !== c) { t.cell = c; place(t); }
        });
      }
    }

    // ---------- game ----------
    function pickFaces(kinds) {
      const files = shuffleArr(pets().slice()).slice(0, kinds);
      const faces = files.map(f => petImage(f)).filter(Boolean);
      for (let i = faces.length; i < kinds; i++) faces.push(fallbackFace(i));
      return faces;
    }

    function newGame() {
      clearTimers();
      board.querySelectorAll('.llk-tile').forEach(n => n.remove());
      svg.innerHTML = '';
      lines = gravityLines(LEVELS[lv].g);
      const pairs = (COLS * ROWS) / 2;
      const kinds = Math.min(20, 15 + lv);
      const faces = pickFaces(kinds);
      const ids = [];
      for (let p = 0; p < pairs; p++) ids.push(p % kinds, p % kinds);
      shuffleArr(ids);
      grid = new Array(W * H).fill(null);
      alive = [];
      let k = 0, uid = 0;
      for (let y = 1; y <= ROWS; y++) {
        for (let x = 1; x <= COLS; x++) {
          const id = ids[k++];
          const e = document.createElement('div');
          e.className = 'llk-tile';
          e.innerHTML = '<img alt="" draggable="false">';
          e.firstChild.src = faces[id];
          e.style.animationDelay = ((x + y) * 14) + 'ms';
          const t = { uid: uid++, id, cell: idx(x, y), el: e };
          byEl.set(e, t);
          grid[t.cell] = t;
          alive.push(t);
          board.appendChild(e);
        }
      }
      sel = null; hintPair = null;
      locked = false; over = false; started = false; rewarded = false;
      timeLeft = TIME_MAX; lastTick = performance.now();
      score = 0; combo = 0; lastMatchAt = 0;
      hints = HINTS; shuffles = SHUFFLES;
      overlay.classList.add('hidden');
      if (!findMove()) reshuffle();
      fit();
      updateHud();
      updateTimer();
    }

    function setSel(t) {
      if (sel) sel.el.classList.remove('llk-sel');
      sel = t;
      if (sel) sel.el.classList.add('llk-sel');
    }

    function clearHint() {
      if (hintPair) hintPair.forEach(t => t.el.classList.remove('llk-hinted'));
      hintPair = null;
    }

    function drawPath(pts) {
      const poly = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
      poly.setAttribute('points', pts.map(([x, y]) => `${(x + 0.5) * S},${(y + 0.5) * S}`).join(' '));
      poly.setAttribute('pathLength', '1');
      poly.setAttribute('class', 'llk-line');
      svg.appendChild(poly);
      later(() => poly.remove(), PATH_MS);
    }

    function popCombo(n) {
      const s = document.createElement('span');
      s.className = 'llk-pop';
      s.textContent = `连击 ×${n}`;
      comboBox.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    function shake(t) {
      t.el.classList.remove('llk-bad');
      void t.el.offsetWidth;
      t.el.classList.add('llk-bad');
    }

    function tryMatch(a, b) {
      const path = findPath(a.cell, b.cell);
      if (!path) { shake(a); setSel(b); return; }
      setSel(null);
      if (hintPair && (hintPair.includes(a) || hintPair.includes(b))) clearHint();
      grid[a.cell] = null; grid[b.cell] = null;
      alive = alive.filter(t => t !== a && t !== b);
      a.el.classList.add('llk-gone'); b.el.classList.add('llk-gone');
      drawPath(path);

      const now = performance.now();
      combo = (lastMatchAt && now - lastMatchAt < COMBO_WINDOW) ? combo + 1 : 1;
      lastMatchAt = now;
      score += 10 + (combo - 1) * 5;
      if (combo >= 2) popCombo(combo);
      timeLeft = Math.min(TIME_MAX, timeLeft + MATCH_BONUS);
      updateHud(); updateTimer();

      const grav = LEVELS[lv].g !== 'none';
      if (grav) locked = true;
      later(() => {
        a.el.remove(); b.el.remove();
        if (over) return;
        if (grav) { applyGravity(); locked = false; }
        if (!alive.length) { win(); return; }
        if (!findMove()) {
          ctx.toast('没有可消除的方块了，自动洗牌');
          reshuffle();
        }
      }, PATH_MS);
    }

    function onBoardClick(e) {
      const tEl = e.target.closest('.llk-tile');
      if (!tEl || locked || over) return;
      const t = byEl.get(tEl);
      if (!t || !alive.includes(t)) return;
      if (!started) { started = true; lastTick = performance.now(); }
      if (!sel) { setSel(t); return; }
      if (sel === t) { setSel(null); return; }
      if (sel.id === t.id) tryMatch(sel, t);
      else setSel(t);
    }

    function showOverlay(title, sub, canNext) {
      ovTitle.textContent = title;
      ovSub.innerHTML = sub;
      nextBtn.style.display = canNext ? '' : 'none';
      overlay.classList.remove('hidden');
    }

    function win() {
      over = true;
      setSel(null); clearHint();
      const level = lv + 1;
      const bonus = Math.floor(timeLeft / 1000) * 2;
      score += bonus;
      const old = ctx.store.get(bestKey(), null);
      const rec = old == null || score > old;
      if (rec) ctx.store.set(bestKey(), score);
      updateHud();
      const coins = 8 + level * 2;
      showOverlay('通关成功！',
        `<div>第${level}关 · 得分 ${score}（剩余时间奖励 +${bonus}）</div>` +
        `<div>奖励小鱼干 +${coins}</div>` +
        (rec && old != null ? '<div class="llk-rec">新纪录！</div>' : ''),
        lv < LEVELS.length - 1);
      ctx.say(`连连看第${level}关通关啦！`);
      if (!rewarded) { rewarded = true; ctx.reward(coins, '连连看通关'); }
    }

    function lose() {
      over = true;
      setSel(null); clearHint();
      updateHud();
      showOverlay('时间到！', `<div>还剩 ${alive.length} 个方块 · 得分 ${score}</div><div>再试一次吧～</div>`, false);
    }

    function tick() {
      const now = performance.now();
      if (started && !over && ctx.isActive()) {
        timeLeft -= now - lastTick;
        if (timeLeft <= 0) { timeLeft = 0; updateTimer(); lose(); }
        else updateTimer();
      }
      lastTick = now;
    }

    function onHint() {
      hintBtn.blur();
      if (over || hints <= 0 || locked) return;
      const p = findMove();
      if (!p) return;
      hints--;
      clearHint();
      hintPair = p;
      p.forEach(t => t.el.classList.add('llk-hinted'));
      const pair = p;
      later(() => { if (hintPair === pair) clearHint(); }, 2500);
      updateHud();
    }
    function onShuffle() {
      shufBtn.blur();
      if (over || shuffles <= 0 || locked) return;
      shuffles--;
      reshuffle();
      updateHud();
    }
    function setLevel(i) {
      lv = i;
      ctx.store.set('level', lv);
      newGame();
    }
    function onLvClick(e) { const b = e.currentTarget; b.blur(); if (+b.dataset.lv !== lv) setLevel(+b.dataset.lv); }
    function onNew() { newBtn.blur(); newGame(); }
    function onAgain() { againBtn.blur(); newGame(); }
    function onNext() { nextBtn.blur(); setLevel(Math.min(LEVELS.length - 1, lv + 1)); }

    board.addEventListener('click', onBoardClick);
    hintBtn.addEventListener('click', onHint);
    shufBtn.addEventListener('click', onShuffle);
    newBtn.addEventListener('click', onNew);
    againBtn.addEventListener('click', onAgain);
    nextBtn.addEventListener('click', onNext);
    lvBtns.forEach(b => b.addEventListener('click', onLvClick));

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => fit());
      ro.observe(el.parentElement || el);
    } else {
      window.addEventListener('resize', fit);
    }

    newGame();
    const tickTimer = setInterval(tick, 100);

    cleanup = () => {
      clearTimers();
      clearInterval(tickTimer);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      board.removeEventListener('click', onBoardClick);
      hintBtn.removeEventListener('click', onHint);
      shufBtn.removeEventListener('click', onShuffle);
      newBtn.removeEventListener('click', onNew);
      againBtn.removeEventListener('click', onAgain);
      nextBtn.removeEventListener('click', onNext);
      lvBtns.forEach(b => b.removeEventListener('click', onLvClick));
      root.remove();
    };
  }

  Hub.register({
    id: 'lianliankan',
    title: '连连看',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><path d="M10 6.5h4.5v4M17.5 10.5V14" stroke-dasharray="2 2"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
