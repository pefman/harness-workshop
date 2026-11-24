# Aggressive ctx defaults (6/8→16384, 12→16384, 16→32768)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the spec-pinned context defaults (6/8→4096, 12→8192, 16→16384) with agent-first defaults (6/8→16384, 12→16384, 16→32768), one shared default across all scripts, and a fit line that scales with ctx instead of a flat +2 GB.

**Architecture:** One shared helper `default_ctx_for_tier(tier)` in `lib/common.sh` (single source of truth); the launcher, tools script, and the menu banner each use it. The banner's fit estimate becomes `size + ctx × 0.00025 GB` (fp16 KV ≈ 0.25 MB/token, deliberately conservative).

**Tech Stack:** bash 5+, python3 (fit math kept in awk for consistency with the existing banner).

**Spec:** Design doc `docs/superpowers/specs/2026-11-24-llama-wsl-workshop-design.md` — its `--ctx` line and its "size + ~2 GB context" fit note are updated as part of this change (spec sync). Plan doc `docs/superpowers/plans/2026-11-24-llama-wsl-workshop.md` is a historical record and is not rewritten.

## Global Constraints

- Defaults are per-tier: 6/8→16384, 12→16384, 16→32768. `--ctx` override still wins everywhere.
- `bin/llama-claude.sh` needs no change — it reads `n_ctx` from the live endpoint.
- Existing tests updated, never deleted: tier-6-ctx, tier-16-ctx, tier-12-ctx assertions in `tests/test_launch.sh` + `tests/test_menu.sh`.
- Spec + README sync in this change.

## Review Focus

1. **Fit line accuracy** — a 14B at 32768 ctx is ~11.3 GB + ~8 GB ctx = ~19 GB, not "size + 2 GB". Assert via `bin/llama.sh` smoke (menu banner line).
2. **All three scripts agree** — launcher, tools, banner all print the same per-tier ctx.
3. **README/spec consistency** — no stale 4096/8192/16384 left in living docs.

---

### Task 1: Implement + sync

- [ ] **Step 1:** `lib/common.sh` — add `default_ctx_for_tier(tier)` (echoes the default ctx; empty + return 1 for unknown tier).
- [ ] **Step 2:** `bin/llama-launch.sh` — replace inline ctx case with `default_ctx_for_tier`; update header comment (`--ctx` default text).
- [ ] **Step 3:** `bin/llama-tools.sh` — same; header comment too.
- [ ] **Step 4:** `bin/llama.sh` — tier_banner: derive ctx from `default_ctx_for_tier`, compute `needed = size + ctx * 0.00025` (GB, 1 dp), print the ctx-scaled fit line.
- [ ] **Step 5:** Update `tests/test_launch.sh` (6→16384, 12→16384, 16→32768) and `tests/test_menu.sh` (16→32768); assert no stale `4096`/`8192` remain in living docs.
- [ ] **Step 6:** `README.md` — `--ctx-size` by-tier line + example command; `docs/superpowers/specs/2026-11-24-llama-wsl-workshop-design.md` — `--ctx` line + VRAM/fit note.
- [ ] **Step 7:** Run `tests/run_tests.sh` — all green.
- [ ] **Step 8:** Commit — `feat: raise per-tier ctx defaults (6/8,12→16384, 16→32768) + ctx-scaled fit line`.
