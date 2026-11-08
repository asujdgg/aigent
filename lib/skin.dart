import 'package:flutter/material.dart';

/// v4.15 皮肤系统：整套语义色由一份「预设 + 自定义」配置生成。
///
/// 设计原则和 v4 最初的 Quiet Depth 一致——只有画布、纸面、墨色三层，
/// 强调色只用于可点的地方。主题不是换一堆花哨颜色，而是换这三层的
/// 冷暖与明度关系：GitHub 的纸白、Nord 的冷灰、Gruvbox 的暖褐，
/// 各自成立但都不抢内容。
///
/// 所有界面代码仍在用 `C.ink` / `MuseC.bubble(dark)` 这类固定名字，
/// 这里把名字映射到当前皮肤，换肤时不用改任何调用点。
class Palette {
  final Color bg;
  final Color surface;
  final Color chip;
  final Color sink;
  final Color line;
  final Color hair;
  final Color border;
  final Color borderStrong;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color accent;
  final Color bubble;
  final Color ok;
  final Color warn;
  final Color danger;

  const Palette({
    required this.bg,
    required this.surface,
    required this.chip,
    required this.sink,
    required this.line,
    required this.hair,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.bubble,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  /// 从「画布 / 纸面 / 强调色」三颗种子派生整张色板。
  /// 只让用户挑这三样，其余明度关系由代码保证，避免自定义出一套读不清的字。
  factory Palette.seed({
    required Color bg,
    required Color surface,
    required Color accent,
    required bool dark,
  }) {
    Color mix(Color a, Color b, double t) =>
        Color.lerp(a, b, t.clamp(0.0, 1.0))!;
    final ink = dark ? const Color(0xFFF2F2F5) : const Color(0xFF15171B);
    return Palette(
      bg: bg,
      surface: surface,
      chip: mix(surface, ink, dark ? 0.075 : 0.055),
      sink: mix(surface, ink, dark ? 0.05 : 0.035),
      line: mix(surface, ink, dark ? 0.15 : 0.10),
      hair: mix(surface, ink, dark ? 0.10 : 0.065),
      border: mix(surface, ink, dark ? 0.17 : 0.12),
      borderStrong: mix(surface, ink, dark ? 0.36 : 0.28),
      ink: ink,
      ink2: mix(ink, bg, dark ? 0.40 : 0.42),
      ink3: mix(ink, bg, dark ? 0.58 : 0.60),
      accent: accent,
      bubble: accent,
      ok: dark ? const Color(0xFF7EC699) : const Color(0xFF2F6B4F),
      warn: dark ? const Color(0xFFE0B060) : const Color(0xFF8A6A33),
      danger: dark ? const Color(0xFFF08A8A) : const Color(0xFFB04444),
    );
  }
}

/// 一套主题预设。亮暗各一张色板，随系统 / 设置切换。
class SkinPreset {
  final String id;
  final String name;
  final String note;
  final Palette light;
  final Palette dark;
  final Color swatch; // 设置页色卡用

  const SkinPreset({
    required this.id,
    required this.name,
    required this.note,
    required this.light,
    required this.dark,
    required this.swatch,
  });
}

/// 全局皮肤。由 `main.dart` 在构建 MaterialApp 前写入；
/// 设置页改动后整页重建，立即生效。
class Skin {
  static Palette light = kSkinPresets.first.light;
  static Palette dark = kSkinPresets.first.dark;

  /// 圆角强度：0.6（硬朗）~ 1.4（圆润）。只影响带圆角的容器。
  static double radius = 1.0;

  static SkinPreset get preset => _active;
  static SkinPreset _active = kSkinPresets.first;

  static void applyPreset(SkinPreset p, {double radiusScale = 1.0}) {
    _active = p;
    light = p.light;
    dark = p.dark;
    radius = radiusScale;
  }

  /// 自定义：三颗种子 + 圆角，亮暗共用同一支强调色。
  static void applyCustom({
    required Color accent,
    Color? canvasLight,
    Color? canvasDark,
    double radiusScale = 1.0,
  }) {
    final l = canvasLight ?? const Color(0xFFF6F7F9);
    final d = canvasDark ?? const Color(0xFF0B0B0D);
    final p = SkinPreset(
      id: 'custom',
      name: '自定义',
      note: '你的配方',
      light: Palette.seed(
        bg: l,
        surface: _paperOver(l),
        accent: accent,
        dark: false,
      ),
      dark: Palette.seed(
        bg: d,
        surface: _paperOver(d),
        accent: accent,
        dark: true,
      ),
      swatch: accent,
    );
    applyPreset(p, radiusScale: radiusScale);
  }

  /// 纸面比画布亮一档（浅色）或亮两档（深色），保证卡片浮得起来。
  static Color _paperOver(Color bg) {
    final isDark = bg.computeLuminance() < 0.4;
    return Color.lerp(bg, Colors.white, isDark ? 0.075 : 0.62)!;
  }

  static SkinPreset? byId(String id) {
    for (final p in kSkinPresets) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 内置主题。数量刻意多：有人喜欢纯白纸面，有人喜欢暖褐，
/// 也有人只在夜里用低对比的灰蓝；这些都不该被迫接受同一套配色。
final List<SkinPreset> kSkinPresets = [
  // 默认：v4 原本的「静水深」配色。升级后外观不变，其它主题都是额外选择。
  _preset('quiet', '静水深', '默认 · 克制', const Color(0xFF3478F6),
      const Color(0xFFFFFFFF), const Color(0xFFF2F4F7),
      const Color(0xFF6BA4FF), const Color(0xFF000000),
      const Color(0xFF141416)),
  _preset('github', 'GitHub', '纸白 · 工程感', const Color(0xFF0969DA),
      const Color(0xFFFFFFFF), const Color(0xFFF6F8FA),
      const Color(0xFF2F81F7), const Color(0xFF0D1117),
      const Color(0xFF161B22)),
  _preset('chatgpt', 'ChatGPT', '中性灰 · 专注', const Color(0xFF10A37F),
      const Color(0xFFFFFFFF), const Color(0xFFF7F7F8),
      const Color(0xFF10A37F), const Color(0xFF212121),
      const Color(0xFF2F2F2F)),
  _preset('claude', 'Claude', '暖米 · 纸张', const Color(0xFFC96442),
      const Color(0xFFFAF9F5), const Color(0xFFFFFFFF),
      const Color(0xFFD97757), const Color(0xFF262624),
      const Color(0xFF30302E)),
  _preset('nord', 'Nord', '冷蓝灰 · 克制', const Color(0xFF5E81AC),
      const Color(0xFFECEFF4), const Color(0xFFFFFFFF),
      const Color(0xFF88C0D0), const Color(0xFF2E3440),
      const Color(0xFF3B4252)),
  _preset('dracula', 'Dracula', '紫调 · 夜行', const Color(0xFF7B5BD6),
      const Color(0xFFF8F8F2), const Color(0xFFFFFFFF),
      const Color(0xFFBD93F9), const Color(0xFF282A36),
      const Color(0xFF44475A)),
  _preset('solarized', 'Solarized', '暖纸 · 低对比', const Color(0xFF268BD2),
      const Color(0xFFFDF6E3), const Color(0xFFFFFBF0),
      const Color(0xFF4FA3DC), const Color(0xFF002B36),
      const Color(0xFF073642)),
  _preset('gruvbox', 'Gruvbox', '暖褐 · 复古', const Color(0xFFC35A11),
      const Color(0xFFFBF1C7), const Color(0xFFFFF8DC),
      const Color(0xFFFABD2F), const Color(0xFF282828),
      const Color(0xFF3C3836)),
  _preset('one', 'One Dark', '石墨 · 经典', const Color(0xFF4078F2),
      const Color(0xFFFAFAFA), const Color(0xFFFFFFFF),
      const Color(0xFF61AFEF), const Color(0xFF282C34),
      const Color(0xFF2C313A)),
  _preset('catppuccin', 'Catppuccin', '柔紫 · 奶油', const Color(0xFF8839EF),
      const Color(0xFFEFF1F5), const Color(0xFFFFFFFF),
      const Color(0xFFCBA6F7), const Color(0xFF1E1E2E),
      const Color(0xFF313244)),
  _preset('tokyo', 'Tokyo Night', '深蓝 · 霓虹', const Color(0xFF3D6FE0),
      const Color(0xFFF5F5FA), const Color(0xFFFFFFFF),
      const Color(0xFF7AA2F7), const Color(0xFF1A1B26),
      const Color(0xFF24283B)),
  _preset('monokai', 'Monokai', '炭黑 · 高饱和', const Color(0xFFD93B2B),
      const Color(0xFFFAFAF5), const Color(0xFFFFFFFF),
      const Color(0xFFA6E22E), const Color(0xFF272822),
      const Color(0xFF3E3D32)),
  _preset('rosepine', 'Rosé Pine', '玫瑰 · 柔雾', const Color(0xFFB4637A),
      const Color(0xFFFAF4ED), const Color(0xFFFFFFFF),
      const Color(0xFFEBBCBA), const Color(0xFF191724),
      const Color(0xFF1F1D2E)),
  _preset('linear', 'Linear', '极简 · 产品感', const Color(0xFF5E6AD2),
      const Color(0xFFFFFFFF), const Color(0xFFF7F8FA),
      const Color(0xFF7C88E8), const Color(0xFF08090A),
      const Color(0xFF141516)),
  _preset('notion', 'Notion', '文档 · 米白', const Color(0xFF337EA9),
      const Color(0xFFFFFFFF), const Color(0xFFF7F6F3),
      const Color(0xFF4E9ECD), const Color(0xFF191919),
      const Color(0xFF202020)),
  _preset('vercel', 'Vercel', '黑白 · 锐利', const Color(0xFF111111),
      const Color(0xFFFFFFFF), const Color(0xFFFAFAFA),
      const Color(0xFF0070F3), const Color(0xFF000000),
      const Color(0xFF111111)),
  _preset('everforest', 'Everforest', '森绿 · 护眼', const Color(0xFF6E8B1F),
      const Color(0xFFFDF6E3), const Color(0xFFFFFBF0),
      const Color(0xFFA7C080), const Color(0xFF2D353B),
      const Color(0xFF343F44)),
  _preset('ayu', 'Ayu', '琥珀 · 清透', const Color(0xFFE08A2E),
      const Color(0xFFFAFAFA), const Color(0xFFFFFFFF),
      const Color(0xFFE6B450), const Color(0xFF0B0E14),
      const Color(0xFF1B1F27)),
  _preset('kanagawa', 'Kanagawa', '靛青 · 浮世绘', const Color(0xFFC84053),
      const Color(0xFFF8F5EE), const Color(0xFFFFFFFF),
      const Color(0xFF7E9CD8), const Color(0xFF1F1F28),
      const Color(0xFF2A2A37)),
];

SkinPreset _preset(
  String id,
  String name,
  String note,
  Color accentLight,
  Color paperLight,
  Color canvasLight,
  Color accentDark,
  Color canvasDark,
  Color paperDark,
) {
  return SkinPreset(
    id: id,
    name: name,
    note: note,
    light: Palette.seed(
      bg: canvasLight,
      surface: paperLight,
      accent: accentLight,
      dark: false,
    ),
    dark: Palette.seed(
      bg: canvasDark,
      surface: paperDark,
      accent: accentDark,
      dark: true,
    ),
    swatch: accentLight,
  );
}

/// 解析 `#RRGGBB` / `RRGGBB`，失败时回退。
Color colorFromHex(String raw, Color fallback) {
  final v = raw.trim().replaceFirst('#', '');
  if (v.length == 6 || v.length == 8) {
    final n = int.tryParse(v, radix: 16);
    if (n != null) {
      return Color(v.length == 6 ? (0xFF000000 | n) : n);
    }
  }
  return fallback;
}

String hexOf(Color c) =>
    '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 把设置里的皮肤参数落到全局。启动与每次改主题都会走这里。
void applySkinFromSettings({
  required String id,
  required String accent,
  required String canvas,
  required double radius,
}) {
  if (id == 'custom') {
    final a = colorFromHex(accent, const Color(0xFF3478F6));
    final l = canvas.trim().isEmpty
        ? const Color(0xFFF6F7F9)
        : colorFromHex(canvas, const Color(0xFFF6F7F9));
    // 深色画布由浅色画布压暗而来，保持同一色相，不额外发明一种颜色。
    final d = Color.lerp(l, Colors.black, 0.93)!;
    Skin.applyCustom(
      accent: a,
      canvasLight: l,
      canvasDark: d,
      radiusScale: radius,
    );
    return;
  }
  final p = Skin.byId(id) ?? kSkinPresets.first;
  Skin.applyPreset(p, radiusScale: radius);
}
