// 国际象棋 — board UI. Rules/search in chess-engine.js (window.ChessEngine), run in a Web Worker.
(function () {
  const E = window.ChessEngine;
  const LEVELS = { easy: { label: '简单', reward: 5 }, normal: { label: '普通', reward: 12 }, hard: { label: '困难', reward: 25 } };
  const THEMES = {
    wood: ['#f0d9b5', '#b58863', '木纹'],
    green: ['#eeeed2', '#769656', '草地'],
    sea: ['#dee3e6', '#8ca2ad', '海蓝'],
    candy: ['#fde2e4', '#e8a0b4', '糖果']
  };
  const TEASE = ['将死！这盘是我的啦～', '嘿嘿，要不要再来一盘？', '我的皇后可厉害了！'];

  // SVG pieces: shared silhouettes, filled white or dark
  const SHAPES = {
    1: '<path d="M22.5 9a4 4 0 0 0-3.2 6.4A6.5 6.5 0 0 0 16 21c0 2 1 3.8 2.4 5-3 1-7.4 5.6-7.4 13.5h23c0-7.9-4.4-12.5-7.4-13.5A6.5 6.5 0 0 0 29 21a6.5 6.5 0 0 0-3.3-5.6A4 4 0 0 0 22.5 9z"/>',
    2: '<path d="M22 10c10.5 1 16.5 8 16 29H15c0-9 10-6.5 8-21"/><path d="M24 18c.4 2.9-5.6 7.4-8 9-3 2-2.8 4.3-5 4-1-.9 1.4-3 0-3-1 0 .2 1.2-1 2-1 0-4 1-4-4 0-2 6-12 6-12s1.9-1.9 2-3.5c-.7-1-.5-2-.5-3 1-1 3 2.5 3 2.5h2s.8-2 2.5-3c1 0 1 3 1 3"/>',
    3: '<path d="M9 36c3.4-1 10.1.4 13.5-2 3.4 2.4 10.1 1 13.5 2 0 0 1.6.5 3 2-.7 1-1.6 1-3 .5-3.4-1-10.1.5-13.5-1-3.4 1.5-10.1 0-13.5 1-1.4.5-2.3.5-3-.5 1.4-2 3-2 3-2z"/><path d="M15 32c2.5 2.5 12.5 2.5 15 0 .5-1.5 0-2 0-2 0-2.5-2.5-4-2.5-4 5.5-1.5 6-11.5-5-15.5-11 4-10.5 14-5 15.5 0 0-2.5 1.5-2.5 4 0 0-.5.5 0 2z"/><circle cx="22.5" cy="8" r="2.5"/>',
    4: '<path d="M9 39h27v-3H9zM12 36v-4h21v4zM11 14V9h4v2h5V9h5v2h5V9h4v5"/><path d="M34 14l-3 3H14l-3-3M31 17v12.5H14V17M31 29.5l1.5 2.5h-20l1.5-2.5"/>',
    5: '<path d="M9 26c8.5-1.5 21-1.5 27 0l2-12-7 11V11l-5.5 13.5-3-15-3 15-5.5-14V25L7 14z"/><path d="M9 26c0 2 1.5 2 2.5 4 1 1.5 1 1 .5 3.5-1.5 1-1.5 2.5-1.5 2.5-1.5 1.5.5 2.5.5 2.5 6.5 1 16.5 1 23 0 0 0 1.5-1 0-2.5 0 0 .5-1.5-1-2.5-.5-2.5-.5-2 .5-3.5 1-2 2.5-2 2.5-4-8.5-1.5-18.5-1.5-27 0z"/><circle cx="6" cy="12" r="2"/><circle cx="14" cy="9" r="2"/><circle cx="22.5" cy="8" r="2"/><circle cx="31" cy="9" r="2"/><circle cx="39" cy="12" r="2"/>',
    6: '<path d="M22.5 11.6V6M20 8h5"/><path d="M22.5 25s4.5-7.5 3-10.5c0 0-1-2.5-3-2.5s-3 2.5-3 2.5c-1.5 3 3 10.5 3 10.5"/><path d="M12.5 37c5.5 3.5 14.5 3.5 20 0v-7s9-4.5 6-10.5c-4-6.5-13.5-3.5-16 4V27v-3.5c-2.5-7.5-12-10.5-16-4-3 6 6 10.5 6 10.5v7"/><path d="M12.5 30c5.5-3 14.5-3 20 0M12.5 33.5c5.5-3 14.5-3 20 0M12.5 37c5.5-3 14.5-3 20 0" fill="none"/>'
  };
  function pieceSvg(p) {
    const white = p > 0;
    return `<svg viewBox="0 0 45 45"><g fill="${white ? '#fffaf0' : '#3b2a22'}" stroke="${white ? '#3b2a22' : '#f3e6d4'}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round">${SHAPES[Math.abs(p)]}</g></svg>`;
  }

  let inst = null;
  Hub.register({
    id: 'chess', title: '国际象棋', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M8 20h8M9 17h6l-1-5 2-3-3-1V5h-2v3l-3 1 2 3z"/><path d="M11 5h2"/></svg>',
    mount(el, ctx) {
      const cfg = Object.assign({ mode: 'ai', color: 1, level: 'normal', theme: 'wood' }, ctx.store.get('cfg', {}));
      const root = document.createElement('div');
      root.className = 'ch-root';
      root.innerHTML = `
        <div class="ch-main">
          <div class="ch-board"></div>
          <div class="ch-promo ch-hidden"></div>
          <div class="ch-banner ch-hidden"></div>
        </div>
        <div class="ch-side">
          <div class="ch-seg" data-k="mode"><button data-v="ai">人机对战</button><button data-v="pvp">双人对战</button></div>
          <div class="ch-seg" data-k="color"><button data-v="1">执白先手</button><button data-v="-1">执黑后手</button></div>
          <div class="ch-seg" data-k="level">${Object.entries(LEVELS).map(([k, v]) => `<button data-v="${k}">${v.label}</button>`).join('')}</div>
          <div class="ch-seg ch-themes" data-k="theme">${Object.entries(THEMES).map(([k, v]) => `<button data-v="${k}">${v[2]}</button>`).join('')}</div>
          <div class="ch-status"></div>
          <div class="ch-caps"><div class="ch-cap-w"></div><div class="ch-cap-b"></div></div>
          <div class="ch-btns"><button class="ch-btn" data-a="undo">悔棋</button><button class="ch-btn" data-a="flip">翻转</button><button class="ch-btn ch-primary" data-a="new">新局</button></div>
          <ol class="ch-moves"></ol>
          <div class="ch-stats"></div>
        </div>`;
      el.appendChild(root);
      const q = s => root.querySelector(s);
      const boardEl = q('.ch-board');

      let st, history, legalMoves, selected, lastMove, over, thinking, flipped, rewarded, reps, searchId = 0;
      let worker = null;
      try { worker = new Worker('games/chess-engine.js'); } catch { worker = null; }
      const waiting = new Map();
      if (worker) worker.onmessage = e => { const cb = waiting.get(e.data.id); waiting.delete(e.data.id); if (cb) cb(e.data); };

      const human = side => cfg.mode === 'pvp' || side === Number(cfg.color);
      function newGame() {
        waiting.clear();
        st = E.initial();
        history = [];
        reps = new Map([[E.posKey(st), 1]]);
        selected = -1; lastMove = null; over = null; thinking = false; rewarded = false;
        flipped = cfg.mode === 'ai' && Number(cfg.color) < 0;
        q('.ch-banner').classList.add('ch-hidden');
        q('.ch-promo').classList.add('ch-hidden');
        refresh();
        maybeAi();
      }
      function refresh() {
        legalMoves = over ? [] : E.legal(st);
        render();
      }

      // ---------- rendering ----------
      function render() {
        const theme = THEMES[cfg.theme] || THEMES.wood;
        boardEl.style.setProperty('--light', theme[0]);
        boardEl.style.setProperty('--dark', theme[1]);
        const checkSq = !over && E.inCheck(st, st.side) ? E.kingSq(st.b, st.side) : -1;
        const targets = new Map();
        if (selected >= 0) for (const m of legalMoves) if (m.f === selected) targets.set(m.t, m);
        let html = '';
        for (let row = 0; row < 8; row++) {
          for (let col = 0; col < 8; col++) {
            const rank = flipped ? row : 7 - row, file = flipped ? 7 - col : col;
            const s = E.sq(file, rank);
            const p = st.b[s];
            const cls = ['ch-sq', (rank + file) % 2 ? 'l' : 'd'];
            if (s === selected) cls.push('sel');
            if (lastMove && (s === lastMove.f || s === lastMove.t)) cls.push('last');
            if (s === checkSq) cls.push('check');
            if (targets.has(s)) cls.push(p ? 'cap' : 'dot');
            const coordF = row === 7 ? `<span class="ch-cf">${'abcdefgh'[file]}</span>` : '';
            const coordR = col === 0 ? `<span class="ch-cr">${rank + 1}</span>` : '';
            html += `<div class="${cls.join(' ')}" data-s="${s}">${coordF}${coordR}${p ? `<div class="ch-pc${human(Math.sign(p)) && Math.sign(p) === st.side && !over ? ' mine' : ''}">${pieceSvg(p)}</div>` : ''}</div>`;
          }
        }
        boardEl.innerHTML = html;
        renderSide();
      }
      function renderSide() {
        for (const seg of root.querySelectorAll('.ch-seg')) {
          const k = seg.dataset.k;
          seg.classList.toggle('ch-disabled', cfg.mode === 'pvp' && (k === 'color' || k === 'level'));
          seg.querySelectorAll('button').forEach(b => b.classList.toggle('on', String(cfg[k]) === b.dataset.v));
        }
        const who = st.side > 0 ? '白方' : '黑方';
        let status;
        if (over) status = `<b>${over.text}</b>`;
        else if (thinking) status = `<span class="ch-dot ${st.side > 0 ? 'w' : 'b'}"></span>电脑思考中…`;
        else status = `<span class="ch-dot ${st.side > 0 ? 'w' : 'b'}"></span>${cfg.mode === 'ai' ? (human(st.side) ? '轮到你走棋' : '电脑走棋') : `轮到${who}`}${E.inCheck(st, st.side) ? ' · <em>将军！</em>' : ''}`;
        q('.ch-status').innerHTML = status;
        // captured pieces
        const count = { 1: {}, '-1': {} };
        for (const h of history) if (h.u.cap) { const c = h.u.cap; (count[Math.sign(c)][Math.abs(c)] = (count[Math.sign(c)][Math.abs(c)] || 0) + 1); }
        const capHtml = side => [5, 4, 3, 2, 1].map(t => Array(count[side][t] || 0).fill(`<span>${pieceSvg(t * side)}</span>`).join('')).join('');
        q('.ch-cap-w').innerHTML = capHtml(-1);
        q('.ch-cap-b').innerHTML = capHtml(1);
        const ol = q('.ch-moves');
        ol.innerHTML = '';
        for (let i = 0; i < history.length; i += 2) {
          const li = document.createElement('li');
          li.innerHTML = `<span>${history[i].san}</span><span>${history[i + 1] ? history[i + 1].san : ''}</span>`;
          ol.appendChild(li);
        }
        ol.scrollTop = ol.scrollHeight;
        q('[data-a=undo]').disabled = !history.length || thinking;
        const s = ctx.store.get('stats', {})[cfg.level] || { w: 0, l: 0, d: 0 };
        q('.ch-stats').textContent = cfg.mode === 'ai' ? `${LEVELS[cfg.level].label}战绩：${s.w} 胜 ${s.l} 负 ${s.d} 和` : '双人对战';
      }

      // ---------- flow ----------
      function play(m) {
        const text = E.san(st, m);
        const u = E.make(st, m);
        history.push({ u, san: text });
        lastMove = m;
        selected = -1;
        const k = E.posKey(st);
        reps.set(k, (reps.get(k) || 0) + 1);
        checkEnd(k);
        refresh();
        if (!over) maybeAi();
      }
      function checkEnd(k) {
        const moves = E.legal(st);
        if (!moves.length) {
          if (E.inCheck(st, st.side)) return finish(-st.side, `${st.side > 0 ? '黑方' : '白方'}胜 · 将死`);
          return finish(0, '和棋 · 逼和');
        }
        if (reps.get(k) >= 3) return finish(0, '和棋 · 三次重复');
        if (st.half >= 100) return finish(0, '和棋 · 50 回合规则');
        if (E.insufficient(st)) return finish(0, '和棋 · 子力不足');
      }
      function finish(winner, text) {
        over = { winner, text };
        const bn = q('.ch-banner');
        bn.textContent = text;
        bn.classList.remove('ch-hidden');
        if (cfg.mode !== 'ai') return;
        const stats = ctx.store.get('stats', {});
        const s = stats[cfg.level] || (stats[cfg.level] = { w: 0, l: 0, d: 0 });
        if (!winner) s.d++;
        else if (winner === Number(cfg.color)) {
          s.w++;
          ctx.say('国际象棋赢啦！');
          if (!rewarded) { rewarded = true; ctx.reward(LEVELS[cfg.level].reward, '国际象棋胜利'); }
        } else { s.l++; ctx.say(TEASE[Math.floor(Math.random() * TEASE.length)]); }
        ctx.store.set('stats', stats);
      }
      function maybeAi() {
        if (over || human(st.side)) return;
        thinking = true;
        renderSide();
        const id = ++searchId, mySide = st.side;
        const done = r => {
          if (!inst || id !== searchId || over || st.side !== mySide) return;
          thinking = false;
          const m = legalMoves.find(x => r.move && x.f === r.move.f && x.t === r.move.t && x.p === r.move.p) || legalMoves[0];
          play(m);
        };
        if (worker) {
          waiting.set(id, done);
          worker.postMessage({ id, st: { b: Array.from(st.b), side: st.side, castle: st.castle, ep: st.ep, half: st.half, full: st.full }, level: cfg.level });
        } else setTimeout(() => done(E.search(st, cfg.level)), 30);
      }
      function undo() {
        if (!history.length) return;
        waiting.clear(); searchId++;
        thinking = false;
        const pop = () => {
          const h = history.pop();
          const k = E.posKey(st);
          reps.set(k, (reps.get(k) || 1) - 1);
          E.unmake(st, h.u);
        };
        pop();
        if (cfg.mode === 'ai' && !human(st.side) && history.length) pop();
        lastMove = history.length ? history[history.length - 1].u.m : null;
        over = null; selected = -1;
        q('.ch-banner').classList.add('ch-hidden');
        refresh();
        maybeAi();
      }
      function askPromotion(moves) {
        const box = q('.ch-promo');
        box.innerHTML = [5, 4, 3, 2].map(t => `<button data-p="${t}">${pieceSvg(t * st.side)}</button>`).join('');
        box.classList.remove('ch-hidden');
        box.onclick = e => {
          const b = e.target.closest('button');
          if (!b) return;
          box.classList.add('ch-hidden');
          play(moves.find(m => m.p === Number(b.dataset.p)));
        };
      }

      // ---------- input ----------
      const onBoard = e => {
        const cell = e.target.closest('.ch-sq');
        if (!cell || over || thinking || !human(st.side) || !q('.ch-promo').classList.contains('ch-hidden')) return;
        const s = Number(cell.dataset.s);
        const moves = legalMoves.filter(m => m.f === selected && m.t === s);
        if (moves.length) return moves.length > 1 ? askPromotion(moves) : play(moves[0]);
        selected = st.b[s] * st.side > 0 && legalMoves.some(m => m.f === s) ? s : -1;
        render();
      };
      boardEl.addEventListener('click', onBoard);
      const onSide = e => {
        const b = e.target.closest('button');
        if (!b || b.disabled) return;
        if (b.dataset.a === 'new') return newGame();
        if (b.dataset.a === 'undo') return undo();
        if (b.dataset.a === 'flip') { flipped = !flipped; return render(); }
        const seg = b.closest('.ch-seg');
        if (!seg || seg.classList.contains('ch-disabled')) return;
        const k = seg.dataset.k;
        cfg[k] = k === 'color' ? Number(b.dataset.v) : b.dataset.v;
        ctx.store.set('cfg', cfg);
        if (k === 'theme') return render();
        if (history.length) ctx.toast('设置已更改，开始新的一局');
        newGame();
      };
      q('.ch-side').addEventListener('click', onSide);

      inst = {
        dispose() {
          waiting.clear();
          if (worker) worker.terminate();
          boardEl.removeEventListener('click', onBoard);
          q('.ch-side').removeEventListener('click', onSide);
          root.remove();
        }
      };
      newGame();
    },
    unmount() { if (inst) { inst.dispose(); inst = null; } }
  });
})();
