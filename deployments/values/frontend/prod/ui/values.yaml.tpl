replicaCount: 3
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
resources: {}
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 12
  targetCPUUtilizationPercentage: 60
volumes: []
nodeSelector: {}
tolerations: []
affinity: {}
ingress:
  enabled: true
  domain: "${APP_NAME}.${DOMAIN_SUFFIX}"
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-credentials: 'true'
    nginx.ingress.kubernetes.io/cors-allow-methods: "*"
    nginx.ingress.kubernetes.io/cors-allow-origins: "*"
    nginx.ingress.kubernetes.io/cors-expose-headers: "*"
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /
      pathType: Prefix
  tls: []
env:
  VITE_API_BASE_URL: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
  VITE_API_BASE: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
