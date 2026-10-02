import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import '../common/task.dart';
import '../net/http.dart';
import '../tools/github_component.dart';

/// mihomo (Clash.Meta) — the proxy core used by Clash Verge Rev. CML runs it directly
/// and keeps it updated from MetaCubeX/mihomo releases.
class MihomoCore extends GithubComponent {
  MihomoCore(super.http);

  @override
  String get id => 'mihomo';
  @override
  String get displayName => 'mihomo 内核';
  @override
  String get repo => 'MetaCubeX/mihomo';

  @override
  GithubAsset? pickAsset(GithubRelease r) {
    final arch = Os.arch == 'arm64' ? 'arm64' : (Os.arch == 'x86' ? '386' : 'amd64-compatible');
    final re = RegExp('^mihomo-windows-$arch-v[\\d.]+\\.zip\$');
    return r.assets.where((a) => re.hasMatch(a.name)).firstOrNull;
  }

  @override
  Future<void> install(File file, GithubAsset asset, Task? task) async {
    final tmp = p.join(installDir, '.unpack');
    if (await Directory(tmp).exists()) await Directory(tmp).delete(recursive: true);
    await GithubComponent.unzipTo(file, tmp);
    final exe = await Directory(tmp).list(recursive: true).firstWhere((e) => e is File && e.path.toLowerCase().endsWith('.exe'));
    final dest = File(exePath);
    if (await dest.exists()) await dest.delete();
    await (exe as File).rename(dest.path);
    await Directory(tmp).delete(recursive: true);
  }

  String get exePath => p.join(installDir, 'mihomo.exe');
  bool get installed => File(exePath).existsSync();
}

/// Full Clash Verge Rev desktop app (optional). Tracks clash-verge-rev releases and installs silently.
class ClashVergeApp extends GithubComponent {
  ClashVergeApp(super.http);

  @override
  String get id => 'clash-verge';
  @override
  String get displayName => 'Clash Verge Rev';
  @override
  String get repo => 'clash-verge-rev/clash-verge-rev';

  @override
  GithubAsset? pickAsset(GithubRelease r) {
    final arch = Os.arch == 'arm64' ? 'arm64' : 'x64';
    return r.assets.where((a) => a.name.endsWith('_$arch-setup.exe')).firstOrNull;
  }

  /// Runs the official installer with its normal UI so the user sees and confirms every step.
  @override
  Future<void> install(File file, GithubAsset asset, Task? task) async {
    final keep = File(p.join(installDir, asset.name));
    await keep.parent.create(recursive: true);
    await file.copy(keep.path);
    task?.update(detail: '请在弹出的安装程序中完成安装', progress: -1);
    final r = await Process.run(keep.path, const []);
    if (r.exitCode != 0) throw CmlException('verge_install', 'Clash Verge 安装未完成（退出码 ${r.exitCode}）');
  }

  static String? findInstalled() {
    for (final base in [Platform.environment['ProgramFiles'], Platform.environment['LOCALAPPDATA'] == null ? null : p.join(Platform.environment['LOCALAPPDATA']!, 'Programs')]) {
      if (base == null) continue;
      for (final name in ['Clash Verge', 'clash-verge']) {
        final exe = p.join(base, name, 'clash-verge.exe');
        if (File(exe).existsSync()) return exe;
      }
    }
    return null;
  }
}

class ProxySubscription {
  String name;
  String url;
  DateTime? updated;
  int? usedBytes, totalBytes;
  DateTime? expire;
  ProxySubscription(this.name, this.url, {this.updated, this.usedBytes, this.totalBytes, this.expire});

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'updated': updated?.toIso8601String(),
        'used': usedBytes,
        'total': totalBytes,
        'expire': expire?.toIso8601String(),
      };
  factory ProxySubscription.fromJson(Map j) => ProxySubscription('${j['name']}', '${j['url']}',
      updated: DateTime.tryParse('${j['updated']}'),
      usedBytes: j['used'] as int?,
      totalBytes: j['total'] as int?,
      expire: DateTime.tryParse('${j['expire']}'));

  String get file => p.join(Os.cmlHome, 'proxy', 'profiles', '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.yaml');
}

enum ProxyMode {
  rule('规则'),
  global('全局'),
  direct('直连');

  final String label;
  const ProxyMode(this.label);
}

class ProxyGroup {
  final String name;
  final String type;
  final String now;
  final List<String> all;
  ProxyGroup(this.name, this.type, this.now, this.all);
}

class ProxySettings {
  int mixedPort = 7890;
  int controllerPort = 9097;
  String secret = '';
  ProxyMode mode = ProxyMode.rule;
  bool allowLan = false;
  bool systemProxy = false;
  bool autoStart = false;
  bool autoUpdateCore = true;
  bool tun = false;
  String? selected;
  List<ProxySubscription> subscriptions = [];

  Map<String, dynamic> toJson() => {
        'mixedPort': mixedPort,
        'controllerPort': controllerPort,
        'secret': secret,
        'mode': mode.name,
        'allowLan': allowLan,
        'systemProxy': systemProxy,
        'autoStart': autoStart,
        'autoUpdateCore': autoUpdateCore,
        'tun': tun,
        'selected': selected,
        'subscriptions': [for (final s in subscriptions) s.toJson()],
      };

  void load(Map j) {
    mixedPort = j['mixedPort'] as int? ?? mixedPort;
    controllerPort = j['controllerPort'] as int? ?? controllerPort;
    secret = j['secret'] as String? ?? secret;
    mode = ProxyMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => ProxyMode.rule);
    allowLan = j['allowLan'] == true;
    systemProxy = j['systemProxy'] == true;
    autoStart = j['autoStart'] == true;
    autoUpdateCore = j['autoUpdateCore'] != false;
    tun = j['tun'] == true;
    selected = j['selected'] as String?;
    subscriptions = [for (final s in j['subscriptions'] as List? ?? []) ProxySubscription.fromJson(s as Map)];
  }
}

/// Built-in Clash Verge–like proxy: subscriptions, node selection, modes, system proxy.
class ProxyService {
  final Http http;
  final MihomoCore core;
  final ProxySettings settings = ProxySettings();
  Process? _proc;
  final logs = <String>[];
  final _logCtl = StreamController<String>.broadcast();

  ProxyService(this.http) : core = MihomoCore(http);

  String get _home => p.join(Os.cmlHome, 'proxy');
  String get _settingsFile => p.join(_home, 'settings.json');
  bool get running => _proc != null;
  Stream<String> get logStream => _logCtl.stream;
  String get proxyAddress => '127.0.0.1:${settings.mixedPort}';

  Future<void> load() async {
    final j = await JsonFile.read(_settingsFile);
    if (j is Map) settings.load(j);
    if (settings.secret.isEmpty) {
      final r = Random.secure();
      settings.secret = base64Url.encode(List.generate(18, (_) => r.nextInt(256))).replaceAll('=', '');
      await save();
    }
  }

  Future<void> save() => JsonFile.write(_settingsFile, settings.toJson());

  // ---------- subscriptions ----------

  Future<ProxySubscription> addSubscription(String name, String url) async {
    final s = ProxySubscription(name, url);
    await updateSubscription(s);
    settings.subscriptions.removeWhere((x) => x.name == name);
    settings.subscriptions.add(s);
    settings.selected ??= name;
    await save();
    return s;
  }

  Future<void> updateSubscription(ProxySubscription s) async {
    // many providers return Clash YAML only for clash-compatible user agents
    final res = await http.send('GET', Uri.parse(s.url), headers: {'User-Agent': 'clash-verge/v2.5.6 mihomo'});
    final body = await Http.readAll(res, null);
    if (res.statusCode >= 400) throw CmlException('sub_http', '订阅更新失败（HTTP ${res.statusCode}）');
    final text = utf8.decode(body, allowMalformed: true);
    if (!text.contains('proxies:') && !text.contains('proxy-providers:')) {
      throw const CmlException('sub_format', '订阅内容不是 Clash 配置（请在机场后台选择 Clash/Mihomo 订阅链接）');
    }
    final info = res.headers.value('subscription-userinfo');
    if (info != null) {
      int? v(String k) => int.tryParse(RegExp('$k=(\\d+)').firstMatch(info)?.group(1) ?? '');
      s.usedBytes = (v('upload') ?? 0) + (v('download') ?? 0);
      s.totalBytes = v('total');
      final e = v('expire');
      if (e != null && e > 0) s.expire = DateTime.fromMillisecondsSinceEpoch(e * 1000);
    }
    await File(s.file).parent.create(recursive: true);
    await File(s.file).writeAsString(text);
    s.updated = DateTime.now();
    await save();
  }

  // ---------- core lifecycle ----------

  /// Writes the runtime config: the selected profile with CML's port/controller/mode overrides prepended.
  Future<String> _writeRuntimeConfig() async {
    final sub = settings.subscriptions.where((s) => s.name == settings.selected).firstOrNull;
    if (sub == null || !await File(sub.file).exists()) throw const CmlException('no_profile', '请先添加订阅');
    final profile = await File(sub.file).readAsString();
    final overrides = <String>{'mixed-port', 'port', 'socks-port', 'redir-port', 'tproxy-port', 'external-controller', 'secret', 'mode', 'allow-lan', 'external-ui', 'tun'};
    // drop top-level keys we override (keeps everything else untouched)
    final lines = profile.split('\n');
    final kept = <String>[];
    var skipping = false;
    for (final l in lines) {
      final m = RegExp(r'^([A-Za-z0-9_-]+):').firstMatch(l);
      if (m != null) skipping = overrides.contains(m.group(1));
      if (!skipping) kept.add(l);
    }
    final head = [
      'mixed-port: ${settings.mixedPort}',
      'allow-lan: ${settings.allowLan}',
      'mode: ${settings.mode.name}',
      'external-controller: 127.0.0.1:${settings.controllerPort}',
      'secret: "${settings.secret}"',
      if (settings.tun) ...['tun:', '  enable: true', '  stack: mixed', '  auto-route: true', '  auto-detect-interface: true'],
    ];
    final path = p.join(_home, 'runtime.yaml');
    await File(path).writeAsString('${head.join('\n')}\n${kept.join('\n')}');
    return path;
  }

  Future<void> start() async {
    if (running) return;
    if (!core.installed) throw const CmlException('core_missing', 'mihomo 内核尚未下载');
    final cfg = await _writeRuntimeConfig();
    final proc = await Process.start(core.exePath, ['-d', _home, '-f', cfg], workingDirectory: _home);
    _proc = proc;
    for (final s in [proc.stdout, proc.stderr]) {
      s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_log);
    }
    unawaited(proc.exitCode.then((c) {
      _log('[CML] 内核已退出（$c）');
      if (identical(_proc, proc)) _proc = null;
      if (settings.systemProxy) unawaited(SystemProxy.disable());
    }));
    // wait for controller
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await _api('GET', '/version');
        break;
      } catch (_) {}
    }
    if (settings.systemProxy) await SystemProxy.enable(proxyAddress);
  }

  Future<void> stop() async {
    final p = _proc;
    _proc = null;
    p?.kill();
    if (settings.systemProxy) await SystemProxy.disable();
  }

  Future<void> restart() async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await start();
  }

  void _log(String l) {
    logs.add(l);
    if (logs.length > 1000) logs.removeAt(0);
    _logCtl.add(l);
  }

  // ---------- controller API ----------

  Future<dynamic> _api(String method, String path, [Object? body]) async {
    final u = Uri.parse('http://127.0.0.1:${settings.controllerPort}$path');
    final c = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final req = await c.openUrl(method, u).timeout(const Duration(seconds: 5));
      req.headers.set('Authorization', 'Bearer ${settings.secret}');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final t = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) throw CmlException('controller', '内核接口错误：$t');
      return t.isEmpty ? null : jsonDecode(t);
    } finally {
      c.close(force: true);
    }
  }

  Future<List<ProxyGroup>> groups() async {
    final j = await _api('GET', '/proxies') as Map;
    final proxies = j['proxies'] as Map;
    final out = <ProxyGroup>[];
    // keep the order of GLOBAL's member list (matches the profile order)
    final order = [for (final n in (proxies['GLOBAL']?['all'] as List? ?? [])) '$n'];
    for (final name in [...order, 'GLOBAL']) {
      final g = proxies[name];
      if (g is! Map || g['all'] == null) continue;
      out.add(ProxyGroup(name, '${g['type']}', '${g['now'] ?? ''}', [for (final x in g['all'] as List) '$x']));
    }
    return out;
  }

  Future<void> select(String group, String proxy) => _api('PUT', '/proxies/${Uri.encodeComponent(group)}', {'name': proxy});

  /// Delay in ms, or null on timeout.
  Future<int?> delay(String proxy, {String url = 'https://www.gstatic.com/generate_204', int timeoutMs = 5000}) async {
    try {
      final j = await _api('GET', '/proxies/${Uri.encodeComponent(proxy)}/delay?timeout=$timeoutMs&url=${Uri.encodeComponent(url)}') as Map;
      return (j['delay'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> setMode(ProxyMode m) async {
    settings.mode = m;
    await save();
    if (running) await _api('PATCH', '/configs', {'mode': m.name});
  }

  Future<void> setSystemProxy(bool on) async {
    settings.systemProxy = on;
    await save();
    if (!running) return;
    on ? await SystemProxy.enable(proxyAddress) : await SystemProxy.disable();
  }

  /// Live traffic (bytes/s up, down).
  Stream<(int, int)> traffic() async* {
    final c = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:${settings.controllerPort}/traffic'));
      req.headers.set('Authorization', 'Bearer ${settings.secret}');
      final res = await req.close();
      await for (final l in res.transform(utf8.decoder).transform(const LineSplitter())) {
        final j = jsonDecode(l) as Map;
        yield ((j['up'] as num).toInt(), (j['down'] as num).toInt());
      }
    } finally {
      c.close(force: true);
    }
  }
}

/// Windows system proxy via the Internet Settings registry key.
abstract class SystemProxy {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';

  static Future<void> enable(String hostPort) async {
    await Process.run('reg', ['add', _key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    await Process.run('reg', ['add', _key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', hostPort, '/f']);
    await Process.run('reg', ['add', _key, '/v', 'ProxyOverride', '/t', 'REG_SZ', '/d', bypass, '/f']);
  }

  static Future<void> disable() async {
    await Process.run('reg', ['add', _key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
  }
}
