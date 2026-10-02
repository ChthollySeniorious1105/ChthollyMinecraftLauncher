import 'package:flutter/material.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../state/app_state.dart';
import '../theme/themes.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';

const _roleColors = [
  0, 0xFF1ABC9C, 0xFF2ECC71, 0xFF3498DB, 0xFF9B59B6, 0xFFE91E63, 0xFFF1C40F, 0xFFE67E22, 0xFFE74C3C, 0xFF95A5A6, //
  0xFF11806A, 0xFF1F8B4C, 0xFF206694, 0xFF71368A, 0xFFAD1457, 0xFFC27C0E, 0xFFA84300, 0xFF992D22, 0xFF607D8B,
];

/// Server roles: list (ordered by power) on the left, editor on the right.
Future<void> rolesDialog(BuildContext context, AppState app) async {
  int? sel = app.sortedRoles.firstOrNull?.id;
  await showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => AnimatedBuilder(
      animation: app,
      builder: (c, _) {
        final t = PulseColors.of(c);
        final roles = app.sortedRoles;
        if (sel == null || !app.roles.containsKey(sel)) sel = roles.firstOrNull?.id;
        final r = app.roles[sel];
        bool editable(RoleDef x) => app.isOwner || x.position < app.myTop;
        return StatefulBuilder(builder: (c, set) {
          return AlertDialog(
            title: Row(children: [
              const Expanded(child: Text('角色与权限')),
              FilledButton.icon(onPressed: () => app.send({'t': Msg.roleCreate, 'name': '新角色'}), icon: const Icon(Icons.add, size: 18), label: const Text('创建角色')),
            ]),
            content: SizedBox(
              width: 760,
              height: 520,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 220,
                  child: ListView(children: [
                    for (final x in roles)
                      HoverTile(
                        selected: x.id == sel,
                        onTap: () => set(() => sel = x.id),
                        child: Row(children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: x.color == 0 ? t.muted : Color(x.color), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(x.name, overflow: TextOverflow.ellipsis)),
                          if (!editable(x)) Icon(Icons.lock, size: 14, color: t.muted),
                          Text('${app.members.values.where((m) => x.id == RoleDef.everyone || m.roles.contains(x.id)).length}',
                              style: TextStyle(color: t.muted, fontSize: 12)),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('越靠上的角色权限越高。只能管理比你最高角色低的角色。', style: TextStyle(color: t.muted, fontSize: 11.5)),
                    ),
                  ]),
                ),
                VerticalDivider(color: t.divider),
                Expanded(child: r == null ? const SizedBox() : _RoleEditor(key: ValueKey(r.id), app: app, role: r, editable: editable(r))),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('完成'))],
          );
        });
      },
    ),
  );
}

class _RoleEditor extends StatefulWidget {
  final AppState app;
  final RoleDef role;
  final bool editable;
  const _RoleEditor({super.key, required this.app, required this.role, required this.editable});
  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late final _name = TextEditingController(text: widget.role.name);

  void _update(Map<String, dynamic> m) => widget.app.send({'t': Msg.roleUpdate, 'id': widget.role.id, ...m});

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final r = widget.role;
    final app = widget.app;
    final everyone = r.id == RoleDef.everyone;
    final ed = widget.editable;
    final mine = app.basePerms;
    return ListView(padding: const EdgeInsets.only(right: 8), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _name,
            enabled: ed && !everyone,
            maxLength: 32,
            decoration: const InputDecoration(labelText: '角色名称'),
            onSubmitted: (v) => _update({'name': v.trim()}),
            onTapOutside: (_) {
              if (_name.text.trim() != r.name && _name.text.trim().isNotEmpty) _update({'name': _name.text.trim()});
            },
          ),
        ),
        if (!everyone && ed) ...[
          BarButton(Icons.arrow_upward, '上移（权限更高）', () => app.send({'t': Msg.roleMove, 'id': r.id, 'delta': 1})),
          BarButton(Icons.arrow_downward, '下移', () => app.send({'t': Msg.roleMove, 'id': r.id, 'delta': -1})),
          BarButton(Icons.delete_outline, '删除角色', () async {
            if (await confirm(context, '删除角色', '确定删除「${r.name}」？拥有此角色的成员将失去它。', danger: true)) {
              app.send({'t': Msg.roleDelete, 'id': r.id});
            }
          }, color: t.danger),
        ],
      ]),
      if (!everyone) ...[
        const Text('颜色'),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in _roleColors)
            InkWell(
              onTap: ed ? () => _update({'color': c}) : null,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c == 0 ? t.input : Color(c),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: r.color == c ? t.text : t.divider, width: r.color == c ? 2 : 1),
                ),
                child: c == 0 ? Icon(Icons.block, size: 14, color: t.muted) : null,
              ),
            ),
        ]),
        SwitchListTile(
          value: r.hoist,
          onChanged: ed ? (v) => _update({'hoist': v}) : null,
          title: const Text('在成员列表中单独显示'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: r.mentionable,
          onChanged: ed ? (v) => _update({'ment': v}) : null,
          title: Text('允许任何人 @${r.name}'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
      const Divider(),
      Text(everyone ? '所有成员的默认权限' : '权限', style: const TextStyle(fontWeight: FontWeight.w700)),
      for (final (bit, label, desc) in Perm.labels)
        SwitchListTile(
          value: r.perms & bit != 0,
          // can't toggle what I don't have myself
          onChanged: ed && (app.isOwner || mine & bit != 0) ? (v) => _update({'perms': v ? r.perms | bit : r.perms & ~bit}) : null,
          title: Text(label, style: TextStyle(color: bit == Perm.administrator ? t.danger : null)),
          subtitle: desc.isEmpty ? null : Text(desc, style: TextStyle(color: t.muted, fontSize: 12)),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
    ]);
  }
}

/// Assign roles to a member.
Future<void> memberRolesDialog(BuildContext context, AppState app, Member m) async {
  final sel = {...m.roles};
  await showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = PulseColors.of(c);
      final roles = app.sortedRoles.where((r) => r.id != RoleDef.everyone).toList();
      return AlertDialog(
        title: Text('${m.display} 的角色'),
        content: SizedBox(
          width: 380,
          height: 400,
          child: roles.isEmpty
              ? Center(child: Text('还没有角色，可在“角色与权限”中创建', style: TextStyle(color: t.muted)))
              : ListView(children: [
                  for (final r in roles)
                    CheckboxListTile(
                      value: sel.contains(r.id),
                      onChanged: app.isOwner || r.position < app.myTop ? (v) => set(() => v == true ? sel.add(r.id) : sel.remove(r.id)) : null,
                      title: Align(alignment: Alignment.centerLeft, child: RoleChip(r)),
                      dense: true,
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              app.send({'t': Msg.memberRoles, 'id': m.id, 'roles': sel.toList()});
              Navigator.pop(c);
            },
            child: const Text('保存'),
          ),
        ],
      );
    }),
  );
}

/// Per-channel permission overwrites: for each role, every channel permission is
/// inherit / allow / deny.
Future<void> channelPermsDialog(BuildContext context, AppState app, ChannelInfo ch) async {
  final ow = {for (final o in ch.overwrites) o.role: Overwrite(o.role, o.allow, o.deny)};
  int sel = RoleDef.everyone;
  const voiceOnly = Perm.connect | Perm.speak | Perm.stream | Perm.muteMembers | Perm.moveMembers;
  const textOnly = Perm.sendMessages | Perm.attachFiles | Perm.addReactions | Perm.mentionEveryone | Perm.manageMessages;
  final scoped = Perm.labels.where((l) => l.$1 & Perm.channelScoped != 0 && l.$1 & (ch.isVoice ? textOnly : voiceOnly) == 0).toList();
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = PulseColors.of(c);
      final roles = app.sortedRoles;
      final o = ow[sel] ?? Overwrite(sel, 0, 0);
      int state(int bit) => o.allow & bit != 0 ? 1 : (o.deny & bit != 0 ? -1 : 0);
      void setState(int bit, int v) => set(() {
            final x = ow[sel] ??= Overwrite(sel, 0, 0);
            x.allow &= ~bit;
            x.deny &= ~bit;
            if (v == 1) x.allow |= bit;
            if (v == -1) x.deny |= bit;
          });
      return AlertDialog(
        title: Text('「${ch.name}」频道权限'),
        content: SizedBox(
          width: 720,
          height: 480,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 200,
              child: ListView(children: [
                for (final r in roles)
                  HoverTile(
                    selected: r.id == sel,
                    onTap: () => set(() => sel = r.id),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: r.color == 0 ? t.muted : Color(r.color), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                      if ((ow[r.id]?.allow ?? 0) != 0 || (ow[r.id]?.deny ?? 0) != 0) Icon(Icons.tune, size: 14, color: t.accent),
                    ]),
                  ),
              ]),
            ),
            VerticalDivider(color: t.divider),
            Expanded(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('“继承”使用角色本身的权限；“拒绝”优先于 @everyone，任一角色“允许”即可覆盖拒绝。拥有“管理员”权限的角色不受频道权限限制。',
                      style: TextStyle(color: t.muted, fontSize: 12)),
                ),
                if (sel == RoleDef.everyone)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => setState(Perm.viewChannel, -1),
                      icon: const Icon(Icons.lock, size: 16),
                      label: const Text('设为私密频道（@everyone 不可见，再给需要的角色“允许查看”）'),
                    ),
                  ),
                for (final (bit, label, _) in scoped)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(label)),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: [
                          ButtonSegment(value: -1, icon: Icon(Icons.close, size: 16, color: t.danger), tooltip: '拒绝'),
                          const ButtonSegment(value: 0, icon: Icon(Icons.horizontal_rule, size: 16), tooltip: '继承'),
                          ButtonSegment(value: 1, icon: Icon(Icons.check, size: 16, color: t.online), tooltip: '允许'),
                        ],
                        selected: {state(bit)},
                        onSelectionChanged: (v) => setState(bit, v.first),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      );
    }),
  );
  if (ok == true) {
    app.send({
      't': Msg.channelPerms,
      'id': ch.id,
      'ow': [for (final o in ow.values) if (o.allow != 0 || o.deny != 0) o.toJson()],
    });
  }
}

/// Attachment storage: retention, total quota (oldest deleted first), per-file limit.
Future<void> storageDialog(BuildContext context, AppState app) async {
  app.send({'t': Msg.storageInfo});
  final days = TextEditingController(text: '${app.fileDays}');
  final maxGb = TextEditingController(text: (app.storageMB / 1024).toStringAsFixed(app.storageMB % 1024 == 0 ? 0 : 1));
  final fileMb = TextEditingController(text: '${app.fileMaxMB}');
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => AnimatedBuilder(
      animation: app,
      builder: (c, _) {
        final t = PulseColors.of(c);
        final used = asInt(app.storage['used']);
        final max = app.storageMB * 1024 * 1024;
        return AlertDialog(
          title: const Text('文件存储'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('已用 ${formatBytes(used)} / ${formatBytes(max)} · ${asInt(app.storage['files'])} 个文件'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: max == 0 ? 0 : (used / max).clamp(0.0, 1.0), minHeight: 6),
              const SizedBox(height: 16),
              TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '保留天数', suffixText: '天', helperText: '上传的文件超过此时间自动删除')),
              const SizedBox(height: 10),
              TextField(
                  controller: maxGb,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '存储上限', suffixText: 'GB', helperText: '超出上限时先删除最旧的文件')),
              const SizedBox(height: 10),
              TextField(
                  controller: fileMb,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '单个文件上限', suffixText: 'MB', helperText: '最大 2048 MB（2 GB）')),
              const SizedBox(height: 10),
              Text('降低上限或保留天数会立即删除超出的旧文件。', style: TextStyle(color: t.idle, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
  final d = int.tryParse(days.text.trim());
  final g = double.tryParse(maxGb.text.trim());
  final f = int.tryParse(fileMb.text.trim());
  if (d == null || d < 1 || g == null || g <= 0 || f == null || f < 1) {
    app.toast('请输入有效的数值');
    return;
  }
  app.send({
    't': Msg.serverSettings,
    'fileDays': d,
    'storageMB': (g * 1024).round().clamp(1, 1 << 30),
    'fileMaxMB': f.clamp(1, kMaxFileBytes ~/ (1024 * 1024)),
  });
}

/// Pick a member to start a DM with.
Future<void> newDmDialog(BuildContext context, AppState app) async {
  var q = '';
  await showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = PulseColors.of(c);
      final list = app.members.values
          .where((m) => m.id != app.me && (q.isEmpty || m.display.toLowerCase().contains(q) || m.username.toLowerCase().contains(q)))
          .toList()
        ..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0) != 0 ? (b.online ? 1 : 0) - (a.online ? 1 : 0) : a.display.compareTo(b.display));
      return AlertDialog(
        title: const Text('发起私信'),
        content: SizedBox(
          width: 400,
          height: 420,
          child: Column(children: [
            TextField(autofocus: true, decoration: const InputDecoration(hintText: '搜索成员', prefixIcon: Icon(Icons.search)), onChanged: (v) => set(() => q = v.trim().toLowerCase())),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('没有找到成员', style: TextStyle(color: t.muted)))
                  : ListView(children: [
                      for (final m in list)
                        HoverTile(
                          onTap: () {
                            Navigator.pop(c);
                            app.openDm(m.id);
                          },
                          child: Row(children: [
                            Avatar(m, size: 32, showPresence: true),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.display, style: TextStyle(color: nameColor(c, m), fontWeight: FontWeight.w600)),
                                Text(m.username, style: TextStyle(color: t.muted, fontSize: 12)),
                              ]),
                            ),
                          ]),
                        ),
                    ]),
            ),
          ]),
        ),
      );
    }),
  );
}
