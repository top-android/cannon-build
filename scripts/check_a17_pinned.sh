#!/usr/bin/env bash
#
# check_a17_pinned.sh -- 校验当前源码树是否就是某份锁定清单（repo manifest -r）的状态
#
# 用法：
#   bash scripts/check_a17_pinned.sh manifests/a17-pinned-2026-11-10.xml [/cannon/rom]
#
# 判据：清单里 revision 是 40 位 SHA 的 project，逐个 `git rev-parse HEAD` 比对。
#   revision 仍是分支/tag 的 project 记为「未锁定」，单独列出（这些仓无法保证复现）。
#
# 退出码：0 全部一致；1 有差异/缺失/未锁定；2 用法错误。
set -uo pipefail

MAN="${1:-}"
ROOT="${2:-/cannon/rom}"

[ -n "$MAN" ] && [ -f "$MAN" ] || { echo "用法: $0 <pinned.xml> [tree]"; exit 2; }
[ -d "$ROOT/.repo" ] || { echo "!! 不是 repo 树: $ROOT"; exit 2; }

python3 - "$MAN" "$ROOT" <<'PY'
import os, re, subprocess, sys
import xml.etree.ElementTree as ET

man, root = sys.argv[1], sys.argv[2]
r = ET.parse(man).getroot()
d = r.find('default')
default_rev = d.get('revision') if d is not None else None

sha_re = re.compile(r'^[0-9a-f]{40}$')
ok = diff = miss = unpinned = 0
bad, missing, loose = [], [], []

for p in r.findall('project'):
    path = p.get('path')
    rev = p.get('revision') or default_rev
    if not path:
        continue
    if not rev or not sha_re.match(rev):
        unpinned += 1
        loose.append(f"{path} ({rev})")
        continue
    g = os.path.join(root, path, '.git')
    if not os.path.exists(g):
        miss += 1
        missing.append(path)
        continue
    try:
        head = subprocess.check_output(
            ['git', '-C', os.path.join(root, path), 'rev-parse', 'HEAD'],
            stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError:
        miss += 1
        missing.append(path)
        continue
    if head == rev:
        ok += 1
    else:
        diff += 1
        bad.append(f"{path}\n      want {rev}\n      have {head}")

print(f"清单     : {man}")
print(f"源码树   : {root}")
print(f"一致 {ok} / 不一致 {diff} / 缺失 {miss} / 未锁定 {unpinned}")

if bad:
    print("\n== 不一致 ==")
    for b in bad:
        print("  " + b)
if missing:
    print("\n== 缺失（未 sync 或路径不存在）==")
    for m in missing[:20]:
        print("  " + m)
    if len(missing) > 20:
        print(f"  ... 另有 {len(missing)-20} 个")
if loose:
    print("\n== 未锁定（revision 不是 SHA，无法保证复现）==")
    for l in loose[:20]:
        print("  " + l)
    if len(loose) > 20:
        print(f"  ... 另有 {len(loose)-20} 个")

sys.exit(0 if (diff == 0 and miss == 0 and unpinned == 0) else 1)
PY
