import 'dart:async';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/theme_picker.dart';
import '../widgets/common.dart';

/// `--settings-section N` scrolls to section N on first open (screenshots / shortcuts).
int? initialSettingsSection;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppState _app = App.read(context);
  late final s = _app.settings;
  late final jvm = TextEditingController(text: s.jvmArgs);
  late final game = TextEditingController(text: s.gameArgs);
  late final pre = TextEditingController(text: s.preLaunchCommand);
  late final cfKey = TextEditingController(text: s.curseforgeKey);
  late final ghMirror = TextEditingController(text: s.githubMirror);
  late final clientId = TextEditingController(text: s.msaClientId);
  late final width = TextEditingController(text: s.windowWidth?.toString() ?? '');
  late final height = TextEditingController(text: s.windowHeight?.toString() ?? '');
  late final _fields = [jvm, game, pre, cfKey, ghMirror, clientId, width, height];
  Timer? _saveTimer;
  bool scanning = false;
  final scroll = ScrollController();
  final _keys = List.generate(7, (_) => GlobalKey());
  int railIndex = 0;
  static List<String> get _names => ['Java', trGlobal('内存'), trGlobal('游戏'), trGlobal('下载'), trGlobal('账号'), trGlobal('外观'), trGlobal('启动器')];
  static const _icons = [Icons.coffee_outlined, Icons.memory_rounded, Icons.sports_esports_outlined, Icons.download_outlined, Icons.account_circle_outlined, Icons.palette_outlined, Icons.rocket_launch_outlined];

  @override
  void initState() {
    super.initState();
    // Text fields auto-save (debounced) so edits survive leaving the page without pressing Enter.
    for (final c in _fields) {
      c.addListener(_scheduleSave);
    }
    final i = initialSettingsSection;
    initialSettingsSection = null;
    if (i != null) WidgetsBinding.instance.addPostFrameCallback((_) => _jump(i));
  }

  List<Widget> _spaced(List<Widget> w) => [for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 18), w[i]]];

  void _jump(int i) {
    final c = _keys[i].currentContext;
    if (c == null) return;
    setState(() => railIndex = i);
    Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  /// Highlights the section currently at the top of the viewport.
  void _syncRail() {
    var best = 0;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy < 260) best = i;
    }
    if (scroll.hasClients && scroll.position.pixels >= scroll.position.maxScrollExtent - 4) best = _keys.length - 1;
    if (best != railIndex) setState(() => railIndex = best);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) _save();
    _saveTimer?.cancel();
    for (final c in _fields) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _save() {
    _saveTimer?.cancel();
    s
      ..jvmArgs = jvm.text.trim()
      ..gameArgs = game.text.trim()
      ..preLaunchCommand = pre.text.trim()
      ..curseforgeKey = cfKey.text.trim()
      ..githubMirror = ghMirror.text.trim()
      ..msaClientId = clientId.text.trim()
      ..windowWidth = int.tryParse(width.text.trim())
      ..windowHeight = int.tryParse(height.text.trim());
    _app.saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final mem = Memory.info();
    final maxMem = (mem.totalMb ~/ 256 * 256).clamp(1024, 131072);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 0, 0),
        child: SizedBox(
          width: 150,
          child: Column(children: [
            for (var i = 0; i < _names.length; i++)
              _RailItem(label: _names[i], icon: _icons[i], selected: i == railIndex, onTap: () => _jump(i)),
          ]),
        ),
      ),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _syncRail();
            return false;
          },
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 28, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced([
      // ---------------- Java ----------------
      KeyedSubtree(key: _keys[0], child: Section(
        title: 'Java',
        icon: Icons.coffee_outlined,
        actions: [
          TextButton.icon(
            icon: scanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 16),
            label: Text(trGlobal('自动扫描')),
            onPressed: scanning
                ? null
                : () async {
                    setState(() => scanning = true);
                    await app.ctx.java.scan();
                    if (mounted) setState(() => scanning = false);
                    app.changed();
                  },
          ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(trGlobal('手动添加')),
            onPressed: () async {
              final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'java.exe', extensions: ['exe'])]);
              if (f == null) return;
              final j = await app.ctx.java.addManual(f.path);
              if (!context.mounted) return;
              j == null ? toast(context, trGlobal('这不是有效的 Java'), error: true) : app.changed();
            },
          ),
        ],
        child: Column(children: [
          FieldRow(
            trGlobal('使用的 Java'),
            DropdownButton<String?>(
              isExpanded: true,
              value: app.ctx.java.installs.any((j) => j.path == s.javaPath) ? s.javaPath : null,
              items: [
                DropdownMenuItem(value: null, child: Text(trGlobal('自动选择（按游戏版本挑选合适的 Java，缺少时自动下载）'))),
                for (final j in app.ctx.java.installs) DropdownMenuItem(value: j.path, child: Text('${j.label}   ${j.path}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                s.javaPath = v;
                app.saveSettings();
              },
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 5.2,
            children: [for (final j in app.ctx.java.installs) _JavaCard(java: j, selected: s.javaPath == j.path)],
          ),
        ]),
      )),
      // ---------------- memory ----------------
      KeyedSubtree(key: _keys[1], child: Section(
        title: trGlobal('内存'),
        icon: Icons.memory_rounded,
        child: Column(children: [
          SwitchRow(trGlobal('自动分配内存'), s.autoMemory, (v) {
            setState(() => s.autoMemory = v);
            app.saveSettings();
          }, help: trGlobal('根据 Mod 数量、游戏版本和当前空闲内存自动决定，并给系统保留余量')),
          if (!s.autoMemory)
            FieldRow(
              trGlobal('最大内存'),
              Row(children: [
                Expanded(
                  child: Slider(
                    min: 512,
                    max: maxMem.toDouble(),
                    divisions: (maxMem - 512) ~/ 256,
                    value: s.memoryMb.toDouble().clamp(512, maxMem.toDouble()),
                    label: '${s.memoryMb} MB',
                    onChanged: (v) => setState(() => s.memoryMb = v.round()),
                    onChangeEnd: (_) => app.saveSettings(),
                  ),
                ),
                SizedBox(width: 90, child: Text('${s.memoryMb} MB')),
              ]),
            ),
          FieldRow(trGlobal('物理内存'), Text(trGlobal('共 {0} GB，当前可用 {1} GB', [(mem.totalMb / 1024).toStringAsFixed(1), (mem.availableMb / 1024).toStringAsFixed(1)]))),
          SwitchRow(trGlobal('启动前优化内存'), s.optimizeMemoryBeforeLaunch, (v) {
            setState(() => s.optimizeMemoryBeforeLaunch = v);
            app.saveSettings();
          }),
        ]),
      )),
      // ---------------- game ----------------
      KeyedSubtree(key: _keys[2], child: Section(
        title: trGlobal('游戏'),
        icon: Icons.sports_esports_outlined,
        child: Column(children: [
          SwitchRow(trGlobal('版本隔离'), s.isolateVersions, (v) {
            setState(() => s.isolateVersions = v);
            app.saveSettings();
          }, help: trGlobal('每个版本使用独立的 mods、存档、配置文件夹，互不影响')),
          FieldRow(
            trGlobal('窗口大小'),
            Row(children: [
              SizedBox(width: 90, child: TextField(controller: width, decoration: InputDecoration(hintText: trGlobal('宽')), onEditingComplete: _save)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
              SizedBox(width: 90, child: TextField(controller: height, decoration: InputDecoration(hintText: trGlobal('高')), onEditingComplete: _save)),
              const SizedBox(width: 16),
              Checkbox(
                value: s.fullscreen,
                onChanged: (v) {
                  setState(() => s.fullscreen = v!);
                  app.saveSettings();
                },
              ),
              Text(trGlobal('全屏')),
            ]),
          ),
          FieldRow(
            trGlobal('启动后启动器'),
            DropdownButton<int>(
              value: s.afterLaunch,
              items: [
                DropdownMenuItem(value: 0, child: Text(trGlobal('保持不变'))),
                DropdownMenuItem(value: 1, child: Text(trGlobal('最小化'))),
                DropdownMenuItem(value: 2, child: Text(trGlobal('关闭'))),
              ],
              onChanged: (v) {
                setState(() => s.afterLaunch = v!);
                app.saveSettings();
              },
            ),
          ),
          FieldRow(trGlobal('JVM 参数'), TextField(controller: jvm, onEditingComplete: _save, decoration: InputDecoration(hintText: trGlobal('附加在默认参数之后')))),
          FieldRow(trGlobal('游戏参数'), TextField(controller: game, onEditingComplete: _save)),
          FieldRow(trGlobal('启动前执行命令'), TextField(controller: pre, onEditingComplete: _save)),
        ]),
      )),
      // ---------------- downloads ----------------
      KeyedSubtree(key: _keys[3], child: Section(
        title: trGlobal('下载'),
        icon: Icons.download_outlined,
        child: Column(children: [
          FieldRow(
            trGlobal('游戏文件下载源'),
            DropdownButton<DownloadSource>(
              value: s.downloadSource,
              items: [for (final d in DownloadSource.values) DropdownMenuItem(value: d, child: Text(trCore(d.label)))],
              onChanged: (v) {
                setState(() => s.downloadSource = v!);
                app.saveSettings();
              },
            ),
          ),
          FieldRow(
            trGlobal('Mod / 资源下载源'),
            DropdownButton<ContentSource>(
              value: s.contentSource,
              items: [for (final d in ContentSource.values) DropdownMenuItem(value: d, child: Text(trCore(d.label)))],
              onChanged: (v) {
                setState(() => s.contentSource = v!);
                app.saveSettings();
              },
            ),
          ),
          FieldRow(
            trGlobal('下载线程数'),
            Row(children: [
              Expanded(
                child: Slider(
                  min: 4,
                  max: 128,
                  divisions: 31,
                  value: s.downloadThreads.toDouble(),
                  label: '${s.downloadThreads}',
                  onChanged: (v) => setState(() => s.downloadThreads = v.round()),
                  onChangeEnd: (_) => app.saveSettings(),
                ),
              ),
              SizedBox(width: 40, child: Text('${s.downloadThreads}')),
            ]),
          ),
          FieldRow('CurseForge API Key', TextField(controller: cfKey, obscureText: true, onEditingComplete: _save, decoration: InputDecoration(hintText: trGlobal('使用官方 CurseForge API 时需要')))),
          FieldRow(trGlobal('GitHub 加速前缀'), TextField(controller: ghMirror, onEditingComplete: _save, decoration: InputDecoration(hintText: trGlobal('例如 https://ghfast.top/（留空直连）'))),
              help: trGlobal('用于下载 Chunker、mihomo、CML 更新等 GitHub 文件')),
        ]),
      )),
      // ---------------- account ----------------
      KeyedSubtree(key: _keys[4], child: Section(
        title: trGlobal('账号'),
        icon: Icons.account_circle_outlined,
        child: Column(children: [
          SwitchRow(trGlobal('正版登录时验证 SSL 证书'), s.verifyLoginSsl, (v) async {
            if (!v && !await confirm(context, trGlobal('关闭证书验证'), trGlobal('关闭后登录请求可能被中间人截获。仅在公司/校园网络的代理导致登录失败时临时关闭。'), danger: true, ok: trGlobal('仍然关闭'))) return;
            setState(() => s.verifyLoginSsl = v);
            app.saveSettings();
          }),
          FieldRow(trGlobal('Azure 应用 ID'), TextField(controller: clientId, onEditingComplete: _save, decoration: InputDecoration(hintText: MsaConfig.builtInClientId.isEmpty ? trGlobal('必须填写（已获 Mojang 批准的应用）') : trGlobal('留空使用内置 ID'))),
              help: trGlobal('微软登录需要一个经过 Mojang 审核的 Azure 应用 ID（aka.ms/mce-reviewappid）')),
        ]),
      )),
      // ---------------- appearance ----------------
      KeyedSubtree(key: _keys[5], child: Section(
        title: trGlobal('外观'),
        icon: Icons.palette_outlined,
        child: Column(children: [
          FieldRow(
            'Language / 语言',
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<AppLanguage>(
                segments: [for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
                selected: {AppLanguage.fromCode(s.language)},
                onSelectionChanged: (v) {
                  s.language = v.first.code;
                  app.saveSettings();
                },
              ),
            ),
          ),
          FieldRow(
            trGlobal('主题'),
            ThemePicker(
              selected: s.theme,
              dark: s.darkMode,
              onSelected: (id) {
                s.theme = id;
                s.accentColor = null;
                app.saveSettings();
              },
            ),
            help: trGlobal('{0} 款主题，同时作用于 Aurora、Pulse 和内置应用', [cmlThemes.length]),
          ),
          SwitchRow(trGlobal('深色模式'), s.darkMode, (v) {
            s.darkMode = v;
            app.saveSettings();
          }),
          FieldRow(
            trGlobal('界面缩放'),
            Row(children: [
              Expanded(
                child: Slider(
                  min: 0.8,
                  max: 1.4,
                  divisions: 12,
                  value: s.uiScale,
                  label: '${(s.uiScale * 100).round()}%',
                  onChanged: (v) => setState(() => s.uiScale = v),
                  onChangeEnd: (_) => app.saveSettings(),
                ),
              ),
              SizedBox(width: 50, child: Text('${(s.uiScale * 100).round()}%')),
            ]),
          ),
          FieldRow(
            trGlobal('背景图片'),
            Row(children: [
              Expanded(child: Text(s.backgroundImage.isEmpty ? trGlobal('无') : s.backgroundImage, overflow: TextOverflow.ellipsis)),
              TextButton(
                onPressed: () async {
                  final f = await openFile(acceptedTypeGroups: [XTypeGroup(label: trGlobal('图片'), extensions: ['png', 'jpg', 'jpeg', 'webp'])]);
                  if (f == null) return;
                  s.backgroundImage = f.path;
                  app.saveSettings();
                },
                child: Text(trGlobal('选择')),
              ),
              if (s.backgroundImage.isNotEmpty)
                TextButton(
                  onPressed: () {
                    s.backgroundImage = '';
                    app.saveSettings();
                  },
                  child: Text(trGlobal('清除')),
                ),
            ]),
          ),
        ]),
      )),
      // ---------------- launcher ----------------
      KeyedSubtree(key: _keys[6], child: Section(
        title: trGlobal('启动器'),
        icon: Icons.rocket_launch_outlined,
        child: Column(children: [
          SwitchRow(trGlobal('自动更新启动器'), s.autoUpdate, (v) {
            setState(() => s.autoUpdate = v);
            app.saveSettings();
          }),
          SwitchRow(trGlobal('自动更新内置工具'), s.autoUpdateTools, (v) {
            setState(() => s.autoUpdateTools = v);
            app.saveSettings();
          }, help: trGlobal('mihomo 内核与 Chunker 会在启动时检查 GitHub 新版本')),
          FieldRow(
            trGlobal('当前版本'),
            Row(children: [
              Text('CML ${SelfUpdater.currentVersion}'),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  try {
                    final r = await app.ctx.updater.checkUpdate();
                    if (!context.mounted) return;
                    if (r == null) return toast(context, trGlobal('已是最新版本'));
                    if (await confirm(context, trGlobal('发现新版本 {0}', [r.tag]), r.body.isEmpty ? trGlobal('是否更新？') : r.body, ok: trGlobal('更新并重启'))) {
                      await app.runTask(trGlobal('更新 CML'), (t) => app.ctx.updater.update(release: r, task: t));
                      await app.ctx.updater.applyAndRestart();
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, errText(e), error: true);
                  }
                },
                child: Text(trGlobal('检查更新')),
              ),
            ]),
          ),
          FieldRow(trGlobal('数据目录'), Text(Os.cmlHome)),
        ]),
      )),
]),
            ),
          ),
        ),
      ),
    ]);
  }
}


class _RailItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 18, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: selected ? cs.primary : cs.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}


class _JavaCard extends StatelessWidget {
  final JavaInstall java;
  final bool selected;
  const _JavaCard({required this.java, required this.selected});

  static Color _color(int major) => switch (major) {
        >= 25 => Colors.deepPurple,
        >= 21 => Colors.indigo,
        >= 17 => Colors.teal,
        >= 11 => Colors.blueGrey,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _color(java.major);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? t.colorScheme.primary : CmlColors.of(context).cardBorder, width: selected ? 2 : 1),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
          child: Text('${java.major}', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text('${java.vendor} ${java.version}', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              if (!java.is64Bit) Pill(trGlobal('32 位'), color: Colors.red),
              if (java.manual) Pill(trGlobal('手动'), color: Colors.grey),
            ]),
            Text(java.path, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}
