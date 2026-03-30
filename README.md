# SUSE Demo Environment - AWS

## Purpose
This repository contains OpenTofu projects to deploy a SUSE demo environment (Rancher Manager, SUSE Observability, SUSE Security) running in AWS.  The infrastructure code here will deploy the core product with fundamental configuration needed.  After that, the demo requires some interactive updates via the WebUI or Kubernetes API.

This demo will have a cost associated with it - as it runs in AWS and I have opted to use SLES.  
I  have published some cost estimates (with AWS Calculator output).  

## Status
This is very much still a work-in-progress at this time (2025 October) but overall should be functional.  

| Project                  | Status |
|:-------------------------|:------:|
| Shared Services          | Done   | 
| **SUSE Rancher Manager** | Done   |
| **SUSE Observability**   | Done   |
| **SUSE Security**        | Done   | 

## Products In-Scope

- **SUSE Rancher Manager** - Kubernetes management platform
- **SUSE Observability** - Monitoring and observability solution
- **SUSE Security** - Security and compliance tools
- **Let's Encrypt** - Certificate Vendor

## Architecture

The demo environment is organized into separate OpenTofu modules:

- **shared-services/** - Common infrastructure (VPC, networking, security groups, etc.)
- **rancher-manager/** - SUSE Rancher Manager deployment
- **observability/** - SUSE Observability deployment
- **security/** - SUSE Security deployment

## Prerequisites

- **OpenTofu >= 1.5.0** - Infrastructure provisioning tool
  - macOS: `brew install opentofu`
  - Other platforms: https://opentofu.org/docs/intro/install/
- **AWS CLI** configured with appropriate credentials (STS will work here)
- **Route53 Domain** - A Top-Level Domain (TLD) hosted by AWS that you own/manage, with permissions to modify records
- **SUSE Customer Center** login and registration for SLES Hosts, you will use: Bring Your Own Subscription (BYOS)

During the deployment you will need to provide or create:
- SSH key pair for EC2 instances
- HostedZoneId for your TLD

## Managed/Automated Deployment

### democtl
Cut right to the chase...

Demo Control / Demo Cuddle / Demo [Cuttle Fish?](https://en.wikipedia.org/wiki/Cuttlefish)... anyhow...

I created Scripts/democtl to manage this demo in a more automated way.  I do recommend that you do the deployment manually a few times to see what is actually happening.  **Then**... knock yerself out with the cuttle command.

Sync this this repo and cd in to it, copy terraform.tfvars.example to terraform.tfvars and update it, then have some fun:

```bash
mkdir -p ~/Developer/Projects; cd $_
# Archive existing demo directory
[ -d "suse-demo-aws" ] && { i=1; while [ -d "suse-demo-aws-$(date +%F)-$(printf '%02d' $i)" ]; do ((i++)); done; mv suse-demo-aws "suse-demo-aws-$(date +%F)-$(printf '%02d' $i)"; }
git clone https://github.com/jradtke-suse/suse-demo-aws.git; cd suse-demo-aws
cp ../terraform.tfvars.example terraform.tfvars
cat terraform.tfvars
Scripts/democtl build

# Display a countdown timer to wait for the cluster to (hopefully) be done building 
countdown_seconds=360
while [ "$countdown_seconds" -ge 0 ]; do
    printf "\rTime remaining: %2d seconds \033[0K" "$countdown_seconds"
    countdown_seconds=$((countdown_seconds - 1))
    sleep 1
done
```

And.. the fun
```
EXAMPLES:
    # Deploy infrastructure
    Scripts/democtl build

    # Display terraform outputs
    Scripts/democtl output

    # Retrieve kubeconfig files
    Scripts/democtl getkube

    # Destroy infrastructure
    Scripts/democtl destroy

    # Show help
    Scripts/democtl help
```

## Manual Steps
If you are more interested in some manual steps, continue reading...

### Deployment Order

Deploy projects in the following order to ensure dependencies are met:

1. **Shared Services** - Deploy first to create common infrastructure (this is the only real dependency)
2. **SUSE Rancher Manager** - Deploy Rancher for Kubernetes management
3. **SUSE Observability** - Deploy monitoring stack
4. **SUSE Security** - Deploy security components

### Quick Start

1. Download Repo and Configure Variables

Note: I store a "hydrated configuraiton" that has all the values populated and just copy it in to my project directory

Copy terraform.tfvars.example to terraform.tfvars then, edit the file with your settings - typically:

* owner
* ssh_public_key
* rancher_instance_type
* route53_zone_id
* letsencrypt_email
* suse_email
* suse_regcode
* suse_observability_license
* suse_observability_admin_password
* neuvector_version

```bash
mkdir -p ~/Developer/Projects; cd $_
# Archive existing demo directory
[ -d "suse-demo-aws" ] && { i=1; while [ -d "suse-demo-aws-$(date +%F)-$(printf '%02d' $i)" ]; do ((i++)); done; mv suse-demo-aws "suse-demo-aws-$(date +%F)-$(printf '%02d' $i)"; }
git clone https://github.com/jradtke-suse/suse-demo-aws.git; cd suse-demo-aws
cp ../terraform.tfvars.example terraform.tfvars 
# Confirm the values have been updated
egrep 'owner|ssh_public_key|rancher_instance_type|route53_zone_id|letsencrypt_email|suse_email|suse_regcode|suse_observability_license|suse_observability_admin_password|neuvector_version' terraform.tfvars 
```

### 2. Deploy Shared Services
NOTE: You cannot cut-and-paste the entire stanza because the "apply" command requires input.
  you can run:  echo "yes" | (command)

```bash
cd shared-services
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
cd -
```

### 3. Deploy SUSE Rancher Manager

```bash
cd rancher-manager
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
cd -
```

### 4. Deploy SUSE Observability

```bash
cd observability
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
cd -
```

### 5. Deploy SUSE Security

```bash
cd security
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
cd -
```

## Configuration

**NEW:** All projects now share a single unified `terraform.tfvars` file at the repository root. This simplifies configuration management and ensures consistency across all modules.

### Key Changes
- **Single Configuration File:** Edit `terraform.tfvars` at the root for all modules
- **Module-Specific Variables:** Instance types and volumes are now prefixed:
  - `rancher_instance_type`, `rancher_root_volume_size`
  - `observability_instance_type`, `observability_root_volume_size`
  - `security_instance_type`, `security_root_volume_size`
- **Common Variables:** Shared variables defined in `common-vars.tf` (symlinked into each module)

### Usage
When running OpenTofu commands, reference the root configuration file:

```bash
cd shared-services
tofu init
tofu plan -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

Apply the same pattern for all modules (rancher-manager, observability, security).

## Cleanup

To destroy all resources, run `tofu destroy` in reverse order:

**Important:** Destroy in reverse order to respect state dependencies. You must type "yes" and hit enter for each module.

Also, if you do not see/recognize the risk in the following commands, I'd probably just run them manually ;-)  (hint: you shouldn't *really* echo "yes" to a command, let alone a command with "destroy" in it.  - you've been warned)

```bash
cd security && echo "yes" | tofu destroy -var-file=../terraform.tfvars; cd - 
cd observability && echo "yes" | tofu destroy -var-file=../terraform.tfvars; cd  -
cd rancher-manager && echo "yes" | tofu destroy -var-file=../terraform.tfvars; cd -
cd shared-services && echo "yes" | tofu destroy -var-file=../terraform.tfvars; cd -
```

## Cost Estimates

This section is a work-in-progress and I will update as I learn more.  
You can *always* utilize: [AWS Calculator](https://calculator.aws/) or [Vantage](https://instances.vantage.sh/) 

![My Cost Estimate](Images/cost-estimate-spreadsheet-10-28.png)

## Notes and Caveats

* This is NOT completely automated.  You will need to proceed with some click-ops, etc.. to connect the different products (i.e. add Rancher Manager to the Observability platform using kubectl/helm).  This is intentional to allow some insight in to how these independent products work together.
* I have intentionally left some of my own (opinionated) values in some of the variables - specifically my own domain_name.  I feel it makes it easier to understand how the variable values are used.  You MUST, however, update with your own values.
* I have created a sub-domain for this demo (suse-demo-aws.kubernerdes.com) and an IAM principal with the appropriate permissions that allows me to create records in that domain.  This is somewhat unique to my own situation as my top-level domain (kubernerdes.com) is owned/managed by another AWS account.  I have delegated this demo domain using [Route53 Multi-Account Delegation](https://github.com/cloudxabide/route53_multi_account_delegation) which is not an official process, but certainly works.
* Everything is in a public subnet (NATGW is not needed).
* While there is a separate directory for each SUSE product, they all rely on the tfstate file in the shared-services directory.  Therefore, do not modify the "shared-services" once it has been deployed, and remove that infrastructure last.
* Similar to the state-file I just mentioned, there is a single terraform.tfvars file in the root/base directory which requires you to reference it when running OpenTofu commands.  I am not positive this was the best approach, but it was the best I could create given the other project design considerations I imposed on myself.

**NOTE:** This is ONLY intended to run as a demo/lab. Trade-offs have been made to minimize cost which make this approach unacceptable for production use-cases.


