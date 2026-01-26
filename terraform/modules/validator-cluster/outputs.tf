output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "nodes" {
  description = "Map of all node instance information (including validator)"
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

output "domain_verification_bucket" {
  description = "Name of the S3 bucket for domain verification files"
  value       = length(aws_s3_bucket.domain_verification) > 0 ? aws_s3_bucket.domain_verification[0].id : null
}

output "domain_verification_cloudfront_domain" {
  description = "CloudFront distribution domain name for domain verification"
  value       = length(aws_cloudfront_distribution.domain_verification) > 0 ? aws_cloudfront_distribution.domain_verification[0].domain_name : null
}
