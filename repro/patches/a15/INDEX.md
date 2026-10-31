# A15 工作树补丁快照（自动导出）

> 由 `scripts/export_dirty_patches.sh` 于 2026-10-31 01:02:26 生成。
> 用途：防丢失的**当前工作树**文本快照。注意：这些是“已应用态”导出，apply 到干净树前需人工比对基线。
> 二进制改动（.apk/.so/.bin）不在补丁内容里，需由 repatch/patchelf 脚本再生。

| 仓库 | 补丁文件 | tracked 变更 | 新增源码文件 |
|---|---|---|---|
| `build/make` | build_make.patch | 1 file changed, 6 insertions(+) | — |
| `build/soong` | build_soong.patch | 3 files changed, 35 insertions(+), 14 deletions(-) |  scripts/__pycache__/ |
| `device/xiaomi/cannon` | device_xiaomi_cannon.patch | 8 files changed（`git diff ed2d505`＝基线→工作树：8 文件全量 + **实验B `WIFI_AVOID_IFACE_RESET_MAC_CHANGE := true`（BoardConfig.mk:201）**；2026-10-31 重导 14564B） | `libshims/src/CppVerboseAbort.cpp` |
| `frameworks/base` | frameworks_base.patch | 6 files changed, 65 insertions(+), 1 deletion(-) | — |
| `frameworks/native` | frameworks_native.patch | 1 file changed, 12 insertions(+), 2 deletions(-) | — |
| `frameworks/opt/telephony` | frameworks_opt_telephony.patch | 1 file changed, 19 insertions(+), 6 deletions(-) | — |
| `frameworks/opt/net/wifi` | frameworks_opt_net_wifi.patch | 1 file changed, 4 insertions(+)（**实验D**：`WifiPickerTracker.handleWifiStateChangedAction` 开WiFi时加 `conditionallyUpdateScanResults(true)` 复刻A13秒刷，MAX_SCAN_AGE仍15s；2026-10-31 手工导出 971B） | — |
| `hardware/mediatek` | hardware_mediatek.patch | 1 file changed, 7 insertions(+), 2 deletions(-) |  aidl/power-mediatek/android.hardware.power-service-mediatek.rc aidl/power-mediatek/service.cpp wlan/ |
| `hardware/mediatek/wlan` | hardware_mediatek_wlan.patch | 3 files changed, 8 insertions(+), 3 deletions(-) |  wpa_supplicant_8_lib/Android.bp |
| `hardware/lineage/compat` | hardware_lineage_compat.patch | 2 files changed, 16 insertions(+), 4 deletions(-) | — |
| `packages/apps/Jelly` | packages_apps_Jelly.patch | 1 file changed, 38 insertions(+) | — |
| `packages/apps/Settings` | packages_apps_Settings.patch | 5 files changed, 261 insertions(+)（**A15 热点自定义网段前端**：strings/wifi_tether_settings 改 + wifi_hotspot_custom_subnet.xml/WifiHotspotCustomSubnetSettings.java 新增 + WifiTetherSettings.java 改；**实验E MAX_SCAN_AGE 已回退不含**；2026-10-31 05:11 重生成 15216B） | res/xml/wifi_hotspot_custom_subnet.xml, src/com/android/settings/wifi/tether/WifiHotspotCustomSubnetSettings.java |
| `packages/apps/Trebuchet` | packages_apps_Trebuchet.patch | 3 files changed, 41 insertions(+), 2 deletions(-) | — |
| `packages/modules/Bluetooth` | packages_modules_Bluetooth.patch | 3 files changed, 31 insertions(+), 6 deletions(-) | — |
| `packages/modules/Connectivity` | packages_modules_Connectivity.patch | 4 files changed, 112 insertions(+), 6 deletions(-) | — |
| `packages/modules/NetworkStack` | packages_modules_NetworkStack.patch | 1 file changed, 5 insertions(+), 2 deletions(-) | — |
| `packages/modules/Wifi` | packages_modules_Wifi.patch | 2 files changed, 20 insertions(+), 38 deletions(-) | — |
| `packages/providers/MediaProvider` | packages_providers_MediaProvider.patch | 1 file changed, 14 insertions(+) | — |
| `system/core` | system_core.patch | 1 file changed, 16 insertions(+), 1 deletion(-) | — |
| `system/libhidl` | system_libhidl.patch | 1 file changed, 4 insertions(+), 1 deletion(-) | — |
| `vendor/lineage` | vendor_lineage.patch | 1 file changed, 6 insertions(+), 1 deletion(-) | — |
| `vendor/xiaomi/cannon` | vendor_xiaomi_cannon.patch | 32 files changed（`git diff 5973ac1`＝基线→工作树：32 文件全量 + **实验A 删 wifi-service-lazy 预编译覆盖行 + 实验C 删 libwifi-hal.so 预编译覆盖行**；2026-10-31 重导 19667B） | — |
| `kernel/xiaomi/cannon` | kernel_xiaomi_cannon.patch | 无 | — |
