import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/services/edge_tts.dart';
import 'package:ai_agent_app/services/voice_catalog.dart';
import 'package:ai_agent_app/services/voice_service.dart';

void main() {
  group('微软朗读签名', () {
    test('Sec-MS-GEC 与官方库逐字节一致', () {
      // 参考值来自 edge-tts 7.3.1 的 generate_sec_ms_gec_v2(ts)。
      final a = EdgeTts.secMsGec(
          DateTime.fromMillisecondsSinceEpoch(1794096000 * 1000, isUtc: true));
      final b = EdgeTts.secMsGec(
          DateTime.fromMillisecondsSinceEpoch(1794100000 * 1000, isUtc: true));
      expect(a,
          'ABEF6609F439255F-2DE289BF7F823B723C1396A0D51795C45A535CBEB4A0BF4A56A95A8FF05093A4');
      expect(b,
          '1B0E3DA421FF693B-F25DE5736BD0341A2DD33F1CD1F2CAAC9620CC442EFD63BE782DBF19E414D450');
    });

    test('同一 5 分钟窗口内签名稳定', () {
      final t1 = DateTime.fromMillisecondsSinceEpoch(1794096001 * 1000);
      final t2 = DateTime.fromMillisecondsSinceEpoch(1794096299 * 1000);
      expect(EdgeTts.secMsGec(t1), EdgeTts.secMsGec(t2));
    });
  });

  group('转写收尾', () {
    test('汉字之间的空格被去掉，并补句号', () {
      expect(polishTranscript('你 好 世 界'), '你好世界。');
      expect(polishTranscript('打开 设置 页面'), '打开设置页面。');
    });

    test('疑问句补问号', () {
      expect(polishTranscript('今天天气怎么样'), '今天天气怎么样？');
      expect(polishTranscript('你吃饭了吗'), '你吃饭了吗？');
    });

    test('已有标点不重复添加', () {
      expect(polishTranscript('好的。'), '好的。');
      expect(polishTranscript('真的吗？'), '真的吗？');
    });

    test('尾部复读被收敛', () {
      // 「这是测试」后面跟着一串幻觉复读，只留一个字。
      expect(polishTranscript('这是测试试试试试试试试试'), '这是测试。');
    });

    test('英文首字母大写', () {
      expect(polishTranscript('hello world'), 'Hello world.');
    });

    test('空串原样返回', () {
      expect(polishTranscript('   '), '');
    });
  });

  group('引擎清单', () {
    test('默认朗读是免密钥的微软通道', () {
      final e = ttsEngineById('edge');
      expect(e, isNotNull);
      expect(e!.proto, VoiceProto.edge);
      expect(e.needsKey, isFalse);
      expect(e.voiceId('晓晓'), 'zh-CN-XiaoxiaoNeural');
      expect(e.voiceId('云希'), 'zh-CN-YunxiNeural');
    });

    test('默认识别是免密钥在线 Whisper', () {
      final e = sttEngineById('ovh-whisper');
      expect(e, isNotNull);
      expect(e!.needsKey, isFalse);
      expect(e.model, 'whisper-large-v3-turbo');
      expect(e.zhOptimized, isTrue);
      expect(kSttEngines.first.id, 'ovh-whisper');
    });

    test('每个朗读引擎都有可用音色或明确需要填写', () {
      for (final e in kTtsEngines) {
        if (e.voices.isNotEmpty) {
          expect(e.voiceId(e.voices.first), isNotEmpty, reason: e.id);
        }
        if (e.voiceIds.isNotEmpty) {
          expect(e.voiceIds.length, e.voices.length,
              reason: '${e.id} 音色名与取值数量必须一致');
        }
      }
    });

    test('引擎 id 全局唯一', () {
      final tts = kTtsEngines.map((e) => e.id).toSet();
      final stt = kAllSttEngines.map((e) => e.id).toSet();
      expect(tts.length, kTtsEngines.length);
      expect(stt.length, kAllSttEngines.length);
    });
  });
}
