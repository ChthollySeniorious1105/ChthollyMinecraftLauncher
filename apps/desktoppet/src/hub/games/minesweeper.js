// 扫雷 — classic Windows-style Minesweeper module for the hub. See ../MODULES.md for the contract.
(function () {
  const PRESETS = {
    beginner: { label: '初级', rows: 9, cols: 9, mines: 10 },
    intermediate: { label: '中级', rows: 16, cols: 16, mines: 40 },
    expert: { label: '高级', rows: 16, cols: 30, mines: 99 }
  };
  const LIMITS = { rowsMin: 9, rowsMax: 24, colsMin: 9, colsMax: 30, minesMin: 10 };

  // ---------- SVG assets ----------
  const MINE_BODY =
    '<g stroke="#000" stroke-width="1.3" stroke-linecap="square">' +
    '<line x1="8" y1="1.8" x2="8" y2="14.2"/><line x1="1.8" y1="8" x2="14.2" y2="8"/>' +
    '<line x1="3.8" y1="3.8" x2="12.2" y2="12.2"/><line x1="12.2" y1="3.8" x2="3.8" y2="12.2"/></g>' +
    '<circle cx="8" cy="8" r="4.6" fill="#000"/><rect x="5.6" y="5.6" width="2" height="2" fill="#fff"/>';
  const SVG_MINE = '<svg viewBox="0 0 16 16" class="ms-ico">' + MINE_BODY + '</svg>';
  const SVG_MINE_X = '<svg viewBox="0 0 16 16" class="ms-ico">' + MINE_BODY +
    '<g stroke="#f00" stroke-width="1.6"><line x1="1.5" y1="1.5" x2="14.5" y2="14.5"/><line x1="14.5" y1="1.5" x2="1.5" y2="14.5"/></g></svg>';
  const SVG_FLAG = '<svg viewBox="0 0 16 16" class="ms-ico">' +
    '<polygon points="9,2 9,8.6 3.2,5.3" fill="#f00"/>' +
    '<rect x="8.4" y="2" width="1.6" height="10" fill="#000"/>' +
    '<rect x="6" y="11" width="6" height="1.4" fill="#000"/><rect x="3.8" y="12.3" width="10.4" height="1.9" fill="#000"/></svg>';

  const FACE_BASE = '<circle cx="12" cy="12" r="10.4" fill="#ff0" stroke="#000" stroke-width="1.3"/>';
  const FACES = {
    normal: FACE_BASE +
      '<circle cx="8.6" cy="9.6" r="1.35" fill="#000"/><circle cx="15.4" cy="9.6" r="1.35" fill="#000"/>' +
      '<path d="M7.2 14.3 Q12 19.2 16.8 14.3" fill="none" stroke="#000" stroke-width="1.4" stroke-linecap="round"/>',
    oh: FACE_BASE +
      '<circle cx="8.6" cy="9.3" r="1.35" fill="#000"/><circle cx="15.4" cy="9.3" r="1.35" fill="#000"/>' +
      '<circle cx="12" cy="15.6" r="2.4" fill="none" stroke="#000" stroke-width="1.4"/>',
    win: FACE_BASE +
      '<path d="M3.2 8.8 H20.8" stroke="#000" stroke-width="1.2"/>' +
      '<path d="M5.4 8.4 H10.8 V10.2 Q8.4 13.4 5.4 10.2 Z" fill="#000"/>' +
      '<path d="M13.2 8.4 H18.6 V10.2 Q15.6 13.4 13.2 10.2 Z" fill="#000"/>' +
      '<path d="M7.2 15 Q12 19.2 16.8 15" fill="none" stroke="#000" stroke-width="1.4" stroke-linecap="round"/>',
    lose: FACE_BASE +
      '<g stroke="#000" stroke-width="1.3" stroke-linecap="round">' +
      '<line x1="7.1" y1="8.1" x2="10.1" y2="11.1"/><line x1="10.1" y1="8.1" x2="7.1" y2="11.1"/>' +
      '<line x1="13.9" y1="8.1" x2="16.9" y2="11.1"/><line x1="16.9" y1="8.1" x2="13.9" y2="11.1"/></g>' +
      '<path d="M7.4 17.6 Q12 13.2 16.6 17.6" fill="none" stroke="#000" stroke-width="1.4" stroke-linecap="round"/>'
  };

  // 7-segment digit (viewBox 0 0 13 23)
  function hSeg(y, x1, x2) {
    const t = 1.25;
    return `${x1},${y} ${x1 + t},${y - t} ${x2 - t},${y - t} ${x2},${y} ${x2 - t},${y + t} ${x1 + t},${y + t}`;
  }
  function vSeg(x, y1, y2) {
    const t = 1.25;
    return `${x},${y1} ${x + t},${y1 + t} ${x + t},${y2 - t} ${x},${y2} ${x - t},${y2 - t} ${x - t},${y1 + t}`;
  }
  const SEGS = {
    a: hSeg(1.6, 1.8, 11.2), g: hSeg(11.5, 1.8, 11.2), d: hSeg(21.4, 1.8, 11.2),
    f: vSeg(1.6, 1.9, 11.2), b: vSeg(11.4, 1.9, 11.2), e: vSeg(1.6, 11.8, 21.1), c: vSeg(11.4, 11.8, 21.1)
  };
  const DIGIT_SEGS = {
    '0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc', '5': 'afgcd',
    '6': 'afgedc', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': ''
  };
  function digitSvg(ch) {
    const on = DIGIT_SEGS[ch] || '';
    let s = '<svg viewBox="0 0 13 23" class="ms-digit">';
    for (const k of 'abcdefg') s += `<polygon points="${SEGS[k]}" fill="${on.includes(k) ? '#f00' : '#3a0000'}"/>`;
    return s + '</svg>';
  }
  function ledText(n) {
    n = Math.max(-99, Math.min(999, n | 0));
    if (n < 0) return '-' + String(-n).padStart(2, '0');
    return String(n).padStart(3, '0');
  }

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'ms-root';
    root.innerHTML = `
      <div class="ms-bar">
        <div class="ms-seg" role="group" aria-label="难度">
          ${Object.keys(PRESETS).map(k => `<button type="button" data-diff="${k}">${PRESETS[k].label}</button>`).join('')}
          <button type="button" data-diff="custom">自定义</button>
        </div>
        <label class="ms-chk"><input type="checkbox" class="ms-marks"><span>标记(?)</span></label>
      </div>
      <div class="ms-custom hidden">
        <label>行数 <input type="number" class="ms-in-rows" min="${LIMITS.rowsMin}" max="${LIMITS.rowsMax}"></label>
        <label>列数 <input type="number" class="ms-in-cols" min="${LIMITS.colsMin}" max="${LIMITS.colsMax}"></label>
        <label>雷数 <input type="number" class="ms-in-mines" min="${LIMITS.minesMin}"></label>
        <button type="button" class="ms-btn ms-primary ms-custom-ok">确定</button>
        <button type="button" class="ms-btn ms-custom-cancel">取消</button>
      </div>
      <div class="ms-frame">
        <div class="ms-head">
          <div class="ms-led ms-led-mines"></div>
          <button type="button" class="ms-face" title="新游戏 (F2)"><svg viewBox="0 0 24 24"></svg></button>
          <div class="ms-led ms-led-time"></div>
        </div>
        <div class="ms-board"></div>
      </div>
      <div class="ms-best"></div>
      <div class="ms-help">左键翻开 · 右键插旗 · 左右键同按 / 中键 / 单击数字 快速翻开周围 · F2 新游戏</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const frameEl = $('.ms-frame'), boardEl = $('.ms-board'), faceBtn = $('.ms-face'), faceSvg = faceBtn.querySelector('svg');
    const ledMines = $('.ms-led-mines'), ledTime = $('.ms-led-time');
    const bestEl = $('.ms-best'), marksCb = $('.ms-marks');
    const customEl = $('.ms-custom');
    const inRows = $('.ms-in-rows'), inCols = $('.ms-in-cols'), inMines = $('.ms-in-mines');
    const customOk = $('.ms-custom-ok'), customCancel = $('.ms-custom-cancel');
    const diffBtns = [...root.querySelectorAll('[data-diff]')];

    // ---------- settings ----------
    let diff = ctx.store.get('diff', 'beginner');
    if (!PRESETS[diff] && diff !== 'custom') diff = 'beginner';
    let custom = sanitizeCustom(ctx.store.get('custom', { rows: 20, cols: 24, mines: 80 }));
    let marks = ctx.store.get('marks', true) !== false;
    marksCb.checked = marks;

    function sanitizeCustom(c) {
      c = c || {};
      const rows = Math.max(LIMITS.rowsMin, Math.min(LIMITS.rowsMax, parseInt(c.rows, 10) || LIMITS.rowsMin));
      const cols = Math.max(LIMITS.colsMin, Math.min(LIMITS.colsMax, parseInt(c.cols, 10) || LIMITS.colsMin));
      const maxM = (rows - 1) * (cols - 1);
      const mines = Math.max(LIMITS.minesMin, Math.min(maxM, parseInt(c.mines, 10) || LIMITS.minesMin));
      return { rows, cols, mines };
    }
    const config = () => diff === 'custom' ? custom : PRESETS[diff];

    // ---------- state ----------
    let R, C, M, cells, els, state, revealedCount, flagCount, elapsed, lastTick, face;
    // state: 'ready' | 'playing' | 'won' | 'lost'
    let pressed = [];
    const input = { left: false, right: false, middle: false, chord: false, consumed: false, armed: false, hover: -1 };

    function neighbors(i) {
      const r = (i / C) | 0, c = i % C, out = [];
      for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
        if (!dr && !dc) continue;
        const rr = r + dr, cc = c + dc;
        if (rr >= 0 && rr < R && cc >= 0 && cc < C) out.push(rr * C + cc);
      }
      return out;
    }

    function newGame() {
      const cfg = config();
      R = cfg.rows; C = cfg.cols; M = cfg.mines;
      state = 'ready';
      revealedCount = 0; flagCount = 0; elapsed = 0; lastTick = 0;
      resetInput();
      pressed = [];
      cells = [];
      for (let i = 0; i < R * C; i++) cells.push({ mine: false, n: 0, open: false, flag: false, q: false, boom: false, html: null, cls: null });

      const cs = Math.max(16, Math.min(30, Math.floor(700 / C), Math.floor(430 / R)));
      boardEl.style.setProperty('--cs', cs + 'px');
      boardEl.style.setProperty('--bv', Math.max(2, Math.round(cs / 8)) + 'px');
      boardEl.style.gridTemplateColumns = `repeat(${C}, ${cs}px)`;
      const frag = document.createDocumentFragment();
      els = [];
      for (let i = 0; i < R * C; i++) {
        const d = document.createElement('div');
        d.dataset.i = i;
        els.push(d);
        frag.appendChild(d);
      }
      boardEl.textContent = '';
      boardEl.appendChild(frag);
      for (let i = 0; i < R * C; i++) paint(i);
      setFace('normal');
      updateMines();
      updateTime();
      updateBar();
    }

    function placeMines(safe) {
      const total = R * C;
      const excl = new Set([safe]);
      if (total - 9 >= M) neighbors(safe).forEach(j => excl.add(j));
      const pool = [];
      for (let i = 0; i < total; i++) if (!excl.has(i)) pool.push(i);
      for (let k = 0; k < M && pool.length; k++) {
        const j = k + ((Math.random() * (pool.length - k)) | 0);
        const t = pool[k]; pool[k] = pool[j]; pool[j] = t;
        cells[pool[k]].mine = true;
      }
      for (let i = 0; i < total; i++) cells[i].n = neighbors(i).reduce((s, j) => s + (cells[j].mine ? 1 : 0), 0);
    }

    // ---------- rendering ----------
    function paint(i) {
      const c = cells[i], d = els[i];
      let cls = 'ms-cell', html = '';
      const over = state === 'lost';
      if (c.open) {
        cls += ' ms-open';
        if (c.mine) { html = SVG_MINE; if (c.boom) cls += ' ms-boom'; }
        else if (c.n) { cls += ' ms-n' + c.n; html = String(c.n); }
      } else if (over && c.mine && !c.flag) {
        cls += ' ms-open'; html = SVG_MINE;
      } else if (over && c.flag && !c.mine) {
        cls += ' ms-open'; html = SVG_MINE_X;
      } else if (c.flag) {
        html = SVG_FLAG;
      } else {
        if (c.q) { html = '?'; cls += ' ms-q'; }
        if (pressed.includes(i)) cls += ' ms-open';
      }
      if (c.cls !== cls) { d.className = cls; c.cls = cls; }
      if (c.html !== html) { d.innerHTML = html; c.html = html; }
    }

    function setFace(f) {
      if (face === f) return;
      face = f;
      faceSvg.innerHTML = FACES[f];
    }
    function refreshFace() {
      if (state === 'won') setFace('win');
      else if (state === 'lost') setFace('lose');
      else if (input.armed && (input.left || input.chord) && !input.consumed) setFace('oh');
      else setFace('normal');
    }

    let ledMinesText = '', ledTimeText = '';
    function updateMines() {
      const t = ledText(M - flagCount);
      if (t !== ledMinesText) { ledMinesText = t; ledMines.innerHTML = [...t].map(digitSvg).join(''); }
    }
    const shownTime = () => state === 'ready' ? 0 : Math.min(999, Math.floor(elapsed / 1000) + 1);
    function updateTime() {
      const t = ledText(shownTime());
      if (t !== ledTimeText) { ledTimeText = t; ledTime.innerHTML = [...t].map(digitSvg).join(''); }
    }

    function bestKey(d) { return 'best_' + d; }
    function updateBar() {
      diffBtns.forEach(b => b.classList.toggle('active', b.dataset.diff === diff));
      bestEl.innerHTML = '最佳成绩：' + Object.keys(PRESETS).map(k => {
        const v = ctx.store.get(bestKey(k), null);
        return `<span class="${k === diff ? 'cur' : ''}">${PRESETS[k].label} ${v != null ? v + ' 秒' : '—'}</span>`;
      }).join('') + (diff === 'custom' ? `<span class="cur">自定义 ${R}×${C} / ${M} 雷（不计纪录）</span>` : '');
    }

    // ---------- pressed feedback ----------
    function computePressed() {
      if (state === 'won' || state === 'lost' || !input.armed || input.consumed || input.hover < 0) return [];
      let list;
      if (input.chord) list = [input.hover, ...neighbors(input.hover)];
      else if (input.left) list = [input.hover];
      else return [];
      return list.filter(j => !cells[j].open && !cells[j].flag);
    }
    function updatePressed() {
      const next = computePressed();
      const old = pressed;
      pressed = next;
      old.forEach(paint);
      next.forEach(paint);
      refreshFace();
    }

    // ---------- game logic ----------
    function startIfNeeded(i) {
      if (state !== 'ready') return;
      placeMines(i);
      state = 'playing';
      elapsed = 0;
      lastTick = performance.now();
      updateTime();
    }

    function reveal(i) {
      if (state !== 'ready' && state !== 'playing') return;
      const c = cells[i];
      if (c.open || c.flag) return;
      startIfNeeded(i);
      if (c.mine) { c.boom = true; c.open = true; lose(); return; }
      openArea(i);
      checkWin();
    }

    function openArea(i) {
      const stack = [i];
      while (stack.length) {
        const k = stack.pop();
        const c = cells[k];
        if (c.open || c.flag || c.mine) continue;
        c.open = true; c.q = false;
        revealedCount++;
        paint(k);
        if (c.n === 0) neighbors(k).forEach(j => { if (!cells[j].open && !cells[j].flag) stack.push(j); });
      }
    }

    function chord(i) {
      if (state !== 'playing') return;
      const c = cells[i];
      if (!c.open || !c.n) return;
      const nb = neighbors(i);
      const flags = nb.reduce((s, j) => s + (cells[j].flag ? 1 : 0), 0);
      if (flags !== c.n) return;
      let hit = false;
      nb.forEach(j => {
        const n = cells[j];
        if (n.open || n.flag) return;
        if (n.mine) { n.boom = true; n.open = true; hit = true; }
      });
      if (hit) { lose(); return; }
      nb.forEach(j => openArea(j));
      checkWin();
    }

    function toggleMark(i) {
      if (state !== 'ready' && state !== 'playing') return;
      const c = cells[i];
      if (c.open) return;
      if (c.flag) {
        c.flag = false; flagCount--;
        c.q = marks;
      } else if (c.q) {
        c.q = false;
      } else {
        c.flag = true; flagCount++;
      }
      paint(i);
      updateMines();
    }

    function lose() {
      state = 'lost';
      pressed = [];
      for (let i = 0; i < cells.length; i++) paint(i);
      refreshFace();
      updateTime();
    }

    function checkWin() {
      if (state !== 'playing' || revealedCount !== R * C - M) return;
      state = 'won';
      pressed = [];
      cells.forEach((c, i) => {
        if (c.mine && !c.flag) { c.flag = true; c.q = false; }
        paint(i);
      });
      flagCount = M;
      updateMines();
      updateTime();
      refreshFace();
      const t = shownTime();
      if (ctx.reward) ctx.reward({ beginner: 3, intermediate: 10, expert: 20 }[diff] || 3, '扫雷胜利');
      if (diff !== 'custom') {
        const old = ctx.store.get(bestKey(diff), null);
        if (old == null || t < old) {
          ctx.store.set(bestKey(diff), t);
          ctx.say('扫雷新纪录！' + t + '秒');
          ctx.toast && ctx.toast(`${PRESETS[diff].label}新纪录：${t} 秒`);
          updateBar();
          return;
        }
      }
      ctx.toast && ctx.toast(`胜利！用时 ${t} 秒`);
    }

    // ---------- timer ----------
    const timer = setInterval(() => {
      const now = performance.now();
      if (state === 'playing') {
        if (ctx.isActive()) elapsed += Math.min(now - lastTick, 1000);
        updateTime();
      }
      lastTick = now;
    }, 200);

    // ---------- input ----------
    function cellFrom(target) {
      const d = target && target.closest ? target.closest('.ms-cell') : null;
      if (!d || !boardEl.contains(d)) return -1;
      return +d.dataset.i;
    }
    function resetInput() {
      input.left = input.right = input.middle = input.chord = input.consumed = input.armed = false;
      input.hover = -1;
    }

    function onBoardDown(e) {
      e.preventDefault();
      if (state === 'won' || state === 'lost') return;
      const i = cellFrom(e.target);
      input.hover = i;
      input.armed = true;
      if (e.button === 0) {
        input.left = true;
        if (input.right) input.chord = true;
      } else if (e.button === 2) {
        input.right = true;
        if (input.left) input.chord = true;
        else if (i >= 0) toggleMark(i);
      } else if (e.button === 1) {
        input.middle = true;
        input.chord = true;
      }
      updatePressed();
    }

    function onMove(e) {
      if (!input.armed) return;
      const i = cellFrom(e.target);
      if (i !== input.hover) { input.hover = i; updatePressed(); }
    }

    function onUp(e) {
      if (!input.armed) return;
      const i = cellFrom(e.target);
      if (e.button === 0) input.left = false;
      else if (e.button === 2) input.right = false;
      else if (e.button === 1) input.middle = false;
      else return;
      if (!input.consumed && i >= 0) {
        if (input.chord) {
          chord(i);
          input.consumed = true;
        } else if (e.button === 0) {
          const c = cells[i];
          if (c.open && c.n) chord(i); else reveal(i);
          input.consumed = true;
        }
      } else if (input.chord) {
        input.consumed = true;
      }
      if (!input.left && !input.right && !input.middle) resetInput();
      updatePressed();
    }

    function onBlur() { resetInput(); if (cells) updatePressed(); }
    function onContext(e) { e.preventDefault(); }

    function onKey(e) {
      if (!ctx.isActive()) return;
      if (e.key === 'F2') {
        e.preventDefault();
        newGame();
      }
    }

    function onFace() { faceBtn.blur(); newGame(); }

    function onDiff(e) {
      const k = e.currentTarget.dataset.diff;
      e.currentTarget.blur();
      if (k === 'custom') { openCustom(); return; }
      customEl.classList.add('hidden');
      diff = k;
      ctx.store.set('diff', diff);
      newGame();
    }
    function openCustom() {
      inRows.value = custom.rows; inCols.value = custom.cols; inMines.value = custom.mines;
      customEl.classList.remove('hidden');
    }
    function onCustomOk() {
      custom = sanitizeCustom({ rows: inRows.value, cols: inCols.value, mines: inMines.value });
      ctx.store.set('custom', custom);
      diff = 'custom';
      ctx.store.set('diff', diff);
      customEl.classList.add('hidden');
      newGame();
    }
    function onCustomCancel() { customEl.classList.add('hidden'); }
    function onCustomKey(e) { if (e.key === 'Enter') onCustomOk(); else if (e.key === 'Escape') onCustomCancel(); }
    function onMarks() {
      marks = marksCb.checked;
      ctx.store.set('marks', marks);
      if (!marks && cells) cells.forEach((c, i) => { if (c.q) { c.q = false; paint(i); } });
      marksCb.blur();
    }

    boardEl.addEventListener('mousedown', onBoardDown);
    frameEl.addEventListener('contextmenu', onContext);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    window.addEventListener('blur', onBlur);
    window.addEventListener('keydown', onKey);
    faceBtn.addEventListener('click', onFace);
    diffBtns.forEach(b => b.addEventListener('click', onDiff));
    customOk.addEventListener('click', onCustomOk);
    customCancel.addEventListener('click', onCustomCancel);
    customEl.addEventListener('keydown', onCustomKey);
    marksCb.addEventListener('change', onMarks);

    newGame();

    cleanup = () => {
      clearInterval(timer);
      boardEl.removeEventListener('mousedown', onBoardDown);
      frameEl.removeEventListener('contextmenu', onContext);
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
      window.removeEventListener('blur', onBlur);
      window.removeEventListener('keydown', onKey);
      faceBtn.removeEventListener('click', onFace);
      diffBtns.forEach(b => b.removeEventListener('click', onDiff));
      customOk.removeEventListener('click', onCustomOk);
      customCancel.removeEventListener('click', onCustomCancel);
      customEl.removeEventListener('keydown', onCustomKey);
      marksCb.removeEventListener('change', onMarks);
      root.remove();
    };
  }

  Hub.register({
    id: 'minesweeper',
    title: '扫雷',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="5.5" fill="currentColor" stroke="none"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
