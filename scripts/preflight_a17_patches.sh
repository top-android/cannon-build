#!/bin/bash
# A17 编译前检查（只读）：确认已知"树外 out / sbox 内核头"坑的补丁是否就位。
# 不满足则 exit 1，阻止盲目开编。用法： bash scripts/preflight_a17_patches.sh
set -u
TOP=/cannon/rom-a17
LAUNCHER=/cannon/scripts/run_a17_build_detached.sh
fail=0
chk(){ if [ "$1" = 1 ]; then echo "  [OK]   $2"; else echo "  [FAIL] $2"; fail=1; fi; }

echo "== A17 编译前检查 =="
echo "  $(grep -oE '^export OUT_DIR=[^ ]+' "$LAUNCHER" 2>/dev/null | head -1)"

# 1) OUT_DIR 必须相对(out*)，绝对会致 siso @config//main.star 失败
if grep -qE '^export OUT_DIR=out' "$LAUNCHER"; then chk 1 "OUT_DIR 相对"; else chk 0 "OUT_DIR 必须相对(out*)，别用绝对路径"; fi

# 2) kernel 头 sbox 需 dep_files 含 scripts/** 与 arch/$(KERNEL_ARCH)/Makefile
BP=$TOP/vendor/lineage/build/soong/Android.bp
if grep -q 'scripts/\*\*/\*' "$BP" && grep -q 'arch/\$(KERNEL_ARCH)/Makefile' "$BP"; then chk 1 "Android.bp dep_files 含 scripts/**+arch Makefile"; else chk 0 "Android.bp dep_files 缺 scripts/** 或 arch Makefile"; fi

# 3) clean_headers.sh 在 sbox(chroot 无 bionic) 需优雅跳过
CH=$TOP/vendor/lineage/tools/clean_headers.sh
if grep -q 'without bionic); skip' "$CH"; then chk 1 "clean_headers.sh 有 sbox 优雅跳过"; else chk 0 "clean_headers.sh 未处理无 bionic(会127)"; fi

# 4) 内核头 O= 必须绝对
# 首选：build/tasks/kernel.mk 用 O=$(abspath ...) 手术式绝对（持久、不重脏原生图）
KM=$TOP/vendor/lineage/build/tasks/kernel.mk
BK=$TOP/vendor/lineage/config/BoardConfigKernel.mk
if grep -q 'O=$(abspath $(KERNEL_BUILD_OUT_PREFIX)' "$KM"; then
  chk 1 "kernel.mk 用 O=\$(abspath ...) 手术式绝对(持久解，不重脏原生图)"
elif grep -qE '^KERNEL_BUILD_OUT_PREFIX[[:space:]]*:=[[:space:]]*\$\(BUILD_TOP\)/' "$BK" && ! grep -q 'ifeq ($(OUT_DIR_PREFIX),out)' "$BK"; then
  chk 1 "BoardConfigKernel.mk KERNEL_BUILD_OUT_PREFIX 无条件绝对(根治解已落地)"
else
  MF=$TOP/out-a17/soong/.intermediates/vendor/lineage/build/soong/generated_kernel_includes/generator.sbox.textproto
  if [ -f "$MF" ] && grep -q 'O=/cannon/rom-a17/out-a17' "$MF"; then
    chk 1 "持久解未落地，但 manifest 有临时绝对O=兜底(仅当前out/不重分析时有效，重分析会失效)"
  else
    chk 0 "内核头 O= 非绝对：kernel.mk/BoardConfigKernel.mk 未修 且 manifest 无临时兜底 → 头会被沙箱丢弃"
  fi
fi

echo "== 结果：$([ $fail = 0 ] && echo PASS || echo '有未满足项 → 请先补丁再编') =="
exit $fail
