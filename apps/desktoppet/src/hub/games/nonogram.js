// 数织 (Nonogram / Picross) — hub module. See ../MODULES.md for the contract.
(function () {
  // ---------- built-in puzzles ('#' filled, '.' empty); all verified line-solvable ----------
  const BUILTIN = [
    // 5x5
    { n: '爱心', g: ['.#.#.','#####','#####','.###.','..#..'] },
    { n: '小鱼', g: ['..#..','.##.#','#####','.##.#','..#..'] },
    { n: '蘑菇', g: ['.###.','##.##','#####','..#..','.###.'] },
    { n: '小房子', g: ['..#..','.###.','#####','.#.#.','.###.'] },
    { n: '小伞', g: ['.###.','#####','..#..','..#..','.##..'] },
    { n: '笑脸', g: ['.#.#.','.#.#.','#...#','#...#','.###.'] },
    { n: '小树', g: ['..#..','.###.','#####','..#..','.###.'] },
    { n: '音符', g: ['..###','..#.#','..#..','###..','##...'] },
    // 10x10
    { n: '猫咪脸', g: ['.#......#.','.##....##.','.########.','##########','##.####.##','##.####.##','##########','####..####','.########.','..######..'] },
    { n: '热带鱼', g: ['..........','...###...#','..#####.##','.#########','##.#######','##########','.#########','..#####.##','...###...#','..........'] },
    { n: '星星', g: ['....##....','...####...','...####...','##########','.########.','..######..','..######..','.###..###.','.##....##.','.#......#.'] },
    { n: '猫爪印', g: ['..##..##..','..##..##..','##......##','##..##..##','...####...','..######..','.########.','.########.','..##..##..','..........'] },
    { n: '咖啡杯', g: ['..#..#....','...#..#...','..#..#....','#######...','#########.','#######.#.','#########.','#######...','.#####....','##########'] },
    { n: '小雨伞', g: ['....#.....','..#####...','.#######..','#########.','#########.','#.#.#.#.#.','....#.....','....#.....','.#..#.....','..##......'] },
    { n: '苹果', g: ['.....##...','....##....','.###..###.','##########','##########','##########','##########','.########.','.########.','..##..##..'] },
    { n: '小兔子', g: ['.##...##..','.##...##..','.##...##..','.##...##..','.#######..','#########.','##.###.##.','#########.','###...###.','.#######..'] },
    { n: '弯月亮', g: ['..####....','.###......','###.......','###.......','###.......','###.......','###......#','.###....##','..########','...######.'] },
    { n: '小花', g: ['...####...','.##....##.','##..##..##','##.####.##','.##.##.##.','...####...','....##....','.##.##.##.','..######..','....##....'] },
    { n: '鲸鱼', g: ['..#.#.....','...#......','...#.....#','.######.##','#########.','#.#######.','#########.','.#######..','...####...','..........'] },
    { n: '铃铛', g: ['....##....','...####...','..######..','..######..','..######..','.########.','.########.','##########','....##....','..........'] },
    // 15x15
    { n: '大猫咪', g: [
      '##...........##',
      '.##.........##.',
      '.###.......###.',
      '.####.....####.',
      '.#############.',
      '###############',
      '###..#####..###',
      '###..#####..###',
      '###############',
      '######...######',
      '#######.#######',
      '.#####.#.#####.',
      '.#############.',
      '..###########..',
      '....#######....'
    ] },
    { n: '小熊', g: [
      '.###.......###.',
      '#####.....#####',
      '##.#########.##',
      '###############',
      '.#############.',
      '.###..###..###.',
      '.###..###..###.',
      '.#############.',
      '.#####...#####.',
      '.####.....####.',
      '.####.###.####.',
      '.####..#..####.',
      '..####...####..',
      '...#########...',
      '.....#####.....'
    ] },
    { n: '大蘑菇', g: [
      '.....#####.....',
      '...#########...',
      '..###..###..#..',
      '.###....#....#.',
      '.####..###..##.',
      '###############',
      '##..#######..##',
      '#....#####....#',
      '##..#######..##',
      '###############',
      '....#######....',
      '....#.#.#.#....',
      '....#######....',
      '....#######....',
      '.....#####.....'
    ] },
    { n: '温馨小屋', g: [
      '..........##...',
      '......#...##...',
      '.....###..##...',
      '....#####.##...',
      '...#########...',
      '..###########..',
      '.#############.',
      '###############',
      '.#...........#.',
      '.#.###...###.#.',
      '.#.#.#...#.#.#.',
      '.#.###.#.###.#.',
      '.#.....#.....#.',
      '.#.....#.....#.',
      '###############'
    ] },
    { n: '下午茶', g: [
      '....#..#..#....',
      '...#..#..#.....',
      '....#..#..#....',
      '...............',
      '.###########...',
      '.#.........####',
      '.###########..#',
      '.###########..#',
      '.###########..#',
      '.###########.##',
      '..#########.##.',
      '..##########...',
      '...#######.....',
      '###############',
      '.#############.'
    ] },
    { n: '大雨伞', g: [
      '.......#.......',
      '.....#####.....',
      '...#########...',
      '..###########..',
      '.#############.',
      '.#############.',
      '###############',
      '#..#..###..#..#',
      '.......#.......',
      '.......#.......',
      '.......#.......',
      '.......#.......',
      '...#...#.......',
      '...##..#.......',
      '....###........'
    ] },
    { n: '金鱼', g: [
      '.....###.......',
      '....#####......',
      '...#######...##',
      '..#########.###',
      '.###########.##',
      '##.#########.#.',
      '#############..',
      '##.#########.#.',
      '.###########.##',
      '..#########.###',
      '...#######...##',
      '....#####......',
      '.....###.......',
      '...............',
      '..#.#..#.#..#..'
    ] },
    { n: '企鹅', g: [
      '.....#####.....',
      '...#########...',
      '..###########..',
      '..##..###..##..',
      '.###.#.#.#.###.',
      '.###..###..###.',
      '.####.....####.',
      '.###...#...###.',
      '##....###....##',
      '##...........##',
      '##...........##',
      '.#...........#.',
      '.##.........##.',
      '..###########..',
      '.####.....####.'
    ] },
    { n: '生日蛋糕', g: [
      '...#...#...#...',
      '..###.###.###..',
      '...#...#...#...',
      '...#...#...#...',
      '.#############.',
      '.#...........#.',
      '.#############.',
      '.#.#.#.#.#.#.#.',
      '.#############.',
      '#.............#',
      '#.#.#.#.#.#.#.#',
      '#.............#',
      '###############',
      '.#############.',
      '...............'
    ] },
    { n: '小鸡', g: [
      '......###......',
      '.....#####.....',
      '....#######....',
      '....##.####....',
      '..#########....',
      '.##########....',
      '...#######.....',
      '...##########..',
      '..############.',
      '.#############.',
      '.#############.',
      '..###########..',
      '...#########...',
      '.....#...#.....',
      '....##..##.....'
    ] },
  ];

  const REWARD = { 5: 3, 10: 6, 15: 10, 20: 14 };
  const GROUPS = [
    { key: '5', size: 5, name: '5×5' },
    { key: '10', size: 10, name: '10×10' },
    { key: '15', size: 15, name: '15×15' }
  ];
  const PET_SIZES = [10, 15, 20];
  const PET_DAILY_MAX = 5;
  const HISTORY_MAX = 300;
  const SAVES_MAX = 40;
  const EMPTY = 0, FILL = 1, MARK = 2;

  const PUZZLES = BUILTIN.map((p, i) => {
    const R = p.g.length, C = p.g[0].length;
    const sol = p.g.join('').split('').map(ch => (ch === '#' ? 1 : 0));
    return { id: 'b' + i, kind: 'builtin', name: p.n, R, C, sol };
  });

  const PET_NAMES = {
    fox: '狐狸', cat: '猫咪', corgi: '柯基', rabbit: '兔子', bear: '小熊', penguin: '企鹅', duck: '鸭子',
    hedgehog: '刺猬', owl: '猫头鹰', deer: '小鹿', panda: '熊猫', hamster: '仓鼠', seal: '海豹', otter: '水獭',
    frog: '青蛙', raccoon: '浣熊', shiba: '柴犬', chick: '小鸡', turtle: '乌龟', squirrel: '松鼠'
  };

  const imgCache = new Map();     // pet file -> data: URL (shared across mounts)
  const pixCache = new Map();     // pet file -> { w, h, data }
  const petPuzCache = new Map();  // file:size -> generated puzzle
  let cleanup = null;

  function petImage(file) {
    if (imgCache.has(file)) return imgCache.get(file);
    let url = '';
    try { url = (window.api && window.api.petImage(file)) || ''; } catch (_) { url = ''; }
    imgCache.set(file, url);
    return url;
  }
  function petList() {
    try { return ((window.api && window.api.pets()) || []).slice(); } catch (_) { return []; }
  }
  function petLabel(file) {
    const key = String(file).replace(/\.png$/i, '').replace(/^\d+-/, '').toLowerCase();
    return PET_NAMES[key] || key || '宠物';
  }

  function fmtTime(ms) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
  function today() {
    const d = new Date();
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }
  function esc(s) {
    return String(s).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  }

  // ---------- line solver ----------
  // clue: block lengths; line: -1 unknown / 0 empty / 1 filled.
  // Returns the line with every cell that is identical in all consistent placements set, or null on contradiction.
  function solveLine(clue, line) {
    const n = line.length, k = clue.length;
    const memo = [];
    for (let i = 0; i <= n + 1; i++) memo.push(new Int8Array(k + 1).fill(-1));
    const fillAfter = new Uint8Array(n + 1);   // any known-filled cell in [i, n)
    for (let i = n - 1; i >= 0; i--) fillAfter[i] = fillAfter[i + 1] || line[i] === 1 ? 1 : 0;
    const zeros = new Int32Array(n + 1);        // prefix count of known-empty cells
    for (let i = 0; i < n; i++) zeros[i + 1] = zeros[i] + (line[i] === 0 ? 1 : 0);
    const canBlock = (i, L) => i + L <= n && zeros[i + L] === zeros[i] && (i + L === n || line[i + L] !== 1);
    // f(i, j): can cells [i, n) hold blocks j..k-1
    function f(i, j) {
      if (i > n) return false;
      const m = memo[i][j];
      if (m !== -1) return m === 1;
      let r;
      if (j === k) r = i >= n || !fillAfter[i];
      else if (i >= n) r = false;
      else {
        r = line[i] !== 1 && f(i + 1, j);
        if (!r && canBlock(i, clue[j])) {
          const e = i + clue[j];
          r = e === n ? j + 1 === k : f(e + 1, j + 1);
        }
      }
      memo[i][j] = r ? 1 : 0;
      return r;
    }
    if (!f(0, 0)) return null;
    const canE = new Uint8Array(n), canF = new Uint8Array(n);
    const reach = [];
    for (let i = 0; i <= n + 1; i++) reach.push(new Uint8Array(k + 1));
    reach[0][0] = 1;
    for (let i = 0; i <= n; i++) {
      for (let j = 0; j <= k; j++) {
        if (!reach[i][j] || !f(i, j)) continue;
        if (j === k) { for (let x = i; x < n; x++) canE[x] = 1; continue; }
        if (i >= n) continue;
        if (line[i] !== 1 && f(i + 1, j)) { canE[i] = 1; reach[i + 1][j] = 1; }
        if (canBlock(i, clue[j])) {
          const e = i + clue[j];
          if (e === n) {
            if (j + 1 === k) for (let x = i; x < e; x++) canF[x] = 1;
          } else if (f(e + 1, j + 1)) {
            for (let x = i; x < e; x++) canF[x] = 1;
            canE[e] = 1;
            reach[e + 1][j + 1] = 1;
          }
        }
      }
    }
    const out = line.slice();
    for (let x = 0; x < n; x++) {
      if (canE[x] && !canF[x]) out[x] = 0;
      else if (canF[x] && !canE[x]) out[x] = 1;
      else if (!canE[x] && !canF[x]) return null;
    }
    return out;
  }

  function lineClue(arr) {
    const c = [];
    let run = 0;
    for (const v of arr) {
      if (v === 1) run++;
      else if (run) { c.push(run); run = 0; }
    }
    if (run) c.push(run);
    return c;
  }
  function makeClues(sol, R, C) {
    const rows = [], cols = [];
    for (let r = 0; r < R; r++) rows.push(lineClue(sol.slice(r * C, r * C + C)));
    for (let c = 0; c < C; c++) {
      const a = [];
      for (let r = 0; r < R; r++) a.push(sol[r * C + c]);
      cols.push(lineClue(a));
    }
    return { rows, cols };
  }
  // Iterate the line solver over all rows/columns to a fixpoint.
  function solveGrid(rows, cols, start) {
    const R = rows.length, C = cols.length;
    const g = start ? start.slice() : new Array(R * C).fill(-1);
    const dirty = new Uint8Array(R + C).fill(1);
    let changed = true;
    while (changed) {
      changed = false;
      for (let l = 0; l < R + C; l++) {
        if (!dirty[l]) continue;
        dirty[l] = 0;
        const isRow = l < R, idx = isRow ? l : l - R, len = isRow ? C : R;
        const line = [];
        for (let i = 0; i < len; i++) line.push(g[isRow ? idx * C + i : i * C + idx]);
        const res = solveLine(isRow ? rows[idx] : cols[idx], line);
        if (!res) return { ok: false, solved: false, grid: g };
        for (let i = 0; i < len; i++) {
          if (res[i] !== line[i]) {
            g[isRow ? idx * C + i : i * C + idx] = res[i];
            changed = true;
            dirty[isRow ? R + i : i] = 1;
          }
        }
      }
    }
    return { ok: true, solved: g.every(v => v !== -1), grid: g };
  }
  const sameClue = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

  // ---------- pet puzzle generation ----------
  function loadPetPixels(file, cb) {
    if (pixCache.has(file)) { cb(pixCache.get(file)); return; }
    const url = petImage(file);
    if (!url) { cb(null); return; }
    const img = new Image();
    img.onload = () => {
      try {
        const w = img.naturalWidth || 320, h = img.naturalHeight || 320;
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        const g = cv.getContext('2d', { willReadFrequently: true });
        g.drawImage(img, 0, 0);
        const px = { w, h, data: g.getImageData(0, 0, w, h).data };
        pixCache.set(file, px);
        cb(px);
      } catch (_) { cb(null); }
    };
    img.onerror = () => cb(null);
    img.src = url;
  }

  // Average alpha and luminance per cell over the square crop around the opaque artwork.
  function sampleCells(px, N) {
    const { w, h, data } = px;
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (data[(y * w + x) * 4 + 3] > 40) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) { x0 = 0; y0 = 0; x1 = w - 1; y1 = h - 1; }
    const bw = x1 - x0 + 1, bh = y1 - y0 + 1, S = Math.max(bw, bh);
    const ox = x0 - (S - bw) / 2, oy = y0 - (S - bh) / 2;
    const A = new Float32Array(N * N), L = new Float32Array(N * N);
    for (let r = 0; r < N; r++) {
      for (let c = 0; c < N; c++) {
        let sa = 0, sl = 0, n = 0;
        const ya = oy + r * S / N, yb = oy + (r + 1) * S / N, xa = ox + c * S / N, xb = ox + (c + 1) * S / N;
        for (let y = Math.floor(ya); y < Math.ceil(yb); y++) {
          for (let x = Math.floor(xa); x < Math.ceil(xb); x++) {
            n++;
            if (x < 0 || y < 0 || x >= w || y >= h) continue;
            const i = (y * w + x) * 4, a = data[i + 3] / 255;
            sa += a;
            sl += a * (0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]) / 255;
          }
        }
        A[r * N + c] = n ? sa / n : 0;
        L[r * N + c] = sa > 0 ? sl / sa : 1;
      }
    }
    return { A, L, crop: { x: ox, y: oy, s: S, w, h } };
  }

  function genPetPuzzle(file, N, cb) {
    const key = file + ':' + N;
    if (petPuzCache.has(key)) { cb(petPuzCache.get(key)); return; }
    loadPetPixels(file, px => {
      if (!px) { cb(null); return; }
      const { A, L, crop } = sampleCells(px, N);
      // luminance stats of the opaque area: clearly dark cells (eyes, nose, dark fur) become holes
      let sum = 0, cnt = 0;
      for (let i = 0; i < A.length; i++) if (A[i] > 0.3) { sum += L[i]; cnt++; }
      const mean = cnt ? sum / cnt : 0.5;
      let v2 = 0;
      for (let i = 0; i < A.length; i++) if (A[i] > 0.3) v2 += (L[i] - mean) * (L[i] - mean);
      const sd = cnt ? Math.sqrt(v2 / cnt) : 0;
      let fallback = null, found = null;
      outer:
      for (const k of [1.0, 1.3, 1.7, Infinity]) {          // darkness threshold (in std devs)
        for (const a of [0.5, 0.4, 0.6, 0.3, 0.7]) {         // alpha threshold
          const sol = Array.from(A, (v, i) => (v >= a && !(L[i] < mean - k * sd) ? 1 : 0));
          const density = sol.reduce((s, v) => s + v, 0) / sol.length;
          if (density < 0.2 || density > 0.85) continue;       // nearly empty / full
          if (!fallback) fallback = sol;
          const { rows, cols } = makeClues(sol, N, N);
          if (solveGrid(rows, cols).solved) { found = sol; break outer; }
        }
      }
      const guess = !found;
      const sol = found || fallback || Array.from(A, v => (v >= 0.5 ? 1 : 0));
      const p = { id: 'pet:' + file + ':' + N, kind: 'pet', pet: file, name: petLabel(file), R: N, C: N, sol, guess, crop };
      petPuzCache.set(key, p);
      cb(p);
    });
  }

  function drawThumb(canvas, p, sizePx) {
    const cs = Math.max(1, Math.floor(sizePx / Math.max(p.R, p.C)));
    canvas.width = cs * p.C;
    canvas.height = cs * p.R;
    const g = canvas.getContext('2d');
    g.fillStyle = '#6b3f24';
    for (let r = 0; r < p.R; r++) {
      for (let c = 0; c < p.C; c++) if (p.sol[r * p.C + c]) g.fillRect(c * cs, r * cs, cs, cs);
    }
  }

  // ---------- module ----------
  function mount(el, ctx) {
    const root = document.createElement('div');
    root.className = 'ng-root';
    root.innerHTML = `
      <div class="ng-select">
        <div class="ng-head">
          <div class="ng-seg ng-tabs">
            ${GROUPS.map(g => `<button type="button" data-tab="${g.key}">${g.name}</button>`).join('')}
            <button type="button" data-tab="pet">宠物图</button>
          </div>
          <div class="ng-summary"></div>
        </div>
        <div class="ng-petbar hidden">
          <div class="ng-seg ng-psize">
            ${PET_SIZES.map(s => `<button type="button" data-psize="${s}">${s}×${s}</button>`).join('')}
          </div>
          <button type="button" class="ng-btn ng-primary ng-random">随机一只</button>
          <span class="ng-daily"></span>
        </div>
        <div class="ng-list"></div>
      </div>
      <div class="ng-play hidden">
        <div class="ng-bar">
          <button type="button" class="ng-btn ng-back" title="返回列表 (Esc)">‹ 返回</button>
          <div class="ng-title"></div>
          <div class="ng-stats">
            <div class="ng-stat"><span>用时</span><b class="ng-time">0:00</b></div>
            <div class="ng-stat ng-miss-box"><span>失误</span><b class="ng-miss">0</b></div>
            <div class="ng-stat"><span>提示</span><b class="ng-hints">0</b></div>
          </div>
        </div>
        <div class="ng-tools">
          <div class="ng-seg ng-mode" title="触控板用户可切换左键的作用 (X 键)">
            <button type="button" data-mode="fill"><i class="ng-ico-fill"></i>填充</button>
            <button type="button" data-mode="mark"><i class="ng-ico-mark"></i>标记</button>
          </div>
          <button type="button" class="ng-btn ng-undo" title="撤销 (Ctrl+Z)">撤销</button>
          <button type="button" class="ng-btn ng-check" title="标出当前的错误格">检查</button>
          <button type="button" class="ng-btn ng-hint" title="揭示一步逻辑推理">提示</button>
          <button type="button" class="ng-btn ng-reset">重置</button>
          <button type="button" class="ng-btn ng-mm" title="开启后填错会立即被标记并计为失误"></button>
        </div>
        <div class="ng-winbar hidden">
          <div class="ng-win-text"><b class="ng-win-name"></b><span class="ng-win-sub"></span></div>
          <div class="ng-win-btns">
            <button type="button" class="ng-btn ng-primary ng-next">下一题</button>
            <button type="button" class="ng-btn ng-back2">返回列表</button>
          </div>
        </div>
        <div class="ng-stage">
          <div class="ng-board">
            <div class="ng-corner"></div>
            <div class="ng-colclues"></div>
            <div class="ng-rowclues"></div>
            <div class="ng-gridwrap">
              <div class="ng-grid"></div>
              <div class="ng-pic"><img alt="" draggable="false"></div>
            </div>
          </div>
        </div>
        <div class="ng-help">左键填充 · 右键标记 × · 按住拖动可连续涂抹（锁定同一行/列）· Ctrl+Z 撤销</div>
      </div>
    `;
    el.appendChild(root);

    const $ = s => root.querySelector(s);
    const selectEl = $('.ng-select'), playEl = $('.ng-play');
    const tabBtns = [...root.querySelectorAll('[data-tab]')];
    const psizeBtns = [...root.querySelectorAll('[data-psize]')];
    const summaryEl = $('.ng-summary'), petbar = $('.ng-petbar'), dailyEl = $('.ng-daily'), listEl = $('.ng-list');
    const randomBtn = $('.ng-random');
    const titleEl = $('.ng-title'), timeEl = $('.ng-time'), missEl = $('.ng-miss'), missBox = $('.ng-miss-box'), hintsEl = $('.ng-hints');
    const toolsEl = $('.ng-tools'), modeBtns = [...root.querySelectorAll('[data-mode]')];
    const undoBtn = $('.ng-undo'), checkBtn = $('.ng-check'), hintBtn = $('.ng-hint'), resetBtn = $('.ng-reset'), mmBtn = $('.ng-mm');
    const backBtn = $('.ng-back'), back2Btn = $('.ng-back2'), nextBtn = $('.ng-next');
    const winbar = $('.ng-winbar'), winName = $('.ng-win-name'), winSub = $('.ng-win-sub');
    const stage = $('.ng-stage'), board = $('.ng-board'), colCluesEl = $('.ng-colclues'), rowCluesEl = $('.ng-rowclues');
    const gridEl = $('.ng-grid'), picEl = $('.ng-pic'), picImg = picEl.querySelector('img');

    // ---------- persistent state ----------
    let tab = ctx.store.get('tab', '5');
    if (!GROUPS.some(g => g.key === tab) && tab !== 'pet') tab = '5';
    let petSize = ctx.store.get('petSize', 10);
    if (!PET_SIZES.includes(petSize)) petSize = 10;
    let mistakesMode = !!ctx.store.get('mistakesMode', false);
    let toolMode = ctx.store.get('toolMode', 'fill') === 'mark' ? 'mark' : 'fill';
    const solvedMap = Object.assign({}, ctx.store.get('solved', {}));   // id -> { time }
    const saves = Object.assign({}, ctx.store.get('saves', {}));        // id -> { c, t, m, h, u }

    // ---------- game state ----------
    let alive = true;
    let screen = 'select';
    let puz = null, clues = null;
    let cells = [];                 // EMPTY / FILL / MARK
    let cellEls = [], rowClueEls = [], colClueEls = [];
    let rowDone = [], colDone = [];
    let history = [];
    let stroke = null;
    let hover = null;               // { r, c }
    let elapsed = 0, lastTick = 0, started = false, finished = false;
    let mistakes = 0, hints = 0;
    let cs = 24;                    // cell pitch px
    let tickTimer = 0, resetArmTimer = 0, picTimer = 0, winbarTimer = 0;
    const flashTimers = new Set();

    const later = (fn, ms) => {
      const t = setTimeout(() => { flashTimers.delete(t); fn(); }, ms);
      flashTimers.add(t);
      return t;
    };

    // ---------- select screen ----------
    function renderSelect() {
      tabBtns.forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
      psizeBtns.forEach(b => b.classList.toggle('active', +b.dataset.psize === petSize));
      const doneCount = PUZZLES.filter(p => solvedMap[p.id]).length;
      summaryEl.textContent = `已完成 ${doneCount} / ${PUZZLES.length}`;
      petbar.classList.toggle('hidden', tab !== 'pet');
      listEl.innerHTML = '';
      listEl.className = 'ng-list' + (tab === 'pet' ? ' ng-list-pet' : '');
      if (tab === 'pet') {
        const d = ctx.store.get('petDaily', { d: '', n: 0 });
        const n = d.d === today() ? d.n : 0;
        dailyEl.textContent = `今日宠物图奖励 ${n} / ${PET_DAILY_MAX}`;
        const pets = petList();
        if (!pets.length) {
          listEl.innerHTML = '<div class="ng-empty">没有找到宠物图片</div>';
          return;
        }
        pets.forEach(file => {
          const id = 'pet:' + file + ':' + petSize;
          const rec = solvedMap[id];
          const b = document.createElement('button');
          b.type = 'button';
          b.className = 'ng-card' + (rec ? ' ng-solved' : '');
          b.dataset.pet = file;
          b.innerHTML = `<div class="ng-thumb ng-thumb-pet"><img alt="" draggable="false"></div>
            <div class="ng-card-name">${esc(petLabel(file))}</div>
            <div class="ng-card-sub">${rec ? '最佳 ' + fmtTime(rec.time) : saves[id] ? '<span class="ng-prog">进行中</span>' : petSize + '×' + petSize}</div>`;
          b.querySelector('img').src = petImage(file);
          listEl.appendChild(b);
        });
        return;
      }
      const size = +tab;
      PUZZLES.forEach((p, idx) => {
        if (p.R !== size) return;
        const rec = solvedMap[p.id];
        const num = PUZZLES.filter((q, j) => q.R === size && j <= idx).length;
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'ng-card' + (rec ? ' ng-solved' : '');
        b.dataset.idx = idx;
        b.innerHTML = `<div class="ng-thumb">${rec ? '<canvas></canvas>' : `<span class="ng-q">?</span>`}</div>
          <div class="ng-card-name">${rec ? esc(p.name) : '第 ' + num + ' 题'}</div>
          <div class="ng-card-sub">${rec ? '最佳 ' + fmtTime(rec.time) : saves[p.id] ? '<span class="ng-prog">进行中</span>' : '未完成'}</div>`;
        if (rec) drawThumb(b.querySelector('canvas'), p, 60);
        listEl.appendChild(b);
      });
    }

    function onListClick(e) {
      const b = e.target.closest('.ng-card');
      if (!b || !listEl.contains(b)) return;
      if (b.dataset.pet) openPet(b.dataset.pet, petSize);
      else openPuzzle(PUZZLES[+b.dataset.idx]);
    }
    function openPet(file, size) {
      genPetPuzzle(file, size, p => {
        if (!alive) return;
        if (!p) { ctx.toast('宠物图片加载失败'); return; }
        openPuzzle(p);
      });
    }
    function randomPet() {
      const pets = petList();
      if (!pets.length) return;
      const unsolved = pets.filter(f => !solvedMap['pet:' + f + ':' + petSize]);
      const pool = unsolved.length ? unsolved : pets;
      openPet(pool[(Math.random() * pool.length) | 0], petSize);
    }

    // ---------- play screen ----------
    function setScreen(s) {
      screen = s;
      selectEl.classList.toggle('hidden', s !== 'select');
      playEl.classList.toggle('hidden', s !== 'play');
    }

    function openPuzzle(p) {
      endStroke(false);
      clearFlashTimers();
      puz = p;
      clues = makeClues(p.sol, p.R, p.C);
      const sv = saves[p.id];
      const n = p.R * p.C;
      cells = new Array(n).fill(EMPTY);
      if (sv && typeof sv.c === 'string' && sv.c.length === n) {
        for (let i = 0; i < n; i++) cells[i] = +sv.c[i] || EMPTY;
        elapsed = sv.t || 0; mistakes = sv.m || 0; hints = sv.h || 0;
        started = cells.some(v => v !== EMPTY) || elapsed > 0;
      } else {
        elapsed = 0; mistakes = 0; hints = 0; started = false;
      }
      history = [];
      finished = false;
      hover = null;
      lastTick = performance.now();
      buildBoard();
      setScreen('play');
      toolsEl.classList.remove('hidden');
      winbar.classList.add('hidden');
      const sizeTxt = `${p.R}×${p.C}`;
      if (p.kind === 'pet') {
        titleEl.innerHTML = `宠物图 · ${sizeTxt}` + (p.guess ? ' <span class="ng-tag" title="这张图无法只靠逻辑推出，可能需要猜测">需要猜测</span>' : '');
      } else {
        const idx = PUZZLES.indexOf(p);
        const num = PUZZLES.filter((q, j) => q.R === p.R && j <= idx).length;
        titleEl.innerHTML = `${sizeTxt} · 第 ${num} 题` + (solvedMap[p.id] ? ` · ${esc(p.name)}` : '');
      }
      updateHud();
      fit();
    }

    function buildBoard() {
      const { R, C } = puz;
      board.classList.remove('ng-won');
      picEl.classList.remove('ng-show');
      picImg.removeAttribute('src');
      picEl.classList.toggle('ng-haspic', puz.kind === 'pet');
      colCluesEl.innerHTML = '';
      rowCluesEl.innerHTML = '';
      gridEl.innerHTML = '';
      colCluesEl.style.gridTemplateColumns = `repeat(${C}, var(--ng-cs))`;
      rowCluesEl.style.gridTemplateRows = `repeat(${R}, var(--ng-cs))`;
      gridEl.style.gridTemplateColumns = `repeat(${C}, var(--ng-cs))`;
      colClueEls = clues.cols.map((cl, c) => {
        const d = document.createElement('div');
        d.className = 'ng-cc' + (c % 5 === 4 && c < C - 1 ? ' ng-g5r' : '');
        d.innerHTML = (cl.length ? cl : [0]).map(v => `<span>${v}</span>`).join('');
        colCluesEl.appendChild(d);
        return d;
      });
      rowClueEls = clues.rows.map((cl, r) => {
        const d = document.createElement('div');
        d.className = 'ng-rc' + (r % 5 === 4 && r < R - 1 ? ' ng-g5b' : '');
        d.innerHTML = (cl.length ? cl : [0]).map(v => `<span>${v}</span>`).join('');
        rowCluesEl.appendChild(d);
        return d;
      });
      const frag = document.createDocumentFragment();
      cellEls = [];
      for (let r = 0; r < R; r++) {
        for (let c = 0; c < C; c++) {
          const d = document.createElement('div');
          let cls = 'ng-cell';
          if (c % 5 === 4 && c < C - 1) cls += ' ng-g5r';
          if (r % 5 === 4 && r < R - 1) cls += ' ng-g5b';
          if (c === C - 1) cls += ' ng-lastc';
          if (r === R - 1) cls += ' ng-lastr';
          d.className = cls;
          d.style.setProperty('--ng-d', ((r + c) * (300 / (R + C))) + 'ms');
          frag.appendChild(d);
          cellEls.push(d);
        }
      }
      gridEl.appendChild(frag);
      for (let i = 0; i < cells.length; i++) paintCell(i);
      rowDone = new Array(R).fill(false);
      colDone = new Array(C).fill(false);
      for (let r = 0; r < R; r++) updateLine(true, r);
      for (let c = 0; c < C; c++) updateLine(false, c);
    }

    function paintCell(i) {
      const d = cellEls[i];
      d.classList.toggle('ng-f', cells[i] === FILL);
      d.classList.toggle('ng-x', cells[i] === MARK);
    }

    function lineCells(isRow, idx) {
      const { R, C } = puz;
      const out = [];
      if (isRow) for (let c = 0; c < C; c++) out.push(idx * C + c);
      else for (let r = 0; r < R; r++) out.push(r * C + idx);
      return out;
    }
    function updateLine(isRow, idx) {
      const pattern = lineCells(isRow, idx).map(i => (cells[i] === FILL ? 1 : 0));
      const done = sameClue(lineClue(pattern), isRow ? clues.rows[idx] : clues.cols[idx]);
      if (isRow) rowDone[idx] = done; else colDone[idx] = done;
      (isRow ? rowClueEls : colClueEls)[idx].classList.toggle('ng-done', done);
    }
    function updateLinesFor(indices) {
      const rs = new Set(), cs2 = new Set();
      indices.forEach(i => { rs.add((i / puz.C) | 0); cs2.add(i % puz.C); });
      rs.forEach(r => updateLine(true, r));
      cs2.forEach(c => updateLine(false, c));
    }

    function fit() {
      if (!puz || screen !== 'play') return;
      const { R, C } = puz;
      const maxR = Math.max(1, ...clues.rows.map(c => c.length || 1));
      const maxC = Math.max(1, ...clues.cols.map(c => c.length || 1));
      const host = el.parentElement || el;
      const st = getComputedStyle(el);
      const padY = (parseFloat(st.paddingTop) || 0) + (parseFloat(st.paddingBottom) || 0);
      const chrome = root.offsetHeight - stage.offsetHeight;
      const aw = Math.max(200, stage.clientWidth - 8);
      const ah = Math.max(200, (host.clientHeight || 600) - padY - chrome - 12);
      let pick = 12, fs = 10, rw = 0, ch = 0;
      for (let s = 44; s >= 12; s--) {
        const f = Math.max(10, Math.min(15, Math.round(s * 0.52)));
        const w = Math.ceil(maxR * f * 1.25 + 10);
        const h = Math.ceil(maxC * f * 1.2 + 8);
        pick = s; fs = f; rw = w; ch = h;
        if (s * C + w + 6 <= aw && s * R + h + 6 <= ah) break;
      }
      cs = pick;
      board.style.setProperty('--ng-cs', cs + 'px');
      board.style.setProperty('--ng-fs', fs + 'px');
      board.style.setProperty('--ng-rw', rw + 'px');
      board.style.setProperty('--ng-ch', ch + 'px');
      if (puz.kind === 'pet' && puz.crop) {
        const k = (cs * C) / puz.crop.s;
        picImg.style.width = (puz.crop.w * k) + 'px';
        picImg.style.height = (puz.crop.h * k) + 'px';
        picImg.style.left = (-puz.crop.x * k) + 'px';
        picImg.style.top = (-puz.crop.y * k) + 'px';
      }
    }

    function updateHud() {
      timeEl.textContent = fmtTime(elapsed);
      missEl.textContent = mistakes;
      hintsEl.textContent = hints;
      missBox.classList.toggle('hidden', !mistakesMode && !mistakes);
      mmBtn.textContent = '纠错模式：' + (mistakesMode ? '开' : '关');
      mmBtn.classList.toggle('active', mistakesMode);
      modeBtns.forEach(b => b.classList.toggle('active', b.dataset.mode === toolMode));
      undoBtn.disabled = !history.length || finished;
    }

    function tick() {
      const now = performance.now();
      if (screen === 'play' && started && !finished && ctx.isActive()) {
        elapsed += now - lastTick;
        timeEl.textContent = fmtTime(elapsed);
      }
      lastTick = now;
    }

    function saveProgress() {
      if (!puz || finished) return;
      const any = cells.some(v => v !== EMPTY);
      if (!any && !elapsed) delete saves[puz.id];
      else saves[puz.id] = { c: cells.join(''), t: Math.round(elapsed), m: mistakes, h: hints, u: Date.now() };
      const keys = Object.keys(saves);
      if (keys.length > SAVES_MAX) {
        keys.sort((a, b) => (saves[a].u || 0) - (saves[b].u || 0));
        keys.slice(0, keys.length - SAVES_MAX).forEach(k => delete saves[k]);
      }
      ctx.store.set('saves', saves);
    }

    function startTimer() {
      if (!started) { started = true; lastTick = performance.now(); }
    }

    function flash(i, cls, ms) {
      const d = cellEls[i];
      if (!d) return;
      d.classList.remove(cls);
      void d.offsetWidth;
      d.classList.add(cls);
      later(() => d.classList.remove(cls), ms);
    }
    function flashClue(isRow, idx) {
      const d = (isRow ? rowClueEls : colClueEls)[idx];
      if (!d) return;
      d.classList.add('ng-hintline');
      later(() => d.classList.remove('ng-hintline'), 1600);
    }
    function clearFlashTimers() {
      flashTimers.forEach(t => clearTimeout(t));
      flashTimers.clear();
      clearTimeout(picTimer); picTimer = 0;
      clearTimeout(winbarTimer); winbarTimer = 0;
    }

    // ---------- input: painting ----------
    function cellFromEvent(e) {
      const rect = gridEl.getBoundingClientRect();
      const x = e.clientX - rect.left - gridEl.clientLeft;
      const y = e.clientY - rect.top - gridEl.clientTop;
      const c = Math.floor(x / cs), r = Math.floor(y / cs);
      return { r, c, inside: r >= 0 && c >= 0 && r < puz.R && c < puz.C };
    }

    function applyCell(i) {
      if (stroke.dead) return;
      const cur = cells[i];
      let next;
      if (stroke.target === EMPTY) {
        if (cur !== stroke.action) return;
        next = EMPTY;
      } else {
        if (cur !== EMPTY) return;
        next = stroke.target;
        if (next === FILL && mistakesMode && !puz.sol[i]) {
          next = MARK;
          mistakes++;
          stroke.dead = true;
          flash(i, 'ng-err', 900);
        }
      }
      if (!stroke.changes.has(i)) stroke.changes.set(i, cur);
      cells[i] = next;
      paintCell(i);
      updateLinesFor([i]);
      startTimer();
    }

    function paintTo(r, c) {
      const s = stroke;
      if (s.axis === null && (r !== s.r0 || c !== s.c0)) {
        s.axis = Math.abs(r - s.r0) > Math.abs(c - s.c0) ? 'col' : 'row';
      }
      if (s.axis === 'row') r = s.r0;
      else if (s.axis === 'col') c = s.c0;
      r = Math.max(0, Math.min(puz.R - 1, r));
      c = Math.max(0, Math.min(puz.C - 1, c));
      if (r === s.lr && c === s.lc) return;
      s.lr = r; s.lc = c;
      if (s.axis === 'row') {
        const a = Math.min(s.c0, c), b = Math.max(s.c0, c);
        for (let x = a; x <= b; x++) applyCell(r * puz.C + x);
      } else if (s.axis === 'col') {
        const a = Math.min(s.r0, r), b = Math.max(s.r0, r);
        for (let y = a; y <= b; y++) applyCell(y * puz.C + c);
      } else {
        applyCell(r * puz.C + c);
      }
    }

    function onGridDown(e) {
      if (!puz || finished || screen !== 'play') return;
      if (e.button !== 0 && e.button !== 2) return;
      e.preventDefault();
      endStroke(true);
      const p = cellFromEvent(e);
      if (!p.inside) return;
      const primary = toolMode === 'fill' ? FILL : MARK;
      const secondary = primary === FILL ? MARK : FILL;
      const action = e.button === 2 ? secondary : primary;
      const i = p.r * puz.C + p.c;
      stroke = {
        pointerId: e.pointerId, r0: p.r, c0: p.c, lr: -1, lc: -1, axis: null,
        action, target: cells[i] === action ? EMPTY : action, changes: new Map(), dead: false
      };
      try { gridEl.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
      paintTo(p.r, p.c);
      setHover(p.r, p.c);
    }

    function onGridMove(e) {
      if (!puz || screen !== 'play') return;
      const p = cellFromEvent(e);
      if (stroke && stroke.pointerId === e.pointerId) {
        paintTo(p.r, p.c);
        const r = stroke.axis === 'row' ? stroke.r0 : p.r, c = stroke.axis === 'col' ? stroke.c0 : p.c;
        setHover(Math.max(0, Math.min(puz.R - 1, r)), Math.max(0, Math.min(puz.C - 1, c)));
      } else if (p.inside && !finished) {
        setHover(p.r, p.c);
      } else {
        setHover(-1, -1);
      }
    }

    function onGridUp(e) {
      if (stroke && (e.pointerId === undefined || stroke.pointerId === e.pointerId)) endStroke(true);
    }
    function onGridLeave() {
      if (!stroke) setHover(-1, -1);
    }

    function endStroke(commit) {
      if (!stroke) return;
      const s = stroke;
      stroke = null;
      try { gridEl.releasePointerCapture(s.pointerId); } catch (_) { /* ignore */ }
      if (!commit || !s.changes.size) { if (s.dead) { updateHud(); saveProgress(); } return; }
      const entry = [];
      s.changes.forEach((prev, i) => { if (prev !== cells[i]) entry.push([i, prev, cells[i]]); });
      if (entry.length) pushHistory(entry);
      updateHud();
      saveProgress();
      checkWin();
    }

    function pushHistory(entry) {
      history.push(entry);
      if (history.length > HISTORY_MAX) history.shift();
    }

    function setHover(r, c) {
      const prev = hover;
      if (prev && prev.r === r && prev.c === c) return;
      if (prev) toggleHl(prev.r, prev.c, false);
      hover = r >= 0 && c >= 0 ? { r, c } : null;
      if (hover) toggleHl(r, c, true);
    }
    function toggleHl(r, c, on) {
      if (!puz) return;
      const { R, C } = puz;
      if (r >= 0 && r < R) {
        rowClueEls[r] && rowClueEls[r].classList.toggle('ng-hl', on);
        for (let x = 0; x < C; x++) cellEls[r * C + x] && cellEls[r * C + x].classList.toggle('ng-hl', on);
      }
      if (c >= 0 && c < C) {
        colClueEls[c] && colClueEls[c].classList.toggle('ng-hl', on);
        for (let y = 0; y < R; y++) cellEls[y * C + c] && cellEls[y * C + c].classList.toggle('ng-hl', on);
      }
    }

    // ---------- actions ----------
    function undo() {
      if (!puz || finished || !history.length) return;
      endStroke(true);
      const entry = history.pop();
      if (!entry) return;
      entry.forEach(([i, prev]) => { cells[i] = prev; paintCell(i); });
      updateLinesFor(entry.map(x => x[0]));
      updateHud();
      saveProgress();
    }

    function errorCells() {
      const out = [];
      for (let i = 0; i < cells.length; i++) {
        if ((cells[i] === FILL && !puz.sol[i]) || (cells[i] === MARK && puz.sol[i])) out.push(i);
      }
      return out;
    }

    function check() {
      if (!puz || finished) return;
      const errs = errorCells();
      errs.forEach(i => flash(i, 'ng-err', 1600));
      if (!errs.length) {
        const left = cells.reduce((n, v, i) => n + (v !== FILL && puz.sol[i] ? 1 : 0), 0);
        ctx.toast(`目前没有错误，还差 ${left} 格`);
      } else {
        ctx.toast(`发现 ${errs.length} 处错误`);
      }
    }

    function setCell(i, v, entry) {
      if (cells[i] === v) return;
      entry.push([i, cells[i], v]);
      cells[i] = v;
      paintCell(i);
    }

    function hint() {
      if (!puz || finished) return;
      endStroke(true);
      const entry = [];
      const errs = errorCells();
      if (errs.length) {
        const i = errs[(Math.random() * errs.length) | 0];
        setCell(i, EMPTY, entry);
        flash(i, 'ng-hintcell', 1600);
        ctx.toast('这一格有误，已帮你清除');
      } else {
        const known = cells.map(v => (v === FILL ? 1 : v === MARK ? 0 : -1));
        const { R, C } = puz;
        let best = null;
        for (let l = 0; l < R + C && !best; l++) {
          const isRow = l < R, idx = isRow ? l : l - R;
          const ids = lineCells(isRow, idx);
          const line = ids.map(i => known[i]);
          if (line.every(v => v !== -1)) continue;
          const res = solveLine(isRow ? clues.rows[idx] : clues.cols[idx], line);
          if (!res) continue;
          const found = [];
          ids.forEach((i, k) => { if (line[k] === -1 && res[k] !== -1) found.push([i, res[k]]); });
          if (found.length) {
            const fills = found.filter(x => x[1] === 1);
            const pick = (fills.length ? fills : found)[0];
            best = { isRow, idx, i: pick[0], v: pick[1] };
          }
        }
        if (best) {
          setCell(best.i, best.v ? FILL : MARK, entry);
          flash(best.i, 'ng-hintcell', 1600);
          flashClue(best.isRow, best.idx);
          ctx.toast(`提示：看第 ${best.idx + 1} ${best.isRow ? '行' : '列'}的线索`);
        } else {
          const unknown = [];
          for (let i = 0; i < cells.length; i++) if (cells[i] === EMPTY || (cells[i] === MARK && puz.sol[i])) unknown.push(i);
          const pool = unknown.filter(i => puz.sol[i]);
          const src = pool.length ? pool : unknown;
          if (!src.length) return;
          const i = src[(Math.random() * src.length) | 0];
          setCell(i, puz.sol[i] ? FILL : MARK, entry);
          flash(i, 'ng-hintcell', 1600);
          ctx.toast('这里需要猜测，直接揭示一格');
        }
      }
      if (!entry.length) return;
      hints++;
      startTimer();
      pushHistory(entry);
      updateLinesFor(entry.map(x => x[0]));
      updateHud();
      saveProgress();
      checkWin();
    }

    function resetPuzzle() {
      if (!puz || finished) return;
      if (!resetBtn.classList.contains('ng-arm')) {
        resetBtn.classList.add('ng-arm');
        resetBtn.textContent = '确认重置？';
        clearTimeout(resetArmTimer);
        resetArmTimer = setTimeout(disarmReset, 2500);
        return;
      }
      disarmReset();
      endStroke(false);
      cells.fill(EMPTY);
      history = [];
      elapsed = 0; mistakes = 0; hints = 0; started = false;
      for (let i = 0; i < cells.length; i++) paintCell(i);
      for (let r = 0; r < puz.R; r++) updateLine(true, r);
      for (let c = 0; c < puz.C; c++) updateLine(false, c);
      delete saves[puz.id];
      ctx.store.set('saves', saves);
      updateHud();
    }
    function disarmReset() {
      clearTimeout(resetArmTimer); resetArmTimer = 0;
      resetBtn.classList.remove('ng-arm');
      resetBtn.textContent = '重置';
    }

    // ---------- win ----------
    function checkWin() {
      if (finished || !puz) return;
      if (!rowDone.every(Boolean) || !colDone.every(Boolean)) return;
      tick();
      finished = true;
      endStroke(false);
      setHover(-1, -1);
      const p = puz;
      const time = Math.round(elapsed);
      const firstTime = !solvedMap[p.id];
      const old = solvedMap[p.id];
      const newBest = !!old && time < old.time;
      solvedMap[p.id] = { time: old ? Math.min(old.time, time) : time };
      ctx.store.set('solved', solvedMap);
      delete saves[p.id];
      ctx.store.set('saves', saves);

      // reveal: clear marks, pop filled cells along the diagonal, fade in pet art
      for (let i = 0; i < cells.length; i++) if (cells[i] === MARK) { cells[i] = EMPTY; paintCell(i); }
      board.classList.add('ng-won');
      if (p.kind === 'pet') {
        picImg.src = petImage(p.pet);
        picTimer = setTimeout(() => { picTimer = 0; picEl.classList.add('ng-show'); }, 750);
      }

      const size = Math.max(p.R, p.C);
      const coins = REWARD[size] || 3;
      let rewardTxt = '';
      if (p.kind === 'pet') {
        const d = ctx.store.get('petDaily', { d: '', n: 0 });
        const cur = d.d === today() ? d : { d: today(), n: 0 };
        if (cur.n < PET_DAILY_MAX) {
          cur.n++;
          ctx.store.set('petDaily', cur);
          ctx.reward(coins, '数织通关');
          rewardTxt = ` · 小鱼干 +${coins}（今日 ${cur.n}/${PET_DAILY_MAX}）`;
        } else {
          rewardTxt = ' · 今日宠物图奖励已领完';
        }
      } else if (firstTime) {
        ctx.reward(coins, '数织通关');
        rewardTxt = ` · 小鱼干 +${coins}`;
      }
      ctx.say('数织完成：' + p.name);

      const extra = [];
      if (mistakes) extra.push(`失误 ${mistakes}`);
      if (hints) extra.push(`提示 ${hints}`);
      winName.textContent = `完成！「${p.name}」`;
      winSub.textContent = ` 用时 ${fmtTime(time)}` + (newBest ? '（新纪录）' : '') + (extra.length ? ' · ' + extra.join(' · ') : '') + rewardTxt;
      nextBtn.textContent = p.kind === 'pet' ? '再来一张' : '下一题';
      if (p.kind !== 'pet') titleEl.innerHTML = `${p.R}×${p.C} · ${esc(p.name)}`;
      winbarTimer = setTimeout(() => {
        winbarTimer = 0;
        toolsEl.classList.add('hidden');
        winbar.classList.remove('hidden');
      }, 400);
      updateHud();
    }

    function nextPuzzle() {
      if (!puz) return;
      if (puz.kind === 'pet') {
        const pets = petList();
        const others = pets.filter(f => f !== puz.pet && !solvedMap['pet:' + f + ':' + puz.R]);
        const pool = others.length ? others : pets.filter(f => f !== puz.pet);
        if (!pool.length) { goBack(); return; }
        openPet(pool[(Math.random() * pool.length) | 0], puz.R);
        return;
      }
      const idx = PUZZLES.indexOf(puz);
      const order = PUZZLES.slice(idx + 1).concat(PUZZLES.slice(0, idx));
      const nxt = order.find(q => !solvedMap[q.id]) || PUZZLES[(idx + 1) % PUZZLES.length];
      if (nxt.R !== puz.R) { tab = String(nxt.R); ctx.store.set('tab', tab); }
      openPuzzle(nxt);
    }

    function goBack() {
      endStroke(true);
      tick();
      saveProgress();
      disarmReset();
      clearFlashTimers();
      setHover(-1, -1);
      puz = null;
      setScreen('select');
      renderSelect();
    }

    // ---------- event wiring ----------
    const on = (t, ev, fn, opt) => { t.addEventListener(ev, fn, opt); return () => t.removeEventListener(ev, fn, opt); };
    const offs = [];
    tabBtns.forEach(b => offs.push(on(b, 'click', () => {
      b.blur();
      tab = b.dataset.tab;
      ctx.store.set('tab', tab);
      renderSelect();
    })));
    psizeBtns.forEach(b => offs.push(on(b, 'click', () => {
      b.blur();
      petSize = +b.dataset.psize;
      ctx.store.set('petSize', petSize);
      renderSelect();
    })));
    modeBtns.forEach(b => offs.push(on(b, 'click', () => {
      b.blur();
      toolMode = b.dataset.mode;
      ctx.store.set('toolMode', toolMode);
      updateHud();
    })));
    offs.push(on(listEl, 'click', onListClick));
    offs.push(on(randomBtn, 'click', () => { randomBtn.blur(); randomPet(); }));
    offs.push(on(undoBtn, 'click', () => { undoBtn.blur(); undo(); }));
    offs.push(on(checkBtn, 'click', () => { checkBtn.blur(); check(); }));
    offs.push(on(hintBtn, 'click', () => { hintBtn.blur(); hint(); }));
    offs.push(on(resetBtn, 'click', () => { resetBtn.blur(); resetPuzzle(); }));
    offs.push(on(mmBtn, 'click', () => {
      mmBtn.blur();
      mistakesMode = !mistakesMode;
      ctx.store.set('mistakesMode', mistakesMode);
      ctx.toast(mistakesMode ? '纠错模式：填错的格子会立即被标记并计为失误' : '纠错模式已关闭');
      updateHud();
    }));
    offs.push(on(backBtn, 'click', () => { backBtn.blur(); goBack(); }));
    offs.push(on(back2Btn, 'click', () => { back2Btn.blur(); goBack(); }));
    offs.push(on(nextBtn, 'click', () => { nextBtn.blur(); nextPuzzle(); }));
    offs.push(on(gridEl, 'pointerdown', onGridDown));
    offs.push(on(gridEl, 'pointermove', onGridMove));
    offs.push(on(gridEl, 'pointerup', onGridUp));
    offs.push(on(gridEl, 'pointercancel', onGridUp));
    offs.push(on(gridEl, 'pointerleave', onGridLeave));
    offs.push(on(gridEl, 'lostpointercapture', onGridUp));
    offs.push(on(stage, 'contextmenu', e => e.preventDefault()));
    offs.push(on(window, 'pointerup', onGridUp));
    offs.push(on(window, 'blur', () => endStroke(true)));
    offs.push(on(window, 'keydown', e => {
      if (!ctx.isActive() || screen !== 'play') return;
      const tag = e.target && e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if ((e.ctrlKey || e.metaKey) && (e.key === 'z' || e.key === 'Z')) {
        e.preventDefault();
        undo();
      } else if (!e.ctrlKey && !e.metaKey && !e.altKey && (e.key === 'x' || e.key === 'X')) {
        toolMode = toolMode === 'fill' ? 'mark' : 'fill';
        ctx.store.set('toolMode', toolMode);
        updateHud();
      } else if (e.key === 'Escape') {
        goBack();
      }
    }));

    let ro = null;
    if (typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => fit());
      ro.observe(el.parentElement || el);
    } else {
      offs.push(on(window, 'resize', fit));
    }

    tickTimer = setInterval(tick, 250);
    setScreen('select');
    renderSelect();

    cleanup = () => {
      alive = false;
      if (screen === 'play') { endStroke(true); tick(); saveProgress(); }
      clearInterval(tickTimer);
      clearTimeout(resetArmTimer);
      clearFlashTimers();
      if (ro) ro.disconnect();
      offs.forEach(off => off());
      root.remove();
    };
  }

  Hub.register({
    id: 'nonogram',
    title: '数织',
    group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18" stroke-width="1.2"/><rect x="9" y="9" width="6" height="6" fill="currentColor" stroke="none"/><rect x="4" y="4" width="5" height="5" rx="1.2" fill="currentColor" stroke="none"/><rect x="15" y="15" width="5" height="5" rx="1.2" fill="currentColor" stroke="none"/></svg>',
    mount,
    unmount() {
      if (cleanup) { cleanup(); cleanup = null; }
    }
  });
})();
