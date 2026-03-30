# SUSE Observability - Client Registration - Lab Version

# NOTE: NOTE: NOTE
#   YOU NEED TO UPDATE stackstate.cluster.name to the value you entered when creating the stackpack
```
CLUSTER_NAME=rancher
helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'=$CLUSTER_NAME \
--set-string 'stackstate.url'='https://observability.suse-demo-aws.kubernerdes.com/receiver/stsAgent' \
--set 'nodeAgent.skipKubeletTLSVerify'=true \
--set-string 'global.skipSslValidation'=true \
suse-observability-agent suse-observability/suse-observability-agent
```


## Original/default
The following is what you would see as a default registration string
```
helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update
```
then...
```
helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'='rancher' \
--set-string 'stackstate.url'='https://observability.suse-demo-aws.kubernerdes.com/receiver/stsAgent' \
suse-observability-agent suse-observability/suse-observability-agent

