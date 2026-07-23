# Ansible IAM Role and S3 Buckets for SSM Sessions

locals {
  ansible_enabled = length(var.ansible_role_principals) > 0
  # SSM-session file-transfer bucket per region (the aws_ssm connection plugin
  # needs a bucket in the instance's region)
  ansible_regions      = local.ansible_enabled ? local.regions : {}
  ansible_region_names = sort(keys(local.ansible_regions))

  ansible_session_resources = flatten([for r in local.ansible_region_names : [
    "arn:aws:ec2:${r}:${data.aws_caller_identity.current.account_id}:instance/*",
    "arn:aws:ssm:${r}::document/AWS-StartSSHSession"
  ]])
  ansible_session_arns = [for r in local.ansible_region_names : "arn:aws:ssm:${r}:${data.aws_caller_identity.current.account_id}:session/*"]
  ansible_bucket_arns  = flatten([for r in local.ansible_region_names : [
    aws_s3_bucket.ansible_ssm[r].arn,
    "${aws_s3_bucket.ansible_ssm[r].arn}/*"
  ]])
}

resource "aws_s3_bucket" "ansible_ssm" {
  for_each = local.ansible_regions

  region = each.key
  # Region as infix: the TerraformApply IAM policy scopes S3 management by the
  # "*-ansible-ssm" suffix, so the purpose suffix must stay last.
  bucket = each.key == var.region ? "${data.aws_caller_identity.current.account_id}-${var.environment}-ansible-ssm" : "${data.aws_caller_identity.current.account_id}-${var.environment}-${each.key}-ansible-ssm"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_ssm" {
  for_each = local.ansible_regions

  region = each.key
  bucket = aws_s3_bucket.ansible_ssm[each.key].id

  rule {
    id     = "expire-ssm-files"
    status = "Enabled"

    expiration {
      days = 1
    }
  }
}

resource "aws_iam_role" "ansible" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  name = "${var.environment}-ansible"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.ansible_role_principals
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "ansible_ec2" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  name = "ec2-inventory"
  role = aws_iam_role.ansible[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeForInventory"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ansible_ssm" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  name = "ssm-session"
  role = aws_iam_role.ansible[0].id

  # Two jsonencode branches so the single-region rendering stays byte-identical
  # (session Resource as a plain string) while multi-region gets a list.
  policy = length(local.ansible_session_arns) == 1 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMStartSession"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus"
        ]
        Resource = local.ansible_session_resources
      },
      {
        Sid    = "SSMSessionResource"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = local.ansible_session_arns[0]
      }
    ]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMStartSession"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus"
        ]
        Resource = local.ansible_session_resources
      },
      {
        Sid    = "SSMSessionResource"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = local.ansible_session_arns
      }
    ]
  })
}

resource "aws_iam_role_policy" "ansible_s3" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  name = "s3-ssm-bucket"
  role = aws_iam_role.ansible[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SSMBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation"
        ]
        Resource = local.ansible_bucket_arns
      }
    ]
  })
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_s3_bucket.ansible_ssm[0]
  to   = aws_s3_bucket.ansible_ssm["ap-south-1"]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.ansible_ssm[0]
  to   = aws_s3_bucket_lifecycle_configuration.ansible_ssm["ap-south-1"]
}
