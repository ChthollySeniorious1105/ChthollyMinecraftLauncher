import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_shared/pulse_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../theme/themes.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import 'main_screen.dart';

/// Messages of one text channel + composer.
class ChatView extends StatefulWidget {
  final ChannelInfo channel;
  const ChatView({super.key, required this.channel});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  Message? _replyTo;
  Message? _editing;
  late AppState _app;
  final Map<int, GlobalKey> _keys = {}; // message id -> key (for scroll-to)
  int _flash = 0; // message id highlighted after a jump
  bool _atBottom = true;
  int _seenCount = 0; // messages loaded when the user scrolled away from the bottom
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _app = AppScope.read(context);
    _app.mentionRequest.addListener(_onMention);
    _app.jumpTo.addListener(_onJump);
    // restore the unsent draft of this channel
    final d = _app.drafts[widget.channel.id];
    if (d != null) _input.text = d;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _onJump();
    });
  }

  @override
  void dispose() {
    final text = _input.text;
    if (text.trim().isEmpty) {
      _app.drafts.remove(widget.channel.id);
    } else {
      _app.drafts[widget.channel.id] = text;
    }
    _app.mentionRequest.removeListener(_onMention);
    _app.jumpTo.removeListener(_onJump);
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onJump() {
    final j = _app.jumpTo.value;
    if (j == null || j.$1 != widget.channel.id) return;
    _app.jumpTo.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMessage(j.$2));
  }

  /// Scrolls the (reversed) list until the message is built, centres it and flashes it.
  Future<void> _scrollToMessage(int id, [int attempt = 0]) async {
    final msgs = _app.histories[widget.channel.id]?.messages ?? const <Message>[];
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx < 0 || !_scroll.hasClients || !mounted) return;
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => _flash = id);
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted && _flash == id) setState(() => _flash = 0);
      });
      return;
    }
    if (attempt > 20) return;
    // not built yet: estimate its offset from the end (~60 px per message) and retry
    final fromEnd = msgs.length - 1 - idx;
    _scroll.jumpTo((fromEnd * 60.0).clamp(0.0, _scroll.position.maxScrollExtent));
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (mounted) await _scrollToMessage(id, attempt + 1);
  }

  void _scrollToBottom() {
    final h = _app.histories[widget.channel.id];
    if (h != null && h.detached) {
      _app.returnToPresent(widget.channel.id);
    } else if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _onMention() {
    final m = _app.mentionRequest.value;
    if (m == null) return;
    _app.mentionRequest.value = null;
    _input.text = '${_input.text}$m';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  void _onScroll() {
    // reversed list: maxScrollExtent = oldest
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _app.loadOlder(widget.channel.id);
    final bottom = _scroll.position.pixels < 80;
    if (bottom != _atBottom) {
      setState(() {
        _atBottom = bottom;
        _seenCount = _app.histories[widget.channel.id]?.messages.length ?? 0;
      });
    }
  }

  void _send() {
    final text = _input.text.trim();
    final ch = widget.channel.id;
    final ups = _editing == null ? _app.files.composer(ch) : const [];
    if (text.isEmpty && ups.isEmpty) return;
    if (text.length > kMaxMessageLength) {
      _app.toast('消息最多 $kMaxMessageLength 字');
      return;
    }
    if (ups.isNotEmpty && !_app.files.readyToSend(ch)) {
      _app.toast(ups.any((u) => u.error != null) ? '有附件上传失败，请重试或移除' : '附件还在上传，请稍候');
      return;
    }
    if (_editing != null) {
      if (text != _editing!.text) _app.editMessage(_editing!, text);
      _editing = null;
    } else {
      _app.sendMessage(ch, text, reply: _replyTo?.id ?? 0, attachments: _app.files.take(ch));
      _replyTo = null;
    }
    _input.clear();
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _startEdit(Message m) {
    setState(() {
      _editing = m;
      _replyTo = null;
      _input.text = m.text;
      _input.selection = TextSelection.collapsed(offset: m.text.length);
    });
    _focus.requestFocus();
  }

  Future<void> _pickFiles() async {
    final fs = await openFiles();
    if (fs.isEmpty) return;
    await _app.files.add(widget.channel.id, [for (final f in fs) f.path]);
  }

  /// Ctrl+V: files copied in Explorer or an image on the clipboard.
  Future<bool> _paste() async {
    if (!widget.channel.can(Perm.attachFiles)) return false;
    final paths = await clipboardFiles();
    if (paths.isNotEmpty) {
      await _app.files.add(widget.channel.id, paths);
      return true;
    }
    final png = await clipboardImagePng();
    if (png != null) {
      await _app.files.addBytes(widget.channel.id, png, '粘贴的图片.png');
      return true;
    }
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.keyV && HardwareKeyboard.instance.isControlPressed) {
      // text paste keeps working: only intercept when the clipboard has files / an image
      _paste();
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && (_editing != null || _replyTo != null)) {
      setState(() {
        if (_editing != null) _input.clear();
        _editing = null;
        _replyTo = null;
      });
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && _input.text.isEmpty) {
      final mine = _app.histories[widget.channel.id]?.messages.where((m) => m.uid == _app.me && !m.pending).toList();
      if (mine != null && mine.isNotEmpty) {
        _startEdit(mine.last);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final h = app.histories[widget.channel.id];
    final msgs = h?.messages ?? const <Message>[];
    final typing = app.typingIn(widget.channel.id);
    final newer = _atBottom ? 0 : (msgs.length - _seenCount).clamp(0, 999);
    final detached = h?.detached ?? false;
    final showJump = detached || !_atBottom;
    final loud = detached || newer > 0;
    final canSend = widget.channel.can(Perm.sendMessages);
    final canAttach = canSend && widget.channel.can(Perm.attachFiles);
    final title = app.channelTitle(widget.channel);
    return DropTarget(
      enable: canAttach,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        app.files.add(widget.channel.id, [for (final f in d.files) f.path]);
      },
      child: Stack(children: [
        _body(app, t, h, msgs, typing, newer, detached, showJump, loud, canSend, canAttach, title),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: t.chat.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(12)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.upload_file, size: 48, color: t.onAccent),
                    const SizedBox(height: 8),
                    Text('上传到 ${widget.channel.isDm ? '@' : '#'}$title', style: TextStyle(color: t.onAccent, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('单个文件最大 ${formatBytes(app.files.maxBytes)} · 保留 ${app.fileDays} 天', style: TextStyle(color: t.onAccent.withValues(alpha: 0.8))),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _body(AppState app, PulseTheme t, ChannelHistory? h, List<Message> msgs, List<Member> typing, int newer, bool detached, bool showJump,
      bool loud, bool canSend, bool canAttach, String title) {
    final ups = app.files.composer(widget.channel.id);
    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            itemCount: msgs.length + 1,
            itemBuilder: (context, i) {
              if (i == msgs.length) return _header(t, h);
              final idx = msgs.length - 1 - i;
              final m = msgs[idx];
              final prev = idx > 0 ? msgs[idx - 1] : null;
              final grouped = prev != null && prev.uid == m.uid && m.reply == 0 && (m.ts - prev.ts) < 5 * 60 * 1000;
              final newDay = prev == null || !_sameDay(prev.ts, m.ts);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (newDay) _DayDivider(m.ts),
                _MessageTile(
                  m,
                  key: m.id > 0 ? _keys.putIfAbsent(m.id, GlobalKey.new) : null,
                  flash: m.id == _flash,
                  grouped: grouped && !newDay,
                  onReply: () {
                    setState(() {
                      _replyTo = m;
                      _editing = null;
                    });
                    _focus.requestFocus();
                  },
                  onEdit: () => _startEdit(m),
                ),
              ]);
            },
          ),
            ),
          ),
          if (showJump)
            Positioned(
              left: 16,
              right: 16,
              bottom: 8,
              child: Center(
                child: Material(
                  color: loud ? t.accent : t.rail,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _scrollToBottom,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.arrow_downward, size: 16, color: loud ? t.onAccent : t.text),
                        const SizedBox(width: 6),
                        Text(
                          detached ? '正在查看较早的消息 · 回到最新' : (newer > 0 ? '$newer 条新消息' : '回到最新'),
                          style: TextStyle(color: loud ? t.onAccent : t.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      if (_replyTo != null || _editing != null) _contextBar(app, t),
      if (ups.isNotEmpty && _editing == null) UploadTray(ups),
      if (!canSend)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.input, borderRadius: BorderRadius.circular(8)),
            child: Text('你没有在此频道发送消息的权限', style: TextStyle(color: t.muted)),
          ),
        )
      else
      Padding(
        padding: EdgeInsets.fromLTRB(16, (_replyTo != null || _editing != null) ? 0 : 4, 16, 2),
        child: Container(
          decoration: BoxDecoration(
            color: t.input,
            borderRadius: (_replyTo != null || _editing != null) ? const BorderRadius.vertical(bottom: Radius.circular(8)) : BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (canAttach && _editing == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: BarButton(Icons.add_circle, '上传文件（也可拖入或 Ctrl+V 粘贴）', _pickFiles),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _EmojiButton(onPick: (e) {
                final sel = _input.selection;
                final pos = sel.isValid ? sel.start : _input.text.length;
                _input.text = _input.text.replaceRange(pos, sel.isValid ? sel.end : pos, e);
                _input.selection = TextSelection.collapsed(offset: pos + e.length);
                _focus.requestFocus();
              }),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) {
                    app.sendTyping(widget.channel.id);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: _editing != null ? '编辑消息' : (widget.channel.isDm ? '发送私信给 @$title' : '发送消息到 #$title'),
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
                  ),
                ),
              ),
            ),
            if (_input.text.length > kMaxMessageLength - 200)
              Padding(
                padding: const EdgeInsets.only(bottom: 14, right: 6),
                child: Text('${kMaxMessageLength - _input.text.length}',
                    style: TextStyle(color: _input.text.length > kMaxMessageLength ? t.danger : t.muted, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: BarButton(Icons.send, '发送 (Enter)', _input.text.trim().isEmpty && ups.isEmpty ? null : _send,
                  color: _input.text.trim().isEmpty && ups.isEmpty ? t.muted.withValues(alpha: 0.4) : t.accent),
            ),
          ]),
        ),
      ),
      SizedBox(
        height: 22,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            if (typing.isNotEmpty) ...[
              const _TypingDots(),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  typing.length > 3 ? '好几个人正在输入…' : '${typing.map((m) => m.display).join('、')} 正在输入…',
                  style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _contextBar(AppState app, PulseTheme t) {
    final editing = _editing != null;
    final author = _replyTo == null ? null : app.members[_replyTo!.uid];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Color.lerp(t.input, t.rail, 0.35),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Row(children: [
          Icon(editing ? Icons.edit : Icons.reply, size: 16, color: t.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(editing ? '正在编辑消息 · Esc 取消 · Enter 保存' : '回复 ${author?.display ?? ''}',
                style: TextStyle(color: t.muted, fontSize: 12.5), overflow: TextOverflow.ellipsis),
          ),
          InkWell(
            onTap: () => setState(() {
              if (editing) _input.clear();
              _editing = null;
              _replyTo = null;
            }),
            child: Icon(Icons.cancel, size: 18, color: t.muted),
          ),
        ]),
      ),
    );
  }

  Widget _header(PulseTheme t, ChannelHistory? h) {
    if (h == null || !h.loaded || h.loading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (h.more) return const SizedBox(height: 40);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.channel.isDm) ...[
          Avatar(_app.dmPartner(widget.channel), size: 68),
          const SizedBox(height: 12),
          Text(_app.channelTitle(widget.channel), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: t.text)),
          const SizedBox(height: 4),
          Text('这是你与 ${_app.channelTitle(widget.channel)} 私信的开始。私信只有你们两人可见。', style: TextStyle(color: t.muted)),
        ] else ...[
          CircleAvatar(radius: 34, backgroundColor: t.hover, child: Icon(Icons.tag, size: 40, color: t.text)),
          const SizedBox(height: 12),
          Text('欢迎来到 #${widget.channel.name}！', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: t.text)),
          const SizedBox(height: 4),
          Text(widget.channel.topic.isNotEmpty ? widget.channel.topic : '这是 #${widget.channel.name} 频道的开始。', style: TextStyle(color: t.muted)),
        ],
      ]),
    );
  }

  static bool _sameDay(int a, int b) {
    final x = DateTime.fromMillisecondsSinceEpoch(a), y = DateTime.fromMillisecondsSinceEpoch(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _DayDivider extends StatelessWidget {
  final int ts;
  const _DayDivider(this.ts);
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Expanded(child: Divider(color: t.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('${d.year}年${d.month}月${d.day}日', style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Divider(color: t.divider)),
      ]),
    );
  }
}

class _MessageTile extends StatefulWidget {
  final Message m;
  final bool grouped, flash;
  final VoidCallback onReply, onEdit;
  const _MessageTile(this.m, {super.key, required this.grouped, required this.onReply, required this.onEdit, this.flash = false});
  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final m = widget.m;
    final author = app.members[m.uid];
    final mention = m.uid != app.me && app.mentionsMe(m.text, everyone: m.everyone);
    final compact = app.settings.compact;
    final reply = m.reply > 0 ? app.histories[m.ch]?.messages.where((x) => x.id == m.reply).firstOrNull : null;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (m.text.isNotEmpty || m.attachments.isEmpty) _RichText(m.text, pending: m.pending, edited: m.edited > 0),
      if (m.attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final a in m.attachments) AttachmentView(a)]),
        ),
      if (m.reactions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in m.reactions.entries) _ReactionChip(m, e.key, e.value),
          ]),
        ),
    ]);
    Widget content;
    if (widget.grouped) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 56,
          child: _hover
              ? Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(formatTime(m.ts).split(' ').last, style: TextStyle(color: t.muted, fontSize: 10.5), textAlign: TextAlign.center),
                )
              : null,
        ),
        Expanded(child: body),
      ]);
    } else {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (reply != null || m.reply > 0)
          GestureDetector(
            onTap: () => app.jumpToMessage(m.ch, m.reply),
            child: MouseRegion(cursor: SystemMouseCursors.click, child: _ReplyPreview(reply)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: GestureDetector(
              onTap: author == null ? null : () => showProfileCard(context, app, author),
              child: Avatar(author, size: compact ? 0.1 : 40),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Flexible(
                  child: GestureDetector(
                    onTap: author == null ? null : () => showProfileCard(context, app, author),
                    child: Text(author?.display ?? '已删除的用户',
                        overflow: TextOverflow.ellipsis, style: TextStyle(color: nameColor(context, author), fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
                if (author != null && author.role >= Role.admin)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(author.role == Role.owner ? Icons.workspace_premium : Icons.shield, size: 13, color: nameColor(context, author)),
                  )
                else if (author != null && app.hoistRole(author) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: RoleChip(app.hoistRole(author)!, small: true),
                  ),
                const SizedBox(width: 8),
                Text(formatTime(m.ts, seconds: app.settings.showSeconds), style: TextStyle(color: t.muted, fontSize: 11.5)),
                if (m.pinned) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.push_pin, size: 12, color: t.muted)),
              ]),
              const SizedBox(height: 2),
              body,
            ]),
          ),
        ]),
      ]);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapUp: m.pending ? null : (d) => _menu(context, app, d.globalPosition),
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(top: widget.grouped ? 0 : (compact ? 4 : 14)),
            padding: const EdgeInsets.only(left: 8, right: 48, top: 2, bottom: 2),
            decoration: BoxDecoration(
              color: widget.flash
                  ? t.accent.withValues(alpha: 0.22)
                  : mention
                      ? t.idle.withValues(alpha: 0.10)
                      : (_hover ? t.hover.withValues(alpha: 0.35) : null),
              border: mention ? Border(left: BorderSide(color: t.idle, width: 2)) : null,
            ),
            child: content,
          ),
          if (_hover && !m.pending) Positioned(right: 16, top: widget.grouped ? -14 : 0, child: _actions(app, t)),
        ]),
      ),
    );
  }

  bool _canManage(AppState app) {
    final ch = app.channels[widget.m.ch];
    return ch != null && !ch.isDm && ch.can(Perm.manageMessages);
  }

  Widget _actions(AppState app, PulseTheme t) {
    final m = widget.m;
    final mine = m.uid == app.me;
    final canReact = app.channels[m.ch]?.can(Perm.addReactions) ?? false;
    return Container(
      decoration: BoxDecoration(
        color: t.chat,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.divider),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canReact) ...[
          for (final e in kQuickReactions.take(3))
            InkWell(onTap: () => app.react(m, e), child: Padding(padding: const EdgeInsets.all(5), child: Text(e, style: const TextStyle(fontSize: 16)))),
          _EmojiButton(onPick: (e) => app.react(m, e), icon: Icons.add_reaction_outlined),
        ],
        BarButton(Icons.reply, '回复', widget.onReply),
        if (mine && m.text.isNotEmpty) BarButton(Icons.edit, '编辑', widget.onEdit),
        if (mine || _canManage(app)) BarButton(Icons.delete_outline, '删除', () => _delete(app), color: t.danger),
      ]),
    );
  }

  Future<void> _delete(AppState app) async {
    if (HardwareKeyboard.instance.isShiftPressed || await confirm(context, '删除消息', '确定要删除这条消息吗？（按住 Shift 点击可跳过确认）', ok: '删除', danger: true)) {
      app.deleteMessage(widget.m);
    }
  }

  void _menu(BuildContext context, AppState app, Offset pos) {
    final m = widget.m;
    final mine = m.uid == app.me;
    final ch = app.channels[m.ch];
    final canPin = mine || _canManage(app) || (ch?.isDm ?? false);
    showContextMenu(context, pos, [
      menuItem('回复', widget.onReply, icon: Icons.reply),
      if (mine && m.text.isNotEmpty) menuItem('编辑', widget.onEdit, icon: Icons.edit),
      if (m.text.isNotEmpty) menuItem('复制文本', () => copyText(context, m.text), icon: Icons.copy),
      for (final a in m.attachments)
        if (!a.expired) menuItem('下载 ${a.name}', () => app.files.download(a), icon: Icons.download),
      if (canPin) menuItem(m.pinned ? '取消置顶' : '置顶消息', () => app.setPinned(m, !m.pinned), icon: Icons.push_pin_outlined),
      if (ch?.can(Perm.addReactions) ?? false)
        for (final e in kQuickReactions) menuItem('回应 $e', () => app.react(m, e)),
      if (mine || _canManage(app)) menuItem('删除消息', () => _delete(app), icon: Icons.delete_outline, danger: true),
    ]);
  }
}

class _ReplyPreview extends StatelessWidget {
  final Message? reply;
  const _ReplyPreview(this.reply);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final r = reply;
    final a = r == null ? null : app.members[r.uid];
    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 2),
      child: Row(children: [
        Container(width: 26, height: 10, margin: const EdgeInsets.only(top: 8, right: 4),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: t.muted, width: 2), top: BorderSide(color: t.muted, width: 2)),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)))),
        if (r == null)
          Text('原消息未加载或已删除', style: TextStyle(color: t.muted, fontSize: 12.5, fontStyle: FontStyle.italic))
        else ...[
          Avatar(a, size: 16),
          const SizedBox(width: 4),
          Text(a?.display ?? '?', style: TextStyle(color: nameColor(context, a), fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Flexible(
              child: Text(r.text.isEmpty && r.attachments.isNotEmpty ? '[附件] ${r.attachments.first.name}' : r.text.replaceAll('\n', ' '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5))),
        ],
      ]),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final Message m;
  final String e;
  final List<int> uids;
  const _ReactionChip(this.m, this.e, this.uids);
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final mine = uids.contains(app.me);
    final names = uids.map((u) => app.members[u]?.display ?? '?').take(10).join('、');
    return Tooltip(
      message: names,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => app.react(m, e),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: mine ? t.accent.withValues(alpha: 0.18) : t.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: mine ? t.accent : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(e, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text('${uids.length}', style: TextStyle(color: mine ? t.accent : t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Message text with clickable links, `inline code`, ```code blocks```, **bold** and @mentions.
class _RichText extends StatelessWidget {
  final String text;
  final bool pending, edited;
  const _RichText(this.text, {required this.pending, required this.edited});

  static final _token = RegExp(r'```([\s\S]*?)```|`([^`\n]+)`|\*\*([^*\n]+)\*\*|(https?://[^\s<>"]+)|(@[\w.\-一-鿿]+)');

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final base = TextStyle(color: pending ? t.muted : t.text, fontSize: 15, height: 1.4);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final mt in _token.allMatches(text)) {
      if (mt.start > last) spans.add(TextSpan(text: text.substring(last, mt.start)));
      if (mt.group(1) != null) {
        spans.add(WidgetSpan(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(4), border: Border.all(color: t.divider)),
            child: Text(mt.group(1)!.replaceFirst(RegExp(r'^\w*\n'), ''), style: TextStyle(fontFamily: 'Consolas', fontSize: 13.5, color: t.text)),
          ),
        ));
      } else if (mt.group(2) != null) {
        spans.add(TextSpan(
          text: mt.group(2),
          style: TextStyle(fontFamily: 'Consolas', fontSize: 13.5, backgroundColor: t.rail),
        ));
      } else if (mt.group(3) != null) {
        spans.add(TextSpan(text: mt.group(3), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (mt.group(4) != null) {
        final url = mt.group(4)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openLink(context, url),
              child: Text(url, style: base.copyWith(color: const Color(0xFF00A8FC), decoration: TextDecoration.underline)),
            ),
          ),
        ));
      } else {
        final name = mt.group(5)!.substring(1);
        final isMe = app.myMember != null && (name == app.myMember!.username || name == app.myMember!.display || name == 'everyone' || name == '全体');
        final known = isMe || app.members.values.any((m) => m.username == name || m.display == name) || app.roles.values.any((r) => r.name == name);
        spans.add(TextSpan(
          text: mt.group(5),
          style: known ? TextStyle(color: t.accent, backgroundColor: t.accent.withValues(alpha: 0.15), fontWeight: FontWeight.w600) : null,
        ));
      }
      last = mt.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (edited) spans.add(TextSpan(text: ' (已编辑)', style: TextStyle(color: t.muted, fontSize: 11)));
    return Text.rich(TextSpan(style: base, children: spans));
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    // never open links silently: show the real target first (anti-phishing)
    if (await confirm(context, '打开外部链接', '即将在浏览器中打开：\n\n${uri.toString()}\n\n请确认你信任这个网站。', ok: '打开')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: t.text.withValues(alpha: 0.3 + 0.7 * ((_c.value * 3 - i) % 3 < 1 ? 1 : 0)),
              shape: BoxShape.circle,
            ),
          ),
      ]),
    );
  }
}

const _emojis = [
  '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😋', '😛', '😜', '🤪', '🤗', '🤔', '🤨', '😐',
  '😑', '😶', '🙄', '😏', '😣', '😥', '😮', '😯', '😪', '😫', '🥱', '😴', '😌', '😓', '😔', '😕', '🙃', '🤑', '😲', '😖', '😞', '😟', '😤', '😢',
  '😭', '😦', '😧', '😨', '😩', '🤯', '😬', '😰', '😱', '🥵', '🥶', '😳', '🤪', '😵', '😡', '😠', '🤬', '😷', '🤒', '🤕', '🤢', '🤮', '😎', '🤓',
  '🧐', '😈', '👿', '👹', '💀', '👻', '👽', '🤖', '💩', '😺', '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '👏', '🙌', '👐', '🙏', '💪', '❤️', '🧡',
  '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💯', '🔥', '✨', '⭐', '🎉', '🎊', '🎮', '🏆', '⚽', '🍕', '🍔', '🍟', '☕', '🍺', '🍻', '👀', '💤',
];

class _EmojiButton extends StatelessWidget {
  final void Function(String) onPick;
  final IconData icon;
  const _EmojiButton({required this.onPick, this.icon = Icons.emoji_emotions_outlined});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return BarButton(icon, '表情', () async {
      final box = context.findRenderObject() as RenderBox;
      final pos = box.localToGlobal(Offset.zero);
      final r = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(pos.dx, pos.dy - 300, pos.dx + 1, pos.dy),
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 300),
        items: [
          PopupMenuItem<String>(
            enabled: false,
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 320,
              height: 280,
              child: GridView.count(
                crossAxisCount: 8,
                children: [
                  for (final e in _emojis)
                    InkWell(
                      onTap: () => Navigator.pop(context, e),
                      child: Center(child: Text(e, style: TextStyle(fontSize: 22, color: t.text))),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
      if (r != null) onPick(r);
    });
  }
}
