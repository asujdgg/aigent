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

/// 一章跨越的年数范围。人生不是逐帧的：大部分年份自动流过，
/// 只在真正需要决定的节点停下。跨度太小会变成流水账，太大又
/// 会让玩家失去参与感，4~8 年是实测比较舒服的区间。
const int kMinStageYears = 3;
const int kMaxStageYears = 9;

/// 一项天赋：天生偏向的维度 + 一个具体说法。
///
/// 「强项」不是抽象数值，而是能被叙述抓住的东西——模型拿到
/// 「过目不忘」比拿到「才智 +22」更容易写出有画面感的段落。
class LifeTalent {
  final String key;
  final String name;
  final String desc;
  final String hint;

  const LifeTalent(this.key, this.name, this.desc, this.hint);
}

const List<LifeTalent> kTalents = [
  LifeTalent('mind', '过目不忘', '看过的东西像刻在脑子里，考试前翻一遍就够。', '读书人'),
  LifeTalent('mind', '一点就透', '别人讲三遍的事，你听一半就明白。', '学什么都快'),
  LifeTalent('mind', '钻得进去', '对着一个问题能坐一整天不觉得烦。', '技术型'),
  LifeTalent('health', '底子硬', '从小没怎么进过医院，冬天也光着脚跑。', '身体好'),
  LifeTalent('health', '耐折腾', '熬夜、赶路、扛重物，睡一觉就缓过来。', '吃得住苦'),
  LifeTalent('charm', '耐看', '第一眼不出挑，越看越顺眼，说话时别人愿意听。', '人缘好'),
  LifeTalent('charm', '自来熟', '跟谁都能在三句话里熟起来。', '会来事'),
  LifeTalent('wealth', '家里有余粮', '不算富，但从不缺口粮与学费。', '起点稳'),
  LifeTalent('wealth', '会算账', '从小就知道钱该花在哪，买菜都要比三家。', '精打细算'),
  LifeTalent('fame', '站在人前不怵', '一屋子人看着你，你反而更清醒。', '能上台'),
  LifeTalent('fame', '被记住', '见过你的人都记得你的名字。', '有名气'),
  LifeTalent('joy', '心大', '天塌下来先睡一觉，醒来再说。', '抗打击'),
  LifeTalent('joy', '容易开心', '一碗热汤、一场雨都能让你高兴半天。', '知足'),
];

/// 一次开局抽奖的结果：六维 + 天赋 + 稀有度。
///
/// 抽奖是纯函数（注入 [Random]），离线可测，也不依赖任何模型。
class CharacterRoll {
  final LifeStats stats;
  final LifeTalent talent;

  /// 0 普通 / 1 稀有 / 2 传说。
  final int rarity;

  const CharacterRoll({
    required this.stats,
    required this.talent,
    required this.rarity,
  });

  int get total =>
      stats.health + stats.mind + stats.charm + stats.wealth + stats.fame + stats.joy;

  /// 最强的那一项，用来在界面上标「强项」。
  String get strongestKey {
    var best = kStatKeys.first;
    for (final k in kStatKeys) {
      if (stats[k] > stats[best]) best = k;
    }
    return best;
  }
}

/// 抽一个人：六维各有起伏，一项天赋拉开差距，再随机给一项短板。
///
/// 刻意保留明显短板：六边形战士没有故事，偏低的那一维才是
/// 「这一生要面对什么」的起点。
CharacterRoll rollCharacter([Random? rng]) {
  final r = rng ?? Random();
  final base = <String, int>{
    for (final k in kStatKeys) k: 30 + r.nextInt(30), // 30~59
  };
  // 天赋一项，稀有度越高加成越大。
  final talent = kTalents[r.nextInt(kTalents.length)];
  final roll = r.nextInt(100);
  final rarity = roll >= 94 ? 2 : (roll >= 72 ? 1 : 0);
  final bonus = switch (rarity) { 2 => 26, 1 => 19, _ => 13 };
  base[talent.key] = (base[talent.key]! + bonus).clamp(0, 100);
  // 一项短板，避开天赋维度。
  final others = kStatKeys.where((k) => k != talent.key).toList();
  final weak = others[r.nextInt(others.length)];
  base[weak] = (base[weak]! - (8 + r.nextInt(8))).clamp(0, 100);
  return CharacterRoll(
    stats: LifeStats(
      health: base['health']!,
      mind: base['mind']!,
      charm: base['charm']!,
      wealth: base['wealth']!,
      fame: base['fame']!,
      joy: base['joy']!,
    ),
    talent: talent,
    rarity: rarity,
  );
}


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

/// 一章人生（含抉择与结算结果）。
///
/// 一章不是一年：它覆盖 [startAge] 到 [age] 这几年，正文概括这段时间
/// 怎么过的，末尾才是一个需要玩家拍板的关键节点。
class LifeEvent {
  final int startAge;
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
    int? startAge,
    required this.year,
    required this.title,
    required this.story,
    List<LifeChoice>? choices,
    this.chosenIndex = -1,
    this.outcome = '',
    Map<String, int>? deltas,
    this.years = 1,
  })  : startAge = (startAge ?? (age - 1)).clamp(0, kMaxAge),
        choices = choices ?? <LifeChoice>[],
        deltas = deltas ?? <String, int>{};

  bool get resolved => chosenIndex >= 0 && outcome.isNotEmpty;

  /// 「0 → 6 岁」这样的跨度文本，界面上比单个年龄更能说明
  /// 这一章自动跑过了多少年。
  String get spanLabel =>
      startAge == age ? '$age' : '$startAge → $age';

  Map<String, dynamic> toJson() => {
        'startAge': startAge,
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
        startAge: (j['startAge'] as num?)?.toInt(),
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

  /// 出生地（省 / 市）。旧存档没有这两项，读回来是空字符串。
  String province;
  String city;

  /// 开局抽到的天赋。key 是六维之一，name/desc 直接参与叙述。
  String talentKey;
  String talentName;
  String talentDesc;

  /// 0 普通 / 1 稀有 / 2 传说，只用于展示。
  int talentRarity;

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
    this.province = '',
    this.city = '',
    this.talentKey = '',
    this.talentName = '',
    this.talentDesc = '',
    this.talentRarity = 0,
    this.birthYear = 2000,
    this.age = 0,
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
    final place = province.isEmpty
        ? ''
        : ' · 生于 ${city.isEmpty ? province : '$province$city'}';
    b.writeln('> $era$place · $gender · $birthYear 年 · 终于 $age 岁 · '
        '人生评分 $score');
    b.writeln();
    b.writeln('人生目标：${goal.trim().isEmpty ? '顺其自然' : goal}');
    if (talentName.trim().isNotEmpty) {
      b.writeln();
      b.writeln('天赋：$talentName${talentDesc.trim().isEmpty ? '' : ' —— $talentDesc'}');
    }
    b.writeln();
    b.writeln('最终状态：${_statsLine()}');
    b.writeln();
    b.writeln('## 人生履历');
    b.writeln();
    for (final e in events) {
      b.writeln('### ${e.spanLabel} 岁 · ${e.title}（${e.year} 年）');
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
        'province': province,
        'city': city,
        'talentKey': talentKey,
        'talentName': talentName,
        'talentDesc': talentDesc,
        'talentRarity': talentRarity,
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
        province: (j['province'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        talentKey: (j['talentKey'] ?? '').toString(),
        talentName: (j['talentName'] ?? '').toString(),
        talentDesc: (j['talentDesc'] ?? '').toString(),
        talentRarity: (j['talentRarity'] as num?)?.toInt() ?? 0,
        birthYear: (j['birthYear'] as num?)?.toInt() ?? 2000,
        age: (j['age'] as num?)?.toInt() ?? 0,
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

/// 解析一章人生的 JSON；解析不出来时给一个可继续玩的兜底章节。
LifeEvent parseEventJson(String raw, int startAge, int year) {
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
  // 模型偶尔会给 years=1，把一章写成一年；这里兜到最小跨度，
  // 保证「很多年自动跑过去」的节奏不被拆碎。
  final rawYears = (j['years'] as num?)?.toInt() ?? 5;
  var years = rawYears.clamp(kMinStageYears, kMaxStageYears);
  if (startAge + years > kMaxAge) {
    years = (kMaxAge - startAge).clamp(1, kMaxStageYears);
  }
  final endAge = (startAge + years).clamp(startAge, kMaxAge);
  return LifeEvent(
    startAge: startAge,
    age: endAge,
    year: year,
    title: title.isEmpty ? '人生的一个岔路口' : title,
    story: story.isEmpty
        ? '这几年没什么大事，日子自己往前走，直到某个岔路口摆在面前。'
        : story,
    choices: choices.take(3).toList(),
    years: years,
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
    '叙述节奏：一章跨越若干年，用一段话概括这几年怎么过的，'
    '只在章末停在一个需要玩家决定的时刻；绝不逐年罗列，也不写成年表。'
    '请用与设定一致的语言、克制而有画面感的笔调叙述，不要说教，'
    '不要跳出剧情，不要提到自己是 AI 或这是游戏。'
    '所有输出必须是严格 JSON，不要 Markdown 代码块以外任何多余文字。';

String buildEventUser(LifeCharacter c) {
  final recent = c.events.length > 4
      ? c.events.sublist(c.events.length - 4)
      : c.events;
  final hist = recent.isEmpty
      ? '（人生刚刚开始）'
      : recent
          .map((e) => '${e.spanLabel}岁 ${e.title}：'
              '${e.resolved ? e.outcome : '尚未抉择'}')
          .join('\n');
  final place = c.province.isEmpty
      ? '未设定'
      : (c.city.isEmpty ? c.province : '${c.province}${c.city}');
  final talent = c.talentName.trim().isEmpty
      ? '没有特别的天赋'
      : '${c.talentName} —— ${c.talentDesc}';
  return '角色：${c.name}，${c.gender}，${c.age} 岁（${c.year} 年）。\n'
      '出生地：$place\n'
      '人生目标：${c.goal}\n'
      '天赋：$talent\n'
      '当前状态：${kStatLabels.asMap().entries.map((e) => '${e.value} ${c.stats[kStatKeys[e.key]]}').join('、')}\n'
      '已经过去的人生：\n$hist\n\n'
      '请写下一章：从 ${c.age} 岁开始，往后推进 3 到 9 年'
      '（跨度由你判断，多数时候 5 年左右，重要转折可以短一些）。\n'
      '正文 150 到 220 字，概括这几年怎么过来的：发生了什么、遇到谁、'
      '生活怎样悄悄变了；不要按年份罗列，不要「这一年」开头的流水账，'
      '也不要从出生写起——直接写这一段。\n'
      '结尾必须停在一个真正需要决定的时刻，给 2 到 3 个有真实取舍的选项。'
      '输出 JSON：{"title":"四到八字的章节名","story":"本章叙述",'
      '"years":推进年数,"choices":[{"text":"选项","hint":"一句话说明代价或倾向"}]}。';
}

String buildResolveUser(LifeCharacter c, LifeEvent e, int choiceIndex) =>
    '角色：${c.name}，${e.startAge} 到 ${e.age} 岁这一章刚走到岔路口，时代：${c.era}。'
    '当前状态：${kStatLabels.asMap().entries.map((x) => '${x.value} ${c.stats[kStatKeys[x.key]]}').join('、')}\n'
    '这一章：${e.title} — ${e.story}\n'
    'TA 的选择：${e.choices[choiceIndex].text}\n\n'
    '请判定这个选择的后果，叙述 60 到 120 字（可以顺带交代之后一两年的变化），'
    '并给出六维属性变化。'
    '输出 JSON：{"outcome":"结果叙述","deltas":'
    '{"health":0,"mind":0,"charm":0,"wealth":0,"fame":0,"joy":0}}。'
    'deltas 为整数，单项 -30 到 30，有得必有失，不要让所有属性都上涨。';

String buildFinaleUser(LifeCharacter c) {
  final place = c.province.isEmpty
      ? ''
      : '，生于${c.city.isEmpty ? c.province : '${c.province}${c.city}'}';
  final talent =
      c.talentName.trim().isEmpty ? '' : '，天赋「${c.talentName}」';
  return '这是 ${c.name} 的一生：${c.gender}，${c.era}$place$talent，'
      '享年 ${c.age} 岁，目标「${c.goal}」。\n'
      '履历：\n${c.events.map((e) => '${e.spanLabel}岁 ${e.title}：${e.outcome}').join('\n')}\n'
      '最终状态：${kStatLabels.asMap().entries.map((x) => '${x.value} ${c.stats[kStatKeys[x.key]]}').join('、')}\n\n'
      '请写一段 150 到 250 字的人生总结（像传记末尾的评语，'
      '回望 TA 的选择与命运，温和但不粉饰），并在最后单独一行给出'
      '0 到 100 的整数评分。第一行写总结，第二行只写数字。';
}

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

  /// 生成下一章（未抉择）。年龄在这里推进：一章写完，人就长了几岁。
  Future<LifeEvent> nextEvent(LifeCharacter c, SeatLike conn,
      {CancelToken? cancel}) async {
    final pending = c.pending;
    if (pending != null) return pending;
    if (c.over) throw StateError('这一生已经结束了');
    // 先记下这一章的起点年龄，再让模型决定跨几年。
    final startAge = c.age;
    final raw = await _ask(
        conn, buildLifeSystem(c), buildEventUser(c), cancel: cancel);
    final e = parseEventJson(raw, startAge, c.birthYear + startAge);
    c.events.add(e);
    c.age = e.age;
    _emit();
    return e;
  }

  /// 结算当前章节的选择。年龄不在这里推进——章节开始时已经推进过，
  /// 这里只负责后果与属性。
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
