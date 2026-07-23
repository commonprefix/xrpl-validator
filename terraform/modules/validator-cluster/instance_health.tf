resource "aws_cloudwatch_event_rule" "ec2_scheduled_change" {
  for_each = local.regions

  region      = each.key
  name        = "${var.environment}-ec2-scheduled-change"
  description = "AWS Health scheduled changes for EC2 (instance retirement, migration, scheduled stop/reboot, network maintenance)"

  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
    detail = {
      service           = ["EC2"]
      eventTypeCategory = ["scheduledChange"]
    }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "ec2_scheduled_change_to_sns" {
  for_each = local.regions

  region    = each.key
  rule      = aws_cloudwatch_event_rule.ec2_scheduled_change[each.key].name
  target_id = "${var.environment}-ec2-scheduled-change-sns"
  arn       = aws_sns_topic.alerts[each.key].arn
}

# Only in regions that have nodes — EventBridge rejects an empty instance-id filter
locals {
  node_regions = { for r, cfg in local.regions : r => cfg if length([for name in keys(local.nodes_by_name) : name if local.node_region[name] == r]) > 0 }
}

resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  for_each = local.node_regions

  region      = each.key
  name        = "${var.environment}-ec2-state-change"
  description = "EC2 instance state-change notifications for cluster nodes"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      "instance-id" = [for name, n in aws_instance.node : n.id if local.node_region[name] == each.key]
    }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "ec2_state_change_to_sns" {
  for_each = local.node_regions

  region    = each.key
  rule      = aws_cloudwatch_event_rule.ec2_state_change[each.key].name
  target_id = "${var.environment}-ec2-state-change-sns"
  arn       = aws_sns_topic.alerts[each.key].arn
}

data "aws_iam_policy_document" "alerts_topic" {
  for_each = local.regions

  statement {
    sid     = "AllowEventBridgePublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts[each.key].arn]
  }

  statement {
    sid     = "AllowCloudWatchAlarmsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts[each.key].arn]
  }
}

resource "aws_sns_topic_policy" "alerts_eventbridge" {
  for_each = local.regions

  region = each.key
  arn    = aws_sns_topic.alerts[each.key].arn
  policy = data.aws_iam_policy_document.alerts_topic[each.key].json
}

# Migration artifacts: both existing stacks are single-region ap-south-1;
# remove once all stacks have applied the for_each changes.
moved {
  from = aws_cloudwatch_event_rule.ec2_scheduled_change
  to   = aws_cloudwatch_event_rule.ec2_scheduled_change["ap-south-1"]
}

moved {
  from = aws_cloudwatch_event_target.ec2_scheduled_change_to_sns
  to   = aws_cloudwatch_event_target.ec2_scheduled_change_to_sns["ap-south-1"]
}

moved {
  from = aws_cloudwatch_event_rule.ec2_state_change
  to   = aws_cloudwatch_event_rule.ec2_state_change["ap-south-1"]
}

moved {
  from = aws_cloudwatch_event_target.ec2_state_change_to_sns
  to   = aws_cloudwatch_event_target.ec2_state_change_to_sns["ap-south-1"]
}

moved {
  from = aws_sns_topic_policy.alerts_eventbridge
  to   = aws_sns_topic_policy.alerts_eventbridge["ap-south-1"]
}
