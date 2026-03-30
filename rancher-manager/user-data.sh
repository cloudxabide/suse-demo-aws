#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting SLES 15 Kubernetes setup..."
echo "Running as: $(whoami)"
echo "Started at: $(date)"

#######################################
# SUSE Registration and update
#######################################
echo "Registering SLES 15 system with SUSE Customer Center..."

# Register the system with SUSE Customer Center
if [ -n "${smt_url}" ]; then
    # Register with SMT/RMT server
    echo "SUSEConnect --url \"${smt_url}\" --regcode \"${suse_regcode}\" --email \"${suse_email}\" "
    SUSEConnect --url "${smt_url}" --regcode "${suse_regcode}" --email "${suse_email}"
else
    # Register with SUSE Customer Center (default)
    echo "SUSEConnect --regcode \"${suse_regcode}\" --email \"${suse_email}\" "
    SUSEConnect --regcode "${suse_regcode}" --email "${suse_email}"
fi

# Verify registration
SUSEConnect --status

echo "SLES registration completed successfully"

# Update system
zypper refresh
zypper update -y

#######################################
# Validate CA Trust Store
#######################################
echo "=== Validating CA Trust Store ==="
# Install CA certificates package if not present
zypper install -y ca-certificates-mozilla

# Update trust store
if update-ca-certificates --fresh; then
    echo "✓ CA trust store updated successfully"
else
    echo "✗ CA trust store update failed"
    exit 1
fi

# Verify ISRG Root X1 (Let's Encrypt) is present (multiple possible locations)
if grep -qr "ISRG Root X1" /etc/pki/trust/ /var/lib/ca-certificates/ 2>/dev/null || \
   grep -q "Let's Encrypt" /var/lib/ca-certificates/ca-bundle.pem 2>/dev/null || \
   [ -f "/etc/pki/trust/anchors/ISRG_Root_X1.pem" ] || \
   [ -f "/usr/share/pki/trust/anchors/ISRG_Root_X1.pem" ]; then
    echo "✓ Let's Encrypt root CA is trusted"
else
    echo "⚠ Let's Encrypt root CA verification inconclusive (may still be trusted via system defaults)"
    echo "  Continuing deployment - Let's Encrypt should work with default SLES 15 trust store"
fi

#######################################
# Install required packages
#######################################
zypper install -y curl wget git-core

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

#######################################
# Install K3s with TLS SANs
#######################################
# Get instance metadata for TLS certificate SANs
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Installing K3s with TLS SANs..."
echo "  Hostname: ${hostname}"
echo "  Public IP: $PUBLIC_IP"
echo "  Private IP: $PRIVATE_IP"

# Set K3s version if specified, otherwise use latest stable
if [ -n "${k3s_version}" ]; then
  export INSTALL_K3S_VERSION="${k3s_version}"
  echo "Installing K3s version: ${k3s_version}"
else
  echo "Installing latest stable K3s version"
fi

curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san ${hostname} \
  --tls-san $PUBLIC_IP \
  --tls-san $PRIVATE_IP

# Wait for K3s service to be active
echo "Waiting for K3s service to be active..."
until systemctl is-active --quiet k3s; do
  echo "K3s service not yet active..."
  sleep 5
done

# Set up kubeconfig and bash ENV for root/ec2-user
mkdir -p /root/.kube /home/ec2-user/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config
export KUBECONFIG=/root/.kube/config
cat << EOF | tee -a /root/.bashrc
export KUBECONFIG=/root/.kube/config
alias kge='clear; kubectl get events --sort-by=.lastTimestamp'
alias kgea='clear; kubectl get events -A --sort-by=.lastTimestamp'
set -o vi
EOF
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
# TEST - Added a PS1 var to test.  I'd like to see/know what system I am connected to
cat << EOF | tee -a /home/ec2-user/.bashrc
export KUBECONFIG=~/.kube/config
alias kge='clear; kubectl get events --sort-by=.lastTimestamp'
alias kgea='clear; kubectl get events -A --sort-by=.lastTimestamp'
set -o vi
PS1="\u@\h - ${hostname_short} - \w \$ "
EOF
chown -R ec2-user /home/ec2-user/.kube

# Wait for K3s API server to be responsive
echo "Waiting for K3s API server to be ready..."
until kubectl get nodes > /dev/null 2>&1; do
  echo "K3s API server not yet responsive..."
  sleep 5
done

# Wait for nodes to be Ready
echo "Waiting for K3s node to be Ready..."
until kubectl wait --for=condition=Ready nodes --all --timeout=10s > /dev/null 2>&1; do
  echo "K3s node not yet ready..."
  sleep 5
done

# Wait for core K3s components to be running
echo "Waiting for core K3s components..."
until kubectl get deployment -n kube-system coredns > /dev/null 2>&1; do
  echo "CoreDNS not yet deployed..."
  sleep 5
done

kubectl wait --for=condition=available --timeout=300s deployment/coredns -n kube-system

echo "K3s is fully ready!" 

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v${cert_manager_version}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager || true

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v${cert_manager_version} \
  --wait

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

#######################################
# Validate cert-manager Installation
#######################################
echo "=== Validating cert-manager Installation ==="

# Wait for cert-manager webhook to be ready
if kubectl wait --for=condition=Available deployment/cert-manager-webhook \
  -n cert-manager --timeout=300s; then
    echo "✓ cert-manager webhook is available"
else
    echo "✗ cert-manager webhook failed to become available"
    kubectl logs -n cert-manager -l app=cert-manager --tail=50
    exit 1
fi

#######################################
# Configure Let's Encrypt ClusterIssuer (if enabled)
#######################################
%{ if enable_letsencrypt ~}
echo "Configuring Let's Encrypt ClusterIssuer..."

# Create ClusterIssuer for Let's Encrypt
cat <<'ISSUER_EOF' | kubectl apply -f -
${letsencrypt_clusterissuer}
ISSUER_EOF

echo "Let's Encrypt ClusterIssuers created (staging and production)"
echo "Using environment: ${letsencrypt_environment}"

#######################################
# Validate ClusterIssuers
#######################################
echo "=== Validating Let's Encrypt ClusterIssuers ==="
for issuer in letsencrypt-staging letsencrypt-production; do
    timeout=60
    while [ $timeout -gt 0 ]; do
        status=$(kubectl get clusterissuer $issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$status" = "True" ]; then
            echo "✓ ClusterIssuer $issuer is ready"
            break
        fi
        sleep 2
        ((timeout--))
    done

    if [ "$status" != "True" ]; then
        echo "✗ ClusterIssuer $issuer failed to become ready"
        kubectl describe clusterissuer $issuer
        exit 1
    fi
done
%{ endif ~}

#######################################
# Create cattle-system namespace and Certificate (if Let's Encrypt enabled)
#######################################
kubectl create namespace cattle-system || true

%{ if enable_letsencrypt ~}
echo "Creating Let's Encrypt Certificate for Rancher..."

# Create the Certificate resource BEFORE installing Rancher
cat <<'CERT_EOF' | kubectl apply -f -
${letsencrypt_certificate}
CERT_EOF

echo "Certificate resource created - waiting for cert-manager to issue certificate..."

#######################################
# Monitor Certificate Issuance
#######################################
echo "=== Monitoring Certificate Issuance ==="
timeout=300
while [ $timeout -gt 0 ]; do
    ready=$(kubectl get certificate rancher-tls -n cattle-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    if [ "$ready" = "True" ]; then
        echo "✓ Certificate rancher-tls issued successfully"
        kubectl get certificate rancher-tls -n cattle-system
        break
    elif [ "$ready" = "False" ]; then
        reason=$(kubectl get certificate rancher-tls -n cattle-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
        echo "⚠ Certificate issuance in progress: $reason"
    fi

    sleep 5
    ((timeout--))
done

if [ "$ready" != "True" ]; then
    echo "⚠ Certificate rancher-tls not ready within timeout - continuing anyway"
    kubectl describe certificate rancher-tls -n cattle-system
    kubectl describe certificaterequest -n cattle-system
    kubectl describe order -n cattle-system
    echo "Note: Rancher installation will proceed - certificate may complete in background"
fi

# Verify the TLS secret exists before installing Rancher
echo "Verifying TLS secret exists..."
if kubectl get secret tls-rancher-ingress -n cattle-system > /dev/null 2>&1; then
    echo "✓ TLS secret tls-rancher-ingress exists"
else
    echo "⚠ TLS secret not found - Rancher ingress may have issues until certificate completes"
fi
%{ endif ~}

#######################################
# Install Rancher
#######################################
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

%{ if enable_letsencrypt ~}
# Install Rancher with external cert-manager (we manage certificates ourselves)
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=${hostname} \
  --set replicas=1 \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=secret \
  --set privateCA=false \
  --version ${rancher_version} \
  --wait \
  --timeout 15m
%{ else ~}
# Install Rancher with default self-signed certificate
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=${hostname} \
  --set replicas=1 \
  --set bootstrapPassword=admin \
  --version ${rancher_version} \
  --wait \
  --timeout 15m
%{ endif ~}

# Wait for Rancher to be ready
echo "Waiting for Rancher deployment to be available..."
kubectl -n cattle-system wait --for=condition=available --timeout=600s deployment/rancher

# Wait for Rancher pods to be fully running
echo "Waiting for Rancher pods to be ready..."
kubectl -n cattle-system wait --for=condition=ready --timeout=600s pod -l app=rancher

%{ if enable_letsencrypt ~}
#######################################
# Validate HTTPS Endpoint with Let's Encrypt Certificate
#######################################
echo "=== Validating HTTPS Endpoint ==="

# Wait for DNS propagation
echo "Waiting for DNS propagation..."
timeout=120
while [ $timeout -gt 0 ]; do
    if nslookup ${hostname} > /dev/null 2>&1; then
        echo "✓ DNS resolution successful for ${hostname}"
        break
    fi
    sleep 5
    ((timeout--))
done

# Test TLS connection (best effort - may fail if still propagating)
if command -v openssl >/dev/null 2>&1; then
    echo "Testing TLS certificate chain..."
    echo | openssl s_client -connect ${hostname}:443 -servername ${hostname} 2>/dev/null | \
      openssl x509 -noout -subject -issuer -dates 2>/dev/null || \
      echo "Note: TLS verification pending - DNS/certificate may still be propagating"
fi

# Final certificate status check
cert_ready=$(kubectl get certificate rancher-tls -n cattle-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$cert_ready" = "True" ]; then
    echo "✓ Let's Encrypt certificate is ready and in use"
else
    echo "⚠ Certificate may still be finalizing - check: kubectl describe certificate rancher-tls -n cattle-system"
fi
%{ endif ~}

echo "Rancher installation complete!"
echo "Access Rancher at: https://${hostname}"
echo "Bootstrap password: admin"
echo "Please change the password on first login"
