# repro/patches/a17 —— A17(LOS 24.0 / android-17.0.0_r1) 构建期补丁

由 A16 补丁（`repro/patches/a16/`）在 A17 源码上逐条评估/重定位而来。共 **16 个补丁**，
`scripts/apply_a17_cannon_patches.sh` 幂等重放（已应用会自动跳过）。

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

## 四、5 自有仓（device/vendor/kernel/wlan/Wifi）基线已含
它们 A17 分支内容 == A16 tip，A16 补丁本就在分支里，故**不产 a17 patch**。
device 的 file_contexts 反向 check 差 1 hunk 是因分支比导出快照更新（多了 a16_preassemble 声明），非缺陷。
