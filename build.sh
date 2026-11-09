#!/usr/bin/env bash
# Aigent — 一键构建 Android Release APK
# 用法: ./build.sh            （使用系统默认源）
#       USE_CN_MIRROR=1 ./build.sh   （国内网络，走腾讯 / 阿里云镜像）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---------- 1. 定位 Flutter（工程要求 Dart 3.5+ / Flutter 3.24+） ----------
# 逐个探测候选并校验版本，避免 PATH 里存在旧版 Flutter 时误用。
pick_flutter() {
  for c in /opt/flutter324/bin/flutter "$(command -v flutter 2>/dev/null)" \
           "$HOME/flutter/bin/flutter" /opt/flutter/bin/flutter \
           /usr/local/flutter/bin/flutter; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    ver="$("$c" --version 2>/dev/null | grep -oE 'Flutter [0-9]+\.[0-9]+' | head -1)"
    major="$(echo "$ver" | grep -oE '[0-9]+' | head -1)"
    minor="$(echo "$ver" | grep -oE '[0-9]+' | tail -1)"
    if [ -n "$major" ] && [ -n "$minor" ]; then
      if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 24 ]; }; then
        echo "$c"
        return 0
      fi
    fi
  done
  return 1
}
FLUTTER_BIN="$(pick_flutter)"
if [ -z "$FLUTTER_BIN" ]; then
  echo "错误：未找到 Flutter 3.24+（本工程需要 Dart 3.5+），请安装后重试。" >&2
  exit 1
fi
FLUTTER_ROOT="$(dirname "$(dirname "$FLUTTER_BIN")")"
export PATH="$(dirname "$FLUTTER_BIN"):$PATH"

# ---------- 1.5 中文离线语音包（随包分发，缺失则补下载） ----------
# 源码包不含这 42 MB 模型（会让 zip 膨胀 80 倍），首次构建时自动取一份。
# 国内镜像优先：官方源在部分网络下只有十几 KB/s，实测基本下不完。
SPEECH_ZIP="$ROOT/assets/speech/vosk-model-small-cn-0.22.zip"
if [ ! -f "$SPEECH_ZIP" ]; then
  echo "==> 缺少中文离线语音包，开始下载（约 42 MB）"
  mkdir -p "$ROOT/assets/speech"
  curl -L --fail -m 900 -o "$SPEECH_ZIP" \
    "https://hf-mirror.com/xushunbin/vosk-model-cn-kaldi-multicn-0.15/resolve/main/vosk-model-small-cn-0.22.zip" \
    || curl -L --fail -m 900 -o "$SPEECH_ZIP" \
    "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip" \
    || { echo "警告：语音包下载失败，构建出的 APK 将不含离线识别。" >&2; rm -f "$SPEECH_ZIP"; }
fi

# ---------- 2. JDK 17（AGP 8.x 要求） ----------
if [ -d /opt/jdk17 ]; then
  export JAVA_HOME=/opt/jdk17
  export PATH="$JAVA_HOME/bin:$PATH"
elif [ -n "${JAVA_HOME:-}" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
else
  echo "错误：未设置 JAVA_HOME，且 /opt/jdk17 不存在。AGP 8.1 需要 JDK 17。" >&2
  exit 1
fi

# ---------- 3. Android SDK ----------
if [ -d /opt/android-sdk ]; then
  export ANDROID_HOME=/opt/android-sdk
elif [ -n "${ANDROID_HOME:-}" ]; then
  :
else
  export ANDROID_HOME="$HOME/Android/Sdk"
fi
export ANDROID_SDK_ROOT="$ANDROID_HOME"

if [ ! -d "$ANDROID_HOME/platforms" ]; then
  echo "错误：$ANDROID_HOME 下未找到 platforms，请先安装 Android SDK 34 / 35（compileSdk 35）。" >&2
  exit 1
fi

# ---------- 4. 制品源（国内镜像可选） ----------
if [ "${USE_CN_MIRROR:-0}" = "1" ] || [ -f "$ROOT/.use_cn_mirror" ]; then
  export FLUTTER_STORAGE_BASE_URL="https://mirrors.cloud.tencent.com/flutter"
  export PUB_HOSTED_URL="https://pub.dev"
  echo "使用国内镜像：$FLUTTER_STORAGE_BASE_URL"
else
  export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
  export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
fi
export FLUTTER_SUPPRESS_ANALYTICS=true

# ---------- 5. 重生成 v2 图标并写入 local.properties ----------
if command -v python3 >/dev/null 2>&1 && [ -f "$ROOT/tool/generate_icons.py" ]; then
  python3 "$ROOT/tool/generate_icons.py" >/dev/null 2>&1 || true
fi
# App 内「查看源代码」的离线资源 + 启动图标，必须在 pub get 之前生成。
if [ -f "$ROOT/tool/build_source_assets.py" ]; then
  python3 "$ROOT/tool/build_source_assets.py"
fi
{
  echo "flutter.sdk=$FLUTTER_ROOT"
  echo "sdk.dir=$ANDROID_HOME"
  echo "flutter.buildMode=release"
} > "$ROOT/android/local.properties"

echo "==> Flutter: $(flutter --version 2>/dev/null | head -1)"
echo "==> JAVA_HOME: $JAVA_HOME"
echo "==> ANDROID_HOME: $ANDROID_HOME"

# ---------- 6. 依赖与构建 ----------
echo "==> flutter pub get"
flutter pub get

echo "==> flutter build apk --release"
flutter build apk --release

APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "错误：构建未完成，未找到 $APK" >&2
  exit 1
fi

# 从 pubspec.yaml 读版本号，避免每次升级都回来改这里的硬编码文件名。
VER="$(grep -m1 '^version:' "$ROOT/pubspec.yaml" \
  | sed -E 's/^version:[[:space:]]*([^+]+).*/\1/' | tr -d '[:space:]')"
OUT="$ROOT/Aigent-v${VER:-0.0.0}.apk"
cp -f "$APK" "$OUT"
echo ""
echo "构建完成：$OUT"
ls -lh "$OUT"
echo "安装：adb install -r $OUT"
