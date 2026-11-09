import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/agent_tools.dart';
import '../services/file_extract.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'agent_panel.dart';
import 'model_picker_sheet.dart';
import 'muse.dart';
import 'persona.dart';
import 'research_sheet.dart';
import 'roundtable_screen.dart';
import 'life_screen.dart';
import 'settings_screen.dart';
import 'source_browser.dart';
import 'tool_drawer.dart';
import 'widgets.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  /// 顶栏收缩进度 0（大头像）→ 1（一行小头像）。
  /// 用 ValueNotifier 把重建范围限制在顶栏，滚动时不会重排整个消息列表。
  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);
  Timer? _follow;
  bool _drawerOpen = false;
  String? _lastConvId;

  /// 生成刚开始时强制滚到最新一次回答：Muse 顶栏占了近 190px，
  /// 不主动跟一次的话用户发完消息很可能还停在会话顶部。
  bool _forceFollow = false;
  bool _wasGenerating = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 周期与动画时长一致，形成连续线性跟随，避免逐字跳动的阶梯感。
    _follow = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      if (context.read<AppState>().generating) _followOutput();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final t = (_scroll.offset / 120).clamp(0.0, 1.0);
    if ((_collapse.value - t).abs() > 0.004) _collapse.value = t;
  }

  @override
  void dispose() {
    _follow?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _followOutput() {
    if (!_scroll.hasClients) return;
    final force = _forceFollow;
    _forceFollow = false;
    if (!force && _scroll.position.extentAfter > 240) return;
    final target = _scroll.position.maxScrollExtent;
    if (target - _scroll.offset < 1) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 90),
      curve: Curves.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final conv = st.active;
    final configured = _configured(st);

    // 切换会话时把列表拉回顶部，避免新会话停在旧会话的滚动偏移上。
    if (_lastConvId != conv.id) {
      _lastConvId = conv.id;
      _collapse.value = 0;
      _wasGenerating = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }

    // 本会话刚开始生成：下一帧强制跟随一次到最新回答。
    if (st.generating && !_wasGenerating) {
      _forceFollow = true;
      _wasGenerating = true;
    } else if (!st.generating) {
      _wasGenerating = false;
    }

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: MuseC.canvas(dark),
      onDrawerChanged: (open) => setState(() => _drawerOpen = open),
      onEndDrawerChanged: (open) => setState(() => _drawerOpen = open),
      drawer: WorkspaceDrawer(
        onResearch: _openResearchFromDrawer,
        onToolbox: _openToolbox,
      ),
      endDrawer: const ToolDrawer(),
      body: AnimatedContainer(
        duration: D.anim,
        curve: D.curve,
        transform: Matrix4.identity()..scale(_drawerOpen ? 0.972 : 1.0),
        transformAlignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MuseC.canvas(dark),
          borderRadius: _drawerOpen
              ? BorderRadius.all(Radius.circular(D.floatR))
              : BorderRadius.zero,
        ),
        child: SafeArea(
          // v4.13：底部导航整条移除，输入台直接坐到屏幕底部；
          // 安全区改由这里承担，手势导航条不会压住输入框。
          bottom: true,
          // 平板 / 折叠屏展开后，正文限宽居中：一行铺满 900dp 会很难读，
          // 输入台也会宽得像搜索栏。手机竖屏下这个约束不生效。
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _list(st, dark, conv)),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: MuseTopBar(
                        collapse: _collapse,
                        dark: dark,
                        persona: _persona(st),
                        statusLine: configured
                            ? '${st.settings.activeProfile.name} · ${st.settings.model}'
                            : '点此配置接口',
                        connected: configured,
                        showPill: st.settings.personaEnabled,
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        onAvatar: _openPersonaPicker,
                        onStatus: () => _showModels(st, dark),
                      ),
                    ),
                    // 列表底部淡出到画布色，内容不会硬生生被输入栏切断。
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                MuseC.canvas(dark).withOpacity(0),
                                MuseC.canvas(dark),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 智能体授权：贴在输入栏上方的非模态横条，不遮挡阅读，
                    // 也不会像对话框那样打断正在进行的回答。
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 研究工作流：四个阶段摊开显示，长任务不再只有一句
                          // 滚动的状态文字。
                          Selector<AppState, ({ResearchStage stage, int step, int total})>(
                            selector: (_, s) => (
                              stage: s.researchStage,
                              step: s.researchStep,
                              total: s.researchTotal,
                            ),
                            builder: (_, r, __) => r.stage ==
                                        ResearchStage.idle ||
                                    r.stage == ResearchStage.done ||
                                    r.stage == ResearchStage.failed
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ResearchProgressBar(
                                      dark: dark,
                                      stage: r.stage,
                                      step: r.step,
                                      total: r.total,
                                      onStop: () =>
                                          context.read<AppState>().stop(),
                                    ),
                                  ),
                          ),
                          Selector<AppState, AgentAction?>(
                            selector: (_, s) => s.pendingAgentAction,
                            builder: (_, action, __) => action == null
                                ? const SizedBox.shrink()
                                : AgentApprovalBar(action: action, dark: dark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ComposerBar(
                // 会话 id 变化会触发 didUpdateWidget，自动换成该会话的草稿。
                key: ValueKey('composer_${conv.id}'),
                dark: dark,
                muse: true,
                convId: conv.id,
                draftSeed: st.draftSeed,
                onGallery: () => _pickImage(ImageSource.gallery),
                onCamera: () => _pickImage(ImageSource.camera),
                onFiles: _pickFiles,
                onOpenSettings: _openSettings,
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 是否已有可用连接：填了密钥，或接口地址不是官方占位地址（免密 / 本地源）。
  bool _configured(AppState st) =>
      st.settings.apiKey.trim().isNotEmpty ||
      !st.settings.baseUrl.startsWith('https://api.openai.com');

  /// v4.13：底部导航移除后，「研究 / 工具」并入左侧抽屉。
  /// 抽屉关闭动画与本页弹层不能抢同一帧，所以统一放到下一帧再开。
  void _openToolbox() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openResearchFromDrawer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openResearch();
    });
  }

  void _openResearch() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceOf(dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
      ),
      builder: (_) => const ResearchLauncher(),
    );
  }

  /// 顶栏状态条点开：与输入台共用同一个极简弹层，两处样式不再分叉。
  /// 检测 / 刷新 / 接口设置这些管理动作都在设置页，这里只负责换模型。
  void _showModels(AppState st, bool dark) {
    unawaited(showModelPickerSheet(
      context,
      dark: dark,
      st: st,
      onOpenSettings: _openSettings,
    ));
  }

  /// 当前会话生效的形象（可能被会话单独覆盖）。
  Persona _persona(AppState st) => st.settings.personaFor(st.active.personaId);

  void _openPersonaPicker() {
    // 一个形象都没建设时，与其弹出一个只有「还没有形象」的空面板，
    // 不如直接带用户去新建——「没有设置就什么都没有」。
    if (context.read<AppState>().settings.personas.isEmpty) {
      Navigator.of(context).push(
        SoftPageRoute(
            builder: (_) => const SettingsScreen(initialCat: 'persona')),
      );
      return;
    }
    showPersonaPicker(
      context,
      dark: Theme.of(context).brightness == Brightness.dark,
      onOpenSettings: () => Navigator.of(context).push(
        SoftPageRoute(
            builder: (_) => const SettingsScreen(initialCat: 'persona')),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      SoftPageRoute(
        // 设置页返回时要立刻露出聊天页，同样不能让下层被摘掉。
        keepBelow: true,
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  Widget _list(AppState st, bool dark, Conversation conv) {
    return Scrollbar(
      controller: _scroll,
      radius: const Radius.circular(4),
      thickness: 3,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          // 给悬浮顶栏留出展开高度；滚动后内容从渐变遮罩下自然淡出。
          const SliverToBoxAdapter(child: SizedBox(height: 190)),
          if (conv.messages.isEmpty)
            SliverToBoxAdapter(child: _empty(st, dark))
          else ...[
            SliverToBoxAdapter(
              child: MuseDateChip(at: conv.messages.first.at, dark: dark),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              // SliverList 按需构建，长会话不会一次性布局全部消息。
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AppearIn(
                    key: ValueKey('m_${conv.messages[i].id}'),
                    id: conv.messages[i].id,
                    child: MessageCard(
                      message: conv.messages[i],
                      dark: dark,
                      muse: true,
                      raw: st.settings.rawOutput,
                      onRegenerate: () => st.regenerate(),
                    ),
                  ),
                  childCount: conv.messages.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 空态引导：不往会话里写假消息，因此不会污染历史、朗读与 Token 统计。
  Widget _empty(AppState st, bool dark) {
    return MuseOnboarding(
      persona: _persona(st),
      dark: dark,
      modelLine: _configured(st)
          ? '${st.settings.activeProfile.name} · ${st.settings.model}'
          : '尚未配置接口',
      onConfigure: _openSettings,
      onPersona: _openPersonaPicker,
      onVoice: () => Navigator.of(context).push(
        SoftPageRoute(
          builder: (_) => const SettingsScreen(initialCat: 'voice'),
        ),
      ),
      onTools: () => _scaffoldKey.currentState?.openEndDrawer(),
      onStarter: (s) => st.send(s),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final st = context.read<AppState>();
    try {
      if (source == ImageSource.gallery) {
        final files =
            await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1280);
        final list = <Attachment>[];
        for (final f in files) {
          list.add(await FileExtractService.fromXFile(f));
        }
        if (list.isNotEmpty) st.addAttachments(list);
      } else {
        final f = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 72, maxWidth: 1280);
        if (f != null) st.addAttachment(await FileExtractService.fromXFile(f));
      }
    } catch (e) {
      _toast('图片读取失败：$e');
    }
  }

  Future<void> _pickFiles() async {
    final st = context.read<AppState>();
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'txt',
          'csv',
          'tsv',
          'md',
          'markdown',
          'json',
          'jsonl',
          'log',
          'yaml',
          'yml',
          'xml',
          'html',
          'htm',
          'toml',
          'ini',
          'sql',
          'py',
          'js',
          'ts',
          'dart',
          'java',
          'kt',
          'go',
          'rs',
          'c',
          'h',
          'cpp',
          'sh',
          'css',
          'scss',
          'tex',
          'srt',
          'vtt',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'bmp',
        ],
      );
      if (res == null) return;
      final list = <Attachment>[];
      for (final f in res.files) {
        list.add(await FileExtractService.fromPlatformFile(f));
      }
      if (list.isNotEmpty) st.addAttachments(list);
    } catch (e) {
      _toast('文件读取失败：$e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class WorkspaceDrawer extends StatelessWidget {
  /// 底部导航去掉后，这两个入口挪进抽屉，功能一个不少。
  final VoidCallback? onResearch;
  final VoidCallback? onToolbox;

  const WorkspaceDrawer({super.key, this.onResearch, this.onToolbox});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 窄屏（320dp 的老机器 / 小折叠屏外屏）别让抽屉铺满整屏，
    // 留一条右边距才能看出「这是抽屉，右滑可关」。
    final w = (MediaQuery.sizeOf(context).width * 0.88).clamp(240.0, 300.0);
    return Drawer(
      width: w,
      backgroundColor: surfaceOf(dark),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(D.pagePad, 26, D.pagePad, 20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      kAppIconAsset,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        color: C.brand,
                        child: const Icon(Icons.blur_circular_rounded,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题列自己吃掉剩余宽度：字号调大或窄屏（320dp 老机器、
                  // 小折叠屏外屏）时，版本行宁可省略也不能把抽屉顶出血。
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aigent',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: display(dark, size: 17)),
                        const SizedBox(height: 2),
                        Text('V$kAppVersion · BUILD $kAppBuild',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sectionTitle(dark)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: hairOf(dark)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
              child: _drawerAction(dark, Icons.add_rounded, '新建工作台', () {
                st.newConversation();
                Navigator.pop(context);
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(D.pagePad, 18, D.pagePad, 8),
              child: Label(t('会话 · ${st.conversations.length}')),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: st.conversations.length,
                itemBuilder: (context, i) {
                  final c = st.conversations[i];
                  final active = c.id == st.activeId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? (dark ? C.dSink : C.brandSoft)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(D.r),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(dark,
                            size: 13,
                            weight: active ? FontWeight.w600 : FontWeight.w400),
                      ),
                      subtitle: Text('${c.count} 条 · ${hhmm(c.at)}',
                          style: sub(dark, size: 12.5)),
                      onTap: () {
                        st.switchConversation(c.id);
                        Navigator.pop(context);
                      },
                      onLongPress: () => _confirmDelete(context, st, c.id),
                    ),
                  );
                },
              ),
            ),
            Container(height: 1, color: hairOf(dark)),
            const SizedBox(height: 6),
            // 功能入口增加到 7 条后，矮屏（320×568 一类）会被挤爆：
            // 这一组改为「最多占剩余空间、超出自己滚」，会话列表仍优先填充。
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  _drawerAction(dark, Icons.widgets_rounded, '工具', () {
                    Navigator.pop(context);
                    onToolbox?.call();
                  }),
                  _drawerAction(
                      dark, Icons.travel_explore_rounded, '深度研究', () {
                    Navigator.pop(context);
                    onResearch?.call();
                  }),
                  _drawerAction(dark, Icons.forum_rounded, 'AI 圆桌会议', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(SoftPageRoute(
                      keepBelow: true,
                      builder: (_) => const RoundtableScreen(),
                    ));
                  }),
                  _drawerAction(
                      dark, Icons.auto_stories_rounded, '模拟人生', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(SoftPageRoute(
                      keepBelow: true,
                      builder: (_) => const LifeScreen(),
                    ));
                  }),
                  // 功能 / 配置 两组之间留一点空隙，不画线、不加小标题：
                  // 五条同款入口堆在一起，只靠图标区分太难扫。
                  const SizedBox(height: 6),
                  _drawerAction(dark, Icons.settings_rounded, '设置', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      SoftPageRoute(
        // 设置页返回时要立刻露出聊天页，同样不能让下层被摘掉。
        keepBelow: true,
        builder: (_) => const SettingsScreen(),
      ),
                    );
                  }),
                  _drawerAction(
                      dark, Icons.smartphone_rounded, '设备智能体', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(SoftPageRoute(
                        builder: (_) =>
                            const SettingsScreen(initialCat: 'agent')));
                  }),
                  _drawerAction(dark, Icons.info_rounded, '关于',
                      () => _about(context, dark),
                      // 版本号放这里，顶部就不必再挤一行 BUILD 号。
                      trailing: 'v$kAppVersion'),
                ],
              ),
              ),
            ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 抽屉底部的一条动作。
  ///
  /// 统一成 46 高、19 号圆角线性图标、14 号文字：之前行高压到 39、
  /// 图标混用「描边 / 圆角」两套风格，五条叠在一起又挤又乱，
  /// 手指也容易点到隔壁。
  Widget _drawerAction(
      bool dark, IconData icon, String text, VoidCallback onTap,
      {String? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(D.r),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 19, color: dark ? C.dInk2 : C.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(dark, size: 13.5)),
              ),
              if (trailing != null)
                Text(trailing,
                    style: meta(dark, size: 11.5, color: dark ? C.dInk3 : C.ink3)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState st, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('删除工作台')),
        content: Text(t('该会话的所有消息将被移除，且无法恢复。')),
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
    if (ok == true) st.deleteConversation(id);
  }

  void _about(BuildContext context, bool dark) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aigent'),
        content: Text(
          'Aigent v$kAppVersion · 手机智能体客户端。\n\n'
          '除了对话，它还能读取本机型号与配置，并在你授权后操作设备：'
          '在独立工作区里读写文件、运行受限任务脚本、打开应用与网页、'
          '新建日历日程、设置闹钟。所有文件操作都被隔离在应用专属目录，'
          '覆盖自动备份、删除进入回收站。\n\n'
          'API 请求由本设备直接发往你配置的接口，凭据经 AES 加密后仅存本地。',
          style: ts(dark, size: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(SoftPageRoute<void>(
                  builder: (_) => const SourceBrowser()));
            },
            child: Text(t('查看源代码')),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('知道了'))),
        ],
      ),
    );
  }
}
