import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/file_extract.dart';
import '../services/model_brand.dart';
import '../services/model_catalog.dart';
import '../services/model_probe.dart';
import '../services/free_pool.dart';
import '../services/lang_catalog.dart';
import '../services/relay_catalog.dart';
import '../services/voice_catalog.dart';
import '../skin.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'agent_panel.dart';
import 'billing_panel.dart';
import 'brand_icon.dart';
import 'cache_panel.dart';
import 'free_pool_panel.dart';
import 'games_hub.dart';
import 'lang_picker_sheet.dart';
import 'model_search_box.dart';
import 'persona.dart';
import 'relay_panel.dart';
import 'research_sheet.dart';
import 'voice_panel.dart';
import 'widgets.dart';

// ---------------------------------------------------------------- 设置分类

class SettingsCat {
  final String id;
  final String title;
  final String desc;
  final IconData icon;
  final List<String> keys;

  /// 子页顶部那句说明。分类卡已经写过一次，子页再写一遍就是重复，
  /// 所以结构自带标题的页面（搜索源、免密模型）把它关掉。
  final bool showDesc;
  const SettingsCat(this.id, this.title, this.desc, this.icon, this.keys,
      {this.showDesc = true});
}

/// 设置首页的分类目录。搜索按标题、描述与关键词别名匹配，
/// 这样输入「深色」「token」「serper」也能直达对应分类。
List<SettingsCat> get kSettingsCats => [
  SettingsCat('connection', t('连接与模型'), t('接口地址、密钥、模型与多配置档'), Icons.hub_outlined, [
    'api',
    'key',
    'base',
    'url',
    '模型',
    '连接',
    '配置',
    '地址',
    '密钥',
    'ollama',
    'profile',
    '凭据'
  ]),
  SettingsCat(
      'relay', t('网页版反代'), t('把开源 xx2api 项目接成一条连接'), Icons.swap_horiz_rounded, [
    '反代',
    '网页',
    '逆向',
    'xx2api',
    'web2api',
    'chat2api',
    'g4f',
    'copilot',
    'free-api',
    '中转',
    '本地网关',
    '局域网',
    '扫描',
    'deepseek',
    '公益',
    '公共',
    'github',
    '开源'
  ]),
  SettingsCat('free', t('免密模型'), t('探测公开的免密钥模型，能对话才列出'), Icons.bolt_outlined,
      showDesc: false, [
    '免密',
    '无需密钥',
    '免费',
    '白嫖',
    '公开',
    'pollinations',
    'llm7',
    'free',
    'no key',
    '聚合',
    'ovh',
    'kilo',
    '限流'
  ]),
  SettingsCat('appearance', t('外观主题'), t('19 套主题、自定义配色、圆角与字号'), Icons.palette_outlined,
      ['主题', '深色', '浅色', '夜间', '颜色', '外观', 'dark', 'theme', '系统', '字号', '大小', '字体', '皮肤', '配色', '自定义', 'github', '皮肤']),
  SettingsCat('language', t('语言与地区'), t('界面、回答、语音识别三套语言，独立设置'),
      Icons.language_rounded, [
    '语言',
    '中文',
    '英文',
    '多语言',
    'language',
    'i18n',
    '翻译',
    '小语种',
    '识别语言',
    '语种',
    'lang'
  ]),
  SettingsCat('persona', t('人物形象'), t('自定义头像、名字、性格与角色设定'),
      Icons.face_retouching_natural_outlined, [
    '形象',
    '人物',
    '头像',
    '角色',
    '名字',
    '人设',
    '性格',
    'muse',
    'persona',
    '设定',
    '自定义'
  ]),
  SettingsCat('voice', t('语音'), t('朗读与语音输入，免费与付费引擎都可切'), Icons.graphic_eq_rounded, [
    '语音',
    '朗读',
    'tts',
    'stt',
    '麦克风',
    '听写',
    '转写',
    'voice',
    'speak',
    'whisper',
    '说话',
    '声音',
    '音色'
  ]),
  SettingsCat(
      'agent', t('设备智能体'), t('本机信息、隔离工作区与应用 / 日历 / 闹钟操作'),
      Icons.smartphone_outlined, [
    '智能体',
    '设备',
    '本机',
    'agent',
    '工作区',
    '沙箱',
    '运行代码',
    '脚本',
    '打开应用',
    '闹钟',
    '日历',
    '浏览器',
    '型号',
    '配置',
    '授权',
    '工具调用',
    '干活'
  ]),
  SettingsCat('capability', t('能力档位'), t('档位、深度思考与联网总开关'), Icons.tune_rounded,
      ['档位', '深度思考', '联网', '搜索', 'tier', '温度', '推理', '能力']),
  SettingsCat('vision', t('图片与多模态'), t('发送格式、视觉能力判定与图片诊断'), Icons.image_outlined,
      ['图片', '视觉', '多模态', 'vision', 'image', 'base64', 'heic', '格式', '识图']),
  SettingsCat(
      'search', t('联网搜索源'), t('多源选择、每源密钥与连通性测试'), Icons.travel_explore_outlined,
      showDesc: false, [
    '搜索源',
    'serper',
    'tavily',
    'github',
    'bing',
    'google',
    'exa',
    'brave',
    '源',
    '检索',
    'serpapi'
  ]),
  SettingsCat('research', t('研究工作台'), t('深度研究工作流、实验记录与报告'), Icons.science_outlined,
      ['研究', '工作流', '实验', '记录', '原始输出', '报告', 'research']),
  SettingsCat(
      'presets',
      t('提示词预设'),
      t('System Prompt 预设与变量插值'),
      Icons.article_outlined,
      ['提示词', 'system', 'prompt', '预设', '变量', '注入', '人设']),
  SettingsCat('usage', t('Token 用量'), t('累计消耗、单价、明细与导出'), Icons.data_usage_outlined,
      ['token', '用量', '费用', '价格', '单价', '统计', 'csv', '消耗']),
  SettingsCat('cache', t('缓存命中'), t('命中统计、响应复用与缓存管理'), Icons.cached_outlined,
      ['缓存', '命中', '复用', '省钱', 'cache', 'hit', 'prompt cache']),
  SettingsCat('billing', t('费用与价格'), t('实时价格、按模型与按天花费'), Icons.payments_outlined,
      ['费用', '价格', '花了多少钱', '计费', '账单', '汇率', 'price', 'cost']),
  SettingsCat('games', t('游戏'), t('圆桌会议、模拟人生与 7 个小游戏'), Icons.sports_esports_outlined,
      ['游戏', '玩', '娱乐', '圆桌', '会议', '模拟人生', '轮盘', '猜数字', '剪刀', '抽签', '八球', '二十问', '接龙', 'game']),
];

/// 分类搜索匹配（纯函数，便于单测）：标题、描述或关键词别名命中即可。
bool settingsCatMatches(SettingsCat c, String q) {
  final k = q.trim().toLowerCase();
  if (k.isEmpty) return true;
  return c.title.toLowerCase().contains(k) ||
      c.desc.toLowerCase().contains(k) ||
      c.keys.any((e) => e.toLowerCase().contains(k));
}

class SettingsScreen extends StatefulWidget {
  /// 可选：直接进入某个分类子页（如从形象弹层跳到「人物形象」）。
  final String? initialCat;
  const SettingsScreen({super.key, this.initialCat});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _prompt;

  /// 每个搜索源独立一份配置输入框，按需创建、统一释放。
  final Map<String, TextEditingController> _srcKey = {};
  final Map<String, TextEditingController> _srcEp = {};
  final Map<String, TextEditingController> _srcCx = {};

  /// 已展开配置的搜索源。默认全部收起——6 个启用的源各摊开一张卡，
  /// 页面会变成一长串输入框，想找的东西反而找不到。
  final Set<String> _openSource = {};

  TextEditingController _ctl(Map<String, TextEditingController> pool,
          String name, String initial) =>
      pool.putIfAbsent(name, () => TextEditingController(text: initial));

  bool _obscure = true;
  bool _manualModel = false;
  bool _probing = false;
  ModelProbe? _probe;
  Timer? _saveDebounce;
  Timer? _fetchDebounce;

  /// 子页跑在独立路由上，本 State 的局部变化靠它通知子页重画。
  final ValueNotifier<int> _uiTick = ValueNotifier<int>(0);
  String _q = '';

  /// 搜索默认收起：首页第一眼只有标题和分组，不再顶着一个灰色输入框。
  bool _searchOpen = false;
  late final TextEditingController _search;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _base = TextEditingController(text: s.baseUrl);
    _key = TextEditingController(text: s.apiKey);
    _model = TextEditingController(text: s.model);
    _prompt = TextEditingController(text: s.activePreset.content);
    _search = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final st = context.read<AppState>();
      if (st.models.isEmpty && !st.modelsLoading && _shouldAutoFetch()) {
        st.refreshModels(baseUrl: _base.text, apiKey: _key.text);
      }
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _fetchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _base.dispose();
    _key.dispose();
    _model.dispose();
    _prompt.dispose();
    _uiTick.dispose();
    for (final c in [..._srcKey.values, ..._srcEp.values, ..._srcCx.values]) {
      c.dispose();
    }
    super.dispose();
  }

  AppState get st => context.read<AppState>();

  /// 子页现在跑在独立路由上，本 State 的 setState 不会再重建它。
  /// 所以设置页里的状态变更统一走这里：刷新自己，也通知子页重画。
  /// 纯局部 UI 状态（密钥显隐、探测中、手动输入模型）都靠这一条。
  void _setState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _uiTick.value++;
  }

  /// 子页要跟着「本页局部状态 + AppState」两条线一起重画。
  late final Listenable _repaint = Listenable.merge([_uiTick, st]);

  bool _shouldAutoFetch() {
    if (_key.text.trim().isNotEmpty) return true;
    return RegExp(r'localhost|127\.0\.0\.1|192\.168\.|10\.\d+\.')
        .hasMatch(_base.text);
  }

  // ------------------------------------------------------------ 配置档

  /// 切换配置后把新快照灌回输入框，避免显示上一份的 URL / Key。
  void _loadActive() {
    final s = st.settings;
    _base.text = s.baseUrl;
    _key.text = s.apiKey;
    _model.text = s.model;
  }

  Future<void> _switchProfile(String id) async {
    if (id == st.settings.activeProfileId) return;
    await _persistAll();
    await st.switchProfile(id);
    if (!mounted) return;
    _loadActive();
    _setState(() {});
  }

  Future<void> _newProfile() async {
    final preset = await showDialog<ProfilePreset>(
      context: context,
      builder: (ctx) => const _PresetDialog(),
    );
    if (preset == null || !mounted) return;
    await _persistAll();
    final label = preset.name == '自定义' ? '自定义连接' : preset.name;
    await st.addProfile(
        name: label, baseUrl: preset.baseUrl, model: preset.model);
    if (!mounted) return;
    _loadActive();
    _setState(() {});
    _toast('已创建「$label」，切换不会删除原有配置');
  }

  Future<void> _renameProfile() async {
    final s = st.settings;
    final ctrl = TextEditingController(text: s.activeProfile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('重命名配置')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: t('配置名称')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(t('保存'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await st.renameProfile(s.activeProfileId, name);
    if (mounted) _setState(() {});
  }

  Future<void> _duplicateProfile() async {
    await _persistAll();
    await st.duplicateProfile(st.settings.activeProfileId);
    if (!mounted) return;
    _loadActive();
    _setState(() {});
    _toast('已复制当前配置');
  }

  Future<void> _deleteProfile() async {
    final s = st.settings;
    if (s.profiles.length <= 1) {
      _toast('至少需要保留一份配置');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('删除配置')),
        content: Text('将移除「${s.activeProfile.name}」及其密钥，其余配置不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('删除'))),
        ],
      ),
    );
    if (ok != true) return;
    await st.deleteProfile(s.activeProfileId);
    if (!mounted) return;
    _loadActive();
    _setState(() {});
    _toast('已删除该配置');
  }

  /// 从反代面板接入一条连接：新建配置档并切过去，原有配置完整保留。
  Future<void> _addRelay(
    RelayPreset preset,
    String baseUrl,
    String key,
    String model,
  ) =>
      _addConn(preset.name, baseUrl, key, model);

  /// 免密面板接入：名字里带上模型，便于在配置列表里区分同源的不同模型。
  Future<void> _addFree(
    String name,
    String baseUrl,
    String key,
    String model,
  ) =>
      _addConn(name, baseUrl, key, model);

  Future<void> _addConn(
    String name,
    String baseUrl,
    String key,
    String model,
  ) async {
    await _persistAll();
    await st.addProfile(name: name, baseUrl: baseUrl, model: model);
    if (key.isNotEmpty) await st.setApiKey(key);
    if (!mounted) return;
    _loadActive();
    _setState(() {});
    // 模型列表在后台补全，不挡住面板关闭。
    unawaited(st.refreshModels(baseUrl: baseUrl, apiKey: key));
  }

  Widget _profileBar(bool dark, AppSettings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: s.profiles.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == s.profiles.length) {
                return GestureDetector(
                  onTap: _newProfile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: fieldOf(dark),
                      borderRadius: BorderRadius.circular(D.r),
                      border: Border.all(color: borderOf(dark)),
                    ),
                    child: Center(
                      child: Text(t('+ 新建'),
                          style: meta(dark, size: 11.5, color: accentOf(dark))),
                    ),
                  ),
                );
              }
              final p = s.profiles[i];
              final active = p.id == s.activeProfileId;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _switchProfile(p.id),
                child: AnimatedContainer(
                  duration: D.anim,
                  curve: D.curve,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: active ? C.brand : fieldOf(dark),
                    borderRadius: BorderRadius.circular(D.r),
                    border:
                        Border.all(color: active ? C.brand : borderOf(dark)),
                  ),
                  child: Center(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color:
                            active ? Colors.white : (dark ? C.dInk2 : C.ink2),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                s.activeProfile.hostLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta(dark, size: 11.5),
              ),
            ),
            _miniAction('重命名', _renameProfile, dark),
            const SizedBox(width: 14),
            _miniAction('复制', _duplicateProfile, dark),
            const SizedBox(width: 14),
            _miniAction('删除', _deleteProfile, dark, danger: true),
          ],
        ),
      ],
    );
  }

  Widget _miniAction(String text, VoidCallback onTap, bool dark,
      {bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: meta(dark,
            size: 11.5, color: danger ? C.danger : (dark ? C.dInk2 : C.ink2)),
      ),
    );
  }

  // ------------------------------------------------------------ 持久化

  void _writeAll(AppSettings s, [void Function(AppSettings s)? extra]) {
    s.baseUrl = _base.text.trim();
    s.model = _model.text.trim();
    // 编辑框内容写回当前预设，同时同步旧镜像字段。
    s.setPresetContent(_prompt.text);
    for (final p in SearchProvider.values) {
      final k = _srcKey[p.name];
      final e = _srcEp[p.name];
      final c = _srcCx[p.name];
      if (k != null || e != null || c != null) {
        s.setSourceCfg(
          p,
          key: k?.text.trim(),
          endpoint: e?.text.trim(),
          cx: c?.text.trim(),
        );
      }
    }
    if (extra != null) extra(s);
  }

  Future<void> _persistAll() async {
    _saveDebounce?.cancel();
    await st.patch((s) => _writeAll(s));
    await st.setApiKey(_key.text);
  }

  /// 输入时防抖落盘，避免逐字符写磁盘 + 整页重建造成的输入掉帧。
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 260), () {
      _persistAll();
    });
  }

  void _onConnChanged() {
    _scheduleSave();
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted) return;
      await _persistAll();
      await st.refreshModels(baseUrl: _base.text, apiKey: _key.text);
    });
  }

  /// 乐观更新：点击瞬间改内存 + 立即刷新，落盘在后台进行。
  /// 旧实现每点一次开关要 await 两次磁盘写再重建整页长表单，是「不跟手」的主因。
  void _toggle(void Function(AppSettings s) fn) {
    st.apply((s) => _writeAll(s, fn));
    if (mounted) _setState(() {});
  }

  void _syncModel(String model) {
    if (_manualModel || !mounted || _model.text == model) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _manualModel || _model.text == model) return;
      _model.value = TextEditingValue(
        text: model,
        selection: TextSelection.collapsed(offset: model.length),
      );
    });
  }

  // ------------------------------------------------------------ 页面骨架

  @override
  Widget build(BuildContext context) {
    final cat = widget.initialCat;
    // 从抽屉直接深链到某个分类时，根路由本身就是那个子页；
    // 常规路径下根路由是分类目录，子页作为独立路由推入（见 _openCat）。
    // 注意：不要在这里根据 isCurrent 包 ExcludeSemantics。那会让本页在
    // push/pop 的那一帧整体重建一次（几十毫秒），正好落在动画起点上，
    // 反而把卡顿做回去。下层语义由 ModalRoute 自己的 BlockSemantics
    // 处理，不需要额外干预。
    return cat == null ? _hubScaffold(context) : _detailScaffold(context, cat);
  }

  Widget _hubScaffold(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      // 顶栏与页面同色、无阴影：白底 AppBar 叠灰底搜索框会像套了两层壳。
      backgroundColor: canvasOf(dark),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: canvasOf(dark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(t('设置'),
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
        leading: _roundIcon(dark, Icons.arrow_back_rounded,
            () => Navigator.maybePop(context)),
        actions: [
          _roundIcon(
            dark,
            _searchOpen ? Icons.keyboard_arrow_up_rounded : Icons.search_rounded,
            () {
              _setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _q = '';
                  _search.clear();
                  _searchFocus.unfocus();
                }
              });
              if (_searchOpen) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocus.requestFocus();
                });
              }
            },
            tooltip: _searchOpen ? t('收起搜索') : t('搜索设置'),
          ),
        ],
      ),
      body: _hub(dark),
    );
  }

  Widget _detailScaffold(BuildContext context, String id) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: _detailAppBar(context, id, dark),
      // 只有 body 跟着状态重建：顶栏是静态的，没必要在每次设置项
      // 变动（拖字号滑块、拨开关）时重新布局一遍 AppBar。
      body: AnimatedBuilder(
        animation: _repaint,
        builder: (_, __) => _detail(dark, id),
      ),
    );
  }

  PreferredSizeWidget _detailAppBar(
      BuildContext context, String id, bool dark) {
    return AppBar(
      centerTitle: true,
      backgroundColor: canvasOf(dark),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(_catById(id).title,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
      leading: _roundIcon(dark, Icons.arrow_back_rounded,
          () => Navigator.maybePop(context)),
      actions: const [SizedBox(width: 4)],
    );
  }

  /// 顶栏圆形图标：一层极淡的底 + 一圈更淡的边。
  ///
  /// 默认主题（静水深）的画布只比纸面深一点点，纯透明按钮浮在上面
  /// 像是"没有落点"——两根箭头悬在空中，既看不出边界也看不出可点。
  /// 这里给 3% 的黑底 + 0.8px 的 hair 线：近看有边界，远看几乎消失，
  /// 不会变成"描边按钮"那种廉价感。
  Widget _roundIcon(bool dark, IconData icon, VoidCallback onPressed,
      {String? tooltip}) {
    final btn = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 底色只给 1.5%，真正撑起"边界感"的是下面那层柔光。
        color: dark
            ? Colors.white.withOpacity(0.045)
            : Colors.black.withOpacity(0.015),
        border: Border.all(color: hairOf(dark), width: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.30 : 0.055),
            blurRadius: 9,
            offset: const Offset(0, 1.4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          splashColor: (dark ? Colors.white : Colors.black).withOpacity(0.04),
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: dark ? C.dInk2 : C.ink2),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: tooltip == null ? btn : Tooltip(message: tooltip, child: btn),
    );
  }

  /// 打开分类子页。
  ///
  /// 子页必须是**独立路由**：这样系统返回/侧滑只退一层，转场交给路由层，
  /// 不再用 AnimatedSwitcher 把两页塞进同一个 Stack——那种做法在转场
  /// 期间会同时布局两份长列表（掉帧），半透明叠加还会留下重影。
  void _openCat(String id) {
    if (id == widget.initialCat) return;
    Navigator.of(context).push(_catRoute(id));
  }

  Route<void> _catRoute(String id) => SoftPageRoute<void>(
        settings: RouteSettings(name: 'settings/$id'),
        // 返回时要盖在设置主目录上，主目录必须一直保持布局与缓存，
        // 否则返回的第一帧要重建整页，就是那一下卡顿。
        keepBelow: true,
        builder: (_) => _SettingsDetailPage(owner: this, catId: id),
      );

  SettingsCat _catById(String id) =>
      kSettingsCats.firstWhere((c) => c.id == id);

  /// 分类导航首页：搜索框 + 8 张分类卡。首屏只构建这十来个 widget，
  /// 不再一次性铺开整份长表单，滚动与进入都更轻快。
  /// 首页分组：跟系统设置一样按用途分段，而不是十三个同款卡片排下来。
  /// 搜索时按组过滤，空组直接不渲染。
  ///
  /// 语言放在「偏好设置」第一位：它是全局开关，排在语音、形象后面
  /// 用户会在设置里翻半天找不到。
  static const List<(String, List<String>)> _hubGroups = [
    ('连接与能力', ['connection', 'relay', 'free', 'capability', 'vision']),
    (
      '偏好设置',
      ['language', 'appearance', 'persona', 'voice', 'agent', 'search', 'research']
    ),
    ('数据与高级', ['presets', 'usage', 'cache', 'billing']),
    ('游戏', ['games']),
  ];

  Widget _hub(bool dark) {
    final s = st.settings;
    final q = _q.trim().toLowerCase();
    final groups = <(String, List<SettingsCat>)>[];
    for (final g in _hubGroups) {
      final items = g.$2
          .map((id) => kSettingsCats.firstWhere((c) => c.id == id))
          .where((c) => settingsCatMatches(c, q))
          .toList();
      if (items.isNotEmpty) groups.add((g.$1, items));
    }
    return ListView(
      key: const PageStorageKey('settings_hub'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
      physics: const ClampingScrollPhysics(),
      children: [
        // 搜索是「按需展开」的一条细线，不再是首页第一眼的灰色方块。
        AnimatedSize(
          duration: D.animFast,
          curve: D.curve,
          alignment: Alignment.topCenter,
          child: _searchOpen || _q.isNotEmpty
              ? _searchLine(dark)
              : const SizedBox(width: double.infinity),
        ),
        SizedBox(height: _searchOpen || _q.isNotEmpty ? 14 : 4),
        if (groups.isEmpty)
          _hubEmpty(dark, _q.trim())
        else
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Text(
                g.$1,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: dark ? C.dInk3 : C.ink3,
                ),
              ),
            ),
            _groupCard(dark, g.$2, s),
            const SizedBox(height: 22),
          ],
      ],
    );
  }

  /// 无填充、无边框的一条输入行，只有底部一根细线。
  Widget _searchLine(bool dark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              size: 17, color: dark ? C.dInk3 : C.ink3),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: ts(dark, size: 13.5),
              cursorHeight: 15,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (v) => _setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: t('搜索设置'),
                hintStyle: ts(dark, size: 13.5, color: dark ? C.dInk3 : C.ink3),
              ),
            ),
          ),
          if (_q.isNotEmpty)
            GestureDetector(
              onTap: () {
                _search.clear();
                _setState(() => _q = '');
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Icon(Icons.cancel_rounded,
                    size: 16, color: dark ? C.dInk3 : C.ink3),
              ),
            ),
        ],
      ),
    );
  }

  /// 一组设置：一个圆角容器，行与行之间只有一条细线，没有阴影和卡片堆叠。
  Widget _groupCard(bool dark, List<SettingsCat> cats, AppSettings s) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairOf(dark), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < cats.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Container(height: 0.8, color: hairOf(dark)),
              ),
            _catRow(dark, cats[i], s),
          ],
        ],
      ),
    );
  }

  Widget _hubEmpty(bool dark, String q) {
    return Padding(
      padding: const EdgeInsets.only(top: 46),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                size: 26, color: dark ? C.dInk3 : C.ink3),
            const SizedBox(height: 12),
            Text('没有找到「$q」相关设置', style: ts(dark, size: 13)),
            const SizedBox(height: 5),
            Text(t('换个关键词试试'), style: meta(dark, size: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _catRow(bool dark, SettingsCat c, AppSettings s) {
    final muted = dark ? C.dInk3 : C.ink3;
    return InkWell(
      onTap: () => _openCat(c.id),
      splashColor: (dark ? Colors.white : Colors.black).withOpacity(0.03),
      highlightColor: Colors.transparent,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(c.icon, size: 20, color: dark ? C.dInk2 : C.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: dark ? C.dInk : C.ink,
                        )),
                    const SizedBox(height: 2),
                    Text(_summary(c.id, s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: muted,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  /// 分类卡上的动态摘要：不点进去也能看到关键状态。
  String _summary(String id, AppSettings s) {
    switch (id) {
      case 'connection':
        return '${s.activeProfile.name} · ${s.model.isEmpty ? "未设模型" : s.model}';
      case 'relay':
        return '${kRelayPresets.length} 个项目 · 公益实例 · 全网搜索';
      case 'free':
        return '${kFreeEndpoints.length} 个免密源 · 一键测试';
      case 'appearance':
        // 摘要里不放中文标签：换成外语界面时，这一行也得是外语才不割裂。
        final skinName = Skin.byId(s.skinId)?.name ?? t('自定义');
        return '$skinName · ${(s.fontScale * 100).round()}%';
      case 'language':
        final ui = uiLangByCode(s.uiLang);
        return '${ui?.native ?? '简体中文'} · ${replyLangLabel(s.replyLang)}';
      case 'persona':
        // 没有形象时不写「未设置」这类占位词，只说这一栏能干什么。
        return s.personas.isEmpty
            ? '头像用软件图标 · 点进去新建'
            : '${s.activePersona.name} · 共 ${s.personas.length} 个形象';
      case 'voice':
        return _voiceBrief(s);
      case 'agent': {
        final n = <bool>[
          s.agentAllowWorkspace,
          s.agentAllowExternal,
          s.agentAllowSystem,
          s.agentAllowNetwork,
          s.agentAllowDevice,
        ].where((e) => e).length;
        return s.agentEnabled
            ? '${_permName(s.agentPermissionLevel)} · $n 组授权 · 每次确认${s.agentConfirmEach ? "开" : "关"}'
            : '未启用 · 仅回答问题';
      }
      case 'capability':
        return '${s.tier.label} · 思考${s.deepThinking ? "开" : "关"} · 联网${s.webSearch ? "开" : "关"}';
      case 'vision':
        return s.visionFormat.label;
      case 'search':
        return '已启用 ${s.activeSources.length} 个源 · 每源 ${s.searchCount} 条';
      case 'research':
        return '${s.researchWorkflow ? "工作流已开" : "工作流未启用"} · ${st.records.length} 条记录';
      case 'presets':
        return '当前：${s.activePreset.name}（${s.promptPresets.length} 份）';
      case 'usage':
        final models = st.tokenStats.byModel.length;
        final days = st.tokenStats.days.length;
        return '累计 ${st.tokenStats.total} tok · 今日 ${st.tokenStats.todayTotal}'
            '${models > 0 ? ' · $models 个模型' : ''}'
            '${days > 1 ? ' · $days 天' : ''}';
      case 'games':
        return '2 ${t('个 AI 玩法')} · 7 ${t('个离线小游戏')}';
      case 'cache':
        return '命中 ${st.cacheLedger.hits} 次 · ${st.responseCache.size} 条缓存';
      case 'billing':
        final c = st.totalCost;
        return c == null ? '未设置单价' : '累计约 ¥${c.toStringAsFixed(4)}';
      default:
        return '';
    }
  }

  String _permName(int lv) => switch (lv) {
        AppSettings.kPermMinimal => t('少量权限'),
        AppSettings.kPermStandard => t('标准权限'),
        AppSettings.kPermFull => t('完全权限'),
        _ => t('自定义'),
      };

  String _voiceBrief(AppSettings s) {
    final tts = ttsEngineById(s.ttsEngineId)?.name ?? '系统语音';
    final stt = sttEngineById(s.sttEngineId)?.name ?? '系统识别';
    return '朗读 $tts · 输入 $stt';
  }

  /// 子页：只构建当前分类那一张卡片。
  Widget _detail(bool dark, String id) {
    final s = st.settings;
    return SingleChildScrollView(
      key: PageStorageKey('settings_$id'),
      padding: const EdgeInsets.fromLTRB(D.pagePad, 10, D.pagePad, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_catById(id).showDesc)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                _catById(id).desc,
                style: meta(dark,
                    size: 12,
                    height: 1.55,
                    color: dark ? C.dInk2 : C.ink2),
              ),
            ),
          _cardFor(dark, id, s),
        ],
      ),
    );
  }

  Widget _cardFor(bool dark, String id, AppSettings s) {
    switch (id) {
      case 'connection':
        return _connectionCard(dark, s);
      case 'relay':
        return RelayPanel(
          dark: dark,
          currentBaseUrl: s.baseUrl,
          onAdd: _addRelay,
        );
      case 'free':
        return FreePoolPanel(
          dark: dark,
          profiles: s.profiles,
          onAdd: _addFree,
        );
      case 'appearance':
        return _section(dark, '外观主题', _appearanceSection(dark, s));
      case 'language':
        return _section(dark, '语言', _languageSection(dark, s));
      case 'persona':
        return _personaCard(dark, s);
      case 'voice':
        return VoicePanel(dark: dark);
      case 'agent':
        return AgentPanel(dark: dark);
      case 'capability':
        return _capabilityCard(dark, s);
      case 'vision':
        return _section(dark, '图片与多模态', _visionSection(dark, s));
      case 'search':
        return _searchSection(dark, s);
      case 'research':
        return _researchCard(dark);
      case 'presets':
        return _presetCard(dark, s);
      case 'usage':
        return _usageCard(dark);
      case 'cache':
        return CachePanel(dark: dark);
      case 'billing':
        return BillingPanel(dark: dark);
      case 'games':
        return GamesHub(dark: dark);
      default:
        return const SizedBox.shrink();
    }
  }

  // ------------------------------------------------------------ 连接子页

  Widget _connectionCard(bool dark, AppSettings s) {
    return _section(dark, '连接', [
      _profileBar(dark, s),
      const SizedBox(height: 20),
      _field('API BASE URL', _base,
          dark: dark,
          hint: 'https://api.openai.com/v1',
          onChanged: (_) => _onConnChanged()),
      const SizedBox(height: 16),
      _field('API KEY', _key,
          dark: dark,
          hint: t('sk-…（本地 Ollama 可留空）'),
          obscure: _obscure,
          onChanged: (_) => _onConnChanged(),
          suffix: GestureDetector(
            onTap: () => _setState(() => _obscure = !_obscure),
            child: Text(
              _obscure ? '显示' : '隐藏',
              style: meta(dark, size: 11.5, color: accentOf(dark)),
            ),
          )),
      const SizedBox(height: 20),
      _modelPicker(dark),
      const SizedBox(height: 12),
      SwitchRow(
        title: t('临时凭据（用完即销毁）'),
        subtitle: t('不写入磁盘，仅保留在本次会话内存中'),
        value: s.ephemeral,
        onChanged: (v) async {
          await st.setEphemeral(v);
          if (mounted) _setState(() {});
        },
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _destroy(dark),
          child: Text(t('销毁本地凭据'), style: meta(dark, size: 11.5, color: C.danger)),
        ),
      ),
      const SizedBox(height: 10),
      Text(t('凭据经 AES 加密仅存本机，请求直发你填写的接口。'), style: meta(dark, size: 11.5)),
      const SizedBox(height: 12),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openCat('relay'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 窄屏 + 大字号时这行会超宽（「在电脑上跑着 g4f / chat2api /
            // Ollama？」本身就有十九个字），交给 Flexible 折行，
            // 别把「一键接入」挤出屏幕。
            Flexible(
              child: Text(t('在电脑上跑着 g4f / chat2api / Ollama？'),
                  style: meta(dark, size: 11.5)),
            ),
            const SizedBox(width: 5),
            Text(t('一键接入'), style: meta(dark, size: 11.5, color: accentOf(dark))),
            Icon(Icons.chevron_right_rounded, size: 13, color: accentOf(dark)),
          ],
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------ 能力子页

  Widget _capabilityCard(bool dark, AppSettings s) {
    return _section(dark, '能力', [
      TierSelector(
        value: s.tier,
        onChanged: (t) => _toggle((x) => x.tier = t),
      ),
      const SizedBox(height: 12),
      SwitchRow(
        title: t('深度思考'),
        subtitle: t('先完成推理再输出结论，只显示摘要'),
        value: s.deepThinking,
        onChanged: (v) => _toggle((x) => x.deepThinking = v),
      ),
      SwitchRow(
        title: t('联网搜索'),
        subtitle: s.searchActive
            ? '已启用 · ${s.activeSources.length} 个搜索源'
            : (s.webSearch ? '已开启但未选择搜索源，不会发起检索' : '未启用 · 请求不经过任何搜索服务'),
        value: s.webSearch,
        onChanged: (v) => _toggle((x) => x.webSearch = v),
      ),
    ]);
  }

  // ------------------------------------------------------------ 研究子页

  Widget _researchCard(bool dark) {
    final s = st.settings;
    return _section(dark, '研究工作台', [
      SwitchRow(
        title: t('深度研究工作流'),
        subtitle: t('多轮检索 → 大纲 → 逐节展开 → 汇总报告'),
        value: s.researchWorkflow,
        onChanged: (v) => _toggle((x) => x.researchWorkflow = v),
      ),
      SwitchRow(
        title: t('原始输出'),
        subtitle: t('等宽原样呈现，不解析 Markdown、不转换引用'),
        value: s.rawOutput,
        onChanged: (v) => _toggle((x) => x.rawOutput = v),
      ),
      SwitchRow(
        title: t('自动记录实验'),
        subtitle: t('保存参数与响应原文，最多 120 条'),
        value: s.autoRecord,
        onChanged: (v) => _toggle((x) => x.autoRecord = v),
      ),
      SwitchRow(
        title: t('用量追踪'),
        subtitle: t('索取真实 usage；若接口报错可关闭，退化为估算 ≈'),
        value: s.usageTracking,
        onChanged: (v) => _toggle((x) => x.usageTracking = v),
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          Expanded(
              child: _btn(dark, '开始深度研究', () => _open(const ResearchLauncher()),
                  primary: true)),
          const SizedBox(width: 8),
          Expanded(
              child: _btn(dark, 'Token 用量', () => _open(const UsageSheet()))),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
              child: _btn(dark, '实验记录 · ${st.records.length}',
                  () => _open(const RecordsSheet()))),
          const SizedBox(width: 8),
          Expanded(
              child: _btn(dark, '导出报告', () async {
            await Clipboard.setData(
                ClipboardData(text: st.exportResearchReport()));
            _toast('研究报告已复制到剪贴板');
          })),
        ],
      ),
    ]);
  }

  // ------------------------------------------------------------ 预设子页

  Widget _presetCard(bool dark, AppSettings s) {
    return _section(dark, '提示词预设库', [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('当前预设'), style: sectionTitle(dark)),
                const SizedBox(height: 5),
                Text(
                  '${s.activePreset.name}  ·  '
                  '${s.activePreset.builtin ? "内置" : "自定义"}  ·  '
                  '${s.promptPresets.length} 份',
                  style: ts(dark, size: 13.5, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _openPresetManager,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: fieldOf(dark),
                borderRadius: BorderRadius.circular(D.r),
                border: Border.all(color: borderOf(dark)),
              ),
              child: Text(t('管理 / 切换'),
                  style: meta(dark, size: 11.5, color: accentOf(dark))),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(t('可用变量：{{query}} {{date}} {{time}} {{model}} {{language}} {{sources}} {{tier}}，发送前替换为真实值。'),
        style: meta(dark, size: 11.5),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _prompt,
        minLines: 5,
        maxLines: 10,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.6,
          color: dark ? C.dInk : C.ink,
        ),
        decoration: fieldDecoration(dark,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13)),
        onChanged: (_) => _scheduleSave(),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _btn(dark, '应用', () {
              _persistAll();
              _toast('当前预设已生效');
            }, primary: true),
          ),
          const SizedBox(width: 8),
          Expanded(child: _btn(dark, '预览请求体', () => _preview(dark))),
          const SizedBox(width: 8),
          Expanded(
            child: _btn(dark, '还原内置', () {
              final id = s.activePreset.id;
              final builtin = defaultPresets().where((e) => e.id == id);
              _prompt.text = builtin.isNotEmpty
                  ? builtin.first.content
                  : kDefaultSystemPrompt;
              _persistAll();
              _setState(() {});
              _toast('已还原此预设的内置内容');
            }),
          ),
        ],
      ),
    ]);
  }

  // ------------------------------------------------------------ 用量子页

  Widget _usageCard(bool dark) {
    return _section(dark, '用量概览', [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('累计'), style: meta(dark, size: 11.5)),
                const SizedBox(height: 4),
                Text('${st.tokenStats.total} tok',
                    style: ts(dark, size: 20, weight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('今日'), style: meta(dark, size: 11.5)),
                const SizedBox(height: 4),
                Text('${st.tokenStats.todayTotal} tok',
                    style: ts(dark, size: 20, weight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('请求'), style: meta(dark, size: 11.5)),
                const SizedBox(height: 4),
                Text('${st.tokenStats.requests}',
                    style: ts(dark, size: 20, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(t('真实 usage 优先；网关未返回时按字符估算并标 ≈。'), style: meta(dark, size: 11.5)),
      const SizedBox(height: 12),
      _btn(dark, '打开用量面板与单价设置', () => _open(const UsageSheet())),
    ]);
  }

  // ------------------------------------------------------------ 人物形象

  Widget _personaCard(bool dark, AppSettings s) {
    final st = this.st;
    final current = s.activePersona;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(dark, '形象库', [
          SizedBox(
            // 74 在默认字号下刚好，1.38 倍字号时文字会顶出 3px；
            // 给足 80，并且不让文字折行。
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: s.personas.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i == s.personas.length) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      st.addPersona('新形象');
                      _setState(() {});
                      _toast('已创建，可在下方编辑');
                    },
                    child: SizedBox(
                      width: 58,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: borderOf(dark)),
                            ),
                            child: Icon(Icons.add_rounded,
                                size: 20, color: accentOf(dark)),
                          ),
                          const SizedBox(height: 6),
                          Text(t('新建'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: meta(dark, size: 11.5)),
                        ],
                      ),
                    ),
                  );
                }
                final p = s.personas[i];
                final on = p.id == s.activePersonaId;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    st.setActivePersona(p.id);
                    _setState(() {});
                  },
                  child: SizedBox(
                    width: 58,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: on
                                ? Border.all(color: accentOf(dark), width: 1.6)
                                : null,
                          ),
                          child: PersonaAvatar(
                              persona: p, size: 42, dark: dark, ring: false),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta(dark,
                              size: 11.5, color: on ? accentOf(dark) : null),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child:
                    Text('当前默认：${current.name}', style: meta(dark, size: 11.5)),
              ),
              if (!current.builtin)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(t('删除形象')),
                        content: Text('将删除「${current.name}」，引用它的工作台会回落到全局默认。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(t('取消'))),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(t('删除'))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      st.deletePersona(current.id);
                      _setState(() {});
                    }
                  },
                  child: Text(t('删除此形象'),
                      style: meta(dark, size: 11.5, color: C.danger)),
                ),
            ],
          ),
        ]),
        _section(dark, '编辑 · ${current.name}', [
          PersonaEditor(
            key: ValueKey('pe_${current.id}'),
            persona: current,
            dark: dark,
            onChanged: () {
              if (mounted) _setState(() {});
            },
          ),
        ]),
        _section(dark, '显示方式', [
          SwitchRow(
            title: t('启用人物形象'),
            subtitle: t('关闭后主界面回到纯工作台样式'),
            value: s.personaEnabled,
            onChanged: (v) => _toggle((x) => x.personaEnabled = v),
          ),
          SwitchRow(
            title: t('顶部形象区'),
            subtitle: t('消息列表上方显示头像与名字'),
            value: s.showPersonaHeader,
            onChanged: (v) => _toggle((x) => x.showPersonaHeader = v),
          ),
          SwitchRow(
            title: t('助手消息头像'),
            subtitle: t('每条回答前显示形象小头像'),
            value: s.showBubbleAvatar,
            onChanged: (v) => _toggle((x) => x.showBubbleAvatar = v),
          ),
          const SizedBox(height: 10),
          Text(t('每个工作台还可在顶栏头像处单独指定形象；角色设定会作为身份说明写入 System Prompt，只影响语气与风格，不改变模型本身的能力边界。'),
            style: meta(dark, size: 11.5),
          ),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------ 外观

  List<Widget> _appearanceSection(bool dark, AppSettings s) {
    final sysDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final current = Skin.byId(s.skinId);
    return [
      Text(t('明暗模式'), style: sectionTitle(dark)),
      const SizedBox(height: 10),
      Row(
        children: AppThemeMode.values.map((m) {
          final on = s.themeMode == m;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggle((x) => x.themeMode = m),
              child: Container(
                height: 38,
                margin: EdgeInsets.only(right: m == AppThemeMode.dark ? 0 : 7),
                decoration: BoxDecoration(
                  color: on ? C.brand : surfaceOf(dark),
                  borderRadius: BorderRadius.circular(D.r),
                  border: on ? null : Border.all(color: borderOf(dark)),
                  boxShadow: on ? softShadow(dark, scale: 0.4) : null,
                ),
                child: Center(
                  child: Text(m.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? Colors.white : (dark ? C.dInk2 : C.ink2),
                      )),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text(t('系统当前'), style: meta(dark, size: 11.5)),
        const Spacer(),
        Text(sysDark ? '深色' : '浅色',
            style: meta(dark, size: 11.5, color: accentOf(dark))),
      ]),
      const SizedBox(height: 24),
      Row(children: [
        Text(t('主题'), style: sectionTitle(dark)),
        const Spacer(),
        Text(
          current?.name ?? '自定义',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: accentOf(dark),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Text('${kSkinPresets.length} 套内置，也可以自己做一套。点一下整站立即换色。',
          style: meta(dark, size: 11.5, height: 1.5)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (_, box) {
        const gap = 9.0;
        final w = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in kSkinPresets) _skinCard(dark, s, p, w),
            _skinCustomCard(dark, s, w),
          ],
        );
      }),
      if (s.skinId == 'custom') ...[
        const SizedBox(height: 16),
        _customSkinPanel(dark, s),
      ],
      const SizedBox(height: 24),
      Text(t('字号'), style: sectionTitle(dark)),
      const SizedBox(height: 6),
      Row(children: [
        Text('${(s.fontScale * 100).round()}%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: accentOf(dark),
            )),
        const Spacer(),
        Text(t('预览：静水深流，字要看得清'), style: meta(dark, size: 12)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: accentOf(dark),
          inactiveTrackColor: borderOf(dark),
          thumbColor: accentOf(dark),
        ),
        child: Slider(
          value: s.fontScale.clamp(0.85, 1.4),
          min: 0.85,
          max: 1.4,
          divisions: 22,
          onChanged: (v) =>
              _toggle((x) => x.fontScale = double.parse(v.toStringAsFixed(2))),
        ),
      ),
      Row(
        children: [
          for (var i = 0; i < kFontScales.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggle((x) => x.fontScale = kFontScales[i].value),
                child: Container(
                  height: 32,
                  margin: EdgeInsets.only(
                      right: i == kFontScales.length - 1 ? 0 : 7),
                  decoration: BoxDecoration(
                    color: (s.fontScale - kFontScales[i].value).abs() < 0.01
                        ? C.brand
                        : surfaceOf(dark),
                    borderRadius: BorderRadius.circular(D.r),
                    border: (s.fontScale - kFontScales[i].value).abs() < 0.01
                        ? null
                        : Border.all(color: borderOf(dark)),
                  ),
                  child: Center(
                    child: Text(
                      t(kFontScales[i].label),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            (s.fontScale - kFontScales[i].value).abs() < 0.01
                                ? FontWeight.w600
                                : FontWeight.w400,
                        color: (s.fontScale - kFontScales[i].value).abs() < 0.01
                            ? Colors.white
                            : (dark ? C.dInk2 : C.ink2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 9),
      Text(t('只缩放文字，不改行高与间距，调大也不会把按钮撑破。'),
          style: meta(dark, size: 11.5)),
    ];
  }

  /// 主题卡：迷你「一屏」预览。上半是画布，中间一块纸面，右下角一颗强调点。
  Widget _skinCard(bool dark, AppSettings s, SkinPreset p, double width) {
    final on = s.skinId == p.id;
    final pl = dark ? p.dark : p.light;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle((x) => x.skinId = p.id),
      child: AnimatedContainer(
        duration: D.anim,
        width: width,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: surfaceOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(
            color: on ? accentOf(dark) : borderOf(dark),
            width: on ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skinPreview(pl),
            const SizedBox(height: 7),
            Row(children: [
              Flexible(
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: dark ? C.dInk : C.ink,
                    )),
              ),
              if (on) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle_rounded,
                    size: 13, color: accentOf(dark)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(p.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta(dark, size: 10.5)),
          ],
        ),
      ),
    );
  }

  Widget _skinPreview(Palette pl) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: pl.bg,
        borderRadius: BorderRadius.circular(7),
      ),
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: pl.accent, shape: BoxShape.circle),
          ),
          const Spacer(),
          Container(
            height: 9,
            width: 40,
            decoration: BoxDecoration(
              color: pl.surface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: pl.border, width: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 7,
            width: 24,
            decoration: BoxDecoration(
              color: pl.chip,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skinCustomCard(bool dark, AppSettings s, double width) {
    final on = s.skinId == 'custom';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle((x) => x.skinId = 'custom'),
      child: AnimatedContainer(
        duration: D.anim,
        width: width,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: surfaceOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(
            color: on ? accentOf(dark) : borderOf(dark),
            width: on ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: colorFromHex(s.skinCanvas, const Color(0xFFF6F7F9)),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderOf(dark), width: 0.6),
              ),
              child: Center(
                child: Icon(Icons.colorize_rounded,
                    size: 18, color: colorFromHex(s.skinAccent, C.brand)),
              ),
            ),
            const SizedBox(height: 7),
            Row(children: [
              Text(t('自定义'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: dark ? C.dInk : C.ink,
                  )),
              if (on) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle_rounded,
                    size: 13, color: accentOf(dark)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(t('主色 · 页面 · 圆角'), style: meta(dark, size: 10.5)),
          ],
        ),
      ),
    );
  }

  /// 自定义面板：只给三颗真正影响观感的旋钮，避免一屏几十个色值。
  Widget _customSkinPanel(bool dark, AppSettings s) {
    const accents = [
      Color(0xFF3478F6),
      Color(0xFF0EA5A5),
      Color(0xFF17A34A),
      Color(0xFFE07B39),
      Color(0xFFD9534F),
      Color(0xFFD9538F),
      Color(0xFF8B5CF6),
      Color(0xFF5E6AD2),
      Color(0xFFA16207),
      Color(0xFF6B7280),
      Color(0xFF111111),
      Color(0xFFC08A2E),
    ];
    const canvases = [
      Color(0xFFFFFFFF),
      Color(0xFFF6F7F9),
      Color(0xFFFAF9F5),
      Color(0xFFF1EFE7),
      Color(0xFFEDF2F7),
      Color(0xFFF4F0FA),
    ];
    final accent = colorFromHex(s.skinAccent, C.brand);
    final canvas = colorFromHex(s.skinCanvas, const Color(0xFFF6F7F9));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius: BorderRadius.circular(D.cardR),
        border: Border.all(color: borderOf(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('主色'), style: sectionTitle(dark)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in accents)
                GestureDetector(
                  onTap: () =>
                      _toggle((x) => x.skinAccent = hexOf(c)),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.value == c.value
                            ? (dark ? Colors.white : Colors.black)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(t('页面底色'), style: sectionTitle(dark)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in canvases)
                GestureDetector(
                  onTap: () => _toggle((x) => x.skinCanvas = hexOf(c)),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: canvas.value == c.value
                            ? accent
                            : borderOf(dark),
                        width: canvas.value == c.value ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Text(t('圆角'), style: sectionTitle(dark)),
            const Spacer(),
            Text('${(s.skinRadius * 100).round()}%',
                style: meta(dark, size: 11.5, color: accentOf(dark))),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: accentOf(dark),
              inactiveTrackColor: borderOf(dark),
              thumbColor: accentOf(dark),
            ),
            child: Slider(
              value: s.skinRadius.clamp(0.6, 1.4),
              min: 0.6,
              max: 1.4,
              divisions: 16,
              onChanged: (v) => _toggle(
                  (x) => x.skinRadius = double.parse(v.toStringAsFixed(2))),
            ),
          ),
          Text(t('圆角只作用于卡片、按钮与输入台，不影响排版。'),
              style: meta(dark, size: 11)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 语言

  List<Widget> _languageSection(bool dark, AppSettings s) {
    final ui = uiLangByCode(s.uiLang);
    return [
      Text(t('界面语言'), style: sectionTitle(dark)),
      const SizedBox(height: 8),
      _pickRow(dark, ui?.native ?? '简体中文', t('按钮、标题与说明文字都跟着换'),
          _pickUiLang),
      const SizedBox(height: 8),
      Text(
        t('切换后整站文字立即变成该语言，不留中文；少数深层说明若尚未翻译会以英文显示。'
            '回答语言与识别语言在下面单独设置，互不影响。'),
        style: meta(dark, size: 11.5, height: 1.5),
      ),
      const SizedBox(height: 22),
      Text(t('对话语言'), style: sectionTitle(dark)),
      const SizedBox(height: 8),
      _pickRow(dark, replyLangLabel(s.replyLang), t('AI 用这种语言回答'),
          _pickReplyLang),
      const SizedBox(height: 8),
      Text(t('「跟随提问」不追加任何语言指令，由模型自行判断；选定后会写进 System Prompt。'),
        style: meta(dark, size: 11.5, height: 1.5),
      ),
      const SizedBox(height: 22),
      Text(t('语音识别语言'), style: sectionTitle(dark)),
      const SizedBox(height: 8),
      _pickRow(dark, speechLangLabel(s.voiceLang), '听写按这种语言转写',
          _pickSpeechLang),
      const SizedBox(height: 8),
      Text(t('选错语种最常见的表现是「听得到、但转成另一门语言」。带口音时优先选同语种的地区版本。'),
        style: meta(dark, size: 11.5, height: 1.5),
      ),
      const SizedBox(height: 20),
      Text(t('识别语言只影响听写；说错语种时转写会串到另一门语言。'),
          style: meta(dark, size: 11.5, color: dark ? C.dInk3 : C.ink3)),
    ];
  }

  Future<void> _pickUiLang() async {
    final st = context.read<AppState>();
    final code = await showLangPicker(
      context,
      dark: st.settings.darkMode,
      title: t('界面语言'),
      items: [
        // 中文界面里显示「中文名 + 本地写法」；已经切成别的语言后，
        // 再摆一列中文名就等于没翻译，所以只留本地写法。
        for (final l in kUiLangs)
          LangItem(l.code, L10n.isZh ? l.name : l.native, L10n.isZh ? l.native : ''),
      ],
      selected: st.settings.uiLang,
    );
    if (code == null || !mounted) return;
    // 先把词表读进来，再改设置：否则 MaterialApp 会先重建一帧英文。
    await L10n.load(code);
    if (!mounted) return;
    _toggle((x) => x.uiLang = code);
    if (mounted) _setState(() {});
  }

  Widget _pickRow(
      bool dark, String value, String hint, Future<void> Function() onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        decoration: BoxDecoration(
          color: fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(color: borderOf(dark)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: ts(dark, size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(hint, style: meta(dark, size: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 19, color: dark ? C.dInk3 : C.ink3),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReplyLang() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final code = await showLangPicker(
      context,
      dark: dark,
      title: t('对话语言'),
      items: [
        for (final l in kReplyLangs)
          LangItem(l.code, L10n.isZh ? l.label : l.native,
              L10n.isZh ? l.native : ''),
      ],
      selected: st.settings.replyLang,
    );
    if (code != null && code != st.settings.replyLang) {
      _toggle((x) => x.replyLang = code);
    }
  }

  Future<void> _pickSpeechLang() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final code = await showLangPicker(
      context,
      dark: dark,
      title: t('语音识别语言'),
      items: [
        for (final l in kSpeechLangs)
          LangItem(l.code, L10n.isZh ? l.label : l.native,
              L10n.isZh ? l.native : ''),
      ],
      selected: st.settings.voiceLang,
    );
    if (code != null && code != st.settings.voiceLang) {
      _toggle((x) => x.voiceLang = code);
    }
  }

  // ------------------------------------------------------------ 多模态
  List<Widget> _visionSection(bool dark, AppSettings s) {
    final vision = looksLikeVisionModel(s.model);
    return [
      Row(children: [
        Text(t('当前模型'), style: meta(dark, size: 11.5)),
        const Spacer(),
        Flexible(
          child: Text(s.model.isEmpty ? '未设置' : s.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: meta(dark, size: 11.5, color: accentOf(dark))),
        ),
      ]),
      const SizedBox(height: 7),
      Text(
        vision
            ? '✓ 名称看起来具备视觉能力，可以发送图片，最终以接口实际支持为准。'
            : '✕ 该模型名称不像视觉模型。DeepSeek、GPT-3.5 等纯文本模型无法识别图片，'
                '请改用 gpt-4o / Claude 3 / Gemini / Qwen-VL 等支持视觉的模型。',
        style: meta(dark, size: 11.5, color: vision ? null : C.warn),
      ),
      const SizedBox(height: 18),
      Text(t('图片发送格式'), style: sectionTitle(dark)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: VisionFormat.values.map((f) {
          final on = s.visionFormat == f;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggle((x) => x.visionFormat = f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: on ? C.brand : surfaceOf(dark),
                borderRadius: BorderRadius.circular(D.r),
                border: on ? null : Border.all(color: borderOf(dark)),
              ),
              child: Text(f.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? Colors.white : (dark ? C.dInk2 : C.ink2),
                  )),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 9),
      Text(s.visionFormat.note, style: meta(dark, size: 11.5)),
      const SizedBox(height: 16),
      _btn(dark, '图片诊断 / 请求体预览', () => _visionDiag(dark)),
      const SizedBox(height: 12),
      Text(t('图片以 base64 内联发送，单图长边 1280、质量 72。带图请求若报 400 / 413 / Connection closed，多为模型不支持视觉或中转不接受内联图片，可切换上方格式排查。'),
        style: meta(dark, size: 11.5),
      ),
    ];
  }

  void _visionDiag(bool dark) {
    _persistAll();
    final s = st.settings;
    final diags = st.imageDiagnostics;
    final msg = FileExtractService.imageMessage(
            '请分析这些图片。', st.pending, s.visionFormat) ??
        <String, dynamic>{'role': 'user', 'content': '（当前没有待发图片）'};
    final b = StringBuffer();
    b.writeln('模型：${s.model}');
    b.writeln('视觉能力判定：'
        '${looksLikeVisionModel(s.model) ? '可能支持' : '可能不支持'}');
    b.writeln('发送格式：${s.visionFormat.label}');
    b.writeln('编码后图片体积：'
        '${(st.imagePayloadBytes / 1024).toStringAsFixed(0)} KB');
    b.writeln('');
    if (diags.isEmpty) {
      b.writeln('待发图片：无（先在主界面选一张图再来看诊断）');
    } else {
      b.writeln('待发图片：');
      for (final d in diags) {
        b.writeln('  · ${d.name}');
        b.writeln('    真实格式 ${d.mime} · ${d.sizeLabel} · '
            'base64 ${(d.base64Len / 1024).toStringAsFixed(0)} KB'
            '${d.supported ? '' : '  ← 多数视觉模型不支持该格式'}');
        if (d.note != null) b.writeln('    ${d.note}');
      }
    }
    b.writeln('');
    b.writeln('最终消息结构（base64 已省略）：');
    b.writeln(_redactImageBody(msg));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('图片诊断'), style: ts(dark, size: 15, weight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(b.toString(),
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.6,
                    color: dark ? C.dInk2 : C.ink2)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('关闭'))),
        ],
      ),
    );
  }

  String _redactImageBody(Map<String, dynamic> m) {
    final copy = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
    final c = copy['content'];
    if (c is List) {
      for (final p in c) {
        if (p is Map && p['type'] == 'image_url') {
          final u = p['image_url'];
          if (u is Map && u['url'] is String) {
            final s = u['url'] as String;
            final i = s.indexOf('base64,');
            if (i >= 0) {
              u['url'] = '${s.substring(0, i + 7)}<已省略 ${s.length - i - 7} 字符>';
            }
          }
        }
      }
    }
    final imgs = copy['images'];
    if (imgs is List) {
      for (var k = 0; k < imgs.length; k++) {
        imgs[k] = '<已省略 ${imgs[k].toString().length} 字符 base64>';
      }
    }
    return const JsonEncoder.withIndent('  ').convert(copy);
  }

  // ------------------------------------------------------------------ 模型

  /// v4.12：这一页只围绕「当前这个 API」组织——它有多少个模型、当前选了
  /// 哪个、到底能不能用、点一下就能换。跨所有连接的搜索收在下面，
  /// 不再把「N 个系列 / M 个连接」这种汇总数字铺在最显眼的位置。
  Widget _modelPicker(bool dark) {
    return Selector<AppState,
        ({
          bool loading,
          String? error,
          String model,
          bool showAll,
          String pid,
          int pn,
          int count,
          String profile
        })>(
      selector: (_, s) => (
        loading: s.modelsLoading,
        error: s.modelsError,
        model: s.settings.model,
        showAll: s.settings.showAllModels,
        pid: s.settings.activeProfileId,
        pn: s.settings.profiles.length,
        count: s.models.length,
        profile: s.settings.activeProfile.name,
      ),
      builder: (context, snap, _) {
        final state = context.read<AppState>();
        _syncModel(snap.model);
        final list = snap.showAll ? state.models : state.chatModels;
        final shown = list.take(30).toList();
        final catalog = state.modelCatalog;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 当前连接：名字 + 这个 API 下有多少个模型 + 刷新
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('当前 API'), style: meta(dark, size: 11.5)),
                      const SizedBox(height: 2),
                      Text('${snap.profile} · ${snap.count} 个模型',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              ts(dark, size: 13.5, weight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (snap.loading)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.4, color: accentOf(dark)),
                  )
                else
                  GestureDetector(
                    onTap: () async {
                      await _persistAll();
                      final ok = await state.refreshModels(
                          baseUrl: _base.text, apiKey: _key.text);
                      if (mounted) {
                        _toast(ok
                            ? '模型列表已更新'
                            : (state.modelsError ?? '拉取失败'));
                      }
                    },
                    child: Text(t('刷新'),
                        style: meta(dark, size: 12, color: accentOf(dark))),
                  ),
              ],
            ),
            if (snap.error != null) ...[
              const SizedBox(height: 6),
              Text('读取失败：${snap.error}',
                  style: meta(dark, size: 11.5, color: C.warn)),
            ],
            const SizedBox(height: 10),
            // 2. 这个 API 下的模型列表
            Text(_manualModel ? '手动填写模型 ID' : '这个 API 下的模型',
                style: sectionTitle(dark)),
            const SizedBox(height: 6),
            if (_manualModel)
              _field('', _model,
                  dark: dark,
                  hint: t('手动填写模型 ID'),
                  onChanged: (_) => _scheduleSave())
            else if (shown.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: insetBox(dark),
                child: Text(t('还没有拉到模型列表，点右上角「刷新」读取。'),
                    style: sub(dark, size: 12.5)),
              )
            else
              Container(
                decoration: insetBox(dark),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 264),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => BrandModelTile(
                      modelId: shown[i].id,
                      subtitle: resolveModelBrand(shown[i].id).label,
                      selected: shown[i].id == snap.model,
                      dark: dark,
                      onTap: () => _pickLocalModel(state, shown[i].id),
                    ),
                  ),
                ),
              ),
            if (!_manualModel && list.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('还有 ${list.length - shown.length} 个，用下面搜索可直接定位',
                    style: meta(dark, size: 11.5)),
              ),
            const SizedBox(height: 16),
            // 3. 检测当前模型能不能用（真发一句最短请求，会花极少量额度）
            _probeCard(dark, state, snap.model),
            const SizedBox(height: 16),
            // 4. 跨连接查找（只在需要时出现）
            Text(t('在所有连接里查找'), style: sectionTitle(dark)),
            const SizedBox(height: 6),
            ModelSearchBox(
              dark: dark,
              catalog: catalog,
              currentModel: snap.model,
              showAll: snap.showAll,
              onPick: _pickCatalogModel,
              onManualUse: _useManualModel,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () =>
                      state.patch((x) => x.showAllModels = !x.showAllModels),
                  child: Text(
                    snap.showAll ? '✓ 显示全部模型' : '显示全部模型',
                    style: meta(
                        dark, size: 11.5, color: dark ? C.dInk2 : C.ink2),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _setState(() => _manualModel = !_manualModel),
                  child: Text(_manualModel ? '从列表选择' : '手动输入 ID',
                      style: meta(dark, size: 11.5, color: accentOf(dark))),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _probeCard(bool dark, AppState state, String model) {
    final p = _probe;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: insetBox(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.network_check_rounded,
                  size: 16, color: accentOf(dark)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('检测「${model.isEmpty ? '未指定' : model}」能否使用',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sub(dark, size: 12.5)),
              ),
              if (_probing)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.4, color: accentOf(dark)),
                )
              else
                GestureDetector(
                  onTap: () => _runProbe(state),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentOf(dark),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(t('开始检测'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (p != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                    p.ok
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 15,
                    color: p.ok ? C.ok : C.warn),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('${p.headline} · ${p.timing}\n${p.detail}',
                      style: meta(dark, size: 11.5, height: 1.55)),
                ),
              ],
            )
          else
            Text(t('会真发一句极短的问题，消耗少量额度。'),
                style: meta(dark, size: 11.5)),
        ],
      ),
    );
  }

  Future<void> _runProbe(AppState state) async {
    if (_probing) return;
    _setState(() {
      _probing = true;
      _probe = null;
    });
    await _persistAll();
    final r = await state.probeModel();
    if (!mounted) return;
    _setState(() {
      _probing = false;
      _probe = r;
    });
  }

  Future<void> _pickLocalModel(AppState state, String id) async {
    await _persistAll();
    await state.selectModel(id);
    if (!mounted) return;
    _model.text = id;
    _setState(() {});
    _toast('已选用 $id');
  }

  /// 点选目录中的模型：先把当前编辑写回配置，再按需切换连接。
  Future<void> _pickCatalogModel(ModelEntry e) async {
    await _persistAll();
    final changed = e.profileId != st.settings.activeProfileId;
    final name = e.profileName;
    await st.selectCatalogModel(e);
    if (!mounted) return;
    _loadActive();
    _model.text = e.id;
    _setState(() {});
    _toast(changed ? '已选用 ${e.id}，并切换到「$name」' : '已选用 ${e.id}');
  }

  /// 无命中时按输入的 ID 手动使用。
  void _useManualModel(String id) {
    _model.text = id;
    _persistAll();
    _setState(() => _manualModel = true);
    _toast('已填入 $id，可继续编辑');
  }

  // -------------------------------------------------------------- 搜索接口

  Widget _searchSection(bool dark, AppSettings s) {
    final enabled = s.activeSources;
    final total = SearchProvider.values.length;
    return _section(dark, '', [
      Text(
        '已启用 ${enabled.length} / $total',
        style: ts(dark, size: 13, weight: FontWeight.w600, height: 1.4),
      ),
      const SizedBox(height: 5),
      Text(t('点一下启用，再点关闭。只有启用的源才会参与联网检索。'),
        style: meta(dark,
            size: 12, height: 1.6, color: dark ? C.dInk2 : C.ink2),
      ),
      const SizedBox(height: 18),
      _sourceChips(dark, s),
      if (enabled.isEmpty) ...[
        const SizedBox(height: 2),
        Text(t('还没有启用任何源，联网搜索不会发起检索。'),
            style: meta(dark, size: 12, height: 1.6, color: C.warn)),
      ],
      if (enabled.isNotEmpty) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(t('已启用的源 · 点开填密钥或端点'), style: sectionTitle(dark)),
        ),
        for (final p in enabled) _sourceConfigRow(dark, s, p),
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          Text(t('每源结果条数'), style: ts(dark, size: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: fieldOf(dark),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: borderStrongOf(dark)),
            ),
            child: DropdownButton<int>(
              value: s.searchCount,
              underline: const SizedBox.shrink(),
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 6),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: dark ? C.dInk2 : C.ink2),
              style: ts(dark, size: 13, height: 1.3),
              items: const [3, 5, 8, 10, 15, 20]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n 条')))
                  .toList(),
              onChanged: (n) => _toggle((x) => x.searchCount = n ?? 5),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _testSources(dark),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: dark ? C.brand.withOpacity(0.16) : C.brandSoft,
            borderRadius: BorderRadius.circular(D.r),
            border: Border.all(color: accentOf(dark).withOpacity(0.32)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_tethering_rounded,
                  size: 16, color: accentOf(dark)),
              const SizedBox(width: 7),
              Text(t('测试已启用搜索源'),
                  style: ts(dark,
                      size: 13,
                      weight: FontWeight.w600,
                      color: accentOf(dark))),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(t('多源并行检索，按 URL 去重并交错合并引用；单个源失败不影响其他源。'),
          style: meta(dark,
              size: 11.5, height: 1.65, color: dark ? C.dInk2 : C.ink2)),
    ]);
  }

  Widget _sourceChips(bool dark, AppSettings s) {
    final groups = <String, List<SearchProvider>>{};
    for (final p in SearchProvider.values) {
      groups.putIfAbsent(p.group, () => <SearchProvider>[]).add(p);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((g) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.key, style: sectionTitle(dark)),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: g.value.map((p) {
                  final on = s.isSourceEnabled(p);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggle((x) => x.setSourceEnabled(p, !on)),
                    child: AnimatedContainer(
                      duration: D.animFast,
                      curve: D.curve,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        // 未启用：白底 + 明确的描边，读起来像「可以按」；
                        // 启用：淡蓝底 + 蓝边 + 勾，状态一眼可辨。
                        color: on
                            ? (dark ? C.brand.withOpacity(0.18) : C.brandSoft)
                            : (dark ? C.dSink : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: on
                              ? accentOf(dark).withOpacity(0.55)
                              : borderStrongOf(dark),
                          width: on ? 1.2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (on) ...[
                            Icon(Icons.check_rounded,
                                size: 14, color: accentOf(dark)),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            p.shortLabel,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontWeight:
                                  on ? FontWeight.w600 : FontWeight.w500,
                              color: on
                                  ? (dark ? C.dInk : C.ink)
                                  : (dark ? C.dInk2 : C.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 已启用的源：一行摘要，点开才出现输入框。
  /// 六个源全部展开时是一屏半的输入框，真正要改的东西会被淹没。
  Widget _sourceConfigRow(bool dark, AppSettings s, SearchProvider p) {
    final open = _openSource.contains(p.name);
    final savedEp = s.sourceEndpoint(p);
    final overrideEp = savedEp == p.endpoint ? '' : savedEp;
    final missingKey = p.needsKey && s.sourceKey(p).trim().isEmpty;
    final muted = dark ? C.dInk2 : C.ink2;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setState(() {
              if (open) {
                _openSource.remove(p.name);
              } else {
                _openSource.add(p.name);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(p.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(dark,
                            size: 13.5, weight: FontWeight.w500, height: 1.3)),
                  ),
                  if (missingKey) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: C.warn.withOpacity(dark ? 0.22 : 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(t('待填密钥'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: C.warn)),
                    ),
                    const SizedBox(width: 7),
                  ] else ...[
                    Text(
                      p.needsKey
                          ? '需密钥'
                          : (p.showKeyField ? '可选密钥' : '免密钥'),
                      style: meta(dark, size: 11.5, color: muted),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p.note.isNotEmpty) ...[
                    Text(p.note,
                        style:
                            meta(dark, size: 11.5, height: 1.6, color: muted)),
                    const SizedBox(height: 10),
                  ],
                  if (p.showKeyField) ...[
                    _field(p.keyLabel, _ctl(_srcKey, p.name, s.sourceKey(p)),
                        dark: dark,
                        hint: t('填入该服务商的密钥'),
                        onChanged: (_) => _scheduleSave()),
                    const SizedBox(height: 10),
                  ],
                  _field(
                    'Endpoint 覆盖',
                    _ctl(_srcEp, p.name, overrideEp),
                    dark: dark,
                    hint: p.endpoint.isEmpty
                        ? '必填，支持 {query} / {q} / {count} 占位符'
                        : '留空使用默认：${p.endpoint}',
                    onChanged: (_) => _scheduleSave(),
                  ),
                  if (p.needsCx) ...[
                    const SizedBox(height: 10),
                    _field(
                      'Google CSE CX',
                      _ctl(_srcCx, p.name, s.sourceCx(p)),
                      dark: dark,
                      hint: t('自定义搜索引擎 ID'),
                      onChanged: (_) => _scheduleSave(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _testSources(bool dark) async {
    await _persistAll();
    if (!mounted) return;
    _toast('正在并行测试已启用搜索源…');
    final res = await st.searchSvc.testAll('flutter', st.settings);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(t('搜索源连通性'), style: ts(dark, size: 15, weight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: res.isEmpty
                  ? <Widget>[Text(t('未启用任何搜索源'), style: sub(dark, size: 12.5))]
                  : res.entries
                      .map<Widget>((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(e.key.shortLabel,
                                      style: ts(dark, size: 13)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(e.value,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: e.value.startsWith('失败')
                                            ? C.warn
                                            : (dark ? C.dInk3 : C.ink3),
                                      )),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('关闭'))),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 通用

  /// 分区：白色纸片 + 1px 实描边。标题用正文级字号与实色，
  /// 不再用 12px 浅灰——一页里最该被看见的一行反而最淡，整页就会发灰。
  Widget _section(bool dark, String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderOf(dark), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: dark ? C.dInk : C.ink,
              ),
            ),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {required bool dark,
      String? hint,
      bool obscure = false,
      Widget? suffix,
      ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label,
              style: meta(dark,
                  size: 11.5,
                  color: dark ? C.dInk2 : C.ink2,
                  height: 1.35)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: c,
          obscureText: obscure,
          maxLines: 1,
          style: ts(dark, size: 13.5, height: 1.4),
          decoration: fieldDecoration(
            dark,
            hint: hint,
            suffix: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 10), child: suffix),
          ),
          onChanged: onChanged ?? (_) => _scheduleSave(),
        ),
      ],
    );
  }

  Widget _btn(bool dark, String text, VoidCallback onTap,
      {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: primary ? C.brand : surfaceOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: primary ? null : Border.all(color: borderOf(dark)),
          boxShadow: primary ? softShadow(dark, scale: 0.45) : null,
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary ? Colors.white : (dark ? C.dInk2 : C.ink2),
            ),
          ),
        ),
      ),
    );
  }

  void _open(Widget sheet) {
    _persistAll();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  /// 预设库里可能切换/新建/重命名预设，关闭面板后把编辑框同步到新的当前预设。
  Future<void> _openPresetManager() async {
    await _persistAll();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PresetManager(),
    );
    if (!mounted) return;
    _setState(() => _prompt.text = st.settings.activePreset.content);
  }

  void _preview(bool dark) {
    _persistAll();
    final body = st.previewBody('你好，请介绍你自己');
    final text = const JsonEncoder.withIndent('  ').convert(body);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('发送前预览 · 最终请求体'),
            style: ts(dark, size: 15, weight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.5,
                color: dark ? C.dInk2 : C.ink2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              _toast('请求体已复制');
            },
            child: Text(t('复制')),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('关闭'))),
        ],
      ),
    );
  }

  Future<void> _destroy(bool dark) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('销毁本地凭据')),
        content: Text(t('所有连接配置的密钥将被清除，且无法恢复。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('销毁'))),
        ],
      ),
    );
    if (ok != true) return;
    await st.destroyCredentials();
    _key.clear();
    if (mounted) {
      _setState(() {});
      _toast('本地凭据已销毁');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }
}

/// 新建配置时的预设选择：纯文本列表，不套卡片。
class _PresetDialog extends StatelessWidget {
  const _PresetDialog();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(t('新建连接配置'), style: ts(dark, size: 15, weight: FontWeight.w600)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: kProfilePresets.map((p) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.name, style: ts(dark, size: 13)),
                subtitle: p.baseUrl.isEmpty
                    ? null
                    : Text(p.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11.5)),
                onTap: () => Navigator.pop(context, p),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t('取消'))),
      ],
    );
  }
}

/// 分类子页的路由宿主。
///
/// 没有把子页整块下沉成独立的 StatefulWidget：四十多个设置条目全都依赖
/// [_SettingsScreenState] 里的输入框、防抖计时器和凭据状态，整体搬迁是
/// 一次大重构。这里把「本页局部状态 + AppState」两条变更线合并成一个
/// Listenable，子页只负责跟着重建——既保住了独立路由（逐层返回、原生
/// 转场），又不用改任何一条业务逻辑。
class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.owner, required this.catId});

  final _SettingsScreenState owner;
  final String catId;

  @override
  Widget build(BuildContext context) =>
      owner._detailScaffold(context, catId);
}
