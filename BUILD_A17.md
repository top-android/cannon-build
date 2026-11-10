# A17 — LineageOS 24.0 / Android 17

## 命令

```bash
cd /cannon/cannon-build
PROFILE=a17 ./build.sh build
```

变体默认 `userdebug`，release 默认 `cp2a`。产物 `/cannon/out/target/product/cannon/lineage-24.0-*-cannon.zip`，
日志 `/cannon/build.log`。

## 固定环境

`build.sh` 内部已固定，不要临时增删——任何一项变化都会改变编译命令指纹，触发全量重编。

| 变量 | 值 | 说明 |
|---|---|---|
| `OUT_DIR` | `out`（相对） | siso 的 `--config_repo_dir` 必须是相对路径 |
| `SOONG_NINJA` | `siso` | 禁止回退 ninja |
| `SOONG_INCREMENTAL_ANALYSIS` | `true` | 不设等于全量分析 |
| `USE_CCACHE` | `1` | |
| `CCACHE_EXEC` | `/usr/bin/ccache` | 漏了它等于换了一套编译命令 |
| `CCACHE_DIR` | `/cannon/ccache` | |
| `CCACHE_MAXSIZE` | `50G` | |
| `GOGC` | `100` | Go 默认值；机器 64G，`30` 只会让 runtime 频繁 GC |
| `BUILD_NUMBER` | `$(date +%Y%m%d)` | |
| `JOBS` | `$(nproc)` | 内存不足时用 `JOBS=N` 覆盖 |

## 流程

1. `m -j$JOBS vendorimage` —— A17 的 target_files 打包直接 `cp $OUT/vendor.img`，kati 未建依赖，需先补。
2. `m -j$JOBS bacon` —— 出 zip。

## 三个必要条件

缺任何一条都会表现为卡第一屏 / 卡开机动画、无 adb，容易误判成内核问题。

### 1. 内核只有 legacy ION，没有 dma-heap

`/proc/config.gz` 里只有 `CONFIG_ION=y`，没有 `CONFIG_DMABUF_HEAPS`，`/dev/dma_heap` 不存在；
vendor 的 gralloc4 只走 dma-buf heap，因此 `libdmabufheap` 必须编成 legacy ION 实现。设备树需要：

```make
$(call soong_config_set_bool,libion,legacy_impl,true)
```

验证：`strings /system/lib64/libdmabufheap.so | grep -c /dev/ion` 应为 3。

### 2. SELinux 放行 HAL 访问 /dev/ion

```make
include device/lineage/sepolicy/libion/sepolicy.mk
```

缺这条时 `open("/dev/ion")` 被拒；本机内核 `audit_enabled=0`，dmesg/logcat 里看不到 avc 拒绝。

验证：`grep -c 'hal_graphics_allocator ion_device' /system_ext/etc/selinux/system_ext_sepolicy.cil` 应为 1。

### 3. packages/modules/Connectivity 固定在 d468719

A17 的 BPF（netd/offload 程序、ringbuf）需要 cannong 的组件集成提交 `d468719`。
`build.sh apply` 会调 `scripts/pin_a17_connectivity.sh` 自动固定。

## 内核

固定用 `kernel/xiaomi/cannon`（4.14.336），树外 `O=/cannon/kbuild/out-rom-a17` 全量编译：

```bash
bash /cannon/kbuild/build-a17-panic.sh
```

该内核没有 A17 需要的 BPF backport 能力（`CGROUP_SOCK_ADDR` / `CGROUP_SOCKOPT` /
`INET_SOCK_RELEASE`，`bpf_prog_load` 直接返回 `-EINVAL`），因此 **不 backport，走闸门降级**：
`packages_modules_Connectivity.patch` 把 V/25Q2/25Q4 版本闸门降级为警告，
`loadAllObjects()` 失败不 `return 38`（否则走不到平台 loader，`/system/etc/bpf/gpuMem.bpf`
不会 pin，system_server 读 `gpu_mem_total_map` 时直接 abort），
BpfHandler / NetdUpdatable / ClatCoordinator 失败不 abort。

代价：netd 拿不到 BPF 程序，socket tagging、data saver、cgroup 策略降级。

## 复现「当期树」（锁定清单）

`local_manifests/cannon-a17.xml` 里公有上游仓跟的是 `refs/heads/lineage-24.0`（移动分支），
`repo sync` 拿到的 HEAD 会随上游前进 —— 那时 `repro/patches/a17/*.patch`（按导出当天的 HEAD
生成）就可能 drift。要 1:1 复现当期树，用 `repo manifest -r` 导出的锁定清单：

```bash
cd /cannon/rom
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0   # 先正常 init
cp /cannon/cannon-build/manifests/a17-pinned-2026-11-10.xml .repo/manifests/
mv .repo/local_manifests .repo/local_manifests.bak    # 锁定清单已含自有仓，避免重复 project
repo init -m a17-pinned-2026-11-10.xml                # 不重给 -u，沿用上面的 url/branch
repo sync -c -j8
```

清单内容：**1241 个 project 全部 `revision=<40 位 SHA>`**，包括
6 个自有仓（device / vendor / kernel / hardware-mediatek / hardware-mediatek_wlan /
packages-modules-Wifi）、`vendor/lineage-priv/keys`，以及 pin 过的
`packages/modules/Connectivity@d468719`。

校验当前树是不是这份清单：

```bash
bash /cannon/cannon-build/scripts/check_a17_pinned.sh \
     /cannon/cannon-build/manifests/a17-pinned-2026-11-10.xml
# 一致 1197 / 不一致 0 / 缺失 0 / 未锁定 0
```

> `build.sh init` 会把 `local_manifests/cannon-a17.xml` 重新装回去并 `repo init` 到**分支模式**，
> 那之后就不再是锁定的树了。要锁定状态就别再跑 `build.sh init`；日常 `build` 不受影响
> （它只 lunch + 编，不重做 init）。
