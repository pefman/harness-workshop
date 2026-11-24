# llama-claude.sh — endpoint-aware claude check

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A small script that probes the local llama.cpp endpoint and prints the exact claude configuration that matches what the endpoint is actually serving (not the tier default) — env block + the exact `claude --settings ... --model` invocation — launching claude with it when given `--run`.

**Architecture:** One new bash script `bin/llama-claude.sh`. It curls `http://<host>:<port>/v1/models`, parses the first loaded model with `python3`, derives the base URL (no `/v1`, because claude appends `/v1/messages` itself) plus session env vars, matches the basename against `config/models.sh` for an honest "matches config" line, and prints the block. It never starts the server and never writes to user configs; session-only `--settings` env wins over the global gateway settings.

**Tech Stack:** bash 5+, python3 (JSON), curl (probe). No new dependencies — same toolchain as the rest of the toolkit.

**Spec:** Approved short design — "bin/llama-claude.sh — check the local endpoint, choose the correct claude config" (session of 2026-11-24; approach A, print-by-default with `--run` to launch, no extra flags, live server as source of truth). No formal spec doc: small change per the brainstorming gate.

## Global Constraints

- bash 5+, `set -euo pipefail`; plain (non-color) output — tests assert exact strings.
- Exit codes: `0` success (print or launch OK with claude); `1` runtime failure (unreachable endpoint, unparseable response, missing model id); `2` usage/bad flags. Matches the repo's existing contract (`llama-launch.sh`, `llama-tools.sh`).
- Base URL printed must never carry `/v1` — claude appends `/v1/messages`.
- claude config is passed as a session `--settings` env override — global `~/.claude/settings.json` `env` wins over shell env.
- Tests under `tests/test_*.sh`, run via `tests/run_tests.sh`; network-dependent assertions skip (not fail) when the server is not up.

## Review Focus

The input classes the approved design implies but no task's tests exercise yet:

1. **Endpoint unreachable** (server down / wrong port) → exit 1, error names the URL.
2. **Response body unparseable or missing a model id** → exit 1, not a crash.
3. **Live id matches a `config/models.sh` entry** → `matches:` line with the exact config id.
4. **Live id unmatched** → still prints, marked unmatched (server is the source of truth).
5. **`--run` launches claude with passthrough args after `--` and propagates claude's exit code** → stub-`claude` test asserts the exact argv and the exit code (0 path and non-zero path).
6. **Base URL never carries `/v1`** → exact-string assertion in tests.

---

### Task 1: `bin/llama-claude.sh` + `tests/test_claude.sh`

**Files:**
- Create: `bin/llama-claude.sh`
- Create: `tests/test_claude.sh`

**Interfaces:**
- Consumes: `config/models.sh` (`model_entry[<id>]`, file column of each entry — basename match only); `tests/_assert.sh` (`assert_eq`, `assert_contains`, `report_and_exit`).
- Produces: script contract —
  - Flags: `--host <h>` (default `127.0.0.1`), `--port <p>` (default `8081`), `--run` (launch claude instead of print), `--` (extra args forwarded to claude), `-h|--help`. Unknown flag → exit 2 with usage.
  - Env seam for offline tests: `LLAMA_CLAUDE_FIXTURE=<path>` — reads the fixture JSON instead of curling. (Same pattern as `LLAMA_VENDOR` in the vendor scripts.)
  - Output (print mode): the endpoint line, the model line (basename + ctx when present, `matches:`/`note:` line), the env block (`ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY=local`, `ANTHROPIC_AUTH_TOKEN=local`, `ANTHROPIC_MODEL=<basename>`), and the exact `claude --settings '<json>' --model '<basename>'` command.
  - `--run`: prints the same block, then `claude --settings '<json>' --model '<basename>' <args...>`; exit code = claude's exit code. claude is found via `require_cmd`-style check, error to stderr, exit 1.
- [ ] **Step 1: Write `tests/test_claude.sh`** (failing) — helper fixtures:
  - `--help` → exit 0, usage line present.
  - unknown flag (`--bogus`) → exit 2.
  - unreachable: `--port 59999` (no fixture) → exit 1, stderr/stdout contains the URL `http://127.0.0.1:59999`.
  - fixture match case: temp fixture with `data[0].id = ".../Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"`, `meta.n_ctx = 16384` → exit 0; output contains `ANTHROPIC_BASE_URL=http://127.0.0.1:8081`; does NOT contain `/v1` in its base URL line; contains `ANTHROPIC_MODEL=Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`; contains `matches:` with `qwen2.5-0.5b-q4-k-m`; contains `16384`.
  - fixture unmatched case: basename `unmatched-model.gguf` → exit 0; contains `note:` and `unmatched-model.gguf`.
  - fixture garbage (not JSON / missing id) → exit 1.
  - `--run` argv: stub `claude` in PATH (tmp dir) that echoes `CLAUDE_ARGV:$*` → `--run -- -p hi` → exit 0, output contains `CLAUDE_ARGV:--settings` and the model id; stub that exits 3 → `--run` → rc 3.
  - live case (skip, not fail, when the server is not up): default port 8081, no fixture → exit 0, output contains the `http://` endpoint line and no `/v1` in the base-URL line.
- [ ] **Step 2: Run `tests/test_claude.sh` — all fail (script does not exist).**
- [ ] **Step 3: Implement `bin/llama-claude.sh`** — probe (`curl -sf -m 2`, or fixture), `python3` parse (`data[0]`, `.id`, `.meta.n_ctx`), basename, basename-match against every `model_entry` (case-insensitive), print block, `--run` launch with session env (same structure as `llama-tools.sh`'s claude branch — env keys: `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_CUSTOM_MODEL_OPTION`, `ANTHROPIC_CUSTOM_MODEL_OPTION_NAME`, `ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION`).
- [ ] **Step 4: Run `tests/test_claude.sh` — all pass.**

### Task 2: Full suite + commit

- [ ] **Step 1: Run `bash tests/run_tests.sh`** — all test files green.
- [ ] **Step 2: Live smoke** — run `./bin/llama-claude.sh` against the running server on 8081 (and `--run -- -p "say hi"` if the server is up); confirm correct config lines.
- [ ] **Step 3: Commit** — `feat: add bin/llama-claude.sh — endpoint-aware claude config check` (only `bin/llama-claude.sh`, `tests/test_claude.sh`; do not commit the untracked `bin/llama-tools.sh` — it is a separate workstream).
