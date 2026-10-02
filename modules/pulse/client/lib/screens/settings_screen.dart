import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../native/native.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../theme/themes.dart';
import '../widgets/avatar_editor.dart';
import '../widgets/common.dart';

/// Full-screen settings (Discord style: category list on the left).
class SettingsScreen extends StatefulWidget {
  final int initialTab;
  const SettingsScreen({super.key, this.initialTab = 0});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _tab = widget.initialTab;

  static const _tabs = [
    (Icons.person, '我的账号'),
    (Icons.mic, '语音与音频'),
    (Icons.auto_fix_high, '变声器（GPU）'),
    (Icons.keyboard, '快捷键'),
    (Icons.palette, '外观与主题'),
    (Icons.notifications, '通知'),
    (Icons.info_outline, '关于'),
  ];

  @override
  void dispose() {
    final app = AppScope.read(context);
    if (app.micTest) app.setMicTest(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: t.chat,
          body: Row(children: [
            Expanded(
              flex: 2,
              child: ColoredBox(
                color: t.sidebar,
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: 220,
                    child: ListView(padding: const EdgeInsets.fromLTRB(0, 60, 8, 20), children: [
                      const SectionLabel('用户设置'),
                      for (var i = 0; i < _tabs.length; i++)
                        HoverTile(
                          selected: _tab == i,
                          onTap: () => setState(() => _tab = i),
                          child: Row(children: [
                            Icon(_tabs[i].$1, size: 18, color: _tab == i ? t.text : t.muted),
                            const SizedBox(width: 10),
                            Text(_tabs[i].$2, style: TextStyle(color: _tab == i ? t.text : t.muted, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Stack(children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 740,
                    child: ListView(padding: const EdgeInsets.fromLTRB(40, 60, 40, 60), children: [
                      Text(_tabs[_tab].$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 20),
                      switch (_tab) {
                        0 => const _AccountTab(),
                        1 => const _AudioTab(),
                        2 => const _VoiceChangerTab(),
                        3 => const _HotkeyTab(),
                        4 => const _AppearanceTab(),
                        5 => const _NotifyTab(),
                        _ => const _AboutTab(),
                      },
                    ]),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 50,
                  child: Column(children: [
                    IconButton.outlined(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    Text('ESC', style: TextStyle(color: t.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Set by the host launcher (CML keeps AI voices in its add-on folder so they survive updates).
String? voicesDirOverride;

// ------------------------------------------------------------------ helpers

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section(this.title, this.children, {this.subtitle});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: TextStyle(color: t.muted, fontSize: 12.5))],
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final double value, min, max;
  final int? divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const _SliderRow({required this.value, required this.min, required this.max, required this.label, required this.onChanged, this.divisions, this.onChangeEnd});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label(value),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(width: 70, child: Text(label(value), textAlign: TextAlign.right)),
      ]);
}

/// Runs a settings change and always repaints the page that owns [context] right away,
/// even if the handler throws (the error is logged). Settings controls must not depend
/// on an app-wide notification to redraw: if that path is skipped the control looks
/// "dead" until something else (e.g. switching windows) triggers a rebuild.
void _apply(BuildContext context, VoidCallback change) {
  try {
    change();
  } catch (e, st) {
    AppScope.read(context).logEvent('settings handler error: $e\n$st');
  } finally {
    if (context.mounted) (context as Element).markNeedsBuild();
  }
}

Widget _switch(BuildContext context, String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) {
  final t = PulseColors.of(context);
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: TextStyle(color: t.text, fontSize: 14.5)),
    subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: t.muted, fontSize: 12.5)),
    value: value,
    onChanged: (v) => _apply(context, () => onChanged(v)),
  );
}

// ------------------------------------------------------------------ account

class _AccountTab extends StatefulWidget {
  const _AccountTab();
  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  late final AppState app = AppScope.read(context);
  late final _display = TextEditingController(text: app.myMember?.display ?? '');
  late final _bio = TextEditingController(text: app.myMember?.bio ?? '');
  final _old = TextEditingController(), _new = TextEditingController(), _new2 = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final m = app.myMember;
    if (!app.authed || m == null) return Text('登录服务器后可以编辑个人资料。', style: TextStyle(color: t.muted));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: t.sidebar, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          AvatarEditButton(m, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.display, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: nameColor(context, m))),
              Text('${m.username} · ${m.role == Role.owner ? '服主' : (m.roles.isEmpty ? '成员' : app.sortedRoles.where((r) => m.roles.contains(r.id)).map((r) => r.name).join('、'))} · ${app.serverName}', style: TextStyle(color: t.muted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      _Section('昵称', [
        Row(children: [
          Expanded(child: TextField(controller: _display, maxLength: 32)),
          const SizedBox(width: 10),
          FilledButton(onPressed: () => app.updateProfile(display: _display.text.trim()), child: const Text('保存')),
        ]),
      ]),
      _Section('关于我', [
        TextField(controller: _bio, maxLength: 190, maxLines: 3),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => app.updateProfile(bio: _bio.text.trim()), child: const Text('保存'))),
      ]),
      _Section('头像', subtitle: '上传图片作为头像（自动裁成正方形）；没有图片时显示下面选择的颜色和名字首字', [
        Row(children: [
          FilledButton.icon(onPressed: () => showAvatarEditor(context), icon: const Icon(Icons.image, size: 18), label: const Text('上传头像…')),
          const SizedBox(width: 10),
          if (m.avatarHash.isNotEmpty)
            OutlinedButton(
              onPressed: () => app.uploadAvatar(null),
              style: OutlinedButton.styleFrom(foregroundColor: t.danger),
              child: const Text('移除图片头像'),
            ),
        ]),
      ]),
      _Section('自定义状态', subtitle: '显示在成员列表和个人资料卡上', [const _StatusEditor()]),
      _Section('头像颜色', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < avatarColors.length; i++)
            InkWell(
              onTap: () => app.updateProfile(avatar: i),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: avatarColors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: m.avatar == i ? t.text : Colors.transparent, width: 3),
                ),
              ),
            ),
        ]),
      ]),
      _Section('名字颜色', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in accentPresets)
            InkWell(
              onTap: () => app.updateProfile(color: c),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c == 0 ? t.input : Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: m.color == c ? t.text : Colors.transparent, width: 3),
                ),
                child: c == 0 ? Icon(Icons.block, size: 16, color: t.muted) : null,
              ),
            ),
        ]),
      ]),
      _Section('修改密码', subtitle: '修改后其他设备上的登录会失效', [
        TextField(controller: _old, obscureText: true, decoration: const InputDecoration(hintText: '当前密码')),
        const SizedBox(height: 8),
        TextField(controller: _new, obscureText: true, decoration: const InputDecoration(hintText: '新密码（至少 8 位）')),
        const SizedBox(height: 8),
        TextField(controller: _new2, obscureText: true, decoration: const InputDecoration(hintText: '确认新密码')),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () {
            final err = validatePassword(_new.text);
            if (err != null) return app.toast(err);
            if (_new.text != _new2.text) return app.toast('两次输入的新密码不一致');
            app.send({'t': Msg.changePassword, 'old': _old.text, 'new': _new.text});
            _old.clear();
            _new.clear();
            _new2.clear();
          },
          child: const Text('修改密码'),
        ),
      ]),
      _Section('登录', [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: t.danger),
          onPressed: () async {
            Navigator.pop(context);
            await app.disconnect(logout: true);
          },
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ]),
    ]);
  }
}

class _StatusEditor extends StatefulWidget {
  const _StatusEditor();
  @override
  State<_StatusEditor> createState() => _StatusEditorState();
}

class _StatusEditorState extends State<_StatusEditor> {
  late final AppState app = AppScope.read(context);
  late final _text = TextEditingController(text: app.myMember?.statusText ?? '');
  late String _emoji = app.myMember?.statusEmoji ?? '';
  int _clearMin = 0; // 0 = never

  static const _emojis = ['', '🎮', '💻', '📚', '🎧', '😴', '🍜', '🏃', '🚗', '🎬', '🔕', '🎉'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        PopupMenuButton<String>(
          tooltip: '选择图标',
          initialValue: _emoji,
          onSelected: (e) => setState(() => _emoji = e),
          itemBuilder: (_) => [
            for (final e in _emojis) PopupMenuItem(value: e, height: 36, child: Text(e.isEmpty ? '（无）' : e, style: const TextStyle(fontSize: 18))),
          ],
          child: Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.input, borderRadius: BorderRadius.circular(6)),
            child: Text(_emoji.isEmpty ? '🙂' : _emoji, style: TextStyle(fontSize: 18, color: _emoji.isEmpty ? t.muted : null)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _text, maxLength: 64, decoration: const InputDecoration(hintText: '例如：开黑中，晚上 10 点后在线', counterText: ''))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Text('自动清除：', style: TextStyle(color: t.muted)),
        DropdownButton<int>(
          value: _clearMin,
          items: const [
            DropdownMenuItem(value: 0, child: Text('不清除')),
            DropdownMenuItem(value: 30, child: Text('30 分钟后')),
            DropdownMenuItem(value: 60, child: Text('1 小时后')),
            DropdownMenuItem(value: 240, child: Text('4 小时后')),
            DropdownMenuItem(value: 1440, child: Text('明天')),
          ],
          onChanged: (v) => setState(() => _clearMin = v ?? 0),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            _text.clear();
            setState(() => _emoji = '');
            app.setStatusText('', '');
          },
          child: const Text('清除'),
        ),
        FilledButton(
          onPressed: () => app.setStatusText(_text.text.trim(), _emoji, clearAfter: _clearMin == 0 ? null : Duration(minutes: _clearMin)),
          child: const Text('保存状态'),
        ),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ audio

class _AudioTab extends StatefulWidget {
  const _AudioTab();
  @override
  State<_AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<_AudioTab> {
  List<AudioDevice> _inputs = [], _outputs = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final app = AppScope.read(context);
    setState(() {
      _inputs = app.native.devices(capture: true);
      _outputs = app.native.devices(capture: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final s = app.settings;
    if (!app.native.available) {
      return Text('音频引擎不可用：${app.native.loadError}', style: TextStyle(color: t.danger));
    }
    Widget devicePicker(bool capture) {
      final list = capture ? _inputs : _outputs;
      final cur = capture ? s.inputDevice : s.outputDevice;
      final ids = {'', ...list.map((d) => d.id)};
      return DropdownButtonFormField<String>(
        initialValue: ids.contains(cur) ? cur : '',
        isExpanded: true,
        items: [
          DropdownMenuItem(value: '', child: Text('系统默认（${list.where((d) => d.isDefault).map((d) => d.name).firstOrNull ?? '—'}）')),
          for (final d in list) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (capture) {
            s.inputDevice = v ?? '';
          } else {
            s.outputDevice = v ?? '';
          }
          app.native.setDevice(capture: capture, id: v ?? '');
          app.savePrefs();
        },
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _Section('输入设备', [
            devicePicker(true),
            const SizedBox(height: 14),
            Text('输入音量', style: TextStyle(color: t.muted, fontSize: 12.5)),
            _SliderRow(
              value: s.inputGain,
              min: 0,
              max: 4,
              divisions: 80,
              label: (v) => '${(v * 100).round()}%',
              onChanged: (v) {
                s.inputGain = v;
                app.native.setInputGain(v);
                setState(() {});
              },
              onChangeEnd: (_) => app.savePrefs(),
            ),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _Section('输出设备', [
            devicePicker(false),
            const SizedBox(height: 14),
            Text('输出音量', style: TextStyle(color: t.muted, fontSize: 12.5)),
            _SliderRow(
              value: s.outputVolume,
              min: 0,
              max: 2,
              divisions: 40,
              label: (v) => '${(v * 100).round()}%',
              onChanged: (v) {
                s.outputVolume = v;
                app.native.setOutputVolume(v);
                setState(() {});
              },
              onChangeEnd: (_) => app.savePrefs(),
            ),
          ]),
        ),
      ]),
      Row(children: [
        TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新设备列表')),
        const SizedBox(width: 12),
        TextButton.icon(onPressed: () => app.native.playSound(Sound.test), icon: const Icon(Icons.volume_up, size: 18), label: const Text('播放测试音')),
      ]),
      const SizedBox(height: 12),
      _Section('麦克风测试', subtitle: '开启后你会听到自己经过降噪/变声处理后的声音（建议戴耳机）', [
        Row(children: [
          FilledButton(
            onPressed: () => app.setMicTest(!app.micTest),
            style: app.micTest ? FilledButton.styleFrom(backgroundColor: t.danger, foregroundColor: Colors.white) : null,
            child: Text(app.micTest ? '停止测试' : '开始测试'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: app.meterTick,
              builder: (_, _, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LevelMeter(app.levels[0], active: app.levels.length > 4 && app.levels[4] > 0),
                const SizedBox(height: 4),
                Text(app.levels.length > 4 && app.levels[4] > 0 ? '● 正在发送' : '○ 未发送',
                    style: TextStyle(color: app.levels.length > 4 && app.levels[4] > 0 ? t.online : t.muted, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ]),
      _Section('输入模式', [
        RadioGroup<int>(
          groupValue: s.inputMode,
          onChanged: (v) {
            s.inputMode = v ?? InputMode.vad;
            app.native.setInputMode(s.inputMode);
            app.savePrefs();
          },
          child: Column(children: [
            const RadioListTile(contentPadding: EdgeInsets.zero, value: InputMode.vad, title: Text('语音激活'), subtitle: Text('检测到说话时自动发送')),
            RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: InputMode.ptt,
                title: const Text('按键说话'),
                subtitle: Text('按住全局快捷键时发送（当前：${_bindingText(app, s.pttKey)}，在“快捷键”页修改）')),
            const RadioListTile(contentPadding: EdgeInsets.zero, value: InputMode.open, title: Text('持续开麦'), subtitle: Text('始终发送（不推荐，除非环境很安静）')),
          ]),
        ),
        if (s.inputMode == InputMode.vad) ...[
          const SizedBox(height: 6),
          Text('语音激活灵敏度（越靠右越不容易被触发）', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.vadThreshold,
            min: 0.05,
            max: 0.95,
            divisions: 18,
            label: (v) => '${(v * 100).round()}',
            onChanged: (v) {
              s.vadThreshold = v;
              app.native.setVadThreshold(v);
              setState(() {});
            },
            onChangeEnd: (_) => app.savePrefs(),
          ),
          ValueListenableBuilder<int>(
            valueListenable: app.meterTick,
            builder: (_, _, _) => Padding(
              padding: const EdgeInsets.only(right: 70),
              child: _VadBar(app.levels.length > 2 ? app.levels[2] : 0, s.vadThreshold),
            ),
          ),
        ],
        if (s.inputMode == InputMode.ptt) ...[
          const SizedBox(height: 6),
          Text('松开按键后的延迟', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.pttReleaseMs.toDouble(),
            min: 0,
            max: 1000,
            divisions: 20,
            label: (v) => '${v.round()} ms',
            onChanged: (v) {
              s.pttReleaseMs = v.round();
              app.native.setPttReleaseMs(s.pttReleaseMs);
              setState(() {});
            },
            onChangeEnd: (_) => app.savePrefs(),
          ),
        ],
      ]),
      _Section('实时降噪', subtitle: 'RNNoise 神经网络降噪（本地运行，不上传任何声音）：可去除键盘、风扇、空调、背景人声等噪音', [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('关闭')),
            ButtonSegment(value: 1, label: Text('轻度')),
            ButtonSegment(value: 2, label: Text('标准')),
            ButtonSegment(value: 3, label: Text('强力')),
          ],
          selected: {s.noiseSuppression},
          onSelectionChanged: (v) {
            s.noiseSuppression = v.first;
            app.native.setNoiseSuppression(v.first);
            app.savePrefs();
          },
        ),
      ]),
      _Section('音质', [
        Text('最高码率（语音频道可能限制得更低）', style: TextStyle(color: t.muted, fontSize: 12.5)),
        _SliderRow(
          value: s.bitrate.toDouble(),
          min: 16000,
          max: 128000,
          divisions: 14,
          label: (v) => '${(v / 1000).round()} kbps',
          onChanged: (v) {
            s.bitrate = (v / 8000).round() * 8000;
            app.native.setBitrate(s.bitrate);
            setState(() {});
          },
          onChangeEnd: (_) => app.savePrefs(),
        ),
      ]),
      _Section('说话者浮窗', subtitle: '在语音频道时显示一个置顶的小窗，列出频道成员并高亮正在说话的人；可拖动，点 × 关闭', [
        _switch(context, '在语音频道中显示', s.overlay, (v) => app.setOverlay(v)),
        if (s.overlay) ...[
          _switch(context, '只显示正在说话的人', s.overlaySpeakingOnly, (v) {
            s.overlaySpeakingOnly = v;
            app.applyOverlayConfig();
            app.savePrefs();
          }, subtitle: '没人说话时浮窗只剩标题栏，最不挡视线'),
          _switch(context, 'Pulse 在前台时隐藏', s.overlayHideFocused, (v) {
            s.overlayHideFocused = v;
            app.applyOverlayConfig();
            app.savePrefs();
          }, subtitle: '主窗口里已经能看到谁在说话'),
          _switch(context, '锁定（鼠标穿透）', s.overlayLocked, (v) {
            s.overlayLocked = v;
            app.applyOverlayConfig();
            app.savePrefs();
          }, subtitle: '锁定后浮窗不能拖动、不会挡住游戏里的点击，× 按钮隐藏；用快捷键或这里取消锁定'),
          Text('背景不透明度', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.overlayOpacity,
            min: 0.2,
            max: 1,
            divisions: 16,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) {
              setState(() => s.overlayOpacity = v);
              app.applyOverlayConfig();
            },
            onChangeEnd: (_) => app.savePrefs(),
          ),
          Text('大小', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.overlayScale,
            min: 0.7,
            max: 1.6,
            divisions: 9,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) {
              setState(() => s.overlayScale = v);
              app.applyOverlayConfig();
            },
            onChangeEnd: (_) => app.savePrefs(),
          ),
          TextButton.icon(
            onPressed: app.native.overlayResetPosition,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('重置浮窗位置'),
          ),
        ],
      ]),
      _Section('提醒', [
        _switch(context, '静音时说话提醒', s.warnMutedTalk, (v) {
          s.warnMutedTalk = v;
          app.savePrefs();
        }, subtitle: '在语音频道里静音状态下说话，会提示你麦克风是关着的'),
      ]),
      _Section('提示音', [
        _switch(context, '播放加入 / 离开 / 静音提示音', s.sounds, (v) {
          s.sounds = v;
          app.native.setSoundVolume(v ? s.soundVolume : 0);
          app.savePrefs();
        }),
        if (s.sounds)
          _SliderRow(
            value: s.soundVolume,
            min: 0,
            max: 1,
            divisions: 20,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) {
              s.soundVolume = v;
              app.native.setSoundVolume(v);
              setState(() {});
            },
            onChangeEnd: (_) {
              app.native.playSound(Sound.message);
              app.savePrefs();
            },
          ),
      ]),
    ]);
  }
}

class _VadBar extends StatelessWidget {
  final double prob, threshold;
  const _VadBar(this.prob, this.threshold);
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return Container(
        height: 10,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: LinearGradient(colors: [t.idle, t.idle, t.online, t.online], stops: [0, threshold, threshold, 1]),
        ),
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w * (1 - prob.clamp(0.0, 1.0)),
            child: const SizedBox.shrink(),
          ),
          Positioned(
            left: w * prob.clamp(0.0, 1.0),
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(decoration: BoxDecoration(color: t.input.withValues(alpha: 0.85), borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)))),
          ),
        ]),
      );
    });
  }
}

String _bindingText(AppState app, Binding b) => b.vk == 0 ? '未设置' : app.bindingLabelOf(b);

// ------------------------------------------------------------------ voice changer

class _VoiceChangerTab extends StatefulWidget {
  const _VoiceChangerTab();
  @override
  State<_VoiceChangerTab> createState() => _VoiceChangerTabState();
}

class _VoiceChangerTabState extends State<_VoiceChangerTab> {
  List<File> _voices = [];

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    app.refreshGpu();
    _scanVoices();
  }

  // PULSE_VOICES_DIR: CML keeps voices in its add-on folder so they survive launcher updates.
  String get _voicesDir => voicesDirOverride ?? '${File(Platform.resolvedExecutable).parent.path}\\ai\\voices';

  void _scanVoices() {
    try {
      final d = Directory(_voicesDir);
      if (!d.existsSync()) d.createSync(recursive: true);
      _voices = d.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.onnx')).toList()..sort((a, b) => a.path.compareTo(b.path));
    } catch (_) {
      _voices = [];
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final s = app.settings;
    final st = asInt(app.vcStatus['state']);
    final adapters = (app.gpu['adapters'] as List? ?? const []).cast<Map>();
    final providers = app.gpuProviders;
    final ortErr = asStr(app.gpu['ortError']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Section('模式', subtitle: '变声在你的电脑上本地完成，其他人只会收到变声后的声音', [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: VcMode.off, label: Text('关闭'), icon: Icon(Icons.block)),
            ButtonSegment(value: VcMode.dsp, label: Text('经典变声'), icon: Icon(Icons.tune)),
            ButtonSegment(value: VcMode.ai, label: Text('AI 变声（显卡）'), icon: Icon(Icons.memory)),
          ],
          selected: {s.vcMode},
          onSelectionChanged: (v) => app.setVoiceChangerMode(v.first),
        ),
        const SizedBox(height: 8),
        Text(
          switch (s.vcMode) {
            VcMode.dsp => '经典变声：实时变调 / 机器人音效，几乎零延迟，CPU 占用极低。',
            VcMode.ai => 'AI 变声：在本机显卡上运行 RVC 声音转换模型（HuBERT + RMVPE 音高 + 声码器），把你的声音转换成目标音色。延迟约 0.3–0.5 秒。',
            _ => '变声器已关闭。',
          },
          style: TextStyle(color: t.muted, fontSize: 12.5),
        ),
      ]),
      if (s.vcMode != VcMode.off)
        _Section('音调', [
          _SliderRow(
            value: s.vcPitch,
            min: -24,
            max: 24,
            divisions: 48,
            label: (v) => '${v > 0 ? '+' : ''}${v.round()} 半音',
            onChanged: (v) {
              s.vcPitch = v.roundToDouble();
              app.native.setVcPitch(s.vcPitch);
              setState(() {});
            },
            onChangeEnd: (_) => app.savePrefs(),
          ),
          Wrap(spacing: 8, children: [
            for (final (label, v) in [('男声 → 女声', 12.0), ('女声 → 男声', -12.0), ('稍高', 4.0), ('稍低', -4.0), ('原调', 0.0)])
              ActionChip(
                label: Text(label),
                onPressed: () {
                  s.vcPitch = v;
                  app.native.setVcPitch(v);
                  app.savePrefs();
                },
              ),
          ]),
          if (s.vcMode == VcMode.dsp) ...[
            const SizedBox(height: 8),
            _switch(context, '机器人音效', s.vcRobot, (v) {
              s.vcRobot = v;
              app.native.setVcRobot(v);
              app.savePrefs();
            }),
          ],
        ]),
      if (s.vcMode == VcMode.ai) ...[
        _Section('状态', [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.sidebar, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Icon(
                switch (st) { VcState.running => Icons.check_circle, VcState.loading => Icons.hourglass_top, VcState.error => Icons.error, _ => Icons.power_settings_new },
                color: switch (st) { VcState.running => t.online, VcState.loading => t.idle, VcState.error => t.danger, _ => t.muted },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    switch (st) {
                      VcState.running => '运行中 · ${app.vcStatus['providerLabel']}',
                      VcState.loading => '正在加载模型并编译显卡内核…',
                      VcState.error => '出错：${app.vcStatus['error']}',
                      _ => '未加载',
                    },
                    style: TextStyle(color: t.text),
                  ),
                  if (st == VcState.running)
                    Text('总延迟约 ${app.vcStatus['latencyMs']} ms · 单次推理 ${app.vcStatus['inferMs']} ms · 卡顿 ${app.vcStatus['underruns']} 次',
                        style: TextStyle(color: t.muted, fontSize: 12)),
                ]),
              ),
              TextButton(onPressed: app.reloadAi, child: const Text('重新加载')),
            ]),
          ),
        ]),
        _Section('计算设备', subtitle: '支持 NVIDIA / AMD / Intel / 高通等任何支持 DirectX 12 的显卡（DirectML），也可安装厂商加速插件', [
          if (ortErr.isNotEmpty) Text(ortErr, style: TextStyle(color: t.danger)),
          DropdownButtonFormField<String>(
            initialValue: providers.any((p) => p.id == s.vcProvider) ? s.vcProvider : (providers.isNotEmpty ? providers.first.id : null),
            isExpanded: true,
            items: [for (final p in providers) DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              s.vcProvider = v ?? 'auto';
              app.savePrefs();
              app.reloadAi();
            },
          ),
          const SizedBox(height: 10),
          for (final a in adapters)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(asBool(a['software']) ? Icons.computer : Icons.developer_board, size: 16, color: t.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${a['name']} · ${a['vendor']} · ${asInt(a['vramMB']) >= 1024 ? '${(asInt(a['vramMB']) / 1024).toStringAsFixed(0)} GB' : '${a['vramMB']} MB'} · 驱动 ${a['driver']}',
                    style: TextStyle(color: t.muted, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          Text('ONNX Runtime ${app.gpu['ort'] ?? '-'}', style: TextStyle(color: t.muted, fontSize: 11.5)),
        ]),
        _Section('声音模型', subtitle: '把 RVC v2 声音模型（.onnx，768 维，带音高）放进 ai\\voices 文件夹即可使用。请只使用你有权使用的声音。', [
          DropdownButtonFormField<String>(
            initialValue: s.vcModel.isEmpty || _voices.any((f) => f.path == s.vcModel) ? s.vcModel : '',
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('内置基础音色（RVC 预训练，109 种音色）')),
              for (final f in _voices) DropdownMenuItem(value: f.path, child: Text(f.uri.pathSegments.last, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              s.vcModel = v ?? '';
              app.savePrefs();
              app.reloadAi();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(onPressed: _scanVoices, icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新')),
            TextButton.icon(
              onPressed: () => Process.run('explorer.exe', [_voicesDir]),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('打开模型文件夹'),
            ),
          ]),
          if (asInt(app.vcStatus['speakers']) > 1) ...[
            const SizedBox(height: 6),
            Text('音色编号（0 – ${asInt(app.vcStatus['speakers']) - 1}）', style: TextStyle(color: t.muted, fontSize: 12.5)),
            _SliderRow(
              value: s.vcSpeaker.toDouble(),
              min: 0,
              max: (asInt(app.vcStatus['speakers']) - 1).toDouble(),
              divisions: asInt(app.vcStatus['speakers']) - 1,
              label: (v) => '#${v.round()}',
              onChanged: (v) {
                s.vcSpeaker = v.round();
                app.native.setVcSpeaker(s.vcSpeaker);
                setState(() {});
              },
              onChangeEnd: (_) => app.savePrefs(),
            ),
          ],
        ]),
        _Section('延迟与质量', subtitle: '切换预设是即时的（显存 ≥ 6 GB 的显卡会在后台提前编译三个预设）；切换时声音不会中断', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (label, b, e) in vcLatencyPresets)
              ChoiceChip(
                label: Text(label),
                selected: s.vcBlockMs == b && s.vcExtraMs == e,
                onSelected: (_) {
                  setState(() {
                    s.vcBlockMs = b;
                    s.vcExtraMs = e;
                  });
                  app.savePrefs();
                  app.reloadAi();
                },
              ),
            if (app.vcStatus['switching'] == true)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('正在切换（旧设置继续工作）…', style: TextStyle(color: t.muted, fontSize: 12)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          Text('自定义：处理块大小（越小延迟越低，但对显卡要求越高）', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.vcBlockMs.toDouble(),
            min: 100,
            max: 500,
            divisions: 8,
            label: (v) => '${v.round()} ms',
            onChanged: (v) => setState(() => s.vcBlockMs = (v / 50).round() * 50),
            onChangeEnd: (_) {
              app.savePrefs();
              app.reloadAi();
            },
          ),
          Text('上下文长度（越长音质越稳定，推理越慢）', style: TextStyle(color: t.muted, fontSize: 12.5)),
          _SliderRow(
            value: s.vcExtraMs.toDouble(),
            min: 100,
            max: 800,
            divisions: 7,
            label: (v) => '${v.round()} ms',
            onChanged: (v) => setState(() => s.vcExtraMs = (v / 100).round() * 100),
            onChangeEnd: (_) {
              app.savePrefs();
              app.reloadAi();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('关闭 AI 变声后保持模型加载（再次开启无需等待）', style: TextStyle(color: t.text))),
            DropdownButton<int>(
              value: s.vcKeepLoadedMin,
              items: const [
                DropdownMenuItem(value: 0, child: Text('立即释放显存')),
                DropdownMenuItem(value: 10, child: Text('10 分钟')),
                DropdownMenuItem(value: 60, child: Text('1 小时')),
                DropdownMenuItem(value: -1, child: Text('一直保持')),
              ],
              onChanged: (v) {
                s.vcKeepLoadedMin = v ?? 10;
                app.savePrefs();
              },
            ),
          ]),
        ]),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ hotkeys

class _HotkeyTab extends StatefulWidget {
  const _HotkeyTab();
  @override
  State<_HotkeyTab> createState() => _HotkeyTabState();
}

class _HotkeyTabState extends State<_HotkeyTab> {
  int? _capturing;

  void _capture(AppState app, int slot) {
    setState(() => _capturing = slot);
    app.onHotkeyCaptured = (vk, mods) {
      if (!mounted) return;
      final s = app.settings;
      if (vk != 0) {
        final b = Binding(vk, mods);
        switch (slot) {
          case HotkeySlot.ptt:
            s.pttKey = b;
          case HotkeySlot.mute:
            s.muteKey = b;
          case HotkeySlot.deafen:
            s.deafenKey = b;
          case HotkeySlot.voiceChanger:
            s.vcKey = b;
          case HotkeySlot.overlay:
            s.overlayKey = b;
        }
        app.applyHotkeys();
        app.savePrefs();
      }
      setState(() => _capturing = null);
    };
    app.native.hotkeyCapture(true);
  }

  void _clear(AppState app, int slot) {
    final s = app.settings;
    switch (slot) {
      case HotkeySlot.ptt:
        s.pttKey = Binding.none;
      case HotkeySlot.mute:
        s.muteKey = Binding.none;
      case HotkeySlot.deafen:
        s.deafenKey = Binding.none;
      case HotkeySlot.voiceChanger:
        s.vcKey = Binding.none;
      case HotkeySlot.overlay:
        s.overlayKey = Binding.none;
    }
    app.applyHotkeys();
    app.savePrefs();
  }

  @override
  void dispose() {
    if (_capturing != null) {
      final app = AppScope.read(context);
      app.native.hotkeyCapture(false);
      app.onHotkeyCaptured = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final s = app.settings;
    Widget row(String title, String sub, int slot, Binding b) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.sidebar, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
                Text(sub, style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
            OutlinedButton(
              onPressed: _capturing == null ? () => _capture(app, slot) : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(170, 40)),
              child: Text(_capturing == slot ? '请按下按键…（Esc 取消）' : _bindingText(app, b),
                  style: TextStyle(color: _capturing == slot ? t.idle : t.text, fontFamily: 'Consolas')),
            ),
            IconButton(tooltip: '清除', onPressed: b.vk == 0 ? null : () => _clear(app, slot), icon: const Icon(Icons.close, size: 18)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switch(context, '启用全局快捷键', s.globalHotkeys, (v) {
        s.globalHotkeys = v;
        app.applyHotkeys();
        app.savePrefs();
      }, subtitle: 'Pulse 在后台或玩全屏游戏时快捷键依然有效；按键仍会正常传给当前程序。支持键盘按键和鼠标中键 / 侧键。'),
      const SizedBox(height: 16),
      row('按键说话（开麦键）', '按住时发送语音（需在“语音与音频”选择“按键说话”模式）', HotkeySlot.ptt, s.pttKey),
      row('切换静音', '开 / 关自己的麦克风', HotkeySlot.mute, s.muteKey),
      row('切换闭麦', '同时关闭麦克风和扬声器', HotkeySlot.deafen, s.deafenKey),
      row('切换变声器', '开 / 关变声器', HotkeySlot.voiceChanger, s.vcKey),
      row('显示 / 隐藏说话者浮窗', '游戏中快速开关置顶的说话者小窗', HotkeySlot.overlay, s.overlayKey),
      const SizedBox(height: 8),
      Text('提示：以管理员身份运行的游戏中，需同样以管理员身份运行 Pulse 才能接收快捷键（Windows 安全限制）。', style: TextStyle(color: t.muted, fontSize: 12.5)),
    ]);
  }
}

// ------------------------------------------------------------------ appearance

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final s = app.settings;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hostTheme != null)
        _Section('主题', [Text('主题跟随 CML 启动器，在 CML「设置 → 外观」中切换。', style: TextStyle(color: t.muted))])
      else ...[
      _Section('主题', [
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final th in pulseThemes)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                s.theme = th.id;
                app.savePrefs();
              },
              child: Container(
                width: 148,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: s.theme == th.id ? t.accent : t.divider, width: s.theme == th.id ? 2.5 : 1),
                ),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 64,
                      child: Row(children: [
                        Container(width: 14, color: th.rail),
                        Container(width: 36, color: th.sidebar, child: Column(children: [
                          const SizedBox(height: 8),
                          for (var i = 0; i < 3; i++) Container(height: 4, margin: const EdgeInsets.fromLTRB(5, 0, 5, 5), color: th.muted.withValues(alpha: 0.6)),
                        ])),
                        Expanded(
                          child: Container(
                            color: th.chat,
                            padding: const EdgeInsets.all(6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(height: 5, width: 40, color: th.accent),
                              const SizedBox(height: 5),
                              Container(height: 4, width: 60, color: th.text.withValues(alpha: 0.7)),
                              const SizedBox(height: 4),
                              Container(height: 4, width: 45, color: th.text.withValues(alpha: 0.5)),
                              const Spacer(),
                              Container(height: 9, decoration: BoxDecoration(color: th.input, borderRadius: BorderRadius.circular(3))),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(th.name, style: TextStyle(color: t.text, fontSize: 12.5)),
                ]),
              ),
            ),
        ]),
      ]),
      _Section('强调色', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in accentPresets)
            Tooltip(
              message: c == 0 ? '主题默认' : '',
              child: InkWell(
                onTap: () {
                  s.accent = c;
                  app.savePrefs();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c == 0 ? themeById(s.theme).accent : Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: s.accent == c ? t.text : Colors.transparent, width: 3),
                  ),
                  child: c == 0 ? const Icon(Icons.auto_awesome, size: 16, color: Colors.white) : null,
                ),
              ),
            ),
        ]),
      ]),
      ],
      _Section('缩放', [
        _SliderRow(
          value: s.uiScale,
          min: 0.8,
          max: 1.5,
          divisions: 14,
          label: (v) => '${(v * 100).round()}%',
          onChanged: (v) {
            s.uiScale = (v * 20).round() / 20;
            app.savePrefs();
          },
        ),
      ]),
      _Section('消息显示', [
        _switch(context, '紧凑模式', s.compact, (v) {
          s.compact = v;
          app.savePrefs();
        }, subtitle: '缩小消息之间的间距'),
        _switch(context, '时间显示秒', s.showSeconds, (v) {
          s.showSeconds = v;
          app.savePrefs();
        }),
      ]),
      _Section('窗口', [
        _switch(context, '关闭窗口时最小化到托盘', s.closeToTray, (v) {
          s.closeToTray = v;
          app.savePrefs();
        }, subtitle: '语音通话和全局快捷键会继续工作；右键托盘图标可静音或退出'),
      ]),
    ]);
  }
}

class _NotifyTab extends StatelessWidget {
  const _NotifyTab();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return Column(children: [
      _switch(context, '有人 @我 时提示', s.notifyMentions, (v) {
        s.notifyMentions = v;
        app.savePrefs();
      }, subtitle: '播放提示音并在频道上显示红点'),
      _switch(context, '所有新消息都提示', s.notifyAll, (v) {
        s.notifyAll = v;
        app.savePrefs();
      }, subtitle: '窗口不在前台时，每条新消息都播放提示音（“请勿打扰”状态下不响）'),
    ]);
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.graphic_eq_rounded, color: t.accent, size: 40),
        const SizedBox(width: 10),
        Text('Pulse 1.0', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: t.text)),
      ]),
      const SizedBox(height: 12),
      Text('文字 / 语音聊天 · 全局开麦键 · RNNoise 实时降噪 · GPU AI 变声', style: TextStyle(color: t.muted)),
      const SizedBox(height: 20),
      _Section('安全', [
        Text('• 与服务器之间全程加密（X25519 密钥交换 + ChaCha20-Poly1305），防篡改、防重放。\n'
            '• 首次连接记住服务器身份，之后身份改变会拒绝连接并警告（防冒充）。\n'
            '• 密码在服务器上以 Argon2id 加盐哈希保存；本机只保存登录令牌，并用 Windows DPAPI 加密。\n'
            '• 语音降噪与变声全部在本机完成。'),
      ]),
      _Section('音频', [
        Text('输入：${app.inputDeviceName.isEmpty ? '-' : app.inputDeviceName}\n输出：${app.outputDeviceName.isEmpty ? '-' : app.outputDeviceName}',
            style: TextStyle(color: t.muted)),
      ]),
      _Section('开源组件', [
        Text('Flutter · Opus（BSD）· RNNoise（BSD）· miniaudio（MIT-0）· ONNX Runtime / DirectML（MIT）· '
            'RVC / RMVPE / HuBERT 预训练模型（MIT，lj1995/VoiceConversionWebUI）',
            style: TextStyle(color: t.muted, fontSize: 12.5)),
      ]),
      _Section('数据', [
        Text('设置保存在 ${app.settings.directory}', style: TextStyle(color: t.muted, fontSize: 12.5)),
      ]),
    ]);
  }
}
