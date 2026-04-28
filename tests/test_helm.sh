#!/usr/bin/env bash
# Helm rendering tests for deployments/appset.
# Verifies the chart renders exactly one AppProject (named <env>-<appName>)
# and two ApplicationSets, with no empty documents.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

echo "--- Helm template rendering tests ---"

if ! command -v helm &>/dev/null; then
  echo "  [SKIP] helm not found — install helm v3 and re-run"
  exit 0
fi

APPSET="$REPO_ROOT/deployments/appset"
APP_NAME="test-app"
ENV="dev"

# Run helm template with all required values (values.yaml was deleted; all via --set)
OUTPUT=$(helm template "$APPSET" \
  --set appName="$APP_NAME" \
  --set env="$ENV" \
  --set org="test-org" \
  --set repo="test-repo" \
  --set server="https://kubernetes.default.svc" \
  --set IngressFrontendHost="${APP_NAME}-${ENV}.apps.example.com" \
  --set IngressBackendHost="${APP_NAME}-${ENV}.apps.example.com" \
  2>&1)

HELM_EXIT=$?
assert_eq "helm template exits 0" "0" "$HELM_EXIT"

# Exactly one AppProject
APPPROJECT_COUNT=$(echo "$OUTPUT" | grep -c "^kind: AppProject" || true)
assert_eq "exactly one AppProject rendered" "1" "$APPPROJECT_COUNT"

# AppProject name is <env>-<appName>
assert_contains \
  "AppProject named ${ENV}-${APP_NAME}" \
  "name: ${ENV}-${APP_NAME}" \
  "$OUTPUT"

# Exactly two ApplicationSets (backend + frontend)
APPSET_COUNT=$(echo "$OUTPUT" | grep -c "^kind: ApplicationSet" || true)
assert_eq "exactly two ApplicationSets rendered" "2" "$APPSET_COUNT"

# Backend ApplicationSet present
assert_contains \
  "backend ApplicationSet present" \
  "backend-appset-${APP_NAME}-${ENV}" \
  "$OUTPUT"

# Frontend ApplicationSet present
assert_contains \
  "frontend ApplicationSet present" \
  "frontend-appset-${APP_NAME}-${ENV}" \
  "$OUTPUT"

# No empty documents (a document that contains only whitespace between --- markers)
EMPTY_DOCS=$(echo "$OUTPUT" | awk '/^---/{doc=""} {doc=doc $0} /^---/{if(doc ~ /^---[[:space:]]*$/) print "EMPTY"}' | wc -l | tr -d '[:space:]')
assert_eq "no empty documents in helm output" "0" "$EMPTY_DOCS"

# Both ApplicationSets point project to <env>-<appName>
PROJ_REF_COUNT=$(echo "$OUTPUT" | grep -c "project: '${ENV}-${APP_NAME}'" || true)
assert_eq "both ApplicationSets reference project ${ENV}-${APP_NAME}" "2" "$PROJ_REF_COUNT"

# Both ApplicationSets use revision: HEAD (not a hardcoded branch)
REVISION_MAIN=$(echo "$OUTPUT" | grep -c "revision: main" || true)
assert_eq "no hardcoded 'revision: main' in rendered output" "0" "$REVISION_MAIN"

report
