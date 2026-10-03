import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
// ignore: implementation_imports
import 'package:aurora_shared/src/simulate.dart' show rebuildEngine;
import 'package:flutter/foundation.dart';

import '../state/app_state.dart';
import 'replay_store.dart';
import 'sfx.dart';

/// 单机游戏: runs a game engine on this device against bots, no server.
///
/// Produces [GameState]s shaped exactly like the network ones so the normal
/// boards render it; [AppState.action] routes board actions to [act].
class LocalSession extends ChangeNotifier implements GameHost {
  final GameDef def;
  final Map<String, dynamic> options;
  final int players;
  final int humanSeat;
  final int botLevel;
  final String humanName;
  final int humanAvatar;

  /// Override the engine's bot delay (tests); null = engine.botDelayMs.
  final int? botDelayMs;

  /// Save a replay file when the game ends.
  final bool saveReplay;

  LocalSession({
    required this.def,
    required Map<String, dynamic> options,
    required this.players,
    this.humanSeat = 0,
    this.botLevel = 1,
    required this.humanName,
    required this.humanAvatar,
    this.botDelayMs,
    this.saveReplay = true,
  }) : options = def.normalizeOptions(options);

  late GameEngine engine;
  late GameSetup _setup;
  late int _seed;
  late ReplayRecorder _rec;
  late List<String> names;
  late List<int> avatars;

  /// What the board shows (my seat's view).
  GameState? state;

  /// Game log lines ("系统" messages), newest last.
  final List<ChatLine> logs = [];

  /// Successful actions (seat, action) since the start — for 悔棋.
  final List<(int, Map<String, dynamic>)> _log = [];

  /// 托管: bots also play my seat.
  bool auto = false;
  bool _finished = false;
  bool _disposed = false;
  int _epoch = 0;
  Timer? _botTimer;
  final Set<Timer> _timers = {};
  bool _wasMyTurn = false;

  /// Where the replay was saved (after the game ended).
  String? replayPath;

  void Function(String)? onToast;
  void Function(SfxKind)? onSound;
  void Function(EmoteEvent)? onEmote;

  bool get isOver => engine.isOver;
  bool get canResign => !isOver && engine.canResign;
  bool get canDraw => !isOver && engine.canDraw;
  bool get canUndo => def.undo && !isOver && _log.any((e) => e.$1 == humanSeat);

  /// Placing of the human (1 = won) once over, or null.
  int? get myPlacing {
    final p = isOver ? engine.placings : null;
    return p != null && humanSeat < p.length ? p[humanSeat] : null;
  }

  /// Build the engine and start (or restart) the game.
  void begin() {
    _epoch++;
    _cancelAll();
    _finished = false;
    auto = false;
    replayPath = null;
    logs.clear();
    _log.clear();
    names = [for (var i = 0; i < players; i++) i == humanSeat ? humanName : '电脑${i < humanSeat ? i + 1 : i}'];
    avatars = [for (var i = 0; i < players; i++) i == humanSeat ? humanAvatar : 0];
    _seed = Random().nextInt(1 << 31);
    _setup = GameSetup(
      players: players,
      options: options,
      names: names,
      bots: [for (var i = 0; i < players; i++) i != humanSeat],
      hostSeat: humanSeat,
      rng: def.undo ? Random(_seed) : Random(),
      botLevel: botLevel,
      botRng: Random(),
    );
    engine = def.create(_setup);
    engine.host = this;
    _rec = ReplayRecorder(players);
    _wasMyTurn = false;
    try {
      engine.start();
    } catch (e) {
      onToast?.call('游戏启动失败：$e');
    }
    onSound?.call(SfxKind.start);
    _changed();
  }

  // ---------------------------------------------------------------- GameHost

  @override
  void log(String text) {
    logs.add(ChatLine(0, '系统', 0, text, DateTime.now(), true));
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
    _rec.log(text);
  }

  @override
  void Function() schedule(int ms, void Function() fn) {
    final epoch = _epoch;
    late Timer t;
    t = Timer(Duration(milliseconds: ms < 0 ? 0 : ms), () {
      _timers.remove(t);
      if (_disposed || epoch != _epoch) return;
      try {
        fn();
      } catch (e) {
        debugPrint('local schedule error: $e');
      }
      _changed();
    });
    _timers.add(t);
    return () {
      t.cancel();
      _timers.remove(t);
    };
  }

  // ----------------------------------------------------------------- actions

  /// A board action from the human player.
  void act(Map<String, dynamic> a) {
    if (_disposed || isOver) return;
    _apply(humanSeat, a, fromHuman: true);
  }

  bool _apply(int seat, Map<String, dynamic> a, {bool fromHuman = false}) {
    Map<String, dynamic> wire;
    try {
      wire = (jsonDecode(jsonEncode(a)) as Map).cast<String, dynamic>();
    } catch (_) {
      return false;
    }
    try {
      engine.handle(seat, wire);
    } on GameError catch (e) {
      if (fromHuman) onToast?.call(e.message);
      return false;
    } catch (e) {
      if (fromHuman) onToast?.call('操作失败：$e');
      debugPrint('local handle error: $e');
      return false;
    }
    _log.add((seat, wire));
    _changed();
    return true;
  }

  void setAuto(bool on) {
    auto = on;
    _changed();
  }

  void resign() {
    if (!canResign) return;
    try {
      engine.resign(humanSeat);
    } on GameError catch (e) {
      onToast?.call(e.message);
      return;
    }
    _changed();
  }

  /// 求和: the bots always accept.
  void offerDraw() {
    if (!canDraw) return;
    try {
      engine.agreeDraw();
    } on GameError catch (e) {
      onToast?.call(e.message);
      return;
    }
    onToast?.call('电脑同意了和棋');
    _changed();
  }

  /// 悔棋: rebuild from the seed without my last action (and everything after).
  void undo() {
    if (!def.undo || isOver) return;
    final k = _log.lastIndexWhere((e) => e.$1 == humanSeat);
    if (k < 0) {
      onToast?.call('没有可以悔的棋');
      return;
    }
    final keep = _log.sublist(0, k);
    GameEngine e2;
    try {
      e2 = rebuildEngine(def, _setup.copyWith(rng: Random(_seed), bots: [for (var i = 0; i < players; i++) i != humanSeat]), keep);
    } catch (e) {
      onToast?.call('悔棋失败：$e');
      return;
    }
    _epoch++;
    _cancelAll();
    engine = e2;
    engine.host = this;
    _log
      ..clear()
      ..addAll(keep);
    log('$humanName 悔棋');
    _changed();
  }

  // ------------------------------------------------------------------ engine

  void _changed() {
    if (_disposed) return;
    final e = engine;
    Map<String, dynamic> view;
    try {
      view = e.view(humanSeat);
    } catch (err) {
      view = {'error': '$err'};
    }
    state = GameState(def.id, humanSeat, names, [for (var i = 0; i < players; i++) i != humanSeat], avatars, view, e.isOver);
    if (!_rec.full) {
      for (var s = -1; s < players; s++) {
        try {
          _rec.add(s, s == humanSeat ? view : e.view(s));
        } catch (_) {}
      }
    }
    final myTurn = !e.isOver && e.waitingFor.contains(humanSeat);
    if (myTurn && !_wasMyTurn && !auto) onSound?.call(SfxKind.turn);
    _wasMyTurn = myTurn;
    if (e.isOver && !_finished) {
      _finished = true;
      _cancelBots();
      final p = myPlacing;
      onSound?.call(p == null ? SfxKind.over : (p == 1 ? SfxKind.win : SfxKind.lose));
      if (saveReplay) unawaited(_saveReplay());
    } else if (!e.isOver) {
      _scheduleBots();
    }
    notifyListeners();
  }

  bool _isBotSeat(int s) => s != humanSeat || auto;

  void _scheduleBots() {
    // keep an already pending bot move (fast ticking games would otherwise
    // postpone it forever)
    if (_botTimer?.isActive ?? false) return;
    List<int> w;
    try {
      w = engine.waitingFor;
    } catch (_) {
      return;
    }
    if (!w.any(_isBotSeat)) return;
    final epoch = _epoch;
    final delay = botDelayMs ?? engine.botDelayMs;
    _botTimer = Timer(Duration(milliseconds: delay), () => _runBots(epoch));
  }

  void _runBots(int epoch) {
    _botTimer = null;
    if (_disposed || epoch != _epoch || engine.isOver) return;
    final w = List.of(engine.waitingFor);
    var acted = false;
    for (final s in w) {
      if (!_isBotSeat(s)) continue;
      Map<String, dynamic>? a;
      try {
        a = engine.runBot(s);
      } catch (e) {
        debugPrint('local bot error: $e');
      }
      if (a == null) continue;
      if (_apply(s, a)) {
        acted = true;
        break; // _changed() re-scheduled the next bot move
      }
    }
    if (!acted && !_disposed && epoch == _epoch) {
      // bot returned null (or an illegal move): retry shortly
      _botTimer = Timer(const Duration(milliseconds: 500), () => _runBots(epoch));
    }
  }

  void _cancelBots() {
    _botTimer?.cancel();
    _botTimer = null;
  }

  void _cancelAll() {
    _cancelBots();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  Future<void> _saveReplay() async {
    try {
      final doc = _rec.finish((d) => ReplayMeta(
            id: newReplayId(),
            game: def.id,
            gameName: def.name,
            startedAt: _rec.startedAt,
            durationMs: d,
            names: names,
            avatars: avatars,
            bots: [for (var i = 0; i < players; i++) i != humanSeat],
            options: options,
            uids: [for (var i = 0; i < players; i++) i == humanSeat ? 'local' : ''],
            ranking: engine.placings,
            room: '单机',
          ));
      replayPath = await ReplayStore.saveDoc(doc);
    } catch (e) {
      debugPrint('save local replay failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cancelAll();
    super.dispose();
  }
}
