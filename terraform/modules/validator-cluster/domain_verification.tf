# Domain verification infrastructure for XRPL validator
# Hosts xrp-ledger.toml at https://<domain>/.well-known/xrp-ledger.toml

locals {
  domain_enabled         = local.validator.domain != null
  hosted_zone_id_enabled = local.validator.hosted_zone_id != null
}

# Provider for us-east-1 (required for ACM certificates used with CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::065810619864:role/TerraformApply"
  }
}

# S3 bucket for hosting verification files
resource "aws_s3_bucket" "domain_verification" {
  count  = local.domain_enabled ? 1 : 0
  bucket = "${var.environment}-xrpl-validator-domain-verification"

  tags = {
    Name        = "${var.environment}-xrpl-validator-domain-verification"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "domain_verification" {
  count  = local.domain_enabled ? 1 : 0
  bucket = aws_s3_bucket.domain_verification[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "domain_verification" {
  count  = local.domain_enabled ? 1 : 0
  bucket = aws_s3_bucket.domain_verification[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "domain_verification" {
  count  = local.domain_enabled ? 1 : 0
  bucket = aws_s3_bucket.domain_verification[0].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3600
  }
}

# Custom 404 error page
resource "aws_s3_object" "error_page" {
  count        = local.domain_enabled ? 1 : 0
  bucket       = aws_s3_bucket.domain_verification[0].id
  key          = "404.html"
  content_type = "text/html; charset=utf-8"
  content      = <<-EOF
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>404 Not Found</title>
      <style>
        body {
          font-family: 'Courier New', monospace;
          background: #faf8f5;
          color: #1a1a1a;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          margin: 0;
        }
        h1 { margin-top: 2rem; font-weight: normal; }
        a { color: #e91e63; text-decoration: none; }
        a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>404 Not Found</h1>
      <p>The requested resource was not found.</p>
      <p><a href="https://commonprefix.com">commonprefix.com</a></p>
    </body>
    </html>
  EOF
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "domain_verification" {
  count                             = local.domain_enabled ? 1 : 0
  name                              = "${var.environment}-xrpl-validator-oac"
  description                       = "OAC for XRPL validator domain verification"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 bucket policy allowing CloudFront access
resource "aws_s3_bucket_policy" "domain_verification" {
  count  = local.domain_enabled ? 1 : 0
  bucket = aws_s3_bucket.domain_verification[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.domain_verification[0].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.domain_verification[0].arn
          }
        }
      }
    ]
  })
}

# ACM certificate (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "domain_verification" {
  count             = local.domain_enabled ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = local.validator.domain
  validation_method = "DNS"

  tags = {
    Name        = "${var.environment}-xrpl-validator-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record for ACM certificate
resource "aws_route53_record" "cert_validation" {
  count   = local.domain_enabled && local.hosted_zone_id_enabled ? 1 : 0
  zone_id = local.validator.hosted_zone_id

  name    = tolist(aws_acm_certificate.domain_verification[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.domain_verification[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.domain_verification[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "domain_verification" {
  count                   = local.domain_enabled && local.hosted_zone_id_enabled ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.domain_verification[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "domain_verification" {
  count   = local.domain_enabled ? 1 : 0
  enabled = true
  comment = "XRPL validator domain verification for ${var.environment}"

  aliases = [local.validator.domain]

  origin {
    domain_name              = aws_s3_bucket.domain_verification[0].bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.domain_verification[0].id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.domain_verification[0].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.domain_verification[0].id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  viewer_certificate {
    acm_certificate_arn            = local.hosted_zone_id_enabled ? aws_acm_certificate_validation.domain_verification[0].certificate_arn : aws_acm_certificate.domain_verification[0].arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.environment}-xrpl-validator-cf"
    Environment = var.environment
  }

  depends_on = [aws_acm_certificate.domain_verification]
}

# Route53 record pointing domain to CloudFront
resource "aws_route53_record" "domain_verification" {
  count   = local.domain_enabled && local.hosted_zone_id_enabled ? 1 : 0
  zone_id = local.validator.hosted_zone_id
  name    = local.validator.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.domain_verification[0].domain_name
    zone_id                = aws_cloudfront_distribution.domain_verification[0].hosted_zone_id
    evaluate_target_health = false
  }
}
