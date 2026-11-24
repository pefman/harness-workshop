# llama.cpp workshop

A bash-based toolkit for setting up and testing llama.cpp-based Llama models on
WSL/Linux with NVIDIA GPUs — built for workshop attendees on machines with
6–16 GB of VRAM.

**Runtime:** llama.cpp (pinned build `b12675`, CUDA 12.8, bundled runtime).
**Not Ollama.** Models are pulled directly from Hugging Face (bartowski's GGUF repos).
**No model weights or binaries are committed to git** — they download on first run.

---

## Quick start

```bash
bin/llama.sh                      # bare run → interactive menu (Setup/Models/Launch/Help/Exit)
```

Or use the scripts directly:

```bash
bin/llama-setup.sh --download     # detect WSL/GPU, download + unpack llama.cpp (~815 MB total)
bin/llama-models.sh list          # list the models in your tier
bin/llama-launch.sh               # download (if missing) + start llama-server
```

On a GPU machine, auto-detect kicks in: `nvidia-smi` reports your VRAM, the tier is
snapped down to the closest supported tier (6/8/12/16 GB), and the menu shows your
tier + the default model with a fit line.

**Requirements** (checked by the scripts, with clear errors if missing):

| Tool | Needed for |
|------|-----------|
| `nvidia-smi` | GPU detection (optional — scripts fall back to tier 6 with a note) |
| `hf` (huggingface-cli) | model downloads (required for `models`/`launch` when a model is missing) |
| `curl`, `tar`, `find` | `setup` (pinned binary download) |
| `python3` | JSON output (`list --json`) |

---

## Tiers and defaults

VRAM (MiB) is snapped DOWN to the closest tier — a 24 GB card maps to tier 16.
Defaults are Llama-first, except tier 16 which showcases a bigger-class Qwen.

| Tier | VRAM | Default model | Size |
|------|------|---------------|------|
| 6    | 6 GB | `llama-3.2-3b-q4-k-m` ★ | 2.02 GB |
| 8    | 8 GB | `llama-3.1-8b-q4-k-m` ★ | 4.58 GB |
| 12   | 12 GB | `llama-3.1-8b-q8-0` ★ | 7.95 GB |
| 16   | 16 GB | `qwen2.5-14b-q6-k` ★ | 11.29 GB |

Each tier has 5 choices. The model list shows the current tier and a fit line
(size + ~2 GB context vs the tier limit). VRAM needed ≈ model size + 2 GB.

Model sizes and repos live in `config/models.sh` (id, size_gb, quant, family,
params, hf_repo, hf_file, tier_default — measured, bartowski repos).

---

## Scripts

| Script | What it does |
|--------|--------------|
| `bin/llama.sh` | Top-level menu + arg dispatch. Bare run → menu; `--help` prints help |
| `bin/llama-setup.sh` | Detect WSL + GPU, download + unpack the pinned llama.cpp, report status |
| `bin/llama-models.sh` | `list` tier models (plain or `--json`), `download <id>`/`all` |
| `bin/llama-launch.sh` | Start `llama-server` with the tier-appropriate parameters |

### `bin/llama.sh`

```bash
bin/llama.sh                     # interactive menu
bin/llama.sh help                # show help
bin/llama.sh setup               # → bin/llama-setup.sh
bin/llama.sh models list --tier 6
bin/llama.sh models download all
bin/llama.sh launch --dry-run --tier 16
```

The menu loops back after each action. Launch starts the server in the foreground
(Ctrl-C to stop). Use `--dry-run` for the exact resolved command.

The **Models** branch lists the active tier's models (size, family, ★ default),
then prompts you to download one:

```text
models in tier 16 — pick one to download
  1) mistral-7b-q8-0    7.17 GB  mistral 7B
  2) llama-3.1-8b-q8-0  7.95 GB  llama 8B
  ...
  5) qwen2.5-14b-q6-k  11.29 GB  qwen 14B ★

download [1-5] / all / back: 2
```

`1`–`5` downloads that model, `all` downloads the whole tier, `back` returns
to the menu without downloading. Downloads run the same idempotent, size-checked
path as `bin/llama-models.sh download`.

### `bin/llama-setup.sh`

```bash
bin/llama-setup.sh --check       # report status; exit 0 healthy / 2 missing or size mismatch
bin/llama-setup.sh --download    # force re-download; reports "already installed" if tarballs are good
bin/llama-setup.sh --check --vram 8
```

Downloads into `vendor/`:

- `vendor/llama.cpp-bin.tar.gz` — llama.cpp executables + ggml libs (~220 MB)
- `vendor/llama.cpp-cudart.tar.gz` — CUDA runtime (~567 MB)
- `vendor/llama.cpp/bin/` — flattened binaries + libraries (symlinks preserved)

Both assets are pinned in `config/llama.sh` (`LLAMA_CPP_BUILD_ID=b12675`, exact URLs,
exact byte sizes, verified on download).

### `bin/llama-models.sh`

```bash
bin/llama-models.sh list                    # active tier
bin/llama-models.sh list --tier 6
bin/llama-models.sh list --tier 6 --json    # one JSON object per line
bin/llama-models.sh download qwen2.5-0.5b-q4-k-m
bin/llama-models.sh download all            # all 5 models in the active tier
bin/llama-models.sh download all --tier 6 --force
```

Downloads go to `vendor/models/<hf_file>`, size-checked against the manifest
(~15% tolerance — manifest sizes are measured bytes / 1024^3, 2dp, approximate). An existing file with a
bad size exits non-zero with a "size mismatch" message; `--force` re-downloads.
`download all` covers the active tier only (5 models), not all 20.

### `bin/llama-launch.sh`

```bash
bin/llama-launch.sh                          # active tier + default model
bin/llama-launch.sh --model llama-3.2-3b-q4-k-m
bin/llama-launch.sh --tier 16 --model qwen2.5-14b-q6-k
bin/llama-launch.sh --dry-run --ctx 32768
bin/llama-launch.sh --host 0.0.0.0 --port 8080
```

Parameters (per spec):

- `--model vendor/models/<file>.gguf`
- `--n-gpu-layers auto`
- `--ctx-size` by tier: 6/8 GB → 16384, 12 GB → 16384, 16 GB → 32768 (`--ctx` overrides)
- `--host 127.0.0.1 --port 8080` (overridable via `--host`/`--port`)
- threads left to llama.cpp's own default (no invented number)
- prints the endpoint + a sample `curl` line on start

Missing model → prints `downloading <model> (~<size>)...` then downloads it
(no menu step needed). Missing llama-server → exits 2 with "run llama-setup.sh first".
`--dry-run` prints the download line + the exact resolved command and exits 0
without downloading or launching.

---

## Flags (all scripts)

| Flag | What it does |
|------|--------------|
| `--vram N` | Override detected VRAM (integer GB). Wins over env/auto-detect |
| `--tier T` | Override detected tier (6/8/12/16). Wins over `--vram` |
| `--model <id>` | Model id (launcher/models). Default: tier's ★ default |
| `--host H` | Listen host (launcher). Default 127.0.0.1 |
| `--port P` | Listen port (launcher). Default 8080 |
| `--ctx N` | Context size (launcher). Default: by tier |
| `--dry-run` | Print the resolved command, exit 0 (launcher) |
| `--json` | JSON output, one object per line (models list) |
| `--force` | Re-download even if the file is present and good (models) |
| `--check` / `--download` | Setup: report status / force re-download |

Environment overrides (used by tests, and handy by hand):

| Var | Effect |
|-----|--------|
| `LLAMA_VRAM_MIB` | Override GPU memory (MiB) |
| `LLAMA_VENDOR` | Override vendor dir (for hermetic runs) |
| `LLAMA_FORCE_NO_GPU=1` | Report "no GPU" (test hook) |
| `LLAMA_NO_COLOR=1` | Plain output (no ANSI colors) |
| `LLAMA_TEST_NETWORK=1` | Enable network-gated tests (`tests/run_tests.sh`) |
| `LLAMA_TEST_NETWORK_ALL=1` | Also download all tier-6 models in tests (~6.7 GB) |

---

## Where files live / what's committed

| Path | Status |
|------|--------|
| `bin/`, `config/`, `lib/`, `tests/` | committed — the toolkit |
| `docs/` | committed — design + plan |
| `vendor/` | **gitignored** — binaries + downloaded models |
| `vendor/llama.cpp-*.tar.gz` | pinned tarballs (verified by size) |
| `vendor/llama.cpp/bin/` | flattened binaries + libs |
| `vendor/models/` | downloaded GGUF models |

Not committed: binaries, model weights, `vendor/` state. Every download is
idempotent and size-checked against the manifests — workshop machines share
network hiccups, so a failed download self-heals on the next run.

---

## Tests

```bash
tests/run_tests.sh                 # offline suite (fast)
LLAMA_TEST_NETWORK=1 tests/run_tests.sh   # + network checks (smallest model, ~0.37 GB)
```

The launcher is the proof — bring it up and curl the endpoint. No standalone
"test models" script by design (the launcher is the verification).

---

## Pinned build

`b12675` (2026-11-24, nightly — not a stable release). The pinned build id,
URLs, and exact byte sizes are declared in `config/llama.sh`. Bump the build id
there to pin a newer release.
