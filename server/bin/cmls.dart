import 'dart:convert';
import 'dart:io';

import 'package:cml_core/tunnel.dart';
import 'package:cmls/cmls.dart';

/// cmls.exe [--port N] [--name NAME] [--password PW] [--data DIR]
///          [--public-udp PORT|off] [--public-udp-room ROOM] [--public-udp-max N]
///
/// `--public-udp` (alias `--udp-port`, default off) opens a game-facing Bedrock UDP port: CMLS answers
/// RakNet pings there with the exposed room's pong and relays any internet Bedrock client to that room's
/// host, so players without CML can "Add Server" `<cmls-host>:<PORT>`. The exposed room is the one given by
/// `--public-udp-room`, otherwise the first password-less Bedrock room whose host ticked "公网直连".
/// This publishes the host's game to the whole internet like a normal server (room passwords do not
/// apply); per-IP rate limits and `--public-udp-max` (default 32) flows cap abuse.
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
  final pu = arg('--public-udp') ?? arg('--udp-port');
  if (pu != null) cfg.publicUdpPort = pu == 'off' ? 0 : int.parse(pu);
  if (arg('--public-udp-room') != null) cfg.publicUdpRoom = arg('--public-udp-room')!.toUpperCase();
  if (arg('--public-udp-max') != null) cfg.publicUdpMaxFlows = int.parse(arg('--public-udp-max')!);
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
  if (server.publicUdpPort != null) {
    print('基岩版公网入口：UDP ${server.publicUdpPort}（需额外放行 / 映射该 UDP 端口）。'
        '${cfg.publicUdpRoom.isEmpty ? '房主创建无密码基岩版房间并勾选「公网直连」后生效。' : '固定公开房间 ${cfg.publicUdpRoom}。'}');
    print('注意：公网入口会把房主的游戏像普通服务器一样暴露给任何人，房间密码对它无效，请依赖游戏自身的白名单 / Xbox 登录。');
  }

  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });

  if (!stdin.hasTerminal) return;
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final parts = line.trim().split(RegExp(r'\s+'));
    switch (parts.first) {
      case 'help':
        print('rooms  列出房间\nusers  列出在线玩家\nkick <#id>  断开玩家\nban <#id>  封禁 IP（到重启为止）\nclose <房间号>  关闭房间\n'
            'public <房间号|off>  设置基岩版公网 UDP 入口指向的房间（off = 由房主自行开启）\nquit  关闭服务器');
      case 'rooms':
        if (server.rooms.isEmpty) print('（没有房间）');
        for (final r in server.rooms.values) {
          final udp = r.isBedrock ? '  [基岩版 ${r.flows.length} 个 UDP 流${server.publicRoom == r ? '，公网 UDP ${server.publicUdpPort}' : ''}]' : '';
          print('${r.id}  ${r.title}  房主 ${r.host.name}  ${r.guests.length + 1} 人  ${r.public ? '公开' : '私密'}${r.locked ? ' 🔒' : ''}  ${r.version}$udp');
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
      case 'public':
        if (server.publicUdpPort == null) {
          print('未开启公网 UDP 入口（启动参数 --public-udp <端口>）');
        } else {
          final id = parts.length > 1 && parts[1] != 'off' ? parts[1].toUpperCase() : '';
          server.setPublicUdpRoom(id);
          print(id.isEmpty ? '公网 UDP 入口改为由房主开启' : '公网 UDP ${server.publicUdpPort} → 房间 $id');
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
