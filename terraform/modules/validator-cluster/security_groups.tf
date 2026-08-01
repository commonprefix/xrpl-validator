resource "aws_security_group" "node" {
  for_each = local.regions

  region      = each.key
  name        = "${var.environment}-node"
  description = "Security group for XRPL node servers"
  vpc_id      = module.vpc[each.key].vpc_id

  ingress {
    description = "XRPL peer protocol from internet"
    from_port   = 51235
    to_port     = 51235
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "XRPL peer protocol between nodes"
    from_port   = 51235
    to_port     = 51235
    protocol    = "tcp"
    self        = true
  }

  # Non-admin WebSocket API for approved consumers (e.g. peered VPCs)
  dynamic "ingress" {
    for_each = toset(each.value.ws_api_cidrs)
    content {
      description = "XRPL public WebSocket API (non-admin)"
      from_port   = var.ws_api_port
      to_port     = var.ws_api_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "HTTPS for AWS APIs (SSM, CloudWatch, S3, Secrets Manager) and dnf repos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "XRPL peer protocol to internet"
    from_port   = 51235
    to_port     = 51235
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "XRPL peer protocol between nodes"
    from_port   = 51235
    to_port     = 51235
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name        = "${var.environment}-node"
    Environment = var.environment
  }
}

resource "aws_security_group" "validator" {
  region      = local.validator_region
  name        = "${var.environment}-validator-v2"
  description = "Security group for private XRPL validator"
  vpc_id      = module.vpc[local.validator_region].vpc_id

  # Ingress rules
  ingress {
    description     = "XRPL peer protocol from nodes"
    from_port       = 51235
    to_port         = 51235
    protocol        = "tcp"
    security_groups = [aws_security_group.node[local.validator_region].id]
  }

  # Cross-region cluster nodes can't be referenced by SG over peering — allow by CIDR
  dynamic "ingress" {
    for_each = local.peer_region_cidrs[local.validator_region]
    content {
      description = "XRPL peer protocol from ${ingress.key} nodes"
      from_port   = 51235
      to_port     = 51235
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "egress" {
    for_each = local.peer_region_cidrs[local.validator_region]
    content {
      description = "XRPL peer protocol to ${egress.key} nodes"
      from_port   = 51235
      to_port     = 51235
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }

  egress {
    description = "HTTPS for AWS APIs (SSM, CloudWatch, S3, Secrets Manager) and dnf repos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "XRPL peer protocol to nodes"
    from_port       = 51235
    to_port         = 51235
    protocol        = "tcp"
    security_groups = [aws_security_group.node[local.validator_region].id]
  }

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}

# Migration artifact: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each change.
moved {
  from = aws_security_group.node
  to   = aws_security_group.node["ap-south-1"]
}
