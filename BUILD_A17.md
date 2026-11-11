# A17 — LineageOS 24.0 / Android 17

## 命令

```bash
cd /cannon/cannon-build
./build-a17.sh all             # 锁定清单 init + sync + build（A17 不再 apply 补丁）
./build-a17.sh build           # 树已就绪，只编
./build-a17.sh module vendorimage
./build-a17.sh --help          # 完整用法（子命令 / 变体 / 环境变量 / 例子）
```

变体由 `CANNON_VARIANT` 控制（默认 `userdebug`），release 默认 `cp2a`：

| 变体 | lunch | ro.debuggable | 用途 |
|---|---|---|---|
| `userdebug` | `lineage_cannon cp2a userdebug` | 1 | 日常调试（默认） |
| `eng` | `lineage_cannon cp2a eng` | 1 | 工程变体 |
| `user` | `lineage_cannon cp2a user` | 0 | 发布，需要签名密钥 |

产物 `/cannon/out/target/product/cannon/lineage-24.0-*-cannon.zip`，日志 `/cannon/build.log`。

### 切换变体

切换会触发 installclean —— build 打印 `Build configuration changed ... forcing installclean`，
删掉 `out/target/product/cannon/` 下已装好的 system / system_ext / product / vendor 和全部 `.img`，
并因编译参数变化接近全量重编（约 12 万步）。`build-a17.sh` 会比对
`out/target/product/cannon/previous_build_config.mk` 并**中止**；确实要就地切，加
`CANNON_ALLOW_VARIANT_SWITCH=1`。更推荐给每个变体单独一个 OUT_DIR，别冲掉现有产物：

```bash
OUT_DIR=/cannon/out-user CANNON_VARIANT=user ./build-a17.sh all
CANNON_ALLOW_VARIANT_SWITCH=1 CANNON_VARIANT=eng ./build-a17.sh build
```

> ⚠ `device/xiaomi/cannon/device.mk` 里写死了 eng 的 ADB 属性矩阵
> （`ro.secure=0` / `ro.adb.secure=0` / `service.adb.root=1` → `/product/build.prop`），
> `user` 变体也会带上这套。正式发布前必须改回。

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

`build.sh` 只跑 `m -j$JOBS bacon`，一次出 zip。

2026-11-08 之前「先 `m vendorimage` 再 `bacon`」的 workaround 已删除：根因是 target_files
打包对 `vendor.img` 本体没有依赖 → 并发抢跑（`No such file` / 无 AVB footer / sparse 头半截），
已由 `repro/patches/a17/build_make.patch` 在 `build/make/core/Makefile` 里补显式依赖修复。

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

### 3. 全部修复仓走 top-android fork 单轨（2026-11-11 起）

A17 的修复不再靠「sync 后打补丁」，而是 commit 到 GitHub 组织 `top-android` 各仓的
`cannon-a17` 分支，由唯一的 `.repo/local_manifests/cannon-a17.xml` 指过去（23 个 project），
`APPLY_PATCHES=0`，`repro/patches/a17/` 只作归档、不再参与构建。

| 分类 | project |
|---|---|
| AOSP / LineageOS 侧（18） | art、build/make、build/soong、frameworks/base、frameworks/native、frameworks/opt/telephony、hardware/lineage/compat、hardware/nxp/secure_element、hardware/xiaomi、packages/apps/{Jelly,Launcher3,Settings}、packages/modules/{NetworkStack,Bluetooth,Connectivity}、packages/providers/MediaProvider、system/{core,netd,sepolicy}、vendor/lineage |
| 设备侧（5） | device/xiaomi/cannon、vendor/xiaomi/cannon、system/bpf |
| 由 pinned 钉 SHA（不重复定义） | kernel/xiaomi/cannon、hardware/mediatek、hardware/mediatek/wlan、packages/modules/Wifi、device/mediatek/sepolicy_vndr、vendor/lineage-priv/keys |

- 清单里统一用 `remove-project` + `top-android/*` + `revision="cannon-a17"` 覆盖 pinned 条目；
  未列出的 1200+ project 仍按 pinned SHA checkout。
- `cmd_init_pinned` 只保留 `cannon-a17.xml`（或安装后的 `cannon.xml`），不再有 `cannon-fork.xml`。
- 首次切换（project `name` 从 `LineageOS/*` 变成 `top-android/*`）必须重建 `.git` 元数据，
  执行一次（线程数跟随机器，不用写死 `-j8`）：

```bash
cd /cannon/rom
src=(art build/make build/soong frameworks/base frameworks/native frameworks/opt/telephony \
  hardware/lineage/compat hardware/nxp/secure_element hardware/xiaomi \
  packages/apps/Jelly packages/apps/Launcher3 packages/apps/Settings \
  packages/modules/{NetworkStack,Bluetooth,Connectivity} packages/providers/MediaProvider \
  system/{core,netd,sepolicy} vendor/lineage device/xiaomi/cannon vendor/xiaomi/cannon system/bpf)
PATH=/root/bin:$PATH repo sync --force-sync -j"$(nproc)" "${src[@]}"
```

之后普通 `repo sync` 即可，全部修复仓不再 apply 补丁。上游更新时在各 fork 的
`cannon-a17` 上 `git rebase LineageOS/lineage-24.0`，再重新导出 pinned 清单基线 SHA。

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

## 复现「当期树」（锁定清单 / build-a17.sh）

`local_manifests/cannon-a17.xml` 里公有上游仓跟的是 `refs/heads/lineage-24.0`（移动分支），
`repo sync` 拿到的 HEAD 会随上游前进 —— 那时 `repro/patches/a17/*.patch`（按导出当天的 HEAD
生成）就可能 drift。要 1:1 复现当期树，用 **`build-a17.sh`**（A17 专用入口，默认锁定清单模式）：

> 锁定清单模式**照样 `--depth=1` 浅克隆**（clone 速度不变）：repo 对 SHA revision 直接
> `git fetch --depth=1 <url> <sha>`，GitHub 支持按 SHA 浅取。实测 `system/bpf@1787201`
> 3 秒取到，本地 1 条提交 + `.git/shallow`。要回溯历史时 `git fetch --unshallow`。
>
> 补丁与清单是配套的：清单不变就不会 drift。将来换新清单（上游前移）后补丁若报
> 「漂移/不匹配」，按 `repro/patches/a17/INDEX.md` 末尾的方法用 `git diff HEAD` 重导即可。

```bash
cd /cannon/cannon-build
./build-a17.sh all          # init（锁定清单）+ sync + build（无 apply 阶段）
# 或分步：init / sync / apply / build / module <target>
```

它做的事和 `PROFILE=a17 CANNON_VARIANT=userdebug ./build.sh ...` 完全一样，**只有 init/sync 不同**：
不再装 `local_manifests/cannon-a17.xml` 跟分支，而是把 `manifests/a17-pinned-*.xml`
（默认取最新的那份）装进 `.repo/manifests/` 再 `repo init -m`，1241 个 project 全钉在 40 位 SHA。
`build.sh` 里对应 `PINNED_MANIFEST=<路径|latest>`，手工等价操作：

```bash
cd /cannon/rom
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0   # 先建 .repo
cp /cannon/cannon-build/manifests/a17-pinned-2026-11-10.xml .repo/manifests/
mkdir -p .repo/local_manifests && cp /cannon/cannon-build/local_manifests/cannon-fork.xml .repo/local_manifests/
repo init -m a17-pinned-2026-11-10.xml
repo sync -c -j"$(nproc)"
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

> 注意区分入口：
> - `./build-a17.sh ...` → 锁定清单模式（推荐，树可复现）
> - `PROFILE=a17 ./build.sh init` → 分支模式（装 `local_manifests/cannon-a17.xml`，
>   树随上游前进）。`build.sh build/module` 不重做 init，所以已经在锁定树上时
>   继续 `./build-a17.sh build` 不会破坏锁定状态。
