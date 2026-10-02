// 日本麻将 (立直麻将) rules engine. Browser: window.Riichi. Node: module.exports.
// Tiles: 136 ids, kind = id >> 2 (0-8 万 1-9, 9-17 筒, 18-26 索, 27-30 东南西北, 31-33 白发中).
// Red fives (akadora): ids 16 (5m), 52 (5p), 88 (5s).
(function (root) {
  'use strict';

  // ================= tiles =================
  const RED = new Set([16, 52, 88]);
  const kindOf = id => id >> 2;
  const isHonor = k => k >= 27;
  const isTerm = k => k < 27 && (k % 9 === 0 || k % 9 === 8);
  const isYao = k => isHonor(k) || isTerm(k);
  const suitOf = k => (k < 27 ? Math.floor(k / 9) : 3);
  const numOf = k => (k < 27 ? (k % 9) + 1 : 0);
  const KIND_NAMES = [];
  (() => {
    const CN = '一二三四五六七八九';
    for (let i = 0; i < 9; i++) KIND_NAMES.push(CN[i] + '万');
    for (let i = 0; i < 9; i++) KIND_NAMES.push(CN[i] + '筒');
    for (let i = 0; i < 9; i++) KIND_NAMES.push(CN[i] + '索');
    KIND_NAMES.push('东', '南', '西', '北', '白', '发', '中');
  })();
  const WIND_NAMES = ['东', '南', '西', '北'];
  function tileName(id) { return (RED.has(id) ? '赤' : '') + KIND_NAMES[kindOf(id)]; }
  // compact notation used in replays: 1m..9m, 1p.., 1s.., 1z..7z, 0 = red five
  function tileCode(id) {
    const k = kindOf(id);
    if (k >= 27) return (k - 26) + 'z';
    return (RED.has(id) ? 0 : numOf(k)) + 'mps'[suitOf(k)];
  }
  function countsOf(ids) {
    const c = new Array(34).fill(0);
    for (const id of ids) c[kindOf(id)]++;
    return c;
  }
  // dora indicator -> dora kind
  function doraOf(k, sanma) {
    if (k < 27) {
      if (sanma && k === 0) return 8;           // 三麻: 1m indicator -> 9m
      if (sanma && k === 8) return 0;
      return k - (k % 9) + ((k % 9) + 1) % 9;
    }
    if (k <= 30) return 27 + ((k - 27 + 1) % 4);
    return 31 + ((k - 31 + 1) % 3);
  }

  // ================= RNG =================
  function rng(seed) {
    let a = seed >>> 0 || 1;
    return () => {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // ================= shanten =================
  // standard-form shanten; melds = number of calls already fixed. -1 = complete hand
  function shantenStandard(c, melds) {
    let best = 8;
    const need = 4 - melds;
    const cc = c.slice();
    function dfs(i, m, t, pair) {
      while (i < 34 && !cc[i]) i++;
      if (i >= 34) {
        const tt = Math.min(t, need - m);
        const s = 2 * (need - m) - tt - pair;
        if (s < best) best = s;
        return;
      }
      if (cc[i] >= 3 && m < need) { cc[i] -= 3; dfs(i, m + 1, t, pair); cc[i] += 3; }
      if (i < 27 && i % 9 <= 6 && cc[i + 1] && cc[i + 2] && m < need) {
        cc[i]--; cc[i + 1]--; cc[i + 2]--; dfs(i, m + 1, t, pair); cc[i]++; cc[i + 1]++; cc[i + 2]++;
      }
      if (cc[i] >= 2 && !pair) { cc[i] -= 2; dfs(i, m, t, 1); cc[i] += 2; }
      if (m + t < need) {
        if (cc[i] >= 2) { cc[i] -= 2; dfs(i, m, t + 1, pair); cc[i] += 2; }
        if (i < 27 && i % 9 <= 7 && cc[i + 1]) { cc[i]--; cc[i + 1]--; dfs(i, m, t + 1, pair); cc[i]++; cc[i + 1]++; }
        if (i < 27 && i % 9 <= 6 && cc[i + 2]) { cc[i]--; cc[i + 2]--; dfs(i, m, t + 1, pair); cc[i]++; cc[i + 2]++; }
      }
      const save = cc[i]; cc[i] = 0; dfs(i + 1, m, t, pair); cc[i] = save;
    }
    dfs(0, 0, 0, 0);
    return best;
  }
  function shantenChiitoi(c) {
    let pairs = 0, kinds = 0;
    for (let i = 0; i < 34; i++) if (c[i]) { kinds++; if (c[i] >= 2) pairs++; }
    return 6 - pairs + Math.max(0, 7 - kinds);
  }
  function shantenKokushi(c) {
    let kinds = 0, pair = 0;
    for (let i = 0; i < 34; i++) if (isYao(i) && c[i]) { kinds++; if (c[i] >= 2) pair = 1; }
    return 13 - kinds - pair;
  }
  function shanten(c, melds) {
    melds = melds || 0;
    let s = shantenStandard(c, melds);
    if (melds === 0) s = Math.min(s, shantenChiitoi(c), shantenKokushi(c));
    return s;
  }

  // ================= hand decomposition =================
  // c: counts of the closed part INCLUDING the winning tile (sum = 14 - 3*melds)
  // returns list of { pair, sets: [{type:'seq'|'tri', k}] }
  function decompose(c) {
    const out = [];
    const cc = c.slice();
    for (let p = 0; p < 34; p++) {
      if (cc[p] < 2) continue;
      cc[p] -= 2;
      const sets = [];
      (function rec(i) {
        while (i < 34 && !cc[i]) i++;
        if (i >= 34) { out.push({ pair: p, sets: sets.slice() }); return; }
        if (cc[i] >= 3) { cc[i] -= 3; sets.push({ type: 'tri', k: i }); rec(i); sets.pop(); cc[i] += 3; }
        if (i < 27 && i % 9 <= 6 && cc[i + 1] && cc[i + 2]) {
          cc[i]--; cc[i + 1]--; cc[i + 2]--; sets.push({ type: 'seq', k: i }); rec(i); sets.pop(); cc[i]++; cc[i + 1]++; cc[i + 2]++;
        }
      })(0);
      cc[p] += 2;
    }
    return out;
  }
  const isChiitoi = c => c.every(x => x === 0 || x === 2) && c.filter(x => x === 2).length === 7;
  const isKokushi = c => {
    let pair = false;
    for (let i = 0; i < 34; i++) {
      if (isYao(i)) { if (!c[i]) return false; if (c[i] === 2) pair = true; }
      else if (c[i]) return false;
    }
    return pair;
  };
  function isComplete(c, melds) {
    if (!melds && (isChiitoi(c) || isKokushi(c))) return true;
    return decompose(c).length > 0;
  }
  // kinds that complete a 13-(3n) tile closed hand
  function waitsOf(c, melds) {
    const w = [];
    for (let k = 0; k < 34; k++) {
      if (c[k] >= 4) continue;
      c[k]++;
      if (isComplete(c, melds)) w.push(k);
      c[k]--;
    }
    return w;
  }

  // ================= scoring =================
  const YAKU = {
    riichi: ['立直', 1], dblriichi: ['两立直', 2], ippatsu: ['一发', 1], tsumo: ['门前清自摸和', 1],
    tanyao: ['断幺九', 1], pinfu: ['平和', 1], iipeikou: ['一杯口', 1], haitei: ['海底捞月', 1], houtei: ['河底捞鱼', 1],
    rinshan: ['岭上开花', 1], chankan: ['抢杠', 1],
    yakuhai_haku: ['役牌 白', 1], yakuhai_hatsu: ['役牌 发', 1], yakuhai_chun: ['役牌 中', 1],
    bakaze: ['场风', 1], jikaze: ['自风', 1],
    chiitoi: ['七对子', 2], sanshoku: ['三色同顺', 2], ittsu: ['一气通贯', 2], chanta: ['混全带幺九', 2],
    toitoi: ['对对和', 2], sanankou: ['三暗刻', 2], sankantsu: ['三杠子', 2], sanshokudoukou: ['三色同刻', 2],
    shousangen: ['小三元', 2], honroutou: ['混老头', 2],
    honitsu: ['混一色', 3], junchan: ['纯全带幺九', 3], ryanpeikou: ['二杯口', 3],
    chinitsu: ['清一色', 6],
    // yakuman: han = 13 * multiplier
    kokushi: ['国士无双', 13], kokushi13: ['国士无双十三面', 26], suuankou: ['四暗刻', 13], suuankoutanki: ['四暗刻单骑', 26],
    daisangen: ['大三元', 13], shousuushii: ['小四喜', 13], daisuushii: ['大四喜', 26], tsuuiisou: ['字一色', 13],
    ryuuiisou: ['绿一色', 13], chinroutou: ['清老头', 13], chuuren: ['九莲宝灯', 13], chuuren9: ['纯正九莲宝灯', 26],
    suukantsu: ['四杠子', 13], tenhou: ['天和', 13], chiihou: ['地和', 13],
    dora: ['宝牌', 1], aka: ['赤宝牌', 1], ura: ['里宝牌', 1], kita: ['拔北宝牌', 1]
  };
  const GREEN = new Set([19, 20, 21, 23, 25, 32]); // 2s3s4s6s8s 发

  function basePoints(han, fu, yakuman) {
    if (yakuman) return 8000 * yakuman;
    if (han >= 13) return 8000;
    if (han >= 11) return 6000;
    if (han >= 8) return 4000;
    if (han >= 6) return 3000;
    if (han >= 5) return 2000;
    const b = fu * Math.pow(2, han + 2);
    return Math.min(2000, b);
  }
  const ceil100 = x => Math.ceil(x / 100) * 100;
  function limitName(han, yakuman, base) {
    if (yakuman) return yakuman > 1 ? `${yakuman}倍役满` : '役满';
    if (han >= 13) return '累计役满';
    if (han >= 11) return '三倍满';
    if (han >= 8) return '倍满';
    if (han >= 6) return '跳满';
    if (base >= 2000) return '满贯';
    return '';
  }

  /**
   * Score a winning hand.
   * w = { closed: tileIds (incl. winning tile), melds: [{type:'chi'|'pon'|'minkan'|'ankan'|'kakan', kinds:[..]}],
   *       winTile: id, tsumo, seatWind (0-3), roundWind (0-3), riichi, dblriichi, ippatsu, haitei, houtei,
   *       rinshan, chankan, tenhou, chiihou, doraKinds: [...], uraKinds: [...], kita: n, aka: bool, sanma }
   * returns null if no yaku, else { han, fu, yaku: [[name, han]], yakuman, base, name }
   */
  function scoreHand(w) {
    const closedC = countsOf(w.closed);
    const melds = w.melds || [];
    const open = melds.some(m => m.type !== 'ankan');
    const menzen = !open;
    const winK = kindOf(w.winTile);
    const allC = closedC.slice();
    for (const m of melds) for (const k of m.kinds) allC[k]++;
    const ALL_KINDS = [];
    for (let k = 0; k < 34; k++) if (allC[k]) ALL_KINDS.push(k);
    const yakuhaiKinds = new Set([31, 32, 33, 27 + w.roundWind, 27 + w.seatWind]);

    let best = null;
    const consider = res => {
      if (!res) return;
      const pts = res.yakuman ? res.yakuman * 1e6 : basePoints(res.han, res.fu, 0) * 1000 + res.han * 10 + res.fu / 10;
      if (!best || pts > best._pts) { res._pts = pts; best = res; }
    };

    // ---- yakuman checks shared by all shapes ----
    function yakumanList(shape) {
      const ym = [];
      if (w.tenhou) ym.push('tenhou');
      if (w.chiihou) ym.push('chiihou');
      if (ALL_KINDS.every(isHonor)) ym.push('tsuuiisou');
      if (ALL_KINDS.every(k => isTerm(k))) ym.push('chinroutou');
      if (ALL_KINDS.every(k => GREEN.has(k))) ym.push('ryuuiisou');
      if (shape) {
        const tris = shape.allSets.filter(s => s.type !== 'seq').map(s => s.k);
        const dragons = [31, 32, 33].filter(k => tris.includes(k)).length;
        if (dragons === 3) ym.push('daisangen');
        const winds = [27, 28, 29, 30].filter(k => tris.includes(k)).length;
        if (winds === 4) ym.push('daisuushii');
        else if (winds === 3 && shape.pair >= 27 && shape.pair <= 30) ym.push('shousuushii');
        const kans = melds.filter(m => m.type.includes('kan')).length;
        if (kans === 4) ym.push('suukantsu');
        if (shape.closedTris === 4) ym.push(shape.pair === winK && shape.tankiPossible ? 'suuankoutanki' : 'suuankou');
      }
      if (menzen && !melds.length) {
        // 九莲宝灯: 1112345678999 + any in one suit
        const s = suitOf(winK);
        if (s < 3 && ALL_KINDS.every(k => suitOf(k) === s)) {
          const base = s * 9, need = [3, 1, 1, 1, 1, 1, 1, 1, 3];
          if (need.every((n, i) => closedC[base + i] >= n)) {
            const pre = closedC.slice(); pre[winK]--;
            ym.push(need.every((n, i) => pre[base + i] === n) ? 'chuuren9' : 'chuuren');
          }
        }
      }
      return ym;
    }
    function yakumanResult(ym) {
      if (!ym.length) return null;
      const mult = ym.reduce((s, y) => s + YAKU[y][1] / 13, 0);
      return { han: 13 * mult, fu: 0, yakuman: mult, yaku: ym.map(y => [YAKU[y][0], YAKU[y][1] >= 26 ? '双倍役满' : '役满']) };
    }
    function doraCount() {
      let d = 0, u = 0, a = 0;
      const all = w.closed.slice();
      for (const m of melds) for (const id of m.ids || []) all.push(id);
      for (const id of all) {
        const k = kindOf(id);
        for (const dk of w.doraKinds || []) if (dk === k) d++;
        if (w.riichi || w.dblriichi) for (const uk of w.uraKinds || []) if (uk === k) u++;
        if (w.aka && RED.has(id)) a++;
      }
      // 拔北: each North set aside counts as dora, plus normal dora on North
      let kita = w.kita || 0;
      if (kita) for (const dk of w.doraKinds || []) if (dk === 30) kita += w.kita;
      return { d, u, a, kita };
    }
    function situational(yaku) {
      if (w.dblriichi) yaku.push('dblriichi');
      else if (w.riichi) yaku.push('riichi');
      if (w.ippatsu && (w.riichi || w.dblriichi)) yaku.push('ippatsu');
      if (w.tsumo && menzen) yaku.push('tsumo');
      if (w.haitei && w.tsumo && !w.rinshan) yaku.push('haitei');
      if (w.houtei && !w.tsumo) yaku.push('houtei');
      if (w.rinshan) yaku.push('rinshan');
      if (w.chankan) yaku.push('chankan');
    }
    function finish(yaku, fu) {
      if (!yaku.length) return null;
      let han = 0;
      const list = yaku.map(y => {
        let h = YAKU[y][1];
        // kuisagari: open hands lose one han on these
        if (open && ['sanshoku', 'ittsu', 'chanta', 'honitsu', 'junchan', 'chinitsu'].includes(y)) h--;
        han += h;
        return [YAKU[y][0], h];
      });
      const dc = doraCount();
      if (dc.d) { han += dc.d; list.push([YAKU.dora[0], dc.d]); }
      if (dc.a) { han += dc.a; list.push([YAKU.aka[0], dc.a]); }
      if (dc.u) { han += dc.u; list.push([YAKU.ura[0], dc.u]); }
      if (dc.kita) { han += dc.kita; list.push([YAKU.kita[0], dc.kita]); }
      return { han, fu, yakuman: 0, yaku: list };
    }

    // ---- 国士 ----
    if (menzen && !melds.length && isKokushi(closedC)) {
      const pre = closedC.slice(); pre[winK]--;
      const thirteen = [...Array(34).keys()].filter(isYao).every(k => pre[k] === 1);
      const ym = yakumanList(null);
      ym.unshift(thirteen ? 'kokushi13' : 'kokushi');
      return finalize(yakumanResult(ym));
    }

    // ---- 七对子 ----
    if (menzen && !melds.length && isChiitoi(closedC)) {
      const ym = yakumanList(null);
      if (ym.length) consider(yakumanResult(ym));
      else {
        const yaku = ['chiitoi'];
        situational(yaku);
        if (ALL_KINDS.every(k => !isYao(k))) yaku.push('tanyao');
        if (ALL_KINDS.every(isYao)) yaku.push('honroutou');
        flushYaku(yaku);
        consider(finish(yaku, 25));
      }
    }

    function flushYaku(yaku) {
      const suits = new Set(ALL_KINDS.filter(k => k < 27).map(suitOf));
      const hasHonor = ALL_KINDS.some(isHonor);
      if (suits.size === 1 && !hasHonor) yaku.push('chinitsu');
      else if (suits.size === 1 && hasHonor) yaku.push('honitsu');
    }

    // ---- standard shapes ----
    for (const dec of decompose(closedC)) {
      // the winning tile can complete different groups in the same decomposition: try each
      const groups = dec.sets.map(s => ({ ...s, open: false }));
      const placements = [];
      if (dec.pair === winK) placements.push({ where: 'pair' });
      groups.forEach((s, i) => {
        if (s.type === 'tri' && s.k === winK) placements.push({ where: i, wait: 'shanpon' });
        if (s.type === 'seq' && winK >= s.k && winK <= s.k + 2) {
          const pos = winK - s.k, n = numOf(s.k);
          const wait = pos === 1 ? 'kanchan' : (pos === 0 && n === 7) || (pos === 2 && n === 1) ? 'penchan' : 'ryanmen';
          placements.push({ where: i, wait });
        }
      });
      for (const pl of placements) {
        const allSets = groups.map((s, i) => ({ type: s.type, k: s.k, open: false, ron: !w.tsumo && pl.where === i }));
        for (const m of melds) {
          if (m.type === 'chi') allSets.push({ type: 'seq', k: Math.min(...m.kinds), open: true });
          else allSets.push({ type: m.type === 'pon' ? 'tri' : 'kan', k: m.kinds[0], open: m.type !== 'ankan', meld: m.type });
        }
        // closed triplets (a triplet completed by ron counts as open)
        const closedTris = allSets.filter(s => (s.type === 'tri' || s.type === 'kan') && !s.open && !s.ron).length;
        const shape = { pair: dec.pair, allSets, closedTris, tankiPossible: pl.where === 'pair' };
        const ym = yakumanList(shape);
        if (ym.length) { consider(yakumanResult(ym)); continue; }

        const yaku = [];
        situational(yaku);
        const seqs = allSets.filter(s => s.type === 'seq');
        const tris = allSets.filter(s => s.type !== 'seq');
        const wait = pl.where === 'pair' ? 'tanki' : pl.wait;
        const pairYakuhai = dec.pair >= 31 || dec.pair === 27 + w.roundWind || dec.pair === 27 + w.seatWind;
        const isPinfu = menzen && seqs.length === 4 && wait === 'ryanmen' && !pairYakuhai;
        if (isPinfu) yaku.push('pinfu');
        if (ALL_KINDS.every(k => !isYao(k)) && (w.kuitan !== false || menzen)) yaku.push('tanyao');
        for (const t of tris) {
          if (t.k === 31) yaku.push('yakuhai_haku');
          if (t.k === 32) yaku.push('yakuhai_hatsu');
          if (t.k === 33) yaku.push('yakuhai_chun');
          if (t.k === 27 + w.roundWind) yaku.push('bakaze');
          if (t.k === 27 + w.seatWind) yaku.push('jikaze');
        }
        if (menzen) {
          const cnt = {};
          for (const s of seqs) cnt[s.k] = (cnt[s.k] || 0) + 1;
          const dup = Object.values(cnt).reduce((a, v) => a + Math.floor(v / 2), 0);
          if (dup >= 2) yaku.push('ryanpeikou');
          else if (dup === 1) yaku.push('iipeikou');
        }
        for (let n = 0; n < 7; n++) if ([0, 1, 2].every(s => seqs.some(q => q.k === s * 9 + n))) { yaku.push('sanshoku'); break; }
        for (let s = 0; s < 3; s++) if ([0, 3, 6].every(n => seqs.some(q => q.k === s * 9 + n))) { yaku.push('ittsu'); break; }
        for (let n = 0; n < 9; n++) if ([0, 1, 2].every(s => tris.some(q => q.k === s * 9 + n))) { yaku.push('sanshokudoukou'); break; }
        if (tris.length === 4) yaku.push('toitoi');
        if (closedTris === 3) yaku.push('sanankou');
        if (tris.filter(t => t.type === 'kan').length === 3) yaku.push('sankantsu');
        const dragonTris = tris.filter(t => t.k >= 31).length;
        if (dragonTris === 2 && dec.pair >= 31) yaku.push('shousangen');
        const setHasYao = s => (s.type === 'seq' ? isTerm(s.k) || isTerm(s.k + 2) : isYao(s.k));
        const allYao = ALL_KINDS.every(isYao);
        if (allYao) yaku.push('honroutou');
        else if (allSets.every(setHasYao) && isYao(dec.pair) && seqs.length) {
          if (ALL_KINDS.some(isHonor)) yaku.push('chanta'); else yaku.push('junchan');
        }
        flushYaku(yaku);
        if (!yaku.length) continue;

        // ---- fu ----
        let fu;
        if (isPinfu && w.tsumo) fu = 20;
        else {
          fu = 20;
          if (menzen && !w.tsumo) fu += 10;
          if (w.tsumo && !isPinfu) fu += 2;
          for (const t of tris) {
            let f = 2;
            if (isYao(t.k)) f *= 2;
            if (!t.open && !t.ron) f *= 2;
            if (t.type === 'kan') f *= 4;
            fu += f;
          }
          if (dec.pair >= 31) fu += 2;
          if (dec.pair === 27 + w.roundWind) fu += 2;
          if (dec.pair === 27 + w.seatWind) fu += 2;
          if (wait === 'kanchan' || wait === 'penchan' || wait === 'tanki') fu += 2;
          if (fu === 20) fu = 30; // open pinfu shape
          fu = Math.ceil(fu / 10) * 10;
        }
        consider(finish(yaku, fu));
      }
    }
    return finalize(best);

    function finalize(res) {
      if (!res) return null;
      delete res._pts;
      res.base = basePoints(res.han, res.fu, res.yakuman);
      res.name = limitName(res.han, res.yakuman, res.base);
      return res;
    }
  }
  // payments for a win. honba: counters. returns { total, fromDiscarder } or { fromDealer, fromOthers }
  function payments(base, dealer, tsumo, honba, sanma) {
    if (!tsumo) {
      const total = ceil100(base * (dealer ? 6 : 4));
      return { ron: total, total: total + honba * 300 };
    }
    if (dealer) {
      const each = ceil100(base * 2);
      const n = sanma ? 2 : 3;
      return { all: each, honbaEach: 100, total: (each + 100 * honba) * n };
    }
    const d = ceil100(base * 2), o = ceil100(base);
    return { dealerPays: d, otherPays: o, honbaEach: 100, total: d + o * (sanma ? 1 : 2) + honba * 100 * (sanma ? 2 : 3) };
  }

  // ================= game =================
  /**
   * new Game({ players: 4|3, seed, akadora: true, kuitan: true, length: 'east'|'south', startPoints })
   * Drive with pending() / act(seat, action) until finished.
   */
  function Game(opts) {
    opts = Object.assign({ players: 4, seed: (Math.random() * 2 ** 31) | 0, akadora: true, kuitan: true, length: 'south' }, opts || {});
    const n = opts.players === 3 ? 3 : 4;
    opts.players = n;
    if (!opts.startPoints) opts.startPoints = n === 3 ? 35000 : 25000;
    this.opts = opts;
    this.n = n;
    this.sanma = n === 3;
    this.rand = rng(opts.seed);
    this.scores = new Array(n).fill(opts.startPoints);
    this.round = 0;       // 0 = 东, 1 = 南
    this.kyoku = 0;       // dealer seat index within the round
    this.honba = 0;
    this.sticks = 0;      // riichi sticks on the table
    this.finished = false;
    this.log = [];        // full record
    this.log.push({ t: 'start', opts: { ...opts }, scores: this.scores.slice() });
    this.startHand();
  }
  const G = Game.prototype;

  G.startHand = function () {
    const n = this.n;
    let tiles = [];
    for (let id = 0; id < 136; id++) {
      const k = kindOf(id);
      if (this.sanma && k >= 1 && k <= 7) continue;           // 三麻: no 2m-8m
      tiles.push(id);
    }
    if (!this.opts.akadora) tiles = tiles.slice();
    for (let i = tiles.length - 1; i > 0; i--) { const j = Math.floor(this.rand() * (i + 1)); [tiles[i], tiles[j]] = [tiles[j], tiles[i]]; }
    this.dead = tiles.splice(tiles.length - 14, 14);            // dead wall: [0..3] rinshan, doras from index 4
    this.wall = tiles;
    this.doraIdx = [4];                                         // indicator positions in dead wall
    this.rinshanUsed = 0;
    this.hands = [];
    this.melds = [];
    this.rivers = [];
    this.kita = [];
    this.riichi = [];
    this.ippatsu = [];
    this.furitenTemp = [];
    this.furitenRiichi = [];
    this.firstTurn = [];
    for (let s = 0; s < n; s++) {
      this.hands.push(this.wall.splice(0, 13));
      this.melds.push([]); this.rivers.push([]); this.kita.push(0);
      this.riichi.push(0); this.ippatsu.push(false); this.furitenTemp.push(false); this.furitenRiichi.push(false);
      this.firstTurn.push(true);
    }
    this.dealer = this.kyoku;
    this.turn = this.dealer;
    this.kanCount = 0;
    this.kanBy = [];
    this.lastDiscard = null;
    this.phase = 'draw';
    this.handResult = null;
    this.anyCall = false;
    this.windsDiscarded = [];
    this.log.push({
      t: 'deal', round: this.round, kyoku: this.kyoku, honba: this.honba, sticks: this.sticks, dealer: this.dealer,
      hands: this.hands.map(h => h.slice()), dora: this.doraIndicators(), scores: this.scores.slice(),
      wallLen: this.wall.length
    });
    this.draw();
  };
  G.seatWind = function (s) { return (s - this.dealer + this.n) % this.n; };
  G.doraIndicators = function () { return this.doraIdx.map(i => this.dead[i]); };
  G.uraIndicators = function () { return this.doraIdx.map(i => this.dead[i + 1]); };
  G.doraKinds = function () { return this.doraIndicators().map(id => doraOf(kindOf(id), this.sanma)); };
  G.uraKinds = function () { return this.uraIndicators().map(id => doraOf(kindOf(id), this.sanma)); };
  G.wallLeft = function () { return this.wall.length; };

  G.draw = function (rinshan) {
    const s = this.turn;
    let id;
    if (rinshan) {
      // rinshan tiles are dead[0..3]; the taken slot is refilled from the end of the live wall so the
      // dead wall stays at 14 tiles and dora indicator positions never move
      id = this.dead[this.rinshanUsed];
      this.dead[this.rinshanUsed] = this.wall.pop();
      this.rinshanUsed++;
    } else {
      if (!this.wall.length) return this.exhaustive();
      id = this.wall.shift();
    }
    this.hands[s].push(id);
    this.drawn = id;
    this.rinshan = !!rinshan;
    this.phase = 'turn';
    this.log.push({ t: 'draw', seat: s, tile: id, rinshan: !!rinshan });
  };

  // ---------- legal action enumeration ----------
  G.pending = function () {
    if (this.finished) return [];
    if (this.phase === 'turn') return [{ seat: this.turn, actions: this.turnActions(this.turn) }];
    if (this.phase === 'call') return this.callOptions.filter(o => !o.decided).map(o => ({ seat: o.seat, actions: o.actions }));
    if (this.phase === 'result') return [{ seat: -1, actions: [{ type: 'next' }] }];
    return [];
  };
  G.closedMeldsCount = function (s) { return this.melds[s].length; };
  G.turnActions = function (s) {
    const hand = this.hands[s];
    const acts = [];
    const c = countsOf(hand);
    const melds = this.melds[s].length;
    // tsumo
    const res = this.evalWin(s, this.drawn, true);
    if (res) acts.push({ type: 'tsumo' });
    // kyuushu kyuuhai
    if (this.firstTurn[s] && !this.anyCall) {
      const yao = new Set(hand.map(kindOf).filter(isYao)).size;
      if (yao >= 9) acts.push({ type: 'kyuushu' });
    }
    const inRiichi = !!this.riichi[s];
    // kans (only if tiles remain)
    if (this.wall.length > 0 && this.kanCount < 4) {
      for (let k = 0; k < 34; k++) {
        if (c[k] !== 4) continue;
        if (inRiichi) {
          // riichi ankan only with the drawn tile and without changing waits
          if (kindOf(this.drawn) !== k) continue;
          const before = countsOf(hand.filter(id => id !== this.drawn));
          const w1 = waitsOf(before, melds).join();
          const after = c.slice(); after[k] = 0;
          const w2 = waitsOf(after, melds + 1).join();
          if (w1 !== w2 || !w1) continue;
        }
        acts.push({ type: 'ankan', kind: k });
      }
      if (!inRiichi) for (const m of this.melds[s]) {
        if (m.type !== 'pon') continue;
        const id = hand.find(x => kindOf(x) === m.kinds[0]);
        if (id != null) acts.push({ type: 'kakan', tile: id });
      }
    }
    if (this.sanma && this.wall.length > 0) {
      const north = hand.find(x => kindOf(x) === 30);
      if (north != null && (!inRiichi || north === this.drawn)) acts.push({ type: 'kita', tile: north });
    }
    // discards
    if (inRiichi) {
      acts.push({ type: 'discard', tile: this.drawn });
      return acts;
    }
    const banned = this.kuikaeBan || [];
    for (const id of hand) if (!banned.includes(kindOf(id))) acts.push({ type: 'discard', tile: id });
    // riichi
    if (!this.melds[s].some(m => m.type !== 'ankan') && this.scores[s] >= 1000 && this.wall.length >= this.n) {
      for (const id of hand) {
        const cc = c.slice(); cc[kindOf(id)]--;
        if (shantenStandard(cc, melds) === 0 || (melds === 0 && (shantenChiitoi(cc) === 0 || shantenKokushi(cc) === 0))) {
          if (!acts.some(a => a.type === 'riichi' && kindOf(a.tile) === kindOf(id) && !RED.has(a.tile) === !RED.has(id))) acts.push({ type: 'riichi', tile: id });
        }
      }
    }
    return acts;
  };

  // can seat s win with tile id? returns score or null. Considers furiten for ron.
  G.evalWin = function (s, id, tsumo, extra) {
    extra = extra || {};
    const closed = tsumo ? this.hands[s].slice() : this.hands[s].concat([id]);
    const c = countsOf(closed);
    const melds = this.melds[s];
    if (!isComplete(c, melds.length)) return null;
    if (!tsumo && this.isFuriten(s)) return null;
    const first = this.firstTurn[s] && !this.anyCall;
    const res = scoreHand({
      closed, melds, winTile: id, tsumo,
      seatWind: this.seatWind(s), roundWind: this.round,
      riichi: this.riichi[s] === 1, dblriichi: this.riichi[s] === 2, ippatsu: this.ippatsu[s],
      haitei: tsumo && this.wall.length === 0 && !this.rinshan, houtei: !tsumo && this.wall.length === 0,
      rinshan: tsumo && this.rinshan, chankan: !!extra.chankan,
      tenhou: tsumo && first && s === this.dealer, chiihou: tsumo && first && s !== this.dealer,
      doraKinds: this.doraKinds(), uraKinds: this.uraKinds(), kita: this.kita[s], aka: this.opts.akadora,
      kuitan: this.opts.kuitan, sanma: this.sanma
    });
    return res;
  };
  G.isFuriten = function (s) {
    if (this.furitenTemp[s] || this.furitenRiichi[s]) return true;
    const c = countsOf(this.hands[s]);
    const waits = waitsOf(c, this.melds[s].length);
    return this.rivers[s].some(d => waits.includes(kindOf(d.tile)));
  };
  G.waits = function (s) { return waitsOf(countsOf(this.hands[s]), this.melds[s].length); };

  // ---------- applying actions ----------
  G.act = function (seat, a) {
    if (this.finished) throw new Error('game finished');
    if (this.phase === 'result') { if (a.type === 'next') return this.nextHand(); throw new Error('expected next'); }
    if (this.phase === 'turn') {
      if (seat !== this.turn) throw new Error('not your turn');
      const legal = this.turnActions(seat);
      if (!legal.some(l => l.type === a.type && (l.tile === undefined || l.tile === a.tile) && (l.kind === undefined || l.kind === a.kind))) throw new Error('illegal action ' + JSON.stringify(a));
      return this.doTurn(seat, a);
    }
    if (this.phase === 'call') return this.doCall(seat, a);
    throw new Error('bad phase');
  };

  G.doTurn = function (s, a) {
    const hand = this.hands[s];
    this.kuikaeBan = null;
    if (a.type === 'tsumo') return this.win([s], s, this.drawn, true);
    if (a.type === 'kyuushu') return this.abort('九种九牌');
    if (a.type === 'ankan' || a.type === 'kakan' || a.type === 'kita') {
      this.breakIppatsu();
      if (a.type === 'kita') {
        hand.splice(hand.indexOf(a.tile), 1);
        this.kita[s]++;
        this.log.push({ t: 'kita', seat: s, tile: a.tile });
        this.firstTurn[s] = false;
        return this.draw(true);
      }
      if (a.type === 'ankan') {
        const ids = hand.filter(x => kindOf(x) === a.kind);
        for (const id of ids) hand.splice(hand.indexOf(id), 1);
        this.melds[s].push({ type: 'ankan', kinds: [a.kind, a.kind, a.kind, a.kind], ids, from: s });
        this.log.push({ t: 'ankan', seat: s, tiles: ids });
        return this.afterKan(s);
      }
      // kakan: others may rob it (chankan)
      const m = this.melds[s].find(x => x.type === 'pon' && x.kinds[0] === kindOf(a.tile));
      hand.splice(hand.indexOf(a.tile), 1);
      m.type = 'kakan'; m.kinds.push(m.kinds[0]); m.ids.push(a.tile);
      this.log.push({ t: 'kakan', seat: s, tile: a.tile });
      const robbers = [];
      for (let o = 0; o < this.n; o++) {
        if (o === s) continue;
        if (this.evalWin(o, a.tile, false, { chankan: true })) robbers.push({ seat: o, actions: [{ type: 'ron' }, { type: 'pass' }] });
      }
      if (robbers.length) {
        this.phase = 'call';
        this.callOptions = robbers.map(r => ({ ...r, decided: false }));
        this.callCtx = { tile: a.tile, from: s, chankan: true };
        return;
      }
      return this.afterKan(s);
    }
    // discard / riichi
    const riichi = a.type === 'riichi';
    const idx = hand.indexOf(a.tile);
    hand.splice(idx, 1);
    const tsumogiri = a.tile === this.drawn;
    if (this.ippatsu[s] && !riichi) this.ippatsu[s] = false;
    if (riichi) {
      this.riichi[s] = this.firstTurn[s] && !this.anyCall ? 2 : 1;
      this.pendingRiichi = s;
    }
    if (!this.riichi[s]) this.furitenTemp[s] = false;
    this.rivers[s].push({ tile: a.tile, tsumogiri, riichi, called: false });
    this.log.push({ t: 'discard', seat: s, tile: a.tile, tsumogiri, riichi });
    if (this.firstTurn[s]) {
      const k = kindOf(a.tile);
      this.windsDiscarded.push(k);
    }
    this.firstTurn[s] = false;
    this.lastDiscard = { seat: s, tile: a.tile };
    this.drawn = null;
    return this.offerCalls(s, a.tile);
  };
  G.afterKan = function (s) {
    this.kanCount++;
    this.kanBy.push(s);
    this.anyCall = true;
    this.firstTurn = this.firstTurn.map(() => false);
    // reveal a new dora indicator immediately (simplification applied to all kan types)
    this.doraIdx.push(4 + this.doraIdx.length * 2);
    this.log.push({ t: 'dora', tile: this.dead[this.doraIdx[this.doraIdx.length - 1]] });
    if (this.kanCount === 4 && new Set(this.kanBy).size > 1) {
      // 四杠散了 is resolved after the discard; flag it
      this.fourKanAbort = true;
    }
    this.turn = s;
    return this.draw(true);
  };
  G.breakIppatsu = function () { this.ippatsu = this.ippatsu.map(() => false); };

  G.offerCalls = function (from, tile) {
    const k = kindOf(tile);
    const opts = [];
    for (let o = 0; o < this.n; o++) {
      if (o === from) continue;
      const acts = [];
      const res = this.evalWin(o, tile, false);
      if (res) acts.push({ type: 'ron' });
      else if (!this.isFuriten(o) && isComplete(countsOf(this.hands[o].concat([tile])), this.melds[o].length)) {
        // complete but no yaku: missed win still makes you temporarily furiten
      }
      if (this.wall.length > 0 && !this.riichi[o]) {
        const same = this.hands[o].filter(x => kindOf(x) === k);
        if (same.length >= 2) acts.push({ type: 'pon', tiles: pickPair(same) });
        if (same.length >= 3 && this.kanCount < 4) acts.push({ type: 'daiminkan', tiles: same.slice(0, 3) });
        if (!this.sanma && o === (from + 1) % this.n && k < 27) {
          for (const combo of chiCombos(this.hands[o], k)) acts.push({ type: 'chi', tiles: combo });
        }
      }
      if (acts.length) { acts.push({ type: 'pass' }); opts.push({ seat: o, actions: acts, decided: false }); }
    }
    // any complete-with-this-tile hand that passes becomes temp furiten (handled in doCall)
    if (!opts.length) return this.nextTurn(from);
    this.phase = 'call';
    this.callOptions = opts;
    this.callCtx = { tile, from };
  };
  function pickPair(same) {
    // prefer keeping a red five in hand
    const sorted = same.slice().sort((a, b) => (RED.has(a) ? 1 : 0) - (RED.has(b) ? 1 : 0));
    return sorted.slice(0, 2);
  }
  function chiCombos(hand, k) {
    const res = [];
    const n = k % 9;
    const pick = kind => {
      const ids = hand.filter(x => kindOf(x) === kind);
      return ids.find(x => !RED.has(x)) ?? ids[0];
    };
    for (const [a, b] of [[-2, -1], [-1, 1], [1, 2]]) {
      if (n + a < 0 || n + b > 8) continue;
      const x = pick(k + a), y = pick(k + b);
      if (x != null && y != null) res.push([x, y]);
    }
    return res;
  }

  G.doCall = function (seat, a) {
    const opt = this.callOptions.find(o => o.seat === seat && !o.decided);
    if (!opt) throw new Error('no call pending for seat ' + seat);
    const ok = opt.actions.some(l => l.type === a.type && (!l.tiles || !a.tiles || l.tiles.join() === a.tiles.join()));
    if (!ok) throw new Error('illegal call ' + JSON.stringify(a));
    opt.decided = true;
    opt.choice = a;
    if (a.type === 'pass' && opt.actions.some(l => l.type === 'ron')) {
      // passing a ron: temporary furiten (permanent if in riichi)
      if (this.riichi[seat]) this.furitenRiichi[seat] = true; else this.furitenTemp[seat] = true;
    }
    if (this.callOptions.some(o => !o.decided)) {
      // a ron already chosen can't be outranked; wait only for other ron decisions
      return;
    }
    return this.resolveCalls();
  };
  G.resolveCalls = function () {
    const { tile, from, chankan } = this.callCtx;
    const choices = this.callOptions.map(o => ({ seat: o.seat, a: o.choice }));
    const rons = choices.filter(c => c.a.type === 'ron').map(c => c.seat)
      .sort((x, y) => ((x - from + this.n) % this.n) - ((y - from + this.n) % this.n));
    this.callOptions = null;
    if (rons.length) {
      if (rons.length === 3 && this.n === 4) return this.abort('三家和了');
      return this.win(rons, from, tile, false, { chankan });
    }
    if (chankan) return this.afterKan(from);
    // riichi stick is only committed once the discard passes
    this.commitRiichi();
    if (this.fourKanAbort) return this.abort('四杠散了');
    const kan = choices.find(c => c.a.type === 'daiminkan');
    const pon = choices.find(c => c.a.type === 'pon');
    const chi = choices.find(c => c.a.type === 'chi');
    const call = kan || pon || chi;
    if (!call) return this.nextTurn(from);
    const s = call.seat, hand = this.hands[s];
    for (const id of call.a.tiles) hand.splice(hand.indexOf(id), 1);
    const ids = call.a.tiles.concat([tile]);
    const kinds = ids.map(kindOf).sort((x, y) => x - y);
    const type = call.a.type === 'daiminkan' ? 'minkan' : call.a.type;
    this.melds[s].push({ type, kinds, ids, from, called: tile });
    this.rivers[from][this.rivers[from].length - 1].called = true;
    this.anyCall = true;
    this.breakIppatsu();
    this.firstTurn = this.firstTurn.map(() => false);
    this.log.push({ t: type, seat: s, from, tile, tiles: call.a.tiles });
    this.turn = s;
    if (type === 'minkan') return this.afterKan(s);
    // kuikae: can't discard the called kind (or the other end of a chi) this turn
    const ban = [kindOf(tile)];
    if (type === 'chi') {
      const lo = kinds[0], hi = kinds[2];
      if (kindOf(tile) === lo && hi % 9 < 8) ban.push(hi + 1);
      if (kindOf(tile) === hi && lo % 9 > 0) ban.push(lo - 1);
    }
    this.kuikaeBan = ban;
    this.drawn = null;
    this.rinshan = false;
    this.phase = 'turn';
    // if every discard would be banned, lift the restriction
    if (!this.hands[s].some(id => !ban.includes(kindOf(id)))) this.kuikaeBan = null;
  };
  G.commitRiichi = function () {
    if (this.pendingRiichi == null) return;
    const s = this.pendingRiichi;
    this.pendingRiichi = null;
    this.scores[s] -= 1000;
    this.sticks++;
    this.ippatsu[s] = true;
    this.log.push({ t: 'riichi', seat: s, scores: this.scores.slice() });
    if (this.n === 4 && this.riichi.every(r => r)) this.abortNext = '四家立直';
  };
  G.nextTurn = function (from) {
    this.commitRiichi();
    if (this.abortNext) { const r = this.abortNext; this.abortNext = null; return this.abort(r); }
    if (this.fourKanAbort) return this.abort('四杠散了');
    // 四风连打
    if (this.n === 4 && this.windsDiscarded.length === 4 && !this.anyCall) {
      const k = this.windsDiscarded[0];
      if (k >= 27 && k <= 30 && this.windsDiscarded.every(x => x === k)) return this.abort('四风连打');
    }
    this.turn = (from + 1) % this.n;
    this.draw(false);
  };

  // ---------- hand end ----------
  G.win = function (winners, from, tile, tsumo, extra) {
    extra = extra || {};
    const results = [];
    const delta = new Array(this.n).fill(0);
    let first = true;
    for (const s of winners) {
      const res = this.evalWin(s, tile, tsumo, extra);
      const dealer = s === this.dealer;
      const p = payments(res.base, dealer, tsumo, first ? this.honba : 0, this.sanma);
      if (tsumo) {
        for (let o = 0; o < this.n; o++) {
          if (o === s) continue;
          let pay = dealer ? p.all : o === this.dealer ? p.dealerPays : p.otherPays;
          pay += 100 * this.honba;
          delta[o] -= pay; delta[s] += pay;
        }
      } else {
        const pay = p.ron + (first ? this.honba * 300 : 0);
        delta[from] -= pay; delta[s] += pay;
      }
      if (first) { delta[s] += this.sticks * 1000; }
      results.push({
        seat: s, from, tsumo, tile, han: res.han, fu: res.fu, yakuman: res.yakuman, yaku: res.yaku, name: res.name,
        hand: this.hands[s].slice(), melds: this.melds[s].map(m => ({ ...m })),
        ura: this.riichi[s] ? this.uraIndicators() : [], points: tsumo ? p.total : p.ron
      });
      first = false;
    }
    this.sticks = 0;
    for (let i = 0; i < this.n; i++) this.scores[i] += delta[i];
    const dealerWon = winners.includes(this.dealer);
    this.handResult = { type: 'agari', wins: results, delta, scores: this.scores.slice(), dora: this.doraIndicators(), renchan: dealerWon };
    this.log.push({ t: 'agari', wins: results, delta, scores: this.scores.slice() });
    this.phase = 'result';
  };
  G.exhaustive = function () {
    const tenpai = [];
    for (let s = 0; s < this.n; s++) if (this.waits(s).length) tenpai.push(s);
    const delta = new Array(this.n).fill(0);
    const pool = this.n === 4 ? 3000 : 2000;
    if (tenpai.length && tenpai.length < this.n) {
      for (let s = 0; s < this.n; s++) {
        if (tenpai.includes(s)) delta[s] += pool / tenpai.length;
        else delta[s] -= pool / (this.n - tenpai.length);
      }
    }
    for (let i = 0; i < this.n; i++) this.scores[i] += delta[i];
    this.handResult = { type: 'ryuukyoku', reason: '荒牌流局', tenpai, delta, scores: this.scores.slice(), renchan: tenpai.includes(this.dealer), honbaUp: true };
    this.log.push({ t: 'ryuukyoku', reason: '荒牌流局', tenpai, hands: this.hands.map(h => h.slice()), delta, scores: this.scores.slice() });
    this.phase = 'result';
  };
  G.abort = function (reason) {
    this.commitRiichi();
    this.handResult = { type: 'ryuukyoku', reason, tenpai: [], delta: new Array(this.n).fill(0), scores: this.scores.slice(), renchan: true, honbaUp: true };
    this.log.push({ t: 'ryuukyoku', reason, hands: this.hands.map(h => h.slice()), delta: this.handResult.delta, scores: this.scores.slice() });
    this.phase = 'result';
  };
  G.nextHand = function () {
    const r = this.handResult;
    const busted = this.scores.some(x => x < 0);
    if (r.renchan) this.honba++;
    else if (r.type === 'agari') this.honba = 0;
    else this.honba++;
    if (!r.renchan) {
      this.kyoku++;
      if (this.kyoku >= this.n) { this.kyoku = 0; this.round++; }
    }
    const lastRound = this.opts.length === 'east' ? 0 : 1;
    const top = Math.max(...this.scores);
    const target = this.n === 4 ? 30000 : 40000;
    // all-last dealer who is on top ends the game (agari-yame); overtime ends once someone reaches target
    const pastEnd = this.round > lastRound;
    const allLastDealerTop = this.round === lastRound && this.kyoku === this.n - 1 && r.renchan &&
      this.scores[this.dealer] === top && top >= target;
    if (busted || (pastEnd && (top >= target || this.round > lastRound + 1)) || allLastDealerTop) {
      if (this.sticks) { const w = this.scores.indexOf(top); this.scores[w] += this.sticks * 1000; this.sticks = 0; }
      this.finished = true;
      this.phase = 'over';
      this.log.push({ t: 'end', scores: this.scores.slice(), ranks: this.ranks() });
      return;
    }
    this.startHand();
  };
  G.ranks = function () {
    const order = [...Array(this.n).keys()].sort((a, b) => this.scores[b] - this.scores[a] || a - b);
    const ranks = new Array(this.n);
    order.forEach((s, i) => { ranks[s] = i + 1; });
    return ranks;
  };

  // everything seat s is allowed to know (for the UI / AI)
  G.visibleState = function (s) {
    return {
      seat: s, players: this.n, sanma: this.sanma, round: this.round, kyoku: this.kyoku, honba: this.honba, sticks: this.sticks,
      dealer: this.dealer, turn: this.turn, phase: this.phase, scores: this.scores.slice(),
      hand: this.hands[s].slice(), drawn: this.turn === s ? this.drawn : null,
      handSizes: this.hands.map(h => h.length),
      melds: this.melds.map(ms => ms.map(m => ({ type: m.type, ids: m.ids.slice(), from: m.from, called: m.called }))),
      rivers: this.rivers.map(r => r.map(d => ({ ...d }))),
      riichi: this.riichi.slice(), kita: this.kita.slice(),
      dora: this.doraIndicators(), wallLeft: this.wall.length,
      seatWind: this.seatWind(s), roundWind: this.round,
      lastDiscard: this.lastDiscard, callTile: this.phase === 'call' ? this.callCtx.tile : null,
      furiten: this.isFuriten(s), result: this.phase === 'result' ? this.handResult : null,
      finished: this.finished
    };
  };
  G.record = function () { return { app: 'DesktopPet-riichi', version: 1, opts: this.opts, log: this.log.slice() }; };

  // ================= replay =================
  // Rebuilds per-step views from a record for the 牌谱 viewer. Each step: { event, view }
  function Replay(record) {
    const steps = [];
    let st = null;
    const n = record.opts.players;
    for (const ev of record.log) {
      if (ev.t === 'start') { st = { scores: ev.scores.slice(), n }; steps.push({ ev, view: null }); continue; }
      if (ev.t === 'deal') {
        st = {
          n, round: ev.round, kyoku: ev.kyoku, honba: ev.honba, sticks: ev.sticks, dealer: ev.dealer,
          hands: ev.hands.map(h => h.slice()), melds: Array.from({ length: n }, () => []), rivers: Array.from({ length: n }, () => []),
          riichi: new Array(n).fill(false), kita: new Array(n).fill(0), dora: ev.dora.slice(), scores: ev.scores.slice(),
          wallLeft: ev.wallLen != null ? ev.wallLen : ev.wall.length, turn: ev.dealer, drawn: null, result: null
        };
      } else if (ev.t === 'draw') {
        st.hands[ev.seat].push(ev.tile); st.drawn = ev.tile; st.turn = ev.seat;
        if (!ev.rinshan) st.wallLeft--; else st.wallLeft--;
      } else if (ev.t === 'discard') {
        const h = st.hands[ev.seat]; h.splice(h.indexOf(ev.tile), 1);
        st.rivers[ev.seat].push({ tile: ev.tile, tsumogiri: ev.tsumogiri, riichi: ev.riichi });
        if (ev.riichi) st.riichi[ev.seat] = true;
        st.drawn = null;
      } else if (ev.t === 'riichi') { st.scores = ev.scores.slice(); st.sticks++; }
      else if (ev.t === 'chi' || ev.t === 'pon' || ev.t === 'minkan') {
        const h = st.hands[ev.seat];
        for (const id of ev.tiles) h.splice(h.indexOf(id), 1);
        st.melds[ev.seat].push({ type: ev.t, ids: ev.tiles.concat([ev.tile]), from: ev.from, called: ev.tile });
        const r = st.rivers[ev.from]; if (r.length) r[r.length - 1].called = true;
        st.turn = ev.seat;
      } else if (ev.t === 'ankan') {
        const h = st.hands[ev.seat];
        for (const id of ev.tiles) h.splice(h.indexOf(id), 1);
        st.melds[ev.seat].push({ type: 'ankan', ids: ev.tiles.slice() });
      } else if (ev.t === 'kakan') {
        const h = st.hands[ev.seat]; h.splice(h.indexOf(ev.tile), 1);
        const m = st.melds[ev.seat].find(x => x.type === 'pon' && kindOf(x.ids[0]) === kindOf(ev.tile));
        if (m) { m.type = 'kakan'; m.ids.push(ev.tile); }
      } else if (ev.t === 'kita') {
        const h = st.hands[ev.seat]; h.splice(h.indexOf(ev.tile), 1); st.kita[ev.seat]++;
      } else if (ev.t === 'dora') st.dora.push(ev.tile);
      else if (ev.t === 'agari' || ev.t === 'ryuukyoku') { st.result = ev; st.scores = ev.scores.slice(); }
      else if (ev.t === 'end') { st = Object.assign({}, st, { end: ev }); }
      steps.push({ ev, view: st ? JSON.parse(JSON.stringify(st)) : null });
    }
    return {
      steps,
      length: steps.length,
      stepTo: i => steps[Math.max(0, Math.min(steps.length - 1, i))],
      // indexes of the 'deal' events, for jumping between hands
      hands: steps.map((s, i) => (s.ev.t === 'deal' ? i : -1)).filter(i => i >= 0)
    };
  }

  // describe an event in Chinese, for replay lists
  function describe(ev, names) {
    const who = s => (names ? names[s] : `玩家${s + 1}`);
    switch (ev.t) {
      case 'deal': return `${WIND_NAMES[ev.round]}${ev.kyoku + 1}局 ${ev.honba}本场 开始`;
      case 'draw': return `${who(ev.seat)} ${ev.rinshan ? '岭上' : ''}摸牌 ${tileName(ev.tile)}`;
      case 'discard': return `${who(ev.seat)} ${ev.riichi ? '立直！' : ''}打出 ${tileName(ev.tile)}${ev.tsumogiri ? '（摸切）' : ''}`;
      case 'chi': return `${who(ev.seat)} 吃 ${tileName(ev.tile)}`;
      case 'pon': return `${who(ev.seat)} 碰 ${tileName(ev.tile)}`;
      case 'minkan': return `${who(ev.seat)} 明杠 ${tileName(ev.tile)}`;
      case 'ankan': return `${who(ev.seat)} 暗杠 ${tileName(ev.tiles[0])}`;
      case 'kakan': return `${who(ev.seat)} 加杠 ${tileName(ev.tile)}`;
      case 'kita': return `${who(ev.seat)} 拔北`;
      case 'riichi': return `${who(ev.seat)} 立直成立`;
      case 'dora': return `新宝牌指示牌 ${tileName(ev.tile)}`;
      case 'agari': return ev.wins.map(w => `${who(w.seat)} ${w.tsumo ? '自摸' : '荣和'} ${w.name || (w.han + '番' + w.fu + '符')} ${w.points}点`).join('；');
      case 'ryuukyoku': return `流局（${ev.reason}）`;
      case 'end': return '对局结束';
      default: return ev.t;
    }
  }

  const api = {
    Game, Replay, describe, scoreHand, payments, basePoints,
    shanten, shantenStandard, shantenChiitoi, shantenKokushi, waitsOf, isComplete, decompose,
    countsOf, kindOf, isHonor, isTerm, isYao, suitOf, numOf, doraOf, tileName, tileCode, RED, KIND_NAMES, WIND_NAMES, YAKU
  };
  root.Riichi = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
