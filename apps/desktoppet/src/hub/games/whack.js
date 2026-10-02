// 打地鼠 — whack-a-mole game module for the hub. See ../MODULES.md for the contract.
(function () {
  const ROUND_MS = 60000;
  const HOLES = 9;
  const PTS = { mole: 10, gold: 30, bomb: -30 };
  const HIT_SHOW_MS = 380;
  const KEYS = { Digit7: 0, Digit8: 1, Digit9: 2, Digit4: 3, Digit5: 4, Digit6: 5, Digit1: 6, Digit2: 7, Digit3: 8,
    Numpad7: 0, Numpad8: 1, Numpad9: 2, Numpad4: 3, Numpad5: 4, Numpad6: 5, Numpad1: 6, Numpad2: 7, Numpad3: 8 };

  let cleanup = null;

  const lerp = (a, b, t) => a + (b - a) * t;

  const MOLE_SVG = kind => {
    if (kind === 'bomb') {
      return `<svg viewBox="0 0 100 100" class="wh-svg">
        <path d="M62 22 q8 -12 18 -8" stroke="#8a5634" stroke-width="4" fill="none" stroke-linecap="round"/>
        <g class="wh-spark"><circle cx="81" cy="13" r="6" fill="#ffd34d"/><circle cx="81" cy="13" r="3" fill="#fff6c8"/></g>
        <rect x="50" y="20" width="16" height="12" rx="3" fill="#555" transform="rotate(20 58 26)"/>
        <circle cx="50" cy="60" r="34" fill="#3b3440"/>
        <ellipse cx="38" cy="46" rx="9" ry="6" fill="#fff" opacity=".25" transform="rotate(-30 38 46)"/>
        <g class="wh-eyes-open"><path d="M34 58 l10 4 M66 58 l-10 4" stroke="#ff8a7a" stroke-width="4" stroke-linecap="round"/></g>
        <g class="wh-eyes-x"><path d="M34 54l8 8M42 54l-8 8M58 54l8 8M66 54l-8 8" stroke="#ff8a7a" stroke-width="4" stroke-linecap="round"/></g>
        <path d="M40 76 q10 -6 20 0" stroke="#ff8a7a" stroke-width="3.5" fill="none" stroke-linecap="round"/>
      </svg>`;
    }
    const gold = kind === 'gold';
    const body = gold ? '#f2b705' : '#a86b43';
    const dark = gold ? '#c98a00' : '#7a4a2c';
    const belly = gold ? '#fff0a8' : '#e9c29b';
    return `<svg viewBox="0 0 100 100" class="wh-svg">
      ${gold ? '<path d="M34 16 l6 10 l10 -12 l10 12 l6 -10 l-2 18 h-28z" fill="#ffd34d" stroke="#c98a00" stroke-width="2" stroke-linejoin="round"/>' : ''}
      <circle cx="26" cy="32" r="9" fill="${dark}"/><circle cx="74" cy="32" r="9" fill="${dark}"/>
      <circle cx="26" cy="32" r="4.5" fill="#f4a3a0"/><circle cx="74" cy="32" r="4.5" fill="#f4a3a0"/>
      <path d="M12 100 V62 a38 38 0 0 1 76 0 V100z" fill="${body}" stroke="${dark}" stroke-width="2.5"/>
      <ellipse cx="50" cy="84" rx="24" ry="20" fill="${belly}"/>
      <g class="wh-eyes-open">
        <circle cx="37" cy="54" r="5.5" fill="#3a2418"/><circle cx="63" cy="54" r="5.5" fill="#3a2418"/>
        <circle cx="35.5" cy="52" r="2" fill="#fff"/><circle cx="61.5" cy="52" r="2" fill="#fff"/>
      </g>
      <g class="wh-eyes-x">
        <path d="M32 49l10 10M42 49l-10 10M58 49l10 10M68 49l-10 10" stroke="#3a2418" stroke-width="3.5" stroke-linecap="round"/>
      </g>
      <ellipse cx="26" cy="66" rx="6" ry="3.5" fill="#f28b82" opacity=".6"/><ellipse cx="74" cy="66" rx="6" ry="3.5" fill="#f28b82" opacity=".6"/>
      <ellipse cx="50" cy="64" rx="7" ry="5" fill="#e0637a"/>
      <path d="M30 66 h-14 M30 70 l-13 4 M70 66 h14 M70 70 l13 4" stroke="${dark}" stroke-width="1.6" stroke-linecap="round"/>
      <path d="M44 70 q6 5 12 0" stroke="#3a2418" stroke-width="2" fill="none" stroke-linecap="round"/>
      <rect x="46" y="72" width="8" height="7" rx="1.5" fill="#fff" stroke="${dark}" stroke-width="1"/>
      ${gold ? '<path d="M84 44 l2 5 l5 2 l-5 2 l-2 5 l-2 -5 l-5 -2 l5 -2z M14 76 l1.5 4 l4 1.5 l-4 1.5 l-1.5 4 l-1.5 -4 l-4 -1.5 l4 -1.5z" fill="#fff" class="wh-twinkle"/>' : ''}
    </svg>`;
  };

  function mount(el, ctx) {
    // ---------- DOM ----------
    const root = document.createElement('div');
    root.className = 'wh-root';
    root.innerHTML = `
      <div class="wh-bar">
        <div class="wh-stats">
          <div class="wh-stat"><span class="wh-lbl">得分</span><b class="wh-score">0</b></div>
          <div class="wh-stat"><span class="wh-lbl">时间</span><b class="wh-time">60</b></div>
          <div class="wh-stat wh-combo-box"><span class="wh-lbl">连击</span><b class="wh-combo">0</b></div>
          <div class="wh-stat"><span class="wh-lbl">最佳</span><b class="wh-best">0</b></div>
        </div>
        <div class="wh-opts">
          <button type="button" class="wh-btn wh-toggle">开始</button>
        </div>
      </div>
      <div class="wh-timebar"><div class="wh-timefill"></div></div>
      <div class="wh-stage">
        <div class="wh-field">
          ${Array.from({ length: HOLES }, (_, i) => `
            <div class="wh-hole" data-i="${i}">
              <div class="wh-pit"></div>
              <div class="wh-mask"><div class="wh-mole"></div></div>
              <div class="wh-dirt"></div>
            </div>`).join('')}
          <div class="wh-hammer"><svg viewBox="0 0 64 64">
            <rect x="29" y="22" width="7" height="38" rx="3" fill="#b07a4f" stroke="#6b3f24" stroke-width="2"/>
            <rect x="10" y="6" width="44" height="22" rx="7" fill="#e8793a" stroke="#6b3f24" stroke-width="2.5"/>
            <rect x="10" y="6" width="8" height="22" rx="3" fill="#f6c89d" stroke="#6b3f24" stroke-width="2"/>
            <rect x="46" y="6" width="8" height="22" rx="3" fill="#f6c89d" stroke="#6b3f24" stroke-width="2"/>
            <path d="M22 11 h18" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity=".5"/>
          </svg></div>
        </div>
        <div class="wh-overlay">
          <div class="wh-card">
            <div class="wh-title"></div>
            <div class="wh-sub"></div>
            <button type="button" class="wh-btn wh-primary wh-ov-btn"></button>
          </div>
        </div>
      </div>
      <div class="wh-help">点击冒头的地鼠（或小键盘 1-9） · 金色地鼠 +${PTS.gold} · 千万别敲炸弹 ${PTS.bomb} · 连击越高得分越多 · 空格 / P 暂停</div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.wh-stage'), field = $('.wh-field'), hammer = $('.wh-hammer');
    const scoreEl = $('.wh-score'), timeEl = $('.wh-time'), comboEl = $('.wh-combo'), bestEl = $('.wh-best');
    const comboBox = $('.wh-combo-box'), timeFill = $('.wh-timefill');
    const overlay = $('.wh-overlay'), ovTitle = $('.wh-title'), ovSub = $('.wh-sub'), ovBtn = $('.wh-ov-btn');
    const toggleBtn = $('.wh-toggle');
    const holeEls = [...root.querySelectorAll('.wh-hole')];
    const holes = holeEls.map(h => ({ el: h, mole: h.querySelector('.wh-mole'), kind: null, phase: 'down', t: 0, dur: 0 }));

    // ---------- state ----------
    let state = 'ready';        // 'ready' | 'play' | 'paused' | 'over'
    let score = 0, combo = 0, maxCombo = 0, hits = 0, left = ROUND_MS, spawnAcc = 0;
    let best = ctx.store.get('best', 0) || 0;
    let raf = 0, lastT = 0;

    // ---------- layout ----------
    function fit() {
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(240, stage.clientWidth - 8);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 8);
      // field = 3 cells wide, 3 cells * 0.9 tall (+ padding)
      const cell = Math.floor(Math.max(70, Math.min((aw - 40) / 3, (ah - 30) / 2.8, 170)));
      field.style.setProperty('--wh-cell', cell + 'px');
    }

    // ---------- HUD ----------
    function updateHud() {
      scoreEl.textContent = score;
      comboEl.textContent = combo;
      bestEl.textContent = Math.max(best, score);
      timeEl.textContent = Math.ceil(left / 1000);
      timeFill.style.width = (left / ROUND_MS * 100) + '%';
      timeFill.classList.toggle('wh-low', left <= 10000);
      toggleBtn.textContent = state === 'play' ? '暂停' : state === 'paused' ? '继续' : state === 'over' ? '再来一局' : '开始';
    }

    function showOverlay(extra) {
      if (state === 'play') { overlay.classList.add('hidden'); return; }
      overlay.classList.remove('hidden');
      if (state === 'ready') {
        ovTitle.textContent = '打地鼠';
        ovSub.innerHTML = '60 秒内敲中尽可能多的地鼠<br>越到后面地鼠越快哦';
        ovBtn.textContent = '开始游戏';
      } else if (state === 'paused') {
        ovTitle.textContent = '已暂停';
        ovSub.textContent = '按 空格 / P 继续';
        ovBtn.textContent = '继续';
      } else {
        ovTitle.textContent = '时间到！';
        ovSub.innerHTML =
          `<div>得分 <b>${score}</b> · 敲中 ${hits} 只 · 最高连击 ${maxCombo}</div>` +
          (extra && extra.coins ? `<div>奖励小鱼干 +${extra.coins}</div>` : '') +
          (extra && extra.newBest ? '<div class="wh-rec">新纪录！</div>' : `<div>最佳 ${best}</div>`);
        ovBtn.textContent = '再来一局';
      }
    }

    function setState(s, extra) {
      state = s;
      root.classList.toggle('wh-playing', s === 'play');
      updateHud();
      showOverlay(extra);
    }

    function resetRound() {
      score = 0; combo = 0; maxCombo = 0; hits = 0; left = ROUND_MS; spawnAcc = 400;
      holes.forEach(h => hideHole(h, true));
      field.querySelectorAll('.wh-float,.wh-pow').forEach(n => n.remove());
    }

    function primary() {
      if (state === 'ready') { resetRound(); setState('play'); }
      else if (state === 'play') setState('paused');
      else if (state === 'paused') setState('play');
      else { resetRound(); setState('play'); }
    }

    // ---------- moles ----------
    function hideHole(h, instant) {
      h.phase = 'down'; h.kind = null; h.t = 0;
      h.el.classList.remove('wh-up', 'wh-hit');
      if (instant) h.el.classList.add('wh-instant');
      if (instant) { void h.el.offsetWidth; h.el.classList.remove('wh-instant'); }
    }

    function spawn(p) {
      const free = holes.filter(h => h.phase === 'down' && h.t <= 0);
      const upCount = holes.filter(h => h.phase === 'up').length;
      const maxUp = 1 + Math.floor(p * 3.2);
      if (!free.length || upCount >= maxUp) return;
      const h = free[(Math.random() * free.length) | 0];
      const r = Math.random();
      const bombP = 0.1 + p * 0.1;
      h.kind = r < bombP ? 'bomb' : r < bombP + 0.08 ? 'gold' : 'mole';
      h.dur = lerp(1350, 620, p) * (h.kind === 'gold' ? 0.75 : 1) * (0.85 + Math.random() * 0.3);
      h.t = h.dur;
      h.phase = 'up';
      h.mole.innerHTML = MOLE_SVG(h.kind);
      h.el.dataset.kind = h.kind;
      h.el.classList.remove('wh-hit');
      h.el.classList.add('wh-up');
    }

    function floatText(h, text, cls) {
      const s = document.createElement('span');
      s.className = 'wh-float ' + (cls || '');
      s.textContent = text;
      s.style.left = (h.el.offsetLeft + h.el.offsetWidth / 2) + 'px';
      s.style.top = (h.el.offsetTop + h.el.offsetHeight * 0.2) + 'px';
      field.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    function pow(x, y, boom) {
      const s = document.createElement('span');
      s.className = 'wh-pow' + (boom ? ' wh-boom' : '');
      s.style.left = x + 'px';
      s.style.top = y + 'px';
      field.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    function popCombo(n) {
      const s = document.createElement('span');
      s.className = 'wh-cpop';
      s.textContent = `连击 ×${n}`;
      comboBox.appendChild(s);
      s.addEventListener('animationend', () => s.remove());
    }

    const multiplier = () => 1 + Math.min(4, Math.floor(combo / 5)) * 0.5;

    function whack(i) {
      if (state !== 'play') return;
      const h = holes[i];
      if (!h) return;
      const rect = h.el.getBoundingClientRect(), fr = field.getBoundingClientRect();
      if (h.phase !== 'up') {
        // empty swing breaks the combo
        if (combo > 0) { combo = 0; updateHud(); }
        return;
      }
      h.phase = 'hit';
      h.t = HIT_SHOW_MS;
      h.el.classList.add('wh-hit');
      const cx = rect.left - fr.left + rect.width / 2, cy = rect.top - fr.top + rect.height * 0.45;
      if (h.kind === 'bomb') {
        combo = 0;
        score = Math.max(0, score + PTS.bomb);
        floatText(h, String(PTS.bomb), 'wh-bad');
        pow(cx, cy, true);
        field.classList.remove('wh-shake'); void field.offsetWidth; field.classList.add('wh-shake');
      } else {
        combo++;
        hits++;
        if (combo > maxCombo) maxCombo = combo;
        const pts = Math.round(PTS[h.kind] * multiplier());
        score += pts;
        floatText(h, '+' + pts, h.kind === 'gold' ? 'wh-gold' : '');
        pow(cx, cy, false);
        if (combo >= 5 && combo % 5 === 0) popCombo(combo);
      }
      updateHud();
    }

    function endRound() {
      holes.forEach(h => hideHole(h));
      const newBest = score > best && score > 0;
      if (newBest) {
        best = score;
        ctx.store.set('best', best);
        ctx.say(`打地鼠新纪录：${score} 分！`);
      }
      const coins = Math.min(15, Math.floor(score / 100));
      if (coins > 0) ctx.reward(coins, '打地鼠');
      setState('over', { newBest, coins });
    }

    // ---------- loop ----------
    function update(dt) {
      left -= dt;
      if (left <= 0) { left = 0; updateHud(); endRound(); return; }
      const p = 1 - left / ROUND_MS;
      for (const h of holes) {
        if (h.phase === 'up') {
          h.t -= dt;
          if (h.t <= 0) {
            if (h.kind !== 'bomb' && combo > 0) combo = 0;   // escaped mole breaks combo
            hideHole(h);
            h.t = 250;              // brief cooldown before reuse
          }
        } else if (h.phase === 'hit') {
          h.t -= dt;
          if (h.t <= 0) { hideHole(h); h.t = 250; }
        } else if (h.t > 0) {
          h.t -= dt;
        }
      }
      spawnAcc -= dt;
      if (spawnAcc <= 0) {
        spawn(p);
        spawnAcc = lerp(900, 360, p) * (0.7 + Math.random() * 0.6);
      }
      updateHud();
    }

    function frame(t) {
      raf = requestAnimationFrame(frame);
      const dt = lastT ? Math.min(100, t - lastT) : 0;
      lastT = t;
      if (state !== 'play') return;
      if (!ctx.isActive()) { setState('paused'); return; }
      update(dt);
    }

    // ---------- input ----------
    function moveHammer(e) {
      const fr = field.getBoundingClientRect();
      hammer.style.left = (e.clientX - fr.left) + 'px';
      hammer.style.top = (e.clientY - fr.top) + 'px';
    }
    function onFieldMove(e) { moveHammer(e); }
    function onFieldEnter() { field.classList.add('wh-hover'); }
    function onFieldLeave() { field.classList.remove('wh-hover'); }
    function onFieldDown(e) {
      if (e.button !== 0) return;
      moveHammer(e);
      hammer.classList.remove('wh-swing'); void hammer.offsetWidth; hammer.classList.add('wh-swing');
      if (state !== 'play') return;
      const h = e.target.closest('.wh-hole');
      if (h && field.contains(h)) whack(+h.dataset.i);
      else if (combo > 0) { combo = 0; updateHud(); }
    }
    function onKey(e) {
      if (!ctx.isActive()) return;
      const tg = e.target;
      if (tg && (tg.tagName === 'INPUT' || tg.tagName === 'TEXTAREA' || tg.isContentEditable)) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      if (e.code in KEYS) {
        e.preventDefault();
        if (state === 'play') whack(KEYS[e.code]);
        return;
      }
      if (e.code === 'Space' || e.code === 'KeyP' || (e.code === 'Enter' && state !== 'play')) {
        e.preventDefault();
        if (e.repeat) return;
        if (document.activeElement && root.contains(document.activeElement)) document.activeElement.blur();
        primary();
      }
    }
    function onToggle(e) { e.currentTarget.blur(); primary(); }

    field.addEventListener('pointermove', onFieldMove);
    field.addEventListener('pointerenter', onFieldEnter);
    field.addEventListener('pointerleave', onFieldLeave);
    field.addEventListener('pointerdown', onFieldDown);
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

    setState('ready');
    fit();
    raf = requestAnimationFrame(frame);

    cleanup = () => {
      cancelAnimationFrame(raf);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      window.removeEventListener('keydown', onKey);
      field.removeEventListener('pointermove', onFieldMove);
      field.removeEventListener('pointerenter', onFieldEnter);
      field.removeEventListener('pointerleave', onFieldLeave);
      field.removeEventListener('pointerdown', onFieldDown);
      toggleBtn.removeEventListener('click', onToggle);
      ovBtn.removeEventListener('click', onToggle);
      root.remove();
    };
  }

  Hub.register({
    id: 'whack',
    title: '打地鼠',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 19v-4a6 6 0 0 1 12 0v4"/><ellipse cx="12" cy="20" rx="9" ry="2" fill="currentColor" fill-opacity=".25"/><circle cx="10" cy="13.5" r=".9" fill="currentColor" stroke="none"/><circle cx="14" cy="13.5" r=".9" fill="currentColor" stroke="none"/><path d="M11 16h2"/><path d="M14.5 3.5l5 3-1.5 2.5-5-3z" fill="currentColor" fill-opacity=".3"/><path d="M17.2 7.8l-2.4 4"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
