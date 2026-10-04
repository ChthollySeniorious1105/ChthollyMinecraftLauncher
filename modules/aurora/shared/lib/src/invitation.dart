/// An invitation never contains a room password or a reconnect token.
class AuroraInvitation {
  final String webUrl;
  final String room;
  final String nativeAddress;
  const AuroraInvitation(this.webUrl, this.room, this.nativeAddress);

  static AuroraInvitation? parse(String text) {
    final candidate = RegExp(
      r'https?://[^\s]+',
    ).firstMatch(text.trim())?.group(0);
    if (candidate == null || candidate.length > 2048) return null;
    final u = Uri.tryParse(candidate);
    if (u == null || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
    final code = (u.queryParameters['room'] ?? '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{5}$').hasMatch(code)) return null;
    final native = u.queryParameters['tcp'] ?? '';
    if (native.length > 255 || native.contains(RegExp(r'[\s/\\?#@]')))
      return null;
    return AuroraInvitation(
      u.replace(query: '', fragment: '').toString(),
      code,
      native,
    );
  }

  String get url => Uri.parse(webUrl)
      .replace(
        queryParameters: {
          'room': room,
          if (nativeAddress.isNotEmpty) 'tcp': nativeAddress,
        },
        fragment: '',
      )
      .toString();
}
