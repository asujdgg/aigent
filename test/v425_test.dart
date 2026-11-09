import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/agent_tools.dart';
import 'package:ai_agent_app/services/cache_store.dart';
import 'package:ai_agent_app/services/device_bridge.dart';
import 'package:ai_agent_app/services/llm_client.dart';
import 'package:ai_agent_app/services/price_catalog.dart';
import 'package:ai_agent_app/theme.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';

LlmRequest _req(String model, {String text = '你好'}) => LlmRequest(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-test',
      model: model,
      messages: [
        {'role': 'user', 'content': text},
      ],
      maxTokens: 512,
      temperature: 0.7,
      topP: 0.9,
      thinkingBudget: 0,
      reasoningEffort: 'medium',
      deepThinking: false,
    );

void main() {
  group('全新安装不显示假模型', () {
    test('默认没有模型，地址只是占位模板', () {
      final s = AppSettings();
      expect(s.model, isEmpty);
      expect(s.apiKey, isEmpty);
      expect(s.baseUrl, 'https://api.openai.com/v1');
      expect(s.cachedModels, isEmpty);
    });

    test('用户选过模型后，编码往返不会丢', () {
      final s = AppSettings();
      s.model = 'deepseek-chat';
      final back = AppSettings();
      back.load(Map<String, dynamic>.from(jsonDecode(s.encode()) as Map));
      expect(back.model, 'deepseek-chat');
    });

    test('空模型不会伪造出一条可用连接', () {
      final s = AppSettings();
      final configured = s.apiKey.trim().isNotEmpty ||
          !s.baseUrl.startsWith('https://api.openai.com');
      expect(configured, isFalse);
    });
  });

  group('提示词缓存命中解析', () {
    test('OpenAI prompt_tokens_details.cached_tokens', () {
      final u = TokenUsage.fromApi({
        'prompt_tokens': 1000,
        'completion_tokens': 100,
        'prompt_tokens_details': {'cached_tokens': 640},
      })!;
      expect(u.prompt, 1000);
      expect(u.cached, 640);
      expect(u.hasCacheHit, isTrue);
    });

    test('Anthropic / 国产网关的其它写法', () {
      expect(
          TokenUsage.fromApi({
            'input_tokens': 300,
            'output_tokens': 20,
            'cache_read_input_tokens': 120,
          })!
              .cached,
          120);
      expect(
          TokenUsage.fromApi({
            'prompt_tokens': 300,
            'completion_tokens': 20,
            'prompt_cache_hit_tokens': 88,
          })!
              .cached,
          88);
      expect(TokenUsage.fromApi({'prompt_tokens': 10})!.cached, 0);
    });

    test('TokenStats 汇总缓存 token 并能序列化', () {
      final st = TokenStats();
      st.add(const TokenUsage(prompt: 100, completion: 10, cached: 60),
          model: 'm1');
      st.add(const TokenUsage(prompt: 50, completion: 5), model: 'm1');
      expect(st.cachedTokens, 60);
      expect(st.cacheHitRequests, 1);
      final back = TokenStats.fromJson(st.toJson());
      expect(back.cachedTokens, 60);
      expect(back.cacheHitRequests, 1);
      expect(back.todayTotal, 165);
      back.reset();
      expect(back.cachedTokens, 0);
    });

    test('相加保留缓存字段', () {
      const a = TokenUsage(prompt: 1, completion: 1, cached: 1);
      const b = TokenUsage(prompt: 2, completion: 2, cached: 3);
      expect((a + b).cached, 4);
    });
  });

  group('本地响应缓存', () {
    test('同样的请求得到同样的 key，参数变了 key 就变', () {
      final a = ResponseCache.keyFor(_req('gpt-4o'));
      final b = ResponseCache.keyFor(_req('gpt-4o'));
      expect(a, b);
      expect(a, isNot(ResponseCache.keyFor(_req('gpt-4o', text: '别的'))));
      expect(a, isNot(ResponseCache.keyFor(_req('gpt-4o-mini'))));
      expect(a, startsWith('c'));
    });

    test('写入后可命中，空回答不入缓存', () {
      final c = ResponseCache();
      const k = 'k1';
      c.put(k, '', null);
      expect(c.get(k), isNull);
      c.put(k, '答案', const TokenUsage(prompt: 10, completion: 4));
      final hit = c.get(k);
      expect(hit, isNotNull);
      expect(hit!.text, '答案');
      expect(hit.usage!.total, 14);
      expect(c.size, 1);
      expect(c.hitCount, 1);
    });

    test('过期条目自动丢弃', () {
      final c = ResponseCache();
      c.load({
        'hitCount': 0,
        'entries': {
          'old': {
            'text': '很久以前的回答',
            'at': 1,
            'usage': {'prompt': 1, 'completion': 1}
          }
        }
      });
      expect(c.get('old'), isNull);
    });

    test('清空后不再命中', () {
      final c = ResponseCache();
      c.put('k', 'v', null);
      c.clear();
      expect(c.get('k'), isNull);
      expect(c.hitCount, 0);
    });

    test('摘要取最后一条用户消息', () {
      const req = LlmRequest(
        baseUrl: 'x',
        apiKey: '',
        model: 'm',
        messages: [
          {'role': 'system', 'content': '系统提示'},
          {'role': 'user', 'content': '帮我找一下上周的会议记录'},
        ],
        maxTokens: 10,
        temperature: 0,
        topP: 1,
        thinkingBudget: 0,
        reasoningEffort: '',
        deepThinking: false,
      );
      expect(ResponseCache.summaryOf(req), contains('会议记录'));
    });
  });

  group('命中台账', () {
    test('累计、按模型分组与序列化', () {
      final l = CacheLedger();
      l.add(const CacheHitEntry(
          at: 1, model: 'm1', kind: CacheHitKind.prompt, tokens: 100));
      l.add(const CacheHitEntry(
          at: 2, model: 'm1', kind: CacheHitKind.response, tokens: 50));
      l.add(const CacheHitEntry(
          at: 3, model: 'm2', kind: CacheHitKind.prompt, tokens: 20));
      expect(l.hits, 3);
      expect(l.tokens, 170);
      expect(l.promptHits, 2);
      expect(l.responseHits, 1);
      expect(l.byModel['m1'], 150);
      final back = CacheLedger.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(l.toJson())) as Map));
      expect(back.hits, 3);
      expect(back.byModel['m2'], 20);
      back.clear();
      expect(back.hits, 0);
    });

    test('记录条数有上限', () {
      final l = CacheLedger();
      for (var i = 0; i < CacheLedger.maxRecords + 20; i++) {
        l.add(CacheHitEntry(
            at: i, model: 'm', kind: CacheHitKind.response, tokens: 1));
      }
      expect(l.records.length, CacheLedger.maxRecords);
      expect(l.responseHits, CacheLedger.maxRecords + 20);
    });
  });

  group('实时价格', () {
    test('解析 LiteLLM 费率表', () {
      final m = PriceCatalog.parseLiteLlm({
        'gpt-4o': {
          'input_cost_per_token': 0.0000025,
          'output_cost_per_token': 0.00001,
          'cache_read_input_token_cost': 0.00000125,
        },
        'sample_spec': {'input_cost_per_token': 1},
      });
      expect(m.length, 1);
      final p = m['gpt-4o']!;
      expect(p.inputPerM, closeTo(2.5, 0.001));
      expect(p.outputPerM, closeTo(10, 0.001));
      expect(p.cachedPerM, closeTo(1.25, 0.001));
    });

    test('解析 OpenRouter 费率表并登记短名', () {
      final m = PriceCatalog.parseOpenRouter({
        'data': [
          {
            'id': 'openai/gpt-4o',
            'pricing': {
              'prompt': '0.0000025',
              'completion': '0.00001',
              'input_cache_read': '0.00000125',
            }
          }
        ]
      });
      expect(m.containsKey('openai/gpt-4o'), isTrue);
      expect(m.containsKey('gpt-4o'), isTrue);
      expect(m['gpt-4o']!.inputPerM, closeTo(2.5, 0.001));
    });

    test('带日期 / 供应商前缀的模型名也能匹配', () {
      final m = PriceCatalog.parseLiteLlm({
        'gpt-4o': {'input_cost_per_token': 0.0000025},
      });
      expect(PriceCatalog.lookup(m, 'gpt-4o-2024-08-06'), isNotNull);
      expect(PriceCatalog.lookup(m, 'openai/gpt-4o'), isNotNull);
      expect(PriceCatalog.lookup(m, 'gpt-4o-mini-20250101'), isNotNull);
      expect(PriceCatalog.lookup(m, '完全不存在的模型xyz'), isNull);
    });

    test('费用计算：输入 / 输出 / 缓存折扣 / 汇率', () {
      final c = PriceCatalog.costOf(
        prompt: 1000000,
        completion: 1000000,
        inputPerM: 2,
        outputPerM: 10,
        cachedTokens: 500000,
        cachedPerM: 1,
        usdToCny: 7,
      );
      // 50 万全价输入(1) + 100 万输出(10) + 50 万缓存(0.5) = 11.5 USD
      expect(c, closeTo(80.5, 0.001));
    });
  });

  group('智能体权限分级', () {
    test('三档一键套用，危险能力只在完全权限放开', () {
      final s = AppSettings();
      s.applyPermissionLevel(AppSettings.kPermMinimal);
      expect(s.agentAllowWorkspace, isFalse);
      expect(s.agentAllowExternal, isFalse);
      expect(s.agentAllowDevice, isFalse);

      s.applyPermissionLevel(AppSettings.kPermStandard);
      expect(s.agentAllowWorkspace, isTrue);
      expect(s.agentAllowExternal, isTrue);
      expect(s.agentAllowSystem, isFalse);
      expect(s.agentAllowDevice, isFalse);

      s.applyPermissionLevel(AppSettings.kPermFull);
      expect(s.agentAllowSystem, isTrue);
      expect(s.agentAllowNetwork, isTrue);
      expect(s.agentAllowDevice, isTrue);

      s.markCustomPermission();
      expect(s.agentPermissionLevel, AppSettings.kPermCustom);
    });

    test('档位与授权能跨会话保存', () {
      final s = AppSettings();
      s.applyPermissionLevel(AppSettings.kPermFull);
      final back = AppSettings();
      back.load(Map<String, dynamic>.from(jsonDecode(s.encode()) as Map));
      expect(back.agentPermissionLevel, AppSettings.kPermFull);
      expect(back.agentAllowDevice, isTrue);
    });

    test('旧配置没有档位字段时从授权反推，不偷偷放权', () {
      final s = AppSettings();
      s.agentAllowWorkspace = true;
      s.agentAllowExternal = false;
      final j = Map<String, dynamic>.from(jsonDecode(s.encode()) as Map);
      j.remove('agentPermissionLevel');
      final back = AppSettings();
      back.load(j);
      expect(back.agentAllowDevice, isFalse);
      expect(back.agentPermissionLevel, isNot(AppSettings.kPermFull));
    });

    test('设备授权默认关闭，新工具都登记在案', () {
      const g = AgentGrant();
      expect(g.allows('device'), isFalse);
      expect(g.allows(''), isTrue);
      expect(AgentGrant.labelOf('device'), '设备清理');

      final clean = agentToolById('agent.storage.clean')!;
      expect(clean.grant, 'device');
      expect(clean.needsConfirmation, isTrue);
      final info = agentToolById('agent.storage.info')!;
      expect(info.risk, AgentRisk.read);
      expect(info.needsConfirmation, isFalse);
      expect(agentToolById('agent.files.search'), isNotNull);
      expect(agentToolById('agent.files.delete'), isNotNull);
      expect(agentToolById('agent.storage.settings'), isNotNull);
    });

    test('存储大小可读格式化', () {
      expect(StorageSummary.human(0), '0 B');
      expect(StorageSummary.human(512), '512 B');
      expect(StorageSummary.human(2048), '2.0 KB');
      expect(StorageSummary.human(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('界面与转场', () {
    test('设置里有缓存命中与费用两个新分类', () {
      final ids = kSettingsCats.map((c) => c.id).toList();
      expect(ids, contains('cache'));
      expect(ids, contains('billing'));
      expect(ids, contains('games'));
      expect(ids.toSet().length, ids.length);
    });

    test('所有整页路由默认保持下层 onstage（按钮返回不重建）', () {
      final r = SoftPageRoute<void>(builder: (_) => const SizedBox.shrink());
      expect(r.keepBelow, isTrue);
      expect(r.opaque, isFalse);
      final opaque = SoftPageRoute<void>(
          keepBelow: false, builder: (_) => const SizedBox.shrink());
      expect(opaque.opaque, isTrue);
    });
  });
}
