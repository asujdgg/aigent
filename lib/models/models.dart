import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

const String kDefaultSystemPrompt =
    'You are a precise, concise research assistant. Answer in the language of the user. '
    'Structure long answers with short paragraphs, lists and headings. '
    'When sources are provided, ground claims in them and cite them as [1], [2].';

/// 单一版本来源：界面、关于页、设备信息都读这里，避免各页各写一份。
const String kAppVersion = '4.26.0';
const int kAppBuild = 45;
const String kAppIconAsset = 'assets/brand/app_icon.png';

enum Tier { lite, standard, deep, expert }

extension TierX on Tier {
  String get label {
    switch (this) {
      case Tier.lite:
        return '轻量';
      case Tier.standard:
        return '标准';
      case Tier.deep:
        return '深度';
      case Tier.expert:
        return '专家';
    }
  }

  String get hint {
    switch (this) {
      case Tier.lite:
        return '低延迟 / 不思考 / 短回复';
      case Tier.standard:
        return '速度与质量均衡';
      case Tier.deep:
        return '强模型 / 长上下文 / 高思考预算';
      case Tier.expert:
        return '最高配置 / 最大上下文';
    }
  }

  int get maxTokens => const {
        Tier.lite: 1024,
        Tier.standard: 2048,
        Tier.deep: 4096,
        Tier.expert: 8192,
      }[this]!;

  double get temperature => const {
        Tier.lite: 0.25,
        Tier.standard: 0.55,
        Tier.deep: 0.7,
        Tier.expert: 0.8,
      }[this]!;

  double get topP => const {
        Tier.lite: 0.85,
        Tier.standard: 0.9,
        Tier.deep: 0.95,
        Tier.expert: 0.97,
      }[this]!;

  int get thinkingBudget => const {
        Tier.lite: 0,
        Tier.standard: 0,
        Tier.deep: 4096,
        Tier.expert: 16384,
      }[this]!;

  String get reasoningEffort => const {
        Tier.lite: 'low',
        Tier.standard: 'medium',
        Tier.deep: 'high',
        Tier.expert: 'high',
      }[this]!;

  int get historyLimit => const {
        Tier.lite: 6,
        Tier.standard: 12,
        Tier.deep: 24,
        Tier.expert: 40,
      }[this]!;
}

enum Role { user, assistant, tool }

class Citation {
  final int index;
  final String title;
  final String url;
  final String snippet;
  final String source;

  const Citation({
    required this.index,
    required this.title,
    required this.url,
    this.snippet = '',
    this.source = '',
  });

  String get host {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'url': url,
        'snippet': snippet,
        'source': source,
      };

  factory Citation.fromJson(Map<dynamic, dynamic> j) => Citation(
        index: (j['index'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        snippet: (j['snippet'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
      );
}

enum AttachKind { image, text, pdf }

/// 按模型 ID 粗判是否具备视觉能力。只用于「提示 / 引导」，不阻断发送：
/// 很多网关用自定义别名，最终是否支持图片由服务端决定。
final RegExp _kVisionRe = RegExp(
  r'vision|[-_]vl\b|vl[-_]|omni|gpt-4o|gpt-4\.1|claude[-_]?3|claude[-_]?4|gemini|pixtral|llava|qwen[-_]?2?[-_]?vl|internvl|glm-4v|step-1v|yi-vl|cogvlm|minicpm-v|gpt-4-turbo|(^|[-_/])(o3|o4)([-_:/.]|$)|image|multimodal',
  caseSensitive: false,
);

bool looksLikeVisionModel(String id) =>
    id.trim().isNotEmpty && _kVisionRe.hasMatch(id);

/// 多模态图片在请求里的发送格式。不同网关差异很大，允许自行切换排查。
enum VisionFormat { openai, openaiLite, ollama, textOnly }

extension VisionFormatX on VisionFormat {
  String get label {
    switch (this) {
      case VisionFormat.openai:
        return 'OpenAI 标准';
      case VisionFormat.openaiLite:
        return '标准 · 去 detail';
      case VisionFormat.ollama:
        return 'Ollama images';
      case VisionFormat.textOnly:
        return '仅文本（不发送图片）';
    }
  }

  String get note {
    switch (this) {
      case VisionFormat.openai:
        return 'content 数组 + image_url(data URI) + detail:auto，OpenAI / 多数中转';
      case VisionFormat.openaiLite:
        return '同上但去掉 detail 字段，兼容不接受 detail 的网关';
      case VisionFormat.ollama:
        return 'content 为纯文本，图片放顶层 images 数组（纯 base64）';
      case VisionFormat.textOnly:
        return '只发文字说明，不携带图片字节；用于确认网关是否因图片报错';
    }
  }
}

class Attachment {
  final String id;
  final String name;
  final AttachKind kind;
  final Uint8List? imageBytes;
  final String? text;
  final int size;

  /// 按真实字节魔数判定的 MIME（优先于按扩展名猜测）。
  final String? imageMime;

  const Attachment({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    this.imageBytes,
    this.text,
    this.imageMime,
  });

  String get mime {
    if (kind == AttachKind.image) {
      if (imageMime != null && imageMime!.isNotEmpty) return imageMime!;
      final e = name.toLowerCase();
      if (e.endsWith('.png')) return 'image/png';
      if (e.endsWith('.webp')) return 'image/webp';
      if (e.endsWith('.gif')) return 'image/gif';
      if (e.endsWith('.bmp')) return 'image/bmp';
      if (e.endsWith('.heic') || e.endsWith('.heif')) return 'image/heic';
      return 'image/jpeg';
    }
    return 'text/plain';
  }

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1048576).toStringAsFixed(1)} MB';
  }

  bool get isImage => kind == AttachKind.image && imageBytes != null;

  /// 历史落盘用。图片按 base64 随消息保存，重开软件仍能看到原图。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'size': size,
        if (imageBytes != null && imageBytes!.isNotEmpty)
          'image': base64Encode(imageBytes!),
        if (text != null) 'text': text,
        if (imageMime != null) 'mime': imageMime,
      };

  factory Attachment.fromJson(Map<dynamic, dynamic> j) {
    Uint8List? bytes;
    final raw = j['image'];
    if (raw is String && raw.isNotEmpty) {
      try {
        bytes = base64Decode(raw);
      } catch (_) {}
    }
    return Attachment(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      kind: AttachKind.values.firstWhere(
        (k) => k.name == (j['kind'] ?? '').toString(),
        orElse: () => AttachKind.text,
      ),
      size: (j['size'] as num?)?.toInt() ?? bytes?.length ?? 0,
      imageBytes: bytes,
      text: j['text']?.toString(),
      imageMime: j['mime']?.toString(),
    );
  }
}

/// 只保存原始思维链，UI 层永远不展示原文，只消费 [summary]。
class ThinkingTrace extends ChangeNotifier {
  ThinkingTrace();

  final StringBuffer _buf = StringBuffer();
  bool running = false;
  bool done = false;
  int startedAt = 0;

  void append(String s) {
    if (s.isEmpty) return;
    _buf.write(s);
    notifyListeners();
  }

  void markRunning() {
    running = true;
    startedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void markDone() {
    if (!running && done) return;
    _endedAt = DateTime.now().millisecondsSinceEpoch;
    running = false;
    done = true;
    notifyListeners();
  }

  int get chars => _buf.length;
  String get raw => _buf.toString();

  /// 展开时显示的全文：只压掉多余空行，不截断、不改写。
  /// 思考内容本身就是模型的原始独白，改写它等于又一次编造。
  String get full {
    final t = raw.replaceAll('\r\n', '\n');
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// 思考耗时（毫秒）；未结束时返回 0。
  int get elapsedMs {
    if (startedAt <= 0) return 0;
    final end = done ? _endedAt : DateTime.now().millisecondsSinceEpoch;
    final d = end - startedAt;
    return d < 0 ? 0 : d;
  }

  String get elapsedLabel {
    final ms = elapsedMs;
    if (ms <= 0) return '';
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  int _endedAt = 0;

  /// 只持久化原始正文与时间点：恢复后的思考记录是只读的历史，
  /// 不再参与流式追加，所以 running 一律为 false。
  Map<String, dynamic> toJson() => {
        'raw': raw,
        'startedAt': startedAt,
        'endedAt': _endedAt,
      };

  factory ThinkingTrace.fromJson(Map<dynamic, dynamic> j) {
    final t = ThinkingTrace();
    final r = (j['raw'] ?? '').toString();
    if (r.isNotEmpty) t._buf.write(r);
    t.startedAt = (j['startedAt'] as num?)?.toInt() ?? 0;
    t._endedAt = (j['endedAt'] as num?)?.toInt() ?? 0;
    t.done = t.startedAt > 0;
    return t;
  }

  String get summary {
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '已完成推理，结论见下方回答。';
    final parts = t
        .split(RegExp(r'[。！？.!?;；]'))
        .map((e) => e.trim())
        .where((e) => e.length > 8)
        .toList();
    final picked = parts.take(2).join('；').trim();
    final base = picked.isEmpty ? t : picked;
    return base.length > 116 ? '${base.substring(0, 116)}…' : base;
  }
}

class ChatMessage extends ChangeNotifier {
  final String id;
  final Role role;
  final DateTime at;
  String content;
  List<Attachment> attachments;
  List<Citation> citations;
  ThinkingTrace? thinking;
  bool streaming;
  String? model;
  String? tierLabel;
  String? error;
  String? searchQuery;
  int? elapsedMs;
  TokenUsage? usage;

  /// 本机工具执行记录（Role.tool）：消息流里渲染成一张独立的操作卡片，
  /// 不会混入发给模型的上下文（send 构建历史时跳过 Role.tool）。
  String? toolName;
  bool? toolOk;

  /// 第几步 / 耗时（毫秒）：执行轨迹按这两项排成时间线。
  int? toolStep;
  int? toolMs;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? at,
    List<Attachment>? attachments,
    List<Citation>? citations,
    this.thinking,
    this.streaming = false,
    this.model,
    this.tierLabel,
    this.error,
    this.searchQuery,
    this.toolName,
    this.toolOk,
    this.toolStep,
    this.toolMs,
  })  : at = at ?? DateTime.now(),
        attachments = attachments ?? [],
        citations = citations ?? [];

  void append(String s) {
    if (s.isEmpty) return;
    content += s;
    notifyListeners();
  }

  void setStreaming(bool v) {
    streaming = v;
    notifyListeners();
  }

  void finish({String? err}) {
    streaming = false;
    error = err;
    notifyListeners();
  }

  void setCitations(List<Citation> c) {
    citations = c;
    notifyListeners();
  }

  /// 历史落盘。streaming 不进文件：重开软件时不可能有正在生成的回答。
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'at': at.millisecondsSinceEpoch,
        'content': content,
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) a.toJson()],
        if (citations.isNotEmpty)
          'citations': [for (final c in citations) c.toJson()],
        if (thinking != null && thinking!.raw.trim().isNotEmpty)
          'thinking': thinking!.toJson(),
        if ((model ?? '').isNotEmpty) 'model': model,
        if ((tierLabel ?? '').isNotEmpty) 'tierLabel': tierLabel,
        if ((error ?? '').isNotEmpty) 'error': error,
        if ((searchQuery ?? '').isNotEmpty) 'searchQuery': searchQuery,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (usage != null) 'usage': usage!.toJson(),
        if (toolName != null) 'toolName': toolName,
        if (toolOk != null) 'toolOk': toolOk,
        if (toolStep != null) 'toolStep': toolStep,
        if (toolMs != null) 'toolMs': toolMs,
      };

  factory ChatMessage.fromJson(Map<dynamic, dynamic> j) {
    final m = ChatMessage(
      id: (j['id'] ?? '').toString(),
      role: Role.values.firstWhere(
        (r) => r.name == (j['role'] ?? '').toString(),
        orElse: () => Role.assistant,
      ),
      content: (j['content'] ?? '').toString(),
      at: DateTime.fromMillisecondsSinceEpoch(
          (j['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
    );
    final atts = j['attachments'];
    if (atts is List) {
      m.attachments = atts
          .whereType<Map>()
          .map((e) => Attachment.fromJson(Map<dynamic, dynamic>.from(e)))
          .toList();
    }
    final cits = j['citations'];
    if (cits is List) {
      m.citations = cits
          .whereType<Map>()
          .map((e) => Citation.fromJson(Map<dynamic, dynamic>.from(e)))
          .toList();
    }
    final th = j['thinking'];
    if (th is Map) m.thinking = ThinkingTrace.fromJson(th);
    m.model = j['model']?.toString();
    m.tierLabel = j['tierLabel']?.toString();
    m.error = j['error']?.toString();
    m.searchQuery = j['searchQuery']?.toString();
    m.elapsedMs = (j['elapsedMs'] as num?)?.toInt();
    m.toolName = j['toolName']?.toString();
    m.toolOk = j['toolOk'] is bool ? j['toolOk'] as bool : null;
    m.toolStep = (j['toolStep'] as num?)?.toInt();
    m.toolMs = (j['toolMs'] as num?)?.toInt();
    final u = j['usage'];
    if (u is Map) m.usage = TokenUsage.fromJson(u);
    return m;
  }
}

class Conversation {
  final String id;
  String title;
  final DateTime at;
  final List<ChatMessage> messages;

  // ---- 会话级运行时状态（内存态，彼此完全隔离）----
  // v3.7 前这些是 AppState 的全局单例：切换 / 新建会话只改 activeId，
  // 于是 A 会话「生成中」会串到 B，输入草稿也会跟着跑到别的对话框。
  /// 输入栏草稿，按会话独立保存，切回来仍在。
  String draft = '';

  /// 待发附件，按会话独立。
  List<Attachment> draftAttachments = [];

  /// 该会话是否正在生成。
  bool generating = false;

  /// 该会话的状态栏文案（生成中 / 检索中…）。
  String status = '';

  /// 该会话绑定的人物形象 id；为空则跟随全局默认形象。
  String personaId = '';

  Conversation({
    required this.id,
    required this.title,
    DateTime? at,
    List<ChatMessage>? messages,
  })  : at = at ?? DateTime.now(),
        messages = messages ?? [];

  int get count => messages.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'at': at.millisecondsSinceEpoch,
        if (personaId.isNotEmpty) 'personaId': personaId,
        'messages': [for (final m in messages) m.toJson()],
      };

  factory Conversation.fromJson(Map<dynamic, dynamic> j) {
    final list = j['messages'];
    return Conversation(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '新对话').toString(),
      at: DateTime.fromMillisecondsSinceEpoch(
          (j['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      messages: list is List
          ? list
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<dynamic, dynamic>.from(e)))
              .toList()
          : <ChatMessage>[],
    )..personaId = (j['personaId'] ?? '').toString();
  }
}

// ---------------------------------------------------------------- 人物形象

/// 可自定义的 AI 形象。头像支持「字符 / emoji」或「相册图片（base64）」，
/// 角色设定会作为一段 system 文本注入，让形象不只是贴图。
class Persona {
  String id;
  String name;

  /// 文字 / emoji 头像（无自定义图片时显示）。
  String glyph;

  /// 自定义头像：压缩后的 jpeg base64；为空则用 [glyph]。
  String imageB64;

  /// 一句话设定，展示在名字下方。
  String tagline;

  /// 角色与语气设定，注入 system prompt。
  String roleHint;

  /// 主题色索引，指向 [kPersonaTints]。
  int tint;

  /// 内置预设不可删除，只能编辑。
  bool builtin;

  Persona({
    required this.id,
    required this.name,
    this.glyph = 'A',
    this.imageB64 = '',
    this.tagline = '',
    this.roleHint = '',
    this.tint = 0,
    this.builtin = false,
  });

  bool get hasImage => imageB64.isNotEmpty;

  Color get color => kPersonaTints[tint.clamp(0, kPersonaTints.length - 1)];

  Persona copyWith({
    String? id,
    String? name,
    String? glyph,
    String? imageB64,
    String? tagline,
    String? roleHint,
    int? tint,
    bool? builtin,
  }) =>
      Persona(
        id: id ?? this.id,
        name: name ?? this.name,
        glyph: glyph ?? this.glyph,
        imageB64: imageB64 ?? this.imageB64,
        tagline: tagline ?? this.tagline,
        roleHint: roleHint ?? this.roleHint,
        tint: tint ?? this.tint,
        builtin: builtin ?? this.builtin,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'glyph': glyph,
        'imageB64': imageB64,
        'tagline': tagline,
        'roleHint': roleHint,
        'tint': tint,
        'builtin': builtin,
      };

  factory Persona.fromJson(Map<dynamic, dynamic> j) => Persona(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '形象').toString(),
        glyph: (j['glyph'] ?? 'A').toString(),
        imageB64: (j['imageB64'] ?? '').toString(),
        tagline: (j['tagline'] ?? '').toString(),
        roleHint: (j['roleHint'] ?? '').toString(),
        tint: (j['tint'] as num?)?.toInt() ?? 0,
        builtin: j['builtin'] == true,
      );
}

/// 低饱和的主题色，克制的墨蓝 / 赭 / 松绿 / 紫灰 / 石墨。
const List<Color> kPersonaTints = [
  Color(0xFF203A5E),
  Color(0xFF8A6A33),
  Color(0xFF3A6656),
  Color(0xFF6B5470),
  Color(0xFF4A5568),
  Color(0xFF9E4747),
];

/// v4.9.2：形象库默认是空的。
///
/// 以前这里塞了一条「不使用形象」，于是每个用户都能在顶栏和切换面板里
/// 读到一句「你没设置形象」——没设置就该什么都没有，而不是多一行解释。
/// 现在列表完全由用户自己建，没建就是空列表。
List<Persona> defaultPersonas() => <Persona>[];

/// 没设置形象时的内部占位：只为让 `activePersona` 永远有对象可返回，
/// 它不进列表、不带任何文案，界面上不会显示成一条「形象」。
Persona nonePersona() =>
    Persona(id: 'persona_none', name: '', glyph: '', builtin: true);

/// 内置搜索源注册表。新增源只需在此加枚举 + 元数据 + [SearchService] 的请求分支。
enum SearchProvider {
  // 主流商业 API
  tavily,
  serper,
  serpapi,
  searchapi,
  brave,
  exa,
  you,
  firecrawl,
  bing,
  google,
  // 国内
  bocha,
  // 代码 / 开发者
  githubRepo,
  githubCode,
  githubIssues,
  // 自建 / 免密钥 / 轻量
  searxng,
  ddg,
  wikipedia,
  mojeek,
  yep,
  jina,
  // 兜底
  custom,
}

extension SearchProviderX on SearchProvider {
  String get label {
    switch (this) {
      case SearchProvider.tavily:
        return 'Tavily';
      case SearchProvider.serper:
        return 'Serper.dev（Google）';
      case SearchProvider.serpapi:
        return 'SerpAPI（Google）';
      case SearchProvider.searchapi:
        return 'SearchAPI.io';
      case SearchProvider.brave:
        return 'Brave Search';
      case SearchProvider.exa:
        return 'Exa AI（语义检索）';
      case SearchProvider.you:
        return 'You.com / YDC';
      case SearchProvider.firecrawl:
        return 'Firecrawl Search';
      case SearchProvider.bing:
        return 'Bing Web Search v7';
      case SearchProvider.google:
        return 'Google 可编程搜索 CSE';
      case SearchProvider.bocha:
        return '博查 BochaAI（国内）';
      case SearchProvider.githubRepo:
        return 'GitHub 仓库搜索';
      case SearchProvider.githubCode:
        return 'GitHub 代码搜索';
      case SearchProvider.githubIssues:
        return 'GitHub Issues / PR';
      case SearchProvider.searxng:
        return 'SearXNG（自建）';
      case SearchProvider.ddg:
        return 'DuckDuckGo Instant（免密钥）';
      case SearchProvider.wikipedia:
        return 'Wikipedia（免密钥）';
      case SearchProvider.mojeek:
        return 'Mojeek';
      case SearchProvider.yep:
        return 'Yep.com（免密钥）';
      case SearchProvider.jina:
        return 'Jina AI Search';
      case SearchProvider.custom:
        return '自定义 HTTP 接口';
    }
  }

  /// 引用卡片与连通性测试里的短标签。
  String get shortLabel {
    switch (this) {
      case SearchProvider.githubRepo:
        return 'GitHub 仓库';
      case SearchProvider.githubCode:
        return 'GitHub 代码';
      case SearchProvider.githubIssues:
        return 'GitHub Issue';
      default:
        return label.split('（').first.trim();
    }
  }

  String get group {
    switch (this) {
      case SearchProvider.tavily:
      case SearchProvider.serper:
      case SearchProvider.serpapi:
      case SearchProvider.searchapi:
      case SearchProvider.brave:
      case SearchProvider.exa:
      case SearchProvider.you:
      case SearchProvider.firecrawl:
      case SearchProvider.bing:
      case SearchProvider.google:
        return '主流商业 API';
      case SearchProvider.bocha:
        return '国内可用';
      case SearchProvider.githubRepo:
      case SearchProvider.githubCode:
      case SearchProvider.githubIssues:
        return '代码 / 开发者';
      case SearchProvider.searxng:
      case SearchProvider.ddg:
      case SearchProvider.wikipedia:
      case SearchProvider.mojeek:
      case SearchProvider.yep:
      case SearchProvider.jina:
        return '自建 / 免密钥';
      case SearchProvider.custom:
        return '自定义';
    }
  }

  String get endpoint {
    switch (this) {
      case SearchProvider.tavily:
        return 'https://api.tavily.com/search';
      case SearchProvider.serper:
        return 'https://google.serper.dev/search';
      case SearchProvider.serpapi:
        return 'https://serpapi.com/search.json';
      case SearchProvider.searchapi:
        return 'https://www.searchapi.io/api/v1/search';
      case SearchProvider.brave:
        return 'https://api.search.brave.com/res/v1/web/search';
      case SearchProvider.exa:
        return 'https://api.exa.ai/search';
      case SearchProvider.you:
        return 'https://api.ydc-index.io/search';
      case SearchProvider.firecrawl:
        return 'https://api.firecrawl.dev/v1/search';
      case SearchProvider.bing:
        return 'https://api.bing.microsoft.com/v7.0/search';
      case SearchProvider.google:
        return 'https://www.googleapis.com/customsearch/v1';
      case SearchProvider.bocha:
        return 'https://api.bochaai.com/v1/web-search';
      case SearchProvider.githubRepo:
        return 'https://api.github.com/search/repositories';
      case SearchProvider.githubCode:
        return 'https://api.github.com/search/code';
      case SearchProvider.githubIssues:
        return 'https://api.github.com/search/issues';
      case SearchProvider.searxng:
        return '';
      case SearchProvider.ddg:
        return 'https://api.duckduckgo.com/';
      case SearchProvider.wikipedia:
        return 'https://zh.wikipedia.org/w/api.php';
      case SearchProvider.mojeek:
        return 'https://api.mojeek.com/search';
      case SearchProvider.yep:
        return 'https://api.yep.com/fs/2/search';
      case SearchProvider.jina:
        return 'https://s.jina.ai/';
      case SearchProvider.custom:
        return '';
    }
  }

  /// 密钥在设置页的显示名。
  String get keyLabel {
    switch (this) {
      case SearchProvider.google:
        return 'Google API Key';
      case SearchProvider.ddg:
      case SearchProvider.wikipedia:
      case SearchProvider.yep:
        return 'API Key（该源无需密钥）';
      case SearchProvider.searxng:
        return 'API Key（自建实例通常无需）';
      case SearchProvider.githubRepo:
      case SearchProvider.githubIssues:
        return 'GitHub Token（可选，提升速率限制）';
      case SearchProvider.githubCode:
        return 'GitHub Token（代码搜索必需）';
      case SearchProvider.searchapi:
      case SearchProvider.serpapi:
        return 'API Key';
      default:
        return '搜索 API Key';
    }
  }

  bool get needsKey {
    switch (this) {
      case SearchProvider.ddg:
      case SearchProvider.wikipedia:
      case SearchProvider.yep:
      case SearchProvider.searxng:
      case SearchProvider.githubRepo:
      case SearchProvider.githubIssues:
        return false;
      default:
        return true;
    }
  }

  /// 需要额外填写 Endpoint 的源（自建实例或自定义接口）。
  bool get needsEndpoint =>
      this == SearchProvider.custom || this == SearchProvider.searxng;

  bool get needsCx => this == SearchProvider.google;

  /// 免密钥但填 Token 能显著提速 / 解锁能力的源，设置页仍展示密钥输入框。
  bool get showKeyField =>
      needsKey ||
      this == SearchProvider.githubRepo ||
      this == SearchProvider.githubIssues;

  String get note {
    switch (this) {
      case SearchProvider.tavily:
        return 'POST · 为 LLM 优化的检索，返回正文摘要';
      case SearchProvider.serper:
        return 'POST · X-API-KEY 请求头，Google 结果';
      case SearchProvider.serpapi:
        return 'GET · api_key 查询参数，支持多引擎';
      case SearchProvider.searchapi:
        return 'GET · api_key 查询参数，默认 Google 引擎';
      case SearchProvider.brave:
        return 'GET · X-Subscription-Token 请求头，独立索引';
      case SearchProvider.exa:
        return 'POST · 神经网络语义检索，返回正文';
      case SearchProvider.you:
        return 'GET · X-API-Key 请求头，返回 hits 与片段';
      case SearchProvider.firecrawl:
        return 'POST · Bearer 认证，附带网页抓取';
      case SearchProvider.bing:
        return 'GET · Ocp-Apim-Subscription-Key 请求头';
      case SearchProvider.google:
        return 'GET · 需同时填写 API Key 与 CSE CX';
      case SearchProvider.bocha:
        return 'POST · Bearer 认证，国内直连可用';
      case SearchProvider.githubRepo:
        return 'GET · 匿名可用；填 Token 提升速率。支持 repo:、language: 等搜索语法';
      case SearchProvider.githubCode:
        return 'GET · 需有代码读取权限的 GitHub Token，未认证返回 401';
      case SearchProvider.githubIssues:
        return 'GET · 检索 Issue / PR，支持 is:pr、label: 等语法';
      case SearchProvider.searxng:
        return 'GET · 填自建实例地址，如 https://searx.example/search（需开启 JSON 格式）';
      case SearchProvider.ddg:
        return 'GET · 免密钥，返回 Instant Answer，结果较少';
      case SearchProvider.wikipedia:
        return 'GET · 免密钥，仅检索维基百科条目';
      case SearchProvider.mojeek:
        return 'GET · k 参数认证，独立爬虫索引';
      case SearchProvider.yep:
        return 'GET · 免密钥，Ahrefs 提供的公开接口';
      case SearchProvider.jina:
        return 'GET · 返回 Markdown 列表，可选 Bearer 提升配额';
      case SearchProvider.custom:
        return 'GET · 地址支持 {query} 占位符，自动解析任意 JSON 结构';
    }
  }
}

/// 一份完整的 API 连接配置。切换时整份保留，不需要删除旧的。
/// [apiKey] 只在内存中持有，由 SecureStore 单独加密保管，绝不写入设置 JSON。
class ApiProfile {
  String id;
  String name;
  String baseUrl;
  String apiKey;
  String model;
  List<String> cachedModels;
  int cachedModelsAt;
  bool showAllModels;

  ApiProfile({
    required this.id,
    required this.name,
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = '',
    List<String>? cachedModels,
    this.cachedModelsAt = 0,
    this.showAllModels = false,
  }) : cachedModels = cachedModels ?? <String>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'cachedModels': cachedModels,
        'cachedModelsAt': cachedModelsAt,
        'showAllModels': showAllModels,
      };

  factory ApiProfile.fromJson(Map<dynamic, dynamic> j) => ApiProfile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '未命名').toString(),
        baseUrl: (j['baseUrl'] ?? 'https://api.openai.com/v1').toString(),
        model: (j['model'] ?? '').toString(),
        cachedModels: j['cachedModels'] is List
            ? (j['cachedModels'] as List).map((e) => e.toString()).toList()
            : <String>[],
        cachedModelsAt: (j['cachedModelsAt'] as num?)?.toInt() ?? 0,
        showAllModels: j['showAllModels'] == true,
      );

  ApiProfile copyWith({String? id, String? name}) => ApiProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        cachedModels: List<String>.of(cachedModels),
        cachedModelsAt: cachedModelsAt,
        showAllModels: showAllModels,
      );

  /// 主机短名，用于列表展示。
  String get hostLabel {
    try {
      final u = Uri.parse(baseUrl);
      return u.host.isEmpty ? baseUrl : u.host;
    } catch (_) {
      return baseUrl;
    }
  }
}

/// 新建配置时的常用预设，只填地址与默认模型，密钥仍需用户自填。
class ProfilePreset {
  final String name;
  final String baseUrl;
  final String model;
  const ProfilePreset(this.name, this.baseUrl, this.model);
}

const List<ProfilePreset> kProfilePresets = [
  ProfilePreset('OpenAI', 'https://api.openai.com/v1', ''),
  ProfilePreset('DeepSeek', 'https://api.deepseek.com/v1', ''),
  ProfilePreset(
      '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', ''),
  ProfilePreset('Moonshot', 'https://api.moonshot.cn/v1', ''),
  ProfilePreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', ''),
  ProfilePreset('Groq', 'https://api.groq.com/openai/v1', ''),
  ProfilePreset('OpenRouter', 'https://openrouter.ai/api/v1', ''),
  ProfilePreset('Ollama 本地', 'http://localhost:11434/v1', ''),
  ProfilePreset('自定义', '', ''),
];

// ---------------------------------------------------------------- Token 用量

/// 单次请求的 token 消耗。estimated=true 表示接口未返回 usage，由本地估算得出。
class TokenUsage {
  final int prompt;
  final int completion;
  final bool estimated;

  /// 本次请求里**命中了服务端提示词缓存**的输入 token 数。
  ///
  /// OpenAI 放在 `usage.prompt_tokens_details.cached_tokens`；Anthropic 用
  /// `cache_read_input_tokens`；不少国产网关用 `prompt_cache_hit_tokens`
  /// / `cached_tokens`。这部分 token 通常按 1~2 折计价，是「命中缓存」
  /// 统计与省钱估算的原始数据。接口不返回时为 0。
  final int cached;

  const TokenUsage({
    required this.prompt,
    required this.completion,
    this.estimated = false,
    this.cached = 0,
  });

  int get total => prompt + completion;
  bool get isEmpty => total <= 0;

  /// 有缓存命中（哪怕网关没给 token 明细，也可由本地响应缓存补记）。
  bool get hasCacheHit => cached > 0;

  TokenUsage operator +(TokenUsage o) => TokenUsage(
        prompt: prompt + o.prompt,
        completion: completion + o.completion,
        estimated: estimated || o.estimated,
        cached: cached + o.cached,
      );

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'completion': completion,
        'estimated': estimated,
        if (cached > 0) 'cached': cached,
      };

  factory TokenUsage.fromJson(Map<dynamic, dynamic> j) => TokenUsage(
        prompt: (j['prompt'] as num?)?.toInt() ?? 0,
        completion: (j['completion'] as num?)?.toInt() ?? 0,
        estimated: j['estimated'] == true,
        cached: (j['cached'] as num?)?.toInt() ?? 0,
      );

  /// 兼容 OpenAI / Anthropic / Gemini / Ollama 的常见 usage 字段。
  static TokenUsage? fromApi(Map<dynamic, dynamic> j) {
    final p = _int(j['prompt_tokens']) ??
        _int(j['input_tokens']) ??
        _int(j['prompt_eval_count']) ??
        _int(j['promptTokenCount']) ??
        0;
    final c = _int(j['completion_tokens']) ??
        _int(j['output_tokens']) ??
        _int(j['eval_count']) ??
        _int(j['candidatesTokenCount']) ??
        0;
    final t = _int(j['total_tokens']) ?? _int(j['totalTokenCount']);
    final cached = _cachedTokens(j);
    if (p == 0 && c == 0) {
      if (t == null || t <= 0) return null;
      return TokenUsage(prompt: t, completion: 0, cached: cached);
    }
    return TokenUsage(prompt: p, completion: c, cached: cached);
  }

  /// 把各家「命中缓存」的写法归一成一个数字。
  static int _cachedTokens(Map<dynamic, dynamic> j) {
    final details = j['prompt_tokens_details'];
    final candidates = <dynamic>[
      if (details is Map) details['cached_tokens'],
      j['cache_read_input_tokens'],
      j['prompt_cache_hit_tokens'],
      j['cached_tokens'],
      if (j['usage_details'] is Map)
        (j['usage_details'] as Map)['cached_tokens'],
      if (j['cache_tokens_details'] is Map)
        (j['cache_tokens_details'] as Map)['cached'],
    ];
    for (final v in candidates) {
      if (v is num && v > 0) return v.toInt();
    }
    return 0;
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : null;

  /// 兜底估算：CJK 约 1.6 字符/token，拉丁约 4 字符/token。
  static TokenUsage estimate(String promptText, String completionText) =>
      TokenUsage(
        prompt: _est(promptText),
        completion: _est(completionText),
        estimated: true,
      );

  static int _est(String s) {
    if (s.isEmpty) return 0;
    var cjk = 0;
    for (final r in s.runes) {
      if (r >= 0x2E80 && r <= 0x9FFF) cjk++;
    }
    final other = s.length - cjk;
    return (cjk / 1.6 + other / 4).ceil();
  }

  String get label => '${estimated ? '≈' : ''}$total tok';
}

/// 某一天的用量：按模型分开记，请求数单独记。
///
/// v4.9.3 起用量不再只是「累计 + 今天」两团数字，而是能回答
/// 「今天用了多少、昨天用了多少、哪个模型最贵」——所以按天留桶。
class DayUsage {
  DayUsage();

  final Map<String, TokenUsage> models = {};
  int requests = 0;
  int estimated = 0;

  int get prompt => models.values.fold(0, (a, b) => a + b.prompt);
  int get completion => models.values.fold(0, (a, b) => a + b.completion);
  int get cached => models.values.fold(0, (a, b) => a + b.cached);
  int get total => prompt + completion;
  bool get isEmpty => total <= 0 && requests == 0;

  void add(String model, TokenUsage u) {
    final old = models[model];
    models[model] = old == null ? u : old + u;
    requests++;
    if (u.estimated) estimated++;
  }

  Map<String, dynamic> toJson() => {
        'requests': requests,
        if (estimated > 0) 'estimated': estimated,
        'models': {
          for (final e in models.entries) e.key: e.value.toJson(),
        },
      };

  factory DayUsage.fromJson(Map<dynamic, dynamic> j) {
    final d = DayUsage();
    d.requests = (j['requests'] as num?)?.toInt() ?? 0;
    d.estimated = (j['estimated'] as num?)?.toInt() ?? 0;
    final m = j['models'];
    if (m is Map) {
      m.forEach((k, v) {
        if (v is Map) {
          d.models[k.toString()] =
              TokenUsage.fromJson(Map<dynamic, dynamic>.from(v));
        }
      });
    }
    return d;
  }
}

/// 累计用量：总量、按模型、按天（每天再按模型）。
class TokenStats {
  TokenStats();

  int prompt = 0;
  int completion = 0;
  int requests = 0;
  int estimatedRequests = 0;

  /// 累计命中服务端提示词缓存的输入 token，以及发生命中的请求数。
  int cachedTokens = 0;
  int cacheHitRequests = 0;

  /// 全时段按模型汇总，供概览直接用。
  final Map<String, TokenUsage> byModel = {};

  /// 20261108 → 当天用量。历史里读回来的也在这里，不会因为跨天清零。
  final Map<int, DayUsage> byDay = {};

  int get total => prompt + completion;
  bool get isEmpty => total <= 0 && byDay.isEmpty;

  static int dayOf(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  DayUsage day(int key) => byDay[key] ?? DayUsage();
  DayUsage get today => day(dayOf(DateTime.now()));
  int get todayTotal => today.total;
  int get todayPrompt => today.prompt;
  int get todayCompletion => today.completion;
  int get todayRequests => today.requests;

  /// 有数据的日子，从旧到新。
  List<int> get days {
    final l = byDay.keys.toList()..sort();
    return l;
  }

  void add(TokenUsage? u, {required String model}) {
    if (u == null || u.isEmpty) return;
    final k = dayOf(DateTime.now());
    prompt += u.prompt;
    completion += u.completion;
    requests++;
    if (u.estimated) estimatedRequests++;
    if (u.cached > 0) {
      cachedTokens += u.cached;
      cacheHitRequests++;
    }
    final old = byModel[model];
    byModel[model] = old == null ? u : old + u;
    (byDay[k] ??= DayUsage()).add(model, u);
  }

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'completion': completion,
    'requests': requests,
    if (estimatedRequests > 0) 'estimatedRequests': estimatedRequests,
    if (cachedTokens > 0) 'cachedTokens': cachedTokens,
    if (cacheHitRequests > 0) 'cacheHitRequests': cacheHitRequests,
    'byModel': {
          for (final e in byModel.entries) e.key: e.value.toJson(),
        },
        'days': {
          for (final e in byDay.entries) '${e.key}': e.value.toJson(),
        },
      };

  factory TokenStats.fromJson(Map<dynamic, dynamic> j) {
    final t = TokenStats();
    t.prompt = (j['prompt'] as num?)?.toInt() ?? 0;
    t.completion = (j['completion'] as num?)?.toInt() ?? 0;
    t.requests = (j['requests'] as num?)?.toInt() ?? 0;
    t.estimatedRequests = (j['estimatedRequests'] as num?)?.toInt() ?? 0;
    t.cachedTokens = (j['cachedTokens'] as num?)?.toInt() ?? 0;
    t.cacheHitRequests = (j['cacheHitRequests'] as num?)?.toInt() ?? 0;
    final bm = j['byModel'];
    if (bm is Map) {
      bm.forEach((k, v) {
        if (v is Map) {
          t.byModel[k.toString()] =
              TokenUsage.fromJson(Map<dynamic, dynamic>.from(v));
        }
      });
    }
    final bd = j['days'];
    if (bd is Map) {
      bd.forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null && v is Map) {
          t.byDay[key] = DayUsage.fromJson(Map<dynamic, dynamic>.from(v));
        }
      });
    }
    return t;
  }

  void reset() {
    prompt = 0;
    completion = 0;
    requests = 0;
    estimatedRequests = 0;
    cachedTokens = 0;
    cacheHitRequests = 0;
    byModel.clear();
    byDay.clear();
  }
}

// ---------------------------------------------------------------- 研究工作台

enum ResearchStage {
  idle,
  searching,
  outlining,
  drafting,
  verifying,
  done,
  failed
}

extension ResearchStageX on ResearchStage {
  String get label {
    switch (this) {
      case ResearchStage.idle:
        return '待开始';
      case ResearchStage.searching:
        return '检索资料';
      case ResearchStage.outlining:
        return '拟定大纲';
      case ResearchStage.drafting:
        return '逐节展开';
      case ResearchStage.verifying:
        return '核对引用';
      case ResearchStage.done:
        return '已完成';
      case ResearchStage.failed:
        return '已中断';
    }
  }
}

/// 可保存、命名、切换、对比的 System Prompt 预设。
/// 内容完全由用户掌控；{{变量}} 在发送前由客户端做纯文本插值。
class PromptPreset {
  String id;
  String name;
  String content;
  int updatedAt;
  bool builtin;

  PromptPreset({
    required this.id,
    required this.name,
    required this.content,
    int? updatedAt,
    this.builtin = false,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  static const List<String> varNames = [
    'query',
    'date',
    'time',
    'model',
    'language',
    'sources',
    'tier',
  ];

  static final RegExp _var = RegExp(r'\{\{\s*([a-zA-Z_]+)\s*\}\}');

  /// 提取内容里用到的变量，供 UI 提示。
  static List<String> variablesOf(String text) => _var
      .allMatches(text)
      .map((m) => m.group(1) ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  /// 纯文本插值；未知变量原样保留，不会抛错。
  String render({
    String query = '',
    String model = '',
    String language = '简体中文',
    String sources = '',
    String tier = '',
  }) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final map = <String, String>{
      'query': query,
      'date': date,
      'time': time,
      'model': model,
      'language': language,
      'sources': sources,
      'tier': tier,
    };
    return content.replaceAllMapped(
        _var, (m) => map[m.group(1)] ?? m.group(0) ?? '');
  }

  PromptPreset copy({String? id, String? name}) => PromptPreset(
        id: id ?? 'p_${DateTime.now().microsecondsSinceEpoch}',
        name: name ?? this.name,
        content: content,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        builtin: false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'updatedAt': updatedAt,
        'builtin': builtin,
      };

  factory PromptPreset.fromJson(Map<dynamic, dynamic> j) => PromptPreset(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '未命名预设').toString(),
        content: (j['content'] ?? '').toString(),
        updatedAt: (j['updatedAt'] as num?)?.toInt(),
        builtin: j['builtin'] == true,
      );
}

/// 内置预设：只定义「回答角色与格式」，不含任何绕过模型自身安全机制的内容。
List<PromptPreset> defaultPresets() => [
      PromptPreset(
          id: 'p_standard',
          name: '标准研究',
          content: kDefaultSystemPrompt,
          builtin: true),
      PromptPreset(
          id: 'p_review',
          name: '结构化综述',
          content:
              'You are a rigorous research analyst. Answer in {{language}}. '
              'Structure every answer as: 1) a one-paragraph executive summary, '
              '2) numbered findings with the evidence supporting each, '
              '3) limitations and open questions. When sources are provided, '
              'ground each claim in them and cite as [1], [2]. '
              'Distinguish clearly between what sources state and your inference. '
              'Current date: {{date}}.',
          builtin: true),
      PromptPreset(
          id: 'p_fact',
          name: '事实核查',
          content: 'You are a fact-checking assistant. Answer in {{language}}. '
              'For the claim under review, list each verifiable sub-claim, '
              'label it Supported / Contradicted / Insufficient evidence, '
              'and point to the specific source that decides it. '
              'Never present an unverified claim as established fact. '
              'Cite sources as [1], [2]. Model in use: {{model}}.',
          builtin: true),
      PromptPreset(
          id: 'p_code',
          name: '代码分析',
          content: 'You are a senior code reviewer. Answer in {{language}}. '
              'Focus on correctness, edge cases, complexity and failure modes. '
              'Show minimal reproducible examples and concrete fixes. '
              'Quote file/line references when available. '
              'Do not speculate about code you have not seen.',
          builtin: true),
      PromptPreset(
          id: 'p_brief',
          name: '极简直答',
          content: 'Answer in {{language}}, in the fewest words that remain '
              'accurate. No preamble, no restating the question, no closing '
              'remarks. Prefer a short list over prose when the answer has parts.',
          builtin: true),
    ];

/// 一次生成的完整实验记录：参数、请求体（密钥脱敏）、响应原文、token 消耗。
class ExperimentRecord {
  final String id;
  final int at;
  final String kind; // 'chat' | 'research'
  final String presetName;
  final String model;
  final String tier;
  final String query;
  final Map<String, dynamic> params;
  final String requestBody;
  final String responseRaw;
  final int elapsedMs;
  final String? error;
  final TokenUsage? usage;

  const ExperimentRecord({
    required this.id,
    required this.at,
    required this.kind,
    required this.presetName,
    required this.model,
    required this.tier,
    required this.query,
    required this.params,
    required this.requestBody,
    required this.responseRaw,
    required this.elapsedMs,
    this.error,
    this.usage,
  });

  String get dateLabel =>
      '${DateTime.fromMillisecondsSinceEpoch(at).month.toString().padLeft(2, '0')}-'
      '${DateTime.fromMillisecondsSinceEpoch(at).day.toString().padLeft(2, '0')} '
      '${DateTime.fromMillisecondsSinceEpoch(at).hour.toString().padLeft(2, '0')}:'
      '${DateTime.fromMillisecondsSinceEpoch(at).minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at,
        'kind': kind,
        'presetName': presetName,
        'model': model,
        'tier': tier,
        'query': query,
        'params': params,
        'requestBody': requestBody,
        'responseRaw': responseRaw,
        'elapsedMs': elapsedMs,
        'error': error,
        'usage': usage?.toJson(),
      };

  String toMarkdown() {
    final b = StringBuffer();
    b.writeln('## $dateLabel · $presetName · $model');
    b.writeln('- 类型：$kind / 档位：$tier / 耗时：$elapsedMs ms');
    if (usage != null) {
      b.writeln('- Token：输入 ${usage!.prompt} / 输出 ${usage!.completion} / '
          '合计 ${usage!.total}${usage!.estimated ? '（估算）' : ''}');
    }
    b.writeln('- 提问：$query');
    if (error != null) b.writeln('- 错误：$error');
    b.writeln(
        '\n### 参数\n```json\n${const JsonEncoder.withIndent('  ').convert(params)}\n```');
    b.writeln('\n### 请求体\n```json\n$requestBody\n```');
    b.writeln('\n### 响应原文\n```text\n$responseRaw\n```');
    return b.toString();
  }
}

/// 主题模式：跟随系统 / 固定浅色 / 固定深色。
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.system:
        return '跟随系统';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }

  String get shortLabel {
    switch (this) {
      case AppThemeMode.system:
        return '系统';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }

  String get note {
    switch (this) {
      case AppThemeMode.system:
        return '随 Android 深色模式自动切换，无需手动开关';
      case AppThemeMode.light:
        return '始终使用浅色纸白界面';
      case AppThemeMode.dark:
        return '始终使用深色墨蓝界面';
    }
  }
}

class AppSettings {
  /// 所有连接配置。顶层 baseUrl / apiKey / model 始终是「当前生效配置」的镜像，
  /// 这样其余业务代码无需感知多配置的存在。
  List<ApiProfile> profiles = [];
  String activeProfileId = '';

  String baseUrl = 'https://api.openai.com/v1';
  String apiKey = '';
  /// 全新安装时**不预设任何模型**。以前这里写死 `gpt-4o-mini`，于是设备
  /// 明明一个连接都没配，顶栏却挂着一个既不能选也不能用的 GPT 模型名，
  /// 点开模型列表还是空的。留空后各处统一显示「未配置 / 去添加连接」，
  /// 只有用户真正选定模型（或从旧配置读回来）才会出现模型名。
  String model = '';
  Tier tier = Tier.standard;
  bool deepThinking = false;
  bool webSearch = false;

  /// v3.2 起「无审查模式」这个概念被移除：模型的行为由模型自身决定，
  /// 客户端既不审查也不反审查。researchWorkflow 只控制「深度研究工作流」。
  bool researchWorkflow = false;
  bool ephemeral = false;

  /// 旧字段：仅用于把老配置里的自定义 System Prompt 迁移进预设库。
  String systemPrompt = kDefaultSystemPrompt;

  /// 主题模式默认跟随系统。[darkMode] 保留为只读兼容镜像，避免旧读取路径失效。
  AppThemeMode themeMode = AppThemeMode.system;
  bool get darkMode => themeMode == AppThemeMode.dark;

  /// 全站字号倍率：0.9 / 1.0 / 1.12 / 1.25（见 lang_catalog.dart 的 kFontScales）。
  /// 在 MaterialApp 层通过 textScaler 生效，不改各页写死的字号。
  double fontScale = 1.0;

  // ---- v4.15 主题 ----
  /// 内置主题 id（见 skin.dart 的 kSkinPresets）；'custom' 表示自定义。
  String skinId = 'quiet';

  /// 自定义主色（#RRGGBB）；为空时用默认墨蓝。
  String skinAccent = '';

  /// 自定义画布色（#RRGGBB）；决定「页面」本身的冷暖。
  String skinCanvas = '';

  /// 圆角强度：0.6 硬朗 ~ 1.4 圆润。
  double skinRadius = 1.0;

  /// 界面语言（i18n.dart 的 kUiLangs）。和回答语言 / 识别语言相互独立：
  /// 界面英文、答案中文是很正常的组合。
  String uiLang = 'zh';

  /// 对话语言：AI 用哪种语言回答。`auto` 跟随提问语言。
  String replyLang = 'auto';

  // ---- 研究工作台 ----
  List<PromptPreset> promptPresets = [];
  String activePresetId = '';

  /// 原始输出：回答不做 Markdown 渲染与引用角标转换，等宽原样呈现。
  bool rawOutput = false;
  bool autoRecord = true;

  /// 在流式请求里附加 stream_options.include_usage，向网关索取真实 token 数。
  bool usageTracking = true;

  /// 图片在请求里的发送格式；网关不认标准 data URI 时可切换排查。
  VisionFormat visionFormat = VisionFormat.openai;

  /// 用户已确认「当前模型可能不支持图片」提示后不再重复打扰。
  bool visionHintDismissed = false;

  /// 1 速览 / 2 标准 / 3 深入（决定逐节展开的节数）。
  int researchDepth = 2;

  /// 每百万 token 单价（¥），用于本地估算费用；0 表示不计算。
  double priceInPerM = 0;
  double priceOutPerM = 0;

  // ---- v4.25 命中缓存 ----
  /// 复用完全相同的非流式请求结果（圆桌 / 模拟人生 / 小游戏 / 深度研究）。
  /// 主对话是流式的，永远不受影响。
  bool responseCacheEnabled = true;

  // ---- v4.25 实时价格与计费 ----
  /// 从公开价格表按当前模型名自动匹配单价；关掉则只用手动单价。
  bool priceAuto = false;
  int priceUpdatedAt = 0;
  String priceSource = '';
  String priceMatchedModel = '';
  /// 公开价格表以美元报价，这里换算成人民币显示。
  double usdToCny = 7.2;

  // ---- 人物形象 ----
  /// 形象库：只有用户自己建的形象，没建就是空。
  List<Persona> personas = defaultPersonas();

  /// 全局默认形象 id；空串表示「没有形象」，头像回落到软件图标。
  String activePersonaId = '';

  /// 主界面是否展示人物形象（顶部形象区 / 助手头像）。
  bool personaEnabled = true;

  /// 消息列表顶部是否展示形象条。
  bool showPersonaHeader = true;

  /// 助手气泡是否带小头像。
  bool showBubbleAvatar = true;

  // ---- 语音 ----
  /// 消息下是否显示「朗读」按钮。
  bool ttsEnabled = true;

  /// 朗读引擎 id（见 services/voice_catalog.dart）。
  /// v4.10 起默认微软 Edge 朗读：免密钥、中文音色自然，
  /// 失败会自动回落系统语音，比默认系统 TTS 好听得多。
  String ttsEngineId = 'edge';

  /// 音色：引擎自定义的短名 / voice_id。
  String ttsVoice = '';

  /// 语速倍率，0.5 ~ 2.0。
  double ttsRate = 1.0;

  /// TTS 模型名，OpenAI 兼容通道使用（留空则用 tts-1）。
  String ttsModel = '';

  /// 自定义 TTS 根地址；空表示跟随当前连接。
  String ttsBaseUrl = '';

  /// 回答完成后自动朗读。
  bool autoSpeak = false;

  /// v4.3 顶栏静音开关：只决定是否出声，不清空任何语音引擎配置。
  /// 手动点朗读会自动解除静音，避免「点了没反应」。
  bool voiceMuted = false;

  /// 语音输入引擎 id。
  /// v4.10 起默认「在线 Whisper（免密钥）」：本地 Vosk 小模型没有标点、
  /// 错字多，是「识别不准」的根因；OVH 的公开端点免密钥、自带标点。
  /// 要完全离线时在设置里切回内置离线识别。
  String sttEngineId = 'ovh-whisper';
  String sttModel = '';
  String sttBaseUrl = '';

  /// v4.11：说完静音自动停止识别，并把结果**放进输入框**。
  ///
  /// 语音识别一律不替用户按发送键：识别错一两个字是常态，必须先让人
  /// 看一眼、改一下，再自己点发送。旧的 `sttAutoSend`（识别完直接发）
  /// 已移除，旧配置里的同名键会被忽略，避免升级后仍旧自动发出去。
  bool sttAutoStopOnSilence = true;

  /// 朗读 / 识别语言，BCP-47。
  String voiceLang = 'zh-CN';

  // ---- v4.4 语音输入增强 ----
  /// 长按语音键 = 按住说话（松手识别 / 上滑取消）；关掉则仅保留点击式。
  bool holdToTalk = true;

  /// 端侧离线优先：默认关闭。只在系统确认支持离线识别、且用户显式开启时启用。
  bool sttPreferOffline = false;

  /// 本地识别不可用 / 无结果时，自动依次回落到系统在线识别与云端引擎。
  bool sttAutoFallback = true;

  /// 说完自动收尾的静音时长（毫秒），越短越跟手。
  int sttSilenceMs = 700;

  /// 语音引擎密钥：只进加密仓，**不写入设置快照**。
  String voiceTtsKey = '';
  String voiceSttKey = '';

  // ---- 设备智能体（v4.7）----
  /// 总开关：默认关闭。只有打开它，模型才会拿到本机工具并可能真正执行动作。
  /// 「了解设备」是只读的，随时可用；「真干活」必须由用户显式授权。
  bool agentEnabled = false;

  /// 每个非只读动作都先在界面上请用户点「允许」，默认开启。
  bool agentConfirmEach = true;

  /// 四类授权，默认只放开「沙箱内文件与脚本」——它已被独立工作区、
  /// 覆盖备份、回收站三重保护；会跳出本应用或写入系统数据的都不放开。
  bool agentAllowWorkspace = true;
  bool agentAllowExternal = false;
  bool agentAllowSystem = false;
  bool agentAllowNetwork = false;

  /// v4.25 新增：设备清理与全盘文件查找。属于高敏感能力，默认关闭。
  bool agentAllowDevice = false;

  /// 权限档位：0 少量 / 1 标准 / 2 完全。UI 上一键切换下面五组授权，
  /// 用户仍能逐项微调；微调后档位会自动回落到「自定义」(-1)。
  int agentPermissionLevel = 1;

  /// 一次发送里最多执行几步工具调用，防止模型陷入循环（1~8）。
  int agentMaxSteps = 4;

  /// 用户已读过风险说明，不再重复弹提示。
  bool agentRiskAck = false;

  static const int kPermMinimal = 0;
  static const int kPermStandard = 1;
  static const int kPermFull = 2;
  static const int kPermCustom = -1;

  /// 档位名称（中文原文，交给 t() 翻译）。
  static String permissionLabel(int level) => switch (level) {
        kPermMinimal => '少量权限',
        kPermStandard => '标准权限',
        kPermFull => '完全权限',
        _ => '自定义',
      };

  /// 档位说明：切换前就能看清这一档到底能做什么。
  static String permissionNote(int level) => switch (level) {
        kPermMinimal => '只读本机信息、已装应用与文件清单；不写任何数据，不调起其它应用。',
        kPermStandard =>
          '在少量权限基础上，允许隔离工作区读写与任务脚本、打开应用与网页、分享与剪贴板。',
        kPermFull => '开放全部能力：日历与闹钟、网页抓取，以及设备缓存清理与可访问文件删除。',
        _ => '已手动调整单项授权，不对应任何预设档位。',
      };

  /// 一键套用档位。只改授权，不动「每次确认」与「总开关」——
  /// 完全权限也不等于静默执行，危险动作仍会逐条弹确认。
  void applyPermissionLevel(int level) {
    if (level != kPermMinimal && level != kPermStandard && level != kPermFull) {
      agentPermissionLevel = kPermCustom;
      return;
    }
    agentPermissionLevel = level;
    agentAllowWorkspace = level >= kPermStandard;
    agentAllowExternal = level >= kPermStandard;
    agentAllowSystem = level >= kPermFull;
    agentAllowNetwork = level >= kPermFull;
    agentAllowDevice = level >= kPermFull;
  }

  /// 单项开关被手动拨过后，档位标记为自定义。
  void markCustomPermission() => agentPermissionLevel = kPermCustom;

  int _inferPermissionLevel() {
    if (!agentAllowWorkspace &&
        !agentAllowExternal &&
        !agentAllowSystem &&
        !agentAllowNetwork &&
        !agentAllowDevice) {
      return kPermMinimal;
    }
    if (agentAllowWorkspace &&
        agentAllowExternal &&
        agentAllowSystem &&
        agentAllowNetwork &&
        agentAllowDevice) {
      return kPermFull;
    }
    if (agentAllowWorkspace &&
        agentAllowExternal &&
        !agentAllowSystem &&
        !agentAllowNetwork &&
        !agentAllowDevice) {
      return kPermStandard;
    }
    return kPermCustom;
  }

  void ensurePersonas() {
    // v4.9.2：内置形象一律不进列表——包括旧版那条「不使用形象」占位。
    // 用户自建的形象（builtin = false）原样保留。
    personas.removeWhere((p) => p.builtin);
    // 选中的形象被删了就回落到第一个自建形象；一个都没建就留空。
    if (!personas.any((p) => p.id == activePersonaId)) {
      activePersonaId = personas.isEmpty ? '' : personas.first.id;
    }
  }

  Persona get activePersona => personaById(activePersonaId) ?? nonePersona();

  Persona? personaById(String id) {
    for (final p in personas) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 会话可单独指定形象；为空或已删除时回落到全局默认。
  Persona personaFor(String conversationPersonaId) =>
      personaById(conversationPersonaId) ?? activePersona;

  /// 旧版「单一搜索源」字段：仅用于读取旧配置并迁移，运行时不再作为检索依据。
  SearchProvider searchProvider = SearchProvider.tavily;
  String searchKey = '';
  String searchEndpoint = SearchProvider.tavily.endpoint;
  String searchCx = '';
  int searchCount = 5;

  /// 可同时启用的多个搜索源（按枚举名存储）。
  List<String> enabledSources = [SearchProvider.tavily.name];

  /// 每个源独立的配置：name -> {key, endpoint, cx}。
  Map<String, Map<String, String>> sourceCfg = {};

  String openApiUrl = '';
  bool pluginEnabled = false;

  /// 从 /v1/models 自动拉取的模型列表（本地缓存，冷启动即可用）。
  List<String> cachedModels = [];
  int cachedModelsAt = 0;
  bool showAllModels = false;

  // ------------------------------------------------------------ 预设库

  void ensurePresets() {
    if (promptPresets.isEmpty) {
      promptPresets = defaultPresets();
      // 老版本的自定义提示词无损迁移为第一份可编辑预设。
      if (systemPrompt.trim().isNotEmpty &&
          systemPrompt.trim() != kDefaultSystemPrompt) {
        promptPresets.insert(
          0,
          PromptPreset(id: 'p_migrated', name: '我的提示词', content: systemPrompt),
        );
      }
    }
    if (!promptPresets.any((p) => p.id == activePresetId)) {
      activePresetId = promptPresets.first.id;
    }
  }

  PromptPreset get activePreset {
    if (promptPresets.isEmpty) return defaultPresets().first;
    return promptPresets.firstWhere(
      (p) => p.id == activePresetId,
      orElse: () => promptPresets.first,
    );
  }

  PromptPreset? presetById(String id) {
    for (final p in promptPresets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 编辑当前预设内容时同步旧镜像字段，保证任何遗留读取路径一致。
  void setPresetContent(String v) {
    final p = activePreset;
    p.content = v;
    p.updatedAt = DateTime.now().millisecondsSinceEpoch;
    systemPrompt = v;
  }

  int get sectionCount {
    switch (researchDepth) {
      case 1:
        return 2;
      case 3:
        return 6;
      default:
        return 4;
    }
  }

  // ------------------------------------------------------------ 搜索源多选

  List<SearchProvider> get activeSources {
    final out = <SearchProvider>[];
    for (final n in enabledSources) {
      for (final p in SearchProvider.values) {
        if (p.name == n && !out.contains(p)) out.add(p);
      }
    }
    return out;
  }

  /// 是否真正会发起联网检索。
  ///
  /// 总开关与「至少一个已启用搜索源」必须同时成立。任何一处为 false 时，
  /// 界面不得出现任何联网 / 检索字样，也不得发起任何检索请求。
  /// 所有涉及联网的判断统一走这里，避免状态栏与真实行为不一致。
  bool get searchActive => webSearch && activeSources.isNotEmpty;

  bool isSourceEnabled(SearchProvider p) => enabledSources.contains(p.name);

  void setSourceEnabled(SearchProvider p, bool on) {
    if (on) {
      if (!enabledSources.contains(p.name)) enabledSources.add(p.name);
    } else {
      enabledSources.remove(p.name);
    }
  }

  String sourceKey(SearchProvider p) =>
      sourceCfg[p.name]?['key'] ??
      (p.name == searchProvider.name ? searchKey : '');

  String sourceEndpoint(SearchProvider p) {
    final v = sourceCfg[p.name]?['endpoint'] ?? '';
    if (v.isNotEmpty) return v;
    if (p.name == searchProvider.name && searchEndpoint.isNotEmpty) {
      return searchEndpoint;
    }
    return p.endpoint;
  }

  String sourceCx(SearchProvider p) =>
      sourceCfg[p.name]?['cx'] ??
      (p.name == searchProvider.name ? searchCx : '');

  void setSourceCfg(SearchProvider p,
      {String? key, String? endpoint, String? cx}) {
    final m = <String, String>{};
    final old = sourceCfg[p.name];
    if (old != null) m.addAll(old);
    if (key != null) m['key'] = key;
    if (endpoint != null) m['endpoint'] = endpoint;
    if (cx != null) m['cx'] = cx;
    sourceCfg[p.name] = m;
  }

  Map<String, dynamic> toJson() => {
        // 先固化当前镜像到激活配置，避免任何写路径漏同步。
        'profiles': (() {
          syncActive();
          return profiles.map((p) => p.toJson()).toList();
        })(),
        'activeProfileId': activeProfileId,
        'baseUrl': baseUrl,
        'model': model,
        'tier': tier.name,
        'deepThinking': deepThinking,
        // v3.1 起只写新字段：旧版持久化的 webSearch 不再被读取，
        // 避免覆盖安装后继承到「用户以为关着」的联网状态。
        'webSearchV2': webSearch,
        // v3.2：不再写旧 researchMode（无审查语义已移除）。
        'researchWorkflow': researchWorkflow,
        'rawOutput': rawOutput,
        'autoRecord': autoRecord,
        'usageTracking': usageTracking,
        'visionFormat': visionFormat.name,
        'visionHintDismissed': visionHintDismissed,
        'researchDepth': researchDepth,
        'priceInPerM': priceInPerM,
        'priceOutPerM': priceOutPerM,
        'responseCacheEnabled': responseCacheEnabled,
        'priceAuto': priceAuto,
        'priceUpdatedAt': priceUpdatedAt,
        'priceSource': priceSource,
        'priceMatchedModel': priceMatchedModel,
        'usdToCny': usdToCny,
        'personas': personas.map((p) => p.toJson()).toList(),
        'activePersonaId': activePersonaId,
        'personaEnabled': personaEnabled,
        'showPersonaHeader': showPersonaHeader,
        'showBubbleAvatar': showBubbleAvatar,
        'ttsEnabled': ttsEnabled,
        'ttsEngineId': ttsEngineId,
        'ttsVoice': ttsVoice,
        'ttsRate': ttsRate,
        'ttsModel': ttsModel,
        'ttsBaseUrl': ttsBaseUrl,
        'autoSpeak': autoSpeak,
        'voiceMuted': voiceMuted,
        'sttEngineId': sttEngineId,
        'sttModel': sttModel,
        'sttBaseUrl': sttBaseUrl,
        'sttAutoStopOnSilence': sttAutoStopOnSilence,
        'voiceLang': voiceLang,
        'holdToTalk': holdToTalk,
        'sttPreferOffline': sttPreferOffline,
        'sttAutoFallback': sttAutoFallback,
        'sttSilenceMs': sttSilenceMs,
        'promptPresets': promptPresets.map((p) => p.toJson()).toList(),
        'activePresetId': activePresetId,
        'ephemeral': ephemeral,
        'systemPrompt': systemPrompt,
        'themeMode': themeMode.name,
        'darkMode': darkMode,
        'fontScale': fontScale,
        'skinId': skinId,
        'skinAccent': skinAccent,
        'skinCanvas': skinCanvas,
        'skinRadius': skinRadius,
        'uiLang': uiLang,
        'replyLang': replyLang,
        'searchProvider': searchProvider.name,
        'searchKey': searchKey,
        'searchEndpoint': searchEndpoint,
        'searchCx': searchCx,
        'searchCount': searchCount,
        'enabledSources': enabledSources,
        'sourceCfg': sourceCfg,
        'openApiUrl': openApiUrl,
        'pluginEnabled': pluginEnabled,
        'cachedModels': cachedModels,
        'cachedModelsAt': cachedModelsAt,
        'showAllModels': showAllModels,
        // ---- 设备智能体 ----
        'agentEnabled': agentEnabled,
        'agentConfirmEach': agentConfirmEach,
        'agentAllowWorkspace': agentAllowWorkspace,
        'agentAllowExternal': agentAllowExternal,
        'agentAllowSystem': agentAllowSystem,
        'agentAllowNetwork': agentAllowNetwork,
        'agentAllowDevice': agentAllowDevice,
        'agentPermissionLevel': agentPermissionLevel,
        'agentMaxSteps': agentMaxSteps,
        'agentRiskAck': agentRiskAck,
        // 语音默认值迁移标记：只迁移一次，之后用户显式选离线会被保留。
        'sttMigratedV47': true,
        'sttMigratedV48': true,
        'voiceMigratedV410': true,
      };

  void load(Map<String, dynamic> j) {
    baseUrl = (j['baseUrl'] ?? baseUrl).toString();
    model = (j['model'] ?? model).toString();
    tier =
        Tier.values.firstWhere((e) => e.name == j['tier'], orElse: () => tier);
    deepThinking = j['deepThinking'] == true;
    // 不读旧字段 'webSearch'：升级到 v3.1 后一律默认关闭，
    // 由用户在工具抽屉显式重新开启。开启后写的是 webSearchV2。
    webSearch = j['webSearchV2'] == true;
    // 旧 researchMode 一律不读：升级到 v3.2 后研究工作流默认关闭。
    researchWorkflow = j['researchWorkflow'] == true;
    rawOutput = j['rawOutput'] == true;
    autoRecord = j['autoRecord'] != false;
    usageTracking = j['usageTracking'] != false;
    visionFormat = VisionFormat.values.firstWhere(
      (e) => e.name == j['visionFormat'],
      orElse: () => VisionFormat.openai,
    );
    visionHintDismissed = j['visionHintDismissed'] == true;
    researchDepth = (j['researchDepth'] as num?)?.toInt().clamp(1, 3) ?? 2;
    priceInPerM = (j['priceInPerM'] as num?)?.toDouble() ?? 0;
    priceOutPerM = (j['priceOutPerM'] as num?)?.toDouble() ?? 0;
    responseCacheEnabled = j['responseCacheEnabled'] != false;
    priceAuto = j['priceAuto'] == true;
    priceUpdatedAt = (j['priceUpdatedAt'] as num?)?.toInt() ?? 0;
    priceSource = (j['priceSource'] ?? '').toString();
    priceMatchedModel = (j['priceMatchedModel'] ?? '').toString();
    usdToCny = ((j['usdToCny'] as num?)?.toDouble() ?? 7.2).clamp(0.1, 100.0);

    // 人物形象：只保留用户自建的形象，读入时丢掉旧版预置人设和
    // v4.8 那条「不使用形象」占位——没有形象就是空列表。
    personas = j['personas'] is List
        ? (j['personas'] as List)
            .whereType<Map>()
            .map((m) => Persona.fromJson(Map<dynamic, dynamic>.from(m)))
            .where((p) => p.id.isNotEmpty && !p.builtin)
            .toList()
        : <Persona>[];
    activePersonaId = (j['activePersonaId'] ?? activePersonaId).toString();
    if (j.containsKey('personaEnabled')) {
      personaEnabled = j['personaEnabled'] == true;
    }
    if (j.containsKey('showPersonaHeader')) {
      showPersonaHeader = j['showPersonaHeader'] == true;
    }
    if (j.containsKey('showBubbleAvatar')) {
      showBubbleAvatar = j['showBubbleAvatar'] == true;
    }
    // 语音：旧配置没有这些字段时用「系统语音 + 关闭自动朗读」的保守默认，
    // 不主动帮用户花钱，也不在没有权限时弹窗。
    ttsEnabled = j['ttsEnabled'] != false;
    ttsEngineId = (j['ttsEngineId'] ?? ttsEngineId).toString();
    ttsVoice = (j['ttsVoice'] ?? '').toString();
    ttsRate = ((j['ttsRate'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0);
    ttsModel = (j['ttsModel'] ?? '').toString();
    ttsBaseUrl = (j['ttsBaseUrl'] ?? '').toString();
    autoSpeak = j['autoSpeak'] == true;
    // 旧配置没有该字段时默认不静音，升级后朗读行为不变。
    voiceMuted = j['voiceMuted'] == true;
    sttEngineId = (j['sttEngineId'] ?? sttEngineId).toString();
    // v4.8 一次性迁移：系统识别在不少国产 ROM 上根本没有可用服务，
    // 「一个都不能用」就是这么来的。统一换成内置离线引擎；
    // 用户之后手动选回系统在线会保留自己的选择。
    if (j['sttMigratedV48'] != true &&
        (sttEngineId == 'system' || sttEngineId == 'system-offline')) {
      sttEngineId = 'vosk-cn';
    }
    // v4.10：默认换成免密钥在线 Whisper + 微软朗读。只迁移一次，
    // 之后用户自己选回离线 / 系统语音就尊重选择。
    if (j['voiceMigratedV410'] != true) {
      if (sttEngineId == 'vosk-cn') sttEngineId = 'ovh-whisper';
      if (ttsEngineId == 'system') ttsEngineId = 'edge';
    }
    sttModel = (j['sttModel'] ?? '').toString();
    sttBaseUrl = (j['sttBaseUrl'] ?? '').toString();
    // 旧字段 sttAutoSend 不再读取：无论老配置里是 true 还是 false，
    // 升级后都走「先回填输入框、确认后再发」这一条路径。
    sttAutoStopOnSilence = j['sttAutoStopOnSilence'] != false;
    voiceLang = (j['voiceLang'] ?? 'zh-CN').toString();
    // v4.4 新增：老配置缺字段时保持「本地优先 + 按住说话 + 自动回落」，
    // 静音时长夹在 300~3000ms，防止手改 JSON 写入离谱值。
    holdToTalk = j['holdToTalk'] != false;
    // 离线优先默认关：只有用户显式开过才启用，避免默认路径直接失败。
    sttPreferOffline = j['sttPreferOffline'] == true;
    sttAutoFallback = j['sttAutoFallback'] != false;
    sttSilenceMs =
        ((j['sttSilenceMs'] as num?)?.toInt() ?? 700).clamp(300, 3000);
    ensurePersonas();
    ephemeral = j['ephemeral'] == true;
    systemPrompt = (j['systemPrompt'] ?? systemPrompt).toString();
    // 主题：新版三档；旧版只有 darkMode 二值开关。升级后默认跟随系统，
    // 但用户此前明确开过深色时保留深色，避免覆盖安装后界面突然变亮。
    final rawMode = j['themeMode'];
    if (rawMode is String) {
      themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == rawMode,
        orElse: () => AppThemeMode.system,
      );
    } else {
      themeMode =
          j['darkMode'] == true ? AppThemeMode.dark : AppThemeMode.system;
    }
    // 字号：只接受 0.85–1.3，避免坏配置把界面撑爆或缩到看不清。
    fontScale =
        ((j['fontScale'] as num?)?.toDouble() ?? 1.0).clamp(0.85, 1.4);
    skinId = (j['skinId'] ?? skinId).toString();
    skinAccent = (j['skinAccent'] ?? '').toString();
    skinCanvas = (j['skinCanvas'] ?? '').toString();
    skinRadius = ((j['skinRadius'] as num?)?.toDouble() ?? 1.0).clamp(0.6, 1.4);
    uiLang = (j['uiLang'] ?? uiLang).toString();
    replyLang = (j['replyLang'] ?? replyLang).toString();

    promptPresets = j['promptPresets'] is List
        ? (j['promptPresets'] as List)
            .whereType<Map>()
            .map((m) => PromptPreset.fromJson(Map<dynamic, dynamic>.from(m)))
            .where((p) => p.id.isNotEmpty)
            .toList()
        : <PromptPreset>[];
    activePresetId = (j['activePresetId'] ?? '').toString();
    ensurePresets();
    searchProvider = SearchProvider.values.firstWhere(
        (e) => e.name == j['searchProvider'],
        orElse: () => searchProvider);
    searchKey = (j['searchKey'] ?? '').toString();
    searchEndpoint = (j['searchEndpoint'] ?? searchEndpoint).toString();
    searchCx = (j['searchCx'] ?? '').toString();
    searchCount = (j['searchCount'] as num?)?.toInt() ?? 5;

    // 多选搜索源；旧配置（无 enabledSources）自动迁移为「仅旧主源」。
    enabledSources = j['enabledSources'] is List
        ? (j['enabledSources'] as List)
            .map((e) => e.toString())
            .where((e) => SearchProvider.values.any((p) => p.name == e))
            .toList()
        : <String>[searchProvider.name];
    if (enabledSources.isEmpty) {
      enabledSources = <String>[searchProvider.name];
    }
    sourceCfg = <String, Map<String, String>>{};
    if (j['sourceCfg'] is Map) {
      (j['sourceCfg'] as Map).forEach((k, v) {
        if (v is Map) {
          final m = <String, String>{};
          v.forEach((kk, vv) => m[kk.toString()] = vv.toString());
          sourceCfg[k.toString()] = m;
        }
      });
    }
    // 旧版全局密钥 / 地址迁移到当时的主源，避免升级后配置丢失。
    sourceCfg.putIfAbsent(
        searchProvider.name,
        () => {
              'key': searchKey,
              'endpoint': searchEndpoint,
              'cx': searchCx,
            });

    openApiUrl = (j['openApiUrl'] ?? '').toString();
    pluginEnabled = j['pluginEnabled'] == true;
    cachedModels = j['cachedModels'] is List
        ? (j['cachedModels'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    cachedModelsAt = (j['cachedModelsAt'] as num?)?.toInt() ?? 0;
    showAllModels = j['showAllModels'] == true;

    // ---- 设备智能体 ----
    // 旧配置没有这些字段时一律保持「关闭 + 每次确认 + 只授权沙箱文件」，
    // 覆盖安装不会突然获得打开应用或写系统数据的权限。
    agentEnabled = j['agentEnabled'] == true;
    agentConfirmEach = j['agentConfirmEach'] != false;
    agentAllowWorkspace = j['agentAllowWorkspace'] != false;
    agentAllowExternal = j['agentAllowExternal'] == true;
    agentAllowSystem = j['agentAllowSystem'] == true;
    agentAllowNetwork = j['agentAllowNetwork'] == true;
    agentAllowDevice = j['agentAllowDevice'] == true;
    agentMaxSteps = ((j['agentMaxSteps'] as num?)?.toInt() ?? 4).clamp(1, 8);
    agentRiskAck = j['agentRiskAck'] == true;
    // 旧配置没有档位字段：从已保存的授权反推，避免升级后界面显示
    // 「标准权限」却实际没打开对应开关，也绝不借升级偷偷放开新权限。
    final savedLevel = j['agentPermissionLevel'];
    if (savedLevel is num) {
      final v = savedLevel.toInt();
      agentPermissionLevel = v < -1 ? -1 : (v > 2 ? 2 : v);
    } else {
      agentPermissionLevel = _inferPermissionLevel();
    }

    // ---- 多连接配置 ----
    // 旧版只有一份全局连接：无损迁移为「默认连接」，用户不需要重新填写。
    final raw = j['profiles'];
    if (raw is List && raw.isNotEmpty) {
      profiles = raw
          .whereType<Map>()
          .map((m) => ApiProfile.fromJson(Map<dynamic, dynamic>.from(m)))
          .where((p) => p.id.isNotEmpty)
          .toList();
    }
    if (profiles.isEmpty) {
      profiles = <ApiProfile>[
        ApiProfile(
          id: 'default',
          name: '默认连接',
          baseUrl: baseUrl,
          model: model,
          cachedModels: List<String>.of(cachedModels),
          cachedModelsAt: cachedModelsAt,
          showAllModels: showAllModels,
        )
      ];
    }
    activeProfileId = (j['activeProfileId'] ?? '').toString();
    if (!profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = profiles.first.id;
    }
    activate(activeProfileId);
  }

  // ------------------------------------------------------------ 连接配置档

  ApiProfile get activeProfile => profiles.firstWhere(
        (p) => p.id == activeProfileId,
        orElse: () => profiles.isNotEmpty ? profiles.first : _fallback(),
      );

  ApiProfile _fallback() => ApiProfile(id: 'default', name: '默认连接');

  ApiProfile? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 把当前生效值写回激活配置（密钥单独加密存，不进设置 JSON）。
  void syncActive() {
    if (profiles.isEmpty) return;
    final p = activeProfile;
    p.baseUrl = baseUrl;
    p.model = model;
    p.apiKey = apiKey;
    p.cachedModels = List<String>.of(cachedModels);
    p.cachedModelsAt = cachedModelsAt;
    p.showAllModels = showAllModels;
  }

  /// 切换配置：把目标配置的完整快照载入为当前生效值。
  void activate(String id) {
    if (profiles.isEmpty) return;
    final p = profileById(id);
    if (p == null) return;
    activeProfileId = id;
    baseUrl = p.baseUrl;
    apiKey = p.apiKey;
    model = p.model;
    cachedModels = List<String>.of(p.cachedModels);
    cachedModelsAt = p.cachedModelsAt;
    showAllModels = p.showAllModels;
  }

  /// 供 SecureStore 读写：id -> 明文 Key。
  Map<String, String> profileKeys() => {
        for (final p in profiles) p.id: p.apiKey,
        // 语音引擎密钥走同一条加密通道，用保留 id 区分，不会冒出一个假配置。
        if (voiceTtsKey.isNotEmpty) '_voice_tts': voiceTtsKey,
        if (voiceSttKey.isNotEmpty) '_voice_stt': voiceSttKey,
      };

  void applyProfileKeys(Map<String, String> keys) {
    for (final p in profiles) {
      p.apiKey = keys[p.id] ?? '';
    }
    voiceTtsKey = keys['_voice_tts'] ?? voiceTtsKey;
    voiceSttKey = keys['_voice_stt'] ?? voiceSttKey;
    // 重新对齐当前镜像里的 Key。
    apiKey = activeProfile.apiKey;
  }

  String encode() => jsonEncode(toJson());
}
