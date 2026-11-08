import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'i18n.dart';
import 'models/models.dart';
import 'skin.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  final state = AppState();
  // 只做本地凭据读取（毫秒级），不阻塞首帧渲染，保证冷启动速度。
  await state.boot();
  // 界面语言词表从 assets 读一次（几十毫秒），首帧就是目标语言，
  // 不会先闪一帧中文再切换。
  await L10n.load(state.settings.uiLang);

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const AgentApp(),
    ),
  );
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, ({AppThemeMode mode, double scale, String skin, String accent, String canvas, double radius, String uiLang})>(
      selector: (_, s) => (
        mode: s.settings.themeMode,
        scale: s.settings.fontScale,
        skin: s.settings.skinId,
        accent: s.settings.skinAccent,
        canvas: s.settings.skinCanvas,
        radius: s.settings.skinRadius,
        uiLang: s.settings.uiLang,
      ),
      builder: (_, pref, __) {
        // 皮肤是全局单例：先落到 C / MuseC，再构建两套 ThemeData，
        // 这样所有页面（包括已经打开的弹层）下一次重建就是新配色。
        // 词表已在启动 / 切换语言时载入，这里只负责调色板。
        applySkinFromSettings(
          id: pref.skin,
          accent: pref.accent,
          canvas: pref.canvas,
          radius: pref.radius,
        );
        return MaterialApp(
        title: 'Aigent',
        debugShowCheckedModeBanner: false,
        // 亮/暗两套主题同时提供，交给 ThemeMode 决定：
        // system 时由 Android 平台亮度实时驱动，无需重启。
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: flutterThemeMode(pref.mode),
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          // 字号设置：只缩放文字，不动布局尺寸——各页写死的行高与间距
          // 保持稳定，避免「调大字号 → 按钮被撑破」。
          final mq = MediaQuery.of(context);
          // 状态栏 / 导航栏图标随当前主题反转，深色底用亮色图标。
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              // 小米 / OPPO / vivo 默认会给透明导航栏加一层半透明遮罩，
              // 关掉后页面颜色才能真正铺到屏幕底边。
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            ),
            // 阿拉伯语 / 希伯来语 / 波斯语 / 乌尔都语从右往左排。
            // MaterialApp 的 locale 仍按系统，这里显式覆盖方向，
            // 免得选了 RTL 语言却还在左边对齐。
            child: Directionality(
              textDirection: kRtlLangs.contains(pref.uiLang)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: MediaQuery(
                data: mq.copyWith(
                  // 字号 = 用户档位 × 阅读基准 × 系统字体缩放。
                  textScaler: TextScaler.linear(effectiveTextScale(
                    pref.scale,
                    mq.textScaler.scale(14) / 14,
                  )),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
          // 语言变化时只重建首页：整棵 MaterialApp 换 key 虽然也能刷新文案，
          // 但会把路由栈一起清空——用户在设置页切语言会被弹回主页。
          home: KeyedSubtree(
            key: ValueKey('lang-${pref.uiLang}'),
            child: const WorkspaceScreen(),
          ),
        );
      },
    );
  }
}

/// 从右往左书写的界面语言。
const Set<String> kRtlLangs = {'ar', 'he', 'fa', 'ur'};

/// 阅读基准系数。
///
/// 页面里的字号是按「排版稿」写的（正文 15.5 / 气泡 14.5 / 辅助 11.5），
/// 直接渲染到手机上偏小——这是 v4.16 之前默认字看着累的根因。
/// ChatGPT 的对话正文是 16sp、Gemini 约 16sp、系统设置正文 16sp，
/// 这里统一乘 1.10：正文 15.5 → 17，气泡 14.5 → 16，辅助 11.5 → 12.7，
/// 既不挤爆既有行高，也落在人眼最舒服的区间。
///
/// 做成「基准系数」而不是改每个 fontSize，是为了让已经存过
/// `fontScale = 1.0` 的老用户升级后立刻变舒服，不必手动再调一次。
const double kFontBaseline = 1.10;

/// 合成本次渲染实际使用的文字缩放（纯函数，便于单测）。
///
/// - `pref`：用户在设置里选的档位（0.85–1.4）
/// - `system`：系统字体缩放（Android 设置里的「字体大小」）
///
/// 系统缩放只吸收 0.85–1.25 这一段：超过 1.25 再叠乘会到 1.7 以上，
/// 卡片里的两行标题会被挤出容器，反而更难读。
double effectiveTextScale(double pref, double system) {
  final sys = system.isFinite && system > 0 ? system.clamp(0.85, 1.25) : 1.0;
  return (pref.clamp(0.85, 1.4) * kFontBaseline * sys).clamp(0.9, 1.75);
}

/// 把应用内的三档主题映射成 Flutter 的 ThemeMode（可单独测试）。
ThemeMode flutterThemeMode(AppThemeMode m) {
  switch (m) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
  }
}
