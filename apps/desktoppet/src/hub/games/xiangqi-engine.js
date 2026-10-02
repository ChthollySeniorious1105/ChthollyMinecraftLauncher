// 中国象棋 rules engine + search. Loaded three ways:
//  - as a normal <script> in the hub (window.XiangqiEngine)
//  - as a Web Worker script (answers {id, board, side, level} with the best move)
//  - from node for perft tests (module.exports)
// Board: Int8Array(90), index = row * 9 + col, row 0 = black back rank (top), row 9 = red back rank.
// Pieces: red positive, black negative. 1 帅 2 仕 3 相 4 马 5 车 6 炮 7 兵. Move = from << 7 | to.
(function (root) {
  const K = 1, A = 2, B = 3, N = 4, R = 5, C = 6, P = 7;
  const VAL = [0, 0, 200, 200, 400, 900, 450, 100];
  const MATE = 100000;
  const DIR4 = [[-1, 0], [1, 0], [0, -1], [0, 1]];
  const DIAG = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
  const HORSE = [[-2, -1], [-2, 1], [2, -1], [2, 1], [-1, -2], [1, -2], [-1, 2], [1, 2]];

  function initial() {
    const b = new Int8Array(90);
    const back = [R, N, B, A, K, A, B, N, R];
    for (let c = 0; c < 9; c++) { b[c] = -back[c]; b[81 + c] = back[c]; }
    b[19] = -C; b[25] = -C; b[64] = C; b[70] = C;
    for (let c = 0; c < 9; c += 2) { b[27 + c] = -P; b[54 + c] = P; }
    return b;
  }

  const inPalace = (side, r, c) => c >= 3 && c <= 5 && (side > 0 ? r >= 7 && r <= 9 : r >= 0 && r <= 2);
  const ownHalf = (side, r) => (side > 0 ? r >= 5 : r <= 4);
  const onBoard = (r, c) => r >= 0 && r < 10 && c >= 0 && c < 9;

  // pseudo-legal moves (may leave own king attacked)
  function genMoves(b, side, capturesOnly, out) {
    out = out || [];
    for (let sq = 0; sq < 90; sq++) {
      const p = b[sq];
      if (p * side <= 0) continue;
      const t = p > 0 ? p : -p, r = (sq / 9) | 0, c = sq % 9;
      const add = to => {
        const q = b[to];
        if (q * side > 0) return;
        if (capturesOnly && q === 0) return;
        out.push(sq << 7 | to);
      };
      if (t === K) {
        for (const [dr, dc] of DIR4) if (inPalace(side, r + dr, c + dc)) add((r + dr) * 9 + c + dc);
      } else if (t === A) {
        for (const [dr, dc] of DIAG) if (inPalace(side, r + dr, c + dc)) add((r + dr) * 9 + c + dc);
      } else if (t === B) {
        for (const [dr, dc] of DIAG) {
          const rr = r + 2 * dr, cc = c + 2 * dc;
          if (onBoard(rr, cc) && ownHalf(side, rr) && !b[(r + dr) * 9 + c + dc]) add(rr * 9 + cc);
        }
      } else if (t === N) {
        for (const [dr, dc] of HORSE) {
          const rr = r + dr, cc = c + dc;
          if (!onBoard(rr, cc)) continue;
          const leg = Math.abs(dr) === 2 ? (r + dr / 2) * 9 + c : r * 9 + c + dc / 2;
          if (!b[leg]) add(rr * 9 + cc);
        }
      } else if (t === R) {
        for (const [dr, dc] of DIR4) {
          let rr = r + dr, cc = c + dc;
          while (onBoard(rr, cc)) {
            const to = rr * 9 + cc;
            if (b[to]) { add(to); break; }
            if (!capturesOnly) out.push(sq << 7 | to);
            rr += dr; cc += dc;
          }
        }
      } else if (t === C) {
        for (const [dr, dc] of DIR4) {
          let rr = r + dr, cc = c + dc, screen = false;
          while (onBoard(rr, cc)) {
            const to = rr * 9 + cc, q = b[to];
            if (!screen) {
              if (q) screen = true;
              else if (!capturesOnly) out.push(sq << 7 | to);
            } else if (q) {
              if (q * side < 0) out.push(sq << 7 | to);
              break;
            }
            rr += dr; cc += dc;
          }
        }
      } else if (t === P) {
        const f = side > 0 ? -1 : 1;
        if (onBoard(r + f, c)) add((r + f) * 9 + c);
        if (!ownHalf(side, r)) {
          if (c > 0) add(r * 9 + c - 1);
          if (c < 8) add(r * 9 + c + 1);
        }
      }
    }
    return out;
  }

  function findKing(b, side) {
    const k = K * side;
    // kings live in the palaces, so only scan those squares
    const rows = side > 0 ? [7, 8, 9] : [0, 1, 2];
    for (const r of rows) for (let c = 3; c <= 5; c++) if (b[r * 9 + c] === k) return r * 9 + c;
    return -1;
  }

  // is square sq attacked by side `by`? (includes the "flying general" rule)
  function attacked(b, sq, by) {
    const r = (sq / 9) | 0, c = sq % 9;
    for (const [dr, dc] of DIR4) {
      let rr = r + dr, cc = c + dc, screen = false;
      while (onBoard(rr, cc)) {
        const q = b[rr * 9 + cc];
        if (q) {
          if (!screen) {
            if (q === by * R) return true;
            if (q === by * K && dc === 0) return true;
            screen = true;
          } else {
            if (q === by * C) return true;
            break;
          }
        }
        rr += dr; cc += dc;
      }
    }
    for (const [dr, dc] of HORSE) {
      const hr = r + dr, hc = c + dc;
      if (!onBoard(hr, hc) || b[hr * 9 + hc] !== by * N) continue;
      // the horse moves (-dr, -dc); its leg is next to the horse along the long axis
      const leg = Math.abs(dr) === 2 ? (hr - dr / 2) * 9 + hc : hr * 9 + hc - dc / 2;
      if (!b[leg]) return true;
    }
    const f = by > 0 ? -1 : 1; // direction the attacking pawns move
    if (onBoard(r - f, c) && b[(r - f) * 9 + c] === by * P) return true;
    for (const dc of [-1, 1]) {
      if (!onBoard(r, c + dc) || b[r * 9 + c + dc] !== by * P) continue;
      if (by > 0 ? r <= 4 : r >= 5) return true;
    }
    return false;
  }

  const inCheck = (b, side) => {
    const k = findKing(b, side);
    return k < 0 || attacked(b, k, -side);
  };

  function makeMove(b, m) {
    const f = m >> 7, t = m & 127, cap = b[t];
    b[t] = b[f]; b[f] = 0;
    return cap;
  }
  function unmake(b, m, cap) {
    const f = m >> 7, t = m & 127;
    b[f] = b[t]; b[t] = cap;
  }

  function genLegal(b, side) {
    const res = [];
    for (const m of genMoves(b, side, false)) {
      const cap = makeMove(b, m);
      if (!inCheck(b, side)) res.push(m);
      unmake(b, m, cap);
    }
    return res;
  }

  function perft(b, side, depth) {
    if (depth === 0) return 1;
    let n = 0;
    for (const m of genMoves(b, side, false)) {
      const cap = makeMove(b, m);
      if (!inCheck(b, side)) n += depth === 1 ? 1 : perft(b, -side, depth - 1);
      unmake(b, m, cap);
    }
    return n;
  }

  // ---------- evaluation (from red's point of view) ----------
  function pst(t, r, c) {
    // r, c from red's perspective (row 0 = enemy back rank)
    const center = 4 - Math.abs(c - 4);
    switch (t) {
      case P:
        if (r >= 5) return r === 5 ? 5 : 0;
        return 60 + center * 8 + (r <= 2 && r >= 1 ? 25 : 0) - (r === 0 ? 40 : 0);
      case N: return center * 6 + (r >= 2 && r <= 6 ? 12 : 0) - (r === 9 ? 15 : 0);
      case C: return (c === 4 ? 15 : 0) + (r === 7 || r === 2 ? 5 : 0);
      case R: return (r <= 4 ? 15 : 0) + (c === 3 || c === 5 ? 5 : 0);
      default: return 0;
    }
  }
  function evaluate(b) {
    let s = 0;
    for (let sq = 0; sq < 90; sq++) {
      const p = b[sq];
      if (!p) continue;
      const r = (sq / 9) | 0, c = sq % 9;
      if (p > 0) s += VAL[p] + pst(p, r, c);
      else s -= VAL[-p] + pst(-p, 9 - r, 8 - c);
    }
    return s;
  }

  // ---------- search ----------
  const LEVELS = {
    easy: { maxDepth: 2, timeMs: 800, noise: 60 },
    normal: { maxDepth: 4, timeMs: 2500, noise: 0 },
    hard: { maxDepth: 30, timeMs: 1500, noise: 0 }
  };

  function search(b, side, opts) {
    opts = typeof opts === 'string' ? LEVELS[opts] : opts || LEVELS.normal;
    const start = Date.now();
    let nodes = 0, stop = false;
    const history = new Int32Array(90 << 7);
    const killers = [];

    const score = (m, killer) => {
      const cap = b[m & 127];
      if (cap) return 1e6 + VAL[Math.abs(cap)] * 10 - VAL[Math.abs(b[m >> 7])] / 10;
      if (killer && (killer[0] === m || killer[1] === m)) return 5e5;
      return history[m];
    };
    const order = (moves, ply) => {
      const k = killers[ply];
      const sc = moves.map(m => score(m, k));
      const idx = moves.map((_, i) => i).sort((x, y) => sc[y] - sc[x]);
      return idx.map(i => moves[i]);
    };
    const timeUp = () => {
      if ((++nodes & 1023) === 0 && Date.now() - start > opts.timeMs) stop = true;
      return stop;
    };

    function qs(alpha, beta, s, ply) {
      if (timeUp()) return 0;
      const stand = evaluate(b) * s;
      if (stand >= beta) return stand;
      if (stand > alpha) alpha = stand;
      if (ply > 40) return stand;
      const moves = order(genMoves(b, s, true), ply);
      for (const m of moves) {
        const cap = makeMove(b, m);
        if (Math.abs(cap) === K) { unmake(b, m, cap); return MATE - ply; }
        if (inCheck(b, s)) { unmake(b, m, cap); continue; }
        const v = -qs(-beta, -alpha, -s, ply + 1);
        unmake(b, m, cap);
        if (stop) return 0;
        if (v >= beta) return v;
        if (v > alpha) alpha = v;
      }
      return alpha;
    }

    function ab(depth, alpha, beta, s, ply) {
      if (timeUp()) return 0;
      const check = inCheck(b, s);
      if (check && ply < 30) depth++;
      if (depth <= 0) return qs(alpha, beta, s, ply);
      let best = -MATE + ply, any = false;
      const moves = order(genMoves(b, s, false), ply);
      for (const m of moves) {
        const cap = makeMove(b, m);
        if (inCheck(b, s)) { unmake(b, m, cap); continue; }
        any = true;
        const v = -ab(depth - 1, -beta, -alpha, -s, ply + 1);
        unmake(b, m, cap);
        if (stop) return 0;
        if (v > best) best = v;
        if (v > alpha) alpha = v;
        if (alpha >= beta) {
          if (!cap) {
            const k = killers[ply] || (killers[ply] = [0, 0]);
            if (k[0] !== m) { k[1] = k[0]; k[0] = m; }
            history[m] += depth * depth;
          }
          break;
        }
      }
      // no legal move: checkmate or stalemate — both lose in xiangqi
      if (!any) return -MATE + ply;
      return best;
    }

    let rootMoves = genLegal(b, side);
    if (!rootMoves.length) return { move: 0, score: -MATE, depth: 0, nodes };
    let bestMove = rootMoves[0], bestScore = -Infinity, doneDepth = 0;
    let rootScores = new Map();
    for (let d = 1; d <= opts.maxDepth; d++) {
      let alpha = -MATE - 1, iterBest = 0, iterScore = -Infinity;
      const scores = new Map();
      for (const m of rootMoves) {
        const cap = makeMove(b, m);
        let v = -ab(d - 1, -MATE - 1, -alpha, -side, 1);
        unmake(b, m, cap);
        if (stop) break;
        if (opts.noise) v += Math.round((Math.random() - 0.5) * opts.noise * 2);
        scores.set(m, v);
        if (v > iterScore) { iterScore = v; iterBest = m; }
        if (v > alpha) alpha = v;
      }
      if (stop && !iterBest) break;
      if (!stop || iterScore > bestScore) { bestMove = iterBest; bestScore = iterScore; }
      if (stop) break;
      doneDepth = d;
      rootScores = scores;
      // search the best moves first next iteration
      rootMoves = rootMoves.slice().sort((x, y) => (scores.get(y) ?? -Infinity) - (scores.get(x) ?? -Infinity));
      if (Math.abs(bestScore) > MATE - 100) break;
    }
    void rootScores;
    return { move: bestMove, score: bestScore, depth: doneDepth, nodes };
  }

  // ---------- Chinese notation (board BEFORE the move) ----------
  const CN = '一二三四五六七八九', FW = '１２３４５６７８９';
  const NAME_R = ['', '帅', '仕', '相', '马', '车', '炮', '兵'];
  const NAME_B = ['', '将', '士', '象', '马', '车', '炮', '卒'];
  function notate(b, m) {
    const f = m >> 7, t = m & 127, p = b[f], side = p > 0 ? 1 : -1, ty = Math.abs(p);
    const fr = (f / 9) | 0, fc = f % 9, tr = (t / 9) | 0, tc = t % 9;
    const num = n => (side > 0 ? CN : FW)[n - 1];
    const file = c => (side > 0 ? 9 - c : c + 1);
    const name = (side > 0 ? NAME_R : NAME_B)[ty];
    const same = [];
    for (let r = 0; r < 10; r++) if (b[r * 9 + fc] === p) same.push(r);
    let head;
    if (same.length >= 2) {
      // order front (closest to the enemy) to back
      same.sort((x, y) => (side > 0 ? x - y : y - x));
      const i = same.indexOf(fr);
      const labels = same.length === 2 ? ['前', '后'] : same.length === 3 ? ['前', '中', '后'] : ['一', '二', '三', '四', '五'];
      head = labels[i] + name;
    } else head = name + num(file(fc));
    let act;
    if (fr === tr) act = '平' + num(file(tc));
    else {
      const fwd = side > 0 ? tr < fr : tr > fr;
      const diag = ty === N || ty === B || ty === A;
      act = (fwd ? '进' : '退') + num(diag ? file(tc) : Math.abs(tr - fr));
    }
    return head + act;
  }

  const api = { K, A, B, N, R, C, P, VAL, MATE, LEVELS, initial, genMoves, genLegal, makeMove, unmake, inCheck, attacked, findKing, perft, evaluate, search, notate };
  root.XiangqiEngine = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;

  // running as a dedicated worker
  if (typeof window === 'undefined' && typeof importScripts === 'function') {
    self.onmessage = e => {
      const d = e.data;
      const res = search(Int8Array.from(d.board), d.side, d.level);
      self.postMessage({ id: d.id, move: res.move, score: res.score, depth: res.depth });
    };
  }
})(typeof self !== 'undefined' ? self : globalThis);
