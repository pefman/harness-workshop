#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh

set +e

# helper: tmp vendor with a stub binary + both tarballs at correct sizes
tmp_with_binary() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/llama.cpp/bin"
  : > "$tmp/llama.cpp/bin/llama-server"
  truncate -s 220261389 "$tmp/llama.cpp-bin.tar.gz"
  truncate -s 594372523 "$tmp/llama.cpp-cudart.tar.gz"
  echo "$tmp"
}

# check passes when binary exists
tmp=$(tmp_with_binary)
rc=0
out=$(LLAMA_VENDOR="$tmp" LLAMA_VRAM_MIB=24564 ./bin/llama-setup.sh --check 2>&1) || rc=$?
assert_eq "$rc" "0" "check_exits_zero_when_installed"
assert_contains "$out" "GPU found" "check_prints_gpu_found"
assert_contains "$out" "tier 16" "check_prints_tier_16"
rm -rf "$tmp"

# check exits 2 with "not installed" on empty vendor
tmp=$(mktemp -d)
rc=0
out=$(LLAMA_VENDOR="$tmp" LLAMA_VRAM_MIB=24564 ./bin/llama-setup.sh --check 2>&1) || rc=$?
assert_eq "$rc" "2" "check_exits_2_when_not_installed"
assert_contains "$out" "not installed" "check_prints_not_installed"
rm -rf "$tmp"

# check exits 2 with "size mismatch" when the tarball is wrong size
tmp=$(tmp_with_binary)
printf 'small' > "$tmp/llama.cpp-bin.tar.gz"
rc=0
out=$(LLAMA_VENDOR="$tmp" LLAMA_VRAM_MIB=24564 ./bin/llama-setup.sh --check 2>&1) || rc=$?
assert_eq "$rc" "2" "check_exits_2_on_size_mismatch"
assert_contains "$out" "size mismatch" "check_prints_size_mismatch"
rm -rf "$tmp"

# check with WSL env present is detected (synthetic: WSL_DISTRO_NAME)
tmp=$(tmp_with_binary)
rc=0
out=$(LLAMA_VENDOR="$tmp" WSL_DISTRO_NAME=WSL_TEST ./bin/llama-setup.sh --check 2>&1) || rc=$?
assert_eq "$rc" "0" "check_exits_zero_with_wsl_env"
assert_contains "$out" "WSL detected" "check_reports_wsl_detected"
rm -rf "$tmp"

# check with the GPU env forced off: reports "no GPU", still exits 0
tmp=$(tmp_with_binary)
rc=0
out=$(LLAMA_VENDOR="$tmp" LLAMA_FORCE_NO_GPU=1 ./bin/llama-setup.sh --check 2>&1) || rc=$?
assert_eq "$rc" "0" "check_exits_zero_without_gpu"
assert_contains "$out" "no GPU" "check_reports_no_gpu"
rm -rf "$tmp"

# download is idempotent: tarball already correct size → exits 0 without network
tmp=$(tmp_with_binary)
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama-setup.sh --download 2>&1) || rc=$?
assert_eq "$rc" "0" "download_exits_zero_when_tarball_matches"
assert_contains "$out" "already installed" "download_reports_already_installed"
rm -rf "$tmp"

# bad tarball + failing curl stub → old install preserved (unpack-before-swap)
tmp=$(mktemp -d)
mkdir -p "$tmp/llama.cpp/bin" "$tmp/bin"
: > "$tmp/llama.cpp/bin/llama-server"
touch "$tmp/llama.cpp/bin/marker"
printf 'small' > "$tmp/llama.cpp-bin.tar.gz"
printf 'small' > "$tmp/llama.cpp-cudart.tar.gz"
cat > "$tmp/bin/curl" <<'STUB'
#!/bin/bash
while [ $# -gt 0 ]; do
  case "$1" in
    -o) dest="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'garbage' > "$dest"
STUB
chmod +x "$tmp/bin/curl"
rc=0
out=$(PATH="$tmp/bin:$PATH" LLAMA_VENDOR="$tmp" ./bin/llama-setup.sh --download 2>&1) || rc=$?
assert_eq "$rc" "2" "download_failure_exits_2"
assert_file_exists "$tmp/llama.cpp/bin/llama-server" "download_failure_preserves_old_install"
assert_file_exists "$tmp/llama.cpp/bin/marker" "download_failure_preserves_old_tree"
rm -rf "$tmp"

# full download (network-gated): real tarball into tmp vendor
if [ "${LLAMA_TEST_NETWORK:-0}" = "1" ]; then
  tmp=$(mktemp -d)
  rc=0
  out=$(LLAMA_VENDOR="$tmp" ./bin/llama-setup.sh --download 2>&1) || rc=$?
  assert_eq "$rc" "0" "download_network_exits_zero"
  assert_file_exists "$tmp/llama.cpp/bin/llama-server" "download_network_unpacks_llama_server"
  assert_file_exists "$tmp/llama.cpp-bin.tar.gz" "download_network_keeps_bin_tarball"
  assert_file_exists "$tmp/llama.cpp-cudart.tar.gz" "download_network_keeps_cudart_tarball"
  rm -rf "$tmp"
else
  echo "skip: download_network_* (LLAMA_TEST_NETWORK unset)"
fi

set -e
report_and_exit
