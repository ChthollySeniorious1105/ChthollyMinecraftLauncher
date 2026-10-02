import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../native/native.dart';
import '../net/connection.dart';
import 'files.dart';
import 'screen_share.dart';
import '../theme/themes.dart' show avatarColors;
import 'avatars.dart';
import 'settings.dart';

class Member {
  final int id;
  String username, display, bio, status;
  int role, color, avatar;
  bool online;
  String avatarHash = ''; // custom image ('' = palette avatar)
  String statusText = '', statusEmoji = '';
  List<int> roles = [];
  Member(this.id, this.username, this.display, this.role, this.color, this.avatar, this.bio, this.online, this.status);

  factory Member.fromJson(Map<String, dynamic> j) => Member(asInt(j['id']), asStr(j['user']), asStr(j['display']), asInt(j['role']),
      asInt(j['color']), asInt(j['avatar']), asStr(j['bio']), asBool(j['online']), asStr(j['status'], 'offline'))
    ..avatarHash = asStr(j['avh'])
    ..statusText = asStr(j['stxt'])
    ..statusEmoji = asStr(j['semo'])
    ..roles = [for (final r in (j['roles'] as List? ?? const [])) asInt(r)];

  void update(Map<String, dynamic> j) {
    username = asStr(j['user'], username);
    display = asStr(j['display'], display);
    role = asInt(j['role'], role);
    color = asInt(j['color'], color);
    avatar = asInt(j['avatar'], avatar);
    bio = asStr(j['bio'], bio);
    avatarHash = asStr(j['avh']);
    statusText = asStr(j['stxt']);
    statusEmoji = asStr(j['semo']);
    if (j.containsKey('roles')) roles = [for (final r in (j['roles'] as List)) asInt(r)];
    if (j.containsKey('online')) online = asBool(j['online']);
    if (j.containsKey('status')) status = asStr(j['status'], status);
  }

  /// Effective presence shown to others.
  String get presence => !online ? 'offline' : status;
}

class ChannelInfo {
  final int id;
  String name, kind, topic;
  int position, slowmode, bitrate, lastId;
  int perms = Perm.all; // my effective permissions here (from the server)
  List<Overwrite> overwrites = [];
  List<int> members = []; // DM participants
  ChannelInfo(this.id, this.name, this.kind, this.topic, this.position, this.slowmode, this.bitrate, this.lastId);
  factory ChannelInfo.fromJson(Map<String, dynamic> j) => ChannelInfo(asInt(j['id']), asStr(j['name']), asStr(j['kind']),
      asStr(j['topic']), asInt(j['pos']), asInt(j['slow']), asInt(j['bitrate'], 64000), asInt(j['last']))
    ..perms = asInt(j['perms'], Perm.all)
    ..overwrites = [for (final o in (j['ow'] as List? ?? const [])) Overwrite.fromJson(o as Map<String, dynamic>)]
    ..members = [for (final m in (j['members'] as List? ?? const [])) asInt(m)];
  bool get isVoice => kind == ChannelKind.voice;
  bool get isDm => kind == ChannelKind.dm;
  bool can(int p) => (perms & p) == p;
}

/// A file attached to a message.
class Attachment {
  final String id, name;
  final int size, w, h, at, expires;
  final bool thumb;
  bool gone;
  Attachment(this.id, this.name, this.size, this.w, this.h, this.at, this.expires, this.thumb, this.gone);
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(asStr(j['id']), asStr(j['name']), asInt(j['size']), asInt(j['w']),
      asInt(j['h']), asInt(j['at']), asInt(j['exp']), asBool(j['thumb']), asBool(j['gone']));
  bool get isImage => thumb && w > 0 && h > 0;
  bool get expired => gone || (expires > 0 && DateTime.now().millisecondsSinceEpoch > expires);
}

/// A screen share in a voice channel.
class StreamInfo {
  final int uid;
  int channel, w, h, fps;
  String title;
  List<int> viewers;
  StreamInfo(this.uid, this.channel, this.w, this.h, this.fps, this.title, this.viewers);
  factory StreamInfo.fromJson(Map<String, dynamic> j) => StreamInfo(asInt(j['uid']), asInt(j['ch']), asInt(j['w']), asInt(j['h']), asInt(j['fps']),
      asStr(j['title']), [for (final v in (j['viewers'] as List? ?? const [])) asInt(v)]);
}

class Message {
  final int id, ch, uid, ts, reply;
  String text;
  int edited;
  Map<String, List<int>> reactions;
  bool pinned = false;
  bool everyone = false; // the author may notify @everyone
  List<Attachment> attachments = const [];
  bool pending; // optimistic local echo
  final String nonce;
  Message(this.id, this.ch, this.uid, this.text, this.ts, this.edited, this.reply, this.reactions, {this.pending = false, this.nonce = ''});

  factory Message.fromJson(Map<String, dynamic> j) {
    final r = <String, List<int>>{};
    final rj = j['react'];
    if (rj is Map) {
      for (final e in rj.entries) {
        r['${e.key}'] = [for (final u in (e.value as List)) asInt(u)];
      }
    }
    return Message(asInt(j['id']), asInt(j['ch']), asInt(j['uid']), asStr(j['text']), asInt(j['ts']), asInt(j['edited']), asInt(j['reply']), r)
      ..pinned = asBool(j['pin'])
      ..everyone = asBool(j['ev'])
      ..attachments = [for (final a in (j['att'] as List? ?? const [])) Attachment.fromJson((a as Map).cast<String, dynamic>())];
  }
}

class ChannelHistory {
  final List<Message> messages = [];
  bool loaded = false, loading = false, more = true;
  bool detached = false; // showing an older window (after a jump), not the live end
  int unread = 0, mentions = 0;
}

class VoiceUser {
  final int id;
  int channel;
  bool mute, deaf, serverMute;
  VoiceUser(this.id, this.channel, this.mute, this.deaf, this.serverMute);
}

class GpuProvider {
  final String id, label, kind, vendor;
  GpuProvider(this.id, this.label, this.kind, this.vendor);
}

/// Application state: connection, server data, voice, settings.
class AppState extends ChangeNotifier {
  final Native native;
  final Settings settings;
  final Connection conn = Connection();
  AppState(this.native, this.settings) {
    avatars = AvatarCache(Directory('${settings.directory}${Platform.pathSeparator}avatars'), (uid, h) {
      conn.send({'t': Msg.getAvatar, 'id': uid, 'h': h});
    });
    files = FileManager(this);
    screen = ScreenShare(this);
  }

  late final AvatarCache avatars;
  late final FileManager files;
  late final ScreenShare screen;

  /// Unsent composer text per channel (survives switching channels).
  final Map<int, String> drafts = {};

  /// Incremented to move keyboard focus into the search box (Ctrl+F).
  final ValueNotifier<int> focusSearch = ValueNotifier(0);

  void markAllRead() {
    for (final h in histories.values) {
      h.unread = 0;
      h.mentions = 0;
    }
    notifyListeners();
  }

  /// Search results / pinned messages (UI listens to [notifyListeners]).
  List<Message> searchResults = [];
  String searchQuery = '';
  bool searching = false, searchMore = false;
  final Map<int, List<Message>> pins = {};

  /// Set when the chat should scroll to (and flash) a message after a jump.
  final ValueNotifier<(int, int)?> jumpTo = ValueNotifier(null); // (channel, message id)

  // ---- connection
  ConnState state = ConnState.disconnected;
  String? address;
  SavedServer? saved;
  String? lastError;
  bool authed = false;
  bool _manualDisconnect = false;
  Timer? _reconnect;
  int _reconnectTry = 0;

  /// Set when the pinned key differs: the UI asks whether to trust the new one.
  String? identityMismatch;
  String fingerprint = '';

  // ---- server data
  int me = 0;
  String serverName = '';
  String motd = '';
  String regMode = RegMode.open;
  bool serverHasPass = false;
  final Map<int, Member> members = {};
  final Map<int, ChannelInfo> channels = {};
  final Map<int, RoleDef> roles = {};
  final Map<int, StreamInfo> streams = {}; // by streamer uid
  int basePerms = Perm.all; // my server-wide permissions
  int fileDays = kDefaultFileDays, fileMaxMB = kMaxFileBytes ~/ (1024 * 1024), storageMB = kDefaultStorageMB;
  Map<String, dynamic> storage = {};
  final Map<int, ChannelHistory> histories = {};
  final Map<int, VoiceUser> voice = {};
  final Map<int, Map<int, DateTime>> typing = {}; // ch -> uid -> until
  int? currentChannel;
  int? voiceChannel; // the one I'm in
  String myStatus = 'online';

  // ---- voice state
  bool selfMute = false, selfDeaf = false;
  bool speaking = false;
  final Set<int> talking = {};
  Map<int, double> userLevels = {};
  Timer? _meter;
  bool micTest = false;
  String? audioError;
  String inputDeviceName = '', outputDeviceName = '';

  // voice changer
  Map<String, dynamic> vcStatus = {'state': 0};
  Map<String, dynamic> gpu = {};

  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;
  final _mentions = StreamController<(Message, ChannelInfo)>.broadcast();
  Stream<(Message, ChannelInfo)> get mentions => _mentions.stream;

  /// Results of admin requests the UI waits for.
  final _inviteCodes = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get inviteCodes => _inviteCodes.stream;
  List<Map<String, dynamic>> bans = [];

  /// "@user " text to insert into the composer (member context menu → mention).
  final ValueNotifier<String?> mentionRequest = ValueNotifier(null);

  // hotkey capture (settings UI)
  void Function(int vk, int mods)? onHotkeyCaptured;

  StreamSubscription? _msgSub, _voiceSub, _closeSub, _nativeSub;

  @override
  void notifyListeners() {
    _syncOverlay();
    super.notifyListeners();
  }

  Member? get myMember => members[me];
  bool get isOwner => (myMember?.role ?? 0) >= Role.owner;
  bool can(int perm) => (basePerms & perm) == perm;

  /// Any moderation / management permission (shows the admin menu entries).
  bool get isAdmin => (basePerms & (Perm.manageServer | Perm.manageChannels | Perm.manageRoles | Perm.banMembers | Perm.createInvite)) != 0;

  int topPosition(Member? m) => m == null ? 0 : Perms.top(roles, m.roles, owner: m.role == Role.owner);
  int get myTop => topPosition(myMember);

  /// Can I act on [m] with [perm] (role hierarchy like the server)?
  bool canModerate(Member m, int perm) => m.id != me && m.role != Role.owner && can(perm) && myTop > topPosition(m);

  /// Highest coloured role of a member (name colour).
  RoleDef? colorRole(Member m) {
    RoleDef? best;
    for (final id in m.roles) {
      final r = roles[id];
      if (r != null && r.color != 0 && (best == null || r.position > best.position)) best = r;
    }
    return best;
  }

  /// Highest hoisted role (member list group).
  RoleDef? hoistRole(Member m) {
    RoleDef? best;
    for (final id in m.roles) {
      final r = roles[id];
      if (r != null && r.hoist && (best == null || r.position > best.position)) best = r;
    }
    return best;
  }

  List<RoleDef> get sortedRoles => roles.values.toList()..sort((a, b) => b.position.compareTo(a.position));

  /// The other participant of a DM.
  Member? dmPartner(ChannelInfo c) => members[c.members.firstWhere((x) => x != me, orElse: () => 0)];

  String channelTitle(ChannelInfo c) => c.isDm ? (dmPartner(c)?.display ?? '私信') : c.name;

  void toast(String s) => _toasts.add(s);

  // ================================================================ speaker overlay

  bool _overlayHintShown = false;
  String _overlayKey = '';
  final Map<int, String> _overlayAvatarSent = {};

  void setOverlay(bool on) {
    settings.overlay = on;
    settings.save();
    _syncOverlay(force: true);
    notifyListeners();
  }

  void applyOverlayConfig() {
    final s = settings;
    native.overlayConfig(
        speakingOnly: s.overlaySpeakingOnly, opacity: s.overlayOpacity, scale: s.overlayScale, locked: s.overlayLocked, hideFocused: s.overlayHideFocused);
  }

  /// Letter-avatar background colour (same palette as the UI), ARGB.
  static int avatarArgb(Member? m) => avatarColors[(m?.avatar ?? 0) % avatarColors.length].toARGB32();

  /// Pushes the voice channel roster to the native overlay when it changed.
  void _syncOverlay({bool force = false}) {
    if (!native.available) return;
    final ch = voiceChannel == null ? null : channels[voiceChannel];
    final show = ch != null && settings.overlay && authed;
    final users = <(int, String, int, int)>[];
    if (ch != null) {
      final ids = [for (final v in voice.values) if (v.channel == ch.id) v.id]
        ..sort((a, b) => a == me ? -1 : (b == me ? 1 : (members[a]?.display ?? '').compareTo(members[b]?.display ?? '')));
      for (final id in ids) {
        final m = members[id];
        final v = voice[id]!;
        final self = id == me;
        final flags = (v.serverMute ? 4 : 0) | ((self ? selfDeaf : v.deaf) ? 2 : 0) | ((self ? selfMute : v.mute) ? 1 : 0) |
            (!self && userVolume(id) == 0 ? 1 : 0);
        users.add((id, m?.display ?? '#$id', avatarArgb(m), flags));
        // custom avatar images: send once per hash
        final h = m?.avatarHash ?? '';
        if (_overlayAvatarSent[id] != h) {
          final bytes = h.isEmpty ? null : avatars.get(id, h);
          if (h.isEmpty || bytes != null) {
            native.overlayAvatar(id, bytes);
            _overlayAvatarSent[id] = h;
          }
        }
      }
    }
    final key = '$show|${ch?.name}|$me|${users.map((u) => '${u.$1}:${u.$2}:${u.$3}:${u.$4}').join(',')}';
    if (!force && key == _overlayKey) return;
    _overlayKey = key;
    if (show) native.overlayRoster(ch.name, me, users);
    native.overlayShow(show);
  }

  /// Diagnostic log: %APPDATA%/Pulse/pulse.log (connection events, errors; never message content).
  void logEvent(String s) {
    try {
      final f = File('${settings.directory}${Platform.pathSeparator}pulse.log');
      if (f.existsSync() && f.lengthSync() > 1 << 20) f.renameSync('${f.path}.old');
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $s\n', mode: FileMode.append);
    } catch (_) {}
  }

  // ================================================================ lifecycle

  Future<void> start() async {
    _msgSub = conn.messages.listen(_onMessage);
    _voiceSub = conn.voice.listen(_onVoice);
    _closeSub = conn.closed.listen(_onClosed);
    files.start();
    if (native.available) {
      if (!native.init()) audioError = '音频系统初始化失败';
      _nativeSub = native.events.listen(_onNative);
      applyAudioSettings();
      applyHotkeys();
      applyOverlayConfig();
      avatars.addListener(_syncOverlay);
      native.startPlayback();
    } else {
      audioError = native.loadError;
    }
    // reconnect to the last server automatically if we have a session
    if (settings.lastServer.isNotEmpty) {
      final s = settings.find(settings.lastServer);
      if (s != null && settings.tokenFor(s) != null) unawaited(connectTo(s.address));
    }
  }

  @override
  void dispose() {
    screen.reset();
    _msgSub?.cancel();
    _voiceSub?.cancel();
    _closeSub?.cancel();
    _nativeSub?.cancel();
    _meter?.cancel();
    _reconnect?.cancel();
    conn.close();
    native.shutdown();
    super.dispose();
  }

  void applyAudioSettings() {
    final s = settings;
    native
      ..setInputGain(s.inputGain)
      ..setOutputVolume(s.outputVolume)
      ..setSoundVolume(s.sounds ? s.soundVolume : 0)
      ..setInputMode(s.inputMode)
      ..setVadThreshold(s.vadThreshold)
      ..setNoiseSuppression(s.noiseSuppression)
      ..setBitrate(s.bitrate)
      ..setPttReleaseMs(s.pttReleaseMs)
      ..setVcPitch(s.vcPitch)
      ..setVcRobot(s.vcRobot)
      ..setVcSpeaker(s.vcSpeaker)
      ..setDevice(capture: true, id: s.inputDevice)
      ..setDevice(capture: false, id: s.outputDevice);
    _applyVcMode();
  }

  void _applyVcMode() {
    final m = settings.vcMode;
    if (m == VcMode.ai) {
      final st = asInt(vcStatus['state']);
      if (st == VcState.off || st == VcState.error) {
        native.prewarmAi([for (final (_, b, e) in vcLatencyPresets) (b, e)]);
        native.configureAi(
            provider: settings.vcProvider, model: settings.vcModel, blockMs: settings.vcBlockMs, extraMs: settings.vcExtraMs, speaker: settings.vcSpeaker);
      }
    }
    native.setVcMode(m);
  }

  void reloadAi() {
    native.prewarmAi([for (final (_, b, e) in vcLatencyPresets) (b, e)]);
    native.configureAi(
        provider: settings.vcProvider, model: settings.vcModel, blockMs: settings.vcBlockMs, extraMs: settings.vcExtraMs, speaker: settings.vcSpeaker);
  }

  /// Frees AI models (GPU memory) after the AI voice has not been used for a while.
  /// Until then switching back to AI is instant (the engine keeps it warm).
  Timer? _aiIdleUnload;

  void setVoiceChangerMode(int mode) {
    settings.vcMode = mode;
    settings.save();
    _aiIdleUnload?.cancel();
    if (mode != VcMode.ai && asInt(vcStatus['state']) != VcState.off) {
      final minutes = settings.vcKeepLoadedMin;
      if (minutes == 0) {
        native.unloadAi();
      } else if (minutes > 0) {
        _aiIdleUnload = Timer(Duration(minutes: minutes), () {
          if (settings.vcMode != VcMode.ai) native.unloadAi();
        });
      }
    }
    _applyVcMode();
    notifyListeners();
  }

  void applyHotkeys() {
    final s = settings;
    native.setHotkey(HotkeySlot.ptt, s.pttKey.vk, s.pttKey.mods);
    native.setHotkey(HotkeySlot.mute, s.muteKey.vk, s.muteKey.mods);
    native.setHotkey(HotkeySlot.deafen, s.deafenKey.vk, s.deafenKey.mods);
    native.setHotkey(HotkeySlot.voiceChanger, s.vcKey.vk, s.vcKey.mods);
    native.setHotkey(HotkeySlot.overlay, s.overlayKey.vk, s.overlayKey.mods);
    native.enableHotkeys(s.globalHotkeys);
  }

  void refreshGpu() {
    gpu = native.gpuInfo();
    notifyListeners();
  }

  List<GpuProvider> get gpuProviders => [
        for (final p in (gpu['providers'] as List? ?? const []))
          GpuProvider(asStr(p['id']), asStr(p['label']), asStr(p['kind']), asStr(p['vendor'])),
      ];

  // ================================================================ connection

  Future<bool> connectTo(String addr) async {
    _manualDisconnect = false;
    _reconnect?.cancel();
    address = Connection.normalizeAddress(addr);
    saved = settings.find(address!) ?? SavedServer(address!);
    state = ConnState.connecting;
    lastError = null;
    identityMismatch = null;
    notifyListeners();
    logEvent('connecting to $address');
    try {
      final key = await conn.connect(address!);
      fingerprint = conn.serverFingerprint ?? '';
      final pin = saved!.pinnedKey;
      if (pin.isNotEmpty && pin != key) {
        // like SSH: refuse silently changed server identities
        identityMismatch = fingerprint;
        await conn.close();
        state = ConnState.disconnected;
        lastError = '服务器身份已改变！可能是服务器重装，也可能有人在冒充服务器。';
        notifyListeners();
        return false;
      }
      if (pin.isEmpty) saved!.pinnedKey = key;
      settings.remember(saved!);
      state = ConnState.connected;
      awaitingLogin = false;
      _reconnectTry = 0;
      settings.lastServer = address!;
      saved!.lastUsed = DateTime.now().millisecondsSinceEpoch;
      settings.save();
      final token = settings.tokenFor(saved!);
      if (token != null) {
        conn.send({'t': Msg.resume, 'token': token, 'ver': kProtocolVersion});
      }
      notifyListeners();
      return true;
    } catch (e) {
      state = ConnState.disconnected;
      lastError = '连接失败：${e is Exception ? e.toString().replaceFirst(RegExp(r'^\w*Exception:?\s*'), '') : e}';
      notifyListeners();
      return false;
    }
  }

  /// User confirmed the new server identity.
  Future<void> trustNewIdentity() async {
    if (saved == null) return;
    saved!.pinnedKey = '';
    settings.setToken(saved!, null); // never send an old token to an unverified server
    settings.save();
    identityMismatch = null;
    await connectTo(saved!.address);
  }

  /// Sends a pre-auth request, reconnecting first if the unauthenticated
  /// connection was dropped in the meantime (server login timeout, network blip).
  Future<void> _sendAuth(Map<String, dynamic> m) async {
    if (!conn.isOpen && address != null) {
      if (!await connectTo(address!)) return;
    }
    lastError = null;
    notifyListeners();
    conn.send(m);
  }

  void login(String user, String pass, {String serverPass = ''}) {
    saved?.username = user;
    _sendAuth({'t': Msg.login, 'user': user, 'pass': pass, 'serverPass': serverPass, 'ver': kProtocolVersion});
  }

  void register(String user, String pass, String display, {String invite = '', String serverPass = ''}) {
    saved?.username = user;
    _sendAuth({
      't': Msg.register,
      'user': user,
      'pass': pass,
      'display': display,
      'invite': invite,
      'serverPass': serverPass,
      'ver': kProtocolVersion,
    });
  }

  Future<void> disconnect({bool logout = false}) async {
    _manualDisconnect = true;
    awaitingLogin = false;
    _reconnect?.cancel();
    leaveVoice();
    if (logout) {
      conn.send({'t': Msg.logout});
      if (saved != null) settings.setToken(saved!, null);
      settings.lastServer = '';
      settings.save();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await conn.close();
    _resetServerState();
    state = ConnState.disconnected;
    notifyListeners();
  }

  void _resetServerState() {
    authed = false;
    screen.reset();
    roles.clear();
    streams.clear();
    me = 0;
    members.clear();
    channels.clear();
    histories.clear();
    voice.clear();
    typing.clear();
    currentChannel = null;
    voiceChannel = null;
    talking.clear();
    native.clearSpeakers();
    native.setTransmit(false);
  }

  /// True while the login / register form should stay visible even though the
  /// unauthenticated socket is gone (it reconnects on submit).
  bool awaitingLogin = false;

  void _onClosed(String reason) {
    logEvent('connection closed: $reason (authed=$authed manual=$_manualDisconnect)');
    final wasAuthed = authed;
    final inVoice = voiceChannel;
    _resetServerState();
    state = ConnState.disconnected;
    if (!wasAuthed && !_manualDisconnect && identityMismatch == null) {
      awaitingLogin = true;
      notifyListeners();
      return;
    }
    if (_manualDisconnect) {
      notifyListeners();
      return;
    }
    lastError = reason;
    notifyListeners();
    if (wasAuthed && address != null && saved != null && settings.tokenFor(saved!) != null) {
      // auto-reconnect with backoff, rejoin the voice channel afterwards
      final delay = Duration(seconds: [1, 2, 4, 8, 15, 30][_reconnectTry.clamp(0, 5)]);
      _reconnectTry++;
      _rejoinVoice = inVoice;
      _reconnect = Timer(delay, () => connectTo(address!));
    }
  }

  int? _rejoinVoice;

  // ================================================================ incoming

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case Msg.authOk:
        final tok = m['token'];
        if (tok is String && saved != null) {
          settings.setToken(saved!, tok);
          settings.save();
        }
        me = asInt(m['me']);
        authed = true;
      case Msg.authErr:
        lastError = asStr(m['msg']);
        logEvent('auth error: ${m['code']} $lastError');
        if (asStr(m['code']) == 'session' && saved != null) {
          settings.setToken(saved!, null);
          settings.save();
        }
        authed = false;
      case Msg.welcome:
        _onWelcome(m);
      case Msg.server:
        _serverInfo(m);
      case Msg.channels:
        basePerms = asInt(m['base'], basePerms);
        _setChannels(m['channels'] as List);
      case Msg.roles:
        roles
          ..clear()
          ..addAll({for (final r in (m['roles'] as List)) asInt(r['id']): RoleDef.fromJson(r as Map<String, dynamic>)});
      case Msg.dm:
        final c = ChannelInfo.fromJson(m['c'] as Map<String, dynamic>);
        channels[c.id] = channels[c.id] ?? c;
        channels[c.id]!
          ..members = c.members
          ..perms = c.perms
          ..lastId = c.lastId;
        if (asBool(m['open'])) selectChannel(c.id);
      case Msg.streams:
        _setStreams(m['streams'] as List);
      case Msg.keyframeRequest:
        screen.keyframeRequested();
        return;
      case Msg.mediaTicket:
        screen.onMediaTicket(asStr(m['ticket']));
        return;
      case Msg.uploadTicket:
        files.onUploadTicket(m);
        return;
      case Msg.fileTicket:
        files.onFileTicket(m);
        return;
      case Msg.thumbData:
        files.onThumb(asStr(m['id']), asStr(m['data']));
        return;
      case Msg.filesGone:
        final ids = {for (final x in (m['ids'] as List)) asStr(x)};
        for (final h in histories.values) {
          for (final msg in h.messages) {
            for (final a in msg.attachments) {
              if (ids.contains(a.id)) a.gone = true;
            }
          }
        }
      case Msg.storageData:
        storage = m;
      case Msg.member:
        final j = m['m'] as Map<String, dynamic>;
        final id = asInt(j['id']);
        final ex = members[id];
        if (ex == null) {
          members[id] = Member.fromJson(j);
        } else {
          ex.update(j);
        }
      case Msg.memberRemoved:
        members.remove(asInt(m['id']));
      case Msg.presence:
        final u = members[asInt(m['id'])];
        if (u != null) {
          u.online = asBool(m['online']);
          u.status = asStr(m['status'], u.status);
        }
      case Msg.message:
        _onChatMessage(m);
      case Msg.messageEdited:
        final msg = _findMsg(asInt(m['ch']), asInt(m['id']));
        if (msg != null) {
          msg.text = asStr(m['text']);
          msg.edited = asInt(m['edited']);
        }
      case Msg.messageDeleted:
        histories[asInt(m['ch'])]?.messages.removeWhere((x) => x.id == asInt(m['id']));
      case Msg.reaction:
        final msg = _findMsg(asInt(m['ch']), asInt(m['id']));
        if (msg != null) {
          final uids = [for (final u in (m['uids'] as List)) asInt(u)];
          if (uids.isEmpty) {
            msg.reactions.remove(asStr(m['e']));
          } else {
            msg.reactions[asStr(m['e'])] = uids;
          }
        }
      case Msg.historyData:
        _onHistory(m);
      case Msg.typingNotice:
        typing.putIfAbsent(asInt(m['ch']), () => {})[asInt(m['uid'])] = DateTime.now().add(const Duration(seconds: 6));
        Timer(const Duration(seconds: 6, milliseconds: 100), notifyListeners);
      case Msg.voiceUser:
        _onVoiceUser(m);
      case Msg.avatarData:
        try {
          avatars.put(asStr(m['h']), base64.decode(asStr(m['data'])));
        } catch (_) {}
        return;
      case Msg.searchResult:
        searchResults = [for (final j in (m['msgs'] as List)) Message.fromJson(j as Map<String, dynamic>)];
        searchMore = asBool(m['more']);
        searching = false;
      case Msg.pinsData:
        pins[asInt(m['ch'])] = [for (final j in (m['msgs'] as List)) Message.fromJson(j as Map<String, dynamic>)];
      case Msg.pinned:
        final msg = _findMsg(asInt(m['ch']), asInt(m['id']));
        msg?.pinned = asBool(m['on']);
        if (pins.containsKey(asInt(m['ch']))) conn.send({'t': Msg.pins, 'ch': asInt(m['ch'])});
      case Msg.inviteCode:
        _inviteCodes.add(m);
        return;
      case Msg.bans:
        bans = [for (final b in (m['bans'] as List)) b as Map<String, dynamic>];
      case Msg.toast:
        toast(asStr(m['msg']));
        return;
      case Msg.error:
        if (m['upload'] != null) files.onUploadError(asStr(m['upload']), asStr(m['msg']));
        if (m['file'] != null) files.onFileError(asStr(m['file']), asStr(m['msg']));
        toast(asStr(m['msg']));
        logEvent('server error: ${m['msg']} fatal=${m['fatal']}');
        if (asBool(m['fatal'])) {
          _manualDisconnect = true;
          lastError = asStr(m['msg']);
          if (saved != null) {
            settings.setToken(saved!, null);
            settings.save();
          }
        }
      case Msg.pong:
        return;
      default:
        return;
    }
    notifyListeners();
  }

  void _onWelcome(Map<String, dynamic> m) {
    avatars.resetInflight();
    me = asInt(m['me']);
    myStatus = asStr(m['myStatus'], 'online');
    _serverInfo(m['server'] as Map<String, dynamic>);
    basePerms = asInt(m['base'], Perm.all);
    roles
      ..clear()
      ..addAll({for (final r in (m['roles'] as List? ?? const [])) asInt(r['id']): RoleDef.fromJson(r as Map<String, dynamic>)});
    if (saved != null) {
      saved!.name = serverName;
      settings.save();
    }
    members
      ..clear()
      ..addAll({for (final j in (m['members'] as List)) asInt(j['id']): Member.fromJson(j as Map<String, dynamic>)});
    histories.clear();
    _setChannels(m['channels'] as List);
    voice.clear();
    for (final v in (m['voice'] as List)) {
      final j = v as Map<String, dynamic>;
      voice[asInt(j['id'])] = VoiceUser(asInt(j['id']), asInt(j['ch']), asBool(j['mute']), asBool(j['deaf']), asBool(j['smute']));
    }
    _setStreams(m['streams'] as List? ?? const []);
    authed = true;
    lastError = null;
    final texts = sortedChannels(ChannelKind.text);
    if (currentChannel == null || !channels.containsKey(currentChannel)) currentChannel = texts.isNotEmpty ? texts.first.id : null;
    if (currentChannel != null) selectChannel(currentChannel!);
    final rejoin = _rejoinVoice;
    _rejoinVoice = null;
    if (rejoin != null && channels.containsKey(rejoin)) joinVoice(rejoin);
  }

  void _serverInfo(Map<String, dynamic> s) {
    serverName = asStr(s['name'], serverName);
    motd = asStr(s['motd']);
    regMode = asStr(s['regMode'], regMode);
    serverHasPass = asBool(s['hasPass']);
    fileDays = asInt(s['fileDays'], fileDays);
    fileMaxMB = asInt(s['fileMaxMB'], fileMaxMB);
    storageMB = asInt(s['storageMB'], storageMB);
  }

  void _setStreams(List list) {
    streams
      ..clear()
      ..addAll({for (final j in list) asInt(j['uid']): StreamInfo.fromJson(j as Map<String, dynamic>)});
    screen.onStreams();
  }

  /// Streams in a voice channel.
  List<StreamInfo> streamsIn(int ch) => streams.values.where((s) => s.channel == ch).toList();

  void _setChannels(List list) {
    final seen = <int>{};
    for (final j in list) {
      final c = ChannelInfo.fromJson(j as Map<String, dynamic>);
      seen.add(c.id);
      final ex = channels[c.id];
      if (ex == null) {
        channels[c.id] = c;
      } else {
        ex
          ..name = c.name
          ..topic = c.topic
          ..position = c.position
          ..slowmode = c.slowmode
          ..bitrate = c.bitrate
          ..perms = c.perms
          ..overwrites = c.overwrites
          ..members = c.members;
      }
    }
    channels.removeWhere((id, _) => !seen.contains(id));
    histories.removeWhere((id, _) => !seen.contains(id));
    if (currentChannel != null && !channels.containsKey(currentChannel)) {
      final t = sortedChannels(ChannelKind.text);
      currentChannel = t.isNotEmpty ? t.first.id : null;
      if (currentChannel != null) selectChannel(currentChannel!);
    }
    if (voiceChannel != null && !channels.containsKey(voiceChannel)) leaveVoice();
    final vch = voiceChannel == null ? null : channels[voiceChannel];
    if (vch != null) native.setBitrate(vch.bitrate < settings.bitrate ? vch.bitrate : settings.bitrate);
  }

  List<ChannelInfo> sortedChannels(String kind) =>
      channels.values.where((c) => c.kind == kind).toList()..sort((a, b) => a.position.compareTo(b.position));

  Message? _findMsg(int ch, int id) {
    final h = histories[ch];
    if (h == null) return null;
    for (var i = h.messages.length - 1; i >= 0; i--) {
      if (h.messages[i].id == id) return h.messages[i];
    }
    return null;
  }

  bool mentionsMe(String text, {bool everyone = true}) {
    final u = myMember;
    if (u == null) return false;
    if (text.contains('@${u.username}') || text.contains('@${u.display}')) return true;
    if (everyone && (text.contains('@everyone') || text.contains('@全体'))) return true;
    // mentionable roles I have
    for (final id in u.roles) {
      final r = roles[id];
      if (r != null && r.mentionable && text.contains('@${r.name}')) return true;
    }
    return false;
  }

  void _onChatMessage(Map<String, dynamic> m) {
    final ch = asInt(m['ch']);
    final msg = Message.fromJson(m['m'] as Map<String, dynamic>);
    final h = histories.putIfAbsent(ch, () => ChannelHistory());
    final nonce = asStr(m['nonce']);
    if (nonce.isNotEmpty) h.messages.removeWhere((x) => x.pending && x.nonce == nonce);
    if (!h.detached) h.messages.add(msg);
    channels[ch]?.lastId = msg.id;
    typing[ch]?.remove(msg.uid);
    if (msg.uid == me) return;
    final c0 = channels[ch];
    final mention = (c0?.isDm ?? false) || mentionsMe(msg.text, everyone: msg.everyone);
    final focused = ch == currentChannel && windowFocused;
    if (!focused) {
      h.unread++;
      if (mention) h.mentions++;
    }
    if (mention && !focused && settings.notifyMentions) {
      native.playSound(Sound.mention);
      if (!windowFocused) native.flashWindow();
      final c = channels[ch];
      if (c != null) _mentions.add((msg, c));
    } else if (!focused && settings.notifyAll && myStatus != 'dnd') {
      native.playSound(Sound.message);
    }
  }

  bool windowFocused = true;

  void _onHistory(Map<String, dynamic> m) {
    final ch = asInt(m['ch']);
    final h = histories.putIfAbsent(ch, () => ChannelHistory());
    final msgs = [for (final j in (m['msgs'] as List)) Message.fromJson(j as Map<String, dynamic>)];
    final ids = {for (final x in h.messages) x.id};
    final fresh = msgs.where((x) => !ids.contains(x.id)).toList();
    final around = asInt(m['around']);
    if (around > 0 && h.messages.isNotEmpty && msgs.isNotEmpty && msgs.last.id < h.messages.first.id) {
      // jumped to a message older than what is loaded and not adjacent: replace the window
      // (avoids a hole in the timeline); "load newer" is not needed because the live tail is re-fetched below.
      h.messages
        ..clear()
        ..addAll(msgs);
      h.detached = true;
    } else {
      h.messages
        ..addAll(fresh)
        // pending local echoes (id 0) stay at the end
        ..sort((a, b) => (a.id == 0 ? 1 << 62 : a.id).compareTo(b.id == 0 ? 1 << 62 : b.id));
    }
    if (around == 0 || h.messages.first.id == msgs.firstOrNull?.id) h.more = asBool(m['more']);
    h.loaded = true;
    h.loading = false;
    if (around > 0) jumpTo.value = (ch, around);
  }

  /// Scrolls the chat to [id] in [ch], loading the surrounding page first if needed.
  void jumpToMessage(int ch, int id) {
    if (currentChannel != ch) selectChannel(ch);
    final h = histories[ch];
    if (h != null && h.messages.any((x) => x.id == id)) {
      jumpTo.value = (ch, id);
      notifyListeners();
      return;
    }
    conn.send({'t': Msg.around, 'ch': ch, 'id': id});
  }

  /// Back to the live end of a channel after browsing an old window.
  void returnToPresent(int ch) {
    final h = histories[ch];
    if (h == null) return;
    h.messages.clear();
    h.loaded = false;
    h.detached = false;
    h.more = true;
    h.loading = true;
    conn.send({'t': Msg.history, 'ch': ch});
    notifyListeners();
  }

  void search(String q, {int ch = 0, int from = 0}) {
    searchQuery = q;
    searching = true;
    conn.send({'t': Msg.search, 'q': q, 'ch': ch, 'from': from});
    notifyListeners();
  }

  void loadPins(int ch) => conn.send({'t': Msg.pins, 'ch': ch});
  void setPinned(Message msg, bool on) => conn.send({'t': Msg.pin, 'ch': msg.ch, 'id': msg.id, 'on': on});

  void setStatusText(String text, String emoji, {Duration? clearAfter}) => conn.send({
        't': Msg.setStatusText,
        'text': text,
        'emoji': emoji,
        'until': clearAfter == null ? 0 : DateTime.now().add(clearAfter).millisecondsSinceEpoch,
      });

  void uploadAvatar(Uint8List? bytes) => conn.send({'t': Msg.setAvatar, 'data': bytes == null ? '' : base64.encode(bytes)});

  void _onVoiceUser(Map<String, dynamic> m) {
    final id = asInt(m['id']);
    final ch = m['ch'];
    final prev = voice[id];
    if (ch == null) {
      voice.remove(id);
      native.removeSpeaker(id);
      talking.remove(id);
      if (id == me) {
        _leftVoiceLocally();
      } else if (prev != null && prev.channel == voiceChannel) {
        native.playSound(Sound.leave);
      }
      return;
    }
    final v = VoiceUser(id, asInt(ch), asBool(m['mute']), asBool(m['deaf']), asBool(m['smute']));
    voice[id] = v;
    if (id == me) {
      if (voiceChannel != v.channel) {
        // joined, or moved by an admin
        voiceChannel = v.channel;
        _enteredVoiceLocally();
      }
      native.setMute(selfMute || v.serverMute);
    } else if (voiceChannel != null && v.channel == voiceChannel && prev?.channel != voiceChannel) {
      native.playSound(Sound.join);
    } else if (prev?.channel == voiceChannel && v.channel != voiceChannel) {
      native.playSound(Sound.leave);
      native.removeSpeaker(id);
    }
  }

  void _onVoice((int, Uint8List) v) {
    final (uid, data) = v;
    if (selfDeaf || voiceChannel == null) return;
    native.pushVoice(uid, data);
  }

  void _onNative(NativeEvent e) {
    switch (e.type) {
      case NativeEv.videoPacket || NativeEv.screen || NativeEv.videoSize:
        screen.onNative(e);
      case NativeEv.packet:
        if (voiceChannel != null && authed) conn.sendVoice(e.data);
      case NativeEv.speaking:
        speaking = e.a == 1;
        notifyListeners();
      case NativeEv.overlay:
        settings.overlay = false;
        settings.save();
        notifyListeners();
        if (!_overlayHintShown) {
          _overlayHintShown = true;
          toast('说话者浮窗已关闭，可在语音面板或“设置 → 语音与音频”重新打开');
        }
      case NativeEv.mutedTalk:
        if (settings.warnMutedTalk && !(voice[me]?.serverMute ?? false)) {
          final k = bindingLabelOf(settings.muteKey);
          toast('你正在说话，但麦克风已静音${k.isEmpty ? '' : '（$k 取消静音）'}');
        }
      case NativeEv.hotkey:
        if (e.b != 1) return;
        switch (e.a) {
          case HotkeySlot.mute:
            toggleMute();
          case HotkeySlot.deafen:
            toggleDeafen();
          case HotkeySlot.overlay:
            setOverlay(!settings.overlay);
            toast(settings.overlay ? '已显示说话者浮窗' : '已隐藏说话者浮窗');
          case HotkeySlot.voiceChanger:
            setVoiceChangerMode(settings.vcMode == VcMode.off ? (settings.vcModel.isEmpty && asInt(vcStatus['state']) != 2 ? VcMode.dsp : VcMode.ai) : VcMode.off);
            toast(settings.vcMode == VcMode.off ? '变声器已关闭' : '变声器已开启');
        }
      case NativeEv.hotkeyCaptured:
        final cb = onHotkeyCaptured;
        onHotkeyCaptured = null;
        cb?.call(e.a, e.b);
      case NativeEv.vcStatus:
        try {
          vcStatus = jsonDecode(e.text) as Map<String, dynamic>;
        } catch (_) {}
        if (asInt(vcStatus['state']) == VcState.error) toast('AI 变声器错误：${vcStatus['error']}');
        notifyListeners();
      case NativeEv.device:
        if (e.b == -1) {
          audioError = e.text;
          toast(e.text);
        } else if (e.b == 1) {
          if (e.a == 0) {
            inputDeviceName = e.text;
          } else {
            outputDeviceName = e.text;
          }
          audioError = null;
        } else if (e.b == 0 && e.text == 'stopped') {
          // device unplugged: restart on the system default
          Timer(const Duration(milliseconds: 500), () {
            if (e.a == 0) {
              if (voiceChannel != null || micTest) native.startCapture();
            } else {
              native.startPlayback();
            }
          });
        }
        notifyListeners();
      case NativeEv.log:
        if (kDebugMode) debugPrint('[native] ${e.text}');
    }
  }

  // ================================================================ actions

  void selectChannel(int id) {
    currentChannel = id;
    final h = histories.putIfAbsent(id, () => ChannelHistory());
    h.unread = 0;
    h.mentions = 0;
    if (!h.loaded && !h.loading) {
      h.loading = true;
      conn.send({'t': Msg.history, 'ch': id});
    }
    notifyListeners();
  }

  void loadOlder(int ch) {
    final h = histories[ch];
    if (h == null || h.loading || !h.more || h.messages.isEmpty) return;
    h.loading = true;
    conn.send({'t': Msg.history, 'ch': ch, 'before': h.messages.first.id});
  }

  int _nonce = 0;

  void sendMessage(int ch, String text, {int reply = 0, List<String> attachments = const []}) {
    final t = text.trim();
    if (t.isEmpty && attachments.isEmpty) return;
    final nonce = '${DateTime.now().microsecondsSinceEpoch}-${_nonce++}';
    histories.putIfAbsent(ch, () => ChannelHistory()).messages.add(
        Message(0, ch, me, t, DateTime.now().millisecondsSinceEpoch, 0, reply, {}, pending: true, nonce: nonce));
    conn.send({'t': Msg.sendMsg, 'ch': ch, 'text': t, 'reply': reply, 'nonce': nonce, if (attachments.isNotEmpty) 'att': attachments});
    notifyListeners();
  }

  void openDm(int uid) => conn.send({'t': Msg.dmOpen, 'uid': uid});

  void closeDm(int ch) {
    conn.send({'t': Msg.dmClose, 'id': ch});
    if (currentChannel == ch) {
      final t = sortedChannels(ChannelKind.text);
      if (t.isNotEmpty) selectChannel(t.first.id);
    }
  }

  /// DMs, most recent first.
  List<ChannelInfo> get dms => channels.values.where((c) => c.isDm).toList()..sort((a, b) => b.lastId.compareTo(a.lastId));

  void editMessage(Message m, String text) => conn.send({'t': Msg.editMsg, 'ch': m.ch, 'id': m.id, 'text': text});
  void deleteMessage(Message m) => conn.send({'t': Msg.deleteMsg, 'ch': m.ch, 'id': m.id});
  void react(Message m, String e) => conn.send({'t': Msg.react, 'ch': m.ch, 'id': m.id, 'e': e});

  DateTime _lastTyping = DateTime(2000);
  void sendTyping(int ch) {
    final now = DateTime.now();
    if (now.difference(_lastTyping).inSeconds < 4) return;
    _lastTyping = now;
    conn.send({'t': Msg.typing, 'ch': ch});
  }

  List<Member> typingIn(int ch) {
    final t = typing[ch];
    if (t == null) return const [];
    final now = DateTime.now();
    t.removeWhere((_, until) => until.isBefore(now));
    return [for (final id in t.keys) if (members[id] != null && id != me) members[id]!];
  }

  void joinVoice(int ch) {
    if (!authed) return;
    if (voiceChannel == ch) return;
    conn.send({'t': Msg.voiceJoin, 'ch': ch});
  }

  void leaveVoice() {
    if (voiceChannel == null) return;
    conn.send({'t': Msg.voiceLeave});
    _leftVoiceLocally();
  }

  void _enteredVoiceLocally() {
    native.clearSpeakers();
    if (native.startCapture() != 0) toast('无法打开麦克风，请在设置中检查输入设备');
    native.setMute(selfMute);
    native.setDeafen(selfDeaf);
    native.setTransmit(true);
    final ch = channels[voiceChannel];
    native.setBitrate(ch != null && ch.bitrate < settings.bitrate ? ch.bitrate : settings.bitrate);
    native.playSound(Sound.join);
    _startMeter();
    conn.send({'t': Msg.voiceState, 'mute': selfMute, 'deaf': selfDeaf});
    notifyListeners();
  }

  void _leftVoiceLocally() {
    if (voiceChannel == null) return;
    voiceChannel = null;
    screen.leftVoice();
    native.setTransmit(false);
    if (!micTest) native.stopCapture();
    native.clearSpeakers();
    talking.clear();
    speaking = false;
    native.playSound(Sound.leave);
    if (!micTest) _stopMeter();
    notifyListeners();
  }

  /// "Ctrl + Shift + M"; '' when unbound.
  String bindingLabelOf(Binding b) => b.vk == 0
      ? ''
      : [
          if (b.mods & 1 != 0) 'Ctrl',
          if (b.mods & 2 != 0) 'Shift',
          if (b.mods & 4 != 0) 'Alt',
          if (b.mods & 8 != 0) 'Win',
          native.keyName(b.vk),
        ].join(' + ');

  void toggleMute() {
    selfMute = !selfMute;
    if (!selfMute && selfDeaf) {
      selfDeaf = false;
      native.setDeafen(false);
    }
    native.setMute(selfMute || (voice[me]?.serverMute ?? false));
    native.playSound(selfMute ? Sound.mute : Sound.unmute);
    if (voiceChannel != null) conn.send({'t': Msg.voiceState, 'mute': selfMute, 'deaf': selfDeaf});
    notifyListeners();
  }

  void toggleDeafen() {
    selfDeaf = !selfDeaf;
    if (selfDeaf) {
      selfMute = true;
      native.clearSpeakers();
    } else {
      selfMute = false;
    }
    native.setDeafen(selfDeaf);
    native.setMute(selfMute || (voice[me]?.serverMute ?? false));
    native.playSound(selfDeaf ? Sound.deafen : Sound.undeafen);
    if (voiceChannel != null) conn.send({'t': Msg.voiceState, 'mute': selfMute, 'deaf': selfDeaf});
    notifyListeners();
  }

  void setPtt(bool held) => native.setPtt(held);

  void setMicTest(bool on) {
    micTest = on;
    if (on) {
      native.startCapture();
      native.setMonitor(true);
      _startMeter();
    } else {
      native.setMonitor(false);
      if (voiceChannel == null) {
        native.stopCapture();
        _stopMeter();
      }
    }
    notifyListeners();
  }

  /// Meter polling for speaking rings / input meters (UI reads [userLevels], [levels]).
  List<double> levels = const [0, 0, 0, 0, 0];
  final ValueNotifier<int> meterTick = ValueNotifier(0);

  void _startMeter() {
    _meter ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
      levels = native.levels();
      final ul = native.userLevels();
      final now = <int>{for (final e in ul.entries) if (e.value > 0.015) e.key};
      if (speaking && voiceChannel != null) now.add(me);
      userLevels = ul;
      final changed = now.length != talking.length || !now.containsAll(talking);
      if (changed) {
        talking
          ..clear()
          ..addAll(now);
        notifyListeners();
      }
      meterTick.value++;
    });
  }

  void _stopMeter() {
    _meter?.cancel();
    _meter = null;
    levels = const [0, 0, 0, 0, 0];
    meterTick.value++;
  }

  double userVolume(int uid) => settings.userVolumes['$address|$uid'] ?? 1.0;

  void setUserVolume(int uid, double v) {
    settings.userVolumes['$address|$uid'] = v;
    native.setUserVolume(uid, v);
    settings.save();
    notifyListeners();
  }

  void applyUserVolumes() {
    for (final id in members.keys) {
      final v = settings.userVolumes['$address|$id'];
      if (v != null) native.setUserVolume(id, v);
    }
  }

  void setStatus(String s) {
    myStatus = s;
    conn.send({'t': Msg.setProfile, 'status': s});
    notifyListeners();
  }

  void updateProfile({String? display, String? bio, int? color, int? avatar}) => conn.send({
        't': Msg.setProfile,
        'display': ?display,
        'bio': ?bio,
        'color': ?color,
        'avatar': ?avatar,
      });

  void send(Map<String, dynamic> m) => conn.send(m);

  void savePrefs() {
    settings.save();
    notifyListeners();
  }
}
