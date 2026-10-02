import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cml_core/cml_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

CrashFinding? f(String log, [String? id]) {
  final r = CrashAnalyzer.analyzeText(log);
  return id == null ? r.primary : r.findings.where((x) => x.id == id).firstOrNull;
}

void main() {
  test('Fabric: missing dependency names both mods', () {
    final x = f("""
net.fabricmc.loader.impl.FormattedException: Mod resolution encountered an incompatible mod set!
A potential solution has been determined:
	 - Install fabric-api, any version.
Unmet dependency listing:
	 - Mod 'Sodium Extra' (sodium-extra) 0.5.4 requires any version of mod 'Sodium' (sodium), which is missing!
""")!;
    expect(x.id, 'missing_mod');
    expect(x.confidence, CrashConfidence.certain);
    expect(x.mods, containsAll(['sodium', 'fabric-api']));
    expect(x.fixes, contains(CrashFix.installMod));
  });

  test('Forge: missing mod and wrong Minecraft version', () {
    final missing = f('''
Missing or unsupported mandatory dependencies:
	Mod ID: 'geckolib', Requested by: 'alexsmobs', Expected range: '[4.0,)', Actual version: '[MISSING]'
''')!;
    expect(missing.id, 'missing_mod');
    expect(missing.mods, ['geckolib']);
    final mc = f('''
	Mod ID: 'minecraft', Requested by: 'jei', Expected range: '[1.20.1,1.20.2)', Actual version: '1.21.1'
''')!;
    expect(mc.id, 'wrong_mc');
    expect(mc.mods, ['jei']);
  });

  test('Java: class file version gives the required major', () {
    final x = f('java.lang.UnsupportedClassVersionError: net/minecraft/client/main/Main has been compiled by a more recent version of the Java Runtime '
        '(class file version 65.0), this version of the Java Runtime only recognizes class file versions up to 52.0')!;
    expect(x.id, 'java_old');
    expect(x.javaMajor, 21);
    expect(x.detail, contains('Java 8'));
  });

  test('Java 8 only Forge on newer Java', () {
    final x = f('java.lang.ClassCastException: class jdk.internal.loader.ClassLoaders\$AppClassLoader cannot be cast to class java.net.URLClassLoader')!;
    expect(x.id, 'java_new');
    expect(x.javaMajor, 8);
  });

  test('memory, mixin, duplicates, GPU driver', () {
    expect(f('java.lang.OutOfMemoryError: Java heap space')!.id, 'oom');
    expect(f('Error occurred during initialization of VM\nCould not reserve enough space for 8388608KB object heap')!.id, 'heap');
    final mixin = f('org.spongepowered.asm.mixin.transformer.throwables.MixinTransformerError: An unexpected critical error was encountered\n'
        'Caused by: org.spongepowered.asm.mixin.throwables.MixinApplyError: Mixin [cpsplus.mixins.json:MinecraftClientMixin] from phase [DEFAULT] in config [cpsplus.mixins.json] FAILED during APPLY\n'
        'Mixin apply for mod cpsplus failed cpsplus.mixins.json:MinecraftClientMixin')!;
    expect(mixin.id, 'mixin');
    expect(mixin.mods, ['cpsplus']);
    final dup = f("net.fabricmc.loader.impl.FormattedException: Found duplicate mods: 'sodium' (2 files)")!;
    expect(dup.id, 'duplicate');
    final gpu = f('# A fatal error has been detected by the Java Runtime Environment:\n#  EXCEPTION_ACCESS_VIOLATION (0xc0000005)\n# Problematic frame:\n# C  [ig9icd64.dll+0x1a2b]')!;
    expect(gpu.id, 'native');
    expect(gpu.title, contains('显卡'));
    expect(gpu.confidence, CrashConfidence.certain);
  });

  test('vanilla crash report: suspected mods and description', () {
    final r = CrashAnalyzer.analyzeText('---- Minecraft Crash Report ----\nDescription: Rendering overlay\njava.lang.NullPointerException\nSuspected Mods: Xaero\'s Minimap (xaerominimap)');
    expect(r.description, 'Rendering overlay');
    expect(r.primary!.mods, ['xaerominimap']);
  });

  test('stack frame is traced back to the installed jar that owns the package', () async {
    final dir = await Directory.systemTemp.createTemp('cml_crash');
    try {
      void jar(String name, List<String> classes) {
        final enc = ZipFileEncoder()..create(p.join(dir.path, name));
        for (final c in classes) {
          enc.addArchiveFile(ArchiveFile(c, 1, [0]));
        }
        enc.closeSync();
      }

      jar('WorldDL.litemod', ['wdl/WDLEvents.class', 'wdl/WDL.class']);
      jar('jei-1.21.jar', ['mezz/jei/common/A.class', 'com/google/common/X.class']);
      jar('shaded-lib.jar', ['com/google/common/X.class']); // shared package: not evidence
      final mods = await CrashAnalyzer.modPackages(dir.path);
      expect(mods.map((m) => m.file), containsAll(['WorldDL.litemod', 'jei-1.21.jar']));
      expect(mods.expand((m) => m.packages), isNot(contains('com.google.common')));

      const log = '''
Description: WDL mod: exception in onWorldClientTick event
java.lang.NullPointerException: WDL mod: exception in onWorldClientTick event
	at adm.a(SourceFile:204)
	at wdl.WDLEvents.onItemGuiClosed(WDLEvents.java:271)
	at net.minecraft.client.main.Main.main(SourceFile:124)
A detailed walkthrough of the error, its code path and all known details is as follows:
''';
      final r = CrashAnalyzer.analyzeText(log, mods: mods);
      expect(r.primary!.id, 'stack_mod');
      expect(r.primary!.mods, ['WorldDL.litemod']);
      expect(r.primary!.detail, contains('WDLEvents.onItemGuiClosed'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('deepest "Caused by" wins and obfuscated / framework frames are skipped', () {
    const log = '''
net.minecraftforge.fml.common.LoaderException: java.lang.NoSuchMethodError: net.minecraft.client.Minecraft.getMinecraft()
	at net.minecraftforge.fml.common.LoadController.transition(LoadController.java:162)
Caused by: java.lang.NoSuchMethodError: net.minecraft.client.Minecraft.getMinecraft()
	at com.lstar.inputrepeatmanager.InputRepeatManagerClient.<init>(InputRepeatManagerClient.java:25)
''';
    final x = f(log, 'stack_pkg')!;
    expect(x.mods, ['com.lstar.inputrepeatmanager']);
  });

  test('analyzeCrash reads only files written for this crash', () async {
    final dir = await Directory.systemTemp.createTemp('cml_crash');
    try {
      final reports = Directory(p.join(dir.path, 'crash-reports'))..createSync();
      final old = File(p.join(reports.path, 'crash-old-client.txt'))..writeAsStringSync('java.lang.OutOfMemoryError: Java heap space');
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
      final started = DateTime.now();
      File(p.join(dir.path, 'logs', 'latest.log'))
        ..createSync(recursive: true)
        ..writeAsStringSync("\t - Mod 'A' (a) 1.0 requires any version of mod 'B' (b), which is missing!");
      final r = await CrashAnalyzer.analyzeCrash(gameDir: dir.path, since: started, exitCode: 1);
      expect(r.primary!.id, 'missing_mod');
      expect(r.findings.any((x) => x.id == 'oom'), isFalse); // the old report is ignored
      expect(r.sources.single, endsWith('latest.log'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('unknown log gives no finding; one-line API still works', () {
    expect(CrashAnalyzer.analyzeText('all good').findings, isEmpty);
    expect(CrashAnalyzer.analyze('java.lang.OutOfMemoryError: Java heap space'), contains('内存'));
  });
}
