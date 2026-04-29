You are working in the `risk_control_assessment_agentic_solution_gitops` repo. An external audit found ~15 issues across correctness, security, documentation, and forker-friction. Land the fixes below in one pass, grouped by section. After each section, run `bash tests/run_all.sh` and confirm 0 failures (with `envsubst` and `helm` available; `shellcheck`, `python3-yaml` may be skipped). Commit each section as its own git commit using the existing `<type>: <subject>` convention.

Do not weaken any existing test or assertion. Do not delete `config.yaml` keys without also deleting the matching key in `tests/fixtures/config.test.yaml` and removing every `${KEY}` reference.

---

## CONTEXT YOU NEED BEFORE STARTING

1. **How the repo deploys:** `config.yaml` → `scripts/apply-config.sh` runs `envsubst` → produces `*.yaml` next to every `*.tpl`. The generated `deployments/appset/` Helm chart is then installed by a per-env `.github/workflows/ci-cd-<env>.yaml` workflow into the `argocd` namespace. ArgoCD's ApplicationSet then watches `deployments/values/<env>/` and syncs each service (`api`, `auth`, `ui`) using `deployments/charts/<backend|frontend>/`.

2. **Rendered namespace formula:** The AppSet template sets the destination namespace to `{{ .Values.env }}-{{ .Values.appName }}` (e.g. `dev-risk-control-assessment-agentic-solution`). Source: `deployments/appset/templates/appset.backend.yaml` Line 30 and `appset.frontend.yaml`.

3. **Service-name formula:** From `deployments/charts/backend/templates/_helpers.tpl`, the rendered Service name is `<Release.Name>-<chart-name>` truncated to 63 chars. Release.Name is `<APP_NAME>-<env>-<svc>` per the AppSet template, so the auth Service ends up at `<APP_NAME>-<env>-auth-backend`.

4. **Tests are currently run on `main`** via `tests/run_all.sh`. Section A has a logic bug that causes the spv.no whitelisting assertion to fail every run. Fix that first so you have a green baseline to measure against.

5. **Existing test suites** (`tests/run_all.sh`): `test_parse.sh`, `test_static.sh`, `test_apply_config.sh`, `test_helm.sh`, `test_charts.sh`, `test_idempotency.sh`, `test_shellcheck.sh`. Add new assertions to the existing suite that fits best — do not create new suite files unless told to.

---

## SECTION A – Get the test suite green (do this first; one commit)

**●A1.** In `tests/test_helm.sh`, the spv.no regression guard uses `grep -A1` (line after) where it should use `grep -B1` (line before). The rendered AppProject is:

```
- group: spv.no
  kind: AzureKeyVaultSecret
- group: policy
  kind: PodDisruptionBudget
```

so `grep -A1 "kind: AzureKeyVaultSecret"` returns the `policy` line, not the `spv.no` line. Change `-A1` to `-B1` at the AKV_LINE assignment. Confirm `bash tests/run_all.sh` exits 0.

**●●Commit message●●**
```
fix: test_helm.sh spv.no guard checked the wrong line

The regression guard used grep -A1 (line after kind: AzureKeyVaultSecret)
which returned the next entry's group (policy). The intended group
(spv.no) is on the line before. Switch to -B1.
```

---

## SECTION B – Fix the runtime correctness bug (one commit)

**●B1.** Every per-env api `values.yaml.tpl` builds an in-cluster URL for the auth service using the wrong namespace component. The four affected files are:

- `deployments/values/backend/dev/api/values.yaml.tpl`
- `deployments/values/backend/qa/api/values.yaml.tpl`
- `deployments/values/backend/stage/api/values.yaml.tpl`
- `deployments/values/backend/prod/api/values.yaml.tpl`

Each currently contains a value like:
```
AUTH_SERVICE_URL: "http://${APP_NAME}-<env>-auth-backend.<env>.svc.cluster.local"
```

The actual K8s namespace is `<env>-<APP_NAME>`, not `<env>`. Change each line to:
```
AUTH_SERVICE_URL: "http://${APP_NAME}-<env>-auth-backend.<env>-${APP_NAME}.svc.cluster.local"
```

where `<env>` is the literal `dev` / `qa` / `stage` / `prod` already present on that line. Keep the rest of the line identical.

**●B2.** Add a regression guard to `tests/test_static.sh` (under the existing static checks, before `report`):

```bash
# Auth-service FQDN must reference namespace <env>-${APP_NAME}, not just <env>
echo ""
echo "--- AUTH_SERVICE_URL namespace formula guard ---"
for env in dev qa stage prod; do
  tpl="$D/values/backend/${env}/api/values.yaml.tpl"
  expected="auth-backend.${env}-\${APP_NAME}.svc.cluster.local"
  count=$(grep -c "$expected" "$tpl" 2>/dev/null || true)
  [[ "${count:-0}" -gt 0 ]] \
    && _pass "${env}/api: AUTH_SERVICE_URL uses namespace ${env}-\${APP_NAME}" \
    || _fail "${env}/api: AUTH_SERVICE_URL has wrong namespace" \
      "host suffix '$expected'" \
      "not found in $tpl"
done

# Inverse guard: must not contain the buggy short-namespace form
for env in dev qa stage prod; do
  tpl="$D/values/backend/${env}/api/values.yaml.tpl"
  bad="auth-backend.${env}.svc.cluster.local"
  count=$(grep -c "$bad" "$tpl" 2>/dev/null || true)
  [[ "${count:-0}" -eq 0 ]] \
    && _pass "${env}/api: no buggy short-namespace AUTH_SERVICE_URL" \
    || _fail "${env}/api: buggy short-namespace form still present" \
      "0 matches for '$bad'" \
      "${count}"
done
```

**●B3.** Run `bash tests/run_all.sh` – expect 0 failures.

**●●Commit message●●**
```
fix: AUTH_SERVICE_URL points to wrong namespace in all envs

The AppSet deploys workloads to namespace <env>-<appName>, but the
auth FQDN was built on the <env>.svc.cluster.local. As a result
api pods would NXDOMAIN on every auth call. Correct the FQDN in all
four envs and add a static test guard so this can't regress.
```

---

## SECTION C – Documentation correctness (one commit)

**●C1.** `docs/runbook.md` lines 82 and 86 use `<APP_NAME>-<env>` namespace order, contradicting line 30 which correctly says `<env>-<app-name>`. Replace:

- Line 82: `kubectl get pods -n <APP_NAME>-stage` → `kubectl get pods -n stage-<APP_NAME>`
- Line 86: `kubectl rollout status deployment/<release> -n <APP_NAME>-prod` → `kubectl rollout status deployment/<release> -n prod-<APP_NAME>`

**●C2.** `CONTRIBUTING.md` lines 10-11 hint at a `config.yaml.local` overlay that `scripts/apply-config.sh` does not implement. Pick one:

- **❶ Easiest:** delete the `cp config.yaml config.yaml.local  # optional — keep secrets out of git` line.
- **❷ Implement:** In `scripts/apply-config.sh`, after parsing `$CONFIG`, if `$ROOT/config.yaml.local` exists, parse it the same way and let it override values. Add `config.yaml.local` to `.gitignore`. Add a paragraph to `CONTRIBUTING.md` explaining that `config.yaml.local` is an optional, gitignored overlay.

If you implement the overlay: add a test to `tests/test_apply_config.sh` that creates a `config.yaml.local` with one overriding key and asserts the rendered output uses the overlay value.

**●●Commit message●●**
```
docs: fix runbook namespace order and drop misleading .local hint

- runbook.md: <env>-<app-name> namespace order applied to "Promote from
  stage to prod" steps (was <APP_NAME>-stage / <APP_NAME>-prod which
  contradicts the rotation runbook 4 lines above).
- CONTRIBUTING.md: drop the config.yaml.local hint (not implemented).
```

---

## SECTION D – Genericize for forkers (one commit)

The README claims `APP_NAME`, `GITHUB_ORG`, `GITHUB_REPO`, `ADMIN_EMAIL` are "fixed for this project". For a template that strangers will fork, that's the wrong default. Move them into the `CHANGE_ME_*` group.

**●D1.** Edit `config.yaml`:
- `APP_NAME: "risk-control-assessment-agentic-solution"` → `APP_NAME: "CHANGE_ME_APP_NAME"`
- `GITHUB_ORG: "newking9088"` → `GITHUB_ORG: "CHANGE_ME_GITHUB_ORG"`
- `GITHUB_REPO: "risk_control_assessment_agentic_solution_gitops"` → `GITHUB_REPO: "CHANGE_ME_GITHUB_REPO"`
- `ADMIN_EMAIL: "newking9088@gmail.com"` → `ADMIN_EMAIL: "CHANGE_ME_ADMIN_EMAIL"`
- Update the `# --- App identity (fixed) ---` comment to `# --- App identity ---` and add a one-line hint per key.

`tests/fixtures/config.test.yaml` keeps its real test values — only the production `config.yaml` gets the placeholders.

**●D2.** Update `.github/CODEOWNERS`:
```
# Replace @your-org/platform-team with your GitHub team or username.
* @your-org/platform-team
deployments/appset/templates/project.yaml @your-org/platform-team
.github/workflows/* @your-org/platform-team
scripts/apply-config.sh @your-org/platform-team
```

**●D3.** Update README "Step 1 – Fill in `config.yaml`":
- Add `APP_NAME`, `GITHUB_ORG`, `GITHUB_REPO`, `ADMIN_EMAIL` to the list of CHANGE_ME values that must be set.
- Delete the "Values already populated (fixed by the architecture)" section, or shrink it to only `API_PORT`, `AUTH_PORT`, `UI_PORT`, `LLM_API_URL`.

**●D4.** Update README "Prerequisites" to also list `python3` + `pyyaml` (currently only mentioned in CONTRIBUTING.md).

**●D5.** Add a `python3 --version` and `python3 -c 'import yaml'` step to the spin-up flow in CONTRIBUTING.md so users hit the requirement before step 2.5.

**●D6.** Verify by running `bash scripts/apply-config.sh` (it should exit 2 with `placeholder values` because the new CHANGE_ME keys aren't filled). Run `bash tests/run_all.sh` – should still pass because tests use `config.test.yaml`.

**●●Commit message●●**
```
chore: genericize template for forkers

- config.yaml: APP_NAME, GITHUB_ORG, GITHUB_REPO, ADMIN_EMAIL are now
  CHANGE_ME_* values; remove the misleading "fixed by the architecture"
  framing.
- CODEOWNERS: replace personal handle with @your-org/platform-team
  placeholder.
- README: surface python3+pyyaml prerequisite, list new CHANGE_ME keys
  in Step 1.
- tests/fixtures/config.test.yaml unchanged — tests still pass.
```

---

## SECTION E – Frontend health probes (one commit)

**●E1.** `deployments/charts/frontend/templates/deployment.yaml` has zero probe blocks. Add liveness and readiness probes inside the container spec, gated on values being defined (mirror the backend chart pattern):

```yaml
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

**●E2.** Add defaults to `deployments/charts/frontend/values.yaml`:

```yaml
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 10
  periodSeconds: 20
  timeoutSeconds: 3
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
```

(`/` works for an nginx-served React SPA. If a forker maps the runtime, they override per-env.)

**●E3.** Add an assertion to `tests/test_charts.sh` inside the per-env frontend block (after the existing `mountPath: /var/run` check):

```bash
assert_contains \
  "frontend ${env}/ui: Deployment includes livenessProbe" \
  "livenessProbe:" \
  "$OUT"
assert_contains \
  "frontend ${env}/ui: Deployment includes readinessProbe" \
  "readinessProbe:" \
  "$OUT"
```

**●E4.** Run `bash tests/run_all.sh` – confirm 0 failures.

**●●Commit message●●**
```
feat: add liveness/readiness probes to frontend chart

The frontend chart had no probes, so K8s marked pods Ready as soon as
the container PID started. Bad rollouts slipped through and stuck
pods were never restarted. Add backend-style probe rendering with
sensible nginx defaults (HTTP GET /), gated on values, and a
test_charts.sh assertion.
```

---

## SECTION F – Tighten security defaults (one commit)

**●F1.** Lock dev/qa/stage CORS to specific origins. In all nine `deployments/values/n/values.yaml.tpl` files for dev, qa, and stage (api, auth, ui), change:
- `cors-allow-origin: "*"` → `cors-allow-origin: "https://${APP_NAME}-<env>.${DOMAIN_SUFFIX}"`
- `cors-allow-methods: "*"` → `cors-allow-methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS"`
- `cors-expose-headers: "*"` → `cors-expose-headers: "Content-Length,Content-Range"`

(Prod is already locked — leave it.)

**●F2.** Per-app ServiceAccount. In `deployments/charts/backend/values.yaml` and `deployments/charts/frontend/values.yaml`, change `serviceAccount.create` to `true`. Add a `serviceaccount.yaml` template to both charts (standard Helm pattern):

```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "<chart>.serviceAccountName" . }}
  labels:
    {{- include "<chart>.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automount }}
{{- end }}
```

Also add `ServiceAccount` to the `namespaceResourceWhitelist` in `deployments/appset/templates/project.yaml` (group: `""`, kind: `ServiceAccount`).

In each per-env `values.yaml.tpl` (12 files), remove the `create: false` override so the chart default (`create: true`) wins.

**●F3.** Drop dead `serviceAccount.automount` config. The deployment templates read top-level `Values.automountServiceAccountToken`, not `Values.serviceAccount.automount`. Remove the `automount: true` line from every per-env `values.yaml.tpl` that has it (it does nothing).

**●F4.** Path-routing collision. In all four api `values.yaml.tpl` files, change the api ingress path regex from `/api/(.*)` to `/api/(?!auth/)(.*)` so it explicitly excludes `/api/auth/*`. Add `nginx.ingress.kubernetes.io/use-regex: "true"` annotation if not already present. The rewrite-target `/$1` remains unchanged.

**●F5.** Run `bash tests/run_all.sh` – confirm 0 failures. If `test_static.sh` has CORS assertions that need updating, update them to assert the locked form, not the wildcard form.

**●●Commit message●●**
```
security: lock dev/qa/stage CORS, per-app ServiceAccount, exclude
auth path from api regex

- CORS in dev/qa/stage now mirrors prod's locked-origin pattern;
  wildcard with cors-allow-credentials never worked in browsers anyway.
- Charts default to serviceAccount.create=true so each Release gets
  its own SA — enables per-app RBAC and workload-identity binding.
- Remove dead serviceAccount.automount overrides (the chart reads
  top-level automountServiceAccountToken).
- api ingress regex now explicitly excludes /api/auth/* so it can't
  swallow auth traffic regardless of nginx-ingress sort order.
```

---

## SECTION G – Documentation polish (one commit)

**●G1.** `SECURITY.md` – add a one-line maintainer note above the "Use GitHub's private vulnerability reporting" section:

```markdown
> **Maintainers:** enable private vulnerability reporting under
> Settings → Code security → Private vulnerability reporting before
> publishing this template.
```

**●G2.** `README.md` – under "Step 4 – Configure GitHub Environments", add a TIP block explaining how to base64-encode a kubeconfig:

```bash
# macOS/Linux
cat ~/.kube/config | base64 | pbcopy   # macOS
cat ~/.kube/config | base64 -w 0       # Linux
```

**●G3.** `README.md` – add a new section "Cluster prerequisites" before "Activating with real values" listing the one-liners to install ArgoCD and the AKV-to-Kubernetes operator (link to upstream docs for the actual install).

**●G4.** `.gitignore` – add:

```
config.yaml.local
.idea/
.vscode/
*.swp
```

**●G5.** Move `docs/notes/GITOPS_HARDEN_PROMPT.md` and `docs/notes/GITOPS_CORRECTNESS_PROMPT.md` to be referenced from `CONTRIBUTING.md` under a new "Internal prompts" section, OR delete them if they're scratch artifacts. Make the call based on whether you want forkers to see the prompt history.

**●●Commit message●●**
```
docs: polish for fresh forkers

- SECURITY.md: note that private vuln reporting must be enabled per repo.
- README: Cluster prerequisites section + base64-kubeconfig snippet.
- .gitignore: ignore IDE files and config.yaml.local.
- docs/notes: kept as audit trail, linked from CONTRIBUTING.md.
```

---

## ACCEPTANCE CRITERIA

Before opening the PR:

1. `bash tests/run_all.sh` exits 0 with `envsubst` and `helm` installed.
2. `bash scripts/apply-config.sh` against the production `config.yaml` exits with code 2 and prints `placeholder values` (because the new CHANGE_ME keys are unset). Against `tests/fixtures/config.test.yaml` it exits 0.
3. `helm template deployments/charts/backend -f deployments/values/backend/<env>/api/values.yaml` for any env contains `auth-backend.<env>-${APP_NAME}.svc.cluster.local` (verifying B1).
4. `helm template deployments/charts/frontend -f deployments/values/frontend/<env>/ui/values.yaml` contains both `livenessProbe:` and `readinessProbe:` (verifying E1).
5. `git grep newking9088` returns zero matches (verifying D1/D2).
6. `git grep 'cors-allow-origin: "\*"'` returns zero matches in any non-comment line (verifying F1).
7. The PR description groups the seven commits (A – G) with a one-line summary each, and a "Test plan" checklist that mirrors items 1–6 above.

---

## NON-GOALS

- Do **not** rewrite `apply-config.sh` to use a YAML parser unless implementing C2's overlay requires it. The current `cut`/`sed` parser is fragile but already covered by `test_parse.sh`.
- Do **not** add new charts or environments.
- Do **not** rename `appset` or change the AppSet path layout — ArgoCD ApplicationSets are watching those literal paths.
