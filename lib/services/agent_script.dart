import 'agent_workspace.dart';

/// 受限任务脚本解释器 —— 对应需求里的「可以在手机上运行代码之类的」。
///
/// 必须说清边界：Android 应用沙箱里**不允许执行任意系统命令或原生二进制**，
/// 也不会内置一个通用语言运行时（那既不可控也极易被滥用）。因此这里提供的是
/// 一组白名单指令组成的**任务脚本**：能写文档、批量整理文本、串起一串可复现
/// 的动作，但每条指令都只能落在 [AgentWorkspace] 沙箱内，且每一步都有输出、
/// 有备份、可回滚。模型生成脚本 → 用户看得见 → 授权后执行 → 结果回灌。
///
/// 语法（每行一条，`#` 为注释，路径可用双引号包裹）：
/// ```
/// print 开始整理
/// write notes/plan.md <<<
/// # 计划
/// 第一行
/// >>>
/// append notes/plan.md 追加一行
/// read notes/plan.md
/// list notes
/// mkdir drafts
/// rename notes/plan.md notes/final.md
/// delete drafts/old.txt
/// ```
/// 支持 `${date}` `${time}` `${model}` `${brand}` 内置变量。
class ScriptResult {
  final bool ok;
  final List<String> lines;
  final int steps;
  final String? error;

  const ScriptResult({
    required this.ok,
    required this.lines,
    required this.steps,
    this.error,
  });

  String get output => lines.join('\n');
}

class AgentScriptRunner {
  AgentScriptRunner(this.workspace);

  final AgentWorkspace workspace;

  static const int maxSourceLines = 200;
  static const int maxSteps = 60;
  static const int maxOutputChars = 20000;

  static const Set<String> _commands = {
    'print',
    'write',
    'append',
    'read',
    'list',
    'mkdir',
    'delete',
    'rename',
  };

  Future<ScriptResult> run(
    String source, {
    Map<String, String> vars = const {},
    String deviceModel = '',
    String deviceBrand = '',
  }) async {
    final now = DateTime.now();
    final allVars = <String, String>{
      'date': '${now.year}-${_p(now.month)}-${_p(now.day)}',
      'time': '${_p(now.hour)}:${_p(now.minute)}',
      'model': deviceModel,
      'brand': deviceBrand,
      ...vars,
    };
    final out = <String>[];
    var steps = 0;
    final rawLines = source.replaceAll('\r\n', '\n').split('\n');
    if (rawLines.length > maxSourceLines) {
      return ScriptResult(
        ok: false,
        lines: out,
        steps: 0,
        error: '脚本超过 $maxSourceLines 行上限，已拒绝执行',
      );
    }

    try {
      // 先把 <<< ... >>> 多行块抽出来，用占位符替换，便于按行解析。
      final blocks = <String>[];
      final flat = source.replaceAll('\r\n', '\n').replaceAllMapped(
            RegExp(r'<<<\s*\n?([\s\S]*?)\n?\s*>>>'),
            (m) {
              blocks.add(m.group(1) ?? '');
              return '\u0000B${blocks.length - 1}\u0000';
            },
          );

      for (final raw in flat.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (++steps > maxSteps) {
          throw const WorkspaceException('指令数超过上限，已停止执行');
        }
        final tokens = _tokenize(line);
        if (tokens.isEmpty) continue;
        final cmd = tokens.first.toLowerCase();
        if (!_commands.contains(cmd)) {
          throw WorkspaceException(
              '未知指令「$cmd」，只允许：${_commands.join(' / ')}');
        }
        final args = tokens.sublist(1).map((t) {
          final bm = RegExp(r'^\u0000B(\d+)\u0000$').firstMatch(t);
          final v = bm != null ? blocks[int.parse(bm.group(1)!)] : t;
          return _interpolate(v, allVars);
        }).toList();

        switch (cmd) {
          case 'print':
            out.add(args.join(' '));
            break;
          case 'write':
            _need(args, 2, 'write <路径> <内容>');
            out.add('· ${await workspace.write(args[0], args.sublist(1).join(' '))}');
            break;
          case 'append':
            _need(args, 2, 'append <路径> <内容>');
            out.add('· ${await workspace.append(args[0], args.sublist(1).join(' '))}');
            break;
          case 'read':
            _need(args, 1, 'read <路径>');
            final text = await workspace.read(args[0]);
            out.add('· ${args[0]}（${text.length} 字）:\n$text');
            break;
          case 'list':
            final entries = await workspace.list(args.isEmpty ? '' : args[0]);
            out.add(entries.isEmpty
                ? '· 工作区为空'
                : '· 共 ${entries.length} 项：\n${entries.map((e) => '  ${e.isDir ? "📁" : "·"} ${e.rel}  ${e.sizeLabel}').join('\n')}');
            break;
          case 'mkdir':
            _need(args, 1, 'mkdir <目录>');
            out.add('· ${await workspace.mkdir(args[0])}');
            break;
          case 'delete':
            _need(args, 1, 'delete <路径>');
            out.add('· ${await workspace.delete(args[0])}');
            break;
          case 'rename':
            _need(args, 2, 'rename <旧路径> <新路径>');
            out.add('· ${await workspace.rename(args[0], args[1])}');
            break;
        }
        if (out.join('\n').length > maxOutputChars) {
          throw const WorkspaceException('脚本输出过长，已停止执行');
        }
      }
      return ScriptResult(ok: true, lines: out, steps: steps);
    } on WorkspaceException catch (e) {
      out.add('× ${e.message}');
      return ScriptResult(ok: false, lines: out, steps: steps, error: e.message);
    } catch (e) {
      out.add('× 执行出错：$e');
      return ScriptResult(ok: false, lines: out, steps: steps, error: '$e');
    }
  }

  void _need(List<String> args, int n, String usage) {
    if (args.length < n) throw WorkspaceException('参数不足，用法：$usage');
  }

  String _interpolate(String s, Map<String, String> vars) => s.replaceAllMapped(
        RegExp(r'\$\{(\w+)\}'),
        (m) => vars[m.group(1)] ?? m.group(0)!,
      );

  /// 按空格切词，支持双引号包裹含空格的路径。占位符本身不含空格，能安全穿过。
  List<String> _tokenize(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        quoted = !quoted;
      } else if (!quoted && c == ' ') {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(c);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  /// 注入 System Prompt 的脚本语法说明。
  static String get syntaxPrompt => '''
[任务脚本] 用 workspace.run 时可以提交一段受限脚本，语法如下（每行一条，# 为注释）：
print <文本> / write <路径> <文本> / append <路径> <文本> / read <路径>
list [目录] / mkdir <目录> / delete <路径> / rename <旧> <新>
多行内容用 <<< 开头、单独一行 >>> 结尾包裹。可用 \${date} \${time} \${model} \${brand} 变量。
脚本只能访问隔离工作区，最多 $maxSourceLines 行 / $maxSteps 条指令；覆盖写会自动备份旧版、删除进入回收站，不会真正丢失文件。''';
}
