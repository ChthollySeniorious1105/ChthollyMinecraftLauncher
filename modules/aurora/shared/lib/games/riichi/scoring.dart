/// Point calculation: base points -> payments.
library;

int _roundUp100(int v) => (v + 99) ~/ 100 * 100;

/// Ron payment (paid entirely by the discarder), excluding honba.
int ronPoints(int base, bool dealer) => _roundUp100(base * (dealer ? 6 : 4));

/// Tsumo payments excluding honba: (dealerPays, nonDealerPays).
/// When the winner is the dealer every other player pays [nonDealerPays]
/// (dealerPays is then meaningless and equals the same value).
(int, int) tsumoPoints(int base, bool dealer) {
  if (dealer) {
    final each = _roundUp100(base * 2);
    return (each, each);
  }
  return (_roundUp100(base * 2), _roundUp100(base));
}

/// Human-readable score string, e.g. "1000/2000" or "8000".
String pointsLabel(int base, bool dealer, bool tsumo) {
  if (!tsumo) return '${ronPoints(base, dealer)}';
  final (d, n) = tsumoPoints(base, dealer);
  return dealer ? '$n∀' : '$n/$d';
}
