import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/connection.dart';
import '../platform/local_session.dart';
import '../platform/replay_store.dart';
import '../platform/sfx.dart';
import '../voice/voice.dart';
import '../i18n/aurora_i18n.dart';

class ChatLine {
  final int from;
  final String name;
  final int avatar;
  final String text;
  final DateTime time;
  final bool system;
  ChatLine(
    this.from,
    this.name,
    this.avatar,
    this.text,
    this.time,
    this.system,
  );
}

/// Snapshot of the game state sent by the server for this client.
class GameState {
  final String game;
  final int seat;
  final List<String> names;
  final List<bool> bots;
  final List<int> avatars;
  final Map<String, dynamic> view;
  final bool over;

  /// game seat -> ms left on the turn clock when this state was received.
  final Map<int, int> deadlines;
  final DateTime received;
  GameState(
    this.game,
    this.seat,
    this.names,
    this.bots,
    this.avatars,
    this.view,
    this.over, {
    this.deadlines = const {},
    DateTime? received,
  }) : received = received ?? DateTime.now();
}

/// A quick emote/phrase shown as a floating bubble.
class EmoteEvent {
  final String name;
  final int avatar;
  final String text;
  final int seat;
  EmoteEvent(this.name, this.avatar, this.text, this.seat);
}

/// Global client state: profile, connection, lobby, room, game, chat, voice.
class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  final Connection conn = Connection();
  late final VoiceEngine voice = VoiceEngine(conn.sendVoice);

  // profile & settings
  String name = '';
  int avatar = 1;
  String themeId = 'majsoul';

  /// UI language. `zh` is Simplified Chinese and `en` is English.
  String language = 'zh';
  List<String> recentServers = [];
  double uiScale = 1.0;

  /// Random per-install identity (never shown); the server derives a stable
  /// player id from it for 战绩 / 回放.
  String uid = '';

  /// Sound effects (settings: 音效开关 / 音量).
  final Sfx sfx = Sfx();

  /// 收藏的游戏 / 最近玩过 (game ids, newest first).
  List<String> favoriteGames = [];
  List<String> recentGames = [];

  /// Active single-player session (no server needed), or null.
  LocalSession? local;

  // server features (from welcome)
  bool serverAi = false;
  String aiLabel = '';
  String pid = '';
  String publicWebUrl = '', publicNativeAddress = '';
  int? webPort;
  AuroraInvitation? pendingInvitation;
  Map<String, dynamic>? dailyState;

  // replays / stats (filled by server replies)
  List<ReplayMeta>? replayList;
  bool replayListMine = false;
  Map<String, dynamic>? myStats;
  final Map<String, List<Map<String, dynamic>>> leaderboards = {};
  final Map<String, List<String?>> _chunks = {};
  final Map<String, Completer<Uint8List>> _replayWaits = {};

  final _emotes = StreamController<EmoteEvent>.broadcast();
  Stream<EmoteEvent> get emotes => _emotes.stream;

  // result sound bookkeeping
  (int, int)? _tallyAtStart;
  bool _awaitResult = false;
  Timer? _resultTimer;
  DateTime _lastGameMsg = DateTime.fromMillisecondsSinceEpoch(0);

  // connection
  ConnState state = ConnState.disconnected;
  String address = '';
  String? lastError;

  /// Address whose pinned server key didn't match on the last attempt.
  String? keyMismatch;

  /// Forget the pinned key for [addr] and reconnect (user confirmed).
  Future<void> trustNewServerKey(String addr) async {
    await prefs.remove('pin:${addr.toLowerCase()}');
    keyMismatch = null;
    await connect(addr);
  }

  String? get serverFingerprint => conn.serverFingerprint;
  String serverName = '';
  int myId = 0;
  String _token = '';
  DateTime _resumeSaved = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wantConnected = false;
  Timer? _reconnectTimer;

  // lobby
  List<Map<String, dynamic>> rooms = [];
  int onlineCount = 0;
  List<Map<String, dynamic>> games = [];

  // room
  Map<String, dynamic>? room;
  GameState? game;

  /// After a game ends the result stays up for [autoLeaveDelay], then the
  /// room screen (seats / ready) comes back. Non-null while counting down.
  DateTime? autoLeaveAt;
  static const autoLeaveDelay = Duration(seconds: 3);
  Timer? _autoLeaveTimer;
  bool _leftFinished =
      false; // finished game already dismissed: don't show it again
  final List<ChatLine> chat = [];
  int unreadChat = 0;

  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  Future<void> load({String? initialLanguage}) async {
    prefs = await SharedPreferences.getInstance();
    name = prefs.getString('name') ?? '';
    avatar =
        prefs.getInt('avatar') ?? 1 + DateTime.now().millisecond % kAvatarCount;
    themeId = prefs.getString('theme') ?? 'majsoul';
    final systemLanguage =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en'
        ? 'en'
        : 'zh';
    language =
        initialLanguage ??
        prefs.getString('language') ??
        (kIsWeb ? systemLanguage : 'zh');
    currentAuroraLanguage = AuroraLanguage.fromCode(language);
    recentServers = prefs.getStringList('servers') ?? [];
    uiScale = prefs.getDouble('uiScale') ?? 1.0;
    if (kIsWebTransport)
      pendingInvitation = AuroraInvitation.parse(Uri.base.toString());
    uid = prefs.getString('uid') ?? '';
    if (uid.length != 64) {
      final r = Random.secure();
      uid = [
        for (var i = 0; i < 32; i++)
          r.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      prefs.setString('uid', uid);
    }
    sfx.enabled = prefs.getBool('sfx') ?? true;
    sfx.volume = prefs.getDouble('sfxVolume') ?? 0.7;
    favoriteGames = prefs.getStringList('favGames') ?? [];
    recentGames = prefs.getStringList('recentGames') ?? [];
    voice.noiseLevel = prefs.getDouble('noise') ?? 2;
    voice.setNoiseLevel(voice.noiseLevel);
    voice.pushToTalk = prefs.getBool('ptt') ?? false;
    voice.outputVolume = prefs.getDouble('volume') ?? 1.0;
    voice.inputGain = prefs.getDouble('micGain') ?? 1.0;
    conn.messages.listen(_onMessage);
    conn.voice.listen((v) => voice.onRemoteAudio(v.$1, v.$2));
    conn.closed.listen(_onClosed);
  }

  bool get hasProfile => name.isNotEmpty;

  void touch() => notifyListeners();

  Map<String, dynamic>? gameInfo(String id) {
    for (final g in games) {
      if (g['id'] == id) {
        if (currentAuroraLanguage == AuroraLanguage.zhCN) return g;
        return {
          ...g,
          'name': auroraGameText('${g['name']}'),
          'category': auroraCategory('${g['category']}'),
          'description': auroraEnglish['${g['description']}'] ?? g['description'],
        };
      }
    }
    return null;
  }

  void setTheme(String id) {
    themeId = id;
    prefs.setString('theme', id);
    notifyListeners();
  }

  AuroraLanguage get auroraLanguage => AuroraLanguage.fromCode(language);

  void setLanguage(String code) {
    final next = AuroraLanguage.fromCode(code).code;
    if (language == next &&
        currentAuroraLanguage == AuroraLanguage.fromCode(next))
      return;
    language = next;
    currentAuroraLanguage = AuroraLanguage.fromCode(next);
    prefs.setString('language', next);
    notifyListeners();
  }

  void setUiScale(double v) {
    uiScale = v;
    prefs.setDouble('uiScale', v);
    notifyListeners();
  }

  void setNoise(double v) {
    voice.setNoiseLevel(v);
    prefs.setDouble('noise', v);
  }

  void setOutputVolume(double v) {
    voice.setOutputVolume(v);
    prefs.setDouble('volume', v);
  }

  void setInputGain(double v) {
    voice.setInputGain(v);
    prefs.setDouble('micGain', v);
  }

  void setSfx(bool on) {
    sfx.enabled = on;
    prefs.setBool('sfx', on);
    notifyListeners();
  }

  void setSfxVolume(double v) {
    sfx.volume = v;
    prefs.setDouble('sfxVolume', v);
    notifyListeners();
  }

  bool isFavorite(String id) => favoriteGames.contains(id);

  void toggleFavorite(String id) {
    if (!favoriteGames.remove(id)) favoriteGames.insert(0, id);
    prefs.setStringList('favGames', favoriteGames);
    notifyListeners();
  }

  void noteGamePlayed(String id) {
    if (id.isEmpty) return;
    recentGames.remove(id);
    recentGames.insert(0, id);
    if (recentGames.length > 8) recentGames = recentGames.sublist(0, 8);
    prefs.setStringList('recentGames', recentGames);
  }

  // ---- single player ----
  void startLocal(LocalSession s) {
    if (!identical(local, s)) local?.dispose();
    local = s;
    s.onToast = toast;
    s.onSound = sfx.play;
    s.onEmote = _emotes.add;
    noteGamePlayed(s.def.id);
    s.begin();
    notifyListeners();
  }

  void endLocal() {
    local?.dispose();
    local = null;
    notifyListeners();
  }

  /// Show one of my emotes (network: send it; local game: just show it).
  void sendEmote(int e) {
    if (e < 0 || e >= kEmotes.length) return;
    if (local != null) {
      _emotes.add(EmoteEvent(name, avatar, kEmotes[e], local!.humanSeat));
      sfx.play(SfxKind.emote);
      return;
    }
    send({'t': Msg.emote, 'e': e});
  }

  // ---- replays / stats ----
  void requestReplays({bool mine = false}) {
    replayListMine = mine;
    replayList = null;
    send({'t': Msg.listReplays, 'mine': mine});
    notifyListeners();
  }

  /// Downloads a replay (gzip bytes). Completes with an error on timeout.
  Future<Uint8List> fetchReplayGz(String id) {
    final w = _replayWaits[id];
    if (w != null) return w.future;
    final c = _replayWaits[id] = Completer<Uint8List>();
    _chunks.remove(id);
    send({'t': Msg.getReplay, 'id': id});
    return c.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () {
        _replayWaits.remove(id);
        _chunks.remove(id);
        throw TimeoutException('下载回放超时');
      },
    );
  }

  Future<Replay> fetchReplay(String id) async =>
      decodeReplayGz(await fetchReplayGz(id));

  void _onReplayChunk(Map<String, dynamic> m) {
    final id = asStr(m['id']);
    final n = asInt(m['n'], 0), i = asInt(m['i'], -1);
    if (n <= 0 || n > 2000 || i < 0 || i >= n) return;
    final parts = _chunks.putIfAbsent(id, () => List<String?>.filled(n, null));
    if (parts.length != n) return;
    parts[i] = asStr(m['data']);
    if (parts.any((p) => p == null)) return;
    _chunks.remove(id);
    final c = _replayWaits.remove(id);
    if (c == null || c.isCompleted) return;
    try {
      final b = BytesBuilder(copy: false);
      for (final p in parts) {
        b.add(base64.decode(p!));
      }
      c.complete(b.takeBytes());
    } catch (e) {
      c.completeError(FormatException('回放数据损坏：$e'));
    }
  }

  void requestStats() => send({'t': Msg.myStats});
  void requestLeaderboard(String game) =>
      send({'t': Msg.leaderboard, 'game': game});

  // ---- room v3 helpers ----
  Map<String, dynamic> get caps =>
      (room?['caps'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic>? get pendingRequest =>
      (room?['request'] as Map?)?.cast<String, dynamic>();
  int get botLevel => asInt(room?['botLevel'], 1).clamp(0, 2);
  List<Map<String, dynamic>> get tally => [
    for (final t in (room?['tally'] as List? ?? const []))
      if (t is Map) t.cast<String, dynamic>(),
  ];
  bool get myAuto =>
      mySeat >= 0 && mySeat < seats.length && seats[mySeat]['auto'] == true;

  Map<String, dynamic>? _myTallyRow() {
    for (final t in tally) {
      if (pid.isNotEmpty ? t['pid'] == pid : t['name'] == name) return t;
    }
    return null;
  }

  (int, int) _myTally() {
    final r = _myTallyRow();
    return (asInt(r?['games'], 0), asInt(r?['wins'], 0));
  }

  void _checkResult() {
    if (!_awaitResult) return;
    final start = _tallyAtStart ?? (0, 0);
    final now = _myTally();
    if (now.$1 > start.$1) {
      _awaitResult = false;
      _resultTimer?.cancel();
      sfx.play(now.$2 > start.$2 ? SfxKind.win : SfxKind.lose);
      _tallyAtStart = now;
    }
  }

  void setPtt(bool v) {
    voice.pushToTalk = v;
    prefs.setBool('ptt', v);
    notifyListeners();
  }

  String? saveProfile(String newName, int newAvatar) {
    final err = validateName(newName);
    if (err != null) return err;
    name = newName.trim();
    avatar = newAvatar.clamp(1, kAvatarCount);
    prefs.setString('name', name);
    prefs.setInt('avatar', avatar);
    if (state == ConnState.connected) {
      conn.send({'t': Msg.setProfile, 'name': name, 'avatar': avatar});
    }
    notifyListeners();
    return null;
  }

  Future<void> connect(String addr) async {
    final invite = AuroraInvitation.parse(addr);
    if (invite != null) {
      pendingInvitation = invite;
      if (!kIsWebTransport && invite.nativeAddress.isEmpty) {
        lastError = '该邀请没有客户端地址，请向房主获取客户端地址后连接';
        notifyListeners();
        return;
      }
      addr = kIsWebTransport ? invite.webUrl : invite.nativeAddress;
    }
    address = addr.trim();
    _token = '';
    try {
      final saved =
          jsonDecode(prefs.getString('resume:$address') ?? '{}') as Map;
      final at = asInt(saved['at'], 0);
      if (saved['name'] == name &&
          DateTime.now().millisecondsSinceEpoch - at < 600000)
        _token = asStr(saved['token']);
    } catch (_) {}
    _wantConnected = true;
    lastError = null;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _reconnectTimer?.cancel();
    state = ConnState.connecting;
    notifyListeners();
    try {
      final key = await conn.connect(address);
      // Trust on first use: pin the server key per address (like SSH known_hosts).
      final pinKey = 'pin:${address.toLowerCase()}';
      final pinned = prefs.getString(pinKey);
      if (pinned == null) {
        await prefs.setString(pinKey, key);
      } else if (pinned != key) {
        _wantConnected = false;
        await conn.close();
        state = ConnState.disconnected;
        keyMismatch = address;
        lastError =
            '警告：$address 的服务器身份已变化（指纹 ${conn.serverFingerprint}）。'
            '可能是服务器重装了，也可能有人在冒充/窃听。确认安全后可在连接页选择"信任新身份"。';
        notifyListeners();
        return;
      }
      keyMismatch = null;
      conn.send({
        't': Msg.hello,
        'ver': kProtocolVersion,
        'name': name,
        'avatar': avatar,
        'token': _token,
        'uid': uid,
      });
    } catch (e) {
      state = ConnState.disconnected;
      lastError = '无法连接到 $address：${_friendly(e)}';
      notifyListeners();
      if (_wantConnected && myId != 0) _scheduleReconnect();
    }
  }

  String _friendly(Object e) {
    if (e is ConnectException) return e.message;
    final s = e.toString();
    if (s.contains('timed out') || s.contains('超时')) return '连接超时';
    if (s.contains('refused') || s.contains('拒绝')) return '连接被拒绝（服务器未启动或端口错误）';
    if (s.contains('Failed host lookup')) return '无法解析地址';
    return s.replaceFirst('SocketException: ', '');
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_wantConnected && state == ConnState.disconnected) _doConnect();
    });
  }

  void _onClosed(String reason) {
    state = ConnState.disconnected;
    if (_wantConnected) {
      lastError = '$reason，正在重连…';
      _scheduleReconnect();
    }
    voice.setMic(false);
    notifyListeners();
  }

  Future<void> resumeConnection() async {
    if (_wantConnected && state != ConnState.connecting) await _doConnect();
  }

  Future<void> disconnect() async {
    await prefs.remove('resume:$address');
    dailyState = null;
    _wantConnected = false;
    _reconnectTimer?.cancel();
    await voice.setMic(false);
    await conn.close();
    state = ConnState.disconnected;
    room = null;
    game = null;
    rooms = [];
    myId = 0;
    _token = '';
    chat.clear();
    notifyListeners();
  }

  void send(Map<String, dynamic> msg) => conn.send(msg);
  void action(Map<String, dynamic> a) {
    final l = local;
    if (l != null) {
      l.act(a);
      return;
    }
    conn.send({'t': Msg.action, 'a': a});
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case Msg.welcome:
        final firstConnect = state != ConnState.connected;
        state = ConnState.connected;
        lastError = null;
        myId = asInt(m['id'], 0);
        _token = asStr(m['token']);
        prefs.setString(
          'resume:$address',
          jsonEncode({
            'token': _token,
            'at': DateTime.now().millisecondsSinceEpoch,
            'name': name,
          }),
        );
        publicWebUrl = asStr(m['publicWebUrl']);
        publicNativeAddress = asStr(m['publicNativeAddress']);
        webPort = m['webPort'] is int ? m['webPort'] as int : null;
        serverName = asStr(m['server']);
        games = [
          for (final g in (m['games'] as List? ?? []))
            (g as Map).cast<String, dynamic>(),
        ];
        serverAi = m['ai'] == true;
        aiLabel = asStr(m['aiLabel']);
        pid = asStr(m['pid']);
        if (firstConnect) {
          recentServers.remove(address);
          recentServers.insert(0, address);
          if (recentServers.length > 8)
            recentServers = recentServers.sublist(0, 8);
          prefs.setStringList('servers', recentServers);
        }
      case Msg.dailyState:
        dailyState = m;
      case Msg.rooms:
        rooms = [
          for (final r in (m['rooms'] as List? ?? []))
            (r as Map).cast<String, dynamic>(),
        ];
        onlineCount = asInt(m['online'], 0);
      case Msg.room:
        final r = m['room'];
        final prevId = room?['id'];
        final wasPlaying = room?['playing'] == true;
        room = r == null ? null : (r as Map).cast<String, dynamic>();
        if (room == null) {
          game = null;
          chat.clear();
          voice.setMic(false);
          voice.reset();
        } else if (prevId != room!['id']) {
          chat.clear();
          game = null;
        }
        if (room != null && pendingInvitation?.room == room!['id'])
          pendingInvitation = null;
        if (room != null && room!['hasGame'] != true) game = null;
        if (game == null) _cancelAutoLeave();
        if (room == null || prevId != room!['id']) _leftFinished = false;
        if (room != null &&
            room!['playing'] == true &&
            (!wasPlaying || prevId != room!['id'])) {
          // a match started (or I joined one)
          noteGamePlayed(asStr(room!['game']));
          if (prevId == room!['id'] && mySeat >= 0) sfx.play(SfxKind.start);
          _tallyAtStart = _myTally();
        }
        _checkResult();
      case Msg.game:
        if (m['game'] == null) {
          game = null;
          _cancelAutoLeave();
        } else if (m['over'] == true && _leftFinished) {
          // result already shown and dismissed (e.g. resent on reconnect)
        } else {
          if (m['over'] != true) _leftFinished = false;
          final prev = game;
          game = GameState(
            asStr(m['game']),
            asInt(m['seat']),
            [for (final n in (m['names'] as List? ?? [])) '$n'],
            [for (final b in (m['bots'] as List? ?? [])) b == true],
            asIntList(m['avatars']),
            (m['view'] as Map).cast<String, dynamic>(),
            m['over'] == true,
            deadlines: {
              for (final e in ((m['deadlines'] as Map?) ?? const {}).entries)
                int.parse('${e.key}'): asInt(e.value, 0),
            },
          );
          _gameSounds(prev, game!);
          if (game!.over) {
            _scheduleAutoLeave();
          } else {
            _cancelAutoLeave();
          }
        }
      case Msg.chatMsg:
        chat.add(
          ChatLine(
            asInt(m['from'], 0),
            asStr(m['name']),
            asInt(m['avatar'], 0),
            asStr(m['text']),
            DateTime.fromMillisecondsSinceEpoch(asInt(m['ts'], 0)),
            m['system'] == true,
          ),
        );
        if (chat.length > 300) chat.removeRange(0, chat.length - 300);
        unreadChat++;
      case Msg.emoteMsg:
        final e = asInt(m['e']);
        if (e < 0 || e >= kEmotes.length) return;
        final ev = EmoteEvent(
          asStr(m['name']),
          asInt(m['avatar'], 0),
          kEmotes[e],
          asInt(m['seat']),
        );
        chat.add(
          ChatLine(
            asInt(m['from'], 0),
            ev.name,
            ev.avatar,
            ev.text,
            DateTime.now(),
            false,
          ),
        );
        if (chat.length > 300) chat.removeRange(0, chat.length - 300);
        _emotes.add(ev);
        sfx.play(SfxKind.emote);
      case Msg.replays:
        replayList = [
          for (final r in (m['replays'] as List? ?? const []))
            if (r is Map) ReplayMeta.fromJson(r.cast<String, dynamic>()),
        ];
      case Msg.replayChunk:
        _onReplayChunk(m);
        return;
      case Msg.stats:
        myStats = (m['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
      case Msg.board:
        leaderboards[asStr(m['game'])] = [
          for (final r in (m['rows'] as List? ?? const []))
            if (r is Map) r.cast<String, dynamic>(),
        ];
      case Msg.error:
        _toasts.add(asStr(m['msg']));
        if (m['fatal'] == true) {
          _wantConnected = false;
          lastError = asStr(m['msg']);
        }
      case Msg.toast:
        _toasts.add(asStr(m['msg']));
      case Msg.pong:
        if (_token.isNotEmpty &&
            DateTime.now().difference(_resumeSaved).inSeconds >= 60) {
          _resumeSaved = DateTime.now();
          prefs.setString(
            'resume:$address',
            jsonEncode({
              'token': _token,
              'at': _resumeSaved.millisecondsSinceEpoch,
              'name': name,
            }),
          );
        }
        return;
    }
    notifyListeners();
  }

  void _gameSounds(GameState? prev, GameState now) {
    final t = DateTime.now();
    final quiet = t.difference(_lastGameMsg).inMilliseconds >= 1500;
    _lastGameMsg = t;
    if (now.seat < 0) return;
    if (now.over) {
      if (prev != null && !prev.over && prev.game == now.game) {
        // win/lose comes from the room tally (sent right after); fall back to
        // a neutral "game over" sound if it doesn't change.
        _awaitResult = true;
        _resultTimer?.cancel();
        _resultTimer = Timer(const Duration(milliseconds: 1800), () {
          if (_awaitResult) {
            _awaitResult = false;
            sfx.play(SfxKind.over);
          }
        });
        _checkResult();
      }
      return;
    }
    final mine = now.deadlines.containsKey(now.seat);
    if (mine &&
        (prev == null || prev.over || !prev.deadlines.containsKey(now.seat))) {
      sfx.play(SfxKind.turn);
    } else if (quiet && prev != null && !prev.over) {
      sfx.play(SfxKind.tick);
    }
  }

  void _scheduleAutoLeave() {
    if (_autoLeaveTimer != null) return;
    autoLeaveAt = DateTime.now().add(autoLeaveDelay);
    _autoLeaveTimer = Timer(autoLeaveDelay, leaveFinishedGame);
  }

  void _cancelAutoLeave() {
    _autoLeaveTimer?.cancel();
    _autoLeaveTimer = null;
    autoLeaveAt = null;
  }

  /// Close the finished game's board and go back to the room (seats / ready).
  void leaveFinishedGame() {
    _cancelAutoLeave();
    if (game == null || !game!.over) return;
    game = null;
    _leftFinished = true;
    notifyListeners();
  }

  // ---- room helpers ----
  bool get isHost => room != null && room!['host'] == myId;

  List<Map<String, dynamic>> get seats => [
    for (final s in (room?['seats'] as List? ?? []))
      (s as Map).cast<String, dynamic>(),
  ];

  int get mySeat =>
      seats.indexWhere((s) => (s['client'] as Map?)?['id'] == myId);

  Map<String, dynamic>? memberById(int id) {
    for (final m in (room?['members'] as List? ?? [])) {
      if ((m as Map)['id'] == id) return m.cast<String, dynamic>();
    }
    return null;
  }

  void toast(String s) => _toasts.add(auroraT(s));

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _autoLeaveTimer?.cancel();
    _resultTimer?.cancel();
    local?.dispose();
    voice.dispose();
    conn.close();
    super.dispose();
  }
}
