# Inter-region VPC peering: full mesh between all regions.
# Everything here is empty for single-region stacks.

locals {
  region_names = sort(keys(local.regions))

  region_pairs = {
    for p in flatten([
      for i, a in local.region_names : [
        for j, b in local.region_names : { requester = a, accepter = b } if i < j
      ]
    ]) : "${p.requester}|${p.accepter}" => p
  }

  # Peering connection id lookup for either direction ("a|b" and "b|a").
  # References the accepter so dependent routes wait for acceptance.
  peering_id = merge(flatten([
    for key, p in local.region_pairs : [
      { "${p.requester}|${p.accepter}" = aws_vpc_peering_connection_accepter.this[key].vpc_peering_connection_id },
      { "${p.accepter}|${p.requester}" = aws_vpc_peering_connection_accepter.this[key].vpc_peering_connection_id },
    ]
  ])...)

  # For each region, the CIDRs of every other region
  peer_region_cidrs = {
    for r in local.region_names : r => {
      for o in local.region_names : o => local.regions[o].vpc_cidr if o != r
    }
  }
}

resource "aws_vpc_peering_connection" "this" {
  for_each = local.region_pairs

  region      = each.value.requester
  vpc_id      = module.vpc[each.value.requester].vpc_id
  peer_vpc_id = module.vpc[each.value.accepter].vpc_id
  peer_region = each.value.accepter
  auto_accept = false # cross-region peering can never auto-accept from the requester side

  tags = {
    Name        = "${var.environment}-${each.value.requester}-${each.value.accepter}"
    Environment = var.environment
  }
}

resource "aws_vpc_peering_connection_accepter" "this" {
  for_each = local.region_pairs

  region                    = each.value.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id
  auto_accept               = true

  tags = {
    Name        = "${var.environment}-${each.value.requester}-${each.value.accepter}"
    Environment = var.environment
  }
}

# Public route tables: a route to every peered region
resource "aws_route" "public_peering" {
  for_each = merge([
    for r in local.region_names : {
      for o, cidr in local.peer_region_cidrs[r] : "${r}|${o}" => { region = r, cidr = cidr }
    }
  ]...)

  region                    = each.value.region
  route_table_id            = module.vpc[each.value.region].public_route_table_ids[0]
  destination_cidr_block    = each.value.cidr
  vpc_peering_connection_id = local.peering_id[each.key]
}
