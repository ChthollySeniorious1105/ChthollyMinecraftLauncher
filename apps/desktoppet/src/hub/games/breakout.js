// 打砖块 Breakout — canvas brick-breaker game module for the hub. See ../MODULES.md for the contract.
(function () {
  const GW = 600, GH = 520;              // logical game size
  const COLS = 12, BW = 46, BH = 18, GAP = 2;
  const BX0 = (GW - (COLS * (BW + GAP) - GAP)) / 2, BY0 = 56;
  const PAD_Y = 486, PAD_H = 12, PAD_W = 92;
  const R = 7, R_BIG = 11;
  const NET_Y = GH - 10;
  const PAD_SPEED = 600;
  const MAX_BALLS = 30, MAX_PARTS = 520, MAX_DROPS = 8;
  const MAX_SP = 560;                    // base-speed cap (before fast/slow modifiers)
  const DROP_CHANCE = 0.2;
  const START_LIVES = 3, MAX_LIVES = 6;
  const HAND_LEVELS = 12;
  const ROW_COLORS = ['#e8793a', '#f0995a', '#f2b33d', '#e3867a', '#d9652a', '#f4c27a', '#e0a15a', '#ef8a6a', '#f2b33d', '#e8793a', '#f0995a', '#e3867a', '#d9652a'];
  const CONFETTI = ['#e8793a', '#f2b33d', '#ef5b7a', '#35b56a', '#2f9ed8', '#b154d6', '#ffffff'];

  // Map legend: '.' empty, '1' normal, '2' two-hit, '3' three-hit, '#' steel (unbreakable),
  // 'T' TNT (explodes 3x3, chains), 'C' coin brick (小鱼干 bonus), 'P' guaranteed power-up (glowing).
  // move: { rows: [...] | 'all', amp, spd } makes rows sway horizontally.
  const LEVELS = [
    { name: '热身', map: [
      '............',
      'P1111111111P',
      '111111111111',
      '11111CC11111',
      '111111111111',
      '.1111111111.'
    ] },
    { name: '爱心', map: [
      '..111..111..',
      '.1111111111.',
      '111P2112P111',
      '112222222211',
      '1122C22C2211',
      '.1122222211.',
      '..11222211..',
      '...112211...',
      '....1TT1....',
      '.....11.....'
    ] },
    { name: '猫爪', map: [
      '...11..11...',
      '...2P..P2...',
      '...11..11...',
      '11........11',
      '2T........T2',
      '11..1111..11',
      '...122221...',
      '..12233221..',
      '..122CC221..',
      '...111111...'
    ] },
    { name: '小鱼干', map: [
      '............',
      '...1111.....',
      '..12P221..11',
      '.12222221.1T',
      '1#2C22222111',
      '.12222221.1T',
      '..122221..1P',
      '...1111.....'
    ] },
    { name: '猫咪脸', map: [
      '1..........1',
      '11........11',
      '121111111121',
      '111111111111',
      '11T111111T11',
      '111111111111',
      '1111P22P1111',
      '.11C1111C11.',
      '..11111111..'
    ] },
    { name: '城堡', map: [
      '1.1.1..1.1.1',
      '111111111111',
      '1#22233222#1',
      '1#2......2#1',
      '1#2.TCCT.2#1',
      '1#2......2#1',
      '1###2PP2###1'
    ] },
    { name: '星钻', map: [
      '.....33.....',
      '....2P12....',
      '...211112...',
      '..21C11C12..',
      '.2111##1112.',
      '..21T11T12..',
      '...211112...',
      '....2112....',
      '.....22.....'
    ] },
    { name: 'TNT 仓库', map: [
      '111111111111',
      '1T111T11T111',
      '222222222222',
      'T22C22T22C2T',
      '333333333333',
      '3T3P33P3T333',
      '222222222222',
      '11T1111T1111'
    ] },
    { name: '摇摆列车', move: { rows: [1, 3, 5], amp: 48, spd: 1.6 }, map: [
      '111111111111',
      '..22222222..',
      '111111111111',
      '..3C3333C3..',
      '111111111111',
      '..2P2TT2P2..',
      '111111111111'
    ] },
    { name: '钢铁迷宫', map: [
      'CC11111111CC',
      '111P1111P111',
      '222222222222',
      '###..##..###',
      '.3333333333.',
      '.3T......T3.',
      '##..####..##',
      '111111111111'
    ] },
    { name: '金库', move: { rows: [4], amp: 40, spd: 2.2 }, map: [
      '#CCCCCCCCCC#',
      '#3333333333#',
      '#....TT....#',
      '##.######.##',
      '..22222222..',
      '1P11111111P1',
      '111111111111'
    ] },
    { name: 'BOSS 大猫王', boss: true, move: { rows: 'all', amp: 80, spd: 0.9 }, map: [
      '..2......2..',
      '..32....23..',
      '..33333333..',
      '..3T3333T3..',
      '..3#P33P#3..',
      '..33333333..',
      '..3C3TT3C3..',
      '...333333...',
      '....2222....',
      '...P....P...'
    ] }
  ];

  // Power-ups. dur > 0 → timed (shown in HUD with countdown ring). bad → red capsule.
  const POWERS = {
    wide:    { label: '宽', color: '#f2b33d', name: '加长挡板', dur: 14, w: 10 },
    multi:   { label: '多', color: '#e8793a', name: '多球', dur: 0, w: 9 },
    slow:    { label: '慢', color: '#6fae94', name: '减速', dur: 10, w: 6 },
    laser:   { label: '光', color: '#b154d6', name: '激光', dur: 10, w: 7 },
    life:    { label: '命', color: '#ef5b7a', name: '生命 +1', dur: 0, w: 3 },
    fire:    { label: '火', color: '#ff7a1a', name: '火球', dur: 8, w: 6 },
    split:   { label: '裂', color: '#35b56a', name: '分裂', dur: 0, w: 7 },
    magnet:  { label: '磁', color: '#2f9ed8', name: '磁铁', dur: 15, w: 6 },
    big:     { label: '巨', color: '#a0785a', name: '巨球', dur: 12, w: 6 },
    bomb:    { label: '爆', color: '#5a4a42', name: '炸弹球', dur: 10, w: 6 },
    shield:  { label: '盾', color: '#1bb3b3', name: '护盾', dur: 0, w: 6 },
    x2:      { label: '倍', color: '#e6a800', name: '分数 ×2', dur: 15, w: 7 },
    zap:     { label: '电', color: '#4f7cff', name: '闪电', dur: 0, w: 7 },
    missile: { label: '弹', color: '#6b8e23', name: '追踪导弹', dur: 6, w: 6 },
    shrink:  { label: '缩', color: '#d93a3a', name: '挡板缩短', dur: 10, w: 6, bad: true },
    fast:    { label: '快', color: '#d93a3a', name: '球加速', dur: 10, w: 6, bad: true }
  };
  const POWER_TOTAL = Object.values(POWERS).reduce((s, p) => s + p.w, 0);
  function randomPower(rand, goodOnly) {
    for (;;) {
      let r = rand() * POWER_TOTAL;
      for (const k in POWERS) {
        r -= POWERS[k].w;
        if (r <= 0) { if (goodOnly && POWERS[k].bad) break; return k; }
      }
      if (!goodOnly) return 'wide';
    }
  }

  let cleanup = null;

  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

  function roundRect(g, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    g.beginPath();
    g.moveTo(x + r, y);
    g.arcTo(x + w, y, x + w, y + h, r);
    g.arcTo(x + w, y + h, x, y + h, r);
    g.arcTo(x, y + h, x, y, r);
    g.arcTo(x, y, x + w, y, r);
    g.closePath();
  }

  function shade(hex, amt) {
    const n = parseInt(hex.slice(1), 16);
    let r = (n >> 16) & 255, gg = (n >> 8) & 255, b = n & 255;
    const f = v => clamp(Math.round(amt < 0 ? v * (1 + amt) : v + (255 - v) * amt), 0, 255);
    r = f(r); gg = f(gg); b = f(b);
    return '#' + ((1 << 24) | (r << 16) | (gg << 8) | b).toString(16).slice(1);
  }

  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Procedural endless level. n = level number (> HAND_LEVELS).
  function genLevel(n) {
    const d = n - HAND_LEVELS;
    const rng = mulberry32(n * 9973 + 17);
    const rows = Math.min(12, 6 + ((d + 1) >> 1));
    const style = (rng() * 5) | 0;
    const map = [];
    let steel = 0;
    const steelMax = Math.min(10, 2 + d);
    const moving = [];
    for (let r = 0; r < rows; r++) {
      const half = [];
      const isMove = d >= 2 && r % 2 === 1 && rng() < Math.min(0.6, 0.15 + d * 0.04);
      for (let c = 0; c < 6; c++) {
        let empty = false;
        if (style === 1) empty = (r + c) % 2 === 1 && rng() < 0.7;          // checker
        else if (style === 2) empty = r % 3 === 2;                           // stripes
        else if (style === 3) empty = c < Math.abs(r - rows / 2) - 1;       // diamond
        else if (style === 4) empty = rng() < 0.22;                          // noise
        if (isMove && c === 0) empty = true;
        if (empty) { half.push('.'); continue; }
        const p = rng();
        let ch;
        const pSteel = Math.min(0.08, 0.02 + d * 0.006);
        if (p < pSteel && steel < steelMax && r < rows - 1 && !isMove) { ch = '#'; steel += 2; }
        else if (p < pSteel + 0.05) ch = 'T';
        else if (p < pSteel + 0.08) ch = 'C';
        else if (p < pSteel + 0.12) ch = 'P';
        else if (p < pSteel + 0.12 + Math.min(0.4, 0.06 + d * 0.035)) ch = '3';
        else if (p < 0.7) ch = '2';
        else ch = '1';
        half.push(ch);
      }
      map.push(half.join('') + half.slice().reverse().join(''));
      if (isMove) moving.push(r);
    }
    if (!map.some(row => /[123TCP]/.test(row))) map[0] = '111111111111';
    const lv = { name: `无尽 ${d}`, map, endless: true };
    if (moving.length) lv.move = { rows: moving, amp: 40, spd: 1.2 + Math.min(1.4, d * 0.08) };
    return lv;
  }

  // ---------- WebAudio synth ----------
  function makeAudio(isMuted) {
    let ac = null, master = null, noiseBuf = null;
    const last = {};
    function ensure() {
      if (isMuted()) return null;
      if (!ac) {
        try {
          const AC = window.AudioContext || window.webkitAudioContext;
          if (!AC) return null;
          ac = new AC();
          master = ac.createGain();
          master.gain.value = 0.32;
          const comp = ac.createDynamicsCompressor();
          master.connect(comp); comp.connect(ac.destination);
        } catch (e) { ac = null; return null; }
      }
      if (ac.state === 'suspended') ac.resume().catch(() => {});
      return ac;
    }
    function gate(name, gap) {
      const now = performance.now();
      if (last[name] && now - last[name] < gap) return false;
      last[name] = now;
      return true;
    }
    function tone(f, dur, type, vol, f2, delay) {
      const a = ensure(); if (!a) return;
      const t = a.currentTime + (delay || 0);
      const o = a.createOscillator(), gn = a.createGain();
      o.type = type || 'square';
      o.frequency.setValueAtTime(f, t);
      if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + dur);
      gn.gain.setValueAtTime(0.0001, t);
      gn.gain.exponentialRampToValueAtTime(vol, t + 0.005);
      gn.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(gn); gn.connect(master);
      o.start(t); o.stop(t + dur + 0.03);
    }
    function noise(dur, vol, freq, ftype, f2, delay) {
      const a = ensure(); if (!a) return;
      if (!noiseBuf) {
        noiseBuf = a.createBuffer(1, a.sampleRate, a.sampleRate);
        const d = noiseBuf.getChannelData(0);
        for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      }
      const t = a.currentTime + (delay || 0);
      const src = a.createBufferSource(); src.buffer = noiseBuf;
      const flt = a.createBiquadFilter(); flt.type = ftype || 'lowpass';
      flt.frequency.setValueAtTime(freq, t);
      if (f2) flt.frequency.exponentialRampToValueAtTime(f2, t + dur);
      const gn = a.createGain();
      gn.gain.setValueAtTime(vol, t);
      gn.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      src.connect(flt); flt.connect(gn); gn.connect(master);
      src.start(t); src.stop(t + dur + 0.03);
    }
    const semi = n => Math.pow(2, n / 12);
    return {
      unlock() { ensure(); },
      hit(combo) { if (gate('hit', 25)) tone(330 * semi(Math.min(combo, 30)), 0.09, 'square', 0.12); },
      brk(combo) { if (!gate('brk', 30)) return; tone(520 * semi(Math.min(combo, 30)), 0.12, 'triangle', 0.18); noise(0.08, 0.12, 3000, 'highpass'); },
      steel() { if (gate('steel', 40)) tone(1200, 0.07, 'square', 0.06, 900); },
      paddle() { if (gate('pad', 30)) tone(180, 0.08, 'sine', 0.25, 120); },
      wall() { if (gate('wall', 40)) tone(240, 0.04, 'sine', 0.08); },
      boom() { if (!gate('boom', 60)) return; noise(0.5, 0.5, 900, 'lowpass', 80); tone(140, 0.4, 'sine', 0.5, 35); },
      power() { [0, 4, 7, 12].forEach((s, i) => tone(523 * semi(s), 0.1, 'triangle', 0.18, null, i * 0.05)); },
      bad() { [0, -3, -6].forEach((s, i) => tone(330 * semi(s), 0.12, 'sawtooth', 0.1, null, i * 0.07)); },
      coin() { tone(988, 0.07, 'square', 0.1); tone(1319, 0.18, 'square', 0.1, null, 0.07); },
      zap() { if (!gate('zap', 50)) return; noise(0.18, 0.25, 2500, 'bandpass', 600); tone(90, 0.15, 'sawtooth', 0.12, 60); },
      laser() { if (gate('laser', 60)) tone(1400, 0.08, 'square', 0.05, 500); },
      missile() { if (gate('missile', 80)) noise(0.12, 0.12, 1200, 'bandpass', 3000); },
      shield() { tone(660, 0.2, 'sine', 0.2, 990); },
      combo(n) { [0, 4, 7, 11, 14].forEach((s, i) => tone(440 * semi(s + Math.min(n / 5, 12)), 0.09, 'square', 0.08, null, i * 0.04)); },
      lose() { tone(440, 0.6, 'sawtooth', 0.15, 80); noise(0.4, 0.15, 600, 'lowpass', 100); },
      clear() { [0, 4, 7, 12, 16, 19, 24].forEach((s, i) => tone(523 * semi(s), 0.16, 'triangle', 0.18, null, i * 0.07)); },
      over() { [7, 4, 0, -5].forEach((s, i) => tone(392 * semi(s), 0.25, 'triangle', 0.16, null, i * 0.16)); },
      close() { if (ac) { try { ac.close(); } catch (e) { /* ignore */ } ac = null; } }
    };
  }

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'bo-root';
    root.innerHTML = `
      <div class="bo-bar">
        <div class="bo-stats">
          <div class="bo-stat"><span class="bo-lbl">分数</span><b class="bo-score">0</b></div>
          <div class="bo-stat"><span class="bo-lbl">最高</span><b class="bo-best">0</b></div>
          <div class="bo-stat"><span class="bo-lbl">关卡</span><b class="bo-level">1</b></div>
          <div class="bo-stat"><span class="bo-lbl">生命</span><b class="bo-lives"></b></div>
          <div class="bo-stat"><span class="bo-lbl">小鱼干</span><b class="bo-coins">0</b></div>
        </div>
        <div class="bo-opts">
          <button type="button" class="bo-btn bo-mute" title="音效"></button>
          <button type="button" class="bo-btn bo-pause">暂停</button>
          <button type="button" class="bo-btn bo-primary bo-new">新游戏</button>
        </div>
      </div>
      <div class="bo-stage">
        <canvas class="bo-canvas"></canvas>
        <div class="bo-overlay hidden">
          <div class="bo-card">
            <div class="bo-ov-title"></div>
            <div class="bo-ov-sub"></div>
            <div class="bo-ov-btns"><button type="button" class="bo-btn bo-primary bo-ov-btn"></button></div>
          </div>
        </div>
      </div>
      <div class="bo-help">鼠标 / ←→ 移动 · 空格 / 点击发射 · 磁铁吸住后再按发射 · P / Esc 暂停 · 红色胶囊是坏道具，躲开它！</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.bo-stage'), canvas = $('.bo-canvas');
    const g = canvas.getContext('2d');
    const scoreEl = $('.bo-score'), bestEl = $('.bo-best'), levelEl = $('.bo-level'), livesEl = $('.bo-lives'), coinsEl = $('.bo-coins');
    const pauseBtn = $('.bo-pause'), newBtn = $('.bo-new'), muteBtn = $('.bo-mute');
    const overlay = $('.bo-overlay'), ovTitle = $('.bo-ov-title'), ovSub = $('.bo-ov-sub'), ovBtn = $('.bo-ov-btn');

    let muted = !!ctx.store.get('muted', false);
    const sfx = makeAudio(() => muted);

    // ---------- state ----------
    let state = 'ready';     // ready | play | clear | over
    let paused = false;
    let levelIdx = 0, levelNum = 1, level = null, levelTime = 0;
    let score = 0, lives = START_LIVES, levelCoins = 0;
    let best = ctx.store.get('best', 0) || 0;
    let bestAnnounced = false;
    let bricks = [], balls = [], drops = [], beams = [], missiles = [], bolts = [], parts = [], floats = [], rings = [];
    let padX = GW / 2, padW = PAD_W, padTargetW = PAD_W, padSquash = 0;
    const T = {};             // active timed power-ups: kind -> seconds left
    let shields = 0;
    let laserCd = 0, missileCd = 0;
    let baseSpeed = 330;
    let combo = 0, comboShow = 0, comboPeak = 0;
    let keyL = false, keyR = false, mouseX = null;
    let shake = 0, hitStop = 0, flash = 0;
    let rafId = 0, lastT = 0;
    let scale = 1, dpr = 1;
    let ovAction = null;

    // ---------- layout ----------
    function fit() {
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(240, stage.clientWidth);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 4);
      const cssW = Math.floor(Math.min(GW * 1.2, aw, ah * GW / GH));
      const cssH = Math.floor(cssW * GH / GW);
      dpr = window.devicePixelRatio || 1;
      canvas.style.width = cssW + 'px';
      canvas.style.height = cssH + 'px';
      canvas.width = Math.round(cssW * dpr);
      canvas.height = Math.round(cssH * dpr);
      scale = cssW / GW;
      draw();
    }

    // ---------- HUD ----------
    function updateHud() {
      scoreEl.textContent = score;
      bestEl.textContent = Math.max(best, score);
      levelEl.textContent = levelNum;
      livesEl.textContent = lives > 0 ? '♥'.repeat(lives) : '—';
      coinsEl.textContent = levelCoins;
      pauseBtn.textContent = paused ? '继续' : '暂停';
      muteBtn.textContent = muted ? '🔇' : '🔊';
    }
    function showOverlay(title, sub, btnText, action) {
      ovTitle.textContent = title;
      ovSub.innerHTML = sub;
      ovBtn.textContent = btnText;
      ovAction = action;
      overlay.classList.remove('hidden');
    }
    function hideOverlay() { overlay.classList.add('hidden'); ovAction = null; }

    // ---------- setup ----------
    function levelDef(n) { return n <= HAND_LEVELS ? LEVELS[n - 1] : genLevel(n); }
    function buildLevel() {
      level = levelDef(levelNum);
      bricks = [];
      const moveRows = level.move ? (level.move.rows === 'all' ? null : new Set(level.move.rows)) : new Set();
      level.map.forEach((row, ry) => {
        for (let c = 0; c < COLS; c++) {
          const ch = row[c];
          if (!ch || ch === '.' || ch === ' ') continue;
          const type = ch === '#' ? 'steel' : ch === 'T' ? 'tnt' : ch === 'C' ? 'coin' : ch === 'P' ? 'power' : 'normal';
          const hp = ch === '2' ? 2 : ch === '3' ? 3 : 1;
          const x = BX0 + c * (BW + GAP);
          bricks.push({
            x, x0: x, y: BY0 + ry * (BH + GAP), w: BW, h: BH, type, hp, maxHp: hp, alive: true, flash: 0,
            moving: !!level.move && (moveRows === null || moveRows.has(ry)),
            color: ROW_COLORS[ry % ROW_COLORS.length]
          });
        }
      });
      const n = levelNum - 1;
      baseSpeed = Math.min(MAX_SP, 320 + Math.min(n, 20) * 10);
      levelTime = 0;
    }

    function newBall(x, y, dx, dy, stuck) {
      return { x, y, dx, dy, sp: baseSpeed, stuck: !!stuck, off: 0, trail: [] };
    }
    function resetBall() {
      const b = newBall(padX, PAD_Y - R, 0, -1, true);
      b.off = (Math.random() - 0.5) * 30;
      balls = [b];
      drops = []; beams = []; missiles = [];
      for (const k of Object.keys(T)) delete T[k];
      padTargetW = PAD_W;
      combo = 0;
      state = 'ready';
    }
    function startLevel() {
      buildLevel();
      parts = []; floats = []; rings = []; bolts = [];
      levelCoins = 0;
      resetBall();
      padW = PAD_W;
      hideOverlay();
      updateHud();
    }
    function newGame() {
      levelNum = 1;
      score = 0; lives = START_LIVES;
      bestAnnounced = false; paused = false; comboPeak = 0;
      shields = 0;
      padX = GW / 2;
      startLevel();
    }

    // ---------- helpers ----------
    const ballR = () => (T.big > 0 ? R_BIG : R);
    const speedMult = () => (T.slow > 0 ? 0.62 : 1) * (T.fast > 0 ? 1.35 : 1);
    const scoreMult = () => (T.x2 > 0 ? 2 : 1);
    function addScore(n) { score += Math.round(n * scoreMult()); }
    function burst(x, y, color, n, spd, grav) {
      const room = MAX_PARTS - parts.length;
      n = Math.min(n, room);
      for (let i = 0; i < n; i++) {
        const a = Math.random() * Math.PI * 2, s = (0.3 + Math.random()) * spd;
        parts.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - 40, life: 0.5 + Math.random() * 0.5, max: 1, size: 2 + Math.random() * 3.5, color, grav: grav == null ? 520 : grav });
      }
    }
    function addFloat(x, y, text, color, big) { floats.push({ x, y, text, color, life: big ? 1.4 : 0.9, max: big ? 1.4 : 0.9, big }); }
    function kick(amount, stop) { shake = Math.min(14, shake + amount); if (stop) hitStop = Math.max(hitStop, stop); }
    function breakableLeft() { return bricks.some(b => b.alive && b.type !== 'steel'); }

    // ---------- bricks ----------
    function damage(br, dmg, source) {
      if (!br.alive) return;
      br.flash = 0.12;
      if (br.type === 'steel') {
        if (source === 'fire' || source === 'boom' || source === 'zap') {
          // fireballs and explosions melt steel after enough hits
          br.hp -= 0.34;
          if (br.hp > -1) { burst(br.x + br.w / 2, br.y + br.h / 2, '#d9cbbd', 3, 70); sfx.steel(); return; }
        } else { burst(br.x + br.w / 2, br.y + br.h / 2, '#c9b8a6', 3, 60); sfx.steel(); return; }
      } else {
        br.hp -= dmg;
        if (br.hp > 0) {
          addScore(5);
          burst(br.x + br.w / 2, br.y + br.h / 2, '#f6d7b3', 5, 80);
          sfx.hit(combo);
          return;
        }
      }
      destroy(br);
    }
    function destroy(br) {
      br.alive = false;
      combo++;
      comboPeak = Math.max(comboPeak, combo);
      const base = br.type === 'tnt' ? 30 : br.type === 'steel' ? 50 : 10 * br.maxHp;
      const pts = base + Math.min(combo, 50) * 2;
      addScore(pts);
      const cx = br.x + br.w / 2, cy = br.y + br.h / 2;
      if (combo >= 3 && combo % 1 === 0) addFloat(cx, cy, `+${Math.round(pts * scoreMult())}`, '#e8793a');
      burst(cx, cy, br.type === 'steel' ? '#9c8472' : br.color, 12 + Math.min(combo, 20), 170);
      kick(1 + Math.min(combo, 20) * 0.08);
      sfx.brk(combo);
      if (combo > 0 && combo % 10 === 0) { comboShow = 1.2; sfx.combo(combo); }
      if (br.type === 'coin') {
        levelCoins++;
        addFloat(cx, cy - 10, '🐟 +1', '#c98f4a');
        sfx.coin();
      }
      if (br.type === 'tnt') explode(cx, cy, 1);
      if (br.type === 'power') spawnDrop(cx, cy, randomPower(Math.random, true));
      else if (Math.random() < DROP_CHANCE) spawnDrop(cx, cy, randomPower(Math.random, false));
      updateHud();
      if (!breakableLeft() && state === 'play') levelClear();
    }
    // 3x3 blast around (x, y); chains through TNT bricks
    function explode(x, y, radiusCells) {
      const rx = (BW + GAP) * (radiusCells + 0.5), ry = (BH + GAP) * (radiusCells + 0.5);
      rings.push({ x, y, r: 6, max: Math.max(rx, ry) * 1.4, life: 0.45 });
      burst(x, y, '#ff9a3c', 26, 260, 200);
      burst(x, y, '#5a4a42', 12, 180, 300);
      kick(7, 0.06);
      flash = Math.max(flash, 0.25);
      sfx.boom();
      // defer the chain a little so explosions ripple outwards
      setTimeout(() => {
        if (!cleanup) return;
        for (const b of bricks) {
          if (!b.alive) continue;
          const bx = b.x + b.w / 2, by = b.y + b.h / 2;
          if (Math.abs(bx - x) <= rx && Math.abs(by - y) <= ry) damage(b, 3, 'boom');
        }
      }, 70);
    }
    function spawnDrop(x, y, kind) {
      if (drops.length >= MAX_DROPS) return;
      drops.push({ x, y, kind, vy: 90, t: 0 });
    }

    // ---------- power-ups ----------
    function applyPower(kind, x) {
      const P = POWERS[kind];
      addFloat(x, PAD_Y - 22, P.name, P.bad ? '#d93a3a' : P.color, true);
      if (P.bad) sfx.bad(); else { sfx.power(); addScore(25); }
      if (P.dur) T[kind] = P.dur;
      switch (kind) {
        case 'wide': delete T.shrink; break;
        case 'shrink': delete T.wide; break;
        case 'slow': delete T.fast; break;
        case 'fast': delete T.slow; break;
        case 'life': lives = Math.min(MAX_LIVES, lives + 1); break;
        case 'multi': multiply(2); break;
        case 'split': multiply(3, true); break;
        case 'shield': shields = Math.min(3, shields + 1); sfx.shield(); break;
        case 'zap': lightning(5); break;
        case 'magnet': break;
      }
      padTargetW = T.wide > 0 ? PAD_W * 1.6 : T.shrink > 0 ? PAD_W * 0.6 : PAD_W;
      updateHud();
    }
    function multiply(n, every) {
      const src = balls.filter(b => !b.stuck);
      const add = [];
      const spread = n === 3 ? [-0.45, 0.45] : [0.35];
      const list = every ? src : src.slice(0, Math.max(1, Math.ceil(src.length / 2)));
      for (const b of list) {
        for (const ang of spread) {
          if (balls.length + add.length >= MAX_BALLS) break;
          const c = Math.cos(ang), s = Math.sin(ang);
          let dx = b.dx * c - b.dy * s, dy = b.dx * s + b.dy * c;
          if (Math.abs(dy) < 0.25) dy = dy < 0 ? -0.3 : 0.3;
          const l = Math.hypot(dx, dy);
          const nb = newBall(b.x, b.y, dx / l, dy / l);
          nb.sp = b.sp;
          add.push(nb);
        }
      }
      if (!add.length && balls.length < MAX_BALLS) {
        for (const dx of [-0.45, 0.45]) add.push(newBall(padX, PAD_Y - R - 2, dx, -Math.sqrt(1 - dx * dx)));
        if (state === 'ready') state = 'play';
      }
      balls.push(...add);
    }
    function lightning(n) {
      const alive = bricks.filter(b => b.alive && b.type !== 'steel');
      for (let i = 0; i < n && alive.length; i++) {
        const br = alive.splice((Math.random() * alive.length) | 0, 1)[0];
        const tx = br.x + br.w / 2, ty = br.y + br.h / 2;
        const pts = [[padX, PAD_Y]];
        const segs = 7;
        for (let s = 1; s < segs; s++) {
          const t = s / segs;
          pts.push([padX + (tx - padX) * t + (Math.random() - 0.5) * 40, PAD_Y + (ty - PAD_Y) * t]);
        }
        pts.push([tx, ty]);
        bolts.push({ pts, life: 0.35 });
        setTimeout(() => { if (cleanup) damage(br, 9, 'zap'); }, 60 + i * 70);
      }
      flash = Math.max(flash, 0.3);
      kick(5);
      sfx.zap();
    }
    function fire() {
      if (state !== 'play') return;
      if (T.laser > 0 && laserCd <= 0) {
        laserCd = 0.22;
        beams.push({ x: padX - padW / 2 + 8, y: PAD_Y }, { x: padX + padW / 2 - 8, y: PAD_Y });
        sfx.laser();
      }
    }
    function launch() {
      let any = false;
      for (const b of balls) {
        if (!b.stuck) continue;
        const a = clamp(b.off / (padW / 2), -1, 1) * 0.6 + (Math.random() - 0.5) * 0.15;
        b.dx = Math.sin(a); b.dy = -Math.cos(a);
        b.stuck = false;
        any = true;
      }
      if (any) { state = 'play'; sfx.unlock(); }
      return any;
    }

    // ---------- physics ----------
    function fixAngle(b) {
      const MIN = 0.25;
      if (Math.abs(b.dy) < MIN) {
        b.dy = (b.dy < 0 ? -1 : 1) * MIN;
        b.dx = (b.dx < 0 ? -1 : 1) * Math.sqrt(1 - MIN * MIN);
      }
      // avoid perfectly vertical loops too
      if (Math.abs(b.dx) < 0.04) b.dx = (Math.random() < 0.5 ? -1 : 1) * 0.08;
      const l = Math.hypot(b.dx, b.dy) || 1;
      b.dx /= l; b.dy /= l;
    }
    function collideRect(b, r, rad) {
      const nx = clamp(b.x, r.x, r.x + r.w), ny = clamp(b.y, r.y, r.y + r.h);
      const ddx = b.x - nx, ddy = b.y - ny;
      const d2 = ddx * ddx + ddy * ddy;
      if (d2 > rad * rad) return false;
      let n;
      if (d2 === 0) {
        const pl = b.x - r.x, pr = r.x + r.w - b.x, pt = b.y - r.y, pb = r.y + r.h - b.y;
        const m = Math.min(pl, pr, pt, pb);
        if (m === pt) { n = [0, -1]; b.y = r.y - rad; }
        else if (m === pb) { n = [0, 1]; b.y = r.y + r.h + rad; }
        else if (m === pl) { n = [-1, 0]; b.x = r.x - rad; }
        else { n = [1, 0]; b.x = r.x + r.w + rad; }
      } else {
        const d = Math.sqrt(d2);
        n = [ddx / d, ddy / d];
        b.x = nx + n[0] * (rad + 0.01);
        b.y = ny + n[1] * (rad + 0.01);
      }
      const dot = b.dx * n[0] + b.dy * n[1];
      if (dot < 0) { b.dx -= 2 * dot * n[0]; b.dy -= 2 * dot * n[1]; }
      fixAngle(b);
      return true;
    }
    function stepBall(b, dt) {
      const rad = ballR();
      const dist = b.sp * speedMult() * dt;
      const steps = Math.max(1, Math.ceil(dist / (rad * 0.5)));
      const s = dist / steps;
      for (let i = 0; i < steps; i++) {
        b.x += b.dx * s;
        b.y += b.dy * s;
        if (b.x < rad) { b.x = rad; b.dx = Math.abs(b.dx); sfx.wall(); }
        else if (b.x > GW - rad) { b.x = GW - rad; b.dx = -Math.abs(b.dx); sfx.wall(); }
        if (b.y < rad) { b.y = rad; b.dy = Math.abs(b.dy); sfx.wall(); }
        // paddle
        const half = padW / 2;
        if (b.dy > 0 && b.y + rad >= PAD_Y && b.y - rad <= PAD_Y + PAD_H &&
            b.x >= padX - half - rad && b.x <= padX + half + rad && b.y < PAD_Y + PAD_H / 2) {
          padSquash = 1;
          combo = 0;
          sfx.paddle();
          if (T.magnet > 0) {
            b.stuck = true;
            b.off = clamp(b.x - padX, -half + rad, half - rad);
            b.y = PAD_Y - rad;
            return true;
          }
          const rel = clamp((b.x - padX) / (half + rad * 0.5), -1, 1);
          const ang = rel * (Math.PI / 3);
          b.dx = Math.sin(ang); b.dy = -Math.cos(ang);
          fixAngle(b);
          b.y = PAD_Y - rad - 0.01;
          b.sp = Math.min(MAX_SP, b.sp + 1.5);
          continue;
        }
        // bricks
        for (const br of bricks) {
          if (!br.alive) continue;
          if (b.x + rad < br.x || b.x - rad > br.x + br.w || b.y + rad < br.y || b.y - rad > br.y + br.h) continue;
          if (T.fire > 0 && br.type !== 'steel') {
            // fireball: smash straight through
            damage(br, 99, 'fire');
            continue;
          }
          if (collideRect(b, br, rad)) {
            if (T.bomb > 0) explode(br.x + br.w / 2, br.y + br.h / 2, 1);
            damage(br, T.big > 0 ? 2 : 1, T.fire > 0 ? 'fire' : 'ball');
            b.sp = Math.min(MAX_SP, b.sp + 2.5);
            break;
          }
        }
        if (state !== 'play') return true;
        if (b.y - rad > NET_Y && shields > 0) {
          shields--;
          b.y = NET_Y - rad; b.dy = -Math.abs(b.dy);
          fixAngle(b);
          burst(b.x, NET_Y, '#1bb3b3', 16, 150);
          sfx.shield();
          kick(3);
        }
        if (b.y - rad > GH) return false;
      }
      b.trail.push(b.x, b.y);
      if (b.trail.length > 16) b.trail.splice(0, 2);
      return true;
    }

    // ---------- flow ----------
    function loseLife() {
      lives--;
      kick(12, 0.15);
      flash = 0.4;
      sfx.lose();
      updateHud();
      if (lives <= 0) { gameOver(); return; }
      ctx.toast && ctx.toast(`还剩 ${lives} 条命`);
      resetBall();
    }
    function checkBest() {
      if (score > best) {
        const old = best;
        best = score;
        ctx.store.set('best', best);
        if (!bestAnnounced && old > 0) { bestAnnounced = true; ctx.say(`打砖块新纪录：${best} 分！`); }
      }
      updateHud();
    }
    function levelClear() {
      state = 'clear';
      balls.forEach(b => { b.stuck = true; });
      flash = 0.6;
      sfx.clear();
      confetti();
      // time bonus for fast clears
      const bonus = Math.max(0, Math.round((90 - levelTime) * 20));
      addScore(bonus);
      const coins = Math.min(15, 3 + levelNum) + Math.min(10, levelCoins);
      checkBest();
      ctx.reward(coins, '打砖块过关');
      const next = levelDef(levelNum + 1).name;
      showOverlay(`第 ${levelNum} 关完成！`,
        `<div>「${level.name}」已清空 · 用时 ${Math.round(levelTime)} 秒${bonus ? ` · 速通奖励 +${bonus}` : ''}</div>` +
        `<div>最高连击 ${comboPeak} · 奖励小鱼干 +${coins}${levelCoins ? `（含金币砖 ${Math.min(10, levelCoins)}）` : ''}</div>` +
        `<div class="bo-muted">下一关：${next}</div>`,
        '下一关', nextLevel);
    }
    function nextLevel() { levelNum++; startLevel(); }
    function gameOver() {
      state = 'over';
      balls = [];
      const wasBest = score > best, hadOld = best > 0;
      checkBest();
      sfx.over();
      showOverlay('游戏结束',
        `<div>到达第 ${levelNum} 关 · 得分 ${score} · 最高连击 ${comboPeak}</div>` +
        (wasBest && hadOld ? '<div class="bo-rec">新纪录！</div>' : `<div class="bo-muted">最高分 ${best}</div>`),
        '再来一局', newGame);
    }
    function setPaused(p) {
      if (state === 'over' || state === 'clear') p = false;
      if (paused === p) return;
      paused = p;
      if (paused) showOverlay('已暂停', '<div class="bo-muted">按 P / Esc 或点击继续</div>', '继续', () => setPaused(false));
      else hideOverlay();
      updateHud();
    }
    function confetti() {
      for (let i = 0; i < 90 && parts.length < MAX_PARTS; i++) {
        parts.push({ x: Math.random() * GW, y: -10 - Math.random() * 60, vx: (Math.random() - 0.5) * 80, vy: 60 + Math.random() * 120,
          life: 2 + Math.random(), max: 3, size: 4 + Math.random() * 4, color: CONFETTI[(Math.random() * CONFETTI.length) | 0], grav: 60, spin: true });
      }
    }

    // ---------- update ----------
    function update(dt) {
      if (hitStop > 0) { hitStop -= dt; return; }
      if (state === 'play') levelTime += dt;
      // paddle
      if (keyL || keyR) { padX += ((keyR ? 1 : 0) - (keyL ? 1 : 0)) * PAD_SPEED * dt; mouseX = null; }
      else if (mouseX != null) padX += (mouseX - padX) * Math.min(1, dt * 25);
      padW += (padTargetW - padW) * Math.min(1, dt * 10);
      padX = clamp(padX, padW / 2, GW - padW / 2);
      padSquash = Math.max(0, padSquash - dt * 6);

      // timers
      for (const k of Object.keys(T)) {
        T[k] -= dt;
        if (T[k] <= 0) {
          delete T[k];
          if (k === 'wide' || k === 'shrink') padTargetW = T.wide > 0 ? PAD_W * 1.6 : T.shrink > 0 ? PAD_W * 0.6 : PAD_W;
          if (k === 'magnet' && state === 'play') launch();
        }
      }
      if (laserCd > 0) laserCd -= dt;
      if (T.laser > 0 && (keyFire || mouseDown) && state === 'play') fire();
      if (T.missile > 0 && state === 'play') {
        missileCd -= dt;
        if (missileCd <= 0) {
          missileCd = 0.35;
          for (const side of [-1, 1]) missiles.push({ x: padX + side * padW / 3, y: PAD_Y - 4, vx: side * 60, vy: -260, life: 3 });
          sfx.missile();
        }
      }
      for (const br of bricks) {
        if (br.flash > 0) br.flash -= dt;
        if (br.moving && br.alive && level.move) br.x = br.x0 + Math.sin(performance.now() / 1000 * level.move.spd) * level.move.amp;
      }

      // balls
      if (state === 'ready' || state === 'play') {
        for (const b of balls) if (b.stuck) { b.x = padX + clamp(b.off, -padW / 2 + ballR(), padW / 2 - ballR()); b.y = PAD_Y - ballR(); }
      }
      if (state === 'play') {
        balls = balls.filter(b => b.stuck || stepBall(b, dt));
        if (state === 'play' && !balls.length) loseLife();
      }

      // drops
      if (state === 'play' || state === 'ready') {
        drops = drops.filter(d => {
          d.t += dt;
          d.y += d.vy * dt;
          d.vy = Math.min(200, d.vy + 50 * dt);
          if (d.y + 8 >= PAD_Y && d.y - 8 <= PAD_Y + PAD_H && Math.abs(d.x - padX) <= padW / 2 + 16) {
            applyPower(d.kind, d.x);
            return false;
          }
          return d.y < GH + 20;
        });
      }

      // lasers
      beams = beams.filter(bm => {
        bm.y -= 780 * dt;
        if (bm.y < -10) return false;
        for (const br of bricks) {
          if (br.alive && bm.x >= br.x && bm.x <= br.x + br.w && bm.y >= br.y && bm.y <= br.y + br.h) {
            if (state === 'play') damage(br, 1, 'laser');
            return false;
          }
        }
        return true;
      });
      // homing missiles
      missiles = missiles.filter(m => {
        m.life -= dt;
        let tgt = null, bd = Infinity;
        for (const br of bricks) {
          if (!br.alive || br.type === 'steel') continue;
          const d = Math.hypot(br.x + br.w / 2 - m.x, br.y + br.h / 2 - m.y);
          if (d < bd) { bd = d; tgt = br; }
        }
        if (tgt) {
          const ax = tgt.x + tgt.w / 2 - m.x, ay = tgt.y + tgt.h / 2 - m.y, l = Math.hypot(ax, ay) || 1;
          m.vx += ax / l * 900 * dt; m.vy += ay / l * 900 * dt;
          const sp = Math.hypot(m.vx, m.vy), max = 420;
          if (sp > max) { m.vx *= max / sp; m.vy *= max / sp; }
        }
        m.x += m.vx * dt; m.y += m.vy * dt;
        if (parts.length < MAX_PARTS && Math.random() < 0.7) parts.push({ x: m.x, y: m.y, vx: 0, vy: 0, life: 0.3, max: 0.3, size: 3, color: '#c9c2b8', grav: -40 });
        for (const br of bricks) {
          if (br.alive && m.x >= br.x && m.x <= br.x + br.w && m.y >= br.y && m.y <= br.y + br.h) {
            if (state === 'play') { damage(br, 2, 'missile'); burst(m.x, m.y, '#ffb347', 8, 120); }
            return false;
          }
        }
        return m.life > 0 && m.y > -20 && m.x > -20 && m.x < GW + 20;
      });

      // effects
      parts = parts.filter(p => {
        p.life -= dt;
        p.vy += p.grav * dt;
        p.x += p.vx * dt; p.y += p.vy * dt;
        return p.life > 0 && p.y < GH + 20;
      });
      floats = floats.filter(f => { f.life -= dt; f.y -= (f.big ? 22 : 34) * dt; return f.life > 0; });
      rings = rings.filter(r => { r.life -= dt; r.r += (r.max - r.r) * Math.min(1, dt * 12); return r.life > 0; });
      bolts = bolts.filter(b => (b.life -= dt) > 0);
      if (shake > 0) shake = Math.max(0, shake - dt * 24);
      if (flash > 0) flash = Math.max(0, flash - dt * 1.8);
      if (comboShow > 0) comboShow -= dt;
    }

    // ---------- drawing ----------
    function drawBrick(br) {
      let top, bot, edge;
      if (br.type === 'steel') { top = '#c2b3a5'; bot = '#7f6453'; edge = '#5a4234'; }
      else if (br.type === 'tnt') { top = '#e0493a'; bot = '#a02a20'; edge = '#6e1a13'; }
      else if (br.type === 'coin') { top = '#ffe38a'; bot = '#e0a526'; edge = '#a8761a'; }
      else if (br.maxHp >= 2) {
        const k = br.hp / br.maxHp;
        top = shade('#c8683a', 0.3 * (1 - k)); bot = shade('#8e4424', 0.3 * (1 - k)); edge = '#6b3f24';
      } else { top = shade(br.color, 0.25); bot = shade(br.color, -0.12); edge = shade(br.color, -0.3); }
      const grd = g.createLinearGradient(0, br.y, 0, br.y + br.h);
      grd.addColorStop(0, top); grd.addColorStop(1, bot);
      if (br.type === 'power') {
        g.save();
        g.shadowColor = '#fff3a0'; g.shadowBlur = 10 + Math.sin(performance.now() / 150) * 5;
      }
      roundRect(g, br.x, br.y, br.w, br.h, 4);
      g.fillStyle = grd; g.fill();
      if (br.type === 'power') g.restore();
      g.lineWidth = 1; g.strokeStyle = edge; g.stroke();
      g.fillStyle = 'rgba(255,255,255,0.3)';
      roundRect(g, br.x + 3, br.y + 2, br.w - 6, 4, 2); g.fill();
      g.textAlign = 'center'; g.textBaseline = 'middle';
      const cx = br.x + br.w / 2, cy = br.y + br.h / 2 + 1;
      if (br.type === 'steel') {
        g.fillStyle = '#5a4234';
        for (const [ox, oy] of [[5, 5], [br.w - 5, 5], [5, br.h - 5], [br.w - 5, br.h - 5]]) { g.beginPath(); g.arc(br.x + ox, br.y + oy, 1.6, 0, Math.PI * 2); g.fill(); }
      } else if (br.type === 'tnt') {
        g.fillStyle = '#fff'; g.font = 'bold 10px Arial'; g.fillText('TNT', cx, cy);
      } else if (br.type === 'coin') {
        g.fillStyle = '#8a5a12'; g.font = 'bold 11px "Microsoft YaHei", sans-serif'; g.fillText('🐟', cx, cy);
      } else if (br.type === 'power') {
        g.fillStyle = '#fff'; g.font = 'bold 12px Arial'; g.fillText('?', cx, cy);
      }
      if (br.maxHp >= 2 && br.hp < br.maxHp && br.type !== 'steel') {
        g.strokeStyle = 'rgba(60,30,12,0.75)'; g.lineWidth = 1.2;
        g.beginPath();
        g.moveTo(br.x + br.w * 0.3, br.y + 1); g.lineTo(br.x + br.w * 0.42, br.y + br.h * 0.5); g.lineTo(br.x + br.w * 0.36, br.y + br.h - 1);
        if (br.hp <= br.maxHp - 2) { g.moveTo(br.x + br.w * 0.42, br.y + br.h * 0.5); g.lineTo(br.x + br.w * 0.7, br.y + br.h * 0.35); g.lineTo(br.x + br.w * 0.8, br.y + br.h - 2); }
        g.stroke();
      }
      if (br.flash > 0) { g.fillStyle = `rgba(255,255,255,${br.flash * 5})`; roundRect(g, br.x, br.y, br.w, br.h, 4); g.fill(); }
    }
    function drawPaddle() {
      const sq = padSquash * 3;
      const x = padX - padW / 2 - sq, w = padW + sq * 2, y = PAD_Y + sq * 0.6, h = PAD_H - sq * 0.6;
      const grd = g.createLinearGradient(0, y, 0, y + h);
      const magnet = T.magnet > 0;
      grd.addColorStop(0, magnet ? '#3f8fce' : '#8a5534'); grd.addColorStop(1, magnet ? '#205a8a' : '#5a3219');
      roundRect(g, x, y, w, h, 6);
      g.fillStyle = grd; g.fill();
      g.fillStyle = 'rgba(255,230,190,0.4)';
      roundRect(g, x + 4, y + 2, w - 8, 3, 1.5); g.fill();
      if (T.laser > 0) { g.fillStyle = '#b154d6'; g.fillRect(x + 5, y - 5, 6, 6); g.fillRect(x + w - 11, y - 5, 6, 6); }
      if (T.missile > 0) { g.fillStyle = '#6b8e23'; g.fillRect(x + w / 3 - 3, y - 6, 6, 7); g.fillRect(x + w * 2 / 3 - 3, y - 6, 6, 7); }
    }
    function drawBall(b) {
      const rad = ballR();
      const fireOn = T.fire > 0, bomb = T.bomb > 0;
      // trail
      for (let i = 0; i < b.trail.length; i += 2) {
        const a = i / b.trail.length;
        g.globalAlpha = a * 0.45;
        g.fillStyle = fireOn ? '#ff7a1a' : bomb ? '#5a4a42' : '#f2b37a';
        g.beginPath(); g.arc(b.trail[i], b.trail[i + 1], rad * (0.4 + a * 0.6), 0, Math.PI * 2); g.fill();
      }
      g.globalAlpha = 1;
      if (fireOn) { g.save(); g.shadowColor = '#ff6a00'; g.shadowBlur = 16; }
      const grd = g.createRadialGradient(b.x - 2, b.y - 2, 1, b.x, b.y, rad);
      grd.addColorStop(0, '#fffdf8');
      grd.addColorStop(1, fireOn ? '#ff7a1a' : bomb ? '#6b5a50' : T.slow > 0 ? '#bfd8c6' : T.fast > 0 ? '#f08a8a' : '#f6c89d');
      g.beginPath(); g.arc(b.x, b.y, rad, 0, Math.PI * 2);
      g.fillStyle = grd; g.fill();
      if (fireOn) g.restore();
      g.lineWidth = 1.2; g.strokeStyle = fireOn ? '#c24400' : '#b5562b'; g.stroke();
      if (fireOn && parts.length < MAX_PARTS && Math.random() < 0.8) parts.push({ x: b.x, y: b.y, vx: (Math.random() - 0.5) * 40, vy: (Math.random() - 0.5) * 40, life: 0.35, max: 0.35, size: 3 + Math.random() * 3, color: Math.random() < 0.5 ? '#ffb347' : '#ff6a00', grav: -60 });
    }
    function drawDrop(d) {
      const P = POWERS[d.kind];
      const wob = Math.sin(d.t * 8) * 1.5;
      g.save();
      g.translate(d.x, d.y);
      g.rotate(Math.sin(d.t * 3) * 0.12);
      g.shadowColor = P.bad ? '#ff4d4d' : P.color; g.shadowBlur = 8;
      roundRect(g, -18, -9 + wob * 0.2, 36, 18, 9);
      const grd = g.createLinearGradient(0, -9, 0, 9);
      grd.addColorStop(0, shade(P.color, 0.25)); grd.addColorStop(1, shade(P.color, -0.15));
      g.fillStyle = grd; g.fill();
      g.shadowBlur = 0;
      g.strokeStyle = P.bad ? '#7a1010' : shade(P.color, -0.4); g.lineWidth = 1.4; g.stroke();
      g.fillStyle = '#fff';
      g.font = 'bold 12px "Microsoft YaHei", sans-serif';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(P.label, 0, 1);
      g.restore();
    }
    function drawStatus() {
      const items = Object.keys(T).filter(k => POWERS[k] && POWERS[k].dur);
      g.textBaseline = 'middle'; g.textAlign = 'center';
      items.forEach((k, i) => {
        const P = POWERS[k], x = 24 + i * 34, y = 22, frac = T[k] / P.dur;
        g.beginPath(); g.arc(x, y, 13, 0, Math.PI * 2);
        g.fillStyle = P.bad ? '#d93a3a' : P.color; g.fill();
        g.beginPath(); g.arc(x, y, 15, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac);
        g.strokeStyle = 'rgba(107,63,36,.6)'; g.lineWidth = 3; g.stroke();
        g.fillStyle = '#fff'; g.font = 'bold 11px "Microsoft YaHei", sans-serif';
        g.fillText(P.label, x, y + 0.5);
      });
      if (shields > 0) {
        g.fillStyle = '#1bb3b3'; g.font = 'bold 11px "Microsoft YaHei", sans-serif'; g.textAlign = 'right';
        g.fillText(`护盾 ×${shields}`, GW - 12, 20);
      }
      if (T.x2 > 0) {
        g.fillStyle = '#e6a800'; g.font = 'bold 12px Arial'; g.textAlign = 'right';
        g.fillText('SCORE ×2', GW - 12, shields > 0 ? 38 : 20);
      }
    }
    function draw() {
      const k = scale * dpr;
      g.setTransform(k, 0, 0, k, 0, 0);
      const bg = g.createLinearGradient(0, 0, 0, GH);
      bg.addColorStop(0, '#fff8ec'); bg.addColorStop(1, '#f8e4ca');
      g.fillStyle = bg; g.fillRect(0, 0, GW, GH);
      g.fillStyle = 'rgba(232,121,58,0.07)';
      for (let y = 20; y < GH; y += 40) for (let x = 20 + ((y / 40) % 2) * 20; x < GW; x += 40) { g.beginPath(); g.arc(x, y, 2, 0, Math.PI * 2); g.fill(); }
      g.save();
      if (shake > 0) g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake);
      if (shields > 0) {
        g.strokeStyle = `rgba(27,179,179,${0.55 + Math.sin(performance.now() / 200) * 0.2})`;
        g.lineWidth = 4; g.beginPath(); g.moveTo(0, NET_Y); g.lineTo(GW, NET_Y); g.stroke();
      }
      for (const br of bricks) if (br.alive) drawBrick(br);
      for (const r of rings) {
        g.globalAlpha = Math.max(0, r.life / 0.45);
        g.strokeStyle = '#ff8a2a'; g.lineWidth = 5 * g.globalAlpha + 1;
        g.beginPath(); g.arc(r.x, r.y, r.r, 0, Math.PI * 2); g.stroke();
      }
      g.globalAlpha = 1;
      g.lineCap = 'round';
      for (const bm of beams) {
        g.strokeStyle = '#b154d6'; g.lineWidth = 3;
        g.beginPath(); g.moveTo(bm.x, bm.y); g.lineTo(bm.x, bm.y + 14); g.stroke();
      }
      for (const m of missiles) {
        g.save(); g.translate(m.x, m.y); g.rotate(Math.atan2(m.vy, m.vx));
        g.fillStyle = '#6b8e23'; g.fillRect(-6, -2.5, 12, 5);
        g.fillStyle = '#e8553a'; g.beginPath(); g.moveTo(6, -2.5); g.lineTo(10, 0); g.lineTo(6, 2.5); g.fill();
        g.restore();
      }
      for (const bo of bolts) {
        g.globalAlpha = bo.life / 0.35;
        for (const [wdt, col] of [[6, 'rgba(120,160,255,.5)'], [2, '#fff']]) {
          g.strokeStyle = col; g.lineWidth = wdt;
          g.beginPath(); bo.pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); g.stroke();
        }
      }
      g.globalAlpha = 1;
      for (const d of drops) drawDrop(d);
      drawPaddle();
      for (const b of balls) drawBall(b);
      for (const p of parts) {
        g.globalAlpha = clamp(p.life / p.max, 0, 1);
        g.fillStyle = p.color;
        if (p.spin) {
          g.save(); g.translate(p.x, p.y); g.rotate(p.life * 6); g.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2); g.restore();
        } else g.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
      }
      g.globalAlpha = 1;
      g.textAlign = 'center'; g.textBaseline = 'middle';
      for (const f of floats) {
        g.globalAlpha = clamp(f.life / f.max, 0, 1);
        g.font = f.big ? 'bold 16px "Microsoft YaHei", sans-serif' : 'bold 12px "Microsoft YaHei", sans-serif';
        g.lineWidth = 3; g.strokeStyle = 'rgba(255,255,255,.9)'; g.strokeText(f.text, f.x, f.y);
        g.fillStyle = f.color; g.fillText(f.text, f.x, f.y);
      }
      g.globalAlpha = 1;
      g.restore();
      // combo banner
      if (combo >= 5) {
        const pop = comboShow > 0 ? 1 + comboShow * 0.35 : 1;
        g.save();
        g.translate(GW / 2, GH * 0.62);
        g.scale(pop, pop);
        g.font = 'bold 26px Arial';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.lineWidth = 5; g.strokeStyle = '#fff';
        const txt = `COMBO ×${combo}`;
        g.strokeText(txt, 0, 0);
        g.fillStyle = combo >= 30 ? '#e8475f' : combo >= 15 ? '#e8793a' : '#e0a526';
        g.fillText(txt, 0, 0);
        g.restore();
      }
      if (flash > 0) { g.fillStyle = `rgba(255,250,235,${flash})`; g.fillRect(0, 0, GW, GH); }
      drawStatus();
      if (state === 'ready' && !paused) {
        g.fillStyle = 'rgba(107,63,36,0.78)';
        g.font = '14px "Microsoft YaHei", sans-serif';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText(`第 ${levelNum} 关「${level.name}」 · 按空格或点击发射`, GW / 2, PAD_Y - 60);
      }
    }

    // ---------- loop ----------
    function frame(t) {
      rafId = requestAnimationFrame(frame);
      const dt = Math.min(1 / 30, Math.max(0, (t - lastT) / 1000));
      lastT = t;
      if (!ctx.isActive()) {
        if (state === 'play' && !paused) setPaused(true);
        return;
      }
      if (!paused) update(dt);
      draw();
    }

    // ---------- input ----------
    let keyFire = false, mouseDown = false;
    const toLogicalX = cx => { const r = canvas.getBoundingClientRect(); return (cx - r.left) / (r.width || 1) * GW; };
    function action() {
      if (paused) return setPaused(false);
      if (ovAction && (state === 'clear' || state === 'over')) return ovAction();
      if (state === 'ready') return launch();
      if (state === 'play') { if (!launch()) fire(); }
    }
    function onMouseMove(e) { if (!paused) mouseX = toLogicalX(e.clientX); }
    function onMouseDown(e) { if (e.button !== 0 || paused) return; mouseDown = true; mouseX = toLogicalX(e.clientX); sfx.unlock(); action(); }
    function onMouseUp() { mouseDown = false; }
    function onKeyDown(e) {
      if (!ctx.isActive()) return;
      const k = e.key;
      if (k === 'ArrowLeft') { keyL = true; e.preventDefault(); }
      else if (k === 'ArrowRight') { keyR = true; e.preventDefault(); }
      else if (k === ' ' || k === 'Spacebar') {
        e.preventDefault();
        keyFire = true;
        if (e.repeat) return;
        sfx.unlock();
        action();
      } else if (k === 'p' || k === 'P' || k === 'Escape') {
        e.preventDefault();
        if (state === 'play' || state === 'ready') setPaused(!paused);
      }
    }
    function onKeyUp(e) {
      if (e.key === 'ArrowLeft') keyL = false;
      else if (e.key === 'ArrowRight') keyR = false;
      else if (e.key === ' ') keyFire = false;
    }
    function onBlur() { keyL = keyR = keyFire = mouseDown = false; }
    function onPauseBtn() { pauseBtn.blur(); if (state === 'play' || state === 'ready') setPaused(!paused); }
    function onNewBtn() { newBtn.blur(); newGame(); }
    function onOvBtn() { ovBtn.blur(); if (ovAction) ovAction(); }
    function onMute() { muteBtn.blur(); muted = !muted; ctx.store.set('muted', muted); updateHud(); }

    canvas.addEventListener('mousemove', onMouseMove);
    canvas.addEventListener('mousedown', onMouseDown);
    window.addEventListener('mouseup', onMouseUp);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
    pauseBtn.addEventListener('click', onPauseBtn);
    newBtn.addEventListener('click', onNewBtn);
    ovBtn.addEventListener('click', onOvBtn);
    muteBtn.addEventListener('click', onMute);

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') { ro = new ResizeObserver(() => fit()); ro.observe(el.parentElement || el); }
    else window.addEventListener('resize', fit);

    newGame();
    fit();
    lastT = performance.now();
    rafId = requestAnimationFrame(frame);

    cleanup = () => {
      cancelAnimationFrame(rafId);
      if (score > best) { best = score; ctx.store.set('best', best); }
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      canvas.removeEventListener('mousemove', onMouseMove);
      canvas.removeEventListener('mousedown', onMouseDown);
      window.removeEventListener('mouseup', onMouseUp);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      pauseBtn.removeEventListener('click', onPauseBtn);
      newBtn.removeEventListener('click', onNewBtn);
      ovBtn.removeEventListener('click', onOvBtn);
      muteBtn.removeEventListener('click', onMute);
      sfx.close();
      root.remove();
    };
    // test hook: lets the automated smoke test grant power-ups
    root._bo = { applyPower: k => applyPower(k, padX), launch, get state() { return { balls: balls.length, bricks: bricks.filter(b => b.alive).length, score, T: Object.keys(T), shields }; } };
  }

  Hub.register({
    id: 'breakout',
    title: '打砖块',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><rect x="3" y="4" width="5" height="3" rx="1"/><rect x="9.5" y="4" width="5" height="3" rx="1" fill="currentColor" fill-opacity=".3"/><rect x="16" y="4" width="5" height="3" rx="1"/><rect x="6" y="9" width="5" height="3" rx="1" fill="currentColor" fill-opacity=".3"/><rect x="13" y="9" width="5" height="3" rx="1"/><circle cx="14" cy="16" r="1.6" fill="currentColor" stroke="none"/><path d="M7 20.5h10"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
