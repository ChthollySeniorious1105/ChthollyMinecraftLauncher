import 'dart:io';

import 'package:cml/i18n/core_en.dart';
import 'package:cml/i18n/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extracts the first argument of every `trGlobal('…'` call in lib/.
Iterable<String> sourceKeys() sync* {
  final re = RegExp(r"trGlobal\('((?:[^'\\]|\\.)*)'");
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('i18n')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      yield m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\n', '\n').replaceAll(r'\$', r'$');
    }
  }
}

void main() {
  test('every UI string has an English translation', () {
    final missing = {for (final k in sourceKeys()) if (englishFor(k) == null) k};
    expect(missing, isEmpty, reason: 'run tool/i18n_realign.py + gen_strings_en.py');
  });

  test('placeholders survive translation', () {
    final ph = RegExp(r'\{\d\}');
    for (final e in [for (final t in englishTables) ...t.entries]) {
      final a = ph.allMatches(e.key).map((m) => m[0]).toSet();
      final b = ph.allMatches(e.value).map((m) => m[0]).toSet();
      expect(b, a, reason: e.key);
    }
    for (final e in coreEn.entries) {
      final a = ph.allMatches(e.key).map((m) => m[0]).toSet();
      final b = ph.allMatches(e.value).map((m) => m[0]).toSet();
      expect(b, a, reason: e.key);
    }
  });

  test('translate and trCore', () {
    expect(translate(AppLanguage.en, '安装 {0}', ['1.21.1']), 'Install 1.21.1');
    expect(translate(AppLanguage.zh, '安装 {0}', ['1.21.1']), '安装 1.21.1');
    currentLanguage = AppLanguage.en;
    expect(trCore('找不到版本 1.20.1 的 JSON 文件'), 'JSON file of version 1.20.1 not found');
    expect(trCore('有 3 个文件下载失败，例如 a/b.jar'), '3 files failed to download, e.g. a/b.jar');
    expect(trCore('下载文件 12 / 300'), 'Downloading files 12 / 300');
    expect(trCore('完全没见过的消息'), '完全没见过的消息');
    currentLanguage = AppLanguage.zh;
    expect(trCore('找不到版本 1.20.1 的 JSON 文件'), '找不到版本 1.20.1 的 JSON 文件');
  });
}
