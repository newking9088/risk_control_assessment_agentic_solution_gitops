#!/usr/bin/env bash
# ShellCheck static analysis for all bash scripts.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

echo "--- ShellCheck static analysis ---"

if ! command -v shellcheck &>/dev/null; then
  echo "  [SKIP] shellcheck not found — install shellcheck and re-run"
  exit 0
fi

TARGETS=(
  "$REPO_ROOT/scripts/apply-config.sh"
  "$TESTS_DIR/test_parse.sh"
  "$TESTS_DIR/test_static.sh"
  "$TESTS_DIR/test_apply_config.sh"
  "$TESTS_DIR/test_helm.sh"
  "$TESTS_DIR/test_charts.sh"
  "$TESTS_DIR/test_idempotency.sh"
  "$TESTS_DIR/test_shellcheck.sh"
  "$TESTS_DIR/run_all.sh"
  "$TESTS_DIR/lib.sh"
)

ALL_PASS=true
for f in "${TARGETS[@]}"; do
  OUT=$(shellcheck "$f" 2>&1)
  STATUS=$?
  if [[ $STATUS -eq 0 ]]; then
    _pass "shellcheck: $(basename "$f") clean"
  else
    _fail "shellcheck: $(basename "$f") has issues" "exit 0" "exit $STATUS"
    echo "$OUT"
    ALL_PASS=false
  fi
done

report
