// 翻牌配对 — memory card-matching game module for the hub. See ../MODULES.md for the contract.
(function () {
  const LEVELS = [
    { key: 'easy',   name: '简单', cols: 4, rows: 3, reward: 3 },
    { key: 'normal', name: '普通', cols: 4, rows: 4, reward: 5 },
    { key: 'hard',   name: '困难', cols: 6, rows: 4, reward: 8 },
    { key: 'hell',   name: '地狱', cols: 6, rows: 6, reward: 12 }
  ];
  const MISMATCH_MS = 700;
  const WIN_DELAY_MS = 550;
  const RATIO = 1.25;           // card height / width
  const imgCache = new Map();   // pet file -> data: URL (shared across mounts)

  let cleanup = null;

  function petImage(file) {
    if (imgCache.has(file)) return imgCache.get(file);
    let url = '';
    try { url = (window.api && window.api.petImage(file)) || ''; } catch (_) { url = ''; }
    imgCache.set(file, url);
    return url;
  }

  // Fallback face if pet art is unavailable: colored paw badge with a number.
  function fallbackFace(i) {
    const hue = (i * 47) % 360;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" fill="hsl(${hue},70%,78%)"/><text x="50" y="64" font-size="42" text-anchor="middle" font-family="sans-serif" font-weight="700" fill="hsl(${hue},55%,30%)">${i + 1}</text></svg>`;
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  }

  function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  function fmtTime(ms) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }

  function starsFor(moves, pairs) {
    if (moves <= Math.ceil(pairs * 1.5)) return 3;
    if (moves <= Math.ceil(pairs * 2.2)) return 2;
    return 1;
  }
  const starStr = n => '★'.repeat(n) + '☆'.repeat(3 - n);

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'mm-root';
    root.innerHTML = `
      <div class="mm-bar">
        <div class="mm-stats">
          <div class="mm-stat"><span class="mm-lbl">步数</span><b class="mm-moves">0</b></div>
          <div class="mm-stat"><span class="mm-lbl">用时</span><b class="mm-time">0:00</b></div>
          <div class="mm-stat mm-combo-box"><span class="mm-lbl">连击</span><b class="mm-combo">0</b></div>
          <div class="mm-stat"><span class="mm-lbl">最佳</span><b class="mm-best">—</b></div>
        </div>
        <div class="mm-opts">
          <div class="mm-seg" role="group" aria-label="难度">
            ${LEVELS.map((l, i) => `<button type="button" data-lv="${i}" title="${l.cols}×${l.rows}">${l.name}</button>`).join('')}
          </div>
          <button type="button" class="mm-btn mm-primary mm-new">新游戏</button>
        </div>
      </div>
      <div class="mm-stage">
        <div class="mm-grid"></div>
        <div class="mm-overlay hidden">
          <div class="mm-card-ov">
            <div class="mm-ov-title">全部配对成功！</div>
            <div class="mm-ov-stars"></div>
            <div class="mm-ov-sub"></div>
            <div class="mm-ov-btns">
              <button type="button" class="mm-btn mm-primary mm-again">再来一局</button>
            </div>
          </div>
        </div>
      </div>
      <div class="mm-help">点击翻开两张牌，图案相同即配对成功 · 连续配对可叠加连击</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.mm-stage'), grid = $('.mm-grid');
    const movesEl = $('.mm-moves'), timeEl = $('.mm-time'), comboEl = $('.mm-combo'), bestEl = $('.mm-best');
    const comboBox = $('.mm-combo-box');
    const overlay = $('.mm-overlay'), ovStars = $('.mm-ov-stars'), ovSub = $('.mm-ov-sub');
    const newBtn = $('.mm-new'), againBtn = $('.mm-again');
    const lvBtns = [...root.querySelectorAll('[data-lv]')];

    // ---------- state ----------
    let lv = ctx.store.get('level', 1);
    if (!(lv >= 0 && lv < LEVELS.length)) lv = 1;
    let cards = [];          // { id, face, el, up, matched }
    let open = [];           // currently face-up unmatched cards (max 2)
    let locked = false;
    let moves = 0, matched = 0, combo = 0, maxCombo = 0;
    let started = false, finished = false, rewarded = false;
    let elapsed = 0, lastTick = 0;
    let mismatchTimer = 0, winTimer = 0, tickTimer = 0;

    const level = () => LEVELS[lv];
    const bestKey = () => 'best_' + level().key;
    const getBest = () => ctx.store.get(bestKey(), null);

    // ---------- layout ----------
    function fit() {
      const { cols, rows } = level();
      const gap = cols >= 6 && rows >= 6 ? 8 : 10;
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;   // bar + help + paddings + gaps
      const aw = Math.max(200, stage.clientWidth - 8);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 8);
      let w = (aw - gap * (cols - 1)) / cols;
      const hFromH = (ah - gap * (rows - 1)) / rows;
      w = Math.min(w, hFromH / RATIO, 120);
      w = Math.max(36, Math.floor(w));
      grid.style.setProperty('--mm-w', w + 'px');
      grid.style.setProperty('--mm-h', Math.floor(w * RATIO) + 'px');
      grid.style.setProperty('--mm-gap', gap + 'px');
      grid.style.gridTemplateColumns = `repeat(${cols}, var(--mm-w))`;
    }

    // ---------- HUD ----------
    function updateHud() {
      movesEl.textContent = moves;
      timeEl.textContent = fmtTime(elapsed);
      comboEl.textContent = combo;
      const b = getBest();
      bestEl.textContent = b ? `${b.moves}步 · ${fmtTime(b.time)}` : '—';
      lvBtns.forEach(bt => bt.classList.toggle('active', +bt.dataset.lv === lv));
    }

    function tick() {
      const now = performance.now();
      if (started && !finished && ctx.isActive()) {
        elapsed += now - lastTick;
        timeEl.textContent = fmtTime(elapsed);
      }
      lastTick = now;
    }

    function popCombo(n) {
      const s = document.createElement('span');
      s.className = 'mm-pop';
      s.textContent = `连击 ×${n}`;
      comboBox.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    // ---------- game ----------
    function pickFaces(n) {
      let files = [];
      try { files = (window.api && window.api.pets()) || []; } catch (_) { files = []; }
      const chosen = shuffle(files.slice()).slice(0, n);
      const faces = chosen.map(f => petImage(f)).filter(Boolean);
      for (let i = faces.length; i < n; i++) faces.push(fallbackFace(i));
      return faces;
    }

    function clearTimers() {
      clearTimeout(mismatchTimer); mismatchTimer = 0;
      clearTimeout(winTimer); winTimer = 0;
    }

    function newGame() {
      clearTimers();
      const { cols, rows } = level();
      const pairs = (cols * rows) / 2;
      const faces = pickFaces(pairs);
      const deck = shuffle(faces.flatMap((f, i) => [{ id: i, face: f }, { id: i, face: f }]));
      grid.innerHTML = '';
      cards = deck.map((d, idx) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'mm-card';
        b.dataset.idx = idx;
        b.setAttribute('aria-label', '背面朝上的牌');
        b.innerHTML = `<div class="mm-inner"><div class="mm-face mm-back"></div><div class="mm-face mm-front"><img alt="" draggable="false"></div></div>`;
        b.querySelector('img').src = d.face;
        b.style.animationDelay = (idx * 18) + 'ms';
        grid.appendChild(b);
        return { id: d.id, face: d.face, el: b, up: false, matched: false };
      });
      open = []; locked = false;
      moves = 0; matched = 0; combo = 0; maxCombo = 0;
      started = false; finished = false; rewarded = false;
      elapsed = 0; lastTick = performance.now();
      overlay.classList.add('hidden');
      fit();
      updateHud();
    }

    function setUp(c, up) {
      c.up = up;
      c.el.classList.toggle('mm-up', up);
      c.el.setAttribute('aria-label', up ? '已翻开的牌' : '背面朝上的牌');
    }

    function flip(c) {
      if (locked || finished || c.up || c.matched) return;
      if (!started) { started = true; lastTick = performance.now(); }
      setUp(c, true);
      open.push(c);
      if (open.length < 2) return;

      moves++;
      const [a, b] = open;
      open = [];
      if (a.id === b.id) {
        a.matched = b.matched = true;
        matched++;
        combo++;
        if (combo > maxCombo) maxCombo = combo;
        if (combo >= 2) popCombo(combo);
        [a, b].forEach(x => {
          x.el.classList.add('mm-matched');
          x.el.setAttribute('aria-label', '已配对');
        });
        updateHud();
        if (matched === cards.length / 2) {
          tick();
          finished = true;
          winTimer = setTimeout(win, WIN_DELAY_MS);
        }
      } else {
        combo = 0;
        locked = true;
        [a, b].forEach(x => x.el.classList.add('mm-miss'));
        updateHud();
        mismatchTimer = setTimeout(() => {
          mismatchTimer = 0;
          [a, b].forEach(x => { x.el.classList.remove('mm-miss'); setUp(x, false); });
          locked = false;
        }, MISMATCH_MS);
      }
    }

    function win() {
      winTimer = 0;
      const L = level();
      const pairs = cards.length / 2;
      const stars = starsFor(moves, pairs);
      const time = Math.round(elapsed);
      const old = getBest();
      const newMoves = !old || moves < old.moves;
      const newTime = !old || time < old.time;
      ctx.store.set(bestKey(), {
        moves: old ? Math.min(old.moves, moves) : moves,
        time: old ? Math.min(old.time, time) : time
      });
      updateHud();

      ovStars.textContent = starStr(stars);
      const rec = [];
      if (old && newMoves) rec.push('最少步数新纪录！');
      if (old && newTime) rec.push('最快用时新纪录！');
      ovSub.innerHTML =
        `<div>${L.name} ${L.cols}×${L.rows} · ${moves} 步 · ${fmtTime(time)}</div>` +
        `<div>最高连击 ${maxCombo} · 奖励小鱼干 +${L.reward}</div>` +
        (rec.length ? `<div class="mm-rec">${rec.join(' ')}</div>` : '');
      overlay.classList.remove('hidden');
      overlay.style.animation = 'none';
      void overlay.offsetWidth;
      overlay.style.animation = '';

      ctx.say('翻牌全部配对成功！');
      if (!rewarded) {
        rewarded = true;
        ctx.reward(L.reward, '翻牌配对');
      }
    }

    function setLevel(i) {
      if (i === lv) return;
      lv = i;
      ctx.store.set('level', lv);
      newGame();
    }

    // ---------- input ----------
    function onGridClick(e) {
      const b = e.target.closest('.mm-card');
      if (!b || !grid.contains(b)) return;
      const c = cards[+b.dataset.idx];
      if (c) flip(c);
    }
    function onLvClick(e) { const b = e.currentTarget; b.blur(); setLevel(+b.dataset.lv); }
    function onNew() { newBtn.blur(); newGame(); }
    function onAgain() { againBtn.blur(); newGame(); }

    grid.addEventListener('click', onGridClick);
    lvBtns.forEach(b => b.addEventListener('click', onLvClick));
    newBtn.addEventListener('click', onNew);
    againBtn.addEventListener('click', onAgain);

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => fit());
      ro.observe(el.parentElement || el);
    } else {
      window.addEventListener('resize', fit);
    }

    newGame();
    tickTimer = setInterval(tick, 250);

    cleanup = () => {
      clearTimers();
      clearInterval(tickTimer);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      grid.removeEventListener('click', onGridClick);
      lvBtns.forEach(b => b.removeEventListener('click', onLvClick));
      newBtn.removeEventListener('click', onNew);
      againBtn.removeEventListener('click', onAgain);
      root.remove();
    };
  }

  Hub.register({
    id: 'memory',
    title: '翻牌配对',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="4" width="8" height="12" rx="2" transform="rotate(-8 7 10)"/><rect x="12" y="6" width="8" height="12" rx="2" transform="rotate(8 16 12)" fill="currentColor" fill-opacity=".25"/><circle cx="16" cy="12" r="1.6" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
