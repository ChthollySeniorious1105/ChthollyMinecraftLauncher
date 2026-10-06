import 'package:aurora_shared/aurora_shared.dart';

/// Emoji reactions on recent chat messages of one chat channel (a room, or
/// the lobby). Only the last [keep] player messages can be reacted to, so
/// memory stays bounded no matter how long the channel lives.
class ChatReactions {
  static const keep = 300;

  /// message id -> reaction index -> client ids that reacted
  final Map<int, Map<int, Set<int>>> _msgs = {};

  /// Remember a new player message so it can receive reactions.
  void track(int id) {
    _msgs[id] = {};
    if (_msgs.length > keep) _msgs.remove(_msgs.keys.first);
  }

  /// Toggle [clientId]'s reaction [e] on message [id]. Returns true if the
  /// reaction is now on, false if it was removed. Throws [GameError] for an
  /// unknown message or reaction.
  bool toggle(int id, int e, int clientId) {
    if (e < 0 || e >= kReactions.length) throw GameError('无效的表情');
    final msg = _msgs[id];
    if (msg == null) throw GameError('消息太旧了，不能再贴表情');
    final who = msg.putIfAbsent(e, () => <int>{});
    if (who.remove(clientId)) {
      if (who.isEmpty) msg.remove(e);
      return false;
    }
    who.add(clientId);
    return true;
  }
}
