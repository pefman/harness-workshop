#!/usr/bin/env bash
# bin/llama-setup.sh — detect WSL+GPU, download + unpack pinned llama.cpp, report.
# Usage: llama-setup.sh [--check|--download]
#   --check   report status, exit 0 healthy / 2 not installed or size mismatch
#   --download  force re-download; print "already installed" if tarballs are good
#   (no args) report status + install hint (non-blocking)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/config/llama.sh"

VENDOR_DIR="${LLAMA_VENDOR:-$PROJECT_ROOT/vendor}"
BIN_TARBALL="$VENDOR_DIR/llama.cpp-bin.tar.gz"
CUDART_TARBALL="$VENDOR_DIR/llama.cpp-cudart.tar.gz"
BIN_DIR="$VENDOR_DIR/llama.cpp/bin"
SERVER="$BIN_DIR/llama-server"

mode="--check"
vram_override=""
tier_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--download) mode="$1"; shift ;;
    --vram) vram_override="$2"; shift 2 ;;
    --tier) tier_override="$2"; shift 2 ;;
    -h|--help)
      cat <<'HELP'
usage: llama-setup.sh [--check|--download] [--vram N] [--tier T]

  --check   report status, exit 0 healthy / 2 not installed or size mismatch
  --download  force re-download; print "already installed" if tarballs are good
  --vram N  override detected VRAM (integer GB)
  --tier T  override detected tier (6|8|12|16)
HELP
      exit 0 ;;
    *) echo "usage: llama-setup.sh [--check|--download] [--vram N] [--tier T]" >&2; exit 2 ;;
  esac
done

# flag wins over the environment override
[ -n "$vram_override" ] && export LLAMA_VRAM_MIB=$((vram_override * 1024))

check_tarball_size() { # tarball expected-size-bytes
  local tarball="$1" expected="$2" actual
  [[ -f "$tarball" ]] || return 1
  actual=$(stat -c%s "$tarball" 2>/dev/null || echo 0)
  [[ "$actual" == "$expected" ]]
}

report() {
  # --- environment ---
  if [ "$(detect_wsl)" = "1" ]; then
    echo "WSL detected"
  else
    echo "WSL not detected"
  fi

  # --- GPU ---
  local gpu_line tier_gb tier_snap
  if gpu_line=$(detect_gpu_memory_mib 2>/dev/null); then
    tier_gb=$(vram_gb_from_mib "$gpu_line")
    tier_snap=$(snap_tier "$tier_gb")
    [ -n "$tier_override" ] && tier_snap="$tier_override"
    echo "GPU found (${tier_gb} GB, tier ${tier_snap})"
  else
    if [ -n "$tier_override" ]; then
      echo "no GPU (tier override: ${tier_override})"
    else
      echo "no GPU"
    fi
  fi

  # --- binary ---
  if [ -f "$SERVER" ]; then
    echo "llama.cpp ${LLAMA_CPP_BUILD_ID}: installed ($SERVER)"
  else
    echo "llama.cpp ${LLAMA_CPP_BUILD_ID}: not installed"
  fi
}

check() {
  # nothing in vendor at all → not installed
  if [ ! -f "$BIN_TARBALL" ] && [ ! -f "$CUDART_TARBALL" ] && [ ! -f "$SERVER" ]; then
    echo "error: not installed — run bin/llama-setup.sh --download" >&2
    return 2
  fi
  if [ -f "$BIN_TARBALL" ] && ! check_tarball_size "$BIN_TARBALL" "$LLAMA_CPP_BIN_SIZE_BYTES"; then
    echo "error: size mismatch (bin tarball)" >&2
    return 2
  fi
  if [ -f "$CUDART_TARBALL" ] && ! check_tarball_size "$CUDART_TARBALL" "$LLAMA_CPP_CUDART_SIZE_BYTES"; then
    echo "error: size mismatch (cudart tarball)" >&2
    return 2
  fi
  if [ ! -f "$SERVER" ]; then
    echo "error: not installed — run bin/llama-setup.sh --download" >&2
    return 2
  fi
  report
  return 0
}

download_one() { # url dest expected_size
  local url="$1" dest="$2" expected="$3"
  if check_tarball_size "$dest" "$expected"; then
    return 0
  fi
  echo "downloading $(basename "$dest") (${expected} bytes)..."
  [[ -f "$dest" ]] && rm -f "$dest"
  curl -fL --fail -sS -o "$dest" "$url" || {
    echo "error: download failed ($url)" >&2
    rm -f "$dest"
    return 1
  }
  local actual
  actual=$(stat -c%s "$dest" 2>/dev/null || echo 0)
  if [ "$actual" != "$expected" ]; then
    echo "error: size mismatch (expected ${expected} bytes, got ${actual})" >&2
    return 2
  fi
  return 0
}

download() {
  require_cmd curl || return 1
  require_cmd tar || return 1
  require_cmd find || return 1
  mkdir -p "$VENDOR_DIR"

  local bin_ok cudart_ok
  bin_ok=$(check_tarball_size "$BIN_TARBALL" "$LLAMA_CPP_BIN_SIZE_BYTES" >/dev/null 2>&1 && echo 1 || echo 0)
  cudart_ok=$(check_tarball_size "$CUDART_TARBALL" "$LLAMA_CPP_CUDART_SIZE_BYTES" >/dev/null 2>&1 && echo 1 || echo 0)

  if [ "$bin_ok" = "1" ] && [ "$cudart_ok" = "1" ] && [ -f "$SERVER" ]; then
    echo "already installed (llama.cpp ${LLAMA_CPP_BUILD_ID})"
    return 0
  fi

  download_one "$LLAMA_CPP_BIN_URL" "$BIN_TARBALL" "$LLAMA_CPP_BIN_SIZE_BYTES" || return 1
  download_one "$LLAMA_CPP_CUDART_URL" "$CUDART_TARBALL" "$LLAMA_CPP_CUDART_SIZE_BYTES" || return 1

  local tmpdir
  tmpdir=$(mktemp -d)
  rm -rf "$VENDOR_DIR/llama.cpp"
  mkdir -p "$VENDOR_DIR/llama.cpp/bin"
  tar -xzf "$BIN_TARBALL" -C "$tmpdir" || { echo "error: unpack failed (bin)" >&2; rm -rf "$tmpdir"; return 1; }
  tar -xzf "$CUDART_TARBALL" -C "$tmpdir" || { echo "error: unpack failed (cudart)" >&2; rm -rf "$tmpdir"; return 1; }
  # flatten everything into bin/ — file names (llama-*, libggml-*, libcudart.so.12, ...) are unique.
  # Preserve symlinks: the dynamic linker resolves libllama.so.1 -> libllama.so.1.0.0 etc.
  find "$tmpdir" -mindepth 2 -maxdepth 2 -type f -o -type l | while IFS= read -r f; do
    cp -a "$f" "$BIN_DIR/$(basename "$f")"
  done
  rm -rf "$tmpdir"

  if [ ! -f "$SERVER" ]; then
    echo "error: unpacked archives do not contain bin/llama-server" >&2
    return 1
  fi
  report
  echo "installed llama.cpp ${LLAMA_CPP_BUILD_ID}"
  return 0
}

case "$mode" in
  --check)
    if check; then exit 0; else exit 2; fi ;;
  --download)
    if download; then exit 0; else exit 2; fi ;;
esac
