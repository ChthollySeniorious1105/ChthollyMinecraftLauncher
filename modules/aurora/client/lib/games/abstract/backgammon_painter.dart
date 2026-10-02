part of 'backgammon_board.dart';

// 棋盘几何（以单位 u 表示）：宽 15.1u，高 12.2u。
const double _bgW = 15.1, _bgH = 12.2, _fr = 0.3;
const _whiteChecker = Color(0xFFF3EBDD);
const _blackChecker = Color(0xFF2B2320);

class _Geo {
  final double u;
  final bool flipV; // 执黑时上下翻转，使己方内盘在右下
  _Geo(this.u, this.flipV);

  double colX(int k) => (_fr + k + (k >= 6 ? 1 : 0)) * u;
  double get barX => (_fr + 6) * u;
  double get trayX => (_fr + 13 + _fr) * u;
  double get topY => _fr * u;
  double get botY => (_bgH - _fr) * u;
  double get midY => _bgH / 2 * u;

  /// 绝对点位 -> (显示列, 是否在下排)
  (int, bool) place(int idx) {
    final bottomLow = !flipV; // 白方视角下排是 0..11
    if (idx < 12) return (11 - idx, bottomLow);
    return (idx - 12, !bottomLow);
  }

  int idxAt(int k, bool bottom) {
    final low = bottom == !flipV;
    return low ? 11 - k : 12 + k;
  }

  Offset checker(int idx, int i, int count) {
    final (k, bottom) = place(idx);
    final x = colX(k) + u / 2;
    final r = u * 0.47;
    final span = 5 * u - 2 * r;
    final step = count <= 5 ? 2 * r : span / (count - 1);
    final d = r + i * step;
    return Offset(x, bottom ? botY - d : topY + d);
  }
}

class _BgPainter extends CustomPainter {
  final _Geo geo;
  final List<int> board;
  final List<int> bar, off;
  final int me; // 下方的座位（视角）
  final Set<int> sources;
  final int selected;
  final Set<int> targets;
  final Set<int> lastTo;
  final int cube, cubeOwner;
  final bool cubeOn;
  final Color felt;

  _BgPainter({
    required this.geo,
    required this.board,
    required this.bar,
    required this.off,
    required this.me,
    required this.sources,
    required this.selected,
    required this.targets,
    required this.lastTo,
    required this.cube,
    required this.cubeOwner,
    required this.cubeOn,
    required this.felt,
  });

  Color _col(int seat) => seat == 0 ? _whiteChecker : _blackChecker;

  void _checker(Canvas canvas, Offset c, double r, int seat, {bool glow = false}) {
    absStone(canvas, c, r, _col(seat));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = (seat == 0 ? Colors.brown.shade300 : Colors.black).withValues(alpha: 0.7);
    canvas.drawCircle(c, r * 0.7, ring);
    if (glow) {
      canvas.drawCircle(
          c,
          r * 1.02,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.16
            ..color = const Color(0xFFFFD54F));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = geo.u;
    final full = Offset.zero & size;
    // 木框
    canvas.drawRRect(
        RRect.fromRectAndRadius(full, Radius.circular(u * 0.3)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B3E1F), Color(0xFF4A2812), Color(0xFF6B3E1F)],
          ).createShader(full));
    // 两个半区 + 托盘
    final feltPaint = Paint()..color = felt;
    final left = Rect.fromLTRB(_fr * u, geo.topY, geo.barX, geo.botY);
    final right = Rect.fromLTRB(geo.barX + u, geo.topY, geo.trayX - _fr * u, geo.botY);
    for (final r in [left, right]) {
      canvas.drawRect(r, feltPaint);
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.05
            ..color = Colors.black38);
    }
    final tray = Rect.fromLTRB(geo.trayX, geo.topY, geo.trayX + 1.2 * u, geo.botY);
    final trayPaint = Paint()..color = Color.lerp(felt, Colors.black, 0.35)!;
    final trayTop = Rect.fromLTRB(tray.left, tray.top, tray.right, geo.midY - u * 0.3);
    final trayBot = Rect.fromLTRB(tray.left, geo.midY + u * 0.3, tray.right, tray.bottom);
    for (final t in [trayTop, trayBot]) {
      canvas.drawRRect(RRect.fromRectAndRadius(t, Radius.circular(u * 0.12)), trayPaint);
    }
    if (targets.contains(25)) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(trayBot.deflate(u * 0.04), Radius.circular(u * 0.12)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.12
            ..color = const Color(0xFF66BB6A));
    }
    // 三角
    final light = Color.lerp(const Color(0xFFEBD9B4), felt, 0.1)!;
    const dark = Color(0xFFA8392E);
    for (var k = 0; k < 12; k++) {
      for (final bottom in [false, true]) {
        final idx = geo.idxAt(k, bottom);
        final x = geo.colX(k);
        final baseY = bottom ? geo.botY : geo.topY;
        final tipY = bottom ? geo.botY - 4.8 * u : geo.topY + 4.8 * u;
        final path = Path()
          ..moveTo(x + u * 0.04, baseY)
          ..lineTo(x + u - u * 0.04, baseY)
          ..lineTo(x + u / 2, tipY)
          ..close();
        final c = (k + (bottom ? 1 : 0)) % 2 == 0 ? dark : light;
        canvas.drawPath(path, Paint()..color = c);
        if (idx == selected) {
          canvas.drawPath(path, Paint()..color = const Color(0x66FFD54F));
        }
        if (lastTo.contains(idx)) {
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = u * 0.06
                ..color = const Color(0xCC42A5F5));
        }
        // 点号（己方视角 1..24）
        final rel = me == 0 ? idx + 1 : 24 - idx;
        absTextAt(canvas, '$rel', Offset(x + u / 2, bottom ? geo.botY + _fr * u * 0.5 : _fr * u * 0.5), u * 0.24,
            Colors.white70);
      }
    }
    // 中柱
    canvas.drawRect(
        Rect.fromLTRB(geo.barX, geo.topY, geo.barX + u, geo.botY),
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF4A2812), Color(0xFF7A4A26), Color(0xFF4A2812)])
              .createShader(Rect.fromLTRB(geo.barX, 0, geo.barX + u, 1)));
    final r = u * 0.47;
    // 棋子
    for (var idx = 0; idx < 24; idx++) {
      final n = board[idx].abs();
      if (n == 0) continue;
      final seat = board[idx] > 0 ? 0 : 1;
      for (var i = 0; i < n; i++) {
        final c = geo.checker(idx, i, n);
        _checker(canvas, c, r, seat, glow: i == n - 1 && sources.contains(idx) && selected != idx);
        if (i == n - 1 && idx == selected) {
          canvas.drawCircle(
              c,
              r * 1.05,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = r * 0.22
                ..color = const Color(0xFFFF7043));
        }
      }
      if (n > 5) {
        final c = geo.checker(idx, n - 1, n);
        absTextAt(canvas, '$n', c, u * 0.4, seat == 0 ? Colors.black87 : Colors.white, weight: FontWeight.bold);
      }
    }
    // 目标点
    for (final t in targets) {
      if (t >= 24) continue;
      final n = board[t].abs();
      final c = geo.checker(t, n == 0 ? 0 : min(n, 4), n == 0 ? 1 : max(n, 5));
      canvas.drawCircle(c, r * 0.5, Paint()..color = const Color(0xCC66BB6A));
      canvas.drawCircle(
          c,
          r * 0.9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.1
            ..color = const Color(0xFF66BB6A));
    }
    // 中柱棋子：我方在上半（将进入对方内盘），对方在下半
    final bx = geo.barX + u / 2;
    for (final seat in [0, 1]) {
      final n = bar[seat];
      final up = seat == me;
      for (var i = 0; i < n; i++) {
        final d = u * 0.9 + i * min(2 * r, 3.6 * u / max(1, n));
        final c = Offset(bx, up ? geo.midY - d : geo.midY + d);
        _checker(canvas, c, r, seat, glow: up && sources.contains(24) && i == n - 1 && selected != 24);
        if (up && selected == 24 && i == n - 1) {
          canvas.drawCircle(
              c,
              r * 1.05,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = r * 0.22
                ..color = const Color(0xFFFF7043));
        }
      }
    }
    // 已移出：我方在下，对方在上
    for (final seat in [0, 1]) {
      final n = off[seat];
      final mine = seat == me;
      final area = mine ? trayBot : trayTop;
      for (var i = 0; i < n; i++) {
        final h = u * 0.27;
        final y = mine ? area.bottom - u * 0.08 - (i + 1) * h : area.top + u * 0.08 + i * h;
        final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(area.left + u * 0.1, y, area.width - u * 0.2, h * 0.86), Radius.circular(h * 0.3));
        canvas.drawRRect(rr, Paint()..color = _col(seat));
        canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = Colors.black45);
      }
    }
    // 加倍骰
    if (cubeOn) {
      final cs = u * 1.0;
      final cy = cubeOwner == -1 ? geo.midY : (cubeOwner == me ? geo.midY + u * 0.2 : geo.midY - u * 0.2);
      final rect = Rect.fromCenter(center: Offset(_fr * u + u * 0.9, cy), width: cs, height: cs);
      canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(1.5, 2)), Radius.circular(cs * 0.18)),
          Paint()..color = Colors.black38);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cs * 0.18)), Paint()..color = Colors.white);
      final label = cubeOwner == -1 ? '64' : '$cube';
      absTextAt(canvas, label, rect.center, cs * (label.length > 1 ? 0.42 : 0.55),
          cubeOwner == -1 ? Colors.black45 : const Color(0xFF1B5E20),
          weight: FontWeight.w800);
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter o) => true;
}
