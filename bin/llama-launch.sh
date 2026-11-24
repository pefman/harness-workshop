#!/usr/bin/env bash
# bin/llama-launch.sh — start llama-server with the tier-appropriate parameters.
# Usage:
#   llama-launch.sh [--model id] [--tier T] [--vram N] [--host H] [--port P] [--ctx N] [--dry-run]
#
#   --model      model id from config/models.sh (default: tier's ★ default)
#   --tier       tier 6|8|12|16 (default: auto-detected from GPU)
#   --host       listen host (default: 127.0.0.1)
#   --port       listen port (default: 8080)
#   --ctx        context size (default: by tier — 6/8,12→16384, 16→32768)
#   --vram N     override detected VRAM (integer GB)
#   --dry-run    print the download line + exact resolved command, exit 0
#                without downloading or launching
#
# Missing model → prints "downloading <model> (~<size>)..." then downloads it
# on launch (no menu step needed). Missing llama-server → exit 2 with hint.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/config/models.sh"

VENDOR_DIR="${LLAMA_VENDOR:-$PROJECT_ROOT/vendor}"
BIN_DIR="$VENDOR_DIR/llama.cpp/bin"
MODELS_DIR="$VENDOR_DIR/models"

# --- args ---
model_override=""
tier_override=""
vram_override=""
host="127.0.0.1"
port="8080"
ctx_override=""
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      [[ $# -ge 2 ]] || { echo "error: --model requires a value" >&2; exit 2; }
      model_override="$2"; shift 2 ;;
    --tier)
      [[ $# -ge 2 ]] || { echo "error: --tier requires a value" >&2; exit 2; }
      tier_override="$2"; shift 2 ;;
    --vram)
      [[ $# -ge 2 ]] || { echo "error: --vram requires a value" >&2; exit 2; }
      vram_override="$2"; shift 2 ;;
    --host)
      [[ $# -ge 2 ]] || { echo "error: --host requires a value" >&2; exit 2; }
      host="$2"; shift 2 ;;
    --port)
      [[ $# -ge 2 ]] || { echo "error: --port requires a value" >&2; exit 2; }
      port="$2"; shift 2 ;;
    --ctx)
      [[ $# -ge 2 ]] || { echo "error: --ctx requires a value" >&2; exit 2; }
      ctx_override="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'HELP'
usage: llama-launch.sh [--model id] [--tier T] [--vram N] [--host H] [--port P] [--ctx N] [--dry-run]

  --model      model id from config/models.sh (default: tier's default)
  --tier       tier 6|8|12|16 (default: auto-detected from GPU)
  --vram N     override detected VRAM (integer GB)
  --host       listen host (default: 127.0.0.1)
  --port       listen port (default: 8080)
  --ctx        context size (default: by tier — 6/8,12→16384, 16→32768)
  --dry-run    print the download line + exact resolved command, exit 0
               without downloading or launching
HELP
      exit 0 ;;
    *) echo "error: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

# flag wins over the environment override
if [ -n "$vram_override" ]; then
  [[ "$vram_override" =~ ^[0-9]+$ ]] || { echo "error: --vram requires an integer GB value, got '$vram_override'" >&2; exit 2; }
  export LLAMA_VRAM_MIB=$((vram_override * 1024))
fi
if [ -n "$ctx_override" ]; then
  [[ "$ctx_override" =~ ^[0-9]+$ ]] || { echo "error: --ctx requires an integer value, got '$ctx_override'" >&2; exit 2; }
fi

# --- resolve tier + model ---
tier=$(active_tier "$tier_override")
[ -z "$tier_override" ] && ! detect_gpu_memory_mib >/dev/null 2>&1 && \
  echo "note: no GPU detected, defaulting to tier 6" >&2

if [ -n "$model_override" ]; then
  model_id="$model_override"
  [[ -n "${model_entry[$model_id]:-}" ]] || { echo "error: unknown model id '$model_id'" >&2; exit 2; }
else
  model_id=$(default_model_for_tier "$tier" 2>/dev/null) || { echo "error: unknown tier '$tier'" >&2; exit 2; }
fi

IFS='|' read -r size quant family params repo file <<< "${model_entry[$model_id]}"
model_file="$MODELS_DIR/$file"

# --- ctx by tier ---
ctx="$ctx_override"
if [ -z "$ctx" ]; then
  ctx=$(default_ctx_for_tier "$tier") || { echo "error: unknown tier '$tier'" >&2; exit 2; }
fi

# --- binary must exist ---
server=$(ensure_vendor_llama "$BIN_DIR") || { echo "error: run llama-setup.sh first" >&2; exit 2; }

# --- exact command line ---
cmd_line="LD_LIBRARY_PATH=$BIN_DIR $server --model $model_file --n-gpu-layers auto --ctx-size $ctx --host $host --port $port"

missing_model=0
[ -f "$model_file" ] || missing_model=1

if [ "$dry_run" = "1" ]; then
  if [ "$missing_model" = "1" ]; then
    echo "downloading $model_id (~${size} GB)..."
    echo "$cmd_line"
    exit 0
  fi
  if ! size_ok "$model_file" "$size"; then
    actual=$(stat -c%s "$model_file" 2>/dev/null || echo 0)
    echo "error: size mismatch — $file is ${actual} bytes, expected ~${size} GB. Use bin/llama-models.sh download $model_id --force to re-download." >&2
    exit 2
  fi
  echo "$cmd_line"
  exit 0
fi

# --- model present-but-wrong-size → refuse to launch (same check as the models script) ---
if [ "$missing_model" = "0" ] && ! size_ok "$model_file" "$size"; then
  actual=$(stat -c%s "$model_file" 2>/dev/null || echo 0)
  echo "error: size mismatch — $file is ${actual} bytes, expected ~${size} GB. Use bin/llama-models.sh download $model_id --force to re-download." >&2
  exit 2
fi

if [ "$missing_model" = "1" ]; then
  echo "downloading $model_id (~${size} GB)..."
  require_cmd hf || exit 1
  mkdir -p "$MODELS_DIR"
  if ! hf download "$repo" "$file" --local-dir "$MODELS_DIR"; then
    echo "error: download failed for $model_id ($repo/$file)" >&2
    exit 1
  fi
  if [ ! -f "$model_file" ]; then
    echo "error: download did not produce $model_file" >&2
    exit 1
  fi
  if ! size_ok "$model_file" "$size"; then
    actual=$(stat -c%s "$model_file" 2>/dev/null || echo 0)
    echo "error: size mismatch after download — $file is ${actual} bytes, expected ~${size} GB" >&2
    exit 2
  fi
fi

# --- launch ---
echo "server: http://$host:$port/"
echo "curl:  curl http://$host:$port/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}]}'"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$server" --model "$model_file" --n-gpu-layers auto --ctx-size "$ctx" --host "$host" --port "$port"
