#!/usr/bin/env bash
# 全量构建前自检：工作区改动是否都能被 repro 补丁重建
#
# 背景：build.sh 的 repo sync 带 --force-remove-dirty，未提交且未归档的改动会被丢弃。
# 若补丁清单缺文件（历史上 packages/modules/Connectivity 漏了 BpfUtils.h 等 7 个文件），
# 全量包必然缺这些 hunk，表现为 bpfloader 失败 -> netd_shared map 缺失 ->
# system_server 崩溃循环 -> 卡开机动画；而增量构建不 sync，所以永远正常。
#
# 用法：
#   bash check_patch_coverage.sh [/cannon/rom]
#   CANNON_PATCH_SUBDIR=a17 CANNON_PATCHDIR=... MAPFILE=... bash check_patch_coverage.sh
#
# 退出码：0 = 可安全 sync；1 = 存在已跟踪改动未被补丁覆盖，必须先导出补丁
set -uo pipefail

ROOT="${1:-/cannon/rom}"
SUBDIR="${CANNON_PATCH_SUBDIR:-a17}"
MAPFILE="${MAPFILE:-/cannon/cannon-build/scripts/apply_${SUBDIR}_cannon_patches.sh}"
PATCHDIR="${CANNON_PATCHDIR:-/cannon/cannon-build/repro/patches/${SUBDIR}}"

[ -d "$ROOT" ] || { echo "树不存在: $ROOT"; exit 2; }
[ -f "$MAPFILE" ] || { echo "找不到补丁映射: $MAPFILE"; exit 2; }
[ -d "$PATCHDIR" ] || { echo "找不到补丁目录: $PATCHDIR"; exit 2; }

echo "== 补丁覆盖自检  TREE=$ROOT  PATCHDIR=$PATCHDIR"

BAD=0
WARN=0
while IFS=: read -r pf repo; do
    p="$PATCHDIR/$pf"
    [ -f "$p" ] || continue
    [ -d "$ROOT/$repo/.git" ] || continue

    tracked=$(git -C "$ROOT/$repo" diff --name-only HEAD 2>/dev/null | sort -u)
    untracked=$(git -C "$ROOT/$repo" ls-files --others --exclude-standard 2>/dev/null | sort -u)
    [ -z "${tracked}${untracked}" ] && continue

    covered=$(grep '^diff --git' "$p" | sed 's|.*b/||' | sort -u)
    miss_t=$(comm -23 <(printf '%s\n' "$tracked") <(printf '%s\n' "$covered"))
    miss_u=$(comm -23 <(printf '%s\n' "$untracked") <(printf '%s\n' "$covered"))

    if [ -n "$miss_t" ]; then
        BAD=1
        echo "### [阻断] $repo：以下已跟踪改动未进补丁 $pf，sync 后必丢"
        printf '%s\n' "$miss_t" | sed 's/^/    /'
    fi
    if [ -n "$miss_u" ]; then
        WARN=1
        echo "### [警告] $repo：以下未跟踪文件未进补丁 $pf（sync 时可能保留，但不可依赖）"
        printf '%s\n' "$miss_u" | sed 's/^/    /'
    fi
done < <(grep -E '^[[:space:]]*"[a-zA-Z0-9_]+\.patch:[^"]+"' "$MAPFILE" | sed 's/^[[:space:]]*//; s/"//g')

ALT="${CANNON_ALT_PATCHDIR:-/cannon/cannon-port-log/repro/patches/${SUBDIR}}"
if [ -d "$ALT" ] && [ "$ALT" != "$PATCHDIR" ]; then
    d=$(diff -rq "$PATCHDIR" "$ALT" 2>/dev/null | grep -vE '_archived|_obsolete|\.bak' | head -5)
    if [ -n "$d" ]; then
        WARN=1
        echo "### [警告] 另一份补丁目录与生效目录不一致（生效: $PATCHDIR）"
        printf '%s\n' "$d" | sed 's/^/    /'
    fi
fi

if [ "$BAD" = "1" ]; then
    echo "RESULT: FAIL（把上面 [阻断] 的改动导出进 $PATCHDIR 后再 sync/build）"
    exit 1
fi
if [ "$WARN" = "1" ]; then
    echo "RESULT: OK（有警告，不阻断 sync）"
else
    echo "RESULT: OK"
fi
exit 0