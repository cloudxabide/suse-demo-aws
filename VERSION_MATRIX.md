# Compatibility Matrix

This is not accurate yet (it is a placeholder that will be populated later)

While many parts of my Demo are "latest" and un-versioned, I thought it was a good idea to keep track of what versions all work
together and successfully deploy

| date       | AMI-ID                | OS          | Kubernetes | Rancher | Observability | Security  | cert-manager |
|:-----------|-----------------------|-------------|--------------|---------|---------------|-----------|:-------------|
| 2025-10-14 | ami-0e4ba0f9cbbb667bc | SLES15 SP7  | v1.33.5+k3s1 | 2.12.2  | v2.6.1        | 5.4.6     | 1.15.3       |
| 2025-10-09 | ami-0abcdef123456     | SLES15 SP7  | K3s 1.31     | 2.12.2  | 5.3.0         | 5.4.6     | 1.15.3       |


helpful commands
```
aws ec2 describe-instances --region us-east-2 --query "Reservations[].Instances[].ImageId"
```
