import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../services/feature_store.dart';
import '../services/mini_games.dart';
import '../services/model_source.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'feature_kit.dart';
import 'game_model_bar.dart';

/// 单个小游戏页。前五个纯本地，后两个走当前模型。
class MiniGameScreen extends StatefulWidget {
  const MiniGameScreen({super.key, required this.kind});

  final MiniGameKind kind;

  @override
  State<MiniGameScreen> createState() => _MiniGameScreenState();
}

class _MiniGameScreenState extends State<MiniGameScreen> {
  final FeatureStore store = FeatureStore();
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();

  // 抉择轮盘
  String? wheelResult;
  double wheelTurns = 0;

  // 猜数字
  GuessNumberGame? guess;
  String? guessHint;

  // 石头剪刀布
  int rpsWin = 0;
  int rpsLose = 0;
  int rpsDraw = 0;
  RpsMove? myMove;
  RpsMove? aiMove;

  // 每日一签
  bool fortuneRevealed = false;

  // 魔法八球
  int? eightBallAnswer;

  // AI 玩法
  final List<Map<String, String>> messages = [];
  final List<String> bubbles = [];
  bool aiBusy = false;
  String? aiNotice;
  String? secret;
  int questionsLeft = 20;
  CancelToken? cancel;

  bool get needsAi => miniGameNeedsAi(widget.kind);

  @override
  void initState() {
    super.initState();
    if (widget.kind == MiniGameKind.guess) guess = GuessNumberGame();
  }

  @override
  void dispose() {
    cancel?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  AppState get st => Provider.of<AppState>(context, listen: false);
  ModelChoice get model => gameModel ?? currentChatChoice(st.settings);
  ModelChoice? gameModel;

  // ------------------------------------------------------------------ 标题

  String get gameTitle {
    switch (widget.kind) {
      case MiniGameKind.wheel:
        return t('抉择轮盘');
      case MiniGameKind.guess:
        return t('猜数字');
      case MiniGameKind.rps:
        return t('石头剪刀布');
      case MiniGameKind.fortune:
        return t('每日一签');
      case MiniGameKind.eightBall:
        return t('魔法八球');
      case MiniGameKind.twentyQuestions:
        return t('二十问');
      case MiniGameKind.storyChain:
        return t('故事接龙');
    }
  }

  String get gameDesc {
    switch (widget.kind) {
      case MiniGameKind.wheel:
        return t('把纠结的选项都写进去，让轮盘替你做决定。');
      case MiniGameKind.guess:
        return t('我心里藏着一个 1 到 100 的数字，看你能几次猜中。');
      case MiniGameKind.rps:
        return t('和我来几局，纯靠运气，不花流量。');
      case MiniGameKind.fortune:
        return t('每天一支签，同一天不会变。图个乐子，别当真。');
      case MiniGameKind.eightBall:
        return t('心里默念一个问题，摇一摇，看它怎么回答。');
      case MiniGameKind.twentyQuestions:
        return t('我想好了一个东西，你用是非题在 20 次内猜出来。');
      case MiniGameKind.storyChain:
        return t('你一句我一句，让故事一直讲下去。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: featureAppBar(context, dark, title: gameTitle),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
            children: [
              featureCard(dark, [
                featureHint(dark, gameDesc),
              ]),
              if (needsAi) ...[
                GameModelBar(
                  dark: dark,
                  store: store,
                  onChanged: (m) {
                    if (mounted) setState(() => gameModel = m);
                  },
                ),
              ],
              _body(dark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool dark) {
    switch (widget.kind) {
      case MiniGameKind.wheel:
        return _wheel(dark);
      case MiniGameKind.guess:
        return _guess(dark);
      case MiniGameKind.rps:
        return _rps(dark);
      case MiniGameKind.fortune:
        return _fortune(dark);
      case MiniGameKind.eightBall:
        return _eightBall(dark);
      case MiniGameKind.twentyQuestions:
        return _aiChat(dark);
      case MiniGameKind.storyChain:
        return _aiChat(dark);
    }
  }

  // ---------------------------------------------------------------- 轮盘

  Widget _wheel(bool dark) {
    final options = parseWheelOptions(input.text);
    return featureCard(dark, [
      featureLabel(dark, t('候选选项')),
      TextField(
        controller: input,
        maxLines: 4,
        minLines: 2,
        style: ts(dark, size: 13),
        decoration: fieldDecoration(dark, hint: t('每行一个，或用逗号隔开')),
        onChanged: (_) => setState(() {}),
      ),
      featureHint(dark, '${options.length} ${t('个选项')}'),
      const SizedBox(height: 12),
      featurePrimary(
        dark: dark,
        label: t('转起来'),
        icon: Icons.casino_rounded,
        onPressed: options.length < 2
            ? null
            : () {
                final r = spinWheel(options);
                if (r == null) return;
                HapticFeedback.mediumImpact();
                setState(() {
                  wheelResult = r;
                  wheelTurns += 1;
                });
              },
      ),
      if (wheelResult != null) ...[
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Container(
            key: ValueKey('$wheelResult-$wheelTurns'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            decoration: BoxDecoration(
              color: C.brand.withOpacity(0.10),
              borderRadius: BorderRadius.circular(D.r),
              border: Border.all(color: C.brand.withOpacity(0.28), width: 0.9),
            ),
            child: Column(
              children: [
                Text(t('就选这个'), style: meta(dark, size: 11.5)),
                const SizedBox(height: 8),
                Text(wheelResult!,
                    textAlign: TextAlign.center,
                    style: display(dark, size: 22)),
              ],
            ),
          ),
        ),
      ],
    ]);
  }

  // -------------------------------------------------------------- 猜数字

  Widget _guess(bool dark) {
    final g = guess!;
    return featureCard(dark, [
      featureLabel(dark, t('猜一个 1 到 100 的数字')),
      TextField(
        controller: input,
        keyboardType: TextInputType.number,
        style: ts(dark, size: 14),
        decoration: fieldDecoration(dark, hint: '1 - 100'),
        onSubmitted: (_) => _doGuess(),
      ),
      const SizedBox(height: 12),
      featurePrimary(
        dark: dark,
        label: g.done ? t('再玩一局') : t('猜！'),
        icon: g.done ? Icons.refresh_rounded : Icons.search_rounded,
        onPressed: _doGuess,
      ),
      if (guessHint != null) ...[
        const SizedBox(height: 14),
        featureNotice(dark, guessHint!, error: !g.done),
      ],
      featureHint(dark, '${t('已猜')} ${g.tries} ${t('次')}'),
    ]);
  }

  void _doGuess() {
    final g = guess!;
    if (g.done) {
      setState(() {
        guess = GuessNumberGame();
        guessHint = null;
        input.clear();
      });
      return;
    }
    final n = int.tryParse(input.text.trim());
    if (n == null) {
      setState(() => guessHint = t('请输入 1 到 100 的整数'));
      return;
    }
    final r = g.guess(n);
    if (r == null) {
      setState(() => guessHint = t('请输入 1 到 100 的整数'));
      return;
    }
    setState(() {
      if (r == 0) {
        guessHint = '${t('猜中了！就是')} ${g.target}，${t('一共用了')} ${g.tries} ${t('次')}。';
      } else if (r < 0) {
        guessHint = '${t('小了')} ↑';
      } else {
        guessHint = '${t('大了')} ↓';
      }
      input.clear();
    });
  }

  // ---------------------------------------------------------- 石头剪刀布

  Widget _rps(bool dark) {
    return featureCard(dark, [
      featureLabel(dark, t('出拳')),
      Row(
        children: [
          for (final m in RpsMove.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 7),
                child: _rpsButton(dark, m),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      if (myMove != null && aiMove != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: insetBox(dark),
          child: Column(
            children: [
              Text('${t('你')} ${t(rpsLabel(myMove!))}  ·  ${t('我')} ${t(rpsLabel(aiMove!))}',
                  style: ts(dark, size: 13)),
              const SizedBox(height: 7),
              Text(_rpsResultText(),
                  style: display(dark, size: 18)),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _score(dark, t('胜'), rpsWin, C.ok),
          _score(dark, t('负'), rpsLose, C.danger),
          _score(dark, t('平'), rpsDraw, dark ? C.dInk3 : C.ink3),
        ],
      ),
    ]);
  }

  String rpsLabel(RpsMove m) {
    switch (m) {
      case RpsMove.rock:
        return '石头';
      case RpsMove.scissors:
        return '剪刀';
      case RpsMove.paper:
        return '布';
    }
  }

  String _rpsResultText() {
    final r = rpsJudge(myMove!, aiMove!);
    if (r > 0) return t('你赢了');
    if (r < 0) return t('我赢了');
    return t('平局');
  }

  Widget _score(bool dark, String label, int v, Color c) => Column(
        children: [
          Text('$v', style: display(dark, size: 20)),
          const SizedBox(height: 2),
          Text(label, style: meta(dark, size: 11, color: c)),
        ],
      );

  Widget _rpsButton(bool dark, RpsMove m) {
    final icons = {
      RpsMove.rock: Icons.back_hand_rounded,
      RpsMove.scissors: Icons.content_cut_rounded,
      RpsMove.paper: Icons.panorama_horizontal_rounded,
    };
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: BorderSide(color: borderOf(dark)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
      ),
      onPressed: () {
        final ai = randomRps();
        final r = rpsJudge(m, ai);
        HapticFeedback.selectionClick();
        setState(() {
          myMove = m;
          aiMove = ai;
          if (r > 0) {
            rpsWin++;
          } else if (r < 0) {
            rpsLose++;
          } else {
            rpsDraw++;
          }
        });
      },
      child: Column(
        children: [
          Icon(icons[m], size: 20, color: dark ? C.dInk2 : C.ink2),
          const SizedBox(height: 5),
          Text(t(rpsLabel(m)), style: ts(dark, size: 11.5)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 每日一签

  Widget _fortune(bool dark) {
    final idx = fortuneIndex(DateTime.now(), kFortuneTexts.length);
    final f = kFortuneTexts[idx];
    return featureCard(dark, [
      featureLabel(dark, t('今日签')),
      if (!fortuneRevealed)
        featureEmpty(dark, Icons.auto_awesome_rounded, t('静一静心，点下面抽签'))
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
          decoration: insetBox(dark),
          child: Column(
            children: [
              Text(t(f.$1),
                  style: display(dark, size: 24)),
              const SizedBox(height: 12),
              Text(t(f.$2),
                  textAlign: TextAlign.center,
                  style: ts(dark, size: 13, height: 1.7)),
            ],
          ),
        ),
      const SizedBox(height: 14),
      featurePrimary(
        dark: dark,
        label: fortuneRevealed ? t('再看看') : t('抽一支签'),
        icon: Icons.auto_awesome_rounded,
        onPressed: () {
          HapticFeedback.mediumImpact();
          setState(() => fortuneRevealed = !fortuneRevealed);
        },
      ),
      featureHint(dark, t('同一天抽到的签不会变，明天再来会有新签。')),
    ]);
  }

  // -------------------------------------------------------------- 魔法八球

  Widget _eightBall(bool dark) {
    return featureCard(dark, [
      featureLabel(dark, t('心里默念一个问题')),
      TextField(
        controller: input,
        maxLines: 2,
        style: ts(dark, size: 13),
        decoration: fieldDecoration(dark, hint: t('例如：今天适合开始新计划吗？')),
      ),
      const SizedBox(height: 12),
      featurePrimary(
        dark: dark,
        label: t('摇一摇'),
        icon: Icons.help_outline_rounded,
        onPressed: () {
          HapticFeedback.mediumImpact();
          setState(() => eightBallAnswer =
              eightBallIndex(kEightBallTexts.length, random: Random()));
        },
      ),
      if (eightBallAnswer != null) ...[
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Container(
            key: ValueKey(eightBallAnswer),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
            decoration: BoxDecoration(
              color: C.brand.withOpacity(0.09),
              borderRadius: BorderRadius.circular(D.r),
              border: Border.all(color: C.brand.withOpacity(0.26), width: 0.9),
            ),
            child: Text(t(kEightBallTexts[eightBallAnswer!]),
                textAlign: TextAlign.center,
                style: display(dark, size: 18)),
          ),
        ),
      ],
    ]);
  }

  // ------------------------------------------------------------- AI 对话玩法

  Widget _aiChat(bool dark) {
    return featureCard(dark, [
      Row(
        children: [
          Expanded(child: featureLabel(dark, t('对话'))),
          featureOutline(
            dark: dark,
            label: t('重新开始'),
            icon: Icons.refresh_rounded,
            onPressed: aiBusy ? null : _restartAi,
          ),
        ],
      ),
      if (widget.kind == MiniGameKind.twentyQuestions)
        featureHint(dark, '${t('剩余提问')} $questionsLeft'),
      if (aiNotice != null) featureNotice(dark, aiNotice!, error: true),
      if (messages.isEmpty && !aiBusy)
        featureEmpty(dark, Icons.chat_bubble_outline_rounded,
            t('点开始，由模型先说第一句。'))
      else
        for (var i = 0; i < messages.length; i++) _bubble(dark, messages[i]),
      if (aiBusy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: input,
        maxLines: 2,
        minLines: 1,
        style: ts(dark, size: 13),
        decoration: fieldDecoration(dark, hint: _aiHint()),
        onSubmitted: (_) => _sendAi(),
      ),
      const SizedBox(height: 10),
      featurePrimary(
        dark: dark,
        label: messages.isEmpty ? t('开始') : t('发送'),
        icon: messages.isEmpty ? Icons.play_arrow_rounded : Icons.send_rounded,
        busy: aiBusy,
        onPressed: aiBusy ? null : _sendAi,
      ),
      featureHint(dark, t('AI 玩法会调用你所选的模型，按实际用量计费。')),
    ]);
  }

  String _aiHint() => widget.kind == MiniGameKind.twentyQuestions
      ? t('用一个是非题提问…')
      : t('写下接下来发生的事…');

  Widget _bubble(bool dark, Map<String, String> m) {
    final mine = m['role'] == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: mine ? C.brand.withOpacity(0.13) : fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(color: hairOf(dark), width: 0.7),
        ),
        child: Text(m['content'] ?? '',
            style: ts(dark, size: 12.5, height: 1.55)),
      ),
    );
  }

  void _restartAi() {
    cancel?.cancel();
    setState(() {
      messages.clear();
      secret = null;
      questionsLeft = 20;
      aiNotice = null;
      input.clear();
    });
  }

  Future<void> _sendAi() async {
    final text = input.text.trim();
    if (aiBusy) return;
    final m = model;
    if (m.model.trim().isEmpty ||
        (m.baseUrl.trim().startsWith('https://api.openai.com') &&
            m.apiKey.trim().isEmpty)) {
      setState(() => aiNotice = t('尚未配置接口，请先到设置里填好连接与模型。'));
      return;
    }
    final first = messages.isEmpty;
    if (!first && text.isEmpty) return;
    if (widget.kind == MiniGameKind.twentyQuestions && questionsLeft <= 0) {
      setState(() => aiNotice = t('20 次提问用完了，点重新开始再来一局。'));
      return;
    }

    // 首局：二十问先由模型在心里定一个东西，故事接龙让用户给主题。
    if (first) {
      if (widget.kind == MiniGameKind.twentyQuestions) {
        secret = kTwentySecrets[Random().nextInt(kTwentySecrets.length)];
      } else if (text.isEmpty) {
        setState(() => aiNotice = t('先给故事起个主题吧'));
        return;
      }
    }

    final system = widget.kind == MiniGameKind.twentyQuestions
        ? twentyQuestionsSystem(secret ?? '')
        : storyChainSystem();
    final opening = widget.kind == MiniGameKind.twentyQuestions
        ? twentyQuestionsOpening()
        : storyChainOpening(text);

    setState(() {
      aiNotice = null;
      aiBusy = true;
      if (first) {
        messages.add({'role': 'user', 'content': opening});
      } else {
        messages.add({'role': 'user', 'content': text});
        if (widget.kind == MiniGameKind.twentyQuestions) questionsLeft--;
      }
      input.clear();
    });
    cancel = CancelToken();
    try {
      final raw = await miniGameComplete(
        complete: (req, {CancelToken? cancel}) =>
            st.llm.complete(req, cancel: cancel),
        baseUrl: m.baseUrl,
        apiKey: m.apiKey,
        model: m.model,
        system: system,
        history: messages,
      );
      final answer = raw.trim().isEmpty ? t('（模型没有回复）') : raw.trim();
      if (!mounted) return;
      setState(() => messages.add({'role': 'assistant', 'content': answer}));
      if (widget.kind == MiniGameKind.twentyQuestions &&
          normalizeTwentyAnswer(answer) == 'correct') {
        setState(() => aiNotice = '${t('猜对了！答案是')} ${t(secret ?? '')}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => aiNotice = '${t('模型调用失败')}：$e');
    } finally {
      cancel = null;
      if (mounted) setState(() => aiBusy = false);
    }
  }
}

// ---------------------------------------------------------------- 本地文案库

/// 签级 + 签文。t() 包的是中文原句，词表里逐条登记。
const List<(String, String)> kFortuneTexts = [
  ('上上签', '云开月正明，所行皆顺路。今天适合把一直想做的事往前推一步。'),
  ('上签', '风渐软，水渐平。手上的事会慢慢有回音，不必急着催。'),
  ('中签', '有得有失，平常心最稳。今天宜把节奏放慢一点。'),
  ('平签', '不进不退，也是一日。守住眼前，就是守住运气。'),
  ('小吉', '一点小惊喜正在路上，留意身边不显眼的机会。'),
  ('待时', '眼下还不是最好的时机，先攒力气，等风来。'),
  ('顺签', '想不通的事，出去走一圈大概就有答案了。'),
];

const List<String> kEightBallTexts = [
  '答案是肯定的。',
  '看起来不错，放手去做。',
  '现在还看不清，再等等。',
  '别急着决定，先睡一觉。',
  '大概率可以，但留个后手。',
  '换个角度想想会更好。',
  '这次恐怕不行。',
  '宇宙说：再问一次。',
];

const List<String> kTwentySecrets = [
  '一只猫',
  '埃菲尔铁塔',
  '一把雨伞',
  '月亮',
  '一本书',
  '一杯咖啡',
  '自行车',
  '钢琴',
  '长城',
  '冰淇淋',
];
