#!/usr/bin/env bash
# Xiaomi cannon / cannong (MT6853T) — LineageOS 21 一键构建
#
#   ./build.sh doctor   环境体检
#   ./build.sh init     repo init + 安装 local_manifests
#   ./build.sh sync     repo sync
#   ./build.sh build    lunch + m bacon
#   ./build.sh all      init + sync + apply 补丁 + build（A14 / LineageOS 21，默认）
#   ./build.sh a14      同 all（A14，显式别名）
#   ./build.sh a15      A15 专用：init + sync + apply 补丁 + build（LineageOS 22.2）
#   ./build.sh a16      A16 专用：init + sync + apply 补丁 + build（LineageOS 23.2 / Android 16）
#   ./build.sh a17      A17 专用：init + sync + apply 补丁 + build（LineageOS 24.0 / Android 17）
#
# 【2026-10-31】A14 也改为「上游 LineageOS/AOSP + build-time 补丁」：
#   原 top-android/android_* 快照仓已删，A14 现在与 A15/A16 同一套 apply 机制
#   （local_manifests/cannon.xml 只覆盖自有仓，其余走上游 + apply_a14 补丁）。
# 也可用环境变量覆盖：PROFILE=a15 ./build.sh all
#
set -euo pipefail

ROM_DIR="${ROM_DIR:-/cannon/rom}"
OUT_DIR="${OUT_DIR:-/cannon/out}"
LOG="${LOG:-/cannon/build.log}"
CCACHE_DIR="${CCACHE_DIR:-/cannon/ccache}"
JOBS="${JOBS:-$(nproc)}"                # 默认取系统最大线程数；内存不足时用 JOBS=N 覆盖
LUNCH_TARGET="${LUNCH_TARGET:-lineage_cannon-ap2a-userdebug}"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/LineageOS/android.git}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-lineage-21.0}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- local_manifests 与补丁开关（A14 默认 = 上游 + patch）----
LOCAL_MANIFEST_NAME="${LOCAL_MANIFEST_NAME:-cannon.xml}"
APPLY_PATCHES="${APPLY_PATCHES:-1}"                       # A14 也走 build-time 补丁（原快照仓已删）
# ---- 按 profile 选择的辅助变量（A14 默认值见下；a15/a16 profile 覆盖）----
LUNCH_ARGS=()          # 非空时 cmd_build 用多参 lunch（A16 需三参：product release variant）
APPLY_SCRIPT="$SRC_DIR/scripts/apply_a14_cannon_patches.sh"   # A14 默认补丁脚本
PATCH_SUBDIR="a14_orphan"                                     # repro/patches/<PATCH_SUBDIR>（a14_orphan/a15/a16）

# ---- A15 profile（LineageOS 22.2 / Android 15）----
# 仅在选中 a15 子命令、或有 top-android 已建好 lineage-22.2-cannon 分支时使用。
# 目标：lunch lineage_cannon-bp1a-user，local_manifests 用 cannon-22.2.xml，
#       编译前重放 A15 构建期补丁（幂等：仓库里已提交的改动会自动跳过）。
apply_a15_profile() {
    MANIFEST_BRANCH="lineage-22.2"
    LUNCH_TARGET="lineage_cannon-bp1a-user"
    LOCAL_MANIFEST_NAME="cannon-22.2.xml"
    APPLY_PATCHES="1"
    APPLY_SCRIPT="$SRC_DIR/scripts/apply_a15_cannon_patches.sh"
    PATCH_SUBDIR="a15"
}
[ "${PROFILE:-}" = "a15" ] && apply_a15_profile

# ---- A16 profile（LineageOS 23.2 / Android 16，release=bp4a）----
# 关键差异：A16 的 lunch 需三参（product release variant）。
# 目标：lunch lineage_cannon bp4a user（发布变体），local_manifests 用 cannon-a16.xml
#       （5 自有仓 lineage-23.2-cannon 双轨 + 上游 + build-time 补丁），
#       编译前重放 A16 构建期补丁（apply_a16，幂等）。
# 变体默认 user（正式发布）；调试期可 CANNON_VARIANT=userdebug ./build.sh a16 覆盖。
apply_a16_profile() {
    MANIFEST_BRANCH="lineage-23.2"
    local variant="${CANNON_VARIANT:-user}"
    LUNCH_TARGET="lineage_cannon-bp4a-${variant}"   # 仅用于显示/兼容旧逻辑
    LUNCH_ARGS=(lineage_cannon bp4a "$variant")     # A16 三参：product release variant
    LOCAL_MANIFEST_NAME="cannon-a16.xml"
    APPLY_PATCHES="1"
    APPLY_SCRIPT="$SRC_DIR/scripts/apply_a16_cannon_patches.sh"
    PATCH_SUBDIR="a16"
}
[ "${PROFILE:-}" = "a16" ] && apply_a16_profile

# ---- A17 profile（LineageOS 24.0 / Android 17）----
# 目标：lunch lineage_cannon <release> userdebug（调试变体，默认），local_manifests 用 cannon-a17.xml
#       （5 自有仓 lineage-24.0-cannon 双轨 + 上游 lineage-24.0 + build-time 补丁），
#       编译前重放 A17 构建期补丁（apply_a17，幂等；基线阶段无补丁则自动跳过）。
# A17 的 lunch release 代号 = cp2a（2026-11-05 实测：本树 vendor/lineage/release/
# release_config_map.mk 只声明了 cp2a；A16 是 bp4a）。可用 CANNON_RELEASE=<code> 覆盖。
apply_a17_profile() {
    MANIFEST_BRANCH="lineage-24.0"
    local variant="${CANNON_VARIANT:-userdebug}"
    local release="${CANNON_RELEASE:-cp2a}"
    LUNCH_TARGET="lineage_cannon-${release}-${variant}"   # 仅用于显示/兼容旧逻辑
    LUNCH_ARGS=(lineage_cannon "$release" "$variant")     # A17 三参：product release variant
    LOCAL_MANIFEST_NAME="cannon-a17.xml"
    APPLY_PATCHES="1"
    APPLY_SCRIPT="$SRC_DIR/scripts/apply_a17_cannon_patches.sh"
    PATCH_SUBDIR="a17"
}
[ "${PROFILE:-}" = "a17" ] && apply_a17_profile

c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
die()    { c_red "错误: $*"; exit 1; }

# repo 在非交互 shell 里通常不在 PATH，优先用工作区自带的
repo_bin() {
    if [ -x "$ROM_DIR/.repo/repo/repo" ]; then
        echo "python3 $ROM_DIR/.repo/repo/repo"
    elif command -v repo >/dev/null 2>&1; then
        echo "repo"
    else
        die "找不到 repo，先装: mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod a+x ~/bin/repo"
    fi
}

cmd_doctor() {
    step "环境体检"
    local ok=1

    command -v git    >/dev/null || { c_red "缺 git"; ok=0; }
    command -v ccache >/dev/null || { c_ylw "缺 ccache —— 会全量编译"; ok=0; }
    command -v python3 >/dev/null || { c_red "缺 python3"; ok=0; }
    [ -e /usr/bin/python ] || c_ylw "/usr/bin/python 不存在（A14 某些脚本还要它）"

    if command -v ccache >/dev/null; then
        echo "ccache: $(command -v ccache)"
        CCACHE_DIR="$CCACHE_DIR" ccache -s 2>/dev/null | sed -n '1,8p' || true
    fi

    local mem_gb swap_gb
    mem_gb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
    swap_gb=$(( $(awk '/SwapTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
    echo "内存: ${mem_gb}G  交换: ${swap_gb}G"
    [ $((mem_gb + swap_gb)) -lt 40 ] && c_ylw "内存+交换 < 40G，-j8 bacon 可能仍会 OOM"

    df -h "$(dirname "$OUT_DIR")" | tail -1 | awk '{print "磁盘: 已用 "$3" 可用 "$4}'

    if [ -f "$ROM_DIR/vendor/lineage-priv/keys/keys.mk" ]; then
        c_grn "签名密钥: vendor/lineage-priv/keys 已就位"
        grep -m1 'PRODUCT_DEFAULT_DEV_CERTIFICATE' "$ROM_DIR/vendor/lineage-priv/keys/keys.mk" || true
    else
        c_ylw "签名密钥缺失 —— 会退回 AOSP testkey（ro.build.tags=test-keys）"
    fi

    [ "$ok" = 1 ] && c_grn "基本可用" || c_ylw "有缺项，见上面"
}

cmd_init() {
    step "repo init → $ROM_DIR ($MANIFEST_BRANCH)"
    mkdir -p "$ROM_DIR"
    cd "$ROM_DIR"
    $(repo_bin) init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" \
        --git-lfs --depth=1 -g default,-notdefault,-infra --no-clone-bundle

    step "安装 local_manifests/$LOCAL_MANIFEST_NAME → .repo/local_manifests/cannon.xml"
    mkdir -p .repo/local_manifests
    [ -f "$SRC_DIR/local_manifests/$LOCAL_MANIFEST_NAME" ] || die "缺 local_manifests/$LOCAL_MANIFEST_NAME"
    cp "$SRC_DIR/local_manifests/$LOCAL_MANIFEST_NAME" .repo/local_manifests/cannon.xml
    c_grn "已写入 .repo/local_manifests/cannon.xml（源=$LOCAL_MANIFEST_NAME）"
}

cmd_sync() {
    [ -d "$ROM_DIR/.repo" ] || die "$ROM_DIR 不是 repo 工作区，先跑 ./build.sh init"
    step "repo sync（首次约 60-80G）"
    cd "$ROM_DIR"
    $(repo_bin) sync -c --force-sync --force-remove-dirty --no-tags \
        --no-clone-bundle -j"$(nproc)" --optimized-fetch --prune

    if [ -f vendor/lineage-priv/keys/keys.mk ]; then
        c_grn "签名密钥已同步"
    else
        c_ylw "vendor/lineage-priv/keys 没拉到（private 仓库，检查 ssh key 和 org 权限）"
    fi
}

cmd_apply() {
    if [ "$APPLY_PATCHES" != "1" ]; then
        c_ylw "未启用补丁（APPLY_PATCHES=0），跳过"
        return 0
    fi
    # A17：Connectivity 的补丁必须打在固定提交 d468719 之上，所以 pin 必须先于补丁
    # 判据用 PATCH_SUBDIR（apply_a17_profile 里设），不用 PROFILE：
    # `./build.sh a17` 分支只调 apply_a17_profile，不会设置 PROFILE，用 PROFILE 判断会被静默跳过。
    if [ "${PATCH_SUBDIR:-}" = "a17" ]; then
        bash "$SRC_DIR/scripts/pin_a17_connectivity.sh" "$ROM_DIR" || die "Connectivity 固定失败"
    fi

    step "应用构建期补丁（幂等：仓库里已提交的改动会自动跳过）"
    local script="$APPLY_SCRIPT"
    [ -n "$script" ] || script="$SRC_DIR/scripts/apply_a14_cannon_patches.sh"
    [ -f "$script" ] || die "找不到 $script"
    CANNON_PATCHDIR="${CANNON_PATCHDIR:-$SRC_DIR/repro/patches/${PATCH_SUBDIR:-a15}}" \
        bash "$script" "$ROM_DIR"
}

# siso 1.5.8 的 --config_repo_dir 只认相对路径：OUT_DIR 是树外绝对路径时，
# soong 会传绝对的 --config_repo_dir，siso 直接报
#   failed to load @config//main.star: open main.star: no such file or directory
# 处理：在源码树内建 out -> $OUT_DIR 软链，把 OUT_DIR 换成相对的 out（产物仍在原位置）。
normalize_out_dir() {
    case "$OUT_DIR" in
        /*)
            [ "$OUT_DIR" = "$ROM_DIR/out" ] && return 0
            mkdir -p "$OUT_DIR"
            if [ -e "$ROM_DIR/out" ] && [ ! -L "$ROM_DIR/out" ]; then
                die "$ROM_DIR/out 是真实目录，与 OUT_DIR=$OUT_DIR 冲突；先移走它"
            fi
            ln -sfn "$OUT_DIR" "$ROM_DIR/out"
            c_ylw "OUT_DIR 在源码树外 → 已建软链 $ROM_DIR/out -> $OUT_DIR，改用 OUT_DIR=out（规避 siso 绝对路径 bug）"
            OUT_DIR="out"
            ;;
    esac
}

cmd_build() {
    [ -f "$ROM_DIR/build/envsetup.sh" ] || die "源码不完整，先跑 ./build.sh sync"
    normalize_out_dir
    [ -n "${OUT_DIR:-}" ] || die "OUT_DIR 必须设置"   # 不设会落到 $ROM_DIR/out，白编 17 万步

    step "编译 → $LUNCH_TARGET  (OUT_DIR=$OUT_DIR, -j$JOBS)"
    mkdir -p "$(dirname "$LOG")"
    : > "$LOG"
    cd "$ROM_DIR"

    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache || true)"
    export CCACHE_DIR CCACHE_MAXSIZE=50G
    # GOGC 用 Go 默认 100。30 是 27G 内存时代为压低 soong_build 峰值堆设的；
    # 本机 64G，30 只会让 Go runtime 频繁 GC（siso 报 memory stall 500~900ms/s）。
    export GOGC="${GOGC:-100}"
    # GOMEMLIMIT 不设：软限低于实际需求时，runtime 会在极限附近疯狂 GC
    # （44GiB 时 heap 到 40GB+，memory stall 600~700ms/s，全量分析拖到 40 分钟以上）。
    # export GOMEMLIMIT="${GOMEMLIMIT:-44GiB}"
    export OUT_DIR

    # A17 铁律：一律 siso，绝不回退 ninja（见 docs/A17_SISO_NEVER_NINJA.md）。
    # 手动 `m` 时若漏掉上面这几个变量，命令指纹会变 → 整片重编，所以统一从这里进。
    if [ "${SOONG_NINJA:-siso}" != "siso" ]; then
        die "SOONG_NINJA 必须是 siso，禁止回退 ninja"
    fi
    export SOONG_NINJA=siso
    # 增量分析：只有显式 true 才走，不设=全量（config.go:359）。
    # soong_build 无论增量都要加载全图（~40G），增量省的是重算时间。
    export SOONG_INCREMENTAL_ANALYSIS=true

    # 不设的话 soong 会用 "eng.<用户名>.<时间戳>"（build/soong/ui/build/build.go:73），
    # ro.build.version.incremental 就变成 eng.root.20261027.103315 这种难看的串
    export BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d)}"

    c_ylw "环境: OUT_DIR=$OUT_DIR CCACHE_DIR=$CCACHE_DIR CCACHE_EXEC=$CCACHE_EXEC GOGC=$GOGC JOBS=$JOBS BUILD_NUMBER=$BUILD_NUMBER SOONG_NINJA=$SOONG_NINJA"

    # shellcheck disable=SC1091
    source build/envsetup.sh >/dev/null
    # A16 的 lunch 需三参（product release variant），已由 apply_a16_profile 写入 LUNCH_ARGS；
    # A14/A15 用单参 LUNCH_TARGET（三段式单串，旧 lunch 可解析）。
    if [ "${#LUNCH_ARGS[@]}" -gt 0 ]; then
        lunch "${LUNCH_ARGS[@]}"
    else
        lunch "$LUNCH_TARGET"
    fi

    # 2026-11-08: 原 workaround（先 m vendorimage 再 bacon）已删除。根因（target_files
    # 打包对 vendor.img 本体无依赖 → 并发抢跑：No such file / 无 AVB footer / sparse 头
    # 半截）已由 build/make/core/Makefile 的显式依赖修复（repro/patches/a17/build_make.patch）。
    # 正式版出包注意：zip 内日期取 kati 生成时的 date，出正式包前需清 kati ninja 缓存
    # （rm $OUT/soong/build.lineage_cannon.*.ninja）并显式传 BUILD_NUMBER=<正式版日期>。

    local start; start=$(date +%s)
    m -j"$JOBS" bacon 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] || die "编译失败（rc=$rc），看 $LOG"

    c_grn "完成，用时 $(( ($(date +%s) - start) / 60 )) 分钟"
    ls -lh "$OUT_DIR"/target/product/cannon/lineage-*.zip 2>/dev/null || true
}

# 单模块/单目标编译：走同一套环境、同一个日志，避免手敲漏变量
#   PROFILE=a17 CANNON_VARIANT=userdebug ./build.sh module librenderengine
cmd_module() {
    [ $# -ge 1 ] || die "用法: ./build.sh module <target> [target...]"
    [ -f "$ROM_DIR/build/envsetup.sh" ] || die "源码不完整，先跑 ./build.sh sync"
    normalize_out_dir
    step "编译目标: $*  (OUT_DIR=$OUT_DIR, -j$JOBS)"
    mkdir -p "$(dirname "$LOG")"
    cd "$ROM_DIR"

    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache || true)"
    export CCACHE_DIR CCACHE_MAXSIZE=50G
    # GOGC 用 Go 默认 100。30 是 27G 内存时代为压低 soong_build 峰值堆设的；
    # 本机 64G，30 只会让 Go runtime 频繁 GC（siso 报 memory stall 500~900ms/s）。
    export GOGC="${GOGC:-100}"
    # GOMEMLIMIT 不设：软限低于实际需求时，runtime 会在极限附近疯狂 GC
    # （44GiB 时 heap 到 40GB+，memory stall 600~700ms/s，全量分析拖到 40 分钟以上）。
    # export GOMEMLIMIT="${GOMEMLIMIT:-44GiB}"
    export OUT_DIR
    export BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d)}"
    export SOONG_NINJA=siso
    export SOONG_INCREMENTAL_ANALYSIS=true

    c_ylw "环境: OUT_DIR=$OUT_DIR CCACHE_DIR=$CCACHE_DIR CCACHE_EXEC=$CCACHE_EXEC GOGC=$GOGC JOBS=$JOBS BUILD_NUMBER=$BUILD_NUMBER"

    # shellcheck disable=SC1091
    source build/envsetup.sh >/dev/null
    if [ "${#LUNCH_ARGS[@]}" -gt 0 ]; then
        lunch "${LUNCH_ARGS[@]}"
    else
        lunch "$LUNCH_TARGET"
    fi

    echo "=== module build: $* $(date -u '+%F %T') UTC ===" >> "$LOG"
    m -j"$JOBS" "$@" 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] || die "编译失败（rc=$rc），看 $LOG"
    c_grn "完成: $*"
}

case "${1:-}" in
    doctor) cmd_doctor ;;
    init)   cmd_init ;;
    sync)   cmd_sync ;;
    build)  cmd_build ;;
    module) shift; cmd_module "$@" ;;
    all)    cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a14)    cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a15)    apply_a15_profile; cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a16)    apply_a16_profile; cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a17)    apply_a17_profile; cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    *)      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
