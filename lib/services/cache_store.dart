import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'llm_client.dart' show LlmRequest;

/// 「命中缓存」的两类来源。
///
/// - `prompt`：服务端提示词缓存（OpenAI `prompt_tokens_details.cached_tokens`、
///   Anthropic `cache_read_input_tokens` 等）。请求照常发出，但命中的输入
///   token 按折扣计价，是真实省下的钱。
/// - `response`：本地响应复用。完全相同的请求（同地址、同模型、同消息、
///   同采样参数）在有效期内直接返回上次的回答，**不再发起网络请求**。
///   主对话是流式 `chat()`，不走这条路径，所以正常聊天永远拿到新回答；
///   受益的是圆桌会议、模拟人生、小游戏、深度研究这类重复度高的内部调用。
enum CacheHitKind { prompt, response }

class CacheHitEntry {
  final int at;
  final String model;
  final CacheHitKind kind;
  final int tokens;
  final String summary;

  const CacheHitEntry({
    required this.at,
    required this.model,
    required this.kind,
    required this.tokens,
    this.summary = '',
  });

  String get kindId => kind == CacheHitKind.prompt ? 'prompt' : 'response';

  Map<String, dynamic> toJson() => {
        'at': at,
        'model': model,
        'kind': kindId,
        'tokens': tokens,
        if (summary.isNotEmpty) 'summary': summary,
      };

  factory CacheHitEntry.fromJson(Map<dynamic, dynamic> j) => CacheHitEntry(
        at: (j['at'] as num?)?.toInt() ?? 0,
        model: (j['model'] ?? '').toString(),
        kind: j['kind'] == 'prompt'
            ? CacheHitKind.prompt
            : CacheHitKind.response,
        tokens: (j['tokens'] as num?)?.toInt() ?? 0,
        summary: (j['summary'] ?? '').toString(),
      );
}

/// 命中台账。累计数字与最近记录分开存，记录只留最新 200 条，
/// 避免长期使用后 JSON 无限膨胀。
class CacheLedger {
  CacheLedger();

  static const int maxRecords = 200;

  int promptHits = 0;
  int responseHits = 0;
  int promptTokens = 0;
  int responseTokens = 0;
  final List<CacheHitEntry> records = [];

  int get hits => promptHits + responseHits;
  int get tokens => promptTokens + responseTokens;

  /// 按模型汇总的命中 token，供查看页分组展示。
  Map<String, int> get byModel {
    final m = <String, int>{};
    for (final r in records) {
      m[r.model] = (m[r.model] ?? 0) + r.tokens;
    }
    return m;
  }

  void add(CacheHitEntry e) {
    records.insert(0, e);
    if (records.length > maxRecords) records.removeRange(maxRecords, records.length);
    if (e.kind == CacheHitKind.prompt) {
      promptHits++;
      promptTokens += e.tokens;
    } else {
      responseHits++;
      responseTokens += e.tokens;
    }
  }

  void clear() {
    promptHits = 0;
    responseHits = 0;
    promptTokens = 0;
    responseTokens = 0;
    records.clear();
  }

  Map<String, dynamic> toJson() => {
        'promptHits': promptHits,
        'responseHits': responseHits,
        'promptTokens': promptTokens,
        'responseTokens': responseTokens,
        'records': [for (final r in records) r.toJson()],
      };

  factory CacheLedger.fromJson(Map<dynamic, dynamic> j) {
    final l = CacheLedger();
    l.promptHits = (j['promptHits'] as num?)?.toInt() ?? 0;
    l.responseHits = (j['responseHits'] as num?)?.toInt() ?? 0;
    l.promptTokens = (j['promptTokens'] as num?)?.toInt() ?? 0;
    l.responseTokens = (j['responseTokens'] as num?)?.toInt() ?? 0;
    final r = j['records'];
    if (r is List) {
      for (final e in r) {
        if (e is Map) l.records.add(CacheHitEntry.fromJson(e));
      }
      if (l.records.length > maxRecords) {
        l.records.removeRange(maxRecords, l.records.length);
      }
    }
    return l;
  }
}

class CachedAnswer {
  final String text;
  final TokenUsage? usage;
  final int at;

  const CachedAnswer({required this.text, this.usage, required this.at});

  Map<String, dynamic> toJson() => {
        'text': text,
        'at': at,
        if (usage != null) 'usage': usage!.toJson(),
      };

  factory CachedAnswer.fromJson(Map<dynamic, dynamic> j) => CachedAnswer(
        text: (j['text'] ?? '').toString(),
        at: (j['at'] as num?)?.toInt() ?? 0,
        usage: j['usage'] is Map
            ? TokenUsage.fromJson(Map<dynamic, dynamic>.from(j['usage'] as Map))
            : null,
      );
}

/// 本地响应缓存。纯 Dart 数据结构，持久化交给 [CacheStore]，方便单测。
class ResponseCache {
  ResponseCache({this.enabled = true, this.maxEntries = 120})
      : _entries = <String, CachedAnswer>{};

  bool enabled;
  final int maxEntries;

  /// 命中有效期：6 小时。过期的回答会被丢弃，不会把上周的结论端出来。
  static const int ttlMs = 6 * 60 * 60 * 1000;

  final Map<String, CachedAnswer> _entries;
  int hitCount = 0;

  int get size => _entries.length;

  /// 稳定哈希（FNV-1a 64 位）。不用 `String.hashCode`：它只在单个进程内
  /// 稳定，而缓存要落盘、重启后继续命中。
  static String keyFor(LlmRequest req) {
    String payload;
    try {
      payload = jsonEncode([
        req.baseUrl.trim(),
        req.model.trim(),
        req.messages,
        req.temperature,
        req.topP,
        req.maxTokens,
        req.reasoningEffort,
        req.deepThinking,
        req.thinkingBudget,
      ]);
    } catch (_) {
      // 消息里偶尔会塞进不可序列化的对象，此时退化为「不可能命中」的 key，
      // 让请求照常发出，绝不因为缓存逻辑把功能弄坏。
      payload = 'unserializable:${DateTime.now().microsecondsSinceEpoch}';
    }
    var h = 0x23d25b;
    for (final unit in payload.codeUnits) {
      h ^= unit;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'c${h.toRadixString(16)}';
  }

  /// 取最后一条用户消息做展示摘要，避免把整段 System Prompt 塞进记录。
  static String summaryOf(LlmRequest req) {
    for (final m in req.messages.reversed) {
      if (m['role'] == 'user') {
        final s = (m['content'] ?? '').toString().replaceAll('\n', ' ').trim();
        return s.length > 46 ? '${s.substring(0, 46)}…' : s;
      }
    }
    return '';
  }

  CachedAnswer? get(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final v = _entries[key];
    if (v == null) return null;
    if (v.text.trim().isEmpty || now - v.at > ttlMs) {
      _entries.remove(key);
      return null;
    }
    hitCount++;
    return v;
  }

  void put(String key, String text, TokenUsage? usage) {
    if (text.trim().isEmpty || text.length > 60000) return;
    _entries[key] = CachedAnswer(
        text: text, usage: usage, at: DateTime.now().millisecondsSinceEpoch);
    if (_entries.length > maxEntries) {
      // 简单 LRU 近似：按写入时间淘汰最旧的一半。
      final sorted = _entries.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in sorted.take(_entries.length - maxEntries)) {
        _entries.remove(e.key);
      }
    }
  }

  void clear() {
    _entries.clear();
    hitCount = 0;
  }

  Map<String, dynamic> toJson() => {
        'hitCount': hitCount,
        'entries': {
          for (final e in _entries.entries) e.key: e.value.toJson(),
        },
      };

  void load(Map<dynamic, dynamic> j) {
    hitCount = (j['hitCount'] as num?)?.toInt() ?? 0;
    final e = j['entries'];
    if (e is Map) {
      e.forEach((k, v) {
        if (v is Map) {
          _entries[k.toString()] =
              CachedAnswer.fromJson(Map<dynamic, dynamic>.from(v));
        }
      });
    }
  }
}

/// 命中台账与响应缓存的落盘。和会话历史分开：历史可能有几 MB，
/// 这里只有几十 KB，用 SharedPreferences 原子写入即可。
class CacheStore {
  CacheStore({Map<String, String>? memory}) : _memory = memory;

  final Map<String, String>? _memory;
  static const String kLedger = 'cache.ledger.v1';
  static const String kResponses = 'cache.responses.v1';

  Future<String?> _read(String key) async {
    final m = _memory;
    if (m != null) return m[key];
    return (await SharedPreferences.getInstance()).getString(key);
  }

  Future<void> _write(String key, String value) async {
    final m = _memory;
    if (m != null) {
      m[key] = value;
      return;
    }
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  Future<void> load(CacheLedger ledger, ResponseCache cache) async {
    try {
      final l = await _read(kLedger);
      if (l != null && l.isNotEmpty) {
        final v = jsonDecode(l);
        if (v is Map) {
          final loaded = CacheLedger.fromJson(Map<dynamic, dynamic>.from(v));
          ledger.promptHits = loaded.promptHits;
          ledger.responseHits = loaded.responseHits;
          ledger.promptTokens = loaded.promptTokens;
          ledger.responseTokens = loaded.responseTokens;
          ledger.records
            ..clear()
            ..addAll(loaded.records);
        }
      }
      final r = await _read(kResponses);
      if (r != null && r.isNotEmpty) {
        final v = jsonDecode(r);
        if (v is Map) cache.load(Map<dynamic, dynamic>.from(v));
      }
    } catch (_) {
      // 存档损坏就当空，不让页面起不来。
    }
  }

  Future<void> save(CacheLedger ledger, ResponseCache cache) async {
    await _write(kLedger, jsonEncode(ledger.toJson()));
    await _write(kResponses, jsonEncode(cache.toJson()));
  }

  Future<void> clear() async {
    await _write(kLedger, '{}');
    await _write(kResponses, '{}');
  }
}
