# cannon-build

Xiaomi Redmi Note 9T 5G（`cannon` / `cannong`，MT6853T）在 A12 厂商底座上的 LineageOS 构建入口。
clone 本仓 → 一条 `./build.sh` → 出包，不依赖任何本机手工改动。

## 支持版本

| 命令 | LineageOS | Android | release | 变体 | lunch |
|---|---|---|---|---|---|
| `./build.sh all` | 21.0 | 14 | `ap2a` | `userdebug` | `lineage_cannon-ap2a-userdebug` |
| `./build.sh a15` | 22.2 | 15 | `bp1a` | `user` | `lineage_cannon-bp1a-user` |
| `./build.sh a16` | 23.2 | 16 | `bp4a` | `user` | `lineage_cannon bp4a user` |
| `./build.sh a17` | 24.0 | 17 | `cp2a` | `userdebug` | `lineage_cannon cp2a userdebug` |

A16 / A17 的 lunch 是三参（product / release / variant），A14 / A15 是单串。

A17 的固定命令、环境变量与内核路线见 [`BUILD_A17.md`](BUILD_A17.md)。

## 前置条件

- 内存 + swap ≥ 40G
- 磁盘 ≥ 300G（源码 ~68G + out 100G+ + ccache）
- `ccache`、`git-lfs`、`python3`，以及 `/usr/bin/python` 软链
- `~/.ssh/config` 里 `github.com` 走 `ssh.github.com:443`（22 端口被封时）

## 使用

```bash
git clone git@github.com:top-android/cannon-build.git
cd cannon-build

./build.sh doctor     # 环境体检
./build.sh a17        # init + sync + apply 补丁 + build
```

分步执行：

| 命令 | 作用 |
|---|---|
| `./build.sh init` | `repo init` + 安装 `local_manifests/<profile>.xml` |
| `./build.sh sync` | `repo sync` |
| `./build.sh apply` | 重放构建期补丁（幂等） |
| `./build.sh build` | `lunch` + `m bacon` |
| `./build.sh module <target>` | 单模块编译，共用同一套环境与日志 |

`PROFILE=<a15\|a16\|a17>` 可让 `all` 使用指定 profile（不设即 A14 默认）；`a15` / `a16` / `a17` 子命令自带 profile。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ROM_DIR` | `/cannon/rom` | 源码目录 |
| `OUT_DIR` | `/cannon/out` | 输出目录，必须显式设置 |
| `LOG` | `/cannon/build.log` | 编译日志 |
| `CCACHE_DIR` | `/cannon/ccache` | ccache 目录 |
| `JOBS` | `$(nproc)` | 并行度，内存不足时下调 |
| `CANNON_VARIANT` | profile 默认 | 构建变体 |
| `CANNON_RELEASE` | profile 默认 | release 代号 |

其余变量（`SOONG_NINJA`、`CCACHE_EXEC`、`GOGC` 等）由 `build.sh` 固定，不要临时增删——会改变编译命令指纹，触发全量重编。

## 仓库布局

改动分两类：**自有分支**（上游没有、或有独立历史）与**构建期补丁**（其余仓指向上游，改动在编译前叠加）。

| 路径 | 来源 | 说明 |
|---|---|---|
| `device/xiaomi/cannon` | top-android | 设备树 |
| `vendor/xiaomi/cannon` | top-android | vendor blob 修正 |
| `kernel/xiaomi/cannon` | top-android | 内核，默认 `lineage-21-cannon` |
| `hardware/mediatek/wlan` | top-android | 上游无独立仓 |
| `packages/modules/Wifi` | top-android | HAL 空指针旁路 |
| `vendor/lineage-priv/keys` | 私有 | 签名密钥，**必须 private** |
| 其余（`build/make`、`frameworks/*`、`system/core`、`packages/modules/*` 等） | 上游 | 补丁在 `repro/patches/{a14_orphan,a15,a16,a17}` |

补丁由 `scripts/apply_a*.sh` 在编译前重放，幂等；`scripts/export_a16_dirty_patches.sh` 从源码树导出。

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
