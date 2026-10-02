// 宠物消消乐 — match-3 with pet tiles, specials and cascades. See ../MODULES.md for the contract.
(function () {
  const N = 8, KINDS = 6;
  const MODES = { time: { name: '限时 60 秒', time: 60 }, moves: { name: '限步 30 步', moves: 30 } };
  const FALLBACK = ['#e8553a', '#f3c34a', '#5da35a', '#4a90d9', '#9b6ad8', '#e86aa8'];
  let cleanup = null;

  function petFaces() {
    try {
      const list = (window.api && window.api.pets()) || [];
      const files = list.map(p => (typeof p === 'string' ? p : p.file)).filter(Boolean);
      for (let i = files.length - 1; i > 0; i--) { const j = (Math.random() * (i + 1)) | 0; [files[i], files[j]] = [files[j], files[i]]; }
      return files.slice(0, KINDS).map(f => window.api.petImage(f)).filter(Boolean);
    } catch (_) { return []; }
  }

  function mount(el, ctx) {
    let mode = MODES[ctx.store.get('mode')] ? ctx.store.get('mode') : 'time';
    const bests = ctx.store.get('best', {}) || {};
    const root = document.createElement('div');
    root.className = 'm3-root';
    root.innerHTML = `
      <div class="m3-side">
        <div class="m3-stat big"><span>得分</span><b class="m3-score">0</b></div>
        <div class="m3-stat"><span class="m3-lim-l">时间</span><b class="m3-lim">60</b></div>
        <div class="m3-stat"><span>最佳</span><b class="m3-best">0</b></div>
        <div class="m3-seg">${Object.entries(MODES).map(([k, m]) => `<button data-m="${k}">${m.name}</button>`).join('')}</div>
        <button class="btn m3-hintbtn">提示</button>
        <button class="btn primary m3-new">新游戏</button>
        <div class="m3-legend">
          <div><i class="m3-lg line"></i>4 连：直线消除</div>
          <div><i class="m3-lg bomb"></i>L / T 形：3×3 炸弹</div>
          <div><i class="m3-lg color"></i>5 连：同色全消</div>
        </div>
      </div>
      <div class="m3-main">
        <div class="m3-board"><div class="m3-tiles"></div><div class="m3-combo"></div>
          <div class="m3-ov"><div class="m3-card"><div class="m3-title">宠物消消乐</div><div class="m3-sub"></div><button class="btn primary m3-go">开始</button></div></div>
        </div>
        <div class="m3-help">点击两个相邻的宠物交换位置，或直接拖动 · 三个及以上连成一线即可消除 · 连锁越多分越高 · P 暂停</div>
      </div>`;
    el.appendChild(root);
    const q = s => root.querySelector(s);
    const tilesBox = q('.m3-tiles'), board = q('.m3-board');

    let faces = petFaces();
    let grid = [], state = 'ready', score = 0, left = 0, sel = null, busy = false, chain = 0, timer = 0, idleT = 0, hintEls = [], uid = 0;
    // cell: { id, k (kind 0..5), sp: null|'h'|'v'|'bomb'|'color', el }

    const at = (r, c) => (r >= 0 && r < N && c >= 0 && c < N ? grid[r][c] : null);
    function tileHTML(t) {
      const face = faces[t.k] ? `<img src="${faces[t.k]}" draggable="false" alt="">` : `<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="15" fill="${FALLBACK[t.k]}"/><circle cx="15" cy="15" r="5" fill="#fff" opacity=".45"/></svg>`;
      return `<div class="m3-face">${face}</div>`;
    }
    function makeTile(k, r, c, fromRow) {
      const t = { id: ++uid, k, sp: null, el: document.createElement('div') };
      t.el.className = `m3-tile k${k}`;
      t.el.innerHTML = tileHTML(t);
      t.el.style.setProperty('--r', fromRow != null ? fromRow : r);
      t.el.style.setProperty('--c', c);
      tilesBox.appendChild(t.el);
      return t;
    }
    function place(t, r, c) { t.el.style.setProperty('--r', r); t.el.style.setProperty('--c', c); t.r = r; t.c = c; }
    function setSpecial(t, sp) {
      t.sp = sp;
      t.el.classList.remove('sp-h', 'sp-v', 'sp-bomb', 'sp-color');
      if (sp) t.el.classList.add('sp-' + sp);
      if (sp === 'color') { t.k = -1; t.el.innerHTML = '<div class="m3-face"><svg viewBox="0 0 40 40"><defs><radialGradient id="m3rb" cx="35%" cy="30%"><stop offset="0" stop-color="#fff"/><stop offset=".4" stop-color="#ffd34d"/><stop offset="1" stop-color="#e8553a"/></radialGradient></defs><circle cx="20" cy="20" r="15" fill="url(#m3rb)"/><path d="M20 8l3 8 8 1-6 5 2 8-7-4-7 4 2-8-6-5 8-1z" fill="#fff" opacity=".9"/></svg></div>'; }
    }

    function findRuns() {
      const runs = [];
      for (let r = 0; r < N; r++) {
        let c = 0;
        while (c < N) {
          const t = grid[r][c]; let e = c + 1;
          if (t && t.k >= 0) while (e < N && grid[r][e] && grid[r][e].k === t.k) e++;
          if (t && t.k >= 0 && e - c >= 3) runs.push({ dir: 'h', cells: Array.from({ length: e - c }, (_, i) => [r, c + i]) });
          c = e;
        }
      }
      for (let c = 0; c < N; c++) {
        let r = 0;
        while (r < N) {
          const t = grid[r][c]; let e = r + 1;
          if (t && t.k >= 0) while (e < N && grid[e][c] && grid[e][c].k === t.k) e++;
          if (t && t.k >= 0 && e - r >= 3) runs.push({ dir: 'v', cells: Array.from({ length: e - r }, (_, i) => [r + i, c]) });
          r = e;
        }
      }
      return runs;
    }
    function hasMove() {
      for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
        for (const [dr, dc] of [[0, 1], [1, 0]]) {
          const a = at(r, c), b = at(r + dr, c + dc);
          if (!a || !b) continue;
          if (a.sp === 'color' || b.sp === 'color') return [[r, c], [r + dr, c + dc]];
          swapData(r, c, r + dr, c + dc);
          const ok = findRuns().length > 0;
          swapData(r, c, r + dr, c + dc);
          if (ok) return [[r, c], [r + dr, c + dc]];
        }
      }
      return null;
    }
    function swapData(r1, c1, r2, c2) { const t = grid[r1][c1]; grid[r1][c1] = grid[r2][c2]; grid[r2][c2] = t; }

    function fill() {
      tilesBox.innerHTML = '';
      do {
        grid = [];
        for (let r = 0; r < N; r++) {
          grid.push([]);
          for (let c = 0; c < N; c++) {
            let k;
            do { k = (Math.random() * KINDS) | 0; }
            while ((c >= 2 && grid[r][c - 1].k === k && grid[r][c - 2].k === k) || (r >= 2 && grid[r - 1][c].k === k && grid[r - 2][c].k === k));
            grid[r].push({ k });
          }
        }
      } while (!hasMove());
      for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
        const t = makeTile(grid[r][c].k, r, c, r - N - 1);
        grid[r][c] = t; t.r = r; t.c = c;
        t.el.style.transitionDelay = `${(N - r) * 25 + c * 8}ms`;
      }
      requestAnimationFrame(() => requestAnimationFrame(() => { for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) place(grid[r][c], r, c); setTimeout(clearDelays, 600); }));
    }
    function clearDelays() { for (const row of grid) for (const t of row) if (t) t.el.style.transitionDelay = ''; }

    const wait = ms => new Promise(r => setTimeout(r, ms));
    async function trySwap(a, b) {
      if (busy || state !== 'run') return;
      clearHint();
      busy = true;
      const ta = at(a[0], a[1]), tb = at(b[0], b[1]);
      swapData(a[0], a[1], b[0], b[1]);
      place(ta, b[0], b[1]); place(tb, a[0], a[1]);
      await wait(180);
      // colour bomb swapped with anything clears that colour
      if (ta.sp === 'color' || tb.sp === 'color') {
        useMove();
        const bomb = ta.sp === 'color' ? ta : tb, other = bomb === ta ? tb : ta;
        const kill = new Set([key(bomb.r, bomb.c)]);
        for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
          const t = grid[r][c];
          if (other.sp === 'color' || (t && t.k === other.k)) kill.add(key(r, c));
        }
        chain = 1;
        await clearCells(kill, null);
        await cascade();
        busy = false;
        afterTurn();
        return;
      }
      const runs = findRuns();
      if (!runs.length) {
        swapData(a[0], a[1], b[0], b[1]);
        place(ta, a[0], a[1]); place(tb, b[0], b[1]);
        ta.el.classList.add('nope'); tb.el.classList.add('nope');
        await wait(200);
        ta.el.classList.remove('nope'); tb.el.classList.remove('nope');
        busy = false;
        return;
      }
      useMove();
      chain = 0;
      await resolve(runs, [b, a]);
      await cascade();
      busy = false;
      afterTurn();
    }
    const key = (r, c) => r * N + c;
    function useMove() { if (mode === 'moves') { left--; hud(); } }

    // runs → cleared cells (+ spawn specials at the swapped spot or run centre)
    async function resolve(runs, prefer) {
      chain++;
      const kill = new Set(), spawn = [];
      const cellRuns = new Map();
      for (const run of runs) for (const [r, c] of run.cells) { const k = key(r, c); cellRuns.set(k, (cellRuns.get(k) || []).concat(run)); kill.add(k); }
      const usedRuns = new Set();
      // L/T shapes: a cell shared by a horizontal and a vertical run
      for (const [k, rs] of cellRuns) {
        if (rs.length > 1 && rs.some(x => x.dir === 'h') && rs.some(x => x.dir === 'v')) {
          spawn.push({ k, sp: 'bomb', kind: grid[Math.floor(k / N)][k % N].k });
          rs.forEach(x => usedRuns.add(x));
        }
      }
      for (const run of runs) {
        if (usedRuns.has(run) || run.cells.length < 4) continue;
        const pos = run.cells.find(([r, c]) => prefer && prefer.some(p => p[0] === r && p[1] === c)) || run.cells[Math.floor(run.cells.length / 2)];
        const [r, c] = pos;
        spawn.push({ k: key(r, c), sp: run.cells.length >= 5 ? 'color' : run.dir === 'h' ? 'v' : 'h', kind: grid[r][c].k });
      }
      const keep = new Set(spawn.map(s => s.k));
      await clearCells(kill, keep);
      for (const s of spawn) {
        const r = Math.floor(s.k / N), c = s.k % N;
        const t = grid[r][c];
        if (t) { setSpecial(t, s.sp); t.el.classList.add('born'); setTimeout(() => t.el.classList.remove('born'), 400); }
      }
    }
    // clears cells; triggers specials caught in the blast
    async function clearCells(kill, keep) {
      const queue = [...kill];
      const seen = new Set(queue);
      while (queue.length) {
        const k = queue.shift();
        const r = Math.floor(k / N), c = k % N, t = grid[r][c];
        if (!t || (keep && keep.has(k)) || !t.sp) continue;
        const add = (rr, cc) => { if (rr < 0 || rr >= N || cc < 0 || cc >= N) return; const kk = key(rr, cc); if (!seen.has(kk)) { seen.add(kk); queue.push(kk); } };
        if (t.sp === 'h') for (let x = 0; x < N; x++) add(r, x);
        if (t.sp === 'v') for (let y = 0; y < N; y++) add(y, c);
        if (t.sp === 'bomb') for (let y = -1; y <= 1; y++) for (let x = -1; x <= 1; x++) add(r + y, c + x);
        if (t.sp === 'color') { const kinds = {}; for (const row of grid) for (const x of row) if (x && x.k >= 0) kinds[x.k] = (kinds[x.k] || 0) + 1; const top = +Object.keys(kinds).sort((a, b) => kinds[b] - kinds[a])[0]; for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (grid[y][x] && grid[y][x].k === top) add(y, x); }
        if (t.sp === 'h' || t.sp === 'v' || t.sp === 'bomb') beam(t.sp, r, c);
      }
      let n = 0;
      for (const k of seen) {
        if (keep && keep.has(k)) continue;
        const r = Math.floor(k / N), c = k % N, t = grid[r][c];
        if (!t) continue;
        n++;
        t.el.classList.add('pop');
        const el = t.el;
        setTimeout(() => el.remove(), 260);
        grid[r][c] = null;
      }
      const gain = n * 10 * chain + (n > 3 ? (n - 3) * 15 : 0);
      score += gain;
      showCombo(gain);
      hud();
      await wait(230);
    }
    function beam(sp, r, c) {
      const b = document.createElement('div');
      b.className = `m3-beam ${sp}`;
      b.style.setProperty('--r', r); b.style.setProperty('--c', c);
      tilesBox.appendChild(b);
      setTimeout(() => b.remove(), 400);
    }
    function showCombo(gain) {
      const el = q('.m3-combo');
      el.textContent = chain > 1 ? `${chain} 连锁！+${gain}` : `+${gain}`;
      el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
    }
    async function cascade() {
      for (;;) {
        // gravity
        for (let c = 0; c < N; c++) {
          let w = N - 1;
          for (let r = N - 1; r >= 0; r--) {
            const t = grid[r][c];
            if (t) { if (w !== r) { grid[w][c] = t; grid[r][c] = null; place(t, w, c); } w--; }
          }
          for (let r = w, i = 0; r >= 0; r--, i++) {
            const t = makeTile((Math.random() * KINDS) | 0, r, c, -1 - i);
            grid[r][c] = t; t.r = r; t.c = c;
          }
        }
        await wait(20);
        for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) place(grid[r][c], r, c);
        await wait(260);
        const runs = findRuns();
        if (!runs.length) break;
        await resolve(runs, null);
      }
      if (!hasMove()) await shuffle();
    }
    async function shuffle() {
      const all = grid.flat();
      do {
        for (let i = all.length - 1; i > 0; i--) { const j = (Math.random() * (i + 1)) | 0; [all[i], all[j]] = [all[j], all[i]]; }
        for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) grid[r][c] = all[r * N + c];
      } while (findRuns().length || !hasMove());
      flash('没有可消的了，重新洗牌！');
      for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) place(grid[r][c], r, c);
      await wait(350);
    }
    function flash(t) { const el = q('.m3-combo'); el.textContent = t; el.classList.remove('show'); void el.offsetWidth; el.classList.add('show'); }

    function afterTurn() {
      armHint();
      if (mode === 'moves' && left <= 0) end();
    }
    function clearHint() { clearTimeout(idleT); hintEls.forEach(e => e.classList.remove('hint')); hintEls = []; }
    function armHint() { clearHint(); idleT = setTimeout(showHint, 5000); }
    function showHint() {
      if (state !== 'run' || busy) return;
      const m = hasMove();
      if (!m) return;
      hintEls = m.map(([r, c]) => grid[r][c].el);
      hintEls.forEach(e => e.classList.add('hint'));
    }

    // ---------- input: click-click or drag ----------
    let down = null;
    function cellFromEvent(e) {
      const rect = tilesBox.getBoundingClientRect();
      const c = Math.floor((e.clientX - rect.left) / rect.width * N), r = Math.floor((e.clientY - rect.top) / rect.height * N);
      return r >= 0 && r < N && c >= 0 && c < N ? [r, c] : null;
    }
    function select(p) {
      if (sel) { const t = at(sel[0], sel[1]); if (t) t.el.classList.remove('sel'); }
      sel = p;
      if (p) at(p[0], p[1]).el.classList.add('sel');
    }
    tilesBox.addEventListener('pointerdown', e => {
      if (state !== 'run' || busy) return;
      const p = cellFromEvent(e);
      if (!p) return;
      down = { p, x: e.clientX, y: e.clientY };
      if (sel && Math.abs(sel[0] - p[0]) + Math.abs(sel[1] - p[1]) === 1) { const s = sel; select(null); down = null; trySwap(s, p); return; }
      select(sel && sel[0] === p[0] && sel[1] === p[1] ? null : p);
    });
    window.addEventListener('pointermove', onMove);
    function onMove(e) {
      if (!down || busy) return;
      const dx = e.clientX - down.x, dy = e.clientY - down.y;
      const size = tilesBox.getBoundingClientRect().width / N;
      if (Math.max(Math.abs(dx), Math.abs(dy)) < size * 0.4) return;
      const [r, c] = down.p;
      const to = Math.abs(dx) > Math.abs(dy) ? [r, c + Math.sign(dx)] : [r + Math.sign(dy), c];
      down = null;
      if (!at(to[0], to[1])) return;
      select(null);
      trySwap([r, c], to);
    }
    const onUp = () => { down = null; };
    window.addEventListener('pointerup', onUp);

    // ---------- flow ----------
    function hud() {
      q('.m3-score').textContent = score;
      q('.m3-best').textContent = bests[mode] || 0;
      q('.m3-lim-l').textContent = mode === 'time' ? '时间' : '剩余步数';
      q('.m3-lim').textContent = left;
      q('.m3-lim').parentElement.classList.toggle('low', (mode === 'time' && left <= 10) || (mode === 'moves' && left <= 5));
      root.querySelectorAll('.m3-seg button').forEach(b => b.classList.toggle('on', b.dataset.m === mode));
    }
    function start() {
      clearInterval(timer); clearHint();
      faces = petFaces();
      score = 0; sel = null; busy = false;
      left = mode === 'time' ? MODES.time.time : MODES.moves.moves;
      state = 'run';
      q('.m3-ov').classList.add('hidden');
      fill();
      hud();
      armHint();
      if (mode === 'time') timer = setInterval(() => {
        if (state !== 'run' || !ctx.isActive()) return;
        left--; hud();
        if (left <= 0) { clearInterval(timer); waitEnd(); }
      }, 1000);
    }
    async function waitEnd() { while (busy) await wait(100); end(); }
    function end() {
      if (state === 'over') return;
      state = 'over';
      clearInterval(timer); clearHint();
      const rec = score > (bests[mode] || 0);
      if (rec) { bests[mode] = score; ctx.store.set('best', bests); }
      const coins = Math.max(0, Math.min(15, Math.floor(score / 700)));
      if (coins) ctx.reward(coins, '宠物消消乐结算');
      if (rec && score >= 1000) ctx.say(`消消乐新纪录：${score} 分！`);
      q('.m3-title').textContent = rec ? '新纪录！🎉' : mode === 'time' ? '时间到！' : '步数用完啦';
      q('.m3-sub').innerHTML = `本局得分 <b>${score}</b>${coins ? `<br>获得 ${coins} 小鱼干` : ''}`;
      q('.m3-go').textContent = '再来一局';
      q('.m3-ov').classList.remove('hidden');
      hud();
    }
    function pause() {
      if (state === 'run') { state = 'pause'; q('.m3-title').textContent = '暂停中'; q('.m3-sub').textContent = `当前得分 ${score}`; q('.m3-go').textContent = '继续'; q('.m3-ov').classList.remove('hidden'); board.classList.add('paused'); }
      else if (state === 'pause') { state = 'run'; q('.m3-ov').classList.add('hidden'); board.classList.remove('paused'); armHint(); }
    }
    q('.m3-go').onclick = () => (state === 'pause' ? pause() : start());
    q('.m3-new').onclick = start;
    q('.m3-hintbtn').onclick = () => { if (state === 'run') { clearHint(); showHint(); } };
    root.querySelectorAll('.m3-seg button').forEach(b => b.onclick = () => {
      if (state === 'run' && !confirm('切换模式会结束当前这局，确定吗？')) return;
      mode = b.dataset.m; ctx.store.set('mode', mode);
      clearInterval(timer); state = 'ready';
      left = mode === 'time' ? MODES.time.time : MODES.moves.moves;
      q('.m3-title').textContent = '宠物消消乐'; q('.m3-sub').innerHTML = intro(); q('.m3-go').textContent = '开始';
      q('.m3-ov').classList.remove('hidden');
      hud();
    });
    const intro = () => (mode === 'time' ? '60 秒内尽可能多地消除！' : '只有 30 步，每一步都要想好哦');
    function onKey(e) {
      if (!ctx.isActive() || e.ctrlKey || e.metaKey || e.altKey) return;
      const tg = e.target && e.target.tagName;
      if (tg === 'INPUT' || tg === 'TEXTAREA') return;
      if (e.key === 'p' || e.key === 'P' || e.key === 'Escape') { e.preventDefault(); pause(); }
      else if (e.key === 'Enter' && state !== 'run') { e.preventDefault(); q('.m3-go').click(); }
    }
    window.addEventListener('keydown', onKey);
    const pauseWatch = setInterval(() => { if (state === 'run' && !ctx.isActive()) pause(); }, 500);

    left = mode === 'time' ? MODES.time.time : MODES.moves.moves;
    q('.m3-sub').innerHTML = intro();
    fill();
    hud();
    cleanup = () => {
      clearInterval(timer); clearInterval(pauseWatch); clearTimeout(idleT);
      window.removeEventListener('keydown', onKey); window.removeEventListener('pointermove', onMove); window.removeEventListener('pointerup', onUp);
    };
  }

  Hub.register({
    id: 'match3', title: '宠物消消乐', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="6.5" cy="6.5" r="3"/><circle cx="17.5" cy="6.5" r="3" fill="currentColor"/><circle cx="6.5" cy="17.5" r="3" fill="currentColor"/><circle cx="12" cy="17.5" r="3" fill="currentColor"/><circle cx="17.5" cy="17.5" r="3" fill="currentColor"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
