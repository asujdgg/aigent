import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/services/mini_games.dart';

void main() {
  group('抉择轮盘', () {
    test('中英文逗号、分号、换行都能分隔，去空去重', () {
      expect(parseWheelOptions('A,B，C; D\nE；F'),
          ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(parseWheelOptions('A,A, A ,,'), ['A']);
      expect(parseWheelOptions('  '), isEmpty);
    });

    test('少于两个选项转不起来，结果必在选项内', () {
      expect(spinWheel(['A']), isNull);
      expect(spinWheel([]), isNull);
      final opts = ['A', 'B', 'C'];
      for (var seed = 0; seed < 30; seed++) {
        expect(opts, contains(spinWheel(opts, seed: seed)));
      }
    });
  });

  group('猜数字', () {
    test('判定三种结果', () {
      expect(judgeGuess(50, 30), -1);
      expect(judgeGuess(50, 50), 0);
      expect(judgeGuess(50, 70), 1);
    });

    test('注入目标可确定性验证，越界不接受，猜中后锁定', () {
      final g = GuessNumberGame(target: 42);
      expect(g.guess(20), -1);
      expect(g.guess(60), 1);
      expect(g.guess(42), 0);
      expect(g.done, isTrue);
      expect(g.tries, 3);
      expect(g.guess(1), 0); // 结束后不再计数
      expect(g.tries, 3);
    });

    test('越界输入不消耗次数', () {
      final g = GuessNumberGame(target: 42);
      expect(g.guess(0), isNull);
      expect(g.guess(101), isNull);
      expect(g.tries, 0);
    });
  });

  group('石头剪刀布', () {
    test('三态循环胜负', () {
      expect(rpsJudge(RpsMove.rock, RpsMove.scissors), 1);
      expect(rpsJudge(RpsMove.scissors, RpsMove.paper), 1);
      expect(rpsJudge(RpsMove.paper, RpsMove.rock), 1);
      expect(rpsJudge(RpsMove.rock, RpsMove.paper), -1);
      expect(rpsJudge(RpsMove.rock, RpsMove.rock), 0);
    });

    test('随机出拳始终合法', () {
      for (var s = 0; s < 20; s++) {
        expect(RpsMove.values, contains(randomRps(seed: s)));
      }
    });
  });

  group('每日一签与八球', () {
    test('同一天同一支签，跨天变化，下标不越界', () {
      final d1 = DateTime(2026, 11, 9);
      final d2 = DateTime(2026, 11, 10);
      expect(fortuneIndex(d1, 7), fortuneIndex(d1, 7));
      expect(fortuneIndex(d1, 7), isIn(List.generate(7, (i) => i)));
      expect(fortuneIndex(d2, 7), isIn(List.generate(7, (i) => i)));
      expect(fortuneIndex(DateTime(2026, 11, 9, 23, 59), 7),
          fortuneIndex(d1, 7));
      expect(fortuneIndex(d1, 0), 0);
    });

    test('八球下标不越界', () {
      for (var s = 0; s < 20; s++) {
        expect(eightBallIndex(8, seed: s), isIn(List.generate(8, (i) => i)));
      }
      expect(eightBallIndex(0), 0);
    });
  });

  group('AI 玩法提示词', () {
    test('二十问系统词藏住答案且限定回答', () {
      final sys = twentyQuestionsSystem('月亮');
      expect(sys, contains('月亮'));
      expect(sys, contains('只回答'));
      expect(twentyQuestionsOpening(), contains('20'));
    });

    test('故事接龙按主题开篇', () {
      expect(storyChainSystem(), contains('60'));
      expect(storyChainOpening('太空电梯'), contains('太空电梯'));
    });

    test('回答归一化覆盖四种判定', () {
      expect(normalizeTwentyAnswer('是'), 'yes');
      expect(normalizeTwentyAnswer('不是'), 'no');
      expect(normalizeTwentyAnswer('不确定'), 'unclear');
      expect(normalizeTwentyAnswer('猜对了！'), 'correct');
      expect(normalizeTwentyAnswer('Yes'), 'yes');
      expect(normalizeTwentyAnswer('No'), 'no');
      expect(normalizeTwentyAnswer('很长的解释'), 'unclear');
    });

    test('玩法标记：只有两个需要 AI', () {
      expect(miniGameNeedsAi(MiniGameKind.wheel), isFalse);
      expect(miniGameNeedsAi(MiniGameKind.guess), isFalse);
      expect(miniGameNeedsAi(MiniGameKind.rps), isFalse);
      expect(miniGameNeedsAi(MiniGameKind.fortune), isFalse);
      expect(miniGameNeedsAi(MiniGameKind.eightBall), isFalse);
      expect(miniGameNeedsAi(MiniGameKind.twentyQuestions), isTrue);
      expect(miniGameNeedsAi(MiniGameKind.storyChain), isTrue);
    });
  });
}
