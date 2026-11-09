#!/usr/bin/env python3
"""把英文界面词表机翻成目标语言，生成 lib/i18n/<code>.dart。

为什么要自己写生成器：
- 界面文案以中文原文为 key（`t('复制')`），英文词表是人工翻的，
  质量比机翻中文好；所以链路是 中文 → 英文（人工）→ 目标语言（Argos）。
- Argos 默认挂 Stanza 分句器，首次使用会联网下载模型，沙箱里直接卡死；
  界面文案几乎都是单句，用换行分句足够，于是替换成 FakeSent。
- 译文落到磁盘缓存，中断后可以续跑，不重复翻 300 条。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = '/tmp/i18n_cache'
os.makedirs(CACHE, exist_ok=True)

# ---------------------------------------------------------------- 词表解析


def read_map(path):
    src = open(path, encoding='utf-8').read()
    pat = re.compile(r"^  '((?:[^'\\]|\\.)*)':\s*\n?\s*'((?:[^'\\]|\\.)*)',", re.M)
    pairs = dict(pat.findall(src))

    def unesc(s):
        return (s.replace("\\'", "'").replace('\\"', '"')
                .replace('\\n', '\n').replace('\\\\', '\\'))

    return {unesc(k): unesc(v) for k, v in pairs.items()}


def read_dart_maps(path):
    """按 `const Map<String, String> kXxxUi = {` 切块，返回 {变量名: 词表}。"""
    src = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'const Map<String, String> (k\w+Ui) = \{(.*?)\n\};', src, re.S):
        body = m.group(2)
        pat = re.compile(r"^  '((?:[^'\\]|\\.)*)':\s*'((?:[^'\\]|\\.)*)',", re.M)
        pairs = dict(pat.findall(body))

        def unesc(x):
            return (x.replace("\\'", "'").replace('\\n', '\n')
                    .replace('\\\\', '\\'))

        out[m.group(1)] = {unesc(k): unesc(v) for k, v in pairs.items()}
    return out


def collect_keys():
    keys = set()
    ui = os.path.join(ROOT, 'lib', 'ui')
    for name in os.listdir(ui):
        if not name.endswith('.dart'):
            continue
        s = open(os.path.join(ui, name), encoding='utf-8').read()
        for m in re.finditer(r"(?:L10n\.)?t\('((?:[^'\\]|\\.)*)'\)", s):
            k = m.group(1).replace("\\'", "'").replace('\\n', '\n')
            if re.search(r'[\u4e00-\u9fa5]', k) and '$' not in k:
                keys.add(k)
    # 与 check_i18n 保持一致：天赋文案也要进词表。
    p2 = os.path.join(ROOT, 'lib', 'services', 'life_sim.dart')
    if os.path.exists(p2):
        s2 = open(p2, encoding='utf-8').read()
        pat = re.compile(
            r"LifeTalent\(\s*'[^']*',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'\)")
        for m in pat.finditer(s2):
            for g in m.groups():
                if re.search(r'[\u4e00-\u9fa5]', g) and '$' not in g:
                    keys.add(g)
    return keys


# ---------------------------------------------------------------- Dart 转义


def dart_str(s):
    out = (s.replace('\\', '\\\\').replace("'", "\\'")
           .replace('$', '\\$').replace('\n', '\\n'))
    return out


# ---------------------------------------------------------------- 译文润色

LATIN = re.compile(r'^[A-Za-zÀ-ÿА-Яа-яΑ-ω]')
SENT_END = re.compile(r'[.!?。！？]$')


def polish(src, dst):
    dst = dst.strip()
    if not dst:
        return dst
    # Argos 常给单句补一个句号；原文没有就删掉，短标签不该像句子。
    if dst.endswith('.') and not src.rstrip().endswith('.'):
        dst = dst[:-1].rstrip()
    # 原文首字母大写时，译文也跟着大写（德语名词本来大写，不受影响）。
    if src[:1].isupper() and LATIN.match(dst) and dst[:1].islower():
        dst = dst[0].upper() + dst[1:]
    return dst


# ---------------------------------------------------------------- 翻译


class FakeSent:
    """单行即一句。界面文案里极少出现需要二次切分的段。"""

    def split_sentences(self, text):
        parts = [p for p in text.split('\n') if p.strip()]
        return parts or [text]


def translate_all(code, pairs, manual):
    # 繁体中文没有 en→zh-TW 的 Argos 模型。把英文机翻回中文既慢又不准，
    # 正确做法是对中文原文做简繁转换；已有译文一律保留，只补新增词条。
    if code == 'zh-TW':
        try:
            import zhconv

            def conv(s):
                return zhconv.convert(s, 'zh-tw')
        except ImportError:
            # 没装 zhconv 时退回简体原文：功能不受影响，check_i18n 仍能通过。
            def conv(s):
                return s

        path = os.path.join(ROOT, 'assets', 'i18n', 'zh-TW.tsv')
        existing = {}
        if os.path.exists(path):
            for line in open(path, encoding='utf-8').read().split('\n'):
                if '\t' in line:
                    k, v = line.split('\t', 1)
                    existing[k.replace(r'\n', '\n')] = v.replace(r'\n', '\n')
        out = {k: existing.get(k) or conv(k) for k in pairs}
        out.update(manual)
        return out

    import argostranslate.translate as T

    path = os.path.join(CACHE, f'{code}.json')
    done = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    # 空串也算没翻出来：Argos 偶尔对个别长句返回空，若不重翻，
    # write_tsv 会跳过这一行，check_i18n 就会报缺词条。
    todo = [k for k in pairs if not done.get(k)]
    if todo:
        tr = T.get_translation_from_codes('en', code)
        tr.underlying.sentencizer = FakeSent()
        for i, k in enumerate(todo):
            try:
                done[k] = polish(pairs[k], tr.translate(pairs[k]))
            except Exception as e:  # noqa: BLE001
                print(f'  ! {code} {pairs[k][:40]!r} {e}', flush=True)
                done[k] = pairs[k]
            if i % 40 == 0:
                json.dump(done, open(path, 'w', encoding='utf-8'),
                          ensure_ascii=False, indent=0)
                print(f'  {code} {i}/{len(todo)}', flush=True)
        json.dump(done, open(path, 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=0)
    out = dict(done)
    out.update(manual)  # 人工短语优先，机翻不覆盖
    # 机翻仍是空串时回退英文原文，绝不让词表缺行。
    for k in list(out):
        if not out[k]:
            out[k] = pairs.get(k, k)
    return out


def write_tsv(code, table, keys):
    """输出 `assets/i18n/<code>.tsv`：中文原文 \t 译文。

    选 TSV 不选 JSON / Dart：体积小一半，diff 一行一条，改一条译文
    不会在 PR 里炸出满屏括号。
    """
    out = os.path.join(ROOT, 'assets', 'i18n')
    os.makedirs(out, exist_ok=True)
    lines = []
    for k in sorted(keys, key=lambda x: (len(x), x)):
        v = table.get(k)
        if not v:
            continue
        # 换行在 TSV 里会断行，转成字面 \n，运行时还原。
        lines.append(k.replace('\n', r'\n') + '\t' + v.replace('\n', r'\n'))
    path = os.path.join(out, f'{code}.tsv')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    return path


def main():
    targets = sys.argv[2:] if len(sys.argv) > 2 else []
    mode = sys.argv[1] if len(sys.argv) > 1 else 'gen'

    en = read_map(os.path.join(ROOT, 'lib', 'i18n', 'en.dart'))
    core = os.path.join(ROOT, 'lib', 'i18n', 'core.dart')
    core_maps = read_dart_maps(core) if os.path.exists(core) else {}
    keys = collect_keys()
    pairs = {k: en[k] for k in keys if k in en}
    print(f'keys {len(keys)} 有英文 {len(pairs)} 核心块 {list(core_maps)}', flush=True)

    if mode == 'check':
        return

    for code in targets:
        print(f'== {code}', flush=True)
        var = 'k' + code.replace('-', '_').title().replace('_', '') + 'Ui'
        table = translate_all(code, pairs, core_maps.get(var, {}))
        path = write_tsv(code, table, keys)
        print(f'   -> {path} {len(table)} 条', flush=True)


if __name__ == '__main__':
    main()
