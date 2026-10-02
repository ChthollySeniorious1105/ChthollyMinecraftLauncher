import '../../src/engine.dart';
import 'battle2048.dart';
import 'minesweeper.dart';
import 'rules.dart';
import 'snake.dart';
import 'sudoku.dart';
import 'tetris.dart';

/// 俄罗斯方块/贪吃蛇/扫雷/2048/数独 对战
final List<GameDef> arcadeGames = [
  GameDef(
    id: 'tetrisbattle',
    name: '俄罗斯方块对战',
    category: '派对',
    description: 'TETR.IO 多人规则：SRS 旋转（含 180°）、7-bag、5 个预览、暂存。T-Spin、B2B、连击、全消送出更多垃圾；'
        '垃圾行先进入等待槽，可用消行抵消。3 分钟后垃圾倍率逐渐增加，顶到天花板出局，坚持到最后者获胜。',
    playerRange: (o) => (2, 4),
    options: const [
      OptionDef('level', '起始速度', [OptionChoice(1, '1 级'), OptionChoice(4, '4 级'), OptionChoice(8, '8 级')], 1),
      OptionDef('target', '攻击目标', [OptionChoice('random', '随机'), OptionChoice('payback', '反击（优先打最后攻击你的人）')], 'random'),
    ],
    rules: tetrisRules,
    create: TetrisBattle.new,
  ),
  GameDef(
    id: 'snakebattle',
    name: '贪吃蛇大作战',
    category: '派对',
    description: '所有蛇在同一张 30×30 地图上，吃食物变长；撞墙、撞到别的蛇或自己即出局，迎头相撞同归于尽。最后存活或时间到时最长者获胜。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('time', '时长', [OptionChoice(120, '2 分钟'), OptionChoice(180, '3 分钟'), OptionChoice(300, '5 分钟')], 180),
    ],
    rules: snakeRules,
    create: SnakeBattle.new,
  ),
  GameDef(
    id: 'minesweeper',
    name: '扫雷竞速',
    category: '派对',
    description: '所有人同一张雷图、各扫各的，首次点击必定安全。最先扫完者获胜；踩雷出局（或罚时），时间到按进度排名。',
    playerRange: (o) => (2, 6),
    options: const [
      OptionDef('level', '难度', [OptionChoice('easy', '初级 9×9'), OptionChoice('medium', '中级 16×16'), OptionChoice('hard', '高级 30×16')], 'easy'),
      OptionDef('hit', '踩雷', [OptionChoice('out', '出局'), OptionChoice('penalty', '罚时 10 秒')], 'out'),
    ],
    rules: minesweeperRules,
    create: MinesweeperRace.new,
  ),
  GameDef(
    id: 'battle2048',
    name: '2048对战',
    category: '派对',
    description: '每人一块 4×4 棋盘，出块顺序相同，各自滑动合并。合成 128 及以上给对手扔石块。全员卡死或时间到时分数最高者获胜。',
    playerRange: (o) => (2, 4),
    options: const [
      OptionDef('attack', '石块攻击', [OptionChoice(true, '开启'), OptionChoice(false, '关闭')], true),
      OptionDef('time', '时长', [OptionChoice(120, '2 分钟'), OptionChoice(180, '3 分钟'), OptionChoice(300, '5 分钟')], 180),
    ],
    rules: battle2048Rules,
    create: Battle2048.new,
  ),
  GameDef(
    id: 'sudokurace',
    name: '数独竞速',
    category: '派对',
    description: '所有人同一道唯一解数独，各填各的。填错计失误，失误过多出局；最先完成者获胜。支持笔记模式。',
    playerRange: (o) => (1, 6),
    options: const [
      OptionDef('diff', '难度', [OptionChoice('easy', '简单'), OptionChoice('medium', '中等'), OptionChoice('hard', '困难')], 'medium'),
      OptionDef('mistakes', '失误上限', [OptionChoice(3, '3 次出局'), OptionChoice(5, '5 次出局'), OptionChoice(0, '不限')], 3),
    ],
    rules: sudokuRules,
    create: SudokuRace.new,
  ),
];
