// Tool pages: 记账本 / 习惯打卡 / 计算器. See MODULES.md for the module contract.
(function () {
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const pad = n => String(n).padStart(2, '0');
  const dayKey = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const today = () => dayKey(new Date());
  const parseDay = k => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
  const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
  const WEEK = ['日', '一', '二', '三', '四', '五', '六'];
  const DEL_SVG = '<svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
  const isTyping = e => { const t = e.target && e.target.tagName; return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || (e.target && e.target.isContentEditable); };

  const ICON = {
    ledger: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M5 3.5h12a2 2 0 0 1 2 2v15H7a2 2 0 0 1-2-2z"/><path d="M5 17a2 2 0 0 1 2-2h12M9.5 7.5l2 2.5 2-2.5M11.5 10v3.5M9.5 11h4" stroke-linecap="round"/></svg>',
    habits: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3.5" y="4.5" width="17" height="16" rx="2.5"/><path d="M3.5 9.5h17M8 2.5v4M16 2.5v4" stroke-linecap="round"/><path d="M8.5 15l2.3 2.2 4.7-4.7" stroke-linecap="round"/></svg>',
    calc: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="4.5" y="2.5" width="15" height="19" rx="2.5"/><rect x="7.5" y="5.5" width="9" height="4" rx="1"/><path d="M8 13h.01M12 13h.01M16 13h.01M8 17h.01M12 17h.01M16 17h.01" stroke-width="2.6" stroke-linecap="round"/></svg>'
  };

  // =====================================================================
  // 记账本
  // =====================================================================
  const CATS = {
    out: [
      ['food', '餐饮', '🍜', '#f28c50'], ['traffic', '交通', '🚌', '#5b9bd5'], ['shop', '购物', '🛍️', '#e8638a'],
      ['fun', '娱乐', '🎮', '#9b7ae0'], ['house', '居住', '🏠', '#c2894e'], ['med', '医疗', '💊', '#4db6ac'],
      ['study', '学习', '📚', '#6aa84f'], ['other', '其他', '📦', '#a39180']
    ],
    in: [
      ['salary', '工资', '💰', '#e0a526'], ['redpack', '红包', '🧧', '#e5484d'], ['otherin', '其他', '✨', '#8fb35a']
    ]
  };
  const CAT = {};
  for (const t of ['out', 'in']) for (const [id, name, emoji, color] of CATS[t]) CAT[id] = { id, name, emoji, color, type: t };
  const money = v => (Math.round(v) / 100).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  Hub.register({
    id: 'ledger', title: '记账本', group: 'tool', order: 6, icon: ICON.ledger,
    mount(el, ctx) {
      let entries = ctx.store.get('entries', []);   // {id, type, amount(cents), cat, note, date}
      let budget = ctx.store.get('budget', 0);       // cents per month, 0 = none
      const now = new Date();
      let ym = [now.getFullYear(), now.getMonth()];  // viewed month
      let type = 'out', cat = 'food';
      const save = () => ctx.store.set('entries', entries);

      el.innerHTML = `
        <div class="acc-root">
          <h2 class="page-title">记账本</h2>
          <div class="acc-top">
            <div class="acc-month">
              <button class="btn acc-prev" title="上个月">‹</button>
              <b class="acc-ym"></b>
              <button class="btn acc-next" title="下个月">›</button>
              <button class="btn acc-now">本月</button>
            </div>
            <button class="btn acc-export">导出 CSV</button>
          </div>
          <div class="acc-sum">
            <div class="card acc-sum-i in"><span>收入</span><b class="acc-in"></b></div>
            <div class="card acc-sum-i out"><span>支出</span><b class="acc-out"></b></div>
            <div class="card acc-sum-i bal"><span>结余</span><b class="acc-bal"></b></div>
          </div>
          <div class="card acc-budget">
            <div class="acc-budget-row">
              <span class="side-title">月预算</span>
              <span class="acc-budget-txt set-sub"></span>
              <input class="input acc-budget-in" type="number" min="0" step="100" placeholder="未设置">
              <button class="btn acc-budget-set">设置</button>
            </div>
            <div class="acc-bar"><div></div></div>
          </div>
          <div class="acc-grid">
            <form class="card acc-form">
              <div class="side-title">记一笔</div>
              <div class="acc-type"><button type="button" data-t="out">支出</button><button type="button" data-t="in">收入</button></div>
              <div class="acc-cats"></div>
              <div class="acc-fields">
                <input class="input acc-amt" type="number" min="0.01" step="0.01" placeholder="金额" required>
                <input class="input acc-date" type="date" required>
              </div>
              <input class="input acc-note" maxlength="60" placeholder="备注（可选）">
              <button class="btn primary acc-add" type="submit">保存</button>
            </form>
            <div class="card acc-chart">
              <div class="side-title">支出构成</div>
              <div class="acc-donut-wrap"><svg class="acc-donut" viewBox="0 0 160 160"></svg><div class="acc-legend"></div></div>
            </div>
          </div>
          <div class="card acc-daily">
            <div class="side-title">每日收支</div>
            <svg class="acc-bars" viewBox="0 0 680 150"></svg>
          </div>
          <div class="card acc-list-card">
            <div class="side-title">明细</div>
            <div class="acc-list"></div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      q('.acc-date').value = today();

      const monthKey = () => `${ym[0]}-${pad(ym[1] + 1)}`;
      const monthEntries = (key = monthKey()) => entries.filter(e => e.date.startsWith(key + '-'));
      const totals = list => {
        let i = 0, o = 0;
        for (const e of list) e.type === 'in' ? i += e.amount : o += e.amount;
        return { i, o };
      };

      function renderForm() {
        el.querySelectorAll('.acc-type button').forEach(b => b.classList.toggle('on', b.dataset.t === type));
        q('.acc-form').dataset.t = type;
        const box = q('.acc-cats');
        box.innerHTML = '';
        for (const [id, name, emoji, color] of CATS[type]) {
          const b = h(`<button type="button" class="acc-cat ${id === cat ? 'on' : ''}" style="--c:${color}"><i>${emoji}</i><span>${name}</span></button>`);
          b.onclick = () => { cat = id; renderForm(); };
          box.appendChild(b);
        }
      }

      function renderDonut(list) {
        const by = {};
        for (const e of list) if (e.type === 'out') by[e.cat] = (by[e.cat] || 0) + e.amount;
        const rows = Object.entries(by).sort((a, b) => b[1] - a[1]);
        const total = rows.reduce((s, r) => s + r[1], 0);
        const svg = q('.acc-donut'), legend = q('.acc-legend');
        const R = 58, C = 2 * Math.PI * R;
        if (!total) {
          svg.innerHTML = `<circle cx="80" cy="80" r="${R}" fill="none" stroke="#f1e3d1" stroke-width="22"/><text x="80" y="85" class="acc-dc-t">暂无支出</text>`;
          legend.innerHTML = '<div class="set-sub">本月还没有支出记录</div>';
          return;
        }
        let off = 0, s = '';
        for (const [id, v] of rows) {
          const len = v / total * C;
          const gap = rows.length > 1 ? Math.min(1.5, len / 3) : 0;
          s += `<circle cx="80" cy="80" r="${R}" fill="none" stroke="${(CAT[id] || CAT.other).color}" stroke-width="22"
            stroke-dasharray="${Math.max(0, len - gap)} ${C}" stroke-dashoffset="${-off}" transform="rotate(-90 80 80)"><title>${(CAT[id] || CAT.other).name} ${money(v)}</title></circle>`;
          off += len;
        }
        s += `<text x="80" y="76" class="acc-dc-s">总支出</text><text x="80" y="96" class="acc-dc-v">${money(total)}</text>`;
        svg.innerHTML = s;
        legend.innerHTML = rows.map(([id, v]) => {
          const c = CAT[id] || CAT.other;
          return `<div class="acc-lg"><i style="background:${c.color}"></i><span>${c.emoji} ${c.name}</span><b>${money(v)}</b><em>${(v / total * 100).toFixed(1)}%</em></div>`;
        }).join('');
      }

      function renderBars(list) {
        const days = new Date(ym[0], ym[1] + 1, 0).getDate();
        const inD = new Array(days).fill(0), outD = new Array(days).fill(0);
        for (const e of list) { const d = Number(e.date.slice(8)) - 1; (e.type === 'in' ? inD : outD)[d] += e.amount; }
        const max = Math.max(1, ...inD, ...outD);
        const W = 680, top = 12, base = 126, bw = W / days;
        const isCur = monthKey() === today().slice(0, 7), td = new Date().getDate();
        let s = `<line x1="0" x2="${W}" y1="${base}" y2="${base}" stroke="#ead9c3"/>`;
        for (let i = 0; i < days; i++) {
          const x = i * bw, w = Math.max(2, bw / 2 - 2);
          const ho = outD[i] / max * (base - top), hi = inD[i] / max * (base - top);
          if (isCur && i + 1 === td) s += `<rect x="${x}" y="0" width="${bw}" height="${base}" fill="#fde9d9" opacity=".6"/>`;
          if (outD[i]) s += `<rect x="${x + bw / 2 - w - 1}" y="${base - ho}" width="${w}" height="${ho}" rx="2" fill="#e8793a"><title>${ym[1] + 1}/${i + 1} 支出 ${money(outD[i])}</title></rect>`;
          if (inD[i]) s += `<rect x="${x + bw / 2 + 1}" y="${base - hi}" width="${w}" height="${hi}" rx="2" fill="#5da35a"><title>${ym[1] + 1}/${i + 1} 收入 ${money(inD[i])}</title></rect>`;
          if (i === 0 || (i + 1) % 5 === 0) s += `<text x="${x + bw / 2}" y="144" class="acc-bl">${i + 1}</text>`;
        }
        q('.acc-bars').innerHTML = s;
      }

      function renderList(list) {
        const box = q('.acc-list');
        if (!list.length) { box.innerHTML = '<div class="acc-empty">这个月还没有记录，记下第一笔吧~</div>'; return; }
        const groups = {};
        for (const e of list) (groups[e.date] = groups[e.date] || []).push(e);
        box.innerHTML = '';
        for (const d of Object.keys(groups).sort().reverse()) {
          const g = groups[d].sort((a, b) => b.id - a.id), t = totals(g), dt = parseDay(d);
          const sec = h(`<div class="acc-day"><div class="acc-day-h"><b>${dt.getMonth() + 1}月${dt.getDate()}日</b><span>周${WEEK[dt.getDay()]}${d === today() ? ' · 今天' : ''}</span>
            <em>${t.i ? `收 ${money(t.i)}` : ''}${t.i && t.o ? ' · ' : ''}${t.o ? `支 ${money(t.o)}` : ''}</em></div></div>`);
          for (const e of g) {
            const c = CAT[e.cat] || CAT.other;
            const row = h(`<div class="acc-row"><i class="acc-ic" style="background:${c.color}22;color:${c.color}">${c.emoji}</i>
              <div class="acc-row-t"><div>${c.name}</div><div class="set-sub"></div></div>
              <b class="${e.type}">${e.type === 'in' ? '+' : '-'}${money(e.amount)}</b>
              <button class="acc-del" title="删除">${DEL_SVG}</button></div>`);
            row.querySelector('.set-sub').textContent = e.note || '';
            row.querySelector('.acc-del').onclick = () => { entries = entries.filter(x => x !== e); save(); render(); };
            sec.appendChild(row);
          }
          box.appendChild(sec);
        }
      }

      function renderBudget(t) {
        const bar = q('.acc-bar div'), txt = q('.acc-budget-txt');
        if (document.activeElement !== q('.acc-budget-in')) q('.acc-budget-in').value = budget ? budget / 100 : '';
        if (!budget) { txt.textContent = '设置每月预算，超支时桌宠会提醒你'; bar.style.width = '0'; bar.parentElement.className = 'acc-bar'; return; }
        const r = t.o / budget;
        txt.textContent = r > 1 ? `已超支 ${money(t.o - budget)}（${money(t.o)} / ${money(budget)}）` : `已用 ${money(t.o)} / ${money(budget)}，剩余 ${money(budget - t.o)}`;
        bar.style.width = `${Math.min(100, r * 100)}%`;
        bar.parentElement.className = `acc-bar${r > 1 ? ' over' : r > 0.8 ? ' warn' : ''}`;
      }

      function render() {
        q('.acc-ym').textContent = `${ym[0]}年${ym[1] + 1}月`;
        const list = monthEntries(), t = totals(list);
        q('.acc-in').textContent = money(t.i);
        q('.acc-out').textContent = money(t.o);
        q('.acc-bal').textContent = money(t.i - t.o);
        q('.acc-bal').classList.toggle('neg', t.i - t.o < 0);
        renderBudget(t);
        renderDonut(list);
        renderBars(list);
        renderList(list);
      }

      const shift = n => { const d = new Date(ym[0], ym[1] + n, 1); ym = [d.getFullYear(), d.getMonth()]; render(); };
      q('.acc-prev').onclick = () => shift(-1);
      q('.acc-next').onclick = () => shift(1);
      q('.acc-now').onclick = () => { const d = new Date(); ym = [d.getFullYear(), d.getMonth()]; render(); };
      el.querySelectorAll('.acc-type button').forEach(b => b.onclick = () => { type = b.dataset.t; cat = CATS[type][0][0]; renderForm(); });

      q('.acc-form').onsubmit = e => {
        e.preventDefault();
        const amount = Math.round(Number(q('.acc-amt').value) * 100);
        const date = q('.acc-date').value;
        if (!(amount > 0) || !/^\d{4}-\d{2}-\d{2}$/.test(date)) { ctx.toast('请输入有效的金额和日期'); return; }
        const mk = date.slice(0, 7);
        const before = totals(monthEntries(mk)).o;
        entries.push({ id: Date.now(), type, amount, cat, note: q('.acc-note').value.trim(), date });
        save();
        q('.acc-amt').value = ''; q('.acc-note').value = '';
        const [y, m] = mk.split('-').map(Number); ym = [y, m - 1];
        render();
        ctx.toast(`已记录${type === 'in' ? '收入' : '支出'} ${money(amount)}`);
        if (type === 'out' && budget) {
          const after = before + amount;
          if (before <= budget && after > budget) ctx.say(`${m}月的预算超支啦！已经花了 ${money(after)}，省着点哦~`);
          else if (before <= budget * 0.8 && after > budget * 0.8 && after <= budget) ctx.say(`${m}月预算已经用掉 ${Math.round(after / budget * 100)}% 了，注意控制哦~`);
        }
        q('.acc-amt').focus();
      };

      q('.acc-budget-set').onclick = () => {
        const v = Math.max(0, Math.round(Number(q('.acc-budget-in').value || 0) * 100));
        budget = v; ctx.store.set('budget', budget);
        ctx.toast(v ? `月预算已设为 ${money(v)}` : '已取消月预算');
        render();
        const t = totals(monthEntries(today().slice(0, 7)));
        if (v && t.o > v) ctx.say(`本月已经超出预算 ${money(t.o - v)} 了哦！`);
      };
      q('.acc-budget-in').onkeydown = e => { if (e.key === 'Enter') q('.acc-budget-set').click(); };

      q('.acc-export').onclick = () => {
        const list = monthEntries().sort((a, b) => a.date.localeCompare(b.date) || a.id - b.id);
        if (!list.length) { ctx.toast('本月没有可导出的记录'); return; }
        const cell = v => /[",\n]/.test(v) ? `"${String(v).replace(/"/g, '""')}"` : v;
        const lines = [['日期', '类型', '分类', '金额', '备注'].join(',')];
        for (const e of list) lines.push([e.date, e.type === 'in' ? '收入' : '支出', (CAT[e.cat] || CAT.other).name, (e.amount / 100).toFixed(2), cell(e.note || '')].join(','));
        const blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = `记账本-${monthKey()}.csv`;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
        ctx.toast('已导出 CSV');
      };

      renderForm();
      render();
    },
    unmount() {}
  });

  // =====================================================================
  // 习惯打卡
  // =====================================================================
  const HB_COLORS = ['#e8793a', '#5da35a', '#5b9bd5', '#e8638a', '#9b7ae0', '#e0a526', '#4db6ac', '#c2894e'];
  const HB_ICONS = ['💧', '🏃', '📖', '🧘', '🥗', '😴', '✍️', '🎸', '💊', '🧹', '🌞', '🚭', '💪', '🐾', '🎯', '🧠'];
  const WEEKS = 20;

  function streaks(days) {
    // current streak: consecutive days ending today (or yesterday if today not done yet)
    let d = new Date(), cur = 0;
    if (!days[dayKey(d)]) d = addDays(d, -1);
    while (days[dayKey(d)]) { cur++; d = addDays(d, -1); }
    let best = 0, run = 0, prev = null;
    for (const k of Object.keys(days).filter(k => days[k]).sort()) {
      const t = parseDay(k);
      run = prev && Math.round((t - prev) / 864e5) === 1 ? run + 1 : 1;
      best = Math.max(best, run); prev = t;
    }
    return { cur, best: Math.max(best, cur) };
  }

  Hub.register({
    id: 'habits', title: '习惯打卡', group: 'tool', order: 7, icon: ICON.habits,
    mount(el, ctx) {
      let habits = ctx.store.get('habits', []);   // {id, name, color, icon, days: {key: true}}
      const save = () => ctx.store.set('habits', habits);
      let editing = null; // habit being edited or 'new'
      let form = { name: '', color: HB_COLORS[0], icon: HB_ICONS[0] };

      el.innerHTML = `
        <div class="hb-root">
          <h2 class="page-title">习惯打卡 <span class="set-sub hb-date"></span> <button class="btn primary hb-new">+ 新习惯</button></h2>
          <div class="hb-summary"></div>
          <div class="card hb-editor hidden">
            <div class="side-title hb-ed-title">新习惯</div>
            <div class="hb-ed-row"><input class="input hb-name" maxlength="20" placeholder="习惯名称，如：每天喝 8 杯水"></div>
            <div class="hb-ed-row"><span class="set-sub">图标</span><div class="hb-icons"></div></div>
            <div class="hb-ed-row"><span class="set-sub">颜色</span><div class="hb-colors"></div></div>
            <div class="hb-ed-btns"><button class="btn hb-del-h">删除习惯</button><span></span><button class="btn hb-cancel">取消</button><button class="btn primary hb-save">保存</button></div>
          </div>
          <div class="hb-list"></div>
        </div>`;
      const q = s => el.querySelector(s);
      const d0 = new Date();
      q('.hb-date').textContent = `${d0.getMonth() + 1}月${d0.getDate()}日 周${WEEK[d0.getDay()]}`;

      function openEditor(hb) {
        editing = hb || 'new';
        form = hb ? { name: hb.name, color: hb.color, icon: hb.icon } : { name: '', color: HB_COLORS[habits.length % HB_COLORS.length], icon: HB_ICONS[habits.length % HB_ICONS.length] };
        q('.hb-editor').classList.remove('hidden');
        q('.hb-ed-title').textContent = hb ? '编辑习惯' : '新习惯';
        q('.hb-del-h').style.display = hb ? '' : 'none';
        q('.hb-name').value = form.name;
        renderEditor();
        q('.hb-name').focus();
      }
      function closeEditor() { editing = null; q('.hb-editor').classList.add('hidden'); }
      function renderEditor() {
        q('.hb-icons').innerHTML = HB_ICONS.map(i => `<button class="hb-pick ${i === form.icon ? 'on' : ''}" data-i="${i}">${i}</button>`).join('');
        q('.hb-colors').innerHTML = HB_COLORS.map(c => `<button class="hb-sw ${c === form.color ? 'on' : ''}" data-c="${c}" style="background:${c}"></button>`).join('');
        el.querySelectorAll('.hb-pick').forEach(b => b.onclick = () => { form.icon = b.dataset.i; renderEditor(); });
        el.querySelectorAll('.hb-sw').forEach(b => b.onclick = () => { form.color = b.dataset.c; renderEditor(); });
      }
      q('.hb-new').onclick = () => openEditor(null);
      q('.hb-cancel').onclick = closeEditor;
      q('.hb-name').onkeydown = e => { if (e.key === 'Enter') q('.hb-save').click(); if (e.key === 'Escape') closeEditor(); };
      q('.hb-save').onclick = () => {
        const name = q('.hb-name').value.trim();
        if (!name) { ctx.toast('请输入习惯名称'); q('.hb-name').focus(); return; }
        if (editing === 'new') habits.push({ id: Date.now(), name, color: form.color, icon: form.icon, days: {} });
        else Object.assign(editing, { name, color: form.color, icon: form.icon });
        save(); closeEditor(); render();
      };
      q('.hb-del-h').onclick = () => {
        if (editing === 'new' || !confirm(`确定删除习惯「${editing.name}」及其全部打卡记录吗？`)) return;
        habits = habits.filter(x => x !== editing);
        save(); closeEditor(); render();
      };

      function checkAllDone() {
        const t = today();
        if (!habits.length || !habits.every(x => x.days[t])) return;
        if (ctx.store.get('rewardDate', '') === t) return;
        ctx.store.set('rewardDate', t);
        ctx.reward(5, '习惯全勤');
        ctx.say('今天的习惯全部打卡完成！坚持就是胜利 🎉');
      }

      function toggle(hb, key) {
        if (hb.days[key]) delete hb.days[key]; else hb.days[key] = true;
        save(); render();
        if (key === today() && hb.days[key]) {
          const s = streaks(hb.days);
          if (s.cur > 1 && s.cur % 7 === 0) ctx.say(`「${hb.name}」已经连续坚持 ${s.cur} 天啦！`);
          checkAllDone();
        }
      }

      function heatmap(hb) {
        const CELL = 12, GAP = 3, S = CELL + GAP;
        const now = new Date();
        const dow = (now.getDay() + 6) % 7;                      // Monday = 0
        const start = addDays(now, -dow - (WEEKS - 1) * 7);      // Monday, WEEKS-1 weeks ago
        const created = hb.id ? dayKey(new Date(hb.id)) : '';
        let s = '', lastMonth = -1;
        for (let w = 0; w < WEEKS; w++) {
          const wd = addDays(start, w * 7);
          if (wd.getMonth() !== lastMonth) {
            if (w < WEEKS - 1) s += `<text x="${22 + w * S}" y="9" class="hb-ml">${wd.getMonth() + 1}月</text>`;
            lastMonth = wd.getMonth();
          }
          for (let d = 0; d < 7; d++) {
            const day = addDays(start, w * 7 + d), k = dayKey(day);
            if (day > now) continue;
            const on = !!hb.days[k];
            const cls = `hb-cell${on ? ' on' : ''}${k === today() ? ' today' : ''}${k < created && !on ? ' pre' : ''}`;
            s += `<rect x="${22 + w * S}" y="${14 + d * S}" width="${CELL}" height="${CELL}" rx="3" class="${cls}" data-k="${k}"${on ? ` style="fill:${hb.color}"` : ''}><title>${day.getMonth() + 1}月${day.getDate()}日 ${on ? '已打卡' : '未打卡'}（点击切换）</title></rect>`;
          }
        }
        for (const [d, t] of [[0, '一'], [2, '三'], [4, '五'], [6, '日']]) s += `<text x="0" y="${14 + d * S + 10}" class="hb-wl">${t}</text>`;
        return `<svg class="hb-heat" viewBox="0 0 ${22 + WEEKS * S} ${14 + 7 * S}" width="${22 + WEEKS * S}" height="${14 + 7 * S}">${s}</svg>`;
      }

      function weekRate(hb) {
        const now = new Date(), dow = (now.getDay() + 6) % 7;
        let done = 0;
        for (let i = 0; i <= dow; i++) if (hb.days[dayKey(addDays(now, -i))]) done++;
        return { done, total: dow + 1 };
      }

      function render() {
        const t = today();
        const doneToday = habits.filter(x => x.days[t]).length;
        let wd = 0, wt = 0;
        for (const hb of habits) { const r = weekRate(hb); wd += r.done; wt += r.total; }
        const R = 26, C = 2 * Math.PI * R, ratio = habits.length ? doneToday / habits.length : 0;
        q('.hb-summary').innerHTML = habits.length ? `
          <div class="card hb-sum-card">
            <svg viewBox="0 0 64 64" class="hb-ring"><circle cx="32" cy="32" r="${R}" class="bg"/><circle cx="32" cy="32" r="${R}" class="fg" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - ratio)}" transform="rotate(-90 32 32)"/>
              <text x="32" y="37">${doneToday}/${habits.length}</text></svg>
            <div><div class="hb-sum-t">${ratio === 1 ? '今日全勤！太棒了 🎉' : `今天还有 ${habits.length - doneToday} 个习惯待完成`}</div>
            <div class="set-sub">本周完成率 ${wt ? Math.round(wd / wt * 100) : 0}% · 全部完成可获得 5 小鱼干（每天一次）</div></div>
          </div>` : '';
        const list = q('.hb-list');
        list.innerHTML = habits.length ? '' : '<div class="card hb-empty">还没有习惯，点击右上角「新习惯」开始养成好习惯吧~</div>';
        for (const hb of habits) {
          const s = streaks(hb.days), w = weekRate(hb), on = !!hb.days[t];
          const card = h(`<div class="card hb-card" style="--hc:${hb.color}">
            <div class="hb-head">
              <span class="hb-icon">${esc(hb.icon)}</span>
              <div class="hb-info"><div class="hb-name-t"></div>
                <div class="set-sub">连续 <b>${s.cur}</b> 天 · 最长 <b>${s.best}</b> 天 · 本周 ${w.done}/${w.total}（${Math.round(w.done / w.total * 100)}%）· 累计 ${Object.keys(hb.days).length} 天</div></div>
              <button class="hb-edit" title="编辑"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16z"/></svg></button>
              <button class="hb-tick ${on ? 'on' : ''}">${on ? '✔ 已打卡' : '打卡'}</button>
            </div>
            <div class="hb-heat-wrap">${heatmap(hb)}</div>
          </div>`);
          card.querySelector('.hb-name-t').textContent = hb.name;
          card.querySelector('.hb-tick').onclick = () => toggle(hb, t);
          card.querySelector('.hb-edit').onclick = () => openEditor(hb);
          card.querySelectorAll('.hb-cell').forEach(r => r.addEventListener('click', () => toggle(hb, r.dataset.k)));
          list.appendChild(card);
        }
      }
      render();
    },
    unmount() {}
  });

  // =====================================================================
  // 计算器 (Windows standard mode style: immediate execution)
  // =====================================================================
  const round12 = n => (n === 0 ? 0 : Number(n.toPrecision(12)));
  function fmtNum(n) {
    if (!isFinite(n)) return '错误';
    const v = round12(n);
    if (v === 0) return '0';
    const a = Math.abs(v);
    if (a >= 1e16 || a < 1e-12) return v.toExponential(11).replace(/\.?0+e/, 'e');
    let s = v.toFixed(Math.max(0, 11 - Math.floor(Math.log10(a))));
    if (s.includes('.')) s = s.replace(/\.?0+$/, '');
    return s;
  }
  const group = s => {
    if (/e/.test(s) || s === '错误') return s;
    const neg = s.startsWith('-'), [i, f] = (neg ? s.slice(1) : s).split('.');
    return (neg ? '-' : '') + i.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (f !== undefined ? '.' + f : '');
  };

  let calcCleanup = null;
  Hub.register({
    id: 'calc', title: '计算器', group: 'tool', order: 8, icon: ICON.calc,
    mount(el, ctx) {
      let history = ctx.store.get('history', []);   // {expr, result}
      let memory = ctx.store.get('memory', null);    // number | null
      const S = {
        entry: '0',        // text of the current operand
        typing: true,      // user is typing into entry
        acc: null,         // left operand
        op: null,          // pending operator
        expr: '',          // top line
        last: null,        // {op, b} for repeated "="
        error: false,
        unaryLabel: null   // label of unary-transformed entry, shown in expr
      };

      el.innerHTML = `
        <div class="calc-root">
          <h2 class="page-title">计算器</h2>
          <div class="calc-wrap">
            <div class="card calc-main">
              <div class="calc-screen"><div class="calc-expr"></div><div class="calc-disp">0</div></div>
              <div class="calc-mem">
                <button data-k="MC">MC</button><button data-k="MR">MR</button><button data-k="M+">M+</button><button data-k="M-">M-</button><button data-k="MS">MS</button><span class="calc-mv"></span>
              </div>
              <div class="calc-keys">
                <button data-k="%" class="fn">%</button><button data-k="CE" class="fn">CE</button><button data-k="C" class="fn">C</button><button data-k="BS" class="fn">⌫</button>
                <button data-k="inv" class="fn">¹/ₓ</button><button data-k="sqr" class="fn">x²</button><button data-k="sqrt" class="fn">²√x</button><button data-k="÷" class="op">÷</button>
                <button data-k="7">7</button><button data-k="8">8</button><button data-k="9">9</button><button data-k="×" class="op">×</button>
                <button data-k="4">4</button><button data-k="5">5</button><button data-k="6">6</button><button data-k="-" class="op">−</button>
                <button data-k="1">1</button><button data-k="2">2</button><button data-k="3">3</button><button data-k="+" class="op">+</button>
                <button data-k="neg">±</button><button data-k="0">0</button><button data-k=".">.</button><button data-k="=" class="eq">=</button>
              </div>
            </div>
            <div class="card calc-side">
              <div class="calc-side-h"><span class="side-title">历史记录</span><button class="btn calc-clear-h" title="清空历史">清空</button></div>
              <div class="calc-hist"></div>
              <div class="set-sub calc-tip">键盘：数字 / + - * / / Enter / Esc(C) / Del(CE) / Backspace / % / R(1/x) / Q(x²) / @(√) / F9(±)</div>
            </div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      // full-precision value behind a computed result (display text is rounded to 12 digits)
      let val = null, valText = null;
      const cur = () => (val !== null && valText === S.entry ? val : Number(S.entry));
      const opSym = { '+': '+', '-': '−', '×': '×', '÷': '÷' };

      function apply(a, op, b) {
        switch (op) {
          case '+': return a + b;
          case '-': return a - b;
          case '×': return a * b;
          case '÷': if (b === 0) throw new Error(a === 0 ? '结果未定义' : '除数不能为零'); return a / b;
        }
        return b;
      }
      function setResult(v) {
        if (!isFinite(v)) throw new Error('溢出');
        S.entry = fmtNum(v);
        if (S.entry === '-0') S.entry = '0';
        val = S.entry === '0' ? 0 : v; valText = S.entry;
      }
      function fail(msg) {
        S.error = msg; S.acc = null; S.op = null; S.last = null; S.typing = true; S.entry = '0'; S.unaryLabel = null;
      }
      function reset() { val = null; Object.assign(S, { entry: '0', typing: true, acc: null, op: null, expr: '', last: null, error: false, unaryLabel: null }); }
      const operandLabel = () => S.unaryLabel || fmtNum(cur());

      function pushHistory(expr, result) {
        history.unshift({ expr, result });
        history = history.slice(0, 40);
        ctx.store.set('history', history);
        renderHistory();
      }

      function press(k) {
        if (S.error && !/^[0-9.]$|^C$|^CE$|^BS$/.test(k)) return;
        if (S.error) reset();
        try {
          if (/^[0-9]$/.test(k)) {
            if (!S.typing || S.unaryLabel) {
              if (S.expr.endsWith('=')) S.expr = '';
              S.entry = '0'; S.typing = true; S.unaryLabel = null;
            }
            if (S.entry.replace(/[-.]/g, '').length >= 16) return;
            S.entry = S.entry === '0' ? k : S.entry === '-0' ? '-' + k : S.entry + k;
          } else if (k === '.') {
            if (!S.typing || S.unaryLabel) { if (S.expr.endsWith('=')) S.expr = ''; S.entry = '0'; S.typing = true; S.unaryLabel = null; }
            if (!S.entry.includes('.')) S.entry += '.';
          } else if (k in opSym) {
            if (S.op && (S.typing || S.unaryLabel)) {
              const r = apply(S.acc, S.op, cur()); setResult(r);
            }
            if (!S.op || S.typing || S.unaryLabel || S.expr.endsWith('=')) S.acc = cur();
            S.op = k; S.typing = false; S.unaryLabel = null;
            S.expr = `${fmtNum(S.acc)} ${opSym[k]}`;
          } else if (k === '=') {
            let a, op, b;
            if (S.op) { a = S.acc; op = S.op; b = cur(); S.last = { op, b }; }
            else if (S.last && S.expr.endsWith('=')) { a = cur(); op = S.last.op; b = S.last.b; }
            else { const lbl = operandLabel(); S.expr = `${lbl} =`; S.typing = false; S.unaryLabel = null; return; }
            const bl = S.op ? operandLabel() : fmtNum(b);
            const expr = `${fmtNum(a)} ${opSym[op]} ${bl} =`;
            setResult(apply(a, op, b));
            S.expr = expr; S.acc = null; S.op = null; S.typing = false; S.unaryLabel = null;
            pushHistory(expr, S.entry);
          } else if (k === 'CE') {
            S.entry = '0'; S.typing = true; S.unaryLabel = null;
            if (S.expr.endsWith('=')) S.expr = '';
          } else if (k === 'C') {
            reset();
          } else if (k === 'BS') {
            if (S.typing && !S.unaryLabel) {
              S.entry = S.entry.slice(0, -1);
              if (S.entry === '' || S.entry === '-' || S.entry === '-0') S.entry = '0';
            } else if (S.expr.endsWith('=')) S.expr = '';
          } else if (k === 'neg') {
            if (S.entry === '0') return;
            if (S.typing && !S.unaryLabel) S.entry = S.entry.startsWith('-') ? S.entry.slice(1) : '-' + S.entry;
            else unary(v => -v, l => `negate(${l})`);
          } else if (k === 'inv') {
            if (cur() === 0) throw new Error('除数不能为零');
            unary(v => 1 / v, l => `1/(${l})`);
          } else if (k === 'sqr') {
            unary(v => v * v, l => `sqr(${l})`);
          } else if (k === 'sqrt') {
            if (cur() < 0) throw new Error('无效输入');
            unary(Math.sqrt, l => `√(${l})`);
          } else if (k === '%') {
            const v = cur();
            let r;
            if (S.op === '+' || S.op === '-') r = S.acc * v / 100;
            else if (S.op) r = v / 100;
            else r = 0;
            setResult(r);
            S.unaryLabel = fmtNum(r); S.typing = false;
            if (S.expr.endsWith('=')) S.expr = '';
            S.expr = S.op ? `${fmtNum(S.acc)} ${opSym[S.op]} ${S.unaryLabel}` : S.unaryLabel;
          } else if (k === 'MC') { memory = null; ctx.store.set('memory', memory); }
          else if (k === 'MR') { if (memory !== null) { S.entry = fmtNum(memory); S.typing = false; S.unaryLabel = S.entry; if (S.expr.endsWith('=')) S.expr = ''; } }
          else if (k === 'MS') { memory = round12(cur()); ctx.store.set('memory', memory); S.typing = false; }
          else if (k === 'M+' || k === 'M-') {
            memory = round12((memory || 0) + (k === 'M+' ? cur() : -cur()));
            ctx.store.set('memory', memory); S.typing = false;
          }
        } catch (err) {
          fail(err.message);
        }
        render();
      }

      function unary(fn, label) {
        const base = S.unaryLabel || fmtNum(cur());
        if (S.expr.endsWith('=')) S.expr = '';
        setResult(fn(cur()));
        S.unaryLabel = label(base);
        S.typing = false;
        S.expr = S.op ? `${fmtNum(S.acc)} ${opSym[S.op]} ${S.unaryLabel}` : S.unaryLabel;
      }

      function render() {
        const disp = q('.calc-disp');
        const text = S.error || group(S.entry);
        disp.textContent = text;
        disp.classList.toggle('err', !!S.error);
        disp.style.fontSize = `${text.length > 18 ? 22 : text.length > 14 ? 28 : text.length > 11 ? 34 : 42}px`;
        q('.calc-expr').textContent = S.expr || ' ';
        q('.calc-mv').textContent = memory !== null ? `M = ${group(fmtNum(memory))}` : '';
        el.querySelectorAll('.calc-mem [data-k=MC], .calc-mem [data-k=MR]').forEach(b => b.disabled = memory === null);
        el.querySelectorAll('.calc-keys button').forEach(b => {
          const k = b.dataset.k;
          b.disabled = !!S.error && !/^[0-9.]$|^C$|^CE$|^BS$/.test(k);
        });
      }

      function renderHistory() {
        const box = q('.calc-hist');
        if (!history.length) { box.innerHTML = '<div class="calc-empty">还没有历史记录</div>'; return; }
        box.innerHTML = '';
        for (const it of history) {
          const row = h('<button class="calc-hi"><div class="calc-hi-e"></div><div class="calc-hi-r"></div></button>');
          row.querySelector('.calc-hi-e').textContent = it.expr;
          row.querySelector('.calc-hi-r').textContent = group(it.result);
          row.onclick = () => { reset(); S.entry = it.result; S.typing = false; S.expr = it.expr; render(); };
          box.appendChild(row);
        }
      }

      el.querySelectorAll('.calc-root button[data-k]').forEach(b => b.onclick = () => { press(b.dataset.k); b.blur(); });
      q('.calc-clear-h').onclick = () => { history = []; ctx.store.set('history', history); renderHistory(); };

      const KEYMAP = { '+': '+', '-': '-', '*': '×', 'x': '×', '/': '÷', 'Enter': '=', '=': '=', 'Escape': 'C', 'Delete': 'CE',
        'Backspace': 'BS', '%': '%', 'r': 'inv', 'R': 'inv', 'q': 'sqr', 'Q': 'sqr', '@': 'sqrt', 'F9': 'neg', '.': '.', ',': '.' };
      function onKey(e) {
        if (!ctx.isActive() || isTyping(e)) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        let k = /^[0-9]$/.test(e.key) ? e.key : KEYMAP[e.key];
        if (!k) return;
        e.preventDefault();
        press(k);
        const btn = el.querySelector(`.calc-keys button[data-k="${CSS.escape(k)}"]`);
        if (btn) { btn.classList.add('press'); setTimeout(() => btn.classList.remove('press'), 110); }
      }
      window.addEventListener('keydown', onKey);
      calcCleanup = () => window.removeEventListener('keydown', onKey);

      render();
      renderHistory();
    },
    unmount() { if (calcCleanup) calcCleanup(); calcCleanup = null; }
  });

})();
