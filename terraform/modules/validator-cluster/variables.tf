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

variable "regions" {
  description = "Map of region name => network config for that region. Must include var.region (the primary region). When null, a single-region map is built from var.region/var.availability_zones/var.vpc_cidr."
  type = map(object({
    vpc_cidr           = string
    availability_zones = list(string)
    private_node_networking = optional(bool, true) # Create private node subnets + NAT in this region (only needed where private non-validator nodes live)
    patch_schedule          = optional(string, null) # Override var.patch_schedule for this region (stagger windows across regions)
  }))
  default = null
}

variable "nodes" {
  description = "List of node configurations (exactly one must have validator = true)"
  type = list(object({
    name              = string
    instance_type     = string
    root_volume_size  = number
    region            = optional(string, null) # Region the node lives in (must be a key of var.regions); null = var.region
    availability_zone = number # Index into the node's region availability_zones (0, 1, etc.)
    ledger_history    = optional(string, "6000")
    node_size         = optional(string, "medium")
    peers_max         = optional(number, 21)
    validator         = optional(bool, false) # True for the validator node (private, no SSL)
    enable_alarm_actions = optional(bool, null) # Per-node override of var.enable_alarm_actions. A muted (false) node is also excluded from cluster-count/peer-count expectations — it's joining, not joined.
    public            = optional(bool, false) # Public nodes get public IPs and are in public subnets
    secret_name       = string                # Sensitive data (validation_seed, validator_token for validator)
    var_secret_name   = string                # Variable/public data (validation_public_key)
    ssl_subject = optional(object({
      cn = string # Common Name
      o  = string # Organization
      c  = string # Country
    }), null)
    domain         = optional(string, null) # Domain for validator verification (e.g., testnet.validator.xrpl.commonprefix.com)
    hosted_zone_id = optional(string, null) # Route53 hosted zone ID for DNS record (requires domain to be set)
    # Fee voting (validator only). Values in drops. Leave unset to use rippled defaults.
    reference_fee   = optional(string, "")
    account_reserve = optional(string, "")
    owner_reserve   = optional(string, "")
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

  validation {
    condition     = alltrue([for n in var.nodes : n.hosted_zone_id == null || n.domain != null])
    error_message = "hosted_zone_id requires domain to be set."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.domain == null || n.validator == true])
    error_message = "domain can only be set on the validator node."
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

variable "discord_webhook_secret_name" {
  description = "Name of the Secrets Manager secret containing the Discord webhook URL. Secret should have format: {\"webhook_url\": \"https://discord.com/api/webhooks/...\"}"
  type        = string
  default     = null
}

variable "enable_alarm_actions" {
  description = "Enable alarm actions. Set to false for initial deployment before Ansible configures instances, then set to true after."
  type        = bool
  default     = true
}
