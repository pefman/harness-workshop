#!/usr/bin/env bash
# bin/llama-tools.sh — start an agent harness (opencode / pi / claude)
# wired to this workshop's local llama.cpp endpoint.
#
# Usage:
#   llama-tools.sh                            → print usage + the three commands
#   llama-tools.sh <tool> [flags...] [-- harness-args]
#       <tool> = opencode | pi | claude | all
#   llama-tools.sh help                       → this help
#
# The local server is reused when it is already up on the port (e.g. started
# by bin/llama-launch.sh); otherwise one is started for the session and
# stopped when the harness exits.
#
# Flags:
#   --model id   model id from config/models.sh (default: active tier's ★ default)
#   --tier T     tier 6|8|12|16 (default: auto-detected from GPU)
#   --vram N     override detected VRAM (integer GB)
#   --host H     listen host (default: 127.0.0.1)
#   --port P     listen port (default: 8080)
#   --ctx N      context size (default: 6/8,12→16384, 16→32768)
#   --dry-run    print the resolved plan + exact commands, exit 0
# Extra args after `--` are forwarded to the harness.
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
tool=""
model_override=""
tier_override=""
vram_override=""
host="127.0.0.1"
port="8080"
ctx_override=""
dry_run=0
declare -a harness_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --model) [[ $# -ge 2 ]] || { echo "error: --model requires a value" >&2; exit 2; }; model_override="$2"; shift 2 ;;
    --tier) [[ $# -ge 2 ]] || { echo "error: --tier requires a value" >&2; exit 2; }; tier_override="$2"; shift 2 ;;
    --vram) [[ $# -ge 2 ]] || { echo "error: --vram requires a value" >&2; exit 2; }; vram_override="$2"; shift 2 ;;
    --host) [[ $# -ge 2 ]] || { echo "error: --host requires a value" >&2; exit 2; }; host="$2"; shift 2 ;;
    --port) [[ $# -ge 2 ]] || { echo "error: --port requires a value" >&2; exit 2; }; port="$2"; shift 2 ;;
    --ctx) [[ $# -ge 2 ]] || { echo "error: --ctx requires a value" >&2; exit 2; }; ctx_override="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --) shift; harness_args=("$@"); break ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)
      if [[ -z "$tool" ]]; then
        tool="$1"; shift; continue
      fi
      echo "error: unknown argument '$1' (use -- to forward args to the harness)" >&2
      exit 2 ;;
  esac
done

help_text() { sed -n '2,30p' "${BASH_SOURCE[0]}"; }

if [ -z "$tool" ]; then
  help_text
  exit 0
fi

if [ "$tool" = "help" ]; then
  help_text
  exit 0
fi

# flag wins over the environment override (same precedence as llama-launch.sh)
if [ -n "$vram_override" ]; then
  [[ "$vram_override" =~ ^[0-9]+$ ]] || { echo "error: --vram requires an integer GB value, got '$vram_override'" >&2; exit 2; }
  export LLAMA_VRAM_MIB=$((vram_override * 1024))
fi
if [ -n "$ctx_override" ]; then
  [[ "$ctx_override" =~ ^[0-9]+$ ]] || { echo "error: --ctx requires an integer value, got '$ctx_override'" >&2; exit 2; }
fi
[[ "$port" =~ ^[0-9]+$ ]] || { echo "error: --port requires an integer value, got '$port'" >&2; exit 2; }
[[ "$port" -ge 1 && "$port" -le 65535 ]] || { echo "error: --port out of range: '$port'" >&2; exit 2; }
if [ -n "$tier_override" ] && [[ ! "$tier_override" =~ ^(6|8|12|16)$ ]]; then
  echo "error: --tier must be one of 6|8|12|16, got '$tier_override'" >&2
  exit 2
fi

# --- resolve tier + model (same precedence as llama-launch.sh) ---
tier=$(active_tier "$tier_override")
if [ -n "$model_override" ]; then
  model_id="$model_override"
  [[ -n "${model_entry[$model_id]:-}" ]] || { echo "error: unknown model id '$model_id'" >&2; exit 2; }
else
  if ! detect_gpu_memory_mib >/dev/null 2>&1 && [ -z "$tier_override" ]; then
    echo "note: no GPU detected, defaulting to tier 6" >&2
  fi
  model_id=$(default_model_for_tier "$tier" 2>/dev/null) || { echo "error: unknown tier '$tier'" >&2; exit 2; }
fi

IFS='|' read -r size quant family params repo file <<< "${model_entry[$model_id]}"
model_file="$MODELS_DIR/$file"

# --- ctx (by tier; --ctx overrides) ---
ctx="$ctx_override"
if [ -z "$ctx" ]; then
  ctx=$(default_ctx_for_tier "$tier") || { echo "error: unknown tier '$tier'" >&2; exit 2; }
fi

model_name="$params $quant"
endpoint="http://$host:$port/v1"
# claude speaks the Anthropic Messages API and appends /v1/messages itself —
# its base URL must not carry the /v1 suffix.
claude_base_url="http://$host:$port"

plan_lines() {
  echo "endpoint: $endpoint"
  echo "model:    $model_id (${size} GB) · tier $tier · ctx $ctx"
  echo "server:   bin/llama-launch.sh --model $model_id --host $host --port $port --ctx $ctx"
  [ -f "$model_file" ] || echo "download:  $model_id (~${size} GB)"
}

harness_line() {
  case "$1" in
    opencode) echo "opencode:  opencode   (cwd: $PROJECT_ROOT, temp .opencode/opencode.json)" ;;
    pi) echo "pi:        PI_CODING_AGENT_DIR=<tmp> pi --provider llamacpp --model $model_id" ;;
    claude) echo "claude:    claude --settings '<env override>' --model $model_id" ;;
  esac
}

# --- tool dispatch ---
case "$tool" in
  all)
    plan_lines
    harness_line opencode
    harness_line pi
    harness_line claude
    exit 0 ;;
  opencode|pi|claude) ;;
  *)
    echo "error: unknown tool '$tool' — expected opencode|pi|claude|all" >&2
    help_text >&2
    exit 2 ;;
esac

# --- validate binary ---
server=$(ensure_vendor_llama "$BIN_DIR") || { echo "error: run llama-setup.sh first" >&2; exit 2; }

# --- dry run ---
if [ "$dry_run" = "1" ]; then
  plan_lines
  harness_line "$tool"
  if [ -n "${harness_args[*]:-}" ]; then
    echo "args:      ${harness_args[*]}"
  fi
  exit 0
fi

# --- server lifecycle ---
server_started=0
server_pid=""
log_file=""
temp_config=""
pi_tmp=""
opencode_dir_created=0
clean_up() {
  [ -n "${temp_config:-}" ] && rm -rf "$temp_config"
  if [ "$opencode_dir_created" = "1" ] && [ -d "$PROJECT_ROOT/.opencode" ] && [ -z "$(ls -A "$PROJECT_ROOT/.opencode" 2>/dev/null)" ]; then
    rmdir "$PROJECT_ROOT/.opencode" 2>/dev/null || true
  fi
  [ -n "${pi_tmp:-}" ] && rm -rf "$pi_tmp"
  if [ "$server_started" = "1" ] && [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap clean_up EXIT INT TERM

server_up() {
  curl -sf -m 2 "$endpoint/models" >/dev/null 2>&1
}

if server_up; then
  # warn if the running server is serving a different model than requested
  loaded_model=$(curl -sf -m 2 "$endpoint/models" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print((data.get('data') or [{}])[0].get('id', ''))
except Exception:
    print('')
" 2>/dev/null)
  if [ -n "$loaded_model" ]; then
    want=$(basename "$model_file")
    got=$(basename "$loaded_model" 2>/dev/null)
    if [ "$want" != "$got" ]; then
      echo "note: server on $host:$port is serving '$got' (requested '$want'); the server will use its loaded model" >&2
    fi
  fi
else
  require_cmd curl || { echo "error: curl not found" >&2; exit 1; }
  log_file=$(mktemp /tmp/llama-tools-server.XXXXXX.log)
  echo "starting llama-server on $host:$port ..." >&2
  "$PROJECT_ROOT/bin/llama-launch.sh" --model "$model_id" --host "$host" --port "$port" --ctx "$ctx" >"$log_file" 2>&1 &
  server_pid=$!
  server_started=1
  ready=0
  for i in $(seq 1 300); do
    if server_up; then ready=1; break; fi
    sleep 1
  done
  if [ "$ready" = "0" ]; then
    echo "error: llama-server did not become ready on $host:$port — log: $log_file" >&2
    tail -20 "$log_file" >&2 || true
    exit 1
  fi
fi

# --- launch the harness ---
echo "endpoint: $endpoint"
echo "model:    $model_id (${size} GB) · tier $tier · ctx $ctx"
echo "server:   $endpoint ($( [ "$server_started" = "1" ] && echo "started by this script" || echo "already running — leaving it alone" ) )"

set +e
case "$tool" in
  opencode)
    require_cmd opencode || { echo "error: opencode not found in PATH" >&2; exit 1; }
    temp_opencode_dir="$PROJECT_ROOT/.opencode"
    temp_config="$temp_opencode_dir/opencode.json"
    if [ -e "$temp_config" ]; then
      echo "error: $temp_config already exists — it would be overwritten. Remove it or wire the llamacpp provider into your config manually." >&2
      temp_config="" # keep the user's file untouched
      exit 2
    fi
    if [ ! -d "$temp_opencode_dir" ]; then
      mkdir -p "$temp_opencode_dir"
      opencode_dir_created=1
    fi
    cat > "$temp_config" <<JSON
{
  "model": "llamacpp/$model_id",
  "providers": {
    "llamacpp": {
      "name": "llama.cpp local",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "$endpoint", "apiKey": "local" },
      "models": {
        "$model_id": {
          "name": "$model_name",
          "limit": { "context": $ctx, "output": 2048 }
        }
      }
    }
  }
}
JSON
    cd "$PROJECT_ROOT"
    opencode "${harness_args[@]}"
    rc=$?
    cd - >/dev/null
    ;;
  pi)
    require_cmd pi || { echo "error: pi not found in PATH" >&2; exit 1; }
    pi_tmp=$(mktemp -d /tmp/llama-tools-pi.XXXXXX)
    cat > "$pi_tmp/models.json" <<JSON
{
  "providers": {
    "llamacpp": {
      "baseUrl": "$endpoint",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "$model_id",
          "name": "$model_name",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": $ctx,
          "maxTokens": 2048,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
JSON
    PI_CODING_AGENT_DIR="$pi_tmp" pi --provider llamacpp --model "$model_id" "${harness_args[@]}"
    rc=$?
    ;;
  claude)
    require_cmd claude || { echo "error: claude not found in PATH" >&2; exit 1; }
    settings=$(python3 -c "
import json
cfg = {'env': {
  'ANTHROPIC_BASE_URL': '$claude_base_url',
  'ANTHROPIC_API_KEY': 'local',
  'ANTHROPIC_AUTH_TOKEN': 'local',
  'ANTHROPIC_MODEL': '$model_id',
  'ANTHROPIC_DEFAULT_OPUS_MODEL': '$model_id',
  'ANTHROPIC_DEFAULT_SONNET_MODEL': '$model_id',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL': '$model_id',
  'ANTHROPIC_CUSTOM_MODEL_OPTION': '$model_id',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_NAME': '$model_name',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION': 'Local llama.cpp endpoint ($model_id)'
}}
print(json.dumps(cfg))
")
    claude --settings "$settings" --model "$model_id" "${harness_args[@]}"
    rc=$?
    ;;
esac

# the EXIT trap cleans up (temp config, temp dir, background server); let the
# harness's own exit code through
exit "$rc"
