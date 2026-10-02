// 四子棋 — Connect Four vs AI (three levels) or two players. See ../MODULES.md for the contract.
(function () {
  const COLS = 7, ROWS = 6;
  const DIFFS = {
    easy: { label: '简单', depth: 1, noise: 0.45, reward: 3 },
    normal: { label: '普通', depth: 4, noise: 0, reward: 8 },
    hard: { label: '困难', depth: 8, noise: 0, reward: 18 }
  };
  const ORDER = [3, 2, 4, 1, 5, 0, 6];   // centre-first move ordering
  let cleanup = null;

  // ---------- engine (board: array[COLS*ROWS], index c*ROWS+r, r=0 bottom; 0 empty, 1 / 2 players) ----------
  const idx = (c, r) => c * ROWS + r;
  function height(b, c) { let r = 0; while (r < ROWS && b[idx(c, r)]) r++; return r; }
  const LINES = [];
  for (let c = 0; c < COLS; c++) for (let r = 0; r < ROWS; r++)
    for (const [dc, dr] of [[1, 0], [0, 1], [1, 1], [1, -1]]) {
      const ec = c + dc * 3, er = r + dr * 3;
      if (ec < 0 || ec >= COLS || er < 0 || er >= ROWS) continue;
      LINES.push([0, 1, 2, 3].map(k => idx(c + dc * k, r + dr * k)));
    }
  function winner(b) {
    for (const l of LINES) { const v = b[l[0]]; if (v && v === b[l[1]] && v === b[l[2]] && v === b[l[3]]) return { who: v, line: l }; }
    return null;
  }
  function evalBoard(b, me) {
    const op = 3 - me;
    let s = 0;
    for (let r = 0; r < ROWS; r++) { if (b[idx(3, r)] === me) s += 3; else if (b[idx(3, r)] === op) s -= 3; }
    for (const l of LINES) {
      let m = 0, o = 0;
      for (const i of l) { if (b[i] === me) m++; else if (b[i] === op) o++; }
      if (m && o) continue;
      if (m === 3) s += 50; else if (m === 2) s += 6;
      if (o === 3) s -= 60; else if (o === 2) s -= 6;
    }
    return s;
  }
  // score from the perspective of `me`, maximise over my moves
  function search(b, depth, me, deadline) {
    function rec(d, alpha, beta, cur) {
      const w = winner(b);
      if (w) return w.who === me ? 100000 + d : -100000 - d;
      if (b.every(Boolean)) return 0;
      if (d === 0 || performance.now() > deadline) return evalBoard(b, me);
      if (cur === me) {
        let v = -Infinity;
        for (const c of ORDER) { const r = height(b, c); if (r >= ROWS) continue; b[idx(c, r)] = cur; v = Math.max(v, rec(d - 1, alpha, beta, 3 - cur)); b[idx(c, r)] = 0; alpha = Math.max(alpha, v); if (alpha >= beta) break; }
        return v;
      }
      let v = Infinity;
      for (const c of ORDER) { const r = height(b, c); if (r >= ROWS) continue; b[idx(c, r)] = cur; v = Math.min(v, rec(d - 1, alpha, beta, 3 - cur)); b[idx(c, r)] = 0; beta = Math.min(beta, v); if (alpha >= beta) break; }
      return v;
    }
    const scores = [];
    for (const c of ORDER) {
      const r = height(b, c);
      if (r >= ROWS) continue;
      b[idx(c, r)] = me;
      scores.push({ c, v: rec(depth - 1, -Infinity, Infinity, 3 - me) });
      b[idx(c, r)] = 0;
    }
    return scores;
  }
  function aiMove(b, me, diff) {
    const D = DIFFS[diff];
    // always take an immediate win / block an immediate loss, even on easy
    for (const who of [me, 3 - me]) for (const c of ORDER) {
      const r = height(b, c); if (r >= ROWS) continue;
      b[idx(c, r)] = who; const w = winner(b); b[idx(c, r)] = 0;
      if (w && (who === me || Math.random() > D.noise)) return c;
    }
    const legal = ORDER.filter(c => height(b, c) < ROWS);
    if (Math.random() < D.noise) return legal[(Math.random() * legal.length) | 0];
    let best = null;
    const deadline = performance.now() + 650;
    // iterative deepening so the hard level never blocks the UI for long
    for (let d = Math.min(2, D.depth); d <= D.depth; d++) {
      const sc = search(b, d, me, deadline);
      if (performance.now() > deadline && best) break;
      const top = Math.max(...sc.map(s => s.v));
      const pool = sc.filter(s => s.v === top);
      best = pool[0].c;
      if (Math.abs(top) >= 100000) break;
    }
    return best != null ? best : legal[0];
  }

  // ---------- UI ----------
  function mount(el, ctx) {
    const saved = ctx.store.get('opts', {}) || {};
    let mode = saved.mode === 'pvp' ? 'pvp' : 'ai';
    let diff = DIFFS[saved.diff] ? saved.diff : 'normal';
    let humanFirst = saved.first !== false;
    const rec = ctx.store.get('rec', {}) || {};
    let board, turn, over, history, aiTimer = 0, busy = false;

    const root = document.createElement('div');
    root.className = 'c4-root';
    root.innerHTML = `
      <div class="c4-main">
        <div class="c4-board">
          <div class="c4-drops">${Array.from({ length: COLS }, (_, c) => `<div class="c4-col" data-c="${c}"><div class="c4-ghost"></div></div>`).join('')}</div>
          <div class="c4-grid"></div>
          <svg class="c4-frame" viewBox="0 0 700 600" preserveAspectRatio="none"><defs><mask id="c4-holes"><rect width="700" height="600" fill="#fff"/>${
            Array.from({ length: COLS * ROWS }, (_, i) => `<circle cx="${(i % COLS) * 100 + 50}" cy="${Math.floor(i / COLS) * 100 + 50}" r="40" fill="#000"/>`).join('')}</mask></defs>
            <rect width="700" height="600" rx="24" fill="#2f6fd0" mask="url(#c4-holes)"/>
            <rect x="2" y="2" width="696" height="596" rx="22" fill="none" stroke="rgba(255,255,255,.25)" stroke-width="4"/></svg>
        </div>
        <div class="c4-help">点击列落子 · ← → 选列，Enter / 空格落子 · Ctrl+Z 悔棋 · N 新局</div>
      </div>
      <div class="c4-side">
        <div class="c4-status"><i class="c4-dot"></i><span></span></div>
        <div class="c4-lbl">模式</div>
        <div class="c4-seg c4-mode"><button data-v="ai">人机对战</button><button data-v="pvp">双人对战</button></div>
        <div class="c4-aiopts">
          <div class="c4-lbl">难度</div>
          <div class="c4-seg c4-diff">${Object.entries(DIFFS).map(([k, d]) => `<button data-v="${k}">${d.label}</button>`).join('')}</div>
          <div class="c4-lbl">先手</div>
          <div class="c4-seg c4-first"><button data-v="1">我先手</button><button data-v="0">电脑先手</button></div>
        </div>
        <div class="c4-btns"><button class="btn c4-undo">悔棋</button><button class="btn primary c4-new">新局</button></div>
        <div class="c4-lbl">战绩</div>
        <table class="c4-rec"><thead><tr><th></th><th>胜</th><th>负</th><th>和</th></tr></thead><tbody></tbody></table>
      </div>
      <div class="c4-ov hidden"><div class="c4-card"><div class="c4-ov-t"></div><div class="c4-ov-s"></div><button class="btn primary c4-again">再来一局</button></div></div>`;
    el.appendChild(root);
    const q = s => root.querySelector(s);
    const grid = q('.c4-grid');
    let hoverCol = 3;

    const human = () => (mode === 'pvp' ? turn : humanFirst ? 1 : 2);
    const isHumanTurn = () => mode === 'pvp' || turn === human();
    const persist = () => ctx.store.set('opts', { mode, diff, first: humanFirst });

    function renderRec() {
      q('.c4-rec tbody').innerHTML = Object.entries(DIFFS).map(([k, d]) => {
        const r = rec[k] || { w: 0, l: 0, d: 0 };
        return `<tr class="${k === diff ? 'on' : ''}"><td>${d.label}</td><td>${r.w}</td><td>${r.l}</td><td>${r.d}</td></tr>`;
      }).join('');
    }
    function renderOpts() {
      root.querySelectorAll('.c4-mode button').forEach(b => b.classList.toggle('on', b.dataset.v === mode));
      root.querySelectorAll('.c4-diff button').forEach(b => b.classList.toggle('on', b.dataset.v === diff));
      root.querySelectorAll('.c4-first button').forEach(b => b.classList.toggle('on', (b.dataset.v === '1') === humanFirst));
      q('.c4-aiopts').style.display = mode === 'ai' ? '' : 'none';
      renderRec();
    }
    function status() {
      const dot = q('.c4-dot'), t = q('.c4-status span');
      dot.className = 'c4-dot p' + turn;
      if (over) { t.textContent = over.text; return; }
      if (mode === 'pvp') t.textContent = `${turn === 1 ? '红方' : '黄方'}落子`;
      else t.textContent = isHumanTurn() ? '轮到你落子' : '电脑思考中…';
      q('.c4-undo').disabled = !history.length || busy;
    }
    function draw(anim) {
      grid.innerHTML = '';
      for (let c = 0; c < COLS; c++) for (let r = 0; r < ROWS; r++) {
        const v = board[idx(c, r)];
        if (!v) continue;
        const d = document.createElement('div');
        d.className = `c4-disc p${v}`;
        d.style.left = `${c / COLS * 100}%`;
        d.style.top = `${(ROWS - 1 - r) / ROWS * 100}%`;
        if (anim && anim.c === c && anim.r === r) { d.classList.add('drop'); d.style.setProperty('--from', `${-(ROWS - r) * 100 - 20}%`); }
        if (over && over.line && over.line.includes(idx(c, r))) d.classList.add('win');
        grid.appendChild(d);
      }
      root.querySelectorAll('.c4-col').forEach(col => {
        const c = +col.dataset.c;
        col.classList.toggle('full', height(board, c) >= ROWS);
        col.classList.toggle('hover', c === hoverCol && !over && isHumanTurn() && !busy);
        col.querySelector('.c4-ghost').className = `c4-ghost p${turn}`;
      });
      status();
    }
    function newGame() {
      clearTimeout(aiTimer);
      board = new Array(COLS * ROWS).fill(0);
      turn = 1; over = null; history = []; busy = false;
      q('.c4-ov').classList.add('hidden');
      draw();
      if (mode === 'ai' && !humanFirst) scheduleAI();
    }
    function play(c) {
      if (over) return false;
      const r = height(board, c);
      if (r >= ROWS) return false;
      board[idx(c, r)] = turn;
      history.push(c);
      const w = winner(board);
      if (w) finish(w);
      else if (board.every(Boolean)) finish(null);
      else turn = 3 - turn;
      draw({ c, r });
      return true;
    }
    function finish(w) {
      if (!w) over = { text: '平局！' };
      else if (mode === 'pvp') over = { text: `${w.who === 1 ? '红方' : '黄方'}获胜！`, line: w.line };
      else over = { text: w.who === human() ? '你赢了！🎉' : '电脑赢了', line: w.line, win: w.who === human() };
      if (mode === 'ai') {
        const r = rec[diff] = rec[diff] || { w: 0, l: 0, d: 0 };
        if (!w) r.d++; else if (over.win) r.w++; else r.l++;
        ctx.store.set('rec', rec);
        renderRec();
        if (over.win) {
          ctx.reward(DIFFS[diff].reward, '四子棋胜利');
          ctx.say(`四子棋${DIFFS[diff].label}难度赢啦！连成四个真厉害～`);
        }
      }
      setTimeout(() => {
        if (!over) return;
        q('.c4-ov-t').textContent = over.text;
        q('.c4-ov-s').textContent = mode === 'ai' && over.win ? `获得 ${DIFFS[diff].reward} 小鱼干` : `共 ${history.length} 手`;
        q('.c4-ov').classList.remove('hidden');
      }, 900);
    }
    function scheduleAI() {
      if (over || mode !== 'ai' || isHumanTurn()) return;
      busy = true; status();
      aiTimer = setTimeout(function tick() {
        if (!ctx.isActive()) { aiTimer = setTimeout(tick, 300); return; }
        const c = aiMove(board.slice(), turn, diff);
        busy = false;
        play(c);
      }, 380);
    }
    function humanPlay(c) {
      if (busy || over || !isHumanTurn()) return;
      if (play(c)) scheduleAI();
    }
    function undo() {
      if (busy || !history.length) return;
      clearTimeout(aiTimer);
      // in AI mode take back the AI reply as well so it is the player's turn again
      const n = mode === 'ai' ? (over && !over.win && turn !== human() ? 1 : 2) : 1;
      for (let i = 0; i < n && history.length; i++) {
        const c = history.pop();
        board[idx(c, height(board, c) - 1)] = 0;
      }
      turn = history.length % 2 === 0 ? 1 : 2;
      over = null;
      q('.c4-ov').classList.add('hidden');
      draw();
      if (mode === 'ai' && !isHumanTurn()) scheduleAI();
    }

    root.querySelectorAll('.c4-col').forEach(col => {
      col.addEventListener('mouseenter', () => { hoverCol = +col.dataset.c; draw(); });
      col.addEventListener('click', () => humanPlay(+col.dataset.c));
    });
    root.querySelectorAll('.c4-mode button').forEach(b => b.onclick = () => { mode = b.dataset.v; persist(); renderOpts(); newGame(); });
    root.querySelectorAll('.c4-diff button').forEach(b => b.onclick = () => { diff = b.dataset.v; persist(); renderOpts(); newGame(); });
    root.querySelectorAll('.c4-first button').forEach(b => b.onclick = () => { humanFirst = b.dataset.v === '1'; persist(); renderOpts(); newGame(); });
    q('.c4-new').onclick = newGame;
    q('.c4-again').onclick = newGame;
    q('.c4-undo').onclick = undo;

    function onKey(e) {
      if (!ctx.isActive()) return;
      const t = e.target && e.target.tagName;
      if (t === 'INPUT' || t === 'TEXTAREA') return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); undo(); return; }
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.key === 'ArrowLeft') { hoverCol = (hoverCol + COLS - 1) % COLS; draw(); e.preventDefault(); }
      else if (e.key === 'ArrowRight') { hoverCol = (hoverCol + 1) % COLS; draw(); e.preventDefault(); }
      else if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') { e.preventDefault(); humanPlay(hoverCol); }
      else if (e.key >= '1' && e.key <= '7') { hoverCol = +e.key - 1; humanPlay(hoverCol); }
      else if (e.key === 'n' || e.key === 'N') newGame();
    }
    window.addEventListener('keydown', onKey);
    cleanup = () => { clearTimeout(aiTimer); window.removeEventListener('keydown', onKey); };

    renderOpts();
    newGame();
  }

  Hub.register({
    id: 'connect4', title: '四子棋', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="8" cy="9" r="1.8"/><circle cx="12" cy="9" r="1.8"/><circle cx="16" cy="9" r="1.8"/><circle cx="8" cy="15" r="1.8" fill="currentColor"/><circle cx="12" cy="15" r="1.8" fill="currentColor"/><circle cx="16" cy="15" r="1.8"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
