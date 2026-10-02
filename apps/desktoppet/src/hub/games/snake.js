// 贪吃蛇 — Snake game module for the hub. See ../MODULES.md for the contract.
(function () {
  const COLS = 24, ROWS = 20, CELL = 22;
  const W = COLS * CELL, H = ROWS * CELL;
  const SPEEDS = { slow: { label: '慢', ms: 150 }, mid: { label: '中', ms: 105 }, fast: { label: '快', ms: 70 } };
  const DIRS = { up: { x: 0, y: -1 }, down: { x: 0, y: 1 }, left: { x: -1, y: 0 }, right: { x: 1, y: 0 } };
  const KEYMAP = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    KeyW: 'up', KeyS: 'down', KeyA: 'left', KeyD: 'right'
  };
  const FOOD_PTS = 1, BONUS_PTS = 5, BONUS_CHANCE = 0.22, BONUS_MS = 6000;

  let cleanup = null;

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'sn-root';
    root.innerHTML = `
      <div class="sn-bar">
        <div class="sn-stats">
          <div class="sn-stat"><span class="sn-lbl">得分</span><b class="sn-score">0</b></div>
          <div class="sn-stat"><span class="sn-lbl">最佳</span><b class="sn-best">0</b></div>
        </div>
        <div class="sn-opts">
          <div class="sn-seg" role="group" aria-label="速度">
            ${Object.keys(SPEEDS).map(k => `<button type="button" data-speed="${k}">${SPEEDS[k].label}</button>`).join('')}
          </div>
          <label class="sn-wrap"><input type="checkbox" class="sn-wrap-cb"><span>穿墙</span></label>
          <button type="button" class="sn-btn sn-toggle">开始</button>
        </div>
      </div>
      <div class="sn-board">
        <canvas class="sn-canvas"></canvas>
        <div class="sn-overlay">
          <div class="sn-card">
            <div class="sn-title"></div>
            <div class="sn-sub"></div>
            <button type="button" class="sn-btn sn-primary sn-ov-btn"></button>
          </div>
        </div>
      </div>
      <div class="sn-help">方向键 / WASD 移动 · 空格 / P 暂停 · 金色果子限时出现，价值 ${BONUS_PTS} 分</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const canvas = $('.sn-canvas');
    const g = canvas.getContext('2d');
    const scoreEl = $('.sn-score'), bestEl = $('.sn-best');
    const overlay = $('.sn-overlay'), ovTitle = $('.sn-title'), ovSub = $('.sn-sub'), ovBtn = $('.sn-ov-btn');
    const toggleBtn = $('.sn-toggle'), wrapCb = $('.sn-wrap-cb');
    const speedBtns = [...root.querySelectorAll('[data-speed]')];

    // ---------- settings ----------
    let speed = ctx.store.get('speed', 'mid');
    if (!SPEEDS[speed]) speed = 'mid';
    let wrap = !!ctx.store.get('wrap', false);
    wrapCb.checked = wrap;

    const bestKey = () => 'best_' + speed;
    const getBest = () => ctx.store.get(bestKey(), 0) || 0;

    // ---------- state ----------
    let snake, dir, queue, food, bonus, score, state, ticks, dirty = true;
    // state: 'ready' | 'running' | 'paused' | 'over'

    function reset() {
      const cy = Math.floor(ROWS / 2), cx = 6;
      snake = [{ x: cx, y: cy }, { x: cx - 1, y: cy }, { x: cx - 2, y: cy }];
      dir = 'right';
      queue = [];
      score = 0;
      ticks = 0;
      bonus = null;
      food = randomFree();
      state = 'ready';
      updateHud();
      showOverlay();
      dirty = true;
    }

    function occupied(x, y) {
      if (snake.some(s => s.x === x && s.y === y)) return true;
      if (food && food.x === x && food.y === y) return true;
      if (bonus && bonus.x === x && bonus.y === y) return true;
      return false;
    }

    function randomFree() {
      const free = [];
      for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) if (!occupied(x, y)) free.push({ x, y });
      return free.length ? free[(Math.random() * free.length) | 0] : null;
    }

    function updateHud() {
      scoreEl.textContent = score;
      bestEl.textContent = getBest();
      speedBtns.forEach(b => b.classList.toggle('active', b.dataset.speed === speed));
      toggleBtn.textContent = state === 'running' ? '暂停' : state === 'paused' ? '继续' : state === 'over' ? '再来一局' : '开始';
    }

    function showOverlay(extra) {
      if (state === 'running') { overlay.classList.add('hidden'); return; }
      overlay.classList.remove('hidden');
      if (state === 'ready') {
        ovTitle.textContent = '贪吃蛇';
        ovSub.textContent = `速度：${SPEEDS[speed].label} · ${wrap ? '可穿墙' : '撞墙结束'}`;
        ovBtn.textContent = '开始游戏';
      } else if (state === 'paused') {
        ovTitle.textContent = '已暂停';
        ovSub.textContent = '按 空格 / P 继续';
        ovBtn.textContent = '继续';
      } else if (state === 'over') {
        ovTitle.textContent = extra && extra.win ? '全部吃满啦！' : '游戏结束';
        ovSub.textContent = `得分 ${score}` + (extra && extra.newBest ? ' · 新纪录！' : ` · 最佳 ${getBest()}`);
        ovBtn.textContent = '再来一局';
      }
    }

    function setState(s, extra) {
      state = s;
      if (s === 'running') acc = 0;
      updateHud();
      showOverlay(extra);
      dirty = true;
    }

    function primaryAction() {
      if (state === 'ready') setState('running');
      else if (state === 'running') setState('paused');
      else if (state === 'paused') setState('running');
      else if (state === 'over') { reset(); setState('running'); }
    }

    function enqueue(d) {
      const last = queue.length ? queue[queue.length - 1] : dir;
      const a = DIRS[last], b = DIRS[d];
      if (d === last || (a.x + b.x === 0 && a.y + b.y === 0)) return;
      if (queue.length < 2) queue.push(d);
    }

    // ---------- game logic ----------
    function tick() {
      ticks++;
      if (queue.length) dir = queue.shift();
      const d = DIRS[dir];
      const head = snake[0];
      let nx = head.x + d.x, ny = head.y + d.y;
      if (wrap) {
        nx = (nx + COLS) % COLS;
        ny = (ny + ROWS) % ROWS;
      } else if (nx < 0 || ny < 0 || nx >= COLS || ny >= ROWS) {
        return gameOver(false);
      }
      const eatsFood = food && food.x === nx && food.y === ny;
      const eatsBonus = bonus && bonus.x === nx && bonus.y === ny;
      const grows = eatsFood;
      // tail moves away this tick unless growing
      const body = grows ? snake : snake.slice(0, -1);
      if (body.some(s => s.x === nx && s.y === ny)) return gameOver(false);

      snake.unshift({ x: nx, y: ny });
      if (!grows) snake.pop();

      if (eatsBonus) {
        score += BONUS_PTS;
        bonus = null;
        ctx.toast && ctx.toast('金色果子 +' + BONUS_PTS);
      }
      if (eatsFood) {
        score += FOOD_PTS;
        food = null;
        food = randomFree();
        if (!food) return gameOver(true);
        if (!bonus && Math.random() < BONUS_CHANCE) {
          const p = randomFree();
          if (p) {
            const life = Math.round(BONUS_MS / SPEEDS[speed].ms);
            bonus = { x: p.x, y: p.y, born: ticks, life };
          }
        }
      }
      if (bonus && ticks - bonus.born >= bonus.life) bonus = null;
      if (eatsFood || eatsBonus) updateHud();
      dirty = true;
    }

    function gameOver(win) {
      if (ctx.reward && score >= 10) ctx.reward(Math.min(15, Math.floor(score / 10)), '贪吃蛇结算');
      const old = getBest();
      const newBest = score > old && score > 0;
      if (newBest) {
        ctx.store.set(bestKey(), score);
        ctx.say('贪吃蛇新纪录！' + score);
      }
      setState('over', { win, newBest });
    }

    // ---------- rendering ----------
    let dpr = 0;
    function setupCanvas() {
      const r = window.devicePixelRatio || 1;
      if (r === dpr) return;
      dpr = r;
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      canvas.style.width = W + 'px';
      canvas.style.height = H + 'px';
      dirty = true;
    }

    const cx = c => c * CELL + CELL / 2;

    function drawBoard() {
      g.fillStyle = '#fffaf2';
      g.fillRect(0, 0, W, H);
      g.fillStyle = '#f8eedf';
      for (let y = 0; y < ROWS; y++)
        for (let x = (y & 1); x < COLS; x += 2) g.fillRect(x * CELL, y * CELL, CELL, CELL);
    }

    function drawApple(x, y) {
      const px = cx(x), py = cx(y) + 1;
      const r = CELL * 0.36;
      // shadow
      g.fillStyle = 'rgba(107,63,36,0.12)';
      g.beginPath(); g.ellipse(px, py + r * 0.95, r * 0.8, r * 0.25, 0, 0, Math.PI * 2); g.fill();
      // body (two lobes)
      g.fillStyle = '#e5484d';
      g.beginPath();
      g.arc(px - r * 0.35, py, r * 0.75, 0, Math.PI * 2);
      g.arc(px + r * 0.35, py, r * 0.75, 0, Math.PI * 2);
      g.fill();
      g.beginPath(); g.ellipse(px, py + r * 0.2, r * 0.95, r * 0.7, 0, 0, Math.PI * 2); g.fill();
      // highlight
      g.fillStyle = 'rgba(255,255,255,0.55)';
      g.beginPath(); g.ellipse(px - r * 0.45, py - r * 0.25, r * 0.18, r * 0.28, -0.5, 0, Math.PI * 2); g.fill();
      // stem
      g.strokeStyle = '#6b3f24'; g.lineWidth = 2; g.lineCap = 'round';
      g.beginPath(); g.moveTo(px, py - r * 0.55); g.quadraticCurveTo(px + 1, py - r * 1.05, px + 3, py - r * 1.2); g.stroke();
      // leaf
      g.fillStyle = '#6cbf5a';
      g.beginPath();
      g.ellipse(px + r * 0.5, py - r * 0.95, r * 0.42, r * 0.2, -0.5, 0, Math.PI * 2);
      g.fill();
      // cute face
      g.fillStyle = '#4a3426';
      g.beginPath(); g.arc(px - r * 0.3, py + r * 0.1, 1.3, 0, Math.PI * 2); g.arc(px + r * 0.3, py + r * 0.1, 1.3, 0, Math.PI * 2); g.fill();
      g.strokeStyle = '#4a3426'; g.lineWidth = 1;
      g.beginPath(); g.arc(px, py + r * 0.28, r * 0.14, 0.15 * Math.PI, 0.85 * Math.PI); g.stroke();
    }

    function drawBonus(now) {
      if (!bonus) return;
      const left = bonus.life - (ticks - bonus.born);
      const remainMs = left * SPEEDS[speed].ms;
      if (remainMs < 2000 && Math.floor(now / 150) % 2 === 0) return; // blink before expiring
      const px = cx(bonus.x), py = cx(bonus.y);
      const pulse = 1 + Math.sin(now / 160) * 0.08;
      const r = CELL * 0.4 * pulse;
      // timer ring
      g.strokeStyle = 'rgba(232,121,58,0.45)'; g.lineWidth = 2;
      g.beginPath(); g.arc(px, py, CELL * 0.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0, left / bonus.life)); g.stroke();
      // star
      const grad = g.createRadialGradient(px - r * 0.3, py - r * 0.3, 1, px, py, r);
      grad.addColorStop(0, '#fff3b0'); grad.addColorStop(1, '#f2b705');
      g.fillStyle = grad;
      g.strokeStyle = '#c98a00'; g.lineWidth = 1.2;
      g.beginPath();
      for (let i = 0; i < 10; i++) {
        const a = -Math.PI / 2 + i * Math.PI / 5;
        const rr = i % 2 ? r * 0.48 : r;
        g.lineTo(px + Math.cos(a) * rr, py + Math.sin(a) * rr);
      }
      g.closePath(); g.fill(); g.stroke();
    }

    function lerpColor(a, b, t) {
      const r = Math.round(a[0] + (b[0] - a[0]) * t);
      const gg = Math.round(a[1] + (b[1] - a[1]) * t);
      const bb = Math.round(a[2] + (b[2] - a[2]) * t);
      return `rgb(${r},${gg},${bb})`;
    }

    function drawSnake() {
      const n = snake.length;
      const HEAD = [232, 121, 58], TAIL = [246, 196, 120];
      g.lineCap = 'round'; g.lineJoin = 'round';
      // outline pass then fill pass
      for (let pass = 0; pass < 2; pass++) {
        for (let i = n - 1; i > 0; i--) {
          const a = snake[i], b = snake[i - 1];
          const wrapped = Math.abs(a.x - b.x) + Math.abs(a.y - b.y) > 1;
          const t = i / Math.max(1, n - 1);
          const w = CELL * (0.78 - 0.18 * t);
          g.strokeStyle = pass === 0 ? '#b8561f' : lerpColor(HEAD, TAIL, t);
          g.lineWidth = pass === 0 ? w + 3 : w;
          g.beginPath();
          if (wrapped) {
            g.moveTo(cx(a.x), cx(a.y)); g.lineTo(cx(a.x), cx(a.y));
            g.stroke();
            g.beginPath(); g.moveTo(cx(b.x), cx(b.y)); g.lineTo(cx(b.x), cx(b.y));
          } else {
            g.moveTo(cx(a.x), cx(a.y)); g.lineTo(cx(b.x), cx(b.y));
          }
          g.stroke();
        }
        // head
        const h = snake[0];
        g.fillStyle = pass === 0 ? '#b8561f' : '#e8793a';
        g.beginPath(); g.arc(cx(h.x), cx(h.y), CELL * 0.45 + (pass === 0 ? 1.5 : 0), 0, Math.PI * 2); g.fill();
      }
      // belly spots
      g.fillStyle = 'rgba(255,250,242,0.35)';
      for (let i = 2; i < n; i += 3) {
        const s = snake[i];
        g.beginPath(); g.arc(cx(s.x), cx(s.y), CELL * 0.12, 0, Math.PI * 2); g.fill();
      }
      // eyes
      const h = snake[0];
      const face = DIRS[dir];
      const px = cx(h.x), py = cx(h.y);
      const fx = face.x, fy = face.y;           // forward
      const sx = -fy, sy = fx;                  // side
      const dead = state === 'over';
      for (const side of [-1, 1]) {
        const ex = px + fx * CELL * 0.14 + sx * side * CELL * 0.2;
        const ey = py + fy * CELL * 0.14 + sy * side * CELL * 0.2;
        if (dead) {
          g.strokeStyle = '#4a3426'; g.lineWidth = 1.6; g.lineCap = 'round';
          const k = CELL * 0.09;
          g.beginPath(); g.moveTo(ex - k, ey - k); g.lineTo(ex + k, ey + k); g.moveTo(ex + k, ey - k); g.lineTo(ex - k, ey + k); g.stroke();
        } else {
          g.fillStyle = '#fff';
          g.beginPath(); g.arc(ex, ey, CELL * 0.13, 0, Math.PI * 2); g.fill();
          g.fillStyle = '#4a3426';
          g.beginPath(); g.arc(ex + fx * CELL * 0.045, ey + fy * CELL * 0.045, CELL * 0.07, 0, Math.PI * 2); g.fill();
          g.fillStyle = '#fff';
          g.beginPath(); g.arc(ex + fx * CELL * 0.02 - 1, ey + fy * CELL * 0.02 - 1, 1, 0, Math.PI * 2); g.fill();
        }
      }
      // blush
      g.fillStyle = 'rgba(229,72,77,0.35)';
      for (const side of [-1, 1]) {
        g.beginPath();
        g.arc(px - fx * CELL * 0.08 + sx * side * CELL * 0.3, py - fy * CELL * 0.08 + sy * side * CELL * 0.3, CELL * 0.07, 0, Math.PI * 2);
        g.fill();
      }
    }

    function render(now) {
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      drawBoard();
      if (food) drawApple(food.x, food.y);
      drawBonus(now);
      drawSnake();
    }

    // ---------- loop ----------
    let raf = 0, last = 0, acc = 0;
    function frame(now) {
      raf = requestAnimationFrame(frame);
      setupCanvas();
      const dt = last ? Math.min(now - last, 250) : 0;
      last = now;
      if (state === 'running') {
        if (!ctx.isActive()) {
          setState('paused');
        } else {
          acc += dt;
          const step = SPEEDS[speed].ms;
          while (acc >= step && state === 'running') { acc -= step; tick(); }
        }
      }
      if (dirty || bonus) {
        dirty = false;
        render(now);
      }
    }

    // ---------- input ----------
    function onKey(e) {
      if (!ctx.isActive()) return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' && t.type !== 'checkbox' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      const d = KEYMAP[e.code];
      if (d) {
        e.preventDefault();
        if (state === 'ready') setState('running');
        if (state === 'running') enqueue(d);
        return;
      }
      if (e.code === 'Space' || e.code === 'KeyP' || (e.code === 'Enter' && state !== 'running')) {
        e.preventDefault();
        if (e.repeat) return;
        if (document.activeElement && root.contains(document.activeElement)) document.activeElement.blur();
        primaryAction();
      }
    }

    function onSpeed(e) {
      const k = e.currentTarget.dataset.speed;
      if (k === speed) return;
      speed = k;
      ctx.store.set('speed', speed);
      reset();
      e.currentTarget.blur();
    }
    function onWrap() {
      wrap = wrapCb.checked;
      ctx.store.set('wrap', wrap);
      reset();
      wrapCb.blur();
    }
    function onToggle(e) { e.currentTarget.blur(); primaryAction(); }

    speedBtns.forEach(b => b.addEventListener('click', onSpeed));
    wrapCb.addEventListener('change', onWrap);
    toggleBtn.addEventListener('click', onToggle);
    ovBtn.addEventListener('click', onToggle);
    window.addEventListener('keydown', onKey);

    reset();
    setupCanvas();
    raf = requestAnimationFrame(frame);

    cleanup = () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('keydown', onKey);
      speedBtns.forEach(b => b.removeEventListener('click', onSpeed));
      wrapCb.removeEventListener('change', onWrap);
      toggleBtn.removeEventListener('click', onToggle);
      ovBtn.removeEventListener('click', onToggle);
      root.remove();
    };
  }

  Hub.register({
    id: 'snake',
    title: '贪吃蛇',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 18h9a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h8"/><circle cx="19" cy="6" r="2" fill="currentColor" stroke="none"/><circle cx="6" cy="10" r="1.2" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
