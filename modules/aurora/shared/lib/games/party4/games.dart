import '../../src/engine.dart';

typedef QuizQuestion = (String, List<String>, int, String, String);
const quizBank = <QuizQuestion>[
  (
    '合成工作台需要几个木板？',
    ['2 个', '4 个', '6 个', '8 个'],
    1,
    '用四个木板填满 2×2 合成格。',
    'minecraft',
  ),
  ('哪种工具最适合挖掘石头？', ['镐', '锄', '剪刀', '钓鱼竿'], 0, '镐用于开采石头与矿石。', 'minecraft'),
  (
    '苦力怕最有名的攻击方式是什么？',
    ['射箭', '爆炸', '喷火', '扔雪球'],
    1,
    '苦力怕接近玩家后会引爆。',
    'minecraft',
  ),
  ('哪种物品可以用来给羊染色？', ['沙子', '煤炭', '染料', '石头'], 2, '染料可以改变羊毛的颜色。', 'minecraft'),
  (
    '想设置重生点，主世界通常使用什么？',
    ['床', '箱子', '熔炉', '栅栏'],
    0,
    '在主世界使用床可以设置重生点。',
    'minecraft',
  ),
  ('红石粉最常用于什么？', ['烹饪', '电路', '染皮革', '驯马'], 1, '红石粉能够传递红石信号。', 'minecraft'),
  (
    '制作下界传送门框架使用哪种方块？',
    ['泥土', '玻璃', '黑曜石', '沙砾'],
    2,
    '黑曜石构成传送门的框架。',
    'minecraft',
  ),
  ('哪种生物会掉落末影珍珠？', ['鸡', '末影人', '猪', '蜜蜂'], 1, '击败末影人有机会获得末影珍珠。', 'minecraft'),
  (
    '熔炉可以把铁矿石烧炼成什么？',
    ['铁锭', '钻石', '红石', '木炭'],
    0,
    '铁矿石经过烧炼可以得到铁锭。',
    'minecraft',
  ),
  ('哪种物品能吸引并繁殖牛？', ['小麦', '骨头', '煤', '火药'], 0, '牛会跟随手持小麦的玩家。', 'minecraft'),
  (
    '雪傀儡的身体由哪种方块组成？',
    ['两个雪块', '两个铁块', '两个石块', '两个木板'],
    0,
    '雪傀儡需要两个雪块和雕刻南瓜。',
    'minecraft',
  ),
  (
    '哪种容器能让同一玩家在不同地点访问同一份物品？',
    ['木桶', '漏斗', '末影箱', '发射器'],
    2,
    '末影箱的物品栏属于玩家本人。',
    'minecraft',
  ),
  ('一天通常有多少小时？', ['12', '24', '36', '48'], 1, '一天通常按 24 小时计算。', 'general'),
  ('三角形有几条边？', ['2', '3', '4', '5'], 1, '三角形由三条边围成。', 'general'),
  ('太阳系中我们生活在哪颗行星？', ['火星', '地球', '金星', '木星'], 1, '地球是我们的家园。', 'general'),
  (
    '“一石二鸟”通常形容什么？',
    ['一次实现两个目的', '两只鸟打架', '搬运石头', '飞行很快'],
    0,
    '比喻做一件事同时达到两个目的。',
    'general',
  ),
  (
    '二进制中 10 表示十进制的几？',
    ['1', '2', '10', '20'],
    1,
    '二进制 10 = 1×2 + 0。',
    'general',
  ),
  (
    '哪种颜色由蓝色和黄色颜料混合得到？',
    ['绿色', '紫色', '橙色', '黑色'],
    0,
    '常见颜料中蓝色与黄色混合可得到绿色。',
    'general',
  ),
  ('地球的天然卫星是什么？', ['太阳', '月球', '火星', '金星'], 1, '月球是地球的天然卫星。', 'general'),
  ('一个正方体有几个面？', ['4', '5', '6', '8'], 2, '正方体有六个正方形面。', 'general'),
  ('汉字“森”由几个“木”组成？', ['1', '2', '3', '4'], 2, '“森”由三个“木”组成。', 'general'),
  (
    '一公斤等于多少克？',
    ['10', '100', '1000', '10000'],
    2,
    '一公斤就是一千克，等于 1000 克。',
    'general',
  ),
  ('哪种动物属于哺乳动物？', ['鲸', '鲨鱼', '金鱼', '蝴蝶'], 0, '鲸生活在水中，但属于哺乳动物。', 'general'),
  (
    '“春眠不觉晓”的下一句是什么？',
    ['处处闻啼鸟', '举头望明月', '白日依山尽', '千山鸟飞绝'],
    0,
    '这句出自孟浩然《春晓》。',
    'general',
  ),
];

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

class QuizParty extends RoundParty {
  QuizParty(super.setup);
  late final questions =
      (quizBank
          .where(
            (q) =>
                setup.opt<String>('topic', 'all') != 'minecraft' ||
                q.$5 == 'minecraft',
          )
          .toList()
        ..shuffle(rng));
  final Map<int, int> answers = {};
  QuizQuestion get q =>
      questions[round.clamp(0, rounds - 1) % questions.length];
  @override
  void prepare() {
    answers.clear();
    if (setup.bots.any((b) => !b)) {
      final r = round;
      host.schedule(45000, () {
        if (round == r && !done && !reveal) {
          submitted.addAll(List.generate(players, (i) => i));
          reveal = true;
        }
      });
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (advance(seat, a)) return;
    final answer = asInt(a['answer']);
    if (answer < 0 || answer >= 4) throw GameError('请选择一个答案');
    answers[seat] = answer;
    if (answer == q.$3) scores[seat] += 10;
    submit(seat);
  }

  @override
  List<int>? get placings {
    if (!done) return null;
    if (!setup.opt<bool>('teams', false)) return rankByScore(scores);
    final teams = [
      for (var t = 0; t < 2; t++)
        [for (var s = t; s < players; s += 2) scores[s]],
    ];
    final avg = [
      for (final t in teams) t.fold<int>(0, (a, b) => a + b) * 100 ~/ t.length,
    ];
    return rankByScore([for (var s = 0; s < players; s++) avg[s % 2]]);
  }

  @override
  Map<String, dynamic> view(int seat) => {
    ...common(seat),
    'question': q.$1,
    'choices': q.$2,
    'scores': reveal || done ? scores : null,
    'teamMode': setup.opt<bool>('teams', false),
    'answer': reveal || done ? q.$3 : null,
    'explanation': reveal || done ? q.$4 : '',
    'mine': answers[seat],
    if (reveal || done)
      'answers': {for (final a in answers.entries) '${a.key}': a.value},
  };
  @override
  Map<String, dynamic>? bot(int seat) => reveal
      ? {'continue': true}
      : {
          'answer': rng.nextInt(100) < [45, 70, 90][botLevel.clamp(0, 2)]
              ? q.$3
              : rng.nextInt(4),
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

class EscapeHouse extends GameEngine {
  EscapeHouse(super.setup);
  int stage = 0, mistakes = 0;
  late final rooms = setup.opt<int>('rooms', 3);
  final Set<int> inspected = {};
  final List<String> inventory = [];
  late int left, right;
  late List<int> choices;
  static const names = ['极光天文台', '玻璃温室', '齿轮工坊', '潮汐图书馆', '星光出口'];
  static const items = ['调查壁画', '打开笔记', '检查锁盒'];
  @override
  void start() => _prepare();
  void _prepare() {
    inspected.clear();
    left = 2 + rng.nextInt(8);
    right = 2 + rng.nextInt(8);
    final answer = left * right + stage;
    choices = [answer, answer + 1, answer + 3, answer + 5]..shuffle(rng);
  }

  @override
  bool get isOver => stage == rooms || mistakes >= 6;
  @override
  List<int>? get placings =>
      isOver ? List.filled(players, stage == rooms ? 1 : 2) : null;
  @override
  List<int> get waitingFor => isOver ? [] : List.generate(players, (i) => i);
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (!waitingFor.contains(seat)) throw GameError('当前不能操作');
    if (a['type'] == 'inspect') {
      final i = asInt(a['item']);
      if (i < 0 || i > 2 || inspected.contains(i)) throw GameError('这条线索已经收集');
      inspected.add(i);
      host.log('${name(seat)} 找到一条线索');
      return;
    }
    if (inspected.length != 3) throw GameError('请先调查三个物品，收齐线索');
    final i = asInt(a['choice']);
    if (i < 0 || i >= choices.length) throw GameError('请选择密码');
    if (choices[i] != left * right + stage) {
      mistakes++;
      return;
    }
    inventory.add('${names[stage]}钥匙');
    stage++;
    if (!isOver) _prepare();
  }

  @override
  Map<String, dynamic> view(int seat) => {
    'stage': stage + 1,
    'rooms': rooms,
    'title': stage == rooms ? '重见极光' : names[stage],
    'inspected': inspected.toList(),
    'clues': [
      inspected.contains(0) ? '壁画：$left 排星星，每排 $right 颗。' : '壁画上的星星藏着第一个数字。',
      inspected.contains(1) ? '笔记：用星星总数加上 $stage。' : '笔记中记录了计算方法。',
      inspected.contains(2) ? '锁盒：选中计算出的密码，即可取出门钥匙。' : '锁盒里似乎有一把钥匙。',
    ],
    'choices': inspected.length == 3 ? choices : [],
    'inventory': inventory,
    'mistakes': mistakes,
    'done': isOver,
    'won': stage == rooms,
  };
  @override
  Map<String, dynamic>? bot(int seat) => inspected.length < 3
      ? {
          'type': 'inspect',
          'item': [0, 1, 2].firstWhere((i) => !inspected.contains(i)),
        }
      : {'type': 'solve', 'choice': choices.indexOf(left * right + stage)};
}
