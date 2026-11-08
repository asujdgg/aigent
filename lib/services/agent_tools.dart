import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'agent_script.dart';
import 'agent_workspace.dart';
import 'device_bridge.dart';
import 'plugin_service.dart';

/// 风险等级。只读类可以静默跑；写入与外部动作默认需要用户明确授权。
enum AgentRisk { read, workspace, external, system, network }

/// 授权分组。四个开关都在「设置 → 设备智能体」里，默认全关。
class AgentGrant {
  final bool workspace;
  final bool external;
  final bool system;
  final bool network;

  const AgentGrant({
    this.workspace = false,
    this.external = false,
    this.system = false,
    this.network = false,
  });

  bool allows(String grant) => switch (grant) {
        '' => true,
        'workspace' => workspace,
        'external' => external,
        'system' => system,
        'network' => network,
        _ => false,
      };

  static String labelOf(String grant) => switch (grant) {
        'workspace' => '文件与脚本',
        'external' => '应用与网页',
        'system' => '日历与闹钟',
        'network' => '网页抓取',
        _ => '只读',
      };
}

class AgentTool {
  final String id;
  final String name;
  final String summary;
  final String usage;
  final AgentRisk risk;
  final String grant;

  const AgentTool({
    required this.id,
    required this.name,
    required this.summary,
    required this.usage,
    required this.risk,
    this.grant = '',
  });

  String get shortId => id.startsWith('agent.') ? id.substring(6) : id;

  String get riskLabel => switch (risk) {
        AgentRisk.read => '只读',
        AgentRisk.workspace => '写工作区',
        AgentRisk.external => '调起外部应用',
        AgentRisk.system => '系统数据',
        AgentRisk.network => '网络读取',
      };

  /// 只读且无副作用的工具可以在「每次确认」开启时依然静默执行。
  bool get needsConfirmation => risk != AgentRisk.read;
}

/// 本机工具全集。每一项都对应一段**真实可执行**的本地能力，不列做不到的。
const List<AgentTool> kAgentTools = [
  AgentTool(
    id: 'agent.device.info',
    name: '读取本机信息',
    summary: '获取手机型号、厂商、芯片、内存、存储、屏幕、电量与系统版本',
    usage: '无参数',
    risk: AgentRisk.read,
  ),
  AgentTool(
    id: 'agent.app.list',
    name: '列出已装应用',
    summary: '列出这台手机上可以从桌面启动的应用及其应用名 / 包名',
    usage: 'keyword(可选，按名字过滤)',
    risk: AgentRisk.read,
  ),
  AgentTool(
    id: 'agent.workspace.list',
    name: '查看工作区',
    summary: '列出隔离工作区里的文件与文件夹',
    usage: 'path(可选，子目录)',
    risk: AgentRisk.read,
  ),
  AgentTool(
    id: 'agent.workspace.read',
    name: '读取工作区文件',
    summary: '读取工作区内某个文本文件的完整内容',
    usage: 'path(必填，工作区内相对路径)',
    risk: AgentRisk.read,
  ),
  AgentTool(
    id: 'agent.workspace.usage',
    name: '工作区用量',
    summary: '查看文件数、占用空间与回收站条目数',
    usage: '无参数',
    risk: AgentRisk.read,
  ),
  AgentTool(
    id: 'agent.workspace.write',
    name: '写文件',
    summary: '在工作区新建或覆盖一个文本文件（覆盖前自动备份旧版）',
    usage: 'path(必填), content(必填)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.append',
    name: '追加文本',
    summary: '往工作区已有文件末尾追加内容（追加前自动备份）',
    usage: 'path(必填), content(必填)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.mkdir',
    name: '新建文件夹',
    summary: '在工作区内创建子目录',
    usage: 'path(必填)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.delete',
    name: '删除到回收站',
    summary: '把工作区文件移入回收站（不真删，可恢复）',
    usage: 'path(必填)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.rename',
    name: '重命名',
    summary: '重命名 / 移动工作区内的文件或文件夹',
    usage: 'from(必填), to(必填)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.restore',
    name: '恢复文件',
    summary: '从回收站恢复一个被删除或被覆盖前的版本',
    usage: 'name(必填，回收站条目名)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.workspace.run',
    name: '运行任务脚本',
    summary: '在沙箱内执行一段受限任务脚本，批量完成文件整理 / 文档生成',
    usage: 'script(必填，脚本全文)',
    risk: AgentRisk.workspace,
    grant: 'workspace',
  ),
  AgentTool(
    id: 'agent.web.fetch',
    name: '读取网页正文',
    summary: '抓取一个公开网页的正文文本并作为结果返回（禁止内网地址）',
    usage: 'url(必填，http/https)',
    risk: AgentRisk.network,
    grant: 'network',
  ),
  AgentTool(
    id: 'agent.web.open',
    name: '用本机浏览器打开',
    summary: '调起手机浏览器打开网页，或直接发起一次网页搜索',
    usage: 'url 或 query(二选一)',
    risk: AgentRisk.external,
    grant: 'external',
  ),
  AgentTool(
    id: 'agent.app.open',
    name: '打开应用',
    summary: '按应用名或包名启动手机上已安装的应用',
    usage: 'name 或 package(二选一)',
    risk: AgentRisk.external,
    grant: 'external',
  ),
  AgentTool(
    id: 'agent.share.text',
    name: '系统分享',
    summary: '调起系统分享面板发送一段文本',
    usage: 'text(必填)',
    risk: AgentRisk.external,
    grant: 'external',
  ),
  AgentTool(
    id: 'agent.clipboard.set',
    name: '写入剪贴板',
    summary: '把一段文本复制到系统剪贴板',
    usage: 'text(必填)',
    risk: AgentRisk.external,
    grant: 'external',
  ),
  AgentTool(
    id: 'agent.toast',
    name: '屏幕提示',
    summary: '在手机上弹一条短提示',
    usage: 'text(必填)',
    risk: AgentRisk.external,
    grant: 'external',
  ),
  AgentTool(
    id: 'agent.calendar.add',
    name: '新建日历日程',
    summary: '打开系统日历的新建事件页（需用户点保存才生效）',
    usage: 'title(必填), start(ISO 时间或 +分钟数), minutes(时长), location, description',
    risk: AgentRisk.system,
    grant: 'system',
  ),
  AgentTool(
    id: 'agent.alarm.set',
    name: '设置闹钟',
    summary: '打开系统时钟的设置闹钟页（需用户点保存才生效）',
    usage: 'hour(0-23, 必填), minute(0-59), label',
    risk: AgentRisk.system,
    grant: 'system',
  ),
];

AgentTool? agentToolById(String id) {
  for (final t in kAgentTools) {
    if (t.id == id || t.shortId == id) return t;
  }
  return null;
}

/// 从模型输出里解析本机工具调用。
///
/// 复用 OpenApiPlugin 里那套稳健的 JSON 扫描（fenced / 内联 / 括号平衡），
/// 但**只认 `agent.` 前缀或本机工具短名**，这样同时启用 OpenAPI 插件时两边
/// 不会互相把对方的工具 JSON 吞掉。
Map<String, dynamic>? parseAgentToolCall(String text) {
  final call = OpenApiPlugin.parseToolCall(text);
  if (call == null) return null;
  final raw = call['tool'].toString().trim();
  final tool = agentToolById(raw);
  if (tool == null) return null;
  return {
    'tool': tool.id,
    'arguments': call['arguments'] as Map<String, dynamic>,
    'name': tool.name,
  };
}

/// 注入 System Prompt 的本机能力说明。
String buildAgentPrompt({
  required DeviceInfo info,
  required AgentGrant grant,
  required String workspaceRoot,
  required bool confirmEach,
}) {
  final b = StringBuffer();
  b.writeln('[本机能力] 你运行在用户这台手机上，可以真正操作设备，而不只是回答问题。'
      '默认仍然直接回答；只有用户明确要求你「打开 / 查找 / 保存 / 设置 / 运行」时才调用工具。');
  b.writeln('[设备信息] ${info.promptSummary}');
  b.writeln('[隔离工作区] 你有一个专属文件夹（$workspaceRoot），所有文件操作只能在这里进行。'
      '只接受相对路径；绝对路径、..、隐藏文件、符号链接一律被拒绝。'
      '覆盖写会自动备份旧版，删除只是移入回收站，不会真正丢失文件。'
      '绝不要求或诱导用户提供工作区之外的文件路径，也不要声称能读写手机里其它文件。');
  b.writeln('[工具调用格式] 需要调用工具时，只输出一行 JSON，不附加解释、不要放进代码块：');
  b.writeln('{"tool":"agent.工具ID","arguments":{"参数名":"值"}}');
  b.writeln('可用工具（共 ${kAgentTools.length} 个，方括号为当前授权状态）：');
  for (final t in kAgentTools) {
    final on = grant.allows(t.grant);
    b.writeln('- ${t.id} | ${t.name} | ${t.summary} | 参数: ${t.usage} | '
        '${t.grant.isEmpty ? "可直接用" : "[${on ? "已授权" : "未授权"}] ${AgentGrant.labelOf(t.grant)}"}');
  }
  b.writeln('调用后会收到「[工具执行结果]」，届时请用自然语言总结实际做了什么，'
      '不要再输出工具 JSON；未获授权或执行失败时如实说明，不要反复重试同一个调用。');
  if (confirmEach) {
    b.writeln('[风险确认] 写文件、打开应用、日历闹钟等动作会在界面上先请用户点「允许」，'
        '用户可能拒绝；请把这一步当作正常结果处理。');
  }
  b.writeln(AgentScriptRunner.syntaxPrompt);
  b.writeln('[硬边界] 你不能执行任意系统命令、安装软件、读取其它应用的数据、'
      '修改系统设置或删除用户文件。做不到的请求直接说明原因并给出替代做法。');
  return b.toString();
}

/// 一次待用户确认的动作（非模态确认条展示用）。
class AgentAction {
  final String tool;
  final String toolName;
  final String preview;
  final Map<String, dynamic> args;

  const AgentAction({
    required this.tool,
    required this.toolName,
    required this.preview,
    required this.args,
  });
}

class AgentExecution {
  final String tool;
  final String toolName;
  final bool ok;
  final String message;
  final String? missingGrant;
  final bool declined;

  const AgentExecution({
    required this.tool,
    required this.toolName,
    required this.ok,
    required this.message,
    this.missingGrant,
    this.declined = false,
  });

  /// 回灌给模型的结果文本。
  String get asToolResult => ok
      ? '[工具 $toolName 执行结果]\n$message'
      : (declined
          ? '[工具 $toolName 未执行] 用户拒绝了这次操作。请改用文字说明，不要重试。'
          : '[工具 $toolName 未执行] $message');
}

/// 本机工具执行器。所有动作都在这里收敛：授权检查 → 用户确认 → 执行 → 审计日志。
class AgentRuntime {
  AgentRuntime({
    required this.workspace,
    required this.grant,
    required this.deviceInfo,
    DeviceBridge? device,
    this.confirm,
    this.confirmEach = true,
  }) : device = device ?? DeviceBridge();

  final AgentWorkspace workspace;
  final AgentGrant grant;
  final DeviceInfo deviceInfo;
  final DeviceBridge device;
  final Future<bool> Function(AgentAction action)? confirm;
  final bool confirmEach;

  static String _arg(Map<String, dynamic> a, String key, [String fallback = '']) {
    final v = a[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static int _int(Map<String, dynamic> a, String key, int fallback) {
    final v = a[key];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  String previewOf(AgentTool t, Map<String, dynamic> a) {
    final path = _arg(a, 'path', _arg(a, 'from'));
    return switch (t.id) {
      'agent.workspace.write' || 'agent.workspace.append' =>
        '写入文件：$path（${_arg(a, 'content').length} 字）',
      'agent.workspace.run' => '运行任务脚本（${_arg(a, 'script').length} 字）',
      'agent.workspace.delete' => '移入回收站：$path',
      'agent.workspace.rename' => '重命名：$path → ${_arg(a, 'to')}',
      'agent.workspace.restore' => '从回收站恢复：${_arg(a, 'name')}',
      'agent.workspace.mkdir' => '新建文件夹：$path',
      'agent.app.open' => '打开应用：${_arg(a, 'name', _arg(a, 'package'))}',
      'agent.web.open' => '打开网页：${_arg(a, 'url', _arg(a, 'query'))}',
      'agent.web.fetch' => '抓取网页：${_arg(a, 'url')}',
      'agent.calendar.add' => '新建日程：${_arg(a, 'title')}',
      'agent.alarm.set' => '设置闹钟：${_arg(a, 'hour')}:${_arg(a, 'minute')}',
      'agent.share.text' => '调起分享：${_arg(a, 'text')}',
      'agent.clipboard.set' => '写入剪贴板：${_arg(a, 'text')}',
      'agent.toast' => '屏幕提示：${_arg(a, 'text')}',
      _ => '${t.name} ${_arg(a, 'path')}'.trim(),
    };
  }

  Future<AgentExecution> execute(String toolId, Map<String, dynamic> args) async {
    final t = agentToolById(toolId);
    if (t == null) {
      return AgentExecution(
          tool: toolId, toolName: toolId, ok: false, message: '未知本机工具：$toolId');
    }
    if (!grant.allows(t.grant)) {
      final msg = '该操作需要「${AgentGrant.labelOf(t.grant)}」授权，'
          '请到 设置 → 设备智能体 打开对应开关后再试。';
      await _log(t, false, '未授权：${t.name}');
      return AgentExecution(
          tool: t.id,
          toolName: t.name,
          ok: false,
          message: msg,
          missingGrant: t.grant);
    }
    if (confirmEach && t.needsConfirmation && confirm != null) {
      final ok = await confirm!(AgentAction(
        tool: t.id,
        toolName: t.name,
        preview: previewOf(t, args),
        args: args,
      ));
      if (!ok) {
        await _log(t, false, '用户拒绝：${previewOf(t, args)}');
        return AgentExecution(
            tool: t.id,
            toolName: t.name,
            ok: false,
            declined: true,
            message: '用户拒绝');
      }
    }

    try {
      final msg = await _run(t, args);
      await _log(t, true, previewOf(t, args));
      return AgentExecution(
          tool: t.id, toolName: t.name, ok: true, message: msg);
    } catch (e) {
      final msg = '执行失败：$e';
      await _log(t, false, '${previewOf(t, args)} → $e');
      return AgentExecution(
          tool: t.id, toolName: t.name, ok: false, message: msg);
    }
  }

  Future<void> _log(AgentTool t, bool ok, String detail) async {
    try {
      await workspace.log(AgentLogEntry(
        at: DateTime.now().millisecondsSinceEpoch,
        tool: t.id,
        detail: detail,
        ok: ok,
      ));
    } catch (_) {}
  }

  Future<String> _run(AgentTool t, Map<String, dynamic> a) async {
    switch (t.id) {
      case 'agent.device.info':
        return deviceInfo.promptSummary;

      case 'agent.app.list':
        final kw = _arg(a, 'keyword').toLowerCase();
        final apps = await device.apps();
        final list = kw.isEmpty
            ? apps
            : apps.where((x) =>
                x.label.toLowerCase().contains(kw) ||
                x.packageName.toLowerCase().contains(kw)).toList();
        if (list.isEmpty) return '没有找到可启动的应用（可能需要系统权限或未安装桌面应用）。';
        final rows = list
            .take(60)
            .map((x) => '- ${x.label} → ${x.packageName}${x.system ? "（系统应用）" : ""}')
            .join('\n');
        return '共 ${list.length} 个应用：\n$rows';

      case 'agent.workspace.list':
        final entries = await workspace.list(_arg(a, 'path'));
        if (entries.isEmpty) return '工作区当前为空。';
        final rows = entries
            .map((e) => '- ${e.isDir ? "[目录] " : ""}${e.rel}  ${e.sizeLabel}')
            .join('\n');
        return '工作区共 ${entries.length} 项：\n$rows';

      case 'agent.workspace.read':
        final path = _arg(a, 'path');
        if (path.isEmpty) return '缺少 path 参数';
        return '文件 $path 内容：\n${await workspace.read(path)}';

      case 'agent.workspace.usage':
        final u = await workspace.usage();
        return '工作区：${u.files} 个文件，${(u.bytes / 1024).toStringAsFixed(1)} KB；'
            '回收站 ${u.trashFiles} 个条目。';

      case 'agent.workspace.write':
        return workspace.write(_arg(a, 'path'), _arg(a, 'content'));

      case 'agent.workspace.append':
        return workspace.append(_arg(a, 'path'), _arg(a, 'content'));

      case 'agent.workspace.mkdir':
        return workspace.mkdir(_arg(a, 'path'));

      case 'agent.workspace.delete':
        return workspace.delete(_arg(a, 'path'));

      case 'agent.workspace.rename':
        return workspace.rename(_arg(a, 'from'), _arg(a, 'to'));

      case 'agent.workspace.restore':
        return workspace.restore(_arg(a, 'name'));

      case 'agent.workspace.clearTrash':
        return workspace.clearTrash();

      case 'agent.workspace.run':
        final script = _arg(a, 'script');
        if (script.trim().isEmpty) return '缺少 script 参数';
        final r = await AgentScriptRunner(workspace).run(
          script,
          deviceModel: deviceInfo.model,
          deviceBrand: deviceInfo.brand,
        );
        final head = r.ok
            ? '脚本执行完成，共 ${r.steps} 条指令：'
            : '脚本在第 ${r.steps} 条指令中断：${r.error}';
        return '$head\n${r.output.isEmpty ? "（无输出）" : r.output}';

      case 'agent.web.fetch':
        return _fetch(_arg(a, 'url'));

      case 'agent.web.open':
        var url = _arg(a, 'url');
        final q = _arg(a, 'query');
        if (url.isEmpty && q.isNotEmpty) {
          url = 'https://www.bing.com/search?q=${Uri.encodeQueryComponent(q)}';
        }
        if (url.isEmpty) return '需要 url 或 query 参数';
        final ok = await device.openUrl(url);
        return ok
            ? '已在手机浏览器中打开：$url'
            : '未能打开浏览器（系统可能没有可用浏览器），链接：$url';

      case 'agent.app.open':
        var pkg = _arg(a, 'package');
        final name = _arg(a, 'name');
        if (pkg.isEmpty && name.isNotEmpty) {
          final apps = await device.apps();
          final k = name.toLowerCase();
          final hit = apps.where((x) =>
              x.label.toLowerCase() == k ||
              x.label.toLowerCase().contains(k) ||
              x.packageName.toLowerCase().contains(k));
          if (hit.isEmpty) {
            return '手机上没找到叫「$name」的可启动应用。可先用 agent.app.list 查看全部应用。';
          }
          pkg = hit.first.packageName;
          final ok = await device.openApp(pkg);
          return ok
              ? '已打开「${hit.first.label}」（$pkg）'
              : '找到「${hit.first.label}」但启动失败，可能受系统限制';
        }
        if (pkg.isEmpty) return '需要 name 或 package 参数';
        final ok = await device.openApp(pkg);
        return ok ? '已启动 $pkg' : '启动失败：未找到该应用或系统拒绝了启动';

      case 'agent.share.text':
        final ok = await device.shareText(_arg(a, 'text'));
        return ok ? '已调起系统分享面板' : '分享失败（系统没有可用的分享目标）';

      case 'agent.clipboard.set':
        final text = _arg(a, 'text');
        try {
          await Clipboard.setData(ClipboardData(text: text));
          return '已复制 ${text.length} 字到剪贴板';
        } catch (_) {
          final ok = await device.setClipboard(text);
          return ok ? '已复制到剪贴板' : '写入剪贴板失败';
        }

      case 'agent.toast':
        final ok = await device.toast(_arg(a, 'text'));
        return ok ? '已显示提示' : '提示显示失败';

      case 'agent.calendar.add':
        return _calendar(a);

      case 'agent.alarm.set':
        final h = _int(a, 'hour', -1);
        final m = _int(a, 'minute', 0);
        if (h < 0 || h > 23 || m < 0 || m > 59) {
          return '时间不合法：hour 需 0-23，minute 需 0-59';
        }
        final ok = await device.setAlarm(
            hour: h, minute: m, label: _arg(a, 'label', 'Aigent'));
        return ok
            ? '已打开系统时钟的「设置闹钟」页（$h:$m），需你点保存才会生效'
            : '未能调起系统时钟，请确认手机已安装时钟应用';

      default:
        return '工具尚未实现：${t.id}';
    }
  }

  Future<String> _calendar(Map<String, dynamic> a) async {
    final title = _arg(a, 'title');
    if (title.isEmpty) return '缺少 title 参数';
    final raw = _arg(a, 'start');
    DateTime start;
    if (raw.isEmpty) {
      start = DateTime.now().add(const Duration(hours: 1));
    } else if (RegExp(r'^\+?\d+$').hasMatch(raw)) {
      start = DateTime.now()
          .add(Duration(minutes: int.tryParse(raw.replaceFirst('+', '')) ?? 60));
    } else {
      start = DateTime.tryParse(raw) ??
          DateTime.now().add(const Duration(hours: 1));
    }
    final minutes = _int(a, 'minutes', 60).clamp(1, 24 * 60);
    final end = start.add(Duration(minutes: minutes));
    final ok = await device.addCalendar(
      title: title,
      startMillis: start.millisecondsSinceEpoch,
      endMillis: end.millisecondsSinceEpoch,
      description: _arg(a, 'description'),
      location: _arg(a, 'location'),
    );
    return ok
        ? '已打开系统日历「新建事件」页：$title（${start.toString().substring(0, 16)}，'
            '$minutes 分钟），需你点保存才会写入日历'
        : '未能调起系统日历，请确认手机已安装日历应用';
  }

  /// 抓取公开网页正文。显式拦掉内网 / 回环 / 元数据地址，避免模型被诱导
  /// 去探测局域网或云元数据服务（SSRF）。
  Future<String> _fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
      return '只接受 http / https 网址';
    }
    final host = uri.host.toLowerCase();
    if (isBlockedHost(host)) {
      return '出于安全考虑，禁止抓取本机 / 内网 / 元数据地址：$host';
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      maxRedirects: 3,
      responseType: ResponseType.plain,
      headers: {'User-Agent': 'Mozilla/5.0 (Aigent/4.7; Android)'},
    ));
    final resp = await dio.get<String>(url);
    final body = resp.data ?? '';
    if (body.length > 200000) {
      return '网页过大（${body.length} 字符），已放弃读取。可用 agent.web.open 在浏览器里查看。';
    }
    final text = _htmlToText(body);
    final clipped = text.length > 12000 ? '${text.substring(0, 12000)}\n…（已截断）' : text;
    return '网页 $url 的正文（${text.length} 字）：\n$clipped';
  }

  /// 内网 / 回环 / 云元数据主机黑名单（公开以便回归测试）。
  static bool isBlockedHost(String h) {
    if (h.isEmpty || h == 'localhost' || h.endsWith('.local') || h == '::1') {
      return true;
    }
    if (h.contains('metadata') || h == '169.254.169.254') return true;
    final v4 = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(h);
    if (v4 != null) {
      final a = int.parse(v4.group(1)!);
      final b = int.parse(v4.group(2)!);
      if (a == 127 || a == 10 || a == 0 || (a == 169 && b == 254)) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 100 && b >= 64 && b <= 127) return true;
    }
    return false;
  }

  static String _htmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>|</h[1-6]>',
            caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'&#(\d+);'), '');
    s = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    return s.trim();
  }
}

/// 把模型输出里可能夹带的工具 JSON 清掉，避免最终答案里残留一行生硬的结构。
String stripAgentToolJson(String text) {
  final t = text.trim();
  final call = parseAgentToolCall(t);
  if (call == null) return text;
  return t
      .replaceAll(RegExp(r'\{[^{}]*"tool"\s*:\s*"agent\.[^{}]*\}'), '')
      .replaceAll(RegExp(r'```(?:tool|json)?\s*[\s\S]*?```', caseSensitive: false), '')
      .trim();
}
