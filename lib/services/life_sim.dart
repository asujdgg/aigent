import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'llm_client.dart';
import 'roundtable.dart' show CompleteFn;

/// AI 驱动的文字人生模拟。
///
/// 玩法：创建角色 → AI 逐年（或每几年）生成一次人生事件与 2~3 个抉择 →
/// 玩家选择 → AI 判定结果并结算六维属性 → 直到寿终或主动收尾，生成传记。
///
/// 与聊天区分开：所有状态都在本机存档里，不写进会话历史，
/// 也不影响 Token 统计之外的任何对话数据。

const List<String> kStatKeys = [
  'health',
  'mind',
  'charm',
  'wealth',
  'fame',
  'joy',
];

const List<String> kStatLabels = [
  '健康',
  '才智',
  '魅力',
  '财富',
  '声望',
  '幸福',
];

const List<String> kEraOptions = [
  '现代都市 · 2026 年',
  '九十年代 · 小城旧事',
  '古代 · 书香门第',
  '近未来 · 赛博都市',
];

const List<String> kGoalOptions = [
  '顺其自然，过好每一天',
  '事业有成，闯出一番名堂',
  '家人平安，守住平凡幸福',
  '见世面，走遍天涯',
  '求知到底，成为某个领域的行家',
];

const int kMaxAge = 82;
const int kMaxEvents = 40;

/// 六维属性，全部 0–100。
class LifeStats {
  int health;
  int mind;
  int charm;
  int wealth;
  int fame;
  int joy;

  LifeStats({
    this.health = 70,
    this.mind = 55,
    this.charm = 50,
    this.wealth = 40,
    this.fame = 10,
    this.joy = 60,
  });

  int operator [](String key) {
    switch (key) {
      case 'health':
        return health;
      case 'mind':
        return mind;
      case 'charm':
        return charm;
      case 'wealth':
        return wealth;
      case 'fame':
        return fame;
      case 'joy':
        return joy;
      default:
        return 0;
    }
  }

  Map<String, int> toMap() => {
        'health': health,
        'mind': mind,
        'charm': charm,
        'wealth': wealth,
        'fame': fame,
        'joy': joy,
      };

  factory LifeStats.fromMap(Map<dynamic, dynamic> m) => LifeStats(
        health: _int(m['health'], 70),
        mind: _int(m['mind'], 55),
        charm: _int(m['charm'], 50),
        wealth: _int(m['wealth'], 40),
        fame: _int(m['fame'], 10),
        joy: _int(m['joy'], 60),
      );

  Map<String, dynamic> toJson() => toMap();

  static int _int(dynamic v, int fallback) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? fallback;
}

/// 把属性变化夹到 0–100。纯函数，离线可测。
LifeStats applyDeltas(LifeStats base, Map<String, int> deltas) {
  int v(int cur, String key) =>
      (cur + (deltas[key] ?? 0)).clamp(0, 100).toInt();
  return LifeStats(
    health: v(base.health, 'health'),
    mind: v(base.mind, 'mind'),
    charm: v(base.charm, 'charm'),
    wealth: v(base.wealth, 'wealth'),
    fame: v(base.fame, 'fame'),
    joy: v(base.joy, 'joy'),
  );
}

class LifeChoice {
  final String text;
  final String hint;

  const LifeChoice({required this.text, this.hint = ''});

  Map<String, dynamic> toJson() => {'text': text, 'hint': hint};

  factory LifeChoice.fromJson(Map<dynamic, dynamic> j) => LifeChoice(
        text: (j['text'] ?? '').toString(),
        hint: (j['hint'] ?? '').toString(),
      );
}

/// 一次人生事件（含抉择与结算结果）。
class LifeEvent {
  final int age;
  final int year;
  final String title;
  final String story;
  final List<LifeChoice> choices;
  int chosenIndex;
  String outcome;
  Map<String, int> deltas;
  int years;

  LifeEvent({
    required this.age,
    required this.year,
    required this.title,
    required this.story,
    List<LifeChoice>? choices,
    this.chosenIndex = -1,
    this.outcome = '',
    Map<String, int>? deltas,
    this.years = 1,
  })  : choices = choices ?? <LifeChoice>[],
        deltas = deltas ?? <String, int>{};

  bool get resolved => chosenIndex >= 0 && outcome.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'age': age,
        'year': year,
        'title': title,
        'story': story,
        'choices': [for (final c in choices) c.toJson()],
        'chosenIndex': chosenIndex,
        'outcome': outcome,
        'deltas': deltas,
        'years': years,
      };

  factory LifeEvent.fromJson(Map<dynamic, dynamic> j) => LifeEvent(
        age: (j['age'] as num?)?.toInt() ?? 0,
        year: (j['year'] as num?)?.toInt() ?? 2000,
        title: (j['title'] ?? '').toString(),
        story: (j['story'] ?? '').toString(),
        choices: j['choices'] is List
            ? (j['choices'] as List)
                .whereType<Map>()
                .map((e) => LifeChoice.fromJson(e))
                .toList()
            : <LifeChoice>[],
        chosenIndex: (j['chosenIndex'] as num?)?.toInt() ?? -1,
        outcome: (j['outcome'] ?? '').toString(),
        deltas: j['deltas'] is Map
            ? (j['deltas'] as Map).map(
                (k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0))
            : <String, int>{},
        years: (j['years'] as num?)?.toInt() ?? 1,
      );
}

class LifeCharacter {
  final String id;
  String name;
  String gender;
  String era;
  String goal;
  int birthYear;
  int age;
  LifeStats stats;
  final List<LifeEvent> events;
  bool ended;
  String epitaph;
  int score;
  final DateTime createdAt;

  LifeCharacter({
    required this.id,
    this.name = '',
    this.gender = '女',
    // 默认参数必须是编译期常量，不能写 kEraOptions.first。
    this.era = '现代都市 · 2026 年',
    this.goal = '顺其自然，过好每一天',
    this.birthYear = 2000,
    this.age = 16,
    LifeStats? stats,
    List<LifeEvent>? events,
    this.ended = false,
    this.epitaph = '',
    this.score = 0,
    DateTime? createdAt,
  })  : stats = stats ?? LifeStats(),
        events = events ?? <LifeEvent>[],
        createdAt = createdAt ?? DateTime.now();

  int get year => birthYear + age;

  LifeEvent? get pending =>
      events.isEmpty || events.last.resolved ? null : events.last;

  /// 健康归零、到寿、或事件数封顶即结束。年龄上限是硬性的，
  /// 免得模型一直给 years=0 让人生无限循环。
  bool get over => ended || stats.health <= 0 || age >= kMaxAge ||
      events.length >= kMaxEvents;

  String toMarkdown() {
    final b = StringBuffer();
    // 分三段写，避免「$name的一生」被 Dart 当成中文标识符，
    // 也避开字符串拼接 / 多余插值大括号两组 lint。
    b.write('# ');
    b.write(name);
    b.writeln('的一生');
    b.writeln();
    b.writeln('> $era · $gender · 生于 $birthYear 年 · 终于 $age 岁 · '
        '人生评分 $score');
    b.writeln();
    b.writeln('人生目标：${goal.trim().isEmpty ? '顺其自然' : goal}');
    b.writeln();
    b.writeln('最终状态：${_statsLine()}');
    b.writeln();
    b.writeln('## 人生履历');
    b.writeln();
    for (final e in events) {
      b.writeln('### ${e.age} 岁 · ${e.title}（${e.year} 年）');
      b.writeln();
      b.writeln(e.story);
      b.writeln();
      if (e.resolved) {
        b.writeln('选择：${e.choices[e.chosenIndex].text}');
        b.writeln();
        b.writeln('结果：${e.outcome}');
        b.writeln();
      }
    }
    if (epitaph.trim().isNotEmpty) {
      b.writeln('## 盖棺定论');
      b.writeln();
      b.writeln(epitaph.trim());
      b.writeln();
    }
    b.writeln('---');
    b.writeln('由 Aigent 模拟人生生成，纯属虚构。');
    return b.toString();
  }

  String _statsLine() => [
        for (var i = 0; i < kStatKeys.length; i++)
          '${kStatLabels[i]} ${stats[kStatKeys[i]]}'
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gender': gender,
        'era': era,
        'goal': goal,
        'birthYear': birthYear,
        'age': age,
        'stats': stats.toJson(),
        'events': [for (final e in events) e.toJson()],
        'ended': ended,
        'epitaph': epitaph,
        'score': score,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory LifeCharacter.fromJson(Map<dynamic, dynamic> j) => LifeCharacter(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        gender: (j['gender'] ?? '女').toString(),
        era: (j['era'] ?? kEraOptions.first).toString(),
        goal: (j['goal'] ?? kGoalOptions.first).toString(),
        birthYear: (j['birthYear'] as num?)?.toInt() ?? 2000,
        age: (j['age'] as num?)?.toInt() ?? 16,
        stats: j['stats'] is Map
            ? LifeStats.fromMap(j['stats'] as Map)
            : LifeStats(),
        events: j['events'] is List
            ? (j['events'] as List)
                .whereType<Map>()
                .map((e) => LifeEvent.fromJson(e))
                .toList()
            : <LifeEvent>[],
        ended: j['ended'] == true,
        epitaph: (j['epitaph'] ?? '').toString(),
        score: (j['score'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      );
}

/// 模型偶尔会包一层 ```json 或加前后废话，这里统一抠出第一个 JSON 对象。
Map<String, dynamic> extractJsonObject(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final m = fence.firstMatch(s);
  if (m != null) s = m.group(1)!.trim();
  final start = s.indexOf('{');
  if (start < 0) return <String, dynamic>{};
  // 从后往前找最后一个 }，兼容正文里出现花括号的情况。
  final end = s.lastIndexOf('}');
  if (end <= start) return <String, dynamic>{};
  try {
    final v = jsonDecode(s.substring(start, end + 1));
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return <String, dynamic>{};
}

/// 解析事件 JSON；解析不出来时给一个可继续玩的兜底事件。
LifeEvent parseEventJson(String raw, int age, int year) {
  final j = extractJsonObject(raw);
  final choices = <LifeChoice>[];
  final cs = j['choices'];
  if (cs is List) {
    for (final c in cs) {
      if (c is Map) {
        choices.add(LifeChoice(
            text: (c['text'] ?? '').toString(),
            hint: (c['hint'] ?? '').toString()));
      } else if (c is String && c.trim().isNotEmpty) {
        choices.add(LifeChoice(text: c.trim()));
      }
    }
  }
  if (choices.isEmpty) {
    choices.addAll(const [
      LifeChoice(text: '稳妥行事，按部就班'),
      LifeChoice(text: '冒险一试，抓住机会'),
    ]);
  }
  final title = (j['title'] ?? '').toString().trim();
  final story = (j['story'] ?? '').toString().trim();
  final years = (j['years'] as num?)?.toInt() ?? 1;
  return LifeEvent(
    age: age,
    year: year,
    title: title.isEmpty ? '人生的一个岔路口' : title,
    story: story.isEmpty
        ? '这一年，生活把你推到了一个需要做出选择的路口。'
        : story,
    choices: choices.take(3).toList(),
    years: years.clamp(1, 8),
  );
}

/// 解析抉择结果 JSON。
({String outcome, Map<String, int> deltas, int years}) parseResolveJson(
    String raw) {
  final j = extractJsonObject(raw);
  final outcome = (j['outcome'] ?? '').toString().trim();
  final deltas = <String, int>{};
  final d = j['deltas'];
  if (d is Map) {
    for (final k in kStatKeys) {
      final v = d[k];
      if (v is num) deltas[k] = v.toInt().clamp(-30, 30);
    }
  }
  return (
    outcome: outcome.isEmpty ? '日子照旧往前走，只是心里多了一点说不清的滋味。' : outcome,
    deltas: deltas,
    years: ((j['years'] as num?)?.toInt() ?? 1).clamp(1, 8),
  );
}

String buildLifeSystem(LifeCharacter c) =>
    '你是一款文字人生模拟游戏的人生叙述者。时代背景：${c.era}。'
    '请用与设定一致的语言、克制而有画面感的笔调叙述，不要说教，'
    '不要跳出剧情，不要提到自己是 AI 或这是游戏。'
    '所有输出必须是严格 JSON，不要 Markdown 代码块以外任何多余文字。';

String buildEventUser(LifeCharacter c) {
  final recent = c.events.length > 5
      ? c.events.sublist(c.events.length - 5)
      : c.events;
  final hist = recent.isEmpty
      ? '（人生刚刚开始）'
      : recent
          .map((e) => '${e.age}岁 ${e.title}：'
              '${e.resolved ? e.outcome : '尚未抉择'}')
          .join('\n');
  return '角色：${c.name}，${c.gender}，${c.age} 岁（${c.year} 年）。\n'
      '人生目标：${c.goal}\n'
      '当前状态：${kStatLabels.asMap().entries.map((e) => '${e.value} ${c.stats[kStatKeys[e.key]]}').join('、')}\n'
      '近期履历：\n$hist\n\n'
      '请生成下一段人生事件，必须与年龄、时代、当前状态和过往经历连贯。'
      '输出 JSON：{"title":"事件标题","story":"80到160字的场景叙述",'
      '"choices":[{"text":"选项一","hint":"简短倾向提示"},'
      '{"text":"选项二","hint":"..."},{"text":"选项三","hint":"..."}],'
      '"years":本次推进的年数}。choices 给 2 到 3 个，'
      '彼此应有真实的取舍差异，不要都是明显的好选择。';
}

String buildResolveUser(LifeCharacter c, LifeEvent e, int choiceIndex) =>
    '角色：${c.name}，${c.age} 岁，时代：${c.era}。'
    '当前状态：${kStatLabels.asMap().entries.map((x) => '${x.value} ${c.stats[kStatKeys[x.key]]}').join('、')}\n'
    '刚发生的事件：${e.title} — ${e.story}\n'
    'TA 的选择：${e.choices[choiceIndex].text}\n\n'
    '请判定这个选择的后果，叙述 60 到 120 字，并给出六维属性变化。'
    '输出 JSON：{"outcome":"结果叙述","deltas":'
    '{"health":0,"mind":0,"charm":0,"wealth":0,"fame":0,"joy":0},'
    '"years":推进年数}。deltas 为整数，单项 -30 到 30，'
    '有得必有失，不要让所有属性都上涨。';

String buildFinaleUser(LifeCharacter c) =>
    '这是 ${c.name} 的一生：${c.gender}，${c.era}，享年 ${c.age} 岁，'
    '目标「${c.goal}」。\n'
    '履历：\n${c.events.map((e) => '${e.age}岁 ${e.title}：${e.outcome}').join('\n')}\n'
    '最终状态：${kStatLabels.asMap().entries.map((x) => '${x.value} ${c.stats[kStatKeys[x.key]]}').join('、')}\n\n'
    '请写一段 150 到 250 字的人生总结（像传记末尾的评语，'
    '回望 TA 的选择与命运，温和但不粉饰），并在最后单独一行给出'
    '0 到 100 的整数评分。第一行写总结，第二行只写数字。';

/// 人生引擎：所有 LLM 调用可注入，便于离线单测。
class LifeEngine {
  LifeEngine({LlmClient? llm, CompleteFn? complete, this.onChanged})
      : _llm = llm ?? LlmClient(),
        _complete = complete;

  final LlmClient _llm;
  final CompleteFn? _complete;
  final void Function()? onChanged;

  Future<String> _ask(SeatLike conn, String system, String user,
      {int maxTokens = 800, CancelToken? cancel}) {
    final req = LlmRequest(
      baseUrl: conn.baseUrl,
      apiKey: conn.apiKey,
      model: conn.model,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      maxTokens: maxTokens,
      temperature: 0.85,
      topP: 0.95,
      thinkingBudget: 0,
      reasoningEffort: 'medium',
      deepThinking: false,
      includeUsage: false,
    );
    final fn = _complete;
    if (fn != null) return fn(req, cancel: cancel);
    return _llm.complete(req, cancel: cancel);
  }

  void _emit() => onChanged?.call();

  /// 生成下一段事件（未抉择）。
  Future<LifeEvent> nextEvent(LifeCharacter c, SeatLike conn,
      {CancelToken? cancel}) async {
    final pending = c.pending;
    if (pending != null) return pending;
    if (c.over) throw StateError('这一生已经结束了');
    final raw = await _ask(
        conn, buildLifeSystem(c), buildEventUser(c), cancel: cancel);
    final e = parseEventJson(raw, c.age, c.year);
    c.events.add(e);
    _emit();
    return e;
  }

  /// 结算当前事件的选择，并推进年龄与属性。
  Future<LifeEvent> choose(LifeCharacter c, int index, SeatLike conn,
      {CancelToken? cancel}) async {
    final e = c.pending;
    if (e == null) throw StateError('当前没有待抉择的事件');
    if (index < 0 || index >= e.choices.length) {
      throw StateError('选项不存在');
    }
    final raw = await _ask(conn, buildLifeSystem(c),
        buildResolveUser(c, e, index),
        cancel: cancel);
    final r = parseResolveJson(raw);
    e.chosenIndex = index;
    e.outcome = r.outcome;
    e.deltas = r.deltas;
    c.stats = applyDeltas(c.stats, r.deltas);
    final years = (r.years <= 0 ? e.years : r.years).clamp(1, 8);
    e.years = years;
    c.age = (c.age + years).clamp(0, kMaxAge);
    if (c.over) c.ended = true;
    _emit();
    return e;
  }

  /// 收尾：写传记与评分。
  Future<void> finalize(LifeCharacter c, SeatLike conn,
      {CancelToken? cancel}) async {
    c.ended = true;
    _emit();
    final raw = await _ask(conn, buildLifeSystem(c), buildFinaleUser(c),
        maxTokens: 900, cancel: cancel);
    final parsed = parseFinale(raw);
    c.epitaph = parsed.text;
    c.score = parsed.score;
    _emit();
  }
}

/// 传记文本与评分解析（最后一行只写数字）。
({String text, int score}) parseFinale(String raw) {
  final s = raw.trim();
  final lines = s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return (text: '这一生，平淡而真实。', score: 60);
  int score = 60;
  var textLines = lines;
  final last = lines.last.replaceAll(RegExp(r'[^0-9\-]'), '');
  final n = int.tryParse(last);
  if (n != null && lines.length > 1) {
    score = n.clamp(0, 100);
    textLines = lines.sublist(0, lines.length - 1);
  }
  return (text: textLines.join('\n').trim(), score: score);
}

/// 一次 LLM 调用所需的连接信息，与会议席位解耦。
class SeatLike {
  final String baseUrl;
  final String apiKey;
  final String model;

  const SeatLike({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });
}

/// 随机生成一个不重复的角色 id。
String newLifeId() =>
    'life_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

String newMeetingId() =>
    'meet_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
