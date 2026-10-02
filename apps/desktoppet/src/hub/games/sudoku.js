// 数独 — Sudoku module for the hub. See ../MODULES.md for the contract.
(function () {
  const DIFFS = [
    { key: 'easy',   name: '简单', givens: 40, reward: 5 },
    { key: 'medium', name: '中等', givens: 32, reward: 8 },
    { key: 'hard',   name: '困难', givens: 27, reward: 12 },
    { key: 'expert', name: '专家', givens: 23, reward: 18 }
  ];
  const GEN_BUDGET_MS = 250;
  const HISTORY_MAX = 150;

  // ---------- geometry helpers ----------
  const ROW = i => (i / 9) | 0;
  const COL = i => i % 9;
  const BOX = i => ((ROW(i) / 3) | 0) * 3 + ((COL(i) / 3) | 0);
  const PEERS = [];
  for (let i = 0; i < 81; i++) {
    const p = [];
    for (let j = 0; j < 81; j++) {
      if (j !== i && (ROW(j) === ROW(i) || COL(j) === COL(i) || BOX(j) === BOX(i))) p.push(j);
    }
    PEERS.push(p);
  }
  const POP = new Uint8Array(512);
  for (let m = 1; m < 512; m++) POP[m] = POP[m >> 1] + (m & 1);

  function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      const t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  // ---------- solver (bitmask backtracking with MRV) ----------
  // Returns number of solutions found (stops at `limit`). If `out` is given and
  // random=true, fills `out` with the first (randomised) solution.
  function solve(grid, limit, random, out) {
    const cells = grid.slice();
    const rows = new Int32Array(9), cols = new Int32Array(9), boxes = new Int32Array(9);
    for (let i = 0; i < 81; i++) {
      const v = cells[i];
      if (!v) continue;
      const b = 1 << (v - 1), r = ROW(i), c = COL(i), x = BOX(i);
      if ((rows[r] | cols[c] | boxes[x]) & b) return 0;
      rows[r] |= b; cols[c] |= b; boxes[x] |= b;
    }
    let count = 0;
    function rec() {
      let best = -1, bestMask = 0, bestCnt = 10;
      for (let i = 0; i < 81; i++) {
        if (cells[i]) continue;
        const m = ~(rows[ROW(i)] | cols[COL(i)] | boxes[BOX(i)]) & 511;
        const n = POP[m];
        if (n === 0) return;
        if (n < bestCnt) { best = i; bestMask = m; bestCnt = n; if (n === 1) break; }
      }
      if (best < 0) {
        count++;
        if (out && count === 1) for (let i = 0; i < 81; i++) out[i] = cells[i];
        return;
      }
      const r = ROW(best), c = COL(best), x = BOX(best);
      const digits = [];
      for (let d = 0; d < 9; d++) if (bestMask & (1 << d)) digits.push(d);
      if (random) shuffle(digits);
      for (const d of digits) {
        const b = 1 << d;
        cells[best] = d + 1;
        rows[r] |= b; cols[c] |= b; boxes[x] |= b;
        rec();
        rows[r] &= ~b; cols[c] &= ~b; boxes[x] &= ~b;
        cells[best] = 0;
        if (count >= limit) return;
      }
    }
    rec();
    return count;
  }

  // Generate a puzzle with a unique solution. Tries to reach `target` givens within a
  // time budget; keeps the best (fewest givens) attempt if the target is not reached.
  function generate(target) {
    const deadline = performance.now() + GEN_BUDGET_MS;
    let best = null;
    do {
      const solution = new Array(81).fill(0);
      solve(new Array(81).fill(0), 1, true, solution);
      const g = solution.slice();
      let givens = 81;
      for (const i of shuffle([...Array(81).keys()])) {
        if (givens <= target) break;
        if (best && performance.now() > deadline) break;
        const t = g[i];
        g[i] = 0;
        if (solve(g, 2, false) !== 1) g[i] = t;
        else givens--;
      }
      if (!best || givens < best.givens) best = { puzzle: g, solution, givens };
      if (best.givens <= target) break;
    } while (performance.now() < deadline);
    return best;
  }

  const fmt = ms => {
    const s = Math.floor(ms / 1000);
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    const p = n => String(n).padStart(2, '0');
    return h ? `${h}:${p(m)}:${p(ss)}` : `${p(m)}:${p(ss)}`;
  };

  let cleanup = null;

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'sd-root';
    root.innerHTML = `
      <div class="sd-top">
        <div class="sd-seg" role="group" aria-label="难度">
          ${DIFFS.map(d => `<button type="button" data-diff="${d.key}">${d.name}</button>`).join('')}
        </div>
        <button type="button" class="sd-btn sd-check" title="开启后填错的数字标红并计入错误数">纠错</button>
        <button type="button" class="sd-btn sd-primary sd-new">新游戏</button>
      </div>
      <div class="sd-main">
        <div class="sd-board-wrap">
          <div class="sd-board"></div>
          <div class="sd-overlay hidden">
            <div class="sd-card">
              <div class="sd-ov-title"></div>
              <div class="sd-ov-sub"></div>
              <button type="button" class="sd-btn sd-primary sd-ov-btn"></button>
            </div>
          </div>
        </div>
        <div class="sd-side">
          <div class="sd-stats">
            <div class="sd-stat"><span>时间</span><b class="sd-time">00:00</b></div>
            <div class="sd-stat sd-mis-box"><span>错误</span><b class="sd-mis">0</b></div>
            <div class="sd-stat"><span>提示</span><b class="sd-hints">0</b></div>
            <div class="sd-stat"><span>最佳</span><b class="sd-best">--:--</b></div>
          </div>
          <div class="sd-pad">
            ${[1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => `<button type="button" class="sd-num" data-n="${n}"><b>${n}</b><small></small></button>`).join('')}
          </div>
          <div class="sd-acts">
            <button type="button" class="sd-act sd-undo" title="撤销 (Ctrl+Z)">
              <svg viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/></svg><span>撤销</span></button>
            <button type="button" class="sd-act sd-erase" title="擦除 (Backspace / Delete)">
              <svg viewBox="0 0 24 24"><path d="m7 21-4.3-4.3a1 1 0 0 1 0-1.4l10-10a1 1 0 0 1 1.4 0l5.6 5.6a1 1 0 0 1 0 1.4L13 21"/><path d="M22 21H7"/><path d="m5 11 9 9"/></svg><span>擦除</span></button>
            <button type="button" class="sd-act sd-note" title="笔记模式 (N)">
              <svg viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg><span>笔记</span><i class="sd-note-flag">关</i></button>
            <button type="button" class="sd-act sd-hint" title="提示 (H)">
              <svg viewBox="0 0 24 24"><path d="M9 18h6"/><path d="M10 22h4"/><path d="M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z"/></svg><span>提示</span></button>
          </div>
          <button type="button" class="sd-btn sd-pause">暂停</button>
        </div>
      </div>
      <div class="sd-help">方向键移动 · 1-9 填数 · Backspace 擦除 · N 切换笔记 · Shift+数字 快速笔记 · Ctrl+Z 撤销</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const boardEl = $('.sd-board');
    const overlay = $('.sd-overlay'), ovTitle = $('.sd-ov-title'), ovSub = $('.sd-ov-sub'), ovBtn = $('.sd-ov-btn');
    const timeEl = $('.sd-time'), misEl = $('.sd-mis'), misBox = $('.sd-mis-box'), hintsEl = $('.sd-hints'), bestEl = $('.sd-best');
    const checkBtn = $('.sd-check'), newBtn = $('.sd-new'), pauseBtn = $('.sd-pause');
    const undoBtn = $('.sd-undo'), eraseBtn = $('.sd-erase'), noteBtn = $('.sd-note'), hintBtn = $('.sd-hint');
    const noteFlag = $('.sd-note-flag');
    const diffBtns = [...root.querySelectorAll('[data-diff]')];
    const numBtns = [...root.querySelectorAll('.sd-num')];

    const cellEls = [];
    for (let i = 0; i < 81; i++) {
      const d = document.createElement('div');
      const r = ROW(i), c = COL(i);
      d.className = 'sd-cell' +
        (c === 2 || c === 5 ? ' sd-bR' : '') + (c === 8 ? ' sd-lc' : '') +
        (r === 2 || r === 5 ? ' sd-bB' : '') + (r === 8 ? ' sd-lr' : '');
      d.dataset.i = i;
      boardEl.appendChild(d);
      cellEls.push(d);
    }

    // ---------- state ----------
    let diff = ctx.store.get('diff', 'medium');
    if (!DIFFS.some(d => d.key === diff)) diff = 'medium';
    let checkMistakes = ctx.store.get('checkMistakes', true) !== false;
    let game = null;      // { puzzle, solution, values, notes, mistakes, hints, elapsed, done, rewarded, history }
    let sel = -1;
    let noteMode = false;
    let paused = false;
    let generating = false;
    let genTimer = 0;
    let lastTick = Date.now(), lastSave = 0;

    const diffInfo = () => DIFFS.find(d => d.key === diff);
    const gameKey = () => 'game_' + diff;
    const bests = () => ctx.store.get('best', {}) || {};

    function valid81(a) {
      return Array.isArray(a) && a.length === 81 && a.every(v => Number.isInteger(v) && v >= 0 && v <= 9);
    }

    // ---------- persistence ----------
    function save() {
      if (!game) return;
      ctx.store.set(gameKey(), {
        puzzle: game.puzzle, solution: game.solution, values: game.values, notes: game.notes,
        mistakes: game.mistakes, hints: game.hints, elapsed: Math.floor(game.elapsed),
        done: game.done, rewarded: game.rewarded, history: game.history.slice(-HISTORY_MAX)
      });
      lastSave = Date.now();
    }

    function load() {
      const s = ctx.store.get(gameKey(), null);
      if (s && valid81(s.puzzle) && valid81(s.solution) && valid81(s.values) &&
          Array.isArray(s.notes) && s.notes.length === 81 && !s.done) {
        game = {
          puzzle: s.puzzle, solution: s.solution, values: s.values,
          notes: s.notes.map(n => (n | 0) & 511),
          mistakes: s.mistakes | 0, hints: s.hints | 0, elapsed: +s.elapsed || 0,
          done: false, rewarded: !!s.rewarded,
          history: Array.isArray(s.history) ? s.history : []
        };
        sel = -1; paused = false;
        showOverlay(null);
        renderAll();
      } else {
        newGame();
      }
    }

    // ---------- game lifecycle ----------
    function newGame() {
      if (generating) return;
      generating = true;
      game = null;
      sel = -1; paused = false;
      showOverlay('gen');
      renderAll();
      clearTimeout(genTimer);
      // let the "生成中" overlay paint before the (short) synchronous generation
      genTimer = setTimeout(() => {
        genTimer = 0;
        const res = generate(diffInfo().givens);
        generating = false;
        game = {
          puzzle: res.puzzle, solution: res.solution, values: res.puzzle.slice(),
          notes: new Array(81).fill(0), mistakes: 0, hints: 0, elapsed: 0,
          done: false, rewarded: false, history: []
        };
        lastTick = Date.now();
        showOverlay(null);
        renderAll();
        save();
      }, 30);
    }

    function setDiff(k) {
      if (k === diff || generating) return;
      save();
      diff = k;
      ctx.store.set('diff', diff);
      load();
    }

    // ---------- rendering ----------
    function conflicts() {
      const bad = new Uint8Array(81);
      const v = game.values;
      for (let i = 0; i < 81; i++) {
        if (!v[i]) continue;
        for (const j of PEERS[i]) if (v[j] === v[i]) { bad[i] = 1; break; }
      }
      return bad;
    }

    function renderBoard() {
      if (!game) {
        cellEls.forEach(e => { e.className = e.className.replace(/ sd-(given|sel|peer|same|bad|user)/g, ''); e.innerHTML = ''; });
        return;
      }
      const v = game.values;
      const bad = conflicts();
      const sv = sel >= 0 ? v[sel] : 0;
      for (let i = 0; i < 81; i++) {
        const e = cellEls[i];
        const cls = ['sd-cell'];
        const r = ROW(i), c = COL(i);
        if (c === 2 || c === 5) cls.push('sd-bR');
        if (c === 8) cls.push('sd-lc');
        if (r === 2 || r === 5) cls.push('sd-bB');
        if (r === 8) cls.push('sd-lr');
        const given = !!game.puzzle[i];
        if (given) cls.push('sd-given'); else if (v[i]) cls.push('sd-user');
        if (sel >= 0) {
          if (i === sel) cls.push('sd-sel');
          else if (ROW(i) === ROW(sel) || COL(i) === COL(sel) || BOX(i) === BOX(sel)) cls.push('sd-peer');
          if (sv && v[i] === sv && i !== sel) cls.push('sd-same');
        }
        if (v[i] && !given && (bad[i] || (checkMistakes && v[i] !== game.solution[i]))) cls.push('sd-bad');
        else if (v[i] && given && bad[i]) cls.push('sd-bad');
        e.className = cls.join(' ');
        if (v[i]) {
          e.textContent = v[i];
        } else if (game.notes[i]) {
          let h = '<div class="sd-notes">';
          for (let d = 1; d <= 9; d++) {
            const on = game.notes[i] & (1 << (d - 1));
            h += `<span${on && d === sv ? ' class="sd-nh"' : ''}>${on ? d : ''}</span>`;
          }
          e.innerHTML = h + '</div>';
        } else {
          e.textContent = '';
        }
      }
    }

    function renderSide() {
      const counts = new Array(10).fill(0);
      if (game) game.values.forEach(x => counts[x]++);
      numBtns.forEach(b => {
        const n = +b.dataset.n;
        const left = 9 - counts[n];
        b.querySelector('small').textContent = game ? (left > 0 ? left : '') : '';
        b.classList.toggle('sd-full', !!game && left <= 0);
        b.classList.toggle('sd-cur', !!game && sel >= 0 && game.values[sel] === n);
      });
      diffBtns.forEach(b => b.classList.toggle('active', b.dataset.diff === diff));
      checkBtn.classList.toggle('active', checkMistakes);
      noteBtn.classList.toggle('active', noteMode);
      noteFlag.textContent = noteMode ? '开' : '关';
      misBox.style.display = checkMistakes ? '' : 'none';
      misEl.textContent = game ? game.mistakes : 0;
      hintsEl.textContent = game ? game.hints : 0;
      const b = bests()[diff];
      bestEl.textContent = b ? fmt(b) : '--:--';
      undoBtn.disabled = !game || !game.history.length || game.done;
      pauseBtn.textContent = paused ? '继续' : '暂停';
      pauseBtn.disabled = !game || game.done;
      root.classList.toggle('sd-notemode', noteMode);
      renderTime();
    }

    function renderTime() {
      timeEl.textContent = fmt(game ? game.elapsed : 0);
    }

    function renderAll() { renderBoard(); renderSide(); }

    let ovMode = null;
    function showOverlay(mode) {
      ovMode = mode;
      if (!mode) { overlay.classList.add('hidden'); boardEl.classList.remove('sd-blur'); return; }
      overlay.classList.remove('hidden');
      overlay.classList.toggle('sd-win', mode === 'win');
      boardEl.classList.toggle('sd-blur', mode === 'pause' || mode === 'gen');
      ovBtn.style.display = mode === 'gen' ? 'none' : '';
      if (mode === 'gen') {
        ovTitle.textContent = '生成题目中…';
        ovSub.textContent = diffInfo().name + '难度';
      } else if (mode === 'pause') {
        ovTitle.textContent = '已暂停';
        ovSub.textContent = '用时 ' + fmt(game.elapsed);
        ovBtn.textContent = '继续';
      } else if (mode === 'win') {
        const b = bests()[diff];
        const rec = game.newRecord;
        ovTitle.textContent = '数独完成！';
        ovSub.innerHTML = `${diffInfo().name} · 用时 <b>${fmt(game.elapsed)}</b>` +
          (rec ? ' · 新纪录！' : (b ? ` · 最佳 ${fmt(b)}` : '')) +
          `<br>错误 ${game.mistakes} · 提示 ${game.hints}`;
        ovBtn.textContent = '再来一局';
      }
      overlay.style.animation = 'none';
      void overlay.offsetWidth;
      overlay.style.animation = '';
    }

    // ---------- actions ----------
    const playable = () => game && !game.done && !generating && !paused;

    // Apply a mutation, recording previous states of touched cells for undo.
    function mutate(fn) {
      const changes = [];
      const seen = new Set();
      const touch = i => {
        if (seen.has(i)) return;
        seen.add(i);
        changes.push([i, game.values[i], game.notes[i]]);
      };
      fn(touch);
      const real = changes.filter(([i, v, n]) => game.values[i] !== v || game.notes[i] !== n);
      if (real.length) {
        game.history.push(real);
        if (game.history.length > HISTORY_MAX) game.history.shift();
      }
      return real.length > 0;
    }

    function placeValue(i, n, isHint) {
      let wrong = false;
      const changed = mutate(touch => {
        touch(i);
        game.values[i] = n;
        game.notes[i] = 0;
        const bit = 1 << (n - 1);
        for (const j of PEERS[i]) {
          if (!game.values[j] && (game.notes[j] & bit)) { touch(j); game.notes[j] &= ~bit; }
        }
      });
      if (changed && !isHint && n !== game.solution[i]) wrong = true;
      if (wrong && checkMistakes) {
        game.mistakes++;
        misBox.classList.remove('sd-shake');
        void misBox.offsetWidth;
        misBox.classList.add('sd-shake');
      }
      return changed;
    }

    function input(n, forceNote) {
      if (!playable()) return;
      if (sel < 0) { ctx.toast && ctx.toast('先选择一个格子'); return; }
      if (game.puzzle[sel]) return;
      const note = noteMode !== !!forceNote;
      if (note) {
        if (game.values[sel]) return;
        mutate(touch => { touch(sel); game.notes[sel] ^= 1 << (n - 1); });
      } else if (game.values[sel] === n) {
        mutate(touch => { touch(sel); game.values[sel] = 0; });
      } else {
        placeValue(sel, n, false);
      }
      after();
    }

    function erase() {
      if (!playable() || sel < 0 || game.puzzle[sel]) return;
      mutate(touch => { touch(sel); game.values[sel] = 0; game.notes[sel] = 0; });
      after();
    }

    function undo() {
      if (!playable()) return;
      const last = game.history.pop();
      if (!last) { ctx.toast && ctx.toast('没有可撤销的步骤'); return; }
      for (let k = last.length - 1; k >= 0; k--) {
        const [i, v, n] = last[k];
        game.values[i] = v; game.notes[i] = n;
      }
      sel = last[0][0];
      after();
    }

    function hint() {
      if (!playable()) return;
      const need = i => !game.puzzle[i] && game.values[i] !== game.solution[i];
      let i = sel >= 0 && need(sel) ? sel : -1;
      if (i < 0) {
        const cand = [];
        for (let k = 0; k < 81; k++) if (need(k)) cand.push(k);
        if (!cand.length) return;
        i = cand[(Math.random() * cand.length) | 0];
      }
      placeValue(i, game.solution[i], true);
      game.hints++;
      sel = i;
      const e = cellEls[i];
      after();
      e.classList.add('sd-hinted');
      setTimeout(() => e.classList.remove('sd-hinted'), 700);
    }

    function after() {
      renderAll();
      checkWin();
      save();
    }

    function checkWin() {
      if (game.done) return;
      for (let i = 0; i < 81; i++) if (game.values[i] !== game.solution[i]) return;
      game.done = true;
      const b = bests();
      game.newRecord = !b[diff] || game.elapsed < b[diff];
      if (game.newRecord) { b[diff] = Math.floor(game.elapsed); ctx.store.set('best', b); }
      ctx.say('数独完成！用时 ' + fmt(game.elapsed));
      if (!game.rewarded) {
        game.rewarded = true;
        ctx.reward(diffInfo().reward, '数独通关');
      }
      sel = -1;
      renderAll();
      root.classList.add('sd-solved');
      setTimeout(() => root.classList.remove('sd-solved'), 1200);
      showOverlay('win');
    }

    function togglePause() {
      if (!game || game.done || generating) return;
      paused = !paused;
      showOverlay(paused ? 'pause' : null);
      lastTick = Date.now();
      renderSide();
    }

    function toggleNote() { noteMode = !noteMode; renderSide(); }

    function moveSel(dr, dc) {
      if (!game || game.done) return;
      if (sel < 0) { sel = 40; renderAll(); return; }
      const r = (ROW(sel) + dr + 9) % 9, c = (COL(sel) + dc + 9) % 9;
      sel = r * 9 + c;
      renderAll();
    }

    // ---------- timer ----------
    const tickTimer = setInterval(() => {
      const now = Date.now();
      const dt = Math.min(now - lastTick, 1000);
      lastTick = now;
      if (!game || game.done || generating || paused || !ctx.isActive()) return;
      game.elapsed += dt;
      renderTime();
      if (now - lastSave > 5000) save();
    }, 250);

    // ---------- input ----------
    function onKey(e) {
      if (!ctx.isActive()) return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
      if ((e.ctrlKey || e.metaKey) && e.code === 'KeyZ') { e.preventDefault(); undo(); return; }
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      if (ovMode === 'win' && e.code === 'Enter') { e.preventDefault(); newGame(); return; }
      if (ovMode === 'pause') {
        if (e.code === 'Enter' || e.code === 'Space' || e.code === 'KeyP') { e.preventDefault(); togglePause(); }
        return;
      }
      const m = /^(?:Digit|Numpad)([0-9])$/.exec(e.code);
      if (m) {
        e.preventDefault();
        const n = +m[1];
        if (n === 0) erase(); else input(n, e.shiftKey);
        return;
      }
      switch (e.code) {
        case 'ArrowUp': e.preventDefault(); moveSel(-1, 0); break;
        case 'ArrowDown': e.preventDefault(); moveSel(1, 0); break;
        case 'ArrowLeft': e.preventDefault(); moveSel(0, -1); break;
        case 'ArrowRight': e.preventDefault(); moveSel(0, 1); break;
        case 'Backspace': case 'Delete': e.preventDefault(); erase(); break;
        case 'KeyN': e.preventDefault(); toggleNote(); break;
        case 'KeyH': e.preventDefault(); hint(); break;
        case 'KeyP': e.preventDefault(); togglePause(); break;
        case 'Escape': if (sel >= 0) { sel = -1; renderAll(); } break;
      }
    }

    function onBoardDown(e) {
      const c = e.target.closest('.sd-cell');
      if (!c || !game || game.done || paused) return;
      sel = +c.dataset.i;
      renderAll();
    }
    function onPad(e) { const b = e.currentTarget; b.blur(); input(+b.dataset.n, false); }
    function onDiff(e) { const b = e.currentTarget; b.blur(); setDiff(b.dataset.diff); }
    function onCheck() {
      checkBtn.blur();
      checkMistakes = !checkMistakes;
      ctx.store.set('checkMistakes', checkMistakes);
      ctx.toast && ctx.toast(checkMistakes ? '纠错已开启：填错会标红并计数' : '纠错已关闭：只标出冲突');
      if (game) renderAll();
    }
    function onNew() { newBtn.blur(); newGame(); }
    function onPause() { pauseBtn.blur(); togglePause(); }
    function onUndo() { undoBtn.blur(); undo(); }
    function onErase() { eraseBtn.blur(); erase(); }
    function onNote() { noteBtn.blur(); toggleNote(); }
    function onHint() { hintBtn.blur(); hint(); }
    function onOv() {
      ovBtn.blur();
      if (ovMode === 'pause') togglePause();
      else if (ovMode === 'win') newGame();
    }

    const binds = [
      [boardEl, 'pointerdown', onBoardDown], [checkBtn, 'click', onCheck], [newBtn, 'click', onNew],
      [pauseBtn, 'click', onPause], [undoBtn, 'click', onUndo], [eraseBtn, 'click', onErase],
      [noteBtn, 'click', onNote], [hintBtn, 'click', onHint], [ovBtn, 'click', onOv],
      ...numBtns.map(b => [b, 'click', onPad]), ...diffBtns.map(b => [b, 'click', onDiff]),
      [window, 'keydown', onKey]
    ];
    binds.forEach(([t, ev, fn]) => t.addEventListener(ev, fn));

    renderSide();
    load();

    cleanup = () => {
      if (game && !generating) save();
      clearInterval(tickTimer);
      clearTimeout(genTimer);
      binds.forEach(([t, ev, fn]) => t.removeEventListener(ev, fn));
      root.remove();
    };
  }

  Hub.register({
    id: 'sudoku',
    title: '数独',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18" stroke-width="1.2" opacity=".6"/><path d="M5.2 5.5h1.6v2.2M16.6 16.3a1.2 1.2 0 1 1 1.8 1l-1.8 1.4h2.2" stroke-width="1.3" stroke-linecap="round"/><circle cx="12" cy="12" r="1.3" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
