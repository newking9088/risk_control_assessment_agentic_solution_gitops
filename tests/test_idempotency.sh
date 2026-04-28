#!/usr/bin/env bash
# Idempotency test: running apply-config.sh twice produces byte-identical output.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

echo "--- apply-config.sh idempotency tests ---"

if ! command -v envsubst &>/dev/null; then
  echo "  [SKIP] envsubst not found — install gettext and re-run"
  exit 0
fi

# Build an isolated temp tree
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

cp -r "$REPO_ROOT/deployments" "$TMPDIR_ROOT/"
cp -r "$REPO_ROOT/.github"     "$TMPDIR_ROOT/"
mkdir -p "$TMPDIR_ROOT/scripts"
cp "$REPO_ROOT/scripts/apply-config.sh" "$TMPDIR_ROOT/scripts/"
cp "$TESTS_DIR/fixtures/config.test.yaml" "$TMPDIR_ROOT/config.yaml"

# First run
bash "$TMPDIR_ROOT/scripts/apply-config.sh" >/dev/null 2>&1
assert_eq "first apply-config.sh run exits 0" "0" "$?"

# Snapshot 1: sorted list of "sha256  filename" for every generated .yaml
SNAP1=$(find "$TMPDIR_ROOT" -name "*.yaml" -not -name "*.tpl" | sort \
  | xargs sha256sum 2>/dev/null | sed "s|$TMPDIR_ROOT/||g" | sort)

# Second run on the same tree
bash "$TMPDIR_ROOT/scripts/apply-config.sh" >/dev/null 2>&1
assert_eq "second apply-config.sh run exits 0" "0" "$?"

# Snapshot 2
SNAP2=$(find "$TMPDIR_ROOT" -name "*.yaml" -not -name "*.tpl" | sort \
  | xargs sha256sum 2>/dev/null | sed "s|$TMPDIR_ROOT/||g" | sort)

if [[ "$SNAP1" == "$SNAP2" ]]; then
  _pass "apply-config.sh output is byte-identical on second run"
else
  DIFF=$(diff <(echo "$SNAP1") <(echo "$SNAP2") || true)
  _fail "apply-config.sh is NOT idempotent — snapshots differ" "identical" "$DIFF"
fi

report
