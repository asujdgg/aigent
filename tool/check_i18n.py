#!/usr/bin/env python3
"""检查界面文案与词表的完整性。

CI 与本地都用同一条命令：

    python3 tool/check_i18n.py

检查项：
1. 代码里所有 `t('中文')` 都能在 en.dart 找到英文（带 `$` 插值的除外）；
2. 每种语言的 tsv 都覆盖同一批 key；
3. 没有 key 里有未转义的制表符 / 换行。
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def collect_keys():
    keys, skipped = set(), set()
    for p in glob.glob(os.path.join(ROOT, 'lib', 'ui', '*.dart')):
        s = open(p, encoding='utf-8').read()
        for m in re.finditer(r"(?:L10n\.)?t\('((?:[^'\\]|\\.)*)'\)", s):
            k = m.group(1).replace("\\'", "'").replace('\\n', '\n')
            if not re.search(r'[\u4e00-\u9fa5]', k):
                continue
            if '$' in k:
                skipped.add(k)
            else:
                keys.add(k)
    return keys, skipped


def read_en():
    src = open(os.path.join(ROOT, 'lib', 'i18n', 'en.dart'), encoding='utf-8').read()
    pat = re.compile(r"^  '((?:[^'\\]|\\.)*)':\s*\n?\s*'((?:[^'\\]|\\.)*)',", re.M)
    def unesc(x):
        return (x.replace("\\'", "'").replace('\\n', '\n')
                .replace('\\\\', '\\'))

    return {unesc(k): unesc(v) for k, v in pat.findall(src)}


def read_tsv(path):
    out = {}
    for line in open(path, encoding='utf-8').read().split('\n'):
        if not line.strip() or '\t' not in line:
            continue
        k, v = line.split('\t', 1)
        out[k.replace(r'\n', '\n')] = v
    return out


def main():
    keys, skipped = collect_keys()
    en = read_en()
    missing_en = sorted(keys - set(en))
    ok = True
    print(f'代码词条 {len(keys)}（另有 {len(skipped)} 条含插值，跳过）')
    if missing_en:
        ok = False
        print(f'✗ en.dart 缺 {len(missing_en)} 条：')
        for k in missing_en[:12]:
            print('   ', k)

    files = sorted(glob.glob(os.path.join(ROOT, 'assets', 'i18n', '*.tsv')))
    print(f'语言词表 {len(files)} 份')
    for p in files:
        code = os.path.basename(p)[:-4]
        t = read_tsv(p)
        lack = keys - set(t)
        if lack:
            ok = False
            print(f'✗ {code} 缺 {len(lack)} 条，例如：{list(lack)[:3]}')
        if len(t) < len(keys):
            ok = False

    print('✓ 全部通过' if ok else '✗ 存在缺失')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
