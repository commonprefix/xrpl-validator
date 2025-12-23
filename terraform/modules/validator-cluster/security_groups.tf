resource "aws_security_group" "node" {
  name        = "${var.environment}-node"
  description = "Security group for XRPL node servers"
  vpc_id      = module.vpc.vpc_id

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
  name        = "${var.environment}-validator-v2"
  description = "Security group for private XRPL validator"
  vpc_id      = module.vpc.vpc_id

  # Ingress rules
  ingress {
    description     = "XRPL peer protocol from nodes"
    from_port       = 51235
    to_port         = 51235
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
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
    security_groups = [aws_security_group.node.id]
  }

  tags = {
    Name        = "${var.environment}-validator"
    Environment = var.environment
  }
}
