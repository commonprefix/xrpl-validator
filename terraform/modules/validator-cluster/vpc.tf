module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.environment
  cidr = var.vpc_cidr

  azs            = var.availability_zones
  public_subnets = [cidrsubnet(var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1)]

  enable_nat_gateway   = false
  enable_flow_log      = false
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false

  tags = {
    Environment = var.environment
  }
}

resource "aws_subnet" "validator" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20)
  availability_zone = var.availability_zones[local.validator.availability_zone]

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}

resource "aws_subnet" "node" {
  count = length(var.availability_zones)

  vpc_id            = module.vpc.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.environment}-node-${var.availability_zones[count.index]}"
    Environment = var.environment
  }
}

resource "aws_eip" "validator_nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-validator-nat"
    Environment = var.environment
  }
}

resource "aws_eip" "node_nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-node-nat"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "validator" {
  allocation_id = aws_eip.validator_nat.id
  subnet_id     = module.vpc.public_subnets[0]

  tags = {
    Name        = "${var.environment}-validator-nat"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "node" {
  allocation_id = aws_eip.node_nat.id
  subnet_id     = module.vpc.public_subnets[1]

  tags = {
    Name        = "${var.environment}-node-nat"
    Environment = var.environment
  }
}

resource "aws_route_table" "validator" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.validator.id
  }

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}

resource "aws_route_table" "node" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.node.id
  }

  tags = {
    Name        = "${var.environment}-node"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "validator" {
  subnet_id      = aws_subnet.validator.id
  route_table_id = aws_route_table.validator.id
}

resource "aws_route_table_association" "node" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.node[count.index].id
  route_table_id = aws_route_table.node.id
}
