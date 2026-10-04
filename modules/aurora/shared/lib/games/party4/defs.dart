import '../../src/engine.dart';
import 'games.dart';

final List<GameDef> party4Games = [
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
        '# 熄灯挑战\n- 点击一格，切换该格与上下左右相邻灯的亮灭。\n- 每个人操作自己的棋盘，最先全部熄灭者获胜。\n- 所有题目都由合法操作生成，保证有解。\n- 亮灯与灭灯都有文字标记，不依赖颜色区分。点击同一格两次会恢复原状，边角只影响实际存在的邻格。每位玩家都能看到其他人的剩余亮灯数。观众可以查看第一位玩家的棋盘，不能替玩家操作。',
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
