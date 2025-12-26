# Domain verification infrastructure for XRPL validator
# Hosts xrp-ledger.toml at https://<domain>/.well-known/xrp-ledger.toml

# Provider for us-east-1 (required for ACM certificates used with CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
