replicaCount: 3
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-api
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
  targetPort: "${API_PORT}"
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 2Gi
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 45
  periodSeconds: 30
  failureThreshold: 3
  timeoutSeconds: 3
readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 6
  timeoutSeconds: 3
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
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
    nginx.ingress.kubernetes.io/proxy-body-size: 50m
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/rewrite-target: "/$1"
  paths:
    - path: /api/(.*)
      pathType: ImplementationSpecific
  # tls:
  #   - hosts:
  #       - "${APP_NAME}.${DOMAIN_SUFFIX}"
  #     secretName: "${APP_NAME}-prod-tls"  # provisioned by cert-manager or pre-created
  tls: []
keyvault:
  name: ${KEYVAULT_NAME_PROD}
dockerKeyvault:
  name: ${DOCKER_KEYVAULT_NAME}
  pullSecretName: ${PULL_SECRET_NAME}
secrets:
  - ADMIN_DATABASE_URL
  - OPENAI_API_KEY
  - STORAGE_PRIMARY_CONNECTION_STRING
env:
  APP_ENV: "prod"
  LOG_LEVEL: "WARNING"
  DB_SCHEMA: "app"
  DB_POOL_MIN: "10"
  DB_POOL_MAX: "50"
  OPENAI_API_URL: "${LLM_API_URL}"
  CORS_ALLOWED_ORIGINS: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
  AUTH_SERVICE_URL: "http://${APP_NAME}-prod-auth-backend.prod-${APP_NAME}.svc.cluster.local"
