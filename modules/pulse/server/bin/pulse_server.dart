import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pulse_shared/pulse_shared.dart';
import 'package:pulse_server/server.dart';

/// Pulse server entry point.
///
/// Usage: pulse_server [--port 7800] [--name "我的服务器"] [--data <dir>]
/// Settings are kept in pulse_server.json next to the executable; the first
/// interactive start asks for port and name.
Future<void> main(List<String> args) async {
  int? port;
  String? name;
  String? dataDir;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if ((a == '--port' || a == '-p') && i + 1 < args.length) {
      port = int.tryParse(args[++i]);
    } else if (a.startsWith('--port=')) {
      port = int.tryParse(a.substring(7));
    } else if (a == '--name' && i + 1 < args.length) {
      name = args[++i];
    } else if (a == '--data' && i + 1 < args.length) {
      dataDir = args[++i];
    } else if (a == '--help' || a == '-h') {
      stdout.writeln('用法: pulse_server [--port 端口] [--name 服务器名称] [--data 数据目录]');
      return;
    }
  }

  final exe = Platform.resolvedExecutable;
  // `dart run` resolves to dart.exe; keep data next to the script in that case
  final exeDir = exe.toLowerCase().endsWith('dart.exe') ? Directory.current.path : File(exe).parent.path;
  final sep = Platform.pathSeparator;
  final cfgFile = File('$exeDir${sep}pulse_server.json');
  Map<String, dynamic> cfg = {};
  if (cfgFile.existsSync()) {
    try {
      cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
  }
  port ??= cfg['port'] is int ? cfg['port'] as int : null;
  final firstRun = !cfgFile.existsSync();
  if (port == null && stdin.hasTerminal) {
    stdout.write('请输入服务器端口（直接回车使用 $kDefaultPort）：');
    port = int.tryParse(stdin.readLineSync(encoding: utf8)?.trim() ?? '');
    stdout.write('请输入服务器名称（直接回车使用 "Pulse 服务器"）：');
    final n = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
    if (n.isNotEmpty) name = n;
  }
  port ??= kDefaultPort;
  if (port < 1 || port > 65535) {
    stderr.writeln('端口无效：$port');
    exit(1);
  }
  try {
    cfg['port'] = port;
    cfgFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
  } catch (_) {}

  final store = Store(Directory(dataDir ?? '$exeDir${sep}data'))..load();
  if (name != null) {
    store.name = name;
    store.markDirty('channels');
  } else if (firstRun) {
    store.markDirty('channels');
  }
  final identity = _loadIdentity('$exeDir${sep}server_identity.key');
  final server = PulseServer(port, store: store, identity: identity, discoveryPort: kDiscoveryPort);
  try {
    await server.start();
  } on SocketException catch (e) {
    stderr.writeln('无法监听端口 $port：${e.message}');
    exit(1);
  }
  logLine('服务器名称：${store.name}');
  logLine('服务器指纹：${identity.fingerprint}（用户首次连接时会看到，可用于核对服务器身份）');
  logLine('注册方式：${_regLabel(store.regMode)}；已有用户 ${store.users.length} 人');
  logLine(server.describeStorage());
  if (store.users.isEmpty) logLine('提示：第一个注册的账号将自动成为服主');
  logLine('本机地址：');
  for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in iface.addresses) {
      logLine('  ${a.address}:$port  (${iface.name})');
    }
  }
  logLine('输入 help 查看控制台命令');

  if (stdin.hasTerminal) {
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
      final parts = line.trim().split(RegExp(r'\s+'));
      final verb = parts.first;
      final rest = parts.skip(1).toList();
      final arg = rest.join(' ');
      switch (verb) {
        case 'help':
          stdout.writeln('users                   列出所有用户\n'
              'online                  在线连接\n'
              'kick <用户>             断开用户（用户名或 #id）\n'
              'ban <用户>              封禁用户及其 IP\n'
              'unban <用户>            解除封禁\n'
              'op <用户>               设为管理员\n'
              'deop <用户>             取消管理员\n'
              'owner <用户>            转让服主\n'
              'resetpw <用户> <新密码> 重置密码并让其所有设备下线\n'
              'reg open|invite|closed  注册方式：开放 / 邀请码 / 关闭\n'
              'invite [次数] [小时]    生成邀请码（默认 1 次、24 小时；0 = 不限）\n'
              'say <文本>              全服公告\n'
              'storage                 查看附件存储占用\n'
              'storage days <天>       附件保留天数（默认 $kDefaultFileDays 天，到期自动删除）\n'
              'storage max <MB>        附件总存储上限（超出时先删除最旧的附件）\n'
              'storage file <MB>       单个文件大小上限（最大 2048 MB）\n'
              'quit                    关闭服务器');
        case 'users':
          final l = server.describeUsers();
          stdout.writeln(l.isEmpty ? '（还没有用户）' : l.join('\n'));
        case 'online':
          for (final c in server.authed) {
            stdout.writeln('连接#${c.id} ${c.user!.username} ${c.ip}');
          }
        case 'kick' || 'ban':
          stdout.writeln(server.consoleKick(arg, ban: verb == 'ban') ? '完成' : '没有找到用户 $arg');
        case 'unban':
          stdout.writeln(server.consoleUnban(arg) ? '已解除封禁' : '没有找到被封禁的用户 $arg');
        case 'op' || 'deop' || 'owner':
          final role = verb == 'op' ? Role.admin : (verb == 'owner' ? Role.owner : Role.member);
          stdout.writeln(server.consoleSetRole(arg, role) ? '已设为${Role.label(role)}' : '没有找到用户 $arg');
        case 'resetpw':
          if (rest.length < 2 || validatePassword(rest[1]) != null) {
            stdout.writeln('用法：resetpw <用户> <新密码（至少 8 位）>');
          } else {
            stdout.writeln(await server.consoleResetPassword(rest[0], rest[1]) ? '密码已重置' : '没有找到用户 ${rest[0]}');
          }
        case 'reg':
          if ([RegMode.open, RegMode.invite, RegMode.closed].contains(arg)) {
            server.setRegMode(arg);
            stdout.writeln('注册方式：${_regLabel(arg)}');
          } else {
            stdout.writeln('用法：reg open|invite|closed（当前：${_regLabel(store.regMode)}）');
          }
        case 'invite':
          final uses = rest.isNotEmpty ? int.tryParse(rest[0]) ?? 1 : 1;
          final hours = rest.length > 1 ? int.tryParse(rest[1]) ?? 24 : 24;
          stdout.writeln('邀请码：${server.createInviteConsole(uses, hours)}');
        case 'storage':
          final n = rest.length > 1 ? int.tryParse(rest[1]) : null;
          if (rest.isEmpty) {
            stdout.writeln(server.describeStorage());
          } else if (n == null || n < 1 || !['days', 'max', 'file'].contains(rest[0])) {
            stdout.writeln('用法：storage | storage days <天> | storage max <MB> | storage file <MB>');
          } else {
            server.setStorage(days: rest[0] == 'days' ? n : null, maxMB: rest[0] == 'max' ? n : null, fileMaxMB: rest[0] == 'file' ? n : null);
            stdout.writeln(server.describeStorage());
          }
        case 'say':
          if (arg.isEmpty) {
            stdout.writeln('用法：say <文本>');
          } else {
            server.announce(arg);
            stdout.writeln('已发送公告');
          }
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
  Future<void> shutdown() async {
    logLine('正在保存数据并关闭…');
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  // periodic flush as a safety net (message logs are append-only)
  Timer.periodic(const Duration(seconds: 10), (_) => store.flush());
}

String _regLabel(String m) => switch (m) { RegMode.invite => '需要邀请码', RegMode.closed => '已关闭', _ => '开放注册' };

/// Long-term server key (X25519 seed). Clients pin it per address; keep this
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
