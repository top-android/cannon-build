#!/usr/bin/env bash
#
# apply_a15_cannon_patches.sh -- A15(LOS 22.2) 全裸改补丁【幂等重放器】
#
# 作用：把 repro/patches/a15/*.patch 里记录的 A15 改动，重放到源码树（默认 /cannon/rom）。
#       这是"防丢补丁"的另一半：export_dirty_patches.sh 负责导出，本脚本负责重现。
#       覆盖 A15_PATCH_COVERAGE.md 里全部 🔴裸改 / 🟠部分裸改 项
#       （frameworks/base R3+IMS、packages/modules/Bluetooth R2、build/soong、
#        hardware/lineage/compat、vendor/lineage 等）。
#
# 语义（与 apply_cannon_patches.sh 对齐）：
#   - 每个补丁先判"是否已应用"（git apply --reverse --check 通过=已应用→跳过）。
#   - 未应用但可正向应用（git apply --check）=施加。
#   - 都不能=漂移/不匹配 → 报错并以非零退出（提醒需重新导出快照）。
#   - CANNON_DRY_RUN=1 时只报告，不写任何文件（安全体检）。
#   - 含二进制的补丁（"Binary files ... differ"占位）不 git apply，转为提示用 repatch 脚本再生。
#
# 用法：
#   bash scripts/apply_a15_cannon_patches.sh [/cannon/rom]
#   CANNON_DRY_RUN=1 bash scripts/apply_a15_cannon_patches.sh /cannon/rom
#
set -uo pipefail

TREE="${1:-/cannon/rom}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHDIR="${CANNON_PATCHDIR:-$HERE/../repro/patches/a15}"
DRY="${CANNON_DRY_RUN:-0}"

echo "================================================================"
echo " apply_a15_cannon_patches.sh"
echo "   TREE    = $TREE"
echo "   PATCHDIR= $PATCHDIR"
echo "   DRY_RUN = $DRY"
echo "================================================================"

if [ ! -d "$TREE" ]; then echo "!! 源码树不存在: $TREE"; exit 2; fi
if [ ! -d "$PATCHDIR" ]; then echo "!! 补丁目录不存在: $PATCHDIR"; exit 2; fi

# 补丁文件名 -> 仓库相对路径（严格对应 export_dirty_patches.sh 的 DEFAULT_REPOS）
MAP=(
  "build_make.patch:build/make"
  "build_soong.patch:build/soong"
  "device_xiaomi_cannon.patch:device/xiaomi/cannon"
  "frameworks_base.patch:frameworks/base"
  "frameworks_native.patch:frameworks/native"
  "frameworks_opt_telephony.patch:frameworks/opt/telephony"
  "hardware_lineage_compat.patch:hardware/lineage/compat"
  "hardware_mediatek.patch:hardware/mediatek"
  "hardware_mediatek_wlan.patch:hardware/mediatek/wlan"
  "packages_apps_Jelly.patch:packages/apps/Jelly"
  "packages_apps_Trebuchet.patch:packages/apps/Trebuchet"
  "packages_modules_Bluetooth.patch:packages/modules/Bluetooth"
  "packages_modules_Connectivity.patch:packages/modules/Connectivity"
  "packages_modules_NetworkStack.patch:packages/modules/NetworkStack"
  "packages_modules_Wifi.patch:packages/modules/Wifi"
  "packages_providers_MediaProvider.patch:packages/providers/MediaProvider"
  "system_core.patch:system/core"
  "system_libhidl.patch:system/libhidl"
  "vendor_lineage.patch:vendor/lineage"
  "vendor_xiaomi_cannon.patch:vendor/xiaomi/cannon"
  "kernel_xiaomi_cannon.patch:kernel/xiaomi/cannon"
)

APPLIED=0; SKIPPED=0; DRIFT=0; BINARY=0; FAIL=0
DRIFT_LIST=""

for entry in "${MAP[@]}"; do
  p="${entry%%:*}"; repo="${entry#*:}"
  pf="$PATCHDIR/$p"; rp="$TREE/$repo"
  printf -- '--- %-45s (%s) ' "$p" "$repo"
  if [ ! -f "$pf" ]; then echo "缺补丁!"; FAIL=1; continue; fi
  if [ ! -d "$rp/.git" ]; then echo "缺仓库!"; FAIL=1; continue; fi

  # 二进制占位：git apply 无法处理，路由到 repatch 脚本再生
  if grep -qE '^Binary files .* differ$' "$pf"; then
    echo "含二进制占位 → 跳过(git apply)，用 scripts/repatch_vendor_blobs.sh 再生二进制"
    BINARY=$((BINARY+1)); continue
  fi

  # 无 diff 内容（该仓库工作树已干净/已回退）→ 无可重放，直接跳过
  # （例：2026-10-30 r31 回退扫描裁剪后，kernel/xiaomi/cannon 工作树与 HEAD 一致，补丁为空）
  if ! grep -qE '^diff --git ' "$pf"; then
    echo "无 diff 内容（树已干净），跳过"; SKIPPED=$((SKIPPED+1)); continue
  fi

  if git -C "$rp" apply --reverse --check "$pf" >/dev/null 2>&1; then
    echo "已应用，跳过"; SKIPPED=$((SKIPPED+1))
  elif git -C "$rp" apply --check "$pf" >/dev/null 2>&1; then
    if [ "$DRY" = "1" ]; then
      echo "可应用(dry-run 未写)"; APPLIED=$((APPLIED+1))
    else
      if git -C "$rp" apply "$pf" >/dev/null 2>&1; then
        echo "已应用"; APPLIED=$((APPLIED+1))
      else
        echo "应用失败!"; FAIL=1
      fi
    fi
  else
    echo "漂移/不匹配(既不能正应用也不能反应用)"; DRIFT=$((DRIFT+1)); FAIL=1
    DRIFT_LIST="$DRIFT_LIST\n    - $p ($repo)"
  fi
done

echo "================================================================"
echo " 汇总: applied=$APPLIED skipped=$SKIPPED binary=$BINARY drift=$DRIFT fail=$FAIL"
if [ "$DRIFT" != "0" ]; then
  echo " !! 漂移项（快照与树不匹配，需重新导出 repro/patches/a15）："
  echo -e "$DRIFT_LIST"
  echo "   重新导出： bash scripts/export_dirty_patches.sh"
fi
echo "================================================================"

[ "$FAIL" = "0" ] && { echo "RESULT: OK"; exit 0; } || { echo "RESULT: FAIL"; exit 1; }
