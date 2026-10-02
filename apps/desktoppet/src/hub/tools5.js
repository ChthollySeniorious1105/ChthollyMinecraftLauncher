// Pet-related extra pages: 衣橱 / 成就 / 剪贴板历史 (+ backup section injected into 设置)
(function () {
  const api = window.api;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const FISH = '<svg class="fish-ic" viewBox="0 0 40 40"><path d="M5 20c5-8 18-9 25 0-7 9-20 8-25 0z" fill="#d9a066"/><path d="M29 20l7-6v12z" fill="#c98f4a"/><circle cx="11" cy="18.5" r="1.6" fill="#4a3426"/></svg>';
  const ICON = {
    wardrobe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M9 3.5 4 6l1.5 5L7 10.5V20h10v-9.5l1.5.5L20 6l-5-2.5c-.5 1.5-1.7 2.5-3 2.5s-2.5-1-3-2.5z"/></svg>',
    ach: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M7 6H4v2a3 3 0 0 0 3 3M17 6h3v2a3 3 0 0 1-3 3M12 14v3M8 20h8l-1-3H9z"/></svg>',
    clip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="5" y="4.5" width="14" height="16.5" rx="2"/><path d="M9 4.5V3h6v1.5M9 10h6M9 14h6M9 18h3" stroke-linecap="round"/></svg>'
  };

  // ============ 衣橱 ============
  let wardOff = null;
  Hub.register({
    id: 'wardrobe', title: '衣橱', group: 'pet', order: 1.5, icon: ICON.wardrobe,
    mount(el, ctx) {
      el.innerHTML = `
        <h2 class="page-title">衣橱 <span class="set-sub">装扮会显示在桌面宠物身上，每个部位可以穿一件</span></h2>
        <div class="wd-wrap">
          <div class="card wd-preview"><div class="wd-stage"><img alt=""><div class="wd-wear"></div></div>
            <div class="wd-coins">${FISH}<b></b></div>
            <button class="btn wd-clear">全部脱下</button></div>
          <div class="wd-list"></div>
        </div>`;
      const q = s => el.querySelector(s);
      function render(c) {
        const pet = api.settings.get().pet;
        q('.wd-stage img').src = api.petImage(pet);
        q('.wd-coins b').textContent = c.coins;
        const a = (window.PET_ANCHORS || {})[pet];
        const wear = q('.wd-wear');
        wear.innerHTML = '';
        for (const id of Object.values(c.equipped || {})) {
          const it = Wardrobe.ITEMS[id];
          if (!it || !a) continue;
          const p = Wardrobe.place(it, a);
          const d = document.createElement('div');
          d.innerHTML = it.svg;
          const svg = d.firstElementChild;
          Object.assign(svg.style, { left: `${p.left * 100}%`, top: `${p.top * 100}%`, width: `${p.width * 100}%`, height: `${p.height * 100}%`, transform: `rotate(${p.rot || 0}deg)` });
          wear.appendChild(svg);
        }
        const list = q('.wd-list');
        list.innerHTML = '';
        for (const [slot, label] of Object.entries(Wardrobe.SLOTS)) {
          const sec = document.createElement('div');
          sec.className = 'card';
          sec.innerHTML = `<div class="side-title">${label}</div><div class="wd-grid"></div>`;
          for (const [id, it] of Object.entries(Wardrobe.ITEMS).filter(([, i]) => i.slot === slot)) {
            const owned = c.owned.includes(id), on = c.equipped[slot] === id;
            const b = document.createElement('button');
            b.className = `wd-item ${owned ? 'owned' : ''} ${on ? 'on' : ''} ${!owned && c.coins < it.price ? 'poor' : ''}`;
            b.innerHTML = `<div class="wd-ic">${it.svg}</div><span>${it.name}</span><em>${on ? '穿戴中' : owned ? '已拥有' : `${FISH}${it.price}`}</em>`;
            b.onclick = () => {
              const r = api.care.action(owned ? 'wear' : 'wear-buy', id);
              if (!r.ok && r.msg) ctx.toast(r.msg);
              if (r.state) render(r.state);
            };
            sec.querySelector('.wd-grid').appendChild(b);
          }
          list.appendChild(sec);
        }
      }
      q('.wd-clear').onclick = () => {
        const c = api.care.get();
        for (const id of Object.values(c.equipped)) api.care.action('wear', id);
        render(api.care.get());
      };
      render(api.care.get());
      wardOff = api.care.onChange(render);
    },
    unmount() { wardOff && wardOff(); wardOff = null; }
  });

  // ============ 成就 ============
  let achOff = null;
  Hub.register({
    id: 'achievements', title: '成就', group: 'pet', order: 3, icon: ICON.ach,
    mount(el) {
      const render = () => {
        const { list, stats } = api.ach.get();
        const done = list.filter(a => a.at).length;
        el.innerHTML = `
          <h2 class="page-title">成就 <span class="set-sub">已解锁 ${done} / ${list.length}</span></h2>
          <div class="card ach-sum">
            <div class="ach-prog"><div style="width:${done / list.length * 100}%"></div></div>
            <div class="ach-stats">
              <div><b>${stats.wins}</b><span>游戏胜利</span></div>
              <div><b>${Object.keys(stats.gameKinds || {}).length}</b><span>赢过的游戏种类</span></div>
              <div><b>${stats.pomos}</b><span>番茄钟</span></div>
              <div><b>${stats.feeds}</b><span>喂食次数</span></div>
              <div><b>${stats.pets}</b><span>摸摸次数</span></div>
            </div>
          </div>
          <div class="ach-grid">${list.sort((a, b) => !!b.at - !!a.at).map(a => `
            <div class="ach-card ${a.at ? 'got' : ''}">
              <div class="ach-ic">${a.icon}</div>
              <div><b>${esc(a.name)}</b><div class="set-sub">${esc(a.desc)}</div>
              <div class="ach-meta">${a.at ? `${new Date(a.at).toLocaleDateString('zh-CN')} 解锁` : `奖励 ${a.coins} 小鱼干`}</div></div>
            </div>`).join('')}</div>`;
      };
      render();
      achOff = api.ach.onUnlock(render);
    },
    unmount() { achOff && achOff(); achOff = null; }
  });

  // ============ 剪贴板历史 ============
  let clipOff = null, clipKey = null;
  Hub.register({
    id: 'clipboard', title: '剪贴板', group: 'tool', order: 5.5, icon: ICON.clip,
    mount(el, ctx) {
      let filter = '';
      el.innerHTML = `
        <h2 class="page-title">剪贴板历史 <span class="set-sub">自动记录复制过的文字（最多 100 条，固定的不会被挤掉）</span></h2>
        <div class="card cb-card">
          <div class="cb-bar">
            <input class="input cb-search" placeholder="搜索…">
            <label class="cb-toggle">记录剪贴板 <label class="switch"><input type="checkbox" class="cb-on"><span></span></label></label>
            <button class="btn cb-clear">清空未固定</button>
          </div>
          <ul class="cb-list"></ul>
        </div>`;
      const q = s => el.querySelector(s);
      const on = q('.cb-on');
      on.checked = api.settings.get().clipboard !== false;
      on.onchange = () => api.settings.update({ clipboard: on.checked });
      function render(list) {
        const ul = q('.cb-list');
        const shown = list.filter(c => !filter || c.text.toLowerCase().includes(filter));
        shown.sort((a, b) => !!b.pinned - !!a.pinned);
        ul.innerHTML = shown.length ? '' : `<li class="todo-empty">${list.length ? '没有匹配的内容' : '复制一些文字试试吧~'}</li>`;
        shown.slice(0, 200).forEach((c, idx) => {
          const li = document.createElement('li');
          li.className = `cb-item ${c.pinned ? 'pinned' : ''}`;
          li.innerHTML = `<span class="cb-idx">${idx < 9 ? idx + 1 : ''}</span><div class="cb-text"></div>
            <span class="cb-time">${new Date(c.t).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
            <button class="cb-pin" title="${c.pinned ? '取消固定' : '固定'}">${c.pinned ? '★' : '☆'}</button>
            <button class="todo-del" title="删除"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>`;
          li.querySelector('.cb-text').textContent = c.text.length > 400 ? c.text.slice(0, 400) + '…' : c.text;
          li.onclick = e => {
            if (e.target.closest('button')) return;
            api.clips.copy(c.text);
            ctx.toast('已复制');
          };
          li.querySelector('.cb-pin').onclick = () => { c.pinned = !c.pinned; api.clips.set(list); };
          li.querySelector('.todo-del').onclick = () => api.clips.set(list.filter(x => x !== c));
          ul.appendChild(li);
        });
        clipKey = e => {
          if (!ctx.isActive() || e.target.tagName === 'INPUT' || !/^[1-9]$/.test(e.key)) return;
          const c = shown[Number(e.key) - 1];
          if (c) { api.clips.copy(c.text); ctx.toast(`已复制第 ${e.key} 条`); }
        };
      }
      q('.cb-search').oninput = e => { filter = e.target.value.trim().toLowerCase(); render(api.clips.get()); };
      q('.cb-clear').onclick = () => api.clips.set(api.clips.get().filter(c => c.pinned));
      const onKey = e => clipKey && clipKey(e);
      window.addEventListener('keydown', onKey);
      render(api.clips.get());
      const off = api.clips.onChange(render);
      clipOff = () => { off(); window.removeEventListener('keydown', onKey); };
    },
    unmount() { clipOff && clipOff(); clipOff = null; clipKey = null; }
  });

  // ============ backup section inside 设置 ============
  // wrap the settings page's mount to append a backup card without editing tools.js
  const mods = Hub.list();
  const settingsMod = mods.find(m => m.id === 'settings');
  if (settingsMod) {
    const orig = settingsMod.mount;
    settingsMod.mount = function (el, ctx) {
      orig.call(this, el, ctx);
      const s = api.settings.get();
      const card = document.createElement('div');
      card.className = 'card set-card';
      card.innerHTML = `
        <div class="side-title">更多</div>
        <div class="set-row"><div><div>散步模式</div><div class="set-sub">宠物会沿着屏幕底部走来走去</div></div>
          <label class="switch"><input type="checkbox" data-walk ${s.walk ? 'checked' : ''}><span></span></label></div>
        <div class="set-row"><div><div>数据备份</div><div class="set-sub">导出 / 导入全部数据（宠物、游戏记录、待办、记账等），导入后自动重启</div></div>
          <div style="display:flex;gap:8px"><button class="btn" data-exp>导出备份</button><button class="btn" data-imp>导入备份</button></div></div>`;
      const about = [...el.querySelectorAll('.set-card')].pop();
      el.insertBefore(card, about);
      card.querySelector('[data-walk]').onchange = e => api.settings.update({ walk: e.target.checked });
      card.querySelector('[data-exp]').onclick = async () => {
        const r = await api.backup.exportData();
        if (r.ok) ctx.toast('已导出到 ' + r.path);
      };
      card.querySelector('[data-imp]').onclick = async () => {
        if (!confirm('导入会覆盖当前所有数据，确定继续吗？')) return;
        const r = await api.backup.importData();
        if (!r.ok && r.msg) ctx.toast(r.msg);
      };
    };
  }
})();
