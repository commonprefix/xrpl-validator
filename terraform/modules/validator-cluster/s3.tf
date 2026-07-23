# S3 Buckets for wallet.db backups (one per region; bucket names are globally
# unique, so the primary region keeps the legacy name and others get a suffix)
resource "aws_s3_bucket" "wallet_db" {
  for_each = local.regions

  region = each.key
  # Region as infix: the TerraformApply IAM policy scopes S3 management by the
  # "*-rippled-wallet-db" suffix, so the purpose suffix must stay last.
  bucket = each.key == var.region ? "${data.aws_caller_identity.current.account_id}-${var.environment}-rippled-wallet-db" : "${data.aws_caller_identity.current.account_id}-${var.environment}-${each.key}-rippled-wallet-db"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "wallet_db" {
  for_each = local.regions

  region = each.key
  bucket = aws_s3_bucket.wallet_db[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wallet_db" {
  for_each = local.regions

  region = each.key
  bucket = aws_s3_bucket.wallet_db[each.key].id

  rule {
    # Preserve AWS's default SSE-C block (ransomware protection)
    blocked_encryption_types = ["SSE-C"]

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "wallet_db" {
  for_each = local.regions

  region = each.key
  bucket = aws_s3_bucket.wallet_db[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_s3_bucket.wallet_db
  to   = aws_s3_bucket.wallet_db["ap-south-1"]
}

moved {
  from = aws_s3_bucket_versioning.wallet_db
  to   = aws_s3_bucket_versioning.wallet_db["ap-south-1"]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.wallet_db
  to   = aws_s3_bucket_server_side_encryption_configuration.wallet_db["ap-south-1"]
}

moved {
  from = aws_s3_bucket_public_access_block.wallet_db
  to   = aws_s3_bucket_public_access_block.wallet_db["ap-south-1"]
}
