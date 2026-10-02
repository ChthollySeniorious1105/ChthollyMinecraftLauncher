// 宠物花园 / 扭蛋机 pages and the 接食物 mini-game. Garden & gacha state is owned by the main process (src/play.js).
(function () {
  const api = window.api;
  const FISH_IC = '<svg class="fish-ic" viewBox="0 0 40 40"><path d="M5 20c5-8 18-9 25 0-7 9-20 8-25 0z" fill="#d9a066"/><path d="M29 20l7-6v12z" fill="#c98f4a"/><circle cx="11" cy="18.5" r="1.6" fill="#4a3426"/></svg>';
  const RAR = { 1: '普通', 2: '稀有', 3: '珍贵' };
  const fmtLeft = ms => {
    const m = Math.ceil(ms / 60e3);
    return m >= 60 ? `${Math.floor(m / 60)} 小时 ${m % 60 ? `${m % 60} 分` : ''}` : `${m} 分钟`;
  };

  // =====================================================================
  // 宠物花园
  // =====================================================================
  // mature crop art on a 60x60 box; the leafy top sits at y≈30 so it pokes out of the soil
  const CROP_ART = {
    radish: g => `<path d="M24 28q-6-14 2-18M30 28q0-16 6-18M36 28q6-12 0-16" stroke="#5aa04a" stroke-width="4" fill="none" stroke-linecap="round"/><ellipse cx="30" cy="38" rx="11" ry="10" fill="${g || '#f06a86'}"/><path d="M30 47l-1 8" stroke="${g || '#f06a86'}" stroke-width="2"/><ellipse cx="26" cy="35" rx="3" ry="2" fill="#fff" opacity=".45"/>`,
    carrot: g => `<path d="M26 22q-4-12 2-14M30 22q0-14 4-16M34 22q6-10 2-14" stroke="#5aa04a" stroke-width="4" fill="none" stroke-linecap="round"/><path d="M21 24h18l-8 32h-2z" fill="${g || '#f28a2a'}"/><path d="M24 32h6M26 40h5M28 48h3" stroke="#c9661a" stroke-width="1.5"/>`,
    tomato: g => `<path d="M30 14v-6" stroke="#5aa04a" stroke-width="3"/><circle cx="30" cy="34" r="16" fill="${g || '#e8453a'}"/><path d="M20 20l10 5 10-5-5 7h-10z" fill="#5aa04a"/><ellipse cx="23" cy="30" rx="4" ry="3" fill="#fff" opacity=".4"/>`,
    corn: g => `<path d="M18 54q-4-26 10-40M42 54q4-26-10-40" fill="#7cc05a"/><ellipse cx="30" cy="30" rx="9" ry="20" fill="${g || '#f7cf3a'}"/><path d="M24 20h12M23 26h14M23 32h14M23 38h14M25 44h10" stroke="#d9a820" stroke-width="1.4"/><path d="M30 10q-2-6 2-8" stroke="#c28a4a" stroke-width="2" fill="none"/>`,
    strawberry: g => `<path d="M16 22q14 42 28 0z" fill="${g || '#e83a5a'}"/><path d="M16 22q14 -8 28 0l-6 4-8-3-8 3z" fill="#5aa04a"/><path d="M30 18v-8" stroke="#5aa04a" stroke-width="3"/>${[[22, 28], [30, 30], [38, 28], [25, 36], [34, 36], [30, 43]].map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="1.2" ry="1.8" fill="#ffe36a"/>`).join('')}`,
    pumpkin: g => `<path d="M30 16q2-8 8-8" stroke="#5a7a3a" stroke-width="3" fill="none" stroke-linecap="round"/><ellipse cx="18" cy="36" rx="10" ry="16" fill="${g || '#f08a2a'}"/><ellipse cx="42" cy="36" rx="10" ry="16" fill="${g || '#f08a2a'}"/><ellipse cx="30" cy="36" rx="12" ry="18" fill="${g || '#f7a040'}"/><path d="M30 18v36" stroke="#d9701a" stroke-width="1.5"/>`
  };
  const GOLD = '#f3c34a';
  function cropSvg(id, golden) { return `<svg viewBox="0 0 60 60">${CROP_ART[id](golden ? GOLD : '')}</svg>`; }
  // sprout grows through three stages before showing the crop itself
  function plantSvg(id, pct, golden) {
    if (pct >= 1) return cropSvg(id, golden);
    const leaf = golden ? '#e2b63a' : '#6ab04c';
    if (pct < 0.34) return `<svg viewBox="0 0 60 60"><path d="M30 56v-8" stroke="${leaf}" stroke-width="3" stroke-linecap="round"/><path d="M30 50q-8-2-9-9 7 0 9 9zM30 50q8-2 9-9-7 0-9 9z" fill="${leaf}"/></svg>`;
    if (pct < 0.67) return `<svg viewBox="0 0 60 60"><path d="M30 58v-22" stroke="${leaf}" stroke-width="3.5" stroke-linecap="round"/><path d="M30 44q-12-2-14-12 11 0 14 12zM30 40q12-3 14-13-11 0-14 13z" fill="${leaf}"/><path d="M30 36q-5-6 0-12 5 6 0 12z" fill="${leaf}"/></svg>`;
    return `<svg viewBox="0 0 60 60" class="gd-big"><path d="M30 58v-30" stroke="${leaf}" stroke-width="4" stroke-linecap="round"/><path d="M30 50q-16-2-18-14 14 0 18 14zM30 44q16-3 18-15-14 0-18 15zM30 36q-12-4-12-16 11 3 12 16z" fill="${leaf}"/><circle cx="30" cy="24" r="5" fill="${golden ? GOLD : '#f6f0a0'}"/></svg>`;
  }

  let gdCleanup = null;
  Hub.register({
    id: 'garden', title: '宠物花园', group: 'pet', order: 1.3,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21v-9"/><path d="M12 12c0-4 3-7 7-7 0 4-3 7-7 7z"/><path d="M12 14c0-3-2.5-5.5-6-5.5 0 3 2.5 5.5 6 5.5z"/><path d="M4 21h16"/></svg>',
    mount(el, ctx) {
      el.innerHTML = `
        <div class="gd-root">
          <h2 class="page-title">宠物花园 <span class="set-sub">种下种子，关掉程序也会继续生长；浇过水长得快一倍</span></h2>
          <div class="gd-bar">
            <div class="gd-stat"><span>小鱼干</span><b class="gd-coins"></b></div>
            <div class="gd-stat"><span>累计收获</span><b class="gd-harv"></b></div>
            <div class="gd-acts"><button class="btn gd-waterall">💧 全部浇水</button><button class="btn primary gd-harvall">🧺 全部收获</button></div>
          </div>
          <div class="gd-field"><div class="gd-sky"><div class="gd-sun"></div><img class="gd-pet" alt=""></div><div class="gd-plots"></div></div>
          <div class="gd-tip set-sub">点空地选种子 · 点作物浇水 / 收获 · 每块地有 6% 几率长出价值三倍的金色作物</div>
          <div class="gd-pick hidden"></div>
        </div>`;
      const q = s => el.querySelector(s);
      let st = api.play.get(), timer = 0;

      function render() {
        const g = st.garden, c = api.care.get();
        q('.gd-coins').innerHTML = `${FISH_IC}${c.coins}`;
        q('.gd-harv').textContent = g.harvests;
        q('.gd-pet').src = api.petImage(api.settings.get().pet);
        const box = q('.gd-plots');
        box.innerHTML = '';
        g.plots.forEach((p, i) => {
          const b = document.createElement('button');
          const crop = p && g.crops.find(x => x.id === p.crop);
          b.className = 'gd-plot' + (p ? (p.ripe ? ' ripe' : '') + (p.wet ? ' wet' : '') + (p.golden && p.pct >= 0.67 ? ' gold' : '') : ' empty');
          b.innerHTML = p
            ? `<div class="gd-soil"></div><div class="gd-plant">${plantSvg(p.crop, p.ripe ? 1 : p.pct, p.golden)}</div>
               ${p.ripe ? '<i class="gd-ready">可收获</i>' : `<div class="gd-info"><b>${crop.name}</b><span>${p.wet ? '💧 ' : ''}${fmtLeft(p.left)}</span><div class="gd-pb"><b style="width:${p.pct * 100}%"></b></div></div>`}
               ${!p.ripe && !p.wet ? '<i class="gd-dry" title="土壤干了，浇水长得更快">💧</i>' : ''}`
            : '<div class="gd-soil"></div><div class="gd-plus">＋</div>';
          b.onclick = () => (!p ? openPick(i) : p.ripe ? op('harvest', i) : !p.wet ? op('water', i) : ctx.toast(`${crop.name}还要 ${fmtLeft(p.left)}`));
          b.oncontextmenu = e => {
            e.preventDefault();
            if (p && !p.ripe && confirm(`铲掉这株${crop.name}吗？种子不会退还`)) op('dig', i);
          };
          box.appendChild(b);
        });
        if (g.nextPlot) {
          const b = document.createElement('button');
          b.className = 'gd-plot lock';
          b.innerHTML = `<div class="gd-plus">🔒</div><span class="gd-price">扩建 ${FISH_IC}${g.nextPlot}</span>`;
          b.onclick = () => op('unlock');
          box.appendChild(b);
        }
        q('.gd-waterall').disabled = !g.plots.some(p => p && !p.ripe && !p.wet);
        q('.gd-harvall').disabled = !g.plots.some(p => p && p.ripe);
      }
      function op(name, a) {
        const r = api.play.garden(name, a);
        if (!r.ok) { if (r.msg) ctx.toast(r.msg); return; }
        st.garden = r.garden;
        if (name === 'harvest') {
          r.got.forEach(x => popCoin(x.i, x.coins, x.golden));
          if (r.got.some(x => x.golden)) ctx.say('金色的作物！闪闪发光 ✨');
        } else if (name === 'water') {
          el.querySelectorAll('.gd-plot').forEach((b, i) => { if (a === -1 || a === i) b.classList.add('splash'); });
        }
        render();
      }
      function popCoin(i, coins, golden) {
        const plot = el.querySelectorAll('.gd-plot')[i];
        if (!plot) return;
        const f = document.createElement('div');
        f.className = 'gd-pop' + (golden ? ' gold' : '');
        f.innerHTML = `${FISH_IC}+${coins}`;
        const r = plot.getBoundingClientRect(), rr = q('.gd-root').getBoundingClientRect();
        f.style.left = `${r.left - rr.left + r.width / 2}px`; f.style.top = `${r.top - rr.top + 20}px`;
        q('.gd-root').appendChild(f);
        setTimeout(() => f.remove(), 1200);
      }
      function openPick(i) {
        const c = api.care.get(), box = q('.gd-pick');
        box.innerHTML = `<div class="card gd-pickc"><div class="gd-pickh"><b>选择种子</b><button class="btn gd-pickx">取消</button></div>
          <div class="gd-seeds">${st.garden.crops.map(cr => {
            const lock = c.level < cr.lv, poor = c.coins < cr.seed;
            return `<button class="gd-seed ${lock ? 'lock' : ''}" data-id="${cr.id}" ${lock || poor ? 'disabled' : ''}>
              <div class="gd-seedic">${cropSvg(cr.id)}</div><b>${cr.name}</b>
              <span>${lock ? `Lv.${cr.lv} 解锁` : `${fmtLeft(cr.min * 60e3)} 成熟`}</span>
              <em><span>${FISH_IC}${cr.seed}</span><span class="gd-sell">卖 ${cr.sell}</span></em></button>`;
          }).join('')}</div></div>`;
        box.classList.remove('hidden');
        box.querySelector('.gd-pickx').onclick = () => box.classList.add('hidden');
        box.querySelectorAll('.gd-seed').forEach(b => { b.onclick = () => { box.classList.add('hidden'); op('plant', { i, crop: b.dataset.id }); }; });
      }
      q('.gd-pick').addEventListener('mousedown', e => { if (e.target === e.currentTarget) e.currentTarget.classList.add('hidden'); });
      q('.gd-waterall').onclick = () => op('water', -1);
      q('.gd-harvall').onclick = () => op('harvest', -1);
      render();
      // growth is time-based, so just refresh the view periodically
      timer = setInterval(() => { st = api.play.get(); render(); }, 15000);
      const off = api.play.onChange(s => { st = s; render(); });
      gdCleanup = () => { clearInterval(timer); if (off) off(); };
    },
    unmount() { if (gdCleanup) gdCleanup(); gdCleanup = null; }
  });

  // =====================================================================
  // 扭蛋机
  // =====================================================================
  const CAPS = [['#f7a8c4', '#fff'], ['#9fd4f2', '#fff'], ['#b8e0a0', '#fff'], ['#ffe07a', '#fff'], ['#c8b0f0', '#fff'], ['#ffb482', '#fff']];
  let gcCleanup = null;
  Hub.register({
    id: 'gacha', title: '扭蛋机', group: 'pet', order: 1.4,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="9" r="6.5"/><path d="M6 13h12v8H6z"/><circle cx="12" cy="17" r="1.6"/><path d="M9 7.5a3 3 0 0 1 3-2"/></svg>',
    mount(el, ctx) {
      el.innerHTML = `
        <div class="gc-root">
          <h2 class="page-title">扭蛋机 <span class="set-sub">每天免费扭一次，集齐 24 款宠物手办</span></h2>
          <div class="gc-top">
            <div class="gc-machine">
              <div class="gc-dome"><div class="gc-balls"></div><div class="gc-shine"></div></div>
              <div class="gc-body">
                <div class="gc-label">GACHA</div>
                <button class="gc-knob" title="扭一次"><i></i></button>
                <div class="gc-slot"><div class="gc-out"></div></div>
              </div>
            </div>
            <div class="gc-side card">
              <div class="gc-price"></div>
              <button class="btn primary gc-spin"></button>
              <div class="gc-rates"><span class="r1">普通 70%</span><span class="r2">稀有 25%</span><span class="r3">珍贵 5%</span></div>
              <div class="set-sub gc-pity"></div>
              <div class="set-sub">重复的手办会换回 <b class="gc-dup"></b> 小鱼干</div>
            </div>
          </div>
          <div class="side-title gc-h">手办陈列柜 <span class="set-sub gc-count"></span></div>
          <div class="gc-shelf"></div>
          <div class="gc-reveal hidden"></div>
        </div>`;
      const q = s => el.querySelector(s);
      let st = api.play.get().gacha, busy = false;
      const balls = q('.gc-balls');
      balls.innerHTML = Array.from({ length: 16 }, (_, i) => {
        const [a, b] = CAPS[i % CAPS.length];
        const x = 12 + (i % 5) * 18 + (Math.floor(i / 5) % 2) * 9, y = 58 - Math.floor(i / 5) * 16;
        return `<i style="left:${x}%;bottom:${100 - y - 30}%;background:linear-gradient(180deg,${a} 50%,${b} 50%);--d:${(i % 4) * 0.08}s"></i>`;
      }).join('');

      function render() {
        const c = api.care.get();
        q('.gc-price').innerHTML = st.free ? '<b class="gc-free">今日免费</b>' : `<b>${FISH_IC}${st.price}</b><span class="set-sub">/ 次 · 拥有 ${c.coins}</span>`;
        q('.gc-spin').textContent = st.free ? '免费扭一次' : '扭一次';
        q('.gc-spin').disabled = busy || (!st.free && c.coins < st.price);
        q('.gc-pity').textContent = `再扭 ${st.pity} 次必出珍贵`;
        q('.gc-dup').textContent = st.dup;
        const got = st.list.filter(x => st.owned[x.id]).length;
        q('.gc-count').textContent = `${got} / ${st.list.length}`;
        q('.gc-shelf').innerHTML = [3, 2, 1].map(r => `<div class="gc-row r${r}"><span class="gc-rowh">${RAR[r]}</span><div>${st.list.filter(x => x.rarity === r).map(x => {
          const n = st.owned[x.id];
          return `<div class="gc-fig ${n ? '' : 'no'}" title="${n ? `${x.name} ×${n}` : '???'}"><span>${n ? x.icon : '?'}</span><em>${n ? x.name : '???'}</em>${n > 1 ? `<i>×${n}</i>` : ''}</div>`;
        }).join('')}</div></div>`).join('');
      }
      function spin() {
        if (busy) return;
        const r = api.play.gacha();
        if (!r.ok) { ctx.toast(r.msg || '扭不动'); return; }
        busy = true;
        const next = api.play.get().gacha;
        const m = q('.gc-machine');
        m.classList.remove('spin'); void m.offsetWidth; m.classList.add('spin');
        const [a] = CAPS[Math.floor(Math.random() * CAPS.length)];
        const cap = q('.gc-out');
        cap.style.background = `linear-gradient(180deg,${r.item.rarity === 3 ? '#ffd24a' : a} 50%,#fff 50%)`;
        cap.className = 'gc-out';
        setTimeout(() => cap.classList.add('drop'), 700);
        setTimeout(() => { st = next; reveal(r); }, 1500);
        render();
      }
      function reveal(r) {
        const box = q('.gc-reveal');
        box.innerHTML = `<div class="gc-rc r${r.item.rarity}"><div class="gc-rays"></div>
          <div class="gc-egg"><div class="gc-egg-t"></div><div class="gc-egg-b"></div></div>
          <div class="gc-rfig">${r.item.icon}</div><b>${r.item.name}</b>
          <div class="gc-rtags"><span class="gc-rar r${r.item.rarity}">${RAR[r.item.rarity]}</span>${r.isNew ? '<span class="gc-new">新手办！</span>' : `<span class="gc-dupt">重复 · ${FISH_IC}+${r.refund}</span>`}</div>
          <button class="btn primary gc-ok">收下</button></div>`;
        box.classList.remove('hidden');
        const close = () => { box.classList.add('hidden'); q('.gc-out').className = 'gc-out'; busy = false; render(); };
        box.querySelector('.gc-ok').onclick = close;
        box.onmousedown = e => { if (e.target === box) close(); };
      }
      q('.gc-spin').onclick = spin;
      q('.gc-knob').onclick = spin;
      render();
      gcCleanup = () => { busy = false; };
    },
    unmount() { if (gcCleanup) gcCleanup(); gcCleanup = null; }
  });

  // =====================================================================
  // 接食物 mini-game: the pet catches falling food with a basket, avoid bombs
  // =====================================================================
  const FOODS = [
    { k: 'apple', pts: 10, w: 30, c: '#e8553a' },
    { k: 'fish', pts: 15, w: 22, c: '#d9a066' },
    { k: 'onigiri', pts: 20, w: 16, c: '#fff' },
    { k: 'cake', pts: 40, w: 7, c: '#f7d7a8' },
    { k: 'star', pts: 0, w: 3, c: '#ffd24a' },      // 5 s double points
    { k: 'heart', pts: 0, w: 2, c: '#f06f7e' },     // +1 life
    { k: 'bomb', pts: 0, w: 16, c: '#3a3a4a' }
  ];
  function drawItem(g, k, x, y, r, t) {
    g.save(); g.translate(x, y); g.rotate(Math.sin(t / 300 + x) * 0.25);
    const circ = (cx, cy, rr, c) => { g.fillStyle = c; g.beginPath(); g.arc(cx, cy, rr, 0, 7); g.fill(); };
    if (k === 'apple') { circ(0, 2, r, '#e8553a'); g.strokeStyle = '#6b3f24'; g.lineWidth = 2.5; g.beginPath(); g.moveTo(0, -r + 2); g.lineTo(2, -r - 5); g.stroke(); g.fillStyle = '#5da35a'; g.beginPath(); g.ellipse(6, -r - 3, 6, 3, -0.5, 0, 7); g.fill(); circ(-r * 0.4, -r * 0.2, r * 0.25, 'rgba(255,255,255,.45)'); }
    else if (k === 'fish') { g.fillStyle = '#d9a066'; g.beginPath(); g.ellipse(-2, 0, r * 1.1, r * 0.6, 0, 0, 7); g.fill(); g.fillStyle = '#c98f4a'; g.beginPath(); g.moveTo(r * 0.8, 0); g.lineTo(r * 1.5, -r * 0.6); g.lineTo(r * 1.5, r * 0.6); g.fill(); circ(-r * 0.6, -2, 2, '#4a3426'); }
    else if (k === 'onigiri') { g.fillStyle = '#fff'; g.strokeStyle = '#e2d6c4'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(0, -r); g.quadraticCurveTo(r * 1.3, r, 0, r); g.quadraticCurveTo(-r * 1.3, r, 0, -r); g.fill(); g.stroke(); g.fillStyle = '#2e3b2c'; g.fillRect(-r * 0.5, r * 0.25, r, r * 0.75); }
    else if (k === 'cake') { g.fillStyle = '#f7d7a8'; g.fillRect(-r, -r * 0.3, r * 2, r * 1.2); g.fillStyle = '#fff'; g.fillRect(-r, -r * 0.5, r * 2, r * 0.45); g.fillStyle = '#f0a4b0'; g.fillRect(-r, r * 0.35, r * 2, r * 0.2); circ(0, -r * 0.8, r * 0.3, '#e8553a'); }
    else if (k === 'star') {
      g.fillStyle = '#ffd24a'; g.shadowColor = '#ffd24a'; g.shadowBlur = 14; g.beginPath();
      for (let i = 0; i < 10; i++) { const a = i * Math.PI / 5 - Math.PI / 2, rr = i % 2 ? r * 0.45 : r; g.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); }
      g.fill();
    } else if (k === 'heart') { g.fillStyle = '#f06f7e'; g.beginPath(); g.moveTo(0, r * 0.8); g.bezierCurveTo(-r * 1.4, -r * 0.2, -r * 0.6, -r * 1.2, 0, -r * 0.4); g.bezierCurveTo(r * 0.6, -r * 1.2, r * 1.4, -r * 0.2, 0, r * 0.8); g.fill(); }
    else if (k === 'bomb') {
      circ(0, 2, r, '#3a3a4a'); circ(-r * 0.35, -r * 0.2, r * 0.25, 'rgba(255,255,255,.3)');
      g.strokeStyle = '#8a6a4a'; g.lineWidth = 2.5; g.beginPath(); g.moveTo(r * 0.4, -r * 0.6); g.quadraticCurveTo(r * 0.8, -r * 1.3, r * 0.3, -r * 1.5); g.stroke();
      circ(r * 0.3, -r * 1.55, 3 + Math.sin(t / 60) * 1.5, '#ffb42a');
    }
    g.restore();
  }

  let ccCleanup = null;
  Hub.register({
    id: 'catch', title: '接食物', group: 'game', order: 31,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 13h16l-2 7H6z"/><path d="M8 13l2-4M16 13l-2-4"/><circle cx="12" cy="4" r="1.8"/></svg>',
    mount(el, ctx) {
      el.innerHTML = `
        <div class="cc-root">
          <div class="cc-hud"><div><span>得分</span><b class="cc-score">0</b></div><div><span>连击</span><b class="cc-combo">0</b></div><div><span>生命</span><b class="cc-lives"></b></div><div><span>最高</span><b class="cc-best"></b></div></div>
          <div class="cc-stage">
            <canvas class="cc-canvas"></canvas>
            <div class="cc-ov"><b class="cc-title">接食物</b><div class="cc-sub">← → / A D 或鼠标移动宠物，接住掉落的食物，躲开炸弹</div>
              <div class="cc-legend"><span>🍎 10</span><span>🐟 15</span><span>🍙 20</span><span>🍰 40</span><span>⭐ 双倍</span><span>❤️ 加命</span><span>💣 扣命</span></div>
              <button class="btn primary cc-go">开始游戏</button></div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      const cv = q('.cc-canvas'), g = cv.getContext('2d');
      const W = 720, H = 460, DPR = Math.min(2, window.devicePixelRatio || 1);
      cv.width = W * DPR; cv.height = H * DPR;
      const petImg = new Image(); petImg.src = api.petImage(api.settings.get().pet);
      let best = ctx.store.get('best', 0);
      let running = false, raf = 0, last = 0, t = 0;
      let px = W / 2, target = W / 2, keys = { l: false, r: false };
      let items = [], parts = [], floats = [], score = 0, combo = 0, lives = 3, spawnT = 0, dbl = 0, hurt = 0, missed = 0;

      function hud() {
        q('.cc-score').textContent = score;
        q('.cc-combo').textContent = combo >= 5 ? `${combo}🔥` : combo;
        q('.cc-lives').textContent = '❤️'.repeat(Math.max(0, lives)) || '—';
        q('.cc-best').textContent = best;
      }
      function start() {
        petImg.src = api.petImage(api.settings.get().pet);
        items = []; parts = []; floats = []; score = 0; combo = 0; lives = 3; spawnT = 0; dbl = 0; hurt = 0; t = 0; missed = 0;
        px = target = W / 2;
        running = true;
        q('.cc-ov').classList.add('hidden');
        hud();
      }
      function over() {
        running = false;
        const isBest = score > best;
        if (isBest) { best = score; ctx.store.set('best', best); }
        api.ach.set('catchBest', score);
        const coins = Math.min(30, Math.floor(score / 40));
        if (coins > 0) ctx.reward(coins, '接食物');
        if (isBest && score >= 200) ctx.say(`接食物新纪录 ${score} 分！`);
        const ov = q('.cc-ov');
        ov.querySelector('.cc-title').textContent = isBest ? '新纪录！' : '游戏结束';
        ov.querySelector('.cc-sub').innerHTML = `得分 <b>${score}</b>${coins ? ` · 获得 ${coins} 小鱼干` : ''}`;
        ov.querySelector('.cc-go').textContent = '再来一局';
        ov.classList.remove('hidden');
        hud();
      }
      function spawn() {
        // difficulty ramps with time: more bombs and faster falls
        const lvl = Math.min(1, t / 90);
        const pool = FOODS.map(f => (f.k === 'bomb' ? f.w * (0.5 + lvl) : f.k === 'heart' && lives >= 5 ? 0 : f.w));
        let r = Math.random() * pool.reduce((a, b) => a + b, 0), i = 0;
        while ((r -= pool[i]) > 0) i++;
        const f = FOODS[i];
        items.push({ f, x: 30 + Math.random() * (W - 60), y: -20, vy: 120 + lvl * 170 + Math.random() * 60, r: f.k === 'cake' ? 16 : 14 });
      }
      function burst(x, y, c, n) { for (let i = 0; i < n; i++) parts.push({ x, y, vx: (Math.random() - 0.5) * 260, vy: -Math.random() * 220, c, t: 0 }); }
      function float(x, y, text, c) { floats.push({ x, y, text, c, t: 0 }); }

      function step(now) {
        raf = requestAnimationFrame(step);
        const dt = Math.min(0.05, (now - (last || now)) / 1000); last = now;
        const paused = running && !ctx.isActive();
        if (running && !paused) update(dt);
        draw(now);
        if (paused) {
          g.fillStyle = 'rgba(255,244,228,.6)'; g.fillRect(0, 0, W, H);
          g.fillStyle = '#6b3f24'; g.textAlign = 'center'; g.font = 'bold 24px "Segoe UI", "Microsoft YaHei", sans-serif';
          g.fillText('已暂停 · 点击画面继续', W / 2, H / 2); g.textAlign = 'start';
        }
      }
      function update(dt) {
        t += dt;
        if (keys.l) target = px - 600 * dt * 2;
        if (keys.r) target = px + 600 * dt * 2;
        target = Math.max(50, Math.min(W - 50, target));
        px += Math.max(-620 * dt, Math.min(620 * dt, target - px));
        spawnT -= dt;
        if (spawnT <= 0) { spawn(); spawnT = Math.max(0.32, 0.9 - t / 120); }
        dbl = Math.max(0, dbl - dt); hurt = Math.max(0, hurt - dt);
        const bx = px, by = H - 62;
        for (const it of items) {
          it.y += it.vy * dt;
          if (!it.done && it.y > by - 10 && it.y < by + 22 && Math.abs(it.x - bx) < 48) {
            it.done = true;
            const k = it.f.k;
            if (k === 'bomb') { lives--; combo = 0; hurt = 0.6; burst(it.x, it.y, '#ff8a3a', 22); float(it.x, it.y - 20, '-1 ❤️', '#e5484d'); }
            else if (k === 'heart') { lives = Math.min(5, lives + 1); burst(it.x, it.y, '#f06f7e', 12); float(it.x, it.y - 20, '+1 ❤️', '#f06f7e'); }
            else if (k === 'star') { dbl = 6; burst(it.x, it.y, '#ffd24a', 18); float(it.x, it.y - 20, '双倍得分!', '#e8a020'); }
            else {
              combo++;
              const pts = it.f.pts * (dbl > 0 ? 2 : 1) * (combo >= 10 ? 2 : combo >= 5 ? 1.5 : 1);
              score += Math.round(pts);
              burst(it.x, it.y, it.f.c, 8);
              float(it.x, it.y - 20, `+${Math.round(pts)}`, dbl > 0 ? '#e8a020' : '#6b3f24');
            }
            hud();
            if (lives <= 0) { over(); return; }
          } else if (!it.done && it.y > H + 20) {
            it.done = true;
            if (it.f.k !== 'bomb' && it.f.k !== 'star' && it.f.k !== 'heart') { combo = 0; missed++; hud(); }
          }
        }
        items = items.filter(it => !it.done);
      }
      function draw(now) {
        g.setTransform(DPR, 0, 0, DPR, 0, 0);
        const sky = g.createLinearGradient(0, 0, 0, H);
        sky.addColorStop(0, '#ffe9c8'); sky.addColorStop(0.6, '#ffd6b0'); sky.addColorStop(1, '#f7c49a');
        g.fillStyle = sky; g.fillRect(0, 0, W, H);
        // soft bokeh background
        for (let i = 0; i < 10; i++) {
          const x = (i * 137 + now / 60) % (W + 80) - 40, y = 60 + (i * 53) % 220;
          g.fillStyle = `rgba(255,255,255,${0.12 + (i % 3) * 0.05})`; g.beginPath(); g.arc(x, y, 18 + (i % 4) * 10, 0, 7); g.fill();
        }
        // ground
        g.fillStyle = '#a8d48a'; g.beginPath(); g.moveTo(0, H - 34);
        for (let x = 0; x <= W; x += 40) g.quadraticCurveTo(x + 20, H - 42, x + 40, H - 34);
        g.lineTo(W, H); g.lineTo(0, H); g.fill();
        g.fillStyle = '#8cc06e'; g.fillRect(0, H - 18, W, 18);
        if (dbl > 0) { g.fillStyle = `rgba(255,210,74,${0.12 + Math.sin(now / 120) * 0.05})`; g.fillRect(0, 0, W, H); }
        for (const it of items) {
          g.fillStyle = 'rgba(0,0,0,.08)'; g.beginPath(); g.ellipse(it.x, H - 30, 10, 3, 0, 0, 7); g.fill();
          drawItem(g, it.f.k, it.x, it.y, it.r, now);
        }
        // pet + basket
        const bx = px, by = H - 62, lean = (target - px) / 40;
        g.save(); g.translate(bx, by + 30); g.rotate(Math.max(-0.12, Math.min(0.12, lean * 0.05)));
        if (hurt > 0 && Math.floor(now / 80) % 2) g.globalAlpha = 0.4;
        if (petImg.complete && petImg.naturalWidth) g.drawImage(petImg, -55, -120, 110, 110);
        g.fillStyle = '#c98f4a'; g.beginPath(); g.moveTo(-48, -32); g.lineTo(48, -32); g.lineTo(38, 0); g.lineTo(-38, 0); g.fill();
        g.strokeStyle = '#a0703a'; g.lineWidth = 2;
        for (let i = -36; i <= 36; i += 12) { g.beginPath(); g.moveTo(i, -30); g.lineTo(i * 0.8, -2); g.stroke(); }
        g.fillStyle = '#d9a066'; g.fillRect(-52, -36, 104, 8);
        g.restore();
        // particles + floating text
        parts = parts.filter(p => (p.t += 1 / 60) < 0.7);
        for (const p of parts) { p.vy += 9; p.x += p.vx / 60; p.y += p.vy / 60; g.fillStyle = p.c; g.globalAlpha = 1 - p.t / 0.7; g.beginPath(); g.arc(p.x, p.y, 3.5, 0, 7); g.fill(); }
        g.globalAlpha = 1;
        floats = floats.filter(f => (f.t += 1 / 60) < 0.9);
        g.textAlign = 'center'; g.font = 'bold 18px "Segoe UI", "Microsoft YaHei", sans-serif';
        for (const f of floats) { g.globalAlpha = 1 - f.t / 0.9; g.fillStyle = f.c; g.fillText(f.text, f.x, f.y - f.t * 40); }
        g.globalAlpha = 1; g.textAlign = 'start';
        if (dbl > 0) { g.fillStyle = '#e8a020'; g.font = 'bold 15px "Segoe UI", "Microsoft YaHei", sans-serif'; g.fillText(`⭐ 双倍 ${dbl.toFixed(1)}s`, 14, 26); }
      }

      q('.cc-go').onclick = start;
      const stage = q('.cc-stage');
      stage.addEventListener('mousemove', e => { if (!running) return; const r = cv.getBoundingClientRect(); target = (e.clientX - r.left) / r.width * W; });
      function onKey(e) {
        if (!ctx.isActive()) return;
        const down = e.type === 'keydown';
        if (['ArrowLeft', 'KeyA'].includes(e.code)) { keys.l = down; e.preventDefault(); }
        else if (['ArrowRight', 'KeyD'].includes(e.code)) { keys.r = down; e.preventDefault(); }
        else if (down && (e.code === 'Space' || e.code === 'Enter') && !running) { e.preventDefault(); start(); }
      }
      window.addEventListener('keydown', onKey);
      window.addEventListener('keyup', onKey);
      hud();
      raf = requestAnimationFrame(step);
      ccCleanup = () => { cancelAnimationFrame(raf); window.removeEventListener('keydown', onKey); window.removeEventListener('keyup', onKey); };
    },
    unmount() { if (ccCleanup) ccCleanup(); ccCleanup = null; }
  });
})();
