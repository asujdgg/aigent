/// 模型 ID → 官方品牌图标 / 供应商显示名。
///
/// 纯逻辑、可单测，不依赖 Flutter。模型列表里每个条目都用同一套彩色
/// 官方标记（见 `tool/build_brand_icons.py`），认不出来的统一落到
/// [ModelBrand.generic]，绝不出现「有的彩色、有的黑白」的混杂。
library;

/// 一个模型的品牌归属。
class ModelBrand {
  /// `assets/brand_models/<key>.png`。
  final String key;

  /// 副标题里的供应商名（中文优先，便于快速扫读）。
  final String label;

  const ModelBrand(this.key, this.label);

  static const generic = ModelBrand('generic', '其他模型');

  String get asset => 'assets/brand_models/$key.png';

  @override
  bool operator ==(Object other) =>
      other is ModelBrand && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);

  @override
  String toString() => 'ModelBrand($key, $label)';
}

/// 有序规则表：**模型本身的品牌在前，网关 / 运营商在后**。
/// 于是 `openai/gpt-4o` 归 OpenAI、`groq/llama-3.3` 归 Meta，
/// 而认不出来的自定义 ID 才会落到它所在的连接服务商。
/// 关键词都经过挑选，避免 `yi`、`o1` 之类的短串误伤别的模型名。
const List<({String key, String label, List<String> keys})> _kRules = [
  (key: 'openai', label: 'OpenAI', keys: [
    'gpt-', 'gpt3', 'gpt4', 'chatgpt', 'o1-', 'o3-', 'o4-', 'o1_', 'o3_',
    'davinci', 'dall-e', 'sora', 'chatgpt-4o', 'openai/'
  ]),
  (key: 'anthropic', label: 'Anthropic Claude', keys: ['claude']),
  (key: 'google', label: 'Google Gemini', keys: [
    'gemini', 'gemma', 'google/', 'palm', 'learnlm'
  ]),
  (key: 'deepseek', label: 'DeepSeek 深度求索', keys: ['deepseek']),
  (key: 'qwen', label: '阿里通义千问', keys: [
    'qwen', 'qwq', 'qvq', 'tongyi', 'qwen-long', 'qwen-vl'
  ]),
  (key: 'zhipu', label: '智谱 AI', keys: [
    'glm-', 'chatglm', 'cogview', 'cogvlm', 'codegeex', 'zhipu', 'zai/',
    'thudm', 'autoglm'
  ]),
  (key: 'doubao', label: '字节豆包', keys: ['doubao', 'seed-', 'bytedance']),
  (key: 'kimi', label: '月之暗面 Kimi', keys: ['kimi', 'moonshot']),
  (key: 'mistral', label: 'Mistral AI', keys: [
    'mistral', 'mixtral', 'codestral', 'magistral', 'ministral', 'pixtral',
    'devstral'
  ]),
  (key: 'meta', label: 'Meta Llama', keys: ['llama', 'meta-llama']),
  (key: 'grok', label: 'xAI Grok', keys: ['grok', 'x-ai/', 'xai/']),
  (key: 'hunyuan', label: '腾讯混元', keys: ['hunyuan', 'tencent/']),
  (key: 'baidu', label: '百度文心', keys: [
    'ernie', 'wenxin', 'baidu/', 'qianfan'
  ]),
  (key: 'minimax', label: 'MiniMax 稀宇', keys: ['minimax', 'abab', 'hailuo']),
  (key: 'yi', label: '零一万物 Yi', keys: [
    'yi-', 'yi_', '/yi', '01-ai', 'lingyi'
  ]),
  (key: 'baichuan', label: '百川智能', keys: ['baichuan']),
  (key: 'stepfun', label: '阶跃星辰', keys: ['step-', 'stepfun', 'stepfun/']),
  (key: 'spark', label: '讯飞星火', keys: ['spark', 'iflytek', 'xunfei']),
  (key: 'internlm', label: '书生·浦语', keys: ['internlm', 'shusheng']),
  (key: 'cohere', label: 'Cohere', keys: ['command-', 'cohere/', 'aya-']),
  (key: 'perplexity', label: 'Perplexity', keys: [
    'sonar', 'perplexity/', 'r1-1776'
  ]),
  (key: 'nvidia', label: 'NVIDIA', keys: ['nemotron', 'nvidia/']),
  (key: 'microsoft', label: 'Microsoft', keys: ['phi-', 'phi3', 'phi4', 'microsoft/']),
  (key: 'ai21', label: 'AI21 Labs', keys: ['ai21', 'jamba']),
  // ---- 以下为连接服务商：仅当模型名本身认不出来时才落到它们 ----
  (key: 'openrouter', label: 'OpenRouter', keys: ['openrouter']),
  (key: 'siliconflow', label: '硅基流动', keys: [
    'siliconflow', 'siliconcloud', 'silicon/'
  ]),
  (key: 'volcengine', label: '火山引擎', keys: ['volcengine', 'volces', 'volc-']),
  (key: 'deepinfra', label: 'DeepInfra', keys: ['deepinfra']),
  (key: 'fireworks', label: 'Fireworks AI', keys: ['fireworks']),
  (key: 'together', label: 'Together AI', keys: ['together']),
  (key: 'novita', label: 'Novita AI', keys: ['novita']),
  (key: 'cloudflare', label: 'Cloudflare Workers AI', keys: [
    'cloudflare', 'workersai', '@cf/'
  ]),
  (key: 'huggingface', label: 'Hugging Face', keys: [
    'huggingface', 'hf.co', 'hugging'
  ]),
  (key: 'azure', label: 'Azure OpenAI', keys: ['azure']),
  (key: 'bedrock', label: 'Amazon Bedrock', keys: ['bedrock', 'amazon/', 'nova-']),
  (key: 'groq', label: 'Groq', keys: ['groq']),
  (key: 'ollama', label: 'Ollama', keys: ['ollama']),
  (key: 'pollinations', label: 'Pollinations', keys: ['pollinations']),
  (key: 'kilocode', label: 'Kilo Code', keys: ['kilocode', 'kilo']),
  (key: 'replicate', label: 'Replicate', keys: ['replicate']),
  (key: 'alibaba', label: '阿里巴巴云', keys: ['alibaba', 'aliyun', 'dashscope']),
  (key: 'anthropic', label: 'Anthropic Claude', keys: ['anthropic/']),
  (key: 'google', label: 'Google Gemini', keys: ['google/']),
  (key: 'deepseek', label: 'DeepSeek 深度求索', keys: ['deepseek-ai/']),
  (key: 'openai', label: 'OpenAI', keys: ['openai']),
  (key: 'meta', label: 'Meta Llama', keys: ['meta/']),
];

/// 把任意模型 ID 归一到品牌。识别不到就返回 [ModelBrand.generic]。
ModelBrand resolveModelBrand(String id) {
  final s = id.trim().toLowerCase();
  if (s.isEmpty) return ModelBrand.generic;
  for (final r in _kRules) {
    for (final k in r.keys) {
      if (s.contains(k)) return ModelBrand(r.key, r.label);
    }
  }
  return ModelBrand.generic;
}

/// 全部已内置图标的 key，供自检 / 单测使用。
const Set<String> kBrandKeys = {
  'openai', 'anthropic', 'google', 'deepseek', 'qwen', 'zhipu', 'doubao',
  'kimi', 'mistral', 'meta', 'grok', 'hunyuan', 'baidu', 'minimax', 'yi',
  'baichuan', 'stepfun', 'spark', 'internlm', 'cohere', 'perplexity',
  'nvidia', 'microsoft', 'openrouter', 'siliconflow', 'volcengine',
  'deepinfra', 'fireworks', 'together', 'novita', 'cloudflare',
  'huggingface', 'azure', 'bedrock', 'ai21', 'alibaba', 'groq', 'moonshot',
  'ollama', 'pollinations', 'kilocode', 'replicate', 'generic',
};
