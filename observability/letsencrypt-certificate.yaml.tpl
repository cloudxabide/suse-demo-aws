---
# Certificate resource for SUSE Observability
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: observability-tls
  namespace: suse-observability
spec:
  secretName: tls-observability-ingress
  issuerRef:
    name: letsencrypt-${letsencrypt_environment}
    kind: ClusterIssuer
  commonName: ${hostname}
  dnsNames:
  - ${hostname}
