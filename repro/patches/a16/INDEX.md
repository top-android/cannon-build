# A16 补丁快照索引（自有仓双轨 + AOSP 上游仓单轨）

> 源码树 `/cannon/rom-a16`（LineageOS 23.2 / lineage-23.2-cannon / bp4a）。
> **两种来源，处置不同**（见 `docs/DECISIONS.md` D7）：

## 一、自有仓（top-android 组织内）——**双轨：commit 入库 + 含二进制 patch**

> 这类仓由我们自有，改动**直接 commit 进仓**（本地分支 `lineage-23.2-cannon`，未 push），
> 干净 checkout 即当前态；**同时**导出 `git diff --binary`（含 `.so` 二进制内容）的完整 patch，
> 可 apply 到别处/给别人。
> **[2026-11-03 重整]** 发现 device 仓两处存档各存了**不同提交**的快照、互相缺失
> （build 仓存 `8ad0eb3`=最旧；log 仓存 `b440ee0`+`36af3c7`），且 sepolicy `36af3c7`
> 单补丁从未登记进 `apply_a16` 的 MAP（从未重放）。现改为**累计补丁**：
> `device_xiaomi_cannon.patch = git diff --binary 1627c00 36af3c7`（A15 基线 1627c00 → A16 HEAD 36af3c7），
> 单文件即涵盖全部 A16 device 改动，两仓逐字节一致。回验：干净 `1627c00` + 本 patch == `36af3c7` 工作树。
> commit 链：`1627c00`(A15设备树) → `8ad0eb3`(device修复入库) → `b440ee0`(vendor一步装配staging预注入) → `36af3c7`(sepolicy补回stash误清, HEAD)。

| 仓库 | commit | 补丁文件 | 大小 | 变更摘要 |
|---|---|---|---|---|
| `device/xiaomi/cannon` | `1627c00..36af3c7`（累计） | device_xiaomi_cannon.patch | 47KB | 17 files, +616/−12（含 `libshims/src/netutils_dep_stub.c`、`sepolicy/private/cannon_finalize.te`、`cannon_a16_residual.te`、`tools/a16_assemble_vendor.sh`、`a16_preassemble_vendor.sh`、`device.mk`、`configs/vintf/manifest.xml`、`rootdir/*`、`sepolicy/vendor/{vendor_init,hal_fingerprint_default}.te`、`file_contexts`）|
| `vendor/xiaomi/cannon` | `c6dafbc` | vendor_xiaomi_cannon.patch | 103KB | 5 files，4 个 `.so` **含二进制内容**（libhidlbase×2/libutils/libexpat） |
| `hardware/mediatek/wlan` | `b042dac` | hardware_mediatek_wlan.patch | 63KB | 11 files, +1246/−3（全新 libwifi-hal-wrapper/wlan_assistant 源码模块） |
| `packages/modules/Wifi` | `4eb8d97` | packages_modules_Wifi.patch | 6KB | 2 files, +28/−39（老 vendor getFeatureSet/getWakeReason 空指针旁路） |
| `kernel/xiaomi/cannon` | `d94c2e36e` | kernel_xiaomi_cannon.patch | 5KB | 6 files（fs/file.c fs/open.c fs.h syscalls.h unistd.h close_range.h）；close_range(2)+CLOSE_RANGE_CLOEXEC 回填 |

## 二、AOSP 上游仓——**单轨：上游 + build-time apply patch（不 commit 入库）**

> 非自有仓，走上游 fork + 编译期打补丁。以下为 **2026-11-01 19:50 工作树文本快照**（"已应用态"），
> apply 到干净树前需人工比对基线；二进制改动（.apk/.so/.bin）不在文本补丁里，需 repatch/patchelf 再生。

| 仓库 | 补丁文件 | tracked 变更 | 新增源码文件 |
|---|---|---|---|
| `art` | art.patch | 1 file, +5/−4 | — |
| `build/make` | build_make.patch | 1 file, +28（含 OTA vendor 复用白名单镜像 + `__DATA` map 修复，2026-11-02 刷新） | — |
| `build/soong` | build_soong.patch | 3 files, +12/−13 | — |
| `frameworks/base` | frameworks_base.patch | 8 files, +92/−11 | — |
| `frameworks/native` | frameworks_native.patch | 1 file, +12/−2 | — |
| `frameworks/opt/telephony` | frameworks_opt_telephony.patch | 2 files, +95/−6 | — |
| `hardware/mediatek` | hardware_mediatek.patch | 4 files, +33/−35 | aidl/power-mediatek/*.bp/.cpp/.h/.rc/.xml |
| `hardware/lineage/compat` | hardware_lineage_compat.patch | 1 file, +10/−2 | — |
| `packages/apps/Jelly` | packages_apps_Jelly.patch | 1 file, +38 | — |
| `packages/modules/Bluetooth` | packages_modules_Bluetooth.patch | 3 files, +31/−6 | — |
| `packages/modules/Connectivity` | packages_modules_Connectivity.patch | 8 files, +136/−15 | — |
| `packages/modules/NetworkStack` | packages_modules_NetworkStack.patch | 1 file, +5/−2 | — |
| `packages/providers/MediaProvider` | packages_providers_MediaProvider.patch | 1 file, +14 | — |
| `system/core` | system_core.patch | 1 file, +16/−1 | — |
| `system/libhidl` | system_libhidl.patch | 1 file, +4/−1 | — |
| `vendor/lineage` | vendor_lineage.patch | 1 file, +1/−1 | — |

> 注：`frameworks/opt/net/wifi`、`packages/apps/Launcher3`、`packages/apps/Settings` 为 05:22 更早快照，未在 19:50 批次更新，按需重导。
