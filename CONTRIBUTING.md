# Contributing

## Development setup

```bash
git clone https://github.com/newking9088/risk_control_assessment_agentic_solution_gitops
cd risk_control_assessment_agentic_solution_gitops

# 1. Fill in real values
cp config.yaml config.yaml.local  # optional — keep secrets out of git
# Edit config.yaml and replace all CHANGE_ME_* values

# 2. Generate values files
bash scripts/apply-config.sh

# 3. Run the test suite
bash tests/run_all.sh
```

**Requirements:**
- `bash` 4+
- `envsubst` — `brew install gettext` (Mac), `apt install gettext` (Linux), `winget install GNU.gettext` (Windows)
- `helm` v3 (optional — required for Helm rendering suites)
- `python3` (optional — required for YAML validity checks in test_charts.sh)
- `shellcheck` (optional — required for static analysis suite)

## Contribution workflow

1. **Fork** the repository and create a feature branch from `main`.
2. Make your changes, keeping each commit focused on a single concern.
3. Run `bash tests/run_all.sh` and ensure 0 failures.
4. If you modified any `.tpl` files, run `bash scripts/apply-config.sh` and commit the generated files alongside the templates.
5. Open a pull request against `main` using the PR template.

## Commit message convention

```
<type>: <short imperative subject>

[optional body]
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `security`

Examples:
```
feat: add NetworkPolicy template to backend chart
fix: strip inline comments from keyvault values
docs: add ingress label discovery to runbook
security: sha-pin all workflow action references
```

## Generated files

Files ending in `.yaml` that live next to a `.yaml.tpl` are **generated** — never edit them directly. Modify the `.tpl` and re-run `scripts/apply-config.sh`. Commit both the template change and the regenerated output in the same PR.

Generated files:
- `deployments/values/**/*.yaml`
- `deployments/appset/values.yaml`
- `.github/workflows/ci-cd-*.yaml`
