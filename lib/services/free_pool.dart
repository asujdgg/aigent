import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'relay_catalog.dart';

/// 免密来源的类型。公开源由第三方维护，本地源是用户自己的机器。
enum FreeKind { publicSource, local }

/// 一个无需密钥的 OpenAI 兼容端点。
class FreeEndpoint {
  final String id;
  final String name;

  /// 提供方，用于把同一家的多个模型收在一起显示。
  final String provider;
  final String baseUrl;
  final String model;
  final FreeKind kind;
  final String note;
  final bool vision;
  final List<String> fallbackModels;

  const FreeEndpoint({
    required this.id,
    required this.name,
    this.provider = '',
    required this.baseUrl,
    required this.model,
    this.kind = FreeKind.publicSource,
    this.note = '',
    this.vision = false,
    this.fallbackModels = const [],
  });

  String get providerLabel => provider.isEmpty ? name : provider;

  FreeEndpoint copyWith({String? model, String? name}) => FreeEndpoint(
        id: id,
        name: name ?? this.name,
        provider: provider,
        baseUrl: baseUrl,
        model: model ?? this.model,
        kind: kind,
        note: note,
        vision: vision,
        fallbackModels: fallbackModels,
      );
}

/// 内置的公开免密钥端点。
///
/// 只放**当天实测能对话**的源。判断标准是一次 1 token 的真实请求，
/// 不是 `/models` 是否返回 200。2026-11 实测可用的只有四家：
/// Pollinations、OVH AI Endpoints、Kilo Gateway、LLM7（时好时坏）。
/// 之前列过的 g4f.space 要 cake credits、api.airforce 要订阅，
/// 都已删除，免得检测结果全红。
const List<FreeEndpoint> kFreeEndpoints = [
  // ---------------------------------------------------------- Pollinations
  FreeEndpoint(
    id: 'pollinations-fast',
    name: 'Pollinations · Fast',
    provider: 'Pollinations',
    baseUrl: 'https://text.pollinations.ai/openai',
    model: 'openai-fast',
    note: '匿名通道，无需注册；单 IP 同时只能跑一个请求',
    fallbackModels: ['openai'],
  ),
  FreeEndpoint(
    id: 'pollinations-openai',
    name: 'Pollinations · OpenAI',
    provider: 'Pollinations',
    baseUrl: 'https://text.pollinations.ai/openai',
    model: 'openai',
    note: '同一入口的标准档，响应比 fast 慢一些，偶发 402 重试即可',
  ),

  // ---------------------------------------------------------- OVH AI
  FreeEndpoint(
    id: 'ovh-qwen397',
    name: 'OVH · Qwen3.5 397B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Qwen3.5-397B-A17B',
    note: '匿名可用，每个模型每分钟 2 次；大模型里最稳的一个',
    fallbackModels: ['Qwen3.5-9B'],
  ),
  FreeEndpoint(
    id: 'ovh-gptoss120',
    name: 'OVH · GPT-OSS 120B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'gpt-oss-120b',
    note: '匿名可用，带推理过程；每分钟 2 次',
    fallbackModels: ['gpt-oss-20b'],
  ),
  FreeEndpoint(
    id: 'ovh-qwen9',
    name: 'OVH · Qwen3.5 9B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Qwen3.5-9B',
    note: '小模型响应快，适合当默认问答',
    fallbackModels: ['Qwen3.6-27B'],
  ),
  FreeEndpoint(
    id: 'ovh-qwen38',
    name: 'OVH · Qwen3.8 27B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Qwen3.8-27B',
    note: '匿名可用，中文与代码都均衡；每分钟 2 次',
    fallbackModels: ['Qwen3.6-27B', 'Qwen3.5-9B'],
  ),
  FreeEndpoint(
    id: 'ovh-qwen36',
    name: 'OVH · Qwen3.6 27B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Qwen3.6-27B',
    note: '比 3.8 慢一点，长文更稳；每分钟 2 次',
  ),
  FreeEndpoint(
    id: 'ovh-mistral',
    name: 'OVH · Mistral Small 3.2',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Mistral-Small-3.2-24B-Instruct-2506',
    note: '欧洲模型，英文与法语最顺，中文够用',
  ),
  FreeEndpoint(
    id: 'ovh-llama70',
    name: 'OVH · Llama 3.3 70B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Meta-Llama-3_3-70B-Instruct',
    note: '英文最顺，中文一般；每分钟 2 次',
  ),
  FreeEndpoint(
    id: 'ovh-vl',
    name: 'OVH · Qwen2.5-VL 72B',
    provider: 'OVH AI',
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    model: 'Qwen2.5-VL-72B-Instruct',
    note: '能读图，匿名通道里少见的视觉模型',
    vision: true,
    fallbackModels: ['Qwen3.5-9B'],
  ),

  // ---------------------------------------------------------- Kilo
  FreeEndpoint(
    id: 'kilo-auto',
    name: 'Kilo · Auto Free',
    provider: 'Kilo',
    baseUrl: 'https://kilo.ai/api/gateway/v1',
    model: 'kilo-auto/free',
    note: '自动路由到免费模型，约每小时 200 次；不需要登录',
    fallbackModels: ['nvidia/nemotron-3.5-super-vl:free'],
  ),
  FreeEndpoint(
    id: 'kilo-nemotron',
    name: 'Kilo · Nemotron VL',
    provider: 'Kilo',
    baseUrl: 'https://kilo.ai/api/gateway/v1',
    model: 'nvidia/nemotron-3.5-super-vl:free',
    note: '免费视觉档，图片理解可用',
    vision: true,
  ),

  FreeEndpoint(
    id: 'kilo-beam',
    name: 'Kilo · Beam Free',
    provider: 'Kilo',
    baseUrl: 'https://kilo.ai/api/gateway/v1',
    model: 'reflection/beam-free',
    note: '免费档，实测可直连；上下文比 auto 长',
  ),

  // ---------------------------------------------------------- LLM7
  FreeEndpoint(
    id: 'llm7-deepseek',
    name: 'LLM7 · DeepSeek V4 Flash',
    provider: 'LLM7',
    baseUrl: 'https://api.llm7.io/v1',
    model: 'deepseek-v4-flash:0731',
    note: '免注册按日额度；高峰会回 429，过几分钟再试',
  ),
  FreeEndpoint(
    id: 'llm7-qwen',
    name: 'LLM7 · Qwen Turbo',
    provider: 'LLM7',
    baseUrl: 'https://api.llm7.io/v1',
    model: 'qwen3.5-turbo',
    note: '同入口的轻量档，响应快，适合短问答',
  ),
];

/// 一次探测的结果。
class FreeHit {
  final FreeEndpoint endpoint;
  final bool ok;
  final int latencyMs;
  final List<String> models;
  final String error;
  final int status;

  const FreeHit({
    required this.endpoint,
    required this.ok,
    required this.latencyMs,
    this.models = const [],
    this.error = '',
    this.status = 0,
  });

  String get name => endpoint.name;
  String get baseUrl => endpoint.baseUrl;
  String get provider => endpoint.providerLabel;
  bool get vision => endpoint.vision;

  /// 可用于接入的模型列表：成功时第一个一定是探测通过的那个。
  List<String> get usableModels => models.isEmpty ? [endpoint.model] : models;
}

class _ChatResult {
  final bool ok;
  final int status;
  final String body;
  const _ChatResult(this.ok, this.status, this.body);
}

/// 免密模型探测。
///
/// 只看 `/models` 是不可靠的：很多公开网关会返回完整模型列表，但真正
/// 发起对话时回 402（要额度）、429（要等）或 401（要 Key）。所以这里
/// 以「一次 1 token 的真实对话」作为唯一判定标准。
class FreePool {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
    followRedirects: true,
  ));

  static String _trim(String s) {
    var b = s.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) {
      b = b.substring(0, b.length - '/chat/completions'.length);
    }
    return b;
  }

  /// 把 HTTP 状态码翻译成用户能判断下一步的短句。
  static String explain(int status, String body) {
    final b = body.toLowerCase();
    if (status == 0) {
      return b.contains('timeout') ? '超时未响应' : '域名不可达';
    }
    if (status == 401) return '需要密钥（401）';
    if (status == 403) return '拒绝访问（403），可能地区受限';
    if (status == 402) return '需要订阅或额度（402）';
    if (status == 404) return '路径不对（404）';
    if (status == 408) return '对方超时（408）';
    if (status == 429) return '限流或当日额度用尽（429）';
    if (status >= 500) return '对方服务异常（$status）';
    return 'HTTP $status';
  }

  /// 判断返回体是不是一段真的对话结果，避免把网关的 200 错误页当成功。
  static bool looksLikeCompletion(String body) {
    final b = body.trim();
    if (b.isEmpty) return false;
    if (!b.contains('"choices"') && !b.contains('"content"')) return false;
    if (b.contains('"error"') && !b.contains('"choices"')) return false;
    return true;
  }

  static Future<_ChatResult> _chat(
      String base, String model, String key) async {
    final sw = Stopwatch()..start();
    try {
      final resp = await _dio.post<String>(
        '$base/chat/completions',
        data: '{"model":"$model","messages":[{"role":"user","content":"hi"}],'
            '"max_tokens":1,"stream":false}',
        options: Options(
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}',
          },
        ),
      );
      sw.stop();
      final code = resp.statusCode ?? 0;
      final body = resp.data ?? '';
      if (code == 200 && looksLikeCompletion(body)) {
        return _ChatResult(true, code, body);
      }
      return _ChatResult(false, code, body);
    } on DioException catch (e) {
      sw.stop();
      final timeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return _ChatResult(false, 0, timeout ? 'timeout' : 'unreachable');
    } catch (e) {
      sw.stop();
      return _ChatResult(false, 0, e.toString());
    }
  }

  /// 探测单个来源。成功时会把 `/models` 里的模型一并带回。
  static Future<FreeHit> probe(FreeEndpoint e, {String key = ''}) async {
    final sw = Stopwatch()..start();
    final base = _trim(e.baseUrl);
    var listed = const <String>[];

    // 模型列表只是加分项，失败不阻断对话探测。
    // 有的端点把清单挂在父路径上（text.pollinations.ai/openai → /models）。
    final modelUrls = <String>['$base/models'];
    if (base.endsWith('/openai')) {
      modelUrls
          .add('${base.substring(0, base.length - '/openai'.length)}/models');
    }
    for (final u in modelUrls) {
      try {
        final r = await _dio.get<String>(
          u,
          options: Options(headers: <String, dynamic>{
            'Accept': 'application/json',
            if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}',
          }, receiveTimeout: const Duration(seconds: 8)),
        );
        if ((r.statusCode ?? 0) == 200) {
          final list = RelayProbe.parseModels(r.data);
          if (list.isNotEmpty) {
            listed = list;
            break;
          }
        }
      } catch (_) {}
    }

    final candidates = <String>[];
    void add(String m) {
      final v = m.trim();
      if (v.isNotEmpty && !candidates.contains(v)) candidates.add(v);
    }

    add(e.model);
    for (final m in e.fallbackModels) {
      add(m);
    }
    for (final m in listed.take(4)) {
      add(m);
    }
    if (candidates.isEmpty) add('gpt-3.5-turbo');

    String? okModel;
    var lastStatus = 0;
    var lastBody = '';
    // 最多试两个模型，避免一个来源就拖掉一分钟。
    for (final m in candidates.take(2)) {
      final r = await _chat(base, m, key);
      lastStatus = r.status;
      lastBody = r.body;
      if (r.ok) {
        okModel = m;
        break;
      }
      // 认证 / 额度类错误换模型也没用，直接收手。
      if (r.status == 401 || r.status == 402 || r.status == 403) break;
    }

    sw.stop();
    if (okModel != null) {
      final models = <String>[okModel];
      for (final m in listed) {
        if (!models.contains(m)) models.add(m);
      }
      return FreeHit(
        endpoint: e,
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
        models: models.take(12).toList(),
      );
    }
    return FreeHit(
      endpoint: e,
      ok: false,
      latencyMs: sw.elapsedMilliseconds,
      status: lastStatus,
      error: lastStatus == 200
          ? '返回的不是对话结果，可能被网关拦截'
          : explain(lastStatus, lastBody),
    );
  }

  /// 并发探测，默认 6 路。十几条源分两批跑完，比 3 路快一倍；
  /// 公开源本身有按 IP 的并发限制，再高就容易自己把自己限流。
  static Future<List<FreeHit>> probeAll({
    required List<FreeEndpoint> endpoints,
    String key = '',
    int concurrency = 6,
    ValueChanged<double>? onProgress,
  }) async {
    final hits = <FreeHit>[];
    if (endpoints.isEmpty) {
      onProgress?.call(1);
      return hits;
    }
    var done = 0;
    for (var i = 0; i < endpoints.length; i += concurrency) {
      final chunk = endpoints.skip(i).take(concurrency).toList();
      final part = await Future.wait(chunk.map((e) => probe(e, key: key)));
      hits.addAll(part);
      done += chunk.length;
      onProgress?.call(done / endpoints.length);
    }
    // 可用的排前面，其次按延迟。
    hits.sort((a, b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });
    return hits;
  }

  /// 一键接入用的「最优源」：延迟最低的可用项。
  static FreeHit? fastest(List<FreeHit> hits) {
    FreeHit? best;
    for (final h in hits) {
      if (!h.ok) continue;
      if (best == null || h.latencyMs < best.latencyMs) best = h;
    }
    return best;
  }

  /// 从已有连接里挑出「本机 / 内网 + 没填 Key」的，并入免密池。
  /// 这样用户自己跑的 g4f、Ollama 不必再手动录一遍。
  static List<FreeEndpoint> localFromProfiles(List<ApiProfile> profiles) {
    final out = <FreeEndpoint>[];
    for (final p in profiles) {
      if (p.apiKey.trim().isNotEmpty) continue;
      final host = p.hostLabel;
      final localish =
          RelayProbe.isLoopback(host) || RelayProbe.isPrivateHost(host);
      if (!localish) continue;
      if (p.baseUrl.trim().isEmpty) continue;
      out.add(FreeEndpoint(
        id: 'local_${p.id}',
        name: p.name.isEmpty ? '本机服务' : p.name,
        provider: '本机 / 内网',
        baseUrl: p.baseUrl,
        model: p.model.isEmpty
            ? (p.cachedModels.isNotEmpty
                ? p.cachedModels.first
                : 'gpt-3.5-turbo')
            : p.model,
        kind: FreeKind.local,
        note: '来自你的连接配置',
        fallbackModels: p.cachedModels.take(3).toList(),
      ));
    }
    return out;
  }
}
