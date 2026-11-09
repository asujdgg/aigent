import 'dart:convert';

import 'package:dio/dio.dart';

/// 一个模型公开报价，单位统一为「美元 / 每百万 token」。
class ModelPrice {
  final String id;
  final double inputPerM;
  final double outputPerM;

  /// 命中服务端提示词缓存时的输入单价；没有单列报价时按输入价的一半估。
  final double cachedPerM;

  const ModelPrice({
    required this.id,
    required this.inputPerM,
    required this.outputPerM,
    this.cachedPerM = 0,
  });

  bool get valid => inputPerM > 0 || outputPerM > 0;

  double get effectiveCachedPerM =>
      cachedPerM > 0 ? cachedPerM : inputPerM * 0.5;

  Map<String, dynamic> toJson() => {
        'id': id,
        'in': inputPerM,
        'out': outputPerM,
        'cached': cachedPerM,
      };

  factory ModelPrice.fromJson(Map<dynamic, dynamic> j) => ModelPrice(
        id: (j['id'] ?? '').toString(),
        inputPerM: (j['in'] as num?)?.toDouble() ?? 0,
        outputPerM: (j['out'] as num?)?.toDouble() ?? 0,
        cachedPerM: (j['cached'] as num?)?.toDouble() ?? 0,
      );
}

class PriceFetchResult {
  final Map<String, ModelPrice> prices;
  final String source;
  final String error;

  const PriceFetchResult({
    required this.prices,
    required this.source,
    this.error = '',
  });

  bool get ok => prices.isNotEmpty;
  int get count => prices.length;
}

/// 实时价格表。
///
/// 说明：OpenAI / Anthropic 等官方接口并没有「按调用返回单价」的公开端点，
/// 账单查询需要单独的 Admin Key，客户端不该持有。这里改从两份**公开费率表**
/// 拉价（LiteLLM 维护的 model_prices 与 OpenRouter 的 /models），按当前模型名
/// 匹配单价，再乘以本地已经记下的真实 token 数得出估算费用。
/// 估算值只用于自查，正式账单以服务商后台为准。
class PriceCatalog {
  PriceCatalog({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 12),
              validateStatus: (_) => true,
            ));

  final Dio _dio;

  static const String kLiteLlm =
      'https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json';
  static const String kOpenRouter = 'https://openrouter.ai/api/v1/models';

  /// 主源失败自动回落备源，两个都失败返回带 error 的空结果，不抛异常。
  Future<PriceFetchResult> refresh() async {
    final errors = <String>[];
    final lite = await _get(kLiteLlm);
    if (lite != null) {
      final m = parseLiteLlm(lite);
      if (m.isNotEmpty) return PriceFetchResult(prices: m, source: 'LiteLLM');
    } else {
      errors.add('LiteLLM 价格表');
    }
    final or = await _get(kOpenRouter);
    if (or != null) {
      final m = parseOpenRouter(or);
      if (m.isNotEmpty) return PriceFetchResult(prices: m, source: 'OpenRouter');
    } else {
      errors.add('OpenRouter');
    }
    return PriceFetchResult(
      prices: const {},
      source: '',
      error: errors.isEmpty ? '价格表为空' : '${errors.join(' / ')} 均不可用',
    );
  }

  Future<dynamic> _get(String url) async {
    try {
      final r = await _dio.get<dynamic>(url);
      if ((r.statusCode ?? 0) < 200 || (r.statusCode ?? 0) >= 300) return null;
      final d = r.data;
      if (d is String) return jsonDecode(d);
      return d;
    } catch (_) {
      return null;
    }
  }

  /// LiteLLM：{"gpt-4o": {"input_cost_per_token": 2.5e-6, ...}}
  /// 单价是「美元 / token」，乘 1e6 换算成「美元 / 百万 token」。
  static Map<String, ModelPrice> parseLiteLlm(dynamic data) {
    if (data is! Map) return const {};
    final out = <String, ModelPrice>{};
    data.forEach((key, value) {
      if (key == 'sample_spec' || value is! Map) return;
      final id = key.toString().trim().toLowerCase();
      if (id.isEmpty) return;
      final i = _num(value['input_cost_per_token']) * 1000000;
      final o = _num(value['output_cost_per_token']) * 1000000;
      final c = _num(value['cache_read_input_token_cost']) * 1000000;
      if (i <= 0 && o <= 0) return;
      final p = ModelPrice(id: id, inputPerM: i, outputPerM: o, cachedPerM: c);
      _put(out, id, p);
    });
    return out;
  }

  /// OpenRouter：{"data":[{"id":"openai/gpt-4o","pricing":{"prompt":"0.0000025",...}}]}
  static Map<String, ModelPrice> parseOpenRouter(dynamic data) {
    final list = data is Map ? data['data'] : null;
    if (list is! List) return const {};
    final out = <String, ModelPrice>{};
    for (final e in list) {
      if (e is! Map) continue;
      final id = (e['id'] ?? '').toString().trim().toLowerCase();
      final pr = e['pricing'];
      if (id.isEmpty || pr is! Map) continue;
      final i = _num(pr['prompt']) * 1000000;
      final o = _num(pr['completion']) * 1000000;
      final c = _num(pr['input_cache_read']) * 1000000;
      if (i <= 0 && o <= 0) continue;
      _put(out, id,
          ModelPrice(id: id, inputPerM: i, outputPerM: o, cachedPerM: c));
    }
    return out;
  }

  /// 同一个模型同时以完整 id 和去掉供应商前缀的短名登记，
  /// 这样 `openai/gpt-4o` 和 `gpt-4o` 都能查到。
  static void _put(Map<String, ModelPrice> out, String id, ModelPrice p) {
    out[id] = p;
    if (id.contains('/')) {
      final short = id.split('/').last;
      if (short.isNotEmpty) out.putIfAbsent(short, () => p);
    }
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  /// 按模型名找单价：精确 → 去供应商前缀 → 去日期 / 版本后缀 → 最长前缀。
  /// 网关常给 `gpt-4o-2024-08-06`、`claude-sonnet-4-5-20250929` 这类带版本
  /// 的名字，精确匹配会落空，所以必须做归一化。
  static ModelPrice? lookup(Map<String, ModelPrice> table, String model) {
    var m = model.trim().toLowerCase();
    if (m.isEmpty || table.isEmpty) return null;
    final direct = table[m];
    if (direct != null) return direct;
    if (m.contains('/')) m = m.split('/').last;
    final short = table[m];
    if (short != null) return short;

    final base = m
        // gpt-4o-2024-08-06 / claude-...-20250929 / qwen-20250101
        .replaceAll(RegExp(r'[-_]?20\d{2}-?\d{2}-?\d{2}$'), '')
        .replaceAll(RegExp(r'[-_:](latest|preview)$'), '')
        .replaceAll(RegExp(r'[-_]v\d+(\.\d+)?$'), '');
    if (base != m) {
      final hit = table[base];
      if (hit != null) return hit;
    }

    ModelPrice? best;
    var bestLen = 0;
    for (final e in table.entries) {
      final k = e.key.contains('/') ? e.key.split('/').last : e.key;
      if (k.length > bestLen && m.startsWith(k) && k.length >= 3) {
        best = e.value;
        bestLen = k.length;
      }
    }
    return best;
  }

  /// 美元 → 人民币。
  static double toCny(double usd, double rate) => usd * rate;

  /// 按单价算一次请求的钱（¥）。
  static double costOf({
    required int prompt,
    required int completion,
    required double inputPerM,
    required double outputPerM,
    double cachedTokens = 0,
    double cachedPerM = 0,
    double usdToCny = 1,
  }) {
    final p = (prompt - cachedTokens).toDouble();
    final cached = cachedTokens.clamp(0, prompt.toDouble()).toDouble();
    final usd = p / 1000000 * inputPerM +
        completion / 1000000 * outputPerM +
        cached / 1000000 * cachedPerM;
    return usd * usdToCny;
  }
}
