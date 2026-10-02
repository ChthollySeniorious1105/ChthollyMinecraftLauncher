// Standard Japanese mahjong tile faces as SVG (viewBox 0 0 60 80). window.MahjongTiles.face(kind, red)
// kind: 0-8 萬子, 9-17 筒子, 18-26 索子, 27-30 東南西北, 31 白, 32 發, 33 中.
// Layouts and colours follow the common Japanese set: 1筒 decorated wheel, 5筒/5索 red centre,
// 7筒 green diagonal + red block, 1索 bird, 7索 red top stick, 9索 red middle column, 8索 M/W bamboo.
(function (root) {
  const BLUE = '#1f4e9c', RED = '#c8281e', GREEN = '#15803d', BLACK = '#1b1b1b';
  const FONT = '"Yu Mincho","YuMincho","Hiragino Mincho ProN","SimSun","Songti SC","KaiTi",serif';

  // ---------- 筒子 ----------
  function dot(x, y, r, col) {
    // concentric coin: outer ring, inner ring and small centre, like printed tiles
    return `<g transform="translate(${x} ${y})">
      <circle r="${r}" fill="${col}"/>
      <circle r="${r * 0.72}" fill="#fff"/>
      <circle r="${r * 0.56}" fill="${col}"/>
      <circle r="${r * 0.22}" fill="#fff"/>
    </g>`;
  }
  function pin1(red) {
    const c1 = red ? RED : BLUE;
    let petals = '';
    for (let i = 0; i < 16; i++) {
      const a = i * Math.PI / 8;
      petals += `<circle cx="${(Math.cos(a) * 17.5).toFixed(2)}" cy="${(Math.sin(a) * 17.5).toFixed(2)}" r="2.2" fill="${GREEN}"/>`;
    }
    return `<g transform="translate(30 40) scale(1.2)">
      <circle r="22" fill="${GREEN}"/><circle r="20" fill="#fff"/>
      ${petals}
      <circle r="14" fill="${c1}"/><circle r="11" fill="#fff"/>
      <circle r="8.6" fill="${RED}"/><circle r="5.2" fill="#fff"/>
      ${[0, 1, 2, 3, 4, 5, 6, 7].map(i => { const a = i * Math.PI / 4 + Math.PI / 8; return `<circle cx="${(Math.cos(a) * 6.9).toFixed(2)}" cy="${(Math.sin(a) * 6.9).toFixed(2)}" r="0.9" fill="#fff"/>`; }).join('')}
      <circle r="2.2" fill="${c1}"/>
    </g>`;
  }
  function pins(n, red) {
    if (n === 1) return pin1(red);
    const B = red ? RED : BLUE, G = red ? RED : GREEN, R = RED;
    const L = {
      2: [[30, 21, 13, G], [30, 59, 13, B]],
      3: [[14, 15, 11, B], [30, 40, 11, R], [46, 65, 11, G]],
      4: [[17, 21, 12, B], [43, 21, 12, G], [17, 59, 12, G], [43, 59, 12, B]],
      5: [[16, 17, 11, B], [44, 17, 11, G], [30, 40, 11, R], [16, 63, 11, G], [44, 63, 11, B]],
      6: [[17, 14, 10, G], [43, 14, 10, G], [17, 43, 10, R], [43, 43, 10, R], [17, 66, 10, R], [43, 66, 10, R]],
      7: [[12, 11, 8.3, G], [30, 18, 8.3, G], [48, 25, 8.3, G], [18, 48, 9, R], [42, 48, 9, R], [18, 68, 9, R], [42, 68, 9, R]],
      8: [[17, 10.5, 8.6, B], [43, 10.5, 8.6, B], [17, 30.5, 8.6, B], [43, 30.5, 8.6, B], [17, 50, 8.6, B], [43, 50, 8.6, B], [17, 70, 8.6, B], [43, 70, 8.6, B]],
      9: [[12, 14, 8.5, B], [30, 14, 8.5, B], [48, 14, 8.5, B], [12, 40, 8.5, R], [30, 40, 8.5, R], [48, 40, 8.5, R], [12, 66, 8.5, G], [30, 66, 8.5, G], [48, 66, 8.5, G]]
    }[n];
    return L.map(([x, y, r, c]) => dot(x, y, r, c)).join('');
  }

  // ---------- 索子 ----------
  function stick(x, y, h, col, rot) {
    // bamboo stick: rounded body with two nodes and a light centre line
    const w = 7.6, t = rot ? ` transform="rotate(${rot} ${x} ${y + h / 2})"` : '';
    return `<g${t}>
      <rect x="${x - w / 2}" y="${y}" width="${w}" height="${h}" rx="3" fill="${col}"/>
      <rect x="${x - w / 2 - 0.8}" y="${y + h * 0.5 - 1.1}" width="${w + 1.6}" height="2.2" rx="1.1" fill="${col}"/>
      <rect x="${x - w / 2 - 0.8}" y="${y - 0.4}" width="${w + 1.6}" height="2" rx="1" fill="${col}"/>
      <rect x="${x - w / 2 - 0.8}" y="${y + h - 1.6}" width="${w + 1.6}" height="2" rx="1" fill="${col}"/>
      <path d="M${x} ${y + 2.5}V${y + h * 0.5 - 2}M${x} ${y + h * 0.5 + 2}V${y + h - 2.5}" stroke="#fff" stroke-width="1.1" stroke-linecap="round" opacity=".75"/>
    </g>`;
  }
  function bird(red) {
    const body = red ? RED : GREEN;
    return `<g transform="translate(33 38) scale(1.05)">
      <path d="M-4 18c-6 4-14 8-18 6 3-2 8-6 10-10z" fill="${BLUE}"/>
      <path d="M-2 20c-3 5-8 11-12 11 1-3 4-8 6-12z" fill="${RED}"/>
      <path d="M-14 4c-2-12 6-24 16-24 8 0 12 6 11 12l-3 2c3 4 4 10 2 16-3 8-12 11-20 8-5-2-7-8-6-14z" fill="${body}"/>
      <path d="M-8 0c2-4 8-6 12-3-2 5-8 8-12 7z" fill="#fff" opacity=".35"/>
      <path d="M-10 8c4 4 12 6 18 2-2 6-9 9-15 7z" fill="${BLUE}"/>
      <path d="M10-12l9-2-6 6z" fill="#e0a526"/>
      <circle cx="5" cy="-12" r="3" fill="#fff"/><circle cx="5.6" cy="-12" r="1.6" fill="${BLACK}"/>
      <path d="M-4 -18c2-6 8-9 12-7-4 1-7 3-9 7" fill="${RED}"/>
      <path d="M-3 26v6M3 25v7" stroke="#e0a526" stroke-width="2" stroke-linecap="round"/>
    </g>`;
  }
  function sous(n, red) {
    if (n === 1) return bird(red);
    const G = red ? RED : GREEN, R = RED, B = red ? RED : BLUE;
    const H = 30;
    const P = {
      2: [[30, 6, G], [30, 44, B]],
      3: [[30, 6, B], [17, 44, G], [43, 44, G]],
      4: [[18, 6, G], [42, 6, B], [18, 44, B], [42, 44, G]],
      5: [[14, 6, G], [46, 6, B], [30, 25, R], [14, 44, B], [46, 44, G]],
      6: [[13, 6, G], [30, 6, G], [47, 6, G], [13, 44, B], [30, 44, B], [47, 44, B]],
      7: [[30, 2, R], [13, 29, G], [30, 29, G], [47, 29, G], [13, 55, B], [30, 55, B], [47, 55, B]],
      9: [[13, 2, G], [30, 2, R], [47, 2, G], [13, 29, B], [30, 29, R], [47, 29, B], [13, 55, G], [30, 55, R], [47, 55, G]]
    };
    if (n === 8) {
      // 8索: tilted sticks forming an M on top and a W below
      return [
        stick(10, 5, H, G), stick(50, 5, H, G), stick(23, 5, H, B, 24), stick(37, 5, H, B, -24),
        stick(10, 45, H, B), stick(50, 45, H, B), stick(23, 45, H, G, -24), stick(37, 45, H, G, 24)
      ].join('');
    }
    const h = n === 7 || n === 9 ? 23 : H;
    return P[n].map(([x, y, c]) => stick(x, y, h, c)).join('');
  }

  // ---------- 萬子 / 字牌 ----------
  const MAN_NUM = ['一', '二', '三', '四', '伍', '六', '七', '八', '九'];
  function man(n, red) {
    return `<text x="30" y="34" font-size="34" text-anchor="middle" fill="${red ? RED : BLACK}" font-family=${JSON.stringify(FONT)} font-weight="700">${MAN_NUM[n - 1]}</text>
      <text x="30" y="74" font-size="36" text-anchor="middle" fill="${RED}" font-family=${JSON.stringify(FONT)} font-weight="700">萬</text>`;
  }
  function honor(k) {
    if (k === 31) {
      // 白: blue frame (the common Japanese design)
      return `<rect x="11" y="13" width="38" height="54" rx="4" fill="none" stroke="${BLUE}" stroke-width="4"/>
        <rect x="16.5" y="18.5" width="27" height="43" rx="2" fill="none" stroke="${BLUE}" stroke-width="1.4"/>`;
    }
    const ch = { 27: '東', 28: '南', 29: '西', 30: '北', 32: '發', 33: '中' }[k];
    const col = k === 32 ? GREEN : k === 33 ? RED : BLACK;
    return `<text x="30" y="56" font-size="46" text-anchor="middle" fill="${col}" font-family=${JSON.stringify(FONT)} font-weight="700">${ch}</text>`;
  }

  const cache = new Map();
  function face(kind, red) {
    const key = kind * 2 + (red ? 1 : 0);
    if (cache.has(key)) return cache.get(key);
    let inner;
    if (kind < 9) inner = man(kind + 1, red);
    else if (kind < 18) inner = pins(kind - 8, red);
    else if (kind < 27) inner = sous(kind - 17, red);
    else inner = honor(kind);
    const svg = `<svg viewBox="0 0 60 80" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;
    cache.set(key, svg);
    return svg;
  }
  root.MahjongTiles = { face };
})(typeof window !== 'undefined' ? window : globalThis);
