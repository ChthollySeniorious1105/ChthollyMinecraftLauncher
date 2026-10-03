import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';

const bool isWeb = false;

String defaultWebAddress() => '';

class _TcpLink implements Link {
  final Socket s;
  _TcpLink(this.s);
  @override
  Stream<Uint8List> get data => s;
  @override
  void add(List<int> bytes) => s.add(bytes);
  @override
  Future<void> close() async {
    try {
      await s.close();
    } catch (_) {}
    s.destroy();
  }

  @override
  void destroy() => s.destroy();
}

Future<Link> openLink(String address, Duration timeout) async {
  final (host, port) = parseHostPort(address);
  if (host.isEmpty) throw const ConnectException('地址为空');
  final Socket s;
  try {
    s = await Socket.connect(host, port, timeout: timeout);
  } on SocketException catch (e) {
    final m = '${e.osError?.message ?? ''} ${e.message}';
    if (m.contains('timed out') || m.contains('超时')) throw const ConnectException('连接超时');
    if (m.contains('refused') || m.contains('拒绝') || e.osError?.errorCode == 10061 || e.osError?.errorCode == 111) {
      throw const ConnectException('连接被拒绝（服务器未启动或端口错误）');
    }
    if (m.contains('host lookup') || m.contains('No such host')) throw const ConnectException('无法解析地址');
    throw ConnectException(e.message.isEmpty ? '$e' : e.message);
  }
  s.setOption(SocketOption.tcpNoDelay, true);
  s.done.catchError((_) {});
  return _TcpLink(s);
}
