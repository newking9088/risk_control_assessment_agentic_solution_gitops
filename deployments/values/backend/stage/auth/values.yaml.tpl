replicaCount: 2
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
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70
volumes: []
volumeMounts: []
nodeSelector: {}
tolerations: []
affinity: {}
ingress:
  enabled: true
  domain: "${APP_NAME}-stage.${DOMAIN_SUFFIX}"
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-credentials: 'true'
    nginx.ingress.kubernetes.io/cors-allow-methods: "*"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
    nginx.ingress.kubernetes.io/cors-expose-headers: "*"
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /api/auth
      pathType: Prefix
  tls: []
keyvault:
  name: ${KEYVAULT_NAME_PROD}
secrets:
  - ADMIN_DATABASE_URL
  - BETTER_AUTH_SECRET
env:
  PORT: "${AUTH_PORT}"
  NODE_ENV: "production"
  TRUSTED_ORIGINS: "https://${APP_NAME}-stage.${DOMAIN_SUFFIX}"
  DATABASE_SSL: "true"
  ADMIN_EMAIL: "${ADMIN_EMAIL}"
  BETTER_AUTH_URL: "https://${APP_NAME}-stage.${DOMAIN_SUFFIX}/api/auth"
