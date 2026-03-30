output "instance_id" {
  description = "ID of the SUSE Observability EC2 instance"
  value       = aws_instance.observability.id
}

output "private_ip" {
  description = "Private IP address of SUSE Observability instance"
  value       = aws_instance.observability.private_ip
}

output "public_ip" {
  description = "Public IP address of SUSE Observability instance"
  value       = var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip
}

output "suse_observability_url" {
  description = "URL to access SUSE Observability UI"
  value       = "http://${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip}:8080"
}

output "suse_observability_base_url" {
  description = "Configured base URL for SUSE Observability"
  value       = var.suse_observability_base_url
}

output "fqdn" {
  description = "Fully qualified domain name for SUSE Observability"
  value       = var.create_route53_record ? local.observability_fqdn : null
}

output "observability_hostname" {
  description = "Hostname used for SUSE Observability installation"
  value       = local.observability_fqdn
}

output "route53_record" {
  description = "Route53 DNS record (if created)"
  value = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? {
    fqdn    = "${var.hostname_observability}.${var.subdomain}.${var.root_domain}"
    zone_id = local.zone_id
    type    = "A"
    value   = var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip
  } : null
}

output "k3s_kubeconfig_path" {
  description = "Path to K3s kubeconfig file on the instance"
  value       = "/etc/rancher/k3s/k3s.yaml"
}

output "credentials_file_path" {
  description = "Path to SUSE Observability credentials file on the instance"
  value       = "/root/suse-observability-credentials.txt"
}

output "security_group_id" {
  description = "ID of SUSE Observability security group"
  value       = aws_security_group.observability.id
}

output "kubectl_commands" {
  description = "Useful kubectl commands for managing SUSE Observability"
  value = <<-EOT
    # Get pods status
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip} "sudo kubectl get pods -n suse-observability"

    # Get services
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip} "sudo kubectl get svc -n suse-observability"

    # View logs
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip} "sudo kubectl logs -n suse-observability -l app=suse-observability-router --tail=100"

    # Get Default Admin password 
    ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip} "grep passw /var/log/user-data.log"
  EOT
}

output "deployment_info" {
  description = "SUSE Observability deployment information"
  value = {
    sizing_profile = "10-nonha"
    instance_type  = var.observability_instance_type
    storage_size   = "${var.observability_root_volume_size}GB"
    kubernetes     = "K3s (lightweight)"
    namespace      = "suse-observability"
  }
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = var.ssh_public_key != "" ? "ssh -i ~/.ssh/suse-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip}" : "Use AWS Systems Manager Session Manager to connect"
}
