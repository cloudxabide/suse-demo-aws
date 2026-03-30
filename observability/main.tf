terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "suse-demo"
      Component   = "observability"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

locals {
  # Build FQDN: hostname.subdomain.root_domain (e.g., observability.suse-demo-aws.kubernerdes.com)
  observability_fqdn = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "${var.hostname_observability}.${var.subdomain}.${var.root_domain}" : "observability.${var.environment}.local"
  # Get zone ID and strip /hostedzone/ prefix if present (handles user input like "/hostedzone/Z123" or "Z123")
  raw_zone_id        = var.route53_zone_id != "" ? var.route53_zone_id : (var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? data.aws_route53_zone.main[0].zone_id : "")
  zone_id            = trimprefix(local.raw_zone_id, "/hostedzone/")
}

# Data source to get shared services outputs
data "terraform_remote_state" "shared" {
  backend = "local"

  config = {
    path = "${path.module}/../shared-services/terraform.tfstate"
  }
}

# Data source to lookup Route53 hosted zone (only if creating DNS record)
data "aws_route53_zone" "main" {
  count        = var.create_route53_record && var.route53_zone_id == "" && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  name         = "${var.subdomain}.${var.root_domain}."
  private_zone = false
}

# Get latest SLES AMI
data "aws_ami" "sles" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["suse-sles-15-sp*-v*-hvm-ssd-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for SUSE Observability
resource "aws_security_group" "observability" {
  name_prefix = "${var.environment}-observability-"
  description = "Security group for SUSE Observability (StackState)"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id

  # SUSE Observability UI (HTTPS)
  ingress {
    description = "SUSE Observability UI"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SUSE Observability UI (HTTP)
  ingress {
    description = "SUSE Observability UI HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SUSE Observability Router (default port)
  ingress {
    description = "SUSE Observability Router"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # K3s API Server
  ingress {
    description = "K3s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-suse-observability-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Observability
resource "aws_iam_role" "observability" {
  name_prefix = "${var.environment}-observability-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-observability-role"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "observability" {
  name_prefix = "${var.environment}-observability-"
  role        = aws_iam_role.observability.name
}

# Attach SSM policy for remote management
resource "aws_iam_role_policy_attachment" "observability_ssm" {
  role       = aws_iam_role.observability.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for cert-manager Route53 DNS-01 challenge
resource "aws_iam_policy" "cert_manager_route53" {
  count       = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  name_prefix = "${var.environment}-observability-certmanager-route53-"
  description = "Allow cert-manager to manage Route53 records for DNS-01 challenge"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${local.zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-observability-certmanager-route53-policy"
  }
}

# Attach Route53 policy to Observability IAM role
resource "aws_iam_role_policy_attachment" "observability_cert_manager_route53" {
  count      = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  role       = aws_iam_role.observability.name
  policy_arn = aws_iam_policy.cert_manager_route53[0].arn
}

# Key Pair
resource "aws_key_pair" "observability" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.environment}-observability-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.environment}-observability-key"
  }
}

# EC2 Instance for Observability
resource "aws_instance" "observability" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.sles.id
  instance_type          = var.observability_instance_type
  subnet_id              = data.terraform_remote_state.shared.outputs.public_subnet_ids[0]
  key_name               = var.ssh_public_key != "" ? aws_key_pair.observability[0].key_name : null
  iam_instance_profile   = aws_iam_instance_profile.observability.name
  vpc_security_group_ids = [
    aws_security_group.observability.id,
    data.terraform_remote_state.shared.outputs.ssh_security_group_id,
    data.terraform_remote_state.shared.outputs.internal_security_group_id
  ]

  root_block_device {
    volume_size           = var.observability_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    suse_observability_license        = var.suse_observability_license
    suse_observability_base_url       = var.suse_observability_base_url
    suse_observability_admin_password = var.suse_observability_admin_password
    suse_rancher_url                  = var.suse_rancher_url
    suse_email                        = var.suse_email
    suse_regcode                      = var.suse_regcode
    smt_url                           = var.smt_url
    cert_manager_version              = var.cert_manager_version
    k3s_version                       = var.k3s_version
    hostname                          = var.hostname_observability
    hostname_short                    = var.hostname_observability
    subdomain                         = var.subdomain
    root_domain                       = var.root_domain
    enable_letsencrypt                = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != ""
    letsencrypt_environment           = var.letsencrypt_environment
    letsencrypt_clusterissuer         = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != "" ? templatefile("${path.module}/letsencrypt-clusterissuer.yaml.tpl", {
      letsencrypt_email = var.letsencrypt_email
      aws_region        = var.aws_region
    }) : ""
    letsencrypt_certificate = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != "" ? templatefile("${path.module}/letsencrypt-certificate.yaml.tpl", {
      hostname                = local.observability_fqdn
      letsencrypt_environment = var.letsencrypt_environment
    }) : ""
  })

  tags = {
    Name = "${var.environment}-suse-observability"
  }
}

# Elastic IP for Observability
resource "aws_eip" "observability" {
  count    = var.create_eip ? 1 : 0
  instance = aws_instance.observability.id
  domain   = "vpc"

  tags = {
    Name = "${var.environment}-observability-eip"
  }
}

# Route53 A Record for SUSE Observability
resource "aws_route53_record" "observability" {
  count   = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  zone_id = local.zone_id
  name    = "${var.hostname_observability}.${var.subdomain}.${var.root_domain}"
  type    = "A"
  ttl     = 300
  records = [var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip]
}
