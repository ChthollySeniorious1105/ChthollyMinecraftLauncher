import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:aurora_shared/aurora_shared.dart';

class DailyChallenges {
  final File? file;
  final String salt;
  final Map<String, DailyPuzzle> active = {};
  final Map<String, Map<String, dynamic>> records = {};
  String _activeDay = '';
  DailyChallenges(Directory? dir, this.salt)
    : file = dir == null ? null : File('${dir.path}/daily.json') {
    if (file?.existsSync() == true) {
      try {
        final j = jsonDecode(file!.readAsStringSync()) as Map;
        for (final e in j.entries) {
          records['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
        }
      } catch (_) {}
    }
  }
  String get day => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  void _rollover() {
    if (_activeDay == day) return;
    _activeDay = day;
    active.clear();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);
    records.removeWhere((_, v) => '${v['day']}'.compareTo(cutoff) < 0);
  }

  void start(String pid, String kind) {
    _rollover();
    if (pid.isEmpty || !dailyKinds.containsKey(kind))
      throw GameError('请使用有效玩家身份选择挑战');
    if (active.length >= 2000 && !active.containsKey(pid))
      throw GameError('挑战人数已满，请稍后再试');
    // Keep an unfinished attempt when opening the same challenge again.
    final p = active[pid];
    if (p != null && p.kind == kind && !p.done) return;
    final digest = sha256
        .convert(utf8.encode('$salt|daily-v1|$day|$kind'))
        .bytes;
    final seed =
        digest.take(4).fold<int>(0, (v, b) => (v << 8) | b) & 0x7fffffff;
    active[pid] = DailyPuzzle(kind, seed);
  }

  void act(String pid, String name, int avatar, Map<String, dynamic> a) {
    _rollover();
    final p = active[pid];
    if (p == null) throw GameError('请先选择今日挑战');
    p.act(a);
    if (!p.done) return;
    final key = '$day|${p.kind}|$pid', old = records[key];
    if (old == null ||
        p.score > asInt(old['score']) ||
        p.score == asInt(old['score']) && p.moves < asInt(old['moves'])) {
      records[key] = {
        'day': day,
        'kind': p.kind,
        'pid': pid,
        'name': name,
        'avatar': avatar,
        'score': p.score,
        'moves': p.moves,
        'won': p.won,
      };
      final f = file;
      if (f != null) {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(jsonEncode(records));
      }
    }
  }

  Map<String, dynamic> snapshot(String pid) {
    _rollover();
    return {
      't': Msg.dailyState,
      'day': day,
      'active': active[pid]?.view(),
      'kinds': dailyKinds,
      'boards': {for (final kind in dailyKinds.keys) kind: _board(kind)},
      'mine': [
        for (final r in records.values)
          if (r['day'] == day && r['pid'] == pid) r,
      ],
    };
  }

  List<Map<String, dynamic>> _board(String kind) {
    final rows =
        records.values
            .where((r) => r['day'] == day && r['kind'] == kind)
            .toList()
          ..sort((a, b) {
            final c = asInt(b['score']).compareTo(asInt(a['score']));
            return c != 0 ? c : asInt(a['moves']).compareTo(asInt(b['moves']));
          });
    return rows.take(20).toList();
  }
}
