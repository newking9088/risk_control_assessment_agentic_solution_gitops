You are working in the repo `risk_control_assessment_agentic_solution_gitops`, a GitOps template
(config.yaml + scripts/apply-config.sh + *.tpl files) intended to bootstrap a repo clean output.
Fix the issues below. Do not refactor anything else. Verify by running `bash scripts/apply-config.sh`
after the fixes and confirming clean output.

---

**1. Fix `deployments/appset/templates/project.yaml`**

It uses `{{- range .Values.envs }}` but workflows pass `--set env=<one-env>` (singular). Replace the
range loop with a single non-iterating manifest using `.Values.env` and `.Values.appName`, mirroring
how `appset.backend.yaml` and `appset.frontend.yaml` reference `.Values.env`. The metadata.name must
be `{{ .Values.env }}-{{ .Values.appName }}`, description `"RCA Platform project – {{ .Values.env }}"`,
keep finalizers, sourceRepos `['*']`, destinations namespace/server `'*'`, and
clusterResourceWhitelist group/kind `'*'`.

---

**2. Fix `scripts/apply-config.sh` to tolerate inline `#` comments after values**

Currently `val=$(echo "$line" | cut -d':' -f2- | xargs | sed 's/^"//;s/"$//')` produces
`CHANGE_ME_KEYVAULT_DEV # used for dev + qa` for:

```yaml
KEYVAULT_NAME_DEV: "CHANGE_ME_KEYVAULT_DEV"     # used for dev + qa
```

Strip any unquoted trailing comment before processing, e.g. with sed: only treat `#` as a comment
when it is preceded by whitespace and not inside quotes. Also:
- Skip lines that have no `:`.
- Skip lines whose key is empty after stripping.

Keep the script POSIX-bash and dependency-free aside from envsubst. Add a small test: after parsing,
the script should print and verify that no exported variable's value contains `#` or unbalanced
quotes; warn (not fail) if it does.

---

**3. Fix the nginx CORS annotation typo in all backend and frontend value templates**

Replace every occurrence of `nginx.ingress.kubernetes.io/cors-allow-origins` with
`nginx.ingress.kubernetes.io/cors-allow-origin` (singular). Files affected:
- `deployments/values/backend/{dev,qa,stage,prod}/{api,auth}/values.yaml.tpl` (8 files)
- `deployments/values/frontend/{dev,qa,stage,prod}/ui/values.yaml.tpl` (4 files)
- `deployments/charts/backend/values.yaml` and `deployments/charts/frontend/values.yaml`

Do NOT change any other annotation keys.

---

**4. Make workflows and appset values fully template-driven**

The repo must be reusable without manual edits. Currently the four workflow files and
`deployments/appset/values.yaml` hard-code `APP_NAME`, `GITHUB_ORG`, and `GITHUB_REPO`.

- Add `.github/workflows/ci-cd-dev.yaml.tpl`, `ci-cd-qa.yaml.tpl`, `ci-cd-stage.yaml.tpl`, and
  `ci-cd-prod.yaml.tpl` that mirror today's workflows exactly but reference `${APP_NAME}`,
  `${GITHUB_ORG}`, `${GITHUB_REPO}` as envsubst variables in the `env:` block. Delete the existing
  non-tpl workflow files (apply-config.sh will regenerate them).

- Add `deployments/appset/values.yaml.tpl` referencing `${APP_NAME}`, `${GITHUB_ORG}`,
  `${GITHUB_REPO}` for appName/org/repo and leaving env/server/IngressFrontendHost/IngressBackendHost
  as empty strings (populated at deploy time via `--set`). Delete the existing
  `deployments/appset/values.yaml`.

- Update `scripts/apply-config.sh` so its `find` picks up `.tpl` files under
  `.github/workflows/` and `deployments/appset/` in addition to `deployments/values/`.

---

**5. Fix the misleading comment in `config.yaml`**

Line 7 currently reads:
```
# Secrets (Key Vault names, registry credentials) should also be set in .env
```
The script never reads `.env`. Replace it with:
```
# Secrets remain in Azure Key Vault; nothing is read from .env
```

---

**6. Update README**

- In **Step 3 — Commit the generated files**, replace:
  ```bash
  git add deployments/values/**/*.yaml
  ```
  with:
  ```bash
  git add deployments/values/ deployments/appset/values.yaml .github/workflows/ci-cd-*.yaml
  # or: find . -name '*.yaml' -not -name '*.tpl' | xargs git add
  ```

- In the **Repository structure** section add a short note that `.github/workflows/ci-cd-*.yaml`
  and `deployments/appset/values.yaml` are also generated from `.tpl` files by `apply-config.sh`.

---

**7. Add `.helmignore` files**

Create `deployments/charts/backend/.helmignore` and `deployments/charts/frontend/.helmignore` with
the standard Helm-generated content:

```
# Patterns to ignore when building packages.
.DS_Store
.git/
.gitignore
.gitmodules
.helmignore
*.tgz
.idea/
.vscode/
```

---

## Acceptance criteria

- `bash scripts/apply-config.sh` runs clean against a `config.yaml` where every `CHANGE_ME` has been
  replaced with a sample value, and produces resolved files for:
  - every `deployments/values/**/*.yaml` (no `.tpl` suffix)
  - all four `.github/workflows/ci-cd-*.yaml`
  - `deployments/appset/values.yaml`

- `helm template deployments/appset --set env=dev --set server=https://kubernetes.default.svc`
  renders exactly one `AppProject` named `dev-<APP_NAME>` plus the two ApplicationSets — no empty
  documents.

- `grep -r 'cors-allow-origins' deployments/` returns no matches.

- No file outside `deployments/values/`, `deployments/appset/values.yaml`,
  `.github/workflows/ci-cd-*.yaml`, `README.md`, `config.yaml`, or `scripts/apply-config.sh`
  is modified.
