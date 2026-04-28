#!/usr/bin/env bash
# Shared test helpers — source this file, do not execute directly.

PASS=0
FAIL=0
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() {
  echo "  [FAIL] $1"
  [[ -n "${2:-}" ]] && echo "         expected : $2"
  [[ -n "${3:-}" ]] && echo "         got      : $3"
  (( FAIL++ )) || true
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$expected" == "$actual" ]] && _pass "$desc" || _fail "$desc" "$expected" "$actual"
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  [[ "$haystack" == *"$needle"* ]] && _pass "$desc" || _fail "$desc" "contains '$needle'" "not found in: $haystack"
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  [[ "$haystack" != *"$needle"* ]] && _pass "$desc" || _fail "$desc" "should not contain '$needle'" "found it"
}

assert_file_exists() {
  local desc="$1" path="$2"
  [[ -f "$path" ]] && _pass "$desc" || _fail "$desc" "file exists" "not found: $path"
}

assert_file_absent() {
  local desc="$1" path="$2"
  [[ ! -f "$path" ]] && _pass "$desc" || _fail "$desc" "file absent" "found unexpectedly: $path"
}

assert_zero_grep() {
  local desc="$1" pattern="$2" dir="$3"
  local count
  count=$(grep -r "$pattern" "$dir" 2>/dev/null | wc -l | tr -d '[:space:]')
  [[ "$count" == "0" ]] && _pass "$desc" || _fail "$desc" "0 matches for '$pattern'" "$count match(es)"
}

assert_nonzero_grep() {
  local desc="$1" pattern="$2" target="$3"
  local count
  count=$(grep -c "$pattern" "$target" 2>/dev/null || true)
  [[ "${count:-0}" -gt 0 ]] && _pass "$desc" || _fail "$desc" "at least 1 match for '$pattern'" "0 matches in $target"
}

assert_count_eq() {
  local desc="$1" expected="$2" pattern="$3" input="$4"
  local actual
  actual=$(echo "$input" | grep -c "$pattern" || true)
  [[ "$expected" == "$actual" ]] && _pass "$desc" || _fail "$desc" "$expected occurrence(s) of '$pattern'" "$actual"
}

report() {
  echo ""
  echo "  Results: ${PASS} passed  ${FAIL} failed"
  [[ $FAIL -eq 0 ]]
}
