import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_shared/aurora_shared.dart';

/// A server found on the local network.
class LanServer {
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  const LanServer(this.name, this.host, this.port, this.fingerprint);
  String get address => '$host:$port';
}

/// Broadcasts [kDiscoveryHello] to UDP [kDiscoveryPort] and collects replies
/// for [wait]. Never throws: returns an empty list when broadcast is not
/// possible on this platform / network.
Future<List<LanServer>> discoverLanServers({Duration wait = const Duration(seconds: 2)}) async {
  final found = <String, LanServer>{};
  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    final s = sock;
    final sub = s.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = s.receive()) != null) {
        try {
          final j = jsonDecode(utf8.decode(d!.data));
          if (j is! Map) continue;
          final port = asInt(j['port'], kDefaultPort);
          final host = d.address.address;
          final srv = LanServer(asStr(j['name'], '服务器'), host, port, asStr(j['fp']));
          found[srv.address] = srv;
        } catch (_) {}
      }
    }, onError: (_) {});
    final hello = utf8.encode(kDiscoveryHello);
    void blast() {
      for (final target in ['255.255.255.255', ..._subnetBroadcasts]) {
        try {
          s.send(hello, InternetAddress(target), kDiscoveryPort);
        } catch (_) {}
      }
    }

    await _loadSubnets();
    blast();
    await Future.delayed(wait ~/ 3);
    blast(); // UDP is lossy: send twice
    await Future.delayed(wait - wait ~/ 3);
    await sub.cancel();
  } catch (_) {
    // broadcast not permitted / no network
  } finally {
    try {
      sock?.close();
    } catch (_) {}
  }
  final list = found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}

final List<String> _subnetBroadcasts = [];

/// Directed /24 broadcasts for each IPv4 interface (some routers drop
/// 255.255.255.255).
Future<void> _loadSubnets() async {
  _subnetBroadcasts.clear();
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifs) {
      for (final a in i.addresses) {
        final p = a.address.split('.');
        if (p.length == 4) _subnetBroadcasts.add('${p[0]}.${p[1]}.${p[2]}.255');
      }
    }
  } catch (_) {}
}
