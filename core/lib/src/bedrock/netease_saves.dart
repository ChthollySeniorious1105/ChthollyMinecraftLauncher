import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../addons/addons.dart';
import '../common/errors.dart';
import '../common/os.dart';
import '../saves/worlds.dart';

// ---------------------------------------------------------------- GBK (code page 936)

typedef _MbToWcC = Int32 Function(Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>, Int32);
typedef _MbToWcD = int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int);
typedef _WcToMbC = Int32 Function(Uint32, Uint32, Pointer<Uint16>, Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Pointer<Int32>);
typedef _WcToMbD = int Function(int, int, Pointer<Uint16>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Int32>);

/// GBK / CP936 conversion through the Windows code-page APIs (MultiByteToWideChar / WideCharToMultiByte).
/// On other platforms it falls back to Latin-1-ish byte passthrough for ASCII.
abstract class Gbk {
  static const codePage = 936;
  static final DynamicLibrary? _k32 = Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;
  static final _mb2wc = _k32?.lookupFunction<_MbToWcC, _MbToWcD>('MultiByteToWideChar');
  static final _wc2mb = _k32?.lookupFunction<_WcToMbC, _WcToMbD>('WideCharToMultiByte');

  static String decode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final f = _mb2wc;
    if (f == null) return String.fromCharCodes(bytes.map((b) => b < 0x80 ? b : 0xFFFD));
    final src = calloc<Uint8>(bytes.length);
    try {
      src.asTypedList(bytes.length).setAll(0, bytes);
      final n = f(codePage, 0, src, bytes.length, nullptr, 0);
      if (n <= 0) return String.fromCharCodes(bytes);
      final dst = calloc<Uint16>(n);
      try {
        f(codePage, 0, src, bytes.length, dst, n);
        return String.fromCharCodes(dst.asTypedList(n));
      } finally {
        calloc.free(dst);
      }
    } finally {
      calloc.free(src);
    }
  }

  static Uint8List encode(String s) {
    if (s.isEmpty) return Uint8List(0);
    final f = _wc2mb;
    final units = s.codeUnits;
    if (f == null) return Uint8List.fromList([for (final c in units) c < 0x80 ? c : 0x3F]);
    final src = calloc<Uint16>(units.length);
    try {
      src.asTypedList(units.length).setAll(0, units);
      final n = f(codePage, 0, src, units.length, nullptr, 0, nullptr, nullptr);
      final dst = calloc<Uint8>(n);
      try {
        f(codePage, 0, src, units.length, dst, n, nullptr, nullptr);
        return Uint8List.fromList(dst.asTypedList(n));
      } finally {
        calloc.free(dst);
      }
    } finally {
      calloc.free(src);
    }
  }

  /// True when every character survives a GBK round trip (NeMcDecrypter reads the path as GBK).
  static bool canEncode(String s) => decode(encode(s)) == s;
}

// ---------------------------------------------------------------- NeMcDecrypter

enum NeteaseAction {
  /// 2.查看文件/文件夹加密状态
  status('2', '检查加密状态', writes: false),

  /// 0.网易地图解密 (decrypts the db files in place)
  decrypt('0', '解密存档', writes: true),

  /// 3.获取存档秘钥
  readKey('3', '读取存档密钥', writes: false);

  final String menu;
  final String label;
  final bool writes;
  const NeteaseAction(this.menu, this.label, {required this.writes});
}

/// One line of NeMcDecrypter output. The tool prefixes messages with `I:` (info) / `E:` (error).
class NeteaseLine {
  final String text;
  const NeteaseLine(this.text);
  bool get isError => text.startsWith('E:') || text.contains('Exception');
  bool get isInfo => text.startsWith('I:');
  String get message => (isInfo || text.startsWith('E:')) ? text.substring(2) : text;
}

class NeteaseResult {
  final NeteaseAction action;
  final String dbPath;
  final int exitCode;
  final List<NeteaseLine> lines;
  final String? backup;

  /// `[已加密]xxx` / `[未加密]xxx` counts parsed from the status scan.
  final int encrypted;
  final int plain;

  /// Key printed by [NeteaseAction.readKey], if any.
  final String? key;
  const NeteaseResult(this.action, this.dbPath, this.exitCode, this.lines, {this.backup, this.encrypted = 0, this.plain = 0, this.key});

  bool get hasError => lines.any((l) => l.isError);
  bool get worldEncrypted => lines.any((l) => l.text.contains('读取到加密存档')) || encrypted > 0;
  bool get worldPlain => lines.any((l) => l.text.contains('未加密存档')) || (plain > 0 && encrypted == 0);
}

/// Drives the bundled NeMcDecrypter.exe (third-party, Java-based console tool) for the user's OWN
/// NetEase (China edition) Bedrock worlds. Interactive menu → we write `<menu>\r\n<db path>\r\n` to stdin
/// and close it; the tool exits on EOF. Output and input are GBK.
class NeteaseSaves {
  final String exe;
  NeteaseSaves({String? exe}) : exe = exe ?? Bundled.neteaseDecrypter;

  bool get available => File(exe).existsSync();

  static String get backupDir => p.join(Os.cmlHome, 'backups', 'netease');

  /// Folders where NetEase Bedrock (PC 我的世界 / 网易版基岩) usually keeps worlds; only existing ones.
  static List<String> candidateWorldRoots() {
    final app = Os.appData;
    final local = Os.localAppData;
    final c = <String>[
      p.join(app, 'MinecraftPE_Netease', 'minecraftWorlds'),
      p.join(local, 'MinecraftPE_Netease', 'minecraftWorlds'),
      p.join(app, 'MinecraftPE_Netease', 'games', 'com.netease', 'minecraftWorlds'),
      p.join(app, 'Netease', 'MinecraftPE', 'minecraftWorlds'),
    ];
    return c.where((d) => Directory(d).existsSync()).toList();
  }

  /// Worlds (folders containing db\CURRENT) under [root].
  static List<Directory> worldsIn(String root) {
    final d = Directory(root);
    if (!d.existsSync()) return [];
    return d.listSync().whereType<Directory>().where((w) => File(p.join(w.path, 'db', 'CURRENT')).existsSync()).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }

  /// Display name from levelname.txt (GBK or UTF-8), else the folder name.
  static String worldName(String worldDir) {
    final f = File(p.join(worldDir, 'levelname.txt'));
    if (f.existsSync()) {
      final b = f.readAsBytesSync();
      try {
        return utf8.decode(b).trim();
      } on FormatException {
        return Gbk.decode(b).trim();
      }
    }
    return p.basename(worldDir);
  }

  /// Accepts a world folder or its db folder; returns the db folder (must contain CURRENT and a MANIFEST).
  static String resolveDb(String path) {
    var db = path;
    if (!File(p.join(db, 'CURRENT')).existsSync() && File(p.join(path, 'db', 'CURRENT')).existsSync()) db = p.join(path, 'db');
    if (!File(p.join(db, 'CURRENT')).existsSync()) {
      throw const CmlException('netease_no_db', '这个文件夹不是基岩版存档（找不到 db\\CURRENT）');
    }
    final hasManifest = Directory(db).listSync().any((e) => p.basename(e.path).startsWith('MANIFEST-'));
    if (!hasManifest) throw const CmlException('netease_no_manifest', '存档 db 文件夹缺少 MANIFEST 文件');
    return db;
  }

  /// Zips the world (parent of db) into `%APPDATA%\CML\backups\netease`.
  static Future<String> backup(String dbPath) async {
    final world = p.basename(dbPath).toLowerCase() == 'db' ? p.dirname(dbPath) : dbPath;
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final safe = p.basename(world).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    final out = p.join(backupDir, '$safe-$stamp.zip');
    await Worlds.zipDir(world, out, includeFolder: true);
    return out;
  }

  /// Runs [action] on the world at [path]. Writing actions back up first unless [backupFirst] is false.
  Future<NeteaseResult> run(NeteaseAction action, String path,
      {bool backupFirst = true, void Function(NeteaseLine l)? onLine, Duration timeout = const Duration(minutes: 10)}) async {
    if (!available) throw CmlException('tool_missing', '找不到 ${p.basename(exe)}，请重新安装 CML');
    final db = resolveDb(p.normalize(path));
    if (!Gbk.canEncode(db)) {
      throw const CmlException('netease_path', '存档路径含有 GBK 无法表示的字符，请把存档复制到纯中文/英文路径下再试');
    }
    String? bak;
    if (action.writes && backupFirst) bak = await backup(db);

    final proc = await Process.start(exe, const [], workingDirectory: p.dirname(exe));
    final lines = <NeteaseLine>[];
    var encrypted = 0, plain = 0;
    String? key;
    final done = <Future<void>>[];
    void pipe(Stream<List<int>> s) {
      final c = Completer<void>();
      done.add(c.future);
      final buf = <int>[];
      void flushLine() {
        final text = cleanLine(Gbk.decode(buf));
        buf.clear();
        if (text.isEmpty) return;
        for (final t in splitPrompts(text)) {
          final l = NeteaseLine(t);
          if (t.startsWith('[已加密]')) encrypted++;
          if (t.startsWith('[未加密]')) plain++;
          key ??= parseKey(t);
          lines.add(l);
          onLine?.call(l);
        }
      }

      s.listen((chunk) {
        for (final b in chunk) {
          if (b == 0x0A) {
            flushLine();
          } else {
            buf.add(b);
          }
        }
      }, onDone: () {
        flushLine();
        c.complete();
      });
    }

    pipe(proc.stdout);
    pipe(proc.stderr);
    proc.stdin.add(Gbk.encode('${action.menu}\r\n$db\r\n'));
    await proc.stdin.flush();
    await proc.stdin.close();
    final code = await proc.exitCode.timeout(timeout, onTimeout: () {
      proc.kill(ProcessSignal.sigkill);
      return -1;
    });
    await Future.wait(done).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    return NeteaseResult(action, db, code, lines, backup: bak, encrypted: encrypted, plain: plain, key: key);
  }

  /// Drops the ASCII-art banner, menu and CR characters.
  static String cleanLine(String s) {
    final t = s.replaceAll('\r', '').trimRight();
    if (t.trim().isEmpty) return '';
    if (RegExp(r'^[@\s]+$').hasMatch(t)) return ''; // banner
    if (t.contains('Developed by')) return '';
    if (RegExp(r'^\s*[0-3]\.').hasMatch(t)) return ''; // menu entries
    return t.trim();
  }

  /// The prompts have no newline, so the first answer is glued to them:
  /// `请选择运行方式0/1/2:请将db文件夹拖至此处->I:...` → `I:...`.
  static List<String> splitPrompts(String s) {
    var t = s;
    final arrow = t.lastIndexOf('->');
    if (arrow >= 0 && (t.contains('请选择') || t.contains('拖至此处') || t.contains('拖到此处'))) t = t.substring(arrow + 2);
    t = t.replaceAll(RegExp(r'^请选择运行方式[0-9/]*:'), '').replaceAll(RegExp(r'^请输入加密方式:'), '').trim();
    t = t.replaceAll(RegExp(r'^-{3,}\s*'), '').replaceAll(RegExp(r'\s*-{3,}$'), '').trim();
    return t.isEmpty ? const [] : [t];
  }

  /// Looks for a key printed as `秘钥:xxxx` / `密钥：xxxx` / `key: xxxx`.
  static String? parseKey(String s) {
    final m = RegExp(r'(?:秘钥|密钥|key)\s*[:：=]\s*([0-9A-Za-z+/=_-]{6,})', caseSensitive: false).firstMatch(s);
    return m?.group(1);
  }
}
