// 俄罗斯方块 — Tetris (modern guideline) module for the hub. See ../MODULES.md for the contract.
(function () {
  const COLS = 10, VISIBLE = 20, HIDDEN = 2, ROWS = VISIBLE + HIDDEN, CELL = 26;
  const W = COLS * CELL, H = VISIBLE * CELL;
  const SIDE_W = 96, HOLD_H = 72;
  const NEXT_SLOTS = [{ h: 72, c: 20 }, { h: 57, c: 15 }, { h: 57, c: 15 }, { h: 57, c: 15 }, { h: 57, c: 15 }];
  const NEXT_H = NEXT_SLOTS.reduce((a, s) => a + s.h, 0);
  const DAS = 150, ARR = 40, LOCK_MS = 500, MOVE_LIMIT = 15, CLEAR_MS = 360;
  const LINE_PTS = [0, 100, 300, 500, 800];
  const CLEAR_NAMES = ['', '', '双消！', '三消！', '四消！'];

  const COLORS = {
    I: '#35c3de', O: '#f3c530', T: '#a45ee5', S: '#58c457',
    Z: '#e74c4c', J: '#4a78e6', L: '#f0892c'
  };
  const BASE = {
    I: [[0, 0, 0, 0], [1, 1, 1, 1], [0, 0, 0, 0], [0, 0, 0, 0]],
    J: [[1, 0, 0], [1, 1, 1], [0, 0, 0]],
    L: [[0, 0, 1], [1, 1, 1], [0, 0, 0]],
    O: [[1, 1], [1, 1]],
    S: [[0, 1, 1], [1, 1, 0], [0, 0, 0]],
    T: [[0, 1, 0], [1, 1, 1], [0, 0, 0]],
    Z: [[1, 1, 0], [0, 1, 1], [0, 0, 0]]
  };
  const TYPES = Object.keys(BASE);

  // Precompute cell lists for the 4 rotation states (SRS: plain matrix rotation in the bounding box).
  const SHAPES = {};
  for (const t of TYPES) {
    let m = BASE[t];
    SHAPES[t] = [];
    for (let r = 0; r < 4; r++) {
      const cells = [];
      for (let y = 0; y < m.length; y++) for (let x = 0; x < m.length; x++) if (m[y][x]) cells.push([x, y]);
      SHAPES[t].push(cells);
      const n = m.length;
      m = m.map((row, y) => row.map((_, x) => m[n - 1 - x][y]));
    }
  }

  // SRS kick tables, (x, y) with y pointing UP (as in the guideline). Key = from + to.
  const KICK_JLSTZ = {
    '01': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '10': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '12': [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    '21': [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    '23': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    '32': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '30': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    '03': [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]]
  };
  const KICK_I = {
    '01': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '10': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '12': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
    '21': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '23': [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    '32': [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    '30': [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    '03': [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]]
  };

  function hexRgb(h) {
    const n = parseInt(h.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  // amt > 0 mixes toward white, < 0 toward black
  function shade(hex, amt, alpha) {
    const c = hexRgb(hex).map(v => Math.round(amt >= 0 ? v + (255 - v) * amt : v * (1 + amt)));
    return alpha == null ? `rgb(${c[0]},${c[1]},${c[2]})` : `rgba(${c[0]},${c[1]},${c[2]},${alpha})`;
  }

  function gravityMs(level) {
    const l = Math.min(level, 20) - 1;
    return Math.pow(0.8 - l * 0.007, l) * 1000;
  }

  let cleanup = null;

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'tt-root';
    root.innerHTML = `
      <div class="tt-side tt-left">
        <div class="tt-panel">
          <div class="tt-cap">暂存 <span>C</span></div>
          <canvas class="tt-hold"></canvas>
        </div>
        <div class="tt-panel tt-stats">
          <div class="tt-stat"><span>得分</span><b class="tt-score">0</b></div>
          <div class="tt-stat"><span>等级</span><b class="tt-level">1</b></div>
          <div class="tt-stat"><span>行数</span><b class="tt-lines">0</b></div>
          <div class="tt-stat"><span>最佳</span><b class="tt-best">0</b></div>
        </div>
      </div>
      <div class="tt-board">
        <canvas class="tt-field"></canvas>
        <div class="tt-overlay">
          <div class="tt-card">
            <div class="tt-title"></div>
            <div class="tt-sub"></div>
            <div class="tt-keys">
              <div><kbd>←</kbd><kbd>→</kbd><span>左右移动</span></div>
              <div><kbd>↓</kbd><span>软降</span></div>
              <div><kbd>空格</kbd><span>硬降</span></div>
              <div><kbd>↑</kbd><kbd>X</kbd><span>顺时针旋转</span></div>
              <div><kbd>Z</kbd><span>逆时针旋转</span></div>
              <div><kbd>C</kbd><kbd>Shift</kbd><span>暂存</span></div>
              <div><kbd>P</kbd><kbd>Esc</kbd><span>暂停</span></div>
            </div>
            <button type="button" class="tt-btn tt-primary tt-ov-btn"></button>
          </div>
        </div>
      </div>
      <div class="tt-side tt-right">
        <div class="tt-panel">
          <div class="tt-cap">下一个</div>
          <canvas class="tt-next"></canvas>
        </div>
        <button type="button" class="tt-btn tt-toggle">开始</button>
      </div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const field = $('.tt-field'), holdCv = $('.tt-hold'), nextCv = $('.tt-next');
    const g = field.getContext('2d'), hg = holdCv.getContext('2d'), ng = nextCv.getContext('2d');
    const scoreEl = $('.tt-score'), levelEl = $('.tt-level'), linesEl = $('.tt-lines'), bestEl = $('.tt-best');
    const overlay = $('.tt-overlay'), ovTitle = $('.tt-title'), ovSub = $('.tt-sub'), ovKeys = $('.tt-keys'), ovBtn = $('.tt-ov-btn');
    const toggleBtn = $('.tt-toggle');

    const getBest = () => ctx.store.get('best', 0) || 0;

    // ---------- state ----------
    let board, bag, queue, cur, hold, canHold, score, lines, level, state;
    let gravAcc, lockTimer, resets, lowestY, landed, clearing, banner;
    let held = { left: false, right: false }, softDown = false;
    let dasDir = 0, dasCharge = 0, arrDone = 0;
    let dirty = true, sideDirty = true;
    // state: 'ready' | 'running' | 'paused' | 'over'

    function reset() {
      board = Array.from({ length: ROWS }, () => new Array(COLS).fill(null));
      bag = [];
      queue = [];
      refillQueue();
      cur = null;
      hold = null;
      canHold = true;
      score = 0; lines = 0; level = 1;
      clearing = null; banner = null;
      releaseKeys();
      state = 'ready';
      updateHud();
      showOverlay();
      dirty = sideDirty = true;
    }

    function refillQueue() {
      while (queue.length < 6) {
        if (!bag.length) {
          bag = TYPES.slice();
          for (let i = bag.length - 1; i > 0; i--) {
            const j = (Math.random() * (i + 1)) | 0;
            [bag[i], bag[j]] = [bag[j], bag[i]];
          }
        }
        queue.push(bag.pop());
      }
    }

    function releaseKeys() {
      held.left = held.right = false;
      softDown = false;
      dasDir = 0; dasCharge = 0; arrDone = 0;
    }

    function collide(type, rot, x, y) {
      for (const [cx, cy] of SHAPES[type][rot]) {
        const bx = x + cx, by = y + cy;
        if (bx < 0 || bx >= COLS || by >= ROWS) return true;
        if (by >= 0 && board[by][bx]) return true;
      }
      return false;
    }

    function spawn(type) {
      const p = { type, rot: 0, x: type === 'O' ? 4 : 3, y: 0 };
      if (collide(p.type, p.rot, p.x, p.y)) { cur = null; gameOver(); return false; }
      if (!collide(p.type, p.rot, p.x, p.y + 1)) p.y++; // guideline: drop one row on spawn if possible
      cur = p;
      gravAcc = 0; lockTimer = 0; resets = 0; landed = false; lowestY = p.y;
      dirty = sideDirty = true;
      return true;
    }

    function spawnNext() {
      const t = queue.shift();
      refillQueue();
      canHold = true;
      spawn(t);
    }

    function afterMove() {
      if (cur.y > lowestY) { lowestY = cur.y; resets = 0; lockTimer = 0; landed = false; }
      else if (landed && resets < MOVE_LIMIT) { resets++; lockTimer = 0; }
      dirty = true;
    }

    function tryMove(dx, dy) {
      if (!cur || collide(cur.type, cur.rot, cur.x + dx, cur.y + dy)) return false;
      cur.x += dx; cur.y += dy;
      afterMove();
      return true;
    }

    function rotate(dir) {
      if (!cur) return false;
      if (cur.type === 'O') return false;
      const from = cur.rot, to = (from + dir + 4) % 4;
      const kicks = (cur.type === 'I' ? KICK_I : KICK_JLSTZ)['' + from + to];
      for (const [kx, ky] of kicks) {
        const nx = cur.x + kx, ny = cur.y - ky;
        if (!collide(cur.type, to, nx, ny)) {
          cur.rot = to; cur.x = nx; cur.y = ny;
          afterMove();
          return true;
        }
      }
      return false;
    }

    function dropDistance() {
      let d = 0;
      while (!collide(cur.type, cur.rot, cur.x, cur.y + d + 1)) d++;
      return d;
    }

    function hardDrop() {
      if (!cur) return;
      const d = dropDistance();
      cur.y += d;
      score += d * 2;
      lockPiece();
    }

    function doHold() {
      if (!cur || !canHold) return;
      const t = cur.type;
      if (hold) {
        const h = hold;
        hold = t;
        spawn(h);
      } else {
        hold = t;
        const n = queue.shift();
        refillQueue();
        spawn(n);
      }
      canHold = false;
      sideDirty = true;
    }

    function lockPiece() {
      let allHidden = true;
      for (const [cx, cy] of SHAPES[cur.type][cur.rot]) {
        const bx = cur.x + cx, by = cur.y + cy;
        if (by >= 0) board[by][bx] = cur.type;
        if (by >= HIDDEN) allHidden = false;
      }
      cur = null;
      dirty = true;
      if (allHidden) { updateHud(); gameOver(); return; }

      const full = [];
      for (let y = 0; y < ROWS; y++) if (board[y].every(Boolean)) full.push(y);
      if (full.length) {
        const n = full.length;
        score += LINE_PTS[n] * level;
        lines += n;
        const newLevel = 1 + Math.floor(lines / 10);
        if (newLevel > level) {
          level = newLevel;
          ctx.toast && ctx.toast('等级提升！当前等级 ' + level);
        }
        clearing = { rows: full, t: 0 };
        banner = CLEAR_NAMES[n] ? { text: CLEAR_NAMES[n], t: 0 } : null;
        updateHud();
      } else {
        updateHud();
        spawnNext();
      }
    }

    function finishClear() {
      const rows = new Set(clearing.rows);
      board = board.filter((_, y) => !rows.has(y));
      while (board.length < ROWS) board.unshift(new Array(COLS).fill(null));
      clearing = null;
      spawnNext();
    }

    function gameOver() {
      if (ctx.reward && score >= 1000) ctx.reward(Math.min(20, Math.floor(score / 1000)), '俄罗斯方块结算');
      const newBest = score > getBest() && score > 0;
      if (newBest) {
        ctx.store.set('best', score);
        ctx.say('俄罗斯方块新纪录！' + score);
      }
      releaseKeys();
      setState('over', { newBest });
    }

    // ---------- HUD / overlay ----------
    let hudCache = '';
    function updateHud() {
      const best = Math.max(getBest(), score);
      const key = score + '|' + level + '|' + lines + '|' + best + '|' + state;
      if (key === hudCache) return;
      hudCache = key;
      scoreEl.textContent = score;
      levelEl.textContent = level;
      linesEl.textContent = lines;
      bestEl.textContent = best;
      toggleBtn.textContent = state === 'running' ? '暂停' : state === 'paused' ? '继续' : state === 'over' ? '再来一局' : '开始';
    }

    function showOverlay(extra) {
      if (state === 'running') { overlay.classList.add('hidden'); return; }
      overlay.classList.remove('hidden');
      ovKeys.style.display = state === 'ready' || state === 'paused' ? '' : 'none';
      if (state === 'ready') {
        ovTitle.textContent = '俄罗斯方块';
        ovSub.textContent = '按 回车 / 空格 开始';
        ovBtn.textContent = '开始游戏';
      } else if (state === 'paused') {
        ovTitle.textContent = '已暂停';
        ovSub.textContent = '按 P / Esc 继续';
        ovBtn.textContent = '继续';
      } else if (state === 'over') {
        ovTitle.textContent = '游戏结束';
        ovSub.textContent = `得分 ${score} · 行数 ${lines}` + (extra && extra.newBest ? ' · 新纪录！' : ` · 最佳 ${getBest()}`);
        ovBtn.textContent = '再来一局';
      }
    }

    function setState(s, extra) {
      state = s;
      last = 0;
      if (s !== 'running') releaseKeys();
      updateHud();
      showOverlay(extra);
      dirty = sideDirty = true;
    }

    function start() {
      reset();
      setState('running');
      spawnNext();
    }

    function primaryAction() {
      if (state === 'ready' || state === 'over') start();
      else if (state === 'running') setState('paused');
      else if (state === 'paused') setState('running');
    }

    // ---------- update ----------
    function update(dt) {
      if (banner) { banner.t += dt; if (banner.t > 900) banner = null; dirty = true; }
      if (clearing) {
        clearing.t += dt;
        dirty = true;
        if (clearing.t >= CLEAR_MS) finishClear();
        return;
      }
      if (!cur) return;

      // DAS / ARR
      if (dasDir) {
        dasCharge += dt;
        if (dasCharge >= DAS) {
          const n = Math.floor((dasCharge - DAS) / ARR) + 1;
          while (arrDone < n) {
            if (!tryMove(dasDir, 0)) { arrDone = n; break; }
            arrDone++;
          }
        }
      }

      // gravity / lock
      if (collide(cur.type, cur.rot, cur.x, cur.y + 1)) {
        landed = true;
        gravAcc = 0;
        lockTimer += dt;
        if (lockTimer >= LOCK_MS) lockPiece();
      } else {
        const gMs = gravityMs(level);
        const interval = softDown ? Math.min(gMs, Math.max(gMs / 20, 5)) : gMs;
        gravAcc += dt;
        let scored = false;
        while (gravAcc >= interval) {
          gravAcc -= interval;
          if (!collide(cur.type, cur.rot, cur.x, cur.y + 1)) {
            cur.y++;
            if (softDown) { score += 1; scored = true; }
            afterMove();
          } else { gravAcc = 0; break; }
        }
        if (scored) updateHud();
      }
    }

    // ---------- rendering ----------
    let dpr = 0;
    const blockCache = new Map();

    function sizeCanvas(c, w, h) {
      c.width = Math.round(w * dpr);
      c.height = Math.round(h * dpr);
      c.style.width = w + 'px';
      c.style.height = h + 'px';
    }
    function setupCanvas() {
      const r = window.devicePixelRatio || 1;
      if (r === dpr) return;
      dpr = r;
      blockCache.clear();
      sizeCanvas(field, W, H);
      sizeCanvas(holdCv, SIDE_W, HOLD_H);
      sizeCanvas(nextCv, SIDE_W, NEXT_H);
      dirty = sideDirty = true;
    }

    function paintBlock(c, s, color) {
      const grad = c.createLinearGradient(0, 0, s, s);
      grad.addColorStop(0, shade(color, 0.28));
      grad.addColorStop(0.5, color);
      grad.addColorStop(1, shade(color, -0.18));
      c.fillStyle = grad;
      c.fillRect(0, 0, s, s);
      const b = Math.max(2, s * 0.15);
      const poly = (pts, fill) => {
        c.fillStyle = fill;
        c.beginPath();
        c.moveTo(pts[0], pts[1]);
        for (let i = 2; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1]);
        c.closePath();
        c.fill();
      };
      poly([0, 0, s, 0, s - b, b, b, b], shade(color, 0.5));             // top
      poly([0, 0, b, b, b, s - b, 0, s], shade(color, 0.3));             // left
      poly([0, s, b, s - b, s - b, s - b, s, s], shade(color, -0.35));   // bottom
      poly([s, 0, s, s, s - b, s - b, s - b, b], shade(color, -0.2));    // right
      // glint
      c.fillStyle = 'rgba(255,255,255,0.45)';
      c.fillRect(b + s * 0.06, b + s * 0.06, s * 0.2, s * 0.08);
      c.strokeStyle = 'rgba(0,0,0,0.28)';
      c.lineWidth = 1;
      c.strokeRect(0.5, 0.5, s - 1, s - 1);
    }

    function getBlock(type, size) {
      const key = type + '|' + size;
      let c = blockCache.get(key);
      if (!c) {
        c = document.createElement('canvas');
        const px = Math.max(1, Math.round(size * dpr));
        c.width = c.height = px;
        const cc = c.getContext('2d');
        cc.scale(px / size, px / size);
        paintBlock(cc, size, COLORS[type]);
        blockCache.set(key, c);
      }
      return c;
    }

    function drawBlock(c, type, x, y, size) {
      c.drawImage(getBlock(type, size), x, y, size, size);
    }

    function drawField() {
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      const bg = g.createLinearGradient(0, 0, 0, H);
      bg.addColorStop(0, '#2c2019');
      bg.addColorStop(1, '#3a2a1f');
      g.fillStyle = bg;
      g.fillRect(0, 0, W, H);
      // subtle grid
      g.strokeStyle = 'rgba(255,240,220,0.06)';
      g.lineWidth = 1;
      g.beginPath();
      for (let x = 1; x < COLS; x++) { g.moveTo(x * CELL + 0.5, 0); g.lineTo(x * CELL + 0.5, H); }
      for (let y = 1; y < VISIBLE; y++) { g.moveTo(0, y * CELL + 0.5); g.lineTo(W, y * CELL + 0.5); }
      g.stroke();

      const over = state === 'over';
      // stack
      for (let y = HIDDEN; y < ROWS; y++) {
        for (let x = 0; x < COLS; x++) {
          const t = board[y][x];
          if (t) drawBlock(g, t, x * CELL, (y - HIDDEN) * CELL, CELL);
        }
      }
      if (over) {
        g.fillStyle = 'rgba(40,28,20,0.45)';
        g.fillRect(0, 0, W, H);
      }

      // line clear flash
      if (clearing) {
        const p = clearing.t / CLEAR_MS;
        const on = Math.floor(clearing.t / 60) % 2 === 0;
        for (const y of clearing.rows) {
          if (y < HIDDEN) continue;
          const py = (y - HIDDEN) * CELL;
          g.fillStyle = `rgba(255,250,235,${(on ? 0.85 : 0.45) * (1 - p * 0.5)})`;
          const shrink = p * W / 2;
          g.fillRect(shrink, py, W - shrink * 2, CELL);
        }
      }

      if (cur) {
        // ghost
        const gd = dropDistance();
        if (gd > 0) {
          const col = COLORS[cur.type];
          g.fillStyle = shade(col, 0, 0.16);
          g.strokeStyle = shade(col, 0.2, 0.75);
          g.lineWidth = 1.5;
          for (const [cx, cy] of SHAPES[cur.type][cur.rot]) {
            const by = cur.y + gd + cy;
            if (by < HIDDEN) continue;
            const px = (cur.x + cx) * CELL, py = (by - HIDDEN) * CELL;
            g.fillRect(px + 1, py + 1, CELL - 2, CELL - 2);
            g.strokeRect(px + 2, py + 2, CELL - 4, CELL - 4);
          }
        }
        // active piece (dim slightly as lock delay runs out)
        const fade = landed ? Math.min(1, lockTimer / LOCK_MS) : 0;
        for (const [cx, cy] of SHAPES[cur.type][cur.rot]) {
          const by = cur.y + cy;
          drawBlock(g, cur.type, (cur.x + cx) * CELL, (by - HIDDEN) * CELL, CELL);
        }
        if (fade > 0) {
          g.fillStyle = `rgba(0,0,0,${fade * 0.22})`;
          for (const [cx, cy] of SHAPES[cur.type][cur.rot]) {
            g.fillRect((cur.x + cx) * CELL, (cur.y + cy - HIDDEN) * CELL, CELL, CELL);
          }
        }
      }

      if (banner) {
        const p = banner.t / 900;
        g.save();
        g.globalAlpha = p < 0.7 ? 1 : 1 - (p - 0.7) / 0.3;
        g.font = 'bold 30px "Microsoft YaHei", "PingFang SC", sans-serif';
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        const y = H * 0.38 - p * 24;
        g.lineWidth = 5;
        g.strokeStyle = '#6b3f24';
        g.strokeText(banner.text, W / 2, y);
        g.fillStyle = '#ffd27a';
        g.fillText(banner.text, W / 2, y);
        g.restore();
      }
    }

    function drawMini(c, type, cx, cy, size) {
      const cells = SHAPES[type][0];
      let minX = 9, maxX = -1, minY = 9, maxY = -1;
      for (const [x, y] of cells) {
        minX = Math.min(minX, x); maxX = Math.max(maxX, x);
        minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      }
      const w = (maxX - minX + 1) * size, h = (maxY - minY + 1) * size;
      const ox = Math.round(cx - w / 2), oy = Math.round(cy - h / 2);
      for (const [x, y] of cells) drawBlock(c, type, ox + (x - minX) * size, oy + (y - minY) * size, size);
    }

    function drawSide() {
      hg.setTransform(dpr, 0, 0, dpr, 0, 0);
      hg.clearRect(0, 0, SIDE_W, HOLD_H);
      if (hold) {
        hg.globalAlpha = canHold ? 1 : 0.35;
        drawMini(hg, hold, SIDE_W / 2, HOLD_H / 2, 18);
        hg.globalAlpha = 1;
      }
      ng.setTransform(dpr, 0, 0, dpr, 0, 0);
      ng.clearRect(0, 0, SIDE_W, NEXT_H);
      if (state === 'ready') return;
      let y = 0;
      NEXT_SLOTS.forEach((slot, i) => {
        const t = queue[i];
        if (t) drawMini(ng, t, SIDE_W / 2, y + slot.h / 2, slot.c);
        y += slot.h;
      });
    }

    // ---------- loop ----------
    let raf = 0, last = 0;
    function frame(now) {
      raf = requestAnimationFrame(frame);
      setupCanvas();
      const dt = last ? Math.min(now - last, 100) : 0;
      last = now;
      if (state === 'running') {
        if (!ctx.isActive()) setState('paused');
        else { update(dt); dirty = true; }
      }
      if (dirty) { dirty = false; drawField(); }
      if (sideDirty) { sideDirty = false; drawSide(); }
    }

    // ---------- input ----------
    function isTyping(t) {
      return t && ((t.tagName === 'INPUT' && t.type !== 'checkbox') || t.tagName === 'TEXTAREA' || t.isContentEditable);
    }

    function onKeyDown(e) {
      if (!ctx.isActive()) return;
      if (isTyping(e.target)) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      const code = e.code;
      const handled = ['ArrowLeft', 'ArrowRight', 'ArrowDown', 'ArrowUp', 'Space', 'KeyX', 'KeyZ', 'KeyC',
        'ShiftLeft', 'ShiftRight', 'KeyP', 'Escape', 'Enter'];
      if (!handled.includes(code)) return;
      e.preventDefault();
      if (document.activeElement && root.contains(document.activeElement)) document.activeElement.blur();

      if (state === 'ready' || state === 'over') {
        if (!e.repeat && (code === 'Enter' || code === 'Space')) start();
        return;
      }
      if (state === 'paused') {
        if (!e.repeat && (code === 'KeyP' || code === 'Escape' || code === 'Enter')) setState('running');
        return;
      }
      // running
      switch (code) {
        case 'ArrowLeft':
        case 'ArrowRight': {
          if (e.repeat) return;
          const d = code === 'ArrowLeft' ? -1 : 1;
          if (d < 0) held.left = true; else held.right = true;
          dasDir = d; dasCharge = 0; arrDone = 0;
          tryMove(d, 0);
          break;
        }
        case 'ArrowDown': softDown = true; break;
        case 'ArrowUp':
        case 'KeyX': if (!e.repeat) rotate(1); break;
        case 'KeyZ': if (!e.repeat) rotate(-1); break;
        case 'KeyC':
        case 'ShiftLeft':
        case 'ShiftRight': if (!e.repeat) doHold(); break;
        case 'Space': if (!e.repeat) hardDrop(); break;
        case 'KeyP':
        case 'Escape': if (!e.repeat) setState('paused'); break;
      }
    }

    function onKeyUp(e) {
      if (!ctx.isActive()) return;
      const code = e.code;
      if (code === 'ArrowDown') softDown = false;
      else if (code === 'ArrowLeft' || code === 'ArrowRight') {
        const d = code === 'ArrowLeft' ? -1 : 1;
        if (d < 0) held.left = false; else held.right = false;
        if (dasDir === d) {
          const other = d < 0 ? held.right : held.left;
          dasDir = other ? -d : 0;
          dasCharge = 0; arrDone = 0;
        }
      }
    }

    function onBlur() {
      releaseKeys();
      if (state === 'running') setState('paused');
    }

    function onToggle(e) { e.currentTarget.blur(); primaryAction(); }

    toggleBtn.addEventListener('click', onToggle);
    ovBtn.addEventListener('click', onToggle);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);

    reset();
    setupCanvas();
    raf = requestAnimationFrame(frame);

    cleanup = () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      toggleBtn.removeEventListener('click', onToggle);
      ovBtn.removeEventListener('click', onToggle);
      blockCache.clear();
      root.remove();
    };
  }

  Hub.register({
    id: 'tetris',
    title: '俄罗斯方块',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="4" width="5.5" height="5.5" rx="1"/><rect x="9.25" y="4" width="5.5" height="5.5" rx="1"/><rect x="15.5" y="4" width="5.5" height="5.5" rx="1"/><rect x="9.25" y="10.25" width="5.5" height="5.5" rx="1"/><rect x="3" y="14.5" width="5.5" height="5.5" rx="1" opacity=".55"/><rect x="15.5" y="14.5" width="5.5" height="5.5" rx="1" opacity=".55"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
