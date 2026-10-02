import 'package:aurora_shared/games/monopoly/board_data.dart';

import '../../widgets/common.dart';

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
List<int> _ints(Object? v) => v is List ? [for (final e in v) _i(e)] : <int>[];
Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

class MPlayer {
  final int cash, pos, jailTurns, cards, worth;
  final bool jail, bankrupt;
  MPlayer(Map<String, dynamic> m)
      : cash = _i(m['cash']),
        pos = _i(m['pos']),
        jailTurns = _i(m['jailTurns']),
        cards = _i(m['cards']),
        worth = _i(m['worth']),
        jail = m['jail'] == true,
        bankrupt = m['bankrupt'] == true;
}

/// Typed wrapper over the monopoly engine view.
class MView {
  final GameContext g;
  final Map<String, dynamic> v;
  MView(this.g) : v = g.view;

  String get phase => '${v['phase'] ?? 'roll'}';
  int get turn => _i(v['turn']);
  int get round => _i(v['round'], 1);
  int get roundLimit => _i(v['roundLimit'], 200);
  bool get timed => v['timed'] == true;
  List<int> get dice => _ints(v['dice']);
  int get rolls => _i(v['rolls']);
  bool get again => v['again'] == true;
  int get buySq => _i(v['buySq'], -1);
  List<int> get owner {
    final o = _ints(v['owner']);
    return o.length == 40 ? o : List.filled(40, -1);
  }

  List<int> get houses {
    final o = _ints(v['houses']);
    return o.length == 40 ? o : List.filled(40, 0);
  }

  List<bool> get mortgaged {
    final m = v['mortgaged'];
    if (m is List && m.length == 40) return [for (final e in m) e == true];
    return List.filled(40, false);
  }

  int get housesLeft => _i(v['housesLeft']);
  int get hotelsLeft => _i(v['hotelsLeft']);
  bool get potOn => v['potOn'] == true;
  int get pot => _i(v['pot']);
  bool get auctionOn => v['auctionOn'] != false;
  List<MPlayer> get players => [for (final p in (v['players'] as List? ?? const [])) MPlayer(_map(p)!)];
  Map<String, dynamic>? get auction => _map(v['auction']);
  Map<String, dynamic>? get debt => _map(v['debt']);
  Map<String, dynamic>? get trade => _map(v['trade']);
  int get tradesLeft => _i(v['tradesLeft']);
  Map<String, dynamic>? get card => _map(v['card']);
  List<String> get events => [for (final e in (v['events'] as List? ?? const [])) '$e'];
  int get winner => _i(v['winner'], -1);
  List<Map<String, dynamic>> get result => [for (final r in (v['result'] as List? ?? const [])) _map(r)!];
  List<int> legal(String k) => _ints(_map(v['legal'])?[k]);

  int get me => g.seat;
  bool get isOver => g.over || phase == 'over';
  bool get myTurn => !isOver && me >= 0 && turn == me;
  MPlayer? get mine => me >= 0 && me < players.length ? players[me] : null;

  bool get iAmDebtor => phase == 'debt' && debt != null && _i(debt!['from']) == me;
  bool get canManage =>
      !isOver && me >= 0 && (iAmDebtor || (myTurn && (phase == 'roll' || phase == 'end' || phase == 'buy')));

  /// Square to emphasise on the board.
  int get focus {
    if (phase == 'buy') return buySq;
    final a = auction;
    if (a != null) return _i(a['sq'], -1);
    final ps = players;
    return turn < ps.length ? ps[turn].pos : -1;
  }

  String status() {
    if (isOver) {
      final w = winner;
      return w >= 0 ? '游戏结束：${g.name(w)} 获胜！' : '游戏结束';
    }
    final t = g.name(turn);
    switch (phase) {
      case 'buy':
        final s = mBoard[buySq.clamp(0, 39)];
        return myTurn ? '是否购买 ${s.name}（¥${s.price}）？' : '$t 正在考虑购买 ${s.name}';
      case 'auction':
        final a = auction!;
        final s = mBoard[_i(a['sq']).clamp(0, 39)];
        final waiting = _ints(a['waiting']);
        if (waiting.contains(me)) return '拍卖 ${s.name}：请出价（当前 ¥${_i(a['high'])}）';
        return '拍卖 ${s.name} 进行中';
      case 'debt':
        final d = debt!;
        final from = _i(d['from']);
        if (from == me) return '你需要支付 ¥${_i(d['amount'])}（${d['why']}）';
        return '${g.name(from)} 正在筹款还债';
      case 'trade':
        final tr = trade!;
        final to = _i(tr['to']);
        if (to == me) return '${g.name(_i(tr['from']))} 向你提出交易';
        return '等待 ${g.name(to)} 回应交易';
      case 'end':
        return myTurn ? '你的回合：可以管理地产，然后结束回合' : '$t 的回合';
      default:
        if (myTurn) {
          if (mine?.jail == true) return '你在监狱中：掷对子出狱，或付款/用卡';
          return again ? '掷出对子！再掷一次' : '轮到你掷骰子';
        }
        return '等待 $t 掷骰子';
    }
  }
}

String mSqKind(Sq s) => switch (s.type) {
      SqType.street => '${mGroupNames[s.group]}街道',
      SqType.station => '车站',
      SqType.utility => '公用事业',
      SqType.tax => '税务',
      SqType.chance => '机会',
      SqType.chest => '命运',
      _ => '角落',
    };
