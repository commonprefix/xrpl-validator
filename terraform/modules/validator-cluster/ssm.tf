# SSM Patch Manager Resources (per region)

resource "aws_ssm_patch_baseline" "this" {
  for_each = local.regions

  region           = each.key
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
  for_each = local.regions

  region      = each.key
  baseline_id = aws_ssm_patch_baseline.this[each.key].id
  patch_group = var.environment
}

resource "aws_ssm_maintenance_window" "patch" {
  for_each = local.regions

  region            = each.key
  name              = "${var.environment}-patch-window"
  schedule          = coalesce(each.value.patch_schedule, var.patch_schedule)
  duration          = 2
  cutoff            = 1
  schedule_timezone = "UTC"

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_maintenance_window_target" "patch" {
  for_each = local.regions

  region        = each.key
  window_id     = aws_ssm_maintenance_window.patch[each.key].id
  name          = "${var.environment}-patch-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = [var.environment]
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  for_each = local.regions

  region           = each.key
  window_id        = aws_ssm_maintenance_window.patch[each.key].id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "1"
  max_errors       = "0"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patch[each.key].id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["NoReboot"]
      }

      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patch[each.key].name
        cloudwatch_output_enabled = true
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "patch" {
  for_each = local.regions

  region            = each.key
  name              = "/aws/ssm/${var.environment}/patch-manager"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  for_each = local.regions

  region = each.key
  name   = "AmazonCloudWatch-${var.environment}"
  type   = "String"
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
  for_each = local.regions

  region            = each.key
  name              = "/aws/ec2/${var.environment}/messages"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "secure" {
  for_each = local.regions

  region            = each.key
  name              = "/aws/ec2/${var.environment}/secure"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
  }
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_ssm_patch_baseline.this
  to   = aws_ssm_patch_baseline.this["ap-south-1"]
}

moved {
  from = aws_ssm_patch_group.this
  to   = aws_ssm_patch_group.this["ap-south-1"]
}

moved {
  from = aws_ssm_maintenance_window.patch
  to   = aws_ssm_maintenance_window.patch["ap-south-1"]
}

moved {
  from = aws_ssm_maintenance_window_target.patch
  to   = aws_ssm_maintenance_window_target.patch["ap-south-1"]
}

moved {
  from = aws_ssm_maintenance_window_task.patch
  to   = aws_ssm_maintenance_window_task.patch["ap-south-1"]
}

moved {
  from = aws_cloudwatch_log_group.patch
  to   = aws_cloudwatch_log_group.patch["ap-south-1"]
}

moved {
  from = aws_ssm_parameter.cloudwatch_agent_config
  to   = aws_ssm_parameter.cloudwatch_agent_config["ap-south-1"]
}

moved {
  from = aws_cloudwatch_log_group.messages
  to   = aws_cloudwatch_log_group.messages["ap-south-1"]
}

moved {
  from = aws_cloudwatch_log_group.secure
  to   = aws_cloudwatch_log_group.secure["ap-south-1"]
}
