import 'dart:math';

import 'ai.dart';

/// Thrown by engines when an action is illegal. The message is shown to the player.
class GameError implements Exception {
  final String message;
  GameError(this.message);
  @override
  String toString() => message;
}

class OptionChoice {
  final Object value;
  final String label;
  const OptionChoice(this.value, this.label);
  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// A room-level game option (always a choice list so every client can render it).
class OptionDef {
  final String key;
  final String label;
  final List<OptionChoice> choices;
  final Object defaultValue;
  const OptionDef(this.key, this.label, this.choices, this.defaultValue);
  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'choices': [for (final c in choices) c.toJson()],
        'default': defaultValue,
      };
}

/// Everything an engine needs to start a match.
class GameSetup {
  /// Number of players (game seats are 0..players-1).
  final int players;
  final Map<String, dynamic> options;

  /// Display names, indexed by game seat.
  final List<String> names;

  /// Which game seats are controlled by bots.
  final List<bool> bots;

  /// Game seat of the room host, or -1 if the host is not seated.
  final int hostSeat;
  final Random rng;

  /// Server-provided extra data, keyed by resource name. Loaded by the server
  /// from files next to the executable (see server/README / words/ folder), e.g.
  /// `'drawguess.words'` -> List<String> of lines "词语|类别" added by the server admin.
  final Map<String, Object> resources;

  /// Bot strength chosen by the room host: 0 简单, 1 普通, 2 困难.
  final int botLevel;

  /// LLM service configured on the server (`.env`), or null. Engines must work
  /// without it; see [GameEngine.aiOn].
  final AiService? ai;

  GameSetup({
    required this.players,
    required this.options,
    required this.names,
    required this.bots,
    this.hostSeat = -1,
    Random? rng,
    this.resources = const {},
    this.botLevel = 1,
    this.ai,
    Random? botRng,
  })  : rng = rng ?? Random(),
        botRng = botRng ?? Random();

  /// Randomness for bot() thinking only (see [GameEngine.rng]).
  final Random botRng;

  /// Same setup with a different rng / bots list (used to rebuild an engine for 悔棋).
  GameSetup copyWith({Random? rng, List<bool>? bots}) => GameSetup(
        players: players,
        options: options,
        names: names,
        bots: bots ?? List.of(this.bots),
        hostSeat: hostSeat,
        rng: rng,
        resources: resources,
        botLevel: botLevel,
        ai: ai,
        botRng: botRng,
      );

  /// Custom text lines the server admin supplied for [key] (empty if none).
  List<String> resourceLines(String key) {
    final v = resources[key];
    return v is List<String> ? v : const [];
  }

  T opt<T>(String key, T fallback) {
    final v = options[key];
    return v is T ? v : fallback;
  }
}

/// Services the server provides to a running engine.
abstract class GameHost {
  /// Push a system line into the room chat (e.g. "张三 立直").
  void log(String text);

  /// Run [fn] after [ms] milliseconds (reveal delays, timeouts ...).
  /// The server re-broadcasts views after [fn] runs. Returns a cancel function.
  void Function() schedule(int ms, void Function() fn);
}

class NullHost implements GameHost {
  @override
  void log(String text) {}
  @override
  void Function() schedule(int ms, void Function() fn) => () {};
}

/// Base class for every game. Engines are authoritative and run on the server.
///
/// Contract:
///  * [start] is called once after construction, after [host] is set.
///  * [handle] applies an action from a game seat or throws [GameError].
///    The server broadcasts fresh views to everyone after every successful
///    handle() and after every scheduled callback.
///  * [view] returns a JSON-serialisable map (only Map/List/String/num/bool/null)
///    for a seat (seat -1 = spectator) containing ONLY what that seat may see.
///  * [waitingFor] lists seats the game currently expects input from; for bot
///    seats in that list the server calls [bot] after [botDelayMs].
///  * When the game ends set [isOver] true; put results into the view.
abstract class GameEngine {
  final GameSetup setup;
  GameHost host = NullHost();

  GameEngine(this.setup);

  int get players => setup.players;

  /// Game randomness. Inside [bot] this is a separate, unrecorded generator so
  /// bot thinking never changes the game's own random sequence (replays and
  /// 悔棋 rebuild the game from the seed + recorded actions only).
  Random get rng => _inBot ? setup.botRng : setup.rng;
  bool _inBot = false;

  /// What the server / simulator call instead of [bot] directly.
  Map<String, dynamic>? runBot(int seat) {
    _inBot = true;
    try {
      return bot(seat);
    } finally {
      _inBot = false;
    }
  }

  String name(int seat) =>
      seat >= 0 && seat < setup.names.length ? setup.names[seat] : '?';
  bool isBot(int seat) => seat >= 0 && seat < setup.bots.length && setup.bots[seat];

  void start();
  void handle(int seat, Map<String, dynamic> action);
  Map<String, dynamic> view(int seat);
  List<int> get waitingFor;
  bool get isOver;

  /// Return a legal action for a bot seat, or null to do nothing right now.
  Map<String, dynamic>? bot(int seat) => null;

  /// Delay before the server asks a bot to move, in ms.
  int get botDelayMs => 800;

  /// Bot strength 0 简单 / 1 普通 / 2 困难 (room setting).
  int get botLevel => setup.botLevel;

  /// True when the room enabled this game's `ai` option AND the server has an
  /// LLM configured. Always false in the simulator / tests without a fake.
  bool get aiOn => setup.options['ai'] == true && (setup.ai?.available ?? false);

  /// Final placing per game seat once [isOver]: 1 = best, ties share a rank
  /// (e.g. team games: all winners 1, all losers 2). null = not ranked.
  /// Used for 战绩 / Elo / 系列赛 and the win/lose sound.
  List<int>? get placings => null;

  /// 认输: set when the engine supports resigning; [resign] must end the game
  /// (or, in multi-player games, drop that seat) and set [placings].
  bool get canResign => false;
  void resign(int seat) => throw GameError('该游戏不支持认输');

  /// 求和: all human players agreed; end the game as a draw.
  bool get canDraw => false;
  void agreeDraw() => throw GameError('该游戏不支持和棋');

  /// Voice routing: game seats allowed to hear [seat] right now (seat -1 =
  /// spectators). null = everyone. Example: werewolf night → only wolves hear
  /// wolves. Spectators always hear everyone; the server applies this filter.
  Set<int>? voiceListeners(int seat) => null;
}

/// Static description of a game type.
class GameDef {
  final String id;
  final String name;
  final String category;
  final String description;
  final List<OptionDef> options;

  /// Allowed player counts for the given options: (min, max).
  final (int, int) Function(Map<String, dynamic> options) playerRange;
  final bool botSupport;
  final GameEngine Function(GameSetup setup) create;

  /// Full rules shown in the client (plain text; lines starting with `#` are
  /// headings, `- ` bullets).
  final String rules;

  /// 悔棋 support: the server rebuilds the engine from the same rng seed by
  /// re-applying the recorded actions minus the undone ones. Only set this
  /// when handle() is deterministic given the seed AND bot() has no side
  /// effects on game state/rng (the simulator verifies this).
  final bool undo;

  const GameDef({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.playerRange,
    required this.create,
    this.options = const [],
    this.botSupport = true,
    this.rules = '',
    this.undo = false,
  });

  Map<String, dynamic> defaultOptions() =>
      {for (final o in options) o.key: o.defaultValue};

  /// Fill missing / invalid option values with defaults.
  Map<String, dynamic> normalizeOptions(Map<String, dynamic>? raw) {
    final out = <String, dynamic>{};
    for (final o in options) {
      final v = raw?[o.key];
      out[o.key] = o.choices.any((c) => c.value == v) ? v : o.defaultValue;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'options': [for (final o in options) o.toJson()],
        'bots': botSupport,
        // rules are compiled into every client (same shared package), so the
        // welcome message doesn't carry them (it would exceed kMaxFrame)
        'undo': undo,
        'players': [defaultOptionsRange().$1, defaultOptionsRange().$2],
      };

  (int, int) defaultOptionsRange() => playerRange(defaultOptions());
}

/// Lenient int coercion for client-supplied values. Never throws: non-finite
/// doubles (JSON `1e999` decodes to Infinity) and junk map to [fallback].
int asInt(Object? v, [int fallback = -1]) => v is int
    ? v
    : (v is num
        ? (v.isFinite ? v.toInt() : fallback)
        : (v is String ? int.tryParse(v) ?? fallback : fallback));

String asStr(Object? v, [String fallback = '']) => v is String ? v : fallback;

bool asBool(Object? v) => v == true;

List<int> asIntList(Object? v) =>
    v is List ? [for (final e in v) asInt(e)] : <int>[];

List<T> shuffled<T>(Iterable<T> items, Random rng) => List<T>.of(items)..shuffle(rng);

/// Mahjong-style "fake think" delay (雀魂 behaviour): when a discard can't be
/// claimed by anyone, still pause sometimes so the table's timing doesn't reveal
/// whether a claim was possible. Returns 0 (no pause) or 500..1000 ms.
/// Call it for every discard with no possible claim; when a claim IS possible
/// the real claim window already makes everyone wait.
int claimCoverDelayMs(Random rng, {double probability = 0.6}) =>
    claimCoverEnabled && rng.nextDouble() < probability ? 500 + rng.nextInt(501) : 0;

/// Rule unit tests that step engines synchronously turn this off.
bool claimCoverEnabled = true;

/// Standard ranking from scores (higher is better unless [lowWins]); ties share
/// the better rank. Convenience for [GameEngine.placings].
List<int> rankByScore(List<num> scores, {bool lowWins = false}) => [
      for (var i = 0; i < scores.length; i++)
        1 + [for (var j = 0; j < scores.length; j++) j].where((j) => lowWins ? scores[j] < scores[i] : scores[j] > scores[i]).length,
    ];

/// Ranking where [winners] are 1st and everyone else 2nd.
List<int> rankWinners(int players, Iterable<int> winners) {
  final w = winners.toSet();
  return [for (var i = 0; i < players; i++) w.contains(i) ? 1 : (w.isEmpty ? 1 : 2)];
}
