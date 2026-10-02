// Extra pages: 照顾宠物 / 闹钟与倒计时 / 白噪音 / 帮我决定 / 系统监视
(function () {
  const api = window.api;
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const pad = n => String(n).padStart(2, '0');

  const ICON = {
    care: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 20s-7-4.3-8.6-8.6C2.2 8 4.3 4.8 7.4 4.8c2 0 3.5 1.1 4.6 2.6 1.1-1.5 2.6-2.6 4.6-2.6 3.1 0 5.2 3.2 4 6.6C19 15.7 12 20 12 20z"/></svg>',
    alarm: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="13" r="7.5"/><path d="M12 9v4l2.5 2M4 5l3-2.5M20 5l-3-2.5"/></svg>',
    noise: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 12h2M7 8v8M11 5v14M15 9v6M19 7v10"/></svg>',
    wheel: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v17M3.5 12h17M6 6l12 12M18 6L6 18" stroke-width="1.3"/><path d="M12 1.5l-2 3h4z" fill="currentColor"/></svg>',
    sys: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4M6.5 12.5l2.5-3 2.5 2 3-4 3 3" stroke-linecap="round"/></svg>'
  };

  // ============ 照顾宠物 ============
  const ITEMS = {
    apple: ['苹果', '<svg viewBox="0 0 40 40"><path d="M20 13c-4-3-12-2-12 8 0 7 5 13 8 13 2 0 3-1 4-1s2 1 4 1c3 0 8-6 8-13 0-10-8-11-12-8z" fill="#e8553a"/><path d="M20 13c0-3 1-6 3-8" stroke="#6b3f24" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M21 9c3-3 7-3 8-2-2 3-5 4-8 2z" fill="#5da35a"/><ellipse cx="14" cy="19" rx="2" ry="3" fill="#fff" opacity=".4"/></svg>'],
    onigiri: ['饭团', '<svg viewBox="0 0 40 40"><path d="M20 5C14 5 5 22 6 29c1 5 6 6 14 6s13-1 14-6c1-7-8-24-14-24z" fill="#fff" stroke="#e2d6c4" stroke-width="1.5"/><rect x="12" y="23" width="16" height="12" rx="2" fill="#2e3b2c"/><circle cx="16" cy="19" r="1.2" fill="#4a3426"/><circle cx="24" cy="19" r="1.2" fill="#4a3426"/></svg>'],
    milk: ['牛奶', '<svg viewBox="0 0 40 40"><path d="M13 12l3-6h8l3 6v22a2 2 0 0 1-2 2H15a2 2 0 0 1-2-2z" fill="#f4f8fb" stroke="#9bb8cf" stroke-width="1.5"/><path d="M13 20h14v8H13z" fill="#7fb0dd"/><path d="M16 6h8" stroke="#9bb8cf" stroke-width="2"/></svg>'],
    coffee: ['咖啡', '<svg viewBox="0 0 40 40"><path d="M8 15h20v11a8 8 0 0 1-8 8h-4a8 8 0 0 1-8-8z" fill="#fff" stroke="#c9b49d" stroke-width="1.5"/><path d="M28 18h2a4 4 0 0 1 0 8h-2" fill="none" stroke="#c9b49d" stroke-width="2"/><ellipse cx="18" cy="16" rx="9" ry="2" fill="#7a4a2a"/><path d="M14 11c0-2 2-2 2-4M20 11c0-2 2-2 2-4" stroke="#c9b49d" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>'],
    cake: ['蛋糕', '<svg viewBox="0 0 40 40"><path d="M6 22h28v12H6z" fill="#f7d7a8"/><path d="M6 22h28v4c-3 2-4-1-7 1s-4-1-7 1-4-1-7 1-4-1-7 0z" fill="#fff"/><path d="M6 30h28" stroke="#f0a4b0" stroke-width="3"/><path d="M20 22V14" stroke="#9bb8cf" stroke-width="2.5"/><path d="M20 8c2 2 2 4 0 5-2-1-2-3 0-5z" fill="#f7a53a"/><circle cx="12" cy="20" r="2.2" fill="#e8553a"/><circle cx="28" cy="20" r="2.2" fill="#e8553a"/></svg>'],
    icecream: ['冰淇淋', '<svg viewBox="0 0 40 40"><path d="M13 20l7 17 7-17z" fill="#e6b170"/><path d="M15 23l8 8M18 21l6 6M25 23l-8 8" stroke="#c98f4a" stroke-width="1"/><circle cx="16" cy="16" r="6" fill="#f7b6c8"/><circle cx="24" cy="16" r="6" fill="#fff3c9"/><circle cx="20" cy="10" r="6" fill="#a6d8b8"/><circle cx="20" cy="4.5" r="1.8" fill="#e8553a"/></svg>'],
    fish: ['小鱼干', '<svg viewBox="0 0 40 40"><path d="M5 20c5-8 18-9 25 0-7 9-20 8-25 0z" fill="#d9a066"/><path d="M29 20l7-6v12z" fill="#c98f4a"/><circle cx="11" cy="18.5" r="1.6" fill="#4a3426"/><path d="M16 15v10M20 14v12M24 15v10" stroke="#b0773f" stroke-width="1.2"/></svg>'],
    ball: ['玩具球', '<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="14" fill="#f3c34a"/><path d="M6 20c8-5 20-5 28 0M20 6c-5 8-5 20 0 28" stroke="#e8553a" stroke-width="3" fill="none"/><ellipse cx="14" cy="13" rx="3" ry="2" fill="#fff" opacity=".5"/></svg>'],
    bath: ['泡泡浴', '<svg viewBox="0 0 40 40"><path d="M4 20h32v5a9 9 0 0 1-9 9H13a9 9 0 0 1-9-9z" fill="#7fb0dd"/><path d="M4 20h32" stroke="#5a8fc0" stroke-width="2"/><circle cx="12" cy="15" r="4" fill="#eaf4fc" stroke="#9bb8cf"/><circle cx="20" cy="12" r="5" fill="#eaf4fc" stroke="#9bb8cf"/><circle cx="28" cy="15" r="3.5" fill="#eaf4fc" stroke="#9bb8cf"/><path d="M10 34l-2 3M30 34l2 3" stroke="#5a8fc0" stroke-width="2"/></svg>']
  };
  const EFFECT_NAME = { hunger: '饱食', mood: '心情', energy: '精力', clean: '清洁' };
  const NEED_COLOR = { hunger: '#f0a04b', mood: '#f06f7e', energy: '#6aa7e0', clean: '#5dbfa6' };
  const FISH = '<svg class="fish-ic" viewBox="0 0 40 40"><path d="M5 20c5-8 18-9 25 0-7 9-20 8-25 0z" fill="#d9a066"/><path d="M29 20l7-6v12z" fill="#c98f4a"/><circle cx="11" cy="18.5" r="1.6" fill="#4a3426"/></svg>';

  let careOff = null;
  Hub.register({
    id: 'care', title: '照顾宠物', group: 'pet', order: 1, icon: ICON.care,
    mount(el, ctx) {
      const s = api.settings.get();
      el.innerHTML = `
        <h2 class="page-title">照顾宠物</h2>
        <div class="care-top">
          <div class="card care-pet">
            <div class="care-avatar"><img src="${api.petImage(s.pet)}" alt=""><div class="care-mood"></div></div>
            <div class="care-info">
              <div class="care-lv"><b class="lv"></b><div class="exp-bar"><div></div></div><span class="exp-txt"></span></div>
              <div class="care-needs"></div>
              <div class="care-actions">
                <button class="btn" data-a="play">🎾 陪它玩</button>
                <button class="btn" data-a="rest">💤 休息</button>
                <button class="btn primary" data-a="checkin">📅 每日签到</button>
              </div>
            </div>
          </div>
          <div class="card care-wallet">
            <div class="side-title">我的小鱼干</div>
            <div class="coins">${FISH}<b></b></div>
            <div class="set-sub">玩游戏获胜、完成番茄钟、签到都能获得小鱼干</div>
            <div class="side-title" style="margin-top:12px">最近动态</div>
            <ul class="care-log"></ul>
          </div>
        </div>
        <div class="care-bottom">
          <div class="card"><div class="side-title">背包 <span class="set-sub">点击使用</span></div><div class="inv-grid"></div></div>
          <div class="card"><div class="side-title">商店</div><div class="shop-grid"></div></div>
        </div>`;
      const q = sel => el.querySelector(sel);
      const effectText = eff => Object.entries(eff).map(([k, v]) => `${EFFECT_NAME[k]}${v > 0 ? '+' : ''}${v}`).join(' ');

      function render(c) {
        q('.lv').textContent = `Lv.${c.level}`;
        q('.exp-bar div').style.width = `${c.exp / c.need * 100}%`;
        q('.exp-txt').textContent = `${Math.floor(c.exp)}/${c.need}`;
        q('.coins b').textContent = c.coins;
        q('.care-needs').innerHTML = Object.keys(EFFECT_NAME).map(k => `
          <div class="need"><span>${EFFECT_NAME[k]}</span>
          <div class="need-bar"><div style="width:${c[k]}%;background:${c[k] < 25 ? '#e5484d' : NEED_COLOR[k]}"></div></div>
          <em>${Math.round(c[k])}</em></div>`).join('');
        const avg = (c.hunger + c.mood + c.energy + c.clean) / 4;
        q('.care-mood').textContent = avg > 75 ? '😄 超开心' : avg > 50 ? '🙂 还不错' : avg > 25 ? '😕 有点不舒服' : '😢 需要照顾';
        const checked = ctx.store.get('checkin') === new Date().toDateString();
        const cb = q('[data-a=checkin]');
        cb.disabled = checked;
        cb.textContent = checked ? '✅ 今日已签到' : '📅 每日签到';
        q('.care-log').innerHTML = c.log.slice(0, 6).map(l =>
          `<li><span>${new Date(l.t).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}</span>${esc(l.text)}</li>`).join('') || '<li class="set-sub">暂无</li>';

        const inv = q('.inv-grid');
        inv.innerHTML = '';
        const owned = Object.entries(c.inventory).filter(([, n]) => n > 0);
        if (!owned.length) inv.innerHTML = '<div class="set-sub">背包空空的，去商店买点东西吧~</div>';
        for (const [id, n] of owned) {
          const b = h(`<button class="item" title="${effectText(c.shop[id].effect)}">${ITEMS[id][1]}<span>${ITEMS[id][0]}</span><i>${n}</i></button>`);
          b.onclick = () => act('use', id);
          inv.appendChild(b);
        }
        const shop = q('.shop-grid');
        shop.innerHTML = '';
        for (const [id, it] of Object.entries(c.shop)) {
          const b = h(`<button class="item shop ${c.coins < it.price ? 'poor' : ''}">${ITEMS[id][1]}<span>${ITEMS[id][0]}</span><small>${effectText(it.effect)}</small><b>${FISH}${it.price}</b></button>`);
          b.onclick = () => act('buy', id);
          shop.appendChild(b);
        }
      }
      function act(a, item) {
        const r = api.care.action(a, item);
        if (!r.ok && r.msg) ctx.toast(r.msg);
        else if (r.ok && a === 'buy') ctx.toast(`买到了 ${ITEMS[item][0]}，已放进背包`);
        if (r.state) render(r.state);
      }
      el.querySelectorAll('[data-a=play],[data-a=rest]').forEach(b => b.onclick = () => act(b.dataset.a));
      q('[data-a=checkin]').onclick = () => {
        const today = new Date().toDateString();
        if (ctx.store.get('checkin') === today) return;
        const yesterday = new Date(Date.now() - 864e5).toDateString();
        const streak = ctx.store.get('checkinLast') === yesterday ? ctx.store.get('streak', 0) + 1 : 1;
        ctx.store.set('checkin', today);
        ctx.store.set('checkinLast', today);
        ctx.store.set('streak', streak);
        api.ach.set('streak', streak);
        const coins = 10 + Math.min(streak - 1, 6) * 2;
        api.care.reward(coins, `签到（连续 ${streak} 天）`);
        ctx.toast(`签到成功！连续 ${streak} 天，获得 ${coins} 小鱼干`);
        ctx.say(`签到成功！已经连续 ${streak} 天啦~`);
      };
      render(api.care.get());
      careOff = api.care.onChange(render);
    },
    unmount() { careOff && careOff(); careOff = null; }
  });

  // ============ 闹钟 & 倒计时 ============
  let alarmOff = null, alarmTimer = null;
  Hub.register({
    id: 'alarms', title: '闹钟 / 倒计时', group: 'tool', order: 2, icon: ICON.alarm,
    mount(el, ctx) {
      const DAYS = ['日', '一', '二', '三', '四', '五', '六'];
      el.innerHTML = `
        <h2 class="page-title">闹钟 / 倒计时</h2>
        <div class="al-wrap">
          <div class="card">
            <div class="side-title">闹钟</div>
            <form class="al-form">
              <input class="input" type="time" required value="08:00">
              <input class="input al-label" placeholder="备注（可选）" maxlength="40">
              <div class="al-days">${DAYS.map((d, i) => `<label><input type="checkbox" value="${i}"><span>${d}</span></label>`).join('')}</div>
              <button class="btn primary" type="submit">添加</button>
            </form>
            <div class="set-sub">不选星期 = 只响一次</div>
            <ul class="al-list"></ul>
          </div>
          <div class="card">
            <div class="side-title">倒计时</div>
            <div class="cd-presets">${[1, 3, 5, 10, 15, 30, 60].map(m => `<button class="btn" data-m="${m}">${m} 分钟</button>`).join('')}</div>
            <form class="cd-form">
              <input class="input cd-min" type="number" min="1" max="1440" value="20"> 分钟
              <input class="input cd-label" placeholder="提醒内容，如：泡面好了" maxlength="40">
              <button class="btn primary" type="submit">开始</button>
            </form>
            <ul class="cd-list"></ul>
          </div>
        </div>`;
      const q = sel => el.querySelector(sel);
      let state = api.alarms.get();
      const uid = () => Date.now() + Math.random();

      function render(st) {
        state = st;
        const al = q('.al-list');
        al.innerHTML = st.alarms.length ? '' : '<li class="todo-empty">还没有闹钟</li>';
        for (const a of [...st.alarms].sort((x, y) => x.time.localeCompare(y.time))) {
          const li = h(`<li class="al-item ${a.enabled ? '' : 'off'}">
            <b>${a.time}</b><div><div>${esc(a.label || '闹钟')}</div><div class="set-sub">${a.days.length ? (a.days.length === 7 ? '每天' : '每周' + a.days.map(d => DAYS[d]).join('、')) : '仅一次'}</div></div>
            <label class="switch"><input type="checkbox" ${a.enabled ? 'checked' : ''}><span></span></label>
            <button class="todo-del" title="删除"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></li>`);
          li.querySelector('input').onchange = e => { a.enabled = e.target.checked; a.lastFired = null; api.alarms.setAlarms(st.alarms); };
          li.querySelector('.todo-del').onclick = () => api.alarms.setAlarms(st.alarms.filter(x => x !== a));
          al.appendChild(li);
        }
        renderCountdowns();
      }
      function renderCountdowns() {
        const cl = q('.cd-list');
        const list = state.countdowns;
        cl.innerHTML = list.length ? '' : '<li class="todo-empty">没有进行中的倒计时</li>';
        for (const c of list) {
          const left = Math.max(0, c.endAt - Date.now());
          const s = Math.ceil(left / 1000);
          const li = h(`<li class="cd-item"><div class="cd-ring"><svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="15" class="ring-bg"/><circle cx="18" cy="18" r="15" class="ring-fg" stroke-dasharray="94.25" stroke-dashoffset="${94.25 * (1 - left / c.total)}" transform="rotate(-90 18 18)"/></svg></div>
            <div><b>${s >= 3600 ? Math.floor(s / 3600) + ':' : ''}${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}</b><div class="set-sub">${esc(c.label || '倒计时')}</div></div>
            <button class="todo-del" title="取消"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></li>`);
          li.querySelector('.todo-del').onclick = () => api.alarms.setCountdowns(state.countdowns.filter(x => x.id !== c.id));
          cl.appendChild(li);
        }
      }
      function addCountdown(min, label) {
        const total = min * 60 * 1000;
        api.alarms.setCountdowns([...state.countdowns, { id: uid(), label, endAt: Date.now() + total, total }]);
        ctx.toast(`已开始 ${min} 分钟倒计时`);
      }
      q('.al-form').onsubmit = e => {
        e.preventDefault();
        const time = q('.al-form input[type=time]').value;
        if (!time) return;
        const days = [...el.querySelectorAll('.al-days input:checked')].map(i => Number(i.value));
        api.alarms.setAlarms([...state.alarms, { id: uid(), time, days, label: q('.al-label').value.trim(), enabled: true, lastFired: null }]);
        q('.al-label').value = '';
        ctx.toast(`闹钟已设置：${time}`);
      };
      q('.cd-form').onsubmit = e => {
        e.preventDefault();
        const m = Math.min(1440, Math.max(1, Math.round(Number(q('.cd-min').value)) || 1));
        addCountdown(m, q('.cd-label').value.trim());
        q('.cd-label').value = '';
      };
      el.querySelectorAll('.cd-presets .btn').forEach(b => b.onclick = () => addCountdown(Number(b.dataset.m), ''));
      render(state);
      alarmOff = api.alarms.onChange(render);
      alarmTimer = setInterval(renderCountdowns, 1000);
    },
    unmount() { alarmOff && alarmOff(); alarmOff = null; clearInterval(alarmTimer); }
  });

  // ============ 白噪音 (generated with WebAudio, no audio files) ============
  let audio = null; // survives page switches so sound keeps playing
  function noiseBuffer(ctx, type) {
    const len = ctx.sampleRate * 4;
    const buf = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch);
      let last = 0, b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
      for (let i = 0; i < len; i++) {
        const w = Math.random() * 2 - 1;
        if (type === 'brown') { last = (last + 0.02 * w) / 1.02; d[i] = last * 3.5; }
        else if (type === 'pink') {
          b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.969 * b2 + w * 0.153852;
          b3 = 0.8665 * b3 + w * 0.3104856; b4 = 0.55 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.016898;
          d[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11; b6 = w * 0.115926;
        } else d[i] = w * 0.5;
      }
    }
    return buf;
  }
  const SOUNDS = {
    rain: { name: '雨声', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'pink'); src.loop = true;
      const hp = ac.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 400;
      const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 6000;
      src.connect(hp).connect(lp).connect(out); src.start();
      // random droplets
      const drops = setInterval(() => {
        const o = ac.createOscillator(), g = ac.createGain();
        o.frequency.value = 1800 + Math.random() * 2500;
        g.gain.setValueAtTime(0.03 * Math.random(), ac.currentTime);
        g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.05);
        o.connect(g).connect(out); o.start(); o.stop(ac.currentTime + 0.06);
      }, 60);
      return () => { src.stop(); clearInterval(drops); };
    } },
    ocean: { name: '海浪', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'brown'); src.loop = true;
      const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900;
      const g = ac.createGain(); g.gain.value = 0.5;
      const lfo = ac.createOscillator(); lfo.frequency.value = 0.09;
      const lg = ac.createGain(); lg.gain.value = 0.45;
      lfo.connect(lg).connect(g.gain);
      src.connect(lp).connect(g).connect(out); src.start(); lfo.start();
      return () => { src.stop(); lfo.stop(); };
    } },
    fire: { name: '篝火', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'brown'); src.loop = true;
      const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 500;
      src.connect(lp).connect(out); src.start();
      const crackle = setInterval(() => {
        if (Math.random() < 0.5) return;
        const b = ac.createBufferSource(); b.buffer = noiseBuffer.cache || (noiseBuffer.cache = noiseBuffer(ac, 'white'));
        const g = ac.createGain(), bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 2000 + Math.random() * 3000;
        g.gain.setValueAtTime(0.6 * Math.random(), ac.currentTime);
        g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.03);
        b.connect(bp).connect(g).connect(out); b.start(0, Math.random() * 3, 0.04);
      }, 45);
      return () => { src.stop(); clearInterval(crackle); };
    } },
    wind: { name: '风声', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'pink'); src.loop = true;
      const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 1.2; bp.frequency.value = 500;
      const lfo = ac.createOscillator(); lfo.frequency.value = 0.13;
      const lg = ac.createGain(); lg.gain.value = 300;
      lfo.connect(lg).connect(bp.frequency);
      src.connect(bp).connect(out); src.start(); lfo.start();
      return () => { src.stop(); lfo.stop(); };
    } },
    brown: { name: '褐噪音', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'brown'); src.loop = true;
      src.connect(out); src.start();
      return () => src.stop();
    } },
    white: { name: '白噪音', build(ac, out) {
      const src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, 'white'); src.loop = true;
      const g = ac.createGain(); g.gain.value = 0.35;
      src.connect(g).connect(out); src.start();
      return () => src.stop();
    } }
  };
  const SOUND_ICON = {
    rain: '<svg viewBox="0 0 48 48"><path d="M14 26a8 8 0 0 1 1-16 11 11 0 0 1 20 3 7 7 0 0 1-1 13z" fill="#cfe0f0"/><path d="M16 32l-2 5M24 32l-2 5M32 32l-2 5M20 39l-2 5M28 39l-2 5" stroke="#6aa7e0" stroke-width="2.5" stroke-linecap="round"/></svg>',
    ocean: '<svg viewBox="0 0 48 48"><path d="M4 26c5-6 10-6 14 0s10 6 14 0 10-6 14 0v14H4z" fill="#6aa7e0"/><path d="M4 34c5-5 10-5 14 0s10 5 14 0 10-5 14 0" stroke="#fff" stroke-width="2.5" fill="none"/><circle cx="36" cy="12" r="5" fill="#f7c948"/></svg>',
    fire: '<svg viewBox="0 0 48 48"><path d="M24 6c2 8 12 12 12 22a12 12 0 0 1-24 0c0-6 4-8 5-13 3 3 3 6 3 8 3-4 4-10 4-17z" fill="#f0873a"/><path d="M24 24c1 4 6 6 6 10a6 6 0 0 1-12 0c0-3 3-5 6-10z" fill="#f7c948"/><path d="M10 42l28-4M10 38l28 4" stroke="#8b5a36" stroke-width="3" stroke-linecap="round"/></svg>',
    wind: '<svg viewBox="0 0 48 48" fill="none" stroke="#7fb8a8" stroke-width="3" stroke-linecap="round"><path d="M6 18h24a5 5 0 1 0-5-5M6 26h32a5 5 0 1 1-5 5M6 34h16"/></svg>',
    brown: '<svg viewBox="0 0 48 48"><path d="M4 24c3-8 5 8 8 0s5-12 8 0 5 10 8 0 5-8 8 0 5 6 8 0" stroke="#a0724a" stroke-width="3" fill="none" stroke-linecap="round"/></svg>',
    white: '<svg viewBox="0 0 48 48"><path d="M4 24l3-8 3 14 3-18 3 20 3-16 3 12 3-14 3 18 3-12 3 10 3-8 3 6 3-4" stroke="#9b8472" stroke-width="2" fill="none" stroke-linejoin="round"/></svg>'
  };
  function ensureAudio() {
    if (audio) return audio;
    const ac = new AudioContext();
    const master = ac.createGain();
    master.connect(ac.destination);
    audio = { ac, master, playing: {}, sleepAt: 0, sleepTimer: null };
    return audio;
  }
  function toggleSound(id, vol) {
    const a = ensureAudio();
    if (a.playing[id]) { a.playing[id].stop(); delete a.playing[id]; return false; }
    const g = a.ac.createGain(); g.gain.value = vol; g.connect(a.master);
    const stop = SOUNDS[id].build(a.ac, g);
    a.playing[id] = { gain: g, stop: () => { stop(); g.disconnect(); } };
    if (a.ac.state === 'suspended') a.ac.resume();
    return true;
  }
  function stopAll() {
    if (!audio) return;
    for (const id of Object.keys(audio.playing)) { audio.playing[id].stop(); delete audio.playing[id]; }
    clearTimeout(audio.sleepTimer); audio.sleepAt = 0;
  }

  let noiseTimer = null;
  Hub.register({
    id: 'noise', title: '白噪音', group: 'tool', order: 3, icon: ICON.noise,
    mount(el, ctx) {
      const vols = ctx.store.get('vols', {});
      el.innerHTML = `
        <h2 class="page-title">白噪音 <span class="set-sub">多种声音可叠加，切换页面后继续播放</span></h2>
        <div class="noise-grid"></div>
        <div class="card noise-bar">
          <span>总音量</span><input type="range" min="0" max="1" step="0.01" class="master">
          <span>定时关闭</span>
          <select class="input sleep"><option value="0">不关闭</option><option value="15">15 分钟</option><option value="30">30 分钟</option><option value="60">60 分钟</option><option value="90">90 分钟</option></select>
          <span class="sleep-left set-sub"></span>
          <button class="btn stop">全部停止</button>
        </div>`;
      const grid = el.querySelector('.noise-grid');
      const render = () => {
        grid.innerHTML = '';
        for (const [id, s] of Object.entries(SOUNDS)) {
          const on = !!(audio && audio.playing[id]);
          const card = h(`<div class="noise-card ${on ? 'on' : ''}"><button class="noise-btn">${SOUND_ICON[id]}<span>${s.name}</span></button>
            <input type="range" min="0" max="1" step="0.01" value="${vols[id] ?? 0.6}"></div>`);
          card.querySelector('.noise-btn').onclick = () => { toggleSound(id, vols[id] ?? 0.6); render(); };
          card.querySelector('input').oninput = e => {
            vols[id] = Number(e.target.value); ctx.store.set('vols', vols);
            if (audio && audio.playing[id]) audio.playing[id].gain.gain.value = vols[id];
          };
          grid.appendChild(card);
        }
      };
      const master = el.querySelector('.master');
      master.value = ctx.store.get('master', 0.8);
      master.oninput = () => { ensureAudio().master.gain.value = Number(master.value); ctx.store.set('master', Number(master.value)); };
      ensureAudio().master.gain.value = Number(master.value);
      el.querySelector('.sleep').onchange = e => {
        const m = Number(e.target.value);
        clearTimeout(audio.sleepTimer);
        audio.sleepAt = m ? Date.now() + m * 60e3 : 0;
        if (m) audio.sleepTimer = setTimeout(() => { stopAll(); render(); ctx.say('白噪音已定时关闭，晚安~'); }, m * 60e3);
      };
      el.querySelector('.stop').onclick = () => { stopAll(); render(); };
      const tick = () => {
        const s = audio && audio.sleepAt ? Math.max(0, Math.ceil((audio.sleepAt - Date.now()) / 1000)) : 0;
        el.querySelector('.sleep-left').textContent = s ? `剩余 ${pad(Math.floor(s / 60))}:${pad(s % 60)}` : '';
      };
      noiseTimer = setInterval(tick, 1000);
      render();
    },
    unmount() { clearInterval(noiseTimer); }
  });

  // ============ 帮我决定（转盘） ============
  let wheelRaf = 0;
  Hub.register({
    id: 'wheel', title: '帮我决定', group: 'tool', order: 4, icon: ICON.wheel,
    mount(el, ctx) {
      const PRESETS = {
        '今天吃什么': ['火锅', '麻辣烫', '黄焖鸡', '拉面', '寿司', '汉堡', '饺子', '沙拉', '烤肉', '螺蛳粉'],
        '做什么': ['看书', '运动', '打游戏', '看电影', '学习', '睡觉', '散步', '打扫房间'],
        '是否': ['是', '否'],
        '掷骰子': ['1', '2', '3', '4', '5', '6']
      };
      let items = ctx.store.get('items', PRESETS['今天吃什么']);
      let angle = 0, spinning = false;
      el.innerHTML = `
        <h2 class="page-title">帮我决定</h2>
        <div class="wheel-wrap">
          <div class="wheel-box">
            <canvas width="760" height="760"></canvas>
            <svg class="wheel-pointer" viewBox="0 0 40 50"><path d="M20 48L4 12a16 16 0 1 1 32 0z" fill="#e8793a" stroke="#fff" stroke-width="3"/><circle cx="20" cy="16" r="6" fill="#fff"/></svg>
            <button class="wheel-go">GO</button>
          </div>
          <div class="card wheel-side">
            <div class="side-title">预设</div>
            <div class="wheel-presets">${Object.keys(PRESETS).map(k => `<button class="btn" data-p="${k}">${k}</button>`).join('')}</div>
            <div class="side-title" style="margin-top:12px">选项（每行一个）</div>
            <textarea class="input wheel-items" rows="10"></textarea>
            <div class="wheel-result"></div>
          </div>
        </div>`;
      const cv = el.querySelector('canvas'), g = cv.getContext('2d');
      const ta = el.querySelector('.wheel-items');
      const COLORS = ['#f7b267', '#f79d65', '#f4845f', '#f27059', '#f25c54', '#a3c585', '#7fb8a8', '#6aa7e0', '#b39ddb', '#f0a4b0'];
      ta.value = items.join('\n');
      function draw() {
        const W = cv.width, R = W / 2 - 16, n = items.length || 1;
        g.clearRect(0, 0, W, W);
        g.save(); g.translate(W / 2, W / 2);
        g.beginPath(); g.arc(0, 0, R + 10, 0, Math.PI * 2); g.fillStyle = '#6b3f24'; g.fill();
        for (let i = 0; i < n; i++) {
          const a0 = angle + i * 2 * Math.PI / n, a1 = a0 + 2 * Math.PI / n;
          g.beginPath(); g.moveTo(0, 0); g.arc(0, 0, R, a0, a1); g.closePath();
          g.fillStyle = COLORS[i % COLORS.length]; g.fill();
          g.strokeStyle = 'rgba(255,255,255,.7)'; g.lineWidth = 3; g.stroke();
          g.save(); g.rotate((a0 + a1) / 2);
          g.fillStyle = '#fff'; g.font = `bold ${n > 12 ? 22 : 30}px "Microsoft YaHei UI"`; g.textAlign = 'right'; g.textBaseline = 'middle';
          g.shadowColor = 'rgba(0,0,0,.25)'; g.shadowBlur = 4;
          const t = items[i] || '';
          g.fillText(t.length > 8 ? t.slice(0, 7) + '…' : t, R - 24, 0);
          g.restore();
        }
        for (let i = 0; i < 24; i++) {
          const a = i / 24 * Math.PI * 2;
          g.beginPath(); g.arc(Math.cos(a) * (R + 5), Math.sin(a) * (R + 5), 4, 0, Math.PI * 2);
          g.fillStyle = i % 2 ? '#f7c948' : '#fff'; g.fill();
        }
        g.restore();
      }
      ta.oninput = () => {
        items = ta.value.split('\n').map(s => s.trim()).filter(Boolean).slice(0, 24);
        ctx.store.set('items', items); draw();
      };
      el.querySelectorAll('[data-p]').forEach(b => b.onclick = () => {
        items = PRESETS[b.dataset.p].slice(); ta.value = items.join('\n'); ctx.store.set('items', items); draw();
      });
      el.querySelector('.wheel-go').onclick = () => {
        if (spinning || items.length < 2) { if (items.length < 2) ctx.toast('至少需要两个选项'); return; }
        spinning = true;
        el.querySelector('.wheel-result').textContent = '';
        const start = angle, total = Math.PI * 2 * (5 + Math.random() * 3) + Math.random() * Math.PI * 2;
        const dur = 4200, t0 = performance.now();
        const step = now => {
          const t = Math.min(1, (now - t0) / dur);
          angle = start + total * (1 - Math.pow(1 - t, 4));
          draw();
          if (t < 1) { wheelRaf = requestAnimationFrame(step); return; }
          spinning = false;
          // the pointer is at the top (-90deg)
          const n = items.length;
          const rel = ((-Math.PI / 2 - angle) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
          const pick = items[Math.floor(rel / (2 * Math.PI / n))];
          el.querySelector('.wheel-result').innerHTML = `结果：<b>${esc(pick)}</b>`;
          ctx.say(`就决定是「${pick}」啦！`);
        };
        wheelRaf = requestAnimationFrame(step);
      };
      draw();
    },
    unmount() { cancelAnimationFrame(wheelRaf); }
  });

  // ============ 系统监视 ============
  let sysTimer = null;
  Hub.register({
    id: 'sysmon', title: '系统监视', group: 'tool', order: 5, icon: ICON.sys,
    mount(el) {
      const hist = { cpu: [], mem: [] };
      const N = 60;
      el.innerHTML = `
        <h2 class="page-title">系统监视</h2>
        <div class="sys-grid">
          <div class="card sys-gauge" data-k="cpu"><div class="side-title">CPU</div><svg viewBox="0 0 120 70"><path d="M10 64a50 50 0 0 1 100 0" class="g-bg"/><path d="M10 64a50 50 0 0 1 100 0" class="g-fg" pathLength="100"/><text x="60" y="58" class="g-val">0%</text></svg><div class="set-sub sys-sub"></div></div>
          <div class="card sys-gauge" data-k="mem"><div class="side-title">内存</div><svg viewBox="0 0 120 70"><path d="M10 64a50 50 0 0 1 100 0" class="g-bg"/><path d="M10 64a50 50 0 0 1 100 0" class="g-fg" pathLength="100"/><text x="60" y="58" class="g-val">0%</text></svg><div class="set-sub sys-sub"></div></div>
          <div class="card sys-info"><div class="side-title">系统信息</div><dl></dl></div>
        </div>
        <div class="card"><div class="side-title">最近 60 秒 <span class="legend"><i style="background:#e8793a"></i>CPU <i style="background:#6aa7e0"></i>内存</span></div><svg class="sys-chart" viewBox="0 0 600 160" preserveAspectRatio="none"></svg></div>`;
      const fmtBytes = b => b > 1 << 30 ? (b / (1 << 30)).toFixed(1) + ' GB' : (b / (1 << 20)).toFixed(0) + ' MB';
      const fmtDur = s => { s = Math.floor(s); const d = Math.floor(s / 86400); return `${d ? d + ' 天 ' : ''}${Math.floor(s % 86400 / 3600)} 小时 ${Math.floor(s % 3600 / 60)} 分`; };
      const gauge = (k, v, sub) => {
        const c = el.querySelector(`[data-k=${k}]`);
        const fg = c.querySelector('.g-fg');
        fg.style.strokeDashoffset = 100 - v * 100;
        fg.style.stroke = v > 0.85 ? '#e5484d' : v > 0.6 ? '#f0a04b' : k === 'cpu' ? '#e8793a' : '#6aa7e0';
        c.querySelector('.g-val').textContent = `${Math.round(v * 100)}%`;
        c.querySelector('.sys-sub').textContent = sub;
      };
      const line = (arr, color) => {
        if (arr.length < 2) return '';
        const pts = arr.map((v, i) => `${(i + N - arr.length) / (N - 1) * 600},${160 - v * 150 - 5}`).join(' ');
        return `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>`;
      };
      const update = () => {
        const s = api.sys();
        const mem = 1 - s.memFree / s.memTotal;
        hist.cpu.push(s.cpu); hist.mem.push(mem);
        if (hist.cpu.length > N) { hist.cpu.shift(); hist.mem.shift(); }
        gauge('cpu', s.cpu, `${s.cores} 核`);
        gauge('mem', mem, `${fmtBytes(s.memTotal - s.memFree)} / ${fmtBytes(s.memTotal)}`);
        el.querySelector('.sys-info dl').innerHTML = `
          <dt>主机名</dt><dd>${esc(s.host)}</dd><dt>系统</dt><dd>${esc(s.platform)}</dd>
          <dt>处理器</dt><dd title="${esc(s.cpuModel)}">${esc(s.cpuModel)}</dd>
          <dt>开机时长</dt><dd>${fmtDur(s.uptime)}</dd><dt>桌宠已陪伴</dt><dd>${fmtDur(s.appUptime)}</dd>`;
        const grid = [0.25, 0.5, 0.75].map(v => `<line x1="0" x2="600" y1="${160 - v * 150 - 5}" y2="${160 - v * 150 - 5}" stroke="#f1e3d1" vector-effect="non-scaling-stroke"/>`).join('');
        el.querySelector('.sys-chart').innerHTML = grid + line(hist.mem, '#6aa7e0') + line(hist.cpu, '#e8793a');
      };
      update();
      sysTimer = setInterval(update, 1000);
    },
    unmount() { clearInterval(sysTimer); }
  });
})();
