import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../common/errors.dart';
import '../net/http.dart';

/// Azure application used for Microsoft login.
///
/// Minecraft services only accept tokens from Azure apps that Mojang has approved
/// (https://aka.ms/mce-reviewappid). Set the approved client id at build time with
/// `--dart-define=CML_MSA_CLIENT_ID=<id>` or in settings → 账号 → 高级.
abstract class MsaConfig {
  static const builtInClientId = String.fromEnvironment('CML_MSA_CLIENT_ID');
  static String clientId = builtInClientId;
  static const scope = 'XboxLive.signin offline_access';
  static const tenant = 'consumers';

  /// Public Xbox Live client used by the `microsoft.com/link` code flow (no Azure app needed).
  static const liveClientId = '00000000441cc96b';
  static const liveScope = 'service::user.auth.xboxlive.com::MBI_SSL';
}

/// Which OAuth flow an account was signed in with.
enum LoginMethod {
  /// login.live.com device code → enter the code at microsoft.com/link. Default, works out of the box.
  link,

  /// Azure AD (login.microsoftonline.com) with a Mojang-approved app id.
  azure,
}

class DeviceCode {
  final String userCode;
  final String deviceCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  final String message;
  final LoginMethod method;
  DeviceCode(this.userCode, this.deviceCode, this.verificationUri, this.expiresIn, this.interval, this.message, this.method);

  /// Link that pre-fills the code where supported.
  String get directUri => method == LoginMethod.link ? 'https://www.microsoft.com/link?otc=$userCode' : verificationUri;
}

class Cape {
  final String id;
  final String alias;
  final String url;
  final bool active;
  Cape(this.id, this.alias, this.url, this.active);
}

class Skin {
  final String id;
  final String url;
  final String variant; // CLASSIC / SLIM
  final bool active;
  Skin(this.id, this.url, this.variant, this.active);
}

/// A logged-in Microsoft account. Serialised (minus nothing) into the account store,
/// which the launcher encrypts with DPAPI.
class MsAccount {
  String name;
  String uuid;
  String mcToken;
  DateTime mcExpires;
  String refreshToken;
  String xuid;
  List<Skin> skins;
  List<Cape> capes;
  LoginMethod method;

  MsAccount({
    required this.name,
    required this.uuid,
    required this.mcToken,
    required this.mcExpires,
    required this.refreshToken,
    this.xuid = '0',
    this.skins = const [],
    this.capes = const [],
    this.method = LoginMethod.link,
  });

  bool get tokenValid => DateTime.now().isBefore(mcExpires.subtract(const Duration(minutes: 5)));
  Skin? get activeSkin => skins.where((s) => s.active).firstOrNull;
  Cape? get activeCape => capes.where((c) => c.active).firstOrNull;

  Map<String, dynamic> toJson() => {
        'name': name,
        'uuid': uuid,
        'mcToken': mcToken,
        'mcExpires': mcExpires.toIso8601String(),
        'refreshToken': refreshToken,
        'xuid': xuid,
        'skins': [for (final s in skins) {'id': s.id, 'url': s.url, 'variant': s.variant, 'active': s.active}],
        'capes': [for (final c in capes) {'id': c.id, 'alias': c.alias, 'url': c.url, 'active': c.active}],
        'method': method.name,
      };

  factory MsAccount.fromJson(Map j) => MsAccount(
        name: '${j['name']}',
        uuid: '${j['uuid']}',
        mcToken: '${j['mcToken']}',
        mcExpires: DateTime.tryParse('${j['mcExpires']}') ?? DateTime(2000),
        refreshToken: '${j['refreshToken']}',
        xuid: '${j['xuid'] ?? '0'}',
        skins: [for (final s in (j['skins'] as List? ?? [])) Skin('${s['id']}', '${s['url']}', '${s['variant']}', s['active'] == true)],
        capes: [for (final c in (j['capes'] as List? ?? [])) Cape('${c['id']}', '${c['alias']}', '${c['url']}', c['active'] == true)],
        // accounts saved before LoginMethod existed came from Azure
        method: LoginMethod.values.firstWhere((m) => m.name == j['method'], orElse: () => LoginMethod.azure),
      );
}

class MicrosoftAuth {
  final Http http;

  /// "正版登录时验证 SSL 证书". Only turn off behind TLS-intercepting proxies.
  bool verifySsl;
  MicrosoftAuth(this.http, {this.verifySsl = true});

  static const _login = 'https://login.microsoftonline.com/${MsaConfig.tenant}/oauth2/v2.0';
  static const _live = 'https://login.live.com';
  static const _services = 'https://api.minecraftservices.com';

  /// Azure is used only when an app id is configured; otherwise the microsoft.com/link flow.
  LoginMethod get defaultMethod => MsaConfig.clientId.isEmpty ? LoginMethod.link : LoginMethod.azure;

  void _requireClientId() {
    if (MsaConfig.clientId.isEmpty) {
      throw const CmlException('msa_client_id', '未配置 Azure 应用 ID，请改用「microsoft.com/link」方式登录，或在设置中填写');
    }
  }

  Uri _tokenUri(LoginMethod m) => Uri.parse(m == LoginMethod.link ? '$_live/oauth20_token.srf' : '$_login/token');
  String _clientId(LoginMethod m) => m == LoginMethod.link ? MsaConfig.liveClientId : MsaConfig.clientId;
  String _scope(LoginMethod m) => m == LoginMethod.link ? MsaConfig.liveScope : MsaConfig.scope;

  Future<DeviceCode> startDeviceCode({LoginMethod? method}) async {
    final m = method ?? defaultMethod;
    if (m == LoginMethod.azure) _requireClientId();
    final j = m == LoginMethod.link
        ? await http.postForm(Uri.parse('$_live/oauth20_connect.srf'),
            {'client_id': MsaConfig.liveClientId, 'scope': MsaConfig.liveScope, 'response_type': 'device_code'}, verifySsl: verifySsl) as Map
        : await http.postForm(Uri.parse('$_login/devicecode'), {'client_id': MsaConfig.clientId, 'scope': MsaConfig.scope}, verifySsl: verifySsl) as Map;
    return DeviceCode('${j['user_code']}', '${j['device_code']}', '${j['verification_uri'] ?? 'https://www.microsoft.com/link'}',
        (j['expires_in'] as num).toInt(), (j['interval'] as num?)?.toInt() ?? 5, '${j['message'] ?? ''}', m);
  }

  /// Polls until the user finishes signing in, then completes the full chain.
  Future<MsAccount> pollDeviceCode(DeviceCode dc, {CancelToken? cancel, void Function(String)? onStep}) async {
    var interval = dc.interval;
    final deadline = DateTime.now().add(Duration(seconds: dc.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      cancel?.throwIfCancelled();
      await Future<void>.delayed(Duration(seconds: interval));
      cancel?.throwIfCancelled();
      try {
        final j = await http.postForm(
            _tokenUri(dc.method),
            {
              'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              'client_id': _clientId(dc.method),
              'device_code': dc.deviceCode,
            },
            verifySsl: verifySsl) as Map;
        return await _finish('${j['access_token']}', '${j['refresh_token']}', dc.method, onStep);
      } on HttpStatusException catch (e) {
        final err = (e.json is Map) ? '${e.json['error']}' : '';
        if (err == 'authorization_pending') continue;
        if (err == 'slow_down') {
          interval += 5;
          continue;
        }
        if (err == 'expired_token') break;
        if (err == 'authorization_declined' || err == 'access_denied') throw const CmlException('msa_declined', '你拒绝了登录授权');
        rethrow;
      }
    }
    throw const CmlException('msa_expired', '登录代码已过期，请重新登录');
  }

  /// Refreshes the Minecraft token (and profile/skins/capes).
  Future<MsAccount> refresh(MsAccount a, {void Function(String)? onStep}) async {
    if (a.method == LoginMethod.azure) _requireClientId();
    try {
      final j = await http.postForm(
          _tokenUri(a.method),
          {'grant_type': 'refresh_token', 'client_id': _clientId(a.method), 'refresh_token': a.refreshToken, 'scope': _scope(a.method)},
          verifySsl: verifySsl) as Map;
      return await _finish('${j['access_token']}', '${j['refresh_token']}', a.method, onStep);
    } on HttpStatusException catch (e) {
      if (e.status == 400 || e.status == 401) throw CmlException('msa_relogin', '账号 ${a.name} 的登录已过期，请重新登录', e);
      rethrow;
    }
  }

  /// Ensures [a] has a valid token, refreshing if needed. Returns the same or a refreshed account.
  Future<MsAccount> ensureValid(MsAccount a) async => a.tokenValid ? a : refresh(a);

  Future<MsAccount> _finish(String msToken, String refreshToken, LoginMethod method, void Function(String)? onStep) async {
    onStep?.call('正在登录 Xbox Live');
    final xbl = await http.postJson(
        Uri.parse('https://user.auth.xboxlive.com/user/authenticate'),
        {
          'Properties': {'AuthMethod': 'RPS', 'SiteName': 'user.auth.xboxlive.com', 'RpsTicket': '${method == LoginMethod.link ? 't' : 'd'}=$msToken'},
          'RelyingParty': 'http://auth.xboxlive.com',
          'TokenType': 'JWT',
        },
        verifySsl: verifySsl) as Map;
    final xblToken = '${xbl['Token']}';
    final uhs = '${xbl['DisplayClaims']['xui'][0]['uhs']}';

    onStep?.call('正在获取 XSTS 令牌');
    Map xsts;
    try {
      xsts = await http.postJson(
          Uri.parse('https://xsts.auth.xboxlive.com/xsts/authorize'),
          {
            'Properties': {'SandboxId': 'RETAIL', 'UserTokens': [xblToken]},
            'RelyingParty': 'rp://api.minecraftservices.com/',
            'TokenType': 'JWT',
          },
          verifySsl: verifySsl) as Map;
    } on HttpStatusException catch (e) {
      final code = (e.json is Map) ? (e.json['XErr'] as num?)?.toInt() : null;
      throw CmlException('xsts_$code', switch (code) {
        2148916233 => '该微软账号还没有 Xbox 档案，请先访问 xbox.com 创建',
        2148916235 => '你所在的地区无法使用 Xbox Live',
        2148916236 || 2148916237 => '该账号需要完成成人验证（韩国地区）',
        2148916238 => '这是未成年账号，需要家长将其加入家庭组后才能登录',
        _ => 'Xbox Live 授权失败',
      }, e);
    }
    final xstsToken = '${xsts['Token']}';
    final xuid = '${(xsts['DisplayClaims']?['xui'] as List?)?.firstOrNull?['xid'] ?? '0'}';

    onStep?.call('正在登录 Minecraft');
    final mc = await http.postJson(Uri.parse('$_services/authentication/login_with_xbox'), {'identityToken': 'XBL3.0 x=$uhs;$xstsToken'},
        verifySsl: verifySsl) as Map;
    final mcToken = '${mc['access_token']}';
    final expires = DateTime.now().add(Duration(seconds: (mc['expires_in'] as num?)?.toInt() ?? 86400));

    onStep?.call('正在读取游戏档案');
    final profile = await _profile(mcToken);
    if (profile == null) {
      throw const CmlException('no_profile', '该账号没有购买 Minecraft Java 版，或尚未创建角色名（请先在官方启动器中设置）');
    }
    return _accountFrom(profile, mcToken, expires, refreshToken, xuid)..method = method;
  }

  Future<Map?> _profile(String mcToken) async {
    try {
      return await http.getJson(Uri.parse('$_services/minecraft/profile'), headers: {'Authorization': 'Bearer $mcToken'}, verifySsl: verifySsl)
          as Map;
    } on HttpStatusException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  MsAccount _accountFrom(Map p, String token, DateTime exp, String refresh, String xuid) => MsAccount(
        name: '${p['name']}',
        uuid: '${p['id']}',
        mcToken: token,
        mcExpires: exp,
        refreshToken: refresh,
        xuid: xuid,
        skins: _skins(p),
        capes: _capes(p),
      );

  static List<Skin> _skins(Map p) =>
      [for (final s in (p['skins'] as List? ?? [])) Skin('${s['id']}', '${s['url']}', '${s['variant']}', s['state'] == 'ACTIVE')];
  static List<Cape> _capes(Map p) =>
      [for (final c in (p['capes'] as List? ?? [])) Cape('${c['id']}', '${c['alias']}', '${c['url']}', c['state'] == 'ACTIVE')];

  Map<String, String> _auth(MsAccount a) => {'Authorization': 'Bearer ${a.mcToken}'};

  /// Re-reads skins and capes.
  Future<void> reloadProfile(MsAccount a) async {
    final p = await _profile(a.mcToken);
    if (p == null) return;
    a
      ..name = '${p['name']}'
      ..skins = _skins(p)
      ..capes = _capes(p);
  }

  /// Equips cape [capeId], or hides the cape when null ("披风切换").
  Future<void> setCape(MsAccount a, String? capeId) async {
    final u = Uri.parse('$_services/minecraft/profile/capes/active');
    final p = capeId == null
        ? await http.request('DELETE', u, headers: _auth(a), verifySsl: verifySsl)
        : await http.postJson(u, {'capeId': capeId}, headers: _auth(a), verifySsl: verifySsl, method: 'PUT');
    if (p is Map) a.capes = _capes(p);
  }

  /// Uploads a skin PNG (64×64 or 64×32). [slim] selects the Alex model.
  Future<void> uploadSkin(MsAccount a, Uint8List png, {required bool slim}) async {
    final boundary = '----cml${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="variant"\r\n\r\n${slim ? 'slim' : 'classic'}\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="skin.png"\r\nContent-Type: image/png\r\n\r\n'))
      ..add(png)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final p = await http.request('POST', Uri.parse('$_services/minecraft/profile/skins'),
        body: body.takeBytes(), contentType: 'multipart/form-data; boundary=$boundary', headers: _auth(a), verifySsl: verifySsl);
    if (p is Map) a.skins = _skins(p);
  }

  Future<void> resetSkin(MsAccount a) async {
    final p = await http.request('DELETE', Uri.parse('$_services/minecraft/profile/skins/active'), headers: _auth(a), verifySsl: verifySsl);
    if (p is Map) a.skins = _skins(p);
  }
}
