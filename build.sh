#!/usr/bin/env bash
# Xiaomi cannon / cannong (MT6853T) — LineageOS 21 一键构建
#
#   ./build.sh doctor   环境体检
#   ./build.sh init     repo init + 安装 local_manifests
#   ./build.sh sync     repo sync
#   ./build.sh build    lunch + m bacon
#   ./build.sh all      init + sync + build            （A14 / LineageOS 21，默认）
#   ./build.sh a15      A15 专用：init + sync + apply 补丁 + build（LineageOS 22.2）
#   ./build.sh a16      A16 专用：init + sync + apply 补丁 + build（LineageOS 23.2 / Android 16）
#
# A14 不受影响：不选 a15、不设 PROFILE=a15 时，行为与旧版完全一致。
# 也可用环境变量覆盖：PROFILE=a15 ./build.sh all
#
set -euo pipefail

ROM_DIR="${ROM_DIR:-/cannon/rom}"
OUT_DIR="${OUT_DIR:-/cannon/out}"
LOG="${LOG:-/cannon/build.log}"
CCACHE_DIR="${CCACHE_DIR:-/cannon/ccache}"
JOBS="${JOBS:-8}"                       # bacon 在 -j16 会 OOM（exit 137），别调高
LUNCH_TARGET="${LUNCH_TARGET:-lineage_cannon-ap2a-userdebug}"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/LineageOS/android.git}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-lineage-21.0}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- local_manifests 与补丁开关（A14 默认值保持不变）----
LOCAL_MANIFEST_NAME="${LOCAL_MANIFEST_NAME:-cannon.xml}"
APPLY_PATCHES="${APPLY_PATCHES:-0}"
# ---- 按 profile 选择的辅助变量（A14 默认空）----
LUNCH_ARGS=()          # 非空时 cmd_build 用多参 lunch（A16 需三参：product release variant）
APPLY_SCRIPT=""        # profile 决定用哪个 apply_*_cannon_patches.sh
PATCH_SUBDIR=""        # repro/patches/<PATCH_SUBDIR>（a15 / a16）

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
# 目标：lunch lineage_cannon bp4a userdebug，local_manifests 用 cannon-23.2.xml，
#       编译前重放 A16 构建期补丁（apply_a16，幂等）。
apply_a16_profile() {
    MANIFEST_BRANCH="lineage-23.2"
    LUNCH_TARGET="lineage_cannon-bp4a-userdebug"    # 仅用于显示/兼容旧逻辑
    LUNCH_ARGS=(lineage_cannon bp4a userdebug)      # A16 首轮实际三参 userdebug（build-a16.log:34 证实；发布期再切 user）
    LOCAL_MANIFEST_NAME="cannon-23.2.xml"
    APPLY_PATCHES="1"
    APPLY_SCRIPT="$SRC_DIR/scripts/apply_a16_cannon_patches.sh"
    PATCH_SUBDIR="a16"
}
[ "${PROFILE:-}" = "a16" ] && apply_a16_profile

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
        c_ylw "非补丁 profile，跳过补丁（A14 不需要）"
        return 0
    fi
    step "应用构建期补丁（幂等：仓库里已提交的改动会自动跳过）"
    local script="$APPLY_SCRIPT"
    [ -n "$script" ] || script="$SRC_DIR/scripts/apply_a15_cannon_patches.sh"
    [ -f "$script" ] || die "找不到 $script"
    CANNON_PATCHDIR="${CANNON_PATCHDIR:-$SRC_DIR/repro/patches/${PATCH_SUBDIR:-a15}}" \
        bash "$script" "$ROM_DIR"
}

cmd_build() {
    [ -f "$ROM_DIR/build/envsetup.sh" ] || die "源码不完整，先跑 ./build.sh sync"
    [ -n "${OUT_DIR:-}" ] || die "OUT_DIR 必须设置"   # 不设会落到 $ROM_DIR/out，白编 17 万步

    step "编译 → $LUNCH_TARGET  (OUT_DIR=$OUT_DIR, -j$JOBS)"
    mkdir -p "$(dirname "$LOG")"
    cd "$ROM_DIR"

    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache || true)"
    export CCACHE_DIR CCACHE_MAXSIZE=50G
    export GOGC=50
    export OUT_DIR

    # 不设的话 soong 会用 "eng.<用户名>.<时间戳>"（build/soong/ui/build/build.go:73），
    # ro.build.version.incremental 就变成 eng.root.20261027.103315 这种难看的串
    export BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d)}"

    # shellcheck disable=SC1091
    source build/envsetup.sh >/dev/null
    # A16 的 lunch 需三参（product release variant），已由 apply_a16_profile 写入 LUNCH_ARGS；
    # A14/A15 用单参 LUNCH_TARGET（三段式单串，旧 lunch 可解析）。
    if [ "${#LUNCH_ARGS[@]}" -gt 0 ]; then
        lunch "${LUNCH_ARGS[@]}"
    else
        lunch "$LUNCH_TARGET"
    fi

    local start; start=$(date +%s)
    m -j"$JOBS" bacon 2>&1 | tee "$LOG"
    local rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] || die "编译失败（rc=$rc），看 $LOG"

    c_grn "完成，用时 $(( ($(date +%s) - start) / 60 )) 分钟"
    ls -lh "$OUT_DIR"/target/product/cannon/lineage-*.zip 2>/dev/null || true
}

case "${1:-}" in
    doctor) cmd_doctor ;;
    init)   cmd_init ;;
    sync)   cmd_sync ;;
    build)  cmd_build ;;
    all)    cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a15)    apply_a15_profile; cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    a16)    apply_a16_profile; cmd_init; cmd_sync; cmd_apply; cmd_build ;;
    *)      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
