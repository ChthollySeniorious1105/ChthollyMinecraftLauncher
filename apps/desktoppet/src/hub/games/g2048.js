// 2048 — sliding tile puzzle module for the hub. See ../MODULES.md for the contract.
(function () {
  const BOARD = 400;                  // board pixel size
  const SIZES = [3, 4, 5];
  const GAPS = { 3: 14, 4: 12, 5: 10 };
  const SLIDE_MS = 120;               // must match CSS transition
  const WIN_VALUE = 2048;
  const KEYMAP = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    KeyW: 'up', KeyS: 'down', KeyA: 'left', KeyD: 'right'
  };

  let cleanup = null;

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'g48-root';
    root.innerHTML = `
      <div class="g48-bar">
        <div class="g48-stats">
          <div class="g48-stat g48-score-box"><span class="g48-lbl">得分</span><b class="g48-score">0</b></div>
          <div class="g48-stat"><span class="g48-lbl">最佳</span><b class="g48-best">0</b></div>
        </div>
        <div class="g48-opts">
          <div class="g48-seg" role="group" aria-label="棋盘大小">
            ${SIZES.map(n => `<button type="button" data-size="${n}">${n}×${n}</button>`).join('')}
          </div>
          <button type="button" class="g48-btn g48-undo" title="撤销一步 (Ctrl+Z)">撤销</button>
          <button type="button" class="g48-btn g48-primary g48-new">新游戏</button>
        </div>
      </div>
      <div class="g48-board">
        <div class="g48-cells"></div>
        <div class="g48-tiles"></div>
        <div class="g48-overlay hidden">
          <div class="g48-card">
            <div class="g48-title"></div>
            <div class="g48-sub"></div>
            <div class="g48-ov-btns">
              <button type="button" class="g48-btn g48-ov-a"></button>
              <button type="button" class="g48-btn g48-primary g48-ov-b"></button>
            </div>
          </div>
        </div>
      </div>
      <div class="g48-help">方向键 / WASD 或在棋盘上拖动滑动 · 相同数字相撞合并 · 合成 ${WIN_VALUE} 获胜</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const board = $('.g48-board'), cellsLayer = $('.g48-cells'), tilesLayer = $('.g48-tiles');
    const scoreEl = $('.g48-score'), bestEl = $('.g48-best'), scoreBox = $('.g48-score-box');
    const overlay = $('.g48-overlay'), ovTitle = $('.g48-title'), ovSub = $('.g48-sub');
    const ovA = $('.g48-ov-a'), ovB = $('.g48-ov-b');
    const undoBtn = $('.g48-undo'), newBtn = $('.g48-new');
    const sizeBtns = [...root.querySelectorAll('[data-size]')];

    // ---------- state ----------
    let size = ctx.store.get('size', 4);
    if (!SIZES.includes(size)) size = 4;
    let gap, cell;
    let grid;          // grid[r][c] = tile | null ; tile = { id, v, r, c, anim }
    let score, won, keep, over, prev, startBest;
    let nextId = 1;
    const els = new Map();   // tile id -> element
    let dyingEls = [], dyingTimer = 0;

    const bestKey = () => 'best_' + size;
    const gameKey = () => 'game_' + size;
    const getBest = () => ctx.store.get(bestKey(), 0) || 0;

    const emptyGrid = () => Array.from({ length: size }, () => Array(size).fill(null));
    const values = () => grid.map(row => row.map(t => (t ? t.v : 0)));

    function gridFromValues(vals) {
      const g = emptyGrid();
      for (let r = 0; r < size; r++)
        for (let c = 0; c < size; c++) {
          const v = vals && vals[r] && vals[r][c];
          if (v) g[r][c] = { id: nextId++, v, r, c, anim: '' };
        }
      return g;
    }

    function validVals(v) {
      return Array.isArray(v) && v.length === size && v.every(row => Array.isArray(row) && row.length === size);
    }

    // ---------- geometry ----------
    function layout() {
      gap = GAPS[size];
      cell = (BOARD - gap * (size + 1)) / size;
      board.style.width = board.style.height = BOARD + 'px';
      root.style.setProperty('--g48-radius', Math.round(cell * 0.09 + 3) + 'px');
      cellsLayer.innerHTML = '';
      for (let r = 0; r < size; r++)
        for (let c = 0; c < size; c++) {
          const d = document.createElement('div');
          d.className = 'g48-cell';
          d.style.width = d.style.height = cell + 'px';
          d.style.left = pos(c) + 'px';
          d.style.top = pos(r) + 'px';
          cellsLayer.appendChild(d);
        }
      sizeBtns.forEach(b => b.classList.toggle('active', +b.dataset.size === size));
    }
    const pos = i => gap + i * (cell + gap);

    function fontSize(v) {
      const digits = String(v).length;
      const k = digits <= 2 ? 0.48 : digits === 3 ? 0.4 : digits === 4 ? 0.32 : 0.26;
      return Math.round(cell * k);
    }

    // ---------- rendering ----------
    function makeEl(t) {
      const e = document.createElement('div');
      e.className = 'g48-tile';
      e.style.width = e.style.height = cell + 'px';
      const inner = document.createElement('div');
      inner.className = 'g48-in ' + (t.v <= WIN_VALUE ? 'g48-v' + t.v : 'g48-vbig');
      if (t.anim === 'new') inner.classList.add('g48-new');
      else if (t.anim === 'merge') { inner.classList.add('g48-merge'); e.classList.add('g48-top'); }
      inner.style.fontSize = fontSize(t.v) + 'px';
      inner.textContent = t.v;
      e.appendChild(inner);
      place(e, t);
      return e;
    }

    function place(e, t) {
      e.style.transform = `translate(${pos(t.c)}px, ${pos(t.r)}px)`;
    }

    function flushDying() {
      clearTimeout(dyingTimer);
      dyingTimer = 0;
      dyingEls.forEach(e => e.remove());
      dyingEls = [];
    }

    function render(dying) {
      if (dying && dying.length) {
        for (const t of dying) {
          const e = els.get(t.id);
          if (!e) continue;
          place(e, t);
          e.classList.add('g48-dying');
          els.delete(t.id);
          dyingEls.push(e);
        }
        clearTimeout(dyingTimer);
        dyingTimer = setTimeout(flushDying, SLIDE_MS + 20);
      }
      const live = new Set();
      for (let r = 0; r < size; r++)
        for (let c = 0; c < size; c++) {
          const t = grid[r][c];
          if (!t) continue;
          live.add(t.id);
          let e = els.get(t.id);
          if (!e) {
            e = makeEl(t);
            tilesLayer.appendChild(e);
            els.set(t.id, e);
          } else {
            place(e, t);
          }
          t.anim = '';
        }
      for (const [id, e] of els) if (!live.has(id)) { e.remove(); els.delete(id); }
    }

    function clearTiles() {
      flushDying();
      els.forEach(e => e.remove());
      els.clear();
    }

    function updateHud() {
      scoreEl.textContent = score;
      bestEl.textContent = getBest();
      undoBtn.disabled = !prev;
    }

    function floatPlus(n) {
      const s = document.createElement('span');
      s.className = 'g48-plus';
      s.textContent = '+' + n;
      scoreBox.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    let ovMode = null;
    function showOverlay(mode) {
      ovMode = mode;
      if (!mode) { overlay.classList.add('hidden'); return; }
      overlay.classList.remove('hidden');
      overlay.classList.toggle('g48-win', mode === 'win');
      if (mode === 'win') {
        ovTitle.textContent = '你赢了！';
        ovSub.textContent = `合成了 ${WIN_VALUE} · 得分 ${score}`;
        ovA.textContent = '新游戏';
        ovB.textContent = '继续';
        ovA.style.display = '';
      } else {
        const nb = score > startBest && score > 0;
        ovTitle.textContent = '游戏结束';
        ovSub.textContent = `得分 ${score}` + (nb ? ' · 新纪录！' : ` · 最佳 ${getBest()}`);
        ovA.textContent = '撤销';
        ovA.style.display = prev ? '' : 'none';
        ovB.textContent = '再来一局';
      }
      // restart the fade-in animation
      overlay.style.animation = 'none';
      void overlay.offsetWidth;
      overlay.style.animation = '';
    }

    // ---------- persistence ----------
    function save() {
      ctx.store.set(gameKey(), { vals: values(), score, won, keep, over, prev, startBest });
    }

    function load() {
      const s = ctx.store.get(gameKey(), null);
      if (s && validVals(s.vals) && s.vals.some(row => row.some(v => v))) {
        grid = gridFromValues(s.vals);
        score = s.score | 0;
        won = !!s.won;
        keep = !!s.keep;
        over = !!s.over;
        prev = s.prev && validVals(s.prev.vals) ? s.prev : null;
        startBest = typeof s.startBest === 'number' ? s.startBest : getBest();
        clearTiles();
        render();
        updateHud();
        if (over) showOverlay('over');
        else if (won && !keep) showOverlay('win');
        else showOverlay(null);
      } else {
        newGame();
      }
    }

    // ---------- game logic ----------
    function emptyCells() {
      const out = [];
      for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (!grid[r][c]) out.push([r, c]);
      return out;
    }

    function spawn() {
      const free = emptyCells();
      if (!free.length) return;
      const [r, c] = free[(Math.random() * free.length) | 0];
      grid[r][c] = { id: nextId++, v: Math.random() < 0.9 ? 2 : 4, r, c, anim: 'new' };
    }

    function newGame() {
      clearTiles();
      grid = emptyGrid();
      score = 0; won = false; keep = false; over = false; prev = null;
      startBest = getBest();
      spawn(); spawn();
      render();
      updateHud();
      showOverlay(null);
      save();
    }

    function lineCells(dir, i) {
      const out = [];
      for (let k = 0; k < size; k++) {
        if (dir === 'left') out.push([i, k]);
        else if (dir === 'right') out.push([i, size - 1 - k]);
        else if (dir === 'up') out.push([k, i]);
        else out.push([size - 1 - k, i]);
      }
      return out;
    }

    function canMove() {
      for (let r = 0; r < size; r++)
        for (let c = 0; c < size; c++) {
          const t = grid[r][c];
          if (!t) return true;
          if (c + 1 < size && grid[r][c + 1] && grid[r][c + 1].v === t.v) return true;
          if (r + 1 < size && grid[r + 1][c] && grid[r + 1][c].v === t.v) return true;
        }
      return false;
    }

    function move(dir) {
      if (over || ovMode) return;
      flushDying();
      const snapshot = { vals: values(), score };
      const ng = emptyGrid();
      const dying = [];
      let moved = false, gained = 0, hitWin = false;

      for (let i = 0; i < size; i++) {
        const line = lineCells(dir, i);
        let t = 0, last = null, lastMerged = false;
        for (const [r, c] of line) {
          const tile = grid[r][c];
          if (!tile) continue;
          if (last && !lastMerged && last.v === tile.v) {
            const [tr, tc] = line[t - 1];
            tile.r = tr; tile.c = tc;
            const m = { id: nextId++, v: tile.v * 2, r: tr, c: tc, anim: 'merge' };
            dying.push(last, tile);
            ng[tr][tc] = m;
            gained += m.v;
            if (m.v === WIN_VALUE) hitWin = true;
            last = m; lastMerged = true;
            moved = true;
          } else {
            const [tr, tc] = line[t];
            if (tr !== r || tc !== c) moved = true;
            tile.r = tr; tile.c = tc;
            ng[tr][tc] = tile;
            last = tile; lastMerged = false;
            t++;
          }
        }
      }
      if (!moved) return;

      prev = snapshot;
      grid = ng;
      score += gained;
      spawn();
      render(dying);

      if (gained) {
        floatPlus(gained);
        if (score > getBest()) ctx.store.set(bestKey(), score);
      }

      if (hitWin && !won) {
        won = true;
        ctx.say('合成 2048 啦！太厉害了！');
        if (ctx.reward) ctx.reward(20, '合成 2048');
        showOverlay('win');
      } else if (!canMove()) {
        over = true;
        if (ctx.reward && score >= 500) ctx.reward(Math.min(15, Math.floor(score / 500)), '2048 结算');
        if (score > startBest && score > 0) ctx.say(`2048 新纪录！${score} 分，好棒！`);
        showOverlay('over');
      }
      updateHud();
      save();
    }

    function undo() {
      if (!prev) { ctx.toast && ctx.toast('没有可撤销的步骤'); return; }
      clearTiles();
      grid = gridFromValues(prev.vals);
      score = prev.score;
      prev = null;
      over = false;
      if (ovMode) showOverlay(null);
      render();
      updateHud();
      save();
    }

    function setSize(n) {
      if (n === size) return;
      save();
      size = n;
      ctx.store.set('size', size);
      clearTiles();
      layout();
      load();
    }

    // ---------- input ----------
    function onKey(e) {
      if (!ctx.isActive()) return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
      if ((e.ctrlKey || e.metaKey) && e.code === 'KeyZ') {
        e.preventDefault();
        undo();
        return;
      }
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      const d = KEYMAP[e.code];
      if (d) {
        e.preventDefault();
        move(d);
        return;
      }
      if (e.code === 'Enter' && ovMode) {
        e.preventDefault();
        ovB.click();
      }
    }

    let drag = null;
    function onPointerDown(e) {
      if (e.button !== 0 || ovMode) return;
      drag = { x: e.clientX, y: e.clientY, id: e.pointerId };
      try { board.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
    }
    function onPointerUp(e) {
      if (!drag || e.pointerId !== drag.id) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      drag = null;
      if (Math.max(Math.abs(dx), Math.abs(dy)) < 24) return;
      if (Math.abs(dx) > Math.abs(dy)) move(dx > 0 ? 'right' : 'left');
      else move(dy > 0 ? 'down' : 'up');
    }
    function onPointerCancel() { drag = null; }

    function onSizeClick(e) { const b = e.currentTarget; b.blur(); setSize(+b.dataset.size); }
    function onUndo() { undoBtn.blur(); undo(); }
    function onNew() { newBtn.blur(); newGame(); }
    function onOvA() {
      ovA.blur();
      if (ovMode === 'win') newGame();
      else undo();
    }
    function onOvB() {
      ovB.blur();
      if (ovMode === 'win') {
        keep = true;
        showOverlay(null);
        if (!canMove()) { over = true; showOverlay('over'); }
        save();
      } else {
        newGame();
      }
    }

    sizeBtns.forEach(b => b.addEventListener('click', onSizeClick));
    undoBtn.addEventListener('click', onUndo);
    newBtn.addEventListener('click', onNew);
    ovA.addEventListener('click', onOvA);
    ovB.addEventListener('click', onOvB);
    board.addEventListener('pointerdown', onPointerDown);
    board.addEventListener('pointerup', onPointerUp);
    board.addEventListener('pointercancel', onPointerCancel);
    window.addEventListener('keydown', onKey);

    layout();
    load();

    cleanup = () => {
      window.removeEventListener('keydown', onKey);
      clearTimeout(dyingTimer);
      sizeBtns.forEach(b => b.removeEventListener('click', onSizeClick));
      undoBtn.removeEventListener('click', onUndo);
      newBtn.removeEventListener('click', onNew);
      ovA.removeEventListener('click', onOvA);
      ovB.removeEventListener('click', onOvB);
      board.removeEventListener('pointerdown', onPointerDown);
      board.removeEventListener('pointerup', onPointerUp);
      board.removeEventListener('pointercancel', onPointerCancel);
      root.remove();
    };
  }

  Hub.register({
    id: 'g2048',
    title: '2048',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><rect x="6" y="6" width="5" height="5" rx="1" fill="currentColor" stroke="none"/><rect x="13" y="6" width="5" height="5" rx="1" fill="currentColor" stroke="none" opacity=".5"/><rect x="6" y="13" width="5" height="5" rx="1" fill="currentColor" stroke="none" opacity=".5"/><rect x="13" y="13" width="5" height="5" rx="1" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
