replicaCount: 3
enabled: true
image:
  repository: ${REGISTRY_URL}/${APP_NAME}-ui
  pullPolicy: Always
  # WARNING: pin to an immutable SHA digest or commit-SHA tag for prod deploys.
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
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: "500m"
    memory: 256Mi
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 12
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
    - path: /
      pathType: Prefix
  # tls:
  #   - hosts:
  #       - "${APP_NAME}.${DOMAIN_SUFFIX}"
  #     secretName: "${APP_NAME}-prod-tls"  # provisioned by cert-manager or pre-created
  tls: []
env:
  VITE_API_BASE_URL: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
  VITE_API_BASE: "https://${APP_NAME}.${DOMAIN_SUFFIX}"
