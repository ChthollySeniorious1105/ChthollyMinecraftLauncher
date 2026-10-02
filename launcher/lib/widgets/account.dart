import 'dart:async';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';

import '../state.dart';

/// Microsoft sign-in: the user enters a short code at microsoft.com/link.
Future<MsAccount?> showLoginDialog(BuildContext context) => showDialog<MsAccount>(context: context, barrierDismissible: false, builder: (_) => const _LoginDialog());

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  DeviceCode? code;
  String step = trGlobal('正在获取登录代码…');
  String? error;
  bool copied = false;
  bool finishing = false;
  late LoginMethod method;
  CancelToken cancel = CancelToken();
  DateTime? expires;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    method = App.read(context).ctx.auth.defaultMethod;
    _start();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && code != null) setState(() {});
    });
  }

  Future<void> _start() async {
    final app = App.read(context);
    cancel.cancel();
    cancel = CancelToken();
    final myCancel = cancel;
    setState(() {
      code = null;
      error = null;
      copied = false;
      finishing = false;
      step = trGlobal('正在获取登录代码…');
    });
    try {
      final dc = await app.ctx.auth.startDeviceCode(method: method);
      if (!mounted || myCancel.isCancelled) return;
      setState(() {
        code = dc;
        expires = DateTime.now().add(Duration(seconds: dc.expiresIn));
        step = trGlobal('等待你在浏览器中完成登录');
      });
      await _copy();
      final acc = await app.ctx.auth.pollDeviceCode(dc, cancel: myCancel, onStep: (s) {
        if (mounted) {
          setState(() {
            finishing = true;
            step = s;
          });
        }
      });
      app.ctx.accounts.upsert(acc);
      await app.ctx.accounts.save();
      app.changed();
      if (mounted) Navigator.pop(context, acc);
    } on CancelledException {
      // replaced by a new attempt or dialog closed
    } catch (e) {
      if (mounted && !myCancel.isCancelled) setState(() => error = errText(e));
    }
  }

  Future<void> _copy() async {
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code!.userCode));
    if (mounted) setState(() => copied = true);
  }

  void _open() => launchUrl(Uri.parse(code!.directUri));

  @override
  void dispose() {
    cancel.cancel();
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final left = expires == null ? 0 : expires!.difference(DateTime.now()).inSeconds.clamp(0, 99999);
    final hasAzure = MsaConfig.clientId.isNotEmpty;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 12, 18),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Row(children: [
              const _MsLogo(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trGlobal('登录 Microsoft 账号'), style: t.textTheme.titleMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
                  Text(trGlobal('使用拥有 Minecraft Java 版的账号'), style: t.textTheme.bodySmall?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85))),
                ]),
              ),
              IconButton(icon: Icon(Icons.close, color: cs.onPrimary), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: error != null
                  ? _errorView(t)
                  : code == null
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
                      : finishing
                          ? _finishingView(t)
                          : _codeView(t, left),
            ),
          ),
          if (hasAzure)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(children: [
                Text(trGlobal('登录方式'), style: t.textTheme.bodySmall),
                const SizedBox(width: 8),
                SegmentedButton<LoginMethod>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [ButtonSegment(value: LoginMethod.link, label: Text('microsoft.com/link')), ButtonSegment(value: LoginMethod.azure, label: Text(trGlobal('Azure 应用')))],
                  selected: {method},
                  onSelectionChanged: (s) {
                    method = s.first;
                    _start();
                  },
                ),
              ]),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _codeView(ThemeData t, int left) {
    final cs = t.colorScheme;
    final c = code!;
    return Column(key: const ValueKey('code'), mainAxisSize: MainAxisSize.min, children: [
      _StepRow(n: 1, text: trGlobal('打开 '), link: 'microsoft.com/link', onTap: _open),
      const SizedBox(height: 6),
      _StepRow(n: 2, text: trGlobal('输入下面的代码并登录你的 Microsoft 账号')),
      const SizedBox(height: 18),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _copy,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.primary.withValues(alpha: 0.35))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < c.userCode.length; i++) ...[
              if (i > 0 && i == c.userCode.length ~/ 2) const SizedBox(width: 14),
              Container(
                width: 34,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Text(c.userCode[i], style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary, fontFamily: 'Consolas')),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 8),
      AnimatedOpacity(
        opacity: copied ? 1 : 0.6,
        duration: const Duration(milliseconds: 200),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(copied ? Icons.check_circle : Icons.content_copy, size: 14, color: copied ? Colors.green : t.hintColor),
          const SizedBox(width: 4),
          Text(copied ? trGlobal('代码已复制，直接粘贴即可') : trGlobal('点击代码复制'), style: t.textTheme.bodySmall),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(trGlobal('打开 microsoft.com/link')),
            onPressed: _open,
          ),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Expanded(child: Text(step, style: t.textTheme.bodySmall)),
        Text(trGlobal('{0}:{1} 后过期', [left ~/ 60, (left % 60).toString().padLeft(2, '0')]), style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
      ]),
    ]);
  }

  Widget _finishingView(ThemeData t) => Padding(
        key: const ValueKey('finishing'),
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(children: [
          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(step, style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(trGlobal('浏览器中已完成授权，正在获取游戏档案'), style: t.textTheme.bodySmall),
        ]),
      );

  Widget _errorView(ThemeData t) => Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(children: [
          Icon(Icons.error_outline_rounded, size: 44, color: t.colorScheme.error),
          const SizedBox(height: 12),
          Text(error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(icon: const Icon(Icons.refresh), label: Text(trGlobal('重新获取代码')), onPressed: _start),
        ]),
      );
}

class _StepRow extends StatelessWidget {
  final int n;
  final String text;
  final String? link;
  final VoidCallback? onTap;
  const _StepRow({required this.n, required this.text, this.link, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      CircleAvatar(radius: 11, backgroundColor: t.colorScheme.primary, child: Text('$n', style: TextStyle(fontSize: 12, color: t.colorScheme.onPrimary, fontWeight: FontWeight.bold))),
      const SizedBox(width: 10),
      Text(text),
      if (link != null)
        InkWell(
          onTap: onTap,
          child: Text(link!, style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
        ),
    ]);
  }
}

/// Four-square Microsoft logo.
class _MsLogo extends StatelessWidget {
  final double size;
  const _MsLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final s = size / 2 - 1;
    Widget sq(Color c) => Container(width: s, height: s, color: c);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(const Color(0xFFF25022)), sq(const Color(0xFF7FBA00))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(const Color(0xFF00A4EF)), sq(const Color(0xFFFFB900))]),
        ]),
      ),
    );
  }
}

/// Player head from the Minecraft skin (face + hat layer).
class SkinHead extends StatelessWidget {
  final String? skinUrl;
  final double size;
  const SkinHead(this.skinUrl, {super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(size / 5)),
      child: Icon(Icons.person, size: size * 0.7, color: Theme.of(context).colorScheme.onPrimaryContainer),
    );
    if (skinUrl == null) return placeholder;
    Widget layer(double dx) => Positioned(
          left: -dx * size / 8,
          top: -size,
          child: Image.network(skinUrl!, width: size * 8, height: size * 8, filterQuality: FilterQuality.none, fit: BoxFit.fill, errorBuilder: (_, _, _) => const SizedBox()),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 5),
      child: SizedBox(width: size, height: size, child: Stack(clipBehavior: Clip.hardEdge, children: [layer(8), layer(40)])),
    );
  }
}

/// Shows a file's folder in Explorer.
Future<void> revealInExplorer(String path) async {
  if (await FileSystemEntity.isDirectory(path)) {
    await Process.start('explorer.exe', [path]);
  } else {
    await Process.start('explorer.exe', ['/select,', path]);
  }
}
