// Hub shell: sidebar navigation + module mounting. See MODULES.md for the module contract.
(function () {
  const api = window.api;
  // paint with the CML launcher's theme before any module renders, then follow it live
  PetTheme.init();
  const modules = [];
  let current = null;

  function makeStore(id) {
    const key = `mod:${id}`;
    let cache = api.store.get(key) || {};
    return {
      get(k, def) { return k in cache ? cache[k] : def; },
      set(k, v) { cache[k] = v; api.store.set(key, cache); }
    };
  }

  function toast(text) {
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = text;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2000);
  }

  function renderNav() {
    const nav = document.getElementById('sidebar');
    nav.innerHTML = '';
    const groups = [['main', ''], ['pet', '宠物'], ['tool', '工具'], ['game', '小游戏'], ['system', '其他']];
    for (const [g, label] of groups) {
      const items = modules.filter(m => (m.group || 'tool') === g).sort((a, b) => (a.order || 0) - (b.order || 0));
      if (!items.length) continue;
      if (label) {
        const h = document.createElement('div');
        h.className = 'nav-group';
        h.textContent = label;
        nav.appendChild(h);
      }
      for (const m of items) {
        const b = document.createElement('button');
        b.className = 'nav-item';
        b.dataset.id = m.id;
        b.innerHTML = `${m.icon || ''}<span></span>`;
        b.querySelector('span').textContent = m.title;
        b.title = m.title;   // the sidebar collapses to icons on narrow windows
        b.addEventListener('click', () => open(m.id));
        nav.appendChild(b);
      }
    }
  }

  // force: re-mount non-game pages so they show fresh data when the window is re-shown
  function open(id, force) {
    const m = modules.find(x => x.id === id) || modules[0];
    if (current && current.mod === m && !(force && m.group !== 'game')) return;
    if (current) {
      try { current.mod.unmount && current.mod.unmount(); } catch (e) { console.error(e); }
      current.el.remove();
    }
    const el = document.createElement('div');
    el.className = 'page';
    document.getElementById('content').appendChild(el);
    const entry = { mod: m, el };
    current = entry;
    const ctx = {
      store: makeStore(m.id),
      say: (text, mood = 'happy') => api.pet.say(text, mood, 6000),
      isActive: () => current === entry && document.hasFocus(),
      open,
      toast,
      reward: (coins, reason) => { api.care.reward(coins, reason); toast(`获得 ${coins} 小鱼干 🐟`); }
    };
    try { m.mount(el, ctx); } catch (e) { console.error(e); el.textContent = '加载失败：' + e.message; }
    document.querySelectorAll('.nav-item').forEach(b => b.classList.toggle('active', b.dataset.id === m.id));
    api.store.set('hub:last', m.id);
    if (api.debug) api.debug('page ' + m.id);
  }

  window.Hub = {
    register(mod) { modules.push(mod); },
    list: () => modules.slice(),
    open,
    toast,
    start() {
      window.addEventListener('error', e => api.debug && api.debug(`hub error: ${e.message} @${e.filename}:${e.lineno}`));
      renderNav();
      const q = new URLSearchParams(location.search).get('page');
      open(q && q !== 'home' ? q : 'home');
      api.hub.onOpen(page => open(page, true));
      document.querySelector('[data-act=min]').onclick = api.hub.minimize;
      document.querySelector('[data-act=max]').onclick = api.hub.toggleMax;
      document.querySelector('[data-act=close]').onclick = api.hub.close;
      const avatar = () => { document.getElementById('tb-avatar').src = api.petImage(api.settings.get().pet); };
      avatar();
      api.settings.onChange(avatar);
    }
  };
})();
