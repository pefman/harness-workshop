#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
for f in tests/test_*.sh; do
  [ -f "$f" ] || continue
  echo "== $f =="
  if bash "$f"; then
    :
  else
    fail=$((fail+1))
  fi
done

if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail test file(s)"
  exit 1
fi
echo "All test files passed"
exit 0
