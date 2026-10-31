#!/usr/bin/env bash
#
# export_a16_dirty_patches.sh -- 从 A16 源码树导出各 project 改动为【可 git apply 重放】的合法补丁
#
# 与 apply_a16_cannon_patches.sh 配套：本脚本导出 → repro/patches/a16/*.patch，apply 脚本负责重放。
# 相比老式 export_dirty_patches.sh 的两点改进（关键）：
#   1) untracked 新源码用 `git diff --no-index -- /dev/null <file>` 生成【标准 unified diff】
#      （含 new file mode / --- /dev/null / +++ b/<f>），可被 `git apply` 真正重放；
#      旧脚本用 `sed 's/^/+/'` 生成的是"伪 diff"，无法 apply。
#   2) hardware/mediatek 下嵌套的 wlan/ 是独立 project，导出 hardware/mediatek 时自动排除，
#      避免与 hardware/mediatek/wlan.patch 重复；hardware/mediatek 本身 0 改动 → 产出空补丁（apply 端跳过）。
#
# 用法：
#   bash scripts/export_a16_dirty_patches.sh [/cannon/rom-a16]
#
# 说明：pairs 列表严格对应 apply_a16_cannon_patches.sh 的 MAP（A16 首轮 20 个 project）。
#       新增/删除 project 时两处同步改。
#
set -u
SRC="${1:-/cannon/rom-a16}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DST="$HERE/../repro/patches/a16"
mkdir -p "$DST"

pairs=(
"build/make:build_make" "build/soong:build_soong" "device/xiaomi/cannon:device_xiaomi_cannon"
"frameworks/base:frameworks_base" "frameworks/native:frameworks_native"
"frameworks/opt/net/wifi:frameworks_opt_net_wifi" "frameworks/opt/telephony:frameworks_opt_telephony"
"hardware/lineage/compat:hardware_lineage_compat" "hardware/mediatek:hardware_mediatek"
"hardware/mediatek/wlan:hardware_mediatek_wlan" "packages/apps/Jelly:packages_apps_Jelly"
"packages/apps/Settings:packages_apps_Settings" "packages/modules/Bluetooth:packages_modules_Bluetooth"
"packages/modules/Connectivity:packages_modules_Connectivity" "packages/modules/NetworkStack:packages_modules_NetworkStack"
"packages/modules/Wifi:packages_modules_Wifi" "packages/providers/MediaProvider:packages_providers_MediaProvider"
"system/core:system_core" "system/libhidl:system_libhidl" "vendor/lineage:vendor_lineage"
)

for e in "${pairs[@]}"; do
  path="${e%%:*}"; name="${e##*:}"; rp="$SRC/$path"
  [ -d "$rp/.git" ] || { echo "SKIP 非git: $path"; continue; }
  pf="$DST/$name.patch"; : > "$pf"
  git -C "$rp" diff >> "$pf" 2>/dev/null
  # untracked 新源码（排除备份垃圾、排除 hardware/mediatek 下嵌套 project 的 wlan/）
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$path" = "hardware/mediatek" ]; then case "$f" in wlan/*) continue;; esac; fi
    case "$f" in *.bak*|*.orig*|*.rej|*.patch) continue;; esac
    if grep -qI . "$rp/$f" 2>/dev/null; then
      ( cd "$rp" && git diff --no-index -- /dev/null "$f" 2>/dev/null ) >> "$pf"
    else
      printf '# [二进制新增文件，略，由脚本再生] %s\n' "$f" >> "$pf"
    fi
  done < <(git -C "$rp" ls-files --others --exclude-standard 2>/dev/null)
  nf=$(grep -c '^diff --git' "$pf" 2>/dev/null || echo 0)
  printf "%-32s files=%-3s lines=%s\n" "$name" "$nf" "$(wc -l < "$pf")"
done
echo "导出完成 → $DST"
