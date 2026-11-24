#!/usr/bin/env bash
# lib/common.sh — shared helpers for the workshop toolkit.
# Sourced by every bin/ script. Never `exit` from inside a function; return 1.

# --- project tree ---
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_SELF_DIR/.." && pwd)"
export PROJECT_ROOT

# vendor dir — overridable for tests
VENDOR_DIR="${LLAMA_VENDOR:-$PROJECT_ROOT/vendor}"
export VENDOR_DIR

# --- core helpers ---

# detect_wsl() → prints 1 if inside WSL, 0 otherwise (stdout)
detect_wsl() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo 1
    return 0
  fi
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]]; then
    echo 1
    return 0
  fi
  echo 0
  return 0
}

# detect_gpu_memory_mib() → prints integer MiB; errors (returns 1) with a
# message on stderr when nvidia-smi is unavailable or silent.
detect_gpu_memory_mib() {
  if [[ -n "${LLAMA_VRAM_MIB:-}" ]]; then
    echo "$LLAMA_VRAM_MIB"
    return 0
  fi
  # test hook: skip the real query, report "missing" as if nvidia-smi were absent
  if [[ -n "${LLAMA_FORCE_NO_GPU:-}" ]]; then
    echo "error: nvidia-smi not found" >&2
    return 1
  fi
  require_cmd nvidia-smi || return 1
  local raw
  if ! raw=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1); then
    echo "error: nvidia-smi failed to report memory" >&2
    return 1
  fi
  raw=${raw//[^0-9]/}
  if [[ -z "$raw" ]]; then
    echo "error: nvidia-smi returned no memory figure" >&2
    return 1
  fi
  echo "$raw"
  return 0
}

# snap_tier(vram_gb) → tier string (6|8|12|16), rounds DOWN, floors at 6
snap_tier() {
  local gb="$1"
  awk -v v="$gb" 'BEGIN {
    if (v < 6) { print "6"; exit }
    if (v >= 16) { print "16"; exit }
    if (v >= 12) { print "12"; exit }
    if (v >= 8) { print "8"; exit }
    print "6"
  }'
}

# vram_gb_from_mib(mib) → whole GB, rounded (24 GB = 24564 MiB)
vram_gb_from_mib() {
  local mib="$1"
  awk -v m="$mib" 'BEGIN { print int(m/1024 + 0.5) }'
}

# active_tier(override) → tier string (6|8|12|16). Uses the override when given,
# otherwise the auto-detected tier; falls back to 6 when no GPU is detectable.
active_tier() {
  local override="${1:-}"
  if [[ -n "$override" ]]; then
    echo "$override"
    return 0
  fi
  local mib
  if mib=$(detect_gpu_memory_mib 2>/dev/null); then
    snap_tier "$(vram_gb_from_mib "$mib")"
    return 0
  fi
  echo "6"
  return 0
}

# default_ctx_for_tier(tier) → prints the per-tier default context size
# (6/8→16384, 12→16384, 16→32768); returns 1 and prints nothing for an unknown tier.
default_ctx_for_tier() {
  case "${1:-}" in
    6|8|12) echo 16384 ;;
    16) echo 32768 ;;
    *) return 1 ;;
  esac
}

# ensure_vendor_llama(bin_dir) → prints resolved llama-server path, else
# prints a clear error to stderr and returns 1.
ensure_vendor_llama() {
  local bin_dir="$1"
  if [[ -f "$bin_dir/llama-server" ]]; then
    echo "$bin_dir/llama-server"
    return 0
  fi
  echo "error: llama.cpp not found at $bin_dir/llama-server (run llama-setup.sh first)" >&2
  return 1
}

# expected_bytes(gb) → expected file size in bytes. Manifests (config/models.sh)
# carry GiB-derived sizes (measured bytes / 1024^3, 2dp), so convert with 1024^3.
expected_bytes() {
  awk -v g="$1" 'BEGIN { printf "%d", g * 1073741824 }'
}

# size_ok(file, manifest_gb, tolerance_pct) → exits 0 when the file exists and is
# within tolerance_pct% of the expected size (default 15%). Returns 1 otherwise.
size_ok() {
  local file="$1" manifest_gb="$2" tolerance="${3:-15}"
  [[ -f "$file" ]] || return 1
  local actual expected tol diff
  actual=$(stat -c%s "$file" 2>/dev/null || echo 0)
  expected=$(expected_bytes "$manifest_gb")
  tol=$((expected * tolerance / 100))
  diff=$((actual - expected)); [ "$diff" -lt 0 ] && diff=$((-diff))
  [[ "$diff" -le "$tol" ]]
}

# color(text, code) → ANSI-wrapped text, plain when not a tty or LLAMA_NO_COLOR
color() {
  local text="$1" code="$2"
  if [[ -n "${LLAMA_NO_COLOR:-}" ]]; then
    echo "$text"
    return 0
  fi
  if ! [ -t 1 ]; then
    echo "$text"
    return 0
  fi
  printf '\033[%sm%s\033[0m' "$code" "$text"
}

# require_cmd(cmd) → error message + return 1 if cmd missing from PATH
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' not found in PATH" >&2
    return 1
  fi
  return 0
}
