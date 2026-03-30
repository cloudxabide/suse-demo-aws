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
      Component   = "rancher-manager"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# Data source to get shared services outputs
data "terraform_remote_state" "shared" {
  backend = "local"

  config = {
    path = "${path.module}/../shared-services/terraform.tfstate"
  }
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

# Route53 Zone lookup (if zone_id not provided)
data "aws_route53_zone" "main" {
  count        = var.create_route53_record && var.route53_zone_id == "" && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  name         = "${var.subdomain}.${var.root_domain}"
  private_zone = false
}

# Local variable for hostname
locals {
  # Build FQDN: hostname.subdomain.root_domain (e.g., rancher.suse-demo-aws.kubernerdes.com)
  rancher_fqdn = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "${var.hostname_rancher}.${var.subdomain}.${var.root_domain}" : "rancher.${var.environment}.local"
  # Get zone ID and strip /hostedzone/ prefix if present (handles user input like "/hostedzone/Z123" or "Z123")
  raw_zone_id  = var.route53_zone_id != "" ? var.route53_zone_id : (var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? data.aws_route53_zone.main[0].zone_id : "")
  zone_id      = trimprefix(local.raw_zone_id, "/hostedzone/")
  scc_suse_email = var.suse_email
  scc_regcode = var.suse_regcode
}

# Security Group for Rancher
resource "aws_security_group" "rancher" {
  name_prefix = "${var.environment}-rancher-"
  description = "Security group for Rancher Manager"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id

  # Rancher UI
  ingress {
    description = "Rancher UI"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Rancher UI HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Kubernetes API
  ingress {
    description = "Kubernetes API"
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
    Name = "${var.environment}-rancher-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Rancher
resource "aws_iam_role" "rancher" {
  name_prefix = "${var.environment}-rancher-"

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
    Name = "${var.environment}-rancher-role"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "rancher" {
  name_prefix = "${var.environment}-rancher-"
  role        = aws_iam_role.rancher.name
}

# Attach SSM policy for remote management
resource "aws_iam_role_policy_attachment" "rancher_ssm" {
  role       = aws_iam_role.rancher.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for cert-manager Route53 DNS-01 challenge
resource "aws_iam_policy" "cert_manager_route53" {
  count       = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  name_prefix = "${var.environment}-rancher-certmanager-route53-"
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
    Name = "${var.environment}-rancher-certmanager-route53-policy"
  }
}

# Attach Route53 policy to Rancher IAM role
resource "aws_iam_role_policy_attachment" "rancher_cert_manager_route53" {
  count      = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  role       = aws_iam_role.rancher.name
  policy_arn = aws_iam_policy.cert_manager_route53[0].arn
}

# Key Pair
resource "aws_key_pair" "rancher" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.environment}-rancher-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.environment}-rancher-key"
  }
}

# EC2 Instance for Rancher
resource "aws_instance" "rancher" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.sles.id
  instance_type          = var.rancher_instance_type
  subnet_id              = data.terraform_remote_state.shared.outputs.public_subnet_ids[0]
  key_name               = var.ssh_public_key != "" ? aws_key_pair.rancher[0].key_name : null
  iam_instance_profile   = aws_iam_instance_profile.rancher.name
  vpc_security_group_ids = [
    aws_security_group.rancher.id,
    data.terraform_remote_state.shared.outputs.ssh_security_group_id,
    data.terraform_remote_state.shared.outputs.internal_security_group_id
  ]

  root_block_device {
    volume_size           = var.rancher_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    rancher_version            = var.rancher_version
    cert_manager_version       = var.cert_manager_version
    k3s_version                = var.k3s_version
    hostname                   = local.rancher_fqdn
    hostname_short             = var.hostname_rancher
    suse_email                 = var.suse_email
    suse_regcode               = var.suse_regcode
    smt_url                    = var.smt_url
    enable_letsencrypt         = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != ""
    letsencrypt_email          = var.letsencrypt_email
    letsencrypt_environment    = var.letsencrypt_environment
    letsencrypt_clusterissuer  = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != "" ? templatefile("${path.module}/letsencrypt-clusterissuer.yaml.tpl", {
      letsencrypt_email = var.letsencrypt_email
      aws_region        = var.aws_region
    }) : ""
    letsencrypt_certificate = var.enable_letsencrypt && var.create_route53_record && var.letsencrypt_email != "" ? templatefile("${path.module}/letsencrypt-certificate.yaml.tpl", {
      hostname                = local.rancher_fqdn
      letsencrypt_environment = var.letsencrypt_environment
    }) : ""
  })

  tags = {
    Name = "${var.environment}-rancher-manager"
  }
}

# Elastic IP for Rancher
resource "aws_eip" "rancher" {
  count    = var.create_eip ? 1 : 0
  instance = aws_instance.rancher.id
  domain   = "vpc"

  tags = {
    Name = "${var.environment}-rancher-eip"
  }
}

# Route53 A Record for Rancher
resource "aws_route53_record" "rancher" {
  count   = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  zone_id = local.zone_id
  name    = "${var.hostname_rancher}.${var.subdomain}.${var.root_domain}"
  type    = "A"
  ttl     = 300
  records = [var.create_eip ? aws_eip.rancher[0].public_ip : aws_instance.rancher.public_ip]
}
