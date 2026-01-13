output "vpc_id" {
  description = "ID of the VPC containing the cluster"
  value       = module.cluster.vpc_id
}

output "nodes" {
  description = "Map of all EC2 instances with their IDs, private IPs, and validator status"
  value       = module.cluster.nodes
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications"
  value       = module.cluster.sns_topic_arn
}

output "ansible_role_arn" {
  description = "ARN of the IAM role to assume when running Ansible"
  value       = module.cluster.ansible_role_arn
}

output "ansible_ssm_bucket" {
  description = "S3 bucket name used for SSM session data"
  value       = module.cluster.ansible_ssm_bucket
}
