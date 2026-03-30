#!/bin/bash
#
# SUSE Demo AWS - Automated Deployment Script
#
# This script automates the deployment of all SUSE demo infrastructure modules
# in the correct order with validation and error handling.
#

set -e  # Exit on error

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TERRAFORM_VARS="${PROJECT_ROOT}/terraform.tfvars"
readonly MODULES=("shared-services" "rancher-manager" "observability" "security")

# Minimum required versions
readonly MIN_TERRAFORM_VERSION="1.5.0"

#######################################
# Print colored message
# Arguments:
#   $1: Color code
#   $2: Message
#######################################
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

#######################################
# Print section header
# Arguments:
#   $1: Section name
#######################################
print_header() {
    echo ""
    echo "========================================"
    print_message "$BLUE" "$1"
    echo "========================================"
    echo ""
}

#######################################
# Compare version strings
# Arguments:
#   $1: Version 1
#   $2: Version 2
# Returns:
#   0 if v1 >= v2, 1 otherwise
#######################################
version_ge() {
    [ "$1" = "$2" ] && return 0
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            return 0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    return 0
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    print_header "Checking Prerequisites"

    local all_good=true

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_message "$RED" "✗ Terraform not found"
        print_message "$YELLOW" "  Install from: https://www.terraform.io/downloads"
        all_good=false
    else
        local tf_version=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
        if [ -z "$tf_version" ]; then
            # Fallback for older Terraform versions
            tf_version=$(terraform version | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n1)
        fi

        if version_ge "$tf_version" "$MIN_TERRAFORM_VERSION"; then
            print_message "$GREEN" "✓ Terraform ${tf_version}"
        else
            print_message "$RED" "✗ Terraform ${tf_version} (minimum ${MIN_TERRAFORM_VERSION} required)"
            all_good=false
        fi
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_message "$YELLOW" "⚠ AWS CLI not found (optional but recommended)"
        print_message "$YELLOW" "  Install from: https://aws.amazon.com/cli/"
    else
        local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        print_message "$GREEN" "✓ AWS CLI ${aws_version}"

        # Check AWS credentials
        if aws sts get-caller-identity &> /dev/null; then
            local account_id=$(aws sts get-caller-identity --query Account --output text)
            local user_arn=$(aws sts get-caller-identity --query Arn --output text)
            print_message "$GREEN" "✓ AWS credentials valid"
            print_message "$BLUE" "  Account: ${account_id}"
            print_message "$BLUE" "  Identity: ${user_arn}"
        else
            print_message "$RED" "✗ AWS credentials not configured or invalid"
            print_message "$YELLOW" "  Run: aws configure"
            all_good=false
        fi
    fi

    # Check for jq (optional but useful)
    if ! command -v jq &> /dev/null; then
        print_message "$YELLOW" "⚠ jq not found (optional, used for JSON parsing)"
    else
        print_message "$GREEN" "✓ jq found"
    fi

    # Check terraform.tfvars exists
    if [ ! -f "$TERRAFORM_VARS" ]; then
        print_message "$RED" "✗ terraform.tfvars not found at: ${TERRAFORM_VARS}"
        print_message "$YELLOW" "  Please copy terraform.tfvars.example and customize it:"
        print_message "$YELLOW" "  cp terraform.tfvars.example terraform.tfvars"
        print_message "$YELLOW" "  vim terraform.tfvars"
        all_good=false
    else
        print_message "$GREEN" "✓ terraform.tfvars found"
    fi

    if [ "$all_good" = true ]; then
        echo ""
        return 0
    else
        echo ""
        print_message "$RED" "Prerequisites check failed. Please fix the issues above."
        exit 1
    fi
}

#######################################
# Validate terraform.tfvars contents
#######################################
validate_tfvars() {
    print_header "Validating Configuration"

    if [ ! -f "$TERRAFORM_VARS" ]; then
        return 1
    fi

    local warnings=0

    # Check ssh_public_key
    if ! grep -q 'ssh_public_key.*=.*"ssh-' "$TERRAFORM_VARS"; then
        print_message "$YELLOW" "⚠ Warning: ssh_public_key appears to be empty or invalid"
        print_message "$YELLOW" "  You won't be able to SSH to instances without a valid SSH key"
        ((warnings++))
    else
        print_message "$GREEN" "✓ SSH public key configured"
    fi

    # Check suse_email
    if ! grep -q 'suse_email.*=.*".*@.*"' "$TERRAFORM_VARS"; then
        print_message "$YELLOW" "⚠ Warning: suse_email appears to be empty"
        print_message "$YELLOW" "  SUSE registration will fail without a valid email"
        ((warnings++))
    else
        print_message "$GREEN" "✓ SUSE email configured"
    fi

    # Check suse_regcode
    if ! grep -q 'suse_regcode.*=.*"[A-Z0-9]' "$TERRAFORM_VARS"; then
        print_message "$YELLOW" "⚠ Warning: suse_regcode appears to be empty"
        print_message "$YELLOW" "  SUSE registration will fail without a valid registration code"
        ((warnings++))
    else
        print_message "$GREEN" "✓ SUSE registration code configured"
    fi

    # Check allowed_cidr_blocks
    if grep -q 'allowed.*cidr.*=.*"0\.0\.0\.0/0"' "$TERRAFORM_VARS"; then
        print_message "$YELLOW" "⚠ Warning: CIDR blocks are set to 0.0.0.0/0 (open to internet)"
        print_message "$YELLOW" "  Consider restricting to your IP for better security"
        ((warnings++))
    fi

    # Check for observability license (if observability will be deployed)
    if ! grep -q 'suse_observability_license.*=.*"[A-Z0-9]' "$TERRAFORM_VARS"; then
        print_message "$YELLOW" "⚠ Warning: suse_observability_license appears to be empty"
        print_message "$YELLOW" "  Observability deployment will fail without a valid license"
        ((warnings++))
    else
        print_message "$GREEN" "✓ SUSE Observability license configured"
    fi

    if [ $warnings -gt 0 ]; then
        echo ""
        print_message "$YELLOW" "Found ${warnings} warning(s) in configuration"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "$RED" "Deployment cancelled"
            exit 1
        fi
    else
        print_message "$GREEN" "✓ Configuration looks good"
    fi

    echo ""
}

#######################################
# Initialize a module
# Arguments:
#   $1: Module name
#######################################
init_module() {
    local module=$1

    print_message "$BLUE" "Initializing ${module}..."

    cd "${PROJECT_ROOT}/${module}"

    if terraform init -input=false; then
        print_message "$GREEN" "✓ ${module} initialized"
    else
        print_message "$RED" "✗ Failed to initialize ${module}"
        return 1
    fi

    cd "${PROJECT_ROOT}"
}

#######################################
# Deploy a module
# Arguments:
#   $1: Module name
#   $2: Module display name
#######################################
deploy_module() {
    local module=$1
    local display_name=$2

    print_header "Deploying ${display_name}"

    cd "${PROJECT_ROOT}/${module}"

    # Initialize
    print_message "$BLUE" "Running terraform init..."
    if ! terraform init -input=false; then
        print_message "$RED" "✗ Failed to initialize ${module}"
        return 1
    fi

    # Plan
    print_message "$BLUE" "Running terraform plan..."
    if ! terraform plan -var-file=../terraform.tfvars -out=tfplan; then
        print_message "$RED" "✗ Failed to plan ${module}"
        return 1
    fi

    # Apply
    print_message "$BLUE" "Running terraform apply..."
    if ! terraform apply -input=false tfplan; then
        print_message "$RED" "✗ Failed to apply ${module}"
        return 1
    fi

    # Clean up plan file
    rm -f tfplan

    print_message "$GREEN" "✓ ${display_name} deployed successfully"

    cd "${PROJECT_ROOT}"
    echo ""
}

#######################################
# Show deployment summary
#######################################
show_summary() {
    print_header "Deployment Summary"

    cd "${PROJECT_ROOT}"

    # Shared Services
    print_message "$BLUE" "=== Shared Services ==="
    if [ -f "shared-services/terraform.tfstate" ]; then
        cd shared-services
        echo "VPC ID: $(terraform output -raw vpc_id 2>/dev/null || echo 'N/A')"
        echo "Region: $(grep 'aws_region' ../terraform.tfvars | cut -d'=' -f2 | tr -d ' "')"
        cd ..
    fi
    echo ""

    # Rancher Manager
    print_message "$BLUE" "=== Rancher Manager ==="
    if [ -f "rancher-manager/terraform.tfstate" ]; then
        cd rancher-manager
        local rancher_url=$(terraform output -raw rancher_url 2>/dev/null || echo 'N/A')
        local rancher_ip=$(terraform output -raw public_ip 2>/dev/null || echo 'N/A')
        echo "URL: ${rancher_url}"
        echo "Public IP: ${rancher_ip}"
        echo "Default Password: admin"
        cd ..
    fi
    echo ""

    # SUSE Observability
    print_message "$BLUE" "=== SUSE Observability ==="
    if [ -f "observability/terraform.tfstate" ]; then
        cd observability
        local obs_url=$(terraform output -raw observability_url 2>/dev/null || echo 'N/A')
        local obs_ip=$(terraform output -raw public_ip 2>/dev/null || echo 'N/A')
        echo "URL: ${obs_url}"
        echo "Public IP: ${obs_ip}"
        echo "Credentials: SSH to instance and check /root/suse-observability-credentials.txt"
        cd ..
    fi
    echo ""

    # SUSE Security
    print_message "$BLUE" "=== SUSE Security (NeuVector) ==="
    if [ -f "security/terraform.tfstate" ]; then
        cd security
        local nv_url=$(terraform output -raw neuvector_url 2>/dev/null || echo 'N/A')
        local nv_ip=$(terraform output -raw public_ip 2>/dev/null || echo 'N/A')
        echo "URL: ${nv_url}"
        echo "Public IP: ${nv_ip}"
        echo "Default Credentials: admin / admin (CHANGE IMMEDIATELY)"
        cd ..
    fi
    echo ""

    print_message "$GREEN" "=== Deployment Complete! ==="
    echo ""
    print_message "$YELLOW" "Next Steps:"
    echo "1. Wait 10-15 minutes for all services to fully start"
    echo "2. Access each service using the URLs above"
    echo "3. Follow Post_Install.md for product integration steps"
    echo ""
}

#######################################
# Main deployment flow
#######################################
main() {
    print_header "SUSE Demo AWS - Automated Deployment"

    echo "This script will deploy all SUSE demo infrastructure in the correct order:"
    echo "  1. Shared Services (VPC, networking, security groups)"
    echo "  2. Rancher Manager"
    echo "  3. SUSE Observability"
    echo "  4. SUSE Security (NeuVector)"
    echo ""
    print_message "$YELLOW" "Note: This will create AWS resources that incur costs."
    echo ""

    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "Deployment cancelled"
        exit 0
    fi

    echo ""

    # Run checks
    check_prerequisites
    validate_tfvars

    # Deploy modules
    deploy_module "shared-services" "Shared Services" || exit 1
    deploy_module "rancher-manager" "Rancher Manager" || exit 1
    deploy_module "observability" "SUSE Observability" || exit 1
    deploy_module "security" "SUSE Security" || exit 1

    # Show summary
    show_summary
}

# Run main function
main "$@"
