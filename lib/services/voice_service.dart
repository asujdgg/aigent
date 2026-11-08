import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'edge_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'speech_model.dart';
import 'voice_catalog.dart';

/// 语音服务：一个入口，多种协议。
///
/// 底层全部走 MainActivity 暴露的原生通道（TextToSpeech / MediaPlayer /
/// SpeechRecognizer / MediaRecorder），不依赖任何第三方 Android 插件——
/// 那些插件各自锁定 AGP 版本，会把 release 构建拖垮。
///
/// 设计取舍：
/// - **永远有兜底**：云端通道失败（401 / 404 / 超时 / 额度用尽）时自动回落
///   到系统朗读，用户至少能听见内容。
/// - **长文分段**：免费 URL 通道对长度敏感，按标点切成 240 字以内再顺序播放。
/// - **返回文案而不是抛异常**：调用方直接拿去展示。
/// 转写收尾：本地模型爱把汉字用空格隔开、又完全不吐标点；
/// 云端 whisper 偶尔在尾部复读同一两个字。这里统一收拾干净。
String polishTranscript(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;

  // 1) 汉字之间不该有空格（Vosk 中文的输出形态）。
  var prev = '';
  while (prev != t) {
    prev = t;
    t = t.replaceAllMapped(
      RegExp(r'([\u4e00-\u9fa5])[ \t]+([\u4e00-\u9fa5])'),
      (m) => '${m[1]}${m[2]}',
    );
  }

  // 2) 尾部复读："试试试试试试试" → "试"，只收拾 1~2 字的病态重复。
  t = t.replaceAllMapped(
    RegExp(r'([\u4e00-\u9fa5]{1,2})\1{4,}'),
    (m) => m[1]!,
  );

  // 3) 英文句首大写。
  if (RegExp(r'^[a-z]').hasMatch(t)) {
    t = t[0].toUpperCase() + t.substring(1);
  }

  // 4) 补句末标点。
  const enders = '。！？.!?…~～';
  if (!enders.contains(t[t.length - 1])) {
    final question = RegExp(
      r'(吗|呢|么|嘛|什么|怎么|怎么样|如何|为什么|哪[儿里个]?|谁|多少|'
      r'几[个点]?|多久|多远|多大|多长|是不是|有没有|能不能|可不可以|对不对)$',
    );
    final cjk = RegExp(r'[\u4e00-\u9fa5]').hasMatch(t);
    t += question.hasMatch(t) ? (cjk ? '？' : '?') : (cjk ? '。' : '.');
  }
  return t;
}

class VoiceService {
  VoiceService._internal();
  static final VoiceService instance = VoiceService._internal();

  static const MethodChannel _ch = MethodChannel('aigent/voice');
  static const EventChannel _ev = EventChannel('aigent/voice_events');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 90),
  ));

  final ValueNotifier<bool> speaking = ValueNotifier(false);
  final ValueNotifier<bool> listening = ValueNotifier(false);
  final ValueNotifier<bool> sttAvailable = ValueNotifier(true);

  /// 实时音量 0~1，驱动「按住说话」浮层的波形。
  final ValueNotifier<double> rms = ValueNotifier(0);

  /// 当前这次识别是否真的跑在端侧（用于浮层显示「本地识别中」）。
  final ValueNotifier<bool> offlineActive = ValueNotifier(false);

  StreamSubscription<dynamic>? _evSub;
  Completer<String?>? _speakDone;

  void Function(String text, bool isFinal)? _sttHandler;
  void Function()? _sttSpeechEnd;
  void Function(String message)? _sttNotice;
  String _sttLang = 'zh-CN';
  int _sttSilenceMs = 700;
  String _sttEngine = 'system';
  bool _fallbackArmed = false;
  Map<String, dynamic>? _capsCache;

  String _lastError = '';
  String get lastError => _lastError;

  String _recPath = '';

  // ------------------------------------------------------------ 事件

  void _ensureSubscribed() {
    if (_evSub != null) return;
    _evSub = _ev.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final m = Map<String, dynamic>.from(raw);
    final type = (m['type'] ?? '').toString();
    switch (type) {
      case 'tts_start':
        speaking.value = true;
        break;
      case 'tts_done':
        speaking.value = false;
        _finishSpeak(null);
        break;
      case 'tts_error':
        speaking.value = false;
        _finishSpeak((m['message'] ?? '朗读失败').toString());
        break;
      case 'player_start':
        speaking.value = true;
        break;
      case 'player_done':
        speaking.value = false;
        _finishSpeak(null);
        break;
      case 'player_error':
        speaking.value = false;
        _finishSpeak((m['message'] ?? '音频无法播放').toString());
        break;
      case 'stt_start':
        listening.value = true;
        offlineActive.value = m['offline'] == true;
        break;
      case 'stt_speech_begin':
        break;
      case 'stt_speech_end':
        _sttSpeechEnd?.call();
        break;
      case 'stt_rms':
      case 'rec_rms':
        rms.value = ((m['level'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
        break;
      case 'stt_partial':
        _sttHandler?.call((m['text'] ?? '').toString(), false);
        break;
      case 'stt_final':
        listening.value = false;
        rms.value = 0;
        _sttHandler?.call(
            polishTranscript((m['text'] ?? '').toString()), true);
        break;
      case 'stt_no_result':
        listening.value = false;
        rms.value = 0;
        _sttHandler?.call('', true);
        break;
      case 'stt_error':
        _lastError = friendlySttError((m['message'] ?? '识别失败').toString());
        // 离线引擎不可用（最常见是没下载中文离线包）时自动切在线，
        // 别让用户以为语音功能坏了；只回落一次，避免无限重启。
        if (_fallbackArmed && m['offline'] == true) {
          _fallbackArmed = false;
          _sttNotice?.call('离线语音包不可用，已切到在线识别');
          unawaited(_restartOnline());
          return;
        }
        listening.value = false;
        rms.value = 0;
        _sttHandler?.call('', true);
        break;
    }
  }

  Future<void> _restartOnline() async {
    await Future.delayed(const Duration(milliseconds: 160));
    try {
      await _ch.invokeMethod<bool>('stt.start', {
        'lang': _sttLang,
        'preferOffline': false,
        'silenceMs': _sttSilenceMs,
      });
    } catch (_) {
      listening.value = false;
      _sttHandler?.call('', true);
    }
  }

  void _finishSpeak(String? error) {
    final c = _speakDone;
    _speakDone = null;
    if (c != null && !c.isCompleted) c.complete(error);
  }

  // ------------------------------------------------------------ TTS

  /// 每轮朗读的代号。用户点「取消」后，正在合成的音频即使回来也不再播放——
  /// 取消两秒后突然出声，比慢更让人意外。
  int _speakGen = 0;

  /// 首段音频缓存：停止后重听同一段不必再走一次网络合成。
  /// 只收 140 字以内的小片段，总量压到 4 MB，超了就丢最早的一条。
  final Map<String, Uint8List> _ttsCache = {};
  int _ttsCacheBytes = 0;
  static const int _ttsCacheMax = 4 * 1024 * 1024;

  /// 朗读。返回 null 表示已播完（或被取消），否则是给用户看的错误文案。
  Future<String?> speak({
    required String text,
    required TtsEngine engine,
    String voice = '',
    double rate = 1.0,
    String lang = 'zh-CN',
    String baseUrl = '',
    String apiKey = '',
    String model = '',
  }) async {
    final clean = stripMarkdown(text);
    if (clean.trim().isEmpty) return '没有可朗读的内容';
    _ensureSubscribed();
    // stop() 会递增代号，让上一轮还在合成的音频作废；之后才取本轮代号。
    await stop();
    final gen = ++_speakGen;

    // 界面上显示「晓晓」，接口要的是 zh-CN-XiaoxiaoNeural。
    final v = engine.voiceId(voice);
    switch (engine.proto) {
      case VoiceProto.system:
        return _speakSystem(clean, lang, rate);
      case VoiceProto.urlQuery:
        return _speakUrl(engine, clean, v, lang);
      case VoiceProto.openAI:
        return _speakOpenAi(clean, v, rate, baseUrl, apiKey, model);
      case VoiceProto.elevenLabs:
        return _speakEleven(clean, v, baseUrl, apiKey);
      case VoiceProto.edge:
        return _speakEdge(clean, v, rate, gen);
      case VoiceProto.fish:
        return _speakFish(clean, v, baseUrl, apiKey);
      case VoiceProto.azure:
        return _speakAzure(clean, v, baseUrl, apiKey);
    }
  }

  Future<String?> _speakSystem(String text, String lang, double rate) async {
    final done = Completer<String?>();
    _speakDone = done;
    try {
      await _ch.invokeMethod<bool>('tts.speak', {
        'text': text,
        'lang': lang,
        'rate': rate,
      });
    } on PlatformException catch (e) {
      _speakDone = null;
      return '系统语音不可用：${e.message ?? ''}';
    }
    return done.future.timeout(const Duration(seconds: 180), onTimeout: () {
      _speakDone = null;
      return null;
    });
  }

  Future<String?> _speakUrl(
      TtsEngine engine, String text, String voice, String lang) async {
    final urls = <String>[];
    for (final part in chunk(text, 240)) {
      final u = _urlFor(engine, part, voice, lang);
      if (u == null) return '该引擎缺少必要参数';
      urls.add(u.toString());
    }
    if (urls.isEmpty) return '没有可朗读的内容';

    for (var i = 0; i < urls.length; i++) {
      final err = await _playUrl(urls[i]);
      if (err != null) {
        if (i == 0) {
          // 第一段就播不出来，说明通道不可用：换系统语音，别让用户干等。
          final fb = await _speakSystem(text, lang, 1.0);
          return fb == null ? null : '${engine.name} 不可用，已改用系统语音';
        }
        return null;
      }
    }
    return null;
  }

  Uri? _urlFor(TtsEngine engine, String text, String voice, String lang) {
    final t = Uri.encodeComponent(text);
    switch (engine.id) {
      case 'youdao':
        // type: 1 英式 / 2 美式（中文同样走 2）。
        final type = voice == '英音' ? 1 : 2;
        return Uri.parse('${engine.baseUrl}?audio=$t&type=$type');
      case 'baidu':
        final lan = lang.toLowerCase().startsWith('zh') ? 'zh' : 'en';
        return Uri.parse('${engine.baseUrl}?lan=$lan&text=$t&spd=3&source=web');
      case 'google':
        final tl = lang.toLowerCase().startsWith('zh') ? 'zh-CN' : 'en';
        return Uri.parse('${engine.baseUrl}?ie=UTF-8&client=tw-ob&tl=$tl'
            '&q=$t');
      case 'streamelements':
        final v = voice.isEmpty ? 'Brian' : Uri.encodeComponent(voice);
        return Uri.parse('${engine.baseUrl}?voice=$v&text=$t');
      default:
        return null;
    }
  }

  Future<String?> _speakOpenAi(String text, String voice, double rate,
      String baseUrl, String apiKey, String model) async {
    final base = _trimSlash(baseUrl);
    if (base.isEmpty) return '未配置接口地址';
    try {
      final resp = await _dio.post<List<int>>(
        '$base/audio/speech',
        data: {
          'model': model.trim().isEmpty ? 'tts-1' : model.trim(),
          'input': text,
          'voice': voice.trim().isEmpty ? 'alloy' : voice.trim(),
          'response_format': 'mp3',
          'speed': rate.clamp(0.5, 2.0),
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Content-Type': 'application/json',
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return '服务端没有返回音频';
      final path = await _writeTemp(bytes, 'mp3');
      if (path == null) return '音频写入失败';
      final err = await _playFile(path);
      _deleteQuietly(path);
      return err;
    } on DioException catch (e) {
      return explainTtsError(e);
    } catch (e) {
      return '合成失败：${_short(e)}';
    }
  }

  /// 微软 Edge 朗读：WebSocket 合成，返回 mp3。
  /// 通道一旦失败就整段回落系统语音，避免念到一半没声音。
  /// 探测朗读通道是否真的能用（不播放，只合成一小段）。
  /// 返回「可用 · 1.2s」这类短句；失败返回原因。
  Future<String> probeTts({
    required TtsEngine engine,
    String voice = '',
    String baseUrl = '',
    String apiKey = '',
    String model = '',
    double rate = 1.0,
  }) async {
    final v = engine.voiceId(voice);
    final sw = Stopwatch()..start();
    String say(bool ok, String detail) =>
        '${ok ? '可用' : '不可用'} · ${sw.elapsedMilliseconds}ms · $detail';

    switch (engine.proto) {
      case VoiceProto.system:
        return '可用 · 本机系统引擎，无需测速';
      case VoiceProto.edge:
        try {
          final bytes = await EdgeTts.synthesize(
            text: '你好',
            voice: v.isEmpty ? 'zh-CN-XiaoxiaoNeural' : v,
            rate: rate,
            timeout: const Duration(seconds: 15),
          );
          return say(bytes.length > 1000, '微软通道');
        } catch (e) {
          return '不可用 · ${e is EdgeTtsException ? e.message : e}';
        }
      case VoiceProto.urlQuery:
        final u = _urlFor(engine, '你好', v, 'zh-CN');
        if (u == null) return '不可用 · 该引擎缺少参数';
        try {
          final r = await _dio.get<List<int>>(
            u.toString(),
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'User-Agent': 'Mozilla/5.0'},
            ),
          );
          final n = r.data?.length ?? 0;
          return say(n > 500, '$n 字节');
        } on DioException catch (e) {
          return '不可用 · ${explainTtsError(e)}';
        }
      case VoiceProto.openAI:
        try {
          final base = _trimSlash(baseUrl);
          if (base.isEmpty) return '不可用 · 未填接口地址';
          final r = await _dio.post<List<int>>(
            '$base/audio/speech',
            data: {
              'model': model.trim().isEmpty ? 'tts-1' : model.trim(),
              'input': '你好',
              'voice': v.trim().isEmpty ? 'alloy' : v.trim(),
              'response_format': 'mp3',
            },
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'Content-Type': 'application/json',
                if (apiKey.trim().isNotEmpty)
                  'Authorization': 'Bearer ${apiKey.trim()}',
              },
            ),
          );
          final n = r.data?.length ?? 0;
          return say(n > 500, '$n 字节');
        } on DioException catch (e) {
          return '不可用 · ${explainTtsError(e)}';
        }
      case VoiceProto.elevenLabs:
        if (apiKey.trim().isEmpty) return '不可用 · 需要填 API Key';
        try {
          final base = _trimSlash(baseUrl).isEmpty
              ? 'https://api.elevenlabs.io'
              : _trimSlash(baseUrl);
          final id = _elevenVoices[v] ?? _elevenVoices['Rachel']!;
          final r = await _dio.post<List<int>>(
            '$base/v1/text-to-speech/$id',
            data: {'text': '你好', 'model_id': 'eleven_multilingual_v2'},
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'xi-api-key': apiKey.trim(),
                'Accept': 'audio/mpeg',
              },
            ),
          );
          return say((r.data?.length ?? 0) > 500, 'ElevenLabs');
        } on DioException catch (e) {
          return '不可用 · ${explainTtsError(e)}';
        }
      case VoiceProto.fish:
        if (apiKey.trim().isEmpty) return '不可用 · 需要填 API Key';
        try {
          final base = _trimSlash(baseUrl).isEmpty
              ? 'https://api.fish.audio'
              : _trimSlash(baseUrl);
          final r = await _dio.post<List<int>>(
            '$base/v1/tts',
            data: {
              'text': '你好',
              'format': 'mp3',
              if (v.trim().isNotEmpty) 'reference_id': v.trim(),
            },
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'Authorization': 'Bearer ${apiKey.trim()}',
                'Content-Type': 'application/json',
              },
            ),
          );
          return say((r.data?.length ?? 0) > 500, 'Fish Audio');
        } on DioException catch (e) {
          return '不可用 · ${explainTtsError(e)}';
        }
      case VoiceProto.azure:
        if (apiKey.trim().isEmpty) return '不可用 · 需要填订阅密钥';
        try {
          final raw = baseUrl.trim().isEmpty ? 'eastasia' : baseUrl.trim();
          final base = raw.startsWith('http')
              ? _trimSlash(raw)
              : 'https://$raw.tts.speech.microsoft.com';
          final r = await _dio.post<List<int>>(
            '$base/cognitiveservices/v1',
            data: "<speak version='1.0' xml:lang='zh-CN'>"
                "<voice name='${v.isEmpty ? 'zh-CN-XiaoxiaoNeural' : v}'>你好"
                '</voice></speak>',
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'Ocp-Apim-Subscription-Key': apiKey.trim(),
                'Content-Type': 'application/ssml+xml',
                'X-Microsoft-OutputFormat':
                    'audio-24khz-48kbitrate-mono-mp3',
              },
            ),
          );
          return say((r.data?.length ?? 0) > 500, 'Azure');
        } on DioException catch (e) {
          return '不可用 · ${explainTtsError(e)}';
        }
    }
  }

  /// 微软 Edge 朗读：WebSocket 合成，返回 mp3。
  ///
  /// v4.14：首段缩到 140 字，且**下一段在播放当前段时就已经开合成**。
  /// 原来一次合成 300 字才出声，长回答点下去要干等两三秒，看起来像按钮坏了；
  /// 现在首段合成量只有一半，段与段之间也不再出现「念完一句停一下」。
  Future<String?> _speakEdge(
      String text, String voice, double rate, int gen) async {
    final v = voice.trim().isEmpty ? 'zh-CN-XiaoxiaoNeural' : voice.trim();
    final parts = chunk(text, 140);
    if (parts.isEmpty) return '没有可朗读的内容';

    Future<Uint8List> synth(String s) async {
      final key = '$v|${rate.toStringAsFixed(2)}|$s';
      final hit = _ttsCache[key];
      if (hit != null) return hit;
      final bytes = await EdgeTts.synthesize(text: s, voice: v, rate: rate);
      _cacheTts(key, bytes);
      return bytes;
    }

    var current = synth(parts[0]);
    for (var i = 0; i < parts.length; i++) {
      final Uint8List bytes;
      try {
        bytes = await current;
      } catch (e) {
        if (gen != _speakGen) return null;
        if (i == 0) {
          final fb = await _speakSystem(text, 'zh-CN', rate);
          final why = e is EdgeTtsException ? e.message : e.toString();
          return fb == null ? null : '微软朗读不可用（$why），已改用系统语音';
        }
        // 后面某一段失败就安静收尾，不要把已经念过的内容重来一遍。
        return null;
      }
      if (gen != _speakGen) return null;

      // 先把下一段挂上，当前这段播放的时间正好用来合成它。
      if (i + 1 < parts.length) {
        current = synth(parts[i + 1]);
        // 预取的 future 若失败，先在这里兜一下，避免变成未捕获异常；
        // 真正的错误会在下一轮 await 时抛出。
        unawaited(current.catchError((Object _) => Uint8List(0)));
      }

      final path = await _writeTemp(bytes, 'mp3');
      if (path == null) return '音频写入失败';
      if (gen != _speakGen) {
        _deleteQuietly(path);
        return null;
      }
      final err = await _playFile(path);
      _deleteQuietly(path);
      if (gen != _speakGen) return null;
      if (err != null) return err;
    }
    return null;
  }

  void _cacheTts(String key, Uint8List bytes) {
    if (bytes.length > 512 * 1024 || _ttsCache.containsKey(key)) return;
    _ttsCache[key] = bytes;
    _ttsCacheBytes += bytes.length;
    while (_ttsCacheBytes > _ttsCacheMax && _ttsCache.isNotEmpty) {
      final first = _ttsCache.keys.first;
      _ttsCacheBytes -= _ttsCache.remove(first)?.length ?? 0;
    }
  }

  Future<String?> _speakFish(
      String text, String voice, String baseUrl, String apiKey) async {
    if (apiKey.trim().isEmpty) return 'Fish Audio 需要填写 API Key';
    final base = _trimSlash(baseUrl).isEmpty
        ? 'https://api.fish.audio'
        : _trimSlash(baseUrl);
    final parts = chunk(text, 500);
    for (var i = 0; i < parts.length; i++) {
      try {
        final resp = await _dio.post<List<int>>(
          '$base/v1/tts',
          data: {
            'text': parts[i],
            'format': 'mp3',
            'mp3_bitrate': 128,
            'latency': 'normal',
            if (voice.trim().isNotEmpty) 'reference_id': voice.trim(),
          },
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
          ),
        );
        final bytes = resp.data;
        if (bytes == null || bytes.isEmpty) return 'Fish Audio 没有返回音频';
        final path = await _writeTemp(bytes, 'mp3');
        if (path == null) return '音频写入失败';
        final err = await _playFile(path);
        _deleteQuietly(path);
        if (err != null) return err;
      } on DioException catch (e) {
        return explainTtsError(e);
      } catch (e) {
        return '合成失败：${_short(e)}';
      }
    }
    return null;
  }

  /// Azure 语音：区域名 → `https://{region}.tts.speech.microsoft.com`。
  Future<String?> _speakAzure(
      String text, String voice, String baseUrl, String apiKey) async {
    if (apiKey.trim().isEmpty) return 'Azure 需要填写订阅密钥';
    final raw = baseUrl.trim().isEmpty ? 'eastasia' : baseUrl.trim();
    final base = raw.startsWith('http')
        ? _trimSlash(raw)
        : 'https://$raw.tts.speech.microsoft.com';
    final url = base.endsWith('/cognitiveservices/v1')
        ? base
        : '$base/cognitiveservices/v1';
    final v =
        voice.trim().isEmpty ? 'zh-CN-XiaoxiaoNeural' : voice.trim();
    try {
      final resp = await _dio.post<List<int>>(
        url,
        data: "<speak version='1.0' xml:lang='zh-CN'>"
            "<voice name='$v'>${_escapeXml(text)}</voice></speak>",
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Ocp-Apim-Subscription-Key': apiKey.trim(),
            'Content-Type': 'application/ssml+xml',
            'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
            'User-Agent': 'Aigent',
          },
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return 'Azure 没有返回音频';
      final path = await _writeTemp(bytes, 'mp3');
      if (path == null) return '音频写入失败';
      final err = await _playFile(path);
      _deleteQuietly(path);
      return err;
    } on DioException catch (e) {
      return explainTtsError(e);
    } catch (e) {
      return '合成失败：${_short(e)}';
    }
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<String?> _speakEleven(
      String text, String voice, String baseUrl, String apiKey) async {
    if (apiKey.trim().isEmpty) return 'ElevenLabs 需要填写 API Key';
    final base = _trimSlash(baseUrl).isEmpty
        ? 'https://api.elevenlabs.io'
        : _trimSlash(baseUrl);
    final id = _elevenVoices[voice] ??
        (voice.trim().isEmpty ? _elevenVoices['Rachel']! : voice.trim());
    try {
      final resp = await _dio.post<List<int>>(
        '$base/v1/text-to-speech/$id',
        data: {
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'xi-api-key': apiKey.trim(),
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return 'ElevenLabs 没有返回音频';
      final path = await _writeTemp(bytes, 'mp3');
      if (path == null) return '音频写入失败';
      final err = await _playFile(path);
      _deleteQuietly(path);
      return err;
    } on DioException catch (e) {
      return explainTtsError(e);
    } catch (e) {
      return '合成失败：${_short(e)}';
    }
  }

  static const Map<String, String> _elevenVoices = {
    'Rachel': '21m00Tcm4TlvDq8ikWAM',
    'Adam': 'pNInz6obpgDQGcFmaJgB',
    'Bella': 'EXAVITQu4vr4xnSDxMaL',
    'Antoni': 'ErXwobaYiN019PkySvjV',
    'Domi': 'AZnzlk1XvdvUeBnXmlld',
  };

  Future<String?> _playUrl(String url) async {
    final done = Completer<String?>();
    _speakDone = done;
    final ok =
        await _ch.invokeMethod<bool>('player.url', {'url': url}) ?? false;
    if (!ok) {
      _speakDone = null;
      return '音频地址无法播放';
    }
    return done.future.timeout(const Duration(seconds: 120), onTimeout: () {
      _speakDone = null;
      return null;
    });
  }

  Future<String?> _playFile(String path) async {
    final done = Completer<String?>();
    _speakDone = done;
    final ok =
        await _ch.invokeMethod<bool>('player.file', {'path': path}) ?? false;
    if (!ok) {
      _speakDone = null;
      return '音频文件无法播放';
    }
    return done.future.timeout(const Duration(seconds: 180), onTimeout: () {
      _speakDone = null;
      return null;
    });
  }

  Future<void> stop() async {
    // 让还在合成中的那一轮作废：用户点停止后不该再冒出声音。
    _speakGen++;
    _finishSpeak(null);
    try {
      await _ch.invokeMethod('player.stop');
    } catch (_) {}
    try {
      await _ch.invokeMethod('tts.stop');
    } catch (_) {}
    speaking.value = false;
  }

  // ------------------------------------------------------------ STT

  /// 系统识别：边说边出字，中间结果直接回传。
  ///
  /// [preferOffline] 为真时优先端侧离线引擎（Android 12+），失败自动回落
  /// 在线；[silenceMs] 控制说完多久收尾，默认 700ms，比系统默认更跟手。
  Future<bool> startSystemListen({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    bool preferOffline = true,
    bool autoFallback = true,
    int silenceMs = 700,
    String engine = 'system',
    void Function()? onSpeechEnd,
    void Function(String message)? onNotice,
  }) async {
    _ensureSubscribed();
    _sttHandler = onText;
    _sttSpeechEnd = onSpeechEnd;
    _sttNotice = onNotice;
    _sttLang = lang;
    _sttSilenceMs = silenceMs.clamp(300, 3000);
    _sttEngine = engine;
    _fallbackArmed = autoFallback;
    rms.value = 0;

    // 端侧离线：模型在应用私有目录里，先加载再开麦。全部本地完成，
    // 不经过任何服务器；模型没装时直接告诉上层去下载，而不是静默失败。
    if (engine == SpeechModel.engineId) {
      try {
        final status = await SpeechModel.status();
        if (!status.ready) {
          _lastError = '离线语音包还没下载';
          sttAvailable.value = false;
          return false;
        }
        final prepared = await _ch.invokeMethod<bool>('vosk.prepare', {
              'path': status.path,
            }) ??
            false;
        if (!prepared) {
          _lastError = '离线语音包加载失败，可在设置里重新下载';
          sttAvailable.value = false;
          return false;
        }
        final ok = await _ch.invokeMethod<bool>('vosk.start', {
              'silenceMs': _sttSilenceMs,
            }) ??
            false;
        sttAvailable.value = ok;
        if (!ok) _lastError = '离线识别启动失败';
        return ok;
      } on PlatformException catch (e) {
        _lastError = e.message ?? '离线识别启动失败';
        sttAvailable.value = false;
        return false;
      } catch (e) {
        _lastError = _short(e);
        sttAvailable.value = false;
        return false;
      }
    }

    try {
      final ok = await _ch.invokeMethod<bool>('stt.start', {
            'lang': lang,
            'preferOffline': preferOffline,
            'silenceMs': _sttSilenceMs,
          }) ??
          false;
      sttAvailable.value = ok;
      if (!ok) _lastError = '系统没有可用的语音识别服务';
      return ok;
    } on PlatformException catch (e) {
      _lastError = e.message ?? '无法启动识别';
      sttAvailable.value = false;
      return false;
    } catch (e) {
      // MissingPluginException（测试 / 无原生实现）等一律按不可用处理。
      _lastError = _short(e);
      sttAvailable.value = false;
      return false;
    }
  }

  /// 查询本机语音识别能力；结果缓存，设置页和输入栏共用。
  Future<Map<String, dynamic>> capabilities() async {
    final cached = _capsCache;
    if (cached != null) return cached;
    try {
      final raw =
          await _ch.invokeMethod<Map<dynamic, dynamic>>('stt.capabilities');
      _capsCache = raw == null
          ? <String, dynamic>{'available': false, 'onDevice': false}
          : Map<String, dynamic>.from(raw);
    } catch (_) {
      // 单测 / 桌面端没有原生通道时按「不可用」处理，不让整个面板报错。
      _capsCache = <String, dynamic>{'available': false, 'onDevice': false};
    }
    return _capsCache!;
  }

  /// 设置页「一键测速」：本地引擎读系统能力，云端引擎测 /models 连通延迟。
  /// 不发起真实转写，因此不弹麦克风权限、不消耗额度。
  Future<SttProbeResult> probe({
    required SttEngine engine,
    required String baseUrl,
    required String apiKey,
  }) async {
    if (engine.proto == VoiceProto.system) {
      final sw = Stopwatch()..start();
      final caps = await capabilities();
      sw.stop();
      final available = caps['available'] == true;
      final onDevice = caps['onDevice'] == true;
      if (!available) {
        return SttProbeResult(
            ok: false,
            label: '系统无识别服务',
            detail: '这台设备没有可用的语音识别服务，请改用云端引擎。',
            ms: sw.elapsedMilliseconds);
      }
      final local = engine.offline && onDevice;
      return SttProbeResult(
        ok: local || !engine.offline,
        label: local ? '端侧离线可用' : '系统在线可用',
        detail: local
            ? '零网络往返，按住说话松手即出字。'
            : (engine.offline
                ? '这台设备没有端侧离线包，已启用自动回落在线识别。'
                : '由系统识别服务处理，边说边出字。'),
        ms: sw.elapsedMilliseconds,
      );
    }

    final base = _trimSlash(baseUrl);
    if (base.isEmpty) {
      return const SttProbeResult(
          ok: false, label: '未配置地址', detail: '先填接口地址再测。', ms: 0);
    }
    final sw = Stopwatch()..start();
    try {
      await _dio.get<dynamic>(
        '$base/models',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
        ),
      );
      sw.stop();
      return SttProbeResult(
        ok: true,
        label: '连接正常 · ${sw.elapsedMilliseconds}ms',
        detail: '地址可访问；实际转写延迟还受录音长度影响。',
        ms: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final code = e.response?.statusCode ?? 0;
      // 有些服务不给 /models，但转写端点可用；401/404 才当失败。
      if (code != 401 && code != 404 && code != 0) {
        return SttProbeResult(
          ok: true,
          label: '服务可达 · ${sw.elapsedMilliseconds}ms',
          detail: '返回 $code（可能未开放 /models），转写端点仍可能可用。',
          ms: sw.elapsedMilliseconds,
        );
      }
      return SttProbeResult(
        ok: false,
        label: code == 0 ? '连不上' : '返回 $code',
        detail: code == 401 ? '密钥无效。' : explainSttError(e),
        ms: sw.elapsedMilliseconds,
      );
    }
  }

  Future<void> stopSystemListen() async {
    _fallbackArmed = false;
    try {
      await _ch.invokeMethod(
          _sttEngine == SpeechModel.engineId ? 'vosk.stop' : 'stt.stop');
    } catch (_) {}
    listening.value = false;
    rms.value = 0;
  }

  Future<void> cancelSystemListen() async {
    _fallbackArmed = false;
    try {
      await _ch.invokeMethod(
          _sttEngine == SpeechModel.engineId ? 'vosk.cancel' : 'stt.cancel');
    } catch (_) {}
    listening.value = false;
    rms.value = 0;
    offlineActive.value = false;
    _sttHandler = null;
    _sttSpeechEnd = null;
    _sttNotice = null;
  }

  /// 云端转写用的录音：原生 MediaRecorder，16k 单声道 AAC。
  Future<bool> startRecording() async {
    _ensureSubscribed();
    try {
      var granted = await _ch.invokeMethod<bool>('rec.hasPermission') ?? false;
      if (!granted) {
        await _ch.invokeMethod('rec.requestPermission');
        // 系统权限弹窗要人点，最多等 6 秒；用户拒绝就明确说出来。
        for (var i = 0; i < 12 && !granted; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          granted = await _ch.invokeMethod<bool>('rec.hasPermission') ?? false;
        }
        if (!granted) {
          _lastError = '没有麦克风权限，请在系统设置里允许录音';
          return false;
        }
      }
      final dir = await getTemporaryDirectory();
      _recPath =
          '${dir.path}/aigent_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _ch.invokeMethod('rec.start', {'path': _recPath});
      listening.value = true;
      return true;
    } on PlatformException catch (e) {
      _lastError = e.message ?? '录音启动失败';
      listening.value = false;
      return false;
    } catch (e) {
      _lastError = _short(e);
      listening.value = false;
      return false;
    }
  }

  /// 停止录音并上传转写。[onStatus] 用于「识别中」提示。
  Future<String?> stopAndTranscribe({
    required SttEngine engine,
    required String baseUrl,
    required String apiKey,
    String model = '',
    String lang = 'zh-CN',
    void Function(String status)? onStatus,
  }) async {
    String? path;
    try {
      path = await _ch.invokeMethod<String>('rec.stop');
    } catch (e) {
      _lastError = _short(e);
      listening.value = false;
      rms.value = 0;
      return null;
    }
    listening.value = false;
    rms.value = 0;
    final p = (path == null || path.isEmpty) ? _recPath : path;
    if (p.isEmpty || !File(p).existsSync()) {
      _lastError = '没有录到声音，按住说久一点';
      return null;
    }

    final base = _trimSlash(baseUrl);
    if (base.isEmpty) {
      _lastError = '未配置转写接口地址';
      _deleteQuietly(p);
      return null;
    }
    onStatus?.call('识别中…');
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(p, filename: 'voice.m4a'),
        if (model.trim().isNotEmpty) 'model': model.trim(),
        if (lang.isNotEmpty) 'language': lang.split('-').first,
      });
      final resp = await _dio.post<dynamic>(
        '$base/audio/transcriptions',
        data: form,
        options: Options(headers: {
          if (apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${apiKey.trim()}',
        }),
      );
      final d = resp.data;
      if (d is Map && d['text'] is String) {
        return polishTranscript((d['text'] as String));
      }
      if (d is String) return polishTranscript(d);
      _lastError = '服务端返回格式不认识';
      return null;
    } on DioException catch (e) {
      _lastError = explainSttError(e);
      return null;
    } catch (e) {
      _lastError = _short(e);
      return null;
    } finally {
      _deleteQuietly(p);
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _ch.invokeMethod('rec.cancel');
    } catch (_) {}
    listening.value = false;
    rms.value = 0;
  }

  void dispose() {
    _evSub?.cancel();
    _evSub = null;
  }

  // ------------------------------------------------------------ 工具

  Future<String?> _writeTemp(List<int> bytes, String ext) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/aigent_tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// 去掉 Markdown 标记：朗读时不该把 `**`、链接地址、代码块都念出来。
  static String stripMarkdown(String src) {
    var s = src;
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '。代码块已跳过。');
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    // 链接只保留文字：Dart 的 replaceAll 不解析 $1，必须用 replaceAllMapped，
    // 否则会把「文档」念成「美元一」。
    s = s.replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[*_`>|]'), '');
    s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
    return s.trim();
  }

  /// 按句子边界切段。免费通道对长度敏感，硬切会把词切坏。
  static List<String> chunk(String src, int max) {
    final out = <String>[];
    var rest = src.trim();
    while (rest.length > max) {
      var cut = -1;
      for (var i = max; i > max ~/ 3; i--) {
        final c = rest[i - 1];
        if (c == '。' ||
            c == '！' ||
            c == '？' ||
            c == '.' ||
            c == '!' ||
            c == '?' ||
            c == '\n' ||
            c == '；' ||
            c == ';') {
          cut = i;
          break;
        }
      }
      if (cut <= 0) cut = max;
      out.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static String _trimSlash(String s) {
    var v = s.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// 原生层的英文异常直接甩给用户，只会让人以为是手机坏了。
  /// 这里只翻译「有明确下一步」的几类，其余原样保留方便排查。
  static String friendlySttError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('peer field id') || s.contains('com.sun.jna')) {
      return '离线识别引擎没加载起来（安装包的压缩步骤裁掉了原生库的必要字段）。'
          '在 设置 → 语音 里先把引擎切成「系统语音」就能用；'
          '装 4.9.3 及之后的版本会彻底修复。';
    }
    if (s.contains('model') &&
        (s.contains('not found') || s.contains('no such file'))) {
      return '离线语音包不完整，去 设置 → 语音 重新解压一次。';
    }
    if (s.contains('out of memory') || s.contains('oom')) {
      return '内存不足，离线模型加载失败。关掉一些后台应用再试。';
    }
    return raw;
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  /// 把 HTTP 错误翻译成「下一步该做什么」，而不是甩一个状态码。
  static String explainTtsError(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final base = _trimSlash(e.requestOptions.baseUrl);
    switch (code) {
      case 401:
        return '密钥无效或未填（401）。检查这条连接 / 语音引擎的 Key。';
      case 402:
        return '额度不足（402）。这条通道要付费或免费额度已用完。';
      case 403:
        return '被拒绝（403）。可能是该模型未对当前账号开放。';
      case 404:
        return '这个地址没有 /audio/speech（404）。该服务商可能只做对话，'
            '换「系统语音」或有道 / 百度。';
      case 429:
        return '请求太频繁（429）。等一会儿再试，或换成系统语音。';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return '超时。检查网络，或换系统语音。';
        }
        if (e.type == DioExceptionType.connectionError) {
          return '连不上 $base。检查地址与网络。';
        }
        return '请求失败${code == 0 ? '' : '（$code）'}：${e.message ?? ''}';
    }
  }

  static String explainSttError(DioException e) {
    final code = e.response?.statusCode ?? 0;
    switch (code) {
      case 401:
        return '密钥无效（401）。转写接口需要 Key。';
      case 404:
        return '这个地址没有 /audio/transcriptions（404）。'
            '换成「系统识别」，或填支持 Whisper 的接口。';
      case 413:
        return '录音太大（413）。说短一点再试。';
      case 429:
        return '请求太频繁（429）。稍后再试。';
      default:
        if (e.type == DioExceptionType.connectionError) {
          return '连不上转写服务。';
        }
        return '转写失败${code == 0 ? '' : '（$code）'}';
    }
  }
}
