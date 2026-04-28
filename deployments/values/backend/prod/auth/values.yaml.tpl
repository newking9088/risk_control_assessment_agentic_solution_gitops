replicaCount: 3
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-auth
  pullPolicy: Always
  # WARNING: pin to an immutable SHA digest or commit-SHA tag for prod deploys.
  tag: "latest"
imagePullSecrets:
  - name: ${PULL_SECRET_NAME}
nameOverride: ""
fullnameOverride: ""
serviceAccount:
  create: false
  automount: true
  annotations: {}
  name: ""
podAnnotations: {}
podLabels: {}
podSecurityContext: {}
securityContext: {}
service:
  type: ClusterIP
  port: 80
  targetPort: "${AUTH_PORT}"
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi
livenessProbe:
  httpGet:
    path: /health
    port: http
readinessProbe:
  httpGet:
    path: /health
    port: http
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 60
nodeSelector: {}
tolerations: []
affinity: {}
ingress:
  enabled: true
  domain: "${APP_NAME}.${DOMAIN_SUFFIX}"
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-credentials: 'true'
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
    nginx.ingress.kubernetes.io/cors-expose-headers: "Content-Length,Content-Range"
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /api/auth
      pathType: Prefix
  # tls:
  #   - hosts:
  #       - "${APP_NAME}.${DOMAIN_SUFFIX}"
  #     secretName: "${APP_NAME}-prod-tls"  # provisioned by cert-manager or pre-created
  tls: []
keyvault:
  name: ${KEYVAULT_NAME_PROD}
secrets:
  - ADMIN_DATABASE_URL
  - BETTER_AUTH_SECRET
env:
  PORT: "${AUTH_PORT}"
  NODE_ENV: "production"
  TRUSTED_ORIGINS: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
  DATABASE_SSL: "true"
  ADMIN_EMAIL: "${ADMIN_EMAIL}"
  BETTER_AUTH_URL: "https://${APP_NAME}.${DOMAIN_SUFFIX}/api/auth"
