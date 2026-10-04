import '../i18n/aurora_i18n.dart';

import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/chat_panel.dart';
import '../widgets/common.dart';
import '../widgets/game_picker.dart';
import 'local_game_screen.dart';
import 'profile_screen.dart';
import 'replay_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import '../widgets/invite_dialog.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final app = AppScope.read(context);
    final res = await showDialog<CreateRoomResult>(
      useRootNavigator: false,
      context: context,
      builder: (_) => CreateRoomDialog(app: app),
    );
    if (res == null) return;
    app.send({
      't': 'create_room',
      'name': res.name,
      'game': res.game,
      'options': res.options,
      'password': res.password,
      'private': res.private,
    });
  }

  /// Enter a (possibly private) room by its 5-character code.
  Future<void> _joinByCode(BuildContext context) async {
    final ctl = TextEditingController();
    final pwd = TextEditingController();
    var spectate = false;
    final ok = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const AuroraText('输入房间号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctl,
                autofocus: true,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: auroraT('例如 A7K2Q'),
                  counterText: '',
                ),
                onSubmitted: (_) => Navigator.pop(c, true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pwd,
                obscureText: true,
                decoration: InputDecoration(labelText: auroraT('房间密码（如有）')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: spectate,
                onChanged: (v) => set(() => spectate = v ?? false),
                title: const AuroraText('以观战者身份进入'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const AuroraText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const AuroraText('进入'),
            ),
          ],
        ),
      ),
    );
    final code = ctl.text.trim().toUpperCase();
    if (ok != true || code.isEmpty) return;
    if (!context.mounted) return;
    AppScope.read(context).send({
      't': 'join_room',
      'room': code,
      'password': pwd.text,
      'spectate': spectate,
    });
  }

  Future<void> _join(
    BuildContext context,
    Map<String, dynamic> r, {
    bool spectate = false,
  }) async {
    final app = AppScope.read(context);
    var pwd = '';
    if (r['locked'] == true) {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        useRootNavigator: false,
        context: context,
        builder: (c) => AlertDialog(
          title: const AuroraText('输入房间密码'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            obscureText: true,
            onSubmitted: (_) => Navigator.pop(c, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const AuroraText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const AuroraText('进入'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      pwd = ctl.text;
    }
    app.send({
      't': 'join_room',
      'room': r['id'],
      'password': pwd,
      'spectate': spectate,
    });
  }

  static void _push(BuildContext context, Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width > 900;
    final roomList = app.rooms.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.meeting_room_outlined, size: 64, color: cs.primary),
                const SizedBox(height: 8),
                const AuroraText('还没有房间，创建一个吧！'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add),
                  label: const AuroraText('创建房间'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _joinByCode(context),
                  icon: const Icon(Icons.vpn_key),
                  label: const AuroraText('输入房间号'),
                ),
              ],
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisExtent: 116,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: app.rooms.length,
            itemBuilder: (context, i) {
              final r = app.rooms[i];
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _join(context, r),
                  onLongPress: () => _join(context, r, spectate: true),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${r['id']}',
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${r['name']}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (r['locked'] == true)
                              const Icon(Icons.lock, size: 16),
                            IconButton(
                              tooltip: auroraT('观战'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.visibility, size: 18),
                              onPressed: () =>
                                  _join(context, r, spectate: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          auroraGameText('${r['gameName']}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.secondary),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            // Counts shrink first so the status chip always fits narrow cards.
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.event_seat, size: 16),
                                  Flexible(
                                    child: Text(
                                      ' ${r['players']}/${r['seats']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.people, size: 16),
                                  Flexible(
                                    child: Text(
                                      ' ${r['members']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (r['playing'] == true
                                            ? Colors.orange
                                            : Colors.green)
                                        .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                auroraT(r['playing'] == true ? '对局中' : '等待中'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(
          message: '已加密连接 · 服务器指纹 ${app.serverFingerprint ?? '-'}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 16, color: Colors.greenAccent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  app.serverName.isEmpty ? '大厅' : app.serverName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (wide && app.rooms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: const AuroraText('创建房间'),
              ),
            ),
          IconButton(
            tooltip: auroraT('输入房间号'),
            onPressed: () => _joinByCode(context),
            icon: const Icon(Icons.vpn_key),
          ),
          if (wide) ...[
            IconButton(
              tooltip: auroraT('对局回放'),
              onPressed: () => _push(context, const ReplaysScreen()),
              icon: const Icon(Icons.slideshow),
            ),
            IconButton(
              tooltip: auroraT('战绩与排行'),
              onPressed: () => _push(context, const StatsScreen()),
              icon: const Icon(Icons.emoji_events),
            ),
            IconButton(
              tooltip: auroraT('单机游戏'),
              onPressed: () => _push(context, const LocalSetupScreen()),
              icon: const Icon(Icons.smart_toy),
            ),
            Center(child: AuroraText('在线 ${app.onlineCount}  ')),
            IconButton(
              tooltip: auroraT('刷新'),
              onPressed: () => app.send({'t': 'list_rooms'}),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: auroraT('主题与设置'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.palette),
            ),
            InkWell(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Avatar(app.avatar, size: 32),
                    const SizedBox(width: 6),
                    Text(app.name),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: auroraT('断开连接'),
              onPressed: app.disconnect,
              icon: const Icon(Icons.logout),
            ),
          ] else ...[
            Builder(
              builder: (context) => IconButton(
                tooltip: auroraT('大厅聊天'),
                icon: const Icon(Icons.chat),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
            PopupMenuButton<String>(
              icon: Avatar(app.avatar, size: 30),
              onSelected: (v) {
                switch (v) {
                  case 'refresh':
                    app.send({'t': 'list_rooms'});
                  case 'replays':
                    _push(context, const ReplaysScreen());
                  case 'stats':
                    _push(context, const StatsScreen());
                  case 'local':
                    _push(context, const LocalSetupScreen());
                  case 'settings':
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  case 'profile':
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  case 'logout':
                    app.disconnect();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: AuroraText('${app.name} · 在线 ${app.onlineCount}'),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: AuroraText('刷新'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'replays',
                  child: ListTile(
                    leading: Icon(Icons.slideshow),
                    title: AuroraText('对局回放'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'stats',
                  child: ListTile(
                    leading: Icon(Icons.emoji_events),
                    title: AuroraText('战绩与排行'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'local',
                  child: ListTile(
                    leading: Icon(Icons.smart_toy),
                    title: AuroraText('单机游戏'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    leading: Icon(Icons.person),
                    title: AuroraText('个人资料'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.palette),
                    title: AuroraText('主题与设置'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: AuroraText('断开连接'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      endDrawer: wide
          ? null
          : const Drawer(
              width: 340,
              child: SafeArea(child: ChatPanel(title: '大厅聊天', voice: false)),
            ),
      floatingActionButton: app.rooms.isEmpty || wide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const AuroraText('创建房间'),
            ),
      body: Column(
        children: [
          InvitationBanner(app: app),
          if (app.lastError != null)
            MaterialBanner(
              content: Text(app.lastError!),
              actions: [
                TextButton(
                  onPressed: app.disconnect,
                  child: const AuroraText('返回'),
                ),
              ],
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      Expanded(child: roomList),
                      SizedBox(
                        width: 340,
                        child: Card(
                          margin: const EdgeInsets.all(12),
                          child: ChatPanel(title: '大厅聊天', voice: false),
                        ),
                      ),
                    ],
                  )
                : roomList,
          ),
        ],
      ),
    );
  }
}
