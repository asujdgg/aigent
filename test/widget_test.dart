import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_agent_app/main.dart' as app;
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/file_extract.dart';
import 'package:ai_agent_app/services/lang_catalog.dart';
import 'package:ai_agent_app/services/llm_client.dart';
import 'package:ai_agent_app/services/free_pool.dart';
import 'package:ai_agent_app/services/model_catalog.dart';
import 'package:ai_agent_app/services/project_search.dart';
import 'package:ai_agent_app/services/relay_catalog.dart';
import 'package:ai_agent_app/services/search_service.dart';
import 'package:ai_agent_app/services/voice_catalog.dart';
import 'package:ai_agent_app/services/voice_service.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/free_pool_panel.dart';
import 'package:ai_agent_app/ui/lang_picker_sheet.dart';
import 'package:ai_agent_app/ui/muse.dart';
import 'package:ai_agent_app/ui/relay_panel.dart';
import 'package:ai_agent_app/ui/voice_panel.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';
import 'package:ai_agent_app/ui/widgets.dart';
import 'package:ai_agent_app/ui/workspace_screen.dart';

void main() {
  group('能力档位与参数映射', () {
    test('档位越深，token 与思考预算越大', () {
      expect(Tier.lite.maxTokens, 1024);
      expect(Tier.expert.maxTokens, 8192);
      expect(
          Tier.deep.thinkingBudget, greaterThan(Tier.standard.thinkingBudget));
      expect(Tier.expert.historyLimit, greaterThan(Tier.lite.historyLimit));
    });

    test('设置序列化不包含明文 API Key', () {
      final s = AppSettings();
      s.apiKey = 'sk-secret-value';
      expect(s.encode().contains('sk-secret-value'), isFalse);
    });

    test('思考摘要只输出精简结论', () {
      final t = ThinkingTrace();
      t.append('第一步：拆解问题。第二步：检索资料并交叉验证。第三步：形成结论。');
      expect(t.summary.length, lessThanOrEqualTo(120));
      expect(t.summary, isNot(contains('第三步')));
    });
  });

  group('回归：开关打开后必须能关掉', () {
    testWidgets('点击 Switch 只触发一次 onChanged，且可来回切换', (tester) async {
      var value = true;
      final calls = <bool>[];

      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SwitchRow(
              title: '联网搜索',
              subtitle: '测试单行开关',
              value: value,
              onChanged: (v) {
                calls.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, [false], reason: '关闭时不得被第二次回调改回 true');
      expect(value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, [false, true]);
      expect(value, isTrue);

      // 整行文字区域同样可点，且只触发一次。
      await tester.tap(find.text('联网搜索'));
      await tester.pumpAndSettle();
      expect(calls, [false, true, false]);
      expect(value, isFalse);
    });
  });

  group('多选搜索源', () {
    test('可同时启用多个源，且每个源有独立配置与默认 Endpoint', () {
      final s = AppSettings();
      s.setSourceEnabled(SearchProvider.githubRepo, true);
      s.setSourceEnabled(SearchProvider.ddg, true);
      s.setSourceCfg(SearchProvider.githubCode, key: 'ghp_example');

      expect(s.activeSources.length, 3);
      expect(s.activeSources.contains(SearchProvider.tavily), isTrue);
      expect(s.activeSources.contains(SearchProvider.githubRepo), isTrue);
      expect(s.activeSources.contains(SearchProvider.ddg), isTrue);
      expect(s.sourceKey(SearchProvider.githubCode), 'ghp_example');
      expect(s.sourceEndpoint(SearchProvider.githubIssues),
          'https://api.github.com/search/issues');
    });

    test('多选与逐源配置可完整序列化 / 反序列化', () {
      final s = AppSettings();
      s.setSourceEnabled(SearchProvider.githubRepo, true);
      s.setSourceEnabled(SearchProvider.bocha, true);
      s.setSourceCfg(SearchProvider.bocha, key: 'bocha-key');
      s.setSourceCfg(SearchProvider.githubRepo,
          endpoint: 'https://ghe.example.com/api/search/repositories');

      final restored = AppSettings();
      restored.load(Map<String, dynamic>.from(jsonDecode(s.encode()) as Map));

      expect(restored.activeSources.length, 3);
      expect(restored.sourceKey(SearchProvider.bocha), 'bocha-key');
      expect(restored.sourceEndpoint(SearchProvider.githubRepo),
          'https://ghe.example.com/api/search/repositories');
    });

    test('旧版单源配置自动迁移，密钥不丢失', () {
      final s = AppSettings();
      s.load({
        'searchProvider': 'serper',
        'searchKey': 'serper-key',
        'searchEndpoint': 'https://google.serper.dev/search',
      });
      expect(s.activeSources, [SearchProvider.serper]);
      expect(s.sourceKey(SearchProvider.serper), 'serper-key');
    });

    test('内置 GitHub 三源齐全', () {
      expect(SearchProvider.values.contains(SearchProvider.githubRepo), isTrue);
      expect(SearchProvider.values.contains(SearchProvider.githubCode), isTrue);
      expect(
          SearchProvider.values.contains(SearchProvider.githubIssues), isTrue);
      expect(SearchProvider.values.length, 21);
      expect(SearchProvider.githubCode.needsKey, isTrue);
      expect(SearchProvider.githubRepo.needsKey, isFalse);
    });
  });

  group('多 API 连接配置', () {
    test('旧版单连接自动迁移为一份配置，不需要重新填写', () {
      final s = AppSettings();
      s.load({'baseUrl': 'https://a.example/v1', 'model': 'model-a'});
      expect(s.profiles.length, 1);
      expect(s.profiles.first.name, '默认连接');
      expect(s.activeProfile.baseUrl, 'https://a.example/v1');
      expect(s.model, 'model-a');
    });

    test('切换配置不删除旧配置，且各自保留 Key / 模型列表', () {
      final s = AppSettings();
      s.load({});
      final firstId = s.activeProfileId;
      s.apiKey = 'key-a';
      s.cachedModels = ['model-a1'];
      s.syncActive();

      s.profiles.add(ApiProfile(
          id: 'b',
          name: 'B 服务',
          baseUrl: 'https://b.example/v1',
          model: 'model-b'));
      s.applyProfileKeys({firstId: 'key-a', 'b': 'key-b'});
      s.activate('b');
      s.cachedModels = ['model-b1', 'model-b2'];
      s.syncActive();

      // 切回第一份：地址、Key、模型列表完整恢复。
      s.activate(firstId);
      expect(s.profiles.length, 2, reason: '切换不得删除任何配置');
      expect(s.apiKey, 'key-a');
      expect(s.cachedModels, ['model-a1']);

      // 再切回去：第二份也完好。
      s.activate('b');
      expect(s.baseUrl, 'https://b.example/v1');
      expect(s.apiKey, 'key-b');
      expect(s.model, 'model-b');
      expect(s.cachedModels, ['model-b1', 'model-b2']);
    });

    test('配置序列化不含任何明文密钥，删除当前项自动切换', () {
      final s = AppSettings();
      s.load({});
      s.profiles.add(ApiProfile(id: 'b', name: 'B', baseUrl: 'https://b/v1'));
      s.applyProfileKeys({'default': 'sk-a', 'b': 'sk-b'});
      final json = s.encode();
      expect(json.contains('sk-a'), isFalse);
      expect(json.contains('sk-b'), isFalse);
      expect(s.profileKeys()['b'], 'sk-b');

      final restored = AppSettings();
      restored.load(Map<String, dynamic>.from(jsonDecode(json) as Map));
      expect(restored.profiles.length, 2);

      restored.activate('b');
      restored.profiles.removeWhere((p) => p.id == 'b');
      restored.activate(restored.profiles.first.id);
      expect(restored.profiles.length, 1);
      expect(restored.activeProfile.id, 'default');
    });

    test('内置连接预设齐全', () {
      expect(kProfilePresets.length, greaterThanOrEqualTo(8));
      expect(kProfilePresets.any((p) => p.name == 'Ollama 本地'), isTrue);
      expect(kProfilePresets.any((p) => p.name == 'DeepSeek'), isTrue);
    });
  });

  group('回归：关闭联网后不得残留联网状态', () {
    test('searchActive 需要总开关与至少一个搜索源同时成立', () {
      final s = AppSettings();
      expect(s.searchActive, isFalse, reason: '默认不联网');

      s.webSearch = true;
      expect(s.searchActive, isTrue);

      s.enabledSources = [];
      expect(s.searchActive, isFalse, reason: '没有搜索源不得发起检索');

      s.setSourceEnabled(SearchProvider.serper, true);
      expect(s.searchActive, isTrue);

      s.webSearch = false;
      expect(s.searchActive, isFalse, reason: '总开关关闭后立即失效');
    });

    test('联网状态文案可被准确识别，普通生成文案不误判', () {
      expect(AppState.isSearchStatus('联网检索中…'), isTrue);
      expect(AppState.isSearchStatus('检索失败，继续作答'), isTrue);
      expect(AppState.isSearchStatus('已合并 2 个源 · 6 条资料'), isTrue);
      expect(AppState.isSearchStatus('生成中…'), isFalse);
      expect(AppState.isSearchStatus(''), isFalse);
    });

    test('v3.1 升级后不继承旧版持久化的联网开关，新状态可正常保存', () {
      final upgraded = AppSettings();
      upgraded.load({'webSearch': true, 'webSearchV2': false});
      expect(upgraded.webSearch, isFalse, reason: '覆盖安装不得沿用旧版「以为关着」的联网状态');

      final opened = AppSettings();
      opened.load({
        'webSearchV2': true,
        'enabledSources': ['serper']
      });
      expect(opened.searchActive, isTrue);

      final restored = AppSettings();
      restored
          .load(Map<String, dynamic>.from(jsonDecode(opened.encode()) as Map));
      expect(restored.searchActive, isTrue);
    });

    test('未启用联网时检索服务直接返回空，不发出任何请求', () async {
      final s = AppSettings();
      s.webSearch = false;
      final hits = await SearchService().search('flutter', s);
      expect(hits, isEmpty);

      s.webSearch = true;
      s.enabledSources = [];
      expect(await SearchService().search('flutter', s), isEmpty);
    });
  });

  group('引用展示', () {
    test('正文角标转可点链接，越界与代码块不受影响', () {
      final out = linkifyCitations('见 [1] 与 [2][3]', 3);
      expect(out, contains('aigent://cite/1'));
      expect(out, contains('aigent://cite/3'));
      expect(linkifyCitations('见 [9]', 3), '见 [9]');
      expect(linkifyCitations('没有角标', 3), '没有角标');

      final mixed = linkifyCitations('```\n[1]\n```\n正文 [1]', 1);
      final parts = mixed.split('```');
      expect(parts[1].contains('aigent://'), isFalse);
      expect(parts[2], contains('aigent://cite/1'));
    });

    test('引用条目携带来源与域名', () {
      const c = Citation(
          index: 2,
          title: '示例',
          url: 'https://www.example.com/a',
          snippet: '',
          source: 'Tavily');
      expect(c.host, 'example.com');
      expect(c.source, 'Tavily');
    });
  });

  group('研究工作台：提示词预设库', () {
    test('变量插值替换已知变量，未知变量原样保留', () {
      final p = PromptPreset(
        id: 'x',
        name: '测试',
        content: '模型 {{model}} / 日期 {{date}} / 提问 {{query}} / 未知 {{nope}}',
      );
      final out = p.render(model: 'gpt-4o', query: '量子计算');
      expect(out, contains('模型 gpt-4o'));
      expect(out, contains('提问 量子计算'));
      expect(out, contains('{{nope}}'));
      expect(PromptPreset.variablesOf(p.content),
          containsAll(<String>['model', 'date', 'query', 'nope']));
    });

    test('旧配置迁移：自定义提示词不丢，旧 researchMode 不再继承', () {
      final s = AppSettings();
      s.load(<String, dynamic>{
        'systemPrompt': '我的自定义提示词',
        'researchMode': true,
        'webSearch': true,
      });
      expect(s.researchWorkflow, isFalse, reason: 'v3.2 起「无审查模式」语义移除，不能继承旧开关');
      expect(s.webSearch, isFalse);
      expect(s.promptPresets.first.content, '我的自定义提示词');
      expect(s.activePreset.content, '我的自定义提示词');
      expect(s.encode().contains('我的自定义提示词'), isTrue);
    });

    test('切换预设不会覆盖另一份的内容', () {
      final s = AppSettings();
      s.ensurePresets();
      final a = s.activePreset;
      s.setPresetContent('A 内容');
      final b = PromptPreset(id: 'b', name: 'B', content: 'B 内容');
      s.promptPresets.add(b);
      s.activePresetId = b.id;
      expect(s.activePreset.content, 'B 内容');
      s.activePresetId = a.id;
      expect(s.activePreset.content, 'A 内容');
    });

    test('最终 System Prompt 来自当前预设，客户端不注入审查或反审查指令', () {
      final st = AppState();
      st.settings = AppSettings();
      st.settings.ensurePresets();
      st.settings.model = 'model-x';
      st.settings.setPresetContent('你是研究员，模型 {{model}}，问题 {{query}}');
      final sys = st.buildSystemPrompt(query: '测试问题');
      expect(sys, contains('model-x'));
      expect(sys, contains('测试问题'));
      expect(sys.contains('安全边界'), isFalse);
      expect(sys.contains('忽略'), isFalse);
    });
  });

  group('Token 消耗量查看', () {
    test('兼容 OpenAI / Anthropic / Ollama 的 usage 字段', () {
      expect(
          TokenUsage.fromApi(<String, dynamic>{
            'prompt_tokens': 10,
            'completion_tokens': 5,
          })!
              .total,
          15);
      expect(
          TokenUsage.fromApi(<String, dynamic>{
            'input_tokens': 3,
            'output_tokens': 7,
          })!
              .completion,
          7);
      expect(
          TokenUsage.fromApi(<String, dynamic>{
            'prompt_eval_count': 4,
            'eval_count': 6,
          })!
              .total,
          10);
      expect(
          TokenUsage.fromApi(<String, dynamic>{'total_tokens': 9})!.prompt, 9);
      expect(TokenUsage.fromApi(<String, dynamic>{}), isNull);
    });

    test('网关未返回 usage 时估算并标记为估算', () {
      final u = TokenUsage.estimate('中文测试内容较长一些', '输出内容');
      expect(u.estimated, isTrue);
      expect(u.total, greaterThan(0));
      expect(u.label, startsWith('≈'));
    });

    test('累计用量按模型分组、按日统计、可清零', () {
      final st = TokenStats();
      st.add(const TokenUsage(prompt: 10, completion: 5), model: 'm1');
      st.add(const TokenUsage(prompt: 20, completion: 10), model: 'm1');
      st.add(const TokenUsage(prompt: 7, completion: 3, estimated: true),
          model: 'm2');
      expect(st.total, 55);
      expect(st.requests, 3);
      expect(st.byModel['m1']!.total, 45);
      expect(st.estimatedRequests, 1);
      expect(st.todayTotal, 55);
      st.reset();
      expect(st.total, 0);
      expect(st.byModel, isEmpty);
    });

    LlmRequest req(bool include) => LlmRequest(
          baseUrl: 'https://example.com/v1',
          apiKey: '',
          model: 'm',
          messages: const <Map<String, dynamic>>[
            {'role': 'user', 'content': 'hi'}
          ],
          maxTokens: 100,
          temperature: 0.5,
          topP: 0.9,
          thinkingBudget: 0,
          reasoningEffort: 'medium',
          deepThinking: false,
          includeUsage: include,
        );

    test('用量追踪开关控制 stream_options', () {
      expect(req(true).toBody()['stream_options'],
          <String, dynamic>{'include_usage': true});
      expect(req(false).toBody().containsKey('stream_options'), isFalse);
      expect(req(true).toBody(stream: false).containsKey('stream_options'),
          isFalse);
    });

    test('请求体不含明文 API Key', () {
      const r = LlmRequest(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-should-not-appear',
        model: 'm',
        messages: <Map<String, dynamic>>[
          {'role': 'user', 'content': 'hi'}
        ],
        maxTokens: 100,
        temperature: 0.5,
        topP: 0.9,
        thinkingBudget: 0,
        reasoningEffort: 'medium',
        deepThinking: false,
      );
      expect(jsonEncode(r.toBody()).contains('sk-should-not-appear'), isFalse);
    });

    test('实验记录导出包含 token 用量且不含密钥', () {
      const r = ExperimentRecord(
        id: '1',
        at: 1700000000000,
        kind: 'chat',
        presetName: '标准研究',
        model: 'm',
        tier: '标准',
        query: '提问',
        params: <String, dynamic>{'max_tokens': 100},
        requestBody: '{"model":"m"}',
        responseRaw: '回答原文',
        elapsedMs: 120,
        usage: TokenUsage(prompt: 10, completion: 5),
      );
      final md = r.toMarkdown();
      expect(md, contains('Token'));
      expect(md, contains('回答原文'));
      expect(md.contains('sk-'), isFalse);
      expect(r.toJson()['usage'], isNotNull);
    });
  });

  group('多模态 / 图片识别排查', () {
    Attachment img(String name, List<int> bytes) {
      final b = Uint8List.fromList(bytes);
      return Attachment(
        id: 'a',
        name: name,
        kind: AttachKind.image,
        size: b.length,
        imageBytes: b,
        imageMime: FileExtractService.imageMimeOf(b),
      );
    }

    final jpeg = <int>[
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0,
      1
    ];
    final png = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
      0,
      0
    ];
    final heic = <int>[
      0,
      0,
      0,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x68,
      0x65,
      0x69,
      0x63,
      0,
      0,
      0,
      0
    ];
    final webp = <int>[
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
      0,
      0,
      0,
      0
    ];

    test('按字节魔数判定真实格式，扩展名失真不会误标 JPEG', () {
      expect(FileExtractService.imageMimeOf(Uint8List.fromList(jpeg)),
          'image/jpeg');
      expect(
          FileExtractService.imageMimeOf(Uint8List.fromList(png)), 'image/png');
      expect(FileExtractService.imageMimeOf(Uint8List.fromList(webp)),
          'image/webp');
      expect(FileExtractService.imageMimeOf(Uint8List.fromList(heic)),
          'image/heic');
      // 文件名是 .jpg，字节却是 PNG：必须按真实格式声明。
      expect(img('photo.jpg', png).mime, 'image/png');
    });

    test('OpenAI 标准格式产出 content 数组与 data URI', () {
      final m = FileExtractService.imageMessage(
          '总结一下', [img('a.jpg', jpeg)], VisionFormat.openai)!;
      expect(m['role'], 'user');
      final c = m['content'] as List;
      expect(c.length, 2);
      expect(c.first['type'], 'text');
      expect(c.first['text'], '总结一下');
      expect(c.last['type'], 'image_url');
      final u = c.last['image_url'] as Map;
      expect(u['url'].toString(), startsWith('data:image/jpeg;base64,'));
      expect(u['detail'], 'auto');
    });

    test('去 detail 格式不携带 detail 字段', () {
      final m = FileExtractService.imageMessage(
          'q', [img('a.jpg', jpeg)], VisionFormat.openaiLite)!;
      final u = (m['content'] as List).last['image_url'] as Map;
      expect(u.containsKey('detail'), isFalse);
    });

    test('Ollama 格式把纯 base64 放 images 数组、content 保持字符串', () {
      final m = FileExtractService.imageMessage(
          'q', [img('a.jpg', jpeg)], VisionFormat.ollama)!;
      expect(m['content'], isA<String>());
      final imgs = m['images'] as List;
      expect(imgs.length, 1);
      expect(imgs.first.toString().contains('data:'), isFalse);
    });

    test('仅文本模式完全不携带图片字节', () {
      final m = FileExtractService.imageMessage(
          'q', [img('a.jpg', jpeg)], VisionFormat.textOnly)!;
      expect(m['content'].toString(), contains('未发送给模型'));
      expect(jsonEncode(m).contains('base64,'), isFalse);
      expect(m['images'], isNull);
    });

    test('hasImages 正确区分真实带图与仅文本降级', () {
      LlmRequest req(VisionFormat f) => LlmRequest(
            baseUrl: 'https://example.com/v1',
            apiKey: '',
            model: 'm',
            messages: [
              FileExtractService.imageMessage('q', [img('a.jpg', jpeg)], f)!
            ],
            maxTokens: 10,
            temperature: 0,
            topP: 1,
            thinkingBudget: 0,
            reasoningEffort: '',
            deepThinking: false,
          );
      expect(req(VisionFormat.openai).hasImages, isTrue);
      expect(req(VisionFormat.ollama).hasImages, isTrue);
      expect(req(VisionFormat.textOnly).hasImages, isFalse);
    });

    test('视觉能力判定：deepseek-v4-flash 不视作视觉模型', () {
      expect(looksLikeVisionModel('deepseek-v4-flash'), isFalse);
      expect(looksLikeVisionModel('gpt-4o-mini'), isTrue);
      expect(looksLikeVisionModel('qwen2-vl-7b'), isTrue);
      expect(const ModelInfo(id: 'gpt-4o').vision, isTrue);
    });

    test('发送格式可持久化，旧配置默认 OpenAI 标准', () {
      final s = AppSettings()..visionFormat = VisionFormat.ollama;
      expect(s.toJson()['visionFormat'], 'ollama');
      final s2 = AppSettings()..load(s.toJson());
      expect(s2.visionFormat, VisionFormat.ollama);
      final s3 = AppSettings()..load(<String, dynamic>{});
      expect(s3.visionFormat, VisionFormat.openai);
      expect(s3.visionHintDismissed, isFalse);
    });

    test('诊断标出不支持的格式与超大图片', () {
      final heicDiag =
          FileExtractService.diagnose([img('a.heic', heic)]).single;
      expect(heicDiag.mime, 'image/heic');
      expect(heicDiag.supported, isFalse);
      expect(heicDiag.note, isNotNull);

      final big = Uint8List(5 * 1024 * 1024)
        ..[0] = 0xFF
        ..[1] = 0xD8
        ..[2] = 0xFF;
      final bigDiag = FileExtractService.diagnose([
        Attachment(
            id: 'b',
            name: 'big.jpg',
            kind: AttachKind.image,
            size: big.length,
            imageBytes: big,
            imageMime: 'image/jpeg')
      ]).single;
      expect(bigDiag.supported, isTrue);
      expect(bigDiag.note, contains('413'));
      expect(bigDiag.base64Len, greaterThan(bigDiag.bytes));
    });
  });

  group('主题模式 / 跟随系统', () {
    test('默认跟随系统，三档标签齐全', () {
      final s = AppSettings();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.darkMode, isFalse);
      expect(AppThemeMode.values.length, 3);
      for (final m in AppThemeMode.values) {
        expect(m.label.isNotEmpty, isTrue);
        expect(m.shortLabel.isNotEmpty, isTrue);
        expect(m.note.isNotEmpty, isTrue);
      }
    });

    test('三档映射到 Flutter ThemeMode，system 不再被当成固定浅色', () {
      expect(app.flutterThemeMode(AppThemeMode.system), ThemeMode.system);
      expect(app.flutterThemeMode(AppThemeMode.light), ThemeMode.light);
      expect(app.flutterThemeMode(AppThemeMode.dark), ThemeMode.dark);
      expect(ThemeMode.values.length, 3);
    });

    test('三档可完整序列化 / 反序列化', () {
      for (final m in AppThemeMode.values) {
        final s = AppSettings()..themeMode = m;
        final j = s.toJson();
        expect(j['themeMode'], m.name);
        final s2 = AppSettings()..load(j);
        expect(s2.themeMode, m);
      }
    });

    test('darkMode 是只读镜像，随 themeMode 同步', () {
      final s = AppSettings()..themeMode = AppThemeMode.dark;
      expect(s.darkMode, isTrue);
      expect(s.toJson()['darkMode'], isTrue);
      s.themeMode = AppThemeMode.light;
      expect(s.darkMode, isFalse);
      expect(s.toJson()['darkMode'], isFalse);
    });

    test('旧配置迁移：开过深色保留深色，否则升级后默认跟随系统', () {
      final a = AppSettings()..load(<String, dynamic>{'darkMode': true});
      expect(a.themeMode, AppThemeMode.dark);
      final b = AppSettings()..load(<String, dynamic>{});
      expect(b.themeMode, AppThemeMode.system);
      final c = AppSettings()..load(<String, dynamic>{'darkMode': false});
      expect(c.themeMode, AppThemeMode.system);
    });

    test('新 themeMode 优先于遗留 darkMode，且不继承旧的强制深色', () {
      final s = AppSettings()
        ..load(<String, dynamic>{'themeMode': 'system', 'darkMode': true});
      expect(s.themeMode, AppThemeMode.system);
      expect(s.darkMode, isFalse);
    });
  });

  group('设置页 v3.5：分类导航与搜索', () {
    test('分类目录覆盖全部设置域且 id 唯一', () {
      expect(kSettingsCats.length, 15);
      final ids = kSettingsCats.map((c) => c.id).toSet();
      expect(ids.length, kSettingsCats.length);
      expect(
          ids.containsAll(const [
            'connection',
            'relay',
            'free',
            'appearance',
            'language',
            'persona',
            'voice',
            'agent',
            'capability',
            'vision',
            'search',
            'research',
            'presets',
            'usage',
            'games'
          ]),
          isTrue);
      for (final c in kSettingsCats) {
        expect(c.title.isNotEmpty, isTrue);
        expect(c.desc.isNotEmpty, isTrue);
        expect(c.keys.isNotEmpty, isTrue);
      }
    });

    test('空关键词返回全部分类', () {
      expect(kSettingsCats.where((c) => settingsCatMatches(c, '')).length,
          kSettingsCats.length);
      expect(
          kSettingsCats.where((c) => settingsCatMatches(c, '   ')).length,
          kSettingsCats.length);
    });

    test('反代关键词可直达网页版反代分类', () {
      String hit(String q) =>
          kSettingsCats.firstWhere((c) => settingsCatMatches(c, q)).id;
      expect(hit('反代'), 'relay');
      expect(hit('chat2api'), 'relay');
      expect(hit('G4F'), 'relay');
      expect(hit('局域网'), 'relay');
      expect(hit('deepseek'), 'relay');
    });

    test('免密关键词可直达免密模型分类', () {
      String hit(String q) =>
          kSettingsCats.firstWhere((c) => settingsCatMatches(c, q)).id;
      expect(hit('免密'), 'free');
      expect(hit('无需密钥'), 'free');
      expect(hit('pollinations'), 'free');
    });

    test('形象关键词可直达人物形象分类', () {
      String hit(String q) =>
          kSettingsCats.firstWhere((c) => settingsCatMatches(c, q)).id;
      expect(hit('头像'), 'persona');
      expect(hit('形象'), 'persona');
      expect(hit('PERSONA'), 'persona');
    });

    test('关键词别名可直达对应分类（大小写不敏感）', () {
      String hit(String q) =>
          kSettingsCats.firstWhere((c) => settingsCatMatches(c, q)).id;
      expect(hit('深色'), 'appearance');
      expect(hit('THEME'), 'appearance');
      expect(hit('token'), 'usage');
      expect(hit('serper'), 'search');
      expect(hit('提示词'), 'presets');
      expect(hit('图片'), 'vision');
      expect(hit('工作流'), 'research');
      expect(hit('key'), 'connection');
    });

    test('无匹配关键词返回空结果', () {
      expect(
          kSettingsCats
              .where((c) => settingsCatMatches(c, 'zzzz-不存在的设置'))
              .isEmpty,
          isTrue);
    });
  });

  group('设置页 v3.5：开关清晰化与乐观更新', () {
    testWidgets('开关显示明确的开/关状态文字与副标题', (tester) async {
      Widget wrap(bool v) => MaterialApp(
            home: Scaffold(
              body: SwitchRow(
                title: '深度思考',
                subtitle: '先完成推理再输出结论',
                value: v,
                onChanged: (_) {},
              ),
            ),
          );

      await tester.pumpWidget(wrap(true));
      expect(find.text('深度思考'), findsOneWidget);
      expect(find.text('先完成推理再输出结论'), findsOneWidget,
          reason: '副标题必须真正渲染，旧实现遗漏了它');
      expect(find.text('开'), findsOneWidget);
      expect(find.text('关'), findsNothing);

      await tester.pumpWidget(wrap(false));
      await tester.pumpAndSettle();
      expect(find.text('关'), findsOneWidget);
      expect(find.text('开'), findsNothing);
    });

    testWidgets('新卡片样式下文字区与 Switch 仍各自只回调一次', (tester) async {
      var value = false;
      final calls = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SwitchRow(
              title: '用量追踪',
              subtitle: '索取真实 usage',
              value: value,
              onChanged: (v) {
                calls.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      await tester.tap(find.text('用量追踪'));
      await tester.pumpAndSettle();
      expect(calls, [true, false], reason: '不得回归「打开后关不掉」双重触发');
    });

    test('apply 同步改内存并立即生效，落盘失败不影响交互', () {
      final st = AppState()..settings = AppSettings();
      expect(st.settings.deepThinking, isFalse);
      st.apply((s) => s.deepThinking = true);
      expect(st.settings.deepThinking, isTrue,
          reason: '乐观更新必须在调用返回时就已生效，不等 await');
      st.apply((s) => s.webSearch = true);
      expect(st.settings.webSearch, isTrue);
    });
  });

  group('流式输出 v3.6：乱码 / 逐字蹦 / 结束突变', () {
    test('协议行、心跳与半截 JSON 都不会被当成回答正文', () {
      final c = LlmClient();
      for (final dirty in [
        'event: message',
        'id: 123',
        ': ping',
        'data: {"choices":',
        '<noscript>请启用 JavaScript</noscript>',
        '[DONE]',
        'HTTP/1.1 200 OK',
      ]) {
        expect(c.parseSseEvent(dirty), isNull, reason: dirty);
      }
      expect(LlmClient.isReadableStreamText('event: message'), isFalse);
      expect(LlmClient.isReadableStreamText('HTTP/1.1 200 OK'), isFalse);
      expect(LlmClient.isReadableStreamText('这是一段正常回答'), isTrue);
    });

    test('合法 delta 正常解析', () {
      final chunk =
          LlmClient().parseSseEvent('{"choices":[{"delta":{"content":"你好"}}]}');
      expect(chunk, isNotNull);
      expect(chunk!.content, '你好');
    });

    test('usage-only 收尾事件不再被丢弃', () {
      final chunk = LlmClient().parseSseEvent(
          '{"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}');
      expect(chunk, isNotNull);
      expect(chunk!.usage, isNotNull);
      expect(chunk.usage!.prompt, 12);
    });

    test('兼容顶层 content 与对象形态正文', () {
      final c = LlmClient();
      expect(c.parseSseEvent('{"response":"来自 Ollama"}')!.content, '来自 Ollama');
      expect(
          c
              .parseSseEvent(
                  '{"choices":[{"delta":{"content":{"text":"对象正文"}}}]}')!
              .content,
          '对象正文');
    });

    test('清洗掉替换字符 / BOM / 控制符 / 零宽字符', () {
      expect(LlmClient.cleanStreamText('你\uFFFD好\uFEFF\u200B\u0001'), '你好');
      expect(LlmClient.cleanStreamText('第一行\n第二行\t结束'), '第一行\n第二行\t结束');
    });

    test('批量刷新：短片段不逐字输出，够量或超时才出', () {
      expect(shouldFlushStream('你', 10, true), isFalse);
      expect(shouldFlushStream('你好', 10, true), isFalse);
      expect(shouldFlushStream('你好呀，', 10, true), isTrue); // 句读边界
      expect(shouldFlushStream('一二三四五六七八', 80, false), isTrue);
      expect(shouldFlushStream('短', 150, false), isTrue); // 超时兜底
      expect(shouldFlushStream('x' * 45, 0, false), isTrue); // 超长立即
    });

    test('Markdown 补齐幂等：流式与最终渲染字符串一致', () {
      for (final s in const [
        '**加粗还没写完',
        '```dart\nprint(1)',
        '这是 `行内代码',
        '## 标题\n\n正常段落 **已完成**',
      ]) {
        final once = completeMarkdown(s);
        expect(completeMarkdown(once), once, reason: s);
      }
      expect(completeMarkdown('**加粗还没写完').endsWith('**'), isTrue);
      expect(completeMarkdown('```dart\nprint(1)').endsWith('```'), isTrue);
    });

    test('代码块内的未闭合符号不受补齐影响', () {
      const s = '```\n** 这不是粗体\n```';
      expect(completeMarkdown(s), s);
    });
  });

  group('模型关键词搜索 v3.6：跨运营商同族聚合', () {
    ModelCatalog catalog() => ModelCatalog.fromSources(const [
          ModelSource(
            profileId: 'a',
            profileName: '官方',
            modelIds: [
              'openai/gpt-4o-2024-08-06',
              'gpt-4o-mini',
              'deepseek-chat-v3',
            ],
            active: true,
          ),
          ModelSource(
            profileId: 'b',
            profileName: '中转B',
            modelIds: [
              'azure/gpt-4o',
              'gpt-4o-mini',
              'claude-3-5-sonnet-20241022',
            ],
          ),
          ModelSource(
            profileId: 'c',
            profileName: '中转C',
            modelIds: ['gpt-4o', 'qwen2.5-72b-instruct'],
          ),
        ]);

    test('族归一化去掉 provider 前缀与日期后缀', () {
      expect(modelFamily('openai/gpt-4o-2024-08-06'), 'gpt-4o');
      expect(modelFamily('anthropic/claude-3-5-sonnet-20241022:free'),
          'claude-3-5-sonnet');
      expect(modelProvider('azure/gpt-4o'), 'azure');
      expect(modelFamily('deepseek-chat-v3-0324'), 'deepseek-chat-v3');
    });

    test('命中一个即把同模型的其他运营商全部列出', () {
      final groups = catalog().search('gpt-4o');
      final entries = groups.expand((g) => g.entries).toList();
      final ids = entries.map((e) => e.id).toList();
      expect(ids, contains('openai/gpt-4o-2024-08-06'));
      expect(ids, contains('azure/gpt-4o'));
      expect(ids, contains('gpt-4o'));
      expect(entries.map((e) => e.profileId).toSet(),
          containsAll(['a', 'b', 'c']));
      expect(groups.every((g) => g.providerCount >= 1), isTrue);
    });

    test('跨配置同 ID 不去重，各自保留一条', () {
      expect(catalog().entries.where((e) => e.id == 'gpt-4o-mini').length, 2);
    });

    test('简写别名与大小写不敏感', () {
      final c = catalog();
      expect(c.search('4o').isNotEmpty, isTrue);
      expect(c.search('GPT-4O').isNotEmpty, isTrue);
      expect(c.search('ds').isNotEmpty, isTrue);
    });

    test('多关键词 AND，无命中或空关键词返回空', () {
      final c = catalog();
      expect(c.search('gpt claude'), isEmpty);
      expect(c.search('不存在的模型xyz'), isEmpty);
      expect(c.search(''), isEmpty);
    });

    test('能力关键词只筛视觉 / 推理模型', () {
      final c = ModelCatalog.fromSources(const [
        ModelSource(
            profileId: 'a',
            profileName: 'p',
            modelIds: ['gpt-4o', 'deepseek-r1']),
      ]);
      final v = c.search('视觉').expand((g) => g.entries).toList();
      expect(v.any((e) => e.id == 'gpt-4o'), isTrue);
      expect(v.any((e) => e.id == 'deepseek-r1'), isFalse);
      final r = c.search('推理').expand((g) => g.entries).toList();
      expect(r.any((e) => e.id == 'deepseek-r1'), isTrue);
    });

    test('目录统计与快捷族', () {
      final c = catalog();
      expect(c.sourceCount, 3);
      expect(c.familyCount, 5);
      expect(c.topFamilies(3).length, 3);
    });
  });

  // ---------------------------------------------------------------- v3.7
  group('v3.7 会话隔离：生成状态 / 草稿 / 附件互不串台', () {
    AppState seeded() {
      final st = AppState()..settings = AppSettings();
      st.conversations = [
        Conversation(id: 'c1', title: '对话一'),
        Conversation(id: 'c2', title: '对话二'),
      ];
      st.activeId = 'c1';
      return st;
    }

    test('生成中状态按会话独立：A 生成不会让 B 显示正在生成', () {
      final st = seeded();
      final a = st.convById('c1')!;
      final b = st.convById('c2')!;
      a.generating = true;
      a.status = '生成中…';
      expect(st.generating, isTrue, reason: '当前在 A');
      expect(st.status, '生成中…');

      st.switchConversation('c2');
      expect(st.generating, isFalse, reason: '切到 B 必须干净');
      expect(st.status, isEmpty);
      expect(st.active.id, 'c2');

      st.switchConversation('c1');
      expect(st.generating, isTrue, reason: '切回 A 仍保留自己的生成状态');
      expect(st.status, '生成中…');
      // B 从未被写入。
      expect(b.generating, isFalse);
      expect(b.status, isEmpty);
    });

    test('输入草稿按会话独立保存，切走再切回仍在', () {
      final st = seeded();
      st.setDraft('c1', '给 A 的问题');
      st.setDraft('c2', '给 B 的问题');
      expect(st.draftFor('c1'), '给 A 的问题');
      expect(st.draftFor('c2'), '给 B 的问题');
      st.switchConversation('c2');
      expect(st.draftFor(st.activeId), '给 B 的问题');
    });

    test('程序化预填递增 seed 且只写目标会话草稿', () {
      final st = seeded();
      final before = st.draftSeed;
      st.prefillDraft('c2', '快捷开场');
      expect(st.draftSeed, before + 1);
      expect(st.draftFor('c2'), '快捷开场');
      expect(st.draftFor('c1'), isEmpty);
    });

    test('待发附件按会话隔离', () {
      final st = seeded();
      st.addAttachment(const Attachment(
          id: 'f1', name: 'a.png', kind: AttachKind.image, size: 10));
      expect(st.pending.length, 1);
      st.switchConversation('c2');
      expect(st.pending, isEmpty, reason: 'B 不该看到 A 选的图片');
      st.switchConversation('c1');
      expect(st.pending.length, 1, reason: '切回 A 附件仍在');
    });

    test('新建会话后生成状态与草稿都是空的', () {
      final st = seeded();
      final a = st.convById('c1')!;
      a.generating = true;
      a.status = '生成中…';
      st.setDraft('c1', '半句话');
      st.newConversation();
      expect(st.generating, isFalse);
      expect(st.status, isEmpty);
      expect(st.draftFor(st.activeId), isEmpty);
      expect(st.active.id, isNot('c1'));
    });

    test('删除正在生成的会话会取消并释放其流上下文', () {
      final st = seeded();
      st.convById('c1')!.generating = true;
      st.deleteConversation('c1');
      expect(st.convById('c1'), isNull);
      expect(st.activeId, 'c2');
      expect(st.generating, isFalse);
    });

    test('anyGenerating 只看是否有任意会话在生成', () {
      final st = seeded();
      expect(st.anyGenerating, isFalse);
      st.convById('c2')!.generating = true;
      expect(st.anyGenerating, isTrue);
      expect(st.generating, isFalse, reason: '当前活动会话是 c1');
    });
  });

  group('v3.7 人物形象', () {
    test('Persona 序列化往返保留头像、设定与主题色', () {
      final p = Persona(
        id: 'px',
        name: '小砚',
        glyph: '砚',
        imageB64: 'YWJj',
        tagline: '研究搭档',
        roleHint: '先给结论',
        tint: 3,
      );
      final q = Persona.fromJson(p.toJson());
      expect(q.id, 'px');
      expect(q.name, '小砚');
      expect(q.glyph, '砚');
      expect(q.imageB64, 'YWJj');
      expect(q.hasImage, isTrue);
      expect(q.tagline, '研究搭档');
      expect(q.roleHint, '先给结论');
      expect(q.tint, 3);
      expect(q.color, kPersonaTints[3]);
    });

    test('旧配置无 persona 字段时保持空形象库，不塞占位条目', () {
      final s = AppSettings()
        ..load(<String, dynamic>{
          'model': 'gpt-4o',
          'themeMode': 'dark',
        });
      expect(s.personas, isEmpty);
      expect(s.activePersonaId, isEmpty);
      expect(s.activePersona.name, isEmpty, reason: '没设置形象就没有名字');
      expect(s.personaEnabled, isTrue);
      expect(s.model, 'gpt-4o');
      expect(s.themeMode, AppThemeMode.dark);
    });

    test('形象设置完整往返（含自定义图片与开关）', () {
      final s = AppSettings();
      s.personas = [
        Persona(id: 'q1', name: '自定义', imageB64: 'eHl6', tint: 5),
      ];
      s.activePersonaId = 'q1';
      s.personaEnabled = false;
      s.showPersonaHeader = false;
      s.showBubbleAvatar = false;
      final t = AppSettings()..load(s.toJson());
      expect(t.activePersona.name, '自定义');
      expect(t.activePersona.hasImage, isTrue);
      expect(t.activePersona.tint, 5);
      expect(t.personaEnabled, isFalse);
      expect(t.showPersonaHeader, isFalse);
      expect(t.showBubbleAvatar, isFalse);
    });

    test('会话可单独指定形象，删除后回落全局默认', () {
      final st = AppState()..settings = AppSettings();
      final c = Conversation(id: 'c1', title: 'A');
      st.conversations = [c];
      st.activeId = 'c1';
      st.addPersona('临时');
      final customId = st.settings.activePersonaId;
      st.setConversationPersona('c1', customId);
      expect(st.activePersona.id, customId);
      expect(st.settings.personaFor(c.personaId).id, customId);

      st.deletePersona(customId);
      expect(c.personaId, isEmpty, reason: '引用已删形象的会话回落到全局默认');
      expect(st.settings.personas, isEmpty, reason: '最后一个形象删掉后库里就是空的');
      expect(st.activePersona.name, isEmpty);
    });

    test('角色设定写入 System Prompt，关闭形象后不注入', () {
      final st = AppState()..settings = AppSettings();
      st.settings.ensurePresets();
      st.conversations = [Conversation(id: 'c1', title: 'A')];
      st.activeId = 'c1';
      final p = Persona(
        id: 'pz',
        name: '砚',
        tagline: '研究搭档',
        roleHint: '语气克制，先给结论再给依据。',
      );
      final sys = st.buildSystemPrompt(query: '测试', persona: p);
      expect(sys, contains('砚'));
      expect(sys, contains('语气克制，先给结论再给依据。'));
      expect(sys, contains('[身份]'));

      st.settings.personaEnabled = false;
      final off = st.buildSystemPrompt(query: '测试', persona: p);
      expect(off.contains('[身份]'), isFalse);
      // 关闭形象也不该引入任何审查 / 反审查指令。
      expect(off.contains('安全边界'), isFalse);
    });

    test('自定义头像字节经 base64 存入形象', () {
      final st = AppState()..settings = AppSettings();
      final id = st.addPersona('带图');
      st.setPersonaAvatar(id, Uint8List.fromList([1, 2, 3, 255]));
      final p = st.settings.personaById(id)!;
      expect(p.hasImage, isTrue);
      expect(base64Decode(p.imageB64), [1, 2, 3, 255]);
      st.clearPersonaAvatar(id);
      expect(p.hasImage, isFalse);
    });

    test('不存在的形象 id 不会改动形象库', () {
      final st = AppState()..settings = AppSettings();
      final n = st.settings.personas.length;
      st.deletePersona('persona_none');
      expect(st.settings.personas.length, n);
    });
  });

  group('v3.8 网页版反代：地址解析与探测', () {
    test('主机输入支持裸 IP、host:port 与完整 URL', () {
      final a = RelayProbe.parseTarget('192.168.1.5');
      expect(a.host, '192.168.1.5');
      expect(a.port, isNull);
      expect(a.scheme, 'http');

      final b = RelayProbe.parseTarget('localhost:5005');
      expect(b.host, 'localhost');
      expect(b.port, 5005);

      final c = RelayProbe.parseTarget('http://10.0.0.7:8000/v1');
      expect(c.host, '10.0.0.7');
      expect(c.port, 8000);
      expect(c.scheme, 'http');

      final d = RelayProbe.parseTarget('https://relay.example.com/v1');
      expect(d.host, 'relay.example.com');
      expect(d.port, isNull);
      expect(d.scheme, 'https');

      final e = RelayProbe.parseTarget('  ');
      expect(e.host, '127.0.0.1');
    });

    test('候选模型地址会补 /v1，且不重复', () {
      expect(RelayProbe.modelUrls('http://h:8000/v1'),
          ['http://h:8000/v1/models']);
      expect(RelayProbe.modelUrls('http://h:8000/'),
          ['http://h:8000/models', 'http://h:8000/v1/models']);
      expect(RelayProbe.modelUrls('http://h:8000/v1/chat/completions'),
          ['http://h:8000/v1/models']);
      expect(RelayProbe.modelUrls('http://h:8000/v1/models'),
          ['http://h:8000/v1/models']);
    });

    test('模型列表兼容 OpenAI、Ollama 与纯数组', () {
      expect(
          RelayProbe.parseModels({
            'data': [
              {'id': 'gpt-4o'},
              {'id': 'deepseek-chat'}
            ]
          }),
          ['gpt-4o', 'deepseek-chat']);
      expect(
          RelayProbe.parseModels({
            'models': [
              {'name': 'qwen3'},
              {'name': 'llama3.3'}
            ]
          }),
          ['qwen3', 'llama3.3']);
      expect(RelayProbe.parseModels(['m1', 'm2']), ['m1', 'm2']);
      expect(RelayProbe.parseModels('{"data":[{"id":"kimi"}]}'), ['kimi']);
      expect(RelayProbe.parseModels({'error': 'x'}), isEmpty);
    });

    test('回环地址识别与主机猜测', () {
      expect(RelayProbe.isLoopback('127.0.0.1'), isTrue);
      expect(RelayProbe.isLoopback('LOCALHOST'), isTrue);
      expect(RelayProbe.isLoopback('192.168.1.5'), isFalse);
      // 当前连接是公网地址时不拿它当扫描目标，回落到 127.0.0.1。
      expect(RelayProbe.guessHost('https://api.openai.com/v1'), '127.0.0.1');
      expect(RelayProbe.guessHost('http://192.168.1.9:8000/v1'), '192.168.1.9');
    });

    test('预设库 id 唯一、端口与模型可用', () {
      final ids = kRelayPresets.map((p) => p.id).toSet();
      expect(ids.length, kRelayPresets.length);
      expect(kRelayPresets.length, greaterThanOrEqualTo(12));
      for (final p in kRelayPresets) {
        expect(p.port, greaterThan(0));
        expect(p.path.startsWith('/') || p.fixedBaseUrl != null, isTrue);
        expect(p.name.isNotEmpty, isTrue);
        expect(p.summary.isNotEmpty, isTrue);
        // 公共实例没有部署命令，其余项目必须给出可复制的启动方式。
        expect(p.deploy.isNotEmpty || p.isPublicInstance, isTrue);
        for (final t in p.tags) {
          expect(kRelayTags.contains(t), isTrue);
        }
      }
      // 没有密钥的项目必须明确标成 none，避免面板逼用户填空 Key。
      final noKey = kRelayPresets.where((p) => p.auth == RelayAuth.none);
      expect(noKey.map((p) => p.id),
          containsAll(['g4f', 'ollama', 'copilot-api']));
    });

    test('扫描失败时不抛异常，返回空列表', () async {
      // 保留端口 1，必然连不上；只验证失败路径不会把异常抛给 UI。
      final hits = await RelayProbe.scan(host: '127.0.0.1:1');
      expect(hits, isEmpty);
    });

    testWidgets('反代面板能渲染，点项目能打开接入弹层', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);

      var added = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RelayPanel(
              dark: false,
              currentBaseUrl: 'https://api.openai.com/v1',
              onAdd: (p, base, key, model) async {
                added++;
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('扫描已运行的服务'), findsOneWidget);
      expect(find.text('gpt4free'), findsOneWidget);
      // 公网连接不该被当成扫描目标。
      expect(find.text('127.0.0.1 或 192.168.1.5'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('gpt4free'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('gpt4free'));
      await tester.pumpAndSettle();

      expect(find.text('接口地址'), findsOneWidget);
      expect(find.text('测试连通'), findsOneWidget);
      expect(find.text('部署'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('接入'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('接入'));
      await tester.pumpAndSettle();
      expect(added, 1);
    });

    test('预设库覆盖反代、网关、官方与本机四类', () {
      for (final g in RelayGroup.values) {
        expect(kRelayPresets.where((p) => p.group == g).isNotEmpty, isTrue,
            reason: '$g 分组为空');
      }
      final official = kRelayPresets.where((p) => p.isOfficial).toList();
      expect(official, isNotEmpty);
      for (final p in official) {
        // 官方平台没有自建端口，必须写死地址且必须带 Key。
        expect(p.fixedBaseUrl, isNotNull);
        expect(p.auth, RelayAuth.required);
      }
      expect(kRelayPresets.map((p) => p.id), contains('deepseek-official'));
      expect(kRelayPresets.length, greaterThanOrEqualTo(24));
    });

    test('关键词能搜到 deepseek 相关项目', () {
      final hit = kRelayPresets.where((p) =>
          p.name.toLowerCase().contains('deepseek') ||
          p.models.any((m) => m.toLowerCase().contains('deepseek')));
      expect(hit.map((p) => p.id),
          containsAll(['chat2api-multi', 'deepseek-official']));
    });
  });

  group('v3.9 免密模型池', () {
    test('内置免密源 id 唯一、地址为 https', () {
      expect(kFreeEndpoints, isNotEmpty);
      final ids = kFreeEndpoints.map((e) => e.id).toSet();
      expect(ids.length, kFreeEndpoints.length);
      for (final e in kFreeEndpoints) {
        expect(e.baseUrl.startsWith('https://'), isTrue);
        expect(e.model.isNotEmpty, isTrue);
        expect(e.kind, FreeKind.publicSource);
      }
    });

    test('错误码能区分额度、密钥、限流与路径', () {
      expect(FreePool.explain(402, ''), contains('额度'));
      expect(FreePool.explain(401, ''), contains('密钥'));
      expect(FreePool.explain(429, ''), contains('限流'));
      expect(FreePool.explain(404, ''), contains('路径'));
      expect(FreePool.explain(503, ''), contains('异常'));
      expect(FreePool.explain(0, 'timeout'), contains('超时'));
      expect(FreePool.explain(0, 'unreachable'), contains('不可达'));
    });

    test('200 但不是对话结果不算成功', () {
      expect(
          FreePool.looksLikeCompletion(
              '{"choices":[{"message":{"content":"hi"}}]}'),
          isTrue);
      expect(FreePool.looksLikeCompletion('{"error":{"message":"nope"}}'),
          isFalse);
      expect(FreePool.looksLikeCompletion('<html>blocked</html>'), isFalse);
      expect(FreePool.looksLikeCompletion(''), isFalse);
    });

    test('从已有连接里挑出免密的本机与内网服务', () {
      final profiles = [
        ApiProfile(
            id: 'a',
            name: '本机 g4f',
            baseUrl: 'http://127.0.0.1:1337/v1',
            model: 'gpt-4o-mini'),
        ApiProfile(
            id: 'b',
            name: '局域网 Ollama',
            baseUrl: 'http://192.168.1.5:11434/v1',
            model: 'qwen3'),
        ApiProfile(
            id: 'c',
            name: '内网但有 Key',
            baseUrl: 'http://192.168.1.5:8000/v1',
            model: 'x',
            apiKey: 'sk-1'),
        ApiProfile(
            id: 'd',
            name: '公网官方',
            baseUrl: 'https://api.openai.com/v1',
            model: 'gpt-4o'),
      ];
      final r = FreePool.localFromProfiles(profiles);
      expect(r.length, 2);
      expect(r.map((e) => e.id), containsAll(['local_a', 'local_b']));
      for (final e in r) {
        expect(e.kind, FreeKind.local);
        expect(e.fallbackModels.length, lessThanOrEqualTo(3));
      }
    });

    testWidgets('免密面板渲染，未检测时列出待检测来源', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FreePoolPanel(
              dark: false,
              profiles: const [],
              onAdd: (name, base, key, model) async {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 标题与页面标题重复，v4.9.4 起卡片不再重复写「免密模型」，
      // 直接用说明句与操作按钮作为入口。
      expect(find.text('免密模型'), findsNothing);
      expect(find.textContaining('四家匿名通道'), findsOneWidget);
      expect(find.text('一键测试'), findsOneWidget);
      expect(find.text('待检测'), findsOneWidget);
      expect(find.text('Pollinations'), findsOneWidget);
      expect(find.text('LLM7'), findsOneWidget);
    });
  });

  group('v4.0 全网搜索与公益实例', () {
    test('GitHub 搜索结果解析', () {
      final list = ProjectSearch.parse('''
{"items":[
 {"full_name":"a/b","description":"desc","html_url":"https://github.com/a/b",
  "language":"Python","stargazers_count":6700,"pushed_at":"2026-11-01T00:00:00Z","archived":false},
 {"full_name":"c/d","description":null,"html_url":"https://github.com/c/d",
  "stargazers_count":900,"pushed_at":"2025-01-02T00:00:00Z","archived":true}
]}''');
      expect(list.length, 2);
      expect(list.first.fullName, 'a/b');
      expect(list.first.stars, 6700);
      expect(list.first.metaLine, contains('6.7k'));
      expect(list.last.archived, isTrue);
      expect(list.last.metaLine, contains('已归档'));
    });

    test('非法返回体不会抛异常', () {
      expect(ProjectSearch.parse('<html>'), isEmpty);
      expect(ProjectSearch.parse('{"items":[]}'), isEmpty);
      expect(ProjectSearch.parse('[]'), isEmpty);
    });

    test('公益实例必须是固定地址且需要 Key', () {
      final pub = kRelayPresets.where((p) => p.isPublicInstance).toList();
      expect(pub.length, greaterThanOrEqualTo(5));
      for (final p in pub) {
        expect(p.fixedBaseUrl, isNotNull);
        expect(p.fixedBaseUrl!.startsWith('https://'), isTrue);
        expect(p.auth, RelayAuth.required);
        expect(p.deploy, isEmpty);
        expect(p.repoUrl, isNotEmpty);
        // 固定地址不能被扫描框里的主机名覆盖。
        expect(p.urlFor('127.0.0.1'), p.fixedBaseUrl);
      }
    });

    test('免密源覆盖四家以上、含视觉模型', () {
      expect(kFreeEndpoints.length, greaterThanOrEqualTo(10));
      final providers = kFreeEndpoints.map((e) => e.providerLabel).toSet();
      expect(providers.length, greaterThanOrEqualTo(4));
      expect(
          providers, containsAll(['Pollinations', 'OVH AI', 'Kilo', 'LLM7']));
      expect(kFreeEndpoints.any((e) => e.vision), isTrue);
      final ids = kFreeEndpoints.map((e) => e.id).toSet();
      expect(ids.length, kFreeEndpoints.length);
    });

    test('fastest 只挑可用里延迟最低的', () {
      final a = FreeHit(endpoint: kFreeEndpoints[0], ok: true, latencyMs: 900);
      final b = FreeHit(endpoint: kFreeEndpoints[1], ok: true, latencyMs: 120);
      final c = FreeHit(endpoint: kFreeEndpoints[2], ok: false, latencyMs: 50);
      expect(FreePool.fastest([a, b, c])?.latencyMs, 120);
      expect(FreePool.fastest([c]), isNull);
    });
  });

  group('v4.2 语音：朗读与语音输入', () {
    test('TTS 引擎 id 唯一，地址与鉴权自洽', () {
      final ids = kTtsEngines.map((e) => e.id).toSet();
      expect(ids.length, kTtsEngines.length);
      for (final e in kTtsEngines) {
        expect(e.summary.isNotEmpty, isTrue, reason: e.id);
        if (e.followsConnection) {
          expect(e.baseUrl, isEmpty, reason: '${e.id} 跟随连接时不该写死地址');
        }
        if (e.proto != VoiceProto.system &&
            e.proto != VoiceProto.azure &&
            !e.followsConnection) {
          expect(e.baseUrl.startsWith('http'), isTrue, reason: e.id);
        }
        // Azure 的「地址」是区域名，拼接时才变成主机。
        if (e.proto == VoiceProto.azure) {
          expect(e.baseUrl.isNotEmpty, isTrue, reason: e.id);
        }
      }
      expect(ttsEngineById('system')?.proto, VoiceProto.system);
      expect(ttsEngineById('不存在'), isNull);
    });

    test('标着免费/离线的引擎都不要求密钥', () {
      for (final e in kTtsEngines) {
        if (e.badge == '免费' || e.badge == '离线') {
          expect(e.needsKey, isFalse, reason: '${e.id} 标了免费却要 Key');
        }
      }
    });

    test('STT 覆盖系统识别与多家云端', () {
      expect(kSttEngines.any((e) => e.proto == VoiceProto.system), isTrue);
      final cloud =
          kSttEngines.where((e) => e.proto == VoiceProto.openAI).toList();
      expect(cloud.length, greaterThanOrEqualTo(3));
      // 跟随连接的那一项不能写死地址，否则切了连接还是打到旧服务。
      for (final e in kSttEngines.where((e) => e.followsConnection)) {
        expect(e.baseUrl, isEmpty, reason: e.id);
      }
      expect(sttEngineById('whisper-local')?.needsKey, isFalse);
    });

    test('朗读前剥掉 Markdown 标记，不念语法和链接', () {
      const src = '# 标题\n\n这是**重点**，参见[文档](https://a.com/x)。'
          '\n\n```dart\nprint(1);\n```';
      final out = VoiceService.stripMarkdown(src);
      expect(out.contains('#'), isFalse);
      expect(out.contains('**'), isFalse);
      expect(out.contains('https://'), isFalse);
      expect(out.contains('print(1)'), isFalse);
      expect(out.contains('代码块已跳过'), isTrue);
      expect(out.contains('重点'), isTrue);
      expect(out.contains('文档'), isTrue);
    });

    test('长文按标点切段，段长不超标且内容不丢', () {
      final src = List.filled(30, '这是一句话。').join();
      final parts = VoiceService.chunk(src, 60);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(60));
        expect(p.endsWith('。'), isTrue, reason: '切段应落在标点上');
      }
      expect(parts.join(), src);
    });

    test('超长且无标点的文本仍能被切开', () {
      final src = 'a' * 500;
      final parts = VoiceService.chunk(src, 100);
      expect(parts.length, 5);
      for (final p in parts) {
        expect(p.length, 100);
      }
    });

    test('朗读错误码能指出下一步该做什么', () {
      DioException err(int code) => DioException(
            requestOptions:
                RequestOptions(path: '/audio/speech', baseUrl: 'https://x/v1'),
            response: Response(
              requestOptions:
                  RequestOptions(path: '/', baseUrl: 'https://x/v1'),
              statusCode: code,
            ),
          );
      expect(VoiceService.explainTtsError(err(401)), contains('密钥'));
      expect(VoiceService.explainTtsError(err(402)), contains('额度'));
      expect(VoiceService.explainTtsError(err(404)), contains('系统语音'));
      expect(VoiceService.explainTtsError(err(429)), contains('频繁'));
      expect(VoiceService.explainSttError(err(404)), contains('系统识别'));
    });

    test('语音配置能无损往返序列化，密钥不进快照', () {
      final s = AppSettings()
        ..ttsEngineId = 'youdao'
        ..ttsVoice = '英音'
        ..ttsRate = 1.3
        ..autoSpeak = true
        ..sttEngineId = 'groq'
        ..sttAutoStopOnSilence = false
        ..voiceLang = 'en-US'
        ..voiceTtsKey = 'sk-voice-secret';

      final json = s.encode();
      expect(json.contains('sk-voice-secret'), isFalse,
          reason: '语音密钥绝不能写入设置快照');

      final back = AppSettings()
        ..load(jsonDecode(json) as Map<String, dynamic>);
      expect(back.ttsEngineId, 'youdao');
      expect(back.ttsVoice, '英音');
      expect(back.ttsRate, closeTo(1.3, 0.001));
      expect(back.autoSpeak, isTrue);
      expect(back.sttEngineId, 'groq');
      expect(back.sttAutoStopOnSilence, isFalse);
      expect(back.voiceLang, 'en-US');
      // v4.11 起彻底不再有「识别完自动发送」这个开关。
      expect(json.contains('sttAutoSend'), isFalse);
    });

    test('旧配置升级后朗读可用、自动朗读默认关闭', () {
      final s = AppSettings()
        ..load(<String, dynamic>{'baseUrl': 'https://api.openai.com/v1'});
      expect(s.ttsEnabled, isTrue);
      // v4.10 起默认微软 Edge 朗读：免密钥且音色比系统 TTS 自然。
      expect(s.ttsEngineId, 'edge');
      expect(s.autoSpeak, isFalse, reason: '不能替用户决定要不要出声');
      expect(s.sttAutoStopOnSilence, isTrue);
    });

    test('旧配置里的「说完自动发送」升级后失效', () {
      final s = AppSettings()..load(<String, dynamic>{
        'baseUrl': 'https://api.openai.com/v1',
        'sttAutoSend': true,
      });
      // 老用户即使开过自动发送，升级后也只回填输入框，不会把错话发出去。
      expect(s.sttAutoStopOnSilence, isTrue);
      expect(s.encode().contains('sttAutoSend'), isFalse);
    });

    testWidgets('语音面板渲染出朗读与输入两栏', (tester) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);

      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: VoicePanel(dark: false)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('朗读'), findsOneWidget);
      expect(find.text('语音输入'), findsOneWidget);
      expect(find.text('系统语音'), findsOneWidget);
      expect(find.text('系统离线识别'), findsOneWidget);
      expect(find.text('系统在线识别'), findsOneWidget);
      expect(find.text('试听'), findsOneWidget);
      expect(find.text('说完静音自动停止'), findsOneWidget);
      expect(find.text('按住说话'), findsOneWidget);
      expect(find.text('一键测速'), findsOneWidget);
    });
  });

  group('v4.3 Muse 界面与右上角朗读控制', () {
    test('日期标签按上午 / 下午生成', () {
      expect(museDateLabel(DateTime(2026, 7, 12, 15, 30)), '7-12 下午');
      expect(museDateLabel(DateTime(2026, 1, 3, 9, 5)), '1-3 上午');
    });

    test('静音开关可持久化，旧配置升级后默认不静音', () {
      final s = AppSettings();
      expect(s.voiceMuted, isFalse);
      s.voiceMuted = true;
      final back = AppSettings()
        ..load(jsonDecode(s.encode()) as Map<String, dynamic>);
      expect(back.voiceMuted, isTrue);
      final legacy = AppSettings()..load(<String, dynamic>{});
      expect(legacy.voiceMuted, isFalse);
    });

    test('静音时朗读返回明确提示，不会静默失败', () async {
      final st = AppState()..settings = AppSettings();
      st.settings.voiceMuted = true;
      final err = await st.speak('一段回答');
      expect(err, isNotNull);
      expect(err, contains('静音'));
    });

    testWidgets('顶栏渲染形象、状态与单颗朗读按钮', (tester) async {
      final p = Persona(id: 'p_top', name: '牛來', glyph: '牛');
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: MuseTopBar(
              collapse: ValueNotifier<double>(0),
              dark: true,
              persona: p,
              statusLine: '默认连接 · gpt-4o-mini',
              connected: true,
              onMenu: () {},
              onAvatar: () {},
              onStatus: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // v4.9 起名字与模型名并在同一行，省掉一整行高度。
      expect(
        find.textContaining(p.name),
        findsOneWidget,
      );
      expect(find.textContaining('默认连接 · gpt-4o-mini'), findsOneWidget);
      // v4.14：朗读与静音合并成一颗按钮，左右各一个圆钮才真正对称。
      expect(find.byType(MuseVoiceControls), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
      expect(find.byTooltip('朗读上一条回答'), findsOneWidget);
    });

    testWidgets('没设置形象时顶栏只留模型信息，不多一句占位文案', (tester) async {
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: MuseTopBar(
              collapse: ValueNotifier<double>(0),
              dark: true,
              persona: nonePersona(),
              statusLine: 'Kilo · kilo-auto/free',
              connected: true,
              onMenu: () {},
              onAvatar: () {},
              onStatus: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('不使用形象'), findsNothing);
      expect(find.textContaining('Kilo · kilo-auto/free'), findsOneWidget);
    });

    testWidgets('长按朗读按钮可切换静音并持久化到设置', (tester) async {
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(
          home: Scaffold(body: MuseVoiceControls(dark: true)),
        ),
      ));
      await tester.pumpAndSettle();
      // v4.14：静音不再是独立按钮，长按唯一的朗读键切换。
      await tester.longPress(find.byType(MuseVoiceControls));
      await tester.pumpAndSettle();
      expect(st.settings.voiceMuted, isTrue);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('没有回答时点朗读只给提示，不进入准备中', (tester) async {
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: const MaterialApp(
          home: Scaffold(body: MuseVoiceControls(dark: true)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MuseVoiceControls));
      await tester.pump();
      expect(find.text('还没有可以朗读的回答'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('底部导航已移除，主页只留输入台', (tester) async {
      // v4.13：底栏整条删掉，「研究 / 工具」并入左侧抽屉。
      // 这里守住两件事：底栏组件不再存在，抽屉里仍有这两个入口。
      var research = 0;
      var toolbox = 0;
      final key = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: AppState(),
        child: MaterialApp(
          home: Scaffold(
            key: key,
            drawer: WorkspaceDrawer(
              onResearch: () => research++,
              onToolbox: () => toolbox++,
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('工具'), findsOneWidget);
      expect(find.text('深度研究'), findsOneWidget);
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      expect(toolbox, 1);
    });

    testWidgets('空态只留欢迎语与建议胶囊，不写假消息', (tester) async {
      String? starter;
      await tester.pumpWidget(MaterialApp(
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
              onStarter: (s) => starter = s,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 「快速开始」四行大卡会让首屏只剩半截对话，v4.9 起整体移除。
      expect(find.text('快速开始'), findsNothing);
      expect(find.text('连接接口'), findsNothing);
      // 没设置形象：开场白不提名字，也不出现任何占位文案。
      expect(find.textContaining('有什么要处理的，交给我'), findsOneWidget);
      expect(find.textContaining('不使用形象'), findsNothing);
      await tester.tap(find.text('解释一段代码'));
      expect(starter, '解释一段代码');
    });

    testWidgets('Muse 气泡无署名与底部操作行，长按才呼出菜单', (tester) async {
      final st = AppState()..settings = AppSettings();
      final m = ChatMessage(
        id: 'muse_m1',
        role: Role.assistant,
        content: '这是一条回答',
      );
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageCard(
                message: m,
                dark: true,
                muse: true,
                onRegenerate: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('这是一条回答'), findsOneWidget);
      expect(find.byType(MuseBubble), findsOneWidget);
      expect(find.text('复制'), findsNothing);
      expect(find.text('重新生成'), findsNothing);
      await tester.longPress(find.byType(MuseBubble));
      await tester.pumpAndSettle();
      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('朗读这条'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
    });

    testWidgets('输入台常驻深度思考与联网开关，开态可读', (tester) async {
      final st = AppState()..settings = AppSettings();
      Widget wrap() => ChangeNotifierProvider<AppState>.value(
            value: st,
            child: MaterialApp(
              home: Scaffold(
                body: ComposerBar(
                  dark: true,
                  muse: true,
                  convId: 'c_muse',
                  draftSeed: 0,
                  onGallery: () {},
                  onCamera: () {},
                  onFiles: () {},
                ),
              ),
            ),
          );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('随便问点什么'), findsOneWidget);
      // v4.9：开关不再藏在设置页，输入框下面直接可见可点。
      expect(find.text('深度'), findsOneWidget);
      expect(find.text('联网'), findsOneWidget);
      // v4.12：语音只留主键一个入口，独立的小话筒已删除。
      expect(find.text('开始说话'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      await tester.tap(find.text('深度'));
      await tester.pumpAndSettle();
      expect(st.settings.deepThinking, isTrue);
      await tester.tap(find.text('联网'));
      await tester.pumpAndSettle();
      expect(st.settings.webSearch, isTrue);
    });
  });

  group('v4.9 输入台在窄屏下不溢出', () {
    testWidgets('320dp 宽度仍能完整排下工具条', (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerBar(
                dark: true,
                muse: true,
                convId: st.active.id,
                draftSeed: 0,
                onGallery: () {},
                onCamera: () {},
                onFiles: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('开始说话'), findsOneWidget);
      expect(find.text('深度'), findsOneWidget);
    });
  });

  group('v4.4 适配、输入台与本地优先语音', () {
    test('STT 主列表只留开箱可用的通道，需部署的折叠到实验区', () {
      // v4.10 起主列表首位是免密钥在线 Whisper：本地小模型没有标点、
      // 错字多，用户实测不可用，不再作为默认推荐。
      expect(kSttEngines.first.id, 'ovh-whisper');
      expect(kSttEngines.first.needsKey, isFalse);
      expect(kSttEngines.first.zhOptimized, isTrue);
      expect(kSttEngines.any((e) => e.id == 'vosk-cn'), isTrue,
          reason: '离线引擎保留，供没有网络时切换');
      expect(kLocalSttEngines.length, 2);
      expect(kExperimentalSttEngines.length, 2);
      expect(kAllSttEngines.length, kSttEngines.length +
          kExperimentalSttEngines.length);
      for (final e in kAllSttEngines) {
        expect(e.speed, inInclusiveRange(1, 3), reason: e.id);
        expect(e.accuracy, inInclusiveRange(1, 3), reason: e.id);
        expect(e.tags, isNotEmpty, reason: e.id);
      }
      expect(sttEngineById('vosk-cn')!.tags, contains('本地'));
      expect(kExperimentalSttEngines.first.tags, contains('需部署'));
      expect(sttEngineById('groq')?.speed, 3);
      expect(sttEngineById('siliconflow')?.zhOptimized, isTrue);
      expect(sttEngineById('whisper-local')?.offline, isTrue);
      expect(sttEngineById('不存在的引擎'), isNull);
    });

    test('语音默认走系统在线识别，旧配置一次性迁移', () {
      final s = AppSettings();
      expect(s.holdToTalk, isTrue);
      // 离线优先是「一个都用不了」的根因，默认必须关闭。
      expect(s.sttPreferOffline, isFalse);
      expect(s.sttAutoFallback, isTrue);
      expect(s.sttEngineId, 'ovh-whisper');
      expect(s.sttSilenceMs, 700);
      s.holdToTalk = false;
      s.sttSilenceMs = 99999;
      final raw = jsonDecode(s.encode()) as Map<String, dynamic>;
      expect(raw['holdToTalk'], isFalse);
      expect(raw['sttMigratedV47'], isTrue);
      expect(raw['sttMigratedV48'], isTrue);
      final back = AppSettings()..load(raw);
      expect(back.holdToTalk, isFalse);
      expect(back.sttSilenceMs, lessThanOrEqualTo(3000));
      // 老配置没有这些字段时保持「按住说话 + 在线优先」的新默认。
      final legacy = AppSettings()..load(<String, dynamic>{});
      expect(legacy.holdToTalk, isTrue);
      expect(legacy.sttPreferOffline, isFalse);
      expect(legacy.sttAutoFallback, isTrue);
      expect(legacy.sttSilenceMs, 700);
      expect(legacy.sttEngineId, 'ovh-whisper');
      // 旧版写死的离线引擎升级后回到在线；用户之后显式选回离线则保留。
      final old = AppSettings()
        ..load(<String, dynamic>{
          'sttEngineId': 'system-offline',
          'sttPreferOffline': true,
        });
      // v4.10 再把离线默认换成免密钥在线 Whisper（本地小模型不准）。
      expect(old.sttEngineId, 'ovh-whisper');
      expect(old.sttPreferOffline, isTrue);
      final mine = AppSettings()
        ..load(<String, dynamic>{
          'sttEngineId': 'system-offline',
          'sttMigratedV48': true,
          'voiceMigratedV410': true,
        });
      expect(mine.sttEngineId, 'system-offline');
    });

    test('没有原生通道时能力探测返回不可用，不让设置页报错', () async {
      final caps = await VoiceService.instance.capabilities();
      expect(caps['available'], isFalse);
      expect(caps['onDevice'], isFalse);
    });

    testWidgets('按住说话浮层渲染波形、状态与实时转写文字', (tester) async {
      final level = ValueNotifier<double>(0.6);
      addTearDown(level.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MuseHoldToTalk(
            dark: true,
            cancelling: false,
            offline: true,
            partial: '帮我写一段大纲',
            level: level,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('本地识别中'), findsOneWidget);
      expect(find.text('松手完成 · 上滑取消'), findsOneWidget);
      expect(find.text('帮我写一段大纲'), findsOneWidget);
      expect(find.byType(MuseWaveform), findsOneWidget);
    });

    testWidgets('上滑取消时浮层切换到红色提示', (tester) async {
      final level = ValueNotifier<double>(0.0);
      addTearDown(level.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MuseHoldToTalk(
            dark: false,
            cancelling: true,
            offline: false,
            partial: '这句话不该显示',
            level: level,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('松开取消'), findsOneWidget);
      expect(find.text('手指移回来可继续'), findsOneWidget);
      expect(find.text('这句话不该显示'), findsNothing);
    });

    testWidgets('输入文字后主键从语音键切成发送键', (tester) async {
      final st = AppState()..settings = AppSettings();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: ComposerBar(
              dark: true,
              muse: true,
              convId: st.active.id,
              draftSeed: 0,
              onGallery: () {},
              onCamera: () {},
              onFiles: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('开始说话'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '写一首诗');
      await tester.pumpAndSettle();
      expect(find.text('发送'), findsOneWidget);
      expect(find.text('开始说话'), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(st.draftFor(st.active.id), '写一首诗');
    });

    testWidgets('语言选择器可搜索并回传代码', (tester) async {
      String? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showLangPicker(
                    ctx,
                    dark: false,
                    title: '对话语言',
                    items: [
                      for (final l in kReplyLangs)
                        LangItem(l.code, l.label, l.native),
                    ],
                    selected: 'zh-Hans',
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      // 首屏只构建可见行，长列表要靠搜索定位，所以直接搜「冰岛」。
      await tester.enterText(find.byType(TextField), '冰岛');
      await tester.pumpAndSettle();
      expect(find.text('冰岛语'), findsOneWidget);
      await tester.tap(find.text('冰岛语'));
      await tester.pumpAndSettle();
      expect(picked, 'is');
    });

    testWidgets('点麦克风打开语音面板，出错时给出重试与提示', (tester) async {
      final st = AppState()..settings = AppSettings();
      // 这条用例验证的是「系统识别启动失败」的提示，固定走系统引擎；
      // 内置离线引擎的缺模型分支由单独的用例覆盖。
      st.settings.sttEngineId = 'system';
      // 测试环境没有原生实现：把通道 mock 成启动失败，验证错误路径。
      const ch = MethodChannel('aigent/voice');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ch,
        (call) async => switch (call.method) {
          'stt.start' => false,
          'stt.available' => false,
          _ => null,
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null));
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: ComposerBar(
              dark: true,
              muse: true,
              convId: st.active.id,
              draftSeed: 0,
              onGallery: () {},
              onCamera: () {},
              onFiles: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // v4.12：唯一语音入口是「开始说话」主键，独立小话筒已删除。
      // 测试环境没有原生通道：面板应打开并进入错误态，而不是崩溃。
      await tester.tap(find.text('开始说话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('出现问题'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      // v4.11：语音面板只负责「把文字放进输入框」，不再替用户发送。
      expect(find.text('填入输入框'), findsOneWidget);
      expect(find.text('发送'), findsNothing);
      // 取消后面板关闭，输入框草稿保持原样。
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('出现问题'), findsNothing);
      expect(st.draftFor(st.active.id), '');
    });
  });

  group('v4.11 输入台快捷换模型', () {
    Widget wrap(AppState st) => ChangeNotifierProvider<AppState>.value(
          value: st,
          child: MaterialApp(
            home: Scaffold(
              body: ComposerBar(
                dark: false,
                muse: true,
                convId: st.active.id,
                draftSeed: 0,
                onGallery: () {},
                onCamera: () {},
                onFiles: () {},
              ),
            ),
          ),
        );

    testWidgets('输入台常驻当前模型，点开就能直接选常用模型', (tester) async {
      final st = AppState()..settings = AppSettings();
      st.settings.cachedModels = [
        'gpt-4o-mini',
        'claude-3-5-sonnet',
        'deepseek-chat',
      ];
      await tester.pumpWidget(wrap(st));
      await tester.pumpAndSettle();

      // 不用滚到页面顶部：输入台里就有当前模型与搜索入口。
      expect(find.text('gpt-4o-mini'), findsOneWidget);
      expect(find.text('搜索模型'), findsOneWidget);

      await tester.tap(find.text('搜索模型'));
      await tester.pumpAndSettle();
      // v4.13：弹层只剩「标题 + 单行模型列表」，管理动作都挪去设置页。
      expect(find.text('选择模型'), findsOneWidget);
      expect(find.text('claude-3-5-sonnet'), findsWidgets);
      expect(find.text('检测当前模型'), findsNothing);
      expect(find.text('刷新列表'), findsNothing);
      expect(find.text('接口设置'), findsNothing);

      await tester.tap(find.text('claude-3-5-sonnet').first);
      await tester.pumpAndSettle();
      expect(st.settings.model, 'claude-3-5-sonnet');
      expect(find.text('选择模型'), findsNothing);
    });

    testWidgets('特大字号 + 320dp 窄屏：输入台不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final st = AppState()..settings = AppSettings();
      st.settings.fontScale = 1.25;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: wrap(st),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 字号放大后语音主键仍在，不会被挤掉。
      expect(find.text('开始说话'), findsOneWidget);
    });

    testWidgets('搜索框能跨系列锁定模型，无命中可按 ID 使用', (tester) async {
      final st = AppState()..settings = AppSettings();
      st.settings.cachedModels = ['gpt-4o-mini', 'deepseek-chat'];
      await tester.pumpWidget(wrap(st));
      await tester.pumpAndSettle();

      await tester.tap(find.text('gpt-4o-mini'));
      await tester.pumpAndSettle();
      // v4.13：搜索收成标题栏里的放大镜，点开才展开输入框。
      await tester.tap(find.byTooltip('搜索模型'));
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').contains('claude'),
      );
      expect(search, findsOneWidget);

      await tester.enterText(search, 'deepseek');
      await tester.pumpAndSettle();
      expect(find.text('deepseek-chat'), findsWidgets);
      await tester.tap(find.text('deepseek-chat').last);
      await tester.pumpAndSettle();
      expect(st.settings.model, 'deepseek-chat');

      // 手动指定一个列表里没有的 ID 也能直接生效。
      await tester.tap(find.text('搜索模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索模型'));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'my-custom-model');
      await tester.pumpAndSettle();
      expect(find.textContaining('按「my-custom-model」使用'), findsOneWidget);
      await tester.tap(find.textContaining('按「my-custom-model」使用'));
      await tester.pumpAndSettle();
      expect(st.settings.model, 'my-custom-model');
    });
  });
}

