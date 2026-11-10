#!/usr/bin/env bash
# ============================================================================
# A17 · 固定 packages/modules/Connectivity 到 cannong 的组件集成提交
#
# 背景：A17 的 BPF（netd/offload 程序、ringbuf、bpfloader 降级）在 4.14 内核上
#   需要专门的兼容层。LineageOS 主线没有这层，直接编出来的系统在 4.14 上：
#     - bpfloader 加载 netd 程序失败 → /sys/fs/bpf/netd_shared/* 缺失
#     - system_server 在 LocalNetEventHandler/BpfRingbuf 处 SIGABRT（boot loop）
#   仓库里 d468719 "Apply cannong Android 17 component integration" 正好落在
#   我们当前 HEAD 之上，包含 NetBpfLoad/BpfHandler/netd.c/offload.c 等 8 个文件、
#   624 行的 4.14 兼容改造，实测可正常加载。
#
# 用法：
#   bash scripts/pin_a17_connectivity.sh [源码树路径，默认 /cannon/rom]
# 幂等：已经在目标提交上时直接返回 0。
# ============================================================================
set -u

TREE="${1:-/cannon/rom}"
REPO="$TREE/packages/modules/Connectivity"
REV="d4687192c4a0e1cb10eb6abf4a7371dc64fcf8d4"
URL="https://github.com/LineageOS/android_packages_modules_Connectivity"

[ -d "$REPO/.git" ] || { echo "[connectivity-pin] ❌ 找不到仓库: $REPO"; exit 1; }

cd "$REPO" || exit 1

if [ "$(git rev-parse HEAD)" = "$REV" ]; then
    echo "[connectivity-pin] = 已固定在 d468719（cannong A17 组件集成）"
    exit 0
fi

# 有本地改动时不要动，避免覆盖别人的工作
if [ -n "$(git status --porcelain)" ]; then
    echo "[connectivity-pin] ⚠ 工作区有未提交改动，跳过（请先清理/提交）"
    git status --porcelain | head -5
    exit 1
fi

if ! git cat-file -e "$REV^{commit}" 2>/dev/null; then
    echo "[connectivity-pin] 拉取 $REV ..."
    git fetch --depth=2 "$URL" "$REV" >/dev/null 2>&1 || {
        echo "[connectivity-pin] ❌ 拉取失败"; exit 1; }
fi

echo "[connectivity-pin] 切到 d468719 ..."
git checkout -q "$REV" || { echo "[connectivity-pin] ❌ checkout 失败"; exit 1; }

if [ "$(git rev-parse HEAD)" = "$REV" ]; then
    echo "[connectivity-pin] ✓ 已切到 d468719"
else
    echo "[connectivity-pin] ❌ 结果校验失败"
    exit 1
fi
