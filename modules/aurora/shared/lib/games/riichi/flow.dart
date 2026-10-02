part of 'engine.dart';

extension RiichiFlow on RiichiGame {
  // ------------------------------------------------------------------ 换三张
  void _handleExchange(int seat, Map<String, dynamic> a) {
    if (exchSel.containsKey(seat)) throw GameError('你已经选好了');
    final ids = asIntList(a['tiles']).toSet().toList();
    if (ids.length != 3) throw GameError('请选择 3 张牌');
    final p = ps[seat];
    for (final id in ids) {
      if (!p.hand.contains(id)) throw GameError('手里没有这张牌');
      if (isWild(id)) throw GameError('百搭牌不能交换');
    }
    exchSel[seat] = ids;
    if (exchSel.length < n) return;
    for (var s = 0; s < n; s++) {
      ps[s].hand.removeWhere(exchSel[s]!.contains);
    }
    for (var s = 0; s < n; s++) {
      final target = (s + (exchDir == -1 ? n - 1 : exchDir)) % n;
      ps[target].hand.addAll(exchSel[s]!);
      exchGot[target] = exchSel[s]!;
    }
    for (final p in ps) {
      _sortHand(p);
    }
    host.log('换三张完成（${exchDirName(exchDir)}）');
    _beginPlay();
  }

  static String exchDirName(int d) => d == 1 ? '交给下家' : (d == -1 ? '交给上家' : '交给对家');

  // ------------------------------------------------------------------ turn actions
  void _handleTurn(int s, String t, Map<String, dynamic> a) {
    final p = ps[s];
    final ta = turnActions(s);
    switch (t) {
      case 'discard':
        final id = asInt(a['tile']);
        final riichi = asBool(a['riichi']);
        final dark = asBool(a['dark']);
        if (!p.hand.contains(id)) throw GameError('手里没有这张牌');
        if (isWild(id)) throw GameError('百搭牌不能打出');
        if (p.riichi && id != drawnId) throw GameError('立直后只能摸切');
        if (p.forbidden.contains(kindOf(id))) throw GameError('食替：不能打出与鸣牌相关的牌');
        if (riichi && !(ta['riichi'] as List).contains(id)) throw GameError('打这张牌不能立直');
        if (dark) {
          if (!rules.dark) throw GameError('本模式不能暗牌');
          if (p.score < (riichi ? 2000 : 1000)) throw GameError('点数不足，不能暗牌');
        }
        _discard(s, id, riichi: riichi, dark: dark);
      case 'tsumo':
        if (ta['tsumo'] != true) throw GameError('不能自摸');
        _tsumo(s);
      case 'ankan':
        final k = asInt(a['kind']);
        if (!(ta['ankan'] as List).contains(k)) throw GameError('不能暗杠');
        _ankan(s, k);
      case 'kakan':
        final k = asInt(a['kind']);
        if (!(ta['kakan'] as List).contains(k)) throw GameError('不能加杠');
        _kakan(s, k);
      case 'kita':
        if (ta['kita'] != true) throw GameError('不能拔北');
        _kita(s);
      case 'kyuushu':
        if (ta['kyuushu'] != true) throw GameError('不满足九种九牌');
        _abortive('九种九牌', [s]);
      default:
        throw GameError('未知操作');
    }
  }

  /// Legal self actions in the current turn (cached per state).
  Map<String, dynamic> turnActions(int s) {
    final p = ps[s];
    final key = '$handSerial|$s|$phase|$drawnId|$rinshanFlag|${p.hand.join(",")}|${p.melds.length}|${live.length}|${p.score}|${p.riichi}|$afterCall';
    if (_taKey == key && _taVal != null) return _taVal!;
    final out = <String, dynamic>{
      'tsumo': false,
      'riichi': <int>[],
      'ankan': <int>[],
      'kakan': <int>[],
      'kita': false,
      'kyuushu': false,
      'dark': false,
    };
    if (phase == 'turn' && s == turn) {
      final canKan = live.isNotEmpty && kanTotal < 4 && !afterCall;
      if (drawnId >= 0 && !afterCall) {
        out['tsumo'] = evalWin(s, drawnId, tsumo: true) != null;
      }
      if (!p.riichi && pendingRiichi < 0 && p.closed && p.score >= 1000 && live.length >= 4 && !afterCall) {
        final ids = <int>[];
        final seen = <int>{};
        for (final id in p.hand) {
          if (isWild(id) || !seen.add(kindOf(id))) continue;
          final rest = List<int>.of(p.hand)..remove(id);
          if (waitsOfIds(rest, p.melds.length).isNotEmpty) {
            for (final j in p.hand) {
              if (kindOf(j) == kindOf(id) && !isWild(j)) ids.add(j);
            }
          }
        }
        out['riichi'] = ids;
      }
      if (canKan) {
        final c = realCounts(p.hand);
        final ank = <int>[];
        for (var k = 0; k < 34; k++) {
          if (c[k] < 4) continue;
          if (p.riichi) {
            if (drawnId < 0 || kindOf(drawnId) != k) continue;
            final before = waitsOfIds(List.of(p.hand)..remove(drawnId), p.melds.length);
            final after = waitsOfIds([for (final id in p.hand) if (kindOf(id) != k || isWild(id)) id], p.melds.length + 1);
            if (before.isEmpty || before.join(',') != after.join(',')) continue;
          }
          ank.add(k);
        }
        out['ankan'] = ank;
        if (!p.riichi) {
          out['kakan'] = [
            for (final m in p.melds)
              if (m.type == 'pon' && c[kindOf(m.tiles.first)] > 0) kindOf(m.tiles.first)
          ];
        }
      }
      if (rules.sanma && live.isNotEmpty && !afterCall) {
        final hasNorth = p.hand.any((id) => kindOf(id) == kNorth && !isWild(id));
        if (hasNorth) {
          if (!p.riichi) {
            out['kita'] = true;
          } else if (drawnId >= 0 && kindOf(drawnId) == kNorth) {
            out['kita'] = true;
          }
        }
      }
      if (firstTurn[s] && uninterrupted && drawnId >= 0 && !rinshanFlag) {
        final c = realCounts(p.hand);
        final kinds = yaochuKinds.where((k) => c[k] > 0).length;
        out['kyuushu'] = kinds >= 9;
      }
      out['dark'] = rules.dark && p.score >= 1000;
    }
    _taKey = key;
    _taVal = out;
    return out;
  }

  void _discard(int s, int id, {bool riichi = false, bool dark = false}) {
    final p = ps[s];
    p.hand.remove(id);
    _sortHand(p);
    if (p.riichi) p.ippatsu = false;
    final d = Discard(id, tsumogiri: id == drawnId, riichi: riichi, dark: dark);
    p.river.add(d);
    if (riichi) {
      pendingRiichi = s;
      pendingDouble = firstTurn[s] && uninterrupted;
    }
    firstTurn[s] = false;
    p.tempFuriten = false;
    p.forbidden = {};
    drawnId = -1;
    rinshanFlag = false;
    afterCall = false;
    discarder = s;
    respTile = id;
    respKind = 'discard';
    lastEvent = {'t': riichi ? 'riichi' : 'discard', 'seat': s};
    if (riichi) host.log('${name(s)} 立直${dark ? "（暗牌）" : ""}');
    if (dark) {
      p.score -= 1000;
      handDelta[s] -= 1000;
      kyoutaku++;
      host.log('${name(s)} 支付 1000 点暗牌打出');
      opts = {};
      resp = {};
      for (var o = 0; o < n; o++) {
        if (o != s && active(o) && ps[o].score >= 2000) opts[o] = {'open': true};
      }
      if (opts.isEmpty) {
        _afterNoCall();
      } else {
        phase = 'anyeOpen';
      }
      return;
    }
    _openResponses();
  }

  // ------------------------------------------------------------------ 暗夜之战
  void _handleAnyeOpen(int seat, String t) {
    if (!opts.containsKey(seat) || resp.containsKey(seat)) throw GameError('现在不需要你操作');
    resp[seat] = {'t': t == 'open' ? 'open' : 'skip'};
    if (resp.length < opts.length) return;
    int? opener;
    for (var i = 1; i < n; i++) {
      final o = (discarder + i) % n;
      if (resp[o]?['t'] == 'open') {
        opener = o;
        break;
      }
    }
    if (opener == null) {
      _afterNoCall();
      return;
    }
    ps[opener].score -= 2000;
    handDelta[opener] -= 2000;
    kyoutaku += 2;
    host.log('${name(opener)} 支付 2000 点开牌');
    if (ps[discarder].score >= 4000) {
      phase = 'anyeLock';
      opts = {};
      resp = {};
    } else {
      _handleAnyeLock(false);
    }
  }

  void _handleAnyeLock(bool lock) {
    final d = ps[discarder].river.last;
    if (lock) {
      if (ps[discarder].score < 4000) throw GameError('点数不足，不能锁定');
      ps[discarder].score -= 4000;
      handDelta[discarder] -= 4000;
      kyoutaku += 4;
      d.locked = true;
      host.log('${name(discarder)} 支付 4000 点锁定暗牌');
      _afterNoCall();
      return;
    }
    d.dark = false;
    host.log('暗牌被翻开：${kindNames[kindOf(d.id)]}');
    _openResponses();
  }

  // ------------------------------------------------------------------ responses to a discard
  void _openResponses() {
    opts = {};
    resp = {};
    final k = kindOf(respTile);
    for (var o = 0; o < n; o++) {
      if (o == discarder || !active(o)) continue;
      final op = <String, dynamic>{};
      final po = ps[o];
      final waits = waitsFor(o);
      if (waits.contains(k)) {
        if (!isFuriten(o, waits) && evalWin(o, respTile, houtei: live.isEmpty) != null) {
          op['ron'] = true;
        } else {
          _markMissed(o);
        }
      }
      if (!po.riichi && live.isNotEmpty) {
        final same = [for (final id in po.hand) if (kindOf(id) == k && !isWild(id)) id];
        if (same.length >= 2) {
          final pons = _distinctPairs(same);
          final ok = pons.where((pair) => _leavesDiscard(po, pair, {k})).toList();
          if (ok.isNotEmpty) op['pon'] = ok;
        }
        if (same.length >= 3 && kanTotal < 4) op['kan'] = true;
        if (!rules.sanma && o == nextActive(discarder) && k < 27) {
          final chis = _chiOptions(po, respTile);
          if (chis.isNotEmpty) op['chi'] = chis;
        }
      }
      if (op.isNotEmpty) opts[o] = op;
    }
    if (opts.isEmpty) {
      _coverPause(_afterNoCall);
    } else {
      phase = 'call';
    }
  }

  /// Nobody can claim: sometimes pause 0.5–1 s anyway (雀魂-style) so timing
  /// doesn't reveal whether anyone could have called.
  void _coverPause(void Function() next) {
    final ms = claimCoverDelayMs(rng);
    if (ms == 0) {
      next();
      return;
    }
    pausedPhase = phase;
    phase = 'pause';
    host.schedule(ms, () {
      if (phase != 'pause') return;
      phase = pausedPhase;
      next();
    });
  }

  List<List<int>> _distinctPairs(List<int> ids) {
    final out = <List<int>>[];
    final seen = <String>{};
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final key = ([ts.code(ids[i]), ts.code(ids[j])]..sort()).join();
        if (seen.add(key)) out.add([ids[i], ids[j]]);
      }
    }
    return out;
  }

  bool _leavesDiscard(PState p, List<int> used, Set<int> forbidden) =>
      p.hand.any((id) => !used.contains(id) && !isWild(id) && !forbidden.contains(kindOf(id)));

  Set<int> _chiForbidden(int calledKind, List<int> used) {
    final ks = used.map(kindOf).toList()..sort();
    final f = {calledKind};
    if (calledKind < ks[0] && ks[1] % 9 < 8) f.add(ks[1] + 1);
    if (calledKind > ks[1] && ks[0] % 9 > 0) f.add(ks[0] - 1);
    return f;
  }

  List<List<int>> _chiOptions(PState p, int tile) {
    final k = kindOf(tile);
    final pos = k % 9;
    final out = <List<int>>[];
    final seen = <String>{};
    for (final (a, b) in [(-2, -1), (-1, 1), (1, 2)]) {
      if (pos + a < 0 || pos + b > 8) continue;
      final ka = k + a, kb = k + b;
      final as = p.hand.where((id) => kindOf(id) == ka && !isWild(id));
      final bs = p.hand.where((id) => kindOf(id) == kb && !isWild(id));
      for (final x in as) {
        for (final y in bs) {
          final key = '${ts.code(x)}${ts.code(y)}';
          if (!seen.add(key)) continue;
          if (_leavesDiscard(p, [x, y], _chiForbidden(k, [x, y]))) out.add([x, y]);
        }
      }
    }
    return out;
  }

  void _markMissed(int o) {
    final p = ps[o];
    if (p.riichi) {
      p.riichiFuriten = true;
    } else {
      p.tempFuriten = true;
    }
  }

  void _handleResponse(int seat, String t, Map<String, dynamic> a) {
    final op = opts[seat];
    if (op == null || resp.containsKey(seat)) throw GameError('现在不需要你操作');
    switch (t) {
      case 'ron':
        if (op['ron'] != true) throw GameError('不能荣和');
        resp[seat] = {'t': 'ron'};
      case 'pon':
      case 'chi':
        final list = (op[t] as List?)?.cast<List<int>>();
        if (list == null) throw GameError(t == 'pon' ? '不能碰' : '不能吃');
        final ids = asIntList(a['tiles']);
        List<int>? pick;
        for (final c in list) {
          if (ids.isEmpty || (ids.length == 2 && ids.toSet().containsAll(c))) {
            pick = c;
            break;
          }
        }
        if (pick == null) throw GameError('无效的鸣牌组合');
        resp[seat] = {'t': t, 'tiles': pick};
      case 'kan':
        if (op['kan'] != true) throw GameError('不能杠');
        resp[seat] = {'t': 'kan'};
      case 'skip':
        resp[seat] = {'t': 'skip'};
      default:
        throw GameError('未知操作');
    }
    // Early resolve: a higher-priority answer can't be beaten by pending ones.
    if (resp.length < opts.length) return;
    _resolveResponses();
  }

  void _resolveResponses() {
    final order = [for (var i = 1; i < n; i++) (discarder + i) % n];
    final rons = [for (final o in order) if (resp[o]?['t'] == 'ron') o];
    for (final o in opts.keys) {
      if (opts[o]!['ron'] == true && resp[o]?['t'] != 'ron') _markMissed(o);
    }
    if (rons.length >= 3 && rules.tripleRonAbort && !rules.bloodbath) {
      if (pendingRiichi == discarder) pendingRiichi = -1; // the riichi tile was ronned
      opts = {};
      _abortive('三家和了', rons);
      return;
    }
    if (rons.isNotEmpty) {
      _doRons(rons);
      return;
    }
    if (respKind == 'discard') {
      _establishRiichi();
      if (_checkAbortAfterDiscard()) return;
    }
    int? caller;
    for (final o in order) {
      final t = resp[o]?['t'];
      if (t == 'pon' || t == 'kan') {
        caller = o;
        break;
      }
    }
    caller ??= [for (final o in order) if (resp[o]?['t'] == 'chi') o].firstOrNull;
    final kind = respKind;
    opts = {};
    if (caller == null) {
      if (kind == 'kakan') {
        _finishKakan();
      } else if (kind == 'ankan' || kind == 'kita') {
        _drawRinshan(turn);
      } else {
        _afterNoCall();
      }
      return;
    }
    _establishRiichi();
    final r = resp[caller]!;
    _call(caller, r['t'] as String, (r['tiles'] as List?)?.cast<int>() ?? const []);
  }

  void _establishRiichi() {
    if (pendingRiichi < 0) return;
    final p = ps[pendingRiichi];
    p.riichi = true;
    p.doubleRiichi = pendingDouble;
    p.ippatsu = true;
    p.score -= 1000;
    handDelta[pendingRiichi] -= 1000;
    p.riichiRiverIndex = p.river.length - 1;
    kyoutaku++;
    pendingRiichi = -1;
  }

  void _afterNoCall() {
    _establishRiichi();
    if (_checkAbortAfterDiscard()) return;
    phase = 'turn';
    if (live.isEmpty) {
      _exhaustiveDraw();
      return;
    }
    _draw(nextActive(discarder));
  }

  /// 四风连打 / 四家立直 / 四杠散了, checked once a discard has passed without ron.
  bool _checkAbortAfterDiscard() {
    if (!rules.abortive || rules.bloodbath) return false;
    final why = abortAfterDiscard();
    if (why == null) return false;
    opts = {};
    resp = {};
    _abortive(why, why == '四家立直' ? [for (var s = 0; s < n; s++) s] : const []);
    return true;
  }

  /// Name of the abortive draw triggered by the current state (after a discard), or null.
  String? abortAfterDiscard() {
    if (!rules.sanma && n == 4) {
      // 四风连打: the first discard of all four players is the same wind, no calls in between.
      if (uninterrupted && ps.every((p) => p.river.length == 1 && p.melds.isEmpty)) {
        final k = kindOf(ps[0].river.first.id);
        if (isWind(k) && ps.every((p) => kindOf(p.river.first.id) == k)) return '四风连打';
      }
      if (ps.every((p) => p.riichi)) return '四家立直';
    }
    if (kanTotal >= 4 && ps.where((p) => p.melds.any((m) => m.isKan)).length >= 2) return '四杠散了';
    return null;
  }

  void _interrupt() {
    uninterrupted = false;
    for (final p in ps) {
      p.ippatsu = false;
    }
  }

  void _call(int s, String t, List<int> ids) {
    final p = ps[s];
    final d = ps[discarder].river.last;
    d.called = true;
    _interrupt();
    final k = kindOf(respTile);
    if (t == 'kan') {
      final used = [for (final id in p.hand) if (kindOf(id) == k && !isWild(id)) id].take(3).toList();
      p.hand.removeWhere(used.contains);
      p.melds.add(Meld('minkan', [...used, respTile], respTile, discarder));
      _checkPao(s, k);
      kanTotal++;
      _revealKanDora();
      host.log('${name(s)} 杠');
      lastEvent = {'t': 'kan', 'seat': s};
      _drawRinshan(s);
      return;
    }
    p.hand.removeWhere(ids.contains);
    p.melds.add(Meld(t, [...ids, respTile], respTile, discarder));
    if (t == 'pon') _checkPao(s, k);
    p.forbidden = t == 'pon' ? {k} : _chiForbidden(k, ids);
    host.log('${name(s)} ${t == 'pon' ? "碰" : "吃"}');
    lastEvent = {'t': t, 'seat': s};
    turn = s;
    drawnId = -1;
    afterCall = true;
    rinshanFlag = false;
    phase = 'turn';
  }

  /// 包牌: the discarder who fed the 3rd dragon / 4th wind set becomes liable.
  void _checkPao(int s, int k) {
    if (!rules.pao || rules.bloodbath) return;
    final p = ps[s];
    final sets = [for (final m in p.melds) if (m.type != 'chi') kindOf(m.tiles.first)];
    if (isDragon(k) && sets.where(isDragon).length == 3) {
      p.pao = discarder;
      p.paoYaku = '大三元';
    } else if (isWind(k) && sets.where(isWind).length == 4) {
      p.pao = discarder;
      p.paoYaku = '大四喜';
    } else {
      return;
    }
    host.log('${name(discarder)} ${p.paoYaku}包牌');
  }

  // ------------------------------------------------------------------ kans / kita
  void _ankan(int s, int k) {
    final p = ps[s];
    final used = [for (final id in p.hand) if (kindOf(id) == k && !isWild(id)) id];
    p.hand.removeWhere(used.contains);
    p.melds.add(Meld('ankan', used, -1, -1));
    kanTotal++;
    _interrupt();
    _revealKanDora();
    host.log('${name(s)} 暗杠');
    lastEvent = {'t': 'kan', 'seat': s};
    // 国士无双 may rob a closed kan.
    discarder = s;
    respTile = used.first;
    respKind = 'ankan';
    opts = {};
    resp = {};
    for (var o = 0; o < n; o++) {
      if (o == s || !active(o)) continue;
      final w = waitsFor(o);
      if (!w.contains(k)) continue;
      final v = evalWin(o, respTile, chankan: true);
      if (v != null && !isFuriten(o, w) && v.yaku.any((y) => y.name.startsWith('国士'))) opts[o] = {'ron': true};
    }
    if (opts.isEmpty) {
      _drawRinshan(s);
    } else {
      phase = 'chankan';
    }
  }

  void _kakan(int s, int k) {
    final p = ps[s];
    final id = p.hand.firstWhere((i) => kindOf(i) == k && !isWild(i));
    p.hand.remove(id);
    final m = p.melds.firstWhere((m) => m.type == 'pon' && kindOf(m.tiles.first) == k);
    m.type = 'kakan';
    m.tiles.add(id);
    uninterrupted = false; // ippatsu of others survives until the kan is completed (抢杠一发)
    host.log('${name(s)} 加杠');
    lastEvent = {'t': 'kan', 'seat': s};
    discarder = s;
    respTile = id;
    respKind = 'kakan';
    opts = {};
    resp = {};
    for (var o = 0; o < n; o++) {
      if (o == s || !active(o)) continue;
      final w = waitsFor(o);
      if (!w.contains(k)) continue;
      if (!isFuriten(o, w) && evalWin(o, id, chankan: true) != null) {
        opts[o] = {'ron': true};
      } else {
        _markMissed(o);
      }
    }
    if (opts.isEmpty) {
      _finishKakan();
    } else {
      phase = 'chankan';
    }
  }

  void _finishKakan() {
    _interrupt();
    kanTotal++;
    _revealKanDora();
    _drawRinshan(discarder);
  }

  void _kita(int s) {
    final p = ps[s];
    final id = p.hand.lastWhere((i) => kindOf(i) == kNorth && !isWild(i));
    p.hand.remove(id);
    p.kita.add(id);
    host.log('${name(s)} 拔北');
    lastEvent = {'t': 'kita', 'seat': s};
    discarder = s;
    respTile = id;
    respKind = 'kita';
    opts = {};
    resp = {};
    for (var o = 0; o < n; o++) {
      if (o == s || !active(o)) continue;
      final w = waitsFor(o);
      if (!w.contains(kNorth)) continue;
      if (!isFuriten(o, w) && evalWin(o, id) != null) {
        opts[o] = {'ron': true};
      } else {
        _markMissed(o);
      }
    }
    if (opts.isEmpty) {
      _drawRinshan(s);
    } else {
      phase = 'chankan';
    }
  }
}
