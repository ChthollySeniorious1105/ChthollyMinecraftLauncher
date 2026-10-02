import '../../src/engine.dart';

const hanabiColorNames = ['红', '黄', '绿', '蓝', '白', '彩'];
const _copies = [0, 3, 2, 2, 2, 1];

class HCard {
  final int id, color, number;

  /// Public knowledge from clues.
  final Set<int> colors; // still possible colors
  final Set<int> numbers; // still possible numbers
  bool clued = false;

  /// Signal set from a play clue: identities (c*10+n) the card may be, playable at clue time.
  Set<int>? sig;
  bool saved = false;
  HCard(this.id, this.color, this.number, int nColors)
      : colors = {for (var c = 0; c < nColors; c++) c},
        numbers = {1, 2, 3, 4, 5};
}

/// 花火 (cooperative).
class Hanabi extends GameEngine {
  Hanabi(super.setup);

  late final int nColors = setup.opt<bool>('rainbow', false) ? 6 : 5;
  late final int handSize = players <= 3 ? 5 : 4;
  List<HCard> deck = [];
  late List<List<HCard>> hands; // index 0 = newest
  late List<int> stacks;
  final List<HCard> discards = [];
  int clues = 8, fuses = 0, turn = 0;
  int finalTurns = -1; // turns left after the deck ran out
  bool over = false;
  String endReason = '';
  Map<String, dynamic>? lastAction;
  final List<String> recent = [];
  int _seq = 0;

  int get maxScore => nColors * 5;
  int get score => fuses >= 3 ? 0 : stacks.fold(0, (a, b) => a + b);

  @override
  void start() {
    stacks = List.filled(nColors, 0);
    for (var c = 0; c < nColors; c++) {
      for (var n = 1; n <= 5; n++) {
        for (var k = 0; k < _copies[n]; k++) {
          deck.add(HCard(_seq++, c, n, nColors));
        }
      }
    }
    deck.shuffle(rng);
    hands = [for (var p = 0; p < players; p++) <HCard>[]];
    for (var i = 0; i < handSize; i++) {
      for (var p = 0; p < players; p++) {
        hands[p].insert(0, deck.removeLast());
      }
    }
    turn = rng.nextInt(players);
  }

  String cardName(HCard c) => '${hanabiColorNames[c.color]}${c.number}';

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 8) recent.removeAt(0);
  }

  bool playable(int c, int n) => stacks[c] == n - 1;

  // --------------------------------------------------------- knowledge helpers
  /// Copies of identity (c,n) not yet seen in public info (discards + stacks).
  int _publicRemaining(int c, int n) {
    var r = _copies[n];
    if (stacks[c] >= n) r--;
    for (final d in discards) {
      if (d.color == c && d.number == n) r--;
    }
    return r;
  }

  /// Common-knowledge possible identities of a card (c*10+n).
  Set<int> publicPoss(HCard k) => {
        for (final c in k.colors)
          for (final n in k.numbers)
            if (_publicRemaining(c, n) > 0) c * 10 + n
      };

  /// Possible identities of [seat]'s own card, using clues + everything [seat] sees.
  Map<int, int> ownPoss(int seat, HCard k) {
    final seen = <int, int>{};
    for (var p = 0; p < players; p++) {
      if (p == seat) continue;
      for (final c in hands[p]) {
        final id = c.color * 10 + c.number;
        seen[id] = (seen[id] ?? 0) + 1;
      }
    }
    final out = <int, int>{};
    for (final c in k.colors) {
      for (final n in k.numbers) {
        final left = _publicRemaining(c, n) - (seen[c * 10 + n] ?? 0);
        if (left > 0) out[c * 10 + n] = left;
      }
    }
    return out;
  }

  bool _dead(int c, int n) {
    if (stacks[c] >= n) return true;
    for (var m = stacks[c] + 1; m < n; m++) {
      // every copy of a lower card is already discarded -> this card can never be played
      if (_publicRemaining(c, m) <= 0) return true;
    }
    return false;
  }

  bool critical(int c, int n) => !_dead(c, n) && _publicRemaining(c, n) == 1;

  int chop(int p) {
    final h = hands[p];
    for (var i = h.length - 1; i >= 0; i--) {
      if (!h[i].clued) return i;
    }
    return -1;
  }

  // --------------------------------------------------------- actions
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    switch (type) {
      case 'clue':
        _clue(seat, asInt(a['to']), asInt(a['color'], -1), asInt(a['number'], -1));
      case 'play':
        _play(seat, asInt(a['i']));
      case 'discard':
        _discard(seat, asInt(a['i']));
      default:
        throw GameError('未知操作');
    }
    _advance();
  }

  /// Cards of [to] matching the clue (throws on illegal clue).
  List<int> clueTargets(int seat, int to, int color, int number) {
    if (clues <= 0) throw GameError('没有提示标记了');
    if (to < 0 || to >= players || to == seat) throw GameError('只能提示其他玩家');
    if ((color < 0) == (number < 0)) throw GameError('请选择一种颜色或一个数字');
    if (color >= nColors || number > 5 || (number >= 0 && number < 1)) throw GameError('无效提示');
    final h = hands[to];
    final hits = [for (var i = 0; i < h.length; i++) if (color >= 0 ? h[i].color == color : h[i].number == number) i];
    if (hits.isEmpty) throw GameError('提示必须至少指向一张牌');
    return hits;
  }

  void _clue(int seat, int to, int color, int number) {
    final hits = clueTargets(seat, to, color, number);
    final h = hands[to];
    final ch = chop(to);
    final fresh = [for (final i in hits) if (!h[i].clued) i];
    for (var i = 0; i < h.length; i++) {
      final c = h[i];
      final hit = hits.contains(i);
      if (color >= 0) {
        hit ? c.colors.retainAll({color}) : c.colors.remove(color);
      } else {
        hit ? c.numbers.retainAll({number}) : c.numbers.remove(number);
      }
    }
    // convention: focus = chop if newly touched, else newest newly-touched card
    if (fresh.isNotEmpty) {
      final focus = fresh.contains(ch) ? ch : fresh.first;
      final f = h[focus];
      final sig = {for (final id in publicPoss(f)) if (playable(id ~/ 10, id % 10)) id};
      if (sig.isEmpty) {
        f.saved = true;
      } else {
        f.sig = sig;
      }
    }
    for (final i in hits) {
      h[i].clued = true;
    }
    clues--;
    final what = color >= 0 ? '${hanabiColorNames[color]}色' : '$number';
    lastAction = {'type': 'clue', 'from': seat, 'to': to, 'color': color, 'number': number, 'ids': [for (final i in hits) h[i].id]};
    _log('${name(seat)} 提示 ${name(to)}：${hits.length} 张 $what');
  }

  void _removeAndDraw(int seat, int i) {
    hands[seat].removeAt(i);
    if (deck.isNotEmpty) {
      hands[seat].insert(0, deck.removeLast());
      if (deck.isEmpty) {
        finalTurns = players + 1; // decremented once for the current turn in _advance
        _log('牌堆已空，每人还有最后一个回合');
      }
    }
  }

  void _play(int seat, int i) {
    if (i < 0 || i >= hands[seat].length) throw GameError('无效的牌');
    final c = hands[seat][i];
    if (playable(c.color, c.number)) {
      stacks[c.color]++;
      if (c.number == 5 && clues < 8) clues++;
      lastAction = {'type': 'play', 'from': seat, 'ok': true, 'card': _cardJson(c, true)};
      _log('${name(seat)} 成功打出 ${cardName(c)}');
    } else {
      fuses++;
      discards.add(c);
      lastAction = {'type': 'play', 'from': seat, 'ok': false, 'card': _cardJson(c, true)};
      _log('${name(seat)} 打出 ${cardName(c)} 失败！引信 $fuses/3');
    }
    _removeAndDraw(seat, i);
  }

  void _discard(int seat, int i) {
    if (clues >= 8) throw GameError('提示标记已满（8 个），不能弃牌');
    if (i < 0 || i >= hands[seat].length) throw GameError('无效的牌');
    final c = hands[seat][i];
    discards.add(c);
    clues++;
    lastAction = {'type': 'discard', 'from': seat, 'card': _cardJson(c, true)};
    _log('${name(seat)} 弃掉 ${cardName(c)}');
    _removeAndDraw(seat, i);
  }

  void _advance() {
    if (fuses >= 3) {
      _finish('三次失误，烟花秀失败');
      return;
    }
    if (stacks.every((s) => s == 5)) {
      _finish('完美演出！');
      return;
    }
    if (finalTurns > 0) {
      finalTurns--;
      if (finalTurns == 0) {
        _finish('牌堆耗尽，最后一轮结束');
        return;
      }
    }
    turn = (turn + 1) % players;
  }

  void _finish(String reason) {
    over = true;
    endReason = reason;
    _log('游戏结束：$reason，得分 $score / $maxScore');
  }

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  bool get isOver => over;

  /// Cooperative: everyone shares the result.
  @override
  List<int>? get placings => over ? List.filled(players, 1) : null;

  Map<String, dynamic> _cardJson(HCard c, bool visible) => {
        'id': c.id,
        'c': visible ? c.color : null,
        'n': visible ? c.number : null,
        'cc': c.colors.toList()..sort(),
        'nn': c.numbers.toList()..sort(),
        'clued': c.clued,
      };

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : 'play',
        'turn': turn,
        'colors': nColors,
        'clues': clues,
        'fuses': fuses,
        'deck': deck.length,
        'stacks': stacks,
        'score': score,
        'max': maxScore,
        'finalTurns': finalTurns,
        'hands': [
          for (var p = 0; p < players; p++) [for (final c in hands[p]) _cardJson(c, p != seat || over)]
        ],
        'discards': [for (final c in discards) _cardJson(c, true)],
        'last': lastAction,
        'recent': recent,
        'result': over ? {'score': score, 'max': maxScore, 'reason': endReason} : null,
      };

  // --------------------------------------------------------- bot
  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final h = hands[seat];
    final poss = [for (final c in h) ownPoss(seat, c)];

    // 简单: fairly often does something random (never looks at its own cards)
    if (botLevel <= 0 && rng.nextDouble() < 0.2) {
      final r = _randomAction(seat);
      if (r != null) return r;
    }

    bool allPlayable(Iterable<int> ids) => ids.isNotEmpty && ids.every((id) => playable(id ~/ 10, id % 10));
    bool allDead(Iterable<int> ids) => ids.isNotEmpty && ids.every((id) => _dead(id ~/ 10, id % 10));

    // 1. play known / signalled playable cards (lowest number first)
    int? playIdx;
    var bestN = 99;
    for (var i = 0; i < h.length; i++) {
      final ids = poss[i].keys.toSet();
      final sig = h[i].sig;
      var cand = sig != null ? ids.intersection(sig) : ids;
      final ok = allPlayable(ids) || (sig != null && allPlayable(cand));
      if (cand.isEmpty) cand = ids;
      if (ok) {
        final n = cand.map((id) => id % 10).reduce((a, b) => a < b ? a : b);
        if (n < bestN) {
          bestN = n;
          playIdx = i;
        }
      }
    }
    if (playIdx != null) return {'type': 'play', 'i': playIdx};

    // 2. save critical chop cards
    if (clues > 0) {
      for (var d = 1; d < players; d++) {
        final p = (seat + d) % players;
        final ch = chop(p);
        if (ch < 0) continue;
        final c = hands[p][ch];
        if (!critical(c.color, c.number) || playable(c.color, c.number)) continue;
        // only urgent for the next couple of players
        if (d > 2) continue;
        if (botLevel <= 0 && rng.nextDouble() < 0.5) continue; // 简单 often forgets to save
        for (final cl in [
          {'number': c.number},
          {'color': c.color}
        ]) {
          if (_isSaveClue(p, ch, cl)) return {'type': 'clue', 'to': p, ...cl};
        }
      }
    }

    // 2b. 困难: 2-save — protect a chop 2 that nobody else holds
    if (botLevel >= 2 && clues > 0) {
      for (var d = 1; d < players && d <= 2; d++) {
        final p = (seat + d) % players;
        final ch = chop(p);
        if (ch < 0) continue;
        final c = hands[p][ch];
        if (c.number != 2 || _dead(c.color, 2) || playable(c.color, 2)) continue;
        var dup = false;
        for (var q = 0; q < players && !dup; q++) {
          if (q == seat) continue; // can't see own hand
          for (var i = 0; i < hands[q].length; i++) {
            final o = hands[q][i];
            if (!(q == p && i == ch) && o.color == c.color && o.number == 2) dup = true;
          }
        }
        if (dup) continue;
        final cl = {'number': 2};
        if (_isSaveClue(p, ch, cl)) return {'type': 'clue', 'to': p, ...cl};
      }
    }

    // 3. play clues
    if (clues > 0) {
      final known = <int>{};
      for (var p = 0; p < players; p++) {
        for (final c in hands[p]) {
          if (p != seat && (c.sig != null || c.clued)) known.add(c.color * 10 + c.number);
        }
      }
      Map<String, dynamic>? best;
      var bv = 0.0;
      for (var d = 1; d < players; d++) {
        final p = (seat + d) % players;
        final hp = hands[p];
        final options = <Map<String, dynamic>>[
          for (var c = 0; c < nColors; c++) {'color': c},
          for (var n = 1; n <= 5; n++) {'number': n},
        ];
        for (final cl in options) {
          final r = _evalPlayClue(p, cl, known);
          if (r == null) continue;
          final v = r - d * 0.3 + (hp.length - 1) * 0;
          if (v > bv) {
            bv = v;
            best = {'type': 'clue', 'to': p, ...cl};
          }
        }
      }
      if (best != null) return best;
    }

    // 3b. 困难: in the final round a discard gains nothing — gamble on the likeliest card
    if (botLevel >= 2 && deck.isEmpty && fuses < 2) {
      var bi = -1;
      var bp = 0.0;
      for (var i = 0; i < h.length; i++) {
        final tot = poss[i].values.fold(0, (a, b) => a + b);
        final ok = poss[i].entries.where((e) => playable(e.key ~/ 10, e.key % 10)).fold(0, (a, e) => a + e.value);
        final pr = tot == 0 ? 0.0 : ok / tot;
        if (pr > bp) {
          bp = pr;
          bi = i;
        }
      }
      if (bi >= 0 && bp >= 0.15) return {'type': 'play', 'i': bi};
    }

    // 4. discard
    if (clues < 8) {
      for (var i = h.length - 1; i >= 0; i--) {
        if (allDead(poss[i].keys)) return {'type': 'discard', 'i': i};
      }
      final ch = chop(seat);
      if (ch >= 0) return {'type': 'discard', 'i': ch};
      // everything clued: discard the least valuable (not possibly critical)
      for (var i = h.length - 1; i >= 0; i--) {
        if (!h[i].saved && !poss[i].keys.any((id) => critical(id ~/ 10, id % 10))) return {'type': 'discard', 'i': i};
      }
      return {'type': 'discard', 'i': h.length - 1};
    }

    // 5. 8 clues and nothing obvious: give a harmless clue, else play the likeliest card
    for (var d = 1; d < players; d++) {
      final p = (seat + d) % players;
      for (final cl in <Map<String, dynamic>>[
        for (var n = 5; n >= 1; n--) {'number': n},
        for (var c = 0; c < nColors; c++) {'color': c},
      ]) {
        if (_harmless(p, cl)) return {'type': 'clue', 'to': p, ...cl};
      }
    }
    var bi = 0;
    var bp = -1.0;
    for (var i = 0; i < h.length; i++) {
      final tot = poss[i].values.fold(0, (a, b) => a + b);
      final ok = poss[i].entries.where((e) => playable(e.key ~/ 10, e.key % 10)).fold(0, (a, e) => a + e.value);
      final pr = tot == 0 ? 0.0 : ok / tot;
      if (pr > bp) {
        bp = pr;
        bi = i;
      }
    }
    final gamble = botLevel >= 2 ? (bp > 0.6 || (fuses == 0 && bp > 0.25)) : (bp > 0.5 || fuses < 2);
    if (gamble) return {'type': 'play', 'i': bi};
    // fallback: any legal clue
    final p = (seat + 1) % players;
    return {'type': 'clue', 'to': p, 'number': hands[p].first.number};
  }

  /// A random legal clue / discard (rarely a blind play) — used by 简单 bots.
  Map<String, dynamic>? _randomAction(int seat) {
    final opts = <Map<String, dynamic>>[];
    if (clues > 0) {
      for (var d = 1; d < players; d++) {
        final p = (seat + d) % players;
        for (final c in hands[p]) {
          opts.add({'type': 'clue', 'to': p, 'color': c.color});
          opts.add({'type': 'clue', 'to': p, 'number': c.number});
        }
      }
    }
    if (clues < 8) {
      for (var i = 0; i < hands[seat].length; i++) {
        if (!hands[seat][i].clued) opts.add({'type': 'discard', 'i': i});
      }
    }
    if (fuses < 2 && rng.nextDouble() < 0.15) return {'type': 'play', 'i': rng.nextInt(hands[seat].length)};
    return opts.isEmpty ? null : opts[rng.nextInt(opts.length)];
  }

  /// Simulates the public knowledge after a clue: returns (hits, focus index, focus sig) or null if illegal.
  (List<int>, int, Set<int>)? _simClue(int p, Map<String, dynamic> cl) {
    final h = hands[p];
    final color = asInt(cl['color'], -1), number = asInt(cl['number'], -1);
    final hits = [for (var i = 0; i < h.length; i++) if (color >= 0 ? h[i].color == color : h[i].number == number) i];
    if (hits.isEmpty) return null;
    final fresh = [for (final i in hits) if (!h[i].clued) i];
    if (fresh.isEmpty) return (hits, -1, <int>{});
    final ch = chop(p);
    final focus = fresh.contains(ch) ? ch : fresh.first;
    final f = h[focus];
    final cs = color >= 0 ? f.colors.intersection({color}) : f.colors;
    final ns = number >= 0 ? f.numbers.intersection({number}) : f.numbers;
    final sig = <int>{
      for (final c in cs)
        for (final n in ns)
          if (_publicRemaining(c, n) > 0 && playable(c, n)) c * 10 + n
    };
    return (hits, focus, sig);
  }

  bool _isSaveClue(int p, int ch, Map<String, dynamic> cl) {
    final r = _simClue(p, cl);
    if (r == null) return false;
    final (_, focus, sig) = r;
    return focus == ch && sig.isEmpty;
  }

  /// Clue that creates no false play signal.
  bool _harmless(int p, Map<String, dynamic> cl) {
    final r = _simClue(p, cl);
    if (r == null) return false;
    final (_, focus, sig) = r;
    if (focus < 0 || sig.isEmpty) return true;
    final f = hands[p][focus];
    return playable(f.color, f.number);
  }

  double? _evalPlayClue(int p, Map<String, dynamic> cl, Set<int> known) {
    final r = _simClue(p, cl);
    if (r == null) return null;
    final (hits, focus, sig) = r;
    if (focus < 0 || sig.isEmpty) return null;
    final h = hands[p];
    final f = h[focus];
    if (!playable(f.color, f.number)) return null;
    if (known.contains(f.color * 10 + f.number)) return null;
    // duplicate playable cards in the same hand are fine; count newly useful touches
    var v = 2.0 + (5 - f.number) * 0.1;
    for (final i in hits) {
      if (i == focus || h[i].clued) continue;
      final c = h[i];
      if (_dead(c.color, c.number)) {
        v -= 0.5;
      } else {
        v += 0.3;
      }
    }
    if (f.number == 5) v += 0.5;
    return v;
  }
}
