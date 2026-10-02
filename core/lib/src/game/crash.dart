import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// How sure a finding is. [certain]: the log states the cause explicitly (e.g. "requires mod X").
/// [likely]: a well-known signature. [possible]: weak hint (only shown when nothing better matched).
enum CrashConfidence { certain, likely, possible }

/// What the user can do about a finding; the UI turns these into buttons.
enum CrashFix {
  /// Raise max memory (settings).
  moreMemory,

  /// Pick / install another Java ([CrashFinding.javaMajor] = required major).
  changeJava,

  /// Download the missing mod(s) ([CrashFinding.mods]).
  installMod,

  /// Remove / disable the mod(s) ([CrashFinding.mods]).
  removeMod,

  /// Re-download game files (版本 → 补全文件).
  repairFiles,

  /// Update the graphics driver.
  updateDriver,

  /// Sign in again.
  relogin,

  /// Move the game to an ASCII path.
  movePath,

  /// Open the mods folder.
  openMods,
}

class CrashFinding {
  final String id;

  /// Short Chinese title, e.g. "缺少前置 Mod".
  final String title;

  /// One or two sentences: what happened and what to do.
  final String detail;
  final CrashConfidence confidence;
  final List<CrashFix> fixes;

  /// Mods named by the log (mod ids or jar names).
  final List<String> mods;

  /// Required Java major for [CrashFix.changeJava], when known.
  final int? javaMajor;

  /// Log line(s) that triggered the finding.
  final String evidence;
  const CrashFinding(this.id, this.title, this.detail,
      {this.confidence = CrashConfidence.likely, this.fixes = const [], this.mods = const [], this.javaMajor, this.evidence = ''});
}

/// One crash: the files read, all findings (most certain first) and the useful log excerpt.
class CrashReport {
  final List<CrashFinding> findings;

  /// Files that were read, newest first (game output is not a file).
  final List<String> sources;

  /// "Description:" of a vanilla crash report, if any.
  final String? description;

  /// Lines worth showing: exception, causes, suspected mods, first stack frames.
  final List<String> excerpt;
  final int? exitCode;
  const CrashReport(this.findings, this.sources, this.description, this.excerpt, this.exitCode);

  CrashFinding? get primary => findings.isEmpty ? null : findings.first;
}

/// Minecraft crash analysis, modelled on PCL's: collects every log the crash left behind and matches
/// loader-specific error formats (Fabric / Quilt / Forge / NeoForge), JVM errors and vanilla crash
/// reports. Findings carry the mods involved and a fix the launcher can offer.
abstract class CrashAnalyzer {
  /// Game output tail + the newest log files written since [since] (a few seconds of slack).
  ///
  /// [modsDir] (the instance's mods folder) lets stack frames be traced back to the mod whose code
  /// threw, for crashes that don't name a mod explicitly.
  static Future<CrashReport> analyzeCrash({required String gameDir, String? modsDir, List<String> output = const [], DateTime? since, int? exitCode}) async {
    final texts = <String>[];
    final sources = <String>[];
    if (output.isNotEmpty) texts.add(output.join('\n'));
    final cutoff = since?.subtract(const Duration(seconds: 10));
    for (final f in await _crashFiles(gameDir)) {
      if (cutoff != null && (await f.lastModified()).isBefore(cutoff)) continue;
      try {
        texts.add(await _readTail(f));
        sources.add(f.path);
      } catch (_) {}
    }
    final mods = modsDir == null ? const <ModPackage>[] : await modPackages(modsDir);
    return analyzeText(texts.join('\n'), sources: sources, exitCode: exitCode, mods: mods);
  }

  /// Java packages of every jar in [modsDir] (e.g. `com.lstar.inputrepeatmanager`). Packages that
  /// several jars contain (shaded libraries) are dropped, so a match points at exactly one mod.
  static Future<List<ModPackage>> modPackages(String modsDir) async {
    final out = <ModPackage>[];
    final d = Directory(modsDir);
    if (!await d.exists()) return out;
    await for (final e in d.list()) {
      final n = e.path.toLowerCase();
      // .litemod: LiteLoader mods (1.8–1.12)
      if (e is! File || !(n.endsWith('.jar') || n.endsWith('.litemod'))) continue;
      try {
        final pkgs = await _jarPackages(e);
        if (pkgs.isNotEmpty) out.add(ModPackage(p.basename(e.path), pkgs));
      } catch (_) {}
    }
    final count = <String, int>{};
    for (final m in out) {
      for (final x in m.packages) {
        count[x] = (count[x] ?? 0) + 1;
      }
    }
    return [
      for (final m in out)
        if (m.packages.any((x) => count[x] == 1)) ModPackage(m.file, {for (final x in m.packages) if (count[x] == 1) x}),
    ];
  }

  static const _notModPackages = ['net/minecraft/', 'com/mojang/', 'org/spongepowered/', 'kotlin/', 'org/jetbrains/', 'META-INF/'];

  /// Package prefixes (first 3 segments, or 2 for shallow names) of the .class files in a jar.
  static Future<Set<String>> _jarPackages(File jar) async {
    final input = InputFileStream(jar.path);
    try {
      final z = ZipDecoder().decodeStream(input);
      final out = <String>{};
      for (final f in z.files) {
        final n = f.name;
        if (!n.endsWith('.class') || _notModPackages.any(n.startsWith)) continue;
        final parts = n.split('/')..removeLast();
        // root-level classes are obfuscated / default-package code; one-segment packages (e.g. `wdl`) count
        if (parts.isEmpty || (parts.length == 1 && parts[0].length < 3)) continue;
        out.add(parts.take(parts.length >= 3 ? 3 : parts.length).join('.'));
      }
      return out;
    } finally {
      await input.close();
    }
  }

  /// Logs a crash can leave, newest first: crash-reports/, logs/latest.log, logs/debug.log, hs_err_pid*.log.
  static Future<List<File>> _crashFiles(String gameDir) async {
    final out = <File>[];
    Future<void> add(String dir, bool Function(String) want) async {
      final d = Directory(dir);
      if (!await d.exists()) return;
      await for (final e in d.list()) {
        if (e is File && want(p.basename(e.path).toLowerCase())) out.add(e);
      }
    }

    await add(p.join(gameDir, 'crash-reports'), (n) => n.endsWith('.txt'));
    await add(p.join(gameDir, 'logs'), (n) => n == 'latest.log' || n == 'debug.log');
    await add(gameDir, (n) => n.startsWith('hs_err_pid') && n.endsWith('.log'));
    final mod = {for (final f in out) f.path: await f.lastModified()};
    out.sort((a, b) => mod[b.path]!.compareTo(mod[a.path]!));
    // the newest crash report and hs_err are enough; older ones belong to earlier crashes
    final picked = <File>[];
    var report = false, hs = false;
    for (final f in out) {
      final n = p.basename(f.path).toLowerCase();
      if (n.startsWith('crash-')) {
        if (report) continue;
        report = true;
      } else if (n.startsWith('hs_err')) {
        if (hs) continue;
        hs = true;
      }
      picked.add(f);
    }
    return picked;
  }

  static Future<String> _readTail(File f, {int maxBytes = 3 << 20}) async {
    final len = await f.length();
    final raf = await f.open();
    try {
      if (len > maxBytes) await raf.setPosition(len - maxBytes);
      final bytes = await raf.read(maxBytes);
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return const SystemEncoding().decode(bytes);
      }
    } finally {
      await raf.close();
    }
  }

  /// Old one-line API (kept for callers that only need a sentence).
  static String? analyze(String log) {
    final f = analyzeText(log).primary;
    return f == null ? null : '${f.title}：${f.detail}';
  }

  static CrashReport analyzeText(String log, {List<String> sources = const [], int? exitCode, List<ModPackage> mods = const []}) {
    final found = <String, CrashFinding>{};
    void add(CrashFinding f) {
      final old = found[f.id];
      if (old == null || f.confidence.index < old.confidence.index) {
        found[f.id] = f;
      } else if (f.mods.isNotEmpty) {
        found[f.id] = CrashFinding(old.id, old.title, old.detail,
            confidence: old.confidence, fixes: old.fixes, mods: {...old.mods, ...f.mods}.toList(), javaMajor: old.javaMajor ?? f.javaMajor, evidence: old.evidence);
      }
    }

    String line(Match m) {
      final s = log.lastIndexOf('\n', m.start) + 1;
      final e = log.indexOf('\n', m.end);
      return log.substring(s, e < 0 ? log.length : e).trim();
    }

    // ---- Java / JVM ----
    final cv = RegExp(r'class file version (\d+)\.0\).*?(?:up to|recognizes class file versions up to) (\d+)\.0').firstMatch(log);
    if (cv != null) {
      final need = int.parse(cv.group(1)!) - 44;
      final have = int.parse(cv.group(2)!) - 44;
      add(CrashFinding('java_old', 'Java 版本过低', '游戏或某个 Mod 需要 Java $need，当前使用的是 Java $have。请在「设置 → Java」或版本设置中改用 Java $need 或更高版本。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.changeJava], javaMajor: need, evidence: line(cv)));
    } else {
      final m = RegExp(r'UnsupportedClassVersionError|has been compiled by a more recent version of the Java Runtime').firstMatch(log);
      if (m != null) {
        add(CrashFinding('java_old', 'Java 版本过低', '游戏或某个 Mod 需要更高版本的 Java。请在「设置 → Java」中改用更新的 Java。',
            fixes: const [CrashFix.changeJava], evidence: line(m)));
      }
    }
    final jv = RegExp(r'(?:requires|needs) (?:Java|java) (\d+)').firstMatch(log);
    if (jv != null && !found.containsKey('java_old')) {
      add(CrashFinding('java_old', 'Java 版本不符', '需要 Java ${jv.group(1)}。请在设置中切换。',
          fixes: const [CrashFix.changeJava], javaMajor: int.tryParse(jv.group(1)!), evidence: line(jv)));
    }
    final java8Mod = RegExp(r'java\.lang\.ClassCastException: class jdk\.internal\.loader\.ClassLoaders\$AppClassLoader cannot be cast to class java\.net\.URLClassLoader')
        .firstMatch(log);
    if (java8Mod != null) {
      add(CrashFinding('java_new', 'Java 版本过高', '这个版本（通常是 1.16.5 及以下的 Forge）只能用 Java 8 运行。请在版本设置中选择 Java 8。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.changeJava], javaMajor: 8, evidence: line(java8Mod)));
    }
    final oom = RegExp(r'java\.lang\.OutOfMemoryError(?:: (.+))?').firstMatch(log);
    if (oom != null) {
      final meta = (oom.group(1) ?? '').contains('Metaspace');
      add(CrashFinding('oom', '内存不足', meta ? 'Java 元空间耗尽，通常是 Mod 太多。请增加分配的内存或减少 Mod。' : '分配给游戏的内存用完了。请在「设置 → 内存」中调大最大内存，或减少 Mod / 光影 / 渲染距离。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.moreMemory], evidence: line(oom)));
    }
    final heap = RegExp(r'Could not reserve enough space for (?:object heap|\d+KB object heap)|Invalid maximum heap size|Error occurred during initialization of VM').firstMatch(log);
    if (heap != null) {
      add(CrashFinding('heap', '内存设置无效', '分配的内存超过了可用内存，或使用了只能用约 1.5 GB 的 32 位 Java。请降低最大内存，或改用 64 位 Java。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.moreMemory, CrashFix.changeJava], evidence: line(heap)));
    }
    final hs = RegExp(r'# Problematic frame:\s*\n#\s*(.+)').firstMatch(log);
    final accessViolation = RegExp(r'EXCEPTION_ACCESS_VIOLATION').firstMatch(log);
    if (hs != null || accessViolation != null) {
      final frame = hs?.group(1)?.trim() ?? '';
      final gpu = RegExp(r'(?:ig[0-9a-z]+icd|atio6axx|atig|nvoglv|amdxx|ig75icd|nvwgf)', caseSensitive: false).hasMatch(frame);
      add(CrashFinding('native', gpu ? '显卡驱动崩溃' : 'Java 原生代码崩溃',
          gpu ? '崩溃发生在显卡驱动（$frame）里。请更新显卡驱动；笔记本请让 Java 使用独立显卡；如开了光影，先关闭光影再试。' : 'Java 虚拟机在原生代码中崩溃${frame.isEmpty ? '' : '（$frame）'}。常见原因是显卡驱动、光影或 Mod 的原生库。请更新显卡驱动并关闭光影后再试。',
          confidence: gpu ? CrashConfidence.certain : CrashConfidence.likely, fixes: const [CrashFix.updateDriver], evidence: frame.isEmpty ? line(accessViolation!) : frame));
    }

    // ---- graphics ----
    final gl = RegExp(r'Pixel format not accelerated|GLFW error 65542|GLFW error 65543|Couldn.t set pixel format|WGL: The driver does not appear to support OpenGL|No OpenGL context found|OpenGL 3\.2 is not supported|Failed to create window')
        .firstMatch(log);
    if (gl != null) {
      add(CrashFinding('opengl', '显卡不支持 OpenGL', '显卡驱动没有提供游戏需要的 OpenGL。请安装显卡厂商的最新驱动（不要用 Windows 自带的「基本显示适配器」）；笔记本请让 Java 使用独立显卡。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.updateDriver], evidence: line(gl)));
    }

    // ---- Fabric / Quilt dependency resolution ----
    for (final m in RegExp(r"(?:Mod|mod) '([^']+)' \(([\w.\-]+)\) [\w.+\-]+ requires (?:any version|version [^ ]+|[^ ]+ version [^ ]+|version[^,\n]*?) of (?:mod )?'?([^',\n(]+?)'?(?: \(([\w.\-]+)\))?,? which is missing")
        .allMatches(log)) {
      final need = m.group(4) ?? m.group(3)!.trim();
      add(CrashFinding('missing_mod', '缺少前置 Mod', '「${m.group(1)}」需要「${m.group(3)!.trim()}」，但没有安装。请在「下载 → Mod」中搜索安装它。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.installMod], mods: [need], evidence: line(m)));
    }
    for (final m in RegExp(r"Install ([\w.\-]+), (?:version |any version)").allMatches(log)) {
      add(CrashFinding('missing_mod', '缺少前置 Mod', '请在「下载 → Mod」中安装缺少的前置 Mod。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.installMod], mods: [m.group(1)!], evidence: line(m)));
    }
    for (final m in RegExp(r"(?:Mod|mod) '([^']+)' \(([\w.\-]+)\) [\w.+\-]+ (?:requires|depends on) [^\n]*?'([^']+)' \(([\w.\-]+)\)[^\n]*?(?:but only the wrong version is present|but version [^\n]+ is present|, but only)")
        .allMatches(log)) {
      add(CrashFinding('mod_version', '前置 Mod 版本不对', '「${m.group(1)}」需要另一个版本的「${m.group(3)}」。请把「${m.group(3)}」更新或换成它要求的版本。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.installMod], mods: [m.group(4)!], evidence: line(m)));
    }
    for (final m in RegExp(r"(?:Mod|mod) '([^']+)' \(([\w.\-]+)\) [\w.+\-]+ (?:is incompatible with|breaks) [^\n]*?'([^']+)' \(([\w.\-]+)\)").allMatches(log)) {
      add(CrashFinding('incompatible', 'Mod 互相冲突', '「${m.group(1)}」与「${m.group(3)}」不兼容，请删除其中一个。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [m.group(2)!, m.group(4)!], evidence: line(m)));
    }
    for (final m in RegExp(r"Mod '([^']+)' \(([\w.\-]+)\)[^\n]*?requires version [^\n]*? of (?:minecraft|'Minecraft')").allMatches(log)) {
      add(CrashFinding('wrong_mc', 'Mod 与游戏版本不符', '「${m.group(1)}」不支持当前的 Minecraft 版本。请换成对应版本的 Mod，或删除它。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [m.group(2)!], evidence: line(m)));
    }
    for (final m in RegExp(r"Mod '([^']+)' \(([\w.\-]+)\)[^\n]*?requires (?:version [^\n]*? of )?(?:fabric loader|'Fabric Loader'|fabricloader)").allMatches(log)) {
      add(CrashFinding('loader_old', '加载器版本过低', '「${m.group(1)}」需要更新的 Fabric Loader。请在「下载」中重新安装最新版 Fabric。',
          confidence: CrashConfidence.certain, mods: [m.group(2)!], evidence: line(m)));
    }

    // ---- Forge / NeoForge ----
    // "Mod ID: 'x', Requested by: 'y', Expected range: '[a,b)', Actual version: '[MISSING]'"
    for (final m in RegExp(r"Mod ID: '?([\w.\-]+)'?, Requested by: '?([\w.\-]+)'?, Expected range: '?([^\n']+?)'?, Actual version: '?([^\n']+?)'?\s*$", multiLine: true)
        .allMatches(log)) {
      final id = m.group(1)!, by = m.group(2)!, range = m.group(3)!.trim(), actual = m.group(4)!.trim();
      if (actual.contains('MISSING')) {
        add(CrashFinding('missing_mod', '缺少前置 Mod', '「$by」需要「$id」（$range），但没有安装。请在「下载 → Mod」中搜索安装。',
            confidence: CrashConfidence.certain, fixes: const [CrashFix.installMod], mods: [id], evidence: line(m)));
      } else if (id == 'minecraft') {
        add(CrashFinding('wrong_mc', 'Mod 与游戏版本不符', '「$by」需要 Minecraft $range，当前是 $actual。请换成对应版本的 Mod。',
            confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [by], evidence: line(m)));
      } else if (id == 'forge' || id == 'neoforge') {
        add(CrashFinding('loader_old', '加载器版本不符', '「$by」需要 $id $range，当前是 $actual。请重新安装对应版本的加载器。',
            confidence: CrashConfidence.certain, mods: [by], evidence: line(m)));
      } else {
        add(CrashFinding('mod_version', '前置 Mod 版本不对', '「$by」需要「$id」$range，当前是 $actual。',
            confidence: CrashConfidence.certain, fixes: const [CrashFix.installMod], mods: [id], evidence: line(m)));
      }
    }
    final dup = RegExp(r'(?:DuplicateModsFoundException|Found duplicate mods|Duplicate mods found|duplicate mod ids?)[^\n]*', caseSensitive: false).firstMatch(log);
    if (dup != null) {
      final ids = {for (final m in RegExp(r"Mod ID: ['\x27]?([\w.\-]+)['\x27]? from mod files?: ").allMatches(log)) m.group(1)!};
      for (final m in RegExp(r"'([\w.\-]+)' \(\d").allMatches(dup.group(0)!)) {
        ids.add(m.group(1)!);
      }
      add(CrashFinding('duplicate', '存在重复的 Mod', 'mods 文件夹里有同一个 Mod 的多个文件${ids.isEmpty ? '' : '（${ids.join('、')}）'}。请只保留一个版本。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.openMods], mods: ids.toList(), evidence: line(dup)));
    }
    final wrongLoader = RegExp(r'(?:This (?:is a|mod is a) (Fabric|Forge|Quilt|NeoForge) mod|is a (Fabric|Forge|NeoForge) mod and cannot be loaded|Mod file [^\n]+ is for (Fabric|Forge))[^\n]*').firstMatch(log);
    if (wrongLoader != null) {
      add(CrashFinding('wrong_loader', 'Mod 用错了加载器', '有 Mod 是给 ${wrongLoader.group(1) ?? wrongLoader.group(2) ?? wrongLoader.group(3)} 用的，和当前的加载器不匹配。请换成对应加载器的版本。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.openMods], evidence: line(wrongLoader)));
    }

    // ---- mixin ----
    for (final m in RegExp(r'Mixin apply(?: for mod ([\w.\-]+))? failed ([\w.\-]+\.mixins?\.json|[\w.\-]+\.json)?[^\n]*').allMatches(log)) {
      final modId = m.group(1) ?? _modFromMixinConfig(m.group(2));
      add(CrashFinding('mixin', 'Mod 注入失败（Mixin）', modId == null
              ? '有 Mod 修改游戏代码失败，通常是 Mod 版本与游戏 / 其他 Mod 不兼容。请更新或删除最近添加的 Mod。'
              : '「$modId」修改游戏代码失败，通常是它与当前游戏版本或其他 Mod 不兼容。请更新或删除它。',
          confidence: modId == null ? CrashConfidence.likely : CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [?modId], evidence: line(m)));
    }
    for (final m in RegExp(r'InvalidInjectionException[^\n]*?([\w.\-]+\.mixins?\.json)').allMatches(log)) {
      final modId = _modFromMixinConfig(m.group(1));
      add(CrashFinding('mixin', 'Mod 注入失败（Mixin）', '「${modId ?? m.group(1)}」修改游戏代码失败，通常是版本不兼容。请更新或删除它。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [?modId], evidence: line(m)));
    }

    // ---- crash-report blame ----
    String? description;
    final desc = RegExp(r'^Description: (.+)$', multiLine: true).firstMatch(log);
    if (desc != null) description = desc.group(1)!.trim();
    final suspects = RegExp(r'Suspected Mods?: (.+)').firstMatch(log)?.group(1)?.trim();
    if (suspects != null && suspects != 'NONE' && suspects != 'None') {
      final ids = [for (final m in RegExp(r'\(([\w.\-]+)\)').allMatches(suspects)) m.group(1)!];
      add(CrashFinding('suspect', '崩溃报告指向了 Mod', '崩溃报告认为问题出在：$suspects。可以先禁用它再试。',
          confidence: CrashConfidence.likely, fixes: const [CrashFix.removeMod], mods: ids.isEmpty ? [suspects] : ids, evidence: 'Suspected Mods: $suspects'));
    }
    // Forge: "-- MOD xxx --" blocks / "Mod File: xxx.jar ... Failure message:"
    for (final m in RegExp(r'Mod File: (?:/|\\|[A-Za-z]:)?[^\n]*?([^/\\\n]+\.jar)\s*\n\s*Failure message: ([^\n]+)').allMatches(log)) {
      add(CrashFinding('mod_error', 'Mod 加载出错', '「${m.group(1)}」加载失败：${m.group(2)!.trim()}',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [m.group(1)!], evidence: line(m)));
    }
    // Fabric: "Could not execute entrypoint stage 'main' due to errors, provided by 'xxx'"
    for (final m in RegExp(r"Could not execute entrypoint stage '\w+' due to errors, provided by '([\w.\-]+)'").allMatches(log)) {
      add(CrashFinding('mod_error', 'Mod 启动出错', '「${m.group(1)}」初始化时出错。请更新或删除它。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.removeMod], mods: [m.group(1)!], evidence: line(m)));
    }

    // ---- environment ----
    final session = RegExp(r'Invalid session|Failed to verify username|invalid_token|401 Unauthorized').firstMatch(log);
    if (session != null) {
      add(CrashFinding('session', '登录已失效', '微软账号登录已过期。请在启动页重新登录后再进入服务器。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.relogin], evidence: line(session)));
    }
    final path = RegExp(r'The directory name is invalid|Invalid path|Illegal char <[^>]+> at index|无法将 .+ 识别为|URISyntaxException').firstMatch(log);
    if (path != null) {
      add(CrashFinding('path', '游戏路径有问题', '游戏目录路径里有特殊字符或中文，部分 Mod / 原生库无法处理。请把游戏移动到只含英文和数字的路径。',
          fixes: const [CrashFix.movePath], evidence: line(path)));
    }
    final files = RegExp(r'java\.lang\.(?:ClassNotFoundException|NoClassDefFoundError): (net\.minecraft[\w.$/]+|com\.mojang[\w.$/]+|org\.lwjgl[\w.$/]+)|Could not find or load main class|Error: Could not find or load main class|java\.util\.zip\.ZipException|invalid LOC header|Unable to read jar')
        .firstMatch(log);
    if (files != null) {
      add(CrashFinding('files', '游戏文件损坏或缺失', '游戏本体或依赖库文件不完整。请在「版本」页对这个版本点「补全文件」。',
          confidence: CrashConfidence.certain, fixes: const [CrashFix.repairFiles], evidence: line(files)));
    }
    // only real failures: skip "[main/WARN]: Error loading class …" notices mods print while scanning optional integrations
    final classMissing = RegExp(r'java\.lang\.(?:ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|NoSuchFieldError): ([\w.$/]+)')
        .allMatches(log)
        .where((m) => !RegExp(r'/(?:WARN|INFO|DEBUG)\]|\[(?:WARN|INFO|DEBUG)\]|Error loading class').hasMatch(line(m)))
        .firstOrNull;
    if (classMissing != null && files == null) {
      final cls = classMissing.group(1)!;
      final what = cls.contains('(') || classMissing.group(0)!.contains('NoSuch') ? '方法 / 字段' : '类';
      add(CrashFinding('class_missing', 'Mod 与版本不兼容', '找不到$what $cls。通常是某个 Mod 是给其他游戏版本做的、缺少前置，或与其他 Mod 不兼容。',
          confidence: CrashConfidence.possible, fixes: const [CrashFix.openMods], evidence: line(classMissing)));
    }
    // ---- stack trace → mod (PCL-style): the first frame of the exception that belongs to an installed mod ----
    if (mods.isNotEmpty && !found.values.any((f) => f.confidence == CrashConfidence.certain && f.mods.isNotEmpty)) {
      final blamed = _blameFromStack(log, mods);
      if (blamed != null) {
        add(CrashFinding('stack_mod', '崩溃发生在 Mod 的代码里', '错误是「${blamed.$1}」抛出的（${blamed.$2}）。请先更新这个 Mod；如果最近才装，先禁用它再试。',
            fixes: const [CrashFix.removeMod], mods: [blamed.$1], evidence: blamed.$3));
      }
    }
    // no installed jar matched (or no mods folder): name the first third-party package in the trace
    if (!found.values.any((f) => f.mods.isNotEmpty && f.confidence != CrashConfidence.possible) && !found.containsKey('stack_mod')) {
      final pkg = _foreignPackage(log);
      if (pkg != null) {
        add(CrashFinding('stack_pkg', '崩溃可能来自某个 Mod', '错误发生在 ${pkg.$1} 的代码里（${pkg.$2}）。请在 mods 文件夹中找到包含这个名字的 Mod，更新或禁用它。',
            confidence: CrashConfidence.possible, fixes: const [CrashFix.openMods], mods: [pkg.$1], evidence: pkg.$3));
      }
    }
    final badJson = RegExp(r'(?:MalformedJsonException|JsonSyntaxException|JsonParseException|Couldn.t parse data file|Failed to (?:parse|load) (?:config|options))[^\n]*').firstMatch(log);
    if (badJson != null && !found.values.any((f) => f.confidence == CrashConfidence.certain)) {
      add(CrashFinding('bad_data', '配置或数据文件损坏', '游戏读取的某个 JSON 文件格式不对（常见于 config 文件夹、服务器的 server.properties / 白名单，或数据包）。请检查最近改过的配置文件，或先删除 config 文件夹里对应 Mod 的配置让它重新生成。',
          fixes: const [CrashFix.openMods], evidence: line(badJson)));
    }
    final shaders = RegExp(r'(?:optifine|iris|oculus)[^\n]*(?:Exception|Error)|Shader[^\n]+(?:compile|link)[^\n]*(?:failed|error)', caseSensitive: false).firstMatch(log);
    if (shaders != null && found.isEmpty) {
      add(CrashFinding('shaders', '光影或 OptiFine 出错', '崩溃和光影 / OptiFine / Iris 有关。请先关闭光影或删除 OptiFine 再试。',
          confidence: CrashConfidence.possible, fixes: const [CrashFix.removeMod], evidence: line(shaders)));
    }
    if (found.isEmpty && exitCode == -805306369) {
      add(const CrashFinding('hang', '游戏无响应被结束', '游戏卡死后被系统或用户结束（退出码 -805306369）。常见原因是内存不足或渲染距离过大。',
          confidence: CrashConfidence.possible, fixes: [CrashFix.moreMemory]));
    }

    final list = found.values.toList()..sort((a, b) => a.confidence.index.compareTo(b.confidence.index));
    return CrashReport(list, sources, description, _excerpt(log), exitCode);
  }

  /// Walks the exception and its "Caused by" sections from the deepest cause up and returns
  /// (jar, class.method, frame line) for the first frame inside an installed mod.
  static (String, String, String)? _blameFromStack(String log, List<ModPackage> mods) {
    final lines = const LineSplitter().convert(log);
    // only the main trace (before the "System Details" / "-- Head --" sections repeats it)
    final end = lines.indexWhere((l) => l.trimLeft().startsWith('A detailed walkthrough of the error'));
    final trace = end > 0 ? lines.sublist(0, end) : lines;
    final causeStarts = [for (var i = 0; i < trace.length; i++) if (trace[i].trimLeft().startsWith('Caused by:')) i];
    final sections = [...causeStarts.reversed, 0];
    for (final start in sections) {
      for (var i = start + 1; i < trace.length && i < start + 60; i++) {
        final l = trace[i].trim();
        if (l.startsWith('Caused by:')) break;
        final m = RegExp(r'^at (?:[\w.]+//)?([\w.$]+)\.([\w$<>]+)\(').firstMatch(l);
        if (m == null) continue;
        final cls = m.group(1)!;
        for (final mod in mods) {
          if (mod.packages.any((pkg) => cls == pkg || cls.startsWith('$pkg.'))) return (mod.file, '${cls.split('.').last}.${m.group(2)}', l);
        }
      }
    }
    return null;
  }

  /// Game, loader, JDK and common library code — never the culprit on its own.
  static final _framework = RegExp(r'^(?:java|javax|jdk|sun|com\.sun|net\.minecraft|com\.mojang|net\.minecraftforge|net\.neoforged|cpw\.mods|net\.fabricmc|org\.quiltmc|org\.spongepowered|org\.lwjgl|io\.netty|com\.google|org\.apache|it\.unimi|joptsimple|oshi|org\.slf4j|kotlin|scala|com\.mumfrey\.liteloader|gg\.essential\.loader|org\.objectweb|optifine|net\.optifine|knot)(?:\.|$)|^[a-z]{1,3}$');

  /// (package, class.method, frame) of the deepest-cause frame that isn't framework code.
  static (String, String, String)? _foreignPackage(String log) {
    final lines = const LineSplitter().convert(log);
    final end = lines.indexWhere((l) => l.trimLeft().startsWith('A detailed walkthrough of the error'));
    final trace = end > 0 ? lines.sublist(0, end) : lines;
    final causeStarts = [for (var i = 0; i < trace.length; i++) if (trace[i].trimLeft().startsWith('Caused by:')) i];
    for (final start in [...causeStarts.reversed, 0]) {
      for (var i = start + 1; i < trace.length && i < start + 60; i++) {
        final l = trace[i].trim();
        if (l.startsWith('Caused by:')) break;
        final m = RegExp(r'^at (?:[\w.]+//)?([\w.$]+)\.([\w$<>]+)\(').firstMatch(l);
        if (m == null) continue;
        final cls = m.group(1)!;
        final parts = cls.split('.');
        // obfuscated vanilla classes (`adm`, `bdb`) are top-level; skip them and framework code
        if (parts.length < 2 || _framework.hasMatch(cls)) continue;
        return (parts.take(parts.length > 3 ? 3 : parts.length - 1).join('.'), '${parts.last}.${m.group(2)}', l);
      }
    }
    return null;
  }

  /// `examplemod.mixins.json` / `mixins.examplemod.json` → `examplemod`.
  static String? _modFromMixinConfig(String? cfg) {
    if (cfg == null) return null;
    final base = cfg.replaceAll(RegExp(r'\.json$'), '');
    final parts = base.split('.').where((x) => x != 'mixins' && x != 'mixin' && x.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.first;
  }

  /// Exception headline + "Caused by" chain + first frames of each, max ~40 lines.
  static List<String> _excerpt(String log) {
    final lines = const LineSplitter().convert(log);
    final out = <String>[];
    for (var i = 0; i < lines.length && out.length < 40; i++) {
      final l = lines[i];
      final head = RegExp(r'(Exception|Error)(:|$)|^Caused by:|Suspected Mods?:|^Description:|Failure message:|which is missing|requires .+ of|# Problematic frame').hasMatch(l) &&
          !l.trimLeft().startsWith('at ');
      if (!head) continue;
      out.add(l.trimRight());
      for (var j = i + 1; j < lines.length && j <= i + 3 && lines[j].trimLeft().startsWith('at '); j++) {
        out.add(lines[j].trimRight());
      }
    }
    // keep each distinct line once (the same trace appears in latest.log and the crash report)
    final seen = <String>{};
    return [for (final l in out) if (seen.add(l.trim())) l];
  }
}

/// A mod jar and the Java packages only it provides.
class ModPackage {
  final String file;
  final Set<String> packages;
  const ModPackage(this.file, this.packages);
}
