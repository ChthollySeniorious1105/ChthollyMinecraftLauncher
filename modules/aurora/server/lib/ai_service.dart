import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_shared/aurora_shared.dart';

void _log(String s) {
  final t = DateTime.now().toIso8601String().substring(11, 19);
  stdout.writeln('[$t] $s');
}

/// LLM access over raw HTTP (there is no official Dart SDK): Anthropic
/// Messages API or any OpenAI-compatible chat-completions endpoint.
/// Configured from `.env` (see env.dart). Never throws, never logs keys.
class HttpAiService extends AiService {
  final String provider; // 'anthropic' | 'openai' | ''
  final String apiKey;
  final String model;
  final String baseUrl;
  final String tokenParam;
  final bool _vision;
  final int maxConcurrency;
  final Duration timeout;
  final int dailyLimit;

  /// Whether to send the server-side fallback beta; turned off permanently
  /// if the API rejects it.
  bool useFallbacks;

  int _active = 0;
  final Queue<Completer<void>> _queue = Queue();
  String _day = '';
  int _todayCount = 0;
  int totalRequests = 0;
  int failures = 0;
  String lastError = '';
  DateTime? lastErrorAt;

  HttpAiService({
    required this.provider,
    required this.apiKey,
    required this.model,
    required this.baseUrl,
    this.tokenParam = 'max_tokens',
    bool vision = true,
    this.maxConcurrency = 4,
    this.timeout = const Duration(seconds: 25),
    this.dailyLimit = 3000,
  })  : _vision = vision,
        useFallbacks = provider == 'anthropic' && (model.startsWith('claude-opus-5') || model.startsWith('claude-fable'));

  /// Build from `.env` values; returns a service that is not [available] when
  /// nothing is configured.
  factory HttpAiService.fromEnv(Map<String, String> env) {
    final p = (env['AI_PROVIDER'] ?? '').trim().toLowerCase();
    int n(String k, int d) => int.tryParse(env[k]?.trim() ?? '') ?? d;
    final vision = !['false', '0', 'no', 'off'].contains((env['AI_VISION'] ?? 'true').trim().toLowerCase());
    String s(String k, String d) {
      final v = env[k]?.trim() ?? '';
      return v.isEmpty ? d : v;
    }

    final common = (
      vision: vision,
      conc: n('AI_MAX_CONCURRENCY', 4).clamp(1, 64),
      timeout: Duration(seconds: n('AI_TIMEOUT', 25).clamp(1, 600)),
      limit: n('AI_DAILY_LIMIT', 3000),
    );
    if (p == 'anthropic') {
      return HttpAiService(
        provider: 'anthropic',
        apiKey: s('ANTHROPIC_API_KEY', ''),
        model: s('ANTHROPIC_MODEL', 'claude-opus-5'),
        baseUrl: s('ANTHROPIC_BASE_URL', 'https://api.anthropic.com'),
        vision: common.vision,
        maxConcurrency: common.conc,
        timeout: common.timeout,
        dailyLimit: common.limit,
      );
    }
    if (p == 'openai') {
      return HttpAiService(
        provider: 'openai',
        apiKey: s('OPENAI_API_KEY', ''),
        model: s('OPENAI_MODEL', 'gpt-4o-mini'),
        baseUrl: s('OPENAI_BASE_URL', 'https://api.openai.com/v1'),
        tokenParam: s('OPENAI_TOKEN_PARAM', 'max_tokens'),
        vision: common.vision,
        maxConcurrency: common.conc,
        timeout: common.timeout,
        dailyLimit: common.limit,
      );
    }
    return HttpAiService(provider: '', apiKey: '', model: '', baseUrl: '');
  }

  bool get configured => (provider == 'anthropic' || provider == 'openai') && apiKey.isNotEmpty;

  void _rollDay() {
    final d = DateTime.now().toIso8601String().substring(0, 10);
    if (d != _day) {
      _day = d;
      _todayCount = 0;
    }
  }

  int get todayCount {
    _rollDay();
    return _todayCount;
  }

  @override
  bool get available => configured && (dailyLimit <= 0 || todayCount < dailyLimit);

  @override
  bool get vision => _vision;

  @override
  String get label => configured ? '$provider · $model' : '';

  String status() {
    if (!configured) {
      return provider.isEmpty ? 'AI 未启用（在 .env 设置 AI_PROVIDER 和 API Key）' : 'AI 未启用：缺少 $provider 的 API Key';
    }
    final err = lastError.isEmpty ? '无' : '${lastErrorAt?.toIso8601String().substring(11, 19)} $lastError';
    return 'AI：$label  可用=${available ? "是" : "否"}  看图=${vision ? "是" : "否"}\n'
        '  今日请求 $todayCount/${dailyLimit <= 0 ? "不限" : dailyLimit}  总计 $totalRequests  失败 $failures  进行中 $_active  排队 ${_queue.length}\n'
        '  最近错误：$err';
  }

  void _fail(String msg) {
    failures++;
    // never include the key; strip anything that looks like one just in case
    var m = msg.replaceAll(apiKey, '***');
    if (m.length > 300) m = '${m.substring(0, 300)}…';
    lastError = m;
    lastErrorAt = DateTime.now();
    _log('AI 请求失败：$m');
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrency) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future; // slot handed over by _release
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _active--;
    }
  }

  @override
  Future<String?> complete(AiRequest req) async {
    if (!available) return null;
    _rollDay();
    _todayCount++;
    totalRequests++;
    await _acquire();
    try {
      return await (provider == 'anthropic' ? _anthropic(req) : _openai(req)).timeout(timeout);
    } on TimeoutException {
      _fail('超时（${timeout.inSeconds} 秒）');
      return null;
    } catch (e) {
      _fail('$e');
      return null;
    } finally {
      _release();
    }
  }

  String _base() => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<(int, String)> _post(Uri url, Map<String, String> headers, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = timeout;
    Future<(int, String)> send() async {
      final rq = await client.postUrl(url);
      headers.forEach(rq.headers.set);
      rq.headers.contentType = ContentType.json;
      rq.add(utf8.encode(jsonEncode(body)));
      final rs = await rq.close();
      final text = await rs.transform(utf8.decoder).join();
      return (rs.statusCode, text);
    }

    try {
      return await send().timeout(timeout);
    } finally {
      // also aborts a request that timed out
      client.close(force: true);
    }
  }

  static String _short(String s) => s.length > 200 ? s.substring(0, 200) : s;

  Future<String?> _anthropic(AiRequest req) async {
    final content = <Map<String, dynamic>>[
      for (final im in req.images)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': im.mediaType, 'data': im.base64Data}
        },
      {'type': 'text', 'text': req.prompt},
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      final fb = useFallbacks;
      final body = <String, dynamic>{
        'model': model,
        // adaptive thinking may consume part of the budget
        'max_tokens': req.maxTokens > 1024 ? req.maxTokens : 1024,
        if (req.system.isNotEmpty) 'system': req.system,
        'messages': [
          {'role': 'user', 'content': content}
        ],
        'output_config': {'effort': 'low'},
        if (fb) 'fallbacks': 'default',
      };
      final headers = {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (fb) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      };
      final (code, text) = await _post(Uri.parse('${_base()}/v1/messages'), headers, body);
      if (code == 400 && fb && RegExp('fallback|beta', caseSensitive: false).hasMatch(text)) {
        useFallbacks = false;
        _log('AI：服务端不支持 fallbacks 参数，已关闭后重试');
        continue;
      }
      if (code < 200 || code >= 300) {
        _fail('Anthropic HTTP $code ${_short(text)}');
        return null;
      }
      final j = jsonDecode(text);
      if (j is! Map) {
        _fail('Anthropic 响应格式错误');
        return null;
      }
      if (j['stop_reason'] == 'refusal') {
        _fail('Anthropic 拒绝回答（refusal）');
        return null;
      }
      final blocks = j['content'];
      if (blocks is! List) return null;
      final out = StringBuffer();
      for (final b in blocks) {
        if (b is Map && b['type'] == 'text' && b['text'] is String) out.write(b['text']);
      }
      return out.toString();
    }
    return null;
  }

  Future<String?> _openai(AiRequest req) async {
    final Object user = req.images.isEmpty
        ? req.prompt
        : [
            {'type': 'text', 'text': req.prompt},
            for (final im in req.images)
              {
                'type': 'image_url',
                'image_url': {'url': 'data:${im.mediaType};base64,${im.base64Data}'}
              },
          ];
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        if (req.system.isNotEmpty) {'role': 'system', 'content': req.system},
        {'role': 'user', 'content': user},
      ],
      tokenParam: req.maxTokens > 800 ? req.maxTokens : 800,
    };
    final (code, text) =
        await _post(Uri.parse('${_base()}/chat/completions'), {'authorization': 'Bearer $apiKey'}, body);
    if (code < 200 || code >= 300) {
      _fail('OpenAI HTTP $code ${_short(text)}');
      return null;
    }
    final j = jsonDecode(text);
    final choices = j is Map ? j['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      _fail('OpenAI 响应中没有 choices');
      return null;
    }
    final msg = (choices.first as Map)['message'];
    final c = msg is Map ? msg['content'] : null;
    if (c is String) return c;
    if (c is List) {
      return [for (final p in c) if (p is Map && p['text'] is String) p['text']].join();
    }
    return null;
  }
}
