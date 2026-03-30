#!/bin/bash
#
# Certificate Monitoring Script for SUSE Demo AWS Infrastructure
#
# This script monitors the status of all Let's Encrypt certificates
# and cert-manager components across all Kubernetes clusters.
#
# Usage: ./check-certificates.sh [--verbose] [--warn-days N]
#
# Suitable for cron scheduling:
# 0 9 * * * /path/to/check-certificates.sh >> /var/log/cert-check.log 2>&1
#

set -e

# Configuration
WARN_DAYS=30  # Days before expiration to warn
VERBOSE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --warn-days)
            WARN_DAYS="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
Certificate Monitoring Script

Usage: $0 [OPTIONS]

OPTIONS:
    --verbose, -v       Show detailed output
    --warn-days N       Days before expiration to warn (default: 30)
    --help, -h          Show this help message

EXAMPLES:
    # Check certificates with default settings
    $0

    # Check with verbose output
    $0 --verbose

    # Warn when certificates expire in 14 days
    $0 --warn-days 14

    # Schedule daily checks via cron (9 AM)
    0 9 * * * $0 >> /var/log/cert-check.log 2>&1
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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
    elif [ -f "$HOME/.kube/config" ]; then
        export KUBECONFIG=$HOME/.kube/config
    else
        print_msg "${RED}" "ERROR: KUBECONFIG not set and ~/.kube/config not found"
        exit 1
    fi
fi

# Track overall status
ISSUES_FOUND=0

print_header "Certificate Status Report - $(date)"
echo "Kubernetes Context: $(kubectl config current-context)"
echo "Warning Threshold: $WARN_DAYS days before expiration"
echo

#######################################
# Check cert-manager health
#######################################
print_header "cert-manager Health Check"

if kubectl get namespace cert-manager &> /dev/null; then
    # Check cert-manager pods
    if kubectl get pods -n cert-manager | grep -q "1/1.*Running"; then
        print_msg "${GREEN}" "✓ cert-manager pods are healthy"
        if [ "$VERBOSE" = true ]; then
            kubectl get pods -n cert-manager
        fi
    else
        print_msg "${RED}" "✗ cert-manager pods are NOT healthy"
        kubectl get pods -n cert-manager
        ((ISSUES_FOUND++))
    fi

    # Check cert-manager deployments
    for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do
        if kubectl get deployment "$deployment" -n cert-manager &> /dev/null; then
            ready=$(kubectl get deployment "$deployment" -n cert-manager -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
            if [ "$ready" = "True" ]; then
                print_msg "${GREEN}" "✓ Deployment $deployment is available"
            else
                print_msg "${RED}" "✗ Deployment $deployment is NOT available"
                ((ISSUES_FOUND++))
            fi
        fi
    done
else
    print_msg "${YELLOW}" "⚠ cert-manager namespace not found"
fi

#######################################
# Check ClusterIssuers
#######################################
print_header "ClusterIssuer Status"

if kubectl get clusterissuers &> /dev/null 2>&1; then
    for issuer in letsencrypt-staging letsencrypt-production; do
        if kubectl get clusterissuer "$issuer" &> /dev/null 2>&1; then
            status=$(kubectl get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            if [ "$status" = "True" ]; then
                print_msg "${GREEN}" "✓ ClusterIssuer $issuer is ready"
            else
                print_msg "${RED}" "✗ ClusterIssuer $issuer is NOT ready"
                if [ "$VERBOSE" = true ]; then
                    kubectl describe clusterissuer "$issuer"
                fi
                ((ISSUES_FOUND++))
            fi
        else
            if [ "$VERBOSE" = true ]; then
                print_msg "${YELLOW}" "⚠ ClusterIssuer $issuer not found"
            fi
        fi
    done
else
    print_msg "${YELLOW}" "⚠ No ClusterIssuers found"
fi

#######################################
# Check Certificates in each namespace
#######################################
print_header "Certificate Status by Namespace"

# Define certificates to check: namespace:certificate-name:secret-name
CERTIFICATES=(
    "cattle-system:rancher-tls:tls-rancher-ingress"
    "suse-observability:observability-tls:tls-observability-ingress"
    "neuvector:security-tls:tls-security-ingress"
)

for cert_info in "${CERTIFICATES[@]}"; do
    IFS=':' read -r ns cert_name secret_name <<< "$cert_info"

    echo
    print_msg "${BLUE}" "Namespace: $ns"
    print_msg "${BLUE}" "----------------------------------------"

    if ! kubectl get namespace "$ns" &> /dev/null; then
        print_msg "${YELLOW}" "⚠ Namespace $ns not found - skipping"
        continue
    fi

    if ! kubectl get certificate "$cert_name" -n "$ns" &> /dev/null 2>&1; then
        print_msg "${YELLOW}" "⚠ Certificate $cert_name not found in $ns"
        continue
    fi

    # Get certificate status
    ready=$(kubectl get certificate "$cert_name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    reason=$(kubectl get certificate "$cert_name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
    not_after=$(kubectl get certificate "$cert_name" -n "$ns" -o jsonpath='{.status.notAfter}' 2>/dev/null)
    renewal_time=$(kubectl get certificate "$cert_name" -n "$ns" -o jsonpath='{.status.renewalTime}' 2>/dev/null)

    if [ "$ready" = "True" ]; then
        print_msg "${GREEN}" "✓ Certificate: $cert_name"
        echo "  Status: Ready"
        echo "  Expires: $not_after"
        [ -n "$renewal_time" ] && echo "  Renewal: $renewal_time"

        # Check expiration date
        if [ -n "$not_after" ]; then
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$not_after" +%s 2>/dev/null)
            current_epoch=$(date +%s)
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [ $days_until_expiry -lt 0 ]; then
                print_msg "${RED}" "  ✗ EXPIRED $((days_until_expiry * -1)) days ago!"
                ((ISSUES_FOUND++))
            elif [ $days_until_expiry -lt $WARN_DAYS ]; then
                print_msg "${YELLOW}" "  ⚠ Expires in $days_until_expiry days"
                ((ISSUES_FOUND++))
            else
                print_msg "${GREEN}" "  ✓ Expires in $days_until_expiry days"
            fi
        fi

        # Verify secret exists
        if kubectl get secret "$secret_name" -n "$ns" &> /dev/null 2>&1; then
            print_msg "${GREEN}" "  ✓ Secret: $secret_name exists"
        else
            print_msg "${RED}" "  ✗ Secret: $secret_name NOT found"
            ((ISSUES_FOUND++))
        fi

    else
        print_msg "${RED}" "✗ Certificate: $cert_name"
        echo "  Status: NOT Ready"
        echo "  Reason: $reason"
        ((ISSUES_FOUND++))

        if [ "$VERBOSE" = true ]; then
            echo
            echo "Certificate Details:"
            kubectl describe certificate "$cert_name" -n "$ns"
        fi
    fi
done

#######################################
# Check for failed CertificateRequests
#######################################
print_header "Recent CertificateRequest Status"

for ns in cert-manager cattle-system suse-observability neuvector; do
    if kubectl get namespace "$ns" &> /dev/null; then
        failed_requests=$(kubectl get certificaterequest -n "$ns" --no-headers 2>/dev/null | grep -v "True" | wc -l || echo "0")
        if [ "$failed_requests" -gt 0 ]; then
            print_msg "${RED}" "✗ Found $failed_requests failed CertificateRequest(s) in $ns"
            kubectl get certificaterequest -n "$ns"
            ((ISSUES_FOUND++))
        elif [ "$VERBOSE" = true ]; then
            total_requests=$(kubectl get certificaterequest -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$total_requests" -gt 0 ]; then
                print_msg "${GREEN}" "✓ All CertificateRequests in $ns are successful ($total_requests total)"
            fi
        fi
    fi
done

#######################################
# Check for failed Orders (ACME challenges)
#######################################
if [ "$VERBOSE" = true ]; then
    print_header "ACME Order Status"

    for ns in cert-manager cattle-system suse-observability neuvector; do
        if kubectl get namespace "$ns" &> /dev/null; then
            order_count=$(kubectl get orders -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$order_count" -gt 0 ]; then
                echo "Orders in $ns:"
                kubectl get orders -n "$ns"
            fi
        fi
    done
fi

#######################################
# Summary
#######################################
print_header "Summary"

if [ $ISSUES_FOUND -eq 0 ]; then
    print_msg "${GREEN}" "✓ All certificates are healthy and valid"
    print_msg "${GREEN}" "✓ No issues found"
    echo
    print_msg "${BLUE}" "Next check should run: $(date -d '+1 day' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v+1d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    exit 0
else
    print_msg "${RED}" "✗ Found $ISSUES_FOUND issue(s) requiring attention"
    echo
    print_msg "${YELLOW}" "Recommended actions:"
    echo "  1. Review certificate status: kubectl get certificates -A"
    echo "  2. Check cert-manager logs: kubectl logs -n cert-manager -l app=cert-manager --tail=100"
    echo "  3. Verify ClusterIssuers: kubectl describe clusterissuers"
    echo "  4. Check recent orders: kubectl get orders -A"
    exit 1
fi
