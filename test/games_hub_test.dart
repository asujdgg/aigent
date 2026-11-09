import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_app/i18n.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/mini_games.dart';
import 'package:ai_agent_app/services/model_source.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/mini_game_screen.dart';
import 'package:ai_agent_app/ui/provider_model_picker.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';

AppState _state() {
  final st = AppState()..settings = AppSettings();
  final s = st.settings;
  s.load({});
  s.apiKey = 'sk-a';
  s.model = 'model-a';
  s.cachedModels = ['model-a', 'model-a2'];
  s.syncActive();
  s.profiles.add(ApiProfile(
    id: 'b',
    name: 'B 服务',
    baseUrl: 'https://b.example/v1',
    model: 'model-b',
    cachedModels: ['model-b', 'model-b2'],
  ));
  s.applyProfileKeys({s.activeProfileId: 'sk-a', 'b': 'sk-b'});
  return st;
}

Widget _wrap(AppState st, Widget home) =>
    ChangeNotifierProvider<AppState>.value(
      value: st,
      child: MaterialApp(home: home),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'zh';
  });

  group('设置里的游戏分类', () {
    test('分类存在且属于「游戏」分组', () {
      expect(kSettingsCats.any((c) => c.id == 'games'), isTrue);
      final games = kSettingsCats.firstWhere((c) => c.id == 'games');
      expect(games.title, '游戏');
      expect(settingsCatMatches(games, '轮盘'), isTrue);
      expect(settingsCatMatches(games, 'game'), isTrue);
    });

    testWidgets('设置首页能看到「游戏」入口', (tester) async {
      final st = _state();
      await tester.pumpWidget(_wrap(st, const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      // 「游戏」是最后一组，需要滚到底才被 ListView 构建出来。
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('游戏'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('游戏子页列出全部玩法入口', (tester) async {
      final st = _state();
      await tester.pumpWidget(
          _wrap(st, const SettingsScreen(initialCat: 'games')));
      await tester.pump(const Duration(milliseconds: 100));
      for (final name in [
        'AI 圆桌会议',
        '模拟人生',
        '二十问',
        '故事接龙',
        '抉择轮盘',
        '猜数字',
        '石头剪刀布',
        '每日一签',
        '魔法八球',
      ]) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('两级模型选择器', () {
    testWidgets('第一级列两家运营商，点进去才是模型列表', (tester) async {
      final st = _state();
      final groups = buildProviderGroups(st.settings,
          activeModels: st.models.map((e) => e.id).toList());
      await tester.pumpWidget(_wrap(
          st,
          ProviderPickerPage(
            dark: false,
            groups: groups,
            chatChoice: currentChatChoice(st.settings),
            title: '选择模型',
          )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('B 服务'), findsOneWidget);
      // 第一级不直接铺模型列表
      expect(find.text('model-b2'), findsNothing);

      await tester.tap(find.text('B 服务'));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('model-b2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('第二级选中模型带地址和密钥返回', (tester) async {
      final st = _state();
      final b = buildProviderGroups(st.settings).firstWhere((g) => g.id == 'b');
      ModelChoice? result;
      await tester.pumpWidget(_wrap(
          st,
          Builder(builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<ModelChoice>(
                      MaterialPageRoute(
                        builder: (_) => ProviderModelsPage(
                          dark: false,
                          group: b,
                        ),
                      ),
                    );
                  },
                  child: const Text('go'),
                ),
              ))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('model-b2'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.model, 'model-b2');
      expect(result!.baseUrl, 'https://b.example/v1');
      expect(result!.apiKey, 'sk-b');
      expect(result!.providerName, 'B 服务');
    });

    testWidgets('搜索框能过滤模型', (tester) async {
      final st = _state();
      final b = buildProviderGroups(st.settings).firstWhere((g) => g.id == 'b');
      await tester.pumpWidget(
          _wrap(st, ProviderModelsPage(dark: false, group: b)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('model-b'), findsOneWidget);
      expect(find.text('model-b2'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'b2');
      await tester.pump();
      expect(find.text('model-b2'), findsOneWidget);
      // 过滤后 model-b 不应出现在列表里（输入提示里也没有该字符串）
      expect(find.text('model-b', findRichText: true), findsNothing);
    });
  });

  group('小游戏页冒烟', () {
    for (final kind in MiniGameKind.values) {
      testWidgets('${kind.name} 能打开且不抛异常', (tester) async {
        final st = _state();
        await tester.pumpWidget(
            _wrap(st, MiniGameScreen(kind: kind)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('猜数字可交互：给出大小或猜中提示', (tester) async {
      final st = _state();
      await tester.pumpWidget(_wrap(
          st, const MiniGameScreen(kind: MiniGameKind.guess)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('猜！'));
      await tester.pump();
      // 目标随机，三种提示之一即可；关键是次数推进且不崩。
      final hasHint = find.textContaining('大了').evaluate().isNotEmpty ||
          find.textContaining('小了').evaluate().isNotEmpty ||
          find.textContaining('猜中了').evaluate().isNotEmpty;
      expect(hasHint, isTrue);
      expect(find.textContaining('已猜'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('轮盘少于两个选项时按钮禁用', (tester) async {
      final st = _state();
      await tester.pumpWidget(_wrap(
          st, const MiniGameScreen(kind: MiniGameKind.wheel)));
      await tester.pump(const Duration(milliseconds: 100));
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '转起来'));
      expect(btn.onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'A, B');
      await tester.pump();
      final btn2 = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '转起来'));
      expect(btn2.onPressed, isNotNull);
    });
  });
}
