import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/agent_tools.dart';
import '../services/agent_workspace.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'widgets.dart';

/// 工作台上的非模态授权条。
///
/// 刻意不用 AlertDialog：弹窗会打断阅读、遮住正在流的回答。
/// 这条横幅贴在输入栏上方，用户可以继续看内容，随时「允许 / 跳过」。
class AgentApprovalBar extends StatelessWidget {
  final AgentAction action;
  final bool dark;

  const AgentApprovalBar({
    super.key,
    required this.action,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius: BorderRadius.circular(D.floatR),
        border: Border.all(color: lineOf(dark)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.5 : 0.12),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 15, color: dark ? C.dInk2 : C.ink2),
              const SizedBox(width: 7),
              Text(t('智能体请求执行'),
                  style: ts(dark, size: 13, weight: FontWeight.w600)),
              const Spacer(),
              Text(action.toolName,
                  style: meta(dark, size: 11.5, color: dark ? C.dInk3 : C.ink3)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            action.preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ts(dark, size: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => st.resolveAgentAction(false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(t('跳过'),
                      style: ts(dark, size: 13, color: dark ? C.dInk2 : C.ink2)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => st.resolveAgentAction(true),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: C.brand,
                    borderRadius: BorderRadius.circular(D.r),
                  ),
                  child: Text(t('允许'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置 → 设备智能体。
///
/// 信息密度按「先看边界、再看授权、最后才看细节」排布：默认只展开三块，
/// 工具全集与执行记录收在折叠区，避免又变成一屏塞满开关的后台感。
class AgentPanel extends StatefulWidget {
  final bool dark;
  const AgentPanel({super.key, required this.dark});

  @override
  State<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel> {
  List<WorkspaceEntry> _files = const [];
  List<WorkspaceEntry> _trash = const [];
  bool _loading = true;
  bool _showTools = false;
  bool _showTrash = false;
  bool _showLog = false;

  bool get dark => widget.dark;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ws = context.read<AppState>().agentWorkspace;
    if (ws == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final f = await ws.list();
      final t = await ws.trashList();
      if (mounted) {
        setState(() {
          _files = f;
          _trash = t;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    await context.read<AppState>().refreshAgentData();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final ws = st.agentWorkspace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(t('设备智能体'), [
          Text(t('默认只回答问题。打开后，模型能读到这台设备的真实信息，并在你授权的范围内真正做事：读写独立工作区、打开应用与网页、新建日历日程、设置闹钟。'),
            style: sub(dark, size: 12.5),
          ),
          const SizedBox(height: 14),
          SwitchRow(
            title: t('启用本机操作'),
            subtitle: t('关闭时与纯聊天客户端完全一致，不注入任何工具'),
            value: s.agentEnabled,
            icon: Icons.touch_app_outlined,
            onChanged: (v) => st.patch((x) => x.agentEnabled = v),
          ),
          const SizedBox(height: 4),
          _note(
            '安全边界：所有文件操作只发生在应用专属目录里，'
            '绝对路径、.. 、隐藏文件与符号链接一律拒绝；'
            '覆盖写会自动备份旧版，删除只是移入回收站，不会真正丢失文件。'
            '系统命令从不执行。',
          ),
        ]),
        _section(t('这台设备'), [
          ...st.deviceInfo.rows.map((r) => _kv(r.label, r.value)),
          const SizedBox(height: 10),
          _link('重新读取设备信息', Icons.refresh_rounded, _refreshAll),
        ]),
        _section(t('授权范围'), [
          Text(t('未授权的动作不会执行，模型会收到「需要授权」的结果并改用文字说明。'),
              style: meta(dark, size: 11.5, height: 1.5)),
          const SizedBox(height: 12),
          SwitchRow(
            title: t('文件与脚本'),
            subtitle: t('隔离工作区内读写、任务脚本（沙箱保护，默认放开）'),
            value: s.agentAllowWorkspace,
            onChanged: (v) => st.patch((x) => x.agentAllowWorkspace = v),
          ),
          SwitchRow(
            title: t('应用与网页'),
            subtitle: t('打开已装应用、调起系统浏览器、分享、写剪贴板'),
            value: s.agentAllowExternal,
            onChanged: (v) => st.patch((x) => x.agentAllowExternal = v),
          ),
          SwitchRow(
            title: t('日历与闹钟'),
            subtitle: t('只打开系统确认页，需你亲手点保存才生效'),
            value: s.agentAllowSystem,
            onChanged: (v) => st.patch((x) => x.agentAllowSystem = v),
          ),
          SwitchRow(
            title: t('网页抓取'),
            subtitle: t('读取公开网页正文（禁止内网 / 元数据地址）'),
            value: s.agentAllowNetwork,
            onChanged: (v) => st.patch((x) => x.agentAllowNetwork = v),
          ),
          SwitchRow(
            title: t('每次操作先问我'),
            subtitle: t('写文件、打开应用等动作在界面上等你点「允许」'),
            value: s.agentConfirmEach,
            onChanged: (v) => st.patch((x) => x.agentConfirmEach = v),
          ),
          const SizedBox(height: 6),
          Text(t('单次任务最多执行几步'), style: meta(dark, size: 11.5)),
          const SizedBox(height: 8),
          Row(
            children: [2, 4, 6, 8].map((n) {
              final on = s.agentMaxSteps == n;
              return Expanded(
                child: GestureDetector(
                  onTap: () => st.patch((x) => x.agentMaxSteps = n),
                  child: Container(
                    height: 32,
                    margin: EdgeInsets.only(right: n == 8 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: on ? C.brand : fieldOf(dark),
                      borderRadius: BorderRadius.circular(D.r),
                      border: on ? null : Border.all(color: lineOf(dark)),
                    ),
                    child: Center(
                      child: Text('$n 步',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            color: on ? Colors.white : (dark ? C.dInk2 : C.ink2),
                          )),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
        _section(t('独立工作区'), [
          Text(
            ws == null
                ? '工作区准备中…'
                : (ws.root),
            maxLines: 2,
            style: ts(dark, size: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _link('复制路径', Icons.copy_all_outlined, () async {
                if (ws == null) return;
                await Clipboard.setData(ClipboardData(text: ws.root));
                _toast('工作区路径已复制');
              }),
              const SizedBox(width: 14),
              _link('刷新', Icons.refresh_rounded, _refreshAll),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('文件 · ${_files.length}',
                  style: ts(dark, size: 13, weight: FontWeight.w600)),
              if (_loading)
                const SizedBox(
                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            Text(t('暂时是空的。让智能体「把结果保存到 notes/」就会出现在下面。'),
                style: meta(dark, size: 11.5, height: 1.5))
          else
            ..._files.take(10).map((e) => _fileRow(ws, e, restore: false)),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _showTrash = !_showTrash),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 15, color: dark ? C.dInk2 : C.ink2),
                  const SizedBox(width: 8),
                  Text('回收站 · ${_trash.length} 个条目',
                      style: ts(dark, size: 13)),
                  const Spacer(),
                  Icon(_showTrash ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 17, color: dark ? C.dInk3 : C.ink3),
                ],
              ),
            ),
          ),
          if (_showTrash) ...[
            const SizedBox(height: 6),
            if (_trash.isEmpty)
              Text(t('回收站是空的。'), style: meta(dark, size: 11.5))
            else ...[
              ..._trash.take(8).map((e) => _fileRow(ws, e, restore: true)),
              const SizedBox(height: 8),
              _link('永久清空回收站', Icons.delete_forever_outlined, _confirmClearTrash,
                  danger: true),
            ],
          ],
        ]),
        _section(t('可用工具 · ${kAgentTools.length}'), [
          Text(t('只读工具随时可用；其余按上面的授权分组生效。'),
              style: meta(dark, size: 11.5, height: 1.5)),
          const SizedBox(height: 10),
          ...(_showTools ? kAgentTools : kAgentTools.take(6))
              .map((t) => _toolRow(t, _grantAllows(s, t))),
          const SizedBox(height: 8),
          _link(_showTools ? '收起' : '查看全部 ${kAgentTools.length} 个工具',
              _showTools ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              () => setState(() => _showTools = !_showTools)),
        ]),
        _section(t('执行记录 · ${st.agentLog.length}'), [
          if (st.agentLog.isEmpty)
            Text(t('还没有执行过本机操作。每一步都会留痕，可随时回溯。'),
                style: meta(dark, size: 11.5, height: 1.5))
          else ...[
            ...(_showLog ? st.agentLog.take(30) : st.agentLog.take(5))
                .map(_logRow),
            if (st.agentLog.length > 5) ...[
              const SizedBox(height: 8),
              _link(_showLog ? '只看最近 5 条' : '显示全部',
                  _showLog ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  () => setState(() => _showLog = !_showLog)),
            ],
          ],
        ]),
      ],
    );
  }

  bool _grantAllows(AppSettings s, AgentTool t) {
    // 与 AppState.agentGrant 保持一致，这里只用于面板上的灰显提示。
    return switch (t.grant) {
      '' => true,
      'workspace' => s.agentAllowWorkspace,
      'external' => s.agentAllowExternal,
      'system' => s.agentAllowSystem,
      'network' => s.agentAllowNetwork,
      _ => false,
    };
  }

  Widget _toolRow(AgentTool t, bool enabled) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_toolIcon(t),
              size: 15,
              color: enabled
                  ? (dark ? C.dInk2 : C.ink2)
                  : (dark ? C.dInk3 : C.ink3)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    style: ts(dark,
                        size: 13,
                        weight: FontWeight.w500,
                        color: enabled ? null : (dark ? C.dInk3 : C.ink3))),
                const SizedBox(height: 2),
                Text(t.summary,
                    style: meta(dark,
                        size: 11.5,
                        height: 1.45,
                        color: dark ? C.dInk3 : C.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(enabled ? t.riskLabel : '未授权',
              style: meta(dark,
                  size: 11.5,
                  color: enabled ? null : C.warn)),
        ],
      ),
    );
  }

  IconData _toolIcon(AgentTool t) {
    if (t.id.startsWith('agent.device')) return Icons.phone_android_outlined;
    if (t.id.startsWith('agent.app')) return Icons.apps_outlined;
    if (t.id.startsWith('agent.workspace')) return Icons.folder_outlined;
    if (t.id.startsWith('agent.web')) return Icons.public_outlined;
    if (t.id == 'agent.calendar.add') return Icons.event_outlined;
    if (t.id == 'agent.alarm.set') return Icons.alarm_outlined;
    if (t.id == 'agent.share.text') return Icons.ios_share_outlined;
    if (t.id == 'agent.clipboard.set') return Icons.content_copy_outlined;
    return Icons.bolt_outlined;
  }

  Widget _fileRow(AgentWorkspace? ws, WorkspaceEntry e, {required bool restore}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(e.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
              size: 14, color: dark ? C.dInk3 : C.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(dark, size: 13)),
                Text('${e.sizeLabel} · ${_time(e.modifiedMs)}',
                    style: meta(dark, size: 11.5)),
              ],
            ),
          ),
          if (restore && ws != null)
            InkWell(
              onTap: () async {
                try {
                  await ws.restore(e.name);
                  await _reload();
                  _toast('已恢复到工作区');
                } catch (err) {
                  _toast('恢复失败：$err');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(t('恢复'),
                    style: ts(dark, size: 13, color: accentOf(dark))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _logRow(AgentLogEntry e) {
    final ok = e.ok;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: 9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? C.ok : C.warn,
            ),
          ),
          Expanded(
            child: Text('${e.tool} · ${e.detail}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: meta(dark, size: 11.5, height: 1.45)),
          ),
          const SizedBox(width: 8),
          Text(_time(e.at), style: meta(dark, size: 11.5)),
        ],
      ),
    );
  }

  Future<void> _confirmClearTrash() async {
    final st = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('永久清空回收站？')),
        content: Text(t('回收站里的备份与被删文件将被真正删除，无法恢复。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('清空'))),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await st.clearAgentTrash();
    await _reload();
    _toast(msg);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 82,
                child: Text(label, style: meta(dark, size: 11.5))),
            Expanded(
                child: Text(value,
                    style: ts(dark, size: 13, height: 1.4))),
          ],
        ),
      );

  Widget _note(String text) => Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
        decoration: BoxDecoration(
          color: fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined,
                size: 15, color: dark ? C.dInk2 : C.ink2),
            const SizedBox(width: 9),
            Expanded(
                child: Text(text,
                    style: meta(dark, size: 11.5, height: 1.6))),
          ],
        ),
      );

  Widget _link(String text, IconData icon, VoidCallback onTap,
          {bool danger = false}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(D.r),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: danger ? C.danger : accentOf(dark)),
              const SizedBox(width: 6),
              Text(text,
                  style: ts(dark,
                      size: 13,
                      color: danger ? C.danger : accentOf(dark))),
            ],
          ),
        ),
      );

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: surfaceBox(dark, shadowScale: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: ts(dark,
                    size: 14.5, weight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.month}/${d.day} ${p(d.hour)}:${p(d.minute)}';
  }
}
