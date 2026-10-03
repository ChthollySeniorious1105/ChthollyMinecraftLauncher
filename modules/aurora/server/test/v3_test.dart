import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

import 'server_test.dart' show TClient;

/// Tiny deterministic 2-player test game: players alternate `{'v': n}` moves;
/// after [limit] moves the higher total wins. Supports resign / draw / undo /
/// voice routing, and an AI bot that waits on setup.ai.
class CountGame extends GameEngine {
  CountGame(super.setup);
  final List<List<int>> moves = []; // [seat, v]
  int turn = 0;
  int r = 0;
  List<int>? result;
  int get limit => setup.opt<int>('limit', 6);
  final _ai = AiSlot();

  @override
  void start() {
    r = rng.nextInt(1 << 30);
    host.log('开始 $r');
  }

  @override
  bool get isOver => result != null;
  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('结束了');
    if (seat != turn) throw GameError('还没轮到你');
    final v = asInt(a['v'], 1);
    moves.add([seat, v]);
    turn = 1 - turn;
    if (moves.length >= limit) {
      final s = [0, 0];
      for (final m in moves) {
        s[m[0]] += m[1];
      }
      result = rankByScore(s);
    }
  }

  @override
  Map<String, dynamic> view(int seat) => {'moves': moves, 'turn': turn, 'r': r, 'result': result, 'me': seat};

  @override
  Map<String, dynamic>? bot(int seat) {
    if (aiOn) {
      final p = _ai.poll(setup.ai!, 'm:${moves.length}', () => const AiRequest(system: 's', prompt: 'p'));
      if (p.pending) return null;
      return {'v': int.tryParse(p.text ?? '') ?? 1};
    }
    return {'v': 1};
  }

  @override
  int get botDelayMs => 50;
  @override
  List<int>? get placings => result;
  @override
  bool get canResign => true;
  @override
  void resign(int seat) => result = [for (var i = 0; i < players; i++) i == seat ? 2 : 1];
  @override
  bool get canDraw => true;
  @override
  void agreeDraw() => result = [1, 1];

  /// 'mute' option: players can't hear each other (spectators still can).
  @override
  Set<int>? voiceListeners(int seat) => setup.opt<bool>('mute', false) ? <int>{} : null;
}

final countDef = GameDef(
  id: 'test_count',
  name: '测试数数',
  category: '测试',
  description: 'test',
  playerRange: (_) => (2, 2),
  options: const [
    OptionDef('limit', '步数', [OptionChoice(6, '6'), OptionChoice(2, '2'), OptionChoice(40, '40')], 6),
    OptionDef('mute', '静音', [OptionChoice(false, '否'), OptionChoice(true, '是')], false),
    OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开')], false),
  ],
  undo: true,
  create: CountGame.new,
);

/// AI that answers "5" after [delay].
class SlowAi extends AiService {
  final Duration delay;
  int calls = 0;
  SlowAi(this.delay);
  @override
  bool get available => true;
  @override
  String get label => 'slow · test';
  @override
  Future<String?> complete(AiRequest req) async {
    calls++;
    await Future.delayed(delay);
    return '5';
  }
}

void main() {
  late AuroraServer server;
  late Directory tmp;
  late SlowAi ai;
  const port = 17801;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('aurora_v3');
    ai = SlowAi(const Duration(milliseconds: 1500));
    server = AuroraServer(port,
        extraGames: [countDef],
        ai: ai,
        salt: 'testsalt-testsalt',
        dataDir: Directory('${tmp.path}/data'),
        replayDir: Directory('${tmp.path}/replays'),
        discoveryPort: 0);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<TClient> login(String name, {String uid = ''}) async {
    final c = TClient();
    await c.connect(port);
    c.send({'t': 'hello', 'ver': kProtocolVersion, 'name': name, 'avatar': 3, 'token': '', 'uid': uid});
    await c.waitT(Msg.welcome);
    return c;
  }

  Future<String> createRoom(TClient c, {Map<String, dynamic> options = const {}}) async {
    c.send({'t': 'create_room', 'game': 'test_count', 'options': options});
    final r = await c.wait((m) => m['t'] == Msg.room && m['room'] != null);
    return r['room']['id'] as String;
  }

  /// Two humans a (seat 0) and b (seat 1) in a started game.
  Future<(TClient, TClient, String)> twoPlayers({Map<String, dynamic> options = const {}}) async {
    final a = await login('甲', uid: 'uid-a');
    final b = await login('乙', uid: 'uid-b');
    final rid = await createRoom(a, options: options);
    b.send({'t': 'join_room', 'room': rid});
    await b.wait((m) => m['t'] == Msg.room && m['room'] != null);
    b.send({'t': 'ready', 'ready': true});
    await a.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[1]['ready'] == true);
    a.send({'t': 'start'});
    await a.wait((m) => m['t'] == Msg.game && m['game'] == 'test_count');
    await b.wait((m) => m['t'] == Msg.game && m['game'] == 'test_count');
    return (a, b, rid);
  }

  Future<Map> gameWhere(TClient c, bool Function(Map v) p) =>
      c.wait((m) => m['t'] == Msg.game && m['view'] is Map && p(m['view'] as Map));

  test('welcome: pid from uid, ai flag and label; uid optional', () async {
    final a = TClient();
    await a.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'x', 'avatar': 1, 'token': '', 'uid': 'abc'});
    final w = await a.waitT(Msg.welcome);
    expect(w['pid'], server.pidFor('abc'));
    expect(w['pid'], matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(w['ai'], isTrue);
    expect(w['aiLabel'], 'slow · test');
    final b = TClient();
    await b.connect(port);
    b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'y', 'avatar': 1, 'token': ''});
    expect((await b.waitT(Msg.welcome))['pid'], '');
    // old protocol version rejected
    final c = TClient();
    await c.connect(port);
    c.send({'t': 'hello', 'ver': 2, 'name': 'z', 'avatar': 1, 'token': ''});
    expect((await c.waitT(Msg.error))['fatal'], isTrue);
  });

  test('emote broadcast with game seat, rate limited, bad index rejected', () async {
    final (a, b, _) = await twoPlayers();
    b.clear();
    a.send({'t': 'emote', 'e': 3});
    final m = await b.waitT(Msg.emoteMsg);
    expect(m['e'], 3);
    expect(m['seat'], 0);
    expect(m['name'], '甲');
    a.send({'t': 'emote', 'e': 999});
    expect((await a.waitT(Msg.error))['msg'], contains('无效'));
    for (var i = 0; i < 8; i++) {
      a.send({'t': 'emote', 'e': 0});
    }
    expect((await a.waitT(Msg.error))['msg'], contains('太快'));
  });

  test('room snapshot has v3 fields; set_room_opts botLevel', () async {
    final a = await login('host');
    await createRoom(a);
    a.send({'t': 'set_room_opts', 'botLevel': 2});
    final r = await a.wait((m) => m['t'] == Msg.room && m['room']?['botLevel'] == 2);
    final room = r['room'] as Map;
    expect(room['caps'], {'resign': false, 'draw': false, 'undo': false});
    expect(room['request'], isNull);
    expect(room['tally'], isEmpty);
    expect((room['seats'] as List).first['auto'], isFalse);
    a.send({'t': 'set_room_opts', 'botLevel': 5});
    expect((await a.waitT(Msg.error))['msg'], contains('难度'));
    // botLevel reaches the engine
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    await a.waitT(Msg.game);
    expect(server.rooms.values.first.engine!.botLevel, 2);
  });

  test('auto_play: bot plays for a 托管 seat quickly', () async {
    final (a, b, _) = await twoPlayers();
    a.send({'t': 'auto_play', 'on': true});
    final r = await b.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[0]['auto'] == true);
    expect(r['room']['seats'][0]['auto'], isTrue);
    // seat 0 is to move: the bot plays for 甲 well under the 5 s offline delay
    final sw = Stopwatch()..start();
    await gameWhere(b, (v) => (v['moves'] as List).length == 1);
    expect(sw.elapsedMilliseconds, lessThan(2000));
    a.send({'t': 'auto_play', 'on': false});
    await b.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[0]['auto'] == false);
    b.send({'t': 'action', 'a': {'v': 1}});
    await gameWhere(a, (v) => (v['moves'] as List).length == 2);
    await Future.delayed(const Duration(milliseconds: 400));
    expect((server.rooms.values.first.engine as CountGame).moves.length, 2, reason: 'no auto move after turning off');
  });

  test('same name + same ip without token resumes the identity and takes 托管 off', () async {
    final (a, b, rid) = await twoPlayers();
    final id = server.rooms[rid]!.seats[0].client!.id;
    a.send({'t': 'auto_play', 'on': true});
    await b.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[0]['auto'] == true);
    a.s.destroy(); // e.g. browser reloaded: token lost
    b.clear();
    await b.wait((m) => m['t'] == Msg.room && ((m['room']['seats'] as List)[0]['client'] as Map)['online'] == false);
    final a2 = TClient();
    await a2.connect(port);
    a2.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '甲', 'avatar': 3, 'token': '', 'uid': 'uid-a'});
    final w = await a2.waitT(Msg.welcome);
    expect(w['id'], id, reason: 'same person, not a new client');
    final r = await a2.wait((m) => m['t'] == Msg.room && m['room'] != null);
    expect((r['room']['seats'] as List)[0]['client']['id'], id);
    a2.send({'t': 'auto_play', 'on': false});
    final r2 = await b.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[0]['auto'] == false);
    expect(r2['room']['seats'][0]['client']['online'], isTrue);
  });

  test('duplicate login with an online name from the same ip is refused', () async {
    await login('丙', uid: 'uid-c');
    final d = TClient();
    await d.connect(port);
    d.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '丙', 'avatar': 3, 'token': '', 'uid': 'uid-d'});
    final e = await d.waitT(Msg.error);
    expect(e['fatal'], isTrue);
    expect(e['msg'], contains('修改名称'));
    // a different name is fine, but renaming onto the online name is not
    final f = await login('丁', uid: 'uid-d');
    f.send({'t': 'set_profile', 'name': '丙', 'avatar': 3});
    final e2 = await f.waitT(Msg.error);
    expect(e2['msg'], contains('已在线'));
  });

  test('player whose seat went to the bot gets it back on return', () async {
    final (a, b, rid) = await twoPlayers();
    a.send({'t': 'leave_room'});
    await b.wait((m) => m['t'] == Msg.room && (m['room']['seats'] as List)[0]['takenOver'] == true);
    b.clear();
    a.send({'t': 'join_room', 'room': rid});
    final r = await b.wait((m) =>
        m['t'] == Msg.room && (m['room']['seats'] as List)[0]['takenOver'] == false);
    final seat = (r['room']['seats'] as List)[0];
    expect(seat['bot'], isFalse);
    expect(seat['client']['name'], '甲');
    expect(server.rooms[rid]!.engine!.setup.bots[0], isFalse);
  });

  test('resign ends the game; stats, tally and replay recorded', () async {
    final (a, b, _) = await twoPlayers();
    final r0 = await a.wait((m) => m['t'] == Msg.room && m['room']['playing'] == true);
    expect(r0['room']['caps'], {'resign': true, 'draw': true, 'undo': true});
    a.send({'t': 'action', 'a': {'v': 2}});
    await gameWhere(b, (v) => (v['moves'] as List).length == 1);
    b.send({'t': 'resign'});
    final over = await a.wait((m) => m['t'] == Msg.game && m['over'] == true);
    expect(over['view']['result'], [1, 2]);
    final room = await a.wait((m) => m['t'] == Msg.room && (m['room']['tally'] as List).length == 2);
    final tally = (room['room']['tally'] as List).cast<Map>();
    final ta = tally.firstWhere((t) => t['name'] == '甲');
    expect(ta['wins'], 1);
    expect(ta['points'], 3);
    expect(tally.firstWhere((t) => t['name'] == '乙')['points'], 0);
    // stats + Elo
    a.send({'t': 'my_stats'});
    final st = (await a.waitT(Msg.stats))['stats'] as Map;
    expect(st['games'], 1);
    expect(st['wins'], 1);
    expect(st['per']['test_count']['elo'], 1516);
    b.send({'t': 'my_stats'});
    expect(((await b.waitT(Msg.stats))['stats'] as Map)['per']['test_count']['elo'], 1484);
    await server.stats.flush();
    await Future.delayed(const Duration(milliseconds: 100));
    final saved = jsonDecode(File('${tmp.path}/data/stats.json').readAsStringSync()) as Map;
    expect((saved['players'] as Map).length, 2);
    // replay saved and listable (mine)
    Map? meta;
    for (var i = 0; i < 40 && meta == null; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      a.send({'t': 'list_replays', 'mine': true});
      final l = (await a.waitT(Msg.replays))['replays'] as List;
      if (l.isNotEmpty) meta = l.first as Map;
    }
    expect(meta, isNotNull);
    expect(meta!['game'], 'test_count');
    expect(meta['ranking'], [1, 2]);
    expect(meta.containsKey('uids'), isFalse, reason: 'uids are private');
  });

  test('draw request: respond yes ends as draw; no = cancel with toast', () async {
    final (a, b, _) = await twoPlayers();
    a.send({'t': 'request', 'kind': 'draw'});
    final rq = await b.wait((m) => m['t'] == Msg.room && m['room']['request'] != null);
    final req = rq['room']['request'] as Map;
    expect(req['kind'], 'draw');
    expect(req['need'], [2]);
    b.send({'t': 'respond', 'id': req['id'], 'yes': false});
    expect((await a.waitT(Msg.toast))['msg'], contains('拒绝'));
    await a.wait((m) => m['t'] == Msg.room && m['room']['request'] == null);
    a.send({'t': 'request', 'kind': 'draw'});
    final rq2 = await b.wait((m) => m['t'] == Msg.room && m['room']['request'] != null);
    // requester can't answer own request
    a.send({'t': 'respond', 'id': rq2['room']['request']['id'], 'yes': true});
    expect((await a.waitT(Msg.error))['msg'], contains('不需要'));
    b.send({'t': 'respond', 'id': rq2['room']['request']['id'], 'yes': true});
    final over = await a.wait((m) => m['t'] == Msg.game && m['over'] == true);
    expect(over['view']['result'], [1, 1]);
  });

  test('undo request/respond rebuilds from seed without the undone moves', () async {
    final (a, b, _) = await twoPlayers();
    final r = (server.rooms.values.first.engine as CountGame).r;
    // b has not moved yet
    b.send({'t': 'request', 'kind': 'undo'});
    expect((await b.waitT(Msg.error))['msg'], contains('没有可以悔的棋'));
    a.send({'t': 'action', 'a': {'v': 7}});
    await gameWhere(b, (v) => (v['moves'] as List).length == 1);
    b.send({'t': 'action', 'a': {'v': 3}});
    await gameWhere(a, (v) => (v['moves'] as List).length == 2);
    a.send({'t': 'action', 'a': {'v': 9}});
    await gameWhere(b, (v) => (v['moves'] as List).length == 3);
    // b undoes his last move (index 1): moves 1 and 2 are dropped
    b.send({'t': 'request', 'kind': 'undo'});
    final rq = await a.wait((m) => m['t'] == Msg.room && m['room']['request'] != null);
    a.send({'t': 'respond', 'id': rq['room']['request']['id'], 'yes': true});
    final g = await gameWhere(b, (v) => (v['moves'] as List).length == 1);
    expect(g['view']['moves'], [
      [0, 7]
    ]);
    expect(g['view']['turn'], 1);
    expect(g['view']['r'], r, reason: 'same seed');
    // game continues normally on the rebuilt engine
    b.send({'t': 'action', 'a': {'v': 4}});
    await gameWhere(a, (v) => (v['moves'] as List).length == 2);
  });

  test('undo against a bot executes immediately', () async {
    final a = await login('solo');
    await createRoom(a);
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    a.send({'t': 'action', 'a': {'v': 5}});
    await gameWhere(a, (v) => (v['moves'] as List).length == 2); // bot answered
    a.send({'t': 'request', 'kind': 'undo'});
    await gameWhere(a, (v) => (v['moves'] as List).isEmpty);
  });

  test('voice routing follows engine.voiceListeners; spectators hear all', () async {
    final (a, b, rid) = await twoPlayers(options: {'mute': true});
    final s = await login('观众');
    s.send({'t': 'join_room', 'room': rid, 'spectate': true});
    await s.wait((m) => m['t'] == Msg.room && m['room'] != null);
    a.sendFrame(kFrameVoice, List.filled(100, 1));
    await Future.delayed(const Duration(milliseconds: 300));
    expect(b.voice, isEmpty, reason: 'muted by the game');
    expect(s.voice.length, 1, reason: 'spectators always hear');
    s.sendFrame(kFrameVoice, List.filled(100, 1));
    await Future.delayed(const Duration(milliseconds: 300));
    expect(a.voice, isEmpty, reason: 'players do not hear spectators while muted');
  });

  test('voice to everyone when voiceListeners is null', () async {
    final (a, b, _) = await twoPlayers();
    a.sendFrame(kFrameVoice, List.filled(100, 1));
    await Future.delayed(const Duration(milliseconds: 300));
    expect(b.voice.length, 1);
  });

  test('AI bot pending: server retries until the reply arrives', () async {
    Room.botRetryMs = 200;
    final a = await login('人', uid: 'uid-h');
    await createRoom(a, options: {'ai': true, 'limit': 2});
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    a.send({'t': 'action', 'a': {'v': 1}});
    final over = await a.wait((m) => m['t'] == Msg.game && m['over'] == true).timeout(const Duration(seconds: 5));
    expect(over['view']['moves'], [
      [0, 1],
      [1, 5]
    ], reason: 'the AI reply (5) was used');
    expect(ai.calls, 1, reason: 'one request, polled until done');
    // bot-only record: bots get no stats; the human does
    a.send({'t': 'my_stats'});
    expect(((await a.waitT(Msg.stats))['stats'] as Map)['games'], 1);
    Room.botRetryMs = 700;
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('replay download: chunks decode to a Replay with all seats', () async {
    final a = await login('rec', uid: 'uid-r');
    await createRoom(a, options: {'limit': 40});
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    for (var i = 0; i < 20; i++) {
      await gameWhere(a, (v) => v['turn'] == 0 && (v['moves'] as List).length == i * 2);
      a.send({'t': 'action', 'a': {'v': 2}});
    }
    await a.wait((m) => m['t'] == Msg.game && m['over'] == true);
    Map? meta;
    for (var i = 0; i < 40 && meta == null; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      a.send({'t': 'list_replays'});
      final l = (await a.waitT(Msg.replays))['replays'] as List;
      if (l.isNotEmpty) meta = l.first as Map;
    }
    final id = meta!['id'];
    a.send({'t': 'get_replay', 'id': id});
    final first = await a.waitT(Msg.replayChunk);
    final n = first['n'] as int;
    final parts = <int, String>{first['i'] as int: first['data'] as String};
    while (parts.length < n) {
      final c = await a.waitT(Msg.replayChunk);
      parts[c['i'] as int] = c['data'] as String;
    }
    final bytes = [for (var i = 0; i < n; i++) ...base64.decode(parts[i]!)];
    final rep = Replay.fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
    expect(rep.meta.id, id);
    expect(rep.meta.uids, [server.pidFor('uid-r'), '']);
    expect(rep.meta.bots, [false, true]);
    for (final seat in [-1, 0, 1]) {
      final fr = rep.frames(seat);
      expect(fr, isNotEmpty, reason: 'seat $seat');
      expect(fr.last.$2['me'], seat, reason: 'seat $seat track has its own view');
      expect((fr.last.$2['moves'] as List).length, 40);
    }
    expect(rep.logs.any((l) => '${l[1]}'.startsWith('开始')), isTrue);
    // unknown id
    a.send({'t': 'get_replay', 'id': 'nope0000'});
    expect((await a.waitT(Msg.error))['msg'], contains('回放'));
    // store reload from disk
    final store = ReplayStore(Directory('${tmp.path}/replays'));
    expect(store.count, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('aborted unfinished game with few frames is not saved', () async {
    final a = await login('ab');
    await createRoom(a);
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    await a.waitT(Msg.game);
    a.send({'t': 'abort'});
    await a.wait((m) => m['t'] == Msg.game && m['game'] == null);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(server.replays.count, 0);
  });

  test('host kick: member leaves and cannot rejoin for 5 minutes', () async {
    final a = await login('房主');
    final b = await login('捣乱');
    final rid = await createRoom(a);
    b.send({'t': 'join_room', 'room': rid});
    final rb = await b.wait((m) => m['t'] == Msg.room && m['room'] != null);
    final bid = (rb['room']['members'] as List).firstWhere((x) => x['name'] == '捣乱')['id'];
    b.send({'t': 'kick', 'id': 1});
    expect((await b.waitT(Msg.error))['msg'], contains('房主'));
    a.send({'t': 'kick', 'id': bid});
    await b.wait((m) => m['t'] == Msg.room && m['room'] == null);
    expect((await b.waitT(Msg.toast))['msg'], contains('移出'));
    b.send({'t': 'join_room', 'room': rid});
    expect((await b.waitT(Msg.error))['msg'], contains('移出'));
  });

  test('leaderboard requires 3 games', () async {
    for (var i = 0; i < 3; i++) {
      server.stats.record('g', [
        const StatEntry('p1', 'A', 1, false, 1),
        const StatEntry('p2', 'B', 2, false, 2),
        const StatEntry('', '电脑', 0, true, 3),
      ]);
    }
    server.stats.record('g', [const StatEntry('p3', 'C', 1, false, 1), const StatEntry('p1', 'A', 1, false, 2)]);
    final a = await login('q');
    a.send({'t': 'leaderboard', 'game': 'g'});
    final rows = (await a.waitT(Msg.board))['rows'] as List;
    expect(rows.map((r) => r['name']), ['A', 'B']);
    expect(rows[0]['p'], 4);
    expect(rows[0]['w'], 3);
    expect(rows[0]['elo'], greaterThan(1500));
  });

  test('LAN discovery replies with name, port and fingerprint', () async {
    final u = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = Completer<Map>();
    u.listen((ev) {
      final d = u.receive();
      if (d != null && !got.isCompleted) got.complete(jsonDecode(utf8.decode(d.data)) as Map);
    });
    // UDP is lossy (Windows may drop the very first datagram): resend
    for (var i = 0; i < 15 && !got.isCompleted; i++) {
      u.send(utf8.encode(kDiscoveryHello), InternetAddress.loopbackIPv4, server.discoveryBoundPort!);
      await Future.any([got.future, Future.delayed(const Duration(milliseconds: 200))]);
    }
    final j = await got.future.timeout(const Duration(seconds: 3));
    expect(j['port'], port);
    expect(j['name'], 'Aurora 服务器');
    expect(j['fp'], server.identity.fingerprint.replaceAll(':', '').substring(0, 16));
    u.close();
  });

  test('console: say announces, kick disconnects, ban blocks the IP', () async {
    final a = await login('听众');
    server.announce('维护通知');
    expect((await a.waitT(Msg.toast))['msg'], contains('维护通知'));
    expect((await a.waitT(Msg.chatMsg))['system'], isTrue);
    final id = server.onlineClients.first.id;
    expect(server.kickClient(id, ban: true), isTrue);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(a.closed, isTrue);
    final s = await Socket.connect('127.0.0.1', port);
    final done = Completer<bool>();
    s.listen((_) {}, onDone: () => done.complete(true), onError: (_) => done.complete(true));
    expect(await done.future.timeout(const Duration(seconds: 3)), isTrue);
    expect(server.kickClient(99999), isFalse);
  });

  test('null placings: no stats but replay still saved', () async {
    // tictactoe may not implement placings yet; either way nothing crashes
    final a = await login('t', uid: 'uid-t');
    a.send({'t': 'create_room', 'game': 'tictactoe'});
    await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    a.send({'t': 'start'});
    for (;;) {
      final g = await a.wait((m) => m['t'] == Msg.game);
      final v = g['view'] as Map;
      if (g['over'] == true) break;
      if (v['turn'] == g['seat']) a.send({'t': 'action', 'a': {'cell': (v['cells'] as List).indexOf(-1)}});
    }
    for (var i = 0; i < 40 && server.replays.count == 0; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(server.replays.count, 1);
  });

  test('ReplayStore prunes beyond keep', () async {
    final d = Directory('${tmp.path}/prune');
    final st = ReplayStore(d, keep: 2);
    for (var i = 0; i < 4; i++) {
      final id = st.newId();
      await st.save({
        'v': 1,
        'meta': {'id': id, 'game': 'x', 'uids': <String>[]},
        'tracks': [],
        'logs': []
      });
      await Future.delayed(const Duration(milliseconds: 5));
    }
    expect(st.count, 2);
    expect(d.listSync().whereType<File>().where((f) => f.path.endsWith('.json.gz')).length, 2);
    expect(ReplayStore(d, keep: 2).count, 2);
    expect(Uint8List.fromList(base64.decode((await st.chunks(st.list().first['id'] as String))!.first)).take(2),
        [0x1f, 0x8b]);
  });
}
