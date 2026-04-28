name: Deploy — stage

on:
  workflow_dispatch:

env:
  APP_NAME: "${APP_NAME}"
  ENV: "stage"
  DOMAIN_SUFFIX: ${{ vars.DOMAIN_SUFFIX }}
  CLUSTER_SERVER: ${{ vars.CLUSTER_SERVER }}
  GITHUB_ORG: "${GITHUB_ORG}"
  GITHUB_REPO: "${GITHUB_REPO}"

jobs:
  deploy-stage:
    runs-on: ubuntu-latest
    environment: stage
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Set up kubeconfig
        uses: azure/k8s-set-context@v4
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBECONFIG }}

      - name: Deploy AppSet — stage
        run: |
          INGRESS_HOST="${APP_NAME}-${ENV}.${DOMAIN_SUFFIX}"
          helm upgrade --install \
            appset-${APP_NAME}-${ENV} \
            deployments/appset \
            --namespace argocd \
            --create-namespace \
            --set appName="${APP_NAME}" \
            --set env="${ENV}" \
            --set org="${GITHUB_ORG}" \
            --set repo="${GITHUB_REPO}" \
            --set server="${CLUSTER_SERVER}" \
            --set IngressFrontendHost="${INGRESS_HOST}" \
            --set IngressBackendHost="${INGRESS_HOST}" \
            --wait --timeout 5m
