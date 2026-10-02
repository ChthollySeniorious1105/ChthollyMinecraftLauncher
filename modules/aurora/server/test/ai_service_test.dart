import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

/// Fake Anthropic + OpenAI endpoints on a local HttpServer.
class FakeApi {
  late HttpServer http;
  final requests = <({String path, Map<String, String> headers, Map<String, dynamic> body})>[];

  /// Returns (status, json body) for a request; may delay.
  Future<(int, Object)> Function(String path, Map<String, dynamic> body, Map<String, String> headers) reply =
      (p, b, h) async => (200, {});

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((rq) async {
      final text = await utf8.decoder.bind(rq).join();
      final headers = <String, String>{};
      rq.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      final body = jsonDecode(text) as Map<String, dynamic>;
      requests.add((path: rq.uri.path, headers: headers, body: body));
      final (code, out) = await reply(rq.uri.path, body, headers);
      try {
        rq.response
          ..statusCode = code
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(out));
        await rq.response.close();
      } catch (_) {}
    });
  }

  String get base => 'http://127.0.0.1:${http.port}';
  Future<void> stop() => http.close(force: true);
}

void main() {
  late FakeApi api;
  setUp(() async {
    api = FakeApi();
    await api.start();
  });
  tearDown(() => api.stop());

  final img = AiImage('image/png', Uint8List.fromList([1, 2, 3, 4]));

  HttpAiService anthropic({String model = 'claude-opus-5', Duration timeout = const Duration(seconds: 5), int limit = 100}) =>
      HttpAiService(
          provider: 'anthropic', apiKey: 'sk-secret-key', model: model, baseUrl: api.base, timeout: timeout, dailyLimit: limit);

  test('anthropic request shape, headers, image blocks, text join', () async {
    api.reply = (p, b, h) async => (
          200,
          {
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': '你'},
              {'type': 'text', 'text': '好'},
            ]
          }
        );
    final ai = anthropic();
    expect(ai.available, isTrue);
    expect(ai.label, 'anthropic · claude-opus-5');
    final r = await ai.complete(AiRequest(system: 'sys', prompt: 'hi', images: [img], maxTokens: 300));
    expect(r, '你好');
    final q = api.requests.single;
    expect(q.path, '/v1/messages');
    expect(q.headers['x-api-key'], 'sk-secret-key');
    expect(q.headers['anthropic-version'], '2023-06-01');
    expect(q.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(q.headers['content-type'], contains('application/json'));
    final b = q.body;
    expect(b['model'], 'claude-opus-5');
    expect(b['max_tokens'], 1024);
    expect(b['system'], 'sys');
    expect(b['output_config'], {'effort': 'low'});
    expect(b['fallbacks'], 'default');
    for (final k in ['temperature', 'top_p', 'top_k', 'thinking']) {
      expect(b.containsKey(k), isFalse, reason: k);
    }
    final content = (b['messages'] as List).single['content'] as List;
    expect(content[0], {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/png', 'data': base64.encode([1, 2, 3, 4])}
    });
    expect(content[1], {'type': 'text', 'text': 'hi'});
  });

  test('non-fallback models get no beta header', () async {
    api.reply = (p, b, h) async => (200, {'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'ok'}]});
    final ai = anthropic(model: 'claude-sonnet-5');
    expect(await ai.complete(const AiRequest(system: '', prompt: 'x', maxTokens: 2000)), 'ok');
    final q = api.requests.single;
    expect(q.headers.containsKey('anthropic-beta'), isFalse);
    expect(q.body.containsKey('fallbacks'), isFalse);
    expect(q.body.containsKey('system'), isFalse);
    expect(q.body['max_tokens'], 2000);
  });

  test('refusal returns null', () async {
    api.reply = (p, b, h) async => (200, {'stop_reason': 'refusal', 'content': [{'type': 'text', 'text': 'partial'}]});
    final ai = anthropic();
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), isNull);
    expect(ai.lastError, contains('refusal'));
  });

  test('400 about fallbacks retries once without them and remembers', () async {
    api.reply = (p, b, h) async => b.containsKey('fallbacks')
        ? (400, {'type': 'error', 'error': {'type': 'invalid_request_error', 'message': 'fallbacks: unknown beta'}})
        : (200, {'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'ok'}]});
    final ai = anthropic();
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), 'ok');
    expect(api.requests.length, 2);
    expect(api.requests[1].headers.containsKey('anthropic-beta'), isFalse);
    expect(api.requests[1].body.containsKey('fallbacks'), isFalse);
    expect(ai.useFallbacks, isFalse);
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), 'ok');
    expect(api.requests.length, 3, reason: 'no second probe with fallbacks');
  });

  test('other HTTP errors return null without leaking the key', () async {
    api.reply = (p, b, h) async => (500, {'error': 'boom sk-secret-key'});
    final ai = anthropic();
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), isNull);
    expect(ai.lastError, contains('500'));
    expect(ai.lastError, isNot(contains('sk-secret-key')));
    expect(ai.status(), isNot(contains('sk-secret-key')));
    expect(api.requests.length, 1);
  });

  test('timeout returns null', () async {
    api.reply = (p, b, h) async {
      await Future.delayed(const Duration(seconds: 3));
      return (200, {'stop_reason': 'end_turn', 'content': []});
    };
    final ai = anthropic(timeout: const Duration(milliseconds: 500));
    final sw = Stopwatch()..start();
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), isNull);
    expect(sw.elapsedMilliseconds, lessThan(2500));
    expect(ai.lastError, contains('超时'));
  });

  test('daily cap makes the service unavailable', () async {
    api.reply = (p, b, h) async => (200, {'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'ok'}]});
    final ai = anthropic(limit: 1);
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), 'ok');
    expect(ai.available, isFalse);
    expect(await ai.complete(const AiRequest(system: 's', prompt: 'p')), isNull);
    expect(api.requests.length, 1);
  });

  test('concurrency limit queues requests', () async {
    var inFlight = 0, peak = 0;
    api.reply = (p, b, h) async {
      inFlight++;
      peak = peak > inFlight ? peak : inFlight;
      await Future.delayed(const Duration(milliseconds: 150));
      inFlight--;
      return (200, {'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'ok'}]});
    };
    final ai = HttpAiService(
        provider: 'anthropic', apiKey: 'k', model: 'claude-sonnet-5', baseUrl: api.base, maxConcurrency: 2);
    final rs = await Future.wait([for (var i = 0; i < 5; i++) ai.complete(const AiRequest(system: '', prompt: 'p'))]);
    expect(rs, everyElement('ok'));
    expect(peak, lessThanOrEqualTo(2));
  });

  test('openai: text-only string content, images as data URLs, token param', () async {
    api.reply = (p, b, h) async => (
          200,
          {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '苹果'}
              }
            ]
          }
        );
    final ai = HttpAiService.fromEnv({
      'AI_PROVIDER': 'openai',
      'OPENAI_API_KEY': 'sk-o',
      'OPENAI_MODEL': 'deepseek-chat',
      'OPENAI_BASE_URL': '${api.base}/v1/',
      'OPENAI_TOKEN_PARAM': 'max_completion_tokens',
      'AI_VISION': 'false',
    });
    expect(ai.vision, isFalse);
    expect(ai.label, 'openai · deepseek-chat');
    expect(await ai.complete(const AiRequest(system: 'sys', prompt: 'hi')), '苹果');
    var q = api.requests.last;
    expect(q.path, '/v1/chat/completions');
    expect(q.headers['authorization'], 'Bearer sk-o');
    expect(q.body['model'], 'deepseek-chat');
    expect(q.body['max_completion_tokens'], 800);
    expect(q.body.containsKey('max_tokens'), isFalse);
    expect(q.body['messages'], [
      {'role': 'system', 'content': 'sys'},
      {'role': 'user', 'content': 'hi'},
    ]);
    expect(await ai.complete(AiRequest(system: 'sys', prompt: 'look', images: [img])), '苹果');
    q = api.requests.last;
    final user = (q.body['messages'] as List)[1]['content'] as List;
    expect(user[0], {'type': 'text', 'text': 'look'});
    expect(user[1], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,${base64.encode([1, 2, 3, 4])}'}
    });
  });

  test('not configured → unavailable', () {
    expect(HttpAiService.fromEnv({}).available, isFalse);
    expect(HttpAiService.fromEnv({'AI_PROVIDER': 'anthropic'}).available, isFalse);
    final a = HttpAiService.fromEnv({'AI_PROVIDER': 'anthropic', 'ANTHROPIC_API_KEY': 'k'});
    expect(a.available, isTrue);
    expect(a.model, 'claude-opus-5');
    expect(a.baseUrl, 'https://api.anthropic.com');
    expect(a.useFallbacks, isTrue);
  });

  test('.env parser', () {
    final e = parseEnv('# c\nA=1\n export B = "x # y" \nC=\'q\'\nD=plain # comment\nE=\n bad line\n﻿F=2\n');
    expect(e, {'A': '1', 'B': 'x # y', 'C': 'q', 'D': 'plain', 'E': '', 'F': '2'});
    expect(parseEnv(envTemplate)['ANTHROPIC_MODEL'], 'claude-opus-5');
    expect(parseEnv(envTemplate)['OPENAI_BASE_URL'], 'https://api.openai.com/v1');
    final dir = Directory.systemTemp.createTempSync('aurora_env');
    ensureEnvExample(dir.path);
    expect(File('${dir.path}/.env.example').existsSync(), isTrue);
    File('${dir.path}/.env').writeAsStringSync('AI_PROVIDER=openai\nREPLAY_KEEP=5\n');
    final (vals, path) = loadEnv([dir.path]);
    expect(path, isNotNull);
    expect(vals['AI_PROVIDER'], 'openai');
    expect(vals['REPLAY_KEEP'], '5');
    dir.deleteSync(recursive: true);
  });
}
