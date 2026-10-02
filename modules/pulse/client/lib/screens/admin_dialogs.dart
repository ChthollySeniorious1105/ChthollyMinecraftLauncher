import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';
import '../widgets/common.dart';

Future<void> createChannelDialog(BuildContext context, AppState app, {String kind = ChannelKind.text}) async {
  final name = TextEditingController();
  var k = kind;
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('创建频道'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: k,
              onChanged: (v) => set(() => k = v ?? k),
              child: const Column(children: [
                RadioListTile(value: ChannelKind.text, title: Text('文字频道'), secondary: Icon(Icons.tag)),
                RadioListTile(value: ChannelKind.voice, title: Text('语音频道'), secondary: Icon(Icons.volume_up)),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(controller: name, autofocus: true, maxLength: kMaxChannelName, decoration: const InputDecoration(hintText: '频道名称'),
                onSubmitted: (_) => Navigator.pop(c, true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('创建')),
        ],
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) app.send({'t': Msg.chCreate, 'name': name.text.trim(), 'kind': k});
}

Future<void> editChannelDialog(BuildContext context, AppState app, ChannelInfo ch) async {
  final name = TextEditingController(text: ch.name);
  final topic = TextEditingController(text: ch.topic);
  var slow = ch.slowmode;
  var bitrate = ch.bitrate;
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('编辑 ${ch.isVoice ? '语音' : '文字'}频道'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('名称'),
            const SizedBox(height: 4),
            TextField(controller: name, maxLength: kMaxChannelName),
            if (!ch.isVoice) ...[
              const Text('主题'),
              const SizedBox(height: 4),
              TextField(controller: topic, maxLength: kMaxTopic, maxLines: 2),
              const SizedBox(height: 8),
              Text('慢速模式：${slow == 0 ? '关' : '$slow 秒'}'),
              Slider(
                value: [0, 5, 10, 30, 60, 300, 900, 3600].indexOf(slow).clamp(0, 7).toDouble(),
                min: 0,
                max: 7,
                divisions: 7,
                onChanged: (v) => set(() => slow = [0, 5, 10, 30, 60, 300, 900, 3600][v.round()]),
              ),
            ] else ...[
              Text('音质（码率上限）：${bitrate ~/ 1000} kbps'),
              Slider(value: bitrate.toDouble(), min: 16000, max: 128000, divisions: 14, onChanged: (v) => set(() => bitrate = (v / 8000).round() * 8000)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    ),
  );
  if (ok == true) {
    app.send({
      't': Msg.chUpdate,
      'id': ch.id,
      'name': name.text.trim(),
      if (!ch.isVoice) 'topic': topic.text.trim(),
      if (!ch.isVoice) 'slowmode': slow,
      if (ch.isVoice) 'bitrate': bitrate,
    });
  }
}

Future<void> inviteDialog(BuildContext context, AppState app) async {
  var uses = 1, hours = 24;
  Map<String, dynamic>? result;
  StreamSubscription? sub;
  await showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      sub ??= app.inviteCodes.listen((m) => set(() => result = m));
      final t = PulseColors.of(c);
      return AlertDialog(
        title: const Text('邀请他人'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('把服务器地址发给朋友即可加入。${app.regMode == RegMode.invite ? '当前服务器需要邀请码才能注册。' : ''}', style: TextStyle(color: t.muted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: SelectableText(app.address ?? '', style: const TextStyle(fontFamily: 'Consolas', fontSize: 16))),
              IconButton(icon: const Icon(Icons.copy), onPressed: () => copyText(c, app.address ?? '')),
            ]),
            const Divider(height: 24),
            const Text('生成注册邀请码'),
            Row(children: [
              const Text('可用次数'),
              const SizedBox(width: 8),
              DropdownButton<int>(value: uses, items: [for (final u in [1, 5, 10, 50, 0]) DropdownMenuItem(value: u, child: Text(u == 0 ? '不限' : '$u'))],
                  onChanged: (v) => set(() => uses = v ?? 1)),
              const SizedBox(width: 20),
              const Text('有效期'),
              const SizedBox(width: 8),
              DropdownButton<int>(value: hours, items: [for (final h in [1, 24, 168, 720, 0]) DropdownMenuItem(value: h, child: Text(h == 0 ? '永久' : (h < 24 ? '$h 小时' : '${h ~/ 24} 天')))],
                  onChanged: (v) => set(() => hours = v ?? 24)),
            ]),
            if (result != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.input, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Expanded(child: SelectableText('${result!['code']}', style: const TextStyle(fontFamily: 'Consolas', fontSize: 22, letterSpacing: 2))),
                  IconButton(icon: const Icon(Icons.copy), onPressed: () => copyText(c, '服务器：${app.address}\n邀请码：${result!['code']}')),
                ]),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          FilledButton(onPressed: () => app.send({'t': Msg.createInvite, 'uses': uses, 'hours': hours}), child: const Text('生成邀请码')),
        ],
      );
    }),
  );
  await sub?.cancel();
}

Future<void> serverSettingsDialog(BuildContext context, AppState app) async {
  final name = TextEditingController(text: app.serverName);
  final motd = TextEditingController(text: app.motd);
  final pass = TextEditingController();
  var reg = app.regMode;
  var changePass = false;
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = PulseColors.of(c);
      return AlertDialog(
        title: const Text('服务器设置'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('服务器名称'),
              const SizedBox(height: 4),
              TextField(controller: name, maxLength: 24),
              const Text('公告（显示在服务器信息里）'),
              const SizedBox(height: 4),
              TextField(controller: motd, maxLength: 500, maxLines: 3),
              const SizedBox(height: 8),
              const Text('注册方式'),
              RadioGroup<String>(
                groupValue: reg,
                onChanged: (v) => set(() => reg = v ?? reg),
                child: const Column(children: [
                  RadioListTile(value: RegMode.open, title: Text('开放注册')),
                  RadioListTile(value: RegMode.invite, title: Text('需要邀请码')),
                  RadioListTile(value: RegMode.closed, title: Text('关闭注册')),
                ]),
              ),
              if (app.isOwner) ...[
                CheckboxListTile(
                  value: changePass,
                  onChanged: (v) => set(() => changePass = v ?? false),
                  title: Text(app.serverHasPass ? '修改 / 移除服务器进入密码' : '设置服务器进入密码'),
                  subtitle: Text('登录和注册都需要输入此密码；留空表示移除', style: TextStyle(color: t.muted, fontSize: 12)),
                ),
                if (changePass) TextField(controller: pass, obscureText: true, decoration: const InputDecoration(hintText: '新的服务器密码（留空 = 无密码）')),
              ],
            ]),
          ),
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
      't': Msg.serverSettings,
      'name': name.text.trim(),
      'motd': motd.text.trim(),
      'regMode': reg,
      if (changePass) 'serverPass': pass.text,
    });
  }
}

Future<void> bansDialog(BuildContext context, AppState app) async {
  app.send({'t': Msg.listBans});
  await showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => AnimatedBuilder(
      animation: app,
      builder: (c, _) {
        final t = PulseColors.of(c);
        return AlertDialog(
          title: const Text('封禁列表'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: app.bans.isEmpty
                ? Center(child: Text('没有被封禁的用户', style: TextStyle(color: t.muted)))
                : ListView(children: [
                    for (final b in app.bans)
                      ListTile(
                        leading: const Icon(Icons.block),
                        title: Text('${b['display']}（${b['user']}）'),
                        subtitle: Text('${formatTime(asInt(b['at']))}${asStr(b['reason']).isEmpty ? '' : ' · ${b['reason']}'}'),
                        trailing: TextButton(onPressed: () => app.send({'t': Msg.unban, 'id': b['id']}), child: const Text('解除')),
                      ),
                  ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
        );
      },
    ),
  );
}

void showServerInfo(BuildContext context, AppState app) {
  final online = app.members.values.where((m) => m.online).length;
  showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) {
      final t = PulseColors.of(c);
      return AlertDialog(
        title: Text(app.serverName),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (app.motd.isNotEmpty) ...[Text(app.motd), const Divider(height: 24)],
            _kv('地址', app.address ?? '', t),
            _kv('成员', '${app.members.length} 人（$online 在线）', t),
            _kv('注册', switch (app.regMode) { RegMode.invite => '需要邀请码', RegMode.closed => '已关闭', _ => '开放' }, t),
            _kv('延迟', '${app.conn.pingMs} ms', t),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.lock, size: 16, color: t.online),
              const SizedBox(width: 6),
              Text('端到服务器加密（X25519 + ChaCha20-Poly1305）', style: TextStyle(color: t.online, fontSize: 12.5)),
            ]),
            const SizedBox(height: 4),
            SelectableText('服务器指纹 ${app.fingerprint}', style: TextStyle(fontFamily: 'Consolas', color: t.muted, fontSize: 12.5)),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
      );
    },
  );
}

Widget _kv(String k, String v, PulseTheme t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 60, child: Text(k, style: TextStyle(color: t.muted))),
        Expanded(child: SelectableText(v)),
      ]),
    );
