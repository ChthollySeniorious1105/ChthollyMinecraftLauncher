// 五子棋 — Gomoku module for the hub. See ../MODULES.md for the contract.
(function () {
  const N = 15;
  const CELL = 32, M = 34;
  const SIZE = M * 2 + CELL * (N - 1);           // 516
  const R = CELL * 0.46;                         // stone radius
  const EMPTY = 0, BLACK = 1, WHITE = 2;
  const DIFFS = {
    easy: { label: '简单', reward: 5 },
    normal: { label: '普通', reward: 10 },
    hard: { label: '困难', reward: 20 }
  };
  const COLS_LBL = 'ABCDEFGHIJKLMNO';
  const STARS = [[3, 3], [11, 3], [3, 11], [11, 11], [7, 7]];
  const TEASE = [
    '嘿嘿，这局我赢啦～再来挑战吧！',
    '喵哈哈，五子连珠！你还要多练练哦～',
    '差一点点哦，不过这局是我的啦！',
    '五子棋可没那么简单，下次加油～',
    '被我偷偷连成五子啦，嘻嘻！'
  ];

  // ================= AI =================
  const DIRS4 = [[1, 0], [0, 1], [1, 1], [1, -1]];
  const S_FIVE = 1e7, S_WIN4 = 1e6, S_43 = 5e5, S_33 = 1e5;
  const WIN = 1e9;
  const OPEN3_PATS = ['001110', '011100', '011010', '010110'];
  const OPEN2_PATS = ['001100', '011000', '000110', '01010', '010010'];

  // pattern occurs in s and spans the center index 5
  function hasPat(s, p) {
    let i = s.indexOf(p);
    while (i !== -1) {
      if (i <= 5 && i + p.length > 5) return true;
      i = s.indexOf(p, i + 1);
    }
    return false;
  }

  // line of 11 cells around (x,y) in direction (dx,dy) from color c's view; center assumed c
  function lineStr(b, x, y, dx, dy, c) {
    let s = '';
    for (let k = -5; k <= 5; k++) {
      if (k === 0) { s += '1'; continue; }
      const nx = x + dx * k, ny = y + dy * k;
      if (nx < 0 || ny < 0 || nx >= N || ny >= N) { s += '2'; continue; }
      const v = b[ny * N + nx];
      s += v === EMPTY ? '0' : v === c ? '1' : '2';
    }
    return s;
  }

  // 6 five, 5 open4, 4 four, 3 open3, 2 sleep3, 1.5 open2, 1 sleep2, 0.5 one, 0 dead
  function shapeOf(s) {
    let maxOnes = 0;
    for (let st = 1; st <= 5; st++) {
      const w = s.substr(st, 5);
      if (w.indexOf('2') !== -1) continue;
      let ones = 0;
      for (let k = 0; k < 5; k++) if (w.charCodeAt(k) === 49) ones++;
      if (ones > maxOnes) maxOnes = ones;
    }
    if (maxOnes >= 5) return 'five';
    if (maxOnes === 4) return hasPat(s, '011110') ? 'open4' : 'four';
    if (maxOnes === 3) return OPEN3_PATS.some(p => hasPat(s, p)) ? 'open3' : 'sleep3';
    if (maxOnes === 2) return OPEN2_PATS.some(p => hasPat(s, p)) ? 'open2' : 'sleep2';
    if (maxOnes === 1) return 'one';
    return null;
  }

  function pointScore(b, x, y, c) {
    const cnt = { five: 0, open4: 0, four: 0, open3: 0, sleep3: 0, open2: 0, sleep2: 0, one: 0 };
    for (const [dx, dy] of DIRS4) {
      const sh = shapeOf(lineStr(b, x, y, dx, dy, c));
      if (sh) cnt[sh]++;
    }
    if (cnt.five) return S_FIVE;
    let s = 0;
    if (cnt.open4 || cnt.four >= 2) s = S_WIN4;
    else if (cnt.four && cnt.open3) s = S_43;
    else if (cnt.open3 >= 2) s = S_33;
    return s + cnt.four * 6000 + cnt.open3 * 5000 + cnt.sleep3 * 500 +
      cnt.open2 * 300 + cnt.sleep2 * 60 + cnt.one * 10;
  }

  function genMoves(b, me) {
    const opp = 3 - me;
    const out = [];
    let any = false;
    for (let i = 0; i < N * N; i++) {
      if (b[i] !== EMPTY) { any = true; continue; }
      const x = i % N, y = (i / N) | 0;
      let near = false;
      for (let dy = -2; dy <= 2 && !near; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= N) continue;
        for (let dx = -2; dx <= 2; dx++) {
          const nx = x + dx;
          if (nx < 0 || nx >= N || (dx === 0 && dy === 0)) continue;
          if (b[ny * N + nx] !== EMPTY) { near = true; break; }
        }
      }
      if (!near) continue;
      out.push({ i, a: pointScore(b, x, y, me), d: pointScore(b, x, y, opp) });
    }
    if (!any) {
      const c = (N >> 1) * N + (N >> 1);
      return [{ i: c, a: 10, d: 10 }];
    }
    return out;
  }

  // static evaluation from the perspective of the side to move
  function staticEval(moves) {
    const threats = moves.filter(m => m.d >= S_FIVE);
    if (threats.length >= 2) return -WIN / 2;
    let as = moves.map(m => m.a).sort((p, q) => q - p);
    const ds = moves.map(m => m.d).sort((p, q) => q - p);
    if (threats.length === 1) as = [threats[0].a];      // forced block
    const a0 = as[0] || 0, d0 = ds[0] || 0;
    const aRest = (as[1] || 0) + (as[2] || 0) + (as[3] || 0);
    const dRest = (ds[1] || 0) + (ds[2] || 0) + (ds[3] || 0);
    return a0 - 0.6 * d0 + 0.1 * aRest - 0.1 * dRest;
  }

  const TIMEOUT = {};

  function negamax(b, me, depth, alpha, beta, ply, S) {
    if (++S.nodes % 64 === 0 && performance.now() > S.deadline) throw TIMEOUT;
    const moves = genMoves(b, me);
    if (!moves.length) return 0;
    for (const m of moves) if (m.a >= S_FIVE) return WIN - ply;
    const threats = moves.filter(m => m.d >= S_FIVE);
    if (depth === 0) return staticEval(moves);
    let list;
    if (threats.length) list = threats;
    else {
      moves.sort((p, q) => (q.a + q.d * 0.9) - (p.a + p.d * 0.9));
      list = moves.slice(0, S.width);
    }
    let best = -Infinity;
    for (const m of list) {
      b[m.i] = me;
      const v = -negamax(b, 3 - me, depth - 1, -beta, -alpha, ply + 1, S);
      b[m.i] = EMPTY;
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  function aiChoose(board, me, diff) {
    const b = Int8Array.from(board);
    const moves = genMoves(b, me);
    if (moves.length === 1) return moves[0].i;
    // immediate win / forced block
    let win = moves.find(m => m.a >= S_FIVE);
    if (win) return win.i;
    const block = moves.filter(m => m.d >= S_FIVE);
    if (block.length) return block.sort((p, q) => q.a - p.a)[0].i;

    if (diff === 'easy') {
      const sc = moves.map(m => ({ i: m.i, s: m.a + m.d * 0.6 + Math.random() * 400 }))
        .sort((p, q) => q.s - p.s);
      if (sc[0].s >= S_33) return sc[0].i;
      const k = Math.min(sc.length, 3);
      return sc[(Math.random() * k) | 0].i;
    }
    if (diff === 'normal') {
      let best = null, bs = -Infinity;
      for (const m of moves) {
        const s = m.a * 1.1 + m.d + Math.random() * 30;
        if (s > bs) { bs = s; best = m; }
      }
      return best.i;
    }

    // hard: iterative-deepening alpha-beta over top candidates
    const start = performance.now();
    const S = { deadline: start + 450, nodes: 0, width: 8 };
    let root = moves.slice().sort((p, q) => (q.a * 1.1 + q.d) - (p.a * 1.1 + p.d)).slice(0, 12);
    // an own winning shape (open four / double four) beats anything the search needs to confirm
    if (root[0].a >= S_WIN4 && root[0].a >= root[0].d) return root[0].i;
    let bestMove = root[0].i;
    for (let depth = 2; depth <= 4; depth++) {
      let iterBest = null, alpha = -Infinity;
      const scored = [];
      try {
        for (const m of root) {
          b[m.i] = me;
          let v;
          try { v = -negamax(b, 3 - me, depth - 1, -Infinity, -alpha, 1, S); }
          finally { b[m.i] = EMPTY; }
          // small tie-break by static heuristic
          v += (m.a * 1.1 + m.d) * 1e-4;
          scored.push({ m, v });
          if (v > alpha) { alpha = v; iterBest = m; }
        }
      } catch (e) {
        if (e !== TIMEOUT) throw e;
        break;
      }
      if (iterBest) bestMove = iterBest.i;
      if (alpha >= WIN / 2) break;             // found a forced win
      root = scored.sort((p, q) => q.v - p.v).map(o => o.m);
      if (performance.now() - start > 180) break; // next depth would likely overrun
    }
    return bestMove;
  }

  // ================= module =================
  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'gk-root';
    root.innerHTML = `
      <div class="gk-board">
        <canvas class="gk-canvas"></canvas>
        <div class="gk-banner hidden">
          <span class="gk-banner-text"></span>
          <button type="button" class="gk-btn gk-primary gk-again">再来一局</button>
        </div>
      </div>
      <div class="gk-side">
        <div class="gk-group">
          <div class="gk-lbl">模式</div>
          <div class="gk-seg" data-seg="mode">
            <button type="button" data-v="ai">人机对战</button><button type="button" data-v="pvp">双人对战</button>
          </div>
        </div>
        <div class="gk-group gk-ai-only">
          <div class="gk-lbl">执子</div>
          <div class="gk-seg" data-seg="color">
            <button type="button" data-v="1">执黑先手</button><button type="button" data-v="2">执白后手</button>
          </div>
        </div>
        <div class="gk-group gk-ai-only">
          <div class="gk-lbl">难度</div>
          <div class="gk-seg" data-seg="diff">
            ${Object.keys(DIFFS).map(k => `<button type="button" data-v="${k}">${DIFFS[k].label}</button>`).join('')}
          </div>
        </div>
        <div class="gk-status">
          <span class="gk-dot"></span>
          <span class="gk-status-text"></span>
        </div>
        <div class="gk-info">手数 <b class="gk-count">0</b></div>
        <div class="gk-actions">
          <button type="button" class="gk-btn gk-undo">悔棋</button>
          <button type="button" class="gk-btn gk-primary gk-new">新局</button>
        </div>
        <div class="gk-stats gk-ai-only">
          <div class="gk-lbl">战绩</div>
          <table>
            <thead><tr><th></th><th>胜</th><th>负</th><th>和</th></tr></thead>
            <tbody></tbody>
          </table>
        </div>
        <div class="gk-help">点击交叉点落子，先连成五子者胜</div>
      </div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const canvas = $('.gk-canvas');
    const g = canvas.getContext('2d');
    const banner = $('.gk-banner'), bannerText = $('.gk-banner-text');
    const statusText = $('.gk-status-text'), statusDot = $('.gk-dot'), countEl = $('.gk-count');
    const undoBtn = $('.gk-undo'), newBtn = $('.gk-new'), againBtn = $('.gk-again');
    const statsBody = $('.gk-stats tbody');
    const segs = [...root.querySelectorAll('.gk-seg')];

    // ---------- settings ----------
    let mode = ctx.store.get('mode', 'ai');
    if (mode !== 'ai' && mode !== 'pvp') mode = 'ai';
    let humanColor = ctx.store.get('color', BLACK) === WHITE ? WHITE : BLACK;
    let diff = ctx.store.get('diff', 'normal');
    if (!DIFFS[diff]) diff = 'normal';

    function getStats() {
      const s = ctx.store.get('stats', {}) || {};
      for (const k of Object.keys(DIFFS)) {
        s[k] = Object.assign({ w: 0, l: 0, d: 0 }, s[k] || {});
      }
      return s;
    }

    // ---------- state ----------
    let board, moves, turn, over, thinking = false, aiTimer = 0, hover = -1, rewarded = false;

    function newGame() {
      clearTimeout(aiTimer);
      thinking = false;
      board = new Int8Array(N * N);
      moves = [];
      turn = BLACK;
      over = null;
      rewarded = false;
      hover = -1;
      banner.classList.add('hidden');
      update();
      if (mode === 'ai' && turn !== humanColor) scheduleAI();
    }

    function findLine(i) {
      const c = board[i], x = i % N, y = (i / N) | 0;
      for (const [dx, dy] of DIRS4) {
        const cells = [i];
        for (const s of [1, -1]) {
          let nx = x + dx * s, ny = y + dy * s;
          while (nx >= 0 && ny >= 0 && nx < N && ny < N && board[ny * N + nx] === c) {
            cells.push(ny * N + nx);
            nx += dx * s; ny += dy * s;
          }
        }
        if (cells.length >= 5) return cells;
      }
      return null;
    }

    function place(i) {
      board[i] = turn;
      moves.push(i);
      const line = findLine(i);
      if (line) finish(turn, line);
      else if (moves.length === N * N) finish(0, null);
      else turn = 3 - turn;
      update();
    }

    function finish(winner, line) {
      over = { winner, line };
      thinking = false;
      let text;
      if (mode === 'ai') {
        const stats = getStats();
        if (winner === 0) { stats[diff].d++; text = '平局！'; }
        else if (winner === humanColor) {
          stats[diff].w++;
          text = '你赢了！';
          ctx.say('五子棋赢啦！');
          if (!rewarded) {
            rewarded = true;
            ctx.reward(DIFFS[diff].reward, '五子棋胜利');
          }
        } else {
          stats[diff].l++;
          text = '电脑获胜';
          ctx.say(TEASE[(Math.random() * TEASE.length) | 0]);
        }
        ctx.store.set('stats', stats);
      } else {
        text = winner === 0 ? '平局！' : (winner === BLACK ? '黑棋' : '白棋') + '获胜！';
      }
      bannerText.textContent = text + ` · 共 ${moves.length} 手`;
      banner.classList.remove('hidden');
    }

    function scheduleAI() {
      thinking = true;
      update();
      const aiColor = turn;
      const delay = diff === 'hard' ? 60 : 280;
      aiTimer = setTimeout(() => {
        aiTimer = 0;
        if (!thinking || over || turn !== aiColor) return;
        let i;
        try { i = aiChoose(board, aiColor, diff); }
        catch (e) { console.error('[gomoku] AI error', e); i = board.findIndex(v => v === EMPTY); }
        thinking = false;
        if (i >= 0 && board[i] === EMPTY) place(i);
        else update();
      }, delay);
    }

    function humanPlay(i) {
      if (over || thinking || i < 0 || board[i] !== EMPTY) return;
      if (mode === 'ai' && turn !== humanColor) return;
      place(i);
      if (!over && mode === 'ai') scheduleAI();
    }

    function popMove() {
      const i = moves.pop();
      turn = board[i];
      board[i] = EMPTY;
    }

    function undo() {
      if (over || !moves.length) return;
      if (thinking) { clearTimeout(aiTimer); aiTimer = 0; thinking = false; }
      if (mode === 'pvp') popMove();
      else {
        popMove();
        if (turn !== humanColor && moves.length) popMove();
        if (turn !== humanColor) { update(); scheduleAI(); return; }
      }
      update();
    }

    // ---------- UI ----------
    function update() {
      segs.forEach(sg => {
        const cur = sg.dataset.seg === 'mode' ? mode : sg.dataset.seg === 'color' ? String(humanColor) : diff;
        sg.querySelectorAll('button').forEach(b => b.classList.toggle('active', b.dataset.v === cur));
      });
      root.classList.toggle('gk-pvp', mode === 'pvp');
      countEl.textContent = moves.length;

      let txt, dot = turn;
      if (over) {
        dot = over.winner;
        if (over.winner === 0) txt = '平局';
        else if (mode === 'ai') txt = over.winner === humanColor ? '你赢了！' : '电脑获胜';
        else txt = (over.winner === BLACK ? '黑棋' : '白棋') + '获胜';
      } else if (thinking) {
        txt = '电脑思考中…';
      } else if (mode === 'ai') {
        txt = '轮到你落子（' + (humanColor === BLACK ? '黑' : '白') + '）';
      } else {
        txt = '轮到' + (turn === BLACK ? '黑棋' : '白棋');
      }
      statusText.textContent = txt;
      statusDot.className = 'gk-dot' + (dot === BLACK ? ' black' : dot === WHITE ? ' white' : ' none');
      root.classList.toggle('gk-thinking', thinking);

      let canUndo = !over && moves.length > 0;
      if (canUndo && mode === 'ai' && !thinking) {
        // need at least one human move on the board
        canUndo = moves.some((_, k) => (k % 2 === 0 ? BLACK : WHITE) === humanColor);
      }
      undoBtn.disabled = !canUndo;

      const stats = getStats();
      statsBody.innerHTML = Object.keys(DIFFS).map(k =>
        `<tr class="${k === diff ? 'cur' : ''}"><td>${DIFFS[k].label}</td><td>${stats[k].w}</td><td>${stats[k].l}</td><td>${stats[k].d}</td></tr>`
      ).join('');
      render();
    }

    // ---------- rendering ----------
    let dpr = 0, bgCanvas = null;
    const px = c => M + c * CELL;

    function setupCanvas() {
      const r = window.devicePixelRatio || 1;
      if (r === dpr && bgCanvas) return;
      dpr = r;
      canvas.width = Math.round(SIZE * dpr);
      canvas.height = Math.round(SIZE * dpr);
      canvas.style.width = SIZE + 'px';
      canvas.style.height = SIZE + 'px';
      bgCanvas = buildBackground();
    }

    function buildBackground() {
      const c = document.createElement('canvas');
      c.width = Math.round(SIZE * dpr);
      c.height = Math.round(SIZE * dpr);
      const b = c.getContext('2d');
      b.setTransform(dpr, 0, 0, dpr, 0, 0);
      // wood base
      const grad = b.createLinearGradient(0, 0, SIZE, SIZE);
      grad.addColorStop(0, '#f0cf96');
      grad.addColorStop(0.5, '#e4b673');
      grad.addColorStop(1, '#d9a45e');
      b.fillStyle = grad;
      b.fillRect(0, 0, SIZE, SIZE);
      // grain
      let seed = 20240917;
      const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
      for (let k = 0; k < 70; k++) {
        const y0 = rnd() * SIZE;
        const amp = 2 + rnd() * 6, freq = 0.006 + rnd() * 0.012, ph = rnd() * 6.28;
        b.strokeStyle = `rgba(${120 + (rnd() * 40) | 0},${70 + (rnd() * 30) | 0},30,${0.04 + rnd() * 0.08})`;
        b.lineWidth = 0.6 + rnd() * 1.8;
        b.beginPath();
        for (let x = -4; x <= SIZE + 4; x += 6) {
          const y = y0 + Math.sin(x * freq + ph) * amp + Math.sin(x * freq * 3.1 + ph) * amp * 0.25;
          if (x === -4) b.moveTo(x, y); else b.lineTo(x, y);
        }
        b.stroke();
      }
      // soft vignette
      const vg = b.createRadialGradient(SIZE / 2, SIZE / 2, SIZE * 0.3, SIZE / 2, SIZE / 2, SIZE * 0.75);
      vg.addColorStop(0, 'rgba(255,240,210,0)');
      vg.addColorStop(1, 'rgba(120,70,20,0.18)');
      b.fillStyle = vg;
      b.fillRect(0, 0, SIZE, SIZE);
      // grid
      b.strokeStyle = 'rgba(70,40,15,0.85)';
      b.lineWidth = 1;
      for (let k = 0; k < N; k++) {
        const p = Math.round(px(k)) + 0.5;
        b.beginPath(); b.moveTo(px(0), p); b.lineTo(px(N - 1), p); b.stroke();
        b.beginPath(); b.moveTo(p, px(0)); b.lineTo(p, px(N - 1)); b.stroke();
      }
      b.lineWidth = 2;
      b.strokeRect(px(0) - 0.5, px(0) - 0.5, CELL * (N - 1) + 2, CELL * (N - 1) + 2);
      // star points
      b.fillStyle = 'rgba(60,32,12,0.95)';
      for (const [sx, sy] of STARS) {
        b.beginPath(); b.arc(Math.round(px(sx)) + 0.5, Math.round(px(sy)) + 0.5, 3.6, 0, Math.PI * 2); b.fill();
      }
      // coordinates
      b.fillStyle = 'rgba(90,52,22,0.9)';
      b.font = '11px "Segoe UI", "Microsoft YaHei", sans-serif';
      b.textAlign = 'center';
      b.textBaseline = 'middle';
      for (let k = 0; k < N; k++) {
        b.fillText(COLS_LBL[k], px(k), 9);
        b.fillText(COLS_LBL[k], px(k), SIZE - 9);
        b.fillText(String(N - k), 10, px(k));
        b.fillText(String(N - k), SIZE - 10, px(k));
      }
      return c;
    }

    function drawStone(x, y, color, alpha) {
      const cx = px(x), cy = px(y);
      g.save();
      g.globalAlpha = alpha;
      if (alpha === 1) {
        g.shadowColor = 'rgba(40,20,5,0.45)';
        g.shadowBlur = 4 * dpr;
        g.shadowOffsetX = 1.5 * dpr;
        g.shadowOffsetY = 2 * dpr;
      }
      const grad = g.createRadialGradient(cx - R * 0.35, cy - R * 0.4, R * 0.1, cx, cy, R);
      if (color === BLACK) {
        grad.addColorStop(0, '#7a7a7a');
        grad.addColorStop(0.35, '#2c2c2c');
        grad.addColorStop(1, '#0a0a0a');
      } else {
        grad.addColorStop(0, '#ffffff');
        grad.addColorStop(0.6, '#f1ede6');
        grad.addColorStop(1, '#c9c1b4');
      }
      g.fillStyle = grad;
      g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.fill();
      g.restore();
    }

    function render() {
      setupCanvas();
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.drawImage(bgCanvas, 0, 0);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);

      for (let i = 0; i < N * N; i++) if (board[i]) drawStone(i % N, (i / N) | 0, board[i], 1);

      // hover preview
      const humanTurn = !over && !thinking && (mode === 'pvp' || turn === humanColor);
      if (hover >= 0 && humanTurn && board[hover] === EMPTY) drawStone(hover % N, (hover / N) | 0, turn, 0.45);

      // last move marker
      if (moves.length) {
        const i = moves[moves.length - 1];
        g.fillStyle = '#e5484d';
        g.beginPath(); g.arc(px(i % N), px((i / N) | 0), 3.8, 0, Math.PI * 2); g.fill();
      }

      // winning line
      if (over && over.line) {
        const pts = over.line.map(i => ({ x: px(i % N), y: px((i / N) | 0) }));
        pts.sort((a, b) => a.x - b.x || a.y - b.y);
        const a = pts[0], z = pts[pts.length - 1];
        g.save();
        g.lineCap = 'round';
        g.strokeStyle = 'rgba(232,121,58,0.85)';
        g.lineWidth = 5;
        g.shadowColor = 'rgba(232,121,58,0.9)';
        g.shadowBlur = 8 * dpr;
        g.beginPath(); g.moveTo(a.x, a.y); g.lineTo(z.x, z.y); g.stroke();
        g.shadowBlur = 0;
        g.lineWidth = 2.5;
        g.strokeStyle = '#ff9a4d';
        for (const p of pts) { g.beginPath(); g.arc(p.x, p.y, R + 1.5, 0, Math.PI * 2); g.stroke(); }
        g.restore();
      }
    }

    // ---------- input ----------
    function cellFromEvent(e) {
      const rect = canvas.getBoundingClientRect();
      const sx = SIZE / rect.width, sy = SIZE / rect.height;
      const mx = (e.clientX - rect.left) * sx, my = (e.clientY - rect.top) * sy;
      const cx = Math.round((mx - M) / CELL), cy = Math.round((my - M) / CELL);
      if (cx < 0 || cy < 0 || cx >= N || cy >= N) return -1;
      if (Math.hypot(mx - px(cx), my - px(cy)) > CELL * 0.48) return -1;
      return cy * N + cx;
    }
    function onMove(e) {
      const h = cellFromEvent(e);
      if (h !== hover) { hover = h; render(); }
      canvas.style.cursor = h >= 0 && board[h] === EMPTY && !over && !thinking ? 'pointer' : 'default';
    }
    function onLeave() { if (hover !== -1) { hover = -1; render(); } }
    function onClick(e) {
      const i = cellFromEvent(e);
      if (i >= 0) humanPlay(i);
    }
    function onSeg(e) {
      const btn = e.target.closest('button');
      if (!btn) return;
      const seg = e.currentTarget.dataset.seg, v = btn.dataset.v;
      btn.blur();
      if (seg === 'mode') { if (v === mode) return; mode = v; ctx.store.set('mode', mode); }
      else if (seg === 'color') { const c = +v; if (c === humanColor && mode === 'ai') return; humanColor = c; ctx.store.set('color', c); }
      else if (seg === 'diff') { if (v === diff) return; diff = v; ctx.store.set('diff', diff); }
      const midGame = moves.length > 0 && !over;
      newGame();
      if (midGame) ctx.toast && ctx.toast('设置已更改，已开始新的一局');
    }
    function onUndo(e) { e.currentTarget.blur(); undo(); }
    function onNew(e) { e.currentTarget.blur(); newGame(); }
    function onResize() { render(); }

    canvas.addEventListener('mousemove', onMove);
    canvas.addEventListener('mouseleave', onLeave);
    canvas.addEventListener('click', onClick);
    segs.forEach(s => s.addEventListener('click', onSeg));
    undoBtn.addEventListener('click', onUndo);
    newBtn.addEventListener('click', onNew);
    againBtn.addEventListener('click', onNew);
    window.addEventListener('resize', onResize);

    newGame();

    cleanup = () => {
      clearTimeout(aiTimer);
      thinking = false;
      window.removeEventListener('resize', onResize);
      canvas.removeEventListener('mousemove', onMove);
      canvas.removeEventListener('mouseleave', onLeave);
      canvas.removeEventListener('click', onClick);
      segs.forEach(s => s.removeEventListener('click', onSeg));
      undoBtn.removeEventListener('click', onUndo);
      newBtn.removeEventListener('click', onNew);
      againBtn.removeEventListener('click', onNew);
      root.remove();
    };
  }

  Hub.register({
    id: 'gomoku',
    title: '五子棋',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18" opacity=".55"/><circle cx="9" cy="9" r="2.6" fill="currentColor" stroke="none"/><circle cx="15" cy="15" r="2.4" fill="none" stroke-width="1.8"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
