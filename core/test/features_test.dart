import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cml_core/cml_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cml-feat'));
  tearDown(() async => tmp.delete(recursive: true));

  test('servers.dat round trip', () async {
    final l = ServerList(tmp.path);
    await l.save([SavedServer('我的服务器', 'mc.example.com:25570', acceptTextures: true), SavedServer('本地', 'localhost')]);
    final back = await ServerList(tmp.path).load();
    expect(back.map((s) => s.name), ['我的服务器', '本地']);
    expect(back.first.hostPort, ('mc.example.com', 25570));
    expect(back.first.acceptTextures, isTrue);
    expect(back.last.hostPort, ('localhost', 25565));
    expect(SavedServer('', '[::1]:25566').hostPort, ('::1', 25566));
  });

  test('motd flattening', () {
    expect(ServerPinger.motdText({'text': 'A', 'color': 'red', 'extra': [{'text': 'B', 'bold': true}]}), '§cA§lB');
  });

  test('curseforge fingerprint', () {
    expect(curseforgeFingerprint(Uint8List.fromList(utf8.encode('hello world'))), 2824650221);
    expect(curseforgeFingerprint(Uint8List.fromList(utf8.encode('hello\tworld\r\n'))), 2824650221);
  });

  test('full instance export → import', () async {
    final dir = GameDir(p.join(tmp.path, '.minecraft'));
    await Directory(dir.versionDir('1.20.1')).create(recursive: true);
    await File(dir.versionJson('1.20.1')).writeAsString(jsonEncode({'id': '1.20.1', 'type': 'release', 'mainClass': 'x', 'libraries': []}));
    await File(dir.versionJar('1.20.1')).writeAsBytes([1, 2, 3]);
    await Directory(dir.versionDir('Pack')).create(recursive: true);
    await File(dir.versionJson('Pack')).writeAsString(jsonEncode({'id': 'Pack', 'inheritsFrom': '1.20.1', 'libraries': []}));
    final mods = Directory(p.join(dir.versionDir('Pack'), 'mods'))..createSync();
    File(p.join(mods.path, 'a.jar')).writeAsBytesSync([9, 9]);
    File(p.join(dir.versionDir('Pack'), 'options.txt')).writeAsStringSync('fov:1');

    final scan = await InstanceExporter.scan(dir.versionDir('Pack'), 'Pack');
    expect(scan.map((e) => e.path), containsAll(['mods', 'options.txt']));

    final out = p.join(tmp.path, 'pack.cmlpack');
    final r = await InstanceExporter(ContentApi(Http())).export(
      dir: dir, versionId: 'Pack', gameDir: dir.versionDir('Pack'), include: ['mods', 'options.txt'], format: ExportFormat.full, output: out, name: 'Pack');
    expect(r.bundled, 2);

    final dir2 = GameDir(p.join(tmp.path, 'other'));
    final id = await InstanceExporter.importFull(dir2, out, 'Imported');
    expect(id, 'Imported');
    expect(File(p.join(dir2.versionDir('Imported'), 'mods', 'a.jar')).existsSync(), isTrue);
    expect(File(dir2.versionJson('1.20.1')).existsSync(), isTrue);
    expect((await dir2.load('Imported')).inheritsFrom, '1.20.1');
  });

  test('mrpack export references nothing offline but bundles overrides', () async {
    final dir = GameDir(p.join(tmp.path, '.minecraft'));
    await Directory(dir.versionDir('1.21.1')).create(recursive: true);
    await File(dir.versionJson('1.21.1')).writeAsString(jsonEncode({
      'id': '1.21.1',
      'mainClass': 'x',
      'libraries': [{'name': 'net.fabricmc:fabric-loader:0.16.5'}]
    }));
    File(p.join(dir.versionDir('1.21.1'), 'options.txt')).writeAsStringSync('x');
    final out = p.join(tmp.path, 'p.mrpack');
    // unreachable API → everything bundled as overrides, still a valid index
    final api = ContentApi(Http(timeout: const Duration(milliseconds: 1)));
    await InstanceExporter(api).export(
        dir: dir, versionId: '1.21.1', gameDir: dir.versionDir('1.21.1'), include: ['options.txt'], format: ExportFormat.modrinth, output: out, name: 'T');
    final z = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    final idx = jsonDecode(utf8.decode(z.findFile('modrinth.index.json')!.readBytes()!)) as Map;
    expect(idx['dependencies'], {'minecraft': '1.21.1', 'fabric-loader': '0.16.5'});
    expect(z.findFile('overrides/options.txt'), isNotNull);
  });

  test('logs and screenshots listing', () async {
    final g = tmp.path;
    Directory(p.join(g, 'logs')).createSync();
    File(p.join(g, 'logs', 'latest.log')).writeAsStringSync('[main/INFO]: hi');
    Directory(p.join(g, 'crash-reports')).createSync();
    File(p.join(g, 'crash-reports', 'crash-1.txt')).writeAsStringSync('Description: Ticking entity\njava.lang.OutOfMemoryError');
    File(p.join(g, 'logs', 'old.log.gz')).writeAsBytesSync(gzip.encode(utf8.encode('压缩日志')));
    Directory(p.join(g, 'screenshots')).createSync();
    File(p.join(g, 'screenshots', 'a.png')).writeAsBytesSync([0]);
    final logs = await InstanceFiles.logs(g);
    expect(logs.where((l) => l.crash).length, 1);
    final gz = logs.firstWhere((l) => l.name.endsWith('.gz'));
    expect(await InstanceFiles.read(gz), '压缩日志');
    expect(InstanceFiles.diagnose(await InstanceFiles.read(logs.firstWhere((l) => l.crash))), contains('内存'));
    expect((await InstanceFiles.screenshots(g)).length, 1);
  });
}
