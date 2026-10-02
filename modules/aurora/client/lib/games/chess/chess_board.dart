import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'shell.dart';

const _glyphs = ['', '♟', '♞', '♝', '♜', '♛', '♚']; // filled glyphs
const _pieceNames = ['', '兵', '马', '象', '车', '后', '王'];

/// One chess piece drawn from a Unicode glyph: filled body + dark outline.
class ChessPieceGlyph extends StatelessWidget {
  final int piece; // signed
  final double size;
  const ChessPieceGlyph(this.piece, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final white = piece > 0;
    final g = '${_glyphs[piece.abs()]}︎';
    final base = TextStyle(fontSize: size, height: 1.0, fontFamilyFallback: const ['Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans']);
    return Stack(alignment: Alignment.center, children: [
      // shadow
      Transform.translate(
        offset: Offset(size * 0.03, size * 0.05),
        child: Text(g, style: base.copyWith(color: Colors.black.withValues(alpha: 0.35))),
      ),
      Text(g, style: base.copyWith(color: white ? const Color(0xFFFFFBF0) : const Color(0xFF26221E))),
      Text(g,
          style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * 0.035
                ..color = white ? const Color(0xFF2B2520) : const Color(0xFF9A8F80))),
    ]);
  }
}

class ChessBoard extends StatefulWidget {
  final GameContext g;
  const ChessBoard(this.g, {super.key});
  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  int? sel;
  int _plies = -1;

  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final whiteSeat = v['whiteSeat'] as int;
    final turn = v['turn'] as int;
    final moves = (v['moves'] as List).cast<int>();
    final last = (v['last'] as List).cast<int>();
    final check = v['check'] as int?;
    final san = (v['san'] as List).cast<String>();
    final captured = (v['captured'] as List).map((e) => (e as List).cast<int>()).toList();
    final winner = v['winner'] as int;
    final reason = v['reason'] as String;
    final plies = v['plies'] as int;
    if (plies != _plies) {
      _plies = plies;
      sel = null;
    }
    final me = g.seat;
    final myColor = me == whiteSeat ? 1 : (me == 1 - whiteSeat ? -1 : 1);
    final flipped = myColor < 0;
    final myTurn = !g.over && turn == me;
    final bottomSeat = me >= 0 && me < 2 ? me : whiteSeat;
    final topSeat = 1 - bottomSeat;

    String colorName(int s) => s == whiteSeat ? '白方' : '黑方';
    String status;
    if (winner == -1) {
      status = '和棋：$reason';
    } else if (winner >= 0) {
      status = '${g.name(winner)} 获胜（$reason）';
    } else if (myTurn) {
      status = check != null ? '你被将军了！请应将' : '轮到你走棋（${colorName(me)}）';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）${check != null ? ' · 将军' : ''}';
    }
    final offer = v['drawOffer'] as int? ?? -1;
    if (!g.over && offer >= 0 && offer != me) status = '${g.name(offer)} 提议和棋';

    Widget capturedRow(int color) {
      // pieces captured BY [color] → show opponent's pieces
      final list = List<int>.of(captured[color == 1 ? 0 : 1])..sort((a, b) => b - a);
      return Wrap(children: [for (final t in list) ChessPieceGlyph(color == 1 ? -t : t, size: 14)]);
    }

    Widget tagFor(int s) {
      final c = s == whiteSeat ? 1 : -1;
      return g.tag(s,
          active: !g.over && turn == s,
          sub: colorName(s),
          trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: capturedRow(c)));
    }

    final targets = <int>{
      if (sel != null)
        for (final m in moves)
          if (m ~/ 64 == sel) m % 64
    };

    Future<void> tap(int sqr) async {
      if (!myTurn) return;
      final p = board[sqr];
      final mine = p != 0 && (p > 0) == (myColor > 0);
      if (sel != null && targets.contains(sqr)) {
        final from = sel!;
        final isPromo = board[from].abs() == 1 && (sqr ~/ 8 == 7 || sqr ~/ 8 == 0);
        var promo = 0;
        if (isPromo) {
          final r = await _askPromotion(context, myColor);
          if (r == null) return;
          promo = r;
        }
        setState(() => sel = null);
        g.act({'from': from, 'to': sqr, 'promo': promo});
        return;
      }
      setState(() => sel = mine && sel != sqr ? sqr : null);
    }

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / 8;
      final cs = Theme.of(context).colorScheme;
      const light = Color(0xFFF0D9B5), dark = Color(0xFFB58863);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          for (var vr = 0; vr < 8; vr++)
            for (var vc = 0; vc < 8; vc++)
              () {
                final rank = flipped ? vr : 7 - vr;
                final file = flipped ? 7 - vc : vc;
                final s = rank * 8 + file;
                final isLight = (rank + file) % 2 == 1;
                final p = board[s];
                Color bg = isLight ? light : dark;
                if (last.contains(s)) bg = Color.lerp(bg, const Color(0xFFE8D84A), 0.55)!;
                if (sel == s) bg = Color.lerp(bg, const Color(0xFF6AA84F), 0.6)!;
                final coordColor = isLight ? dark : light;
                return Positioned(
                  left: vc * cell,
                  top: vr * cell,
                  width: cell,
                  height: cell,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tap(s),
                    child: Container(
                      color: bg,
                      child: Stack(children: [
                        if (check == s)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(colors: [Colors.red.withValues(alpha: 0.9), Colors.red.withValues(alpha: 0)]),
                              ),
                            ),
                          ),
                        if (vc == 0)
                          Positioned(
                            left: 2,
                            top: 1,
                            child: Text('${rank + 1}', style: TextStyle(fontSize: cell * 0.17, color: coordColor, fontWeight: FontWeight.bold)),
                          ),
                        if (vr == 7)
                          Positioned(
                            right: 2,
                            bottom: 0,
                            child: Text('abcdefgh'[file], style: TextStyle(fontSize: cell * 0.17, color: coordColor, fontWeight: FontWeight.bold)),
                          ),
                        if (p != 0) Center(child: ChessPieceGlyph(p, size: cell * 0.8)),
                        if (targets.contains(s))
                          Center(
                            child: p == 0
                                ? Container(
                                    width: cell * 0.3,
                                    height: cell * 0.3,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.25)),
                                  )
                                : Container(
                                    width: cell * 0.92,
                                    height: cell * 0.92,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black.withValues(alpha: 0.3), width: cell * 0.07)),
                                  ),
                          ),
                      ]),
                    ),
                  ),
                );
              }(),
          if (!myTurn && !g.over && g.seat >= 0)
            Positioned(right: 4, bottom: 4, child: Icon(Icons.hourglass_top, size: cell * 0.3, color: cs.primary.withValues(alpha: 0.7))),
        ]),
      );
    });

    return BoardShell(
      topTag: tagFor(topSeat),
      bottomTag: tagFor(bottomSeat),
      status: status,
      statusHighlight: myTurn || (offer >= 0 && offer != me && !g.over),
      board: boardWidget,
      actions: resignDrawActions(context, g),
      extra: MoveList(san),
      result: g.over ? (winner == -1 ? '和棋 · $reason' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜') ) : null,
    );
  }

  Future<int?> _askPromotion(BuildContext context, int color) {
    return showDialog<int>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('兵升变为'),
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in const [5, 4, 3, 2])
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(ctx, t),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFFF0D9B5), borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.all(4),
                    child: ChessPieceGlyph(t * color, size: 40),
                  ),
                  const SizedBox(height: 4),
                  Text(_pieceNames[t]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
