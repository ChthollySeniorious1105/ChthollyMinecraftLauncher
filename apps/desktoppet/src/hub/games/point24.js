// 24 点 — combine four cards with + − × ÷ to make 24. See ../MODULES.md for the contract.
(function () {
  const TIME = 60;
  const SUITS = [['♠', '#2a2a2a'], ['♥', '#d8323c'], ['♣', '#2a2a2a'], ['♦', '#d8323c']];
  const FACE = { 1: 'A', 11: 'J', 12: 'Q', 13: 'K' };
  const OPS = [['+', '+'], ['-', '−'], ['*', '×'], ['/', '÷']];
  let cleanup = null;

  // ---------- exact rationals ----------
  const gcd = (a, b) => { a = Math.abs(a); b = Math.abs(b); while (b) [a, b] = [b, a % b]; return a || 1; };
  const R = (n, d = 1) => { if (d < 0) { n = -n; d = -d; } const g = gcd(n, d); return { n: n / g, d: d / g }; };
  function apply(a, op, b) {
    if (op === '+') return R(a.n * b.d + b.n * a.d, a.d * b.d);
    if (op === '-') return R(a.n * b.d - b.n * a.d, a.d * b.d);
    if (op === '*') return R(a.n * b.n, a.d * b.d);
    if (!b.n) return null;
    return R(a.n * b.d, a.d * b.n);
  }
  const is24 = r => r.n === 24 && r.d === 1;
  const fmt = r => (r.d === 1 ? String(r.n) : `${r.n}/${r.d}`);

  // items: [{ v: rational, e: expression string, p: precedence }]; returns list of steps or null
  function solve(items) {
    if (items.length === 1) return is24(items[0].v) ? [] : null;
    for (let i = 0; i < items.length; i++) for (let j = 0; j < items.length; j++) {
      if (i === j) continue;
      const rest = items.filter((_, k) => k !== i && k !== j);
      for (const [op, sym] of OPS) {
        if ((op === '+' || op === '*') && j < i) continue;   // commutative: try one order only
        const v = apply(items[i].v, op, items[j].v);
        if (!v) continue;
        const prec = op === '+' || op === '-' ? 1 : 2;
        const wrap = (it, right) => (it.p < prec || (right && it.p === prec && (op === '-' || op === '/')) ? `(${it.e})` : it.e);
        const e = `${wrap(items[i], false)} ${sym} ${wrap(items[j], true)}`;
        const sub = solve([...rest, { v, e, p: prec }]);
        if (sub) return [{ a: items[i], b: items[j], op, v, e }, ...sub];
      }
    }
    return null;
  }
  const solveNums = nums => solve(nums.map(n => ({ v: R(n), e: String(n), p: 3 })));
  function deal() {
    for (;;) {
      const nums = Array.from({ length: 4 }, () => 1 + ((Math.random() * 13) | 0));
      const s = solveNums(nums);
      if (s) return { nums, suits: nums.map(() => (Math.random() * 4) | 0), solution: s };
    }
  }

  function cardSvg(n, suit) {
    const [s, col] = SUITS[suit];
    const label = FACE[n] || String(n);
    const pips = n <= 10 && n > 1 ? Math.min(n, 10) : 0;
    const PIP_POS = {
      2: [[50, 30], [50, 110]], 3: [[50, 28], [50, 70], [50, 112]], 4: [[32, 32], [68, 32], [32, 108], [68, 108]],
      5: [[32, 32], [68, 32], [50, 70], [32, 108], [68, 108]], 6: [[32, 30], [68, 30], [32, 70], [68, 70], [32, 110], [68, 110]],
      7: [[32, 30], [68, 30], [50, 50], [32, 70], [68, 70], [32, 110], [68, 110]],
      8: [[32, 28], [68, 28], [50, 48], [32, 68], [68, 68], [50, 90], [32, 112], [68, 112]],
      9: [[32, 26], [68, 26], [32, 54], [68, 54], [50, 70], [32, 86], [68, 86], [32, 114], [68, 114]],
      10: [[32, 26], [68, 26], [50, 42], [32, 56], [68, 56], [32, 84], [68, 84], [50, 98], [32, 114], [68, 114]]
    };
    const body = pips
      ? PIP_POS[pips].map(([x, y]) => `<text x="${x}" y="${y + 7}" font-size="20" text-anchor="middle" fill="${col}">${s}</text>`).join('')
      : n === 1
        ? `<text x="50" y="86" font-size="54" text-anchor="middle" fill="${col}">${s}</text>`
        : `<rect x="22" y="24" width="56" height="92" rx="6" fill="${col === '#d8323c' ? '#fde8e8' : '#e8ecf4'}" stroke="${col}" stroke-width="1.5"/>
           <text x="50" y="84" font-size="40" font-weight="700" text-anchor="middle" fill="${col}" font-family="Georgia, serif">${label}</text>`;
    return `<svg viewBox="0 0 100 140"><rect x="1" y="1" width="98" height="138" rx="10" fill="#fff" stroke="#d8cbb8" stroke-width="2"/>
      <text x="10" y="24" font-size="18" font-weight="700" fill="${col}" font-family="Georgia, serif">${label}</text><text x="10" y="40" font-size="14" fill="${col}">${s}</text>
      <g transform="rotate(180 50 70)"><text x="10" y="24" font-size="18" font-weight="700" fill="${col}" font-family="Georgia, serif">${label}</text><text x="10" y="40" font-size="14" fill="${col}">${s}</text></g>
      ${body}</svg>`;
  }

  function mount(el, ctx) {
    let mode = ctx.store.get('mode', 'timed') === 'practice' ? 'practice' : 'timed';
    let total = ctx.store.get('total', 0), best = ctx.store.get('best', 0);
    let streak = 0, hand, cards, hist, sel, opSel, peeked, done, left = TIME, timer = 0, nextT = 0;

    const root = document.createElement('div');
    root.className = 'p24-root';
    root.innerHTML = `
      <div class="p24-bar">
        <div class="p24-stats">
          <div class="p24-stat"><span>连续</span><b class="p24-streak">0</b></div>
          <div class="p24-stat"><span>最佳连续</span><b class="p24-best">0</b></div>
          <div class="p24-stat"><span>累计解出</span><b class="p24-total">0</b></div>
        </div>
        <div class="p24-seg"><button data-m="timed">计时模式</button><button data-m="practice">练习模式</button></div>
      </div>
      <div class="p24-timer"><b></b><span></span></div>
      <div class="p24-table"><div class="p24-cards"></div><div class="p24-msg"></div></div>
      <div class="p24-ops">${OPS.map(([op, sym]) => `<button class="p24-op" data-op="${op}">${sym}</button>`).join('')}</div>
      <div class="p24-btns">
        <button class="btn p24-undo">撤销</button><button class="btn p24-reset">重来</button>
        <button class="btn p24-hint">提示</button><button class="btn p24-show">看答案</button><button class="btn primary p24-next">换一组</button>
      </div>
      <div class="p24-help">点一张牌 → 点运算符 → 再点一张牌，两张牌合成结果；最后剩下的一张等于 24 即成功 · 键盘：1-4 选牌，+ - * / 运算，Z 撤销，R 重来，H 提示，N 换一组</div>`;
    el.appendChild(root);
    const q = s => root.querySelector(s);

    function stats() {
      q('.p24-streak').textContent = streak;
      q('.p24-best').textContent = best;
      q('.p24-total').textContent = total;
      root.querySelectorAll('.p24-seg button').forEach(b => b.classList.toggle('on', b.dataset.m === mode));
      q('.p24-timer').style.visibility = mode === 'timed' ? '' : 'hidden';
    }
    function msg(t, cls) { const m = q('.p24-msg'); m.textContent = t; m.className = 'p24-msg' + (cls ? ' ' + cls : ''); }
    function newHand() {
      clearTimeout(nextT);
      hand = deal();
      cards = hand.nums.map((n, i) => ({ id: i, v: R(n), e: String(n), p: 3, n, suit: hand.suits[i], orig: true }));
      hist = []; sel = null; opSel = null; peeked = false; done = false; left = TIME;
      msg('');
      render(true);
      tickTimer();
    }
    function render(dealt) {
      const box = q('.p24-cards');
      box.innerHTML = '';
      cards.forEach((c, i) => {
        const b = document.createElement('button');
        b.className = 'p24-card' + (c.orig ? '' : ' made') + (sel === c ? ' sel' : '') + (dealt ? ' deal' : '');
        if (dealt) b.style.animationDelay = `${i * 70}ms`;
        b.innerHTML = c.orig ? cardSvg(c.n, c.suit) : `<div class="p24-made"><b>${fmt(c.v)}</b><span>${c.e}</span></div>`;
        if (done && cards.length === 1) b.classList.add(is24(c.v) ? 'win' : 'lose');
        b.onclick = () => pickCard(c);
        box.appendChild(b);
      });
      root.querySelectorAll('.p24-op').forEach(b => b.classList.toggle('on', b.dataset.op === opSel));
      q('.p24-undo').disabled = !hist.length || done;
    }
    function pickCard(c) {
      if (done) return;
      if (!sel || (sel === c && !opSel)) { sel = sel === c ? null : c; render(); return; }
      if (!opSel) { sel = c; render(); return; }
      if (c === sel) return;
      const v = apply(sel.v, opSel, c.v);
      if (!v) { msg('不能除以 0 哦', 'bad'); return; }
      const prec = opSel === '+' || opSel === '-' ? 1 : 2;
      const sym = OPS.find(o => o[0] === opSel)[1];
      const wrap = (it, right) => (it.p < prec || (right && it.p === prec && (opSel === '-' || opSel === '/')) ? `(${it.e})` : it.e);
      const merged = { id: Math.random(), v, e: `${wrap(sel, false)} ${sym} ${wrap(c, true)}`, p: prec };
      hist.push(cards);
      const at = cards.indexOf(c);
      cards = cards.filter(x => x !== sel && x !== c);
      cards.splice(Math.min(at, cards.length), 0, merged);
      sel = merged; opSel = null;
      if (cards.length === 1) check();
      render();
    }
    function pickOp(op) { if (done || !sel) return; opSel = opSel === op ? null : op; render(); }
    function check() {
      done = true; sel = null;
      clearInterval(timer);
      const c = cards[0];
      if (is24(c.v)) {
        total++; ctx.store.set('total', total);
        const rewarded = mode === 'timed' && !peeked;
        if (rewarded) {
          streak++;
          if (streak > best) { best = streak; ctx.store.set('best', best); if (best >= 3) ctx.say(`24 点连续解出 ${best} 组，新纪录！`); }
          const coins = Math.min(3, 2 + (streak % 5 === 0 ? 1 : 0));
          ctx.reward(coins, streak % 10 === 0 ? '24 点连胜' : '24 点胜利');
          msg(`= 24 ✔  ${c.e}　+${coins} 小鱼干`, 'good');
        } else msg(`= 24 ✔  ${c.e}${peeked ? '（看过答案，不计连胜）' : ''}`, 'good');
        nextT = setTimeout(newHand, 1800);
      } else {
        msg(`= ${fmt(c.v)}，不是 24，撤销再试试`, 'bad');
        done = false;     // let them undo
      }
      stats();
    }
    function undo() { if (!hist.length) return; cards = hist.pop(); sel = null; opSel = null; done = false; msg(''); render(); tickTimer(true); }
    function reset() { if (!hist.length) return; cards = hist[0]; hist = []; sel = null; opSel = null; done = false; msg(''); render(); tickTimer(true); }
    function hint() {
      if (done) return;
      // solve from the current cards; if the player went down a dead end, say so
      const s = solve(cards.map(c => ({ ...c })));
      peeked = true;
      if (!s) { msg('现在这几张凑不出 24 了，撤销一步试试', 'bad'); return; }
      if (!s.length) return;
      const st = s[0];
      msg(`提示：先算 ${st.e} = ${fmt(st.v)}`);
    }
    function show() {
      peeked = true;
      const last = hand.solution[hand.solution.length - 1];
      msg(`答案：${last.e} = 24`);
      if (mode === 'timed') { streak = 0; stats(); }
    }
    function tickTimer(keep) {
      clearInterval(timer);
      const t = q('.p24-timer');
      if (mode !== 'timed') return;
      const draw = () => { t.querySelector('b').style.width = `${left / TIME * 100}%`; t.querySelector('span').textContent = `${left} 秒`; t.classList.toggle('low', left <= 10); };
      if (!keep) left = TIME;
      draw();
      timer = setInterval(() => {
        if (!ctx.isActive() || done) return;
        left--;
        draw();
        if (left <= 0) {
          clearInterval(timer);
          done = true;
          streak = 0; stats();
          const last = hand.solution[hand.solution.length - 1];
          msg(`时间到！参考答案：${last.e}`, 'bad');
          nextT = setTimeout(newHand, 2600);
        }
      }, 1000);
    }

    root.querySelectorAll('.p24-op').forEach(b => b.onclick = () => pickOp(b.dataset.op));
    root.querySelectorAll('.p24-seg button').forEach(b => b.onclick = () => { mode = b.dataset.m; ctx.store.set('mode', mode); streak = 0; stats(); newHand(); });
    q('.p24-undo').onclick = undo;
    q('.p24-reset').onclick = reset;
    q('.p24-hint').onclick = hint;
    q('.p24-show').onclick = show;
    q('.p24-next').onclick = () => { if (mode === 'timed' && !done) streak = 0; stats(); newHand(); };

    function onKey(e) {
      if (!ctx.isActive() || e.ctrlKey || e.metaKey || e.altKey) return;
      const t = e.target && e.target.tagName;
      if (t === 'INPUT' || t === 'TEXTAREA') return;
      const k = e.key;
      if (k >= '1' && k <= '4') { const c = cards[+k - 1]; if (c) pickCard(c); }
      else if ('+-*/'.includes(k)) pickOp(k);
      else if (k === 'x' || k === 'X') pickOp('*');
      else if (k === 'z' || k === 'Z' || k === 'Backspace') undo();
      else if (k === 'r' || k === 'R') reset();
      else if (k === 'h' || k === 'H') hint();
      else if (k === 'n' || k === 'N') q('.p24-next').click();
      else return;
      e.preventDefault();
    }
    window.addEventListener('keydown', onKey);
    cleanup = () => { clearInterval(timer); clearTimeout(nextT); window.removeEventListener('keydown', onKey); };

    stats();
    newHand();
  }

  Hub.register({
    id: 'point24', title: '24 点', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="5" width="11" height="15" rx="2"/><path d="M9 3.5h8a2 2 0 0 1 2 2V17"/><path d="M6 10.5a2 2 0 1 1 3.4 1.4L6 15.5h4" stroke-linecap="round"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
