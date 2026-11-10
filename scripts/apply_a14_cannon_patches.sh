#!/usr/bin/env bash
#
# apply_a14_cannon_patches.sh -- A14(LOS 21) 裸改补丁【幂等重放器】
#
# 背景：
#   A14 原依赖 top-android/android_* 的 12 个"无上游历史 patch 快照仓"。
#   这些仓已于 2026-10-31 归档删除，改为"上游 LineageOS/AOSP + build-time 补丁"复现。
#   例外：hardware/mediatek/wlan 上游 LineageOS 无独立仓（是 android_hardware_mediatek
#   的子目录），仍保留自有仓 top-android/android_hardware_mediatek_wlan（已恢复），不走本脚本。
#   packages/modules/Wifi 仓未删、仍用自有分支，也不走本脚本。
#
# 支持两种补丁格式（repro/patches/a14_orphan 内混杂）：
#   1) git 格式（首行 ^diff --git）：git apply 幂等
#        - git apply --reverse --check 通过 = 已应用 → 跳过
#        - git apply --check        通过 = 可应用 → 施加
#        - 都不通过 = 漂移 → 报错
#   2) 旧 diff -ruN 格式（up/android_<repo>/... orph/android_<repo>/...）：patch -p2
#        - 正向 patch -p2 --dry-run 成功 = 可应用 → 施加
#        - 否则 反向 patch -p2 -R --dry-run 成功 = 已应用 → 跳过
#        - 都不成功 = 漂移 → 报错
#
# 语义与 apply_a15/a16 对齐：幂等；CANNON_DRY_RUN=1 只报告不写文件。
#
# 用法：
#   bash scripts/apply_a14_cannon_patches.sh [/cannon/rom]
#   CANNON_DRY_RUN=1 bash scripts/apply_a14_cannon_patches.sh /cannon/rom
#
set -uo pipefail

TREE="${1:-/cannon/rom}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHDIR="${CANNON_PATCHDIR:-$HERE/../repro/patches/a14_orphan}"
DRY="${CANNON_DRY_RUN:-0}"

echo "================================================================"
echo " apply_a14_cannon_patches.sh"
echo "   TREE    = $TREE"
echo "   PATCHDIR= $PATCHDIR"
echo "   DRY_RUN = $DRY"
echo "================================================================"

[ -d "$TREE" ]     || { echo "!! 源码树不存在: $TREE"; exit 2; }
[ -d "$PATCHDIR" ] || { echo "!! 补丁目录不存在: $PATCHDIR"; exit 2; }
command -v patch >/dev/null 2>&1 || { echo "!! 缺 patch 命令"; exit 2; }

# 补丁文件名 -> 仓库相对路径（严格对应 repro/patches/a14_orphan；不含 wlan / Wifi，见头注）
MAP=(
  "android_build_make.patch:build/make"
  "android_frameworks_base.patch:frameworks/base"
  "android_frameworks_native.patch:frameworks/native"
  "android_frameworks_opt_telephony.patch:frameworks/opt/telephony"
  "android_hardware_mediatek.patch:hardware/mediatek"
  "android_packages_modules_NetworkStack.patch:packages/modules/NetworkStack"
  "android_packages_modules_Bluetooth.patch:packages/modules/Bluetooth"
  "android_packages_providers_MediaProvider.patch:packages/providers/MediaProvider"
  "android_system_core.patch:system/core"
  "android_packages_apps_Jelly.patch:packages/apps/Jelly"
  "android_packages_apps_Trebuchet.patch:packages/apps/Trebuchet"
)

APPLIED=0; SKIPPED=0; DRIFT=0; FAIL=0
DRIFT_LIST=""

for entry in "${MAP[@]}"; do
  p="${entry%%:*}"; repo="${entry#*:}"
  pf="$PATCHDIR/$p"; rp="$TREE/$repo"
  printf -- '--- %-46s (%s) ' "$p" "$repo"
  if [ ! -f "$pf" ];             then echo "缺补丁!"; FAIL=1; continue; fi
  if [ ! -d "$rp/.git" ];        then echo "缺仓库(未 sync?)!"; FAIL=1; continue; fi

  if grep -qE '^diff --git ' "$pf"; then
    # ---------- git 格式 ----------
    if git -C "$rp" apply --reverse --check "$pf" >/dev/null 2>&1; then
      echo "已应用,跳过"; SKIPPED=$((SKIPPED+1))
    elif git -C "$rp" apply --check "$pf" >/dev/null 2>&1; then
      if [ "$DRY" = "1" ]; then
        echo "可应用(dry-run 未写)"; APPLIED=$((APPLIED+1))
      elif git -C "$rp" apply "$pf" >/dev/null 2>&1; then
        echo "已应用"; APPLIED=$((APPLIED+1))
      else
        echo "应用失败!"; FAIL=1
      fi
    else
      echo "漂移/不匹配"; DRIFT=$((DRIFT+1)); FAIL=1
      DRIFT_LIST="$DRIFT_LIST\n    - $p ($repo) [git]"
    fi
  else
    # ---------- 旧 diff -ruN 格式：patch -p2（--forward：只正向应用，遇已应用则跳过，绝不反向） ----------
    # 注意：绝不能用 --batch！GNU patch 的 --batch 在"看起来像反向"时会自动反向应用，
    #       从而把已应用的补丁回退掉。--forward 则明确"跳过已应用、不反向"。
    if patch -p2 --dry-run --forward -d "$rp" -i "$pf" </dev/null >/dev/null 2>&1; then
      if [ "$DRY" = "1" ]; then
        echo "可应用(dry-run 未写)"; APPLIED=$((APPLIED+1))
      elif patch -p2 --forward -d "$rp" -i "$pf" </dev/null >/dev/null 2>&1; then
        echo "已应用(patch)"; APPLIED=$((APPLIED+1))
      else
        echo "应用失败!"; FAIL=1
      fi
    elif patch -p2 -R --dry-run -d "$rp" -i "$pf" </dev/null >/dev/null 2>&1; then
      echo "已应用,跳过"; SKIPPED=$((SKIPPED+1))
    else
      echo "漂移/不匹配"; DRIFT=$((DRIFT+1)); FAIL=1
      DRIFT_LIST="$DRIFT_LIST\n    - $p ($repo) [diff-ruN]"
    fi
  fi
done

echo "================================================================"
echo " 汇总: applied=$APPLIED skipped=$SKIPPED drift=$DRIFT fail=$FAIL"
if [ "$DRIFT" != "0" ]; then
  echo " !! 漂移项（快照与树不匹配，需重新导出）："
  echo -e "$DRIFT_LIST"
fi
echo "================================================================"

[ "$FAIL" = "0" ] && { echo "RESULT: OK"; exit 0; } || { echo "RESULT: FAIL"; exit 1; }
