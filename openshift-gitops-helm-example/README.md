# openshift-gitops-helm-example

A self-contained GitOps template for deploying a **frontend + backend** application to **Red Hat OpenShift** using Helm charts driven by ArgoCD ApplicationSets.

## Repository layout

```
charts/
  backend/        Helm chart — backend API service
  frontend/       Helm chart — frontend UI service
deployments/
  appset/         ArgoCD AppProject + ApplicationSet chart (deploy this one)
  values/         Per-environment values files (plain YAML, no templating)
    backend/{dev,stage,prod}/api/values.yaml
    frontend/{dev,stage,prod}/ui/values.yaml
.github/workflows/
  _deploy.yml             Reusable deploy workflow (workflow_call)
  bump-image-tag.yml      GitOps CD: bump image.tag via PR
  ci-cd-dev.yml           Auto-deploy on push to main
  ci-cd-stage.yml         Manual deploy to stage
  ci-cd-prod.yml          Manual deploy to prod
examples/
  app-repo-build-and-push.yml   Reference workflow for application source repos
```

## Prerequisites

- OpenShift cluster with the **OpenShift GitOps** operator installed (`openshift-gitops` namespace)
- **External Secrets Operator** installed (optional — charts degrade gracefully when `secretStore` is omitted)
- GitHub Actions secrets/variables configured (see below)

## Required GitHub Actions variables

| Variable | Description |
|---|---|
| `APP_NAME` | Name prefix for all resources |
| `GITHUB_ORG` | GitHub organisation |
| `GITHUB_REPO` | This repository name |
| `CLUSTER_SERVER_DEV` / `_STAGE` / `_PROD` | Kubernetes API server URL |
| `BACKEND_HOST_DEV` / `_STAGE` / `_PROD` | Backend Route hostname |
| `FRONTEND_HOST_DEV` / `_STAGE` / `_PROD` | Frontend Route hostname |

## Required GitHub Actions secrets

| Secret | Description |
|---|---|
| `KUBECONFIG_B64_DEV` / `_STAGE` / `_PROD` | Base64-encoded kubeconfig per cluster |

## Manual deploy

```bash
helm upgrade --install my-app-appset ./deployments/appset \
  --namespace openshift-gitops --create-namespace \
  --set appName=my-app \
  --set env=dev \
  --set org=my-org \
  --set repo=my-gitops-repo \
  --set server=https://api.my-cluster.example.com:6443 \
  --set IngressBackendHost=my-app-dev.apps.my-cluster.example.com \
  --set IngressFrontendHost=my-app-dev.apps.my-cluster.example.com
```

## Linting

```bash
helm lint charts/backend
helm lint charts/frontend
helm lint deployments/appset
```
