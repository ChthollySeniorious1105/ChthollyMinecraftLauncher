import 'dart:convert';
import 'dart:math';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:aurora_shared/src/simulate.dart';
void main(List<String> args) {
  for (final id in args) {
    final def = findGame(id)!;
    final p = def.defaultOptionsRange().$1 < 4 && def.defaultOptionsRange().$2 >= 4 ? 4 : def.defaultOptionsRange().$1;
    final e = def.create(GameSetup(players: p, options: def.defaultOptions(), names: [for (var i=0;i<p;i++) 'P$i'], bots: List.filled(p, true), hostSeat: 0, rng: Random(3)));
    final h = SimHost(); e.host = h; e.start(); h.runPending();
    for (var i = 0; i < 25 && !e.isOver; i++) { final w = e.waitingFor; if (w.isEmpty) { h.runPending(); continue; } final a = e.bot(w.first); if (a==null) break; e.handle(w.first, a); h.runPending(); }
    var s = jsonEncode(e.view(1));
    print('=== $id p=$p (seat1): ${s.length > 1500 ? s.substring(0,1500) : s}');
    s = jsonEncode(e.view(-1));
    print('--- spectator: ${s.length > 700 ? s.substring(0,700) : s}');
  }
}
