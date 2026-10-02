import 'dart:io';
import 'package:cml_core/cml_core.dart';

Future<void> main(List<String> args) async {
  final files = <File>[];
  for (final root in args) {
    await for (final e in Directory(root).list(recursive: true, followLinks: false).handleError((_) {})) {
      final n = e.path.toLowerCase();
      if (e is File && ((n.contains('crash-reports') && n.endsWith('.txt')) || (n.contains('hs_err_pid') && n.endsWith('.log')))) files.add(e);
    }
  }
  var hit = 0;
  for (final f in files) {
    String text;
    try {
      text = await f.readAsString();
      if (text.isEmpty) throw const FormatException();
    } catch (_) {
      text = const SystemEncoding().decode(await f.readAsBytes());
    }
    // versions/<id>/crash-reports/x.txt -> versions/<id>/mods
    final modsDir = '${f.parent.parent.path}${Platform.pathSeparator}mods';
    final r = CrashAnalyzer.analyzeText(text, mods: await CrashAnalyzer.modPackages(modsDir));
    final p = r.primary;
    if (p != null) hit++;
    final name = f.path.split(RegExp(r'[\/]')).reversed.take(3).toList().reversed.join('/');
    print('${p == null ? '  ?' : 'OK '} $name');
    print('     desc: ${r.description ?? '-'}');
    for (final x in r.findings.take(3)) {
      print('     [${x.confidence.name}] ${x.title}${x.mods.isEmpty ? '' : ' mods=${x.mods}'} — ${x.detail}');
    }
  }
  print('analyzed ${files.length}, with findings $hit');
}
