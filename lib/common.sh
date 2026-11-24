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

# config_lookup(tier) → absolute path to config/models.sh
config_lookup() {
  echo "$PROJECT_ROOT/config/models.sh"
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

# bin_paths() → echoes the bin/ scripts (absolute paths)
bin_paths() {
  printf '%s\n' \
    "$PROJECT_ROOT/bin/llama.sh" \
    "$PROJECT_ROOT/bin/llama-setup.sh" \
    "$PROJECT_ROOT/bin/llama-models.sh" \
    "$PROJECT_ROOT/bin/llama-launch.sh"
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
