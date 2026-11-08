# 第三方资源与许可

本项目自身代码采用 [MIT](LICENSE)。**MIT 不覆盖下列第三方资源**，它们各自适用自己的条款。

## 随仓库分发的资源

| 资源 | 位置 | 用途 | 许可 |
|---|---|---|---|
| Vosk `vosk-model-small-cn-0.22` | `assets/speech/*.zip` | 离线中文语音识别 | 上游模型自带许可，见 [Vosk 模型页](https://alphacephei.com/vosk/models) |
| [LobeHub Icons](https://github.com/lobehub/lobe-icons) 衍生图标 | `assets/brand_models/`、`assets/brand/` | 标识模型品牌 | MIT |
| 各模型厂商品牌标识 | 同上 | 仅用于标识对应模型 | 版权归各厂商所有，仅作识别用途 |
| `assets/source_bundle.json` | 应用内源码浏览 | 本项目自身源码打包 | MIT（本项目代码） |
| `assets/i18n/*.tsv` | 界面语言词表 | 机器翻译 + 人工校对的译文 | 随本项目分发 |

> 品牌图标只用来告诉用户「这条连接对应哪个模型」，不代表厂商背书或关联。

## pub 依赖

`pubspec.yaml` 中的依赖来自 pub.dev，各自许可以其仓库 LICENSE 为准（常见为 MIT / BSD-3-Clause / Apache-2.0）。主要依赖：

| 包 | 用途 |
|---|---|
| `provider` | 状态管理 |
| `dio` | HTTP / 流式请求 |
| `shared_preferences`、`encrypt`、`crypto` | 本地存储与凭据加密 |
| `flutter_markdown`、`url_launcher` | 富文本与外链 |
| `image_picker`、`file_picker`、`path_provider`、`path`、`archive` | 文件与路径 |
| `cupertino_icons` | 图标 |
| `syncfusion_flutter_pdf` | PDF 解析 |
| `flutter_lints`（dev） | 静态检查 |

**特别提示：`syncfusion_flutter_pdf` 适用 Syncfusion 自有许可**（社区许可有营收与团队规模条件，超出需商业授权）。商用前请自行核对 [Syncfusion 许可条款](https://www.syncfusion.com/licensing) 并确认合规——这是本项目唯一需要额外留意的依赖。

## 生成脚本

`tool/` 下的脚本在生成词表时可能调用机器翻译服务；生成的词表随仓库分发。你也可以直接修改 `assets/i18n/*.tsv` 修正译文。

## 本项目的承诺

- 不收集数据、无账号、无遥测，详见 [SECURITY](SECURITY.md)。
- 若你是上述资源的权利人、认为使用方式不妥，请开 Issue 说明，我们会调整或移除。
