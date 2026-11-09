import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../i18n.dart';
import '../services/feature_store.dart';
import '../services/model_source.dart';
import '../services/roundtable.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'feature_kit.dart';
import 'provider_model_picker.dart';

/// 多模型圆桌会议页。
///
/// 流程：填议题 →（可选）AI 生成大纲并手改 → 选 3~5 个席位（不同模型 /
/// 不同连接 / 不同立场）→ 多轮讨论 → 主持人汇总 → 导出纪要、留档。
class RoundtableScreen extends StatefulWidget {
  const RoundtableScreen({super.key});

  @override
  State<RoundtableScreen> createState() => _RoundtableScreenState();
}

class _RoundtableScreenState extends State<RoundtableScreen> {
  late AppState st;
  final FeatureStore store = FeatureStore();
  final TextEditingController topicCtrl = TextEditingController();
  final TextEditingController agendaCtrl = TextEditingController();
  final ScrollController scroll = ScrollController();

  late Meeting meeting;
  late RoundtableEngine engine;
  CancelToken? cancel;
  Timer? saveTimer;
  bool booting = true;
  bool busy = false;
  String? notice;
  List<Meeting> history = [];

  @override
  void initState() {
    super.initState();
    st = Provider.of<AppState>(context, listen: false);
    engine = RoundtableEngine(
      llm: st.llm,
      onChanged: _onEngineChanged,
    );
    meeting = Meeting(id: newMeetingIdForUi(), rounds: 2);
    topicCtrl.addListener(_syncTopic);
    agendaCtrl.addListener(_syncAgenda);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    cancel?.cancel();
    topicCtrl.removeListener(_syncTopic);
    agendaCtrl.removeListener(_syncAgenda);
    topicCtrl.dispose();
    agendaCtrl.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleSave();
  }

  void _syncTopic() => meeting.topic = topicCtrl.text;
  void _syncAgenda() => meeting.agenda = agendaCtrl.text;

  void _scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      history = await store.upsertMeeting(meeting);
      if (mounted) setState(() {});
    });
  }

  Future<void> _boot() async {
    try {
      final savedSeats = await store.loadSeats();
      if (savedSeats.isNotEmpty) {
        _restoreKeys(savedSeats);
        meeting.seats = savedSeats;
      } else {
        meeting.seats = _buildDefaultSeats();
      }
      history = await store.loadMeetings();
    } catch (_) {
      meeting.seats = _buildDefaultSeats();
    }
    if (!mounted) return;
    setState(() => booting = false);
  }

  /// 席位存档不保存密钥，启动时按地址从当前连接把 key 补回去。
  void _restoreKeys(List<Seat> seats) {
    for (final s in seats) {
      if (s.providerName.trim().isEmpty) {
        s.providerName = providerNameFor(st.settings, s.baseUrl);
      }
      if (s.apiKey.isNotEmpty) continue;
      for (final p in st.settings.profiles) {
        if (p.baseUrl.trim() == s.baseUrl.trim() && p.apiKey.isNotEmpty) {
          s.apiKey = p.apiKey;
          break;
        }
      }
      if (s.apiKey.isEmpty && s.baseUrl.trim() == st.settings.baseUrl.trim()) {
        s.apiKey = st.settings.apiKey;
      }
    }
  }

  List<Seat> _buildDefaultSeats() {
    final s = st.settings;
    final candidates = <({String baseUrl, String apiKey, String model})>[];
    for (final p in s.profiles) {
      candidates
          .add((baseUrl: p.baseUrl, apiKey: p.apiKey, model: p.model));
      for (final m in p.cachedModels.take(10)) {
        candidates.add((baseUrl: p.baseUrl, apiKey: p.apiKey, model: m));
      }
    }
    for (final m in st.models.take(10)) {
      candidates.add((baseUrl: s.baseUrl, apiKey: s.apiKey, model: m.id));
    }
    final seats = defaultSeats(
      fallbackBaseUrl: s.baseUrl,
      fallbackApiKey: s.apiKey,
      fallbackModel: s.model,
      candidates: candidates,
      count: 5,
    );
    // 一条连接、一个模型时，用同一模型配上不同立场，会议照样开得起来。
    var i = 0;
    while (seats.length < 3 && s.model.trim().isNotEmpty) {
      final k = seats.length;
      seats.add(Seat(
        id: 'seat_fill_$i',
        name: kDefaultSeatNames[k % kDefaultSeatNames.length],
        role: kDefaultRoles[k % kDefaultRoles.length],
        baseUrl: s.baseUrl,
        apiKey: s.apiKey,
        model: s.model,
        providerName: s.activeProfile.name,
      ));
      i++;
    }
    for (final seat in seats) {
      if (seat.providerName.trim().isEmpty) {
        seat.providerName = providerNameFor(s, seat.baseUrl);
      }
    }
    return seats;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: featureAppBar(context, dark,
          title: t('AI 圆桌会议'),
          actions: [
            featureRoundButton(dark, Icons.history_rounded,
                () => _openHistory(dark),
                tooltip: t('会议记录')),
            featureRoundButton(dark, Icons.add_rounded, _newMeeting,
                tooltip: t('新建会议')),
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
                      if (notice != null) featureNotice(dark, notice!),
                      _topicCard(dark),
                      _seatsCard(dark),
                      const SizedBox(height: 4),
                      if (meeting.running)
                        featureOutline(
                            dark: dark,
                            label: t('停止会议'),
                            icon: Icons.stop_rounded,
                            onPressed: _stop)
                      else
                        featurePrimary(
                            dark: dark,
                            label: t('开始会议'),
                            icon: Icons.forum_rounded,
                            onPressed: meeting.activeSeats.isEmpty
                                ? null
                                : _start),
                      if (meeting.status.isNotEmpty)
                        featureHint(dark, meeting.status,
                            color: meeting.phase == MeetingPhase.failed
                                ? C.danger
                                : accentOf(dark)),
                      if (meeting.turns.isNotEmpty) _turnsCard(dark),
                      if (meeting.summary.isNotEmpty) _summaryCard(dark),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _topicCard(bool dark) => featureCard(dark, [
        featureLabel(dark, t('会议议题')),
        TextField(
          controller: topicCtrl,
          maxLines: 3,
          minLines: 1,
          style: ts(dark, size: 13.5),
          decoration: fieldDecoration(dark, hint: t('输入这次要讨论的问题')),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: featureLabel(dark, t('会议大纲'))),
            featureOutline(
                dark: dark,
                label: t('生成大纲'),
                icon: Icons.auto_awesome_rounded,
                onPressed: busy || topicCtrl.text.trim().isEmpty
                    ? null
                    : _generateOutline),
          ],
        ),
        TextField(
          controller: agendaCtrl,
          maxLines: 5,
          minLines: 2,
          style: ts(dark, size: 12.5, height: 1.5),
          decoration: fieldDecoration(dark, hint: t('由 AI 根据议题生成，可手动修改')),
        ),
        featureHint(dark, t('每行一条，讨论时所有参会者都会看到这份大纲。')),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
                width: 70,
                child: Text(t('讨论轮数'), style: sub(dark, size: 12.5))),
            Expanded(
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 1, label: Text(t('1 轮'))),
                  ButtonSegment(value: 2, label: Text(t('2 轮'))),
                  ButtonSegment(value: 3, label: Text(t('3 轮'))),
                ],
                selected: {meeting.rounds.clamp(1, 3)},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(ts(dark, size: 12)),
                ),
                onSelectionChanged: (v) {
                  setState(() => meeting.rounds = v.first);
                  _scheduleSave();
                },
              ),
            ),
          ],
        ),
      ]);

  Widget _seatsCard(bool dark) {
    final seats = meeting.seats;
    return featureCard(dark, [
      Row(
        children: [
          Expanded(child: featureLabel(dark, '${t('参会模型')} · ${meeting.activeSeats.length}')),
          featureOutline(
              dark: dark,
              label: t('添加席位'),
              icon: Icons.person_add_alt_rounded,
              onPressed: seats.length >= 5 ? null : () => _editSeat(dark, null)),
        ],
      ),
      featureHint(dark, t('可选不同连接或不同模型；同一模型换立场也能形成分歧。')),
      if (seats.isEmpty)
        featureEmpty(dark, Icons.person_off_rounded, t('暂无参会席位'))
      else
        for (var i = 0; i < seats.length; i++) _seatTile(dark, seats[i], i),
      const SizedBox(height: 8),
      featureOutline(
          dark: dark,
          label: t('从已有连接补齐 5 个模型'),
          icon: Icons.auto_fix_high_rounded,
          onPressed: () {
            setState(() => meeting.seats = _buildDefaultSeats());
            _scheduleSave();
          }),
    ]);
  }

  Widget _seatTile(bool dark, Seat s, int index) {
    final on = s.usable;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: fieldOf(dark),
        borderRadius: BorderRadius.circular(D.r),
        border: Border.all(color: hairOf(dark), width: 0.8),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: on ? C.brand.withOpacity(0.12) : fieldOf(dark),
          child: Text('${index + 1}',
              style: ts(dark,
                  size: 12,
                  weight: FontWeight.w600,
                  color: on ? C.brand : (dark ? C.dInk3 : C.ink3))),
        ),
        title: Text(t(s.displayName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(dark, size: 13, weight: FontWeight.w600)),
        subtitle: Text(
            '${s.providerName.trim().isEmpty ? t('未指定连接') : s.providerName}'
            ' · ${t(s.role.split(' · ').first)} · ${s.model}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: meta(dark, size: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: s.enabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) {
                setState(() => s.enabled = v);
                _scheduleSave();
              },
            ),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: dark ? C.dInk3 : C.ink3),
          ],
        ),
        onTap: () => _editSeat(dark, index),
      ),
    );
  }

  Widget _turnsCard(bool dark) {
    int? round;
    final items = <Widget>[];
    for (final turn in meeting.turns) {
      if (turn.round != round) {
        round = turn.round;
        items.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(t('第 $round 轮'), style: sectionTitle(dark)),
        ));
      }
      items.add(_turnTile(dark, turn));
    }
    return featureCard(dark, [
      Row(
        children: [
          Expanded(child: featureLabel(dark, t('讨论记录'))),
          featureOutline(
              dark: dark,
              label: t('导出纪要'),
              icon: Icons.copy_rounded,
              onPressed: _export),
        ],
      ),
      ...items,
    ]);
  }

  Widget _turnTile(bool dark, MeetingTurn turn) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(color: hairOf(dark), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t(turn.seatName),
                      style: ts(dark, size: 12.5, weight: FontWeight.w600)),
                ),
                Text(turn.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta(dark, size: 10.5)),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              turn.ok ? turn.content : '${t('未发言')}：${turn.error ?? ''}',
              style: ts(dark, size: 12.5, height: 1.6),
            ),
          ],
        ),
      );

  Widget _summaryCard(bool dark) => featureCard(dark, [
        featureLabel(dark, t('会议结论')),
        SelectableText(meeting.summary, style: ts(dark, size: 12.8, height: 1.65)),
        const SizedBox(height: 12),
        featureOutline(
            dark: dark,
            label: t('导出纪要'),
            icon: Icons.copy_rounded,
            onPressed: _export),
      ]);

  // ------------------------------------------------------------------ 动作

  Future<void> _generateOutline() async {
    if (meeting.activeSeats.isEmpty) {
      setState(() => notice = t('至少需要一个可用的参会模型'));
      return;
    }
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final text = await engine.outline(meeting);
      agendaCtrl.text = text;
      setState(() {});
    } catch (e) {
      setState(() => notice = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
      _scheduleSave();
    }
  }

  Future<void> _start() async {
    if (topicCtrl.text.trim().isEmpty) {
      setState(() => notice = t('请先填写会议议题'));
      return;
    }
    FocusScope.of(context).unfocus();
    cancel = CancelToken();
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      await engine.run(meeting, cancel: cancel);
    } finally {
      cancel = null;
      if (mounted) setState(() => busy = false);
      _scheduleSave();
    }
  }

  void _stop() {
    cancel?.cancel();
    setState(() => meeting.status = t('正在停止'));
  }

  void _newMeeting() {
    cancel?.cancel();
    final seats = meeting.seats.map((s) => s.copy()).toList();
    meeting = Meeting(id: newMeetingIdForUi(), rounds: meeting.rounds, seats: seats);
    topicCtrl.clear();
    agendaCtrl.clear();
    setState(() {
      busy = false;
      notice = null;
    });
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: meeting.toMarkdown()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t('已复制到剪贴板')),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _editSeat(bool dark, int? index) async {
    final isNew = index == null;
    final s = isNew
        ? Seat(
            id: 'seat_${DateTime.now().microsecondsSinceEpoch}',
            name: kDefaultSeatNames[meeting.seats.length % 5],
            role: kDefaultRoles[meeting.seats.length % 5],
            baseUrl: st.settings.baseUrl,
            apiKey: st.settings.apiKey,
            model: st.settings.model,
            providerName: st.settings.activeProfile.name,
          )
        : meeting.seats[index].copy();
    // 旧存档没有运营商名，按地址补一个，界面上才不会空着。
    if (s.providerName.trim().isEmpty) {
      s.providerName = providerNameFor(st.settings, s.baseUrl);
    }
    final nameCtrl = TextEditingController(text: s.name);
    final roleCtrl = TextEditingController(text: s.role);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SeatSheet(
        dark: dark,
        seat: s,
        isNew: isNew,
        nameCtrl: nameCtrl,
        roleCtrl: roleCtrl,
        onDelete: isNew
            ? null
            : () {
                Navigator.pop(ctx, false);
                setState(() => meeting.seats.removeAt(index));
                _scheduleSave();
              },
      ),
    );
    if (ok != true || !mounted) return;
    s.name = nameCtrl.text.trim();
    s.role = roleCtrl.text.trim();
    setState(() {
      if (isNew) {
        if (meeting.seats.length < 5) meeting.seats.add(s);
      } else {
        meeting.seats[index] = s;
      }
    });
    _scheduleSave();
  }

  Future<void> _openHistory(bool dark) async {
    history = await store.loadMeetings();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MeetingHistorySheet(
        dark: dark,
        items: history,
        onLoad: (m) {
          Navigator.pop(ctx);
          _loadMeeting(m);
        },
        onDelete: (id) async {
          await store.deleteMeeting(id);
          history = await store.loadMeetings();
          if (ctx.mounted) Navigator.pop(ctx);
          _openHistory(dark);
        },
      ),
    );
  }

  void _loadMeeting(Meeting m) {
    _restoreKeys(m.seats);
    meeting = m;
    topicCtrl.text = m.topic;
    agendaCtrl.text = m.agenda;
    setState(() => notice = null);
  }
}

String newMeetingIdForUi() =>
    'meet_${DateTime.now().microsecondsSinceEpoch}';

/// 席位编辑弹层。
class _SeatSheet extends StatefulWidget {
  const _SeatSheet({
    required this.dark,
    required this.seat,
    required this.isNew,
    required this.nameCtrl,
    required this.roleCtrl,
    this.onDelete,
  });

  final bool dark;
  final Seat seat;
  final bool isNew;
  final TextEditingController nameCtrl;
  final TextEditingController roleCtrl;
  final VoidCallback? onDelete;

  @override
  State<_SeatSheet> createState() => _SeatSheetState();
}

class _SeatSheetState extends State<_SeatSheet> {
  late Seat _seat;

  @override
  void initState() {
    super.initState();
    _seat = widget.seat;
  }

  Future<void> _pickModel() async {
    final picked = await showProviderModelPicker(
      context,
      dark: widget.dark,
      currentBaseUrl: _seat.baseUrl,
      currentModel: _seat.model,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _seat.baseUrl = picked.baseUrl;
      _seat.apiKey = picked.apiKey;
      _seat.model = picked.model;
      _seat.providerName = picked.providerName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86),
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
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(t('席位设置'),
                            style: display(dark, size: 18))),
                    if (widget.onDelete != null)
                      TextButton(
                          onPressed: widget.onDelete,
                          child: Text(t('删除席位'),
                              style: ts(dark, size: 12.5, color: C.danger))),
                  ],
                ),
              ),
              Container(height: 1, color: hairOf(dark)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(dark, t('名称'), widget.nameCtrl, t('例如：分析者')),
                      const SizedBox(height: 12),
                      Text(t('角色立场'), style: sectionTitle(dark)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in kDefaultRoles)
                            ActionChip(
                              label: Text(t(r.split(' · ').first),
                                  style: ts(dark, size: 11.5)),
                              backgroundColor: fieldOf(dark),
                              side: BorderSide(color: hairOf(dark)),
                              onPressed: () => widget.roleCtrl.text = r,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _field(dark, '', widget.roleCtrl, t('自定义立场描述')),
                      const SizedBox(height: 16),
                      Text(t('连接与模型'), style: sectionTitle(dark)),
                      const SizedBox(height: 7),
                      InkWell(
                        borderRadius: BorderRadius.circular(D.r),
                        onTap: _pickModel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: fieldOf(dark),
                            borderRadius: BorderRadius.circular(D.r),
                            border:
                                Border.all(color: hairOf(dark), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hub_outlined,
                                  size: 17, color: accentOf(dark)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        _seat.providerName.trim().isEmpty
                                            ? t('未选择连接')
                                            : _seat.providerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: ts(dark,
                                            size: 12.5,
                                            weight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(
                                        _seat.model.trim().isEmpty
                                            ? t('点这里选择运营商与模型')
                                            : _seat.model,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: meta(dark, size: 11)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  size: 18,
                                  color: dark ? C.dInk3 : C.ink3),
                            ],
                          ),
                        ),
                      ),
                      featureHint(
                          dark, t('先选运营商（连接），再从该运营商的模型列表里挑一个。')),
                      const SizedBox(height: 18),
                      featurePrimary(
                          dark: dark,
                          label: t('保存'),
                          icon: Icons.check_rounded,
                          onPressed: () {
                            widget.seat.baseUrl = _seat.baseUrl;
                            widget.seat.apiKey = _seat.apiKey;
                            widget.seat.model = _seat.model;
                            widget.seat.providerName = _seat.providerName;
                            Navigator.pop(context, true);
                          }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(bool dark, String label, TextEditingController c, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: sectionTitle(dark)),
          const SizedBox(height: 7),
        ],
        TextField(
          controller: c,
          style: ts(dark, size: 13),
          decoration: fieldDecoration(dark, hint: hint),
        ),
      ],
    );
  }
}

/// 历史会议弹层。
class _MeetingHistorySheet extends StatelessWidget {
  const _MeetingHistorySheet({
    required this.dark,
    required this.items,
    required this.onLoad,
    required this.onDelete,
  });

  final bool dark;
  final List<Meeting> items;
  final ValueChanged<Meeting> onLoad;
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
                child: Text(t('会议记录'), style: display(dark, size: 18)),
              ),
            ),
            Container(height: 1, color: hairOf(dark)),
            Flexible(
              child: items.isEmpty
                  ? featureEmpty(dark, Icons.history_toggle_off_rounded,
                      t('暂无历史会议'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final m = items[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                              m.topic.trim().isEmpty ? t('未命名议题') : m.topic,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts(dark, size: 13)),
                          subtitle: Text(
                              '${m.createdAt.month}/${m.createdAt.day} · '
                              '${m.activeSeats.length} ${t('位参会者')} · '
                              '${m.turns.length} ${t('条发言')}',
                              style: meta(dark, size: 11)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 18, color: dark ? C.dInk3 : C.ink3),
                            onPressed: () => onDelete(m.id),
                          ),
                          onTap: () => onLoad(m),
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
