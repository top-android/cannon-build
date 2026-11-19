# cannon A17：HIDL→AIDL 迁移清单 + 测试方法 + 快照恢复后复现步骤

> 生成时间：2026-11-20
> 对应源码状态：`cannon-build` commit `fbae55b`，清单 `manifests/a17-pinned-2026-11-20.xml`
> 本文件同时存放在 `/root/cannon-a17-hidl2aidl.md`（系统盘，快照回滚不影响）
> 和 `cannon-build/docs/A17-HIDL2AIDL.md`（已推 GitHub）。

---

## 二、A16/A17 的 HIDL→AIDL 名单

A17 树里 **HIDL 接口已被整个删掉**（`hardware/interfaces` 下只剩 `aidl/`）的包：

`ir`、`light`、`vibrator`、`memtrack`、`dumpstate`、`identity`、`macsec`、
`motioncontext`、`npu`、`rebootescrow`、`threadnetwork`、`uwb`

> graphics 系列（allocator 4.0 / mapper 4.0 / composer 2.1~2.4）HIDL 定义都还在，没被删。

本机（cannon / MT6853T）命中情况：

| HAL | 本机原来 | 现在 | 状态 |
|---|---|---|---|
| **ir** | vendor 声明 `ir@1.0::IConsumerIr` | `android.hardware.ir-service.lineage`（AIDL） | 已修。A17 无 HIDL 客户端，Lineage 的 AIDL 服务内部 `hw_get_module("consumerir")` 直接调 vendor 的 `consumerir.common.so`，**不走 HIDL** |
| **vibrator** | HIDL 1.0（A16 已删） | `vibrator-service.mediatek`（AIDL） | 已修 |
| **light** | — | 设备树 `lights/` AIDL 服务 | 正常 |
| **memtrack** | HIDL 1.0 | `memtrack-service.mediatek`（AIDL） | 正常，只影响 `dumpsys meminfo` 的 GL 统计 |
| **codec2** | HIDL `media.c2@1.2` | AIDL c2 服务 + shim | 已修（硬解） |
| **gnss / power / sensors / usb** | HIDL | 设备树/mediatek AIDL | 已迁 |

仍然声明 HIDL、A17 也还保留 HIDL 客户端的（不用动，但要能证明它真的连上了）：

`audio@7.0`、`audio.effect@7.0`、`bluetooth@1.1`、`camera.provider@2.6`、
`composer@2.3`、`allocator@4.0`、`mapper@4.0`、`thermal@1.0/2.0`、
`soundtrigger@2.3`、`drm@1.4`、`cas@1.2`、`media.omx@1.0`、`media.c2@1.2`、
`tetheroffload@1.0/1.1`、`health@2.1`、`keymaster@4.1`、`gatekeeper@1.0`。

---

## 三、测试方法

### 0) 先做一次全局「静默失效」扫描（最能抓到 ir/硬解这类问题）

```bash
# VINTF 里声明了、但 hwservicemanager 里根本没注册的 HAL —— 这类就是"看着有、用起来没反应"
adb shell lshal -S | grep -w declared

# AIDL 服务清单（A17 新迁的都在这里）
adb shell lshal --types=a

# 框架服务是否都在
adb shell dumpsys -l | sort > /tmp/svc.txt

# 只在用某个功能时才会冒出来的 binder 失败
adb shell logcat -b all -d | grep -iE "ServiceManagement.*(not found|does not exist)|No such service|Failed to get|vintf.*(fail|mismatch)"
```

判读：`declared` 里出现你要用的那个 HAL，就是"功能不可用但平时不报错"。

### 1) 红外（已修，回归用）

```bash
adb shell lshal -S | grep -i consumerir      # 应看到 android.hardware.ir.IConsumerIr/default = alive
adb shell getprop ro.hardware.consumerir     # common
adb shell ls -l /dev/irtx
```

功能测：装「万能遥控」，选小米电视发一个音量键。
失败时 `logcat -s ConsumerIr` 会有 `hw_get_module failed` 或 `transmit failed`。

### 2) 硬解（已修，回归用）

```bash
adb shell dumpsys media.codec | grep -iE "c2.android|c2.mtk|aidl" | head
adb shell logcat -c; # 播一个 4K HEVC
adb shell logcat -d | grep -iE "CCodec|codec2|OMX" | grep -iE "error|fail|fallback"
```

功能测：Moonlight 串流 + 本地 4K HEVC 播放，`dumpsys media.codec` 里应出现 `c2.mtk.*`
而不是全 `c2.android.*`（软解）。

### 3) 震动 / 背光（A16 迁的，容易"部分场景不震"）

```bash
adb shell cmd vibrator vibrate 500          # 应有震动；无输出且不震 = HAL 没连上
adb shell dumpsys vibrator_manager | head -20
adb shell cmd -l | grep -i light
```

特别测：**关机充电时的呼吸灯**、**来电震动**（这两条走的是不同的调用路径，平时点屏幕不会触发）。

### 4) memtrack（只影响内存统计，最容易漏）

```bash
adb shell dumpsys meminfo com.android.systemui | grep -iE "GL mtrack|EGL mtrack"
```

全是 0 说明 memtrack HAL 没工作——不影响使用，但排查内存问题时会被误导。

### 5) thermal（只在长时间高负载才炸）

```bash
adb shell dumpsys thermalservice | head -30     # 应有 temperature 列表且非全 0
```

测法：跑 10 分钟游戏/Moonlight，看是否降频、`dumpsys thermalservice` 的 throttling status
是否变化。HIDL 没连上时不会报错，只是**永远不降频**（烫手+耗电）。

### 6) soundtrigger（只在"语音唤醒"时用）

```bash
adb shell dumpsys soundtrigger | head -20
```

失败表现：设置里"语音匹配/热词"开关点了没反应，logcat 无报错。

### 7) tetheroffload（只在开热点+大流量时用）

```bash
adb shell dumpsys tethering | grep -iE "offload|hardware"
```

HIDL 没连上会**静默回落到软件转发**：热点能用，但大流量时 CPU 飙高、速度上不去。

### 8) 其余（audio / bt / camera / composer / drm / cas / omx）

```bash
adb shell dumpsys media.audio_flinger | grep -iE "HAL|7.0"
adb shell dumpsys bluetooth_manager | grep -iE "HCI|1.1"
adb shell dumpsys media.camera | grep -iE "provider|2.6"
adb shell dumpsys SurfaceFlinger | grep -iE "composer|2.3"
adb shell dumpsys media.drm | head
adb shell dumpsys media.cas | head
```

这几项的共同特征：HIDL 没连上时**功能整个不可用**（能立刻发现），不属于"静默"类，优先级低。

---

## 四、恢复旧快照后，复现 2026-11-20 源码状态

前提：快照里的 `.ninja_log` 是好的（能增量编译），但 `/cannon/rom` 和
`/cannon/cannon-build` 都会回滚到旧状态。按下面顺序恢复。

### 1) 先恢复 cannon-build 本身（清单、补丁、脚本都在里面）

```bash
git -C /cannon/cannon-build fetch origin
git -C /cannon/cannon-build reset --hard origin/main      # 应到 fbae55b
git -C /cannon/cannon-build log --oneline -1
```

### 2) 单独拉 9 个已固化的仓（不走全量 repo sync）

| path | remote |
|---|---|
| device/xiaomi/cannon | https://github.com/top-android/android_device_xiaomi_cannon |
| vendor/xiaomi/cannon | https://github.com/top-android/android_vendor_xiaomi_cannon |
| frameworks/av | https://github.com/top-android/android_frameworks_av |
| frameworks/base | https://github.com/top-android/android_frameworks_base |
| packages/apps/Settings | https://github.com/top-android/android_packages_apps_Settings |
| packages/apps/Launcher3 | https://github.com/top-android/android_packages_apps_Launcher3 |
| packages/apps/CarrierConfig | https://github.com/top-android/android_packages_apps_CarrierConfig |
| packages/apps/ThemePicker | https://github.com/top-android/android_packages_apps_ThemePicker |
| packages/services/Telephony | https://github.com/top-android/android_packages_services_Telephony |

```bash
cd /cannon/rom
while read -r path url; do
  echo "=== $path"
  git -C "$path" fetch "$url" cannon-a17
  git -C "$path" reset --hard FETCH_HEAD
done <<'EOF'
device/xiaomi/cannon https://github.com/top-android/android_device_xiaomi_cannon
vendor/xiaomi/cannon https://github.com/top-android/android_vendor_xiaomi_cannon
frameworks/av https://github.com/top-android/android_frameworks_av
frameworks/base https://github.com/top-android/android_frameworks_base
packages/apps/Settings https://github.com/top-android/android_packages_apps_Settings
packages/apps/Launcher3 https://github.com/top-android/android_packages_apps_Launcher3
packages/apps/CarrierConfig https://github.com/top-android/android_packages_apps_CarrierConfig
packages/apps/ThemePicker https://github.com/top-android/android_packages_apps_ThemePicker
packages/services/Telephony https://github.com/top-android/android_packages_services_Telephony
EOF
```

> 若某个仓在旧快照里是浅克隆、`reset --hard` 报缺对象，先 `git fetch --unshallow <url>` 再拉。
> `device` / `vendor` 的二进制 prebuilt（`.so`、`prebuilts/c2aidl/*`）都在仓里，`reset --hard` 会一并恢复。

### 3) 同步 .repo 里的清单，避免 repo 认为树被改过

```bash
cp /cannon/cannon-build/local_manifests/cannon-a17.xml \
   /cannon/rom/.repo/local_manifests/cannon-a17.xml
```

### 4) 校验

```bash
bash /cannon/cannon-build/scripts/check_a17_pinned.sh \
     /cannon/cannon-build/manifests/a17-pinned-2026-11-20.xml
# 期望：一致 1197 / 不一致 0 / 缺失 0 / 未锁定 0

CANNON_DRY_RUN=1 bash /cannon/cannon-build/scripts/apply_a17_cannon_patches.sh /cannon/rom
# 期望：applied=0 skipped=21 drift=0 fail=0
```

`check_a17_pinned.sh` 若报「不一致」，说明旧快照里还有别的仓与 11-20 清单不同
（11-18 之前的状态），把差异列出来逐个决定是回退还是保留。

### 5) 编译（user 变体，日志固定 /cannon/build.log）

```bash
cd /cannon/cannon-build
OUT_DIR=/cannon/out-user CANNON_VARIANT=user JOBS=$(nproc) \
  ./build-a17.sh build 2>&1 | tee /cannon/build.log
```

> 注意：`build-a17.sh build` 不重做 init/sync，所以树不会被 repo 改回去。
> 出包后**不要自动上传**，先列改动等确认。

---

## 附：本次固化的 9 个提交

| 仓 | 提交 |
|---|---|
| device/xiaomi/cannon | `2175a34` codec2 AIDL 硬解整套 |
| vendor/xiaomi/cannon | `32e9dfd` 不再拷贝冲突库 |
| frameworks/av | `91b123f` sff deliverMessage patch 等 |
| frameworks/base | `54e07df9` 默认应用 + 信号格去「!」 |
| packages/apps/Settings | `db9f7c3` 更多默认应用页 |
| packages/apps/Launcher3 | `baa603c` 3x5~8x10 网格 |
| packages/apps/CarrierConfig | `c179174` 三运营商中文化 |
| packages/apps/ThemePicker | `4110d93` 布局按行列 |
| packages/services/Telephony | `07cb13a` 配置缓存按构建时间失效 |
