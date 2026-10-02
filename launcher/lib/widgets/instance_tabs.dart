import 'dart:convert';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import '../state.dart';
import 'account.dart';
import 'common.dart';

// ============================================================== mod updates

class ModUpdatesTab extends StatefulWidget {
  final String folder;
  final GameVersion? version;
  const ModUpdatesTab({super.key, required this.folder, required this.version});
  @override
  State<ModUpdatesTab> createState() => _ModUpdatesTabState();
}

class _ModUpdatesTabState extends State<ModUpdatesTab> {
  UpdateScan? scan;
  bool busy = false;
  bool beta = false;

  String? get loader => widget.version?.loaders.where((l) => l != ModLoader.optifine).firstOrNull?.slug;

  Future<void> _check() async {
    final app = App.read(context);
    final v = widget.version;
    if (v == null) return;
    setState(() => busy = true);
    final r = await app.runTask(context.tr('检查更新'), (t) => app.ctx.contentUpdater.check(widget.folder, gameVersion: v.baseVersion, loader: loader, includeBeta: beta, task: t),
        onError: (e) => toast(context, errText(e), error: true));
    if (mounted) {
      setState(() {
        scan = r;
        busy = false;
      });
    }
  }

  Future<void> _apply() async {
    final app = App.read(context);
    final list = scan!.updates.where((u) => u.selected).toList();
    if (list.isEmpty) return;
    setState(() => busy = true);
    final n = await app.runTask(context.tr('更新 {0} 个文件', [list.length]), (t) => app.ctx.contentUpdater.apply(list, task: t),
        onError: (e) => toast(context, errText(e), error: true));
    if (!mounted) return;
    setState(() => busy = false);
    if (n != null) {
      toast(context, context.tr('已更新 {0} 个文件，旧文件移到了 .cml-old 文件夹', [n]));
      _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = scan;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          FilledButton.icon(
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.update_rounded, size: 18),
            label: Text(context.tr('检查更新')),
            onPressed: busy || widget.version == null ? null : _check,
          ),
          const SizedBox(width: 12),
          Checkbox(value: beta, onChanged: (v) => setState(() => beta = v == true)),
          Text(context.tr('包含测试版')),
          const Spacer(),
          if (s != null && s.updates.isNotEmpty) ...[
            TextButton(
              onPressed: () => setState(() {
                final all = s.updates.every((u) => u.selected);
                for (final u in s.updates) {
                  u.selected = !all;
                }
              }),
              child: Text(context.tr('全选 / 取消')),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(context.tr('更新所选（{0}）', [s.updates.where((u) => u.selected).length])),
              onPressed: busy ? null : _apply,
            ),
          ],
        ]),
      ),
      Expanded(
        child: s == null
            ? EmptyHint(Icons.update_rounded, context.tr('通过 Modrinth 与 CurseForge 检查本版本 Mod、资源包、光影是否有新版本\n更新前旧文件会自动备份'))
            : ListView(padding: const EdgeInsets.all(12), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(context.tr('检查了 {0} 个文件：{1} 个可更新，{2} 个无法识别（非平台发布的文件）', [s.checked, s.updates.length, s.unknown.length]),
                      style: t.textTheme.bodySmall),
                ),
                if (s.updates.isEmpty) EmptyHint(Icons.check_circle_outline, context.tr('全部都是最新版本')),
                for (final u in s.updates)
                  CheckboxListTile(
                    value: u.selected,
                    onChanged: (v) => setState(() => u.selected = v == true),
                    title: Text(u.local.displayName),
                    subtitle: Text('${u.currentVersion}  →  ${u.latest.versionNumber}  ·  ${u.platform == ContentPlatform.modrinth ? 'Modrinth' : 'CurseForge'}'
                        '${u.latest.channel == 'release' ? '' : '  ·  ${u.latest.channel}'}'),
                    secondary: Icon(Icons.arrow_circle_up_rounded, color: t.colorScheme.primary),
                  ),
                if (s.unknown.isNotEmpty)
                  ExpansionTile(
                    title: Text(context.tr('无法识别的文件（{0}）', [s.unknown.length])),
                    children: [for (final f in s.unknown) ListTile(dense: true, title: Text(f.displayName))],
                  ),
              ]),
      ),
    ]);
  }
}

// ============================================================== screenshots

class ScreenshotsTab extends StatefulWidget {
  final String gameDir;
  const ScreenshotsTab({super.key, required this.gameDir});
  @override
  State<ScreenshotsTab> createState() => _ScreenshotsTabState();
}

class _ScreenshotsTabState extends State<ScreenshotsTab> {
  List<ScreenshotInfo>? shots;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await InstanceFiles.screenshots(widget.gameDir);
    if (mounted) setState(() => shots = s);
  }

  void _view(int i) => showDialog(context: context, builder: (_) => _Viewer(shots: shots!, index: i, onDeleted: _load));

  @override
  Widget build(BuildContext context) {
    final s = shots;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          Text(context.tr('{0} 张截图', [s.length])),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(context.tr('打开文件夹')),
            onPressed: () async {
              final d = Directory(p.join(widget.gameDir, 'screenshots'));
              await d.create(recursive: true);
              await revealInExplorer(d.path);
            },
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: s.isEmpty
            ? EmptyHint(Icons.photo_library_outlined, context.tr('还没有截图\n在游戏中按 F2 截图'))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 280, childAspectRatio: 16 / 10, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: s.length,
                itemBuilder: (_, i) => InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _view(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(s[i].file, fit: BoxFit.cover, cacheWidth: 400, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.black45,
                          child: Text(fmtDate(s[i].time), style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
      ),
    ]);
  }
}

class _Viewer extends StatefulWidget {
  final List<ScreenshotInfo> shots;
  final int index;
  final VoidCallback onDeleted;
  const _Viewer({required this.shots, required this.index, required this.onDeleted});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int i = widget.index;

  @override
  Widget build(BuildContext context) {
    final s = widget.shots[i];
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(24),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => setState(() => i = (i - 1).clamp(0, widget.shots.length - 1)),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => setState(() => i = (i + 1).clamp(0, widget.shots.length - 1)),
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(child: InteractiveViewer(child: Image.file(s.file, fit: BoxFit.contain))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  IconButton(onPressed: i > 0 ? () => setState(() => i--) : null, icon: const Icon(Icons.chevron_left, color: Colors.white)),
                  Text('${i + 1} / ${widget.shots.length}  ·  ${p.basename(s.file.path)}  ·  ${fmtBytes(s.size)}', style: const TextStyle(color: Colors.white)),
                  IconButton(onPressed: i < widget.shots.length - 1 ? () => setState(() => i++) : null, icon: const Icon(Icons.chevron_right, color: Colors.white)),
                  const Spacer(),
                  IconButton(
                    tooltip: context.tr('复制图片'),
                    icon: const Icon(Icons.copy, color: Colors.white),
                    onPressed: () async {
                      // copy via PowerShell (Flutter has no image clipboard on desktop)
                      await Process.run('powershell', [
                        '-NoProfile',
                        '-Command',
                        "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile('${s.file.path.replaceAll("'", "''")}'))"
                      ]);
                      if (context.mounted) toast(context, context.tr('已复制到剪贴板'));
                    },
                  ),
                  IconButton(tooltip: context.tr('在文件夹中显示'), icon: const Icon(Icons.folder_open, color: Colors.white), onPressed: () => revealInExplorer(s.file.path)),
                  IconButton(
                    tooltip: context.tr('删除'),
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () async {
                      if (!await confirm(context, context.tr('删除截图'), context.tr('删除 {0}？', [p.basename(s.file.path)]), danger: true)) return;
                      await s.file.delete();
                      widget.onDeleted();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================== logs

class LogsTab extends StatefulWidget {
  final String gameDir;
  const LogsTab({super.key, required this.gameDir});
  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  List<LogFile>? logs;
  LogFile? current;
  String text = '';
  String? diagnosis;
  String filter = '';
  bool onlyProblems = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await InstanceFiles.logs(widget.gameDir);
    if (!mounted) return;
    setState(() => logs = l);
    if (current == null && l.isNotEmpty) _open(l.first);
  }

  Future<void> _open(LogFile f) async {
    final t = await InstanceFiles.read(f);
    if (!mounted) return;
    setState(() {
      current = f;
      text = t;
      diagnosis = InstanceFiles.diagnose(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = logs;
    if (l == null) return const Center(child: CircularProgressIndicator());
    if (l.isEmpty) return EmptyHint(Icons.article_outlined, context.tr('这个版本还没有日志'));
    var lines = text.split('\n');
    if (onlyProblems) lines = lines.where((x) => x.contains('ERROR') || x.contains('WARN') || x.contains('Exception') || x.contains('Caused by') || x.trimLeft().startsWith('at ')).toList();
    if (filter.isNotEmpty) lines = lines.where((x) => x.toLowerCase().contains(filter)).toList();
    return Row(children: [
      SizedBox(
        width: 250,
        child: ListView(padding: const EdgeInsets.all(8), children: [
          for (final f in l)
            ListTile(
              dense: true,
              selected: identical(f, current),
              leading: Icon(f.crash ? Icons.report_rounded : Icons.article_outlined, color: f.crash ? t.colorScheme.error : null, size: 20),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${fmtDate(f.time)} · ${fmtBytes(f.size)}'),
              onTap: () => _open(f),
            ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: context.tr('搜索日志')),
                  onChanged: (v) => setState(() => filter = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(label: Text(context.tr('仅错误与警告')), selected: onlyProblems, onSelected: (v) => setState(() => onlyProblems = v)),
              IconButton(tooltip: context.tr('复制全部'), icon: const Icon(Icons.copy, size: 18), onPressed: () => Clipboard.setData(ClipboardData(text: text))),
              IconButton(tooltip: context.tr('在文件夹中显示'), icon: const Icon(Icons.folder_open, size: 18), onPressed: current == null ? null : () => revealInExplorer(current!.file.path)),
              IconButton(tooltip: context.tr('用记事本打开'), icon: const Icon(Icons.open_in_new, size: 18), onPressed: current == null ? null : () => Process.start('notepad.exe', [current!.file.path])),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
            ]),
          ),
          if (diagnosis != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(Icons.lightbulb_outline, color: t.colorScheme.onErrorContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(diagnosis!, style: TextStyle(color: t.colorScheme.onErrorContainer))),
              ]),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF14161B), borderRadius: BorderRadius.circular(10)),
              child: SelectionArea(
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final x = lines[i];
                    final c = x.contains('ERROR') || x.contains('Exception') || x.contains('Caused by')
                        ? const Color(0xFFFF7B7B)
                        : x.contains('WARN')
                            ? const Color(0xFFFFD27B)
                            : const Color(0xFFCFD6E0);
                    return Text(x, style: TextStyle(fontFamily: 'Consolas', fontSize: 11.5, color: c, height: 1.35));
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ============================================================== servers

class ServersTab extends StatefulWidget {
  final String gameDir;
  final String versionId;
  const ServersTab({super.key, required this.gameDir, required this.versionId});
  @override
  State<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends State<ServersTab> {
  List<SavedServer>? servers;
  final status = <String, ServerStatus?>{};
  final errors = <String, String>{};

  ServerList get list => ServerList(widget.gameDir);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await list.load();
      if (!mounted) return;
      setState(() => servers = s);
      _pingAll();
    } catch (e) {
      if (mounted) setState(() => servers = []);
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  void _pingAll() {
    for (final s in servers ?? <SavedServer>[]) {
      _ping(s);
    }
  }

  Future<void> _ping(SavedServer s) async {
    setState(() {
      status.remove(s.ip);
      errors.remove(s.ip);
    });
    try {
      final r = await ServerPinger.ping(s.ip);
      if (mounted) setState(() => status[s.ip] = r);
    } catch (e) {
      if (mounted) setState(() => errors[s.ip] = context.tr('无法连接'));
    }
  }

  Future<void> _save() async {
    await list.save(servers!);
    setState(() {});
  }

  Future<void> _edit([SavedServer? s]) async {
    final name = TextEditingController(text: s?.name ?? 'Minecraft Server');
    final ip = TextEditingController(text: s?.ip ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s == null ? context.tr('添加服务器') : context.tr('编辑服务器')),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: context.tr('服务器名称'))),
            const SizedBox(height: 10),
            TextField(controller: ip, autofocus: true, decoration: InputDecoration(labelText: context.tr('服务器地址'), hintText: 'mc.example.com:25565')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, ip.text.trim().isNotEmpty), child: Text(context.tr('保存'))),
        ],
      ),
    );
    if (ok != true) return;
    if (s == null) {
      final n = SavedServer(name.text.trim(), ip.text.trim());
      servers!.add(n);
      await _save();
      _ping(n);
    } else {
      s
        ..name = name.text.trim()
        ..ip = ip.text.trim();
      await _save();
      _ping(s);
    }
  }

  Future<void> _join(SavedServer s) async {
    final app = App.read(context);
    app.settings.selectedVersion = widget.versionId;
    await app.saveSettings();
    if (!mounted) return;
    app.gameLog.clear();
    await app.runTask(context.tr('启动 {0} 并进入 {1}', [widget.versionId, s.name]), (t) async {
      final gp = await app.ctx.launch(widget.versionId, task: t, onLog: app.addLog, joinServer: s.ip);
      app.running = gp;
      app.changed();
      gp.exitCode.then((_) {
        app.running = null;
        app.changed();
      });
    }, onError: (e) => toast(context, errText(e), error: true));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = servers;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          FilledButton.tonalIcon(icon: const Icon(Icons.add, size: 18), label: Text(context.tr('添加服务器')), onPressed: () => _edit()),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 16), label: Text(context.tr('全部刷新')), onPressed: _pingAll),
          const Spacer(),
          Text(context.tr('与游戏内「多人游戏」列表同步（servers.dat）'), style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
        ]),
      ),
      Expanded(
        child: s.isEmpty
            ? EmptyHint(Icons.dns_outlined, context.tr('还没有保存的服务器'))
            : ReorderableListView.builder(
                padding: const EdgeInsets.all(12),
                buildDefaultDragHandles: false,
                itemCount: s.length,
                onReorderItem: (a, b) async {
                  final x = s.removeAt(a);
                  s.insert(b, x);
                  await _save();
                },
                itemBuilder: (_, i) {
                  final sv = s[i];
                  final st = status[sv.ip];
                  final err = errors[sv.ip];
                  final iconBytes = st?.favicon ?? (sv.icon == null ? null : _b64(sv.icon!));
                  return Card(
                    key: ValueKey('$i|${sv.ip}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator, color: Colors.grey)),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: iconBytes == null
                              ? Container(width: 56, height: 56, color: t.colorScheme.surfaceContainerHighest, child: const Icon(Icons.dns_rounded))
                              : Image.memory(iconBytes, width: 56, height: 56, filterQuality: FilterQuality.none, gaplessPlayback: true),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(sv.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              Text(sv.ip, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                            ]),
                            const SizedBox(height: 4),
                            if (st != null) MotdText(st.motd) else Text(err ?? context.tr('正在连接…'), style: TextStyle(color: err != null ? t.colorScheme.error : t.hintColor)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        if (st != null)
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(children: [
                              Icon(Icons.signal_cellular_alt_rounded, size: 16, color: st.pingMs < 100 ? Colors.green : st.pingMs < 250 ? Colors.orange : Colors.red),
                              const SizedBox(width: 4),
                              Text('${st.pingMs} ms'),
                            ]),
                            Tooltip(
                              message: st.sample.isEmpty ? '' : st.sample.join('\n'),
                              child: Text('${st.online} / ${st.max}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Text(st.version, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor), maxLines: 1),
                          ]),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: App.of(context).running != null ? null : () => _join(sv), child: Text(context.tr('加入'))),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'edit':
                                await _edit(sv);
                              case 'copy':
                                await Clipboard.setData(ClipboardData(text: sv.ip));
                              case 'refresh':
                                _ping(sv);
                              case 'delete':
                                if (context.mounted && await confirm(context, context.tr('删除服务器'), context.tr('删除 {0}？', [sv.name]), danger: true)) {
                                  s.removeAt(i);
                                  await _save();
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: Text(context.tr('编辑'))),
                            PopupMenuItem(value: 'copy', child: Text(context.tr('复制地址'))),
                            PopupMenuItem(value: 'refresh', child: Text(context.tr('刷新'))),
                            PopupMenuItem(value: 'delete', child: Text(context.tr('删除'))),
                          ],
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  static Uint8List? _b64(String s) {
    try {
      return base64Decode(s.contains(',') ? s.substring(s.indexOf(',') + 1) : s);
    } catch (_) {
      return null;
    }
  }
}

/// Renders a Minecraft MOTD with § colour / bold / italic codes.
class MotdText extends StatelessWidget {
  final String motd;
  const MotdText(this.motd, {super.key});

  static const _colors = {
    '0': Color(0xFF000000), '1': Color(0xFF0000AA), '2': Color(0xFF00AA00), '3': Color(0xFF00AAAA), '4': Color(0xFFAA0000),
    '5': Color(0xFFAA00AA), '6': Color(0xFFFFAA00), '7': Color(0xFFAAAAAA), '8': Color(0xFF555555), '9': Color(0xFF5555FF),
    'a': Color(0xFF55FF55), 'b': Color(0xFF55FFFF), 'c': Color(0xFFFF5555), 'd': Color(0xFFFF55FF), 'e': Color(0xFFFFFF55), 'f': Color(0xFFFFFFFF),
  };

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall!;
    final spans = <TextSpan>[];
    Color? color;
    var bold = false, italic = false;
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString(), style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : null, fontStyle: italic ? FontStyle.italic : null)));
      buf.clear();
    }

    final s = motd.trim();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '§' && i + 1 < s.length) {
        flush();
        final c = s[++i].toLowerCase();
        if (_colors.containsKey(c)) {
          color = _colors[c];
          bold = italic = false;
        } else if (c == 'l') {
          bold = true;
        } else if (c == 'o') {
          italic = true;
        } else if (c == 'r') {
          color = null;
          bold = italic = false;
        }
      } else {
        buf.write(s[i]);
      }
    }
    flush();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(6)),
      child: Text.rich(TextSpan(style: base.copyWith(color: const Color(0xFFAAAAAA), fontFamily: 'Consolas'), children: spans), maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

// ============================================================== export

Future<void> showExportDialog(BuildContext context, String versionId, String gameDir) =>
    showDialog(context: context, builder: (_) => _ExportDialog(versionId: versionId, gameDir: gameDir));

class _ExportDialog extends StatefulWidget {
  final String versionId, gameDir;
  const _ExportDialog({required this.versionId, required this.gameDir});
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportFormat format = ExportFormat.modrinth;
  List<ExportEntry>? entries;
  late final name = TextEditingController(text: widget.versionId);
  final version = TextEditingController(text: '1.0.0');

  @override
  void initState() {
    super.initState();
    InstanceExporter.scan(widget.gameDir, widget.versionId).then((e) {
      if (mounted) setState(() => entries = e);
    });
  }

  Future<void> _export() async {
    final app = App.read(context);
    final loc = await getSaveLocation(suggestedName: '${name.text.trim()}.${format.ext}');
    if (loc == null || !mounted) return;
    final include = [for (final e in entries!) if (e.selected) e.path];
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.lang;
    Navigator.pop(context);
    final r = await app.runTask(
        context.tr('导出 {0}', [widget.versionId]),
        (t) => app.ctx.exporter.export(
              dir: app.ctx.gameDir,
              versionId: widget.versionId,
              gameDir: widget.gameDir,
              include: include,
              format: format,
              output: loc.path,
              name: name.text.trim(),
              version: version.text.trim(),
              task: t,
            ),
        onError: (e) => messenger.showSnackBar(SnackBar(content: Text(errText(e)))));
    if (r != null) {
      messenger.showSnackBar(SnackBar(content: Text(translate(lang, '已导出：{0} 个文件从平台下载，{1} 个文件打包在内', [r.referenced, r.bundled]))));
      await revealInExplorer(r.output);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = entries;
    final total = e == null ? 0 : e.where((x) => x.selected).fold<int>(0, (a, b) => a + b.size);
    return AlertDialog(
      title: Text(context.tr('导出实例 {0}', [widget.versionId])),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RadioGroup<ExportFormat>(
            groupValue: format,
            onChanged: (v) => setState(() => format = v!),
            child: Column(children: [
              for (final f in ExportFormat.values)
                RadioListTile<ExportFormat>(
                  dense: true,
                  value: f,
                  title: Text(context.tr(f.label)),
                  subtitle: Text(
                      context.tr(switch (f) {
                        ExportFormat.modrinth => 'Modrinth 上能找到的文件只记录下载地址，其余打包，体积小',
                        ExportFormat.curseforge => 'CurseForge 上能找到的文件只记录项目 ID，其余打包',
                        ExportFormat.full => '包含版本文件和全部选中内容，可离线导入到任何 CML',
                      }),
                      style: t.textTheme.bodySmall),
                ),
            ]),
          ),
          if (format != ExportFormat.full)
            Row(children: [
              Expanded(child: TextField(controller: name, decoration: InputDecoration(labelText: context.tr('整合包名称')))),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: TextField(controller: version, decoration: InputDecoration(labelText: context.tr('版本号')))),
            ]),
          const SizedBox(height: 10),
          Text(context.tr('包含的文件（约 {0}）', [fmtBytes(total)]), style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: e == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    for (final x in e)
                      CheckboxListTile(
                        dense: true,
                        value: x.selected,
                        onChanged: (v) => setState(() => x.selected = v == true),
                        title: Text(x.path),
                        subtitle: Text('${x.files} ${context.tr('个文件')} · ${fmtBytes(x.size)}'),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('取消'))),
        FilledButton(onPressed: e == null ? null : _export, child: Text(context.tr('导出'))),
      ],
    );
  }
}
