import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// 圆形形象头像：自定义图片优先，否则用低饱和底色 + 字符。
/// 图片解码失败时自动回落到字符，绝不因坏数据崩溃。
class PersonaAvatar extends StatelessWidget {
  final Persona persona;
  final double size;
  final bool dark;
  final VoidCallback? onTap;
  final bool ring;

  /// 圆形底盘颜色；悬浮顶栏里用透明，让外层白色圆盘直接托住头像。
  final Color? backdrop;

  const PersonaAvatar({
    super.key,
    required this.persona,
    required this.size,
    required this.dark,
    this.onTap,
    this.ring = true,
    this.backdrop,
  });

  @override
  Widget build(BuildContext context) {
    Widget face;
    Uint8List? bytes;
    if (persona.hasImage) {
      try {
        bytes = base64Decode(persona.imageB64);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes != null) {
      face = Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _glyph(),
      );
    } else if (persona.builtin && persona.glyph.trim().isEmpty) {
      // v4.7：默认形象不再画一个彩色字母，直接用软件自己的启动图标。
      // 用户没自定义头像时，看到的就是桌面上的那个图标，不再有「预设人设」的观感。
      face = Image.asset(
        kAppIconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _glyph(),
      );
    } else {
      face = _glyph();
    }

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backdrop ?? surfaceOf(dark),
        border: ring ? Border.all(color: borderOf(dark), width: 1) : null,
        boxShadow: backdrop == null ? softShadow(dark, scale: 0.35) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipOval(child: face),
    );
    if (onTap == null) return avatar;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }

  Widget _glyph() {
    final g = persona.glyph.trim();
    final text = g.isEmpty ? 'A' : g;
    // emoji / 单个字符放大，多字（如「砚」或短名）略收。
    final fs = size * (text.length > 2 ? 0.3 : 0.42);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: persona.color,
      ),
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: fs,
            fontWeight: FontWeight.w500,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

/// 消息列表顶部的居中形象区：圆形头像 + 名字 + 一句话设定。
/// 点击可切换形象；整体保持留白与细线，不用渐变或彩色卡片。
class PersonaHeader extends StatelessWidget {
  final Persona persona;
  final bool dark;
  final VoidCallback onEdit;
  final bool compact;

  const PersonaHeader({
    super.key,
    required this.persona,
    required this.dark,
    required this.onEdit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // 会话顶部只保留一行「署名」：头像 + 名字 + 一句话设定。
    // 原来的居中三段式（头像 / 名字+状态点 / 蓝色切换链接 + 分隔线）
    // 会在每条会话开头重复一次自我介绍，是最典型的模板感来源。
    return Padding(
      padding: EdgeInsets.fromLTRB(
          D.pagePad, compact ? 14 : 26, D.pagePad, compact ? 4 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PersonaAvatar(
            persona: persona,
            size: compact ? 26 : 60,
            dark: dark,
            ring: false,
            onTap: onEdit,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              persona.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(dark,
                  size: 13,
                  weight: FontWeight.w600,
                  color: dark ? C.dInk2 : C.ink2),
            ),
          ),
          if (persona.tagline.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                persona.tagline.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta(dark, size: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空态：以人物形象为主角的欢迎页。
class PersonaHero extends StatelessWidget {
  final Persona persona;
  final bool dark;
  final VoidCallback onEdit;
  final VoidCallback onConfigure;
  final ValueChanged<String> onStarter;

  const PersonaHero({
    super.key,
    required this.persona,
    required this.dark,
    required this.onEdit,
    required this.onConfigure,
    required this.onStarter,
  });

  /// 建议项只给「动作」，不写「给我三个不同角度的看法」这类客套长句——
  /// 那种句式一眼就能看出是模型生成的文案。短、动词开头、不卖弄。
  static const List<String> kStarters = [
    '总结一篇文章',
    '解释一段代码',
    '把想法整理成大纲',
  ];

  @override
  Widget build(BuildContext context) {
    final dark = this.dark;
    // 左对齐的编辑式版面：形象缩小成「署名」，大标题成为主角。
    // 原来是「居中头像 + 名字 + 副标题 + 蓝色链接 + 分隔线 + 三张卡片」，
    // 那套结构几乎每个 AI 生成的落地页都长这样。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PersonaAvatar(
                    persona: persona,
                    size: 42,
                    dark: dark,
                    ring: false,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(persona.name, style: display(dark, size: 17)),
                        if (persona.tagline.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            persona.tagline.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(dark,
                                size: 13,
                                color: dark ? C.dInk3 : C.ink3,
                                height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Text(t('编辑'),
                          style: meta(dark,
                              size: 11.5, color: dark ? C.dInk3 : C.ink3)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Text(t('说点什么'), style: display(dark, size: 27)),
              const SizedBox(height: 9),
              Text(t('直接输入，或者从下面挑一个开头。'),
                style: ts(dark,
                    size: 13, color: dark ? C.dInk2 : C.ink2, height: 1.6),
              ),
              const SizedBox(height: 24),
              Container(height: 1, color: hairOf(dark)),
              for (final s in kStarters) _starterRow(s),
              const SizedBox(height: 24),
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onConfigure,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 14, color: dark ? C.dInk3 : C.ink3),
                        const SizedBox(width: 7),
                        Text(t('配置连接'),
                            style: ts(dark,
                                size: 13, color: dark ? C.dInk2 : C.ink2)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('AIGENT  ·  V$kAppVersion', style: meta(dark, size: 11.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 建议项：无卡片、无底色，只有细分隔线。整行可点。
  Widget _starterRow(String s) {
    final dark = this.dark;
    return InkWell(
      onTap: () => onStarter(s),
      splashColor: (dark ? C.dInk2 : C.ink2).withOpacity(0.05),
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairOf(dark))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(s,
                  style: ts(dark, size: 14, color: dark ? C.dInk : C.ink)),
            ),
            Icon(Icons.arrow_outward_rounded,
                size: 14, color: dark ? C.dInk3 : C.ink3),
          ],
        ),
      ),
    );
  }
}

/// 形象切换弹层：列出形象库，可为当前会话单独指定，或进入设置编辑。
class PersonaPickerSheet extends StatelessWidget {
  final bool dark;
  final VoidCallback onOpenSettings;
  const PersonaPickerSheet({
    super.key,
    required this.dark,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final conv = st.active;
    return Container(
      decoration: BoxDecoration(
        color: surfaceOf(dark),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(D.floatR)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(D.pagePad, 12, D.pagePad, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderOf(dark),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(t('选择形象'), style: display(dark, size: 19)),
              if (s.personas.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(t('可为当前这个工作台单独指定，不影响其它工作台。'),
                    style: meta(dark, size: 11.5)),
              ],
              const SizedBox(height: 16),
              if (s.personas.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: s.personas.length,
                  separatorBuilder: (_, __) =>
                      Container(height: 1, color: hairOf(dark)),
                  itemBuilder: (_, i) {
                    final p = s.personas[i];
                    final current =
                        conv.personaId.isEmpty ? s.activePersonaId : conv.personaId;
                    final selected = p.id == current;
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      leading: PersonaAvatar(persona: p, size: 38, dark: dark),
                      title: Text(p.name,
                          style: ts(dark,
                              size: 13.5,
                              weight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                      subtitle: p.tagline.trim().isEmpty
                          ? null
                          : Text(p.tagline.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: meta(dark, size: 11.5)),
                      trailing: selected
                          ? Icon(Icons.check_rounded,
                              size: 18, color: accentOf(dark))
                          : null,
                      onTap: () {
                        st.setConversationPersona(conv.id, p.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // 空库只可能是异常兜底：正常入口在没有形象时直接进设置新建。
              if (s.personas.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(t('还没有形象。点下面新建一个，头像、名字、说话方式都可以自己定。'),
                    style: meta(dark, size: 11.5, height: 1.6),
                  ),
                ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onOpenSettings();
                },
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: C.brand,
                    borderRadius: BorderRadius.circular(D.r),
                    boxShadow: softShadow(dark, scale: 0.45),
                  ),
                  child: Center(
                    child: Text(s.personas.isEmpty ? '新建形象' : '管理形象 · 自定义头像与设定',
                        style: ts(dark,
                            size: 13,
                            weight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开形象切换弹层。
Future<void> showPersonaPicker(
  BuildContext context, {
  required bool dark,
  required VoidCallback onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PersonaPickerSheet(
      dark: dark,
      onOpenSettings: onOpenSettings,
    ),
  );
}

// ---------------------------------------------------------------- 形象编辑

/// 单个形象的编辑卡：头像、名字、一句话设定、字符 / emoji、角色设定、主题色。
/// 输入即时写入（乐观更新，不重建整页），切换形象时通过 didUpdateWidget 重载。
class PersonaEditor extends StatefulWidget {
  final Persona persona;
  final bool dark;
  final VoidCallback onChanged;
  const PersonaEditor({
    super.key,
    required this.persona,
    required this.dark,
    required this.onChanged,
  });

  @override
  State<PersonaEditor> createState() => _PersonaEditorState();
}

class _PersonaEditorState extends State<PersonaEditor> {
  late final TextEditingController _name;
  late final TextEditingController _tagline;
  late final TextEditingController _glyph;
  late final TextEditingController _role;
  late String _loadedId;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadedId = widget.persona.id;
    _name = TextEditingController(text: widget.persona.name);
    _tagline = TextEditingController(text: widget.persona.tagline);
    _glyph = TextEditingController(text: widget.persona.glyph);
    _role = TextEditingController(text: widget.persona.roleHint);
  }

  @override
  void didUpdateWidget(covariant PersonaEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.persona.id != _loadedId) {
      _loadedId = widget.persona.id;
      _name.text = widget.persona.name;
      _tagline.text = widget.persona.tagline;
      _glyph.text = widget.persona.glyph;
      _role.text = widget.persona.roleHint;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _glyph.dispose();
    _role.dispose();
    super.dispose();
  }

  AppState get st => context.read<AppState>();

  void _save() {
    // 文字只写数据、不 setState：输入时不会逐字重建整张设置卡。
    // 头像 / 主题色这类需要即时反馈的操作才调用 onChanged 刷新。
    st.updatePersona(
      widget.persona.id,
      name: _name.text,
      tagline: _tagline.text,
      glyph: _glyph.text,
      roleHint: _role.text,
    );
  }

  Future<void> _pickAvatar() async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 78,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      st.setPersonaAvatar(widget.persona.id, bytes);
      widget.onChanged();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final p = widget.persona;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 头像 + 操作 ----
        Row(
          children: [
            PersonaAvatar(
              persona: p,
              size: 62,
              dark: dark,
              onTap: _pickAvatar,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('点击头像从相册选择'), style: ts(dark, size: 13)),
                  const SizedBox(height: 3),
                  Text(t('自动压缩到 320px，仅存本地'), style: meta(dark, size: 11.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _miniBtn(dark, '选择图片', _pickAvatar),
                      const SizedBox(width: 8),
                      if (p.hasImage)
                        _miniBtn(dark, '移除图片', () {
                          st.clearPersonaAvatar(p.id);
                          widget.onChanged();
                        }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _label(dark, '名字'),
        _box(_name, '给形象起个名字', onChanged: (_) => _save()),
        const SizedBox(height: 14),
        _label(dark, '一句话设定'),
        _box(_tagline, '展示在名字下方', onChanged: (_) => _save()),
        const SizedBox(height: 14),
        _label(dark, '头像字符 / EMOJI（无自定义图片时显示）'),
        _box(_glyph, 'A / 砚 / ✦ / 🐤', onChanged: (_) => _save()),
        const SizedBox(height: 14),
        _label(dark, '角色设定（会写入 System Prompt）'),
        TextField(
          controller: _role,
          minLines: 3,
          maxLines: 6,
          style: ts(dark, size: 13, height: 1.6),
          decoration: _deco(dark, '例如：语气克制、先给结论、擅长把复杂问题拆成结构…'),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 16),
        _label(dark, '主题色'),
        const SizedBox(height: 9),
        Row(
          children: [
            for (var i = 0; i < kPersonaTints.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    st.updatePersona(p.id, tint: i);
                    widget.onChanged();
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: kPersonaTints[i],
                      shape: BoxShape.circle,
                      border: p.tint == i
                          ? Border.all(color: dark ? C.dInk : C.ink, width: 2)
                          : null,
                    ),
                    child: p.tint == i
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _label(bool dark, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text.toUpperCase(), style: sectionTitle(dark)),
      );

  Widget _box(TextEditingController c, String hint,
          {ValueChanged<String>? onChanged}) =>
      TextField(
        controller: c,
        maxLines: 1,
        style: ts(widget.dark, size: 13, height: 1.4),
        decoration: _deco(widget.dark, hint),
        onChanged: onChanged,
      );

  InputDecoration _deco(bool dark, String hint) => fieldDecoration(
        dark,
        hint: hint,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      );

  Widget _miniBtn(bool dark, String text, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: surfaceOf(dark),
            borderRadius: BorderRadius.circular(D.r),
            border: Border.all(color: borderOf(dark)),
          ),
          child: Text(text, style: meta(dark, size: 11.5, color: accentOf(dark))),
        ),
      );
}
