import 'dart:async';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/account.dart' show revealInExplorer;
import '../widgets/common.dart';

/// Bedrock tools: a native front-end for the bundled BedrockTool CLI (world download, skins, packet
/// capture, Realms …) and the NetEase save decrypter.
class BedrockToolsPage extends StatefulWidget {
  const BedrockToolsPage({super.key});
  @override
  State<BedrockToolsPage> createState() => _BedrockToolsPageState();
}

class _BedrockToolsPageState extends State<BedrockToolsPage> with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TabBar(controller: tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: trGlobal('BedrockTool 工具箱')),
          Tab(text: trGlobal('网易存档解密')),
        ]),
        Expanded(child: TabBarView(controller: tabs, children: const [_BedrockToolTab(), _NeteaseTab()])),
      ]);
}

// ============================ tool specs ============================

enum _Kind { address, realm, toggle, number, text, list, file, folder, folders }

class _Field {
  final String flag;
  final String label;
  final String? help;
  final _Kind kind;
  final bool advanced;
  const _Field(this.flag, this.label, this.kind, {this.help, this.advanced = false});
}

class _Tool {
  final String command;
  final String title;
  final String desc;
  final IconData icon;
  final List<_Field> fields;
  const _Tool(this.command, this.title, this.desc, this.icon, this.fields);
}

List<_Field> _proxyFields() => [
      _Field('address', trGlobal('服务器地址'), _Kind.address, help: trGlobal('IP[:端口]，或 realm:名称')),
      _Field('listen', trGlobal('本地监听地址'), _Kind.text, help: trGlobal('游戏里连接这个地址'), advanced: true),
      _Field('capture', trGlobal('同时保存抓包'), _Kind.toggle, help: trGlobal('写入 captures 文件夹（.pcap2）'), advanced: true),
      _Field('client-cache', trGlobal('客户端区块缓存'), _Kind.toggle, advanced: true),
      _Field('debug', trGlobal('调试模式'), _Kind.toggle, advanced: true),
      _Field('extra-debug', trGlobal('详细调试日志'), _Kind.toggle, help: trGlobal('生成 packets.log'), advanced: true),
    ];

List<_Tool> _tools() => [
      _Tool('worlds', trGlobal('下载服务器世界'), trGlobal('通过代理进服，边走边保存区块为本地存档'), Icons.public, [
        ..._proxyFields(),
        _Field('void', trGlobal('虚空生成器'), _Kind.toggle, help: trGlobal('未下载的区域保持虚空')),
        _Field('save-entities', trGlobal('保存实体'), _Kind.toggle),
        _Field('save-inventories', trGlobal('保存容器物品'), _Kind.toggle, help: trGlobal('箱子等需要打开过')),
        _Field('save-players', trGlobal('把玩家保存为实体'), _Kind.toggle),
        _Field('image', trGlobal('结束时生成地图 PNG'), _Kind.toggle),
        _Field('block-updates', trGlobal('记录方块更新'), _Kind.toggle),
        _Field('entity-culling', trGlobal('移除已死亡实体'), _Kind.toggle, help: trGlobal('实验性')),
        _Field('chunk-radius', trGlobal('强制区块半径'), _Kind.number, help: trGlobal('0 = 使用服务器设置')),
        _Field('exclude-mobs', trGlobal('排除的生物'), _Kind.list, help: trGlobal('逗号分隔，如 zombie,creeper'), advanced: true),
        _Field('script', trGlobal('脚本文件'), _Kind.file, help: trGlobal('JS 脚本（可选）'), advanced: true),
      ]),
      _Tool('skins', trGlobal('保存皮肤'), trGlobal('保存服务器里其他玩家的皮肤'), Icons.face_retouching_natural, [
        ..._proxyFields(),
        _Field('filter', trGlobal('玩家名过滤'), _Kind.text, help: trGlobal('正则表达式，留空保存全部')),
        _Field('texture-only', trGlobal('只保存贴图'), _Kind.toggle),
        _Field('timestamped', trGlobal('文件名带时间'), _Kind.toggle),
        _Field('no-proxy', trGlobal('不启动代理'), _Kind.toggle, help: trGlobal('直接以机器人身份连接'), advanced: true),
      ]),
      _Tool('capture', trGlobal('抓包'), trGlobal('把所有数据包保存为 pcap2 文件'), Icons.radar, _proxyFields()),
      _Tool('chat-log', trGlobal('聊天记录'), trGlobal('把聊天消息写入日志文件'), Icons.forum_outlined, [
        ..._proxyFields(),
        _Field('verbose', trGlobal('详细输出'), _Kind.toggle),
      ]),
      _Tool('list-realms', trGlobal('Realms 列表'), trGlobal('列出你的账号能访问的 Realms'), Icons.cloud_outlined, const []),
      _Tool('realm-address', trGlobal('Realm 地址'), trGlobal('获取 Realm 的实际服务器地址'), Icons.travel_explore, [
        _Field('realm', trGlobal('Realm'), _Kind.realm, help: trGlobal('名称或 ID')),
      ]),
      _Tool('merge', trGlobal('合并世界'), trGlobal('把多个下载的世界合并成一个'), Icons.merge_type, [
        _Field('-args', trGlobal('要合并的世界'), _Kind.folders, help: trGlobal('至少两个')),
        _Field('out', trGlobal('输出名称'), _Kind.text, help: trGlobal('保存在工具数据目录')),
        _Field('bounds', trGlobal('只显示边界'), _Kind.toggle, help: trGlobal('不合并，只输出各世界范围')),
      ]),
      _Tool('packs', trGlobal('下载资源包'), trGlobal('保存服务器发送的资源包'), Icons.inventory_2_outlined, [
        ..._proxyFields().where((f) => f.flag != 'listen'),
        _Field('folders', trGlobal('解压为文件夹'), _Kind.toggle, help: trGlobal('否则保存为 .mcpack')),
        _Field('save-encrypted', trGlobal('同时保存加密原包'), _Kind.toggle, advanced: true),
      ]),
      _Tool('render', trGlobal('渲染地图'), trGlobal('把存档渲染成俯视 PNG'), Icons.map_outlined, [
        _Field('world', trGlobal('存档文件夹'), _Kind.folder),
        _Field('out', trGlobal('输出文件名'), _Kind.text),
      ]),
    ];

class _ConsoleLine {
  final String text;
  final String? level;
  final DateTime time;
  _ConsoleLine(this.text, this.level) : time = DateTime.now();
  bool get error => level == 'ERRO' || level == 'FATA' || level == 'PANI';
}

// ============================ BedrockTool tab ============================

class _BedrockToolTab extends StatefulWidget {
  const _BedrockToolTab();
  @override
  State<_BedrockToolTab> createState() => _BedrockToolTabState();
}

class _BedrockToolTabState extends State<_BedrockToolTab> with AutomaticKeepAliveClientMixin {
  final tool = BedrockTool();
  String selected = 'worlds';
  final Map<String, Map<String, Object?>> values = {};
  final Map<String, TextEditingController> ctl = {};
  final Map<String, FocusNode> focus = {};
  bool advanced = false;

  List<String> history = [];
  List<BtRealm> realms = [];
  bool loadingRealms = false;

  BtRun? run;
  String? runCommand;
  String? listening;
  final List<_ConsoleLine> console = [];
  final consoleScroll = ScrollController();
  String filter = '';
  bool errorsOnly = false;

  List<BtOutput> outputs = [];
  BuildContext? _loginDialog;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    run?.cancel();
    for (final c in ctl.values) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
    consoleScroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final h = await tool.history();
    final o = await tool.outputs();
    if (mounted) {
      setState(() {
        history = h;
        outputs = o;
      });
    }
  }

  Map<String, Object?> _vals(String cmd) => values.putIfAbsent(cmd, () {
        final c = BtCommands.byName(cmd);
        return {
          for (final f in c?.flags ?? const <BtFlag>[])
            f.name: switch (f.type) {
              BtFlagType.boolean => f.defaultBool,
              _ => f.defaultValue,
            },
          if (cmd == 'merge') '-args': <String>[],
        };
      });

  TextEditingController _ctl(String cmd, String flag) => ctl.putIfAbsent('$cmd/$flag', () {
        final v = _vals(cmd)[flag];
        final c = TextEditingController(text: v is String ? v : (v == null ? '' : '$v'));
        c.addListener(() => _vals(cmd)[flag] = c.text);
        return c;
      });

  // ---------------- running

  Future<void> _start(_Tool t) async {
    final v = Map<String, Object?>.from(_vals(t.command));
    List<String> positional = const [];
    if (t.command == 'merge') {
      positional = [...(v.remove('-args') as List<String>? ?? [])];
      if (positional.length < 2) return toast(context, trGlobal('请至少选择两个世界'), error: true);
    }
    if (t.fields.any((f) => f.kind == _Kind.address) && '${v['address'] ?? ''}'.trim().isEmpty) {
      return toast(context, trGlobal('请填写服务器地址'), error: true);
    }
    if (t.command == 'render' && '${v['world'] ?? ''}'.trim().isEmpty) return toast(context, trGlobal('请选择存档文件夹'), error: true);
    if (t.command == 'realm-address' && '${v['realm'] ?? ''}'.trim().isEmpty) return toast(context, trGlobal('请选择或填写 Realm'), error: true);
    if (v['chunk-radius'] is String) {
      final n = int.tryParse('${v['chunk-radius']}'.trim());
      v['chunk-radius'] = n == null || n <= 0 ? null : n;
    }
    v.removeWhere((k, _) => !t.fields.any((f) => f.flag == k));
    try {
      final r = await tool.start(t.command, flags: v, positional: positional);
      if ('${v['address'] ?? ''}'.trim().isNotEmpty) await tool.remember('${v['address']}');
      setState(() {
        run = r;
        runCommand = t.command;
        listening = null;
        console.add(_ConsoleLine('> bedrocktool ${r.args.join(' ')}', 'CML'));
      });
      r.events.listen(_onEvent);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  void _onEvent(BtEvent e) {
    if (!mounted) return;
    switch (e) {
      case BtLine l:
        console.add(_ConsoleLine(l.text, l.level));
        if (console.length > 5000) console.removeRange(0, 1000);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (consoleScroll.hasClients) consoleScroll.jumpTo(consoleScroll.position.maxScrollExtent);
        });
      case BtLogin l:
        _showLogin(l);
      case BtLoginDone d:
        _closeLogin();
        toast(context, d.success ? trGlobal('Xbox 登录成功') : trGlobal('Xbox 登录失败：{0}', [d.error ?? '']), error: !d.success);
      case BtListening l:
        listening = l.address;
      case BtRealm r:
        if (!realms.any((x) => x.id == r.id)) realms.add(r);
      case BtExit x:
        _closeLogin();
        console.add(_ConsoleLine(x.cancelled ? trGlobal('已停止') : trGlobal('进程已退出，代码 {0}', [x.code]), x.code == 0 || x.cancelled ? 'CML' : 'ERRO'));
        run = null;
        runCommand = null;
        listening = null;
        _refresh();
    }
    setState(() {});
  }

  Future<void> _stop() async {
    await run?.cancel();
  }

  void _closeLogin() {
    final c = _loginDialog;
    _loginDialog = null;
    if (c != null && c.mounted) Navigator.of(c).pop();
  }

  void _showLogin(BtLogin l) {
    _closeLogin();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        _loginDialog = c;
        final t = Theme.of(c);
        return AlertDialog(
          icon: const Icon(Icons.sports_esports_outlined, size: 32),
          title: Text(trGlobal('登录 Xbox Live')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(trGlobal('BedrockTool 需要用你的微软账号登录才能连接服务器。在浏览器打开下面的链接并确认代码：'), style: t.textTheme.bodyMedium),
              const SizedBox(height: 16),
              if (l.code.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                  child: SelectableText(l.code,
                      textAlign: TextAlign.center, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6, fontFamily: 'Consolas')),
                ),
              const SizedBox(height: 10),
              SelectableText(l.url, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
              const SizedBox(height: 10),
              Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(trGlobal('等待登录完成…登录信息保存在 CML 数据目录，下次无需再登录'), style: t.textTheme.bodySmall)),
              ]),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _closeLogin();
                _stop();
              },
              child: Text(trGlobal('取消')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(trGlobal('复制代码')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: l.code.isEmpty ? l.url : l.code));
                toast(context, trGlobal('已复制到剪贴板'));
              },
            ),
            FilledButton.icon(icon: const Icon(Icons.open_in_browser, size: 18), label: Text(trGlobal('打开浏览器')), onPressed: () => launchUrl(Uri.parse(l.url))),
          ],
        );
      },
    ).whenComplete(() => _loginDialog = null);
  }

  Future<void> _loadRealms() async {
    if (run != null) return toast(context, trGlobal('请先停止正在运行的任务'), error: true);
    setState(() {
      loadingRealms = true;
      realms = [];
    });
    try {
      final r = await tool.start('list-realms');
      setState(() {
        run = r;
        runCommand = 'list-realms';
      });
      r.events.listen(_onEvent);
      await r.exitCode;
      if (mounted && realms.isEmpty) toast(context, trGlobal('没有找到 Realm'));
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => loadingRealms = false);
    }
  }

  // ---------------- build

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tools = _tools();
    final t = tools.firstWhere((x) => x.command == selected, orElse: () => tools.first);
    return PageBody(children: [
      _banner(context),
      if (!tool.available)
        Card(
          child: EmptyHint(Icons.extension_off_outlined, trGlobal('没有找到 BedrockTool（{0}），请重新安装 CML', [tool.exe])),
        ),
      _grid(context, tools),
      _form(context, t),
      _console(context),
      _outputs(context),
    ]);
  }

  Widget _banner(BuildContext context) {
    final t = Theme.of(context);
    final white = t.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9));
    Widget chip(IconData i, String s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: CmlColors.of(context).hero, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const Icon(Icons.grass_rounded, color: Colors.white, size: 48),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trGlobal('基岩版工具箱'), style: t.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(trGlobal('下载服务器世界、保存皮肤、抓包与 Realms 工具（基于 BedrockTool）'), style: white),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              chip(Icons.verified_outlined, trGlobal('支持基岩版 {0}', [BedrockToolInfo.supportedVersion])),
              chip(Icons.lan_outlined, trGlobal('协议 {0}', [BedrockToolInfo.protocol])),
              chip(tool.loggedIn ? Icons.check_circle_outline : Icons.person_outline, tool.loggedIn ? trGlobal('Xbox 已登录') : trGlobal('首次使用需登录 Xbox')),
            ]),
          ]),
        ),
        Column(children: [
          if (tool.loggedIn)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.logout, size: 16),
              label: Text(trGlobal('退出 Xbox 登录')),
              onPressed: () async {
                await tool.logout();
                setState(() {});
              },
            ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(trGlobal('数据目录')),
            onPressed: () async {
              await Directory(tool.workDir).create(recursive: true);
              await revealInExplorer(tool.workDir);
            },
          ),
        ]),
      ]),
    );
  }

  Widget _grid(BuildContext context, List<_Tool> tools) {
    final th = Theme.of(context);
    return Section(
      title: trGlobal('选择工具'),
      icon: Icons.apps_rounded,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final t in tools)
            SizedBox(
              width: w,
              child: Material(
                color: t.command == selected ? th.colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: t.command == selected ? th.colorScheme.primary : th.dividerColor, width: t.command == selected ? 1.5 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => selected = t.command),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: th.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Icon(t.icon, color: th.colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                            if (runCommand == t.command) ...[const SizedBox(width: 6), Pill(trGlobal('运行中'), color: Colors.green)],
                          ]),
                          const SizedBox(height: 2),
                          Text(t.desc, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _form(BuildContext context, _Tool t) {
    final hasAdvanced = t.fields.any((f) => f.advanced);
    final fields = t.fields.where((f) => advanced || !f.advanced).toList();
    final running = run != null;
    final th = Theme.of(context);
    return Section(
      title: t.title,
      subtitle: t.desc,
      icon: t.icon,
      actions: [
        if (hasAdvanced)
          Row(children: [
            Text(trGlobal('高级选项'), style: th.textTheme.bodySmall),
            Switch(value: advanced, onChanged: (v) => setState(() => advanced = v)),
          ]),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (fields.isEmpty) Text(trGlobal('这个工具没有参数，直接运行即可'), style: TextStyle(color: th.hintColor)),
        for (final f in fields) _field(context, t, f),
        if (t.fields.any((f) => f.kind == _Kind.address)) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: th.colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18, color: th.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  listening != null
                      ? trGlobal('代理已启动：打开 Minecraft 基岩版，在「服务器」里添加 本机IP（或 127.0.0.1）端口 {0} 并加入', [listening!.split(':').last])
                      : trGlobal('运行后 BedrockTool 会在本机开启代理，在游戏中连接本机即可通过代理进入目标服务器'),
                  style: th.textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          if (running)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: th.colorScheme.error),
              icon: const Icon(Icons.stop_rounded),
              label: Text(runCommand == t.command ? trGlobal('停止') : trGlobal('停止当前任务')),
              onPressed: _stop,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(trGlobal('运行')),
              onPressed: tool.available ? () => _start(t) : null,
            ),
          const SizedBox(width: 12),
          if (running) ...[
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(trGlobal('正在运行 {0}', [runCommand ?? ''])),
          ],
        ]),
      ]),
    );
  }

  Widget _field(BuildContext context, _Tool t, _Field f) {
    final v = _vals(t.command);
    switch (f.kind) {
      case _Kind.toggle:
        return SwitchRow(f.label, v[f.flag] == true, (b) => setState(() => v[f.flag] = b), help: f.help);
      case _Kind.address:
        final c = _ctl(t.command, f.flag);
        return FieldRow(
          f.label,
          Row(children: [
            Expanded(
              child: RawAutocomplete<String>(
                textEditingController: c,
                focusNode: focus.putIfAbsent('${t.command}/${f.flag}', FocusNode.new),
                optionsBuilder: (te) => history.where((h) => h.toLowerCase().contains(te.text.toLowerCase())),
                fieldViewBuilder: (ctx, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: InputDecoration(isDense: true, hintText: trGlobal('例如 play.example.com:19132'), prefixIcon: const Icon(Icons.dns_outlined, size: 18)),
                ),
                optionsViewBuilder: (ctx, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
                      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                        for (final o in options) ListTile(dense: true, leading: const Icon(Icons.history, size: 16), title: Text(o), onTap: () => onSelected(o)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _realmButton((r) => c.text = 'realm:${r.name}'),
          ]),
          help: f.help,
        );
      case _Kind.realm:
        final c = _ctl(t.command, f.flag);
        return FieldRow(
          f.label,
          Row(children: [
            Expanded(child: TextField(controller: c, decoration: InputDecoration(isDense: true, hintText: trGlobal('Realm 名称或 ID')))),
            const SizedBox(width: 8),
            _realmButton((r) => c.text = r.name),
          ]),
          help: f.help,
        );
      case _Kind.number:
      case _Kind.text:
      case _Kind.list:
        return FieldRow(
          f.label,
          TextField(
            controller: _ctl(t.command, f.flag),
            keyboardType: f.kind == _Kind.number ? TextInputType.number : null,
            inputFormatters: f.kind == _Kind.number ? [FilteringTextInputFormatter.digitsOnly] : null,
            decoration: const InputDecoration(isDense: true),
          ),
          help: f.help,
        );
      case _Kind.file:
      case _Kind.folder:
        final c = _ctl(t.command, f.flag);
        return FieldRow(
          f.label,
          Row(children: [
            Expanded(child: TextField(controller: c, decoration: const InputDecoration(isDense: true))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final r = f.kind == _Kind.folder
                    ? await getDirectoryPath(initialDirectory: _defaultWorldsDir())
                    : (await openFile(acceptedTypeGroups: [XTypeGroup(label: 'JavaScript', extensions: ['js'])]))?.path;
                if (r != null) c.text = r;
              },
              child: Text(trGlobal('浏览')),
            ),
          ]),
          help: f.help,
        );
      case _Kind.folders:
        final list = (v[f.flag] as List<String>?) ?? <String>[];
        return FieldRow(
          f.label,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in list)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, size: 18),
                title: Text(p.basename(w)),
                subtitle: Text(w, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => list.remove(w))),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(trGlobal('添加世界')),
              onPressed: () async {
                final d = await getDirectoryPath(initialDirectory: _defaultWorldsDir());
                if (d != null && !list.contains(d)) setState(() => v[f.flag] = [...list, d]);
              },
            ),
          ]),
          help: f.help,
        );
    }
  }

  String? _defaultWorldsDir() {
    final d = p.join(tool.workDir, 'worlds');
    return Directory(d).existsSync() ? d : null;
  }

  Widget _realmButton(void Function(BtRealm r) onPick) => PopupMenuButton<BtRealm>(
        tooltip: trGlobal('从我的 Realms 选择'),
        onSelected: onPick,
        onOpened: realms.isEmpty && !loadingRealms ? _loadRealms : null,
        itemBuilder: (_) => [
          if (realms.isEmpty)
            PopupMenuItem(enabled: false, child: Text(loadingRealms ? trGlobal('正在读取 Realms…') : trGlobal('正在读取，请稍后再点开'))),
          for (final r in realms) PopupMenuItem(value: r, child: Text('${r.name}  (${r.id})')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            loadingRealms ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_outlined, size: 18),
            const SizedBox(width: 4),
            Text(trGlobal('Realms')),
          ]),
        ),
      );

  Widget _console(BuildContext context) {
    final th = Theme.of(context);
    final f = filter.toLowerCase();
    final shown = console.where((l) => (!errorsOnly || l.error || l.level == 'WARN') && (f.isEmpty || l.text.toLowerCase().contains(f))).toList();
    Color? colorOf(_ConsoleLine l) => switch (l.level) {
          'ERRO' || 'FATA' || 'PANI' => th.colorScheme.error,
          'WARN' => Colors.orange,
          'DEBU' || 'TRAC' => th.hintColor,
          'CML' => th.colorScheme.primary,
          _ => null,
        };
    return Section(
      title: trGlobal('控制台'),
      icon: Icons.terminal,
      actions: [
        SizedBox(
          width: 200,
          child: TextField(
            decoration: InputDecoration(isDense: true, hintText: trGlobal('过滤'), prefixIcon: const Icon(Icons.search, size: 18)),
            onChanged: (s) => setState(() => filter = s),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(label: Text(trGlobal('仅错误/警告')), selected: errorsOnly, onSelected: (b) => setState(() => errorsOnly = b)),
        IconButton(
          tooltip: trGlobal('复制全部'),
          icon: const Icon(Icons.copy_all, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: shown.map((l) => l.level == null ? l.text : '[${l.level}] ${l.text}').join('\n')));
            toast(context, trGlobal('已复制到剪贴板'));
          },
        ),
        IconButton(tooltip: trGlobal('清空'), icon: const Icon(Icons.delete_sweep_outlined, size: 18), onPressed: () => setState(console.clear)),
      ],
      child: Container(
        height: 280,
        decoration: BoxDecoration(color: th.brightness == Brightness.dark ? Colors.black26 : Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(10),
        child: shown.isEmpty
            ? Center(child: Text(trGlobal('运行工具后，输出会显示在这里'), style: TextStyle(color: th.hintColor)))
            : SelectionArea(
                child: ListView.builder(
                  controller: consoleScroll,
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final l = shown[i];
                    return Text(l.text, style: TextStyle(fontFamily: 'Consolas', fontSize: 11.5, height: 1.35, color: colorOf(l)));
                  },
                ),
              ),
      ),
    );
  }

  Widget _outputs(BuildContext context) {
    final th = Theme.of(context);
    const icons = {
      'world': Icons.public,
      'skin': Icons.face,
      'capture': Icons.radar,
      'pack': Icons.inventory_2_outlined,
      'image': Icons.image_outlined,
      'chat': Icons.forum_outlined,
      'log': Icons.description_outlined,
    };
    final kinds = {
      'world': trGlobal('世界'),
      'skin': trGlobal('皮肤'),
      'capture': trGlobal('抓包'),
      'pack': trGlobal('资源包'),
      'image': trGlobal('图片'),
      'chat': trGlobal('聊天'),
      'log': trGlobal('日志'),
      'other': trGlobal('其他'),
    };
    return Section(
      title: trGlobal('输出文件'),
      icon: Icons.folder_copy_outlined,
      subtitle: tool.workDir,
      actions: [IconButton(tooltip: trGlobal('刷新'), icon: const Icon(Icons.refresh), onPressed: _refresh)],
      child: outputs.isEmpty
          ? EmptyHint(Icons.inbox_outlined, trGlobal('还没有输出文件'))
          : Column(children: [
              for (final o in outputs.take(60))
                ListTile(
                  dense: true,
                  leading: Icon(icons[o.kind] ?? Icons.insert_drive_file_outlined, color: th.colorScheme.primary),
                  title: Row(children: [
                    Flexible(child: Text(o.name, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Pill(kinds[o.kind] ?? o.kind),
                  ]),
                  subtitle: Text('${fmtDate(o.modified)}${o.isDirectory ? '' : '  ·  ${fmtBytes(o.size)}'}  ·  ${p.relative(o.path, from: tool.workDir)}'),
                  trailing: Wrap(spacing: 4, children: [
                    if (!o.isDirectory)
                      TextButton(onPressed: () => Process.start('explorer.exe', [o.path]), child: Text(trGlobal('打开'))),
                    TextButton(onPressed: () => revealInExplorer(o.path), child: Text(o.isDirectory ? trGlobal('打开文件夹') : trGlobal('所在位置'))),
                  ]),
                ),
            ]),
    );
  }
}

// ============================ NetEase tab ============================

class _NeteaseTab extends StatefulWidget {
  const _NeteaseTab();
  @override
  State<_NeteaseTab> createState() => _NeteaseTabState();
}

class _NeteaseTabState extends State<_NeteaseTab> with AutomaticKeepAliveClientMixin {
  final ne = NeteaseSaves();
  List<String> roots = [];
  List<Directory> worlds = [];
  String? path;
  NeteaseAction action = NeteaseAction.status;
  bool running = false;
  final List<NeteaseLine> lines = [];
  NeteaseResult? result;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    roots = NeteaseSaves.candidateWorldRoots();
    worlds = [for (final r in roots) ...NeteaseSaves.worldsIn(r)];
    setState(() {});
  }

  Future<void> _pick() async {
    final d = await getDirectoryPath(initialDirectory: roots.firstOrNull, confirmButtonText: trGlobal('选择存档文件夹'));
    if (d != null) setState(() => path = d);
  }

  Future<void> _run() async {
    final pth = path;
    if (pth == null) return toast(context, trGlobal('请先选择存档'), error: true);
    if (action.writes &&
        !await confirm(context, trGlobal('解密存档'), trGlobal('将直接修改这个存档的 db 文件。开始前会自动把整个存档备份到 CML 备份目录。\n\n请确认这是你自己的存档。'), ok: trGlobal('备份并解密'))) {
      return;
    }
    setState(() {
      running = true;
      lines.clear();
      result = null;
    });
    try {
      final r = await ne.run(action, pth, onLine: (l) {
        if (mounted) setState(() => lines.add(l));
      });
      if (!mounted) return;
      setState(() => result = r);
      if (r.backup != null) toast(context, trGlobal('已备份到 {0}', [r.backup]));
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final th = Theme.of(context);
    final r = result;
    return PageBody(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.withValues(alpha: 0.4))),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: Colors.orange, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trGlobal('仅用于你自己的网易存档'), style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(trGlobal('网易版（中国版）基岩版的本地存档是加密的。这个工具可以检查和解密你自己创建/拥有的存档，以便备份或导入国际版。请勿用于他人的作品或付费地图。'),
                  style: th.textTheme.bodySmall?.copyWith(height: 1.5)),
            ]),
          ),
        ]),
      ),
      if (!ne.available) Card(child: EmptyHint(Icons.extension_off_outlined, trGlobal('没有找到 NeMcDecrypter（{0}），请重新安装 CML', [ne.exe]))),
      Section(
        title: trGlobal('选择存档'),
        icon: Icons.folder_special_outlined,
        actions: [
          IconButton(tooltip: trGlobal('重新扫描'), icon: const Icon(Icons.refresh), onPressed: _scan),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(icon: const Icon(Icons.folder_open, size: 18), label: Text(trGlobal('选择文件夹')), onPressed: _pick),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (path != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: th.colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(Icons.check_circle, color: th.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(NeteaseSaves.worldName(p.basename(path!).toLowerCase() == 'db' ? p.dirname(path!) : path!), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(path!, style: th.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                TextButton(onPressed: () => revealInExplorer(path!), child: Text(trGlobal('打开文件夹'))),
              ]),
            ),
          if (worlds.isEmpty)
            Text(
              roots.isEmpty
                  ? trGlobal('没有自动找到网易版存档目录（通常在 {0}），请手动选择存档文件夹', [r'%APPDATA%\MinecraftPE_Netease\minecraftWorlds'])
                  : trGlobal('存档目录里没有找到存档'),
              style: TextStyle(color: th.hintColor),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(shrinkWrap: true, children: [
                for (final w in worlds)
                  ListTile(
                    dense: true,
                    selected: path == w.path,
                    leading: const Icon(Icons.public),
                    title: Text(NeteaseSaves.worldName(w.path)),
                    subtitle: Text('${p.basename(w.path)}  ·  ${fmtDate(w.statSync().modified)}'),
                    onTap: () => setState(() => path = w.path),
                  ),
              ]),
            ),
        ]),
      ),
      Section(
        title: trGlobal('操作'),
        icon: Icons.lock_open_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<NeteaseAction>(
            segments: [
              ButtonSegment(value: NeteaseAction.status, icon: const Icon(Icons.search, size: 18), label: Text(trGlobal('检查加密状态'))),
              ButtonSegment(value: NeteaseAction.decrypt, icon: const Icon(Icons.lock_open, size: 18), label: Text(trGlobal('解密存档'))),
              ButtonSegment(value: NeteaseAction.readKey, icon: const Icon(Icons.key, size: 18), label: Text(trGlobal('读取存档密钥'))),
            ],
            selected: {action},
            onSelectionChanged: (s) => setState(() => action = s.first),
          ),
          const SizedBox(height: 10),
          Text(
            switch (action) {
              NeteaseAction.status => trGlobal('只读取，不修改存档：列出 db 里每个文件是否加密'),
              NeteaseAction.decrypt => trGlobal('就地解密 db 文件；会先把整个存档备份到 {0}', [NeteaseSaves.backupDir]),
              NeteaseAction.readKey => trGlobal('只读取，不修改存档：读出存档的加密密钥'),
            },
            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
          ),
          const SizedBox(height: 14),
          Row(children: [
            FilledButton.icon(
              icon: running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
              label: Text(running ? trGlobal('处理中…') : trGlobal('开始')),
              onPressed: running || path == null || !ne.available ? null : _run,
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(trGlobal('备份目录')),
              onPressed: () async {
                await Directory(NeteaseSaves.backupDir).create(recursive: true);
                await revealInExplorer(NeteaseSaves.backupDir);
              },
            ),
          ]),
        ]),
      ),
      if (lines.isNotEmpty || r != null)
        Section(
          title: trGlobal('结果'),
          icon: Icons.fact_check_outlined,
          actions: [
            if (r != null) ...[
              if (r.worldEncrypted) Pill(trGlobal('已加密'), color: Colors.orange),
              if (r.worldPlain) Pill(trGlobal('未加密'), color: Colors.green),
              if (r.hasError) ...[const SizedBox(width: 6), Pill(trGlobal('有错误'), color: th.colorScheme.error)],
            ],
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (r != null && r.action == NeteaseAction.status)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(trGlobal('加密文件 {0} 个，未加密 {1} 个', [r.encrypted, r.plain]), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (r?.key != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Text(trGlobal('密钥：'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Expanded(child: SelectableText(r!.key!, style: const TextStyle(fontFamily: 'Consolas'))),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: r.key!));
                      toast(context, trGlobal('已复制到剪贴板'));
                    },
                  ),
                ]),
              ),
            if (r?.backup != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Icon(Icons.inventory_2_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(trGlobal('已备份到 {0}', [r!.backup]), style: th.textTheme.bodySmall)),
                  TextButton(onPressed: () => revealInExplorer(r.backup!), child: Text(trGlobal('所在位置'))),
                ]),
              ),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: th.brightness == Brightness.dark ? Colors.black26 : Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10)),
              child: SelectionArea(
                child: ListView(shrinkWrap: true, children: [
                  for (final l in lines)
                    Text(l.text,
                        style: TextStyle(fontFamily: 'Consolas', fontSize: 11.5, height: 1.4, color: l.isError ? th.colorScheme.error : (l.isInfo ? th.colorScheme.primary : null))),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
