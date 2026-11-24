#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh
source config/models.sh
source config/llama.sh

# five entries per tier
for tier in 6 8 12 16; do
  n=$(list_models_for_tier "$tier" | wc -l)
  assert_eq "$n" "5" "list_models_for_tier_${tier}_five_entries"
done

# each tier includes at least one Llama-family entry; tier 16 includes at least one Qwen
assert_at_least_one_llama() {
  local tier="$1" out count
  out=$(list_models_for_tier "$tier")
  count=$(echo "$out" | awk '$4=="llama"{c++} END{print c+0}')
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [ "$count" -ge 1 ]; then
    echo "pass: tier_${tier}_includes_llama"
  else
    echo "FAIL: tier_${tier}_includes_llama — expected >=1 llama entry, got $count"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  fi
}
for tier in 6 8 12 16; do
  assert_at_least_one_llama "$tier"
done

out=$(list_models_for_tier 16)
q_count=$(echo "$out" | awk '$4=="qwen"{c++} END{print c+0}')
_TEST_COUNT=$((_TEST_COUNT+1))
if [ "$q_count" -ge 1 ]; then
  echo "pass: tier_16_includes_qwen"
else
  echo "FAIL: tier_16_includes_qwen — expected >=1 qwen entry, got $q_count"
  _FAIL_COUNT=$((_FAIL_COUNT+1))
fi

# model_url returns the HF resolve URL
assert_eq "$(model_url llama-3.2-3b-q4-k-m)" \
  "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf" \
  "model_url_llama_3_2_3b_q4_k_m"

# defaults per tier
assert_eq "$(default_model_for_tier 6)"  "llama-3.2-3b-q4-k-m"  "default_tier_6"
assert_eq "$(default_model_for_tier 8)"  "llama-3.1-8b-q4-k-m"  "default_tier_8"
assert_eq "$(default_model_for_tier 12)" "llama-3.1-8b-q8-0"    "default_tier_12"
assert_eq "$(default_model_for_tier 16)" "qwen2.5-14b-q6-k"      "default_tier_16"

# binary manifest is complete (two assets: binaries + CUDA runtime)
[[ -n "${LLAMA_CPP_BUILD_ID:-}"  ]] && assert_eq "$LLAMA_CPP_BUILD_ID" "b12675" "binary_build_id" \
  || { echo "FAIL: binary_build_id — LLAMA_CPP_BUILD_ID unset"; _FAIL_COUNT=$((_FAIL_COUNT+1)); _TEST_COUNT=$((_TEST_COUNT+1)); }
assert_contains "${LLAMA_CPP_BIN_URL:-}" "b12675" "binary_bin_url_contains_build_id"
assert_contains "${LLAMA_CPP_BIN_URL:-}" "ubuntu-cuda-12.8-x64" "binary_bin_url_is_cuda_12_8"
assert_eq "${LLAMA_CPP_BIN_SIZE_BYTES:-0}" "220261389" "binary_bin_size_bytes"
assert_contains "${LLAMA_CPP_CUDART_URL:-}" "b12675" "binary_cudart_url_contains_build_id"
assert_eq "${LLAMA_CPP_CUDART_SIZE_BYTES:-0}" "594372523" "binary_cudart_size_bytes"

report_and_exit
