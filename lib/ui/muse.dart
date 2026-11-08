import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/speech_model.dart';
import '../services/voice_catalog.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../skin.dart';
import '../i18n.dart';
import '../theme.dart';
import 'persona.dart';

/// v4.3「Muse」视觉层。
///
/// 参考的是一类黑色沉浸式助理界面：纯黑画布、悬浮形象顶栏、
/// 助手用深灰气泡、用户用亮蓝气泡、胶囊输入台（v4.13 起底部导航已移除）。
/// 与参考稿的区别（也就是「更加优化」的部分）：
///  1. 顶栏随滚动连续收缩，内容从渐变遮罩下淡出，而不是硬切两张图；
///  2. 「邀请」这类没有实际作用的装饰，换成真实的静音 / 朗读控制；
///  3. 名字胶囊里的副标题显示真实连接状态，蓝点只在未配置时出现；
///  4. 引导卡每一行都通往真实功能，不是写死的演示数据；
///  5. 亮色模式有完整对应色板，不是只做一张深色稿。
class MuseC {
  static Color get bg => Skin.dark.bg;
  static Color get bgLight => Skin.light.bg;

  /// 助手气泡 / 输入台 / 卡片。
  static Color get surface => Skin.dark.surface;
  static Color get surfaceLight => Skin.light.surface;

  /// 顶栏圆形按钮、名字胶囊。
  static Color get pill => Skin.dark.chip;
  static Color get pillLight => Skin.light.chip;

  /// 用户气泡与唯一强调色。
  static Color get blue => Skin.light.accent;
  static Color get blueDark => Skin.dark.accent;

  static Color get ink => Skin.dark.ink;
  static Color get inkLight => Skin.light.ink;
  static Color get ink2 => Skin.dark.ink2;
  static Color get ink2Light => Skin.light.ink2;
  static Color get ink3 => Skin.dark.ink3;
  static Color get ink3Light => Skin.light.ink3;

  static Color canvas(bool dark) => dark ? bg : bgLight;
  static Color bubble(bool dark) => dark ? surface : surfaceLight;
  static Color chip(bool dark) => dark ? pill : pillLight;
  static Color text(bool dark) => dark ? ink : inkLight;
  static Color sub(bool dark) => dark ? ink2 : ink2Light;
  static Color faint(bool dark) => dark ? ink3 : ink3Light;
  static Color accent(bool dark) => dark ? blueDark : blue;
  static Color send(bool dark) => dark ? blueDark : blue;
}

/// 会话开头的时间标签：「7-12 下午」。做成纯函数方便单测。
String museDateLabel(DateTime d) =>
    '${d.month}-${d.day} ${d.hour < 12 ? '上午' : '下午'}';

/// 居中、极淡的日期分隔。
class MuseDateChip extends StatelessWidget {
  final DateTime at;
  final bool dark;
  const MuseDateChip({super.key, required this.at, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Center(
        child: Text(
          museDateLabel(at),
          style: TextStyle(
            fontSize: 11.5,
            color: MuseC.faint(dark),
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// 通用气泡：助手宽气泡 / 用户收缩气泡，长按可呼出操作。
class MuseBubble extends StatelessWidget {
  final bool dark;
  final bool user;
  final Widget child;
  final bool wide;
  final VoidCallback? onLongPress;

  const MuseBubble({
    super.key,
    required this.dark,
    required this.child,
    this.user = false,
    this.wide = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: onLongPress,
        child: Container(
          width: wide ? double.infinity : null,
          constraints: BoxConstraints(
            maxWidth: wide ? 480 : 310,
            minWidth: wide ? 0 : 52,
          ),
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
          decoration: BoxDecoration(
            color: user ? MuseC.send(dark) : MuseC.bubble(dark),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 左上角圆形菜单按钮。
class MuseRoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool dark;
  final double size;

  const MuseRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.dark,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.62,
        containedInkWell: false,
        highlightShape: BoxShape.circle,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MuseC.chip(dark),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: MuseC.text(dark)),
        ),
      ),
    );
  }
}

/// 声波：三根竖条。播放时做错相呼吸，静止时保持等高。
class MuseWaveIcon extends StatefulWidget {
  final bool active;
  final Color color;
  const MuseWaveIcon({super.key, required this.active, required this.color});

  @override
  State<MuseWaveIcon> createState() => _MuseWaveIconState();
}

class _MuseWaveIconState extends State<MuseWaveIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 860),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant MuseWaveIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        final heights = <double>[
          6 + 8 * (0.35 + 0.65 * v),
          6 + 9 * (0.35 + 0.65 * (1 - v).abs()),
          6 + 7 * (0.35 + 0.65 * ((v + 0.4) % 1)),
        ];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < heights.length; i++) ...[
              if (i > 0) const SizedBox(width: 2.4),
              Container(
                width: 2.2,
                height: widget.active ? heights[i] : 9,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 右上角朗读控制：一颗按钮。
///
/// v4.14：原来「音量 + 波形」两颗圆钮功能重叠（音量其实只是朗读的静音
/// 开关），合并成一颗后，顶栏左右各一个圆钮，视觉上真正对称、也少一次选择。
/// 静音没有消失：长按这颗按钮切换，设置 → 语音 里同样保留开关。
///
/// 点下去**立刻**进入「准备中」：微软通道要先合成首段音频，过去这一两秒
/// 按钮毫无变化，用户会以为点坏了。现在转圈从手指抬起那一帧就开始，
/// 再点一次就是取消；听到声音后同一颗按钮变成「停止」。
class MuseVoiceControls extends StatefulWidget {
  final bool dark;
  final double size;

  const MuseVoiceControls({super.key, required this.dark, this.size = 40});

  @override
  State<MuseVoiceControls> createState() => _MuseVoiceControlsState();
}

class _MuseVoiceControlsState extends State<MuseVoiceControls> {
  /// 已点击、音频还没真正开始。
  bool _pending = false;
  bool _pressed = false;
  Timer? _guard;

  @override
  void initState() {
    super.initState();
    VoiceService.instance.speaking.addListener(_onSpeaking);
  }

  @override
  void dispose() {
    VoiceService.instance.speaking.removeListener(_onSpeaking);
    _guard?.cancel();
    super.dispose();
  }

  void _onSpeaking() {
    if (!mounted) return;
    if (VoiceService.instance.speaking.value && _pending) {
      _guard?.cancel();
      setState(() => _pending = false);
    }
  }

  Future<void> _tap() async {
    final st = context.read<AppState>();
    final speaking = VoiceService.instance.speaking.value;

    // 准备中或正在播：同一颗按钮就是「停」。
    if (_pending || speaking) {
      await st.stopSpeaking();
      _guard?.cancel();
      if (mounted) setState(() => _pending = false);
      return;
    }

    ChatMessage? target;
    for (final m in st.active.messages.reversed) {
      if (m.role == Role.assistant && m.content.trim().isNotEmpty) {
        target = m;
        break;
      }
    }
    if (target == null) {
      _snack(L10n.t(L10n.t('还没有可以朗读的回答')));
      return;
    }

    // 静音时手动点朗读自动解除，否则就是「点了没反应」。
    if (st.settings.voiceMuted) {
      st.apply((s) => s.voiceMuted = false);
      _snack(L10n.t(L10n.t('已开启朗读')));
    }

    setState(() => _pending = true);
    // 兜底：万一原生层一直不回报开始事件，25 秒后也要把按钮放回可点状态。
    _guard = Timer(const Duration(seconds: 25), () {
      if (mounted && _pending) setState(() => _pending = false);
    });

    final err = await st.speak(target.content);
    _guard?.cancel();
    if (!mounted) return;
    if (_pending) setState(() => _pending = false);
    if (err != null && err.isNotEmpty) _snack(err);
  }

  void _toggleMute() {
    final st = context.read<AppState>();
    final next = !st.settings.voiceMuted;
    st.apply((s) => s.voiceMuted = next);
    _snack(next ? L10n.t('朗读已静音 · 长按可恢复') : L10n.t('朗读已开启'));
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = widget.dark;
    final muted = st.settings.voiceMuted;
    return ValueListenableBuilder<bool>(
      valueListenable: VoiceService.instance.speaking,
      builder: (context, speaking, _) {
        final active = _pending || speaking;
        final accent = MuseC.accent(dark);
        final tip = _pending
            ? L10n.t('正在准备朗读 · 点击取消')
            : speaking
                ? L10n.t('停止朗读')
                : muted
                    ? L10n.t('朗读上一条回答（已静音）')
                    : L10n.t('朗读上一条回答');
        return Tooltip(
          message: tip,
          // 长按留给「切换静音」，不让它顺手弹出一个 tooltip。
          triggerMode: TooltipTriggerMode.manual,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            onLongPress: _toggleMute,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1,
              duration: D.animFast,
              curve: D.curve,
              child: AnimatedContainer(
                duration: D.anim,
                curve: D.curve,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: active ? accent.withOpacity(dark ? 0.18 : 0.10) : MuseC.chip(dark),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _pending
                      ? SizedBox(
                          width: widget.size * 0.36,
                          height: widget.size * 0.36,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: accent,
                          ),
                        )
                      : speaking
                          ? MuseWaveIcon(active: true, color: accent)
                          : muted
                              ? Icon(
                                  Icons.volume_off_rounded,
                                  size: widget.size * 0.44,
                                  color: MuseC.faint(dark),
                                )
                              : MuseWaveIcon(
                                  active: false,
                                  color: MuseC.text(dark),
                                ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }
}

/// 悬浮形象顶栏：随 [collapse]（0 → 1）把大头像收成一行小头像，
/// 名字胶囊淡出，底下那层渐变让滚上来的消息自然淡出，不做硬切。
class MuseTopBar extends StatelessWidget {
  final ValueListenable<double> collapse;
  final bool dark;
  final Persona persona;
  final String statusLine;
  final bool connected;

  /// 关闭「人物形象」时仍保留头像，但收起名字胶囊。
  final bool showPill;
  final VoidCallback onMenu;
  final VoidCallback onAvatar;
  final VoidCallback onStatus;

  const MuseTopBar({
    super.key,
    required this.collapse,
    required this.dark,
    required this.persona,
    required this.statusLine,
    required this.connected,
    required this.onMenu,
    required this.onAvatar,
    required this.onStatus,
    this.showPill = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: collapse,
      builder: (context, raw, _) {
        final t = raw.clamp(0.0, 1.0);
        final avatar = lerpDouble(54, 32, t)!;
        final height = lerpDouble(126, 56, t)!;
        final pillOpacity = showPill ? (1 - t * 1.7).clamp(0.0, 1.0) : 0.0;
        final bg = MuseC.canvas(dark);
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bg, bg, bg.withOpacity(0)],
                        stops: const [0, 0.70, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: lerpDouble(12, 6, t)!,
                child: MuseRoundButton(
                  icon: Icons.menu_rounded,
                  tooltip: L10n.t('会话与设置'),
                  onTap: onMenu,
                  dark: dark,
                  size: lerpDouble(44, 38, t)!,
                ),
              ),
              Positioned(
                right: 12,
                top: lerpDouble(12, 6, t)!,
                child: MuseVoiceControls(
                  dark: dark,
                  size: lerpDouble(44, 38, t)!,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: lerpDouble(6, 4, t)!,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _avatar(avatar, t),
                    // 只让淡出的胶囊失效，收缩后头像仍可点开形象切换。
                    IgnorePointer(
                      ignoring: pillOpacity < 0.05,
                      child: Opacity(
                        opacity: pillOpacity,
                        child: Transform.scale(
                          scale: lerpDouble(1, 0.86, t)!,
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding:
                                EdgeInsets.only(top: lerpDouble(10, 0, t)!),
                            child: _namePill(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatar(double size, double t) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAvatar,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? const Color(0xFFF1F1F3) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.5 : 0.12),
              blurRadius: 18 * (1 - t * 0.6),
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(size * 0.055),
        clipBehavior: Clip.antiAlias,
        child: ClipOval(
          child: PersonaAvatar(
            persona: persona,
            size: size * 0.89,
            dark: dark,
            ring: false,
            backdrop: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _namePill(BuildContext context) {
    // 没设置形象就不占位：胶囊里只留模型 / 连接信息，绝不显示
    // 「不使用形象」这类解释性文案。
    final name = persona.name.trim();
    final label = [
      if (name.isNotEmpty) name,
      if (statusLine.isNotEmpty) statusLine,
    ].join('  ·  ');
    if (label.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onStatus,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        decoration: BoxDecoration(
          color: MuseC.chip(dark),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!connected) ...[
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: MuseC.blue,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            Flexible(
              child: Text(
                // 名字与模型并在同一行：两行胶囊会把首屏再压掉一层，
                // 而模型名本来就是「当前在用哪个」的补充信息。
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: MuseC.text(dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「按住说话」浮层：实时波形 + 计时 + 实时上屏文字 + 上滑取消。
/// 用 OverlayEntry 挂上去，本身 IgnorePointer，不抢长按手势的 up 事件。
class MuseHoldToTalk extends StatelessWidget {
  final bool dark;
  final bool cancelling;
  final bool offline;
  final String partial;
  final ValueListenable<double> level;

  const MuseHoldToTalk({
    super.key,
    required this.dark,
    required this.cancelling,
    required this.offline,
    required this.partial,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFE5484D);
    final accent = cancelling ? danger : MuseC.accent(dark);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withOpacity(dark ? 0.58 : 0.34),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    22, 26, 22, 34 + MediaQuery.viewPaddingOf(context).bottom),
                decoration: BoxDecoration(
                  color: MuseC.bubble(dark),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cancelling ? '松开取消' : (offline ? '本地识别中' : '正在聆听'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 46,
                      child: ValueListenableBuilder<double>(
                        valueListenable: level,
                        builder: (_, v, __) => MuseWaveform(
                          level: v,
                          color: accent,
                          active: !cancelling,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 22),
                      child: Text(
                        cancelling
                            ? '松开手指即取消本次录音'
                            : (partial.trim().isEmpty ? '…' : partial.trim()),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: MuseC.text(dark),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      cancelling ? '手指移回来可继续' : '松手完成 · 上滑取消',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MuseC.faint(dark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 20 根柱子的音量波形：静音时是一条细线，说话时按音量起伏。
class MuseWaveform extends StatelessWidget {
  final double level;
  final Color color;
  final bool active;

  const MuseWaveform({
    super.key,
    required this.level,
    required this.color,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(level: level, color: color, active: active),
      size: Size.infinite,
    );
  }
}

class _WavePainter extends CustomPainter {
  final double level;
  final Color color;
  final bool active;

  _WavePainter(
      {required this.level, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 21;
    final gap = size.width / bars;
    final w = gap * 0.42;
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color.withOpacity(active ? 0.9 : 0.4)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < bars; i++) {
      // 中间高、两端低的包络，再叠加实时音量。
      final envelope = 1 - ((i - (bars - 1) / 2).abs() / ((bars - 1) / 2));
      const double floor = 3;
      final h = floor +
          (size.height - floor) *
              (0.16 + 0.72 * envelope) *
              (0.35 + 0.65 * level);
      final x = gap * (i + 0.5);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.level != level || old.color != color || old.active != active;
}

/// 空态引导：欢迎气泡 + 快速开始卡 + 可点的建议气泡。
/// 全部是纯展示，不往会话里写假消息，因此不会污染历史、朗读与统计。
class MuseOnboarding extends StatelessWidget {
  final Persona persona;
  final bool dark;
  final String modelLine;
  final VoidCallback onConfigure;
  final VoidCallback onPersona;
  final VoidCallback onVoice;
  final VoidCallback onTools;
  final ValueChanged<String> onStarter;

  const MuseOnboarding({
    super.key,
    required this.persona,
    required this.dark,
    required this.modelLine,
    required this.onConfigure,
    required this.onPersona,
    required this.onVoice,
    required this.onTools,
    required this.onStarter,
  });

  static const List<String> kStarters = [
    '总结一篇文章',
    '解释一段代码',
    '整理成大纲',
    '查一下最新进展',
  ];

  // 没有形象（name 为空）或只有字符头像时，开场白不提名字。
  bool get _plain => persona.name.trim().isEmpty || persona.glyph.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MuseDateChip(at: DateTime.now(), dark: dark),
              MuseBubble(
                dark: dark,
                wide: true,
                child: Text(
                  // 不用形象时不能再念「我是不使用形象」——那句话读起来像
                  // 产品在报错。没有名字就直接说事。
                  _plain
                      ? '有什么要处理的，交给我。也可以直接问一句。'
                      : '嘿，我是${persona.name}。把手头的事交给我，或者直接问一句。',
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.68,
                    color: MuseC.text(dark),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 建议改成一条可横滑的胶囊带：四个入口占一行，不再竖着堆成
              // 三个满宽蓝气泡把首屏顶满。
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: kStarters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = kStarters[i];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onStarter(t),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: MuseC.chip(dark),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: (dark ? Colors.white : Colors.black)
                                .withOpacity(dark ? 0.07 : 0.05),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            color: MuseC.text(dark),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------- 语音面板
///
/// 点输入栏麦克风弹出：自动开始识别、实时波形与文字、明确的
/// 「取消 / 重录 / 填入输入框」按钮。
///
/// v4.11 起语音识别**绝不替用户按发送键**：说完静音自动停止，识别出的
/// 句子回填到主界面输入框，用户看一眼、改一下，再自己点发送。这是主流
/// AI 客户端的做法，也避免识别错一两个字就直接把错话发出去。

enum _VPhase { listening, processing, result, error, needModel }

Future<void> showMuseVoiceSheet(
  BuildContext context, {
  required bool dark,
  required String convId,
  required ValueChanged<String> onFill,
  VoidCallback? onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(dark ? 0.62 : 0.38),
    builder: (_) => MuseVoiceSheet(
      dark: dark,
      convId: convId,
      onFill: onFill,
      onOpenSettings: onOpenSettings,
    ),
  );
}

class MuseVoiceSheet extends StatefulWidget {
  final bool dark;
  final String convId;

  /// 把最终识别文字（含录音前已有草稿）回填到输入台。
  final ValueChanged<String> onFill;
  final VoidCallback? onOpenSettings;

  const MuseVoiceSheet({
    super.key,
    required this.dark,
    required this.convId,
    required this.onFill,
    this.onOpenSettings,
  });

  @override
  State<MuseVoiceSheet> createState() => _MuseVoiceSheetState();
}

class _MuseVoiceSheetState extends State<MuseVoiceSheet>
    with SingleTickerProviderStateMixin {
  static const Color _danger = Color(0xFFE5484D);

  late final AppState _st = context.read<AppState>();
  late final VoiceService _voice = VoiceService.instance;

  /// 打开面板前的输入框内容：取消 / 重录时恢复到这句话。
  late final String _base = _st.draftFor(widget.convId);

  _VPhase _phase = _VPhase.listening;
  SttEngine? _engine;
  String _partial = '';
  String _final = '';
  bool _done = false;
  bool _settled = false;
  String _error = '';
  bool _downloading = false;
  double _dl = 0;

  // v4.11 云端录音的静音收尾：原生每 ~90ms 上报一次音量，系统 / Vosk
  // 通道由原生层自己判静音，这里只给「录完再上传转写」的云端通道补上
  // 同样的「说完就停」，不用一直按着、也不用再点一下停止。
  bool _heardVoice = false;
  DateTime? _silenceSince;
  late DateTime _recordStartedAt;
  bool _autoStopping = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _voice.rms.addListener(_onRms);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _voice.rms.removeListener(_onRms);
    _pulse.dispose();
    _voice.rms.value = 0;
    if (!_settled) _cleanupListen();
    super.dispose();
  }

  /// 音量驱动的自动收尾：必须先真的听到过声音，才启动静音计时，
  /// 否则一开麦就会被环境底噪判成「说完了」。
  void _onRms() {
    if (_settled || _autoStopping || _phase != _VPhase.listening) return;
    // 系统 / 内置离线通道由原生层按 silenceMs 自行收尾，不重复判定。
    if ((_engine?.proto ?? VoiceProto.system) == VoiceProto.system) return;
    if (!_st.settings.sttAutoStopOnSilence) return;
    final now = DateTime.now();
    if (now.difference(_recordStartedAt).inMilliseconds >= 60000) {
      _autoStopping = true;
      unawaited(_manualStop());
      return;
    }
    const voiceOn = 0.10;
    if (_voice.rms.value >= voiceOn) {
      _heardVoice = true;
      _silenceSince = null;
      return;
    }
    if (!_heardVoice) return;
    // 开麦后至少录满 800ms，避免一声气息 / 轻咳就被当成说完了。
    if (now.difference(_recordStartedAt).inMilliseconds < 800) return;
    _silenceSince ??= now;
    // 云端比系统识别多给一点余量：700ms 对「边说边出字」很跟手，
    // 但对整段录完再上传，容易把句间停顿误判成结束。
    final wait = (_st.settings.sttSilenceMs + 350).clamp(900, 3000);
    if (now.difference(_silenceSince!).inMilliseconds >= wait) {
      _autoStopping = true;
      unawaited(_manualStop());
    }
  }

  void _cleanupListen() {
    if ((_engine?.proto ?? VoiceProto.system) == VoiceProto.system) {
      unawaited(_voice.cancelSystemListen());
    } else {
      unawaited(_voice.cancelRecording());
    }
  }

  String _join(String t) => _base.isEmpty ? t : '$_base $t';

  Future<void> _start({bool restart = false}) async {
    if (restart) {
      _partial = '';
      _final = '';
      _done = false;
      _settled = false;
      _error = '';
      _st.setDraft(widget.convId, _base);
    }
    _heardVoice = false;
    _silenceSince = null;
    _recordStartedAt = DateTime.now();
    _autoStopping = false;
    final engine = _st.activeSttEngine;
    if (!mounted) return;
    // 内置离线引擎还没装模型：模型就在安装包里，直接自动安装，
    // 不再让用户「点一下下载」然后对着 0% 干等。
    if (engine.id == SpeechModel.engineId && !_st.speechModel.ready) {
      setState(() {
        _engine = engine;
        _phase = _VPhase.needModel;
        _error = '';
      });
      unawaited(_install());
      return;
    }
    setState(() {
      _engine = engine;
      _phase = _VPhase.listening;
      _error = '';
    });
    _pulse.repeat();

    final ok = engine.proto == VoiceProto.system
        ? await _voice.startSystemListen(
            lang: _st.settings.voiceLang,
            engine: engine.id,
            preferOffline: engine.offline || _st.settings.sttPreferOffline,
            autoFallback: _st.settings.sttAutoFallback,
            silenceMs: _st.settings.sttSilenceMs,
            onNotice: _fail,
            onText: _onText,
          )
        : await _voice.startRecording();
    if (!mounted) return;
    if (!ok) {
      _fail(_voice.lastError.trim().isEmpty
          ? '无法开始识别，请检查麦克风权限'
          : _voice.lastError);
    }
  }

  void _onText(String text, bool isFinal) {
    if (!mounted || _settled) return;
    final t = text.trim();
    if (t.isNotEmpty) {
      _partial = t;
      if (!isFinal) _st.setDraft(widget.convId, _join(t));
    }
    if (isFinal && !_done) {
      _done = true;
      if (t.isNotEmpty) _final = t;
      _finishToComposer();
    }
  }

  /// 识别结束：面板收起，文字落进输入框，发送权交还给用户。
  void _finishToComposer() {
    if (!mounted || _settled) return;
    final t = _final.trim().isNotEmpty ? _final.trim() : _partial.trim();
    if (t.isEmpty) {
      _fail('没有识别到内容，再试一次或换个识别引擎');
      return;
    }
    _settled = true;
    _pulse.stop();
    _cleanupListen();
    Navigator.of(context).pop();
    widget.onFill(_join(t));
  }

  void _fail(String msg) {
    if (!mounted) return;
    _pulse.stop();
    setState(() {
      _phase = _VPhase.error;
      _error = msg;
    });
  }

  /// 手动点停止 / 静音自动停止：只做「停止 + 回填」，永远不发消息。
  Future<void> _manualStop() async {
    if (_settled || _phase == _VPhase.processing) return;
    if (_phase == _VPhase.error || _phase == _VPhase.needModel) return;
    setState(() => _phase = _VPhase.processing);
    _pulse.stop();

    if ((_engine?.proto ?? VoiceProto.system) == VoiceProto.system) {
      await _voice.stopSystemListen();
      if (!mounted || _settled) return;
      // 最终结果由系统回调 _onText；本地识别出字很快，最多等 4 秒。
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (!_done && !_settled && mounted &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted || _settled) return;
      // 超时没等到 final：用「边说边出字」已经拿到的结果回填。
      _finishToComposer();
      return;
    }

    final text = await _voice.stopAndTranscribe(
      engine: _engine!,
      baseUrl: _st.resolveSttBaseUrl(),
      apiKey: _st.resolveSttKey(),
      model: _st.settings.sttModel.trim().isEmpty
          ? _engine!.model
          : _st.settings.sttModel,
      lang: _st.settings.voiceLang,
    );
    if (!mounted || _settled) return;
    final t = (text ?? '').trim();
    if (t.isEmpty) {
      _fail(_voice.lastError.trim().isEmpty
          ? '没有识别到内容，再试一次或换个识别引擎'
          : _voice.lastError);
      return;
    }
    _final = t;
    _finishToComposer();
  }

  void _cancel() {
    _settled = true;
    _pulse.stop();
    _cleanupListen();
    _st.setDraft(widget.convId, _base);
    Navigator.of(context).pop();
  }

  /// 手势下滑 / 点遮罩关闭：识别出内容就保留，否则恢复原草稿。
  void _onDismissed() {
    if (_settled) return;
    _settled = true;
    _pulse.stop();
    _cleanupListen();
    final t = _final.trim().isNotEmpty ? _final.trim() : _partial.trim();
    if (t.isNotEmpty) {
      _st.prefillDraft(widget.convId, _join(t));
    } else {
      _st.setDraft(widget.convId, _base);
    }
  }

  void _restart() => _start(restart: true);

  /// 面板内直接安装语音包：模型随包分发，这里只是解压，不走网络。
  Future<void> _install() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _dl = 0;
    });
    final timer = Timer.periodic(const Duration(milliseconds: 240), (_) {
      if (!mounted) return;
      setState(() => _dl = _st.speechModelProgress);
    });
    final ok = await _st.downloadSpeechModel();
    timer.cancel();
    if (!mounted) return;
    setState(() => _downloading = false);
    if (ok) {
      _start(restart: true);
    } else {
      _fail(_st.speechModelError.trim().isEmpty
          ? '语音包装载失败，可以到设置 → 语音里重试'
          : _st.speechModelError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final accent = MuseC.accent(dark);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final text = _final.trim().isNotEmpty ? _final.trim() : _partial.trim();
    final hasText = text.isNotEmpty && _phase != _VPhase.processing;

    final status = switch (_phase) {
      _VPhase.listening => _st.settings.sttAutoStopOnSilence
          ? '说完静音自动停止'
          : '正在聆听',
      _VPhase.processing => '识别中…',
      _VPhase.result => '识别完成',
      _VPhase.error => '出现问题',
      _VPhase.needModel => _downloading ? '正在准备语音包' : '准备好后自动开麦',
    };
    final statusColor = _phase == _VPhase.error ? _danger : accent;
    final needModel = _phase == _VPhase.needModel;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onDismissed();
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: MuseC.bubble(dark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：引擎徽标 + 关闭。
              Row(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _voice.offlineActive,
                    builder: (_, offline, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: MuseC.text(dark).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: offline ? const Color(0xFF4FAE8C) : accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            // 以引擎自身属性为准：内置离线引擎哪怕还没开始
                            // 录音，也不该被标成「云端」——那会让人以为
                            // 请求走出去了，其实是本地模型在跑。
                            '${_engine?.name ?? '语音识别'} · '
                            '${(offline || (_engine?.offline ?? false)) ? '本地' : '云端'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: MuseC.sub(dark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkResponse(
                    onTap: _cancel,
                    radius: 20,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.close_rounded,
                          size: 19, color: MuseC.sub(dark)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(status,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  )),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: _phase == _VPhase.error
                    ? Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: _danger,
                        ),
                      )
                    : needModel
                    ? Text(
                        _downloading
                            ? '首次使用，正在把内置的中文语音包装到本机。\n'
                                '装好后飞行模式也能识别，录音不离开这台手机。'
                            : '本机离线语音包还没装好。\n'
                                '点下方按钮重试，装好后不联网也能识别。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.6,
                          color: MuseC.sub(dark),
                        ),
                      )
                    : Text(
                        text.isEmpty ? '开始说话…' : text,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: text.isEmpty
                              ? MuseC.faint(dark)
                              : MuseC.text(dark),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              // 波形：聆听时跟随音量，其他状态保持静默细线。
              SizedBox(
                height: 36,
                child: _phase == _VPhase.listening
                    ? ValueListenableBuilder<double>(
                        valueListenable: _voice.rms,
                        builder: (_, v, __) => MuseWaveform(
                          level: v,
                          color: accent,
                        ),
                      )
                    : MuseWaveform(level: 0, color: accent, active: false),
              ),
              const SizedBox(height: 10),
              // 中央脉冲圆钮。
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final listening = _phase == _VPhase.listening;
                  final p = listening ? _pulse.value : 0.0;
                  return SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (listening) ...[
                          _ring(
                              84 + 26 * p, accent.withOpacity(0.28 * (1 - p))),
                          _ring(84 + 13 * p, accent.withOpacity(0.2 * (1 - p))),
                        ],
                        Material(
                          color: _phase == _VPhase.error
                              ? MuseC.text(dark).withOpacity(0.08)
                              : accent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: needModel
                                ? (_downloading ? null : _install)
                                : (_phase == _VPhase.listening
                                    ? _manualStop
                                    : (_phase == _VPhase.error
                                        ? _restart
                                        : null)),
                            child: SizedBox(
                              width: 78,
                              height: 78,
                              child: Center(
                                child: switch (_phase) {
                                  _VPhase.listening => const Icon(
                                      Icons.mic_none_rounded,
                                      size: 30,
                                      color: Colors.white,
                                    ),
                                  _VPhase.processing => SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: MuseC.bubble(dark),
                                      ),
                                    ),
                                  _VPhase.result => Icon(
                                      Icons.check_rounded,
                                      size: 30,
                                      color: MuseC.bubble(dark),
                                    ),
                                  _VPhase.error => Icon(
                                      Icons.refresh_rounded,
                                      size: 28,
                                      color: MuseC.sub(dark),
                                    ),
                                  _VPhase.needModel => _downloading
                                      ? SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            value: _dl <= 0 ? null : _dl,
                                            strokeWidth: 2.6,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // 底部三键：取消 / 重录 / 填入输入框。
              // 没有「发送」——说完只把文字交给输入框，看清楚再发。
              Row(
                children: [
                  Expanded(
                    child: _ghostButton('取消', MuseC.sub(dark), _cancel),
                  ),
                  const SizedBox(width: 12),
                  _roundGhost(
                    icon: Icons.replay_rounded,
                    onTap: _phase == _VPhase.processing ? null : _restart,
                    dark: dark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fillButton(hasText, dark),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _ghostButton(String label, Color color, VoidCallback? onTap) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _roundGhost({
    required IconData icon,
    required VoidCallback? onTap,
    required bool dark,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.outlined(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: MuseC.sub(dark)),
        style: IconButton.styleFrom(
          side: BorderSide(
            color: (dark ? Colors.white : Colors.black).withOpacity(0.12),
            width: 1,
          ),
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _fillButton(bool enabled, bool dark) {
    final accent = MuseC.accent(dark);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        height: 44,
        child: TextButton.icon(
          onPressed: enabled ? _manualStop : null,
          style: TextButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          icon: const Icon(Icons.done_rounded, size: 18),
          label: Text(L10n.t('填入输入框'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
