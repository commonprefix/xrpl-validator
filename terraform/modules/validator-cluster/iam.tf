# IAM Resources

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  all_var_secret_names = [for node in var.nodes : node.var_secret_name]
}

resource "aws_iam_role" "node" {
  for_each = local.nodes_by_name

  name               = each.key # Node names already include environment prefix
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  for_each = local.nodes_by_name

  role       = aws_iam_role.node[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "node_cloudwatch" {
  for_each = local.nodes_by_name

  role       = aws_iam_role.node[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "node_secrets" {
  for_each = local.nodes_by_name

  name = "secrets"
  role = aws_iam_role.node[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWriteOwnSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.secret_name}-*"
        ]
      },
      {
        Sid    = "ReadWriteOwnVarSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.var_secret_name}-*"
        ]
      },
      {
        Sid    = "ReadAllVarSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          for name in local.all_var_secret_names :
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${name}-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "node_wallet_db" {
  for_each = local.nodes_by_name

  name = "wallet-db"
  role = aws_iam_role.node[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WalletDbS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.wallet_db.arn}/${each.value.name}/wallet.db"
        ]
      },
      {
        Sid    = "WalletDbS3ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.wallet_db.arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["${each.value.name}/*"]
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  for_each = local.nodes_by_name

  name = each.key # Node names already include environment prefix
  role = aws_iam_role.node[each.key].name

  tags = {
    Environment = var.environment
  }
}
