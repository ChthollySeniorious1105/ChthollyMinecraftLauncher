// 黑白棋 — Reversi / Othello module for the hub. See ../MODULES.md for the contract.
(function () {
  const EMPTY = 0, BLACK = 1, WHITE = 2;
  const DIFFS = {
    easy: { label: '简单', reward: 4 },
    normal: { label: '普通', reward: 10 },
    hard: { label: '困难', reward: 20 }
  };
  const NAME = { 1: '黑方', 2: '白方' };
  const TEASE = [
    '嘿嘿，这局是我的啦～角落可要抢先占哦！',
    '喵～翻翻翻，全变成我的颜色啦！',
    '黑白棋讲究“少吃多占”，下次再来挑战吧～',
    '差一点点哦，再来一局？'
  ];

  // ================= board helpers =================
  // RAYS[sq] = array of rays (each an array of squares walking outward in one direction)
  const RAYS = [];
  for (let sq = 0; sq < 64; sq++) {
    const x = sq % 8, y = sq >> 3, rays = [];
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue;
      const r = [];
      let nx = x + dx, ny = y + dy;
      while (nx >= 0 && ny >= 0 && nx < 8 && ny < 8) { r.push(ny * 8 + nx); nx += dx; ny += dy; }
      if (r.length >= 2) rays.push(r);
    }
    RAYS[sq] = rays;
  }

  function isLegal(b, sq, c) {
    if (b[sq] !== EMPTY) return false;
    const o = 3 - c;
    for (const r of RAYS[sq]) {
      if (b[r[0]] !== o) continue;
      let k = 1;
      while (k < r.length && b[r[k]] === o) k++;
      if (k < r.length && b[r[k]] === c) return true;
    }
    return false;
  }
  function movesOf(b, c) {
    const res = [];
    for (let sq = 0; sq < 64; sq++) if (b[sq] === EMPTY && isLegal(b, sq, c)) res.push(sq);
    return res;
  }
  function countMoves(b, c) {
    let n = 0;
    for (let sq = 0; sq < 64; sq++) if (b[sq] === EMPTY && isLegal(b, sq, c)) n++;
    return n;
  }
  function flipsOf(b, sq, c) {
    const o = 3 - c, out = [];
    for (const r of RAYS[sq]) {
      let k = 0;
      while (k < r.length && b[r[k]] === o) k++;
      if (k > 0 && k < r.length && b[r[k]] === c) for (let j = 0; j < k; j++) out.push(r[j]);
    }
    return out;
  }
  function counts(b) {
    let bl = 0, wh = 0;
    for (let i = 0; i < 64; i++) { if (b[i] === BLACK) bl++; else if (b[i] === WHITE) wh++; }
    return { b: bl, w: wh };
  }

  // fast make/unmake with a shared flip stack (search only)
  const FS = new Int8Array(8192);
  let sp = 0;
  function doMove(b, sq, c) {
    const o = 3 - c, start = sp;
    for (const r of RAYS[sq]) {
      let k = 0;
      while (k < r.length && b[r[k]] === o) k++;
      if (k > 0 && k < r.length && b[r[k]] === c) for (let j = 0; j < k; j++) { b[r[j]] = c; FS[sp++] = r[j]; }
    }
    b[sq] = c;
    return start;
  }
  function undoMove(b, sq, start, c) {
    const o = 3 - c;
    while (sp > start) b[FS[--sp]] = o;
    b[sq] = EMPTY;
  }

  // ================= AI =================
  const W = [
    100, -20, 10, 5, 5, 10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
    10, -2, -1, -1, -1, -1, -2, 10,
    5, -2, -1, -1, -1, -1, -2, 5,
    5, -2, -1, -1, -1, -1, -2, 5,
    10, -2, -1, -1, -1, -1, -2, 10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5, 5, 10, -20, 100
  ];
  const CORNERS = [[0, [1, 8, 9]], [7, [6, 15, 14]], [56, [57, 48, 49]], [63, [62, 55, 54]]];
  const TIMEOUT = { timeout: true };
  const WIN_SCORE = 100000;

  function finalScore(b, c) {
    let d = 0;
    for (let i = 0; i < 64; i++) { if (b[i] === c) d++; else if (b[i] === 3 - c) d--; }
    return d > 0 ? WIN_SCORE + d : d < 0 ? -WIN_SCORE + d : 0;
  }

  function evaluate(b, c, hard) {
    const o = 3 - c;
    let pos = 0, empties = 0, disc = 0;
    for (let i = 0; i < 64; i++) {
      const v = b[i];
      if (v === c) { pos += W[i]; disc++; }
      else if (v === o) { pos -= W[i]; disc--; }
      else empties++;
    }
    // once a corner is taken, its X / C squares are no longer dangerous
    for (const [cn, adj] of CORNERS) {
      if (b[cn] === EMPTY) continue;
      for (const a of adj) { if (b[a] === c) pos -= W[a]; else if (b[a] === o) pos += W[a]; }
    }
    const mc = countMoves(b, c), mo = countMoves(b, o);
    let mob = mc + mo ? 100 * (mc - mo) / (mc + mo + 2) : 0;
    let s = pos + (hard ? 0.9 : 0.6) * mob;
    if (hard) {
      // frontier discs (adjacent to an empty square) are a liability
      let fr = 0;
      for (let i = 0; i < 64; i++) {
        const v = b[i];
        if (v === EMPTY) continue;
        const x = i & 7, y = i >> 3;
        let front = false;
        for (let dy = -1; dy <= 1 && !front; dy++) for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < 8 && ny < 8 && b[ny * 8 + nx] === EMPTY) { front = true; break; }
        }
        if (front) fr += v === c ? -1 : 1;
      }
      s += 4 * fr;
      if (empties < 16) s += (16 - empties) * disc * 0.8;
    } else if (empties < 12) s += disc * 2;
    return s;
  }

  function orderStatic(ms) { return ms.sort((a, b) => W[b] - W[a]); }

  function negamax(b, c, depth, alpha, beta, passed, S) {
    if ((++S.nodes & 1023) === 0 && performance.now() > S.deadline) throw TIMEOUT;
    if (depth <= 0) return evaluate(b, c, S.hard);
    const ms = movesOf(b, c);
    if (!ms.length) {
      if (passed) return finalScore(b, c);
      return -negamax(b, 3 - c, depth - 1, -beta, -alpha, true, S);
    }
    orderStatic(ms);
    let best = -Infinity;
    for (const m of ms) {
      const st = doMove(b, m, c);
      const v = -negamax(b, 3 - c, depth - 1, -beta, -alpha, false, S);
      undoMove(b, m, st, c);
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  function rootSearch(b, c, depth, ms, S) {
    let alpha = -Infinity, best = ms[0], bestV = -Infinity;
    for (const m of ms) {
      const st = doMove(b, m, c);
      const v = -negamax(b, 3 - c, depth - 1, -Infinity, -alpha, false, S);
      undoMove(b, m, st, c);
      if (v > bestV) { bestV = v; best = m; }
      if (v > alpha) alpha = v;
    }
    return { move: best, score: bestV };
  }

  // exact endgame solver on disc difference (empties list for speed)
  function solve(b, c, alpha, beta, passed, empties, S) {
    if ((++S.nodes & 1023) === 0 && performance.now() > S.deadline) throw TIMEOUT;
    const o = 3 - c;
    let ms = [];
    for (const sq of empties) if (b[sq] === EMPTY && isLegal(b, sq, c)) ms.push(sq);
    if (!ms.length) {
      if (passed) { let d = 0; for (let i = 0; i < 64; i++) { if (b[i] === c) d++; else if (b[i] === o) d--; } return d; }
      return -solve(b, o, -beta, -alpha, true, empties, S);
    }
    if (ms.length > 1) {
      let emptyCount = 0;
      for (const sq of empties) if (b[sq] === EMPTY) emptyCount++;
      if (emptyCount > 6) {
        // fastest-first: minimise opponent mobility
        const keyed = ms.map(m => { const st = doMove(b, m, c); let n = 0; for (const e of empties) if (b[e] === EMPTY && isLegal(b, e, o)) n++; undoMove(b, m, st, c); return [m, n * 100 - W[m]]; });
        keyed.sort((x, y) => x[1] - y[1]);
        ms = keyed.map(k => k[0]);
      } else orderStatic(ms);
    }
    let best = -Infinity;
    for (const m of ms) {
      const st = doMove(b, m, c);
      const v = -solve(b, o, -beta, -alpha, false, empties, S);
      undoMove(b, m, st, c);
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  function aiChoose(board, c, diff) {
    const ms = movesOf(board, c);
    if (!ms.length) return -1;
    if (ms.length === 1) return ms[0];
    if (diff === 'easy') {
      if (Math.random() < 0.35) return ms[(Math.random() * ms.length) | 0];
      let best = [], bn = -1;
      for (const m of ms) {
        const n = flipsOf(board, m, c).length + Math.random() * 1.5;
        if (n > bn + 0.5) { bn = n; best = [m]; } else if (Math.abs(n - bn) <= 0.5) best.push(m);
      }
      return best[(Math.random() * best.length) | 0];
    }
    const b = Int8Array.from(board);
    sp = 0;
    if (diff === 'normal') {
      const S = { nodes: 0, deadline: Infinity, hard: false };
      // shuffle first so equal scores are not always resolved the same way
      for (let i = ms.length - 1; i > 0; i--) { const j = (Math.random() * (i + 1)) | 0; [ms[i], ms[j]] = [ms[j], ms[i]]; }
      return rootSearch(b, c, 3, orderStatic(ms.slice()), S).move;
    }
    // hard
    const t0 = performance.now();
    const empties = [];
    for (let i = 0; i < 64; i++) if (b[i] === EMPTY) empties.push(i);
    if (empties.length <= 12) {
      const S = { nodes: 0, deadline: t0 + 2500 };
      try {
        let best = ms[0], bestV = -Infinity, alpha = -65;
        const ordered = orderStatic(ms.slice());
        for (const m of ordered) {
          const st = doMove(b, m, c);
          const v = -solve(b, 3 - c, -65, -alpha, false, empties, S);
          undoMove(b, m, st, c);
          if (v > bestV) { bestV = v; best = m; }
          if (v > alpha) alpha = v;
        }
        return best;
      } catch (e) {
        if (e !== TIMEOUT) throw e;
        sp = 0;
        for (let i = 0; i < 64; i++) b[i] = board[i];
      }
    }
    const S = { nodes: 0, deadline: performance.now() + 800, hard: true };
    let order = orderStatic(ms.slice()), best = order[0];
    for (let d = 1; d <= 6; d++) {
      try {
        const r = rootSearch(b, c, d, order, S);
        best = r.move;
        order = [best, ...order.filter(m => m !== best)];
        if (Math.abs(r.score) >= WIN_SCORE) break; // result is decided
      } catch (e) {
        if (e !== TIMEOUT) throw e;
        break;
      }
    }
    return best;
  }

  // ================= module =================
  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'rv-root';
    let cells = '';
    for (let i = 0; i < 64; i++) {
      cells += `<div class="rv-cell" data-i="${i}"><div class="rv-stone"><div class="rv-flip"><i class="rv-face rv-fb"></i><i class="rv-face rv-fw"></i></div></div></div>`;
    }
    let lines = '';
    for (let k = 1; k < 8; k++) lines += `<line x1="${k}" y1="0" x2="${k}" y2="8"/><line x1="0" y1="${k}" x2="8" y2="${k}"/>`;
    root.innerHTML = `
      <div class="rv-board">
        <svg class="rv-bg" viewBox="0 0 8 8" preserveAspectRatio="none">
          <defs><radialGradient id="rvFelt" cx="50%" cy="45%" r="75%"><stop offset="0" stop-color="#3a9d5d"/><stop offset="1" stop-color="#23733f"/></radialGradient></defs>
          <rect width="8" height="8" fill="url(#rvFelt)"/>
          <g stroke="#1a5a30" stroke-width="0.035">${lines}</g>
          <g fill="#1a5a30"><circle cx="2" cy="2" r=".08"/><circle cx="6" cy="2" r=".08"/><circle cx="2" cy="6" r=".08"/><circle cx="6" cy="6" r=".08"/></g>
        </svg>
        <div class="rv-grid">${cells}</div>
        <div class="rv-banner hidden"><span class="rv-banner-text"></span><button type="button" class="btn primary rv-again">再来一局</button></div>
      </div>
      <div class="rv-side">
        <div class="rv-score">
          <div class="rv-sc rv-sc-b"><i class="rv-dot black"></i><b class="rv-nb">2</b><span class="rv-who-b"></span></div>
          <div class="rv-sc rv-sc-w"><i class="rv-dot white"></i><b class="rv-nw">2</b><span class="rv-who-w"></span></div>
        </div>
        <div class="rv-group">
          <div class="rv-lbl">模式</div>
          <div class="rv-seg" data-seg="mode"><button type="button" data-v="ai">人机对战</button><button type="button" data-v="pvp">双人对战</button></div>
        </div>
        <div class="rv-group rv-ai-only">
          <div class="rv-lbl">执子</div>
          <div class="rv-seg" data-seg="color"><button type="button" data-v="1">执黑先手</button><button type="button" data-v="2">执白后手</button></div>
        </div>
        <div class="rv-group rv-ai-only">
          <div class="rv-lbl">难度</div>
          <div class="rv-seg" data-seg="diff">${Object.keys(DIFFS).map(k => `<button type="button" data-v="${k}">${DIFFS[k].label}</button>`).join('')}</div>
        </div>
        <div class="rv-status"><span class="rv-dot rv-sdot"></span><span class="rv-status-text"></span></div>
        <div class="rv-actions">
          <button type="button" class="btn rv-undo">悔棋</button>
          <button type="button" class="btn primary rv-new">新局</button>
        </div>
        <div class="rv-stats rv-ai-only">
          <div class="rv-lbl">战绩</div>
          <table><thead><tr><th></th><th>胜</th><th>负</th><th>和</th></tr></thead><tbody></tbody></table>
        </div>
        <div class="rv-help">落子须夹住对方棋子并将其翻转；无处可下时自动跳过，双方都无法落子时终局，子多者胜。<br>快捷键：Ctrl+Z 悔棋 · N 新局</div>
      </div>`;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const cellEls = [...root.querySelectorAll('.rv-cell')];
    const flipEls = cellEls.map(c => c.querySelector('.rv-flip'));
    const stoneEls = cellEls.map(c => c.querySelector('.rv-stone'));
    const banner = $('.rv-banner'), bannerText = $('.rv-banner-text');
    const statusText = $('.rv-status-text'), statusDot = $('.rv-sdot');
    const undoBtn = $('.rv-undo');
    const segs = [...root.querySelectorAll('.rv-seg')];

    let mode = ctx.store.get('mode', 'ai');
    if (mode !== 'ai' && mode !== 'pvp') mode = 'ai';
    let human = ctx.store.get('color', BLACK) === WHITE ? WHITE : BLACK;
    let diff = ctx.store.get('diff', 'normal');
    if (!DIFFS[diff]) diff = 'normal';

    function getStats() {
      const s = ctx.store.get('stats', {}) || {};
      for (const k of Object.keys(DIFFS)) s[k] = Object.assign({ w: 0, l: 0, d: 0 }, s[k] || {});
      return s;
    }

    let board, turn, over, hist, last, thinking = false, aiTimer = 0, rewarded = false, passNote = '';
    let shown = new Int8Array(64);

    function newGame() {
      clearTimeout(aiTimer); aiTimer = 0;
      thinking = false;
      board = new Int8Array(64);
      board[27] = WHITE; board[36] = WHITE; board[28] = BLACK; board[35] = BLACK;
      turn = BLACK; over = null; hist = []; last = -1; rewarded = false; passNote = '';
      banner.classList.add('hidden');
      render(-1, false);
      if (mode === 'ai' && turn !== human) scheduleAI(500);
    }

    // ---------- rendering ----------
    function render(origin, anim) {
      const ox = origin % 8, oy = origin >> 3;
      const humanTurn = !over && !thinking && (mode === 'pvp' || turn === human);
      const legal = humanTurn ? new Set(movesOf(board, turn)) : new Set();
      for (let i = 0; i < 64; i++) {
        const v = board[i], cell = cellEls[i], flip = flipEls[i], stone = stoneEls[i];
        if (v !== shown[i]) {
          if (v === EMPTY) {
            cell.classList.remove('has');
          } else if (shown[i] === EMPTY || !anim) {
            flip.style.transition = 'none';
            flip.classList.toggle('w', v === WHITE);
            void flip.offsetWidth;
            flip.style.transition = '';
            cell.classList.add('has');
            stone.classList.remove('pop', 'lift');
            stone.style.animationDelay = '0ms';
            if (anim) { void stone.offsetWidth; stone.classList.add('pop'); }
          } else {
            const dist = Math.max(Math.abs((i % 8) - ox), Math.abs((i >> 3) - oy));
            const delay = `${Math.max(0, dist - 1) * 70 + 60}ms`;
            flip.style.transitionDelay = delay;
            stone.style.animationDelay = delay;
            stone.classList.remove('pop', 'lift');
            void stone.offsetWidth;
            stone.classList.add('lift');
            flip.classList.toggle('w', v === WHITE);
          }
          shown[i] = v;
        }
        cell.classList.toggle('hint', legal.has(i));
        cell.classList.toggle('last', i === last);
      }
      root.classList.toggle('rv-turn-w', turn === WHITE);
      root.classList.toggle('rv-pvp', mode === 'pvp');
      root.classList.toggle('rv-thinking', thinking);
      updateSide();
    }

    function updateSide() {
      segs.forEach(sg => {
        const cur = sg.dataset.seg === 'mode' ? mode : sg.dataset.seg === 'color' ? String(human) : diff;
        sg.querySelectorAll('button').forEach(b => b.classList.toggle('active', b.dataset.v === cur));
      });
      const n = counts(board);
      $('.rv-nb').textContent = n.b; $('.rv-nw').textContent = n.w;
      $('.rv-who-b').textContent = mode === 'ai' ? (human === BLACK ? '你' : '电脑') : '黑方';
      $('.rv-who-w').textContent = mode === 'ai' ? (human === WHITE ? '你' : '电脑') : '白方';
      $('.rv-sc-b').classList.toggle('on', !over && turn === BLACK);
      $('.rv-sc-w').classList.toggle('on', !over && turn === WHITE);

      let txt, dot = turn;
      if (over) {
        dot = over.winner;
        txt = over.winner === 0 ? '平局' : mode === 'ai' ? (over.winner === human ? '你赢了！' : '电脑获胜') : NAME[over.winner] + '获胜';
      } else if (thinking) txt = '电脑思考中…';
      else if (mode === 'ai') txt = '轮到你落子';
      else txt = `轮到${NAME[turn]}`;
      if (!over && passNote) txt = passNote + ' · ' + txt;
      statusText.textContent = txt;
      statusDot.className = 'rv-dot rv-sdot ' + (dot === BLACK ? 'black' : dot === WHITE ? 'white' : 'none');
      undoBtn.disabled = !!over || !hist.some(h => mode === 'pvp' || h.turn === human);

      const st = getStats();
      $('.rv-stats tbody').innerHTML = Object.keys(DIFFS).map(k =>
        `<tr class="${k === diff ? 'cur' : ''}"><td>${DIFFS[k].label}</td><td>${st[k].w}</td><td>${st[k].l}</td><td>${st[k].d}</td></tr>`).join('');
    }

    // ---------- game flow ----------
    function play(i) {
      const fl = flipsOf(board, i, turn);
      if (!fl.length || board[i] !== EMPTY) return false;
      hist.push({ b: board.slice(), turn, last, passNote });
      board[i] = turn;
      for (const f of fl) board[f] = turn;
      last = i;
      advance();
      render(i, true);
      return true;
    }

    function advance() {
      const o = 3 - turn;
      passNote = '';
      if (movesOf(board, o).length) { turn = o; return; }
      if (movesOf(board, turn).length) {
        const who = mode === 'ai' ? (o === human ? '你' : '电脑') : NAME[o];
        passNote = `${who}无子可下，跳过`;
        ctx.toast(`${who}无子可下，跳过一手`);
        return;
      }
      finish();
    }

    function finish() {
      const n = counts(board);
      const winner = n.b > n.w ? BLACK : n.w > n.b ? WHITE : 0;
      over = { winner };
      let text;
      if (mode === 'ai') {
        const stats = getStats();
        if (winner === 0) { stats[diff].d++; text = '平局！'; }
        else if (winner === human) {
          stats[diff].w++;
          text = '你赢了！';
          if (!rewarded) {
            rewarded = true;
            ctx.say(`黑白棋${DIFFS[diff].label}难度赢啦！${n.b}:${n.w}，厉害厉害～`);
            ctx.reward(DIFFS[diff].reward, '黑白棋胜利');
          }
        } else {
          stats[diff].l++;
          text = '电脑获胜';
          ctx.say(TEASE[(Math.random() * TEASE.length) | 0]);
        }
        ctx.store.set('stats', stats);
      } else text = winner === 0 ? '平局！' : NAME[winner] + '获胜！';
      bannerText.textContent = `${text}  黑 ${n.b} : ${n.w} 白`;
      setTimeout(() => { if (over) banner.classList.remove('hidden'); }, 600);
    }

    function scheduleAI(delay) {
      thinking = true;
      updateSide();
      root.classList.add('rv-thinking');
      cellEls.forEach(c => c.classList.remove('hint'));
      const aiColor = turn;
      clearTimeout(aiTimer);
      aiTimer = setTimeout(function tick() {
        aiTimer = 0;
        if (!thinking || over || turn !== aiColor) return;
        if (!ctx.isActive()) { aiTimer = setTimeout(tick, 300); return; }
        let m;
        try { m = aiChoose(board, aiColor, diff); }
        catch (e) { console.error('[reversi] AI error', e); m = movesOf(board, aiColor)[0]; }
        thinking = false;
        if (m >= 0) play(m); else render(-1, false);
        afterMove();
      }, delay);
    }

    function afterMove() {
      if (!over && mode === 'ai' && turn !== human) scheduleAI(620);
    }

    function humanPlay(i) {
      if (over || thinking) return;
      if (mode === 'ai' && turn !== human) return;
      if (play(i)) afterMove();
    }

    function undo() {
      if (over || !hist.length) return;
      let idx = hist.length - 1;
      if (mode === 'ai') while (idx >= 0 && hist[idx].turn !== human) idx--;
      if (idx < 0) return;
      clearTimeout(aiTimer); aiTimer = 0; thinking = false;
      const s = hist[idx];
      hist.length = idx;
      board = s.b; turn = s.turn; last = s.last; passNote = s.passNote;
      render(-1, false);
    }

    // ---------- events ----------
    function onClick(e) {
      const c = e.target.closest('.rv-cell');
      if (c) humanPlay(+c.dataset.i);
    }
    function onSeg(e) {
      const btn = e.target.closest('button');
      if (!btn) return;
      const seg = e.currentTarget.dataset.seg, v = btn.dataset.v;
      btn.blur();
      if (seg === 'mode') { if (v === mode) return; mode = v; ctx.store.set('mode', mode); }
      else if (seg === 'color') { const c = +v; if (c === human) return; human = c; ctx.store.set('color', c); }
      else if (seg === 'diff') { if (v === diff) return; diff = v; ctx.store.set('diff', diff); }
      const mid = hist.length > 0 && !over;
      newGame();
      if (mid) ctx.toast('设置已更改，已开始新的一局');
    }
    function onUndo(e) { e.currentTarget.blur(); undo(); }
    function onNew(e) { e.currentTarget.blur(); newGame(); }
    function onKey(e) {
      if (!ctx.isActive()) return;
      const t = e.target && e.target.tagName;
      if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') return;
      if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); }
      else if (!e.ctrlKey && !e.metaKey && !e.altKey && (e.key === 'n' || e.key === 'N')) { e.preventDefault(); newGame(); }
    }

    const grid = $('.rv-grid'), newBtn = $('.rv-new'), againBtn = $('.rv-again');
    grid.addEventListener('click', onClick);
    segs.forEach(s => s.addEventListener('click', onSeg));
    undoBtn.addEventListener('click', onUndo);
    newBtn.addEventListener('click', onNew);
    againBtn.addEventListener('click', onNew);
    window.addEventListener('keydown', onKey);

    newGame();

    cleanup = () => {
      clearTimeout(aiTimer); aiTimer = 0;
      thinking = false;
      window.removeEventListener('keydown', onKey);
      grid.removeEventListener('click', onClick);
      segs.forEach(s => s.removeEventListener('click', onSeg));
      undoBtn.removeEventListener('click', onUndo);
      newBtn.removeEventListener('click', onNew);
      againBtn.removeEventListener('click', onNew);
      root.remove();
    };
  }

  Hub.register({
    id: 'reversi',
    title: '黑白棋',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="3.2" fill="currentColor" stroke="none"/><circle cx="15" cy="15" r="3.2" fill="currentColor" stroke="none"/><circle cx="15" cy="9" r="2.8"/><circle cx="9" cy="15" r="2.8"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
