---
# Certificate resource for SUSE Security (NeuVector)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: security-tls
  namespace: neuvector
spec:
  secretName: tls-security-ingress
  issuerRef:
    name: letsencrypt-${letsencrypt_environment}
    kind: ClusterIssuer
  commonName: ${hostname}
  dnsNames:
  - ${hostname}
