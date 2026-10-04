import '../../src/engine.dart';
import 'games.dart';

final List<GameDef> party4Games = [
  GameDef(
    id: 'quizparty',
    name: '知识派对',
    category: '派对',
    description: '一起回答我的世界与生活知识题，答完统一揭晓；正确率决定胜负，支持分队。',
    playerRange: (_) => (2, 12),
    create: QuizParty.new,
    options: const [
      OptionDef('rounds', '题数', [
        OptionChoice(5, '5 题'),
        OptionChoice(10, '10 题'),
      ], 5),
      OptionDef('topic', '题库', [
        OptionChoice('all', '综合知识'),
        OptionChoice('minecraft', '我的世界'),
      ], 'all'),
      OptionDef('teams', '分队', [
        OptionChoice(false, '个人赛'),
        OptionChoice(true, '单双座位分队'),
      ], false),
    ],
    rules:
        '# 知识派对\n- 每题有四个选项，提交后不能修改，全部答完或 45 秒后统一揭晓。\n- 答对得 10 分，答错或超时不得分，不按反应速度加分。\n- 分队时单双座位各一队，按队员平均分比较，避免人数优势。\n- 揭晓后所有玩家点击继续进入下一题。\n- 观众只能看见题面与提交进度，揭晓前看不到任何人的答案或本题得分。掉线玩家会由电脑接手。可以选择我的世界专题，也可以使用综合题库。',
  ),
  GameDef(
    id: 'memorypairs',
    name: '记忆翻翻乐',
    category: '桌游',
    description: '轮流翻开两张牌，找到相同图案即可得分并继续；考验记忆而非手速。',
    playerRange: (_) => (2, 6),
    create: MemoryPairs.new,
    options: const [
      OptionDef('pairs', '牌对数', [
        OptionChoice(8, '8 对'),
        OptionChoice(12, '12 对'),
      ], 8),
    ],
    rules:
        '# 记忆翻翻乐\n- 每回合翻两张未配对的牌。\n- 相同则得 1 分并继续，不同则确认后交给下一位。\n- 已翻过的图案可以记忆；所有牌配对后，得分最多者获胜。\n- 手机直接点击卡片，电脑使用鼠标选择。翻错时两张牌会保留到当前玩家点击继续，方便所有人记忆。牌背不会向观众或其他玩家发送真实图案。出现并列最高分时共享第一名。',
  ),
  GameDef(
    id: 'escapehouse',
    name: '极光密室',
    category: '派对',
    description: '合作探索天文台、温室与机械室，收集线索和钥匙，解开密码一起逃脱。',
    playerRange: (_) => (1, 6),
    create: EscapeHouse.new,
    options: const [
      OptionDef('rooms', '房间数', [
        OptionChoice(3, '3 间'),
        OptionChoice(5, '5 间'),
      ], 3),
    ],
    rules:
        '# 极光密室\n- 所有人共享线索与背包，点击场景中的物品进行调查。\n- 收齐三个线索后，结合算式与标记选择密码，获得下一间房的钥匙。\n- 答错累计 6 次则挑战失败；全员可以讨论并操作，没有手速要求。\n- 每间房中的数字会变化，所有线索对队友与观众公开。壁画给出排数和每排数量，笔记给出附加值。队友可以分工调查，成功后背包保存钥匙。失败后可重开一局。',
  ),
  GameDef(
    id: 'lightsout',
    name: '熄灯挑战',
    category: '棋类',
    description: '点击灯格会切换自己与上下左右的灯；所有人同一道题，率先全部熄灭获胜。',
    playerRange: (_) => (1, 6),
    create: LightsOut.new,
    options: const [
      OptionDef('size', '棋盘', [
        OptionChoice(3, '3 × 3'),
        OptionChoice(4, '4 × 4'),
      ], 3),
    ],
    rules:
        '# 熄灯挑战\n- 点击一格，切换该格与上下左右相邻灯的亮灭。\n- 每个人操作自己的棋盘，最先全部熄灭者获胜。\n- 所有题目都由合法操作生成，保证有解。可使用每日挑战练习。\n- 亮灯与灭灯都有文字标记，不依赖颜色区分。点击同一格两次会恢复原状，边角只影响实际存在的邻格。每位玩家都能看到其他人的剩余亮灯数。观众可以查看第一位玩家的棋盘，不能替玩家操作。',
  ),
  GameDef(
    id: 'wordtiles',
    name: '字词拼图',
    category: '派对',
    description: '根据中文提示重排字块，拼出成语或我的世界词语；支持撤回、跳过。',
    playerRange: (_) => (1, 8),
    create: WordTiles.new,
    options: const [
      OptionDef('rounds', '题数', [
        OptionChoice(5, '5 题'),
        OptionChoice(10, '10 题'),
      ], 5),
    ],
    rules:
        '# 字词拼图\n- 按提示依次点击字块，再提交完整答案。\n- 答对得 10 分；每次答错扣 1 分；跳过不得分。\n- 所有人完成当前题后统一揭晓，再继续下一题。\n- 点击已经选择的字块可撤回到该位置，也可用清空按钮重新排列。每个字块只能使用一次，重复汉字按不同字块处理。等待时可以看到提交进度，不能提前查看答案。手机无需弹出键盘。',
  ),
];
