import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/models.dart';
import 'cache_store.dart';

class LlmChunk {
  final String content;
  final String reasoning;
  final bool done;
  final bool cancelled;
  final String? error;

  /// 网关返回的真实 token 用量（通常在最后一个 chunk，或独立 usage chunk）。
  final TokenUsage? usage;

  const LlmChunk({
    this.content = '',
    this.reasoning = '',
    this.done = false,
    this.cancelled = false,
    this.error,
    this.usage,
  });

  bool get isEmpty =>
      content.isEmpty &&
      reasoning.isEmpty &&
      !done &&
      error == null &&
      usage == null;
}

class LlmRequest {
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<Map<String, dynamic>> messages;
  final int maxTokens;
  final double temperature;
  final double topP;
  final int thinkingBudget;
  final String reasoningEffort;
  final bool deepThinking;
  final Map<String, dynamic> extraBody;

  /// 请求网关在流式结束前返回 usage（OpenAI stream_options.include_usage）。
  /// 若网关不接受该字段，关闭设置里的「用量追踪」即可。
  final bool includeUsage;

  const LlmRequest({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.messages,
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    required this.thinkingBudget,
    required this.reasoningEffort,
    required this.deepThinking,
    this.extraBody = const {},
    this.includeUsage = true,
  });

  Map<String, dynamic> toBody({bool stream = true}) {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': topP,
      'stream': stream,
    };
    if (includeUsage && stream) {
      body['stream_options'] = const {'include_usage': true};
    }
    if (deepThinking) {
      // 兼容三类 OpenAI 格式网关：o-series / Claude 网关 / 通用 reasoning 参数。
      body['reasoning_effort'] = reasoningEffort;
      body['thinking_budget'] = thinkingBudget;
      body['thinking'] = {
        'type': 'enabled',
        'budget_tokens': thinkingBudget,
      };
    }
    body.addAll(extraBody);
    return body;
  }

  /// 本次请求是否真的携带了图片字节（用于把 400/413 错误解释清楚）。
  bool get hasImages => messages.any((m) {
        final c = m['content'];
        final inContent =
            c is List && c.any((p) => p is Map && p['type'] == 'image_url');
        final imgs = m['images'];
        return inContent || (imgs is List && imgs.isNotEmpty);
      });
}

/// 从接口拉取到的模型信息。能力标签由模型 ID 推断，仅用于 UI 提示。
class ModelInfo {
  final String id;
  final String owner;

  const ModelInfo({required this.id, this.owner = ''});

  bool get reasoning => RegExp(
        r'(^|[-_/])(o1|o3|o4|r1|qwq|reasoner|thinking|think)([-_:/.]|$)|deepseek-r|reasoning',
        caseSensitive: false,
      ).hasMatch(id);

  bool get vision => looksLikeVisionModel(id);

  /// 过滤掉嵌入 / 语音 / 绘图 / 审核等非对话模型，让下拉列表保持清爽。
  bool get isChat => !RegExp(
        r'embed|whisper|tts[-_]|dall[-_]e|image[-_]gen|moderation|rerank|bge[-_]|bce[-_]|audio|realtime|transcri|safecheck|guard|reranker',
        caseSensitive: false,
      ).hasMatch(id);

  String get tag {
    final t = <String>[];
    if (reasoning) t.add('推理');
    if (vision) t.add('视觉');
    return t.join(' · ');
  }
}

class ModelFetchResult {
  final List<ModelInfo> models;
  final String? error;

  const ModelFetchResult(this.models, {this.error});

  bool get ok => error == null && models.isNotEmpty;
}

/// OpenAI Chat Completions 兼容客户端（SSE 流式）。
class LlmClient {
  final Dio _dio;

  /// 全局默认响应缓存。圆桌会议 / 模拟人生 / 小游戏会自己 new 一个
  /// LlmClient，用静态默认值才能保证它们也走同一份缓存。
  /// 由 AppState 在启动时注入；未注入时缓存完全不生效（测试不受影响）。
  static ResponseCache? defaultCache;

  /// 命中时回调，AppState 用它把命中写进台账并刷新界面。
  static void Function(CacheHitEntry entry)? onCacheHit;

  LlmClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          followRedirects: true,
        ));

  static String endpoint(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  Stream<LlmChunk> chat(LlmRequest req, {CancelToken? cancel}) async* {
    final url = endpoint(req.baseUrl);
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (req.apiKey.isNotEmpty) 'Authorization': 'Bearer ${req.apiKey}',
    };

    Response<ResponseBody> resp;
    try {
      resp = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(req.toBody()),
        cancelToken: cancel,
        options: Options(headers: headers, responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        yield const LlmChunk(done: true, cancelled: true);
      } else {
        yield LlmChunk(error: '连接失败：${_describe(e)}');
      }
      return;
    } catch (e) {
      yield LlmChunk(error: '请求异常：$e');
      return;
    }

    final code = resp.statusCode ?? 0;
    final body = resp.data;
    if (code < 200 || code >= 300 || body == null) {
      // 错误体按字节累积后一次性解码：逐块 utf8.decode 会把跨块的汉字拆开，
      // 错误提示里就会出现替换字符。
      final bytes = <int>[];
      try {
        await for (final b in body!.stream) {
          bytes.addAll(b);
          if (bytes.length > 4000) break;
        }
      } catch (_) {}
      final detail = utf8.decode(bytes, allowMalformed: true).trim();
      final hint = req.hasImages &&
              (code == 400 || code == 413 || code == 415 || code == 422)
          ? '网关拒绝了带图片的请求。最常见原因是当前模型不支持视觉，或该中转不认内联 base64 图片。'
              '可到「设置 → 多模态」切换发送格式，或换用带视觉能力的模型。\n'
          : '';
      yield LlmChunk(
          error: '$hint'
              'HTTP $code${detail.isEmpty ? '' : ' · $detail'}');
      return;
    }

    // utf8.decoder 是有状态的 Converter，跨分包的多字节字符不会断裂。
    final textStream = utf8.decoder.bind(body.stream.cast<List<int>>());
    var lineBuf = '';
    var sawDone = false;
    var emitted = false; // 是否成功解析出过结构化事件
    var jsonMode = false; // 进入 JSON 模式后，非 JSON 片段一律不再混入正文
    final eventData = <String>[];
    final plain = StringBuffer();
    final outbox = <LlmChunk>[];

    /// 处理一个候选事件数据：能解析就产出 chunk，否则只接受可读纯文本，
    /// 协议行 / 半截 JSON / 二进制噪声全部丢弃，绝不写进回答。
    void accept(String candidate) {
      if (candidate.isEmpty) return;
      if (candidate == '[DONE]') {
        sawDone = true;
        return;
      }
      final chunk = parseSseEvent(candidate);
      if (chunk != null) {
        emitted = true;
        jsonMode = true;
        outbox.add(chunk);
        return;
      }
      if (candidate.startsWith('{')) return; // 半截 JSON 继续等拼接
      if (!jsonMode && isReadableStreamText(candidate)) plain.write(candidate);
    }

    void pushData(String v) {
      eventData.add(v);
      final joined = eventData.join('\n').trim();
      if (joined.isEmpty) return;
      if (joined == '[DONE]') {
        sawDone = true;
        eventData.clear();
        return;
      }
      // 每次收到 data 行就尝试解析：既兼容「每行一个事件」的网关，
      // 也兼容把一个 JSON 拆成多行 data 的网关（失败就继续累积）。
      final chunk = parseSseEvent(joined);
      if (chunk != null) {
        emitted = true;
        jsonMode = true;
        eventData.clear();
        outbox.add(chunk);
        return;
      }
      if (joined.startsWith('{')) {
        if (joined.length > 200000) eventData.clear();
        return;
      }
      accept(joined);
      eventData.clear();
    }

    void finishEvent() {
      if (eventData.isEmpty) return;
      final joined = eventData.join('\n').trim();
      eventData.clear();
      accept(joined);
    }

    void handleLine(String raw) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        finishEvent(); // SSE 空行 = 一个事件结束
        return;
      }
      if (line.startsWith(':')) return; // 注释 / 心跳
      if (line.startsWith('data:')) {
        pushData(line.substring(5).trimLeft());
        return;
      }
      // event:/id:/retry: 等协议行一律忽略；兼容不带 data: 前缀、直接吐裸 JSON 的网关。
      final t = line.trimLeft();
      if (t.startsWith('{')) {
        final chunk = parseSseEvent(t);
        if (chunk != null) {
          emitted = true;
          jsonMode = true;
          outbox.add(chunk);
        }
      }
    }

    try {
      await for (final text in textStream) {
        lineBuf += text;
        while (!sawDone) {
          final nl = lineBuf.indexOf('\n');
          final cr = lineBuf.indexOf('\r');
          final int cut;
          final int skip;
          if (nl >= 0 && (cr < 0 || nl < cr)) {
            cut = nl;
            skip = 1;
          } else if (cr >= 0) {
            cut = cr;
            skip = (cr + 1 < lineBuf.length && lineBuf[cr + 1] == '\n') ? 2 : 1;
          } else {
            break;
          }
          final line = lineBuf.substring(0, cut);
          lineBuf = lineBuf.substring(cut + skip);
          handleLine(line);
        }
        for (final c in outbox) {
          yield c;
        }
        outbox.clear();
        if (sawDone) break;
      }
      if (!sawDone) {
        handleLine(lineBuf); // 收尾最后一行
        finishEvent();
        lineBuf = '';
        for (final c in outbox) {
          yield c;
        }
        outbox.clear();
      }
    } catch (e) {
      final closed = e.toString().contains('Connection closed') ||
          e.toString().contains('HttpException');
      if (closed) {
        yield LlmChunk(
            error: req.hasImages
                ? '网关在传输中关闭了连接。本次请求带图片，最常见是图片请求体过大、'
                    '或该中转不支持多模态而提前断开。建议换用带视觉能力的模型、'
                    '减少/压缩图片，或在 设置 → 多模态 切到「仅文本」验证。'
                : '网关在传输中关闭了连接（Connection closed while receiving data）。'
                    '请检查 Base URL、网络与该接口是否稳定。');
      } else {
        yield LlmChunk(error: '流式读取中断：$e');
      }
      return;
    }

    if (sawDone) {
      yield const LlmChunk(done: true);
      return;
    }
    final tail = plain.toString().trim();
    if (!emitted && tail.isNotEmpty) {
      if (_looksLikeHtml(tail)) {
        yield const LlmChunk(
            error: '接口返回的不是模型数据，而是一段网页（可能是登录页、'
                '风控验证页或反向代理错误页）。请检查 Base URL 是否完整、'
                'API Key 是否有效、该地址是否要求浏览器验证。');
        return;
      }
      // 兼容忽略 stream=true、直接返回完整 JSON 或纯文本的网关。
      yield parseSseEvent(tail) ?? LlmChunk(content: tail);
      return;
    }
    yield const LlmChunk(done: true);
  }

  static bool _looksLikeHtml(String s) {
    final h = s.substring(0, s.length > 512 ? 512 : s.length).toLowerCase();
    return h.contains('<!doctype html') ||
        h.contains('<html') ||
        h.contains('<noscript') ||
        (h.contains('<body') && h.contains('<div'));
  }

  Future<String> complete(LlmRequest req, {CancelToken? cancel}) async {
    final r = await completeWithUsage(req, cancel: cancel);
    return r.text;
  }

  /// 深度研究工作流需要同时拿到正文与 token 用量。
  Future<({String text, TokenUsage? usage, bool fromCache})>
      completeWithUsage(LlmRequest req, {CancelToken? cancel}) async {
    // 只缓存「一次性完整回答」的调用。主对话走流式 chat()，不经过这里，
    // 所以用户重新问同一个问题永远拿到新回答，不会被旧答案糊弄。
    final cache = defaultCache;
    final cacheable = cache != null && cache.enabled && req.model.trim().isNotEmpty;
    final key = cacheable ? ResponseCache.keyFor(req) : null;

    if (key != null) {
      final hit = cache!.get(key);
      if (hit != null) {
        final saved = hit.usage?.total ??
            TokenUsage.estimate('', hit.text).total;
        LlmClient.onCacheHit?.call(CacheHitEntry(
          at: DateTime.now().millisecondsSinceEpoch,
          model: req.model,
          kind: CacheHitKind.response,
          tokens: saved,
          summary: ResponseCache.summaryOf(req),
        ));
        return (text: hit.text, usage: hit.usage, fromCache: true);
      }
    }

    final buf = StringBuffer();
    TokenUsage? usage;
    await for (final c in chat(req, cancel: cancel)) {
      if (c.error != null) throw StateError(c.error!);
      if (c.cancelled) throw StateError('已取消');
      buf.write(c.content);
      if (c.usage != null) usage = c.usage;
    }
    final text = buf.toString();
    // 出错 / 空回答绝不入缓存，否则一次故障会被反复复用。
    if (key != null && text.trim().isNotEmpty) {
      cache!.put(key, text, usage);
    }
    return (text: text, usage: usage, fromCache: false);
  }

  /// 把一个 SSE 事件数据解析为 chunk；解析不了返回 null
  /// （调用方决定继续拼接还是丢弃，绝不把原始片段当正文输出）。
  /// 公开以便回归测试：脏片段必须返回 null，绝不变成回答正文。
  LlmChunk? parseSseEvent(String data) {
    final s = data.trim();
    if (s.isEmpty || s == '[DONE]') return null;
    if (!s.startsWith('{') && !s.startsWith('[')) return null;
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) {
        if (v['error'] != null) {
          final e = v['error'];
          return LlmChunk(
              error: e is Map
                  ? (e['message'] ?? e.toString()).toString()
                  : e.toString());
        }
        return _fromResponseJson(v);
      }
    } catch (_) {}
    return null;
  }

  /// 只接受「看起来是正文」的纯文本，挡住协议行 / HTML / 二进制噪声。
  /// 公开以便回归测试：协议行 / HTML / 二进制噪声一律不接受。
  static bool isReadableStreamText(String s) {
    if (s.isEmpty) return false;
    final low = s.toLowerCase();
    for (final p in const [
      'event:',
      'id:',
      'retry:',
      'data:',
      'http/',
      'content-type:',
      '<!doctype',
      '<html',
      '<?xml',
    ]) {
      if (low.startsWith(p)) return false;
    }
    if (s.startsWith('{') || s.startsWith('[')) return false;
    var bad = 0;
    for (final r in s.runes) {
      if (r < 0x20 && r != 0x0A && r != 0x09) bad++;
    }
    return bad * 4 < s.length;
  }

  /// 去掉解码失败残留、BOM、零宽字符与孤立控制符 —— 流式「乱码」的最后一道闸。
  /// 公开以便回归测试：清掉解码失败残留、BOM、零宽字符与孤立控制符。
  static String cleanStreamText(String s) {
    if (s.isEmpty) return s;
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r == 0xFFFD || r == 0xFEFF) continue;
      if (r == 0x200B || r == 0x200C || r == 0x200D || r == 0x2060) continue;
      if (r < 0x20 && r != 0x0A && r != 0x09 && r != 0x0D) continue;
      if (r >= 0xD800 && r <= 0xDFFF) continue;
      b.writeCharCode(r);
    }
    return b.toString();
  }

  LlmChunk? _fromResponseJson(Map<String, dynamic> j) {
    // usage 可能出现在顶层、choices[0] 内，或 Ollama 的顶层计数字段；
    // 也可能单独出现在没有 choices 的收尾事件里，因此先解析。
    TokenUsage? usage;
    for (final src in <dynamic>[j['usage'], j['usage_metadata'], j]) {
      if (src is Map) {
        usage = TokenUsage.fromApi(src);
        if (usage != null) break;
      }
    }

    var content = '';
    var reasoning = '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final u = first['usage'];
        if (usage == null && u is Map) usage = TokenUsage.fromApi(u);
        final delta = first['delta'];
        final message = first['message'];
        final m = delta is Map
            ? delta
            : (message is Map ? message : const <String, dynamic>{});
        content = _readContent(m['content']);
        final rv =
            m['reasoning_content'] ?? m['reasoning'] ?? m['thinking'] ?? '';
        reasoning = rv is String
            ? rv
            : (rv is Map ? (rv['content'] ?? '').toString() : '');
      }
    }
    // 兼容把正文直接放在顶层的网关（Ollama /api/generate、部分中转）。
    if (content.isEmpty) {
      final top =
          j['content'] ?? j['text'] ?? j['response'] ?? j['output_text'];
      if (top != null) content = _readContent(top);
    }
    content = cleanStreamText(content);
    reasoning = cleanStreamText(reasoning);
    if (content.isEmpty && reasoning.isEmpty && usage == null) return null;
    return LlmChunk(content: content, reasoning: reasoning, usage: usage);
  }

  static String _readContent(dynamic c) {
    if (c == null) return '';
    if (c is String) return c;
    if (c is Map) {
      final v = c['text'] ?? c['content'] ?? c['value'];
      return v == null ? '' : v.toString();
    }
    if (c is List) {
      final b = StringBuffer();
      for (final p in c) {
        if (p is Map) {
          if (p['text'] != null) b.write(p['text'].toString());
        } else {
          b.write(p.toString());
        }
      }
      return b.toString();
    }
    return c.toString();
  }

  static String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查 Base URL 与网络';
      case DioExceptionType.receiveTimeout:
        return '接收超时';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.connectionError:
        return '无法建立连接';
      default:
        return e.message ?? e.type.name;
    }
  }

  // ------------------------------------------------------------ 模型列表

  /// 从用户填写的 Base URL 推导 /models 候选地址。
  /// 兼容：以 /v1 结尾、以 /chat/completions 结尾、裸根地址（补 /v1）、
  /// 以及 Ollama 原生 /api/tags。
  static List<String> modelEndpoints(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    const chat = '/chat/completions';
    if (b.endsWith(chat)) {
      b = b.substring(0, b.length - chat.length);
      while (b.endsWith('/')) {
        b = b.substring(0, b.length - 1);
      }
    }
    final out = <String>[];
    void add(String u) {
      if (!out.contains(u)) out.add(u);
    }

    add('$b/models');
    final hasVersion =
        RegExp(r'/v\d+[a-z0-9]*$', caseSensitive: false).hasMatch(b);
    if (!hasVersion) add('$b/v1/models');
    final root = hasVersion ? b.substring(0, b.lastIndexOf('/')) : b;
    add('$root/api/tags');
    return out;
  }

  static String modelsEndpoint(String baseUrl) => modelEndpoints(baseUrl).first;

  /// 自动拉取当前接口可用模型。逐个尝试候选地址，任一成功即返回。
  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
    CancelToken? cancel,
  }) async {
    if (baseUrl.trim().isEmpty) {
      return const ModelFetchResult([], error: '请先填写 API Base URL');
    }
    final key = apiKey.trim();
    String? last;
    for (final url in modelEndpoints(baseUrl)) {
      try {
        final resp = await _dio.get<dynamic>(
          url,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.json,
            headers: <String, dynamic>{
              'Accept': 'application/json',
              if (key.isNotEmpty) 'Authorization': 'Bearer $key',
            },
            validateStatus: (_) => true,
          ),
        );
        final code = resp.statusCode ?? 0;
        if (code < 200 || code >= 300) {
          last = code == 401 || code == 403
              ? 'HTTP $code · 凭据无效或该接口需要授权'
              : 'HTTP $code';
          // 认证错误换地址也没用，直接结束；404 则继续尝试下一个候选。
          if (code == 401 || code == 403) break;
          continue;
        }
        final list = _parseModels(resp.data);
        if (list.isNotEmpty) return ModelFetchResult(list);
        last = '接口未返回可用模型';
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          return const ModelFetchResult([], error: '已取消');
        }
        last = _describe(e);
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          break;
        }
      } catch (e) {
        last = '解析失败：$e';
      }
    }
    return ModelFetchResult(const [], error: last ?? '未能获取模型列表');
  }

  /// 兼容 OpenAI {"data":[{"id":...}]}、Ollama {"models":[{"name":...}]}、
  /// 纯数组 ["model-a"] 以及 {"results":[...]} 等变体。
  static List<ModelInfo> _parseModels(dynamic data) {
    dynamic v = data;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    List<dynamic>? raw;
    if (v is List) {
      raw = v;
    } else if (v is Map) {
      for (final k in const ['data', 'models', 'results', 'items']) {
        if (v[k] is List) {
          raw = v[k] as List<dynamic>;
          break;
        }
      }
    }
    if (raw == null) return const [];

    final out = <ModelInfo>[];
    final seen = <String>{};
    for (final e in raw) {
      String id = '';
      String owner = '';
      if (e is String) {
        id = e;
      } else if (e is Map) {
        for (final k in const ['id', 'name', 'model', 'model_name', 'slug']) {
          if (e[k] != null) {
            id = e[k].toString();
            break;
          }
        }
        final details = e['details'];
        owner = (e['owned_by'] ??
                e['owner'] ??
                (details is Map ? details['family'] : null) ??
                '')
            .toString();
      }
      id = id.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(ModelInfo(id: id, owner: owner));
    }
    return out;
  }
}
