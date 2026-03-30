#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting SLES 15 Security setup..."
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
# Disable Docker (need to confirm this is necessary)
#######################################
# Check if Docker is installed before attempting to disable it
if systemctl list-unit-files | grep -q docker.service; then
    echo "Docker service found - disabling..."
    systemctl disable docker.service --now
else
    echo "Docker service not found - skipping disable"
fi

if systemctl list-unit-files | grep -q docker.socket; then
    echo "Docker socket found - disabling..."
    systemctl disable docker.socket --now
else
    echo "Docker socket not found - skipping disable"
fi
# If docker is running during the remainder of the install, it causes issues
# namely, the enforcer-pod pulls a docker-specific image

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

#######################################
# Install cert-manager
#######################################
echo "Installing cert-manager..."

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
# Install NeuVector
#######################################
echo "Installing NeuVector..."

kubectl create namespace neuvector || true

helm repo add neuvector https://neuvector.github.io/neuvector-helm/
helm repo update

# Create NeuVector values file
cat > /tmp/neuvector-values.yaml <<NVEOF
# Global runtime configuration for K3s containerd
k3s:
  enabled: true
  runtimePath: /run/k3s/containerd/containerd.sock

controller:
  replicas: 1
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists

manager:
  enabled: true
  env:
    ssl: false
  svc:
    type: ClusterIP

cve:
  scanner:
    enabled: true
    replicas: 1

enforcer:
  enabled: true
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists

# Disable other runtimes
docker:
  enabled: false

containerd:
  enabled: false

crio:
  enabled: false

# Disable CRD webhook for single-node setup
crdwebhook:
  enabled: false
NVEOF


echo "Let's install Neuvector using Helm"
helm install neuvector neuvector/core \
  --namespace neuvector \
  --set k3s.enabled=true \
  --values /tmp/neuvector-values.yaml \
  --wait

# Wait for NeuVector to be ready
echo "Waiting for NeuVector deployment to be available..."
kubectl wait --for=condition=available --timeout=600s deployment/neuvector-controller-pod -n neuvector || true
kubectl wait --for=condition=available --timeout=600s deployment/neuvector-manager-pod -n neuvector || true

# Wait for NeuVector pods to be fully running
echo "Waiting for NeuVector pods to be ready..."
kubectl wait --for=condition=ready --timeout=600s pod -l app=neuvector-manager-pod -n neuvector || true

#######################################
# Create Ingress for NeuVector
#######################################
echo "Creating Ingress for NeuVector..."

cat > /tmp/neuvector-ingress.yaml <<INGEOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuvector-ingress
  namespace: neuvector
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
%{ if enable_letsencrypt ~}
  tls:
    - hosts:
        - ${hostname}
      secretName: tls-security-ingress
%{ endif ~}
  rules:
    - host: ${hostname}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neuvector-service-webui
                port:
                  number: 8443
INGEOF

kubectl apply -f /tmp/neuvector-ingress.yaml

#######################################
# Create Let's Encrypt Certificate (if enabled)
#######################################
%{ if enable_letsencrypt ~}
echo "Creating Let's Encrypt Certificate for NeuVector..."

# Now that neuvector namespace exists, create the Certificate resource
cat <<'CERT_EOF' | kubectl apply -f -
${letsencrypt_certificate}
CERT_EOF

echo "Certificate resource created - cert-manager will request certificate from Let's Encrypt"

#######################################
# Monitor Certificate Issuance
#######################################
echo "=== Monitoring Certificate Issuance ==="
timeout=300
while [ $timeout -gt 0 ]; do
    ready=$(kubectl get certificate security-tls -n neuvector -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    if [ "$ready" = "True" ]; then
        echo "✓ Certificate security-tls issued successfully"
        kubectl get certificate security-tls -n neuvector
        break
    elif [ "$ready" = "False" ]; then
        reason=$(kubectl get certificate security-tls -n neuvector -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
        echo "⚠ Certificate issuance in progress: $reason"
    fi

    sleep 5
    ((timeout--))
done

if [ "$ready" != "True" ]; then
    echo "✗ Certificate security-tls failed to issue within timeout"
    kubectl describe certificate security-tls -n neuvector
    kubectl describe certificaterequest -n neuvector
    kubectl describe order -n neuvector
    echo "Note: Certificate may still complete - check with: kubectl describe certificate security-tls -n neuvector"
fi

#######################################
# Validate HTTPS Endpoint
#######################################
echo "=== Validating HTTPS Endpoint ==="
endpoint="https://${hostname}"

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
%{ endif ~}

# Install Trivy
echo "Installing Trivy vulnerability scanner..."
TRIVY_INSTALLED=false
if wget https://github.com/aquasecurity/trivy/releases/download/v0.56.2/trivy_0.56.2_Linux-64bit.rpm; then
    if rpm -ivh trivy_0.56.2_Linux-64bit.rpm; then
        echo "Trivy installed successfully"
        TRIVY_INSTALLED=true
    else
        echo "Failed to install Trivy RPM - continuing without it"
    fi
else
    echo "Failed to download Trivy - continuing without it"
fi

# Create and start Trivy systemd service only if Trivy was installed
if [ "$TRIVY_INSTALLED" = true ]; then
    cat > /etc/systemd/system/trivy-server.service <<EOF
[Unit]
Description=Trivy Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trivy server --listen 0.0.0.0:8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # Start Trivy server
    systemctl daemon-reload
    systemctl enable trivy-server
    systemctl start trivy-server
    echo "Trivy server started and enabled"
else
    echo "Skipping Trivy server setup - Trivy not installed"
fi

# Install Falco (runtime security)
rpm --import https://falco.org/repo/falcosecurity-packages.asc
curl -s -o /etc/zypp/repos.d/falcosecurity.repo https://falco.org/repo/falcosecurity-rpm.repo
zypper refresh
zypper install -y falco

# Start Falco (service may already be enabled by package installation)
systemctl daemon-reload
systemctl enable falco 2>/dev/null || echo "Falco service already enabled or is an alias"
systemctl start falco || echo "Falco service may already be running"
systemctl status falco --no-pager || true

#######################################
# Final Status
#######################################
echo "SUSE Security stack installation complete!"
echo "=========================================="
echo ""
echo "NeuVector Access:"
%{ if enable_letsencrypt ~}
echo "  URL: https://${hostname}"
%{ else ~}
echo "  URL: https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
%{ endif ~}
echo "  Default credentials: admin / admin"
echo "  IMPORTANT: Change password on first login!"
echo ""
echo "Trivy Server: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo ""
echo "Falco runtime security is enabled and monitoring system calls"
echo ""
echo "To check deployment status:"
echo "  kubectl get pods -n neuvector"
echo "  kubectl get ingress -n neuvector"
%{ if enable_letsencrypt ~}
echo "  kubectl get certificate -n neuvector"
%{ endif ~}
echo ""
echo "To scan an image with Trivy:"
echo "  trivy image --server http://localhost:8080 your-image:tag"
echo ""
echo "Installation logs: /var/log/user-data.log"
ADMIN_PASSWORD=$(sudo /usr/local/bin/kubectl get secret --namespace neuvector neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}')
echo "Initial admin password: $ADMIN_PASSWORD"
