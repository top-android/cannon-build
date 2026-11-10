# A17 补丁快照索引（自有仓双轨 + 上游仓单轨）

> 源码树 `/cannon/rom`（LineageOS 24.0 / Android 17 / `lineage-24.0`）。
> **2026-11-10 全部用 `git diff HEAD` 从当前工作树重新导出**（repo sync 后上游 HEAD 前移，
> 旧补丁的 `index`/行号已漂移）。规则改成**一个仓库一个补丁**，不再对同一仓库拆多个文件。
>
> 组成：**21 个 apply 补丁**（公有上游仓，build-time 打，不入库）
> + **6 个自有仓归档补丁**（已 commit 进 top-android fork，不 apply）
> + **1 个 webview LFS workaround**（记录用，不 apply）。
>
> 校验（全部通过）：`CANNON_DRY_RUN=1 bash scripts/apply_a17_cannon_patches.sh /cannon/rom`
> → 21 个全部「已应用，跳过」，`applied=0 skipped=21 drift=0 fail=0`。

## 一、公有上游仓（21，`scripts/apply_a17_cannon_patches.sh` 幂等重放）

| 补丁 | 大小 | 仓库 | 文件 | 变更摘要 |
|---|---|---|---|---|
| art.patch | 1020 | art | 1 | `tools/hiddenapi/hiddenapi.cc`：MTK 原厂 boot classpath 在多个 jar 里合法地重复同一个类（netdagent V1_0），A16 把重复类升级成 `LOG(FATAL)`；恢复 pre-A16 的宽容语义（只比 descriptor），与 A15/stock 一致 |
| build_make.patch | 7838 | build/make | 2 | `core/Makefile`：① recovery 根目录删 `d` 软链（指向宿主 `/sys/kernel/debug`，会破坏 zip）；② 支持 `BOARD_CANNON_VENDOR_PREASSEMBLE` 钩子；③ `CANNON_SKIP_VINTF_COMPAT` 时跳过 framework compatibility 检查。`core/soong_extra_config.mk`：新增 |
| build_soong.patch | 2853 | build/soong | 3 | `scripts/gen_build_prop.py`（display.id / ro.debuggable 段）、`scripts/check_boot_jars/package_allowed_list.txt`（放行 MTK boot jar）、`ci_tests/ci_test_package_zip.go`：OUT_DIR 在源码树外时 `installedFile` 是绝对路径，`TrimPrefix(productOut)` 裁不掉 → `validatePathInternal` 报 `Path is outside directory` |
| frameworks_base.patch | 11785 | frameworks/base | 8 | StorageManager / StorageManagerService（外置存储判定）、SecureLockDeviceRepository、DockObserver、SoundEffectsHelper、Notifier、AppOpService、SubscriptionManager |
| frameworks_native.patch | 1366 | frameworks/native | 1 | `libs/binder/ProcessState.cpp`：老 vendor HAL（A12 blob，如 `android.hardware.audio.service`）会在 `startThreadPool()` 后调 `setThreadPoolMaxThreadCount(0)`，AOSP 这里 `LOG_ALWAYS_FATAL` → HAL 每 5s abort 一次 → 降级为告警 |
| frameworks_opt_telephony.patch | 9955 | frameworks/opt/telephony | 2 | `RIL.java`、`ImsPhoneCallTracker.java`：开机重放 VoLTE 开关（`bootVolteReapply`，12s 延迟 / 6s 间隔 / 30s 重试），加快 IMS 注册 |
| hardware_lineage_compat.patch | 1198 | hardware/lineage/compat | 1 | `libbase/strings.cpp`：自包含 `Trim` 实现，不依赖某一版 libbase 的模板实例化符号（否则垫片自己加载不到） |
| hardware_nxp_secure_element.patch | 542 | hardware/nxp/secure_element | 1 | `frameworks/sems/Android.bp`：源码库改名 `com.nxp.sems.src.legacy`（`enabled:false`），避开与 vendor prebuilt `com.nxp.sems` 的同名跨分区冲突 |
| hardware_xiaomi.patch | 614 | hardware/xiaomi | 1 | `aidl/fingerprint/Android.bp`：加 `FingerprintJoin.cpp`，在模块内提供 `Join(vector<string>&, const char*)`——V13 原厂 libbase blob 没这个实例，避免跨 namespace 依赖 |
| packages_apps_Jelly.patch | 2981 | packages/apps/Jelly | 1 | `webview/WebClient.kt`：只允许白名单 scheme 留在 WebView 内加载 |
| packages_apps_Launcher3.patch | 4020 | packages/apps/Launcher3 | 3 | overview 常驻「清除全部」（`overview_actions_container.xml` + `OverviewActionsView` + `RecentsView`） |
| packages_apps_Settings.patch | 6294 | packages/apps/Settings | 3 | 热点自定义网段子菜单（strings / `wifi_tether_settings.xml` / `WifiTetherSettings.java`） |
| packages_modules_Bluetooth.patch | 5578 | packages/modules/Bluetooth | 3 | `A2dpService.java`：激活设备后重新 `handleBluetoothActiveDeviceChanged(device, null, …)`，让音频策略(重)注册 A2DP 输出（部分 vendor 栈丢首次通知 → 声音留扬声器）；`client_interface_aidl.cc`、`hci_layer.cc` |
| packages_modules_Connectivity.patch | 29423 | packages/modules/Connectivity | 12 | 4.14 非 GKI 的 BPF 全套降级：`NetBpfLoad.cpp`（map id 32/33 降级告警、复用分支不 abort、跳过重复 pin、sanitizeMapFlags 剥 RDONLY_PROG、跳过 test.o）、`BpfHandler.cpp`/`NetdUpdatable.cpp`/`ClatCoordinator.cpp`（失败不 abort）、`BpfUtils.h`、`netbpfload.rc`/`.35rc`（`wait_for_prop`→`setprop`、`reboot_on_failure` 注释）、`libeventpolling/*`、`LocalNetEventListener.java`。**注意该仓先被 `scripts/pin_a17_connectivity.sh` 固定到 `d468719` 再打补丁** |
| packages_modules_NetworkStack.patch | 1440 | packages/modules/NetworkStack | 1 | `res/values/config.xml`：captive portal 探测地址换成国内可达端点（`connect.rom.miui.com` / `connectivitycheck.gstatic.cn`） |
| packages_providers_MediaProvider.patch | 1572 | packages/providers/MediaProvider | 1 | `TranscodeHelperImpl.java`：`MediaCodecList::getInstance()` 的 binder 调用在 A12 vendor + A14+ system 上永不返回，跳过转码初始化 |
| system_bpf.patch | 4955 | system/bpf | 2 | `loader/Loader.cpp`：zero 哨兵检查失败由 `abort()` 改为跳过该 map 并记日志（4.14 改不了 .o）；`loader/bpfloader.rs`：critical 失败不 panic |
| system_core.patch | 1543 | system/core | 1 | `libutils/binder/RefBase.cpp`：A14 起 `incStrongRequireStrong` 对无强引用的对象 abort；A12 老 vendor blob（MTK camera HAL）会用 `sp<T>::fromExisting()` 收养刚构造的对象 → 容忍这一种情况 |
| system_netd.patch | 5467 | system/netd | 2 | `server/BandwidthController.cpp` + `server/netd.rc`：4.14 上没有可用的 xt_bpf pinned 程序，bpfloader SIGABRT → netd 侧降级、netd1shot 的 `reboot_on_failure` 注释掉 |
| system_sepolicy.patch | 3236 | system/sepolicy | 4 | `private/{bpfloader,crash_dump}.te` + `prebuilts/api/202604/private/` 同名两份：userdebug 放行 crash_dump ptrace bpfloader（拿 tombstone） |
| vendor_lineage.patch | 2337 | vendor/lineage | 2 | 内核头 sbox 链：`build/soong/Android.bp` 的 `generated_kernel_includes.dep_files` 补 `scripts/**/*` + `arch/$(KERNEL_ARCH)/Makefile`；`tools/clean_headers.sh` 在 sbox（无 bionic）里找不到 `clean_header.py` 时优雅跳过 |

## 二、自有仓（6，已 commit 进 top-android fork，patch 仅作归档）

> 干净 checkout 即当前态（`local_manifests/cannon-a17.xml` 的 revision），
> 所以**不登记到 MAP**，只留 patch 便于离线复现/移植。

| 补丁 | 大小 | 仓库 | 文件 | 说明 |
|---|---|---|---|---|
| device_xiaomi_cannon.patch | 1573 | device/xiaomi/cannon | 2 | 旧快照（ION legacy + libion sepolicy），**已过时**，仅历史记录 |
| vendor_xiaomi_cannon.patch | 1296 | vendor/xiaomi/cannon | 1 | 旧快照（删 `cas@1.2-service-lazy` copy），**已过时** |
| kernel_xiaomi_cannon.patch | 4164 | kernel/xiaomi/cannon | 2 | 旧快照（`uapi/linux/bpf.h` + `net/core/filter.c` 的 4.14 BPF 适配），**已过时** |
| hardware_mediatek.patch | 19123 | hardware/mediatek | 11 | 停用撞名 java_library + PowerOffAlarm 去 kernel 头 + AIDL power HAL（已 commit `5ebbf02`） |
| hardware_mediatek_wlan.patch | 717 | hardware/mediatek/wlan | 1 | BITS 掩码修正 |
| packages_modules_Wifi.patch | 6119 | packages/modules/Wifi | 2 | 老 vendor `getFeatureSet`/`getWakeReason` 空指针旁路 |

## 三、不参与 apply 的记录

| 文件 | 大小 | 说明 |
|---|---|---|
| external_chromium-webview_prebuilt_x86_64.patch | 819 | 删 `.gitattributes`/`.lfsconfig`/`webview.apk`（LFS 指针）的本地 workaround。应用后 repo 的 LFS 钩子会把 `.gitattributes`/`.lfsconfig` 又生成成 untracked，**不可靠**，故只作记录、不登记 |

## 四、相对上一版（2026-11-04 快照）的差异

- **全部重生成**：上游 HEAD 前移，21 个补丁的 `index` 行与 hunk 行号都变了（`build_make` 6769→7838B、`system_netd` 457→5467B、`packages_apps_Settings` 15156→6294B 等）。
- **新增**：`system_bpf.patch`、`system_sepolicy.patch`、`vendor_lineage.patch`（合并原两个 sbox 补丁）、`packages_modules_Connectivity.patch`（合并原 `_loader` 版，覆盖 12 文件）、`hardware_xiaomi.patch`（原 `hardware_xiaomi_fingerprint_join.patch` 改名）。
- **移除**：`frameworks_opt_net_wifi.patch`、`system_libhidl.patch`——上游已吸收，工作树无 diff（这两个文件本来就不存在）。
- **归档到 `_obsolete/`**：`packages_modules_Connectivity_loader.patch`、`vendor_lineage_clean_headers_sbox.patch`、`vendor_lineage_kernel_headers_sbox.patch`、`vendor_lineage_kernel_o_abspath.patch`、`hardware_xiaomi_fingerprint_join.patch`。
- **`vendor_lineage_kernel_o_abspath.patch` 不再需要**：它只解决「`OUT_DIR` 用自定义名（如 `out-a17`）时 `O=` 是相对路径、sbox 内头被丢弃」。当前构建固定 `OUT_DIR=out`，工作树里 `build/tasks/kernel.mk` 已无该改动。若以后改回自定义 OUT_DIR，需要重新评估这一坑。

## 回验方法

```bash
# 1) 全部补丁与当前树是否一致（应全部「已应用，跳过」，drift=0）
CANNON_DRY_RUN=1 bash /cannon/cannon-build/scripts/apply_a17_cannon_patches.sh /cannon/rom

# 2) 单个补丁
git -C /cannon/rom/<repo> apply --reverse --check /cannon/cannon-build/repro/patches/a17/<patch>

# 3) 重新导出（改完源码后）
git -C /cannon/rom/<repo> diff HEAD > /cannon/cannon-build/repro/patches/a17/<patch>
```
