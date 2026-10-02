import 'dart:async';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

import '../state.dart';
import '../widgets/common.dart';

/// Built-in Clash Verge–style proxy (mihomo core).
class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key});
  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  List<ProxyGroup> groups = [];
  final delays = <String, int?>{};
  String? coreVersion;
  StreamSubscription<(int, int)>? traffic;
  (int, int) speed = (0, 0);
  bool busy = false;

  ProxyService get proxy => App.read(context).ctx.proxy;

  @override
  void initState() {
    super.initState();
    proxy.core.installedVersion().then((v) {
      if (mounted) setState(() => coreVersion = v);
    });
    if (proxy.running) _attach();
  }

  @override
  void dispose() {
    traffic?.cancel();
    super.dispose();
  }

  Future<void> _attach() async {
    await _loadGroups();
    traffic?.cancel();
    traffic = proxy.traffic().listen((s) {
      if (mounted) setState(() => speed = s);
    }, onError: (_) {});
  }

  Future<void> _loadGroups() async {
    try {
      final g = await proxy.groups();
      if (mounted) setState(() => groups = g);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final app = App.read(context);
    setState(() => busy = true);
    try {
      if (proxy.running) {
        await proxy.stop();
        traffic?.cancel();
        groups = [];
      } else {
        if (!proxy.core.installed) {
          await app.runTask(trGlobal('下载 mihomo 内核'), (t) => proxy.core.update(task: t));
          coreVersion = await proxy.core.installedVersion();
        }
        await proxy.start();
        await _attach();
      }
      app.ctx.applySettings();
      app.changed();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _addSub() async {
    final url = await prompt(context, trGlobal('订阅链接'), hint: trGlobal('https://…（Clash / Mihomo 格式）'));
    if (url == null || url.trim().isEmpty || !mounted) return;
    final name = await prompt(context, trGlobal('订阅名称'), initial: Uri.tryParse(url.trim())?.host ?? trGlobal('订阅'));
    if (name == null || name.trim().isEmpty || !mounted) return;
    final app = App.read(context);
    await app.runTask(trGlobal('导入订阅 {0}', [name.trim()]), (_) => proxy.addSubscription(name.trim(), url.trim()), onError: (e) => toast(context, errText(e), error: true));
    if (mounted) setState(() {});
  }

  Future<void> _testGroup(ProxyGroup g) async {
    await Future.wait([
      for (final n in g.all)
        proxy.delay(n).then((d) {
          if (mounted) setState(() => delays[n] = d);
        })
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final s = proxy.settings;
    final t = Theme.of(context);
    return PageBody(children: [
      Section(
        title: trGlobal('代理'),
        icon: Icons.shield_outlined,
        actions: [
          Text('mihomo ${coreVersion ?? '未下载'}', style: t.textTheme.bodySmall),
          TextButton(
            onPressed: () async {
              await app.runTask(trGlobal('更新 mihomo 内核'), (tk) async {
                final r = await proxy.core.checkUpdate();
                if (r != null) await proxy.core.update(release: r, task: tk);
              }, onError: (e) => toast(context, errText(e), error: true));
              coreVersion = await proxy.core.installedVersion();
              if (mounted) setState(() {});
            },
            child: Text(trGlobal('检查内核更新')),
          ),
        ],
        child: Column(children: [
          Row(children: [
            Icon(proxy.running ? Icons.shield : Icons.shield_outlined, color: proxy.running ? Colors.green : t.disabledColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(proxy.running ? trGlobal('运行中 · {0}', [proxy.proxyAddress]) : trGlobal('未运行'), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (proxy.running) Text('↑ ${fmtBytes(speed.$1)}/s   ↓ ${fmtBytes(speed.$2)}/s', style: t.textTheme.bodySmall),
              ]),
            ),
            SegmentedButton<ProxyMode>(
              segments: [for (final m in ProxyMode.values) ButtonSegment(value: m, label: Text(trCore(m.label)))],
              selected: {s.mode},
              onSelectionChanged: (v) async {
                await proxy.setMode(v.first);
                setState(() {});
              },
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: busy ? null : _toggle, child: Text(proxy.running ? trGlobal('停止') : trGlobal('启动'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SwitchListTile(
                dense: true,
                title: Text(trGlobal('系统代理')),
                value: s.systemProxy,
                onChanged: (v) async {
                  await proxy.setSystemProxy(v);
                  setState(() {});
                },
              ),
            ),
            Expanded(
              child: SwitchListTile(
                dense: true,
                title: Text(trGlobal('启动器下载走代理')),
                value: app.settings.useBuiltInProxy,
                onChanged: (v) {
                  app.settings.useBuiltInProxy = v;
                  app.saveSettings();
                },
              ),
            ),
            Expanded(
              child: SwitchListTile(
                dense: true,
                title: Text(trGlobal('随 CML 启动')),
                value: s.autoStart,
                onChanged: (v) async {
                  s.autoStart = v;
                  await proxy.save();
                  setState(() {});
                },
              ),
            ),
            Expanded(
              child: SwitchListTile(
                dense: true,
                title: Text(trGlobal('TUN 模式')),
                subtitle: Text(trGlobal('需管理员权限'), style: TextStyle(fontSize: 11)),
                value: s.tun,
                onChanged: (v) async {
                  s.tun = v;
                  await proxy.save();
                  if (proxy.running) await proxy.restart();
                  setState(() {});
                },
              ),
            ),
          ]),
        ]),
      ),
      Section(
        title: trGlobal('订阅'),
        icon: Icons.rss_feed_rounded,
        actions: [TextButton.icon(icon: const Icon(Icons.add, size: 16), label: Text(trGlobal('添加订阅')), onPressed: _addSub)],
        child: s.subscriptions.isEmpty
            ? Text(trGlobal('还没有订阅。添加机场提供的 Clash / Mihomo 订阅链接。'))
            : RadioGroup<String>(
                groupValue: s.selected,
                onChanged: (v) async {
                  s.selected = v;
                  await proxy.save();
                  if (proxy.running) {
                    await proxy.restart();
                    await _attach();
                  }
                  setState(() {});
                },
                child: Column(children: [
                  for (final sub in s.subscriptions)
                    RadioListTile<String>(
                      dense: true,
                      value: sub.name,
                      title: Text(sub.name),
                      subtitle: Text([
                        if (sub.totalBytes != null) trGlobal('流量 {0} / {1}', [fmtBytes(sub.usedBytes ?? 0), fmtBytes(sub.totalBytes!)]),
                        if (sub.expire != null) trGlobal('到期 {0}', [fmtDate(sub.expire).split(' ').first]),
                        trGlobal('更新于 {0}', [fmtDate(sub.updated)]),
                      ].join('  ·  ')),
                      secondary: Wrap(children: [
                        IconButton(
                          icon: const Icon(Icons.sync, size: 18),
                          tooltip: trGlobal('更新订阅'),
                          onPressed: () async {
                            await App.read(context).runTask(trGlobal('更新订阅 {0}', [sub.name]), (_) => proxy.updateSubscription(sub), onError: (e) => toast(context, errText(e), error: true));
                            if (proxy.running && s.selected == sub.name) await proxy.restart();
                            if (mounted) setState(() {});
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            if (!await confirm(context, trGlobal('删除订阅'), trGlobal('删除 {0}？', [sub.name]), danger: true)) return;
                            s.subscriptions.remove(sub);
                            if (s.selected == sub.name) s.selected = s.subscriptions.firstOrNull?.name;
                            await proxy.save();
                            setState(() {});
                          },
                        ),
                      ]),
                    ),
                ]),
              ),
      ),
      if (proxy.running)
        Section(
          title: trGlobal('节点'),
          icon: Icons.public,
          actions: [IconButton(onPressed: _loadGroups, icon: const Icon(Icons.refresh))],
          child: Column(children: [
            for (final g in groups.where((g) => g.type == 'Selector' || g.type == 'URLTest' || g.type == 'Fallback'))
              ExpansionTile(
                title: Text(g.name),
                subtitle: Text(trGlobal('{0} · 当前：{1}', [g.type, g.now])),
                trailing: IconButton(icon: const Icon(Icons.speed, size: 18), tooltip: trGlobal('测速'), onPressed: () => _testGroup(g)),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final n in g.all)
                      ChoiceChip(
                        selected: n == g.now,
                        label: Text('$n${delays.containsKey(n) ? '  ${delays[n] == null ? '超时' : '${delays[n]}ms'}' : ''}'),
                        onSelected: g.type != 'Selector'
                            ? null
                            : (_) async {
                                await proxy.select(g.name, n);
                                await _loadGroups();
                              },
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
              ),
          ]),
        ),
      Section(
        title: trGlobal('Clash Verge Rev 完整版'),
        icon: Icons.apps_outlined,
        child: Row(children: [
          Expanded(child: Text(trGlobal('需要 Clash Verge Rev 的完整界面（规则编辑、脚本、覆写等）时，可以一键安装/更新官方最新版，与内置代理二选一使用。'))),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: () async {
              if (!await confirm(context, 'Clash Verge Rev', trGlobal('将从 GitHub（clash-verge-rev/clash-verge-rev）下载官方最新安装程序并打开，安装过程由你在安装程序中确认。继续？'))) return;
              await app.runTask(trGlobal('下载 Clash Verge Rev'), (t) => app.ctx.clashVerge.update(task: t), onError: (e) => toast(context, errText(e), error: true));
            },
            child: Text(ClashVergeApp.findInstalled() == null ? trGlobal('安装') : trGlobal('更新到最新版')),
          ),
        ]),
      ),
    ]);
  }
}
