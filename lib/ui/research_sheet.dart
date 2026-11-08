import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// 底部面板通用外壳：圆角纸片 + 顶部手柄 + 标题，内容可滚动并避开键盘。
class SheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const SheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: canvasOf(dark),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(D.floatR)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 11),
              Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: lineOf(dark),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 14, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: display(dark, size: 18)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: sub(dark, size: 12.5)),
                          ],
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: fieldOf(dark),
                          borderRadius: BorderRadius.circular(D.r),
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: dark ? C.dInk2 : C.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: hairOf(dark)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _paper(bool dark, List<Widget> children) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: surfaceBox(dark, shadowScale: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

Widget _label(bool dark, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text.toUpperCase(), style: sectionTitle(dark)),
    );

Widget _btn(bool dark, String text, VoidCallback onTap,
        {bool primary = false}) =>
    GestureDetector(
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

void _toast(BuildContext context, String s) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
  );
}

Future<void> _copy(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  _toast(context, '$label已复制到剪贴板');
}

String _num(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ------------------------------------------------------------------ 用量面板

/// 20261108 → 11-08；跨年的历史带上年份，避免同一天两个「11-08」。
String _dayLabel(int key) {
  final y = key ~/ 10000;
  final m = (key ~/ 100) % 100;
  final d = key % 100;
  final mm = m.toString().padLeft(2, '0');
  final dd = d.toString().padLeft(2, '0');
  return y == DateTime.now().year ? '$mm-$dd' : '${y % 100}-$mm-$dd';
}

class UsageSheet extends StatelessWidget {
  const UsageSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stats = st.tokenStats;
    final cost = st.estimatedCost;

    return SheetScaffold(
      title: t('Token 用量'),
      subtitle: t('真实 usage 优先，未返回时本地估算'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paper(dark, [
            _label(dark, '累计'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_num(stats.total), style: display(dark, size: 34)),
                const SizedBox(width: 8),
                Text('tokens', style: meta(dark, size: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Text('今日 ${_num(stats.todayTotal)} tok · ${stats.requests} 次请求',
                style: ts(dark, size: 13, color: dark ? C.dInk2 : C.ink2)),
            if (stats.estimatedRequests > 0) ...[
              const SizedBox(height: 8),
              Text(
                '其中 ${stats.estimatedRequests} 次网关未返回 usage，已按字符估算（≈）。'
                '若接口因 stream_options 报 400，可在设置里关闭「用量追踪」。',
                style: meta(dark, size: 11.5, color: C.warn),
              ),
            ],
          ]),
          _paper(dark, [
            _label(dark, '输入 / 输出'),
            Row(
              children: [
                Expanded(child: _stat(dark, '输入', _num(stats.prompt))),
                const SizedBox(width: 10),
                Expanded(child: _stat(dark, '输出', _num(stats.completion))),
                const SizedBox(width: 10),
                Expanded(child: _stat(dark, '请求', _num(stats.requests))),
              ],
            ),
            if (cost != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(t('按当前单价估算'), style: ts(dark, size: 13)),
                  const Spacer(),
                  Text('¥ ${cost.toStringAsFixed(4)}',
                      style: ts(dark, size: 15, weight: FontWeight.w600)),
                ],
              ),
            ],
          ]),
          if (stats.byModel.isNotEmpty)
            _paper(dark, [
              _label(dark, '按模型 · 累计'),
              ...stats.byModel.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(dark, size: 13)),
                              const SizedBox(height: 2),
                              Text(
                                  '↑${_num(e.value.prompt)}  ↓${_num(e.value.completion)}',
                                  style: meta(dark, size: 11.5)),
                            ],
                          ),
                        ),
                        Text('${_num(e.value.total)} tok',
                            style: ts(dark,
                                size: 13, weight: FontWeight.w600)),
                      ],
                    ),
                  )),
            ]),
          if (stats.days.isNotEmpty)
            _paper(dark, [
              _label(dark, '按天'),
              ...stats.days.reversed.take(14).map((d) {
                final u = stats.day(d);
                final isToday = d == TokenStats.dayOf(DateTime.now());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(isToday ? '今天' : _dayLabel(d),
                          style: ts(dark,
                              size: 13,
                              weight: isToday
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                      const Spacer(),
                      Text('${_num(u.total)} tok · ${u.requests} 次',
                          style: meta(dark, size: 11.5)),
                    ],
                  ),
                );
              }),
            ]),
          _paper(dark, [
            _label(dark, '单价与追踪'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t('向网关索取真实 usage'), style: ts(dark, size: 13)),
              subtitle: Text(t('请求体附带 stream_options.include_usage'),
                  style: meta(dark, size: 11.5)),
              value: s.usageTracking,
              activeColor: C.brand,
              onChanged: (v) => st.patch((x) => x.usageTracking = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _priceField(dark, '输入 ¥ / 百万', s.priceInPerM, (v) {
                    st.patch((x) => x.priceInPerM = v);
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _priceField(dark, '输出 ¥ / 百万', s.priceOutPerM, (v) {
                    st.patch((x) => x.priceOutPerM = v);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(t('填 0 表示不计算费用。价格只用于本地估算，不联网、不上传。'),
                style: meta(dark, size: 11.5)),
          ]),
          Row(
            children: [
              Expanded(
                  child: _btn(dark, '导出 CSV',
                      () => _copy(context, st.exportUsageCsv(), '用量表'))),
              const SizedBox(width: 10),
              Expanded(
                child: _btn(dark, '清零统计', () async {
                  final ok = await _confirm(
                      context, dark, '清零累计用量？', '仅清除本地统计，不影响实验记录。');
                  if (ok == true) st.resetTokenStats();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(bool dark, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: insetBox(dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: meta(dark, size: 11.5)),
            const SizedBox(height: 6),
            Text(value, style: ts(dark, size: 17, weight: FontWeight.w600)),
          ],
        ),
      );

  Widget _priceField(
      bool dark, String label, double value, ValueChanged<double> onChanged) {
    final ctrl =
        TextEditingController(text: value == 0 ? '' : value.toStringAsFixed(2));
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: ts(dark, size: 13),
      decoration: fieldDecoration(dark, hint: label),
      onChanged: (v) => onChanged(double.tryParse(v.trim()) ?? 0),
    );
  }
}

// ------------------------------------------------------------------ 实验记录

class RecordsSheet extends StatelessWidget {
  const RecordsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final list = st.records;

    return SheetScaffold(
      title: t('实验记录'),
      subtitle: t('每次调用的参数、请求体与响应原文'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _btn(dark, '导出 Markdown',
                      () => _copy(context, st.exportRecordsMarkdown(), '记录'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _btn(dark, '导出 JSON',
                      () => _copy(context, st.exportRecordsJson(), '记录'))),
            ],
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            _paper(dark, [
              Text(t('还没有记录。'), style: ts(dark, size: 13)),
              const SizedBox(height: 8),
              Text(t('在设置页打开「自动记录实验」，之后每次普通对话与深度研究的每一轮调用都会连同参数、脱敏请求体和模型原文一起留档，最多 120 条。'),
                style: meta(dark, size: 11.5),
              ),
            ])
          else
            ...list.map((r) => GestureDetector(
                  onTap: () => _detail(context, dark, r),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                    decoration: surfaceBox(dark, shadowScale: 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(r.dateLabel, style: meta(dark, size: 11.5)),
                            const SizedBox(width: 8),
                            Text(r.kind == 'research' ? '研究' : '对话',
                                style: meta(dark,
                                    size: 11.5, color: accentOf(dark))),
                            const Spacer(),
                            if (r.usage != null)
                              Text(r.usage!.label,
                                  style: meta(dark, size: 11.5)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(r.query.isEmpty ? '（多模态任务）' : r.query,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ts(dark, size: 13)),
                        const SizedBox(height: 7),
                        Text('${r.presetName}  /  ${r.model}  /  ${r.tier}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta(dark, size: 11.5)),
                      ],
                    ),
                  ),
                )),
          if (list.isNotEmpty) ...[
            const SizedBox(height: 4),
            _btn(dark, '清空全部记录', () async {
              final ok = await _confirm(
                  context, dark, '清空全部实验记录？', '共 ${list.length} 条，清空后无法恢复。');
              if (ok == true) st.clearRecords();
            }),
          ],
        ],
      ),
    );
  }

  void _detail(BuildContext context, bool dark, ExperimentRecord r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.dateLabel} · ${r.presetName}',
            style: ts(dark, size: 14, weight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              r.toMarkdown(),
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
                Clipboard.setData(ClipboardData(text: r.toMarkdown()));
                Navigator.pop(ctx);
                _toast(context, '该条记录已复制');
              },
              child: Text(t('复制'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('关闭'))),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 研究启动

class ResearchLauncher extends StatefulWidget {
  const ResearchLauncher({super.key});

  @override
  State<ResearchLauncher> createState() => _ResearchLauncherState();
}

class _ResearchLauncherState extends State<ResearchLauncher> {
  final _topic = TextEditingController();

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final busy = st.researching;

    return SheetScaffold(
      title: t('深度研究'),
      subtitle: t('检索 → 大纲 → 逐节展开 → 汇总报告'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy)
            _paper(dark, [
              _label(dark, '进行中'),
              Text(st.researchStatusLabel,
                  style: ts(dark, size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: st.researchTotal == 0
                    ? null
                    : st.researchStep / (st.researchTotal + 2),
                backgroundColor: fieldOf(dark),
                color: C.brand,
                minHeight: 3,
              ),
              const SizedBox(height: 10),
              _btn(dark, '中断研究', () => st.stop()),
            ]),
          _paper(dark, [
            _label(dark, '研究主题'),
            TextField(
              controller: _topic,
              minLines: 2,
              maxLines: 4,
              enabled: !busy,
              style: ts(dark, size: 13.5, height: 1.55),
              decoration:
                  fieldDecoration(dark, hint: t('例如：端侧小模型在 2025 年的推理优化路径')),
            ),
          ]),
          _paper(dark, [
            _label(dark, '研究深度'),
            Row(
              children: [
                _depth(dark, st, 1, '速览', '2 节'),
                const SizedBox(width: 8),
                _depth(dark, st, 2, '标准', '4 节'),
                const SizedBox(width: 8),
                _depth(dark, st, 3, '深入', '6 节'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              s.searchActive
                  ? '联网已启用 · ${s.activeSources.length} 个源，将先做多源检索再展开。'
                  : '联网未启用，报告基于模型自身知识，请自行核实关键事实。',
              style: meta(dark,
                  size: 11.5, color: s.searchActive ? accentOf(dark) : null),
            ),
            const SizedBox(height: 6),
            Text(
                '预计 ${st.settings.sectionCount + 1} 次模型调用，'
                '逐节结果会实时出现在会话里，可随时中断。',
                style: meta(dark, size: 11.5)),
          ]),
          _btn(dark, busy ? '正在研究…' : '开始研究', () {
            if (busy || _topic.text.trim().isEmpty) {
              if (!busy) _toast(context, '请先填写研究主题');
              return;
            }
            final topic = _topic.text.trim();
            Navigator.pop(context);
            st.runResearch(topic);
          }, primary: true),
        ],
      ),
    );
  }

  Widget _depth(
      bool dark, AppState st, int value, String label, String sections) {
    final on = st.settings.researchDepth == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => st.patch((x) => x.researchDepth = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? C.brand : fieldOf(dark),
            borderRadius: BorderRadius.circular(D.r),
            border: on ? null : Border.all(color: borderOf(dark)),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : (dark ? C.dInk : C.ink),
                  )),
              const SizedBox(height: 4),
              Text(sections,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: on ? Colors.white70 : (dark ? C.dInk3 : C.ink3),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 预设管理

class PresetManager extends StatelessWidget {
  const PresetManager({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SheetScaffold(
      title: t('提示词预设库'),
      subtitle: t('切换不丢失内容；每份预设独立保存'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...s.promptPresets.map((p) {
            final on = p.id == s.activePresetId;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: surfaceBox(
                dark,
                shadowScale: 0.4,
                fill: on ? (dark ? C.dSink : C.brandSoft) : null,
              ),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                onTap: () {
                  st.patch((x) => x.activePresetId = p.id);
                  Navigator.pop(context);
                },
                title: Text(p.name,
                    style: ts(dark,
                        size: 13.5,
                        weight: on ? FontWeight.w600 : FontWeight.w400)),
                subtitle: Text(
                  '${p.builtin ? "内置" : "自定义"} · ${p.content.length} 字符'
                  '${PromptPreset.variablesOf(p.content).isEmpty ? "" : " · 含变量"}',
                  style: meta(dark, size: 11.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (on)
                      Icon(Icons.check_rounded,
                          size: 16, color: accentOf(dark)),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz_rounded,
                          size: 18, color: dark ? C.dInk3 : C.ink3),
                      color: surfaceOf(dark),
                      surfaceTintColor: Colors.transparent,
                      onSelected: (v) => _onAction(context, st, dark, p, v),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'rename', child: Text(t('重命名'))),
                        PopupMenuItem(value: 'copy', child: Text(t('复制一份'))),
                        PopupMenuItem(
                            value: 'export', child: Text(t('复制内容'))),
                        if (!p.builtin)
                          PopupMenuItem(
                              value: 'delete', child: Text(t('删除'))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                  child: _btn(dark, '新建预设',
                      () => _onAction(context, st, dark, null, 'new'),
                      primary: true)),
              const SizedBox(width: 10),
              Expanded(
                  child: _btn(dark, '恢复内置', () async {
                final ok = await _confirm(
                    context, dark, '恢复内置预设？', '会追加缺失的内置预设，你自己的预设不会被删除。');
                if (ok == true) {
                  st.patch((x) {
                    for (final d in defaultPresets()) {
                      if (!x.promptPresets.any((e) => e.id == d.id)) {
                        x.promptPresets.add(d);
                      }
                    }
                  });
                }
              })),
            ],
          ),
          const SizedBox(height: 14),
          Text(t('在提示词里使用 {{query}} {{date}} {{time}} {{model}} {{language}} {{sources}} {{tier}}，发送前会被替换为真实值。'),
            style: meta(dark, size: 11.5),
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, AppState st, bool dark,
      PromptPreset? p, String action) async {
    if (action == 'export' && p != null) {
      await _copy(context, p.content, '预设内容');
      return;
    }
    if (action == 'copy' && p != null) {
      st.patch((x) {
        final c = p.copy(name: '${p.name} 副本');
        x.promptPresets.add(c);
        x.activePresetId = c.id;
      });
      return;
    }
    if (action == 'delete' && p != null) {
      if (st.settings.promptPresets.length <= 1) {
        _toast(context, '至少保留一份预设');
        return;
      }
      final ok = await _confirm(context, dark, '删除「${p.name}」？', '不可恢复。');
      if (ok == true) {
        st.patch((x) {
          x.promptPresets.removeWhere((e) => e.id == p.id);
          if (x.activePresetId == p.id) {
            x.activePresetId = x.promptPresets.first.id;
          }
        });
      }
      return;
    }
    if (action == 'new' || action == 'rename') {
      final name = await _askName(
          context,
          dark,
          action == 'new' ? '新建预设' : '重命名预设',
          action == 'new' ? '' : p?.name ?? '');
      if (name == null || name.trim().isEmpty) return;
      st.patch((x) {
        if (action == 'new') {
          final np = PromptPreset(
              id: 'p_${DateTime.now().millisecondsSinceEpoch}',
              name: name.trim(),
              content: kDefaultSystemPrompt);
          x.promptPresets.add(np);
          x.activePresetId = np.id;
        } else if (p != null) {
          final target = x.presetById(p.id);
          if (target != null) target.name = name.trim();
        }
      });
    }
  }

  Future<String?> _askName(
      BuildContext context, bool dark, String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: ts(dark, size: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: ts(dark, size: 13.5),
          decoration: fieldDecoration(dark, hint: t('预设名称')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(t('确定'))),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 通用确认

Future<bool?> _confirm(
        BuildContext context, bool dark, String title, String body) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: ts(dark, size: 15)),
        content: Text(body, style: ts(dark, size: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('确定'))),
        ],
      ),
    );
