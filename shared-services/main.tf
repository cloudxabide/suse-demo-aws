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
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-suse-demo-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-suse-demo-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-suse-demo-public-${var.availability_zones[count.index]}"
    Type = "public"
  }
}



# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-suse-demo-public-rt"
  }
}


# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group - SSH Access
resource "aws_security_group" "ssh" {
  name_prefix = "${var.environment}-suse-demo-ssh-"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-suse-demo-ssh-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group - HTTPS Access
resource "aws_security_group" "https" {
  name_prefix = "${var.environment}-suse-demo-https-"
  description = "Allow HTTPS access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from allowed IPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-suse-demo-https-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group - HTTP Access
resource "aws_security_group" "http" {
  name_prefix = "${var.environment}-suse-demo-http-"
  description = "Allow HTTP access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from allowed IPs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-suse-demo-http-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group - Internal Communication
resource "aws_security_group" "internal" {
  name_prefix = "${var.environment}-suse-demo-internal-"
  description = "Allow internal VPC communication"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-suse-demo-internal-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
