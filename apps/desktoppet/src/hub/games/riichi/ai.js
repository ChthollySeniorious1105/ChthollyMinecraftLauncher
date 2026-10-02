// 日本麻将 computer players. Browser: window.RiichiAI. Node: module.exports.
// decide(view, actions, level) -> one of `actions`. view = game.visibleState(seat).
(function (root) {
  'use strict';
  const R = root.Riichi || (typeof require === 'function' ? require('./engine.js') : null);
  const { kindOf, countsOf, isHonor, isYao, shanten, doraOf } = R;

  // tiles we can see (own hand, rivers, melds, dora indicators, kita)
  function visibleCounts(v) {
    const c = new Array(34).fill(0);
    for (const id of v.hand) c[kindOf(id)]++;
    for (const r of v.rivers) for (const d of r) c[kindOf(d.tile)]++;
    for (const ms of v.melds) for (const m of ms) for (const id of m.ids) c[kindOf(id)]++;
    for (const id of v.dora) c[kindOf(id)]++;
    return c;
  }
  function meldCount(v) { return v.melds[v.seat].length; }

  // tiles that reduce shanten, weighted by how many are still unseen
  function ukeire(c, melds, seen, sanma) {
    const base = shanten(c, melds);
    let n = 0;
    for (let k = 0; k < 34; k++) {
      if (sanma && k >= 1 && k <= 7) continue;
      const left = 4 - seen[k];
      if (left <= 0) continue;
      c[k]++;
      if (shanten(c, melds) < base) n += left;
      c[k]--;
    }
    return n;
  }

  function doraKinds(v) { return v.dora.map(id => doraOf(kindOf(id), v.sanma)); }

  // how dangerous is discarding kind k against a threatening opponent? lower = safer
  function danger(v, k, threats) {
    let worst = 0;
    for (const t of threats) {
      const river = v.rivers[t].map(d => kindOf(d.tile));
      if (river.includes(k)) continue;                          // 现物
      let d = 10;
      if (isHonor(k)) {
        const seen = visibleCounts(v)[k];
        d = seen >= 3 ? 1 : seen === 2 ? 3 : 6;
      } else {
        const n = k % 9;
        // 筋: 1-4-7 / 2-5-8 / 3-6-9 of the same suit discarded by the threat
        const suji = [];
        if (n - 3 >= 0) suji.push(k - 3);
        if (n + 3 <= 8) suji.push(k + 3);
        const onSuji = suji.length && suji.every(s => river.includes(s));
        const halfSuji = suji.some(s => river.includes(s));
        if (onSuji) d = n === 0 || n === 8 ? 2 : 4;
        else if (halfSuji) d = 6;
        else d = n === 0 || n === 8 ? 7 : n === 1 || n === 7 ? 8 : 10;
        // 壁: all four of a neighbour visible makes one side impossible
        const seen = visibleCounts(v);
        if ((n > 0 && seen[k - 1] >= 4) || (n < 8 && seen[k + 1] >= 4)) d -= 2;
      }
      worst = Math.max(worst, d);
    }
    return worst;
  }

  function threatsOf(v) {
    const t = [];
    for (let s = 0; s < v.players; s++) {
      if (s === v.seat) continue;
      if (v.riichi[s]) { t.push(s); continue; }
      // heavy open hands late in the hand
      const openMelds = v.melds[s].filter(m => m.type !== 'ankan').length;
      if (openMelds >= 3 || (openMelds >= 2 && v.wallLeft < 30)) t.push(s);
    }
    return t;
  }

  // value hints for keeping a tile
  function tileValue(v, k, c) {
    let val = 0;
    const dk = doraKinds(v);
    val += dk.filter(x => x === k).length * 1.5;
    const yakuhai = k >= 31 || k === 27 + v.roundWind || k === 27 + v.seatWind;
    if (yakuhai && c[k] >= 2) val += 2;
    else if (isHonor(k) && c[k] === 1) val -= yakuhai ? 0.3 : 1;
    if (!isHonor(k) && (k % 9 === 0 || k % 9 === 8)) val -= 0.4;
    return val;
  }

  function chooseDiscard(v, discards, level) {
    const c = countsOf(v.hand);
    const melds = meldCount(v);
    const seen = visibleCounts(v);
    const threats = level === 'hard' ? threatsOf(v) : [];
    const sh0 = shanten(c, melds);
    let fold = false;
    if (threats.length) {
      // fold when far from tenpai (or tenpai on a cheap hand against riichi late)
      fold = sh0 >= 2 || (sh0 === 1 && v.wallLeft < 25);
    }
    const scored = [];
    const seenKinds = new Set();
    for (const a of discards) {
      const k = kindOf(a.tile);
      const key = k * 2 + (R.RED.has(a.tile) ? 1 : 0);
      if (seenKinds.has(key)) continue;
      seenKinds.add(key);
      c[k]--;
      const sh = shanten(c, melds);
      const uk = level === 'hard' ? ukeire(c, melds, seen, v.sanma) : 0;
      c[k]++;
      let score = -sh * 1000 + uk * 4 - tileValue(v, k, c) * 6 - (R.RED.has(a.tile) ? 12 : 0);
      if (level === 'easy') score += Math.random() * 300;
      if (threats.length) {
        const d = danger(v, k, threats);
        score -= d * (fold ? 400 : sh <= 0 ? 8 : 40);
      }
      scored.push({ a, score });
    }
    scored.sort((x, y) => y.score - x.score);
    return scored[0].a;
  }

  // does the hand have (or plausibly aim for) a yaku if we open it?
  function openYakuPlan(v, c) {
    for (let k = 27; k < 34; k++) {
      const yakuhai = k >= 31 || k === 27 + v.roundWind || k === 27 + v.seatWind;
      if (yakuhai && c[k] >= 2) return true;
    }
    for (const m of v.melds[v.seat]) {
      const k = kindOf(m.ids[0]);
      if (k >= 31 || k === 27 + v.roundWind || k === 27 + v.seatWind) return true;
    }
    // tanyao
    let yao = 0;
    for (let k = 0; k < 34; k++) if (isYao(k)) yao += c[k];
    const meldYao = v.melds[v.seat].some(m => m.ids.some(id => isYao(kindOf(id))));
    if (yao <= 1 && !meldYao) return true;
    // honitsu / chinitsu direction
    const suitCount = [0, 0, 0];
    for (let k = 0; k < 27; k++) suitCount[Math.floor(k / 9)] += c[k];
    const total = c.reduce((a, b) => a + b, 0);
    let honors = 0;
    for (let k = 27; k < 34; k++) honors += c[k];
    if (Math.max(...suitCount) + honors >= total - 1) return true;
    return false;
  }

  function decide(v, actions, level) {
    level = level === 'hard' ? 'hard' : 'easy';
    const has = t => actions.find(a => a.type === t);
    if (has('tsumo')) return has('tsumo');
    if (has('ron')) return has('ron');
    if (has('next')) return has('next');
    // turn actions
    const discards = actions.filter(a => a.type === 'discard');
    if (discards.length) {
      if (has('kyuushu')) {
        const yao = new Set(v.hand.map(kindOf).filter(isYao)).size;
        if (yao < 11) return has('kyuushu');
      }
      if (has('kita')) return has('kita');
      const c = countsOf(v.hand);
      const melds = meldCount(v);
      const threats = level === 'hard' ? threatsOf(v) : [];
      // kan: only when it doesn't hurt the hand
      for (const a of actions.filter(x => x.type === 'ankan' || x.type === 'kakan')) {
        if (threats.length && level === 'hard') break;
        const k = a.kind != null ? a.kind : kindOf(a.tile);
        const cc = c.slice(); cc[k] -= a.type === 'ankan' ? 4 : 1;
        const after = shanten(cc, melds + (a.type === 'ankan' ? 1 : 0));
        const before = Math.min(...discards.map(d => { const x = c.slice(); x[kindOf(d.tile)]--; return shanten(x, melds); }));
        if (after <= before) return a;
      }
      const riichis = actions.filter(a => a.type === 'riichi');
      if (riichis.length) {
        const pick = chooseDiscard(v, riichis.map(r => ({ type: 'discard', tile: r.tile })), level);
        const r = riichis.find(x => x.tile === pick.tile);
        // hard: dama with a big hand is fine, but riichi is usually right; avoid riichi very late
        if (level === 'easy' || v.wallLeft >= 8) return r;
      }
      return chooseDiscard(v, discards, level);
    }
    // call decisions
    const pass = has('pass');
    if (!pass) return actions[0];
    const c = countsOf(v.hand);
    const melds = meldCount(v);
    const sh = shanten(c, melds);
    const k = v.callTile != null ? kindOf(v.callTile) : -1;
    const kan = has('daiminkan');
    if (kan && level === 'easy' && Math.random() < 0.3) return kan;
    const calls = actions.filter(a => a.type === 'pon' || a.type === 'chi');
    for (const a of calls) {
      const cc = c.slice();
      for (const id of a.tiles) cc[kindOf(id)]--;
      // best discard after calling
      let bestAfter = 9;
      for (let x = 0; x < 34; x++) if (cc[x]) { cc[x]--; bestAfter = Math.min(bestAfter, shanten(cc, melds + 1)); cc[x]++; }
      const yakuhai = k >= 31 || k === 27 + v.roundWind || k === 27 + v.seatWind;
      if (level === 'easy') {
        if (a.type === 'pon' && yakuhai) return a;
        if (bestAfter < sh && Math.random() < 0.25 && openYakuPlan(v, c)) return a;
        continue;
      }
      if (threatsOf(v).length && sh >= 2) continue;
      if (a.type === 'pon' && yakuhai) return a;
      if (bestAfter < sh && openYakuPlan(v, c) && (sh <= 2 || v.wallLeft < 40)) return a;
    }
    return pass;
  }

  const api = { decide, ukeire, danger };
  root.RiichiAI = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
