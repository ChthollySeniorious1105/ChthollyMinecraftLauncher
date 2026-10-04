import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:aurora_server/server.dart';

/// Aurora server entry point.
///
/// Usage: aurora_server [--port 7788] [--web-port 7790] [--name "我的服务器"]
/// If --port is not given, the port is read from aurora_server.json next to
/// the executable, or asked interactively on first run. The web client (HTTP +
/// WebSocket) listens on --web-port / `webPort` (default 7790, 0 = off) and
/// serves the `web` folder next to the executable.
Future<void> main(List<String> args) async {
  int? port;
  int? webPort;
  String? name;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if ((a == '--port' || a == '-p') && i + 1 < args.length) {
      port = int.tryParse(args[++i]);
    } else if (a.startsWith('--port=')) {
      port = int.tryParse(a.substring(7));
    } else if (a == '--web-port' && i + 1 < args.length) {
      webPort = int.tryParse(args[++i]);
    } else if (a.startsWith('--web-port=')) {
      webPort = int.tryParse(a.substring(11));
    } else if (a == '--name' && i + 1 < args.length) {
      name = args[++i];
    } else if (a == '--help' || a == '-h') {
      stdout.writeln('用法: aurora_server [--port 端口] [--web-port 网页版端口(0=关闭)] [--name 服务器名称]');
      return;
    }
  }

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  final cfgFile = File('$exeDir${sep}aurora_server.json');
  Map<String, dynamic> cfg = {};
  if (cfgFile.existsSync()) {
    try {
      cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
  }
  port ??= cfg['port'] is int ? cfg['port'] as int : null;
  name ??= cfg['name'] is String ? cfg['name'] as String : null;

  if (port == null && stdin.hasTerminal) {
    stdout.write('请输入服务器端口（直接回车使用 $kDefaultPort）：');
    final line = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
    port = int.tryParse(line);
    stdout.write('请输入服务器名称（直接回车使用 "Aurora 服务器"）：');
    final n = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
    if (n.isNotEmpty) name = n;
  }
  port ??= kDefaultPort;
  if (port < 1 || port > 65535) {
    stderr.writeln('端口无效：$port');
    exit(1);
  }
  name ??= 'Aurora 服务器';
  webPort ??= cfg['webPort'] is int ? cfg['webPort'] as int : kDefaultWebPort;
  if (webPort < 0 || webPort > 65535 || (webPort == port && webPort != 0)) {
    stderr.writeln('网页版端口无效：$webPort（不能与游戏端口相同，0 表示关闭）');
    exit(1);
  }
  // pid salt: generated once; changing it resets everyone's 战绩 identity
  final oldSalt = cfg['salt'];
  final salt = oldSalt is String && oldSalt.length >= 16 ? oldSalt : _randomHex(16);
  try {
    // keep any extra keys the admin added; only update the ones we own
    cfg
      ..['port'] = port
      ..['webPort'] = webPort
      ..['name'] = name
      ..['salt'] = salt;
    cfgFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
  } catch (_) {}

  ensureEnvExample(exeDir);
  final (env, envPath) = loadEnv([exeDir, Directory.current.path]);
  final ai = HttpAiService.fromEnv(env);
  final identity = _loadIdentity('$exeDir${sep}server_identity.key');
  final server = AuroraServer(port,
      serverName: name,
      resourceDir: Directory('$exeDir${sep}words'),
      identity: identity,
      ai: ai.configured ? ai : null,
      salt: salt,
      dataDir: Directory('$exeDir${sep}data'),
      replayDir: Directory('$exeDir${sep}replays'),
      replayKeep: int.tryParse(env['REPLAY_KEEP']?.trim() ?? '') ?? 2000,
      discoveryPort: kDiscoveryPort,
      webPort: webPort == 0 ? null : webPort,
      webDir: Directory('$exeDir${sep}web'),
      publicWebUrl: env['PUBLIC_WEB_URL']?.trim() ?? '',
      publicNativeAddress: env['PUBLIC_TCP_ADDRESS']?.trim() ?? '',
      trustProxy: env['TRUST_PROXY']?.trim().toLowerCase() == 'true');
  server.resources.ensureTemplates();
  try {
    await server.start();
  } on SocketException catch (e) {
    stderr.writeln('无法监听端口 $port：${e.message}');
    exit(1);
  }
  logLine('服务器名称：$name');
  logLine('服务器指纹：${identity.fingerprint}（玩家首次连接时会看到，可用于核对服务器身份）');
  logLine('已加载 ${gameRegistry.length} 款游戏');
  logLine(envPath == null ? '未找到 .env（可参考 exe 同目录的 .env.example 创建）' : '已读取配置 $envPath');
  logLine(ai.configured ? 'AI 已启用：${ai.label}' : 'AI 未启用（电脑玩家使用普通算法）');
  logLine('回放 ${server.replays.count} 局，战绩 ${server.stats.players.length} 人');
  logLine('本机地址：');
  for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in iface.addresses) {
      logLine('  ${a.address}:$port  (${iface.name})');
    }
  }
  final wp = server.webBoundPort;
  if (wp != null) {
    logLine('网页版：浏览器打开 http://<上面的地址>:$wp 即可游玩（内网穿透时把 TCP $wp 也映射出去）');
  }
  logLine('输入 help 查看控制台命令');

  if (stdin.hasTerminal) {
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
      final cmd = line.trim();
      final sp = cmd.indexOf(' ');
      final verb = sp < 0 ? cmd : cmd.substring(0, sp);
      final arg = sp < 0 ? '' : cmd.substring(sp + 1).trim();
      switch (verb) {
        case 'help':
          stdout.writeln('rooms          列出房间\n'
              'users          列出在线玩家\n'
              'kick <#id>     断开玩家\n'
              'ban <#id>      断开玩家并封禁其 IP（到重启为止）\n'
              'say <文本>     全服系统公告\n'
              'ai             AI 状态、今日用量、最近错误\n'
              'replays        回放数量与占用空间\n'
              'stats          战绩人数\n'
              'quit           关闭服务器');
        case 'rooms':
          final lines = server.describeRooms();
          stdout.writeln(lines.isEmpty ? '（没有房间）' : lines.join('\n'));
        case 'users':
          for (final c in server.onlineClients) {
            stdout.writeln('#${c.id} ${c.name} ${c.address} ${c.room == null ? "大厅" : "房间${c.room!.id}"}');
          }
        case 'kick' || 'ban':
          final id = int.tryParse(arg.replaceFirst('#', ''));
          if (id == null) {
            stdout.writeln('用法：$verb <玩家#id>（用 users 查看 id）');
          } else if (server.kickClient(id, ban: verb == 'ban')) {
            stdout.writeln(verb == 'ban' ? '已断开并封禁 #$id 的 IP' : '已断开 #$id');
          } else {
            stdout.writeln('没有找到玩家 #$id');
          }
        case 'say':
          if (arg.isEmpty) {
            stdout.writeln('用法：say <文本>');
          } else {
            server.announce(arg);
            stdout.writeln('已发送公告');
          }
        case 'ai':
          stdout.writeln(ai.status());
        case 'replays':
          final mb = (server.replays.totalBytes / 1024 / 1024).toStringAsFixed(1);
          stdout.writeln('回放 ${server.replays.count} 局，占用约 $mb MB（最多保留 ${server.replays.keep} 局）');
        case 'stats':
          stdout.writeln('战绩记录 ${server.stats.players.length} 人');
        case 'quit' || 'exit' || 'stop':
          await server.stop();
          exit(0);
        case '':
          break;
        default:
          stdout.writeln('未知命令，输入 help 查看帮助');
      }
    });
  }
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

String _randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Long-term server key (X25519 seed). Clients pin its fingerprint; keep this
/// file private and back it up — deleting it makes every client warn that the
/// server identity changed.
ServerIdentity _loadIdentity(String path) {
  final f = File(path);
  try {
    if (f.existsSync()) {
      final seed = base64.decode(f.readAsStringSync().trim());
      if (seed.length == 32) return ServerIdentity.fromSeed(seed);
      stderr.writeln('server_identity.key 格式错误，将重新生成');
    }
  } catch (e) {
    stderr.writeln('读取 server_identity.key 失败：$e');
  }
  final seed = ServerIdentity.newSeed();
  try {
    f.writeAsStringSync(base64.encode(seed));
  } catch (e) {
    stderr.writeln('无法保存 server_identity.key（重启后指纹会变化）：$e');
  }
  return ServerIdentity.fromSeed(seed);
}
