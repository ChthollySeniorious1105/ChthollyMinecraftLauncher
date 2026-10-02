// 中国象棋 — board UI. Rules and search live in xiangqi-engine.js (window.XiangqiEngine),
// which also runs as a Web Worker so the computer never freezes the window.
(function () {
  const E = window.XiangqiEngine;
  const LEVELS = { easy: { label: '简单', reward: 5 }, normal: { label: '普通', reward: 12 }, hard: { label: '困难', reward: 25 } };
  const NAME_R = ['', '帅', '仕', '相', '傌', '俥', '炮', '兵'];
  const NAME_B = ['', '將', '士', '象', '馬', '車', '砲', '卒'];
  const CELL = 52, M = 40;
  const W = M * 2 + CELL * 8, H = M * 2 + CELL * 9;
  const TEASE = ['将军！这局是我的啦～', '嘿嘿，棋差一招哦', '再来一盘？我让你一个车…开玩笑的', '这步棋你没想到吧！'];

  // the worker loads the engine file itself; if workers are unavailable, search inline
  function makeSearcher() {
    let worker = null, seq = 0;
    const waiting = new Map();
    try {
      worker = new Worker('games/xiangqi-engine.js');
      worker.onmessage = e => {
        const cb = waiting.get(e.data.id);
        waiting.delete(e.data.id);
        if (cb) cb(e.data);
      };
      worker.onerror = () => { worker = null; };
    } catch { worker = null; }
    return {
      run(board, side, level, cb) {
        const id = ++seq;
        if (worker) {
          waiting.set(id, cb);
          worker.postMessage({ id, board: Array.from(board), side, level });
        } else {
          setTimeout(() => cb(Object.assign({ id }, E.search(Int8Array.from(board), side, level))), 30);
        }
        return id;
      },
      cancel() { waiting.clear(); },
      dispose() { waiting.clear(); if (worker) worker.terminate(); worker = null; }
    };
  }

  let inst = null;

  Hub.register({
    id: 'xiangqi', title: '中国象棋', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="6.2" stroke-width="1.2"/><path d="M9 10.5h6M12 8v8M9.5 14h5" stroke-width="1.6" stroke-linecap="round"/></svg>',
    mount(el, ctx) {
      const root = document.createElement('div');
      root.className = 'xq-root';
      root.innerHTML = `
        <div class="xq-main">
          <canvas class="xq-board"></canvas>
          <div class="xq-banner xq-hidden"></div>
        </div>
        <div class="xq-side">
          <div class="xq-seg" data-k="mode"><button data-v="ai">人机对战</button><button data-v="pvp">双人对战</button></div>
          <div class="xq-seg" data-k="color"><button data-v="1">执红先手</button><button data-v="-1">执黑后手</button></div>
          <div class="xq-seg" data-k="level">${Object.entries(LEVELS).map(([k, v]) => `<button data-v="${k}">${v.label}</button>`).join('')}</div>
          <div class="xq-status"></div>
          <div class="xq-btns"><button class="xq-btn" data-a="undo">悔棋</button><button class="xq-btn xq-primary" data-a="new">新局</button></div>
          <div class="xq-moves-t">着法</div>
          <ol class="xq-moves"></ol>
          <div class="xq-stats"></div>
        </div>`;
      el.appendChild(root);
      const q = s => root.querySelector(s);
      const canvas = q('.xq-board'), g = canvas.getContext('2d');

      const cfg = Object.assign({ mode: 'ai', color: 1, level: 'normal' }, ctx.store.get('cfg', {}));
      let board, side, history, selected, targets, lastMove, over, thinking, searchId, rewarded;
      const searcher = makeSearcher();
      let hoverSq = -1;

      function newGame() {
        searcher.cancel();
        board = E.initial();
        side = 1;
        history = [];
        selected = -1; targets = []; lastMove = 0; over = null; thinking = false; rewarded = false;
        q('.xq-banner').classList.add('xq-hidden');
        render();
        maybeAi();
      }
      const human = s => cfg.mode === 'pvp' || s === Number(cfg.color);

      function sqToXY(sq) {
        let r = (sq / 9) | 0, c = sq % 9;
        if (cfg.mode === 'ai' && Number(cfg.color) < 0) { r = 9 - r; c = 8 - c; } // black at the bottom
        return [M + c * CELL, M + r * CELL];
      }
      function xyToSq(x, y) {
        let c = Math.round((x - M) / CELL), r = Math.round((y - M) / CELL);
        if (c < 0 || c > 8 || r < 0 || r > 9) return -1;
        if (Math.hypot(x - (M + c * CELL), y - (M + r * CELL)) > CELL * 0.46) return -1;
        if (cfg.mode === 'ai' && Number(cfg.color) < 0) { r = 9 - r; c = 8 - c; }
        return r * 9 + c;
      }

      // ---------- drawing ----------
      function setupCanvas() {
        const dpr = window.devicePixelRatio || 1;
        canvas.width = W * dpr; canvas.height = H * dpr;
        canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
        g.setTransform(dpr, 0, 0, dpr, 0, 0);
      }
      function drawBoard() {
        const grd = g.createLinearGradient(0, 0, W, H);
        grd.addColorStop(0, '#f1c98a'); grd.addColorStop(1, '#dca763');
        g.fillStyle = grd;
        g.beginPath(); g.roundRect(0, 0, W, H, 14); g.fill();
        g.strokeStyle = 'rgba(140, 90, 40, .12)';
        for (let i = 0; i < 40; i++) {
          g.lineWidth = 1 + (i % 3);
          g.beginPath();
          const y = (i * 37) % H;
          g.moveTo(0, y); g.bezierCurveTo(W / 3, y + 8, W * 2 / 3, y - 8, W, y + 4); g.stroke();
        }
        g.strokeStyle = '#6b3f24';
        g.lineWidth = 3;
        g.strokeRect(M - 6, M - 6, CELL * 8 + 12, CELL * 9 + 12);
        g.lineWidth = 1.4;
        for (let r = 0; r < 10; r++) line(0, r, 8, r);
        for (let c = 0; c < 9; c++) {
          if (c === 0 || c === 8) line(c, 0, c, 9);
          else { line(c, 0, c, 4); line(c, 5, c, 9); }
        }
        line(3, 0, 5, 2); line(5, 0, 3, 2); line(3, 7, 5, 9); line(5, 7, 3, 9);
        const marks = [[2, 1], [2, 7], [7, 1], [7, 7]];
        for (let c = 0; c < 9; c += 2) marks.push([3, c], [6, c]);
        for (const [r, c] of marks) mark(r, c);
        g.fillStyle = 'rgba(107, 63, 36, .75)';
        g.font = `bold ${CELL * 0.5}px "KaiTi", "STKaiti", "Microsoft YaHei UI", serif`;
        g.textAlign = 'center'; g.textBaseline = 'middle';
        const ry = M + CELL * 4.5;
        g.fillText('楚 河', M + CELL * 2, ry);
        g.fillText('汉 界', M + CELL * 6, ry);
      }
      function line(c1, r1, c2, r2) {
        g.beginPath(); g.moveTo(M + c1 * CELL, M + r1 * CELL); g.lineTo(M + c2 * CELL, M + r2 * CELL); g.stroke();
      }
      function mark(r, c) {
        const x = M + c * CELL, y = M + r * CELL, d = 4, l = 10;
        g.beginPath();
        for (const sx of [-1, 1]) {
          if ((c === 0 && sx < 0) || (c === 8 && sx > 0)) continue;
          for (const sy of [-1, 1]) {
            g.moveTo(x + sx * (d + l), y + sy * d); g.lineTo(x + sx * d, y + sy * d); g.lineTo(x + sx * d, y + sy * (d + l));
          }
        }
        g.stroke();
      }
      function drawPiece(sq, p, lift) {
        const [x, y0] = sqToXY(sq), y = y0 - (lift ? 3 : 0), rad = CELL * 0.44;
        g.save();
        g.shadowColor = 'rgba(60, 30, 10, .45)'; g.shadowBlur = lift ? 10 : 4; g.shadowOffsetY = lift ? 5 : 2;
        const grd = g.createRadialGradient(x - rad * 0.3, y - rad * 0.3, rad * 0.1, x, y, rad);
        grd.addColorStop(0, '#fff4dc'); grd.addColorStop(0.7, '#f3d7a4'); grd.addColorStop(1, '#d6a765');
        g.fillStyle = grd;
        g.beginPath(); g.arc(x, y, rad, 0, Math.PI * 2); g.fill();
        g.restore();
        const col = p > 0 ? '#c0392b' : '#2b2b2b';
        g.strokeStyle = col; g.lineWidth = 1.6;
        g.beginPath(); g.arc(x, y, rad * 0.8, 0, Math.PI * 2); g.stroke();
        g.fillStyle = col;
        g.font = `bold ${rad * 1.05}px "KaiTi", "STKaiti", "Microsoft YaHei UI", serif`;
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText((p > 0 ? NAME_R : NAME_B)[Math.abs(p)], x, y + 1);
      }
      function render() {
        drawBoard();
        if (lastMove) {
          for (const sq of [lastMove >> 7, lastMove & 127]) {
            const [x, y] = sqToXY(sq);
            g.strokeStyle = '#2f7de1'; g.lineWidth = 2.5;
            corner(x, y, CELL * 0.48);
          }
        }
        const k = E.findKing(board, side);
        if (!over && k >= 0 && E.inCheck(board, side)) {
          const [x, y] = sqToXY(k);
          g.fillStyle = 'rgba(229, 72, 77, .35)';
          g.beginPath(); g.arc(x, y, CELL * 0.52, 0, Math.PI * 2); g.fill();
        }
        for (let sq = 0; sq < 90; sq++) if (board[sq]) drawPiece(sq, board[sq], sq === selected);
        for (const m of targets) {
          const t = m & 127, [x, y] = sqToXY(t);
          g.fillStyle = board[t] ? 'rgba(229, 72, 77, .55)' : 'rgba(46, 160, 67, .6)';
          g.beginPath(); g.arc(x, y, board[t] ? CELL * 0.48 : 7, 0, Math.PI * 2);
          if (board[t]) { g.lineWidth = 3; g.strokeStyle = g.fillStyle; g.stroke(); } else g.fill();
        }
        if (hoverSq >= 0 && targets.some(m => (m & 127) === hoverSq)) {
          const [x, y] = sqToXY(hoverSq);
          g.strokeStyle = 'rgba(46, 160, 67, .9)'; g.lineWidth = 2;
          g.beginPath(); g.arc(x, y, CELL * 0.46, 0, Math.PI * 2); g.stroke();
        }
        renderSide();
      }
      function corner(x, y, s) {
        const l = s * 0.45;
        g.beginPath();
        for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
          g.moveTo(x + sx * s, y + sy * (s - l)); g.lineTo(x + sx * s, y + sy * s); g.lineTo(x + sx * (s - l), y + sy * s);
        }
        g.stroke();
      }
      function renderSide() {
        for (const seg of root.querySelectorAll('.xq-seg')) {
          const k = seg.dataset.k;
          seg.classList.toggle('xq-disabled', cfg.mode === 'pvp' && k !== 'mode');
          seg.querySelectorAll('button').forEach(b => b.classList.toggle('xq-on', String(cfg[k]) === b.dataset.v));
        }
        const st = q('.xq-status');
        const who = side > 0 ? '红方' : '黑方';
        if (over) st.innerHTML = `<b>${over.text}</b>`;
        else if (thinking) st.innerHTML = `<span class="xq-dot ${side > 0 ? 'r' : 'b'}"></span>电脑思考中…`;
        else st.innerHTML = `<span class="xq-dot ${side > 0 ? 'r' : 'b'}"></span>${cfg.mode === 'ai' ? (human(side) ? '轮到你走棋' : '电脑走棋') : `轮到${who}`}${E.inCheck(board, side) ? ' · <em>将军！</em>' : ''}`;
        const ol = q('.xq-moves');
        ol.innerHTML = '';
        for (let i = 0; i < history.length; i += 2) {
          const li = document.createElement('li');
          li.innerHTML = `<span>${history[i].text}</span><span>${history[i + 1] ? history[i + 1].text : ''}</span>`;
          ol.appendChild(li);
        }
        ol.scrollTop = ol.scrollHeight;
        q('[data-a=undo]').disabled = !history.length || thinking;
        const s = ctx.store.get('stats', {})[cfg.level] || { w: 0, l: 0 };
        q('.xq-stats').textContent = cfg.mode === 'ai' ? `${LEVELS[cfg.level].label}战绩：${s.w} 胜 ${s.l} 负` : '双人对战';
      }

      // ---------- game flow ----------
      function play(m) {
        const text = E.notate(board, m);
        const cap = E.makeMove(board, m);
        history.push({ m, cap, text });
        lastMove = m;
        side = -side;
        selected = -1; targets = [];
        checkEnd();
        render();
        if (!over) maybeAi();
      }
      function checkEnd() {
        if (E.genLegal(board, side).length) {
          if (history.length >= 300) finish(0, '回合过多，和棋');
          return;
        }
        const mated = E.inCheck(board, side);
        finish(-side, `${side > 0 ? '黑方' : '红方'}胜 · ${mated ? '绝杀' : '困毙'}`);
      }
      function finish(winner, text) {
        over = { winner, text };
        const banner = q('.xq-banner');
        banner.textContent = text;
        banner.classList.remove('xq-hidden');
        if (cfg.mode !== 'ai' || !winner) return;
        const stats = ctx.store.get('stats', {});
        const s = stats[cfg.level] || (stats[cfg.level] = { w: 0, l: 0 });
        if (winner === Number(cfg.color)) {
          s.w++;
          ctx.say('象棋赢啦！');
          if (!rewarded) { rewarded = true; ctx.reward(LEVELS[cfg.level].reward, '象棋胜利'); }
        } else {
          s.l++;
          ctx.say(TEASE[Math.floor(Math.random() * TEASE.length)]);
        }
        ctx.store.set('stats', stats);
      }
      function maybeAi() {
        if (over || human(side)) return;
        thinking = true;
        render();
        const mySide = side;
        searchId = searcher.run(board, side, cfg.level, res => {
          if (!inst || res.id !== searchId || over || side !== mySide) return;
          thinking = false;
          const legal = E.genLegal(board, side);
          play(legal.includes(res.move) ? res.move : legal[0]);
        });
      }
      function undo() {
        if (!history.length) return;
        searcher.cancel();
        thinking = false;
        const steps = cfg.mode === 'ai' ? (human(side) ? 2 : 1) : 1;
        for (let i = 0; i < steps && history.length; i++) {
          const h = history.pop();
          E.unmake(board, h.m, h.cap);
          side = -side;
        }
        // never leave the computer to move after an undo in AI mode
        if (cfg.mode === 'ai' && !human(side) && history.length) {
          const h = history.pop();
          E.unmake(board, h.m, h.cap);
          side = -side;
        }
        lastMove = history.length ? history[history.length - 1].m : 0;
        over = null; selected = -1; targets = [];
        q('.xq-banner').classList.add('xq-hidden');
        render();
        maybeAi();
      }

      // ---------- input ----------
      const pos = e => {
        const r = canvas.getBoundingClientRect();
        return [(e.clientX - r.left) * W / r.width, (e.clientY - r.top) * H / r.height];
      };
      const onClick = e => {
        if (over || thinking || !human(side)) return;
        const sq = xyToSq(...pos(e));
        if (sq < 0) return;
        const mv = targets.find(m => (m & 127) === sq);
        if (mv) return play(mv);
        if (board[sq] * side > 0) {
          selected = sq;
          targets = E.genLegal(board, side).filter(m => m >> 7 === sq);
        } else { selected = -1; targets = []; }
        render();
      };
      const onMove = e => {
        const sq = xyToSq(...pos(e));
        canvas.style.cursor = sq >= 0 && (board[sq] * side > 0 && human(side) || targets.some(m => (m & 127) === sq)) ? 'pointer' : 'default';
        if (sq !== hoverSq) { hoverSq = sq; if (targets.length) render(); }
      };
      canvas.addEventListener('click', onClick);
      canvas.addEventListener('mousemove', onMove);
      const onSide = e => {
        const b = e.target.closest('button');
        if (!b || b.disabled) return;
        if (b.dataset.a === 'new') return newGame();
        if (b.dataset.a === 'undo') return undo();
        const seg = b.closest('.xq-seg');
        if (!seg || seg.classList.contains('xq-disabled')) return;
        const k = seg.dataset.k, v = b.dataset.v;
        if (String(cfg[k]) === v) return;
        cfg[k] = k === 'color' ? Number(v) : v;
        ctx.store.set('cfg', cfg);
        if (history.length) ctx.toast('设置已更改，开始新的一局');
        newGame();
      };
      q('.xq-side').addEventListener('click', onSide);

      inst = { searcher, cleanup() { canvas.removeEventListener('click', onClick); canvas.removeEventListener('mousemove', onMove); q('.xq-side').removeEventListener('click', onSide); root.remove(); } };
      setupCanvas();
      newGame();
    },
    unmount() {
      if (!inst) return;
      inst.searcher.dispose();
      inst.cleanup();
      inst = null;
    }
  });
})();
