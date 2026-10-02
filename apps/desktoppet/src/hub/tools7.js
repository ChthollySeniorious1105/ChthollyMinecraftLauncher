// 外出探险 / 每日任务 page and 钓鱼 mini-game. Game state is owned by the main process (src/play.js).
(function () {
  const api = window.api;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const FISH_IC = '<svg class="fish-ic" viewBox="0 0 40 40"><path d="M5 20c5-8 18-9 25 0-7 9-20 8-25 0z" fill="#d9a066"/><path d="M29 20l7-6v12z" fill="#c98f4a"/><circle cx="11" cy="18.5" r="1.6" fill="#4a3426"/></svg>';
  const FOOD_NAME = { apple: '苹果', milk: '牛奶', onigiri: '饭团', fish: '小鱼干', icecream: '冰淇淋' };
  const fmtLeft = ms => {
    const s = Math.max(0, Math.ceil(ms / 1000)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60;
    return h ? `${h}:${String(m).padStart(2, '0')}:${String(ss).padStart(2, '0')}` : `${m}:${String(ss).padStart(2, '0')}`;
  };
  const dur = min => (min >= 60 ? `${min / 60} 小时` : `${min} 分钟`);

  // =====================================================================
  // 外出探险 + 每日任务
  // =====================================================================
  let advCleanup = null;
  Hub.register({
    id: 'adventure', title: '外出探险', group: 'pet', order: 1.2,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M7 8V6a5 5 0 0 1 10 0v2"/><rect x="4" y="8" width="16" height="13" rx="3"/><path d="M4 13h16M10 13v2h4v-2"/></svg>',
    mount(el, ctx) {
      el.innerHTML = `
        <div class="adv-root">
          <h2 class="page-title">外出探险 <span class="set-sub">派宠物出门冒险，关掉程序也会继续计时，回来会带礼物</span></h2>
          <div class="adv-top">
            <div class="card adv-quests"><div class="adv-qh"><span class="side-title">今日任务</span><span class="set-sub adv-qbonus"></span></div><div class="adv-qlist"></div></div>
            <div class="card adv-trip"></div>
          </div>
          <div class="side-title adv-h">目的地</div>
          <div class="adv-dests"></div>
          <div class="side-title adv-h">纪念品收藏 <span class="set-sub adv-scount"></span></div>
          <div class="card adv-souv"></div>
        </div>`;
      const q = s => el.querySelector(s);
      let st = api.play.get();

      function renderQuests() {
        const qs = st.quests;
        const done = qs.list.filter(x => x.done).length;
        q('.adv-qbonus').textContent = qs.bonus ? `✅ 全部完成，已领取 ${st.bonus} 小鱼干` : `全部完成额外奖励 ${st.bonus} 小鱼干 · ${done}/3`;
        q('.adv-qlist').innerHTML = qs.list.map(x => `
          <div class="adv-q ${x.done ? 'done' : ''}">
            <i>${x.done ? '✔' : ''}</i>
            <div class="adv-qt"><div>${esc(x.text)}</div><div class="adv-qbar"><b style="width:${x.prog / x.n * 100}%"></b></div></div>
            <span class="adv-qr">${x.prog}/${x.n}<em>${FISH_IC}${x.coins}</em></span>
          </div>`).join('');
      }
      function renderTrip() {
        const box = q('.adv-trip');
        const t = st.trip, c = api.care.get();
        if (!t) {
          box.innerHTML = `<div class="adv-home"><img src="${api.petImage(api.settings.get().pet)}" alt=""><div>
            <b>宠物在家</b><div class="set-sub">精力 ${Math.round(c.energy)} / 100 · Lv.${c.level}</div>
            <div class="set-sub">选一个目的地出发吧，路程越远收获越丰富</div></div></div>`;
          return;
        }
        const dest = st.dests.find(d => d.id === t.dest) || { name: '远方', icon: '🧭' };
        const back = t.end <= Date.now();
        if (back) {
          box.innerHTML = `<div class="adv-back"><div class="adv-gift">🎁</div><div><b>从${esc(dest.name)}回来啦！</b>
            <div class="set-sub">带回了一些东西，快打开看看</div>
            <button class="btn primary adv-claim">打开礼物</button></div></div>`;
          q('.adv-claim').onclick = claim;
          return;
        }
        const pct = (Date.now() - t.start) / (t.end - t.start) * 100;
        box.innerHTML = `<div class="adv-away"><div class="adv-away-ic">${dest.icon}</div><div class="adv-away-t">
          <b>正在${esc(dest.name)}探险…</b>
          <div class="adv-prog"><b style="width:${pct.toFixed(1)}%"></b><span class="adv-walker" style="left:${pct.toFixed(1)}%">🐾</span></div>
          <div class="adv-left">还有 <b class="adv-cd">${fmtLeft(t.end - Date.now())}</b> 回来</div>
          <button class="btn adv-recall">提前叫回</button></div></div>`;
        q('.adv-recall').onclick = () => {
          if (!confirm('提前叫回就什么都带不回来了，消耗的精力也不会返还，确定吗？')) return;
          api.play.recall();
        };
      }
      function renderDests() {
        const c = api.care.get(), busy = !!st.trip;
        q('.adv-dests').innerHTML = st.dests.map(d => {
          const locked = c.level < d.lv, tired = c.energy < d.energy;
          const got = d.finds.filter(f => st.souvenirs[f.id]).length;
          return `<button class="adv-dest ${locked ? 'locked' : ''}" data-id="${d.id}" ${busy || locked ? 'disabled' : ''}>
            <div class="adv-dic">${locked ? '🔒' : d.icon}</div>
            <b>${esc(d.name)}</b><div class="set-sub">${esc(d.desc)}</div>
            <div class="adv-meta"><span>⏱ ${dur(d.min)}</span><span class="${tired && !locked ? 'bad' : ''}">⚡ ${d.energy}</span><span>${FISH_IC}${d.coins[0]}-${d.coins[1]}</span></div>
            <div class="adv-dfoot">${locked ? `Lv.${d.lv} 解锁` : `纪念品 ${got}/${d.finds.length}`}</div>
          </button>`;
        }).join('');
        el.querySelectorAll('.adv-dest').forEach(b => b.onclick = () => {
          const r = api.play.trip(b.dataset.id);
          if (!r.ok && r.msg) ctx.toast(r.msg);
        });
      }
      function renderSouv() {
        const all = st.dests.flatMap(d => d.finds.map(f => ({ ...f, dest: d.name })));
        const got = all.filter(f => st.souvenirs[f.id]).length;
        q('.adv-scount').textContent = `${got} / ${all.length}`;
        q('.adv-souv').innerHTML = all.map(f => {
          const n = st.souvenirs[f.id] || 0;
          return `<div class="adv-sv ${n ? '' : 'no'} r${f.rarity}" title="${n ? `${esc(f.name)} · ${st.rarity[f.rarity]} · 来自${esc(f.dest)} · ×${n}` : `未发现 · 来自${esc(f.dest)}`}">
            <span>${n ? f.icon : '?'}</span><em>${n ? esc(f.name) : '???'}</em>${n > 1 ? `<i>${n}</i>` : ''}</div>`;
        }).join('');
      }
      function render() { renderQuests(); renderTrip(); renderDests(); renderSouv(); }

      function claim() {
        const r = api.play.claim();
        if (!r.ok) { if (r.msg) ctx.toast(r.msg); return; }
        const l = r.loot;
        const ov = document.createElement('div');
        ov.className = 'adv-ov';
        ov.innerHTML = `<div class="card adv-ovc">
          <div class="adv-ovic r${l.find.rarity}">${l.find.icon}</div>
          <b>${esc(l.find.name)}</b><div class="adv-rar r${l.find.rarity}">${st.rarity[l.find.rarity]}${r.isNew ? ' · 新发现！' : ''}</div>
          <div class="adv-story">“在${esc(r.dest || '远方')}${esc(l.story)}”</div>
          <div class="adv-ovl"><span>${FISH_IC} +${l.coins}</span><span>✨ 经验 +${l.exp}</span>${l.food ? `<span>🎒 ${FOOD_NAME[l.food] || l.food} ×1</span>` : ''}</div>
          <button class="btn primary">收下</button></div>`;
        ov.querySelector('button').onclick = () => ov.remove();
        ov.onclick = e => { if (e.target === ov) ov.remove(); };
        el.querySelector('.adv-root').appendChild(ov);
        ctx.say(`我${l.story}，还捡到了${l.find.name}！`);
      }

      const off = api.play.onChange(p => { st = p; render(); });
      const careOff = api.care.onChange(() => { renderDests(); if (!st.trip) renderTrip(); });
      const timer = setInterval(() => {
        const t = st.trip;
        if (!t) return;
        if (t.end <= Date.now()) { if (!q('.adv-claim')) renderTrip(); return; }
        const cd = q('.adv-cd');
        if (cd) cd.textContent = fmtLeft(t.end - Date.now());
        const pct = (Date.now() - t.start) / (t.end - t.start) * 100;
        const bar = q('.adv-prog b'), w = q('.adv-walker');
        if (bar) bar.style.width = pct.toFixed(1) + '%';
        if (w) w.style.left = pct.toFixed(1) + '%';
      }, 1000);
      advCleanup = () => { off(); careOff(); clearInterval(timer); };
      render();
    },
    unmount() { if (advCleanup) advCleanup(); advCleanup = null; }
  });

  // =====================================================================
  // 钓鱼
  // =====================================================================
  // rarity 1 普通 / 2 稀有 / 3 珍贵; pull = how hard the fish fights (bar speed); size range in cm; night-only fish
  const FISHES = [
    { id: 'crucian', name: '鲫鱼', r: 1, size: [10, 25], coins: 3, c1: '#a7b0a0', c2: '#6f7a68', shape: 'round', pull: 1.0 },
    { id: 'carp', name: '鲤鱼', r: 1, size: [25, 60], coins: 4, c1: '#e8a15a', c2: '#b86a2a', shape: 'long', pull: 1.1 },
    { id: 'goldfish', name: '金鱼', r: 1, size: [5, 15], coins: 3, c1: '#ff8a4c', c2: '#e2552a', shape: 'fancy', pull: 0.9 },
    { id: 'minnow', name: '小白条', r: 1, size: [6, 12], coins: 2, c1: '#dfe7ee', c2: '#9fb3c4', shape: 'slim', pull: 1.2 },
    { id: 'catfish', name: '鲶鱼', r: 1, size: [30, 80], coins: 5, c1: '#8a7b66', c2: '#54493a', shape: 'cat', pull: 1.2, night: true },
    { id: 'perch', name: '鲈鱼', r: 1, size: [20, 45], coins: 4, c1: '#9fc28a', c2: '#5d8a4a', shape: 'long', pull: 1.3 },
    { id: 'puffer', name: '河豚', r: 2, size: [10, 30], coins: 8, c1: '#f2d27a', c2: '#c9a23a', shape: 'puffer', pull: 1.3 },
    { id: 'salmon', name: '三文鱼', r: 2, size: [50, 90], coins: 9, c1: '#f28c7a', c2: '#c25a4a', shape: 'long', pull: 1.6 },
    { id: 'clown', name: '小丑鱼', r: 2, size: [6, 11], coins: 8, c1: '#ff7a2a', c2: '#ffffff', shape: 'clown', pull: 1.4 },
    { id: 'eel', name: '鳗鱼', r: 2, size: [40, 100], coins: 10, c1: '#6a7a5a', c2: '#3a4a2a', shape: 'eel', pull: 1.7, night: true },
    { id: 'tuna', name: '金枪鱼', r: 2, size: [80, 200], coins: 12, c1: '#5a7ab0', c2: '#2a4a80', shape: 'long', pull: 1.9 },
    { id: 'koi', name: '锦鲤', r: 3, size: [40, 80], coins: 20, c1: '#ffffff', c2: '#e2452a', shape: 'koi', pull: 1.8 },
    { id: 'angler', name: '灯笼鱼', r: 3, size: [20, 50], coins: 22, c1: '#5a4a7a', c2: '#2a1a4a', shape: 'angler', pull: 2.0, night: true },
    { id: 'shark', name: '小鲨鱼', r: 3, size: [100, 250], coins: 25, c1: '#9aa8b8', c2: '#5a6878', shape: 'shark', pull: 2.3 },
    { id: 'rainbow', name: '彩虹鱼', r: 3, size: [15, 30], coins: 25, c1: '#ff7aa8', c2: '#7ac8ff', shape: 'rainbow', pull: 2.1 },
    { id: 'boot', name: '旧靴子', r: 1, size: [25, 30], coins: 1, c1: '#7a5a3a', c2: '#4a3420', shape: 'boot', pull: 0.6, junk: true }
  ];
  const R_NAME = { 1: '普通', 2: '稀有', 3: '珍贵' };
  const R_W = { 1: 64, 2: 27, 3: 9 };

  // side-view fish drawn on a 100x60 box
  function fishSvg(f, dim) {
    const a = dim ? '#cbbfae' : f.c1, b = dim ? '#b3a795' : f.c2, eye = dim ? '#a89a86' : '#2a1a10';
    const body = {
      round: `<ellipse cx="46" cy="30" rx="30" ry="19" fill="${a}"/>`,
      long: `<ellipse cx="46" cy="30" rx="36" ry="14" fill="${a}"/><path d="M20 30q26 -8 52 0" stroke="${b}" stroke-width="2" fill="none" opacity=".5"/>`,
      slim: `<ellipse cx="48" cy="30" rx="34" ry="9" fill="${a}"/><path d="M18 30h56" stroke="${b}" stroke-width="2"/>`,
      fancy: `<ellipse cx="44" cy="30" rx="24" ry="17" fill="${a}"/><path d="M40 13q6 -10 14 -2M42 47q6 10 14 2" fill="${b}"/>`,
      cat: `<ellipse cx="48" cy="32" rx="36" ry="13" fill="${a}"/><path d="M14 30q-8 -6 -12 -2M14 34q-8 4 -12 6" stroke="${b}" stroke-width="2" fill="none"/>`,
      puffer: `<circle cx="44" cy="30" r="22" fill="${a}"/>${[0, 45, 90, 135, 180, 225, 270, 315].map(t => { const r = t * Math.PI / 180; return `<path d="M${44 + 21 * Math.cos(r)} ${30 + 21 * Math.sin(r)}l${5 * Math.cos(r)} ${5 * Math.sin(r)}" stroke="${b}" stroke-width="2.5"/>`; }).join('')}`,
      clown: `<ellipse cx="46" cy="30" rx="28" ry="16" fill="${a}"/><path d="M34 15v30M52 15v30" stroke="${b}" stroke-width="6"/>`,
      eel: `<path d="M8 30q15 -12 30 0t30 0t20 -4" stroke="${a}" stroke-width="14" fill="none" stroke-linecap="round"/>`,
      koi: `<ellipse cx="46" cy="30" rx="32" ry="15" fill="${a}" stroke="${dim ? a : '#e0c8b8'}" stroke-width="2"/><circle cx="38" cy="26" r="8" fill="${b}"/><circle cx="56" cy="33" r="6" fill="${b}"/>`,
      angler: `<ellipse cx="46" cy="32" rx="26" ry="20" fill="${a}"/><path d="M30 14q4 -12 -8 -12" stroke="${b}" stroke-width="2" fill="none"/><circle cx="21" cy="3" r="4" fill="${dim ? a : '#ffe36a'}"/><path d="M20 38l6 -4 4 4 4 -4 4 4" stroke="#fff" stroke-width="1.6" fill="none"/>`,
      shark: `<path d="M8 32q30 -22 72 -4q-30 18 -72 4z" fill="${a}"/><path d="M40 18l10 -14 4 16z" fill="${b}"/><path d="M14 34h30" stroke="#fff" stroke-width="3" opacity=".6"/>`,
      rainbow: `<ellipse cx="46" cy="30" rx="30" ry="16" fill="${a}"/><path d="M22 26q24 -10 48 0" stroke="#ffe36a" stroke-width="4" fill="none"/><path d="M22 32q24 -8 48 0" stroke="${b}" stroke-width="4" fill="none"/><path d="M24 37q22 -5 44 0" stroke="#8ae08a" stroke-width="3" fill="none"/>`,
      boot: `<path d="M30 6h22v30h26q6 0 6 8v8H30z" fill="${a}"/><path d="M30 44h54" stroke="${b}" stroke-width="4"/><path d="M34 14h14M34 22h14" stroke="${b}" stroke-width="2"/>`
    }[f.shape];
    if (f.shape === 'boot') return `<svg viewBox="0 0 100 60">${body}</svg>`;
    const tail = f.shape === 'eel' ? '' : `<path d="M${f.shape === 'shark' ? 78 : 74} 30l20 -14v28z" fill="${b}"/>`;
    const x = f.shape === 'eel' ? 12 : f.shape === 'shark' ? 20 : 26;
    return `<svg viewBox="0 0 100 60">${tail}${body}<circle cx="${x}" cy="${f.shape === 'eel' ? 28 : 27}" r="3.2" fill="#fff"/><circle cx="${x - 0.6}" cy="${f.shape === 'eel' ? 28 : 27}" r="1.8" fill="${eye}"/></svg>`;
  }

  const isNight = () => { const h = new Date().getHours(); return h >= 19 || h < 6; };
  const timeOfDay = () => { const h = new Date().getHours(); return h >= 6 && h < 17 ? 'day' : h >= 17 && h < 19 ? 'dusk' : 'night'; };
  const fishUrl = f => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(fishSvg(f).replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120" '));
  const SIL = '<svg viewBox="0 0 40 24"><path d="M3 12c7-10 20-11 27 0-7 11-20 10-27 0z"/><path d="M28 12l10-8v16z"/></svg>';

  function rollFish(bait, streak) {
    const pool = FISHES.filter(f => !f.night || isNight());
    // better bait (and a hot streak) shifts weight towards rarer fish and away from junk
    const luck = (bait ? 2 : 1) * (streak >= 3 ? 1.3 : 1);
    const w = pool.map(f => (f.junk ? (bait ? 2 : 8) : R_W[f.r] * (f.r > 1 ? luck : 1)));
    let r = Math.random() * w.reduce((a, b) => a + b, 0), i = 0;
    while ((r -= w[i]) > 0) i++;
    return pool[i];
  }

  // ---------- scene ----------
  const W = 960, H = 540, HZ = 250, DOCK = 338;
  const SCENE = {
    day: {
      sky: ['#6cb8e6', '#b9e0f4', '#eaf6f8'], orb: [720, 84, 30], orbC: '#fff7c8', glow: 'rgba(255,246,200,.6)',
      far: '#a6c9dc', near: '#86b894', trees: '#5d9670', water: ['#9ad4e4', '#4a9cc4', '#1c5a86'], shine: '255,255,255',
      cloud: 'rgba(255,255,255,.92)', dock: ['#b98050', '#8c5a32', '#643e22'], reed: '#5c8a48', cat: '#7a4e2c', pad: ['#5aa05e', '#7cc07a'], shadow: 'rgba(10,40,60,.16)'
    },
    dusk: {
      sky: ['#56629e', '#e58e84', '#ffd29a'], orb: [700, 214, 34], orbC: '#ffe2a6', glow: 'rgba(255,180,120,.65)',
      far: '#a07c9c', near: '#6c5c84', trees: '#4c426a', water: ['#f2b294', '#8e6e9a', '#2c3260'], shine: '255,226,190',
      cloud: 'rgba(255,214,200,.85)', dock: ['#9a6446', '#744830', '#4e2e1e'], reed: '#4a3e58', cat: '#3a2a38', pad: ['#5e6e62', '#7a8a70'], shadow: 'rgba(30,20,50,.2)'
    },
    night: {
      sky: ['#0a1330', '#1c2856', '#3a4380'], orb: [730, 86, 24], orbC: '#fff4d2', glow: 'rgba(255,244,210,.22)',
      far: '#2a3860', near: '#1b2745', trees: '#131c34', water: ['#30507e', '#172c54', '#071327'], shine: '255,244,210',
      cloud: 'rgba(180,190,235,.12)', dock: ['#6e4a30', '#523624', '#362316'], reed: '#16242a', cat: '#241a14', pad: ['#1f3a36', '#2c4e44'], shadow: 'rgba(0,0,0,.28)'
    }
  };
  const rnd = n => { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };

  // everything that never moves is painted once per time of day
  function buildBg(tod, dpr) {
    const S = SCENE[tod], c = document.createElement('canvas');
    c.width = W * dpr; c.height = H * dpr;
    const b = c.getContext('2d');
    b.scale(dpr, dpr);
    let gr = b.createLinearGradient(0, 0, 0, HZ);
    gr.addColorStop(0, S.sky[0]); gr.addColorStop(0.65, S.sky[1]); gr.addColorStop(1, S.sky[2]);
    b.fillStyle = gr; b.fillRect(0, 0, W, HZ);
    if (tod === 'night') {
      for (let i = 0; i < 90; i++) {
        b.fillStyle = `rgba(255,255,255,${0.25 + rnd(i) * 0.7})`;
        const s = rnd(i + 7) < 0.1 ? 2.2 : 1.3;
        b.fillRect(rnd(i + 100) * W, rnd(i + 200) * (HZ - 70), s, s);
      }
    }
    const [ox, oy, orr] = S.orb;
    gr = b.createRadialGradient(ox, oy, 0, ox, oy, orr * 5);
    gr.addColorStop(0, S.glow); gr.addColorStop(1, 'rgba(255,255,255,0)');
    b.fillStyle = gr; b.fillRect(0, 0, W, HZ);
    b.fillStyle = S.orbC; b.beginPath(); b.arc(ox, oy, orr, 0, 7); b.fill();
    if (tod === 'night') {
      b.fillStyle = 'rgba(200,190,160,.35)';
      for (const [dx, dy, r] of [[-7, -5, 5], [6, 4, 4], [-2, 9, 3], [9, -8, 2.5]]) { b.beginPath(); b.arc(ox + dx, oy + dy, r, 0, 7); b.fill(); }
    }
    // far mountains
    b.fillStyle = S.far; b.beginPath(); b.moveTo(0, HZ);
    for (let x = 0; x <= W; x += 24) b.lineTo(x, HZ - 50 - 38 * Math.sin(x / 150 + 1) - 22 * Math.sin(x / 57) - 10 * rnd(x));
    b.lineTo(W, HZ); b.fill();
    // near hills + tree line
    b.fillStyle = S.near; b.beginPath(); b.moveTo(0, HZ);
    for (let x = 0; x <= W; x += 20) b.lineTo(x, HZ - 18 - 16 * Math.sin(x / 210 + 2) - 6 * Math.sin(x / 41));
    b.lineTo(W, HZ); b.fill();
    b.fillStyle = S.trees;
    for (let i = 0; i < 70; i++) {
      const x = rnd(i + 300) * W, h = 10 + rnd(i + 400) * 22, base = HZ - 4 - 14 * Math.sin(x / 210 + 2) * 0.6;
      if (rnd(i + 500) < 0.5) { b.beginPath(); b.moveTo(x - h * 0.32, base); b.lineTo(x, base - h * 1.3); b.lineTo(x + h * 0.32, base); b.fill(); }
      else { b.beginPath(); b.ellipse(x, base - h * 0.5, h * 0.45, h * 0.6, 0, 0, 7); b.fill(); }
    }
    b.fillRect(0, HZ - 5, W, 5);
    // water
    gr = b.createLinearGradient(0, HZ, 0, H);
    gr.addColorStop(0, S.water[0]); gr.addColorStop(0.35, S.water[1]); gr.addColorStop(1, S.water[2]);
    b.fillStyle = gr; b.fillRect(0, HZ, W, H - HZ);
    // mirrored hills on the water
    b.save(); b.globalAlpha = 0.18; b.fillStyle = S.trees; b.beginPath(); b.moveTo(0, HZ);
    for (let x = 0; x <= W; x += 20) b.lineTo(x, HZ + 14 + 12 * Math.sin(x / 210 + 2) + 4 * Math.sin(x / 41));
    b.lineTo(W, HZ); b.fill(); b.restore();
    b.fillStyle = `rgba(${S.shine},.35)`; b.fillRect(0, HZ, W, 1);
    // dock: posts, their reflections, then the deck
    const [top, front, post] = S.dock;
    for (const px of [34, 128, 222]) {
      b.fillStyle = post; b.fillRect(px, DOCK + 16, 16, 86);
      b.fillStyle = 'rgba(0,0,0,.18)'; b.fillRect(px + 10, DOCK + 16, 6, 86);
      b.save(); b.globalAlpha = 0.22; b.fillStyle = post; b.fillRect(px, DOCK + 102, 16, 50); b.restore();
      b.strokeStyle = `rgba(${S.shine},.45)`; b.lineWidth = 1.5; b.beginPath(); b.ellipse(px + 8, DOCK + 100, 16, 4, 0, 0, 7); b.stroke();
    }
    b.fillStyle = 'rgba(0,0,0,.18)'; b.fillRect(0, DOCK + 18, 272, 10);
    b.fillStyle = front; b.fillRect(0, DOCK, 270, 18);
    b.fillStyle = top; b.fillRect(0, DOCK - 10, 276, 11);
    b.fillStyle = 'rgba(255,255,255,.18)'; b.fillRect(0, DOCK - 10, 276, 2);
    b.strokeStyle = 'rgba(0,0,0,.2)'; b.lineWidth = 1;
    for (let x = 38; x < 270; x += 40) { b.beginPath(); b.moveTo(x, DOCK - 10); b.lineTo(x, DOCK + 18); b.stroke(); }
    b.fillStyle = 'rgba(0,0,0,.25)';
    for (let x = 16; x < 270; x += 40) { b.beginPath(); b.arc(x, DOCK + 9, 1.6, 0, 7); b.fill(); }
    return c;
  }

  let fishCleanup = null;
  Hub.register({
    id: 'fishing', title: '钓鱼', group: 'game', order: 30,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 3v10"/><path d="M4 3l12 4"/><path d="M16 7v6"/><path d="M16 13a2 2 0 1 0 2 2"/><path d="M3 20q3 -2 6 0t6 0t6 0"/></svg>',
    mount(el, ctx) {
      el.innerHTML = `
        <div class="fs-root">
          <div class="fs-bar">
            <div class="fs-stats">
              <div class="fs-stat"><span>今日上钩</span><b class="fs-today">0</b></div>
              <div class="fs-stat"><span>连钓</span><b class="fs-streak">0</b></div>
              <div class="fs-stat"><span>图鉴</span><b class="fs-dexn">0/16</b></div>
              <div class="fs-stat"><span>今日可得</span><b class="fs-left"></b></div>
            </div>
            <div class="fs-opts">
              <label class="fs-bait" title="每次抛竿消耗 2 小鱼干，稀有鱼出现概率翻倍"><input type="checkbox"><i></i><span>鱼饵<small>${FISH_IC}2 · 稀有鱼更多</small></span></label>
              <button class="btn fs-dexbtn">📖 图鉴</button>
            </div>
          </div>
          <div class="fs-stage">
            <canvas class="fs-canvas"></canvas>
            <div class="fs-meter hidden">
              <div class="fs-track"><div class="fs-zone"></div><div class="fs-fishmark">${SIL}</div></div>
              <div class="fs-prog"><b></b></div>
            </div>
            <div class="fs-tip"></div>
          </div>
          <div class="fs-foot">
            <div class="fs-steps">
              <div><i>1</i><span><b>抛竿</b>空格 / 点击画面</span></div>
              <div><i>2</i><span><b>收竿</b>浮漂猛沉时立刻按，别被轻啄骗了</span></div>
              <div><i>3</i><span><b>拉线</b>按住上移绿框罩住鱼</span></div>
            </div>
            <div class="fs-basket"><span class="fs-bk-h">今日鱼篓</span><div class="fs-bk"></div></div>
          </div>
          <div class="fs-dex hidden"></div>
        </div>`;
      const q = s => el.querySelector(s);
      const stage = q('.fs-stage'), cv = q('.fs-canvas'), g = cv.getContext('2d');
      const DPR = Math.min(2, window.devicePixelRatio || 1);
      cv.width = W * DPR; cv.height = H * DPR;
      const tip = q('.fs-tip'), meter = q('.fs-meter'), zone = q('.fs-zone'), mark = q('.fs-fishmark'), progB = q('.fs-prog b');
      let st = api.play.get();
      const today = new Date().toDateString();
      const fresh = ctx.store.get('day') !== today;
      let todayN = fresh ? 0 : ctx.store.get('todayN', 0);
      let recent = fresh ? [] : ctx.store.get('recent', []);
      let streak = 0;

      const petImg = new Image();
      const loadPet = () => { petImg.src = api.petImage(api.settings.get().pet); };
      loadPet();
      const offSettings = api.settings.onChange(loadPet);
      let tod = timeOfDay(), bg = buildBg(tod, DPR);

      // phase: idle -> cast (flying) -> wait (with fake nibbles) -> bite -> reel -> result
      let phase = 'idle', t0 = 0, fish = null, biteAt = 0, nibbleAt = 0, nibbleT = -1e9, bobX = 0, bobY = 0, holding = false;
      let bait = false, zoneY = 0.5, zoneV = 0, fishY = 0.5, fishT = 0.5, prog = 0.3, raf = 0, last = 0;
      let ripples = [], drops = [], flyer = null, lastThrash = 0;
      const ZONE_H = 0.26;
      const swimmers = Array.from({ length: 5 }, (_, i) => ({ x: rnd(i + 900) * W, y: HZ + 80 + rnd(i + 910) * (H - HZ - 110), v: (12 + rnd(i + 920) * 18) * (i % 2 ? 1 : -1), s: 0.6 + rnd(i + 930) * 0.7 }));
      const clouds = Array.from({ length: 4 }, (_, i) => ({ x: rnd(i + 950) * W, y: 40 + rnd(i + 960) * 90, s: 0.7 + rnd(i + 970) * 0.7, v: 4 + rnd(i + 980) * 6 }));
      const say = (t, cls) => { tip.textContent = t; tip.className = 'fs-tip' + (cls ? ' ' + cls : ''); };
      const splash = (x, y, n, big) => {
        ripples.push({ x, y, t: performance.now(), big });
        for (let i = 0; i < n; i++) drops.push({ x, y, floor: y, vx: (Math.random() - 0.5) * 160, vy: -80 - Math.random() * (big ? 220 : 120), t: 0 });
      };

      function updStats() {
        q('.fs-today').textContent = todayN;
        q('.fs-streak').textContent = streak >= 3 ? `${streak}🔥` : streak;
        q('.fs-streak').parentElement.classList.toggle('hot', streak >= 3);
        q('.fs-dexn').textContent = `${FISHES.filter(f => st.fishdex[f.id]).length}/${FISHES.length}`;
        q('.fs-left').innerHTML = `${FISH_IC}${st.fishLeft}`;
        q('.fs-bk').innerHTML = recent.length
          ? recent.map(x => { const f = FISHES.find(y => y.id === x.id); return f ? `<span class="r${f.junk ? 0 : f.r}" title="${f.name} · ${x.size} cm">${fishSvg(f)}</span>` : ''; }).join('')
          : '<em>还没有收获，抛一竿试试</em>';
      }
      function reset() { phase = 'idle'; meter.classList.add('hidden'); say('按空格或点击画面抛竿'); }
      function miss(text) { phase = 'result'; t0 = performance.now(); streak = 0; updStats(); say(text, 'bad'); }

      function cast() {
        // bait is paid for in the main process so the coin balance stays authoritative
        bait = false;
        if (q('.fs-bait input').checked) {
          const r = api.care.action('bait');
          if (r.ok) bait = true;
          else { ctx.toast(r.msg || '小鱼干不够买鱼饵了'); q('.fs-bait input').checked = false; }
        }
        phase = 'cast'; t0 = performance.now();
        bobX = 470 + Math.random() * 330; bobY = HZ + 60 + Math.random() * 140;
        say('');
      }
      function hook() {
        const now = performance.now();
        if (phase === 'wait') { miss(now - nibbleT < 400 ? '那只是轻啄，收早啦…' : '太早啦，鱼被吓跑了…'); return; }
        if (phase !== 'bite') return;
        const perfect = now - t0 < 320;
        phase = 'reel';
        zoneY = 0.5; zoneV = 0; fishY = 0.5; fishT = Math.random(); prog = perfect ? 0.5 : 0.3;
        meter.classList.remove('hidden');
        splash(bobX, bobY, 10, true);
        say(perfect ? `完美收竿！${R_NAME[fish.r]}的家伙，按住拉线` : `${R_NAME[fish.r]}的家伙上钩了！按住拉线`, fish.r > 1 ? 'rare' : perfect ? 'good' : '');
      }
      function land(ok) {
        meter.classList.add('hidden');
        if (!ok) { miss('线断了，鱼跑掉了…'); return; }
        phase = 'result'; t0 = performance.now();
        const size = +(fish.size[0] + Math.random() * (fish.size[1] - fish.size[0])).toFixed(1);
        const r = api.play.fish({ id: fish.id, rarity: fish.junk ? 0 : fish.r, size, coins: fish.coins + (size > (fish.size[0] + fish.size[1]) / 2 ? 1 : 0) });
        if (!r.ok) return;
        if (!fish.junk) streak++;
        todayN++;
        recent = [{ id: fish.id, size }, ...recent].slice(0, 10);
        ctx.store.set('day', today); ctx.store.set('todayN', todayN); ctx.store.set('recent', recent);
        st.fishdex = r.dex; st.fishLeft = r.left;
        updStats();
        say('');
        const img = new Image(); img.src = fishUrl(fish);
        flyer = { img, t: performance.now(), x: bobX, y: bobY };
        splash(bobX, bobY, 16, true);
        const f = fish;
        setTimeout(() => { if (fishCleanup) showCatch(f, size, r); }, 650);
        if (fish.r === 3) ctx.say(`钓到了珍贵的${fish.name}！${size} 厘米！`);
      }
      function showCatch(f, size, r) {
        stage.querySelectorAll('.fs-catch').forEach(x => x.remove());
        const ov = document.createElement('div');
        const rk = f.junk ? 0 : f.r;
        ov.className = `fs-catch r${rk}`;
        const best = st.fishdex[f.id].best === size && st.fishdex[f.id].n > 1;
        const pct = (size - f.size[0]) / (f.size[1] - f.size[0]) * 100;
        ov.innerHTML = `<div class="fs-crays"></div><div class="fs-cfish">${fishSvg(f)}</div><b class="fs-cname">${f.name}</b>
          <div class="fs-cbadges"><span class="fs-rar r${rk}">${f.junk ? '垃圾' : R_NAME[f.r]}</span>${r.isNew ? '<span class="fs-badge new">新图鉴</span>' : ''}${best ? '<span class="fs-badge best">最大纪录</span>' : ''}</div>
          <div class="fs-csize"><div><b>${size}</b> cm</div><div class="fs-cbar"><i style="left:${pct}%"></i></div><small><span>${f.size[0]}</span><span>${f.size[1]} cm</span></small></div>
          <div class="fs-ccoin">${r.coins ? `${FISH_IC}+${r.coins}` : r.capped ? '今天的小鱼干奖励已达上限' : ''}</div>`;
        ov.addEventListener('mousedown', e => { e.stopPropagation(); ov.remove(); });
        stage.appendChild(ov);
        setTimeout(() => ov.remove(), 2800);
      }

      function step(now) {
        raf = requestAnimationFrame(step);
        const dt = Math.min(0.05, (now - (last || now)) / 1000); last = now;
        if (phase === 'cast' && now - t0 > 700) {
          phase = 'wait'; biteAt = now + 2000 + Math.random() * 5000; nibbleAt = now + 900 + Math.random() * 1400;
          fish = rollFish(bait, streak);
          splash(bobX, bobY, 8);
          say('耐心等待浮漂下沉…');
        } else if (phase === 'wait') {
          if (now > biteAt) { phase = 'bite'; t0 = now; splash(bobX, bobY, 12, true); say('上钩了！快收竿！', 'hot'); }
          else if (now > nibbleAt && now < biteAt - 600) { nibbleT = now; nibbleAt = now + 700 + Math.random() * 1600; ripples.push({ x: bobX, y: bobY, t: now }); }
        } else if (phase === 'bite' && now - t0 > 1000 - fish.r * 90) {
          miss('慢了一步，鱼溜走了');
        } else if (phase === 'reel') {
          // fish wanders to random targets; faster and jumpier for strong fish
          if (Math.abs(fishY - fishT) < 0.03 || Math.random() < 0.012 * fish.pull) fishT = Math.random();
          fishY += (fishT - fishY) * Math.min(1, dt * 1.6 * fish.pull);
          zoneV += (holding ? 1.9 : -1.6) * dt;
          zoneV *= 0.9;
          zoneY = Math.max(ZONE_H / 2, Math.min(1 - ZONE_H / 2, zoneY + zoneV * dt * 6));
          if (zoneY === ZONE_H / 2 || zoneY === 1 - ZONE_H / 2) zoneV = 0;
          const inside = Math.abs(fishY - zoneY) < ZONE_H / 2;
          prog += (inside ? 0.28 : -0.2 * (0.7 + fish.pull * 0.3)) * dt;
          zone.style.bottom = `${(zoneY - ZONE_H / 2) * 100}%`;
          meter.classList.toggle('in', inside);
          mark.style.bottom = `calc(${fishY * 100}% - 12px)`;
          const p = Math.max(0, Math.min(1, prog));
          progB.style.height = `${p * 100}%`;
          progB.parentElement.classList.toggle('low', p < 0.25);
          if (now - lastThrash > 260 / fish.pull) { lastThrash = now; splash(bobX + (fishY - 0.5) * 70, bobY, 3); }
          if (prog >= 1) land(true); else if (prog <= 0) land(false);
        } else if (phase === 'result' && now - t0 > 1700) reset();
        draw(now, dt);
      }

      function rodGeom(now) {
        // rod pivots at the pet's paw; a = angle above horizontal, bend pulls the tip down
        const bx = 196, by = DOCK - 58;
        let a = 0.66, bend = 0.08;
        if (phase === 'cast') {
          const k = (now - t0) / 700;
          a = k < 0.28 ? 0.66 + k / 0.28 * 0.55 : Math.max(0.5, 1.21 - (k - 0.28) * 2.2);
        } else if (phase === 'reel') { a = holding ? 0.95 : 0.7; bend = (holding ? 0.42 : 0.28) + Math.sin(now / 60) * 0.02 * fish.pull; }
        else if (phase === 'bite') bend = 0.2 + Math.sin(now / 45) * 0.04;
        else a += Math.sin(now / 1400) * 0.02;
        const L = 250;
        return { bx, by, cx: bx + L * 0.55 * Math.cos(a), cy: by - L * 0.55 * Math.sin(a), tx: bx + L * Math.cos(a - bend), ty: by - L * Math.sin(a - bend) };
      }

      function drawBobber(x, y, s, sink) {
        // clipped at the waterline so it visibly dips under
        g.save();
        g.beginPath(); g.rect(x - 20, y - 40, 40, 42); g.clip();
        const yy = y + sink;
        g.strokeStyle = '#333'; g.lineWidth = 1.5 * s; g.beginPath(); g.moveTo(x, yy - 7 * s); g.lineTo(x, yy - 17 * s); g.stroke();
        g.fillStyle = '#ffe36a'; g.beginPath(); g.arc(x, yy - 17 * s, 1.8 * s, 0, 7); g.fill();
        g.fillStyle = '#fff'; g.beginPath(); g.arc(x, yy, 7 * s, 0, 7); g.fill();
        g.fillStyle = '#e5484d'; g.beginPath(); g.arc(x, yy, 7 * s, Math.PI, 0); g.fill();
        g.fillStyle = 'rgba(255,255,255,.7)'; g.beginPath(); g.arc(x - 2.5 * s, yy - 3 * s, 1.8 * s, 0, 7); g.fill();
        g.restore();
      }

      function draw(now, dt) {
        const t = timeOfDay();
        if (t !== tod) { tod = t; bg = buildBg(tod, DPR); }
        const S = SCENE[tod];
        g.setTransform(DPR, 0, 0, DPR, 0, 0);
        g.drawImage(bg, 0, 0, W, H);

        // clouds
        g.fillStyle = S.cloud;
        for (const c of clouds) {
          c.x += c.v * dt; if (c.x > W + 120) c.x = -120;
          for (const [dx, dy, r] of [[0, 0, 22], [24, -8, 26], [50, 0, 20], [24, 6, 22]]) { g.beginPath(); g.ellipse(c.x + dx * c.s, c.y + dy * c.s, r * c.s * 1.2, r * c.s * 0.8, 0, 0, 7); g.fill(); }
        }
        // shimmer on the water, compressed towards the horizon
        for (let i = 0; i < 16; i++) {
          const k = i / 15, y = HZ + 6 + Math.pow(k, 1.6) * (H - HZ - 14), len = 8 + k * 38;
          g.strokeStyle = `rgba(${S.shine},${0.12 + 0.2 * (1 - k)})`; g.lineWidth = 1 + k * 1.2;
          g.beginPath();
          for (let j = 0; j < 6; j++) {
            const x = ((rnd(i * 10 + j) * W + now * 0.012 * (1 + k) * (i % 2 ? 1 : -1)) % (W + 80) + W + 80) % (W + 80) - 40;
            g.moveTo(x, y); g.quadraticCurveTo(x + len / 2, y - 2 - k * 2, x + len, y);
          }
          g.stroke();
        }
        // sun / moon path on the water
        const ox = S.orb[0];
        for (let j = 0; j < 14; j++) {
          const y = HZ + 4 + j * (5 + j * 0.9), w = (46 - j * 1.6) * (0.7 + 0.3 * Math.sin(now / 380 + j * 1.7));
          g.fillStyle = `rgba(${S.shine},${0.5 - j * 0.03})`;
          g.fillRect(ox - w / 2 + Math.sin(now / 500 + j) * 6, y, w, 1.6 + j * 0.15);
        }
        // fish shadows cruising below
        g.fillStyle = S.shadow;
        for (const f of swimmers) {
          f.x += f.v * dt; if (f.x > W + 60) f.x = -60; if (f.x < -60) f.x = W + 60;
          const d = Math.sign(f.v), yy = f.y + Math.sin(now / 900 + f.x / 80) * 4;
          g.beginPath(); g.ellipse(f.x, yy, 22 * f.s, 7 * f.s, 0, 0, 7); g.fill();
          g.beginPath(); g.moveTo(f.x - d * 18 * f.s, yy); g.lineTo(f.x - d * 32 * f.s, yy - 7 * f.s); g.lineTo(f.x - d * 32 * f.s, yy + 7 * f.s); g.fill();
        }
        // lily pads
        for (const [x, y, r, flower] of [[560, 486, 34, true], [628, 512, 24], [880, 402, 20], [410, 520, 26]]) {
          const yy = y + Math.sin(now / 1100 + x) * 1.2;
          g.fillStyle = S.pad[0]; g.beginPath(); g.moveTo(x, yy); g.ellipse(x, yy, r, r * 0.34, 0, 0.35, Math.PI * 2 - 0.05); g.closePath(); g.fill();
          g.fillStyle = S.pad[1]; g.beginPath(); g.ellipse(x - r * 0.15, yy - r * 0.06, r * 0.6, r * 0.18, 0, 0, 7); g.fill();
          if (flower) {
            g.fillStyle = tod === 'night' ? '#b89aae' : '#f7a8c4';
            for (let p = 0; p < 6; p++) { const a = p / 6 * Math.PI * 2; g.beginPath(); g.ellipse(x - 8 + Math.cos(a) * 5, yy - 6 + Math.sin(a) * 2, 5, 3, a, 0, 7); g.fill(); }
            g.fillStyle = '#ffe36a'; g.beginPath(); g.arc(x - 8, yy - 7, 2.6, 0, 7); g.fill();
          }
        }
        // ripples
        ripples = ripples.filter(r => now - r.t < (r.big ? 1100 : 800));
        for (const r of ripples) {
          const k = (now - r.t) / (r.big ? 1100 : 800), s = r.big ? 44 : 26;
          g.strokeStyle = `rgba(${S.shine},${0.8 * (1 - k)})`; g.lineWidth = 1.6;
          g.beginPath(); g.ellipse(r.x, r.y + 2, 6 + s * k, 2 + s * 0.28 * k, 0, 0, 7); g.stroke();
          if (r.big && k > 0.25) { g.beginPath(); g.ellipse(r.x, r.y + 2, s * (k - 0.25), s * 0.28 * (k - 0.25), 0, 0, 7); g.stroke(); }
        }

        // the pet on the dock
        const shake = phase === 'reel' ? (holding ? 1.6 : 0.8) * Math.sin(now / 35) : 0;
        const hop = phase === 'bite' ? -Math.abs(Math.sin(now / 90)) * 5 : 0;
        const PS = 176, px = 58 + shake, py = DOCK - PS * 308 / 320 + 2 + Math.sin(now / 700) * 1.2 + hop;
        g.fillStyle = 'rgba(0,0,0,.2)'; g.beginPath(); g.ellipse(58 + PS / 2, DOCK - 4, 60, 7, 0, 0, 7); g.fill();
        if (petImg.complete && petImg.naturalWidth) g.drawImage(petImg, px, py, PS, PS);

        // rod
        const R = rodGeom(now);
        g.lineCap = 'round';
        g.strokeStyle = '#3e2615'; g.lineWidth = 5;
        g.beginPath(); g.moveTo(R.bx, R.by); g.quadraticCurveTo(R.cx, R.cy, R.tx, R.ty); g.stroke();
        g.strokeStyle = '#8a5a34'; g.lineWidth = 3;
        g.beginPath(); g.moveTo(R.bx, R.by); g.quadraticCurveTo(R.cx, R.cy, R.tx, R.ty); g.stroke();
        g.strokeStyle = '#c7503c'; g.lineWidth = 7;
        g.beginPath(); g.moveTo(R.bx - 14, R.by + 9); g.lineTo(R.bx + 8, R.by - 5); g.stroke();
        g.fillStyle = '#d8d8d8'; g.beginPath(); g.arc(R.bx - 4, R.by + 10, 5, 0, 7); g.fill();

        // line + bobber (smaller near the horizon)
        const s = 0.75 + (bobY - HZ) / (H - HZ) * 0.7;
        let bx = bobX, by = bobY, sink = 0, show = true, sag = 34;
        if (phase === 'idle' || (phase === 'result' && !flyer)) { bx = R.tx + 2 + Math.sin(now / 800) * 3; by = R.ty + 60; sag = 0; }
        else if (phase === 'cast') {
          const k = Math.max(0, ((now - t0) / 700 - 0.28) / 0.72);
          bx = R.tx + (bobX - R.tx) * k; by = R.ty + 60 * (1 - k) + (bobY - R.ty - 60) * k - Math.sin(k * Math.PI) * 120; sag = 10;
        } else if (phase === 'wait') {
          by += Math.sin(now / 420) * 1.4;
          const n = (now - nibbleT) / 240;
          if (n >= 0 && n < 1) sink = Math.sin(n * Math.PI) * 5;
        } else if (phase === 'bite') { sink = 12 + Math.sin(now / 40) * 3; sag = 8; }
        else if (phase === 'reel') { bx = bobX + (fishY - 0.5) * 70 + Math.sin(now / 90) * 3; show = false; sag = 0; }
        else show = false;
        if (!(phase === 'result' && flyer)) {
          g.strokeStyle = tod === 'night' ? 'rgba(255,255,255,.55)' : 'rgba(255,255,255,.85)'; g.lineWidth = 1.1;
          g.beginPath(); g.moveTo(R.tx, R.ty); g.quadraticCurveTo((R.tx + bx) / 2, Math.max(R.ty, by) + sag, bx, by + sink * 0.6); g.stroke();
        }
        if (phase === 'reel') {
          // thrashing fish just below the surface
          g.fillStyle = 'rgba(10,20,40,.35)';
          g.beginPath(); g.ellipse(bx, by + 10, 26, 8, Math.sin(now / 70) * 0.25, 0, 7); g.fill();
          g.strokeStyle = `rgba(${S.shine},.7)`; g.lineWidth = 2;
          g.beginPath(); g.ellipse(bx, by + 2, 18 + Math.sin(now / 80) * 4, 5, 0, 0, 7); g.stroke();
        }
        if (show) drawBobber(bx, by, s, sink);
        if (phase === 'bite') {
          g.fillStyle = '#ffe36a'; g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = 3;
          g.font = '900 34px "Segoe UI", sans-serif'; g.textAlign = 'center';
          const yy = by - 34 - Math.abs(Math.sin(now / 80)) * 6;
          g.strokeText('!', bx, yy); g.fillText('!', bx, yy);
          g.textAlign = 'start';
        }

        // droplets
        drops = drops.filter(d => (d.t += dt) < 0.9);
        g.fillStyle = `rgba(${S.shine},.85)`;
        for (const d of drops) {
          d.vy += 520 * dt; d.x += d.vx * dt; d.y += d.vy * dt;
          if (d.y > d.floor + 4 && d.vy > 0) { d.t = 1; continue; }
          g.beginPath(); g.arc(d.x, d.y, 2.2 * (1 - d.t * 0.6), 0, 7); g.fill();
        }
        // the catch jumps out of the water towards the pet
        if (flyer) {
          const k = (now - flyer.t) / 650;
          if (k >= 1) flyer = null;
          else if (flyer.img.complete && flyer.img.naturalWidth) {
            const x = flyer.x + (150 - flyer.x) * k, y = flyer.y + (DOCK - 120 - flyer.y) * k - Math.sin(k * Math.PI) * 150;
            g.save(); g.translate(x, y); g.rotate(-0.6 + k * 1.4); g.scale(-1, 1);
            g.drawImage(flyer.img, -50, -30, 100, 60); g.restore();
          }
        }
        // reeds in the foreground
        const sway = Math.sin(now / 1300);
        for (let i = 0; i < 14; i++) {
          const x = i < 7 ? 262 + i * 11 + rnd(i) * 8 : 868 + (i - 7) * 13 + rnd(i) * 8, h = 70 + rnd(i + 40) * 70;
          const tx = x + sway * (6 + rnd(i + 60) * 6), ty = H - h;
          g.strokeStyle = S.reed; g.lineWidth = 2.4;
          g.beginPath(); g.moveTo(x, H + 4); g.quadraticCurveTo(x, H - h * 0.5, tx, ty); g.stroke();
          if (rnd(i + 80) < 0.45) { g.strokeStyle = S.cat; g.lineWidth = 6; g.beginPath(); g.moveTo(tx, ty + 4); g.lineTo(tx + sway * 0.8, ty + 20); g.stroke(); }
          else { g.fillStyle = S.reed; g.beginPath(); g.moveTo(x, H - h * 0.3); g.quadraticCurveTo(x + 18, H - h * 0.6, x + 26 + sway * 8, H - h * 0.75); g.quadraticCurveTo(x + 10, H - h * 0.5, x + 2, H - h * 0.25); g.fill(); }
        }
        // fireflies
        if (tod !== 'day') {
          for (let i = 0; i < 16; i++) {
            const x = rnd(i + 700) * W + Math.sin(now / 1500 + i) * 26, y = HZ - 30 + rnd(i + 720) * 110 + Math.cos(now / 1100 + i * 2) * 14;
            const a = (0.5 + 0.5 * Math.sin(now / 400 + i * 3)) * (tod === 'night' ? 1 : 0.5);
            const gr = g.createRadialGradient(x, y, 0, x, y, 9);
            gr.addColorStop(0, `rgba(255,240,150,${a})`); gr.addColorStop(1, 'rgba(255,240,150,0)');
            g.fillStyle = gr; g.fillRect(x - 9, y - 9, 18, 18);
          }
        }
        // soft vignette
        const vg = g.createRadialGradient(W / 2, H / 2, H * 0.45, W / 2, H / 2, W * 0.72);
        vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.22)');
        g.fillStyle = vg; g.fillRect(0, 0, W, H);
      }

      function act() { if (phase === 'idle') cast(); else if (phase === 'wait' || phase === 'bite') hook(); }
      stage.addEventListener('mousedown', e => { if (e.button !== 0) return; if (phase === 'reel') holding = true; else act(); });
      const up = () => { holding = false; };
      window.addEventListener('mouseup', up);
      function onKey(e) {
        if (!ctx.isActive() || e.code !== 'Space') return;
        e.preventDefault();
        if (e.type === 'keydown') { if (e.repeat) return; if (phase === 'reel') holding = true; else act(); }
        else holding = false;
      }
      window.addEventListener('keydown', onKey);
      window.addEventListener('keyup', onKey);

      // 图鉴
      function renderDex() {
        const box = q('.fs-dex'), got = FISHES.filter(f => st.fishdex[f.id]).length;
        box.innerHTML = `<div class="card fs-dexc"><div class="fs-dexh"><b>钓鱼图鉴</b><span class="set-sub">${got} / ${FISHES.length}</span><button class="btn fs-dexx">关闭</button></div>
          <div class="fs-dexbar"><b style="width:${got / FISHES.length * 100}%"></b></div>
          <div class="fs-dexg">${FISHES.map(f => {
            const e = st.fishdex[f.id], rk = f.junk ? 0 : f.r;
            return `<div class="fs-dexi r${rk} ${e ? '' : 'no'}"><div class="fs-dexpic">${fishSvg(f, !e)}</div><b>${e ? f.name : '???'}</b>
              <span class="fs-rar r${rk}">${f.junk ? '垃圾' : R_NAME[f.r]}${f.night ? ' · 🌙 夜行' : ''}</span>
              <em>${e ? `钓到 ${e.n} 次 · 最大 ${e.best} cm` : f.night ? '晚上 7 点后出现' : '尚未钓到'}</em></div>`;
          }).join('')}</div></div>`;
        box.querySelector('.fs-dexx').onclick = () => box.classList.add('hidden');
      }
      q('.fs-dex').addEventListener('mousedown', e => { if (e.target === e.currentTarget) e.currentTarget.classList.add('hidden'); });
      q('.fs-dexbtn').onclick = () => { st = api.play.get(); renderDex(); q('.fs-dex').classList.remove('hidden'); };

      updStats(); reset();
      raf = requestAnimationFrame(step);
      fishCleanup = () => { cancelAnimationFrame(raf); if (offSettings) offSettings(); window.removeEventListener('mouseup', up); window.removeEventListener('keydown', onKey); window.removeEventListener('keyup', onKey); };
    },
    unmount() { if (fishCleanup) fishCleanup(); fishCleanup = null; }
  });
})();
