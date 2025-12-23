# SSM Patch Manager Resources

resource "aws_ssm_patch_baseline" "this" {
  name             = "${var.environment}-patch-baseline"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days = 7
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approval_rule {
    approve_after_days = 14
    compliance_level   = "MEDIUM"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Medium", "Low"]
    }
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.this.id
  patch_group = var.environment
}

resource "aws_ssm_maintenance_window" "patch" {
  name              = "${var.environment}-patch-window"
  schedule          = var.patch_schedule
  duration          = 2
  cutoff            = 1
  schedule_timezone = "UTC"

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_maintenance_window_target" "patch" {
  window_id     = aws_ssm_maintenance_window.patch.id
  name          = "${var.environment}-patch-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = [var.environment]
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  window_id        = aws_ssm_maintenance_window.patch.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "1"
  max_errors       = "0"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patch.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }

      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patch.name
        cloudwatch_output_enabled = true
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "patch" {
  name              = "/aws/ssm/${var.environment}/patch-manager"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name = "AmazonCloudWatch-${var.environment}"
  type = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path        = "/var/log/messages"
              log_group_name   = "/aws/ec2/${var.environment}/messages"
              log_stream_name  = "{instance_id}"
            },
            {
              file_path        = "/var/log/secure"
              log_group_name   = "/aws/ec2/${var.environment}/secure"
              log_stream_name  = "{instance_id}"
            }
          ]
        }
      }
    }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = true
        }
        disk = {
          measurement                 = ["used_percent", "inodes_free"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        diskio = {
          measurement                 = ["io_time", "read_bytes", "write_bytes"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        swap = {
          measurement                 = ["swap_used_percent"]
          metrics_collection_interval = 60
        }
        net = {
          measurement                 = ["bytes_sent", "bytes_recv"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
      }
    }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "messages" {
  name              = "/aws/ec2/${var.environment}/messages"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "secure" {
  name              = "/aws/ec2/${var.environment}/secure"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}
