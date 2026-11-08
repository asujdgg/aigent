import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_bridge.dart';

/// 智能体的**独立工作目录**。
///
/// 这是整个「真干活」能力的物理边界：
///  - 根目录固定在应用专属目录 `aigent_workspace/`，卸载即清理，
///    绝不指向相册、Download、SD 卡根目录或任何用户已有文件夹；
///  - 所有相对路径都经过 [_safe] 校验：拒绝绝对路径、`..`、盘符、
///    隐藏文件与符号链接逃逸，任何越界尝试直接抛错，不做「尽力而为」；
///  - 覆盖写之前先把旧版本备份到 `.trash/`，删除不是真删而是移入
///    回收站，随时可恢复 —— 用户最担心的「文件丢失 / 损坏」在结构上
///    就不可能发生；
///  - 单文件与总数量都有上限，避免模型一轮循环把存储写满；
///  - 每次动作都追加一条审计日志，设置页可查、可回溯。
class WorkspaceException implements Exception {
  final String message;
  const WorkspaceException(this.message);
  @override
  String toString() => message;
}

class WorkspaceEntry {
  final String rel;
  final String name;
  final bool isDir;
  final int size;
  final int modifiedMs;

  const WorkspaceEntry({
    required this.rel,
    required this.name,
    required this.isDir,
    required this.size,
    required this.modifiedMs,
  });

  String get sizeLabel {
    if (isDir) return '文件夹';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1048576).toStringAsFixed(1)} MB';
  }
}

class AgentLogEntry {
  final int at;
  final String tool;
  final String detail;
  final bool ok;

  const AgentLogEntry({
    required this.at,
    required this.tool,
    required this.detail,
    this.ok = true,
  });

  Map<String, dynamic> toJson() => {
        'at': at,
        'tool': tool,
        'detail': detail,
        'ok': ok,
      };

  factory AgentLogEntry.fromJson(Map<dynamic, dynamic> j) => AgentLogEntry(
        at: (j['at'] as num?)?.toInt() ?? 0,
        tool: (j['tool'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        ok: j['ok'] != false,
      );
}

class AgentWorkspace {
  AgentWorkspace(this.root);

  /// 工作区根目录（绝对路径）。
  final String root;

  /// 单文件上限 2 MB；总文件数上限 300；日志保留 500 条。
  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int maxFiles = 300;
  static const int maxLogLines = 500;

  static const String trashDirName = '.trash';
  static const String logFileName = 'agent_log.jsonl';

  Directory get _rootDir => Directory(root);
  String get trashPath => p.join(root, trashDirName);
  String get logPath => p.join(root, logFileName);

  /// 打开（或创建）真机上的工作区。原生通道拿不到路径时逐级降级，
  /// 保证单元测试 / 桌面环境也有一个可用目录。
  static Future<AgentWorkspace> open({DeviceBridge? bridge}) async {
    String? path;
    try {
      path = await (bridge ?? DeviceBridge()).workspaceRoot();
    } catch (_) {}
    if (path == null || path.isEmpty) {
      try {
        path = (await getExternalStorageDirectory())?.path;
      } catch (_) {}
    }
    if (path == null || path.isEmpty) {
      try {
        path = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {}
    }
    path ??= p.join(Directory.systemTemp.path, 'aigent_workspace');
    final ws = AgentWorkspace(p.join(path, 'aigent_workspace'));
    await ws.ensure();
    return ws;
  }

  Future<void> ensure() async {
    if (!_rootDir.existsSync()) {
      await _rootDir.create(recursive: true);
    }
    final trash = Directory(trashPath);
    if (!trash.existsSync()) await trash.create(recursive: true);
  }

  /// 把相对路径解析成绝对路径，并做全部安全校验。
  /// 传入空字符串表示根目录本身，仅允许 [list] 使用。
  String _safe(String rel, {bool allowRoot = false}) {
    final t = rel.trim().replaceAll('\\', '/');
    if (t.isEmpty) {
      if (allowRoot) return root;
      throw const WorkspaceException('路径不能为空');
    }
    if (p.isAbsolute(t) || t.startsWith('/') || t.startsWith('\\')) {
      throw const WorkspaceException('只允许工作区内的相对路径，不接受绝对路径');
    }
    if (RegExp(r'^[A-Za-z]:').hasMatch(t)) {
      throw const WorkspaceException('不接受盘符路径');
    }
    final parts = p.posix.split(t);
    if (parts.any((e) => e == '..')) {
      throw const WorkspaceException('路径不能包含 ..（禁止跳出工作区）');
    }
    if (parts.any((e) => e.startsWith('.') && e != '.')) {
      throw const WorkspaceException('不允许访问隐藏文件或系统保留目录');
    }
    if (parts.contains(trashDirName) || parts.contains(logFileName)) {
      throw const WorkspaceException('该路径由系统保留，不可直接操作');
    }
    final target = p.normalize(p.join(root, t));
    if (!p.isWithin(root, target)) {
      throw const WorkspaceException('路径越出了工作区');
    }
    return target;
  }

  /// 符号链接逃逸检查：真实路径必须仍在根目录内。
  void _assertNoEscape(String target) {
    final rootReal = _rootDir.resolveSymbolicLinksSync();
    bool inside(String real) => real == rootReal || p.isWithin(rootReal, real);
    final parent = Directory(p.dirname(target));
    if (parent.existsSync() && !inside(parent.resolveSymbolicLinksSync())) {
      throw const WorkspaceException('目录链接指向了工作区之外');
    }
    final f = File(target);
    if (f.existsSync() && !inside(f.resolveSymbolicLinksSync())) {
      throw const WorkspaceException('文件链接指向了工作区之外');
    }
    final d = Directory(target);
    if (d.existsSync() && !inside(d.resolveSymbolicLinksSync())) {
      throw const WorkspaceException('目录链接指向了工作区之外');
    }
  }

  String _rel(String abs) => p.relative(abs, from: root).replaceAll('\\', '/');

  bool _isReserved(FileSystemEntity e) =>
      p.basename(e.path) == trashDirName ||
      p.basename(e.path) == logFileName ||
      p.basename(e.path).startsWith('.');

  int _seq = 0;

  /// 把「相对路径」编码进回收站条目名（/ → __），恢复时才能回到原子目录。
  /// 微秒时间戳 + 自增序号：同一毫秒里连续覆盖 / 删除也不会重名或排序颠倒。
  String _trashName(String relName) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    _seq++;
    final safe = relName
        .replaceAll('/', '__')
        .replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]'), '_');
    return '${ts}_${_seq}_$safe';
  }

  Future<void> _checkQuota({required int incomingBytes}) async {
    if (incomingBytes > maxFileBytes) {
      throw WorkspaceException(
          '内容超过单文件上限 ${(maxFileBytes / 1048576).toStringAsFixed(0)} MB，已拒绝写入');
    }
    var count = 0;
    await for (final e in _rootDir.list(recursive: true, followLinks: false)) {
      if (e is File &&
          !_isReserved(e) &&
          !p.isWithin(trashPath, e.path)) {
        count++;
      }
    }
    if (count >= maxFiles) {
      throw const WorkspaceException('工作区文件数已达上限 $maxFiles，请先清理');
    }
  }

  /// 覆盖前备份旧内容；返回备份文件名（无旧文件则返回空串）。
  Future<String> _backup(File f) async {
    if (!f.existsSync()) return '';
    final name = _trashName('${_rel(f.path)}.bak');
    final dest = p.join(trashPath, name);
    await f.copy(dest);
    return name;
  }

  Future<List<WorkspaceEntry>> list([String rel = '']) async {
    await ensure();
    final dir = Directory(_safe(rel, allowRoot: true));
    if (!dir.existsSync()) {
      throw const WorkspaceException('文件夹不存在');
    }
    final out = <WorkspaceEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      if (_isReserved(e)) continue;
      final stat = e.statSync();
      out.add(WorkspaceEntry(
        rel: _rel(e.path),
        name: p.basename(e.path),
        isDir: stat.type == FileSystemEntityType.directory,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      ));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<String> read(String rel) async {
    await ensure();
    final path = _safe(rel);
    _assertNoEscape(path);
    final f = File(path);
    if (!f.existsSync()) throw const WorkspaceException('文件不存在');
    if (f.lengthSync() > maxFileBytes) {
      throw const WorkspaceException('文件超过 2 MB，拒绝一次性读入上下文');
    }
    return f.readAsStringSync();
  }

  /// 写文件。默认允许覆盖，但覆盖前会先把旧版本存入回收站。
  Future<String> write(String rel, String content) async {
    await ensure();
    final path = _safe(rel);
    _assertNoEscape(path);
    final bytes = utf8.encode(content).length;
    if (!File(path).existsSync()) await _checkQuota(incomingBytes: bytes);
    if (bytes > maxFileBytes) {
      throw WorkspaceException(
          '内容超过单文件上限 ${(maxFileBytes / 1048576).toStringAsFixed(0)} MB');
    }
    final parent = Directory(p.dirname(path));
    if (!parent.existsSync()) await parent.create(recursive: true);
    final f = File(path);
    final backup = await _backup(f);
    await f.writeAsString(content, flush: true);
    final tail = backup.isEmpty ? '' : '（旧版已备份为 $backup）';
    return '已写入 ${_rel(path)}，${_human(bytes)}$tail';
  }

  Future<String> append(String rel, String content) async {
    await ensure();
    final path = _safe(rel);
    _assertNoEscape(path);
    final f = File(path);
    final old = f.existsSync() ? await f.readAsString() : '';
    final next = old + content;
    final bytes = utf8.encode(next).length;
    if (!f.existsSync()) await _checkQuota(incomingBytes: bytes);
    if (bytes > maxFileBytes) {
      throw const WorkspaceException('追加后超过单文件 2 MB 上限，已放弃');
    }
    final parent = Directory(p.dirname(path));
    if (!parent.existsSync()) await parent.create(recursive: true);
    final backup = await _backup(f);
    await f.writeAsString(next, flush: true);
    final tail = backup.isEmpty ? '' : '（追加前版本已备份为 $backup）';
    return '已追加到 ${_rel(path)}，现共 ${_human(bytes)}$tail';
  }

  Future<String> mkdir(String rel) async {
    await ensure();
    final path = _safe(rel);
    _assertNoEscape(path);
    final d = Directory(path);
    if (d.existsSync()) return '文件夹 ${_rel(path)} 已存在';
    await d.create(recursive: true);
    return '已新建文件夹 ${_rel(path)}';
  }

  /// 删除 = 移入回收站，永不真删。
  Future<String> delete(String rel) async {
    await ensure();
    final path = _safe(rel);
    _assertNoEscape(path);
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.notFound) {
      throw const WorkspaceException('要删除的文件不存在');
    }
    final dest = p.join(trashPath, _trashName(_rel(path)));
    if (entity == FileSystemEntityType.directory) {
      await Directory(path).rename(dest);
    } else {
      await File(path).rename(dest);
    }
    return '已把 ${_rel(path)} 移入回收站（未真正删除，可在设置页恢复）';
  }

  Future<String> rename(String from, String to) async {
    await ensure();
    final src = _safe(from);
    final dst = _safe(to);
    _assertNoEscape(src);
    _assertNoEscape(dst);
    if (FileSystemEntity.typeSync(src) == FileSystemEntityType.notFound) {
      throw const WorkspaceException('源文件不存在');
    }
    if (File(dst).existsSync() || Directory(dst).existsSync()) {
      throw const WorkspaceException('目标文件已存在，请先删除或换名');
    }
    final parent = Directory(p.dirname(dst));
    if (!parent.existsSync()) await parent.create(recursive: true);
    if (Directory(src).existsSync()) {
      await Directory(src).rename(dst);
    } else {
      await File(src).rename(dst);
    }
    return '已把 ${_rel(src)} 重命名为 ${_rel(dst)}';
  }

  Future<List<WorkspaceEntry>> trashList() async {
    await ensure();
    final dir = Directory(trashPath);
    final out = <WorkspaceEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      final stat = e.statSync();
      out.add(WorkspaceEntry(
        rel: p.basename(e.path),
        name: p.basename(e.path),
        isDir: stat.type == FileSystemEntityType.directory,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      ));
    }
    // 按条目名（时间戳前缀）倒序：文件系统 mtime 在同一毫秒内会并列，
    // 「恢复最近一条」必须稳定指向最后一次操作，而不是随机挑一个。
    out.sort((a, b) => b.rel.compareTo(a.rel));
    return out;
  }

  Future<String> restore(String trashName) async {
    await ensure();
    if (trashName.contains('/') ||
        trashName.contains('\\') ||
        trashName.startsWith('..')) {
      throw const WorkspaceException('回收站条目名不合法');
    }
    final src = p.join(trashPath, trashName);
    if (!File(src).existsSync() && !Directory(src).existsSync()) {
      throw const WorkspaceException('回收站里没有这个条目');
    }
    // 去掉「微秒_序号_」前缀与 .bak 后缀，再把 __ 还原成 /，回到原子目录。
    // 同时兼容旧格式的「毫秒_」前缀。
    var name = trashName.replaceFirst(RegExp(r'^\d+_(?:\d+_)?'), '');
    if (name.endsWith('.bak')) name = name.substring(0, name.length - 4);
    name = name.replaceAll('__', '/');
    if (name.isEmpty) name = 'restored.txt';
    var dest = _safe(name);
    var i = 1;
    while (File(dest).existsSync() || Directory(dest).existsSync()) {
      final ext = p.extension(name);
      final stem = name.substring(0, name.length - ext.length);
      dest = _safe('${stem}_$i$ext');
      i++;
    }
    final parent = Directory(p.dirname(dest));
    if (!parent.existsSync()) await parent.create(recursive: true);
    if (Directory(src).existsSync()) {
      await Directory(src).rename(dest);
    } else {
      await File(src).rename(dest);
    }
    return '已恢复为 ${_rel(dest)}';
  }

  Future<String> clearTrash() async {
    await ensure();
    final dir = Directory(trashPath);
    var n = 0;
    await for (final e in dir.list(followLinks: false)) {
      await e.delete(recursive: true);
      n++;
    }
    return '已永久清空回收站的 $n 个条目（此操作不可撤销）';
  }

  Future<({int files, int bytes, int trashFiles})> usage() async {
    await ensure();
    var files = 0;
    var bytes = 0;
    var trash = 0;
    await for (final e in _rootDir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      if (p.isWithin(trashPath, e.path)) {
        trash++;
      } else if (!_isReserved(e)) {
        files++;
        bytes += e.statSync().size;
      }
    }
    return (files: files, bytes: bytes, trashFiles: trash);
  }

  Future<void> log(AgentLogEntry e) async {
    await ensure();
    final f = File(logPath);
    final line = jsonEncode(e.toJson());
    if (!f.existsSync()) {
      await f.writeAsString('$line\n', flush: true);
      return;
    }
    final lines = await f.readAsLines();
    lines.add(line);
    final trimmed = lines.length > maxLogLines
        ? lines.sublist(lines.length - (maxLogLines * 4 ~/ 5))
        : lines;
    final tmp = File('$logPath.tmp');
    await tmp.writeAsString('${trimmed.join('\n')}\n', flush: true);
    await tmp.rename(logPath);
  }

  Future<List<AgentLogEntry>> readLog({int limit = 80}) async {
    await ensure();
    final f = File(logPath);
    if (!f.existsSync()) return const <AgentLogEntry>[];
    final lines = await f.readAsLines();
    final start = lines.length > limit ? lines.length - limit : 0;
    final out = <AgentLogEntry>[];
    for (final l in lines.sublist(start)) {
      if (l.trim().isEmpty) continue;
      try {
        out.add(AgentLogEntry.fromJson(
            jsonDecode(l) as Map<dynamic, dynamic>));
      } catch (_) {}
    }
    return out.reversed.toList();
  }

  String _human(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}
