import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Repo root (tests run from core/).
final _repo = p.normalize(p.join(Directory.current.path, '..'));

const _helpOut = '\x1B[36mINFO\x1B[0m[0000] Bedrocktool Version v26.52-cml                \x1B[36mpart\x1B[0m=main\n'
    'Available Commands:\n'
    '\tdebug-proxy\tverbose debug packets\n\r\n'
    '\trender\trender a world to png\n\r\n'
    '\ttrans\t\n\r\n'
    '\tworlds\tdownload a world from a server\n\r\n'
    '\tlist-realms\tprints all realms you have access to\n\r\n';

const _worldsFlags = '''Usage of worlds:
ERRO[0000] flag: help requested                          part=main
  -address string
    	remote server address
  -block-updates
    	Block updates
  -capture
    	Capture pcap2 file (default true)
  -chunk-radius value
    	the max chunk radius to force (default <int Value>)
  -exclude-mobs value
    	list of mobs to exclude seperated by comma (default <[]string Value>)
  -listen value
    	example :19132 or 127.0.0.1:19132 (default 0.0.0.0:19132)
  -void
    	save with void generator (default true)
''';

void main() {
  group('BtParse', () {
    test('strips ANSI and splits logrus level', () {
      final line = BtParse.stripAnsi('\x1B[31mERRO\x1B[0m[0003] failed to connect to 1.2.3.4:19132: timeout   \x1B[31mpart\x1B[0m=main\r');
      final (lvl, msg) = BtParse.level(line);
      expect(lvl, 'ERRO');
      expect(msg, startsWith('failed to connect to 1.2.3.4:19132: timeout'));
      expect(BtParse.level('plain text').$1, isNull);
    });

    test('detects the Xbox Live device-code prompt', () {
      final ev = BtParse.events('Authenticate at https://login.live.com/oauth20_remoteconnect.srf?otc=ABCD1234');
      final login = ev.whereType<BtLogin>().single;
      expect(login.url, 'https://login.live.com/oauth20_remoteconnect.srf?otc=ABCD1234');
      expect(login.code, 'ABCD1234');

      final ms = BtParse.events('To sign in, use a web browser to open the page https://www.microsoft.com/link and enter the code K7XQ2PLM to authenticate.');
      expect(ms.whereType<BtLogin>().single.code, 'K7XQ2PLM');

      expect(BtParse.events('Authentication successful.').whereType<BtLoginDone>().single.success, isTrue);
      final failed = BtParse.events('Failed to Authenticate: context canceled').whereType<BtLoginDone>().single;
      expect(failed.success, isFalse);
      expect(failed.error, 'context canceled');
    });

    test('detects listening address and realms', () {
      expect(BtParse.events('INFO[0001] Listening on 0.0.0.0:19132  part=proxy').whereType<BtListening>().single.address, '0.0.0.0:19132');
      final r = BtParse.events('Name: My Realm 2\tid: 123456').whereType<BtRealm>().single;
      expect(r.name, 'My Realm 2');
      expect(r.id, '123456');
    });

    test('parses help command list', () {
      final cmds = BtParse.commandList(_helpOut);
      expect(cmds.keys, containsAll(['debug-proxy', 'render', 'worlds', 'list-realms', 'trans']));
      expect(cmds['worlds'], 'download a world from a server');
    });

    test('parses flag.PrintDefaults output', () {
      final flags = {for (final f in BtParse.flagHelp(_worldsFlags)) f.name: f};
      expect(flags.keys, ['address', 'block-updates', 'capture', 'chunk-radius', 'exclude-mobs', 'listen', 'void']);
      expect(flags['address']!.type, BtFlagType.address);
      expect(flags['block-updates']!.type, BtFlagType.boolean);
      expect(flags['block-updates']!.defaultBool, isFalse);
      expect(flags['capture']!.defaultBool, isTrue);
      expect(flags['chunk-radius']!.type, BtFlagType.integer);
      expect(flags['chunk-radius']!.defaultValue, '');
      expect(flags['exclude-mobs']!.type, BtFlagType.list);
      expect(flags['listen']!.defaultValue, '0.0.0.0:19132');
      expect(flags['void']!.description, 'save with void generator');
    });

    test('builds arguments', () {
      expect(
        BtParse.buildArgs('worlds', {'address': ' play.example.com ', 'void': false, 'chunk-radius': 0, 'exclude-mobs': ['zombie', ' ', 'creeper'], 'script': ''}),
        ['worlds', '-address=play.example.com', '-void=false', '-chunk-radius=0', '-exclude-mobs=zombie,creeper'],
      );
      expect(BtParse.buildArgs('merge', {'out': 'merged'}, positional: ['a', 'b']), ['merge', '-out=merged', 'a', 'b']);
    });

    test('built-in command table', () {
      expect(BtCommands.all.map((c) => c.name), containsAll(['worlds', 'skins', 'capture', 'chat-log', 'list-realms', 'realm-address', 'merge', 'render', 'packs', 'debug-proxy']));
      expect(BtCommands.worlds.flag('void')!.defaultBool, isTrue);
      expect(BtCommands.merge.positional, isTrue);
      expect(BedrockToolInfo.protocol, 2193);
    });

    test('supported version matches gophertunnel info.go', () {
      final info = File(p.join(_repo, 'tools', 'bedrocktool', 'gophertunnel', 'minecraft', 'protocol', 'info.go'));
      if (!info.existsSync()) return;
      final s = info.readAsStringSync();
      expect(RegExp(r'CurrentProtocol\s*=\s*(\d+)').firstMatch(s)!.group(1), '${BedrockToolInfo.protocol}');
      expect(RegExp(r'CurrentVersion\s*=\s*"([^"]+)"').firstMatch(s)!.group(1), BedrockToolInfo.gameVersion);
    });
  });

  group('GBK', () {
    test('decodes and encodes CP936', () {
      // "网易地图解密" in GBK
      final bytes = [0xcd, 0xf8, 0xd2, 0xd7, 0xb5, 0xd8, 0xcd, 0xbc, 0xbd, 0xe2, 0xc3, 0xdc];
      expect(Gbk.decode(bytes), '网易地图解密');
      expect(Gbk.encode('网易地图解密'), bytes);
      expect(Gbk.decode('I:abc'.codeUnits), 'I:abc');
      expect(Gbk.canEncode(r'C:\Users\张三\存档'), isTrue);
      expect(Gbk.canEncode('emoji 😀'), isFalse);
    }, testOn: 'windows');
  });

  group('NeteaseSaves parsing', () {
    test('cleans banner, menu and glued prompts', () {
      expect(NeteaseSaves.cleanLine('  @   @@  @@@ '), '');
      expect(NeteaseSaves.cleanLine('            -Developed by jerbvsjhs'), '');
      expect(NeteaseSaves.cleanLine('2.查看文件/文件夹加密状态 '), '');
      expect(NeteaseSaves.splitPrompts('请选择运行方式0/1/2:请将db文件夹拖至此处->I:CURRENT,MANIFEST-000001读取成功!'), ['I:CURRENT,MANIFEST-000001读取成功!']);
      expect(NeteaseSaves.splitPrompts('请选择运行方式0/1/2:请将文件/文件夹拖至此处->-----------扫描文件:加密方式-------------'), ['扫描文件:加密方式']);
      expect(NeteaseSaves.parseKey('I:存档秘钥: 0123456789abcdef'), '0123456789abcdef');
      const l = NeteaseLine('E:存档未加密!');
      expect(l.isError, isTrue);
      expect(l.message, '存档未加密!');
    });

    test('resolveDb accepts world or db folder', () {
      final tmp = Directory.systemTemp.createTempSync('cml_ne');
      try {
        final db = Directory(p.join(tmp.path, 'db'))..createSync();
        expect(() => NeteaseSaves.resolveDb(tmp.path), throwsA(isA<CmlException>()));
        File(p.join(db.path, 'CURRENT')).writeAsStringSync('MANIFEST-000001\n');
        expect(() => NeteaseSaves.resolveDb(tmp.path), throwsA(isA<CmlException>()));
        File(p.join(db.path, 'MANIFEST-000001')).writeAsBytesSync([0, 1]);
        expect(NeteaseSaves.resolveDb(tmp.path), db.path);
        expect(NeteaseSaves.resolveDb(db.path), db.path);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('real executables', () {
    final btExe = p.join(_repo, 'tools', 'bedrocktool', 'out', 'bedrocktool.exe');
    final neExe = p.join(_repo, 'tools', 'netease', 'NeMcDecrypter.exe');

    test('bedrocktool help / describe', () async {
      final tmp = Directory.systemTemp.createTempSync('cml_bt');
      try {
        final bt = BedrockTool(exe: btExe, workDir: tmp.path);
        final cmds = await bt.commandList();
        expect(cmds.keys, containsAll(['worlds', 'skins', 'capture', 'chat-log', 'list-realms', 'realm-address', 'merge', 'render']));
        final worlds = await bt.describe('worlds');
        expect(worlds.flag('void')!.defaultBool, isTrue);
        expect(worlds.flag('save-inventories'), isNotNull);
        expect(worlds.flag('address')!.type, BtFlagType.address);
        // keep the hardcoded table honest
        for (final c in BtCommands.all) {
          final live = await bt.describe(c.name);
          for (final f in c.flags) {
            expect(live.flag(f.name), isNotNull, reason: '${c.name} -${f.name}');
            expect(live.flag(f.name)!.type == BtFlagType.boolean, f.type == BtFlagType.boolean, reason: '${c.name} -${f.name}');
          }
        }
        final outs = await bt.outputs();
        expect(outs.map((o) => o.kind), contains('log')); // bedrocktool.log
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }, skip: File(btExe).existsSync() ? false : 'run tools/bedrocktool/build.ps1 first');

    test('bedrocktool streamed run with events', () async {
      final tmp = Directory.systemTemp.createTempSync('cml_bt');
      try {
        final bt = BedrockTool(exe: btExe, workDir: tmp.path);
        final run = await bt.start('help');
        final events = await run.events.toList();
        expect(events.whereType<BtLine>().any((l) => l.text.contains('worlds')), isTrue);
        expect(events.last, isA<BtExit>());
        expect((events.last as BtExit).code, 0);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }, skip: File(btExe).existsSync() ? false : 'run tools/bedrocktool/build.ps1 first');

    test('NeMcDecrypter status on a fake unencrypted world (Chinese path)', () async {
      final tmp = Directory.systemTemp.createTempSync('cml_ne');
      try {
        final world = Directory(p.join(tmp.path, '测试 世界'))..createSync();
        final db = Directory(p.join(world.path, 'db'))..createSync();
        File(p.join(db.path, 'CURRENT')).writeAsStringSync('MANIFEST-000001\n');
        File(p.join(db.path, 'MANIFEST-000001')).writeAsBytesSync([0, 1]);
        final ne = NeteaseSaves(exe: neExe);
        final status = await ne.run(NeteaseAction.status, world.path);
        expect(status.plain, 2, reason: status.lines.map((l) => l.text).join('\n'));
        expect(status.encrypted, 0);
        expect(status.lines.any((l) => l.text.contains('搜索到0个文件被加密')), isTrue);

        final dec = await ne.run(NeteaseAction.decrypt, world.path, backupFirst: false);
        expect(dec.worldPlain, isTrue, reason: dec.lines.map((l) => l.text).join('\n'));
        expect(dec.lines.any((l) => l.text.contains('存档未加密')), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }, skip: File(neExe).existsSync() && Platform.isWindows ? false : 'NeMcDecrypter.exe not found', timeout: const Timeout(Duration(minutes: 2)));
  });
}
