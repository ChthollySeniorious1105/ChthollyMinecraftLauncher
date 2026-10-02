import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';

/// One-click launch for Microsoft Store games (Bedrock, Legends, Dungeons, Dungeons II…).
class StoreGamesPage extends StatefulWidget {
  const StoreGamesPage({super.key});
  @override
  State<StoreGamesPage> createState() => _StoreGamesPageState();
}

class _StoreGamesPageState extends State<StoreGamesPage> {
  List<StoreGameStatus>? games;
  String? error;

  static const _icons = {
    'bedrock': Icons.grass,
    'bedrock_preview': Icons.science_outlined,
    'legends': Icons.shield_outlined,
    'dungeons': Icons.castle_outlined,
    'dungeons2': Icons.fort_outlined,
    'education': Icons.school_outlined,
  };

  static const _desc = {
    'bedrock': '基岩版（Windows 版），与手机、主机互通。',
    'bedrock_preview': '基岩版测试版，提前体验新内容。',
    'legends': '动作策略游戏。',
    'dungeons': '地牢探险动作游戏。',
    'dungeons2': '地下城系列新作。',
    'education': '教育版（需要学校/机构账号）。',
  };

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() => games = null);
    try {
      final g = await StoreLauncher.detect();
      if (mounted) setState(() => games = g);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (error != null) return EmptyHint(Icons.error_outline, error!);
    if (games == null) return const Center(child: CircularProgressIndicator());
    final roots = BedrockPaths.roots();
    return PageBody(children: [
      Section(
        title: 'Microsoft Store 游戏',
        icon: Icons.storefront_outlined,
        actions: [IconButton(onPressed: _detect, icon: const Icon(Icons.refresh), tooltip: '重新检测')],
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.7,
          children: [
            for (final g in games!)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: t.dividerColor), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_icons[g.game.id] ?? Icons.sports_esports, size: 28, color: g.installed ? t.colorScheme.primary : t.disabledColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(g.game.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  Text(_desc[g.game.id] ?? '', style: t.textTheme.bodySmall),
                  const Spacer(),
                  Row(children: [
                    Text(g.installed ? '版本 ${g.version}' : '未安装', style: t.textTheme.bodySmall),
                    const Spacer(),
                    if (g.installed)
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('启动'),
                        onPressed: () => StoreLauncher.launch(g).catchError((Object e) {
                          if (context.mounted) toast(context, errText(e), error: true);
                        }),
                      )
                    else
                      OutlinedButton(onPressed: () => StoreLauncher.openStore(g.game), child: const Text('去商店')),
                  ]),
                ]),
              ),
          ],
        ),
      ),
      Section(
        title: '基岩版数据目录',
        icon: Icons.folder_outlined,
        child: roots.isEmpty
            ? const Text('没有找到基岩版数据（安装后至少进入一次游戏）')
            : Column(children: [
                for (final r in roots)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(r.label),
                    subtitle: Text(r.comMojang),
                    trailing: Wrap(spacing: 4, children: [
                      TextButton(onPressed: () => revealInExplorer(r.worlds), child: const Text('存档')),
                      TextButton(onPressed: () => revealInExplorer(r.resourcePacks), child: const Text('资源包')),
                      TextButton(onPressed: () => revealInExplorer(r.behaviorPacks), child: const Text('行为包')),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}
