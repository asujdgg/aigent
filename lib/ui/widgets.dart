import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../models/models.dart';
import '../services/model_brand.dart';
import '../services/voice_catalog.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'brand_icon.dart';
import 'model_picker_sheet.dart';
import 'muse.dart';
import 'persona.dart';

Future<void> openExternal(String? raw) async {
  if (raw == null || raw.trim().isEmpty) return;
  var s = raw.trim();
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null) return;
  try {
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 消息入场：一次性淡入 + 轻微上移 + 轻微放大。滚动出屏再回来不重播。
class AppearIn extends StatefulWidget {
  final String id;
  final Widget child;
  const AppearIn({super.key, required this.id, required this.child});

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> {
  static final Set<String> _played = <String>{};
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (_played.contains(widget.id)) {
      _shown = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_played.length > 400) _played.clear();
        _played.add(widget.id);
        setState(() => _shown = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.035),
      duration: D.animSlow,
      curve: D.curve,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: D.animSlow,
        curve: D.curve,
        child: AnimatedScale(
          scale: _shown ? 1 : 0.985,
          duration: D.animSlow,
          curve: D.curve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 分区标题：小字宽字距，无背景无图标。
class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text.toUpperCase(), style: sectionTitle(dark)),
    );
  }
}

/// 元信息：保持纯文字，不做胶囊，避免装饰堆砌。
class MetaChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? tint;
  const MetaChip(this.text, {super.key, this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: meta(dark, size: 11.5, color: tint ?? (dark ? C.dInk3 : C.ink3)),
    );
  }
}

/// 开关行：独立圆角卡片，轮廓与「开 / 关」状态一眼可辨。
/// 文字区与 Switch 区 hit test 物理隔离，各自只有一个回调，
/// 彻底避免「打开后关不掉」的双重触发。
class SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = value;
    final accent = accentOf(dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AnimatedContainer(
        duration: D.animFast,
        curve: D.curve,
        decoration: BoxDecoration(
          color: on ? accent.withOpacity(dark ? 0.12 : 0.055) : surfaceOf(dark),
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(
            color: on ? accent.withOpacity(0.55) : borderOf(dark),
            width: on ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(left: 13),
                child: Icon(icon,
                    size: 17, color: on ? accent : (dark ? C.dInk3 : C.ink3)),
              ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(!on),
                child: Padding(
                  padding:
                      EdgeInsets.fromLTRB(icon != null ? 10 : 14, 12, 6, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ts(
                          dark,
                          size: 13.5,
                          weight: on ? FontWeight.w600 : FontWeight.w500,
                          color: on
                              ? (dark ? C.dInk : C.ink)
                              : (dark ? C.dInk2 : C.ink2),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(subtitle, style: meta(dark, size: 11.5)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              on ? '开' : '关',
              style: meta(dark, size: 11.5, color: on ? accent : null),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 9),
              child: Switch(
                value: on,
                onChanged: onChanged,
                activeColor: accent,
                activeTrackColor: accent.withOpacity(0.3),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 档位选择：浅灰轨道 + 白色选中块 + 微阴影，克制无彩色渐变。
class TierSelector extends StatelessWidget {
  final Tier value;
  final ValueChanged<Tier> onChanged;
  const TierSelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: insetBox(dark, radius: D.r),
      child: Row(
        children: Tier.values.map((t) {
          final active = t == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(t),
              child: AnimatedContainer(
                duration: D.anim,
                curve: D.curve,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? surfaceOf(dark) : Colors.transparent,
                  borderRadius: BorderRadius.circular(D.r - 3),
                  border: active
                      ? Border.all(color: borderOf(dark), width: 1)
                      : null,
                  boxShadow: active ? softShadow(dark, scale: 0.35) : null,
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: D.anim,
                    curve: D.curve,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? (dark ? C.dInk : C.ink)
                          : (dark ? C.dInk3 : C.ink3),
                    ),
                    child: Text(t.label),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final bool dark;
  final VoidCallback? onRemove;
  const AttachmentChip({
    super.key,
    required this.attachment,
    required this.dark,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: fieldOf(dark),
        borderRadius: BorderRadius.circular(D.r),
        border: Border.all(color: borderOf(dark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (a.isImage)
            Image.memory(a.imageBytes!,
                fit: BoxFit.cover, gaplessPlayback: true)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.kind == AttachKind.pdf ? 'PDF' : 'FILE',
                      style: meta(dark, size: 11.5, color: accentOf(dark)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FileExtractServiceExt.shortName(a.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ts(dark, size: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 3,
              right: 3,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.58),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 11, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 仅供缩略图展示用的文件名裁剪，避免引入额外依赖。
class FileExtractServiceExt {
  static String shortName(String n) {
    return n.length > 14 ? '${n.substring(0, 11)}…' : n;
  }
}

class AttachmentStrip extends StatelessWidget {
  final List<Attachment> items;
  final bool dark;
  final ValueChanged<String>? onRemove;
  const AttachmentStrip({
    super.key,
    required this.items,
    required this.dark,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => AttachmentChip(
          attachment: items[i],
          dark: dark,
          onRemove: onRemove == null ? null : () => onRemove!(items[i].id),
        ),
      ),
    );
  }
}

class BlinkingCaret extends StatefulWidget {
  final bool dark;
  const BlinkingCaret({super.key, required this.dark});

  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<BlinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        width: 2.5,
        height: 16,
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: widget.dark ? C.brandDark : C.brand,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 思考面板：生成中直接铺开实时思考，结束后收成一行可展开的正文。
///
/// 之前只显示 116 字摘要，用户看到的永远是「已完成推理，结论见下方」——
/// 那等于没有思考过程。现在原文照录，只压空行。
class ThinkingPanel extends StatefulWidget {
  final ThinkingTrace trace;
  final bool dark;
  const ThinkingPanel({super.key, required this.trace, required this.dark});

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  bool _open = false;
  final ScrollController _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.trace,
      builder: (context, _) => _panel(),
    );
  }

  Widget _panel() {
    final t = widget.trace;
    final dark = widget.dark;
    final live = t.running;
    final expanded = live || _open;
    if (live) _follow();

    final stat = <String>[
      if (t.chars > 0) '${t.chars} 字',
      if (!live && t.elapsedLabel.isNotEmpty) t.elapsedLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: live ? null : () => setState(() => _open = !_open),
            child: Row(
              children: [
                if (live)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.4, color: accentOf(dark)),
                  )
                else
                  Icon(Icons.auto_awesome_outlined,
                      size: 13, color: dark ? C.dInk3 : C.ink3),
                const SizedBox(width: 7),
                Text(live ? '正在思考' : '思考过程',
                    style: ts(dark,
                        size: 13,
                        weight: FontWeight.w500,
                        color: dark ? C.dInk2 : C.ink2)),
                if (stat.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(stat, style: meta(dark, size: 11.5)),
                ],
                const Spacer(),
                if (!live)
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: D.anim,
                    curve: D.curve,
                    child: Icon(Icons.expand_more,
                        size: 16, color: dark ? C.dInk3 : C.ink3),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: D.animSlow,
            curve: D.curve,
            alignment: Alignment.topLeft,
            child: !expanded
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(top: 8, left: 1),
                    child: Container(
                      constraints: BoxConstraints(maxHeight: live ? 190 : 380),
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: borderOf(dark), width: 1),
                        ),
                      ),
                      child: SingleChildScrollView(
                        controller: _sc,
                        physics: const ClampingScrollPhysics(),
                        child: Text(
                          t.full.isEmpty
                              ? (live ? '等待模型返回思考内容…' : '这个模型没有返回思考过程。')
                              : t.full,
                          style: ts(dark,
                              size: 13,
                              height: 1.72,
                              color: dark ? C.dInk2 : C.ink2),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 引用来源

const List<String> _supDigits = [
  '⁰',
  '¹',
  '²',
  '³',
  '⁴',
  '⁵',
  '⁶',
  '⁷',
  '⁸',
  '⁹'
];

String _superscript(int n) =>
    n.toString().split('').map((c) => _supDigits[int.parse(c)]).join();

/// 把正文里的 [n] 角标替换为可点击的上标链接，跳过代码块。
/// 只有存在对应引用条目时才转换，避免误伤普通方括号文本。
String linkifyCitations(String src, int count) {
  if (count <= 0 || !src.contains('[')) return src;
  final parts = src.split('```');
  final pattern = RegExp(r'\[(\d{1,3})\]');
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].replaceAllMapped(pattern, (m) {
      final n = int.tryParse(m.group(1) ?? '') ?? 0;
      if (n < 1 || n > count) return m.group(0)!;
      return '[${_superscript(n)}](aigent://cite/$n)';
    });
  }
  return parts.join('```');
}

/// 流式过程中把未闭合的 Markdown 语法临时补全，让每个中间态都是合法结构。
/// 流式与结束都调用它，因此回答完成时正文字符串完全一致，不会整段重排。
String completeMarkdown(String src) {
  if (src.isEmpty) return src;
  var s = src;
  // 代码围栏：奇数个 ``` 表示还处在代码块中。
  if ('```'.allMatches(s).length.isOdd) s = '$s\n```';
  final parts = s.split('```');
  for (var i = 0; i < parts.length; i += 2) {
    var p = parts[i];
    if ('**'.allMatches(p).length.isOdd) p = '$p**';
    if ('`'.allMatches(p).length.isOdd) p = '$p`';
    parts[i] = p;
  }
  return parts.join('```');
}

/// 引用区：默认收起为一行，展开后是编号列表。
/// 与「思考过程」同一套语言：一行文字 + 展开后的细竖线，不再套内嵌卡片。
class CitationSection extends StatefulWidget {
  final List<Citation> citations;
  final bool dark;
  const CitationSection(
      {super.key, required this.citations, required this.dark});

  @override
  State<CitationSection> createState() => _CitationSectionState();
}

class _CitationSectionState extends State<CitationSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final list = widget.citations;
    if (list.isEmpty) return const SizedBox.shrink();
    final preview = list
        .take(3)
        .map((c) => c.host)
        .where((h) => h.isNotEmpty)
        .join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.public_outlined,
                      size: 13, color: dark ? C.dInk3 : C.ink3),
                  const SizedBox(width: 7),
                  Text(
                    _open ? '收起来源' : '来源 ${list.length} 条',
                    style: meta(dark, size: 11.5, color: dark ? C.dInk2 : C.ink2),
                  ),
                  if (!_open && preview.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11.5),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: D.anim,
                    curve: D.curve,
                    child: Icon(Icons.expand_more,
                        size: 15, color: dark ? C.dInk3 : C.ink3),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: D.animSlow,
            sizeCurve: D.curve,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              margin: const EdgeInsets.only(top: 6, left: 6),
              padding: const EdgeInsets.only(left: 11),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: borderOf(dark), width: 1),
                ),
              ),
              child: Column(
                children: list
                    .map((c) => CitationRow(citation: c, dark: dark))
                    .toList(),
              ),
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }
}

class CitationRow extends StatelessWidget {
  final Citation citation;
  final bool dark;
  const CitationRow({super.key, required this.citation, required this.dark});

  @override
  Widget build(BuildContext context) {
    final c = citation;
    return InkWell(
      onTap: () => openExternal(c.url),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                c.index.toString().padLeft(2, '0'),
                style: meta(dark, size: 11.5, color: accentOf(dark)),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ts(dark, size: 13, height: 1.45),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.source.isEmpty ? c.host : '${c.source} · ${c.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta(dark, size: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.arrow_outward,
                  size: 13, color: dark ? C.dInk3 : C.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 消息

class MessageCard extends StatelessWidget {
  final ChatMessage message;
  final bool dark;

  /// 原始输出：正文等宽原样呈现，不解析 Markdown、不转换引用角标。
  final bool raw;

  /// 人物形象；为 null 时不显示头像（关闭形象或 raw 模式）。
  final Persona? persona;

  /// v4.3 Muse 版式：助手深灰气泡、用户亮蓝气泡、长按呼出操作。
  /// false 时完全保留 v4.2 的裸排文档式版式。
  final bool muse;
  final VoidCallback onRegenerate;
  const MessageCard({
    super.key,
    required this.message,
    required this.dark,
    this.raw = false,
    this.persona,
    this.muse = false,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    // 每条消息独立重绘 + 独立监听，流式输出不会重建整个列表。
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: message,
        builder: (context, _) => _card(context),
      ),
    );
  }

  Widget _card(BuildContext context) {
    // 本机操作记录：单独一张低调的横条，不套气泡、不参与复制/朗读菜单。
    if (message.role == Role.tool) return _toolCard();
    if (muse) return _museCard(context);
    final m = message;
    final isUser = m.role == Role.user;
    final guard =
        Provider.of<AppState>(context, listen: false).guardNotice(m.content);

    // 用「段间距」代替「卡片边框」来分隔消息：回答之间留 26，用户提问后留 22。
    // 宽屏上把正文收在 720 以内，避免一行太长导致阅读时丢行。
    return Padding(
      padding: EdgeInsets.fromLTRB(D.pagePad, 0, D.pagePad, isUser ? 22 : 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child:
              isUser ? _userCard(m, guard) : _assistantCard(context, m, guard),
        ),
      ),
    );
  }

  /// 本机工具执行记录。刻意做成一条没有色块、没有圆角描边强调的横条：
  /// 它是「做过什么」的凭证，不该抢回答的视觉重心。
  Widget _toolCard() {
    final m = message;
    final ok = m.toolOk != false;
    final accent = accentOf(dark);
    final tint = ok ? accent : C.warn;
    final ms = m.toolMs ?? 0;
    final timeLabel = ms <= 0
        ? ''
        : (ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s');
    final title = m.toolName ?? '本机操作';
    final detail = m.content.trim();

    // 执行轨迹按「步骤」呈现：左侧序号圆点 + 竖线，右侧动作与结果摘要。
    // 之前每步一张带边框的小卡片，连续执行时像一排互不相关的通知，
    // 用户看不出这是同一个任务里的先后动作。
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tint.withOpacity(0.13),
                      ),
                      child: Center(
                        child: m.toolStep == null
                            ? Icon(
                                ok
                                    ? Icons.check_rounded
                                    : Icons.remove_rounded,
                                size: 12,
                                color: tint,
                              )
                            : Text(
                                '${m.toolStep}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                  color: tint,
                                ),
                              ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: detail.isEmpty ? 14 : 26,
                      color: lineOf(dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts(dark,
                                  size: 13, weight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ok ? '完成' : '未执行',
                            style: ts(dark,
                                size: 13,
                                weight: FontWeight.w500,
                                color: tint),
                          ),
                          if (timeLabel.isNotEmpty) ...[
                            Text(' · $timeLabel',
                                style: meta(dark, size: 11.5)),
                          ],
                        ],
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: meta(dark, size: 11.5, height: 1.55),
                        ),
                      ],
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

  // ------------------------------------------------ v4.3 Muse 气泡版式

  /// Muse 版：助手用宽灰气泡、用户用收缩蓝气泡，署名与统计不再挂在
  /// 每条消息上（统一交给顶部形象栏与长按菜单），画面才不会越聊越碎。
  Widget _museCard(BuildContext context) {
    final m = message;
    final isUser = m.role == Role.user;
    final guard =
        Provider.of<AppState>(context, listen: false).guardNotice(m.content);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, isUser ? 10 : 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: isUser
              ? _museUser(context, m, guard)
              : _museAssistant(context, m, guard),
        ),
      ),
    );
  }

  Widget _museUser(BuildContext context, ChatMessage m, String? guard) {
    return MuseBubble(
      dark: dark,
      user: true,
      onLongPress: () => _museActions(context, m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.attachments.isNotEmpty) ...[
            _museAttachments(m),
            if (m.content.isNotEmpty) const SizedBox(height: 10),
          ],
          if (m.content.isNotEmpty)
            Text(
              m.content,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.62,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
          if (guard != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                guard,
                style:
                    const TextStyle(fontSize: 11.5, color: Color(0xFFF0DCB4)),
              ),
            ),
        ],
      ),
    );
  }

  /// 单张图片按图 3 的样子放大成方块预览，多张才回落到缩略图条。
  Widget _museAttachments(ChatMessage m) {
    final list = m.attachments;
    if (list.length == 1 &&
        list.first.kind == AttachKind.image &&
        list.first.imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          list.first.imageBytes!,
          width: 210,
          height: 210,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return AttachmentStrip(items: list, dark: dark);
  }

  Widget _museAssistant(BuildContext context, ChatMessage m, String? guard) {
    return MuseBubble(
      dark: dark,
      wide: true,
      onLongPress: () => _museActions(context, m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.thinking != null) ThinkingPanel(trace: m.thinking!, dark: dark),
          RepaintBoundary(child: _body(context)),
          if (m.error != null) ...[
            const SizedBox(height: 10),
            Text('错误 · ${m.error}',
                style: ts(dark, size: 13, color: C.danger, height: 1.5)),
          ],
          if (guard != null) ...[
            const SizedBox(height: 10),
            Text(guard, style: ts(dark, size: 13, color: C.warn)),
          ],
          if (m.citations.isNotEmpty)
            CitationSection(citations: m.citations, dark: dark),
        ],
      ),
    );
  }

  /// 长按气泡呼出：复制 / 朗读 / 重新生成，顺带显示真实耗时与 token。
  /// 把操作藏进长按，气泡下方才能像参考图一样保持干净。
  void _museActions(BuildContext context, ChatMessage m) {
    final st = Provider.of<AppState>(context, listen: false);
    final stats = <String>[
      if (m.elapsedMs != null) '${(m.elapsedMs! / 1000).toStringAsFixed(1)} 秒',
      if (m.usage != null) '${m.usage!.prompt + m.usage!.completion} tokens',
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MuseC.bubble(dark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: MuseC.faint(dark),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              if (stats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    stats.join('   ·   '),
                    style: TextStyle(fontSize: 11.5, color: MuseC.sub(dark)),
                  ),
                ),
              _museActionTile(ctx, Icons.copy_all_outlined, '复制内容', () {
                Clipboard.setData(ClipboardData(text: m.content));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(t('已复制')), duration: const Duration(seconds: 1)),
                );
              }),
              if (m.role == Role.assistant &&
                  m.content.trim().isNotEmpty &&
                  st.settings.ttsEnabled)
                _museActionTile(ctx, Icons.graphic_eq_rounded, '朗读这条',
                    () async {
                  Navigator.pop(ctx);
                  if (st.settings.voiceMuted) {
                    st.apply((s) => s.voiceMuted = false);
                  }
                  final err = await st.speak(m.content);
                  if (err != null && err.isNotEmpty && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                  }
                }),
              if (m.role == Role.assistant)
                _museActionTile(ctx, Icons.refresh_rounded, '重新生成', () {
                  Navigator.pop(ctx);
                  onRegenerate();
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _museActionTile(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: MuseC.sub(dark)),
      title: Text(label,
          style: TextStyle(fontSize: 13.5, color: MuseC.text(dark))),
      onTap: onTap,
    );
  }

  /// 用户消息：右对齐实心气泡。去掉了阴影和右下角的小尖角——
  /// 那个「对话尾巴」是模板化 UI 的典型标记，去掉后立刻干净。
  Widget _userCard(ChatMessage m, String? guard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
            decoration: BoxDecoration(
              color: dark ? C.dBubble : C.bubble,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.attachments.isNotEmpty) ...[
                  AttachmentStrip(items: m.attachments, dark: dark),
                  const SizedBox(height: 10),
                ],
                if (m.content.isNotEmpty)
                  Text(
                    m.content,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.62,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (guard != null) ...[
          const SizedBox(height: 8),
          Text(guard, style: ts(dark, size: 13, color: C.warn)),
        ],
      ],
    );
  }

  /// 助手消息：**没有卡片**。回答是一段文档，直接排在画布上，
  /// 只有署名行和底部元信息。这是全应用最关键的「去 AI 味」决定：
  /// 正文不该被装进一个带描边、阴影和圆角的盒子里。
  Widget _assistantCard(BuildContext context, ChatMessage m, String? guard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _byline(m),
        const SizedBox(height: 11),
        if (m.thinking != null) ThinkingPanel(trace: m.thinking!, dark: dark),
        RepaintBoundary(child: _body(context)),
        if (m.error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            decoration: BoxDecoration(
              color: C.danger.withOpacity(dark ? 0.10 : 0.045),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('错误 · ${m.error}',
                style: ts(dark, size: 13, color: C.danger, height: 1.5)),
          ),
        ],
        if (guard != null) ...[
          const SizedBox(height: 10),
          Text(guard, style: ts(dark, size: 13, color: C.warn)),
        ],
        if (m.citations.isNotEmpty)
          CitationSection(citations: m.citations, dark: dark),
        _footer(m, context),
      ],
    );
  }

  /// 署名行：头像 + 名字 + 时间。模型名、档位、token 全部下沉到底部，
  /// 不在正文开头堆四个字段——读者先要读的是内容，不是元数据。
  Widget _byline(ChatMessage m) {
    final p = persona;
    return Row(
      children: [
        if (p != null)
          PersonaAvatar(persona: p, size: 22, dark: dark, ring: false)
        else
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(left: 3, right: 3),
            decoration: BoxDecoration(
              color: (dark ? C.dInk3 : C.ink3).withOpacity(0.7),
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            p?.name ?? (m.model ?? '助手'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(dark,
                size: 13,
                weight: FontWeight.w600,
                color: dark ? C.dInk2 : C.ink2),
          ),
        ),
        const Spacer(),
        Text(hhmm(m.at), style: meta(dark, size: 11.5)),
      ],
    );
  }

  Widget _textAction(String text, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          text,
          style: meta(dark, size: 11.5, color: dark ? C.dInk3 : C.ink3),
        ),
      ),
    );
  }

  /// 底部信息行全程占位：流式时半透明禁用，结束后只替换文字，
  /// 不再「凭空多出一行」把内容撑高。
  /// 数字用等宽字形，操作文字压到极淡——它们是「备选项」，不是重点。
  Widget _footer(ChatMessage m, BuildContext context) {
    final busy = m.streaming;
    final stats = <String>[
      if (m.elapsedMs != null) '${(m.elapsedMs! / 1000).toStringAsFixed(1)} 秒',
      if (m.usage != null) '${m.usage!.prompt + m.usage!.completion} tokens',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (busy)
            Text(t('生成中'), style: meta(dark, size: 11.5))
          else if (stats.isNotEmpty)
            Text(stats.join('   ·   '), style: numStyle(dark, size: 11.5)),
          const Spacer(),
          IgnorePointer(
            ignoring: busy,
            child: AnimatedOpacity(
              opacity: busy ? 0 : 1,
              duration: D.anim,
              child: Row(
                children: [
                  if (Provider.of<AppState>(context, listen: false)
                      .settings
                      .ttsEnabled) ...[
                    SpeakAction(text: m.content, dark: dark),
                    const SizedBox(width: 14),
                  ],
                  _textAction('复制', () {
                    Clipboard.setData(ClipboardData(text: m.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(t('已复制回答')),
                          duration: const Duration(seconds: 1)),
                    );
                  }),
                  const SizedBox(width: 14),
                  _textAction('重新生成', onRegenerate),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final m = message;
    if (m.content.isEmpty) {
      if (m.streaming) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BlinkingCaret(dark: dark),
            const SizedBox(width: 8),
            Text(t('等待模型输出'), style: sub(dark, size: 12.5)),
          ],
        );
      }
      return Text(t('（无内容）'), style: sub(dark, size: 12.5));
    }

    // 流式与结束共用同一个渲染路径：全程 Markdown（原始输出模式全程等宽纯文本）。
    // 旧实现流式用纯 Text、结束才切 Markdown，话一说完整段布局重排，
    // 看起来就像「文本自动修复了一下」。两边都做同样的语法补齐后，正文零突变。
    if (raw) {
      return SelectableText(
        m.content,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.65,
          color: dark ? C.dInk : C.ink,
        ),
      );
    }

    // Muse 气泡内空间更紧：字号、行高、段距都收一档，
    // 代码 / 引用块换成比气泡略亮的中性灰，否则会糊成一片。
    final pSize = muse ? 14.5 : 15.5;
    final pHeight = muse ? 1.68 : 1.8;
    final codeBg = muse ? MuseC.chip(dark) : fieldOf(dark);
    final linkColor = muse ? MuseC.accent(dark) : accentOf(dark);
    final data =
        completeMarkdown(linkifyCitations(m.content, m.citations.length));
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href != null && href.startsWith('aigent://cite/')) {
          final n = int.tryParse(href.split('/').last);
          if (n != null && n >= 1 && n <= m.citations.length) {
            openExternal(m.citations[n - 1].url);
          }
          return;
        }
        openExternal(href);
      },
      styleSheet: MarkdownStyleSheet(
        // 正文是这一屏的主角：裸排版 15.5/1.8，气泡内 14.5/1.68。
        p: ts(dark, size: pSize, height: pHeight).copyWith(letterSpacing: -0.1),
        pPadding: EdgeInsets.only(bottom: muse ? 10 : 14),
        h1: display(dark, size: muse ? 19 : 21),
        h2: display(dark, size: muse ? 16.5 : 17.5),
        h3: ts(dark, size: muse ? 14.5 : 15.5, weight: FontWeight.w600),
        h1Padding: const EdgeInsets.only(top: 12, bottom: 8),
        h2Padding: const EdgeInsets.only(top: 10, bottom: 5),
        h3Padding: const EdgeInsets.only(top: 8, bottom: 3),
        a: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withOpacity(0.35),
          decorationThickness: 1,
          fontSize: muse ? 14 : 15,
          fontWeight: FontWeight.w500,
        ),
        strong: ts(dark, size: pSize, weight: FontWeight.w700),
        em: ts(dark, size: pSize).copyWith(fontStyle: FontStyle.italic),
        listBullet: ts(dark, size: pSize, height: 1.5),
        listIndent: 22,
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          color: muse ? MuseC.text(dark) : (dark ? C.dInk : C.ink),
          backgroundColor: codeBg,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(D.r),
          border: Border.all(color: borderOf(dark)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          // 引用只用一条中性竖线，不加底色：底色 + 描边 + 圆角是「卡片化」的三件套。
          border: Border(
            left: BorderSide(
              color: muse ? MuseC.faint(dark) : borderOf(dark),
              width: 2,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
        blockSpacing: 14,
        tableHead: ts(dark, size: 13, weight: FontWeight.w600),
        tableBody: ts(dark, size: 13),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderOf(dark))),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 朗读

/// 朗读按钮：点一下开始，再点停止。
///
/// 用本地状态而不是全局 [VoiceService.speaking]，因为同一屏可能有多条回答，
/// 全局状态会让每一条都变成「停止」。
class SpeakAction extends StatefulWidget {
  final String text;
  final bool dark;
  const SpeakAction({super.key, required this.text, required this.dark});

  @override
  State<SpeakAction> createState() => _SpeakActionState();
}

class _SpeakActionState extends State<SpeakAction> {
  bool _busy = false;

  Future<void> _run() async {
    final st = Provider.of<AppState>(context, listen: false);
    if (_busy) {
      await st.stopSpeaking();
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() => _busy = true);
    final err = await st.speak(widget.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null && err.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final color = dark ? C.dInk3 : C.ink3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _run,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: ValueListenableBuilder<bool>(
          valueListenable: VoiceService.instance.speaking,
          builder: (context, speaking, _) {
            // 点了之后到真正出声之间是「准备中」：微软通道要先合成首段，
            // 这段空窗必须给反馈，否则和「点不动」没区别。
            final preparing = _busy && !speaking;
            final fg = _busy ? accentOf(dark) : color;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: preparing
                      ? Padding(
                          padding: const EdgeInsets.all(1.7),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            color: fg,
                          ),
                        )
                      : Icon(
                          _busy
                              ? Icons.stop_circle_outlined
                              : Icons.graphic_eq_rounded,
                          size: 13,
                          color: fg,
                        ),
                ),
                const SizedBox(width: 4),
                Text(
                  preparing ? '准备中' : (_busy ? '停止' : '朗读'),
                  style: meta(dark, size: 11.5, color: fg),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 状态与输入

/// 状态条：一行极淡的文字 + 细 spinner。文案由 ComposerBar 预先校正，
/// 联网关闭时绝不出现「联网 / 检索」字样。
/// 不套胶囊：状态是系统旁白，不是内容，用容器包起来会让它显得重要。
class StatusLine extends StatelessWidget {
  final String text;
  final bool dark;
  const StatusLine({super.key, required this.text, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(
            strokeWidth: 1.3,
            color: (dark ? C.dInk3 : C.ink3),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: meta(dark, size: 11.5)),
        ),
      ],
    );
  }
}

/// 联网开启时的常驻指示：一个极小圆点 + 源数量。关闭时完全不渲染。
class NetBadge extends StatelessWidget {
  final bool dark;
  final int sources;
  const NetBadge({super.key, required this.dark, required this.sources});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: (dark ? C.dInk3 : C.ink3).withOpacity(0.85),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text('联网 · $sources 源', style: meta(dark, size: 11.5)),
      ],
    );
  }
}

/// 研究工作流的进度条：四个阶段 + 当前步数。
///
/// 之前研究模式只在状态行里滚动一句「逐节展开 3/6」，用户看不到整体
/// 走到哪一步、还剩多少，长任务会以为卡死。这里把流程摊开成一条可读的
/// 轨道：检索 → 大纲 → 展开 → 核对。
class ResearchProgressBar extends StatelessWidget {
  final bool dark;
  final ResearchStage stage;
  final int step;
  final int total;
  final VoidCallback? onStop;

  const ResearchProgressBar({
    super.key,
    required this.dark,
    required this.stage,
    required this.step,
    required this.total,
    this.onStop,
  });

  static const List<ResearchStage> _order = [
    ResearchStage.searching,
    ResearchStage.outlining,
    ResearchStage.drafting,
    ResearchStage.verifying,
  ];

  int get _index {
    final i = _order.indexOf(stage);
    return i < 0 ? 0 : i;
  }

  double get _progress {
    switch (stage) {
      case ResearchStage.searching:
        return 0.12;
      case ResearchStage.outlining:
        return 0.3;
      case ResearchStage.drafting:
        final t = total <= 0 ? 0.0 : step / total;
        return (0.35 + t * 0.55).clamp(0.35, 0.9).toDouble();
      case ResearchStage.verifying:
        return 0.95;
      case ResearchStage.done:
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = MuseC.accent(dark);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      decoration: BoxDecoration(
        color: MuseC.chip(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black)
              .withOpacity(dark ? 0.08 : 0.06),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < _order.length; i++) ...[
                      _dot(i <= _index, accent),
                      if (i != _order.length - 1)
                        Expanded(
                          child: Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: i < _index
                                ? accent.withOpacity(0.55)
                                : (dark ? Colors.white : Colors.black)
                                    .withOpacity(0.10),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (onStop != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onStop,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(t('停止'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: MuseC.sub(dark))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                stage.label,
                style: ts(dark, size: 13, weight: FontWeight.w600),
              ),
              if (stage == ResearchStage.drafting && total > 0) ...[
                const SizedBox(width: 6),
                Text('$step/$total', style: meta(dark, size: 11.5)),
              ],
              const Spacer(),
              Text('${(_progress * 100).round()}%',
                  style: meta(dark, size: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 3,
              backgroundColor:
                  (dark ? Colors.white : Colors.black).withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(bool done, Color accent) {
    return AnimatedContainer(
      duration: D.animFast,
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? accent : (dark ? Colors.white : Colors.black).withOpacity(0.16),
      ),
    );
  }
}

class ComposerBar extends StatefulWidget {
  final bool dark;

  /// v4.3 Muse 外观：纯色无边框胶囊、蓝色发送键、能力指示 chip。
  final bool muse;

  /// 当前活动会话 id：草稿按会话独立保存 / 恢复，切换会话不再串字。
  final String convId;

  /// 程序化预填计数：变化时把草稿同步进输入框。
  final int draftSeed;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onFiles;
  final VoidCallback? onOpenSettings;
  const ComposerBar({
    super.key,
    required this.dark,
    required this.convId,
    required this.draftSeed,
    required this.onGallery,
    required this.onCamera,
    required this.onFiles,
    this.onOpenSettings,
    this.muse = false,
  });

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  bool _pressed = false;
  bool _hasText = false;

  /// 语音输入：录音前的草稿（识别结果会拼在它后面）。
  String _voiceBase = '';

  /// v4.4「按住说话」：长按语音键开始，松手结束，上滑取消。
  bool _holdActive = false;
  bool _holdCancelling = false;
  bool _holdSystem = false;
  bool _holdFinalSent = false;
  String _holdPartial = '';
  int _holdSecs = 0;
  Timer? _holdTimer;
  OverlayEntry? _holdOverlay;
  final ValueNotifier<int> _holdTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    final draft = context.read<AppState>().draftFor(widget.convId);
    _ctrl = TextEditingController(text: draft);
    _hasText = draft.trim().isNotEmpty;
    _focus = FocusNode();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 会话切换：把输入栏换成目标会话自己的草稿（旧草稿已在 onChanged 里
    // 实时写入对应会话，无需在此回存），并清掉发送键的按压态。
    if (oldWidget.convId != widget.convId ||
        oldWidget.draftSeed != widget.draftSeed) {
      final draft = context.read<AppState>().draftFor(widget.convId);
      if (_ctrl.text != draft) {
        _ctrl.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      }
      _hasText = draft.trim().isNotEmpty;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _removeHoldOverlay();
    VoiceService.instance.offlineActive.removeListener(_bumpHold);
    // 离开页面时把监听 / 录音收干净，否则麦克风会一直占用。
    if (_holdActive) {
      VoiceService.instance.cancelRecording();
      VoiceService.instance.cancelSystemListen();
    }
    _holdTick.dispose();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _bumpHold() {
    if (mounted) _holdTick.value++;
  }

  void _removeHoldOverlay() {
    _holdOverlay?.remove();
    _holdOverlay = null;
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 3)),
    );
  }

  /// 把识别结果写进输入框（保留录音前已输入的内容）。
  void _setVoiceText(String add) {
    final v = _voiceBase.isEmpty ? add : '$_voiceBase $add';
    _ctrl.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    _onDraftChanged(v);
  }

  /// 点麦克风：打开语音面板。说完静音自动停止，识别结果**只回填输入框**，
  /// 不替用户按发送键——识别错一两个字是常态，先看清楚、改一下再发。
  void _openVoiceSheet(AppState st) {
    if (st.generating) return;
    // 正在朗读（或还在合成）时开麦会把朗读声一起录进去，先停干净再听。
    unawaited(VoiceService.instance.stop());
    _voiceBase = _ctrl.text.trim();
    unawaited(showMuseVoiceSheet(
      context,
      dark: widget.dark,
      convId: widget.convId,
      onFill: _fillFromVoice,
      onOpenSettings: widget.onOpenSettings,
    ));
  }

  /// 语音识别结果的唯一落点：输入框。转完就安静地放进去，
  /// 不弹提示、不自动发送——文字已经在眼前，检查、改字、发送都由用户决定。
  void _fillFromVoice(String text) {
    if (text.trim().isEmpty || !mounted) return;
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _onDraftChanged(text);
    setState(() => _hasText = true);
    _focus.requestFocus();
  }

  // ------------------------------------------------ v4.4 按住说话

  /// 主键什么时候是「语音键」：没在生成、输入为空、也没有待发附件。
  bool _voiceKeyActive(AppState st) =>
      !st.generating && !_hasText && st.pending.isEmpty;

  Future<void> _startHold(AppState st) async {
    if (!st.settings.holdToTalk || !_voiceKeyActive(st)) return;
    final voice = VoiceService.instance;
    final engine = st.activeSttEngine;
    _voiceBase = _ctrl.text.trim();
    _holdActive = true;
    _holdCancelling = false;
    _holdFinalSent = false;
    _holdPartial = '';
    _holdSecs = 0;
    _holdSystem = engine.proto == VoiceProto.system;
    // 这里刻意不 setState：长按手势已在进行，重建输入栏有可能打断
    // 手势竞技场；浮层的状态全部由 _holdTick / rms 自行驱动。
    _installHoldOverlay();

    final bool ok;
    if (_holdSystem) {
      ok = await voice.startSystemListen(
        lang: st.settings.voiceLang,
        engine: engine.id,
        preferOffline: engine.offline || st.settings.sttPreferOffline,
        autoFallback: st.settings.sttAutoFallback,
        silenceMs: st.settings.sttSilenceMs,
        onText: _onHoldText,
        onSpeechEnd: _bumpHold,
        onNotice: _snack,
      );
    } else {
      ok = await voice.startRecording();
    }
    if (!ok) {
      await _finishHold(st, cancel: true, silent: true);
      if (mounted) {
        _snack(voice.lastError.trim().isEmpty
            ? (_holdSystem ? '系统识别不可用，可在设置 → 语音里换云端引擎' : '无法录音，请检查麦克风权限')
            : voice.lastError);
      }
      return;
    }
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _holdSecs++;
      _bumpHold();
      if (_holdSecs >= 90) {
        t.cancel();
        _finishHold(st);
      }
    });
  }

  /// 系统识别的边说边出字：实时写进输入框。静音 / 最终结果只做「停」，
  /// 文字留在输入框等用户确认，绝不自动发送。
  void _onHoldText(String text, bool isFinal) {
    if (!_holdActive || _holdCancelling) return;
    final t = text.trim();
    _holdPartial = t;
    if (t.isNotEmpty) _setVoiceText(t);
    _bumpHold();
    if (isFinal && !_holdFinalSent && t.isNotEmpty) {
      _holdFinalSent = true;
    }
  }

  void _installHoldOverlay() {
    if (_holdOverlay != null) return;
    final dark = widget.dark;
    VoiceService.instance.offlineActive.addListener(_bumpHold);
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _holdTick,
        builder: (_, __, ___) => MuseHoldToTalk(
          dark: dark,
          cancelling: _holdCancelling,
          offline: _holdSystem && VoiceService.instance.offlineActive.value,
          partial: _holdCancelling ? '' : _holdPartial,
          level: VoiceService.instance.rms,
        ),
      ),
    );
    _holdOverlay = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _updateHoldCancel(LongPressMoveUpdateDetails d) {
    if (!_holdActive) return;
    final cancel = d.offsetFromOrigin.dy < -72;
    if (cancel != _holdCancelling) {
      _holdCancelling = cancel;
      _bumpHold();
    }
  }

  Future<void> _finishHold(AppState st,
      {bool cancel = false, bool silent = false}) async {
    if (!_holdActive) return;
    _holdActive = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    final voice = VoiceService.instance;
    final wasCancelling = cancel || _holdCancelling;
    _removeHoldOverlay();
    voice.offlineActive.removeListener(_bumpHold);
    voice.rms.value = 0;
    if (mounted) {
      setState(() {
        _hasText = _ctrl.text.trim().isNotEmpty;
        // 长按赢下手势后 onTapUp 不会来，手动复原按压缩放。
        _pressed = false;
      });
    }

    if (wasCancelling) {
      if (_holdSystem) {
        await voice.cancelSystemListen();
      } else {
        await voice.cancelRecording();
      }
      // 取消时回到按下前的草稿，别把半句留在输入框。
      _ctrl.value = TextEditingValue(
        text: _voiceBase,
        selection: TextSelection.collapsed(offset: _voiceBase.length),
      );
      _onDraftChanged(_voiceBase);
      _holdPartial = '';
      return;
    }

    if (_holdSystem) {
      // stopListening 会让系统把最终结果回调回来，_onHoldText 已处理自动发送。
      await voice.stopSystemListen();
      return;
    }

    final engine = st.activeSttEngine;
    final text = await voice.stopAndTranscribe(
      engine: engine,
      baseUrl: st.resolveSttBaseUrl(),
      apiKey: st.resolveSttKey(),
      model: st.settings.sttModel.trim().isEmpty
          ? engine.model
          : st.settings.sttModel,
      lang: st.settings.voiceLang,
    );
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      if (!silent) {
        _snack(voice.lastError.trim().isEmpty ? '没有识别到内容' : voice.lastError);
      }
      return;
    }
    _setVoiceText(text.trim());
    // 只回填，不发送：松手之后文字留在输入框，看清楚再点发送。
    if (mounted) setState(() => _hasText = _ctrl.text.trim().isNotEmpty);
  }

  void _submit(AppState st) {
    final text = _ctrl.text;
    if (text.trim().isEmpty && st.pending.isEmpty) return;
    st.send(text);
    _ctrl.clear();
    st.setDraft(widget.convId, '');
  }

  void _onDraftChanged(String v) {
    // 只写内存草稿，不触发全局重建：输入时不会每字符刷新整页。
    context.read<AppState>().setDraft(widget.convId, v);
    // 主键在「语音 / 发送」之间切换，只在状态真的翻转时重建；
    // 长按录音期间不重建，避免打断正在进行的指针手势。
    final has = v.trim().isNotEmpty;
    if (!_holdActive && has != _hasText && mounted) {
      setState(() => _hasText = has);
    }
  }

  Widget _hintCard(
      bool dark, IconData icon, String text, List<Widget> actions) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius: BorderRadius.circular(D.r),
        border: Border.all(color: lineOf(dark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: C.warn),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: meta(dark, size: 11.5, color: dark ? C.dInk2 : C.ink2)),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _visionHint(bool dark, AppState st) {
    final acts = <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => st.patch((x) => x.visionHintDismissed = true),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, top: 1),
          child: Text(t('忽略'), style: meta(dark, size: 11.5, color: accentOf(dark))),
        ),
      ),
      if (widget.onOpenSettings != null)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenSettings,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 1),
            child:
                Text(t('去设置'), style: meta(dark, size: 11.5, color: accentOf(dark))),
          ),
        ),
    ];
    return _hintCard(
        dark, Icons.image_not_supported_outlined, st.visionHint!, acts);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dark = widget.dark;

    // 显示前的最终校正：联网不可用时，任何残留的联网 / 检索文案都不出现。
    final raw = st.status;
    final shown = (!st.settings.searchActive && AppState.isSearchStatus(raw))
        ? (st.generating ? '生成中…' : '')
        : raw;
    final showNet = st.settings.searchActive && shown.isEmpty && !st.generating;
    final muse = widget.muse;
    // 浅色模式改成纯白输入台 + 极淡描边（原来是浅灰实心块，容易显旧）；
    // 深色仍是中性深灰，和纯黑画布拉开一层。
    final fieldFill =
        muse ? (dark ? MuseC.bubble(dark) : Colors.white) : surfaceOf(dark);
    final iconColor = muse
        ? (dark ? MuseC.text(dark) : MuseC.ink2Light)
        : (dark ? C.dInk2 : C.ink2);

    return Container(
      padding: muse
          ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
          : const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: D.anim,
            curve: D.curve,
            alignment: Alignment.topCenter,
            child: shown.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 9),
                    child: StatusLine(text: shown, dark: dark),
                  )
                : showNet
                    ? Padding(
                        padding:
                            const EdgeInsets.only(left: 8, bottom: 9, top: 2),
                        child: NetBadge(
                            dark: dark,
                            sources: st.settings.activeSources.length),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
          ),
          // 图片识别不了的最常见原因：模型不支持视觉 / 请求体过大。发送前直接说清楚。
          if (st.visionHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 9, left: 2, right: 2),
              child: _visionHint(dark, st),
            ),
          if (st.imageSizeHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 9, left: 2, right: 2),
              child: _hintCard(
                  dark, Icons.data_usage_outlined, st.imageSizeHint!, const []),
            ),
          AnimatedSize(
            duration: D.anim,
            curve: D.curve,
            alignment: Alignment.topCenter,
            child: st.pending.isEmpty
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 2),
                    child: AttachmentStrip(
                      items: st.pending,
                      dark: dark,
                      onRemove: (id) => st.removeAttachment(id),
                    ),
                  ),
          ),
          // v4.9 输入台：上半是输入区，下半是一排能看见的开关。
          // 之前「深度思考 / 联网」藏在设置里，用户只能靠猜；现在直接
          // 摆在输入框下面，点一下就切，当前状态一眼可读。
          AnimatedContainer(
            duration: D.anim,
            curve: D.curve,
            decoration: BoxDecoration(
              color: muse ? MuseC.chip(dark) : fieldFill,
              borderRadius: BorderRadius.circular(muse ? 24 : 16),
              border: Border.all(
                color: _focus.hasFocus
                    ? MuseC.accent(dark).withOpacity(0.5)
                    : (dark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.07)),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.34 : 0.07),
                  blurRadius: dark ? 20 : 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(muse ? 14 : 10, 4, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 38),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: ts(dark, size: 15, height: 1.5),
                    decoration: InputDecoration(
                      hintText: _holdActive
                          ? '松开完成 · 上滑取消'
                          : (muse ? t('随便问点什么') : t('输入任务…')),
                      hintStyle: TextStyle(
                          color: muse
                              ? MuseC.faint(dark)
                              : (dark ? C.dInk3 : C.ink3),
                          fontSize: 14.5,
                          height: 1.4,
                          fontWeight: FontWeight.w400),
                      // v4.9.1：全局主题给输入框设了 filled: true（白底），
                      // 但这里的输入框本身就该「长」在外层胶囊上，多刷一层
                      // 白色只会切出一块方方正正的硬边。显式关掉填充，让文字
                      // 直接坐在容器底色上。
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(0, 9, 6, 9),
                      isDense: true,
                    ),
                    onChanged: _onDraftChanged,
                    onSubmitted: (_) => _submit(st),
                  ),
                ),
                const SizedBox(height: 2),
                // v4.11：换模型不必再滚回页面最顶部。输入台里常驻当前模型，
                // 左边点开列表、右边直达搜索，选完立刻回到对话。
                _modelStrip(st, dark),
                const SizedBox(height: 2),
                // v4.12：语音只留右侧主键一个入口（空输入时是「开始说话」，
                // 有文字时是发送），原来那颗独立小话筒与它重复，已删掉。
                // v4.13：字号调到「特大」又碰上 320dp 窄屏时，两个开关的
                // 文字会把主键挤出屏幕，所以这里按可用宽度自动收成纯图标。
                LayoutBuilder(builder: (_, box) {
                  // 320dp 常规字号下标签放得下；只有「又窄又放大了字号」
                  // 时才把标签收成图标，别为了极端组合牺牲默认观感。
                  final scale = MediaQuery.textScalerOf(context).scale(1.0);
                  // 320dp 屏上工具条可用宽度约 274，再窄或字号放大才收成纯图标。
                  final tight = box.maxWidth < 272 || scale > 1.15;
                  return Row(
                    children: [
                      _attach(dark, iconColor),
                      const SizedBox(width: 2),
                      _capToggle(
                        dark,
                        icon: Icons.auto_awesome_outlined,
                        label: '深度',
                        showLabel: !tight,
                        on: st.settings.deepThinking,
                        onTap: () =>
                            st.apply((x) => x.deepThinking = !x.deepThinking),
                      ),
                      const SizedBox(width: 6),
                      _capToggle(
                        dark,
                        icon: Icons.public_rounded,
                        label: '联网',
                        showLabel: !tight,
                        on: st.settings.searchActive,
                        onTap: () {
                          final next = !st.settings.webSearch;
                          st.apply((x) => x.webSearch = next);
                          // 开了总开关但没有启用任何搜索源时，状态仍是「关」，
                          // 用户会以为点坏了；这里说清楚该去哪儿。
                          if (next && st.settings.activeSources.isEmpty) {
                            _snack(t('还没有启用的搜索源，去 设置 → 搜索 里勾选'));
                          }
                        },
                      ),
                      const Spacer(),
                      _primaryKey(st, dark),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 输入台里的模型快捷条。左边是当前模型（点开就是完整列表），
  /// 右边是直达搜索；两处开的是同一个弹层，不必记住两个入口。
  Widget _modelStrip(AppState st, bool dark) {
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final sub = MuseC.sub(dark);
    final accent = MuseC.accent(dark);
    final model = st.settings.model.trim().isEmpty
        ? t('未指定模型')
        : st.settings.model.trim();
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openModelPicker(st),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandIcon(brand: resolveModelBrand(model), size: 18, dark: dark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: MuseC.text(dark)),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 14, color: sub),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openModelPicker(st),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: narrow ? 7 : 9, vertical: 4),
            decoration: BoxDecoration(
              color: MuseC.chip(dark).withOpacity(dark ? 0.9 : 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: dark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.black.withOpacity(0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 13, color: accent),
                if (!narrow) ...[
                  const SizedBox(width: 4),
                  Text(t('搜索模型'),
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: accent)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openModelPicker(AppState st) {
    _focus.unfocus();
    unawaited(showModelPickerSheet(
      context,
      dark: widget.dark,
      st: st,
      onOpenSettings: widget.onOpenSettings,
    ));
  }

  /// 附件入口：一个「＋」，点开才是相册 / 拍照 / 文件。
  Widget _attach(bool dark, Color iconColor) {
    return PopupMenuButton<int>(
      onSelected: (v) {
        if (v == 0) widget.onGallery();
        if (v == 1) widget.onCamera();
        if (v == 2) widget.onFiles();
      },
      padding: EdgeInsets.zero,
      color: surfaceOf(dark),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
      icon: SizedBox(
        width: 30,
        height: 30,
        child: Icon(Icons.add_rounded, size: 22, color: iconColor),
      ),
      itemBuilder: (context) => [
        _menuItem(0, Icons.photo_library_outlined, '相册图片', dark),
        _menuItem(1, Icons.photo_camera_outlined, '拍照', dark),
        _menuItem(2, Icons.attach_file_rounded, '文件 / PDF / CSV', dark),
      ],
    );
  }

  /// 输入框下方的小开关：开启是淡蓝底 + 蓝字，关闭是透明底 + 灰字。
  /// 不用 Switch 那种大控件，也不藏在菜单里——点一次就能看出开没开。
  Widget _capToggle(
    bool dark, {
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback onTap,
    bool showLabel = true,
  }) {
    final accent = MuseC.accent(dark);
    final off = MuseC.sub(dark);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: D.animFast,
        curve: D.curve,
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 8 : 7),
        decoration: BoxDecoration(
          color: on
              ? accent.withOpacity(dark ? 0.18 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: on ? accent : off),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? accent : off,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 右侧主键三态：生成中=停止，空输入=「开始说话」胶囊（点开语音面板、
  /// 长按按住说话），有文字=发送。形状从圆点改成胶囊，和左侧工具条同一
  /// 高度基线，不再像一颗孤零零的蓝点。
  Widget _primaryKey(AppState st, bool dark) {
    final voiceKey = _voiceKeyActive(st);
    final accent = MuseC.accent(dark);
    final danger = C.danger;

    late final Color bg;
    late final Color fg;
    late final String label;
    late final IconData? icon;
    if (st.generating) {
      bg = danger;
      fg = Colors.white;
      label = t('停止');
      icon = null;
    } else if (voiceKey) {
      // 空输入：走语音。深色主题给白胶囊（对比强），浅色主题给深胶囊。
      bg = dark ? Colors.white : const Color(0xFF1C1C1E);
      fg = dark ? const Color(0xFF111113) : Colors.white;
      label = t('开始说话');
      icon = Icons.graphic_eq_rounded;
    } else {
      bg = accent;
      fg = Colors.white;
      label = t('发送');
      icon = Icons.arrow_upward_rounded;
    }

    final child = AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: D.animFast,
      curve: D.curve,
      child: AnimatedContainer(
        duration: D.anim,
        curve: D.curve,
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: st.generating ? 12 : 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: bg.withOpacity(0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (st.generating)
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              )
            else
              Icon(icon, size: 16, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );

    void onTap() {
      if (voiceKey) {
        _openVoiceSheet(st);
      } else if (st.generating) {
        st.stop();
      } else {
        _submit(st);
      }
    }

    if (voiceKey && st.settings.holdToTalk) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _startHold(st),
        onLongPressMoveUpdate: _updateHoldCancel,
        onLongPressEnd: (_) => _finishHold(st),
        onLongPressCancel: () => _finishHold(st, cancel: true),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: onTap,
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: onTap,
      child: child,
    );
  }

  PopupMenuItem<int> _menuItem(int v, IconData icon, String text, bool dark) {
    return PopupMenuItem<int>(
      value: v,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: dark ? C.dInk2 : C.ink2),
          const SizedBox(width: 10),
          Text(text, style: ts(dark, size: 13)),
        ],
      ),
    );
  }
}
