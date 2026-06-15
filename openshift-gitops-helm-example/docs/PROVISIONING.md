# Provisioning OpenShift GitOps + Argo CD + Helm — from zero

A copy-paste, DevOps-perspective runbook for standing up the *cluster side* of this
template: install the **Red Hat OpenShift GitOps** operator, wire **Argo CD** to a
**GitHub** repo, and let it deploy the **Helm charts** in this repo to OpenShift.

This guide is the **platform/infra half** and is aimed at the **infra/platform team** —
it needs `cluster-admin`. On most engagements infra runs this once and hands the app team
a GitOps repo already wired to Argo CD. **App/DevOps teams who were handed a working repo
can skip straight to [`SETUP.md`](./SETUP.md)** — your job is values + secrets/vars, not the
cluster. Apply-ready manifests are in [`../bootstrap/`](../bootstrap).

> **How the pieces relate (DevOps view).** Two repos, one operator, one Argo CD:
>
> ```
>  GitHub: SOURCE repo ──podman build/push──► Nexus (images only)
>  GitHub: GITOPS repo (this) ──watched by──► Argo CD (openshift-gitops ns)
>                                              │ renders charts/<tier> with
>                                              │ deployments/values/<tier>/<env>/<svc>
>                                              ▼
>  OpenShift namespaces: api, ui  ◄── Deployment + Service + Route + ESO secrets
> ```
>
> Argo CD reconciles **from Git**, never from the registry. "Deploy" = merge to Git.

We use the **"chart-in-Git"** Helm pattern (the chart lives in this repo and an
ApplicationSet references it) — Red Hat calls this the most native Helm developer
experience because you can `helm lint` / `helm template` the exact thing Argo CD renders.

---

## Prerequisites

- An OpenShift 4.x cluster and **`cluster-admin`** for the one-time operator + RBAC steps.
- The **`oc`** CLI logged in (`oc login ...`). Optional: the **`argocd`** CLI.
- This repo pushed to GitHub (the **GITOPS repo**).
- Decisions made: your `appName` (e.g. `rca`), GitHub `org`/`repo`, and the cluster API
  server URL.

---

## Step 1 — Install the OpenShift GitOps operator

```bash
oc apply -f bootstrap/01-gitops-operator-subscription.yaml
```

This installs the operator cluster-wide and auto-creates an Argo CD instance named
`openshift-gitops` in the `openshift-gitops` namespace. Wait for it, then grab the URL and
admin password:

```bash
# operator CSV should reach Succeeded
oc get csv -n openshift-operators | grep -i gitops

# Argo CD pods come up in openshift-gitops
oc get pods -n openshift-gitops

# Console URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}'

# admin password (or just use "Log in with OpenShift")
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d ; echo
```

---

## Step 2 — Cluster prerequisites (External Secrets + Nexus trust)

These are infra-team tasks; the charts assume they exist:

- [ ] **External Secrets Operator** installed (OperatorHub → "External Secrets Operator").
- [ ] An ESO **`SecretStore`** in each target namespace (`api`, `ui`) pointing at your
      secret backend — see [`SETUP.md` §4](./SETUP.md#4-argo-cd-wiring).
- [ ] The cluster **trusts the Nexus CA** (`image.config.openshift.io/cluster`
      `additionalTrustedCA` + ConfigMap in `openshift-config`) — see
      [`SETUP.md` §3](./SETUP.md#3-nexus-specifics).

---

## Step 3 — Create the target namespaces and grant Argo CD access

This is the step people miss. Argo CD only deploys into namespaces labeled
`argocd.argoproj.io/managed-by: openshift-gitops`:

```bash
oc apply -f bootstrap/02-target-namespaces.yaml
oc get ns api ui --show-labels
```

(One `Namespace` block per service directory you deploy — add a `worker` namespace if you
add a `deployments/values/backend/<env>/worker/` directory, etc.)

---

## Step 4 — Register the GitOps repo with Argo CD (private repos only)

Public repo → skip. Private repo → edit and apply the repository Secret (a PAT with
**read** access):

```bash
# edit url + token first (or render it from your secret manager)
oc apply -f bootstrap/03-argocd-repo-secret.yaml
```

CLI equivalent:

```bash
argocd repo add https://github.com/<github-org>/<gitops-repo>.git \
  --username git --password "$GITOPS_REPO_TOKEN"
```

---

## Step 5 — Fill in app config

Set the per-env `values.yaml` (image.repository, route.domain, secretStore, enable
`registryPullSecret`) and the GitHub Actions variables/secrets. This is the app-config
half — follow [`SETUP.md` §2–§3](./SETUP.md#2-secrets--variables-reference) and §"First-time
setup runbook".

---

## Step 6 — Bootstrap the ApplicationSets

Install the **appset** chart (the only chart you install by hand). It renders one
AppProject (`<appName>-<org>-<env>`) and two ApplicationSets
(`<appName>-backend-<env>`, `<appName>-frontend-<env>`) into `openshift-gitops`:

```bash
helm upgrade --install rca-appset ./deployments/appset \
  --namespace openshift-gitops \
  --set appName=rca \
  --set env=dev \
  --set org=<github-org> \
  --set repo=<gitops-repo> \
  --set server=https://kubernetes.default.svc
```

`server=https://kubernetes.default.svc` deploys to the same cluster Argo CD runs on; use
the external API URL to target a remote cluster. Repeat with `--set env=stage` / `prod`
for the other environments (or let the `ci-cd-*.yml` workflows do it — see
[`README.md`](../README.md#cicd-workflows)).

Each ApplicationSet's git generator then turns every
`deployments/values/<tier>/<env>/*` directory into an Application
(`<appName>-<env>-<dir>`) deployed into the namespace `<dir>`.

---

## Step 7 — Verify

```bash
# the appset wiring exists
oc -n openshift-gitops get appproject,applicationset

# one Application per values directory, with health/sync status
oc -n openshift-gitops get applications

# drill into one
argocd app get rca-dev-api            # or: oc -n openshift-gitops describe application rca-dev-api

# the workload landed and the Route is up
oc -n api get deploy,svc,route,externalsecret
oc -n api get route -o jsonpath='{.items[0].spec.host}{"\n"}'
```

Healthy looks like: Applications `Synced` + `Healthy`, the Route resolves over HTTPS, and
pods are `Running` (not `ImagePullBackOff`).

---

## Troubleshooting (cluster side)

| Symptom | Likely cause | Fix |
|---|---|---|
| `oc get csv` shows no gitops CSV / it's `Failing` | bad channel or marketplace unreachable | confirm `source: redhat-operators`, a valid `channel`; check `oc get packagemanifest openshift-gitops-operator` |
| Application error: *namespace "api" is not permitted* / RBAC denied | target namespace not managed by Argo CD | ensure the namespace has `argocd.argoproj.io/managed-by: openshift-gitops` (Step 3) |
| Application `ComparisonError` / *repository not accessible* | private repo not registered, or wrong URL/token | apply the repository Secret (Step 4); verify `url` org/repo and a read-scoped PAT |
| Application stuck `Missing`/`OutOfSync`, no Applications generated | git generator path/branch mismatch | confirm the repo has `deployments/values/<tier>/<env>/*` dirs on the branch Argo CD watches (`HEAD`/`main`) |
| Pods `ImagePullBackOff` | Nexus CA not trusted, image host ≠ pull-secret `docker-server`, or `registryPullSecret` disabled | see [`SETUP.md` §3 / §7](./SETUP.md#3-nexus-specifics) |
| `ExternalSecret` `SecretSyncError` | SecretStore missing in the namespace or wrong key/permissions | a `kind: SecretStore` named `secretStore.name` must exist in that namespace ([`SETUP.md` §4](./SETUP.md#4-argo-cd-wiring)) |

---

## Sources

- [Red Hat — Installing OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.12/html-single/installing_gitops/index)
- [Red Hat — Argo CD instance](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.17/html-single/argo_cd_instance/index)
- [redhat-developer/gitops-operator — Usage Guide](https://github.com/redhat-developer/gitops-operator/blob/master/docs/OpenShift%20GitOps%20Usage%20Guide.md)
- [Argo CD — Git directory generator (ApplicationSet)](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [Argo CD — Declarative repositories (repo credential Secret)](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories)
- [Red Hat Developer — 3 patterns for deploying Helm charts with Argo CD](https://developers.redhat.com/articles/2023/05/25/3-patterns-deploying-helm-charts-argocd)
