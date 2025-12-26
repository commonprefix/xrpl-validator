# EC2 Instances

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "node" {
  for_each = local.nodes_by_name

  ami           = data.aws_ami.amazon_linux.id
  instance_type = each.value.instance_type

  # Validator goes in validator subnet, public nodes in public subnets, private nodes in private subnets
  subnet_id = (
    each.value.validator ? aws_subnet.validator.id :
    each.value.public ? module.vpc.public_subnets[each.value.availability_zone % length(module.vpc.public_subnets)] :
    aws_subnet.node[each.value.availability_zone % length(aws_subnet.node)].id
  )

  # Validator uses validator security group, others use node security group
  vpc_security_group_ids = [each.value.validator ? aws_security_group.validator.id : aws_security_group.node.id]

  iam_instance_profile        = aws_iam_instance_profile.node[each.key].name
  monitoring                  = true
  associate_public_ip_address = each.value.public

  disable_api_termination = true
  disable_api_stop        = true

  root_block_device {
    volume_size = each.value.root_volume_size
    volume_type = "gp3"
  }

  tags = merge(
    {
      Name             = each.value.name
      Environment      = var.environment
      PatchGroup       = var.environment
      Validator        = each.value.validator ? "true" : "false"
      SecretName       = each.value.secret_name
      VarSecretName    = each.value.var_secret_name
      LedgerHistory    = each.value.ledger_history
      NodeSize         = each.value.node_size
      LogMaxSizeMB     = var.rippled_log_max_size_mb
      LogMaxFiles      = var.rippled_log_max_files
      WalletDbS3Bucket = aws_s3_bucket.wallet_db.id
    },
    # SSL tags only for non-validators
    each.value.validator ? {} : {
      SslSubjectCN = each.value.ssl_subject != null ? each.value.ssl_subject.cn : each.value.name
      SslSubjectO  = each.value.ssl_subject != null ? each.value.ssl_subject.o : "XRPL Node"
      SslSubjectC  = each.value.ssl_subject != null ? each.value.ssl_subject.c : "US"
    },
    # Domain verification tags only for validators
    each.value.validator ? {
      XrplTomlBucket = aws_s3_bucket.xrpl_toml.id
      Domain         = var.domain
    } : {}
  )

  lifecycle {
    ignore_changes = [ami]
  }
}
