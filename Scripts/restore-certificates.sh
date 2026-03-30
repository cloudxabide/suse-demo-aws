#!/bin/bash
#
# Certificate Restore Script for SUSE Demo AWS Infrastructure
#
# This script restores Let's Encrypt certificates and cert-manager
# account keys from a backup directory.
#
# Usage: ./restore-certificates.sh <backup-directory> [--force]
#
# WARNING: This will overwrite existing certificates and secrets!
#

set -e

# Configuration
BACKUP_DIR="$1"
FORCE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Parse arguments
if [ -z "$BACKUP_DIR" ]; then
    echo "Usage: $0 <backup-directory> [--force]"
    echo
    echo "Example:"
    echo "  $0 /root/cert-backups/20250113-120000"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompt"
    exit 1
fi

if [ "$2" = "--force" ]; then
    FORCE=true
fi

print_msg() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    print_msg "${BLUE}" "========================================"
    print_msg "${BLUE}" "$1"
    print_msg "${BLUE}" "========================================"
}

# Verify backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    print_msg "${RED}" "ERROR: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Verify kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_msg "${RED}" "ERROR: kubectl not found in PATH"
    exit 1
fi

# Verify KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    if [ -f "/root/.kube/config" ]; then
        export KUBECONFIG=/root/.kube/config
    else
        print_msg "${RED}" "ERROR: KUBECONFIG not set and /root/.kube/config not found"
        exit 1
    fi
fi

print_header "Certificate Restore - $(date)"
echo "Backup Directory: $BACKUP_DIR"
echo "Kubernetes Context: $(kubectl config current-context)"
echo

# Show backup contents
print_msg "${BLUE}" "Backup Contents:"
ls -lh "$BACKUP_DIR"
echo

if [ -f "$BACKUP_DIR/backup-manifest.txt" ]; then
    print_msg "${BLUE}" "Backup Manifest:"
    cat "$BACKUP_DIR/backup-manifest.txt"
    echo
fi

# Confirmation prompt
if [ "$FORCE" != true ]; then
    print_msg "${YELLOW}" "WARNING: This will overwrite existing certificates and secrets!"
    print_msg "${YELLOW}" "Make sure you are restoring to the correct cluster."
    echo
    read -p "Continue with restore? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_msg "${YELLOW}" "Restore cancelled"
        exit 0
    fi
fi

RESTORED_COUNT=0
FAILED_COUNT=0

#######################################
# Restore cert-manager secrets
#######################################
print_header "Restoring cert-manager Secrets"

if [ -f "$BACKUP_DIR/cert-manager-account-keys.yaml" ]; then
    print_msg "${BLUE}" "Restoring cert-manager ACME account keys..."

    if kubectl apply -f "$BACKUP_DIR/cert-manager-account-keys.yaml"; then
        print_msg "${GREEN}" "✓ cert-manager account keys restored"
        ((RESTORED_COUNT++))
    else
        print_msg "${RED}" "✗ Failed to restore cert-manager account keys"
        ((FAILED_COUNT++))
    fi
else
    print_msg "${YELLOW}" "⚠ No cert-manager account keys backup found"
fi

#######################################
# Restore ClusterIssuers
#######################################
print_header "Restoring ClusterIssuers"

if [ -f "$BACKUP_DIR/clusterissuers.yaml" ]; then
    print_msg "${BLUE}" "Restoring ClusterIssuers..."

    if kubectl apply -f "$BACKUP_DIR/clusterissuers.yaml"; then
        print_msg "${GREEN}" "✓ ClusterIssuers restored"
        ((RESTORED_COUNT++))

        # Wait for ClusterIssuers to be ready
        print_msg "${BLUE}" "Waiting for ClusterIssuers to be ready..."
        sleep 5

        for issuer in letsencrypt-staging letsencrypt-production; do
            timeout=30
            while [ $timeout -gt 0 ]; do
                status=$(kubectl get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                if [ "$status" = "True" ]; then
                    print_msg "${GREEN}" "✓ ClusterIssuer $issuer is ready"
                    break
                fi
                sleep 2
                ((timeout--))
            done

            if [ "$status" != "True" ]; then
                print_msg "${YELLOW}" "⚠ ClusterIssuer $issuer not ready yet (may need more time)"
            fi
        done
    else
        print_msg "${RED}" "✗ Failed to restore ClusterIssuers"
        ((FAILED_COUNT++))
    fi
else
    print_msg "${YELLOW}" "⚠ No ClusterIssuers backup found"
fi

#######################################
# Restore certificates from each namespace
#######################################
for ns in "cattle-system" "suse-observability" "neuvector"; do
    print_header "Restoring Certificates in Namespace: $ns"

    # Check if namespace exists
    if ! kubectl get namespace "$ns" &> /dev/null; then
        print_msg "${YELLOW}" "⚠ Namespace $ns does not exist - creating..."
        kubectl create namespace "$ns" || print_msg "${RED}" "Failed to create namespace $ns"
    fi

    # Restore Certificate resources
    if [ -f "$BACKUP_DIR/${ns}-certificates.yaml" ]; then
        print_msg "${BLUE}" "Restoring Certificate resources..."

        if kubectl apply -f "$BACKUP_DIR/${ns}-certificates.yaml"; then
            print_msg "${GREEN}" "✓ Certificate resources restored in $ns"
            ((RESTORED_COUNT++))
        else
            print_msg "${RED}" "✗ Failed to restore Certificate resources in $ns"
            ((FAILED_COUNT++))
        fi
    else
        print_msg "${YELLOW}" "⚠ No Certificate resources backup found for $ns"
    fi

    # Restore TLS secrets (only if Certificate resources are not present or failed)
    for secret_file in "$BACKUP_DIR/${ns}-tls-"*.yaml; do
        if [ -f "$secret_file" ]; then
            secret_name=$(basename "$secret_file" .yaml | sed "s/${ns}-//")
            print_msg "${BLUE}" "Restoring secret: $secret_name..."

            if kubectl apply -f "$secret_file"; then
                print_msg "${GREEN}" "✓ Secret $secret_name restored"
                ((RESTORED_COUNT++))
            else
                print_msg "${RED}" "✗ Failed to restore secret $secret_name"
                ((FAILED_COUNT++))
            fi
        fi
    done
done

#######################################
# Verify restored certificates
#######################################
print_header "Verifying Restored Certificates"

sleep 5  # Give Kubernetes time to process

CERTIFICATES=(
    "cattle-system:rancher-tls"
    "suse-observability:observability-tls"
    "neuvector:security-tls"
)

for cert_info in "${CERTIFICATES[@]}"; do
    IFS=':' read -r ns cert_name <<< "$cert_info"

    if kubectl get namespace "$ns" &> /dev/null && \
       kubectl get certificate "$cert_name" -n "$ns" &> /dev/null 2>&1; then

        ready=$(kubectl get certificate "$cert_name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

        if [ "$ready" = "True" ]; then
            print_msg "${GREEN}" "✓ Certificate $cert_name in $ns is ready"
        else
            print_msg "${YELLOW}" "⚠ Certificate $cert_name in $ns is not ready yet"
            print_msg "${YELLOW}" "  This is normal - cert-manager may be processing the certificate"
            print_msg "${YELLOW}" "  Check status with: kubectl describe certificate $cert_name -n $ns"
        fi
    fi
done

#######################################
# Summary
#######################################
print_header "Restore Summary"

print_msg "${GREEN}" "✓ Successfully restored: $RESTORED_COUNT items"
if [ $FAILED_COUNT -gt 0 ]; then
    print_msg "${RED}" "✗ Failed to restore: $FAILED_COUNT items"
fi

echo
print_msg "${BLUE}" "Next Steps:"
echo "  1. Verify certificate status:"
echo "     kubectl get certificates -A"
echo
echo "  2. Check cert-manager logs:"
echo "     kubectl logs -n cert-manager -l app=cert-manager --tail=50"
echo
echo "  3. Monitor certificate issuance:"
echo "     kubectl describe certificate <cert-name> -n <namespace>"
echo
echo "  4. Run certificate health check:"
echo "     ./check-certificates.sh"
echo

if [ $FAILED_COUNT -eq 0 ]; then
    print_msg "${GREEN}" "✓ Restore completed successfully!"
    exit 0
else
    print_msg "${YELLOW}" "⚠ Restore completed with some failures"
    exit 1
fi
