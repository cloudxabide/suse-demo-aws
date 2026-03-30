---
# Certificate resource for Rancher
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rancher-tls
  namespace: cattle-system
spec:
  secretName: tls-rancher-ingress
  issuerRef:
    name: letsencrypt-${letsencrypt_environment}
    kind: ClusterIssuer
  commonName: ${hostname}
  dnsNames:
  - ${hostname}
