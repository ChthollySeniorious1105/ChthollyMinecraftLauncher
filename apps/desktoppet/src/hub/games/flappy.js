// 飞翔小鸟 — Flappy-style canvas game module for the hub. See ../MODULES.md for the contract.
(function () {
  const GW = 420, GH = 560;            // logical game size
  const GROUND_H = 64, GROUND_Y = GH - GROUND_H;
  const BIRD_X = 120, BIRD_R = 15;
  const GRAVITY = 1500;                // px/s^2
  const FLAP_V = -440;                 // px/s
  const MAX_FALL = 620;
  const PIPE_W = 64;
  const PIPE_SPEED0 = 150, PIPE_SPEED_MAX = 230;
  const GAP0 = 168, GAP_MIN = 128;
  const SPACING = 210;                 // horizontal distance between pipes
  const MEDALS = [
    { min: 40, name: '白金', color: '#dfe7ee', edge: '#9fb3c4' },
    { min: 25, name: '金牌', color: '#f7c948', edge: '#c98a00' },
    { min: 10, name: '银牌', color: '#d6d9de', edge: '#8d949c' },
    { min: 5,  name: '铜牌', color: '#e0a15a', edge: '#a8662a' }
  ];

  let cleanup = null;

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const medalFor = s => MEDALS.find(m => s >= m.min) || null;

  function roundRect(g, x, y, w, h, r) {
    g.beginPath();
    g.moveTo(x + r, y);
    g.arcTo(x + w, y, x + w, y + h, r);
    g.arcTo(x + w, y + h, x, y + h, r);
    g.arcTo(x, y + h, x, y, r);
    g.arcTo(x, y, x + w, y, r);
    g.closePath();
  }

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'fp-root';
    root.innerHTML = `
      <div class="fp-bar">
        <div class="fp-stats">
          <div class="fp-stat"><span class="fp-lbl">得分</span><b class="fp-score">0</b></div>
          <div class="fp-stat"><span class="fp-lbl">最佳</span><b class="fp-best">0</b></div>
        </div>
        <div class="fp-opts">
          <button type="button" class="fp-btn fp-toggle">开始</button>
        </div>
      </div>
      <div class="fp-stage">
        <canvas class="fp-canvas"></canvas>
        <div class="fp-overlay hidden">
          <div class="fp-card">
            <div class="fp-title"></div>
            <div class="fp-medal"></div>
            <div class="fp-sub"></div>
            <button type="button" class="fp-btn fp-primary fp-ov-btn"></button>
          </div>
        </div>
      </div>
      <div class="fp-help">点击画面 / 空格 / ↑ 振翅 · P 暂停 · 5 分铜牌 · 10 分银牌 · 25 分金牌 · 40 分白金</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.fp-stage'), canvas = $('.fp-canvas');
    const g = canvas.getContext('2d');
    const scoreEl = $('.fp-score'), bestEl = $('.fp-best');
    const overlay = $('.fp-overlay'), ovTitle = $('.fp-title'), ovMedal = $('.fp-medal'), ovSub = $('.fp-sub'), ovBtn = $('.fp-ov-btn');
    const toggleBtn = $('.fp-toggle');

    // ---------- state ----------
    let state = 'ready';     // 'ready' | 'play' | 'paused' | 'dying' | 'over'
    let best = ctx.store.get('best', 0) || 0;
    let bird, pipes, score, speed, distToNext, groundX, cloudX, hillX, flash, deadT, t0 = 0;
    let rewarded = false;
    let scale = 1, dpr = 1, rafId = 0, lastT = 0;
    const clouds = Array.from({ length: 6 }, (_, i) => ({
      x: i * 90 + Math.random() * 40, y: 40 + Math.random() * 150, s: 0.6 + Math.random() * 0.6
    }));

    function reset() {
      bird = { y: GH * 0.42, vy: 0, rot: 0, wing: 0 };
      pipes = [];
      score = 0;
      speed = PIPE_SPEED0;
      distToNext = 140;
      groundX = groundX || 0; cloudX = cloudX || 0; hillX = hillX || 0;
      flash = 0; deadT = 0;
      rewarded = false;
    }

    // ---------- layout ----------
    function fit() {
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(200, stage.clientWidth);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 4);
      const cssW = Math.floor(Math.min(GW * 1.2, aw, ah * GW / GH));
      const cssH = Math.floor(cssW * GH / GW);
      dpr = window.devicePixelRatio || 1;
      canvas.style.width = cssW + 'px';
      canvas.style.height = cssH + 'px';
      canvas.width = Math.round(cssW * dpr);
      canvas.height = Math.round(cssH * dpr);
      scale = cssW / GW;
      draw(performance.now());
    }

    // ---------- HUD / overlay ----------
    function updateHud() {
      scoreEl.textContent = score;
      bestEl.textContent = Math.max(best, score);
      toggleBtn.textContent = state === 'play' ? '暂停' : state === 'paused' ? '继续' : state === 'over' ? '再来一局' : '开始';
      toggleBtn.disabled = state === 'dying';
    }

    function medalSvg(m) {
      if (!m) return '';
      return `<svg viewBox="0 0 60 70" width="54" height="63">
        <path d="M18 2 h10 l6 22 h-10z" fill="#e8793a"/><path d="M42 2 h-10 l-6 22 h10z" fill="#d9652a"/>
        <circle cx="30" cy="42" r="22" fill="${m.color}" stroke="${m.edge}" stroke-width="3"/>
        <circle cx="30" cy="42" r="15" fill="none" stroke="${m.edge}" stroke-width="1.5" stroke-dasharray="3 3"/>
        <path d="M30 31 l3.4 7 7.6 1 -5.5 5.3 1.3 7.6 -6.8 -3.6 -6.8 3.6 1.3 -7.6 -5.5 -5.3 7.6 -1z" fill="#fff" opacity=".9"/>
      </svg><div class="fp-medal-name">${m.name}</div>`;
    }

    function showOverlay(extra) {
      if (state === 'play' || state === 'dying' || state === 'ready') { overlay.classList.add('hidden'); return; }
      overlay.classList.remove('hidden');
      if (state === 'paused') {
        ovTitle.textContent = '已暂停';
        ovMedal.innerHTML = '';
        ovSub.textContent = '按 空格 / P 继续';
        ovBtn.textContent = '继续';
      } else {
        const m = medalFor(score);
        ovTitle.textContent = '游戏结束';
        ovMedal.innerHTML = medalSvg(m);
        ovSub.innerHTML =
          `<div>得分 <b>${score}</b> · 最佳 ${best}</div>` +
          (extra && extra.coins ? `<div>奖励小鱼干 +${extra.coins}</div>` : '') +
          (extra && extra.newBest ? '<div class="fp-rec">新纪录！</div>' : '');
        ovBtn.textContent = '再来一局';
      }
    }

    function setState(s, extra) {
      state = s;
      updateHud();
      showOverlay(extra);
    }

    // ---------- actions ----------
    function flap() {
      if (state === 'ready') { setState('play'); }
      if (state !== 'play') return;
      bird.vy = FLAP_V;
      bird.wing = 1;
    }

    function primary() {
      if (state === 'ready') flap();
      else if (state === 'play') setState('paused');
      else if (state === 'paused') setState('play');
      else if (state === 'over') { reset(); setState('ready'); }
    }

    function die() {
      if (state !== 'play') return;
      flash = 1;
      deadT = 0;
      setState('dying');
    }

    function finish() {
      const newBest = score > best;
      if (newBest) {
        best = score;
        ctx.store.set('best', best);
        ctx.say(`飞翔小鸟新纪录：${score} 分！`);
      }
      let coins = 0;
      if (!rewarded && score > 0) {
        rewarded = true;
        coins = Math.min(15, Math.floor(score / 5));
        if (coins > 0) ctx.reward(coins, '飞翔小鸟');
      }
      setState('over', { newBest, coins });
    }

    // ---------- update ----------
    function spawnPipe() {
      const gap = Math.max(GAP_MIN, GAP0 - score * 1.6);
      const margin = 56;
      const top = margin + Math.random() * (GROUND_Y - margin * 2 - gap);
      pipes.push({ x: GW + 10, top, gap, passed: false });
    }

    function update(dt, now) {
      const scrolling = state === 'ready' || state === 'play';
      if (scrolling) {
        const sp = state === 'ready' ? PIPE_SPEED0 : speed;
        groundX = (groundX + sp * dt) % 24;
        cloudX += sp * 0.12 * dt;
        hillX += sp * 0.35 * dt;
      }
      bird.wing = Math.max(0, bird.wing - dt * 4);

      if (state === 'ready') {
        bird.y = GH * 0.42 + Math.sin(now / 260) * 8;
        bird.rot = 0;
        return;
      }
      if (state === 'play' || state === 'dying') {
        bird.vy = Math.min(MAX_FALL, bird.vy + GRAVITY * dt);
        bird.y += bird.vy * dt;
        const target = clamp(bird.vy / 500, -0.5, 1.4);
        bird.rot += (target - bird.rot) * Math.min(1, dt * (bird.vy < 0 ? 18 : 6));
        if (bird.y < BIRD_R) { bird.y = BIRD_R; if (bird.vy < 0) bird.vy = 0; }
      }
      if (flash > 0) flash = Math.max(0, flash - dt * 3);

      if (state === 'play') {
        speed = Math.min(PIPE_SPEED_MAX, PIPE_SPEED0 + score * 2.5);
        distToNext -= speed * dt;
        if (distToNext <= 0) { spawnPipe(); distToNext += SPACING; }
        for (const p of pipes) {
          p.x -= speed * dt;
          if (!p.passed && p.x + PIPE_W < BIRD_X) {
            p.passed = true;
            score++;
            updateHud();
          }
        }
        pipes = pipes.filter(p => p.x + PIPE_W > -10);
        // collisions (circle vs rect, slightly forgiving)
        const r = BIRD_R - 2;
        if (bird.y + BIRD_R >= GROUND_Y) { bird.y = GROUND_Y - BIRD_R; die(); return; }
        for (const p of pipes) {
          const rects = [[p.x, -100, PIPE_W, p.top + 100], [p.x, p.top + p.gap, PIPE_W, GROUND_Y - p.top - p.gap]];
          for (const [x, y, w, h] of rects) {
            const nx = clamp(BIRD_X, x, x + w), ny = clamp(bird.y, y, y + h);
            const dx = BIRD_X - nx, dy = bird.y - ny;
            if (dx * dx + dy * dy < r * r) { die(); return; }
          }
        }
      } else if (state === 'dying') {
        deadT += dt;
        if (bird.y + BIRD_R >= GROUND_Y) {
          bird.y = GROUND_Y - BIRD_R;
          bird.vy = 0;
          if (deadT > 0.45) finish();
        }
      }
    }

    // ---------- draw ----------
    function drawCloud(x, y, s) {
      g.beginPath();
      g.arc(x, y, 18 * s, 0, Math.PI * 2);
      g.arc(x + 20 * s, y - 10 * s, 22 * s, 0, Math.PI * 2);
      g.arc(x + 44 * s, y, 18 * s, 0, Math.PI * 2);
      g.arc(x + 22 * s, y + 6 * s, 18 * s, 0, Math.PI * 2);
      g.fill();
    }

    function drawPipe(p) {
      const capH = 24, capOver = 5;
      const grad = g.createLinearGradient(p.x, 0, p.x + PIPE_W, 0);
      grad.addColorStop(0, '#6cbf5a'); grad.addColorStop(0.35, '#a6e38f'); grad.addColorStop(1, '#4e9a3f');
      g.lineWidth = 2.5; g.strokeStyle = '#2f6b26';
      // top body
      g.fillStyle = grad;
      g.fillRect(p.x, -4, PIPE_W, p.top - capH + 4);
      g.strokeRect(p.x, -4, PIPE_W, p.top - capH + 4);
      roundRect(g, p.x - capOver, p.top - capH, PIPE_W + capOver * 2, capH, 5);
      g.fill(); g.stroke();
      // bottom body
      const by = p.top + p.gap;
      g.fillRect(p.x, by + capH, PIPE_W, GROUND_Y - by - capH + 2);
      g.strokeRect(p.x, by + capH, PIPE_W, GROUND_Y - by - capH + 2);
      roundRect(g, p.x - capOver, by, PIPE_W + capOver * 2, capH, 5);
      g.fill(); g.stroke();
      // highlights
      g.fillStyle = 'rgba(255,255,255,0.35)';
      g.fillRect(p.x + 8, 0, 5, p.top - capH);
      g.fillRect(p.x + 8, by + capH, 5, GROUND_Y - by - capH);
    }

    function drawBird(now) {
      g.save();
      g.translate(BIRD_X, bird.y);
      g.rotate(bird.rot);
      const dead = state === 'dying' || state === 'over';
      // body
      g.fillStyle = '#f7c948'; g.strokeStyle = '#6b3f24'; g.lineWidth = 2.2;
      g.beginPath(); g.ellipse(0, 0, BIRD_R + 3, BIRD_R, 0, 0, Math.PI * 2); g.fill(); g.stroke();
      // belly
      g.fillStyle = '#fff1c7';
      g.beginPath(); g.ellipse(2, 6, 11, 7, 0, 0, Math.PI * 2); g.fill();
      // wing
      const flapPhase = state === 'ready' ? Math.sin(now / 90) : (bird.wing > 0 ? Math.sin(bird.wing * Math.PI * 3) : -0.3);
      g.fillStyle = '#f0995a'; g.strokeStyle = '#6b3f24'; g.lineWidth = 2;
      g.beginPath(); g.ellipse(-7, 2 - flapPhase * 6, 9, 5.5, -0.3 - flapPhase * 0.5, 0, Math.PI * 2); g.fill(); g.stroke();
      // eye
      if (dead) {
        g.strokeStyle = '#4a3426'; g.lineWidth = 2; g.lineCap = 'round';
        g.beginPath(); g.moveTo(4, -9); g.lineTo(10, -3); g.moveTo(10, -9); g.lineTo(4, -3); g.stroke();
      } else {
        g.fillStyle = '#fff'; g.strokeStyle = '#6b3f24'; g.lineWidth = 1.5;
        g.beginPath(); g.arc(7, -6, 6, 0, Math.PI * 2); g.fill(); g.stroke();
        g.fillStyle = '#4a3426';
        g.beginPath(); g.arc(9, -6, 3, 0, Math.PI * 2); g.fill();
        g.fillStyle = '#fff';
        g.beginPath(); g.arc(9.8, -7, 1, 0, Math.PI * 2); g.fill();
      }
      // blush
      g.fillStyle = 'rgba(229,72,77,0.4)';
      g.beginPath(); g.ellipse(6, 3, 3.5, 2, 0, 0, Math.PI * 2); g.fill();
      // beak
      g.fillStyle = '#e8793a'; g.strokeStyle = '#6b3f24'; g.lineWidth = 1.8; g.lineJoin = 'round';
      g.beginPath(); g.moveTo(13, -2); g.lineTo(24, 1); g.lineTo(13, 5); g.closePath(); g.fill(); g.stroke();
      // tuft
      g.strokeStyle = '#6b3f24'; g.lineWidth = 2; g.lineCap = 'round';
      g.beginPath(); g.moveTo(-2, -BIRD_R); g.quadraticCurveTo(0, -BIRD_R - 8, 5, -BIRD_R - 6); g.stroke();
      g.restore();
    }

    function draw(now) {
      if (!bird) return;
      const k = scale * dpr;
      g.setTransform(k, 0, 0, k, 0, 0);
      // sky
      const sky = g.createLinearGradient(0, 0, 0, GROUND_Y);
      sky.addColorStop(0, '#9fd8f0'); sky.addColorStop(0.7, '#d7f0f5'); sky.addColorStop(1, '#fbf5ea');
      g.fillStyle = sky; g.fillRect(0, 0, GW, GROUND_Y);
      // sun
      g.fillStyle = 'rgba(255,236,170,0.8)';
      g.beginPath(); g.arc(GW - 70, 70, 28, 0, Math.PI * 2); g.fill();
      // clouds (slow parallax)
      g.fillStyle = 'rgba(255,255,255,0.85)';
      const cw = GW + 120;
      for (const c of clouds) {
        const x = ((c.x - cloudX * c.s) % cw + cw) % cw - 80;
        drawCloud(x, c.y, c.s);
      }
      // hills (mid parallax)
      g.fillStyle = '#bfe3a4';
      g.beginPath(); g.moveTo(0, GROUND_Y);
      for (let x = 0; x <= GW; x += 10) {
        const wx = x + hillX;
        g.lineTo(x, GROUND_Y - 36 - Math.sin(wx / 70) * 18 - Math.sin(wx / 31) * 6);
      }
      g.lineTo(GW, GROUND_Y); g.closePath(); g.fill();
      g.fillStyle = '#a3d68a';
      g.beginPath(); g.moveTo(0, GROUND_Y);
      for (let x = 0; x <= GW; x += 10) {
        const wx = x + hillX * 1.6;
        g.lineTo(x, GROUND_Y - 14 - Math.sin(wx / 45 + 1) * 8);
      }
      g.lineTo(GW, GROUND_Y); g.closePath(); g.fill();
      // pipes
      for (const p of pipes) drawPipe(p);
      // ground
      g.fillStyle = '#e9c98e'; g.fillRect(0, GROUND_Y, GW, GROUND_H);
      g.fillStyle = '#7fbf55'; g.fillRect(0, GROUND_Y, GW, 12);
      g.fillStyle = '#6aa844';
      for (let x = -groundX; x < GW + 24; x += 24) {
        g.beginPath(); g.moveTo(x, GROUND_Y + 12); g.lineTo(x + 12, GROUND_Y + 12); g.lineTo(x + 6, GROUND_Y + 4); g.closePath(); g.fill();
      }
      g.fillStyle = 'rgba(160,110,60,0.25)';
      for (let x = -groundX * 1; x < GW + 24; x += 24) g.fillRect(x + 3, GROUND_Y + 26, 10, 4);
      g.strokeStyle = '#6b3f24'; g.lineWidth = 2;
      g.beginPath(); g.moveTo(0, GROUND_Y); g.lineTo(GW, GROUND_Y); g.stroke();
      // bird
      drawBird(now);
      // score
      if (state !== 'ready') {
        g.font = 'bold 40px "Microsoft YaHei", sans-serif';
        g.textAlign = 'center'; g.textBaseline = 'top';
        g.lineWidth = 6; g.strokeStyle = '#6b3f24'; g.lineJoin = 'round';
        g.strokeText(String(score), GW / 2, 24);
        g.fillStyle = '#fff'; g.fillText(String(score), GW / 2, 24);
      } else {
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.font = 'bold 30px "Microsoft YaHei", sans-serif';
        g.lineWidth = 6; g.strokeStyle = '#6b3f24'; g.lineJoin = 'round';
        g.strokeText('飞翔小鸟', GW / 2, GH * 0.24);
        g.fillStyle = '#fff'; g.fillText('飞翔小鸟', GW / 2, GH * 0.24);
        g.font = '15px "Microsoft YaHei", sans-serif';
        g.fillStyle = 'rgba(107,63,36,0.85)';
        const a = 0.55 + 0.45 * Math.sin(now / 300);
        g.globalAlpha = a;
        g.fillText('点击或按空格起飞', GW / 2, GH * 0.58);
        g.globalAlpha = 1;
      }
      if (flash > 0) {
        g.fillStyle = `rgba(255,255,255,${flash * 0.8})`;
        g.fillRect(0, 0, GW, GH);
      }
    }

    // ---------- loop ----------
    function frame(t) {
      rafId = requestAnimationFrame(frame);
      const dt = lastT ? Math.min(1 / 30, Math.max(0, (t - lastT) / 1000)) : 0;
      lastT = t;
      if (!ctx.isActive()) {
        if (state === 'play') setState('paused');
        return;
      }
      if (state !== 'paused' && state !== 'over') update(dt, t);
      draw(t);
    }

    // ---------- input ----------
    function onPointer(e) {
      if (e.button !== 0) return;
      e.preventDefault();
      if (state === 'ready' || state === 'play') flap();
    }
    function onKey(e) {
      if (!ctx.isActive()) return;
      const tg = e.target;
      if (tg && (tg.tagName === 'INPUT' || tg.tagName === 'TEXTAREA' || tg.isContentEditable)) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      if (e.code === 'Space' || e.code === 'ArrowUp' || e.code === 'KeyW') {
        e.preventDefault();
        if (document.activeElement && root.contains(document.activeElement)) document.activeElement.blur();
        if (state === 'ready' || state === 'play') { if (!e.repeat) flap(); }
        else if (!e.repeat && (state === 'paused' || state === 'over')) primary();
        return;
      }
      if (e.code === 'KeyP' || e.code === 'Escape') {
        if (e.repeat) return;
        if (state === 'play') { e.preventDefault(); setState('paused'); }
        else if (state === 'paused') { e.preventDefault(); setState('play'); }
        return;
      }
      if (e.code === 'Enter' && (state === 'over' || state === 'paused')) { e.preventDefault(); primary(); }
    }
    function onToggle(e) { e.currentTarget.blur(); primary(); }

    canvas.addEventListener('pointerdown', onPointer);
    toggleBtn.addEventListener('click', onToggle);
    ovBtn.addEventListener('click', onToggle);
    window.addEventListener('keydown', onKey);

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => fit());
      ro.observe(el.parentElement || el);
    } else {
      window.addEventListener('resize', fit);
    }

    reset();
    setState('ready');
    fit();
    t0 = performance.now();
    rafId = requestAnimationFrame(frame);

    cleanup = () => {
      cancelAnimationFrame(rafId);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      window.removeEventListener('keydown', onKey);
      canvas.removeEventListener('pointerdown', onPointer);
      toggleBtn.removeEventListener('click', onToggle);
      ovBtn.removeEventListener('click', onToggle);
      root.remove();
    };
  }

  Hub.register({
    id: 'flappy',
    title: '飞翔小鸟',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="11" cy="13" rx="7" ry="6"/><path d="M5 13c1.5-2.5 4-2.5 5 0" fill="currentColor" fill-opacity=".3"/><circle cx="13.5" cy="11" r="1.1" fill="currentColor" stroke="none"/><path d="M18 12.5l4 1-4 1.5"/><path d="M9 7c0-2 1.5-3 3-3"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
