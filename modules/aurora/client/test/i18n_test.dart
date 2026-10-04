import 'dart:io';

import 'package:aurora_client/i18n/aurora_i18n.dart';
import 'package:aurora_client/main.dart';
import 'package:aurora_client/platform/system_fonts.dart';
import 'package:aurora_client/screens/settings_screen.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Language switching and the interface-font setting.
void main() {
  Future<AppState> makeApp(String lang) async {
    SharedPreferences.setMockInitialValues({'name': 'tester', 'avatar': 3});
    final app = AppState();
    app.prefs = await SharedPreferences.getInstance();
    app.name = 'tester';
    app.setLanguage(lang);
    return app;
  }

  for (final lang in AuroraLanguage.values) {
    testWidgets('app builds in ${lang.label}', (tester) async {
      final app = await makeApp(lang.code);
      await tester.pumpWidget(AuroraApp(app));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // TextFields need MaterialLocalizations for the active locale.
      expect(find.byType(TextField), findsWidgets);
    });
  }

  testWidgets('switching to Chinese keeps Material widgets working', (tester) async {
    final app = await makeApp('en');
    await tester.pumpWidget(AuroraApp(app));
    await tester.pump(const Duration(milliseconds: 400));
    app.setLanguage('zh');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('连接服务器'), findsWidgets);
  });

  testWidgets('font picker lists system fonts and applies the choice', (tester) async {
    final app = await makeApp('zh');
    final fonts = (await tester.runAsync(systemFontFamilies))!;
    if (Platform.isWindows) {
      final yahei = fonts.firstWhere((f) => f.family == 'Microsoft YaHei');
      expect(yahei.localName, '微软雅黑');
      // Full DirectWrite family names, not GDI's 31-character legacy names.
      expect(fonts.map((f) => f.family), isNot(contains('Bahnschrift SemiBold SemiConden')));
    }
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(AppScope(
      app: app,
      child: AuroraI18n(
        language: app.auroraLanguage,
        child: MaterialApp(
          locale: app.auroraLanguage.locale,
          supportedLocales: AuroraLanguage.locales,
          localizationsDelegates: AuroraLanguage.delegates,
          home: const SettingsScreen(),
        ),
      ),
    ));
    // The font list resolves outside the fake clock, so let real time pass, then pump frames.
    Future<void> settle() async {
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.ensureVisible(find.text('选择字体'));
    await tester.tap(find.text('选择字体'));
    await settle();
    expect(tester.takeException(), isNull);
    if (fonts.isEmpty) return;
    expect(find.text('共 ${fonts.length} 款系统字体'), findsOneWidget);
    final pick = fonts.firstWhere((f) => f.localName != null, orElse: () => fonts.first);
    // The Chinese name is searchable too.
    await tester.enterText(find.byType(TextField), pick.localName ?? pick.family);
    await settle();
    await tester.tap(find.text(pick.label).last);
    await settle();
    expect(app.fontFamily, pick.family);
    expect(app.prefs.getString('fontFamily'), pick.family);
  });
}
