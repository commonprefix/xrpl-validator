locals {
  nodes_by_name = { for node in var.nodes : node.name => node }

  validator = [for node in var.nodes : node if node.validator][0]

  # Non-validator nodes that count toward cluster expectations (muted nodes excluded)
  node_count = length([for node in var.nodes : node if !node.validator && coalesce(node.enable_alarm_actions, true)])

  # Multi-region: region name => { vpc_cidr, availability_zones }; single-region unless var.regions is set
  regions = var.regions != null ? var.regions : {
    (var.region) = {
      vpc_cidr                = var.vpc_cidr
      availability_zones      = var.availability_zones
      private_node_networking = true
      patch_schedule          = null
      ws_api_cidrs            = []
    }
  }

  # Effective region per node (node.region falls back to the primary region)
  node_region = { for name, node in local.nodes_by_name : name => coalesce(node.region, var.region) }

  validator_region = local.node_region[local.validator.name]

  # Regions that need private node subnets + NAT
  node_network_regions = { for r, cfg in local.regions : r => cfg if cfg.private_node_networking }
}
