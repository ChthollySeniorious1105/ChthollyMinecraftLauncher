import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../common/os.dart';
import 'microsoft.dart';

/// Persists accounts in `%APPDATA%\CML\accounts.dat`, encrypted with Windows DPAPI
/// (CryptProtectData, current-user scope) so tokens are unreadable to other users / machines.
class AccountStore {
  final String path;
  AccountStore([String? path]) : path = path ?? p.join(Os.cmlHome, 'accounts.dat');

  List<MsAccount> accounts = [];
  String? selectedUuid;

  MsAccount? get selected => accounts.where((a) => a.uuid == selectedUuid).firstOrNull ?? accounts.firstOrNull;

  Future<void> load() async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(utf8.decode(Dpapi.unprotect(await f.readAsBytes()))) as Map;
      accounts = [for (final a in j['accounts'] as List) MsAccount.fromJson(a as Map)];
      selectedUuid = j['selected'] as String?;
    } catch (_) {
      // unreadable (other user/machine): start empty rather than crash
      accounts = [];
    }
  }

  Future<void> save() async {
    final data = utf8.encode(jsonEncode({'accounts': [for (final a in accounts) a.toJson()], 'selected': selectedUuid}));
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Dpapi.protect(data), flush: true);
  }

  void upsert(MsAccount a) {
    accounts.removeWhere((x) => x.uuid == a.uuid);
    accounts.add(a);
    selectedUuid = a.uuid;
  }

  void remove(String uuid) {
    accounts.removeWhere((x) => x.uuid == uuid);
    if (selectedUuid == uuid) selectedUuid = accounts.firstOrNull?.uuid;
  }
}

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

/// Minimal DPAPI binding. On non-Windows (tests) data is stored as-is.
abstract class Dpapi {
  static final _crypt32 = Platform.isWindows ? DynamicLibrary.open('crypt32.dll') : null;
  static final _kernel32 = Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  static final _protect = _crypt32?.lookupFunction<
      Int32 Function(Pointer<_Blob>, Pointer<Utf16>, Pointer<_Blob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_Blob>),
      int Function(Pointer<_Blob>, Pointer<Utf16>, Pointer<_Blob>, Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>)>('CryptProtectData');
  static final _unprotect = _crypt32?.lookupFunction<
      Int32 Function(Pointer<_Blob>, Pointer<Pointer<Utf16>>, Pointer<_Blob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_Blob>),
      int Function(Pointer<_Blob>, Pointer<Pointer<Utf16>>, Pointer<_Blob>, Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>)>('CryptUnprotectData');
  static final _localFree = _kernel32?.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');

  static const _uiForbidden = 0x1;
  static final _magic = utf8.encode('CMLD');

  static Uint8List protect(List<int> data) {
    if (_protect == null) return Uint8List.fromList(data);
    return _run(data, (inp, out) => _protect!(inp, nullptr, nullptr, nullptr, nullptr, _uiForbidden, out), prefix: _magic);
  }

  static Uint8List unprotect(Uint8List data) {
    if (_unprotect == null) return data;
    if (data.length < 4 || !_startsWith(data, _magic)) throw const FormatException('not a CML DPAPI blob');
    return _run(Uint8List.sublistView(data, 4), (inp, out) => _unprotect!(inp, nullptr, nullptr, nullptr, nullptr, _uiForbidden, out));
  }

  static bool _startsWith(Uint8List d, List<int> m) {
    for (var i = 0; i < m.length; i++) {
      if (d[i] != m[i]) return false;
    }
    return true;
  }

  static Uint8List _run(List<int> data, int Function(Pointer<_Blob>, Pointer<_Blob>) f, {List<int> prefix = const []}) {
    final inp = calloc<_Blob>();
    final out = calloc<_Blob>();
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      inp.ref
        ..cbData = data.length
        ..pbData = buf;
      if (f(inp, out) == 0) throw const OSError('DPAPI failed');
      final r = Uint8List(prefix.length + out.ref.cbData)
        ..setAll(0, prefix)
        ..setAll(prefix.length, out.ref.pbData.asTypedList(out.ref.cbData));
      _localFree!(out.ref.pbData.cast());
      return r;
    } finally {
      calloc.free(buf);
      calloc.free(inp);
      calloc.free(out);
    }
  }
}
