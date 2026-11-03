# repro/patches/a17 —— A17(LOS 24.0 / android-17.0.0_r1) 构建期补丁

由 A16 补丁（`repro/patches/a16/`）在 A17 源码上逐条评估/重定位而来，并叠加 A17 阶段新增补丁。
**当前共 22 个补丁**（截至 2026-11-03，以本目录实际 `.patch` 为准，见下分类），
`scripts/apply_a17_cannon_patches.sh` 幂等重放（已应用会自动跳过）。A17 阶段新增的主要是：
`device_xiaomi_cannon`（mediatek 移出 PRODUCT_BOOT_JARS）、`hardware_nxp_secure_element`、
`packages_modules_Wifi`，以及 **[五]** 节 3 个 `vendor_lineage_*` 内核头 sbox 链补丁。

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

## 四、5 自有仓（device/vendor/kernel/wlan/Wifi）
- 多数情况 A17 分支内容 == A16 tip，A16 补丁本就在分支里，故**不产 a17 patch**。
- **例外（A17 新改，产补丁）**：
  - `device_xiaomi_cannon.patch`：A17 把 8 个 mediatek vendor jar 移出 `PRODUCT_BOOT_JARS`（治 dex2oat boot image 校验因 `final`/删除类而硬失败；仍装 /system/framework）。
  - `packages_modules_Wifi.patch`、`hardware_nxp_secure_element.patch`：见各自补丁头注释。
- device 的 file_contexts 反向 check 差 1 hunk 是因分支比导出快照更新（多了 a16_preassemble 声明），非缺陷。

## 五、A17 4.14 非GKI 内核头 sbox 链（3 补丁，全部 vendor/lineage）—— 坑王链，全新编译必打

> 背景：本机内核 4.14 非 GKI（`TARGET_KERNEL_PLATFORM_TARGET` 空）。A17 的 `generated_kernel_includes`
> （`vendor/lineage/build/soong/Android.bp` 的 `lineage_generator`）走 `make headers_install` 分支，
> 且该 rule 用 `.Sbox()` 沙箱（**真 chroot，只拷 dep_files+tool_files，无 bionic**）执行。由此有**三连环坑**，
> 缺任一全新编译编到 ~31% 都必失败（`FAILED: .../generated_kernel_includes/gen/.dummy_dep`）：

| 补丁 | 症状 | 修复 |
|---|---|---|
| `vendor_lineage_kernel_headers_sbox.patch` | sbox 内 `make` 报 `scripts/Makefile.ubsan: No such file` exit 127 | Android.bp `generated_kernel_includes.dep_files` 补 `scripts/**/*` + `arch/$(KERNEL_ARCH)/Makefile` |
| `vendor_lineage_clean_headers_sbox.patch` | 收尾 `clean_headers.sh` 调 `./bionic/.../clean_header.py` 报 127（sbox 无 bionic/） | 脚本找不到 clean_header.py 就优雅 `exit 0` 跳过 |
| `vendor_lineage_boardkernel_out_prefix.patch` | `.dummy_dep` 成功但真实 `gen/usr/include` **为空** → 500+ `-nostdlibinc` 消费者全崩 | `BoardConfigKernel.mk` 的 `KERNEL_BUILD_OUT_PREFIX` 改**无条件 `$(BUILD_TOP)/`**（stock `out` 不变；`out-a17` 等任意名均安全）|

- **第三坑为何关键**：`OUT_DIR=out-a17`（siso 要求相对 OUT_DIR）≠ `out` → 原逻辑 `KERNEL_BUILD_OUT_PREFIX` 为空 → `O=` 相对 → sbox 内 `make -C kernel` 把头装进**嵌套沙箱路径被丢弃**。前两补丁只让 make 跑通，第三个才让头落到真实 `gen/`。
- **持久性**：第三补丁是正解；**不要**再靠"临时改 `out-a17/.../generator.sbox.textproto` 的 `O=` 为绝对"（下次 soong 重分析会重生成 manifest 覆盖它）。
- **编译前自检**：`bash /cannon/scripts/preflight_a17_patches.sh`（查本表三补丁 + OUT_DIR 相对是否就位，不 PASS 阻止开编）；结果核验：`bash /cannon/scripts/verify_a17_result.sh`。
- **与 OUT_DIR 关系（别误判）**：只有第三坑与"自定义 OUT_DIR 名"有关；第一、二坑是 sbox 缺文件，**用默认 `out` 也会撞**。故**不要**为躲坑改回树内 `out` 或软链 `out`→`out-a17`（siso 对符号链接路径解析有风险）。
