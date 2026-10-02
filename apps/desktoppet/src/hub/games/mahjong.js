// 麻将接龙 — Mahjong Solitaire (Shanghai) module for the hub. See ../MODULES.md for the contract.
(function () {
  const RATIO = 1.32;     // tile height / width
  const DEPTH = 0.12;     // layer offset (and tile thickness) relative to tile width
  const SHUFFLES = 3;

  // ================= layouts (coordinates in half-tile units) =================
  function mkRow(p, z, y, c0, c1) { for (let c = c0; c <= c1; c++) p.push([c * 2, y, z]); }

  function turtle() {
    const p = [];
    mkRow(p, 0, 0, 1, 12); mkRow(p, 0, 2, 3, 10); mkRow(p, 0, 4, 2, 11); mkRow(p, 0, 6, 1, 12);
    mkRow(p, 0, 8, 1, 12); mkRow(p, 0, 10, 2, 11); mkRow(p, 0, 12, 3, 10); mkRow(p, 0, 14, 1, 12);
    p.push([0, 7, 0], [26, 7, 0], [28, 7, 0]);
    for (let r = 1; r <= 6; r++) mkRow(p, 1, r * 2, 4, 9);
    for (let r = 2; r <= 5; r++) mkRow(p, 2, r * 2, 5, 8);
    for (let r = 3; r <= 4; r++) mkRow(p, 3, r * 2, 6, 7);
    p.push([13, 7, 4]);
    return p; // 144
  }

  function pyramid() {
    const p = [];
    for (let r = 0; r <= 5; r++) mkRow(p, 0, r * 2, 0, 11);
    for (let r = 1; r <= 4; r++) mkRow(p, 1, r * 2, 1, 10);
    for (let r = 2; r <= 3; r++) mkRow(p, 2, r * 2, 2, 9);
    mkRow(p, 3, 5, 3, 8);
    mkRow(p, 4, 5, 4, 7);
    mkRow(p, 5, 5, 5, 6);
    return p; // 140
  }

  function cross() {
    const p = [];
    // layer 0: horizontal bar, vertical bar, four corner blocks
    mkRow(p, 0, 6, 0, 13); mkRow(p, 0, 8, 0, 13);
    for (const r of [0, 1, 2, 5, 6, 7]) mkRow(p, 0, r * 2, 5, 8);
    for (const r of [0, 1, 6, 7]) { mkRow(p, 0, r * 2, 0, 2); mkRow(p, 0, r * 2, 11, 13); }
    // layer 1
    mkRow(p, 1, 6, 1, 12); mkRow(p, 1, 8, 1, 12);
    for (const r of [1, 2, 5, 6]) mkRow(p, 1, r * 2, 6, 7);
    for (const y of [1, 13]) p.push([1, y, 1], [3, y, 1], [23, y, 1], [25, y, 1]);
    // layer 2
    mkRow(p, 2, 7, 3, 10);
    p.push([13, 3, 2], [13, 11, 2]);
    for (const y of [1, 13]) p.push([2, y, 2], [24, y, 2]);
    // layers 3, 4
    mkRow(p, 3, 7, 5, 8);
    p.push([12, 7, 4], [14, 7, 4]);
    return p; // 136
  }

  const LAYOUTS = [
    { key: 'turtle', name: '龟阵', build: turtle, reward: 10 },
    { key: 'cross', name: '十字阵', build: cross, reward: 10 },
    { key: 'pyramid', name: '金字塔', build: pyramid, reward: 10 }
  ].map(L => {
    const pos = L.build().map(([x, y, z]) => ({ x, y, z }));
    const n = pos.length;
    const above = [], left = [], right = [];
    let maxX = 0, maxY = 0, maxZ = 0;
    for (let i = 0; i < n; i++) {
      const a = pos[i];
      maxX = Math.max(maxX, a.x); maxY = Math.max(maxY, a.y); maxZ = Math.max(maxZ, a.z);
      above[i] = []; left[i] = []; right[i] = [];
      for (let j = 0; j < n; j++) {
        if (i === j) continue;
        const b = pos[j], dx = b.x - a.x, dy = b.y - a.y;
        if (b.z > a.z && Math.abs(dx) < 2 && Math.abs(dy) < 2) above[i].push(j);
        else if (b.z === a.z && Math.abs(dy) < 2) {
          if (dx === -2) left[i].push(j);
          else if (dx === 2) right[i].push(j);
        }
      }
    }
    return Object.assign({}, L, { pos, n, above, left, right, maxX, maxY, maxZ });
  });

  function isFreeIn(L, i, present) {
    for (const j of L.above[i]) if (present[j]) return false;
    let lf = true, rf = true;
    for (const j of L.left[i]) if (present[j]) { lf = false; break; }
    if (lf) return true;
    for (const j of L.right[i]) if (present[j]) { rf = false; break; }
    return rf;
  }

  // ================= tiles =================
  // face ids: m1-9 万, s1-9 条, p1-9 筒, w1-4 风, d1-3 箭, f1-4 花, x1-4 季
  const kindOf = f => (f[0] === 'f' || f[0] === 'x') ? f[0] : f;
  const NUM_CN = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  const FONT = "KaiTi, STKaiti, 'Microsoft YaHei', serif";
  const BLUE = '#2a5caa', GREEN = '#2e8b57', RED = '#c8342b', INK = '#1d2b5a';

  function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }
  function fmtTime(ms) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }

  const PIN_POS = {
    1: [[20, 27, 12]],
    2: [[20, 15, 7], [20, 39, 7]],
    3: [[10, 12, 6], [20, 27, 6], [30, 42, 6]],
    4: [[12, 15, 6.5], [28, 15, 6.5], [12, 39, 6.5], [28, 39, 6.5]],
    5: [[11, 13, 6], [29, 13, 6], [20, 27, 6], [11, 41, 6], [29, 41, 6]],
    6: [[12, 11, 5.5], [28, 11, 5.5], [12, 27, 5.5], [28, 27, 5.5], [12, 43, 5.5], [28, 43, 5.5]],
    7: [[9, 9, 4.6], [20, 15, 4.6], [31, 21, 4.6], [13, 33, 4.8], [27, 33, 4.8], [13, 45, 4.8], [27, 45, 4.8]],
    8: [[12, 8, 5], [28, 8, 5], [12, 21, 5], [28, 21, 5], [12, 34, 5], [28, 34, 5], [12, 47, 5], [28, 47, 5]],
    9: [11, 27, 43].flatMap(y => [10, 20, 30].map(x => [x, y, 5]))
  };

  function pinColor(n, k) {
    if (n === 1) return RED;
    if (n === 2) return k ? BLUE : GREEN;
    if (n === 3) return [BLUE, RED, GREEN][k];
    if (n === 5) return k === 2 ? RED : (k % 3 ? GREEN : BLUE);
    if (n === 6) return k < 2 ? GREEN : RED;
    if (n === 7) return k < 3 ? GREEN : RED;
    if (n === 9) return [BLUE, RED, GREEN][(k / 3) | 0];
    return k % 2 ? GREEN : BLUE;
  }
  function pinSvg(n) {
    return PIN_POS[n].map(([x, y, r], k) => {
      const c = pinColor(n, k);
      let s = `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}"/><circle cx="${x}" cy="${y}" r="${(r * 0.62).toFixed(2)}" fill="#fffaf0"/><circle cx="${x}" cy="${y}" r="${(r * 0.32).toFixed(2)}" fill="${c}"/>`;
      if (n === 1) s += `<circle cx="${x}" cy="${y}" r="${r * 0.85}" fill="none" stroke="#fffaf0" stroke-width="1" stroke-dasharray="2 1.6"/>`;
      return s;
    }).join('');
  }

  const STICK_POS = {
    2: [[20, 15], [20, 39]],
    3: [[20, 14], [12, 40], [28, 40]],
    4: [[13, 15], [27, 15], [13, 39], [27, 39]],
    5: [[11, 15], [29, 15], [20, 27, 1], [11, 39], [29, 39]],
    6: [[10, 15], [20, 15], [30, 15], [10, 39], [20, 39], [30, 39]],
    7: [[20, 9, 1], [10, 27], [20, 27], [30, 27], [10, 45], [20, 45], [30, 45]],
    8: [[8, 15], [16, 15], [24, 15], [32, 15], [8, 39], [16, 39], [24, 39], [32, 39]],
    9: [9, 27, 45].flatMap(y => [10, 20, 30].map(x => [x, y, x === 20 ? 1 : 0]))
  };
  function stickSvg(n) {
    if (n === 1) {
      // 幺鸡: a little bird
      return `<g><path d="M9 40 L4 50 L12 45 L10 52 L16 44 Z" fill="${GREEN}"/>` +
        `<ellipse cx="20" cy="32" rx="11" ry="9" fill="${GREEN}"/>` +
        `<path d="M14 30 Q20 24 27 31 Q20 34 14 30Z" fill="#7fc79a"/>` +
        `<circle cx="28" cy="17" r="6.5" fill="${RED}"/><circle cx="30" cy="16" r="1.4" fill="#fff"/>` +
        `<path d="M34 17 L39 19 L34 20Z" fill="#e0a020"/>` +
        `<path d="M17 41 L15 48 M23 41 L24 48" stroke="#b5651d" stroke-width="1.6"/></g>`;
    }
    const w = n === 8 ? 4.4 : 5.4, h = 14;
    return STICK_POS[n].map(([x, y, red]) => {
      const c = red ? RED : GREEN;
      return `<g transform="translate(${x} ${y})"><rect x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" rx="${w / 2 - 0.4}" fill="${c}"/>` +
        `<line x1="${-w / 2}" x2="${w / 2}" y1="0" y2="0" stroke="#fffaf0" stroke-width="1"/>` +
        `<line x1="0" x2="0" y1="${-h / 2 + 2}" y2="${h / 2 - 2}" stroke="#fffaf0" stroke-opacity=".45" stroke-width=".8"/></g>`;
    }).join('');
  }

  const txt = (x, y, size, fill, s, weight) =>
    `<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" text-anchor="middle" font-family="${FONT}" font-weight="${weight || 700}">${s}</text>`;

  const FLOWERS = [['梅', RED], ['兰', '#7b4fa0'], ['竹', GREEN], ['菊', '#d08a00']];
  const SEASONS = [['春', GREEN], ['夏', RED], ['秋', '#d0701a'], ['冬', BLUE]];

  const faceCache = new Map();
  function faceSvg(f) {
    if (faceCache.has(f)) return faceCache.get(f);
    const t = f[0], n = +f.slice(1);
    // suits and honours use the shared standard faces; flowers/seasons keep their own art
    if (window.MahjongTiles && 'mpswd'.includes(t)) {
      const kind = t === 'm' ? n - 1 : t === 'p' ? 8 + n : t === 's' ? 17 + n : t === 'w' ? 26 + n : n === 1 ? 33 : n === 2 ? 32 : 31;
      const svg = window.MahjongTiles.face(kind, false).replace('<svg ', '<svg preserveAspectRatio="xMidYMid meet" ');
      faceCache.set(f, svg);
      return svg;
    }
    let body = '';
    if (t === 'm') body = txt(20, 22, 17, INK, NUM_CN[n]) + txt(20, 47, 20, RED, '萬');
    else if (t === 'p') body = pinSvg(n);
    else if (t === 's') body = stickSvg(n);
    else if (t === 'w') body = txt(20, 38, 29, INK, '东南西北'[n - 1]);
    else if (t === 'd') {
      if (n === 1) body = txt(20, 38, 30, RED, '中');
      else if (n === 2) body = txt(20, 38, 30, GREEN, '發');
      else body = `<rect x="8" y="9" width="24" height="36" rx="2" fill="none" stroke="${BLUE}" stroke-width="2.6"/><rect x="11.5" y="12.5" width="17" height="29" fill="none" stroke="${BLUE}" stroke-width="1"/>`;
    } else {
      const [ch, c] = (t === 'f' ? FLOWERS : SEASONS)[n - 1];
      body = txt(7, 11, 9, c, n) + txt(20, 35, 24, c, ch) +
        `<path d="M8 44 Q20 50 32 44" fill="none" stroke="${c}" stroke-width="1.2" stroke-opacity=".6"/>` +
        txt(33, 11, 8, '#9b8472', t === 'f' ? '花' : '季', 400);
    }
    const svg = `<svg viewBox="0 0 40 54" preserveAspectRatio="xMidYMid meet">${body}</svg>`;
    faceCache.set(f, svg);
    return svg;
  }

  function pairPool() {
    const pool = [];
    for (const t of ['m', 's', 'p']) for (let n = 1; n <= 9; n++) pool.push([t + n, t + n], [t + n, t + n]);
    for (let n = 1; n <= 4; n++) pool.push(['w' + n, 'w' + n], ['w' + n, 'w' + n]);
    for (let n = 1; n <= 3; n++) pool.push(['d' + n, 'd' + n], ['d' + n, 'd' + n]);
    for (const t of ['f', 'x']) {
      const g = shuffle([1, 2, 3, 4].map(n => t + n));
      pool.push([g[0], g[1]], [g[2], g[3]]);
    }
    return shuffle(pool); // 72 pairs
  }

  // Simulates play: repeatedly take two currently free positions and give them a pair.
  // Playing the pairs in the same order clears the board, so the deal is always solvable.
  function tryAssign(L, idxs, pairs) {
    const present = new Uint8Array(L.n);
    for (const i of idxs) present[i] = 1;
    let alive = idxs.slice();
    const res = new Map();
    for (const pr of pairs) {
      const free = alive.filter(i => isFreeIn(L, i, present));
      if (free.length < 2) return null;
      const a = free.splice((Math.random() * free.length) | 0, 1)[0];
      const b = free[(Math.random() * free.length) | 0];
      if (Math.random() < 0.5) { res.set(a, pr[0]); res.set(b, pr[1]); }
      else { res.set(a, pr[1]); res.set(b, pr[0]); }
      present[a] = 0; present[b] = 0;
      alive = alive.filter(i => i !== a && i !== b);
    }
    return res;
  }

  // ================= module =================
  let cleanup = null;

  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'mj-root';
    root.innerHTML = `
      <div class="mj-bar">
        <div class="mj-stats">
          <div class="mj-stat"><span class="mj-lbl">剩余对数</span><b class="mj-left">0</b></div>
          <div class="mj-stat"><span class="mj-lbl">可配对</span><b class="mj-avail">0</b></div>
          <div class="mj-stat"><span class="mj-lbl">用时</span><b class="mj-time">0:00</b></div>
          <div class="mj-stat"><span class="mj-lbl">最佳</span><b class="mj-best">—</b></div>
        </div>
        <div class="mj-seg" role="group" aria-label="布局">
          ${LAYOUTS.map((l, i) => `<button type="button" data-lay="${i}" title="${l.n} 张">${l.name}</button>`).join('')}
        </div>
      </div>
      <div class="mj-tools">
        <button type="button" class="btn mj-hint" title="快捷键 H">提示</button>
        <button type="button" class="btn mj-undo" title="快捷键 Ctrl+Z">撤销</button>
        <button type="button" class="btn mj-shuffle" title="重新排列剩余的牌">洗牌</button>
        <button type="button" class="btn mj-dimbtn" title="将被压住的牌调暗">标出可选</button>
        <button type="button" class="btn primary mj-new" title="快捷键 N">新局</button>
      </div>
      <div class="mj-stage">
        <div class="mj-board"></div>
        <div class="mj-overlay hidden">
          <div class="mj-card">
            <div class="mj-ov-title"></div>
            <div class="mj-ov-sub"></div>
            <div class="mj-ov-btns">
              <button type="button" class="btn primary mj-ov-shuffle">洗牌</button>
              <button type="button" class="btn mj-ov-undo">撤销</button>
              <button type="button" class="btn mj-ov-new">新局</button>
            </div>
          </div>
        </div>
      </div>
      <div class="mj-help">点击两张相同且可移动的牌消除（上方无牌压住，且左侧或右侧至少一边空出）；花牌、季牌同组内可任意配对。</div>`;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const stage = $('.mj-stage'), board = $('.mj-board');
    const leftEl = $('.mj-left'), availEl = $('.mj-avail'), timeEl = $('.mj-time'), bestEl = $('.mj-best');
    const hintBtn = $('.mj-hint'), undoBtn = $('.mj-undo'), shufBtn = $('.mj-shuffle'), dimBtn = $('.mj-dimbtn'), newBtn = $('.mj-new');
    const overlay = $('.mj-overlay'), ovTitle = $('.mj-ov-title'), ovSub = $('.mj-ov-sub');
    const ovShuf = $('.mj-ov-shuffle'), ovUndo = $('.mj-ov-undo'), ovNew = $('.mj-ov-new');
    const laySeg = $('.mj-seg'), layBtns = [...root.querySelectorAll('[data-lay]')];

    let lay = ctx.store.get('layout', 0);
    if (!(lay >= 0 && lay < LAYOUTS.length)) lay = 0;
    let dim = !!ctx.store.get('dim', false);

    let L = null, faces = [], present = null, tileEls = [], freeFlags = [];
    let selected = -1, history = [], shufflesLeft = SHUFFLES;
    let started = false, finished = false, rewarded = false, stuck = false;
    let elapsed = 0, lastTick = performance.now();
    let hintTimer = 0, shakeTimer = 0, winTimer = 0, tickTimer = 0;

    const bestKey = () => 'best_' + L.key;

    // ---------- layout / fit ----------
    function fit() {
      if (!L) return;
      const host = el.parentElement || el;
      const cs = getComputedStyle(el);
      const padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(240, stage.clientWidth - 16);
      const ah = Math.max(200, (host.clientHeight || 640) - padY - chrome - 16);
      const cols = (L.maxX + 2) / 2, rows = (L.maxY + 2) / 2, ex = (L.maxZ + 1.4) * DEPTH;
      let w = Math.min(aw / (cols + ex), ah / (rows * RATIO + ex), 68);
      w = Math.max(22, Math.floor(w));
      const h = Math.round(w * RATIO), d = Math.max(2, Math.round(w * DEPTH));
      board.style.setProperty('--tw', w + 'px');
      board.style.setProperty('--th', h + 'px');
      board.style.setProperty('--d', d + 'px');
      board.style.setProperty('--mz', L.maxZ);
      board.style.width = Math.ceil(cols * w + (L.maxZ + 1.4) * d) + 'px';
      board.style.height = Math.ceil(rows * h + (L.maxZ + 1.4) * d) + 'px';
    }

    // ---------- game ----------
    function newGame() {
      clearTimeout(hintTimer); clearTimeout(winTimer); clearTimeout(shakeTimer);
      L = LAYOUTS[lay];
      const idxs = L.pos.map((_, i) => i);
      let res = null;
      for (let t = 0; t < 400 && !res; t++) res = tryAssign(L, idxs, pairPool().slice(0, L.n / 2));
      faces = new Array(L.n);
      if (res) res.forEach((f, i) => { faces[i] = f; });
      else { // practically unreachable; fall back to a plain random deal
        const all = pairPool().slice(0, L.n / 2).flat();
        shuffle(all).forEach((f, i) => { faces[i] = f; });
      }
      present = new Uint8Array(L.n).fill(1);
      selected = -1; history = []; shufflesLeft = SHUFFLES;
      started = false; finished = false; rewarded = false; stuck = false; elapsed = 0;
      overlay.classList.add('hidden');
      buildBoard();
      fit();
      refresh();
    }

    function buildBoard() {
      const order = L.pos.map((p, i) => i).sort((a, b) => {
        const A = L.pos[a], B = L.pos[b];
        return A.z - B.z || A.x - B.x || A.y - B.y;
      });
      let html = '';
      for (const i of order) {
        const p = L.pos[i];
        html += `<div class="mj-t" data-i="${i}" style="--x:${p.x};--y:${p.y};--z:${p.z};z-index:${p.z * 10000 + p.x * 100 + p.y + 1}"><div class="mj-face">${faceSvg(faces[i])}</div></div>`;
      }
      board.innerHTML = html;
      tileEls = [];
      board.querySelectorAll('.mj-t').forEach(t => { tileEls[+t.dataset.i] = t; });
    }

    function renderFaces() {
      for (let i = 0; i < L.n; i++) tileEls[i].firstChild.innerHTML = faceSvg(faces[i]);
    }

    function freePairs() {
      const byKind = new Map();
      for (let i = 0; i < L.n; i++) {
        if (!present[i] || !freeFlags[i]) continue;
        const k = kindOf(faces[i]);
        if (!byKind.has(k)) byKind.set(k, []);
        byKind.get(k).push(i);
      }
      const out = [];
      byKind.forEach(list => {
        for (let a = 0; a < list.length; a++) for (let b = a + 1; b < list.length; b++) out.push([list[a], list[b]]);
      });
      return out;
    }

    function remaining() { let r = 0; for (let i = 0; i < L.n; i++) r += present[i]; return r; }

    function refresh() {
      for (let i = 0; i < L.n; i++) {
        freeFlags[i] = present[i] ? isFreeIn(L, i, present) : false;
        const t = tileEls[i];
        t.classList.toggle('gone', !present[i]);
        t.classList.toggle('free', freeFlags[i]);
        t.classList.toggle('sel', i === selected);
      }
      const rem = remaining();
      const pairs = freePairs();
      leftEl.textContent = rem / 2;
      availEl.textContent = pairs.length;
      availEl.classList.toggle('warn', rem > 0 && pairs.length <= 1);
      const best = ctx.store.get(bestKey(), null);
      bestEl.textContent = best ? fmtTime(best) : '—';
      timeEl.textContent = fmtTime(elapsed);
      layBtns.forEach(b => b.classList.toggle('active', +b.dataset.lay === lay));
      root.classList.toggle('mj-dim', dim);
      dimBtn.classList.toggle('on', dim);
      undoBtn.disabled = finished || !history.length;
      hintBtn.disabled = finished;
      shufBtn.disabled = finished || shufflesLeft <= 0;
      shufBtn.textContent = `洗牌 (${shufflesLeft})`;
      return { rem, pairs };
    }

    function clearHint() {
      clearTimeout(hintTimer); hintTimer = 0;
      tileEls.forEach(t => t && t.classList.remove('hint'));
    }

    function afterChange() {
      const { rem, pairs } = refresh();
      if (rem === 0) { win(); return; }
      if (!pairs.length) showStuck();
      else if (stuck) { stuck = false; overlay.classList.add('hidden'); }
    }

    function showStuck() {
      stuck = true;
      ovTitle.textContent = '没有可以配对的牌了';
      ovSub.textContent = shufflesLeft > 0
        ? `还剩 ${shufflesLeft} 次洗牌机会，洗一洗剩下的牌吧～`
        : '洗牌次数已用完，可以撤销几步或开始新局。';
      ovShuf.style.display = shufflesLeft > 0 ? '' : 'none';
      ovShuf.textContent = `洗牌 (${shufflesLeft})`;
      ovUndo.style.display = history.length ? '' : 'none';
      overlay.classList.remove('hidden');
    }

    function win() {
      finished = true; stuck = false; selected = -1;
      const prev = ctx.store.get(bestKey(), null);
      const isRecord = !prev || elapsed < prev;
      if (isRecord) ctx.store.set(bestKey(), Math.round(elapsed));
      ctx.store.set('wins', (ctx.store.get('wins', 0) || 0) + 1);
      refresh();
      if (!rewarded) {
        rewarded = true;
        ctx.reward(L.reward, '麻将接龙胜利');
        ctx.say(isRecord && prev
          ? `麻将接龙${L.name}通关！用时 ${fmtTime(elapsed)}，刷新纪录啦～`
          : `麻将接龙${L.name}全部消除！用时 ${fmtTime(elapsed)}，好厉害喵～`);
      }
      ovTitle.textContent = '全部消除，通关啦！';
      ovSub.textContent = `${L.name} · 用时 ${fmtTime(elapsed)}${isRecord && prev ? ' · 新纪录！' : ''} · 获得 ${L.reward} 小鱼干`;
      ovShuf.style.display = 'none';
      ovUndo.style.display = 'none';
      clearTimeout(winTimer);
      winTimer = setTimeout(() => { winTimer = 0; if (finished) overlay.classList.remove('hidden'); }, 450);
    }

    function shake(i) {
      const t = tileEls[i];
      t.classList.remove('shake');
      void t.offsetWidth;
      t.classList.add('shake');
      clearTimeout(shakeTimer);
      shakeTimer = setTimeout(() => { shakeTimer = 0; t.classList.remove('shake'); }, 400);
    }

    function clickTile(i) {
      if (finished || !present[i]) return;
      if (!freeFlags[i]) { shake(i); return; }
      if (!started) { started = true; lastTick = performance.now(); }
      clearHint();
      if (selected === i) { selected = -1; refresh(); return; }
      if (selected >= 0 && kindOf(faces[selected]) === kindOf(faces[i])) {
        const a = selected;
        present[a] = 0; present[i] = 0;
        history.push({ t: 'p', a, b: i });
        selected = -1;
        afterChange();
        return;
      }
      selected = i;
      refresh();
    }

    function hint() {
      if (finished) return;
      const pairs = freePairs();
      if (!pairs.length) { showStuck(); return; }
      clearHint();
      const [a, b] = pairs[(Math.random() * pairs.length) | 0];
      tileEls[a].classList.add('hint'); tileEls[b].classList.add('hint');
      hintTimer = setTimeout(clearHint, 1800);
    }

    function undo() {
      if (finished || !history.length) return;
      clearHint();
      const h = history.pop();
      if (h.t === 'p') { present[h.a] = 1; present[h.b] = 1; }
      else { faces = h.faces; renderFaces(); }
      selected = -1;
      stuck = false;
      overlay.classList.add('hidden');
      afterChange();
    }

    function doShuffle() {
      if (finished || shufflesLeft <= 0) return;
      clearHint();
      const idxs = [];
      for (let i = 0; i < L.n; i++) if (present[i]) idxs.push(i);
      const byKind = new Map();
      for (const i of idxs) {
        const k = kindOf(faces[i]);
        if (!byKind.has(k)) byKind.set(k, []);
        byKind.get(k).push(faces[i]);
      }
      const pairs = [];
      byKind.forEach(list => { shuffle(list); for (let j = 0; j + 1 < list.length; j += 2) pairs.push([list[j], list[j + 1]]); });
      let res = null;
      for (let t = 0; t < 400 && !res; t++) res = tryAssign(L, idxs, shuffle(pairs));
      history.push({ t: 's', faces: faces.slice() });
      const next = faces.slice();
      if (res) res.forEach((f, i) => { next[i] = f; });
      else {
        const pool = shuffle(idxs.map(i => faces[i]));
        idxs.forEach((i, k) => { next[i] = pool[k]; });
      }
      faces = next;
      shufflesLeft--;
      selected = -1;
      stuck = false;
      overlay.classList.add('hidden');
      renderFaces();
      board.classList.remove('mj-shuffling');
      void board.offsetWidth;
      board.classList.add('mj-shuffling');
      ctx.toast(res ? `已洗牌，剩余 ${shufflesLeft} 次` : `已洗牌（剩余 ${shufflesLeft} 次），这次可能无解哦`);
      afterChange();
    }

    function tick() {
      const now = performance.now();
      if (started && !finished && ctx.isActive()) {
        elapsed += now - lastTick;
        timeEl.textContent = fmtTime(elapsed);
      }
      lastTick = now;
    }

    // ---------- events ----------
    function onBoard(e) {
      const t = e.target.closest('.mj-t');
      if (t) clickTile(+t.dataset.i);
    }
    function onLay(e) {
      const b = e.target.closest('[data-lay]');
      if (!b) return;
      b.blur();
      const v = +b.dataset.lay;
      if (v === lay) return;
      lay = v; ctx.store.set('layout', lay);
      newGame();
    }
    function onHint(e) { e.currentTarget.blur(); hint(); }
    function onUndo(e) { e.currentTarget.blur(); undo(); }
    function onShuf(e) { e.currentTarget.blur(); doShuffle(); }
    function onNew(e) { e.currentTarget.blur(); newGame(); }
    function onDim(e) { e.currentTarget.blur(); dim = !dim; ctx.store.set('dim', dim); refresh(); }
    function onKey(e) {
      if (!ctx.isActive()) return;
      const tg = e.target && e.target.tagName;
      if (tg === 'INPUT' || tg === 'TEXTAREA' || tg === 'SELECT') return;
      if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); return; }
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.key === 'h' || e.key === 'H') { e.preventDefault(); hint(); }
      else if (e.key === 'n' || e.key === 'N') { e.preventDefault(); newGame(); }
      else if (e.key === 'Escape' && selected >= 0) { selected = -1; refresh(); }
    }

    board.addEventListener('click', onBoard);
    laySeg.addEventListener('click', onLay);
    hintBtn.addEventListener('click', onHint);
    undoBtn.addEventListener('click', onUndo);
    shufBtn.addEventListener('click', onShuf);
    dimBtn.addEventListener('click', onDim);
    newBtn.addEventListener('click', onNew);
    ovShuf.addEventListener('click', onShuf);
    ovUndo.addEventListener('click', onUndo);
    ovNew.addEventListener('click', onNew);
    window.addEventListener('keydown', onKey);

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => fit());
      ro.observe(el.parentElement || el);
    } else {
      window.addEventListener('resize', fit);
    }

    newGame();
    tickTimer = setInterval(tick, 250);

    cleanup = () => {
      clearTimeout(hintTimer); clearTimeout(shakeTimer); clearTimeout(winTimer);
      clearInterval(tickTimer);
      if (ro) ro.disconnect(); else window.removeEventListener('resize', fit);
      window.removeEventListener('keydown', onKey);
      board.removeEventListener('click', onBoard);
      laySeg.removeEventListener('click', onLay);
      hintBtn.removeEventListener('click', onHint);
      undoBtn.removeEventListener('click', onUndo);
      shufBtn.removeEventListener('click', onShuf);
      dimBtn.removeEventListener('click', onDim);
      newBtn.removeEventListener('click', onNew);
      ovShuf.removeEventListener('click', onShuf);
      ovUndo.removeEventListener('click', onUndo);
      ovNew.removeEventListener('click', onNew);
      root.remove();
    };
  }

  Hub.register({
    id: 'mahjong',
    title: '麻将接龙',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M7.5 6V5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1.5"/><rect x="4" y="6" width="11" height="15" rx="2"/><path d="M7 11h5M9.5 9v8M7.5 14.5l4-1.5" stroke-width="1.4"/></svg>',
    mount,
    unmount() { if (cleanup) { cleanup(); cleanup = null; } }
  });
})();
