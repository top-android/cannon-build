# repro/patches/a17 —— A17(LOS 24.0 / android-17.0.0_r1) 构建期补丁

> **2026-11-10 重新导出**：本目录所有补丁已按当前 `/cannon/rom` 工作树用 `git diff HEAD`
> 重生成（上游 HEAD 前移导致旧补丁 index/行号漂移），并改成一个仓库一个补丁。
> **逐补丁清单以 `INDEX.md` 为准**；本文件保留历史背景与坑位说明。
> 现状：21 个 apply 补丁（公有上游仓）+ 6 个自有仓归档补丁 + 1 个 webview LFS 记录。

由 A16 补丁（`repro/patches/a16/`）在 A17 源码上逐条评估/重定位而来，并叠加 A17 阶段新增补丁。
`scripts/apply_a17_cannon_patches.sh` 幂等重放（已应用会自动跳过）。A17 阶段新增的主要是：
`system_bpf` / `system_sepolicy`（4.14 bpfloader 降级 + userdebug 放行 ptrace）、
`packages_modules_Connectivity`（BPF 全套降级）、
`hardware_nxp_secure_element`、`hardware_xiaomi`，以及 **[五]** 节的 `vendor_lineage` 内核头 sbox 链。
自有仓（device / vendor / kernel / hardware-mediatek / hardware-mediatek_wlan / packages-modules-Wifi）
的改动已 commit 进 top-android fork，patch 只作归档、不参与 apply。


## 一、直接复用（11，A16 原样在 A17 可打）
art, frameworks_base, frameworks_native, hardware_lineage_compat, hardware_mediatek,
packages_apps_Jelly, packages_apps_Settings, packages_modules_Bluetooth,
packages_modules_NetworkStack, packages_providers_MediaProvider, system_core

## 二、重定位后生成（5，A16 hunk 漂移已按 A17 结构改写）
| 补丁 | A16 失败点 | A17 处理 |
|---|---|---|
| build_make | core/Makefile(VINTF 段) | A17 去掉 PRODUCT_ENFORCE_VINTF_MANIFEST 外层，CANNON_SKIP_VINTF_COMPAT 包裹改到 check_vintf_has_system 外层 + OTA vintf_enforce 条件化 |
| build_soong | scripts/gen_build_prop.py | A17 多了 build.uuid 行，display.id 段按 A17 重写为 BuildFlavor |
| frameworks_opt_telephony | ImsPhoneCallTracker 字段段 | 字段插入点按 A17 重定位 |
| packages_apps_Launcher3 | RecentsView.dismissAllTasks | 仅行号大偏移，改 public |
| packages_modules_Connectivity | NetBpfLoad/BpfHandler/NetdUpdatable | BpfHandler 用 Error()<< 改为 ALOGW，其余按 A17 重定位 |

## 三、上游已吸收 → 无需补丁（3）
- frameworks_opt_net_wifi：A17 `initializeState()` 原生调用 `conditionallyUpdateScanResults(true,true)`
- system_libhidl：A17 已删除 getRawServiceInternal 内调试 `sleep(1)`
- vendor_lineage：A17 已整段删除 arm gcc kernel toolchain（仅 clang）

## 四、6 自有仓（device/vendor/kernel/hardware-mediatek/hardware-mediatek-wlan/packages-modules-Wifi）

> 2026-11-10 起 `hardware/mediatek` 也是自有 fork（`top-android/android_hardware_mediatek`，
> 见 `local_manifests/cannon-a17.xml`），改动 commit 进仓，patch 只归档、不 apply。
> 本节下面的「例外」描述是这些补丁当初的由来，内容可能已随分支前进而过时——以 `INDEX.md` 和实际补丁为准。
- 多数情况 A17 分支内容 == A16 tip，A16 补丁本就在分支里，故**不产 a17 patch**。
- **例外（A17 新改，产补丁）**：
  - `device_xiaomi_cannon.patch`：① A17 把 8 个 mediatek vendor jar 移出 `PRODUCT_BOOT_JARS`（治 dex2oat boot image 校验因 `final`/删除类而硬失败；仍装 /system/framework）；② `BoardConfig.mk` 定义 `KERNEL_CROSS_COMPILE := CROSS_COMPILE=aarch64-linux-gnu-`（本 Lineage 树 kernel.mk 引用该变量但未定义，空值使 clang 无 `--target`，vDSO 退化 host x86_64 报 `-ffixed-x18 unsupported`；必须用 gnu 三元组，android 三元组会触发 `clang-android.sh` 的 `__ANDROID__` 报错）；③ `device.mk` 用官方产品变量 `$(call add-product-dex-preopt-module-config, <13个模块>, disable)` 把 13 个 vendor `dex_import`（mediatek-* 11 + `com.nxp.sems` + `hotword`）置入 `DEXPREOPT_DISABLED_MODULES`（→ `DisablePreoptModules` → `build/soong/dexpreopt/dexpreopt.go:122` 按模块名跳 dex2oat）。**这是关 vendor blob dexpreopt 的正解**：`dex_import` 模块类型不支持 `dex_preopt` 属性（blueprint 报 `unrecognized property "dex_preopt.enabled"`），故只能走产品变量。dumpvar 已验证 13 模块名全部进 `DEXPREOPT_DISABLED_MODULES`。
  - `kernel_xiaomi_cannon.patch`：4.14 非 GKI 内核在 clang-21/Android17 工具链下的 5 处漂移修复——`cannon_defconfig` 关 `CONFIG_COMPAT_VDSO`（无 32 位工具链）、`scripts/extract-cert.c` 对 BoringSSL 桩掉 PKCS#11 ENGINE、`asm/spinlock.h` `"I"→"i"`(65536 超 12 位)、`asm/stack_pointer.h` 全局寄存器变量改语句表达式宏、顶层 `Makefile` 加 `-Wno-default-const-init-var-unsafe`。
  - `hardware_mediatek_wlan.patch`：`mediatek_driver_cmd_nl80211.c` BITS 掩码修正。
  - `vendor_xiaomi_cannon.patch`（`c6dafbc`→`224fff4`）：删 `cannon-vendor.mk` 里 `android.hardware.cas@1.2-service-lazy` 预编译 copy 行。A17 make 的 PRODUCT_COPY_FILES 去重会把同名 soong 模块拉入安装集，连带装其 `lazy.rc/lazy.xml`；与 device.mk 装的基模块 `cas@1.2-service` 的 `service.xml` 同声明 `@1.2::IMediaCasService/default` → `check_vintf_vendor` 报 `Conflicting FqInstance` 硬失败（第3轮m EXIT 1 @86%）。删后仅剩基模块单一 manifest（同 A16-D13 去 -lazy 思路）。
  - `packages_modules_Wifi.patch`、`hardware_nxp_secure_element.patch`：见各自补丁头注释。
- device 的 file_contexts 反向 check 差 1 hunk 是因分支比导出快照更新（多了 a16_preassemble 声明），非缺陷。

## 五、A17 4.14 非GKI 内核头 sbox 链（`vendor_lineage.patch` 一个补丁覆盖前两坑）—— 坑王链，全新编译必打

> 背景：本机内核 4.14 非 GKI（`TARGET_KERNEL_PLATFORM_TARGET` 空）。A17 的 `generated_kernel_includes`
> （`vendor/lineage/build/soong/Android.bp` 的 `lineage_generator`）走 `make headers_install` 分支，
> 且该 rule 用 `.Sbox()` 沙箱（**真 chroot，只拷 dep_files+tool_files，无 bionic**）执行。由此有**三连环坑**，
> 缺任一全新编译编到 ~31% 都必失败（`FAILED: .../generated_kernel_includes/gen/.dummy_dep`）：

| 坑 | 症状 | 修复（现落在 `vendor_lineage.patch`） |
|---|---|---|
| ① dep_files 不全 | sbox 内 `make` 报 `scripts/Makefile.ubsan: No such file` exit 127 | Android.bp `generated_kernel_includes.dep_files` 补 `scripts/**/*` + `arch/$(KERNEL_ARCH)/Makefile` |
| ② clean_headers.sh | 收尾 `clean_headers.sh` 调 `./bionic/.../clean_header.py` 报 127（sbox 无 bionic/） | 脚本找不到 clean_header.py 就优雅 `exit 0` 跳过 |
| ③ `O=` 相对路径 | `.dummy_dep` 成功但真实 `gen/usr/include` **为空** → 500+ `-nostdlibinc` 消费者全崩 | 曾用 `vendor_lineage_kernel_o_abspath.patch` 改 `build/tasks/kernel.mk`。**2026-11-10 起不再需要**：构建固定 `OUT_DIR=out`，`KERNEL_BUILD_OUT_PREFIX` 为空也不会走嵌套沙箱路径；补丁已归档 `_obsolete/`。改回自定义 OUT_DIR（`out-a17` 等）时必须重新评估这一坑 |

- **第三坑为何关键**：`OUT_DIR=out-a17`（siso 要求相对 OUT_DIR）≠ `out` → 原逻辑 `KERNEL_BUILD_OUT_PREFIX` 为空 → `O=` 相对 → sbox 内 `make -C kernel` 把头装进**嵌套沙箱路径被丢弃**。前两补丁只让 make 跑通，第三个才让头落到真实 `gen/`。
- **为何改 kernel.mk 而非 BoardConfigKernel.mk（18万步教训）**：改 `config/BoardConfigKernel.mk` 的 `KERNEL_BUILD_OUT_PREFIX` 为无条件绝对虽也能修（且 stock `out` 不受影响），但它是**全局生成规则**，一动会把整片原生子图判脏、重编十余万步（曾白烧 ~18万步 ≈5h）。而 `build/tasks/kernel.mk` 只影响内核相关 edge → 外科手术式修复，不重脏原生图。**当前固定 `out`，两处都不需要改**；`BoardConfigKernel.mk` 无条件化作为"干净树从零编 + 自定义 OUT_DIR"时可选根治（`[待做]`，须在开编前、非增量期落地）。

- **持久性**：改 kernel.mk 是源码级正解——soong 每次重分析都从该规则重新生成 manifest，`O=` 恒为绝对，**不会**被覆盖；**不要**再靠"临时改 `out-a17/.../generator.sbox.textproto` 的 `O=`"（那是下次重分析即失效的临时兜底）。
- **编译前自检**：`bash /cannon/scripts/preflight_a17_patches.sh`（查本表三补丁 + OUT_DIR 相对是否就位，不 PASS 阻止开编）；结果核验：`bash /cannon/scripts/verify_a17_result.sh`。
- **与 OUT_DIR 关系（别误判）**：只有第三坑与"自定义 OUT_DIR 名"有关；第一、二坑是 sbox 缺文件，**用默认 `out` 也会撞**。故**不要**为躲坑改回树内 `out` 或软链 `out`→`out-a17`（siso 对符号链接路径解析有风险）。
