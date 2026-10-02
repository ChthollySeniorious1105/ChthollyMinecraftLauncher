part of 'werewolf.dart';

extension WerewolfView on Werewolf {
  /// Public cause of death: night deaths are not distinguished.
  String _publicCause(int s) {
    final c = deathCause[s];
    if (c == null) return '';
    if (isOver) return c;
    if (diedAtNight.contains(s)) return 'night';
    return c;
  }

  Map<String, dynamic> buildView(int seat) {
    final over = isOver;
    final me = seat >= 0 && seat < players ? seat : -1;
    final myRole = me >= 0 ? roles[me] : null;
    final night = phase == 'night';
    final meAlive = me >= 0 && alive[me];
    final pack = me >= 0 && killers.contains(me); // I open my eyes with the wolves tonight
    final known = me >= 0 ? knownWolves(me) : const <int>{};
    final myLovers = me >= 0 && (lovers.contains(me) || roles[me] == 'cupid') ? lovers : const <int>[];

    // Role labels visible to me.
    final shown = <String?>[
      for (var s = 0; s < players; s++)
        if (over || s == me || revealed.containsKey(s) || known.contains(s) || (myLovers.contains(s) && lovers.contains(me)))
          roles[s]
        else
          null
    ];

    Map<String, dynamic>? nightInfo;
    if (me >= 0 && night && meAlive) {
      final duty = nightDuty(me);
      nightInfo = {
        'done': nightDone(me),
        'duty': duty,
        // Only the seer has to wait for the magician (her result is immediate).
        'magicPending': magicPending && duty == 'check',
      };
      if (pack) {
        nightInfo['wolfVotes'] = [for (final e in wolfVotes.entries) [e.key, e.value]];
        nightInfo['myVote'] = wolfVotes[me];
        if (beautySeat >= 0 && killers.contains(beautySeat)) {
          nightInfo['charm'] = charmDone ? charmPick : null;
        }
      }
      switch (duty) {
        case 'check':
          nightInfo['target'] = seerTarget;
        case 'guard':
          nightInfo['target'] = guardTarget;
          nightInfo['lastGuard'] = lastGuard;
        case 'witch':
          nightInfo['ready'] = wolvesDecided;
          nightInfo['victim'] = wolvesDecided && antidote ? wolfKill : null;
          nightInfo['canSelfSave'] = canSelfSave();
        case 'magic':
          nightInfo['swapped'] = swapped.toList()..sort();
          nightInfo['swap'] = swapA >= 0 ? [swapA, swapB] : null;
        case 'curse':
          nightInfo['target'] = crowTarget;
      }
      if (roles[me] == 'wolfBeauty' && pack) nightInfo['charmDone'] = charmDone;
    }
    if (me >= 0 && night && isWolfSeat(me) && (pack || !alive[me]) && roles[me] != 'hiddenWolf') {
      // pack wolves (even dead ones) know the pack's decision
      nightInfo ??= {'done': true};
      nightInfo['kill'] = wolfKill == -2 ? null : wolfKill;
    }

    final t = task;
    final taskKind = t == null ? '' : t['k'] as String;
    final taskSeat = t == null ? -1 : t['s'] as int;

    return {
      'phase': switch (phase) {
        'lastwords' || 'badge' || 'shoot' => 'task',
        _ => phase,
      },
      'round': round,
      'board': werewolfBoardSummary(roles),
      'boardId': board,
      'win': winMode,
      'selfSave': selfSave,
      'sheriffOn': sheriffOn,
      'roleCounts': {
        for (final r in werewolfRoleNames.keys)
          if (roles.contains(r)) r: roles.where((x) => x == r).length
      },
      'alive': alive,
      'roles': shown,
      'cause': [for (var s = 0; s < players; s++) _publicCause(s)],
      'deathDay': [for (var s = 0; s < players; s++) deathDay[s] ?? 0],
      'idiot': idiotFlipped.toList(),
      'sheriff': sheriff,
      'me': me,
      'myRole': myRole,
      'mates': [for (final s in known) if (s != me) s]..sort(),
      'packMates': pack || (me >= 0 && inPack(me)) ? [for (final s in known) if (s != me && inPack(s)) s] : const <int>[],
      'hiddenActive': myRole == 'hiddenWolf' ? hiddenActive : null,
      'turned': me >= 0 && wildTurned.contains(me),
      'model': myRole == 'wildChild' ? wildModel : -1,
      'lovers': over ? lovers : myLovers,
      'loversThird': over || myLovers.isNotEmpty ? loversThird : false,
      'charmed': me >= 0 && roles[me] == 'wolfBeauty' ? charmed : -1,
      'swapped': myRole == 'magician' ? (swapped.toList()..sort()) : const <int>[],
      'duelUsed': myRole == 'knight' ? duelUsed : null,
      'checks': myRole == 'seer' ? seerChecks[me] : const <int>[],
      'antidote': myRole == 'witch' ? antidote : null,
      'poison': myRole == 'witch' ? poisonLeft : null,
      'night': nightInfo,
      'dawn': dawn,
      // sheriff election
      'signed': [for (final s in signup.keys) s],
      'mySignup': me >= 0 ? signup[me] : null,
      'candidates': candidates,
      'withdrawn': withdrawn.toList(),
      // speeches
      'speaker': speaker,
      'speechKind': speechKind,
      'order': speechOrder,
      'speeches': speeches.length > 60 ? speeches.sublist(speeches.length - 60) : speeches,
      'claims': claims,
      // voting
      'pk': pkList,
      'voteCands': phase == 'vote'
          ? voteCands
          : (phase == 'sheriff_vote' ? (speechKind == 'sheriff_pk' ? pkList : candidates) : const <int>[]),
      'voters': currentVoters,
      'voted': [for (final s in votes.keys) s],
      'myVote': me >= 0 ? votes[me] : null,
      'lastVote': lastVote,
      // the crow's curse is announced when the exile vote starts
      'crow': crowActive ? crowMark : -1,
      'myCurse': myRole == 'crow' && !night ? crowMark : -1,
      // tasks
      'task': taskKind == 'shoot' ? 'skill' : taskKind,
      'canShoot': taskKind == 'shoot' && taskSeat == me ? t!['can'] == true : null,
      'taskSeat': taskSeat,
      'canExplode': canExplode(me),
      'explodeTake': me >= 0 && roles[me] == 'whiteWolfKing',
      'canDuel': canDuel(me),
      // logs
      'log': pubLog.length > 120 ? pubLog.sublist(pubLog.length - 120) : pubLog,
      'private': me >= 0 ? privLog[me] : const <String>[],
      // end
      'winner': winner,
      'reason': reason,
      'camps': over ? [for (var s = 0; s < players; s++) campOf(s)] : null,
      'nights': over ? nights : null,
      'over': over,
    };
  }
}
