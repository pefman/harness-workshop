#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source tests/_assert.sh
source lib/common.sh

# native_linux_reports_not_wsl — detect_wsl returns 0 (not WSL) here
r=$(detect_wsl)
assert_eq "$r" "0" "native_linux_reports_not_wsl"

# snap_tier_below_6g — rounds down, floors at 6
assert_eq "$(snap_tier 5)"   "6"  "snap_tier_below_6g_5gb"
assert_eq "$(snap_tier 6)"   "6"  "snap_tier_below_6g_6gb"
assert_eq "$(snap_tier 7)"   "6"  "snap_tier_below_6g_7gb"
assert_eq "$(snap_tier 8)"   "8"  "snap_tier_8gb"
assert_eq "$(snap_tier 13)"  "12" "snap_tier_13gb"
assert_eq "$(snap_tier 24)"  "16" "snap_tier_24gb"

# vram_gb_from_mib — rounds to whole GB
assert_eq "$(vram_gb_from_mib 24564)" "24" "vram_gb_from_mib_24564"

# detect_gpu_missing_handled — env override wins; missing nvidia-smi errors clearly
if out=$(LLAMA_VRAM_MIB=24564 detect_gpu_memory_mib 2>/tmp/llama-err.txt); then
  assert_eq "$out" "24564" "gpu_memory_from_env"
else
  echo "FAIL: gpu_memory_from_env — expected success"
  _FAIL_COUNT=$((_FAIL_COUNT+1))
  _TEST_COUNT=$((_TEST_COUNT+1))
fi

# missing nvidia-smi: PATH set to a dir without nvidia-smi → clear error, non-zero exit
if out=$(PATH=/nonexistent detect_gpu_memory_mib 2>&1); then
  echo "FAIL: gpu_missing_errors — expected non-zero exit"
  _FAIL_COUNT=$((_FAIL_COUNT+1))
  _TEST_COUNT=$((_TEST_COUNT+1))
else
  assert_contains "$out" "nvidia-smi" "gpu_missing_errors"
fi

# color_not_tty_plain — plain text when LLAMA_NO_COLOR is set
assert_eq "$(LLAMA_NO_COLOR=1 color "hello" "31")" "hello" "color_not_tty_plain"

report_and_exit
