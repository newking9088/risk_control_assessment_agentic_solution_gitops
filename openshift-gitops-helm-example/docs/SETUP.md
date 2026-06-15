# Setup guide — stand up the whole GitOps flow end-to-end

A beginner-friendly, copy-pasteable runbook for taking this template from an empty
cluster to a running app on **Red Hat OpenShift**, using **Argo CD** (OpenShift GitOps),
**Sonatype Nexus** for images, **External Secrets Operator (ESO)** for secrets, OpenShift
**Routes** for ingress, and **oauth2-proxy + Microsoft Entra OIDC** for auth. Images are
built and pushed with **podman**.

You do not need prior context — follow the sections in order. Environments are exactly
**dev**, **stage**, and **prod**.

> **Two repos, two jobs.** Keep them straight — almost every step below belongs to one
> or the other:
>
> | Repo | What it holds | What it does |
> |---|---|---|
> | **SOURCE repo** | application code + `Dockerfile`s + `examples/app-repo-build-and-push.yml` | builds the image with podman, pushes it to Nexus, then bumps the image tag in the GitOps repo |
> | **GITOPS repo** | *this* repo — Helm charts, per-env values, the Argo CD appset, deploy workflows | the single source of truth Argo CD watches and deploys from |

> **Who does what.** On most engagements the **infra/platform team** does the one-time
> cluster setup and hands you a GitOps repo already wired to Argo CD. When that's the case,
> your job shrinks to **values + secrets/vars** — you do **not** touch the cluster.
>
> | Owner | Responsibility | Where |
> |---|---|---|
> | **Infra/platform team (once)** | Install OpenShift GitOps + Argo CD and ESO; create the ESO `SecretStore` in each namespace; trust the Nexus CA; create + label the `api`/`ui` namespaces; register this repo with Argo CD; bootstrap the appset | [`PROVISIONING.md`](./PROVISIONING.md) + [`../bootstrap/`](../bootstrap) |
> | **You — app/DevOps team** | Per-env `values.yaml`; the GitHub Actions variables/secrets; the actual secret **values** in the backend the SecretStore reads | this guide (below) |

### If infra already set up the cluster — your whole job

1. **Per-env `values.yaml`** — set `image.repository`, `route.domain`,
   `secretStore.name`/`remotePrefix`, and `registryPullSecret.enabled: true` for each env
   ([§2c](#2c-valuesyaml-fields-you-edit-per-service)).
2. **Secret values in the backend** — put the keys the ExternalSecrets read
   (`<remotePrefix><NAME>`, plus `<remotePrefix>DOCKER_CONFIG_JSON` for the Nexus pull
   secret) into the secret store infra pointed the `SecretStore` at ([§3](#3-nexus-specifics)).
3. **SOURCE repo vars/secrets** — `REGISTRY`, `IMAGE_NAME`, `REGISTRY_USERNAME`,
   `REGISTRY_PASSWORD`, `GITOPS_PAT` so it can build → push → bump
   ([§2b](#2b-source-repo--consumed-by-examplesapp-repo-build-and-pushyml)).
4. **Deploy** = edit a values file (or merge the auto-opened tag-bump PR). Argo CD does the rest.

You only need the **GitOps-repo GitHub Actions vars/secrets in
[§2a](#2a-gitops-repo-this-repo--consumed-by-ci-cd-devstageprodyml--_deployyml)** (and
`KUBECONFIG_B64_<ENV>`) **if you run the appset-install workflows yourself** instead of
infra. If infra bootstraps the appset, skip §2a entirely.

---

## 1. How it connects

```
 SOURCE repo                         GITOPS repo (this repo)             OpenShift cluster
 ┌──────────────┐  podman build      ┌───────────────────────┐          ┌───────────────────┐
 │ app code +   │  + push image      │ deployments/values/    │          │ Argo CD            │
 │ Dockerfile   ├───────────────►    │   <tier>/<env>/<svc>/  │  watches │ (openshift-gitops) │
 └──────┬───────┘        │           │     values.yaml        │ ◄────────┤  - reads GIT, not  │
        │                ▼           │ image.tag: <new>       │   (git)  │    the registry    │
        │          ┌───────────┐     └───────────┬───────────┘          │  - renders charts/ │
        │          │  NEXUS    │                 │ commit (PR merge)     │  - applies to ns   │
        │ pulls    │  registry │                 ▼                       └─────────┬─────────┘
        │ image    │ (images   │     bump-image-tag.yml edits the one              │ Deployment +
        └──────────┤  only)    │◄──── values file & opens a PR                     ▼ Service +
                   └───────────┘            ▲                              ┌──────────────────┐
                         ▲                  │ workflow_dispatch            │  Route (HTTPS)   │
                         └──────────────────┘ (tag bump)                   │  → your app URL  │
```

In plain words: the **SOURCE repo** builds an image with `podman` and **pushes it to
Nexus**, then triggers a tag bump in **this GITOPS repo**. That bump is just an edit to
one `values.yaml` `image.tag` field, merged to `main`. **Argo CD in the `openshift-gitops`
namespace watches this Git repo** (not the registry), re-renders the Helm chart with the
new tag, and applies the resulting Deployment/Service/Route to the target namespace.
The registry **only stores images** — Argo CD never talks to it; the cluster's nodes pull
the image at run time using the pull secret. So "deploy" always means "change Git", and
rollback always means "revert Git".

---

## 2. Secrets & variables reference

This repo wires per-environment config as **repo-level GitHub Actions variables/secrets
suffixed `_DEV` / `_STAGE` / `_PROD`** (it does *not* use GitHub Environments). Set them
under **Settings → Secrets and variables → Actions** in each repo.

### 2a. GITOPS repo (this repo) — consumed by `ci-cd-{dev,stage,prod}.yml` → `_deploy.yml`

> **Only needed if you (not infra) run the appset-install workflows.** These workflows
> just `helm upgrade --install` the appset; if the infra team already bootstrapped it
> ([`PROVISIONING.md` §6](./PROVISIONING.md)), you can skip this whole table.

| Name | Type | Purpose | dev example | stage example | prod example |
|---|---|---|---|---|---|
| `APP_NAME` | variable | short app slug; prefixes every Argo CD resource | `rca` | `rca` | `rca` |
| `GITHUB_ORG` | variable | org that owns this gitops repo (Argo CD `repoURL`) | `acme` | `acme` | `acme` |
| `GITHUB_REPO` | variable | name of this gitops repo | `rca-gitops` | `rca-gitops` | `rca-gitops` |
| `CLUSTER_SERVER_<ENV>` | variable | Kubernetes API server Argo CD deploys to | `https://api.dev.ocp.example.com:6443` | `https://api.stage.ocp.example.com:6443` | `https://api.ocp.example.com:6443` |
| `BACKEND_HOST_<ENV>` | variable | passed to the appset as `IngressBackendHost` (see note) | `rca-dev.apps.ocp.example.com` | `rca-stage.apps.ocp.example.com` | `rca.apps.ocp.example.com` |
| `FRONTEND_HOST_<ENV>` | variable | passed to the appset as `IngressFrontendHost` (see note) | `rca-dev.apps.ocp.example.com` | `rca-stage.apps.ocp.example.com` | `rca.apps.ocp.example.com` |
| `KUBECONFIG_B64_<ENV>` | secret | base64 kubeconfig with rights to the `openshift-gitops` namespace | `<base64 kubeconfig>` | `<base64 kubeconfig>` | `<base64 kubeconfig>` |

> `<ENV>` is the literal suffix `DEV`, `STAGE`, or `PROD` (e.g. `CLUSTER_SERVER_DEV`).
> `APP_NAME`, `GITHUB_ORG`, `GITHUB_REPO` are shared across all three envs (no suffix).

> **Where the Route hostname actually comes from.** `BACKEND_HOST_<ENV>` /
> `FRONTEND_HOST_<ENV>` are forwarded by `_deploy.yml` into the appset values
> `IngressBackendHost` / `IngressFrontendHost`, which **no template currently consumes**
> (they are reserved). The hostname your Route actually serves is set by **`route.domain`**
> in each `deployments/values/<tier>/<env>/<svc>/values.yaml`. Set `route.domain` to the
> same value you put in these variables so everything is consistent.

Generate `KUBECONFIG_B64_<ENV>` like this:

```bash
# from a kubeconfig that can reach the cluster's openshift-gitops namespace
base64 -w0 ~/.kube/config        # Linux
base64 -i ~/.kube/config         # macOS (no -w flag)
```

**Config that is NOT a GitHub Actions value** (the spec also asks you to cover these — in
this repo they live elsewhere, set them there):

| Concern | Where it lives | Notes |
|---|---|---|
| `ARGOCD_NAMESPACE` | fixed `openshift-gitops` | the `_deploy.yml` `argo-namespace` input default and the appset `argocdNamespace` value; change only if your OpenShift GitOps runs elsewhere |
| `ENTRA_TENANT_ID` | `deployments/values/<tier>/<env>/<svc>/values.yaml` → `oauth2Proxy.oidcIssuerUrl`; also `deployments/appset/values.yaml` → `entra.tenantId` | the GUID in `https://login.microsoftonline.com/<tenant>/v2.0` |
| `ENTRA_AUTHORITY_HOST` | `deployments/appset/values.yaml` → `entra.authorityHost` | `login.microsoftonline.com` (or `login.microsoftonline.us` for GovCloud) |
| `GITOPS_REPO_TOKEN` | Argo CD repository Secret (see [§4](#4-argo-cd-wiring)) | **only if this gitops repo is private** — a PAT with *read* access so Argo CD can clone |

### 2b. SOURCE repo — consumed by `examples/app-repo-build-and-push.yml`

| Name | Type | Purpose | example |
|---|---|---|---|
| `REGISTRY` | env/variable | Nexus Docker host | `nexus.example.com:8443` |
| `IMAGE_NAME` (a.k.a. `IMAGE_REPO`) | env/variable | repo + service path under the registry | `rca/backend-api` |
| `REGISTRY_USERNAME` | secret | Nexus account with push rights | `svc-rca-ci` |
| `REGISTRY_PASSWORD` | secret | Nexus password/token | `<token>` |
| `GITOPS_PAT` (a.k.a. `GITOPS_DISPATCH_TOKEN`) | secret | PAT with **write** access to this gitops repo, to dispatch the tag bump | `<token>` |

> The target gitops `owner`/`repo` and the `tier`/`service`/`env` are edited **inline** in
> the `bump-gitops-tag` step of `app-repo-build-and-push.yml` (the spec calls these
> `GITOPS_ORG` / `GITOPS_REPO`). You can seed `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`
> (and an `.npmrc`) into a source repo automatically with `.github/workflows/set-existing-repo.yml`.

### 2c. `values.yaml` fields you edit per service

| Field | File | Meaning |
|---|---|---|
| `image.repository` | `charts/<tier>/values.yaml` + each `deployments/values/<tier>/<env>/<svc>/values.yaml` | Nexus path of the image (must match the pull secret's `docker-server`) |
| `route.domain` | per-env values | the Route host (leave empty for the cluster default hostname) |
| `secretStore.name` | per-env values | name of the ESO **SecretStore** (kind: `SecretStore`) in the app namespace |
| `secretStore.remotePrefix` | per-env values | key prefix in the secret backend, e.g. `rca/dev/` |
| `registryPullSecret.enabled` | `charts/backend/values.yaml` **and** `charts/frontend/values.yaml` | set `true` for private images so ESO provisions a pull Secret **in that service's namespace** and the Deployment mounts it. Each chart creates its own — a Secret in `api` is not visible in `ui` |
| `registryPullSecret.secretName` | both charts | name of the dockerconfigjson pull Secret (default `nexus-registry-secret`) |

---

## 3. Nexus specifics

**URL format.** Nexus serves Docker repositories one of two ways — pick the one your
instance uses and keep it identical everywhere:

| Form | Looks like | When |
|---|---|---|
| **port-based** | `nexus.example.com:8443/rca/backend-api` | a dedicated connector port per repo |
| **path-based** | `nexus.example.com/repository/docker-hosted/rca/backend-api` | one host, repo selected by path |

The **image tag** (`image.repository`) and the **pull secret's `docker-server`** must
match this host **exactly** — a port-based tag with a path-based secret (or vice-versa)
fails the pull even when the credentials are correct.

**The pull secret is a `.dockerconfigjson`** delivered by ESO (see
`charts/backend/templates/externalsecret-docker.yaml`). The JSON stored in your secret
backend under `<remotePrefix>DOCKER_CONFIG_JSON` looks like this for Nexus:

```json
{
  "auths": {
    "nexus.example.com:8443": {
      "username": "svc-rca-ci",
      "password": "<nexus-token>",
      "auth": "c3ZjLXJjYS1jaTo8bmV4dXMtdG9rZW4+"
    }
  }
}
```

`auth` is `base64("<username>:<password>")`. The `auths` key **is** the `docker-server`
and must equal the host in `image.repository`.

**CA trust — INFRA-TEAM prerequisite.** If Nexus uses a private/internal CA, two parties
must trust it before pulls or pushes work:

1. **The OpenShift cluster** — add the Nexus CA cluster-wide. The cluster team creates a
   ConfigMap in `openshift-config` and references it from the cluster image config:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nexus-registry-ca
     namespace: openshift-config
   data:
     # key = the Nexus host[:port] exactly as it appears in image.repository
     "nexus.example.com:8443": |
       -----BEGIN CERTIFICATE-----
       ...
       -----END CERTIFICATE-----
   ---
   apiVersion: config.openshift.io/v1
   kind: Image
   metadata:
     name: cluster
   spec:
     additionalTrustedCA:
       name: nexus-registry-ca
   ```

2. **The podman build runner** — it must trust the same CA for `podman login`/`podman push`.
   On a RHEL/self-hosted runner: drop the CA into `/etc/pki/ca-trust/source/anchors/` and
   run `update-ca-trust`. Prefer a self-hosted runner inside the Nexus network.

---

## 4. Argo CD wiring

**Where the appset lives.** The Argo CD glue is the Helm chart under
`deployments/appset` — the *only* chart you install yourself. Installing it renders:

- one **AppProject** named `<appName>-<org>-<env>` (e.g. `rca-acme-dev`), and
- two **ApplicationSets** named `<appName>-backend-<env>` and `<appName>-frontend-<env>`,

all in the **`openshift-gitops`** namespace. Each ApplicationSet's git generator globs
`deployments/values/<tier>/<env>/*`; every directory becomes one Argo CD Application named
`<appName>-<env>-<dirname>` (e.g. `rca-dev-api`, `rca-dev-ui`), deployed into a namespace
named after the directory (`api`, `ui`). Sync is automated with prune + self-heal.

**Registering a private gitops repo with Argo CD.** Argo CD must be able to clone this
repo. If it is private, create a repository Secret in `openshift-gitops` using
`GITOPS_REPO_TOKEN` (a read-only PAT):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rca-gitops-repo
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/acme/rca-gitops.git
  username: git                 # any non-empty value when using a PAT
  password: <GITOPS_REPO_TOKEN>  # PAT with read access to the repo
```

Or, equivalently, with the CLI:

```bash
argocd repo add https://github.com/acme/rca-gitops.git \
  --username git --password "$GITOPS_REPO_TOKEN"
```

**ESO SecretStore must already exist.** The charts only create `ExternalSecret` objects
that reference a **`SecretStore`** (namespaced, `kind: SecretStore`) by the name in
`secretStore.name` — so that SecretStore must exist in each app namespace (`api`, `ui`)
and point at your client's secret backend. Placeholder example (replace the provider
block with whatever backend your client runs):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager   # must equal secretStore.name in your values files
  namespace: api              # one per app namespace (api, ui), or use a ClusterSecretStore
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

---

## 5. First-time setup runbook

Do these **in order**. Steps 1 and the SecretStore/CA pieces are infra-team tasks.

1. **Infra prerequisites**
   - [ ] OpenShift **GitOps** operator installed (Argo CD running in `openshift-gitops`).
   - [ ] **External Secrets Operator** installed.
   - [ ] **Nexus CA trusted** by the cluster ([§3](#3-nexus-specifics)) — infra-team task.
   - [ ] An ESO **SecretStore** created in each app namespace, pointing at the secret
         backend, named to match `secretStore.name` ([§4](#4-argo-cd-wiring)).
2. **Create GitHub Actions variables/secrets** for the GITOPS repo from
   [§2a](#2a-gitops-repo-this-repo--consumed-by-ci-cd-devstageprodyml--_deployyml) and for
   the SOURCE repo from [§2b](#2b-source-repo--consumed-by-examplesapp-repo-build-and-pushyml).
   (No GitHub Environments needed — use the `_DEV/_STAGE/_PROD` suffixed names.)
3. **Fill `values.yaml` per env** ([§2c](#2c-valuesyaml-fields-you-edit-per-service)): set
   `image.repository`, `route.domain`, `secretStore.*`, and the pull-secret names for
   `deployments/values/<tier>/<env>/<svc>/values.yaml` and the chart defaults.
4. **Register the gitops repo with Argo CD** if private ([§4](#4-argo-cd-wiring)).
5. **Trigger the SOURCE build** (push to its `main`, or run its workflow) → it builds with
   podman and **pushes to Nexus**, then dispatches the tag bump.
6. **Confirm the tag-bump commit** landed in this gitops repo: the *Bump image tag*
   workflow opened a PR editing one `values.yaml`; **merge it**.
7. **Watch Argo CD sync** — the Application (`<appName>-<env>-<svc>`) goes
   `Synced`/`Healthy` and rolls the Deployment.
8. **Hit the Route URL** — `https://<BACKEND_HOST_<ENV>>` / `https://<FRONTEND_HOST_<ENV>>`.

You can also bootstrap an environment directly (instead of via CI) with the appset chart:

```bash
helm upgrade --install rca-appset ./deployments/appset \
  --namespace openshift-gitops --create-namespace \
  --set appName=rca \
  --set env=dev \
  --set org=acme \
  --set repo=rca-gitops \
  --set server=https://api.dev.ocp.example.com:6443
```

---

## 6. Fully worked example

Sample values: app-name **`rca`**, Nexus host **`nexus.example.com:8443`**, domain
**`apps.ocp.example.com`**, Entra tenant **`00000000-0000-0000-0000-000000000000`**.

**GITOPS repo variables/secrets**

| Name | dev | stage | prod |
|---|---|---|---|
| `APP_NAME` | `rca` | `rca` | `rca` |
| `GITHUB_ORG` | `acme` | `acme` | `acme` |
| `GITHUB_REPO` | `rca-gitops` | `rca-gitops` | `rca-gitops` |
| `CLUSTER_SERVER_<ENV>` | `https://api.dev.ocp.example.com:6443` | `https://api.stage.ocp.example.com:6443` | `https://api.ocp.example.com:6443` |
| `BACKEND_HOST_<ENV>` | `rca-dev.apps.ocp.example.com` | `rca-stage.apps.ocp.example.com` | `rca.apps.ocp.example.com` |
| `FRONTEND_HOST_<ENV>` | `rca-dev.apps.ocp.example.com` | `rca-stage.apps.ocp.example.com` | `rca.apps.ocp.example.com` |
| `KUBECONFIG_B64_<ENV>` | `<b64 dev>` | `<b64 stage>` | `<b64 prod>` |

**SOURCE repo** — `REGISTRY=nexus.example.com:8443`, `IMAGE_NAME=rca/backend-api`,
`REGISTRY_USERNAME=svc-rca-ci`, `REGISTRY_PASSWORD=<token>`, `GITOPS_PAT=<token>`.

**`deployments/values/backend/dev/api/values.yaml`** (the bits you edit):

```yaml
image:
  repository: nexus.example.com:8443/rca/backend-api
  tag: "1.4.2"
route:
  domain: rca-dev.apps.ocp.example.com
secretStore:                      # ESO SecretStore that exists in the `api` namespace
  name: aws-secrets-manager
  remotePrefix: rca/dev/
registryPullSecret:
  enabled: true                   # private image → provision the Nexus pull secret here
oauth2Proxy:
  enabled: true
  oidcIssuerUrl: "https://login.microsoftonline.com/00000000-0000-0000-0000-000000000000/v2.0"
```

Same pattern for **stage** (`rca-stage.apps.ocp.example.com`, `remotePrefix: rca/stage/`)
and **prod** (`rca.apps.ocp.example.com`, `remotePrefix: rca/prod/`). The frontend mirrors
this in its own `ui` namespace with `image.repository: nexus.example.com:8443/rca/frontend-ui`,
`route.domain` set to the frontend host, its own `secretStore`, and
`registryPullSecret.enabled: true`.

> For private images, every env you deploy needs a `secretStore` **and**
> `registryPullSecret.enabled: true` in that env's values (the shipped `dev` values leave
> `secretStore` commented out, which only works for public/anonymous images).

Resulting Argo CD objects in `openshift-gitops` for dev: AppProject `rca-acme-dev`,
ApplicationSets `rca-backend-dev` / `rca-frontend-dev`, Applications `rca-dev-api` (ns
`api`) and `rca-dev-ui` (ns `ui`).

---

## 7. Verification & troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pod stuck **`ImagePullBackOff`** | Cluster doesn't trust the Nexus CA; `image.repository` host ≠ pull-secret `docker-server`; or wrong/missing pull secret | Confirm the `additionalTrustedCA` ConfigMap ([§3](#3-nexus-specifics)); make the image host and the `auths` key identical; check `registryPullSecret.enabled` + the SecretStore has `DOCKER_CONFIG_JSON` |
| Argo CD app **`ComparisonError`** / "repository not accessible" | Argo CD can't clone the gitops repo | Create/fix the repository Secret with a valid `GITOPS_REPO_TOKEN`, or `argocd repo add` ([§4](#4-argo-cd-wiring)); verify the `repoURL` org/repo |
| `ExternalSecret` **`SecretSyncError`** / `SecretSyncedError` | SecretStore missing in the namespace, wrong `secretStore.name`, or the backend key/permissions are off | Ensure a `kind: SecretStore` named exactly `secretStore.name` exists in that namespace; check `remotePrefix` + that the backing key exists and ESO's identity can read it |
| **oauth2-proxy redirect loop** | Entra app registration redirect URI doesn't match the Route | Register `https://<route-host>/oauth2/callback` as a redirect URI in Entra; confirm `oidcIssuerUrl` uses the correct tenant GUID |
| Route returns 503 / app not reachable | Deployment not Healthy, or `route.domain` mismatch | Check the Deployment/pod status and that `route.domain` matches the `BACKEND_HOST_<ENV>` / `FRONTEND_HOST_<ENV>` you advertised |

---

## Copy this checklist before you deploy

```
INFRA (one-time, infra team)
  [ ] OpenShift GitOps operator installed (Argo CD in openshift-gitops)
  [ ] External Secrets Operator installed
  [ ] Nexus internal CA trusted: ConfigMap in openshift-config + Image/cluster additionalTrustedCA
  [ ] podman build runner trusts the same Nexus CA
  [ ] ESO SecretStore exists in each app namespace (api, ui), name = secretStore.name

GITOPS repo (this repo) — Settings → Secrets and variables → Actions
  [ ] Variables: APP_NAME, GITHUB_ORG, GITHUB_REPO
  [ ] Variables per env: CLUSTER_SERVER_<ENV>, BACKEND_HOST_<ENV>, FRONTEND_HOST_<ENV>
  [ ] Secrets per env: KUBECONFIG_B64_<ENV>
  [ ] (private repo) Argo CD repository Secret created with GITOPS_REPO_TOKEN
  [ ] values.yaml per env: image.repository, route.domain, secretStore.name/remotePrefix,
      registryPullSecret.enabled (both charts, for private images), oauth2Proxy.oidcIssuerUrl

SOURCE repo — Settings → Secrets and variables → Actions
  [ ] REGISTRY (nexus host:port), IMAGE_NAME (repo/service)
  [ ] Secrets: REGISTRY_USERNAME, REGISTRY_PASSWORD, GITOPS_PAT
  [ ] bump-gitops-tag step edited with the gitops owner/repo + tier/service/env

GO
  [ ] Push SOURCE → image lands in Nexus
  [ ] Merge the auto-opened tag-bump PR in this repo
  [ ] Argo CD app Synced + Healthy
  [ ] Route URL responds over HTTPS
```
