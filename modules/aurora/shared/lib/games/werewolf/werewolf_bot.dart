part of 'werewolf.dart';

/// Bots only use what their own seat can see: their role, known wolves (if a wolf),
/// their lover, their own seer checks / witch info, plus public state (claims, votes, deaths).
extension WerewolfBot on Werewolf {
  T _pick<T>(List<T> l) => l[rng.nextInt(l.length)];

  /// Wolves [s] knows (plus itself and its lover when in the third camp).
  Set<int> _mates(int s) {
    final k = knownWolves(s);
    final o = loverOf(s);
    if (o >= 0 && loversThird) return {...k, s, o};
    return k;
  }

  /// Seats [s] never wants to harm (its own camp as far as it knows).
  Set<int> _friends(int s) {
    final f = <int>{s, ..._mates(s)};
    final o = loverOf(s);
    if (o >= 0) f.add(o);
    if (roles[s] == 'cupid') f.addAll(lovers);
    if (loversThird && lovers.contains(s) && cupidSeat >= 0) f.add(cupidSeat);
    return f;
  }

  /// Does [s] play for the wolves (as far as its decisions go)?
  bool _wolfish(int s) => isWolfSeat(s) && !(loversThird && lovers.contains(s));

  /// My own check results: seat -> isWolf.
  Map<int, bool> _myChecks(int s) {
    final c = seerChecks[s];
    return {for (var i = 0; i + 1 < c.length; i += 2) c[i]: c[i + 1] == 1};
  }

  /// Seats that publicly claimed seer.
  List<int> get _claimants => {for (final c in claims) c['s'] as int}.toList();

  /// Which claimant a good (non-seer) bot trusts: the first claimant who has not
  /// claimed this bot is a wolf. -1 if none.
  int _trusted(int me) {
    for (final c in _claimants) {
      if (c == me) continue;
      final lied = claims.any((x) => x['s'] == c && x['t'] == me && x['w'] == true);
      if (!lied) return c;
    }
    return -1;
  }

  /// Suspicion score for [t] from [me]'s point of view (higher = more wolf-like).
  double _suspect(int me, int t) {
    if (_friends(me).contains(t) && t != me) return -200;
    if (roles[me] == 'seer') {
      final ch = _myChecks(me);
      if (ch.containsKey(t)) return ch[t]! ? 100 : -100;
      if (_claimants.contains(t)) return 60; // a fake seer
    }
    // Shared "public noise" so good bots without information converge on the
    // same target instead of scattering votes (derived only from public data).
    var v = _publicNoise(t);
    final trust = _trusted(me);
    for (final c in claims) {
      final src = c['s'] as int;
      if (c['t'] == t) {
        final w = c['w'] == true ? 1.0 : -1.0;
        if (src == trust) {
          v += 10 * w;
        } else if (trust >= 0) {
          v -= 3 * w; // a counter-claimant's "gold water" is probably a teammate
        } else {
          v += 2 * w;
        }
      }
      // someone who falsely accused me is a wolf
      if (src == t && c['t'] == me && c['w'] == true && !isWolfSeat(me)) v += 50;
    }
    if (_claimants.contains(t) && t != trust && trust >= 0) v += 6;
    if (t == trust) v -= 8;
    // Public voting record: voting against the trusted seer (or for the seats
    // they cleared) is suspicious.
    if (trust >= 0) {
      final cleared = {for (final c in claims) if (c['s'] == trust && c['w'] != true) c['t']};
      final accused = {for (final c in claims) if (c['s'] == trust && c['w'] == true) c['t']};
      for (final r in voteHist) {
        for (final p in r['votes'] as List) {
          if (p[0] != t) continue;
          final target = p[1];
          if (r['kind'] == 'exile' && (target == trust || cleared.contains(target))) v += 2.5;
          if (r['kind'] == 'exile' && accused.contains(target)) v -= 1;
          if (r['kind'] == 'sheriff' && _claimants.contains(target) && target != trust) v += 1.5;
        }
      }
    }
    if (idiotFlipped.contains(t) || revealed[t] == 'idiot' || revealed[t] == 'knight') v -= 20;
    if (crowActive && crowMark == t) v += 1; // follow the crow's hint
    // 困难: players who voted out revealed good players look suspicious
    if (botLevel == 2) {
      for (final r in voteHist) {
        if (r['kind'] != 'exile') continue;
        final out = r['out'];
        if (out is! int || out < 0 || !revealed.containsKey(out) || werewolfIsWolf(revealed[out]!)) continue;
        for (final p in r['votes'] as List) {
          if (p[0] == t && p[1] == out) v += 1.5;
        }
      }
    }
    return v;
  }

  double _publicNoise(int t) {
    final h = (t * 7919 + round * 104729 + _salt * 31) % 1000;
    return h / 1000.0;
  }

  int _best(List<int> cands, double Function(int) score) {
    var best = cands.first;
    var bs = score(best);
    for (final c in cands.skip(1)) {
      final sc = score(c);
      if (sc > bs) {
        best = c;
        bs = sc;
      }
    }
    return best;
  }

  /// Wolf-side preference for killing / voting out [t].
  double _wolfWant(int me, int t) {
    if (_friends(me).contains(t) || knownWolves(me).contains(t)) return -100;
    var v = rng.nextDouble() * (botLevel == 2 ? 0.5 : 2);
    if (_claimants.contains(t)) v += 8;
    if (t == sheriff) v += 3;
    if (revealed[t] == 'knight') v += 3;
    if (claims.any((c) => c['s'] == t && _mates(me).contains(c['t']) && c['w'] == true)) v += 5;
    if (revealed.containsKey(t)) v -= 2;
    return v;
  }

  /// Hostile pick (vote / curse / shoot) from [s]'s point of view.
  int _hostile(int s, List<int> pool) => _best(pool, (t) => _wolfish(s) ? _wolfWant(s, t) : _suspect(s, t));

  /// LLM speech text on top of the heuristic speech (which keeps the claim
  /// logic). Returns null while pending (caller returns null from bot()).
  Map<String, dynamic>? _aiSpeech(int s, {bool lastWords = false}) {
    final key = 'sp:$round:${lastWords ? 'lw' : speechKind}:${lastWords ? 0 : speechIdx}:$s';
    final base = _aiSpeechBase.putIfAbsent(key, () {
      if (_aiSpeechBase.length > 64) _aiSpeechBase.clear();
      return _speech(s, lastWords: lastWords);
    });
    final r = _ai.poll(setup.ai!, key, () {
      final role = roles[s];
      final wolf = _wolfish(s);
      final claim = base['claim'] as Map?;
      final p = StringBuffer()
        ..writeln('你是 ${seatName(s)}，身份：${werewolfRoleNames[role]}（${werewolfRoleDesc[role] ?? ''}）。'
            '阵营：${team3.contains(s) ? '情侣第三方' : (wolf ? '狼人' : '好人')}。')
        ..writeln('存活：${aliveSeats.map(seatName).join('、')}${sheriff >= 0 ? '；警长：${seatName(sheriff)}' : ''}')
        ..writeln('你的私密信息：')
        ..writeln(privLog[s].isEmpty ? '（无）' : privLog[s].skip(privLog[s].length > 20 ? privLog[s].length - 20 : 0).join('\n'))
        ..writeln('公开记录（最近）：');
      final pub = pubLog.length > 40 ? pubLog.sublist(pubLog.length - 40) : pubLog;
      for (final l in pub) {
        p.writeln('- ${l['t']}');
      }
      final kind = lastWords
          ? '遗言'
          : switch (speechKind) { 'sheriff' || 'sheriff_pk' => '警长竞选发言', 'pk' => 'PK 发言', _ => '白天发言' };
      p.writeln('现在轮到你的$kind。');
      if (claim != null) {
        p.writeln('你这次要以预言家身份报验人：${seatName(claim['target'] as int)} 是${claim['wolf'] == true ? '狼人（查杀）' : '好人（金水）'}，发言要和这个一致。');
      } else if (wolf) {
        p.writeln('你是狼人，要隐藏身份、伪装成好人，可以把怀疑引向好人，但不要暴露狼队友。');
      } else {
        p.writeln('请结合公开信息和你的私密信息，分析谁更像狼人。是否公开自己的神职身份由你判断（通常不要轻易暴露）。');
      }
      p.write('用口语化的中文说 1~3 句话，不超过 ${Werewolf.maxText} 个字，只输出发言内容本身，不要加引号或旁白。');
      return AiRequest(
          system: '你在玩中文网络狼人杀，法官是系统。请像真人玩家一样自然、简洁地发言，玩家用“N号”称呼。',
          prompt: p.toString(),
          maxTokens: 150);
    });
    if (r.pending) return null;
    final raw = r.text;
    var t = raw == null ? '' : AiText.firstLine(sanitizeText(raw), maxLen: 500).replaceAll(RegExp(r'\s+'), ' ');
    if (t.contains('{') || t.contains('}') || t.length < 2 || t.length > Werewolf.maxText) t = '';
    return t.isEmpty ? base : {...base, 'text': t};
  }

  Map<String, dynamic> _speech(int s, {bool lastWords = false}) {
    final r = roles[s];
    Map<String, dynamic>? claim;
    String text;
    final said = claims.where((c) => c['s'] == s).map((c) => c['t']).toSet();
    if (r == 'seer') {
      final ch = _myChecks(s);
      final fresh = ch.entries.where((e) => !said.contains(e.key)).toList();
      if (fresh.isNotEmpty) {
        final e = fresh.last;
        claim = {'target': e.key, 'wolf': e.value};
      }
      text = lastWords ? '我是真预言家，请好人跟着我的验人走' : '我是预言家，大家相信我';
    } else if (s == _fakeSeer && isWolfSeat(s)) {
      final pool = [for (final t in aliveSeats) if (t != s && !said.contains(t)) t];
      if (pool.isNotEmpty && (said.isEmpty || !lastWords)) {
        final t = _pick(pool);
        claim = {'target': t, 'wolf': !knownWolves(s).contains(t) && rng.nextDouble() < 0.6};
      }
      text = '我才是预言家，对跳的是狼';
    } else {
      final trust = _trusted(s);
      final sus = [for (final t in aliveSeats) if (t != s && !_friends(s).contains(t)) t];
      final who = sus.isEmpty ? -1 : _hostile(s, sus);
      text = _pick([
        if (trust >= 0) '我站边 ${seatName(trust)} 的预言家',
        if (who >= 0) '我觉得 ${seatName(who)} 发言有问题',
        if (who >= 0) '今天可以考虑出 ${seatName(who)}',
        '我是好人，过',
        '信息不多，听后面的发言',
        '我是平民，没什么信息',
      ]);
      if (lastWords) text = '我是好人，${who >= 0 ? '重点关注 ${seatName(who)}' : '大家加油'}';
    }
    return {'type': 'end', 'text': text, 'claim': claim};
  }

  /// 骑士: duel the most suspicious player once there is a clear suspect.
  Map<String, dynamic>? _duelAction(int s) {
    if (!canDuel(s)) return null;
    final pool = [for (final t in aliveSeats) if (!_friends(s).contains(t)) t];
    if (pool.isEmpty) return null;
    final t = _best(pool, (t) => _suspect(s, t));
    final sc = _suspect(s, t);
    if (sc > 9 || (round >= 3 && rng.nextDouble() < 0.12)) return {'type': 'duel', 'target': t};
    return null;
  }

  Map<String, dynamic> _explodeAction(int s) {
    if (roles[s] != 'whiteWolfKing') return {'type': 'explode'};
    final pool = [for (final t in aliveSeats) if (!_friends(s).contains(t) && !knownWolves(s).contains(t)) t];
    return {'type': 'explode', 'target': pool.isEmpty ? -1 : _best(pool, (t) => _wolfWant(s, t))};
  }

  Map<String, dynamic>? _nightBot(int s) {
    final r = roles[s];
    final others = [for (final t in aliveSeats) if (t != s) t];
    final duty = nightDuty(s);
    if (duty == 'magic') {
      final pool = [for (final t in aliveSeats) if (!swapped.contains(t)) t];
      if (pool.length >= 2 && rng.nextDouble() < 0.45) {
        // protect a trusted seer / myself by swapping with someone suspicious
        final trust = _trusted(s);
        final a = pool.contains(trust) ? trust : (pool.contains(s) ? s : _pick(pool));
        final rest = pool.where((t) => t != a).toList();
        return {'type': 'magic', 'a': a, 'b': _best(rest, (t) => _suspect(s, t))};
      }
      return {'type': 'magic', 'a': -1, 'b': -1};
    }
    if (magicPending && duty == 'check') return null; // the magician always acts (bot never returns null)
    switch (duty) {
      case 'kill':
        if (r == 'wolfBeauty' && !charmDone) {
          final pool = [for (final t in others) if (!_friends(s).contains(t) && !knownWolves(s).contains(t)) t];
          return {'type': 'charm', 'target': pool.isEmpty ? -1 : _best(pool, (t) => _wolfWant(s, t))};
        }
        if (wolfVotes.containsKey(s) || wolfKill != -2) return null;
        // follow a teammate's choice if there is one
        final prev = wolfVotes.values.where((v) => v >= 0 && !_friends(s).contains(v)).toList();
        if (prev.isNotEmpty) return {'type': 'kill', 'target': prev.first};
        final prey = [for (final t in aliveSeats) if (!_friends(s).contains(t) && !knownWolves(s).contains(t)) t];
        if (prey.isEmpty) return {'type': 'kill', 'target': -1};
        return {'type': 'kill', 'target': _best(prey, (t) => _wolfWant(s, t))};
      case 'link':
        if (others.isEmpty) return {'type': 'link', 'a': s, 'b': s}; // unreachable (≥6 players)
        final a = rng.nextDouble() < 0.35 ? s : _pick(others);
        final rest = aliveSeats.where((t) => t != a).toList();
        return {'type': 'link', 'a': a, 'b': _pick(rest)};
      case 'model':
        return {'type': 'model', 'target': _pick(others)};
      case 'curse':
        final pool = [for (final t in others) if (!_friends(s).contains(t)) t];
        if (pool.isEmpty) return {'type': 'curse', 'target': -1};
        return {'type': 'curse', 'target': _hostile(s, pool)};
      case 'check':
        final ch = _myChecks(s);
        final pool = others.where((t) => !ch.containsKey(t)).toList();
        final p = pool.isEmpty ? others : pool;
        return {'type': 'check', 'target': _best(p, (t) => _suspect(s, t).abs() < 50 ? _suspect(s, t) : 0)};
      case 'guard':
        final opts = [for (final t in aliveSeats) if (t != lastGuard) t];
        if (opts.isEmpty) return {'type': 'guard', 'target': -1};
        final trust = _trusted(s);
        if (trust >= 0 && alive[trust] && trust != lastGuard && rng.nextDouble() < 0.7) {
          return {'type': 'guard', 'target': trust};
        }
        return {'type': 'guard', 'target': _pick(opts)};
      case 'witch':
        if (!wolvesDecided) return null;
        final v = wolfKill;
        if (antidote && v >= 0 && (v != s || canSelfSave())) {
          if (round <= 2 || _claimants.contains(v) || _friends(s).contains(v) || rng.nextDouble() < 0.4) {
            return {'type': 'witch', 'save': true, 'poison': -1};
          }
        }
        final pool = [for (final t in others) if (!_friends(s).contains(t)) t];
        if (poisonLeft && round >= 2 && pool.isNotEmpty) {
          final t = _best(pool, (t) => _suspect(s, t));
          if (_suspect(s, t) > 8) return {'type': 'witch', 'save': false, 'poison': t};
        }
        return {'type': 'witch', 'save': false, 'poison': -1};
      default:
        return {'type': 'sleep'};
    }
  }

  Map<String, dynamic>? botAction(int s) {
    if (isOver) return null;
    final r = roles[s];
    final wolf = _wolfish(s);
    switch (phase) {
      case 'night':
        if (!alive[s] || nightDone(s)) return null;
        return _nightBot(s);
      case 'sheriff_signup':
        if (r == 'whiteWolfKing' && canExplode(s) && rng.nextDouble() < 0.05) return _explodeAction(s);
        final run = r == 'seer' || s == _fakeSeer || rng.nextDouble() < 0.25;
        return {'type': 'run', 'run': run};
      case 'speech':
        if (s != speaker) return null;
        final duel = _duelAction(s);
        if (duel != null) return duel;
        if (r == 'whiteWolfKing' && canExplode(s) && speechKind == 'day' && rng.nextDouble() < 0.1) {
          return _explodeAction(s);
        }
        if (speechKind == 'sheriff' && r != 'seer' && s != _fakeSeer && _claimants.isNotEmpty && rng.nextDouble() < 0.5) {
          return {'type': 'withdraw'};
        }
        if (wolf && canExplode(s) && speechKind == 'pk' && pkList.contains(s) && rng.nextDouble() < 0.15) {
          return _explodeAction(s);
        }
        if (aiOn) return _aiSpeech(s);
        return _speech(s);
      case 'direction':
        final duel = _duelAction(s);
        if (duel != null) return duel;
        return {'type': 'direction', 'dir': rng.nextBool() ? 1 : -1};
      case 'vote':
      case 'sheriff_vote':
        if (!currentVoters.contains(s) || votes.containsKey(s)) return null;
        final cands = [
          for (final t in (phase == 'vote' ? voteCands : (speechKind == 'sheriff_pk' ? pkList : candidates)))
            if (t != s) t
        ];
        if (cands.isEmpty) return {'type': 'vote', 'target': -1};
        if (phase == 'sheriff_vote') {
          final fake = cands.where((t) => _friends(s).contains(t)).toList();
          if (fake.isNotEmpty && (wolf || loverOf(s) >= 0)) return {'type': 'vote', 'target': fake.first};
          if (wolf) return {'type': 'vote', 'target': _best(cands, (t) => -_wolfWant(s, t))};
          final trust = _trusted(s);
          if (cands.contains(trust)) return {'type': 'vote', 'target': trust};
          return {'type': 'vote', 'target': _best(cands, (t) => -_suspect(s, t))};
        }
        final pool = cands.where((t) => !_friends(s).contains(t)).toList();
        if (pool.isEmpty) return {'type': 'vote', 'target': -1};
        // 简单: half the time votes on a hunch
        if (botLevel == 0 && rng.nextBool()) return {'type': 'vote', 'target': _pick(pool)};
        return {'type': 'vote', 'target': _hostile(s, pool)};
      case 'lastwords':
        if (aiOn) return _aiSpeech(s, lastWords: true);
        return _speech(s, lastWords: true);
      case 'badge':
        final pool = [for (final t in aliveSeats) if (t != s) t];
        if (pool.isEmpty) return {'type': 'badge', 'target': -1};
        if (wolf) {
          final m = pool.where((t) => _friends(s).contains(t)).toList();
          return {'type': 'badge', 'target': m.isNotEmpty ? m.first : -1};
        }
        return {'type': 'badge', 'target': _best(pool, (t) => -_suspect(s, t))};
      case 'shoot':
        if (task?['can'] != true) return {'type': 'shoot', 'target': -1};
        final pool = [for (final t in aliveSeats) if (t != s && !_friends(s).contains(t)) t];
        if (pool.isEmpty) return {'type': 'shoot', 'target': -1};
        if (wolf) return {'type': 'shoot', 'target': _best(pool, (t) => _wolfWant(s, t))};
        final t = _best(pool, (t) => _suspect(s, t));
        return {'type': 'shoot', 'target': _suspect(s, t) > 3 || rng.nextDouble() < 0.4 ? t : -1};
    }
    return null;
  }
}
