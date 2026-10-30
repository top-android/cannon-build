# top-android / cannon — LineageOS 21 / 22.2 构建

Xiaomi Redmi Note 9T 5G（`cannon` / `cannong`，MT6853T）在 A12 厂商底座上的构建入口。
支持两套目标：

- **A14 / LineageOS 21**（默认，`lineage_cannon-ap2a-userdebug`）
- **A15 / LineageOS 22.2**（`lineage_cannon-bp1a-user`，已适配完成并发布）

目标：**clone 这一个仓库 → 一条 `./build.sh` 命令 → 出包**，不再依赖任何本机手工 sed。

## 用法

```bash
git clone git@github.com:top-android/cannon-build.git
cd cannon-build

./build.sh doctor    # 先体检

# A14（默认）：LineageOS 21
./build.sh all       # init + sync + build（首次约 60-80G，几小时）

# A15：LineageOS 22.2（已适配，产出 user 变体）
./build.sh a15       # init(lineage-22.2) + sync + apply A15 补丁(幂等) + build
```

`a15` 与 `all` 的差别只是切几个变量，**`all`（A14）默认行为完全不变**：

| 项 | `all`（A14 默认） | `a15` |
|---|---|---|
| `MANIFEST_BRANCH` | `lineage-21.0` | `lineage-22.2` |
| `LOCAL_MANIFEST_NAME` | `cannon.xml` | `cannon-22.2.xml` |
| `LUNCH_TARGET` | `lineage_cannon-ap2a-userdebug` | `lineage_cannon-bp1a-user` |
| 编译前补丁 | 无 | `apply_a15_cannon_patches.sh`（幂等，已提交进 fork 的自动跳过） |

也可用环境变量临时切：`PROFILE=a15 ./build.sh all`。

单独跑：

```bash
./build.sh init      # repo init + 安装 local_manifests/<profile 对应>.xml
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

> 选 `a15`（或 `PROFILE=a15`）会覆盖 `MANIFEST_BRANCH` / `LOCAL_MANIFEST_NAME` / `LUNCH_TARGET`
> 并启用编译前补丁，见上面 profile 对照表；不选就是 A14 默认。

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
| `kernel/xiaomi/cannon` | top-android | defconfig / emimpu / c2k_usb / bpf 回填；默认取 `lineage-21-cannon`（无 KSU），KSU/SUSFS 见 boot 变体 |
| `build/make` | LineageOS | core/Makefile、target/board |
| `frameworks/base` | LineageOS | SystemUI 媒体输出、StorageManager、隐藏 API |
| `frameworks/native` | LineageOS | binder 兼容 MTK A12 vendor |
| `frameworks/opt/telephony` | LineageOS | RIL |
| `hardware/mediatek` | LineageOS | power AIDL |
| `hardware/mediatek/wlan` | xiaomi-mt6853-devs | wifi_hal 构建 |
| `packages/modules/Bluetooth` | LineageOS | A2DP / HCI |
| `packages/modules/NetworkStack` | LineageOS | captive portal 探测地址本地化 |
| `packages/providers/MediaProvider` | LineageOS | TranscodeHelper |
| `system/core` | LineageOS | RefBase |
| `vendor/lineage-priv/keys` | 私有仓库 | 签名密钥，**必须 private** |

`device/mediatek/sepolicy_vndr`、`hardware/xiaomi` 无改动，直接走上游。

`packages/modules/Connectivity`、`system/bpf` 曾经也是 fork（放 bpfloader 的容错补丁），
内核补齐 `bpf_attr` 与 `BPF_MAP_TYPE_DEVMAP_HASH` 之后 4.14 上已无 critical 对象加载失败，
那两个 fork 的改动成了死代码，已回退成上游并从 manifest 移除。

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
7. **内核 `#N` 不是 `#1`** → 走 `m bootimage` 时 `export KBUILD_BUILD_VERSION=1` **传不进内核 make**（soong → `kernel.mk` 那一层丢了），必须写 `out/target/product/cannon/obj/KERNEL_OBJ/.version`，而且初值要写 **0**（内核构建会自增 1 后输出）。
8. **`ro.build.date` 是旧日期** → 它取自 `out/build_date.txt`，且在 `sysprop.mk` 里是 order-only 依赖；**只删 `$OUT/system/build.prop` 没用**，真正缓存的是 `$OUT/obj/PACKAGING/system_build_prop_intermediates/buildinfo.prop`。

> 7、8 两条的完整根因和实测见 [cannon-lineageos-21-build](https://github.com/GTian5418/cannon-lineageos-21-build) 的 `docs/2026-10-28-内核四分支编译与版本号.md` 与 `docs/2026-10-29-ro.build.date沿用旧日期.md`。只换内核请改用 `Cannon_Docker_Kernel_Build` 出 AnyKernel3，别在源码树里连编 boot。

## TODO

- [x] **wifi HAL 被热点打死**（已修，framework 侧规避）
  MTK 的 `libwifi-hal.so` 多处不判空，`getHalInfo()` 拿到空句柄后直接解引用。
  已知两条触发路径，都已在 `packages/modules/Wifi` 里绕开：
  1. `IWifiChip.getFeatureSet()`：ap0 存在时 `getFirstActiveWlanIfaceName()` 返回 AP 接口，
     `wifi_get_supported_feature_set()` 解引用空句柄（fault addr 0x10）。
     修法：`WifiChipAidlImpl.getCapabilitiesInternal()` 用**进程级 static** 缓存，
     开机第一次 `getAllChipInfo()`（此时还没有任何接口）就把特性集存下来，之后不再问 HAL。
     必须是 static —— `HalDeviceManager.getAllChipInfo()` 每次都 `mWifiHal.getChip()`
     新建一个 `WifiChipAidlImpl`，实例字段的缓存活不过一次调用。
  2. `IWifiChip.getDebugHostWakeReasonStats()`：`dumpsys wifi` 会走这条，
     `wifi_get_driver_memory_dump()` 解引用空句柄（fault addr 0x0）。
     修法：`WifiVendorHal.getWlanWakeReasonCount()` 直接返回 null，不向 HAL 取
     （代价是 `dumpsys wifi` 里 `Wlan Wake Reasons` 那行变成 null）。
  **HAL 侧真修做不了**：vendor blob 闭源；树里的 `hardware/mediatek/wlan/wifi_hal`
  是阉割版（无 NAN，缺 `wifi_get_link_stats` / `wifi_set_link_stats` /
  `wifi_clear_link_stats` / `wifi_get_iface_handle` /
  `wifi_multi_sta_set_*` / `wifi_set_subsystem_restart_handler` 共 7 个 C API），
  换上去会丢功能，甚至直接起不来。

- [ ] **热点网段可配置**（后端已做，设置 UI 待做）
  现状：网段由 `packages/modules/Connectivity/Tethering` 的 `PrivateAddressCoordinator` 决定，
  从 `192.168.0.0/16` / `172.16.0.0/12` / `10.0.0.0/8` 里随机挑一个 /24，
  `SoftApConfiguration` 没有 IP 字段。
  - [x] **后端**：`requestStickyDownstreamAddress()` 对 `TETHERING_WIFI` 优先读系统属性
    `persist.sys.cannon.hotspot.subnet`（形如 `192.168.7.0/24`），过 `getConflictWithUpstream()`
    后返回固定网关（`.1`）；未设/非法/与上游冲突则回退随机。
    用法：`adb shell setprop persist.sys.cannon.hotspot.subnet 192.168.7.0/24`，**关再开热点生效**
    （地址运行时缓存）；留空 `setprop ... ""` 恢复随机。
  - [ ] **设置 UI**：`packages/apps/Settings` 的 `res/xml/wifi_tether_settings.xml` 加输入项 +
    `WifiTetherBasePreferenceController` 子类，写 `Settings.Global`，后端再改读 `Settings.Global`。

- [ ] **热点开启时 WiFi 扫描慢 4 倍**
  实测（同一台机器、同一个 r6、同一内核，热点先开再开 WiFi）：

  | 场景 | TRIGGER_SCAN → NEW_SCAN_RESULTS |
  |---|---|
  | 热点关 | 0.82 s |
  | 热点开（AP 2.4G ch6） | 4.00 s |
  | 热点开（AP 5G） | 3.63 s |

  与频段无关。framework 侧不是瓶颈（建 STA 接口 14ms、扫描结果到发起连接 38ms），
  时间全花在驱动扫描上。驱动没有暴露扫描/并发相关的 module_param
  （`gl_init.c` 只有 sta/p2p/ap 三个接口名参数，而且驱动编进内核，
  `/sys/module/wlan` 不存在），DBDC 已经是开的（`include/config.h:1234`），
  扫描时隙调度在闭源固件里。
  唯一低风险缓解：AP 活跃时裁剪扫描信道（2.4G 全扫 + 5G 仅 UNII-1 的 36/40/44/48），
  约能压到 2 秒，代价是热点开着时部分 5G 网络搜不到。**暂不处理。**
  注：Settings 的列表通常要两轮扫描才画全，所以用户感知约 8 秒。

- [x] **A15（LineageOS 22.2）适配**（已完成，用 `./build.sh a15`）
  `lineage_cannon-bp1a-user` 源码树已全量编出并发布。沿途漂移均已处理：
  VNDK 废弃、`TARGET_LD_SHIM_LIBS` 失效（改 patchelf 注入 NEEDED）、
  `ro.build.display.id` 落点从 `sysprop.mk` 迁到 `build/soong/scripts/gen_build_prop.py`。
