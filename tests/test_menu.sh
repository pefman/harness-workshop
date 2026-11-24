#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh

set +e

# --- models subcommand: exits 0 and prints 5 lines ---
tmp=$(mktemp -d)
mkdir -p "$tmp/llama.cpp/bin"
: > "$tmp/llama.cpp/bin/llama-server"
mkdir -p "$tmp/models"
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama.sh models --tier 6 2>&1) || rc=$?
assert_eq "$rc" "0" "menu_models_tier_6_exits_zero"
line_count=$(echo "$out" | wc -l)
assert_eq "$line_count" "5" "menu_models_tier_6_five_lines"
rm -rf "$tmp"

# --- launch subcommand: dry-run, tier 16 ---
tmp=$(mktemp -d)
mkdir -p "$tmp/llama.cpp/bin"
: > "$tmp/llama.cpp/bin/llama-server"
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama.sh launch --dry-run --tier 16 2>&1) || rc=$?
assert_eq "$rc" "0" "menu_launch_tier_16_exits_zero"
assert_contains "$out" "--ctx-size 16384" "menu_launch_tier_16_prints_ctx_16384"
rm -rf "$tmp"

# --- help subcommand prints help text ---
rc=0
out=$(./bin/llama.sh help 2>&1) || rc=$?
assert_eq "$rc" "0" "help_exits_zero"
assert_contains "$out" "launch" "help_prints_launch"
assert_contains "$out" "models" "help_prints_models"
assert_contains "$out" "setup" "help_prints_setup"

# --- bare run, stdin closed → non-zero, no hang ---
rc=0
out=$(./bin/llama.sh </dev/null 2>&1) || rc=$?
assert_eq "$rc" "2" "bare_run_stdin_closed_exits_2"
assert_contains "$out" "no args: run with --help or pass a subcommand" "bare_run_stdin_closed_prints_message"

# --- unknown subcommand → non-zero ---
rc=0
out=$(./bin/llama.sh frobnicate 2>&1) || rc=$?
assert_eq "$rc" "2" "unknown_subcommand_exits_2"
assert_contains "$out" "unknown" "unknown_subcommand_prints_message"

# --- flags shortcut: --models dispatches (equivalent to models) ---
tmp=$(mktemp -d)
mkdir -p "$tmp/llama.cpp/bin"
: > "$tmp/llama.cpp/bin/llama-server"
mkdir -p "$tmp/models"
rc=0
out=$(LLAMA_VENDOR="$tmp" ./bin/llama.sh --models --tier 6 2>&1) || rc=$?
assert_eq "$rc" "0" "flag_models_exits_zero"
line_count=$(echo "$out" | wc -l)
assert_eq "$line_count" "5" "flag_models_five_lines"
rm -rf "$tmp"

set -e
report_and_exit
