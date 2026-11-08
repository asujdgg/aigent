import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// 语言选择用的最小数据单元：两套语言表（对话 / 识别）都能映射到它。
class LangItem {
  final String code;
  final String label;
  final String native;
  const LangItem(this.code, this.label, this.native);
}

/// 通用语言选择弹层：标题 + 搜索 + 单行列表。
///
/// 主语言量级在 60–70 条，必须能搜；列表只显示「中文名 + 本地写法」，
/// 不显示晦涩的 BCP-47 代码，选中的一行右侧打勾。
Future<String?> showLangPicker(
  BuildContext context, {
  required bool dark,
  required String title,
  required List<LangItem> items,
  required String selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surfaceOf(dark),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
    ),
    builder: (_) => _LangSheet(
      dark: dark,
      title: title,
      items: items,
      selected: selected,
    ),
  );
}

class _LangSheet extends StatefulWidget {
  final bool dark;
  final String title;
  final List<LangItem> items;
  final String selected;

  const _LangSheet({
    required this.dark,
    required this.title,
    required this.items,
    required this.selected,
  });

  @override
  State<_LangSheet> createState() => _LangSheetState();
}

class _LangSheetState extends State<_LangSheet> {
  final TextEditingController _q = TextEditingController();

  bool get dark => widget.dark;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<LangItem> get _filtered {
    final k = _q.text.trim().toLowerCase();
    if (k.isEmpty) return widget.items;
    return widget.items
        .where((e) =>
            e.label.toLowerCase().contains(k) ||
            e.native.toLowerCase().contains(k) ||
            e.code.toLowerCase().contains(k))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 9, bottom: 6),
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
                padding: const EdgeInsets.fromLTRB(D.pagePad + 2, 4, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style:
                              ts(dark, size: 18, weight: FontWeight.w700)),
                    ),
                    InkResponse(
                      onTap: () => Navigator.of(context).pop(),
                      radius: 20,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.close_rounded,
                            size: 20, color: dark ? C.dInk2 : C.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(D.pagePad, 0, D.pagePad, 6),
                child: TextField(
                  controller: _q,
                  style: TextStyle(
                      fontSize: 14.5, height: 1.4, color: dark ? C.dInk : C.ink),
                  decoration: InputDecoration(
                    hintText: t('搜索语言，如 英语 / English / 冰岛'),
                    hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: dark ? C.dInk3 : C.ink3,
                        fontWeight: FontWeight.w400),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: dark ? C.dInk3 : C.ink3),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 38, minHeight: 20),
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
              ),
              Expanded(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(D.pagePad, 16, D.pagePad, 0),
                        child: Text(t('没有匹配的语言'), style: sub(dark, size: 13)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final e = list[i];
                          final on = e.code == widget.selected;
                          return InkWell(
                            onTap: () => Navigator.of(context).pop(e.code),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(e.label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.25,
                                          fontWeight: on
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: dark ? C.dInk : C.ink,
                                        )),
                                  ),
                                  if (e.native.isNotEmpty &&
                                      e.native != e.label)
                                    Text(e.native,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: dark ? C.dInk3 : C.ink3)),
                                  if (on) ...[
                                    const SizedBox(width: 10),
                                    Icon(Icons.check_rounded,
                                        size: 20, color: accentOf(dark)),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
