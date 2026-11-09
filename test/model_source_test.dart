import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/feature_store.dart';
import 'package:ai_agent_app/services/model_source.dart';
import 'package:ai_agent_app/services/roundtable.dart';

AppSettings _settings() {
  final s = AppSettings();
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
  return s;
}

void main() {
  group('两级模型选择：按运营商分组', () {
    test('每个连接只列自己的模型，不串台', () {
      final s = _settings();
      final groups = buildProviderGroups(s, activeModels: ['model-a3']);
      expect(groups.length, 2);

      final a = groups.firstWhere((g) => g.active);
      expect(a.name, isNotEmpty);
      expect(a.models, containsAll(['model-a', 'model-a2', 'model-a3']));
      expect(a.models, isNot(contains('model-b')));
      expect(a.models, isNot(contains('model-b2')));

      final b = groups.firstWhere((g) => !g.active);
      expect(b.name, 'B 服务');
      expect(b.baseUrl, 'https://b.example/v1');
      expect(b.apiKey, 'sk-b');
      // 非活动连接不叠加活动连接刚刚刷新的模型
      expect(b.models, isNot(contains('model-a3')));
      expect(b.models, contains('model-b2'));
    });

    test('模型去重且当前模型排第一', () {
      final s = _settings();
      final groups = buildProviderGroups(s, activeModels: ['model-a']);
      final a = groups.firstWhere((g) => g.active);
      expect(a.models.first, 'model-a');
      expect(a.models.toSet().length, a.models.length);
    });

    test('空模型不进列表', () {
      final s = _settings();
      s.profiles.add(ApiProfile(
        id: 'c',
        name: 'C',
        baseUrl: 'https://c/v1',
        model: '',
        cachedModels: ['  ', '', 'model-c'],
      ));
      final c = buildProviderGroups(s).firstWhere((g) => g.id == 'c');
      expect(c.models, ['model-c']);
    });

    test('过滤大小写不敏感，空查询返回全部', () {
      const models = ['GPT-4o', 'gpt-4o-mini', 'deepseek-chat'];
      expect(filterModels(models, ''), models);
      expect(filterModels(models, 'GPT'), hasLength(2));
      expect(filterModels(models, 'deep'), ['deepseek-chat']);
      expect(filterModels(models, 'zzz'), isEmpty);
    });
  });

  group('游戏模型偏好恢复', () {
    test('没记住时退回当前对话模型', () {
      final s = _settings();
      final c = resolveModelChoice(s);
      expect(c.baseUrl, s.baseUrl);
      expect(c.apiKey, 'sk-a');
      expect(c.model, 'model-a');
      expect(c.providerName, s.activeProfile.name);
    });

    test('记住 B 连接时按地址补回 B 的密钥', () {
      final s = _settings();
      final c = resolveModelChoice(
        s,
        baseUrl: 'https://b.example/v1',
        model: 'model-b2',
        providerName: 'B 服务',
      );
      expect(c.apiKey, 'sk-b');
      expect(c.model, 'model-b2');
      expect(c.providerName, 'B 服务');
    });

    test('地址或模型为空时安全退回默认', () {
      final s = _settings();
      expect(resolveModelChoice(s, baseUrl: '', model: 'x').model, 'model-a');
      expect(
          resolveModelChoice(s, baseUrl: 'https://b.example/v1', model: '')
              .model,
          'model-a');
    });

    test('未知地址也能按 host 生成可读名字', () {
      final s = _settings();
      final c = resolveModelChoice(
        s,
        baseUrl: 'https://unknown.example/v1',
        model: 'whatever',
      );
      expect(c.providerName, 'unknown.example');
      expect(c.apiKey, isEmpty);
    });

    test('偏好序列化不含密钥字段', () {
      final p = GameModelPref.fromJson(const GameModelPref(
        baseUrl: 'https://b/v1',
        model: 'm',
        providerName: 'B',
      ).toJson());
      expect(p.baseUrl, 'https://b/v1');
      expect(p.model, 'm');
      expect(p.toJson().toString(), isNot(contains('sk-')));
    });

    test('存档往返不落密钥', () async {
      final mem = <String, String>{};
      final store = FeatureStore(memory: mem);
      await store.saveGameModel(const GameModelPref(
        baseUrl: 'https://b/v1',
        model: 'model-b',
        providerName: 'B',
      ));
      final loaded = await store.loadGameModel();
      expect(loaded!.model, 'model-b');
      expect(mem.values.join(), isNot(contains('sk-')));
    });
  });

  group('席位带运营商名', () {
    test('providerName 随存档往返，旧存档兼容', () {
      final seat = Seat(
        id: 's',
        name: '甲',
        baseUrl: 'https://b/v1',
        apiKey: 'sk-secret',
        model: 'model-b',
        providerName: 'B 服务',
      );
      final json = seat.toJson();
      expect(json.toString(), isNot(contains('sk-secret')));
      final restored = Seat.fromJson(json);
      expect(restored.providerName, 'B 服务');
      expect(restored.apiKey, isEmpty);

      final old = Seat.fromJson({
        'id': 's2',
        'model': 'm',
        'baseUrl': 'https://b/v1',
      });
      expect(old.providerName, isEmpty);

      expect(seat.copy().providerName, 'B 服务');
    });

    test('按地址补运营商名', () {
      final s = _settings();
      expect(providerNameFor(s, 'https://b.example/v1'), 'B 服务');
      expect(providerNameFor(s, 'https://x.example/v1'), 'x.example');
    });
  });
}
