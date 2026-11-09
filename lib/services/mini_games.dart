import 'dart:math';

import 'llm_client.dart';
import 'roundtable.dart' show CompleteFn;

/// 设置 → 游戏 里的玩法清单。
///
/// 前五个纯本地、不花 token、离线可玩；后两个由当前模型驱动。
/// 逻辑尽量集中在这里，UI 只负责渲染，方便离线单测。
enum MiniGameKind {
  wheel,
  guess,
  rps,
  fortune,
  eightBall,
  twentyQuestions,
  storyChain,
}

bool miniGameNeedsAi(MiniGameKind k) =>
    k == MiniGameKind.twentyQuestions || k == MiniGameKind.storyChain;

// ---------------------------------------------------------------- 抉择轮盘

/// 把一段输入（逗号 / 换行分隔）拆成选项，去空去重。
List<String> parseWheelOptions(String raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,，\n;；]'))) {
    final v = part.trim();
    if (v.isEmpty || !seen.add(v)) continue;
    out.add(v);
  }
  return out;
}

/// 轮盘随机结果；少于两个选项返回 null（转不起来）。
String? spinWheel(List<String> options, {int? seed, Random? random}) {
  if (options.length < 2) return null;
  final r = random ?? Random(seed);
  return options[r.nextInt(options.length)];
}

// ------------------------------------------------------------------ 猜数字

/// 返回 -1（小了）/ 0（中了）/ 1（大了）。
int judgeGuess(int target, int value) {
  if (value < target) return -1;
  if (value > target) return 1;
  return 0;
}

class GuessNumberGame {
  GuessNumberGame({
    this.min = 1,
    this.max = 100,
    int? target,
    int? seed,
  }) : target = target ?? (min + Random(seed).nextInt(max - min + 1));

  final int min;
  final int max;
  final int target;
  int tries = 0;
  bool done = false;
  int? last;
  int? lastHint;

  int? guess(int value) {
    if (done) return lastHint;
    if (value < min || value > max) return null;
    tries++;
    last = value;
    lastHint = judgeGuess(target, value);
    if (lastHint == 0) done = true;
    return lastHint;
  }
}

// ------------------------------------------------------------ 石头剪刀布

enum RpsMove { rock, scissors, paper }

/// 返回 1（a 赢）/ -1（b 赢）/ 0（平）。
int rpsJudge(RpsMove a, RpsMove b) {
  if (a == b) return 0;
  const beats = {
    RpsMove.rock: RpsMove.scissors,
    RpsMove.scissors: RpsMove.paper,
    RpsMove.paper: RpsMove.rock,
  };
  return beats[a] == b ? 1 : -1;
}

RpsMove randomRps({int? seed, Random? random}) {
  final r = random ?? Random(seed);
  return RpsMove.values[r.nextInt(RpsMove.values.length)];
}

// -------------------------------------------------------------- 每日一签

/// 同一天抽到同一支签，跨天自然变化；与词表条数无关，只返回下标。
int fortuneIndex(DateTime day, int count) {
  if (count <= 0) return 0;
  final seed = day.year * 10000 + day.month * 100 + day.day;
  return seed % count;
}

// --------------------------------------------------------------- 魔法八球

int eightBallIndex(int count, {int? seed, Random? random}) {
  if (count <= 0) return 0;
  final r = random ?? Random(seed);
  return r.nextInt(count);
}

// ------------------------------------------------------------ AI 玩法提示词

/// 二十问：模型先在心里定好一个答案，用户用是非题提问，模型只回三种判定。
String twentyQuestionsSystem(String secret) =>
    '你正在和用户玩「二十问猜物」游戏。你心里想好的东西是：$secret。'
    '规则：用户每次只能用一个是非题提问；你只回答「是」「不是」或「不确定」，'
    '不要解释、不要补充、不要剧透答案。如果用户直接猜出了 $secret，'
    '就回答「猜对了」并简短祝贺；否则严格只回上述四种之一。';

String twentyQuestionsOpening() =>
    '我已经想好了一个东西。请用一个是非题开始提问，最多 20 次。';

/// 故事接龙：模型与用户轮流写一小段，模型推进剧情并留下悬念。
String storyChainSystem() =>
    '你和用户一起玩故事接龙。规则：'
    '1) 每次只写 60 到 120 字的一小段，接续上一段剧情；'
    '2) 保持人物与设定连贯，不要替用户做决定；'
    '3) 结尾留一个悬念或转折，方便用户接下去；'
    '4) 使用用户当前所用的语言；'
    '5) 不要写标题、编号或任何说明文字，只写故事正文。';

String storyChainOpening(String theme) =>
    '我们来讲一个关于「$theme」的故事。请写开篇第一段。';

/// 把 AI 小游戏的一轮消息发出去。history 为不含 system 的多轮消息。
Future<String> miniGameComplete({
  required CompleteFn complete,
  required String baseUrl,
  required String apiKey,
  required String model,
  required String system,
  required List<Map<String, String>> history,
}) {
  final req = LlmRequest(
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    messages: [
      {'role': 'system', 'content': system},
      ...history,
    ],
    maxTokens: 400,
    temperature: 0.85,
    topP: 0.95,
    thinkingBudget: 0,
    reasoningEffort: 'medium',
    deepThinking: false,
    includeUsage: false,
  );
  return complete(req);
}

/// 把 AI 的判定回答收敛成四类，供 UI 显示不同颜色。
String normalizeTwentyAnswer(String raw) {
  final s = raw.trim();
  if (s.contains('猜对') || s.toLowerCase().contains('correct')) {
    return 'correct';
  }
  if (s.contains('不确定') || s.toLowerCase().contains('unclear')) {
    return 'unclear';
  }
  if (s.startsWith('不是') || s.startsWith('否') ||
      s.toLowerCase().startsWith('no')) {
    return 'no';
  }
  if (s.startsWith('是') || s.toLowerCase().startsWith('yes')) {
    return 'yes';
  }
  return 'unclear';
}
