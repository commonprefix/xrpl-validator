terraform {
  backend "s3" {
    bucket       = "123456789012-tf-state"
    key          = "testnet/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  region             = "us-east-1"
  availability_zones = ["${local.region}a", "${local.region}b"]
}

provider "aws" {
  region = local.region
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/TerraformApply"
  }
}

module "cluster" {
  # If using as git submodule:
  # source = "../../xrpl-validator/terraform/modules/validator-cluster"

  # If using directly from GitHub:
  # source = "github.com/commonprefix/xrpl-validator//terraform/modules/validator-cluster"

  source = "../modules/validator-cluster"

  environment        = "testnet"
  region             = local.region
  availability_zones = local.availability_zones
  vpc_cidr           = "10.0.0.0/16"

  nodes = [
    {
      name              = "testnet-validator"
      instance_type     = "z1d.2xlarge"
      root_volume_size  = 30
      availability_zone = 0
      validator         = true
      secret_name       = "rippled/testnet/secret/validator"
      var_secret_name   = "rippled/testnet/var/validator"
    },
    {
      name              = "testnet-node-1"
      instance_type     = "z1d.large"
      root_volume_size  = 30
      availability_zone = 0
      secret_name       = "rippled/testnet/secret/node-1"
      var_secret_name   = "rippled/testnet/var/node-1"
      ssl_subject = {
        cn = "node-1.example.com"
        o  = "Example Org"
        c  = "US"
      }
    }
  ]

  ansible_role_principals = [
    "arn:aws:iam::123456789012:role/YourAdminRole"
  ]
}
