#!/usr/bin/env python3
"""扫描 DSH client 插件包的 zh/en 字典缺口，输出缺失 key 清单"""
import re, os, json, glob

PKG = "/Users/iiiiiei/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/"
missing_all = {}

for pkg in sorted(os.listdir(PKG)):
    if not pkg.startswith("dsh-client"):
        continue
    f = os.path.join(PKG, pkg, "lib", "client.js")
    if not os.path.exists(f):
        continue
    s = open(f, encoding="utf-8").read()
    # 提取 locale.register 或 const zh/en 字典（宽松匹配对象字面量）
    found = []
    # 模式1: const zh = {...}; const en = {...}
    for name in ("zh", "en"):
        for m in re.finditer(r'const\s+' + name + r'\s*=\s*\{', s):
            start = m.end()
            depth = 1; i = start
            while i < len(s) and depth > 0:
                if s[i] == '{': depth += 1
                elif s[i] == '}': depth -= 1
                i += 1
            body = s[start:i-1]
            keys = set(re.findall(r'"([^"]+)"\s*:', body))
            if keys:
                found.append((name, keys))
    if len(found) >= 2:
        zh_keys = dict(found).get("zh", set())
        en_keys = dict(found).get("en", set())
        # en 有 zh 无的 key
        miss = en_keys - zh_keys
        if miss:
            missing_all[pkg] = sorted(miss)

total = sum(len(v) for v in missing_all.values())
print(f"共 {len(missing_all)} 个包存在 zh 字典缺口，缺失 key 总数 {total}\n")
for pkg, keys in sorted(missing_all.items(), key=lambda x: -len(x[1])):
    print(f"### {pkg} ({len(keys)})")
    print("  " + ", ".join(keys[:40]) + (" ..." if len(keys) > 40 else ""))
