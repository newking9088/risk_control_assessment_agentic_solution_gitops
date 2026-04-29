replicaCount: 1
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-auth
  pullPolicy: Always
  tag: "latest"
imagePullSecrets:
  - name: ${PULL_SECRET_NAME}
nameOverride: ""
fullnameOverride: ""
serviceAccount:
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
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
livenessProbe:
  httpGet:
    path: /health
    port: http
readinessProbe:
  httpGet:
    path: /health
    port: http
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
nodeSelector: {}
tolerations: []
affinity: {}
ingress:
  enabled: true
  domain: "${APP_NAME}-dev.${DOMAIN_SUFFIX}"
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-credentials: 'true'
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://${APP_NAME}-dev.${DOMAIN_SUFFIX}"
    nginx.ingress.kubernetes.io/cors-expose-headers: "Content-Length,Content-Range"
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /api/auth
      pathType: Prefix
  tls: []
keyvault:
  name: ${KEYVAULT_NAME_DEV}
secrets:
  - ADMIN_DATABASE_URL
  - BETTER_AUTH_SECRET
env:
  PORT: "${AUTH_PORT}"
  NODE_ENV: "production"
  TRUSTED_ORIGINS: "https://${APP_NAME}-dev.${DOMAIN_SUFFIX}"
  DATABASE_SSL: "true"
  ADMIN_EMAIL: "${ADMIN_EMAIL}"
  BETTER_AUTH_URL: "https://${APP_NAME}-dev.${DOMAIN_SUFFIX}/api/auth"
