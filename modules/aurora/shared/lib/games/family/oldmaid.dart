import '../../src/engine.dart';
import 'cards.dart';

/// 抽乌龟 (Old Maid).
///
/// mode 'hidden': one random card is removed face-down before the deal, so one
/// card of that rank can never be paired and becomes the 乌龟.
/// mode 'joker': a single 大王 is added to the deck as the 乌龟.
class OldMaid extends GameEngine {
  OldMaid(super.setup);

  late String mode;
  late List<List<String>> hands;
  String removed = ''; // hidden mode: the face-down card (revealed at the end)
  final List<List<String>> discards = []; // public pairs, in order
  late List<int> pairCount;
  int turn = 0;
  String phase = 'play'; // play | over
  final List<int> finishOrder = [];
  int loser = -1;
  int resigned = -1;
  Map<String, dynamic>? last; // public info about the last draw
  String lastCard = ''; // the card moved by the last draw (private to drawer/target)
  int moves = 0;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => phase == 'play' ? [turn] : const [];

  bool active(int s) => hands[s].isNotEmpty && !finishOrder.contains(s) && s != resigned;

  /// The player [s] draws from: the next active seat after [s].
  int targetOf(int s) {
    for (var k = 1; k < players; k++) {
      final t = (s + k) % players;
      if (active(t)) return t;
    }
    return -1;
  }

  @override
  void start() {
    mode = setup.opt<String>('mode', 'hidden');
    var deck = fmDeck();
    if (mode == 'joker') {
      deck.add('RJ');
      deck = shuffled(deck, rng);
    } else {
      deck = shuffled(deck, rng);
      removed = deck.removeLast();
    }
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[i % players].add(deck[i]);
    }
    pairCount = List.filled(players, 0);
    for (var s = 0; s < players; s++) {
      _discardPairs(s);
      hands[s].shuffle(rng);
    }
    host.log(mode == 'joker' ? '抽乌龟开始：大王是乌龟，各自先把成对的牌打掉' : '抽乌龟开始：已抽掉一张暗牌，与它同点的落单牌就是乌龟');
    turn = 0;
    _checkFinished(const []);
    if (phase == 'play' && !active(turn)) turn = _nextActive(turn);
  }

  int _nextActive(int s) {
    for (var k = 1; k <= players; k++) {
      final t = (s + k) % players;
      if (active(t)) return t;
    }
    return -1;
  }

  /// Removes all pairs of equal rank from seat [s]'s hand. Returns the pairs.
  List<List<String>> _discardPairs(int s) {
    final out = <List<String>>[];
    final byRank = <String, List<String>>{};
    for (final c in hands[s]) {
      if (c == 'RJ') continue;
      byRank.putIfAbsent(fmRank(c), () => []).add(c);
    }
    for (final cs in byRank.values) {
      for (var i = 0; i + 1 < cs.length; i += 2) {
        final p = [cs[i], cs[i + 1]];
        out.add(p);
        hands[s].remove(p[0]);
        hands[s].remove(p[1]);
        discards.add(p);
        pairCount[s]++;
      }
    }
    return out;
  }

  /// Seats in [order] whose hand became empty finish (in that order); ends the
  /// game when one player with cards is left.
  void _checkFinished(List<int> order) {
    for (final s in [...order, for (var i = 0; i < players; i++) i]) {
      if (hands[s].isEmpty && !finishOrder.contains(s) && s != resigned) {
        finishOrder.add(s);
        host.log('${name(s)} 的牌出完了，第 ${finishOrder.length} 名上岸');
      }
    }
    final left = [for (var s = 0; s < players; s++) if (active(s)) s];
    if (left.length <= 1) {
      loser = left.isEmpty ? -1 : left.first;
      phase = 'over';
      if (loser >= 0) host.log('${name(loser)} 手里剩下 ${fmCardName(hands[loser].first)}，成了乌龟！');
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (a['type'] != 'draw') throw GameError('未知操作');
    final t = targetOf(seat);
    if (t < 0) throw GameError('没有可抽的玩家');
    final i = asInt(a['index']);
    if (i < 0 || i >= hands[t].length) throw GameError('请选择对方的一张牌');
    final card = hands[t].removeAt(i);
    lastCard = card;
    hands[seat].add(card);
    final pairs = _discardPairs(seat);
    // the receiver hides the new card somewhere in their hand
    final h = hands[seat];
    if (h.isNotEmpty && pairs.isEmpty) {
      h.remove(card);
      h.insert(rng.nextInt(h.length + 1), card);
    }
    hands[t].shuffle(rng);
    moves++;
    last = {
      'from': seat,
      'to': t,
      'index': i,
      'pair': pairs.isEmpty ? null : pairs.first,
      'n': moves,
    };
    host.log(pairs.isEmpty
        ? '${name(seat)} 抽了 ${name(t)} 一张牌，没有配上'
        : '${name(seat)} 抽了 ${name(t)} 一张牌，配成一对 ${fmCardName(pairs.first[0])} ${fmCardName(pairs.first[1])}');
    _checkFinished([t, seat]);
    if (phase == 'play') turn = _nextActive(seat);
  }

  @override
  bool get canResign => phase == 'play';

  @override
  void resign(int seat) {
    if (phase != 'play' || seat < 0 || seat >= players) return;
    if (!active(seat)) return;
    resigned = seat;
    phase = 'over';
    host.log('${name(seat)} 认输，被判为乌龟');
  }

  @override
  List<int>? get placings {
    if (!isOver) return null;
    final p = List.filled(players, players);
    for (var k = 0; k < finishOrder.length; k++) {
      p[finishOrder[k]] = k + 1;
    }
    if (resigned >= 0) {
      // remaining players ranked by fewest cards, resigner last
      final rest = [for (var s = 0; s < players; s++) if (s != resigned && !finishOrder.contains(s)) s];
      for (final s in rest) {
        p[s] = finishOrder.length + 1 + rest.where((o) => hands[o].length < hands[s].length).length;
      }
      p[resigned] = players;
    } else if (loser >= 0) {
      p[loser] = players;
    }
    return p;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final over = phase == 'over';
    final l = last;
    final seesCard = l != null && seat >= 0 && (l['from'] == seat || l['to'] == seat);
    return {
      'phase': phase,
      'mode': mode,
      'turn': turn,
      'target': phase == 'play' ? targetOf(turn) : -1,
      'counts': [for (final h in hands) h.length],
      'pairs': pairCount,
      'hand': seat >= 0 ? hands[seat] : const <String>[],
      'hands': over ? hands : null,
      'discards': [for (final p in discards.length > 8 ? discards.sublist(discards.length - 8) : discards) p],
      'discardCount': discards.length,
      'finish': finishOrder,
      'loser': resigned >= 0 ? resigned : loser,
      'resigned': resigned,
      'removed': over ? removed : null,
      'last': l,
      'lastCard': seesCard || over ? lastCard : null,
      'result': over ? {'placings': placings} : null,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat != turn) return null;
    final t = targetOf(seat);
    if (t < 0) return null;
    // no information about the face-down cards: pick a random position
    return {'type': 'draw', 'index': rng.nextInt(hands[t].length)};
  }
}
