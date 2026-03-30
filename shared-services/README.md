# Shared Services

This OpenTofu project creates the common infrastructure needed for all SUSE demo products.

## Resources Created

- **VPC** - Isolated virtual network
- **Subnets** - Public subnets across multiple availability zones (private subnets not implemented for cost optimization)
- **Internet Gateway** - Provides direct internet access to public subnets
- **Route Tables** - Routing configuration for subnets
- **Security Groups** - Firewall rules for:
  - SSH access
  - HTTP/HTTPS access
  - Internal VPC communication

## Configuration

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` and customize the values:
   - Set `owner` to your name
   - **IMPORTANT:** Update `allowed_ssh_cidr_blocks` and `allowed_web_cidr_blocks` to your IP address for security
   - Adjust `az_count` if you want to use fewer availability zones (default is 3, minimum 1 for cost savings)

## Deployment

```bash
tofu init
tofu plan
tofu apply
```

## Outputs

This module exports outputs that will be used by other projects:
- VPC ID and CIDR
- Public subnet IDs
- Security group IDs
- Availability zones

## Cost Optimization

To minimize costs for a demo environment:
- Use only one availability zone if high availability isn't needed (configured via `az_count` variable)
- All resources use public subnets with Internet Gateway (no NAT Gateway costs)
- Remember to destroy resources when not in use: `tofu destroy`
