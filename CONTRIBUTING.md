# Contributing

## Development setup

```bash
git clone https://github.com/newking9088/risk_control_assessment_agentic_solution_gitops
cd risk_control_assessment_agentic_solution_gitops

# 1. Fill in real values
# Edit config.yaml and replace all CHANGE_ME_* values

# 1.5. Verify python3 + pyyaml are available
python3 --version
python3 -c 'import yaml; print("pyyaml ok")'

# 2. Generate values files
bash scripts/apply-config.sh

# 3. Run the test suite
bash tests/run_all.sh
```

**Requirements:**
- `bash` 4+
- `envsubst` — `brew install gettext` (Mac), `apt install gettext` (Linux), `winget install GNU.gettext` (Windows)
- `python3` + `pyyaml` — required for `tests/test_charts.sh` YAML validity check (`apt install python3-yaml` or `pip install pyyaml`)
- `helm` v3 (optional — required for Helm rendering suites)
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

## Internal prompts

The `docs/notes/` directory contains the AI-assisted audit prompts used to harden this repo. They are kept as an audit trail so future maintainers can understand the reasoning behind non-obvious decisions:

- [GITOPS_HARDEN_PROMPT.md](docs/notes/GITOPS_HARDEN_PROMPT.md) — Sections A/B/C: security hardening
- [GITOPS_CORRECTNESS_PROMPT.md](docs/notes/GITOPS_CORRECTNESS_PROMPT.md) — Sections D/E/F/G: correctness bugs
- [GITOPS_REFINE_PROMPT.md](docs/notes/GITOPS_REFINE_PROMPT.md) — final refinement audit (A–G)
