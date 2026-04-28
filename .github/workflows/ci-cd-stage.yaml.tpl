name: Deploy — stage

on:
  workflow_dispatch:

permissions:
  contents: read
  # id-token: write  # TODO: uncomment when migrating to OIDC workload-identity federation

concurrency:
  group: deploy-${{ github.workflow }}
  cancel-in-progress: true

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
    timeout-minutes: 20
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        # to refresh SHA: 'gh api repos/actions/checkout/commits/v4'

      - name: Set up Helm
        uses: azure/setup-helm@b9e51907a09c216f16ebe8536097933489208112 # v4.3.0
        # to refresh SHA: 'gh api repos/azure/setup-helm/commits/v4'

      - name: Set up kubeconfig
        uses: azure/k8s-set-context@efa7a6c56a5e19b4ba0827a50163baa4d678578b # v4.0.1
        # to refresh SHA: 'gh api repos/azure/k8s-set-context/commits/v4'
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
            --set-string appName="${APP_NAME}" \
            --set-string env="${ENV}" \
            --set-string org="${GITHUB_ORG}" \
            --set-string repo="${GITHUB_REPO}" \
            --set-string server="${CLUSTER_SERVER}" \
            --set-string IngressFrontendHost="${INGRESS_HOST}" \
            --set-string IngressBackendHost="${INGRESS_HOST}" \
            --wait --timeout 5m
