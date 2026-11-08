#!/usr/bin/env python3
"""生成模型列表用的高清彩色品牌图标（256×256 透明底 PNG）。

图标源：@lobehub/icons-static-svg（社区维护的 AI 厂商官方品牌标记集）。
仓库内只保存生成后的 PNG，运行时零网络、零新增依赖、零 SVG 解析开销：
256px 在 36–40dp 的展示尺寸下是 6x 级别，缩放不会糊。

用法：
    python3 tool/build_brand_icons.py                  # 联网从 npmmirror 拉取源
    python3 tool/build_brand_icons.py --src /path/to/icons   # 用已解包的 icons 目录

只在新增 / 更换品牌时重跑；生成结果需要随源码包一起交付。
"""

from __future__ import annotations

import argparse
import io
import pathlib
import sys
import tarfile
import urllib.request

import cairosvg

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "brand_models"
TGZ_URL = (
    "https://registry.npmmirror.com/@lobehub/icons-static-svg"
    "/-/icons-static-svg-1.102.0.tgz"
)
SIZE = 256
NEUTRAL = "#5A6070"  # 彩色图标里残留 currentColor 的次要细节用中性灰

# key -> (源 SVG 文件, 单色图标的官方品牌色 / None 表示本身已是彩色, 供应商显示名)
# 单色源只有 currentColor，这里统一染成该厂商的官方品牌色，保证「全彩色、不混黑白」。
ICONS: dict[str, tuple[str, str | None, str]] = {
    "openai": ("openai.svg", "#10A37F", "OpenAI"),
    "anthropic": ("claude-color.svg", None, "Anthropic Claude"),
    "google": ("gemini-color.svg", None, "Google Gemini"),
    "deepseek": ("deepseek-color.svg", None, "DeepSeek 深度求索"),
    "qwen": ("qwen-color.svg", None, "阿里通义千问"),
    "zhipu": ("zhipu-color.svg", None, "智谱 AI"),
    "doubao": ("doubao-color.svg", None, "字节豆包"),
    "kimi": ("kimi-color.svg", None, "月之暗面 Kimi"),
    "mistral": ("mistral-color.svg", None, "Mistral AI"),
    "meta": ("meta-color.svg", None, "Meta Llama"),
    "grok": ("grok.svg", "#5B6472", "xAI Grok"),
    "hunyuan": ("hunyuan-color.svg", None, "腾讯混元"),
    "baidu": ("baidu-color.svg", None, "百度文心"),
    "minimax": ("minimax-color.svg", None, "MiniMax 稀宇"),
    "yi": ("yi-color.svg", None, "零一万物 Yi"),
    "baichuan": ("baichuan-color.svg", None, "百川智能"),
    "stepfun": ("stepfun-color.svg", None, "阶跃星辰"),
    "spark": ("spark-color.svg", None, "讯飞星火"),
    "internlm": ("internlm-color.svg", None, "书生·浦语"),
    "cohere": ("cohere-color.svg", None, "Cohere"),
    "perplexity": ("perplexity-color.svg", None, "Perplexity"),
    "nvidia": ("nvidia-color.svg", None, "NVIDIA"),
    "microsoft": ("microsoft-color.svg", None, "Microsoft"),
    "openrouter": ("openrouter-color.svg", None, "OpenRouter"),
    "siliconflow": ("siliconcloud-color.svg", None, "硅基流动"),
    "volcengine": ("volcengine-color.svg", None, "火山引擎"),
    "deepinfra": ("deepinfra-color.svg", None, "DeepInfra"),
    "fireworks": ("fireworks-color.svg", None, "Fireworks AI"),
    "together": ("together-color.svg", None, "Together AI"),
    "novita": ("novita-color.svg", None, "Novita AI"),
    "cloudflare": ("workersai-color.svg", None, "Cloudflare Workers AI"),
    "huggingface": ("huggingface-color.svg", None, "Hugging Face"),
    "azure": ("azureai-color.svg", None, "Azure OpenAI"),
    "bedrock": ("bedrock-color.svg", None, "Amazon Bedrock"),
    "ai21": ("ai21-brand-color.svg", None, "AI21 Labs"),
    "alibaba": ("alibaba-color.svg", None, "阿里巴巴"),
    "groq": ("groq.svg", "#F55036", "Groq"),
    "moonshot": ("moonshot.svg", "#4C6FFF", "Moonshot AI"),
    "ollama": ("ollama.svg", "#5B6472", "Ollama"),
    "pollinations": ("pollinations.svg", "#7C5CFF", "Pollinations"),
    "kilocode": ("kilocode.svg", "#4C8BF5", "Kilo Code"),
    "replicate": ("replicate.svg", "#5B6472", "Replicate"),
}

# 认不出来的模型统一用同一个中性标记，绝不出现「有的彩色、有的黑白」。
GENERIC_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<rect x="2" y="2" width="20" height="20" rx="6" fill="#EAF0FE"/>
<path d="M12 6.6l1.35 3.05L16.4 11l-3.05 1.35L12 15.4l-1.35-3.05L7.6 11l3.05-1.35L12 6.6z"
 fill="#3478F6"/>
<circle cx="17.1" cy="16.9" r="1.5" fill="#3478F6" opacity="0.55"/>
</svg>"""


def load_sources(src: str | None) -> dict[str, str]:
    if src:
        base = pathlib.Path(src)
        return {
            p.name: p.read_text(encoding="utf-8")
            for p in base.glob("*.svg")
        }
    print(f"下载图标源：{TGZ_URL}")
    with urllib.request.urlopen(TGZ_URL, timeout=90) as r:
        data = r.read()
    out: dict[str, str] = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        for m in tf.getmembers():
            if m.name.endswith(".svg") and "/icons/" in m.name:
                f = tf.extractfile(m)
                if f is not None:
                    out[pathlib.PurePosixPath(m.name).name] = f.read().decode("utf-8")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", help="已解包的 icons 目录（离线用）")
    args = ap.parse_args()

    svgs = load_sources(args.src)
    if not svgs:
        print("没有读到任何源 SVG", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    ok, fail = 0, []
    for key, (fname, tint, _label) in ICONS.items():
        svg = svgs.get(fname)
        if svg is None:
            fail.append(f"{key}: 缺源文件 {fname}")
            continue
        svg = svg.replace("currentColor", tint or NEUTRAL)
        try:
            cairosvg.svg2png(
                bytestring=svg.encode("utf-8"),
                write_to=str(OUT / f"{key}.png"),
                output_width=SIZE,
                output_height=SIZE,
            )
            ok += 1
        except Exception as e:  # noqa: BLE001
            fail.append(f"{key}: {type(e).__name__} {e}")

    cairosvg.svg2png(
        bytestring=GENERIC_SVG.encode("utf-8"),
        write_to=str(OUT / "generic.png"),
        output_width=SIZE,
        output_height=SIZE,
    )
    ok += 1
    print(f"生成 {ok} 个图标 -> {OUT}")
    if fail:
        print("失败：", *fail, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
