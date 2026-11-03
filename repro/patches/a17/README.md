# repro/patches/a17/ — A17(LOS 24.0) 构建期补丁目录

状态：**基线阶段（空）**。A17 属全新系统，构建期补丁需在 A17 源码上按“症状签名”
重新定位后导出（勿照抄 A16 行号，跨版本必漂移）。

- 导出：`bash scripts/export_dirty_patches_a17.sh`（待建，参照 export_a16_dirty_patches.sh）
- 重放：`bash scripts/apply_a17_cannon_patches.sh /cannon/rom-a17`
  当前无补丁时该脚本打印提示并 0 退出（sync 即可）。
