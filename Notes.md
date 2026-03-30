# Notes

A place for random notes about this project.

## Service and Product Links

[SUSE Rancher Manager](https://rancher.suse-demo-aws.kubernerdes.com/)

[SUSE Observability](https://observability.suse-demo-aws.kubernerdes.com)

[SUSE Security](https://security.suse-demo-aws.kubernerdes.com)

[SUSE MLM](https://mlm.suse-demo-aws.kubernerdes.com) [future]


## AMI for SLES
I opted to have IaC that would allow to simply "pull the latest" image, essentially with no guardrails or guidance.  This ended up with the SLES 15sp7 image, optimized for K8s.  Which seems like it would be fine.  (and, for the most part it is).  

Issues: 
* image is "chost-byos" (Container Host) 
* image contains docker which is installed and enabled

Workaround:
I added commands to disable Docker if/when Docker is present and conflicts (which, at this time is only for the security install)


If you need/want to select a specific AMI, this will help you search
```
 aws ec2 describe-images   --owners 013907871322   --filters "Name=description,Values=*SUSE Linux Enterprise Server 15*"   --query "Images[*].[ImageId,Description,OwnerId]"   --region us-east-1
```

or, look here  
https://pint.suse.com/?resource=images&state=active&csp=amazon

## Let's Encrypt considerations
There are rate limits with LE which are addressed by signifying your certificate as "production" or "staging".  [Let's Encrypt - Rate Limits](https://letsencrypt.org/docs/rate-limits/) - if/when I used the "staging" certificates, I would have connectivity issues and problems with the browser requiring frequent login/re-login.  So, I have opted to test using "production" certificates and I have not hit the rate limits.


