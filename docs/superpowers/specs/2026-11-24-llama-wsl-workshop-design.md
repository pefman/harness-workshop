# Llama on WSL with NVIDIA — Workshop Toolkit

**Date:** 2026-11-24
**Status:** Approved for build (design conversation complete)
**Repo:** `/home/pefman/git/workshop`

## Intent

A workshop of coworkers who will run Llama-style GGUF models on **WSL with NVIDIA GPUs**. Attendees have different amounts of VRAM (6 GB–16 GB). The toolkit should let each person go from a clean checkout to a working GPU-accelerated model with minimal fuss — no flag-memorizing — so the workshop is about models and hardware, not plumbing.

## Goals

- One shared `bin/` of bash scripts; **everything is menu-driven** when run bare, with flags for people who prefer them.
- Auto-detect the machine: WSL? GPU? Total VRAM? Which tier does it land in?
- Pinned, bundled llama.cpp build (CUDA included), downloaded once into `vendor/` — repo stays light, no 400+ MB binaries committed.
- A curated model library: **5 choices per tier, 4 tiers (6/8/12/16 GB)**, spanning several families (Llama, Qwen, Gemma, Mistral, Phi), with real measured file sizes.
- A **harness launcher**: a separate script that starts `llama-server` with the right parameters for the model + tier the user picked, so the attendee can bring the server up and hit it immediately.

## Non-goals / anti-goals

- No web UI, no Next.js, no desktop app — it's bash.
- No model weights committed to git (every file is still a download).
- No uncommitted `vendor/` state — `vendor/` is gitignored and recreated from manifests.
- No GPU-vs-CPU dance of "install CUDA from scratch" — llama.cpp bundles CUDA runtime in the `cudart-*` build, so attendees only need an NVIDIA driver.
- No fancy framework — the scripts must be readable and forkable by coworkers who aren't fluent in bash.

## Constraints

- **WSL2 + NVIDIA driver** is the target; native Linux should also work (the scripts detect, not assume).
- Every download must be **idempotent** and **size-checked** — workshop machines share network hiccups.
- The pinned llama.cpp build is **nightly** (`b12675`, 2026-11-24), not a stable release — that's the honest reason the build id is in the manifest, not the asset name alone.
- Every attendee should be able to run `bin/llama.sh` and land in a menu with working choices on their machine.

## Approaches considered

### Runtime
- **Ollama** (rejected): nice for end users, but it's a daemon + model-catalog lock-in; the workshop should exercise llama.cpp directly so attendees understand what the runtime is doing.
- **llama.cpp** (chosen): single binary, direct control of flags, exactly what we're teaching.

### Binary delivery
- **A. Commit the tar.gz to git**: rejected — 400+ MB, every clone, every coworker pays.
- **B. Repo light, scripts download on first run** (chosen): repo carries a manifest; `setup` downloads and unpacks into `vendor/`. Lighter clones, network required on first setup.
- **C. Git LFS** (mentioned, not chosen): would work, but adds a tool dependency for coworkers who haven't installed `git lfs`; option B with a size check is the simplest robust middle.
- **CUDA build**: `cudart-llama-*-ubuntu-cuda-12.8-x64.tar.gz` over 13.5 — smaller bundled runtime and the broadest driver compatibility. `.tar.gz`, not `.zip`, because the WSL/Linux builds are tar.gz; the `.zip` variants are the Windows-native builds.

### Model library
- 5 choices per tier, 4 tiers, measured GGUF sizes. Defaults are Llama-first (the workshop is about Llama) except where a bigger-class non-Llama model is the natural showcase (tier 16). See "Model library" below.
- Each tier's entry is `<family>-<params>-<quant>.gguf`, pulled from `bartowski`'s Hugging Face repos. A size is the basic integrity check; no checksums because bartowski doesn't publish a per-file sha256 API that's trivially queryable.

### Three shapes for the test concept
The workshop originally said "test some models"; during the design conversation this collapsed into "the launcher is the proof" — no standalone test script. **Dropped.** The launcher brings up the server; the attendee curls it to verify. This is the chosen shape, and it's an anti-goal to reintroduce a separate test script unless the workshop grows one.

## The parts of the design that were decided

- **Auto-detection**: `nvidia-smi --query-gpu=memory.total --format=csv,noheader` → snap down to tier (6/8/12/16 GB). Manual `--vram N` / `--model <name>` / `--tier <t>` flags override in every script.
- **Tiers and model mapping** (below).
- **Pinned binary**: `cudart-llama-b12675-bin-ubuntu-cuda-12.8-x64.tar.gz`
  (<https://github.com/ggml-org/llama.cpp/releases/tag/b12675>), declared in
  `config/llama.sh` (build id, url, expected size in bytes — the size check for
  the tarball reads from that file, not from the asset name alone).
  Unpacks to `vendor/llama.cpp/bin/llama-*`. The size on disk is checked after
  download; the script re-downloads on mismatch.
- **Harness launcher**: separate script `bin/llama-launch.sh`, starts `llama-server` with:
  - `--model vendor/models/<file>.gguf`
  - `--n-gpu-layers auto`
  - `--ctx` by tier: 6/8 GB → 16384, 12 GB → 16384, 16 GB → 32768
  - `--host 127.0.0.1 --port 8080` (overridable via args)
  - threads left to llama.cpp's own default (no invented number)
  - prints the endpoint + a sample `curl` line on start
- **Launcher auto-downloads**: if the chosen model isn't in `vendor/models/`, the launcher downloads it on launch, with a clear `downloading <model> (~<size>)...` line, then starts the server. No menu step required to bring a missing model up.
- **Menu UX**: bare run → menu. Flags bypass. Uses tput colors only if stdout is a tty; otherwise plain.
- **Downloads**: `curl -L` with follow, size-check against the manifest, `set -euo pipefail` everywhere, `vendor/` is the only writable area besides `config/` and `bin/`.

## Model library (measured sizes, bartowski GGUF)

| Tier | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| 6 GB | Qwen2.5-0.5B Q4_K_M (0.37 GB) | Llama-3.2-1B Q4_K_M (0.81 GB) | gemma-2-2b-it Q4_K_M (1.59 GB) | Qwen2.5-3B Q4_K_M (1.93 GB) | Llama-3.2-3B Q4_K_M ★ default (2.02 GB) |
| 8 GB | Mistral-7B-Instruct-v0.3 Q4_K_M (4.07 GB) | Llama-3.1-8B Q4_K_S (4.37 GB) | Llama-3.1-8B Q4_K_M ★ default (4.58 GB) | Qwen2.5-7B Q4_K_M (4.68 GB) | gemma-2-9b-it Q4_K_S (5.10 GB) |
| 12 GB | Llama-3.1-8B Q6_K_L (6.38 GB) | Mistral-7B Q8_0 (7.17 GB) | Llama-3.1-8B Q8_0 ★ default (7.95 GB) | Qwen2.5-14B Q4_K_M (8.37 GB) | gemma-2-9b-it Q8_0 (9.15 GB) |
| 16 GB | Mistral-7B Q8_0 (7.17 GB) | Llama-3.1-8B Q8_0 (7.95 GB) | Qwen2.5-14B Q4_K_S (7.98 GB) | gemma-2-9b-it Q8_0 (9.15 GB) | Qwen2.5-14B Q6_K ★ default (11.29 GB) |

*Each cell lists exactly 5 models. One of the 5 is the default (marked ★). `default_model_for_tier(tier)` in `config/models.sh` returns it.*

*Defaults are Llama-first (the workshop is about Llama) except tier 16, which showcases a bigger-class Qwen, since the hardware is strongest there.*

*VRAM needed is model size + ~0.25 MB per context token (≈4 GB at 16384 ctx, ≈8 GB at 32768 ctx). A "comfortably fits" line is the right expectation for the default of each tier, and the menu shows the fit so the attendee can pick a tighter option.*

## Structure

```
workshop/
├── bin/
│   ├── llama.sh             # single top-level menu (Setup/Models/Launch/Help/Exit)
│   ├── llama-setup.sh       # detect WSL+GPU, download+unpack llama.cpp, report
│   ├── llama-models.sh      # list tier models, download one/all (all = all models in the active tier)
│   └── llama-launch.sh      # harness launcher: start llama-server with tier params
├── config/
│   ├── models.sh            # bash-sourceable tier→models (id, size_gb, quant, family, params, tier_default)
│   └── llama.sh               # bash-sourceable binary manifest (build id, url, size_bytes)
├── lib/
│   └── common.sh            # shared: WSL/GPU/VRAM detect, tier snap, binary lookup, colors
├── vendor/                  # gitignored — llama.cpp + downloaded GGUF models
├── .gitignore
└── README.md
```

## What's left to the builder

- Exact quoting/format of `vendor/` state and error messages.
- `README.md` content (usage, what to expect first, troubleshooting).
- `lib/common.sh` internals (color fallback, VRAM parsing, tier detection edge cases: multi-GPU, <6 GB total, no GPU at all).
- Whether `llama.sh` and the per-task scripts share a `args()` parser or each script validates its own — either is fine.

## What this design explicitly does NOT decide

- Whether to commit a Linux-native binary alongside the ubuntu one (out of scope).
- Whether the workshop wants a single sample prompt or a "hello world" chat once the server is up (out of scope — the launcher prints the curl line).
