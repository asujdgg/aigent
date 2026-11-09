import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_app/i18n.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/feature_store.dart';
import 'package:ai_agent_app/services/life_sim.dart';
import 'package:ai_agent_app/services/roundtable.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/life_screen.dart';
import 'package:ai_agent_app/ui/roundtable_screen.dart';

void main() {
  group('新功能本地存档', () {
    test('会议与人生存档可往返，且不含明文密钥', () async {
      final mem = <String, String>{};
      final store = FeatureStore(memory: mem);
      final m = Meeting(
        id: 'm1',
        topic: '议题',
        seats: [
          Seat(
              id: 's',
              name: '甲',
              baseUrl: 'https://x/v1',
              apiKey: 'sk-super-secret',
              model: 'model-a')
        ],
      );
      m.turns.add(MeetingTurn(
          seatId: 's', seatName: '甲', model: 'model-a', round: 1, content: '观点'));
      var all = await store.upsertMeeting(m);
      expect(all.length, 1);
      expect(mem.values.join(), isNot(contains('sk-super-secret')));
      final loaded = (await store.loadMeetings()).single;
      expect(loaded.topic, '议题');
      expect(loaded.turns.single.content, '观点');
      expect(loaded.seats.single.apiKey, isEmpty); // 密钥不落盘

      final c = LifeCharacter(id: 'l1', name: '林知远');
      c.events.add(parseEventJson('{"title":"一件事","story":"叙述"}', 16, 2026));
      final lives = await store.upsertLife(c);
      expect(lives.length, 1);
      expect((await store.loadLives()).single.events.single.title, '一件事');

      await store.deleteMeeting('m1');
      await store.deleteLife('l1');
      expect(await store.loadMeetings(), isEmpty);
      expect(await store.loadLives(), isEmpty);
    });

    test('同 id 覆盖、按最近插入排前', () async {
      final store = FeatureStore(memory: <String, String>{});
      await store.upsertMeeting(Meeting(id: 'a', topic: '旧'));
      await store.upsertMeeting(Meeting(id: 'b', topic: '新'));
      await store.upsertMeeting(Meeting(id: 'a', topic: '改过'));
      final all = await store.loadMeetings();
      expect(all.length, 2);
      expect(all.first.topic, '改过');
    });
  });

  group('多语言词条', () {
    tearDown(() => L10n.useTable('zh', const {}));

    test('英文界面里新功能文案不含中文', () {
      L10n.lang = 'en';
      for (final k in ['AI 圆桌会议', '模拟人生', '开始会议', '会议结论', '开始这一生']) {
        expect(t(k), isNot(contains(RegExp(r'[\u4e00-\u9fa5]'))), reason: k);
      }
      expect(t('AI 圆桌会议'), 'AI Roundtable');
      expect(t('模拟人生'), 'Life Simulator');
    });

    test('38 份词表都覆盖新功能词条', () {
      const keys = ['AI 圆桌会议', '模拟人生', '开始会议', '会议结论', '开始这一生'];
      final files = Directory('assets/i18n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tsv'))
          .toList();
      expect(files.length, 38);
      for (final f in files) {
        final table = L10n.parseTsv(f.readAsStringSync());
        for (final k in keys) {
          expect(table.containsKey(k), isTrue,
              reason: '${f.path} 缺少 $k');
          expect(table[k], isNot(equals(k)));
        }
        // 每份词表都必须是干净的一行一条
        for (final line in f.readAsStringSync().split('\n')) {
          if (line.trim().isNotEmpty) {
            expect(line.contains('\t'), isTrue, reason: '${f.path} 有坏行');
          }
        }
      }
    });
  });

  group('页面冒烟', () {
    testWidgets('圆桌会议页能打开并展示议题与席位', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(home: RoundtableScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('AI 圆桌会议'), findsOneWidget);
      expect(find.text('会议议题'), findsOneWidget);
      expect(find.text('开始会议'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('模拟人生页能打开并展示创建表单', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(home: LifeScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('模拟人生'), findsOneWidget);
      expect(find.text('创建角色'), findsOneWidget);
      expect(find.text('开始这一生'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('模拟人生可以两级下钻选出生地，并抽一次天赋', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(home: LifeScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 出生地：先选省，点进去再选市，逐层返回。
      await tester.tap(find.text('选择出生地'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('河北'));
      await tester.pumpAndSettle();
      expect(find.text('河北 · 选择城市'), findsOneWidget);
      expect(find.text('石家庄'), findsOneWidget);
      await tester.tap(find.text('石家庄'));
      await tester.pumpAndSettle();
      expect(find.text('河北 · 石家庄'), findsOneWidget);

      // 天赋抽签：抽完换成结果卡，按钮不再出现（一局只有一次）。
      expect(find.text('抽取天赋'), findsOneWidget);
      await tester.ensureVisible(find.text('抽取天赋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('抽取天赋'));
      await tester.pumpAndSettle();
      expect(find.text('抽取天赋'), findsNothing);
      expect(find.text('天赋抽签'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
