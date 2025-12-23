output "vpc_id" {
  description = "ID of the VPC"
  value       = module.cluster.vpc_id
}

output "nodes" {
  description = "Map of all node instance information (including validator)"
  value       = module.cluster.nodes
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (subscribe PagerDuty/Discord here)"
  value       = module.cluster.sns_topic_arn
}
