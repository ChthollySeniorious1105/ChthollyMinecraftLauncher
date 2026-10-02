import 'package:flutter/widgets.dart';

import 'core_en.dart';
import 'strings_en.dart';
import 'strings_en_bedrock.dart';
import 'strings_en_modules.dart';
import 'strings_en_multiplayer.dart';
import 'strings_en_tools.dart';

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

/// All English tables: the generated main table plus hand-maintained per-area tables.
const englishTables = [stringsEn, stringsEnTools, stringsEnBedrock, stringsEnMultiplayer, stringsEnModules];

String? englishFor(String zh) {
  for (final t in englishTables) {
    final v = t[zh];
    if (v != null) return v;
  }
  return null;
}

/// Translates a Chinese source string, filling `{0}`, `{1}` … placeholders.
String translate(AppLanguage lang, String zh, [List<Object?> args = const []]) {
  var s = lang == AppLanguage.en ? (englishFor(zh) ?? zh) : zh;
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

/// Translates a message produced by cml_core (errors, task details, labels) by matching it against
/// the Chinese templates in [coreEn], capturing the `{n}` parts and inserting them into the English text.
String trCore(String msg) {
  if (currentLanguage == AppLanguage.zh || msg.isEmpty) return msg;
  final exact = coreEn[msg];
  if (exact != null) return exact;
  for (final e in _coreMatchers) {
    final m = e.$1.firstMatch(msg);
    if (m == null) continue;
    var out = e.$2;
    for (var i = 0; i < m.groupCount; i++) {
      out = out.replaceAll('{$i}', m.group(i + 1) ?? '');
    }
    return out;
  }
  return msg;
}

final List<(RegExp, String)> _coreMatchers = [
  for (final e in coreEn.entries)
    if (e.key.contains('{0}'))
      (
        RegExp('^${e.key.split(RegExp(r'\{\d\}')).map(RegExp.escape).join('(.*?)')}\$', dotAll: true),
        e.value,
      )
];
