// Classic line-art Bongo Cat boards: white blob cat, black outlines, pink toe beans.
// Registers into window.BongoModes: lbongo (邦戈鼓) / ltable (拍桌) / lkeys (键盘) / ldesk (键鼠).
// The face uses the same classes as the main board (.eo .ehappy .eexcited .esleep .mouth-w .mouth-o #pupils)
// so the overlay's mood / eye-tracking logic works unchanged.
(function (root) {
  const INK = '#1e1e1e', PAD = '#f5909f', BLUSH = '#ffb4c0', HIT = '#e8453a';
  const T = 162;                       // table / paw baseline
  const SW = 4;                        // main stroke width
  const W = 400, H = 270;

  // ---------- cat ----------
  function cat() {
    const body = `M52 ${T + 2}C48 ${T - 46} 76 ${T - 78} 108 ${T - 90}L117 ${T - 132}L153 ${T - 104}`
      + `C181 ${T - 112} 221 ${T - 112} 249 ${T - 106}L287 ${T - 134}L294 ${T - 88}`
      + `C328 ${T - 76} 352 ${T - 46} 350 ${T + 2}Z`;
    return `
      <g class="body">
        <path d="${body}" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
        <path d="M121 ${T - 104}L123 ${T - 120}L139 ${T - 106}" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" opacity=".45"/>
        <path d="M283 ${T - 108}L286 ${T - 122}L271 ${T - 110}" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" opacity=".45"/>
      </g>
      <g id="head">
        <g class="eo">
          <g class="blink"><ellipse cx="170" cy="${T - 50}" rx="6" ry="8" fill="${INK}"/></g>
          <g class="blink"><ellipse cx="232" cy="${T - 50}" rx="6" ry="8" fill="${INK}"/></g>
          <g id="pupils"><circle cx="172" cy="${T - 53}" r="2.2" fill="#fff"/><circle cx="234" cy="${T - 53}" r="2.2" fill="#fff"/></g>
        </g>
        <g class="ehappy" display="none" fill="none" stroke="${INK}" stroke-width="3.4" stroke-linecap="round">
          <path d="M161 ${T - 47}Q170 ${T - 58} 179 ${T - 47}"/><path d="M223 ${T - 47}Q232 ${T - 58} 241 ${T - 47}"/>
        </g>
        <g class="eexcited" display="none" fill="none" stroke="${INK}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round">
          <path d="M162 ${T - 58}L176 ${T - 50}L162 ${T - 42}"/><path d="M240 ${T - 58}L226 ${T - 50}L240 ${T - 42}"/>
        </g>
        <g class="esleep" display="none" fill="none" stroke="${INK}" stroke-width="3.4" stroke-linecap="round">
          <path d="M161 ${T - 50}Q170 ${T - 44} 179 ${T - 50}"/><path d="M223 ${T - 50}Q232 ${T - 44} 241 ${T - 50}"/>
        </g>
        <path class="mouth-w" d="M189 ${T - 38}Q195 ${T - 30} 201 ${T - 37}Q207 ${T - 30} 213 ${T - 38}" fill="none" stroke="${INK}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
        <g class="mouth-o" display="none"><ellipse cx="201" cy="${T - 32}" rx="6" ry="7" fill="#fff" stroke="${INK}" stroke-width="3"/><path d="M197 ${T - 28}Q201 ${T - 31} 205 ${T - 28}" fill="none" stroke="${PAD}" stroke-width="3" stroke-linecap="round"/></g>
        <g opacity=".85">
          <ellipse cx="146" cy="${T - 36}" rx="12" ry="6.5" fill="${BLUSH}"/>
          <ellipse cx="256" cy="${T - 36}" rx="12" ry="6.5" fill="${BLUSH}"/>
          <g stroke="#ef7486" stroke-width="1.6" stroke-linecap="round">
            <path d="M140 ${T - 33}l4 -6M146 ${T - 33}l4 -6M152 ${T - 33}l4 -6"/><path d="M250 ${T - 33}l4 -6M256 ${T - 33}l4 -6M262 ${T - 33}l4 -6"/>
          </g>
        </g>
      </g>`;
  }
  // raised paw behind the table edge, pads showing
  const pawUp = x => `
    <path d="M${x - 21} ${T + 2}V${T - 18}C${x - 21} ${T - 46} ${x + 21} ${T - 46} ${x + 21} ${T - 18}V${T + 2}" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
    <ellipse cx="${x}" cy="${T - 15}" rx="8" ry="6" fill="${PAD}"/>
    <circle cx="${x - 10.5}" cy="${T - 27}" r="3.4" fill="${PAD}"/><circle cx="${x}" cy="${T - 33}" r="3.4" fill="${PAD}"/><circle cx="${x + 10.5}" cy="${T - 27}" r="3.4" fill="${PAD}"/>`;
  // paw slammed down in front of the table edge, tip at (x, tip)
  const pawDown = (x, tip, impact) => `
    <path d="M${x - 20} ${T - 10}C${x - 22} ${T + 4} ${x - 19} ${tip - 8} ${x - 9} ${tip}C${x - 3} ${tip + 3} ${x + 3} ${tip + 3} ${x + 9} ${tip}C${x + 19} ${tip - 8} ${x + 22} ${T + 4} ${x + 20} ${T - 10}" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
    <path d="M${x - 5} ${tip - 9}v5M${x + 5} ${tip - 9}v5" stroke="${INK}" stroke-width="2.4" stroke-linecap="round"/>
    ${impact ? `<g stroke="${INK}" stroke-width="3" stroke-linecap="round">
      <path d="M${x - 27} ${tip - 6}l-10 2"/><path d="M${x + 27} ${tip - 6}l10 2"/><path d="M${x - 17} ${tip + 7}l-6 7"/><path d="M${x + 17} ${tip + 7}l6 7"/>
    </g>` : ''}`;
  const tableEdge = (x0 = 8, x1 = W - 8) => `<path d="M${x0} ${T}H${x1}" stroke="${INK}" stroke-width="${SW}" stroke-linecap="round"/>`;

  // ---------- instruments ----------
  function drum(cx, top, rx, h, id) {
    const ry = rx * 0.28, bw = rx * 0.66, bot = top + h;
    const staves = [-0.55, -0.18, 0.18, 0.55].map(t =>
      `<path d="M${(cx + rx * t).toFixed(1)} ${(top + ry * Math.sqrt(1 - t * t)).toFixed(1)}Q${(cx + rx * t * 0.9).toFixed(1)} ${top + h * 0.55} ${(cx + bw * t).toFixed(1)} ${bot}" stroke="${INK}" stroke-width="1.6" fill="none" opacity=".5"/>`).join('');
    const band = y => { const k = (y - top) / h, hw = rx - (rx - bw) * k * k; return `<path d="M${(cx - hw).toFixed(1)} ${y}Q${cx} ${(y + ry * 1.2).toFixed(1)} ${(cx + hw).toFixed(1)} ${y}" stroke="${INK}" stroke-width="2.6" fill="none"/>`; };
    return `<g id="${id}">
      <path d="M${cx - rx} ${top}C${cx - rx + 2} ${top + h * 0.45} ${cx - bw - 4} ${top + h * 0.8} ${cx - bw} ${bot}H${cx + bw}C${cx + bw + 4} ${top + h * 0.8} ${cx + rx - 2} ${top + h * 0.45} ${cx + rx} ${top}" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
      ${staves}${band(top + h * 0.3)}${band(top + h * 0.72)}
      <ellipse cx="${cx}" cy="${top}" rx="${rx}" ry="${ry}" fill="#fff" stroke="${INK}" stroke-width="${SW}"/>
      <ellipse cx="${cx}" cy="${top}" rx="${rx - 6}" ry="${ry - 3}" fill="none" stroke="${INK}" stroke-width="1.4" opacity=".4"/>
      <g class="hit" opacity="0" stroke="${HIT}" stroke-width="2.6" stroke-linecap="round">
        ${[-16, -6, 4, 14].map(d => `<path d="M${cx + d - 3} ${top + 4}l7 -8"/>`).join('')}
      </g>
    </g>`;
  }
  // flat line-art keyboard: keys from BongoArt.KEYS scaled into (x, y, w, h)
  function keyboard(A, x, y, w, h, prefix) {
    const u = (w - 12) / 18.25, v = (h - 10) / 6.25;
    const keys = A.KEYS.map(k => `<rect id="${prefix}${k.code}" x="${(x + 6 + k.x * u + 0.8).toFixed(1)}" y="${(y + 5 + k.y * v + 0.8).toFixed(1)}" width="${(k.w * u - 1.6).toFixed(1)}" height="${(v - 1.6).toFixed(1)}" rx="1.8" fill="#fff" stroke="${INK}" stroke-width="1.3"/>`).join('');
    return `<rect x="${x}" y="${y + 3}" width="${w}" height="${h}" rx="7" fill="${INK}" opacity=".12"/>
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="7" fill="#fff" stroke="${INK}" stroke-width="${SW - 0.5}"/>${keys}`;
  }
  const keyCenter = (A, code, x, y, w, h) => {
    const k = A.keyOf(code);
    if (!k) return null;
    const u = (w - 12) / 18.25, v = (h - 10) / 6.25;
    return { x: x + 6 + (k.x + k.w / 2) * u, y: y + 5 + (k.y + 0.5) * v, frac: (k.x + k.w / 2) / 18.25 };
  };

  // ---------- shared runtime ----------
  // side: { L|R: { x, tip, until, held:Set } }
  function makeRig(svg, restX) {
    const q = s => svg.querySelector(s);
    const st = { L: { x: restX.L, tip: T + 20, until: 0, held: new Set() }, R: { x: restX.R, tip: T + 20, until: 0, held: new Set() } };
    const timers = new Set();
    function draw() {
      const now = performance.now();
      for (const side of ['L', 'R']) {
        const s = st[side];
        const down = s.held.size > 0 || now < s.until || s.forceDown;
        q('#pawB' + side).innerHTML = down ? '' : pawUp(restX[side]);
        q('#pawF' + side).innerHTML = down ? pawDown(s.x, s.tip, now < s.until) : '';
      }
    }
    function later(fn, ms) { const t = setTimeout(() => { timers.delete(t); fn(); }, ms); timers.add(t); }
    function slam(side, x, tip, holdKey) {
      const s = st[side];
      s.x = x; s.tip = tip;
      s.until = performance.now() + 110;
      if (holdKey != null) s.held.add(holdKey);
      draw();
      later(draw, 120);
    }
    function release(side, holdKey) { st[side].held.delete(holdKey); draw(); }
    draw();
    return { st, draw, slam, release, later, dispose() { timers.forEach(clearTimeout); } };
  }
  const shake = el => el && el.animate([{ transform: 'translate(0,0)' }, { transform: 'translate(0,3px)' }, { transform: 'translate(0,0)' }], { duration: 120 });
  const layers = () => `<g id="pawBL"></g><g id="pawBR"></g>`;
  const front = () => `<g id="pawFL"></g><g id="pawFR"></g><g id="fx"></g>`;
  const shadow = `<ellipse cx="${W / 2}" cy="${H - 6}" rx="170" ry="7" fill="#000" opacity=".1"/>`;
  const sideOf = (A, code) => { const k = A.keyOf(code); return k ? ((k.x + k.w / 2) / 18.25 < 0.5 ? 'L' : 'R') : (code % 2 ? 'L' : 'R'); };

  // ================= 邦戈鼓 =================
  const lbongo = {
    name: '邦戈猫·鼓', size: [W, H],
    svg: () => `${shadow}${cat()}${layers()}${tableEdge()}
      ${drum(140, T + 26, 50, 76, 'drumL')}${drum(264, T + 24, 44, 74, 'drumR')}${front()}`,
    create(svg, ctx) {
      const X = { L: 140, R: 264 }, TIP = { L: T + 26, R: T + 24 };
      const rig = makeRig(svg, { L: 142, R: 262 });
      const q = s => svg.querySelector(s);
      function hit(side) {
        rig.slam(side, X[side], TIP[side]);
        const d = q('#drum' + side);
        shake(d);
        const h = d.querySelector('.hit');
        h.setAttribute('opacity', '1');
        rig.later(() => h.setAttribute('opacity', '0'), 160);
        if (Math.random() < 0.3) ctx.note(X[side], T - 10);
      }
      return {
        key(down, code) { if (!down) return; if (code === 57) { hit('L'); hit('R'); } else hit(sideOf(ctx.A, code)); },
        mouse(down, button) { if (down) hit(button === 2 ? 'R' : 'L'); },
        dispose: rig.dispose
      };
    }
  };

  // ================= 拍桌 =================
  const ltable = {
    name: '邦戈猫·拍桌', size: [W, H],
    svg: () => `${shadow}${cat()}${layers()}
      <g id="tbl">
        <path d="M8 ${T}H${W - 8}L${W - 2} ${T + 44}H2Z" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
        <path d="M2 ${T + 44}V${T + 58}H${W - 2}V${T + 44}" fill="#fff" stroke="${INK}" stroke-width="${SW}" stroke-linejoin="round"/>
        <path d="M30 ${T + 14}H90M300 ${T + 26}H370" stroke="${INK}" stroke-width="1.6" opacity=".3" stroke-linecap="round"/>
        <path d="M24 ${T + 58}V${H - 8}M${W - 24} ${T + 58}V${H - 8}" stroke="${INK}" stroke-width="${SW}" stroke-linecap="round"/>
      </g>
      <g id="cup" transform="translate(338 ${T + 10})">
        <path d="M-14 -22H14L11 4C10 9 -10 9 -11 4Z" fill="#fff" stroke="${INK}" stroke-width="3.2" stroke-linejoin="round"/>
        <path d="M13 -16C22 -16 22 -4 12 -4" fill="none" stroke="${INK}" stroke-width="3" stroke-linecap="round"/>
        <path d="M-5 -30Q-8 -35 -5 -40M3 -30Q0 -35 3 -40" stroke="${INK}" stroke-width="2" fill="none" stroke-linecap="round" opacity=".5"/>
      </g>${front()}`,
    create(svg, ctx) {
      const rig = makeRig(svg, { L: 142, R: 262 });
      const q = s => svg.querySelector(s);
      function slap(side) {
        rig.slam(side, side === 'L' ? 132 : 272, T + 26);
        shake(q('#tbl'));
        const cup = q('#cup');
        cup.animate([{ transform: `translate(338px, ${T + 10}px)` }, { transform: `translate(338px, ${T + 1}px) rotate(${side === 'L' ? -8 : 8}deg)` }, { transform: `translate(338px, ${T + 10}px)` }], { duration: 220, easing: 'ease-out' });
      }
      return {
        key(down, code) { if (!down) return; if (code === 57) { slap('L'); slap('R'); } else slap(sideOf(ctx.A, code)); },
        mouse(down, button) { if (down) slap(button === 2 ? 'R' : 'L'); },
        dispose: rig.dispose
      };
    }
  };

  // ================= 键盘 =================
  const KB = { x: 58, y: T + 10, w: 284, h: 62 };
  const lkeys = {
    name: '邦戈猫·键盘', size: [W, H],
    svg: (s, A) => `${shadow}${cat()}${layers()}${tableEdge()}${keyboard(A, KB.x, KB.y, KB.w, KB.h, 'lk-')}${front()}`,
    create(svg, ctx) {
      const A = ctx.A;
      const rig = makeRig(svg, { L: 142, R: 262 });
      const q = s => svg.querySelector(s);
      const light = (code, on) => { const k = A.keyOf(code); const el = k && q('#lk-' + k.code); if (el) el.setAttribute('fill', on ? PAD : '#fff'); };
      return {
        key(down, code) {
          const c = keyCenter(A, code, KB.x, KB.y, KB.w, KB.h);
          const side = c ? (c.frac < 0.5 ? 'L' : 'R') : sideOf(A, code);
          light(code, down);
          if (down) rig.slam(side, c ? Math.max(side === 'L' ? 78 : 206, Math.min(side === 'L' ? 196 : 324, c.x)) : (side === 'L' ? 140 : 262), c ? c.y + 3 : T + 30, code);
          else rig.release(side, code);
        },
        mouse(down, button) { const side = button === 2 ? 'R' : 'L'; if (down) rig.slam(side, side === 'L' ? 140 : 262, T + 30); },
        dispose: rig.dispose
      };
    }
  };

  // ================= 键鼠 =================
  const DK = { x: 22, y: T + 12, w: 214, h: 56 };
  const PADR = { x: 258, y: T + 8, w: 128, h: 66 };
  const ldesk = {
    name: '邦戈猫·键鼠', size: [W, H],
    svg: (s, A) => `${shadow}${cat()}${layers()}${tableEdge()}${keyboard(A, DK.x, DK.y, DK.w, DK.h, 'lk-')}
      <rect x="${PADR.x}" y="${PADR.y + 3}" width="${PADR.w}" height="${PADR.h}" rx="12" fill="${INK}" opacity=".12"/>
      <rect x="${PADR.x}" y="${PADR.y}" width="${PADR.w}" height="${PADR.h}" rx="12" fill="#fff" stroke="${INK}" stroke-width="${SW - 0.5}"/>
      <rect x="${PADR.x + 6}" y="${PADR.y + 6}" width="${PADR.w - 12}" height="${PADR.h - 12}" rx="8" fill="none" stroke="${INK}" stroke-width="1.3" stroke-dasharray="4 4" opacity=".35"/>
      <g id="lmouse">
        <path d="M-13 -14C-13 -24 13 -24 13 -14V6C13 18 -13 18 -13 6Z" fill="#fff" stroke="${INK}" stroke-width="3.2"/>
        <path id="lmL" d="M-11.6 4H-0.8V16.6C-6 16.4 -11.6 13 -11.6 6Z" fill="#fff"/>
        <path id="lmR" d="M11.6 4H0.8V16.6C6 16.4 11.6 13 11.6 6Z" fill="#fff"/>
        <path d="M-13 4H13M0 4V17" stroke="${INK}" stroke-width="2"/>
        <rect id="lmW" x="-2.2" y="6" width="4.4" height="7" rx="2.2" fill="${INK}"/>
      </g>
      ${front()}`,
    create(svg, ctx) {
      const A = ctx.A;
      const rig = makeRig(svg, { L: 142, R: 262 });
      const q = s => svg.querySelector(s);
      let pos = { x: 0.5, y: 0.5 }, pressing = false;
      rig.st.R.forceDown = true;            // the right paw always holds the mouse
      const light = (code, on) => { const k = A.keyOf(code); const el = k && q('#lk-' + k.code); if (el) el.setAttribute('fill', on ? PAD : '#fff'); };
      function placeMouse() {
        // x range stays under the cat's body so the arm never pokes out past its side
        const mx = PADR.x + 16 + pos.x * (PADR.w - 84), my = PADR.y + 24 + pos.y * (PADR.h - 40);
        q('#lmouse').setAttribute('transform', `translate(${mx.toFixed(1)} ${my.toFixed(1)})`);
        rig.st.R.x = mx; rig.st.R.tip = my - (pressing ? 2 : 6);
        rig.draw();
      }
      placeMouse();
      let raf = 0;
      return {
        key(down, code) {
          const c = keyCenter(A, code, DK.x, DK.y, DK.w, DK.h);
          light(code, down);
          if (down) rig.slam('L', c ? Math.max(74, Math.min(210, c.x)) : 130, c ? c.y + 3 : T + 30, code);
          else rig.release('L', code);
        },
        mouse(down, button) {
          const id = button === 1 ? '#lmL' : button === 2 ? '#lmR' : null;
          if (id) q(id).setAttribute('fill', down ? PAD : '#fff');
          if (button === 3) q('#lmW').setAttribute('fill', down ? HIT : INK);
          pressing = down && button !== 3;
          placeMouse();
        },
        move(p) { pos = p; if (!raf) raf = requestAnimationFrame(() => { raf = 0; placeMouse(); }); },
        wheel(dir) { const w = q('#lmW'); w.setAttribute('transform', `translate(0 ${dir > 0 ? 1.5 : -1.5})`); rig.later(() => w.removeAttribute('transform'), 120); },
        dispose() { rig.dispose(); cancelAnimationFrame(raf); }
      };
    }
  };

  root.BongoModes = Object.assign(root.BongoModes || {}, { lbongo, ltable, lkeys, ldesk });
})(typeof window !== 'undefined' ? window : globalThis);
