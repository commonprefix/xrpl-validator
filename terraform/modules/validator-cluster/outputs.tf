output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "nodes" {
  description = "Map of all node instance information"
  value = {
    for name, instance in aws_instance.node : name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      validator   = local.nodes_by_name[name].validator
    }
  }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "ansible_role_arn" {
  description = "ARN of the Ansible IAM role"
  value       = length(aws_iam_role.ansible) > 0 ? aws_iam_role.ansible[0].arn : null
}

output "ansible_ssm_bucket" {
  description = "Name of the S3 bucket for Ansible SSM sessions"
  value       = length(aws_s3_bucket.ansible_ssm) > 0 ? aws_s3_bucket.ansible_ssm[0].id : null
}

output "xrpl_toml_bucket" {
  description = "Name of the S3 bucket for xrp-ledger.toml"
  value       = aws_s3_bucket.xrpl_toml.id
}

output "domain_verification_url" {
  description = "URL to verify domain setup"
  value       = "https://${var.domain}/.well-known/xrp-ledger.toml"
}
