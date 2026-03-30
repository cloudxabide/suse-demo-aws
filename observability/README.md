# SUSE Observability

This OpenTofu project deploys SUSE Observability (powered by StackState) on AWS.

## Overview

SUSE Observability is a comprehensive observability platform that provides:
- **Full-Stack Observability** - Unified view of infrastructure, applications, and services
- **Topology Mapping** - Automatic discovery and visualization of service dependencies
- **Health Monitoring** - Real-time health status and anomaly detection
- **Event Correlation** - Intelligent correlation of events across the stack
- **Kubernetes Integration** - Native support for Kubernetes monitoring
- **Rancher Integration** - Seamless integration with SUSE Rancher Manager

All components run on a single EC2 instance with:
- SUSE Linux Enterprise Server (SLES) 15
- K3s (lightweight Kubernetes)
- Cert-manager (certificate management)
- SUSE Observability (StackState)

## Prerequisites

1. **Shared Services infrastructure must be deployed first**
   ```bash
   cd ../shared-services
   tofu apply
   ```

2. **SUSE Observability license key** - Required for deployment

3. **Unified configuration file** - Use the repository root `terraform.tfvars` file (see Configuration section below)

4. **SSH key pair** (optional but recommended) for instance access

5. **Route53 hosted zone** (optional) - Required for Let's Encrypt TLS certificates

## Resources Created

- EC2 instance (default: t3.xlarge) running SUSE Observability
- Security groups:
  - HTTP/HTTPS (ports 80, 443) for Observability UI via ingress
  - Router port (8080) for agent communication
  - K3s API (port 6443)
  - SSH access via shared-services security group
- IAM role and instance profile with:
  - SSM Session Manager support
  - Route53 permissions for cert-manager (when Let's Encrypt is enabled)
- Elastic IP (optional, enabled by default)
- Route53 DNS A record (optional)
- Kubernetes ingress for SUSE Observability with TLS support

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

   # Observability Instance Configuration
   observability_instance_type    = "t3.xlarge"  # Minimum for 10-nonha profile
   observability_root_volume_size = 300          # Minimum 280GB for 10-nonha profile

   # DNS Configuration (optional)
   create_route53_record = true
   root_domain           = "kubernerdes.com"
   subdomain             = "suse-demo-aws"
   hostname_observability = "observability"
   # This creates: observability.suse-demo-aws.kubernerdes.com

   # Let's Encrypt (optional)
   enable_letsencrypt      = true
   letsencrypt_email       = "your-email@example.com"
   letsencrypt_environment = "staging"  # Use "production" when ready

   # SUSE Registration
   suse_email   = "your-email@example.com"
   suse_regcode = "YOUR-SUSE-REGISTRATION-CODE"

   # SUSE Observability Configuration
   suse_observability_license        = "YOUR_LICENSE_KEY"
   suse_observability_base_url       = "https://observability.suse-demo-aws.kubernerdes.com"
   suse_observability_admin_password = ""  # Leave empty to auto-generate
   suse_rancher_url                  = "https://rancher.suse-demo-aws.kubernerdes.com"
   ```

## Deployment

Deploy using the unified configuration file from the repository root:

```bash
cd observability
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

**Installation time:** ~15-20 minutes for complete setup

## Accessing SUSE Observability

After deployment, wait ~15-20 minutes for the installation to complete.

### Get Access URL

```bash
tofu output observability_url
```

### Access SUSE Observability UI

- **With Route53/Let's Encrypt:** `https://observability.suse-demo-aws.kubernerdes.com`
- **Without DNS:** Use the output from `tofu output observability_url`

### Get Admin Credentials

```bash
# SSH to the instance
$(tofu output -raw ssh_command)

# View the admin credentials
cat /root/suse-observability-credentials.txt
```

The credentials file contains:
- Admin username
- Admin password (auto-generated if not specified)
- Access URL
- License information

## Using SUSE Observability

### Dashboard Overview

1. **Topology View** - Visualize your infrastructure and application dependencies
2. **Health Dashboard** - Monitor the health status of all components
3. **Events** - View and correlate events across your stack
4. **Traces** - Analyze distributed traces for applications
5. **Metrics** - Explore time-series metrics data
6. **Logs** - Search and analyze logs from all sources

### Integrating with Rancher Manager

To monitor Rancher-managed clusters:

1. Access SUSE Observability UI
2. Navigate to **Settings** → **Agents**
3. Deploy the SUSE Observability agent to your Rancher-managed clusters:
   - Access Rancher Manager UI
   - Navigate to target cluster
   - Install SUSE Observability agent via Helm chart
   - Configure agent to connect to this SUSE Observability instance

### Adding Custom Data Sources

SUSE Observability supports various data sources:
- Kubernetes clusters
- Cloud platforms (AWS, Azure, GCP)
- Container orchestrators
- Service meshes (Istio, Linkerd)
- Monitoring tools (Prometheus, Datadog)
- APM tools (Jaeger, Zipkin)

Refer to [SUSE Observability documentation](https://docs.stackstate.com/) for detailed integration guides.

## Monitoring Installation

**Check deployment status:**

```bash
# Get SSH command and connect
$(tofu output -raw ssh_command)

# Verify K3s cluster
kubectl get nodes
kubectl get pods -A

# Check SUSE Observability deployment
kubectl get pods -n suse-observability
kubectl get ingress -n suse-observability
kubectl get certificate -n suse-observability  # If Let's Encrypt enabled

# View SUSE Observability services
kubectl get svc -n suse-observability

# View installation logs
sudo tail -f /var/log/user-data.log
sudo journalctl -u cloud-init-output -f
```

## Let's Encrypt TLS Certificates

When `enable_letsencrypt = true` and Route53 DNS is configured:

**Monitor certificate issuance:**

```bash
# SSH to instance
$(tofu output -raw ssh_command)

# Check certificate status
kubectl get certificate -n suse-observability
kubectl describe certificate observability-tls -n suse-observability

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

## Cost Optimization

- Default instance type is `t3.xlarge` (~$0.17/hour, ~$122/month)
- Minimum instance type for 10-nonha profile is `t3.xlarge`
- Set `create_eip = false` to avoid Elastic IP charges (~$3.60/month)
- Remember to destroy when not in use: `tofu destroy -var-file=../terraform.tfvars`

## Troubleshooting

### SUSE Observability UI not accessible

1. **Check instance status:**
   ```bash
   aws ec2 describe-instances --filters "Name=tag:Name,Values=*observability*" --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]"
   ```

2. **Verify security groups allow your IP:**
   ```bash
   # Check your current IP
   curl ifconfig.me

   # Update allowed_cidr_blocks in terraform.tfvars if needed
   ```

3. **Check SUSE Observability deployment:**
   ```bash
   # SSH to instance
   $(tofu output -raw ssh_command)

   # Check pods
   kubectl get pods -n suse-observability
   kubectl describe pods -n suse-observability

   # Check ingress
   kubectl get ingress -n suse-observability
   kubectl describe ingress suse-observability-ingress -n suse-observability
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
   kubectl get certificate -n suse-observability
   kubectl describe certificate observability-tls -n suse-observability
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
   aws iam list-attached-role-policies --role-name $(tofu output -raw instance_id | xargs aws ec2 describe-instances --instance-ids --query "Reservations[].Instances[].IamInstanceProfile.Arn" --output text | cut -d'/' -f2)
   ```

### Installation logs

**View complete installation logs:**

```bash
$(tofu output -raw ssh_command)
sudo tail -f /var/log/user-data.log
sudo journalctl -u cloud-init-output
```

### Common Issues

| Issue | Solution |
|-------|----------|
| SUSE Observability UI shows 502/503 error | Wait for pods to be ready: `kubectl wait --for=condition=ready pod -l app=suse-observability -n suse-observability --timeout=900s` |
| Certificate stuck in pending | Check DNS: `dig observability.suse-demo-aws.kubernerdes.com` and cert-manager logs |
| Can't SSH to instance | Verify security group allows your IP and SSH key is correct |
| Installation appears stuck | Installation can take 15-20 minutes. Monitor with `sudo tail -f /var/log/user-data.log` |
| Insufficient disk space | Ensure `observability_root_volume_size` is at least 280GB (300GB recommended) |
| Performance issues | Minimum instance type is `t3.xlarge`. Consider upgrading to `t3.2xlarge` for better performance |

## Additional Resources

- [SUSE Observability Documentation](https://docs.stackstate.com/)
- [StackState Kubernetes Agent](https://docs.stackstate.com/setup/agent/kubernetes-openshift/)
- [SUSE Observability Helm Charts](https://helm.stackstate.io/)
