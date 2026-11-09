import '../models/models.dart';

/// 「连接（运营商 / 提供商）→ 模型列表」的一级条目。
///
/// 圆桌会议、模拟人生、AI 小游戏共用同一份来源：用户先选一家连接，
/// 再进入这一家的模型列表挑具体模型。密钥只在内存中传递，绝不落盘。
class ProviderGroup {
  final String id;
  final String name;
  final String host;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final bool active;

  const ProviderGroup({
    required this.id,
    required this.name,
    required this.host,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    this.active = false,
  });
}

/// 一次两级选择的结果。
class ModelChoice {
  final String baseUrl;
  final String apiKey;
  final String model;
  final String providerName;

  const ModelChoice({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.providerName,
  });

  String get label => '$providerName · $model';
}

/// 某个连接下可见的模型：当前模型优先，其次是该连接缓存的模型。
///
/// [activeModels] 是活动连接刚刚刷新到内存里的列表（可能还没写回 profile），
/// 由调用方从 AppState 传入；非活动连接只看自己的缓存，避免串台。
List<String> modelsForProfile(
  AppSettings s,
  ApiProfile p, {
  List<String> activeModels = const [],
}) {
  final isActive = p.id == s.activeProfileId;
  final raw = <String>[
    if (isActive) s.model,
    p.model,
    if (isActive) ...activeModels,
    ...p.cachedModels,
  ];
  final seen = <String>{};
  final out = <String>[];
  for (final m in raw) {
    final v = m.trim();
    if (v.isEmpty || !seen.add(v)) continue;
    out.add(v);
  }
  return out;
}

/// 把设置里的多连接整理成可展示的分组列表。
List<ProviderGroup> buildProviderGroups(
  AppSettings s, {
  List<String> activeModels = const [],
}) {
  return [
    for (final p in s.profiles)
      ProviderGroup(
        id: p.id,
        name: p.name,
        host: p.hostLabel,
        baseUrl: p.baseUrl,
        apiKey: p.apiKey,
        models: modelsForProfile(s, p, activeModels: activeModels),
        active: p.id == s.activeProfileId,
      ),
  ];
}

/// 「沿用当前对话模型」的快捷结果。
ModelChoice currentChatChoice(AppSettings s) => ModelChoice(
      baseUrl: s.baseUrl,
      apiKey: s.apiKey,
      model: s.model,
      providerName: s.activeProfile.name,
    );

/// 按关键词过滤模型 ID（大小写不敏感）。
List<String> filterModels(List<String> models, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return models;
  return models.where((m) => m.toLowerCase().contains(q)).toList();
}

/// 按地址从当前连接里补回密钥（存档不写密钥）。
String apiKeyForBaseUrl(AppSettings s, String baseUrl) {
  if (baseUrl.trim() == s.baseUrl.trim()) return s.apiKey;
  for (final p in s.profiles) {
    if (p.baseUrl.trim() == baseUrl.trim()) return p.apiKey;
  }
  return '';
}

/// 把「记住的模型」还原成可直接发请求的 [ModelChoice]。
/// 没记住、或记住的模型已失效时，一律退回当前对话模型，避免请求打到空地址。
ModelChoice resolveModelChoice(
  AppSettings s, {
  String? baseUrl,
  String? model,
  String? providerName,
}) {
  final b = (baseUrl ?? '').trim();
  final m = (model ?? '').trim();
  if (b.isEmpty || m.isEmpty) return currentChatChoice(s);
  final name = (providerName ?? '').trim().isNotEmpty
      ? providerName!.trim()
      : providerNameFor(s, b);
  return ModelChoice(
    baseUrl: b,
    apiKey: apiKeyForBaseUrl(s, b),
    model: m,
    providerName: name,
  );
}

/// 按 baseUrl 找连接名，用于把存档里只有地址的席位显示成可读文字。
String providerNameFor(AppSettings s, String baseUrl) {
  for (final p in s.profiles) {
    if (p.baseUrl.trim() == baseUrl.trim()) return p.name;
  }
  if (baseUrl.trim() == s.baseUrl.trim()) return s.activeProfile.name;
  try {
    final h = Uri.parse(baseUrl).host;
    if (h.isNotEmpty) return h;
  } catch (_) {}
  return baseUrl;
}
