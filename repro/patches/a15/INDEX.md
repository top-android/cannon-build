# A15 工作树补丁快照（自动导出）

> 由 `scripts/export_dirty_patches.sh` 于 2026-10-30 12:51:55 生成。
> 用途：防丢失的**当前工作树**文本快照。注意：这些是“已应用态”导出，apply 到干净树前需人工比对基线。
> 二进制改动（.apk/.so/.bin）不在补丁内容里，需由 repatch/patchelf 脚本再生。

| 仓库 | 补丁文件 | tracked 变更 | 新增源码文件 |
|---|---|---|---|
| `kernel/xiaomi/cannon` | kernel_xiaomi_cannon.patch | 无（2026-10-30 r31 回退扫描裁剪，工作树=HEAD；空补丁，apply 跳过）| — |
