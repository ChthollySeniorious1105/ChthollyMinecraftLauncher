import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'transport.dart';

const bool isWeb = true;

/// The server that served this page (its web port also accepts `/ws`).
String defaultWebAddress() {
  final loc = web.window.location;
  return loc.host.isEmpty ? '' : '${loc.protocol}//${loc.host}';
}

/// Turns user input into a WebSocket URL: full ws(s)/http(s) URLs are kept,
/// bare "host[:port]" gets the page's scheme; the path defaults to `/ws`.
String webSocketUrl(String address) {
  var a = address.trim();
  if (a.isEmpty) a = defaultWebAddress();
  final secure = web.window.location.protocol == 'https:';
  if (a.startsWith('http://')) a = 'ws://${a.substring(7)}';
  if (a.startsWith('https://')) a = 'wss://${a.substring(8)}';
  if (!a.startsWith('ws://') && !a.startsWith('wss://')) {
    if (a.contains('://')) a = a.substring(a.indexOf('://') + 3);
    a = '${secure ? 'wss' : 'ws'}://$a';
  }
  final u = Uri.parse(a);
  return u.replace(path: u.path.isEmpty || u.path == '/' ? '/ws' : u.path).toString();
}

class _WsLink implements Link {
  final web.WebSocket ws;
  final _data = StreamController<Uint8List>();
  _WsLink(this.ws);

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  void add(List<int> bytes) {
    if (ws.readyState != web.WebSocket.OPEN) return;
    final u = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    ws.send(u.toJS);
  }

  void _done([Object? error]) {
    if (_data.isClosed) return;
    if (error != null) _data.addError(error);
    _data.close();
  }

  @override
  Future<void> close() async {
    try {
      ws.close();
    } catch (_) {}
    _done();
  }

  @override
  void destroy() {
    try {
      ws.close();
    } catch (_) {}
    _done();
  }
}

Future<Link> openLink(String address, Duration timeout) async {
  final String url;
  try {
    url = webSocketUrl(address);
  } catch (_) {
    throw const ConnectException('地址格式错误');
  }
  if (web.window.location.protocol == 'https:' && url.startsWith('ws://')) {
    throw const ConnectException('HTTPS 页面只能连接 wss:// 地址');
  }
  final web.WebSocket ws;
  try {
    ws = web.WebSocket(url);
  } catch (_) {
    throw const ConnectException('地址格式错误');
  }
  ws.binaryType = 'arraybuffer';
  final link = _WsLink(ws);
  final opened = Completer<void>();
  ws.onopen = ((web.Event _) {
    if (!opened.isCompleted) opened.complete();
  }).toJS;
  ws.onmessage = ((web.MessageEvent e) {
    final d = e.data;
    if (d.isA<JSArrayBuffer>()) {
      link._data.add((d as JSArrayBuffer).toDart.asUint8List());
    }
  }).toJS;
  ws.onerror = ((web.Event _) {
    if (!opened.isCompleted) {
      opened.completeError(const ConnectException('无法建立 WebSocket 连接（服务器未开启网页版或地址/端口错误）'));
    }
  }).toJS;
  ws.onclose = ((web.CloseEvent _) {
    if (!opened.isCompleted) {
      opened.completeError(const ConnectException('无法建立 WebSocket 连接（服务器未开启网页版或地址/端口错误）'));
    }
    link._done();
  }).toJS;
  try {
    await opened.future.timeout(timeout);
  } on TimeoutException {
    link.destroy();
    throw const ConnectException('连接超时');
  }
  return link;
}
