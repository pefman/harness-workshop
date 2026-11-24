#!/usr/bin/env bash
# config/models.sh — tier→models library (measured GGUF sizes, bartowski repos).
# Sourced by bin/*.sh. Sizes are real download bytes / 1024^3, rounded to 2dp.

if ! declare -A _LLAMA_MODELS_PROBE 2>/dev/null; then
  echo "error: config/models.sh requires bash 4+ (associative arrays)" >&2
  return 2
fi

declare -A tier_models
declare -A model_entry
declare -A tier_defaults

# --- tier 6 (2 GB class) ---
tier_models[6]="qwen2.5-0.5b-q4-k-m
llama-3.2-1b-q4-k-m
gemma-2-2b-q4-k-m
qwen2.5-3b-q4-k-m
llama-3.2-3b-q4-k-m"
tier_defaults[6]="llama-3.2-3b-q4-k-m"

# --- tier 8 (4-5 GB class) ---
tier_models[8]="mistral-7b-q4-k-m
llama-3.1-8b-q4-k-s
llama-3.1-8b-q4-k-m
qwen2.5-7b-q4-k-m
gemma-2-9b-q4-k-s"
tier_defaults[8]="llama-3.1-8b-q4-k-m"

# --- tier 12 (6-9 GB class) ---
tier_models[12]="llama-3.1-8b-q6-k-l
mistral-7b-q8-0
llama-3.1-8b-q8-0
qwen2.5-14b-q4-k-m
gemma-2-9b-q8-0"
tier_defaults[12]="llama-3.1-8b-q8-0"

# --- tier 16 (8-11 GB class) ---
tier_models[16]="mistral-7b-q8-0
llama-3.1-8b-q8-0
qwen2.5-14b-q4-k-s
gemma-2-9b-q8-0
qwen2.5-14b-q6-k"
tier_defaults[16]="qwen2.5-14b-q6-k"

# --- model entries: size_gb|quant|family|params|hf_repo|hf_file ---
model_entry[qwen2.5-0.5b-q4-k-m]="0.37|Q4_K_M|qwen|0.5B|bartowski/Qwen2.5-0.5B-Instruct-GGUF|Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"
model_entry[llama-3.2-1b-q4-k-m]="0.81|Q4_K_M|llama|1B|bartowski/Llama-3.2-1B-Instruct-GGUF|Llama-3.2-1B-Instruct-Q4_K_M.gguf"
model_entry[gemma-2-2b-q4-k-m]="1.59|Q4_K_M|gemma|2B|bartowski/gemma-2-2b-it-GGUF|gemma-2-2b-it-Q4_K_M.gguf"
model_entry[qwen2.5-3b-q4-k-m]="1.93|Q4_K_M|qwen|3B|bartowski/Qwen2.5-3B-Instruct-GGUF|Qwen2.5-3B-Instruct-Q4_K_M.gguf"
model_entry[llama-3.2-3b-q4-k-m]="2.02|Q4_K_M|llama|3B|bartowski/Llama-3.2-3B-Instruct-GGUF|Llama-3.2-3B-Instruct-Q4_K_M.gguf"

model_entry[mistral-7b-q4-k-m]="4.07|Q4_K_M|mistral|7B|bartowski/Mistral-7B-Instruct-v0.3-GGUF|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
model_entry[llama-3.1-8b-q4-k-s]="4.37|Q4_K_S|llama|8B|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_S.gguf"
model_entry[llama-3.1-8b-q4-k-m]="4.58|Q4_K_M|llama|8B|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
model_entry[qwen2.5-7b-q4-k-m]="4.68|Q4_K_M|qwen|7B|bartowski/Qwen2.5-7B-Instruct-GGUF|Qwen2.5-7B-Instruct-Q4_K_M.gguf"
model_entry[gemma-2-9b-q4-k-s]="5.10|Q4_K_S|gemma|9B|bartowski/gemma-2-9b-it-GGUF|gemma-2-9b-it-Q4_K_S.gguf"

model_entry[llama-3.1-8b-q6-k-l]="6.38|Q6_K_L|llama|8B|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q6_K_L.gguf"
model_entry[mistral-7b-q8-0]="7.17|Q8_0|mistral|7B|bartowski/Mistral-7B-Instruct-v0.3-GGUF|Mistral-7B-Instruct-v0.3-Q8_0.gguf"
model_entry[llama-3.1-8b-q8-0]="7.95|Q8_0|llama|8B|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q8_0.gguf"
model_entry[qwen2.5-14b-q4-k-m]="8.37|Q4_K_M|qwen|14B|bartowski/Qwen2.5-14B-Instruct-GGUF|Qwen2.5-14B-Instruct-Q4_K_M.gguf"
model_entry[gemma-2-9b-q8-0]="9.15|Q8_0|gemma|9B|bartowski/gemma-2-9b-it-GGUF|gemma-2-9b-it-Q8_0.gguf"

model_entry[qwen2.5-14b-q4-k-s]="7.98|Q4_K_S|qwen|14B|bartowski/Qwen2.5-14B-Instruct-GGUF|Qwen2.5-14B-Instruct-Q4_K_S.gguf"
model_entry[qwen2.5-14b-q6-k]="11.29|Q6_K|qwen|14B|bartowski/Qwen2.5-14B-Instruct-GGUF|Qwen2.5-14B-Instruct-Q6_K.gguf"

# list_models_for_tier(tier) → prints 5 lines: <id> <size> GB <family> <params> <quant>
list_models_for_tier() {
  local tier="$1"
  [[ -n "${tier_models[$tier]:-}" ]] || { echo "error: unknown tier '$tier'" >&2; return 1; }
  local ids="${tier_models[$tier]}"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    IFS='|' read -r size quant family params repo file <<< "${model_entry[$id]}"
    echo "$id $size GB $family $params $quant"
  done <<< "$ids"
}

# model_url(id) → https://huggingface.co/<repo>/resolve/main/<file>
model_url() {
  local id="$1"
  [[ -n "${model_entry[$id]:-}" ]] || { echo "error: unknown model id '$id'" >&2; return 1; }
  IFS='|' read -r size quant family params repo file <<< "${model_entry[$id]}"
  echo "https://huggingface.co/$repo/resolve/main/$file"
}

# default_model_for_tier(tier) → the default model id for the tier
default_model_for_tier() {
  local tier="$1"
  [[ -n "${tier_defaults[$tier]:-}" ]] || { echo "error: unknown tier '$tier'" >&2; return 1; }
  echo "${tier_defaults[$tier]}"
}
