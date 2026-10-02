import '../../widgets/common.dart';
import 'chain_board.dart';
import 'justone_board.dart';
import 'wavelength_board.dart';

/// Just One / 频率猜心 / 成语接龙 / 飞花令
final Map<String, BoardBuilder> party3Boards = {
  'justone': (g) => JustOneBoard(g),
  'wavelength': (g) => WavelengthBoard(g),
  'chengyu': (g) => ChainBoard(g, feihua: false),
  'feihualing': (g) => ChainBoard(g, feihua: true),
};
