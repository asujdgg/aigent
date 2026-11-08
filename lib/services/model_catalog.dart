import 'llm_client.dart';

/// 一个连接配置（运营商）下缓存到的模型列表。
/// 聚合时**不在跨配置层面去重**：同一个模型 ID 在两家运营商下各占一条，
/// 关键词命中时才能把「同样的模型、不同运营商」一次性列出来对比选择。
class ModelSource {
  final String profileId;
  final String profileName;
  final List<String> modelIds;
  final bool active;

  const ModelSource({
    required this.profileId,
    required this.profileName,
    required this.modelIds,
    this.active = false,
  });
}

/// 目录中的一条可选模型。
class ModelEntry {
  final String id;
  final String profileId;
  final String profileName;
  final String provider;
  final String family;
  final bool active;
  final bool vision;
  final bool reasoning;
  final bool chat;

  /// 是否被关键词直接命中；false 表示因「同族 / 相近族」被一起带出。
  final bool directHit;

  const ModelEntry({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.provider,
    required this.family,
    required this.active,
    required this.vision,
    required this.reasoning,
    required this.chat,
    this.directHit = true,
  });

  /// 展示用运营商：优先用模型 ID 里的 provider 前缀，否则用连接配置名。
  String get providerLabel => provider.isNotEmpty ? provider : profileName;

  String get tags => [
        if (vision) '视觉 vision',
        if (reasoning) '推理 reasoning',
      ].join(' ');

  String get haystack =>
      ('$id $providerLabel $profileName $family $tags').toLowerCase();

  ModelEntry withHit(bool hit) => ModelEntry(
        id: id,
        profileId: profileId,
        profileName: profileName,
        provider: provider,
        family: family,
        active: active,
        vision: vision,
        reasoning: reasoning,
        chat: chat,
        directHit: hit,
      );
}

/// 同一「模型族」下的全部版本 / 全部运营商。
class ModelGroup {
  final String family;
  final List<ModelEntry> entries;

  const ModelGroup(this.family, this.entries);

  int get providerCount => entries.map((e) => e.providerLabel).toSet().length;

  int get directCount => entries.where((e) => e.directHit).length;
}

// 能力类关键词的哨兵：走布尔判定而不是普通子串匹配。
const String _kVision = '\u0001vision';
const String _kReasoning = '\u0001reasoning';

/// 常见简写 / 中文叫法 → 标准关键词（组内 OR，组间 AND）。
/// 输入「4o」「ds」「通义」「视觉」也能命中对应模型。
const Map<String, List<String>> kModelAliases = {
  '4o': ['gpt-4o', '4o'],
  'gpt4': ['gpt-4'],
  'gpt4o': ['gpt-4o'],
  'ds': ['deepseek'],
  '深度求索': ['deepseek'],
  '克劳德': ['claude'],
  'qwen': ['qwen'],
  '通义': ['qwen'],
  'glm': ['glm'],
  '智谱': ['glm'],
  'gemini': ['gemini'],
  '谷歌': ['gemini'],
  'vision': [_kVision],
  '视觉': [_kVision],
  '看图': [_kVision],
  '多模态': [_kVision],
  'reasoning': [_kReasoning],
  '推理': [_kReasoning],
  '思考': [_kReasoning],
  'thinking': [_kReasoning],
};

/// 从 `provider/model` 形式里取出运营商（OpenRouter / 各类中转常见）。
String modelProvider(String id) {
  final s = id.trim();
  final slash = s.indexOf('/');
  if (slash > 0 && slash <= 24) return s.substring(0, slash);
  return '';
}

/// 把模型 ID 归一化成「族名」，用于把同一模型的不同版本 / 不同运营商聚在一起。
///
/// - `openai/gpt-4o-2024-08-06` → `gpt-4o`
/// - `anthropic/claude-3-5-sonnet-20241022:free` → `claude-3-5-sonnet`
/// - `deepseek-chat-v3-0324` → `deepseek-chat-v3`
String modelFamily(String id) {
  var s = id.trim().toLowerCase();
  final slash = s.indexOf('/');
  if (slash > 0 && slash <= 24) s = s.substring(slash + 1);
  s = s.replaceAll(RegExp(r':(free|extended|exacto|nitro|floor|online)$'), '');
  s = s.replaceAll(RegExp(r'@\d{6,}$'), '');
  s = s.replaceAll(
      RegExp(r'[-_]?(20\d{2}[-_]?\d{2}[-_]?\d{2}|20\d{2}[-_]?\d{2})$'), '');
  s = s.replaceAll(RegExp(r'[-_]\d{4}$'), '');
  s = s.replaceAll(RegExp(r'[-_](preview|latest|beta|exp)$'), '');
  s = s.replaceAll(RegExp(r'[-_]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? id.trim().toLowerCase() : s;
}

/// 汇总所有连接配置的模型，支持关键词搜索与跨运营商同族对比。纯逻辑，可单测。
class ModelCatalog {
  final List<ModelEntry> entries;

  const ModelCatalog(this.entries);

  factory ModelCatalog.fromSources(List<ModelSource> sources) {
    final out = <ModelEntry>[];
    final seen = <String>{};
    for (final src in sources) {
      for (final raw in src.modelIds) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        // 同一配置内去重，跨配置保留（不同运营商各占一条）。
        if (!seen.add('${src.profileId}|$id')) continue;
        final mi = ModelInfo(id: id);
        out.add(ModelEntry(
          id: id,
          profileId: src.profileId,
          profileName: src.profileName,
          provider: modelProvider(id),
          family: modelFamily(id),
          active: src.active,
          vision: mi.vision,
          reasoning: mi.reasoning,
          chat: mi.isChat,
        ));
      }
    }
    return ModelCatalog(out);
  }

  int get sourceCount => entries.map((e) => e.profileId).toSet().length;

  int get familyCount => entries.map((e) => e.family).toSet().length;

  /// 高频族，作为空态下的快捷入口。
  List<String> topFamilies(int n) {
    final count = <String, int>{};
    for (final e in entries.where((e) => e.chat)) {
      count[e.family] = (count[e.family] ?? 0) + 1;
    }
    final keys = count.keys.toList()
      ..sort((a, b) {
        final c = count[b]!.compareTo(count[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return keys.take(n).toList();
  }

  static List<List<String>> _tokens(String q) {
    final out = <List<String>>[];
    for (final raw in q.trim().toLowerCase().split(RegExp(r'[\s,，+]+'))) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      out.add(kModelAliases[t] ?? [t]);
    }
    return out;
  }

  /// 关键词命中后，把同族及相近族下**所有运营商 / 所有版本**一并带出并分组。
  /// 多个关键词之间是 AND；别名组内是 OR；`视觉`/`推理` 走能力判定。
  List<ModelGroup> search(
    String query, {
    bool showAll = false,
    int maxEntries = 240,
  }) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return const [];
    final pool = showAll ? entries : entries.where((e) => e.chat).toList();

    bool hit(ModelEntry e) {
      final hay = e.haystack;
      for (final group in tokens) {
        var ok = false;
        for (final t in group) {
          if (t == _kVision) {
            if (e.vision) ok = true;
          } else if (t == _kReasoning) {
            if (e.reasoning) ok = true;
          } else if (hay.contains(t)) {
            ok = true;
          }
          if (ok) break;
        }
        if (!ok) return false;
      }
      return true;
    }

    final directKeys = <String>{};
    final families = <String>{};
    for (final e in pool) {
      if (!hit(e)) continue;
      directKeys.add('${e.profileId}|${e.id}');
      families.add(e.family);
      if (directKeys.length >= maxEntries) break;
    }
    if (directKeys.isEmpty) return const [];

    // 相近族（同前缀、长度差有限）：搜 gpt-4o 也能看到 gpt-4o-mini 等变体。
    final near = <String>{};
    for (final f in pool.map((e) => e.family).toSet()) {
      if (families.contains(f)) continue;
      for (final base in families) {
        if ((f.startsWith(base) || base.startsWith(f)) &&
            (f.length - base.length).abs() <= 12) {
          near.add(f);
          break;
        }
      }
    }
    families.addAll(near);

    final byFamily = <String, List<ModelEntry>>{};
    var total = 0;
    for (final e in pool) {
      if (!families.contains(e.family)) continue;
      if (total >= maxEntries) break;
      final key = '${e.profileId}|${e.id}';
      byFamily
          .putIfAbsent(e.family, () => <ModelEntry>[])
          .add(directKeys.contains(key) ? e : e.withHit(false));
      total++;
    }

    final groups = <ModelGroup>[];
    byFamily.forEach((family, list) {
      list.sort((a, b) {
        if (a.directHit != b.directHit) return a.directHit ? -1 : 1;
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.providerLabel.compareTo(b.providerLabel);
      });
      groups.add(ModelGroup(family, list));
    });
    groups.sort((a, b) {
      final d = b.directCount.compareTo(a.directCount);
      return d != 0 ? d : a.family.compareTo(b.family);
    });
    return groups.take(12).toList(growable: false);
  }
}
