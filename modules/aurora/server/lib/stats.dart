import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Per-player record (keyed by stable pid).
class PlayerStats {
  String name;
  int avatar;
  int games = 0;
  int wins = 0;

  /// gameId -> {p: games, w: wins, elo}
  final Map<String, Map<String, num>> per = {};
  PlayerStats(this.name, this.avatar);

  Map<String, dynamic> toJson() => {'name': name, 'avatar': avatar, 'games': games, 'wins': wins, 'per': per};

  static PlayerStats fromJson(Map<String, dynamic> j) {
    final s = PlayerStats('${j['name'] ?? ''}', (j['avatar'] as num?)?.toInt() ?? 1)
      ..games = (j['games'] as num?)?.toInt() ?? 0
      ..wins = (j['wins'] as num?)?.toInt() ?? 0;
    final per = j['per'];
    if (per is Map) {
      for (final e in per.entries) {
        final v = e.value;
        if (v is Map) {
          s.per['${e.key}'] = {
            'p': (v['p'] as num?)?.toInt() ?? 0,
            'w': (v['w'] as num?)?.toInt() ?? 0,
            'elo': (v['elo'] as num?)?.toDouble() ?? StatsStore.initialElo,
          };
        }
      }
    }
    return s;
  }

  Map<String, dynamic> publicJson() => {
        'games': games,
        'wins': wins,
        'per': {
          for (final e in per.entries) e.key: {'p': e.value['p'], 'w': e.value['w'], 'elo': (e.value['elo'] ?? 1500).round()}
        },
      };
}

/// One finished-game participant.
class StatEntry {
  final String pid; // '' = anonymous human or bot
  final String name;
  final int avatar;
  final bool bot;
  final int placing;
  const StatEntry(this.pid, this.name, this.avatar, this.bot, this.placing);
}

/// 战绩 / Elo, persisted to `<dir>/stats.json`.
class StatsStore {
  static const initialElo = 1500.0;
  static const k = 32.0;
  static const minGamesForBoard = 3;

  final File? file;
  final Map<String, PlayerStats> players = {};
  Timer? _saveTimer;
  bool _saving = false, _again = false;

  StatsStore(Directory? dir) : file = dir == null ? null : File('${dir.path}${Platform.pathSeparator}stats.json') {
    _load();
  }

  void _load() {
    final f = file;
    if (f == null || !f.existsSync()) return;
    try {
      final j = jsonDecode(f.readAsStringSync());
      final ps = j is Map ? j['players'] : null;
      if (ps is Map) {
        for (final e in ps.entries) {
          if (e.value is Map) players['${e.key}'] = PlayerStats.fromJson((e.value as Map).cast<String, dynamic>());
        }
      }
    } catch (e) {
      stderr.writeln('读取 stats.json 失败：$e');
    }
  }

  /// Apply one finished game. Returns true if anything changed.
  bool record(String gameId, List<StatEntry> entries) {
    final humans = [for (final e in entries) if (!e.bot && e.pid.isNotEmpty) e];
    if (humans.isEmpty) return false;
    PlayerStats rec(StatEntry e) {
      final p = players.putIfAbsent(e.pid, () => PlayerStats(e.name, e.avatar));
      p.name = e.name;
      p.avatar = e.avatar;
      return p;
    }

    Map<String, num> g(PlayerStats p) => p.per.putIfAbsent(gameId, () => {'p': 0, 'w': 0, 'elo': initialElo});
    // Elo from pre-game ratings
    final before = [for (final h in humans) (g(rec(h))['elo'] ?? initialElo).toDouble()];
    final delta = List.filled(humans.length, 0.0);
    if (humans.length > 1) {
      for (var i = 0; i < humans.length; i++) {
        for (var j = 0; j < humans.length; j++) {
          if (i == j) continue;
          final s = humans[i].placing < humans[j].placing ? 1.0 : (humans[i].placing == humans[j].placing ? 0.5 : 0.0);
          final exp = 1 / (1 + pow(10, (before[j] - before[i]) / 400));
          delta[i] += k * (s - exp) / (humans.length - 1);
        }
      }
    }
    for (var i = 0; i < humans.length; i++) {
      final p = rec(humans[i]);
      final gg = g(p);
      p.games++;
      gg['p'] = (gg['p'] ?? 0) + 1;
      if (humans[i].placing == 1) {
        p.wins++;
        gg['w'] = (gg['w'] ?? 0) + 1;
      }
      gg['elo'] = before[i] + delta[i];
    }
    scheduleSave();
    return true;
  }

  Map<String, dynamic> statsFor(String pid) =>
      players[pid]?.publicJson() ?? {'games': 0, 'wins': 0, 'per': <String, dynamic>{}};

  List<Map<String, dynamic>> leaderboard(String gameId, {int limit = 50}) {
    final rows = <(PlayerStats, Map<String, num>)>[
      for (final p in players.values)
        if (p.per[gameId] case final g? when (g['p'] ?? 0) >= minGamesForBoard) (p, g)
    ]..sort((a, b) => (b.$2['elo'] ?? 0).compareTo(a.$2['elo'] ?? 0));
    return [
      for (final (p, g) in rows.take(limit))
        {'name': p.name, 'avatar': p.avatar, 'elo': (g['elo'] ?? initialElo).round(), 'p': g['p'], 'w': g['w']}
    ];
  }

  void scheduleSave() {
    if (file == null) return;
    _saveTimer ??= Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      save();
    });
  }

  /// Atomic write: temp file then rename.
  Future<void> save() async {
    final f = file;
    if (f == null) return;
    if (_saving) {
      _again = true;
      return;
    }
    _saving = true;
    try {
      final text = jsonEncode({'v': 1, 'players': {for (final e in players.entries) e.key: e.value.toJson()}});
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      stderr.writeln('保存 stats.json 失败：$e');
    } finally {
      _saving = false;
      if (_again) {
        _again = false;
        unawaited(save());
      }
    }
  }

  Future<void> flush() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      await save();
    }
  }
}
