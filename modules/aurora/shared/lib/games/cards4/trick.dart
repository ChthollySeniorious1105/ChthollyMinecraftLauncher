import '../../src/engine.dart';
import 'cards.dart';

/// Trick-flow core shared by 够级 / 保皇 / 双扣.
///
/// After every play the engine builds a *response queue* ([responders]): the
/// seats that may still answer the current table. A pass pops the queue; a
/// successful play replaces the table and rebuilds the queue. When the queue
/// is empty the table owner wins the trick and leads (or, if they went out,
/// [leaderAfter] decides who does — 接风).
abstract class C4Trick extends GameEngine {
  C4Trick(super.setup);

  late List<List<String>> hands;
  late List<Map<String, dynamic>?> acts;
  List<String> tableCards = [];
  Map<String, dynamic>? tableInfo; // combo json of the current table
  int tableSeat = -1;
  List<int> queue = [];
  int turn = 0;
  List<int> finish = [];
  int plays = 0; // plays this round (for the UI)

  bool active(int s) => hands[s].isNotEmpty;
  int get activeCount => hands.where((h) => h.isNotEmpty).length;
  bool get leading => tableSeat < 0;

  int nextActive(int s) {
    for (var i = 1; i <= players; i++) {
      final t = (s + i) % players;
      if (active(t)) return t;
    }
    return s;
  }

  /// Seats (in answer order) that may respond to [seat]'s play.
  List<int> responders(int seat) => [
        for (var i = 1; i < players; i++)
          if (active((seat + i) % players)) (seat + i) % players,
      ];

  /// Who leads after [winner] took a trick.
  int leaderAfter(int winner) => active(winner) ? winner : nextActive(winner);

  /// Validates [cards] as a play by [seat] against the table and returns the
  /// combo json (must contain 'label'). Throws [GameError] when illegal.
  Map<String, dynamic> checkPlay(int seat, List<String> cards);

  bool get roundDone;
  void endRound();

  /// Hooks.
  void onPlay(int seat, List<String> cards, Map<String, dynamic> info) {}
  void onPass(int seat) {}
  void onTrickWon(int seat) {}
  void onFinish(int seat) {}

  void resetTrick() {
    acts = List.filled(players, null);
    tableCards = [];
    tableInfo = null;
    tableSeat = -1;
    queue = [];
  }

  void handlePlay(int seat, Map<String, dynamic> a) {
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'pass') {
      if (leading) throw GameError('你是首家，必须出牌');
      acts[seat] = {'pass': true};
      if (queue.isNotEmpty && queue.first == seat) queue.removeAt(0);
      onPass(seat);
      _advance();
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final hand = hands[seat];
    final cards = c4Take(a['cards'], hand);
    final info = checkPlay(seat, cards);
    c4Remove(hand, cards);
    c4Sort(cards);
    tableCards = cards;
    tableInfo = info;
    tableSeat = seat;
    plays++;
    acts[seat] = {'cards': cards, 'label': info['label']};
    onPlay(seat, cards, info);
    if (hand.isEmpty) {
      finish.add(seat);
      host.log('${name(seat)} 出完了（第${finish.length}名）');
      onFinish(seat);
      if (roundDone) {
        endRound();
        return;
      }
    }
    queue = responders(seat);
    _advance();
  }

  void _advance() {
    queue.removeWhere((s) => !active(s) || s == tableSeat);
    if (queue.isEmpty) {
      final w = tableSeat;
      onTrickWon(w);
      final lead = leaderAfter(w);
      resetTrick();
      turn = lead;
    } else {
      turn = queue.first;
    }
  }

  Map<String, dynamic> trickView(int seat) => {
        'turn': turn,
        'lead': leading,
        'hand': seat >= 0 && seat < players ? hands[seat] : <String>[],
        'counts': [for (final h in hands) h.length],
        'acts': acts,
        'table': tableInfo,
        'tableCards': tableCards,
        'tableSeat': tableSeat,
        'finish': finish,
      };
}
