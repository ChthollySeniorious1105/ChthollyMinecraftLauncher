// 国际象棋 rules engine + search. Browser script (window.ChessEngine), Web Worker, and node module.
// Board: 0x88 array of 128. Pieces: white positive, black negative. 1 P 2 N 3 B 4 R 5 Q 6 K.
// State: { b: Int8Array(128), side: 1|-1, castle: bitmask (1 K,2 Q,4 k,8 q), ep: square|-1, half, full }
// Move: object { f, t, p (promotion piece type or 0), flag: '' | 'ep' | 'castle' | 'double' }
(function (root) {
  const P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6;
  const VAL = [0, 100, 320, 330, 500, 900, 0];
  const MATE = 100000;
  const N_D = [-33, -31, -18, -14, 14, 18, 31, 33];
  const B_D = [-17, -15, 15, 17];
  const R_D = [-16, -1, 1, 16];
  const K_D = [-17, -16, -15, -1, 1, 15, 16, 17];
  const sq = (file, rank) => rank * 16 + file;           // rank 0 = white's first rank
  const fileOf = s => s & 7, rankOf = s => s >> 4;
  const name = s => 'abcdefgh'[fileOf(s)] + (rankOf(s) + 1);

  function initial() {
    const b = new Int8Array(128);
    const back = [R, N, B, Q, K, B, N, R];
    for (let f = 0; f < 8; f++) {
      b[sq(f, 0)] = back[f]; b[sq(f, 1)] = P;
      b[sq(f, 7)] = -back[f]; b[sq(f, 6)] = -P;
    }
    return { b, side: 1, castle: 15, ep: -1, half: 0, full: 1 };
  }
  const clone = st => ({ b: Int8Array.from(st.b), side: st.side, castle: st.castle, ep: st.ep, half: st.half, full: st.full });

  function fromFEN(fen) {
    const [pos, side, cas, ep, half, full] = fen.trim().split(/\s+/);
    const b = new Int8Array(128);
    const map = { p: P, n: N, b: B, r: R, q: Q, k: K };
    pos.split('/').forEach((row, i) => {
      let f = 0;
      for (const ch of row) {
        if (/\d/.test(ch)) { f += Number(ch); continue; }
        const t = map[ch.toLowerCase()];
        b[sq(f, 7 - i)] = ch === ch.toUpperCase() ? t : -t;
        f++;
      }
    });
    let castle = 0;
    if (cas.includes('K')) castle |= 1; if (cas.includes('Q')) castle |= 2;
    if (cas.includes('k')) castle |= 4; if (cas.includes('q')) castle |= 8;
    const epSq = ep === '-' ? -1 : sq(ep.charCodeAt(0) - 97, Number(ep[1]) - 1);
    return { b, side: side === 'w' ? 1 : -1, castle, ep: epSq, half: Number(half || 0), full: Number(full || 1) };
  }

  function attacked(b, s, by) {
    // pawns
    const pr = by > 0 ? -1 : 1; // attacker pawns sit one rank "behind" from their direction
    for (const df of [-1, 1]) {
      const a = s + pr * 16 + df;
      if (!(a & 0x88) && b[a] === by * P) return true;
    }
    for (const d of N_D) { const a = s + d; if (!(a & 0x88) && b[a] === by * N) return true; }
    for (const d of K_D) { const a = s + d; if (!(a & 0x88) && b[a] === by * K) return true; }
    for (const d of B_D) {
      let a = s + d;
      while (!(a & 0x88)) { const p = b[a]; if (p) { if (p === by * B || p === by * Q) return true; break; } a += d; }
    }
    for (const d of R_D) {
      let a = s + d;
      while (!(a & 0x88)) { const p = b[a]; if (p) { if (p === by * R || p === by * Q) return true; break; } a += d; }
    }
    return false;
  }
  function kingSq(b, side) {
    for (let s = 0; s < 128; s++) if (!(s & 0x88) && b[s] === side * K) return s;
    return -1;
  }
  const inCheck = (st, side) => attacked(st.b, kingSq(st.b, side), -side);

  function genPseudo(st, capturesOnly) {
    const { b, side } = st, out = [];
    for (let s = 0; s < 128; s++) {
      if (s & 0x88) { s += 7; continue; }
      const p = b[s];
      if (p * side <= 0) continue;
      const t = p * side;
      if (t === P) {
        const fwd = side * 16, start = side > 0 ? 1 : 6, last = side > 0 ? 7 : 0;
        const one = s + fwd;
        const push = (to, flag) => {
          if (rankOf(to) === last) for (const pp of [Q, R, B, N]) out.push({ f: s, t: to, p: pp, flag });
          else out.push({ f: s, t: to, p: 0, flag });
        };
        if (!capturesOnly && !(one & 0x88) && !b[one]) {
          push(one, '');
          const two = one + fwd;
          if (rankOf(s) === start && !b[two]) out.push({ f: s, t: two, p: 0, flag: 'double' });
        }
        for (const df of [-1, 1]) {
          const to = s + fwd + df;
          if (to & 0x88) continue;
          if (b[to] * side < 0) push(to, '');
          else if (to === st.ep) out.push({ f: s, t: to, p: 0, flag: 'ep' });
        }
      } else if (t === N || t === K) {
        for (const d of t === N ? N_D : K_D) {
          const to = s + d;
          if (to & 0x88 || b[to] * side > 0) continue;
          if (capturesOnly && !b[to]) continue;
          out.push({ f: s, t: to, p: 0, flag: '' });
        }
        if (t === K && !capturesOnly) {
          const r = side > 0 ? 0 : 7, ks = side > 0 ? 1 : 4, qs = side > 0 ? 2 : 8;
          if (s === sq(4, r) && !attacked(b, s, -side)) {
            if (st.castle & ks && !b[sq(5, r)] && !b[sq(6, r)] && b[sq(7, r)] === side * R &&
                !attacked(b, sq(5, r), -side) && !attacked(b, sq(6, r), -side)) out.push({ f: s, t: sq(6, r), p: 0, flag: 'castle' });
            if (st.castle & qs && !b[sq(3, r)] && !b[sq(2, r)] && !b[sq(1, r)] && b[sq(0, r)] === side * R &&
                !attacked(b, sq(3, r), -side) && !attacked(b, sq(2, r), -side)) out.push({ f: s, t: sq(2, r), p: 0, flag: 'castle' });
          }
        }
      } else {
        const dirs = t === B ? B_D : t === R ? R_D : K_D;
        for (const d of dirs) {
          let to = s + d;
          while (!(to & 0x88)) {
            const q = b[to];
            if (q * side > 0) break;
            if (!capturesOnly || q) out.push({ f: s, t: to, p: 0, flag: '' });
            if (q) break;
            to += d;
          }
        }
      }
    }
    return out;
  }

  // castling-right masks: moving from / capturing on these squares clears rights
  const CASTLE_MASK = new Int8Array(128).fill(15);
  CASTLE_MASK[sq(4, 0)] = 15 & ~3; CASTLE_MASK[sq(0, 0)] = 15 & ~2; CASTLE_MASK[sq(7, 0)] = 15 & ~1;
  CASTLE_MASK[sq(4, 7)] = 15 & ~12; CASTLE_MASK[sq(0, 7)] = 15 & ~8; CASTLE_MASK[sq(7, 7)] = 15 & ~4;

  // returns undo info
  function make(st, m) {
    const b = st.b, side = st.side;
    const u = { m, cap: b[m.t], castle: st.castle, ep: st.ep, half: st.half, capSq: m.t };
    const piece = b[m.f];
    if (m.flag === 'ep') { u.capSq = m.t - side * 16; u.cap = b[u.capSq]; b[u.capSq] = 0; }
    b[m.t] = m.p ? m.p * side : piece;
    b[m.f] = 0;
    if (m.flag === 'castle') {
      const r = rankOf(m.f);
      if (fileOf(m.t) === 6) { b[sq(5, r)] = b[sq(7, r)]; b[sq(7, r)] = 0; }
      else { b[sq(3, r)] = b[sq(0, r)]; b[sq(0, r)] = 0; }
    }
    st.castle &= CASTLE_MASK[m.f] & CASTLE_MASK[m.t];
    st.ep = m.flag === 'double' ? m.f + side * 16 : -1;
    st.half = Math.abs(piece) === P || u.cap ? 0 : st.half + 1;
    if (side < 0) st.full++;
    st.side = -side;
    return u;
  }
  function unmake(st, u) {
    const m = u.m, b = st.b;
    st.side = -st.side;
    const side = st.side;
    b[m.f] = m.p ? P * side : b[m.t];
    b[m.t] = 0;
    b[u.capSq] = u.cap;
    if (m.flag === 'castle') {
      const r = rankOf(m.f);
      if (fileOf(m.t) === 6) { b[sq(7, r)] = b[sq(5, r)]; b[sq(5, r)] = 0; }
      else { b[sq(0, r)] = b[sq(3, r)]; b[sq(3, r)] = 0; }
    }
    st.castle = u.castle; st.ep = u.ep; st.half = u.half;
    if (side < 0) st.full--;
  }
  function legal(st) {
    const res = [];
    for (const m of genPseudo(st, false)) {
      const u = make(st, m);
      if (!inCheck(st, -st.side)) res.push(m);
      unmake(st, u);
    }
    return res;
  }
  function perft(st, d) {
    if (!d) return 1;
    let n = 0;
    for (const m of genPseudo(st, false)) {
      const u = make(st, m);
      if (!inCheck(st, -st.side)) n += d === 1 ? 1 : perft(st, d - 1);
      unmake(st, u);
    }
    return n;
  }

  // ---------- evaluation ----------
  // piece-square tables (white's view, rank 0 first), indexed [rank*8+file]
  const PST = {
    [P]: [0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, -20, -20, 10, 10, 5, 5, -5, -10, 0, 0, -10, -5, 5, 0, 0, 0, 20, 20, 0, 0, 0,
      5, 5, 10, 25, 25, 10, 5, 5, 10, 10, 20, 30, 30, 20, 10, 10, 50, 50, 50, 50, 50, 50, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0],
    [N]: [-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 5, 5, 0, -20, -40, -30, 5, 10, 15, 15, 10, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30,
      -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 10, 15, 15, 10, 0, -30, -40, -20, 0, 0, 0, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50],
    [B]: [-20, -10, -10, -10, -10, -10, -10, -20, -10, 5, 0, 0, 0, 0, 5, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 0, 10, 10, 10, 10, 0, -10,
      -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 0, 0, 0, 0, 0, 0, -10, -20, -10, -10, -10, -10, -10, -10, -20],
    [R]: [0, 0, 0, 5, 5, 0, 0, 0, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5,
      -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 5, 10, 10, 10, 10, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0],
    [Q]: [-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 5, 0, 0, 0, 0, -10, -10, 5, 5, 5, 5, 5, 0, -10, 0, 0, 5, 5, 5, 5, 0, -5,
      -5, 0, 5, 5, 5, 5, 0, -5, -10, 0, 5, 5, 5, 5, 0, -10, -10, 0, 0, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20],
    [K]: [20, 30, 10, 0, 0, 10, 30, 20, 20, 20, 0, 0, 0, 0, 20, 20, -10, -20, -20, -20, -20, -20, -20, -10, -20, -30, -30, -40, -40, -30, -30, -20,
      -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30]
  };
  const K_END = [-50, -30, -30, -30, -30, -30, -30, -50, -30, -30, 0, 0, 0, 0, -30, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -20, -10, 0, 0, -10, -20, -30, -50, -40, -30, -20, -20, -30, -40, -50];
  function evaluate(st) {
    const b = st.b;
    let s = 0, mat = 0;
    for (let q = 0; q < 128; q++) { if (q & 0x88) { q += 7; continue; } const p = b[q]; if (p && Math.abs(p) !== K && Math.abs(p) !== P) mat += VAL[Math.abs(p)]; }
    const endgame = mat < 2600;
    for (let q = 0; q < 128; q++) {
      if (q & 0x88) { q += 7; continue; }
      const p = b[q];
      if (!p) continue;
      const t = Math.abs(p), f = fileOf(q), r = rankOf(q);
      const idx = p > 0 ? r * 8 + f : (7 - r) * 8 + f;
      const pst = t === K && endgame ? K_END[idx] : PST[t][idx];
      s += (p > 0 ? 1 : -1) * (VAL[t] + pst);
    }
    return s * st.side;
  }

  // ---------- search ----------
  const LEVELS = {
    easy: { maxDepth: 2, timeMs: 600, noise: 80 },
    normal: { maxDepth: 4, timeMs: 2000, noise: 10 },
    hard: { maxDepth: 30, timeMs: 1800, noise: 0 }
  };
  const key = m => (m.f << 8 | m.t) << 3 | m.p;
  function search(st0, opts) {
    opts = typeof opts === 'string' ? LEVELS[opts] : opts || LEVELS.normal;
    const st = clone(st0);
    const start = Date.now();
    let nodes = 0, stop = false;
    const history = new Map(), killers = [];
    const timeUp = () => { if ((++nodes & 1023) === 0 && Date.now() - start > opts.timeMs) stop = true; return stop; };
    const scoreMove = (m, ply) => {
      const cap = st.b[m.t];
      if (cap || m.flag === 'ep') return 1e6 + VAL[Math.abs(cap) || 1] * 10 - VAL[Math.abs(st.b[m.f])] / 10 + (m.p === Q ? 5e5 : 0);
      if (m.p === Q) return 9e5;
      const k = killers[ply];
      const mk = key(m);
      if (k && (k[0] === mk || k[1] === mk)) return 5e5;
      return history.get(mk) || 0;
    };
    const order = (ms, ply) => ms.map(m => [scoreMove(m, ply), m]).sort((a, b) => b[0] - a[0]).map(x => x[1]);
    function qs(alpha, beta, ply) {
      if (timeUp()) return 0;
      const stand = evaluate(st);
      if (stand >= beta) return stand;
      if (stand > alpha) alpha = stand;
      if (ply > 30) return stand;
      for (const m of order(genPseudo(st, true), ply)) {
        const u = make(st, m);
        if (inCheck(st, -st.side)) { unmake(st, u); continue; }
        const v = -qs(-beta, -alpha, ply + 1);
        unmake(st, u);
        if (stop) return 0;
        if (v >= beta) return v;
        if (v > alpha) alpha = v;
      }
      return alpha;
    }
    function ab(depth, alpha, beta, ply) {
      if (timeUp()) return 0;
      if (st.half >= 100) return 0;
      const check = inCheck(st, st.side);
      if (check) depth++;
      if (depth <= 0) return qs(alpha, beta, ply);
      let best = -Infinity, any = false;
      for (const m of order(genPseudo(st, false), ply)) {
        const u = make(st, m);
        if (inCheck(st, -st.side)) { unmake(st, u); continue; }
        any = true;
        const v = -ab(depth - 1, -beta, -alpha, ply + 1);
        unmake(st, u);
        if (stop) return 0;
        if (v > best) best = v;
        if (v > alpha) alpha = v;
        if (alpha >= beta) {
          if (!u.cap) {
            const mk = key(m);
            const k = killers[ply] || (killers[ply] = [0, 0]);
            if (k[0] !== mk) { k[1] = k[0]; k[0] = mk; }
            history.set(mk, (history.get(mk) || 0) + depth * depth);
          }
          break;
        }
      }
      if (!any) return check ? -MATE + ply : 0;
      return best;
    }
    let root = legal(st);
    if (!root.length) return { move: null, score: 0, depth: 0 };
    let bestMove = root[0], bestScore = -Infinity, depthDone = 0;
    for (let d = 1; d <= opts.maxDepth; d++) {
      let alpha = -Infinity, iterBest = null, iterScore = -Infinity;
      const scores = new Map();
      for (const m of root) {
        const u = make(st, m);
        let v = -ab(d - 1, -Infinity, -alpha, 1);
        unmake(st, u);
        if (stop) break;
        if (opts.noise) v += Math.round((Math.random() - 0.5) * opts.noise * 2);
        scores.set(m, v);
        if (v > iterScore) { iterScore = v; iterBest = m; }
        if (v > alpha) alpha = v;
      }
      if (iterBest && (!stop || iterScore > bestScore)) { bestMove = iterBest; bestScore = iterScore; }
      if (stop) break;
      depthDone = d;
      root = root.slice().sort((a, b) => (scores.get(b) ?? -Infinity) - (scores.get(a) ?? -Infinity));
      if (Math.abs(bestScore) > MATE - 200) break;
    }
    return { move: bestMove, score: bestScore, depth: depthDone, nodes };
  }

  // ---------- notation ----------
  const LETTER = ['', '', 'N', 'B', 'R', 'Q', 'K'];
  function san(st, m) {
    const p = Math.abs(st.b[m.f]);
    let s;
    if (m.flag === 'castle') s = fileOf(m.t) === 6 ? 'O-O' : 'O-O-O';
    else {
      const cap = st.b[m.t] || m.flag === 'ep';
      if (p === P) s = (cap ? 'abcdefgh'[fileOf(m.f)] + 'x' : '') + name(m.t) + (m.p ? '=' + LETTER[m.p] : '');
      else {
        const others = legal(st).filter(o => o.t === m.t && o.f !== m.f && st.b[o.f] === st.b[m.f]);
        let dis = '';
        if (others.length) {
          if (!others.some(o => fileOf(o.f) === fileOf(m.f))) dis = 'abcdefgh'[fileOf(m.f)];
          else if (!others.some(o => rankOf(o.f) === rankOf(m.f))) dis = String(rankOf(m.f) + 1);
          else dis = name(m.f);
        }
        s = LETTER[p] + dis + (cap ? 'x' : '') + name(m.t);
      }
    }
    const u = make(st, m);
    const chk = inCheck(st, st.side);
    if (chk) s += legal(st).length ? '+' : '#';
    unmake(st, u);
    return s;
  }
  // position key for repetition detection
  const posKey = st => Array.from(st.b).join(',') + st.side + st.castle + st.ep;
  function insufficient(st) {
    const pcs = [];
    for (let q = 0; q < 128; q++) { if (q & 0x88) { q += 7; continue; } const p = Math.abs(st.b[q]); if (p && p !== K) pcs.push(p); }
    return !pcs.length || (pcs.length === 1 && (pcs[0] === N || pcs[0] === B));
  }

  const api = { P, N, B, R, Q, K, VAL, MATE, LEVELS, sq, fileOf, rankOf, name, initial, clone, fromFEN, legal, make, unmake, inCheck, perft, evaluate, search, san, posKey, insufficient, attacked, kingSq };
  root.ChessEngine = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window === 'undefined' && typeof importScripts === 'function') {
    self.onmessage = e => {
      const d = e.data;
      const st = { b: Int8Array.from(d.st.b), side: d.st.side, castle: d.st.castle, ep: d.st.ep, half: d.st.half, full: d.st.full };
      const r = search(st, d.level);
      self.postMessage({ id: d.id, move: r.move, score: r.score, depth: r.depth });
    };
  }
})(typeof self !== 'undefined' ? self : globalThis);
