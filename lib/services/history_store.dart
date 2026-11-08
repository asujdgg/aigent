import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// 一次落盘的完整快照：会话 + 当前会话 + 用量统计。
///
/// 以前这三样只在内存里，杀掉进程就全没了；现在统一写进应用私有目录的
/// 一个 JSON 文件，冷启动时原样读回来。
class HistorySnapshot {
  final List<Conversation> conversations;
  final String activeId;
  final Map<String, dynamic>? usage;

  const HistorySnapshot({
    required this.conversations,
    required this.activeId,
    this.usage,
  });
}

/// 会话历史的本地存储。
///
/// 用文件而不是 SharedPreferences：一条带图片的消息可能几百 KB，
/// SharedPreferences 是整份 XML 读写的，塞进去会让启动和保存都变慢。
/// 写入走「临时文件 + rename」，避免写一半被杀进程留下半个 JSON。
class HistoryStore {
  /// 测试可注入临时目录；生产走 path_provider。
  final Future<Directory> Function()? dirProvider;

  HistoryStore({this.dirProvider});

  static const String fileName = 'aigent_history.json';

  /// 会话数上限：再多也没人翻，留着只会拖慢启动。
  static const int maxConversations = 80;

  /// 单会话消息上限。
  static const int maxMessages = 400;

  /// 单张图片进历史的体积上限；超过只留文件名，不存字节。
  static const int maxImageBytes = 1200 * 1024;

  Future<File> _file() async {
    final d = dirProvider != null
        ? await dirProvider!()
        : await getApplicationSupportDirectory();
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$fileName');
  }

  Future<HistorySnapshot?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final list = map['conversations'];
      final convs = <Conversation>[];
      if (list is List) {
        for (final e in list.whereType<Map>()) {
          final c = Conversation.fromJson(Map<dynamic, dynamic>.from(e));
          if (c.id.isEmpty) continue;
          // 恢复出来的一定不是「生成中」：上次的流早就断了。
          for (final m in c.messages) {
            m.streaming = false;
          }
          c.generating = false;
          c.status = '';
          convs.add(c);
        }
      }
      final usage = map['usage'];
      return HistorySnapshot(
        conversations: convs,
        activeId: (map['activeId'] ?? '').toString(),
        usage: usage is Map ? Map<String, dynamic>.from(usage) : null,
      );
    } catch (_) {
      // 文件损坏不该让应用起不来：挪到一边，下次从空历史开始。
      try {
        final f = await _file();
        if (await f.exists()) {
          await f.rename('${f.path}.bad');
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> save(HistorySnapshot snapshot) async {
    try {
      final convs = _prepare(snapshot.conversations);
      final payload = <String, dynamic>{
        'v': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'activeId': snapshot.activeId,
        'conversations': [for (final c in convs) c.toJson()],
        if (snapshot.usage != null) 'usage': snapshot.usage,
      };
      final text = jsonEncode(payload);
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // 存储满 / 权限异常：不影响当前会话继续用，只是这次没存上。
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 落盘前裁剪：旧会话整条丢弃，超长会话保留最近的消息，
  /// 超大图片只留文件名——宁可少存一张图，也不能让文件无限膨胀。
  ///
  /// 全程只动副本：内存里的会话和消息不能因为「存了一次盘」就被截断。
  List<Conversation> _prepare(List<Conversation> all) {
    final sorted = List<Conversation>.of(all)
      ..sort((a, b) => b.at.compareTo(a.at));
    final keep = sorted.take(maxConversations).toList();
    final out = <Conversation>[];
    for (final c in keep) {
      final msgs = c.messages.length > maxMessages
          ? c.messages.sublist(c.messages.length - maxMessages)
          : c.messages;
      final cloned = <ChatMessage>[];
      for (final m in msgs) {
        final copy = _cloneMessage(m);
        copy.attachments = [
          for (final a in m.attachments)
            (a.imageBytes != null && a.imageBytes!.length > maxImageBytes)
                ? Attachment(
                    id: a.id,
                    name: a.name,
                    kind: a.kind,
                    size: a.size,
                    text: a.text,
                    imageMime: a.imageMime,
                  )
                : a,
        ];
        cloned.add(copy);
      }
      out.add(Conversation(
        id: c.id,
        title: c.title,
        at: c.at,
        messages: cloned,
      )..personaId = c.personaId);
    }
    return out;
  }

  ChatMessage _cloneMessage(ChatMessage m) {
    final c = ChatMessage(
      id: m.id,
      role: m.role,
      content: m.content,
      at: m.at,
      attachments: List<Attachment>.of(m.attachments),
      citations: List<Citation>.of(m.citations),
    );
    c.thinking = m.thinking;
    c.model = m.model;
    c.tierLabel = m.tierLabel;
    c.error = m.error;
    c.searchQuery = m.searchQuery;
    c.elapsedMs = m.elapsedMs;
    c.usage = m.usage;
    c.toolName = m.toolName;
    c.toolOk = m.toolOk;
    c.toolStep = m.toolStep;
    c.toolMs = m.toolMs;
    return c;
  }
}
