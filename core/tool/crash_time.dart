import 'dart:io';
import 'package:cml_core/cml_core.dart';

Future<void> main(List<String> a) async {
  final sw = Stopwatch()..start();
  final t = const SystemEncoding().decode(await File(a[0]).readAsBytes());
  final r1 = CrashAnalyzer.analyzeText(t);
  print('text only: ${sw.elapsedMilliseconds} ms, ${r1.findings.length} findings');
  sw.reset();
  final mods = await CrashAnalyzer.modPackages(a[1]);
  print('modPackages: ${sw.elapsedMilliseconds} ms, ${mods.length} jars, ${mods.fold<int>(0, (x, m) => x + m.packages.length)} packages');
  sw.reset();
  final r = CrashAnalyzer.analyzeText(t, mods: mods);
  print('with mods: ${sw.elapsedMilliseconds} ms');
  for (final f in r.findings) {
    print('[${f.confidence.name}] ${f.id} ${f.title} mods=${f.mods}\n   ${f.detail}');
  }
}
