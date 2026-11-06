# A17 补丁快照索引（自有仓双轨 + AOSP 上游仓单轨）

> 源码树 `/cannon/rom-a17`（LineageOS 24.0 / Android 17 / `lineage-24.0-cannon` / bp1a）。
> 详细背景与分类说明见同目录 `README.md`。本文件只做**逐补丁清单**（文件名 / 大小 / 目标 / 基线 / 来源）。
> 截至 2026-11-04，共 **25** 个 `.patch`。`scripts/apply_a17_cannon_patches.sh` 幂等重放（缺省按文件名顺序）。

## 一、自有仓（top-android 组织内）——**双轨：本地 commit 入库 + 含二进制 patch**

> 改动**直接 commit 进仓**（本地分支 `lineage-24.0-cannon`，**未 push**），干净 checkout 即当前态；
> **同时**导出 `git diff --binary <baseline> <HEAD>` 的完整 patch（含 `.so` 等二进制）。回验：干净 `<baseline>` + 本 patch == 当前工作树。

| 补丁 | 大小 | 仓库 | 基线 → HEAD | 变更摘要 |
|---|---|---|---|---|
| device_xiaomi_cannon.patch | 1208 | device/xiaomi/cannon | 当前 HEAD | 2 files：`device.mk` 加 `$(call soong_config_set_bool,libion,legacy_impl,true)`（MT6853 只有 legacy ION，否则 libdmabufheap 无 `/dev/ion` 回退 → gralloc 分配全失败）+ `BoardConfig.mk` 加 `include device/lineage/sepolicy/libion/sepolicy.mk`（放行 `hal_graphics_allocator` 访问 `ion_device`）。**2026-11-06 重新生成**，此前那版（KERNEL_CROSS_COMPILE/dexpreopt）已进入基线，归档到 `_obsolete/` |
| kernel_xiaomi_cannon.patch | 3924 | kernel/xiaomi/cannon | `215867a3d` → `cf7bd8d54` | 5 files：`cannon_defconfig`(关 COMPAT_VDSO)、`scripts/extract-cert.c`(BoringSSL 桩)、`asm/spinlock.h`(I→i)、`asm/stack_pointer.h`(sp 宏)、`Makefile`(-Wno-default-const-init-var-unsafe) |
| hardware_mediatek_wlan.patch | 717 | hardware/mediatek/wlan | `b042dac` → `3a37b5b` | 1 file：`mediatek_driver_cmd_nl80211.c` BITS 掩码修正 |

| vendor_xiaomi_cannon.patch | 1296 | vendor/xiaomi/cannon | `c6dafbc` → `224fff4` | 1 file `cannon-vendor.mk`：删 cas@1.2-service-lazy 预编译 copy。A17 make 的 PRODUCT_COPY_FILES 去重会把同名 soong 模块 `android.hardware.cas@1.2-service-lazy` 拉入安装集，连带装其 `lazy.rc/lazy.xml`，与 device.mk 装的基模块 `cas@1.2-service` 的 `service.xml` 同声明 `@1.2::IMediaCasService/default` → `check_vintf_vendor` 报 `Conflicting FqInstance`。删除该 copy 行后仅剩基模块单一 manifest（同 A16-D13 去 -lazy 思路）|
| packages_modules_Wifi.patch | 6119 | packages/modules/Wifi | 见补丁头 | 老 vendor getFeatureSet/getWakeReason 空指针旁路 |

> 注：`vendor/xiaomi/cannon` 仓此前 A17 期无净改动（曾试 `dex_import` 加 `dex_preopt` 属性属非法已撤销，正确 dexpreopt 关闭改在 device.mk 产品变量）；本轮新增 cas lazy copy 删除，故恢复 vendor 补丁（`c6dafbc`→`224fff4`）。

## 二、AOSP 上游仓——**单轨：上游 + build-time apply patch（不 commit 入库）**

### 2.1 直接复用（A16 原样可打，11）
art(1020), frameworks_base(11785), frameworks_native(1366), hardware_lineage_compat(1198),
hardware_mediatek(19123), packages_apps_Jelly(2981), packages_apps_Settings(15156),
packages_modules_Bluetooth(5578), packages_modules_NetworkStack(1440),
packages_providers_MediaProvider(1572), system_core(1543)

### 2.2 重定位后生成（A16 hunk 漂移按 A17 改写，5）
build_make(5594), build_soong(2853), frameworks_opt_telephony(9955),
packages_apps_Launcher3(4020)

> **packages_modules_Connectivity.patch 已停用**（归档于 `_obsolete/`）。
> 4.14 的 BPF 兼容层改由 `scripts/pin_a17_connectivity.sh` 把该仓固定到
> cansong 组件集成提交 `d468719`（`build.sh apply` 的 a17 分支会自动调用）。

### 2.3 其它（1）
hardware_nxp_secure_element(542)

## 三、A17 4.14 非 GKI 内核头 sbox 链（3，全部 vendor/lineage，坑王链，全新编译必打）

| 补丁 | 大小 | 目标文件 | 修复 |
|---|---|---|---|
| vendor_lineage_kernel_headers_sbox.patch | 902 | `build/soong/Android.bp` | `generated_kernel_includes.dep_files` 补 `scripts/**/*` + `arch/$(KERNEL_ARCH)/Makefile`（sbox 内 make 找不到 Makefile.* 报 127）|
| vendor_lineage_clean_headers_sbox.patch | 1435 | `tools/clean_headers.sh` | sbox(chroot 无 bionic) 找不到 clean_header.py 时优雅跳过（否则 127）|
| vendor_lineage_kernel_o_abspath.patch | 2297 | `build/tasks/kernel.mk` | 三处 `O=$(abspath ...)` 强制绝对（否则 `out-a17`≠`out` 时 O= 相对、sbox 内头被丢弃）；**手术式，不重脏原生图**（勿改 BoardConfigKernel.mk 全局，见 18万步教训）|

## 回验方法（任一自有仓）
```bash
git -C /cannon/rom-a17/<repo> stash -u            # 暂存（若有）
git -C /cannon/rom-a17/<repo> checkout <baseline>
git -C /cannon/rom-a17/<repo> apply /cannon/repro/patches/a17/<patch>
diff -rq <...>                                     # 应与当前工作树一致
```
