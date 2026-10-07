import '../../src/engine.dart';
import 'cards.dart';

/// 钓鱼 (Go Fish).
class GoFish extends GameEngine {
  GoFish(super.setup);

  late List<List<String>> hands;
  late List<String> pond;
  late List<List<String>> books; // ranks laid down per seat
  int turn = 0;
  String phase = 'play'; // play | over
  int resigned = -1;
  final List<Map<String, dynamic>> log = []; // public ask log
  int asks = 0;

  /// Public knowledge (derived only from public events): ranks a seat is known
  /// to hold (rank -> ask index when learnt) and known not to hold.
  late List<Map<String, int>> known;
  late List<Map<String, int>> lacks;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => phase == 'play' ? [turn] : const [];

  int get totalBooks => books.fold(0, (a, b) => a + b.length);

  @override
  void start() {
    final deck = shuffled(fmDeck(), rng);
    final n = players <= 3 ? 7 : 5;
    hands = [for (var s = 0; s < players; s++) deck.sublist(s * n, (s + 1) * n)..sort(fmByRank)];
    pond = deck.sublist(players * n);
    books = List.generate(players, (_) => <String>[]);
    known = List.generate(players, (_) => <String, int>{});
    lacks = List.generate(players, (_) => <String, int>{});
    host.log('钓鱼开始：每人 $n 张，池塘 ${pond.length} 张');
    for (var s = 0; s < players; s++) {
      _checkBooks(s);
    }
    turn = 0;
    _beginTurn();
  }

  void _draw(int s) {
    final c = pond.removeLast();
    hands[s]
      ..add(c)
      ..sort(fmByRank);
    lacks[s].clear(); // an unknown card joined the hand
  }

  /// Lays down any four-of-a-kind in seat [s]'s hand. Returns the ranks booked.
  List<String> _checkBooks(int s) {
    final out = <String>[];
    for (final r in fmRanks.split('')) {
      if (hands[s].where((c) => fmRank(c) == r).length == 4) {
        hands[s].removeWhere((c) => fmRank(c) == r);
        books[s].add(r);
        out.add(r);
        for (var o = 0; o < players; o++) {
          known[o].remove(r);
          lacks[o][r] = asks;
        }
        host.log('${name(s)} 凑齐四张 ${fmRankName(r)}，成书！');
      }
    }
    return out;
  }

  void _addLog(Map<String, dynamic> e) {
    log.add(e);
    if (log.length > 30) log.removeAt(0);
  }

  int _next(int s) => (s + 1) % players;

  bool _hasTarget(int s) => [for (var o = 0; o < players; o++) if (o != s && o != resigned && hands[o].isNotEmpty) o].isNotEmpty;

  /// Advances automatic steps (empty hands draw / skip) until [turn] can ask.
  void _beginTurn() {
    for (var guard = 0; guard < 500; guard++) {
      if (totalBooks >= 13) {
        _finish();
        return;
      }
      if (turn == resigned) {
        turn = _next(turn);
        continue;
      }
      if (hands[turn].isEmpty) {
        if (pond.isEmpty) {
          turn = _next(turn);
          continue;
        }
        _draw(turn);
        _addLog({'type': 'refill', 'seat': turn});
        _checkBooks(turn);
        if (hands[turn].isEmpty) continue;
      }
      if (!_hasTarget(turn)) {
        if (pond.isEmpty) {
          turn = _next(turn);
          continue;
        }
        _draw(turn);
        final b = _checkBooks(turn);
        _addLog({'type': 'solo', 'seat': turn, 'book': b.isEmpty ? null : b.first});
        turn = _next(turn);
        continue;
      }
      return;
    }
    _finish();
  }

  void _finish() {
    phase = 'over';
    final best = books.map((b) => b.length).reduce((a, b) => a > b ? a : b);
    final w = [for (var s = 0; s < players; s++) if (books[s].length == best && s != resigned) name(s)];
    host.log('游戏结束：${w.join('、')} 以 $best 本书获胜');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (a['type'] != 'ask') throw GameError('未知操作');
    final t = asInt(a['target']);
    final r = asStr(a['rank']);
    if (t < 0 || t >= players || t == seat || t == resigned) throw GameError('请选择要问的玩家');
    if (hands[t].isEmpty) throw GameError('${name(t)} 没有手牌了');
    if (r.length != 1 || !fmRanks.contains(r)) throw GameError('请选择点数');
    if (!hands[seat].any((c) => fmRank(c) == r)) throw GameError('只能要自己手里有的点数');
    asks++;
    known[seat][r] = asks;
    lacks[seat].remove(r);
    final got = hands[t].where((c) => fmRank(c) == r).toList();
    final entry = <String, dynamic>{'type': 'ask', 'seat': seat, 'target': t, 'rank': r, 'got': got.length};
    var again = false;
    if (got.isNotEmpty) {
      hands[t].removeWhere((c) => fmRank(c) == r);
      hands[seat]
        ..addAll(got)
        ..sort(fmByRank);
      known[t].remove(r);
      lacks[t][r] = asks;
      again = true;
      host.log('${name(seat)} 向 ${name(t)} 要 ${fmRankName(r)}：给了 ${got.length} 张');
    } else {
      lacks[t][r] = asks;
      if (pond.isEmpty) {
        entry['fish'] = 'empty';
        host.log('${name(seat)} 向 ${name(t)} 要 ${fmRankName(r)}：没有，池塘已空');
      } else {
        final c = pond.last;
        _draw(seat);
        final lucky = fmRank(c) == r;
        entry['fish'] = lucky ? 'lucky' : 'miss';
        if (lucky) {
          known[seat][r] = asks;
          again = true;
        }
        host.log('${name(seat)} 向 ${name(t)} 要 ${fmRankName(r)}：去钓鱼${lucky ? '，钓到了 ${fmRankName(r)}，再来一次！' : ''}');
      }
    }
    final b = _checkBooks(seat);
    if (b.isNotEmpty) entry['book'] = b.first;
    entry['again'] = again;
    _addLog(entry);
    if (!again) turn = _next(seat);
    _beginTurn();
  }

  @override
  bool get canResign => phase == 'play';

  @override
  void resign(int seat) {
    if (phase != 'play' || seat < 0 || seat >= players || resigned >= 0) return;
    resigned = seat;
    host.log('${name(seat)} 认输');
    phase = 'over';
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    final sc = [for (var s = 0; s < players; s++) s == resigned ? -1 : books[s].length];
    return rankByScore(sc);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final over = phase == 'over';
    return {
      'phase': phase,
      'turn': turn,
      'counts': [for (final h in hands) h.length],
      'books': books,
      'pond': pond.length,
      'hand': seat >= 0 ? hands[seat] : const <String>[],
      'hands': over ? hands : null,
      'log': log.length > 12 ? log.sublist(log.length - 12) : log,
      'resigned': resigned,
      'result': over ? {'placings': placings} : null,
    };
  }

  // ---------------------------------------------------------------------------
  // Bot: uses only its own hand + public knowledge (asks, transfers, books).
  // ---------------------------------------------------------------------------
  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    final hand = hands[seat];
    if (hand.isEmpty) return null;
    final targets = [for (var o = 0; o < players; o++) if (o != seat && o != resigned && hands[o].isNotEmpty) o];
    if (targets.isEmpty) return null;
    final cnt = <String, int>{};
    for (final c in hand) {
      cnt[fmRank(c)] = (cnt[fmRank(c)] ?? 0) + 1;
    }
    final ranks = cnt.keys.toList();
    if (botLevel == 0) {
      return {'type': 'ask', 'target': targets[rng.nextInt(targets.length)], 'rank': ranks[rng.nextInt(ranks.length)]};
    }
    // memory window: 普通 remembers the last few asks, 困难 everything
    final window = botLevel >= 2 ? 1 << 30 : players * 2;
    bool fresh(int when) => asks - when < window;
    // 1. someone is known to hold a rank I have
    String? bestR;
    int bestT = -1;
    var bestScore = -1;
    for (final r in ranks) {
      for (final o in targets) {
        final k = known[o][r];
        if (k != null && fresh(k)) {
          final sc = cnt[r]! * 10 + hands[o].length;
          if (sc > bestScore) {
            bestScore = sc;
            bestR = r;
            bestT = o;
          }
        }
      }
    }
    if (bestR != null && (botLevel >= 2 || rng.nextDouble() < 0.85)) {
      return {'type': 'ask', 'target': bestT, 'rank': bestR};
    }
    // 2. ask for my most plentiful rank from someone not known to lack it
    ranks.sort((a, b) => cnt[b]! - cnt[a]!);
    final top = cnt[ranks.first]!;
    final pool = [for (final r in ranks) if (cnt[r] == top) r];
    final r = pool[rng.nextInt(pool.length)];
    final ok = [
      for (final o in targets)
        if (!(lacks[o][r] != null && fresh(lacks[o][r]!))) o
    ];
    final cand = ok.isEmpty ? targets : ok;
    cand.sort((a, b) => hands[b].length - hands[a].length);
    final pick = botLevel >= 2 ? cand.first : cand[rng.nextInt(cand.length)];
    return {'type': 'ask', 'target': pick, 'rank': r};
  }
}
