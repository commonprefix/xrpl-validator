# S3 Bucket for wallet.db backups
resource "aws_s3_bucket" "wallet_db" {
  bucket = "${data.aws_caller_identity.current.account_id}-${var.environment}-rippled-wallet-db"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "wallet_db" {
  bucket = aws_s3_bucket.wallet_db.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wallet_db" {
  bucket = aws_s3_bucket.wallet_db.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "wallet_db" {
  bucket = aws_s3_bucket.wallet_db.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
