# cannon-build

Xiaomi Redmi Note 9T 5G（`cannon` / `cannong`，MT6853T）在 A12 厂商底座上的 LineageOS 构建入口。
A17（LineageOS 24.0）走**全 fork 单轨**：clone 本仓 → `./build-a17.sh all` → 出包，不依赖本机手工改动。

## 支持版本

| 命令 | LineageOS | Android | release | 变体 | lunch |
|---|---|---|---|---|---|
| `./build.sh all` | 21.0 | 14 | `ap2a` | `userdebug` | `lineage_cannon-ap2a-userdebug` |
| `./build.sh a15` | 22.2 | 15 | `bp1a` | `user` | `lineage_cannon-bp1a-user` |
| `./build.sh a16` | 23.2 | 16 | `bp4a` | `user` | `lineage_cannon bp4a user` |
| `./build.sh a17` | 24.0 | 17 | `cp2a` | `userdebug` | `lineage_cannon cp2a userdebug` |
| `./build-a17.sh all` | 24.0 | 17 | `cp2a` | `userdebug` | 同上（**锁定清单模式**，见下） |

A16 / A17 的 lunch 是三参（product / release / variant），A14 / A15 是单串。

A17 的固定命令、环境变量与内核路线见 [`BUILD_A17.md`](BUILD_A17.md)。

> **A17 用 `./build-a17.sh`**：它固定 `PROFILE=a17`，init 用 `manifests/a17-pinned-*.xml`
> （1241 个 project 全钉 SHA），并自动安装 `local_manifests/cannon-a17.xml`
> （23 个仓指向 `top-android/*` 的 `cannon-a17` 分支）。sync 后**没有 apply 阶段**。
> 校验：`bash scripts/check_a17_pinned.sh manifests/a17-pinned-*.xml`。

## 全新环境全量编译（从零到 zip）

### 1. 系统依赖（一次性）

```bash
apt update && apt install -y git repo git-lfs ccache zip unzip \
  libssl-dev libelf-dev bc bison flex python3 pkg-config
gh auth login && gh auth setup-git   # 私有 keys 仓走 https 时需要
```

- 磁盘：源码 ~80G + out ~40G + ccache 50G，建议 ≥200G 可用
- 内存 + swap ≥ 40G（`-j8 bacon` 的底线）
- 目录可用 `ROM_DIR` / `OUT_DIR` 覆盖（默认 `/cannon/rom`、`/cannon/out`）

### 2. clone 并编译

```bash
git clone https://github.com/top-android/cannon-build.git
cd cannon-build

./build-a17.sh doctor   # 体检：git/python3/ccache/内存/磁盘/签名密钥
./build-a17.sh all      # init（锁定清单 + cannon-a17.xml）→ sync → build
```

`all` 里没有 apply 阶段：A17 的修复全部在 `top-android` 各仓的 `cannon-a17` 分支，sync 完即带修复。

### 3. 选择变体（默认 userdebug）

`CANNON_VARIANT` 控制变体。**每个变体给独立 OUT_DIR**，否则切换会触发 installclean，
删掉 `out/target/product/cannon/` 下已装好的 system/vendor 等并接近全量重编：

| 变体 | 命令 | 说明 |
|---|---|---|
| `userdebug`（默认） | `./build-a17.sh all` | `ro.debuggable=1`，日常调试 |
| `user` | `OUT_DIR=/cannon/out-user CANNON_VARIANT=user ./build-a17.sh all` | 发布包，需要签名 keys |
| `eng` | `OUT_DIR=/cannon/out-eng CANNON_VARIANT=eng ./build-a17.sh all` | 工程变体，无优化 |

源码已同步、只想换变体出包时用 `build`：

```bash
OUT_DIR=/cannon/out-user CANNON_VARIANT=user ./build-a17.sh build
OUT_DIR=/cannon/out-eng  CANNON_VARIANT=eng  ./build-a17.sh build
```

确实要就地切换同一个 OUT_DIR，必须加 `CANNON_ALLOW_VARIANT_SWITCH=1`（会 installclean）。
产物分别在各自的 `OUT_DIR/target/product/cannon/` 下，日志仍写 `LOG`（默认 `/cannon/build.log`，
建议按变体覆盖，如 `LOG=/cannon/build-user.log`）。

### 4. 分步等价

| 命令 | 作用 |
|---|---|
| `./build-a17.sh init` | 装 `manifests/a17-pinned-*.xml` + `local_manifests/cannon-a17.xml` |
| `./build-a17.sh sync` | `repo sync`（首次约 60~80G） |
| `./build-a17.sh build` | `lunch lineage_cannon cp2a userdebug` + `m bacon` |
| `./build-a17.sh module <target>` | 单模块编译 |

常见坑：

- 不要用裸 `./build.sh` 跑 A17：它不会设置 A17 profile，会装错 manifest
- `OUT_DIR` 在源码树外时，脚本会自动建 `$ROM_DIR/out` 软链（siso 要求相对路径）
- `vendor/lineage-priv/keys` 是私有仓，local manifest 已改成 https（不依赖 SSH key）；
  没有凭据也能编，但会退回 testkey（`ro.build.tags=test-keys`）
- 不同变体给独立 `OUT_DIR`，否则触发 installclean 冲掉已有产物

## 前置条件

- 内存 + swap ≥ 40G
- 磁盘 ≥ 200G（源码 ~80G + out 40G + ccache 50G）
- `ccache`、`git-lfs`、`python3`、`repo`，以及 `/usr/bin/python` 软链

## 使用（A14 / A15 / A16）

A17 见上文「全新环境全量编译」，其它版本：

```bash
git clone https://github.com/top-android/cannon-build.git
cd cannon-build

./build.sh doctor
./build.sh all      # A14（LineageOS 21）
./build.sh a15      # A15（22.2）
./build.sh a16      # A16（23.2）
```

| 命令 | 作用 |
|---|---|
| `./build.sh init` | `repo init` + 安装 `local_manifests/<profile>.xml`（分支模式） |
| `./build.sh sync` | `repo sync`（浅克隆 `--depth=1`；失败会提示先 `check`） |
| `./build.sh check` | 校验各项目是否仍是浅克隆，`missing` 必须为 0 |
| `./build.sh repair` | 对退化成完整历史的项目删记录后单项目重拉，恢复浅克隆 |
| `./build.sh apply` | 重放构建期补丁（A14–A16 使用；A17 已关闭） |
| `./build.sh build` | `lunch` + `m bacon` |
| `./build.sh module <target>` | 单模块编译，共用同一套环境与日志 |

`build-a17.sh` 子命令相同（`doctor/init/sync/apply/build/module/all`），A17 下 `apply` 为空操作；
`PINNED_MANIFEST=<路径|latest>` 可指定用哪份锁定清单。

`PROFILE=<a15|a16|a17>` 可让 `all` 使用指定 profile（不设即 A14 默认）；`a15` / `a16` / `a17` 子命令自带 profile。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ROM_DIR` | `/cannon/rom` | 源码目录 |
| `OUT_DIR` | `/cannon/out` | 输出目录，必须显式设置 |
| `LOG` | `/cannon/build.log` | 编译日志 |
| `CCACHE_DIR` | `/cannon/ccache` | ccache 目录 |
| `JOBS` | `$(nproc)` | 并行度，内存不足时下调 |
| `CANNON_VARIANT` | profile 默认 | 构建变体：`userdebug`（默认）/ `eng` / `user` |
| `CANNON_RELEASE` | profile 默认 | release 代号 |
| `CANNON_ALLOW_VARIANT_SWITCH` | `0` | `1` = 允许切换变体（会 installclean + 接近全量重编） |
| `PINNED_MANIFEST` | `latest` | 仅 `build-a17.sh`：锁定清单路径，`latest` = `manifests/` 下最新 |

其余变量（`SOONG_NINJA`、`CCACHE_EXEC` 等）由 `build.sh` 固定，不要临时增删——会改变编译命令指纹，触发全量重编。
`GOGC` 由 `build.sh` 设为 `100`，可用同名环境变量覆盖，不影响指纹。

### 切换变体的细节

`build-a17.sh` 会比对 `$OUT_DIR/target/product/cannon/previous_build_config.mk`，变体不一致就中止；
确定要就地切同一 OUT_DIR 时加 `CANNON_ALLOW_VARIANT_SWITCH=1`（会 installclean，约 12 万步重编）。
推荐按上文「3. 选择变体」给每个变体独立 OUT_DIR。

> ⚠ `device.mk` 里的 eng ADB 属性矩阵（`ro.secure=0` / `ro.adb.secure=0` / `service.adb.root=1`）
> 在 `user` 变体里也会写进 `/product/build.prop`，正式发布前必须改回。

## 仓库布局

A17 是**全 fork 单轨**：23 个需要修复的 project 都指向 `top-android/*` 的 `cannon-a17` 分支，
`repro/patches/a17` 仅作归档、不参与构建。A14 / A15 / A16 仍沿用「自有分支 + 构建期补丁」。

| 路径 | 来源 | 说明 |
|---|---|---|
| `device/xiaomi/cannon` | top-android | 设备树（A17: `cannon-a17`） |
| `vendor/xiaomi/cannon` | top-android | vendor blob 修正 |
| `kernel/xiaomi/cannon` | top-android | 内核，A17 用 `lineage-24.0-cannon` |
| `hardware/mediatek` / `hardware/mediatek/wlan` | top-android | 上游无独立仓 |
| `packages/modules/Wifi` | top-android | HAL 空指针旁路 |
| `vendor/lineage-priv/keys` | 私有 | 签名密钥，**必须 private**（https + gh 凭据） |
| A17 其余 18 个仓 | top-android | art / build / frameworks / packages / system 等，均 `cannon-a17` |
| A14–A16 其余仓 | 上游 | 补丁在 `repro/patches/{a14_orphan,a15,a16}` |

A14–A16 的补丁由 `scripts/apply_a*.sh` 在编译前重放（幂等）；`scripts/export_a16_dirty_patches.sh` 从源码树导出。

## 签名

`vendor/lineage/config/common.mk` 会 `-include vendor/lineage-priv/keys/keys.mk`，自动设置
`PRODUCT_DEFAULT_DEV_CERTIFICATE` 与 `PRODUCT_CERTIFICATE_OVERRIDES`。

不要手改 `lineage_cannon.mk`，也不要用 `sign_target_files_apks` 二次签名。

换证书是一次性迁移：所有 APK 重签 + `otacert` 变更，必须整包 fastboot 刷 + `-w`。

## 刷机

同一签名版本上升级，不清数据：

```powershell
adb reboot sideload
adb sideload lineage-<版本>-XXXXXXXX-UNOFFICIAL-cannon.zip
```

首次刷机（从 MIUI 或其他 ROM 过来）：

```powershell
fastboot flash recovery recovery.img
fastboot reboot recovery
```

recovery 里 **Factory reset → Format data**，然后 **Apply update → Apply from ADB**，sideload 整包。
包内含 boot / dtbo / vbmeta / system / vendor / product / system_ext，无需单独刷。

## 已知问题

- 漏设 `OUT_DIR` → soong 落到 `$ROM_DIR/out`，从零编十几万步。
- `-j` 过大 → `ninja failed with: exit status 137`（OOM），下调 `JOBS`。
- 只设 `USE_CCACHE=1` 不生效，必须同时设 `CCACHE_EXEC`。
- `m vbmetaimage` 会因 hashtree 根哈希连坐重编 system/vendor，日常用 `m bootimage` 或整包 `bacon`。
- `fastboot -w` 后 recovery 下 adb 显示 `unauthorized`：recovery 只读 `/adb_keys`，先在系统里点一次「允许 USB 调试」。
- 动过原厂 super 元数据后不能单刷 system/vendor，需整包 sideload 重建 super。

## 许可

未声明开源许可，仅限内部使用。
