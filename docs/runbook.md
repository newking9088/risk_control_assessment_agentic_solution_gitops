# Runbook — Day-2 Operations

## Roll back a deployment

ArgoCD keeps a sync history for each Application. To roll back:

```bash
# List sync history
argocd app history <app-name>

# Roll back to a previous revision
argocd app rollback <app-name> <revision-id>
```

Or via the ArgoCD UI: select the Application → History → click "Rollback" on the desired revision.

To roll back the AppSet itself (the Helm release):

```bash
helm rollback appset-<APP_NAME>-<ENV> -n argocd
```

## Rotate a secret in Azure Key Vault

1. Update the secret value in Azure Key Vault (portal, CLI, or Terraform).
2. The AKV-to-Kubernetes operator polls for changes. Default sync interval is configurable on the `AzureKeyVaultSecret` resource (`.spec.output.sync.interval`).
3. To force an immediate sync, delete and recreate the Kubernetes Secret, or restart the operator pod.
4. Roll the affected pods to pick up the new secret:
   > Each environment's workloads live in namespace `<env>-<app-name>`
   > (e.g. `dev-risk-control-assessment-agentic-solution`).
   ```bash
   kubectl rollout restart deployment/<release-name> -n <env>-<app-name>
   ```

## Add a new environment

1. Add a new environment block in all relevant places:
   - `deployments/values/<backend|frontend>/<newenv>/` — copy an existing env directory and update values.
   - `.github/workflows/ci-cd-<newenv>.yaml.tpl` — copy an existing tpl and update env name, trigger, and timeout.
2. Add the new env to `deployments/appset/` if the ApplicationSet is environment-specific.
3. Run `bash scripts/apply-config.sh` to regenerate YAML files.
4. Run `bash tests/run_all.sh` and update tests as needed.
5. Create the GitHub Environment in **Settings → Environments** with `KUBECONFIG`, `DOMAIN_SUFFIX`, and `CLUSTER_SERVER`.

## Discover ingress labels for NetworkPolicy

Before enabling `networkPolicy.enabled: true` on a chart, identify the correct labels for your ingress controller's namespace and pods.

**Find namespace labels:**
```bash
kubectl get ns -L kubernetes.io/metadata.name
kubectl get ns --show-labels
```

**Find ingress pod labels:**
```bash
# Replace <ingress-ns> with your ingress controller namespace
kubectl get pods -n <ingress-ns> --show-labels
```

**Common patterns:**

| Ingress setup | Namespace selector | Pod selector |
|---|---|---|
| ingress-nginx Helm | `app.kubernetes.io/name: ingress-nginx` | `app.kubernetes.io/name: ingress-nginx` |
| AKS Web App Routing | `kubernetes.azure.com/managedby: aks` | `app: nginx` |
| Kubernetes 1.21+ (any) | `kubernetes.io/metadata.name: <ns>` | varies |

Once you know the labels, set them in your per-env `values.yaml.tpl`:

```yaml
networkPolicy:
  enabled: true
  ingressNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx
  ingressPodSelector: {}
```

## Promote from stage to prod

1. Verify stage is healthy: `kubectl get pods -n <APP_NAME>-stage`
2. Confirm the same image tags are used in prod tpls (update from `latest` to a pinned SHA).
3. Trigger the `Deploy — prod` workflow via GitHub Actions → **Actions** → **Deploy — prod** → **Run workflow**.
4. A required reviewer must approve the deployment in the GitHub Environments page before it proceeds.
5. Monitor rollout: `kubectl rollout status deployment/<release> -n <APP_NAME>-prod`
