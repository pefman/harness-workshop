#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh

set +e

# --- list: tier 6, JSON output (no GPU dependency) ---
list_out=$(./bin/llama-models.sh list --tier 6 --json 2>&1)
rc=$?
assert_eq "$rc" "0" "list_tier_6_exits_zero"
line_count=$(echo "$list_out" | wc -l)
assert_eq "$line_count" "5" "list_tier_6_five_lines"
# every line is valid JSON
bad=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! echo "$line" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    bad=$((bad+1))
  fi
done <<< "$list_out"
assert_eq "$bad" "0" "list_tier_6_json_all_lines_parse"
# line contains id and family
list_first_line=$(echo "$list_out" | head -1)
assert_contains "$list_first_line" "qwen2.5-0.5b-q4-k-m" "list_tier_6_contains_smallest_model"

# --- list: active tier from GPU env (no --tier) ---
active=$(LLAMA_VRAM_MIB=24564 ./bin/llama-models.sh list 2>&1)
rc=$?
assert_eq "$rc" "0" "list_active_tier_exits_zero"
line_count=$(echo "$active" | wc -l)
assert_eq "$line_count" "5" "list_active_tier_five_lines"

# --- list: no GPU, no tier → falls back to tier 6 with a note ---
fallback=$(LLAMA_FORCE_NO_GPU=1 ./bin/llama-models.sh list 2>&1)
rc=$?
assert_eq "$rc" "0" "list_fallback_exits_zero"
assert_contains "$fallback" "tier 6" "list_fallback_prints_tier_6"

# --- download: missing file and no network → exits non-zero ---
tmp=$(mktemp -d)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download qwen2.5-0.5b-q4-k-m 2>&1) || rc=$?
# no network: either non-zero (offline) or 0 if network happens to work — must not hang forever
# assert we got SOME output, not nothing
[ -n "$out" ] || { echo "FAIL: download_offline_prints_output — empty output"; _FAIL_COUNT=$((_FAIL_COUNT+1)); _TEST_COUNT=$((_TEST_COUNT+1)); }
rm -rf "$tmp"

# --- download: file present with wrong size → exit non-zero, clear message ---
tmp=$(mktemp -d)
mkdir -p "$tmp/models"
: > "$tmp/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download qwen2.5-0.5b-q4-k-m 2>&1) || rc=$?
assert_eq "$rc" "2" "download_wrong_size_exits_2"
assert_contains "$out" "size" "download_wrong_size_prints_message"
rm -rf "$tmp"

# --- download: file present with right size → exits 0, "already installed" ---
tmp=$(mktemp -d)
mkdir -p "$tmp/models"
truncate -s 370000000 "$tmp/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download qwen2.5-0.5b-q4-k-m 2>&1) || rc=$?
assert_eq "$rc" "0" "download_correct_size_exits_zero"
assert_contains "$out" "already installed" "download_correct_size_prints_installed"
rm -rf "$tmp"

# --- download: unknown id exits non-zero ---
tmp=$(mktemp -d)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download not-a-real-model 2>&1) || rc=$?
assert_eq "$rc" "2" "download_unknown_id_exits_2"
assert_contains "$out" "unknown" "download_unknown_id_prints_message"
rm -rf "$tmp"

# --- download all (network-gated) ---
if [ "${LLAMA_TEST_NETWORK:-0}" = "1" ]; then
  # only the smallest model (~0.37 GB) — explicit authorization
  tmp=$(mktemp -d)
  rc=0
  out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download qwen2.5-0.5b-q4-k-m 2>&1) || rc=$?
  assert_eq "$rc" "0" "download_smallest_model_exits_zero"
  assert_file_exists "$tmp/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf" "download_smallest_model_file_exists"
  rm -rf "$tmp"
fi

# opt-in: all-5 tier-6 download (~6.7 GB total), off by default
if [ "${LLAMA_TEST_NETWORK_ALL:-0}" = "1" ]; then
  tmp=$(mktemp -d)
  rc=0
  out=$(LLAMA_VENDOR="$tmp" ./bin/llama-models.sh download all --tier 6 2>&1) || rc=$?
  assert_eq "$rc" "0" "download_all_tier_6_exits_zero"
  found=$(find "$tmp/models" -name "*.gguf" -type f 2>/dev/null | wc -l)
  assert_eq "$found" "5" "download_all_tier_6_five_files_after_download"
  rm -rf "$tmp"
fi

set -e
report_and_exit
