#!/usr/bin/env bash
# bin/llama-models.sh — list tier models; download one or all.
# Usage:
#   llama-models.sh list [--tier T] [--json]
#   llama-models.sh download <id>|all [--tier T] [--force]
#   llama-models.sh (bare) → list the active tier (menu-ish, no interaction)
#
# Downloads go to vendor/models/<file>. Size-checked against the manifest
# (2dp GB, 15% tolerance — approximate, not a byte-exact pin like the binary).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/config/models.sh"

VENDOR_DIR="${LLAMA_VENDOR:-$PROJECT_ROOT/vendor}"
MODELS_DIR="$VENDOR_DIR/models"
SIZE_TOLERANCE_PCT=15   # manifest GB is 2dp/approximate — not a byte-exact pin

# --- parse args: <cmd> [positional id] [--tier T] [--json] [--force] ---
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  cmd="$1"
  shift
else
  cmd="list"
fi
positional=""
tier_override=""
vram_override=""
json_mode=0
force_download=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) tier_override="$2"; shift 2 ;;
    --vram) vram_override="$2"; shift 2 ;;
    --json) json_mode=1; shift ;;
    --force) force_download=1; shift ;;
    -h|--help)
      cat <<'HELP'
usage: llama-models.sh list [--tier T] [--vram N] [--json]
       llama-models.sh download <id>|all [--tier T] [--vram N] [--force]

list     print the models in the active tier (auto-detected by GPU)
download download one model id (or "all" = active tier) into vendor/models/
--vram N  override detected VRAM (integer GB)
--force  re-download even if the file already exists with a good size
HELP
      exit 0 ;;
    --*) echo "error: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [ -z "$positional" ]; then positional="$1"; shift;
      else echo "error: unexpected argument '$1'" >&2; exit 2; fi ;;
  esac
done

# flag wins over the environment override
[ -n "$vram_override" ] && export LLAMA_VRAM_MIB=$((vram_override * 1024))

active_tier() {
  if [ -n "$tier_override" ]; then echo "$tier_override"; return 0; fi
  local mib
  if mib=$(detect_gpu_memory_mib 2>/dev/null); then
    snap_tier "$(vram_gb_from_mib "$mib")"
    return 0
  fi
  echo "6"
  return 0
}

# print a note when falling back to tier 6 (no GPU, no --tier)
active_tier_note() {
  if [ -z "$tier_override" ] && ! detect_gpu_memory_mib >/dev/null 2>&1; then
    echo "note: no GPU detected, defaulting to tier 6" >&2
  fi
}

expected_bytes() { awk -v g="$1" 'BEGIN { printf "%d", g * 1000000000 }'; }

size_ok() { # file manifest_gb
  local file="$1" manifest_gb="$2"
  [ -f "$file" ] || return 1
  local actual expected tol diff
  actual=$(stat -c%s "$file" 2>/dev/null || echo 0)
  expected=$(expected_bytes "$manifest_gb")
  tol=$((expected * SIZE_TOLERANCE_PCT / 100))
  diff=$((actual - expected)); [ "$diff" -lt 0 ] && diff=$((-diff))
  [ "$diff" -le "$tol" ]
}

list_models() {
  local tier note
  tier=$(active_tier)
  note=$(active_tier_note)
  [[ -n "$note" ]] && echo "$note" >&2
  local ids="${tier_models[$tier]:-}"
  [[ -n "$ids" ]] || { echo "error: unknown tier '$tier'" >&2; return 2; }
  if [ "$json_mode" = "1" ]; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      IFS='|' read -r size quant family params repo file <<< "${model_entry[$id]}"
      local default="false"
      [ "$(default_model_for_tier "$tier" 2>/dev/null)" = "$id" ] && default="true"
      python3 - "$id" "$size" "$quant" "$family" "$params" "$default" "$repo" "$file" <<'PY'
import sys, json
id, size, quant, family, params, default, repo, file = sys.argv[1:]
print(json.dumps({
  "id": id, "size_gb": float(size), "family": family, "params": params,
  "quant": quant, "default": default == "true",
  "url": "https://huggingface.co/" + repo + "/resolve/main/" + file,
}))
PY
    done <<< "$ids"
  else
    list_models_for_tier "$tier"
  fi
}

download_one() { # id
  local id="$1"
  [[ -n "${model_entry[$id]:-}" ]] || { echo "error: unknown model id '$id'" >&2; return 2; }
  IFS='|' read -r size quant family params repo file <<< "${model_entry[$id]}"
  local target="$MODELS_DIR/$file"

  if [ -f "$target" ] && [ "$force_download" != "1" ]; then
    if size_ok "$target" "$size"; then
      echo "already installed ($id — $file)"
      return 0
    fi
    local actual expected
    actual=$(stat -c%s "$target" 2>/dev/null || echo 0)
    expected=$(expected_bytes "$size")
    echo "error: size mismatch — $file is ${actual} bytes, expected ~${expected} (${size} GB, ${SIZE_TOLERANCE_PCT}% tolerance). Use --force to re-download." >&2
    return 2
  fi

  require_cmd hf || return 1
  mkdir -p "$MODELS_DIR"
  echo "downloading $id (~${size} GB)..."
  rm -f "$target"
  if ! hf download "$repo" "$file" --local-dir "$MODELS_DIR"; then
    echo "error: download failed for $id ($repo/$file)" >&2
    rm -f "$target"
    return 1
  fi
  if [ ! -f "$target" ]; then
    echo "error: download did not produce $target" >&2
    return 1
  fi
  if ! size_ok "$target" "$size"; then
    local actual
    actual=$(stat -c%s "$target" 2>/dev/null || echo 0)
    echo "error: size mismatch after download — $file is ${actual} bytes, expected ~${size} GB" >&2
    return 2
  fi
  echo "installed $id ($file)"
  return 0
}

download_all() { # tier
  local tier="$1"
  local ids="${tier_models[$tier]:-}"
  [[ -n "$ids" ]] || { echo "error: unknown tier '$tier'" >&2; return 2; }
  local failed=0 count=0 id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    count=$((count+1))
    if ! download_one "$id"; then
      failed=$((failed+1))
    fi
  done <<< "$ids"
  echo "----"
  echo "$count models, $failed failed"
  [ "$failed" -gt 0 ] && return 2
  return 0
}

case "$cmd" in
  list)
    list_models ;;
  download)
    if [ -z "$positional" ]; then
      echo "usage: llama-models.sh download <id>|all [--tier T] [--force]" >&2
      exit 2
    fi
    if [ "$positional" = "all" ]; then
      local_tier=$(active_tier)
      active_tier_note
      download_all "$local_tier"
    else
      download_one "$positional"
    fi ;;
  -h|--help|help)
    cat <<'HELP'
usage: llama-models.sh list [--tier T] [--vram N] [--json]
       llama-models.sh download <id>|all [--tier T] [--vram N] [--force]

list     print the models in the active tier (auto-detected by GPU)
download download one model id (or "all" = active tier) into vendor/models/
--vram N  override detected VRAM (integer GB)
--force  re-download even if the file already exists with a good size
HELP
    exit 0 ;;
  *)
    echo "usage: llama-models.sh list [--tier T] [--json] | download <id>|all [--tier T] [--force]" >&2
    exit 2 ;;
esac
