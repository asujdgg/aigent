import 'dart:convert';
import 'package:dio/dio.dart';
import 'llm_client.dart';

/// 多模型圆桌会议。
///
/// 设计要点：
/// - 每个席位自带 baseUrl / apiKey / model，可以来自不同连接、不同厂商；
/// - 后发言的席位能看到前面席位的观点，形成真正的讨论而非并行问答；
/// - 单个席位失败只记在本条发言上，不拖垮整场会议；
/// - 所有 prompt 构造与文本解析都是纯函数，便于离线回归测试。

enum MeetingPhase { idle, outlining, discussing, summarizing, done, failed }

/// 五种默认立场：让同一个模型换个角色也能给出不同角度，
/// 即使用户只有一条连接也能凑出一场有分歧的会。
const List<String> kDefaultRoles = [
  '主持人 · 负责聚焦议题、平衡各方、推进共识',
  '分析者 · 用事实、数据与逻辑拆解问题',
  '质疑者 · 专挑假设漏洞与潜在风险',
  '创意者 · 提供跳出框架的 alternative 方案',
  '务实派 · 关注落地成本、优先级与执行步骤',
];

const List<String> kDefaultSeatNames = [
  '主持人',
  '分析者',
  '质疑者',
  '创意者',
  '务实派',
];

/// 一个参会席位。
class Seat {
  String id;
  String name;
  String role;
  String baseUrl;
  String apiKey;
  String model;
  bool enabled;

  /// 选中的运营商（连接）名，仅用于界面展示；不参与请求。
  String providerName;

  Seat({
    required this.id,
    this.name = '',
    this.role = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.enabled = true,
    this.providerName = '',
  });

  bool get usable => enabled && model.trim().isNotEmpty;

  String get displayName =>
      name.trim().isEmpty ? (model.trim().isEmpty ? '未命名' : model.trim()) : name.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'baseUrl': baseUrl,
        'model': model,
        'enabled': enabled,
        'providerName': providerName,
        // 密钥不落盘：下次进入页面时按 baseUrl 从当前连接重新补全。
      };

  factory Seat.fromJson(Map<dynamic, dynamic> j) => Seat(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        baseUrl: (j['baseUrl'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        enabled: j['enabled'] != false,
        providerName: (j['providerName'] ?? '').toString(),
      );

  Seat copy() => Seat(
        id: id,
        name: name,
        role: role,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        enabled: enabled,
        providerName: providerName,
      );
}

/// 一次发言。
class MeetingTurn {
  final String seatId;
  final String seatName;
  final String model;
  final int round;
  String content;
  String? error;
  final DateTime at;

  MeetingTurn({
    required this.seatId,
    required this.seatName,
    required this.model,
    required this.round,
    this.content = '',
    this.error,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  bool get ok => error == null && content.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'seatId': seatId,
        'seatName': seatName,
        'model': model,
        'round': round,
        'content': content,
        if (error != null) 'error': error,
        'at': at.millisecondsSinceEpoch,
      };

  factory MeetingTurn.fromJson(Map<dynamic, dynamic> j) => MeetingTurn(
        seatId: (j['seatId'] ?? '').toString(),
        seatName: (j['seatName'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        round: (j['round'] as num?)?.toInt() ?? 1,
        content: (j['content'] ?? '').toString(),
        error: j['error']?.toString(),
        at: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      );
}

/// 一场会议（含全部发言、大纲与纪要）。
class Meeting {
  final String id;
  String topic;
  String agenda;
  List<Seat> seats;
  int rounds;
  final List<MeetingTurn> turns;
  String summary;
  MeetingPhase phase;
  String status;
  String? error;
  final DateTime createdAt;

  Meeting({
    required this.id,
    this.topic = '',
    this.agenda = '',
    List<Seat>? seats,
    this.rounds = 2,
    List<MeetingTurn>? turns,
    this.summary = '',
    this.phase = MeetingPhase.idle,
    this.status = '',
    this.error,
    DateTime? createdAt,
  })  : seats = seats ?? <Seat>[],
        turns = turns ?? <MeetingTurn>[],
        createdAt = createdAt ?? DateTime.now();

  List<Seat> get activeSeats => seats.where((s) => s.usable).toList();

  bool get running => phase == MeetingPhase.outlining ||
      phase == MeetingPhase.discussing ||
      phase == MeetingPhase.summarizing;

  /// 导出 Markdown 会议纪要。纯函数式，离线可测。
  String toMarkdown() {
    final b = StringBuffer();
    b.writeln('# ${topic.trim().isEmpty ? '圆桌会议' : topic.trim()}');
    b.writeln();
    b.writeln('> ${_ymd(createdAt)} · ${activeSeats.length} 位参会者 · '
        '$rounds 轮讨论');
    b.writeln();
    if (agenda.trim().isNotEmpty) {
      b.writeln('## 会议大纲');
      b.writeln();
      b.writeln(agenda.trim());
      b.writeln();
    }
    if (turns.isNotEmpty) {
      b.writeln('## 讨论记录');
      b.writeln();
      int? lastRound;
      for (final t in turns) {
        if (t.round != lastRound) {
          lastRound = t.round;
          b.writeln('### 第 $lastRound 轮');
          b.writeln();
        }
        b.writeln('**${t.seatName}**（${t.model}）');
        b.writeln();
        b.writeln(t.ok ? t.content.trim() : '（未发言：${t.error ?? '无内容'}）');
        b.writeln();
      }
    }
    if (summary.trim().isNotEmpty) {
      b.writeln('## 会议结论');
      b.writeln();
      b.writeln(summary.trim());
      b.writeln();
    }
    b.writeln('---');
    b.writeln('由 Aigent 多模型圆桌会议自动生成，请核实关键结论后使用。');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'agenda': agenda,
        'seats': [for (final s in seats) s.toJson()],
        'rounds': rounds,
        'turns': [for (final t in turns) t.toJson()],
        'summary': summary,
        'phase': phase.name,
        'status': status,
        if (error != null) 'error': error,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Meeting.fromJson(Map<dynamic, dynamic> j) => Meeting(
        id: (j['id'] ?? '').toString(),
        topic: (j['topic'] ?? '').toString(),
        agenda: (j['agenda'] ?? '').toString(),
        seats: j['seats'] is List
            ? (j['seats'] as List)
                .whereType<Map>()
                .map((e) => Seat.fromJson(e))
                .toList()
            : <Seat>[],
        rounds: (j['rounds'] as num?)?.toInt() ?? 2,
        turns: j['turns'] is List
            ? (j['turns'] as List)
                .whereType<Map>()
                .map((e) => MeetingTurn.fromJson(e))
                .toList()
            : <MeetingTurn>[],
        summary: (j['summary'] ?? '').toString(),
        phase: MeetingPhase.values.firstWhere(
          (p) => p.name == (j['phase'] ?? '').toString(),
          orElse: () => MeetingPhase.idle,
        ),
        status: (j['status'] ?? '').toString(),
        error: j['error']?.toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      );

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 从模型自由文本里解析议程行。容忍编号、Markdown 标题、项目符号。
List<String> parseAgenda(String raw, {int max = 6}) {
  final out = <String>[];
  final seen = <String>{};
  for (final line in raw.split('\n')) {
    var s = line.trim();
    if (s.isEmpty) continue;
    s = s
        .replaceAll(RegExp(r'^#{1,4}\s*'), '')
        .replaceAll(RegExp(r'^\s*(?:\d+[\.、）)]?|[-*•·])\s*'), '')
        .replaceAll(RegExp(r'^\*\*|\*\*$'), '')
        .trim();
    if (s.length < 2 || s.length > 90) continue;
    // 带句末标点的长句是解释性正文，不是一条议程（模型常爱补一句总结）。
    if (s.length > 40 && RegExp(r'[。！？.!?]$').hasMatch(s)) continue;
    // 过滤「以下是大纲」这类引导句。
    if (RegExp(r'^(以下|本次|会议|大纲|议程|here|agenda)', caseSensitive: false)
            .hasMatch(s) &&
        s.length < 12) {
      continue;
    }
    if (seen.add(s)) out.add(s);
    if (out.length >= max) break;
  }
  return out;
}

/// 把历史发言压成一段给下一位参会者看的上下文。
/// 只取最近 [limit] 条，每条截到 [perTurn] 字，避免长会把上下文撑爆。
String buildDiscussionContext(List<MeetingTurn> turns,
    {int limit = 10, int perTurn = 260}) {
  final recent = turns.length > limit
      ? turns.sublist(turns.length - limit)
      : turns;
  final ok = recent.where((t) => t.ok).toList();
  if (ok.isEmpty) return '（尚无其他人发言，你是第一位。）';
  final b = StringBuffer();
  for (final t in ok) {
    final c = t.content.trim();
    b.writeln('【${t.seatName} · ${t.model} · 第${t.round}轮】'
        '${c.length > perTurn ? '${c.substring(0, perTurn)}…' : c}');
  }
  return b.toString();
}

String buildOutlineUser(String topic, int seatCount) =>
    '会议议题：$topic\n\n'
    '请为这场有 $seatCount 位不同立场的参会者的圆桌会议拟定一份讨论大纲，'
    '输出 4 到 6 条，每行一条，不要编号、不要解释、不要额外文字。'
    '条目应覆盖：问题界定、关键事实、不同立场的分歧点、风险与约束、'
    '可执行的下一步。请与议题使用同一种语言。';

String buildSeatSystem(Seat s) =>
    '你正在参加一场多模型圆桌会议。你的身份是「${s.displayName}」。'
    '你的立场与职责：${s.role.trim().isEmpty ? '就议题发表独立见解' : s.role.trim()}。'
    '请始终保持这个人设与立场，用与议题相同的语言发言，'
    '直接、具体、有信息量，不要客套，不要复述议题，不要使用 Markdown 标题。'
    '篇幅控制在 120 到 260 字。';

String buildSeatUser(Meeting m, Seat s, int round, int total,
        List<MeetingTurn> history) =>
    '会议议题：${m.topic}\n\n'
    '会议大纲：\n${m.agenda.trim().isEmpty ? '（无）' : m.agenda.trim()}\n\n'
    '前面参会者的发言：\n${buildDiscussionContext(history)}\n\n'
    '现在是第 $round / $total 轮，轮到你（${s.displayName}）发言。'
    '${round == 1 ? '请给出你的核心判断与主要理由。' : '请回应前面观点中你赞同或反对的部分，并提出新的推进意见，避免重复自己上一轮的话。'}';

String buildSummaryUser(Meeting m) =>
    '会议议题：${m.topic}\n\n'
    '全部发言记录：\n${buildDiscussionContext(m.turns, limit: 40, perTurn: 420)}\n\n'
    '你是会议主持人，请写一份简明的会议结论，包含三段：\n'
    '1. 共识：各方一致认可的判断；\n'
    '2. 分歧：仍未达成一致的关键点，并说明各自理由；\n'
    '3. 建议：按优先级给出 3 条可执行的下一步。\n'
    '用小标题分段，不要复述整段发言，不要多余客套，与议题使用同一种语言。';

typedef CompleteFn = Future<String> Function(LlmRequest req,
    {CancelToken? cancel});

/// 会议编排器。
class RoundtableEngine {
  RoundtableEngine({LlmClient? llm, CompleteFn? complete, this.onChanged})
      : _llm = llm ?? LlmClient(),
        _complete = complete;

  final LlmClient _llm;
  final CompleteFn? _complete;
  final void Function()? onChanged;

  Future<String> _ask(Seat s, String system, String user,
      {int maxTokens = 900, CancelToken? cancel}) {
    final req = LlmRequest(
      baseUrl: s.baseUrl,
      apiKey: s.apiKey,
      model: s.model,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      maxTokens: maxTokens,
      temperature: 0.72,
      topP: 0.94,
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

  void _check(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw StateError('已取消');
  }

  /// 只生成大纲，不启动讨论。用户可随后手动修改。
  Future<String> outline(Meeting m, {CancelToken? cancel}) async {
    final host = m.activeSeats.isEmpty ? null : m.activeSeats.first;
    if (host == null) throw StateError('至少需要一个可用的参会模型');
    m.phase = MeetingPhase.outlining;
    m.status = '正在拟定大纲';
    _emit();
    try {
      // 已取消时一次请求都不发：否则用户点停止后还会白白消耗一次调用。
      _check(cancel);
      final raw = await _ask(host,
          '你是圆桌会议的主持人助手，只输出大纲条目，不解释、不寒暄。',
          buildOutlineUser(m.topic, m.activeSeats.length),
          maxTokens: 600,
          cancel: cancel);
      final lines = parseAgenda(raw);
      m.agenda = lines.join('\n');
      m.status = '大纲已就绪';
      _emit();
      return m.agenda;
    } catch (e) {
      m.status = '大纲生成失败';
      m.error = '$e';
      _emit();
      rethrow;
    } finally {
      if (m.phase == MeetingPhase.outlining) {
        m.phase = MeetingPhase.idle;
        _emit();
      }
    }
  }

  /// 跑完整场会议：逐轮逐个席位发言，最后主持人汇总。
  /// 若 [m.agenda] 为空且 [autoOutline] 为真，会先自动补一份大纲。
  Future<void> run(Meeting m,
      {CancelToken? cancel, bool autoOutline = true}) async {
    final seats = m.activeSeats;
    if (seats.isEmpty) throw StateError('至少需要一个可用的参会模型');
    if (m.topic.trim().isEmpty) throw StateError('请先填写会议议题');
    if (m.running) return;

    m.error = null;
    m.summary = '';
    m.turns.clear();
    _emit();

    try {
      if (autoOutline && m.agenda.trim().isEmpty) {
        await outline(m, cancel: cancel);
      }
      _check(cancel);

      m.phase = MeetingPhase.discussing;
      for (var round = 1; round <= m.rounds.clamp(1, 3); round++) {
        for (final s in seats) {
          _check(cancel);
          m.status = '第 $round/${m.rounds} 轮 · ${s.displayName} 发言中';
          _emit();
          final turn = MeetingTurn(
            seatId: s.id,
            seatName: s.displayName,
            model: s.model,
            round: round,
            content: '',
          );
          m.turns.add(turn);
          _emit();
          try {
            turn.content = (await _ask(
              s,
              buildSeatSystem(s),
              buildSeatUser(m, s, round, m.rounds,
                  m.turns.sublist(0, m.turns.length - 1)),
              cancel: cancel,
            ))
                .trim();
            if (turn.content.isEmpty) turn.error = '模型返回空内容';
          } catch (e) {
            turn.error = '$e';
          }
          _emit();
        }
      }

      _check(cancel);
      m.phase = MeetingPhase.summarizing;
      m.status = '主持人正在整理会议结论';
      _emit();
      try {
        m.summary = (await _ask(
          seats.first,
          '你是圆桌会议主持人，善于把多方观点提炼成清晰、可执行的结论。',
          buildSummaryUser(m),
          maxTokens: 1400,
          cancel: cancel,
        ))
            .trim();
      } catch (e) {
        m.summary = '结论生成失败：$e';
      }
      m.phase = MeetingPhase.done;
      m.status = '会议结束';
    } on StateError catch (e) {
      m.phase = MeetingPhase.failed;
      m.status = '$e';
      m.error = '$e';
    } catch (e) {
      m.phase = MeetingPhase.failed;
      m.status = '会议中断';
      m.error = '$e';
    } finally {
      _emit();
    }
  }
}

/// 从当前连接配置里凑出 3~5 个「不同模型」的默认席位。
///
/// 优先取多条连接各自的模型；连接不够时，从该连接缓存的模型列表里
/// 继续取不同 ID，保证「一条连接也能开五模型会议」。
List<Seat> defaultSeats({
  required String fallbackBaseUrl,
  required String fallbackApiKey,
  required String fallbackModel,
  required List<({String baseUrl, String apiKey, String model})> candidates,
  int count = 5,
}) {
  final picked = <String>{};
  final out = <Seat>[];
  void add(String base, String key, String model) {
    final m = model.trim();
    if (m.isEmpty) return;
    final sig = '$base|$m';
    if (!picked.add(sig)) return;
    if (out.length >= count) return;
    final i = out.length;
    out.add(Seat(
      id: 'seat_$i',
      name: kDefaultSeatNames[i % kDefaultSeatNames.length],
      role: kDefaultRoles[i % kDefaultRoles.length],
      baseUrl: base.trim().isEmpty ? fallbackBaseUrl : base.trim(),
      apiKey: key,
      model: m,
    ));
  }

  if (fallbackModel.trim().isNotEmpty) {
    add(fallbackBaseUrl, fallbackApiKey, fallbackModel);
  }
  for (final c in candidates) {
    add(c.baseUrl, c.apiKey, c.model);
  }
  return out;
}

/// 便于日志与导出的短名。
String seatLabel(Seat s) => '${s.displayName} · ${s.model}';

String meetingJson(Meeting m) => jsonEncode(m.toJson());
