import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../net/connection.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

/// Server address → connect → login / register.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _addr = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _display = TextEditingController();
  final _invite = TextEditingController();
  final _serverPass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showServerPass = false;
  List<(String, int, String)> _lan = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final s = app.settings;
    _addr.text = s.lastServer.isNotEmpty ? s.lastServer : (s.servers.isNotEmpty ? s.servers.last.address : '');
    if (_addr.text.isNotEmpty) _user.text = s.find(_addr.text)?.username ?? '';
  }

  @override
  void dispose() {
    for (final c in [_addr, _user, _pass, _pass2, _display, _invite, _serverPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final app = AppScope.read(context);
    if (_addr.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await app.connectTo(_addr.text.trim());
    if (mounted) setState(() => _busy = false);
  }

  void _submit() {
    final app = AppScope.read(context);
    final u = _user.text.trim();
    final err = validateUsername(u) ?? validatePassword(_pass.text);
    if (err != null) return app.toast(err);
    if (_register) {
      if (_pass.text != _pass2.text) return app.toast('两次输入的密码不一致');
      final d = _display.text.trim().isEmpty ? u : _display.text.trim();
      final e2 = validateDisplayName(d);
      if (e2 != null) return app.toast(e2);
      app.register(u, _pass.text, d, invite: _invite.text.trim(), serverPass: _serverPass.text);
    } else {
      app.login(u, _pass.text, serverPass: _serverPass.text);
    }
    _pass.clear();
    _pass2.clear();
  }

  Future<void> _scanLan() async {
    setState(() {
      _scanning = true;
      _lan = [];
    });
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..broadcastEnabled = true;
      final found = <String, (String, int, String)>{};
      sock.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = sock!.receive();
        if (d == null) return;
        try {
          final j = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
          // one entry per server (fingerprint): a host answers on every interface,
          // prefer a normal LAN address over virtual adapters (Hyper-V / WSL 172.16/12)
          final key = '${d.address.address}:${j['port']}';
          final fp = asStr(j['fp'], key);
          final prev = found[fp];
          bool virt(String a) => RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
          if (prev == null || (virt(prev.$1) && !virt(key))) found[fp] = (key, asInt(j['online']), asStr(j['name']));
          if (mounted) setState(() => _lan = found.values.toList());
        } catch (_) {}
      });
      final hello = utf8.encode(kDiscoveryHello);
      sock.send(hello, InternetAddress('255.255.255.255'), kDiscoveryPort);
      // also directed broadcast per interface (some routers drop 255.255.255.255)
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          final p = a.address.split('.');
          if (p.length == 4) sock.send(hello, InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'), kDiscoveryPort);
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      sock?.close();
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final connected = app.state == ConnState.connected || app.awaitingLogin;
    final connecting = app.state == ConnState.connecting || _busy;
    return Scaffold(
      backgroundColor: t.rail,
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(t.rail, t.accent, 0.18)!, t.rail, Color.lerp(t.rail, t.accent, 0.08)!],
              ),
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: t.chat,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(Icons.graphic_eq_rounded, color: t.accent, size: 34),
                  const SizedBox(width: 10),
                  Text('Pulse', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: t.text)),
                  const Spacer(),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(connected ? '已连接到 ${app.address}' : '连接到你的服务器', style: TextStyle(color: t.muted)),
                const SizedBox(height: 20),
                if (!connected) ..._connectForm(app, t, connecting) else ..._authForm(app, t),
                if (app.lastError != null && app.identityMismatch == null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: t.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(app.lastError!, style: TextStyle(color: t.danger)),
                  ),
                ],
                if (app.identityMismatch != null) _mismatch(app, t),
                if (app.audioError != null) ...[
                  const SizedBox(height: 10),
                  Text('音频：${app.audioError}', style: TextStyle(color: t.idle, fontSize: 12)),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _connectForm(AppState app, PulseTheme t, bool connecting) {
    final saved = [...app.settings.servers]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return [
      _label('服务器地址', t),
      TextField(
        controller: _addr,
        decoration: const InputDecoration(hintText: '例如 192.168.1.10:7800 或 my.domain.com:7800'),
        onSubmitted: (_) => _connect(),
        enabled: !connecting,
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: connecting ? null : _connect,
        child: connecting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('连接'),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: _scanning ? null : _scanLan,
        icon: _scanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find, size: 18),
        label: const Text('搜索局域网服务器'),
      ),
      for (final (addr, online, name) in _lan)
        HoverTile(
          onTap: () => setState(() => _addr.text = addr),
          child: Row(children: [
            Icon(Icons.dns, size: 18, color: t.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('$name  ·  $addr', overflow: TextOverflow.ellipsis)),
            Text('$online 在线', style: TextStyle(color: t.muted, fontSize: 12)),
          ]),
        ),
      if (saved.isNotEmpty) ...[
        const SizedBox(height: 12),
        _label('最近使用', t),
        for (final s in saved.take(6))
          HoverTile(
            onTap: () {
              setState(() {
                _addr.text = s.address;
                _user.text = s.username;
              });
              _connect();
            },
            onSecondaryTapAt: (pos) => showContextMenu(context, pos, [
              menuItem('从列表移除', () {
                setState(() => app.settings.servers.remove(s));
                app.settings.save();
              }, icon: Icons.delete_outline, danger: true),
            ]),
            child: Row(children: [
              Icon(Icons.history, size: 18, color: t.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(s.name.isEmpty ? s.address : '${s.name}  ·  ${s.address}', overflow: TextOverflow.ellipsis)),
              if (s.tokenBlob.isNotEmpty) Icon(Icons.verified_user, size: 16, color: t.online),
            ]),
          ),
      ],
    ];
  }

  List<Widget> _authForm(AppState app, PulseTheme t) {
    return [
      Row(children: [
        Icon(Icons.lock, size: 14, color: t.online),
        const SizedBox(width: 6),
        Expanded(
          child: Text('加密连接 · 服务器指纹 ${app.fingerprint}',
              style: TextStyle(color: t.muted, fontSize: 12, fontFamily: 'Consolas'), overflow: TextOverflow.ellipsis),
        ),
      ]),
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('登录')), ButtonSegment(value: true, label: Text('注册'))],
        selected: {_register},
        onSelectionChanged: (s) => setState(() => _register = s.first),
      ),
      const SizedBox(height: 16),
      _label('用户名', t),
      TextField(controller: _user, autofocus: true, onSubmitted: (_) => _submit()),
      const SizedBox(height: 12),
      _label('密码', t),
      TextField(controller: _pass, obscureText: true, onSubmitted: (_) => _register ? null : _submit()),
      if (_register) ...[
        const SizedBox(height: 12),
        _label('确认密码', t),
        TextField(controller: _pass2, obscureText: true),
        const SizedBox(height: 12),
        _label('昵称（可选）', t),
        TextField(controller: _display, maxLength: 32),
        _label('邀请码（服务器要求时填写）', t),
        TextField(controller: _invite),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() => _showServerPass = !_showServerPass),
          child: Text(_showServerPass ? '隐藏服务器密码' : '服务器设置了进入密码？', style: TextStyle(color: t.accent, fontSize: 12)),
        ),
      ),
      if (_showServerPass) TextField(controller: _serverPass, obscureText: true, decoration: const InputDecoration(hintText: '服务器密码')),
      const SizedBox(height: 16),
      FilledButton(onPressed: _submit, child: Text(_register ? '注册并进入' : '登录')),
      const SizedBox(height: 8),
      TextButton(onPressed: () => app.disconnect(), child: const Text('返回')),
    ];
  }

  Widget _mismatch(AppState app, PulseTheme t) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: t.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: t.danger)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gpp_bad, color: t.danger),
            const SizedBox(width: 8),
            Text('服务器身份已改变', style: TextStyle(color: t.danger, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text('这台服务器的身份密钥和你上次连接时不同。如果服务器管理员刚重装了服务器，这是正常的；'
              '否则可能有人在冒充服务器窃听你的消息。\n\n新指纹：${app.identityMismatch}\n\n请向管理员核对服务器控制台显示的指纹后再继续。'),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => setState(() => app.identityMismatch = null), child: const Text('取消')),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.danger, foregroundColor: Colors.white),
              onPressed: () => app.trustNewIdentity(),
              child: const Text('我已核对，信任新身份'),
            ),
          ]),
        ]),
      );

  Widget _label(String s, PulseTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s.toUpperCase(), style: TextStyle(color: t.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
