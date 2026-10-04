import 'package:aurora_shared/aurora_shared.dart';

/// A room-owned series; scores survive game changes and reconnects.
class PartyNight {
  final List<String> queue;
  final Map<int, String> votes = {};
  final Map<String, Map<String, dynamic>> scores = {};
  int index = 0;
  bool roundComplete = false;
  PartyNight(List<String> games) : queue = List.of(games);
  bool get finished => roundComplete && index == queue.length - 1;
  List<String> get remaining => queue.skip(index + 1).toList();
  void vote(int client, String game) {
    if (!roundComplete || finished || !remaining.contains(game))
      throw GameError('现在不能投票选择该游戏');
    votes[client] = game;
  }

  String? nextChoice(Set<int> members, bool Function(String) suitable) {
    final candidates = remaining.where(suitable).toList();
    if (candidates.isEmpty) return null;
    int count(String id) => votes.entries
        .where((v) => members.contains(v.key) && v.value == id)
        .length;
    var selected = candidates.first;
    for (final c in candidates.skip(1)) {
      if (count(c) > count(selected)) selected = c;
    }
    return selected;
  }

  void advance(String selected) {
    if (!roundComplete || finished) throw GameError('请先完成当前对局');
    final pos = queue.indexOf(selected, index + 1);
    if (pos < 0) throw GameError('游戏不在队列中');
    queue.removeAt(pos);
    queue.insert(index + 1, selected);
    index++;
    votes.clear();
    roundComplete = false;
  }

  void record(List<Map<String, dynamic>> players, List<int>? ranks) {
    if (roundComplete) return;
    roundComplete = true;
    if (ranks == null) return;
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      final row = scores.putIfAbsent(
        '${p['key']}',
        () => {
          'name': p['name'],
          'avatar': p['avatar'],
          'points': 0,
          'wins': 0,
          'games': 0,
        },
      );
      row['name'] = p['name'];
      row['avatar'] = p['avatar'];
      final earned = ranks[i] == 1
          ? 100
          : players.length <= 1
          ? 0
          : ((players.length - ranks[i]) * 100 ~/ (players.length - 1)).clamp(
              0,
              100,
            );
      row['points'] = asInt(row['points'], 0) + earned;
      row['games'] = asInt(row['games'], 0) + 1;
      if (ranks[i] == 1) row['wins'] = asInt(row['wins'], 0) + 1;
    }
  }

  Map<String, dynamic> toJson() => {
    'queue': queue,
    'index': index,
    'roundComplete': roundComplete,
    'finished': finished,
    'votes': {for (final v in votes.entries) '${v.key}': v.value},
    'scores': scores.values.toList()
      ..sort((a, b) => asInt(b['points']).compareTo(asInt(a['points']))),
  };
}
