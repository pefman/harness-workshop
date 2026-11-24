#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source tests/_assert.sh

set +e

SCRIPT=./bin/llama-claude.sh

# --- --help: exits 0, shows usage ---
out=$("$SCRIPT" --help 2>&1)
rc=$?
assert_eq "$rc" "0" "help_exits_zero"
assert_contains "$out" "llama-claude.sh" "help_shows_usage"

# --- unknown flag: exit 2 ---
out=$("$SCRIPT" --bogus 2>&1)
rc=$?
assert_eq "$rc" "2" "unknown_flag_exits_2"

# --- unreachable endpoint (dead port, no fixture): exit 1, names the URL ---
out=$("$SCRIPT" --port 59999 2>&1)
rc=$?
assert_eq "$rc" "1" "unreachable_exits_1"
assert_contains "$out" "http://127.0.0.1:59999" "unreachable_names_url"

# --- fixture: match case ---
tmp=$(mktemp -d)
cat > "$tmp/fixture.json" <<'JSON'
{"object":"list","data":[{"id":"/home/pefman/git/workshop/vendor/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf","meta":{"n_ctx":16384}}]}
JSON
out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture.json" "$SCRIPT" 2>&1)
rc=$?
assert_eq "$rc" "0" "fixture_match_exits_0"
assert_contains "$out" "ANTHROPIC_BASE_URL=http://127.0.0.1:8080" "fixture_prints_base_url"
line=$(grep -E '^ANTHROPIC_BASE_URL=' <<<"$out")
assert_eq "$line" "ANTHROPIC_BASE_URL=http://127.0.0.1:8080" "base_url_has_no_v1"
assert_contains "$out" "ANTHROPIC_MODEL=Qwen2.5-0.5B-Instruct-Q4_K_M.gguf" "fixture_prints_model_id"
assert_contains "$out" "matches:  qwen2.5-0.5b-q4-k-m" "fixture_matches_config_entry"
assert_contains "$out" "16384" "fixture_prints_ctx"
assert_contains "$out" "claude --settings" "fixture_prints_exact_command"

# --- fixture: unmatched case ---
cat > "$tmp/fixture2.json" <<'JSON'
{"object":"list","data":[{"id":"/tmp/models/some-outside-model.gguf","meta":{"n_ctx":8192}}]}
JSON
out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture2.json" "$SCRIPT" 2>&1)
rc=$?
assert_eq "$rc" "0" "fixture_unmatched_exits_0"
assert_contains "$out" "note:" "fixture_unmatched_shows_note"
assert_contains "$out" "some-outside-model.gguf" "fixture_unmatched_shows_basename"

# --- fixture: garbage / missing id / missing file ---
printf 'not json' > "$tmp/fixture3.json"
out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture3.json" "$SCRIPT" 2>&1)
rc=$?
assert_eq "$rc" "1" "fixture_garbage_exits_1"

printf '{"object":"list","data":[{}]}' > "$tmp/fixture4.json"
out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture4.json" "$SCRIPT" 2>&1)
rc=$?
assert_eq "$rc" "1" "fixture_missing_id_exits_1"

out=$(LLAMA_CLAUDE_FIXTURE="$tmp/does-not-exist.json" "$SCRIPT" 2>&1)
rc=$?
assert_eq "$rc" "1" "missing_fixture_exits_1"

# --- --run: stub claude in PATH; argv + exit-code propagation ---
stubbin="$tmp/bin"
mkdir -p "$stubbin"
cat > "$stubbin/claude" <<'EOF'
#!/usr/bin/env bash
echo "CLAUDE_ARGV:[$*]"
exit "${STUB_RC:-0}"
EOF
chmod +x "$stubbin/claude"

out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture.json" PATH="$stubbin:$PATH" "$SCRIPT" --run -- -p hi 2>&1)
rc=$?
assert_eq "$rc" "0" "run_stub_exits_0"
assert_contains "$out" "CLAUDE_ARGV:[--settings" "run_passes_settings"
assert_contains "$out" "--model" "run_passes_model"
assert_contains "$out" "-p hi" "run_passes_args_after_double_dash"

out=$(LLAMA_CLAUDE_FIXTURE="$tmp/fixture.json" PATH="$stubbin:$PATH" STUB_RC=3 "$SCRIPT" --run 2>&1)
rc=$?
assert_eq "$rc" "3" "run_propagates_claude_exit_code"

rm -rf "$tmp"

# --- live case: skip, not fail, when the server is not up ---
if curl -sf -m 2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
  out=$("$SCRIPT" 2>&1)
  rc=$?
  assert_eq "$rc" "0" "live_prints_config"
  assert_contains "$out" "ANTHROPIC_BASE_URL=http://127.0.0.1:8080" "live_prints_base_url"
  line=$(grep -E '^ANTHROPIC_BASE_URL=' <<<"$out")
  assert_eq "$line" "ANTHROPIC_BASE_URL=http://127.0.0.1:8080" "live_base_url_has_no_v1"
else
  echo "SKIP: live case (server not up on 127.0.0.1:8080)"
fi

set -e
report_and_exit
