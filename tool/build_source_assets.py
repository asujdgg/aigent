#!/usr/bin/env python3
"""构建期生成 App 内「查看源代码」所需的离线资源。

产出：
  assets/source_bundle.json  工程源码全文 + 清单（单文件，避免逐目录声明资源）
  assets/brand/app_icon.png  应用启动图标（供抽屉 / 形象默认头像使用）

只打包人写的源码与配置，不打包 build/、.dart_tool/、APK 与任何凭据。
"""
from __future__ import annotations

import json
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
ASSETS.mkdir(exist_ok=True)
(ASSETS / "brand").mkdir(exist_ok=True)

GLOBS = [
    "lib/**/*.dart",
    "test/*.dart",
    "tool/*.py",
    "tool/*.sh",
    "android/app/src/main/**/*.kt",
    "android/app/src/main/AndroidManifest.xml",
    "android/app/build.gradle.kts",
    "pubspec.yaml",
    "analysis_options.yaml",
    "build.sh",
    "README.md",
]

files = []
seen: set[str] = set()
for pattern in GLOBS:
    for path in sorted(ROOT.glob(pattern)):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel in seen:
            continue
        seen.add(rel)
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        files.append(
            {
                "path": rel,
                "lines": text.count("\n") + 1,
                "size": len(text.encode("utf-8")),
                "content": text,
            }
        )

# 按目录分组，前端展示更清晰：lib/ → android/ → 工程配置 → 测试
ORDER = {"lib/": 0, "android/": 1, "tool/": 2, "test/": 3}
files.sort(key=lambda f: (next((v for k, v in ORDER.items() if f["path"].startswith(k)), 9), f["path"]))

# 版本号必须从 pubspec 读，不能手写——手写就会和安装包对不上。
_pub = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
_m = re.search(r"^version:\s*([0-9][\w.\-]*)\+?(\d+)?", _pub, re.MULTILINE)
VERSION = _m.group(1) if _m else "0.0.0"
BUILD = _m.group(2) if _m and _m.group(2) else "0"

bundle = {
    "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    "version": VERSION,
    "build": BUILD,
    "package": "com.aigent.studio",
    "fileCount": len(files),
    "totalLines": sum(f["lines"] for f in files),
    "files": files,
}
out = ASSETS / "source_bundle.json"
out.write_text(json.dumps(bundle, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

# 应用图标：取最高分辨率的 mipmap
icon_src = ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_v2.png"
icon_dst = ASSETS / "brand/app_icon.png"
if icon_src.exists():
    shutil.copyfile(icon_src, icon_dst)
else:
    # 兜底：生成一个纯色占位图，保证 pubspec 声明的资源一定存在
    from PIL import Image  # type: ignore

    Image.new("RGB", (192, 192), (17, 19, 23)).save(icon_dst)

print(f"source_bundle.json: {len(files)} files, {bundle['totalLines']} lines, {out.stat().st_size} bytes")
print(f"app_icon.png: {icon_dst.stat().st_size} bytes")
