import 'package:flutter/material.dart';

import '../services/model_brand.dart';
import '../services/model_catalog.dart';
import '../i18n.dart';
import '../theme.dart';
import 'brand_icon.dart';

/// 设置页里的跨连接模型搜索。
///
/// v4.12 与输入台弹层共用 [BrandModelTile]：一行 = 官方彩色图标 +
/// 大字模型名 + 小字供应商（跨连接时再带上连接名）。
/// 去掉了原来的系列 chips、分组头、能力标签和几段说明，
/// 搜索结果就是一张干净的列表。
class ModelSearchBox extends StatefulWidget {
  final bool dark;
  final ModelCatalog catalog;
  final String currentModel;
  final bool showAll;
  final ValueChanged<ModelEntry> onPick;
  final ValueChanged<String> onManualUse;

  const ModelSearchBox({
    super.key,
    required this.dark,
    required this.catalog,
    required this.currentModel,
    required this.showAll,
    required this.onPick,
    required this.onManualUse,
  });

  @override
  State<ModelSearchBox> createState() => _ModelSearchBoxState();
}

class _ModelSearchBoxState extends State<ModelSearchBox> {
  final TextEditingController _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final q = _q.text.trim();
    final groups = q.isEmpty
        ? const <ModelGroup>[]
        : widget.catalog.search(q, showAll: widget.showAll);
    final hits = <ModelEntry>[for (final g in groups) ...g.entries];
    final multi = widget.catalog.sourceCount > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          style: ts(dark, size: 13),
          decoration: fieldDecoration(
            dark,
            hint: t('搜模型名 / 厂商，如 gpt-4o / claude / 通义'),
            prefix: Icon(Icons.search_rounded,
                size: 17, color: dark ? C.dInk2 : C.ink2),
            suffix: q.isEmpty
                ? null
                : GestureDetector(
                    onTap: () {
                      _q.clear();
                      setState(() {});
                    },
                    child: Icon(Icons.close_rounded,
                        size: 16, color: dark ? C.dInk2 : C.ink2),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (q.isEmpty)
          Text(t('输入关键词，可在这个连接和所有其他连接里查找。'),
              style: meta(dark, size: 11.5))
        else if (hits.isEmpty)
          _none(dark, q)
        else
          _results(dark, hits, multi),
      ],
    );
  }

  Widget _none(bool dark, String q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('没有命中「$q」', style: ts(dark, size: 13)),
        const SizedBox(height: 5),
        Text(t('可换个简写（4o / ds / 通义），或直接用这个 ID。'),
            style: meta(dark, size: 11.5)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => widget.onManualUse(q),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: accentOf(dark).withOpacity(0.08),
              borderRadius: BorderRadius.circular(D.r),
              border: Border.all(color: accentOf(dark).withOpacity(0.45)),
            ),
            child: Text('按「$q」手动使用',
                style: ts(dark,
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: accentOf(dark))),
          ),
        ),
      ],
    );
  }

  Widget _results(bool dark, List<ModelEntry> hits, bool multi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('命中 ${hits.length} 个模型',
            style: meta(dark, size: 11.5, color: accentOf(dark))),
        const SizedBox(height: 6),
        Container(
          decoration: insetBox(dark),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: hits.length,
              itemBuilder: (_, i) {
                final e = hits[i];
                final brand = resolveModelBrand(e.id);
                return BrandModelTile(
                  modelId: e.id,
                  subtitle: multi
                      ? '${brand.label} · ${e.profileName}'
                      : brand.label,
                  selected: e.active && e.id == widget.currentModel,
                  dark: dark,
                  onTap: () => widget.onPick(e),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
