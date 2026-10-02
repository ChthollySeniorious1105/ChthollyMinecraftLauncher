import 'dart:io';
import 'package:cml_core/cml_core.dart';

/// Manual smoke test: installs a vanilla version + Fabric into a temp dir and builds the launch command.
Future<void> main(List<String> args) async {
  final mc = args.isNotEmpty ? args[0] : '1.20.1';
  final root = Directory('${Directory.systemTemp.path}/cml-smoke').path;
  final http = Http();
  final dl = Downloader(http, source: DownloadSource.auto);
  final gi = GameInstaller(http, dl);
  final dir = GameDir(root);
  final sw = Stopwatch()..start();
  final m = await gi.manifest();
  print('manifest: ${m.versions.length} versions, latest ${m.latestRelease} (${sw.elapsedMilliseconds}ms)');
  await gi.installVanillaJson(dir, m.find(mc)!);
  final t = Task<void>('install');
  t.changes.listen((x) => stdout.write('\r${(x.progress * 100).toStringAsFixed(0)}% ${x.detail}        '));
  await t.run((t) => gi.completeFiles(dir, mc, task: t));
  print('\nvanilla done in ${sw.elapsedMilliseconds}ms');
  final li = LoaderInstaller(http, dl);
  final fab = await li.list(ModLoader.fabric, mc);
  print('fabric versions: ${fab.length}, latest ${fab.first.version}');
  final id = await li.install(dir, fab.first, javaPath: 'java');
  await gi.completeFiles(dir, id);
  final v = await dir.load(id);
  print('$id loaders=${v.loaders} java=${v.requiredJava} libs=${v.libraries.length}');
  final jm = JavaManager('$root/java.json');
  await jm.scan();
  final j = jm.pick(v.requiredJava)!;
  print('java: ${j.label}');
  final cmd = await Launcher.build(dir, id, const LaunchIdentity(name: 'Tester', uuid: '00000000000000000000000000000000', accessToken: 'TOKEN'),
      LaunchOptions(javaPath: j.path, maxMemoryMb: 2048));
  print(cmd.masked('TOKEN').substring(0, 400));
  // run with an invalid token: the game should still reach the main menu loader stage before auth matters
  final gp = await Launcher.start(cmd, onLog: (l) {});
  await gp.ready;
  print('game process ready=${gp.tail.any((l) => l.contains('Setting user') || l.contains('LWJGL'))} lines=${gp.tail.length}');
  await Future<void>.delayed(const Duration(seconds: 8));
  gp.kill();
  print(gp.tail.where((l) => l.contains('ERROR') || l.contains('Exception')).take(5).join('\n'));
  http.close();
}
