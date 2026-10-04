import '../../src/engine.dart';

abstract class RoundParty extends GameEngine {
  RoundParty(super.setup);
  late final scores = List.filled(players, 0);
  final Set<int> submitted = {}, continued = {};
  int round = 0;
  bool reveal = false, done = false;
  int get rounds => setup.opt<int>('rounds', 5);
  void prepare();
  @override
  void start() => prepare();
  @override
  bool get isOver => done;
  @override
  List<int>? get placings => done ? rankByScore(scores) : null;
  @override
  List<int> get waitingFor => done
      ? []
      : [
          for (var s = 0; s < players; s++)
            if (!(reveal ? continued : submitted).contains(s)) s,
        ];
  void check(int seat) {
    if (seat < 0 || seat >= players) throw GameError('观战者不能操作');
    if (!waitingFor.contains(seat)) throw GameError('请等待其他玩家');
  }

  bool advance(int seat, Map<String, dynamic> a) {
    check(seat);
    if (!reveal) return false;
    if (a['continue'] != true) throw GameError('请点击继续');
    continued.add(seat);
    if (continued.length == players) {
      if (++round >= rounds) {
        done = true;
      } else {
        reveal = false;
        submitted.clear();
        continued.clear();
        prepare();
      }
    }
    return true;
  }

  void submit(int seat) {
    submitted.add(seat);
    if (submitted.length == players) reveal = true;
  }

  Map<String, dynamic> common(int seat) => {
    'round': round + 1,
    'rounds': rounds,
    'scores': scores,
    'reveal': reveal,
    'done': done,
    'canAct': waitingFor.contains(seat),
    'submitted': submitted.toList(),
    'ranking': placings,
  };
}

const wordBank = <(String, String)>[
  ('画龙点睛', '比喻在关键处加上一笔，让内容更加生动'),
  ('守株待兔', '比喻不主动努力，只想坐等好运'),
  ('井底之蛙', '比喻见识狭窄的人'),
  ('亡羊补牢', '出了问题及时补救，还不算晚'),
  ('锦上添花', '在美好的事物上再增加美好'),
  ('雪中送炭', '在别人困难时给予帮助'),
  ('自相矛盾', '自己的说法前后冲突'),
  ('胸有成竹', '行动前已经有完整计划'),
  ('水滴石穿', '只要坚持，小小的力量也能成功'),
  ('百折不挠', '遭受很多挫折也不屈服'),
  ('末影珍珠', '末影人掉落的可投掷传送物品'),
  ('红石火把', '红石电路中常见的一种信号源'),
  ('钻石镐', '可以开采黑曜石的钻石工具'),
  ('附魔台', '让装备获得魔法效果的方块'),
  ('铁傀儡', '村庄里的高大铁制守卫'),
  ('下界合金', '我的世界中可用于升级钻石装备的材料'),
  ('循序渐进', '按照顺序，一步一步提高'),
  ('海阔天空', '形容天地广阔，也形容讨论没有拘束'),
];

class WordTiles extends RoundParty {
  WordTiles(super.setup);
  late final words = List.of(wordBank)..shuffle(rng);
  List<String> tiles = [];
  String note = '';

  (String, String) get word => words[round.clamp(0, rounds - 1) % words.length];
  @override
  void prepare() {
    note = '';
    tiles = word.$1.split('')..shuffle(rng);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (advance(seat, a)) return;
    if (a['skip'] == true) {
      submit(seat);
      return;
    }
    final raw = a['order'];
    if (raw is! List || raw.length != tiles.length) throw GameError('请选完全部字块');
    final ids = raw.map((x) => asInt(x)).toList();
    if (ids.toSet().length != tiles.length ||
        ids.any((i) => i < 0 || i >= tiles.length))
      throw GameError('字块不能重复');
    if (ids.map((i) => tiles[i]).join() != word.$1) {
      scores[seat]--;
      note = '${name(seat)} 顺序不对，扣 1 分，请重排后提交';
      return;
    }
    scores[seat] += 10;
    submit(seat);
  }

  @override
  Map<String, dynamic> view(int seat) => {
    ...common(seat),
    'hint': word.$2,
    'note': note,
    'tiles': tiles,
    'answer': reveal || done ? word.$1 : '',
  };
  @override
  Map<String, dynamic>? bot(int seat) {
    if (reveal) return {'continue': true};
    final used = <int>{};
    return {
      'order': [
        for (final c in word.$1.split(''))
          (() {
            final i = List.generate(
              tiles.length,
              (i) => i,
            ).firstWhere((i) => !used.contains(i) && tiles[i] == c);
            used.add(i);
            return i;
          })(),
      ],
    };
  }
}

class MemoryPairs extends GameEngine {
  MemoryPairs(super.setup);
  late final int pairs = setup.opt<int>('pairs', 8);
  late final cards = [for (var i = 0; i < pairs * 2; i++) i ~/ 2]..shuffle(rng);
  late final owners = List.filled(cards.length, -1);
  late final scores = List.filled(players, 0);
  final List<int> open = [];
  final Map<int, int> seen = {};
  int turn = 0;
  bool get reveal => open.length == 2;
  @override
  void start() {
    turn = rng.nextInt(players);
  }

  @override
  bool get isOver => owners.every((i) => i >= 0);
  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;
  @override
  List<int> get waitingFor => isOver ? [] : [turn];
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (!waitingFor.contains(seat)) throw GameError('还没轮到你');
    if (reveal) {
      if (a['continue'] != true) throw GameError('请先确认翻牌结果');
      if (cards[open[0]] != cards[open[1]]) turn = (turn + 1) % players;
      open.clear();
      return;
    }
    final i = asInt(a['cell']);
    if (i < 0 || i >= cards.length || owners[i] >= 0 || open.contains(i))
      throw GameError('这张牌不能翻');
    open.add(i);
    seen[i] = cards[i];
    if (reveal && cards[open[0]] == cards[open[1]]) {
      for (final x in open) {
        owners[x] = seat;
      }
      scores[seat]++;
    }
  }

  @override
  Map<String, dynamic> view(int seat) => {
    'cards': [
      for (var i = 0; i < cards.length; i++)
        if (owners[i] >= 0 || open.contains(i) || isOver) cards[i] else -1,
    ],
    'owners': owners,
    'open': open,
    'turn': turn,
    'reveal': reveal,
    'scores': scores,
    'done': isOver,
    'ranking': placings,
  };
  @override
  Map<String, dynamic>? bot(int seat) {
    if (reveal) return {'continue': true};
    final available = [
      for (var i = 0; i < cards.length; i++)
        if (owners[i] < 0 && !open.contains(i)) i,
    ];
    if (open.isNotEmpty) {
      for (final i in available) {
        if (seen[i] == seen[open.first]) return {'cell': i};
      }
    }
    if (open.isEmpty) {
      for (final i in available) {
        if (seen.containsKey(i) &&
            available.any((j) => j != i && seen[j] == seen[i]))
          return {'cell': i};
      }
    }
    return {
      'cell':
          available.where((i) => !seen.containsKey(i)).firstOrNull ??
          available.first,
    };
  }
}

class LightsOut extends GameEngine {
  LightsOut(super.setup);
  late final n = setup.opt<int>('size', 3);
  late List<List<int>> boards;
  late final moves = List.filled(players, 0);
  int winner = -1;
  static void toggle(List<int> b, int n, int i) {
    for (final j in [
      i,
      if (i ~/ n > 0) i - n,
      if (i ~/ n < n - 1) i + n,
      if (i % n > 0) i - 1,
      if (i % n < n - 1) i + 1,
    ]) {
      b[j] = 1 - b[j];
    }
  }

  static List<int> solve(List<int> board, int n) {
    for (var mask = 0; mask < 1 << n; mask++) {
      final b = List<int>.of(board), out = <int>[];
      void flip(int i) {
        toggle(b, n, i);
        out.add(i);
      }

      for (var c = 0; c < n; c++) {
        if (mask & (1 << c) != 0) flip(c);
      }
      for (var r = 1; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if (b[(r - 1) * n + c] == 1) flip(r * n + c);
        }
      }
      if (b.every((x) => x == 0)) return out;
    }
    return [];
  }

  @override
  void start() {
    final b = List.filled(n * n, 0);
    for (var i = 0; i < n * n; i++) {
      if (rng.nextBool()) toggle(b, n, i);
    }
    if (b.every((x) => x == 0)) toggle(b, n, 0);
    boards = List.generate(players, (_) => List.of(b));
  }

  @override
  bool get isOver => winner >= 0;
  @override
  List<int> get waitingFor => isOver ? [] : List.generate(players, (i) => i);
  @override
  List<int>? get placings => isOver ? rankWinners(players, [winner]) : null;
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (!waitingFor.contains(seat)) throw GameError('当前不能操作');
    final i = asInt(a['cell']);
    if (i < 0 || i >= n * n) throw GameError('无效位置');
    toggle(boards[seat], n, i);
    moves[seat]++;
    if (boards[seat].every((x) => x == 0)) winner = seat;
  }

  @override
  Map<String, dynamic> view(int seat) => {
    'size': n,
    'board': seat < 0 ? boards.first : boards[seat],
    'moves': moves,
    'winner': winner,
    'done': isOver,
    'remaining': [for (final b in boards) b.where((x) => x == 1).length],
  };
  @override
  Map<String, dynamic>? bot(int seat) => {'cell': solve(boards[seat], n).first};
}
