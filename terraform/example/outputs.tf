output "ansible_role_arn" {
  value = module.cluster.ansible_role_arn
}

output "ansible_ssm_bucket" {
  value = module.cluster.ansible_ssm_bucket
}
