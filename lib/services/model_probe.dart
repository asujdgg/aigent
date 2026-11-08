import 'dart:async';

/// 「检测当前模型能否使用」的结果。纯数据，便于单测与 UI 展示。
class ModelProbe {
  final bool ok;
  final int ms;
  final String detail;

  const ModelProbe({required this.ok, required this.ms, required this.detail});

  String get headline => ok ? '当前模型可用' : '当前模型不可用';

  String get timing => '${ms}ms';
}

/// 把网络 / 网关异常翻成人能看懂的一句话。
String describeProbeError(Object e) {
  if (e is TimeoutException) {
    return '请求超时（25 秒）：接口不可达，或模型排队过久';
  }
  var s = e.toString();
  // LlmClient 把网关错误包成 StateError / Exception，先剥掉前缀再归因。
  if (s.startsWith('Bad state: ')) s = s.substring(11);
  if (s.startsWith('Exception: ')) s = s.substring(11);
  if (s.contains('SocketException')) return '连不上服务器，检查 Base URL 与网络';
  if (s.contains('HandshakeException')) return 'TLS 握手失败，检查地址是否用了 https';
  if (s.contains('401') || s.toLowerCase().contains('unauthorized')) {
    return '鉴权失败（401）：API Key 不对或已过期';
  }
  if (s.contains('403')) return '被拒绝（403）：Key 无权限访问该模型';
  if (s.contains('404')) return '接口不存在（404）：检查 Base URL 或模型名';
  if (s.contains('429')) return '限流（429）：额度用尽或请求太频繁';
  if (s.contains('5') && RegExp(r'\b5\d\d\b').hasMatch(s)) {
    return '服务端错误，稍后再试';
  }
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

/// 探测回复的摘要，只用于展示，不写进会话。
String probeReplyPreview(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  return t.length > 24 ? '${t.substring(0, 24)}…' : t;
}
