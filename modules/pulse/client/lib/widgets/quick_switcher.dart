import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';
import 'common.dart';

/// Ctrl+K: fuzzy jump to a text / voice channel or a member's profile.
Future<void> showQuickSwitcher(BuildContext context) => showDialog<void>(useRootNavigator: false, 
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => const _QuickSwitcher(),
    );

class _Item {
  final String label, sub;
  final IconData icon;
  final int score;
  final VoidCallback onPick;
  final Member? member;
  _Item(this.label, this.sub, this.icon, this.score, this.onPick, {this.member});
}

class _QuickSwitcher extends StatefulWidget {
  const _QuickSwitcher();
  @override
  State<_QuickSwitcher> createState() => _QuickSwitcherState();
}

class _QuickSwitcherState extends State<_QuickSwitcher> {
  final _ctl = TextEditingController();
  int _sel = 0;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Subsequence match score (higher = better); -1 = no match.
  static int _score(String text, String q) {
    if (q.isEmpty) return 1;
    final t = text.toLowerCase();
    if (t.startsWith(q)) return 1000 - t.length;
    if (t.contains(q)) return 500 - t.indexOf(q);
    var i = 0, gaps = 0;
    for (final r in t.runes) {
      if (i < q.length && r == q.codeUnitAt(i)) {
        i++;
      } else if (i > 0) {
        gaps++;
      }
    }
    return i == q.length ? 200 - gaps : -1;
  }

  List<_Item> _items(AppState app) {
    final q = _ctl.text.trim().toLowerCase().replaceFirst(RegExp(r'^[#@!]'), '');
    final prefix = _ctl.text.trim().isEmpty ? '' : _ctl.text.trim()[0];
    final out = <_Item>[];
    if (prefix != '@') {
      for (final c in app.channels.values) {
        if (prefix == '!' && !c.isVoice) continue;
        if (prefix == '#' && c.isVoice) continue;
        final sc = _score(c.name, q);
        if (sc < 0) continue;
        final unread = app.histories[c.id]?.unread ?? 0;
        out.add(_Item(
          c.name,
          c.isVoice ? '语音频道 · ${app.voice.values.where((v) => v.channel == c.id).length} 人' : (unread > 0 ? '$unread 条未读' : '文字频道'),
          c.isVoice ? Icons.volume_up : Icons.tag,
          sc + (unread > 0 ? 50 : 0) + (c.id == app.currentChannel ? -100 : 0),
          () => c.isVoice ? app.joinVoice(c.id) : app.selectChannel(c.id),
        ));
      }
    }
    if (prefix != '#' && prefix != '!') {
      for (final m in app.members.values) {
        final sc = [_score(m.display, q), _score(m.username, q)].reduce((a, b) => a > b ? a : b);
        if (sc < 0 || q.isEmpty) continue;
        out.add(_Item(m.display, '@${m.username} · ${statusLabel(m.id == app.me ? app.myStatus : m.presence)}', Icons.person, sc - 10,
            () => app.mentionRequest.value = '@${m.username} ',
            member: m));
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final items = _items(app);
    if (_sel >= items.length) _sel = items.isEmpty ? 0 : items.length - 1;
    void pick(int i) {
      if (i >= items.length) return;
      Navigator.pop(context);
      items[i].onPick();
    }

    return Dialog(
      alignment: const Alignment(0, -0.45),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('快速切换', style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('输入频道或成员名；# 只搜文字频道，! 只搜语音频道，@ 只搜成员', style: TextStyle(color: t.muted, fontSize: 12)),
            const SizedBox(height: 10),
            Focus(
              onKeyEvent: (n, e) {
                if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() => _sel = (_sel + 1).clamp(0, items.isEmpty ? 0 : items.length - 1));
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() => _sel = (_sel - 1).clamp(0, items.isEmpty ? 0 : items.length - 1));
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _ctl,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: '去哪里？', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setState(() => _sel = 0),
                onSubmitted: (_) => pick(_sel),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, children: [
                for (var i = 0; i < items.length; i++)
                  HoverTile(
                    selected: i == _sel,
                    onTap: () => pick(i),
                    child: Row(children: [
                      if (items[i].member != null) Avatar(items[i].member, size: 22) else Icon(items[i].icon, size: 20, color: t.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(items[i].label, style: TextStyle(color: t.text, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      Text(items[i].sub, style: TextStyle(color: t.muted, fontSize: 12)),
                    ]),
                  ),
                if (items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('没有匹配项', textAlign: TextAlign.center, style: TextStyle(color: t.muted))),
              ]),
            ),
            const SizedBox(height: 6),
            Text('↑↓ 选择 · Enter 打开 · Esc 关闭', style: TextStyle(color: t.muted, fontSize: 11.5), textAlign: TextAlign.right),
          ]),
        ),
      ),
    );
  }
}

/// Alt+↑ / Alt+↓ between text channels (Alt+Shift: only unread ones).
void cycleChannel(AppState app, int delta, {bool unreadOnly = false}) {
  final list = app.sortedChannels(ChannelKind.text);
  if (list.isEmpty) return;
  var i = list.indexWhere((c) => c.id == app.currentChannel);
  for (var n = 0; n < list.length; n++) {
    i = (i + delta + list.length) % list.length;
    if (!unreadOnly || (app.histories[list[i].id]?.unread ?? 0) > 0) {
      app.selectChannel(list[i].id);
      return;
    }
  }
}
