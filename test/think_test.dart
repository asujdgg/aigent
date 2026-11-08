import 'package:ai_agent_app/services/think_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('思考流拆分', () {
    test('把 <thinking> 段抽到思考区，正文只留答案', () {
      final s = ThinkSplitter();
      final p = s.add('<thinking>先看前提，再看结论。</thinking>答案是 42。');
      expect(p.thinking, '先看前提，再看结论。');
      expect(p.content, '答案是 42。');
    });

    test('标签被切成两半时不会漏字', () {
      final s = ThinkSplitter();
      final a = s.add('开头<thin');
      final b = s.add('king>中间</think');
      final c = s.add('ing>结尾');
      final d = s.flush();
      final content = a.content + b.content + c.content + d.content;
      final thinking = a.thinking + b.thinking + c.thinking + d.thinking;
      expect(content, '开头结尾');
      expect(thinking, '中间');
    });

    test('没有思考标签的普通正文原样透传', () {
      final s = ThinkSplitter();
      final p = s.add('直接给答案，不做推理。');
      expect(p.thinking, isEmpty);
      expect(p.content, '直接给答案，不做推理。');
      expect(s.flush().isEmpty, isTrue);
    });

    test('半个标签不会提前吐到正文', () {
      final s = ThinkSplitter();
      final p = s.add('结论在下面 <');
      expect(p.content, '结论在下面 ');
      final q = s.add('think>补一句</think>然后');
      expect(q.thinking, '补一句');
      expect(q.content, '然后');
    });

    test('流结束时仍未闭合，残余内容算思考', () {
      final s = ThinkSplitter();
      final p = s.add('<thinking>话没说完');
      expect(p.content, isEmpty);
      expect(p.thinking, '话没说完');
      final t = s.flush();
      expect(t.thinking, isEmpty);
    });

    test('多段思考与正文交替出现时顺序不乱', () {
      final s = ThinkSplitter();
      final p = s.add(
        '<think>一</think>甲<think>二</think>乙',
      );
      expect(p.thinking, '一二');
      expect(p.content, '甲乙');
    });
  });
}
