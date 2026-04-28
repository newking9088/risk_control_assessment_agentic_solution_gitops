# RCA Platform — GitOps Repository

Declarative Kubernetes deployment configuration for the AI-Driven Risk & Control Assessment (RCA) platform. Manages three services (FastAPI backend, Better Auth, React frontend) across four environments using ArgoCD + Helm. Secrets sourced from Azure Key Vault via the AKV-to-Kubernetes operator.

**App repo:** [risk_control_assessment_agentic_solution](https://github.com/newking9088/risk_control_assessment_agentic_solution)

---

## Repository structure

```
config.yaml                          ← Single source of truth for all configurable values
scripts/
  apply-config.sh                    ← Generates values.yaml files from .tpl templates
deployments/
  appset/                            ← ArgoCD ApplicationSets (one per environment)
    Chart.yaml
    values.yaml.tpl                  ← Template; apply-config.sh generates values.yaml
    templates/
      project.yaml                   ← ArgoCD AppProject per env
      appset.backend.yaml            ← ApplicationSet for API + Auth services
      appset.frontend.yaml           ← ApplicationSet for React UI
  charts/
    backend/                         ← Shared Helm chart for API and Auth services
    frontend/                        ← Helm chart for the React SPA
  values/
    backend/{dev,qa,stage,prod}/
      api/values.yaml.tpl            ← FastAPI backend values per env
      auth/values.yaml.tpl           ← Better Auth values per env
    frontend/{dev,qa,stage,prod}/
      ui/values.yaml.tpl             ← Frontend values per env
.github/workflows/
  ci-cd-dev.yaml.tpl                 ← Template; generated ci-cd-dev.yaml auto-deploys on PR merge to main
  ci-cd-qa.yaml.tpl                  ← Template; generated ci-cd-qa.yaml is manual dispatch
  ci-cd-stage.yaml.tpl               ← Template; generated ci-cd-stage.yaml is manual dispatch
  ci-cd-prod.yaml.tpl                ← Template; generated ci-cd-prod.yaml is manual dispatch + approval gate
```

---

## Environment overview

| Environment | Domain | Key Vault | Trigger |
|---|---|---|---|
| dev | `{APP_NAME}-dev.{DOMAIN_SUFFIX}` | `KEYVAULT_NAME_DEV` | PR merge to `main` |
| qa | `{APP_NAME}-qa.{DOMAIN_SUFFIX}` | `KEYVAULT_NAME_DEV` | Manual dispatch |
| stage | `{APP_NAME}-stage.{DOMAIN_SUFFIX}` | `KEYVAULT_NAME_PROD` | Manual dispatch |
| prod | `{APP_NAME}.{DOMAIN_SUFFIX}` | `KEYVAULT_NAME_PROD` | Manual dispatch + approval |

---

## Activating with real values

### Step 1 — Fill in `config.yaml`

Open `config.yaml` and replace every `CHANGE_ME_*` value:

```yaml
REGISTRY_URL: "CHANGE_ME_REGISTRY_URL"       # e.g. ghcr.io/newking9088 or myacr.azurecr.io/myteam
PULL_SECRET_NAME: "CHANGE_ME_PULL_SECRET_NAME"
DOMAIN_SUFFIX: "CHANGE_ME_DOMAIN_SUFFIX"     # e.g. apps.example.com
KEYVAULT_NAME_DEV: "CHANGE_ME_KEYVAULT_DEV"
KEYVAULT_NAME_PROD: "CHANGE_ME_KEYVAULT_PROD"
DOCKER_KEYVAULT_NAME: "CHANGE_ME_DOCKER_KV"
```

Values already populated (fixed by the architecture):
- `APP_NAME`, `GITHUB_ORG`, `GITHUB_REPO`
- `API_PORT` (8000), `AUTH_PORT` (8001), `UI_PORT` (8080)
- `LLM_API_URL`, `ADMIN_EMAIL`

### Step 2 — Generate values files

```bash
bash scripts/apply-config.sh
```

This reads `config.yaml` and produces a `values.yaml` alongside each `.tpl` file under `deployments/values/`.

> **Requires:** `envsubst` — install via `brew install gettext` (Mac), `apt install gettext` (Linux), or `winget install GNU.gettext` (Windows).

### Step 2.5 — Verify

Run the test suite to confirm every template renders cleanly and no config keys are dead:

```bash
bash tests/run_all.sh
```

Covers: config.yaml parse logic, static repo structure, apply-config.sh end-to-end substitution, and Helm rendering. The apply-config and Helm suites auto-skip if `envsubst` or `helm` is not installed.

### Step 3 — Commit the generated files

```bash
git add deployments/values/ deployments/appset/values.yaml .github/workflows/ci-cd-*.yaml
# or: find deployments/values deployments/appset .github/workflows \
#         -name '*.yaml' ! -name '*.tpl' -print0 | xargs -0 git add
git commit -m "chore: populate environment values from config"
git push
```

### Step 4 — Configure GitHub Environments

In **GitHub → Settings → Environments**, create four environments: `dev`, `qa`, `stage`, `prod`.

For each, set:

| Type | Name | Value |
|---|---|---|
| Secret | `KUBECONFIG` | Base64-encoded kubeconfig for the cluster |
| Variable | `DOMAIN_SUFFIX` | Your domain suffix |
| Variable | `CLUSTER_SERVER` | ArgoCD destination server URL |

For `prod`, enable **Required reviewers** to enforce a manual approval gate before deployment.

---

## How deployments work

1. A CI/CD workflow runs `helm upgrade --install` against `deployments/appset/` in the `argocd` namespace.
2. This creates/updates ArgoCD **ApplicationSets** which watch `deployments/values/<env>/` for changes.
3. ArgoCD syncs each service (api, auth, ui) using `deployments/charts/<backend|frontend>/` + the matching `values.yaml`.
4. Secrets are pulled from Azure Key Vault by the [AKV-to-Kubernetes operator](https://akv2k8s.io/) via `AzureKeyVaultSecret` resources.
5. The `api` service is the sole owner of the registry pull-secret; `auth` and `ui` mount it but do not create it.

---

## Secrets managed via Azure Key Vault

The following secrets must exist in the Key Vault before deploying:

| Secret name | Used by | Environment |
|---|---|---|
| `ADMIN-DATABASE-URL` | API, Auth | All |
| `OPENAI-API-KEY` | API | All |
| `STORAGE-PRIMARY-CONNECTION-STRING` | API | All |
| `BETTER-AUTH-SECRET` | Auth | All |

---

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- [AKV-to-Kubernetes operator](https://akv2k8s.io/) installed in the cluster
- Azure Key Vault(s) provisioned with secrets above
- Container registry accessible from the cluster
- `helm` CLI (v3+) available in CI runner

---

## Branch protection

Recommended settings in **GitHub → Settings → Branches → main**:

- Require pull request reviews before merging (1+ approver)
- Require status checks to pass: **`CI Tests / tests`** (the `ci-tests.yaml` workflow)
- Require branches to be up to date before merging
- Restrict who can push directly to `main`

---

## OIDC migration path

Each `ci-cd-*.yaml.tpl` contains a commented-out `id-token: write` permission. When you're ready to use workload-identity federation instead of a `KUBECONFIG` secret:

1. Uncomment `id-token: write` in each workflow tpl.
2. Configure a federated credential in your cloud identity provider.
3. Replace the `Set up kubeconfig` step with your OIDC login step.
4. Remove the `KUBECONFIG` secret from GitHub Environments once confirmed working.

---

## Threat model

This repository contains **configuration only** — no runtime secrets are committed. The threat surface is:

| Threat | Mitigation |
|--------|------------|
| Plaintext secrets in this repo | `config.yaml` only holds infra placeholders; secrets stay in Azure Key Vault and are resolved at deploy time |
| Compromised CI runner exfiltrates `KUBECONFIG` | Migrate to OIDC workload-identity federation (see "OIDC migration path"); rotate kubeconfig on suspicion; runner `permissions: contents: read` |
| Workflow injection via PR title/branch | All `uses:` lines SHA-pinned; `permissions: contents: read` is the workflow default |
| Wildcard ArgoCD access | `AppProject` restricts `sourceRepos`, `destinations` (single namespace), `clusterResourceWhitelist: []`, and an explicit `namespaceResourceWhitelist` |
| Tampered chart entry | `image.pullPolicy: Always` plus per-env prod `WARNING: pin to immutable SHA digest`; CI test asserts the warning is present |
| Container escape via privileged process | `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault` |
| Unreviewed prod changes | Branch protection + required reviewer + GitHub Environment manual approval gate |
| Stale GitHub Actions vulnerability | Dependabot weekly + SHA-pinned actions |

---

## Documentation

- [Architecture](docs/architecture.md) — system diagram, component overview, data-flow
- [Runbook](docs/runbook.md) — rollbacks, secret rotation, adding environments, ingress discovery
- [Contributing](CONTRIBUTING.md) — dev setup, contribution workflow, commit conventions
- [Security](SECURITY.md) — vulnerability reporting, scope, response SLA
