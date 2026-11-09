import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/services/life_sim.dart';
import 'package:ai_agent_app/services/llm_client.dart';
import 'package:ai_agent_app/services/roundtable.dart' show CompleteFn;

const _eventJson = '{"title":"高考那年","story":"教室里的风扇转得很慢，'
    '你盯着志愿表，第一次觉得未来真的要自己选。",'
    '"choices":[{"text":"去大城市读书","hint":"机会多"},'
    '{"text":"留在家乡","hint":"安稳"},{"text":"复读一年","hint":"不甘心"}],'
    '"years":3}';

const _resolveJson = '{"outcome":"你去了大城市，起初很难，后来站住了脚。",'
    '"deltas":{"mind":8,"wealth":-4,"joy":3},"years":4}';

SeatLike _conn() => const SeatLike(
    baseUrl: 'https://example.com/v1', apiKey: 'k', model: 'model-x');

LifeCharacter _char() => LifeCharacter(
      id: 'l1',
      name: '林知远',
      gender: '女',
      era: kEraOptions.first,
      goal: kGoalOptions.first,
      birthYear: 2010,
      age: 16,
    );

void main() {
  group('属性结算', () {
    test('增减后夹在 0–100', () {
      final s = LifeStats(health: 5, wealth: 98);
      final out = applyDeltas(s, {'health': -20, 'wealth': 30, 'mind': 7});
      expect(out.health, 0);
      expect(out.wealth, 100);
      expect(out.mind, 62);
      // 原对象不被改动
      expect(s.health, 5);
    });

    test('未知属性被忽略', () {
      final out = applyDeltas(LifeStats(), {'nonexistent': 999});
      expect(out.toMap(), LifeStats().toMap());
    });
  });

  group('模型 JSON 解析容错', () {
    test('抠出代码块里的 JSON', () {
      final j = extractJsonObject('好的，结果如下：\n```json\n$_eventJson\n```\n希望有用');
      expect(j['title'], '高考那年');
    });

    test('前后有废话也能解析', () {
      final j = extractJsonObject('前言\n{"a":1,"b":"x"}\n后记');
      expect(j['a'], 1);
      expect(j['b'], 'x');
    });

    test('完全没有 JSON 时返回空表', () {
      expect(extractJsonObject('模型拒绝回答'), isEmpty);
      expect(extractJsonObject('{ 坏的 json'), isEmpty);
    });

    test('事件解析：正常结构', () {
      final e = parseEventJson(_eventJson, 18, 2028);
      expect(e.title, '高考那年');
      expect(e.choices.length, 3);
      expect(e.choices.first.hint, '机会多');
      expect(e.years, 3);
      expect(e.resolved, isFalse);
    });

    test('事件解析：脏输入给可继续玩的兜底', () {
      final e = parseEventJson('抱歉我无法生成', 20, 2030);
      expect(e.choices.length, 2);
      expect(e.story.isNotEmpty, isTrue);
      expect(e.years, 1);
    });

    test('选项最多 3 个，年数夹在 1–8', () {
      const raw = '{"choices":["A","B","C","D"],"years":99}';
      final e = parseEventJson(raw, 20, 2030);
      expect(e.choices.length, 3);
      expect(e.years, 8);
    });

    test('结果解析：只接受已知属性且单项受限', () {
      final r = parseResolveJson(_resolveJson);
      expect(r.outcome, contains('大城市'));
      expect(r.deltas['mind'], 8);
      expect(r.deltas['wealth'], -4);
      expect(r.years, 4);
      final wild = parseResolveJson('{"deltas":{"health":999,"unknown":50}}');
      expect(wild.deltas['health'], 30);
      expect(wild.deltas.containsKey('unknown'), isFalse);
    });

    test('传记解析：末行数字是评分', () {
      final r = parseFinale('平凡却认真的一生。\n他没成为谁，却没丢了自己。\n\n78');
      expect(r.score, 78);
      expect(r.text, contains('平凡'));
      expect(r.text, isNot(contains('78')));
      final bad = parseFinale('只有一行文字');
      expect(bad.score, 60);
      expect(bad.text, '只有一行文字');
    });
  });

  group('角色与存档', () {
    test('JSON 往返保留事件、属性与结局', () {
      final c = _char();
      final e = parseEventJson(_eventJson, 18, 2028);
      e.chosenIndex = 0;
      e.outcome = '去了大城市';
      e.deltas = {'mind': 8};
      c.events.add(e);
      c.age = 22;
      c.stats = applyDeltas(c.stats, {'mind': 8});
      c.epitaph = '一段评语';
      c.score = 81;
      c.ended = true;
      final back = LifeCharacter.fromJson(c.toJson());
      expect(back.name, '林知远');
      expect(back.age, 22);
      expect(back.events.single.title, '高考那年');
      expect(back.events.single.chosenIndex, 0);
      expect(back.stats.mind, 63);
      expect(back.score, 81);
      expect(back.ended, isTrue);
    });

    test('履历导出含结局与评分', () {
      final c = _char()..ended = true..score = 88..epitaph = '一生清澈。';
      c.events.add(parseEventJson(_eventJson, 18, 2028));
      final md = c.toMarkdown();
      expect(md, contains('# 林知远的一生'));
      expect(md, contains('高考那年'));
      expect(md, contains('盖棺定论'));
      expect(md, contains('88'));
    });

    test('到寿 / 健康归零 / 事件封顶都判定结束', () {
      final a = _char()..age = kMaxAge;
      expect(a.over, isTrue);
      final b = _char()..stats = LifeStats(health: 0);
      expect(b.over, isTrue);
      final d = _char()..ended = true;
      expect(d.over, isTrue);
      expect(_char().over, isFalse);
    });
  });

  group('人生引擎', () {
    CompleteFn responder() => (LlmRequest req, {CancelToken? cancel}) async {
          final user = '${req.messages.last['content']}';
          if (user.contains('请生成下一段人生事件')) return _eventJson;
          if (user.contains('请判定这个选择的后果')) return _resolveJson;
          return '这是他平凡又认真的一生，没成为谁，却没丢了自己。\n76';
        };

    test('事件 → 抉择 → 属性与年龄推进', () async {
      final c = _char();
      var changes = 0;
      final engine = LifeEngine(complete: responder(), onChanged: () => changes++);
      final e = await engine.nextEvent(c, _conn());
      expect(e.choices.length, 3);
      expect(c.pending, isNotNull);
      // 未抉择时再次请求不会重复生成
      final again = await engine.nextEvent(c, _conn());
      expect(identical(again, e), isTrue);
      expect(c.events.length, 1);

      await engine.choose(c, 0, _conn());
      expect(c.pending, isNull);
      expect(c.age, 20);
      expect(c.stats.mind, 63);
      expect(c.stats.wealth, 36);
      expect(e.outcome, contains('大城市'));
      expect(changes, greaterThan(0));
    });

    test('非法选项直接拒绝', () async {
      final c = _char();
      final engine = LifeEngine(complete: responder());
      await engine.nextEvent(c, _conn());
      await expectLater(engine.choose(c, 9, _conn()), throwsA(isA<StateError>()));
    });

    test('收尾生成传记与评分', () async {
      final c = _char();
      final engine = LifeEngine(complete: responder());
      await engine.finalize(c, _conn());
      expect(c.ended, isTrue);
      expect(c.score, 76);
      expect(c.epitaph, contains('平凡'));
    });

    test('结束后不再生成新事件', () async {
      final c = _char()..ended = true;
      final engine = LifeEngine(complete: responder());
      await expectLater(engine.nextEvent(c, _conn()), throwsA(isA<StateError>()));
    });
  });
}
