import 'lan_io.dart' if (dart.library.js_interop) 'lan_web.dart' as impl;

/// A server found on the local network.
class LanServer {
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  const LanServer(this.name, this.host, this.port, this.fingerprint);
  String get address => '$host:$port';
}

/// Broadcasts to UDP [kDiscoveryPort] and collects replies for [wait]. Never
/// throws; always empty in the browser (no UDP there).
Future<List<LanServer>> discoverLanServers({Duration wait = const Duration(seconds: 2)}) =>
    impl.discoverLanServers(wait: wait);
