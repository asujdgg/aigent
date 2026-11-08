import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/model_brand.dart';
import 'package:ai_agent_app/services/model_probe.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/model_picker_sheet.dart';

void main() {
  group('模型品牌识别', () {
    test('常见模型 ID 都落到对应官方品牌', () {
      const cases = <String, String>{
        'gpt-4o': 'openai',
        'openai/gpt-4o-mini': 'openai',
        'o1-preview': 'openai',
        'claude-3-5-sonnet-20241022': 'anthropic',
        'anthropic/claude-3-opus': 'anthropic',
        'gemini-2.0-flash': 'google',
        'google/gemini-1.5-pro': 'google',
        'gemma-2-9b': 'google',
        'deepseek-chat': 'deepseek',
        'deepseek-ai/DeepSeek-V3': 'deepseek',
        'Qwen/Qwen2.5-72B-Instruct': 'qwen',
        'qwq-32b': 'qwen',
        'glm-4-plus': 'zhipu',
        'chatglm3-6b': 'zhipu',
        'doubao-1.5-pro': 'doubao',
        'kimi-k2': 'kimi',
        'moonshot-v1-8k': 'kimi',
        'mistral-large': 'mistral',
        'meta-llama/Llama-3.3-70B': 'meta',
        'grok-2': 'grok',
        'hunyuan-turbo': 'hunyuan',
        'ernie-4.0': 'baidu',
        'command-r-plus': 'cohere',
        'phi-3-medium': 'microsoft',
        'sonar-reasoning': 'perplexity',
        'openrouter/auto': 'openrouter',
        'siliconflow/my-model': 'siliconflow',
        'my-private-model': 'generic',
      };
      for (final e in cases.entries) {
        expect(resolveModelBrand(e.key).key, e.value,
            reason: '${e.key} 应识别为 ${e.value}');
      }
    });

    test('模型本身的品牌优先于承载它的网关', () {
      // groq 上跑的是 Meta 的 Llama，图标应该用 Meta 官方标记。
      expect(resolveModelBrand('groq/llama-3.3-70b').key, 'meta');
      expect(resolveModelBrand('openrouter/openai/gpt-4o').key, 'openai');
      expect(resolveModelBrand('siliconflow/Qwen/Qwen2.5-72B').key, 'qwen');
    });

    test('认不出来时统一落 generic，不留下空图标或黑白图标', () {
      final b = resolveModelBrand('some-random-id-2026');
      expect(b.key, 'generic');
      expect(b.label.isNotEmpty, isTrue);
      expect(b.asset, 'assets/brand_models/generic.png');
      expect(resolveModelBrand('').key, 'generic');
    });

    test('每个品牌都真的有 256px 高清 PNG 资源', () {
      const pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
      for (final key in kBrandKeys) {
        final f = File('assets/brand_models/$key.png');
        expect(f.existsSync(), isTrue, reason: '缺少 $key.png');
        final bytes = f.readAsBytesSync();
        expect(bytes.length, greaterThan(200), reason: '$key.png 太小');
        expect(bytes.sublist(0, 8), pngHeader, reason: '$key.png 不是 PNG');
      }
    });

    test('规则表不会返回没有资源的品牌 key', () {
      for (final id in [
        'gpt-4o',
        'claude-3-5-sonnet',
        'gemini-2.0-flash',
        'deepseek-chat',
        'Qwen2.5-72B',
        'llama-3.3',
        'my-model',
      ]) {
        expect(kBrandKeys.contains(resolveModelBrand(id).key), isTrue);
      }
    });
  });

  group('模型可用性检测', () {
    test('结果标题与耗时可读', () {
      const ok = ModelProbe(ok: true, ms: 812, detail: '响应正常');
      expect(ok.headline, '当前模型可用');
      expect(ok.timing, '812ms');
      const bad = ModelProbe(ok: false, ms: 0, detail: '还没有选择模型');
      expect(bad.headline, '当前模型不可用');
    });

    test('常见网关错误翻成中文原因', () {
      expect(describeProbeError(TimeoutException('x')), contains('超时'));
      expect(describeProbeError(StateError('401 Unauthorized')),
          contains('鉴权失败'));
      expect(describeProbeError(StateError('429 Too Many Requests')),
          contains('限流'));
      expect(describeProbeError(StateError('404 Not Found')), contains('404'));
      expect(describeProbeError(StateError('SocketException: failed')),
          contains('连不上服务器'));
    });

    test('回复摘要截断且不留换行', () {
      expect(probeReplyPreview('  好\n'), '好');
      expect(
          probeReplyPreview(
              '这是一段明显超过二十四字的很长很长很长很长很长很长很长的回复内容'),
          endsWith('…'));
      expect(probeReplyPreview('   '), isEmpty);
    });
  });

  group('v4.12 简洁图标列表', () {
    testWidgets('模型弹层只剩单行图标列表，管理动作不在主页', (tester) async {
      final st = AppState()..settings = AppSettings();
      st.settings.cachedModels = [
        'gpt-4o',
        'claude-3-5-sonnet',
        'deepseek-chat',
      ];
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: ModelPickerSheet(dark: false, st: st),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('选择模型'), findsOneWidget);
      // 三行各一个官方图标（BrandIcon 内部是 Image.asset）。
      expect(find.byType(Image), findsNWidgets(3));
      // 简洁化后不再有 chips / 系列速查 / 供应商小字 / 底部操作栏。
      expect(find.text('按系列速查'), findsNothing);
      expect(find.text('常用模型'), findsNothing);
      expect(find.text('Anthropic Claude'), findsNothing);
      expect(find.text('检测当前模型'), findsNothing);
      expect(find.text('刷新列表'), findsNothing);
      expect(find.text('接口设置'), findsNothing);
    });
  });
}
