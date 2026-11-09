import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../services/model_source.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'brand_icon.dart';
import 'feature_kit.dart';

/// 两级模型选择器：先选连接（运营商 / 提供商），进入后再选具体模型。
///
/// 圆桌会议席位、模拟人生、AI 小游戏共用。两级都是独立路由，逐层返回，
/// 用的仍是修好的纯位移转场，不会在返回时重建下层页面。
Future<ModelChoice?> showProviderModelPicker(
  BuildContext context, {
  required bool dark,
  String? currentBaseUrl,
  String? currentModel,
  String? title,
}) async {
  final st = Provider.of<AppState>(context, listen: false);
  final activeModels = st.models.map((e) => e.id).toList();
  final groups = buildProviderGroups(st.settings, activeModels: activeModels);
  return Navigator.of(context).push<ModelChoice>(
    SoftPageRoute<ModelChoice>(
      keepBelow: true,
      builder: (_) => ProviderPickerPage(
        dark: dark,
        groups: groups,
        currentBaseUrl: currentBaseUrl,
        currentModel: currentModel,
        chatChoice: currentChatChoice(st.settings),
        title: title ?? t('选择模型'),
      ),
    ),
  );
}

/// 第一级：连接（运营商）列表。
class ProviderPickerPage extends StatelessWidget {
  const ProviderPickerPage({
    super.key,
    required this.dark,
    required this.groups,
    required this.chatChoice,
    required this.title,
    this.currentBaseUrl,
    this.currentModel,
  });

  final bool dark;
  final List<ProviderGroup> groups;
  final ModelChoice chatChoice;
  final String title;
  final String? currentBaseUrl;
  final String? currentModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: featureAppBar(context, dark, title: title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
          children: [
            featureCard(dark, [
              featureLabel(dark, t('当前对话模型')),
              _chatChoiceRow(dark, context),
              featureHint(dark, t('沿用聊天界面正在使用的连接与模型。')),
            ]),
            featureHint(dark, t('先选一家运营商（连接），再进入模型列表挑选。')),
            if (groups.isEmpty)
              featureEmpty(dark, Icons.hub_outlined,
                  t('还没有连接，请先到「连接与模型」里添加。'))
            else
              for (final g in groups) _groupCard(context, dark, g),
          ],
        ),
      ),
    );
  }

  Widget _chatChoiceRow(bool dark, BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(D.r),
        onTap: () => Navigator.of(context).pop(chatChoice),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: accentOf(dark)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chatChoice.providerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(dark, size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(chatChoice.model.isEmpty
                        ? t('未设置模型')
                        : chatChoice.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 17, color: dark ? C.dInk3 : C.ink3),
            ],
          ),
        ),
      );

  Widget _groupCard(BuildContext context, bool dark, ProviderGroup g) {
    final isCurrent = currentBaseUrl != null &&
        currentBaseUrl!.trim() == g.baseUrl.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: surfaceBox(dark, shadowScale: 0.5),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 19,
          backgroundColor: g.active
              ? C.brand.withOpacity(0.13)
              : fieldOf(dark),
          child: Icon(Icons.hub_outlined,
              size: 18, color: g.active ? C.brand : (dark ? C.dInk3 : C.ink3)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(dark, size: 13.5, weight: FontWeight.w600)),
            ),
            if (g.active) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: C.brand.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(t('当前连接'),
                    style: ts(dark, size: 9.5, color: C.brand)),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('${g.host} · ${g.models.length} ${t('个模型')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: meta(dark, size: 11)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent)
              Icon(Icons.check_circle_rounded, size: 16, color: C.ok),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: dark ? C.dInk3 : C.ink3),
          ],
        ),
        onTap: () async {
          final picked = await Navigator.of(context).push<ModelChoice>(
            SoftPageRoute<ModelChoice>(
              keepBelow: true,
              builder: (_) => ProviderModelsPage(
                dark: dark,
                group: g,
                currentModel: isCurrent ? currentModel : null,
              ),
            ),
          );
          if (picked != null && context.mounted) {
            Navigator.of(context).pop(picked);
          }
        },
      ),
    );
  }
}

/// 第二级：某一家连接下的模型列表。
class ProviderModelsPage extends StatefulWidget {
  const ProviderModelsPage({
    super.key,
    required this.dark,
    required this.group,
    this.currentModel,
  });

  final bool dark;
  final ProviderGroup group;
  final String? currentModel;

  @override
  State<ProviderModelsPage> createState() => _ProviderModelsPageState();
}

class _ProviderModelsPageState extends State<ProviderModelsPage> {
  final TextEditingController _q = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    _manual.text = widget.currentModel ?? '';
    _q.addListener(_refresh);
  }

  @override
  void dispose() {
    _q.removeListener(_refresh);
    _q.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ModelChoice _choice(String model) => ModelChoice(
        baseUrl: widget.group.baseUrl,
        apiKey: widget.group.apiKey,
        model: model,
        providerName: widget.group.name,
      );

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final g = widget.group;
    final models = filterModels(g.models, _q.text);
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: featureAppBar(context, dark, title: g.name),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: TextField(
                  controller: _q,
                  style: ts(dark, size: 13),
                  decoration: fieldDecoration(
                    dark,
                    hint: t('搜索模型 ID'),
                    prefix: Icon(Icons.search_rounded,
                        size: 17, color: dark ? C.dInk3 : C.ink3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(g.host, style: meta(dark, size: 11)),
                ),
              ),
              Expanded(
                child: models.isEmpty
                    ? featureEmpty(
                        dark,
                        Icons.search_off_rounded,
                        _q.text.trim().isEmpty
                            ? t('这个连接还没有缓存模型，可在下方手动输入。')
                            : t('没有匹配的模型'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                        itemCount: models.length,
                        itemBuilder: (_, i) => BrandModelTile(
                          modelId: models[i],
                          subtitle: g.name,
                          selected: models[i] == widget.currentModel,
                          dark: dark,
                          iconSize: 32,
                          onTap: () => Navigator.of(context).pop(_choice(models[i])),
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                decoration: hairlineBox(dark, top: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('手动输入模型 ID'), style: sectionTitle(dark)),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manual,
                            style: ts(dark, size: 12.5),
                            decoration:
                                fieldDecoration(dark, hint: t('模型 ID')),
                            onSubmitted: (_) => _useManual(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: C.brand,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(D.r)),
                            elevation: 0,
                          ),
                          onPressed: _useManual,
                          child: Text(t('使用'),
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _useManual() {
    final m = _manual.text.trim();
    if (m.isEmpty) return;
    Navigator.of(context).pop(_choice(m));
  }
}
