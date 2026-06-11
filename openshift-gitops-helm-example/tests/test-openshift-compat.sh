#!/usr/bin/env bash
# OpenShift compatibility tests for the example Helm charts.
#
# Verifies the charts lint, render with every environment values file, and
# produce manifests that satisfy OpenShift conventions:
#   - Route (route.openshift.io/v1) instead of Ingress
#   - Pod/container security contexts compatible with the restricted-v2 SCC
#     (no hardcoded UIDs, no privilege escalation, all capabilities dropped)
#   - Valid Route TLS termination values
#   - The ApplicationSet chart renders 1 AppProject + 2 ApplicationSets
#
# Usage: bash tests/test-openshift-compat.sh   (run from openshift-gitops-helm-example/)
# Requires: helm v3, bash, grep.

set -u
cd "$(dirname "$0")/.."

HELM="${HELM:-helm}"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

check() { # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then ok "$1"; else fail "$1"; fi
}

echo "== helm lint =="
for chart in charts/backend charts/frontend deployments/appset; do
  $HELM lint "$chart" > /dev/null 2>&1
  check "lint $chart" $?
done

echo "== render with every environment values file =="
for f in deployments/values/backend/*/api/values.yaml; do
  $HELM template api charts/backend -f "$f" > /dev/null 2>&1
  check "template charts/backend -f $f" $?
done
for f in deployments/values/frontend/*/ui/values.yaml; do
  $HELM template ui charts/frontend -f "$f" > /dev/null 2>&1
  check "template charts/frontend -f $f" $?
done

echo "== OpenShift resource conventions =="
for chart in charts/backend charts/frontend; do
  rendered="$($HELM template app "$chart" 2>/dev/null)"

  echo "$rendered" | grep -q 'apiVersion: route.openshift.io/v1'
  check "$chart: exposes a Route (route.openshift.io/v1)" $?

  ! echo "$rendered" | grep -q '^kind: Ingress'
  check "$chart: does not render an Ingress" $?

  echo "$rendered" | grep -A2 'tls:' | grep -qE 'termination: (edge|passthrough|reencrypt)'
  check "$chart: Route TLS termination is edge|passthrough|reencrypt" $?
done

echo "== restricted-v2 SCC compatibility =="
for chart in charts/backend charts/frontend; do
  rendered="$($HELM template app "$chart" 2>/dev/null)"

  # OpenShift assigns UIDs/GIDs from the namespace range; hardcoding them
  # causes pods to be rejected or re-mutated under restricted-v2.
  ! echo "$rendered" | grep -qE 'runAsUser|fsGroup'
  check "$chart: no hardcoded runAsUser/fsGroup" $?

  echo "$rendered" | grep -q 'runAsNonRoot: true'
  check "$chart: runAsNonRoot: true" $?

  echo "$rendered" | grep -q 'allowPrivilegeEscalation: false'
  check "$chart: allowPrivilegeEscalation: false" $?

  echo "$rendered" | grep -qE 'drop:.*ALL|- ALL'
  check "$chart: drops ALL capabilities" $?

  echo "$rendered" | grep -q 'type: RuntimeDefault'
  check "$chart: seccompProfile RuntimeDefault" $?

  ! echo "$rendered" | grep -qE 'privileged: true|hostNetwork: true|hostPID: true|hostPath:'
  check "$chart: no privileged/hostNetwork/hostPID/hostPath" $?
done

echo "== oauth2-proxy sidecar variant =="
rendered="$($HELM template app charts/backend --set oauth2Proxy.enabled=true --set oauth2Proxy.oidcIssuerUrl=https://issuer.example 2>/dev/null)"
echo "$rendered" | grep -q 'name: oauth2-proxy'
check "backend: oauth2-proxy sidecar renders when enabled" $?
echo "$rendered" | grep -q 'targetPort: oauth2-proxy'
check "backend: Route targets oauth2-proxy port when sidecar enabled" $?

echo "== ApplicationSet chart =="
rendered="$($HELM template myapp deployments/appset \
  --set appName=myapp --set org=acme --set repo=gitops --set env=dev 2>/dev/null)"

[ "$(echo "$rendered" | grep -c '^kind: AppProject')" -eq 1 ]
check "appset: renders exactly 1 AppProject" $?

[ "$(echo "$rendered" | grep -c '^kind: ApplicationSet')" -eq 2 ]
check "appset: renders exactly 2 ApplicationSets" $?

echo "$rendered" | grep -q 'name: myapp-acme-dev'
check "appset: AppProject name renders as <appName>-<org>-<env>" $?

echo "$rendered" | grep -qE 'path: charts/(backend|frontend)'
check "appset: Application sources point at top-level charts/" $?

echo "$rendered" | grep -q 'revision: HEAD' && echo "$rendered" | grep -q 'targetRevision: HEAD'
check "appset: generator revision and targetRevision are HEAD" $?

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
