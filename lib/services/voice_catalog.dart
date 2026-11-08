/// 语音引擎目录（TTS 朗读 + STT 语音输入）。
///
/// 设计原则和「免密模型」一致：**只放确认可用的通道**，并明确标出
/// 是否需要密钥、是否离线。免费通道会随时失效，所以每一项都写清
/// 回落方案；系统语音永远是最后的兜底（不联网、不花钱、不失效）。
///
/// 所有云端引擎尽量收敛到 OpenAI 兼容协议（`/audio/speech`、
/// `/audio/transcriptions`），这样 OpenAI、Groq、硅基流动、DeepInfra、
/// One API、gpt4free、本地 whisper.cpp 全都用同一段代码。
library;

/// 传输协议族。
/// - [system]：系统内置（Android TTS / SpeechRecognizer），离线可用；
/// - [openai]：OpenAI 兼容，POST 音频二进制或 multipart 上传；
/// - [urlQuery]：GET 拼 URL 直出 mp3，无需密钥（有道 / 百度 / SE）；
/// - [elevenLabs]：ElevenLabs 私有协议，音质最好但按字符计费。
enum VoiceProto {
  system,
  openAI,
  urlQuery,
  elevenLabs,

  /// 微软 Edge「大声朗读」：WebSocket + 私有签名，免密钥。
  edge,

  /// Fish Audio：自有协议，音色用 reference_id。
  fish,

  /// Azure 语音服务：SSML + 订阅密钥 + 区域。
  azure,
}

/// 一个 TTS 引擎。
class TtsEngine {
  final String id;
  final String name;
  final String summary;

  /// 标签：免费 / 离线 / 需 Key / 高音质。用于列表右侧的短标记。
  final String badge;
  final VoiceProto proto;

  /// 固定根地址；空字符串表示「跟随当前连接」。
  final String baseUrl;
  final bool needsKey;
  final List<String> voices;

  /// 与 [voices] 一一对应的实际取值。为空时直接用 [voices]。
  /// 界面上显示「晓晓」，请求里必须是 `zh-CN-XiaoxiaoNeural`。
  final List<String> voiceIds;
  final String note;

  const TtsEngine({
    required this.id,
    required this.name,
    required this.summary,
    required this.badge,
    required this.proto,
    this.baseUrl = '',
    this.needsKey = false,
    this.voices = const [],
    this.voiceIds = const [],
    this.note = '',
  });

  /// 把界面上的音色名换成接口要的值。
  String voiceId(String label) {
    if (label.isEmpty) return voices.isEmpty ? '' : _idAt(0);
    final i = voices.indexOf(label);
    return i >= 0 ? _idAt(i) : label;
  }

  String _idAt(int i) =>
      i < voiceIds.length ? voiceIds[i] : (i < voices.length ? voices[i] : '');

  bool get followsConnection => baseUrl.isEmpty;
  bool get isFree => badge == '免费' || badge == '离线';
}

/// 一个 STT 引擎。
///
/// v4.4 起额外记录「是否本地 / 速度 / 准确度 / 中文优化」，这四个维度
/// 直接决定设置页的标签和默认排序——用户要的是「快、本地、准、多选」，
/// 只给一串名字没法判断该选哪个。
class SttEngine {
  final String id;
  final String name;
  final String summary;
  final String badge;
  final VoiceProto proto;
  final String baseUrl;
  final bool needsKey;

  /// 默认模型名，空表示用服务端默认。
  final String model;
  final String note;

  /// 数据不出手机（系统离线识别 / 本机服务）。
  final bool offline;

  /// 1~3：1 偏慢、3 极快（含网络往返与首字延迟的综合估计）。
  final int speed;

  /// 1~3：1 够用、3 中文标点与专有名词表现最好。
  final int accuracy;

  /// 对中文口语做过专门优化。
  final bool zhOptimized;

  /// 地址完全由用户填写（[baseUrl] 为空时不视为「跟随当前连接」）。
  final bool custom;

  /// 需自行在电脑 / 局域网部署服务，手机本身没有。
  final bool experimental;

  const SttEngine({
    required this.id,
    required this.name,
    required this.summary,
    required this.badge,
    required this.proto,
    this.baseUrl = '',
    this.needsKey = false,
    this.model = '',
    this.note = '',
    this.offline = false,
    this.speed = 2,
    this.accuracy = 2,
    this.zhOptimized = false,
    this.custom = false,
    this.experimental = false,
  });

  bool get followsConnection => baseUrl.isEmpty && !custom;
  bool get isLocal => offline;
  String get speedLabel => switch (speed) {
        3 => '极快',
        2 => '较快',
        _ => '较慢',
      };
  String get accuracyLabel => switch (accuracy) {
        3 => '很准',
        2 => '准确',
        _ => '一般',
      };

  /// 设置页每行右侧的短标签：本地优先，其次速度 / 准确度 / 中文。
  List<String> get tags => [
        if (experimental) '需部署',
        if (custom) '自定义',
        if (offline && !experimental) '本地',
        speedLabel,
        accuracyLabel,
        if (zhOptimized) '中文佳',
        if (needsKey) '需 Key',
      ];
}

/// 内置 TTS 引擎。顺序即推荐顺序：先免费、再跟随连接、最后付费高音质。
const List<TtsEngine> kTtsEngines = [
  TtsEngine(
    id: 'edge',
    name: '微软 Edge 朗读',
    summary: '免密钥，中文 14 个音色，最接近真人',
    badge: '免费',
    proto: VoiceProto.edge,
    voices: ['晓晓', '云希', '云健', '晓伊', '云扬', '晓北', '晓妮', 'Aria'],
    voiceIds: [
      'zh-CN-XiaoxiaoNeural',
      'zh-CN-YunxiNeural',
      'zh-CN-YunjianNeural',
      'zh-CN-XiaoyiNeural',
      'zh-CN-YunyangNeural',
      'zh-CN-liaoning-XiaobeiNeural',
      'zh-CN-shaanxi-XiaoniNeural',
      'en-US-AriaNeural',
    ],
    note: '走 Edge 浏览器的「大声朗读」通道，不需要账号和密钥。'
        '晓晓最自然，云希偏年轻男声，云扬是播音腔。'
        '长回答会分段请求；通道失效时自动回落系统语音。',
  ),
  TtsEngine(
    id: 'system',
    name: '系统语音',
    summary: '调用手机自带语音引擎，离线、零配置、不花钱',
    badge: '离线',
    proto: VoiceProto.system,
    note: '音色取决于系统装了哪家引擎（Google / 各家 ROM 自带）。'
        '长文朗读建议用它，稳定且不消耗额度。',
  ),
  TtsEngine(
    id: 'google',
    name: 'Google 翻译朗读',
    summary: '免密钥，短句快，中文女声干净',
    badge: '免费',
    proto: VoiceProto.urlQuery,
    baseUrl: 'https://translate.google.com/translate_tts',
    voices: ['中文', '英文'],
    note: '翻译页的朗读接口，单次上限约 200 字，长文会分段。'
        '部分网络环境访问不了，失败自动回落系统语音。',
  ),
  TtsEngine(
    id: 'youdao',
    name: '有道词典',
    summary: '免密钥，中英文都可，响应最快',
    badge: '免费',
    proto: VoiceProto.urlQuery,
    baseUrl: 'https://dict.youdao.com/dictvoice',
    voices: ['美音', '英音'],
    note: '无公开配额说明，单次建议不超过 500 字；失败时自动回落到系统语音。',
  ),
  TtsEngine(
    id: 'baidu',
    name: '百度翻译',
    summary: '免密钥，中文女声自然，适合长句',
    badge: '免费',
    proto: VoiceProto.urlQuery,
    baseUrl: 'https://fanyi.baidu.com/gettts',
    voices: ['中文', '英文'],
    note: '翻译页的朗读接口，无需 AppID；按句子分段请求更稳。',
  ),
  TtsEngine(
    id: 'streamelements',
    name: 'StreamElements',
    summary: '免密钥，Amazon Polly 音色，英文质量高',
    badge: '免费',
    proto: VoiceProto.urlQuery,
    baseUrl: 'https://api.streamelements.com/kappa/v2/speech',
    voices: [
      'Brian',
      'Amy',
      'Joanna',
      'Matthew',
      'Ivy',
      'Justin',
      'Salli',
      'Kimberly',
    ],
    note: '面向直播打赏的公开接口，只保证英文音色；中文请用有道或百度。',
  ),
  TtsEngine(
    id: 'fish',
    name: 'Fish Audio',
    summary: '音色克隆与二次元声线，注册送免费额度',
    badge: '免费额度',
    proto: VoiceProto.fish,
    baseUrl: 'https://api.fish.audio',
    needsKey: true,
    note: '在 fish.audio 控制台创建 API Key。默认用官方音色；'
        '想指定自己的音色，把 reference_id 填到「音色」里。',
  ),
  TtsEngine(
    id: 'cosy',
    name: '硅基流动 CosyVoice2',
    summary: '国内访问快，注册送额度，中文自然',
    badge: '免费额度',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.siliconflow.cn/v1',
    needsKey: true,
    voices: ['anna', 'bella', 'claire', 'david', 'diana'],
    note: '模型固定 FunAudioLLM/CosyVoice2-0.5B，'
        'OpenAI 兼容的 /audio/speech。没有额度时返回 402。',
  ),
  TtsEngine(
    id: 'groq-tts',
    name: 'Groq PlayAI',
    summary: '免费额度，延迟极低；中文一般，英文最好',
    badge: '免费额度',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.groq.com/openai/v1',
    needsKey: true,
    voices: ['Arista', 'Cheyenne', 'Celeste', 'Gail', 'Jennifer'],
    voiceIds: [
      'Arista-PlayAI',
      'Cheyenne-PlayAI',
      'Celeste-PlayAI',
      'Gail-PlayAI',
      'Jennifer-PlayAI',
    ],
    note: 'Groq 控制台可直接申请 Key，免费额度按天重置。',
  ),
  TtsEngine(
    id: 'azure',
    name: 'Azure 语音',
    summary: '与 Edge 同源音色，可按区域稳定调用',
    badge: '需 Key',
    proto: VoiceProto.azure,
    baseUrl: 'eastasia',
    needsKey: true,
    voices: ['晓晓', '云希', '云健', '晓伊'],
    voiceIds: [
      'zh-CN-XiaoxiaoNeural',
      'zh-CN-YunxiNeural',
      'zh-CN-YunjianNeural',
      'zh-CN-XiaoyiNeural',
    ],
    note: '「接口地址」填区域名（如 eastasia、eastus），'
        '每月 50 万字符免费。Key 在 Azure 门户的「语音服务」里取。',
  ),
  TtsEngine(
    id: 'current',
    name: '当前连接',
    summary: '用已配置的接口调 /audio/speech，OpenAI 兼容即可',
    badge: '跟随连接',
    proto: VoiceProto.openAI,
    voices: ['alloy', 'nova', 'shimmer', 'echo', 'fable', 'onyx'],
    note: 'OpenAI、Groq、硅基流动、DeepInfra、One API 都实现了这个路径。'
        '若服务商不支持会返回 404，换系统语音即可。',
  ),
  TtsEngine(
    id: 'kokoro',
    name: '本机 Kokoro',
    summary: '本机跑的 Kokoro-FastAPI，免密钥、无限量',
    badge: '免费',
    proto: VoiceProto.openAI,
    baseUrl: 'http://127.0.0.1:8880/v1',
    voices: ['af_heart', 'af_bella', 'am_michael', 'bf_emma'],
    note: 'docker run -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu。'
        '手机要填电脑的内网 IP。',
  ),
  TtsEngine(
    id: 'elevenlabs',
    name: 'ElevenLabs',
    summary: '音质最接近真人，按字符计费',
    badge: '需 Key',
    proto: VoiceProto.elevenLabs,
    baseUrl: 'https://api.elevenlabs.io',
    needsKey: true,
    voices: [
      'Rachel',
      'Adam',
      'Bella',
      'Antoni',
      'Domi',
    ],
    note: '免费额度每月 1 万字符。音色 ID 可在官网 Voices 页查到后直接填。',
  ),
];

/// 内置 STT 引擎。
///
/// v4.6 的原则：**只列这台手机上真能跑起来的**。之前塞了 10 个带
/// 「本地 / 极快 / 很准」标签的选项，但本机 whisper.cpp / sherpa-onnx
/// 需要电脑先起服务、云端都要 Key、默认又强制离线优先——结果是
/// 「一个都不能用」。现在：
///  1. 默认「系统在线识别」，不需要 Key、不需要额外服务；
///  2. 本机 / 局域网类移到 [kExperimentalSttEngines]，明确写出前置条件；
///  3. 重复的云端 Whisper 收敛成一个「自定义 OpenAI 兼容」入口。
const List<SttEngine> kSttEngines = [
  SttEngine(
    id: 'ovh-whisper',
    name: '在线 Whisper（免密钥）',
    summary: 'whisper-large-v3-turbo，免密钥、自带标点、中文准',
    badge: '免费',
    proto: VoiceProto.openAI,
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    speed: 3,
    accuracy: 3,
    zhOptimized: true,
    model: 'whisper-large-v3-turbo',
    note: 'OVH 的公开端点，不用注册、不用 Key，录音上传后直接回转写，'
        '自带标点与断句，比本地小模型准得多。'
        '需要联网；失败会自动回落到系统识别。',
  ),
  SttEngine(
    id: 'ovh-whisper-large',
    name: '在线 Whisper Large（免密钥）',
    summary: 'whisper-large-v3，更准但更慢，适合长句',
    badge: '免费',
    proto: VoiceProto.openAI,
    baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
    speed: 1,
    accuracy: 3,
    zhOptimized: true,
    model: 'whisper-large-v3',
    note: '同一个免密钥端点的大模型档，专有名词与口音更稳；'
        '单次请求比 turbo 慢一倍左右。',
  ),
  SttEngine(
    id: 'vosk-cn',
    name: '内置离线识别',
    summary: '语音包已内置在安装包里，装好即用，完全不联网',
    badge: '离线',
    proto: VoiceProto.system,
    offline: true,
    speed: 3,
    accuracy: 2,
    zhOptimized: true,
    note: '模型随安装包一起分发，首次点麦克风在本机解压，不需要下载、'
        '不会因为网络下不动而失败。不用申请 Key、不看运营商脸色，'
        '飞行模式也能用。模型放在应用私有目录，卸载即清理。',
  ),
  SttEngine(
    id: 'system',
    name: '系统在线识别',
    summary: '调用系统自带识别服务，不需密钥、不需额外部署',
    badge: '开箱即用',
    proto: VoiceProto.system,
    speed: 3,
    accuracy: 3,
    zhOptimized: true,
    note: '由手机系统的语音识别服务处理，边说边出字。'
        '少数精简 ROM 没有识别服务，此时可用云端引擎。',
  ),
  SttEngine(
    id: 'system-offline',
    name: '系统离线识别',
    summary: '端侧引擎，完全不联网；需系统已装中文离线语音包',
    badge: '本地',
    proto: VoiceProto.system,
    offline: true,
    speed: 3,
    accuracy: 2,
    zhOptimized: true,
    note: '只在检测到端侧离线识别可用时才会启用；没有语音包会'
        '自动切回系统在线识别。',
  ),
  SttEngine(
    id: 'current',
    name: '当前连接',
    summary: '把录音发到已配置接口的 /audio/transcriptions',
    badge: '跟随连接',
    proto: VoiceProto.openAI,
    speed: 2,
    accuracy: 3,
    zhOptimized: true,
    model: 'whisper-1',
    note: '只有接口本身提供音频转写时才能用；多数免费文本接口'
        '（如 Pollinations）不支持，会返回 404。',
  ),
  SttEngine(
    id: 'groq',
    name: 'Groq Whisper',
    summary: 'whisper-large-v3-turbo，免费额度、转写极快',
    badge: '免费额度',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.groq.com/openai/v1',
    needsKey: true,
    speed: 3,
    accuracy: 3,
    zhOptimized: true,
    model: 'whisper-large-v3-turbo',
    note: '控制台免费申请 Key；长语音也能秒回，每分钟有请求上限。',
  ),
  SttEngine(
    id: 'siliconflow',
    name: '硅基流动 SenseVoice',
    summary: '中文口语与专有名词更稳，注册送额度',
    badge: '中文佳',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.siliconflow.cn/v1',
    needsKey: true,
    speed: 2,
    accuracy: 3,
    zhOptimized: true,
    model: 'FunAudioLLM/SenseVoiceSmall',
    note: '中文短句表现好于 whisper-small；国内访问稳定。',
  ),
  SttEngine(
    id: 'dashscope',
    name: '阿里 Paraformer',
    summary: '国内直连稳定，中文标点与数字读法好',
    badge: '免费额度',
    proto: VoiceProto.openAI,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    needsKey: true,
    speed: 3,
    accuracy: 3,
    zhOptimized: true,
    model: 'paraformer-v2',
    note: '阿里云百炼控制台申请 Key，新账号有免费额度；'
        '国内网络不需要额外加速。',
  ),
  SttEngine(
    id: 'deepinfra',
    name: 'DeepInfra Whisper',
    summary: '按秒计费极便宜，模型与 Groq 同档',
    badge: '低价',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    needsKey: true,
    speed: 2,
    accuracy: 3,
    zhOptimized: true,
    model: 'openai/whisper-large-v3-turbo',
    note: '注册送试用额度，之后按音频时长计费；'
        'OpenAI 兼容，换模型名即可。',
  ),
  SttEngine(
    id: 'mistral-stt',
    name: 'Mistral Voxtral',
    summary: '欧洲节点，多语种，免费额度较少',
    badge: '免费额度',
    proto: VoiceProto.openAI,
    baseUrl: 'https://api.mistral.ai/v1',
    needsKey: true,
    speed: 2,
    accuracy: 3,
    zhOptimized: false,
    model: 'voxtral-mini-latest',
    note: 'La Plateforme 免费档可试用；中文可用但没有专门优化。',
  ),
  SttEngine(
    id: 'custom',
    name: '自定义 OpenAI 兼容',
    summary: '自己填地址、密钥与模型，覆盖 OpenAI / DeepInfra / Together 等',
    badge: '自定义',
    proto: VoiceProto.openAI,
    needsKey: true,
    custom: true,
    speed: 2,
    accuracy: 3,
    zhOptimized: true,
    note: '地址示例：https://api.openai.com/v1、'
        'https://api.deepinfra.com/v1/openai、https://api.together.xyz/v1。'
        '只要服务端实现 /audio/transcriptions 即可。',
  ),
];

/// 实验 / 需自行部署：手机本身**不会**自动有这些服务，默认不出现在主列表。
/// 折叠展示，避免用户误以为选上就能用。
const List<SttEngine> kExperimentalSttEngines = [
  SttEngine(
    id: 'whisper-local',
    name: '本机 whisper.cpp',
    summary: '需先在电脑 / 同网设备启动 whisper.cpp server',
    badge: '需部署',
    proto: VoiceProto.openAI,
    baseUrl: 'http://127.0.0.1:8080/v1',
    experimental: true,
    offline: true,
    speed: 2,
    accuracy: 3,
    zhOptimized: true,
    model: 'whisper-1',
    note: '手机要填电脑的内网 IP，不是 127.0.0.1。'
        '同类的 Speaches / faster-whisper-server 也可用。',
  ),
  SttEngine(
    id: 'sherpa',
    name: '本机 sherpa-onnx',
    summary: '需先在电脑 / 同网设备启动 sherpa-onnx 服务',
    badge: '需部署',
    proto: VoiceProto.openAI,
    baseUrl: 'http://127.0.0.1:8890/v1',
    experimental: true,
    offline: true,
    speed: 3,
    accuracy: 3,
    zhOptimized: true,
    model: 'SenseVoiceSmall',
    note: 'SenseVoice / Paraformer 端侧模型服务；数据只在局域网内流转。',
  ),
];

/// 全部引擎（主列表 + 实验区），用于按 id 找回旧配置。
List<SttEngine> get kAllSttEngines =>
    [...kSttEngines, ...kExperimentalSttEngines];

/// 本地 / 离线引擎（用于「一键测速」与自动回落链的第一段）。
List<SttEngine> get kLocalSttEngines =>
    kSttEngines.where((e) => e.offline).toList(growable: false);

/// 「一键测速」结果：只测可用性与连通延迟，不发真实转写。
class SttProbeResult {
  final bool ok;
  final String label;
  final String detail;
  final int ms;

  const SttProbeResult({
    required this.ok,
    required this.label,
    required this.detail,
    required this.ms,
  });
}

TtsEngine? ttsEngineById(String id) {
  for (final e in kTtsEngines) {
    if (e.id == id) return e;
  }
  return null;
}

SttEngine? sttEngineById(String id) {
  for (final e in kAllSttEngines) {
    if (e.id == id) return e;
  }
  return null;
}
