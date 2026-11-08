import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'widgets.dart';

class PluginSheet extends StatefulWidget {
  const PluginSheet({super.key});

  @override
  State<PluginSheet> createState() => _PluginSheetState();
}

class _PluginSheetState extends State<PluginSheet> {
  late final TextEditingController _url;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(
        text: context.read<AppState>().settings.openApiUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load(AppState st) async {
    final u = _url.text.trim();
    if (u.isEmpty) return;
    setState(() => _busy = true);
    await st.loadPlugin(u);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = st.plugin;
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(D.floatR)),
        boxShadow: softShadow(dark, scale: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(D.pagePad, 12, D.pagePad, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: borderOf(dark),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(t('HTTP 插件'), style: display(dark, size: 18)),
            const SizedBox(height: 6),
            Text(t('Swagger / OpenAPI JSON 地址'), style: meta(dark, size: 11.5)),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              maxLines: 1,
              style: ts(dark, size: 13, height: 1.4),
              decoration: fieldDecoration(dark,
                  hint: 'https://petstore3.swagger.io/api/v3/openapi.json'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _action(dark, _busy ? '解析中…' : '解析并启用',
                      _busy ? null : () => _load(st),
                      primary: true),
                ),
                const SizedBox(width: 8),
                _action(dark, '移除', p == null ? null : () => st.removePlugin()),
              ],
            ),
            if (st.pluginError != null) ...[
              const SizedBox(height: 10),
              Text(st.pluginError!,
                  style: ts(dark, size: 13, color: C.danger)),
            ],
            if (p != null) ...[
              const SizedBox(height: 14),
              SwitchRow(
                title: t('允许模型调用该插件'),
                subtitle: t('关闭后保留文档但不注入工具清单'),
                value: st.settings.pluginEnabled,
                onChanged: (v) => st.patch((x) => x.pluginEnabled = v),
              ),
              Text('Base URL: ${p.baseUrl}', style: sub(dark, size: 12.5)),
              const SizedBox(height: 12),
              Label(t('端点 · ${p.operations.length}')),
              SizedBox(
                height: 220,
                child: Container(
                  decoration: insetBox(dark),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: p.operations.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: dark ? C.dLine : C.line),
                    itemBuilder: (_, i) {
                      final o = p.operations[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 7, horizontal: 4),
                        child: Row(
                          children: [
                            MetaChip(o.method.toUpperCase()),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ts(dark, size: 13)),
                                  if (o.summary.isNotEmpty)
                                    Text(o.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: sub(dark, size: 12.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(bool dark, String text, VoidCallback? onTap,
      {bool primary = false}) {
    final enabled = onTap != null;
    final color = primary ? C.brand : surfaceOf(dark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: primary
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: enabled ? color : color.withOpacity(0.5),
          borderRadius: BorderRadius.circular(D.r),
          border: primary ? null : Border.all(color: borderOf(dark)),
          boxShadow: primary ? softShadow(dark, scale: 0.45) : null,
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: primary ? Colors.white : (dark ? C.dInk2 : C.ink2),
            ),
          ),
        ),
      ),
    );
  }
}
