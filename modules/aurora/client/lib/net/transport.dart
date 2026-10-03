import 'dart:async';
import 'dart:typed_data';

import 'package:aurora_shared/aurora_shared.dart';

import 'transport_io.dart' if (dart.library.js_interop) 'transport_web.dart' as impl;

/// Connection failure with a user-facing message (dart:io's SocketException
/// does not exist on the web).
class ConnectException implements Exception {
  final String message;
  const ConnectException(this.message);
  @override
  String toString() => message;
}

/// A byte pipe to the server: raw TCP on native platforms, a binary WebSocket
/// (`ws(s)://host:port/ws`, served by the Aurora server's web port) in the
/// browser. Both carry the same length-prefixed encrypted frames.
abstract class Link {
  Stream<Uint8List> get data;
  void add(List<int> bytes);
  Future<void> close();
  void destroy();
}

/// True when running in a browser (TCP sockets are unavailable).
const bool kIsWebTransport = impl.isWeb;

/// Opens a [Link]. [address] is "host:port" (native) or, in the browser, an
/// http(s)/ws(s) URL or "host:port" of the server's web port; empty = the
/// server that served this page.
Future<Link> openLink(String address, {Duration timeout = const Duration(seconds: 8)}) =>
    impl.openLink(address, timeout);

/// Default server address for the browser (the page's own origin), '' on native.
String defaultWebAddress() => impl.defaultWebAddress();

/// Parse "host:port", "host" or "[v6]:port".
(String, int) parseHostPort(String input) {
  var s = input.trim();
  if (s.contains('://')) s = s.substring(s.indexOf('://') + 3);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end > 0) {
      final host = s.substring(1, end);
      final rest = s.substring(end + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
      return (host, port ?? kDefaultPort);
    }
  }
  final i = s.lastIndexOf(':');
  if (i > 0 && s.indexOf(':') == i) {
    return (s.substring(0, i), int.tryParse(s.substring(i + 1)) ?? kDefaultPort);
  }
  return (s, kDefaultPort);
}
