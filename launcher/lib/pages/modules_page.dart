import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show SetEnvironmentVariable;

import 'package:aurora_client/embed.dart';
import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pulse_client/embed.dart';

import '../i18n/i18n.dart';
import '../module_themes.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Aurora party games (cards, mahjong, board games, drawing …), embedded in the CML window.
class AuroraPage extends StatelessWidget {
  const AuroraPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = CmlPalette.of(context);
    return _ModuleFrame(child: AuroraEmbed(theme: ModuleThemes.aurora(pal)));
  }
}

/// Pulse text / voice chat, embedded in the CML window. Voice keeps running on other pages.
class PulsePage extends StatefulWidget {
  const PulsePage({super.key});
  @override
  State<PulsePage> createState() => _PulsePageState();
}

class _PulsePageState extends State<PulsePage> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final pal = CmlPalette.of(context);
    final modelsReady = AddonManager.isInstalled(Addons.pulseModels.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!modelsReady && !_dismissed)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
          child: MaterialBanner(
            elevation: 0,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            leading: const Icon(Icons.graphic_eq),
            content: Text(trGlobal('AI 变声需要单独下载「{0}」（{1}）。文字、语音、降噪和经典变声无需下载即可使用。', [trCore(Addons.pulseModels.name), trCore(Addons.pulseModels.sizeHint)])),
            actions: [
              TextButton(onPressed: () => setState(() => _dismissed = true), child: Text(trGlobal('以后再说'))),
              FilledButton.tonal(onPressed: () => showAddonsDialog(context), child: Text(trGlobal('管理分包'))),
            ],
          ),
        ),
      Expanded(child: _ModuleFrame(child: PulseEmbed(theme: ModuleThemes.pulse(pal), voicesDir: p.join(AddonManager.dirOf(Addons.pulseVoices.id), 'voices')))),
    ]);
  }
}

/// Rounded card that clips an embedded module to the content area.
class _ModuleFrame extends StatelessWidget {
  final Widget child;
  const _ModuleFrame({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: CmlColors.of(context).cardBorder)),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
        ),
      );
}

/// Sets `PULSE_MODELS_DIR` for pulse_native.dll. Must run before Pulse's native engine starts.
void configurePulseModels() {
  final dir = p.join(AddonManager.dirOf(Addons.pulseModels.id), 'models');
  if (Directory(dir).existsSync()) setProcessEnv('PULSE_MODELS_DIR', dir);
}

/// Sets a variable in this process's environment block (visible to native DLLs and child processes).
void setProcessEnv(String name, String value) {
  if (!Platform.isWindows) return;
  final n = name.toNativeUtf16(), v = value.toNativeUtf16();
  try {
    SetEnvironmentVariable(n, v);
  } finally {
    malloc.free(n);
    malloc.free(v);
  }
}

/// Dialog listing the optional add-ons ("分包"): install / update / remove / install from file.
Future<void> showAddonsDialog(BuildContext context) => showDialog(context: context, builder: (_) => const AddonsDialog());

class AddonsDialog extends StatefulWidget {
  const AddonsDialog({super.key});
  @override
  State<AddonsDialog> createState() => _AddonsDialogState();
}

class _AddonsDialogState extends State<AddonsDialog> {
  Map<String, AddonRelease>? _remote;
  final Map<String, String?> _installed = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final addons = App.read(context).ctx.addons;
    for (final a in Addons.all) {
      _installed[a.id] = await AddonManager.installedVersion(a.id);
    }
    if (mounted) setState(() {});
    try {
      final r = await addons.available();
      if (mounted) setState(() => _remote = r);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Future<void> _install(AddonRelease r) async {
    final app = App.read(context);
    Navigator.pop(context);
    await app.runTask(trGlobal('安装 {0}', [r.id]), (t) => app.ctx.addons.install(r, task: t), onError: (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    });
    if (r.id == Addons.pulseModels.id) configurePulseModels();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(trGlobal('分包管理')),
      content: SizedBox(
        width: 620,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(trGlobal('大文件（AI 模型权重）不包含在 CML 主压缩包中，可按需下载。分包安装在 {0}，CML 更新时不会被删除。', [AddonManager.root]),
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
          const SizedBox(height: 12),
          for (final a in Addons.all) _row(a),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(trGlobal('无法获取分包列表：{0}', [_error]), style: TextStyle(color: t.colorScheme.error))),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('关闭')))],
    );
  }

  Widget _row(AddonInfo a) {
    final t = Theme.of(context);
    final cur = _installed[a.id];
    final r = _remote?[a.id];
    final canUpdate = r != null && cur != null && cur != r.version;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.inventory_2_outlined, color: t.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(trCore(a.name), style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Pill(cur == null ? trGlobal('未安装') : trGlobal('已安装 {0}', [cur]), color: cur == null ? t.hintColor : Colors.green),
              ]),
              const SizedBox(height: 2),
              Text('${trCore(a.description)} · ${r != null && r.asset.size > 0 ? fmtBytes(r.asset.size) : trCore(a.sizeHint)}',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
            ]),
          ),
          const SizedBox(width: 8),
          if (cur != null)
            IconButton(
              tooltip: trGlobal('删除'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, trGlobal('删除分包'), trGlobal('删除「{0}」？', [trCore(a.name)]), danger: true)) return;
                await AddonManager.uninstall(a.id);
                await _refresh();
              },
            ),
          if (r != null && (cur == null || canUpdate))
            FilledButton(onPressed: () => _install(r), child: Text(cur == null ? trGlobal('下载安装') : trGlobal('更新'))),
          if (r == null && _remote != null && cur == null) Text(trGlobal('暂无'), style: TextStyle(color: t.hintColor)),
          if (_remote == null && _error == null) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
    );
  }
}
