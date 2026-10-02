import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../common/errors.dart';

/// Thin HttpClient wrapper shared by every module.
///
/// `verifySsl: false` accepts invalid certificates. It is only used by the account
/// login flow (the "正版登录时验证 SSL 证书" setting); everything else always verifies.
class Http {
  static const userAgent = 'ChthollyMinecraftLauncher/0.1';

  final HttpClient _client;
  final HttpClient _insecure;
  Duration timeout;

  Http({this.timeout = const Duration(seconds: 30), String? proxy})
      : _client = _make(false, proxy),
        _insecure = _make(true, proxy);

  static HttpClient _make(bool insecure, String? proxy) {
    final c = HttpClient()
      ..userAgent = userAgent
      ..connectionTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 16
      ..autoUncompress = true;
    if (insecure) c.badCertificateCallback = (_, _, _) => true;
    if (proxy != null && proxy.isNotEmpty) c.findProxy = (_) => 'PROXY $proxy';
    return c;
  }

  /// Route traffic through an HTTP proxy (e.g. built-in mihomo `127.0.0.1:7890`), or system/env when null.
  void setProxy(String? proxy) {
    for (final c in [_client, _insecure]) {
      c.findProxy = (proxy == null || proxy.isEmpty) ? HttpClient.findProxyFromEnvironment : (_) => 'PROXY $proxy';
    }
  }

  Future<HttpClientResponse> send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    List<int>? body,
    bool verifySsl = true,
    CancelToken? cancel,
    int maxRedirects = 8,
  }) async {
    cancel?.throwIfCancelled();
    final c = verifySsl ? _client : _insecure;
    var uri = url;
    for (var hop = 0;; hop++) {
      final req = await c.openUrl(method, uri).timeout(timeout);
      req.followRedirects = false;
      headers?.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      if (res.isRedirect && hop < maxRedirects) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null) throw CmlException('http', '服务器重定向缺少地址：$uri');
        uri = uri.resolve(loc);
        if (res.statusCode == 303) {
          method = 'GET';
          body = null;
        }
        continue;
      }
      return res;
    }
  }

  Future<Uint8List> bytes(Uri url, {Map<String, String>? headers, bool verifySsl = true, CancelToken? cancel}) async {
    final res = await send('GET', url, headers: headers, verifySsl: verifySsl, cancel: cancel);
    final data = await readAll(res, cancel);
    if (res.statusCode >= 400) throw HttpStatusException(url, res.statusCode, utf8.decode(data, allowMalformed: true), null);
    return data;
  }

  Future<String> text(Uri url, {Map<String, String>? headers, bool verifySsl = true}) async =>
      utf8.decode(await bytes(url, headers: headers, verifySsl: verifySsl), allowMalformed: true);

  Future<dynamic> getJson(Uri url, {Map<String, String>? headers, bool verifySsl = true}) async {
    final t = await text(url, headers: {'Accept': 'application/json', ...?headers}, verifySsl: verifySsl);
    try {
      return jsonDecode(t);
    } on FormatException catch (e) {
      throw CmlException('json', '服务器返回了无效数据：${url.host}${url.path}', e);
    }
  }

  Future<dynamic> postJson(Uri url, Object? body, {Map<String, String>? headers, bool verifySsl = true, String method = 'POST'}) =>
      _post(method, url, utf8.encode(jsonEncode(body)), 'application/json', headers, verifySsl);

  Future<dynamic> postForm(Uri url, Map<String, String> form, {Map<String, String>? headers, bool verifySsl = true}) {
    final body = form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return _post('POST', url, utf8.encode(body), 'application/x-www-form-urlencoded', headers, verifySsl);
  }

  /// Sends a raw body (e.g. multipart) and decodes a JSON reply.
  Future<dynamic> request(String method, Uri url, {List<int>? body, String? contentType, Map<String, String>? headers, bool verifySsl = true}) =>
      _post(method, url, body ?? const [], contentType, headers, verifySsl);

  Future<dynamic> _post(String method, Uri url, List<int> body, String? type, Map<String, String>? headers, bool verifySsl) async {
    final res = await send(method, url,
        headers: {'Content-Type': ?type, 'Accept': 'application/json', ...?headers}, body: body, verifySsl: verifySsl);
    final data = await readAll(res, null);
    final t = utf8.decode(data, allowMalformed: true);
    dynamic json;
    try {
      json = t.isEmpty ? null : jsonDecode(t);
    } on FormatException {
      json = null;
    }
    if (res.statusCode >= 400) throw HttpStatusException(url, res.statusCode, t, json);
    return json;
  }

  static Future<Uint8List> readAll(HttpClientResponse res, CancelToken? cancel) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      cancel?.throwIfCancelled();
      b.add(chunk);
    }
    return b.takeBytes();
  }

  void close() {
    _client.close(force: true);
    _insecure.close(force: true);
  }
}

class HttpStatusException extends CmlException {
  final int status;
  final String body;
  final dynamic json;
  HttpStatusException(Uri url, this.status, this.body, this.json) : super('http_$status', '请求失败（HTTP $status）：${url.host}${url.path}');
}
