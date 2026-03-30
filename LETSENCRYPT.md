# Let's Encrypt Integration Guide

This guide explains how to use the Let's Encrypt integration in the SUSE Demo AWS infrastructure.

## Overview

The infrastructure now supports automatic TLS certificate provisioning via Let's Encrypt for all three product modules:
- **rancher-manager** - Rancher Manager UI
- **observability** - SUSE Observability (StackState) UI
- **security** - SUSE Security (NeuVector) UI

Certificates are automatically requested, validated, and renewed using cert-manager with Route53 DNS-01 challenges.

## Prerequisites

1. **Route53 DNS** must be configured:
   - `create_route53_record = true`
   - Valid `root_domain` and `subdomain` configured
   - Route53 hosted zone exists for your domain

2. **Valid email address** for Let's Encrypt notifications:
   - Set `letsencrypt_email` to receive certificate expiration notices

## Configuration

Add the following variables to your `terraform.tfvars` file:

```hcl
# Enable Let's Encrypt
enable_letsencrypt      = true
letsencrypt_email       = "your-email@example.com"
letsencrypt_environment = "staging"  # or "production"
```

### Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_letsencrypt` | Enable Let's Encrypt cert automation | `false` | No |
| `letsencrypt_email` | Email for Let's Encrypt notifications | `""` | Yes (if enabled) |
| `letsencrypt_environment` | Environment: `staging` or `production` | `staging` | No |

## Let's Encrypt Environments

### Staging Environment (Recommended for Testing)

```hcl
letsencrypt_environment = "staging"
```

- **Use when**: Testing your setup, developing, or making changes
- **Rate limits**: Very high (suitable for testing)
- **Certificates**: Valid but issued by a **fake CA** (browsers will show warning)
- **ACME server**: `https://acme-staging-v02.api.letsencrypt.org/directory`

### Production Environment (Use When Ready)

```hcl
letsencrypt_environment = "production"
```

- **Use when**: Everything is working and you're ready for production
- **Rate limits**: Limited (50 certs/week per domain)
- **Certificates**: Trusted by all major browsers
- **ACME server**: `https://acme-v02.api.letsencrypt.org/directory`

**Important**: Test with staging first! If you hit production rate limits, you'll need to wait a week.

## How It Works

### Architecture

1. **IAM Permissions**: Each EC2 instance has an IAM role with Route53 permissions to manage DNS records for DNS-01 challenge validation

2. **cert-manager**: Installed in each K3s cluster to handle certificate lifecycle:
   - Requests certificates from Let's Encrypt
   - Creates DNS TXT records in Route53 for validation
   - Stores certificates as Kubernetes secrets
   - Auto-renews certificates before expiration

3. **ClusterIssuers**: Two ClusterIssuers are created per module:
   - `letsencrypt-staging` - For testing
   - `letsencrypt-production` - For production use

4. **Certificates**: Certificate resources are created for each service:
   - **rancher-manager**: `tls-rancher-ingress` secret in `cattle-system` namespace
   - **observability**: `tls-observability-ingress` secret in `suse-observability` namespace
   - **security**: `tls-security-ingress` secret in `neuvector` namespace

### DNS-01 Challenge Flow

1. cert-manager creates a Certificate request
2. Let's Encrypt asks for proof of domain ownership
3. cert-manager creates a TXT record in Route53: `_acme-challenge.<hostname>`
4. Let's Encrypt validates the TXT record
5. Certificate is issued and stored in Kubernetes secret
6. TXT record is cleaned up automatically

## Monitoring Certificate Status

### Check Certificate Status

```bash
# Rancher Manager
kubectl describe certificate rancher-tls -n cattle-system

# Observability (after namespace is created)
kubectl describe certificate observability-tls -n suse-observability

# Security
kubectl describe certificate security-tls -n neuvector
```

### Check ClusterIssuer Status

```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-staging
kubectl describe clusterissuer letsencrypt-production
```

### View Certificate Secrets

```bash
# Rancher
kubectl get secret tls-rancher-ingress -n cattle-system

# Observability
kubectl get secret tls-observability-ingress -n suse-observability

# Security
kubectl get secret tls-security-ingress -n neuvector
```

## Troubleshooting

### Certificate Not Issuing

1. **Check cert-manager logs**:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

2. **Check Certificate events**:
   ```bash
   kubectl describe certificate <cert-name> -n <namespace>
   ```

3. **Check CertificateRequest**:
   ```bash
   kubectl get certificaterequest -n <namespace>
   kubectl describe certificaterequest <request-name> -n <namespace>
   ```

4. **Verify IAM permissions**:
   - Check that the EC2 instance IAM role has Route53 policy attached
   - Verify the policy allows `route53:ChangeResourceRecordSets` for your hosted zone

### Common Issues

**Issue**: Certificate stuck in "Pending" state
- **Solution**: Check that Route53 hosted zone exists and is accessible
- **Solution**: Verify `create_route53_record = true` and DNS is configured

**Issue**: "Too many certificates already issued"
- **Solution**: You've hit Let's Encrypt rate limits (production only)
- **Solution**: Wait one week or use staging environment

**Issue**: DNS validation fails
- **Solution**: Check Route53 hosted zone ID is correct
- **Solution**: Verify IAM role has Route53 permissions
- **Solution**: Check cert-manager logs for DNS propagation issues

## Migration from Staging to Production

Once you've verified everything works with staging certificates:

1. Update `terraform.tfvars`:
   ```hcl
   letsencrypt_environment = "production"
   ```

2. Re-apply Terraform (triggers user-data change):
   ```bash
   cd rancher-manager
   terraform apply -var-file=../terraform.tfvars

   cd ../observability
   terraform apply -var-file=../terraform.tfvars

   cd ../security
   terraform apply -var-file=../terraform.tfvars
   ```

3. This will recreate instances with new certificates using production ClusterIssuer

## Certificate Auto-Renewal

cert-manager automatically renews certificates when they are within 30 days of expiration. No manual intervention required.

## Cost Considerations

- Let's Encrypt certificates are **free**
- You only pay for Route53 DNS queries during validation (minimal cost)
- No additional AWS costs beyond standard EC2/Route53 usage

## Security Notes

1. **IAM Role Permissions**: Instance IAM roles have minimal Route53 permissions scoped to your hosted zone only

2. **Certificate Storage**: Certificates are stored as Kubernetes secrets with appropriate RBAC controls

3. **Email Notifications**: Use a monitored email address for `letsencrypt_email` to receive expiration warnings (backup to auto-renewal)

## References

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Route53 DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
