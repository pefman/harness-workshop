#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh

set +e

# helper: tmp vendor dir with a stub llama-server binary
vended_tmp() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/llama.cpp/bin"
  : > "$tmp/llama.cpp/bin/llama-server"
  echo "$tmp"
}

# --- dry-run: prints exact command line ---
tmp=$(vended_tmp)
out=$(LLAMA_VENDOR="$tmp" LLAMA_VRAM_MIB=6000 ./bin/llama-launch.sh --dry-run --model llama-3.2-3b-q4-k-m 2>&1)
rc=$?
assert_eq "$rc" "0" "dry_run_exits_zero"
assert_contains "$out" "llama-server" "dry_run_prints_llama_server"
assert_contains "$out" "--model" "dry_run_prints_model_flag"
assert_contains "$out" "--n-gpu-layers auto" "dry_run_prints_n_gpu_layers"
assert_contains "$out" "--ctx-size 4096" "dry_run_prints_ctx_4096_tier_6_default"
assert_contains "$out" "--host 127.0.0.1 --port 8080" "dry_run_prints_host_port"
rm -rf "$tmp"

# --- dry-run: tier 16 → ctx 16384 ---
tmp=$(vended_tmp)
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-launch.sh --dry-run --tier 16 --model qwen2.5-14b-q6-k 2>&1)
rc=$?
assert_eq "$rc" "0" "dry_run_tier_16_exits_zero"
assert_contains "$out" "--ctx-size 16384" "dry_run_tier_16_ctx_16384"
rm -rf "$tmp"

# --- dry-run: tier 12 → ctx 8192 (default model) ---
tmp=$(vended_tmp)
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-launch.sh --dry-run --tier 12 2>&1)
rc=$?
assert_eq "$rc" "0" "dry_run_tier_12_exits_zero"
assert_contains "$out" "--ctx-size 8192" "dry_run_tier_12_ctx_8192"
rm -rf "$tmp"

# --- missing vendor: exits non-zero, clear message ---
tmp=$(mktemp -d)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-launch.sh --dry-run --model llama-3.2-3b-q4-k-m 2>&1) || rc=$?
assert_eq "$rc" "2" "missing_vendor_exits_2"
assert_contains "$out" "run llama-setup.sh" "missing_vendor_prints_setup_hint"
rm -rf "$tmp"

# --- missing model: dry-run prints download line + command, exits 0, no download ---
tmp=$(vended_tmp)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-launch.sh --dry-run --model llama-3.2-3b-q4-k-m 2>&1) || rc=$?
assert_eq "$rc" "0" "missing_model_dry_run_exits_zero"
assert_contains "$out" "downloading llama-3.2-3b-q4-k-m (~2.02 GB)" "missing_model_prints_download_line"
assert_contains "$out" "llama-server" "missing_model_prints_command_line"
# no download should have happened — file must not exist
assert_eq "$(find "$tmp/models" -name '*.gguf' 2>/dev/null | wc -l)" "0" "missing_model_no_download_in_dry_run"
rm -rf "$tmp"

# --- unknown model: exits non-zero ---
tmp=$(vended_tmp)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-launch.sh --dry-run --model not-a-model 2>&1) || rc=$?
assert_eq "$rc" "2" "unknown_model_exits_2"
assert_contains "$out" "unknown" "unknown_model_prints_message"
rm -rf "$tmp"

set -e
report_and_exit
