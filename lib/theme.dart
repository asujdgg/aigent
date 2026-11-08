import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'skin.dart';

/// v4 设计语言：Quiet Depth（静水深）。
///
/// 用「画布 / 纸面」两层材质建立深度：页面是微冷的浅灰，内容是纯白纸片，
/// 纸片靠 1px 极淡描边 + 大模糊低透明阴影浮起，而不是靠卡片色块或渐变。
/// 强调色严格限制在发送键、链接、选中态；不使用发光、彩色渐变、装饰图标。
class C {
  static Palette get _l => Skin.light;
  static Palette get _d => Skin.dark;

  /// 强调色：浅色 / 深色各取当前皮肤的一支。
  static Color get brand => _l.accent;
  static Color get brandSoft => _l.accent.withOpacity(0.10);
  static Color get brandDark => _d.accent;

  static Color get ink => _l.ink;
  static Color get ink2 => _l.ink2;
  static Color get ink3 => _l.ink3;

  /// 画布（页面底）与纸面（卡片 / 抽屉 / 弹层）。
  static Color get paper => _l.bg;
  static Color get surface => _l.surface;

  /// 内嵌次级表面：输入框、代码块、折叠块。
  static Color get sink => _l.sink;
  static Color get line => _l.line;
  static Color get hair => _l.hair;
  static Color get border => _l.border;

  /// 控件描边：比 [border] 深一档，专门给按钮 / 可点标签 / 下拉框用。
  static Color get borderStrong => _l.borderStrong;
  static Color get dBorderStrong => _d.borderStrong;
  static Color get bg => _l.bg;
  static Color get card => _l.surface;

  // 深色一侧沿用同一套语义名，避免每个调用点都写 dark ? a : b。
  static Color get dInk => _d.ink;
  static Color get dInk2 => _d.ink2;
  static Color get dInk3 => _d.ink3;
  static Color get dPaper => _d.bg;
  static Color get dSurface => _d.surface;
  static Color get dLine => _d.line;
  static Color get dHair => _d.hair;
  static Color get dBorder => _d.border;
  static Color get dBg => _d.bg;
  static Color get dCard => _d.surface;
  static Color get dSink => _d.sink;

  static Color get ok => _l.ok;
  static Color get warn => _l.warn;
  static Color get danger => _l.danger;

  /// 用户气泡：跟随强调色，保证整屏只有一支可点色。
  static Color get bubble => _l.bubble;
  static Color get dBubble => _d.bubble;
}

class D {
  static const double u = 8;

  /// 通用圆角：按钮、缩略图、输入框。随「圆角强度」缩放。
  static double get r => 11 * Skin.radius;

  /// 纸片圆角。
  static double get cardR => 16 * Skin.radius;

  /// 输入台圆角。
  static double get floatR => 20.0 * Skin.radius;
  static const Duration animFast = Duration(milliseconds: 140);
  static const Duration anim = Duration(milliseconds: 220);
  static const Duration animSlow = Duration(milliseconds: 300);
  static const Cubic curve = Curves.easeOutCubic;
  static const Cubic curveInOut = Curves.easeInOutCubic;
  static const double pagePad = 16;
  static const double flushInterval = 40;
}

/// 全应用统一页面转场。
///
/// 只有一条实现：新页整幅从右侧推入，旧页**完全静止**。手势返回时，
/// 手指的实时进度直接驱动这条位移，做到 1:1 跟手。
///
/// 为什么不直接用 Flutter 自带的 `PredictiveBackPageTransitionsBuilder`：
/// 它在转场里给整页套了一层 `Opacity`（Android 14 原生效果需要"变暗"），
/// 而全屏 `Opacity` 会强制 `saveLayer` —— 每一帧都要把整页离屏渲染一遍
/// 再合成。低端机上这就是几百毫秒的卡顿，正是「点进去返回卡一下」的
/// 直接来源。这里改用纯位移：只有一层 transform，光栅缓存可以整帧复用。
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _SoftPageTransition(route: route, animation: animation, child: child);
}

/// 统一转场时长的路由。
///
/// `MaterialPageRoute` 默认 300ms。整页切换走 300ms 会显得"拖"：用户
/// 点一下，页面慢悠悠推半秒，手指早已移到别处。240ms 是 iOS 与
/// Material 动效规范的主流区间，返回再快一点（200ms），因为返回是
/// 用户已经确定要走，不该让他等。
///
/// 基类用 `PageRouteBuilder` 而不是 `MaterialPageRoute`：后者在构造函数
/// 里 `assert(opaque)`，而二级页面需要 `opaque = false`（见 [keepBelow]）。
class SoftPageRoute<T> extends PageRouteBuilder<T> {
  SoftPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
    this.keepBelow = false,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: !keepBelow,
        );

  /// 是否让被压在下面的那一页**始终保持布局与光栅缓存**。
  ///
  /// 默认 false。路由不透明时，`Overlay` 会把下层整个从渲染树上摘下来
  /// （`_Theater.skipCount`），不布局也不绘制——这是省 GPU 的正常做法。
  ///
  /// 但二级页面必须置 true，否则会出现「点进去再返回，先卡几百毫秒」：
  /// 返回动画开始的**第一帧**，下层要从 offstage 恢复，重新布局整页
  /// （十几个卡片、几十行中文）再光栅化一次。这一帧的耗时就是那段卡顿，
  /// 而且它正好落在动画起点，看起来像「点了一下没反应」。
  ///
  /// 置 true 后下层一直是 onstage：静止时它的光栅缓存命中，等于零成本；
  /// 只有滚动时多合成一层，实测不到 1ms。
  final bool keepBelow;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      const SoftPageTransitionsBuilder()
          .buildTransitions(this, context, animation, secondaryAnimation, child);
}

/// 页面转场本体：位移 + 手势进度接管。
///
/// 结构在整个生命周期里**从不改变**（永远是同一个 `SlideTransition`），
/// 只切换驱动它的动画对象。这一点很关键：如果手势开始时换一套 widget
/// 结构，手指松开的瞬间（手势结束、动画继续）画面会跳一下。
class _SoftPageTransition extends StatefulWidget {
  const _SoftPageTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_SoftPageTransition> createState() => _SoftPageTransitionState();
}

class _SoftPageTransitionState extends State<_SoftPageTransition>
    with WidgetsBindingObserver {
  /// 本次转场是否由手指驱动过。
  ///
  /// 一旦为 true 就保持到路由销毁：手势拖动时必须是线性的（手指走多少、
  /// 页面走多少），松手后如果立刻切回缓动曲线，页面会从当前位置突然
  /// 跳到曲线上的对应位置。保持线性则全程连续。
  bool _dragged = false;

  /// 当前是否还欠着一次 `Navigator.didStopUserGesture()`。
  ///
  /// 手势进行中导航器会进入 `userGestureInProgress`，这个状态下所有页面
  /// 都不接收点击。必须保证「开一次、关一次」，否则整个 App 会点不动。
  bool _gestureLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 手势没走完就被销毁（极罕见）：把锁还回去，别把整个导航器留在
    // 「不接受点击」的状态里。
    if (_gestureLocked) {
      widget.route.navigator?.didStopUserGesture();
      _gestureLocked = false;
    }
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    // 只有最上层、且允许返回的路由接管手势；下层直接放行。
    if (backEvent.isButtonEvent ||
        !route.isCurrent ||
        !route.popGestureEnabled) {
      return false;
    }
    if (!_dragged) {
      setState(() => _dragged = true);
    }
    route.handleStartBackGesture(progress: 1 - backEvent.progress);
    // 记住「全局指针锁」已经打开，等这次手势收尾时负责关掉。
    _gestureLocked = true;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    _gestureLocked = false;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    final route = widget.route;
    final nav = route.navigator;
    if (nav == null || !_gestureLocked) return;

    // 这里是「点一次没反应、要点第二次」的真凶。
    //
    // 框架默认的 `route.handleCommitBackGesture()` 会按手指位置把退场动画
    // 拉长到最多 800ms，并且把 `userGestureInProgress` 一直保持到动画结束：
    //
    //   didStopUserGesture() 是在动画的 status 变成 dismissed 时才调用的。
    //
    // 而 `_ModalScope` 拿这个标志当「本次事件一律不派发」的开关——
    // 只要它为 true，**每一个**页面都会被 `IgnorePointer(ignoring: true)`
    // 包住。配合 `Curves.fastLinearToSlowEaseIn` 那种极平的收尾曲线，
    // 页面在最后三四百毫秒里看起来已经完全静止，实际上所有点击都被吞掉，
    // 于是用户只能再点一次。
    //
    // 改成：手势一结束立刻解锁，退场走我们自己的 200ms 反向转场
    // （`Navigator.pop` 会用 `reverseTransitionDuration`，并且从控制器
    // 当前值继续，不会跳）。
    nav.didStopUserGesture();
    _gestureLocked = false;
    if (route.isCurrent) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final animation = _dragged
        ? widget.animation
        : CurvedAnimation(
            parent: widget.animation,
            // 进场快起慢收，松手瞬间就有反馈；退场反向。
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
    // 从右往左书写的语言里，页面应该从左边进来。
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // 手指拖动时必须是 1:1（手指走多少、页面走多少），所以位移取整屏；
    // 点按钮触发的转场用 35%，覆盖更快、两页同屏的时间更短。
    //
    // 两者在 _dragged 切换的瞬间不会跳：手势开始时页面正处于原位
    // （animation.value == 1），无论距离取多少，offset 都是 0。
    final distance = _dragged ? 1.0 : 0.35;
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: Offset(rtl ? -distance : distance, 0),
          end: Offset.zero,
        ),
      ),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

// ---------------------------------------------------------------- 材质取色

Color lineOf(bool dark) => dark ? C.dLine : C.line;
Color hairOf(bool dark) => dark ? C.dHair : C.hair;
Color sinkOf(bool dark) => dark ? C.dSink : C.sink;
Color accentOf(bool dark) => dark ? C.brandDark : C.brand;
Color canvasOf(bool dark) => dark ? C.dPaper : C.paper;
Color surfaceOf(bool dark) => dark ? C.dSurface : C.surface;
Color fieldOf(bool dark) => dark ? C.dSink : C.sink;
Color borderOf(bool dark) => dark ? C.dBorder : C.border;
Color borderStrongOf(bool dark) => dark ? C.dBorderStrong : C.borderStrong;

/// 双层柔和阴影：一层负责「浮起」，一层负责「贴边」。
/// 透明度刻意压得很低——阴影一旦可被察觉，就会变成廉价的「贴纸感」。
List<BoxShadow> softShadow(bool dark, {double scale = 1}) => [
      BoxShadow(
        color: dark ? const Color(0x3D000000) : const Color(0x0D1B2C4D),
        blurRadius: 20 * scale,
        offset: Offset(0, 6 * scale),
      ),
      BoxShadow(
        color: dark ? const Color(0x24000000) : const Color(0x081B2C33),
        blurRadius: 4 * scale,
        offset: Offset(0, 1 * scale),
      ),
    ];

/// 白纸片：细描边 + 柔和阴影。所有内容卡片的统一入口。
BoxDecoration surfaceBox(
  bool dark, {
  double? radius,
  bool shadow = true,
  bool border = true,
  Color? fill,
  double shadowScale = 1,
}) {
  return BoxDecoration(
    color: fill ?? surfaceOf(dark),
    borderRadius: BorderRadius.circular(radius ?? D.cardR),
    border: border ? Border.all(color: borderOf(dark), width: 1) : null,
    boxShadow: shadow ? softShadow(dark, scale: shadowScale) : null,
  );
}

/// 内嵌块：无阴影，只有圆角与底色，用于思考摘要、引用区、代码块。
BoxDecoration insetBox(bool dark, {double? radius, Color? fill}) {
  return BoxDecoration(
    color: fill ?? fieldOf(dark),
    borderRadius: BorderRadius.circular(radius ?? D.r),
    border: Border.all(color: borderOf(dark), width: 1),
  );
}

/// 浮起的输入台 / 弹层顶面。
BoxDecoration raisedBox(bool dark, {double? radius}) =>
    surfaceBox(dark, radius: radius ?? D.floatR, shadowScale: 1.35);

/// 圆角输入框：浅灰填充 + 极淡描边，聚焦时描边转墨蓝。
InputDecoration fieldDecoration(
  bool dark, {
  String? hint,
  Widget? suffix,
  Widget? prefix,
  EdgeInsets? padding,
}) {
  OutlineInputBorder outline(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.r),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    filled: true,
    fillColor: fieldOf(dark),
    hintText: hint,
    hintStyle:
        TextStyle(color: dark ? C.dInk3 : C.ink3, fontSize: 12.5, height: 1.4),
    isDense: true,
    contentPadding:
        padding ?? const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    border: outline(borderOf(dark), 1),
    enabledBorder: outline(borderOf(dark), 1),
    focusedBorder: outline(accentOf(dark), 1.4),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(maxHeight: 34, maxWidth: 60),
    prefixIcon: prefix,
    prefixIconConstraints: prefix == null
        ? null
        : const BoxConstraints(maxHeight: 34, maxWidth: 44),
  );
}

/// 兼容旧调用点：返回圆角纸片，不再产生只有一条细线的「假卡片」。
BoxDecoration hairlineBox(bool dark, {bool top = false}) =>
    surfaceBox(dark, radius: D.r, shadow: false);

/// 兼容旧调用点：统一为纸片装饰。
BoxDecoration panelBox(bool dark, {Color? fill, bool border = true}) =>
    surfaceBox(dark, radius: D.r, shadow: false, border: border, fill: fill);

// ---------------------------------------------------------------- 排版

TextStyle ts(bool dark,
    {double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double spacing = 0}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? (dark ? C.dInk : C.ink),
    height: height ?? 1.6,
    letterSpacing: spacing,
  );
}

TextStyle sub(bool dark, {double size = 13}) =>
    ts(dark, size: size, color: dark ? C.dInk2 : C.ink2);

/// 元信息：小字号 + 低对比，用于时间、模型、计数。
/// 中文不加字距——加了会显得松散做作，这也是「模板感」的来源之一。
TextStyle meta(bool dark, {double size = 12, Color? color, double? height}) =>
    ts(
      dark,
      size: size,
      color: color ?? (dark ? C.dInk2 : C.ink2),
      height: height,
    );

/// 数字专用：等宽数字（tabular figures），让耗时、token 数不会左右跳动。
TextStyle numStyle(
  bool dark, {
  double size = 10.5,
  Color? color,
  FontWeight weight = FontWeight.w400,
}) =>
    ts(dark,
            size: size,
            color: color ?? (dark ? C.dInk3 : C.ink3),
            weight: weight)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// 分区标题：小标题，实色、不加宽字距。
///
/// 旧版是 10.5px + 1.5 字距 + 最浅灰，中文在手机上会被拉成一条虚线似的淡影子，
/// 标题读不出来、页面也显得灰。中文不需要靠字距「撑」出高级感，
/// 靠字号与字重区分层级就够了。
TextStyle sectionTitle(bool dark) => TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: 0.2,
      color: dark ? C.dInk2 : C.ink2,
    );

/// 大标题：负字距、重字重，形成编辑式版面。
TextStyle display(bool dark, {double size = 28}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      height: 1.28,
      color: dark ? C.dInk : C.ink,
    );

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: C.brand,
    brightness: brightness,
  ).copyWith(
    primary: dark ? C.brandDark : C.brand,
    onPrimary: Colors.white,
    surface: surfaceOf(dark),
    outline: borderOf(dark),
  );
  final base = dark ? C.dInk : C.ink;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: canvasOf(dark),
    canvasColor: canvasOf(dark),
    dividerColor: hairOf(dark),
    appBarTheme: AppBarTheme(
      backgroundColor: canvasOf(dark),
      foregroundColor: base,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(
        bottom: BorderSide(color: borderOf(dark), width: 1),
      ),
      titleTextStyle: TextStyle(
        color: base,
        fontSize: 16.5,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: dark ? C.dInk2 : C.ink2, size: 20),
    ),
    iconTheme: IconThemeData(color: dark ? C.dInk2 : C.ink2, size: 20),
    textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
          bodyColor: base,
          displayColor: base,
        ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldOf(dark),
      hintStyle: TextStyle(
          color: dark ? C.dInk3 : C.ink3, fontSize: 12.5, height: 1.4),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.r),
        borderSide: BorderSide(color: borderOf(dark)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.r),
        borderSide: BorderSide(color: borderOf(dark)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.r),
        borderSide: BorderSide(color: accentOf(dark), width: 1.4),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairOf(dark), thickness: 1, space: 1),
    splashFactory: InkRipple.splashFactory,
    splashColor: (dark ? C.dInk2 : C.ink2).withOpacity(0.08),
    highlightColor: Colors.transparent,
    cardTheme: CardTheme(
      color: surfaceOf(dark),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(D.cardR),
        side: BorderSide(color: borderOf(dark)),
      ),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: surfaceOf(dark),
      surfaceTintColor: Colors.transparent,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.cardR)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceOf(dark),
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: surfaceOf(dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.floatR)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: SoftPageTransitionsBuilder(),
        TargetPlatform.iOS: SoftPageTransitionsBuilder(),
        TargetPlatform.linux: SoftPageTransitionsBuilder(),
        TargetPlatform.macOS: SoftPageTransitionsBuilder(),
        TargetPlatform.windows: SoftPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? C.dSink : C.ink,
      contentTextStyle:
          TextStyle(fontSize: 12.5, color: dark ? C.dInk : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
    ),
  );
}
