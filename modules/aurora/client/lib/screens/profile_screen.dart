import '../i18n/aurora_i18n.dart';

import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/common.dart';

/// Name + avatar editor (also shown on first launch).
class ProfileScreen extends StatefulWidget {
  final bool firstRun;
  const ProfileScreen({super.key, this.firstRun = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late int _avatar;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _name = TextEditingController(text: app.name);
    _avatar = app.avatar;
  }

  void _save() {
    final app = AppScope.read(context);
    final err = app.saveProfile(_name.text, _avatar);
    setState(() => _error = err);
    if (err == null && !widget.firstRun) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = nameWidth(_name.text.trim());
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? '欢迎来到 Aurora' : '个人资料'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Avatar(_avatar, size: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        maxLength: 18,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => Text(
                              '$width/18',
                              style: const TextStyle(fontSize: 12),
                            ),
                        decoration: InputDecoration(
                          labelText: auroraT('昵称'),
                          helperText: '英文≤18 / 中文≤9 字',
                          helperMaxLines: 2,
                          errorText:
                              _error ?? (width > kMaxNameWidth ? '名称过长' : null),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const AuroraText('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '选择形象（共 $kAvatarCount 种）',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _avatar = 1 + Random().nextInt(kAvatarCount),
                      ),
                      icon: const Icon(Icons.casino),
                      label: const AuroraText('随机'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Card(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 76,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: kAvatarCount,
                      itemBuilder: (context, i) {
                        final id = i + 1;
                        final sel = id == _avatar;
                        return InkWell(
                          borderRadius: BorderRadius.circular(40),
                          onTap: () => setState(() => _avatar = id),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sel ? cs.primary : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ClipOval(
                              child: Image.asset(
                                Avatar.path(id),
                                cacheWidth: 128,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
