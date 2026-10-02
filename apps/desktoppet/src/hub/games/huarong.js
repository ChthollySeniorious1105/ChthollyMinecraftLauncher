// 数字华容道 — sliding number puzzle module for the hub. See ../MODULES.md for the contract.
(function () {
  const SIZES = [
    { n: 3, name: '3×3', reward: 3 },
    { n: 4, name: '4×4', reward: 8 },
    { n: 5, name: '5×5', reward: 15 }
  ];
  const KEYMAP = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    KeyW: 'up', KeyS: 'down', KeyA: 'left', KeyD: 'right'
  };
  const WIN_DELAY_MS = 260;

  let cleanup = null;

  function fmtTime(ms) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }

  function isSolved(t) {
    for (let i = 0; i < t.length - 1; i++) if (t[i] !== i + 1) return false;
    return t[t.length - 1] === 0;
  }

  // Random solvable arrangement: random even permutation with blank in the corner,
  // then a random walk of the blank (walks never break solvability).
  function makeShuffle(n) {
    const N = n * n;
    let t;
    do {
      const nums = [];
      for (let i = 1; i < N; i++) nums.push(i);
      for (let i = nums.length - 1; i > 0; i--) {
        const j = (Math.random() * (i + 1)) | 0;
        [nums[i], nums[j]] = [nums[j], nums[i]];
      }
      let inv = 0;
      for (let i = 0; i < nums.length; i++) for (let j = i + 1; j < nums.length; j++) if (nums[i] > nums[j]) inv++;
      if (inv % 2) [nums[0], nums[1]] = [nums[1], nums[0]];
      t = nums.concat(0);
      let b = N - 1, prev = -1;
      const walk = n * n * 3 + ((Math.random() * n * 4) | 0);
      for (let k = 0; k < walk; k++) {
        const r = (b / n) | 0, c = b % n;
        const opts = [];
        if (r > 0) opts.push(b - n);
        if (r < n - 1) opts.push(b + n);
        if (c > 0) opts.push(b - 1);
        if (c < n - 1) opts.push(b + 1);
        const cand = opts.filter(o => o !== prev);
        const nb = cand[(Math.random() * cand.length) | 0];
        t[b] = t[nb]; t[nb] = 0; prev = b; b = nb;
      }
    } while (isSolved(t));
    return t;
  }

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'hr-root';
    root.innerHTML = `
      <div class="hr-bar">
        <div class="hr-stats">
          <div class="hr-stat"><span class="hr-lbl">步数</span><b class="hr-moves">0</b></div>
          <div class="hr-stat"><span class="hr-lbl">用时</span><b class="hr-time">0:00</b></div>
          <div class="hr-stat"><span class="hr-lbl">最佳</span><b class="hr-best">—</b></div>
        </div>
        <div class="hr-opts">
          <div class="hr-seg" role="group" aria-label="尺寸">
            ${SIZES.map((s, i) => `<button type="button" data-sz="${i}">${s.name}</button>`).join('')}
          </div>
          <button type="button" class="hr-btn hr-primary hr-new">重新打乱</button>
        </div>
      </div>
      <div class="hr-stage">
        <div class="hr-board"></div>
        <div class="hr-overlay hidden">
          <div class="hr-card">
            <div class="hr-ov-title">拼好啦！</div>
            <div class="hr-ov-sub"></div>
            <div class="hr-ov-btns"><button type="button" class="hr-btn hr-primary hr-again">再来一局</button></div>
          </div>
        </div>
      </div>
      <div class="hr-help">点击空格同行 / 同列的数字即可滑动 · 方向键 / WASD 移动 · 按 1→N 顺序排好，空格留在右下角</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.hr-stage'), board = $('.hr-board');
    const movesEl = $('.hr-moves'), timeEl = $('.hr-time'), bestEl = $('.hr-best');
    const overlay = $('.hr-overlay'), ovSub = $('.hr-ov-sub');
    const newBtn = $('.hr-new'), againBtn = $('.hr-again');
    const szBtns = [...root.querySelectorAll('[data-sz]')];

    // ---------- state ----------
    let sz = ctx.store.get('size', 1);
    if (!(sz >= 0 && sz < SIZES.length)) sz = 1;
    let tiles = [];            // index -> number (0 = blank)
    let tileEls = [];          // number -> element
    let moves = 0, started = false, finished = false, rewarded = false;
    let elapsed = 0, lastTick = 0, tickTimer = 0, winTimer = 0;

    const size = () => SIZES[sz];
    const bestKey = () => 'best_' + size().n;
    const getBest = () => ctx.store.get(bestKey(), null);

    // ---------- layout ----------
    function fit() {
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(200, stage.clientWidth - 8);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 8);
      const px = Math.floor(Math.min(aw, ah, 460));
      board.style.setProperty('--hr-size', px + 'px');
    }

    function place(num, idx, animate) {
      const e = tileEls[num];
      if (!e) return;
      const n = size().n;
      const r = (idx / n) | 0, c = idx % n;
      if (!animate) e.classList.add('hr-noanim');
      e.style.setProperty('--r', r);
      e.style.setProperty('--c', c);
      e.classList.toggle('hr-ok', num === idx + 1);
      if (!animate) { void e.offsetWidth; e.classList.remove('hr-noanim'); }
    }

    // ---------- HUD ----------
    function updateHud() {
      movesEl.textContent = moves;
      timeEl.textContent = fmtTime(elapsed);
      const b = getBest();
      bestEl.textContent = b ? `${b.moves}步 · ${fmtTime(b.time)}` : '—';
      szBtns.forEach(bt => bt.classList.toggle('active', +bt.dataset.sz === sz));
    }

    function tick() {
      const now = performance.now();
      if (started && !finished && ctx.isActive()) {
        elapsed += now - lastTick;
        timeEl.textContent = fmtTime(elapsed);
      }
      lastTick = now;
    }

    // ---------- game ----------
    function newGame() {
      clearTimeout(winTimer); winTimer = 0;
      const n = size().n;
      tiles = makeShuffle(n);
      board.innerHTML = '';
      board.style.setProperty('--n', n);
      board.classList.toggle('hr-big', n >= 5);
      tileEls = [null];
      for (let num = 1; num < n * n; num++) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'hr-tile';
        b.dataset.num = num;
        b.innerHTML = `<span>${num}</span>`;
        board.appendChild(b);
        tileEls[num] = b;
      }
      tiles.forEach((num, idx) => { if (num) place(num, idx, false); });
      moves = 0; started = false; finished = false; rewarded = false;
      elapsed = 0; lastTick = performance.now();
      overlay.classList.add('hidden');
      board.classList.remove('hr-done');
      fit();
      updateHud();
    }

    // Slide the tile at idx (and any tiles between it and the blank) toward the blank.
    function slideFrom(idx) {
      if (finished) return false;
      const n = size().n;
      const b = tiles.indexOf(0);
      if (idx === b || idx < 0 || idx >= tiles.length) return false;
      const br = (b / n) | 0, bc = b % n, r = (idx / n) | 0, c = idx % n;
      let step;
      if (r === br) step = c > bc ? 1 : -1;
      else if (c === bc) step = r > br ? n : -n;
      else return false;
      if (!started) { started = true; lastTick = performance.now(); }
      let cur = b;
      while (cur !== idx) {
        const nxt = cur + step;
        tiles[cur] = tiles[nxt];
        tiles[nxt] = 0;
        place(tiles[cur], cur, true);
        cur = nxt;
        moves++;
      }
      updateHud();
      if (isSolved(tiles)) {
        tick();
        finished = true;
        board.classList.add('hr-done');
        winTimer = setTimeout(win, WIN_DELAY_MS);
      }
      return true;
    }

    function moveDir(d) {
      const n = size().n;
      const b = tiles.indexOf(0);
      const br = (b / n) | 0, bc = b % n;
      // the tile that moves INTO the blank in direction d sits on the opposite side of the blank
      if (d === 'up' && br < n - 1) return slideFrom(b + n);
      if (d === 'down' && br > 0) return slideFrom(b - n);
      if (d === 'left' && bc < n - 1) return slideFrom(b + 1);
      if (d === 'right' && bc > 0) return slideFrom(b - 1);
      return false;
    }

    function win() {
      winTimer = 0;
      const S = size();
      const time = Math.round(elapsed);
      const old = getBest();
      const newMoves = !old || moves < old.moves;
      const newTime = !old || time < old.time;
      ctx.store.set(bestKey(), {
        moves: old ? Math.min(old.moves, moves) : moves,
        time: old ? Math.min(old.time, time) : time
      });
      updateHud();
      const rec = [];
      if (old && newMoves) rec.push('最少步数新纪录！');
      if (old && newTime) rec.push('最快用时新纪录！');
      ovSub.innerHTML =
        `<div>${S.name} · ${moves} 步 · ${fmtTime(time)}</div>` +
        `<div>奖励小鱼干 +${S.reward}</div>` +
        (rec.length ? `<div class="hr-rec">${rec.join(' ')}</div>` : '');
      overlay.classList.remove('hidden');
      if (rec.length) ctx.say(`数字华容道 ${S.name} ${rec[0]}`);
      else ctx.say(`数字华容道 ${S.name} 完成啦！`);
      if (!rewarded) {
        rewarded = true;
        ctx.reward(S.reward, '数字华容道完成');
      }
    }

    function setSize(i) {
      if (i === sz) return;
      sz = i;
      ctx.store.set('size', sz);
      newGame();
    }

    // ---------- input ----------
    function onBoardClick(e) {
      const t = e.target.closest('.hr-tile');
      if (!t || !board.contains(t)) return;
      t.blur();
      const idx = tiles.indexOf(+t.dataset.num);
      if (!slideFrom(idx)) {
        t.classList.remove('hr-nope'); void t.offsetWidth; t.classList.add('hr-nope');
      }
    }
    function onKey(e) {
      if (!ctx.isActive()) return;
      const tg = e.target;
      if (tg && (tg.tagName === 'INPUT' || tg.tagName === 'TEXTAREA' || tg.isContentEditable)) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      const d = KEYMAP[e.code];
      if (d) {
        e.preventDefault();
        if (!finished) moveDir(d);
      } else if ((e.code === 'Enter' || e.code === 'Space') && finished && !overlay.classList.contains('hidden')) {
        e.preventDefault();
        newGame();
      }
    }
    function onSz(e) { const b = e.currentTarget; b.blur(); setSize(+b.dataset.sz); }
    function onNew() { newBtn.blur(); newGame(); }
    function onAgain() { againBtn.blur(); newGame(); }

    board.addEventListener('click', onBoardClick);
    szBtns.forEach(b => b.addEventListener('click', onSz));
    newBtn.addEventListener('click', onNew);
    againBtn.addEventListener('click', onAgain);
    window.addEventListener('keydown', onKey);

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
      clearTimeout(winTimer);
      clearInterval(tickTimer);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      window.removeEventListener('keydown', onKey);
      board.removeEventListener('click', onBoardClick);
      szBtns.forEach(b => b.removeEventListener('click', onSz));
      newBtn.removeEventListener('click', onNew);
      againBtn.removeEventListener('click', onAgain);
      root.remove();
    };
  }

  Hub.register({
    id: 'huarong',
    title: '数字华容道',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><rect x="5.5" y="5.5" width="5.5" height="5.5" rx="1" fill="currentColor" fill-opacity=".3"/><rect x="13" y="5.5" width="5.5" height="5.5" rx="1" fill="currentColor" fill-opacity=".3"/><rect x="5.5" y="13" width="5.5" height="5.5" rx="1" fill="currentColor" fill-opacity=".3"/><path d="M14 15.8h4M16.6 14l1.8 1.8-1.8 1.8" stroke-linecap="round"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
