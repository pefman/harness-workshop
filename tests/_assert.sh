#!/usr/bin/env bash
# Tiny assertions for the workshop toolkit tests. Each test file sources
# this, calls the assertions, and ends with `report_and_exit`.

_TEST_COUNT=0
_FAIL_COUNT=0

assert_eq() { # actual expected name
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 — expected '$2', got '$1'"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  else
    echo "pass: $3"
  fi
}

assert_contains() { # haystack needle name
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [[ "$1" != *"$2"* ]]; then
    echo "FAIL: $3 — expected output to contain '$2', got: $1"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  else
    echo "pass: $3"
  fi
}

assert_file_exists() { # path name
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [ ! -f "$1" ]; then
    echo "FAIL: $2 — expected file '$1'"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  else
    echo "pass: $2"
  fi
}

assert_not_empty() { # string name
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [ -z "$1" ]; then
    echo "FAIL: $2 — expected non-empty"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  else
    echo "pass: $2"
  fi
}

assert_success() { # description — runs the caller's command and requires exit 0
  _TEST_COUNT=$((_TEST_COUNT+1))
  if [ "$1" = "0" ]; then
    echo "pass: $2"
  else
    echo "FAIL: $2 — expected exit 0, got $1"
    _FAIL_COUNT=$((_FAIL_COUNT+1))
  fi
}

report_and_exit() {
  echo "---"
  echo "$_TEST_COUNT assertions, $_FAIL_COUNT failed"
  if [ "$_FAIL_COUNT" -gt 0 ]; then exit 1; fi
  exit 0
}
