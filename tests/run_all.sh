#!/usr/bin/env bash
# Run all test suites and report overall pass/fail.
# Usage: bash tests/run_all.sh
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES_FAILED=0

run_suite() {
  local label="$1" file="$TESTS_DIR/$2"
  echo ""
  echo "=============================="
  echo " $label"
  echo "=============================="
  if bash "$file"; then
    return 0
  else
    (( SUITES_FAILED++ )) || true
  fi
}

run_suite "Parsing unit tests"              "test_parse.sh"
run_suite "Static repo checks"              "test_static.sh"
run_suite "apply-config.sh integration"     "test_apply_config.sh"
run_suite "Helm rendering"                  "test_helm.sh"

echo ""
echo "=============================="
if [[ $SUITES_FAILED -eq 0 ]]; then
  echo " All suites passed."
  exit 0
else
  echo " $SUITES_FAILED suite(s) failed."
  exit 1
fi
