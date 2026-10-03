import 'lan.dart';

/// Browsers cannot send UDP broadcasts.
Future<List<LanServer>> discoverLanServers({Duration wait = const Duration(seconds: 2)}) async => const [];
