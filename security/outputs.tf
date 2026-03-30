output "kubectl_commands" {
  description = "Useful kubectl commands for managing SUSE Security"
  value = <<-EOT
    # Get NeuVector pods status
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip} "sudo kubectl get pods -n neuvector"

    # Get ingress
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip} "sudo kubectl get ingress -n neuvector"

    # Get certificate (if Let's Encrypt enabled)
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip} "sudo kubectl get certificate -n neuvector"

    # View installation logs
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip} "sudo tail -f /var/log/user-data.log"

    # Acquire Default Login/Password
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip} "sudo /usr/local/bin/kubectl get secret --namespace neuvector neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ \"\n\" }}'"
  EOT
}

output "deployment_info" {
  description = "SUSE Security deployment information"
  value = {
    components = {
      neuvector = "Container security and network policies"
      trivy     = "Vulnerability scanning"
      falco     = "Runtime security monitoring"
    }
    instance_type = var.security_instance_type
    storage_size  = "${var.security_root_volume_size}GB"
    kubernetes    = "K3s (lightweight)"
    namespace     = "neuvector"
  }
}

output "instance_id" {
  description = "ID of the Security EC2 instance"
  value       = aws_instance.security.id
}

output "private_ip" {
  description = "Private IP address of Security instance"
  value       = aws_instance.security.private_ip
}

output "public_ip" {
  description = "Public IP address of Security instance"
  value       = var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip
}

output "fqdn" {
  description = "Fully qualified domain name for SUSE Security"
  value       = var.create_route53_record ? local.security_fqdn : null
}

output "neuvector_hostname" {
  description = "Hostname used for NeuVector installation"
  value       = local.security_fqdn
}

output "route53_record" {
  description = "Route53 DNS record (if created)"
  value = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? {
    fqdn    = "${var.hostname_security}.${var.subdomain}.${var.root_domain}"
    zone_id = local.zone_id
    type    = "A"
    value   = var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip
  } : null
}

output "neuvector_url" {
  description = "URL to access NeuVector"
  value       = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "https://${var.hostname_security}.${var.subdomain}.${var.root_domain}" : "https://${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip}"
}

output "trivy_url" {
  description = "URL to access Trivy Server"
  value       = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "http://${var.hostname_security}.${var.subdomain}.${var.root_domain}:8080" : "http://${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip}:8080"
}

output "security_group_id" {
  description = "ID of Security security group"
  value       = aws_security_group.security.id
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = var.ssh_public_key != "" ? "ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip}" : "Use AWS Systems Manager Session Manager to connect"
}
