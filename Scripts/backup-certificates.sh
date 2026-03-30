#!/bin/bash
#
# Certificate Backup Script for SUSE Demo AWS Infrastructure
#
# This script backs up all Let's Encrypt certificates and cert-manager
# account keys from the Kubernetes clusters.
#
# Usage: ./backup-certificates.sh [backup-directory]
#

set -e

# Configuration
BACKUP_BASE_DIR="${1:-/root/cert-backups}"
BACKUP_DIR="${BACKUP_BASE_DIR}/$(date +%Y%m%d-%H%M%S)"
NAMESPACES=("cert-manager" "cattle-system" "suse-observability" "neuvector")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

print_msg() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    print_msg "${BLUE}" "========================================"
    print_msg "${BLUE}" "$1"
    print_msg "${BLUE}" "========================================"
}

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

print_header "Certificate Backup - $(date)"

# Create backup directory
mkdir -p "$BACKUP_DIR"
print_msg "${GREEN}" "Created backup directory: $BACKUP_DIR"

#######################################
# Backup cert-manager account keys
#######################################
print_msg "${BLUE}" "Backing up cert-manager account keys..."

if kubectl get namespace cert-manager &> /dev/null; then
    kubectl get secrets -n cert-manager \
      -o yaml > "$BACKUP_DIR/cert-manager-all-secrets.yaml"

    # Backup ACME account keys specifically
    kubectl get secrets -n cert-manager \
      -l "acme.cert-manager.io/private-key=account-key" \
      -o yaml > "$BACKUP_DIR/cert-manager-account-keys.yaml" 2>/dev/null || \
      print_msg "${YELLOW}" "No ACME account keys found"

    print_msg "${GREEN}" "✓ cert-manager secrets backed up"
else
    print_msg "${YELLOW}" "⚠ cert-manager namespace not found - skipping"
fi

#######################################
# Backup TLS certificates from all namespaces
#######################################
for ns in "cattle-system" "suse-observability" "neuvector"; do
    print_msg "${BLUE}" "Backing up certificates from namespace: $ns..."

    if kubectl get namespace "$ns" &> /dev/null; then
        # Backup all Certificate resources
        kubectl get certificates -n "$ns" -o yaml > "$BACKUP_DIR/${ns}-certificates.yaml" 2>/dev/null || \
          print_msg "${YELLOW}" "No Certificate resources found in $ns"

        # Backup TLS secrets
        kubectl get secrets -n "$ns" -o yaml > "$BACKUP_DIR/${ns}-secrets.yaml" 2>/dev/null || \
          print_msg "${YELLOW}" "No secrets found in $ns"

        # Backup specific TLS secrets
        for secret in tls-rancher-ingress tls-observability-ingress tls-security-ingress; do
            if kubectl get secret "$secret" -n "$ns" &> /dev/null 2>&1; then
                kubectl get secret "$secret" -n "$ns" -o yaml > "$BACKUP_DIR/${ns}-${secret}.yaml"
                print_msg "${GREEN}" "✓ Backed up secret: $secret"
            fi
        done
    else
        print_msg "${YELLOW}" "⚠ Namespace $ns not found - skipping"
    fi
done

#######################################
# Backup ClusterIssuers
#######################################
print_msg "${BLUE}" "Backing up ClusterIssuers..."
kubectl get clusterissuers -o yaml > "$BACKUP_DIR/clusterissuers.yaml" 2>/dev/null || \
  print_msg "${YELLOW}" "No ClusterIssuers found"

#######################################
# Create backup manifest
#######################################
cat > "$BACKUP_DIR/backup-manifest.txt" <<EOF
Certificate Backup Manifest
===========================
Date: $(date)
Backup Directory: $BACKUP_DIR
Kubernetes Context: $(kubectl config current-context)

Files Created:
$(ls -lh "$BACKUP_DIR")

Certificate Status at Backup Time:
-----------------------------------
EOF

# Append certificate status for each namespace
for ns in "cattle-system" "suse-observability" "neuvector"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        echo "" >> "$BACKUP_DIR/backup-manifest.txt"
        echo "Namespace: $ns" >> "$BACKUP_DIR/backup-manifest.txt"
        kubectl get certificates -n "$ns" >> "$BACKUP_DIR/backup-manifest.txt" 2>/dev/null || \
          echo "No certificates found" >> "$BACKUP_DIR/backup-manifest.txt"
    fi
done

print_header "Backup Complete!"
print_msg "${GREEN}" "Backup location: $BACKUP_DIR"
print_msg "${GREEN}" "Total backup size: $(du -sh "$BACKUP_DIR" | cut -f1)"
echo
print_msg "${BLUE}" "Backup Contents:"
ls -lh "$BACKUP_DIR"

#######################################
# Cleanup old backups (keep last 7 days)
#######################################
print_msg "${BLUE}" "Cleaning up old backups (keeping last 7 days)..."
find "$BACKUP_BASE_DIR" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
print_msg "${GREEN}" "✓ Cleanup complete"

echo
print_msg "${YELLOW}" "To restore from this backup, use: ./restore-certificates.sh $BACKUP_DIR"
