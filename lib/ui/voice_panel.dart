import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lang_catalog.dart';
import '../services/voice_catalog.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'lang_picker_sheet.dart';

/// 设置 → 语音。
///
/// 两块内容：朗读（TTS）与语音输入（STT）。每个引擎都标明是免费、离线
/// 还是需要 Key——用户最想知道的是「这个要不要花钱、会不会突然失效」。
class VoicePanel extends StatefulWidget {
  final bool dark;
  const VoicePanel({super.key, required this.dark});

  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> {
  late final TextEditingController _ttsBase;
  late final TextEditingController _ttsModel;
  late final TextEditingController _ttsKey;
  late final TextEditingController _sttBase;
  late final TextEditingController _sttModel;
  late final TextEditingController _sttKey;
  bool _testing = false;
  bool _probing = false;
  bool _ttsProbing = false;
  String _ttsProbe = '';
  String _probeText = '测可用性与连通延迟，不发真实转写、不消耗额度';

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _ttsBase = TextEditingController(text: s.ttsBaseUrl);
    _ttsModel = TextEditingController(text: s.ttsModel);
    _ttsKey = TextEditingController(text: s.voiceTtsKey);
    _sttBase = TextEditingController(text: s.sttBaseUrl);
    _sttModel = TextEditingController(text: s.sttModel);
    _sttKey = TextEditingController(text: s.voiceSttKey);
  }

  @override
  void dispose() {
    _ttsBase.dispose();
    _ttsModel.dispose();
    _ttsKey.dispose();
    _sttBase.dispose();
    _sttModel.dispose();
    _sttKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final dark = widget.dark;
    final tts = st.activeTtsEngine;
    final stt = st.activeSttEngine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(dark, t('朗读'), t('把回答读出来。免费通道随时可能失效，系统语音永远可用。'), [
          _switch(
            dark,
            '启用朗读',
            '右上角声波键与长按气泡里的朗读项',
            s.ttsEnabled,
            (v) => st.apply((x) => x.ttsEnabled = v),
          ),
          _switch(
            dark,
            '全部静音',
            '顶栏音量键也能切换；手动点朗读会自动解除',
            s.voiceMuted,
            (v) => st.apply((x) => x.voiceMuted = v),
          ),
          _switch(
            dark,
            '回答后自动朗读',
            '生成完成后直接开口；后台会话不会出声',
            s.autoSpeak,
            (v) => st.apply((x) => x.autoSpeak = v),
          ),
          const SizedBox(height: 6),
          _label(dark, '引擎'),
          for (final e in kTtsEngines)
            _engineRow(
              dark: dark,
              title: e.name,
              summary: e.summary,
              badge: e.badge,
              selected: s.ttsEngineId == e.id,
              onTap: () => st.apply((x) {
                x.ttsEngineId = e.id;
                // 换引擎时清掉旧音色，否则会把 A 引擎的 voice 传给 B。
                x.ttsVoice = e.voices.isEmpty ? '' : e.voices.first;
              }),
            ),
          if (tts.voices.isNotEmpty) ...[
            const SizedBox(height: 14),
            _label(dark, '音色'),
            _chips(dark, tts.voices,
                s.ttsVoice.isEmpty ? tts.voices.first : s.ttsVoice, (v) {
              st.apply((x) => x.ttsVoice = v);
            }),
          ],
          const SizedBox(height: 16),
          _label(dark, '语速'),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: s.ttsRate.clamp(0.6, 2.0),
                    min: 0.6,
                    max: 2.0,
                    divisions: 14,
                    activeColor: accentOf(dark),
                    inactiveColor: borderOf(dark),
                    onChanged: (v) => st.apply((x) => x.ttsRate = v),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${s.ttsRate.toStringAsFixed(1)}×',
                    textAlign: TextAlign.right,
                    style: numStyle(dark, size: 11.5)),
              ),
            ],
          ),
          if (_ttsNeedsConfig(tts)) ...[
            if (tts.proto != VoiceProto.elevenLabs) ...[
              const SizedBox(height: 10),
              _field(
                dark,
                tts.proto == VoiceProto.azure ? '区域' : '接口地址',
                _ttsBase,
                hint: tts.proto == VoiceProto.azure
                    ? 'eastasia / eastus，留空按 eastasia'
                    : (tts.followsConnection
                        ? '留空 = 跟随当前连接（${s.baseUrl}）'
                        : tts.baseUrl),
                onChanged: (v) => st.apply((x) => x.ttsBaseUrl = v.trim()),
              ),
            ],
            if (tts.proto == VoiceProto.openAI) ...[
              const SizedBox(height: 10),
              _field(
                dark,
                '模型',
                _ttsModel,
                hint: tts.id == 'cosy'
                    ? 'FunAudioLLM/CosyVoice2-0.5B'
                    : (tts.id == 'groq-tts' ? 'playai-tts' : '默认 tts-1'),
                onChanged: (v) => st.apply((x) => x.ttsModel = v.trim()),
              ),
            ],
            if (tts.needsKey) ...[
              const SizedBox(height: 10),
              _field(
                dark,
                '密钥',
                _ttsKey,
                obscure: true,
                hint: tts.followsConnection
                    ? '留空 = 用当前连接的 Key'
                    : '${tts.name} 的 API Key',
                onChanged: (v) => st.setVoiceKey(tts: true, key: v),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _btn(dark, _testing ? '播放中…' : '试听', () => _test(st), dark),
              const SizedBox(width: 8),
              _btn(dark, _ttsProbing ? '测试中…' : '测可用',
                  _ttsProbing ? null : () => _probeTts(st, tts), dark,
                  ghost: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tts.isFree ? '不花钱' : '按字符计费',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta(dark, size: 11.5),
                ),
              ),
            ],
          ),
          if (_ttsProbe.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_ttsProbe,
                style: meta(dark,
                    size: 11.5,
                    height: 1.5,
                    color: _ttsProbe.startsWith('可用')
                        ? (dark ? C.dInk : C.ink)
                        : C.warn)),
          ],
          const SizedBox(height: 10),
          Text(tts.note, style: meta(dark, size: 11.5, height: 1.7)),
        ]),
        _card(dark, t('语音输入'), t('说完静音自动停止，识别出的句子放进输入框；确认没识别错，再点发送。'), [
          _switch(
            dark,
            '按住说话',
            '长按语音键开始，松手识别，上滑取消；关掉则只用点击式',
            s.holdToTalk,
            (v) => st.apply((x) => x.holdToTalk = v),
          ),
          _switch(
            dark,
            '说完静音自动停止',
            '说完停顿一下就自动收尾；关掉后需点一下停止。识别结果只回填输入框，不会自动发送',
            s.sttAutoStopOnSilence,
            (v) => st.apply((x) => x.sttAutoStopOnSilence = v),
          ),
          _switch(
            dark,
            '本地优先',
            '系统识别先走端侧引擎，零网络往返、录音不上传（内置离线引擎始终本地）',
            s.sttPreferOffline,
            (v) => st.apply((x) => x.sttPreferOffline = v),
          ),
          _switch(
            dark,
            '自动回落',
            '离线包缺失或识别服务不可用时，自动切到在线识别',
            s.sttAutoFallback,
            (v) => st.apply((x) => x.sttAutoFallback = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _btn(dark, _probing ? '测试中…' : '一键测速', () => _probe(st, stt),
                  dark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _probeText,
                  style: meta(dark, size: 11.5, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _capsLine(dark),
          const SizedBox(height: 16),
          _offlineBox(dark, st),
          const SizedBox(height: 14),
          _label(dark, '本地 / 离线优先'),
          for (final e in kSttEngines.where((x) => x.offline))
            _engineRow(
              dark: dark,
              title: e.name,
              summary: e.summary,
              badge: e.badge,
              tags: e.tags,
              selected: s.sttEngineId == e.id,
              onTap: () => st.apply((x) => x.sttEngineId = e.id),
            ),
          const SizedBox(height: 12),
          _label(dark, '跟随连接 / 云端'),
          for (final e in kSttEngines.where((x) => !x.offline))
            _engineRow(
              dark: dark,
              title: e.name,
              summary: e.summary,
              badge: e.badge,
              tags: e.tags,
              selected: s.sttEngineId == e.id,
              onTap: () => st.apply((x) => x.sttEngineId = e.id),
            ),
          const SizedBox(height: 14),
          _label(dark, '语言'),
          // v4.13：语言从三选一放开成完整列表（含小语种），与设置页「语言」
          // 分类共用同一个选择器，改哪边都是同一份配置。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final code = await showLangPicker(
                context,
                dark: dark,
                title: t('语音识别语言'),
                items: [
                  for (final l in kSpeechLangs)
                    LangItem(l.code, l.label, l.native),
                ],
                selected: s.voiceLang,
              );
              if (code != null) st.apply((x) => x.voiceLang = code);
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              decoration: BoxDecoration(
                color: fieldOf(dark),
                borderRadius: BorderRadius.circular(D.r),
                border: Border.all(color: borderOf(dark)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(speechLangLabel(s.voiceLang),
                        style: ts(dark, size: 13.5, weight: FontWeight.w600)),
                  ),
                  Text('${kSpeechLangs.length} 种',
                      style: meta(dark, size: 11.5)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: dark ? C.dInk3 : C.ink3),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _label(dark, '说完多久收尾'),
          _chips(
              dark,
              const ['更跟手', '标准', '说长句'],
              s.sttSilenceMs <= 500
                  ? '更跟手'
                  : (s.sttSilenceMs >= 1200 ? '说长句' : '标准'), (v) {
            st.apply((x) => x.sttSilenceMs = switch (v) {
                  '更跟手' => 400,
                  '说长句' => 1500,
                  _ => 700,
                });
          }),
          const SizedBox(height: 4),
          if (stt.proto != VoiceProto.system) ...[
            const SizedBox(height: 10),
            _field(
              dark,
              '接口地址',
              _sttBase,
              hint: stt.followsConnection
                  ? '留空 = 跟随当前连接（${s.baseUrl}）'
                  : stt.baseUrl,
              onChanged: (v) => st.apply((x) => x.sttBaseUrl = v.trim()),
            ),
            const SizedBox(height: 10),
            _field(
              dark,
              '模型',
              _sttModel,
              hint: stt.model.isEmpty ? 'whisper-1' : stt.model,
              onChanged: (v) => st.apply((x) => x.sttModel = v.trim()),
            ),
            if (stt.needsKey || !stt.followsConnection) ...[
              const SizedBox(height: 10),
              _field(
                dark,
                '密钥',
                _sttKey,
                obscure: true,
                hint: stt.followsConnection ? '留空 = 用当前连接的 Key' : 'API Key',
                onChanged: (v) => st.setVoiceKey(tts: false, key: v),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            '${stt.note}\n'
            '录音会先存到本机临时目录，转写完成立即删除。',
            style: meta(dark, size: 11.5, height: 1.7),
          ),
        ]),
        _note(dark),
      ],
    );
  }

  /// 一键测速：本地读系统能力，云端只探 /models 连通，不发真实转写。
  Future<void> _probe(AppState st, SttEngine engine) async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _probeText = '正在检测 ${engine.name}…';
    });
    final r = await VoiceService.instance.probe(
      engine: engine,
      baseUrl: st.resolveSttBaseUrl(),
      apiKey: st.resolveSttKey(),
    );
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeText = '${r.label} · ${r.detail}';
    });
  }

  /// 本机识别能力条：明确说清「端侧离线到底能不能用」。
  Widget _capsLine(bool dark) {
    return FutureBuilder<Map<String, dynamic>>(
      future: VoiceService.instance.capabilities(),
      builder: (context, snap) {
        final c = snap.data;
        final available = c?['available'] == true;
        final onDevice = c?['onDevice'] == true;
        final good = available && onDevice;
        final color = good ? const Color(0xFF2E9E6B) : C.warn;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: color.withOpacity(dark ? 0.10 : 0.07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                good ? Icons.bolt_rounded : Icons.info_outline_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  !available
                      ? '本机没有可用的系统语音识别服务，建议选云端引擎；'
                          '长按说话仍会录音上传。'
                      : (good
                          ? '已检测到端侧离线识别：按住说话不走网络，松手即出字，'
                              '是本机最快最省的方案。'
                          : '本机有系统识别，但未安装端侧离线语音包；'
                              '已开启自动回落在线识别，仍可正常使用。'),
                  style: meta(dark, size: 11.5, height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _probeTts(AppState st, TtsEngine engine) async {
    if (_ttsProbing) return;
    setState(() {
      _ttsProbing = true;
      _ttsProbe = '正在检测 ${engine.name}…';
    });
    final r = await VoiceService.instance.probeTts(
      engine: engine,
      voice: st.settings.ttsVoice,
      baseUrl: st.resolveTtsBaseUrl(),
      apiKey: st.resolveTtsKey(),
      model: st.settings.ttsModel,
      rate: st.settings.ttsRate,
    );
    if (!mounted) return;
    setState(() {
      _ttsProbing = false;
      _ttsProbe = '${engine.name}：$r';
    });
  }

  Future<void> _test(AppState st) async {
    if (_testing) {
      await st.stopSpeaking();
      if (mounted) setState(() => _testing = false);
      return;
    }
    setState(() => _testing = true);
    final err = await st.speak('这是一段试听，用来确认音色和语速是否合适。');
    if (!mounted) return;
    setState(() => _testing = false);
    if (err != null && err.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    }
  }

  // ---------------------------------------------------------------- 组件

  Widget _card(bool dark, String title, String desc, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: surfaceBox(dark, shadowScale: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  ts(dark, size: 14.5, weight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 4),
          Text(desc, style: meta(dark, size: 11.5, height: 1.6)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  /// 离线语音包：安装状态 + 解压进度。这是默认识别方式，
  /// 装好之后不需要任何 Key、不联网，也不依赖厂商的识别服务。
  Widget _offlineBox(bool dark, AppState st) {
    final m = st.speechModel;
    final busy = st.speechModelBusy;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: fieldOf(dark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairOf(dark), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                m.ready
                    ? Icons.offline_bolt_outlined
                    : Icons.cloud_download_outlined,
                size: 16,
                color: m.ready ? accentOf(dark) : (dark ? C.dInk3 : C.ink3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.ready
                      ? '离线语音包已安装 · ${m.sizeLabel}'
                      : '离线语音包未安装 · 已随安装包内置',
                  style: ts(dark, size: 13, weight: FontWeight.w500),
                ),
              ),
              if (!busy)
                TextButton(
                  onPressed: () => m.ready
                      ? st.removeSpeechModel()
                      : st.downloadSpeechModel(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(m.ready ? '删除' : '安装',
                      style: meta(dark, size: 11.5, color: accentOf(dark))),
                )
              else
                TextButton(
                  onPressed: st.cancelSpeechDownload,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(t('取消'),
                      style: meta(dark, size: 11.5, color: accentOf(dark))),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (busy) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: st.speechModelProgress <= 0
                    ? null
                    : st.speechModelProgress,
                minHeight: 3,
                backgroundColor: hairOf(dark),
                valueColor: AlwaysStoppedAnimation<Color>(accentOf(dark)),
              ),
            ),
            const SizedBox(height: 6),
            Text('正在安装 ${(st.speechModelProgress * 100).toStringAsFixed(0)}%　'
                '从安装包解压到本机，不耗流量，可以退出这个页面。',
                style: meta(dark, size: 11.5, height: 1.5)),
          ] else if (st.speechModelError.isNotEmpty)
            Text(st.speechModelError,
                style: meta(dark, size: 11.5, color: const Color(0xFFB4453C)))
          else
            Text(t('模型随安装包分发，不需要联网下载。装好后识别全程在本机完成，录音不上传，装在应用私有目录，卸载即清理。'),
              style: meta(dark, size: 11.5, height: 1.6),
            ),
        ],
      ),
    );
  }

  Widget _label(bool dark, String text) => Padding(        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text.toUpperCase(), style: sectionTitle(dark)),
      );

  /// 引擎行：左侧一条 2px 竖线表示选中，比圆点或勾更安静。
  Widget _engineRow({
    required bool dark,
    required String title,
    required String summary,
    required String badge,
    required bool selected,
    required VoidCallback onTap,
    List<String> tags = const [],
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairOf(dark))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: 30,
              margin: const EdgeInsets.only(top: 1, right: 11),
              decoration: BoxDecoration(
                color: selected ? accentOf(dark) : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: ts(dark,
                          size: 13.5,
                          weight: FontWeight.w500,
                          color: selected
                              ? (dark ? C.dInk : C.ink)
                              : (dark ? C.dInk2 : C.ink2))),
                  const SizedBox(height: 3),
                  Text(summary, style: meta(dark, size: 11.5, height: 1.5)),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [for (final t in tags) _tag(dark, t, selected)],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? accentOf(dark).withOpacity(dark ? 0.16 : 0.09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: selected
                        ? accentOf(dark).withOpacity(0.35)
                        : borderOf(dark)),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  color: selected ? accentOf(dark) : (dark ? C.dInk3 : C.ink3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 引擎能力标签：本地用绿色强调，其余跟随选中态。
  Widget _tag(bool dark, String text, bool selected) {
    final local = text == '本地';
    final c = local
        ? const Color(0xFF2E9E6B)
        : (selected ? accentOf(dark) : (dark ? C.dInk3 : C.ink3));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.3,
          color: c,
          fontWeight: local ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _switch(bool dark, String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ts(dark, size: 13.5)),
                const SizedBox(height: 3),
                Text(sub, style: meta(dark, size: 11.5, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: dark ? C.brandDark : C.brand,
          ),
        ],
      ),
    );
  }

  Widget _chips(bool dark, List<String> items, String current,
      ValueChanged<String> onPick) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final v in items)
          GestureDetector(
            onTap: () => onPick(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: v == current
                    ? accentOf(dark).withOpacity(dark ? 0.16 : 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: v == current
                        ? accentOf(dark).withOpacity(0.4)
                        : borderOf(dark)),
              ),
              child: Text(
                v,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight:
                      v == current ? FontWeight.w600 : FontWeight.w400,
                  color:
                      v == current ? accentOf(dark) : (dark ? C.dInk2 : C.ink2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    bool dark,
    String label,
    TextEditingController c, {
    String? hint,
    bool obscure = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(dark, label),
        TextField(
          controller: c,
          obscureText: obscure,
          maxLines: 1,
          style: ts(dark, size: 13, height: 1.4),
          decoration: fieldDecoration(dark, hint: hint),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _btn(bool dark, String text, VoidCallback? onTap, bool _,
      {bool ghost = false}) {
    final on = onTap != null;
    final c = on
        ? accentOf(dark)
        : (dark ? C.dInk3 : C.ink3);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? accentOf(dark).withOpacity(dark ? 0.18 : 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: on
                  ? accentOf(dark).withOpacity(0.35)
                  : borderStrongOf(dark)),
        ),
        child: Text(text,
            style: ts(dark,
                size: 13,
                weight: ghost ? FontWeight.w500 : FontWeight.w600,
                color: c)),
      ),
    );
  }

  /// 只有真需要填地址 / 密钥的引擎才展示这些输入框。
  bool _ttsNeedsConfig(TtsEngine e) =>
      e.proto == VoiceProto.openAI ||
      e.proto == VoiceProto.elevenLabs ||
      e.proto == VoiceProto.fish ||
      e.proto == VoiceProto.azure;

  Widget _note(bool dark) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
        child: Text(t('免费通道来自公开网页接口，随时可能失效或加限制；密钥只加密存在本机，不随配置同步。朗读在右上角声波键或长按气泡呼出；点输入台麦克风即可说话，说完静音自动停止，文字先进输入框，确认后再发送。'),
          style: meta(dark, size: 11.5, height: 1.7),
        ),
      );
}
