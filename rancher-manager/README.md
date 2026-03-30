# SUSE Rancher Manager

This OpenTofu project deploys SUSE Rancher Manager on AWS.

## Overview

Rancher is deployed on a single EC2 instance running:
- SUSE Linux Enterprise Server (SLES)
- K3s (lightweight Kubernetes)
- Cert-manager (certificate management)
- Rancher Manager (Kubernetes management platform)

## Prerequisites

- Shared Services infrastructure must be deployed first
- SSH key pair for instance access (optional but recommended)

## Resources Created

- EC2 instance running Rancher Manager
- Security group for Rancher access (ports 80, 443, 6443)
- IAM role and instance profile
- Elastic IP (optional, enabled by default)
- Route53 DNS record (optional)

## Configuration

**This module uses the unified configuration approach.** Instead of a local `terraform.tfvars` file:

1. Edit the repository root configuration file:
   ```bash
   cd ..
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

2. Update key variables:
   ```hcl
   # Global Configuration
   owner       = "your-name"
   environment = "suse-demo-aws"

   # Security Configuration
   allowed_cidr_blocks = ["YOUR.IP.ADDRESS/32"]  # IMPORTANT: Restrict to your IP!
   ssh_public_key      = "ssh-rsa AAAA..."        # Your SSH public key

   # Rancher Instance Configuration
   rancher_instance_type    = "t3.xlarge"  # Minimum recommended
   rancher_root_volume_size = 100

   # DNS Configuration (optional)
   create_route53_record = true
   root_domain           = "kubernerdes.com"
   subdomain             = "suse-demo-aws"
   hostname_rancher      = "rancher"
   # This creates: rancher.suse-demo-aws.kubernerdes.com

   # SUSE Registration
   suse_email   = "your-email@example.com"
   suse_regcode = "YOUR-SUSE-REGISTRATION-CODE"

   # Rancher Version
   rancher_version      = "2.12.2"
   cert_manager_version = "1.15.3"
   ```

### Route53 DNS Configuration (Optional)

To use a custom domain name instead of an IP address:

1. Ensure you have a Route53 hosted zone for your subdomain (e.g., `suse-demo-aws.kubernerdes.com`)
2. In the root `terraform.tfvars`, set:
   ```hcl
   create_route53_record = true
   root_domain           = "kubernerdes.com"      # Your root domain
   subdomain             = "suse-demo-aws"        # Environment subdomain
   hostname_rancher      = "rancher"              # Service hostname
   # This creates: rancher.suse-demo-aws.kubernerdes.com
   ```
3. (Optional) If you know your Route53 zone ID:
   ```hcl
   route53_zone_id = "Z1234567890ABC"
   ```
   Otherwise, it will be auto-discovered from `subdomain.root_domain`

**Benefits of using Route53:**
- Stable DNS name (e.g., `rancher.suse-demo-aws.kubernerdes.com`)
- SSL certificates work properly with cert-manager
- Easier to remember and share access

### Let's Encrypt TLS Certificates (Optional)

When Route53 DNS is configured, you can enable automatic TLS certificate provisioning:

1. In the root `terraform.tfvars`, set:
   ```hcl
   enable_letsencrypt      = true
   letsencrypt_email       = "your-email@example.com"
   letsencrypt_environment = "staging"  # Use "staging" for testing
   ```

2. **Certificate environments:**
   - **Staging:** Use for testing. Issues fake certificates with high rate limits.
   - **Production:** Issues real, trusted certificates. Has strict rate limits (50 certs/week per domain).

3. **Switching from staging to production:**
   - Update `letsencrypt_environment = "production"` in `terraform.tfvars`
   - Run `tofu apply -var-file=../terraform.tfvars`
   - Wait for cert-manager to issue new certificate (~2-5 minutes)

## Deployment

Deploy using the unified configuration file from the repository root:

```bash
cd rancher-manager
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

**Installation time:** ~10-15 minutes for complete setup

## Accessing Rancher

After deployment (wait ~10-15 minutes for installation to complete):

1. Get the Rancher URL from outputs:
   ```bash
   tofu output rancher_url
   ```

2. Access Rancher in your browser using the URL

3. Default credentials:
   - Username: `admin`
   - Password: `admin` (you'll be prompted to change this)

## Monitoring Installation

SSH into the instance and monitor the installation:

```bash
# Get SSH command
tofu output ssh_command

# Once connected, monitor the installation
sudo journalctl -u cloud-init-output -f

# Check Rancher pods
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pods -n cattle-system
```

## Cost Optimization

- Default instance type is `t3.xlarge` (~$0.17/hour, ~$122/month)
- Set `create_eip = false` to avoid Elastic IP charges (~$3.60/month)
- Remember to destroy when not in use: `tofu destroy`

## Monitoring Let's Encrypt Certificates

When Let's Encrypt is enabled, monitor certificate issuance:

```bash
# SSH to instance
$(tofu output -raw ssh_command)

# Check certificate status
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get certificate -n cattle-system
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml describe certificate rancher-tls -n cattle-system

# View cert-manager logs
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml logs -n cert-manager -l app=cert-manager -f
```

## Troubleshooting

If Rancher is not accessible:
1. Check instance is running: `aws ec2 describe-instances`
2. SSH to instance and check logs: `sudo journalctl -u cloud-init-output`
3. Verify Rancher pods are running: `sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pods -n cattle-system`
4. Check security group allows your IP address
5. If using Route53, verify DNS record was created:
   ```bash
   tofu output route53_record
   nslookup rancher.suse-demo-aws.kubernerdes.com
   ```
6. If DNS is configured but SSL fails, wait for cert-manager to issue certificates (~2-5 minutes)
7. For Let's Encrypt certificate issues:
   - Check certificate status: `sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get certificate -n cattle-system`
   - View cert-manager logs: `sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml logs -n cert-manager -l app=cert-manager`
