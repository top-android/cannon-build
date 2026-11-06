# A17 eng 固定编译指令（2026-11-05 实测 EXIT 0）

> **只准用下面这一条命令。不要手敲 `m`，不要临时加/减环境变量。**
> 2026-11-05 事故：编译跑到 94% 后，手动 `m vendorimage` 漏了 `USE_CCACHE/CCACHE_EXEC`，
> 编译命令指纹变了 → siso 判全脏 → 白重编 8 万步、多花 1 小时。

## 命令

```bash
cd /cannon/cannon-build
CANNON_VARIANT=eng CANNON_RELEASE=cp2a PROFILE=a17 ./build.sh build
```

日志：`/cannon/build.log`（每次启动会清空重写，vendorimage + bacon 都写在这里）
产物：`/cannon/out/target/product/cannon/lineage-24.0-*-cannon.zip`

## 这条命令等价于的环境（build.sh 内部已固定）

| 变量 | 值 | 作用 |
|---|---|---|
| `OUT_DIR` | `out`（**相对**，`/cannon/out` 是树内软链） | siso 的 `--config_repo_dir` 必须是相对路径；绝对路径会报 `@config//main.star` |
| `SOONG_NINJA` | `siso` | 禁止回退 ninja |
| `SOONG_INCREMENTAL_ANALYSIS` | `true` | 不设=false=全量分析（`config.go:359`）；内存 40G 是常态 |
| `USE_CCACHE` | `1` | |
| `CCACHE_EXEC` | `/usr/bin/ccache` | **漏了它 = 编译命令改变 = 全量重编** |
| `CCACHE_DIR` | `/cannon/ccache` | |
| `CCACHE_MAXSIZE` | `50G` | |
| `GOGC` | `30` | 越低越省内存；50 时 soong_build 曾 OOM 被 kill（exit 137） |
| `GOMEMLIMIT` | `44GiB` | Go 软内存上限，防止 `soong_build` 吃满机器被杀 |
| `BUILD_NUMBER` | `$(date +%Y%m%d)` | |
| `JOBS` | `$(nproc)` | 默认取系统最大线程数，内存不足时 `JOBS=N` 覆盖 |
| lunch | `lineage_cannon cp2a eng` | release 默认已是 **cp2a**（脚本内置，不是 bp5a） |

## 流程

1. `m -j$JOBS vendorimage` —— 先补 `vendor.img`。A17 的 target_files 打包会直接 `cp $OUT/vendor.img`，但 kati 没建依赖，并发下会 `cp: bad ... No such file or directory`。已存在则秒过。
2. `m -j$JOBS bacon` —— 出 zip。

## 硬规矩

- **不改源码树**（`.mk` / `.bp` / 任何文件）。改了 mtime，soong 至少要重分析一次（约 10 分钟，`soong_build` 峰值 ~48G）；改生成规则会让整片原生子图判脏。
- 补丁一律由 `apply_a17_cannon_patches.sh` 在**编译前**打，不在编译中途打。
- 要在别处跑 `m`，必须先把上表变量全部 export 成一样的值，否则指纹必变。
- 需要快照 out 时，先停编译，再 `cp -a /cannon/out /cannon/out.snap`（128G，约 1.5 小时）。

---

## A17 在 MT6853（4.14 内核）上必须满足的三个条件

这三条任何一条缺失，都会表现为**卡第一屏 / 卡开机动画、无 adb**，很容易误判成内核问题。

### 1. 内核只有 legacy ION，没有 dma-heap

`/proc/config.gz` 里只有 `CONFIG_ION=y`，**没有** `CONFIG_DMABUF_HEAPS`，`/dev/dma_heap` 不存在；
vendor 的 gralloc4（`android.hardware.graphics.allocator@4.0-impl-mediatek`）只会走 dma-buf heap，
所以 `libdmabufheap` 必须编成 **legacy ION 实现**。device 树里需要：

```make
$(call soong_config_set_bool,libion,legacy_impl,true)
```

不设时（AOSP 默认）编出来的 `libdmabufheap.so` 里没有 `/dev/ion` 字符串，运行期报：

```
DMABUFHEAPS: Could not open DMA-BUF heap named: mtk_mm/system
gralloc4: allocate, buffer allocation failed with 2
GraphicBufferAllocator: Failed to allocate (384 x 384) ... : 5
```

验证方法：`strings /system/lib64/libdmabufheap.so | grep -c /dev/ion`，应为 3（不是 0）。

### 2. SELinux 必须放行 HAL 访问 /dev/ion

BoardConfig 里需要（Lineage 提供的一整套规则）：

```make
include device/lineage/sepolicy/libion/sepolicy.mk
```

它会给 system_ext 私有策略加 `allow hal_graphics_allocator ion_device:chr_file r_file_perms;`。
缺这条时 `open("/dev/ion")` 被拒，分配同样全失败；而本机内核 `audit_enabled=0`，
**dmesg/logcat 里看不到 avc 拒绝**，只能靠 `setenforce 0` 对照。

验证：`grep -c 'hal_graphics_allocator ion_device' /system_ext/etc/selinux/system_ext_sepolicy.cil`，应为 1。

### 3. packages/modules/Connectivity 必须固定在 d468719

A17 的 BPF（netd/offload 程序、ringbuf、bpfloader 降级）要在 4.14 上跑，需要 cannong 的
组件集成提交 `d468719`（8 个文件、624 行）。主线版本会导致：

```
E LocalNetEventHandler: BpfRingbuf init failed: /sys/fs/bpf/netd_shared/... No such file
system_server SIGABRT (libservice-connectivity.so → eventpolling → nativeGetLocalNetwork...)
```

表现为**开机动画循环**（framework 起不来）。`build.sh apply` 会调
`scripts/pin_a17_connectivity.sh` 自动固定到该提交。

## 已知约束

- **kernel**：仓库里的 4.14.336 缺 A17 需要的 BPF 能力（`BPF_MAP_TYPE_*` 22 vs 49），
  init 等不到 `bpf.progs_loaded` 会主动 `reboot bpfloader-failed`。必须用 4.14.357（OpenELA）
  那一支，或者把 BPF 整体 backport。
- **vendor**：自有 V13 blob 的 gralloc/HAL 组合在本机能开机，但需要上面第 1、2 条同时成立；
  改 vendor 后务必先单独验证 `screencap -p /data/local/tmp/a.png` 能否出文件。
- 4.14 内核无 dma-heap 时，allocator 服务若在 `/dev/ion` 就绪前启动，会把 `ion_fd_=-1` 缓存住，
  只能 `stop/start vendor.gralloc-4-0` 恢复。策略修好后正常启动不会触发。

