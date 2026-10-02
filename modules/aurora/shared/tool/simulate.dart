import 'package:aurora_shared/aurora_shared.dart';
import 'package:aurora_shared/src/simulate.dart';

/// Usage: dart run tool/simulate.dart <gameId|all> [games=20] [verbose]
void main(List<String> args) {
  final id = args.isEmpty ? 'all' : args[0];
  final n = args.length > 1 ? int.parse(args[1]) : 20;
  final defs = id == 'all' ? gameRegistry : [findGame(id)!];
  runSims(defs, n: n, verbose: args.contains('verbose'));
}
