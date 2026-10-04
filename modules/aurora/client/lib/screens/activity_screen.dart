import '../i18n/aurora_i18n.dart';

import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../games/boards.dart';
import '../main.dart';
import '../net/connection.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const AuroraText('挑战与新手练习')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.today),
              title: const AuroraText('每日挑战'),
              subtitle: const AuroraText('每日数独、扫雷、2048 与熄灯 · 同服同题 · 个人最好成绩'),
              trailing: const Icon(Icons.chevron_right),
              onTap: app.state == ConnState.connected
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DailyScreen()),
                    )
                  : null,
            ),
          ),
          if (app.state != ConnState.connected)
            const Padding(
              padding: EdgeInsets.all(12),
              child: AuroraText('连接服务器后可参加每日挑战；下方新手练习可以离线使用。'),
            ),
          const SizedBox(height: 12),
          Text('互动新手练习', style: Theme.of(context).textTheme.titleLarge),
          const AuroraText('用真实棋盘完成指定操作，再自由练习。练习不会计入联机排名。'),
          for (final id in const [
            'tictactoe',
            'connect4',
            'gomoku',
            'memorypairs',
            'lightsout',
            'quizparty',
          ])
            Card(
              child: ListTile(
                leading: const Icon(Icons.school),
                title: Text(auroraGameText(findGame(id)!.name)),
                subtitle: const AuroraText('分步提示 · 合法操作 · 可反复练习'),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TutorialScreen(game: id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});
  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  int cell = -1;
  bool flag = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).send({'t': Msg.daily});
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), data = app.dailyState;
    final p = data?['active'] as Map?;
    final kind = '${p?['kind'] ?? ''}';
    final online = app.state == ConnState.connected;
    void act(Map<String, dynamic> a) {
      if (p != null && online) {
        app.send({
          't': Msg.dailyAction,
          'a': {...a, 'revision': p['moves']},
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const AuroraText('每日挑战'),
        actions: [
          IconButton(
            onPressed: online ? () => app.send({'t': Msg.daily}) : null,
            tooltip: auroraT('刷新成绩'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('题目日期：${data?['day'] ?? '加载中'}（UTC）· 每日换题 · 每种挑战保留最好成绩'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in dailyKinds.entries)
                FilledButton.tonal(
                  onPressed: online
                      ? () {
                          setState(() => cell = -1);
                          app.send({'t': Msg.dailyStart, 'kind': e.key});
                        }
                      : null,
                  child: Text(e.value),
                ),
            ],
          ),
          if (!online)
            const Padding(
              padding: EdgeInsets.all(12),
              child: AuroraText('连接已断开，恢复后可继续。'),
            ),
          if (p != null) ...[
            const SizedBox(height: 16),
            Text(
              '${dailyKinds[kind]} · ${p['moves']} 步 · ${p['score']} 分${kind == 'sudoku' ? ' · 失误 ${p['mistakes']}/5' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (p['done'] == true)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    p['won'] == true
                        ? '挑战成功！成绩已提交，可选择同一项目再次练习。'
                        : '本次挑战结束，成绩已提交。可重新练习。',
                  ),
                ),
              ),
            if (kind == 'mines')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const AuroraText('标记模式（点击插旗 / 取消）'),
                value: flag,
                onChanged: (v) => setState(() => flag = v),
              ),
            if (kind == 'sudoku')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AuroraText('先点空格，再点数字；填对的格子会锁定。'),
              ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _grid(context, p, online, act),
              ),
            ),
            const SizedBox(height: 12),
            if (kind == 'sudoku')
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (var d = 1; d <= 9; d++)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: cell >= 0 && p['done'] != true && online
                          ? () => act({'cell': cell, 'digit': d})
                          : null,
                      child: AuroraText('$d'),
                    ),
                ],
              ),
            if (kind == '2048')
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final e in const {
                    'up': '↑ 上',
                    'left': '← 左',
                    'down': '↓ 下',
                    'right': '→ 右',
                  }.entries)
                    FilledButton(
                      onPressed: p['done'] != true && online
                          ? () => act({'dir': e.key})
                          : null,
                      child: Text(e.value),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            const AuroraText('今日排行榜（得分相同则步数更少者优先）'),
            for (final row in ((data?['boards'] as Map?)?[kind] as List? ?? []))
              ListTile(
                dense: true,
                title: Text('${row['name']}'),
                trailing: Text('${row['score']} 分 · ${row['moves']} 步'),
              ),
            const SizedBox(height: 8),
            const Text(
              '每次最多 500 步。切换挑战会替换当前进度；浏览器刷新或短暂断线后可重新选择同一项目继续。',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (p == null && data != null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: AuroraText('选择一项挑战开始。所有设备使用相同规则与题目。'),
            ),
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    Map p,
    bool online,
    void Function(Map<String, dynamic>) act,
  ) {
    final b = p['board'] as List, kind = '${p['kind']}';
    final n = kind == 'sudoku'
        ? 9
        : kind == 'mines'
        ? 6
        : 4;
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: b.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: n,
        mainAxisSpacing: n == 9 ? 2 : 5,
        crossAxisSpacing: n == 9 ? 2 : 5,
      ),
      itemBuilder: (context, i) {
        final value = b[i] as int;
        final flagged = (p['flagged'] as List).contains(i);
        final label = kind == 'mines'
            ? (flagged
                  ? '旗'
                  : value == -2
                  ? '雷'
                  : value == -1
                  ? '?'
                  : value == 0
                  ? '·'
                  : '$value')
            : kind == 'lights'
            ? value == 1
                  ? '亮'
                  : '灭'
            : value == 0
            ? ''
            : '$value';
        final can =
            p['done'] != true &&
            online &&
            kind != '2048' &&
            (kind != 'sudoku' || value == 0);
        return Semantics(
          label:
              '第 ${i ~/ n + 1} 行，第 ${i % n + 1} 列，${label.isEmpty ? '空格' : label}',
          button: can,
          child: Material(
            color: cell == i && kind == 'sudoku'
                ? cs.primaryContainer
                : kind == 'lights' && value == 1
                ? cs.tertiaryContainer
                : cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: kind == 'sudoku' && (i % 3 == 0 || i ~/ 9 % 3 == 0)
                    ? cs.outline
                    : Colors.transparent,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: !can
                  ? null
                  : () {
                      if (kind == 'sudoku') {
                        setState(() => cell = i);
                      } else {
                        act({'cell': i, 'flag': flag});
                      }
                    },
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: n == 9 ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TutorialScreen extends StatefulWidget {
  final String game;
  const TutorialScreen({super.key, required this.game});
  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late GameEngine engine;
  late GameDef def;
  int steps = 0;
  Map<String, dynamic>? suggested;
  bool guided = true;
  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    def = findGame(widget.game)!;
    final n = def.defaultOptionsRange().$1;
    engine = def.create(
      GameSetup(
        players: n,
        options: def.defaultOptions(),
        names: List.generate(n, (i) => '练习席位 ${i + 1}'),
        bots: List.filled(n, true),
        rng: Random(17),
        botRng: Random(31),
      ),
    );
    engine.start();
    steps = 0;
    guided = true;
    _hint();
  }

  void _hint() {
    suggested = engine.waitingFor.isEmpty
        ? null
        : engine.runBot(engine.waitingFor.first);
  }

  void _act(Map<String, dynamic> a) {
    if (engine.waitingFor.isEmpty) return;
    if (guided &&
        suggested != null &&
        suggested!.entries.any((e) => a[e.key] != e.value)) {
      AppScope.read(context).toast('请先完成提示中的操作；也可切换为自由练习。');
      return;
    }
    try {
      engine.handle(engine.waitingFor.first, a);
      setState(() {
        steps++;
        if (steps >= 5) guided = false;
        _hint();
      });
    } on GameError catch (e) {
      AppScope.read(context).toast(e.message);
    }
  }

  String get hint {
    final a = suggested;
    if (engine.isOver) return '练习完成！可以重新开始巩固规则。';
    if (!guided || a == null) return '已经掌握基本操作，现在可以自由练习；轮流控制各练习席位。';
    if (a['continue'] == true) return '观察结果，然后点击“继续”。';
    final cell = a['cell'] ?? a['point'];
    if (cell is int) {
      if (widget.game == 'memorypairs') {
        return '从左到右、从上到下，点击第 ${cell + 1} 张牌。记住已翻开的图案，寻找相同的一对。';
      }
      final v = engine.view(engine.waitingFor.first);
      final n = widget.game == 'tictactoe'
          ? 3
          : widget.game == 'gomoku'
          ? (v['size'] as int? ?? 15)
          : (v['size'] as int? ?? 3);
      return '点击第 ${cell ~/ n + 1} 行、第 ${cell % n + 1} 列的格子。${widget.game == 'lightsout' ? '观察相邻灯如何一起改变。' : ''}';
    }
    if (a['col'] is int) return '点击第 ${(a['col'] as int) + 1} 列，观察棋子落到底部。';
    if (a['answer'] is int) {
      return '阅读题目，再点击选项 ${String.fromCharCode(65 + (a['answer'] as int))}。';
    }
    return '按照提示完成操作：$a';
  }

  @override
  Widget build(BuildContext context) {
    final seat = engine.waitingFor.firstOrNull ?? 0;
    final state = GameState(
      def.id,
      seat,
      engine.setup.names,
      engine.setup.bots,
      List.filled(engine.players, 0),
      engine.view(seat),
      engine.isOver,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${auroraT('新手练习')} · ${auroraGameText(def.name)}'),
        actions: [
          IconButton(
            onPressed: () => setState(_restart),
            tooltip: auroraT('重新开始'),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuroraText('第 ${min(steps + 1, 5)}/5 步 · $hint'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (guided)
                        TextButton(
                          onPressed: () => setState(() => guided = false),
                          child: const AuroraText('自由练习'),
                        ),
                      TextButton(
                        onPressed: suggested == null
                            ? null
                            : () => _act(Map.of(suggested!)),
                        child: const AuroraText('演示这一步'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: buildBoard(
              GameContext(
                AppScope.of(context),
                state,
                optionsOverride: engine.setup.options,
                actionOverride: _act,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
