import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../addons/addons.dart';
import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';

/// Bedrock version the bundled BedrockTool (gophertunnel fork) speaks.
///
/// Keep in sync with `tools/bedrocktool/gophertunnel/minecraft/protocol/info.go`
/// (CurrentProtocol / CurrentVersion) — see `tools/bedrocktool/PROTOCOL_UPDATE.md`.
abstract class BedrockToolInfo {
  static const supportedVersion = '26.52';
  static const gameVersion = '1.26.52';
  static const protocol = 2193;
}

enum BtFlagType { boolean, string, integer, list, address }

/// One command-line flag of a BedrockTool subcommand.
class BtFlag {
  final String name;
  final BtFlagType type;
  final String defaultValue;
  final String description;
  const BtFlag(this.name, this.type, {this.defaultValue = '', this.description = ''});

  bool get defaultBool => defaultValue == 'true';

  @override
  String toString() => 'BtFlag($name, ${type.name}, default=$defaultValue)';
}

/// A subcommand plus its flags. [positional] is set for commands that take trailing args (merge).
class BtCommand {
  final String name;
  final String description;
  final List<BtFlag> flags;
  final bool positional;
  const BtCommand(this.name, this.description, this.flags, {this.positional = false});

  BtFlag? flag(String n) => flags.where((f) => f.name == n).firstOrNull;
}

/// Known subcommands of the bundled build (v26.52, parsed from the Go settings structs).
/// [BedrockTool.describe] re-reads them from the exe when available.
abstract class BtCommands {
  static const _proxy = [
    BtFlag('address', BtFlagType.address, description: 'remote server address'),
    BtFlag('listen', BtFlagType.string, defaultValue: '0.0.0.0:19132', description: 'example :19132 or 127.0.0.1:19132'),
    BtFlag('capture', BtFlagType.boolean, defaultValue: 'true', description: 'Capture pcap2 file'),
    BtFlag('client-cache', BtFlagType.boolean, defaultValue: 'true', description: 'Enable Client Cache'),
    BtFlag('debug', BtFlagType.boolean, description: 'debug mode'),
    BtFlag('extra-debug', BtFlagType.boolean, description: 'extra debug info (packet.log)'),
  ];

  static const worlds = BtCommand('worlds', 'download a world from a server', [
    ..._proxy,
    BtFlag('void', BtFlagType.boolean, defaultValue: 'true', description: 'save with void generator'),
    BtFlag('image', BtFlagType.boolean, description: 'saves an png of the map at the end'),
    BtFlag('save-entities', BtFlagType.boolean, defaultValue: 'true', description: 'Save Entities'),
    BtFlag('save-players', BtFlagType.boolean, description: 'save players as entities'),
    BtFlag('save-inventories', BtFlagType.boolean, defaultValue: 'true', description: 'Save Inventories'),
    BtFlag('block-updates', BtFlagType.boolean, description: 'Block updates'),
    BtFlag('entity-culling', BtFlagType.boolean, description: 'Remove Entities which died or are deleted (experimental)'),
    BtFlag('exclude-mobs', BtFlagType.list, description: 'list of mobs to exclude seperated by comma'),
    BtFlag('chunk-radius', BtFlagType.integer, defaultValue: '0', description: 'the max chunk radius to force'),
    BtFlag('script', BtFlagType.string, description: 'path to script to use'),
  ]);
  static const skins = BtCommand('skins', 'download skins from players on a server', [
    ..._proxy,
    BtFlag('filter', BtFlagType.string, description: 'Name Regex (save if it matches)'),
    BtFlag('no-proxy', BtFlagType.boolean, description: 'No Proxy'),
    BtFlag('texture-only', BtFlagType.boolean, description: 'Texture Only'),
    BtFlag('timestamped', BtFlagType.boolean, defaultValue: 'true', description: 'Timestamped'),
  ]);
  static const capture = BtCommand('capture', 'capture packets in a pcap file', _proxy);
  static const chatLog = BtCommand('chat-log', 'logs chat to a file', [..._proxy, BtFlag('verbose', BtFlagType.boolean, description: 'Verbose')]);
  static const realmsList = BtCommand('list-realms', 'prints all realms you have access to', []);
  static const realmAddress = BtCommand('realm-address', 'gets realms address', [BtFlag('realm', BtFlagType.string, description: 'Realm Name')]);
  static const merge = BtCommand('merge', 'merge worlds', [
    BtFlag('bounds', BtFlagType.boolean, description: 'Show Bounds'),
    BtFlag('out', BtFlagType.string, description: 'Out Path'),
  ], positional: true);
  static const render = BtCommand('render', 'render a world to png', [
    BtFlag('world', BtFlagType.string, description: 'World Path'),
    BtFlag('out', BtFlagType.string, defaultValue: 'world.png', description: 'Output filename'),
  ]);
  static const packs = BtCommand('packs', 'download resource packs from a server', [
    BtFlag('address', BtFlagType.address, description: 'remote server address'),
    BtFlag('capture', BtFlagType.boolean, defaultValue: 'true', description: 'Capture pcap2 file'),
    BtFlag('client-cache', BtFlagType.boolean, defaultValue: 'true', description: 'Enable Client Cache'),
    BtFlag('debug', BtFlagType.boolean, description: 'debug mode'),
    BtFlag('extra-debug', BtFlagType.boolean, description: 'extra debug info (packet.log)'),
    BtFlag('save-encrypted', BtFlagType.boolean, description: 'Save Encrypted'),
    BtFlag('folders', BtFlagType.boolean, description: 'Write Folders'),
  ]);
  static const debugProxy = BtCommand('debug-proxy', 'verbose debug packets', _proxy);

  /// `packs` is plain source (subcommands/resourcepack-d.go); only the optional key-dumping package
  /// subcommands/resourcepack-d/ is git-crypt encrypted and excluded (needs `-tags packs`).
  static const all = [worlds, skins, capture, chatLog, realmsList, realmAddress, merge, render, packs, debugProxy];

  static BtCommand? byName(String n) => all.where((c) => c.name == n).firstOrNull;
}

// ---------------------------------------------------------------- events

sealed class BtEvent {
  const BtEvent();
}

/// A console line, ANSI stripped. [level] is the logrus level (INFO/WARN/ERRO/DEBU/FATA/PANI) or null.
class BtLine extends BtEvent {
  final String text;
  final String? level;
  final bool stderr;
  const BtLine(this.text, {this.level, this.stderr = false});
  bool get isError => level == 'ERRO' || level == 'FATA' || level == 'PANI';
  bool get isWarning => level == 'WARN';
}

/// Xbox Live device-code login requested: open [url] (and enter [code] if the page asks).
class BtLogin extends BtEvent {
  final String url;
  final String code;
  const BtLogin(this.url, this.code);
}

class BtLoginDone extends BtEvent {
  final bool success;
  final String? error;
  const BtLoginDone(this.success, [this.error]);
}

/// The proxy is listening; the user should connect Minecraft to this address.
class BtListening extends BtEvent {
  final String address;
  const BtListening(this.address);
}

class BtRealm extends BtEvent {
  final String name;
  final String id;
  const BtRealm(this.name, this.id);
}

class BtExit extends BtEvent {
  final int code;
  final bool cancelled;
  const BtExit(this.code, {this.cancelled = false});
}

// ---------------------------------------------------------------- parsing

abstract class BtParse {
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');
  static final _level = RegExp(r'^(INFO|WARN|ERRO|DEBU|TRAC|FATA|PANI)\[\d+\]\s*(.*)$');
  static final _auth = RegExp(r'Authenticate at (\S+)');
  static final _otc = RegExp(r'[?&]otc=([A-Za-z0-9-]+)');
  static final _msLink = RegExp(r'(https?://(?:www\.)?microsoft\.com/link\S*|https?://aka\.ms/\S+|https?://login\.live\.com/\S+)[^A-Za-z0-9]+.*?code\s+([A-Z0-9]{6,12})', caseSensitive: false);
  static final _listening = RegExp(r'Listening on (\S+)');
  static final _realm = RegExp(r'Name:\s*(.*?)\s+id:\s*(\S+)');

  static String stripAnsi(String s) => s.replaceAll(_ansi, '').replaceAll('\r', '');

  /// Splits a logrus text line into level and message (trailing `part=…` fields kept).
  static (String?, String) level(String line) {
    final m = _level.firstMatch(line.trim());
    if (m == null) return (null, line);
    return (m.group(1), m.group(2)!.replaceAll(RegExp(r'\s{2,}'), '  ').trim());
  }

  /// Structured events found in one (ANSI-stripped) output line, besides the line itself.
  static List<BtEvent> events(String line) {
    final out = <BtEvent>[];
    final a = _auth.firstMatch(line);
    if (a != null) {
      final url = a.group(1)!;
      out.add(BtLogin(url, _otc.firstMatch(url)?.group(1) ?? ''));
    } else {
      final m = _msLink.firstMatch(line);
      if (m != null) out.add(BtLogin(m.group(1)!, m.group(2)!));
    }
    if (line.contains('Authentication successful')) out.add(const BtLoginDone(true));
    final f = RegExp(r'Failed to Authenticate: (.*)').firstMatch(line);
    if (f != null) out.add(BtLoginDone(false, f.group(1)));
    final l = _listening.firstMatch(line);
    if (l != null) out.add(BtListening(l.group(1)!));
    final r = _realm.firstMatch(line);
    if (r != null) out.add(BtRealm(r.group(1)!, r.group(2)!));
    return out;
  }

  /// Parses `Available Commands:` output of `bedrocktool help` into name → description.
  static Map<String, String> commandList(String text) {
    final out = <String, String>{};
    var inList = false;
    for (final raw in const LineSplitter().convert(stripAnsi(text))) {
      if (raw.contains('Available Commands')) {
        inList = true;
        continue;
      }
      if (!inList || !raw.startsWith('\t')) continue;
      final parts = raw.trim().split('\t');
      final name = parts.first.trim();
      if (name.isEmpty || name.contains(' ')) continue;
      out[name] = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    }
    return out;
  }

  /// Parses Go `flag.PrintDefaults` output (`bedrocktool <cmd> -h=true`).
  static List<BtFlag> flagHelp(String text) {
    final out = <BtFlag>[];
    final lines = const LineSplitter().convert(stripAnsi(text));
    final head = RegExp(r'^  -(\S+)(?:\s+(\S+))?\s*$');
    for (var i = 0; i < lines.length; i++) {
      final m = head.firstMatch(lines[i]);
      if (m == null) continue;
      final name = m.group(1)!;
      final kind = m.group(2);
      var desc = '';
      if (i + 1 < lines.length && lines[i + 1].startsWith('    \t')) desc = lines[++i].trim();
      var def = '';
      final d = RegExp(r'\s*\(default (.*)\)$').firstMatch(desc);
      if (d != null) {
        def = d.group(1)!;
        desc = desc.substring(0, d.start).trim();
        if (def.startsWith('<')) def = ''; // `<int Value>` placeholders of custom flag.Value types
      }
      final type = switch (kind) {
        null => BtFlagType.boolean,
        'string' when name == 'address' => BtFlagType.address,
        _ when desc.contains('comma') => BtFlagType.list,
        _ when RegExp(r'^\d+$').hasMatch(def) || name.contains('radius') => BtFlagType.integer,
        _ => BtFlagType.string,
      };
      out.add(BtFlag(name, type, defaultValue: kind == null && def.isEmpty ? 'false' : def, description: desc));
    }
    return out;
  }

  /// Builds `-flag=value` arguments. Bools are always explicit; empty strings/lists are omitted.
  static List<String> buildArgs(String command, Map<String, Object?> values, {List<String> positional = const []}) {
    final args = <String>[command];
    values.forEach((k, v) {
      if (v == null) return;
      if (v is bool) {
        args.add('-$k=$v');
      } else if (v is List) {
        final s = v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).join(',');
        if (s.isNotEmpty) args.add('-$k=$s');
      } else {
        final s = '$v'.trim();
        if (s.isNotEmpty) args.add('-$k=$s');
      }
    });
    return [...args, ...positional];
  }
}

// ---------------------------------------------------------------- running

/// A running BedrockTool subcommand.
class BtRun {
  final Process process;
  final List<String> args;
  final _events = StreamController<BtEvent>.broadcast();
  final _exit = Completer<int>();
  bool _cancelled = false;

  BtRun._(this.process, this.args) {
    void pipe(Stream<List<int>> s, bool err) {
      s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((raw) {
        final line = BtParse.stripAnsi(raw);
        if (line.trim().isEmpty) return;
        final (lvl, msg) = BtParse.level(line);
        _events.add(BtLine(lvl == null ? line : msg, level: lvl, stderr: err));
        for (final e in BtParse.events(line)) {
          _events.add(e);
        }
      });
    }

    pipe(process.stdout, false);
    pipe(process.stderr, true);
    process.exitCode.then((c) async {
      await Future<void>.delayed(const Duration(milliseconds: 100)); // let the last lines flush
      _events.add(BtExit(c, cancelled: _cancelled));
      await _events.close();
      _exit.complete(c);
    });
  }

  Stream<BtEvent> get events => _events.stream;
  Future<int> get exitCode => _exit.future;
  bool get cancelled => _cancelled;

  /// Answers an interactive prompt (rarely needed: CML always passes the address).
  void send(String line) => process.stdin.writeln(line);

  /// Kills the process tree (bedrocktool has no child processes today, but be safe).
  Future<void> cancel() async {
    _cancelled = true;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    }
    process.kill(ProcessSignal.sigkill);
  }
}

/// A file produced by BedrockTool in its data folder.
class BtOutput {
  final String path;
  final String kind; // world | skin | capture | chat | image | pack | log | other
  final bool isDirectory;
  final DateTime modified;
  final int size;
  const BtOutput(this.path, this.kind, this.isDirectory, this.modified, this.size);
  String get name => p.basename(path);
}

/// Wrapper around the bundled `bedrocktool.exe` CLI.
///
/// The tool's data folder (= its working directory on Windows) is `%APPDATA%\CML\bedrocktool`:
/// token.json / chain.bin (Xbox login), bedrocktool.log, worlds\, skins\, captures\, packs\, *.png, *_chat.log.
class BedrockTool {
  final String exe;
  final String workDir;
  BedrockTool({String? exe, String? workDir})
      : exe = exe ?? Bundled.bedrocktool,
        workDir = workDir ?? p.join(Os.cmlHome, 'bedrocktool');

  bool get available => File(exe).existsSync();
  bool get loggedIn => File(p.join(workDir, 'token.json')).existsSync();

  Future<BtRun> start(String command, {Map<String, Object?> flags = const {}, List<String> positional = const []}) async {
    if (!available) throw CmlException('tool_missing', '找不到 ${p.basename(exe)}，请重新安装 CML');
    await Directory(workDir).create(recursive: true);
    final args = BtParse.buildArgs(command, flags, positional: positional);
    final proc = await Process.start(exe, args, workingDirectory: workDir, environment: {'NO_COLOR': '1'});
    return BtRun._(proc, args);
  }

  /// Runs to completion and returns the combined, ANSI-stripped output.
  Future<(int, String)> runText(List<String> args, {Duration timeout = const Duration(seconds: 30)}) async {
    if (!available) throw CmlException('tool_missing', '找不到 ${p.basename(exe)}，请重新安装 CML');
    await Directory(workDir).create(recursive: true);
    final r = await Process.run(exe, args, workingDirectory: workDir, stdoutEncoding: utf8, stderrEncoding: utf8).timeout(timeout);
    return (r.exitCode, BtParse.stripAnsi('${r.stdout}\n${r.stderr}'));
  }

  Future<Map<String, String>> commandList() async => BtParse.commandList((await runText(['help'])).$2);

  /// Flags of [command] read from the exe; falls back to the built-in table.
  Future<BtCommand> describe(String command) async {
    final known = BtCommands.byName(command);
    try {
      final flags = BtParse.flagHelp((await runText([command, '-h=true'])).$2);
      if (flags.isNotEmpty) return BtCommand(command, known?.description ?? '', flags, positional: known?.positional ?? false);
    } catch (_) {}
    if (known == null) throw CmlException('bt_unknown', '未知的 BedrockTool 命令 $command');
    return known;
  }

  /// Realms the logged-in account can access. Requires login (may emit [BtLogin] on [onEvent]).
  Future<List<BtRealm>> realms({void Function(BtEvent e)? onEvent}) async {
    final run = await start('list-realms');
    final out = <BtRealm>[];
    await for (final e in run.events) {
      if (e is BtRealm) out.add(e);
      onEvent?.call(e);
    }
    return out;
  }

  /// Removes the saved Xbox login.
  Future<void> logout() async {
    for (final f in ['token.json', 'chain.bin', 'chain.json']) {
      final file = File(p.join(workDir, f));
      if (await file.exists()) await file.delete();
    }
  }

  /// Lists what the tool produced, newest first.
  Future<List<BtOutput>> outputs() async {
    final dir = Directory(workDir);
    if (!await dir.exists()) return [];
    final out = <BtOutput>[];
    Future<void> add(FileSystemEntity e, String kind) async {
      final st = await e.stat();
      out.add(BtOutput(e.path, kind, st.type == FileSystemEntityType.directory, st.modified, st.size));
    }

    const folders = {'worlds': 'world', 'skins': 'skin', 'captures': 'capture', 'packs': 'pack'};
    await for (final e in dir.list()) {
      final name = p.basename(e.path);
      if (e is Directory) {
        final kind = folders[name];
        if (kind == null) continue; // blobcache, packcache …
        await for (final sub in e.list()) {
          if (kind == 'world' && sub is Directory) {
            // worlds\<server>\<world>
            await for (final w in sub.list()) {
              if (w is Directory) await add(w, kind);
            }
          } else {
            await add(sub, kind);
          }
        }
      } else if (e is File) {
        final lower = name.toLowerCase();
        if (lower.startsWith('token') || lower.startsWith('chain') || lower.endsWith('.tmp') || lower == 'history.json') continue;
        final kind = lower.endsWith('.png')
            ? 'image'
            : lower.endsWith('_chat.log')
                ? 'chat'
                : lower.endsWith('.pcap2')
                    ? 'capture'
                    : lower.endsWith('.log')
                        ? 'log'
                        : 'other';
        await add(e, kind);
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  // ---------------- server address history

  String get _historyFile => p.join(workDir, 'history.json');

  Future<List<String>> history() async {
    final j = await JsonFile.read(_historyFile);
    return j is Map && j['servers'] is List ? [for (final s in j['servers'] as List) '$s'] : [];
  }

  Future<void> remember(String address) async {
    final a = address.trim();
    if (a.isEmpty) return;
    final h = (await history())..remove(a);
    h.insert(0, a);
    await JsonFile.write(_historyFile, {'servers': h.take(15).toList()});
  }
}
