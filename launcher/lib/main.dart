import 'dart:async';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'i18n/i18n.dart';

import 'pages/download_page.dart';
import 'pages/home_page.dart';
import 'pages/multiplayer_page.dart';
import 'pages/proxy_page.dart';
import 'pages/saves_page.dart';
import 'pages/settings_page.dart';
import 'pages/skin_page.dart';
import 'pages/store_games_page.dart';
import 'pages/tools_page.dart';
import 'pages/versions_page.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/account.dart';
import 'widgets/title_bar.dart';

/// `--page N` opens navigation entry N on start (handy for shortcuts and screenshots).
int _startPage = 0;

/// `--login` opens the sign-in dialog on start.
bool _openLogin = false;

Future<void> main(List<String> args) async {
  _openLogin = args.contains('--login');
  final pi = args.indexOf('--page');
  if (pi >= 0 && pi + 1 < args.length) _startPage = int.tryParse(args[pi + 1]) ?? 0;
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1220, 770),
      minimumSize: Size(1000, 640),
      center: true,
      title: 'ChthollyMinecraftLauncher',
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final state = AppState();
  runApp(App(state: state, child: const CmlApp()));
  await state.init();
}

class CmlApp extends StatelessWidget {
  const CmlApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final s = app.settings;
    final theme = themeById(s.theme);
    final accent = s.accentColor == null ? null : Color(s.accentColor!);
    final lang = AppLanguage.fromCode(s.language);
    currentLanguage = lang;
    // KeyedSubtree forces a full rebuild on language change: some strings live in
    // State fields and const-free lists that only re-read trGlobal when rebuilt.
    return KeyedSubtree(
      key: ValueKey(lang),
      child: I18n(
        language: lang,
        child: MaterialApp(
          title: 'CML',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(theme, dark: false, accent: accent),
          darkTheme: buildTheme(theme, dark: true, accent: accent),
          themeMode: s.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s.uiScale)), child: child!),
          home: app.ready ? const Shell() : const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String subtitle;
  final Widget Function() page;
  const _Dest(this.label, this.icon, this.selectedIcon, this.subtitle, this.page);
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  /// Survives the full rebuild done on language change.
  static int? _keptIndex;
  int _index = (_keptIndex ?? _startPage).clamp(0, _dests.length - 1);
  int get index => _index;
  set index(int v) => _index = _keptIndex = v;

  static List<_Dest> get _dests => <_Dest>[
    _Dest(trGlobal('启动'), Icons.rocket_launch_outlined, Icons.rocket_launch, trGlobal('选择版本，开始游戏'), () => const HomePage()),
    _Dest(trGlobal('版本'), Icons.layers_outlined, Icons.layers, trGlobal('管理已安装的版本、Mod、资源包与光影'), () => const VersionsPage()),
    _Dest(trGlobal('下载'), Icons.download_outlined, Icons.download, trGlobal('游戏、加载器、Mod、整合包、光影、资源包、数据包与 Java'), () => const DownloadPage()),
    _Dest(trGlobal('存档'), Icons.public_outlined, Icons.public, trGlobal('Java 版与基岩版存档管理、备份与转换'), () => const SavesPage()),
    _Dest(trGlobal('联机'), Icons.hub_outlined, Icons.hub, trGlobal('通过 CMLS 服务器安全地与朋友联机'), () => const MultiplayerPage()),
    _Dest(trGlobal('商店游戏'), Icons.sports_esports_outlined, Icons.sports_esports, trGlobal('基岩版、Legends、Dungeons 一键启动'), () => const StoreGamesPage()),
    _Dest(trGlobal('皮肤'), Icons.face_retouching_natural_outlined, Icons.face_retouching_natural, trGlobal('绘制皮肤、3D 预览、上传与披风切换'), () => const SkinPage()),
    _Dest(trGlobal('工具箱'), Icons.handyman_outlined, Icons.handyman, trGlobal('建筑文件转换、资源包转换、存档转换与内存优化'), () => const ToolsPage()),
    _Dest(trGlobal('网络代理'), Icons.shield_outlined, Icons.shield, trGlobal('内置 Clash Verge 代理（mihomo 内核）'), () => const ProxyPage()),
    _Dest(trGlobal('设置'), Icons.tune_outlined, Icons.tune, trGlobal('Java、内存、下载源、账号与外观'), () => const SettingsPage()),
  ];

  /// Group headings shown above these indices in the sidebar.
  static Map<int, String> get _groups => {0: trGlobal('游戏'), 5: trGlobal('扩展'), 8: trGlobal('系统')};

  @override
  void initState() {
    super.initState();
    if (_keptIndex != null) return; // rebuilt after a language switch: startup already done
    _keptIndex = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupChecks());
  }

  Future<void> _startupChecks() async {
    final app = App.read(context);
    if (_openLogin) unawaited(showLoginDialog(context));
    if (app.initError != null) toast(context, trGlobal('初始化出错：{0}', [app.initError]), error: true);
    if (app.settings.autoUpdate) {
      try {
        final r = await app.ctx.updater.checkUpdate();
        if (r != null && mounted) {
          final ok = await confirm(context, trGlobal('发现新版本 {0}', [r.tag]), r.body.isEmpty ? trGlobal('是否现在更新 CML？') : r.body, ok: trGlobal('更新并重启'));
          if (ok && mounted) {
            await app.runTask(trGlobal('更新 CML {0}', [r.tag]), (t) => app.ctx.updater.update(release: r, task: t), onError: (e) => toast(context, errText(e), error: true));
            await app.ctx.updater.applyAndRestart();
          }
        }
      } catch (_) {
        // offline or no releases yet
      }
    }
    if (app.settings.autoUpdateTools) {
      for (final c in <GithubComponent>[app.ctx.proxy.core, app.ctx.chunker]) {
        try {
          if (await c.installedVersion() == null) continue; // only keep installed tools fresh
          final r = await c.checkUpdate();
          if (r != null) await app.runTask(trGlobal('更新 {0} {1}', [c.displayName, r.tag]), (t) => c.update(release: r, task: t));
        } catch (_) {}
      }
    }
    if (app.ctx.proxy.settings.autoStart && app.ctx.proxy.core.installed) {
      try {
        await app.ctx.proxy.start();
        app.ctx.applySettings();
        app.changed();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    final cml = CmlColors.of(context);
    final dest = _dests[index];
    return Scaffold(
      body: Row(children: [
        // ---------------- sidebar ----------------
        Container(
          width: 212,
          decoration: BoxDecoration(color: cml.sidebar, border: Border(right: BorderSide(color: cml.cardBorder))),
          child: Column(children: [
            const DragToMoveArea(child: SizedBox(height: 22, width: double.infinity)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Image.asset('assets/logo.png', width: 38, height: 38, filterQuality: FilterQuality.medium),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ShaderMask(
                    shaderCallback: (r) => cml.hero.createShader(r),
                    child: Text('CML', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2, height: 1.1)),
                  ),
                  Text('Chtholly Launcher', style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
                ]),
              ]),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (var i = 0; i < _dests.length; i++) ...[
                    if (_groups[i] != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(12, i == 0 ? 0 : 14, 0, 6),
                        child: Text(_groups[i]!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      ),
                    _NavItem(dest: _dests[i], selected: i == index, onTap: () => setState(() => index = i)),
                  ],
                ],
              ),
            ),
            const TaskCenterButton(),
            const SizedBox(height: 8),
            _AccountChip(onTap: () => setState(() => index = 0)),
            const SizedBox(height: 12),
          ]),
        ),
        // ---------------- content ----------------
        Expanded(
          child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [cml.pageBg1, cml.pageBg2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Stack(children: [
              if (app.settings.backgroundImage.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.16,
                    child: Image.file(File(app.settings.backgroundImage), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                ),
              Positioned.fill(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const CmlTitleBar(leading: SizedBox.shrink()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 20, 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(dest.label, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(dest.subtitle, style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor)),
                        ]),
                      ),
                      _HeaderAction(
                        icon: app.settings.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        tooltip: app.settings.darkMode ? trGlobal('切换到浅色') : trGlobal('切换到深色'),
                        onTap: () {
                          app.settings.darkMode = !app.settings.darkMode;
                          app.saveSettings();
                        },
                      ),
                      const SizedBox(width: 6),
                      _HeaderAction(
                        icon: Icons.download_for_offline_outlined,
                        tooltip: trGlobal('任务'),
                        badge: app.activeTasks,
                        onTap: () => showDialog(context: context, builder: (_) => const TaskListDialog()),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(a), child: child),
                      ),
                      child: KeyedSubtree(key: ValueKey(index), child: dest.page()),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _NavItem extends StatefulWidget {
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.dest, required this.selected, required this.onTap});
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: sel ? CmlColors.of(context).hero : null,
              color: sel ? null : (hover ? cs.primary.withValues(alpha: 0.07) : Colors.transparent),
              borderRadius: BorderRadius.circular(11),
              boxShadow: sel ? [BoxShadow(color: cs.primary.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            child: Row(children: [
              Icon(sel ? widget.dest.selectedIcon : widget.dest.icon, size: 20, color: sel ? Colors.white : t.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(widget.dest.label, style: TextStyle(color: sel ? Colors.white : t.colorScheme.onSurface, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Round icon button used in the page header.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  const _HeaderAction({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.cardTheme.color,
        shape: CircleBorder(side: BorderSide(color: CmlColors.of(context).cardBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              offset: const Offset(6, -6),
              child: Icon(icon, size: 20, color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

/// Current account at the bottom of the sidebar.
class _AccountChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AccountChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    final a = app.ctx.accounts.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: t.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: a == null ? () => showLoginDialog(context) : onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              SkinHead(a?.activeSkin?.url, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a?.name ?? trGlobal('未登录'), style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(a == null ? trGlobal('点击登录 Microsoft 账号') : trGlobal('v{0} · 正版', [SelfUpdater.currentVersion]), style: t.textTheme.labelSmall?.copyWith(color: t.hintColor), maxLines: 1),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left task indicator; opens the task list.
class TaskCenterButton extends StatelessWidget {
  const TaskCenterButton({super.key});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final n = app.activeTasks;
    if (app.tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: OutlinedButton.icon(
        icon: n > 0 ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.task_alt, size: 16),
        label: Text(n > 0 ? trGlobal('{0} 个任务进行中', [n]) : trGlobal('任务已完成')),
        onPressed: () => showDialog(context: context, builder: (_) => const TaskListDialog()),
      ),
    );
  }
}

class TaskListDialog extends StatelessWidget {
  const TaskListDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    return AlertDialog(
      title: Text(trGlobal('任务')),
      content: SizedBox(
        width: 560,
        child: app.tasks.isEmpty
            ? Text(trGlobal('没有任务'))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final t in app.tasks)
                    ListTile(
                      title: Text(t.title),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: t.state == TaskState.running ? (t.progress < 0 ? null : t.progress) : 1),
                        const SizedBox(height: 4),
                        Text(
                          switch (t.state) {
                            TaskState.failed => trGlobal('失败：{0}', [errText(t.error!)]),
                            TaskState.cancelled => trGlobal('已取消'),
                            TaskState.done => trGlobal('完成'),
                            _ => '${trCore(t.detail)}${t.bytesPerSecond > 0 ? '  ${fmtBytes(t.bytesPerSecond)}/s' : ''}',
                          },
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                      trailing: t.state == TaskState.running ? IconButton(icon: const Icon(Icons.close), tooltip: trGlobal('取消'), onPressed: t.cancel.cancel) : null,
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('关闭')))],
    );
  }
}
