import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/services/llm_client.dart';
import 'package:ai_agent_app/services/roundtable.dart';

Seat _seat(String id, String model, {bool enabled = true}) => Seat(
      id: id,
      name: '席位$id',
      role: '立场$id',
      baseUrl: 'https://example.com/v1',
      apiKey: 'key-$id',
      model: model,
      enabled: enabled,
    );

void main() {
  group('议程解析', () {
    test('清洗编号、Markdown 标题与项目符号', () {
      const raw = '以下是大纲\n'
          '1. 问题界定\n'
          '2、关键事实\n'
          '- 分歧点\n'
          '## 风险与约束\n'
          '• 下一步\n'
          '这一行非常非常长，长到不应该被当成一条议程条目，'
          '所以必须被过滤掉，否则会议大纲会被一句废话占满整整一屏。';
      final out = parseAgenda(raw);
      expect(out, ['问题界定', '关键事实', '分歧点', '风险与约束', '下一步']);
    });

    test('去重且不超过上限', () {
      final out = parseAgenda(
          '条目一\n条目二\n条目一\n条目三\n条目四\n条目五', max: 3);
      expect(out, ['条目一', '条目二', '条目三']);
      expect(out.length, 3);
      expect(out.toSet().length, 3);
    });

    test('空文本返回空列表', () => expect(parseAgenda(''), isEmpty));
  });

  group('讨论上下文', () {
    test('没有发言时给出占位说明', () {
      expect(buildDiscussionContext([]), contains('尚无其他人发言'));
    });

    test('只取最近若干条并逐条截断', () {
      final turns = [
        for (var i = 0; i < 15; i++)
          MeetingTurn(
              seatId: 's$i',
              seatName: '席位$i',
              model: 'm',
              round: 1,
              content: '甲' * 500),
      ];
      final ctx = buildDiscussionContext(turns, limit: 3, perTurn: 20);
      expect(ctx, contains('席位14'));
      expect(ctx, isNot(contains('席位11')));
      expect(ctx.split('甲' * 21).length, 1);
    });

    test('失败的发言不进入上下文', () {
      final bad = MeetingTurn(
          seatId: 'x', seatName: '失败者', model: 'm', round: 1, error: 'boom');
      expect(buildDiscussionContext([bad]), contains('尚无其他人发言'));
    });
  });

  group('会议数据与纪要', () {
    test('JSON 往返不丢字段', () {
      final m = Meeting(
        id: 'm1',
        topic: '要不要做 X',
        agenda: '界定\n风险',
        seats: [_seat('a', 'gpt-a'), _seat('b', 'gpt-b')],
        rounds: 3,
      );
      m.turns.add(MeetingTurn(
          seatId: 'a', seatName: '席位a', model: 'gpt-a', round: 1, content: '支持'));
      m.summary = '结论：先做小规模验证';
      m.phase = MeetingPhase.done;
      final back = Meeting.fromJson(m.toJson());
      expect(back.topic, '要不要做 X');
      expect(back.rounds, 3);
      expect(back.seats.length, 2);
      expect(back.turns.single.content, '支持');
      expect(back.summary, contains('小规模验证'));
      expect(back.phase, MeetingPhase.done);
    });

    test('纪要含大纲、逐轮发言与结论', () {
      final m = Meeting(id: 'm', topic: '议题', agenda: '界定\n分歧');
      m.turns.addAll([
        MeetingTurn(
            seatId: 'a', seatName: '甲', model: 'model-a', round: 1, content: '甲观点'),
        MeetingTurn(
            seatId: 'b', seatName: '乙', model: 'model-b', round: 2, content: '乙观点'),
      ]);
      m.summary = '共识：都不反对';
      final md = m.toMarkdown();
      expect(md, contains('# 议题'));
      expect(md, contains('## 会议大纲'));
      expect(md, contains('### 第 1 轮'));
      expect(md, contains('### 第 2 轮'));
      expect(md, contains('**甲**（model-a）'));
      expect(md, contains('## 会议结论'));
    });

    test('停用的席位不计入参会者', () {
      final m = Meeting(id: 'm', seats: [
        _seat('a', 'm1'),
        _seat('b', 'm2', enabled: false),
      ]);
      expect(m.activeSeats.length, 1);
    });
  });

  group('默认席位', () {
    test('跨连接去重、最多 5 个且角色各不相同', () {
      final seats = defaultSeats(
        fallbackBaseUrl: 'https://a/v1',
        fallbackApiKey: 'ka',
        fallbackModel: 'model-1',
        candidates: [
          (baseUrl: 'https://a/v1', apiKey: 'ka', model: 'model-1'),
          (baseUrl: 'https://a/v1', apiKey: 'ka', model: 'model-2'),
          (baseUrl: 'https://b/v1', apiKey: 'kb', model: 'model-3'),
          (baseUrl: 'https://b/v1', apiKey: 'kb', model: 'model-4'),
          (baseUrl: 'https://c/v1', apiKey: 'kc', model: 'model-5'),
          (baseUrl: 'https://c/v1', apiKey: 'kc', model: 'model-6'),
          (baseUrl: 'https://c/v1', apiKey: 'kc', model: 'model-7'),
        ],
      );
      expect(seats.length, 5);
      expect(seats.map((s) => s.model).toSet().length, 5);
      expect(seats.map((s) => s.role).toSet().length, 5);
      expect(seats.last.apiKey, anyOf('ka', 'kb', 'kc'));
    });

    test('候选为空时仍能用当前模型开一场', () {
      final seats = defaultSeats(
        fallbackBaseUrl: 'https://a/v1',
        fallbackApiKey: 'k',
        fallbackModel: 'only-model',
        candidates: [],
      );
      expect(seats.length, 1);
      expect(seats.single.model, 'only-model');
    });
  });

  group('会议引擎', () {
    Meeting meeting({int seats = 3, int rounds = 2}) => Meeting(
          id: 'm',
          topic: '是否应该做 X',
          rounds: rounds,
          seats: [for (var i = 0; i < seats; i++) _seat('s$i', 'model-$i')],
        );

    CompleteFn responder({String Function(LlmRequest req)? onReq}) =>
        (LlmRequest req, {CancelToken? cancel}) async {
          if (onReq != null) return onReq(req);
          if (req.maxTokens == 600) return '问题界定\n关键事实\n风险';
          if (req.maxTokens == 1400) return '共识\n分歧\n建议';
          return '我的观点';
        };

    test('逐轮逐个发言，最后产出结论', () async {
      final m = meeting();
      var changes = 0;
      final engine = RoundtableEngine(
          complete: responder(), onChanged: () => changes++);
      await engine.run(m);
      expect(m.phase, MeetingPhase.done);
      expect(m.agenda.split('\n').length, 3);
      expect(m.turns.length, 6);
      expect(m.turns.where((t) => t.round == 1).length, 3);
      expect(m.turns.where((t) => t.round == 2).length, 3);
      expect(m.turns.every((t) => t.ok), isTrue);
      expect(m.summary, contains('共识'));
      expect(changes, greaterThan(5));
    });

    test('后发言者能看到前面席位的观点', () async {
      final seen = <String>[];
      final engine = RoundtableEngine(
        complete: (req, {cancel}) async {
          seen.add('${req.messages.last['content']}');
          if (req.maxTokens == 600) return '大纲';
          if (req.maxTokens == 1400) return '结论';
          return '观点 ${seen.length}';
        },
      );
      final m = meeting(seats: 2, rounds: 2);
      await engine.run(m);
      expect(seen.length, 1 + 4 + 1); // 大纲 + 4 次发言 + 总结
      expect(seen[2], contains('观点 2')); // 第二位能看到第一位
      expect(seen[5], contains('观点 5')); // 总结能看到全部
    });

    test('单个席位失败不会拖垮整场会议', () async {
      final engine = RoundtableEngine(
        complete: (req, {cancel}) async {
          if (req.maxTokens == 600) return '大纲';
          if (req.maxTokens == 1400) return '结论';
          if (req.model == 'model-1') throw StateError('模型不可用');
          return '观点';
        },
      );
      final m = meeting(seats: 3, rounds: 1);
      await engine.run(m);
      expect(m.phase, MeetingPhase.done);
      expect(m.turns.length, 3);
      expect(m.turns.where((t) => t.ok).length, 2);
      expect(m.turns[1].error, contains('模型不可用'));
      expect(m.summary, '结论');
    });

    test('取消后标记失败且不再继续请求', () async {
      var calls = 0;
      final engine = RoundtableEngine(
        complete: (req, {cancel}) async {
          calls++;
          return '内容';
        },
      );
      final m = meeting(seats: 2, rounds: 3);
      final token = CancelToken()..cancel();
      await engine.run(m, cancel: token);
      expect(m.phase, MeetingPhase.failed);
      expect(calls, 0);
      expect(m.turns, isEmpty);
    });

    test('没有议题或没有可用席位时直接拒绝', () async {
      final engine = RoundtableEngine(complete: responder());
      final noTopic = meeting()..topic = '';
      await expectLater(engine.run(noTopic), throwsA(isA<StateError>()));
      final noSeat = Meeting(id: 'x', topic: '议题');
      await expectLater(engine.run(noSeat), throwsA(isA<StateError>()));
    });

    test('单独生成大纲后可手动修改再开会', () async {
      final m = meeting();
      final engine = RoundtableEngine(complete: responder());
      final agenda = await engine.outline(m);
      expect(agenda.split('\n').length, 3);
      expect(m.phase, MeetingPhase.idle);
      m.agenda = '我改过的大纲';
      await engine.run(m, autoOutline: false);
      expect(m.agenda, '我改过的大纲');
      expect(m.turns.length, 6);
    });
  });
}
