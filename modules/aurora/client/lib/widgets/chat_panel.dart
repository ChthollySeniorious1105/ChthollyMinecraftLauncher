import 'package:flutter/material.dart';

import '../main.dart';
import 'common.dart';

/// Text chat list + input, plus optional voice controls.
class ChatPanel extends StatefulWidget {
  final String title;
  final bool voice;
  const ChatPanel({super.key, this.title = '聊天', this.voice = true});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  int _lastLen = 0;

  void _send() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    AppScope.read(context).send({'t': 'chat', 'text': t});
    _ctl.clear();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    app.unreadChat = 0;
    final cs = Theme.of(context).colorScheme;
    if (app.chat.length != _lastLen) {
      _lastLen = app.chat.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            tooltip: '语音音量调节',
            visualDensity: VisualDensity.compact,
            onPressed: () => showVolumeDialog(context),
            icon: Icon(Icons.tune, size: 20, color: cs.primary),
          ),
          if (widget.voice) const VoiceControls(),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: app.chat.length,
          itemBuilder: (context, i) {
            final l = app.chat[i];
            if (l.system) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('· ${l.text}',
                    style: TextStyle(fontSize: 12, color: cs.secondary, fontStyle: FontStyle.italic)),
              );
            }
            final mine = l.from == app.myId;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Avatar(l.avatar, size: 28),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: mine ? cs.primary.withValues(alpha: 0.85) : cs.surfaceContainerHighest.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(l.text,
                              style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 30),
                ],
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              maxLength: 500,
              decoration: const InputDecoration(hintText: '说点什么…', counterText: ''),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(onPressed: _send, icon: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }
}

class VoiceControls extends StatelessWidget {
  const VoiceControls({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final v = app.voice;
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (v.error != null)
            Tooltip(message: v.error!, child: Icon(Icons.error_outline, color: cs.error, size: 18)),
          if (v.micOn && v.pushToTalk)
            Listener(
              onPointerDown: (_) {
                v.setPtt(true);
              },
              onPointerUp: (_) {
                v.setPtt(false);
              },
              onPointerCancel: (_) {
                v.setPtt(false);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: v.pttHeld ? Colors.green : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('按住说话', style: TextStyle(fontSize: 12)),
              ),
            ),
          IconButton(
            tooltip: v.micOn ? '关闭麦克风' : '开启麦克风',
            visualDensity: VisualDensity.compact,
            onPressed: () => v.setMic(!v.micOn),
            icon: Icon(v.micOn ? Icons.mic : Icons.mic_off,
                color: v.micOn ? (v.speaking ? Colors.greenAccent : cs.primary) : cs.onSurface.withValues(alpha: 0.5)),
          ),
          // tap = mute speaker, long-press / right-click = volume sliders
          GestureDetector(
            onLongPress: () => showVolumeDialog(context),
            onSecondaryTap: () => showVolumeDialog(context),
            child: IconButton(
              tooltip: v.deafened ? '开启扬声器（长按/右键：音量调节）' : '关闭扬声器（长按/右键：音量调节）',
              visualDensity: VisualDensity.compact,
              onPressed: () => v.setDeafened(!v.deafened),
              icon: Icon(v.deafened ? Icons.headset_off : Icons.headset,
                  color: v.deafened ? cs.error : cs.primary),
            ),
          ),
        ]);
      },
    );
  }
}

/// Quick popup with the microphone / speaker volume sliders.
void showVolumeDialog(BuildContext context) {
  showDialog<void>(useRootNavigator: false, 
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('音量调节'),
      content: const SizedBox(width: 360, child: VolumeSliders()),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('完成'))],
    ),
  );
}

/// 麦克风输入 / 扬声器输出 volume sliders (saved to preferences), plus a live
/// input level meter while the microphone is on.
class VolumeSliders extends StatelessWidget {
  const VolumeSliders({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final v = app.voice;
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        Widget row(IconData icon, String label, double value, double max, ValueChanged<double> onChanged) => Row(children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              SizedBox(width: 72, child: Text(label)),
              Expanded(
                child: Slider(
                  value: value.clamp(0.0, max),
                  min: 0,
                  max: max,
                  divisions: (max * 20).round(),
                  label: '${(value * 100).round()}%',
                  onChanged: onChanged,
                ),
              ),
              SizedBox(width: 44, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end)),
            ]);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row(v.inputGain == 0 ? Icons.mic_off : Icons.mic, '麦克风输入', v.inputGain, 3, app.setInputGain),
          Padding(
            padding: const EdgeInsets.only(left: 108, right: 52),
            child: ValueListenableBuilder<double>(
              valueListenable: v.micLevel,
              builder: (_, lv, _) => ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: v.micOn ? lv.clamp(0.0, 1.0) : 0,
                  minHeight: 6,
                  color: lv > 0.9 ? cs.error : Colors.green,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 108, top: 2),
            child: Text(v.micOn ? '说话时绿条跳动；变红表示过载，请调低' : '开启麦克风后可在此查看输入电平',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          const SizedBox(height: 8),
          row(v.outputVolume == 0 ? Icons.volume_off : Icons.volume_up, '扬声器输出', v.outputVolume, 2, app.setOutputVolume),
        ]);
      },
    );
  }
}
