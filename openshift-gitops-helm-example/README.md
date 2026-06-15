# openshift-gitops-helm-example

A self-contained GitOps template for deploying a **frontend + backend** application to
**Red Hat OpenShift** using Helm charts driven by **Argo CD ApplicationSets**
(OpenShift GitOps operator).

Use it as the starting point for a dedicated *GitOps repo*: the repo that holds your
deployment configuration, separate from your application source repos.

---

## How it works

```
                         (1) one-time bootstrap
  helm install ────────► deployments/appset ──renders──► 1 AppProject
                                                         2 ApplicationSets (backend, frontend)
                                                              │
                         (2) continuous reconciliation        ▼
  git push to this repo ◄──── Argo CD git generator watches deployments/values/<tier>/<env>/*
                                                              │ one Application per directory
                                                              ▼
                              Application: source = charts/<tier>  (HEAD of this repo)
                                           values = deployments/values/<tier>/<env>/<svc>/values.yaml
                                           destination namespace = <svc>  (api, ui, …)
                                                              │
                         (3) rendered workload                ▼
                              Deployment + Service + Route + HPA + ExternalSecrets
```

Three layers, each with a single job:

| Layer | Path | Changes when |
|---|---|---|
| **Charts** (how to deploy) | `charts/backend`, `charts/frontend` | Deployment logic changes (rare, review carefully) |
| **Values** (what, per env) | `deployments/values/<tier>/<env>/<svc>/values.yaml` | Every release — image tags, env vars, scaling |
| **Glue** (Argo CD wiring) | `deployments/appset` | Almost never after bootstrap |

Key mechanics:

- The ApplicationSet **git generator** globs `deployments/values/<tier>/<env>/*`.
  Every directory it finds becomes one Argo CD Application, named
  `<appName>-<env>-<dirname>` and deployed into namespace `<dirname>`.
  **Adding a service instance = adding a values directory. No chart or appset change.**
- Each Application sources the chart from `charts/<tier>` at `HEAD` of this repo and
  layers the per-env values file on top of the chart's `values.yaml` defaults.
- `syncPolicy.automated` with `prune` + `selfHeal` is enabled: whatever is merged to
  the default branch **is** the cluster state. Rollback = `git revert`.
- The AppProject (`<appName>-<org>-<env>`) scopes all generated Applications.

> `charts/` is intentionally at the repo top level, not under `deployments/`.
> A `charts/` directory *inside* a Helm chart means "bundled subchart dependencies";
> keeping them separate keeps backend/frontend independently lintable and templatable.

## Repository layout

```
charts/
  backend/        Helm chart — backend API service
  frontend/       Helm chart — frontend UI service
deployments/
  appset/         Argo CD AppProject + ApplicationSet chart (the only chart YOU install)
  values/         Per-environment values files (plain YAML, no templating)
    backend/{dev,stage,prod}/api/values.yaml
    frontend/{dev,stage,prod}/ui/values.yaml
.github/workflows/
  _deploy.yml             Reusable deploy workflow (workflow_call)
  bump-image-tag.yml      GitOps CD: bump image.tag via PR (manual dispatch)
  ci-cd-dev.yml           Installs/updates the dev appset on push to main
  ci-cd-stage.yml         Manual deploy to stage
  ci-cd-prod.yml          Manual deploy to prod
  set-existing-repo.yml   One-time: seed an app repo with Nexus credentials
examples/
  app-repo-build-and-push.yml   Reference CI workflow for your APPLICATION source repos
bootstrap/
  01-gitops-operator-subscription.yaml   Install the OpenShift GitOps operator
  02-target-namespaces.yaml              Create + label the api/ui namespaces for Argo CD
  03-argocd-repo-secret.yaml             Register this repo with Argo CD (private repos)
docs/
  PROVISIONING.md               Cluster bootstrap: operator → Argo CD → Helm (start here)
  SETUP.md                      App config: GitHub vars/secrets, per-env values, Nexus
tests/
  test-openshift-compat.sh      OpenShift compatibility test suite (see Testing)
```

---

## Taking this template into use

> **New here? Follow the two guides in `docs/`:**
> [`docs/PROVISIONING.md`](docs/PROVISIONING.md) does the cluster bootstrap (install the
> OpenShift GitOps operator, wire Argo CD to GitHub, deploy the Helm charts) with
> copy-paste manifests in [`bootstrap/`](bootstrap); [`docs/SETUP.md`](docs/SETUP.md)
> covers the app config (GitHub Actions vars/secrets, per-env values, Nexus credentials).
> The section below is the condensed version.

### 0. Prerequisites

- OpenShift cluster with the **OpenShift GitOps** operator installed
  (Argo CD running in the `openshift-gitops` namespace).
- **External Secrets Operator** — optional; only needed if you use `secrets:` +
  `secretStore:` in values (templates render nothing when omitted).
- `helm` v3 locally for bootstrap/verification.

### 1. Copy and rename

Copy this directory to the root of a new Git repository (e.g. `my-app-gitops`).
The git generator paths assume `deployments/values/...` sits at the **repo root** —
if you nest the template inside a subdirectory, update `directories[].path` and
`helm.valueFiles` in `deployments/appset/templates/appset.*.yaml` accordingly.

### 2. Replace placeholders

Search for `<` placeholders and `CHANGE_ME`:

| File | Setting | Set to |
|---|---|---|
| `charts/backend/values.yaml` | `image.repository` | your backend image in Nexus, e.g. `nexus.example.com:8443/backend-api` |
| `charts/frontend/values.yaml` | `image.repository` | your frontend image in Nexus |
| `charts/backend/values.yaml` | `registryPullSecret` | set `enabled: true` to provision the Nexus pull secret via ESO |
| `charts/frontend/values.yaml` | `registryPullSecret` | set `enabled: true` to provision the Nexus pull secret via ESO |
| `deployments/appset/values.yaml` | `org`, `repo` | GitHub org and the name of *this* gitops repo |
| `deployments/appset/values.yaml` | `appName` | short app name — prefixes every resource |

Also review per chart: `service.targetPort` (your container port), the
`livenessProbe`/`readinessProbe` paths (default `/health`), and `resources`.

> `entra.*`, `IngressBackendHost`, and `IngressFrontendHost` in
> `deployments/appset/values.yaml` are currently **reserved but unused** — no
> template consumes them. Wire them into your templates or delete them; route
> hostnames are actually controlled by `route.domain` in the per-env values files.

### 3. Set per-environment values

Each `deployments/values/<tier>/<env>/<svc>/values.yaml` overrides the chart
defaults for one service instance in one environment. Typical contents:

```yaml
image:
  tag: "1.4.2"            # what bump-image-tag.yml rewrites

env:                       # plain env vars for the container
  LOG_LEVEL: INFO
  APP_ENV: prod

route:
  domain: my-app.apps.prod-cluster.example.com

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6

secrets:                   # names of secrets the app needs (see Secrets below)
  - DATABASE_URL
secretStore:
  name: aws-secrets-manager
  remotePrefix: myapp/prod/
```

Keep these files **plain YAML** — they are read by Argo CD as Helm value files,
never templated themselves.

### 4. Configure GitHub Actions (optional but recommended)

Repository **variables**:

| Variable | Description |
|---|---|
| `APP_NAME` | Same as `appName` above |
| `GITHUB_ORG` / `GITHUB_REPO` | Org and name of this gitops repo |
| `CLUSTER_SERVER_DEV` / `_STAGE` / `_PROD` | Kubernetes API server URL per cluster |
| `BACKEND_HOST_DEV` / `_STAGE` / `_PROD` | Backend Route hostname per env |
| `FRONTEND_HOST_DEV` / `_STAGE` / `_PROD` | Frontend Route hostname per env |

Repository **secrets**:

| Secret | Description |
|---|---|
| `KUBECONFIG_B64_DEV` / `_STAGE` / `_PROD` | Base64-encoded kubeconfig with rights to the Argo CD namespace |

### 5. Bootstrap each environment (one-time)

Via CI: push to `main` (dev installs automatically), or run *Deploy — stage/prod*
manually from the Actions tab.

Or by hand:

```bash
helm upgrade --install my-app-appset ./deployments/appset \
  --namespace openshift-gitops --create-namespace \
  --set appName=my-app \
  --set env=dev \
  --set org=my-org \
  --set repo=my-app-gitops \
  --set server=https://api.my-cluster.example.com:6443
```

`server` is the destination cluster as known to Argo CD — keep the default
`https://kubernetes.default.svc` when Argo CD deploys to its own cluster.

### 6. Verify

In the Argo CD console you should see the AppProject `my-app-my-org-dev` and one
Application per values directory (e.g. `my-app-dev-api`, `my-app-dev-ui`), each
syncing into a namespace named after the directory (`api`, `ui`).

---

## Day-2 operations

### Releasing a new image (the GitOps CD loop)

1. Your **application repo** builds and pushes the image — see
   `examples/app-repo-build-and-push.yml` for a reference workflow; copy it into the
   app repo, not this one.
2. In *this* repo, run the **Bump image tag** workflow (tier, service, env, new tag).
   It edits the one values file and opens a PR.
3. Merge the PR. Argo CD detects the change at `HEAD` and rolls the Deployment.
   To roll back, revert the PR.

You can also chain step 2 automatically: have the app repo's pipeline trigger
`bump-image-tag.yml` here via `gh workflow run` / `repository_dispatch`.

### Adding an environment

1. Create `deployments/values/backend/<env>/api/values.yaml` and
   `deployments/values/frontend/<env>/ui/values.yaml`.
2. Add a `ci-cd-<env>.yml` workflow (copy `ci-cd-stage.yml`) plus the matching
   GitHub variables/secrets, or bootstrap by hand with `--set env=<env>`.

### Adding another service instance

Add a directory under the matching tier and env — e.g.
`deployments/values/backend/dev/worker/values.yaml` creates Application
`<appName>-dev-worker` in namespace `worker`, rendered from `charts/backend`.
A genuinely different *kind* of service warrants a new chart: copy
`charts/backend`, rename via `Chart.yaml`/`_helpers.tpl`, and add a third
ApplicationSet template in `deployments/appset/templates/`.

### Secrets (External Secrets Operator)

Listing names under `secrets:` with a `secretStore:` configured renders one
`ExternalSecret` per name; ESO materialises it as a Kubernetes Secret which the
Deployment injects as an env var of the same name. The remote key is
`<remotePrefix><NAME>` (e.g. `myapp/prod/DATABASE_URL`). Without `secretStore`,
nothing renders — charts degrade gracefully.

### OIDC authentication (oauth2-proxy sidecar)

Set `oauth2Proxy.enabled: true` plus `oidcIssuerUrl` in a values file to add an
oauth2-proxy sidecar; the Route automatically retargets to it so all external
traffic authenticates before reaching the app. Client id/secret/cookie-secret come
from the `<fullname>-oauth2-proxy` secret (rendered by
`oauth2proxy-externalsecret.yaml` when a `secretStore` is configured).

---

## CI/CD workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `ci-cd-dev.yml` | push to `main`, manual | Installs/updates the **dev** appset release |
| `ci-cd-stage.yml` / `ci-cd-prod.yml` | manual | Same for stage/prod — manual gate by design |
| `_deploy.yml` | called by the above | Checkout → setup helm → write kubeconfig → `helm upgrade --install` the appset |
| `bump-image-tag.yml` | manual | Rewrites `image.tag` in one values file, opens a PR |
| `set-existing-repo.yml` | manual | One-time: copies this repo's Nexus credentials (`REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `NPMRC`) into a target app repo |

Note these workflows only install the **appset chart** (the Argo CD wiring).
Application rollout is Argo CD's job, driven purely by what is merged to `main`.

## Testing

```bash
# Static checks
helm lint charts/backend charts/frontend deployments/appset

# Full OpenShift compatibility suite (lint + render every env values file +
# Route/SCC assertions + appset wiring checks)
bash tests/test-openshift-compat.sh
```

The test suite verifies, among other things, that rendered manifests are
compatible with OpenShift's **restricted-v2 SCC** — see next section.

## Nexus on OpenShift

These charts pull application images from a private **Sonatype Nexus** Docker registry
(the client standard — not JFrog Artifactory). Building/pushing those images uses
**podman/buildah**, never the docker CLI (see `examples/app-repo-build-and-push.yml`).
Three prerequisites have to line up — none are manifests in this repo:

1. **The cluster must trust the Nexus internal CA.** If Nexus is served with a private
   CA, OpenShift cannot pull from it until that CA is added cluster-wide. The cluster
   team adds the CA bundle as a ConfigMap in the `openshift-config` namespace and
   references it from the cluster image config:

   ```yaml
   # ConfigMap (openshift-config namespace) holding the Nexus CA bundle
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nexus-registry-ca
     namespace: openshift-config
   data:
     # key = the Nexus registry host[:port], exactly as it appears in image.repository
     "nexus.example.com:8443": |
       -----BEGIN CERTIFICATE-----
       ...
       -----END CERTIFICATE-----
   ---
   # Patch the cluster-wide image config to trust it (cluster-admin task)
   apiVersion: config.openshift.io/v1
   kind: Image
   metadata:
     name: cluster
   spec:
     additionalTrustedCA:
       name: nexus-registry-ca
   ```

2. **Confirm the Nexus Docker URL format.** Nexus publishes Docker repositories either
   *port-based* (`nexus.example.com:8443/<image>`, a connector per repo) or *path-based*
   (`nexus.example.com/repository/docker-hosted/<image>`, one host, path per repo). Pick
   the one your instance uses and keep it identical in three places: `image.repository`
   in the chart/env values, the `docker-server` inside the pull secret's
   `.dockerconfigjson`, and the CA ConfigMap key above. A mismatch (e.g. port-based image
   tag vs path-based secret) fails the pull even when credentials are correct.

3. **The build runner must trust the Nexus CA too.** `podman login`/`podman push` in the
   app-repo workflow only succeed if the runner trusts the same CA. On a self-hosted
   runner inside the Nexus network, install the CA into the host trust store
   (`/etc/pki/ca-trust/source/anchors/` + `update-ca-trust` on RHEL). Prefer a
   self-hosted runner so it can reach the internal Nexus host at all.

The pull secret itself is delivered through the External Secrets Operator. Because each
service is deployed into its **own namespace** (`api` for the backend, `ui` for the
frontend), each chart provisions its **own** pull secret in that namespace — a Secret in
`api` is not visible to pods in `ui`. So enable `registryPullSecret` in **both**
`charts/backend/values.yaml` and `charts/frontend/values.yaml` (with a `secretStore`
configured for that env). ESO then materialises the `.dockerconfigjson` (containing the
Nexus credentials) as the `nexus-registry-secret` Secret in each namespace, and each
Deployment mounts its own automatically. This requires an ESO `SecretStore` to exist in
both namespaces.

### One-time: seed an app repo with Nexus credentials (`set-existing-repo.yml`)

Each application repo that builds images (via `examples/app-repo-build-and-push.yml`)
needs three Nexus secrets — `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, and `NPMRC`
(an `.npmrc` pointing at the **Nexus npm registry**, used for private `npm install`).
Rather than pasting them into every repo by hand, the `set-existing-repo.yml` workflow
copies them from *this* repo into a target repo. Run it **once per app repo** (re-run to
rotate values):

1. **On this GitOps repo** (Settings → Secrets and variables → Actions), set once:
   - Secrets: `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `NPMRC`, and `REPO_ADMIN_PAT`
     (a PAT allowed to write secrets on the target repo — classic `repo` scope, or a
     fine-grained token with *Secrets: Read/Write* + *Administration* on the target).
   - Variable (optional): `REGISTRY` — the Nexus Docker host (port- or path-based).

   `NPMRC` must target Nexus, not the public registry, e.g.:

   ```ini
   registry=https://nexus.example.com/repository/npm-group/
   //nexus.example.com/repository/npm-group/:_authToken=<nexus-npm-token>
   ```

2. **Run the workflow:** Actions → *Set up existing app repo (Nexus credentials)* → *Run
   workflow*, and enter the target repo as `owner/name` (e.g. `acme/payments-api`).

3. The workflow uses the GitHub CLI to write `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`,
   and `NPMRC` (plus the optional `REGISTRY` variable) onto the target repo. Its
   `app-repo-build-and-push.yml` can then `podman login`/`podman push` to Nexus and
   install private npm packages with no manual secret entry.

## OpenShift specifics

These charts target OpenShift, not generic Kubernetes:

- **Route, not Ingress** — external exposure uses `route.openshift.io/v1` Routes
  with TLS termination (`edge` by default; `passthrough`/`reencrypt` supported via
  `route.tls.termination`). Leave `route.domain` empty to get the cluster default
  hostname.
- **restricted-v2 SCC compliance** — security contexts set `runAsNonRoot`,
  `allowPrivilegeEscalation: false`, drop ALL capabilities, `RuntimeDefault`
  seccomp, and deliberately do **not** set `runAsUser`/`fsGroup`: OpenShift assigns
  UIDs from a per-namespace range and rejects pods that pin them. Your container
  images must therefore run as an arbitrary non-root UID (group-writable paths,
  no `USER 0`).
- **Read-only root filesystem** — containers get `readOnlyRootFilesystem: true`
  with an `emptyDir` mounted at `/tmp`. Add more `volumes`/`volumeMounts` in values
  if your app writes elsewhere.
