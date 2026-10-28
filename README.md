# top-android / cannon — LineageOS 21 构建

Xiaomi Redmi Note 9T 5G（`cannon` / `cannong`，MT6853T）在 A12 厂商底座上的
LineageOS 21（Android 14）构建入口。

目标：**clone 这一个仓库 → `./build.sh all` → 出包**，不再依赖任何本机手工 sed。

## 用法

```bash
git clone git@github.com:top-android/cannon-build.git
cd cannon-build

./build.sh doctor    # 先体检
./build.sh all       # init + sync + build（首次约 60-80G，几小时）
```

单独跑：

```bash
./build.sh init      # repo init + 安装 local_manifests/cannon.xml
./build.sh sync      # repo sync
./build.sh build     # lunch + m bacon
```

可调环境变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `ROM_DIR` | `/cannon/rom` | 源码目录 |
| `OUT_DIR` | `/cannon/out` | **必须显式设置**，否则 soong 落到 `$ROM_DIR/out` 从零编 17 万步 |
| `LOG` | `/cannon/build.log` | 编译日志 |
| `CCACHE_DIR` | `/cannon/ccache` | ccache 目录 |
| `JOBS` | `8` | `bacon` 在 `-j16` 会 OOM（exit 137） |
| `LUNCH_TARGET` | `lineage_cannon-ap2a-userdebug` | |

## 前置条件

- 内存 + swap ≥ 40G（34G 内存跑 `-j8 bacon` 是刚好够）
- 磁盘 ≥ 300G（源码 68G + out 100G+ + ccache）
- `ccache`、`git-lfs`、`python3`，以及 `/usr/bin/python` 软链
- ``/.ssh/config` 里 `github.com` 走 `ssh.github.com:443`（公司/校园网挡 22 端口时必需）

## 仓库布局

所有**带本地改动**的仓库都在 `top-android` 下，分支统一 `lineage-21-cannon`；
没改过的直接用 `LineageOS` 上游 `lineage-21`。见 `local_manifests/cannon.xml`。

| 路径 | 上游 | 为什么有改动 |
|---|---|---|
| `device/xiaomi/cannon` | xiaomi-mt6853-devs | 设备树，主战场 |
| `vendor/xiaomi/cannon` | xiaomi-mt6853-devs | blob 修正 |
| `kernel/xiaomi/cannon` | gtcock（SuSFS） | defconfig / emimpu / c2k_usb |
| `build/make` | LineageOS | core/Makefile、target/board |
| `frameworks/base` | LineageOS | SystemUI 媒体输出、StorageManager、隐藏 API |
| `frameworks/native` | LineageOS | binder 兼容 MTK A12 vendor |
| `frameworks/opt/telephony` | LineageOS | RIL |
| `hardware/mediatek` | LineageOS | power AIDL |
| `hardware/mediatek/wlan` | xiaomi-mt6853-devs | wifi_hal 构建 |
| `packages/modules/Bluetooth` | LineageOS | A2DP / HCI |
| `packages/modules/Connectivity` | LineageOS | NetBpfLoad 容错（bpf_attr 补丁已随内核 backport 回退） |
| `packages/modules/NetworkStack` | LineageOS | captive portal 探测地址本地化 |
| `packages/providers/MediaProvider` | LineageOS | TranscodeHelper |
| `system/bpf` | LineageOS | BpfLoader 容错 |
| `system/core` | LineageOS | RefBase |
| `vendor/lineage-priv/keys` | 私有仓库 | 签名密钥，**必须 private** |

`device/mediatek/sepolicy_vndr`、`hardware/xiaomi` 无改动，直接走上游。

> 移植过程中踩的坑、每个补丁的来龙去脉记在另一个**私有仓库**的 `docs/` 里
> （未公开，不提供链接）。

## 签名

`vendor/lineage/config/common.mk:264` 会 `-include vendor/lineage-priv/keys/keys.mk`，
里面的 `keys.mk` 自动设置：

- `PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey`
- `PRODUCT_CERTIFICATE_OVERRIDES`（A14 那几十个 apex / mainline 模块的 `*.certificate.override`）

**所以不要手改 `lineage_cannon.mk`**，也不要用 `sign_target_files_apks` 二次签名。

> ⚠️ 切自签是一次性迁移：所有 APK 重签 + `otacert` 变更，
> 首次必须整包 fastboot 刷 + `-w`，不能走增量 OTA。
> 切完以后这台机器只能用这一套证书，换证书等于再迁移一次。

## 刷机

### 日常升级（已经在同一签名版本上）

不清数据，两种都行：

**A. 系统更新** —— 设置 → 系统 → 系统更新 → 检查 → 下载 → 安装

**B. sideload**

```powershell
adb reboot sideload
adb sideload lineage-21.0-XXXXXXXX-UNOFFICIAL-cannon.zip
```

### 首次刷机（从 MIUI 或别的 ROM 过来）

只刷 recovery，其余由 OTA 包自己写：

```powershell
fastboot flash recovery recovery.img
fastboot reboot recovery
```

recovery 里：

1. **Factory reset → Format data**（从 MIUI 过来必须清）
2. **Apply update → Apply from ADB**
3. `adb sideload lineage-21.0-XXXXXXXX-UNOFFICIAL-cannon.zip`

包里带 boot / dtbo / vbmeta / system / vendor / product / system_ext，不用单独刷。

### 从 testkey 老版本迁移（仅一次）

20261027 及更早是 AOSP testkey 签的，和现在的自签 key 不兼容，sideload 会验签失败。必须全量 fastboot + `-w`：

```powershell
fastboot flash boot boot.img
fastboot flash recovery recovery.img
fastboot flash dtbo dtbo.img
fastboot flash vbmeta vbmeta.img
fastboot flash vbmeta_system vbmeta_system.img
fastboot flash vbmeta_vendor vbmeta_vendor.img
fastboot -w
fastboot reboot fastboot
fastboot flash system system.img
fastboot flash vendor vendor.img
fastboot flash product product.img
fastboot flash system_ext system_ext.img
fastboot reboot
```

boot / recovery / dtbo / vbmeta 是物理分区（bootloader 刷），system / vendor / product / system_ext 在 super 里是逻辑分区（必须 fastbootd）。走完这一次，以后都走上面的 sideload。

---

## 已知坑

1. **漏 `OUT_DIR`** → soong 用 `$ROM_DIR/out`，从零编 177774 步。日志里看到 `/cannon/rom/out/...` 就是踩了。
2. **`m -j16 bacon` 被 OOM 杀** → `ninja failed with: exit status 137`，内核日志有 `oom-killer`。用 `-j8`。
3. **只设 `USE_CCACHE=1` 不生效**（A14/soong）→ 必须设 `CCACHE_EXEC`。
4. **`m vbmetaimage` 会连坐重编** → 它依赖 system/vendor 的 hashtree 根哈希。日常只 `m bootimage` 或整包 `bacon`。
5. **`fastboot -w` 之后 recovery 下 adb 是 `unauthorized`** → recovery 只认 `/adb_keys`，靠 `copy_userdata_files()` 从 `/data/misc/adb/adb_keys` 复制；`/data` 刚清空就没有。先在系统里点一次"允许 USB 调试"。
6. **动过原厂之后不能单刷 system/vendor** → 原厂把 super 元数据整个换了（缺 `system_ext`），必须走完整 OTA sideload 重建 super。
