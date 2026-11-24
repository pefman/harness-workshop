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
assert_contains "$out" "--ctx-size 32768" "menu_launch_tier_16_prints_ctx_32768"
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

# --- menu: Models branch lists the tier + downloads the picked model (pty) ---
tmp=$(mktemp -d)
mkdir -p "$tmp/llama.cpp/bin" "$tmp/models"
: > "$tmp/llama.cpp/bin/llama-server"
size=$(awk 'BEGIN { printf "%d", 7.17 * 1073741824 }')
truncate -s "$size" "$tmp/models/Mistral-7B-Instruct-v0.3-Q8_0.gguf"
out=$(LLAMA_VENDOR="$tmp" LLAMA_VRAM_MIB=24564 LLAMA_NO_COLOR=1 python3 - <<'PY'
import pty, os, sys, time, select
output = b""
def drain(timeout):
    global output
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.4)
        if r:
            try: chunk = os.read(fd, 4096)
            except OSError: return
            if not chunk: return
            output += chunk
        else:
            return
pid, fd = pty.fork()
if pid == 0:
    os.execv("bin/llama.sh", ["bin/llama.sh"])
drain(6)
os.write(fd, b"2\n"); drain(3)
os.write(fd, b"1\n"); drain(8)
os.write(fd, b"\n"); drain(3)
os.write(fd, b"5\n"); drain(6)
status = None
for _ in range(50):
    wpid, st = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        status = st
        break
    time.sleep(0.1)
code = os.waitstatus_to_exitcode(status) if status is not None else -1
sys.stdout.write(output.decode(errors="replace"))
sys.stdout.write("\nEXIT_STATUS=%d" % code)
PY
)
printf '%s\n' "$out"
assert_contains "$out" "models in tier 16" "menu_models_branch_lists_models"
assert_contains "$out" "already installed (mistral-7b-q8-0" "menu_models_branch_downloads_picked_model"
assert_contains "$out" "EXIT_STATUS=0" "menu_models_branch_exits_zero"
rm -rf "$tmp"

set -e
report_and_exit
