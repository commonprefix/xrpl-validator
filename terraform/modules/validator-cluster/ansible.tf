# Ansible IAM Role and S3 Bucket for SSM Sessions

resource "aws_s3_bucket" "ansible_ssm" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  bucket = "${data.aws_caller_identity.current.account_id}-${var.environment}-ansible-ssm"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_ssm" {
  count = length(var.ansible_role_principals) > 0 ? 1 : 0

  bucket = aws_s3_bucket.ansible_ssm[0].id

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

  policy = jsonencode({
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
        Resource = [
          "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${var.region}::document/AWS-StartSSHSession"
        ]
      },
      {
        Sid    = "SSMSessionResource"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:session/*"
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
        Resource = [
          aws_s3_bucket.ansible_ssm[0].arn,
          "${aws_s3_bucket.ansible_ssm[0].arn}/*"
        ]
      }
    ]
  })
}
