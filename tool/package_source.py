#!/usr/bin/env python3
"""把工程源码打成可复现构建的 zip（不含构建产物 / APK / 凭据）。"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT.parent / "Aigent-v4.24.0-source.zip"

INCLUDE_DIRS = ["lib", "test", "tool", "assets"]
INCLUDE_FILES = [
    "pubspec.yaml",
    "pubspec.lock",
    "analysis_options.yaml",
    "build.sh",
    "README.md",
    # 开源三件套：许可证、CI、Git 忽略规则
    "LICENSE",
    ".gitignore",
    ".github/workflows/ci.yml",
    # 项目交接文档：源码包自带，接手方不需要另外找。
    "HANDOVER.md",
    "android/app/src/main/AndroidManifest.xml",
    "android/app/src/main/kotlin/com/aigent/studio/MainActivity.kt",
    "android/app/build.gradle",
    # JNA / Vosk 的 release 保名规则：缺了它离线识别会崩（见文件内注释）。
    "android/app/proguard-rules.pro",
    "android/build.gradle",
    "android/settings.gradle",
    "android/gradle.properties",
    "android/gradle/wrapper/gradle-wrapper.properties",
    "android/app/src/main/res/values/styles.xml",
    "android/app/src/main/res/values-night/styles.xml",
]

SKIP_NAMES = {".git", ".idea", ".dart_tool", "build", "__pycache__", ".DS_Store"}


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    for d in INCLUDE_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            # 42 MB 的语音包不进源码包：它不是源码，且会让 zip 膨胀 80 倍。
            if p.is_file() and p.suffix == '.zip' and 'speech' in p.parts:
                continue
            if p.is_file() and not (set(p.relative_to(ROOT).parts) & SKIP_NAMES):
                files.append(p)
    for rel in INCLUDE_FILES:
        p = ROOT / rel
        if p.is_file():
            files.append(p)

    seen: set[str] = set()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            rel = p.relative_to(ROOT).as_posix()
            if rel in seen:
                continue
            seen.add(rel)
            z.write(p, f"Aigent-v4.24.0/{rel}")
    print(f"{out}: {len(seen)} files, {out.stat().st_size} bytes")


if __name__ == "__main__":
    main()
