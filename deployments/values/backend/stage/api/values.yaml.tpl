replicaCount: 2
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-api
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
  targetPort: "${API_PORT}"
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "2"
    memory: 1Gi
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
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
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
    nginx.ingress.kubernetes.io/proxy-body-size: 50m
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/rewrite-target: "/$1"
  paths:
    - path: /api/(.*)
      pathType: ImplementationSpecific
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
  APP_ENV: "stage"
  LOG_LEVEL: "WARNING"
  DB_SCHEMA: "app"
  DB_POOL_MIN: "5"
  DB_POOL_MAX: "20"
  OPENAI_API_URL: "${LLM_API_URL}"
  CORS_ALLOWED_ORIGINS: "https://${APP_NAME}-stage.${DOMAIN_SUFFIX}"
  AUTH_SERVICE_URL: "http://${APP_NAME}-stage-auth-backend.stage.svc.cluster.local"
