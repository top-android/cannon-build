#!/usr/bin/env bash
# cannon A17（LineageOS 24.0 / Android 17）专用构建入口 —— 锁定清单模式
#
# 用法：
#   ./build-a17.sh [子命令] [参数]
#
#   doctor          环境体检（ccache / 内存 / 磁盘 / 签名密钥）
#   init            repo init 到 manifests/a17-pinned-*.xml（全 SHA，不跟分支）
#   sync            repo sync（按锁定 SHA 出树）
#   apply           重放 A17 构建期补丁（幂等；先 pin Connectivity 到 d468719）
#   build           lunch + m bacon
#   module <tgt>    单目标编译，例：./build-a17.sh module vendorimage
#   all             init + sync + apply + build
#   help            显示本帮助
#
# 变体（CANNON_VARIANT）：
#   userdebug       默认。调试变体，ro.debuggable=1
#   eng             工程变体，ro.debuggable=1 / ro.secure=0 / 无优化
#   user            发布变体，ro.debuggable=0，需要签名密钥
#
#   ⚠ 切换变体会触发 installclean：build 打印
#     "Build configuration changed ... forcing installclean"，删掉
#     out/target/product/cannon/ 下已装好的 system/system_ext/product/vendor
#     和全部 .img，并因编译参数变化接近全量重编（约 12 万步）。
#     所以脚本会先比对 out/target/product/cannon/previous_build_config.mk，
#     变体不一致就中止；确实要切，加 CANNON_ALLOW_VARIANT_SWITCH=1。
#     更推荐给每个变体单独一个 OUT_DIR，别把现有 userdebug 产物冲掉：
#       OUT_DIR=/cannon/out-user CANNON_VARIANT=user ./build-a17.sh all
#
#   ⚠ device/xiaomi/cannon/device.mk 里写死了 eng 的 ADB 属性矩阵
#     （ro.secure=0 / ro.adb.secure=0 / service.adb.root=1，落在 /product/build.prop）。
#     user 变体也会带上这套，正式发布前必须改回。
#
# 与 `PROFILE=a17 ./build.sh ...` 的唯一区别：init/sync 用**锁定清单**而不是
# local_manifests + 分支。公有上游仓在 cannon-a17.xml 里跟 refs/heads/lineage-24.0，
# 分支一前进，repro/patches/a17/*.patch（按导出当天 HEAD 生成）就会 drift；
# 锁定清单把 1241 个 project 全钉在 40 位 SHA 上，sync 出来的树 = 导出当天。
#
# 环境变量：
#   CANNON_VARIANT                userdebug | eng | user         默认 userdebug
#   CANNON_RELEASE                cp2a                            默认 cp2a
#   CANNON_ALLOW_VARIANT_SWITCH   1 = 允许切换变体（会 installclean）  默认 0
#   PINNED_MANIFEST               latest | 文件名 | 绝对路径       默认 latest
#   OUT_DIR                       产物目录                         默认 /cannon/out
#   LOG                           构建日志                         默认 /cannon/build.log
#   ROM_DIR                       源码树                           默认 /cannon/rom
#   JOBS                          并行度                           默认 nproc
#
# 常用组合：
#   ./build-a17.sh all                                          # 锁定清单全流程（userdebug）
#   ./build-a17.sh module vendorimage                           # 只编 vendor.img
#   CANNON_VARIANT=eng ./build-a17.sh build                     # 切 eng（会提示 installclean）
#   OUT_DIR=/cannon/out-user CANNON_VARIANT=user ./build-a17.sh all   # 独立目录出 user 包
#   PINNED_MANIFEST=manifests/a17-pinned-2026-11-10.xml ./build-a17.sh init
#
# 校验当前树是否就是清单状态：
#   bash scripts/check_a17_pinned.sh manifests/a17-pinned-*.xml
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

die() { printf '\033[31m错误: %s\033[0m\n' "$*" >&2; exit 1; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

usage() { sed -n '2,57p' "$0" | sed 's/^# \{0,1\}//'; }

CANNON_VARIANT="${CANNON_VARIANT:-userdebug}"
CANNON_RELEASE="${CANNON_RELEASE:-cp2a}"
PINNED_MANIFEST="${PINNED_MANIFEST:-latest}"
OUT_DIR="${OUT_DIR:-/cannon/out}"

case " userdebug eng user " in
    *" $CANNON_VARIANT "*) ;;
    *) die "CANNON_VARIANT 只能是 userdebug / eng / user（当前: $CANNON_VARIANT）" ;;
esac

case "${1:-}" in
    ""|-h|--help|help) usage; exit 0 ;;
esac

# 变体切换守卫：build/module/all 才会真正编，才需要检查
check_variant_switch() {
    local pbc="$OUT_DIR/target/product/cannon/previous_build_config.mk"
    [ -f "$pbc" ] || return 0
    local prev prevvar
    prev="$(sed -n 's/^PREVIOUS_BUILD_CONFIG[[:space:]]*:=[[:space:]]*//p' "$pbc" | head -1)"
    [ -n "$prev" ] || return 0
    prevvar="${prev##*-}"
    [ "$prevvar" = "$CANNON_VARIANT" ] && return 0

    warn "================================================================"
    warn " 变体切换: $prevvar → $CANNON_VARIANT"
    warn " 这会触发 installclean —— out/target/product/cannon/ 下的"
    warn " system / system_ext / product / vendor 和全部 .img 会被删掉，"
    warn " 并且编译参数变化导致接近全量重编（约 12 万步）。"
    warn ""
    warn " 想保留现有 $prevvar 产物，给新变体单独一个 OUT_DIR："
    warn "   OUT_DIR=/cannon/out-$CANNON_VARIANT CANNON_VARIANT=$CANNON_VARIANT $0 $*"
    warn ""
    warn " 确认要就地切换：加 CANNON_ALLOW_VARIANT_SWITCH=1"
    warn "================================================================"
    if [ "${CANNON_ALLOW_VARIANT_SWITCH:-0}" != "1" ]; then
        exit 1
    fi
}

case "${1:-}" in
    build|module|all) check_variant_switch "$@" ;;
esac

if [ "$CANNON_VARIANT" != "userdebug" ]; then
    warn "[提示] 变体=$CANNON_VARIANT；device.mk 里的 eng ADB 属性矩阵（ro.secure=0 / ro.adb.secure=0 / service.adb.root=1）仍会写进 /product/build.prop"
fi

export PROFILE=a17
export CANNON_VARIANT CANNON_RELEASE PINNED_MANIFEST OUT_DIR

exec "$SRC_DIR/build.sh" "$@"
