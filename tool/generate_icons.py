#!/usr/bin/env python3
"""生成 Aigent v2 极简启动图标，资源名固定为 ic_launcher_v2。

设计：深墨中性底 + 一个带缺口的细环（聚焦/取景的抽象化）+ 低饱和蓝焦点。
无渐变、无阴影、无 emoji、无机器人意象。与 v1 的四角取景框明显区分。

产出：
  mipmap-*/ic_launcher_v2.png              legacy 48dp 不透明圆角方
  mipmap-*/ic_launcher_v2_foreground.png   adaptive 108dp 透明前景层
  mipmap-anydpi-v26/ic_launcher_v2.xml     Android 8+ 自适应图标
  values/colors.xml                        自适应图标背景色 + 启动页底色

用法: python3 tool/generate_icons.py
"""

import math
import os
from PIL import Image, ImageDraw

BG = (27, 30, 35, 255)         # #1B1E23 深墨
LINE = (233, 237, 242, 255)    # 浅中性细线
DOT = (122, 156, 214, 255)     # 低饱和品牌蓝

SS = 4  # 4x 超采样抗锯齿
DENSITIES = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
}

RES = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
)


def _arc_with_gap(draw, cx, cy, radius, width, gap_deg=56, start_deg=-146):
    """带缺口的细环，两个端点做圆头处理。"""
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    end = start_deg + 360 - gap_deg
    draw.arc(box, start=start_deg, end=end, fill=LINE,
             width=max(1, int(round(width))))
    r = width / 2.0
    for deg in (start_deg, end):
        a = math.radians(deg)
        x, y = cx + radius * math.cos(a), cy + radius * math.sin(a)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=LINE)


def _glyph(draw, cx, cy, ring_dp, unit):
    """unit = 每 dp 的像素数（含超采样）。"""
    px = lambda v: v * unit
    _arc_with_gap(draw, cx, cy, px(ring_dp), px(max(1.5, ring_dp * 0.105)))
    r = px(ring_dp * 0.255)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=DOT)


def _legacy(size_px, density):
    w = size_px * SS
    im = Image.new('RGBA', (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, w - 1], radius=int(w * 0.225), fill=BG)
    _glyph(d, w / 2, w / 2, 11.5, density * SS)
    return im.resize((size_px, size_px), Image.LANCZOS)


def _foreground(size_px, density):
    """108dp 画布，图形落在中心 66dp 安全区内，背景全透明。"""
    w = size_px * SS
    im = Image.new('RGBA', (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    _glyph(d, w / 2, w / 2, 21.0, density * SS)
    return im.resize((size_px, size_px), Image.LANCZOS)


def _cleanup_old_icons():
    """删除 v1 图标资源，确保 APK 内只剩一套、launcher 无法取到旧图。"""
    import glob
    targets = []
    for name in DENSITIES:
        targets += glob.glob(os.path.join(RES, 'mipmap-' + name, 'ic_launcher.png'))
        targets += glob.glob(os.path.join(RES, 'mipmap-' + name, 'ic_launcher_foreground.png'))
        targets += glob.glob(os.path.join(RES, 'mipmap-' + name, 'ic_launcher_round.png'))
    targets += glob.glob(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'))
    for p in targets:
        os.remove(p)
    if targets:
        print('removed %d v1 icon resources' % len(targets))


def main():
    _cleanup_old_icons()

    for name, density in DENSITIES.items():
        folder = os.path.join(RES, 'mipmap-' + name)
        os.makedirs(folder, exist_ok=True)
        legacy_px = int(48 * density)
        fg_px = int(108 * density)
        _legacy(legacy_px, density).save(
            os.path.join(folder, 'ic_launcher_v2.png'))
        _foreground(fg_px, density).save(
            os.path.join(folder, 'ic_launcher_v2_foreground.png'))
        print('mipmap-%-8s legacy=%dx%d  foreground=%dx%d' %
              (name, legacy_px, legacy_px, fg_px, fg_px))

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher_v2.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_v2_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_v2_foreground"/>\n'
                '</adaptive-icon>\n')

    with open(os.path.join(RES, 'values', 'colors.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_v2_background">#FF1B1E23</color>\n'
                '    <color name="launch_bg">#FFF6F7F9</color>\n'
                '</resources>\n')

    print('adaptive icon v2 + colors written')


if __name__ == '__main__':
    main()
