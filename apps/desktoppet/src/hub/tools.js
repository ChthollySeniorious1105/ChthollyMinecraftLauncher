// Built-in tool pages: 首页 / 番茄钟 / 待办 / 便签 / 换宠物 / 设置
(function () {
  const api = window.api;
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const petName = f => ({
    fox: '小狐狸', cat: '小猫咪', corgi: '柯基', rabbit: '小兔子', bear: '小熊', penguin: '企鹅', duck: '小黄鸭',
    hedgehog: '刺猬', owl: '猫头鹰', deer: '小鹿', panda: '熊猫', hamster: '仓鼠', seal: '海豹', otter: '水獭',
    frog: '青蛙', raccoon: '浣熊', shiba: '柴犬', chick: '小鸡', turtle: '乌龟', squirrel: '松鼠'
  }[f.replace(/^\d+-|\.png$/g, '')] || f);

  const ICON = {
    home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>',
    pomodoro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="13.5" r="7.5"/><path d="M12 6c-1-2-3-2.5-4.5-2M12 6c1-2 3-2.5 4.5-2M12 10v3.5l2.5 1.5" stroke-linecap="round"/></svg>',
    todo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3.5" width="16" height="17" rx="2.5"/><path d="M8 9l1.5 1.5L12 8M8 15l1.5 1.5L12 14M14.5 9.5H17M14.5 15.5H17"/></svg>',
    notes: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M5 3.5h14v11l-6 6H5z"/><path d="M13 20.5v-6h6M8.5 8h7M8.5 11.5h4"/></svg>',
    pets: '<svg viewBox="0 0 24 24" fill="currentColor"><ellipse cx="12" cy="16" rx="5" ry="4.2"/><ellipse cx="5.5" cy="10.5" rx="2.2" ry="2.8"/><ellipse cx="18.5" cy="10.5" rx="2.2" ry="2.8"/><ellipse cx="9" cy="5.8" rx="2.1" ry="2.7"/><ellipse cx="15" cy="5.8" rx="2.1" ry="2.7"/></svg>',
    settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1" stroke-linecap="round"/></svg>'
  };

  // ============ 首页 ============
  let homeKey = null;
  Hub.register({
    id: 'home', title: '首页', group: 'main', icon: ICON.home,
    mount(el, ctx) {
      const s = api.settings.get();
      const p = api.pomo.get();
      const todos = (api.store.get('mod:todo') || {}).items || [];
      const left = todos.filter(t => !t.done).length;
      const hr = new Date().getHours();
      const hello = hr < 6 ? "夜深了" : hr < 11 ? "早上好" : hr < 14 ? "中午好" : hr < 18 ? '下午好' : '晚上好';
      el.innerHTML = `
        <div class="home-hero card">
          <img class="home-pet" src="${api.petImage(s.pet)}" alt="">
          <div>
            <div class="home-hello">${hello}！我是你的${esc(petName(s.pet))}</div>
            <div class="home-date">${new Date().toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' })}</div>
            <div class="home-stats">
              <div><b>${p.stats[p.today] || 0}</b><span>今日番茄</span></div>
              <div><b>${left}</b><span>待办未完成</span></div>
              <div><b>${Object.values(p.stats).reduce((a, b) => a + b, 0)}</b><span>累计番茄</span></div>
              <div><b>Lv.${api.care.get().level}</b><span>宠物等级</span></div>
              <div><b>${api.care.get().coins}</b><span>小鱼干</span></div>
            </div>
          </div>
        </div>
        <div class="home-find">
          <input class="input home-search" placeholder="搜索功能或游戏…（按 / 快速聚焦）">
          <div class="home-cats"><button data-c="all" class="on">全部</button><button data-c="pet">宠物</button><button data-c="tool">工具</button><button data-c="game">小游戏</button></div>
        </div>
        <div class="home-grid"></div>`;
      const grid = el.querySelector('.home-grid');
      const tiles = [
        ['care', '照顾宠物', '喂食 / 商店 / 签到'], ['adventure', '外出探险', '每日任务 / 纪念品'], ['fishing', '钓鱼', '图鉴 16 种鱼'], ['garden', '宠物花园', '种菜 / 金色作物'], ['gacha', '扭蛋机', '收集 24 款手办'], ['catch', '接食物', '接住美食躲炸弹'], ['pomodoro', '番茄钟', '专注 25 分钟'], ['todo', '待办清单', '今天要做什么'],
        ['alarms', '闹钟 / 倒计时', '到点提醒你'], ['noise', '白噪音', '雨声 / 海浪 / 篝火'], ['wheel', '帮我决定', '选择困难救星'],
        ['minesweeper', '扫雷', '经典 Windows 扫雷'], ['solitaire', '纸牌接龙', '经典 Windows 纸牌'], ['tetris', '俄罗斯方块', '消除方块'],
        ['g2048', '2048', '合成 2048'], ['sudoku', '数独', '四种难度'], ['gomoku', '五子棋', '挑战电脑'],
        ['memory', '翻牌配对', '考验记忆力'], ['snake', '贪吃蛇', '越吃越长'], ['notes', '便签', '随手记一笔'],
        ['spider', '蜘蛛纸牌', '经典 Windows 蜘蛛'], ['freecell', '空当接龙', '经典 Windows 空当'], ['lianliankan', '连连看', '宠物连连看'],
        ['breakout', '打砖块', '7 个关卡'], ['sokoban', '推箱子', '25 个关卡'], ['ledger', '记账本', '收支 / 预算'],
        ['habits', '习惯打卡', '坚持每一天'], ['calc', '计算器', 'Windows 风格'], ['sysmon', '系统监视', 'CPU / 内存'],
        ['bongo', '键鼠映射', 'BongoCat 看板'], ['wardrobe', '衣橱', '给宠物换装'], ['achievements', '成就', '35 个成就'], ['clipboard', '剪贴板', '复制历史'],
        ['hearts', '红心大战', '经典 Windows 红心'], ['mahjong', '麻将接龙', '经典麻将消除'], ['xiangqi', '中国象棋', '挑战电脑'],
        ['reversi', '黑白棋', '挑战电脑'], ['riichi', '日本麻将', '三麻 / 四麻 · 牌谱'], ['chess', '国际象棋', '挑战电脑'], ['pinball', '弹珠台', '经典弹珠'], ['nonogram', '数织', '宠物像素画'], ['launcher', '快捷启动', '一键打开常用'], ['calendar', '节日日历', '农历 / 节日'], ['huarong', '数字华容道', '滑块拼数字'], ['whack', '打地鼠', '60 秒挑战'],
        ['flappy', '飞翔小鸟', '穿过水管'], ['days', '倒数日', '纪念日提醒'], ['units', '单位换算', '长度 / 温度 …'],
        ['passgen', '密码生成器', '安全随机密码'],
        ['match3', '宠物消消乐', '三消 + 连锁'], ['connect4', '四子棋', '挑战电脑'],
        ['typing', '打字雨', '练习打字速度'], ['point24', '24 点', '加减乘除凑 24']
      ];
      const groupOf = id => { const m = Hub.list().find(x => x.id === id); return m ? m.group : 'tool'; };
      for (const [id, title, sub] of tiles) {
        const nav = document.querySelector(`.nav-item[data-id="${id}"] svg`);
        if (!nav) continue; // module not loaded
        const t = h(`<button class="home-tile"><div class="ht-icon">${nav.outerHTML}</div><div><div class="ht-title">${title}</div><div class="ht-sub">${sub}</div></div></button>`);
        t.dataset.text = (title + sub + id).toLowerCase();
        t.dataset.group = groupOf(id);
        t.onclick = () => ctx.open(id);
        grid.appendChild(t);
      }
      let cat = 'all';
      const search = el.querySelector('.home-search');
      const apply = () => {
        const qv = search.value.trim().toLowerCase();
        let shown = 0;
        grid.querySelectorAll('.home-tile').forEach(t => {
          const ok = (cat === 'all' || t.dataset.group === cat) && (!qv || t.dataset.text.includes(qv));
          t.style.display = ok ? '' : 'none';
          if (ok) shown++;
        });
        let empty = grid.querySelector('.home-none');
        if (!shown && !empty) { empty = h('<div class="home-none">没有找到相关内容</div>'); grid.appendChild(empty); }
        if (shown && empty) empty.remove();
      };
      search.oninput = apply;
      search.onkeydown = e => {
        if (e.key === 'Enter') { const first = [...grid.querySelectorAll('.home-tile')].find(t => t.style.display !== 'none'); if (first) first.click(); }
        if (e.key === 'Escape') { search.value = ''; apply(); }
      };
      el.querySelectorAll('.home-cats button').forEach(b => b.onclick = () => {
        cat = b.dataset.c;
        el.querySelectorAll('.home-cats button').forEach(x => x.classList.toggle('on', x === b));
        apply();
      });
      homeKey = e => {
        if (e.key === '/' && document.activeElement !== search && ctx.isActive()) { e.preventDefault(); search.focus(); }
      };
      window.addEventListener('keydown', homeKey);
    },
    unmount() { if (homeKey) window.removeEventListener('keydown', homeKey); homeKey = null; }
  });

  // ============ 番茄钟 ============
  let pomoOff = null;
  Hub.register({
    id: 'pomodoro', title: '番茄钟', group: 'tool', order: 0, icon: ICON.pomodoro,
    mount(el) {
      const R = 110, C = 2 * Math.PI * R;
      el.innerHTML = `
        <h2 class="page-title">番茄钟</h2>
        <div class="pomo-wrap">
          <div class="card pomo-main">
            <div class="pomo-modes">
              <button data-m="work">专注</button><button data-m="short">短休息</button><button data-m="long">长休息</button>
            </div>
            <svg class="pomo-ring" viewBox="0 0 260 260">
              <circle cx="130" cy="130" r="${R}" class="ring-bg"/>
              <circle cx="130" cy="130" r="${R}" class="ring-fg" stroke-dasharray="${C}" transform="rotate(-90 130 130)"/>
              <g class="tomato" transform="translate(130 64)">
                <circle r="13" fill="#e8553a"/><path d="M0-12c-3-4-7-4-9-3 2 .5 4 2 5 3.5-3-.5-5.5.5-6.5 2 3-.4 6 .2 8.5 2 1-2 4.5-3.2 8.5-2-1.2-2-3.5-2.8-6-2.5 1.4-1.6 3-2.3 5.4-2.5-2.4-1.3-5.6-.8-6.4 2.5z" fill="#5a9c3a"/>
              </g>
              <text x="130" y="145" class="pomo-time">25:00</text>
              <text x="130" y="178" class="pomo-label">专注中</text>
            </svg>
            <div class="pomo-ctrl">
              <button class="btn" data-a="reset" title="重置"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 12a8 8 0 1 0 2.4-5.7M4 4v4h4"/></svg></button>
              <button class="btn primary big" data-a="toggle">开始</button>
              <button class="btn" data-a="skip" title="跳过"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M5 5l9 7-9 7zM16 5h3v14h-3z"/></svg></button>
            </div>
            <div class="pomo-round"></div>
          </div>
          <div class="pomo-side">
            <div class="card">
              <div class="side-title">时长设置（分钟）</div>
              <label class="pomo-cfg">专注 <input class="input" type="number" min="1" max="180" data-k="work"></label>
              <label class="pomo-cfg">短休息 <input class="input" type="number" min="1" max="60" data-k="short"></label>
              <label class="pomo-cfg">长休息 <input class="input" type="number" min="1" max="90" data-k="long"></label>
              <label class="pomo-cfg">长休息间隔 <input class="input" type="number" min="2" max="10" data-k="longEvery"></label>
              <label class="pomo-cfg">自动开始下一段 <label class="switch"><input type="checkbox" data-k="autoStart"><span></span></label></label>
            </div>
            <div class="card">
              <div class="side-title">近 7 天</div>
              <svg class="pomo-chart" viewBox="0 0 280 130"></svg>
            </div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      const fg = q('.ring-fg');
      const LABEL = { work: '专注中', short: '短休息', long: '长休息' };
      let state = api.pomo.get();
      const fmt = ms => { const s = Math.ceil(ms / 1000); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };

      function render(p) {
        state = p;
        q('.pomo-time').textContent = fmt(p.remaining);
        q('.pomo-label').textContent = p.running ? LABEL[p.mode] : (p.remaining < p.total ? '已暂停' : LABEL[p.mode]);
        fg.style.strokeDashoffset = C * (1 - p.remaining / p.total);
        el.querySelector('.pomo-main').dataset.mode = p.mode;
        el.querySelectorAll('.pomo-modes button').forEach(b => b.classList.toggle('on', b.dataset.m === p.mode));
        q('[data-a=toggle]').textContent = p.running ? '暂停' : (p.remaining < p.total ? '继续' : '开始');
        q('.pomo-round').textContent = `今日已完成 ${p.stats[p.today] || 0} 个番茄 · 本轮第 ${p.round % p.cfg.longEvery + 1}/${p.cfg.longEvery} 个`;
        for (const inp of el.querySelectorAll('[data-k]')) {
          if (document.activeElement === inp) continue;
          if (inp.type === 'checkbox') inp.checked = !!p.cfg[inp.dataset.k]; else inp.value = p.cfg[inp.dataset.k];
        }
        renderChart(p);
      }
      function renderChart(p) {
        const svg = q('.pomo-chart');
        const days = [];
        for (let i = 6; i >= 0; i--) {
          const d = new Date(Date.now() - i * 864e5);
          const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
          days.push({ label: i === 0 ? '今天' : `${d.getMonth() + 1}/${d.getDate()}`, v: p.stats[key] || 0 });
        }
        const max = Math.max(4, ...days.map(d => d.v));
        svg.innerHTML = days.map((d, i) => {
          const x = 12 + i * 38, bh = d.v / max * 88, y = 100 - bh;
          return `<rect x="${x}" y="${y}" width="24" height="${Math.max(bh, 2)}" rx="5" fill="${i === 6 ? '#e8793a' : '#f2c9a8'}"/>
            ${d.v ? `<text x="${x + 12}" y="${y - 4}" class="bar-v">${d.v}</text>` : ''}
            <text x="${x + 12}" y="120" class="bar-l">${d.label}</text>`;
        }).join('');
      }

      el.querySelectorAll('.pomo-modes button').forEach(b => b.onclick = () => api.pomo.mode(b.dataset.m));
      q('[data-a=toggle]').onclick = () => state.running ? api.pomo.pause() : api.pomo.start();
      q('[data-a=reset]').onclick = () => api.pomo.reset();
      q('[data-a=skip]').onclick = () => api.pomo.skip();
      for (const inp of el.querySelectorAll('[data-k]')) {
        inp.onchange = () => {
          const k = inp.dataset.k;
          let v = inp.type === 'checkbox' ? inp.checked : Math.round(Number(inp.value));
          if (inp.type !== 'checkbox') v = Math.min(Number(inp.max), Math.max(Number(inp.min), v || Number(inp.min)));
          api.pomo.cfg({ [k]: v });
        };
      }
      render(state);
      pomoOff = api.pomo.onChange(render);
    },
    unmount() { pomoOff && pomoOff(); pomoOff = null; }
  });

  // ============ 待办 ============
  Hub.register({
    id: 'todo', title: '待办清单', group: 'tool', order: 1, icon: ICON.todo,
    mount(el, ctx) {
      let items = ctx.store.get('items', []);
      let filter = 'all';
      el.innerHTML = `
        <h2 class="page-title">待办清单</h2>
        <div class="card todo-card">
          <form class="todo-add">
            <input class="input" placeholder="添加一个待办，回车确认…" maxlength="200">
            <select class="input todo-pri"><option value="0">普通</option><option value="1">重要</option><option value="2">紧急</option></select>
            <button class="btn primary" type="submit">添加</button>
          </form>
          <div class="todo-bar">
            <div class="todo-filters"><button data-f="all">全部</button><button data-f="open">未完成</button><button data-f="done">已完成</button></div>
            <span class="todo-count"></span>
            <button class="btn todo-clear">清除已完成</button>
          </div>
          <div class="todo-progress"><div></div></div>
          <ul class="todo-list"></ul>
        </div>`;
      const q = s => el.querySelector(s);
      const save = () => ctx.store.set('items', items);
      const PRI = ['', '重要', '紧急'];
      function render() {
        const list = q('.todo-list');
        const shown = items.filter(t => filter === 'all' || (filter === 'done') === t.done)
          .sort((a, b) => a.done - b.done || b.pri - a.pri || a.created - b.created);
        list.innerHTML = shown.length ? '' : `<li class="todo-empty">${filter === 'done' ? '还没有完成的事项' : '暂无待办，享受一下空闲时光吧~'}</li>`;
        for (const t of shown) {
          const li = h(`<li class="todo-item ${t.done ? 'done' : ''} pri${t.pri}">
            <button class="todo-check"><svg viewBox="0 0 20 20"><path d="M5 10.5l3.2 3L15 7" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
            <span class="todo-text"></span>${t.pri ? `<em>${PRI[t.pri]}</em>` : ''}
            <button class="todo-del" title="删除"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></li>`);
          li.querySelector('.todo-text').textContent = t.text;
          li.querySelector('.todo-check').onclick = () => {
            t.done = !t.done; save(); render();
            if (t.done) {
              const left = items.filter(x => !x.done).length;
              ctx.say(left ? `完成了「${t.text.slice(0, 12)}」！还剩 ${left} 项~` : '全部待办完成啦！太棒了 🎉');
            }
          };
          li.querySelector('.todo-text').ondblclick = e => {
            const span = e.target;
            span.contentEditable = 'true'; span.focus();
            const done = () => { span.contentEditable = 'false'; t.text = span.textContent.trim() || t.text; save(); render(); };
            span.onblur = done;
            span.onkeydown = ev => { if (ev.key === 'Enter') { ev.preventDefault(); span.blur(); } };
          };
          li.querySelector('.todo-del').onclick = () => { items = items.filter(x => x !== t); save(); render(); };
          list.appendChild(li);
        }
        const done = items.filter(t => t.done).length;
        q('.todo-count').textContent = `${done}/${items.length} 已完成`;
        q('.todo-progress div').style.width = items.length ? `${done / items.length * 100}%` : '0';
        el.querySelectorAll('.todo-filters button').forEach(b => b.classList.toggle('on', b.dataset.f === filter));
      }
      q('.todo-add').onsubmit = e => {
        e.preventDefault();
        const inp = q('.todo-add .input');
        const text = inp.value.trim();
        if (!text) return;
        items.push({ id: Date.now(), text, done: false, pri: Number(q('.todo-pri').value), created: Date.now() });
        inp.value = '';
        save(); render();
      };
      el.querySelectorAll('.todo-filters button').forEach(b => b.onclick = () => { filter = b.dataset.f; render(); });
      q('.todo-clear').onclick = () => { items = items.filter(t => !t.done); save(); render(); };
      render();
      q('.todo-add .input').focus();
    },
    unmount() {}
  });

  // ============ 便签 ============
  Hub.register({
    id: 'notes', title: '便签', group: 'tool', order: 1.5, icon: ICON.notes,
    mount(el, ctx) {
      const COLORS = ['#fff3b0', '#ffd6c9', '#d4f0c9', '#cfe6ff', '#ead7ff'];
      let notes = ctx.store.get('notes', []);
      const save = () => ctx.store.set('notes', notes);
      el.innerHTML = `<h2 class="page-title">便签 <button class="btn primary notes-add">+ 新便签</button></h2><div class="notes-grid"></div>`;
      const grid = el.querySelector('.notes-grid');
      function render() {
        grid.innerHTML = notes.length ? '' : '<div class="todo-empty">点击「新便签」记录灵感吧~</div>';
        for (const n of notes) {
          const card = h(`<div class="note" style="background:${n.color}">
            <textarea placeholder="写点什么…" spellcheck="false"></textarea>
            <div class="note-foot"><div class="note-colors">${COLORS.map(c => `<i data-c="${c}" style="background:${c}"></i>`).join('')}</div>
            <span class="note-time">${new Date(n.updated).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
            <button class="todo-del" title="删除"><svg viewBox="0 0 20 20"><path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></div></div>`);
          const ta = card.querySelector('textarea');
          ta.value = n.text;
          ta.oninput = () => { n.text = ta.value; n.updated = Date.now(); save(); };
          card.querySelectorAll('.note-colors i').forEach(i => i.onclick = () => { n.color = i.dataset.c; card.style.background = n.color; save(); });
          card.querySelector('.todo-del').onclick = () => {
            if (n.text.trim() && !confirm('确定删除这张便签吗？')) return;
            notes = notes.filter(x => x !== n); save(); render();
          };
          grid.appendChild(card);
        }
      }
      el.querySelector('.notes-add').onclick = () => {
        notes.unshift({ id: Date.now(), text: '', color: COLORS[notes.length % COLORS.length], updated: Date.now() });
        save(); render();
        grid.querySelector('textarea').focus();
      };
      render();
    },
    unmount() {}
  });

  // ============ 换宠物 ============
  Hub.register({
    id: 'pets', title: '换宠物', group: 'pet', order: 2, icon: ICON.pets,
    mount(el) {
      el.innerHTML = `<h2 class="page-title">选择你的桌宠</h2><div class="pets-grid"></div>`;
      const grid = el.querySelector('.pets-grid');
      const render = () => {
        const cur = api.settings.get().pet;
        grid.innerHTML = '';
        for (const f of api.pets()) {
          const b = h(`<button class="pet-card ${f === cur ? 'on' : ''}"><img src="${api.petImage(f)}" alt=""><span>${esc(petName(f))}</span></button>`);
          b.onclick = () => { api.settings.update({ pet: f }); setTimeout(render, 50); };
          grid.appendChild(b);
        }
      };
      render();
    },
    unmount() {}
  });

  // ============ 设置 ============
  Hub.register({
    id: 'settings', title: '设置', group: 'system', icon: ICON.settings,
    mount(el) {
      const s = api.settings.get();
      const row = (label, sub, ctrl) => `<div class="set-row"><div><div>${label}</div>${sub ? `<div class="set-sub">${sub}</div>` : ''}</div>${ctrl}</div>`;
      const sw = (k, on) => `<label class="switch"><input type="checkbox" data-k="${k}" ${on ? 'checked' : ''}><span></span></label>`;
      const rem = (k, label, sub) => row(label, sub, `<div class="set-rem"><input class="input" type="number" min="5" max="240" data-rk="${k}" value="${s[k].minutes}"> 分钟 ${sw(k + '.enabled', s[k].enabled)}</div>`);
      el.innerHTML = `
        <h2 class="page-title">设置</h2>
        <div class="card set-card">
          <div class="side-title">桌宠</div>
          ${row('主题配色', `当前：${PetTheme.get().name} · ${PetTheme.HINT}`, '')}
          ${row('宠物大小', '', `<input type="range" min="0.6" max="1.6" step="0.05" value="${s.scale}" data-range="scale"><span class="set-val" data-v="scale">${Math.round(s.scale * 100)}%</span>`)}
          ${row('不透明度', '', `<input type="range" min="0.3" max="1" step="0.05" value="${s.opacity}" data-range="opacity"><span class="set-val" data-v="opacity">${Math.round(s.opacity * 100)}%</span>`)}
          ${row('总在最前', '桌宠显示在其他窗口之上', sw('alwaysOnTop', s.alwaysOnTop))}
          ${row('随机说话', '桌宠会不时冒出一句话', sw('chatter', s.chatter))}
          ${row('开机自启动', '登录 Windows 后自动运行', sw('autoStart', s.autoStart))}
        </div>
        <div class="card set-card">
          <div class="side-title">健康提醒</div>
          ${rem('water', '喝水提醒', '定时提醒补充水分')}
          ${rem('sit', '久坐提醒', '起来活动活动')}
          ${rem('eye', '护眼提醒', '20-20-20 法则：看 20 英尺外 20 秒')}
        </div>
        <div class="card set-card">
          <div class="side-title">关于</div>
          ${row('DesktopPet v1.0.0', '双击桌宠或点击 ⋯ 按钮打开菜单；右键桌宠可快捷设置；托盘图标可隐藏/显示桌宠', '<button class="btn danger" data-quit>退出程序</button>')}
        </div>`;
      for (const inp of el.querySelectorAll('input[data-k]')) {
        inp.onchange = () => {
          const [k, sub] = inp.dataset.k.split('.');
          if (sub) api.settings.update({ [k]: { ...api.settings.get()[k], [sub]: inp.checked } });
          else api.settings.update({ [k]: inp.checked });
        };
      }
      for (const inp of el.querySelectorAll('input[data-rk]')) {
        inp.onchange = () => {
          const k = inp.dataset.rk;
          const v = Math.min(240, Math.max(5, Math.round(Number(inp.value)) || 5));
          inp.value = v;
          api.settings.update({ [k]: { ...api.settings.get()[k], minutes: v } });
        };
      }
      for (const inp of el.querySelectorAll('input[data-range]')) {
        const k = inp.dataset.range;
        inp.oninput = () => { el.querySelector(`[data-v=${k}]`).textContent = `${Math.round(inp.value * 100)}%`; };
        inp.onchange = () => api.settings.update({ [k]: Number(inp.value) });
      }
      el.querySelector('[data-quit]').onclick = () => api.quit();
    },
    unmount() {}
  });
})();
