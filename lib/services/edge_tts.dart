import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';


/// 微软 Edge「大声朗读」通道。
///
/// 免密钥、音色接近真人、中文有 14 个音色，是当前唯一既能离线之外
/// 稳定出声、又不收费的中文 TTS。官方只对 Edge 浏览器开放 WebSocket，
/// 所以这里按它的公开协议拼请求：先握手，再发一帧配置、一帧 SSML，
/// 回包是「2 字节头长度 + 头文本 + mp3 数据」。
///
/// 微软 2024 年起加了 `Sec-MS-GEC` 签名（v2：CS64 + SHA256），
/// 少了它直接 403。签名与版本号都可能随微软前端更新而失效，
/// 因此调用方必须保留「失败回落系统语音」的路径。
class EdgeTts {
  EdgeTts._();

  static const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

  /// 与签名里的 `Sec-MS-GEC-Version` 必须一致，微软按前端版本校验。
  static const _chromium = '143.0.3650.75';
  static const _gecVersion = '2-$_chromium';

  static const _wss =
      'wss://speech.platform.bing.com:443/consumer/speech/synthesize/readaloud/edge/v1';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';

  /// 合成一段语音，返回 mp3 字节。失败抛异常，由调用方回落。
  static Future<Uint8List> synthesize({
    required String text,
    String voice = 'zh-CN-XiaoxiaoNeural',
    double rate = 1.0,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (text.trim().isEmpty) throw const EdgeTtsException('没有可朗读的内容');
    final connId = _hex(16);
    final url = Uri.parse(
      '$_wss?TrustedClientToken=$_token&ConnectionId=$connId'
      '&Sec-MS-GEC=${secMsGec()}&Sec-MS-GEC-Version=$_gecVersion',
    );

    _WsConn ws;
    try {
      ws = await _WsConn.connect(url, {
        'User-Agent': _ua,
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'en-US,en;q=0.9',
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'Cookie': 'muid=${_hex(16).toUpperCase()};',
      }).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const EdgeTtsException('连接微软语音超时');
    } on EdgeTtsException {
      rethrow;
    } catch (e) {
      throw EdgeTtsException('连接微软语音失败：$e');
    }

    final audio = BytesBuilder(copy: false);
    final done = Completer<void>();

    ws.messages.listen(
      (dynamic msg) {
        if (msg is List<int>) {
          if (msg.length < 2) return;
          final headerLen = (msg[0] << 8) | msg[1];
          if (msg.length < 2 + headerLen) return;
          final header = utf8.decode(
            msg.sublist(2, 2 + headerLen),
            allowMalformed: true,
          );
          if (header.contains('Path:audio')) {
            audio.add(msg.sublist(2 + headerLen));
          }
        } else if (msg is String && msg.contains('Path:turn.end')) {
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(EdgeTtsException('微软语音连接中断：$e'));
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    final stamp = _httpDate();
    ws.sendText('X-Timestamp:$stamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}');

    final pct = ((rate.clamp(0.5, 2.0) - 1.0) * 100).round();
    final ssml = "<speak version='1.0' "
        "xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
        "<voice name='$voice'><prosody rate='${pct >= 0 ? '+' : ''}$pct%' "
        "pitch='+0Hz'>${_escape(text)}</prosody></voice></speak>";
    ws.sendText('X-RequestId:${_hex(16)}\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$stamp\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml');

    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      throw const EdgeTtsException('微软语音合成超时');
    } finally {
      await ws.close();
    }

    final bytes = audio.takeBytes();
    if (bytes.isEmpty) throw const EdgeTtsException('微软语音没有返回音频');
    return bytes;
  }

  // ---------------------------------------------------------- 签名

  /// `Sec-MS-GEC`：Windows 文件时间（100ns）对齐到 5 分钟，
  /// 拼上客户端 token 后取 `CS64-SHA256`。
  ///
  /// 注意这里的 SHA256 被微软改过：前 7 个字节当 salt 生成初始状态，
  /// 消息本身从第 8 个字节开始，长度按「7 + 全长」计。用标准 sha256
  /// 算出来的值服务器不认，所以下面把改版算法完整实现了一遍。
  static String secMsGec([DateTime? at]) {
    // 全程整数：1.34e17 超出 double 的 53 位精度，用浮点算会差几十个 tick。
    final epochSec = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    var secs = epochSec + 11644473600; // Unix → Windows 纪元
    secs -= secs % 300; // 5 分钟对齐
    final ticks = secs * 10000000;
    final data = ascii.encode('$ticks$_token');
    final digest = _shaDigest(data);
    final cs64 = _cs64Hex(data, digest);
    return '$cs64-${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  static const int _u32 = 0xFFFFFFFF;

  static const List<int> _k = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
  ];

  static const List<int> _initial = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ];

  /// 微软改过的初始状态（标准 SHA256 的那组被换掉了）。
  static const List<int> _customState = [
    0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
    0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
  ];

  static const List<int> _scheduleSeed = [
    0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
    0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
    0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
    0xD258B060, 0x72766564,
  ];

  static const int _adjust = 0xC9DC06A7;
  static const int _sigma0Adj = 0x059C0B80;
  static const int _sigma1Adj = 0x000B92C0;

  static int _rotr(int x, int n) =>
      (((x & _u32) >> n) | ((x & _u32) << (32 - n))) & _u32;

  static int _sigma0(int x) =>
      (_rotr(x, 7) ^ _rotr(x, 18) ^ ((x & _u32) >> 3)) & _u32;

  static int _sigma1(int x) =>
      (_rotr(x, 17) ^ _rotr(x, 19) ^ ((x & _u32) >> 10)) & _u32;

  static int _bigSigma0(int x) => _rotr(x, 2) ^ _rotr(x, 13) ^ _rotr(x, 22);

  static int _bigSigma1(int x) => _rotr(x, 6) ^ _rotr(x, 11) ^ _rotr(x, 25);

  static void _expand(List<int> w, [int first = 16]) {
    for (var i = first; i < 64; i++) {
      w.add((_sigma1(w[i - 2]) + w[i - 7] + _sigma0(w[i - 15]) + w[i - 16]) &
          _u32);
    }
  }

  static List<int> _rounds(List<int> s, List<int> w, int first) {
    var a = s[0], b = s[1], c = s[2], d = s[3];
    var e = s[4], f = s[5], g = s[6], h = s[7];
    for (var i = first; i < 64; i++) {
      final k = (first == 14 && i == 14) ? _adjust : _k[i];
      final t1 =
          (h + _bigSigma1(e) + (g ^ (e & (f ^ g))) + k + w[i]) & _u32;
      final t2 = (_bigSigma0(a) + ((a & b) | (c & (a | b)))) & _u32;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _u32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _u32;
    }
    return [a, b, c, d, e, f, g, h];
  }

  static List<int> _shaInit(List<int> salt) {
    final w = List<int>.filled(14, 0, growable: true);
    w.add((salt[0] << 16) | (salt[1] << 8) | salt[2]);
    w.add((salt[3] << 24) | (salt[4] << 16) | (salt[5] << 8) | salt[6]);
    for (var i = 16; i < 30; i++) {
      var v = _scheduleSeed[i - 16];
      if (i - 2 >= 14) {
        var s = _sigma1(w[i - 2]);
        if (i == 16) s ^= _sigma1Adj;
        v += s;
      }
      if (i - 7 >= 14) v += w[i - 7];
      if (i - 15 >= 14) {
        var s = _sigma0(w[i - 15]);
        if (i == 29) s ^= _sigma0Adj;
        v += s;
      }
      w.add(v & _u32);
    }
    w.add((_sigma1(w[28]) +
            w[23] +
            _sigma0(w[15]) +
            w[14] +
            _adjust -
            _k[14]) &
        _u32);
    _expand(w, 31);
    final working = _rounds(_customState, w, 14);
    return [for (var i = 0; i < 8; i++) (_initial[i] + working[i]) & _u32];
  }

  static List<int> _shaDigest(List<int> data) {
    if (data.length < 7) throw const EdgeTtsException('签名盐长度不足');
    final length = 57 + data.length;
    final body = <int>[
      ...data.sublist(7),
      0x80,
      ...List<int>.filled((55 - length) % 64, 0),
    ];
    final bits = length * 8;
    for (var i = 7; i >= 0; i--) {
      body.add((bits >> (8 * i)) & 0xFF);
    }
    var state = _shaInit(data.sublist(0, 7));
    for (var off = 0; off < body.length; off += 64) {
      final w = <int>[];
      for (var j = 0; j < 16; j++) {
        final o = off + j * 4;
        w.add((body[o] << 24) |
            (body[o + 1] << 16) |
            (body[o + 2] << 8) |
            body[o + 3]);
      }
      _expand(w);
      final working = _rounds(state, w, 0);
      state = [for (var i = 0; i < 8; i++) (state[i] + working[i]) & _u32];
    }
    final out = <int>[];
    for (final v in state) {
      out.addAll([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
    }
    return out;
  }

  static const List<List<int>> _coef = [
    [0xE82E91B1, 0xB32700D0],
    [0x44DE24C6, 0x88DFF51D],
    [0x3BEB65BC, 0x29514038],
    [0xC89C5933, 0xB328CBDF],
    [0x8D1EC211, 0xD405B4D5],
    [0x314EF5D5, 0x26E55F3C],
    [0xE92491B1, 0x607801C6],
    [0xF0A5B9D5, 0x82B2C1FB],
    [0x06064CF3, 0xFA51A3DA],
    [0xDA79FA60, 0x207CC464],
    [0xBED20560, 0x3C3C74F3],
    [0x89F9C9F8, 0xD2D14B61],
    [0x35FA38C6, 0xBB04A2C1],
    [0xCB49E3C6, 0xC5626167],
  ];

  static String _cs64Hex(List<int> data, List<int> digest) {
    const mask = 0xFFFFFFFF;
    int u32(int v) => v & mask;
    int rol16(int v) {
      final x = v & mask;
      return ((x << 16) | (x >> 16)) & mask;
    }

    int le32(List<int> b, int o) =>
        (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) & mask;

    var keyA = le32(digest, 0) | 1;
    var keyB = le32(digest, 4) | 1;
    final factors = [u32(keyA * 0x82893933), u32(keyB * 0x82893933)];

    final terms = <int>[];
    final offsets = <int>[];
    for (var i = 0; i < _coef.length; i++) {
      terms.add(u32(_coef[i][0] * factors[i % 2]));
      offsets.add(u32(_coef[i][1]));
    }

    // 与 Java/Python 版一致：前置一个 0 字节，按小端 4 字节分组。
    final raw = <int>[0, ...data];
    final pad = (4 - raw.length % 4) % 4;
    raw.addAll(List<int>.filled(pad, 0));
    final words = <int>[];
    for (var i = 0; i < raw.length; i += 4) {
      words.add(le32(raw, i));
    }
    if (words.length.isOdd) words.add(0);

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      var term = w * (i.isEven ? keyA : keyB);
      var off = rol16(w) * (i.isEven ? 0xEF0569FB : 0xC31713DB);
      if (i == 0) {
        term += 0xF2F90B1A * factors[0];
        off += 0x0B1A0000;
      }
      terms.add(u32(term));
      offsets.add(u32(off));
    }

    var swapAcc = 0, swapLast = 0, state = 0, acc = 0;
    for (var i = 0; i + 1 < terms.length; i += 2) {
      final x = terms[i], y = terms[i + 1];
      var t = rol16(u32(offsets[i] + x));
      var q = u32(t * 0x76F50F34);
      swapAcc = u32(swapAcc + u32(rol16(q) * 0xC3EFEA97 + q));
      t = rol16(u32(offsets[i + 1] + y));
      q = u32(t * 0x1881CE3C);
      swapLast = u32(rol16(q) * 0x35BD1EC9 + q);
      swapAcc = u32(swapAcc + swapLast);

      state = u32(state * keyA + x);
      state = u32(rol16(state) * 0xCF98B111);
      state = u32(rol16(state) * 0x87085B9F);
      state = u32(rol16(state) * 0x12CEB96D);
      state = u32(rol16(state) * 0x257E1D83);
      acc = u32(acc + state);

      state = u32(state * keyB + y);
      state = u32(rol16(state) * 0xA27416F5);
      state = u32(rol16(state) * 0xD38396FF);
      state = u32(rol16(u32(rol16(state) * 0x7C932B89)) * 0xBFA49F69);
      acc = u32(acc + state);
    }

    final a = swapLast ^ state;
    final b = swapAcc ^ acc;
    final out = <int>[
      a & 0xFF, (a >> 8) & 0xFF, (a >> 16) & 0xFF, (a >> 24) & 0xFF,
      b & 0xFF, (b >> 8) & 0xFF, (b >> 16) & 0xFF, (b >> 24) & 0xFF,
    ];
    return out
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static final _rnd = Random.secure();

  static String _hex(int bytes) => List<int>.generate(bytes, (_) => _rnd.nextInt(256))
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _httpDate() {
    final t = DateTime.now().toUtc();
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String p(int v) => v.toString().padLeft(2, '0');
    return '${wd[t.weekday - 1]}, ${p(t.day)} ${mo[t.month - 1]} ${t.year} '
        '${p(t.hour)}:${p(t.minute)}:${p(t.second)} GMT';
  }
}

class EdgeTtsException implements Exception {
  final String message;
  const EdgeTtsException(this.message);
  @override
  String toString() => message;
}

/// 极简 WebSocket 客户端。
///
/// `dart:io` 的 WebSocket 在升级请求里会带 `permessage-deflate` 等扩展头，
/// 微软的朗读网关对此直接拒绝（表现为「未升级为 WebSocket」）。
/// 这里手写握手与帧编解码：只实现文本 / 二进制 / ping / close，
/// 够用且完全可控。
class _WsConn {
  _WsConn._(this._socket);

  final SecureSocket _socket;
  final List<int> _buf = [];
  final List<int> _frag = [];
  final _out = StreamController<dynamic>();
  final _rand = Random.secure();
  StreamSubscription? _sub;
  Completer<void>? _handshake;
  bool _ready = false;
  bool _closed = false;
  int _fragOp = 0;

  Stream<dynamic> get messages => _out.stream;

  static Future<_WsConn> connect(
      Uri uri, Map<String, String> headers) async {
    final socket = await SecureSocket.connect(
      uri.host,
      uri.port == 0 ? 443 : uri.port,
    );
    final conn = _WsConn._(socket);
    await conn._handshake_(uri, headers);
    return conn;
  }

  Future<void> _handshake_(
      Uri uri, Map<String, String> headers) async {
    final key = base64Encode(List<int>.generate(16, (_) => _rand.nextInt(256)));
    final sb = StringBuffer()
      ..write('GET ${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'} '
          'HTTP/1.1\r\n')
      ..write('Host: ${uri.host}\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Key: $key\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n');
    headers.forEach((k, v) => sb.write('$k: $v\r\n'));
    sb.write('\r\n');
    _socket.add(ascii.encode(sb.toString()));
    await _socket.flush();

    final hs = Completer<void>();
    _handshake = hs;
    _sub = _socket.listen(
      _onData,
      onError: (Object e) {
        if (!hs.isCompleted) hs.completeError(EdgeTtsException('连接中断：$e'));
        if (!_out.isClosed) _out.close();
      },
      onDone: () {
        if (!hs.isCompleted) {
          hs.completeError(const EdgeTtsException('连接被关闭'));
        }
        if (!_out.isClosed) _out.close();
      },
      cancelOnError: true,
    );
    await hs.future.timeout(const Duration(seconds: 12),
        onTimeout: () => throw const EdgeTtsException('等待握手超时'));
  }

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    if (!_ready) {
      final head = latin1.decode(_buf, allowInvalid: true);
      final idx = head.indexOf('\r\n\r\n');
      if (idx < 0) return;
      final first = head.split('\r\n').first;
      if (!first.contains(' 101')) {
        _closed = true;
        final c = _handshake;
        _handshake = null;
        _sub?.cancel();
        _socket.destroy();
        if (c != null && !c.isCompleted) {
          c.completeError(EdgeTtsException('微软语音拒绝连接（$first）'));
        }
        return;
      }
      _buf.removeRange(0, idx + 4);
      _ready = true;
      final c = _handshake;
      _handshake = null;
      if (c != null && !c.isCompleted) c.complete();
    }
    _drain();
  }

  void _drain() {
    while (_buf.length >= 2) {
      final b0 = _buf[0];
      final b1 = _buf[1];
      final fin = (b0 & 0x80) != 0;
      final op = b0 & 0x0F;
      final masked = (b1 & 0x80) != 0;
      var len = b1 & 0x7F;
      var off = 2;
      if (len == 126) {
        if (_buf.length < 4) return;
        len = (_buf[2] << 8) | _buf[3];
        off = 4;
      } else if (len == 127) {
        if (_buf.length < 10) return;
        var l = 0;
        for (var i = 0; i < 8; i++) {
          l = (l << 8) | _buf[2 + i];
        }
        len = l;
        off = 10;
      }
      final maskAt = off;
      if (masked) off += 4;
      if (_buf.length < off + len) return;
      final payload = _buf.sublist(off, off + len);
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= _buf[maskAt + i % 4];
        }
      }
      _buf.removeRange(0, off + len);

      switch (op) {
        case 0x1:
        case 0x2:
          if (!fin) {
            _fragOp = op;
            _frag
              ..clear()
              ..addAll(payload);
          } else {
            _emit(op, payload);
          }
          break;
        case 0x0:
          _frag.addAll(payload);
          if (fin) {
            _emit(_fragOp == 0 ? 0x2 : _fragOp, List<int>.of(_frag));
            _frag.clear();
          }
          break;
        case 0x8:
          _closed = true;
          if (!_out.isClosed) _out.close();
          _socket.destroy();
          return;
        case 0x9:
          _frame(0x8A, payload);
          break;
        default:
          break;
      }
    }
  }

  void _emit(int op, List<int> payload) {
    if (_out.isClosed) return;
    _out.add(op == 0x1
        ? utf8.decode(payload, allowMalformed: true)
        : payload);
  }

  void sendText(String text) => _frame(0x1, utf8.encode(text));

  void _frame(int op, List<int> payload) {
    if (_closed) return;
    final mask = List<int>.generate(4, (_) => _rand.nextInt(256));
    final h = <int>[0x80 | op];
    if (payload.length < 126) {
      h.add(0x80 | payload.length);
    } else if (payload.length <= 0xFFFF) {
      h
        ..add(0x80 | 126)
        ..add((payload.length >> 8) & 0xFF)
        ..add(payload.length & 0xFF);
    } else {
      h.add(0x80 | 127);
      for (var i = 7; i >= 0; i--) {
        h.add((payload.length >> (8 * i)) & 0xFF);
      }
    }
    h.addAll(mask);
    final body = List<int>.filled(payload.length, 0);
    for (var i = 0; i < payload.length; i++) {
      body[i] = payload[i] ^ mask[i % 4];
    }
    try {
      _socket.add([...h, ...body]);
    } catch (_) {
      _closed = true;
    }
  }

  Future<void> close() async {
    if (!_closed) {
      _frame(0x8, const [0x03, 0xE8]);
      _closed = true;
    }
    try {
      await _socket.flush();
      await _socket.close();
    } catch (_) {}
    await _sub?.cancel();
    if (!_out.isClosed) await _out.close();
  }
}
