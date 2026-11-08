import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/history_store.dart';
import 'package:ai_agent_app/state/app_state.dart';

void main() {
  group('会话历史与用量落盘', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('aigent_hist');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    HistoryStore storeIn(Directory d) =>
        HistoryStore(dirProvider: () async => d);

    test('会话、思考、引用、用量完整往返', () async {
      final store = storeIn(dir);
      final c = Conversation(id: 'c1', title: '旧对话');
      c.messages.add(ChatMessage(
        id: 'm1',
        role: Role.user,
        content: '你好',
        attachments: [
          const Attachment(
            id: 'a1',
            name: 'note.txt',
            kind: AttachKind.text,
            size: 4,
            text: 'abc',
          ),
        ],
      ));
      final a = ChatMessage(id: 'm2', role: Role.assistant, content: '在')
        ..thinking = (ThinkingTrace()..append('先想一下'))
        ..usage = const TokenUsage(prompt: 10, completion: 5)
        ..model = 'gpt-4o'
        ..citations = [
          const Citation(index: 1, title: '来源', url: 'https://a.b')
        ];
      c.messages.add(a);

      final usage = TokenStats()
        ..add(const TokenUsage(prompt: 10, completion: 5), model: 'gpt-4o');
      await store.save(HistorySnapshot(
        conversations: [c],
        activeId: 'c1',
        usage: usage.toJson(),
      ));

      final back = await store.load();
      expect(back, isNotNull);
      expect(back!.activeId, 'c1');
      final conv = back.conversations.single;
      expect(conv.title, '旧对话');
      expect(conv.messages.length, 2);
      expect(conv.messages.first.attachments.single.text, 'abc');
      expect(conv.messages.last.thinking!.raw, '先想一下');
      expect(conv.messages.last.usage!.total, 15);
      expect(conv.messages.last.citations.single.host, 'a.b');
      expect(conv.messages.last.streaming, isFalse);

      final t = TokenStats.fromJson(back.usage!);
      expect(t.total, 15);
      expect(t.todayTotal, 15);
      expect(t.byModel['gpt-4o']!.total, 15);
      expect(t.byDay.length, 1, reason: '当天建了一个日桶');
    });

    test('重启后恢复会话，而不是每次只剩一个空工作台', () async {
      final st = AppState()..settings = AppSettings();
      st.historyStore = storeIn(dir);
      final c = Conversation(id: 'c9', title: '保留我');
      c.messages.add(ChatMessage(id: 'x', role: Role.user, content: '记住这句'));
      st.conversations = [c];
      st.activeId = 'c9';
      st.tokenStats.add(const TokenUsage(prompt: 3, completion: 4), model: 'm1');
      await st.flushHistory();

      final st2 = AppState()..settings = AppSettings();
      st2.historyStore = storeIn(dir);
      await st2.restoreHistory();

      expect(st2.conversations.length, 1);
      expect(st2.activeId, 'c9');
      expect(st2.active.title, '保留我');
      expect(st2.active.messages.single.content, '记住这句');
      expect(st2.tokenStats.total, 7);
    });

    test('生成中的标记不会带进历史', () async {
      final store = storeIn(dir);
      final c = Conversation(id: 'c1', title: 'T');
      c.generating = true;
      c.status = '生成中…';
      c.messages.add(ChatMessage(
        id: 'm1',
        role: Role.assistant,
        content: '半截',
        streaming: true,
      ));
      await store.save(HistorySnapshot(conversations: [c], activeId: 'c1'));
      final back = await store.load();
      expect(back!.conversations.single.generating, isFalse);
      expect(back.conversations.single.status, isEmpty);
      expect(back.conversations.single.messages.single.streaming, isFalse);
    });

    test('超大图片只留文件名，文件不会被撑爆', () async {
      final store = storeIn(dir);
      final big = Uint8List(HistoryStore.maxImageBytes + 1024);
      final c = Conversation(id: 'c1', title: 'T');
      c.messages.add(ChatMessage(
        id: 'm1',
        role: Role.user,
        content: '看图',
        attachments: [
          Attachment(
            id: 'img',
            name: 'big.jpg',
            kind: AttachKind.image,
            size: big.length,
            imageBytes: big,
          ),
        ],
      ));
      await store.save(HistorySnapshot(conversations: [c], activeId: 'c1'));
      final back = await store.load();
      final att = back!.conversations.single.messages.single.attachments.single;
      expect(att.name, 'big.jpg');
      expect(att.imageBytes, isNull);
      // 内存里的原对象不能被落盘裁剪影响。
      expect(c.messages.single.attachments.single.imageBytes, isNotNull);
    });

    test('文件损坏时不崩，按空历史处理', () async {
      final f = File('${dir.path}/${HistoryStore.fileName}');
      await f.writeAsString('{这不是 json');
      final back = await storeIn(dir).load();
      expect(back, isNull);
      expect(await f.exists(), isFalse, reason: '坏文件被挪走');
    });
  });

  group('按天按模型统计', () {
    test('同一天累加，不同模型分开记', () {
      final s = TokenStats();
      s.add(const TokenUsage(prompt: 100, completion: 20), model: 'a');
      s.add(const TokenUsage(prompt: 50, completion: 10), model: 'b');
      s.add(const TokenUsage(prompt: 10, completion: 5), model: 'a');

      expect(s.total, 195);
      expect(s.requests, 3);
      expect(s.byModel['a']!.total, 135);
      expect(s.byModel['b']!.total, 60);
      expect(s.days.length, 1);
      expect(s.today.total, 195);
      expect(s.today.requests, 3);
    });

    test('序列化后按天数据仍在', () {
      final s = TokenStats()
        ..add(const TokenUsage(prompt: 100, completion: 20), model: 'a');
      final back = TokenStats.fromJson(s.toJson());
      expect(back.total, 120);
      expect(back.days, s.days);
      expect(back.today.total, 120);
      expect(back.byModel['a']!.total, 120);
    });

    test('清零会把按天与按模型一起清掉', () {
      final s = TokenStats()
        ..add(const TokenUsage(prompt: 1, completion: 1), model: 'a');
      s.reset();
      expect(s.total, 0);
      expect(s.byDay, isEmpty);
      expect(s.byModel, isEmpty);
      expect(s.todayTotal, 0);
    });
  });
}
