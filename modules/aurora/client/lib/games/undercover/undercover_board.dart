import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _roleNames = {'civ': '平民', 'spy': '卧底', 'blank': '白板', 'gm': '出题人'};

Color _roleColor(String? r, ColorScheme cs) => switch (r) {
      'spy' => Colors.redAccent,
      'blank' => Colors.blueGrey,
      'gm' => Colors.amber.shade700,
      'civ' => Colors.green,
      _ => cs.outline,
    };

class UndercoverBoard extends StatefulWidget {
  final GameContext g;
  const UndercoverBoard(this.g, {super.key});
  @override
  State<UndercoverBoard> createState() => _UndercoverBoardState();
}

class _UndercoverBoardState extends State<UndercoverBoard> {
  bool _showWord = true;
  final _desc = TextEditingController();
  final _civ = TextEditingController();
  final _spy = TextEditingController();
  final _guess = TextEditingController();

  @override
  void dispose() {
    _desc.dispose();
    _civ.dispose();
    _spy.dispose();
    _guess.dispose();
    super.dispose();
  }

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<int> _ints(Object? o) => o is List ? [for (final e in o) (e as num).toInt()] : <int>[];

  @override
  Widget build(BuildContext context) {
    final phase = v['phase'] as String? ?? '';
    final alive = (v['alive'] as List? ?? const []).cast<bool>();
    final roles = (v['roles'] as List? ?? const []).cast<String?>();
    final gm = (v['gm'] as num?)?.toInt() ?? -1;
    final speaker = (v['speaker'] as num?)?.toInt() ?? -1;
    final guesser = (v['guesser'] as num?)?.toInt() ?? -1;
    final voted = _ints(v['voted']).toSet();
    final candidates = _ints(v['candidates']);
    final myVote = (v['myVote'] as num?)?.toInt();
    final round = (v['round'] as num?)?.toInt() ?? 0;
    final tieBreak = v['tieBreak'] == true;
    final me = g.seat;
    final iAmGm = me >= 0 && me == gm;
    final iAlive = me >= 0 && me < alive.length && alive[me];

    String status;
    var hl = false;
    switch (phase) {
      case 'gm_setup':
        status = iAmGm ? '你是出题人，请输入平民词和卧底词' : '等待出题人 ${g.name(gm)} 出题…';
        hl = iAmGm;
      case 'describe':
        hl = speaker == me;
        status = '第 $round 轮${tieBreak ? '（平票加赛）' : ''} · ${hl ? '轮到你描述了' : '${g.name(speaker)} 正在描述'}';
      case 'vote':
        final need = iAlive && myVote == null;
        hl = need;
        status = '第 $round 轮${tieBreak ? '（平票加赛）' : ''} · ${need ? '请投票选出你怀疑的卧底' : '投票中（${voted.length}/${alive.where((a) => a).length}）'}';
      case 'blank_guess':
        hl = guesser == me;
        status = hl ? '你是白板！猜出平民词即可获胜' : '白板 ${g.name(guesser)} 正在猜平民词…';
      default:
        status = _winnerText();
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final players = _playerGrid(context, alive, roles, gm, speaker, voted, candidates, myVote, phase, iAlive);
      final panel = _actionPanel(context, phase, speaker, guesser, iAmGm, iAlive);
      final top = Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 6),
        StatusBar(status, highlight: hl),
        const SizedBox(height: 6),
      ]);
      if (wide) {
        return Column(children: [
          top,
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: players)),
              SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [_wordCard(context), const SizedBox(height: 8), panel, _lastVoteCard(context), _resultCard(context)]),
                ),
              ),
            ]),
          ),
        ]);
      }
      return Column(children: [
        top,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              _wordCard(context),
              const SizedBox(height: 8),
              panel,
              _resultCard(context),
              _lastVoteCard(context),
              const SizedBox(height: 8),
              players,
            ]),
          ),
        ),
      ]);
    });
  }

  String _winnerText() => switch (v['winner']) {
        'civ' => '平民获胜！',
        'spy' => '卧底获胜！',
        'blank' => '白板获胜！',
        _ => '对局结束',
      };

  // ------------------------------------------------------------ my word

  Widget _wordCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = g.seat;
    final myRole = v['myRole'] as String?;
    final myWord = v['myWord'] as String?;
    final gm = (v['gm'] as num?)?.toInt() ?? -1;
    Widget body;
    if (me < 0) {
      body = Text('观战中', style: TextStyle(fontSize: 18, color: cs.onSurface));
    } else if (me == gm) {
      final civ = v['civWord'] as String?;
      final spy = v['spyWord'] as String?;
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('你是出题人（不参与游戏）', style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.bold)),
        if (civ != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 16, alignment: WrapAlignment.center, children: [
            _wordChip('平民词', civ, Colors.green),
            _wordChip('卧底词', spy ?? '', Colors.redAccent),
          ]),
        ],
      ]);
    } else if (myRole == 'blank') {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('你是白板', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        Text('你没有词语，听别人描述，隐藏自己！', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
      ]);
    } else if (myWord == null) {
      body = Text('等待发词…', style: TextStyle(color: cs.onSurface));
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('你的词语', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(_showWord ? myWord : '＊＊＊',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: cs.primary, letterSpacing: 4)),
        ),
        if (g.over && myRole != null)
          Text('身份：${_roleNames[myRole] ?? ''}', style: TextStyle(color: _roleColor(myRole, cs), fontWeight: FontWeight.bold)),
      ]);
    }
    final canToggle = me >= 0 && me != gm && myWord != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.6), width: 2),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Row(children: [
        Expanded(child: Center(child: body)),
        if (canToggle)
          IconButton(
            tooltip: _showWord ? '隐藏词语' : '显示词语',
            icon: Icon(_showWord ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showWord = !_showWord),
          ),
      ]),
    );
  }

  Widget _wordChip(String label, String word, Color color) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: color)),
        Text(word, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      ]);

  // ------------------------------------------------------------ actions

  Widget _actionPanel(BuildContext context, String phase, int speaker, int guesser, bool iAmGm, bool iAlive) {
    final me = g.seat;
    Widget? child;
    if (phase == 'gm_setup' && iAmGm) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _civ, maxLength: 12, decoration: const InputDecoration(labelText: '平民词', isDense: true)),
        TextField(controller: _spy, maxLength: 12, decoration: const InputDecoration(labelText: '卧底词', isDense: true)),
        const SizedBox(height: 4),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('出题并发词'),
          onPressed: () => g.act({'type': 'words', 'civ': _civ.text, 'spy': _spy.text}),
        ),
      ]);
    } else if (phase == 'describe' && speaker == me) {
      void send() {
        if (_desc.text.trim().isEmpty) return;
        g.act({'type': 'describe', 'text': _desc.text});
        _desc.clear();
      }

      child = Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _desc,
          maxLength: 40,
          autofocus: true,
          onSubmitted: (_) => send(),
          decoration: const InputDecoration(labelText: '描述你的词（不能直接说出词语）', isDense: true),
        ),
        Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          FilledButton.icon(icon: const Icon(Icons.chat_bubble), label: const Text('提交描述'), onPressed: send),
          OutlinedButton.icon(
            icon: const Icon(Icons.record_voice_over),
            label: const Text('我已口头描述'),
            onPressed: () => g.act({'type': 'verbal'}),
          ),
        ]),
      ]);
    } else if (phase == 'vote' && iAlive) {
      child = Text(v['myVote'] == null ? '点击下方玩家卡片上的「投票」按钮' : '已投票给 ${g.name((v['myVote'] as num).toInt())}，等待其他人…',
          textAlign: TextAlign.center);
    } else if (phase == 'blank_guess' && guesser == me) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _guess, maxLength: 12, decoration: const InputDecoration(labelText: '你猜的平民词', isDense: true)),
        Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton(onPressed: () => g.act({'type': 'guess', 'word': _guess.text}), child: const Text('猜词')),
          OutlinedButton(onPressed: () => g.act({'type': 'skip'}), child: const Text('放弃')),
        ]),
      ]);
    } else if (me >= 0 && !iAlive && !iAmGm && !g.over) {
      child = const Text('你已出局，可以继续观看');
    }
    if (child == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }

  // ------------------------------------------------------------ vote result / final

  Widget _lastVoteCard(BuildContext context) {
    final lv = v['lastVote'] as Map?;
    if (lv == null || v['phase'] == 'vote') return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final out = (lv['out'] as num).toInt();
    final tie = _ints(lv['tie']);
    final votes = [for (final p in (lv['votes'] as List)) _ints(p)];
    final role = lv['role'] as String?;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('第 ${lv['r']} 轮投票${lv['tb'] == true ? '（加赛）' : ''}结果', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (out >= 0)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${g.name(out)} 出局，身份：'),
            TextSpan(
                text: _roleNames[role] ?? '?',
                style: TextStyle(fontWeight: FontWeight.bold, color: _roleColor(role, cs))),
          ]))
        else
          Text('${tie.map(g.name).join('、')} 平票${lv['tb'] == true ? '，无人出局' : '，进入加赛'}'),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final p in votes)
            Text('${g.name(p[0])}→${g.name(p[1])}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.75))),
        ]),
      ]),
    );
  }

  Widget _resultCard(BuildContext context) {
    if (!g.over) return const SizedBox.shrink();
    final guess = v['guess'] as String?;
    return ResultBanner(
      _winnerText(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('平民词：${v['civWord'] ?? ''}    卧底词：${v['spyWord'] ?? ''}'),
        if (guess != null) Text('白板猜词：$guess（${v['guessOk'] == true ? '正确' : '错误'}）'),
        if (g.seat >= 0 && _ints(v['winners']).contains(g.seat))
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('你赢了！')),
      ]),
    );
  }

  // ------------------------------------------------------------ players

  Widget _playerGrid(BuildContext context, List<bool> alive, List<String?> roles, int gm, int speaker, Set<int> voted,
      List<int> candidates, int? myVote, String phase, bool iAlive) {
    final descs = [for (final d in (v['descs'] as List? ?? const [])) (d as Map).cast<String, dynamic>()];
    final words = (v['words'] as List?)?.cast<String>();
    final liveVotes = {for (final p in (v['liveVotes'] as List? ?? const [])) _ints(p)[0]: _ints(p)[1]};
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 230).floor().clamp(1, 4);
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in g.seatsFromMe())
          SizedBox(
            width: w,
            child: _playerCard(
              context,
              s,
              alive: s < alive.length && alive[s],
              role: s < roles.length ? roles[s] : null,
              isGm: s == gm,
              speaking: phase == 'describe' && s == speaker,
              voted: voted.contains(s),
              canVote: phase == 'vote' && iAlive && myVote == null && s != g.seat && candidates.contains(s),
              myVoteHere: myVote == s,
              candidate: phase == 'vote' && candidates.contains(s),
              descs: [for (final d in descs) if (d['s'] == s) d],
              word: words != null && s < words.length ? words[s] : null,
              votesFor: liveVotes.entries.where((e) => e.value == s).map((e) => e.key).toList(),
            ),
          ),
      ]);
    });
  }

  Widget _playerCard(BuildContext context, int s,
      {required bool alive,
      required String? role,
      required bool isGm,
      required bool speaking,
      required bool voted,
      required bool canVote,
      required bool myVoteHere,
      required bool candidate,
      required List<Map<String, dynamic>> descs,
      required String? word,
      required List<int> votesFor}) {
    final cs = Theme.of(context).colorScheme;
    final showRole = role != null && (isGm || !alive || g.over || s == g.seat);
    final dead = !alive && !isGm;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: dead ? 0.45 : 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: speaking ? cs.primary : (myVoteHere ? Colors.redAccent : cs.outline.withValues(alpha: 0.3)),
          width: speaking || myVoteHere ? 2.5 : 1,
        ),
        boxShadow: speaking ? [BoxShadow(color: cs.primary.withValues(alpha: 0.4), blurRadius: 10)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Avatar(g.avatar(s), size: 38, bot: g.bot(s), dim: dead, speaking: speaking),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${g.name(s)}${s == g.seat ? '（我）' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, decoration: dead ? TextDecoration.lineThrough : null)),
              Wrap(spacing: 4, runSpacing: 2, children: [
                if (isGm) _badge('出题人', Colors.amber.shade700),
                if (dead) _badge('已出局', cs.outline),
                if (showRole && !isGm) _badge(_roleNames[role] ?? '', _roleColor(role, cs)),
                if (word != null && word.isNotEmpty && !isGm) _badge(word, cs.primary),
                if (voted && alive) _badge('已投票', Colors.teal),
                if (speaking) _badge('描述中', cs.primary),
                if (votesFor.isNotEmpty) _badge('${votesFor.length} 票', Colors.redAccent),
              ]),
            ]),
          ),
          if (canVote)
            FilledButton.tonal(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 32)),
              onPressed: () => g.act({'type': 'vote', 'target': s}),
              child: const Text('投票'),
            ),
        ]),
        if (descs.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final d in descs.length > 4 ? descs.sublist(descs.length - 4) : descs)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Text('R${d['r']}${d['tb'] == true ? '加' : ''}：${d['t']}',
                  style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer)),
            ),
        ],
      ]),
    );
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.7))),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );
}
