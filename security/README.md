# SUSE Security

This Terraform module deploys a comprehensive security stack on AWS, including NeuVector container security, Trivy vulnerability scanning, and Falco runtime security monitoring.

## Overview

The security stack includes:
- **NeuVector** - Kubernetes-native container security platform with network policies, runtime protection, and vulnerability scanning
- **Trivy** - Comprehensive vulnerability scanner for containers and other artifacts
- **Falco** - Runtime security and threat detection for suspicious system activity

All components run on a single EC2 instance with SUSE Linux Enterprise Server (SLES) 15 and K3s (lightweight Kubernetes).

## Prerequisites

1. **Shared Services infrastructure must be deployed first**
   ```bash
   cd ../shared-services
   tofu apply
   ```

2. **Unified configuration file** - Use the repository root `terraform.tfvars` file (see Configuration section below)

3. **SSH key pair** (optional but recommended) for instance access

4. **Route53 hosted zone** (optional) - Required for Let's Encrypt TLS certificates

## Resources Created

- EC2 instance (default: t3.large) running the security stack
- Security groups:
  - HTTP/HTTPS (ports 80, 443) for NeuVector web UI via ingress
  - Trivy server (port 8080)
  - SSH access via shared-services security group
- IAM role and instance profile with:
  - SSM Session Manager support
  - Route53 permissions for cert-manager (when Let's Encrypt is enabled)
- Elastic IP (optional, enabled by default)
- Route53 DNS A record (optional)
- Kubernetes ingress for NeuVector with TLS support

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
   allowed_cidr_blocks     = ["YOUR.IP.ADDRESS/32"]  # IMPORTANT: Restrict to your IP!
   ssh_public_key          = "ssh-rsa AAAA..."        # Your SSH public key

   # Security Instance Configuration
   security_instance_type    = "t3.large"
   security_root_volume_size = 100

   # DNS Configuration (optional)
   create_route53_record = true
   root_domain           = "example.com"
   subdomain             = "suse-demo-aws"
   hostname_security     = "security"

   # Let's Encrypt (optional)
   enable_letsencrypt      = true
   letsencrypt_email       = "your-email@example.com"
   letsencrypt_environment = "staging"  # Use "production" when ready

   # SUSE Registration
   suse_email   = "your-email@example.com"
   suse_regcode = "YOUR-SUSE-REGISTRATION-CODE"

   # NeuVector Version
   neuvector_version = "5.4.6"  # Latest stable version
   ```

## Deployment

Deploy using the unified configuration file from the repository root:

```bash
cd security
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

**Installation time:** ~10-15 minutes for complete setup

## Accessing Security Tools

After deployment, wait ~10-15 minutes for the installation to complete.

### Get Access URLs
```bash
tofu output neuvector_url  # NeuVector web UI
tofu output trivy_url      # Trivy server endpoint
tofu output ssh_command    # SSH access command
```

### NeuVector (Container Security)

**Access NeuVector UI:**
- With Route53/Let's Encrypt: `https://security.suse-demo-aws.example.com`
- Without DNS: Use the output from `tofu output neuvector_url`

**Default credentials:** `admin` / `admin`
**⚠️ IMPORTANT:** Change the password immediately on first login!

**Key Features:**
- Container vulnerability scanning and CVE tracking
- Network segmentation and security policies
- Runtime protection (discover, monitor, protect modes)
- Compliance reporting (PCI-DSS, NIST, CIS benchmarks)
- Admission control for Kubernetes

### Trivy (Vulnerability Scanner)

Trivy runs as a server on port 8080 for centralized vulnerability scanning.

**Scan container images from your local machine:**
```bash
# Get Trivy server URL
TRIVY_SERVER=$(tofu output -raw trivy_url)

# Scan an image
trivy image --server $TRIVY_SERVER nginx:latest
trivy image --server $TRIVY_SERVER --severity HIGH,CRITICAL myapp:v1.0
```

**Scan from the instance (SSH in first):**
```bash
trivy image nginx:latest
trivy fs /path/to/project
trivy k8s --report summary
```

### Falco (Runtime Security)

Falco runs as a systemd service and monitors kernel system calls for suspicious activity and security threats.

**View Falco alerts in real-time:**
```bash
# SSH to instance
$(tofu output -raw ssh_command)

# View live Falco alerts
sudo journalctl -u falco -f

# View recent alerts
sudo journalctl -u falco -n 100
```

**Common Falco detections:**
- Shell execution in containers
- Privilege escalation attempts
- Sensitive file access
- Unexpected network connections
- Process behavior anomalies

## Using NeuVector

### Scanning Images
1. Access NeuVector UI
2. Go to Assets → Registries
3. Add your container registry
4. Scan images for vulnerabilities

### Network Policies
1. Go to Policy → Network Rules
2. Create network segmentation rules
3. Monitor and block unauthorized traffic

### Runtime Protection
1. Go to Policy → Groups
2. Enable runtime protection modes:
   - Discover: Learning mode
   - Monitor: Alert on violations
   - Protect: Block violations

## Using Trivy

### Scan Container Images
```bash
trivy image nginx:latest
trivy image --severity HIGH,CRITICAL myapp:v1.0
```

### Scan Filesystem
```bash
trivy fs /path/to/project
```

### Scan Kubernetes Cluster
```bash
trivy k8s --report summary
```

## Let's Encrypt TLS Certificates

When `enable_letsencrypt = true` and Route53 DNS is configured:

**Monitor certificate issuance:**
```bash
# SSH to instance
$(tofu output -raw ssh_command)

# Check certificate status
kubectl get certificate -n neuvector
kubectl describe certificate security-tls -n neuvector

# View cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

**Certificate environments:**
- **Staging:** Use for testing. Issues fake certificates with high rate limits. Perfect for initial setup.
- **Production:** Issues real, trusted certificates. Has strict rate limits (50 certs/week per domain).

**Switching from staging to production:**
1. Update `letsencrypt_environment = "production"` in `terraform.tfvars`
2. Run `tofu apply -var-file=../terraform.tfvars`
3. Wait for cert-manager to issue new certificate (~2-5 minutes)

## Integration with Rancher Manager

Deploy NeuVector agents to Rancher-managed clusters:

1. Access Rancher Manager UI
2. Navigate to **Cluster Management** → Select target cluster
3. Go to **Apps** → **Charts** → Search "NeuVector"
4. Install NeuVector with these settings:
   - Manager: Point to this standalone NeuVector instance
   - Controller: Deploy on target cluster
   - Enforcer: Deploy on target cluster

This allows centralized security management across multiple Kubernetes clusters.

## Monitoring Installation

**Check deployment status:**
```bash
# Get SSH command and connect
$(tofu output -raw ssh_command)

# Verify K3s cluster
kubectl get nodes
kubectl get pods -A

# Check NeuVector deployment
kubectl get pods -n neuvector
kubectl get ingress -n neuvector
kubectl get certificate -n neuvector  # If Let's Encrypt enabled

# Check system services
sudo systemctl status k3s
sudo systemctl status trivy-server
sudo systemctl status falco

# View installation logs
sudo tail -f /var/log/user-data.log
sudo journalctl -u cloud-init-output -f
```

## Cost Optimization

- Default instance type is `t3.large` (~$0.08/hour, ~$58/month)
- Set `create_eip = false` to avoid Elastic IP charges (~$3.60/month)
- Remember to destroy when not in use: `tofu destroy`

## Security Best Practices

1. **Restrict Access**: Update `allowed_cidr_blocks` to your IP only
2. **Change Passwords**: Change NeuVector admin password immediately
3. **Enable MFA**: Configure multi-factor authentication in NeuVector
4. **Review Policies**: Regularly review and update security policies
5. **Monitor Alerts**: Set up notifications for Falco and NeuVector alerts

## Troubleshooting

### NeuVector UI not accessible

1. **Check instance status:**
   ```bash
   aws ec2 describe-instances --filters "Name=tag:Name,Values=*suse-security*" --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]"
   ```

2. **Verify security groups allow your IP:**
   ```bash
   # Check your current IP
   curl ifconfig.me

   # Update allowed_cidr_blocks in terraform.tfvars if needed
   ```

3. **Check NeuVector deployment:**
   ```bash
   # SSH to instance
   $(tofu output -raw ssh_command)

   # Check pods
   kubectl get pods -n neuvector
   kubectl describe pods -n neuvector

   # Check ingress
   kubectl get ingress -n neuvector
   kubectl describe ingress neuvector-ingress -n neuvector
   ```

4. **Check K3s and ingress controller:**
   ```bash
   # Verify K3s is running
   sudo systemctl status k3s
   kubectl get nodes

   # Check Traefik ingress controller (built into K3s)
   kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
   ```

### Let's Encrypt certificate issues

1. **Check certificate status:**
   ```bash
   kubectl get certificate -n neuvector
   kubectl describe certificate security-tls -n neuvector
   ```

2. **Common certificate issues:**
   - **Pending state:** DNS propagation or Route53 permissions issue
   - **Failed state:** Check cert-manager logs
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager --tail=100
   ```

3. **Verify Route53 permissions:**
   ```bash
   # Check IAM role has Route53 permissions
   aws iam get-role-policy --role-name $(tofu output -raw instance_id | xargs aws ec2 describe-instances --instance-ids {} --query "Reservations[].Instances[].IamInstanceProfile.Arn" --output text | cut -d'/' -f2)
   ```

### Installation logs

**View complete installation logs:**
```bash
$(tofu output -raw ssh_command)
sudo tail -f /var/log/user-data.log
sudo journalctl -u cloud-init-output
```

### Common issues

| Issue | Solution |
|-------|----------|
| NeuVector UI shows 502/503 error | Wait for pods to be ready: `kubectl wait --for=condition=ready pod -l app=neuvector-manager-pod -n neuvector --timeout=600s` |
| Certificate stuck in pending | Check DNS: `dig security.suse-demo-aws.example.com` and cert-manager logs |
| Can't SSH to instance | Verify security group allows your IP and SSH key is correct |
| Trivy server not responding | Check service: `sudo systemctl status trivy-server` and restart if needed |
| Falco not logging | Check kernel headers: `sudo zypper install -t pattern devel_kernel` |
