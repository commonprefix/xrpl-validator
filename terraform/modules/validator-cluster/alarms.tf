locals {
  # Nodes with alarms muted (enable_alarm_actions = false) don't count toward
  # cluster expectations yet — they're joining, not joined.
  active_cluster_size    = length([for n in var.nodes : n if coalesce(n.enable_alarm_actions, true)])
  expected_cluster_count = local.active_cluster_size - 1 # Each node sees N-1 cluster peers

  # Validator miss thresholds (used in alarms and dashboard)
  validator_miss_hourly_threshold = 100
  validator_miss_daily_threshold  = 200
}

resource "aws_sns_topic" "alerts" {
  for_each = local.regions

  region = each.key
  name   = "${var.environment}-rippled-alerts"

  tags = {
    Environment = var.environment
  }
}

resource "aws_sns_topic" "reboot_required" {
  for_each = local.regions

  region = each.key
  name   = "${var.environment}-reboot-required"

  tags = {
    Environment = var.environment
  }
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_sns_topic.alerts
  to   = aws_sns_topic.alerts["ap-south-1"]
}

moved {
  from = aws_sns_topic.reboot_required
  to   = aws_sns_topic.reboot_required["ap-south-1"]
}

resource "aws_cloudwatch_metric_alarm" "server_state" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name      = "${each.key}-server-state"
  actions_enabled = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description = local.nodes_by_name[each.key].validator ? (
    "${each.key} is not in proposing state"
  ) : "${each.key} is not in full state"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "rippled_server_state"
  namespace           = "rippled"
  period              = 60
  statistic           = "Average"
  threshold           = local.nodes_by_name[each.key].validator ? 5 : 4 # proposing vs full
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "ledger_seq" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-no-ledger"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} has no validated ledger"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "rippled_ledger_seq"
  namespace           = "rippled"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "cluster_count" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-cluster-count"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} cluster peer count is less than expected"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "rippled_cluster_count"
  namespace           = "rippled"
  period              = 60
  statistic           = "Average"
  # Validator sees N non-validator nodes, nodes see N-1 other cluster members
  threshold           = local.nodes_by_name[each.key].validator ? local.node_count : local.expected_cluster_count
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "ledger_age" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-ledger-age"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} ledger age is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "rippled_ledger_age"
  namespace           = "rippled"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_thresholds.ledger_age_seconds
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "peer_count" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name      = "${each.key}-peer-count"
  actions_enabled = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description = local.nodes_by_name[each.key].validator ? (
    "${each.key} peer count is less than expected"
  ) : "${each.key} peer count is too low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "rippled_peers"
  namespace           = "rippled"
  period              = 60
  statistic           = "Average"
  # Validator must have at least N non-validator nodes, nodes need minimum peers defined
  threshold = local.nodes_by_name[each.key].validator ? local.node_count : var.alarm_thresholds.node_min_peer_count
  treat_missing_data = "breaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_nvme" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-disk-nvme"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} NVMe disk usage is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_thresholds.disk_used_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value.id
    path       = "/var/lib/rippled"
    device     = "nvme1n1"
    fstype     = "xfs"
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_root" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-disk-root"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} root disk usage is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_thresholds.disk_used_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value.id
    path       = "/"
    device     = "nvme0n1p1"
    fstype     = "xfs"
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-memory"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} memory usage is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_thresholds.memory_used_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-cpu"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} CPU usage is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_thresholds.cpu_used_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts[local.node_region[each.key]].arn]
  ok_actions    = [aws_sns_topic.alerts[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "needs_reboot" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-needs-reboot"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} requires a reboot"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "needs_reboot"
  namespace           = "System"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [aws_sns_topic.reboot_required[local.node_region[each.key]].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  for_each = aws_instance.node

  region = local.node_region[each.key]

  alarm_name          = "${each.key}-instance-status-check"
  actions_enabled     = coalesce(local.nodes_by_name[each.key].enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${each.key} failed instance status check - auto rebooting"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    InstanceId = each.value.id
  }

  alarm_actions = [
    "arn:aws:automate:${local.node_region[each.key]}:ec2:reboot",
    aws_sns_topic.alerts[local.node_region[each.key]].arn
  ]

  tags = {
    Environment = var.environment
  }
}

# Validator miss alarms - only for the validator node
resource "aws_cloudwatch_metric_alarm" "validator_miss_hourly" {
  region              = local.validator_region
  alarm_name          = "${local.validator.name}-validator-miss-hourly"
  actions_enabled     = coalesce(local.validator.enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${local.validator.name} has more than ${local.validator_miss_hourly_threshold} missed validations in the last hour"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "validator_missed_1h"
  namespace           = "rippled"
  period              = 180
  statistic           = "Maximum"
  threshold           = local.validator_miss_hourly_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.node[local.validator.name].id
  }

  alarm_actions = [aws_sns_topic.alerts[local.validator_region].arn]
  ok_actions    = [aws_sns_topic.alerts[local.validator_region].arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "validator_miss_daily" {
  region              = local.validator_region
  alarm_name          = "${local.validator.name}-validator-miss-daily"
  actions_enabled     = coalesce(local.validator.enable_alarm_actions, var.enable_alarm_actions)
  alarm_description   = "${local.validator.name} has more than ${local.validator_miss_daily_threshold} missed validations in the last 24 hours"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "validator_missed_24h"
  namespace           = "rippled"
  period              = 180
  statistic           = "Maximum"
  threshold           = local.validator_miss_daily_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.node[local.validator.name].id
  }

  alarm_actions = [aws_sns_topic.alerts[local.validator_region].arn]
  ok_actions    = [aws_sns_topic.alerts[local.validator_region].arn]

  tags = {
    Environment = var.environment
  }
}
