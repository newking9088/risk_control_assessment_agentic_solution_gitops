## Summary

<!-- One to three bullet points describing what changed and why. -->

-

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing behavior to change)
- [ ] Config / template update (changes to `.tpl` files or `config.yaml`)
- [ ] Documentation / runbook update
- [ ] Security hardening

## Test plan

<!-- Steps taken to verify this change works. -->

- [ ] Ran `bash tests/run_all.sh` — 0 failures
- [ ] Verified generated files look correct after `bash scripts/apply-config.sh`

## Checklist

- [ ] All tests pass (`bash tests/run_all.sh`)
- [ ] Generated files committed alongside template changes (`deployments/values/**/*.yaml`, `.github/workflows/ci-cd-*.yaml`, `deployments/appset/values.yaml`)
- [ ] No `CHANGE_ME` placeholders remain in committed files
- [ ] New `.tpl` variables are documented in `config.yaml` and `tests/fixtures/config.test.yaml`
- [ ] If adding a new environment: `docs/runbook.md` updated
