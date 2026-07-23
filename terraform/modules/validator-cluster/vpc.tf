module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.1"

  for_each = local.regions

  region = each.key

  name = var.environment
  cidr = each.value.vpc_cidr

  azs            = each.value.availability_zones
  public_subnets = [cidrsubnet(each.value.vpc_cidr, 8, 0), cidrsubnet(each.value.vpc_cidr, 8, 1)]

  enable_nat_gateway   = false
  enable_flow_log      = false
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false

  tags = {
    Environment = var.environment
  }
}

# Migration artifact: both existing stacks (mainnet, testnet) have ap-south-1 as
# their primary region; remove once all stacks have applied the for_each change.
moved {
  from = module.vpc
  to   = module.vpc["ap-south-1"]
}

resource "aws_subnet" "validator" {
  region            = local.validator_region
  vpc_id            = module.vpc[local.validator_region].vpc_id
  cidr_block        = cidrsubnet(local.regions[local.validator_region].vpc_cidr, 8, 20)
  availability_zone = local.regions[local.validator_region].availability_zones[local.validator.availability_zone]

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}

resource "aws_subnet" "node" {
  for_each = { for pair in flatten([
    for r, cfg in local.node_network_regions : [
      for i, az in cfg.availability_zones : {
        key    = "${r}-${i}"
        region = r
        az     = az
        cidr   = cidrsubnet(cfg.vpc_cidr, 8, 10 + i)
      }
    ]
  ]) : pair.key => pair }

  region            = each.value.region
  vpc_id            = module.vpc[each.value.region].vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name        = "${var.environment}-node-${each.value.az}"
    Environment = var.environment
  }
}

resource "aws_eip" "validator_nat" {
  region = local.validator_region
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-validator-nat"
    Environment = var.environment
  }
}

resource "aws_eip" "node_nat" {
  for_each = local.node_network_regions

  region = each.key
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-node-nat"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "validator" {
  region        = local.validator_region
  allocation_id = aws_eip.validator_nat.id
  subnet_id     = module.vpc[local.validator_region].public_subnets[0]

  tags = {
    Name        = "${var.environment}-validator-nat"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "node" {
  for_each = local.node_network_regions

  region        = each.key
  allocation_id = aws_eip.node_nat[each.key].id
  subnet_id     = module.vpc[each.key].public_subnets[1]

  tags = {
    Name        = "${var.environment}-node-nat"
    Environment = var.environment
  }
}

resource "aws_route_table" "validator" {
  region = local.validator_region
  vpc_id = module.vpc[local.validator_region].vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.validator.id
  }

  dynamic "route" {
    for_each = local.peer_region_cidrs[local.validator_region]
    content {
      cidr_block                = route.value
      vpc_peering_connection_id = local.peering_id["${local.validator_region}|${route.key}"]
    }
  }

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}

resource "aws_route_table" "node" {
  for_each = local.node_network_regions

  region = each.key
  vpc_id = module.vpc[each.key].vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.node[each.key].id
  }

  dynamic "route" {
    for_each = local.peer_region_cidrs[each.key]
    content {
      cidr_block                = route.value
      vpc_peering_connection_id = local.peering_id["${each.key}|${route.key}"]
    }
  }

  tags = {
    Name        = "${var.environment}-node"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "validator" {
  region         = local.validator_region
  subnet_id      = aws_subnet.validator.id
  route_table_id = aws_route_table.validator.id
}

resource "aws_route_table_association" "node" {
  for_each = aws_subnet.node

  region         = each.value.region
  subnet_id      = each.value.id
  route_table_id = aws_route_table.node[each.value.region].id
}

# Migration artifacts: both existing stacks are single-region ap-south-1 with 2 AZs;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_subnet.node[0]
  to   = aws_subnet.node["ap-south-1-0"]
}

moved {
  from = aws_subnet.node[1]
  to   = aws_subnet.node["ap-south-1-1"]
}

moved {
  from = aws_eip.node_nat
  to   = aws_eip.node_nat["ap-south-1"]
}

moved {
  from = aws_nat_gateway.node
  to   = aws_nat_gateway.node["ap-south-1"]
}

moved {
  from = aws_route_table.node
  to   = aws_route_table.node["ap-south-1"]
}

moved {
  from = aws_route_table_association.node[0]
  to   = aws_route_table_association.node["ap-south-1-0"]
}

moved {
  from = aws_route_table_association.node[1]
  to   = aws_route_table_association.node["ap-south-1-1"]
}
