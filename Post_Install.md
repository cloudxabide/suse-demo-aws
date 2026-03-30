# Post-Installation Integration Guide

After all products have deployed successfully (typically 15-20 minutes), follow these steps to integrate the SUSE products together for a complete demo environment.

## Prerequisites

- All three product modules deployed successfully:
  - Rancher Manager
  - SUSE Observability
  - SUSE Security (NeuVector)
- Access credentials for each product UI
- All services are accessible via their URLs

---

## Overview of Integration Steps

1. **Configure Rancher Manager TLS Settings** - Update certificate validation mode
2. **Add Observability Cluster to Rancher Manager** - Import for centralized management
3. **Add Security Cluster to Rancher Manager** - Import for centralized management
4. **Add All Clusters to SUSE Observability** - Monitor all three clusters using Rancher's kubectl shell

---

## 1. Configure Rancher Manager TLS Settings

First, update Rancher Manager to trust system certificates for agent communication.

### Steps:
1. Login to **Rancher Manager UI**
2. Click the **globe icon** in the lower left-hand corner
3. Navigate to **Settings**
4. Scroll down and find **"agent-tls-mode"**
5. Change the value to **"System Store"**
6. Click **Save**

**Why this matters:** This allows Rancher agents to properly validate TLS certificates when connecting to the Rancher server.

---

## 2. Add Observability Cluster to Rancher Manager

Import the SUSE Observability cluster into Rancher for centralized management.

### Steps:

#### 2.1 Initiate Import in Rancher
1. In **Rancher Manager UI**, click **Cluster Management** (barn/silo icon on left)
2. Click **Import Existing** (upper right)
3. Select **Generic** as the cluster type
4. Enter cluster details:
   - **Cluster Name:** `observability`
   - **Description:** `SUSE Observability (StackState) Cluster`
5. Click **Create**

#### 2.2 Apply Registration to Observability Cluster
1. Rancher will display kubectl commands - **copy the first set** to clipboard
2. SSH to the **Observability node**:
   ```bash
   # From your local machine - use terraform output
   cd observability
   terraform output -raw ssh_command

   # Or manually:
   ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@<observability-ip>
   ```
3. Switch to root:
   ```bash
   sudo su -
   ```
4. Paste and execute the Rancher registration commands
5. Monitor the agent deployment:
   ```bash
   kubectl get pods -n cattle-system -w
   ```
6. Wait for all cattle-system pods to be **Running** (press Ctrl+C to exit watch)

### Verify Integration:
- The **observability** cluster should appear in Rancher **Cluster Management**
- Cluster state should show as **Active**
- Click on the cluster name to verify you can access it

---

## 3. Add Security Cluster to Rancher Manager

Import the SUSE Security (NeuVector) cluster into Rancher.

### Steps:

#### 3.1 Initiate Import in Rancher
1. In **Rancher Manager UI**, click **Cluster Management**
2. Click **Import Existing** (upper right)
3. Select **Generic**
4. Enter cluster details:
   - **Cluster Name:** `security`
   - **Description:** `SUSE Security (NeuVector) Cluster`
5. Click **Create**

#### 3.2 Apply Registration to Security Cluster
1. Copy the first set of kubectl commands from Rancher
2. SSH to the **Security node**:
   ```bash
   # From your local machine - use terraform output
   cd security
   terraform output -raw ssh_command

   # Or manually:
   ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@<security-ip>
   ```
3. Switch to root:
   ```bash
   sudo su -
   ```
4. Paste and execute the Rancher registration commands
5. Monitor the deployment:
   ```bash
   kubectl get pods -n cattle-system -w
   ```
6. Wait for all cattle-system pods to be **Running** (press Ctrl+C to exit watch)

### Verify Integration:
- **security** cluster appears in Rancher **Cluster Management**
- Cluster state shows as **Active**
- Click on the cluster name to verify you can access it

**Result:** All three clusters (local, observability, security) are now managed by Rancher Manager.

---

## 4. Add All Clusters to SUSE Observability

Now use Rancher Manager's built-in kubectl shell to add monitoring agents to all three clusters. This is much easier than SSH'ing to each node!

### 4.1 Install Rancher StackPack on Local Cluster

#### Get StackPack Commands from Observability
1. Open **SUSE Observability UI** in a new tab (keep Rancher open)
2. Navigate to **StackPacks** (should be the default view)
3. Search for **"Rancher"** in the StackPacks search
4. Click on the **Rancher** StackPack
5. Click **CREATE NEW SERVICE TOKEN**
6. **Copy** the commands displayed (they'll create a token and deploy the agent)

#### Install on Rancher's Local Cluster
1. Go back to **Rancher Manager UI**
2. Click **Cluster Management** → **local** cluster
3. Click the **Kubectl Shell** button (button with ">_" icon, upper right)
4. **Paste** the Rancher StackPack commands into the kubectl shell
5. Press **Enter** to execute
6. Verify deployment:
   ```bash
   kubectl get pods -n stackstate
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=stackstate-agent -n stackstate --timeout=300s
   ```

**Result:** Rancher Manager (local cluster) is now monitored by SUSE Observability.

---

### 4.2 Install Generic Kubernetes Agent on Observability Cluster

#### Get Generic Kubernetes StackPack Commands
1. In **SUSE Observability UI**, search for **"Generic Kubernetes"**
2. Select the **Generic Kubernetes (including RKE2)** StackPack
3. Click **ADD INSTANCE** or **CREATE NEW SERVICE TOKEN**
4. **Copy** the commands from **Section 1** (Create Service Token) - keep this handy
5. **Copy** the commands from **Section 2** (Deploy Agent) - keep this handy

#### Install on Observability Cluster via Rancher
1. In **Rancher Manager UI**, go to **Cluster Management**
2. Click on the **observability** cluster
3. Click the **Kubectl Shell** button (upper right)
4. **Paste** Section 1 commands (token creation) → Press **Enter**
5. **Paste** Section 2 commands (agent deployment) → Press **Enter**
6. Verify deployment:
   ```bash
   kubectl get pods -n stackstate
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=stackstate-agent -n stackstate --timeout=300s
   ```

**Result:** Observability cluster is now monitoring itself via SUSE Observability.

---

### 4.3 Install Generic Kubernetes Agent on Security Cluster

Use the same Generic Kubernetes StackPack commands you got in step 4.2.

#### Install on Security Cluster via Rancher
1. In **Rancher Manager UI**, go to **Cluster Management**
2. Click on the **security** cluster
3. Click the **Kubectl Shell** button (upper right)
4. **Paste** Section 1 commands (token creation from step 4.2) → Press **Enter**
5. **Paste** Section 2 commands (agent deployment from step 4.2) → Press **Enter**
6. Verify deployment:
   ```bash
   kubectl get pods -n stackstate
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=stackstate-agent -n stackstate --timeout=300s
   ```

**Result:** Security cluster is now monitored by SUSE Observability.

---

### 4.4 Verify All Clusters in SUSE Observability

1. Go to **SUSE Observability UI**
2. Navigate to **Explore** or **Topology** view
3. You should see all three clusters:
   - **Rancher Manager** (local cluster)
   - **Observability** cluster
   - **Security** cluster
4. Verify metrics are flowing:
   - Click on each cluster
   - Check that pods, nodes, and services are visible
   - Verify health status is green

**Success!** All three Kubernetes clusters are now monitored by SUSE Observability, and you managed everything from Rancher's UI without SSH'ing to any nodes!

---

## 5. Configure NeuVector Multi-Cluster (Optional)

If you want centralized security policy management across all clusters:

### Steps:
1. Login to **NeuVector UI** on the security cluster
2. Click on **Admin** dropdown (upper right)
3. Navigate to **Multiple Clusters**
4. Click **Promote** to promote this cluster to Primary
5. Follow the UI wizard to generate federation tokens
6. Apply federation tokens to other clusters using Rancher's kubectl shell

**Note:** This step is optional and for advanced multi-cluster security management.

---

## Post-Integration Validation

After completing all integrations, verify the setup:

### Rancher Manager
- [ ] All three clusters visible in Cluster Management (local, observability, security)
- [ ] All clusters show **Active** state
- [ ] Can kubectl into each cluster from Rancher UI
- [ ] Agent TLS mode set to **"System Store"**

### SUSE Observability
- [ ] All three clusters visible in topology
- [ ] Metrics flowing from all clusters
- [ ] Health status showing for all components
- [ ] No critical alerts for cluster connectivity
- [ ] Can see NeuVector components in topology (from security cluster)
- [ ] Can see Rancher components in topology (from local cluster)

### SUSE Security (NeuVector)
- [ ] NeuVector UI accessible
- [ ] Container scanning working
- [ ] Network policies visible
- [ ] Runtime protection enabled

---

## Troubleshooting

### Agent Pods Not Starting
```bash
# Use Rancher's kubectl shell for the affected cluster
kubectl get pods -n cattle-system
kubectl get pods -n stackstate

# View logs
kubectl logs -n cattle-system -l app=cattle-cluster-agent
kubectl logs -n stackstate -l app.kubernetes.io/name=stackstate-agent
```

### Cluster Not Appearing in Rancher
- Verify cattle-system namespace exists: `kubectl get ns`
- Check registration URL is accessible from the cluster
- Ensure security groups allow required ports (port 443 for Rancher)
- Check cattle-system pods are running: `kubectl get pods -n cattle-system`

### SUSE Observability Agent Not Connecting
- Verify Observability Router is accessible (port 8080)
- Check service token is valid (create a new one if needed)
- Review agent logs for connection errors:
  ```bash
  kubectl logs -n stackstate -l app.kubernetes.io/name=stackstate-agent --tail=100
  ```
- Verify security groups allow traffic from clusters to Observability instance

### Using Rancher's Kubectl Shell
- If kubectl shell is slow or unresponsive, refresh the browser
- Commands run as cluster-admin in the selected cluster
- Shell session persists for 15 minutes of inactivity
- You can open multiple shells to different clusters in different tabs

### General Connectivity Issues
- Verify all EIPs are associated
- Check Route53 DNS records are resolving:
  ```bash
  nslookup rancher.suse-demo-aws.kubernerdes.com
  nslookup observability.suse-demo-aws.kubernerdes.com
  nslookup security.suse-demo-aws.kubernerdes.com
  ```
- Confirm security groups allow required ports
- Test network connectivity: `curl -v https://<service-url>`

---

## Next Steps

After integration is complete:

1. **Explore SUSE Observability**
   - Review topology maps for all three clusters
   - Set up custom dashboards
   - Configure alerting rules
   - Explore relationships between clusters

2. **Configure NeuVector Policies**
   - Enable runtime protection
   - Set up network segmentation
   - Configure compliance scanning
   - Review security events

3. **Deploy Test Applications via Rancher**
   - Use Rancher's App Catalog
   - Deploy to multiple clusters
   - Monitor via SUSE Observability
   - Apply security policies via NeuVector

4. **Set Up Continuous Monitoring**
   - Configure alert notifications in Observability
   - Set up log aggregation
   - Enable automated response actions
   - Create custom monitoring dashboards

---

## Benefits of This Approach

**Using Rancher's kubectl shell instead of SSH:**
- ✅ No need to SSH to individual nodes
- ✅ All operations from Rancher's web UI
- ✅ Cluster-admin access to any managed cluster
- ✅ Easier to copy/paste commands
- ✅ Better logging and history
- ✅ Consistent access method across all clusters

---

## Summary

You have successfully integrated:
- ✅ Three Kubernetes clusters under Rancher Manager (local, observability, security)
- ✅ Complete observability across all clusters via SUSE Observability
- ✅ Centralized cluster management via Rancher
- ✅ Security monitoring via NeuVector on security cluster

**Your SUSE demo environment is now fully operational and integrated!**
