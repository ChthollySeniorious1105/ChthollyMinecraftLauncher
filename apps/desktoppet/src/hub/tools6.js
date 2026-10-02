// More tool pages: 快捷启动 / 节日日历
(function () {
  const api = window.api;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ICON = {
    launch: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M13 3 5 13h6l-1 8 8-10h-6z"/></svg>',
    cal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4" stroke-linecap="round"/><circle cx="12" cy="15" r="1.6" fill="currentColor"/></svg>'
  };
  const KIND_SVG = {
    folder: '<svg viewBox="0 0 48 48"><path d="M5 12a3 3 0 0 1 3-3h10l4 4h18a3 3 0 0 1 3 3v20a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3z" fill="#f2b33d"/><path d="M5 18h38v18a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3z" fill="#f7c948"/></svg>',
    url: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="18" fill="#6aa7e0"/><path d="M6 24h36M24 6c6 5 8 11 8 18s-2 13-8 18c-6-5-8-11-8-18s2-13 8-18z" fill="none" stroke="#fff" stroke-width="2.5"/></svg>',
    app: '<svg viewBox="0 0 48 48"><rect x="7" y="9" width="34" height="28" rx="4" fill="#9b8472"/><rect x="11" y="15" width="26" height="18" rx="2" fill="#fffaf2"/><circle cx="12" cy="12" r="1.5" fill="#fff"/><circle cx="17" cy="12" r="1.5" fill="#fff"/></svg>'
  };

  // ============ 快捷启动 ============
  Hub.register({
    id: 'launcher', title: '快捷启动', group: 'tool', order: 0.5, icon: ICON.launch,
    mount(el, ctx) {
      let items = ctx.store.get('items', []);
      let editing = false, dragFrom = -1;
      const save = () => ctx.store.set('items', items);
      el.innerHTML = `
        <h2 class="page-title">快捷启动 <span class="set-sub">常用程序、文件夹和网址，一键打开。全局快捷键 <b class="ln-key"></b> 可随时呼出菜单</span></h2>
        <div class="card ln-bar">
          <button class="btn" data-add="app">+ 添加程序 / 文件</button>
          <button class="btn" data-add="folder">+ 添加文件夹</button>
          <div class="ln-url"><input class="input" placeholder="网址，如 https://www.bilibili.com"><input class="input ln-uname" placeholder="名称（可选）"><button class="btn" data-add="url">+ 添加网址</button></div>
          <span class="ln-flex"></span>
          <button class="btn ln-edit">整理</button>
        </div>
        <div class="ln-grid"></div>
        <div class="card ln-hot">
          <div class="side-title">全局快捷键</div>
          <div class="set-row"><div><div>呼出 / 隐藏菜单窗口</div><div class="set-sub">在任何程序里按下都能打开桌宠菜单。点击右侧输入框后按下新的组合键</div></div>
          <input class="input ln-hk" readonly></div>
        </div>`;
      const grid = el.querySelector('.ln-grid');
      const hk = el.querySelector('.ln-hk');
      const showKey = () => {
        const k = api.settings.get().hotkey || '';
        hk.value = k || '未设置';
        el.querySelector('.ln-key').textContent = k || '（未设置）';
      };
      showKey();
      hk.onkeydown = e => {
        e.preventDefault();
        if (e.key === 'Escape') return hk.blur();
        if (e.key === 'Backspace' || e.key === 'Delete') { api.settings.update({ hotkey: '' }); return showKey(); }
        if (['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) return;
        const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift'].filter(Boolean);
        if (!mods.length) return ctx.toast('请同时按住 Ctrl / Alt / Shift');
        const key = e.key.length === 1 ? e.key.toUpperCase() : e.key;
        api.settings.update({ hotkey: [...mods, key].join('+') });
        showKey();
        hk.blur();
        ctx.toast('快捷键已设置');
      };

      async function render() {
        grid.innerHTML = '';
        grid.classList.toggle('editing', editing);
        if (!items.length) { grid.innerHTML = '<div class="todo-empty">还没有快捷方式，点上面的按钮添加吧~</div>'; return; }
        items.forEach((it, i) => {
          const b = document.createElement('div');
          b.className = 'ln-item';
          b.draggable = editing;
          b.dataset.i = i;
          b.innerHTML = `<div class="ln-ic">${KIND_SVG[it.kind] || KIND_SVG.app}</div><span></span>
            <button class="ln-del" title="删除">×</button>`;
          b.querySelector('span').textContent = it.name;
          b.title = it.target;
          grid.appendChild(b);
          if (it.kind !== 'url') api.launch.icon(it.target).then(url => { if (url) b.querySelector('.ln-ic').innerHTML = `<img src="${url}" alt="">`; });
        });
      }
      grid.onclick = async e => {
        const item = e.target.closest('.ln-item');
        if (!item) return;
        const i = Number(item.dataset.i);
        if (e.target.closest('.ln-del')) { items.splice(i, 1); save(); return render(); }
        if (editing) {
          const name = prompt('名称', items[i].name);
          if (name && name.trim()) { items[i].name = name.trim(); save(); render(); }
          return;
        }
        item.classList.add('ln-pop');
        setTimeout(() => item.classList.remove('ln-pop'), 300);
        const r = await api.launch.open(items[i]);
        if (!r.ok) ctx.toast(r.msg || '打开失败');
        else api.pet.say(`帮你打开「${items[i].name}」啦~`, 'happy', 2500);
      };
      grid.ondragstart = e => { const it = e.target.closest('.ln-item'); if (it) dragFrom = Number(it.dataset.i); };
      grid.ondragover = e => { if (editing) e.preventDefault(); };
      grid.ondrop = e => {
        e.preventDefault();
        const it = e.target.closest('.ln-item');
        if (!it || dragFrom < 0) return;
        const to = Number(it.dataset.i);
        const [m] = items.splice(dragFrom, 1);
        items.splice(to, 0, m);
        dragFrom = -1;
        save(); render();
      };
      el.querySelector('.ln-bar').onclick = async e => {
        const b = e.target.closest('button');
        if (!b) return;
        if (b.classList.contains('ln-edit')) { editing = !editing; b.textContent = editing ? '完成' : '整理'; b.classList.toggle('primary', editing); if (editing) ctx.toast('拖动排序，点击改名，× 删除'); return render(); }
        const kind = b.dataset.add;
        if (kind === 'url') {
          const inp = el.querySelector('.ln-url .input');
          let url = inp.value.trim();
          if (!url) return ctx.toast('请输入网址');
          if (!/^https?:\/\//i.test(url)) url = 'https://' + url;
          let name = el.querySelector('.ln-uname').value.trim();
          if (!name) { try { name = new URL(url).hostname.replace(/^www\./, ''); } catch { return ctx.toast('网址格式不正确'); } }
          items.push({ id: Date.now(), name, kind: 'url', target: url });
          inp.value = ''; el.querySelector('.ln-uname').value = '';
        } else {
          const r = await api.launch.pick(kind);
          if (!r) return;
          items.push({ id: Date.now(), name: r.name, kind, target: r.target });
        }
        save(); render();
      };
      render();
    },
    unmount() {}
  });

  // ============ 节日日历 ============
  const { festivalsOn, lunarOf, LUNAR_MONTH, LUNAR_DAY } = window.PetFestivals;

  Hub.register({
    id: 'calendar', title: '节日日历', group: 'tool', order: 9.5, icon: ICON.cal,
    mount(el) {
      const now = new Date();
      let y = now.getFullYear(), mo = now.getMonth();
      el.innerHTML = `<h2 class="page-title">节日日历</h2><div class="cal-wrap"><div class="card cal-card"></div><div class="card cal-up"></div></div>`;
      const card = el.querySelector('.cal-card');
      function render() {
        const first = new Date(y, mo, 1), start = new Date(y, mo, 1 - ((first.getDay() + 6) % 7));
        let cells = '';
        for (let i = 0; i < 42; i++) {
          const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
          const fest = festivalsOn(d);
          const l = lunarOf(d);
          const sub = fest[0] || (l ? (l.day === 1 ? (l.leap ? '闰' : '') + LUNAR_MONTH[l.month - 1] + '月' : LUNAR_DAY[l.day - 1]) : '');
          const cls = ['cal-d', d.getMonth() !== mo ? 'out' : '', d.toDateString() === now.toDateString() ? 'today' : '', fest.length ? 'fest' : '', d.getDay() % 6 === 0 ? 'we' : ''].join(' ');
          cells += `<div class="${cls}" title="${esc(fest.join('、'))}"><b>${d.getDate()}</b><span>${esc(sub)}</span></div>`;
        }
        card.innerHTML = `
          <div class="cal-head"><button class="btn" data-m="-1">‹</button><b>${y} 年 ${mo + 1} 月</b><button class="btn" data-m="1">›</button><button class="btn" data-m="0">今天</button></div>
          <div class="cal-grid">${['一', '二', '三', '四', '五', '六', '日'].map(w => `<div class="cal-w">${w}</div>`).join('')}${cells}</div>`;
        card.querySelectorAll('[data-m]').forEach(b => b.onclick = () => {
          const k = Number(b.dataset.m);
          if (!k) { y = now.getFullYear(); mo = now.getMonth(); }
          else { mo += k; if (mo < 0) { mo = 11; y--; } if (mo > 11) { mo = 0; y++; } }
          render();
        });
      }
      // upcoming festivals in the next ~120 days
      const up = [];
      for (let i = 0; i < 120 && up.length < 10; i++) {
        const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
        for (const f of festivalsOn(d)) up.push([d, f, i]);
      }
      el.querySelector('.cal-up').innerHTML = `<div class="side-title">即将到来</div>` + up.map(([d, f, i]) =>
        `<div class="cal-u"><b>${esc(f)}</b><span>${d.getMonth() + 1}月${d.getDate()}日</span><em>${i === 0 ? '今天' : `${i} 天后`}</em></div>`).join('');
      render();
    },
    unmount() {}
  });
})();
