#!/usr/bin/env bash
# cannon A17（LineageOS 24.0 / Android 17）专用构建入口 —— 锁定清单模式
#
#   ./build-a17.sh doctor          环境体检
#   ./build-a17.sh init            repo init 到 manifests/a17-pinned-*.xml（全 SHA，不跟分支）
#   ./build-a17.sh sync            repo sync（按锁定 SHA 出树）
#   ./build-a17.sh apply           重放 A17 构建期补丁（幂等）
#   ./build-a17.sh build           lunch + m bacon
#   ./build-a17.sh module <tgt>    单目标编译（同 build.sh module）
#   ./build-a17.sh all             init + sync + apply + build
#
# 与 `PROFILE=a17 ./build.sh ...` 的唯一区别：init/sync 用**锁定清单**而不是
# local_manifests + 分支。公有上游仓在 cannon-a17.xml 里跟 refs/heads/lineage-24.0，
# 分支一前进，repro/patches/a17/*.patch（按导出当天 HEAD 生成）就会 drift；
# 锁定清单把 1241 个 project 全钉在 40 位 SHA 上，sync 出来的树 = 导出当天。
#
# 可覆盖的环境变量：
#   PINNED_MANIFEST   默认 latest（manifests/ 下最新的 .xml），也可给具体文件名/绝对路径
#   CANNON_VARIANT    默认 userdebug（**不要**改成 eng/user：会触发 installclean 全量重编）
#   CANNON_RELEASE    默认 cp2a
#   JOBS / OUT_DIR / LOG / ROM_DIR  同 build.sh
#
# 校验当前树是否就是清单状态：
#   bash scripts/check_a17_pinned.sh manifests/a17-pinned-*.xml
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

export PROFILE=a17
export CANNON_VARIANT="${CANNON_VARIANT:-userdebug}"
export CANNON_RELEASE="${CANNON_RELEASE:-cp2a}"
export PINNED_MANIFEST="${PINNED_MANIFEST:-latest}"

case "${1:-}" in
    ""|-h|--help|help)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

exec "$SRC_DIR/build.sh" "$@"
