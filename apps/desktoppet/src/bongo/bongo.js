// 键鼠映射看板 overlay: animates the BongoCat-style SVG from global input events.
(function () {
  const api = window.api;
  const A = window.BongoArt;
  const $ = id => document.getElementById(id);
  let cfg = api.bongo.get();
  let svg = null;                 // active <svg>
  const held = new Set();         // key codes currently down
  let mouseDown = { 1: false, 2: false, 3: false };
  let lastInput = Date.now(), cursor = { x: 0.5, y: 0.5 }, mood = 'normal', moodT = 0;
  let pawTarget = null, pawDownUntil = 0;

  // extra boards (邦戈鼓 / 钢琴猫 / 手柄 / 按键条) are plug-ins from shared/bongo-modes.js
  let extra = null;
  const M = window.BongoModes || {};
  function build() {
    const skin = A.SKINS[cfg.skin] || A.SKINS.orange;
    const cat = $('cat'), kb = $('kb'), ex = $('ex');
    if (extra && extra.dispose) extra.dispose();
    extra = null;
    const mode = M[cfg.mode] ? cfg.mode : cfg.mode === 'keyboard' ? 'keyboard' : 'cat';
    cat.classList.toggle('hidden', mode !== 'cat');
    kb.classList.toggle('hidden', mode !== 'keyboard');
    ex.classList.toggle('hidden', !M[mode]);
    for (const el of [cat, kb, ex]) el.innerHTML = '';
    document.body.dataset.mode = mode;
    if (M[mode]) {
      svg = ex;
      ex.setAttribute('viewBox', `0 0 ${M[mode].size[0]} ${M[mode].size[1]}`);
      ex.innerHTML = M[mode].svg(skin, A);
      extra = M[mode].create(ex, {
        A, skin, cfg,
        note: (x, y) => note(x, y),
        caption: t => { if (!cfg.showKeys) return; const s = document.createElement('span'); s.textContent = t; keysBox.appendChild(s); setTimeout(() => s.remove(), 1700); },
        heldMods: () => [...new Set([...held].filter(c => A.MODS[c]).map(c => A.MODS[c]))]
      });
    } else {
      svg = mode === 'keyboard' ? kb : cat;
      svg.innerHTML = mode === 'keyboard' ? A.kbSvg(skin) : A.catSvg(skin);
    }
    document.body.classList.toggle('through', !!cfg.clickThrough);
    $('keys').style.display = cfg.showKeys ? '' : 'none';
    for (const c of held) light(c, true);
    pose();
  }
  const q = sel => svg.querySelector(sel);
  const qa = sel => svg.querySelectorAll(sel);
  const prefix = () => (cfg.mode === 'keyboard' ? 'kk-' : 'ck-');
  function light(code, on) {
    const k = A.keyOf(code);
    if (!k) return;
    const el = svg.querySelector('#' + prefix() + k.code);
    if (el) el.classList.toggle('on', on);
  }

  // ---------- pose: arms, paws, face ----------
  function pose() {
    if (!svg) return;
    setFace();
    if (cfg.mode !== 'cat') return;
    // left paw: on the last pressed key while typing, otherwise resting up
    const armL = q('#armL'), pawL = q('#pawL');
    const typing = pawTarget && Date.now() < pawDownUntil;
    const lp = typing ? pawTarget : A.PAW_L_REST;
    armL.querySelectorAll('path').forEach(p => p.setAttribute('d', A.armPath(A.SHOULDER_L, lp)));
    pawL.setAttribute('transform', `translate(${lp[0].toFixed(1)} ${lp[1].toFixed(1)}) rotate(${typing ? -20 : 12})`);
    pawL.querySelector('.pads').setAttribute('display', typing ? 'none' : '');
    pawL.querySelector('.top').setAttribute('display', typing ? '' : 'none');
    // right paw holds the mouse, which follows the cursor
    const mp = A.mousePoint(cursor.x, cursor.y);
    q('#mouse').setAttribute('transform', `translate(${mp[0].toFixed(1)} ${mp[1].toFixed(1)}) scale(.9)`);
    const pressing = mouseDown[1] || mouseDown[2] || mouseDown[3];
    const rp = [mp[0] + 1, mp[1] - (pressing ? 10 : 14)];
    q('#armR').querySelectorAll('path').forEach(p => p.setAttribute('d', A.armPath(A.SHOULDER_R, rp)));
    q('#pawR').setAttribute('transform', `translate(${rp[0].toFixed(1)} ${rp[1].toFixed(1)}) rotate(-8) scale(${pressing ? '1.04 .92' : '1'})`);
  }
  function setFace() {
    const idle = Date.now() - lastInput > 60000;
    const m = idle ? 'sleep' : mood;
    const show = (sel, on) => qa(sel).forEach(e => e.setAttribute('display', on ? '' : 'none'));
    show('.eo', m === 'normal' || m === 'wow');
    show('.ehappy', m === 'happy');
    show('.eexcited', m === 'excited');
    show('.esleep', m === 'sleep');
    show('.mouth-w', m !== 'wow' && m !== 'excited');
    show('.mouth-o', m === 'wow' || m === 'excited');
    // pupils follow the cursor
    const px = (cursor.x - 0.5) * 8, py = (cursor.y - 0.5) * 6;
    const p = q('#pupils');
    if (p) p.setAttribute('transform', `translate(${px.toFixed(1)} ${py.toFixed(1)})`);
    // head tilts a little toward the cursor
    const h = q('#head');
    if (h && cfg.mode === 'cat' && !extra) h.setAttribute('transform', `translate(190 104) rotate(${((cursor.x - 0.5) * 6).toFixed(2)})`);
  }
  function setMood(m, ms) { mood = m; clearTimeout(moodT); moodT = setTimeout(() => { mood = 'normal'; pose(); }, ms); pose(); }

  // ---------- effects ----------
  const NOTES = ['♪', '♫', '✦', '♥'];
  function note(x, y) {
    const fx = q('#fx');
    if (!fx || fx.childElementCount > 14) return;
    const skin = A.SKINS[cfg.skin] || A.SKINS.orange;
    const t = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    t.setAttribute('x', x); t.setAttribute('y', y);
    t.setAttribute('font-size', 16 + Math.random() * 8);
    t.setAttribute('fill', Math.random() < 0.5 ? skin.accent : skin.accent2);
    t.setAttribute('stroke', '#fff'); t.setAttribute('stroke-width', '1');
    t.setAttribute('class', 'fx-note');
    t.style.setProperty('--dx', `${(Math.random() - 0.5) * 30}px`);
    t.textContent = NOTES[(Math.random() * NOTES.length) | 0];
    fx.appendChild(t);
    setTimeout(() => t.remove(), 1200);
  }
  function bump() {
    const b = q('.body');
    if (!b) return;
    b.classList.remove('bump'); void b.getBBox(); b.classList.add('bump');
  }

  // key captions (combos like Ctrl + C shown as one chip)
  const keysBox = $('keys');
  function caption(code) {
    if (!cfg.showKeys) return;
    if (A.MODS[code]) return;
    const mods = [...held].filter(c => A.MODS[c] && c !== code).map(c => A.MODS[c]);
    const text = [...new Set(mods), A.keyName(code)].join(' + ');
    const s = document.createElement('span');
    if (mods.length) s.className = 'combo';
    s.textContent = text;
    keysBox.appendChild(s);
    while (keysBox.childElementCount > 6) keysBox.firstElementChild.remove();
    setTimeout(() => s.remove(), 1700);
  }

  // ---------- input ----------
  let streak = 0, streakT = 0;
  api.bongo.onKey(({ down, code }) => {
    lastInput = Date.now();
    if (extra) {
      const repeat = down && held.has(code);
      if (down) held.add(code); else held.delete(code);
      if (!repeat) { if (extra.key) extra.key(down, code); if (down && cfg.mode !== 'strip') caption(code); }
      if (down && !repeat) setMood(mood === 'sleep' ? 'normal' : mood, 1);
      return;
    }
    if (down) {
      if (held.has(code)) return;   // auto-repeat
      held.add(code);
      light(code, true);
      caption(code);
      const p = cfg.mode === 'cat' ? A.keyPoint(code) : null;
      if (p) { pawTarget = p; pawDownUntil = Date.now() + 140; setTimeout(pose, 150); }
      bump();
      streak++;
      clearTimeout(streakT);
      streakT = setTimeout(() => { streak = 0; }, 900);
      if (streak > 0 && streak % 12 === 0) { setMood('excited', 1600); if (cfg.mode === 'cat') note(190 + (Math.random() - 0.5) * 80, 40); else note(150 + Math.random() * 60, 20); }
      else if (mood === 'sleep' || Date.now() - lastInput > 60000) setMood('normal', 1);
    } else {
      held.delete(code);
      light(code, false);
    }
    pose();
  });
  api.bongo.onMouse(({ down, button }) => {
    lastInput = Date.now();
    if (extra) { if (extra.mouse) extra.mouse(down, button); if (down) setMood(button === 2 ? 'wow' : 'happy', 500); return; }
    mouseDown[button] = down;
    const id = button === 1 ? '#mbL' : button === 2 ? '#mbR' : null;
    if (id) { const e = q(id); if (e) e.classList.toggle('on', down); }
    if (button === 3) { const w = q('#mWheel'); if (w) w.setAttribute('fill', down ? (A.SKINS[cfg.skin] || A.SKINS.orange).accent : '#6d645b'); }
    if (down) {
      bump();
      if (button === 2) setMood('wow', 700); else setMood('happy', 500);
      if (cfg.showKeys) {
        const s = document.createElement('span');
        s.textContent = ['', '左键', '右键', '中键'][button] || '鼠标';
        keysBox.appendChild(s);
        while (keysBox.childElementCount > 6) keysBox.firstElementChild.remove();
        setTimeout(() => s.remove(), 1700);
      }
    }
    pose();
  });
  let moveRaf = 0;
  api.bongo.onMove(p => {
    cursor = p;
    lastInput = Date.now();
    if (extra && extra.move) extra.move(p);
    if (cfg.mode === 'keyboard') { const d = q('#dot'); if (d) { d.setAttribute('cx', (4 + p.x * 64).toFixed(1)); d.setAttribute('cy', (4 + p.y * 36).toFixed(1)); } }
    if (!moveRaf) moveRaf = requestAnimationFrame(() => { moveRaf = 0; pose(); });
  });
  let wheelT = 0;
  api.bongo.onWheel(({ dir }) => {
    lastInput = Date.now();
    if (extra && extra.wheel) extra.wheel(dir);
    const up = q('.wheel-up'), dn = q('.wheel-down');
    if (up && dn) { up.classList.toggle('on', dir < 0); dn.classList.toggle('on', dir > 0); clearTimeout(wheelT); wheelT = setTimeout(() => { up.classList.remove('on'); dn.classList.remove('on'); }, 160); }
    const w = q('#mWheel');
    if (w) { w.setAttribute('transform', `translate(0 ${dir > 0 ? 1.5 : -1.5})`); setTimeout(() => w.removeAttribute('transform'), 120); }
  });
  api.bongo.onCfg(c => { const rebuild = c.mode !== cfg.mode || c.skin !== cfg.skin || c.sound !== cfg.sound; cfg = c; if (rebuild) build(); else { $('keys').style.display = cfg.showKeys ? '' : 'none'; document.body.classList.toggle('through', !!cfg.clickThrough); } });

  // when not click-through: drag with the top strip, right click for the menu
  let drag = null;
  $('grip').addEventListener('mousedown', e => { if (e.button === 0) drag = { x: e.screenX, y: e.screenY }; });
  window.addEventListener('mousemove', e => {
    if (!drag) return;
    api.bongo.drag(e.screenX - drag.x, e.screenY - drag.y);
    drag = { x: e.screenX, y: e.screenY };
  });
  window.addEventListener('mouseup', () => { drag = null; });
  window.addEventListener('contextmenu', e => { e.preventDefault(); api.bongo.menu(); });
  // click-through mode still needs a way to reach the menu: hover the cat's head
  window.addEventListener('mousemove', e => {
    if (!cfg.clickThrough) return;
    const h = q('#head');
    if (!h) return;
    const r = h.getBoundingClientRect();
    const over = e.clientX > r.left && e.clientX < r.right && e.clientY > r.top && e.clientY < r.bottom;
    api.bongo.ignore(!over);
  });

  setInterval(() => pose(), 1000);   // idle → sleep face
  build();
})();
