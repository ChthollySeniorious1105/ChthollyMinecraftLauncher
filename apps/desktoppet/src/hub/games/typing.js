// 打字雨 — type the falling words before they land. See ../MODULES.md for the contract.
(function () {
  const WORDS = [...new Set(`
    cat dog sun sky tree fish bird milk rain snow wind leaf star moon home book pen cup box car bus ship boat road city park
    apple lemon grape peach melon mango berry honey bread cake cookie candy pizza pasta salad soup rice tea coffee juice water
    happy sunny funny lucky quiet brave smart kind calm cozy fresh sweet warm cool bright gentle clever simple little tiny
    river ocean island forest garden valley desert planet rocket bridge castle dragon tiger rabbit turtle monkey panda koala
    zebra horse sheep goat mouse eagle owl whale shark otter beaver penguin kitten puppy parrot dolphin octopus
    red blue green yellow purple orange pink brown black white silver golden
    one two three four five six seven eight nine ten hundred
    play jump run walk swim fly sing dance read write draw paint cook bake sleep dream smile laugh think learn teach build
    open close start stop push pull give take make find keep hold turn move stand sit wait watch listen speak
    music piano guitar violin drum flute song poem story movie game puzzle picture photo camera letter paper pencil
    window door table chair sofa bed lamp clock mirror carpet pillow blanket basket bottle bucket ladder hammer
    school class lesson friend family mother father sister brother baby teacher doctor farmer baker pilot sailor
    morning evening night today tomorrow yesterday week month year summer winter spring autumn season holiday
    cloud storm thunder rainbow breeze frost flame spark shadow light sound voice color shape circle square
    button pocket jacket sweater scarf glove shoe sock hat ring watch wallet ticket station airport market library
    energy signal battery engine motor wheel robot laser orbit comet galaxy pixel screen keyboard mouse cable
    journey travel voyage adventure treasure secret magic wizard knight prince queen giant ninja pirate
    flower rose tulip daisy grass seed root branch forest meadow harbor canyon glacier volcano
    tomato potato carrot pepper onion garlic ginger olive walnut almond peanut noodle butter cheese
  `.trim().split(/\s+/).filter(w => w.length >= 3 && w.length <= 9))];
  const MODES = { normal: { name: '普通', lives: 5 }, zen: { name: '禅模式', time: 120 } };
  const H = 420;           // play field height (px, logical)
  let cleanup = null;

  function mount(el, ctx) {
    let mode = MODES[ctx.store.get('mode')] ? ctx.store.get('mode') : 'normal';
    const bests = ctx.store.get('best', {}) || {};
    const root = document.createElement('div');
    root.className = 'tp-root';
    root.innerHTML = `
      <div class="tp-bar">
        <div class="tp-stats">
          <div class="tp-stat"><span>得分</span><b class="tp-score">0</b></div>
          <div class="tp-stat"><span>WPM</span><b class="tp-wpm">0</b></div>
          <div class="tp-stat"><span>准确率</span><b class="tp-acc">100%</b></div>
          <div class="tp-stat"><span>连击</span><b class="tp-combo">0</b></div>
          <div class="tp-stat"><span>最佳</span><b class="tp-best">0</b></div>
        </div>
        <div class="tp-seg">${Object.entries(MODES).map(([k, m]) => `<button data-m="${k}">${m.name}</button>`).join('')}</div>
      </div>
      <div class="tp-field">
        <div class="tp-sky"></div>
        <div class="tp-words"></div>
        <div class="tp-ground"><div class="tp-lives"></div><div class="tp-level"></div><div class="tp-typed"></div></div>
        <div class="tp-ov"><div class="tp-card"><div class="tp-title">打字雨</div><div class="tp-sub"></div><button class="btn primary tp-go">开始（Enter）</button></div></div>
      </div>
      <div class="tp-help">直接敲键盘输入正在下落的单词 · 自动锁定首字母匹配的单词 · Backspace 退格 / 取消锁定 · Esc 暂停 · 每 10 个单词升一级</div>`;
    el.appendChild(root);
    const q = s => root.querySelector(s);
    const field = q('.tp-field'), wordsBox = q('.tp-words');

    let state = 'ready', words = [], target = null, typed = '', score = 0, lives = 0, level = 1, cleared = 0;
    let combo = 0, maxCombo = 0, keys = 0, hits = 0, chars = 0, startT = 0, elapsed = 0, spawnT = 0, raf = 0, last = 0, timeLeft = 0;

    function hud() {
      q('.tp-score').textContent = score;
      const min = elapsed / 60;
      q('.tp-wpm').textContent = min > 0.05 ? Math.round(chars / 5 / min) : 0;
      q('.tp-acc').textContent = keys ? Math.round(hits / keys * 100) + '%' : '100%';
      q('.tp-combo').textContent = combo;
      q('.tp-best').textContent = bests[mode] || 0;
      q('.tp-lives').innerHTML = mode === 'normal' ? Array.from({ length: MODES.normal.lives }, (_, i) => `<i class="${i < lives ? '' : 'lost'}">♥</i>`).join('') : `<span class="tp-time">⏱ ${Math.ceil(timeLeft)} 秒</span>`;
      q('.tp-level').textContent = `Lv.${level}`;
      q('.tp-typed').textContent = typed;
      root.querySelectorAll('.tp-seg button').forEach(b => b.classList.toggle('on', b.dataset.m === mode));
    }
    function speedFor() { return 26 + level * 7 + Math.random() * 10; }            // px per second
    function spawnGap() { return Math.max(0.55, 2.3 - level * 0.18) * (0.75 + Math.random() * 0.5); }
    function spawn() {
      const used = new Set(words.map(w => w.text[0]));
      // prefer words whose first letter is not already on screen so targeting stays unambiguous
      let text = '';
      for (let i = 0; i < 12; i++) {
        const pool = WORDS.filter(w => w.length <= 4 + level);
        text = pool[(Math.random() * pool.length) | 0];
        if (!used.has(text[0])) break;
      }
      const d = document.createElement('div');
      d.className = 'tp-word';
      d.innerHTML = `<b></b><span>${text}</span>`;
      wordsBox.appendChild(d);
      const w = d.offsetWidth || text.length * 12;
      const fw = field.clientWidth;
      const x = 12 + Math.random() * Math.max(10, fw - w - 24);
      words.push({ text, el: d, x, y: -26, v: speedFor() });
      d.style.left = x + 'px';
    }
    function lock(w) {
      if (target) target.el.classList.remove('lock');
      target = w;
      if (w) w.el.classList.add('lock');
    }
    function paint(w) {
      const n = w === target ? typed.length : 0;
      w.el.querySelector('b').textContent = w.text.slice(0, n);
      w.el.querySelector('span').textContent = w.text.slice(n);
    }
    function pop(w) {
      const r = w.el.getBoundingClientRect(), fr = field.getBoundingClientRect();
      for (let i = 0; i < 10; i++) {
        const p = document.createElement('i');
        p.className = 'tp-p';
        p.style.left = (r.left - fr.left + r.width / 2) + 'px';
        p.style.top = (r.top - fr.top + r.height / 2) + 'px';
        p.style.setProperty('--dx', `${(Math.random() - 0.5) * 120}px`);
        p.style.setProperty('--dy', `${(Math.random() - 0.7) * 100}px`);
        p.style.background = ['#f3c34a', '#e8793a', '#8cc07a', '#7ac8ff'][i % 4];
        field.appendChild(p);
        setTimeout(() => p.remove(), 600);
      }
      const s = document.createElement('div');
      s.className = 'tp-gain';
      s.textContent = `+${w.gain}`;
      s.style.left = (r.left - fr.left + r.width / 2) + 'px';
      s.style.top = (r.top - fr.top) + 'px';
      field.appendChild(s);
      setTimeout(() => s.remove(), 800);
      w.el.remove();
    }
    function complete(w) {
      combo++; maxCombo = Math.max(maxCombo, combo);
      w.gain = w.text.length * 10 * level + Math.min(combo, 20) * 5;
      score += w.gain;
      chars += w.text.length + 1;
      cleared++;
      if (cleared % 10 === 0) { level++; flash(`升到 Lv.${level}！`); }
      words = words.filter(x => x !== w);
      pop(w);
      target = null; typed = '';
    }
    function miss(w) {
      w.el.classList.add('miss');
      setTimeout(() => w.el.remove(), 400);
      words = words.filter(x => x !== w);
      if (w === target) { target = null; typed = ''; }
      combo = 0;
      if (mode === 'normal') {
        lives--;
        field.classList.remove('hurt'); void field.offsetWidth; field.classList.add('hurt');
        if (lives <= 0) end();
      }
    }
    function flash(t) {
      const f = document.createElement('div');
      f.className = 'tp-flash';
      f.textContent = t;
      field.appendChild(f);
      setTimeout(() => f.remove(), 1200);
    }
    function onChar(ch) {
      keys++;
      if (!target) {
        const cand = words.filter(w => w.text[0] === ch).sort((a, b) => b.y - a.y)[0];
        if (!cand) { combo = 0; shakeTyped(); return; }
        lock(cand);
        typed = ch;
        hits++;
      } else if (target.text[typed.length] === ch) {
        typed += ch; hits++;
      } else { combo = 0; shakeTyped(); return; }
      paint(target);
      if (typed === target.text) complete(target);
    }
    function shakeTyped() { const t = q('.tp-typed'); t.classList.remove('err'); void t.offsetWidth; t.classList.add('err'); }

    function start() {
      for (const w of words) w.el.remove();
      words = []; target = null; typed = ''; score = 0; level = 1; cleared = 0;
      combo = 0; maxCombo = 0; keys = 0; hits = 0; chars = 0; elapsed = 0; spawnT = 0.3;
      lives = MODES.normal.lives; timeLeft = MODES.zen.time;
      state = 'run'; last = 0; startT = performance.now();
      q('.tp-ov').classList.add('hidden');
      hud();
    }
    function end() {
      state = 'over';
      const b = bests[mode] || 0;
      const rec = score > b;
      if (rec) { bests[mode] = score; ctx.store.set('best', bests); }
      const wpm = elapsed > 3 ? Math.round(chars / 5 / (elapsed / 60)) : 0;
      const acc = keys ? Math.round(hits / keys * 100) : 100;
      const coins = Math.max(0, Math.min(15, Math.floor(score / 600) + (acc >= 95 && cleared >= 10 ? 2 : 0)));
      if (coins) ctx.reward(coins, '打字雨结算');
      if (rec && score > 500) ctx.say(`打字雨新纪录：${score} 分，${wpm} WPM！手速好快～`);
      q('.tp-title').textContent = rec ? '新纪录！🎉' : mode === 'zen' ? '时间到' : '游戏结束';
      q('.tp-sub').innerHTML = `得分 <b>${score}</b> · 打出 ${cleared} 个单词<br>速度 ${wpm} WPM · 准确率 ${acc}% · 最高连击 ${maxCombo}${coins ? `<br>获得 ${coins} 小鱼干` : ''}`;
      q('.tp-go').textContent = '再来一局（Enter）';
      q('.tp-ov').classList.remove('hidden');
      hud();
    }
    function pause() {
      if (state === 'run') {
        state = 'pause';
        q('.tp-title').textContent = '暂停中';
        q('.tp-sub').textContent = `当前得分 ${score}`;
        q('.tp-go').textContent = '继续（Enter）';
        q('.tp-ov').classList.remove('hidden');
      } else if (state === 'pause') { state = 'run'; last = 0; q('.tp-ov').classList.add('hidden'); }
    }

    function frame(now) {
      raf = requestAnimationFrame(frame);
      if (state !== 'run') { last = now; return; }
      if (!ctx.isActive()) { pause(); return; }
      const dt = Math.min(0.05, (now - (last || now)) / 1000);
      last = now;
      elapsed += dt;
      if (mode === 'zen') { timeLeft -= dt; if (timeLeft <= 0) { timeLeft = 0; end(); return; } }
      spawnT -= dt;
      if (spawnT <= 0) { spawn(); spawnT = spawnGap(); }
      const floor = field.clientHeight - 46;
      for (const w of words.slice()) {
        w.y += w.v * dt * (w === target ? 0.85 : 1);
        w.el.style.transform = `translateY(${w.y.toFixed(1)}px)`;
        w.el.classList.toggle('danger', w.y > floor - 70);
        if (w.y > floor - 10) miss(w);
      }
      hud();
    }

    function onKey(e) {
      if (!ctx.isActive() || e.ctrlKey || e.metaKey || e.altKey) return;
      const tg = e.target && e.target.tagName;
      if (tg === 'INPUT' || tg === 'TEXTAREA' || tg === 'SELECT') return;
      if (e.key === 'Enter') { e.preventDefault(); if (state === 'pause') pause(); else if (state !== 'run') start(); return; }
      if (e.key === 'Escape') { e.preventDefault(); pause(); return; }
      if (state !== 'run') return;
      if (e.key === 'Backspace') {
        e.preventDefault();
        if (target) { typed = typed.slice(0, -1); paint(target); if (!typed) lock(null); }
        return;
      }
      if (e.key.length === 1 && /[a-zA-Z]/.test(e.key)) { e.preventDefault(); onChar(e.key.toLowerCase()); }
      else if (e.key === ' ') e.preventDefault();
    }
    window.addEventListener('keydown', onKey);
    q('.tp-go').onclick = () => (state === 'pause' ? pause() : start());
    root.querySelectorAll('.tp-seg button').forEach(b => b.onclick = () => {
      if (state === 'run' && !confirm('切换模式会结束当前这局，确定吗？')) return;
      mode = b.dataset.m; ctx.store.set('mode', mode);
      state = 'ready';
      for (const w of words) w.el.remove();
      words = [];
      q('.tp-title').textContent = '打字雨';
      q('.tp-sub').innerHTML = intro();
      q('.tp-go').textContent = '开始（Enter）';
      q('.tp-ov').classList.remove('hidden');
      lives = MODES.normal.lives; timeLeft = MODES.zen.time;
      hud();
      b.blur();
    });
    const intro = () => (mode === 'zen' ? '禅模式：没有生命限制，2 分钟内尽量多打<br>单词落地只会打断连击' : `单词从天而降，在落地前把它打出来！<br>漏掉 ${MODES.normal.lives} 个就结束`);

    q('.tp-sub').innerHTML = intro();
    lives = MODES.normal.lives; timeLeft = MODES.zen.time;
    hud();
    raf = requestAnimationFrame(frame);
    cleanup = () => { cancelAnimationFrame(raf); window.removeEventListener('keydown', onKey); };
  }

  Hub.register({
    id: 'typing', title: '打字雨', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="13" width="19" height="8" rx="2"/><path d="M6 16.5h1M9.5 16.5h1M13 16.5h1M16.5 16.5h1"/><path d="M8 3v5M12 2v7M16 4v4" opacity=".7"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
