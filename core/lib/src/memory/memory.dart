import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

class MemoryInfo {
  final int totalMb;
  final int availableMb;
  final int loadPercent;
  MemoryInfo(this.totalMb, this.availableMb, this.loadPercent);
  int get usedMb => totalMb - availableMb;
}

class OptimizeResult {
  final int processesTrimmed;
  final int freedMb;
  final bool standbyCleared;
  OptimizeResult(this.processesTrimmed, this.freedMb, this.standbyCleared);
}

/// Memory status, automatic allocation and "内存优化".
abstract class Memory {
  static final _k32 = Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;
  static final _psapi = Platform.isWindows ? DynamicLibrary.open('psapi.dll') : null;
  static final _ntdll = Platform.isWindows ? DynamicLibrary.open('ntdll.dll') : null;
  static final _advapi = Platform.isWindows ? DynamicLibrary.open('advapi32.dll') : null;

  static MemoryInfo info() {
    if (_k32 == null) return MemoryInfo(8192, 4096, 50);
    final f = _k32!.lookupFunction<Int32 Function(Pointer<_MemoryStatusEx>), int Function(Pointer<_MemoryStatusEx>)>('GlobalMemoryStatusEx');
    final s = calloc<_MemoryStatusEx>();
    try {
      s.ref.dwLength = sizeOf<_MemoryStatusEx>();
      f(s);
      return MemoryInfo(s.ref.ullTotalPhys ~/ (1 << 20), s.ref.ullAvailPhys ~/ (1 << 20), s.ref.dwMemoryLoad);
    } finally {
      calloc.free(s);
    }
  }

  /// Automatic allocation ("自动分配内存"), similar to PCL:
  /// base on version era + mod count, capped by free memory and total RAM.
  static int autoAllocateMb({required int modCount, required bool modern, bool is64BitJava = true, MemoryInfo? mem}) {
    final m = mem ?? info();
    if (!is64BitJava) return 1024;
    var want = modern ? 2048 : 1536;
    if (modCount > 0) want = 3072 + modCount * 24; // ~ 4 GB for 40 mods, 6 GB for 120
    if (modCount > 200) want = 8192;
    final cap = (m.totalMb * 0.6).floor();
    final free = m.availableMb - 1024; // leave the OS some headroom
    var mb = want;
    if (mb > cap) mb = cap;
    if (mb > free) mb = free;
    if (mb < 1024) mb = 1024;
    return (mb ~/ 128) * 128;
  }

  /// "内存优化": trims the working sets of the given processes (by default only CML itself and the
  /// game it launched) so unused pages go back to the system. When [purgeStandby] is true and CML
  /// runs as administrator, the system standby list is also purged. Both are opt-in actions; CML
  /// never touches other programs' memory unless their PIDs are passed explicitly.
  static Future<OptimizeResult> optimize({List<int> pids = const [], bool purgeStandby = false}) async {
    if (_k32 == null) return OptimizeResult(0, 0, false);
    final before = info().availableMb;
    final openProcess = _k32!.lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>('OpenProcess');
    final closeHandle = _k32!.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    final emptyWs = _psapi!.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EmptyWorkingSet');

    const processQueryInformation = 0x0400, processSetQuota = 0x0100;
    var trimmed = 0;
    for (final id in {...pids, pid}) {
      final h = openProcess(processQueryInformation | processSetQuota, 0, id);
      if (h == 0) continue;
      if (emptyWs(h) != 0) trimmed++;
      closeHandle(h);
    }

    var standby = false;
    if (purgeStandby) standby = _purgeStandbyList();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final after = info().availableMb;
    return OptimizeResult(trimmed, (after - before).clamp(0, 1 << 30), standby);
  }

  /// NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList). Needs admin.
  static bool _purgeStandbyList() {
    try {
      if (!_enablePrivilege('SeProfileSingleProcessPrivilege')) return false;
      final nt = _ntdll!.lookupFunction<Int32 Function(Int32, Pointer<Void>, Uint32), int Function(int, Pointer<Void>, int)>('NtSetSystemInformation');
      const systemMemoryListInformation = 80, memoryPurgeStandbyList = 4;
      final cmd = calloc<Int32>()..value = memoryPurgeStandbyList;
      try {
        return nt(systemMemoryListInformation, cmd.cast(), 4) == 0;
      } finally {
        calloc.free(cmd);
      }
    } catch (_) {
      return false;
    }
  }

  static bool _enablePrivilege(String name) {
    final getCurrentProcess = _k32!.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    final openToken = _advapi!.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<IntPtr>), int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken');
    final lookup = _advapi!.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint64>), int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint64>)>('LookupPrivilegeValueW');
    final adjust = _advapi!.lookupFunction<Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Void>, Pointer<Void>), int Function(int, int, Pointer<Uint8>, int, Pointer<Void>, Pointer<Void>)>('AdjustTokenPrivileges');
    final getLastError = _k32!.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    final closeHandle = _k32!.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

    const tokenAdjust = 0x20, tokenQuery = 0x8, sePrivilegeEnabled = 2;
    final tok = calloc<IntPtr>();
    final luid = calloc<Uint64>();
    final nameP = name.toNativeUtf16();
    // TOKEN_PRIVILEGES { DWORD count; LUID luid; DWORD attrs; } = 16 bytes
    final tp = calloc<Uint8>(16);
    try {
      if (openToken(getCurrentProcess(), tokenAdjust | tokenQuery, tok) == 0) return false;
      if (lookup(nullptr, nameP, luid) == 0) return false;
      tp.cast<Uint32>().value = 1;
      (tp + 4).cast<Uint64>().value = luid.value;
      (tp + 12).cast<Uint32>().value = sePrivilegeEnabled;
      final ok = adjust(tok.value, 0, tp, 16, nullptr, nullptr) != 0 && getLastError() == 0;
      closeHandle(tok.value);
      return ok;
    } finally {
      calloc.free(tok);
      calloc.free(luid);
      calloc.free(nameP);
      calloc.free(tp);
    }
  }
}
