#!/usr/bin/env bash
# bin/llama.sh — single top-level menu + arg dispatch.
# Usage:
#   llama.sh                       → interactive menu (Setup / Models / Launch / Help / Exit)
#   llama.sh setup|models|launch   → dispatch to the matching task script
#   llama.sh --setup|--models|--launch
#   llama.sh help|--help           → print help
#
# Flags are forwarded to the task script:
#   llama.sh models list --tier 6
#   llama.sh models download all --tier 6
#   llama.sh launch --dry-run --tier 16
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/config/models.sh"

BIN_DIR="$PROJECT_ROOT/bin"

help_text() {
  cat <<'HELP'
usage: llama.sh <command> [args...]

  setup       detect WSL/GPU, download + unpack the pinned llama.cpp
  models      list tier models, download one/all (all = active tier)
  launch      start llama-server with the tier-appropriate params
  help        show this help (or: llama.sh --help)

Sub-commands forward extra args to the task script:
  llama.sh models list --tier 6
  llama.sh models download all
  llama.sh launch --dry-run --tier 16

Flags: -h|--help for help.
HELP
}

tier_banner() {
  local tier model size needed verdict
  tier=$(active_tier "")
  model=$(default_model_for_tier "$tier" 2>/dev/null)
  if [ -z "$model" ]; then
    echo "Tier $tier"
    return
  fi
  IFS='|' read -r size _ _ _ _ _ <<< "${model_entry[$model]}"
  needed=$(awk -v s="$size" 'BEGIN { printf "%.1f", s + 2.0 }')
  if awk -v n="$needed" -v t="$tier" 'BEGIN { exit !(n < t) }'; then
    verdict="fits"
  else
    verdict="tight"
  fi
  echo "Tier $tier — default: $model (${size} GB). ~${needed} GB needed (size + 2 GB context) — $verdict."
}

menu_loop() {
  while true; do
    echo
    echo "$(color "llama.cpp workshop" "1;36")"
    tier_banner
    echo
    echo "  1) Setup    — detect WSL/GPU, download + unpack llama.cpp"
    echo "  2) Models   — list tier models / download"
    echo "  3) Launch   — start llama-server with tier params"
    echo "  4) Help     — show usage"
    echo "  5) Exit"
    echo
    printf "Choice [1-5]: "
    if ! read -r choice; then
      exit 0
    fi
    case "$choice" in
      1) "$BIN_DIR/llama-setup.sh" --check; read -p "Press Enter to continue..." ;;
      2) "$BIN_DIR/llama-models.sh" list; read -p "Press Enter to continue..." ;;
      3) "$BIN_DIR/llama-launch.sh"; read -p "Press Enter to continue..." ;;
      4) help_text; read -p "Press Enter to continue..." ;;
      5) exit 0 ;;
      "") echo "please pick 1-5" ;;
      *) echo "unknown choice '$choice' — pick 1-5" ;;
    esac
  done
}

if [ $# -eq 0 ]; then
  if [ -t 0 ]; then
    menu_loop
    exit 0
  fi
  echo "no args: run with --help or pass a subcommand" >&2
  exit 2
fi

case "$1" in
  setup|--setup)     shift; exec "$BIN_DIR/llama-setup.sh" "$@" ;;
  models|--models)   shift; exec "$BIN_DIR/llama-models.sh" "$@" ;;
  launch|--launch)   shift; exec "$BIN_DIR/llama-launch.sh" "$@" ;;
  help|--help|-h)    help_text; exit 0 ;;
  *)
    echo "error: unknown subcommand '$1'" >&2
    help_text >&2
    exit 2 ;;
esac
