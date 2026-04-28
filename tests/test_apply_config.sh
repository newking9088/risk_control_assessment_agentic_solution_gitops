#!/usr/bin/env bash
# Integration test: run apply-config.sh end-to-end in a temp directory using
# the test fixture config.  Verifies all expected output files are generated
# with substituted values and no leftover ${...} placeholders.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

echo "--- apply-config.sh integration tests ---"

if ! command -v envsubst &>/dev/null; then
  echo "  [SKIP] envsubst not found — install gettext and re-run"
  exit 0
fi

# Build an isolated copy of the repo so generated files don't touch the real tree
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

cp -r "$REPO_ROOT/deployments"  "$TMPDIR_ROOT/"
cp -r "$REPO_ROOT/.github"      "$TMPDIR_ROOT/"
mkdir -p "$TMPDIR_ROOT/scripts"
cp "$REPO_ROOT/scripts/apply-config.sh" "$TMPDIR_ROOT/scripts/"
cp "$TESTS_DIR/fixtures/config.test.yaml" "$TMPDIR_ROOT/config.yaml"

# Run the script
bash "$TMPDIR_ROOT/scripts/apply-config.sh" > "$TMPDIR_ROOT/apply.log" 2>&1
APPLY_EXIT=$?

if [[ $APPLY_EXIT -ne 0 ]]; then
  echo "  [FAIL] apply-config.sh exited with code $APPLY_EXIT"
  cat "$TMPDIR_ROOT/apply.log"
  (( FAIL++ )) || true
else
  _pass "apply-config.sh exited 0"
fi

# Script must not emit any WARN lines (sanity check in test fixture is clean)
WARN_COUNT=$(grep -c "WARN:" "$TMPDIR_ROOT/apply.log" || true)
assert_eq "no WARN lines in output (test fixture values are clean)" "0" "$WARN_COUNT"

DV="$TMPDIR_ROOT/deployments/values"
WF="$TMPDIR_ROOT/.github/workflows"
AS="$TMPDIR_ROOT/deployments/appset"

# --- Generated value files ---
for env in dev qa stage prod; do
  for svc in api auth; do
    assert_file_exists \
      "backend ${env}/${svc}/values.yaml generated" \
      "$DV/backend/${env}/${svc}/values.yaml"
  done
  assert_file_exists \
    "frontend ${env}/ui/values.yaml generated" \
    "$DV/frontend/${env}/ui/values.yaml"
done

# --- Generated workflow files ---
for env in dev qa stage prod; do
  assert_file_exists \
    "workflow ci-cd-${env}.yaml generated" \
    "$WF/ci-cd-${env}.yaml"
done

# --- Generated appset values ---
assert_file_exists \
  "deployments/appset/values.yaml generated" \
  "$AS/values.yaml"

# --- Substitution correctness: APP_NAME value appears in generated files ---
assert_nonzero_grep \
  "APP_NAME value substituted in appset/values.yaml" \
  "my-test-app" \
  "$AS/values.yaml"

assert_nonzero_grep \
  "GITHUB_ORG value substituted in appset/values.yaml" \
  "test-org" \
  "$AS/values.yaml"

assert_nonzero_grep \
  "APP_NAME value substituted in ci-cd-dev.yaml" \
  "my-test-app" \
  "$WF/ci-cd-dev.yaml"

# Inline comment was stripped: KEYVAULT_NAME_DEV must not end with "# used for dev"
assert_zero_grep \
  "inline comment not present in backend dev api values.yaml" \
  "# used for dev" \
  "$DV/backend/dev/api/values.yaml"

# --- No unsubstituted ${UPPERCASE} placeholders in generated (non-tpl) files ---
LEFTOVER=$(grep -r '\${[A-Z_][A-Z_0-9]*}' \
  "$DV" "$AS/values.yaml" \
  --include="*.yaml" \
  --exclude="*.tpl" 2>/dev/null | wc -l | tr -d '[:space:]')
assert_eq "no leftover \${VAR} placeholders in generated values files" "0" "$LEFTOVER"

# Workflow files: identity vars substituted, GitHub Actions ${{ }} syntax preserved
for env in dev qa stage prod; do
  assert_zero_grep \
    "ci-cd-${env}.yaml: \${APP_NAME} fully substituted" \
    '\${APP_NAME}' \
    "$WF/ci-cd-${env}.yaml"

  assert_nonzero_grep \
    "ci-cd-${env}.yaml: \${{ }} GitHub Actions syntax preserved" \
    '\${{' \
    "$WF/ci-cd-${env}.yaml"
done

report
