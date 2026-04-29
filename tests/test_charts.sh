#!/usr/bin/env bash
# Per-chart Helm rendering tests.
# Runs apply-config.sh against the test fixture, then helm-templates every
# chart+values combination and validates YAML output with python3.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

echo "--- Per-chart Helm rendering tests ---"

if ! command -v helm &>/dev/null; then
  echo "  [SKIP] helm not found — install helm v3 and re-run"
  exit 0
fi

if ! command -v python3 &>/dev/null; then
  echo "  [SKIP] python3 not found — install python3 and re-run"
  exit 0
fi

if ! python3 -c "import yaml" 2>/dev/null; then
  echo "  [SKIP] python3 yaml module not found — pip install pyyaml or apt install python3-yaml"
  exit 0
fi

if ! command -v envsubst &>/dev/null; then
  echo "  [SKIP] envsubst not found — install gettext and re-run"
  exit 0
fi

# Build an isolated copy of the repo with substituted values
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

cp -r "$REPO_ROOT/deployments" "$TMPDIR_ROOT/"
cp -r "$REPO_ROOT/.github"     "$TMPDIR_ROOT/"
mkdir -p "$TMPDIR_ROOT/scripts"
cp "$REPO_ROOT/scripts/apply-config.sh" "$TMPDIR_ROOT/scripts/"
cp "$TESTS_DIR/fixtures/config.test.yaml" "$TMPDIR_ROOT/config.yaml"

bash "$TMPDIR_ROOT/scripts/apply-config.sh" > "$TMPDIR_ROOT/apply.log" 2>&1
APPLY_EXIT=$?
if [[ $APPLY_EXIT -ne 0 ]]; then
  echo "  [FAIL] apply-config.sh exited $APPLY_EXIT — cannot proceed"
  cat "$TMPDIR_ROOT/apply.log"
  report; exit 1
fi

CHARTS="$TMPDIR_ROOT/deployments/charts"
VALUES="$TMPDIR_ROOT/deployments/values"

# Helm lint both charts
for chart in backend frontend; do
  OUT=$(helm lint "$CHARTS/$chart" 2>&1)
  STATUS=$?
  assert_eq "helm lint $chart exits 0" "0" "$STATUS"
  if [[ $STATUS -ne 0 ]]; then echo "$OUT"; fi
done

# Per-env per-service helm template + YAML validity + volumeMount assertions (E1)
for env in dev qa stage prod; do
  for svc in api auth; do
    vals="$VALUES/backend/${env}/${svc}/values.yaml"
    if [[ ! -f "$vals" ]]; then
      _fail "backend ${env}/${svc}: values.yaml missing" "file" "absent"
      continue
    fi
    OUT=$(helm template "backend-${env}-${svc}" "$CHARTS/backend" -f "$vals" 2>&1)
    STATUS=$?
    assert_eq "helm template backend ${env}/${svc} exits 0" "0" "$STATUS"
    if [[ $STATUS -eq 0 ]]; then
      YAML_OUT=$(echo "$OUT" | python3 -c "import yaml,sys; list(yaml.safe_load_all(sys.stdin))" 2>&1)
      YAML_STATUS=$?
      assert_eq "backend ${env}/${svc} renders valid YAML" "0" "$YAML_STATUS"
      # E1: must include /tmp mountPath
      assert_contains \
        "backend ${env}/${svc}: Deployment includes mountPath /tmp" \
        "mountPath: /tmp" \
        "$OUT"
    fi
  done

  vals="$VALUES/frontend/${env}/ui/values.yaml"
  if [[ ! -f "$vals" ]]; then
    _fail "frontend ${env}/ui: values.yaml missing" "file" "absent"
    continue
  fi
  OUT=$(helm template "frontend-${env}-ui" "$CHARTS/frontend" -f "$vals" 2>&1)
  STATUS=$?
  assert_eq "helm template frontend ${env}/ui exits 0" "0" "$STATUS"
  if [[ $STATUS -eq 0 ]]; then
    YAML_OUT=$(echo "$OUT" | python3 -c "import yaml,sys; list(yaml.safe_load_all(sys.stdin))" 2>&1)
    YAML_STATUS=$?
    assert_eq "frontend ${env}/ui renders valid YAML" "0" "$YAML_STATUS"
    # E1: must include /tmp, /var/cache/nginx, /var/run mountPaths
    assert_contains \
      "frontend ${env}/ui: Deployment includes mountPath /tmp" \
      "mountPath: /tmp" \
      "$OUT"
    assert_contains \
      "frontend ${env}/ui: Deployment includes mountPath /var/cache/nginx" \
      "mountPath: /var/cache/nginx" \
      "$OUT"
    assert_contains \
      "frontend ${env}/ui: Deployment includes mountPath /var/run" \
      "mountPath: /var/run" \
      "$OUT"
    assert_contains \
      "frontend ${env}/ui: Deployment includes livenessProbe" \
      "livenessProbe:" \
      "$OUT"
    assert_contains \
      "frontend ${env}/ui: Deployment includes readinessProbe" \
      "readinessProbe:" \
      "$OUT"
  fi
done

report
