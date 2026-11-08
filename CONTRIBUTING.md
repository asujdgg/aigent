# 贡献指南

欢迎提 Issue 和 PR。这是一个单人维护的 Flutter Android 应用，「简单、能跑、可验证」比堆功能更重要。

## 开发环境

- Flutter **3.24.5** / Dart 3.5.4（CI 固定 3.24.5）
- JDK 17 + Android SDK
- 离线语音模型 `assets/speech/vosk-model-small-cn-0.22.zip`（42 MB）随仓库分发，clone 后无需额外下载

```bash
git clone https://github.com/asujdgg/aigent.git
cd aigent
flutter pub get
flutter run
```

国内网络可先设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 镜像，见 [README](README.md#构建)。

## 提交前必跑

```bash
python3 tool/check_i18n.py   # 300 条核心词条 × 38 份词表零缺失
flutter analyze              # 必须 0 问题
flutter test                 # 必须全绿（当前 228 项）
```

`./build.sh` 会串起版本一致性检查、静态分析与测试再出包。GitHub Actions 对 `main` 的推送和每个 PR 都会跑同样的三项。

## 分支与提交

- 从 `main` 切分支，命名 `fix/xxx`、`feat/xxx`、`i18n/xxx`
- 提交信息用一句祈使句说清「改了什么」，必要时在正文写「为什么」
- 一个 PR 只做一件事；不要顺手格式化无关文件

## 改界面文案的规矩

所有用户可见文案都走 `t('中文原文')`，词表以中文原文为 key，查表顺序是「当前语言 → 英文 → 中文原文」。

1. 代码里写 `t('中文')`
2. 在 `lib/i18n/en.dart` 补一条英文
3. 跑 `python3 tool/gen_i18n.py` 生成其余语言词表
4. 跑 `python3 tool/check_i18n.py` 确认零缺失

直接改 `assets/i18n/<code>.tsv` 修正生硬译文非常欢迎。注意：14 条含变量插值的提示语目前仍显示中文原文，改动时请一并留意。

## PR 检查清单

- [ ] `flutter analyze` 0 问题，`flutter test` 全绿
- [ ] 涉及文案已同步英文词表，词表校验通过
- [ ] 窄屏（110% / 138% 字号）下没有溢出
- [ ] 没有把 API Key、本机路径、签名文件、APK 提交进来
- [ ] 说明了改动原因与验证方式

## 报告问题

用 [bug 模板](.github/ISSUE_TEMPLATE/bug_report.md)，带上机型、Android 版本、复现步骤、截图或日志。安全漏洞请看 [SECURITY](SECURITY.md)，不要公开提。

## 许可

贡献即表示同意你的代码以 [MIT](LICENSE) 许可发布。第三方资源各自适用其许可，见 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES.md)。
