#!/usr/bin/env bash
# bin/llama-claude.sh — check the local llama endpoint and print the claude
# configuration that matches what it is actually serving.
#
# Usage:
#   llama-claude.sh                → print the resolved claude config
#   llama-claude.sh --run          → print the block, then launch claude
#   llama-claude.sh --help         → this help
#
# Flags:
#   --host H     listen host (default: 127.0.0.1)
#   --port P     listen port (default: 8081)
#   --run        launch claude instead of just printing
#   --           forward extra args to claude (e.g. -- -p "hello")
#
# The probe is the live endpoint (http://<host>:<port>/v1/models) — the
# actually-loaded model is the source of truth, not the tier table.
# Exit codes: 0 success, 1 runtime failure, 2 usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/config/models.sh"

host="127.0.0.1"
port="8081"
run_mode=0
harness_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --host) [[ $# -ge 2 ]] || { echo "error: --host requires a value" >&2; exit 2; }; host="$2"; shift 2 ;;
    --port) [[ $# -ge 2 ]] || { echo "error: --port requires a value" >&2; exit 2; }; port="$2"; shift 2 ;;
    --run) run_mode=1; shift ;;
    --) shift; harness_args=("$@"); break ;;
    -h|--help) sed -n '/^#!\/usr\/bin\/env bash/,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | tail -n +2 | head -n -1; exit 0 ;;
    *) echo "error: unknown argument '$1' (use -- to forward args to claude)" >&2; exit 2 ;;
  esac
done

[[ "$port" =~ ^[0-9]+$ ]] || { echo "error: --port requires an integer value, got '$port'" >&2; exit 2; }
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo "error: --port out of range: '$port'" >&2; exit 2; }

endpoint="http://$host:$port"

# --- probe the endpoint ---
if [ -n "${LLAMA_CLAUDE_FIXTURE:-}" ]; then
  if [ ! -f "$LLAMA_CLAUDE_FIXTURE" ]; then
    echo "error: fixture not found: $LLAMA_CLAUDE_FIXTURE" >&2
    exit 1
  fi
  raw=$(cat "$LLAMA_CLAUDE_FIXTURE")
else
  if ! raw=$(curl -sf -m 5 "$endpoint/v1/models" 2>/dev/null); then
    echo "error: local endpoint unreachable: $endpoint/v1/models" >&2
    echo "       (is the server running? start it with bin/llama-launch.sh)" >&2
    exit 1
  fi
fi

# --- parse what the server is actually serving ---
if ! parsed=$(python3 -c 'import json,sys
raw=sys.argv[1]
try: data=json.loads(raw)
except Exception: print("unparseable JSON"); sys.exit(1)
models=data.get("data") or data.get("models") or []
if not models: print("no models in /v1/models response"); sys.exit(1)
e=models[0] or {}
if not isinstance(e, dict): print("unexpected model entry"); sys.exit(1)
mid=e.get("id") or ""
if not isinstance(mid, str) or not mid: print("model has no id"); sys.exit(1)
meta=e.get("meta") or {}
ctx=meta.get("n_ctx")
print(mid)
print(ctx if ctx else "")' "$raw"); then
  echo "error: $parsed" >&2
  exit 1
fi
model_full=$(printf '%s\n' "$parsed" | sed -n '1p')
n_ctx=$(printf '%s\n' "$parsed" | sed -n '2p')
model_id=$(basename "$model_full")

# --- match against the config table (honest note, never a failure) ---
matched=""
for cfg_id in "${!model_entry[@]}"; do
  IFS='|' read -r _ _ _ _ _ file <<< "${model_entry[$cfg_id]}"
  if [ "$(basename "$file" | tr '[:upper:]' '[:lower:]')" = "$(basename "$model_full" | tr '[:upper:]' '[:lower:]')" ]; then
    matched="$cfg_id"
    break
  fi
done

# --- render the block ---
ctx_note=""
[ -n "$n_ctx" ] && ctx_note=" (ctx $n_ctx)"
echo "endpoint: $endpoint"
echo "claude appends /v1/messages itself — the base URL must not carry /v1"
echo "model:    $model_id$ctx_note"
if [ -n "$matched" ]; then
  echo "matches:  $matched"
else
  echo "note:     $model_id is not in config/models.sh — the server is the source of truth"
fi
echo "ANTHROPIC_BASE_URL=$endpoint"
echo "ANTHROPIC_API_KEY=local"
echo "ANTHROPIC_AUTH_TOKEN=local"
echo "ANTHROPIC_MODEL=$model_id"

settings=$(python3 -c 'import json,sys
print(json.dumps({"env":{
"ANTHROPIC_BASE_URL":sys.argv[1],
"ANTHROPIC_API_KEY":"local",
"ANTHROPIC_AUTH_TOKEN":"local",
"ANTHROPIC_MODEL":sys.argv[2],
"ANTHROPIC_DEFAULT_OPUS_MODEL":sys.argv[2],
"ANTHROPIC_DEFAULT_SONNET_MODEL":sys.argv[2],
"ANTHROPIC_DEFAULT_HAIKU_MODEL":sys.argv[2],
"ANTHROPIC_CUSTOM_MODEL_OPTION":sys.argv[2],
"ANTHROPIC_CUSTOM_MODEL_OPTION_NAME":sys.argv[2],
"ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION":"Local llama.cpp endpoint ("+sys.argv[2]+")"
}}))' "$endpoint" "$model_id")

echo "claude --settings '$settings' --model '$model_id'"

# --- launch or print ---
if [ "$run_mode" = "1" ]; then
  command -v claude >/dev/null 2>&1 || { echo "error: claude not found in PATH" >&2; exit 1; }
  set +e
  claude --settings "$settings" --model "$model_id" "${harness_args[@]}"
  rc=$?
  set -e
  exit "$rc"
fi
