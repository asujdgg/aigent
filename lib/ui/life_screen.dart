import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../i18n.dart';
import '../services/feature_store.dart';
import '../services/life_sim.dart';
import '../services/model_source.dart';
import '../services/region_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'feature_kit.dart';
import 'game_model_bar.dart';

/// 模拟人生页：创建角色 → AI 生成事件与抉择 → 结算属性 → 传记收尾。
class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  late AppState st;
  final FeatureStore store = FeatureStore();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController goalCtrl = TextEditingController();
  final ScrollController scroll = ScrollController();

  late LifeEngine engine;
  LifeCharacter? life;
  List<LifeCharacter> saves = [];
  CancelToken? cancel;
  Timer? saveTimer;
  bool booting = true;
  bool busy = false;
  bool showTimeline = false;
  String? notice;

  /// 本局使用的模型。null 时等价于「跟随当前对话」，由 GameModelBar 回调赋值。
  ModelChoice? gameModel;

  // 创建表单
  String gender = '女';
  String era = kEraOptions.first;
  String goal = kGoalOptions.first;
  String province = '';
  String city = '';

  /// 开局抽签结果。null 表示还没抽——没抽不能开始。
  CharacterRoll? roll;

  @override
  void initState() {
    super.initState();
    st = Provider.of<AppState>(context, listen: false);
    engine = LifeEngine(llm: st.llm, onChanged: _onEngineChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    cancel?.cancel();
    nameCtrl.dispose();
    goalCtrl.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    final c = life;
    if (c == null) return;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), () async {
      saves = await store.upsertLife(c);
      if (mounted) setState(() {});
    });
  }

  Future<void> _boot() async {
    try {
      saves = await store.loadLives();
    } catch (_) {}
    if (!mounted) return;
    setState(() => booting = false);
  }

  ModelChoice get model =>
      gameModel ?? currentChatChoice(st.settings);

  SeatLike get conn {
    final m = model;
    return SeatLike(
      baseUrl: m.baseUrl,
      apiKey: m.apiKey,
      model: m.model,
    );
  }

  bool get configured =>
      model.apiKey.trim().isNotEmpty ||
      !model.baseUrl.startsWith('https://api.openai.com');

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: featureAppBar(context, dark,
          title: t('模拟人生'),
          actions: [
            featureRoundButton(dark, Icons.bookmarks_rounded,
                () => _openSaves(dark),
                tooltip: t('人生存档')),
            featureRoundButton(dark, Icons.add_rounded, _reset,
                tooltip: t('新的人生')),
          ]),
      body: booting
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (notice != null)
                        featureNotice(dark, notice!, error: busy == false && notice!.contains('失败')),
                      GameModelBar(
                        dark: dark,
                        store: store,
                        onChanged: (m) {
                          if (mounted) setState(() => gameModel = m);
                        },
                      ),
                      if (!configured)
                        featureNotice(dark, t('尚未配置接口，请先到设置里填好连接与模型。')),
                      if (life == null)
                        _createCard(dark)
                      else ...[
                        _statusCard(dark, life!),
                        if (life!.ended)
                          _finaleCard(dark, life!)
                        else ...[
                          _eventCard(dark, life!),
                          const SizedBox(height: 4),
                          featureOutline(
                              dark: dark,
                              label: t('结束这一生'),
                              icon: Icons.favorite_border_rounded,
                              onPressed: busy ? null : _finish),
                        ],
                        _timelineCard(dark, life!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ------------------------------------------------------------------ 创建

  Widget _createCard(bool dark) => featureCard(dark, [
        featureLabel(dark, t('创建角色')),
        TextField(
          controller: nameCtrl,
          style: ts(dark, size: 13.5),
          decoration: fieldDecoration(
            dark,
            hint: t('给 TA 起个名字'),
            suffix: IconButton(
              icon: Icon(Icons.casino_rounded,
                  size: 17, color: dark ? C.dInk3 : C.ink3),
              onPressed: () => nameCtrl.text = _randomName(),
            ),
          ),
        ),
        featureHint(dark, t('留空将自动取名。')),
        const SizedBox(height: 14),
        Text(t('性别'), style: sectionTitle(dark)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final g in ['女', '男', '其他'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t(g), style: ts(dark, size: 12)),
                  selected: gender == g,
                  showCheckmark: false,
                  backgroundColor: fieldOf(dark),
                  selectedColor: C.brand.withOpacity(0.14),
                  side: BorderSide(
                      color: gender == g ? C.brand : hairOf(dark), width: 0.8),
                  onSelected: (_) => setState(() => gender = g),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(t('出生地'), style: sectionTitle(dark)),
        const SizedBox(height: 8),
        _regionRow(dark),
        const SizedBox(height: 14),
        Text(t('时代背景'), style: sectionTitle(dark)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final e in kEraOptions)
              ChoiceChip(
                label: Text(t(e), style: ts(dark, size: 11.5)),
                selected: era == e,
                showCheckmark: false,
                backgroundColor: fieldOf(dark),
                selectedColor: C.brand.withOpacity(0.14),
                side: BorderSide(
                    color: era == e ? C.brand : hairOf(dark), width: 0.8),
                onSelected: (_) => setState(() => era = e),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(t('人生目标'), style: sectionTitle(dark)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final g in kGoalOptions)
              ChoiceChip(
                label: Text(t(g), style: ts(dark, size: 11.5)),
                selected: goal == g,
                showCheckmark: false,
                backgroundColor: fieldOf(dark),
                selectedColor: C.brand.withOpacity(0.14),
                side: BorderSide(
                    color: goal == g ? C.brand : hairOf(dark), width: 0.8),
                onSelected: (_) => setState(() => goal = g),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: goalCtrl,
          style: ts(dark, size: 12.5),
          decoration: fieldDecoration(dark, hint: t('也可以自己写一个目标')),
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: hairOf(dark)),
        const SizedBox(height: 14),
        featureLabel(dark, t('天赋抽签')),
        featureHint(dark, t('一局只有一次。抽到什么，这一生就从哪里起步。')),
        const SizedBox(height: 10),
        if (roll == null)
          featureOutline(
              dark: dark,
              label: t('抽取天赋'),
              icon: Icons.casino_rounded,
              onPressed: _roll)
        else
          _rollCard(dark, roll!),
        const SizedBox(height: 18),
        featurePrimary(
            dark: dark,
            label: t('开始这一生'),
            icon: Icons.auto_stories_rounded,
            busy: busy,
            onPressed: _create),
        const SizedBox(height: 6),
        featureHint(dark, t('所有剧情由你配置的模型实时生成，只保存在本机。')),
      ]);

  Widget _regionRow(bool dark) => InkWell(
        borderRadius: BorderRadius.circular(D.r),
        onTap: _pickRegion,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: fieldOf(dark),
            borderRadius: BorderRadius.circular(D.r),
            border: Border.all(color: borderOf(dark), width: 0.9),
          ),
          child: Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 17, color: dark ? C.dInk3 : C.ink3),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  province.isEmpty ? t('选择出生地') : regionLabel(province, city),
                  style: ts(dark, size: 13).copyWith(
                      color: province.isEmpty
                          ? (dark ? C.dInk3 : C.ink3)
                          : (dark ? C.dInk : C.ink)),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: dark ? C.dInk3 : C.ink3),
            ],
          ),
        ),
      );

  /// 抽签结果卡：稀有度 + 天赋 + 六维，并在最强项上打星。
  Widget _rollCard(bool dark, CharacterRoll r) {
    final colors = [
      C.ok,
      C.brand,
      const Color(0xFFE0708A),
      const Color(0xFFD9A441),
      const Color(0xFF8A73D6),
      const Color(0xFF43B8A8),
    ];
    // 用字面量而不是查表：i18n 收集脚本只认 t('...') 的字面量，
    // 写成 t(list[i]) 会让「普通 / 稀有 / 传说」漏出中文。
    final rarityName = switch (r.rarity) {
      2 => t('传说'),
      1 => t('稀有'),
      _ => t('普通'),
    };
    final rarityColor = [
      dark ? C.dInk3 : C.ink3,
      C.brand,
      const Color(0xFFD9A441),
    ][r.rarity];
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
      decoration: BoxDecoration(
        color: fieldOf(dark),
        borderRadius: BorderRadius.circular(D.cardR),
        border: Border.all(
            color: r.rarity == 2
                ? const Color(0xFFD9A441).withOpacity(0.55)
                : hairOf(dark),
            width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: rarityColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(rarityName,
                    style: ts(dark,
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: rarityColor)),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(t(r.talent.name), style: display(dark, size: 17))),
            ],
          ),
          const SizedBox(height: 6),
          Text(t(r.talent.desc), style: ts(dark, size: 12, height: 1.55, color: dark ? C.dInk2 : C.ink2)),
          const SizedBox(height: 10),
          for (var i = 0; i < kStatKeys.length; i++)
            statBar(
              dark,
              '${t(kStatLabels[i])}${kStatKeys[i] == r.strongestKey ? ' ★' : ''}',
              r.stats[kStatKeys[i]],
              colors[i],
            ),
          const SizedBox(height: 4),
          Text('${t('天赋')}：${t(r.talent.hint)}',
              style: meta(dark, size: 11)),
        ],
      ),
    );
  }

  Future<void> _pickRegion() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showModalBottomSheet<RegionPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegionSheet(
        dark: dark,
        province: province,
        city: city,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      province = picked.province;
      city = picked.city;
    });
  }

  void _roll() {
    if (roll != null) return;
    setState(() => roll = rollCharacter());
  }

  // ------------------------------------------------------------------ 状态

  Widget _statusCard(bool dark, LifeCharacter c) {
    final colors = [
      C.ok,
      C.brand,
      const Color(0xFFE0708A),
      const Color(0xFFD9A441),
      const Color(0xFF8A73D6),
      const Color(0xFF43B8A8),
    ];
    return featureCard(dark, [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: display(dark, size: 20)),
                const SizedBox(height: 3),
                Text(
                    [
                      t(c.gender),
                      t(c.era),
                      if (c.province.isNotEmpty)
                        regionLabel(c.province, c.city),
                    ].join(' · '),
                    style: meta(dark, size: 11.5)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${c.age} ${t('岁')}',
                  style: numStyle(dark,
                      size: 22,
                      weight: FontWeight.w600,
                      color: dark ? C.dInk : C.ink)),
              // 年份单独成行即可：中文「2026 年」与英文「2026」都不别扭，
              // 也省掉一个在英文里没有对应词的量词词条。
              Text('${c.year}', style: meta(dark, size: 11)),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(height: 1, color: hairOf(dark)),
      const SizedBox(height: 8),
      for (var i = 0; i < kStatKeys.length; i++)
        statBar(dark, t(kStatLabels[i]), c.stats[kStatKeys[i]], colors[i]),
      const SizedBox(height: 6),
      if (c.talentName.trim().isNotEmpty) ...[
        Text('${t('天赋')}：${t(c.talentName)}',
            style: meta(dark, size: 11.5)),
        const SizedBox(height: 3),
      ],
      Text('${t('人生目标')}：${t(c.goal)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: meta(dark, size: 11.5)),
    ]);
  }

  // ------------------------------------------------------------------ 事件

  Widget _eventCard(bool dark, LifeCharacter c) {
    final e = c.pending;
    final last = c.events.isEmpty ? null : c.events.last;
    final showContinue = e == null && !busy && !c.ended;
    return featureCard(dark, [
      Row(
        children: [
          Expanded(child: featureLabel(dark, t('人生事件'))),
          if (showContinue)
            featureOutline(
                dark: dark,
                label: last == null || !last.resolved ? t('推进人生') : t('继续'),
                icon: Icons.arrow_forward_rounded,
                onPressed: _next),
        ],
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else if (e != null) ...[
        Text('${e.spanLabel} ${t('岁')} · ${e.title}',
            style: ts(dark, size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(e.story, style: ts(dark, size: 13, height: 1.7)),
        const SizedBox(height: 14),
        Text(t('你会怎么选？'), style: sectionTitle(dark)),
        const SizedBox(height: 8),
        for (var i = 0; i < e.choices.length; i++) _choiceTile(dark, e, i),
      ] else if (last != null && last.resolved) ...[
        // 选完先看清后果，再决定继续——不要点一下就跳到几年后，
        // 让人不知道自己刚才那个选择到底改变了什么。
        Text('${last.spanLabel} ${t('岁')} · ${last.title}',
            style: ts(dark, size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        _outcomeBlock(dark, last),
      ] else
        featureEmpty(dark, Icons.hourglass_empty_rounded, t('下一段人生尚未发生')),
    ]);
  }

  /// 选择后的后果：选了什么、发生了什么、六维怎么变。
  Widget _outcomeBlock(bool dark, LifeEvent e) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t('选择')}：${e.choices[e.chosenIndex].text}',
              style: meta(dark, size: 11.5)),
          const SizedBox(height: 8),
          Text(e.outcome, style: ts(dark, size: 13, height: 1.7)),
          if (e.deltas.values.any((v) => v != 0)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < kStatKeys.length; i++)
                  if ((e.deltas[kStatKeys[i]] ?? 0) != 0)
                    _deltaChip(dark, t(kStatLabels[i]),
                        e.deltas[kStatKeys[i]]!),
              ],
            ),
          ],
        ],
      );

  Widget _deltaChip(bool dark, String label, int delta) {
    final up = delta > 0;
    final color = up ? C.ok : C.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('$label ${up ? '+' : ''}$delta',
          style: ts(dark,
              size: 10.5, weight: FontWeight.w600, color: color)),
    );
  }

  Widget _choiceTile(bool dark, LifeEvent e, int i) {
    final c = e.choices[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          side: BorderSide(color: borderOf(dark), width: 0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
        ),
        onPressed: busy ? null : () => _choose(i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.text, style: ts(dark, size: 13, weight: FontWeight.w500)),
            if (c.hint.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(c.hint, style: meta(dark, size: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finaleCard(bool dark, LifeCharacter c) => featureCard(dark, [
        featureLabel(dark, t('盖棺定论')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('${c.score}',
                style: numStyle(dark,
                    size: 38,
                    weight: FontWeight.w700,
                    color: C.brand)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t('人生评分 · 满分 100'),
                    style: sub(dark, size: 12))),
          ],
        ),
        const SizedBox(height: 10),
        if (c.epitaph.trim().isEmpty)
          featureEmpty(dark, Icons.auto_stories_rounded, t('正在撰写人生总结'))
        else
          SelectableText(c.epitaph,
              style: ts(dark, size: 13, height: 1.7)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: featureOutline(
                  dark: dark,
                  label: t('导出人生履历'),
                  icon: Icons.copy_rounded,
                  onPressed: _export),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: featureOutline(
                  dark: dark,
                  label: t('新的人生'),
                  icon: Icons.refresh_rounded,
                  onPressed: _reset),
            ),
          ],
        ),
      ]);

  Widget _timelineCard(bool dark, LifeCharacter c) => featureCard(dark, [
        InkWell(
          onTap: () => setState(() => showTimeline = !showTimeline),
          child: Row(
            children: [
              Expanded(
                  child: featureLabel(
                      dark, '${t('人生履历')} · ${c.events.length}')),
              Icon(showTimeline
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
                  size: 18, color: dark ? C.dInk3 : C.ink3),
            ],
          ),
        ),
        if (showTimeline)
          if (c.events.isEmpty)
            featureEmpty(dark, Icons.timeline_rounded, t('还没有故事'))
          else
            for (final e in c.events.reversed) _historyRow(dark, e),
      ]);

  Widget _historyRow(bool dark, LifeEvent e) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Text(e.spanLabel,
                  style: numStyle(dark, size: 11)),
            ),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 6, right: 9),
              decoration: BoxDecoration(
                  color: e.resolved ? C.brand : hairOf(dark),
                  shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: ts(dark, size: 12.5, weight: FontWeight.w600)),
                  if (e.resolved) ...[
                    const SizedBox(height: 3),
                    Text('${t('选择')}：${e.choices[e.chosenIndex].text}',
                        style: meta(dark, size: 11)),
                    const SizedBox(height: 2),
                    Text(e.outcome,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11, height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------ 动作

  Future<void> _create() async {
    if (!configured) {
      setState(() => notice = t('尚未配置接口，请先到设置里填好连接与模型。'));
      return;
    }
    final r = roll;
    if (r == null) {
      setState(() => notice = t('先抽一次天赋，再开始这一生。'));
      return;
    }
    final g = goalCtrl.text.trim().isNotEmpty ? goalCtrl.text.trim() : goal;
    final c = LifeCharacter(
      id: newLifeId(),
      name: nameCtrl.text.trim().isEmpty ? _randomName() : nameCtrl.text.trim(),
      gender: gender,
      era: era,
      goal: g,
      province: province,
      city: city,
      talentKey: r.talent.key,
      talentName: r.talent.name,
      talentDesc: r.talent.desc,
      talentRarity: r.rarity,
      birthYear: _birthYearFor(era),
      age: 0,
      stats: r.stats,
    );
    setState(() {
      life = c;
      notice = null;
    });
    await _next();
  }

  /// 出生年。人生从 0 岁写起，所以这里给的是「出生那一年」，
  /// 不是角色登场时的年份。
  int _birthYearFor(String e) {
    if (e.contains('九十年代')) return 1990;
    if (e.contains('古代')) return 1720;
    if (e.contains('近未来')) return 2088;
    return 2026;
  }

  Future<void> _next() async {
    final c = life;
    if (c == null || c.over) return;
    setState(() {
      busy = true;
      notice = null;
    });
    cancel = CancelToken();
    try {
      await engine.nextEvent(c, conn, cancel: cancel);
    } catch (e) {
      setState(() => notice = '${t('生成事件失败')}：$e');
      if (c.over) await _finish();
    } finally {
      cancel = null;
      if (mounted) setState(() => busy = false);
      _scheduleSave();
    }
  }

  Future<void> _choose(int index) async {
    final c = life;
    if (c == null) return;
    setState(() {
      busy = true;
      notice = null;
    });
    cancel = CancelToken();
    try {
      // 只结算，不自动跳下一章：先让玩家看到这一选择把人生推向了哪。
      await engine.choose(c, index, conn, cancel: cancel);
      if (c.over) {
        await _finish();
      }
    } catch (e) {
      setState(() => notice = '${t('判定结果失败')}：$e');
    } finally {
      cancel = null;
      if (mounted) setState(() => busy = false);
      _scheduleSave();
    }
  }

  Future<void> _finish() async {
    final c = life;
    if (c == null) return;
    c.ended = true;
    setState(() => busy = true);
    try {
      await engine.finalize(c, conn);
    } catch (e) {
      setState(() => notice = '${t('生成传记失败')}：$e');
    } finally {
      if (mounted) setState(() => busy = false);
      _scheduleSave();
    }
  }

  void _reset() {
    cancel?.cancel();
    setState(() {
      life = null;
      roll = null;
      busy = false;
      notice = null;
      showTimeline = false;
    });
  }

  Future<void> _export() async {
    final c = life;
    if (c == null) return;
    await Clipboard.setData(ClipboardData(text: c.toMarkdown()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t('已复制到剪贴板')),
      duration: const Duration(seconds: 1),
    ));
  }

  String _randomName() {
    const surnames = ['林', '陈', '沈', '苏', '许', '周', '顾', '叶', '江', '温'];
    const given = ['知远', '清和', '晚宁', '亦安', '念一', '星回', '未央', '听澜', '子衿', '明澈'];
    final n = DateTime.now().microsecondsSinceEpoch;
    return '${surnames[n % surnames.length]}${given[(n ~/ 7) % given.length]}';
  }

  Future<void> _openSaves(bool dark) async {
    saves = await store.loadLives();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LifeSavesSheet(
        dark: dark,
        items: saves,
        onLoad: (c) {
          Navigator.pop(ctx);
          cancel?.cancel();
          setState(() {
            life = c;
            notice = null;
            showTimeline = true;
          });
        },
        onDelete: (id) async {
          await store.deleteLife(id);
          saves = await store.loadLives();
          if (ctx.mounted) Navigator.pop(ctx);
          _openSaves(dark);
        },
      ),
    );
  }
}

/// 人生存档弹层。
class _LifeSavesSheet extends StatelessWidget {
  const _LifeSavesSheet({
    required this.dark,
    required this.items,
    required this.onLoad,
    required this.onDelete,
  });

  final bool dark;
  final List<LifeCharacter> items;
  final ValueChanged<LifeCharacter> onLoad;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: canvasOf(dark),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(D.floatR)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 11),
            Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                    color: lineOf(dark),
                    borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('人生存档'), style: display(dark, size: 18)),
              ),
            ),
            Container(height: 1, color: hairOf(dark)),
            Flexible(
              child: items.isEmpty
                  ? featureEmpty(dark, Icons.bookmark_border_rounded,
                      t('还没有存档'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final c = items[i];
                        return ListTile(
                          dense: true,
                          title: Text(c.name, style: ts(dark, size: 13)),
                          subtitle: Text(
                              '${t(c.era)} · ${c.age} ${t('岁')} · '
                              '${c.events.length} ${t('段经历')}'
                              '${c.ended ? ' · ${t('已完结')}' : ''}',
                              style: meta(dark, size: 11)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 18, color: dark ? C.dInk3 : C.ink3),
                            onPressed: () => onDelete(c.id),
                          ),
                          onTap: () => onLoad(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 出生地选择结果。用 record 而不是小类，少一个只出现一次的模型。
typedef RegionPick = ({String province, String city});

/// 出生地两级下钻：省 → 市。
///
/// 和「选运营商 → 点进去看模型」是同一套手势：一路点进去、逐层返回，
/// 不做一次性铺开几百个城市的巨型列表。
class _RegionSheet extends StatefulWidget {
  const _RegionSheet({
    required this.dark,
    required this.province,
    required this.city,
  });

  final bool dark;
  final String province;
  final String city;

  @override
  State<_RegionSheet> createState() => _RegionSheetState();
}

class _RegionSheetState extends State<_RegionSheet> {
  RegionProvince? open;
  final TextEditingController q = TextEditingController();

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: BoxDecoration(
          color: canvasOf(dark),
          borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                    color: lineOf(dark),
                    borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (open != null) {
                        setState(() => open = null);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                          open == null
                              ? Icons.close_rounded
                              : Icons.arrow_back_rounded,
                          size: 19,
                          color: dark ? C.dInk2 : C.ink2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      open == null
                          ? t('选择出生地')
                          : '${open!.name} · ${t('选择城市')}',
                      style: display(dark, size: 17),
                    ),
                  ),
                  if (open != null)
                    Text('${open!.cities.length} ${t('个城市')}',
                        style: meta(dark, size: 11)),
                ],
              ),
            ),
            if (open == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                child: TextField(
                  controller: q,
                  onChanged: (_) => setState(() {}),
                  style: ts(dark, size: 13),
                  decoration: fieldDecoration(dark,
                          hint: t('搜索省份或城市'))
                      .copyWith(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            Container(height: 1, color: hairOf(dark)),
            Expanded(
              child: open == null ? _provinceList(dark) : _cityGrid(dark, open!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _provinceList(bool dark) {
    final query = q.text.trim();
    if (query.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: kProvinces.length,
        itemBuilder: (_, i) {
          final p = kProvinces[i];
          final selected = p.name == widget.province;
          return ListTile(
            dense: true,
            title: Text(p.name,
                style: ts(dark,
                    size: 13.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? C.brand : null)),
            subtitle: Text('${p.cities.length} ${t('个城市')}',
                style: meta(dark, size: 11)),
            trailing: Icon(Icons.chevron_right_rounded,
                size: 18, color: dark ? C.dInk3 : C.ink3),
            onTap: () => setState(() => open = p),
          );
        },
      );
    }
    // 搜索时直接把省和市摊平：搜「深圳」应该立刻看到「广东 · 深圳」，
    // 而不是先让用户猜它属于哪个省。
    final hits = <({RegionProvince p, String c})>[];
    for (final p in kProvinces) {
      for (final c in p.cities) {
        if (c.contains(query) || p.name.contains(query)) {
          hits.add((p: p, c: c));
        }
      }
    }
    if (hits.isEmpty) {
      return featureEmpty(
          dark, Icons.search_off_rounded, t('没有找到这个城市，试试别的写法'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: hits.length,
      itemBuilder: (_, i) {
        final h = hits[i];
        return ListTile(
          dense: true,
          title: Text(h.c, style: ts(dark, size: 13.5)),
          subtitle: Text(h.p.name, style: meta(dark, size: 11)),
          onTap: () => Navigator.pop(
              context, (province: h.p.name, city: h.c)),
        );
      },
    );
  }

  Widget _cityGrid(bool dark, RegionProvince p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in p.cities)
            ChoiceChip(
              label: Text(c, style: ts(dark, size: 12.5)),
              selected: p.name == widget.province && c == widget.city,
              showCheckmark: false,
              backgroundColor: fieldOf(dark),
              selectedColor: C.brand.withOpacity(0.14),
              side: BorderSide(
                  color: p.name == widget.province && c == widget.city
                      ? C.brand
                      : hairOf(dark),
                  width: 0.8),
              onSelected: (_) =>
                  Navigator.pop(context, (province: p.name, city: c)),
            ),
        ],
      ),
    );
  }
}
