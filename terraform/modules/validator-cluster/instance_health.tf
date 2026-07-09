resource "aws_cloudwatch_event_rule" "ec2_scheduled_change" {
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
  rule      = aws_cloudwatch_event_rule.ec2_scheduled_change.name
  target_id = "${var.environment}-ec2-scheduled-change-sns"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  name        = "${var.environment}-ec2-state-change"
  description = "EC2 instance state-change notifications for cluster nodes"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      "instance-id" = [for n in aws_instance.node : n.id]
    }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "ec2_state_change_to_sns" {
  rule      = aws_cloudwatch_event_rule.ec2_state_change.name
  target_id = "${var.environment}-ec2-state-change-sns"
  arn       = aws_sns_topic.alerts.arn
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid     = "AllowEventBridgePublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid     = "AllowCloudWatchAlarmsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_sns_topic_policy" "alerts_eventbridge" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}
