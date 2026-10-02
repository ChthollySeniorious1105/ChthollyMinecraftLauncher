import 'package:cml_core/cml_core.dart';

Future<void> main() async {
  final steam = await Steam.installPath();
  print('steam: $steam');
  if (steam == null) return;
  final sw = Stopwatch()..start();
  final info = await AppInfo.load('$steam/appcache/appinfo.vdf');
  print('appinfo: ${info.apps.length} apps in ${sw.elapsedMilliseconds} ms');
  for (final a in Steam.accounts(steam)) {
    sw.reset();
    final lib = await Steam.library(steam, a, appInfo: info);
    final g = lib.games;
    print('account ${a.accountId} recent=${a.mostRecent}: games=${g.length} hidden=${g.where((x) => x.hidden).length} '
        'visible=${g.where((x) => !x.hidden).length} installed=${g.where((x) => x.installed).length} '
        'covers=${g.where((x) => x.coverPath != null).length} collections=${lib.collections.map((c) => '${c.apps.length}').join('/')} '
        'family=${lib.familyName != null} warnings=${lib.warnings} (${sw.elapsedMilliseconds} ms)');
  }
}
