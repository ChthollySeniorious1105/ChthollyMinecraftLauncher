// 日本麻将 — table UI + 牌谱 viewer, styled after 雀魂. Rules: riichi/engine.js, AI: riichi/ai.js.
(function () {
  const R = window.Riichi, AI = window.RiichiAI;
  const NAMES = ['你', '小狐狸', '小熊', '企鹅'];
  const SEAT_PET = [null, '01-fox.png', '05-bear.png', '06-penguin.png'];
  const imgCache = new Map();
  function petFile(seat) {
    if (seat === 0) { try { return window.api.settings.get().pet; } catch { return '02-cat.png'; } }
    return SEAT_PET[seat];
  }
  function avatar(seat, big) {
    const f = petFile(seat);
    if (!imgCache.has(f)) { try { imgCache.set(f, window.api.petImage(f)); } catch { imgCache.set(f, ''); } }
    const url = imgCache.get(f);
    return `<div class="rq-ava${big ? ' big' : ''}">${url ? `<img src="${url}" alt="">` : NAMES[seat][0]}</div>`;
  }
  const SEAT_POS = { 4: ['bottom', 'right', 'top', 'left'], 3: ['bottom', 'right', 'left'] };
  const SEAT_ROT = { bottom: 0, right: -90, top: 180, left: 90 };
  const MAX_RECORDS = 30;
  const BASE_W = 760, BASE_H = 600;

  // ---------- tile artwork: shared/mjtiles.js ----------
  const tileSvg = id => window.MahjongTiles.face(R.kindOf(id), R.RED.has(id));
  function tileEl(id, cls) {
    const d = document.createElement('div');
    d.className = 'rq-tile' + (cls ? ' ' + cls : '') + (id != null && R.RED.has(id) ? ' rq-red' : '');
    if (id == null) d.classList.add('rq-back');
    else { d.innerHTML = tileSvg(id); d.dataset.id = id; d.dataset.k = R.kindOf(id); }
    return d;
  }
  const tileHtml = (id, cls) => `<span class="rq-tile ${cls || ''} ${R.RED.has(id) ? 'rq-red' : ''}" data-k="${R.kindOf(id)}">${tileSvg(id)}</span>`;
  const sortHand = h => h.slice().sort((a, b) => R.kindOf(a) - R.kindOf(b) || a - b);

  // ---------- sound: synthesized clicks + optional voice ----------
  function makeSound(cfg) {
    let ac = null, master = null, noiseBuf = null;
    function ensure() {
      if (!cfg.sound) return null;
      if (!ac) {
        try {
          ac = new AudioContext(); master = ac.createGain(); master.gain.value = 0.35; master.connect(ac.destination);
          noiseBuf = ac.createBuffer(1, ac.sampleRate * 0.2, ac.sampleRate);
          const d = noiseBuf.getChannelData(0);
          for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.exp(-i / (d.length * 0.08));
        } catch { return null; }
      }
      if (ac.state === 'suspended') ac.resume().catch(() => {});
      return ac;
    }
    function clack(vol, freq) {
      const a = ensure(); if (!a) return;
      const src = a.createBufferSource(); src.buffer = noiseBuf;
      const f = a.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq || 2400; f.Q.value = 1.2;
      const g = a.createGain(); g.gain.value = vol;
      src.connect(f); f.connect(g); g.connect(master); src.start();
    }
    function tone(fr, dur, type, vol, delay) {
      const a = ensure(); if (!a) return;
      const t = a.currentTime + (delay || 0);
      const o = a.createOscillator(), g = a.createGain();
      o.type = type; o.frequency.setValueAtTime(fr, t);
      g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.02);
    }
    // voices: Japanese if the system has one, otherwise Chinese
    const JA = { riichi: 'リーチ', ron: 'ロン', tsumo: 'ツモ', pon: 'ポン', chi: 'チー', kan: 'カン', kita: 'キタ' };
    const ZH = { riichi: '立直', ron: '荣', tsumo: '自摸', pon: '碰', chi: '吃', kan: '杠', kita: '拔北' };
    function speak(word) {
      if (!cfg.voice || !window.speechSynthesis) return;
      const voices = speechSynthesis.getVoices();
      const ja = voices.find(v => /^ja/i.test(v.lang));
      const zh = voices.find(v => /^zh/i.test(v.lang));
      const u = new SpeechSynthesisUtterance(ja ? JA[word] : ZH[word]);
      u.voice = ja || zh || null;
      u.lang = ja ? 'ja-JP' : 'zh-CN';
      u.rate = 1.15; u.pitch = 1.25; u.volume = 0.9;
      speechSynthesis.cancel();
      speechSynthesis.speak(u);
    }
    return {
      unlock: ensure,
      discard: big => clack(big ? 0.9 : 0.55, big ? 1800 : 2600),
      draw: () => clack(0.25, 3400),
      hover: () => clack(0.08, 4200),
      call: w => { tone(660, 0.12, 'triangle', 0.18); tone(880, 0.16, 'triangle', 0.16, 0.08); speak(w); },
      riichi: () => { tone(523, 0.2, 'sawtooth', 0.1); tone(784, 0.3, 'triangle', 0.18, 0.1); speak('riichi'); },
      win: w => { [0, 4, 7, 12, 16].forEach((s, i) => tone(523 * Math.pow(2, s / 12), 0.25, 'triangle', 0.18, i * 0.07)); speak(w); },
      tick: () => tone(1200, 0.05, 'square', 0.06),
      count: () => tone(1500, 0.03, 'square', 0.04),
      stamp: () => { clack(1, 900); tone(220, 0.25, 'sine', 0.3); },
      close: () => { if (ac) { try { ac.close(); } catch { /* ignore */ } ac = null; } if (window.speechSynthesis) speechSynthesis.cancel(); }
    };
  }

  let inst = null;

  Hub.register({
    id: 'riichi', title: '日本麻将', group: 'game',
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="4" y="3" width="11" height="15" rx="2"/><path d="M8 7.5h3.5M9.75 7.5v6M7.5 11h4.5" stroke-linecap="round"/><path d="M15 6h3a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2v-1"/></svg>',
    mount(el, ctx) {
      const root = document.createElement('div');
      root.className = 'rq-root';
      el.appendChild(root);
      const cfg = Object.assign({
        players: 4, level: 'hard', length: 'east', akadora: true,
        timer: 'off', pace: 'normal', click: 'single', sound: true, voice: true,
        autoWin: false, noCall: false, autoDiscard: false
      }, ctx.store.get('cfg', {}));
      const saveCfg = () => ctx.store.set('cfg', cfg);
      const sfx = makeSound(cfg);
      let game = null, timers = [], replay = null, rewarded = false, scale = 1;
      const later = (fn, ms) => { const t = setTimeout(() => { timers = timers.filter(x => x !== t); fn(); }, ms); timers.push(t); return t; };
      const clearTimers = () => { timers.forEach(clearTimeout); timers = []; stopClock(); };
      const PACE = { fast: 0.55, normal: 1, slow: 1.5 };

      // ---------- scaling: the table grows with the window ----------
      function fit() {
        const wrap = root.querySelector('.rq-wrap');
        const table = root.querySelector('.rq-table');
        if (!wrap || !table) return;
        const host = el.parentElement || el;
        const cs = getComputedStyle(el);
        const aw = el.clientWidth - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0);
        const ah = (host.clientHeight || BASE_H) - (parseFloat(cs.paddingTop) || 0) - (parseFloat(cs.paddingBottom) || 0) - 4;
        scale = Math.max(0.75, Math.min(2, aw / BASE_W, ah / BASE_H));
        table.style.transform = `scale(${scale})`;
        wrap.style.width = BASE_W * scale + 'px';
        wrap.style.height = BASE_H * scale + 'px';
      }
      const ro = new ResizeObserver(fit);
      ro.observe(el.parentElement || el);

      // ================= lobby =================
      function lobby() {
        clearTimers();
        game = null; replay = null;
        const recs = ctx.store.get('records', []);
        const stats = ctx.store.get('stats', {});
        const st = k => stats[k] || { games: 0, first: 0, rankSum: 0 };
        const seg = (k, opts) => `<div class="rq-seg" data-k="${k}">${opts.map(([v, t]) => `<button data-v="${v}">${t}</button>`).join('')}</div>`;
        root.innerHTML = `
          <div class="rq-lobby">
            <div class="rq-card">
              <div class="rq-title">日本麻将 · 立直麻将</div>
              <div class="rq-row"><span>人数</span>${seg('players', [[4, '四人麻将'], [3, '三人麻将']])}</div>
              <div class="rq-row"><span>电脑</span>${seg('level', [['easy', '简单'], ['hard', '困难']])}</div>
              <div class="rq-row"><span>长度</span>${seg('length', [['east', '东风战'], ['south', '半庄战']])}</div>
              <div class="rq-row"><span>赤宝牌</span>${seg('akadora', [['true', '有'], ['false', '无']])}</div>
              <div class="rq-row"><span>思考时间</span>${seg('timer', [['off', '不限'], ['5+20', '5+20 秒'], ['3+10', '3+10 秒']])}</div>
              <div class="rq-row"><span>出牌</span>${seg('click', [['single', '单击出牌'], ['double', '双击出牌']])}</div>
              <div class="rq-row"><span>节奏</span>${seg('pace', [['fast', '快'], ['normal', '标准'], ['slow', '慢']])}</div>
              <div class="rq-row"><span>声音</span>${seg('sound', [['true', '音效开'], ['false', '音效关']])}${seg('voice', [['true', '语音开'], ['false', '语音关']])}</div>
              <button class="rq-btn rq-primary rq-start">开始对局</button>
              <div class="rq-note">食断有、击飞结束${cfg.players === 3 ? '；三麻去除二～八万、无吃、北可拔北' : ''}。可以拖动手牌向上甩出，悬停手牌会显示听牌提示。</div>
              <div class="rq-stats">
                ${['4-easy', '4-hard', '3-easy', '3-hard'].map(k => { const s = st(k); const [p, l] = k.split('-');
                  return `<div><b>${p}人·${l === 'easy' ? '简单' : '困难'}</b><span>${s.games} 局 · 一位 ${s.first} · 平均顺位 ${s.games ? (s.rankSum / s.games).toFixed(2) : '—'}</span></div>`; }).join('')}
              </div>
            </div>
            <div class="rq-card rq-recs">
              <div class="rq-title">牌谱</div>
              <div class="rq-reclist">${recs.length ? recs.map((r, i) => `
                <div class="rq-rec" data-i="${i}">
                  <div><b>${r.players}人${r.length === 'east' ? '东风' : '半庄'} · ${r.level === 'easy' ? '简单' : '困难'}</b>
                  <span>${new Date(r.at).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })} · 第 ${r.rank} 位 · ${r.score} 点</span></div>
                  <div class="rq-recbtns"><button class="rq-btn" data-a="view">回放</button><button class="rq-btn" data-a="del">删除</button></div>
                </div>`).join('') : '<div class="rq-empty">打完一局后会自动保存牌谱，可在这里回放。</div>'}</div>
            </div>
          </div>`;
        for (const s of root.querySelectorAll('.rq-seg')) {
          s.querySelectorAll('button').forEach(b => b.classList.toggle('on', String(cfg[s.dataset.k]) === b.dataset.v));
        }
        root.querySelector('.rq-lobby').onclick = e => {
          const b = e.target.closest('button');
          if (!b) return;
          const s = b.closest('.rq-seg');
          if (s) {
            const k = s.dataset.k, v = b.dataset.v;
            cfg[k] = k === 'players' ? Number(v) : v === 'true' ? true : v === 'false' ? false : v;
            saveCfg();
            return lobby();
          }
          if (b.classList.contains('rq-start')) { sfx.unlock(); return start(); }
          const rec = b.closest('.rq-rec');
          if (rec) {
            const i = Number(rec.dataset.i);
            const list = ctx.store.get('records', []);
            if (b.dataset.a === 'del') { list.splice(i, 1); ctx.store.set('records', list); return lobby(); }
            if (b.dataset.a === 'view') return openReplay(list[i]);
          }
        };
      }

      // ================= table =================
      // Every seat is laid out like the bottom seat inside a full-size panel that is then rotated
      // around the table centre. Tags, buttons and overlays live outside the rotated panels.
      function buildTable(n) {
        root.innerHTML = `
          <div class="rq-wrap"><div class="rq-table rq-p${n}">
            <div class="rq-sq">
              <div class="rq-center">
                ${SEAT_POS[n].map((p, s) => `<div class="rq-cside rq-c-${p}" data-s="${s}"><em></em><b></b></div>`).join('')}
                <div class="rq-round"></div>
                <div class="rq-info"><span class="rq-wall"></span></div>
                <div class="rq-sticks"></div>
              </div>
              ${SEAT_POS[n].map((p, s) => `
                <div class="rq-seat rq-panel rq-${p} ${s === 0 ? 'rq-self' : 'rq-opp'}" data-s="${s}">
                  <div class="rq-stickpos"></div>
                  <div class="rq-river"></div>
                  <div class="rq-handrow"><div class="rq-hand"></div><div class="rq-melds"></div></div>
                </div>`).join('')}
            </div>
            <div class="rq-dorabox"><span>宝牌指示</span><div class="rq-dora"></div></div>
            ${SEAT_POS[n].map((p, s) => `<div class="rq-tag rq-tag-${p}" data-s="${s}">${avatar(s)}<div class="rq-name"></div></div>`).join('')}
            <div class="rq-assist">
              <button class="rq-pill" data-a="menu">⟵ 大厅</button>
              <button class="rq-pill" data-t="autoWin">自动和牌</button>
              <button class="rq-pill" data-t="noCall">不吃碰杠</button>
              <button class="rq-pill" data-t="autoDiscard">自动摸切</button>
            </div>
            <div class="rq-waits rq-hidden"></div>
            <div class="rq-timer rq-hidden"></div>
            <div class="rq-callbar"></div>
            <div class="rq-chis rq-hidden"></div>
            <div class="rq-fx"></div>
            <div class="rq-toolbar"></div>
            <div class="rq-log rq-hidden"></div>
            <div class="rq-result rq-hidden"></div>
          </div></div>`;
        root.querySelectorAll('[data-t]').forEach(b => b.classList.toggle('on', !!cfg[b.dataset.t]));
        fit();
      }

      // ---------- rendering ----------
      function render(v, opts) {
        opts = opts || {};
        const n = v.players;
        const table = root.querySelector('.rq-table');
        if (!table) return;
        const q = s => table.querySelector(s);
        const self = 0;
        q('.rq-round').textContent = `${R.WIND_NAMES[v.round]}${['一', '二', '三', '四'][v.kyoku]}局`;
        q('.rq-wall').textContent = `余 ${v.wallLeft}`;
        q('.rq-sticks').innerHTML = `<span class="rq-stk100">${v.honba}</span><span class="rq-stk1000">${v.sticks}</span>`;
        const dora = q('.rq-dora');
        dora.innerHTML = '';
        for (let i = 0; i < 5; i++) dora.appendChild(tileEl(i < v.dora.length ? v.dora[i] : null, 'rq-sm'));
        const doraKinds = new Set(v.dora.map(id => R.doraOf(R.kindOf(id), n === 3)));
        const flip = !opts.readonly ? captureHand() : null;
        for (let s = 0; s < n; s++) {
          const pos = SEAT_POS[n][s];
          const side = q(`.rq-cside[data-s="${s}"]`);
          side.querySelector('em').textContent = R.WIND_NAMES[(s - v.dealer + n) % n];
          side.querySelector('b').textContent = v.scores[s];
          side.classList.toggle('turn', s === v.turn);
          side.classList.toggle('dealer', s === v.dealer);
          const seat = q(`.rq-seat[data-s="${s}"]`);
          seat.querySelector('.rq-stickpos').classList.toggle('on', !!v.riichi[s]);
          const river = seat.querySelector('.rq-river');
          river.innerHTML = '';
          for (const d of v.rivers[s]) {
            const t = tileEl(d.tile, 'rq-rv' + (d.riichi ? ' rq-riichi' : '') + (d.called ? ' rq-called' : '') + (d.tsumogiri ? ' rq-tg' : ''));
            if (v.lastDiscard && v.lastDiscard.tile === d.tile && v.lastDiscard.seat === s) t.classList.add('rq-last');
            river.appendChild(t);
          }
          const hand = seat.querySelector('.rq-hand');
          hand.innerHTML = '';
          const showAll = opts.showAll || s === self;
          const tiles = opts.hands ? opts.hands[s] : s === self ? v.hand : new Array(v.handSizes[s]).fill(null);
          const drawn = s === v.turn ? (opts.drawn != null ? opts.drawn : v.drawn) : null;
          const body = sortHand(tiles.filter(x => x !== drawn || x == null));
          const mine = s === self && !opts.readonly;
          for (const id of body) hand.appendChild(tileEl(showAll ? id : null, mine ? 'rq-mine' : ''));
          if (drawn != null && tiles.includes(drawn)) hand.appendChild(tileEl(showAll ? drawn : null, 'rq-drawn' + (mine ? ' rq-mine' : '')));
          else if (s !== self && s === v.turn && tiles.length % 3 === 2 && hand.lastElementChild) hand.lastElementChild.classList.add('rq-drawn');
          const melds = seat.querySelector('.rq-melds');
          melds.innerHTML = '';
          for (const m of v.melds[s]) {
            const g = document.createElement('div');
            g.className = 'rq-meld';
            m.ids.forEach((id, i) => {
              const hidden = m.type === 'ankan' && (i === 0 || i === 3);
              g.appendChild(tileEl(hidden ? null : id, 'rq-ml' + (id === m.called ? ' rq-side' : '')));
            });
            melds.appendChild(g);
          }
          if (v.kita[s]) {
            const g = document.createElement('div');
            g.className = 'rq-meld rq-kita';
            for (let i = 0; i < v.kita[s]; i++) g.appendChild(tileEl(30 * 4 + i, 'rq-ml'));
            melds.appendChild(g);
          }
          const tag = q(`.rq-tag[data-s="${s}"]`);
          tag.querySelector('.rq-name').innerHTML = `${NAMES[s]}${v.riichi[s] ? ' <b>立直</b>' : ''}`;
          tag.classList.toggle('rq-active', s === v.turn);
          void pos;
        }
        // dora glint on every visible dora tile
        table.querySelectorAll('.rq-tile[data-k]').forEach(t => { if (doraKinds.has(Number(t.dataset.k))) t.classList.add('rq-dorat'); });
        if (flip) playFlip(flip);
      }

      // FLIP: remember where each of my tiles was, then slide them into their new places
      function captureHand() {
        const m = new Map();
        root.querySelectorAll('.rq-self .rq-hand .rq-tile').forEach(t => m.set(t.dataset.id, t.getBoundingClientRect().left));
        return m;
      }
      function playFlip(old) {
        root.querySelectorAll('.rq-self .rq-hand .rq-tile').forEach(t => {
          const x0 = old.get(t.dataset.id);
          if (x0 == null) { if (old.size) t.classList.add('rq-new'); return; }
          const dx = (x0 - t.getBoundingClientRect().left) / scale;
          if (Math.abs(dx) > 1) t.animate([{ transform: `translateX(${dx}px)` }, { transform: 'none' }], { duration: 200, easing: 'cubic-bezier(.25,.8,.3,1)' });
        });
      }

      // discard flight from the hand into the river
      function fly(seat, src, big) {
        const table = root.querySelector('.rq-table');
        if (!table || !src) return;
        const dest = table.querySelector(`.rq-seat[data-s="${seat}"] .rq-river`).lastElementChild;
        if (!dest) return;
        const tr = table.getBoundingClientRect(), dr = dest.getBoundingClientRect();
        const pos = SEAT_POS[game ? game.n : 4][seat];
        const rot = SEAT_ROT[pos] + (dest.classList.contains('rq-riichi') ? 90 : 0);
        const w = dest.offsetWidth, h = dest.offsetHeight;
        const cx0 = (src.left + src.width / 2 - tr.left) / scale, cy0 = (src.top + src.height / 2 - tr.top) / scale;
        const cx1 = (dr.left + dr.width / 2 - tr.left) / scale, cy1 = (dr.top + dr.height / 2 - tr.top) / scale;
        const clone = dest.cloneNode(true);
        clone.classList.add('rq-flying');
        clone.style.left = cx1 - w / 2 + 'px';
        clone.style.top = cy1 - h / 2 + 'px';
        table.appendChild(clone);
        dest.style.visibility = 'hidden';
        const s0 = big ? 1.55 : 0.9;
        const a = clone.animate([
          { transform: `translate(${cx0 - cx1}px, ${cy0 - cy1}px) rotate(${SEAT_ROT[pos]}deg) scale(${s0})` },
          { transform: `translate(0, 0) rotate(${rot}deg) scale(1.08)`, offset: 0.85 },
          { transform: `translate(0, 0) rotate(${rot}deg) scale(1)` }
        ], { duration: big ? 210 : 170, easing: 'cubic-bezier(.2,.75,.3,1)' });
        a.onfinish = () => { clone.remove(); dest.style.visibility = ''; sfx.discard(big); };
      }

      // big call text (立直 / 荣 / 自摸 / 碰 …) next to the caller
      const WORDS = { chi: '吃', pon: '碰', daiminkan: '杠', ankan: '杠', kakan: '杠', riichi: '立直', ron: '荣', tsumo: '自摸', kita: '拔北' };
      const VOICE = { chi: 'chi', pon: 'pon', daiminkan: 'kan', ankan: 'kan', kakan: 'kan', riichi: 'riichi', ron: 'ron', tsumo: 'tsumo', kita: 'kita' };
      function announce(seat, a) {
        const w = WORDS[a.type];
        if (!w) return;
        const fx = root.querySelector('.rq-fx');
        if (!fx) return;
        const pos = SEAT_POS[game ? game.n : 4][seat];
        const b = document.createElement('div');
        b.className = `rq-bigcall rq-bc-${pos} rq-bc-${a.type}`;
        b.innerHTML = `<span>${w}</span>`;
        fx.appendChild(b);
        setTimeout(() => b.remove(), a.type === 'riichi' || a.type === 'ron' || a.type === 'tsumo' ? 1500 : 1000);
        if (a.type === 'riichi') sfx.riichi();
        else if (a.type === 'ron' || a.type === 'tsumo') sfx.win(VOICE[a.type]);
        else sfx.call(VOICE[a.type]);
      }

      // ================= game flow =================
      function start() {
        clearTimers();
        rewarded = false;
        game = new R.Game({ players: cfg.players, length: cfg.length, akadora: cfg.akadora, seed: (Math.random() * 2 ** 31) | 0 });
        bank = TIMER().bank;
        buildTable(game.n);
        bindTable();
        loop();
      }
      function bindTable() {
        const table = root.querySelector('.rq-table');
        table.addEventListener('pointerdown', onPointerDown);
        table.addEventListener('pointerover', onHover);
        table.addEventListener('pointerout', onHoverOut);
        table.addEventListener('contextmenu', e => { e.preventDefault(); if (mode === 'riichi') setMode(''); clearSel(); });
        table.querySelector('.rq-assist').onclick = e => {
          const b = e.target.closest('button');
          if (!b) return;
          if (b.dataset.a === 'menu') {
            if (game && !game.finished && !confirm('对局尚未结束，确定返回大厅吗？（本局不计成绩）')) return;
            return lobby();
          }
          const k = b.dataset.t;
          cfg[k] = !cfg[k];
          b.classList.toggle('on', cfg[k]);
          saveCfg();
          if (pendingHuman) applyAssists(pendingHuman);
        };
        table.querySelector('.rq-callbar').onclick = onCallbar;
        table.querySelector('.rq-chis').onclick = onChiPick;
      }

      let pendingHuman = null, botTimer = null, mode = '', selected = null, tenpaiMap = new Map();
      function loop() {
        if (!game || !inst) return;
        render(game.visibleState(0));
        if (game.finished) return later(gameEnd, 600);
        const pend = game.pending();
        if (pend[0].seat === -1) return later(showResult, 700);
        const me = pend.find(p => p.seat === 0);
        const bots = pend.filter(p => p.seat !== 0);
        if (bots.length && (!me || game.phase === 'call')) {
          const seat = bots[0].seat;
          const base = game.phase === 'call' ? 260 : cfg.level === 'hard' ? 620 : 520;
          const delay = (base + Math.random() * 260) * PACE[cfg.pace];
          if (botTimer) { clearTimeout(botTimer); timers = timers.filter(x => x !== botTimer); }
          botTimer = later(() => {
            botTimer = null;
            if (!game) return;
            const cur = game.pending().find(x => x.seat === seat);
            if (!cur) return loop();
            const a = AI.decide(game.visibleState(seat), cur.actions, cfg.level);
            const src = a.type === 'discard' || a.type === 'riichi' ? botSource(seat) : null;
            announce(seat, a);
            game.act(seat, a);
            loop();
            if (src) fly(seat, src, false);
          }, delay);
          if (!me) return;
        }
        if (me) return askHuman(me);
      }
      function botSource(seat) {
        const hand = root.querySelector(`.rq-seat[data-s="${seat}"] .rq-hand`);
        const t = hand && (hand.querySelector('.rq-drawn') || hand.lastElementChild);
        return t ? t.getBoundingClientRect() : null;
      }

      // ---------- my turn / my calls ----------
      function askHuman(p) {
        pendingHuman = p;
        setMode('');
        clearSel();
        const v = game.visibleState(0);
        computeTenpai(p);
        renderCallbar(p);
        renderWaits(v);
        if (applyAssists(p)) return;
        startClock(p);
        if (game.phase === 'turn' && game.drawn != null) sfx.draw();
      }
      // assist toggles and forced moves; returns true when an action was taken automatically
      function applyAssists(p) {
        const acts = p.actions;
        const v = game.visibleState(0);
        const win = acts.find(a => a.type === 'tsumo' || a.type === 'ron');
        if (win && cfg.autoWin) { later(() => humanAct(win), 350); return true; }
        if (game.phase === 'call' && !win) {
          if (cfg.noCall || (acts.length === 1 && acts[0].type === 'pass')) { later(() => humanAct(acts.find(a => a.type === 'pass')), 60); return true; }
        }
        if (game.phase === 'turn') {
          const onlyDiscard = acts.every(a => a.type === 'discard');
          if (onlyDiscard && (v.riichi[0] || cfg.autoDiscard)) {
            later(() => humanAct(acts.find(a => a.tile === game.drawn) || acts[acts.length - 1], true), 420 * PACE[cfg.pace]);
            return true;
          }
        }
        return false;
      }
      // which discards leave me in tenpai, and on what
      function computeTenpai(p) {
        tenpaiMap = new Map();
        if (game.phase !== 'turn') return;
        const v = game.visibleState(0);
        const seen = visibleCounts(v);
        const melds = v.melds[0].length;
        const riichiOk = new Set(p.actions.filter(a => a.type === 'riichi').map(a => a.tile));
        for (const id of v.hand) {
          const k = R.kindOf(id);
          if (tenpaiMap.has('k' + k)) { tenpaiMap.set(id, tenpaiMap.get('k' + k)); continue; }
          const c = R.countsOf(v.hand.filter(x => x !== id));
          const w = R.waitsOf(c, melds);
          const info = w.length ? { waits: w.map(kk => ({ k: kk, left: Math.max(0, 4 - seen[kk] - (kk === k ? 0 : 0)) })), riichi: riichiOk.has(id) } : null;
          if (info) info.total = info.waits.reduce((a, b) => a + b.left, 0);
          tenpaiMap.set('k' + k, info);
          tenpaiMap.set(id, info);
        }
        root.querySelectorAll('.rq-self .rq-mine').forEach(t => t.classList.toggle('rq-tp', !!tenpaiMap.get(Number(t.dataset.id))));
      }
      function visibleCounts(v) {
        const c = new Array(34).fill(0);
        for (const id of v.hand) c[R.kindOf(id)]++;
        for (const r of v.rivers) for (const d of r) if (!d.called) c[R.kindOf(d.tile)]++;
        for (const ms of v.melds) for (const m of ms) for (const id of m.ids) c[R.kindOf(id)]++;
        for (const id of v.dora) c[R.kindOf(id)]++;
        for (let s = 0; s < v.players; s++) c[30] += v.kita[s];
        return c;
      }
      function renderWaits(v) {
        const box = root.querySelector('.rq-waits');
        if (!box) return;
        let waits = null;
        if (v.hand.length % 3 === 1) {
          const w = R.waitsOf(R.countsOf(v.hand), v.melds[0].length);
          if (w.length) { const seen = visibleCounts(v); waits = w.map(k => ({ k, left: Math.max(0, 4 - seen[k]) })); }
        }
        if (!waits) { box.classList.add('rq-hidden'); return; }
        box.classList.remove('rq-hidden');
        box.innerHTML = `<b>听</b>${waits.map(w => `<span class="rq-wt">${tileHtml(w.k * 4, 'rq-xs')}<i>${w.left}</i></span>`).join('')}${v.furiten ? '<em>振听</em>' : ''}`;
      }

      function renderCallbar(p) {
        const bar = root.querySelector('.rq-callbar');
        const chis = root.querySelector('.rq-chis');
        chis.classList.add('rq-hidden');
        const acts = p.actions;
        const btns = [];
        const LABEL = { tsumo: '自摸', ron: '荣和', pon: '碰', chi: '吃', daiminkan: '杠', ankan: '杠', kakan: '加杠', kita: '拔北', kyuushu: '流局', pass: '跳过' };
        const cls = { tsumo: 'win', ron: 'win', pon: 'pon', chi: 'chi', daiminkan: 'kan', ankan: 'kan', kakan: 'kan', kita: 'kan', kyuushu: 'pass', pass: 'pass' };
        let chiDone = false;
        for (const a of acts) {
          if (a.type === 'discard' || a.type === 'riichi') continue;
          if (a.type === 'chi') {
            if (chiDone) continue;
            chiDone = true;
            const n = acts.filter(x => x.type === 'chi').length;
            btns.push(`<button class="rq-cb rq-cb-chi" data-chi="1" data-n="${n}"><span>吃</span></button>`);
            continue;
          }
          const extra = a.kind != null ? tileHtml(a.kind * 4, 'rq-xs') : a.type === 'kakan' ? tileHtml(a.tile, 'rq-xs') : '';
          btns.push(`<button class="rq-cb rq-cb-${cls[a.type]}" data-act='${JSON.stringify(a)}'><span>${LABEL[a.type]}</span>${extra}</button>`);
        }
        if (acts.some(a => a.type === 'riichi')) btns.unshift('<button class="rq-cb rq-cb-riichi" data-riichi="1"><span>立直</span></button>');
        bar.innerHTML = btns.join('');
      }
      function onCallbar(e) {
        const b = e.target.closest('button');
        if (!b || !pendingHuman) return;
        e.stopPropagation();
        if (b.dataset.riichi) return setMode(mode === 'riichi' ? '' : 'riichi');
        if (b.dataset.chi) {
          const opts = pendingHuman.actions.filter(a => a.type === 'chi');
          if (opts.length === 1) return humanAct(opts[0]);
          const box = root.querySelector('.rq-chis');
          const called = game.visibleState(0).callTile;
          box.innerHTML = opts.map((a, i) => `<button data-i="${i}">${sortHand(a.tiles.concat([called])).map(id => tileHtml(id, id === called ? 'rq-xs rq-called-t' : 'rq-xs')).join('')}</button>`).join('');
          box.classList.toggle('rq-hidden');
          return;
        }
        if (b.dataset.act) humanAct(JSON.parse(b.dataset.act));
      }
      function onChiPick(e) {
        const b = e.target.closest('button');
        if (!b || !pendingHuman) return;
        const opts = pendingHuman.actions.filter(a => a.type === 'chi');
        humanAct(opts[Number(b.dataset.i)]);
      }
      function setMode(m) {
        mode = m;
        const rb = root.querySelector('.rq-cb-riichi');
        if (rb) rb.classList.toggle('on', m === 'riichi');
        const ok = pendingHuman ? new Set(pendingHuman.actions.filter(a => a.type === 'riichi').map(a => a.tile)) : new Set();
        root.querySelectorAll('.rq-self .rq-mine').forEach(t => t.classList.toggle('rq-dim', m === 'riichi' && !ok.has(Number(t.dataset.id))));
      }
      function clearSel() {
        selected = null;
        root.querySelectorAll('.rq-self .rq-sel').forEach(t => t.classList.remove('rq-sel'));
      }

      // tile clicks, double-click mode and drag-to-discard
      let drag = null;
      function tryDiscard(t) {
        if (!pendingHuman || game.phase !== 'turn') return false;
        const id = Number(t.dataset.id);
        const want = mode === 'riichi' ? 'riichi' : 'discard';
        const a = pendingHuman.actions.find(x => x.type === want && x.tile === id);
        if (!a) {
          ctx.toast(want === 'riichi' ? '这张牌打出后不能听牌' : game.visibleState(0).riichi[0] ? '立直后只能摸切' : '这张牌现在不能打（食替限制）');
          t.animate([{ transform: 'translateX(-4px)' }, { transform: 'translateX(4px)' }, { transform: 'none' }], { duration: 180 });
          return false;
        }
        humanAct(a, false, t.getBoundingClientRect());
        return true;
      }
      function onPointerDown(e) {
        const t = e.target.closest('.rq-mine');
        if (!t || e.button !== 0) return;
        sfx.unlock();
        drag = { t, x: e.clientX, y: e.clientY, moved: false, id: e.pointerId };
        t.setPointerCapture(e.pointerId);
        t.addEventListener('pointermove', onPointerMove);
        t.addEventListener('pointerup', onPointerUp, { once: true });
      }
      function onPointerMove(e) {
        if (!drag) return;
        const dx = (e.clientX - drag.x) / scale, dy = (e.clientY - drag.y) / scale;
        if (!drag.moved && Math.hypot(dx, dy) < 6) return;
        drag.moved = true;
        drag.t.classList.add('rq-dragging');
        drag.t.style.transform = `translate(${dx}px, ${dy}px) scale(1.08)`;
        drag.dy = dy;
      }
      function onPointerUp() {
        const d = drag;
        drag = null;
        if (!d) return;
        d.t.removeEventListener('pointermove', onPointerMove);
        d.t.classList.remove('rq-dragging');
        if (d.moved) {
          if (d.dy < -45 && tryDiscard(d.t)) return;
          d.t.style.transform = '';
          return;
        }
        // plain click
        if (cfg.click === 'double' && selected !== d.t) {
          clearSel();
          selected = d.t;
          d.t.classList.add('rq-sel');
          sfx.hover();
          return;
        }
        tryDiscard(d.t);
      }

      // hover: lift, highlight same kind everywhere, show waits for that discard
      function onHover(e) {
        const t = e.target.closest('.rq-tile[data-k]');
        if (!t) return;
        const k = t.dataset.k;
        root.querySelectorAll(`.rq-table .rq-tile[data-k="${k}"]`).forEach(x => x.classList.add('rq-same'));
        if (!t.classList.contains('rq-mine')) return;
        sfx.hover();
        const info = tenpaiMap.get(Number(t.dataset.id));
        if (!info || drag) return;
        const tip = document.createElement('div');
        tip.className = 'rq-tip';
        tip.innerHTML = `<div class="rq-tip-h">${info.riichi && pendingHuman && pendingHuman.actions.some(a => a.type === 'riichi') ? '可立直 · ' : ''}听 ${info.waits.length} 种 ${info.total} 张</div>
          <div class="rq-tip-w">${info.waits.map(w => `<span>${tileHtml(w.k * 4, 'rq-xs')}<i>${w.left}</i></span>`).join('')}</div>`;
        t.appendChild(tip);
      }
      function onHoverOut(e) {
        const t = e.target.closest('.rq-tile[data-k]');
        if (!t || (e.relatedTarget && t.contains(e.relatedTarget))) return;
        root.querySelectorAll('.rq-same').forEach(x => x.classList.remove('rq-same'));
        t.querySelectorAll('.rq-tip').forEach(x => x.remove());
      }

      function humanAct(a, auto, srcRect) {
        if (!pendingHuman || !game || !a) return;
        pendingHuman = null;
        stopClock();
        root.querySelector('.rq-callbar').innerHTML = '';
        root.querySelector('.rq-chis').classList.add('rq-hidden');
        if (!srcRect && (a.type === 'discard' || a.type === 'riichi')) {
          const el0 = root.querySelector(`.rq-self .rq-mine[data-id="${a.tile}"]`);
          srcRect = el0 && el0.getBoundingClientRect();
        }
        announce(0, a);
        try { game.act(0, a); } catch (err) { console.error(err); }
        if (botTimer) { clearTimeout(botTimer); timers = timers.filter(x => x !== botTimer); botTimer = null; }
        loop();
        if (srcRect) fly(0, srcRect, true);
        void auto;
      }

      // ---------- thinking clock (optional) ----------
      let bank = 0, clockT = null;
      const TIMER = () => ({ off: { base: 0, bank: 0 }, '5+20': { base: 5, bank: 20 }, '3+10': { base: 3, bank: 10 } })[cfg.timer] || { base: 0, bank: 0 };
      function startClock(p) {
        stopClock();
        const T = TIMER();
        const box = root.querySelector('.rq-timer');
        if (!T.base || !box) return;
        let base = T.base;
        box.classList.remove('rq-hidden');
        const draw = () => { box.innerHTML = `<b>${Math.ceil(base)}</b>${bank > 0 ? `<span>+${Math.ceil(bank)}</span>` : ''}`; box.classList.toggle('warn', base <= 0 && bank <= 5); };
        draw();
        clockT = setInterval(() => {
          if (!ctx.isActive()) return;
          if (base > 0) base = Math.max(0, base - 0.25); else bank = Math.max(0, bank - 0.25);
          if (base <= 0 && bank > 0 && bank <= 5 && Math.abs(bank - Math.round(bank)) < 0.01) sfx.tick();
          draw();
          if (base <= 0 && bank <= 0) {
            stopClock();
            const acts = p.actions;
            const fallback = acts.find(a => a.type === 'pass') || acts.find(a => a.type === 'discard' && a.tile === game.drawn) || acts.filter(a => a.type === 'discard').pop();
            if (fallback) humanAct(fallback, true);
          }
        }, 250);
      }
      function stopClock() {
        clearInterval(clockT); clockT = null;
        const box = root.querySelector('.rq-timer');
        if (box) box.classList.add('rq-hidden');
      }

      // ================= results =================
      const LIMIT_CLASS = { '满贯': 'mangan', '跳满': 'haneman', '倍满': 'baiman', '三倍满': 'sanbaiman', '累计役满': 'yakuman', '役满': 'yakuman' };
      function showResult() {
        if (!game) return;
        const r = game.handResult;
        const box = root.querySelector('.rq-result');
        const pages = [];
        if (r.type === 'agari') {
          for (const w of r.wins) pages.push(() => agariPage(box, w, r));
          if (r.wins.some(w => w.seat === 0)) {
            const w = r.wins.find(x => x.seat === 0);
            ctx.say(w.yakuman ? '役满！！太厉害了！' : w.han >= 6 ? `${w.name}！${w.points} 点！` : `和牌啦！${w.points} 点`);
          }
        } else pages.push(() => ryuukyokuPage(box, r));
        pages.push(() => scorePage(box, r));
        let i = 0;
        const next = () => {
          if (i >= pages.length) {
            box.classList.add('rq-hidden');
            game.act(-1, { type: 'next' });
            bank = TIMER().bank;
            return loop();
          }
          pages[i++]();
          const btn = box.querySelector('.rq-ok');
          if (btn) btn.onclick = next;
        };
        box.classList.remove('rq-hidden');
        next();
      }
      function agariPage(box, w, r) {
        const hand = sortHand(w.hand.filter(x => !(w.tsumo && x === w.tile)));
        const limit = w.yakuman ? (w.yakuman > 1 ? `${w.yakuman}倍役满` : '役满') : w.name;
        box.innerHTML = `
          <div class="rq-res-card rq-agari">
            <img class="rq-res-art" src="${imgCache.get(petFile(w.seat)) || ''}" alt="">
            <div class="rq-res-top"><div class="rq-res-who">${avatar(w.seat, true)}<div><b>${NAMES[w.seat]}</b><span>${w.tsumo ? '自摸' : `荣和 · ${NAMES[w.from]} 放铳`}</span></div></div>
              <div class="rq-res-kind rq-bc-${w.tsumo ? 'tsumo' : 'ron'}">${w.tsumo ? '自摸' : '荣'}</div></div>
            <div class="rq-res-tiles">${hand.map(id => tileHtml(id, 'rq-md')).join('')}<span class="rq-gap"></span>${tileHtml(w.tile, 'rq-md rq-win')}
              ${w.melds.map(m => `<span class="rq-gap"></span>${m.ids.map(id => tileHtml(id, 'rq-md')).join('')}`).join('')}</div>
            <div class="rq-res-dora"><span>宝牌</span>${r.dora.map(id => tileHtml(id, 'rq-xs')).join('')}${w.ura && w.ura.length ? `<span>里宝牌</span>${w.ura.map(id => tileHtml(id, 'rq-xs')).join('')}` : ''}</div>
            <div class="rq-yakus">${w.yaku.map(([nm, h], i) => `<div class="rq-yk" style="animation-delay:${0.25 + i * 0.22}s"><span>${nm}</span><b>${typeof h === 'number' ? h + ' 番' : h}</b></div>`).join('')}</div>
            <div class="rq-res-sum" style="animation-delay:${0.35 + w.yaku.length * 0.22}s">
              <span>${w.yakuman ? '' : `${w.han} 番 ${w.fu} 符`}</span><b class="rq-pts">0</b><em>点</em>
              ${limit ? `<div class="rq-stamp rq-st-${LIMIT_CLASS[w.name] || (w.yakuman ? 'yakuman' : 'mangan')}">${limit}</div>` : ''}
            </div>
            <button class="rq-btn rq-primary rq-ok">确定</button>
          </div>`;
        const delay = (0.35 + w.yaku.length * 0.22) * 1000;
        w.yaku.forEach((_, i) => later(() => sfx.count(), 250 + i * 220));
        later(() => countUp(box.querySelector('.rq-pts'), w.points, 700), delay);
        if (limit) later(() => sfx.stamp(), delay + 750);
      }
      function ryuukyokuPage(box, r) {
        const n = game.n;
        const hands = r.reason === '荒牌流局' ? r.tenpai.map(s => `<div class="rq-rk-hand"><b>${NAMES[s]} 听牌</b><div>${sortHand(game.hands[s]).map(id => tileHtml(id, 'rq-xs')).join('')}</div></div>`).join('') : '';
        box.innerHTML = `
          <div class="rq-res-card">
            <div class="rq-ryu">${r.reason === '荒牌流局' ? '流局' : r.reason}</div>
            ${r.reason === '荒牌流局' ? `<div class="rq-tenpai">${[...Array(n).keys()].map(s => `<span class="${r.tenpai.includes(s) ? 'on' : ''}">${NAMES[s]} ${r.tenpai.includes(s) ? '听牌' : '未听'}</span>`).join('')}</div>` : ''}
            ${hands}
            <button class="rq-btn rq-primary rq-ok">确定</button>
          </div>`;
      }
      function scorePage(box, r) {
        const n = game.n;
        const before = r.scores.map((s, i) => s - r.delta[i]);
        box.innerHTML = `
          <div class="rq-res-card rq-scorecard">
            <div class="rq-res-h">点数变动</div>
            ${[...Array(n).keys()].map(s => `
              <div class="rq-srow ${s === 0 ? 'me' : ''}">
                ${avatar(s)}<span class="rq-sn">${NAMES[s]}</span>
                <b class="rq-sv" data-s="${s}">${before[s]}</b>
                <em class="${r.delta[s] > 0 ? 'up' : r.delta[s] < 0 ? 'down' : ''}">${r.delta[s] > 0 ? '+' : ''}${r.delta[s] || ''}</em>
              </div>`).join('')}
            <button class="rq-btn rq-primary rq-ok">继续</button>
          </div>`;
        later(() => box.querySelectorAll('.rq-sv').forEach(b => countUp(b, r.scores[Number(b.dataset.s)], 800, Number(b.textContent))), 350);
      }
      function countUp(el, to, ms, from) {
        if (!el) return;
        from = from || 0;
        const t0 = performance.now();
        const step = t => {
          const k = Math.min(1, (t - t0) / ms);
          el.textContent = Math.round(from + (to - from) * (1 - Math.pow(1 - k, 3)));
          if (k < 1 && el.isConnected) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
      }

      function gameEnd() {
        if (!game) return;
        const ranks = game.ranks();
        const myRank = ranks[0];
        const key = `${game.n}-${cfg.level}`;
        const stats = ctx.store.get('stats', {});
        const s = stats[key] || (stats[key] = { games: 0, first: 0, rankSum: 0 });
        s.games++; s.rankSum += myRank; if (myRank === 1) s.first++;
        ctx.store.set('stats', stats);
        const rec = game.record();
        const list = ctx.store.get('records', []);
        list.unshift({ at: Date.now(), players: game.n, level: cfg.level, length: cfg.length, rank: myRank, score: game.scores[0], rec });
        ctx.store.set('records', list.slice(0, MAX_RECORDS));
        let coins = 0;
        if (!rewarded && myRank === 1) {
          rewarded = true;
          coins = (cfg.level === 'hard' ? 15 : 6) + (cfg.length === 'south' ? 8 : 0);
          ctx.reward(coins, '日本麻将一位');
          ctx.say('日麻一位！太强啦！');
        } else if (myRank === game.n) ctx.say('四位也没关系，下局一定行！');
        const box = root.querySelector('.rq-result');
        const order = [...Array(game.n).keys()].sort((a, b) => ranks[a] - ranks[b]);
        box.innerHTML = `
          <div class="rq-res-card rq-final">
            <div class="rq-res-h">对局结束</div>
            ${order.map((p, i) => `
              <div class="rq-frow r${ranks[p]} ${p === 0 ? 'me' : ''}" style="animation-delay:${0.15 + (game.n - 1 - i) * 0.25}s">
                <div class="rq-rank">${ranks[p]}</div>${avatar(p)}<span>${NAMES[p]}</span><b>${game.scores[p]}</b>
              </div>`).join('')}
            <div class="rq-note">${coins ? `获得 ${coins} 小鱼干 · ` : ''}牌谱已保存，可在大厅回放。</div>
            <div class="rq-btnrow"><button class="rq-btn" data-e="replay">查看牌谱</button><button class="rq-btn" data-e="lobby">返回大厅</button><button class="rq-btn rq-primary" data-e="again">再来一局</button></div>
          </div>`;
        box.classList.remove('rq-hidden');
        sfx.win(myRank === 1 ? 'tsumo' : null);
        box.onclick = e => {
          const b = e.target.closest('button');
          if (!b) return;
          box.onclick = null;
          if (b.dataset.e === 'again') start();
          else if (b.dataset.e === 'lobby') lobby();
          else openReplay(list[0]);
        };
      }

      // ================= replay viewer =================
      function openReplay(entry) {
        clearTimers();
        game = null;
        const rep = R.Replay(entry.rec);
        const n = entry.rec.opts.players;
        let i = rep.hands[0] || 0, playing = null;
        replay = rep;
        buildTable(n);
        const table = root.querySelector('.rq-table');
        table.classList.add('rq-replay');
        table.querySelector('.rq-assist').innerHTML = '<button class="rq-pill" data-r="menu">⟵ 大厅</button>';
        table.querySelector('.rq-toolbar').innerHTML = `
          <button class="rq-btn" data-r="ph">⏮ 上一局</button><button class="rq-btn" data-r="prev">◀</button>
          <button class="rq-btn rq-primary" data-r="play">▶ 播放</button>
          <button class="rq-btn" data-r="next">▶</button><button class="rq-btn" data-r="nh">下一局 ⏭</button>
          <span class="rq-step"></span>`;
        const log = table.querySelector('.rq-log');
        log.classList.remove('rq-hidden');
        table.addEventListener('pointerover', onHover);
        table.addEventListener('pointerout', onHoverOut);
        const show = () => {
          const step = rep.stepTo(i);
          const v = step.view;
          if (v && v.hands) {
            const vis = {
              players: n, round: v.round, kyoku: v.kyoku, honba: v.honba, sticks: v.sticks, dealer: v.dealer, turn: v.turn,
              scores: v.scores, dora: v.dora, wallLeft: v.wallLeft, rivers: v.rivers, melds: v.melds, riichi: v.riichi, kita: v.kita,
              handSizes: v.hands.map(h => h.length), hand: v.hands[0], drawn: v.drawn, lastDiscard: null
            };
            render(vis, { showAll: true, readonly: true, hands: v.hands, drawn: v.drawn });
          }
          table.querySelector('.rq-step').textContent = `${i + 1} / ${rep.length}`;
          log.textContent = R.describe(step.ev, NAMES);
          log.classList.toggle('big', step.ev.t === 'agari' || step.ev.t === 'ryuukyoku');
        };
        const stop = () => { if (playing) { clearInterval(playing); playing = null; table.querySelector('[data-r=play]').textContent = '▶ 播放'; } };
        table.onclick = e => {
          const b = e.target.closest('button[data-r]');
          if (!b) return;
          const r = b.dataset.r;
          if (r === 'menu') { stop(); return lobby(); }
          if (r === 'play') {
            if (playing) return stop();
            b.textContent = '⏸ 暂停';
            playing = setInterval(() => { if (i >= rep.length - 1) return stop(); i++; show(); }, 450);
            timers.push(playing);
            return;
          }
          stop();
          if (r === 'prev') i = Math.max(0, i - 1);
          if (r === 'next') i = Math.min(rep.length - 1, i + 1);
          if (r === 'ph') i = [...rep.hands].reverse().find(h => h < i) ?? rep.hands[0];
          if (r === 'nh') i = rep.hands.find(h => h > i) ?? rep.length - 1;
          show();
        };
        onKey = e => {
          if (!ctx.isActive() || !replay) return;
          if (e.key === 'ArrowRight') { stop(); i = Math.min(rep.length - 1, i + 1); show(); }
          if (e.key === 'ArrowLeft') { stop(); i = Math.max(0, i - 1); show(); }
        };
        show();
      }
      let onKey = null;
      const keyHandler = e => {
        if (onKey) onKey(e);
        if (!ctx.isActive() || !pendingHuman) return;
        // Space = skip a call offer, Esc = cancel riichi mode
        if (e.key === ' ' && game && game.phase === 'call') { const p = pendingHuman.actions.find(a => a.type === 'pass'); if (p) { e.preventDefault(); humanAct(p); } }
        if (e.key === 'Escape' && mode === 'riichi') setMode('');
      };
      window.addEventListener('keydown', keyHandler);

      inst = { cleanup() { clearTimers(); ro.disconnect(); sfx.close(); window.removeEventListener('keydown', keyHandler); root.remove(); } };
      lobby();
    },
    unmount() { if (inst) { inst.cleanup(); inst = null; } }
  });
})();
