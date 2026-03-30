# Common variables shared across all Terraform modules
# This file should be symlinked or referenced via -var-file flag from each module

# AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
  default     = "suse-demo"
}

# Network Configuration (shared-services only)
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use (1-6)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "The az_count must be between 1 and 6."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "enable_nat_gateway" {
  description = "Boolean whether to deploy NATGW (future use)"
  type        = bool
  default     = false
}

# Security Configuration
variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for better security
}

variable "allowed_web_cidr_blocks" {
  description = "CIDR blocks allowed to access web interfaces"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for better security
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access service interfaces (fallback for modules)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for instance access (shared across all instances)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.ssh_public_key == "" ||
      can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ", var.ssh_public_key))
    )
    error_message = "The ssh_public_key must be a valid SSH public key starting with ssh-rsa, ssh-ed25519, or ecdsa-sha2-*."
  }
}

# Instance Configuration - Module Specific
variable "rancher_instance_type" {
  description = "EC2 instance type for Rancher Manager server"
  type        = string
  default     = "t3.xlarge"
}

variable "observability_instance_type" {
  description = "EC2 instance type for SUSE Observability server (minimum t3.xlarge for 10-nonha profile)"
  type        = string
  default     = "t3.xlarge"
}

variable "security_instance_type" {
  description = "EC2 instance type for Security/NeuVector server"
  type        = string
  default     = "t3.large"
}

variable "rancher_root_volume_size" {
  description = "Root volume size in GB for Rancher Manager"
  type        = number
  default     = 100
}

variable "observability_root_volume_size" {
  description = "Root volume size in GB for Observability (minimum 280GB for 10-nonha profile)"
  type        = number
  default     = 300
}

variable "security_root_volume_size" {
  description = "Root volume size in GB for Security/NeuVector"
  type        = number
  default     = 100
}

# Elastic IP Configuration
variable "create_eip" {
  description = "Create Elastic IPs for instances (applies to product modules)"
  type        = bool
  default     = true
}

# DNS Configuration (Route53)
variable "create_route53_record" {
  description = "Create Route53 DNS records for services"
  type        = bool
  default     = false
}

variable "root_domain" {
  description = "Root domain name (e.g., kubernerdes.com)"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Environment subdomain (e.g., suse-demo-aws)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (leave empty to auto-discover from subdomain.root_domain)"
  type        = string
  default     = ""
}

# DNS Hostnames (per product)
variable "hostname_rancher" {
  description = "Hostname for Rancher Manager service (e.g., rancher). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "rancher"
}

variable "hostname_observability" {
  description = "Hostname for SUSE Observability service (e.g., observability). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "observability"
}

variable "hostname_security" {
  description = "Hostname for SUSE Security/NeuVector service (e.g., security). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "security"
}

# SUSE Registration
variable "suse_email" {
  description = "SUSE Email Address used to register to SCC"
  type        = string
  default     = ""

  validation {
    condition = (
      var.suse_email == "" ||
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.suse_email))
    )
    error_message = "The suse_email must be a valid email address."
  }
}

variable "suse_regcode" {
  description = "SUSE Registration Code used to register to SCC"
  type        = string
  default     = ""
}

variable "smt_url" {
  description = "SMT/RMT server URL (leave empty to use SUSE Customer Center)"
  type        = string
  default     = ""
}

# Product-Specific Versions
variable "rancher_version" {
  description = "Rancher version to install"
  type        = string
  default     = "2.9.2"
}

variable "cert_manager_version" {
  description = "Cert-manager version to install"
  type        = string
  default     = "1.15.3"
}

variable "neuvector_version" {
  description = "NeuVector app version to install (Helm will use latest compatible chart version)"
  type        = string
  default     = "5.4.6"
}

variable "k3s_version" {
  description = "K3s version to install (e.g., v1.30.0+k3s1). Leave empty to use latest stable release."
  type        = string
  default     = ""
}

# SUSE Observability Configuration
variable "suse_observability_license" {
  description = "SUSE Observability license key (required for observability module)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "suse_observability_base_url" {
  description = "Base URL for SUSE Observability (e.g., https://observability.example.com)"
  type        = string
  default     = ""
}

variable "suse_rancher_url" {
  description = "Base URL for SUSE Rancher (e.g., https://rancher.example.com)"
  type        = string
  default     = ""
}

variable "suse_observability_admin_password" {
  description = "Admin password for SUSE Observability (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

# AMI Configuration (optional override)
variable "ami_id" {
  description = "AMI ID to use (leave empty to use latest SLES)"
  type        = string
  default     = ""
}

# Let's Encrypt Configuration
variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = ""

  validation {
    condition = (
      var.letsencrypt_email == "" ||
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.letsencrypt_email))
    )
    error_message = "The letsencrypt_email must be a valid email address when provided."
  }
}

variable "letsencrypt_environment" {
  description = "Let's Encrypt environment: 'staging' for testing, 'production' for real certificates"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.letsencrypt_environment)
    error_message = "The letsencrypt_environment must be either 'staging' or 'production'."
  }
}

variable "enable_letsencrypt" {
  description = "Enable Let's Encrypt certificate automation via cert-manager"
  type        = bool
  default     = false
}
