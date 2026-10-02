import 'package:pulse_shared/pulse_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';
import '../widgets/common.dart';

/// Top-bar search field: Enter searches all text channels ("from:名字" filters by author).
/// Results open in a side sheet; clicking one jumps to the message.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key});
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  late final AppState _app = AppScope.read(context);

  @override
  void initState() {
    super.initState();
    _app.focusSearch.addListener(_onFocus);
  }

  void _onFocus() {
    _focus.requestFocus();
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
  }

  @override
  void dispose() {
    _app.focusSearch.removeListener(_onFocus);
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run() {
    final app = AppScope.read(context);
    var q = _ctl.text.trim();
    var from = 0;
    final m = RegExp(r'from:(\S+)').firstMatch(q);
    if (m != null) {
      final who = m.group(1)!.toLowerCase();
      for (final u in app.members.values) {
        if (u.username.toLowerCase() == who || u.display.toLowerCase() == who) from = u.id;
      }
      q = q.replaceFirst(m.group(0)!, '').trim();
      if (from == 0) return app.toast('没有找到用户 ${m.group(1)}');
    }
    if (q.isEmpty && from == 0) return;
    app.search(q, from: from);
    showSearchPanel(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return SizedBox(
      width: 220,
      height: 30,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _ctl.clear()},
        child: TextField(
          controller: _ctl,
          focusNode: _focus,
          style: const TextStyle(fontSize: 13),
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: '搜索（Ctrl+F）  from:名字',
            hintStyle: TextStyle(fontSize: 12.5, color: t.muted),
            fillColor: t.rail,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            suffixIcon: Icon(Icons.search, size: 16, color: t.muted),
            suffixIconConstraints: const BoxConstraints(minWidth: 28),
          ),
        ),
      ),
    );
  }
}

void showSearchPanel(BuildContext context) => _showSidePanel(context, (c) => const _SearchResults());

void showPinsPanel(BuildContext context, ChannelInfo ch) {
  AppScope.read(context).loadPins(ch.id);
  _showSidePanel(context, (c) => _PinsList(ch));
}

void _showSidePanel(BuildContext context, WidgetBuilder builder) {
  showGeneralDialog<void>(useRootNavigator: false, 
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (c, a, b) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 52, right: 12),
        child: Material(
          color: PulseColors.of(c).sidebar,
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 440, height: MediaQuery.sizeOf(c).height - 90, child: builder(c)),
        ),
      ),
    ),
    transitionBuilder: (c, a, b, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(a), child: child),
    ),
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PanelHeader(
        app.searching ? '搜索中…' : '${app.searchResults.length}${app.searchMore ? '+' : ''} 条结果',
        subtitle: app.searchQuery.isEmpty ? null : '“${app.searchQuery}”',
      ),
      Expanded(
        child: app.searching
            ? const Center(child: CircularProgressIndicator())
            : app.searchResults.isEmpty
                ? Center(child: Text('没有找到匹配的消息', style: TextStyle(color: t.muted)))
                : ListView(padding: const EdgeInsets.all(8), children: [
                    for (final m in app.searchResults) _ResultTile(m, highlight: app.searchQuery),
                    if (app.searchMore)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('结果较多，只显示最新 50 条，请换个更具体的关键词', textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 12)),
                      ),
                  ]),
      ),
    ]);
  }
}

class _PinsList extends StatelessWidget {
  final ChannelInfo ch;
  const _PinsList(this.ch);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final pins = app.pins[ch.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PanelHeader('置顶消息', subtitle: '#${ch.name}'),
      Expanded(
        child: pins == null
            ? const Center(child: CircularProgressIndicator())
            : pins.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('这个频道还没有置顶消息。\n右键消息 → “置顶消息”。', textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                    ),
                  )
                : ListView(padding: const EdgeInsets.all(8), children: [
                    for (final m in pins)
                      _ResultTile(m, trailing: (m.uid == app.me || (app.channels[m.ch]?.can(Perm.manageMessages) ?? false) || (app.channels[m.ch]?.isDm ?? false))
                          ? IconButton(
                              tooltip: '取消置顶',
                              icon: Icon(Icons.close, size: 16, color: t.muted),
                              onPressed: () => app.setPinned(m, false),
                            )
                          : null),
                  ]),
      ),
    ]);
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _PanelHeader(this.title, {this.subtitle});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      color: t.rail,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(color: t.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Message m;
  final String highlight;
  final Widget? trailing;
  const _ResultTile(this.m, {this.highlight = '', this.trailing});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final a = app.members[m.uid];
    final ch = app.channels[m.ch];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: t.chat, borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          Navigator.pop(context);
          app.jumpToMessage(m.ch, m.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(a, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(a?.display ?? '?', overflow: TextOverflow.ellipsis, style: TextStyle(color: nameColor(context, a), fontWeight: FontWeight.w600))),
                  const SizedBox(width: 6),
                  Text('#${ch?.name ?? '?'} · ${formatTime(m.ts)}', style: TextStyle(color: t.muted, fontSize: 11.5)),
                ]),
                const SizedBox(height: 3),
                _highlighted(m.text, highlight, t),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }

  static Widget _highlighted(String text, String q, PulseTheme t) {
    final base = TextStyle(color: t.text, fontSize: 13.5);
    if (q.isEmpty) return Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: base);
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var i = 0;
    while (true) {
      final j = lower.indexOf(q, i);
      if (j < 0) break;
      spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(text: text.substring(j, j + q.length), style: TextStyle(backgroundColor: t.idle.withValues(alpha: 0.4), fontWeight: FontWeight.w600)));
      i = j + q.length;
    }
    spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: 4, overflow: TextOverflow.ellipsis);
  }
}
