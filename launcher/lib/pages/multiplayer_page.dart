import 'dart:async';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Multiplayer via a CMLS relay: host a LAN world or join one.
class MultiplayerPage extends StatefulWidget {
  const MultiplayerPage({super.key});
  @override
  State<MultiplayerPage> createState() => _MultiplayerPageState();
}

/// Survives page switches (the tunnel must keep running while the user browses).
class _Session {
  static TunnelClient? client;
  static String status = '';
  static List<String> members = [];
  static int? localPort;
  static StreamSubscription<Map>? sub;
}

class _MultiplayerPageState extends State<MultiplayerPage> {
  late final address = TextEditingController(text: App.read(context).settings.lastCmlsServer ?? '');
  final serverPassword = TextEditingController();
  final roomCode = TextEditingController();
  final roomPassword = TextEditingController();
  final hostTitle = TextEditingController();
  final hostPassword = TextEditingController();
  final hostPort = TextEditingController();
  bool hostPublic = true;
  bool busy = false;
  List<RoomInfo> rooms = [];

  TunnelClient? get client => _Session.client;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _Session.sub?.cancel();
    _Session.sub = client?.events.listen((m) {
      switch (m['t']) {
        case 'members':
          _Session.members = [for (final x in m['list'] as List) '$x'];
        case 'closed':
          _Session.status = trGlobal('房间已关闭：{0}', [m['reason']]);
          _Session.localPort = null;
        case 'disconnected':
          _Session.status = trGlobal('已断开：{0}', [m['reason']]);
          _Session.client = null;
          _Session.localPort = null;
          _Session.members = [];
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _connect({bool trust = false}) async {
    final app = App.read(context);
    final acc = app.ctx.accounts.selected;
    final addr = address.text.trim();
    if (addr.isEmpty) return;
    setState(() => busy = true);
    final c = TunnelClient(addr, app.ctx.knownServers);
    try {
      await c.connect(name: acc?.name ?? trGlobal('玩家'), password: serverPassword.text, trustNewIdentity: trust);
      _Session.client = c;
      _Session.status = trGlobal('已连接 {0}（指纹 {1}）', [c.serverName, c.fingerprint]);
      app.settings.lastCmlsServer = addr;
      if (!app.settings.cmlsServers.contains(addr)) app.settings.cmlsServers.add(addr);
      await app.saveSettings();
      _listen();
      await _refreshRooms();
    } on IdentityChangedException catch (e) {
      if (!mounted) return;
      final ok = await confirm(context, trGlobal('⚠ 服务器身份已改变'), trGlobal('{0}\n\n只有在你确认服务器重装过时才继续。', [e.message]), ok: trGlobal('信任新身份'), danger: true);
      if (ok) {
        setState(() => busy = false);
        return _connect(trust: true);
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refreshRooms() async {
    try {
      final r = await client!.rooms();
      if (mounted) setState(() => rooms = r);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _host() async {
    final app = App.read(context);
    setState(() => busy = true);
    var port = int.tryParse(hostPort.text.trim());
    String motd = '';
    if (port == null) {
      final found = await TunnelClient.detectLocalLan();
      if (found == null) {
        if (mounted) {
          toast(context, trGlobal('没有检测到已“对局域网开放”的游戏。请在游戏中按 Esc →「对局域网开放」，或手动填写端口。'), error: true);
          setState(() => busy = false);
        }
        return;
      }
      (motd, port) = found;
    }
    try {
      final room = await client!.host(
        title: hostTitle.text.trim().isEmpty ? (motd.isEmpty ? trGlobal('{0} 的世界', [app.ctx.accounts.selected?.name ?? trGlobal('玩家')]) : motd) : hostTitle.text.trim(),
        lanPort: port,
        version: app.settings.selectedVersion ?? '',
        password: hostPassword.text,
        public: hostPublic,
      );
      _Session.status = trGlobal('正在主持房间 {0}（本地端口 {1}）', [room, port]);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _join(String code, {bool locked = false}) async {
    var pw = roomPassword.text;
    if (locked && pw.isEmpty) {
      final r = await prompt(context, trGlobal('房间密码'), obscure: true);
      if (r == null) return;
      pw = r;
    }
    setState(() => busy = true);
    try {
      final port = await client!.join(code, password: pw);
      _Session.localPort = port;
      _Session.status = trGlobal('已加入房间 {0}', [client!.room]);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _leave() async {
    await client?.leave();
    _Session.localPort = null;
    _Session.members = [];
    _Session.status = trGlobal('已离开房间');
    setState(() {});
  }

  Future<void> _disconnect() async {
    await client?.close();
    _Session.client = null;
    _Session.localPort = null;
    _Session.members = [];
    _Session.status = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final c = client;
    final inRoom = c?.room != null;
    return PageBody(children: [
      if (c == null) const _MpHero(),
      Section(
        title: trGlobal('CMLS 联机服务器'),
        icon: Icons.dns_outlined,
        child: c == null
            ? Column(children: [
                Row(children: [
                  Expanded(
                    child: Autocomplete<String>(
                      initialValue: address.value,
                      optionsBuilder: (v) => app.settings.cmlsServers.where((s) => s.contains(v.text)),
                      fieldViewBuilder: (ctx, ctl, focus, submit) {
                        ctl.addListener(() => address.text = ctl.text);
                        return TextField(controller: ctl, focusNode: focus, decoration: InputDecoration(labelText: trGlobal('服务器地址'), hintText: 'example.com:25590'));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 180, child: TextField(controller: serverPassword, obscureText: true, decoration: InputDecoration(labelText: trGlobal('服务器密码（可选）')))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: busy ? null : _connect, child: Text(trGlobal('连接'))),
                ]),
                if (app.settings.cmlsServers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final srv in app.settings.cmlsServers)
                      InputChip(
                        avatar: const Icon(Icons.history_rounded, size: 16),
                        label: Text(srv),
                        onPressed: () => setState(() => address.text = srv),
                        onDeleted: () {
                          app.settings.cmlsServers.remove(srv);
                          app.saveSettings();
                        },
                      ),
                  ]),
                ],
                const SizedBox(height: 8),
                Text(trGlobal('所有联机流量经 X25519 + ChaCha20-Poly1305 端到端加密传输到 CMLS 服务器；首次连接会记住服务器身份，被冒充时会警告。'),
                    style: TextStyle(fontSize: 12)),
              ])
            : Row(children: [
                const Icon(Icons.verified_user, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(_Session.status)),
                if (c.motd.isNotEmpty) Text(c.motd),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _disconnect, child: Text(trGlobal('断开'))),
              ]),
      ),
      if (c != null && inRoom)
        Section(
          title: c.isHost ? trGlobal('我的房间 {0}', [c.room]) : trGlobal('已加入 {0}', [c.room]),
          actions: [
            TextButton.icon(icon: const Icon(Icons.copy, size: 16), label: Text(trGlobal('复制房间号')), onPressed: () => Clipboard.setData(ClipboardData(text: c.room!))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _leave, child: Text(c.isHost ? trGlobal('关闭房间') : trGlobal('离开'))),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!c.isHost && _Session.localPort != null) ...[
              Text(trGlobal('房间已出现在 Minecraft「多人游戏」列表中（局域网世界）。如果没有出现，请手动添加服务器：')),
              const SizedBox(height: 6),
              Row(children: [
                SelectableText('127.0.0.1:${_Session.localPort}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: '127.0.0.1:${_Session.localPort}'))),
              ]),
              const SizedBox(height: 8),
            ],
            if (c.isHost) Text(trGlobal('把房间号发给朋友，他们在 CML 中连接同一个 CMLS 服务器并输入房间号即可加入。关闭 CML 或游戏世界后房间失效。')),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [for (final m in _Session.members) Chip(avatar: const Icon(Icons.person, size: 16), label: Text(m))]),
          ]),
        ),
      if (c != null && !inRoom) ...[
        Section(
          title: trGlobal('创建房间（我来开服）'),
          icon: Icons.add_home_outlined,
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: Text(trGlobal('1. 启动游戏进入单人世界 → Esc →「对局域网开放」\n2. 回到这里点击「创建房间」，CML 会自动检测端口'))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: hostTitle, decoration: InputDecoration(labelText: trGlobal('房间名称（可选）')))),
              const SizedBox(width: 8),
              SizedBox(width: 140, child: TextField(controller: hostPort, decoration: InputDecoration(labelText: trGlobal('端口（自动检测）')))),
              const SizedBox(width: 8),
              SizedBox(width: 160, child: TextField(controller: hostPassword, obscureText: true, decoration: InputDecoration(labelText: trGlobal('房间密码（可选）')))),
              const SizedBox(width: 8),
              Row(children: [Checkbox(value: hostPublic, onChanged: (v) => setState(() => hostPublic = v!)), Text(trGlobal('公开'))]),
              const SizedBox(width: 8),
              FilledButton(onPressed: busy ? null : _host, child: Text(trGlobal('创建房间'))),
            ]),
          ]),
        ),
        Section(
          title: trGlobal('加入房间'),
          icon: Icons.login_rounded,
          actions: [IconButton(onPressed: _refreshRooms, icon: const Icon(Icons.refresh), tooltip: trGlobal('刷新房间列表'))],
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(controller: roomCode, decoration: InputDecoration(labelText: trGlobal('房间号')), textCapitalization: TextCapitalization.characters)),
              const SizedBox(width: 8),
              SizedBox(width: 180, child: TextField(controller: roomPassword, obscureText: true, decoration: InputDecoration(labelText: trGlobal('房间密码（如有）')))),
              const SizedBox(width: 8),
              FilledButton(onPressed: busy ? null : () => _join(roomCode.text.trim()), child: Text(trGlobal('加入'))),
            ]),
            const SizedBox(height: 12),
            if (rooms.isEmpty)
              Text(trGlobal('没有公开房间'))
            else
              for (final r in rooms)
                ListTile(
                  dense: true,
                  leading: Icon(r.locked ? Icons.lock_outline : Icons.public),
                  title: Text(r.title),
                  subtitle: Text(trGlobal('{0} · 房主 {1} · {2} 人{3}', [r.room, r.host, r.players, r.version.isEmpty ? '' : ' · ${r.version}'])),
                  trailing: FilledButton.tonal(onPressed: busy ? null : () => _join(r.room, locked: r.locked), child: Text(trGlobal('加入'))),
                ),
          ]),
        ),
      ],
      Section(
        title: trGlobal('部署 CMLS'),
        icon: Icons.cloud_outlined,
        child: Text(trGlobal('CMLS 是 CML 的联机中继服务端（cmls.exe），部署在任意有公网 IP 或内网穿透的机器上即可：\n  cmls.exe --port 25590 --name "我的联机服"\n首次启动会生成 server_identity.key（服务器身份，请备份勿外传）并显示服务器指纹。只需放行 / 映射 TCP 端口。')),
      ),
    ]);
  }
}


/// Explains how CMLS multiplayer works (shown before connecting).
class _MpHero extends StatelessWidget {
  const _MpHero();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget step(IconData icon, String title, String body) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 10),
              Text(title, style: t.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(body, style: t.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.88), height: 1.5)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: CmlColors.of(context).hero, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trGlobal('和朋友一起玩，无需公网 IP'), style: t.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(trGlobal('局域网世界通过加密隧道转发，朋友在「多人游戏」里就能看到你的房间'), style: t.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.88))),
        const SizedBox(height: 18),
        Row(children: [
          step(Icons.dns_rounded, trGlobal('1. 连接服务器'), trGlobal('填写 CMLS 服务器地址，首次连接会记住服务器指纹')),
          const SizedBox(width: 12),
          step(Icons.add_home_rounded, trGlobal('2. 创建或加入'), trGlobal('房主「对局域网开放」后创建房间，朋友输入房间号')),
          const SizedBox(width: 12),
          step(Icons.sports_esports_rounded, trGlobal('3. 进入游戏'), trGlobal('房间自动出现在多人游戏列表，直接加入即可')),
        ]),
      ]),
    );
  }
}
