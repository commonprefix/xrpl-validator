# Domain verification infrastructure for XRPL validator
# Hosts xrp-ledger.toml at https://<domain>/.well-known/xrp-ledger.toml

# Provider for us-east-1 (required for ACM certificates used with CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# S3 bucket to store the TOML file
resource "aws_s3_bucket" "xrpl_toml" {
  bucket = "${data.aws_caller_identity.current.account_id}-${var.environment}-xrpl-toml"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "xrpl_toml" {
  bucket = aws_s3_bucket.xrpl_toml.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "xrpl_toml" {
  bucket = aws_s3_bucket.xrpl_toml.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control for secure S3 access
resource "aws_cloudfront_origin_access_control" "xrpl_toml" {
  name                              = "${var.environment}-xrpl-toml"
  description                       = "OAC for ${var.environment} xrp-ledger.toml"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "xrpl_toml" {
  bucket = aws_s3_bucket.xrpl_toml.id

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
        Resource = "${aws_s3_bucket.xrpl_toml.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.xrpl_toml.arn
          }
        }
      }
    ]
  })
}

# ACM certificate (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "domain" {
  provider          = aws.us_east_1
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.domain.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "domain" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.domain.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Response headers policy for CORS
resource "aws_cloudfront_response_headers_policy" "xrpl_toml" {
  name = "${var.environment}-xrpl-toml-cors"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    origin_override = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "xrpl_toml" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.environment} xrp-ledger.toml"
  aliases         = [var.domain]

  origin {
    domain_name              = aws_s3_bucket.xrpl_toml.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.xrpl_toml.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.xrpl_toml.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.xrpl_toml.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = 0
    default_ttl                = 300  # 5 minutes - short TTL for TOML updates
    max_ttl                    = 3600 # 1 hour
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.xrpl_toml.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.domain.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

# Route 53 A record pointing to CloudFront
resource "aws_route53_record" "domain" {
  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.xrpl_toml.domain_name
    zone_id                = aws_cloudfront_distribution.xrpl_toml.hosted_zone_id
    evaluate_target_health = false
  }
}

# IPv6 AAAA record
resource "aws_route53_record" "domain_ipv6" {
  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.xrpl_toml.domain_name
    zone_id                = aws_cloudfront_distribution.xrpl_toml.hosted_zone_id
    evaluate_target_health = false
  }
}
