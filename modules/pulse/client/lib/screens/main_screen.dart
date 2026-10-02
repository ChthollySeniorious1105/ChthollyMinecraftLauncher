import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../native/native.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../theme/themes.dart';
import '../widgets/common.dart';
import '../widgets/attachments.dart';
import 'admin_dialogs.dart';
import 'chat_view.dart';
import 'roles_dialogs.dart';
import 'screen_share_view.dart';
import 'search_panels.dart';
import '../widgets/quick_switcher.dart';
import 'settings_screen.dart';

/// Discord-style layout: [rail | channels + user panel | chat | members].
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showMembers = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final ch = app.channels[app.currentChannel];
    final wide = MediaQuery.sizeOf(context).width > 1000;
    return Scaffold(
      backgroundColor: t.chat,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.comma, control: true): _OpenSettings(),
          SingleActivator(LogicalKeyboardKey.keyK, control: true): _Quick(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _FocusSearch(),
          SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _Cycle(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _Cycle(1),
          SingleActivator(LogicalKeyboardKey.arrowUp, alt: true, shift: true): _Cycle(-1, unread: true),
          SingleActivator(LogicalKeyboardKey.arrowDown, alt: true, shift: true): _Cycle(1, unread: true),
          SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true): _ToggleMute(),
          SingleActivator(LogicalKeyboardKey.escape, shift: true): _MarkAllRead(),
        },
        child: Actions(
          actions: {
            _OpenSettings: CallbackAction<_OpenSettings>(onInvoke: (_) => openSettings(context)),
            _Quick: CallbackAction<_Quick>(onInvoke: (_) => showQuickSwitcher(context)),
            _FocusSearch: CallbackAction<_FocusSearch>(onInvoke: (_) => app.focusSearch.value++),
            _Cycle: CallbackAction<_Cycle>(onInvoke: (i) => cycleChannel(app, i.delta, unreadOnly: i.unread)),
            // in-app fallback when global hotkeys are disabled
            _ToggleMute: CallbackAction<_ToggleMute>(onInvoke: (_) => app.settings.globalHotkeys ? null : app.toggleMute()),
            _MarkAllRead: CallbackAction<_MarkAllRead>(onInvoke: (_) => app.markAllRead()),
          },
          child: Row(children: [
            const _Rail(),
            SizedBox(
              width: 240,
              child: ColoredBox(
                color: t.sidebar,
                child: const Column(children: [_ServerHeader(), Expanded(child: _ChannelList()), _VoicePanel(), _UserPanel()]),
              ),
            ),
            Expanded(
              child: Column(children: [
                _TopBar(ch, showMembers: _showMembers, onToggleMembers: () => setState(() => _showMembers = !_showMembers)),
                Expanded(
                  child: Row(children: [
                    Expanded(
                      child: ListenableBuilder(
                        listenable: app.screen,
                        builder: (context, _) {
                          final chat = ch == null ? const Center(child: Text('没有频道')) : ChatView(key: ValueKey(ch.id), channel: ch);
                          if (app.screen.watching.isEmpty) return chat;
                          return StreamSplit(chat: chat);
                        },
                      ),
                    ),
                    if (_showMembers && wide && !(ch?.isDm ?? false)) const SizedBox(width: 240, child: _MemberList()),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OpenSettings extends Intent {
  const _OpenSettings();
}

class _Quick extends Intent {
  const _Quick();
}

class _FocusSearch extends Intent {
  const _FocusSearch();
}

class _ToggleMute extends Intent {
  const _ToggleMute();
}

class _MarkAllRead extends Intent {
  const _MarkAllRead();
}

class _Cycle extends Intent {
  final int delta;
  final bool unread;
  const _Cycle(this.delta, {this.unread = false});
}

void openSettings(BuildContext context, [int tab = 0]) =>
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, a, b) => SettingsScreen(initialTab: tab),
      transitionsBuilder: (_, a, b, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(a), child: child)),
    ));

// ------------------------------------------------------------------ rail

class _Rail extends StatelessWidget {
  const _Rail();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final saved = [...app.settings.servers]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return Container(
      width: 72,
      color: t.rail,
      child: Column(children: [
        const SizedBox(height: 12),
        for (final s in saved.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RailIcon(
              label: s.name.isEmpty ? s.address : s.name,
              selected: s.address.toLowerCase() == app.address?.toLowerCase(),
              onTap: () async {
                if (s.address.toLowerCase() == app.address?.toLowerCase()) return;
                await app.disconnect();
                await app.connectTo(s.address);
              },
            ),
          ),
        Container(width: 32, height: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: t.divider),
        Tooltip(
          message: '添加服务器',
          preferBelow: false,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => app.disconnect(),
            child: CircleAvatar(radius: 24, backgroundColor: t.sidebar, child: Icon(Icons.add, color: t.online)),
          ),
        ),
        const Spacer(),
        Tooltip(
          message: '设置 (Ctrl+,)',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => openSettings(context),
            child: CircleAvatar(radius: 24, backgroundColor: t.sidebar, child: Icon(Icons.settings, color: t.muted)),
          ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

class _RailIcon extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RailIcon({required this.label, required this.selected, required this.onTap});
  @override
  State<_RailIcon> createState() => _RailIconState();
}

class _RailIconState extends State<_RailIcon> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    // server name initials ("测试服务器" → "测试", "My Server" → "MS"); address → first octet
    final words = widget.label.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = RegExp(r'^[\d.:\[\]a-f]+$').hasMatch(widget.label)
        ? widget.label.split(RegExp(r'[.:]')).first
        : words.length > 1 && words.every((w) => w.codeUnitAt(0) < 0x80)
            ? words.take(2).map((w) => w[0].toUpperCase()).join()
            : widget.label.characters.take(2).toString();
    final active = widget.selected || _hover;
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 4,
              height: widget.selected ? 40 : (_hover ? 20 : 0),
              decoration: BoxDecoration(color: t.text, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: active ? t.accent : t.sidebar, borderRadius: BorderRadius.circular(active ? 16 : 24)),
              child: Text(initials, style: TextStyle(color: active ? t.onAccent : t.text, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sidebar

class _ServerHeader extends StatelessWidget {
  const _ServerHeader();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    return Material(
      color: t.sidebar,
      child: InkWell(
        onTap: () => _serverMenu(context, app),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.rail.withValues(alpha: 0.6), width: 1))),
          child: Row(children: [
            Expanded(
              child: Text(app.serverName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.text), overflow: TextOverflow.ellipsis),
            ),
            Icon(Icons.expand_more, color: t.text),
          ]),
        ),
      ),
    );
  }

  void _serverMenu(BuildContext context, AppState app) {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(8, box.size.height));
    showContextMenu(context, pos, [
      menuItem('服务器信息', () => showServerInfo(context, app), icon: Icons.info_outline),
      menuItem('全部标记为已读 (Shift+Esc)', app.markAllRead, icon: Icons.mark_chat_read_outlined),
      menuItem('快速切换 (Ctrl+K)', () => showQuickSwitcher(context), icon: Icons.bolt),
      if (app.can(Perm.manageChannels)) menuItem('创建频道', () => createChannelDialog(context, app), icon: Icons.add_circle_outline),
      if (app.can(Perm.createInvite)) menuItem('邀请他人', () => inviteDialog(context, app), icon: Icons.person_add_alt),
      if (app.can(Perm.manageRoles)) menuItem('角色与权限', () => rolesDialog(context, app), icon: Icons.admin_panel_settings_outlined),
      if (app.can(Perm.manageServer)) menuItem('服务器设置', () => serverSettingsDialog(context, app), icon: Icons.tune),
      if (app.can(Perm.manageServer)) menuItem('文件存储', () => storageDialog(context, app), icon: Icons.storage),
      if (app.can(Perm.banMembers) || app.can(Perm.manageServer)) menuItem('封禁列表', () => bansDialog(context, app), icon: Icons.block),
      const PopupMenuDivider(),
      menuItem('断开连接', () => app.disconnect(), icon: Icons.link_off),
      menuItem('退出登录', () => app.disconnect(logout: true), icon: Icons.logout, danger: true),
    ]);
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final texts = app.sortedChannels(ChannelKind.text);
    final voices = app.sortedChannels(ChannelKind.voice);
    Widget add(String kind) => app.can(Perm.manageChannels)
        ? InkWell(
            onTap: () => createChannelDialog(context, app, kind: kind),
            child: Tooltip(message: '创建频道', child: Icon(Icons.add, size: 18, color: t.muted)),
          )
        : const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.only(bottom: 8), children: [
      SectionLabel('文字频道', trailing: add(ChannelKind.text)),
      for (final c in texts) _TextChannelTile(c),
      SectionLabel('语音频道', trailing: add(ChannelKind.voice)),
      for (final c in voices) ...[
        _VoiceChannelTile(c),
        for (final v in app.voice.values.where((v) => v.channel == c.id).toList()..sort((a, b) => a.id.compareTo(b.id))) _VoiceUserTile(v),
      ],
      if (app.dms.isNotEmpty) ...[
        SectionLabel('私信', trailing: InkWell(onTap: () => newDmDialog(context, app), child: Tooltip(message: '发起私信', child: Icon(Icons.add, size: 18, color: t.muted)))),
        for (final c in app.dms) _DmTile(c),
      ] else
        SectionLabel('私信', trailing: InkWell(onTap: () => newDmDialog(context, app), child: Tooltip(message: '发起私信', child: Icon(Icons.add, size: 18, color: t.muted)))),
    ]);
  }
}

void channelMenu(BuildContext context, AppState app, ChannelInfo c, Offset pos) {
  if (!c.can(Perm.manageChannels)) return;
  showContextMenu(context, pos, [
    menuItem('编辑频道', () => editChannelDialog(context, app, c), icon: Icons.edit),
    if (app.can(Perm.manageRoles) || c.can(Perm.manageChannels)) menuItem('频道权限', () => channelPermsDialog(context, app, c), icon: Icons.lock_outline),
    menuItem('上移', () => app.send({'t': Msg.chMove, 'id': c.id, 'delta': -1}), icon: Icons.arrow_upward),
    menuItem('下移', () => app.send({'t': Msg.chMove, 'id': c.id, 'delta': 1}), icon: Icons.arrow_downward),
    const PopupMenuDivider(),
    menuItem('删除频道', () async {
      if (await confirm(context, '删除频道', '确定删除「${c.name}」？频道内的消息将无法再查看。', ok: '删除', danger: true)) {
        app.send({'t': Msg.chDelete, 'id': c.id});
      }
    }, icon: Icons.delete_outline, danger: true),
  ]);
}

class _TextChannelTile extends StatelessWidget {
  final ChannelInfo c;
  const _TextChannelTile(this.c);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final h = app.histories[c.id];
    final selected = app.currentChannel == c.id;
    final unread = (h?.unread ?? 0) > 0;
    return HoverTile(
      selected: selected,
      onTap: () => app.selectChannel(c.id),
      onSecondaryTapAt: (p) => channelMenu(context, app, c, p),
      child: Row(children: [
        Icon(Icons.tag, size: 20, color: selected || unread ? t.text : t.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(c.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected || unread ? t.text : t.muted, fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
        ),
        if ((h?.mentions ?? 0) > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(8)),
            child: Text('${h!.mentions}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

class _DmTile extends StatelessWidget {
  final ChannelInfo c;
  const _DmTile(this.c);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final h = app.histories[c.id];
    final selected = app.currentChannel == c.id;
    final unread = (h?.unread ?? 0) > 0;
    final m = app.dmPartner(c);
    return HoverTile(
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () => app.selectChannel(c.id),
      onSecondaryTapAt: (p) => showContextMenu(context, p, [
        if (m != null) menuItem('个人资料', () => showProfileCard(context, app, m), icon: Icons.person),
        menuItem('关闭私信', () => app.closeDm(c.id), icon: Icons.close),
      ]),
      child: Row(children: [
        Avatar(m, size: 24, showPresence: true),
        const SizedBox(width: 8),
        Expanded(
          child: Text(app.channelTitle(c),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected || unread ? t.text : t.muted, fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
        ),
        if ((h?.mentions ?? 0) > 0 || unread)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(8)),
            child: Text('${h!.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

class _VoiceChannelTile extends StatelessWidget {
  final ChannelInfo c;
  const _VoiceChannelTile(this.c);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final inIt = app.voiceChannel == c.id;
    final n = app.voice.values.where((v) => v.channel == c.id).length;
    return HoverTile(
      selected: inIt,
      onTap: () => app.joinVoice(c.id),
      onSecondaryTapAt: (p) => channelMenu(context, app, c, p),
      child: Row(children: [
        Icon(Icons.volume_up, size: 20, color: inIt ? t.text : t.muted),
        const SizedBox(width: 6),
        Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: inIt ? t.text : t.muted, fontWeight: FontWeight.w500))),
        if (n > 0) Text('$n', style: TextStyle(color: t.muted, fontSize: 12)),
      ]),
    );
  }
}

class _VoiceUserTile extends StatelessWidget {
  final VoiceUser v;
  const _VoiceUserTile(this.v);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final m = app.members[v.id];
    final talking = app.talking.contains(v.id) && !v.mute && !v.serverMute;
    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: HoverTile(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        onSecondaryTapAt: (p) => memberMenu(context, app, v.id, p),
        child: Row(children: [
          Avatar(m, size: 24, speaking: talking),
          const SizedBox(width: 8),
          Expanded(child: Text(m?.display ?? '#${v.id}', overflow: TextOverflow.ellipsis, style: TextStyle(color: talking ? t.text : t.muted, fontSize: 13))),
          if (app.streams[v.id]?.channel == v.channel)
            InkWell(
              onTap: () => app.screen.watch(v.id),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(3)),
                child: const Text('直播', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
          if (v.serverMute) Tooltip(message: '被管理员静音', child: Icon(Icons.mic_off, size: 15, color: t.danger)),
          if (v.mute && !v.serverMute) Icon(Icons.mic_off, size: 15, color: t.muted),
          if (v.deaf) Icon(Icons.headset_off, size: 15, color: t.muted),
          if (v.id != app.me && app.userVolume(v.id) == 0) Tooltip(message: '已被你本地静音', child: Icon(Icons.volume_off, size: 15, color: t.danger)),
        ]),
      ),
    );
  }
}

/// Shown above the user panel while in a voice channel.
class _VoicePanel extends StatelessWidget {
  const _VoicePanel();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final ch = app.channels[app.voiceChannel];
    if (ch == null) return const SizedBox.shrink();
    final vc = app.settings.vcMode;
    final vcSt = asInt(app.vcStatus['state']);
    final ping = app.conn.pingMs;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: Color.lerp(t.sidebar, t.rail, 0.5), border: Border(bottom: BorderSide(color: t.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.signal_cellular_alt, size: 16, color: ping < 150 ? t.online : (ping < 300 ? t.idle : t.danger)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('语音已连接', style: TextStyle(color: t.online, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${ch.name} · ${ping}ms', style: TextStyle(color: t.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
            ]),
          ),
          BarButton(Icons.call_end, '断开语音', app.leaveVoice, color: t.danger),
        ]),
        const LiveStreamsBar(),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: app.screen,
          builder: (context, _) {
            final sc = app.screen;
            final on = sc.sharing || sc.starting;
            return SizedBox(
              height: 30,
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: on ? t.danger : t.input,
                  foregroundColor: on ? Colors.white : t.text,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: on ? sc.stop : (sc.canShare ? () => shareScreenDialog(context, app) : null),
                icon: Icon(on ? Icons.stop_screen_share : Icons.screen_share, size: 16),
                label: Text(
                  sc.starting
                      ? '正在开始共享…'
                      : sc.sharing
                          ? '停止共享 · ${sc.sourceName}'
                          : (sc.canShare ? '共享屏幕' : '无屏幕共享权限'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(children: [
          if (app.settings.inputMode == InputMode.ptt)
            Expanded(
              child: Listener(
                onPointerDown: (_) => app.setPtt(true),
                onPointerUp: (_) => app.setPtt(false),
                onPointerCancel: (_) => app.setPtt(false),
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: app.speaking ? t.online : t.input, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    app.speaking ? '正在说话…' : '按住说话 · ${bindingLabel(app, app.settings.pttKey)}',
                    style: TextStyle(color: app.speaking ? Colors.white : t.muted, fontSize: 12),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Row(children: [
                Icon(Icons.graphic_eq, size: 16, color: app.speaking ? t.online : t.muted),
                const SizedBox(width: 6),
                Text(app.settings.inputMode == InputMode.vad ? '语音激活' : '持续开麦', style: TextStyle(color: t.muted, fontSize: 12)),
              ]),
            ),
          const SizedBox(width: 2),
          Tooltip(
            message: app.settings.overlay ? '隐藏说话者浮窗' : '显示说话者浮窗（置顶小窗，显示谁在说话）',
            child: InkWell(
              onTap: () => app.setOverlay(!app.settings.overlay),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(app.settings.overlay ? Icons.picture_in_picture_alt : Icons.picture_in_picture_alt_outlined,
                    size: 18, color: app.settings.overlay ? t.accent : t.muted),
              ),
            ),
          ),
          Tooltip(
            message: vc == VcMode.off
                ? '变声器：关'
                : vc == VcMode.dsp
                    ? '变声器：音调 ${app.settings.vcPitch.toStringAsFixed(0)}'
                    : 'AI 变声：${vcSt == VcState.running ? '运行中 ${app.vcStatus['latencyMs']}ms' : vcSt == VcState.loading ? '加载中' : '错误'}',
            child: InkWell(
              onTap: () => openSettings(context, 2),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.auto_fix_high,
                    size: 18,
                    color: vc == VcMode.off ? t.muted : (vc == VcMode.ai && vcSt != VcState.running ? t.idle : t.accent)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

String bindingLabel(AppState app, Binding b) => b.vk == 0 ? '未设置' : app.bindingLabelOf(b);

class _UserPanel extends StatelessWidget {
  const _UserPanel();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final m = app.myMember;
    final sm = app.voice[app.me]?.serverMute ?? false;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Color.lerp(t.sidebar, t.rail, 0.6),
      child: Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _statusMenu(context, app),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Avatar(m, size: 32, showPresence: true, speaking: app.speaking && app.voiceChannel != null),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m?.display ?? '', style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text(statusLabel(app.myStatus), style: TextStyle(color: t.muted, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        BarButton(app.selfMute || sm ? Icons.mic_off : Icons.mic, sm ? '被管理员静音' : (app.selfMute ? '取消静音' : '静音'), app.toggleMute,
            active: app.selfMute || sm),
        BarButton(app.selfDeaf ? Icons.headset_off : Icons.headset, app.selfDeaf ? '取消闭麦' : '闭麦（不听不说）', app.toggleDeafen, active: app.selfDeaf),
        BarButton(Icons.settings, '用户设置', () => openSettings(context)),
      ]),
    );
  }

  void _statusMenu(BuildContext context, AppState app) {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(const Offset(8, -170));
    showContextMenu(context, pos, [
      for (final s in kStatuses)
        menuItem(statusLabel(s), () => app.setStatus(s), icon: switch (s) {
          'online' => Icons.circle,
          'idle' => Icons.dark_mode,
          'dnd' => Icons.do_not_disturb_on,
          _ => Icons.circle_outlined,
        }),
      const PopupMenuDivider(),
      menuItem('编辑个人资料', () => openSettings(context, 0), icon: Icons.edit),
    ]);
  }
}

// ------------------------------------------------------------------ top bar / members

class _TopBar extends StatelessWidget {
  final ChannelInfo? ch;
  final bool showMembers;
  final VoidCallback onToggleMembers;
  const _TopBar(this.ch, {required this.showMembers, required this.onToggleMembers});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final app = AppScope.of(context);
    final c = ch;
    if (c != null && c.isDm) {
      final m = app.dmPartner(c);
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: t.chat, border: Border(bottom: BorderSide(color: t.rail.withValues(alpha: 0.6)))),
        child: Row(children: [
          Avatar(m, size: 24, showPresence: true),
          const SizedBox(width: 8),
          Text(app.channelTitle(c), style: TextStyle(fontWeight: FontWeight.w700, color: t.text, fontSize: 15)),
          if (m != null && m.statusText.isNotEmpty) ...[
            Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 12), color: t.divider),
            Expanded(child: Text('${m.statusEmoji} ${m.statusText}', style: TextStyle(color: t.muted, fontSize: 13), overflow: TextOverflow.ellipsis)),
          ] else
            const Spacer(),
          BarButton(Icons.push_pin_outlined, '置顶消息', () => showPinsPanel(context, c)),
          const SizedBox(width: 8),
          const SearchBox(),
        ]),
      );
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: t.chat, border: Border(bottom: BorderSide(color: t.rail.withValues(alpha: 0.6)))),
      child: Row(children: [
        Icon(Icons.tag, color: t.muted),
        const SizedBox(width: 6),
        Text(c?.name ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: t.text, fontSize: 15)),
        if (c != null && c.topic.isNotEmpty) ...[
          Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 12), color: t.divider),
          Expanded(child: Text(c.topic, style: TextStyle(color: t.muted, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ] else
          const Spacer(),
        if (c != null && c.slowmode > 0) Tooltip(message: '慢速模式：${c.slowmode} 秒', child: Icon(Icons.timer_outlined, size: 18, color: t.muted)),
        const SizedBox(width: 8),
        if (c != null) BarButton(Icons.push_pin_outlined, '置顶消息', () => showPinsPanel(context, c)),
        BarButton(Icons.people_alt, showMembers ? '隐藏成员列表' : '显示成员列表', onToggleMembers, color: showMembers ? t.text : t.muted),
        const SizedBox(width: 8),
        const SearchBox(),
      ]),
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final all = app.members.values.toList()
      ..sort((a, b) {
        final ta = app.topPosition(a), tb = app.topPosition(b);
        return ta != tb ? tb.compareTo(ta) : a.display.toLowerCase().compareTo(b.display.toLowerCase());
      });
    final online = all.where((m) => m.online || m.id == app.me).toList();
    final offline = all.where((m) => !(m.online || m.id == app.me)).toList();
    // online members grouped by their highest hoisted role (Discord style)
    final byRole = <int, List<Member>>{};
    final rest = <Member>[];
    for (final m in online) {
      final r = app.hoistRole(m);
      if (r == null) {
        rest.add(m);
      } else {
        byRole.putIfAbsent(r.id, () => []).add(m);
      }
    }
    final groups = <(String, List<Member>)>[
      for (final r in app.sortedRoles)
        if (byRole[r.id] != null) ('${r.name} — ${byRole[r.id]!.length}', byRole[r.id]!),
      if (rest.isNotEmpty) ('在线 — ${rest.length}', rest),
      if (offline.isNotEmpty) ('离线 — ${offline.length}', offline),
    ];
    return ColoredBox(
      color: t.sidebar,
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        for (final (label, list) in groups) ...[
          SectionLabel(label),
          for (final m in list) _MemberTile(m, dim: !(m.online || m.id == app.me)),
        ],
      ]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Member m;
  final bool dim;
  const _MemberTile(this.m, {required this.dim});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final presence = m.id == app.me ? app.myStatus : m.presence;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: HoverTile(
        onTap: () => showProfileCard(context, app, m),
        onSecondaryTapAt: (p) => memberMenu(context, app, m.id, p),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(m, size: 32, speaking: app.talking.contains(m.id)),
            Positioned(right: -2, bottom: -2, child: PresenceDot(presence == 'invisible' ? 'offline' : presence, size: 12, border: t.sidebar)),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.display, overflow: TextOverflow.ellipsis, style: TextStyle(color: nameColor(context, m), fontWeight: FontWeight.w500)),
              if (m.statusText.isNotEmpty || m.statusEmoji.isNotEmpty)
                Text('${m.statusEmoji}${m.statusEmoji.isNotEmpty && m.statusText.isNotEmpty ? ' ' : ''}${m.statusText}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 11.5))
              else if (m.bio.isNotEmpty)
                Text(m.bio, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 11.5)),
            ]),
          ),
          if (app.streams.containsKey(m.id))
            Tooltip(message: '正在共享屏幕', child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.screen_share, size: 16, color: t.danger))),
          if (m.role == Role.owner) Tooltip(message: '服主', child: Icon(Icons.workspace_premium, size: 16, color: const Color(0xFFF0B232))),
        ]),
      ),
    );
  }
}

void memberMenu(BuildContext context, AppState app, int uid, Offset pos) {
  final m = app.members[uid];
  if (m == null) return;
  final v = app.voice[uid];
  final vch = v == null ? null : app.channels[v.channel];
  bool canIn(int p) => app.canModerate(m, p) && (vch == null || vch.can(p));
  final canMute = v != null && canIn(Perm.muteMembers);
  final canMove = v != null && canIn(Perm.moveMembers);
  final canKick = app.canModerate(m, Perm.kickMembers);
  final canBan = app.canModerate(m, Perm.banMembers);
  final canRoles = app.can(Perm.manageRoles) && (uid == app.me || app.isOwner || app.myTop > app.topPosition(m)) && m.role != Role.owner;
  final st = app.streams[uid];
  showContextMenu(context, pos, [
    menuItem('个人资料', () => showProfileCard(context, app, m), icon: Icons.person),
    if (uid != app.me) menuItem('发送私信', () => app.openDm(uid), icon: Icons.chat_bubble_outline),
    if (st != null && uid != app.me) menuItem('观看屏幕共享', () => app.screen.watch(uid), icon: Icons.live_tv),
    menuItem('提及 @${m.display}', () => app.mentionRequest.value = '@${m.username} ', icon: Icons.alternate_email),
    if (uid != app.me) menuItem('调节音量…', () => userVolumeDialog(context, app, m), icon: Icons.volume_up),
    if (uid != app.me)
      menuItem(app.userVolume(uid) == 0 ? '取消本地静音' : '本地静音', () => app.setUserVolume(uid, app.userVolume(uid) == 0 ? 1.0 : 0.0),
          icon: Icons.volume_off),
    if (canMute || canMove || canKick || canBan || canRoles || (app.isOwner && uid != app.me)) const PopupMenuDivider(),
    if (canMute) menuItem(v.serverMute ? '取消服务器静音' : '服务器静音', () => app.send({'t': Msg.serverMute, 'id': uid, 'on': !v.serverMute}), icon: Icons.mic_off),
    if (canMove)
      for (final c in app.sortedChannels(ChannelKind.voice).where((c) => c.id != v.channel && c.can(Perm.moveMembers)))
        menuItem('移动到 ${c.name}', () => app.send({'t': Msg.moveMember, 'id': uid, 'ch': c.id}), icon: Icons.drive_file_move_outline),
    if (canRoles) menuItem('角色…', () => memberRolesDialog(context, app, m), icon: Icons.shield_outlined),
    if (app.isOwner && uid != app.me)
      menuItem('转让服主', () async {
        if (await confirm(context, '转让服主', '确定把服主转让给 ${m.display}？你将失去服主身份（保留你的角色）。', danger: true)) {
          app.send({'t': Msg.setRole, 'id': uid, 'role': Role.owner});
        }
      }, icon: Icons.workspace_premium),
    if (canKick)
      menuItem('踢出', () async {
        if (await confirm(context, '踢出成员', '将 ${m.display} 断开连接？（之后仍可重新登录）', danger: true)) app.send({'t': Msg.kick, 'id': uid});
      }, icon: Icons.logout, danger: true),
    if (canBan)
      menuItem('封禁', () async {
        final reason = await prompt(context, '封禁 ${m.display}', hint: '原因（可选）');
        if (reason != null) app.send({'t': Msg.ban, 'id': uid, 'reason': reason, 'ip': true});
      }, icon: Icons.block, danger: true),
  ]);
}

void userVolumeDialog(BuildContext context, AppState app, Member m) {
  showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final v = app.userVolume(m.id);
      return AlertDialog(
        title: Text('${m.display} 的音量'),
        content: SizedBox(
          width: 360,
          child: Row(children: [
            const Icon(Icons.volume_down),
            Expanded(
              child: Slider(value: v, min: 0, max: 2, divisions: 40, label: '${(v * 100).round()}%', onChanged: (x) {
                app.setUserVolume(m.id, x);
                set(() {});
              }),
            ),
            SizedBox(width: 48, child: Text('${(v * 100).round()}%')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => app.setUserVolume(m.id, 1.0), child: const Text('重置')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('完成')),
        ],
      );
    }),
  );
}

void showProfileCard(BuildContext context, AppState app, Member m) {
  final t = PulseColors.of(context);
  showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => Dialog(
      child: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: m.color != 0 ? Color(m.color) : avatarColors[m.avatar % avatarColors.length],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
          ),
          Transform.translate(
            offset: const Offset(16, -36),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: t.chat, shape: BoxShape.circle),
              child: Avatar(m, size: 72, showPresence: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.display, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: nameColor(context, m))),
              Text(m.username, style: TextStyle(color: t.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (m.role == Role.owner) Chip(label: const Text('服主'), visualDensity: VisualDensity.compact),
                Chip(label: Text(statusLabel(m.id == app.me ? app.myStatus : m.presence)), visualDensity: VisualDensity.compact),
              ]),
              if (m.roles.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('角色', style: TextStyle(color: t.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in app.sortedRoles.where((r) => m.roles.contains(r.id))) RoleChip(r),
                ]),
              ],
              if (m.bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('关于我', style: TextStyle(color: t.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(m.bio),
              ],
              if (m.id != app.me) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      app.openDm(m.id);
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text('给 ${m.display} 发私信'),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ),
  );
}
