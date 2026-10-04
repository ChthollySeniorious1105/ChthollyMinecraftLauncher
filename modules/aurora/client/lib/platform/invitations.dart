import 'package:aurora_shared/aurora_shared.dart';

import '../net/transport.dart';
import '../state/app_state.dart';

String suggestedWebUrl(AppState app) {
  final saved = app.prefs.getString('inviteWeb:${app.address}') ?? '';
  if (saved.isNotEmpty) return saved;
  if (app.publicWebUrl.isNotEmpty) return app.publicWebUrl;
  if (kIsWebTransport) return defaultWebAddress();
  if (app.webPort == null) return '';
  final (host, _) = parseHostPort(app.address);
  return Uri(scheme: 'http', host: host, port: app.webPort).toString();
}

String? roomInvitation(AppState app, String webUrl) {
  final u = Uri.tryParse(webUrl.trim());
  if (u == null ||
      !['http', 'https'].contains(u.scheme) ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      webUrl.length > 1500) {
    return null;
  }
  final room = app.room?['id'];
  if (room == null) return null;
  final native = app.publicNativeAddress.isNotEmpty
      ? app.publicNativeAddress
      : kIsWebTransport
      ? ''
      : app.address;
  return AuroraInvitation(
    u.replace(query: '', fragment: '').toString(),
    '$room',
    native,
  ).url;
}
