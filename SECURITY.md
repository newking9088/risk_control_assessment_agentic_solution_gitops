# Security Policy

## Supported Versions

This repository contains GitOps configuration only. There is no versioned software release — the `main` branch is always the supported version.

| Branch | Supported |
|--------|-----------|
| `main` | Yes       |
| other  | No        |

## Scope

This repository contains:
- Kubernetes manifests and Helm chart templates
- CI/CD workflow templates
- Deployment configuration (non-secret)

It does **not** contain runtime secrets. All secrets (database URLs, API keys, auth secrets) are stored in Azure Key Vault and resolved at deploy time by the AKV-to-Kubernetes operator. Do not commit secrets to this repository.

## Reporting a Vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Use GitHub's private vulnerability reporting:

1. Go to the **Security** tab of this repository.
2. Click **"Report a vulnerability"**.
3. Provide a description, steps to reproduce, and impact assessment.

**Response SLA:** We will acknowledge your report within **5 business days** and provide a remediation timeline within **10 business days**.

## Out of Scope

- Runtime secrets in Azure Key Vault (report to your cloud security team)
- Kubernetes cluster misconfigurations outside this repo
- Vulnerabilities in upstream tools (ArgoCD, Helm, AKV-to-Kubernetes) — report to their respective projects
