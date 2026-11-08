import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/models.dart';
import '../services/agent_tools.dart';
import '../services/agent_workspace.dart';
import '../services/device_bridge.dart';
import '../services/file_extract.dart';
import '../services/history_store.dart';
import '../services/lang_catalog.dart';
import '../services/llm_client.dart';
import '../services/model_catalog.dart';
import '../services/model_probe.dart';
import '../services/plugin_service.dart';
import '../services/search_service.dart';
import '../services/think_splitter.dart';
import '../services/secure_store.dart';
import '../services/speech_model.dart';
import '../services/voice_catalog.dart';
import '../services/voice_service.dart';

/// 句读 / 换行边界：攒到这类字符时优先成组输出，读起来是一小段而不是逐字。
final RegExp kStreamBoundary = RegExp(r'[\n。！？!?；;，,、：:）)\]】}\s]$');

/// 批量刷新判定，抽成纯函数便于回归测试。
/// 首段攒 4 字、之后 8 字；遇句读或等满 70ms 输出；超 40 字或 140ms 必出。
bool shouldFlushStream(String pending, int ageMs, bool first) {
  final atBoundary = kStreamBoundary.hasMatch(pending);
  final enough = pending.length >= (first ? 4 : 8);
  return ageMs >= 140 ||
      pending.length >= 40 ||
      (enough && (atBoundary || ageMs >= 70));
}

/// 单个会话的流式上下文。v3.7 前这些是 AppState 全局单例，
/// 因此「A 会话生成中切到 B」会串状态、且两个会话并行生成时会互相覆盖缓冲。
/// 现在按会话 id 各存一份，支持后台会话继续生成、前台会话干净可用。
class _StreamCtx {
  CancelToken? cancel;
  Timer? flushTimer;
  final StringBuffer buf = StringBuffer();
  ChatMessage? target;
  int lastFlush = 0;
  bool firstFlush = true;
  final Stopwatch sw = Stopwatch();

  void dispose() {
    flushTimer?.cancel();
    flushTimer = null;
    cancel = null;
    target = null;
  }
}

/// 全局状态：会话、设置、附件、生成流程、插件与研究模式。
/// 流式文本只驱动 [ChatMessage] 自身的 ChangeNotifier，避免整列表重建。
///
/// v3.7：生成状态 / 状态文案 / 草稿 / 待发附件全部下沉到 [Conversation]，
/// 通过同名 getter 代理到当前活动会话；流上下文按会话隔离。
/// 这样切换或新建会话后，各会话互不串台，且允许并行生成。
class AppState extends ChangeNotifier {
  final SecureStore store = SecureStore();
  final LlmClient llm = LlmClient();
  final SearchService searchSvc = SearchService();

  late AppSettings settings;
  List<Conversation> conversations = [];
  String activeId = '';
  bool ready = false;
  String? globalError;

  OpenApiPlugin? plugin;
  String? pluginError;

  bool modelsLoading = false;
  String? modelsError;
  bool _modelsAutoFetched = false;
  bool get modelsAutoFetched => _modelsAutoFetched;

  /// 累计 token 用量（按天 / 按模型，随历史一起落盘）。
  TokenStats tokenStats = TokenStats();

  /// 会话历史本地存储（文件，不进 SharedPreferences）。测试可替换。
  HistoryStore historyStore = HistoryStore();

  Timer? _historyTimer;
  AppLifecycleListener? _lifecycle;
  bool _historyFlushed = false;

  /// 最近的实验记录，最多保留 120 条。
  final List<ExperimentRecord> records = [];

  ResearchStage researchStage = ResearchStage.idle;
  String researchTopic = '';
  String researchReport = '';
  int researchStep = 0;
  int researchTotal = 0;
  bool get researching =>
      researchStage != ResearchStage.idle &&
      researchStage != ResearchStage.done &&
      researchStage != ResearchStage.failed;

  // ---- 设备智能体（v4.7）----
  /// 本机信息快照。冷启动先给一份占位，随后由 [_initAgent] 静默换成真机数据。
  DeviceInfo deviceInfo = DeviceInfo.fallback();

  /// 隔离工作区；未初始化完成前为 null，此时不注入任何需要执行的工具。
  AgentWorkspace? agentWorkspace;

  /// 最近的工具执行审计日志（从工作区日志文件读回）。
  List<AgentLogEntry> agentLog = [];

  /// 当前等待用户确认的动作；非模态确认条据此渲染。
  AgentAction? pendingAgentAction;
  Completer<bool>? _agentApproval;

  AgentGrant get agentGrant => AgentGrant(
        workspace: settings.agentAllowWorkspace,
        external: settings.agentAllowExternal,
        system: settings.agentAllowSystem,
        network: settings.agentAllowNetwork,
      );

  // ---- 端侧离线语音包（v4.8）----
  /// 离线模型状态。首次安装为 missing，下载完成后 ready。
  SpeechModelStatus speechModel = SpeechModelStatus.missing;
  bool speechModelBusy = false;
  double speechModelProgress = 0;
  String speechModelError = '';
  CancelToken? _speechCancel;

  Future<void> refreshSpeechModel({bool notify = true}) async {
    speechModel = await SpeechModel.status();
    if (notify) notifyListeners();
  }

  /// 下载并安装模型。进度写进 [speechModelProgress]，界面直接监听即可。
  Future<bool> downloadSpeechModel() async {
    if (speechModelBusy) return false;
    speechModelBusy = true;
    speechModelProgress = 0;
    speechModelError = '';
    notifyListeners();
    _speechCancel = CancelToken();
    try {
      speechModel = await SpeechModel.download(
        cancelToken: _speechCancel,
        onProgress: (p, _, __) {
          speechModelProgress = p;
          notifyListeners();
        },
      );
      speechModelBusy = false;
      notifyListeners();
      return speechModel.ready;
    } catch (e) {
      speechModelError = e.toString();
      speechModelBusy = false;
      notifyListeners();
      return false;
    } finally {
      _speechCancel = null;
    }
  }

  void cancelSpeechDownload() {
    _speechCancel?.cancel('用户取消');
  }

  Future<void> removeSpeechModel() async {
    await SpeechModel.remove();
    await refreshSpeechModel(notify: false);
    notifyListeners();
  }

  /// 本地缓存的模型列表，冷启动即可渲染，不依赖网络。
  List<ModelInfo> get models =>
      settings.cachedModels.map((e) => ModelInfo(id: e)).toList();

  List<ModelInfo> get chatModels =>
      models.where((m) => settings.showAllModels || m.isChat).toList();

  /// 汇总**所有**连接配置缓存到的模型，供关键词搜索与跨运营商对比。
  /// 活动配置用当前内存快照（可能刚刷新、尚未写回 profile）。
  ModelCatalog get modelCatalog {
    final s = settings;
    // profiles 还没建好时（冷启动读取中、或单测里直接构造 AppState），
    // 也要能用当前缓存的模型搜索，不能让输入台的搜索框空着报「没有命中」。
    if (s.profiles.isEmpty) {
      return ModelCatalog.fromSources([
        ModelSource(
          profileId: s.activeProfileId,
          profileName: s.activeProfile.name,
          modelIds: s.cachedModels,
          active: true,
        ),
      ]);
    }
    return ModelCatalog.fromSources([
      for (final p in s.profiles)
        ModelSource(
          profileId: p.id,
          profileName: p.name,
          modelIds: p.id == s.activeProfileId ? s.cachedModels : p.cachedModels,
          active: p.id == s.activeProfileId,
        ),
    ]);
  }

  /// 选中目录里的模型：若属于别的连接配置，连 Base URL / 密钥一起切过去，
  /// 避免「选了别家模型却仍请求当前网关」。
  Future<void> selectCatalogModel(ModelEntry e) async {
    if (e.profileId.isNotEmpty && e.profileId != settings.activeProfileId) {
      await switchProfile(e.profileId);
    }
    await selectModel(e.id);
  }

  /// 每个会话一份流上下文。会话删除时一并释放，防止泄漏。
  final Map<String, _StreamCtx> _streams = {};
  _StreamCtx _stream(String convId) =>
      _streams.putIfAbsent(convId, () => _StreamCtx());

  /// 惰性兜底：boot 之前或单测里直接构造 AppState 时也不会因空列表崩溃。
  Conversation get active {
    if (conversations.isEmpty) {
      conversations.add(Conversation(id: _id(), title: '新工作台'));
    }
    for (final c in conversations) {
      if (c.id == activeId) return c;
    }
    return conversations.first;
  }

  Conversation? convById(String id) {
    for (final c in conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- 会话级状态的代理：UI 读取代码无需改动，天然随活动会话切换 ----
  bool get generating => active.generating;
  set generating(bool v) => active.generating = v;
  String get status => active.status;
  set status(String v) => active.status = v;
  List<Attachment> get pending => active.draftAttachments;
  set pending(List<Attachment> v) => active.draftAttachments = v;

  /// 输入草稿按会话 id 独立读写；不触发全局重建，避免逐字符刷新整页。
  String draftFor(String convId) => convById(convId)?.draft ?? '';
  void setDraft(String convId, String text) {
    final c = convById(convId);
    if (c != null) c.draft = text;
  }

  /// 程序化预填（空态快捷开场）：递增 seed 让输入栏同步，但不与用户逐字
  /// 输入冲突——输入栏只在 seed 变化时读取一次草稿。
  int draftSeed = 0;
  void prefillDraft(String convId, String text) {
    final c = convById(convId);
    if (c == null) return;
    c.draft = text;
    draftSeed++;
    notifyListeners();
  }

  /// 任意会话是否正在生成（用于研究工作流这类全局互斥判断）。
  bool get anyGenerating => conversations.any((c) => c.generating);

  /// 当前会话生效的人物形象。
  Persona get activePersona => settings.personaFor(active.personaId);
  Persona personaFor(String convId) =>
      settings.personaFor(convById(convId)?.personaId ?? '');

  // ---- 形象库管理 ----

  void setActivePersona(String id) {
    settings.activePersonaId = id;
    apply((_) {});
  }

  /// 当前会话单独指定形象；传空串表示跟随全局默认。
  void setConversationPersona(String convId, String personaId) {
    final c = convById(convId);
    if (c == null) return;
    c.personaId = personaId;
    notifyListeners();
    scheduleHistorySave();
  }

  void updatePersona(String id,
      {String? name,
      String? glyph,
      String? imageB64,
      String? tagline,
      String? roleHint,
      int? tint}) {
    final p = settings.personaById(id);
    if (p == null) return;
    if (name != null) p.name = name;
    if (glyph != null) p.glyph = glyph;
    if (imageB64 != null) p.imageB64 = imageB64;
    if (tagline != null) p.tagline = tagline;
    if (roleHint != null) p.roleHint = roleHint;
    if (tint != null) p.tint = tint;
    apply((_) {});
  }

  String addPersona(String name) {
    final p = Persona(
      id: 'persona_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? '新形象' : name.trim(),
      glyph: '✦',
      tagline: '自定义形象',
    );
    settings.personas.add(p);
    settings.activePersonaId = p.id;
    apply((_) {});
    return p.id;
  }

  /// 删除形象：内置预设不可删；引用了该形象的会话回落到全局默认。
  void deletePersona(String id) {
    final p = settings.personaById(id);
    if (p == null || p.builtin) return;
    settings.personas.removeWhere((e) => e.id == id);
    for (final c in conversations) {
      if (c.personaId == id) c.personaId = '';
    }
    settings.ensurePersonas();
    apply((_) {});
  }

  /// 从相册读取并压缩后的头像字节，写入指定形象。
  void setPersonaAvatar(String id, Uint8List bytes) {
    final p = settings.personaById(id);
    if (p == null) return;
    p.imageB64 = base64Encode(bytes);
    apply((_) {});
  }

  void clearPersonaAvatar(String id) => updatePersona(id, imageB64: '');

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  // ---------------------------------------------------------------- 生命周期

  Future<void> boot() async {
    await store.init();
    settings = AppSettings();
    final saved = store.loadSettings();
    if (saved != null) {
      try {
        settings.load(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } catch (_) {}
    }
    settings.ensurePresets();
    store.setEphemeral(settings.ephemeral);
    // 多配置密钥：旧版单 Key 密文自动落到迁移出来的第一份配置上。
    final keys = store.readProfileKeys();
    if (keys.isNotEmpty &&
        settings.profiles.length == 1 &&
        !keys.containsKey(settings.profiles.first.id)) {
      settings.applyProfileKeys(
          <String, String>{settings.profiles.first.id: keys.values.first});
    } else {
      settings.applyProfileKeys(keys);
    }
    // activate 会重新对齐 apiKey 镜像（load 时密钥尚未注入）。
    settings.activate(settings.activeProfileId);

    final cached = store.loadPluginCache();
    if (cached != null) {
      try {
        plugin = OpenApiPlugin.fromJson(
            Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {}
    }
    await restoreHistory();
    _bindLifecycle();
    ready = true;
    notifyListeners();
    // 首帧渲染后再静默刷新模型列表与本机设备信息，不影响冷启动速度。
    Future.microtask(_autoFetchModels);
    unawaited(_initAgent());
    unawaited(_initSpeechModel());
  }

  Future<void> _initSpeechModel() async {
    await refreshSpeechModel(notify: false);
    notifyListeners();
  }

  // ---------------------------------------------------------- 会话历史持久化

  /// 冷启动恢复：会话、当前会话、用量统计。没有历史才开一个新工作台。
  Future<void> restoreHistory() async {
    HistorySnapshot? snap;
    try {
      snap = await historyStore.load();
    } catch (_) {
      snap = null;
    }
    if (snap != null) {
      conversations = snap.conversations;
      if (snap.activeId.isNotEmpty && convById(snap.activeId) != null) {
        activeId = snap.activeId;
      } else if (conversations.isNotEmpty) {
        activeId = conversations.first.id;
      }
      final u = snap.usage;
      if (u != null) {
        try {
          tokenStats = TokenStats.fromJson(u);
        } catch (_) {}
      }
    }
    if (conversations.isEmpty) _newConversation(silent: true);
  }

  /// 退出 / 切后台时立刻写盘，别等防抖计时器。
  void _bindLifecycle() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(
        onPause: () => unawaited(flushHistory()),
        onDetach: () => unawaited(flushHistory()),
        onInactive: () => unawaited(flushHistory()),
      );
    } catch (_) {
      // 单元测试里没有平台生命周期，忽略即可。
    }
  }

  /// 消息 / 会话变化后延迟落盘：流式输出时每条 token 都写盘会把 IO 打满。
  void scheduleHistorySave() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(flushHistory());
    });
  }

  Future<void> flushHistory() async {
    _historyTimer?.cancel();
    _historyTimer = null;
    if (!_historyFlushed && conversations.isEmpty) return;
    _historyFlushed = true;
    await historyStore.save(HistorySnapshot(
      conversations: conversations,
      activeId: activeId,
      usage: tokenStats.toJson(),
    ));
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// 有凭据（或本地网关）时，启动后自动同步一次可用模型。
  void _autoFetchModels() {
    if (_modelsAutoFetched) return;
    _modelsAutoFetched = true;
    final b = settings.baseUrl;
    final local = RegExp(r'localhost|127\.0\.0\.1|192\.168\.|10\.\d+\.|\[::1\]')
        .hasMatch(b);
    if (settings.apiKey.trim().isEmpty && !local) return;
    refreshModels(silent: true);
  }

  /// 拉取 /models。成功时缓存列表；当前模型已不存在则自动切到首个可用对话模型。
  Future<bool> refreshModels({
    String? baseUrl,
    String? apiKey,
    bool silent = false,
  }) async {
    if (modelsLoading) return false;
    modelsLoading = true;
    modelsError = null;
    notifyListeners();

    final result = await llm.fetchModels(
      baseUrl: (baseUrl ?? settings.baseUrl).trim(),
      apiKey: apiKey ?? settings.apiKey,
    );

    modelsLoading = false;
    if (result.ok) {
      settings.cachedModels = result.models.map((m) => m.id).toList();
      settings.cachedModelsAt = DateTime.now().millisecondsSinceEpoch;
      final usable = result.models.where((m) => m.isChat).toList();
      final preferred = usable.isNotEmpty ? usable : result.models;
      if (!settings.cachedModels.contains(settings.model)) {
        settings.model = preferred.first.id;
      }
      modelsError = null;
      await persist();
    } else {
      modelsError = result.error;
    }
    notifyListeners();
    return result.ok;
  }

  /// 切模型走乐观更新：点下去立刻生效、立刻重建界面，落盘放后台。
  /// 不 await 磁盘写，换模型才不会有一顿；存储层偶发异常也不会把界面卡住。
  Future<void> selectModel(String id) async {
    final v = id.trim();
    if (v.isEmpty || v == settings.model) return;
    apply((s) => s.model = v);
  }

  /// 真发一次最短对话，确认「当前选中的模型 + 当前连接」到底能不能用。
  /// 不写会话、不记 token、不改生成状态；最多 16 个输出 token，
  /// 25 秒硬超时，失败时把 401/404/429 之类翻成中文原因。
  Future<ModelProbe> probeModel([String? modelId]) async {
    final id = (modelId ?? settings.model).trim();
    if (id.isEmpty) {
      return const ModelProbe(ok: false, ms: 0, detail: '还没有选择模型');
    }
    if (settings.baseUrl.trim().isEmpty) {
      return const ModelProbe(ok: false, ms: 0, detail: '还没有填写 API 地址');
    }
    final sw = Stopwatch()..start();
    try {
      final text = await llm
          .complete(LlmRequest(
            baseUrl: settings.baseUrl,
            apiKey: settings.apiKey,
            model: id,
            messages: const [
              {'role': 'user', 'content': '请只回复一个字：好'},
            ],
            maxTokens: 16,
            temperature: 0,
            topP: 1,
            thinkingBudget: 0,
            reasoningEffort: 'low',
            deepThinking: false,
            includeUsage: false,
          ))
          .timeout(const Duration(seconds: 25));
      sw.stop();
      final preview = probeReplyPreview(text);
      return ModelProbe(
        ok: true,
        ms: sw.elapsedMilliseconds,
        detail: preview.isEmpty
            ? '接口连通，但没有返回正文'
            : '响应正常 · $preview',
      );
    } catch (e) {
      sw.stop();
      return ModelProbe(
          ok: false, ms: sw.elapsedMilliseconds, detail: describeProbeError(e));
    }
  }

  /// 设置 JSON 与密钥分开写：Key 永远不进入设置快照。
  Future<void> persist() async {
    await store.saveSettings(settings.encode());
    await store.saveProfileKeys(settings.profileKeys());
  }

  Future<void> patch(void Function(AppSettings s) fn) async {
    fn(settings);
    // 任何设置变更（关总开关、取消全部搜索源、切换配置…）后都做一次校正：
    // 联网已不可用时，状态栏绝不保留「联网 / 检索」字样。
    reconcileStatus(notify: false);
    await persist();
    notifyListeners();
  }

  /// 乐观更新：同步改内存并立即通知 UI，落盘放到后台执行。
  /// 用于开关 / 分段选择这类高频交互——点击瞬间就有视觉反馈，
  /// 不再被两次 await 磁盘写和整页重建拖成「不跟手」。
  void apply(void Function(AppSettings s) fn) {
    fn(settings);
    reconcileStatus(notify: false);
    notifyListeners();
    unawaited(_persistSafe());
  }

  /// 乐观更新的后台落盘：失败也不冒泡，避免打断交互或污染单测。
  Future<void> _persistSafe() async {
    try {
      await persist();
    } catch (_) {}
  }

  /// 让状态文案与「当前是否真的会联网」保持一致。
  void reconcileStatus({bool notify = true}) {
    if (!settings.searchActive && isSearchStatus(status)) {
      status = generating ? '生成中…' : '';
      if (notify) notifyListeners();
    }
  }

  /// 联网总开关专用写入口：关闭的同时立刻清掉任何残留的联网 / 检索文案。
  /// 状态栏可能因上一次请求被中断而停留在旧文案，这里做最后一道防线。
  Future<void> setWebSearch(bool v) async {
    await patch((s) => s.webSearch = v);
  }

  /// 状态文案是否属于「联网检索」范畴，供状态栏做显示前二次校验。
  static bool isSearchStatus(String s) =>
      s.contains('联网') || s.contains('检索') || s.contains('个源');

  Future<void> setApiKey(String key) async {
    settings.apiKey = key.trim();
    settings.syncActive();
    await store.saveProfileKeys(settings.profileKeys());
    notifyListeners();
  }

  // -------------------------------------------------------------- 连接配置档

  /// 切换配置档：先固化当前编辑，再载入目标快照。旧配置完整保留。
  Future<void> switchProfile(String id) async {
    if (id == settings.activeProfileId) return;
    if (settings.profileById(id) == null) return;
    settings.syncActive();
    settings.activate(id);
    await persist();
    notifyListeners();
    // 这条连接还没缓存过模型时静默拉一次：否则用户切过去只看到空列表，
    // 会以为「这条连接没有模型」而不是「还没读过」。
    if (settings.cachedModels.isEmpty && settings.apiKey.trim().isNotEmpty) {
      unawaited(refreshModels(silent: true));
    }
  }

  Future<String> addProfile({
    required String name,
    String baseUrl = '',
    String model = '',
  }) async {
    settings.syncActive();
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    final n = name.trim();
    settings.profiles.add(ApiProfile(
      id: id,
      name: n.isEmpty ? '新连接' : n,
      baseUrl: baseUrl,
      model: model,
    ));
    settings.activate(id);
    await persist();
    notifyListeners();
    return id;
  }

  Future<void> renameProfile(String id, String name) async {
    final p = settings.profileById(id);
    final n = name.trim();
    if (p == null || n.isEmpty) return;
    settings.syncActive();
    p.name = n;
    await persist();
    notifyListeners();
  }

  Future<String> duplicateProfile(String id) async {
    settings.syncActive();
    final src = settings.profileById(id) ?? settings.activeProfile;
    final copy = src.copyWith(
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: '${src.name} 副本',
    );
    settings.profiles.add(copy);
    settings.activate(copy.id);
    await persist();
    notifyListeners();
    return copy.id;
  }

  /// 至少保留一份配置；删除当前激活项时自动切到第一份。
  Future<void> deleteProfile(String id) async {
    if (settings.profiles.length <= 1) return;
    settings.syncActive();
    final wasActive = settings.activeProfileId == id;
    settings.profiles.removeWhere((p) => p.id == id);
    if (wasActive) {
      settings.activate(settings.profiles.first.id);
    }
    await persist();
    notifyListeners();
  }

  Future<void> setEphemeral(bool v) async {
    if (v == settings.ephemeral) return;
    if (v) {
      await store.moveToMemory();
    } else {
      await store.moveToDisk();
    }
    settings.ephemeral = v;
    await persist();
    notifyListeners();
  }

  Future<void> destroyCredentials() async {
    await store.destroy();
    store.setEphemeral(settings.ephemeral);
    settings.apiKey = '';
    for (final p in settings.profiles) {
      p.apiKey = '';
    }
    await persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ 会话

  void _newConversation({bool silent = false}) {
    final c = Conversation(id: _id(), title: '新工作台');
    conversations.insert(0, c);
    activeId = c.id;
    if (!silent) notifyListeners();
    scheduleHistorySave();
  }

  void newConversation() => _newConversation();

  /// 切换会话：只换 activeId。生成状态、状态文案、草稿、附件、流上下文
  /// 都挂在各自会话上，因此切过去是全新干净的一屏；旧会话若在生成则继续
  /// 在后台进行，切回来仍能接着看，互不干扰。
  void switchConversation(String id) {
    if (activeId == id) return;
    activeId = id;
    notifyListeners();
    scheduleHistorySave();
  }

  void renameActive(String title) {
    active.title = title.trim().isEmpty ? '新工作台' : title.trim();
    notifyListeners();
    scheduleHistorySave();
  }

  void deleteConversation(String id) {
    // 删除的会话若还在生成，先取消并释放它的流上下文，避免野流继续写 UI。
    final ctx = _streams.remove(id);
    ctx?.cancel?.cancel('会话已删除');
    ctx?.dispose();
    conversations.removeWhere((c) => c.id == id);
    if (conversations.isEmpty) _newConversation(silent: true);
    if (activeId == id) activeId = conversations.first.id;
    notifyListeners();
    scheduleHistorySave();
  }

  void clearActive() {
    active.messages.clear();
    notifyListeners();
    scheduleHistorySave();
  }

  String transcript() {
    final b = StringBuffer();
    b.writeln('# ${active.title}');
    for (final m in active.messages) {
      b.writeln(
          '\n## ${m.role == Role.user ? '用户' : '助手'} · ${m.at.toIso8601String()}');
      b.writeln(m.content);
      if (m.citations.isNotEmpty) {
        b.writeln('\n引用：');
        for (final c in m.citations) {
          b.writeln('[${c.index}] ${c.title} — ${c.url}');
        }
      }
    }
    return b.toString();
  }

  // ------------------------------------------------------------------ 附件

  void addAttachment(Attachment a) {
    pending.add(a);
    notifyListeners();
  }

  void addAttachments(Iterable<Attachment> list) {
    pending.addAll(list);
    notifyListeners();
  }

  void removeAttachment(String id) {
    pending.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void clearAttachments() {
    pending.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------------ 插件

  Future<void> loadPlugin(String url) async {
    pluginError = null;
    status = '解析 OpenAPI 文档…';
    notifyListeners();
    try {
      final p = await OpenApiPlugin.load(url);
      plugin = p;
      settings.openApiUrl = url;
      settings.pluginEnabled = true;
      await store.savePluginCache(jsonEncode(p.toJson()));
      await persist();
      status = '已加载 ${p.operations.length} 个端点';
    } catch (e) {
      pluginError = e.toString();
      status = '插件加载失败';
    }
    notifyListeners();
  }

  Future<void> removePlugin() async {
    plugin = null;
    pluginError = null;
    settings.openApiUrl = '';
    settings.pluginEnabled = false;
    await store.removePluginCache();
    await persist();
    notifyListeners();
  }

  // ------------------------------------------------------------ 设备智能体

  /// 首帧之后静默加载：设备信息 + 隔离工作区 + 审计日志。
  /// 全是本地 IO，不发起网络请求，不拖慢冷启动。
  Future<void> _initAgent() => refreshAgentData();

  /// 重新读取设备信息、确保工作区就绪并刷新审计日志。设置页可手动触发。
  Future<void> refreshAgentData() async {
    try {
      deviceInfo = await DeviceBridge().info();
      agentWorkspace ??= await AgentWorkspace.open();
      await refreshAgentLog(notify: false);
    } catch (_) {
      // 没有原生通道（单测 / 桌面）时保留 fallback 信息，界面照常可用。
    }
    notifyListeners();
  }

  Future<void> refreshAgentLog({bool notify = true}) async {
    final ws = agentWorkspace;
    agentLog = ws == null ? <AgentLogEntry>[] : await ws.readLog();
    if (notify) notifyListeners();
  }

  /// 每次工具调用都按当前设置重建：授权开关一改，下一轮立即生效。
  AgentRuntime buildAgentRuntime() => AgentRuntime(
        workspace: agentWorkspace!,
        grant: agentGrant,
        deviceInfo: deviceInfo,
        confirm: _confirmAgentAction,
        confirmEach: settings.agentConfirmEach,
      );

  /// 非模态确认：把动作挂到界面上等用户点「允许 / 跳过」，不弹阻塞对话框。
  /// 90 秒无操作自动按「跳过」处理，生成流程不会永久卡住。
  Future<bool> _confirmAgentAction(AgentAction action) async {
    resolveAgentAction(false);
    final c = Completer<bool>();
    _agentApproval = c;
    pendingAgentAction = action;
    notifyListeners();
    try {
      return await c.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );
    } finally {
      pendingAgentAction = null;
      if (identical(_agentApproval, c)) _agentApproval = null;
      notifyListeners();
    }
  }

  void resolveAgentAction(bool allow) {
    final c = _agentApproval;
    if (c != null && !c.isCompleted) c.complete(allow);
  }

  Future<String> clearAgentTrash() async {
    final ws = agentWorkspace;
    if (ws == null) return '工作区尚未就绪';
    final msg = await ws.clearTrash();
    await refreshAgentLog(notify: false);
    notifyListeners();
    return msg;
  }

  // -------------------------------------------------------------- Prompt 组装

  /// 组装最终 System Prompt。设置页的「预览请求体」直接调用它，
  /// 看到的就是真实生效内容：当前预设 + {{变量}} 插值 + 检索/文件/工具上下文。
  /// 客户端不追加任何审查或反审查指令 —— 模型行为由模型与用户自己的预设决定。
  String buildSystemPrompt({
    String query = '',
    String searchContext = '',
    String fileContext = '',
    String sources = '',
    bool withTools = true,
    Persona? persona,
  }) {
    final sys = StringBuffer();
    final langName = replyLangPrompt(settings.replyLang);
    final base = settings.activePreset
        .render(
          query: query,
          model: settings.model,
          language: langName.isEmpty ? '简体中文' : langName,
          sources: sources,
          tier: settings.tier.label,
        )
        .trim();
    sys.writeln(base.isEmpty ? kDefaultSystemPrompt : base);
    // 明确指定对话语言时，用一行短指令兜住模型的自选行为；
    // auto 时完全不追加，避免改变默认表现。
    if (langName.isNotEmpty) {
      sys.writeln('[语言] 用$langName回答（代码、命令、专有名词保持原样）。');
    }
    // 人物形象：名字 + 角色设定作为一段身份说明注入，让形象不只是贴图。
    // 这是普通的角色 / 语气设定，不含任何审查规避意图。
    final p = persona ?? activePersona;
    // 没有形象（名字为空）就完全不注入身份段，别让模型自称「」。
    if (settings.personaEnabled && p.name.trim().isNotEmpty) {
      sys.writeln('[身份] 你的名字是「${p.name}」。'
          '${p.tagline.trim().isEmpty ? '' : '一句话定位：${p.tagline.trim()}。'}'
          '${p.roleHint.trim().isEmpty ? '保持克制、精确、诚实的表达。' : p.roleHint.trim()}');
    }
    if (settings.deepThinking) {
      sys.writeln('[推理指令] 先在内部完成逐步推理与自我校验，再输出精炼结论；不要输出原始思维链。');
    }
    if (searchContext.isNotEmpty) sys.writeln(searchContext);
    if (fileContext.isNotEmpty) sys.writeln(fileContext);
    if (withTools && settings.pluginEnabled && plugin != null) {
      sys.writeln(plugin!.toolPrompt);
    }
    // 本机能力：只有用户显式打开「设备智能体」才注入工具清单与设备信息。
    // 关闭时 System Prompt 与旧版完全一致，不产生任何额外 token 或行为变化。
    if (withTools && settings.agentEnabled) {
      sys.writeln(buildAgentPrompt(
        info: deviceInfo,
        grant: agentGrant,
        workspaceRoot: agentWorkspace?.root ?? '应用专属目录 /aigent_workspace',
        confirmEach: settings.agentConfirmEach,
      ));
    }
    return sys.toString();
  }

  Map<String, dynamic> previewBody(String userText) {
    final t = settings.tier;
    final req = LlmRequest(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      messages: [
        {'role': 'system', 'content': buildSystemPrompt(query: userText)},
        {'role': 'user', 'content': userText.isEmpty ? '（示例提问）' : userText},
      ],
      maxTokens: t.maxTokens,
      temperature: t.temperature,
      topP: t.topP,
      thinkingBudget: t.thinkingBudget,
      reasoningEffort: t.reasoningEffort,
      deepThinking: settings.deepThinking,
    );
    final body = req.toBody();
    body.remove('stream');
    (body['messages'] as List).last = {
      'role': 'user',
      'content': userText.isEmpty ? '（示例提问）' : userText,
    };
    body['api_key'] = settings.apiKey.isEmpty ? '<未设置>' : '<已加密隐藏>';
    return body;
  }

  static final RegExp _hazard = RegExp(
    r'(rm\s+-rf\s+/system|dd\s+if=\S+\s+of=/dev/block|format\s+/system|wipe\s+data|flash_image\s+/system)',
    caseSensitive: false,
  );

  /// 危险命令示例的展示提示。客户端不做内容拦截，但把执行边界说清楚：
  /// 系统命令从不执行，智能体只跑隔离工作区里经授权的受限任务脚本。
  String? guardNotice(String text) {
    if (_hazard.hasMatch(text)) {
      return '文本中包含涉及系统分区写入的命令示例。本应用不会执行系统命令；'
          '智能体只能在隔离工作区内运行受限任务脚本，且需你逐次授权。';
    }
    return null;
  }

  // ------------------------------------------------------------------ 生成

  Map<String, dynamic> _toApiMessage(ChatMessage m) {
    final img = FileExtractService.imageMessage(
        m.content, m.attachments, settings.visionFormat);
    if (img != null) return img;
    return {
      'role': m.role == Role.user ? 'user' : 'assistant',
      'content': m.content,
    };
  }

  /// 当前模型 ID 看起来是否支持视觉（仅提示，不阻断发送）。
  bool get currentModelLikelyVision => looksLikeVisionModel(settings.model);

  bool get hasPendingImages => pending.any((a) => a.isImage);

  /// 选了图片但模型看起来不支持视觉时，输入台给出的明确提示。
  /// 这是「图片识别不了」最常见的原因，必须在发送前让用户看见。
  String? get visionHint {
    if (!hasPendingImages || currentModelLikelyVision) return null;
    if (settings.visionHintDismissed) return null;
    if (settings.visionFormat == VisionFormat.textOnly) return null;
    return '「${settings.model}」看起来不是视觉模型，可能无法识别图片。'
        '请换用带视觉能力的模型，或到 设置 → 多模态 切换发送格式。';
  }

  List<ImageDiag> get imageDiagnostics => FileExtractService.diagnose(pending);

  /// 待发图片编码进 JSON 后的大致字节数（base64 膨胀 ≈ 4/3）。
  int get imagePayloadBytes => pending
      .where((a) => a.isImage)
      .fold<int>(0, (n, a) => n + ((a.imageBytes!.length + 2) ~/ 3) * 4);

  /// 请求体偏大时给出预警：中转网关常见 413 / 提前断开连接。
  String? get imageSizeHint {
    final b = imagePayloadBytes;
    if (b <= 3 * 1024 * 1024) return null;
    final mb = (b / 1048576).toStringAsFixed(1);
    return '待发图片编码后约 $mb MB，部分中转网关会因此拒绝请求'
        '（HTTP 413 或 Connection closed）。建议减少图片数量或压缩后重试。';
  }

  /// 批量语义刷新：文字成小段出现，消除「一个字一个字蹦」的割裂感。
  /// 判定见 [shouldFlushStream]；force 用于停止 / 一轮结束时一次清空。
  /// 流上下文按会话传入，后台会话生成时不会写到当前活动会话。
  void _flush(_StreamCtx ctx, {bool force = false}) {
    final t = ctx.target;
    if (t == null || ctx.buf.isEmpty) return;
    final pending = ctx.buf.toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      final age = ctx.lastFlush == 0 ? 0 : now - ctx.lastFlush;
      if (!shouldFlushStream(pending, age, ctx.firstFlush)) return;
    }
    t.append(pending);
    ctx.buf.clear();
    ctx.lastFlush = now;
    ctx.firstFlush = false;
  }

  static LlmRequest _withMessages(LlmRequest r, List<Map<String, dynamic>> m) =>
      LlmRequest(
        baseUrl: r.baseUrl,
        apiKey: r.apiKey,
        model: r.model,
        messages: m,
        maxTokens: r.maxTokens,
        temperature: r.temperature,
        topP: r.topP,
        thinkingBudget: r.thinkingBudget,
        reasoningEffort: r.reasoningEffort,
        deepThinking: r.deepThinking,
        extraBody: r.extraBody,
      );

  Future<void> send(String raw) async {
    final conv = active;
    // 只拦「本会话」重复生成：别的会话在生成不会影响这里，支持并行。
    if (conv.generating) return;
    final text = raw.trim();
    if (text.isEmpty && conv.draftAttachments.isEmpty) return;

    // 新消息一发出就停掉上一段朗读：否则回答边生成边被旧声音盖住，
    // 也会把刚合成的音频白白播完。
    unawaited(VoiceService.instance.stop());

    // 捕获本次生成所属的会话与流上下文：此后即使用户切到别的会话，
    // 状态文案与流式文本也只落回原会话，绝不串台。
    final ctx = _stream(conv.id);
    if (conv.messages.isEmpty) {
      conv.title = text.isEmpty
          ? '多模态任务'
          : (text.length > 18 ? '${text.substring(0, 18)}…' : text);
    }

    final attachments = List<Attachment>.of(conv.draftAttachments);
    final userMsg = ChatMessage(
      id: _id(),
      role: Role.user,
      content: text,
      attachments: attachments,
    );
    final answer = ChatMessage(
      id: _id(),
      role: Role.assistant,
      content: '',
      thinking: settings.deepThinking ? ThinkingTrace() : null,
      streaming: true,
      model: settings.model,
      tierLabel: settings.tier.label,
    );
    conv.messages.add(userMsg);
    conv.messages.add(answer);
    conv.draftAttachments = [];
    conv.generating = true;
    globalError = null;
    conv.status = '准备中';
    // 取消令牌提前创建：停止按钮在「检索阶段」也能立即生效，不再出现卡死。
    ctx.cancel = CancelToken();
    ctx.sw
      ..reset()
      ..start();
    notifyListeners();
    // 用户消息与占位回答先落一次盘：即便生成中途被杀进程，
    // 重开也能看到自己问过什么、答案停在哪。
    scheduleHistorySave();

    // ---------- 联网检索 ----------
    // 只有 searchActive（总开关 + 至少一个已启用源）为真时才会进入这里，
    // 且界面状态文案与真实行为共用同一个判定，杜绝「关了还显示联网」。
    var searchContext = '';
    if (settings.searchActive && text.isNotEmpty) {
      conv.status = '联网检索中…';
      notifyListeners();
      try {
        final hits = await searchSvc.search(text, settings, cancel: ctx.cancel);
        // 检索期间被停止 / 期间关闭了联网：不再写入任何检索相关状态。
        if (!(ctx.cancel?.isCancelled ?? false) && settings.searchActive) {
          final cites = SearchService.toCitations(hits);
          searchContext = SearchService.buildContext(hits);
          answer.setCitations(cites);
          answer.searchQuery = text;
          conv.status = cites.isEmpty
              ? '未检索到结果，继续作答'
              : '已合并 ${settings.activeSources.length} 个源 · ${cites.length} 条资料';
        }
      } catch (e) {
        if (!(ctx.cancel?.isCancelled ?? false) && settings.searchActive) {
          conv.status = '检索失败，继续作答：$e';
        }
      }
      notifyListeners();
    }

    // 检索过程中用户点了停止：移除空占位回答，干净收尾，不再请求模型。
    if (ctx.cancel?.isCancelled ?? false) {
      conv.messages.remove(answer);
      conv.generating = false;
      conv.status = '';
      ctx.cancel = null;
      ctx.target = null;
      notifyListeners();
      return;
    }

    // ---------- 组装上下文 ----------
    final sys = buildSystemPrompt(
      query: text,
      searchContext: searchContext,
      fileContext: FileExtractService.textContext(attachments),
      sources: answer.citations.isEmpty
          ? ''
          : answer.citations.map((c) => c.title).join('、'),
      persona: settings.personaFor(conv.personaId),
    );
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': sys},
    ];
    final keep = settings.tier.historyLimit * 2;
    final from = conv.messages.length - 1 - keep < 0
        ? 0
        : conv.messages.length - 1 - keep;
    for (var i = from; i < conv.messages.length - 1; i++) {
      final m = conv.messages[i];
      if (m.role == Role.assistant && m.content.trim().isEmpty) continue;
      if (m.role == Role.tool) continue;
      messages.add(_toApiMessage(m));
    }

    final t = settings.tier;
    var req = LlmRequest(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      messages: messages,
      maxTokens: t.maxTokens,
      temperature: t.temperature,
      topP: t.topP,
      thinkingBudget: t.thinkingBudget,
      reasoningEffort: t.reasoningEffort,
      deepThinking: settings.deepThinking,
      includeUsage: settings.usageTracking,
    );
    // 网关未返回 usage 时，用这份输入文本做本地估算。
    final promptSnapshot = messages
        .map((m) => m['content'] is String ? m['content'] as String : '')
        .join('\n');

    TokenUsage? apiUsage;
    String? finalError;
    // 智能体每一轮最多跑 agentMaxSteps 步；插件仍保留原来的 5 轮预算。
    final maxRounds = 5 + (settings.agentEnabled ? settings.agentMaxSteps : 0);
    var agentSteps = 0;
    ctx.target = answer;
    ctx.buf.clear();
    ctx.lastFlush = 0;
    ctx.firstFlush = true;
    ctx.flushTimer?.cancel();
    ctx.flushTimer =
        Timer.periodic(const Duration(milliseconds: 140), (_) => _flush(ctx));

    try {
      for (var round = 0; round < maxRounds; round++) {
        ctx.buf.clear();
        ctx.lastFlush = 0;
        ctx.firstFlush = true;
        answer.setStreaming(true);
        answer.thinking?.markRunning();
        conv.status = settings.deepThinking ? '深度思考中…' : '生成中…';
        notifyListeners();

        var cancelled = false;
        // 有的网关把思考写进正文的 <thinking> 标签里：边收边拆，
        // 思考进思考区，正文只留答案，标签本身不落到用户眼前。
        final splitter = ThinkSplitter();
        await for (final c in llm.chat(req, cancel: ctx.cancel)) {
          if (c.error != null) {
            finalError = c.error;
            break;
          }
          if (c.cancelled) {
            cancelled = true;
            break;
          }
          if (c.reasoning.isNotEmpty) answer.thinking?.append(c.reasoning);
          final piece = splitter.add(c.content);
          if (piece.thinking.isNotEmpty) {
            answer.thinking?.append(piece.thinking);
          }
          if (piece.content.isNotEmpty) ctx.buf.write(piece.content);
          if (c.usage != null) apiUsage = c.usage;
          _flush(ctx);
        }
        final tail = splitter.flush();
        if (tail.thinking.isNotEmpty) answer.thinking?.append(tail.thinking);
        if (tail.content.isNotEmpty) ctx.buf.write(tail.content);
        _flush(ctx, force: true);
        answer.thinking?.markDone();
        if (finalError != null || cancelled) break;

        final full = answer.content;

        // ---------- 本机工具调用循环 ----------
        // 和插件共用「模型输出 → 解析 → 执行 → 结果回灌」这一轮机制，
        // 但只认 agent.* 前缀，每一步都过授权 + 用户确认 + 审计日志。
        if (settings.agentEnabled &&
            agentWorkspace != null &&
            agentSteps < settings.agentMaxSteps) {
          final call = parseAgentToolCall(full);
          if (call != null) {
            agentSteps++;
            final toolId = call['tool'] as String;
            final toolName = call['name'] as String;
            final args = call['arguments'] as Map<String, dynamic>;
            conv.status = '请求执行：$toolName';
            notifyListeners();

            final sw = Stopwatch()..start();
            final exec = await buildAgentRuntime().execute(toolId, args);
            sw.stop();

            // 操作卡片插在最终回答之前；Role.tool 不会进入发给模型的历史，
            // 也不会被当成一条普通回答朗读 / 导出。
            final toolMsg = ChatMessage(
              id: _id(),
              role: Role.tool,
              content: exec.message,
              toolName: toolName,
              toolOk: exec.ok,
              toolStep: agentSteps,
              toolMs: sw.elapsedMilliseconds,
            );
            final at = conv.messages.length - 1;
            conv.messages.insert(at < 0 ? 0 : at, toolMsg);

            answer.content = '';
            answer.setStreaming(true);
            messages.add({'role': 'assistant', 'content': full});
            messages.add({
              'role': 'user',
              'content':
                  '${exec.asToolResult}\n请据此用自然语言给出最终答案，不要再输出工具 JSON。',
            });
            req = _withMessages(req, messages);
            conv.status = exec.ok
                ? '已执行 $toolName · 整理结果中…'
                : '$toolName 未执行 · 继续作答';
            unawaited(refreshAgentLog());
            notifyListeners();
            continue;
          }
        }

        // 步数用尽后模型仍在输出工具 JSON：给一句明确说明，别把生硬的
        // JSON 当作最终答案展示出来。
        if (settings.agentEnabled &&
            agentSteps >= settings.agentMaxSteps &&
            parseAgentToolCall(full) != null) {
          answer.content = '已达到单次任务的操作步数上限'
              '（${settings.agentMaxSteps} 步）。已完成的操作见上方记录；'
              '需要继续的话，再发一条消息即可。';
        }

        // ---------- 插件工具调用循环 ----------
        if (settings.pluginEnabled && plugin != null) {
          final call = OpenApiPlugin.parseToolCall(full);
          if (call != null) {
            final opId = call['tool'] as String;
            final args = call['arguments'] as Map<String, dynamic>;
            conv.status = '调用插件 $opId…';
            notifyListeners();
            String result;
            try {
              result = await plugin!.call(opId, args, apiKey: settings.apiKey);
            } catch (e) {
              result = '工具调用失败：$e';
            }
            answer.content = '';
            answer.setStreaming(true);
            messages.add({'role': 'assistant', 'content': full});
            messages.add({
              'role': 'user',
              'content':
                  '[工具 $opId 的返回结果]\n$result\n请据此用自然语言给出最终答案，不要再输出工具 JSON。',
            });
            req = _withMessages(req, messages);
            conv.status = '已调用 $opId，整理答案中…';
            notifyListeners();
            continue;
          }
        }
        break;
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Connection closed while receiving data') ||
          msg.contains('HttpException')) {
        finalError = '网关在传输中关闭了连接。若本次附带了图片，'
            '多为图片请求体过大或该中转不支持多模态；'
            '可在 设置 → 多模态 缩小图片 / 切换发送格式后重试。';
      } else {
        finalError = '生成异常：$e';
      }
    } finally {
      ctx.flushTimer?.cancel();
      ctx.flushTimer = null;
      _flush(ctx, force: true);
      ctx.target = null;
      ctx.cancel = null;
      answer.finish(err: finalError);
      answer.elapsedMs = ctx.sw.elapsedMilliseconds;

      // 网关未返回 usage 时用本地估算兜底，并明确标注为估算值。
      final usage =
          apiUsage ?? TokenUsage.estimate(promptSnapshot, answer.content);
      answer.usage = usage;
      tokenStats.add(usage, model: settings.model);
      scheduleHistorySave();

      if (settings.autoRecord) {
        final body = req.toBody();
        body.remove('stream');
        _addRecord(ExperimentRecord(
          id: _id(),
          at: DateTime.now().millisecondsSinceEpoch,
          kind: 'chat',
          presetName: settings.activePreset.name,
          model: settings.model,
          tier: t.label,
          query: text,
          params: {
            'max_tokens': t.maxTokens,
            'temperature': t.temperature,
            'top_p': t.topP,
            'thinking_budget': t.thinkingBudget,
            'reasoning_effort': t.reasoningEffort,
            'web_search': settings.searchActive,
            'preset': settings.activePreset.name,
          },
          requestBody: const JsonEncoder.withIndent('  ').convert(body),
          responseRaw: answer.content,
          elapsedMs: ctx.sw.elapsedMilliseconds,
          error: finalError,
          usage: usage,
        ));
      }
      conv.generating = false;
      conv.status = '';
      notifyListeners();

      // 自动朗读：只在用户仍停在这个会话时出声。
      // 后台会话回答完就突然开口，是很吓人的体验。
      final spoken = answer.content.trim();
      if (settings.autoSpeak &&
          settings.ttsEnabled &&
          !settings.voiceMuted &&
          finalError == null &&
          spoken.isNotEmpty &&
          active.id == conv.id) {
        unawaited(speak(spoken));
      }
    }
  }

  void _addRecord(ExperimentRecord r) {
    records.insert(0, r);
    if (records.length > 120) records.removeRange(120, records.length);
  }

  void clearRecords() {
    records.clear();
    notifyListeners();
  }

  void resetTokenStats() {
    tokenStats.reset();
    notifyListeners();
    unawaited(flushHistory());
  }

  /// 本地费用估算（¥）。单价为 0 时返回 null。
  double? get estimatedCost {
    final i = settings.priceInPerM;
    final o = settings.priceOutPerM;
    if (i <= 0 && o <= 0) return null;
    return tokenStats.prompt / 1000000 * i +
        tokenStats.completion / 1000000 * o;
  }

  String exportRecordsMarkdown() {
    final b = StringBuffer();
    b.writeln('# Aigent 实验记录');
    b.writeln('\n共 ${records.length} 条 · 累计 ${tokenStats.total} tok');
    for (final r in records) {
      b.writeln('\n${r.toMarkdown()}');
    }
    return b.toString();
  }

  String exportRecordsJson() => const JsonEncoder.withIndent('  ')
      .convert(records.map((r) => r.toJson()).toList());

  String exportUsageCsv() {
    final b = StringBuffer();
    b.writeln('model,prompt_tokens,completion_tokens,total_tokens,requests');
    for (final e in tokenStats.byModel.entries) {
      b.writeln('"${e.key.replaceAll('"', '""')}",${e.value.prompt},'
          '${e.value.completion},${e.value.total},');
    }
    b.writeln('ALL,${tokenStats.prompt},${tokenStats.completion},'
        '${tokenStats.total},${tokenStats.requests}');
    return b.toString();
  }

  /// 只停止当前活动会话的生成；后台其它会话不受影响。
  void stop() {
    final ctx = _streams[activeId];
    ctx?.cancel?.cancel('用户停止');
    // 有动作正等用户确认时，停止一律按「跳过」收尾，不能让生成流程悬挂。
    resolveAgentAction(false);
    // 立即撤掉状态栏，避免检索阶段停止后仍停在「联网检索中…」。
    if (active.status.isNotEmpty) {
      active.status = '';
      notifyListeners();
    }
    // 研究工作流的取消令牌也挂在同一会话的上下文上。
    if (researching) {
      ctx?.cancel?.cancel('用户停止');
    }
  }

  Future<void> regenerate() async {
    final msgs = active.messages;
    if (msgs.isEmpty) return;
    var last = '';
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == Role.user) {
        last = msgs[i].content;
        break;
      }
    }
    final removeFrom = msgs.lastIndexWhere((m) => m.role == Role.user);
    if (removeFrom >= 0) {
      msgs.removeRange(removeFrom, msgs.length);
      notifyListeners();
    }
    if (last.isNotEmpty) await send(last);
  }

  // ------------------------------------------------------------ 深度研究工作流

  String get researchStatusLabel => researching
      ? '${researchStage.label}${researchStep > 0 ? ' · $researchStep/$researchTotal' : ''}'
      : researchStage.label;

  /// 一次工作流内所有子请求共用同一个取消令牌，停止按钮随时可中断。
  Future<({String text, TokenUsage? usage})> _researchStep({
    required String system,
    required String user,
    required String label,
    required CancelToken? cancel,
  }) async {
    final t = settings.tier;
    final req = LlmRequest(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      maxTokens: t.maxTokens,
      temperature: t.temperature,
      topP: t.topP,
      thinkingBudget: t.thinkingBudget,
      reasoningEffort: t.reasoningEffort,
      deepThinking: settings.deepThinking,
      includeUsage: settings.usageTracking,
    );
    final r = await llm.completeWithUsage(req, cancel: cancel);
    final usage = r.usage ?? TokenUsage.estimate('$system\n$user', r.text);
    tokenStats.add(usage, model: settings.model);
    scheduleHistorySave();
    if (settings.autoRecord) {
      final body = req.toBody();
      body.remove('stream');
      _addRecord(ExperimentRecord(
        id: _id(),
        at: DateTime.now().millisecondsSinceEpoch,
        kind: 'research',
        presetName: '${settings.activePreset.name} · $label',
        model: settings.model,
        tier: settings.tier.label,
        query: user.length > 200 ? '${user.substring(0, 200)}…' : user,
        params: {
          'phase': label,
          'max_tokens': t.maxTokens,
          'temperature': t.temperature,
          'top_p': t.topP,
        },
        requestBody: const JsonEncoder.withIndent('  ').convert(body),
        responseRaw: r.text,
        elapsedMs: 0,
        usage: usage,
      ));
    }
    return r;
  }

  static List<String> _parseSections(String outline, int n) {
    final lines = outline
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l
            .replaceAll(RegExp(r'^#{1,4}\s*'), '')
            .replaceAll(RegExp(r'^\s*(?:\d+[\.、）)]?|[-*•])\s*'), '')
            .trim())
        .where((l) => l.length > 1 && l.length < 80)
        .toList();
    final seen = <String>{};
    final out = <String>[];
    for (final l in lines) {
      if (seen.add(l)) out.add(l);
      if (out.length >= n) break;
    }
    var i = 1;
    while (out.length < n) {
      out.add('补充视角 ${i++}');
    }
    return out;
  }

  /// 检索 → 大纲 → 逐节展开 → 汇总核对，产出一份可导出的 Markdown 报告。
  Future<void> runResearch(String topic) async {
    final q = topic.trim();
    final conv = active;
    if (q.isEmpty || conv.generating || researching) return;

    // 与 send 一样捕获会话与流上下文，切换会话后状态只落回原会话。
    final ctx = _stream(conv.id);
    if (conv.messages.isEmpty) {
      conv.title = q.length > 18 ? '${q.substring(0, 18)}…' : q;
    }
    final answer = ChatMessage(
      id: _id(),
      role: Role.assistant,
      content: '',
      streaming: true,
      model: settings.model,
      tierLabel: settings.tier.label,
    );
    conv.messages.add(ChatMessage(id: _id(), role: Role.user, content: q));
    conv.messages.add(answer);

    ctx.cancel = CancelToken();
    ctx.sw
      ..reset()
      ..start();
    researchTopic = q;
    researchReport = '';
    researchStep = 0;
    researchTotal = settings.sectionCount;
    researchStage = ResearchStage.searching;
    conv.generating = true;
    globalError = null;
    conv.status = '检索资料…';
    notifyListeners();

    var cancelled = false;
    String? error;
    final persona = settings.personaFor(conv.personaId);
    try {
      // ---- 阶段 1：多源检索（仅在联网真正开启时） ----
      var sourceBlock = '（本次未启用联网检索，章节内容基于模型自身知识，请自行核实。）';
      if (settings.searchActive) {
        final hits = await searchSvc.search(q, settings, cancel: ctx.cancel);
        if (!(ctx.cancel?.isCancelled ?? false)) {
          final cites = SearchService.toCitations(hits);
          answer.setCitations(cites);
          answer.searchQuery = q;
          if (hits.isNotEmpty) {
            sourceBlock = SearchService.buildContext(hits);
          }
        }
      }
      if (ctx.cancel?.isCancelled ?? false) {
        cancelled = true;
        throw StateError('已取消');
      }

      // ---- 阶段 2：拟定大纲 ----
      researchStage = ResearchStage.outlining;
      conv.status = '拟定大纲…';
      notifyListeners();
      final outline = await _researchStep(
        label: '大纲',
        cancel: ctx.cancel,
        system: buildSystemPrompt(query: q, withTools: false, persona: persona),
        user: '研究主题：$q\n\n请只输出 $researchTotal 个互不重叠的章节标题，'
            '每行一个，不要编号、不要解释、不要额外文字。'
            '章节应覆盖：背景与定义、关键事实、不同观点与争议、局限与开放问题。\n\n'
            '可用资料：\n$sourceBlock',
      );
      final sections = _parseSections(outline.text, researchTotal);

      // ---- 阶段 3：逐节展开 ----
      answer.append('# $q\n\n');
      final parts = <String>[];
      for (var i = 0; i < sections.length; i++) {
        if (ctx.cancel?.isCancelled ?? false) {
          cancelled = true;
          throw StateError('已取消');
        }
        researchStage = ResearchStage.drafting;
        researchStep = i + 1;
        researchTotal = sections.length;
        conv.status = '逐节展开 ${i + 1}/${sections.length}';
        notifyListeners();

        final r = await _researchStep(
          label: '章节 ${i + 1}',
          cancel: ctx.cancel,
          system:
              buildSystemPrompt(query: q, withTools: false, persona: persona),
          user: '研究主题：$q\n当前章节：${sections[i]}\n'
              '已有章节：${parts.isEmpty ? "无" : parts.map((p) => p.split("\n").first).join("、")}\n\n'
              '请只写这一章，300-500 字，不要重复其他章节内容。'
              '有资料时以 [1] [2] 标注依据，区分「资料所述」与「推断」。\n\n'
              '资料：\n$sourceBlock',
        );
        final section = '## ${sections[i]}\n\n${r.text.trim()}';
        parts.add(section);
        answer.append('$section\n\n');
      }

      // ---- 阶段 4：汇总核对 ----
      researchStage = ResearchStage.verifying;
      conv.status = '核对引用…';
      notifyListeners();
      final date =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-'
          '${DateTime.now().day.toString().padLeft(2, '0')}';
      final b = StringBuffer();
      b.writeln('# $q');
      b.writeln('\n> Aigent 深度研究 · ${settings.activePreset.name} · '
          '${settings.model} · ${settings.tier.label} · $date');
      b.writeln('\n## 资料来源\n');
      if (answer.citations.isNotEmpty) {
        for (final c in answer.citations) {
          b.writeln('[${c.index}] ${c.title} — ${c.url}');
        }
      } else {
        b.writeln(sourceBlock);
      }
      b.writeln('\n---\n');
      b.writeln(parts.join('\n\n'));
      b.writeln('\n---\n');
      b.writeln('本报告由多轮模型调用自动汇总，请核实关键事实与来源后再引用。');
      researchReport = b.toString();
    } catch (e) {
      if (!cancelled) error = '$e';
    } finally {
      answer.finish(err: cancelled ? null : error);
      answer.elapsedMs = ctx.sw.elapsedMilliseconds;
      researchStage = cancelled
          ? ResearchStage.failed
          : (error == null ? ResearchStage.done : ResearchStage.failed);
      conv.generating = false;
      ctx.cancel = null;
      conv.status = '';
      notifyListeners();
    }
  }

  String exportResearchReport() =>
      researchReport.isEmpty ? '# 暂无研究报告\n\n请先在工具抽屉里发起一次深度研究。' : researchReport;

  // -------------------------------------------------------------- 语音

  /// 朗读引擎。id 失效（旧配置 / 手改 JSON）时回落到系统语音。
  TtsEngine get activeTtsEngine =>
      ttsEngineById(settings.ttsEngineId) ?? kTtsEngines.first;

  SttEngine get activeSttEngine =>
      sttEngineById(settings.sttEngineId) ?? kSttEngines.first;

  /// 「跟随连接」的引擎用当前 baseUrl；其余用自身地址，允许被自定义地址覆盖。
  String resolveTtsBaseUrl() {
    final e = activeTtsEngine;
    if (e.followsConnection) return settings.baseUrl;
    final custom = settings.ttsBaseUrl.trim();
    return custom.isEmpty ? e.baseUrl : custom;
  }

  String resolveTtsKey() {
    final e = activeTtsEngine;
    if (e.followsConnection) return settings.apiKey;
    return settings.voiceTtsKey;
  }

  String resolveSttBaseUrl() {
    final e = activeSttEngine;
    if (e.followsConnection) return settings.baseUrl;
    final custom = settings.sttBaseUrl.trim();
    return custom.isEmpty ? e.baseUrl : custom;
  }

  String resolveSttKey() {
    final e = activeSttEngine;
    if (e.followsConnection) return settings.apiKey;
    return settings.voiceSttKey;
  }

  /// 朗读一段文本。返回 null 表示已开始播放，否则是错误文案。
  /// 静音时不出声但给出明确提示；顶栏 / 长按菜单会在调用前自动解除静音。
  Future<String?> speak(String text) {
    if (settings.voiceMuted) {
      return Future<String?>.value('朗读已静音，点右上角音量键开启');
    }
    final e = activeTtsEngine;
    return VoiceService.instance.speak(
      text: text,
      engine: e,
      voice: settings.ttsVoice,
      rate: settings.ttsRate,
      lang: settings.voiceLang,
      baseUrl: resolveTtsBaseUrl(),
      apiKey: resolveTtsKey(),
      model: settings.ttsModel,
    );
  }

  Future<void> stopSpeaking() => VoiceService.instance.stop();

  /// 语音引擎密钥单独保存：和连接密钥共用加密仓，不进设置快照。
  Future<void> setVoiceKey({required bool tts, required String key}) async {
    final v = key.trim();
    if (tts) {
      settings.voiceTtsKey = v;
    } else {
      settings.voiceSttKey = v;
    }
    await persist();
    notifyListeners();
  }
}
