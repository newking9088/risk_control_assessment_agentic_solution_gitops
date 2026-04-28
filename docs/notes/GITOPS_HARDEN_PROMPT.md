You are working in 'risk_control_assessment_agentic_solution_gitops'. The repo is functional but not production-hardened. Land the changes below in one pass, grouped by section. After each section, run 'bash tests/run_all.sh' and confirm 0 failures. Do not weaken any existing test or assertion. Do not change 'config.yaml' keys or values, the existing '.tpl' files' substituted vars, or the Helm chart helpers.

---

## SECTION A – Test coverage (highest leverage: do this first)

**A1.** Add `.github/workflows/ci-tests.yaml` (NOT a .tpl, this is real CI):
  - Triggers: `pull_request` on any branch, `push` on `main`.
  - Top-level `permissions: contents: read`.
  - Top-level `concurrency: group: ci-tests-${{ github.ref }} cancel-in-progress: true`.
  - One job `tests` on `ubuntu-latest` that:
    a. Checks out the repo (`actions/checkout@<sha-pinned>`).
    b. Installs `gettext` (`sudo apt-get update && sudo apt-get install -y gettext`).
    c. Sets up Helm via `azure/setup-helm@<sha-pinned>`.
    d. Installs `python3` (already present on ubuntu-latest) and `shellcheck` (apt-get).
    e. Runs `bash tests/run_all.sh`.
  - Pin every `uses:` line to a full commit SHA with a `# v<x.y.z>` trailing comment. If you cannot determine the latest SHA without network access, leave the line as `uses: org/action@<ver> # TODO: pin to SHA via 'gh api repos/org/action/commits/<tag>'` so a human can finish the pin.

**A2.** Add `tests/test_charts.sh` that, after running apply-config.sh against the test fixture, executes:
  - `helm lint deployments/charts/backend` and `helm lint deployments/charts/frontend` (assert exit 0).
  - For every env in (dev, qa, stage, prod) and svc in (api, auth): render `helm template <release> deployments/charts/backend -f deployments/values/backend/<env>/<svc>/values.yaml` and assert exit 0. Same for `frontend/<env>/ui`.
  - Pipe each rendered output through `python3 -c "import yaml,sys; list(yaml.safe_load_all(sys.stdin))"` to assert YAML validity.
  - Skip with [SKIP] if `helm` or `python3` missing.
  - Wire it into `tests/run_all.sh` as a 5th suite "Per-chart Helm rendering".

**A3.** Add to `tests/test_static.sh`:
  - For every env in (dev, qa), assert `KEYVAULT_NAME_DEV` is referenced in api/auth tpls.
  - For every env in (stage, prod), assert `KEYVAULT_NAME_PROD` is referenced in api/auth tpls.
  - Assert `dockerKeyvault` block appears ONLY in `deployments/values/backend/*/api/values.yaml.tpl` (4 files), and is absent from all auth/ui tpls.
  - Assert `tests/fixtures/config.test.yaml` declares the same set of keys as `config.yaml` (key-set equality; values may differ).

**A4.** Add `tests/test_idempotency.sh`:
  - Build a temp tree, run `apply-config.sh`, snapshot the generated tree (sort+sha256 each generated file).
  - Run `apply-config.sh` again on the same temp tree, snapshot again.
  - Assert the two snapshots are byte-identical.
  - Wire into run_all.sh as a 6th suite.

**A5.** If `shellcheck` is available, add a 7th suite `tests/test_shellcheck.sh` that runs `shellcheck scripts/apply-config.sh tests/*.sh` and asserts exit 0. Skip if not installed.

---

## SECTION B – Security hardening (lock down attack surface)

**B1.** Tighten `deployments/appset/templates/project.yaml`:
  - `sourceRepos` only `https://github.com/{{ .Values.org }}/{{ .Values.repo }}`.
  - `destinations:` only `namespace: {{ .Values.env }}-{{ .Values.appName }}`, `server: {{ .Values.server }}`.
  - Replace the wildcard `clusterResourceWhitelist` with an empty list `[]` (deny cluster-scoped).
  - Add `namespaceResourceWhitelist` as a YAML list of objects, each with `group` and `kind` keys (NOT `e/Kind` shorthand – ArgoCD's CRD strictly requires the object form):
    ```yaml
    namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ""
      kind: Service
    - group: networking.k8s.io
      kind: Ingress
    - group: autoscaling
      kind: HorizontalPodAutoscaler
    - group: ""
      kind: ConfigMap
    - group: ""
      kind: Secret
    - group: ""
      kind: AzureKeyVaultSecret
    - group: policy
      kind: PodDisruptionBudget
    - group: networking.k8s.io
      kind: NetworkPolicy
    ```
  - Update `tests/test_helm.sh` to assert the rendered AppProject (a) has no `*` in destinations or sourceRepos, (b) has `clusterResourceWhitelist: []` (or no entries), and (c) has at least 8 `namespaceResourceWhitelist` entries each with both `group` and `kind` keys.

**B2.** Add explicit `permissions:` to every workflow `.tpl`:
  - Top-level `permissions: contents: read`.
  - For ci-cd-*.yaml.tpl, also keep `id-token: write` (commented out) with a note for the OIDC migration path.

**B3.** Add `concurrency:` blocks to every ci-cd-*.yaml.tpl:
  - dev/qa/stage: `group: deploy-${{ github.workflow }}` with `cancel-in-progress: true`.
  - prod: `group: deploy-prod` with `cancel-in-progress: false` (never cancel a prod deploy mid-flight).

**B4.** SHA-pin every `uses:` in every workflow `.tpl` AND in the new ci-tests.yaml. Format: `uses: org/action@<full-40-char-sha> # v<x.y.z>`. If you cannot resolve a SHA in this session, leave a TODO comment as described in A1.

**B5.** Add chart-default secure pod/container defaults in BOTH `deployments/charts/backend/values.yaml` and `deployments/charts/frontend/values.yaml`:
  ```yaml
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]
  automountServiceAccountToken: false
  ```
  CRITICAL: Because `readOnlyRootFilesystem: true` will crash containers that need to write to disk, you MUST also add default `emptyDir`-backed volumes and volumeMounts so pods come up healthy:
  - In `deployments/charts/backend/values.yaml`: default volumes/volumeMounts to mount `emptyDir: {}` at `/tmp`. Use list syntax so per-env tpls can append.
  - In `deployments/charts/frontend/values.yaml`: default volumes/volumeMounts to mount `emptyDir: {}` at `/tmp` (standard nginx writeable paths).
  - Update both `templates/deployment.yaml` files so the pod-level `volumes` and container-level `volumeMounts` always render from the chart values (so they inherit chart defaults, even if a per-env tpl doesn't override them). The templates already use `{{- with .Values.volumes }}` / `{{- with .Values.volumeMounts }}` pattern — confirm those still work when the chart default is non-empty.

  Also propagate `automountServiceAccountToken: {{ .Values.automountServiceAccountToken }}` into both deployment.yaml templates at pod-spec level. Keep per-env tpls' `securityContext: {}` (so they inherit chart defaults).

  Add a chart-rendering test: helm-template both charts with the new defaults and assert that the rendered Deployment includes `volumeMounts` for `/tmp` (backend) and for `/tmp` + `/var/cache/nginx` + `/var/run` (frontend). This guards against a future contributor blanking the chart defaults.

**B6.** Add a new chart template `templates/poddisruptionbudget.yaml` to BOTH backend and frontend charts. Gate on `.Values.podDisruptionBudget.enabled`. Default in chart values.yaml: `enabled: true, minAvailable: 1`.

**B7.** Add a new chart template `templates/networkpolicy.yaml` to BOTH backend and frontend charts.
  - Gate on `.Values.networkPolicy.enabled`: false in chart values.yaml – opt-in until the user knows their ingress topology.
  - Pattern: default-deny-ingress + allow-from-configurable-ingress-namespace.
  - DO NOT hardcode the ingress-controller namespace label. Different installs use different labels:
    + `ingress-nginx` Helm chart: `app.kubernetes.io/name: ingress-nginx` on the namespace
    + Kubernetes 1.21+: auto-applies `kubernetes.io/metadata.name: <ns>` to every namespace
    + AKS managed addon (Web Application Routing): `app-routing-system` namespace with different labels
  - Make it configurable: set `ingressNamespaceSelector` (object) and `networkPolicy.ingressPodSelector` (object) to chart values.yaml, defaulting to `{}` with a YAML comment showing the two most common forms:
    ```yaml
    # matchLabels:
    #   app.kubernetes.io/name: ingress-nginx
    ```
  - The template should render both selectors via `toYaml` only when non-empty; if both are empty AND `enabled: true`, fail loudly via `{{ fail "networkPolicy.enabled requires ingressNamespaceSelector or ingressPodSelector" }}`.
  - Add a note in `docs/runbook.md` explaining how to discover the right labels: `kubectl get ns -L kubernetes.io/metadata.name` and `kubectl get pods -n <ingress-ns> --show-labels`.

**B8.** Add a "production-pinning" note to `deployments/values/backend/prod/api/values.yaml.tpl`, `deployments/values/backend/prod/auth/values.yaml.tpl`, and `deployments/values/frontend/prod/ui/values.yaml.tpl`:
  Above `tag: "latest"` insert a comment:
  ```
  # WARNING: pin to an immutable SHA digest or commit-SHA tag for prod deploys.
  ```
  Add a static-test assertion in `tests/test_static.sh` that this WARNING comment is present in all three prod tpls.

---

## SECTION C – Permissions, ownership, and supply chain

**C1.** Add `.github/CODEOWNERS`:
  ```
  * @newking9088
  deployments/appset/templates/project.yaml @newking9088
  .github/workflows/* @newking9088
  scripts/apply-config.sh @newking9088
  ```
  Replace `@newking9088` with a placeholder note `@your-team-handle` at the top.

**C2.** Add `.github/dependabot.yml`:
  ```yaml
  version: 2
  updates:
    - package-ecosystem: "github-actions"
      directory: "/"
      schedule:
        interval: "daily"
      labels:
        - "dependencies"
      open-pull-requests-limit: 5
    - package-ecosystem: "docker"
      directory: "/"
      schedule:
        interval: "weekly"
  ```
  Add a top-of-file comment: `# NOTE: Image tags in deployments/values/*/values.yaml.tpl and Chart Application hooks are NOT handled here. Use Resource Fabrication / repo generator or a custom CI workflow.`

**C3.** Add `.github/pull_request_template.md` with sections: Summary, Type of change (checklist), Test plan, Checklist (tests pass, tpl-generated files committed, no CHANGE_ME left).

**C4.** Add `SECURITY.md` at repo root with: supported versions table, how to report (private disclosure via GitHub "Report a vulnerability"), response SLA (acknowledge within 5 business days), and scope (GitOps config only — runtime secrets live in Azure Key Vault, not this repo).

**C5.** Add `CONTRIBUTING.md` at repo root: dev setup (clone, fill config.yaml, run apply-config.sh, run tests), contribution workflow (fork → branch → PR), commit message convention (`<type>: <subject>`), and a note that generated files (values.yaml, ci-cd-*.yaml) must be committed alongside template changes.

**C6.** Add `docs/architecture.md`: system diagram (ASCII or Mermaid), component list (ArgoCD, Helm, AKV-to-Kubernetes, GitHub Actions), data-flow description (config.yaml → apply-config.sh → values.yaml → ArgoCD sync → Kubernetes → secrets from AKV), and environment promotion path.

**C7.** Add `docs/runbook.md`: day-2 operations — how to roll back a deployment, how to rotate a secret in AKV, how to add a new environment, how to discover ingress labels for NetworkPolicy (from B7), and how to promote from stage to prod.

**C8.** Update `README.md`:
  - Add branch-protection note: recommend requiring PR reviews and status checks (`ci-tests` workflow) before merge.
  - Add OIDC migration note: the `id-token: write` permission comment in each ci-cd-*.yaml.tpl is where to wire in workload-identity federation; remove the `KUBECONFIG` secret once OIDC is configured.
  - Add a threat model blurb: this repo contains configuration only — no runtime secrets are committed; secrets are resolved at deploy time from Azure Key Vault.
  - Add links to the new docs: architecture.md, runbook.md, CONTRIBUTING.md, SECURITY.md.
