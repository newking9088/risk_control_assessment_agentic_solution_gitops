replicaCount: 2
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-ui
  pullPolicy: Always
  tag: "latest"
imagePullSecrets:
  - name: ${PULL_SECRET_NAME}
nameOverride: ""
fullnameOverride: ""
serviceAccount:
  create: false
  automount: false
  annotations: {}
  name: ""
podAnnotations: {}
podLabels: {}
podSecurityContext: {}
securityContext: {}
service:
  type: ClusterIP
  port: 80
  targetPort: "${UI_PORT}"
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: "500m"
    memory: 256Mi
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
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
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /
      pathType: Prefix
  tls: []
env:
  VITE_API_BASE_URL: "https://${APP_NAME}-stage.${DOMAIN_SUFFIX}"
  VITE_API_BASE: "https://${APP_NAME}-stage.${DOMAIN_SUFFIX}"
