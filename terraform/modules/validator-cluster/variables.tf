variable "environment" {
  description = "Environment name (e.g., testnet, mainnet)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "nodes" {
  description = "List of node configurations (exactly one must have validator = true)"
  type = list(object({
    name              = string
    instance_type     = string
    root_volume_size  = number
    availability_zone = number # Index into var.availability_zones (0, 1, etc.)
    ledger_history    = optional(string, "6000")
    node_size         = optional(string, "medium")
    validator         = optional(bool, false) # True for the validator node (private, no SSL)
    public            = optional(bool, false) # Public nodes get public IPs and are in public subnets
    secret_name       = string                # Sensitive data (validation_seed, validator_token for validator)
    var_secret_name   = string                # Variable/public data (validation_public_key)
    ssl_subject = optional(object({
      cn = string # Common Name
      o  = string # Organization
      c  = string # Country
    }), null)
  }))

  validation {
    condition     = length([for n in var.nodes : n if n.validator == true]) >= 1
    error_message = "At least one node must have validator = true."
  }

  validation {
    condition     = length([for n in var.nodes : n if n.validator == true]) <= 1
    error_message = "Only one node can have validator = true."
  }

  validation {
    condition     = alltrue([for n in var.nodes : !(n.validator == true && n.public == true)])
    error_message = "A validator cannot be public."
  }
}

variable "patch_schedule" {
  description = "Cron expression for patch maintenance window (in UTC)"
  type        = string
  default     = "cron(0 11 ? * MON *)"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "rippled_log_max_size_mb" {
  description = "Maximum size of rippled debug.log before rotation (in MB)"
  type        = number
  default     = 1024
}

variable "rippled_log_max_files" {
  description = "Number of rotated rippled log files to keep"
  type        = number
  default     = 10 # 10 files x 1GB = 10GB max
}

variable "ansible_role_principals" {
  description = "List of IAM ARNs that can assume the Ansible role"
  type        = list(string)
  default     = []
}

variable "alarm_thresholds" {
  description = "Configurable alarm thresholds"
  type = object({
    ledger_age_seconds   = number
    node_min_peer_count  = number
    disk_used_percent      = number
    memory_used_percent    = number
    cpu_used_percent       = number
  })
  default = {
    ledger_age_seconds   = 20
    node_min_peer_count  = 5
    disk_used_percent      = 75
    memory_used_percent    = 75
    cpu_used_percent       = 75
  }
}
