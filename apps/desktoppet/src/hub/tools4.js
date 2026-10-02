// Tool pages: 倒数日 / 单位换算 / 密码生成器. See MODULES.md for the module contract.
(function () {
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const pad = n => String(n).padStart(2, '0');
  const dayKey = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const today = () => dayKey(new Date());
  const parseDay = k => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
  const WEEK = ['日', '一', '二', '三', '四', '五', '六'];
  const isTyping = e => { const t = e.target && e.target.tagName; return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || (e.target && e.target.isContentEditable); };

  const ICON = {
    days: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3.5" y="4.5" width="17" height="16" rx="2.5"/><path d="M3.5 9.5h17M8 2.5v4M16 2.5v4" stroke-linecap="round"/><path d="M10 13.2l2-1.2v6" stroke-linecap="round"/></svg>',
    units: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/></svg>',
    passgen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="4" y="10.5" width="16" height="10.5" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" stroke-linecap="round"/><path d="M8.5 15.8h.01M12 15.8h.01M15.5 15.8h.01" stroke-width="2.8" stroke-linecap="round"/></svg>'
  };

  // =====================================================================
  // 倒数日
  // =====================================================================
  const DD_COLORS = ['#e8793a', '#e8638a', '#9b7ae0', '#5b9bd5', '#4db6ac', '#5da35a', '#e0a526', '#c2894e'];
  const DAY_MS = 864e5;
  const diffDays = (a, b) => Math.round((b - a) / DAY_MS);   // calendar days from a to b (DST-safe via round)
  const isLeap = y => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  // month/day of the original date in year y (Feb 29 -> Feb 28 in non-leap years)
  const inYear = (orig, y) => (orig.getMonth() === 1 && orig.getDate() === 29 && !isLeap(y)) ? new Date(y, 1, 28) : new Date(y, orig.getMonth(), orig.getDate());

  // returns { left, since, target, nth, isToday, sortKey }
  function evInfo(ev, now) {
    const t0 = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const orig = parseDay(ev.date);
    const r = { left: null, since: null, target: orig, nth: 0, isToday: false, past: false };
    if (ev.repeat) {
      let next = inYear(orig, t0.getFullYear());
      if (next < t0) next = inYear(orig, t0.getFullYear() + 1);
      if (next < orig) next = orig;                         // original date still in the future
      r.target = next;
      r.left = diffDays(t0, next);
      r.nth = next.getFullYear() - orig.getFullYear();
      r.isToday = r.left === 0;
      if (ev.type === 'since') r.since = Math.max(0, diffDays(orig, t0));
    } else if (ev.type === 'since') {
      r.since = diffDays(orig, t0);
      r.isToday = r.since === 0;
      if (r.since < 0) { r.left = -r.since; r.since = null; }
    } else {
      r.left = diffDays(t0, orig);
      r.isToday = r.left === 0;
      if (r.left < 0) { r.past = true; r.since = -r.left; r.left = null; }
    }
    // upcoming first (ascending), then "since" counters, then past countdowns
    r.sortKey = r.left !== null ? r.left : r.past ? 2e6 + r.since : 1e6 + (1e5 - Math.min(r.since, 99999));
    return r;
  }
  const fmtDate = d => `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 周${WEEK[d.getDay()]}`;

  let ddCleanup = null;
  Hub.register({
    id: 'days', title: '倒数日', group: 'tool', order: 9, icon: ICON.days,
    mount(el, ctx) {
      let events = ctx.store.get('events', null);
      if (!Array.isArray(events)) {
        const y = new Date().getFullYear();
        events = [
          { id: 1, name: '元旦', date: `${y + 1}-01-01`, type: 'count', repeat: true, color: DD_COLORS[0], pinned: true },
          { id: 2, name: '认识桌宠', date: today(), type: 'since', repeat: true, color: DD_COLORS[1], pinned: false }
        ];
      }
      const save = () => ctx.store.set('events', events);
      let editing = null, form = null;

      el.innerHTML = `
        <div class="dd-root">
          <h2 class="page-title">倒数日 <span class="set-sub dd-today"></span> <button class="btn primary dd-new">+ 新事件</button></h2>
          <div class="card dd-editor hidden">
            <div class="side-title dd-ed-title">新事件</div>
            <div class="dd-ed-grid">
              <label class="set-sub">名称</label><input class="input dd-name" maxlength="24" placeholder="如：妈妈生日、考试、恋爱纪念日">
              <label class="set-sub">日期</label><input class="input dd-date" type="date">
              <label class="set-sub">类型</label>
              <div class="dd-seg dd-type"><button type="button" data-v="count">倒数日</button><button type="button" data-v="since">纪念日（已经多少天）</button></div>
              <label class="set-sub">每年重复</label>
              <div class="dd-row"><label class="switch"><input type="checkbox" class="dd-repeat"><span></span></label><span class="set-sub">生日、周年纪念等每年都会到来的日子（按公历计算）</span></div>
              <label class="set-sub">置顶</label>
              <div class="dd-row"><label class="switch"><input type="checkbox" class="dd-pin"><span></span></label><span class="set-sub">在顶部大卡片中显示</span></div>
              <label class="set-sub">颜色</label><div class="dd-colors"></div>
            </div>
            <div class="dd-ed-btns"><button class="btn dd-del">删除</button><span></span><button class="btn dd-cancel">取消</button><button class="btn primary dd-save">保存</button></div>
          </div>
          <div class="dd-hero"></div>
          <div class="dd-list"></div>
        </div>`;
      const q = s => el.querySelector(s);

      function openEditor(ev) {
        editing = ev || 'new';
        form = ev ? { ...ev } : { name: '', date: today(), type: 'count', repeat: false, color: DD_COLORS[events.length % DD_COLORS.length], pinned: !events.length };
        q('.dd-editor').classList.remove('hidden');
        q('.dd-ed-title').textContent = ev ? '编辑事件' : '新事件';
        q('.dd-del').style.display = ev ? '' : 'none';
        q('.dd-name').value = form.name;
        q('.dd-date').value = form.date;
        q('.dd-repeat').checked = !!form.repeat;
        q('.dd-pin').checked = !!form.pinned;
        renderEditor();
        el.closest('#content, .page') ? q('.dd-editor').scrollIntoView({ block: 'nearest' }) : 0;
        q('.dd-name').focus();
      }
      function closeEditor() { editing = null; q('.dd-editor').classList.add('hidden'); }
      function renderEditor() {
        el.querySelectorAll('.dd-type button').forEach(b => b.classList.toggle('on', b.dataset.v === form.type));
        q('.dd-colors').innerHTML = DD_COLORS.map(c => `<button type="button" class="dd-sw ${c === form.color ? 'on' : ''}" data-c="${c}" style="background:${c}"></button>`).join('');
        el.querySelectorAll('.dd-sw').forEach(b => b.onclick = () => { form.color = b.dataset.c; renderEditor(); });
      }
      el.querySelectorAll('.dd-type button').forEach(b => b.onclick = () => { form.type = b.dataset.v; renderEditor(); });
      q('.dd-new').onclick = () => openEditor(null);
      q('.dd-cancel').onclick = closeEditor;
      q('.dd-name').onkeydown = e => { if (e.key === 'Enter') q('.dd-save').click(); if (e.key === 'Escape') closeEditor(); };
      q('.dd-save').onclick = () => {
        const name = q('.dd-name').value.trim(), date = q('.dd-date').value;
        if (!name) { ctx.toast('请输入事件名称'); q('.dd-name').focus(); return; }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) { ctx.toast('请选择有效的日期'); return; }
        const data = { name, date, type: form.type, repeat: q('.dd-repeat').checked, color: form.color, pinned: q('.dd-pin').checked };
        if (data.pinned) events.forEach(x => { x.pinned = false; });
        if (editing === 'new') events.push({ id: Date.now(), ...data });
        else Object.assign(editing, data);
        save(); closeEditor(); render();
        announce(true);
      };
      q('.dd-del').onclick = () => {
        if (editing === 'new' || !confirm(`确定删除「${editing.name}」吗？`)) return;
        events = events.filter(x => x !== editing);
        save(); closeEditor(); render();
      };

      function bigText(ev, r) {
        // returns [label, number, unit]
        if (r.isToday) return [ev.type === 'since' && r.nth ? `${r.nth} 周年` : '就是今天', '今天', ''];
        if (ev.type === 'since') {
          if (r.since !== null) return ['已经', r.since, '天'];
          return ['还有', r.left, '天'];
        }
        if (r.past) return ['已过去', r.since, '天'];
        return ['还有', r.left, '天'];
      }
      function subText(ev, r) {
        const parts = [];
        if (ev.repeat) {
          const nth = r.nth > 0 ? (ev.type === 'since' ? `${r.nth} 周年` : `第 ${r.nth} 次`) : '';
          parts.push(`${r.isToday ? '今天' : `下次 ${fmtDate(r.target)}`}${nth ? ' · ' + nth : ''}`);
          if (ev.type === 'since' && !r.isToday) parts.push(`距周年还有 ${r.left} 天`);
          parts.push(`起始 ${ev.date}`);
        } else parts.push(fmtDate(r.target));
        return parts.join(' · ');
      }

      function render() {
        const now = new Date();
        q('.dd-today').textContent = `今天 ${fmtDate(now)}`;
        const rows = events.map(ev => ({ ev, r: evInfo(ev, now) })).sort((a, b) => a.r.sortKey - b.r.sortKey || a.ev.id - b.ev.id);
        const hero = rows.find(x => x.ev.pinned) || rows.find(x => x.r.left !== null) || rows[0];
        const heroBox = q('.dd-hero');
        heroBox.innerHTML = '';
        if (hero) {
          const [lbl, num, unit] = bigText(hero.ev, hero.r);
          const card = h(`<div class="dd-big${hero.r.isToday ? ' today' : ''}" style="--c:${hero.ev.color}">
            <div class="dd-big-l"><div class="dd-big-name"></div><div class="dd-big-sub">${esc(subText(hero.ev, hero.r))}</div>
              <div class="dd-tags">${hero.ev.pinned ? '<span>📌 置顶</span>' : ''}<span>${hero.ev.type === 'since' ? '纪念日' : '倒数日'}</span>${hero.ev.repeat ? '<span>每年</span>' : ''}</div></div>
            <div class="dd-big-r"><span class="dd-big-lbl">${esc(lbl)}</span><b>${num}</b><span class="dd-big-unit">${unit}</span></div>
          </div>`);
          card.querySelector('.dd-big-name').textContent = hero.ev.name;
          card.onclick = () => openEditor(hero.ev);
          heroBox.appendChild(card);
        }
        const list = q('.dd-list');
        list.innerHTML = rows.length ? '' : '<div class="card dd-empty">还没有事件，点击右上角「新事件」添加生日、纪念日或考试倒计时吧~</div>';
        for (const { ev, r } of rows) {
          const [lbl, num, unit] = bigText(ev, r);
          const card = h(`<div class="dd-card${r.isToday ? ' today' : ''}${r.past ? ' past' : ''}" style="--c:${ev.color}">
            <div class="dd-card-t"><div class="dd-card-name"></div><div class="dd-card-sub">${esc(subText(ev, r))}</div></div>
            <div class="dd-card-n"><span>${esc(lbl)}</span><b>${num}</b><em>${unit}</em></div>
            <div class="dd-card-ops">
              <button class="dd-op dd-op-pin${ev.pinned ? ' on' : ''}" title="${ev.pinned ? '取消置顶' : '置顶'}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M9 3h6l-1 6 4 4H6l4-4zM12 13v8" stroke-linecap="round"/></svg></button>
              <button class="dd-op dd-op-edit" title="编辑"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg></button>
              <button class="dd-op dd-op-del" title="删除"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
            </div>
          </div>`);
          card.querySelector('.dd-card-name').textContent = ev.name;
          card.querySelector('.dd-op-edit').onclick = () => openEditor(ev);
          card.querySelector('.dd-op-pin').onclick = () => { const on = !ev.pinned; events.forEach(x => { x.pinned = false; }); ev.pinned = on; save(); render(); };
          card.querySelector('.dd-op-del').onclick = () => {
            if (!confirm(`确定删除「${ev.name}」吗？`)) return;
            events = events.filter(x => x !== ev);
            if (editing === ev) closeEditor();
            save(); render();
          };
          list.appendChild(card);
        }
      }

      // speak once per event per day
      function announce(quiet) {
        const t = today(), now = new Date();
        let said = ctx.store.get('said', {});
        if (said.date !== t) said = { date: t, ids: [] };
        const due = events.filter(ev => evInfo(ev, now).isToday && !said.ids.includes(ev.id));
        if (!due.length) return;
        said.ids.push(...due.map(ev => ev.id));
        ctx.store.set('said', said);
        const names = due.map(ev => `「${ev.name}」`).join('、');
        ctx.say(`今天是${names}！`);
        if (!quiet) ctx.toast(`今天是${names}`);
      }

      let lastDay = today();
      const timer = setInterval(() => {
        const t = today();
        if (t === lastDay) return;
        lastDay = t;
        render();
        announce(false);
      }, 60 * 1000);
      ddCleanup = () => clearInterval(timer);

      render();
      announce(false);
      save();
    },
    unmount() { if (ddCleanup) ddCleanup(); ddCleanup = null; }
  });

  // =====================================================================
  // 单位换算
  // =====================================================================
  // linear units: factor to the base unit. temperature handled separately.
  const UNITS = {
    length: { name: '长度', base: 'm', units: [
      ['km', '千米', 1000], ['m', '米', 1], ['dm', '分米', 0.1], ['cm', '厘米', 0.01], ['mm', '毫米', 1e-3], ['um', '微米', 1e-6], ['nm', '纳米', 1e-9],
      ['li', '里', 500], ['zhang', '丈', 10 / 3], ['chi', '尺', 1 / 3], ['cun', '寸', 1 / 30],
      ['mi', '英里', 1609.344], ['yd', '码', 0.9144], ['ft', '英尺', 0.3048], ['in', '英寸', 0.0254], ['nmi', '海里', 1852], ['ly', '光年', 9460730472580800]
    ] },
    mass: { name: '重量', base: 'kg', units: [
      ['t', '吨', 1000], ['kg', '千克', 1], ['g', '克', 1e-3], ['mg', '毫克', 1e-6], ['ug', '微克', 1e-9],
      ['jin', '斤', 0.5], ['liang', '两', 0.05], ['lb', '磅', 0.45359237], ['oz', '盎司', 0.028349523125], ['ct', '克拉', 2e-4], ['st', '英石', 6.35029318]
    ] },
    temp: { name: '温度', base: 'C', units: [['C', '摄氏度 °C'], ['F', '华氏度 °F'], ['K', '开尔文 K'], ['R', '兰氏度 °R']] },
    area: { name: '面积', base: 'm2', units: [
      ['km2', '平方千米', 1e6], ['ha', '公顷', 1e4], ['mu', '亩', 10000 / 15], ['m2', '平方米', 1], ['dm2', '平方分米', 0.01], ['cm2', '平方厘米', 1e-4], ['mm2', '平方毫米', 1e-6],
      ['mi2', '平方英里', 2589988.110336], ['acre', '英亩', 4046.8564224], ['yd2', '平方码', 0.83612736], ['ft2', '平方英尺', 0.09290304], ['in2', '平方英寸', 6.4516e-4]
    ] },
    volume: { name: '体积', base: 'L', units: [
      ['m3', '立方米', 1000], ['L', '升', 1], ['dL', '分升', 0.1], ['mL', '毫升', 1e-3], ['cm3', '立方厘米', 1e-3], ['mm3', '立方毫米', 1e-6],
      ['galus', '美制加仑', 3.785411784], ['galuk', '英制加仑', 4.54609], ['qt', '美制夸脱', 0.946352946], ['pt', '美制品脱', 0.473176473],
      ['cup', '美制杯', 0.2365882365], ['floz', '美制液量盎司', 0.0295735295625], ['ft3', '立方英尺', 28.316846592], ['in3', '立方英寸', 0.016387064]
    ] },
    speed: { name: '速度', base: 'mps', units: [
      ['mps', '米/秒', 1], ['kmh', '千米/时', 1 / 3.6], ['mph', '英里/时', 0.44704], ['kn', '节', 1852 / 3600], ['fps', '英尺/秒', 0.3048],
      ['mach', '马赫（15°C 海平面）', 340.29], ['c', '光速', 299792458]
    ] },
    data: { name: '数据存储', base: 'B', units: [
      ['bit', '比特 bit', 0.125], ['B', '字节 B', 1],
      ['KB', 'KB（千字节，1000）', 1e3], ['MB', 'MB（1000²）', 1e6], ['GB', 'GB（1000³）', 1e9], ['TB', 'TB（1000⁴）', 1e12], ['PB', 'PB（1000⁵）', 1e15],
      ['KiB', 'KiB（1024）', 1024], ['MiB', 'MiB（1024²）', 1024 ** 2], ['GiB', 'GiB（1024³）', 1024 ** 3], ['TiB', 'TiB（1024⁴）', 1024 ** 4], ['PiB', 'PiB（1024⁵）', 1024 ** 5]
    ] },
    time: { name: '时间', base: 's', units: [
      ['ns', '纳秒', 1e-9], ['us', '微秒', 1e-6], ['ms', '毫秒', 1e-3], ['s', '秒', 1], ['min', '分钟', 60], ['h', '小时', 3600],
      ['d', '天', 86400], ['wk', '周', 604800], ['mo', '月（平均 30.44 天）', 2629746], ['yr', '年（365.2425 天）', 31556952], ['cen', '世纪', 3155695200]
    ] }
  };
  const TO_C = { C: v => v, F: v => (v - 32) * 5 / 9, K: v => v - 273.15, R: v => (v - 491.67) * 5 / 9 };
  const FROM_C = { C: v => v, F: v => v * 9 / 5 + 32, K: v => v + 273.15, R: v => (v + 273.15) * 9 / 5 };
  function convert(cat, v, from, to) {
    if (cat === 'temp') return FROM_C[to](TO_C[from](v));
    const u = UNITS[cat].units, f = u.find(x => x[0] === from)[2], t = u.find(x => x[0] === to)[2];
    return v * f / t;
  }
  function fmtU(n) {
    if (!isFinite(n)) return '—';
    if (n === 0) return '0';
    const a = Math.abs(n);
    if (a >= 1e15 || a < 1e-9) return n.toExponential(8).replace(/\.?0+e/, 'e').replace('e+', 'e');
    let s = Number(n.toPrecision(12)).toString();
    if (/e/.test(s)) s = Number(n.toPrecision(12)).toFixed(12).replace(/\.?0+$/, '');
    return s;
  }
  const groupNum = s => {
    if (/e/.test(s)) return s;
    const neg = s.startsWith('-'), [i, f] = (neg ? s.slice(1) : s).split('.');
    return (neg ? '-' : '') + i.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (f !== undefined ? '.' + f : '');
  };
  const DEFAULT_PAIR = {
    length: ['m', 'ft'], mass: ['kg', 'jin'], temp: ['C', 'F'], area: ['m2', 'mu'], volume: ['L', 'mL'],
    speed: ['kmh', 'mps'], data: ['GB', 'GiB'], time: ['h', 'min']
  };

  Hub.register({
    id: 'units', title: '单位换算', group: 'tool', order: 10, icon: ICON.units,
    mount(el, ctx) {
      const saved = ctx.store.get('state', {}) || {};
      let cat = UNITS[saved.cat] ? saved.cat : 'length';
      const pairs = Object.assign({}, DEFAULT_PAIR, saved.pairs || {});
      for (const k of Object.keys(pairs)) if (!UNITS[k] || !Array.isArray(pairs[k]) || !pairs[k].every(u => UNITS[k].units.some(x => x[0] === u))) pairs[k] = DEFAULT_PAIR[k];
      let value = 1, src = 'a';     // which side the user last typed into
      const persist = () => ctx.store.set('state', { cat, pairs });

      el.innerHTML = `
        <div class="uc-root">
          <h2 class="page-title">单位换算</h2>
          <div class="uc-cats">${Object.keys(UNITS).map(k => `<button type="button" data-c="${k}">${UNITS[k].name}</button>`).join('')}</div>
          <div class="card uc-conv">
            <div class="uc-side"><input class="input uc-in uc-a" inputmode="decimal" spellcheck="false"><select class="input uc-sel uc-sa"></select></div>
            <button class="btn uc-swap" title="交换单位"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/></svg></button>
            <div class="uc-side"><input class="input uc-in uc-b" inputmode="decimal" spellcheck="false"><select class="input uc-sel uc-sb"></select></div>
            <div class="uc-formula set-sub"></div>
          </div>
          <div class="card uc-table-card">
            <div class="side-title uc-tt"></div>
            <div class="uc-table"></div>
            <div class="set-sub uc-tip">点击任意一行可将其设为右侧目标单位</div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      const inA = q('.uc-a'), inB = q('.uc-b'), selA = q('.uc-sa'), selB = q('.uc-sb');
      const uname = (c, id) => UNITS[c].units.find(x => x[0] === id)[1];
      const parse = s => { const t = String(s).replace(/[,\s，]/g, ''); return t === '' || t === '-' || t === '.' ? NaN : Number(t); };

      function fillSelects() {
        const opts = UNITS[cat].units.map(u => `<option value="${u[0]}">${esc(u[1])}</option>`).join('');
        selA.innerHTML = opts; selB.innerHTML = opts;
        selA.value = pairs[cat][0]; selB.value = pairs[cat][1];
      }
      function update(fromTyping) {
        const [ua, ub] = pairs[cat];
        const valid = isFinite(value);
        if (fromTyping !== 'a') inA.value = valid ? fmtU(src === 'a' ? value : convert(cat, value, ub, ua)) : inA.value;
        if (fromTyping !== 'b') inB.value = valid ? fmtU(src === 'b' ? value : convert(cat, value, ua, ub)) : inB.value;
        inA.classList.toggle('bad', !valid && src === 'a');
        inB.classList.toggle('bad', !valid && src === 'b');
        const baseVal = src === 'a' ? value : convert(cat, value, ub, ua);   // value in unit A
        // formula line
        let f = '';
        if (cat === 'temp') {
          const F = { 'C>F': '°F = °C × 9/5 + 32', 'F>C': '°C = (°F − 32) × 5/9', 'C>K': 'K = °C + 273.15', 'K>C': '°C = K − 273.15',
            'F>K': 'K = (°F − 32) × 5/9 + 273.15', 'K>F': '°F = (K − 273.15) × 9/5 + 32', 'C>R': '°R = (°C + 273.15) × 9/5', 'R>C': '°C = (°R − 491.67) × 5/9',
            'F>R': '°R = °F + 459.67', 'R>F': '°F = °R − 459.67', 'K>R': '°R = K × 9/5', 'R>K': 'K = °R × 5/9' };
          f = ua === ub ? '' : '公式：' + F[`${ua}>${ub}`];
        } else if (ua !== ub) f = `1 ${uname(cat, ua)} = ${groupNum(fmtU(convert(cat, 1, ua, ub)))} ${uname(cat, ub)}`;
        q('.uc-formula').textContent = f;
        // full table
        q('.uc-tt').textContent = valid ? `${groupNum(fmtU(baseVal))} ${uname(cat, ua)} 等于` : '请输入有效数字';
        const tbl = q('.uc-table');
        tbl.innerHTML = '';
        for (const [id, name] of UNITS[cat].units) {
          const v = valid ? convert(cat, baseVal, ua, id) : NaN;
          const row = h(`<button type="button" class="uc-row${id === ua ? ' a' : ''}${id === ub ? ' b' : ''}"><b>${valid ? esc(groupNum(fmtU(v))) : '—'}</b><span>${esc(name)}</span></button>`);
          row.title = '设为目标单位';
          row.onclick = () => { if (id === ua) return; pairs[cat][1] = id; selB.value = id; src = 'a'; value = baseVal; persist(); update(); };
          tbl.appendChild(row);
        }
        if (cat === 'temp' && valid) {
          const k = convert('temp', baseVal, ua, 'K');
          if (k < -1e-9) tbl.appendChild(h('<div class="uc-warn">⚠ 低于绝对零度（0 K），物理上不存在</div>'));
        }
      }
      function renderCats() { el.querySelectorAll('.uc-cats button').forEach(b => b.classList.toggle('on', b.dataset.c === cat)); }
      function setCat(c) {
        const cur = src === 'a' ? value : parse(inA.value);
        cat = c; persist(); renderCats(); fillSelects();
        value = isFinite(cur) ? cur : 1; src = 'a';
        if (c === 'temp' && value === 1) value = 25;
        update();
      }

      el.querySelectorAll('.uc-cats button').forEach(b => b.onclick = () => setCat(b.dataset.c));
      inA.oninput = () => { src = 'a'; value = parse(inA.value); update('a'); };
      inB.oninput = () => { src = 'b'; value = parse(inB.value); update('b'); };
      inA.onblur = inB.onblur = () => { if (isFinite(value)) update(); };
      selA.onchange = () => { pairs[cat][0] = selA.value; persist(); update(); };
      selB.onchange = () => { pairs[cat][1] = selB.value; persist(); update(); };
      q('.uc-swap').onclick = () => {
        const cur = src === 'a' ? value : convert(cat, value, pairs[cat][1], pairs[cat][0]);
        pairs[cat] = [pairs[cat][1], pairs[cat][0]];
        selA.value = pairs[cat][0]; selB.value = pairs[cat][1];
        value = cur; src = 'a';          // keep the number on the left, re-interpret in the new unit
        persist(); update();
        q('.uc-swap').blur();
      };

      renderCats(); fillSelects();
      if (cat === 'temp') value = 25;
      update();
    },
    unmount() {}
  });

  // =====================================================================
  // 密码生成器
  // =====================================================================
  const SETS = {
    upper: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    lower: 'abcdefghijklmnopqrstuvwxyz',
    digit: '0123456789',
    symbol: '!@#$%^&*()-_=+[]{};:,.<>/?~'
  };
  const AMBIG = new Set('Il1O0o|`\'"'.split(''));
  const WORDS = [...new Set(`
    apple river stone cloud tiger happy orange silver garden window yellow purple winter summer spring autumn
    forest ocean island mountain valley desert planet rocket bridge castle dragon eagle falcon rabbit turtle
    monkey panda koala zebra lemon mango peach cherry grape melon banana coffee cookie butter bread honey
    candle pencil paper letter button pocket basket bottle carpet mirror ladder hammer anchor compass lantern
    blanket pillow jacket shadow sunset sunrise thunder rainbow breeze meadow harbor canyon glacier volcano
    diamond crystal marble copper bronze velvet cotton silk wooden golden gentle brave quiet clever lucky
    bright calm eager fancy jolly kind lively mighty noble proud rapid simple smart swift tidy warm wise
    zesty bold cozy fresh grand merry neat sunny cheerful friendly humble polite curious steady magic
    music piano guitar violin drum flute poem story novel dream smile laugh dance jump swim climb travel
    journey voyage camera ticket station airport market school library museum temple palace village city
    street corner circle square triangle arrow pixel robot laser orbit comet galaxy nebula meteor atom
    energy signal battery engine motor wheel tractor bicycle scooter sailor pilot farmer baker painter doctor
    nurse chef artist singer writer ranger hunter wizard knight prince queen giant ninja pirate cowboy
    kitten puppy parrot dolphin whale shark octopus penguin otter beaver badger fox wolf bear lion horse
    tomato potato carrot pepper onion garlic ginger olive walnut almond peanut noodle pizza salad soup
    sugar salt spice tea juice water fire earth metal wind snow ice rain storm frost flame spark
  `.trim().split(/\s+/))];
  const history = [];   // memory only — never persisted

  function randInt(n) {
    // uniform integer in [0, n) via rejection sampling (no modulo bias)
    const limit = Math.floor(0x100000000 / n) * n;
    const buf = new Uint32Array(1);
    for (;;) {
      crypto.getRandomValues(buf);
      if (buf[0] < limit) return buf[0] % n;
    }
  }

  function strengthOf(bits) {
    if (bits < 28) return ['很弱', 0, '#e5484d'];
    if (bits < 36) return ['弱', 1, '#f28c50'];
    if (bits < 60) return ['中等', 2, '#e0a526'];
    if (bits < 80) return ['强', 3, '#8fb35a'];
    return ['很强', 4, '#3f9d5a'];
  }
  function crackTime(bits) {
    // offline attack at 1e10 guesses/s, average half the space
    const sec = Math.pow(2, bits - 1) / 1e10;
    if (sec < 1) return '瞬间';
    const U = [[31556952e2, '世纪'], [31556952, '年'], [86400, '天'], [3600, '小时'], [60, '分钟'], [1, '秒']];
    for (const [s, n] of U) if (sec >= s) {
      const v = sec / s;
      return v >= 1e6 ? `约 ${v.toExponential(1).replace('e+', '×10^')} ${n}` : `约 ${Math.round(v).toLocaleString('zh-CN')} ${n}`;
    }
    return '瞬间';
  }

  async function copyText(text) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(text); return true; }
    } catch (e) { /* fall through */ }
    const ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    ta.remove();
    return ok;
  }

  let pwCleanup = null;
  Hub.register({
    id: 'passgen', title: '密码生成器', group: 'tool', order: 11, icon: ICON.passgen,
    mount(el, ctx) {
      // only the generator settings are persisted — never passwords
      const def = { mode: 'chars', len: 16, upper: true, lower: true, digit: true, symbol: true, noAmbig: false, words: 5, sep: '-', cap: true, num: false };
      const opt = Object.assign({}, def, ctx.store.get('opts', {}) || {});
      opt.len = Math.min(64, Math.max(6, opt.len | 0 || 16));
      opt.words = Math.min(10, Math.max(3, opt.words | 0 || 5));
      const persist = () => ctx.store.set('opts', opt);
      let current = '', bits = 0;

      el.innerHTML = `
        <div class="pw-root">
          <h2 class="page-title">密码生成器</h2>
          <div class="card pw-out-card">
            <div class="pw-out"><div class="pw-text"></div>
              <button class="btn pw-regen" title="重新生成 (Enter / 空格)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/></svg></button>
              <button class="btn primary pw-copy" title="复制 (Ctrl+C)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/></svg>复制</button>
            </div>
            <div class="pw-meter"><i></i><i></i><i></i><i></i><i></i></div>
            <div class="pw-meter-t"><b class="pw-str"></b><span class="set-sub pw-bits"></span></div>
          </div>
          <div class="pw-grid">
            <div class="card pw-opts">
              <div class="pw-modes"><button type="button" data-m="chars">随机字符</button><button type="button" data-m="words">单词口令</button></div>
              <div class="pw-chars">
                <div class="pw-len"><span class="side-title">长度</span><input type="range" class="pw-len-r" min="6" max="64"><b class="pw-len-v"></b></div>
                <label class="pw-opt"><span>大写字母 A-Z</span><label class="switch"><input type="checkbox" data-o="upper"><span></span></label></label>
                <label class="pw-opt"><span>小写字母 a-z</span><label class="switch"><input type="checkbox" data-o="lower"><span></span></label></label>
                <label class="pw-opt"><span>数字 0-9</span><label class="switch"><input type="checkbox" data-o="digit"><span></span></label></label>
                <label class="pw-opt"><span>符号 !@#$…</span><label class="switch"><input type="checkbox" data-o="symbol"><span></span></label></label>
                <label class="pw-opt"><span>排除易混淆字符 <em class="set-sub">I l 1 O 0 o |</em></span><label class="switch"><input type="checkbox" data-o="noAmbig"><span></span></label></label>
              </div>
              <div class="pw-words">
                <div class="pw-len"><span class="side-title">单词数</span><input type="range" class="pw-w-r" min="3" max="10"><b class="pw-w-v"></b></div>
                <div class="pw-opt"><span>分隔符</span><div class="pw-seps">${['-', '_', '.', ' ', ''].map(s => `<button type="button" data-s="${s}">${s === ' ' ? '空格' : s === '' ? '无' : s}</button>`).join('')}</div></div>
                <label class="pw-opt"><span>首字母大写</span><label class="switch"><input type="checkbox" data-o="cap"><span></span></label></label>
                <label class="pw-opt"><span>末尾追加一位数字</span><label class="switch"><input type="checkbox" data-o="num"><span></span></label></label>
                <div class="set-sub pw-wl"></div>
              </div>
            </div>
            <div class="card pw-hist-card">
              <div class="pw-hist-h"><span class="side-title">最近生成</span><button class="btn pw-clear">清空</button></div>
              <div class="pw-hist"></div>
              <div class="set-sub pw-note">历史只保存在内存中（最近 10 条），关闭程序后即清除，不会写入磁盘。</div>
            </div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      q('.pw-wl').textContent = `词库共 ${WORDS.length} 个常用英文单词，每个单词约 ${Math.log2(WORDS.length).toFixed(1)} 位熵。`;

      function pool() {
        let sets = ['upper', 'lower', 'digit', 'symbol'].filter(k => opt[k]).map(k => SETS[k]);
        if (opt.noAmbig) sets = sets.map(s => [...s].filter(c => !AMBIG.has(c)).join(''));
        return sets.filter(s => s.length);
      }

      function generate() {
        if (opt.mode === 'words') {
          const w = [];
          for (let i = 0; i < opt.words; i++) {
            let x = WORDS[randInt(WORDS.length)];
            if (opt.cap) x = x[0].toUpperCase() + x.slice(1);
            w.push(x);
          }
          let s = w.join(opt.sep);
          if (opt.num) s += (opt.sep || '') + randInt(10);
          bits = opt.words * Math.log2(WORDS.length) + (opt.num ? Math.log2(10) : 0);
          return s;
        }
        const sets = pool();
        if (!sets.length) { bits = 0; return ''; }
        const all = sets.join('');
        bits = opt.len * Math.log2(all.length);
        // require every enabled set to appear: regenerate until satisfied (keeps the distribution uniform over valid passwords)
        for (let tries = 0; tries < 1000; tries++) {
          let s = '';
          for (let i = 0; i < opt.len; i++) s += all[randInt(all.length)];
          if (opt.len < sets.length || sets.every(set => [...s].some(c => set.includes(c)))) return s;
        }
        return '';
      }

      function renderOut() {
        const box = q('.pw-text');
        box.innerHTML = '';
        if (!current) { box.innerHTML = '<span class="pw-none">请至少选择一种字符类型</span>'; }
        else for (const c of current) {
          const span = document.createElement('span');
          span.textContent = c;
          span.className = /[0-9]/.test(c) ? 'd' : /[A-Za-z]/.test(c) ? '' : 's';
          box.appendChild(span);
        }
        box.style.fontSize = current.length > 48 ? '15px' : current.length > 32 ? '18px' : '22px';
        const [lbl, lvl, color] = strengthOf(bits);
        el.querySelectorAll('.pw-meter i').forEach((i, k) => { i.style.background = current && k <= lvl ? color : ''; });
        q('.pw-str').textContent = current ? lbl : '—';
        q('.pw-str').style.color = color;
        q('.pw-bits').textContent = current ? `约 ${bits.toFixed(1)} 位熵 · 离线暴力破解（10¹⁰ 次/秒）需 ${crackTime(bits)}` : '';
      }
      function renderHist() {
        const box = q('.pw-hist');
        if (!history.length) { box.innerHTML = '<div class="pw-empty">暂无记录</div>'; return; }
        box.innerHTML = '';
        history.forEach(p => {
          const row = h('<button type="button" class="pw-hi" title="点击复制"><code></code><span>复制</span></button>');
          row.querySelector('code').textContent = p;
          row.onclick = () => doCopy(p);
          box.appendChild(row);
        });
      }
      function pushHist(p) {
        if (!p) return;
        const i = history.indexOf(p);
        if (i >= 0) history.splice(i, 1);
        history.unshift(p);
        history.length = Math.min(history.length, 10);
      }
      function regen() {
        current = generate();
        renderOut();
      }
      async function doCopy(text) {
        if (!text) return;
        const ok = await copyText(text);
        ctx.toast(ok ? '已复制到剪贴板' : '复制失败，请手动选择复制');
        if (ok && text === current) { pushHist(current); renderHist(); }
      }
      function renderOpts() {
        el.querySelectorAll('.pw-modes button').forEach(b => b.classList.toggle('on', b.dataset.m === opt.mode));
        q('.pw-chars').style.display = opt.mode === 'chars' ? '' : 'none';
        q('.pw-words').style.display = opt.mode === 'words' ? '' : 'none';
        q('.pw-len-r').value = opt.len; q('.pw-len-v').textContent = opt.len;
        q('.pw-w-r').value = opt.words; q('.pw-w-v').textContent = opt.words;
        el.querySelectorAll('input[data-o]').forEach(i => { i.checked = !!opt[i.dataset.o]; });
        el.querySelectorAll('.pw-seps button').forEach(b => b.classList.toggle('on', b.dataset.s === opt.sep));
      }
      const changed = () => { persist(); renderOpts(); regen(); };

      el.querySelectorAll('.pw-modes button').forEach(b => b.onclick = () => { opt.mode = b.dataset.m; changed(); });
      q('.pw-len-r').oninput = e => { opt.len = +e.target.value; changed(); };
      q('.pw-w-r').oninput = e => { opt.words = +e.target.value; changed(); };
      el.querySelectorAll('input[data-o]').forEach(i => i.onchange = () => {
        opt[i.dataset.o] = i.checked;
        if (!['upper', 'lower', 'digit', 'symbol'].some(k => opt[k])) { opt[i.dataset.o] = true; ctx.toast('至少保留一种字符类型'); }
        changed();
      });
      el.querySelectorAll('.pw-seps button').forEach(b => b.onclick = () => { opt.sep = b.dataset.s; changed(); });
      q('.pw-regen').onclick = e => { e.currentTarget.blur(); regen(); };
      q('.pw-copy').onclick = e => { e.currentTarget.blur(); doCopy(current); };
      q('.pw-clear').onclick = () => { history.length = 0; renderHist(); };

      function onKey(e) {
        if (!ctx.isActive() || isTyping(e)) return;
        if (e.altKey) return;
        if ((e.ctrlKey || e.metaKey) && (e.key === 'c' || e.key === 'C')) {
          const sel = window.getSelection && String(window.getSelection());
          if (sel) return;              // let normal copy of a selection happen
          e.preventDefault(); doCopy(current);
        } else if (!e.ctrlKey && !e.metaKey && (e.key === 'Enter' || e.key === ' ')) {
          if (e.target && e.target.tagName === 'BUTTON') return;
          e.preventDefault(); regen();
        }
      }
      window.addEventListener('keydown', onKey);
      pwCleanup = () => { window.removeEventListener('keydown', onKey); current = ''; };

      renderOpts();
      regen();
      renderHist();
    },
    unmount() { if (pwCleanup) pwCleanup(); pwCleanup = null; }
  });
})();
