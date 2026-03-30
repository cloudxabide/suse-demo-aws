---
# Let's Encrypt Staging ClusterIssuer (for testing)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # Staging server for testing (higher rate limits, fake certs)
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${letsencrypt_email}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - dns01:
        route53:
          region: ${aws_region}
          # Uses EC2 instance IAM role - no credentials needed
---
# Let's Encrypt Production ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    # Production server (lower rate limits, real certs)
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${letsencrypt_email}
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
    - dns01:
        route53:
          region: ${aws_region}
          # Uses EC2 instance IAM role - no credentials needed
