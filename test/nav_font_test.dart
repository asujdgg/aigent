import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ai_agent_app/main.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/theme.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';

/// v4.17 回归：
/// 1) 设置子页的系统返回（侧边手势 / 返回键）必须逐层退出，
///    不能一滑就把整个设置页 pop 掉；
/// 2) 默认字号要在人眼舒适的区间（ChatGPT / Gemini 量级），
///    而不是老版的 15.5 偏小正文。
void main() {
  group('字号基准', () {
    test('默认档位放大到 1.10，正文落在 17 左右', () {
      // 1.0 档 × 1.10 基准 = 1.10 → 正文 15.5 * 1.1 ≈ 17.05
      expect(effectiveTextScale(1.0, 1.0), closeTo(1.10, 0.001));
      expect(15.5 * effectiveTextScale(1.0, 1.0), greaterThanOrEqualTo(16.5));
    });

    test('四档都保持单调而且不会失真', () {
      final scales = [0.9, 1.0, 1.12, 1.25]
          .map((v) => effectiveTextScale(v, 1.0))
          .toList();
      for (var i = 1; i < scales.length; i++) {
        expect(scales[i], greaterThan(scales[i - 1]));
      }
      // 最小档也不能小到回到「看不清」的老问题
      expect(scales.first, greaterThanOrEqualTo(0.9));
      expect(scales.last, lessThanOrEqualTo(1.6));
    });

    test('吸收系统字体缩放，但 1.25 以上不再叠乘', () {
      final normal = effectiveTextScale(1.0, 1.0);
      final big = effectiveTextScale(1.0, 1.25);
      expect(big, greaterThan(normal));
      // 系统 1.6 被夹到 1.25，否则卡片标题会被挤出容器
      expect(effectiveTextScale(1.0, 1.6), closeTo(big, 0.001));
      // 系统字体缩小同样被尊重
      expect(effectiveTextScale(1.0, 0.85), lessThan(normal));
    });

    test('非法输入不崩，回落到 1.0', () {
      expect(effectiveTextScale(1.0, 0), closeTo(1.10, 0.001));
      expect(effectiveTextScale(1.0, double.nan), closeTo(1.10, 0.001));
      expect(effectiveTextScale(1.0, double.infinity), closeTo(1.10, 0.001));
    });
  });

  group('页面转场', () {
    test('路由时长统一：240ms 进入 / 200ms 退出', () {
      final route = SoftPageRoute<void>(builder: (_) => const SizedBox());
      expect(route.transitionDuration, const Duration(milliseconds: 240));
      expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
      // v4.25：全站默认保留下层 onstage。以前只有设置子页这么做，
      // 点按钮返回时下层要从 offstage 恢复、首帧重建整页，正是卡顿来源。
      expect(route.keepBelow, isTrue);
      expect(route.opaque, isFalse);
    });

    test('显式关掉 keepBelow 才恢复不透明', () {
      final route = SoftPageRoute<void>(
        keepBelow: false,
        builder: (_) => const SizedBox(),
      );
      expect(route.keepBelow, isFalse);
      expect(route.opaque, isTrue);
    });

    // v4.26 回归：点顶栏返回按钮一直「卡一下」的真凶，是进出共用同一条
    // 0.35 屏的 tween——退出的页面只滑出三分之一就被摘掉，看起来像
    // 卡了几百毫秒然后突然消失。侧滑走的是整屏跟手，所以只有按钮卡。
    testWidgets('按钮进出都走整屏位移，不会滑到一半就消失', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(c).push(
                  SoftPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('DETAIL_MARK')),
                    ),
                  ),
                ),
                child: const Text('OPEN_MARK'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN_MARK'));
      await tester.pump();
      // 进入半程（120 / 240ms）：整屏 tween 应已移动约半屏。
      await tester.pump(const Duration(milliseconds: 120));
      final enterDx = tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .map((s) => s.position.value.dx)
          .reduce((a, b) => a > b ? a : b);
      expect(enterDx, greaterThan(0.3), reason: '进入应走整屏位移');
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('DETAIL_MARK'))).pop();
      await tester.pump();
      // 退出半程（100 / 200ms）：同样要离开原位足够远。
      await tester.pump(const Duration(milliseconds: 100));
      final exitDx = tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .map((s) => s.position.value.dx)
          .reduce((a, b) => a > b ? a : b);
      expect(exitDx, greaterThan(0.3), reason: '退出应走完整屏位移，而不是 0.35 屏');
      await tester.pumpAndSettle();
      expect(find.text('OPEN_MARK'), findsOneWidget);
    });

  });

  group('设置页逐层返回', () {
    testWidgets('侧滑先回设置主目录，再退出设置', (tester) async {
      final st = AppState()..settings = (AppSettings()..ensurePresets());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(c).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: const Text('HOME_MARK'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('HOME_MARK'));
      await tester.pumpAndSettle();
      expect(find.text('偏好设置'), findsOneWidget);

      // 进「语言与地区」
      await tester.tap(find.text('语言与地区').first);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsWidgets);

      // 第一次系统返回：只退一层，回到设置主目录
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsNothing,
          reason: '子页侧滑应当退回设置主目录，子页本身要离开渲染树');
      expect(find.text('HOME_MARK'), findsNothing,
          reason: '只退一层，设置页仍在栈上');

      // 第二次系统返回：退出设置，回到主界面
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('HOME_MARK'), findsOneWidget);
    });

    testWidgets('连续进两个子页后仍逐层退出', (tester) async {
      final st = AppState()..settings = (AppSettings()..ensurePresets());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(c).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: const Text('HOME_MARK'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('HOME_MARK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('外观主题').first);
      await tester.pumpAndSettle();
      expect(find.text('明暗模式'), findsWidgets);

      // 子页内返回 → 主目录
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('偏好设置'), findsOneWidget);

      // 再进另一个子页，返回同样只退一层
      await tester.tap(find.text('连接与模型').first);
      await tester.pumpAndSettle();
      expect(find.text('API BASE URL'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('偏好设置'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('HOME_MARK'), findsOneWidget);
    });
  });

  group('返回手势结束后不再吞点击', () {
    /// 走真实平台通道模拟一次预测性返回手势。
    Future<void> gesture(WidgetTester tester, String method,
        {double progress = 0}) async {
      final Object? args =
          method == 'commitBackGesture' || method == 'cancelBackGesture'
              ? null
              : <String, Object?>{
                  'touchOffset': <double>[0.0, 400.0],
                  'progress': progress,
                  'swipeEdge': 0,
                };
      final data =
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        data,
        (_) {},
      );
    }

    testWidgets('侧滑返回后立刻可以点下一项', (tester) async {
      final st = AppState()..settings = (AppSettings()..ensurePresets());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: Text('HOME_MARK'))),
          ),
        ),
      );
      final nav = tester.state<NavigatorState>(find.byType(Navigator));

      nav.push(SoftPageRoute<void>(
        keepBelow: true,
        builder: (_) => const SettingsScreen(),
      ));
      await tester.pumpAndSettle();

      nav.push(SoftPageRoute<void>(
        keepBelow: true,
        builder: (_) => const SettingsScreen(initialCat: 'language'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsWidgets);

      await gesture(tester, 'startBackGesture', progress: 0.1);
      await tester.pump();
      await gesture(tester, 'updateBackGestureProgress', progress: 0.55);
      await tester.pump();

      // 手指抬起：这一瞬间必须解除「用户手势进行中」的全局指针锁。
      // 修复前这个标志会一直保持到最长 800ms 的拖尾动画结束，
      // 页面看着已经停稳，点什么都没反应——用户只能再点一次。
      await gesture(tester, 'commitBackGesture');
      await tester.pump();
      expect(nav.userGestureInProgress, isFalse,
          reason: '手势一结束就该能点，而不是等退场动画的 800ms 拖尾');

      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsNothing, reason: '只退一层，回到设置目录');

      // 同一帧内立刻点下一项，必须一次就进。
      await tester.tap(find.text('外观主题').first);
      await tester.pumpAndSettle();
      expect(find.text('明暗模式'), findsWidgets,
          reason: '返回后第一次点击就要生效');
    });

    testWidgets('手势进行中仍然屏蔽点击（不能误触下层）', (tester) async {
      final st = AppState()..settings = (AppSettings()..ensurePresets());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: Text('HOME_MARK'))),
          ),
        ),
      );
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(SoftPageRoute<void>(
        keepBelow: true,
        builder: (_) => const SettingsScreen(),
      ));
      await tester.pumpAndSettle();

      await gesture(tester, 'startBackGesture', progress: 0.05);
      await tester.pump();
      expect(nav.userGestureInProgress, isTrue);

      await tester.tap(find.text('外观主题').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('明暗模式'), findsNothing, reason: '拖动过程中不应该点穿');

      await gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(nav.userGestureInProgress, isFalse, reason: '取消后锁必须还回去');
      expect(find.text('外观主题'), findsWidgets);
    });
  });
}
