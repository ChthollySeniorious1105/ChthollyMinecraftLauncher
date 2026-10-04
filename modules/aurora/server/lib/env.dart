import 'dart:io';

/// Keys understood by the server (`.env` next to the exe, then the cwd).
const envKeys = [
  'AI_PROVIDER',
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_MODEL',
  'ANTHROPIC_BASE_URL',
  'OPENAI_API_KEY',
  'OPENAI_MODEL',
  'OPENAI_BASE_URL',
  'OPENAI_TOKEN_PARAM',
  'AI_VISION',
  'AI_MAX_CONCURRENCY',
  'AI_TIMEOUT',
  'AI_DAILY_LIMIT',
  'REPLAY_KEEP',
  'TRUST_PROXY',
  'PUBLIC_WEB_URL',
  'PUBLIC_TCP_ADDRESS',
];

const envTemplate = '''# Aurora 服务器配置（.env）
# 把本文件复制/重命名为 .env（与 aurora_server.exe 同目录），修改后重启服务器生效。
# 以 # 开头的行是注释；值可以用引号包起来。请勿把含有密钥的 .env 分享给别人。

# ---- 大模型（AI 电脑玩家）----
# AI_PROVIDER=anthropic 或 openai（留空 = 不启用 AI，电脑玩家使用普通算法）
AI_PROVIDER=

# Anthropic（Claude）
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-opus-5
ANTHROPIC_BASE_URL=https://api.anthropic.com

# OpenAI 或任何 OpenAI 兼容服务（DeepSeek / 通义 / Kimi / 本地 Ollama 等）
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
OPENAI_BASE_URL=https://api.openai.com/v1
# 部分新模型要求 max_completion_tokens
OPENAI_TOKEN_PARAM=max_tokens

# 模型是否支持看图（你画我猜 AI 猜画）
AI_VISION=true
# 同时进行的最大请求数
AI_MAX_CONCURRENCY=4
# 单次请求超时（秒）
AI_TIMEOUT=25
# 每日最多请求数，超出后 AI 自动退回普通电脑
AI_DAILY_LIMIT=3000

# ---- 回放 ----
# 最多保留多少局回放（超出删除最旧的）
REPLAY_KEEP=2000

# ---- 网页版 ----
# 网页版端口在 aurora_server.json 的 webPort 或启动参数 --web-port 设置（0 = 关闭）。
# 只有把网页版放在 nginx / Caddy 等反向代理后面时才设为 true（从 X-Forwarded-For 读取玩家 IP）
TRUST_PROXY=false
# 好友能够访问的网页入口，用于二维码与邀请链接（内网穿透时填映射后的地址）
PUBLIC_WEB_URL=
# 好友能够访问的原生客户端 TCP 地址，例如 play.example.com:7788
PUBLIC_TCP_ADDRESS=
''';

/// Parse `KEY=VALUE` lines: `#` comments (whole-line, or after whitespace for
/// unquoted values), optional `export ` prefix, optional single/double quotes.
Map<String, String> parseEnv(String text) {
  final out = <String, String>{};
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.startsWith(String.fromCharCode(0xFEFF))) line = line.substring(1).trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trim();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var v = line.substring(eq + 1).trim();
    if (v.length >= 2 && (v[0] == '"' || v[0] == "'")) {
      final end = v.indexOf(v[0], 1);
      if (end > 0) {
        v = v.substring(1, end);
        out[key] = v;
        continue;
      }
    }
    final hash = v.indexOf(RegExp(r'\s#'));
    if (hash >= 0) v = v.substring(0, hash).trim();
    out[key] = v;
  }
  return out;
}

/// Load the first existing `.env` among [dirs]. Process environment variables
/// for [envKeys] are used as fallback. Returns (values, path or null).
(Map<String, String>, String?) loadEnv(List<String> dirs) {
  final out = <String, String>{};
  for (final k in envKeys) {
    final v = Platform.environment[k];
    if (v != null && v.isNotEmpty) out[k] = v;
  }
  for (final d in dirs) {
    final f = File('$d${Platform.pathSeparator}.env');
    try {
      if (f.existsSync()) {
        out.addAll(parseEnv(f.readAsStringSync()));
        return (out, f.path);
      }
    } catch (_) {}
  }
  return (out, null);
}

/// Write `.env.example` into [dir] if missing.
void ensureEnvExample(String dir) {
  try {
    final f = File('$dir${Platform.pathSeparator}.env.example');
    if (!f.existsSync()) f.writeAsStringSync(envTemplate);
  } catch (_) {}
}
