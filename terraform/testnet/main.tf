terraform {
  backend "s3" {
    bucket       = "065810619864-tf-state"
    key          = "testnet/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  region             = "ap-south-1"
  availability_zones = ["${local.region}a", "${local.region}b"]
}

provider "aws" {
  region = local.region
  assume_role {
    role_arn = "arn:aws:iam::065810619864:role/TerraformApply"
  }
}

module "cluster" {
  source = "../modules/validator-cluster"

  environment        = "testnet"
  region             = local.region
  availability_zones = local.availability_zones
  vpc_cidr           = "10.0.0.0/16"

  rippled_log_max_size_mb = 100
  rippled_log_max_files   = 10

  nodes = [
    {
      name              = "testnet-validator"
      instance_type     = "z1d.2xlarge"
      root_volume_size  = 30
      availability_zone = 0
      ledger_history    = "6000"
      validator         = true
      secret_name       = "rippled/testnet/secret/validator"
      var_secret_name   = "rippled/testnet/var/validator"
    },
    {
      name              = "testnet-node-1"
      instance_type     = "z1d.large"
      root_volume_size  = 30
      availability_zone = 0
      ledger_history    = "6000"
      secret_name       = "rippled/testnet/secret/node-1"
      var_secret_name   = "rippled/testnet/var/node-1"
      ssl_subject = {
        cn = "testnet-node-1.xrpl.commonprefix.com"
        o  = "Common Prefix"
        c  = "EE"
      }
    },
    {
      name              = "testnet-node-3"
      instance_type     = "z1d.large"
      root_volume_size  = 30
      availability_zone = 0
      ledger_history    = "6000"
      public            = true
      secret_name       = "rippled/testnet/secret/node-3"
      var_secret_name   = "rippled/testnet/var/node-3"
      ssl_subject = {
        cn = "testnet-node-3.xrpl.commonprefix.com"
        o  = "Common Prefix"
        c  = "EE"
      }
    }
  ]

  alarm_thresholds = {
    ledger_age_seconds  = 20
    node_min_peer_count = 5  # cluster peers + external peers
    disk_used_percent    = 75
    memory_used_percent  = 75
    cpu_used_percent     = 75
  }

  ansible_role_principals = [
    "arn:aws:iam::065810619864:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_AdministratorAccess_643c5b447b2d159e"
  ]
}

output "ansible_role_arn" {
  value = module.cluster.ansible_role_arn
}

output "ansible_ssm_bucket" {
  value = module.cluster.ansible_ssm_bucket
}

