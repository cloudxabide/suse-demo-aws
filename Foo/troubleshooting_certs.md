# Troubleshooting Certs

I use the following to troubleshoot any certificate issues (which are primarily due to exceeding rate limit).  
I tried using "staging" with Let's Encrypt, but would get browser errors and connectivity issues between clusters and services due to untrusted CA.

# Update the following var(s):
DAENV=staging # staging production are the 2 options

# Gather some infor re: Name of cert and Namespace
# NOTE: this, obviously, would not work on a system with a bunch of certificates.  This command is only for this demo 
DANAMESPACE=$(kubectl get certificate -A --no-headers -o custom-columns=NAME:metadata.namespace)
DACERTNAME=$(kubectl get certificate -A --no-headers -o custom-columns=NAME:metadata.name)

# First, let's review the status - if this says True in column 3, it was successful
kubectl get certificate -A --no-headers
kubectl describe certificate $DACERTNAME -n $DANAMESPACE

# Then we will check request and status
kubectl get certificaterequest -n $DANAMESPACE 
kubectl describe certificaterequest $DACERTNAME -n $DANAMESPACE

kubectl describe clusterissuer letsencrypt-$DAENV

# Check the logs of cert-manager
kubect logs -l app=cert-manager -n cert-manager



  Option 1: Wait (Recommended for Now)

  The 503 errors are temporary "service busy" responses. cert-manager will keep retrying with exponential backoff. Monitor progress:

  # Watch certificate status
  ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@16.58.104.40 'watch kubectl get certificate,certificaterequest -n cattle-system'

  # Check if finalization succeeds
  ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@16.58.104.40 'kubectl logs -n cert-manager deployment/cert-manager -f | grep -i "rancher-tls\|finalize"'

  Option 2: Delete and Recreate (If Urgent)

  Force cert-manager to start fresh with a new order:

  ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@16.58.104.40 << 'EOF'
  kubectl delete certificaterequest rancher-tls-1 -n cattle-system
  kubectl delete order rancher-tls-1-3455351491 -n cattle-system
  kubectl delete challenge rancher-tls-1-3455351491-3040828498 -n cattle-system
  # Certificate will automatically create a new request
  EOF

  Warning: This may hit the same rate limit if Let's Encrypt is still limiting your account/IP.

  Option 3: Switch to Production (If Appropriate)

  If this is for actual use, switch from staging to production issuer (production has higher limits but counts toward your certificate quota):

  ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@16.58.104.40 'kubectl edit certificate rancher-tls -n cattle-system'
  # Change: issuerRef.name from "letsencrypt-staging" to "letsencrypt-production"

