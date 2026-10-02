// Extra 键鼠映射 boards (BongoCat-style modes): 邦戈鼓 / 钢琴猫 / 手柄 / 按键条.
// window.BongoModes[id] = { name, size:[w,h], svg(skin, A), create(svgEl, ctx) -> { key, mouse, move, wheel, tick, dispose } }
// ctx: { A, skin, cfg, caption(text, combo), note(x, y) }
(function (root) {
  const NS = 'http://www.w3.org/2000/svg';

  // cat face reused by the extra boards (same drawing as the main board, via BongoArt.head)
  const face = (A, s, x, y, sc) => `<g transform="translate(${x} ${y}) scale(${sc})"><g id="head">${A.head(s)}</g></g>`;
  const furPaw = (s, x, y, sc, rot, pads) => `<g transform="translate(${x} ${y}) rotate(${rot || 0}) scale(${sc})">
      <ellipse cx="0" cy="0" rx="19" ry="15" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
      ${pads ? `<ellipse cx="0" cy="4" rx="8" ry="6" fill="${s.inner}"/><circle cx="-9.5" cy="-5" r="3.4" fill="${s.inner}"/><circle cx="0" cy="-9" r="3.4" fill="${s.inner}"/><circle cx="9.5" cy="-5" r="3.4" fill="${s.inner}"/>`
        : `<path d="M-6 -12Q-6 -4 -7 2M6 -12Q6 -4 7 2" stroke="${s.line}" stroke-width="2" fill="none" stroke-linecap="round" opacity=".55"/>`}
    </g>`;
  const armStroke = (s, id, d) => `<g id="${id}"><path d="${d}" fill="none" stroke="${s.line}" stroke-width="34" stroke-linecap="round"/><path d="${d}" fill="none" stroke="url(#gFur)" stroke-width="28" stroke-linecap="round"/></g>`;
  const setArm = (el, d) => el && el.querySelectorAll('path').forEach(p => p.setAttribute('d', d));

  // ================= 邦戈鼓 =================
  // classic Bongo Cat: left half of the keyboard → left paw/drum, right half → right, Space → both
  const LEFT_CODES = new Set([1, 41, 2, 3, 4, 5, 6, 15, 16, 17, 18, 19, 20, 58, 30, 31, 32, 33, 34, 42, 44, 45, 46, 47, 48, 29, 3675, 56, 59, 60, 61, 62, 63, 64]);
  const bongo = {
    name: '邦戈鼓', size: [400, 300],
    svg(s, A) {
      const drum = (cx, cy, rx, ry, h, col, id) => `
        <g id="${id}">
          <path d="M${cx - rx} ${cy}V${cy + h}C${cx - rx} ${cy + h + ry * 1.05} ${cx + rx} ${cy + h + ry * 1.05} ${cx + rx} ${cy + h}V${cy}" fill="${col}" stroke="#5a2c14" stroke-width="3"/>
          <path d="M${cx - rx + 2} ${cy + h * 0.28}C${cx - rx} ${cy + h * 0.28 + ry} ${cx + rx} ${cy + h * 0.28 + ry} ${cx + rx - 2} ${cy + h * 0.28}" fill="none" stroke="#f3c38c" stroke-width="5" opacity=".75"/>
          <path d="M${cx - rx + 4} ${cy + h * 0.72}C${cx - rx} ${cy + h * 0.72 + ry} ${cx + rx} ${cy + h * 0.72 + ry} ${cx + rx - 4} ${cy + h * 0.72}" fill="none" stroke="#f3c38c" stroke-width="5" opacity=".75"/>
          ${[-0.6, -0.2, 0.2, 0.6].map(t => `<path d="M${cx + rx * t} ${cy + ry * Math.sqrt(1 - t * t) * 0.95}L${cx + rx * t * 0.96} ${cy + h + ry * 0.8}" stroke="#5a2c14" stroke-width="1.6" opacity=".35"/>`).join('')}
          <ellipse class="skin" cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="#fbe8cf" stroke="#5a2c14" stroke-width="3"/>
          <ellipse cx="${cx}" cy="${cy}" rx="${rx - 7}" ry="${ry - 4}" fill="none" stroke="#e9cda8" stroke-width="2"/>
          ${[0, 1, 2, 3, 4, 5, 6, 7].map(i => { const a = i / 8 * Math.PI * 2; return `<circle cx="${(cx + Math.cos(a) * (rx - 1)).toFixed(1)}" cy="${(cy + Math.sin(a) * (ry - 1)).toFixed(1)}" r="2.4" fill="#caa06a" stroke="#5a2c14" stroke-width="1"/>`; }).join('')}
          <ellipse class="ring" cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none" stroke="${s.accent2}" stroke-width="5" opacity="0"/>
        </g>`;
      return `${A.defs(s)}
        <ellipse cx="200" cy="292" rx="180" ry="9" fill="#000" opacity=".12" filter="url(#fShadow)"/>
        <g class="body"><path d="M104 160C88 200 80 250 80 300H320C320 250 312 200 296 160Z" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
          <ellipse cx="200" cy="222" rx="60" ry="42" fill="${s.belly}"/></g>
        <path d="M0 214H400V300H0Z" fill="url(#gDesk)"/><path d="M0 214H400" stroke="#f3c79c" stroke-width="2"/>
        <path d="M0 288H400V300H0Z" fill="url(#gDeskFront)"/>
        ${drum(122, 232, 70, 22, 40, '#c8743a', 'drumL')}
        ${drum(282, 228, 62, 20, 44, '#b35f2c', 'drumR')}
        ${armStroke(s, 'armL', '')}${armStroke(s, 'armR', '')}
        <g id="pawL"></g><g id="pawR"></g>
        ${face(A, s, 200, 108, 1)}
        <g id="fx"></g>`;
    },
    create(svg, ctx) {
      const s = ctx.skin, q = x => svg.querySelector(x);
      const SH = { L: [142, 190], R: [258, 190] };
      const UP = { L: [112, 168], R: [288, 164] };
      const HIT = { L: [124, 226], R: [280, 222] };
      const until = { L: 0, R: 0 };
      function draw() {
        const now = performance.now();
        for (const side of ['L', 'R']) {
          const down = now < until[side];
          const p = down ? HIT[side] : UP[side];
          setArm(q('#arm' + side), `M${SH[side][0]} ${SH[side][1]}Q${(SH[side][0] + p[0]) / 2} ${Math.min(SH[side][1], p[1]) - 16} ${p[0]} ${p[1]}`);
          q('#paw' + side).innerHTML = furPaw(s, p[0], p[1], 1, side === 'L' ? (down ? -12 : 22) : (down ? 12 : -22), !down);
          const drum = q('#drum' + side);
          drum.querySelector('.skin').setAttribute('fill', down ? '#fff3df' : '#fbe8cf');
          drum.querySelector('.ring').setAttribute('opacity', down ? '.9' : '0');
          drum.setAttribute('transform', down ? 'translate(0 2)' : '');
        }
      }
      function hit(side) {
        until[side] = performance.now() + 110;
        draw();
        setTimeout(draw, 120);
        if (Math.random() < 0.35) ctx.note(side === 'L' ? 122 : 282, 190);
      }
      draw();
      return {
        key(down, code) {
          if (!down) return;
          if (code === 57) { hit('L'); hit('R'); return; }
          hit(LEFT_CODES.has(code) ? 'L' : 'R');
        },
        mouse(down, button) { if (down) hit(button === 2 ? 'R' : 'L'); }
      };
    }
  };

  // ================= 钢琴猫 =================
  // three octaves; each keyboard row maps onto the piano by its horizontal position
  const piano = {
    name: '钢琴猫', size: [620, 300],
    svg(s, A) {
      const W = 520, X0 = 50, Y0 = 170, WHITE = 21, ww = W / WHITE;
      let whites = '', blacks = '';
      const BLACK_AFTER = [0, 1, 3, 4, 5];   // C# D# F# G# A# within each 7 whites
      for (let i = 0; i < WHITE; i++) {
        whites += `<g class="pk" id="pw-${i}"><rect x="${(X0 + i * ww).toFixed(1)}" y="${Y0}" width="${(ww - 1.2).toFixed(1)}" height="96" rx="3" fill="url(#gIvory)" stroke="#8d7f70" stroke-width="1"/>
          <rect class="lit" x="${(X0 + i * ww).toFixed(1)}" y="${Y0}" width="${(ww - 1.2).toFixed(1)}" height="96" rx="3" fill="url(#kOn)" opacity="0"/></g>`;
        if (BLACK_AFTER.includes(i % 7) && i < WHITE - 1) {
          blacks += `<g class="pk" id="pb-${i}"><rect x="${(X0 + (i + 1) * ww - ww * 0.32).toFixed(1)}" y="${Y0}" width="${(ww * 0.62).toFixed(1)}" height="60" rx="2.5" fill="url(#gEbony)"/>
            <rect class="lit" x="${(X0 + (i + 1) * ww - ww * 0.32).toFixed(1)}" y="${Y0}" width="${(ww * 0.62).toFixed(1)}" height="60" rx="2.5" fill="url(#kOn)" opacity="0"/>
            <rect x="${(X0 + (i + 1) * ww - ww * 0.22).toFixed(1)}" y="${Y0 + 2}" width="${(ww * 0.42).toFixed(1)}" height="4" rx="2" fill="#fff" opacity=".18"/></g>`;
        }
      }
      return `${A.defs(s)}
        <defs>
          <linearGradient id="gIvory" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fffdf8"/><stop offset=".85" stop-color="#f3ece1"/><stop offset="1" stop-color="#ddd2c3"/></linearGradient>
          <linearGradient id="gEbony" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3336"/><stop offset="1" stop-color="#141013"/></linearGradient>
          <linearGradient id="gLacquer" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a2f25"/><stop offset=".5" stop-color="#2a1812"/><stop offset="1" stop-color="#1b0f0b"/></linearGradient>
        </defs>
        <ellipse cx="310" cy="292" rx="290" ry="9" fill="#000" opacity=".14" filter="url(#fShadow)"/>
        <g class="body"><path d="M226 110C212 140 206 160 206 190H414C414 160 408 140 394 110Z" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
          <ellipse cx="310" cy="160" rx="50" ry="26" fill="${s.belly}"/></g>
        <!-- piano case -->
        <path d="M30 150H590V290H30Z" fill="url(#gLacquer)" stroke="#120906" stroke-width="2"/>
        <path d="M30 150H590V160H30Z" fill="#6b4536"/>
        <rect x="44" y="164" width="532" height="108" rx="4" fill="#120906"/>
        ${whites}${blacks}
        <path d="M44 268H576" stroke="#6b4536" stroke-width="4"/>
        <text x="310" y="286" text-anchor="middle" font-size="10" font-family="Georgia,serif" font-style="italic" fill="#c9a36b" letter-spacing="3">MEOWSTEIN</text>
        ${armStroke(s, 'armL', '')}${armStroke(s, 'armR', '')}
        <g id="pawL"></g><g id="pawR"></g>
        ${face(A, s, 310, 76, 0.78)}
        <g id="sheet" transform="translate(420 18)">
          <rect x="0" y="0" width="84" height="56" rx="4" fill="#fffaf0" stroke="#c9b9a4"/>
          ${[12, 20, 28, 36, 44].map(y => `<path d="M6 ${y}H78" stroke="#c9b9a4" stroke-width=".8"/>`).join('')}
          <g id="notes"></g>
        </g>
        <g id="fx"></g>`;
    },
    create(svg, ctx) {
      const s = ctx.skin, q = x => svg.querySelector(x);
      const A = ctx.A;
      const W = 520, X0 = 50, Y0 = 170, WHITE = 21, ww = W / WHITE;
      // map a key by its position on the keyboard to a piano key (white or black)
      const ROWMAP = { 1.25: 'b', 2.25: 'w', 3.25: 'b', 4.25: 'w', 0: 'w', 5.25: 'w' };
      function pianoKey(code) {
        const k = A.keyOf(code);
        let frac = 0.5, kind = 'w';
        if (k) { frac = Math.min(0.999, (k.x + k.w / 2) / 15); kind = ROWMAP[k.y] || 'w'; }
        let i = Math.floor(frac * WHITE);
        if (kind === 'b') {
          const hasBlack = j => [0, 1, 3, 4, 5].includes(j % 7) && j < WHITE - 1;
          while (i > 0 && !hasBlack(i)) i--;
          if (hasBlack(i)) return { id: 'pb-' + i, x: X0 + (i + 1) * ww, semi: [1, 3, 6, 8, 10][[0, 1, 3, 4, 5].indexOf(i % 7)] + 12 * Math.floor(i / 7) };
        }
        return { id: 'pw-' + i, x: X0 + i * ww + ww / 2, semi: [0, 2, 4, 5, 7, 9, 11][i % 7] + 12 * Math.floor(i / 7) };
      }
      let ac = null;
      function play(semi) {
        if (!ctx.cfg.sound) return;
        try {
          ac = ac || new AudioContext();
          const f = 130.81 * Math.pow(2, semi / 12), t = ac.currentTime;
          const g = ac.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.22, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 1.3);
          for (const [mul, type, vol] of [[1, 'triangle', 1], [2, 'sine', 0.35], [3, 'sine', 0.12]]) {
            const o = ac.createOscillator(), og = ac.createGain();
            o.type = type; o.frequency.value = f * mul; og.gain.value = vol;
            o.connect(og); og.connect(g); o.start(t); o.stop(t + 1.35);
          }
          g.connect(ac.destination);
        } catch { /* audio unavailable */ }
      }
      const held = new Map();   // code -> piano key
      let lastSide = 'R';
      function draw() {
        const all = [...held.values()];
        const left = all.filter(p => p.x < 310).pop(), right = all.filter(p => p.x >= 310).pop();
        const SH = { L: [258, 150], R: [362, 150] };
        const rest = { L: [236, 150], R: [384, 150] };
        for (const [side, p] of [['L', left], ['R', right]]) {
          const pt = p ? [p.x, Y0 + (p.id.startsWith('pb') ? 40 : 70)] : rest[side];
          setArm(q('#arm' + side), `M${SH[side][0]} ${SH[side][1]}Q${(SH[side][0] + pt[0]) / 2} ${Math.min(SH[side][1], pt[1]) - 12} ${pt[0]} ${pt[1]}`);
          q('#paw' + side).innerHTML = furPaw(s, pt[0], pt[1], 0.8, 0, false);
        }
      }
      let noteX = 8;
      function sheetNote() {
        const n = document.createElementNS(NS, 'text');
        n.setAttribute('x', noteX); n.setAttribute('y', 44 - Math.random() * 30);
        n.setAttribute('font-size', '14'); n.setAttribute('fill', '#3a2a22');
        n.textContent = Math.random() < 0.5 ? '♪' : '♫';
        q('#notes').appendChild(n);
        noteX += 9;
        if (noteX > 74) { noteX = 8; q('#notes').innerHTML = ''; }
      }
      draw();
      return {
        key(down, code) {
          if (down) {
            if (held.has(code)) return;
            const p = pianoKey(code);
            held.set(code, p);
            q('#' + p.id).querySelector('.lit').setAttribute('opacity', '1');
            play(p.semi);
            sheetNote();
            if (Math.random() < 0.3) ctx.note(p.x, 150);
          } else {
            const p = held.get(code);
            held.delete(code);
            if (p && ![...held.values()].some(x => x.id === p.id)) q('#' + p.id).querySelector('.lit').setAttribute('opacity', '0');
          }
          draw();
        },
        mouse(down, button) { this.key(down, button === 2 ? 28 : 30); },
        dispose() { if (ac) try { ac.close(); } catch { /* ignore */ } }
      };
    }
  };

  // ================= 手柄 =================
  // real gamepads via the Gamepad API; otherwise keyboard/mouse drive the pad
  const GP_KEYS = {
    // code -> control
    17: 'lsU', 31: 'lsD', 30: 'lsL', 32: 'lsR',                 // WASD → left stick
    57416: 'dU', 57424: 'dD', 57419: 'dL', 57421: 'dR',         // arrows → d-pad
    36: 'A', 37: 'B', 22: 'X', 23: 'Y',                           // J K U I
    18: 'LB', 16: 'LT', 24: 'RB', 25: 'RT',                       // E Q O P
    57: 'A', 28: 'START', 1: 'BACK', 15: 'BACK', 42: 'L3'
  };
  const gamepad = {
    name: '手柄', size: [460, 300],
    svg(s, A) {
      const fbtn = (id, cx, cy, col, letter) => `<g id="gp-${id}" class="gpb"><circle cx="${cx}" cy="${cy + 2}" r="13" fill="#1b1d22"/><circle class="gp-cap" cx="${cx}" cy="${cy}" r="13" fill="url(#gBtn)" stroke="#0e0f12" stroke-width="1.5"/>
        <text x="${cx}" y="${cy + 5}" text-anchor="middle" font-size="14" font-weight="800" font-family="Segoe UI,Arial" fill="${col}">${letter}</text>
        <circle class="gp-glow" cx="${cx}" cy="${cy}" r="15" fill="none" stroke="${col}" stroke-width="3" opacity="0" filter="url(#fGlow)"/></g>`;
      return `${A.defs(s)}
        <defs>
          <linearGradient id="gShell" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fdfbf8"/><stop offset=".6" stop-color="#e9e4dd"/><stop offset="1" stop-color="#cfc7bc"/></linearGradient>
          <radialGradient id="gBtn" cx=".4" cy=".35" r=".7"><stop offset="0" stop-color="#4a4f5a"/><stop offset="1" stop-color="#23262d"/></radialGradient>
          <radialGradient id="gStick" cx=".4" cy=".35" r=".7"><stop offset="0" stop-color="#555b67"/><stop offset="1" stop-color="#1f2228"/></radialGradient>
        </defs>
        <ellipse cx="230" cy="290" rx="200" ry="9" fill="#000" opacity=".14" filter="url(#fShadow)"/>
        <g class="body"><path d="M150 150C136 190 130 240 130 300H330C330 240 324 190 310 150Z" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
          <ellipse cx="230" cy="210" rx="52" ry="38" fill="${s.belly}"/></g>
        ${face(A, s, 230, 92, 0.86)}
        <g id="pad" transform="translate(0 0)">
          <!-- triggers / bumpers -->
          <g id="gp-LT"><path class="gp-cap" d="M92 150C94 132 112 124 132 126L150 150Z" fill="#3a3f49"/></g>
          <g id="gp-RT"><path class="gp-cap" d="M368 150C366 132 348 124 328 126L310 150Z" fill="#3a3f49"/></g>
          <g id="gp-LB"><path class="gp-cap" d="M82 164C90 146 120 140 150 146L156 160C130 156 104 160 90 172Z" fill="#555b67"/></g>
          <g id="gp-RB"><path class="gp-cap" d="M378 164C370 146 340 140 310 146L304 160C330 156 356 160 370 172Z" fill="#555b67"/></g>
          <!-- shell -->
          <path d="M150 150H310C352 150 382 170 396 214C410 258 412 290 384 296C356 302 338 274 314 250C300 236 282 232 262 232H198C178 232 160 236 146 250C122 274 104 302 76 296C48 290 50 258 64 214C78 170 108 150 150 150Z"
            fill="url(#gShell)" stroke="#8d8378" stroke-width="2.4"/>
          <path d="M150 156H310C340 156 364 170 378 196" fill="none" stroke="#fff" stroke-width="3" opacity=".6" stroke-linecap="round"/>
          <!-- guide button -->
          <circle cx="230" cy="178" r="13" fill="#2b2f36"/><circle id="gp-home" cx="230" cy="178" r="9" fill="${s.accent}" opacity=".85"/>
          <path d="M224 172L236 184M236 172L224 184" stroke="#fff" stroke-width="2.4" stroke-linecap="round" opacity=".9"/>
          <g id="gp-BACK" class="gpb"><rect class="gp-cap" x="196" y="194" width="14" height="8" rx="4" fill="#3a3f49"/></g>
          <g id="gp-START" class="gpb"><rect class="gp-cap" x="250" y="194" width="14" height="8" rx="4" fill="#3a3f49"/></g>
          <!-- left stick -->
          <circle cx="146" cy="196" r="26" fill="#2b2f36"/><circle cx="146" cy="196" r="22" fill="#1b1d22"/>
          <g id="gp-ls"><circle cx="146" cy="196" r="18" fill="url(#gStick)" stroke="#0e0f12" stroke-width="1.5"/><circle cx="146" cy="196" r="12" fill="none" stroke="#6b717d" stroke-width="1.5" stroke-dasharray="2 2"/></g>
          <!-- d-pad -->
          <circle cx="182" cy="250" r="26" fill="#2b2f36"/>
          <g fill="url(#gBtn)" stroke="#0e0f12" stroke-width="1.2">
            <path id="gp-dU" class="gp-cap" d="M175 228H189V244H175Z"/><path id="gp-dD" class="gp-cap" d="M175 256H189V272H175Z"/>
            <path id="gp-dL" class="gp-cap" d="M160 243H176V257H160Z"/><path id="gp-dR" class="gp-cap" d="M188 243H204V257H188Z"/>
          </g>
          <rect x="175" y="243" width="14" height="14" fill="#23262d"/>
          <!-- right stick -->
          <circle cx="278" cy="250" r="26" fill="#2b2f36"/><circle cx="278" cy="250" r="22" fill="#1b1d22"/>
          <g id="gp-rs"><circle cx="278" cy="250" r="18" fill="url(#gStick)" stroke="#0e0f12" stroke-width="1.5"/><circle cx="278" cy="250" r="12" fill="none" stroke="#6b717d" stroke-width="1.5" stroke-dasharray="2 2"/></g>
          <!-- face buttons -->
          ${fbtn('Y', 314, 172, '#f2c230', 'Y')}${fbtn('X', 290, 196, '#3a8fe8', 'X')}${fbtn('B', 338, 196, '#e8453a', 'B')}${fbtn('A', 314, 220, '#39b54a', 'A')}
        </g>
        ${furPaw(s, 112, 238, 1.05, 30, false)}${furPaw(s, 348, 238, 1.05, -30, false)}
        <g id="fx"></g>`;
    },
    create(svg, ctx) {
      const q = x => svg.querySelector(x);
      const on = new Set();
      let stick = { x: 0, y: 0 }, rstick = { x: 0, y: 0 }, mouseT = 0, lastMove = null, raf = 0, dead = false;
      const accent = ctx.skin.accent;
      function setBtn(id, v) {
        const el = q('#gp-' + id);
        if (!el) return;
        const cap = el.classList.contains('gp-cap') ? el : el.querySelector('.gp-cap');
        if (cap) {
          if (!cap.dataset.fill) cap.dataset.fill = cap.getAttribute('fill');
          cap.setAttribute('fill', v ? accent : cap.dataset.fill);
        }
        const glow = el.querySelector && el.querySelector('.gp-glow');
        if (glow) glow.setAttribute('opacity', v ? '1' : '0');
        if (el.classList.contains('gpb')) el.setAttribute('transform', v ? 'translate(0 1.5)' : '');
      }
      function drawSticks() {
        q('#gp-ls').setAttribute('transform', `translate(${(stick.x * 8).toFixed(1)} ${(stick.y * 8).toFixed(1)})`);
        q('#gp-rs').setAttribute('transform', `translate(${(rstick.x * 8).toFixed(1)} ${(rstick.y * 8).toFixed(1)})`);
      }
      function keyStick() {
        stick = { x: (on.has('lsR') ? 1 : 0) - (on.has('lsL') ? 1 : 0), y: (on.has('lsD') ? 1 : 0) - (on.has('lsU') ? 1 : 0) };
        const l = Math.hypot(stick.x, stick.y); if (l > 1) { stick.x /= l; stick.y /= l; }
        drawSticks();
      }
      // real controller polling
      const MAP = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', 'BACK', 'START', 'L3', 'R3', 'dU', 'dD', 'dL', 'dR'];
      let padSeen = false;
      function poll() {
        if (dead) return;
        raf = requestAnimationFrame(poll);
        const pads = navigator.getGamepads ? navigator.getGamepads() : [];
        const gp = [...pads].find(Boolean);
        if (!gp) return;
        if (!padSeen) { padSeen = true; ctx.caption('🎮 已连接手柄'); }
        MAP.forEach((id, i) => { const b = gp.buttons[i]; if (b) setBtn(id, b.pressed || b.value > 0.4); });
        stick = { x: gp.axes[0] || 0, y: gp.axes[1] || 0 };
        rstick = { x: gp.axes[2] || 0, y: gp.axes[3] || 0 };
        drawSticks();
      }
      poll();
      return {
        key(down, code) {
          const id = GP_KEYS[code];
          if (!id) return;
          if (down) on.add(id); else on.delete(id);
          if (id.startsWith('ls')) keyStick(); else setBtn(id, down);
        },
        mouse(down, button) { setBtn(button === 2 ? 'RT' : button === 3 ? 'RB' : 'LT', down); },
        move(p) {
          // mouse motion nudges the right stick, springing back when the mouse stops
          if (lastMove) {
            rstick.x = Math.max(-1, Math.min(1, (p.x - lastMove.x) * 60));
            rstick.y = Math.max(-1, Math.min(1, (p.y - lastMove.y) * 60));
            drawSticks();
          }
          lastMove = p;
          clearTimeout(mouseT);
          mouseT = setTimeout(() => { rstick = { x: 0, y: 0 }; drawSticks(); }, 120);
        },
        dispose() { dead = true; cancelAnimationFrame(raf); clearTimeout(mouseT); }
      };
    }
  };

  // ================= 按键条 =================
  // streamer-style strip: recent keys with repeat counts, KPM and a sparkline, mouse buttons
  const strip = {
    name: '按键条', size: [640, 150],
    svg(s, A) {
      return `${A.defs(s)}
        <defs>
          <linearGradient id="gGlass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f3a" stop-opacity=".92"/><stop offset="1" stop-color="#181a21" stop-opacity=".92"/></linearGradient>
          <linearGradient id="gSpark" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s.accent2}" stop-opacity=".6"/><stop offset="1" stop-color="${s.accent2}" stop-opacity="0"/></linearGradient>
        </defs>
        <rect x="8" y="30" width="624" height="92" rx="22" fill="url(#gGlass)" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
        <rect x="9" y="31" width="622" height="30" rx="21" fill="#fff" opacity=".05"/>
        <!-- peeking cat on the left edge -->
        <g transform="translate(58 44) scale(.42)"><g id="head">${A.head(s)}</g></g>
        ${furPaw(s, 36, 40, 0.62, -10, false)}${furPaw(s, 82, 40, 0.62, 10, false)}
        <g id="chips" transform="translate(120 50)"></g>
        <!-- stats -->
        <g transform="translate(470 42)">
          <path id="spark" d="" fill="url(#gSpark)"/><path id="sparkLine" d="" fill="none" stroke="${s.accent2}" stroke-width="1.6"/>
          <text x="96" y="30" text-anchor="end" font-size="26" font-weight="800" font-family="Segoe UI,Arial" fill="#fff" id="kpm">0</text>
          <text x="96" y="44" text-anchor="end" font-size="10" font-family="Segoe UI,Microsoft YaHei UI" fill="#9aa4b1">键 / 分钟</text>
          <text x="96" y="66" text-anchor="end" font-size="11" font-family="Segoe UI,Microsoft YaHei UI" fill="#9aa4b1" id="total">今日 0 键</text>
        </g>
        <!-- mouse -->
        <g transform="translate(598 76)">
          <path d="M-14 -8C-14 -24 -7 -30 0 -30C7 -30 14 -24 14 -8V8C14 20 7 26 0 26C-7 26 -14 20 -14 8Z" fill="#3a3f4b" stroke="#8a93a3" stroke-width="1.4"/>
          <path id="mbL" class="m-btn" d="M-13 -9C-13 -23 -7 -29 -0.8 -29.2V-9Z" fill="transparent"/>
          <path id="mbR" class="m-btn" d="M13 -9C13 -23 7 -29 0.8 -29.2V-9Z" fill="transparent"/>
          <path d="M0 -30V-9M-14 -9H14" stroke="#8a93a3" stroke-width="1.1"/>
          <rect id="mWheel" x="-2" y="-24" width="4" height="9" rx="2" fill="#c9ced8"/>
        </g>`;
    },
    create(svg, ctx) {
      const q = x => svg.querySelector(x);
      const s = ctx.skin, A = ctx.A;
      const chipsEl = q('#chips');
      const chips = [];            // { label, n, w, el, t }
      const times = [];            // key timestamps for KPM
      const buckets = new Array(30).fill(0);
      const today = new Date().toDateString();
      let total = ctx.cfg.stripDay === today ? (ctx.cfg.stripTotal || 0) : 0;
      function layout() {
        let x = 0;
        for (let i = chips.length - 1; i >= 0; i--) {
          const c = chips[i];
          c.el.setAttribute('transform', `translate(${x} 0)`);
          c.el.style.opacity = x > 320 ? '0' : '';
          x += c.w + 8;
        }
        while (chips.length > 10) chips.shift().el.remove();
      }
      function chip(label) {
        const last = chips[chips.length - 1];
        if (last && last.label === label && performance.now() - last.t < 1500) {
          last.n++; last.t = performance.now();
          last.el.querySelector('.cnt').textContent = '×' + last.n;
          const w = last.baseW + 26;
          if (last.w !== w) { last.w = w; last.el.querySelector('.bg').setAttribute('width', w); }
          last.el.querySelector('.bg').animate([{ transform: 'scale(1.08)' }, { transform: 'none' }], { duration: 140 });
          layout();
          return;
        }
        const g = document.createElementNS(NS, 'g');
        const baseW = Math.max(38, 14 + label.length * 11);
        g.innerHTML = `<rect class="bg" x="0" y="0" width="${baseW}" height="44" rx="10" fill="#fff" fill-opacity=".1" stroke="${s.accent2}" stroke-opacity=".7" stroke-width="1.5"/>
          <rect x="0" y="0" width="${baseW}" height="40" rx="10" fill="#fff" fill-opacity=".06"/>
          <text x="${baseW / 2}" y="28" text-anchor="middle" font-size="17" font-weight="700" font-family="Segoe UI,Microsoft YaHei UI" fill="#fff">${label.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</text>
          <text class="cnt" x="${baseW + 4}" y="28" font-size="13" font-weight="700" font-family="Segoe UI" fill="${s.accent2}"></text>`;
        chipsEl.appendChild(g);
        g.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1 }], { duration: 140 });
        chips.push({ label, n: 1, w: baseW, baseW, el: g, t: performance.now() });
        layout();
      }
      function stats() {
        const now = Date.now();
        while (times.length && now - times[0] > 60000) times.shift();
        q('#kpm').textContent = times.length;
        q('#total').textContent = `今日 ${total} 键`;
        const max = Math.max(4, ...buckets);
        const pts = buckets.map((v, i) => [i * (84 / 29), 60 - v / max * 44]);
        const line = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('');
        q('#sparkLine').setAttribute('d', line);
        q('#spark').setAttribute('d', line + 'L84 60L0 60Z');
      }
      const tick = setInterval(() => { buckets.shift(); buckets.push(0); stats(); }, 2000);
      let saveT = 0;
      stats();
      return {
        key(down, code) {
          if (!down || A.MODS[code]) return;
          const mods = ctx.heldMods();
          chip([...mods, A.keyName(code)].join('+'));
          times.push(Date.now());
          buckets[buckets.length - 1]++;
          total++;
          clearTimeout(saveT);
          saveT = setTimeout(() => window.api.bongo.update({ stripTotal: total, stripDay: today }), 3000);
          stats();
        },
        mouse(down, button) {
          const id = button === 1 ? '#mbL' : button === 2 ? '#mbR' : null;
          if (id) q(id).setAttribute('fill', down ? s.accent : 'transparent');
          if (button === 3) q('#mWheel').setAttribute('fill', down ? s.accent : '#c9ced8');
          if (down) chip(['', '左键', '右键', '中键'][button] || '鼠标');
        },
        wheel(dir) { chip(dir > 0 ? '滚轮 ↓' : '滚轮 ↑'); },
        dispose() { clearInterval(tick); clearTimeout(saveT); }
      };
    }
  };

  root.BongoModes = { bongo, piano, gamepad, strip };
})(typeof window !== 'undefined' ? window : globalThis);
