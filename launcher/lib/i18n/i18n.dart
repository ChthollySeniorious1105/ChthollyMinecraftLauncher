import 'package:flutter/widgets.dart';

import 'strings_en.dart';

/// UI languages. Chinese source strings are the keys; other languages look them up.
enum AppLanguage {
  zh('简体中文', 'zh'),
  en('English', 'en');

  final String label;
  final String code;
  const AppLanguage(this.label, this.code);

  static AppLanguage fromCode(String? c) => values.firstWhere((l) => l.code == c, orElse: () => zh);
}

/// Current language, set from settings by the app root.
class I18n extends InheritedWidget {
  final AppLanguage language;
  const I18n({super.key, required this.language, required super.child});

  static AppLanguage of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<I18n>()?.language ?? AppLanguage.zh;

  @override
  bool updateShouldNotify(I18n old) => old.language != language;
}

/// Translates a Chinese source string, filling `{0}`, `{1}` … placeholders.
String translate(AppLanguage lang, String zh, [List<Object?> args = const []]) {
  var s = lang == AppLanguage.en ? (stringsEn[zh] ?? zh) : zh;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

extension Tr on BuildContext {
  String tr(String zh, [List<Object?> args = const []]) => translate(I18n.of(this), zh, args);
  AppLanguage get lang => I18n.of(this);
}

/// Language for code that has no BuildContext (core messages shown in toasts etc.).
AppLanguage currentLanguage = AppLanguage.zh;
String trGlobal(String zh, [List<Object?> args = const []]) => translate(currentLanguage, zh, args);
