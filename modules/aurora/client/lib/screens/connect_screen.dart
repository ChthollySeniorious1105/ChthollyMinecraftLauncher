import '../i18n/aurora_i18n.dart';

import 'package:flutter/material.dart';

import '../main.dart';
import '../net/connection.dart';
import '../platform/lan.dart';
import '../widgets/common.dart';
import 'local_game_screen.dart';
import 'profile_screen.dart';
import 'replay_screen.dart';
import 'settings_screen.dart';

/// Server address entry ("IP:端口").
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _addr;
  bool _searching = false;
  List<LanServer>? _lan;

  Future<void> _searchLan() async {
    setState(() {
      _searching = true;
      _lan = null;
    });
    List<LanServer> r;
    try {
      r = await discoverLanServers();
    } catch (_) {
      r = const [];
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _lan = r;
    });
  }

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    // browser: the server that served this page is the natural default
    final def = kIsWebTransport ? defaultWebAddress() : '';
    _addr = TextEditingController(
      text:
          app.pendingInvitation?.url ??
          (app.recentServers.isNotEmpty ? app.recentServers.first : def),
    );
  }

  void _connect([String? a]) {
    final addr = (a ?? _addr.text).trim();
    if (addr.isEmpty) return;
    _addr.text = addr;
    AppScope.read(context).connect(addr);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final busy = app.state == ConnState.connecting;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AURORA',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: cs.primary,
                      shadows: [Shadow(color: cs.secondary, blurRadius: 24)],
                    ),
                  ),
                  Text(
                    '联机小游戏',
                    style: TextStyle(
                      fontSize: 16,
                      letterSpacing: 6,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Row(
                                children: [
                                  Avatar(app.avatar, size: 52),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      app.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.edit, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _addr,
                            enabled: !busy,
                            decoration: InputDecoration(
                              labelText: auroraT('服务器地址或邀请链接'),
                              hintText: kIsWebTransport
                                  ? '例如 http://192.168.1.10:7790（网页版端口）'
                                  : '例如 192.168.1.10:7788',
                              prefixIcon: const Icon(Icons.dns),
                            ),
                            onSubmitted: (_) => _connect(),
                          ),
                          if (app.lastError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              app.lastError!,
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                          if (app.keyMismatch != null) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.warning_amber),
                              label: const AuroraText('我确认服务器是可信的，信任新身份'),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  useRootNavigator: false,
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const AuroraText('信任新的服务器身份？'),
                                    content: const Text(
                                      '只有在你确认服务器管理员重装/更换过服务器时才这样做。'
                                      '可以请管理员核对服务器控制台显示的"服务器指纹"。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const AuroraText('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const AuroraText('信任'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true)
                                  app.trustNewServerKey(app.keyMismatch!);
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: busy ? null : _connect,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(busy ? '连接中…' : '连接服务器'),
                          ),
                          if (!kIsWebTransport) const SizedBox(height: 8),
                          if (!kIsWebTransport)
                            OutlinedButton.icon(
                              onPressed: busy || _searching ? null : _searchLan,
                              icon: _searching
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.wifi_find),
                              label: Text(_searching ? '正在搜索局域网…' : '搜索局域网服务器'),
                            ),
                          if (_lan != null) ...[
                            const SizedBox(height: 6),
                            if (_lan!.isEmpty)
                              Text(
                                '没有发现局域网服务器（确认服务器已启动且在同一网络）',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.7),
                                ),
                              )
                            else
                              for (final s in _lan!)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.dns),
                                  title: Text(
                                    s.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${s.address}${s.fingerprint.isEmpty ? '' : ' · 指纹 ${s.fingerprint}'}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.arrow_forward),
                                  onTap: () =>
                                      setState(() => _addr.text = s.address),
                                ),
                          ],
                          if (app.recentServers.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              '最近连接',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final s in app.recentServers)
                                  InputChip(
                                    label: Text(s),
                                    onPressed: busy ? null : () => _connect(s),
                                    onDeleted: () {
                                      app.recentServers.remove(s);
                                      app.prefs.setStringList(
                                        'servers',
                                        app.recentServers,
                                      );
                                      setState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(260, 46),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LocalSetupScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.smart_toy),
                    label: const AuroraText('单机游戏（与电脑对战）'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReplaysScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.slideshow),
                        label: const AuroraText('本机回放'),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.palette),
                        label: const AuroraText('主题与设置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
