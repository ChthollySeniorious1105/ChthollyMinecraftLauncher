// 推箱子 Sokoban — hub module. See ../MODULES.md for the contract.
// Levels are standard XSB rows (# wall, space floor, . goal, $ box, * box on goal, @ player, + player on goal).
// Every level was verified solvable with a BFS push solver during development.
(function () {
  const LEVELS = [
    ["######","#    #","# #@ #","# $* #","# .* #","#    #","######"],
    ["####","#  ####","# . . #","# $$#@#","##    #"," ######"],
    [" #######"," #     #"," # .$. #","## $@$ #","#  .$. #","#      #","########"],
    ["#######","#     #","# .$. #","# $.$ #","# .$. #","# $.$ #","#  @  #","#######"],
    ["########","#      #","# .**$@#","#      #","#####  #","    ####"],
    [" ####"," #  ###"," # $$ #","##... #","#  @$ #","#   ###","#####"],
    ["####","# .#","#  ###","#*@  #","#  $ #","#  ###","####"],
    ["#####","# @ #","#...#","#$$$##","#    #","#    #","######"],
    ["  #####","  #   #","###$$@#","#   ###","#     #","# . . #","#######"],
    ["#####","#.  ##","#@$$ #","##   #"," ##  #","  ##.#","   ###"],
    ["#######","#     #","# # # #","#. $*@#","#   ###","#####"],
    ["#######","#  *  #","#     #","## # ##"," #$@.#"," #   #"," #####"],
    ["#####","#   ##","# $  #","## $ ####"," ###@.  #","  #  .# #","  #     #","  #######"],
    ["     ###","######@##","#    .* #","#   #   #","#####$# #","    #   #","    #####"],
    ["  ####","###  ####","#     $ #","# #  #$ #","# . .#@ #","#########"],
    ["#######","#     #","#. .  #","# ## ##","#  $ #","###$ #","  #@ #","  #  #","  ####"],
    ["#####","#   ###","#. .  #","#   # #","## #  #"," #@$$ #"," #    #"," #  ###"," ####"],
    ["  ######","  #    #","  # ##@##","### # $ #","# ..# $ #","#       #","#  ######","####"],
    ["#######","#     ###","#  @$$..#","#### ## #","  #     #","  #  ####","  #  #","  ####"],
    ["########","#   .. #","#  @$$ #","##### ##","   #  #","   #  #","   #  #","   ####"],
    ["      #####","      #.  #","      #.# #","#######.# #","# @ $ $ $ #","# # # # ###","#       #","#########"],
    ["####","#. ##","#.@ #","#. $#","##$ ###"," # $  #"," #    #"," #  ###"," ####"],
    ["###### #####","#    ###   #","# $$     #@#","# $ #...   #","#   ########","#####"],
    ["  ######","  # ..@#","  # $$ #","  ## ###","   # #","   # #","#### #","#    ##","# #   #","#   # #","###   #","  #####"],
    [" ####"," #  ####"," #     ##","## ##   #","#. .# @$##","#   # $$ #","#  .#    #","##########"]
  ].map(rows => rows.join("\n"));

  const T = 48; // SVG units per tile
  const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
  const KEYS = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    KeyW: 'up', KeyS: 'down', KeyA: 'left', KeyD: 'right'
  };
  const ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="4" y="9" width="11" height="11" rx="1.5"/><path d="M4 14.5h11M9.5 9v11"/><circle cx="18.5" cy="6" r="2.3"/><path d="M18.5 8.5v5M16 11h5" stroke-linecap="round"/></svg>';

  function parse(txt) {
    const rows = txt.split('\n');
    const H = rows.length, W = Math.max(...rows.map(r => r.length));
    const wall = new Uint8Array(W * H), goal = new Uint8Array(W * H);
    const boxes = []; let player = 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const c = rows[y][x] || ' ', i = y * W + x;
      if (c === '#') wall[i] = 1;
      if (c === '.' || c === '*' || c === '+') goal[i] = 1;
      if (c === '$' || c === '*') boxes.push(i);
      if (c === '@' || c === '+') player = i;
    }
    // interior floor = flood fill from the player
    const inside = new Uint8Array(W * H); const st = [player]; inside[player] = 1;
    while (st.length) {
      const c = st.pop(), x = c % W, y = (c / W) | 0;
      for (const [dx, dy] of Object.values(DIRS)) {
        const nx = x + dx, ny = y + dy, n = ny * W + nx;
        if (nx < 0 || ny < 0 || nx >= W || ny >= H || inside[n] || wall[n]) continue;
        inside[n] = 1; st.push(n);
      }
    }
    return { W, H, wall, goal, boxes, player, inside };
  }

  function playerSVG(dir) {
    // a round orange kitty; the face is drawn according to the facing direction
    const side = `<circle cx="7" cy="-1" r="2.6" fill="#3b2418"/><circle cx="7.8" cy="-2" r=".9" fill="#fff"/>
      <path d="M9 5q2.5 1.5 4.5-.5" stroke="#3b2418" stroke-width="1.4" fill="none" stroke-linecap="round"/>
      <ellipse cx="4" cy="4.5" rx="2.6" ry="1.6" fill="#f7a38a" opacity=".8"/>`;
    const face = {
      down: `<circle cx="-6" cy="-1" r="2.6" fill="#3b2418"/><circle cx="6" cy="-1" r="2.6" fill="#3b2418"/>
        <circle cx="-5.2" cy="-2" r=".9" fill="#fff"/><circle cx="6.8" cy="-2" r=".9" fill="#fff"/>
        <path d="M-2.5 4q2.5 2.2 5 0" stroke="#3b2418" stroke-width="1.4" fill="none" stroke-linecap="round"/>
        <ellipse cx="-10" cy="4" rx="2.6" ry="1.6" fill="#f7a38a" opacity=".8"/><ellipse cx="10" cy="4" rx="2.6" ry="1.6" fill="#f7a38a" opacity=".8"/>`,
      up: `<path d="M-5 -3q5 4 10 0M-6 3q6 4 12 0" stroke="#d9652a" stroke-width="1.8" fill="none" stroke-linecap="round"/>`,
      right: side,
      left: side
    };
    const tail = {
      down: '',
      up: '<path d="M8 10q10 2 9-10" stroke="#e8793a" stroke-width="4.5" fill="none" stroke-linecap="round"/>',
      right: '<path d="M-12 9q-9 0-7-10" stroke="#e8793a" stroke-width="4.5" fill="none" stroke-linecap="round"/>',
      left: '<path d="M-12 9q-9 0-7-10" stroke="#e8793a" stroke-width="4.5" fill="none" stroke-linecap="round"/>'
    };
    const flip = dir === 'left' ? ' transform="scale(-1 1)"' : '';
    return `<ellipse cx="0" cy="18" rx="14" ry="3.5" fill="rgba(80,50,30,.18)"/><g class="sk-kitty"><g${flip}>
      ${tail[dir]}
      <path d="M-13-6l-2-12 10 6zM13-6l2-12-10 6z" fill="#e8793a" stroke="#c85f25" stroke-width="1.2" stroke-linejoin="round"/>
      <path d="M-12-8.5l-1-6 5 3zM12-8.5l1-6-5 3z" fill="#fbc7a6"/>
      <ellipse cx="0" cy="1" rx="15" ry="14" fill="#f39150" stroke="#c85f25" stroke-width="1.4"/>
      <path d="M-4-12.5q4 3 8 0" stroke="#d9652a" stroke-width="1.6" fill="none" stroke-linecap="round"/>
      ${face[dir]}
      <ellipse cx="-7" cy="14.5" rx="4" ry="2.6" fill="#fbe1cc" stroke="#c85f25" stroke-width="1"/>
      <ellipse cx="7" cy="14.5" rx="4" ry="2.6" fill="#fbe1cc" stroke="#c85f25" stroke-width="1"/>
    </g></g>`;
  }

  const BOX_SVG = `<rect x="-19" y="-19" width="38" height="38" rx="5" class="sk-box-body"/>
    <rect x="-14" y="-14" width="28" height="28" rx="2" class="sk-box-inner"/>
    <path d="M-14-14L14 14M14-14L-14 14" class="sk-box-x"/>
    <rect x="-19" y="-19" width="38" height="38" rx="5" class="sk-box-edge"/>`;

  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'sk-root';
    root.innerHTML = `
      <div class="sk-bar">
        <div class="sk-title"><b class="sk-lv"></b><span class="sk-best"></span></div>
        <div class="sk-stats">
          <div class="sk-stat"><span>步数</span><b class="sk-moves">0</b></div>
          <div class="sk-stat"><span>推动</span><b class="sk-pushes">0</b></div>
        </div>
        <div class="sk-btns">
          <button class="btn sk-prev" title="上一关">‹</button>
          <button class="btn sk-next" title="下一关">›</button>
          <button class="btn sk-undo" title="撤销 (U / Ctrl+Z)">撤销</button>
          <button class="btn sk-restart" title="重来 (R)">重来</button>
          <button class="btn primary sk-sel">选关</button>
        </div>
      </div>
      <div class="sk-stage">
        <svg class="sk-board" xmlns="http://www.w3.org/2000/svg">
          <g class="sk-static"></g><g class="sk-boxes"></g><g class="sk-player"></g>
        </svg>
        <div class="sk-overlay hidden">
          <div class="sk-card">
            <div class="sk-ov-title">过关啦！</div>
            <div class="sk-ov-sub"></div>
            <div class="sk-ov-btns"><button class="btn sk-ov-again">再玩一次</button><button class="btn primary sk-ov-next">下一关</button></div>
          </div>
        </div>
        <div class="sk-select hidden">
          <div class="sk-sel-head"><span class="side-title">选择关卡</span><span class="set-sub sk-sel-sum"></span><button class="btn sk-sel-close">返回</button></div>
          <div class="sk-grid"></div>
        </div>
      </div>
      <div class="sk-help">方向键 / WASD 移动 · U 或 Ctrl+Z 撤销 · R 重来 · 把所有箱子推到目标点上</div>`;
    el.appendChild(root);
    const $ = s => root.querySelector(s);
    const svg = $('.sk-board'), gStatic = $('.sk-static'), gBoxes = $('.sk-boxes'), gPlayer = $('.sk-player');
    const overlay = $('.sk-overlay'), selectEl = $('.sk-select');

    // progress: { unlocked: count of unlocked levels (>=1), best: { [idx]: {moves, pushes} }, cur }
    const saved = ctx.store.get('progress', {}) || {};
    const prog = { unlocked: Math.max(1, saved.unlocked || 1), best: saved.best || {}, cur: saved.cur || 0 };
    const saveProg = () => ctx.store.set('progress', prog);

    let L = null, idx = 0, boxes = [], boxEls = [], player = 0, dir = 'down';
    let moves = 0, pushes = 0, history = [], won = false, winTimer = null;

    const tileXY = i => [(i % L.W) * T, Math.floor(i / L.W) * T];

    function load(n) {
      idx = Math.max(0, Math.min(LEVELS.length - 1, n));
      prog.cur = idx; saveProg();
      L = parse(LEVELS[idx]);
      boxes = L.boxes.slice(); player = L.player; dir = 'down';
      moves = 0; pushes = 0; history = []; won = false;
      clearTimeout(winTimer);
      overlay.classList.add('hidden');
      drawStatic();
      gBoxes.innerHTML = '';
      boxEls = boxes.map(() => {
        const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
        g.setAttribute('class', 'sk-box');
        g.innerHTML = BOX_SVG;
        gBoxes.appendChild(g);
        return g;
      });
      render(true);
    }

    function drawStatic() {
      const { W, H, wall, goal, inside } = L;
      svg.setAttribute('viewBox', `-4 -4 ${W * T + 8} ${H * T + 8}`);
      const tile = Math.max(26, Math.min(54, Math.floor(700 / W), Math.floor(440 / H)));
      svg.style.width = `${W * tile + 8}px`;
      svg.style.height = `${H * tile + 8}px`;
      let s = '';
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const i = y * W + x, px = x * T, py = y * T;
        if (wall[i]) {
          s += `<g transform="translate(${px} ${py})"><rect x="1" y="1" width="${T - 2}" height="${T - 2}" rx="5" class="sk-wall"/>` +
            `<path d="M3 ${T / 2}H${T - 3}M${T / 2} 3V${T / 2}M${T / 4} ${T / 2}V${T - 3}M${T * 3 / 4} ${T / 2}V${T - 3}" class="sk-mortar"/></g>`;
        } else if (inside[i]) {
          s += `<rect x="${px}" y="${py}" width="${T}" height="${T}" class="sk-floor${(x + y) % 2 ? ' odd' : ''}"/>`;
          if (goal[i]) s += `<g transform="translate(${px + T / 2} ${py + T / 2})" class="sk-goal"><circle r="12"/><circle r="5.5"/></g>`;
        }
      }
      gStatic.innerHTML = s;
    }

    function render(instant) {
      root.classList.toggle('sk-instant', !!instant);
      boxes.forEach((b, k) => {
        const [x, y] = tileXY(b);
        boxEls[k].style.transform = `translate(${x + T / 2}px, ${y + T / 2}px)`;
        boxEls[k].classList.toggle('on', !!L.goal[b]);
      });
      const [px, py] = tileXY(player);
      gPlayer.style.transform = `translate(${px + T / 2}px, ${py + T / 2}px)`;
      if (gPlayer.dataset.dir !== dir) { gPlayer.dataset.dir = dir; gPlayer.innerHTML = playerSVG(dir); }
      $('.sk-moves').textContent = moves;
      $('.sk-pushes').textContent = pushes;
      $('.sk-lv').textContent = `第 ${idx + 1} 关`;
      const b = prog.best[idx];
      $('.sk-best').textContent = b ? `最佳 ${b.moves} 步 / ${b.pushes} 推` : '未通关';
      $('.sk-prev').disabled = idx === 0;
      $('.sk-next').disabled = idx + 1 >= LEVELS.length || idx + 1 >= prog.unlocked;
      $('.sk-undo').disabled = !history.length;
      if (instant) requestAnimationFrame(() => requestAnimationFrame(() => root.classList.remove('sk-instant')));
    }

    function move(d) {
      if (won) return;
      dir = d;
      const [dx, dy] = DIRS[d];
      const W = L.W;
      const n = player + dy * W + dx;
      if (L.wall[n]) { render(); return; }
      const k = boxes.indexOf(n);
      if (k >= 0) {
        const n2 = n + dy * W + dx;
        if (L.wall[n2] || boxes.includes(n2)) { render(); return; }
        boxes[k] = n2; pushes++;
        history.push({ p: player, d, k, from: n });
      } else {
        history.push({ p: player, d, k: -1 });
      }
      player = n; moves++;
      render();
      if (boxes.every(b => L.goal[b])) win();
    }

    function undo() {
      const h = history.pop();
      if (!h) return;
      if (won) { won = false; clearTimeout(winTimer); overlay.classList.add('hidden'); }
      player = h.p; dir = h.d; moves--;
      if (h.k >= 0) { boxes[h.k] = h.from; pushes--; }
      render();
    }

    function win() {
      won = true;
      const level = idx + 1;
      const prev = prog.best[idx];
      const first = !prev;
      const better = !prev || moves < prev.moves || (moves === prev.moves && pushes < prev.pushes);
      if (better) prog.best[idx] = { moves, pushes };
      prog.unlocked = Math.max(prog.unlocked, Math.min(LEVELS.length, idx + 2));
      saveProg();
      render();
      const last = idx + 1 >= LEVELS.length;
      $('.sk-ov-title').textContent = last ? '全部通关！太厉害了！' : '过关啦！';
      $('.sk-ov-sub').textContent = `${moves} 步 · ${pushes} 次推动${!first && better ? ' · 新纪录！' : ''}`;
      $('.sk-ov-next').style.display = last ? 'none' : '';
      winTimer = setTimeout(() => { if (won) overlay.classList.remove('hidden'); }, 280);
      if (first) {
        ctx.reward(3 + Math.floor(level / 5), '推箱子过关');
        ctx.say(last ? '推箱子全部通关啦！你是推箱子大师！' : `推箱子第 ${level} 关通关！下一关解锁啦~`);
      } else if (better) {
        ctx.say(`推箱子第 ${level} 关刷新纪录：${moves} 步！`);
      }
    }

    function showSelect(on) {
      selectEl.classList.toggle('hidden', !on);
      if (!on) return;
      const grid = $('.sk-grid');
      grid.innerHTML = '';
      $('.sk-sel-sum').textContent = `已通关 ${Object.keys(prog.best).length} / ${LEVELS.length}`;
      LEVELS.forEach((_, i) => {
        const b = prog.best[i], locked = i >= prog.unlocked;
        const btn = document.createElement('button');
        btn.className = `sk-cell${b ? ' solved' : ''}${locked ? ' locked' : ''}${i === idx ? ' cur' : ''}`;
        btn.disabled = locked;
        btn.innerHTML = `<b>${i + 1}</b><span>${locked ? '🔒 未解锁' : b ? `✔ ${b.moves} 步` : '未通关'}</span>`;
        btn.onclick = () => { showSelect(false); load(i); };
        grid.appendChild(btn);
      });
    }

    $('.sk-undo').onclick = undo;
    $('.sk-restart').onclick = () => load(idx);
    $('.sk-prev').onclick = () => load(idx - 1);
    $('.sk-next').onclick = () => load(idx + 1);
    $('.sk-sel').onclick = () => showSelect(true);
    $('.sk-sel-close').onclick = () => showSelect(false);
    $('.sk-ov-again').onclick = () => load(idx);
    $('.sk-ov-next').onclick = () => load(idx + 1);

    function onKey(e) {
      if (!ctx.isActive()) return;
      const tag = e.target && e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
      if (!selectEl.classList.contains('hidden')) {
        if (e.key === 'Escape') showSelect(false);
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.code === 'KeyZ') { e.preventDefault(); undo(); return; }
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.code === 'KeyU') { e.preventDefault(); undo(); return; }
      if (e.code === 'KeyR') { e.preventDefault(); load(idx); return; }
      if (won && e.key === 'Enter' && idx + 1 < LEVELS.length) { e.preventDefault(); load(idx + 1); return; }
      const d = KEYS[e.code];
      if (d) { e.preventDefault(); if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); move(d); }
    }
    window.addEventListener('keydown', onKey);
    cleanup = () => { window.removeEventListener('keydown', onKey); clearTimeout(winTimer); };

    load(Math.min(prog.cur, prog.unlocked - 1));
  }

  Hub.register({
    id: 'sokoban', title: '推箱子', group: 'game', icon: ICON,
    levels: LEVELS,
    mount,
    unmount() { if (cleanup) cleanup(); cleanup = null; }
  });
})();
