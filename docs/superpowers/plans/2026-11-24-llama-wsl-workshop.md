# Llama on WSL with NVIDIA — Workshop Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A bash-based workshop toolkit that detects WSL/GPU/VRAM, downloads a pinned llama.cpp, lists and downloads curated GGUF models per VRAM tier (6/8/12/16 GB, 5 choices per tier), and launches `llama-server` with tier-appropriate parameters.

**Architecture:** `lib/common.sh` holds pure detection + resolution helpers (sourceable, unit-testable). `config/llama.sh` is the sourceable binary manifest for the pinned llama.cpp build (build id, URL, expected size in bytes). `config/models.sh` is the sourceable tier→models library (id, size_gb, quant, family, params, tier default). `bin/*.sh` are thin entry points that parse args (or open a menu), call into lib/config, and act. `vendor/` is gitignored, recreated from manifests. One top-level menu dispatches the task scripts.

**Tech Stack:** Bash 4+, `curl`, `nvidia-smi` (NVIDIA driver, WSL2 or native), `jq` avoided (plain bash). Tests are plain bash with a tiny assert helper, run via `tests/run_tests.sh` (no framework).

**Spec:** [docs/superpowers/specs/2026-11-24-llama-wsl-workshop-design.md](../specs/2026-11-24-llama-wsl-workshop-design.md)

## Global Constraints

- Pinned llama.cpp build: `cudart-llama-b12675-bin-ubuntu-cuda-12.8-x64.tar.gz` from `https://github.com/ggml-org/llama.cpp/releases/download/b12675/cudart-llama-b12675-bin-ubuntu-cuda-12.8-x64.tar.gz` — unpacks into `vendor/llama.cpp/bin/`.
- Pinned binary version: `b12675` (this build id, not the asset name).
- Tiers: `6`, `8`, `12`, `16` GB. `snap_tier` rounds DOWN (e.g. 24 GB → `16`).
- Per-tier default context: 6/8 → `4096`, 12 → `8192`, 16 → `16384`.
- Launcher: `llama-server` binary, `--host 127.0.0.1 --port 8080` (overridable), `--n-gpu-layers auto`, threads left to llama.cpp's default.
- VRAM detection: `nvidia-smi --query-gpu=memory.total --format=csv,noheader` → parse integer MiB → divide by 1024 → round to nearest whole GB presented as the tier.
- Every script runs with `set -euo pipefail`, checks stdout is a tty before colors, prints a one-line fallback on any failure, and never exits silently with no output.
- `vendor/` is the only writable area besides `config/`, `bin/`, `lib/`, `tests/`. **Nothing under `vendor/` is committed.**
- Auto-detect everywhere; `--vram N` / `--model <name>` / `--tier T` / `--json` flags override.
- Scripts are idempotent. Every download is size-checked against the manifest entry before use.
- "All" in `llama-models.sh download` means all models in the **active tier** (5), not all 20 across the four tiers.
- `bin/llama-launch.sh` **auto-downloads** the chosen model if missing (prints a clear `downloading <model> (~<size>)...` line, then starts the server). `--dry-run` prints the download line + exact command and exits 0 without downloading or launching.
- One config file declares the binary (`config/llama.sh`); one config file declares the model library (`config/models.sh`). No other config files.

## Review Focus

The six input/failure classes most likely to bite a workshop attendee; each line is pinned to the task that owns the code:

1. **No GPU / `nvidia-smi` missing** → setup reports "no GPU found" and continues in report-only mode rather than crashing (pinned: Task 1, test `detect_gpu_missing_handled`).
2. **VRAM below 6 GB** → snaps to tier `6`; menu shows the 6 GB library rather than crashing (Task 1, test `snap_tier_below_6g`).
3. **Partial or corrupt download** → size check re-downloads or errors clearly, never launches a half file (Task 3, test `download_size_mismatch_redownloads`).
4. **`vendor/` missing** → `llama-launch.sh` prints a clear "run llama-setup.sh first" message and exits non-zero, not an obscure `command not found` (Task 5, test `missing_vendor_errors_clearly`).
5. **Chosen model not downloaded** → launcher auto-downloads with a clear `downloading <model> (~<size>)...` line, not an obscure `No such file or directory` (Task 5, test `missing_model_auto_downloads_in_dry_run`).
6. **Native Linux vs WSL** → both report correctly; WSL-specific checks degrade gracefully on native Linux (Task 1, test `native_linux_reports_not_wsl`).

---

### Task 1: Shared library + test harness

**Files:**
- Create: `lib/common.sh`
- Create: `tests/run_tests.sh`
- Create: `tests/test_common.sh`
- Create: `tests/_assert.sh`

**Interfaces:**
- Produces (all sourced via `source "$(dirname "$0")/lib/common.sh"`):
  - `detect_wsl()` → `1` if inside WSL, `0` otherwise.
  - `detect_gpu_memory_mib()` → integer MiB from `nvidia-smi`, or `error` exits with the detection error message.
  - `snap_tier(vram_gb)` → tier string (`6`, `8`, `12`, or `16`), rounding down.
  - `vram_gb_from_mib(mib)` → float.
  - `config_lookup(tier)` → path to `config/models.sh`.
  - `ensure_vendor_llama(bin_dir)` → prints the resolved `llama-server` path or `error` with the missing-binary message.
  - `bin_paths()` → global array with `bin/llama.sh` etc.
  - `color(text, code)` → ANSI-wrapped text or plain text when not a tty.
  - `require_cmd(cmd)` → error exit if `cmd` is missing from PATH.
- Consumes: nothing (this is the root of the dependency tree).

- [ ] **Step 1: Write failing tests** in `tests/test_common.sh` covering:
  - `native_linux_reports_not_wsl` — `detect_wsl` returns 0 on native Linux (this machine — testable).
  - `snap_tier_below_6g` — `snap_tier 5` → `6`; `snap_tier 6` → `6`; `snap_tier 7` → `6`; `snap_tier 8` → `8`; `snap_tier 13` → `12`; `snap_tier 24` → `16`.
  - `vram_gb_from_mib 24564` → `24`.
  - `detect_gpu_missing_handled` — `detect_gpu_memory_mib` returns a positive integer when `LLAMA_VRAM_MIB` is set; `--check`-style callers degrade gracefully when `nvidia-smi` is missing (the function errors with a clear message, never an obscure bash error).
  - `color_not_tty_plain` — `color` prints plain text when stdout is not a tty (`LLAMA_NO_COLOR=1`).
- [ ] **Step 2: Run** `tests/run_tests.sh` — expect FAIL (`command not found: snap_tier`).
- [ ] **Step 3: Implement** `lib/common.sh` (each function in the Interfaces block above).
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: add shared library + test harness`.

### Task 2: Model library config

**Files:**
- Create: `config/models.sh`
- Create: `config/llama.sh`
- Create: `tests/test_models.sh`

**Interfaces:**
- Consumes: `snap_tier`, `config_lookup` (Task 1).
- Produces (`config/models.sh`, sourceable):
  - `tier_models[tier]` → newline-separated model ids, exactly 5 per tier.
  - `model_entry[id]` → `size_gb|quant|family|params|hf_repo|hf_file`.
  - `tier_defaults[tier]` → the default model id for each tier.
  - `list_models_for_tier(tier)` → prints 5 lines (`<id> <size> GB <family> <params> <quant>`), one per model.
  - `model_url(id)` → HF resolve URL.
  - `default_model_for_tier(tier)` → the tier's default id.
- Produces (`config/llama.sh`, sourceable):
  - `LLAMA_CPP_BUILD_ID` = `b12675`, `LLAMA_CPP_URL` = pinned tarball URL, `LLAMA_CPP_SIZE_BYTES` = expected tarball size in bytes.

- [ ] **Step 1: Write the failing test** (`test_models.sh`) asserting:
  - `list_models_for_tier 6` prints 5 lines; `list_models_for_tier 8 | wc -l` → 5; same for `12` and `16`.
  - Each tier's list includes exactly one Llama-family model (tier 16 includes exactly one Qwen).
  - `model_url` returns `https://huggingface.co/<repo>/resolve/main/<file>`.
  - `default_model_for_tier 6` → `llama-3.2-3b-q4-k-m`; tier 8 → `llama-3.1-8b-q4-k-m`; tier 12 → `llama-3.1-8b-q8-0`; tier 16 → `qwen2.5-14b-q6-k`.
  - `config/llama.sh` sets `LLAMA_CPP_BUILD_ID`, `LLAMA_CPP_URL`, `LLAMA_CPP_SIZE_BYTES` (all non-empty, size > 0).
- [ ] **Step 2: Run** tests — expect FAIL.
- [ ] **Step 3: Implement** `config/models.sh` (bash associative arrays with the exact sizes from the spec table) and `config/llama.sh` + the three helpers.
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: add curated model library config + binary manifest`.

### Task 3: `llama-setup.sh` — download and unpack

**Files:**
- Create: `bin/llama-setup.sh` (executable)
- Test: `tests/test_setup.sh`

**Interfaces:**
- Consumes: all Task 1/2 helpers, the pinned URL, the spec's pinned build id.
- Produces: `bin/llama-setup.sh` with `--check` (report status, exit 0 healthy / 2 not installed or size mismatch), `--download` (force re-download), no args (menu/interactive report). Reads the pinned release from `config/llama.sh` (`LLAMA_CPP_URL`, `LLAMA_CPP_SIZE_BYTES`, `LLAMA_CPP_BUILD_ID`).


- [ ] **Step 1: Write failing tests**:
  - `./bin/llama-setup.sh --check` exits 0 when `vendor/llama.cpp/bin/llama-server` exists.
  - `--check` prints the detected tier and "no GPU" or "GPU found" correctly (env override `LLAMA_VRAM_MIB=24564`).
  - With `vendor/` empty, `--check` exits 2 and prints "not installed" (run in a tmpdir with a fixture `LLAMA_VENDOR=$tmp`).
  - `download_size_mismatch_redownloads` — `--download` against a tmp vendor dir with a stub file at the wrong size re-downloads (or exits 2 with "size mismatch") and never reports success with a bad tarball.
- [ ] **Step 2: Run** tests — expect FAIL.
- [ ] **Step 3: Implement** the script: detect WSL + GPU, resolve pinned URL, download with `curl -L`, verify size, unpack into `vendor/llama.cpp/`, print status.
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: setup script downloads pinned llama.cpp`.

### Task 4: `llama-models.sh` — list and download

**Files:**
- Create: `bin/llama-models.sh` (executable)
- Test: `tests/test_models_script.sh`

**Interfaces:**
- Consumes: `list_models_for_tier`, `model_url` (Task 2), `vendor/` var (Task 3).
- Produces: `bin/llama-models.sh list [--tier T] [--json]` (prints 5 lines), `bin/llama-models.sh download <id>|all` (downloads to `vendor/models/<file>` with size check; `all` = all models in the **active tier**, not all 20), bare run → menu.

- [ ] **Step 1: Write failing tests**:
  - `list --tier 6 --json` outputs valid JSON-ish line 5 or 5 lines (no GPU dependency; env override `LLAMA_VENDOR=$tmp` keeps downloads isolated).
  - `download` exits non-zero and prints a clear message when vendor/models/ has the file but wrong size (run against a tmp fixture with a 0-byte file).
  - `download all --tier 6` into a tmp vendor dir downloads 5 files (guarded by `LLAMA_TEST_NETWORK=1`).
  - `download qwen2.5-0.5b-q4-k-m` into a tmpdir downloads the real file (guarded by `LLAMA_TEST_NETWORK=1`).
- [ ] **Step 2: Run** tests — expect FAIL.
- [ ] **Step 3: Implement** the script.
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: models script lists and downloads`.

### Task 5: `llama-launch.sh` — harness launcher

**Files:**
- Create: `bin/llama-launch.sh` (executable)
- Test: `tests/test_launch.sh`

**Interfaces:**
- Consumes: `list_models_for_tier`, `default_model_for_tier` (Task 2), `ensure_vendor_llama` (Task 1), `--model`/`--tier`/`--dry-run` flags.
- Produces: `bin/llama-launch.sh [--model id] [--tier T] [--dry-run] [--host H] [--port P] [--ctx N]`. When the chosen model is missing from `vendor/models/`, the launcher prints `downloading <model> (~<size>)...` (default) then starts the server. `--dry-run` prints the download line + exact resolved command line and exits 0 **without** downloading or launching. If `vendor/llama.cpp/bin/llama-server` is missing, the script exits non-zero with "run llama-setup.sh first".

- [ ] **Step 1: Write failing tests**:
  - `dry_run_prints_command` — `--dry-run --model llama-3.2-3b-q4-k-m` (with vendor present) prints a command containing `--model`, `--n-gpu-layers auto`, `--ctx 4096`, `--host 127.0.0.1 --port 8080`, `llama-server`.
  - `dry_run_tier_16_ctx_16384` — `--dry-run --tier 16 --model qwen2.5-14b-q6-k` prints `--ctx 16384`.
  - `dry_run_tier_12_ctx_8192` — `--dry-run --tier 12` prints `--ctx 8192`.
  - `missing_vendor_errors_clearly` — with no `vendor/llama.cpp/bin/llama-server`, the script exits non-zero and prints "run llama-setup.sh first".
  - `missing_model_auto_downloads_in_dry_run` — with the model missing (tmp vendor dir), `--dry-run --model llama-3.2-3b-q4-k-m` prints `downloading llama-3.2-3b-q4-k-m (~2.02 GB)...` AND the exact command line; exits 0; performs no download.
- [ ] **Step 2: Run** tests — expect FAIL.
- [ ] **Step 3: Implement** the script.
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: launcher starts llama-server with tier params`.

### Task 6: `bin/llama.sh` — top-level menu + arg dispatch

**Files:**
- Create: `bin/llama.sh` (executable)
- Test: `tests/test_menu.sh`

**Interfaces:**
- Consumes: all of Tasks 3–5 via sub-commands (`bin/llama.sh setup|models|launch`, or `bin/llama.sh --setup` etc.).
- Produces: bare run → interactive menu (Setup / Models / Launch / Help / Exit); flags → dispatch to the matching task script.

- [ ] **Step 1: Write failing tests**:
  - `bin/llama.sh models --tier 6` exits 0 and prints 5 lines (in tmp fixture).
  - `bin/llama.sh launch --dry-run --tier 16` prints `--ctx 16384`.
  - `bin/llama.sh help` prints the help text.
  - `bin/llama.sh` (no args, stdin closed) exits non-zero with "no args: run with --help or pass a subcommand" rather than hanging.
- [ ] **Step 2: Run** tests — expect FAIL.
- [ ] **Step 3: Implement** the menu (POSIX `select` or simple numbered prompts) + dispatch.
- [ ] **Step 4: Run** tests — expect PASS.
- [ ] **Step 5: Commit** `feat: top-level menu + dispatch`.

### Task 7: README + final smoke

**Files:**
- Create: `README.md`
- Modify: `.gitignore` (add `/vendor/`, `.DS_Store`, editor temp files)
- Test: manual smoke run (see Step 2)

- [ ] **Step 1: Write** README.md — what the workshop toolkit is, quick start (`bin/llama.sh`), the tiers + default models table, flags table (`--vram`, `--model`, `--tier`, `--host`, `--port`, `--ctx`, `--dry-run`), config files (`config/llama.sh` binary manifest, `config/models.sh` model library), where files live, what's NOT committed.
- [ ] **Step 2: Full smoke test:** on a GPU machine (or native Linux): `bin/llama-setup.sh --download`, then `bin/llama-launch.sh --dry-run --model llama-3.2-3b-q4-k-m`, then `bin/llama.sh` menu — expect all exit 0.
- [ ] **Step 3: Commit** `docs: README + .gitignore`.

---

## Self-Review Checklist

- [ ] Every spec section is owned by a task: intent/goals (Tasks 1–7), constraints (Task 3 pinned build), tiers + 5 models (Task 2), launcher params (Task 5), auto-detect (Tasks 1–2), vendor/gitignore (Task 7).
- [ ] No step carries more than one action; test names and assertions are exact.
- [ ] Interfaces line up across tasks (same function names, `vendor/` env var, `--dry-run`, `cells`/`model_url` signatures).
- [ ] Review Focus: each line is pinned to a test in Tasks 1–3.
- [ ] Proportion: plan ~180 lines for ~400 lines of code — reasonable.
