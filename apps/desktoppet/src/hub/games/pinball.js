// 弹珠台 — pinball game module. Physics/table: pinball-physics.js (window.PinballPhysics).
(function () {
  const PH = window.PinballPhysics;
  const { W, H, BALL_R } = PH;
  const DT = 1 / 240;
  const BALL_SAVE = 8;
  const EXTRA_AT = 150000;
  const BUMPER_COLORS = ['#f06f7e', '#f2b33d', '#6aa7e0'];

  let cleanup = null;

  function makeAudio(isMuted) {
    let ac = null, master = null;
    function ensure() {
      if (isMuted()) return null;
      if (!ac) {
        try { ac = new AudioContext(); master = ac.createGain(); master.gain.value = 0.3; master.connect(ac.destination); } catch { return null; }
      }
      if (ac.state === 'suspended') ac.resume().catch(() => {});
      return ac;
    }
    function tone(f, dur, type, vol, f2, delay) {
      const a = ensure(); if (!a) return;
      const t = a.currentTime + (delay || 0);
      const o = a.createOscillator(), g = a.createGain();
      o.type = type; o.frequency.setValueAtTime(f, t);
      if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + dur);
      g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.02);
    }
    const last = {};
    const gate = (k, ms) => { const n = performance.now(); if (last[k] && n - last[k] < ms) return false; last[k] = n; return true; };
    return {
      unlock: () => ensure(),
      bumper: i => gate('b', 40) && tone([523, 659, 784][i] || 600, 0.12, 'square', 0.14, null),
      flipper: () => gate('f', 60) && tone(140, 0.05, 'triangle', 0.18, 90),
      sling: () => gate('s', 50) && tone(330, 0.08, 'sawtooth', 0.1, 200),
      target: () => tone(880, 0.1, 'square', 0.12, 1200),
      roll: () => tone(1046, 0.08, 'triangle', 0.12),
      spin: () => gate('sp', 45) && tone(1500, 0.03, 'square', 0.05),
      launch: p => tone(200 + p * 300, 0.25, 'sawtooth', 0.12, 700),
      drain: () => tone(300, 0.6, 'sawtooth', 0.14, 60),
      bonus: () => [0, 4, 7, 12].forEach((s, i) => tone(523 * Math.pow(2, s / 12), 0.12, 'triangle', 0.16, null, i * 0.07)),
      tilt: () => tone(90, 0.5, 'square', 0.18),
      close: () => { if (ac) { try { ac.close(); } catch { /* ignore */ } ac = null; } }
    };
  }

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'pb-root';
    root.innerHTML = `
      <div class="pb-stage">
        <canvas class="pb-canvas"></canvas>
        <div class="pb-overlay"><div class="pb-card"><div class="pb-title"></div><div class="pb-sub"></div><button class="pb-btn pb-primary pb-go"></button></div></div>
      </div>
      <div class="pb-side">
        <div class="pb-stat"><span>分数</span><b class="pb-score">0</b></div>
        <div class="pb-stat"><span>最高</span><b class="pb-best">0</b></div>
        <div class="pb-row"><div class="pb-stat"><span>球</span><b class="pb-ball">1 / 3</b></div><div class="pb-stat"><span>倍率</span><b class="pb-mult">×1</b></div></div>
        <div class="pb-msg"></div>
        <div class="pb-help">
          <div><kbd>Z</kbd> / <kbd>←</kbd> 左挡板</div>
          <div><kbd>/</kbd> / <kbd>→</kbd> 右挡板</div>
          <div>鼠标左 / 右键也可控制挡板</div>
          <div>按住 <kbd>空格</kbd> / <kbd>↓</kbd> 蓄力发射</div>
          <div><kbd>N</kbd> 推台（别推太多会 TILT）</div>
          <div><kbd>P</kbd> / <kbd>Esc</kbd> 暂停</div>
        </div>
        <div class="pb-btns"><button class="pb-btn pb-mute"></button><button class="pb-btn pb-new">新游戏</button></div>
      </div>`;
    el.appendChild(root);
    const $ = s => root.querySelector(s);
    const canvas = $('.pb-canvas'), g = canvas.getContext('2d');
    const overlay = $('.pb-overlay');

    let muted = !!ctx.store.get('muted', false);
    const sfx = makeAudio(() => muted);
    let best = ctx.store.get('best', 0);

    let sim, state, score, ballNo, mult, bonus, saveT, dropSets, extraGiven, nudges, tilted, shake, lights, popups, sparks, msgT, rewarded, paused, lastT = 0, acc = 0, rafId = 0;
    let scale = 1, dpr = 1;

    function fit() {
      const host = el.parentElement || el;
      const avail = Math.max(300, (host.clientHeight || 640) - 48);
      const cssH = Math.min(avail, 620);
      const cssW = Math.round(cssH * W / H);
      dpr = window.devicePixelRatio || 1;
      canvas.style.width = cssW + 'px'; canvas.style.height = cssH + 'px';
      canvas.width = Math.round(cssW * dpr); canvas.height = Math.round(cssH * dpr);
      scale = cssW / W;
    }
    function hud() {
      $('.pb-score').textContent = score.toLocaleString();
      $('.pb-best').textContent = Math.max(best, score).toLocaleString();
      $('.pb-ball').textContent = `${Math.min(ballNo, 3)} / 3${extraGiven ? '+' : ''}`;
      $('.pb-mult').textContent = `×${mult}`;
      $('.pb-mute').textContent = muted ? '🔇 静音' : '🔊 音效';
    }
    function msg(text) { $('.pb-msg').textContent = text; msgT = 2.5; }
    function add(pts, x, y) {
      const p = pts * mult;
      score += p;
      if (x != null) popups.push({ x, y, text: '+' + p, life: 0.8 });
      if (!extraGiven && score >= EXTRA_AT) { extraGiven = true; ballNo--; msg('额外奖励一球！'); sfx.bonus(); }
      hud();
    }
    function showOverlay(title, sub, btn, fn) {
      $('.pb-title').textContent = title; $('.pb-sub').innerHTML = sub; $('.pb-go').textContent = btn;
      $('.pb-go').onclick = () => { sfx.unlock(); fn(); };
      overlay.classList.remove('pb-hidden');
    }
    const hideOverlay = () => overlay.classList.add('pb-hidden');

    function newGame() {
      sim = new PH.Sim();
      score = 0; ballNo = 1; mult = 1; bonus = 0; dropSets = 0; extraGiven = false; nudges = 0; tilted = false;
      shake = 0; lights = {}; popups = []; sparks = []; msgT = 0; rewarded = false; paused = false;
      state = 'play';
      serve();
      hideOverlay();
      hud();
    }
    function serve() {
      sim.addBall(true);
      saveT = BALL_SAVE;
      tilted = false; nudges = 0;
      for (const r of sim.rollovers) r.lit = false;
      msg(`第 ${Math.min(ballNo, 3)} 球 · 按住空格蓄力发射`);
    }
    function ballLost() {
      if (saveT > 0 && !tilted) { sim.addBall(true); msg('保护球！再来一次'); return; }
      if (sim.balls.length) return; // multiball: keep playing
      sfx.drain();
      const endBonus = bonus * mult;
      if (endBonus && !tilted) { score += endBonus; msg(`回合奖励 ${endBonus.toLocaleString()}`); }
      bonus = 0; mult = 1;
      ballNo++;
      hud();
      if (ballNo > 3) return gameOver();
      serve();
    }
    function gameOver() {
      state = 'over';
      const newBest = score > best;
      if (newBest) { best = score; ctx.store.set('best', best); if (score > 0) ctx.say('弹珠台新纪录！' + score.toLocaleString()); }
      if (!rewarded && score > 0) { rewarded = true; ctx.reward(Math.min(20, Math.floor(score / 20000) + 2), '弹珠台结算'); }
      hud();
      showOverlay('游戏结束', `得分 <b>${score.toLocaleString()}</b>${newBest ? '<br><span class="pb-rec">新纪录！</span>' : `<br>最高 ${best.toLocaleString()}`}`, '再来一局', newGame);
    }
    function setPaused(p) {
      if (state !== 'play' || paused === p) return;
      paused = p;
      if (p) showOverlay('已暂停', '按 P / Esc 继续', '继续', () => setPaused(false)); else hideOverlay();
    }

    // ---------- events from the physics ----------
    function handleEvents() {
      for (const e of sim.events) {
        switch (e.type) {
          case 'bumper': add(1000, e.x, e.y - 30); sfx.bumper(e.i); spark(e.x, e.y, BUMPER_COLORS[e.i], 8); bonus += 100; break;
          case 'sling': add(200); sfx.sling(); lights['sling' + e.side] = 0.2; break;
          case 'flipperHit': break;
          case 'target': {
            add(2500, e.x, e.y - 20); sfx.target(); spark(e.x + 10, e.y, '#f7c948', 10); bonus += 500;
            if (sim.targets.every(t => t.down)) {
              dropSets++;
              add(10000);
              sfx.bonus();
              mult = Math.min(5, mult + 1);
              msg(dropSets % 2 === 0 ? '多球模式！' : `目标全灭！倍率 ×${mult}`);
              setTimeout(() => { if (sim) sim.targets.forEach(t => { t.down = false; }); }, 700);
              if (dropSets % 2 === 0 && sim.balls.length < 3) { sim.addBall(false); saveT = Math.max(saveT, 6); }
            }
            break;
          }
          case 'rollover': {
            const r = sim.rollovers[e.i];
            add(500);
            sfx.roll();
            r.lit = true;
            if (sim.rollovers.every(x => x.lit)) {
              mult = Math.min(5, mult + 1);
              msg(`三条通道全亮！倍率 ×${mult}`);
              sfx.bonus();
              sim.rollovers.forEach(x => { x.lit = false; });
            }
            break;
          }
          case 'spinner': add(Math.round(e.spin) * 100); sfx.spin(); break;
          case 'launch': sfx.launch(e.power); break;
          case 'drain': ballLost(); break;
        }
      }
      sim.events.length = 0;
      hud();
    }
    function spark(x, y, color, n) {
      for (let i = 0; i < n && sparks.length < 200; i++) {
        const a = Math.random() * Math.PI * 2, s = 60 + Math.random() * 160;
        sparks.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.4 + Math.random() * 0.3, color });
      }
    }

    // ---------- drawing ----------
    function drawTable() {
      const bg = g.createLinearGradient(0, 0, 0, H);
      bg.addColorStop(0, '#2d1b4e'); bg.addColorStop(1, '#4b2a5c');
      g.fillStyle = bg;
      g.fillRect(0, 0, W, H);
      // playfield art
      g.save();
      g.globalAlpha = 0.18;
      g.fillStyle = '#f7c948';
      g.font = 'bold 42px "Microsoft YaHei UI", sans-serif';
      g.textAlign = 'center';
      g.fillText('喵喵弹珠', 200, 400);
      g.globalAlpha = 0.08;
      for (let i = 0; i < 40; i++) { g.beginPath(); g.arc((i * 97) % W, (i * 53) % H, 2, 0, Math.PI * 2); g.fill(); }
      g.restore();
      // lane lights
      sim.rollovers.forEach(r => {
        g.beginPath(); g.arc(r.x, r.y + 30, 6, 0, Math.PI * 2);
        g.fillStyle = r.lit ? '#ffe066' : 'rgba(255,255,255,.18)'; g.fill();
      });
      // multiplier lights
      for (let i = 1; i <= 5; i++) {
        g.beginPath(); g.arc(150 + i * 20, 470, 6, 0, Math.PI * 2);
        g.fillStyle = mult >= i ? '#ff7a8a' : 'rgba(255,255,255,.15)'; g.fill();
      }
      g.fillStyle = 'rgba(255,255,255,.5)'; g.font = '10px sans-serif'; g.textAlign = 'center';
      g.fillText('倍率', 230, 492);
      // walls
      g.lineCap = 'round'; g.lineJoin = 'round';
      for (const w of sim.walls) {
        g.strokeStyle = w.kick ? (lights['sling' + w.sling] > 0 ? '#fff' : '#ff9ec0') : '#e0c8ff';
        g.lineWidth = w.kick ? 6 : 5;
        g.beginPath(); g.moveTo(w.a[0], w.a[1]); g.lineTo(w.b[0], w.b[1]); g.stroke();
      }
      // launch lane plunger
      const py = 612 + sim.plunger * 18;
      g.fillStyle = '#c9b8e8';
      g.fillRect(PH.LANE_X + 4, py, 20, 640 - py);
      g.fillStyle = '#ff7a8a';
      g.fillRect(PH.LANE_X + 4, py, 20, 4);
      // bumpers
      sim.bumpers.forEach((bm, i) => {
        const pop = bm.lit > 0 ? 1.15 : 1;
        g.save(); g.translate(bm.x, bm.y); g.scale(pop, pop);
        g.shadowColor = BUMPER_COLORS[i]; g.shadowBlur = bm.lit > 0 ? 25 : 8;
        g.beginPath(); g.arc(0, 0, bm.r, 0, Math.PI * 2);
        g.fillStyle = BUMPER_COLORS[i]; g.fill();
        g.shadowBlur = 0;
        g.beginPath(); g.arc(0, 0, bm.r * 0.62, 0, Math.PI * 2);
        g.fillStyle = bm.lit > 0 ? '#fff' : '#fff6e8'; g.fill();
        g.fillStyle = BUMPER_COLORS[i]; g.font = 'bold 13px sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText('🐾', 0, 1);
        g.restore();
      });
      // drop targets
      for (const t of sim.targets) {
        g.save(); g.translate(t.x, t.y); g.rotate(Math.atan2(12, t.w));
        g.fillStyle = t.down ? 'rgba(255,255,255,.12)' : t.lit > 0 ? '#fff' : '#f7c948';
        g.fillRect(0, -3, Math.hypot(t.w, 12), 7);
        g.restore();
      }
      // spinner
      const sp = sim.spinner;
      g.save(); g.translate(sp.x, sp.y);
      g.scale(1, Math.abs(Math.cos(sp.angle)) * 0.9 + 0.1);
      g.fillStyle = '#7fe0c0'; g.fillRect(-sp.w / 2, -5, sp.w, 10);
      g.restore();
      // flippers
      for (const f of sim.flippers) {
        const tip = PH.flipperTip(f);
        g.strokeStyle = '#ffffff'; g.lineWidth = 14;
        g.beginPath(); g.moveTo(f.x, f.y); g.lineTo(tip[0], tip[1]); g.stroke();
        g.strokeStyle = '#ff7a8a'; g.lineWidth = 8;
        g.beginPath(); g.moveTo(f.x, f.y); g.lineTo(tip[0], tip[1]); g.stroke();
        g.fillStyle = '#6b3f24'; g.beginPath(); g.arc(f.x, f.y, 4, 0, Math.PI * 2); g.fill();
      }
      // ball save light
      if (saveT > 0) {
        g.fillStyle = (saveT * 4 | 0) % 2 ? '#7fe0c0' : 'rgba(127,224,192,.3)';
        g.font = 'bold 12px "Microsoft YaHei UI", sans-serif'; g.textAlign = 'center';
        g.fillText('保护球', 200, 540);
      }
    }
    function draw() {
      g.setTransform(scale * dpr, 0, 0, scale * dpr, 0, 0);
      g.save();
      if (shake > 0) g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake);
      drawTable();
      for (const b of sim.balls) {
        const grd = g.createRadialGradient(b.x - 3, b.y - 3, 1, b.x, b.y, BALL_R);
        grd.addColorStop(0, '#ffffff'); grd.addColorStop(1, '#a9a9b8');
        g.beginPath(); g.arc(b.x, b.y, BALL_R, 0, Math.PI * 2); g.fillStyle = grd; g.fill();
      }
      for (const s of sparks) { g.globalAlpha = Math.max(0, s.life * 2); g.fillStyle = s.color; g.fillRect(s.x - 2, s.y - 2, 4, 4); }
      g.globalAlpha = 1;
      g.textAlign = 'center';
      for (const p of popups) {
        g.globalAlpha = Math.max(0, p.life / 0.8);
        g.font = 'bold 14px sans-serif'; g.fillStyle = '#ffe066'; g.fillText(p.text, p.x, p.y);
      }
      g.globalAlpha = 1;
      if (tilted) { g.fillStyle = 'rgba(229,72,77,.85)'; g.font = 'bold 48px sans-serif'; g.fillText('TILT', 200, 330); }
      g.restore();
    }

    // ---------- loop ----------
    function frame(t) {
      rafId = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (t - lastT) / 1000 || 0);
      lastT = t;
      if (!ctx.isActive() && state === 'play' && !paused) setPaused(true);
      if (state === 'play' && !paused) {
        acc += dt;
        while (acc >= DT) { sim.step(DT); acc -= DT; handleEvents(); if (state !== 'play') break; }
        if (saveT > 0 && sim.balls.some(b => !b.inLane)) saveT -= dt;
        for (const k of Object.keys(lights)) lights[k] -= dt;
        for (const s of sparks) { s.x += s.vx * dt; s.y += s.vy * dt; s.life -= dt; }
        sparks = sparks.filter(s => s.life > 0);
        for (const p of popups) { p.y -= 30 * dt; p.life -= dt; }
        popups = popups.filter(p => p.life > 0);
        if (shake > 0) shake = Math.max(0, shake - dt * 30);
        if (msgT > 0 && (msgT -= dt) <= 0) $('.pb-msg').textContent = '';
        nudges = Math.max(0, nudges - dt * 0.25);
      }
      draw();
    }

    // ---------- input ----------
    const LEFT = new Set(['z', 'Z', 'ArrowLeft', 'Shift']), RIGHT = new Set(['/', '?', 'ArrowRight']);
    function setFlip(side, on) {
      if (tilted || state !== 'play' || paused) on = false;
      const f = sim.flippers[side];
      if (on && !f.pressed) sfx.flipper();
      f.pressed = on;
    }
    const onKeyDown = e => {
      if (!ctx.isActive()) return;
      if (LEFT.has(e.key)) { e.preventDefault(); setFlip(0, true); }
      else if (RIGHT.has(e.key)) { e.preventDefault(); setFlip(1, true); }
      else if (e.key === ' ' || e.key === 'ArrowDown') { e.preventDefault(); sfx.unlock(); if (state === 'play' && !paused) sim.charging = true; }
      else if (e.key === 'n' || e.key === 'N') {
        if (state !== 'play' || paused || tilted || e.repeat) return;
        sim.nudge((Math.random() - 0.5) * 160);
        shake = 8; nudges += 1;
        if (nudges > 3) { tilted = true; sfx.tilt(); msg('TILT！本球挡板失效'); sim.flippers.forEach(f => { f.pressed = false; }); }
        else if (nudges > 2) msg('小心！再推就 TILT 了');
      } else if (e.key === 'p' || e.key === 'P' || e.key === 'Escape') { e.preventDefault(); setPaused(!paused); }
    };
    const onKeyUp = e => {
      if (LEFT.has(e.key)) setFlip(0, false);
      else if (RIGHT.has(e.key)) setFlip(1, false);
      else if ((e.key === ' ' || e.key === 'ArrowDown') && sim.charging) { sim.charging = false; sim.launch(); }
    };
    const onMouseDown = e => { sfx.unlock(); if (e.button === 0) setFlip(0, true); if (e.button === 2) setFlip(1, true); };
    const onMouseUp = e => { if (e.button === 0) setFlip(0, false); if (e.button === 2) setFlip(1, false); };
    const noMenu = e => e.preventDefault();
    const onBlur = () => { if (sim) { sim.flippers.forEach(f => { f.pressed = false; }); sim.charging = false; } };
    canvas.addEventListener('mousedown', onMouseDown);
    window.addEventListener('mouseup', onMouseUp);
    canvas.addEventListener('contextmenu', noMenu);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
    $('.pb-new').onclick = () => { $('.pb-new').blur(); newGame(); };
    $('.pb-mute').onclick = () => { muted = !muted; ctx.store.set('muted', muted); $('.pb-mute').blur(); hud(); };
    const ro = new ResizeObserver(fit);
    ro.observe(el.parentElement || el);

    sim = new PH.Sim();
    score = 0; ballNo = 1; mult = 1; lights = {}; popups = []; sparks = []; saveT = 0; state = 'idle';
    fit(); hud();
    showOverlay('喵喵弹珠台', '左右挡板：Z / ← 和 / / →<br>按住空格蓄力，松开发射', '开始游戏', newGame);
    lastT = performance.now();
    rafId = requestAnimationFrame(frame);

    // test hook
    root._pb = { get sim() { return sim; }, get score() { return score; }, newGame };

    cleanup = () => {
      cancelAnimationFrame(rafId);
      ro.disconnect();
      canvas.removeEventListener('mousedown', onMouseDown);
      window.removeEventListener('mouseup', onMouseUp);
      canvas.removeEventListener('contextmenu', noMenu);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      sfx.close();
      root.remove();
    };
  }

  Hub.register({
    id: 'pinball', title: '弹珠台', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 3h12v18H6z" stroke-linejoin="round"/><circle cx="12" cy="9" r="2.2"/><path d="M8.5 17l2.5 1.5M15.5 17l-2.5 1.5"/><circle cx="14" cy="13.5" r="1" fill="currentColor"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
