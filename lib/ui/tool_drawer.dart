import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'persona.dart';
import 'plugin_sheet.dart';
import 'research_sheet.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class ToolDrawer extends StatelessWidget {
  const ToolDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final w = (MediaQuery.sizeOf(context).width * 0.88).clamp(240.0, 306.0);
    return Drawer(
      width: w,
      backgroundColor: canvasOf(dark),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('工具'), style: display(dark, size: 20)),
                  const SizedBox(height: 4),
                  Text(t('当前会话的能力与连接'), style: sub(dark, size: 12.5)),
                ],
              ),
            ),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Label(t('模型能力档位')),
              ),
              TierSelector(
                value: s.tier,
                onChanged: (t) => st.patch((x) => x.tier = t),
              ),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Label(t('能力开关')),
              ),
              SwitchRow(
                title: t('深度思考'),
                value: s.deepThinking,
                onChanged: (v) => st.patch((x) => x.deepThinking = v),
              ),
              SwitchRow(
                title: t('联网搜索'),
                value: s.webSearch,
                onChanged: (v) => st.setWebSearch(v),
              ),
              // 明确的联网状态：关掉时这里与状态栏都不会出现任何联网字样。
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: Text(
                  s.searchActive
                      ? '已启用 · ${s.activeSources.length} 个搜索源'
                      : (s.webSearch
                          ? '已开启，但未选择任何搜索源，不会发起检索'
                          : '未启用 · 请求不会经过任何搜索服务'),
                  style: meta(dark,
                      size: 11.5,
                      color: s.searchActive ? accentOf(dark) : null),
                ),
              ),
              SwitchRow(
                title: t('深度研究工作流'),
                value: s.researchWorkflow,
                onChanged: (v) => st.patch((x) => x.researchWorkflow = v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Text(t('多轮检索 → 拟定大纲 → 逐节展开 → 汇总报告，可随时中断。'),
                  style: meta(dark, size: 11.5),
                ),
              ),
              SwitchRow(
                title: t('原始输出'),
                value: s.rawOutput,
                onChanged: (v) => st.patch((x) => x.rawOutput = v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Text(t('回答不做 Markdown 渲染与引用角标转换，等宽原样呈现。'),
                  style: meta(dark, size: 11.5),
                ),
              ),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Label(t('人物形象')),
              ),
              _action(
                context,
                st.settings.personas.isEmpty
                    ? '选择形象 · 自定义头像与设定'
                    : '当前：${st.activePersona.name} · 点击切换 / 自定义',
                () {
                  final empty = st.settings.personas.isEmpty;
                  Navigator.pop(context);
                  if (empty) {
                    Navigator.of(context).push(
                      SoftPageRoute(
                        builder: (_) =>
                            const SettingsScreen(initialCat: 'persona'),
                      ),
                    );
                    return;
                  }
                  showPersonaPicker(
                    context,
                    dark: dark,
                    onOpenSettings: () => Navigator.of(context).push(
                      SoftPageRoute(
                        builder: (_) =>
                            const SettingsScreen(initialCat: 'persona'),
                      ),
                    ),
                  );
                },
                dark,
              ),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Label(t('研究工作台')),
              ),
              _action(
                  context,
                  '设备智能体 · ${s.agentEnabled ? "已启用" : "未启用"}',
                  () {
                    Navigator.pop(context);
                    Navigator.of(context).push(SoftPageRoute(
                        builder: (_) =>
                            const SettingsScreen(initialCat: 'agent')));
                  },
                  dark),
              _action(context, '开始深度研究',
                  () => _openSheet(context, const ResearchLauncher()), dark),
              _action(context, 'Token 用量 · 累计 ${st.tokenStats.total} tok',
                  () => _openSheet(context, const UsageSheet()), dark),
              _action(context, '实验记录 · ${st.records.length} 条',
                  () => _openSheet(context, const RecordsSheet()), dark),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Label(t('插件系统')),
              ),
              _pluginEntry(context, st, dark),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Label(t('当前会话')),
              ),
              _action(context, '清空消息', () {
                st.clearActive();
                Navigator.pop(context);
              }, dark),
              _action(context, '导出为 Markdown', () async {
                await Clipboard.setData(ClipboardData(text: st.transcript()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(t('会话已复制到剪贴板')),
                        duration: const Duration(seconds: 1)),
                  );
                }
              }, dark),
              _action(context, '导出研究报告', () async {
                await Clipboard.setData(
                    ClipboardData(text: st.exportResearchReport()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(t('研究报告已复制到剪贴板')),
                        duration: const Duration(seconds: 1)),
                  );
                }
              }, dark),
            ]),
            _card(dark, [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Label(t('外观')),
              ),
              Row(
                children: AppThemeMode.values.map((m) {
                  final on = s.themeMode == m;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => st.patch((x) => x.themeMode = m),
                      child: Container(
                        height: 32,
                        margin: EdgeInsets.only(
                            right: m == AppThemeMode.dark ? 0 : 6),
                        decoration: BoxDecoration(
                          color: on ? C.brand : fieldOf(dark),
                          borderRadius: BorderRadius.circular(D.r),
                          border: on ? null : Border.all(color: lineOf(dark)),
                        ),
                        child: Center(
                          child: Text(
                            m.shortLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  on ? FontWeight.w600 : FontWeight.w400,
                              color:
                                  on ? Colors.white : (dark ? C.dInk2 : C.ink2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(s.themeMode.note, style: meta(dark, size: 11.5)),
            ]),
          ],
        ),
      ),
    );
  }

  /// 先收起抽屉，再从根导航层弹出面板，避免抽屉盖住底部面板。
  void _openSheet(BuildContext context, Widget sheet) {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  /// 分组白纸片：细描边 + 柔和阴影，和灰色画布拉开层次。
  Widget _card(bool dark, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 8),
      decoration: surfaceBox(dark, shadowScale: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _action(
      BuildContext context, String text, VoidCallback onTap, bool dark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(D.r),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
        ),
        child: Text(text, style: ts(dark, size: 13.5)),
      ),
    );
  }

  Widget _pluginEntry(BuildContext context, AppState st, bool dark) {
    final p = st.plugin;
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PluginSheet(),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p == null ? '添加 OpenAPI 插件' : p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(dark, size: 13.5)),
                  const SizedBox(height: 3),
                  Text(
                    p == null
                        ? '输入 Swagger / OpenAPI JSON 链接'
                        : '${p.operations.length} 个端点 · ${st.settings.pluginEnabled ? "已启用" : "已停用"}',
                    style: meta(dark, size: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: dark ? C.dInk3 : C.ink3),
          ],
        ),
      ),
    );
  }
}
