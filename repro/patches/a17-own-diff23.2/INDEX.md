# a17-own-diff23.2 —— top-android 自有仓 A17 累计补丁（diff 基线 = lineage-23.2-cannon）

固化日期：2026-11-08（VoLTE/IMS 收官轮）
用途：把 5 个 top-android 自有仓中 4 个的 A17 全部改动，以「23.2 基线 → 当前 HEAD」累计 unified diff 形式留档。
这些补丁是**文档快照**，不是 apply_a17_cannon_patches.sh 的输入——自有仓的改动都在
lineage-24.0-cannon 分支 commit 里（repo sync 即得），无需重放。

| 补丁 | 仓 | 基线 (23.2) | HEAD | 规模 |
|---|---|---|---|---|
| device_xiaomi_cannon.patch | device/xiaomi/cannon | 36af3c7 | f353d60 | 29 files +12446 |
| vendor_xiaomi_cannon.patch | vendor/xiaomi/cannon | c6dafbc | 224fff4 | 1 file -1（删 cas@1.2-service-lazy copy） |
| hardware_mediatek_wlan.patch | hardware/mediatek/wlan | b042dac | b759d4c | 1 file +10（wpa setCountry 空指针防护） |
| packages_modules_Wifi.patch | packages/modules/Wifi | 4eb8d97 | 385594e | 638 files +77k（**含上游 LOS 23.2→24.0 版本差异**，fork 基线不同代） |

- `kernel/xiaomi/cannon` **有意排除**：cannon_defconfig（BOOTPARAM_HUNG_TASK_PANIC→n）保持工作区不提交，
  开机卡死调试仍在进行；待调试结束后再 commit 并补导出。
- HEAD 各仓 md5/提交号以 GitHub top-android 对应分支为准（均已 push：device f353d60 / wlan b759d4c）。
- 再生命令（在 /cannon/rom 树）：
  `git -C <repo> fetch devs lineage-23.2-cannon && git -C <repo> diff devs/lineage-23.2-cannon..HEAD > <patch>`
- 同一套补丁另存于 log 仓 `/cannon/patches/diff23.2-a17/`（双线固化）。
