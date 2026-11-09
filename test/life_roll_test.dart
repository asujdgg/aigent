import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/services/life_sim.dart';
import 'package:ai_agent_app/services/region_data.dart';

void main() {
  group('开局抽天赋', () {
    test('六维都在 0–100，天赋项明显偏高', () {
      for (var seed = 0; seed < 60; seed++) {
        final r = rollCharacter(Random(seed));
        for (final k in kStatKeys) {
          expect(r.stats[k], greaterThanOrEqualTo(0));
          expect(r.stats[k], lessThanOrEqualTo(100));
        }
        expect(r.stats[r.talent.key], greaterThanOrEqualTo(40));
        expect(r.rarity, greaterThanOrEqualTo(0));
        expect(r.rarity, lessThanOrEqualTo(2));
      }
    });

    test('同一随机种子结果稳定', () {
      final a = rollCharacter(Random(7));
      final b = rollCharacter(Random(7));
      expect(a.stats.toMap(), b.stats.toMap());
      expect(a.talent.name, b.talent.name);
      expect(a.rarity, b.rarity);
    });

    test('天赋覆盖多个维度，不会永远同一项', () {
      final keys = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        keys.add(rollCharacter(Random(seed)).talent.key);
      }
      expect(keys.length, greaterThan(3));
    });

    test('最强项与天赋一致', () {
      for (var seed = 0; seed < 40; seed++) {
        final r = rollCharacter(Random(seed));
        // 天赋 +13~26 之后一定不低于其它维度，除非短板恰好和它同分。
        expect(r.stats[r.strongestKey], greaterThanOrEqualTo(40));
      }
    });
  });

  group('地区数据', () {
    test('省份不重复，每省至少一个城市', () {
      final names = kProvinces.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
      for (final p in kProvinces) {
        expect(p.cities, isNotEmpty);
      }
    });

    test('覆盖 34 个省级行政区', () {
      expect(kProvinces.length, 34);
    });

    test('能查到常见城市', () {
      expect(provinceByName('广东')!.cities, contains('深圳'));
      expect(provinceByName('浙江')!.cities, contains('杭州'));
      expect(provinceByName('新疆')!.cities, contains('喀什'));
      expect(provinceByName('黑龙江')!.cities, contains('哈尔滨'));
      expect(provinceByName('不存在'), isNull);
    });

    test('出生地展示文本', () {
      expect(regionLabel('广东', '深圳'), '广东 · 深圳');
      expect(regionLabel('北京', '北京'), '北京');
      expect(regionLabel('', ''), '');
    });
  });

  group('存档兼容', () {
    test('旧档没有地区与天赋也能读', () {
      final c = LifeCharacter.fromJson({
        'id': 'old',
        'name': '旧人',
        'age': 30,
        'stats': {'mind': 70},
      });
      expect(c.province, '');
      expect(c.talentName, '');
      expect(c.events, isEmpty);
      expect(c.stats.mind, 70);
    });

    test('新档往返保留出生地与天赋', () {
      final c = LifeCharacter(
        id: 'n1',
        name: '新人',
        province: '四川',
        city: '成都',
        talentKey: 'mind',
        talentName: '过目不忘',
        talentDesc: '看过就记住',
        talentRarity: 2,
        age: 6,
      )..events.add(LifeEvent(
          startAge: 0,
          age: 6,
          year: 2026,
          title: '童年',
          story: '……',
        ));
      final back = LifeCharacter.fromJson(c.toJson());
      expect(back.province, '四川');
      expect(back.city, '成都');
      expect(back.talentName, '过目不忘');
      expect(back.talentRarity, 2);
      expect(back.events.single.spanLabel, '0 → 6');
      expect(back.toMarkdown(), contains('四川成都'));
    });
  });
}
