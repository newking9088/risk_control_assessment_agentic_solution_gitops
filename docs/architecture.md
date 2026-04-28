# Architecture

## System Overview

The RCA Platform deploys three services across four environments using a GitOps model. Configuration lives in this repo; secrets live in Azure Key Vault.

```
┌─────────────────────────────────────────────────────────────────┐
│  This Repository (GitOps)                                       │
│                                                                 │
│  config.yaml ──► apply-config.sh ──► values.yaml (per env)     │
│                                   └──► ci-cd-*.yaml (workflows) │
└─────────────────────────────────────────────────────────────────┘
         │
         │ git push / PR merge
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions CI/CD                                           │
│                                                                 │
│  helm upgrade --install  deployments/appset/  ──► ArgoCD NS    │
└─────────────────────────────────────────────────────────────────┘
         │
         │ ArgoCD watches deployments/values/<env>/
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                             │
│                                                                 │
│  ArgoCD ApplicationSet                                          │
│    └── Application: api   (Helm: charts/backend)               │
│    └── Application: auth  (Helm: charts/backend)               │
│    └── Application: ui    (Helm: charts/frontend)              │
│                                                                 │
│  AKV-to-Kubernetes operator                                     │
│    └── AzureKeyVaultSecret ──► Kubernetes Secret               │
└─────────────────────────────────────────────────────────────────┘
         │
         │ reads at pod startup
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure Key Vault                                                │
│                                                                 │
│  ADMIN-DATABASE-URL  ·  OPENAI-API-KEY                         │
│  STORAGE-PRIMARY-CONNECTION-STRING  ·  BETTER-AUTH-SECRET      │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Role |
|-----------|------|
| **ArgoCD** | GitOps controller — watches this repo, syncs Kubernetes state to match |
| **ApplicationSet** | Generates one ArgoCD Application per service per environment |
| **AppProject** | ArgoCD RBAC boundary — limits source repos, destinations, and allowed resource kinds |
| **Helm** | Kubernetes manifest templating for backend and frontend charts |
| **AKV-to-Kubernetes** | Syncs secrets from Azure Key Vault into Kubernetes Secrets |
| **GitHub Actions** | CI testing + CD triggering (`helm upgrade --install` for the AppSet) |

## Data-flow: config → cluster

1. Developer fills in `config.yaml` with real infrastructure values.
2. `scripts/apply-config.sh` runs `envsubst` to substitute variables into every `.tpl` file, producing `values.yaml` files under `deployments/values/` and workflow files under `.github/workflows/`.
3. Developer commits generated files and pushes.
4. On push to `main` (dev) or `workflow_dispatch` (qa/stage/prod), GitHub Actions runs `helm upgrade --install` against `deployments/appset/`, deploying the ArgoCD ApplicationSet.
5. ArgoCD detects changes in `deployments/values/<env>/` and syncs each Application using the appropriate Helm chart + values file.
6. At pod startup, the AKV-to-Kubernetes operator resolves `AzureKeyVaultSecret` resources, pulling secrets from Azure Key Vault into Kubernetes Secrets that pods mount as environment variables.

## Environment promotion path

```
dev (auto on PR merge) ──► qa (manual dispatch) ──► stage (manual dispatch) ──► prod (manual dispatch + approval)
```

- **dev/qa** use `KEYVAULT_NAME_DEV`
- **stage/prod** use `KEYVAULT_NAME_PROD`
- **prod** requires manual reviewer approval in GitHub Environments before the deploy job runs

## Services

| Service | Chart | Port | Description |
|---------|-------|------|-------------|
| `api` | `charts/backend` | 8000 | FastAPI backend — owns the registry pull-secret |
| `auth` | `charts/backend` | 8001 | Better Auth service |
| `ui` | `charts/frontend` | 8080 | React SPA served by nginx |
