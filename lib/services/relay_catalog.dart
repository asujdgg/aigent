import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 鉴权方式。
/// - [none]：服务自身不需要 Key，请求不带 Authorization；
/// - [optional]：可留空，留空即不带，填了才带；
/// - [required]：必须填，否则一律 401。
enum RelayAuth { none, optional, required }

/// 分组只影响列表里的分节标题，不参与筛选逻辑。
///
/// [welfare] 不是自建项目，而是第三方公共站点：地址写死、要用对方发的
/// Key、随时可能改规则。单独成组，避免和「自己部署」混在一起。
enum RelayGroup { web, gateway, official, welfare, local }

/// 一个反代 / 网关预设。
///
/// 自建项目只存**部署形态**（默认端口、路径、模型名、鉴权方式），不存
/// 公共地址；官方平台与公益站点是固定地址，用 [fixedBaseUrl]。
class RelayPreset {
  final String id;
  final String name;
  final String owner;
  final String summary;
  final String deploy;
  final int port;
  final String path;
  final RelayAuth auth;
  final String keyHint;
  final List<String> models;
  final List<String> tags;
  final bool vision;
  final bool search;
  final bool tools;
  final RelayGroup group;

  /// 官方平台与公益站点不是「主机 + 端口」形态，直接写死完整地址。
  final String? fixedBaseUrl;

  /// 仓库或官网，用于「打开」。
  final String repoUrl;

  /// 已停更 / 归档，界面上会标出来，免得照着老文档部署。
  final bool archived;

  const RelayPreset({
    required this.id,
    required this.name,
    required this.owner,
    required this.summary,
    required this.deploy,
    required this.port,
    this.path = '/v1',
    this.auth = RelayAuth.optional,
    this.keyHint = '',
    this.models = const [],
    this.tags = const [],
    this.vision = false,
    this.search = false,
    this.tools = false,
    this.group = RelayGroup.web,
    this.fixedBaseUrl,
    this.repoUrl = '',
    this.archived = false,
  });

  String get sampleModel => models.isEmpty ? '' : models.first;

  /// 按用户填的主机拼出接口地址；固定地址的预设忽略主机。
  String urlFor(String host, {String scheme = 'http'}) {
    final fixed = fixedBaseUrl;
    if (fixed != null && fixed.isNotEmpty) return fixed;
    return '$scheme://$host:$port$path';
  }

  bool get isOfficial => group == RelayGroup.official;

  /// 第三方公共站点，不是自己部署的项目。
  bool get isPublicInstance => group == RelayGroup.welfare;

  /// 能力短标签，列表里一行放得下。
  List<String> get abilities => [
        if (vision) '视觉',
        if (search) '联网',
        if (tools) '工具',
      ];
}

/// 屏幕上的筛选标签。第一个是「全部」。
const List<String> kRelayTags = ['全部', '聚合', '国内', '海外', '本地', '官方', '公益'];

/// 预设库。
///
/// 收录标准：仓库当前可访问（2026-11 核对）。上一版里的 LLM-Red-Team
/// 全家桶（kimi/qwen/glm/deepseek-free-api）已整体下架，照着那条路部署
/// 只会看到 404，所以换成还在维护的实现。端口取自各项目 README，
/// 8000 / 3000 / 8080 被多个项目共用，同一台机器只能起一个。
const List<RelayPreset> kRelayPresets = [
  // ------------------------------------------------------------ 网页版反代
  RelayPreset(
    id: 'chatgpt2api',
    name: 'ChatGPT2API',
    owner: 'basketikun/chatgpt2api',
    summary: 'ChatGPT 官网能力转 OpenAI 接口，文本与图片生成都覆盖，自带号池与控制台。',
    deploy:
        'git clone https://github.com/basketikun/chatgpt2api\ncd chatgpt2api && docker compose up -d\n控制台 http://127.0.0.1:3000',
    port: 3000,
    auth: RelayAuth.optional,
    keyHint: '控制台里设置的访问令牌，未开启校验可留空',
    models: ['gpt-5', 'gpt-4o', 'gpt-image-1'],
    tags: ['海外'],
    vision: true,
    tools: true,
    repoUrl: 'https://github.com/basketikun/chatgpt2api',
  ),
  RelayPreset(
    id: 'chat2api-multi',
    name: 'Chat2API 多平台',
    owner: 'xiaoY233/Chat2API',
    summary: '桌面端一次登录 DeepSeek / GLM / Kimi / MiniMax / Qwen / Z.ai，改模型名就换家。',
    deploy: '下载 Release 桌面端并登录各家网页版\n接口默认 127.0.0.1:3000/v1，端口以启动页为准',
    port: 3000,
    auth: RelayAuth.optional,
    keyHint: '桌面端生成的本地密钥，未开启校验可留空',
    models: ['deepseek', 'glm', 'kimi', 'minimax', 'qwen', 'zai'],
    tags: ['聚合', '国内'],
    vision: true,
    tools: true,
    repoUrl: 'https://github.com/xiaoY233/Chat2API',
  ),
  RelayPreset(
    id: 'gemini-web2api',
    name: 'gemini-web2api',
    owner: 'Sophomoresty/gemini-web2api',
    summary: '单文件 Python，把 Gemini 网页版转成接口；默认零鉴权，支持函数调用与联网。',
    deploy:
        'git clone https://github.com/Sophomoresty/gemini-web2api\ncd gemini-web2api && python server.py\n默认 8081 端口',
    port: 8081,
    auth: RelayAuth.none,
    keyHint: '无需密钥（Pro 模型需自行填 Cookie）',
    models: ['gemini-3-flash', 'gemini-3-pro', 'gemini-2.5-flash'],
    tags: ['海外'],
    vision: true,
    search: true,
    tools: true,
    repoUrl: 'https://github.com/Sophomoresty/gemini-web2api',
  ),
  RelayPreset(
    id: 'chat2api',
    name: 'chat2api',
    owner: 'LanQian528/chat2api',
    summary: '较早的 ChatGPT 网页会话实现，支持 GPT-4o 与图片理解，Docker 一条命令。',
    deploy:
        'docker run -d --name chat2api \\\n  -p 5005:5005 lanqian528/chat2api:latest',
    port: 5005,
    auth: RelayAuth.optional,
    keyHint: 'AUTHORIZATION 环境变量或 accessToken，免登录可留空',
    models: ['gpt-4o', 'gpt-4o-mini', 'o3-mini', 'gpt-4.1'],
    tags: ['海外'],
    vision: true,
    repoUrl: 'https://github.com/LanQian528/chat2api',
  ),
  RelayPreset(
    id: 'aurora',
    name: 'Aurora',
    owner: 'aurora-develop/aurora',
    summary: 'Go 写的 ChatGPT 网页版反向代理，启动即用，资源占用低。',
    deploy:
        'git clone https://github.com/aurora-develop/aurora\ncd aurora && go run main.go   # 默认 8080',
    port: 8080,
    auth: RelayAuth.optional,
    keyHint: '配置文件里的 authorization，未开启校验可留空',
    models: ['gpt-4o-mini', 'gpt-4o'],
    tags: ['海外'],
    vision: true,
    repoUrl: 'https://github.com/aurora-develop/aurora',
  ),
  RelayPreset(
    id: 'webai2api',
    name: 'WebAI2API',
    owner: 'foxhui/WebAI2API',
    summary: '用浏览器自动化驱动 LMArena、Gemini、DeepSeek 等网页版，多窗口隔离。',
    deploy:
        'git clone https://github.com/foxhui/WebAI2API\ncd WebAI2API && npm i && npm start\n需要 Node 20+ 与 Xvfb，登录走 VNC',
    port: 8000,
    auth: RelayAuth.optional,
    keyHint: '面板里配置的访问密钥，未开启校验可留空',
    models: ['lmarena-auto', 'gemini-3-pro', 'deepseek-v4'],
    tags: ['聚合', '海外'],
    vision: true,
    tools: true,
    repoUrl: 'https://github.com/foxhui/WebAI2API',
  ),
  RelayPreset(
    id: 'copilot-api',
    name: 'copilot-api',
    owner: 'ericc-ch/copilot-api',
    summary: 'GitHub Copilot 订阅转接口，服务自己完成 GitHub 授权，客户端不用填 Key。',
    deploy: 'npx copilot-api@latest start --port 4141',
    port: 4141,
    auth: RelayAuth.none,
    keyHint: '无需密钥，服务持有 GitHub 授权',
    models: ['gpt-4.1', 'gpt-4o', 'o3-mini', 'claude-3.5-sonnet'],
    tags: ['海外'],
    tools: true,
    repoUrl: 'https://github.com/ericc-ch/copilot-api',
  ),
  RelayPreset(
    id: 'pandora',
    name: 'PandoraNext',
    owner: 'pandora-next/deploy',
    summary: '早期最完整的 ChatGPT 网页版反代，已停更；仍有老部署在跑，新装不建议。',
    deploy:
        'docker run -d -p 8181:8181 \\\n  -v /opt/pandora:/data pengzhile/pandora-next',
    port: 8181,
    auth: RelayAuth.optional,
    keyHint: 'PandoraNext 的 License Id 或代理令牌',
    models: ['gpt-4o', 'gpt-4o-mini'],
    tags: ['海外'],
    vision: true,
    archived: true,
    repoUrl: 'https://github.com/pandora-next/deploy',
  ),

  // ------------------------------------------------------------ 自建网关
  RelayPreset(
    id: 'g4f',
    name: 'gpt4free',
    owner: 'xtekky/g4f',
    summary: '把一批免费供应商聚到一个端点，启动后直接有模型列表，不需要密钥。',
    deploy: 'pip install -U "g4f[all]"\npython -m g4f --port 1337',
    port: 1337,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: [
      'gpt-4o-mini',
      'gpt-4o',
      'deepseek-v3',
      'gemini-2.5-pro',
      'llama-3.3-70b'
    ],
    tags: ['聚合', '海外'],
    vision: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/xtekky/gpt4free',
  ),
  RelayPreset(
    id: 'cliproxyapi',
    name: 'CLIProxyAPI',
    owner: 'router-for-me/CLIProxyAPI',
    summary: '把 Gemini CLI、Codex、Claude Code 的登录态转成接口，模型名直接写 gemini-* / gpt-*。',
    deploy: './cli-proxy-api --login\n./cli-proxy-api   # 默认 8317',
    port: 8317,
    auth: RelayAuth.optional,
    keyHint: 'config.yaml 里配置的 api-keys，未配置可留空',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gpt-5'],
    tags: ['海外'],
    vision: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/router-for-me/CLIProxyAPI',
  ),
  RelayPreset(
    id: 'one-api',
    name: 'One API',
    owner: 'songquanpeng/one-api',
    summary: '自建聚合网关，把多个官方渠道收成一个地址，适合长期用。',
    deploy:
        'docker run -d --name one-api -p 3000:3000 \\\n  -v /opt/one-api:/data justsong/one-api:latest',
    port: 3000,
    auth: RelayAuth.required,
    keyHint: '面板「令牌」页生成的 sk- 开头令牌',
    models: ['gpt-4o', 'deepseek-chat', 'qwen-max'],
    tags: ['聚合'],
    tools: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/songquanpeng/one-api',
  ),
  RelayPreset(
    id: 'new-api',
    name: 'New API',
    owner: 'Calcium-Ion/new-api',
    summary: 'One API 的分支，界面与计费更现代，支持按模型倍率与渠道分组。',
    deploy:
        'docker run -d --name new-api -p 3000:3000 \\\n  -v /opt/new-api:/data calciumion/new-api:latest',
    port: 3000,
    auth: RelayAuth.required,
    keyHint: '控制台「令牌」页生成的 sk- 令牌',
    models: ['gpt-4o', 'deepseek-chat', 'glm-4-flash'],
    tags: ['聚合'],
    tools: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/Calcium-Ion/new-api',
  ),
  RelayPreset(
    id: 'litellm',
    name: 'LiteLLM Proxy',
    owner: 'BerriAI/litellm',
    summary: '百来家供应商统一成 OpenAI 格式，带预算、限流与回落，工程上最省心。',
    deploy: 'pip install "litellm[proxy]"\nlitellm --port 4000',
    port: 4000,
    auth: RelayAuth.required,
    keyHint: '启动时 --api-key 或 config.yaml 里的 master_key',
    models: ['gpt-4o-mini', 'claude-sonnet-4-5', 'deepseek-chat'],
    tags: ['聚合'],
    vision: true,
    tools: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/BerriAI/litellm',
  ),
  RelayPreset(
    id: 'portkey',
    name: 'Portkey Gateway',
    owner: 'Portkey-AI/gateway',
    summary: '开源 AI 网关，1600+ 模型，带缓存、重试与可观测，Node 部署。',
    deploy: 'docker run -d -p 8787:8787 portkeyai/gateway:latest',
    port: 8787,
    auth: RelayAuth.optional,
    keyHint: '配置里的 Authorization，本地可留空',
    models: ['gpt-4o-mini', 'claude-sonnet-4-5', 'gemini-2.5-flash'],
    tags: ['聚合'],
    tools: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/Portkey-AI/gateway',
  ),
  RelayPreset(
    id: 'gpt-load',
    name: 'gpt-load',
    owner: 'tbphp/gpt-load',
    summary: '多密钥轮询与负载均衡，前面挂一堆上游 Key，对外只暴露一个地址。',
    deploy:
        'docker run -d -p 3001:3001 \\\n  -e AUTH_KEY=your-key tbphp/gpt-load:latest',
    port: 3001,
    auth: RelayAuth.required,
    keyHint: '启动时设置的 AUTH_KEY',
    models: ['gpt-4o-mini', 'deepseek-chat'],
    tags: ['聚合'],
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/tbphp/gpt-load',
  ),
  RelayPreset(
    id: 'gemini-balance',
    name: 'Gemini Balance',
    owner: 'snailyp/gemini-balance',
    summary: '多组 Gemini Key 轮询与故障转移，兼容 OpenAI 请求格式。',
    deploy:
        'docker run -d -p 8000:8000 \\\n  -v /opt/gb:/app/data snailyp/gemini-balance:latest',
    port: 8000,
    auth: RelayAuth.required,
    keyHint: '后台设置的 API_KEY',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
    tags: ['海外'],
    vision: true,
    group: RelayGroup.gateway,
    repoUrl: 'https://github.com/snailyp/gemini-balance',
  ),

  // ------------------------------------------------------------ 官方接口
  RelayPreset(
    id: 'deepseek-official',
    name: 'DeepSeek 官方',
    owner: 'deepseek.com',
    summary: '官方接口，按量计费但单价低，新账号常送体验额度；比逆向稳，也不担心封号。',
    deploy: 'platform.deepseek.com 申请 Key\n地址固定为 https://api.deepseek.com/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.deepseek.com/v1',
    auth: RelayAuth.required,
    keyHint: 'sk-… 开头的官方 Key',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    tags: ['官方', '国内'],
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://platform.deepseek.com',
  ),
  RelayPreset(
    id: 'glm-official',
    name: '智谱 GLM',
    owner: 'bigmodel.cn',
    summary: 'glm-4-flash 系列长期免费，注册即可用，适合当日常轻量主力。',
    deploy: 'open.bigmodel.cn 申请 Key\n地址固定为 .../api/paas/v4',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    auth: RelayAuth.required,
    keyHint: 'API Key（形如 xxx.yyy）',
    models: ['glm-4.7-flash', 'glm-4.6', 'glm-4v'],
    tags: ['官方', '国内'],
    vision: true,
    group: RelayGroup.official,
    repoUrl: 'https://open.bigmodel.cn',
  ),
  RelayPreset(
    id: 'siliconflow',
    name: '硅基流动',
    owner: 'siliconflow.cn',
    summary: '国内聚合云，注册送额度，开源模型齐全，OpenAI 格式直连。',
    deploy: 'cloud.siliconflow.cn 申请 Key\n地址固定为 https://api.siliconflow.cn/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.siliconflow.cn/v1',
    auth: RelayAuth.required,
    keyHint: 'sk-… 开头的平台 Key',
    models: ['Qwen/Qwen3-8B', 'deepseek-ai/DeepSeek-V3'],
    tags: ['官方', '国内'],
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://cloud.siliconflow.cn',
  ),
  RelayPreset(
    id: 'groq-official',
    name: 'Groq',
    owner: 'groq.com',
    summary: '免费额度按天给，LPU 推理极快；gpt-oss 与 Llama 都在免费档里。',
    deploy: 'console.groq.com 申请 Key\n地址固定为 https://api.groq.com/openai/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.groq.com/openai/v1',
    auth: RelayAuth.required,
    keyHint: 'gsk_ 开头的 Key',
    models: [
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-120b',
      'qwen/qwen3-32b'
    ],
    tags: ['官方', '海外'],
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://console.groq.com',
  ),
  RelayPreset(
    id: 'cerebras-official',
    name: 'Cerebras',
    owner: 'cerebras.ai',
    summary: '免费档每天百万级 token，推理速度是这批里最快的，适合长输出。',
    deploy: 'cloud.cerebras.ai 申请 Key\n地址固定为 https://api.cerebras.ai/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.cerebras.ai/v1',
    auth: RelayAuth.required,
    keyHint: 'csk- 开头的 Key',
    models: ['llama-3.3-70b', 'qwen-3-32b', 'gpt-oss-120b'],
    tags: ['官方', '海外'],
    group: RelayGroup.official,
    repoUrl: 'https://cloud.cerebras.ai',
  ),
  RelayPreset(
    id: 'google-ai-studio',
    name: 'Google AI Studio',
    owner: 'ai.google.dev',
    summary: 'Gemini 免费档，OpenAI 兼容路径直连，读图与长上下文都能用。',
    deploy: 'aistudio.google.com 申请 Key\n地址固定为 .../v1beta/openai',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    auth: RelayAuth.required,
    keyHint: 'AIza 开头的 Key',
    models: ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash'],
    tags: ['官方', '海外'],
    vision: true,
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://aistudio.google.com',
  ),
  RelayPreset(
    id: 'mistral-official',
    name: 'Mistral',
    owner: 'mistral.ai',
    summary: '免费实验档含 Large 与 Codestral，欧洲线路，中文一般但代码强。',
    deploy: 'console.mistral.ai 申请 Key\n地址固定为 https://api.mistral.ai/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.mistral.ai/v1',
    auth: RelayAuth.required,
    keyHint: '平台 Key',
    models: ['mistral-large-latest', 'codestral-latest', 'ministral-8b-latest'],
    tags: ['官方', '海外'],
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://console.mistral.ai',
  ),
  RelayPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    owner: 'openrouter.ai',
    summary: '一个 Key 打通上百家；带 :free 后缀的模型不收钱，代价是限流。',
    deploy: 'openrouter.ai/keys 申请 Key\n地址固定为 https://openrouter.ai/api/v1',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://openrouter.ai/api/v1',
    auth: RelayAuth.required,
    keyHint: 'sk-or- 开头的 Key',
    models: [
      'deepseek/deepseek-chat-v3.1:free',
      'z-ai/glm-4.6:free',
      'qwen/qwen3-235b:free'
    ],
    tags: ['官方', '海外'],
    tools: true,
    group: RelayGroup.official,
    repoUrl: 'https://openrouter.ai/keys',
  ),

  // ------------------------------------------------------------ 公益实例
  // 第三方公共站点：地址固定、要用对方发放的 Key、随时可能改规则。
  // 这里只列 2026-11 实测能连通的站点，界面上会标「在线 / 需密钥」。
  RelayPreset(
    id: 'pub-gptge',
    name: 'GPT.ge',
    owner: '第三方公共站',
    summary: '老牌公共中转，模型覆盖广；需要站点发放的 Key，免费额度按活动变化。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.gpt.ge/v1',
    auth: RelayAuth.required,
    keyHint: '站点后台生成的 sk- 令牌',
    models: ['gpt-4o-mini', 'gpt-4o', 'deepseek-chat'],
    tags: ['公益'],
    vision: true,
    group: RelayGroup.welfare,
    repoUrl: 'https://api.gpt.ge',
  ),
  RelayPreset(
    id: 'pub-poixe',
    name: 'Poixe',
    owner: '第三方公共站',
    summary: '按天给免费额度的中转，Gemini 系列齐全，支持图片模型。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.poixe.com/v1',
    auth: RelayAuth.required,
    keyHint: '注册后控制台里的 KEY',
    models: ['gemini-3.6-flash', 'gemini-3.5-flash-lite', 'gemini-3-pro-image'],
    tags: ['公益', '海外'],
    vision: true,
    group: RelayGroup.welfare,
    repoUrl: 'https://poixe.com',
  ),
  RelayPreset(
    id: 'pub-xkiro',
    name: 'xKiro Hub',
    owner: '第三方公共站',
    summary: '面向 Claude Code 的免费额度中转，也提供 OpenAI 兼容路径。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.xkiro.com/v1',
    auth: RelayAuth.required,
    keyHint: '站点发放的 ClientApiKey',
    models: ['google/gemini-3.6-flash', 'claude-sonnet-4-5'],
    tags: ['公益', '海外'],
    vision: true,
    tools: true,
    group: RelayGroup.welfare,
    repoUrl: 'https://xkiro.com',
  ),
  RelayPreset(
    id: 'pub-chatanywhere',
    name: 'ChatAnywhere',
    owner: '第三方公共站',
    summary: '长期提供免费的 GPT-3.5 / 4o-mini 额度，Key 免费申请，适合试水。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.chatanywhere.tech/v1',
    auth: RelayAuth.required,
    keyHint: 'GitHub 登录后领取的免费 Key',
    models: ['gpt-4o-mini', 'gpt-3.5-turbo'],
    tags: ['公益'],
    group: RelayGroup.welfare,
    repoUrl: 'https://api.chatanywhere.tech',
  ),
  RelayPreset(
    id: 'pub-mnapi',
    name: 'MN API',
    owner: '第三方公共站',
    summary: '国内可直连的公共中转，注册送额度，按量计费。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://api.mnapi.com/v1',
    auth: RelayAuth.required,
    keyHint: '控制台令牌',
    models: ['gpt-4o-mini', 'claude-sonnet-4-5', 'gemini-2.5-flash'],
    tags: ['公益', '国内'],
    group: RelayGroup.welfare,
    repoUrl: 'https://api.mnapi.com',
  ),
  RelayPreset(
    id: 'pub-v36',
    name: 'V36 中转',
    owner: '第三方公共站',
    summary: '公共中转之一，稳定性一般，胜在免费额度容易拿，适合当备用。',
    deploy: '',
    port: 443,
    path: '',
    fixedBaseUrl: 'https://free.v36.cm/v1',
    auth: RelayAuth.required,
    keyHint: '站点发放的令牌',
    models: ['gpt-4o-mini', 'deepseek-chat'],
    tags: ['公益', '国内'],
    group: RelayGroup.welfare,
    repoUrl: 'https://free.v36.cm',
  ),

  // ------------------------------------------------------------ 本机推理
  RelayPreset(
    id: 'ollama',
    name: 'Ollama',
    owner: 'ollama/ollama',
    summary: '本机跑开源模型，官方自带 OpenAI 兼容层，断网也能用。',
    deploy: 'ollama serve\nollama pull qwen3',
    port: 11434,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: ['qwen3', 'llama3.3', 'deepseek-r1'],
    tags: ['本地'],
    tools: true,
    group: RelayGroup.local,
    repoUrl: 'https://github.com/ollama/ollama',
  ),
  RelayPreset(
    id: 'lmstudio',
    name: 'LM Studio',
    owner: 'lmstudio-ai',
    summary: '桌面端加载本地模型，开服务后走 OpenAI 格式。',
    deploy: 'LM Studio → Developer → Start Server\n默认 1234 端口',
    port: 1234,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: ['local-model'],
    tags: ['本地'],
    group: RelayGroup.local,
    repoUrl: 'https://lmstudio.ai',
  ),
  RelayPreset(
    id: 'vllm',
    name: 'vLLM',
    owner: 'vllm-project/vllm',
    summary: 'GPU 上跑高吞吐推理，自带 OpenAI 服务端，适合有显卡的机器。',
    deploy: 'pip install vllm\nvllm serve Qwen/Qwen3-8B --port 8000',
    port: 8000,
    auth: RelayAuth.none,
    keyHint: '无需密钥（可用 --api-key 开启）',
    models: ['Qwen/Qwen3-8B'],
    tags: ['本地'],
    tools: true,
    group: RelayGroup.local,
    repoUrl: 'https://github.com/vllm-project/vllm',
  ),
  RelayPreset(
    id: 'llamacpp',
    name: 'llama.cpp server',
    owner: 'ggml-org/llama.cpp',
    summary: 'GGUF 单机推理，CPU 也能跑，一条命令起 OpenAI 兼容服务。',
    deploy: 'llama-server -m model.gguf --port 8080',
    port: 8080,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: ['local-model'],
    tags: ['本地'],
    group: RelayGroup.local,
    repoUrl: 'https://github.com/ggml-org/llama.cpp',
  ),
  RelayPreset(
    id: 'localai',
    name: 'LocalAI',
    owner: 'mudler/LocalAI',
    summary: '本地一体化推理服务，文本、视觉、语音都有，镜像开箱可用。',
    deploy: 'docker run -d -p 8080:8080 localai/localai:latest',
    port: 8080,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: ['gpt-4', 'qwen3'],
    tags: ['本地'],
    vision: true,
    group: RelayGroup.local,
    repoUrl: 'https://github.com/mudler/LocalAI',
  ),
  RelayPreset(
    id: 'xinference',
    name: 'Xinference',
    owner: 'xorbitsai/inference',
    summary: '一个服务管多模型，自带 Web UI 与 OpenAI 接口，适合团队内部用。',
    deploy: 'pip install "xinference[all]"\nxinference-local --port 9997',
    port: 9997,
    auth: RelayAuth.none,
    keyHint: '无需密钥',
    models: ['qwen3-instruct'],
    tags: ['本地'],
    vision: true,
    group: RelayGroup.local,
    repoUrl: 'https://github.com/xorbitsai/inference',
  ),
  RelayPreset(
    id: 'open-webui',
    name: 'Open WebUI',
    owner: 'open-webui/open-webui',
    summary: '自带界面的本地聚合层，能接 Ollama 与任意 OpenAI 端点，也有兼容 API。',
    deploy:
        'docker run -d -p 8080:8080 \\\n  -v open-webui:/app/backend/data openwebui/open-webui:main',
    port: 8080,
    auth: RelayAuth.required,
    keyHint: '设置 → 账户 → API 密钥',
    models: ['gpt-4o-mini', 'qwen3'],
    tags: ['本地'],
    tools: true,
    group: RelayGroup.local,
    repoUrl: 'https://github.com/open-webui/open-webui',
  ),
];

/// 公益站导航仓库：持续更新各家中转的额度与可用性。
const String kWelfareIndexUrl =
    'https://github.com/panxunying/ai-coding-welfare';

/// 扫描时额外尝试的端口：常见网关与备用端口，不绑定具体预设。
const List<int> _extraPorts = [8080, 8001, 8002, 9000, 3001, 8181, 1234, 11434];

/// 一次探测的结果。
class RelayHit {
  final String baseUrl;
  final String host;
  final int port;
  final int latencyMs;
  final bool needsKey;
  final List<String> models;
  final RelayPreset? preset;
  final String label;

  const RelayHit({
    required this.baseUrl,
    required this.host,
    required this.port,
    required this.latencyMs,
    required this.needsKey,
    required this.models,
    this.preset,
    this.label = '',
  });

  String get title => preset?.name ?? (label.isEmpty ? '可用的兼容服务' : label);

  bool get ok => !needsKey;
}

class RelayTarget {
  final String host;
  final int? port;
  final String scheme;
  const RelayTarget(this.host, this.port, this.scheme);
}

/// 探测与扫描。全部走短超时，扫描十几个端口控制在几秒内。
class RelayProbe {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 1500),
    receiveTimeout: const Duration(milliseconds: 2600),
    sendTimeout: const Duration(milliseconds: 1500),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
    followRedirects: true,
  ));

  /// 从用户输入里抠出主机与端口。支持直接粘
  /// `http://192.168.1.5:8000/v1`、`192.168.1.5`、`localhost:5005`。
  static RelayTarget parseTarget(String raw) {
    var s = raw.trim();
    var scheme = 'http';
    if (s.contains('://')) {
      final i = s.indexOf('://');
      scheme = s.substring(0, i).toLowerCase();
      s = s.substring(i + 3);
    }
    s = s.split('/').first.split('?').first;
    if (s.startsWith('[')) {
      // IPv6 字面量：[::1]:8000
      final end = s.indexOf(']');
      if (end > 0) {
        final host = s.substring(1, end);
        final rest = s.substring(end + 1);
        final p = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
        return RelayTarget(host, p, scheme);
      }
    }
    final parts = s.split(':');
    if (parts.length == 2) {
      return RelayTarget(parts[0], int.tryParse(parts[1]), scheme);
    }
    return RelayTarget(s.isEmpty ? '127.0.0.1' : s, null, scheme);
  }

  static String _origin(RelayTarget t, int port) =>
      '${t.scheme}://${t.host}:$port';

  /// 候选模型地址，和 LlmClient 的解析保持一致：先原样，再补 /v1。
  static List<String> modelUrls(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) {
      b = b.substring(0, b.length - '/chat/completions'.length);
    }
    final out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    if (b.endsWith('/models')) {
      add(b);
      b = b.substring(0, b.length - '/models'.length);
    }
    add('$b/models');
    final hasVersion =
        RegExp(r'/v\d+[a-z0-9]*$', caseSensitive: false).hasMatch(b);
    if (!hasVersion) add('$b/v1/models');
    return out;
  }

  /// 兼容 OpenAI / Ollama / 纯数组三种返回。
  static List<String> parseModels(dynamic data) {
    dynamic v = data;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    List<dynamic>? raw;
    if (v is List) {
      raw = v;
    } else if (v is Map) {
      for (final k in const ['data', 'models', 'results', 'items']) {
        if (v[k] is List) {
          raw = v[k] as List<dynamic>;
          break;
        }
      }
    }
    if (raw == null) return const [];
    final out = <String>[];
    for (final e in raw) {
      if (e is String) {
        out.add(e);
      } else if (e is Map) {
        final id = e['id'] ?? e['name'] ?? e['model'] ?? e['slug'];
        if (id != null) out.add(id.toString());
      }
    }
    return out;
  }

  /// 探测一个地址是否是可用的 OpenAI 兼容端点。
  /// 200 视为可用；401/403 说明服务在跑但缺 Key，也返回，交给用户补。
  static Future<RelayHit?> probeUrl(
    String baseUrl, {
    String key = '',
    RelayPreset? preset,
    Duration timeout = const Duration(milliseconds: 2600),
  }) async {
    final urls = modelUrls(baseUrl);
    for (final url in urls) {
      final sw = Stopwatch()..start();
      try {
        final resp = await _dio.get<String>(
          url,
          options: Options(
            headers: <String, dynamic>{
              'Accept': 'application/json',
              if (key.trim().isNotEmpty)
                'Authorization': 'Bearer ${key.trim()}',
            },
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
        sw.stop();
        final code = resp.statusCode ?? 0;
        if (code == 200) {
          final models = parseModels(resp.data);
          return RelayHit(
            baseUrl: baseUrl,
            host: _hostOf(baseUrl),
            port: _portOf(baseUrl),
            latencyMs: sw.elapsedMilliseconds,
            needsKey: false,
            models: models,
            preset: preset,
          );
        }
        if (code == 401 || code == 403) {
          return RelayHit(
            baseUrl: baseUrl,
            host: _hostOf(baseUrl),
            port: _portOf(baseUrl),
            latencyMs: sw.elapsedMilliseconds,
            needsKey: true,
            models: const [],
            preset: preset,
          );
        }
      } on DioException {
        sw.stop();
        // 连接被拒或超时：换路径也不会通，直接判这台端口没服务。
        return null;
      }
    }
    return null;
  }

  /// 一键测试：并发探测一批固定地址的预设（公益站、官方接口）。
  ///
  /// 和 [scan] 的区别是不扫端口，只测预设里写死的地址，十几条一起发，
  /// 三秒内能出结果。
  static Future<Map<String, RelayHit?>> probeAll(
    List<RelayPreset> presets, {
    String key = '',
    ValueChanged<double>? onProgress,
  }) async {
    final out = <String, RelayHit?>{};
    if (presets.isEmpty) return out;
    var done = 0;
    const batch = 4;
    for (var i = 0; i < presets.length; i += batch) {
      final chunk = presets.skip(i).take(batch).toList();
      final part = await Future.wait(chunk.map((p) async {
        final base = p.fixedBaseUrl ?? '';
        if (base.isEmpty) return null;
        return probeUrl(base,
            key: key, preset: p, timeout: const Duration(milliseconds: 6000));
      }));
      for (var j = 0; j < chunk.length; j++) {
        out[chunk[j].id] = part[j];
      }
      done += chunk.length;
      onProgress?.call(done / presets.length);
    }
    return out;
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  static int _portOf(String url) {
    try {
      final u = Uri.parse(url);
      return u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
    } catch (_) {
      return 0;
    }
  }

  /// 扫描一台主机上的常见端口。返回按端口排序的命中列表。
  ///
  /// [onProgress] 回调 0~1 的进度，用于画进度条；扫描本身是分批并发，
  /// 每批 6 个，既不会把手机连接数打满，也不会让单端口超时拖住整轮。
  static Future<List<RelayHit>> scan({
    required String host,
    String key = '',
    List<RelayPreset> presets = kRelayPresets,
    ValueChanged<double>? onProgress,
  }) async {
    final target = parseTarget(host);
    if (target.host.isEmpty) return const [];

    // 端口 → 该端口对应的预设。8000 上可能同时是 kimi/qwen/glm，
    // 这时不猜，交给返回的模型名判断。
    final byPort = <int, List<RelayPreset>>{};
    for (final p in presets) {
      if (p.fixedBaseUrl != null) continue;
      byPort.putIfAbsent(p.port, () => <RelayPreset>[]).add(p);
    }

    final ports = <int>[];
    if (target.port != null) {
      ports.add(target.port!);
    } else {
      ports.addAll(byPort.keys);
      for (final p in _extraPorts) {
        if (!ports.contains(p)) ports.add(p);
      }
    }
    ports.sort();

    final hits = <RelayHit>[];
    const batch = 6;
    var done = 0;
    for (var i = 0; i < ports.length; i += batch) {
      final chunk = ports.skip(i).take(batch).toList();
      final results = await Future.wait(chunk.map((port) async {
        final list = byPort[port];
        final preset = (list != null && list.length == 1) ? list.first : null;
        final path = preset?.path ?? '/v1';
        final base = '${_origin(target, port)}$path';
        final hit = await probeUrl(base, key: key, preset: preset);
        if (hit != null) return hit;
        // 预设路径没通，再试一次根路径（部分网关不挂 /v1）。
        if (path != '') {
          return probeUrl(_origin(target, port), key: key, preset: preset);
        }
        return null;
      }));
      for (final h in results) {
        if (h != null) hits.add(h);
      }
      done += chunk.length;
      onProgress?.call(done / ports.length);
    }

    hits.sort((a, b) => a.port.compareTo(b.port));
    return hits;
  }

  /// 判断某个地址是不是「本机回环」——手机上的 127.0.0.1 指向手机自己，
  /// 而不是跑反代的电脑，UI 需要就此给出提示。
  static bool isLoopback(String host) {
    final h = host.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  /// 内网地址判定：只有这类主机才值得扫端口，公网域名扫了也是白扫。
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.startsWith('127.')) return true;
    if (h.endsWith('.local')) return true;
    final parts = h.split('.');
    if (parts.length == 4) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == 10) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b != null && b >= 16 && b <= 31) return true;
    }
    return false;
  }

  /// 从当前连接地址里猜一个可复用的主机名，作为扫描框默认值。
  /// 当前连的是公网 API 时直接回落到 127.0.0.1，不去扫对方。
  static String guessHost(String baseUrl) {
    try {
      final u = Uri.parse(baseUrl);
      if (u.host.isNotEmpty && isPrivateHost(u.host)) return u.host;
    } catch (_) {}
    return '127.0.0.1';
  }
}
