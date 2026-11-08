import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ai_agent_app/main.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/muse.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';
import 'package:ai_agent_app/ui/workspace_screen.dart';

/// 窄屏（360×740dp，多数安卓机的逻辑宽度）× 从「标准」到「特大」的字号，
/// 逐页渲染一遍。字号基准调大后最容易出问题的是固定行高的小卡片、
/// 一行文案 + 右侧数值的设置行——溢出会在这里直接抛出来。
void main() {
  final sizes = [effectiveTextScale(1.0, 1.0), effectiveTextScale(1.25, 1.0)];

  for (final scale in sizes) {
    final tag = '${(scale * 100).round()}%';

    testWidgets('窄屏 $tag：设置主目录与各子页不溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final st = AppState()..settings = (AppSettings()..ensurePresets());

      Future<void> show(Widget page, [String tag = 'hub']) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: st,
            child: MaterialApp(
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
              home: page,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        final e = tester.takeException();
        if (e != null) debugPrint('>>> OVERFLOW IN PAGE: $tag  ->  $e');
        expect(e, isNull);
      }

      await show(const SettingsScreen());

      for (final c in kSettingsCats) {
        // 免密模型 / 搜索源 / 研究 / 语音 有网络探测，冒烟不碰。
        if (const {'free', 'search', 'research', 'voice', 'agent'}
            .contains(c.id)) {
          continue;
        }
        await show(SettingsScreen(initialCat: c.id), c.id);
      }
    });

    testWidgets('窄屏 $tag：抽屉与空态不溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final st = AppState()..settings = (AppSettings()..ensurePresets());
      final key = GlobalKey<ScaffoldState>();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: st,
          child: MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              key: key,
              drawer: WorkspaceDrawer(onResearch: () {}, onToolbox: () {}),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      key.currentState!.openDrawer();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏 $tag：欢迎空态不溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MuseOnboarding(
              persona: nonePersona(),
              dark: true,
              modelLine: '尚未配置接口',
              onConfigure: () {},
              onPersona: () {},
              onVoice: () {},
              onTools: () {},
              onStarter: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    });
  }
}
