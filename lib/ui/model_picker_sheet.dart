import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/model_catalog.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'brand_icon.dart';

/// 输入台 / 顶栏共用的「换模型」弹层（v4.13）。
///
/// 刻意做减法：标题一行、下面是**单行列表**——官方彩色图标 + 模型名 + 选中
/// 对勾，没有分隔线、没有选中底色、没有系列分组、没有底部操作栏。
/// 「检测模型 / 刷新列表 / 接口设置」这些管理动作全部留在设置页，
/// 主页只负责「看一眼、点一下、换掉」。
Future<void> showModelPickerSheet(
  BuildContext context, {
  required bool dark,
  required AppState st,
  VoidCallback? onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surfaceOf(dark),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
    ),
    builder: (_) => ModelPickerSheet(
      dark: dark,
      st: st,
      onOpenSettings: onOpenSettings,
    ),
  );
}

class ModelPickerSheet extends StatefulWidget {
  final bool dark;
  final AppState st;
  final VoidCallback? onOpenSettings;

  const ModelPickerSheet({
    super.key,
    required this.dark,
    required this.st,
    this.onOpenSettings,
  });

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _qFocus = FocusNode();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _q.addListener(_onQuery);
  }

  void _onQuery() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _q.removeListener(_onQuery);
    _qFocus.dispose();
    _q.dispose();
    super.dispose();
  }

  AppState get st => widget.st;
  bool get dark => widget.dark;

  Future<void> _pickCurrent(String id) async {
    await st.selectModel(id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickCatalog(ModelEntry e) async {
    await st.selectCatalogModel(e);
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _qFocus.requestFocus();
      });
    } else {
      _q.clear();
      _qFocus.unfocus();
    }
  }

  /// 连接切换：只在有多个配置档时出现，收成标题下方一行文字。
  ///
  /// v4.16 修了两个问题：
  /// 1. 旧版 Column 直接铺 ListTile，配置一多就超出屏幕且**无法滚动**，
  ///    用户只能看到最上面几条；
  /// 2. 配置多到十几条时纯列表也难找，所以补了一个过滤框。
  Future<void> _pickProfile() async {
    final profiles = st.settings.profiles;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceOf(dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
      ),
      builder: (_) => _ProfileSheet(
        dark: dark,
        profiles: profiles,
        activeId: st.settings.activeProfileId,
      ),
    );
    if (id == null || !mounted) return;
    if (id == st.settings.activeProfileId) return;
    await st.switchProfile(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final catalog = st.modelCatalog;
    final hits = q.isEmpty
        ? const <ModelEntry>[]
        : [
            for (final g in catalog.search(q, showAll: st.settings.showAllModels))
              ...g.entries,
          ];
    final current = st.settings.model.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grip(),
              _header(q),
              if (st.settings.profiles.length > 1) _profileLine(),
              if (_searching) _searchField(q),
              Expanded(
                child: q.isEmpty
                    ? _currentList(current)
                    : _searchList(hits, q, current),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grip() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 9, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withOpacity(0.16)
                : Colors.black.withOpacity(0.10),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );

  Widget _header(String q) => Padding(
        padding: const EdgeInsets.fromLTRB(D.pagePad + 2, 8, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(t('选择模型'),
                  style: ts(dark, size: 18, weight: FontWeight.w700)),
            ),
            _iconBtn(
              // 搜索态用「收起」而不是第二个 ×，免得和右边的关闭按钮撞脸。
              _searching
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.search_rounded,
              _toggleSearch,
              tooltip: _searching ? t('收起搜索') : '搜索模型',
            ),
            const SizedBox(width: 2),
            _iconBtn(Icons.close_rounded, () => Navigator.of(context).pop(),
                tooltip: t('关闭')),
          ],
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon,
              size: 20, color: dark ? C.dInk2 : C.ink2),
        ),
      ),
    );
  }

  Widget _profileLine() {
    final name = st.settings.activeProfile.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(D.pagePad + 2, 0, D.pagePad, 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickProfile,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前连接 · $name',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: dark ? C.dInk2 : C.ink2)),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded,
                size: 15, color: dark ? C.dInk2 : C.ink2),
          ],
        ),
      ),
    );
  }

  Widget _searchField(String q) => Padding(
        padding: const EdgeInsets.fromLTRB(D.pagePad, 6, D.pagePad, 4),
        child: TextField(
          controller: _q,
          focusNode: _qFocus,
          style: TextStyle(fontSize: 14.5, height: 1.4, color: dark ? C.dInk : C.ink),
          decoration: InputDecoration(
            hintText: t('gpt-4o / claude / 通义 / 视觉'),
            hintStyle: TextStyle(
                fontSize: 13.5,
                color: dark ? C.dInk3 : C.ink3,
                fontWeight: FontWeight.w400),
            prefixIcon: Icon(Icons.search_rounded,
                size: 18, color: dark ? C.dInk3 : C.ink3),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 38, minHeight: 20),
            suffixIcon: q.isEmpty
                ? null
                : GestureDetector(
                    onTap: () => _q.clear(),
                    child: Icon(Icons.cancel_rounded,
                        size: 17, color: dark ? C.dInk3 : C.ink3),
                  ),
            isDense: true,
            filled: true,
            fillColor: fieldOf(dark),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.r + 2),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _currentList(String current) {
    final all = st.models;
    final list = st.settings.showAllModels ? all : st.chatModels;
    if (list.isEmpty) return _emptyModels();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(D.pagePad - 8, 2, D.pagePad - 8, 16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final m = list[i];
        return BrandModelTile(
          compact: true,
          modelId: m.id,
          subtitle: '',
          selected: m.id == current,
          dark: dark,
          onTap: () => _pickCurrent(m.id),
        );
      },
    );
  }

  Widget _emptyModels() => Padding(
        padding: const EdgeInsets.fromLTRB(D.pagePad, 18, D.pagePad, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('这个连接还没有读到模型列表。'), style: sub(dark, size: 13)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenSettings?.call();
              },
              child: Text(t('去设置里刷新'),
                  style: ts(dark,
                      size: 13,
                      weight: FontWeight.w600,
                      color: accentOf(dark))),
            ),
          ],
        ),
      );

  Widget _searchList(List<ModelEntry> hits, String q, String current) {
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(D.pagePad, 16, D.pagePad, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('没有命中「$q」', style: ts(dark, size: 14)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _pickCurrent(q),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: accentOf(dark).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(D.r),
                ),
                child: Text('按「$q」使用',
                    style: ts(dark,
                        size: 13,
                        weight: FontWeight.w600,
                        color: accentOf(dark))),
              ),
            ),
          ],
        ),
      );
    }
    final multi = st.settings.profiles.length > 1;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(D.pagePad - 8, 2, D.pagePad - 8, 16),
      itemCount: hits.length,
      itemBuilder: (_, i) {
        final e = hits[i];
        return BrandModelTile(
          compact: true,
          modelId: e.id,
          // 跨连接命中时补一句来源，避免同名模型选错连接。
          subtitle: multi ? e.profileName : '',
          selected: e.active && e.id == current,
          dark: dark,
          onTap: () => _pickCatalog(e),
        );
      },
    );
  }
}

/// 连接配置选择弹层。
///
/// 独立成一个 StatefulWidget 只为一件事：**列表必须能滚**。
/// 旧版把配置直接铺进 `Column(mainAxisSize: min)`，条目一多就被屏幕裁掉，
/// 手指在列表上滑也没反应——配置有十几条的用户只能看到前几条。
class _ProfileSheet extends StatefulWidget {
  final bool dark;
  final List<ApiProfile> profiles;
  final String activeId;

  const _ProfileSheet({
    required this.dark,
    required this.profiles,
    required this.activeId,
  });

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final TextEditingController _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool get dark => widget.dark;

  /// 配置超过 8 条才出现过滤框：两三条时再给一个搜索框是噪音。
  bool get _needFilter => widget.profiles.length > 8;

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.profiles
        : [
            for (final p in widget.profiles)
              if (p.name.toLowerCase().contains(q) ||
                  p.baseUrl.toLowerCase().contains(q) ||
                  p.model.toLowerCase().contains(q))
                p,
          ];
    // 高度三档：少量配置贴着内容，多了就撑到屏幕 72%，中间永远可滚。
    final screenH = MediaQuery.sizeOf(context).height;
    final want = 96.0 + list.length * 52.0 + (_needFilter ? 46 : 0);
    final h = want.clamp(180.0, screenH * 0.72);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 9, bottom: 2),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withOpacity(0.16)
                        : Colors.black.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(D.pagePad, 8, D.pagePad, 2),
                child: Row(
                  children: [
                    Text(t('连接配置'),
                        style: ts(dark, size: 16, weight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text('${widget.profiles.length}',
                        style: meta(dark, size: 12)),
                    const Spacer(),
                    Text(t('点一下切换'),
                        style: meta(dark, size: 11.5)),
                  ],
                ),
              ),
              if (_needFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(D.pagePad, 8, D.pagePad, 2),
                  child: TextField(
                    controller: _q,
                    style: ts(dark, size: 13.5),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: fieldOf(dark),
                      hintText: t('搜索连接名或地址'),
                      hintStyle: meta(dark, size: 13),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 17, color: dark ? C.dInk3 : C.ink3),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 34, minHeight: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(D.r),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(t('没有匹配的连接'),
                            style: meta(dark, size: 13)),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                          // 保证最后一条能滑到标题下方，不被安全区吃掉。
                          itemCount: list.length + 1,
                          itemBuilder: (_, i) {
                            if (i == list.length) {
                              return const SizedBox(height: 8);
                            }
                            final p = list[i];
                            final on = p.id == widget.activeId;
                            return InkWell(
                              onTap: () => Navigator.pop(context, p.id),
                              borderRadius: BorderRadius.circular(D.r),
                              child: Container(
                                height: 52,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                child: Row(
                                  children: [
                                    Icon(
                                      on
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      size: 17,
                                      color: on
                                          ? accentOf(dark)
                                          : (dark ? C.dInk3 : C.ink3),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: ts(dark,
                                                size: 14,
                                                weight: on
                                                    ? FontWeight.w600
                                                    : FontWeight.w400),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _sub(p),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: meta(dark, size: 11.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 副标题只说「跟别的不一样的地方」：模型名 + 主机名，比整条 URL 好认。
  String _sub(ApiProfile p) {
    final host = Uri.tryParse(p.baseUrl)?.host ?? p.baseUrl;
    final h = host.isEmpty ? p.baseUrl : host;
    final m = p.model.trim().isEmpty ? t('未设模型') : p.model.trim();
    return '$m · $h';
  }
}
