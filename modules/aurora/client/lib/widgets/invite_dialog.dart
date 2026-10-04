import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../main.dart';
import '../platform/invitations.dart';
import '../state/app_state.dart';

Future<void> showInviteDialog(BuildContext context) => showDialog(
  useRootNavigator: false,
  context: context,
  builder: (_) => InviteDialog(app: AppScope.read(context)),
);

class InviteDialog extends StatefulWidget {
  final AppState app;
  const InviteDialog({super.key, required this.app});
  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> {
  late final url = TextEditingController(text: suggestedWebUrl(widget.app));
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = roomInvitation(widget.app, url.text);
    return AlertDialog(
      title: const Text('邀请好友 · 扫码加入'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '好友可访问的网页版地址',
                  hintText: 'https://play.example.com',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                '内网穿透时填写实际网页入口地址。手机扫码后可直接用浏览器打开，房间密码需另行输入。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (link != null) ...[
                QrImageView(
                  data: link,
                  size: 220,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'Aurora 房间邀请二维码',
                ),
                const SizedBox(height: 12),
                SelectableText(link),
              ] else
                const Text('请填写有效的 http 或 https 地址'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: link == null
              ? null
              : () {
                  widget.app.prefs.setString(
                    'inviteWeb:${widget.app.address}',
                    url.text.trim(),
                  );
                  copyText(context, '来 Aurora 一起玩！\n$link');
                },
          child: const Text('复制邀请链接'),
        ),
      ],
    );
  }
}

class InvitationBanner extends StatelessWidget {
  final AppState app;
  const InvitationBanner({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    final code = app.pendingInvitation?.room;
    if (code == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        title: Text('邀请房间：$code'),
        subtitle: const Text('已连接服务器，点击加入邀请房间'),
        trailing: FilledButton(
          onPressed: () async {
            final pwd = TextEditingController();
            final ok = await showDialog<bool>(
              useRootNavigator: false,
              context: context,
              builder: (c) => AlertDialog(
                title: Text('加入房间 $code'),
                content: TextField(
                  controller: pwd,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '房间密码（没有则留空）'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('加入'),
                  ),
                ],
              ),
            );
            final password = pwd.text;
            // The dialog route may still be animating; its controller is disposed after the transition.
            Future<void>.delayed(const Duration(seconds: 1), pwd.dispose);
            if (ok == true) {
              app.send({'t': Msg.joinRoom, 'room': code, 'password': password});
            }
          },
          child: const Text('加入'),
        ),
      ),
    );
  }
}
