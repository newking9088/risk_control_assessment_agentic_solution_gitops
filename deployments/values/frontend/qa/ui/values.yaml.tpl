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
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
nodeSelector: {}
tolerations: []
affinity: {}
ingress:
  enabled: true
  domain: "${APP_NAME}-qa.${DOMAIN_SUFFIX}"
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-credentials: 'true'
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET,POST,PUT,PATCH,DELETE,OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://${APP_NAME}-qa.${DOMAIN_SUFFIX}"
    nginx.ingress.kubernetes.io/cors-expose-headers: "Content-Length,Content-Range"
    nginx.ingress.kubernetes.io/enable-cors: 'true'
  paths:
    - path: /
      pathType: Prefix
  tls: []
env:
  VITE_API_BASE_URL: "https://${APP_NAME}-qa.${DOMAIN_SUFFIX}"
  VITE_API_BASE: "https://${APP_NAME}-qa.${DOMAIN_SUFFIX}"
