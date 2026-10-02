// 弹珠台 physics + table geometry. No DOM here so it can be tested in node.
// Coordinates: table 420 x 640, y grows downward (gravity +y).
(function (root) {
  const W = 420, H = 640;
  const BALL_R = 9;
  const GRAVITY = 900;
  const MAX_V = 2200;

  // ---- geometry helpers ----
  function arcPts(cx, cy, r, a0, a1, n) {
    const pts = [];
    for (let i = 0; i <= n; i++) {
      const a = a0 + (a1 - a0) * i / n;
      pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
    }
    return pts;
  }
  const poly = (pts, props) => pts.slice(1).map((p, i) => Object.assign({ a: pts[i], b: p, e: 0.45 }, props || {}));

  // ---- table layout ----
  // launch lane on the right: x 386..414, plunger at bottom
  const LANE_X = 386;
  function buildTable() {
    const walls = [];
    // outer shell: left wall, top dome, right wall (outside the lane)
    walls.push(...poly([[12, 520], [12, 150]]));
    walls.push(...poly(arcPts(213, 150, 201, Math.PI, Math.PI * 2, 28)));      // dome from (12,150) to (414,150)
    walls.push(...poly([[414, 150], [414, 640]]));
    // lane divider (inner wall of the launch lane), open at the top so the ball enters the table
    walls.push(...poly([[LANE_X, 640], [LANE_X, 190]], { lane: true }));
    // bottom funnel to the flippers
    walls.push(...poly([[12, 520], [118, 578]]));
    walls.push(...poly([[LANE_X, 520], [282, 578]]));
    // inlane guides (outlane on the outside)
    walls.push(...poly([[44, 430], [44, 505], [118, 548]]));
    walls.push(...poly([[354, 430], [354, 505], [282, 548]]));
    // top rollover lane separators
    for (const x of [150, 200, 250, 300]) walls.push(...poly([[x, 58], [x, 92]], { e: 0.3 }));
    // left orbit guide
    walls.push(...poly(arcPts(213, 175, 150, Math.PI * 1.05, Math.PI * 1.35, 6), { e: 0.3 }));
    // slingshots (kicking faces)
    const slingL = { a: [70, 440], b: [106, 505], e: 0.3, kick: 520, sling: 'L' };
    const slingR = { a: [328, 440], b: [292, 505], e: 0.3, kick: 520, sling: 'R' };
    walls.push(slingL, slingR);
    walls.push(...poly([[70, 440], [70, 490], [106, 505]], { e: 0.3 }));
    walls.push(...poly([[328, 440], [328, 490], [292, 505]], { e: 0.3 }));

    const bumpers = [
      { x: 160, y: 205, r: 22, kick: 620, lit: 0 },
      { x: 262, y: 205, r: 22, kick: 620, lit: 0 },
      { x: 211, y: 270, r: 22, kick: 620, lit: 0 }
    ];
    const targets = [0, 1, 2].map(i => ({ x: 88 + i * 26, y: 330 - i * 20, w: 20, h: 6, down: false, lit: 0 }));
    const rollovers = [0, 1, 2].map(i => ({ x: 175 + i * 50, y: 75, r: 10, lit: false }));
    const spinner = { x: 330, y: 300, w: 34, angle: 0, spin: 0 };
    // flippers pivot near the bottom; length 70
    const flippers = [
      { x: 122, y: 580, len: 72, rest: 0.52, up: -0.5, ang: 0.52, w: 0, side: 1, pressed: false },
      { x: 278, y: 580, len: 72, rest: Math.PI - 0.52, up: Math.PI + 0.5, ang: Math.PI - 0.52, w: 0, side: -1, pressed: false }
    ];
    return { walls, bumpers, targets, rollovers, spinner, flippers };
  }

  // ---- collision ----
  function closestOnSeg(px, py, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / (dx * dx + dy * dy || 1)));
    return [a[0] + dx * t, a[1] + dy * t, t];
  }
  // reflect ball off a static point contact; returns impact speed along the normal
  function bounce(ball, cx, cy, e, surfVx, surfVy) {
    let nx = ball.x - cx, ny = ball.y - cy;
    const d = Math.hypot(nx, ny) || 1e-6;
    nx /= d; ny /= d;
    ball.x = cx + nx * (BALL_R + 0.01);
    ball.y = cy + ny * (BALL_R + 0.01);
    const rvx = ball.vx - (surfVx || 0), rvy = ball.vy - (surfVy || 0);
    const vn = rvx * nx + rvy * ny;
    if (vn >= 0) return 0;
    ball.vx -= (1 + e) * vn * nx;
    ball.vy -= (1 + e) * vn * ny;
    // a little tangential friction
    const tvx = rvx - vn * nx, tvy = rvy - vn * ny;
    ball.vx -= tvx * 0.02; ball.vy -= tvy * 0.02;
    return -vn;
  }
  function flipperTip(f) { return [f.x + Math.cos(f.ang) * f.len, f.y + Math.sin(f.ang) * f.len]; }

  // ---- simulation ----
  function Sim() {
    const t = buildTable();
    Object.assign(this, t);
    this.balls = [];
    this.events = [];
    this.plunger = 0;       // 0..1 charge
    this.charging = false;
    this.gate = true;       // one-way gate at the lane top: ball can't fall back in
  }
  const S = Sim.prototype;
  S.addBall = function (inLane) {
    const b = inLane ? { x: 400, y: 600, vx: 0, vy: 0 } : { x: 211, y: 150, vx: (Math.random() - 0.5) * 200, vy: 100 };
    b.inLane = !!inLane;
    this.balls.push(b);
    return b;
  };
  S.emit = function (type, data) { this.events.push(Object.assign({ type }, data)); };
  S.launch = function () {
    for (const b of this.balls) if (b.inLane && b.y > 540 && Math.abs(b.vy) < 120) {
      b.vy = -(900 + this.plunger * 1250);
      this.emit('launch', { power: this.plunger });
    }
    this.plunger = 0;
  };
  S.nudge = function (dx) {
    for (const b of this.balls) { b.vx += dx; b.vy -= 120; }
  };
  S.step = function (dt) {
    // flippers
    for (const f of this.flippers) {
      const target = f.pressed ? f.up : f.rest;
      const speed = 28;                      // rad/s
      const prev = f.ang;
      const diff = target - f.ang;
      const stepA = Math.sign(diff) * Math.min(Math.abs(diff), speed * dt);
      f.ang += stepA;
      f.w = (f.ang - prev) / dt;
    }
    if (this.charging) this.plunger = Math.min(1, this.plunger + dt * 1.1);
    this.spinner.angle += this.spinner.spin * dt;
    this.spinner.spin *= Math.pow(0.3, dt);
    for (const bm of this.bumpers) if (bm.lit > 0) bm.lit -= dt;
    for (const tg of this.targets) if (tg.lit > 0) tg.lit -= dt;

    for (const b of this.balls) {
      b.vy += GRAVITY * dt;
      const sp = Math.hypot(b.vx, b.vy);
      if (sp > MAX_V) { b.vx *= MAX_V / sp; b.vy *= MAX_V / sp; }
      b.x += b.vx * dt; b.y += b.vy * dt;

      // launch lane
      if (b.inLane) {
        if (b.x < LANE_X + BALL_R) { b.x = LANE_X + BALL_R; b.vx = Math.abs(b.vx) * 0.3; }
        if (b.x > 414 - BALL_R) { b.x = 414 - BALL_R; b.vx = -Math.abs(b.vx) * 0.3; }
        const plungerY = 612 + this.plunger * 18;
        if (b.y > plungerY - BALL_R && b.vy >= 0) {
          // resting on (or falling onto) the plunger; a ball already moving up is left alone
          b.y = plungerY - BALL_R; b.vy = -b.vy * 0.2; if (Math.abs(b.vy) < 20) b.vy = 0;
        }
        if (b.y < 190) { b.inLane = false; this.emit('enter'); }
        else continue;
      }
      // walls
      for (const w of this.walls) {
        if (w.lane && !b.inLane && b.x > LANE_X - BALL_R - 2 && b.x < LANE_X + BALL_R + 2) {
          // one-way gate: the lane wall only blocks from the table side
        }
        const [cx, cy] = closestOnSeg(b.x, b.y, w.a, w.b);
        if ((b.x - cx) ** 2 + (b.y - cy) ** 2 > BALL_R * BALL_R) continue;
        const imp = bounce(b, cx, cy, w.e);
        if (w.kick && imp > 60) {
          // slingshot: push away from the face
          const dx = w.b[0] - w.a[0], dy = w.b[1] - w.a[1], l = Math.hypot(dx, dy);
          let nx = -dy / l, ny = dx / l;
          if ((b.x - cx) * nx + (b.y - cy) * ny < 0) { nx = -nx; ny = -ny; }
          b.vx += nx * w.kick; b.vy += ny * w.kick;
          this.emit('sling', { side: w.sling });
        } else if (imp > 250) this.emit('wall', { imp });
      }
      // ball entering the lane opening from the table side is blocked by the gate
      if (!b.inLane && b.x > LANE_X - BALL_R && b.y > 190 && b.y < 520) { b.x = LANE_X - BALL_R; b.vx = -Math.abs(b.vx) * 0.5; }
      if (!b.inLane && b.x > LANE_X && b.y <= 190 && b.vy > 0 && b.y > 170) { b.vx -= 400; }
      // bumpers
      for (const bm of this.bumpers) {
        const dx = b.x - bm.x, dy = b.y - bm.y, d = Math.hypot(dx, dy);
        if (d > bm.r + BALL_R) continue;
        const nx = dx / d, ny = dy / d;
        b.x = bm.x + nx * (bm.r + BALL_R + 0.5); b.y = bm.y + ny * (bm.r + BALL_R + 0.5);
        const vn = b.vx * nx + b.vy * ny;
        b.vx -= 2 * vn * nx; b.vy -= 2 * vn * ny;
        b.vx += nx * bm.kick * 0.5; b.vy += ny * bm.kick * 0.5;
        bm.lit = 0.18;
        this.emit('bumper', { i: this.bumpers.indexOf(bm), x: bm.x, y: bm.y });
      }
      // drop targets
      for (const tg of this.targets) {
        if (tg.down) continue;
        const [cx, cy] = closestOnSeg(b.x, b.y, [tg.x, tg.y], [tg.x + tg.w, tg.y + 12]);
        if ((b.x - cx) ** 2 + (b.y - cy) ** 2 > BALL_R * BALL_R) continue;
        bounce(b, cx, cy, 0.5);
        tg.down = true; tg.lit = 0.3;
        this.emit('target', { i: this.targets.indexOf(tg), x: tg.x, y: tg.y });
      }
      // rollovers (sensors)
      for (const ro of this.rollovers) {
        const hit = Math.hypot(b.x - ro.x, b.y - ro.y) < ro.r + BALL_R;
        if (hit && !ro.inside) { ro.inside = true; this.emit('rollover', { i: this.rollovers.indexOf(ro) }); }
        if (!hit) ro.inside = false;
      }
      // spinner sensor
      const sp2 = this.spinner;
      if (Math.abs(b.x - sp2.x) < sp2.w / 2 && Math.abs(b.y - sp2.y) < BALL_R) {
        if (!sp2.inside) { sp2.inside = true; sp2.spin = Math.min(60, Math.abs(b.vy) / 20); this.emit('spinner', { spin: sp2.spin }); }
      } else sp2.inside = false;
      // flippers: segment from pivot to tip, moving surface
      for (const f of this.flippers) {
        const tip = flipperTip(f);
        const [cx, cy] = closestOnSeg(b.x, b.y, [f.x, f.y], tip);
        const rad = BALL_R + 6;
        if ((b.x - cx) ** 2 + (b.y - cy) ** 2 > rad * rad) continue;
        // surface velocity at the contact point (rotation around the pivot)
        const rx = cx - f.x, ry = cy - f.y;
        const svx = -f.w * ry, svy = f.w * rx;
        let nx = b.x - cx, ny = b.y - cy;
        const d = Math.hypot(nx, ny) || 1e-6;
        nx /= d; ny /= d;
        b.x = cx + nx * (rad + 0.01); b.y = cy + ny * (rad + 0.01);
        const rvx = b.vx - svx, rvy = b.vy - svy;
        const vn = rvx * nx + rvy * ny;
        if (vn < 0) {
          b.vx -= 1.25 * vn * nx; b.vy -= 1.25 * vn * ny;
          if (Math.abs(f.w) > 1) this.emit('flipperHit', { side: f.side });
        }
      }
      if (!isFinite(b.x) || !isFinite(b.y)) { b.x = 211; b.y = 150; b.vx = b.vy = 0; }
      // keep inside the cabinet no matter what
      b.x = Math.max(12 + BALL_R, Math.min(414 - BALL_R, b.x));
      if (b.y < BALL_R) { b.y = BALL_R; b.vy = Math.abs(b.vy); }
    }
    // drains
    const kept = [];
    for (const b of this.balls) {
      if (b.y > H + 20) this.emit('drain', { x: b.x });
      else kept.push(b);
    }
    this.balls = kept;
  };

  const api = { Sim, W, H, BALL_R, LANE_X, flipperTip, arcPts };
  root.PinballPhysics = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
