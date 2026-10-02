import 'dart:convert';
import 'dart:io';

import 'package:cml_core/tunnel.dart';
import 'package:cmls/cmls.dart';

/// cmls.exe [--port N] [--name NAME] [--password PW] [--data DIR]
Future<void> main(List<String> args) async {
  String? arg(String k) {
    final i = args.indexOf(k);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final dataDir = arg('--data') ?? (Platform.script.path.endsWith('.dart') ? Directory.current.path : exeDir);
  await Directory(dataDir).create(recursive: true);
  final cfgFile = File('$dataDir${Platform.pathSeparator}cmls.json');
  final keyFile = File('$dataDir${Platform.pathSeparator}server_identity.key');

  ServerConfig cfg;
  if (await cfgFile.exists()) {
    cfg = ServerConfig.fromJson(jsonDecode(await cfgFile.readAsString()) as Map);
  } else {
    cfg = ServerConfig();
    if (stdin.hasTerminal && arg('--port') == null) {
      stdout.write('端口（默认 ${cfg.port}）：');
      final p = int.tryParse(stdin.readLineSync()?.trim() ?? '');
      if (p != null && p > 0 && p < 65536) cfg.port = p;
      stdout.write('服务器名称（默认 CMLS）：');
      final n = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
      if (n.isNotEmpty) cfg.name = n;
    }
  }
  if (arg('--port') != null) cfg.port = int.parse(arg('--port')!);
  if (arg('--name') != null) cfg.name = arg('--name')!;
  if (arg('--password') != null) cfg.password = arg('--password')!;
  await cfgFile.writeAsString(const JsonEncoder.withIndent('  ').convert(cfg.toJson()));

  ServerIdentity id;
  if (await keyFile.exists()) {
    id = ServerIdentity.fromSeed(base64.decode((await keyFile.readAsString()).trim()));
  } else {
    final seed = ServerIdentity.newSeed();
    await keyFile.writeAsString(base64.encode(seed));
    id = ServerIdentity.fromSeed(seed);
    print('已生成服务器身份密钥 server_identity.key —— 请备份，不要外传。');
  }

  final server = CmlsServer(cfg, id, log: (s) => print('[${DateTime.now().toIso8601String().substring(11, 19)}] $s'));
  await server.start();
  print('服务器名称：${cfg.name}');
  print('服务器指纹：${id.fingerprint}（玩家首次连接时核对）');
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      print('  本机地址：${a.address}:${cfg.port}（${i.name}）');
    }
  }
  print('内网穿透只需映射 TCP ${cfg.port}。输入 help 查看命令。');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });

  if (!stdin.hasTerminal) return;
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final parts = line.trim().split(RegExp(r'\s+'));
    switch (parts.first) {
      case 'help':
        print('rooms  列出房间\nusers  列出在线玩家\nkick <#id>  断开玩家\nban <#id>  封禁 IP（到重启为止）\nclose <房间号>  关闭房间\nquit  关闭服务器');
      case 'rooms':
        if (server.rooms.isEmpty) print('（没有房间）');
        for (final r in server.rooms.values) {
          print('${r.id}  ${r.title}  房主 ${r.host.name}  ${r.guests.length + 1} 人  ${r.public ? '公开' : '私密'}${r.locked ? ' 🔒' : ''}  ${r.version}');
        }
      case 'users':
        for (final p in server.peers) {
          print('#${p.id}  ${p.name.isEmpty ? '(未登录)' : p.name}  ${p.ip}  ${p.room?.id ?? ''}');
        }
      case 'kick' || 'ban':
        final pid = int.tryParse(parts.length > 1 ? parts[1].replaceAll('#', '') : '');
        final p = server.peers.where((x) => x.id == pid).firstOrNull;
        if (p == null) {
          print('找不到玩家');
        } else if (parts.first == 'ban') {
          server.ban(p.ip);
          print('已封禁 ${p.ip}');
        } else {
          p.socket.destroy();
          print('已断开 ${p.name}');
        }
      case 'close':
        final r = parts.length > 1 ? server.rooms[parts[1].toUpperCase()] : null;
        if (r == null) {
          print('找不到房间');
        } else {
          r.host.socket.destroy();
        }
      case 'quit' || 'exit' || 'stop':
        await server.stop();
        exit(0);
      case '':
        break;
      default:
        print('未知命令，输入 help 查看');
    }
  }
}
