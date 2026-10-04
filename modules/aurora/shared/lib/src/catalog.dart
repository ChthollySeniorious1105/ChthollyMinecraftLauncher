/// Discovery estimates are suggestions, not a limit on a game's rules/options.
Map<String, dynamic> gameTraits(String id, String category) {
  const short = {
    'tictactoe',
    'connect4',
    'quizparty',
    'memorypairs',
    'lightsout',
    'wordtiles',
    'battle2048',
    'tetrisbattle',
    'snakebattle',
    'pigdice',
    'nothanks',
  };
  const long = {
    'go',
    'chess',
    'xiangqi',
    'shogi',
    'bridge',
    'monopoly',
    'catan',
    'riichi4',
    'riichi3',
    'taiwan16',
    'guandan',
    'shengji',
  };
  const coop = {
    'escapehouse',
    'hanabi',
    'justone',
    'themind',
    'codenames_duet',
  };
  final minutes = short.contains(id)
      ? 5
      : long.contains(id) || category == '麻将'
      ? 45
      : 15;
  return {
    'minutes': minutes,
    'difficulty': long.contains(id) || category == '麻将'
        ? 3
        : short.contains(id) || id == 'escapehouse'
        ? 1
        : 2,
    'mode': coop.contains(id) ? 'coop' : 'competitive',
  };
}

bool matchesGame(
  Map<String, dynamic> g, {
  int players = 0,
  int minutes = 0,
  int difficulty = 0,
  String mode = '',
}) {
  final range = (g['players'] as List?) ?? [1, 99];
  return (players == 0 ||
          players >= (range[0] as num) && players <= (range[1] as num)) &&
      (minutes == 0 || (g['minutes'] as num? ?? 15) <= minutes) &&
      (difficulty == 0 || (g['difficulty'] as num? ?? 2) <= difficulty) &&
      (mode.isEmpty || g['mode'] == mode);
}
