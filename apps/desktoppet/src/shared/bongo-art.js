// 键鼠映射看板 artwork (BongoCat-style), shared by the overlay window and the settings preview.
// window.BongoArt: SKINS, KEYS (layout with uiohook key codes), keyName(code), catSvg(skin), kbSvg(skin),
// and the geometry helpers the overlay uses to aim the paws.
(function (root) {
  const SKINS = {
    orange: { name: '橘猫', fur: '#f9b56a', shade: '#ee8f3e', line: '#6e3f22', belly: '#fff3e2', stripe: '#e07a2e', eye: '#3b2518', inner: '#ffb3b8', accent: '#ff8a3d', accent2: '#ffc15e' },
    gray: { name: '灰猫', fur: '#c3cad3', shade: '#9aa4b1', line: '#3f4853', belly: '#f5f7fa', stripe: '#8792a0', eye: '#2c3440', inner: '#ffb8c4', accent: '#5aa8ff', accent2: '#9fd0ff' },
    white: { name: '白猫', fur: '#fffaf4', shade: '#ebe0d4', line: '#6a5646', belly: '#ffffff', stripe: '#f1e3d4', eye: '#3a6a9e', inner: '#ffc0c8', accent: '#ff7eaa', accent2: '#ffc2d8' },
    black: { name: '黑猫', fur: '#3d3b44', shade: '#2a2830', line: '#121117', belly: '#57545f', stripe: '#2a2830', eye: '#f5c542', inner: '#c47a8c', accent: '#b47cff', accent2: '#dcc2ff' },
    calico: { name: '三花', fur: '#fff6ec', shade: '#e9dccd', line: '#5e4535', belly: '#ffffff', stripe: '#3c332e', eye: '#4a3326', inner: '#ffb3b8', accent: '#ff9a52', accent2: '#ffd08a', patch: '#f0a050' }
  };

  // ---------- keyboard layout (TKL), in key units. [label, uiohook code, width] per row ----------
  const ROWS = [
    { y: 0, keys: [['Esc', 1], [null, 0, 1], ['F1', 59], ['F2', 60], ['F3', 61], ['F4', 62], [null, 0, 0.5], ['F5', 63], ['F6', 64], ['F7', 65], ['F8', 66], [null, 0, 0.5], ['F9', 67], ['F10', 68], ['F11', 87], ['F12', 88], [null, 0, 0.25], ['PrtSc', 3639], ['ScrLk', 70], ['Pause', 3653]] },
    { y: 1.25, keys: [['`', 41], ['1', 2], ['2', 3], ['3', 4], ['4', 5], ['5', 6], ['6', 7], ['7', 8], ['8', 9], ['9', 10], ['0', 11], ['-', 12], ['=', 13], ['⌫', 14, 2], [null, 0, 0.25], ['Ins', 3666], ['Home', 3655], ['PgUp', 3657]] },
    { y: 2.25, keys: [['Tab', 15, 1.5], ['Q', 16], ['W', 17], ['E', 18], ['R', 19], ['T', 20], ['Y', 21], ['U', 22], ['I', 23], ['O', 24], ['P', 25], ['[', 26], [']', 27], ['\\', 43, 1.5], [null, 0, 0.25], ['Del', 3667], ['End', 3663], ['PgDn', 3665]] },
    { y: 3.25, keys: [['Caps', 58, 1.75], ['A', 30], ['S', 31], ['D', 32], ['F', 33], ['G', 34], ['H', 35], ['J', 36], ['K', 37], ['L', 38], [';', 39], ["'", 40], ['Enter', 28, 2.25]] },
    { y: 4.25, keys: [['Shift', 42, 2.25], ['Z', 44], ['X', 45], ['C', 46], ['V', 47], ['B', 48], ['N', 49], ['M', 50], [',', 51], ['.', 52], ['/', 53], ['Shift', 54, 2.75], [null, 0, 1.25], ['↑', 57416]] },
    { y: 5.25, keys: [['Ctrl', 29, 1.25], ['⊞', 3675, 1.25], ['Alt', 56, 1.25], ['', 57, 6.25], ['Alt', 3640, 1.25], ['⊞', 3676, 1.25], ['☰', 3677, 1.25], ['Ctrl', 3613, 1.25], [null, 0, 0.25], ['←', 57419], ['↓', 57424], ['→', 57421]] }
  ];
  const KEYS = [];
  for (const row of ROWS) {
    let x = 0;
    for (const [label, code, w = 1] of row.keys) {
      if (label !== null) KEYS.push({ label, code, x, y: row.y, w, h: 1 });
      x += w;
    }
  }
  const KB_W = 18.25, KB_H = 6.25;
  // codes that should light the same key (numpad-with-numlock-off arrows, numpad enter)
  const ALIAS = { 3612: 28, 61000: 57416, 61003: 57419, 61005: 57421, 61008: 57424, 60999: 3655, 61001: 3657, 61007: 3663, 61009: 3665, 61010: 3666, 61011: 3667 };
  const NAMES = {
    1: 'Esc', 14: 'Backspace', 15: 'Tab', 28: 'Enter', 57: 'Space', 58: 'CapsLock', 29: 'Ctrl', 3613: 'Ctrl', 42: 'Shift', 54: 'Shift',
    56: 'Alt', 3640: 'Alt', 3675: 'Win', 3676: 'Win', 3677: 'Menu', 57416: '↑', 57419: '←', 57421: '→', 57424: '↓',
    3639: 'PrtSc', 70: 'ScrLk', 3653: 'Pause', 69: 'NumLock', 3666: 'Insert', 3667: 'Delete', 3655: 'Home', 3663: 'End', 3657: 'PgUp', 3665: 'PgDn',
    82: 'Num0', 79: 'Num1', 80: 'Num2', 81: 'Num3', 75: 'Num4', 76: 'Num5', 77: 'Num6', 71: 'Num7', 72: 'Num8', 73: 'Num9',
    55: 'Num*', 78: 'Num+', 74: 'Num-', 83: 'Num.', 3637: 'Num/', 3612: 'Enter'
  };
  const MODS = { 29: 'Ctrl', 3613: 'Ctrl', 42: 'Shift', 54: 'Shift', 56: 'Alt', 3640: 'Alt', 3675: 'Win', 3676: 'Win' };
  function keyName(code) {
    if (NAMES[code]) return NAMES[code];
    const k = KEYS.find(x => x.code === code);
    if (k) return k.label;
    if (code >= 59 && code <= 68) return 'F' + (code - 58);
    return '#' + code;
  }
  const keyOf = code => KEYS.find(k => k.code === (ALIAS[code] || code));

  // ---------- shared pieces ----------
  const defs = s => `
    <defs>
      <linearGradient id="gFur" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s.fur}"/><stop offset="1" stop-color="${s.shade}"/></linearGradient>
      <radialGradient id="gHead" cx=".5" cy=".38" r=".7"><stop offset="0" stop-color="${s.fur}"/><stop offset=".78" stop-color="${s.fur}"/><stop offset="1" stop-color="${s.shade}"/></radialGradient>
      <linearGradient id="gDesk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e2ad7a"/><stop offset=".55" stop-color="#cc8f5b"/><stop offset="1" stop-color="#b87945"/></linearGradient>
      <linearGradient id="gDeskFront" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a36434"/><stop offset="1" stop-color="#7c4722"/></linearGradient>
      <linearGradient id="gCase" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbf7f2"/><stop offset="1" stop-color="#ddd3c8"/></linearGradient>
      <linearGradient id="gCap" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#eee6dc"/></linearGradient>
      <linearGradient id="gCapMod" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6ede3"/><stop offset="1" stop-color="#e2d3c3"/></linearGradient>
      <linearGradient id="kOn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s.accent2}"/><stop offset="1" stop-color="${s.accent}"/></linearGradient>
      <linearGradient id="gMouse" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#dcd4ca"/></linearGradient>
      <linearGradient id="gPad" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6f86a3"/><stop offset="1" stop-color="#4c6282"/></linearGradient>
      <filter id="fShadow" x="-20%" y="-20%" width="140%" height="160%"><feGaussianBlur stdDeviation="3"/></filter>
      <filter id="fGlow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3.5"/></filter>
    </defs>`;

  // head centred at (0,0), ~176 wide. Pupils live in #eyes so they can follow the cursor.
  function head(s) {
    const L = s.line;
    const earL = `<path d="M-86 -12C-94 -46 -90 -74 -76 -88C-58 -80 -40 -64 -28 -50Z" fill="url(#gFur)" stroke="${L}" stroke-width="3" stroke-linejoin="round"/>
      <path d="M-78 -24C-82 -46 -79 -64 -71 -74C-58 -66 -48 -58 -40 -48Z" fill="${s.inner}"/>
      <path d="M-74 -30C-74 -44 -72 -54 -68 -60M-66 -36C-64 -46 -62 -52 -58 -56" stroke="${s.fur}" stroke-width="1.6" stroke-linecap="round" opacity=".8"/>`;
    const patches = s.patch ? `
      <path d="M-40 -64C-20 -72 6 -70 16 -60C0 -44 -30 -40 -56 -46C-54 -54 -48 -60 -40 -64Z" fill="${s.patch}" opacity=".95"/>
      <path d="M34 -66C52 -62 70 -48 78 -30C62 -30 44 -40 32 -54Z" fill="${s.stripe}" opacity=".9"/>` : '';
    const stripes = s.patch ? '' : `
      <g stroke="${s.stripe}" stroke-width="4.2" stroke-linecap="round" fill="none" opacity=".85">
        <path d="M-12 -66Q-8 -56 -10 -46"/><path d="M0 -68V-48"/><path d="M12 -66Q8 -56 10 -46"/>
        <path d="M-86 6L-68 10"/><path d="M-88 18L-70 19"/><path d="M86 6L68 10"/><path d="M88 18L70 19"/>
      </g>`;
    return `
      <g class="ear-l">${earL}</g>
      <g transform="scale(-1 1)"><g class="ear-r">${earL}</g></g>
      <path d="M0 -70C55 -70 92 -38 94 2C95 20 90 32 100 42C88 43 86 50 78 52C60 68 32 74 0 74C-32 74 -60 68 -78 52C-86 50 -88 43 -100 42C-90 32 -95 20 -94 2C-92 -38 -55 -70 0 -70Z"
        fill="url(#gHead)" stroke="${L}" stroke-width="3" stroke-linejoin="round"/>
      ${patches}${stripes}
      <ellipse cx="0" cy="42" rx="40" ry="24" fill="${s.belly}" opacity=".9"/>
      <g id="eyes">
        <g class="eo">
          <g class="blink"><ellipse cx="-34" cy="0" rx="12" ry="14" fill="${s.eye}"/></g>
          <g class="blink"><ellipse cx="34" cy="0" rx="12" ry="14" fill="${s.eye}"/></g>
          <g id="pupils"><circle cx="-30" cy="-6" r="4.6" fill="#fff"/><circle cx="-38" cy="6" r="2" fill="#fff"/><circle cx="38" cy="-6" r="4.6" fill="#fff"/><circle cx="30" cy="6" r="2" fill="#fff"/></g>
        </g>
        <g class="ehappy" display="none" fill="none" stroke="${L}" stroke-width="3.6" stroke-linecap="round">
          <path d="M-46 4Q-34 -10 -22 4"/><path d="M22 4Q34 -10 46 4"/>
        </g>
        <g class="eexcited" display="none" fill="none" stroke="${L}" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round">
          <path d="M-46 -8L-26 0L-46 8"/><path d="M46 -8L26 0L46 8"/>
        </g>
        <g class="esleep" display="none" fill="none" stroke="${L}" stroke-width="3.2" stroke-linecap="round">
          <path d="M-46 2Q-34 10 -22 2"/><path d="M22 2Q34 10 46 2"/>
        </g>
      </g>
      <ellipse cx="-54" cy="24" rx="14" ry="7.5" fill="#ff8fa3" opacity=".45"/>
      <ellipse cx="54" cy="24" rx="14" ry="7.5" fill="#ff8fa3" opacity=".45"/>
      <path d="M-6 16Q0 11 6 16Q2 23 0 23Q-2 23 -6 16Z" fill="#f48fa0" stroke="${L}" stroke-width="1.2" stroke-linejoin="round"/>
      <path class="mouth-w" d="M-12 26Q-6 34 0 26Q6 34 12 26" fill="none" stroke="${L}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
      <g class="mouth-o" display="none"><ellipse cx="0" cy="31" rx="7" ry="8" fill="#b8404f" stroke="${L}" stroke-width="2"/><ellipse cx="0" cy="35" rx="4.4" ry="3" fill="#ff8fa3"/></g>
      <g stroke="${L}" stroke-width="1.6" stroke-linecap="round" opacity=".55">
        <path d="M-60 16L-100 8"/><path d="M-60 23L-102 25"/><path d="M-58 30L-96 40"/>
        <path d="M60 16L100 8"/><path d="M60 23L102 25"/><path d="M58 30L96 40"/>
      </g>`;
  }
  // a paw at (0,0); `pads` shows the toe beans (raised paw seen from below)
  function paw(s, pads) {
    return `<ellipse cx="0" cy="0" rx="19" ry="15" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
      ${pads
        ? `<ellipse cx="0" cy="4" rx="8" ry="6" fill="${s.inner}"/><circle cx="-9.5" cy="-5" r="3.4" fill="${s.inner}"/><circle cx="0" cy="-9" r="3.4" fill="${s.inner}"/><circle cx="9.5" cy="-5" r="3.4" fill="${s.inner}"/>`
        : `<path d="M-6 -12Q-6 -4 -7 2M6 -12Q6 -4 7 2" stroke="${s.line}" stroke-width="2" fill="none" stroke-linecap="round" opacity=".55"/>`}`;
  }

  // ---------- keyboard drawing ----------
  // mini: small flat keys for the cat's desk; full: 3D keycaps with legends
  function keysSvg(u, mini, prefix) {
    return KEYS.map(k => {
      const x = k.x * u, y = k.y * u, w = k.w * u, h = k.h * u;
      const mod = k.w > 1 || /^[A-Z][a-z]|[⊞☰⌫]/.test(k.label) || k.label.length > 1 && !/^F\d/.test(k.label);
      if (mini) {
        return `<g class="k" id="${prefix}${k.code}"><rect class="cap" x="${(x + 0.7).toFixed(1)}" y="${(y + 0.7).toFixed(1)}" width="${(w - 1.4).toFixed(1)}" height="${(h - 1.4).toFixed(1)}" rx="1.6" fill="${mod ? 'url(#gCapMod)' : 'url(#gCap)'}"/></g>`;
      }
      const small = k.label.length > 2;
      return `<g class="k" id="${prefix}${k.code}">
        <rect class="glow" x="${x - 2}" y="${y - 2}" width="${w + 4}" height="${h + 4}" rx="8" fill="url(#kOn)" filter="url(#fGlow)"/>
        <rect x="${x + 1.2}" y="${y + 1.2}" width="${w - 2.4}" height="${h - 2.4}" rx="5" fill="#cbbfb1"/>
        <rect class="cap" x="${x + 3.2}" y="${y + 2}" width="${w - 6.4}" height="${h - 8}" rx="4" fill="${mod ? 'url(#gCapMod)' : 'url(#gCap)'}" stroke="#fff" stroke-opacity=".7" stroke-width=".8"/>
        <text x="${x + w / 2}" y="${y + h / 2 + 0.5}" text-anchor="middle" class="${small ? 'small' : ''}">${k.label.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</text>
      </g>`;
    }).join('');
  }

  // ---------- cat mode (380 x 300) ----------
  // keyboard and mouse pad sit on the desk in a skewed plane: (x,y) -> (x - .3y + ox, .62y + oy)
  const KB_U = 9.4, KB = { ox: 44, oy: 220 };
  const PAD = { ox: 250, oy: 218, w: 108, h: 70 };
  const plane = (o, x, y) => [x - 0.3 * y + o.ox, 0.62 * y + o.oy];
  const SHOULDER_L = [128, 186], SHOULDER_R = [252, 186];
  const PAW_L_REST = [110, 198];
  function catSvg(s) {
    const kbw = KB_W * KB_U, kbh = KB_H * KB_U;
    return `${defs(s)}
      <ellipse cx="190" cy="292" rx="175" ry="10" fill="#000" opacity=".12" filter="url(#fShadow)"/>
      <g class="tail"><path d="M292 206C330 200 350 170 344 138C340 118 356 108 366 118" fill="none" stroke="${s.line}" stroke-width="21" stroke-linecap="round"/>
        <path d="M292 206C330 200 350 170 344 138C340 118 356 108 366 118" fill="none" stroke="url(#gFur)" stroke-width="15" stroke-linecap="round"/>
        <path d="M352 120C356 112 362 112 366 118" fill="none" stroke="${s.stripe}" stroke-width="12" stroke-linecap="round" opacity=".8"/></g>
      <g class="body">
        <path d="M96 150C80 196 70 240 70 300H310C310 240 300 196 284 150Z" fill="url(#gFur)" stroke="${s.line}" stroke-width="3"/>
        <ellipse cx="190" cy="206" rx="58" ry="40" fill="${s.belly}"/>
      </g>
      <path d="M0 206H380V286H0Z" fill="url(#gDesk)"/>
      <path d="M0 206H380" stroke="#f3c79c" stroke-width="2"/>
      <g stroke="#a86a3a" stroke-width="1.2" fill="none" opacity=".35">
        <path d="M0 224C80 218 150 230 230 222S340 226 380 220"/><path d="M0 250C90 244 170 256 250 248S350 252 380 246"/><path d="M30 270C110 266 200 276 290 268"/>
      </g>
      <path d="M0 286H380V300H0Z" fill="url(#gDeskFront)"/>
      <!-- keyboard -->
      <g transform="matrix(1 0 -0.3 0.62 ${KB.ox} ${KB.oy})">
        <rect x="-8" y="-4" width="${kbw + 16}" height="${kbh + 16}" rx="7" fill="#000" opacity=".18" filter="url(#fShadow)"/>
        <rect x="-7" y="1" width="${kbw + 14}" height="${kbh + 12}" rx="7" fill="#b9aea2"/>
        <rect x="-7" y="-6" width="${kbw + 14}" height="${kbh + 12}" rx="7" fill="url(#gCase)" stroke="#a89c8f" stroke-width="1.2"/>
        <rect x="-2" y="-1.5" width="${kbw + 4}" height="${kbh + 3}" rx="3" fill="#cfc5ba"/>
        ${keysSvg(KB_U, true, 'ck-')}
      </g>
      <!-- mouse pad -->
      <g transform="matrix(1 0 -0.3 0.62 ${PAD.ox} ${PAD.oy})">
        <rect x="0" y="4" width="${PAD.w}" height="${PAD.h}" rx="12" fill="#000" opacity=".18" filter="url(#fShadow)"/>
        <rect x="0" y="0" width="${PAD.w}" height="${PAD.h}" rx="12" fill="url(#gPad)" stroke="#3b4d68" stroke-width="1.5"/>
        <rect x="6" y="6" width="${PAD.w - 12}" height="${PAD.h - 12}" rx="8" fill="none" stroke="#fff" stroke-opacity=".25" stroke-dasharray="3 3"/>
        <g opacity=".35" fill="#fff"><circle cx="${PAD.w - 18}" cy="16" r="5"/><circle cx="${PAD.w - 28}" cy="12" r="2.6"/><circle cx="${PAD.w - 12}" cy="26" r="2.2"/></g>
      </g>
      <!-- mouse -->
      <g id="mouse">
        <ellipse cx="0" cy="14" rx="18" ry="8" fill="#000" opacity=".2" filter="url(#fShadow)"/>
        <path d="M-15 -8C-15 -24 -8 -30 0 -30C8 -30 15 -24 15 -8V6C15 16 8 22 0 22C-8 22 -15 16 -15 6Z" fill="url(#gMouse)" stroke="#8e8378" stroke-width="1.6"/>
        <path id="mbL" class="m-btn" d="M-14.2 -9C-14.2 -23 -8 -29 -0.8 -29.2V-9Z" fill="transparent"/>
        <path id="mbR" class="m-btn" d="M14.2 -9C14.2 -23 8 -29 0.8 -29.2V-9Z" fill="transparent"/>
        <path d="M0 -30V-9M-15 -9H15" stroke="#9c9186" stroke-width="1.2"/>
        <rect id="mWheel" x="-2.2" y="-24" width="4.4" height="9" rx="2.2" fill="#6d645b"/>
      </g>
      <!-- arms -->
      <g id="armL"><path class="arm-o" fill="none" stroke="${s.line}" stroke-width="34" stroke-linecap="round"/><path class="arm-i" fill="none" stroke="url(#gFur)" stroke-width="28" stroke-linecap="round"/></g>
      <g id="pawL"><g class="pads">${paw(s, true)}</g><g class="top" display="none">${paw(s, false)}</g></g>
      <g id="armR"><path class="arm-o" fill="none" stroke="${s.line}" stroke-width="34" stroke-linecap="round"/><path class="arm-i" fill="none" stroke="url(#gFur)" stroke-width="28" stroke-linecap="round"/></g>
      <g id="pawR">${paw(s, false)}</g>
      <g id="head" transform="translate(190 104)">${head(s)}</g>
      <g id="fx"></g>`;
  }

  // ---------- keyboard mode (640 x 300) ----------
  const FK_U = 27.6, FK = { x: 24, y: 104 };
  function kbSvg(s) {
    const w = KB_W * FK_U, h = KB_H * FK_U;
    return `${defs(s)}
      <!-- peeking cat behind the keyboard -->
      <g transform="translate(150 60) scale(.62)">
        <g id="head">${head(s)}</g>
      </g>
      <ellipse cx="${FK.x + w / 2}" cy="${FK.y + h + 22}" rx="${w / 2 + 6}" ry="9" fill="#000" opacity=".2" filter="url(#fShadow)"/>
      <rect x="${FK.x - 14}" y="${FK.y - 12}" width="${w + 28}" height="${h + 30}" rx="18" fill="#b9aea2"/>
      <rect x="${FK.x - 14}" y="${FK.y - 16}" width="${w + 28}" height="${h + 28}" rx="18" fill="url(#gCase)" stroke="#a89c8f" stroke-width="1.4"/>
      <rect x="${FK.x - 5}" y="${FK.y - 6}" width="${w + 10}" height="${h + 10}" rx="8" fill="#d8cec3"/>
      <!-- paws resting on the case edge -->
      <g transform="translate(106 92) rotate(-8) scale(.9)">${paw(s, false)}</g>
      <g transform="translate(194 92) rotate(8) scale(.9)">${paw(s, false)}</g>
      <g transform="translate(${FK.x} ${FK.y})">${keysSvg(FK_U, false, 'kk-')}</g>
      <circle cx="${FK.x + w - 6}" cy="${FK.y - 10}" r="2.4" fill="#7ce38a" opacity=".9"/>
      <!-- mouse -->
      <g transform="translate(596 190)">
        <ellipse cx="0" cy="62" rx="34" ry="10" fill="#000" opacity=".2" filter="url(#fShadow)"/>
        <path d="M-30 -20C-30 -52 -16 -62 0 -62C16 -62 30 -52 30 -20V22C30 46 16 58 0 58C-16 58 -30 46 -30 22Z" fill="url(#gMouse)" stroke="#8e8378" stroke-width="2"/>
        <path id="mbL" class="m-btn" d="M-28.6 -22C-28.6 -50 -16 -60 -1.4 -60.4V-22Z" fill="transparent"/>
        <path id="mbR" class="m-btn" d="M28.6 -22C28.6 -50 16 -60 1.4 -60.4V-22Z" fill="transparent"/>
        <path d="M0 -62V-22M-30 -22H30" stroke="#9c9186" stroke-width="1.6"/>
        <rect id="mWheel" x="-4.2" y="-52" width="8.4" height="18" rx="4.2" fill="#6d645b"/>
        <path class="wheel-up" d="M0 -74l-7 8h14z" fill="${s.accent}"/>
        <path class="wheel-down" d="M0 -12l-7 -8h14z" fill="${s.accent}"/>
        <path d="M-12 30Q0 38 12 30" stroke="#c9beb1" stroke-width="2" fill="none" stroke-linecap="round"/>
      </g>
      <!-- cursor minimap -->
      <g transform="translate(560 76)">
        <rect x="0" y="0" width="72" height="44" rx="6" fill="#2c3440" stroke="#9aa4b1" stroke-width="1.4"/>
        <rect x="31" y="44" width="10" height="6" fill="#9aa4b1"/><rect x="24" y="49" width="24" height="3" rx="1.5" fill="#9aa4b1"/>
        <circle id="dot" cx="36" cy="22" r="3.4" fill="${s.accent2}"/>
      </g>
      <g id="fx"></g>`;
  }

  // aim helpers for the overlay
  function keyPoint(code) {
    const k = keyOf(code);
    if (!k) return null;
    return plane(KB, (k.x + k.w / 2) * KB_U, (k.y + 0.5) * KB_U);
  }
  function mousePoint(nx, ny) {
    const px = 16 + Math.max(0, Math.min(1, nx)) * (PAD.w - 32), py = 14 + Math.max(0, Math.min(1, ny)) * (PAD.h - 30);
    return plane(PAD, px, py);
  }
  function armPath(from, to) {
    const mx = (from[0] + to[0]) / 2 + (to[0] < from[0] ? -10 : 10), my = (from[1] + to[1]) / 2 - 8;
    return `M${from[0].toFixed(1)} ${from[1].toFixed(1)}Q${mx.toFixed(1)} ${my.toFixed(1)} ${to[0].toFixed(1)} ${to[1].toFixed(1)}`;
  }

  root.BongoArt = { SKINS, KEYS, MODS, keyName, keyOf, catSvg, kbSvg, head, defs, keyPoint, mousePoint, armPath, SHOULDER_L, SHOULDER_R, PAW_L_REST };
})(typeof window !== 'undefined' ? window : globalThis);
