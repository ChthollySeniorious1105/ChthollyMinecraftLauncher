part of 'engine.dart';

extension RiichiWin on RiichiGame {
  /// Counts of the non-wild tiles.
  List<int> realCounts(Iterable<int> ids) {
    final c = List<int>.filled(34, 0);
    for (final id in ids) {
      if (!isWild(id)) c[kindOf(id)]++;
    }
    return c;
  }

  int wildCount(Iterable<int> ids) => ids.where(isWild).length;

  /// Is a 3n+2 set of ids (plus [melds] declared melds) a complete shape?
  bool isAgariIds(List<int> ids, int melds) {
    final c = realCounts(ids);
    final w = wildCount(ids);
    if (w == 0) return shanten(c, melds) == -1;
    return shanten(c, melds) <= w - 1;
  }

  /// Winning kinds for a 3n+1 set of ids.
  List<int> waitsOfIds(List<int> ids, int melds) {
    final c = realCounts(ids);
    final w = wildCount(ids);
    if (w == 0) return waitsOf(c, melds, allowed: ts.kindInGame);
    final out = <int>[];
    for (var k = 0; k < 34; k++) {
      if (!ts.kindInGame(k)) continue;
      c[k]++;
      if (shanten(c, melds) <= w - 1) out.add(k);
      c[k]--;
    }
    return out;
  }

  /// Waits of seat [s] (hand must be 3n+1), cached by hand content.
  List<int> waitsFor(int s) {
    final p = ps[s];
    final key = '$handSerial|${p.hand.join(",")}|${p.melds.length}';
    final c = _waitCache[s];
    if (c != null && c.$1 == key) return c.$2;
    final w = waitsOfIds(p.hand, p.melds.length);
    _waitCache[s] = (key, w);
    return w;
  }

  bool isFuriten(int s, List<int> waits) {
    final p = ps[s];
    if (p.tempFuriten || p.riichiFuriten) return true;
    for (final d in p.river) {
      if ((d.dark || d.locked)) continue;
      if (waits.contains(kindOf(d.id))) return true;
    }
    return false;
  }

  List<int> _doraKinds(List<int> inds) => [for (var i = 0; i < doraShown; i++) doraFromIndicator(kindOf(inds[i]), sanma: rules.sanma)];

  int _countDora(Iterable<int> kinds, List<int> doraKinds) {
    var n = 0;
    for (final k in kinds) {
      for (final d in doraKinds) {
        if (d == k) n++;
      }
    }
    return n;
  }

  /// Evaluate seat [s] winning on tile [id] (for tsumo the tile is already in hand).
  /// Returns null if not a legal win (shape or no yaku).
  HandValue? evalWin(int s, int id, {bool tsumo = false, bool chankan = false, bool houtei = false}) {
    final p = ps[s];
    final hand = tsumo ? List<int>.of(p.hand) : [...p.hand, id];
    if (!isAgariIds(hand, p.melds.length)) return null;
    final meldGroups = [for (final m in p.melds) m.toGroup()];
    final allIds = [...hand, for (final m in p.melds) ...m.tiles];
    final realIds = allIds.where((i) => !isWild(i)).toList();
    final dk = _doraKinds(indicators);
    final uk = _doraKinds(uraIndicators);
    final kitaDora = _countDora(p.kita.map(kindOf), dk);
    final uraKita = _countDora(p.kita.map(kindOf), uk);
    final baseDora = _countDora(realIds.map(kindOf), dk) + kitaDora;
    final ura = _countDora(realIds.map(kindOf), uk) + uraKita;
    final aka = realIds.where(ts.isRed).length + p.kita.where(ts.isRed).length;
    final noCalls = uninterrupted && p.melds.isEmpty;
    final first = firstTurn[s] && noCalls;
    final winKind = kindOf(id);
    final wilds = hand.where(isWild).toList();
    final base = realCounts(hand);

    WinContext ctx(List<int> counts, int extraDora) => WinContext(
          counts: counts,
          winKind: winKind,
          melds: meldGroups,
          tsumo: tsumo,
          riichi: p.riichi,
          doubleRiichi: p.doubleRiichi,
          ippatsu: p.ippatsu,
          rinshan: tsumo && rinshanFlag,
          chankan: chankan,
          haitei: tsumo && live.isEmpty && !rinshanFlag,
          houtei: !tsumo && houtei,
          tenhou: tsumo && first && s == dealer && !rinshanFlag,
          chiihou: tsumo && first && s != dealer && !rinshanFlag,
          seatWind: seatWindKind(s),
          roundWind: roundWindKind,
          kuitan: rules.kuitan,
          dora: baseDora + extraDora,
          ura: ura,
          aka: aka,
          kita: p.kita.length,
        );

    if (wilds.isEmpty) return evaluateHand(ctx(base, 0));
    // Wildcards: try every substitution, keep the most valuable result.
    HandValue? best;
    void rec(int i, List<int> counts, int extra) {
      if (i == wilds.length) {
        if (shanten(counts, p.melds.length) != -1) return;
        final v = evaluateHand(ctx(List.of(counts), extra));
        if (v != null && (best == null || compareValue(v, best!) > 0)) best = v;
        return;
      }
      for (var k = 0; k < 34; k++) {
        if (!ts.kindInGame(k)) continue;
        counts[k]++;
        rec(i + 1, counts, extra);
        counts[k]--;
      }
    }

    rec(0, base, 0);
    return best;
  }

  // ------------------------------------------------------------------ wins
  Map<String, dynamic> _winRecord(int s, HandValue v, bool tsumo, int from, int winTile) {
    final p = ps[s];
    return {
      'seat': s,
      'from': from,
      'tsumo': tsumo,
      'hand': [for (final id in p.hand) if (tsumo ? id != winTile : true) tileCode(id)],
      'win': tileCode(winTile),
      'melds': [for (final m in p.melds) meldJson(m)],
      'yaku': [for (final y in v.yaku) y.toJson()],
      'han': v.han,
      'fu': v.fu,
      'yakuman': v.yakuman,
      'limit': v.limitName,
      'dora': [for (var i = 0; i < doraShown; i++) tileCode(indicators[i])],
      'ura': p.riichi ? [for (var i = 0; i < doraShown; i++) tileCode(uraIndicators[i])] : <String>[],
      'kita': p.kita.length,
    };
  }

  void _pay(int from, int to, int amount) {
    ps[from].score -= amount;
    ps[to].score += amount;
    handDelta[from] -= amount;
    handDelta[to] += amount;
  }

  void _collectSticks(int s) {
    if (kyoutaku > 0) {
      ps[s].score += kyoutaku * 1000;
      handDelta[s] += kyoutaku * 1000;
      kyoutaku = 0;
    }
  }

  /// Base points of the 包牌 yakuman contained in [v] for winner [s] (0 = none).
  int _paoBase(int s, HandValue v) {
    final p = ps[s];
    if (p.pao < 0 || v.yakuman == 0) return 0;
    for (final y in v.yaku) {
      if (y.name == p.paoYaku) return 8000 * y.han;
    }
    return 0;
  }

  void _tsumo(int s) {
    final v = evalWin(s, drawnId, tsumo: true)!;
    final dealerWin = s == dealer;
    final base = v.basePoints;
    final paoBase = _paoBase(s, v);
    final liable = ps[s].pao;
    var total = 0;
    if (paoBase > 0) {
      // 包牌: the liable player pays the whole pao yakuman (as a ron) plus all honba;
      // any remaining yakuman is split as a normal tsumo.
      final restBase = base - paoBase;
      final (rdp, rnp) = restBase > 0 ? tsumoPoints(restBase, dealerWin) : (0, 0);
      var payers = 0;
      for (var o = 0; o < n; o++) {
        if (o == s || ps[o].won) continue;
        payers++;
        final amt = restBase > 0 ? (dealerWin ? rnp : (o == dealer ? rdp : rnp)) : 0;
        if (amt > 0) _pay(o, s, amt);
        total += amt;
      }
      final pAmt = ronPoints(paoBase, dealerWin) + honba * rules.honbaTsumo * payers;
      _pay(liable, s, pAmt);
      total += pAmt;
    } else {
      final (dp, np) = tsumoPoints(base, dealerWin);
      for (var o = 0; o < n; o++) {
        if (o == s || ps[o].won) continue; // 自摸损: winners already out don't pay
        final amt = (dealerWin ? np : (o == dealer ? dp : np)) + honba * rules.honbaTsumo;
        _pay(o, s, amt);
        total += amt;
      }
    }
    _collectSticks(s);
    final rec = _winRecord(s, v, true, -1, drawnId)..['points'] = total;
    if (paoBase > 0) rec['pao'] = {'seat': liable, 'yaku': ps[s].paoYaku};
    handWins.add(rec);
    ps[s]
      ..winTile = drawnId
      ..wonTsumo = true;
    host.log('${name(s)} 自摸 ${v.limitName.isEmpty ? "${v.han}番${v.fu}符" : v.limitName} ${pointsLabel(base, dealerWin, true)}');
    lastEvent = {'t': 'tsumo', 'seat': s};
    _afterWins([s], dealerWin, s);
  }

  void _doRons(List<int> rons) {
    final from = discarder;
    final isKan = respKind == 'kakan' || respKind == 'ankan';
    if (respKind == 'discard') {
      final d = ps[from].river.last;
      d.ronned = true;
    }
    if (pendingRiichi == from) pendingRiichi = -1; // riichi tile ronned: no deposit
    _establishRiichi();
    var dealerWon = false;
    for (var i = 0; i < rons.length; i++) {
      final s = rons[i];
      final v = evalWin(s, respTile, chankan: isKan || respKind == 'kakan', houtei: live.isEmpty && respKind == 'discard')!;
      final dw = s == dealer;
      if (dw) dealerWon = true;
      final pts = ronPoints(v.basePoints, dw) + honba * rules.honbaRon;
      final paoBase = _paoBase(s, v);
      final liable = ps[s].pao;
      if (paoBase > 0 && liable != from) {
        // 包牌 on a ron by someone else: the pao yakuman is split half/half.
        final half = ronPoints(paoBase, dw) ~/ 2;
        _pay(liable, s, half);
        _pay(from, s, pts - half);
      } else {
        _pay(from, s, pts);
      }
      if (i == 0) _collectSticks(s);
      final rec = _winRecord(s, v, false, from, respTile)..['points'] = pts;
      if (paoBase > 0) rec['pao'] = {'seat': liable, 'yaku': ps[s].paoYaku};
      handWins.add(rec);
      ps[s].winTile = respTile;
      host.log('${name(s)} 荣和 ${name(from)} ${v.limitName.isEmpty ? "${v.han}番${v.fu}符" : v.limitName} $pts');
    }
    if (respKind == 'kakan') {
      // robbed kan: the pon stays a pon
      final p = ps[from];
      for (final m in p.melds) {
        if (m.type == 'kakan' && m.tiles.contains(respTile)) {
          m.type = 'pon';
          m.tiles.remove(respTile);
        }
      }
    }
    lastEvent = {'t': 'ron', 'seat': rons.first, 'from': from};
    _afterWins(rons, dealerWon, rons.last);
  }

  void _afterWins(List<int> winners, bool dealerWon, int lastWinner) {
    opts = {};
    resp = {};
    if (!rules.bloodbath) {
      _finishHand({
        'type': 'win',
        'wins': handWins,
        'reveal': _revealAll(),
      }, dealerStays: dealerWon, draw: false);
      return;
    }
    for (final s in winners) {
      ps[s].won = true;
    }
    _interrupt();
    final busted = ps.any((p) => p.score < 0);
    if (activeCount <= 1 || busted) {
      _finishHand({'type': 'win', 'wins': handWins, 'reveal': _revealAll()}, dealerStays: false, draw: false);
      return;
    }
    if (live.isEmpty) {
      _exhaustiveDraw();
      return;
    }
    _draw(nextActive(lastWinner));
  }

  /// Hands revealed on the result screen: every winner of this hand.
  Map<String, dynamic> _revealAll() => {
        for (final w in handWins) '${w['seat']}': [for (final id in ps[w['seat'] as int].hand) tileCode(id)]
      };

  void _exhaustiveDraw() {
    opts = {};
    resp = {};
    final tenpai = <int>[];
    final noten = <int>[];
    for (var s = 0; s < n; s++) {
      if (ps[s].won) continue;
      if (waitsFor(s).isNotEmpty) {
        tenpai.add(s);
      } else {
        noten.add(s);
      }
    }
    // 流局满贯: every discard is a terminal/honor and none was called.
    final nagashi = <Map<String, dynamic>>[];
    if (rules.nagashi && !rules.bloodbath) {
      for (final s in nagashiSeats()) {
        final (dp, np) = tsumoPoints(2000, s == dealer);
        var total = 0;
        for (var o = 0; o < n; o++) {
          if (o == s) continue;
          final amt = s == dealer ? np : (o == dealer ? dp : np);
          _pay(o, s, amt);
          total += amt;
        }
        nagashi.add({'seat': s, 'points': total});
        host.log('${name(s)} 流局满贯 $total');
      }
    }
    if (nagashi.isEmpty && tenpai.isNotEmpty && noten.isNotEmpty) {
      if (rules.bloodbath) {
        for (final a in noten) {
          for (final b in tenpai) {
            _pay(a, b, 1000);
          }
        }
      } else {
        final total = rules.notenTotal;
        final payEach = total ~/ noten.length;
        final getEach = total ~/ tenpai.length;
        for (final a in noten) {
          ps[a].score -= payEach;
          handDelta[a] -= payEach;
        }
        for (final b in tenpai) {
          ps[b].score += getEach;
          handDelta[b] += getEach;
        }
      }
    }
    host.log('荒牌流局，听牌：${tenpai.isEmpty ? "无" : tenpai.map(name).join("、")}');
    lastEvent = {'t': 'draw'};
    _finishHand({
      'type': handWins.isNotEmpty ? 'win' : 'draw',
      'wins': handWins,
      'drawName': nagashi.isNotEmpty ? '流局满贯' : '荒牌流局',
      'tenpai': tenpai,
      if (nagashi.isNotEmpty) 'nagashi': nagashi,
      'reveal': {
        for (final s in tenpai) '$s': [for (final id in ps[s].hand) tileCode(id)],
        for (var s = 0; s < n; s++)
          if (ps[s].won) '$s': [for (final id in ps[s].hand) tileCode(id)],
      },
    }, dealerStays: tenpai.contains(dealer), draw: true);
  }

  /// Seats qualifying for 流局满贯 at an exhaustive draw.
  List<int> nagashiSeats() => [
        for (var s = 0; s < n; s++)
          if (ps[s].river.isNotEmpty && ps[s].river.every((d) => !d.called && isYaochu(kindOf(d.id)))) s
      ];

  /// 途中流局: dealer stays, honba +1, riichi sticks stay on the table.
  /// [show] = seats whose hands are revealed (e.g. the 九种九牌 declarer).
  void _abortive(String why, List<int> show) {
    host.log(show.length == 1 && why == '九种九牌' ? '${name(show.first)} 宣告$why，流局' : '$why，流局');
    lastEvent = {'t': 'abort', 'seat': show.isEmpty ? -1 : show.first};
    _finishHand({
      'type': 'draw',
      'wins': handWins,
      'drawName': why,
      'abort': true,
      'tenpai': <int>[],
      'reveal': {
        for (final s in show) '$s': [for (final id in ps[s].hand) tileCode(id)]
      },
    }, dealerStays: true, draw: true, abort: true);
  }

  // ------------------------------------------------------------------ codes
  /// Client tile code. 百搭牌 are 'W' (their own face, not a real tile).
  String tileCode(int id) => isWild(id) ? 'W' : ts.code(id);

  Map<String, dynamic> meldJson(Meld m) => {
        'type': m.type,
        'tiles': [for (final id in m.tiles) tileCode(id)],
        'called': m.calledId >= 0 ? tileCode(m.calledId) : null,
        'from': m.from < 0 ? -1 : m.from,
      };
}
