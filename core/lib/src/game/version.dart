import '../common/os.dart';

/// Maven coordinate `group:artifact:version[:classifier][@ext]`.
class MavenName {
  final String group, artifact, version;
  final String? classifier;
  final String ext;
  MavenName(this.group, this.artifact, this.version, [this.classifier, this.ext = 'jar']);

  factory MavenName.parse(String s) {
    var ext = 'jar';
    final at = s.indexOf('@');
    if (at >= 0) {
      ext = s.substring(at + 1);
      s = s.substring(0, at);
    }
    final p = s.split(':');
    if (p.length < 3) throw FormatException('bad maven name: $s');
    return MavenName(p[0], p[1], p[2], p.length > 3 ? p[3] : null, ext);
  }

  /// Relative path inside a maven repo / `.minecraft/libraries`.
  String get path {
    final c = classifier == null ? '' : '-$classifier';
    return '${group.replaceAll('.', '/')}/$artifact/$version/$artifact-$version$c.$ext';
  }

  /// Key used for de-duplication when merging inherited versions (version excluded).
  String get key => '$group:$artifact${classifier == null ? '' : ':$classifier'}';

  MavenName withClassifier(String c) => MavenName(group, artifact, version, c, ext);

  @override
  String toString() => '$group:$artifact:$version${classifier == null ? '' : ':$classifier'}${ext == 'jar' ? '' : '@$ext'}';
}

/// Feature flags for argument rules.
class LaunchFeatures {
  final bool customResolution;
  final bool quickPlayMultiplayer;
  final bool quickPlaySingleplayer;
  final bool demo;
  const LaunchFeatures({this.customResolution = false, this.quickPlayMultiplayer = false, this.quickPlaySingleplayer = false, this.demo = false});

  bool has(String f) => switch (f) {
        'has_custom_resolution' => customResolution,
        'is_quick_play_multiplayer' => quickPlayMultiplayer,
        'is_quick_play_singleplayer' => quickPlaySingleplayer,
        'is_demo_user' => demo,
        _ => false,
      };
}

/// Evaluates `rules` arrays from version JSON.
abstract class Rules {
  static bool allows(Object? rules, [LaunchFeatures features = const LaunchFeatures()]) {
    if (rules is! List || rules.isEmpty) return true;
    var allowed = false;
    for (final r in rules) {
      if (r is! Map) continue;
      if (!_matches(r, features)) continue;
      allowed = r['action'] == 'allow';
    }
    return allowed;
  }

  static bool _matches(Map r, LaunchFeatures features) {
    final os = r['os'];
    if (os is Map) {
      if (os['name'] != null && os['name'] != Os.name) return false;
      if (os['arch'] != null) {
        final a = os['arch'];
        final mine = Os.arch;
        if (!(a == mine || (a == 'x86' && mine == 'x86'))) return false;
      }
      if (os['version'] != null) {
        try {
          if (!RegExp('${os['version']}').hasMatch(Os.osVersion)) return false;
        } on FormatException {
          return false;
        }
      }
    }
    final f = r['features'];
    if (f is Map) {
      for (final e in f.entries) {
        if (features.has('${e.key}') != (e.value == true)) return false;
      }
    }
    return true;
  }
}

/// A downloadable file reference from version JSON.
class FileRef {
  final String url;
  final String? sha1;
  final int size;
  final String? path;
  const FileRef(this.url, {this.sha1, this.size = 0, this.path});

  static FileRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = '${j['url'] ?? ''}';
    return FileRef(url, sha1: j['sha1'] as String?, size: (j['size'] as num?)?.toInt() ?? 0, path: j['path'] as String?);
  }
}

class Library {
  final MavenName name;
  final FileRef? artifact;

  /// Old-style natives: classifier → file (e.g. `natives-windows`).
  final Map<String, FileRef> classifiers;

  /// `natives` map: os → classifier template (may contain `${arch}`).
  final Map<String, String> natives;
  final Object? rules;

  /// Maven repo base URL for loader libraries that only give `name` + `url`.
  final String? repo;
  final bool extractExcludeMetaInf;

  /// Whether the library goes on the classpath (`clientreq` false on very old forge entries still goes).
  final bool onClasspath;

  Library({
    required this.name,
    this.artifact,
    this.classifiers = const {},
    this.natives = const {},
    this.rules,
    this.repo,
    this.extractExcludeMetaInf = true,
    this.onClasspath = true,
  });

  factory Library.fromJson(Map j) {
    final dl = j['downloads'];
    final cls = <String, FileRef>{};
    if (dl is Map && dl['classifiers'] is Map) {
      (dl['classifiers'] as Map).forEach((k, v) {
        final f = FileRef.fromJson(v);
        if (f != null) cls['$k'] = f;
      });
    }
    final nat = <String, String>{};
    if (j['natives'] is Map) (j['natives'] as Map).forEach((k, v) => nat['$k'] = '$v');
    return Library(
      name: MavenName.parse('${j['name']}'),
      artifact: dl is Map ? FileRef.fromJson(dl['artifact']) : null,
      classifiers: cls,
      natives: nat,
      rules: j['rules'],
      repo: j['url'] as String?,
      onClasspath: j['clientreq'] != false || j['serverreq'] == null,
    );
  }

  bool get applies => Rules.allows(rules);

  /// True for 1.19+ style native artifacts (`…:natives-windows`).
  bool get isNativeArtifact => name.classifier?.startsWith('natives-') ?? false;

  /// Classifier of the old-style native for the current OS, or null.
  String? get nativeClassifier {
    final t = natives[Os.name];
    if (t == null) return null;
    return t.replaceAll(r'${arch}', Os.arch == 'x86' ? '32' : '64');
  }

  /// Main artifact path relative to libraries dir.
  String get path => artifact?.path ?? name.path;

  /// Main artifact URL ('' when there is nothing to download).
  String get url {
    if (artifact != null) return artifact!.url;
    final base = repo ?? 'https://libraries.minecraft.net/';
    return '${base.endsWith('/') ? base : '$base/'}${name.path}';
  }
}

class AssetIndexRef {
  final String id;
  final FileRef file;
  final int totalSize;
  AssetIndexRef(this.id, this.file, this.totalSize);
}

/// Parsed + inheritance-resolved version JSON.
class GameVersion {
  final String id;
  final Map<String, dynamic> raw;
  final String? inheritsFrom;
  final String mainClass;
  final String type;
  final DateTime? releaseTime;
  final List<Library> libraries;
  final List<Object> gameArgs;
  final List<Object> jvmArgs;
  final String? legacyArgs; // minecraftArguments
  final AssetIndexRef? assetIndex;
  final String? assets;
  final FileRef? client;

  /// Jar to use: own id or `jar` field / parent id for loader versions.
  final String jar;
  final int? javaMajor;
  final String? javaComponent;
  final String? loggingArgument;
  final FileRef? loggingFile;
  final String? loggingId;

  /// Vanilla MC version this resolves to (deepest parent).
  final String baseVersion;

  GameVersion._({
    required this.id,
    required this.raw,
    required this.inheritsFrom,
    required this.mainClass,
    required this.type,
    required this.releaseTime,
    required this.libraries,
    required this.gameArgs,
    required this.jvmArgs,
    required this.legacyArgs,
    required this.assetIndex,
    required this.assets,
    required this.client,
    required this.jar,
    required this.javaMajor,
    required this.javaComponent,
    required this.loggingArgument,
    required this.loggingFile,
    required this.loggingId,
    required this.baseVersion,
  });

  /// Builds a resolved version. [parent] must already be resolved when `inheritsFrom` is set.
  factory GameVersion.resolve(Map<String, dynamic> j, {GameVersion? parent}) {
    final libs = <Library>[];
    final keys = <String>{};
    void addLibs(Iterable<Library> ls) {
      for (final l in ls) {
        // natives are distinct per classifier; keep the child's copy of a duplicate
        final k = '${l.name.key}|${l.nativeClassifier ?? ''}';
        if (keys.add(k)) libs.add(l);
      }
    }

    addLibs([for (final l in (j['libraries'] as List? ?? const [])) if (l is Map && l['name'] != null) Library.fromJson(l)]);
    if (parent != null) addLibs(parent.libraries);

    final args = j['arguments'] as Map?;
    final game = <Object>[...?parent?.gameArgs, ...?(args?['game'] as List?)?.cast<Object>()];
    final jvm = <Object>[...?parent?.jvmArgs, ...?(args?['jvm'] as List?)?.cast<Object>()];

    final ai = j['assetIndex'] as Map?;
    final dls = j['downloads'] as Map?;
    final java = j['javaVersion'] as Map?;
    final logging = (j['logging'] as Map?)?['client'] as Map?;

    return GameVersion._(
      id: '${j['id']}',
      raw: j,
      inheritsFrom: j['inheritsFrom'] as String?,
      mainClass: (j['mainClass'] as String?) ?? parent?.mainClass ?? 'net.minecraft.client.main.Main',
      type: (j['type'] as String?) ?? parent?.type ?? 'release',
      releaseTime: DateTime.tryParse('${j['releaseTime'] ?? ''}') ?? parent?.releaseTime,
      libraries: libs,
      gameArgs: game,
      jvmArgs: jvm,
      legacyArgs: (j['minecraftArguments'] as String?) ?? (args == null ? parent?.legacyArgs : null),
      assetIndex: ai != null ? AssetIndexRef('${ai['id']}', FileRef.fromJson(ai)!, (ai['totalSize'] as num?)?.toInt() ?? 0) : parent?.assetIndex,
      assets: (j['assets'] as String?) ?? parent?.assets,
      client: FileRef.fromJson(dls?['client']) ?? parent?.client,
      jar: (j['jar'] as String?) ?? parent?.jar ?? '${j['id']}',
      javaMajor: (java?['majorVersion'] as num?)?.toInt() ?? parent?.javaMajor,
      javaComponent: (java?['component'] as String?) ?? parent?.javaComponent,
      loggingArgument: (logging?['argument'] as String?) ?? parent?.loggingArgument,
      loggingFile: FileRef.fromJson(logging?['file']) ?? parent?.loggingFile,
      loggingId: ((logging?['file'] as Map?)?['id'] as String?) ?? parent?.loggingId,
      baseVersion: parent?.baseVersion ?? (j['clientVersion'] as String?) ?? '${j['id']}',
    );
  }

  bool get usesLegacyArgs => gameArgs.isEmpty && legacyArgs != null;

  /// Detected mod loaders from libraries / main class.
  Set<ModLoader> get loaders {
    final s = <ModLoader>{};
    for (final l in libraries) {
      final k = '${l.name.group}:${l.name.artifact}';
      if (k == 'net.fabricmc:fabric-loader') s.add(ModLoader.fabric);
      if (k == 'org.quiltmc:quilt-loader') s.add(ModLoader.quilt);
      if (k.startsWith('net.neoforged')) s.add(ModLoader.neoforge);
      if (k == 'net.minecraftforge:forge' || k == 'net.minecraftforge:fmlloader' || k == 'net.minecraftforge:minecraftforge') {
        s.add(ModLoader.forge);
      }
      if (k == 'optifine:OptiFine') s.add(ModLoader.optifine);
      if (k.startsWith('com.cleanroommc')) s.add(ModLoader.cleanroom);
      if (k == 'net.legacyfabric:fabric-loader') s.add(ModLoader.fabric);
    }
    if (mainClass.contains('cpw.mods') && !s.contains(ModLoader.neoforge)) s.add(ModLoader.forge);
    if (s.contains(ModLoader.neoforge)) s.remove(ModLoader.forge);
    return s;
  }

  /// Required Java major version (from JSON, else guessed from release date).
  int get requiredJava {
    if (javaMajor != null) return javaMajor!;
    final t = releaseTime;
    if (t == null) return 8;
    if (t.isAfter(DateTime.utc(2024, 4, 23))) return 21; // 24w14a+
    if (t.isAfter(DateTime.utc(2021, 11, 15))) return 17; // 1.18 pre
    if (t.isAfter(DateTime.utc(2021, 5, 10))) return 16; // 21w19a
    return 8;
  }
}

enum ModLoader {
  forge('Forge'),
  neoforge('NeoForge'),
  fabric('Fabric'),
  quilt('Quilt'),
  optifine('OptiFine'),
  cleanroom('Cleanroom'),
  liteloader('LiteLoader');

  final String label;
  const ModLoader(this.label);

  /// Modrinth loader slug.
  String get slug => name;
}
