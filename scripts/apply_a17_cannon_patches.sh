#!/usr/bin/env bash
#
# apply_a17_cannon_patches.sh -- A17(LOS 24.0) 全裸改补丁【幂等重放器】
#
# 作用：把 repro/patches/a17/*.patch 里记录的 A17 改动，重放到源码树（默认 /cannon/rom-a17）。
#       与 apply_a16 完全对齐的“防丢补丁”另一半：export 负责导出，本脚本负责重现。
#
# 语义（与 apply_a16_cannon_patches.sh 对齐）：
#   - 每个补丁先判"是否已应用"（git apply --reverse --check 通过=已应用→跳过）。
#   - 未应用但可正向应用（git apply --check）=施加。
#   - 都不能=漂移/不匹配 → 报错并非零退出（提醒需重新导出快照）。
#   - CANNON_DRY_RUN=1 只报告不写。
#   - 含二进制占位的新增文件不 git apply，转提示再生。
#
# 【A17 基线阶段】repro/patches/a17 目前还没有补丁（A17 属全新系统，补丁需按
#   症状签名在 A17 源码上重新定位后导出）。此阶段本脚本检测到“无补丁”时，打印
#   提示并 0 退出——即只做 repo sync 即可，不阻断流程。
#
# 用法：
#   bash scripts/apply_a17_cannon_patches.sh [/cannon/rom-a17]
#   CANNON_DRY_RUN=1 bash scripts/apply_a17_cannon_patches.sh /cannon/rom-a17
#
set -uo pipefail

TREE="${1:-/cannon/rom-a17}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHDIR="${CANNON_PATCHDIR:-$HERE/../repro/patches/a17}"
DRY="${CANNON_DRY_RUN:-0}"

echo "================================================================"
echo " apply_a17_cannon_patches.sh"
echo "   TREE    = $TREE"
echo "   PATCHDIR= $PATCHDIR"
echo "   DRY_RUN = $DRY"
echo "================================================================"

if [ ! -d "$TREE" ]; then echo "!! 源码树不存在: $TREE"; exit 2; fi

# 基线阶段：补丁目录不存在或没有任何 .patch → 跳过（sync 即可）
shopt -s nullglob
have_patches=("$PATCHDIR"/*.patch)
if [ ! -d "$PATCHDIR" ] || [ "${#have_patches[@]}" -eq 0 ]; then
  echo "A17 基线阶段：repro/patches/a17 暂无补丁，跳过 apply（当前只需 repo sync）。"
  echo "RESULT: OK (no patches)"
  exit 0
fi

# 补丁文件名 -> 仓库相对路径（新增 A17 补丁后按需要在此登记）
MAP=(
  "art.patch:art"
  "build_make.patch:build/make"
  "build_soong.patch:build/soong"
  # [2026-11-09] 指纹 HIDL→AIDL 已 commit 进仓（device 2f2f689 / vendor 2195ada），
  # 旧 patch 既不能正打也不能反打 → 会造成 drift 失败。保留文件作归档，从 MAP 摘除。
  # "device_xiaomi_cannon.patch:device/xiaomi/cannon"
  "frameworks_base.patch:frameworks/base"
  "frameworks_native.patch:frameworks/native"
  "frameworks_opt_net_wifi.patch:frameworks/opt/net/wifi"
  "frameworks_opt_telephony.patch:frameworks/opt/telephony"
  "hardware_lineage_compat.patch:hardware/lineage/compat"
  "hardware_mediatek.patch:hardware/mediatek"
  "hardware_nxp_secure_element.patch:hardware/nxp/secure_element"
  "hardware_mediatek_wlan.patch:hardware/mediatek/wlan"
  "hardware_xiaomi_fingerprint_join.patch:hardware/xiaomi"
  "kernel_xiaomi_cannon.patch:kernel/xiaomi/cannon"
  "packages_apps_Jelly.patch:packages/apps/Jelly"
  "packages_apps_Launcher3.patch:packages/apps/Launcher3"
  "packages_apps_Settings.patch:packages/apps/Settings"
  "packages_modules_Bluetooth.patch:packages/modules/Bluetooth"
  # [cannon] 主线 packages_modules_Connectivity.patch 已停用（_obsolete/）；
  # 该仓先被 pin 到 d468719，再打本补丁（loader 的 4.14 降级修正）
  "packages_modules_Connectivity_loader.patch:packages/modules/Connectivity"
  "packages_modules_NetworkStack.patch:packages/modules/NetworkStack"
  "packages_modules_Wifi.patch:packages/modules/Wifi"
  "packages_providers_MediaProvider.patch:packages/providers/MediaProvider"
  "system_core.patch:system/core"
  "system_netd.patch:system/netd"                       # netd1shot reboot_on_failure 注释（4.14 调 BPF 期）
  "system_libhidl.patch:system/libhidl"
  "vendor_lineage.patch:vendor/lineage"
  # A17 4.14 非GKI 内核头 sbox 链三补丁（同一 repo/lineage，分文件独立 apply）：
  "vendor_lineage_kernel_headers_sbox.patch:vendor/lineage"     # Android.bp dep_files 补 scripts/**+arch Makefile
  "vendor_lineage_clean_headers_sbox.patch:vendor/lineage"      # clean_headers.sh 在 sbox(无bionic) 优雅跳过
  "vendor_lineage_boardkernel_out_prefix.patch:vendor/lineage"  # BoardConfigKernel.mk O= 无条件绝对(治头被沙箱丢弃)
  # "vendor_xiaomi_cannon.patch:vendor/xiaomi/cannon"   # 同上，已 commit 进仓
)

APPLIED=0; SKIPPED=0; DRIFT=0; BINARY=0; FAIL=0
DRIFT_LIST=""

for entry in "${MAP[@]}"; do
  p="${entry%%:*}"; repo="${entry#*:}"
  pf="$PATCHDIR/$p"; rp="$TREE/$repo"
  [ -f "$pf" ] || continue          # 该仓尚无 A17 补丁 → 静默跳过
  printf -- '--- %-45s (%s) ' "$p" "$repo"
  if [ ! -d "$rp/.git" ]; then echo "缺仓库!"; FAIL=1; continue; fi

  if grep -qE '^Binary files .* differ$|^# \[二进制新增文件' "$pf"; then
    echo "含二进制占位 → 跳过(git apply)，用 scripts/repatch_vendor_blobs.sh 再生二进制"
    BINARY=$((BINARY+1)); continue
  fi
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
  echo " !! 漂移项（快照与树不匹配，需重新导出 repro/patches/a17）："
  echo -e "$DRIFT_LIST"
fi
echo "================================================================"

[ "$FAIL" = "0" ] && { echo "RESULT: OK"; exit 0; } || { echo "RESULT: FAIL"; exit 1; }
