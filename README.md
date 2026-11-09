<div align="center">

# Aigent

**一个把「聊天」做成日常工具的 Android AI 客户端。**

自带连接管理、语音输入与朗读、深度研究工作流、设备智能体、AI 圆桌会议与模拟人生，以及 40 种界面语言与 19 套主题。

[![CI](https://github.com/asujdgg/aigent/actions/workflows/ci.yml/badge.svg)](https://github.com/asujdgg/aigent/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/asujdgg/aigent)](https://github.com/asujdgg/aigent/releases)

Flutter 3.24 · Android 6.0+ · 本地存储 · 无账号 · 无遥测

</div>

---

## 它是什么

Aigent 不是又一个「套壳聊天框」。它把日常真正会用到的部分做成了一个完整的客户端：

| 能力 | 说明 |
|---|---|
| **多连接** | 任意 OpenAI 兼容接口都可以存成一条「连接」，随时切换，互不覆盖 |
| **模型选择** | 输入框上方的模型条一点即换，支持搜索与跨连接查找 |
| **语音输入** | 说完静音自动停止，识别结果先落进输入框，确认后再发送 |
| **朗读** | 微软 Edge / 系统 TTS / OpenAI / ElevenLabs / Azure 五种引擎，长文分段边播边合成 |
| **深度研究** | 多轮检索 → 拟定大纲 → 逐节展开 → 汇总报告，可随时中断 |
| **AI 圆桌会议** | 一个议题，选 3–5 个不同模型 / 连接按大纲多轮讨论，后发言者能看到前面观点，主持人汇总共识、分歧与建议，纪要可导出 |
| **模拟人生** | AI 实时生成人生事件与 2–3 个抉择，六维属性随选择涨落，可存档、续玩、导出传记 |
| **设备智能体** | 读取本机信息，在隔离工作区读写文件、打开应用与网页、建日程、设闹钟，每次都要你确认 |
| **联网搜索** | Serper / Tavily / Exa / Brave / Bing 多源可选，每源独立密钥与连通性测试 |
| **界面** | 40 种界面语言（含小语种）、19 套主题 + 自定义配色、85%–140% 字号 |

**直接安装**：到 [Releases](https://github.com/asujdgg/aigent/releases) 下载最新 APK，在 Android 手机上安装即可，不需要账号，也不需要登录。

所有请求由手机直接发往你配置的接口。API Key 用 AES 加密后只存本机，不同步、不上传。

## 快速上手

1. 到 [Releases](https://github.com/asujdgg/aigent/releases) 下载 `Aigent-v4.23.0.apk`，Android 6.0+ 直接安装，无需注册。
2. 打开左上角菜单 → **设置 → 连接与模型**，新增一条连接：填接口地址（OpenAI 兼容，一般带 `/v1`）、API Key、模型 ID。
3. 回到主页点输入框上方的**模型条**选中它，就能开始对话。

完整的安装、各功能用法、个性化设置与常见问题见 **[使用指南](USAGE.md)**。

## 文档

| 文档 | 内容 |
|---|---|
| [使用指南](USAGE.md) | 安装、配连接、语音 / 朗读 / 研究 / 智能体 / 圆桌会议 / 模拟人生、主题字号语言、常见问题 |
| [README](README.md) | 项目介绍、构建、目录结构、语言机制 |
| [更新日志](CHANGELOG.md) | 各版本变更 |
| [贡献指南](CONTRIBUTING.md) | 开发环境、质量门、文案规矩、PR 清单 |
| [安全政策](SECURITY.md) | 漏洞报告方式与已知边界 |
| [第三方许可](THIRD_PARTY_LICENSES.md) | 随包资源与依赖的许可说明 |
| [许可证](LICENSE) | MIT |

## 构建

需要 Flutter **3.24.x**（Dart 3.5.4）、Android SDK 与 JDK 17。

```bash
git clone https://github.com/asujdgg/aigent.git
cd aigent
flutter pub get
flutter run --release
```

国内网络可先设镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

打包 APK：

```bash
./build.sh          # 检查版本号一致性 → 静态分析 → 测试 → 输出 Aigent-v<版本>.apk
```

质量门也可以单独跑：

```bash
python3 tool/check_i18n.py   # 376 条界面词条 × 38 份词表零缺失
flutter analyze
flutter test
```

> `assets/speech/vosk-model-small-cn-0.22.zip`（约 42 MB）是离线中文语音模型，随仓库分发并打进 APK，首次使用在设备本地解压，不联网下载。

## 目录

```
lib/
├── main.dart               应用入口：主题、字号、界面语言的全局注入
├── skin.dart / theme.dart  19 套主题、自定义配色与页面转场
├── i18n.dart / i18n/       查表逻辑 t() 与英文词表
├── models/                 数据模型与持久化
├── services/               LLM 流式、搜索、语音、圆桌会议编排、人生模拟、本地存档
├── state/                  AppState（唯一可变状态源）
└── ui/                     页面与组件（含圆桌会议页、人生模拟页）
assets/i18n/                40 种界面语言词表（TSV，中文原文为 key）
assets/speech/              Vosk 中文离线语音模型
assets/brand_models/        模型品牌图标
android/                    Kotlin 原生层：录音 VAD、TTS、设备能力
test/                       268 项单元与组件测试
tool/                       品牌图标、词表生成与源码打包脚本
```

## 界面语言的机制

词表以**中文原文**为 key：`t('复制')`。查表顺序是「当前语言 → 英文 → 中文原文」。

- 漏翻不会显示 `settings.copy` 这种 key，最差也是英文。
- 新增文案：写 `t('中文')`，在 `lib/i18n/en.dart` 补一条英文，再跑 `python3 tool/gen_i18n.py` 生成其余语言。
- 用 `python3 tool/check_i18n.py` 校验 376 条界面词条零缺失；发现别扭的译文，直接改 `assets/i18n/<code>.tsv` 并提 PR。

## 隐私

- 不收集任何使用数据，没有统计 SDK。
- 对话内容只存在本机 `shared_preferences` 与沙箱目录。
- 语音默认走系统识别或微软免费通道；离线识别用随包内置的 Vosk 模型，首次使用本地解压，之后完全离线。
- 「设备智能体」的所有写操作都需要你在屏幕上点确认。

## 已知边界

- 只支持 Android。iOS 需要重写原生层的录音与设备能力。
- 语音识别依赖系统或第三方服务，安静环境下准确率最好。
- 界面语言里，日 / 韩 / 法 / 德 / 西 / 葡 / 俄 / 意 / 阿 / 印地为核心人工校对，其余为机器翻译；14 条含变量插值的提示语仍显示中文原文。
- 深度研究的效果取决于你接的模型与搜索源。
- 当前 Release APK 使用 debug 签名，仅供自行安装体验；若要上架，请配置自己的签名密钥。

## 贡献

1. Fork，从 `main` 切一个分支。
2. `flutter analyze` 必须 0 问题，`flutter test` 必须全绿。
3. 涉及界面文案的改动，记得同步 `lib/i18n/en.dart` 与词表。
4. 提交 PR，说明改了什么、为什么。

## 许可证

本项目代码采用 **MIT**，见 [LICENSE](LICENSE)。仓库内另含第三方资源，各自适用其许可：

| 资源 | 用途 | 说明 |
|---|---|---|
| [Vosk vosk-model-small-cn-0.22](https://alphacephei.com/vosk/models) | 离线中文语音识别 | 随上游模型分发，许可见 Vosk 官方模型页 |
| [LobeHub Icons](https://github.com/lobehub/lobe-icons) | 模型品牌图标 | MIT，仅用于标识对应模型，版权归各厂商所有 |
| Syncfusion Flutter PDF | 应用内 PDF 解析 | 适用 Syncfusion 自有许可，商用前请自行确认授权条款 |

第三方资源不因本仓库的 MIT 许可而自动获得再授权。
